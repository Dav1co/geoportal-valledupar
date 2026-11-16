// Prueba en Chrome REAL del Corte 6a de Técnica fase 1: el geovisor técnico (N-11, N-13, N-14) y el Cargue del supervisor de distribución.
// A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC de redes van a la base local REAL (PostGIS de Homebrew con la carga real,
//   la MUE y el 6a); lo de planta (mis formularios) se simula como en el 5c.
// · Antes de cada ancho, la base se rehace (base_chrome.sh) y se siembran: la casilla del geovisor para zt.oper, un daño de hoy y un reporte del bot.
// Uso: node scripts/prueba_chrome_geovisor_c6a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c6a"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_geovisor_c6a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54987, P_EDGE = 54988;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c6a_"));
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
    const t = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt$/.test(fn) ? t : JSON.parse(t) };
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
async function abrir(ancho, rol) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(120000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");      // sin evaluar: la página puede estar cerrándose
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
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

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  // siembra: la casilla del geovisor para zt.oper; un daño de hoy sobre la red real; un reporte del bot
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  const [RED, LON, LAT] = sqlq("select m.codigo || '|' || ST_X(ST_LineInterpolatePoint(m.geom, 0.5)) || '|' || ST_Y(ST_LineInterpolatePoint(m.geom, 0.5)) from redes.activo_vigente_mat m where m.codigo_anterior = 'Distribucion-8435'").split("|");
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  const dlat = Number(LAT) + 0.0004, dlon = Number(LON);
  const dano = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", activo: RED, lat: Number(dlat.toFixed(6)), lon: Number(dlon.toFixed(6)),
    ubicacion_origen: "gps", t_detectado: new Date(Date.now() - 20 * 60000).toISOString(), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida",
    descripcion: "Avisó el vecino Pedro 3001234567", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`));
  sqlq(`select redes.f_reporte_externo_recibir(${lit({ radicado: "ZT6A-0001", canal: "telegram", tipo: "Fuga", lat: Number((Number(LAT) - 0.0004).toFixed(6)), lon: dlon, direccion: "Calle de prueba", descripcion: "La vecina Rosa", recibido_en: new Date(Date.now() - 30 * 60000).toISOString() })})`);

  // ===== A. Administrador: abre con las capas de los dos supervisores =====
  let p = await abrir(ancho, "adm");
  await alGeovisor(p);
  if (process.env.DIAG) { console.log(await p.evaluate(() => ["#raiz", ".geo", ".geo-barra", ".geo-herr", ".geo-cuerpo", ".geo-mapa"].map((s) => { const e = document.querySelector(s); const c = getComputedStyle(e); return `${s} h=${e.getBoundingClientRect().height} d=${c.display} f=${c.flex} pos=${c.position}`; }).join("\n"))); process.exit(0); }
  ok(`${tag} A1 el administrador entra al geovisor desde Técnica; dice «Administrador»`, /Geovisor técnico/.test(await texto(p)) && /Administrador/.test(await p.evaluate(() => document.querySelector(".geo-barra").innerText)));
  const pinto = await tocarEn(p, Number(LON), Number(LAT), 16).then(() => esperarDibujo(p, "t-acu_tramos-l"));
  ok(`${tag} A2 la red se dibuja con la tesela del geovisor (tramos de acueducto y conductos), pedida con el token`, pinto && (await dibujados(p, "t-alc_conductos-l")) > 0
     && rpcs.some((r) => r.fn === "geoportal_redes_geovisor_mvt" && r.a.p_solicitante === EMAILS.adm), `${await dibujados(p, "t-acu_tramos-l")} tramos`);
  await clicTexto(p, ".geo-barra button", "Capas"); await esperarTexto(p, /Volver a la vista por omisión/);
  ok(`${tag} A3 las capas por grupo; encendidas al abrir las de los dos supervisores (red, actividades, muestreo y tanques)`,
     (await marcada(p, "acu_tramos")) && (await marcada(p, "danos")) && (await marcada(p, "muestreo")) && (await marcada(p, "acu_instalaciones")) && (await marcada(p, "reportes_bot")) === false
     && /Actividades registradas/i.test(await texto(p)) && /Calidad y PQR/i.test(await texto(p)),
     JSON.stringify(await p.evaluate(() => [...document.querySelectorAll(".geo-panel [data-capa] input")].map((i) => i.closest("[data-capa]").dataset.capa + "=" + i.checked))));
  // (en la rama del 6b, contratos y reportes de Comercial dejan de ser «preparadas»: se comprueba con la presión)
  ok(`${tag} A4 las capas preparadas se ven apagadas, sin poder encenderlas y con su nota (presión «Espera el modelo hidráulico»)`,
     await p.evaluate(() => { const i = document.querySelector(".geo-panel [data-capa=presion] input"); return i && i.disabled && !i.checked; })
     && /Espera el modelo hidráulico/.test(await texto(p)) && /Reportes de Comercial/.test(await texto(p)) && /Espera el dato/.test(await texto(p)));
  ok(`${tag} A5 «Volver a la vista por omisión» empieza desactivado`, await p.evaluate(() => [...document.querySelectorAll(".geo-panel button")].find((b) => b.textContent.startsWith("Volver a la vista"))?.disabled === true));
  await p.evaluate(() => document.querySelector(".geo-panel [data-capa=acu_tramos] input").click());
  await p.evaluate(() => document.querySelector(".geo-panel [data-capa=reportes_bot] input").click());
  await new Promise((r) => setTimeout(r, 300));
  ok(`${tag} A6 apagar los tramos y prender los reportes del bot cambia el mapa (sin guardarlo en la base)`, (await visibilidad(p, "t-acu_tramos-l")) === "none" && (await visibilidad(p, "g-reportes_bot")) === "visible"
     && sqlq("select count(*) from redes.capas_por_perfil_eventos") === "0");
  await clicTexto(p, ".geo-panel button", "Volver a la vista por omisión"); await new Promise((r) => setTimeout(r, 300));
  ok(`${tag} A7 «Volver a la vista por omisión» deja todo como al abrir`, (await visibilidad(p, "t-acu_tramos-l")) === "visible" && (await visibilidad(p, "g-reportes_bot")) === "none" && (await marcada(p, "acu_tramos")));
  await p.screenshot({ path: join(CAP, `capas_${ancho}.png`) });
  await clicTexto(p, ".geo-panel button", "✕");

  // ===== B. Colores por material y por edad =====
  await clicTexto(p, ".geo-seg button", "Material");
  ok(`${tag} B1 colores por material: la leyenda trae los materiales y los tramos se pintan por el campo material`, /Material[\s\S]*PVC[\s\S]*Sin dato/.test(await p.evaluate(() => document.querySelector(".geo-leyenda")?.innerText ?? ""))
     && JSON.stringify(await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getPaintProperty("t-acu_tramos-l", "line-color"))).includes('"material"'));
  await clicTexto(p, ".geo-seg button", "Edad");
  ok(`${tag} B2 colores por edad: la leyenda por rangos de años y «Sin fecha de instalación»`, /40 años o más[\s\S]*Sin fecha de instalación/.test(await p.evaluate(() => document.querySelector(".geo-leyenda")?.innerText ?? ""))
     && JSON.stringify(await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getPaintProperty("t-acu_tramos-l", "line-color"))).includes('"edad"'));
  await p.screenshot({ path: join(CAP, `edad_${ancho}.png`) });
  await clicTexto(p, ".geo-seg button", "Tipo");
  ok(`${tag} B3 «Tipo» quita la leyenda`, !(await p.$(".geo-leyenda")));

  // ===== C. Actividades por fecha =====
  await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return (m.getSource("g-danos")?._data?.features ?? m.getSource("g-danos")?.serialize?.().data?.features ?? []).length > 0; }, { timeout: 30000 }).catch(() => {});
  const danosHoy = rpcs.filter((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_capa === "danos");
  ok(`${tag} C1 los daños de hoy se piden al abrir (desde = hasta = hoy) y el daño sembrado está en la capa, sin la descripción`,
     danosHoy.length >= 1 && danosHoy[0].a.p_desde === danosHoy[0].a.p_hasta
     && (await p.evaluate((c) => JSON.stringify(document.querySelector(".geo-mapa").__mapa.getSource("g-danos").serialize().data).includes(c), dano.codigo))
     && !(await p.evaluate(() => JSON.stringify(document.querySelector(".geo-mapa").__mapa.getSource("g-danos").serialize().data).includes("Pedro"))), JSON.stringify(danosHoy.map((r) => r.a)));
  await clicTexto(p, ".geo-seg button", "7 días"); await new Promise((r) => setTimeout(r, 1500));
  const semana = rpcs.filter((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_capa === "danos").pop();
  ok(`${tag} C2 «7 días» vuelve a pedir los daños y las intervenciones con 7 días de rango`, semana && semana.a.p_desde < semana.a.p_hasta
     && rpcs.filter((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_capa === "intervenciones" && r.a.p_desde === semana.a.p_desde).length >= 1, JSON.stringify(semana?.a));
  await clicTexto(p, ".geo-seg button", "Rango");
  await p.evaluate(() => { const [d] = document.querySelectorAll(".geo-rango input"); const s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; s.call(d, "2020-01-01"); d.dispatchEvent(new Event("input", { bubbles: true })); });
  ok(`${tag} C3 un rango de más de 12 meses no se deja pedir («máximo 12 meses»)`, /máximo 12 meses/.test(await texto(p)) && await p.evaluate(() => [...document.querySelectorAll(".geo-rango button")].find((b) => b.textContent === "Ver")?.disabled === true));
  await clicTexto(p, ".geo-seg button", "Hoy");

  // ===== D. Tarjetas =====
  await tocarEn(p, Number(LON), Number(LAT));
  await p.waitForSelector(".geo-tarjeta", { timeout: 15000 }).catch(() => {});
  let tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  const diag = await p.evaluate((lon, lat) => { const el = document.querySelector(".geo-mapa"), m = el.__mapa, r = el.getBoundingClientRect(), q = m.project([lon, lat]);
    return JSON.stringify({ r: [r.left, r.top, r.width, r.height], c: [m.getCanvas().width, m.getCanvas().height], z: m.getZoom(), q, n: m.queryRenderedFeatures([[q.x - 14, q.y - 14], [q.x + 14, q.y + 14]]).map((f) => f.layer.id).slice(0, 8),
      vis: m.getLayoutProperty("t-acu_tramos-l", "visibility") }); }, Number(LON), Number(LAT));
  ok(`${tag} D1 tocar el tramo abre su tarjeta: código, tipo con su nombre, material, diámetro, edad y estado; con «Ver ficha», «Reportar daño» y «Registrar intervención»`,
     tj.includes(RED) && /Red de distribución/.test(tj) && /Material/.test(tj) && /Diámetro/.test(tj) && /Edad/.test(tj) && /Ver ficha/.test(tj) && /Reportar daño/.test(tj) && /Registrar intervención/.test(tj), tj + " · " + diag);
  ok(`${tag} D2 la tarjeta sin desborde y con botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".geo-tarjeta button")) >= 44, `mínimo ${await minimo(p, ".geo-tarjeta button")}`);
  await p.screenshot({ path: join(CAP, `tarjeta_tramo_${ancho}.png`) });
  await clicTexto(p, ".geo-tarjeta button", "Ver ficha"); await esperarTexto(p, /Volver al mapa/);
  ok(`${tag} D3 «Ver ficha» abre la ficha del activo encima del mapa`, (await texto(p)).includes(RED) && !!(await p.$(".geo-ficha")));
  await clicTexto(p, "button", "Volver al mapa"); await p.waitForFunction(() => !document.querySelector(".geo-ficha"), { timeout: 10000 });
  ok(`${tag} D4 «Volver al mapa» regresa al mismo lugar con la tarjeta`, !!(await p.$(".geo-tarjeta")) && (await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getZoom())) > 17);
  await tocarEn(p, dlon, dlat);
  await p.waitForFunction(() => document.querySelector(".geo-tarjeta")?.dataset.capa === "danos", { timeout: 15000 }).catch(() => {});
  tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} D5 tocar el daño: su código, tipo, estado, la hora y el activo; nada de la descripción`, tj.includes(dano.codigo) && /Detectado/.test(tj) && tj.includes(RED) && !/Pedro|3001234567/.test(tj), tj);
  await clicTexto(p, ".geo-tarjeta button", "✕");
  ok(`${tag} D6 cerrar la tarjeta`, !(await p.$(".geo-tarjeta")));
  // ir a Reportar daño desde la tarjeta del tramo
  await tocarEn(p, Number(LON), Number(LAT)); await p.waitForSelector(".geo-tarjeta");
  await clicTexto(p, ".geo-tarjeta button", "Reportar daño"); await esperarTexto(p, /Daño o falla|Qué pasó|qué pasó/i);
  await esperarTexto(p, new RegExp(RED));
  ok(`${tag} D7 «Reportar daño» abre el formulario con el tramo ya elegido`, (await texto(p)).includes(RED) && !(await p.$(".geo")), (await texto(p)).slice(0, 400));
  await p.close();

  // ===== E. Capas al abrir, por perfil (administrador) =====
  p = await abrir(ancho, "adm"); await alGeovisor(p);
  await clicTexto(p, ".geo-barra button", "Capas"); await clicTexto(p, ".geo-panel button", "Capas al abrir, por perfil"); await esperarTexto(p, /Motivo del cambio/);
  await p.select(".geo-panel select", "supervisor_planta");
  await p.evaluate(() => document.querySelector(".geo-panel [data-omision=acu_tramos] input").click());
  ok(`${tag} E1 sin motivo no se guarda`, await p.evaluate(() => [...document.querySelectorAll(".geo-panel button")].find((b) => b.textContent.startsWith("Guardar"))?.disabled === true));
  await poner(p, ".geo-panel textarea", "El supervisor de planta también revisa la red");
  await clicTexto(p, ".geo-panel button", "Guardar 1 cambio"); await p.waitForFunction(() => !document.querySelector(".geo-panel textarea"), { timeout: 20000 }).catch(() => {});
  ok(`${tag} E2 el administrador enciende los tramos para el supervisor de planta: queda el evento con su motivo`,
     sqlq("select perfil || '|' || capa || '|' || despues || '|' || autor from redes.capas_por_perfil_eventos") === `supervisor_planta|acu_tramos|true|${EMAILS.adm}`);
  await p.close();

  // ===== F. Supervisor de planta: abre con muestreo y tanques (y ahora la red) =====
  p = await abrir(ancho, "planta"); await alGeovisor(p);
  await clicTexto(p, ".geo-barra button", "Capas");
  ok(`${tag} F1 el supervisor de planta abre con muestreo, tanques y (desde E2) los tramos; los daños, apagados`,
     (await marcada(p, "muestreo")) && (await marcada(p, "acu_instalaciones")) && (await marcada(p, "acu_tramos")) && (await marcada(p, "danos")) === false);
  await clicTexto(p, ".geo-panel button", "✕");
  const mue = JSON.parse(sqlq("select json_build_object('lon', u.lon, 'lat', u.lat, 'c', p.codigo) from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id where u.exactitud = 'verificada' order by p.codigo limit 1"));
  await tocarEn(p, mue.lon, mue.lat, 16);
  await p.waitForFunction(() => document.querySelector(".geo-tarjeta")?.dataset.capa === "muestreo", { timeout: 15000 }).catch(() => {});
  tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} F2 los 27 puntos de muestreo; tocar uno verificado abre su tarjeta`, rpcs.some((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_capa === "muestreo") && tj.includes(mue.c) && /Verificada/.test(tj), tj);
  await p.close();

  // ===== G. Operador con la casilla del geovisor: solo lectura =====
  p = await abrir(ancho, "op"); await alGeovisor(p, "Geovisor técnico (solo lectura)");
  ok(`${tag} G1 el operador con la casilla entra en «Solo lectura»; las actividades, solo de hoy`, /Solo lectura/.test(await p.evaluate(() => document.querySelector(".geo-barra").innerText)) && /Actividades de hoy/.test(await texto(p))
     && !(await p.evaluate(() => [...document.querySelectorAll(".geo-seg button")].some((b) => b.textContent === "7 días"))));
  await clicTexto(p, ".geo-barra button", "Capas");
  ok(`${tag} G2 sin muestreo, reportes ni capas preparadas en su lista`, (await marcada(p, "muestreo")) === null && (await marcada(p, "reportes_bot")) === null && (await marcada(p, "contratos")) === null
     && (await marcada(p, "acu_tramos")) && (await marcada(p, "danos")));
  await clicTexto(p, ".geo-panel button", "✕");
  await tocarEn(p, Number(LON), Number(LAT)); await p.waitForSelector(".geo-tarjeta", { timeout: 15000 }).catch(() => {});
  tj = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} G3 la tarjeta del tramo, sin «Ver ficha»; con «Reportar daño» y «Registrar intervención» porque los tiene asignados`, tj.includes(RED) && !/Ver ficha/.test(tj) && /Reportar daño/.test(tj) && /Registrar intervención/.test(tj), tj);
  const delOp = rpcs.filter((r) => r.fn === "geoportal_redes_geovisor_capa" && r.a.p_solicitante === EMAILS.op);
  ok(`${tag} G4 el operador pidió solo las actividades de hoy (desde = hasta = hoy), nunca otros días ni capas de supervisión`, delOp.length >= 2
     && delOp.every((r) => r.a.p_desde === r.a.p_hasta && r.a.p_desde === delOp[0].a.p_desde && ["danos", "intervenciones"].includes(r.a.p_capa)), JSON.stringify(delOp.map((r) => r.a)));
  ok(`${tag} G5 sin desborde a lo ancho`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `operador_${ancho}.png`) });
  await p.close();
  p = await abrir(ancho, "op2"); await esperarTexto(p, /Sesión de/);
  ok(`${tag} G6 el operador sin la casilla no ve el botón del geovisor`, !/Geovisor técnico/.test(await texto(p)));
  await p.close();

  // ===== H. El supervisor de distribución en el Cargue (lo pendiente del 5c) =====
  p = await abrir(ancho, "dist");
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /No identificados/);
  await clicTexto(p, "[role=tab]", "Cargue de capas"); await esperarTexto(p, /capas en 5 grupos/);
  const capa = (c) => p.evaluate((c) => document.querySelector(`[data-testid=capa-${c}]`)?.innerText ?? "", c);
  ok(`${tag} H1 el supervisor de distribución ve «Cargar versión» en sensores, sumideros y acometidas`, /Cargar versión/.test(await capa("sensores")) && /Cargar versión/.test(await capa("sumideros")) && /Cargar versión/.test(await capa("acometidas")));
  ok(`${tag} H2 en el acueducto, conductos, pozos y descargas: «La carga el administrador» y sin botón de cargar`,
     (await Promise.all(["acueducto", "alc_conductos", "alc_pozos", "alc_descargas"].map(capa))).every((t) => /La carga el administrador/.test(t) && !/Cargar versión/.test(t))
     && /solo el administrador/.test(await texto(p)) && !/en solo lectura/.test(await texto(p)));
  ok(`${tag} H3 «Cargar varias capas de un archivo» disponible (solo con sus capas)`, /Cargar varias capas de un archivo/.test(await texto(p)));
  await p.screenshot({ path: join(CAP, `cargue_supervisor_${ancho}.png`), fullPage: true });
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
