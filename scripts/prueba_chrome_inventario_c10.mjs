// Prueba en Chrome REAL del Corte 10 de Técnica fase 1 (inventario regulatorio), a 390 px (táctil) y 1280 px:
// · El administrador abre Dashboard distribución › Inventario regulatorio: la valoración (propuesta) con sus tres hojas y totales, la conciliación por fila con la red,
//   las filas sin activos, los activos sin fila y la descarga en Excel; desde una fila puntual abre la ficha del activo.
// · La ficha del activo trae «Inventario regulatorio» para el administrador y el supervisor de distribución; el operador no la recibe (sin términos tarifarios).
// · El geovisor, con colores por edad: la leyenda dice «fecha regulatoria, no de instalación» y la tarjeta del tramo también; el operador sigue viendo «sin fecha».
// Las Edges corren DE VERDAD en Deno; las RPC van a la base de Code B (producción hoy + el 10 + la valoración real cargada) con el rol de la API (service_role) y
// los topes de producción (30 s y 8 s). Puertos y base propios de Code B.
// Uso: node scripts/prueba_chrome_inventario_c10.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
//   ANTES=1 RAIZ_UI=<árbol de main>: solo toma las capturas de «antes» (ficha, geovisor por edad y Dashboard distribución) con la página de main.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c10"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_inventario_c10.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_10t> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55993, P_EDGE = 55994;      // puertos de Code B (los de Code A son 5498x)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
// cada ancho arranca de una copia limpia de la plantilla (producción hoy + 10 + valoración cargada), en el clúster de Code B
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
rehacer();

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c10_"));
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
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7, fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
    // Corte 12 (Code A): el inicio pide los avisos; esta base no tiene el 12, así que se responde «sin avisos»
    case "geoportal_tec_avisos": return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
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
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
const texto = (p) => p.evaluate(() => document.body.innerText);
// ---- Corte 11: el inicio de Técnica va por modos (Planta, Redes y Supervisión). Ayudantes de Code A: buscan en cada modo.
const TABS_MODO = '[role=tablist][aria-label="Modo de trabajo"] [role=tab]';
const esperarTexto = async (p, re, ms = 30000) => {
  const fin = Date.now() + ms;
  for (;;) {
    const esta = await p.evaluate(async (s, sel) => {
      const r = new RegExp(s); if (r.test(document.body.innerText)) return true;
      if (!document.querySelector("[data-modo-actual]")) return false;
      for (const t of document.querySelectorAll(sel)) { t.click(); await new Promise((x) => setTimeout(x, 0)); if (r.test(document.body.innerText)) return true; }
      return false; }, re.source, TABS_MODO).catch(() => false);
    if (esta) return;
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)} · errores: ${errores.join(" | ").slice(0, 800)}`); }
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
const textoInicio = (p) => p.evaluate(async (sel) => {
  const tabs = [...document.querySelectorAll(sel)]; if (!tabs.length) return document.body.innerText;
  let s = ""; for (const t of tabs) { t.click(); await new Promise((x) => setTimeout(x, 0)); s += document.body.innerText + "\n"; }
  tabs[0].click(); await new Promise((x) => setTimeout(x, 0)); return s; }, TABS_MODO);
const abrirFormulario = async (p, nombre) => { await esperarTexto(p, new RegExp(nombre)); if (!(await clicTexto(p, "button.tec-tarjeta-modo", nombre))) throw new Error("no está la tarjeta " + nombre); await p.waitForSelector(".tec-volver-barra"); };
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const visibilidad = (p, capa) => p.evaluate((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility"), capa);
const dibujados = (p, capa) => p.evaluate((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) ? m.queryRenderedFeatures({ layers: [c] }).length : -1; }, capa);
const esperarDibujo = (p, capa, ms = 60000) => p.waitForFunction((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) && m.queryRenderedFeatures({ layers: [c] }).length > 0; }, { timeout: ms }, capa).then(() => true).catch(() => false);
const marcada = (p, capa) => p.evaluate((c) => document.querySelector(`.geo-panel [data-capa=${c}] input`)?.checked ?? null, capa);
async function abrir(ancho, rol, hash, gps) {
  const p = await nav.newPage();
  if (gps) await p.setGeolocation({ latitude: gps[1], longitude: gps[0], accuracy: 6 }); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
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


// ---------- 5. Ayudantes (los del 9a-bis) ----------
const tarjeta = (p, c) => p.evaluate((c) => [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((s) => s.innerText.includes(c)).pop()?.innerText ?? "", c);
const enTarjeta = async (p, c, sel, t) => { if (!(await enTarjeta0(p, c, sel, t))) throw new Error(`no hay «${t}» en la tarjeta de «${c}»: ${(await tarjeta(p, c)).slice(0, 500)}`); return true; };
const enTarjeta0 = (p, c, sel, t) => p.evaluate((c, sel, t) => { const s = [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((x) => x.innerText.includes(c)).pop(); if (!s) return false;
  s.scrollIntoView({ block: "center" }); const b = [...s.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.click(); return true; }, c, sel, t);
const pestana = async (p, n) => { if (!(await clicTexto(p, "[role=tab]", n))) throw new Error(`no está la pestaña ${n}`); };
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
async function panelCapas(p) { await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel"); }
async function cerrarPanel(p) { await clicTexto(p, ".geo-panel button", "✕"); await p.waitForFunction(() => !document.querySelector(".geo-panel")); }
async function encender(p, capa, si = true) {
  await panelCapas(p);
  await p.evaluate((c, si) => { const i = document.querySelector(`.geo-panel [data-capa=${c}] input`); i.scrollIntoView({ block: "center" }); if (i.checked !== si) i.click(); }, capa, si);
  await cerrarPanel(p);
}
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? { capa: t.dataset.capa, txt: t.innerText, puntos: Number(t.querySelector(".geo-grafica svg")?.dataset.puntos ?? 0),
  botones: [...t.querySelectorAll("button")].map((b) => b.textContent.trim()), dentro: t.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 } : null; });
async function esperarTarjeta(p, capa, re) {
  await p.waitForFunction((capa, s) => { const t = document.querySelector(".geo-tarjeta"); return t && t.dataset.capa === capa && new RegExp(s).test(t.innerText); }, { timeout: 30000 }, capa, re.source).catch(() => {});
  return tarjetaGeo(p);
}
async function alDashboard(ancho, rol) {
  const p = await abrir(ancho, rol, null);
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Dashboard distribución[\s\S]*No identificados/);
  return p;
}
// antes de tocar el mapa se cierra la tarjeta abierta: a 390 px tapa el centro del mapa, y el toque caería sobre ella
async function tocar(p, lon, lat, zoom) {
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  await tocarEn(p, lon, lat, zoom);
}
const coord = (q) => sqlq(q).split("|").map(Number);
const tiempos = [];


// ---------- 6. Corte 10 ----------
const ANTES = process.env.ANTES === "1";
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
// un tramo de acueducto en operación, largo y amarrado a una fila (o, en «antes», cualquiera): se toca en su punto medio
const TR = sqlq(`select m.codigo || '|' || ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.5)) || '|' || ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.5))
  from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.estado_codigo = 'en_operacion' and not m.retirado and m.longitud_m between 120 and 200 and m.fecha_instalacion is null
   and m.diametro_mm >= 150 ${ANTES ? "" : "and exists (select 1 from redes.val_amarre am where am.activo_id = m.activo_id and am.situacion = 'con_fila')"} order by m.activo_id limit 1`).split("|");
const [TRAMO, TLON, TLAT] = [TR[0], Number(TR[1]), Number(TR[2])];
const SIVA = ANTES ? "" : sqlq("select a.codigo from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.situacion = 'aparte_siva' order by a.id limit 1");
const seccionReg = (p) => p.evaluate(() => document.querySelector("[data-testid=ficha-regulatorio]")?.innerText ?? null);
async function porEdad(p) { await clicTexto(p, ".geo-seg button", "Edad"); await p.waitForSelector('.geo-leyenda[aria-label="Colores por edad"]'); return p.evaluate(() => document.querySelector('.geo-leyenda[aria-label="Colores por edad"]').innerText); }
async function tarjetaTramo(p) {
  await encender(p, "acu_nodos", false); await encender(p, "sectores", false);
  await tocar(p, TLON, TLAT, 18);
  return esperarTarjeta(p, "activo", /Edad/);
}

for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  let p, t, tj, s;
  if (ANTES) {      // solo capturas con la página de main (antes del Corte 10)
    p = await alDashboard(ancho, "adm"); await p.screenshot({ path: join(CAP, `antes_dashboard_${ancho}.png`), fullPage: true }); await p.close();
    p = await abrir(ancho, "dist"); await alGeovisor(p); await porEdad(p); await tarjetaTramo(p); await p.screenshot({ path: join(CAP, `antes_geovisor_edad_${ancho}.png`) });
    await clicTexto(p, ".geo-tarjeta button", "Ver ficha"); await esperarTexto(p, /Datos del activo/); await new Promise((r) => setTimeout(r, 800));
    await p.evaluate(() => [...document.querySelectorAll(".red-seccion h2")].find((h) => /Referencia del Plan Maestro/.test(h.textContent))?.scrollIntoView({ block: "start" })); await new Promise((r) => setTimeout(r, 250));
    await p.screenshot({ path: join(CAP, `antes_ficha_${ancho}.png`) }); await p.close();
    continue;
  }
  // ===== A. El administrador: Dashboard distribución › Inventario regulatorio =====
  p = await alDashboard(ancho, "adm");
  await pestana(p, "Inventario regulatorio");
  await p.waitForSelector("[data-testid=reg-resumen]", { timeout: 30000 }).catch(async () => { throw new Error("no cargó la conciliación: " + (await texto(p)).slice(-600) + " · rpcs: " + rpcs.map((r) => r.fn).join(",") + " · " + errores.join(" | ") + edgeLog.slice(-400)); });
  t = await p.evaluate(() => document.querySelector("[data-testid=reg-resumen]").innerText);
  ok(`${tag} A1 la valoración se presenta como PROPUESTA de 2019 («su adopción no está confirmada»), con su archivo y que es dato de referencia`,
     /Valoración técnica 2019 \(Res\. CRA 688 de 2014\), propuesta: su adopción no está confirmada/.test(t) && /Valoracion_Tecnica_Valledupar_04122019\.xlsx/.test(t) && /no cambia la ficha de ningún activo/.test(t), t.slice(0, 500));
  ok(`${tag} A2 las tres hojas con sus totales: BCR0 de acueducto 101.061 millones; alcantarillado 138.548 (referencia) y alcantarillado (2) 176.452 (vale)`,
     /Acueducto\s+59[\s\S]*101\.061 millones[\s\S]*Sí/.test(t) && /Alcantarillado\s+39[\s\S]*138\.548 millones[\s\S]*Referencia/.test(t) && /Alcantarillado \(2\)\s+68[\s\S]*176\.452 millones[\s\S]*Sí/.test(t)
     && /valoracion_hoja_alcantarillado/.test(t), t);
  s = await p.evaluate(() => document.querySelector("[data-testid=reg-cuenta]").innerText);
  t = await p.evaluate(() => document.querySelector("[data-testid=reg-conciliacion]").innerText);
  ok(`${tag} A3 la conciliación de acueducto: 26 de 33 filas de tubería calzan (2 % o menos); cada fila con valoración, red, diferencia y porcentaje`,
     /Acueducto: 26 de 33 filas de tubería calzan/.test(s) && /TUBERIA PVC · 3″/.test(t) && /388\.534,4 m/.test(t) && /Todas \(59\)/.test(t) && /%/.test(t), s + " · " + t.slice(0, 400));
  ok(`${tag} A4 los puntuales no se comparan por cantidad: la planta Huaricha dice su activo (PTA-000001) y la bocatoma «Sin activo»`,
     /PLANTA HUARICHA[\s\S]{0,200}PTA-000001/.test(t) && /BOCATOMA[\s\S]{0,400}Sin activo/.test(t), t.slice(0, 900));
  await p.screenshot({ path: join(CAP, `conciliacion_acueducto_${ancho}.png`), fullPage: true });
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=reg-conciliacion]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `conciliacion_tabla_${ancho}.png`) });
  await clicTexto(p, "[data-testid=reg-conciliacion] button", "Sin activos");
  t = await p.evaluate(() => document.querySelector("[data-testid=reg-conciliacion] table")?.innerText ?? "");
  ok(`${tag} A5 el filtro «Sin activos» deja las filas que no tienen activo en la red (bocatoma, aducción, desarenadores, terrenos…)`, /BOCATOMA/.test(t) && /DESARENADOR/.test(t) && !/PLANTA HUARICHA/.test(t), t.slice(0, 500));
  await clicTexto(p, "[data-testid=reg-conciliacion] button", "Alcantarillado (2)"); await clicTexto(p, "[data-testid=reg-conciliacion] button", "Todas");
  s = await p.evaluate(() => document.querySelector("[data-testid=reg-cuenta]").innerText);
  t = await p.evaluate(() => document.querySelector("[data-testid=reg-sin-fila]").innerText);
  ok(`${tag} A6 alcantarillado (2): 27 de 63 filas calzan (con el catastro); abajo, los activos sin fila del alcantarillado, con su motivo`,
     /Alcantarillado \(2\): 27 de 63 filas de tubería calzan/.test(s) && /Activos sin fila \(alcantarillado\)/.test(t) && /Proyectado: no entra|Sin fila en la valoración/.test(t), s + " · " + t.slice(0, 300));
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=reg-conciliacion]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `conciliacion_alcantarillado_${ancho}.png`) });
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=reg-sin-fila]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `activos_sin_fila_${ancho}.png`) });
  await clicTexto(p, "[data-testid=reg-conciliacion] button", "Alcantarillado (referencia)");
  s = await p.evaluate(() => document.querySelector("[data-testid=reg-cuenta]").innerText);
  ok(`${tag} A7 la otra hoja de alcantarillado queda de referencia y también se concilia (4 de 34)`, /Alcantarillado: 4 de 34 filas de tubería calzan/.test(s), s);
  await p.evaluate(() => { window.__blobs = []; const o = URL.createObjectURL.bind(URL); URL.createObjectURL = (b) => { window.__blobs.push(b.size); return o(b); }; });
  await clicTexto(p, "[data-testid=reg-conciliacion] button", "Descargar Excel"); await esperarTexto(p, /Listo: [0-9.]+ filas/);
  t = await texto(p); s = await p.evaluate(() => window.__blobs);
  ok(`${tag} A8 «Descargar Excel» arma el libro en el equipo (las tres hojas y los activos sin fila)`, /Listo: [0-9.]+ filas \(las tres hojas y los activos sin fila\)/.test(t) && s.length === 1 && s[0] > 5000, JSON.stringify(s));
  ok(`${tag} A9 la pantalla no se desborda (las tablas se desplazan dentro de su caja) y los botones miden 44 px o más`, (await sinDesborde(p)) && (await minimo(p, "[data-testid=reg-conciliacion] button")) >= 44);
  ok(`${tag} A10 la conciliación llegó en una sola petición (no recalcula nada) y ninguna petición escribió`, rpcs.filter((r) => r.fn === "geoportal_redes_valoracion").length === 1
     && sqlq("select count(*) from redes.ref_cargas where conjunto in ('valoracion', 'val_amarre')") === "2");
  // desde la fila de la planta, a la ficha
  await clicTexto(p, "[data-testid=reg-conciliacion] button", "Acueducto"); await clicTexto(p, "[data-testid=reg-conciliacion] button.tec-enlace", "PTA-000001");
  await esperarTexto(p, /Datos del activo/); await p.waitForSelector("[data-testid=ficha-regulatorio]");
  t = await seccionReg(p);
  ok(`${tag} A11 la ficha de la planta (administrador): «Inventario regulatorio», remunerado vía tarifa «Sí», con sus dos filas (Huaricha y Gota Fría)`,
     /Inventario regulatorio/.test(t) && /Remunerado vía tarifa\s*Sí/.test(t) && /PLANTA HUARICHA/.test(t) && /PLANTA GOTA FRÍA/.test(t) && /Filas de la valoración\s*6 y 7/.test(t), t.slice(0, 600));
  ok(`${tag} A12 dice que es la valoración de 2019, propuesta; entrada en operación regulatoria, vida útil, remanente a hoy, y valor y depreciación «de la fila» (no se reparten)`,
     /Valoración técnica 2019 \(Res\. CRA 688 de 2014\), propuesta/.test(t) && /Entrada en operación \(regulatoria\)\s*01\/07\/1992/.test(t) && /Vida útil\s*40 años/.test(t) && /Vida útil remanente a hoy\s*[0-9,]+ años \(hasta 01\/07\/2032\)/.test(t)
     && /Valor de la fila\s*\$\s?27\.121\.226\.400/.test(t) && /Depreciación anual de la fila/.test(t) && /no se reparten por activo/.test(t), t);
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=ficha-regulatorio]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `ficha_planta_${ancho}.png`) });
  await p.close();

  // ===== B. El supervisor de distribución: geovisor por edad y la ficha de un tramo =====
  p = await alDashboard(ancho, "dist"); t = await p.evaluate(() => [...document.querySelectorAll("[role=tab]")].map((x) => x.textContent.trim()).join(" | "));
  ok(`${tag} B1 el supervisor de distribución no tiene la pestaña «Inventario regulatorio» (es del administrador)`, !/Inventario regulatorio/.test(t) && /Parámetros/.test(t), t);
  await p.close();
  p = await abrir(ancho, "dist"); await alGeovisor(p);
  t = await porEdad(p);
  ok(`${tag} B2 la leyenda por edad dice que, sin fecha de instalación, la edad sale de la «fecha regulatoria, no de instalación»`, /la edad sale de la fecha regulatoria, no de instalación/.test(t) && /Sin fecha de instalación/.test(t), t);
  tj = await tarjetaTramo(p);
  ok(`${tag} B3 al tocar un tramo sin fecha de instalación (${TRAMO}): «Edad: N años (fecha regulatoria, no de instalación)»`, tj && tj.txt.includes(TRAMO) && /Edad\s*3[0-9] años \(fecha regulatoria, no de instalación\)/.test(tj.txt) && tj.dentro, JSON.stringify(tj));
  s = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const f = m.queryRenderedFeatures(m.project([lon, lat])).find((x) => x.properties.prefijo === "RED"); return f ? JSON.stringify(f.properties) : ""; }, TLON, TLAT);
  ok(`${tag} B4 el tramo se pinta con su edad (ya no en el gris de «sin fecha»): la tesela trae edad y edad_reg`, /"edad":3[0-9]/.test(s) && /"edad_reg":true/.test(s), s);
  await p.screenshot({ path: join(CAP, `geovisor_edad_${ancho}.png`) });
  ok(`${tag} B5 el geovisor por edad no se desborda`, await sinDesborde(p));
  await clicTexto(p, ".geo-tarjeta button", "Ver ficha"); await esperarTexto(p, /Datos del activo/); await p.waitForSelector("[data-testid=ficha-regulatorio]");
  t = await seccionReg(p);
  ok(`${tag} B6 la ficha del tramo (supervisor de distribución): remunerado «Sí», su fila de tubería por material y diámetro, con los metros de la fila y cuántos activos tiene amarrados`,
     /Remunerado vía tarifa\s*Sí/.test(t) && /Fila \d+ · TUBERIA [A-Z ]+ de [0-9,]+ pulgadas/.test(t) && /En la fila\s*[0-9.,]+ m · [0-9.]+ activos amarrados/.test(t) && /01\/07\/1989/.test(t), t.slice(0, 700));
  ok(`${tag} B7 la ficha con la sección no se desborda`, await sinDesborde(p));
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=ficha-regulatorio]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `ficha_tramo_${ancho}.png`) });
  await p.close();
  // un tramo de obra SIVA: tiene fila, pero no se remunera (decisión de David, 16-nov)
  p = await abrir(ancho, "adm"); await esperarTexto(p, /Ficha de activos/); await clicTexto(p, "button.tec-tarjeta-modo", "Ficha de activos"); await esperarTexto(p, /Por código/);
  await poner(p, "#red-codigo", SIVA); await clicTexto(p, "button", "Abrir la ficha"); await esperarTexto(p, /Datos del activo/); await p.waitForSelector("[data-testid=ficha-regulatorio]");
  t = await seccionReg(p);
  ok(`${tag} B8 un tramo de obra SIVA (${SIVA}): remunerado vía tarifa «No», dice por qué y sigue mostrando su fila`,
     /Remunerado vía tarifa\s*No/.test(t) && /obra de un tercero \(SIVA\)[\s\S]*no se remunera vía tarifa/.test(t) && /Fila \d+ · TUBERIA/.test(t), t.slice(0, 500));
  await p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), "[data-testid=ficha-regulatorio]"); await new Promise((r) => setTimeout(r, 250)); await p.screenshot({ path: join(CAP, `ficha_tramo_siva_${ancho}.png`) });
  await p.close();

  // ===== C. El operador de redes: nada de esto =====
  p = await abrir(ancho, "op"); await alGeovisor(p);
  t = await porEdad(p);
  ok(`${tag} C1 el operador: la leyenda por edad no menciona la fecha regulatoria`, !/regulatoria/.test(t) && /Sin fecha de instalación/.test(t), t);
  tj = await tarjetaTramo(p);
  ok(`${tag} C2 el operador toca el mismo tramo: «Sin fecha de instalación», sin edad regulatoria`, tj && tj.txt.includes(TRAMO) && /Edad\s*Sin fecha de instalación/.test(tj.txt) && !/regulatoria/.test(tj.txt), JSON.stringify(tj));
  await p.screenshot({ path: join(CAP, `geovisor_edad_operador_${ancho}.png`) });
  await p.close();
  p = await abrir(ancho, "op"); await esperarTexto(p, /Ficha de activos/); await clicTexto(p, "button.tec-tarjeta-modo", "Ficha de activos"); await esperarTexto(p, /Por código/);
  await poner(p, "#red-codigo", TRAMO); await clicTexto(p, "button", "Abrir la ficha"); await esperarTexto(p, /Datos del activo/);
  await new Promise((r) => setTimeout(r, 600));
  t = await texto(p);
  ok(`${tag} C3 la ficha del operador no trae «Inventario regulatorio» ni ningún término tarifario`, (await seccionReg(p)) === null && !/Inventario regulatorio|remunerad|tarifa|valoración|depreciación|regulatori/i.test(t), t.slice(0, 300));
  ok(`${tag} C4 … y la respuesta del servidor tampoco los trae`, !/remunerad|tarif|valoraci|depreciaci|regulator/i.test(sqlq(`select public.geoportal_redes_activo('${EMAILS.op}', '${TRAMO}')::text`)));
  await p.screenshot({ path: join(CAP, `ficha_operador_${ancho}.png`), fullPage: true });
  await p.close();
  p = await abrir(ancho, "op"); t = await textoInicio(p);
  ok(`${tag} C5 el inicio del operador no menciona el inventario regulatorio`, !/regulatori|tarifa/i.test(t));
  await p.close();
}
if (!ANTES) ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
if (!ANTES) ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(ANTES ? "capturas de «antes» tomadas" : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
