// Prueba en Chrome REAL del Corte 11 de Técnica fase 1: el inicio de Técnica por modos (Planta, Redes y Supervisión), con tarjetas grandes.
// A 390 px (táctil) y 1280 px, con cuentas sintéticas: operador de planta, operador de redes, supervisor de planta, supervisor de distribución (sin formularios
// de Técnica: mis_formularios responde 403) y administrador.
// · Las Edges corren DE VERDAD en Deno; las RPC de redes van a la base local (como las ve producción: service_role, 30 s y 8 s); lo de planta se simula.
// Uso: node scripts/prueba_chrome_inicio_c11.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c11"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_inicio_c11.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54989, P_EDGE = 54990;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };      // dist: sin formularios de Técnica (403)
const PLANTA5 = ["entrada", "salida", "muestreo", "entrada_quimicos", "uso_quimicos"];
const FORMS = { [EMAILS.adm]: ["mantenimiento", "uso_quimicos", "muestreo", "danos_fallas", "entrada", "entrada_quimicos", "salida"], [EMAILS.planta]: ["entrada", "salida", "muestreo"],
                [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: PLANTA5 };
const NOMBRE = { entrada: "Entrada", salida: "Salida", muestreo: "Muestreo", entrada_quimicos: "Entrada de químicos", uso_quimicos: "Uso de químicos", danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c11_"));
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
// la página imita la app: .app de alto 100 % con la barra de 54 px (como la prueba de los dashboards del §34)
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    // Corte 6c: como las ve producción. Cada RPC entra con el rol de la API (service_role) y los topes de Supabase: statement_timeout 30 s y lock_timeout 8 s.
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: ["entrada", "salida", "muestreo"].includes(c) })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: a.p_formulario, nombre: NOMBRE[a.p_formulario] ?? "Formulario", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7, fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
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
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_quimic/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 300))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
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
const visibilidad = (p, capa) => p.evaluate((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility"), capa);
const dibujados = (p, capa) => p.evaluate((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) ? m.queryRenderedFeatures({ layers: [c] }).length : -1; }, capa);
const esperarDibujo = (p, capa, ms = 60000) => p.waitForFunction((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) && m.queryRenderedFeatures({ layers: [c] }).length > 0; }, { timeout: ms }, capa).then(() => true).catch(() => false);
const marcada = (p, capa) => p.evaluate((c) => document.querySelector(`.geo-panel [data-capa=${c}] input`)?.checked ?? null, capa);
async function abrir(ancho, rol, hash) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(120000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");      // sin evaluar: la página puede estar cerrándose
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${hash ?? ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alGeovisor(p, boton = "Geovisor técnico") {
  await esperarTexto(p, new RegExp(boton.replace(/[()]/g, "\\$&"))); await clicTexto(p, "button", boton); await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
}
/** Lleva el mapa a un punto y toca la pantalla allí (como un dedo). */
async function tocarEn(p, lon, lat, zoom = 17.5) {
  await p.evaluate((lon, lat, z) => { const m = document.querySelector(".geo-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: z }); }, lon, lat, zoom);
  await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); }, { timeout: 60000 }).catch(() => {});
  await new Promise((r) => setTimeout(r, 400));
  const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lon, lat);
  if (await p.evaluate(() => matchMedia("(hover: none)").matches || navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
}

const fuente = (p, s) => p.evaluate((s) => document.querySelector(".geo-mapa").__mapa.getSource(s)?.serialize().data ?? null, s);
let notaCorte = null;      // Corte 7a: la nota de la capa de contratos con la fecha del último corte de la cartera
async function encender(p, capa) {
  await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel");
  if (capa === "contratos") await p.screenshot({ path: join(CAP, `capas_nota_corte_${p.viewport().width}.png`) });
  if (capa === "contratos") notaCorte = await p.evaluate(() => { const e = document.querySelector(".geo-panel [data-corte=contratos]"); return e ? { txt: e.innerText, px: parseFloat(getComputedStyle(e).fontSize), ancho: e.getBoundingClientRect().right <= document.documentElement.clientWidth } : null; });
  await p.evaluate((c) => { const i = document.querySelector(`.geo-panel [data-capa=${c}] input`); if (!i.checked) i.click(); }, capa);
  await clicTexto(p, ".geo-panel button", "✕");
}


const inicio = (p) => p.evaluate(() => ({
  pestanas: [...document.querySelectorAll('[role=tablist][aria-label="Modo de trabajo"] [role=tab]')].map((b) => ({ modo: b.dataset.modo, txt: b.textContent.trim(), sel: b.getAttribute("aria-selected"), fondo: getComputedStyle(b).backgroundColor, alto: b.getBoundingClientRect().height, esBoton: b.tagName === "BUTTON" })),
  modo: document.querySelector("[data-modo-actual]")?.dataset.modoActual ?? null,
  unico: document.querySelector(".tec-modo-unico")?.textContent ?? null,
  tarjetas: [...document.querySelectorAll("[data-tarjeta]")].map((c) => { const r = c.getBoundingClientRect(), e = getComputedStyle(c); return { clave: c.dataset.tarjeta, boton: c.tagName === "BUTTON", alto: r.height, x: Math.round(r.left), y: Math.round(r.top), ancho: r.width,
    borde: e.borderTopStyle, nom: c.querySelector(".tec-tarjeta-nom")?.textContent ?? "", desc: c.querySelector(".tec-tarjeta-desc")?.textContent ?? "", ini: c.querySelector(".tec-tarjeta-ini")?.dataset.ini ?? "",
    colorIni: getComputedStyle(c.querySelector(".tec-tarjeta-ini")).backgroundColor }; }),
  titulo: (() => { const h = document.querySelector(".tec-inicio-tit h1"); return h ? { txt: h.textContent, y: Math.round(h.getBoundingClientRect().top), x: Math.round(h.getBoundingClientRect().left) } : null; })(),
  selY: (() => { const s = document.querySelector(".tec-modos"); return s ? { y: Math.round(s.getBoundingClientRect().top), x: Math.round(s.getBoundingClientRect().left), der: Math.round(s.getBoundingClientRect().right) } : null; })(),
  fondo: getComputedStyle(document.querySelector(".tec-inicio") ?? document.body).backgroundColor,
  hayForm: !!document.querySelector(".tec-volver-barra"),
}));
const modoA = async (p, m) => { await p.evaluate((m) => document.querySelector(`[role=tab][data-modo=${m}]`).click(), m); await p.waitForFunction((m) => document.querySelector("[data-modo-actual]")?.dataset.modoActual === m, {}, m); };
const tocar = (p, clave) => p.evaluate((c) => { const b = document.querySelector(`button[data-tarjeta=${c}]`); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, clave);
const claves = (i) => i.tarjetas.map((t) => t.clave).join(",");
const COLOR = { planta: "rgb(10, 37, 64)", redes: "rgb(15, 61, 43)", supervision: "rgb(30, 90, 168)" };
const pidio = (fn, correo) => rpcs.some((r) => r.fn === fn && r.a.p_solicitante === correo);

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('${EMAILS.op2}', 'asignar_formulario', 'uso_quimicos'), ('${EMAILS.op2}', 'asignar_formulario', 'entrada_quimicos')`);      // 7b

  // ===== A. Operador de planta: solo Planta, sin selector =====
  let p = await abrir(ancho, "op2"); await esperarTexto(p, /Entrada de químicos/);
  let i = await inicio(p);
  ok(`${tag} A1 operador de planta: un solo modo (Planta), SIN selector, con el nombre del modo como título`, i.pestanas.length === 0 && i.modo === "planta" && i.unico === "Planta", JSON.stringify(i.pestanas) + i.unico);
  ok(`${tag} A2 sus 5 tarjetas en orden: Entrada, Salida, Muestreo, Entrada de químicos y Uso de químicos`, claves(i) === PLANTA5.join(","), claves(i));
  ok(`${tag} A3 ningún formulario se abre solo al entrar (no se pidió ninguno)`, !i.hayForm && !rpcs.some((r) => r.fn === "geoportal_tec_obtener_formulario"));
  ok(`${tag} A4 tarjetas grandes: al menos 68 px de alto, con la inicial, el nombre y una línea de descripción; sin desborde`,
     i.tarjetas.every((t) => t.alto >= 68 && t.ini === t.nom.trim().charAt(0) && t.desc.length > 8) && (await sinDesborde(p)), JSON.stringify(i.tarjetas.map((t) => [t.clave, t.alto, t.ini, t.desc])));
  ok(`${tag} A5 (7b) las cinco tarjetas se abren: los dos formularios de químicos ya tienen pantalla (ninguna «Próximamente»)`,
     i.tarjetas.every((t) => t.boton && t.borde === "solid" && !/Próximamente/.test(t.nom)), JSON.stringify(i.tarjetas.map((t) => [t.clave, t.boton, t.borde])));
  ok(`${tag} A6 el color del modo Planta (#0a2540) en la inicial y el fondo #f2f5f8`, i.tarjetas[0].colorIni === COLOR.planta && i.fondo === "rgb(242, 245, 248)", i.tarjetas[0].colorIni + " " + i.fondo);
  await p.screenshot({ path: join(CAP, `operador_planta_${ancho}.png`) });
  await tocar(p, "entrada_quimicos"); await p.waitForSelector(".fq #fq-cantidad");
  ok(`${tag} A7 (7b) «Entrada de químicos» se abre con «Volver» y su nombre`, (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Entrada de químicos");
  await clicTexto(p, ".tec-volver-barra button", "←"); await p.waitForSelector("[data-tarjeta=entrada]");
  await tocar(p, "entrada"); await p.waitForSelector(".tec-volver-barra");
  await p.waitForFunction(() => !/Cargando el formulario/.test(document.body.innerText));
  ok(`${tag} A8 al tocar «Entrada» se abre en su pantalla, con «Volver» arriba y su nombre, y solo entonces se pide el formulario`,
     /Volver/.test(await p.evaluate(() => document.querySelector(".tec-volver").textContent)) && (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Entrada"
     && rpcs.filter((r) => r.fn === "geoportal_tec_obtener_formulario").length === 1 && (await minimo(p, ".tec-volver")) >= 44 && !(await p.$("[data-tarjeta]")));
  await clicTexto(p, ".tec-volver-barra button", "←"); await p.waitForSelector("[data-tarjeta=entrada]");
  ok(`${tag} A9 «Volver» regresa al inicio con las mismas tarjetas`, claves(await inicio(p)) === PLANTA5.join(","));
  ok(`${tag} A10 el operador de planta nunca pidió el geovisor`, !pidio("geoportal_redes_geovisor", EMAILS.op2));
  await p.close();

  // ===== B. Operador de redes =====
  p = await abrir(ancho, "op"); await esperarTexto(p, /Reportar daño o falla/);
  i = await inicio(p);
  ok(`${tag} B1 operador de redes: un solo modo (Redes), sin selector: daño, intervención y el geovisor en solo lectura (tiene la casilla); sin ficha ni dashboards`,
     i.pestanas.length === 0 && i.unico === "Redes" && claves(i) === "danos_fallas,mantenimiento,geovisor" && /solo lectura/.test(i.tarjetas[2].nom), i.unico + " " + claves(i));
  ok(`${tag} B2 el color del modo Redes (#0f3d2b)`, i.tarjetas[0].colorIni === COLOR.redes);
  ok(`${tag} B3 el geovisor no se cargó al entrar (no se pidió su configuración ni hay mapa)`, !pidio("geoportal_redes_geovisor", EMAILS.op) && !(await p.$(".geo-mapa")));
  await tocar(p, "danos_fallas"); await p.waitForSelector(".tec-volver-barra"); await esperarTexto(p, /daño/i);
  ok(`${tag} B4 «Reportar daño o falla» se abre con «Volver» y su nombre`, (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Reportar daño o falla" && (await sinDesborde(p)));
  await clicTexto(p, ".tec-volver-barra button", "←"); await p.waitForSelector("[data-tarjeta=geovisor]");
  await tocar(p, "geovisor"); await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  ok(`${tag} B5 el geovisor carga solo al abrirlo`, pidio("geoportal_redes_geovisor", EMAILS.op));
  await p.close();

  // ===== C. Supervisor de planta =====
  p = await abrir(ancho, "planta"); await esperarTexto(p, /Muestreo/);
  i = await inicio(p);
  ok(`${tag} C1 supervisor de planta: selector con Planta, Redes y Supervisión (botones reales con aria-selected, de 44 px o más), abre en Planta`,
     i.pestanas.map((x) => x.modo).join() === "planta,redes,supervision" && i.pestanas.every((x) => x.esBoton && x.alto >= 44 && (x.sel === "true") === (x.modo === "planta")) && i.modo === "planta", JSON.stringify(i.pestanas));
  ok(`${tag} C2 el modo elegido lleva su color (Planta #0a2540)`, i.pestanas[0].fondo === COLOR.planta);
  await modoA(p, "redes"); i = await inicio(p);
  ok(`${tag} C3 en Redes solo tiene «Ficha de activos» (buscar); no tiene formularios de redes`, claves(i) === "ficha_buscar" && i.pestanas[1].sel === "true" && i.pestanas[1].fondo === COLOR.redes, claves(i));
  await modoA(p, "supervision"); i = await inicio(p);
  ok(`${tag} C4 en Supervisión: Dashboard PTAP y Geovisor técnico; sin Dashboard distribución ni «Ficha de activos (editar)»`, claves(i) === "dashboard_ptap,geovisor" && i.pestanas[2].fondo === COLOR.supervision && i.tarjetas[0].colorIni === COLOR.supervision, claves(i));
  await p.reload(); await p.waitForSelector("[data-tarjeta=dashboard_ptap]");
  ok(`${tag} C5 se recuerda el último modo elegido (Supervisión) al volver a entrar`, (await inicio(p)).modo === "supervision");
  ok(`${tag} C6 hasta aquí no se ha pedido el geovisor`, !pidio("geoportal_redes_geovisor", EMAILS.planta));
  await tocar(p, "dashboard_ptap"); await esperarTexto(p, /Dashboard PTAP[\s\S]*Volver/);
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-tarjeta=dashboard_ptap]");
  ok(`${tag} C7 del Dashboard PTAP se vuelve al inicio, en el mismo modo`, (await inicio(p)).modo === "supervision");
  await p.evaluate(() => { try { localStorage.clear(); } catch { /* */ } });
  await p.close();

  // ===== D. Supervisor de distribución sin formularios de Técnica (mis_formularios: 403) =====
  p = await abrir(ancho, "dist"); await p.waitForSelector("[data-tarjeta=ficha_buscar]");
  i = await inicio(p);
  ok(`${tag} D1 supervisor de distribución (sin formularios de Técnica): entra al mismo inicio, con Redes y Supervisión; no se le abre el dashboard solo`,
     i.pestanas.map((x) => x.modo).join() === "redes,supervision" && i.modo === "redes" && claves(i) === "ficha_buscar" && !(await p.$(".tdash-cab")), JSON.stringify(i.pestanas) + claves(i));
  ok(`${tag} D2 su sesión dice «Supervisor de distribución»`, /Supervisor de distribución/.test(await p.evaluate(() => document.querySelector(".tec-inicio-sesion").textContent)));
  await modoA(p, "supervision"); i = await inicio(p);
  ok(`${tag} D3 en Supervisión: Dashboard distribución, Geovisor técnico y «Ficha de activos (editar)»; sin Dashboard PTAP`, claves(i) === "dashboard_distribucion,geovisor,ficha_editar", claves(i));
  await tocar(p, "dashboard_distribucion"); await esperarTexto(p, /No identificados/);
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-tarjeta=dashboard_distribucion]");
  ok(`${tag} D4 del Dashboard distribución se vuelve al inicio`, (await inicio(p)).modo === "supervision");
  await tocar(p, "ficha_editar"); await esperarTexto(p, /Ficha de activos|Buscar/);
  ok(`${tag} D5 «Ficha de activos (editar)» abre la ficha de activos`, !(await p.$("[data-tarjeta]")));
  await p.evaluate(() => { try { localStorage.clear(); } catch { /* */ } });
  await p.close();

  // ===== E. Administrador: los tres modos =====
  p = await abrir(ancho, "adm"); await esperarTexto(p, /Entrada de químicos/);
  i = await inicio(p);
  ok(`${tag} E1 administrador: los tres modos; en Planta, los 5 formularios de planta en orden (aunque el servidor los mande revueltos)`, i.pestanas.length === 3 && claves(i) === PLANTA5.join(","), claves(i));
  ok(`${tag} E2 ${ancho < 500 ? "en el celular el selector va debajo del título, a todo lo ancho, y las tarjetas en una columna" : "en escritorio el selector va a la derecha del título y las tarjetas en rejilla (varias columnas de 260 px o más, hasta 1.120 px)"}`,
     ancho < 500 ? i.selY.y > i.titulo.y + 20 && new Set(i.tarjetas.map((t) => t.x)).size === 1 && i.tarjetas[0].ancho > 300
                 : Math.abs(i.selY.y - i.titulo.y) < 40 && i.selY.x > i.titulo.x + 300 && new Set(i.tarjetas.map((t) => t.x)).size >= 3 && i.tarjetas.every((t) => t.ancho >= 260)
                   && Math.max(...i.tarjetas.map((t) => t.x + t.ancho)) - Math.min(...i.tarjetas.map((t) => t.x)) <= 1120, JSON.stringify([i.selY, i.titulo, i.tarjetas.map((t) => [t.x, Math.round(t.ancho)])]));
  await p.screenshot({ path: join(CAP, `modo_planta_${ancho}.png`) });
  await modoA(p, "redes"); i = await inicio(p);
  ok(`${tag} E3 Redes: daño o falla, intervención y «Ficha de activos» (buscar)`, claves(i) === "danos_fallas,mantenimiento,ficha_buscar", claves(i));
  await p.screenshot({ path: join(CAP, `modo_redes_${ancho}.png`) });
  await modoA(p, "supervision"); i = await inicio(p);
  ok(`${tag} E4 Supervisión: Dashboard PTAP, Dashboard distribución, Geovisor técnico y «Ficha de activos (editar)»`, claves(i) === "dashboard_ptap,dashboard_distribucion,geovisor,ficha_editar" && (await sinDesborde(p)), claves(i));
  await p.screenshot({ path: join(CAP, `modo_supervision_${ancho}.png`) });
  ok(`${tag} E5 el geovisor no se cargó al entrar ni al cambiar de modo`, !pidio("geoportal_redes_geovisor", EMAILS.adm) && !(await p.$(".geo-mapa")));
  await tocar(p, "geovisor"); await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  ok(`${tag} E6 … y carga al abrirlo`, pidio("geoportal_redes_geovisor", EMAILS.adm));
  await clicTexto(p, ".geo-barra button", "←"); await p.waitForSelector("[data-tarjeta=geovisor]").catch(() => {});
  ok(`${tag} E7 del geovisor se vuelve al inicio, en Supervisión`, (await inicio(p)).modo === "supervision");
  await modoA(p, "redes"); await tocar(p, "mantenimiento"); await p.waitForSelector(".tec-volver-barra");
  ok(`${tag} E8 «Registrar intervención» se abre con «Volver»`, (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Registrar intervención");
  await p.evaluate(() => { try { localStorage.clear(); } catch { /* */ } });
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
