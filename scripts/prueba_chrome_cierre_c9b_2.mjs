// Prueba en Chrome REAL del segundo pase de pantallas del Corte 9b (Fases 1b, 2 y 3), a 390 px (táctil) y 1280 px:
// · Simulación: el minimapa con las válvulas numeradas; «¿Qué válvulas cierro?» en el daño del Dashboard distribución.
// · Geovisor: el supervisor cierra una válvula sin daño ni intervención (con motivo) y «Volver a calcular»; en «Afectaciones», los DAÑOS ABIERTOS de
//   acueducto y alcantarillado (contorno del activo «Daño reportado», el punto encima y su tarjeta); la capa «Flujo del agua (modelo)» con flechas,
//   selector de hora, leyenda y tarjeta («Modelo, no medido»).
// · Dashboard distribución: «Alertas de presión» (modelo, no medido) y la bandeja «Usuarios sensibles» (sin nombres).
// · La Edge geoportal-redes: las rutas de las Fases 2 y 3 con sus rechazos.
// Las Edges corren DE VERDAD en Deno; las RPC van a la base de Code B (producción hoy + 9b 1a/1b + Fases 2 y 3 del Code A + el flujo cargado) con el rol de
// la API (service_role) y los topes de producción (30 s y 8 s). Puertos y base propios de Code B.
// Uso: node scripts/prueba_chrome_cierre_c9b_2.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
//   ANTES=1 RAIZ_UI=<árbol de main>: solo las capturas de «antes» (Afectaciones, lista de capas, daño del dashboard y pestañas) con la página de main.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c9b_2"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_cierre_c9b_2.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_9b3t> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55985, P_EDGE = 55986;      // puertos de Code B (los de Code A son 5498x)
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
const dir = mkdtempSync(join(tmpdir(), "ui_c9b2_"));
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



// ---------- 6. Corte 9b, segundo pase ----------
const ANTES = process.env.ANTES === "1";
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const TRAMO = "RED-010302";      // se aísla con dos válvulas (160 contratos en la base de pruebas)
const pto = (f) => coord(`select ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), ${f})) || '|' || ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom, 1), ${f})) from redes.activo_vigente_mat m where m.codigo = '${TRAMO}'`);
const [TLON, TLAT] = pto(0.5), [DLON, DLAT] = pto(0.2);
// un pozo de alcantarillado cerca (a más de 60 m del tramo, para que su toque no se confunda) y un punto sin activo
const POZ = sqlq(`select m.codigo || '|' || ST_X(m.geom) || '|' || ST_Y(m.geom) from redes.activo_vigente_mat m where m.sistema = 'alcantarillado' and m.prefijo = 'POZ' and not m.retirado
  and ST_DWithin(m.geom::geography, ST_SetSRID(ST_MakePoint(${TLON}, ${TLAT}), 4326)::geography, 220) and not ST_DWithin(m.geom::geography, ST_SetSRID(ST_MakePoint(${TLON}, ${TLAT}), 4326)::geography, 70)
  order by m.geom <-> ST_SetSRID(ST_MakePoint(${TLON}, ${TLAT}), 4326) limit 1`).split("|");
const [POZO, PLON, PLAT] = [POZ[0], Number(POZ[1]), Number(POZ[2])];
const [SLON, SLAT] = [TLON + 0.0011, TLAT - 0.0011];      // daño sin activo: a unos 170 m
const edgeF = async (rol, accion, o = {}) => {
  const u = new URL(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes`); u.searchParams.set("accion", accion); for (const [k, v] of Object.entries(o.qs ?? {})) u.searchParams.set(k, v);
  const r = await fetch(u, { method: o.metodo ?? (o.cuerpo === undefined ? "GET" : "POST"), headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) }, body: o.cuerpo === undefined ? undefined : JSON.stringify(o.cuerpo) });
  const tipo = r.headers.get("content-type") ?? ""; const cuerpo = /json/.test(tipo) ? await r.json() : new Uint8Array(await r.arrayBuffer());
  return { status: r.status, tipo, cache: r.headers.get("cache-control"), cuerpo };
};
const modo = async (p, n) => { await clicTexto(p, ".geo-seg button", n); await p.waitForFunction((n) => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === n)?.getAttribute("aria-pressed") === "true", {}, n); };
const pintura = (p, capa, prop) => p.evaluate((c, pr) => { const m = document.querySelector(".geo-mapa").__mapa; return m.getLayer(c) ? JSON.stringify(m.getPaintProperty(c, pr)) : null; }, capa, prop);
const panel = (p, d = "[data-testid=panel-cierre]") => p.evaluate((d) => { const s = document.querySelector(d); return s ? { txt: s.innerText, botones: [...s.querySelectorAll("button")].map((b) => b.textContent.trim()),
  alto: Math.min(...[...s.querySelectorAll("button:not(.tec-enlace)")].filter((b) => b.offsetParent).map((b) => b.getBoundingClientRect().height)), valvulas: [...s.querySelectorAll("[data-testid=cie-resultado] li[data-valvula]")].map((x) => x.dataset.valvula) } : null; }, d);
const enPanel = (p, t, dentro = "[data-testid=panel-cierre]") => p.evaluate((t, d) => { const b = [...document.querySelectorAll(`${d} button`)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, t, dentro);
const esperarPanel = (p, re, ms = 40000) => p.waitForFunction((s) => new RegExp(s).test(document.querySelector("[data-testid=panel-cierre]")?.innerText ?? ""), { timeout: ms }, re.source).then(() => true).catch(() => false);
const ver = (p, sel) => p.evaluate((s) => document.querySelector(s)?.scrollIntoView({ block: "start" }), sel);
const leyenda = (p, id) => p.evaluate((id) => document.querySelector(`[data-testid=${id}]`)?.innerText ?? null, id);
const pausa = (ms) => new Promise((x) => setTimeout(x, ms));
const crearDano = (o) => { const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", ubicacion_origen: "mapa", t_detectado: iso(-25), causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }], ...o })})`)).codigo; };
async function apagarNodos(p) { await encender(p, "acu_nodos", false); await encender(p, "sectores", false); }
async function alDashboard2(ancho, rol, pest) {
  const p = await abrir(ancho, rol, null);
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Dashboard distribución[\s\S]*No identificados/);
  if (pest) await pestana(p, pest);
  return p;
}

