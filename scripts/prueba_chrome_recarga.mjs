// Prueba en Chrome REAL de la recarga tras una publicación (src/lib/recarga.tsx), a 390 px (táctil) y 1280 px.
// Simula la publicación: el servidor deja de entregar los módulos que la página carga aparte (404, como GitHub Pages con los nombres viejos).
// · Carga diferida de un componente (lazyConRecarga): recarga UNA vez; si vuelve a fallar, el aviso «Hay una versión nueva…» con su botón, en el lugar del componente.
// · import() suelto (importarConRecarga), promesa que nadie atendió y `lazy` sin envolver (límite de errores general): la misma regla.
// · Sin conexión: no se recarga sola. Un error cualquiera al dibujar: aviso con botón, nunca la pantalla en blanco.
// No usa base ni Edge. Puerto propio de Code B (55991).
// Uso: node scripts/prueba_chrome_recarga.mjs <chrome> <puppeteer-core> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP] = process.argv.slice(2, 4);
if (!PUP) { console.error("Uso: node scripts/prueba_chrome_recarga.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
const CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_recarga"));
mkdirSync(CAP, { recursive: true });
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55991;

// ---------- 1. La página de prueba: el ayudante REAL con cuatro maneras de cargar un módulo aparte ----------
const dir = mkdtempSync(join(tmpdir(), "ui_recarga_"));
writeFileSync(join(dir, "Parte.tsx"), `export function Parte() { return <p data-testid="parte">Minimapa de prueba cargado</p>; }`);
writeFileSync(join(dir, "Otra.tsx"), `export function Otra() { return <p data-testid="otra">Otra parte cargada</p>; }`);
writeFileSync(join(dir, "hoja.ts"), `export const hoja = "hoja de cálculo lista";`);
writeFileSync(join(dir, "suelto.ts"), `export const suelto = "suelto listo";`);
writeFileSync(join(dir, "paquete.tsx"), `
    import React, { lazy, Suspense, useState } from "react"; import { createRoot } from "react-dom/client";
    import ${JSON.stringify(join(raiz, "src/styles/app.css"))};
    import { importarConRecarga, instalarManejadorDeCarga, lazyConRecarga, LimiteDeErrores } from ${JSON.stringify(join(raiz, "src/lib/recarga.tsx"))};
    const Parte = lazyConRecarga(() => import(${JSON.stringify(join(dir, "Parte.tsx"))}).then((m) => ({ default: m.Parte })));
    const SinEnvolver = lazy(() => import(${JSON.stringify(join(dir, "Otra.tsx"))}).then((m) => ({ default: m.Otra })));
    function Rota(): never { throw new Error("falla cualquiera al dibujar"); }
    function Pagina() {
      const [ver, setVer] = useState(""); const [msg, setMsg] = useState("");
      return <div className="tec-pagina" style={{ padding: 16 }}>
        <h1 style={{ fontSize: 22 }}>Formulario de prueba</h1>
        <input id="escrito" aria-label="Lo escrito" style={{ fontSize: 16, minHeight: 44 }} />
        <p><button id="b-parte" onClick={() => setVer("parte")}>Ver el minimapa</button> <button id="b-hoja" onClick={() => importarConRecarga(() => import(${JSON.stringify(join(dir, "hoja.ts"))})).then((m) => setMsg(m.hoja), (e) => setMsg("ERROR: " + e.message))}>Descargar</button>
          {" "}<button id="b-suelto" onClick={() => { void import(${JSON.stringify(join(dir, "suelto.ts"))}).then((m) => setMsg(m.suelto)); }}>Suelto</button>
          {" "}<button id="b-sin" onClick={() => setVer("sin")}>Sin envolver</button> <button id="b-rota" onClick={() => setVer("rota")}>Rota</button></p>
        <p id="msg">{msg}</p>
        <Suspense fallback={<p role="status">Cargando el mapa…</p>}>{ver === "parte" ? <Parte /> : ver === "sin" ? <SinEnvolver /> : ver === "rota" ? <Rota /> : null}</Suspense>
      </div>;
    }
    instalarManejadorDeCarga();
    createRoot(document.getElementById("root")).render(<LimiteDeErrores><Pagina /></LimiteDeErrores>);
    window.__listo = true;`);
await build({
  entryPoints: ["paquete.tsx", "Parte.tsx", "Otra.tsx", "hoja.ts", "suelto.ts"].map((f) => join(dir, f)), nodePaths: [join(raiz, "node_modules")],
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "[name]", chunkNames: "comun-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head>
<body style="height:100%;margin:0"><div id="root" style="height:100%"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor: «publicado» = los módulos aparte (Parte, Otra, hoja, suelto) responden 404 ----------
let publicado = false, cargasDePagina = 0;
const APARTE = /^(Parte|Otra|hoja|suelto)\.js$/;
const TIPOS = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css" };
const servidor = http.createServer((req, res) => {
  const nombre = decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/^\/+/, "") || "index.html";
  if (nombre === "index.html") cargasDePagina++;
  const ruta = join(dir, nombre);
  if ((publicado && APARTE.test(nombre)) || nombre.includes("..") || !existsSync(ruta)) { res.writeHead(404, { "content-type": "text/html" }); res.end("<h1>404</h1>"); return; }
  res.writeHead(200, { "content-type": TIPOS[extname(nombre)] || "application/octet-stream", "cache-control": "no-store" }); res.end(readFileSync(ruta));
});
await new Promise((r) => servidor.listen(PUERTO, "127.0.0.1", r));

// ---------- 3. Chrome ----------
let bien = 0, mal = 0;
const ok = (nombre, cond, detalle = "") => { if (cond) { bien++; console.log(`  ok   ${nombre}`); } else { mal++; console.log(`  FALLA ${nombre}${detalle ? `\n        ${String(detalle).slice(0, 600)}` : ""}`); } };
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const navegador = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--window-size=1400,1000"] });
const errores = [];
async function abrir(ancho) {
  // cada pestaña es una sesión nueva (sessionStorage propio): arranca sin la marca
  const ctx = await navegador.createBrowserContext(); const p = await ctx.newPage();
  await p.setViewport(ancho < 600 ? { width: ancho, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : { width: ancho, height: 900 });
  p.on("pageerror", (e) => errores.push(String(e.message)));
  await p.goto(`http://127.0.0.1:${PUERTO}/index.html`, { waitUntil: "load" }); await p.waitForFunction(() => window.__listo === true);
  return p;
}
const listo = (p) => p.waitForFunction(() => window.__listo === true && !!document.querySelector("#b-parte"), { timeout: 15000 });
const marca = (p) => p.evaluate(() => sessionStorage.getItem("geoportal.recarga.v1"));
const aviso = (p) => p.evaluate(() => { const a = document.querySelector("[data-testid=aviso-recarga]"); if (!a) return null; const b = a.querySelector("button"), r = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
  return { txt: a.querySelector("p").textContent, boton: b.textContent, desactivado: b.disabled, alto: rb.height, dentro: r.left >= 0 && r.right <= window.innerWidth + 0.5 && rb.right <= window.innerWidth + 0.5, fijo: getComputedStyle(a).position === "fixed", rol: a.getAttribute("role") }; });
const VERSION = "Hay una versión nueva del geoportal. Toque para recargar.";
/** Espera a que la página se recargue (una carga más de index.html) y quede lista. */
async function esperarRecarga(p, antes) { const t0 = Date.now(); while (cargasDePagina === antes && Date.now() - t0 < 10000) await pausa(50); await pausa(150); await listo(p); }

for (const ancho of ANCHOS) {
  const A = (s) => `[${ancho}] ${s}`;
  console.log(`\n== ${ancho} px ==`);

  // ===== A. Sin publicación: todo carga como siempre =====
  publicado = false;
  let p = await abrir(ancho);
  await p.click("#b-parte"); await p.waitForSelector("[data-testid=parte]");
  ok(A("A1 sin publicación nueva, el módulo aparte carga y no hay aviso ni marca"), (await aviso(p)) === null && (await marca(p)) === null);
  await p.close();

  // ===== B. Carga diferida de un componente dentro de un formulario =====
  p = await abrir(ancho);
  publicado = true;
  await p.type("#escrito", "fuga en la calle 12"); let n = cargasDePagina;
  await p.click("#b-parte"); await esperarRecarga(p, n);
  ok(A("B1 el módulo no carga tras la publicación: la página se recarga sola UNA vez y deja la marca"), cargasDePagina === n + 1 && /"version":"http[^"]+paquete\.js"/.test(await marca(p) ?? ""), `${cargasDePagina - n} recargas · ${await marca(p)}`);
  ok(A("B2 (para el resumen) lo escrito en un formulario sin borrador se pierde con la recarga"), (await p.$eval("#escrito", (e) => e.value)) === "");
  await p.type("#escrito", "segundo intento"); n = cargasDePagina;
  await p.click("#b-parte"); await p.waitForSelector("[data-testid=aviso-recarga]"); await pausa(1200);
  let a = await aviso(p);
  ok(A("B3 vuelve a fallar: NO se recarga otra vez; aparece «Hay una versión nueva del geoportal. Toque para recargar.» con el botón «Recargar»"), cargasDePagina === n && a.txt === VERSION && a.boton === "Recargar" && !a.desactivado && a.rol === "alert", JSON.stringify(a));
  ok(A("B4 el aviso va en el lugar del minimapa: el formulario sigue ahí con lo escrito; botón de 44 px o más y nada se sale del ancho"), (await p.$eval("#escrito", (e) => e.value)) === "segundo intento" && !a.fijo && a.alto >= 44 && a.dentro
    && await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), JSON.stringify(a));
  await p.screenshot({ path: join(CAP, `despues_aviso_en_formulario_${ancho}.png`) });
  publicado = false; n = cargasDePagina;                      // la versión nueva ya está completa
  await p.click("[data-testid=aviso-recarga] button"); await esperarRecarga(p, n);
  await p.click("#b-parte"); await p.waitForSelector("[data-testid=parte]");
  ok(A("B5 «Recargar» recarga la página y el módulo carga"), cargasDePagina === n + 1 && (await aviso(p)) === null);
  await p.close();

  // ===== C. Sin conexión: no se recarga sola =====
  p = await abrir(ancho); n = cargasDePagina;
  await p.type("#escrito", "sin señal"); await p.setOfflineMode(true);
  await p.click("#b-parte"); await p.waitForSelector("[data-testid=aviso-recarga]"); await pausa(800);
  a = await aviso(p);
  ok(A("C1 sin conexión no se recarga (no se pierde lo escrito): «Sin conexión… Cuando vuelva la señal, toque para recargar», botón apagado y sin marca"), cargasDePagina === n && /^Sin conexión: no se pudo cargar esta parte\. Cuando vuelva la señal, toque para recargar\.$/.test(a.txt) && a.desactivado
    && (await p.$eval("#escrito", (e) => e.value)) === "sin señal" && (await marca(p)) === null, JSON.stringify(a));
  await p.setOfflineMode(false); await p.waitForFunction(() => !document.querySelector("[data-testid=aviso-recarga] button").disabled);
  a = await aviso(p);
  ok(A("C2 al volver la señal el botón se enciende y recarga"), a.txt === VERSION && !a.desactivado && await (async () => { await p.click("[data-testid=aviso-recarga] button"); await esperarRecarga(p, n); return cargasDePagina === n + 1; })());
  await p.close();

  // ===== D. import() suelto de las descargas (importarConRecarga) =====
  p = await abrir(ancho); publicado = true; n = cargasDePagina;
  await p.click("#b-hoja"); await esperarRecarga(p, n);
  ok(A("D1 la hoja de cálculo no carga tras la publicación: recarga una vez"), cargasDePagina === n + 1);
  await p.click("#b-hoja"); await p.waitForFunction(() => /^ERROR/.test(document.querySelector("#msg").textContent)); await pausa(800);
  a = await aviso(p);
  ok(A("D2 vuelve a fallar: sin otra recarga; la descarga dice «Hay una versión nueva del geoportal. Recargue la página y vuelva a intentarlo.» y queda el aviso fijo al pie con el botón"),
    cargasDePagina === n + 1 && (await p.$eval("#msg", (e) => e.textContent)) === "ERROR: Hay una versión nueva del geoportal. Recargue la página y vuelva a intentarlo." && a?.txt === VERSION && a.fijo && a.alto >= 44 && a.dentro, JSON.stringify(a));
  await p.screenshot({ path: join(CAP, `despues_aviso_al_pie_${ancho}.png`) });
  await p.click("#b-hoja"); await pausa(500);
  ok(A("D3 el aviso fijo no se repite"), await p.evaluate(() => document.querySelectorAll("[data-testid=aviso-recarga]").length) === 1);
  await p.close();

  // ===== E. Manejador general: una carga que nadie atendió =====
  p = await abrir(ancho); n = cargasDePagina;
  await p.click("#b-suelto"); await esperarRecarga(p, n);
  ok(A("E1 un import() sin atender que falla: el manejador general recarga una vez"), cargasDePagina === n + 1);
  await p.click("#b-suelto"); await p.waitForSelector("[data-testid=aviso-recarga]"); await pausa(800);
  a = await aviso(p);
  ok(A("E2 vuelve a fallar: el aviso fijo, sin otra recarga"), cargasDePagina === n + 1 && a.txt === VERSION && a.fijo);
  await p.close();

  // ===== F. Límite de errores general: nada deja la pantalla en blanco =====
  p = await abrir(ancho); n = cargasDePagina;
  await p.click("#b-sin"); await esperarRecarga(p, n);
  ok(A("F1 un `lazy` sin envolver que no carga: el límite general recarga una vez"), cargasDePagina === n + 1);
  await p.click("#b-sin"); await p.waitForSelector("[data-testid=aviso-recarga]"); await pausa(800);
  a = await aviso(p);
  ok(A("F2 vuelve a fallar: la pantalla NO queda en blanco; aviso de versión nueva a página completa, con el botón"), cargasDePagina === n + 1 && a.txt === VERSION && !a.fijo && a.alto >= 44 && a.dentro && await p.evaluate(() => document.querySelector("#root").innerText.trim().length > 0), JSON.stringify(a));
  await p.screenshot({ path: join(CAP, `despues_aviso_pagina_${ancho}.png`) });
  await p.close();
  publicado = false;
  p = await abrir(ancho); n = cargasDePagina;
  await p.click("#b-rota"); await p.waitForSelector("[data-testid=aviso-recarga]"); await pausa(800);
  a = await aviso(p);
  ok(A("F3 un error cualquiera al dibujar: «Ocurrió un error en esta pantalla. Toque para recargar.» con el botón; no se recarga sola ni deja marca"), cargasDePagina === n && a.txt === "Ocurrió un error en esta pantalla. Toque para recargar." && a.boton === "Recargar" && (await marca(p)) === null, JSON.stringify(a));
  await p.screenshot({ path: join(CAP, `despues_error_pagina_${ancho}.png`) });
  await p.click("[data-testid=aviso-recarga] button"); await esperarRecarga(p, n);
  ok(A("F4 «Recargar» devuelve la pantalla"), cargasDePagina === n + 1 && (await aviso(p)) === null && !!(await p.$("#escrito")));
  await p.close();
}

await navegador.close(); servidor.close();
console.log(`\n${bien} de ${bien + mal} comprobaciones pasaron${mal ? ` · ${mal} FALLAS` : ""}`);
process.exit(mal ? 1 : 0);
