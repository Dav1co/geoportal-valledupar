// Prueba en Chrome REAL de las pantallas del Corte 9b, Fases 1a y 1b (simulación de cierre y cierre real), a 390 px (táctil) y 1280 px:
// · Geovisor: el cuarto modo «Afectaciones» (Tipo · Material · Edad · Afectaciones), la franja «N zonas sin agua en este momento» con «Ver afectaciones»
//   (en cualquier modo, solo si hay cierres), la leyenda en palabras sencillas y las tarjetas de la zona y de la válvula cerrada.
// · Reportar daño o falla y Registrar intervención: «¿Qué válvulas cierro?», «Válvula cerrada» (con su hora y la hora estimada de regreso), «Válvula abierta»
//   y «Guardar esta simulación».
// · La Edge geoportal-redes: las ocho rutas nuevas, sus rechazos por forma y por permiso.
// Las Edges corren DE VERDAD en Deno; las RPC van a la base de Code B (producción hoy + el 10 + la migración del 9b del Code A) con el rol de la API
// (service_role) y los topes de producción (30 s y 8 s). Puertos y base propios de Code B.
// Uso: node scripts/prueba_chrome_cierre_c9b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
//   ANTES=1 RAIZ_UI=<árbol de main>: solo toma las capturas de «antes» (geovisor y los dos formularios) con la página de main.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c9b"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_cierre_c9b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_9bt> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55987, P_EDGE = 55988;      // puertos de Code B (los de Code A son 5498x)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co", nada: "zt.nada@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
// cada ancho arranca de una copia limpia de la plantilla (producción hoy + el 10 + la migración del 9b), en el clúster de Code B
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
rehacer();

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c9b_"));
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
  // desde el 18-nov los formularios de daño e intervención guardan borrador en el celular: esta prueba los abre varias veces sin guardar, así que cada página arranca sin borradores
  await p.evaluateOnNewDocument(() => { try { indexedDB.deleteDatabase("geoportal-tec-borradores"); } catch { /* sin almacenamiento */ } });
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


// «Cierre por aguas arriba» (17-nov): si el servidor ya tiene la opción nueva, sale primero; estas pruebas son de la simulación de siempre («Aislamiento total»)
const aTotal = async (p) => {
  await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-opciones], [data-testid=cie-resultado], [data-testid=panel-cierre] .tec-aviso-error"), { timeout: 60000 }).catch(() => {});
  if (await p.evaluate(() => { const b = document.querySelector('[data-testid=cie-opciones] [data-opcion="total"]'); if (!b) return false; b.click(); return true; })) await p.waitForSelector("[data-testid=cie-resultado]", { timeout: 60000 }).catch(() => {});
};

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


