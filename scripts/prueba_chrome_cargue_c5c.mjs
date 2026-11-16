// Prueba en Chrome REAL del Corte 5c de Técnica fase 1: la pantalla del Cargue de capas (Dashboard distribución) y, en el Dashboard PTAP › Puntos,
// el administrador que aprueba lo suyo (§32.1) y «Corregir la ubicación» de un punto verificado (§32.2). A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC de redes y las de puntos (geoportal_tec_punto*) van a la base local REAL
//   (PostGIS de Homebrew con la carga real, la primera carga MUE y el 5c); el resto de planta (formularios, registros) se simula como en el 5b.
// · Los archivos son REALES, armados con ogr2ogr desde los shapefiles de origen (pozos en 9377, acueducto en 4326, GeoPackage con 3 capas, KML, Excel y CSV).
// · Antes de cada ancho, la base se rehace (base_chrome.sh).
// Uso: node scripts/prueba_chrome_cargue_c5c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> <archivos> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE, ARCH] = process.argv.slice(2, 9);
const CAP = resolve(process.argv[9] || join(tmpdir(), "capturas_c5c"));
if (!ARCH) { console.error("Uso: node scripts/prueba_chrome_cargue_c5c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> <archivos> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54985, P_EDGE = 54986;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", sup2: "zt.super2@emdupar.gov.co", op: "zt.oper@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.sup2]: "supervisor", [EMAILS.op]: "operador" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c5c_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head><body><div id="raiz" style="display:flex;flex-direction:column;min-height:100vh"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes y de puntos van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: fn === "geoportal_redes_mvt" ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "", con_campos: true }] } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_catalogo_filtros": return { formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "" }], plantas: [], zonas: ["norte", "sur", "medio"], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7,
      fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, bytes: cuerpo.length });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_puntos_mapa$/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcPlanta(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation"]);
const errores = [];
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = async (p, re, ms = 30000) => {
  try { await p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source); }
  catch { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)} · edge: ${edgeLog.slice(-600)}`); }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate((sel, t, dentro) => { const b = [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const subir = async (p, sel, archivo) => { const el = await p.waitForSelector(sel); await el.uploadFile(join(ARCH, archivo)); };
/** El botón con motivo: abre, escribe y confirma, dentro de un contenedor. */
async function conMotivo(p, dentro, rotulo, motivo) {
  if (!(await clicTexto(p, "button", rotulo, dentro))) throw new Error(`no está el botón «${rotulo}» en ${dentro}`);
  await p.waitForFunction((d) => document.querySelector(d)?.querySelector(".dash-motivo input"), { timeout: 5000 }, dentro);
  await p.evaluate((d, m) => { const el = document.querySelector(d).querySelector(".dash-motivo input"); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, m); el.dispatchEvent(new Event("input", { bubbles: true })); }, dentro, motivo);
  await clicTexto(p, "button", "Confirmar:", dentro);
}
async function abrir(ancho, rol, gps) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(120000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", (m) => { if ((m.type() === "error" || m.type() === "warn") && !/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(m.text())) errores.push(`${ancho} ${rol} consola: ${m.text()}`); });
  if (gps) await p.setGeolocation(gps);
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alCargue(p) {
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Redes de acueducto y alcantarillado/);
  await clicTexto(p, "[role=tab]", "Cargue de capas"); await esperarTexto(p, /capas en 5 grupos/);
}
const capaTxt = (p, c) => p.evaluate((c) => document.querySelector(`[data-testid=capa-${c}]`)?.innerText ?? "", c);
const clicEnCapa = (p, c, t) => clicTexto(p, "button", t, `[data-testid=capa-${c}]`);
const siguiente = (p) => clicTexto(p, ".cg-nav button", "Siguiente");

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`; const movil = ancho < 500;
  rehacer(); rpcs.length = 0;
  const RED = sqlq("select codigo || '|' || diametro_mm from redes.activo_vigente_mat where codigo_anterior = 'Distribucion-8435'").split("|");
  sqlq(`select public.geoportal_redes_ficha_editar('${EMAILS.adm}', '${RED[0]}', '{"diametro_mm": 250}', 'Lo midió la cuadrilla al reparar')`);

  // ===== A. La lista de capas (administrador) =====
  let p = await abrir(ancho, "adm");
  await alCargue(p);
  let t = await texto(p);
  ok(`${tag} A1 el Cargue de capas: 5 grupos; la red de acueducto «Al día» en la versión 1; sumideros «Sin cargar»; PQR y barrios como otras capas`,
     /Acueducto/.test(t) && /Alcantarillado/.test(t) && /Tecnología y pérdidas/.test(t) && /Calidad, PQR y reportes/.test(t) && /Base cartográfica/.test(t)
     && /Al día/.test(await capaTxt(p, "acueducto")) && /Versión 1/.test(await capaTxt(p, "acueducto")) && /Sin cargar/.test(await capaTxt(p, "sumideros"))
     && /PQR técnicas/.test(t) && /Predios y contratos/.test(t), (await capaTxt(p, "acueducto")).slice(0, 200));
  await clicTexto(p, "button", "Por cargar o desactualizadas");
  ok(`${tag} A2 el filtro «Por cargar o desactualizadas» deja las capas sin cargar y quita las que están al día`, !(await p.$("[data-testid=capa-acueducto]")) && !!(await p.$("[data-testid=capa-sumideros]")));
  await clicTexto(p, "button", "Todas");
  ok(`${tag} A3 sin desborde y con botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".cg button")) >= 44, `mínimo ${await minimo(p, ".cg button")}`);
  await p.screenshot({ path: join(CAP, `lista_${ancho}.png`), fullPage: true });

  // ===== B. Sumideros: SHP en zip en EPSG 9377, los 5 pasos y publicar =====
  await clicEnCapa(p, "sumideros", "Cargar versión"); await esperarTexto(p, /Paso 1 de 5/);
  await subir(p, "#cg-archivo", "pozos_9377.zip"); await esperarTexto(p, /9\.146.*elementos/);
  ok(`${tag} B1 paso 1: lee el SHP en zip (9.146 puntos) y muestra sus columnas`, /9\.146.*elementos · SHP en zip/.test(await texto(p)) && /LABEL/.test(await texto(p)));
  await siguiente(p); await esperarTexto(p, /Paso 2 de 5/);
  const llave = await p.evaluate(() => document.querySelector("#cg-llave")?.value);
  ok(`${tag} B2 paso 2: propone una columna única como llave y ofrece «Sin columna llave»`, !!llave && llave !== "(geometria)" && /única en todas las filas/.test(await p.evaluate(() => document.querySelector("#cg-llave").selectedOptions[0].textContent))
     && /Sin columna llave/.test(await texto(p)), llave);
  await p.select("#cg-llave", "LABEL");
  await siguiente(p); await esperarTexto(p, /Paso 3 de 5/);
  ok(`${tag} B3 paso 3: detecta MAGNA-SIRGAS Origen Nacional (EPSG 9377) por el .prj`, (await p.evaluate(() => document.querySelector("#cg-srid").value)) === "9377" && /Detectado: MAGNA-SIRGAS Origen Nacional/.test(await texto(p)));
  await p.screenshot({ path: join(CAP, `paso3_sistema_${ancho}.png`), fullPage: true });
  const lotes0 = rpcs.filter((r) => r.fn === "geoportal_redes_carga_lote").length;
  await clicTexto(p, ".cg-nav button", "Subir y revisar"); await esperarTexto(p, /Paso 4 de 5/, 300000);
  const lotesB = rpcs.filter((r) => r.fn === "geoportal_redes_carga_lote");
  t = await texto(p);
  ok(`${tag} B4 subió en lotes de 200 o menos (por la Edge, cada uno de menos de 512 KB) y el resumen dice 9.146 nuevos, 0 retirados, lista para publicar`,
     lotesB.length - lotes0 === 46 && lotesB.every((r) => r.bytes < 512 * 1024) && /Nuevos\s*9\.146/.test(t) && /Retirados\s*0/.test(t) && /Lista para publicar/.test(t), `${lotesB.length - lotes0} lotes · ${t.match(/Nuevos[\s\S]{0,80}/)?.[0]}`);
  await p.waitForFunction(() => { const m = document.querySelector(".cg-mapa-lienzo")?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["pto"] }).length > 0; }, { timeout: 60000 }).catch(() => {});
  const vistos = await p.evaluate(() => document.querySelector(".cg-mapa-lienzo")?.__mapa?.queryRenderedFeatures({ layers: ["pto"] }).length ?? 0);
  ok(`${tag} B5 la vista previa dibuja la muestra sobre Valledupar (EPSG 9377 → WGS 84 en el servidor) con la caja de todo`, vistos > 50 && /Vista previa: (3\d\d|400) de 9\.146/.test(await texto(p)),
     `${vistos} dibujados · ${(await texto(p)).match(/Vista previa[^\n]*/)?.[0]}`);
  await p.screenshot({ path: join(CAP, `paso4_revisar_${ancho}.png`), fullPage: true });
  await siguiente(p); await esperarTexto(p, /Paso 5 de 5/);
  await clicTexto(p, ".cg-nav button", "Publicar versión");
  ok(`${tag} B6 sin nota no publica`, /Escriba la nota de la versión/.test(await texto(p)));
  await poner(p, "#cg-nota", "Sumideros de prueba desde los pozos en 9377");
  await clicTexto(p, ".cg-nav button", "Publicar versión"); await esperarTexto(p, /versión 1 publicada/, 300000);
  ok(`${tag} B7 publicada: 9.146 nuevos; en la base, la carga quedó con el sistema 9377, la llave LABEL y el archivo en la nota`, /9\.146 nuevos/.test(await texto(p))
     && sqlq("select srid_origen || '|' || columna_llave || '|' || nota from redes.cargas where capa_codigo = 'sumideros'") === "9377|LABEL|pozos_9377.zip"
     && sqlq("select count(*) from redes.activo_vigente_mat where capa_codigo = 'sumideros' and prefijo = 'SUM'") === "9146");
  await clicTexto(p, "button", "Volver a las capas"); await esperarTexto(p, /capas en 5 grupos/);
  await p.waitForFunction(() => /Al día/.test(document.querySelector("[data-testid=capa-sumideros]")?.innerText ?? ""), { timeout: 30000 }).catch(() => {});
  ok(`${tag} B8 de vuelta en la lista, sumideros «Al día», versión 1 con 9.146 vigentes`, /Al día/.test(await capaTxt(p, "sumideros")) && /Versión 1[\s\S]*9\.146\s*vigentes/.test(await capaTxt(p, "sumideros")), await capaTxt(p, "sumideros"));

  // ===== C. Red de acueducto: el choque con la ficha y «Devolver este campo a la capa» =====
  await clicEnCapa(p, "acueducto", "Cargar versión"); await esperarTexto(p, /Paso 1 de 5/);
  await subir(p, "#cg-archivo", "acueducto_4326.zip"); await esperarTexto(p, /10\.578.*elementos/);
  await siguiente(p); await esperarTexto(p, /Paso 2 de 5/);
  ok(`${tag} C1 la red de acueducto se carga siempre con su llave del modelo (ID), sin elegirla`, /se carga siempre con la columna ID/.test(await texto(p)) && !(await p.$("#cg-llave")));
  await siguiente(p); await esperarTexto(p, /Paso 3 de 5/);
  await clicTexto(p, ".cg-nav button", "Subir y revisar"); await esperarTexto(p, /Paso 4 de 5/, 300000);
  await esperarTexto(p, /Choques con la ficha \(1\)/);
  const ch = await p.evaluate((c) => document.querySelector(`[data-testid="choque-${c}-diametro_mm"]`)?.innerText ?? "", RED[0]);
  ok(`${tag} C2 el resumen lista el choque: diámetro de la ficha 250 y el de la capa; nada más cambia`, new RegExp(`${RED[0]} · diámetro \\(mm\\): ficha «250», capa «${RED[1]}»`).test(ch) && /Cambiados\s*0(?![\d.])/.test(await texto(p)) && /Iguales\s*17\.960(?![\d.])/.test(await texto(p)), ch + " · " + (await texto(p)).match(/Nuevos[\s\S]{0,90}/)?.[0]);
  await p.screenshot({ path: join(CAP, `choques_${ancho}.png`), fullPage: true });
  await conMotivo(p, `[data-testid="choque-${RED[0]}-diametro_mm"]`, "Devolver este campo a la capa", "Técnica corrigió el diámetro en el modelo");
  await p.waitForFunction(() => !document.querySelector(".cg-choques") && /Cambiados\s*1(?![\d.])/.test(document.body.innerText), { timeout: 120000 }).catch(() => {});
  ok(`${tag} C3 devuelto: el resumen otra vez, sin el choque y con 1 cambiado; la devolución queda con su motivo`, !(await p.$(".cg-choques")) && /Cambiados\s*1(?![\d.])/.test(await texto(p))
     && sqlq(`select campo || '|' || valor_ficha || '|' || motivo from redes.ficha_campo_devoluciones d join redes.activos a on a.id = d.activo_id where a.codigo = '${RED[0]}'`) === "diametro_mm|250|Técnica corrigió el diámetro en el modelo");
  await siguiente(p); await esperarTexto(p, /Paso 5 de 5/);
  await poner(p, "#cg-nota", "Recarga del modelo con el diámetro corregido");
  await clicTexto(p, ".cg-nav button", "Publicar versión"); await esperarTexto(p, /versión 2 publicada/, 300000);
  ok(`${tag} C4 publicada la versión 2 del acueducto: el tramo vuelve al diámetro de la capa y es el único con versión nueva (1 cambiado, 0 retirados)`,
     sqlq(`select diametro_mm from redes.activo_vigente_mat where codigo = '${RED[0]}'`) === RED[1]
     && sqlq("select e.cambiados || '|' || e.retirados || '|' || e.nuevos from redes.carga_eventos e join redes.cargas c on c.id = e.carga_id where c.capa_codigo = 'acueducto' and e.tipo = 'publicar' order by e.id desc limit 1") === "1|0|0",
     sqlq("select e.cambiados || '|' || e.retirados || '|' || e.nuevos from redes.carga_eventos e join redes.cargas c on c.id = e.carga_id where c.capa_codigo = 'acueducto' and e.tipo = 'publicar' order by e.id desc limit 1"));
  await clicTexto(p, "button", "Volver a las capas"); await esperarTexto(p, /capas en 5 grupos/);

  // ===== D. Captaciones: CSV con X y Y en 3116, sin columna llave (cruce por geometría) =====
  await clicEnCapa(p, "captaciones", "Cargar versión"); await esperarTexto(p, /Paso 1 de 5/);
  await subir(p, "#cg-archivo", "captaciones_3116.csv"); await esperarTexto(p, /3.*elementos · CSV/);
  await siguiente(p); await esperarTexto(p, /Paso 2 de 5/);
  await p.select("#cg-llave", "(geometria)");
  ok(`${tag} D1 «Sin columna llave» explica el cruce por geometría`, /se cruza con el vigente del mismo tipo que esté a 2 m o menos/.test(await texto(p)));
  await siguiente(p); await esperarTexto(p, /Paso 3 de 5/);
  ok(`${tag} D2 las columnas X y Y (ESTE y NORTE) se reconocen y el sistema se propone por el rango (MAGNA Bogotá)`,
     (await p.evaluate(() => [document.querySelector("#cg-x").value, document.querySelector("#cg-y").value, document.querySelector("#cg-srid").value].join("|"))) === "ESTE|NORTE|3116");
  await p.select("#cg-srid", "4326");
  ok(`${tag} D3 si se elige un sistema que no cuadra con las coordenadas, avisa antes de subir`, /parecen de MAGNA-SIRGAS Colombia Bogotá/.test(await texto(p)));
  await p.select("#cg-srid", "3116");
  await clicTexto(p, ".cg-nav button", "Subir y revisar"); await esperarTexto(p, /Paso 4 de 5/, 120000);
  ok(`${tag} D4 el resumen dice el resultado del cruce: 0 encontraron par y 3 entran como nuevos`, /Cruce por geometría \(a 2 m\): 0 elementos encontraron su par vigente y 3 entran como nuevos/.test(await texto(p)));
  await conMotivo(p, ".cg-asistente", "Anular esta carga", "Era una prueba del cruce por geometría");
  await esperarTexto(p, /Se anuló la carga de Captaciones/);
  ok(`${tag} D5 «Anular esta carga» la deja anulada y no cambia nada`, sqlq("select estado from redes.v_cargas_estado where capa_codigo = 'captaciones'") === "anulada"
     && sqlq("select count(*) from redes.activo_vigente_mat where capa_codigo = 'captaciones'") === "0");

  // ===== E. Formatos: KML que la capa no acepta y Excel con latitud y longitud =====
  await clicEnCapa(p, "alc_descargas", "Cargar versión"); await esperarTexto(p, /Paso 1 de 5/);
  await subir(p, "#cg-archivo", "descargas.kml"); await esperarTexto(p, /4.*elementos · KML/);
  ok(`${tag} E1 el KML se lee (4 descargas) y, como esa capa no se carga con KML, no deja seguir`, /no se carga con KML/.test(await texto(p))
     && await p.evaluate(() => [...document.querySelectorAll(".cg-nav button")].find((b) => b.textContent.trim() === "Siguiente")?.disabled === true));
  await clicTexto(p, ".cg-nav button", "Cancelar"); await esperarTexto(p, /capas en 5 grupos/);
  await clicEnCapa(p, "sensores", "Cargar versión"); await esperarTexto(p, /Paso 1 de 5/);
  await subir(p, "#cg-archivo", "pozos_4326.xlsx"); await esperarTexto(p, /9\.146.*elementos · Excel/, 60000);
  await siguiente(p); await esperarTexto(p, /Paso 2 de 5/); await p.select("#cg-llave", "LABEL"); await siguiente(p); await esperarTexto(p, /Paso 3 de 5/);
  ok(`${tag} E2 el Excel (9.146 filas): reconoce lon y lat y propone WGS 84`, (await p.evaluate(() => [document.querySelector("#cg-x").value, document.querySelector("#cg-y").value, document.querySelector("#cg-srid").value].join("|"))) === "lon|lat|4326");
  await clicTexto(p, ".cg-nav button", "Atrás"); await clicTexto(p, ".cg-nav button", "Atrás"); await clicTexto(p, ".cg-nav button", "Cancelar"); await esperarTexto(p, /capas en 5 grupos/);

  // ===== F. Carga masiva: el GeoPackage con 3 capas en 9377 =====
  await clicTexto(p, "button", "Cargar varias capas de un archivo"); await esperarTexto(p, /GeoPackage o zip con varios SHP/);
  await subir(p, "#cg-mas-arch", "alcantarillado_9377.gpkg"); await esperarTexto(p, /9\.064 elementos/);
  const dest = await p.evaluate(() => [...document.querySelectorAll("[data-testid^=masiva-] select[id^=cg-md-]")].map((s) => s.value).join("|"));
  ok(`${tag} F1 reparte las 3 capas del GeoPackage por el nombre (conductos, pozos y descargas) y detecta EPSG 9377 en cada una`, dest === "alc_conductos|alc_pozos|alc_descargas"
     && (await p.evaluate(() => [...document.querySelectorAll("select[id^=cg-ms-]")].every((s) => s.value === "9377"))), dest);
  await p.select("#cg-md-0", "interceptores"); await p.select("#cg-md-1", "sumideros"); await p.select("#cg-md-2", "");
  await p.screenshot({ path: join(CAP, `masiva_${ancho}.png`), fullPage: true });
  await clicTexto(p, ".cg-nav button", "Subir y revisar todas"); await esperarTexto(p, /Publicar las 2 listas/, 600000);
  t = await texto(p);
  ok(`${tag} F2 suben las 2 elegidas: 9.064 nuevos en interceptores y los 9.146 sumideros por su llave (ninguno nuevo, ninguno retirado)`,
     /9\.064 nuevos/.test(t) && /Sumideros[^:]*: 0 nuevos · \d[\d.]* cambiados · 0 retirados/.test(t), t.match(/Interceptores[^\n]*|Sumideros[^\n]*/g)?.join(" · "));
  await poner(p, "#cg-mas-nota", "Carga masiva de prueba desde el GeoPackage");
  await clicTexto(p, ".cg-nav button", "Publicar las 2 listas"); await esperarTexto(p, /Volver a las capas/, 600000);
  await p.waitForFunction(() => (document.body.innerText.match(/Publicada: versión/g) ?? []).length === 2, { timeout: 600000 }).catch(() => {});
  ok(`${tag} F3 publicadas las dos, con la misma marca de carga masiva`, ((await texto(p)).match(/Publicada: versión/g) ?? []).length === 2
     && sqlq("select count(distinct masiva_id) || '|' || count(*) from redes.v_cargas_estado where masiva_id is not null and estado = 'publicada'") === "1|2");
  await clicTexto(p, ".cg-nav button", "Volver a las capas"); await esperarTexto(p, /capas en 5 grupos/);

  // ===== G. Historial y «Volver a la versión anterior» =====
  await clicEnCapa(p, "sumideros", "Historial"); await esperarTexto(p, /Sumideros · Historial/); await esperarTexto(p, /Carga \d+ · versión 2/);
  ok(`${tag} G1 el historial de sumideros: 2 cargas publicadas, la masiva marcada, con su nota y su sistema`, /carga masiva/.test(await texto(p)) && ((await texto(p)).match(/Publicada:/g) ?? []).length === 2
     && /MAGNA-SIRGAS Origen Nacional/.test(await texto(p)));
  await conMotivo(p, ".cg-revertir", "Volver a la versión anterior", "La carga masiva era de prueba");
  await esperarTexto(p, /Revertida/);
  ok(`${tag} G2 volver a la versión anterior: la carga masiva de sumideros queda revertida y la versión 1 vuelve a contar`, sqlq("select estado from redes.v_cargas_estado where capa_codigo = 'sumideros' order by id desc limit 1") === "revertida"
     && sqlq("select count(*) from redes.activo_vigente_mat m join redes.cargas c on c.id = m.carga_id where m.capa_codigo = 'sumideros' and c.masiva_id is null") === "9146");
  ok(`${tag} G3 sin desborde en el historial`, await sinDesborde(p));
  await p.close();

  // ===== H. El supervisor de distribución: solo lectura =====
  p = await abrir(ancho, "dist");
  await alCargue(p);
  t = await texto(p);
  ok(`${tag} H1 el supervisor de distribución ve el Cargue en solo lectura: sin «Cargar versión» ni carga masiva, con el historial`, /solo lectura/.test(t) && !/Cargar versión/.test(t)
     && !/Cargar varias capas de un archivo/.test(t) && /Historial/.test(await capaTxt(p, "sumideros")));
  await p.close();

  // ===== I. Dashboard PTAP › Puntos: el administrador aprueba lo suyo (§32.1) y corregir una verificada (§32.2) =====
  const u05 = sqlq("select u.lat || '|' || u.lon from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-05'").split("|").map(Number);
  sqlq(`select public.geoportal_tec_punto_ubicacion_proponer('${EMAILS.adm}', 'MUE-05', ${u05[0] + 0.0003}, ${u05[1]}, 5)`);
  sqlq(`select public.geoportal_tec_punto_ubicacion_proponer('${EMAILS.sup}', 'MUE-06', ${Number(sqlq("select u.lat from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-06'")) + 0.0003}, ${sqlq("select u.lon from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-06'")}, 5)`);
  const u11 = sqlq("select u.lat || '|' || u.lon from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-11'").split("|").map(Number);
  p = await abrir(ancho, "adm", { latitude: u11[0] + 0.0002, longitude: u11[1], accuracy: 6 });
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Secciones|Registros/);
  await clicTexto(p, ".tdash-tab", "Puntos"); await esperarTexto(p, /Ubicaciones por revisar \(2\)/);
  const t5 = await p.evaluate(() => document.querySelector("[data-testid=pendiente-MUE-05]")?.innerText ?? "");
  ok(`${tag} I1 la que tomó el administrador dice que puede revisarla y tiene «Aprobar»`, /Como administrador, puede revisarla/.test(t5) && /Aprobar/.test(t5), t5);
  await clicTexto(p, "button", "Aprobar", "[data-testid=pendiente-MUE-05]"); await clicTexto(p, "button", "Confirmar la aprobación", "[data-testid=pendiente-MUE-05]");
  await esperarTexto(p, /Se aprobó la ubicación de MUE-05/);
  ok(`${tag} I2 el administrador aprueba la suya: MUE-05 queda verificada (GPS del operador), con él como autor`,
     sqlq("select u.exactitud || '|' || u.fuente || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-05'") === `verificada|gps_operador|${EMAILS.adm}`);
  await p.select("#pto-cor-punto", "MUE-11");
  await p.waitForFunction(() => { const m = document.querySelector("[data-testid=corregir] .mue-mapa")?.__mapa; return m && m.loaded(); }, { timeout: 30000 });
  const px = await p.evaluate((lat, lon) => { const el = document.querySelector("[data-testid=corregir] .mue-mapa"); el.scrollIntoView({ block: "center" }); const m = el.__mapa; const r = el.getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, u11[0] + 0.0004, u11[1] + 0.0004);
  if (movil) await p.touchscreen.tap(px.x, px.y); else await p.mouse.click(px.x, px.y);
  await esperarTexto(p, /Nueva: .* \(en el mapa\) · a \d+ m de la de ahora/);
  ok(`${tag} I3 tocar el mapa marca la ubicación nueva (morada) y dice a cuántos metros queda (~60 m)`, /a (5\d|6\d) m de la de ahora/.test(await texto(p)), (await texto(p)).match(/Nueva:[^\n]*/)?.[0]);
  await clicTexto(p, "button", "Guardar la corrección", "[data-testid=corregir]");
  ok(`${tag} I4 sin motivo no guarda`, /Escriba el motivo de la corrección/.test(await texto(p)));
  await clicTexto(p, "button", "Usar la ubicación de este equipo", "[data-testid=corregir]"); await esperarTexto(p, /Ubicación tomada con una precisión de 6 m/);
  ok(`${tag} I5 con el GPS del equipo (6 m) la nueva pasa a ser la del GPS`, /\(con el GPS\) · a 2\d m de la de ahora/.test(await texto(p)), (await texto(p)).match(/Nueva:[^\n]*/)?.[0]);
  await poner(p, "#pto-cor-mot", "La ubicación de David estaba en la otra esquina");
  await clicTexto(p, "button", "Guardar la corrección", "[data-testid=corregir]"); await esperarTexto(p, /Se corrigió la ubicación de MUE-11/); await esperarTexto(p, /Últimas correcciones/);
  ok(`${tag} I6 corregida: MUE-11 verificada, fuente «correccion», del administrador; la anterior (de David) queda en el historial; sale en «Últimas correcciones»`,
     sqlq("select u.exactitud || '|' || u.fuente || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-11'") === `verificada|correccion|${EMAILS.adm}`
     && sqlq("select count(*) from tecnica.puntos_ubicacion u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-11' and u.fuente = 'david'") === "1"
     && /Últimas correcciones/.test(await texto(p)) && /La ubicación de David estaba en la otra esquina/.test(await texto(p)));
  ok(`${tag} I7 sin desborde en «Puntos» y botones de 44 px o más en la corrección`, (await sinDesborde(p)) && (await minimo(p, "[data-testid=corregir] button")) >= 44);
  await p.screenshot({ path: join(CAP, `puntos_corregir_${ancho}.png`), fullPage: true });
  await p.close();
  p = await abrir(ancho, "sup");
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Secciones|Registros/);
  await clicTexto(p, ".tdash-tab", "Puntos"); await esperarTexto(p, /Ubicaciones por revisar \(1\)/);
  const t6 = await p.evaluate(() => document.querySelector("[data-testid=pendiente-MUE-06]")?.innerText ?? "");
  ok(`${tag} I8 el supervisor de planta sigue sin poder revisar la suya`, /la tomó usted: la revisa otro supervisor/.test(t6) && !/Aprobar|Rechazar/.test(t6), t6);
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