for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  for (const e of [EMAILS.op, EMAILS.op2]) sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${e}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  const DAN = crearDano({ tipo: "fuga", sistema: "acueducto", activo: TRAMO, lat: DLAT, lon: DLON, tipo_rotura: "parcial", riesgo: "medio" });
  const DANL = crearDano({ tipo: "rebose", sistema: "alcantarillado", activo: POZO, lat: PLAT, lon: PLON, riesgo: "alto" });
  const DANS = crearDano({ tipo: "fuga", sistema: "acueducto", no_identificado: "Tubo en el andén", lat: SLAT, lon: SLON, tipo_rotura: "parcial", riesgo: "bajo" });
  let p, t, tj, s, r;
  if (ANTES) {      // con la página de main (el primer pase del 9b ya publicado)
    p = await abrir(ancho, "dist"); await alGeovisor(p); await modo(p, "Afectaciones"); await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 16.5 }), TLON, TLAT); await pausa(2500);
    await p.screenshot({ path: join(CAP, `antes_afectaciones_${ancho}.png`) }); await panelCapas(p); await p.evaluate(() => document.querySelector(".geo-panel [data-capa=flujo_modelo]")?.scrollIntoView({ block: "center" })); await pausa(300);
    await p.screenshot({ path: join(CAP, `antes_capas_flujo_${ancho}.png`) }); await p.close();
    p = await alDashboard2(ancho, "dist", "Daños y fallas"); await esperarTexto(p, new RegExp(DAN)); await pausa(400); await p.screenshot({ path: join(CAP, `antes_dashboard_danos_${ancho}.png`), fullPage: true }); await p.close();
    continue;
  }
  const cs = sqlq(`select string_agg(ct.contrato, ',' order by ct.contrato) from (select ct.contrato from redes.contrato_tramo ct join redes.activos a on a.id = ct.activo_id where a.codigo = '${TRAMO}' order by ct.contrato limit 3) ct`).split(",");
  sqlq(`insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values ('${cs[0]}', 'colegio', 'COLEGIO', 'nombre', '${EMAILS.adm}'), ('${cs[1]}', 'clinica', 'CLINICA', 'nombre', '${EMAILS.adm}')`);

  // ===== G. Simulación: el minimapa con las válvulas numeradas (formulario de daño, operador) =====
  p = await abrir(ancho, "op"); await alGeovisor(p); await apagarNodos(p); await tocar(p, TLON, TLAT, 18); tj = await esperarTarjeta(p, "activo", new RegExp(TRAMO));
  if (!tj || !(await clicTexto(p, ".geo-tarjeta button", "Reportar daño"))) throw new Error("la tarjeta del tramo no trae «Reportar daño»: " + JSON.stringify(tj));
  await p.waitForSelector("[data-testid=panel-cierre]"); await enPanel(p, "¿Qué válvulas cierro?"); await aTotal(p); await esperarPanel(p, /Contratos sin agua/);
  await p.waitForSelector("[data-testid=cie-mapa] .cie-mapa-num", { timeout: 30000 }); s = await panel(p);
  const VALV = s.valvulas;
  r = await p.evaluate(() => { const f = document.querySelector("[data-testid=cie-mapa]"); const m = f.querySelector(".cie-mapa-lienzo").__mapa; const c = f.querySelector("canvas").getBoundingClientRect();
    return { nums: [...f.querySelectorAll(".cie-mapa-num")].map((e) => `${e.textContent}:${e.dataset.valvula}`), ancho: Math.round(c.width), alto: Math.round(c.height), fijo: !m.dragPan.isEnabled() && !m.scrollZoom.isEnabled(), pie: f.querySelector("figcaption").textContent,
      dentro: [...f.querySelectorAll(".cie-mapa-num")].every((e) => { const b = e.getBoundingClientRect(); return b.left >= c.left - 2 && b.right <= c.right + 2 && b.top >= c.top - 2 && b.bottom <= c.bottom + 2; }) }; });
  ok(`${tag} G1 el resultado de la simulación trae un minimapa con las 2 válvulas numeradas en el orden de la lista, dentro del mapa y sin interacción`, VALV.length === 2 && r.nums.join(",") === `1:${VALV[0]},2:${VALV[1]}` && r.fijo && r.dentro && r.alto >= 200, JSON.stringify(r));
  ok(`${tag} G2 el formulario con el minimapa no desborda`, await sinDesborde(p));
  await ver(p, "[data-testid=cie-resultado]"); await pausa(1800); await p.screenshot({ path: join(CAP, `simulacion_minimapa_${ancho}.png`) });
  await p.close();

  // ===== H. Dashboard distribución › Daños y fallas: «¿Qué válvulas cierro?» en el daño (supervisor de distribución) =====
  p = await alDashboard2(ancho, "dist", "Daños y fallas"); await esperarTexto(p, new RegExp(DAN));
  r = await p.evaluate(() => [...document.querySelectorAll("[data-cierre]")].map((b) => b.dataset.cierre).sort().join(","));
  ok(`${tag} H1 cada daño de acueducto trae «¿Qué válvulas cierro?»; el de alcantarillado no`, r === [DAN, DANS].sort().join(","), r);
  await p.evaluate((d) => { const b = document.querySelector(`[data-cierre="${d}"]`); b.scrollIntoView({ block: "center" }); b.click(); }, DAN);
  await p.waitForSelector("[data-testid=panel-cierre]"); await enPanel(p, "¿Qué válvulas cierro?"); await aTotal(p); await esperarPanel(p, /Contratos sin agua/); s = await panel(p);
  ok(`${tag} H2 el panel se abre dentro del daño con su código: simula y ofrece «Válvula cerrada» y «Guardar esta simulación»`, s.valvulas.join() === VALV.join() && s.botones.filter((b) => b === "Válvula cerrada").length === 2 && s.botones.includes("Guardar esta simulación") && s.alto >= 44, s.botones.join("|"));
  await enPanel(p, "Válvula cerrada", `[data-testid=panel-cierre] li[data-valvula="${VALV[0]}"]`); await p.waitForSelector("[data-testid=cie-pedir]");
  await enPanel(p, "Confirmar", "[data-testid=cie-pedir]"); await esperarPanel(p, new RegExp(`Válvula ${VALV[0]} cerrada \\(`)); await esperarPanel(p, /Válvulas cerradas por/);
  ok(`${tag} H3 desde el dashboard el supervisor marca la válvula cerrada con el daño`, sqlq(`select m.tipo || '|' || (select codigo from redes.danos where id = m.dano_id) || '|' || m.autor from redes.valvula_maniobras m`) === `cerrar|${DAN}|${EMAILS.dist}`);
  ok(`${tag} H4 el dashboard con el panel abierto no desborda`, await sinDesborde(p));
  await ver(p, "[data-testid=panel-cierre]"); await pausa(1500); await p.screenshot({ path: join(CAP, `dashboard_dano_cierre_${ancho}.png`) });
  await p.close();

  // ===== I. Geovisor: el supervisor cierra una válvula sin daño ni intervención; el operador no tiene el botón =====
  const V2 = sqlq(`select codigo || '|' || ST_X(ST_PointOnSurface(geom)) || '|' || ST_Y(ST_PointOnSurface(geom)) from redes.activo_vigente_mat where codigo = '${VALV[1]}'`).split("|");
  // 19-nov: junto a esa válvula hay otros puntos de la red (un codo a medio metro). La tesela no trae orden, y el geovisor tomaba el primero que viniera: según
  // cómo estuviera armada la base salía la tarjeta del codo (sin «Marcar válvula cerrada») y la I2 fallaba. Aquí se fuerza el orden malo (los vecinos pasan al
  // final de la tabla, que es lo que se dibuja encima) para que la prueba no dependa de la base: debe ganar el punto más cercano al dedo, que es la válvula.
  const VEC = sqlq(`select coalesce(string_agg(b.codigo, ',' order by b.codigo), '') from redes.activo_vigente_mat a join redes.activo_vigente_mat b on b.activo_id <> a.activo_id and GeometryType(b.geom) = 'POINT' and ST_DWithin(a.geom::geography, b.geom::geography, 3) where a.codigo = '${VALV[1]}'`);
  if (VEC) execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-c", "set session_replication_role = replica", "-c", `update redes.activo_vigente_mat set codigo = codigo where codigo in ('${VEC.split(",").join("','")}')`, "-c", "vacuum analyze redes.activo_vigente_mat"], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  ok(`${tag} I0 la válvula de la prueba tiene otros puntos a menos de 3 m (${VEC}): el toque debe dar el más cercano, no el primero de la tesela`, VEC.length > 0, VEC);
  p = await abrir(ancho, "op"); await alGeovisor(p); await tocar(p, Number(V2[1]), Number(V2[2]), 19); tj = await esperarTarjeta(p, "activo", new RegExp(VALV[1]));
  ok(`${tag} I1 el operador ve la tarjeta de la válvula sin «Marcar válvula cerrada»`, !!tj && new RegExp(VALV[1]).test(tj.txt) && !tj.botones.includes("Marcar válvula cerrada") && !(await p.$("[data-testid=cierre-sup]")), tj?.txt.slice(0, 40) + " · " + tj?.botones.join("|"));
  await p.close();
  p = await abrir(ancho, "dist"); await alGeovisor(p); await tocar(p, Number(V2[1]), Number(V2[2]), 19); tj = await esperarTarjeta(p, "activo", new RegExp(VALV[1]));
  ok(`${tag} I2 el supervisor de distribución tiene «Marcar válvula cerrada» en la tarjeta de la válvula`, !!tj && new RegExp(VALV[1]).test(tj.txt) && tj.botones.includes("Marcar válvula cerrada"), tj?.txt.slice(0, 40) + " · " + tj?.botones.join("|"));
  await clicTexto(p, ".geo-tarjeta button", "Marcar válvula cerrada"); await p.waitForSelector("#geo-cs-motivo");
  ok(`${tag} I3 pide el motivo (sin él no deja confirmar), la hora y el regreso estimado`, await p.evaluate(() => [...document.querySelectorAll("[data-testid=cierre-sup] button")].find((b) => /Confirmar el cierre/.test(b.textContent)).disabled && !!document.querySelector("#geo-cs-hecho") && !!document.querySelector("#geo-cs-regreso")));
  await poner(p, "#geo-cs-motivo", "Maniobra de operación de la noche"); await pausa(200); await p.screenshot({ path: join(CAP, `geovisor_cierre_supervisor_${ancho}.png`) });
  await clicTexto(p, "[data-testid=cierre-sup] button", "Confirmar el cierre"); tj = await esperarTarjeta(p, "corte_valvula", /Cerrada desde/);
  r = sqlq(`select m.tipo || '|' || (m.dano_id is null and m.intervencion_id is null) || '|' || m.motivo || '|' || m.autor from redes.valvula_maniobras m join redes.activos a on a.id = m.valvula_id where a.codigo = '${VALV[1]}'`);
  ok(`${tag} I4 queda la maniobra sin daño ni intervención, con su motivo; el geovisor pasa a «Afectaciones» y abre la tarjeta de la válvula cerrada («Maniobra del supervisor»)`, r === `cerrar|true|Maniobra de operación de la noche|${EMAILS.dist}`
     && !!tj && /Maniobra del supervisor/.test(tj.txt) && await p.evaluate(() => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === "Afectaciones").getAttribute("aria-pressed") === "true"), r + " · " + tj?.txt);

  // ===== J. «Afectaciones»: los daños abiertos de acueducto y alcantarillado, con o sin cierre =====
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForSelector("[data-testid=leyenda-danos]");
  t = await leyenda(p, "leyenda-cortes");
  ok(`${tag} J1 la leyenda agrega «Daño reportado» y dice cuántos hay: «3 daños abiertos, sin límite de fecha (acueducto y alcantarillado)»` , /Sin agua[\s\S]*Tubería cerrada[\s\S]*Válvula cerrada[\s\S]*Daño reportado/.test(t) && /3 daños abiertos, sin límite de fecha \(acueducto y alcantarillado\)/.test(t), t);
  r = await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa, ids = m.getStyle().layers.map((l) => l.id);
    return { puntos: m.getSource("x-danos").serialize().data.features.map((f) => f.properties.codigo).sort().join(","), fl: JSON.stringify(m.getFilter("x-dano-activo-l")), fp: JSON.stringify(m.getFilter("x-dano-activo-p")),
      vis: ["x-dano-activo-l", "x-dano-activo-p", "x-dano-punto"].map((c) => m.getLayoutProperty(c, "visibility")).join(","), encima: ids.indexOf("x-dano-punto") > ids.indexOf("x-corte-valvula") && ids.indexOf("x-dano-activo-l") > ids.indexOf("x-corte-cerrado") }; });
  ok(`${tag} J2 los tres daños abiertos están como puntos; el contorno «Daño reportado» va sobre el tramo de acueducto y sobre el pozo de alcantarillado (el daño sin activo, solo el punto)`, r.puntos === [DAN, DANL, DANS].sort().join(",")
     && r.fl.includes(TRAMO) && r.fl.includes(POZO) && r.fl.includes('"tramo"') && r.fp.includes(POZO) && r.fp.includes('"nodo"') && r.vis === "visible,visible,visible", JSON.stringify(r));
  ok(`${tag} J3 el daño queda encima de «tubería cerrada» y «sin agua»; el contorno es distinto (azul oscuro #0a2540, doble línea), no rojo ni naranja`, r.encima && (await pintura(p, "x-dano-activo-l", "line-color")) === '"#0a2540"'
     && (await pintura(p, "x-dano-activo-l", "line-gap-width")) === "7" && (await pintura(p, "x-dano-activo-p", "circle-stroke-color")) === '"#0a2540"' && (await pintura(p, "x-corte-cerrado", "line-color")) === '"#b3261e"');
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 16.6 }), (TLON + PLON) / 2, (TLAT + PLAT) / 2);
  const hayCont = await esperarDibujo(p, "x-dano-activo-l"), hayPozo = await esperarDibujo(p, "x-dano-activo-p"), hayPto = await esperarDibujo(p, "x-dano-punto");
  ok(`${tag} J4 en el mapa se dibujan el contorno del tramo, el del pozo, los puntos de los daños y, con el cierre, la tubería cerrada`, hayCont && hayPozo && hayPto && await esperarDibujo(p, "x-corte-cerrado"));
  await pausa(900); await p.screenshot({ path: join(CAP, `afectaciones_danos_${ancho}.png`) });
  await tocarEn(p, DLON, DLAT, 18); tj = await esperarTarjeta(p, "corte_dano", new RegExp(DAN));
  ok(`${tag} J5 tarjeta del daño de acueducto en lenguaje claro: tipo, desde cuándo, riesgo, su activo y «1 cerrada»`, !!tj && new RegExp(`Daño reportado ${DAN}`).test(tj.txt) && /Fuga o tubería rota/.test(tj.txt) && /Desde\s*\d{1,2}:\d{2}/.test(tj.txt)
     && /Riesgo\s*Medio/.test(tj.txt) && new RegExp(`Activo de acueducto\\s*${TRAMO}`).test(tj.txt) && /Válvulas cerradas\s*1 cerrada/.test(tj.txt) && tj.dentro && !/@/.test(tj.txt), tj?.txt);
  await p.screenshot({ path: join(CAP, `afectaciones_dano_tarjeta_${ancho}.png`) });
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  await tocarEn(p, PLON, PLAT, 18); tj = await esperarTarjeta(p, "corte_dano", new RegExp(DANL));
  ok(`${tag} J6 tarjeta del daño de alcantarillado: «Rebose de alcantarillado», riesgo alto, su pozo y válvulas «No aplica»`, !!tj && /Rebose de alcantarillado/.test(tj.txt) && /Riesgo\s*Alto/.test(tj.txt) && new RegExp(`Activo de alcantarillado\\s*${POZO}`).test(tj.txt) && /Válvulas cerradas\s*No aplica/.test(tj.txt), tj?.txt);
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  await tocarEn(p, SLON, SLAT, 18); tj = await esperarTarjeta(p, "corte_dano", new RegExp(DANS));
  ok(`${tag} J7 el daño sin activo: solo el punto; su tarjeta dice «Sin activo seleccionado» y «Todavía ninguna» válvula cerrada`, !!tj && /Sin activo seleccionado/.test(tj.txt) && /Válvulas cerradas\s*Todavía ninguna/.test(tj.txt), tj?.txt);
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  // volver a calcular (supervisor)
  const fotos0 = Number(sqlq("select count(*) from redes.corte_fotos"));
  await clicTexto(p, "[data-testid=leyenda-cortes] button", "Volver a calcular"); tj = await esperarTarjeta(p, "corte_recalcular", /Volver a calcular/);
  await poner(p, "#geo-recalc", "La red cambió después del cierre"); await clicTexto(p, ".geo-tarjeta button", "Volver a calcular");
  await p.waitForFunction(() => !document.querySelector(".geo-tarjeta[data-capa=corte_recalcular]"), { timeout: 40000 });
  ok(`${tag} J8 «Volver a calcular» (supervisor, con motivo) saca una foto nueva sin abrir ni cerrar válvulas`, Number(sqlq("select count(*) from redes.corte_fotos")) === fotos0 + 1 && sqlq("select count(*) from redes.valvula_maniobras") === "2");
  await modo(p, "Tipo");
  ok(`${tag} J9 fuera de «Afectaciones» el mapa queda limpio: ni contornos ni puntos de daño de ese modo`, (await p.evaluate(() => ["x-dano-activo-l", "x-dano-activo-p", "x-dano-punto"].map((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility")).join(","))) === "none,none,none");

  // ===== K. «Flujo del agua (modelo)» (supervisor) =====
  await panelCapas(p);
  ok(`${tag} K1 la capa «Flujo del agua (modelo)» está en la lista y se puede encender`, await p.evaluate(() => { const i = document.querySelector(".geo-panel [data-capa=flujo_modelo] input"); return !!i && !i.disabled && !i.checked; }));
  await cerrarPanel(p); await encender(p, "flujo_modelo"); await apagarNodos(p);
  await p.waitForSelector("[data-testid=leyenda-flujo]");
  ok(`${tag} K1b la leyenda del flujo llega ${ancho < 700 ? "plegada en el celular (deja libre el mapa)" : "abierta en el PC"}, siempre con el rótulo «Modelo, no medido»`, (await p.evaluate(() => document.querySelector(".geo-leyenda-plegar").getAttribute("aria-expanded"))) === String(ancho >= 700)
     && /Modelo, no medido/.test(await leyenda(p, "leyenda-flujo")));
  if (ancho < 700) await clicTexto(p, "[data-testid=leyenda-flujo] button", "Caudal");
  await p.waitForFunction(() => /Menos de 1/.test(document.querySelector("[data-testid=leyenda-flujo]").innerText), { timeout: 20000 });
  t = await leyenda(p, "leyenda-flujo");
  ok(`${tag} K2 leyenda: caudal en 5 clases (L/s), «Sin flujo en el modelo» y el rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)»`, /Caudal según el modelo \(L\/s\)/.test(t) && /Menos de 1[\s\S]*1 a 5[\s\S]*5 a 20[\s\S]*20 a 100[\s\S]*Más de 100[\s\S]*Sin flujo en el modelo/.test(t)
     && /Modelo, no medido \(modeloV1, Plan Maestro 2014\)/.test(t) && /no llevan flecha/.test(t), t);
  r = await p.evaluate(() => [...document.querySelectorAll("[data-testid=hora-flujo] button")].map((b) => `${b.textContent.trim()}|${b.getAttribute("aria-pressed")}|${Math.round(b.getBoundingClientRect().height)}`).join(" ; "));
  ok(`${tag} K3 selector de hora: «Hora de mayor consumo (17:00)» (elegida) y «Hora de menor consumo (23:00)», de 44 px`, r === "Hora de mayor consumo (17:00)|true|44 ; Hora de menor consumo (23:00)|false|44", r);
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 17 }), TLON, TLAT);
  const hayLin = await esperarDibujo(p, "f-flujo-l"), hayFle = await esperarDibujo(p, "f-flujo-s");
  ok(`${tag} K4 se dibujan las líneas de flujo y las flechas a lo largo de ellas (la imagen de la flecha está cargada)`, hayLin && hayFle && await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.hasImage("flecha")));
  ok(`${tag} K5 azul del acueducto (#1F5FA8), gris (#7b8b99) sin flujo y grosor por la clase de caudal`, /#1F5FA8/.test(await pintura(p, "f-flujo-l", "line-color")) && /#7b8b99/.test(await pintura(p, "f-flujo-l", "line-color"))
     && /"clase"\],1,1\.5,2,2\.5,3,4,4,6,8/.test(await pintura(p, "f-flujo-l", "line-width")), await pintura(p, "f-flujo-l", "line-width"));
  ok(`${tag} K6 la tesela se pidió con la hora «mayor»`, rpcs.some((x) => x.fn === "geoportal_redes_geovisor_mvt_flujo" && x.a.p_hora === "mayor") && !rpcs.some((x) => x.fn === "geoportal_redes_geovisor_mvt_flujo" && x.a.p_hora === "menor"));
  await pausa(900); await p.screenshot({ path: join(CAP, `flujo_modelo_${ancho}.png`) });
  if (ancho < 700) await clicTexto(p, "[data-testid=leyenda-flujo] button", "Caudal");      // se pliega para tocar el mapa
  await tocar(p, TLON, TLAT, 18); tj = await esperarTarjeta(p, "flujo", /L\/s/);
  ok(`${tag} K7 al tocar un tramo: su tarjeta con caudal y velocidad en las dos horas y el rótulo «Modelo, no medido»`, !!tj && new RegExp(TRAMO).test(tj.txt) && /Mayor consumo \(17:00\)\s*7,72 L\/s · 1,69 m\/s/.test(tj.txt) && /Menor consumo \(23:00\)\s*6,26 L\/s · 1,37 m\/s/.test(tj.txt)
     && /Modelo, no medido/.test(tj.txt) && tj.dentro, tj?.txt);
  await p.screenshot({ path: join(CAP, `flujo_tarjeta_${ancho}.png`) });
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  await clicTexto(p, "[data-testid=hora-flujo] button", "Hora de menor consumo");
  await p.waitForFunction(() => true); const fin = Date.now() + 30000; while (Date.now() < fin && !rpcs.some((x) => x.fn === "geoportal_redes_geovisor_mvt_flujo" && x.a.p_hora === "menor")) await pausa(200);
  ok(`${tag} K8 al elegir «menor consumo» la tesela se pide con la hora «menor»`, rpcs.some((x) => x.fn === "geoportal_redes_geovisor_mvt_flujo" && x.a.p_hora === "menor") && await esperarDibujo(p, "f-flujo-l"));
  ok(`${tag} K9 el geovisor con el flujo, su selector y su leyenda no desborda`, await sinDesborde(p));
  await p.close();
  p = await abrir(ancho, "op"); await alGeovisor(p); await panelCapas(p);
  ok(`${tag} K10 el operador no tiene la capa de flujo en su lista`, await p.evaluate(() => !document.querySelector(".geo-panel [data-capa=flujo_modelo]")));
  await cerrarPanel(p); await modo(p, "Afectaciones"); await p.waitForSelector("[data-testid=leyenda-danos]"); t = await leyenda(p, "leyenda-cortes");
  ok(`${tag} K11 el operador ve los daños abiertos de hoy en «Afectaciones» (su geovisor solo trae las actividades del día) y no tiene «Volver a calcular»`, /3 daños abiertos reportados hoy/.test(t) && !/Volver a calcular/.test(t), t);
  await p.close();

  // ===== L. Dashboard distribución: «Alertas de presión» (modelo, no medido) y «Usuarios sensibles» =====
  p = await alDashboard2(ancho, "dist", "Alertas de presión"); await p.waitForSelector("[data-testid=alertas-presion] .ps-niveles");
  t = await p.evaluate(() => document.querySelector(".dash-redes").innerText);
  const ap = JSON.parse(sqlq(`select public.geoportal_redes_alertas_presion('${EMAILS.dist}', 'existente')`)); const n = (x) => new Intl.NumberFormat("es-CO").format(x ?? 0);
  ok(`${tag} L1 «Alertas de presión» dice arriba «Modelo, no medido» y de dónde sale; los cuatro niveles con su límite y su conteo`, /Modelo, no medido\./.test(t) && /no vienen de sensores/.test(t) && /Plan Maestro 2014/.test(t)
     && new RegExp(`Presión baja crítica\\s*menos de 10 m\\.c\\.a\\.\\s*${n(ap.niveles.baja_roja).replace(".", "\\.")}`).test(t) && /Presión alta crítica\s*más de 60 m\.c\.a\./.test(t) && new RegExp(`De ${n(ap.nodos).replace(".", "\\.")} nodos`).test(t), t.slice(0, 700));
  ok(`${tag} L2 la tabla de los nodos más alejados del rango (15, con «Ver los ${ap.peores.length}») y la nota de la presión de trabajo «por verificar»`, (await p.$$(".ps-tabla tbody tr")).length === 15 && new RegExp(`Ver los ${ap.peores.length}`).test(t) && /por verificar con la ficha del fabricante/.test(t));
  ok(`${tag} L3 la pantalla no desborda (la tabla se desplaza dentro de su caja) y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".dash-redes .tdash-cuerpo button, .dash-redes button")) >= 44, String(await minimo(p, ".dash-redes button")));
  await p.screenshot({ path: join(CAP, `alertas_presion_${ancho}.png`), fullPage: true });
  await clicTexto(p, ".dash-redes button.dan-opcion", "Red futura"); const fin2 = Date.now() + 20000; while (Date.now() < fin2 && !rpcs.some((x) => x.fn === "geoportal_redes_alertas_presion" && x.a.p_escenario === "futura")) await pausa(200);
  ok(`${tag} L4 «Red futura» pide el otro escenario del modelo`, rpcs.some((x) => x.fn === "geoportal_redes_alertas_presion" && x.a.p_escenario === "futura"));
  await pestana(p, "Usuarios sensibles"); await p.waitForSelector("[data-testid=us-totales]"); await p.waitForSelector("[data-contrato]");
  t = await p.evaluate(() => document.querySelector(".dash-redes").innerText);
  ok(`${tag} L5 la bandeja: «2 por confirmar · 0 confirmados · 0 descartados», cada contrato con su tipo y la palabra que coincidió, y el aviso de que no hay nombres`, /2 por confirmar · 0 confirmados · 0 descartados/.test(t)
     && new RegExp(`Contrato\\s*${cs[0]}[\\s\\S]*coincidió «COLEGIO»`).test(t) && /no se guardan ni se muestran nombres/.test(t) && !/@/.test(t.replace(EMAILS.dist, "")), t.slice(0, 600));
  await p.screenshot({ path: join(CAP, `usuarios_sensibles_${ancho}.png`), fullPage: true });
  await p.evaluate((c) => [...document.querySelectorAll(`[data-contrato="${c}"] button`)].find((b) => b.textContent.trim() === "Confirmar").click(), cs[0]);
  await p.waitForFunction(() => /1 por confirmar · 1 confirmados/.test(document.querySelector("[data-testid=us-totales]")?.innerText ?? ""), { timeout: 30000 });
  ok(`${tag} L6 «Confirmar» deja el evento (solo agregar) y la bandeja se actualiza`, sqlq(`select accion || '|' || autor from redes.usuario_sensible_eventos where contrato = '${cs[0]}'`) === `confirmar|${EMAILS.dist}`);
  await p.evaluate((c) => [...document.querySelectorAll(`[data-contrato="${c}"] button`)].find((b) => b.textContent.trim() === "Descartar").click(), cs[1]);
  await p.waitForSelector(`#us-m-${cs[1]}`); await poner(p, `#us-m-${cs[1]}`, "Es una casa de familia, no una clínica");
  await p.evaluate((c) => [...document.querySelectorAll(`[data-contrato="${c}"] button`)].find((b) => b.textContent.trim() === "Descartar").click(), cs[1]);
  await p.waitForFunction(() => /0 por confirmar · 1 confirmados · 1 descartados/.test(document.querySelector("[data-testid=us-totales]")?.innerText ?? ""), { timeout: 30000 });
  ok(`${tag} L7 «Descartar» pide el motivo y lo guarda`, sqlq(`select accion || '|' || motivo from redes.usuario_sensible_eventos where contrato = '${cs[1]}'`) === "descartar|Es una casa de familia, no una clínica");
  await poner(p, "#us-contrato", cs[2]); await p.select("#us-tipo", "hospital"); await poner(p, "#us-motivo", "Centro de diálisis del barrio");
  await clicTexto(p, "[data-testid=us-agregar] button", "Agregar y confirmar");
  await p.waitForFunction(() => /2 confirmados/.test(document.querySelector("[data-testid=us-totales]")?.innerText ?? ""), { timeout: 30000 });
  ok(`${tag} L8 «Agregar un contrato» lo deja confirmado, a mano, con su tipo`, sqlq(`select origen || '|' || tipo || '|' || estado from redes.v_usuario_sensible where contrato = '${cs[2]}'`) === "manual|hospital|confirmado");
  ok(`${tag} L9 la bandeja no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".dash-redes button")) >= 44, String(await minimo(p, ".dash-redes button")));
  await p.close();
}

if (!ANTES) {
  // ===== F. La Edge: rutas de las Fases 2 y 3 (base del último ancho) =====
  const DANF = sqlq("select min(codigo) from redes.danos");
  let r = await edgeF("dist", "alertas_presion", { qs: { escenario: "existente" } });
  ok("F1 alertas_presion (GET): al supervisor, sin caché, con el aviso de MODELO; al operador, 403; escenario desconocido, 400", r.status === 200 && /MODELO/.test(r.cuerpo.aviso) && r.cache === "no-store"
     && (await edgeF("op", "alertas_presion")).status === 403 && (await edgeF("dist", "alertas_presion", { qs: { escenario: "x" } })).status === 400);
  r = await edgeF("dist", "sensibles", { qs: { estado: "confirmado" } });
  ok("F2 sensibles (GET): la bandeja sin nombres; al operador, 403; estado o límite mal escritos, 400", r.status === 200 && r.cuerpo.items.length === 2 && Object.keys(r.cuerpo.items[0]).sort().join() === "contrato,desde,estado,lat,lon,origen,palabra,tipo,tipo_nombre,tramo"
     && (await edgeF("op", "sensibles")).status === 403 && (await edgeF("dist", "sensibles", { qs: { estado: "x" } })).status === 400 && (await edgeF("dist", "sensibles", { qs: { limite: "9999" } })).status === 400, JSON.stringify(r.cuerpo).slice(0, 300));
  ok("F3 sensible_fijar rechaza por forma (contrato con letras, acción desconocida, dato de más): 400; al operador, 403", (await edgeF("dist", "sensible_fijar", { cuerpo: { contrato: "12a", accion: "confirmar" } })).status === 400
     && (await edgeF("dist", "sensible_fijar", { cuerpo: { contrato: "123", accion: "borrar" } })).status === 400 && (await edgeF("dist", "sensible_fijar", { cuerpo: { contrato: "123", accion: "confirmar", nombre: "X" } })).status === 400
     && (await edgeF("op", "sensible_fijar", { cuerpo: { contrato: "123", accion: "descartar", motivo: "No es un usuario sensible" } })).status === 403);
  r = await edgeF("op", "afectacion", { cuerpo: { registro: DANF } });
  ok("F4 afectacion (POST) de un daño con válvula cerrada: «según las válvulas cerradas», contratos y sensibles en conteos; registro mal escrito, 400; por GET, 405", r.status === 200 && r.cuerpo.fuente === "cierre_real" && r.cuerpo.contratos === 160
     && !/nombre|direccion|telefono/i.test(JSON.stringify(r.cuerpo)) && (await edgeF("op", "afectacion", { cuerpo: { registro: "DAN-1" } })).status === 400 && (await edgeF("op", "afectacion")).status === 405, JSON.stringify(r.cuerpo).slice(0, 300));
  r = await edgeF("dist", "flujo_modelo");
  ok("F5 flujo_modelo (GET): rótulo «Modelo, no medido», las dos horas y la leyenda", r.status === 200 && /Modelo, no medido/.test(r.cuerpo.rotulo) && r.cuerpo.horas.length === 2 && r.cuerpo.leyenda.clases.length === 5 && r.cache === "no-store");
  r = await edgeF("dist", "geovisor_tesela_flujo", { qs: { hora: "mayor", z: "15", x: "9716", y: "15429", v: "1" } });
  ok("F6 geovisor_tesela_flujo: MVT con caché privada y por sesión; hora desconocida o tesela fuera de rango, 400; al operador, 403", [200, 204].includes(r.status) && /mapbox-vector-tile/.test(r.tipo) && /private/.test(r.cache)
     && (await edgeF("dist", "geovisor_tesela_flujo", { qs: { hora: "pico", z: "15", x: "1", y: "1" } })).status === 400 && (await edgeF("dist", "geovisor_tesela_flujo", { qs: { hora: "mayor", z: "40", x: "1", y: "1" } })).status === 400
     && (await edgeF("op2", "geovisor_tesela_flujo", { qs: { hora: "mayor", z: "15", x: "9716", y: "15429" } })).status === 403, `${r.status} ${r.tipo}`);
  r = await edgeF("dist", "flujo_tramo", { qs: { codigo: TRAMO } });
  ok("F7 flujo_tramo (GET): caudal y velocidad del tramo en las dos horas; sin código, 400", r.status === 200 && r.cuerpo.en_modelo === true && r.cuerpo.horas.length === 2 && (await edgeF("dist", "flujo_tramo")).status === 400);
  r = await edgeF("dist", "sensores");
  ok("F8 sensores (GET): la lista (vacía hoy) con su nota", r.status === 200 && Array.isArray(r.cuerpo.sensores) && /por conectar/.test(r.cuerpo.nota));
  r = await edgeF("dist", "afectaciones_danos");
  ok("F9 afectaciones_danos (GET): todos los daños abiertos, sin caché y sin datos de personas; al operador, 403; por POST, 405", r.status === 200 && r.cuerpo.capa === "afectaciones_danos" && r.cuerpo.total === r.cuerpo.features.length && r.cache === "no-store"
     && !/nombre|telefono|direccion|descripcion|tercero/i.test(JSON.stringify(r.cuerpo)) && (await edgeF("op", "afectaciones_danos")).status === 403 && (await edgeF("dist", "afectaciones_danos", { cuerpo: {} })).status === 405, JSON.stringify(r.cuerpo).slice(0, 300));
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
