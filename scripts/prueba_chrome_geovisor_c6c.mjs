// Prueba en Chrome REAL del Corte 6c de Técnica fase 1 (la del 6b, ahora con la tesela de contratos armada al vuelo y sin copia derivada): la capa de contratos y su tarjeta (§30.1), el muestreo coloreado, los reportes de Comercial (§30.4)
// y compartir la vista con un enlace (§30.2).
// A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC de redes van a la base local REAL (PostGIS de Homebrew con la carga real,
//   la MUE, el 6a, el 6b, el hotfix de safeupdate, el 6c y 111.950 contratos SINTÉTICOS); lo de planta (mis formularios) se simula como en el 5c.
// · Antes de cada ancho, la base se rehace (base_chrome.sh) y se siembra la casilla del geovisor para zt.oper.
// Uso: node scripts/prueba_chrome_geovisor_c6c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c6c"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_geovisor_c6c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54989, P_EDGE = 54990;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c6c_"));
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
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_aviso/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
// ---- Corte 11: el inicio de Técnica va por modos (Planta, Redes y Supervisión) y ningún formulario se abre solo. Estos ayudantes buscan en cada modo.
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
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)}`); }
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
/** Todo lo que la persona tiene en el inicio (la suma de sus modos). */
const textoInicio = (p) => p.evaluate(async (sel) => {
  const tabs = [...document.querySelectorAll(sel)]; if (!tabs.length) return document.body.innerText;
  let s = ""; for (const t of tabs) { t.click(); await new Promise((x) => setTimeout(x, 0)); s += document.body.innerText + "\n"; }
  tabs[0].click(); await new Promise((x) => setTimeout(x, 0)); return s; }, TABS_MODO);
/** Abre un formulario desde su tarjeta del inicio (antes el primero se abría solo). */
const abrirFormulario = async (p, nombre) => { await esperarTexto(p, new RegExp(nombre)); if (!(await clicTexto(p, "button.tec-tarjeta-modo", nombre))) throw new Error("no está la tarjeta " + nombre); await p.waitForSelector(".tec-volver-barra"); };
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

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  // un contrato sintético activo, con ficha, en el centro
  const [C, CLON, CLAT] = sqlq("select c.cod_usuario || '|' || ST_X(c.geom) || '|' || ST_Y(c.geom) from public.catastro_valledupar c join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario where c.cod_usuario ~ '^[1-9][0-9]+$' and c.cod_usuario <> '99999999' and c.id = (select min(c2.id) from public.catastro_valledupar c2 where c2.cod_usuario = c.cod_usuario) and (select s.estado from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc limit 1) = 'ACTIVO' order by c.geom <-> ST_SetSRID(ST_MakePoint(-73.2532, 10.4631), 4326) limit 1").split("|");
  const NOMBRE = sqlq(`select nombre from public.cartera_suscripcion where contrato = '${C}' order by periodo_carga desc limit 1`);
  const CORTE = sqlq("select max(periodo_carga) from public.cartera_suscripcion");

  // ===== A. Contratos y su tarjeta (administrador) =====
  let p = await abrir(ancho, "adm");
  await alGeovisor(p);
  await encender(p, "contratos");
  await tocarEn(p, Number(CLON), Number(CLAT), 18);
  const pinta = await esperarDibujo(p, "c-contratos");
  if (process.env.DIAG) { console.log(JSON.stringify({ mvt: rpcs.filter((r) => r.fn.includes("contratos")).map((r) => r.a), vis: await visibilidad(p, "c-contratos"),
    capa: await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa; return { z: m.getZoom(), src: !!m.getSource("contratos"), lay: !!m.getLayer("c-contratos"), style: m.getStyle().layers.map((l) => l.id).slice(-8) }; }),
    edge: edgeLog.slice(-500) })); process.exit(0); }
  { const [aa, mm, dd] = [CORTE.slice(0, 4), CORTE.slice(4, 6), CORTE.slice(6, 8)]; const esperado = `${Number(dd)}-${["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"][Number(mm) - 1]}-${aa}`;
    ok(`${tag} A0 (7a) la capa de contratos trae una nota pequeña con la fecha del último corte de la cartera («Estado según la cartera del ${esperado}»), dentro de la pantalla`,
       notaCorte && notaCorte.txt === `Estado según la cartera del ${esperado}` && notaCorte.px <= 13 && notaCorte.ancho, JSON.stringify(notaCorte)); }
  ok(`${tag} A1 la capa de contratos se dibuja (desde el zoom 16), pedida con el token, sin nombres en la tesela`, pinta && rpcs.some((r) => r.fn === "geoportal_redes_geovisor_mvt_contratos" && r.a.p_solicitante === EMAILS.adm)
     && !(await p.evaluate(() => JSON.stringify(document.querySelector(".geo-mapa").__mapa.queryRenderedFeatures({ layers: ["c-contratos"] }).map((f) => f.properties)).includes("SUSCRIPTOR"))));
  await p.waitForFunction(() => document.querySelector(".geo-tarjeta")?.dataset.capa === "contrato", { timeout: 15000 }).catch(() => {});
  await p.waitForFunction(() => /Dato personal/.test(document.querySelector(".geo-tarjeta")?.innerText ?? ""), { timeout: 15000 }).catch(() => {});
  let tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} A2 tocar el contrato abre su tarjeta: número, estado, uso, «Dato personal» con nombre, dirección y barrio, el medidor y el tramo`,
     tj.includes(`Contrato ${C}`) && /Activo/.test(tj) && /Dato personal/.test(tj) && tj.includes(NOMBRE) && /Dirección/.test(tj) && /Barrio/.test(tj) && /Medidor/.test(tj), tj);
  ok(`${tag} A3 el perfil de consumo de 6 meses (con el mes sin dato) y el promedio`, (await p.$$eval(".geo-barra-mes", (b) => b.length)) === 6 && /promedio/.test(tj) && /—/.test(tj));
  ok(`${tag} A4 sin teléfono ni deuda en la pantalla`, !tj.includes("3000000000") && !tj.includes("99999") && !/deuda|saldo/i.test(tj));
  ok(`${tag} A5 la lectura quedó en la auditoría (quién y contrato), sin el nombre`, sqlq(`select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = '${EMAILS.adm}' and referencia = '${C}' and detalle::text not like '%SUSCRIPTOR%'`) === "1");
  ok(`${tag} A6 la tarjeta sin desborde y legible a lo ancho`, (await sinDesborde(p)));
  await p.screenshot({ path: join(CAP, `tarjeta_contrato_${ancho}.png`) });
  await clicTexto(p, ".geo-tarjeta button", "✕");
  ok(`${tag} A7 al cerrar la tarjeta, el nombre ya no está en la página`, !(await texto(p)).includes(NOMBRE));

  // ===== B. Muestreo con color (rangos de Salida) =====
  await p.waitForFunction(() => (document.querySelector(".geo-mapa").__mapa.getSource("g-muestreo")?.serialize().data?.features ?? []).length > 0, { timeout: 30000 }).catch(() => {});
  const mue = (await fuente(p, "g-muestreo"))?.features ?? [];
  const fuera = mue.find((f) => f.properties.calidad === "fuera");
  ok(`${tag} B1 los 27 puntos con su calidad: uno fuera (cloro 0,1), uno dentro y los demás sin muestra reciente`, mue.length === 27 && mue.filter((f) => f.properties.calidad === "fuera").length === 1
     && mue.filter((f) => f.properties.calidad === "dentro").length === 1, JSON.stringify(mue.map((f) => f.properties.calidad)));
  if (fuera) await tocarEn(p, fuera.geometry.coordinates[0], fuera.geometry.coordinates[1], 16);
  await p.waitForFunction(() => document.querySelector(".geo-tarjeta")?.dataset.capa === "muestreo", { timeout: 15000 }).catch(() => {});
  tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} B2 su tarjeta: «Fuera del rango» y el cloro con su valor, su rango de Salida (0,3 a 2) y la fecha`, /Fuera del rango/.test(tj) && /Cloro residual libre/.test(tj) && /0,1 mg\/L/.test(tj) && /rango 0.3 a 2/.test(tj) && /Salida/.test(tj), tj);
  const colorMue = await p.evaluate(() => JSON.stringify(document.querySelector(".geo-mapa").__mapa.getPaintProperty("g-muestreo", "circle-stroke-color")));
  ok(`${tag} B3 el color del punto sale de la calidad`, colorMue.includes("calidad") && colorMue.includes("#C62828"));
  await clicTexto(p, ".geo-tarjeta button", "✕");

  // ===== C. Reportes de Comercial (vacía hasta el Corte 8) y atenuar =====
  await encender(p, "reportes_comercial"); await new Promise((r) => setTimeout(r, 800));
  ok(`${tag} C1 la capa de reportes de Comercial se enciende y pide sus datos por fecha (vacía hasta el Corte 8)`, (await visibilidad(p, "g-reportes_comercial")) === "visible"
     && rpcs.some((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_capa === "reportes_comercial") && ((await fuente(p, "g-reportes_comercial"))?.features ?? [1]).length === 0);
  ok(`${tag} C2 azul con contrato y rojo posible clandestino`, JSON.stringify(await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getPaintProperty("g-reportes_comercial", "circle-color"))).includes("con_contrato"));
  await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel [data-atenuar=reportes_comercial]");
  await p.evaluate(() => document.querySelector(".geo-panel [data-atenuar=reportes_comercial]").click()); await new Promise((r) => setTimeout(r, 300));
  ok(`${tag} C3 «Atenuar» baja su opacidad (y solo esa capa tiene el botón)`, (await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getPaintProperty("g-reportes_comercial", "circle-opacity"))) === 0.3
     && (await p.$$eval(".geo-panel [data-atenuar]", (b) => b.length)) === 1);
  await clicTexto(p, ".geo-panel button", "✕");

  // ===== D. Edad: «sin fecha» con su gris propio =====
  await clicTexto(p, ".geo-seg button", "Edad");
  const ley = await p.evaluate(() => [...document.querySelectorAll(".geo-leyenda li")].map((l) => l.innerText + "=" + getComputedStyle(l.querySelector("span")).backgroundColor).join("|"));
  ok(`${tag} D1 por edad, «Sin fecha de instalación» tiene su gris propio (no el del «sin dato» del material)`, /Sin fecha de instalación=rgb\(201, 183, 156\)/.test(ley), ley);
  await clicTexto(p, ".geo-seg button", "Material");
  ok(`${tag} D2 por material, «Sin dato» sigue en el gris de antes`, /Sin dato=rgb\(167, 173, 169\)/.test(await p.evaluate(() => [...document.querySelectorAll(".geo-leyenda li")].map((l) => l.innerText + "=" + getComputedStyle(l.querySelector("span")).backgroundColor).join("|"))));

  // ===== E. Compartir la vista =====
  await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [-73.2501, 10.4702], zoom: 16.25 }));
  await clicTexto(p, ".geo-barra button", "Compartir"); await esperarTexto(p, /Compartir la vista/);
  await p.waitForSelector(".geo-enlace", { timeout: 15000 });
  const enlace = await p.evaluate(() => document.querySelector(".geo-enlace").value);
  const id = (/#geovisor=([a-z0-9]{10})$/.exec(enlace) || [])[1];
  ok(`${tag} E1 «Compartir» da un enlace #geovisor=<código> y guarda la vista (capas, colores, centro y zoom; sin datos personales)`, !!id
     && sqlq(`select colores || '|' || zoom || '|' || ('contratos' = any (capas)) || '|' || ('reportes_comercial' = any (atenuadas)) from redes.vistas_compartidas where id = '${id}'`) === "material|16.25|true|true", enlace);
  ok(`${tag} E2 el aviso dice que quien lo abra debe iniciar sesión y tener permiso`, /iniciar sesión/.test(await texto(p)) && /permiso/.test(await texto(p)));
  await p.screenshot({ path: join(CAP, `compartir_${ancho}.png`) });
  await p.close();
  // el supervisor de distribución lo abre: mismas capas, colores y lugar
  p = await abrir(ancho, "dist", `#geovisor=${id}`);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  await esperarTexto(p, /Vista compartida/);
  const cen = await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa; const c = m.getCenter(); return [c.lng, c.lat, m.getZoom()]; });
  ok(`${tag} E3 el supervisor de distribución abre el enlace: entra directo al geovisor, en el mismo lugar y zoom, con los colores por material`,
     Math.abs(cen[0] + 73.2501) < 1e-4 && Math.abs(cen[1] - 10.4702) < 1e-4 && Math.abs(cen[2] - 16.25) < 0.01 && !!(await p.$(".geo-leyenda")), JSON.stringify(cen));
  ok(`${tag} E4 … y la dirección ya no lleva el código (se consumió)`, !(await p.evaluate(() => location.hash.includes("geovisor"))));
  await p.close();
  // el operador con la casilla: sin las capas que no ve, con aviso
  p = await abrir(ancho, "op", `#geovisor=${id}`);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  await esperarTexto(p, /Vista compartida/);
  const av = await p.evaluate(() => document.querySelector(".geo-vista-aviso")?.innerText ?? "");
  ok(`${tag} E5 el operador lo abre en solo lectura: no ve contratos, muestreo ni reportes de Comercial (el aviso los nombra) y sin «Compartir»`,
     /No se muestran/.test(av) && /Contratos/.test(av) && /Puntos de muestreo/.test(av) && !/Compartir/.test(await p.evaluate(() => document.querySelector(".geo-barra").innerText)), av);
  await p.close();
  // el operador sin la casilla
  p = await abrir(ancho, "op2", `#geovisor=${id}`);
  await esperarTexto(p, /Le compartieron una vista del geovisor técnico/);
  ok(`${tag} E6 quien no tiene el geovisor recibe el aviso y no ve el mapa`, !(await p.$(".geo-mapa")));
  await p.close();

  // ===== F. El operador: sin contratos =====
  p = await abrir(ancho, "op"); await alGeovisor(p, "Geovisor técnico (solo lectura)");
  await clicTexto(p, ".geo-barra button", "Capas");
  ok(`${tag} F0 (7a) el operador no ve la nota del corte de la cartera`, (await p.evaluate(() => document.querySelector(".geo-panel [data-corte]"))) === null);
  ok(`${tag} F1 el operador no tiene la capa de contratos ni «Compartir»`, (await marcada(p, "contratos")) === null && !/Compartir/.test(await p.evaluate(() => document.querySelector(".geo-barra").innerText)));
  ok(`${tag} F2 nunca pidió la tesela ni la tarjeta de contratos`, !rpcs.some((r) => ["geoportal_redes_geovisor_mvt_contratos", "geoportal_redes_contrato_tarjeta"].includes(r.fn) && r.a.p_solicitante === EMAILS.op));
  await p.close();

  // ===== G. Entrada al geovisor desde el Dashboard distribución =====
  p = await abrir(ancho, "dist");
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /No identificados/);
  await clicTexto(p, ".tdash-cab button", "Geovisor técnico");
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 }).catch(() => {});
  ok(`${tag} G1 el Dashboard distribución tiene la entrada «Geovisor técnico»`, !!(await p.$(".geo-mapa")));
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