// ---------- 6. Corte 9b: simulación de cierre y cierre real ----------
const ANTES = process.env.ANTES === "1";
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
// un tramo de la red real que se aísla con dos válvulas (160 contratos en la base de pruebas): se toca en su punto medio
const TRAMO = "RED-010302";
const [TLON, TLAT] = coord(`select ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.5)) || '|' || ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.5)) from redes.activo_vigente_mat m where m.codigo = '${TRAMO}'`);
// el daño de prueba va en otro punto del tramo (a un quinto), para que el toque en el punto medio caiga sobre el tramo y no sobre el daño
const [DLON, DLAT] = coord(`select ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.2)) || '|' || ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), 0.2)) from redes.activo_vigente_mat m where m.codigo = '${TRAMO}'`);
const edgeF = async (rol, accion, o = {}) => {
  const u = new URL(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes`); u.searchParams.set("accion", accion); for (const [k, v] of Object.entries(o.qs ?? {})) u.searchParams.set(k, v);
  const r = await fetch(u, { method: o.metodo ?? (o.cuerpo === undefined ? "GET" : "POST"), headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) }, body: o.cuerpo === undefined ? undefined : JSON.stringify(o.cuerpo) });
  const tipo = r.headers.get("content-type") ?? ""; const cuerpo = /json/.test(tipo) ? await r.json() : new Uint8Array(await r.arrayBuffer());
  return { status: r.status, tipo, cache: r.headers.get("cache-control"), cuerpo };
};
const modo = async (p, n) => { await clicTexto(p, ".geo-seg button", n); await p.waitForFunction((n) => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === n)?.getAttribute("aria-pressed") === "true", {}, n); };
const franja = (p) => p.evaluate(() => { const f = document.querySelector("[data-testid=franja-cortes]"); return f ? { txt: f.innerText, botones: [...f.querySelectorAll("button")].map((b) => b.textContent.trim()), alto: Math.min(...[...f.querySelectorAll("button")].map((b) => b.getBoundingClientRect().height)) } : null; });
const pintura = (p, capa, prop) => p.evaluate((c, pr) => { const m = document.querySelector(".geo-mapa").__mapa; return m.getLayer(c) ? JSON.stringify(m.getPaintProperty(c, pr)) : null; }, capa, prop);
const panel = (p) => p.evaluate(() => { const s = document.querySelector("[data-testid=panel-cierre]"); return s ? { txt: s.innerText, botones: [...s.querySelectorAll("button")].map((b) => b.textContent.trim()),
  alto: Math.min(...[...s.querySelectorAll("button:not(.tec-enlace)")].filter((b) => b.offsetParent).map((b) => b.getBoundingClientRect().height)), valvulas: [...s.querySelectorAll("[data-testid=cie-resultado] li[data-valvula]")].map((x) => x.dataset.valvula) } : null; });
const enPanel = (p, t, dentro = "[data-testid=panel-cierre]") => p.evaluate((t, d) => { const b = [...document.querySelectorAll(`${d} button`)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, t, dentro);
const esperarPanel = (p, re, ms = 40000) => p.waitForFunction((s) => new RegExp(s).test(document.querySelector("[data-testid=panel-cierre]")?.innerText ?? ""), { timeout: ms }, re.source).then(() => true).catch(() => false);
// La hora de regreso como la escribe la pantalla (horaClara): sola si cae hoy; con el día delante («18 de nov, 2:00 a. m.») si cruza la medianoche.
// Antes la prueba esperaba siempre la hora sola y D6 fallaba al correrla después de las 9 p. m. (regreso = ahora + 3 h). FORZAR_REGRESO_MIN la corre a cualquier hora.
const REGRESO_MIN = Number(process.env.FORZAR_REGRESO_MIN || 180);
const diaBogota = (d) => d.toLocaleDateString("es-CO", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit" });
const horaRegreso = (min) => diaBogota(new Date(Date.now() + min * 60000)) === diaBogota(new Date())
  ? /Regreso estimado del servicio\s*\d{1,2}:\d{2}/ : /Regreso estimado del servicio\s*\d{1,2} de [a-zñ]{3,5}\.?, \d{1,2}:\d{2}/;
const campoLocal = (min) => { const d = new Date(Date.now() + min * 60000), z = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`; };
const verPanel = (p) => p.evaluate(() => document.querySelector("[data-testid=panel-cierre]")?.scrollIntoView({ block: "start" }));
async function tarjetaDelTramo(p) {
  await encender(p, "acu_nodos", false); await encender(p, "sectores", false);
  await tocar(p, TLON, TLAT, 18);
  return esperarTarjeta(p, "activo", new RegExp(TRAMO));
}

for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  for (const e of [EMAILS.op, EMAILS.op2]) sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${e}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  let p, t, tj, s, f, r;
  if (ANTES) {      // solo capturas con la página de main (antes de las pantallas del 9b)
    p = await abrir(ancho, "op"); await alGeovisor(p); await new Promise((x) => setTimeout(x, 1500)); await p.screenshot({ path: join(CAP, `antes_geovisor_${ancho}.png`) });
    await tarjetaDelTramo(p); await clicTexto(p, ".geo-tarjeta button", "Reportar daño"); await esperarTexto(p, /1\. Activo y ubicación/); await new Promise((x) => setTimeout(x, 1200));
    await p.screenshot({ path: join(CAP, `antes_dano_${ancho}.png`), fullPage: true }); await p.close();
    p = await abrir(ancho, "op"); await alGeovisor(p); await tarjetaDelTramo(p); await clicTexto(p, ".geo-tarjeta button", "Registrar intervención"); await esperarTexto(p, /De dónde nace/); await new Promise((x) => setTimeout(x, 1200));
    await p.screenshot({ path: join(CAP, `antes_intervencion_${ancho}.png`), fullPage: true }); await p.close();
    continue;
  }
  // un daño abierto del operador sobre el tramo (por la base, como lo deja «Reportar daño o falla»)
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  const DAN = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", ubicacion_origen: "mapa", activo: TRAMO, lat: DLAT, lon: DLON,
    t_detectado: iso(-20), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`)).codigo;

  // ===== A. Sin cierres: el modo «Afectaciones» existe y el mapa queda limpio; no hay franja =====
  p = await abrir(ancho, "op"); await alGeovisor(p);
  ok(`${tag} A1 el selector dice «Tipo · Material · Edad · Afectaciones»`, (await p.evaluate(() => [...document.querySelectorAll(".geo-seg button")].map((b) => b.textContent.trim()).join(" · "))) === "Tipo · Material · Edad · Afectaciones");
  await new Promise((x) => setTimeout(x, 800));
  ok(`${tag} A2 sin válvulas cerradas no hay franja, y la tesela de afectaciones no se pide fuera de su modo`, (await franja(p)) === null && (await visibilidad(p, "x-corte-cerrado")) === "none"
     && rpcs.some((x) => x.fn === "geoportal_redes_cortes_vigentes") && !rpcs.some((x) => x.fn === "geoportal_redes_geovisor_mvt_cortes"));
  await modo(p, "Afectaciones"); await p.waitForSelector("[data-testid=leyenda-cortes]");
  t = await p.evaluate(() => document.querySelector("[data-testid=leyenda-cortes]").innerText);
  ok(`${tag} A3 «Afectaciones»: leyenda en palabras sencillas («Sin agua», «Tubería cerrada», «Válvula cerrada») y «No hay válvulas cerradas en este momento»`, /Sin agua[\s\S]*Tubería cerrada[\s\S]*Válvula cerrada[\s\S]*No hay válvulas cerradas en este momento/.test(t), t);
  ok(`${tag} A4 en «Afectaciones» la red queda de fondo en gris claro (#d5dde6)`, /d5dde6/i.test(await pintura(p, "t-acu_tramos-l", "line-color") ?? await pintura(p, "t-acueducto-l", "line-color") ?? ""), await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getStyle().layers.filter((l) => l.id.endsWith("-l")).map((l) => l.id).join(",")));
  await new Promise((x) => setTimeout(x, 1200)); await p.screenshot({ path: join(CAP, `afectaciones_sin_cierres_${ancho}.png`) });
  await modo(p, "Tipo");
  ok(`${tag} A5 al volver a «Tipo» el mapa queda limpio: sin capas de cortes y con los colores de siempre`, (await visibilidad(p, "x-corte-cerrado")) === "none" && (await visibilidad(p, "x-corte-valvula")) === "none" && !(await p.$("[data-testid=leyenda-cortes]")));

  // ===== B. Reportar daño o falla: «¿Qué válvulas cierro?» (solo la simulación, antes de guardar) =====
  tj = await tarjetaDelTramo(p);
  if (!tj || !(await clicTexto(p, ".geo-tarjeta button", "Reportar daño"))) throw new Error("la tarjeta del tramo no trae «Reportar daño»: " + JSON.stringify(tj));
  await p.waitForSelector("[data-testid=panel-cierre]", { timeout: 30000 }).catch(async () => { throw new Error("el formulario de daño no trae el panel de cierre: " + (await texto(p)).slice(0, 1200) + " · " + errores.join(" | ")); });
  await verPanel(p); s = await panel(p);
  ok(`${tag} B1 el formulario de daño trae «Cierre de válvulas» con el botón «¿Qué válvulas cierro?»`, /Cierre de válvulas/.test(s.txt) && s.botones.includes("¿Qué válvulas cierro?"), s.txt);
  await enPanel(p, "¿Qué válvulas cierro?"); await aTotal(p); await esperarPanel(p, /Contratos sin agua/); s = await panel(p);
  const VALV = s.valvulas;
  ok(`${tag} B2 la simulación dice qué válvulas cerrar (2, en orden) y cuántos tramos y contratos quedan sin agua (rango «De 160 a …»)`, VALV.length === 2 && VALV.every((v) => /^VAL-\d{6}$/.test(v)) && /(Para aislar|Aislamiento total de) RED-010302/.test(s.txt)
     && /Cierre estas 2 válvulas/.test(s.txt) && /Tramos sin agua\s*18/.test(s.txt) && /De 160 a [\d.]+/.test(s.txt), s.txt);
  ok(`${tag} B3 sin el daño guardado no hay «Válvula cerrada» ni «Guardar esta simulación»: lo dice`, !s.botones.some((b) => /Válvula cerrada|Guardar esta simulación/.test(b)) && /guarde primero este registro/.test(s.txt));
  await enPanel(p, "Si una válvula no cierra"); await esperarPanel(p, /no cierra: /); s = await panel(p);
  ok(`${tag} B4 «Si una válvula no cierra…» dice cuáles cerrar en su lugar y los contratos`, VALV.every((v) => new RegExp(`Si ${v} no cierra: (cierre VAL-\\d{6}|no hace falta cerrar otra)`).test(s.txt)) && /no cierra: cierre VAL-/.test(s.txt) && /Quedan sin agua [\d.]+ contratos/.test(s.txt), s.txt.slice(s.txt.indexOf("Si una"), s.txt.indexOf("Si una") + 500));
  ok(`${tag} B5 el panel no desborda, sus botones miden 44 px o más y no trae términos tarifarios ni datos de suscriptores`, (await sinDesborde(p)) && s.alto >= 44 && !/tarif|remunerad|suscriptor|@/i.test(s.txt), String(s.alto));
  await verPanel(p); await new Promise((x) => setTimeout(x, 300)); await p.screenshot({ path: join(CAP, `dano_simulacion_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== C. Registrar intervención sobre el daño: válvula cerrada, hora de regreso, guardar la simulación, válvula abierta =====
  p = await abrir(ancho, "op"); await alGeovisor(p); await tarjetaDelTramo(p);
  await clicTexto(p, ".geo-tarjeta button", "Registrar intervención"); await esperarTexto(p, /De dónde nace/);
  await clicTexto(p, "button.dan-opcion", "Daño o falla"); await p.waitForSelector(".itv-dano");
  await p.evaluate((d) => [...document.querySelectorAll(".itv-dano")].find((b) => b.textContent.includes(d)).click(), DAN);
  await p.waitForSelector("[data-testid=panel-cierre]"); await verPanel(p);
  await enPanel(p, "¿Qué válvulas cierro?"); await aTotal(p); await esperarPanel(p, /Contratos sin agua/); s = await panel(p);
  ok(`${tag} C1 con el daño elegido (${DAN}), cada válvula del resultado trae «Válvula cerrada», y está «Guardar esta simulación»`, s.botones.filter((b) => b === "Válvula cerrada").length === 2 && s.botones.includes("Guardar esta simulación"), s.botones.join(" | "));
  await enPanel(p, "Válvula cerrada", `[data-testid=panel-cierre] li[data-valvula="${VALV[0]}"]`); await p.waitForSelector("[data-testid=cie-pedir]");
  t = await p.evaluate(() => document.querySelector("[data-testid=cie-pedir]").innerText);
  ok(`${tag} C2 «Válvula cerrada» pide la hora (vacía si fue ahora) y la hora estimada de regreso (opcional)`, new RegExp(`Válvula ${VALV[0]} cerrada`).test(t) && /¿A qué hora\?/.test(t) && /Regreso estimado del servicio/.test(t), t);
  await poner(p, "#cie-regreso", campoLocal(REGRESO_MIN));
  await enPanel(p, "Confirmar", "[data-testid=cie-pedir]"); await esperarPanel(p, new RegExp(`Válvula ${VALV[0]} cerrada \\(`)); await esperarPanel(p, /Válvulas cerradas por/); s = await panel(p);
  r = sqlq(`select m.tipo || '|' || (m.dano_id is not null) || '|' || (m.regreso_estimado is not null) || '|' || m.autor from redes.valvula_maniobras m join redes.activos a on a.id = m.valvula_id where a.codigo = '${VALV[0]}'`);
  ok(`${tag} C3 queda la maniobra «cerrar» con el daño, la hora de regreso y quien la hizo; el panel la muestra «Cerrada» y en «Válvulas cerradas por ${DAN}»`, r === `cerrar|true|true|${EMAILS.op}`
     && new RegExp(`Válvulas cerradas por ${DAN}`).test(s.txt) && /Cerrada desde/.test(s.txt) && /regreso estimado/.test(s.txt) && s.botones.includes("Válvula abierta"), r + " · " + s.txt.slice(0, 400));
  await enPanel(p, "Válvula cerrada", `[data-testid=panel-cierre] li[data-valvula="${VALV[1]}"]`); await p.waitForSelector("[data-testid=cie-pedir]");
  await enPanel(p, "Confirmar", "[data-testid=cie-pedir]"); await esperarPanel(p, new RegExp(`Válvula ${VALV[1]} cerrada \\([\\s\\S]*1 zona sin agua, 160 contratos`)); s = await panel(p);
  ok(`${tag} C4 con las dos cerradas el aviso dice «1 zona sin agua, 160 contratos»`, new RegExp(`Válvula ${VALV[1]} cerrada \\([\\s\\S]*En este momento: 1 zona sin agua, 160 contratos`).test(s.txt), s.txt.slice(0, 500));
  await enPanel(p, "Guardar esta simulación"); await esperarPanel(p, new RegExp(`Simulación guardada con ${DAN}`));
  ok(`${tag} C5 «Guardar esta simulación» la deja con el daño (la recalcula el servidor)`, sqlq(`select count(*) || '|' || min(s.contratos_min) || '|' || min(s.valvulas) from redes.simulaciones_cierre s join redes.danos d on d.id = s.dano_id where d.codigo = '${DAN}'`) === "1|160|2");
  ok(`${tag} C6 el formulario de la intervención con el panel no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await panel(p)).alto >= 44);
  await verPanel(p); await new Promise((x) => setTimeout(x, 300)); await p.screenshot({ path: join(CAP, `intervencion_cierre_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== D. El geovisor con cierres: franja en cualquier modo, «Ver afectaciones», leyenda y tarjetas (operador de solo lectura) =====
  const cv = JSON.parse(sqlq(`select public.geoportal_redes_cortes_vigentes('${EMAILS.adm}')`));
  p = await abrir(ancho, "op2"); await alGeovisor(p); await p.waitForSelector("[data-testid=franja-cortes]");
  f = await franja(p);
  ok(`${tag} D1 en modo «Tipo» sale la franja «1 zona sin agua en este momento», con su botón de zona y «Ver afectaciones» (44 px o más); el mapa sigue limpio`, /1 zona sin agua en este momento/.test(f.txt) && f.botones.join("|") === "Zona 1 · 160 contratos|Ver afectaciones"
     && f.alto >= 44 && (await visibilidad(p, "x-corte-cerrado")) === "none", JSON.stringify(f));
  await p.screenshot({ path: join(CAP, `franja_modo_tipo_${ancho}.png`) });
  await modo(p, "Edad");
  ok(`${tag} D2 la franja sigue en los otros modos (Edad)`, /1 zona sin agua/.test((await franja(p))?.txt ?? ""));
  await clicTexto(p, "[data-testid=franja-cortes] button", "Ver afectaciones");
  await p.waitForFunction(() => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === "Afectaciones")?.getAttribute("aria-pressed") === "true");
  const hayCerr = await esperarDibujo(p, "x-corte-cerrado"), hayValv = await esperarDibujo(p, "x-corte-valvula");
  ok(`${tag} D3 «Ver afectaciones» pasa al modo Afectaciones y lleva el mapa a la zona: se dibujan las tuberías cerradas y las válvulas cerradas`, hayCerr && hayValv && (await dibujados(p, "x-corte-valvula")) >= 2
     && await p.evaluate((c) => { const m = document.querySelector(".geo-mapa").__mapa.getBounds(); return m.getWest() <= c[0] && m.getSouth() <= c[1] && m.getEast() >= c[2] && m.getNorth() >= c[3]; }, cv.zonas[0].caja));
  ok(`${tag} D4 colores aprobados: tubería cerrada rojo #b3261e continuo de 5 px; sin agua naranja #c25e00 punteado de 3 px; válvula punto rojo con borde blanco`,
     (await pintura(p, "x-corte-cerrado", "line-color")) === '"#b3261e"' && (await pintura(p, "x-corte-cerrado", "line-width")) === "5" && (await pintura(p, "x-corte-afectado", "line-color")) === '"#c25e00"'
     && (await pintura(p, "x-corte-afectado", "line-dasharray")) === "[2,1.5]" && (await pintura(p, "x-corte-afectado", "line-width")) === "3" && (await pintura(p, "x-corte-valvula", "circle-color")) === '"#b3261e"'
     && (await pintura(p, "x-corte-valvula", "circle-stroke-color")) === '"#FFFFFF"' && (await pintura(p, "x-corte-valvula", "circle-radius")) === "5");
  t = await p.evaluate(() => document.querySelector("[data-testid=leyenda-cortes]").innerText);
  ok(`${tag} D5 la leyenda dice cuántas hay: «2 válvulas cerradas · 160 contratos sin agua»`, /2 válvulas cerradas · 160 contratos sin agua/.test(t), t);
  await new Promise((x) => setTimeout(x, 800)); await p.screenshot({ path: join(CAP, `afectaciones_mapa_${ancho}.png`) });
  await clicTexto(p, "[data-testid=franja-cortes] button", "Zona 1"); tj = await esperarTarjeta(p, "corte_zona", /Contratos afectados/);
  ok(`${tag} D6 tarjeta de la zona en lenguaje claro: «Sin agua desde las …», «Por: … · ${DAN}», «Contratos afectados 160» y «Regreso estimado del servicio»`, !!tj && /Zona 1 sin agua/.test(tj.txt) && /Sin agua desde las \d{1,2}:\d{2}/.test(tj.txt)
     && new RegExp(`Por\\s*[^\\n]* · ${DAN}`).test(tj.txt) && /Contratos afectados\s*160/.test(tj.txt) && horaRegreso(REGRESO_MIN).test(tj.txt) && tj.dentro, tj?.txt);
  await p.screenshot({ path: join(CAP, `afectaciones_zona_${ancho}.png`) });
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  const v0 = cv.valvulas.find((v) => v.codigo === VALV[0]);
  await tocarEn(p, v0.lon, v0.lat, 18); tj = await esperarTarjeta(p, "corte_valvula", /Cerrada desde/);
  ok(`${tag} D7 al tocar la válvula cerrada en el mapa: su tarjeta con el código, «Cerrada desde», quién (el nombre del funcionario, nunca el correo), el daño y el regreso`, !!tj && new RegExp(`Válvula cerrada ${VALV[0]}`).test(tj.txt)
     && /Cerrada desde\s*\d{1,2}:\d{2}/.test(tj.txt) && new RegExp(`Daño o intervención\\s*${DAN}`).test(tj.txt) && /Regreso estimado del servicio/.test(tj.txt) && !/@/.test(tj.txt), tj?.txt);
  ok(`${tag} D8 el operador de solo lectura no tiene «Válvula abierta» ni «Ajustar hora de regreso»`, !!tj && !tj.botones.some((b) => /Válvula abierta|Ajustar hora/.test(b)), tj?.botones.join("|"));
  ok(`${tag} D9 el geovisor con la franja y la tarjeta no desborda`, await sinDesborde(p));
  await p.close();

  // ===== E. Quien puede (administrador): ajustar la hora de regreso y «Válvula abierta» desde la tarjeta del geovisor =====
  p = await abrir(ancho, "adm"); await alGeovisor(p); await p.waitForSelector("[data-testid=franja-cortes]");
  await clicTexto(p, "[data-testid=franja-cortes] button", "Zona 1"); tj = await esperarTarjeta(p, "corte_zona", /Contratos afectados/);
  await p.evaluate((c) => [...document.querySelectorAll(".geo-tarjeta button")].find((b) => b.textContent.includes(c) || b.textContent.startsWith("Válvula")).click(), VALV[0]);
  tj = await esperarTarjeta(p, "corte_valvula", /Cerrada desde/);
  const ESTA = tj.txt.match(/VAL-\d{6}/)[0];
  ok(`${tag} E1 desde la tarjeta de la zona se abre la de su válvula; el administrador tiene «Válvula abierta» y «Ajustar hora de regreso»`, tj.botones.includes("Válvula abierta") && tj.botones.includes("Ajustar hora de regreso"), tj.botones.join("|"));
  await clicTexto(p, ".geo-tarjeta button", "Ajustar hora de regreso"); await p.waitForSelector("#geo-regreso"); await poner(p, "#geo-regreso", campoLocal(600));
  await clicTexto(p, ".geo-tarjeta button", "Guardar la hora");
  await p.waitForFunction(() => !document.querySelector("#geo-regreso"), { timeout: 30000 });
  ok(`${tag} E2 «Ajustar hora de regreso» deja un evento nuevo (nada se borra) y la tarjeta muestra la hora nueva`, sqlq(`select count(*) from redes.valvula_maniobras m join redes.activos a on a.id = m.valvula_id where a.codigo = '${ESTA}' and m.tipo = 'regreso'`) === "1"
     && sqlq(`select count(*) from redes.valvula_maniobras`) === "3");
  await p.screenshot({ path: join(CAP, `afectaciones_valvula_${ancho}.png`) });
  await clicTexto(p, ".geo-tarjeta button", "Válvula abierta"); await p.waitForSelector("[data-testid=cie-pedir]");
  await enPanel(p, "Confirmar", "[data-testid=cie-pedir]");
  await p.waitForFunction(() => !document.querySelector(".geo-tarjeta[data-capa=corte_valvula]"), { timeout: 40000 });
  r = sqlq(`select count(*) filter (where tipo = 'abrir') || '|' || (select zonas || '|' || valvulas_cerradas from redes.corte_fotos order by id desc limit 1) from redes.valvula_maniobras`);
  ok(`${tag} E3 «Válvula abierta» desde el geovisor registra la apertura y saca la foto nueva (queda 1 válvula cerrada, ya sin zona aislada)`, /^1\|\d+\|1$/.test(r), r);
  await p.close();
  sqlq(`select public.geoportal_redes_valvula_maniobra('${EMAILS.adm}', '${VALV.find((v) => v !== ESTA)}', 'abrir')`);
  p = await abrir(ancho, "op2"); await alGeovisor(p); await new Promise((x) => setTimeout(x, 1500));
  ok(`${tag} E4 con todo abierto ya no hay franja`, (await franja(p)) === null);
  await p.close();
}

if (!ANTES) {
  // ===== F. La Edge: las rutas nuevas, sus rechazos por forma y por permiso (base del último ancho: todo abierto, una simulación guardada) =====
  const DANF = sqlq("select max(codigo) from redes.danos");
  let r = await edgeF("op2", "cortes_vigentes");
  ok("F1 cortes_vigentes (GET) responde a todo perfil del geovisor, sin caché; por POST, 405", r.status === 200 && r.cuerpo.hay === false && r.cache === "no-store" && (await edgeF("op2", "cortes_vigentes", { cuerpo: {} })).status === 405, JSON.stringify(r.cuerpo).slice(0, 200));
  r = await edgeF("op2", "geovisor_tesela_cortes", { qs: { z: "15", x: "9717", y: "15421", v: "1" } });
  ok("F2 geovisor_tesela_cortes devuelve MVT (o 204 si está vacía) con caché privada; una tesela fuera de rango, 400", [200, 204].includes(r.status) && /mapbox-vector-tile/.test(r.tipo) && /private/.test(r.cache)
     && (await edgeF("op2", "geovisor_tesela_cortes", { qs: { z: "30", x: "1", y: "1" } })).status === 400, `${r.status} ${r.tipo}`);
  r = await edgeF("op", "simulacion_cierre", { cuerpo: { activo: TRAMO } });
  ok("F3 simulacion_cierre (POST) con el activo responde la simulación; sin activo ni ubicación, o con un dato de más, 400; por GET, 405", r.status === 200 && r.cuerpo.estrecho.valvulas_total === 2 && r.cache === "no-store"
     && (await edgeF("op", "simulacion_cierre", { cuerpo: {} })).status === 400 && (await edgeF("op", "simulacion_cierre", { cuerpo: { activo: TRAMO, otro: 1 } })).status === 400 && (await edgeF("op", "simulacion_cierre")).status === 405);
  r = await edgeF("op", "simulacion_cierre", { cuerpo: { lat: TLAT, lon: TLON } });
  ok("F4 simulacion_cierre desde una ubicación (va en el cuerpo) toma el tramo más cercano", r.status === 200 && r.cuerpo.activo.codigo === TRAMO, JSON.stringify(r.cuerpo).slice(0, 200));
  r = await edgeF("nada", "simulacion_cierre", { cuerpo: { activo: TRAMO } });
  ok("F5 alguien sin Técnica no simula (403) ni maniobra (403)", r.status === 403 && (await edgeF("nada", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar", registro: DANF } })).status === 403, String(r.status));
  r = await edgeF("op", "simulaciones", { qs: { registro: DANF } });
  ok("F6 simulaciones (GET) trae las guardadas del daño; con un código mal escrito, 400", r.status === 200 && r.cuerpo.simulaciones.length === 1 && (await edgeF("op", "simulaciones", { qs: { registro: "DAN-1" } })).status === 400);
  ok("F7 valvula_maniobra rechaza por forma: tipo desconocido, dato de más, hora mal escrita y registro mal escrito (400)", (await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "trabar" } })).status === 400
     && (await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar", registro: DANF, x: 1 } })).status === 400
     && (await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar", registro: DANF, hecho_en: "ayer" } })).status === 400
     && (await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar", registro: "DAN-12" } })).status === 400);
  r = await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar" } });
  ok("F8 el operador no cierra sin daño ni intervención (403: solo el supervisor, con motivo)", r.status === 403, `${r.status} ${JSON.stringify(r.cuerpo)}`);
  r = await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "cerrar", registro: DANF, regreso: new Date(Date.now() + 7200000).toISOString() } });
  const r2 = await edgeF("op", "corte_regreso", { cuerpo: { valvula: "VAL-000592", regreso: new Date(Date.now() + 10800000).toISOString() } });
  ok("F9 valvula_maniobra (cerrar, con el daño) y corte_regreso por la Edge; corte_regreso sin hora, 400", r.status === 200 && r.cuerpo.estado === "cerrada" && r2.status === 200 && !!r2.cuerpo.regreso_estimado
     && (await edgeF("op", "corte_regreso", { cuerpo: { valvula: "VAL-000592" } })).status === 400, `${r.status} ${JSON.stringify(r.cuerpo).slice(0, 200)} · ${r2.status}`);
  r = await edgeF("op", "cortes_recalcular", { cuerpo: { motivo: "La red cambió después del cierre" } });
  const r3 = await edgeF("adm", "cortes_recalcular", { cuerpo: { motivo: "La red cambió después del cierre" } });
  ok("F10 cortes_recalcular: el operador no (403); el administrador sí, con motivo (sin motivo, 400)", r.status === 403 && r3.status === 200 && r3.cuerpo.valvulas_cerradas === 1 && (await edgeF("adm", "cortes_recalcular", { cuerpo: { motivo: "corto" } })).status === 400, `${r.status} ${r3.status}`);
  r = await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "abrir" } });
  ok("F11 valvula_maniobra (abrir) por la Edge; abrir una que no está cerrada lo niega con su texto (400)", r.status === 200 && r.cuerpo.estado === "abierta" && (await edgeF("op", "valvula_maniobra", { cuerpo: { valvula: "VAL-000592", tipo: "abrir" } })).status === 400, JSON.stringify(r.cuerpo).slice(0, 200));
  r = await edgeF("op", "simulacion_guardar", { cuerpo: { registro: DANF } });
  ok("F12 simulacion_guardar por la Edge deja otra simulación con el daño; con un dato de más, 400", r.status === 200 && r.cuerpo.registro === DANF && Number.isInteger(r.cuerpo.id) && (await edgeF("op", "simulacion_guardar", { cuerpo: { registro: DANF, z: 1 } })).status === 400);
  ok("F13 ninguna respuesta de las rutas nuevas trae datos de suscriptores (nombre, dirección, teléfono, cédula)", !/suscriptor|direccion|telefono|cedula/i.test(JSON.stringify([(await edgeF("op", "simulacion_cierre", { cuerpo: { activo: TRAMO } })).cuerpo, (await edgeF("op", "cortes_vigentes")).cuerpo])));
  ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
  ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));
}

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(ANTES ? "capturas de «antes» tomadas" : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
