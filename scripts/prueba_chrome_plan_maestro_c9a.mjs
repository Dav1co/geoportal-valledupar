// Prueba en Chrome REAL del Corte 9a de Técnica fase 1 (integración del Plan Maestro 2014), a 390 px (táctil) y 1280 px:
// · Geovisor: los sectores del Plan (encendidos al abrir), las capas de referencia (apagadas al abrir): presión de MODELO con su advertencia y su perfil horario,
//   campaña de presiones de 2014 con su gráfica de 15 min, válvulas propuestas (no son activos), pluvial existente y alternativa 2043; el operador en solo lectura no ve
//   las de supervisión; el sector del contrato (el de su tramo).
// · Ficha: «Referencia del Plan Maestro 2014» (efecto SUGERIDO de la válvula, sin tocar el oficial), el sector según el Plan y el motivo de «por verificar».
// · Dashboard distribución: la pestaña «Por verificar» (grupos, ver la ficha, marcar verificado con lo que se encontró), el «sector según Plan» del daño, y
//   «Nodos por clasificar» con lo que dice el modelo, la sugerencia, la ficha preliminar con su minimapa y «Confirmar la sugerencia» (no crea activo).
// · Las Edges corren DE VERDAD en Deno; las RPC de redes van a la base local de Code B (plantilla con el 9a y la carga real del Plan), con el rol de la API
//   (service_role) y los topes de producción (statement_timeout 30 s y lock_timeout 8 s). Puertos y base propios de Code B: no toca nada de Code A.
// Uso: node scripts/prueba_chrome_plan_maestro_c9a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c9a"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_plan_maestro_c9a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_9a> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55989, P_EDGE = 55990;      // puertos de Code B (los de Code A son 5498x)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
// cada ancho arranca de una copia limpia de la plantilla (9a + carga real del Plan Maestro), en el clúster de Code B
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
rehacer();

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c9a_"));
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
const esperarTexto = async (p, re, ms = 30000) => {
  try { await p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source); }
  catch { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)} · edge: ${edgeLog.slice(-600)} · errores: ${errores.join(" | ").slice(0, 1500)}`); }
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


// ---------- 5. Ayudantes propios del 9a ----------
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

// Para depurar: ANCHOS=390 SOLO=D node … (por omisión, los dos anchos y todas las secciones)
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const quiero = (s) => !process.env.SOLO || process.env.SOLO.includes(s);
for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  const SUB = sqlq("select m.codigo || '|' || m.nombre || '|' || ST_X(ST_PointOnSurface(m.geom)) || '|' || ST_Y(ST_PointOnSurface(m.geom)) from redes.activo_vigente_mat m where m.prefijo = 'SEC' and m.clase = 'subsector' and m.nombre like 'Subsector 4.1 %'").split("|");
  const NODO = sqlq("select n.llave || '|' || n.nombre || '|' || ST_X(n.geom) || '|' || ST_Y(n.geom) from redes.pm_nodos n join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = n.llave where n.pres_exist_mediana is not null and n.tipo = 'hidrante' order by n.llave limit 1").split("|");
  const CAMP = coord("select ST_X(geom) || '|' || ST_Y(geom) from redes.ref_elementos where capa = 'campana_2014' and llave = 'CAMP2014-P02'");
  const PROP = sqlq("select nombre || '|' || ST_X(geom) || '|' || ST_Y(geom) from redes.ref_elementos where capa = 'plan_valvulas' and nombre = 'S3-437'").split("|");
  const PLUV = sqlq("select nombre || '|' || ST_X(ST_LineInterpolatePoint(geom, 0.5)) || '|' || ST_Y(ST_LineInterpolatePoint(geom, 0.5)) from redes.ref_elementos where capa = 'pluvial' and clase = 'conducto' and ST_Length(geom::geography) > 60 order by llave limit 1").split("|");

  let p, t, tj;
  if (quiero("A")) {
  // ===== A. Geovisor del administrador: sectores y capas de referencia =====
  p = await abrir(ancho, "adm");
  await alGeovisor(p);
  await panelCapas(p);
  t = await p.evaluate(() => document.querySelector(".geo-panel").innerText);
  const REF = ["plan_valvulas", "pluvial", "pluvial_2043", "presion_modelo", "campana_2014"];
  const marcas = {}; for (const c of [...REF, "sectores"]) marcas[c] = await marcada(p, c);
  ok(`${tag} A1 la lista de capas trae las 5 de referencia del Plan (apagadas al abrir) y los sectores (encendidos), con su nota de origen`,
     REF.every((c) => marcas[c] === false) && marcas.sectores === true && /Sectores hidráulicos \(Plan Maestro 2014\)/.test(t) && /Proyectados por el Plan Maestro 2014/.test(t)
     && /Presión de modelo \(no medida\)/i.test(t) && /Válvulas propuestas por el Plan \(no instaladas\)/i.test(t) && /Campaña de presiones 2014 \(medida\)/i.test(t) && /Red pluvial existente/i.test(t), JSON.stringify(marcas) + t.slice(0, 200));
  await p.screenshot({ path: join(CAP, `capas_${ancho}.png`) });
  await cerrarPanel(p);
  ok(`${tag} A2 con las capas de referencia apagadas no se pide ninguna de sus teselas`, !rpcs.some((r) => r.fn === "geoportal_redes_geovisor_mvt_ref"));
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 14 }), Number(SUB[2]), Number(SUB[3]));
  const hayS = await esperarDibujo(p, "t-sectores-ab");
  ok(`${tag} A3 los sectores y subsectores del Plan se dibujan al abrir`, hayS && (await dibujados(p, "t-sectores-a")) > 0);
  await p.screenshot({ path: join(CAP, `sectores_${ancho}.png`) });
  await encender(p, "acu_tramos", false); await encender(p, "acu_nodos", false); await encender(p, "alc_conductos", false); await encender(p, "alc_pozos", false);
  await tocar(p, Number(SUB[2]), Number(SUB[3]), 16);
  tj = await esperarTarjeta(p, "activo", /SEC-/);
  ok(`${tag} A4 tocar dentro de un subsector abre su tarjeta (el subsector antes que el sector): código SEC, nombre y «Proyectado por el Plan Maestro 2014»`,
     tj && tj.txt.includes(SUB[0]) && /Subsector 4\.1/i.test(tj.txt) && /Proyectado por el Plan Maestro 2014/i.test(tj.txt) && tj.dentro, JSON.stringify(tj));

  // presión de modelo
  await encender(p, "presion_modelo");
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 17 }), Number(NODO[2]), Number(NODO[3]));
  const hayP = await esperarDibujo(p, "r-presion_modelo-p");
  const ley = await p.evaluate(() => document.querySelector(".geo-leyenda-presion")?.innerText ?? "");
  ok(`${tag} A5 la presión de modelo se dibuja, pedida con el token, y la leyenda advierte «Presión de modelo, no medida»`,
     hayP && /Presión de modelo, no medida/i.test(ley) && rpcs.some((r) => r.fn === "geoportal_redes_geovisor_mvt_ref" && r.a.p_capa === "presion_modelo" && r.a.p_solicitante === EMAILS.adm), ley);
  await encender(p, "sectores", false);
  await tocar(p, Number(NODO[2]), Number(NODO[3]), 18);
  tj = await esperarTarjeta(p, "ref-presion_modelo", /MODELO/);
  ok(`${tag} A6 tocar un nodo abre su tarjeta de referencia: «Presión de MODELO, no medida», mediana, el perfil horario (2 series de 25 horas) y el origen`,
     tj && /Presión de MODELO, no medida/.test(tj.txt) && /Red existente: mediana del día/i.test(tj.txt) && tj.puntos === 50 && /Origen: Plan Maestro 2014/i.test(tj.txt) && tj.dentro, JSON.stringify(tj));
  ok(`${tag} A7 la tarjeta de referencia lleva a la ficha del activo del nodo y no ofrece reportar daño ni intervención`,
     tj && tj.botones.some((b) => /^Ficha de TOR-/.test(b)) && !tj.botones.some((b) => /Reportar daño|Registrar intervención/.test(b)), JSON.stringify(tj?.botones));
  await p.screenshot({ path: join(CAP, `presion_modelo_${ancho}.png`) });
  await encender(p, "presion_modelo", false);

  // campaña de 2014
  await encender(p, "campana_2014");
  await tocar(p, CAMP[0], CAMP[1], 16);
  tj = await esperarTarjeta(p, "ref-campana_2014", /Calidad del dato/);
  ok(`${tag} A8 la campaña de 2014: tarjeta del punto 2 con «Presión MEDIDA», su gráfica de 15 min (661 lecturas), la dirección y la nota de calidad del dato`,
     tj && /Punto 2/.test(tj.txt) && /Presión MEDIDA en campo en 2014/.test(tj.txt) && tj.puntos === 661 && /Cra 19/.test(tj.txt) && /La serie es igual a la de/.test(tj.txt) && tj.dentro, JSON.stringify(tj));
  await p.screenshot({ path: join(CAP, `campana_2014_${ancho}.png`) });
  await encender(p, "campana_2014", false);

  // válvulas propuestas
  await encender(p, "plan_valvulas");
  await tocar(p, Number(PROP[1]), Number(PROP[2]), 18);
  tj = await esperarTarjeta(p, "ref-plan_valvulas", /PROPUESTA/);
  ok(`${tag} A9 una válvula propuesta: «no está instalada, no es un activo y no entra en ninguna simulación»; sin ficha ni formularios`,
     tj && tj.txt.includes(PROP[0]) && /no está instalada, no es un activo y no entra en ninguna simulación/.test(tj.txt) && !tj.botones.some((b) => /Ficha|Reportar|Registrar/.test(b)), JSON.stringify(tj));
  ok(`${tag} A10 las válvulas propuestas no son activos: ninguna «S» del Plan tiene código VAL`, sqlq("select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and codigo_anterior ~ '^S[0-9]'") === "0");
  await encender(p, "plan_valvulas", false);

  // pluvial existente y alternativa 2043
  await encender(p, "pluvial");
  await tocar(p, Number(PLUV[1]), Number(PLUV[2]), 18);
  tj = await esperarTarjeta(p, "ref-pluvial", /Conducto pluvial/);
  ok(`${tag} A11 la red pluvial existente se dibuja y su tarjeta dice qué es («Conducto pluvial») y que es una capa de referencia`,
     (await dibujados(p, "r-pluvial-l")) > 0 && tj && tj.txt.includes(PLUV[0]) && /Capa de referencia: no es un activo/.test(tj.txt), JSON.stringify(tj));
  await encender(p, "pluvial", false); await encender(p, "pluvial_2043");
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 15 }), Number(PLUV[1]), Number(PLUV[2]));
  ok(`${tag} A12 la alternativa pluvial a 2043 se dibuja al encenderla`, await esperarDibujo(p, "r-pluvial_2043-l"));
  await encender(p, "pluvial_2043", false);
  ok(`${tag} A13 sin desborde horizontal y con botones de 40 px o más`, (await sinDesborde(p)) && (await minimo(p, ".geo-barra button, .geo-seg button")) >= 40);

  // el contrato toma el sector de su tramo
  const [C, CLON, CLAT, CSEC] = sqlq(`select ct.contrato || '|' || ST_X(c.geom) || '|' || ST_Y(c.geom) || '|' || s.sector from redes.contrato_tramo ct join redes.activo_vigente_mat v on v.activo_id = ct.activo_id
      cross join lateral redes.f_sector_de(v.geom) s join public.catastro_valledupar c on c.cod_usuario = ct.contrato and c.id = (select min(c2.id) from public.catastro_valledupar c2 where c2.cod_usuario = ct.contrato)
     where s.subsector is not null and ct.contrato ~ '^[1-9][0-9]+$' and ct.contrato <> '99999999' order by ct.contrato limit 1`).split("|");
  await encender(p, "contratos");
  await tocar(p, Number(CLON), Number(CLAT), 19);
  await esperarDibujo(p, "c-contratos"); await tocar(p, Number(CLON), Number(CLAT), 19);
  tj = await esperarTarjeta(p, "contrato", /Sector según el Plan/);
  ok(`${tag} A14 la tarjeta del contrato trae el «Sector según el Plan» (el de su tramo de acueducto: ${CSEC})`, tj && tj.txt.includes(`Contrato ${C}`) && new RegExp(`Sector según el Plan\\s*${CSEC}`).test(tj.txt), JSON.stringify(tj));
  await p.close();

  }
  if (quiero("B")) {
  // ===== B. Operador en solo lectura: ve la red pluvial y los sectores; no las capas de supervisión =====
  p = await abrir(ancho, "op"); await alGeovisor(p); await panelCapas(p);
  t = await p.evaluate(() => document.querySelector(".geo-panel").innerText);
  ok(`${tag} B1 el operador en solo lectura ve «Red pluvial existente» y los sectores, y no ve presión de modelo, campaña, válvulas propuestas ni la alternativa 2043`,
     /Red pluvial existente/.test(t) && /Sectores hidráulicos/.test(t) && !/Presión de modelo|Campaña de presiones|Válvulas propuestas|alternativa a 2043/i.test(t), t.slice(0, 400));
  await p.close();

  }
  // ===== C. Dashboard distribución (supervisor): «Por verificar», la ficha con la referencia del Plan y el sector del daño =====
  const VAL = sqlq("select m.codigo || '|' || coalesce(m.efecto, '∅') || '|' || m.estado_codigo || '|' || m.version from redes.v_pm_por_verificar x join redes.activo_vigente_mat m on m.activo_id = x.activo_id where x.grupo = 'valvula' order by m.activo_id limit 1").split("|");
  const pd = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${pd.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const DANO = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${pd.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", no_identificado: `Tubo de prueba ${ancho}`, lat: Number(Number(SUB[3]).toFixed(6)), lon: Number(Number(SUB[2]).toFixed(6)),
    ubicacion_origen: "mapa", t_detectado: iso(-200), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", sector: 9, fotos: [{ n: 1, momento: "dano", ruta: pd.fotos[0].ruta }] })})`)).codigo;
  if (quiero("C")) {
  p = await alDashboard(ancho, "dist");
  await pestana(p, "Daños y fallas"); await esperarTexto(p, new RegExp(DANO));
  t = await tarjeta(p, DANO);
  ok(`${tag} C1 el daño conserva su sector escrito a mano (9) y al lado muestra el «sector según Plan» calculado por su ubicación (4, subsector 4.1)`, /sector 9 · sector según Plan 4 \(4\.1\)/.test(t), t);
  await pestana(p, "Por verificar"); await esperarTexto(p, /Todos: 1746/);
  t = await texto(p);
  ok(`${tag} C2 la bandeja «Por verificar»: 1.746 activos en 3 grupos (43 con estado distinto, 63 válvulas y 1.640 pozos), cada uno con su motivo`,
     /Estado distinto en el modelo: 43/.test(t) && /Válvulas por verificar: 63/.test(t) && /Pozos que no están en el catastro: 1640/.test(t) && /Plan Maestro 2014: /.test(t), t.slice(0, 500));
  await p.screenshot({ path: join(CAP, `por_verificar_${ancho}.png`) });
  await p.evaluate(() => document.querySelector("[data-grupo=valvula]").click()); await esperarTexto(p, new RegExp(`${VAL[0]} ·`));
  t = await tarjeta(p, VAL[0]);
  ok(`${tag} C3 el filtro «Válvulas por verificar» muestra la válvula con su motivo (modelo y catastro de 2014)`, /válvula con el estado por verificar en campo \(modelo: /.test(t), t);
  await enTarjeta(p, VAL[0], "button", "Ver la ficha"); await esperarTexto(p, /Referencia del Plan Maestro 2014/);
  t = await texto(p);
  ok(`${tag} C4 la ficha de la válvula: aviso «Por verificar en campo» con su motivo, el sector según el Plan y la sección «Referencia del Plan Maestro 2014» (datos de referencia, no de la ficha oficial)`,
     /Por verificar en campo\. Plan Maestro 2014:/.test(t) && /Sector según el Plan Maestro \(por ubicación\)/i.test(t) && /No hacen parte de la ficha oficial/.test(t) && /Origen: Plan Maestro 2014/.test(t), t.slice(0, 600));
  ok(`${tag} C5 el efecto de la válvula es SUGERIDO («Es una sugerencia…») y el «Efecto en la red» oficial sigue como estaba (${VAL[1]})`,
     /Efecto sugerido por el modelo/i.test(t) && /Es una sugerencia\. El «Efecto en la red» oficial lo define el supervisor/.test(t) && /Estado en la red existente \(modeloV1\)/i.test(t)
     && sqlq(`select coalesce(efecto, '∅') || '|' || estado_codigo || '|' || version from redes.activo_vigente_mat where codigo = '${VAL[0]}'`) === VAL.slice(1).join("|"));
  ok(`${tag} C6 la ficha con la referencia no se desborda y la presión dice «de MODELO, no medida»`, (await sinDesborde(p)) && (/Presión de MODELO, no medida/.test(t) || !/Presión de modelo/.test(t)));
  await p.screenshot({ path: join(CAP, `ficha_valvula_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Volver al Dashboard distribución"); await pestana(p, "Por verificar"); await esperarTexto(p, /Todos: 1746/);
  await p.evaluate(() => document.querySelector("[data-grupo=valvula]").click()); await esperarTexto(p, new RegExp(`${VAL[0]} ·`));
  await enTarjeta(p, VAL[0], "button", "Verificado"); await p.waitForSelector(`#pv-${VAL[0]}`);
  await poner(p, `#pv-${VAL[0]}`, "corto"); await enTarjeta(p, VAL[0], "button", "Confirmar: verificado"); await esperarTexto(p, /Escriba el motivo \(10 caracteres o más\)/);
  await poner(p, `#pv-${VAL[0]}`, `Se abrió y se cerró en campo: opera bien (${ancho})`); await enTarjeta(p, VAL[0], "button", "Confirmar: verificado");
  await esperarTexto(p, new RegExp(`${VAL[0]} quedó verificado`)); await esperarTexto(p, /Válvulas por verificar: 62/);
  ok(`${tag} C7 «Verificado» exige el motivo, guarda lo que se encontró (evento, sin cambiar la ficha) y saca el activo de la bandeja (62 válvulas)`,
     sqlq(`select tipo || '|' || autor from redes.activo_eventos e join redes.activos a on a.id = e.activo_id where a.codigo = '${VAL[0]}' order by e.id desc limit 1`) === `verificar|${EMAILS.dist}`
     && sqlq(`select coalesce(efecto, '∅') || '|' || estado_codigo || '|' || version from redes.activo_vigente_mat where codigo = '${VAL[0]}'`) === VAL.slice(1).join("|"));
  ok(`${tag} C8 el supervisor no tiene «Nodos por clasificar» (sigue siendo del administrador) y la bandeja no se desborda`, !/Nodos por clasificar/.test(await texto(p)) && (await sinDesborde(p)));
  await p.close();

  }
  if (quiero("D")) {
  // ===== D. Administrador: nodos por clasificar con ficha preliminar y sugerencia =====
  p = await alDashboard(ancho, "adm");
  await pestana(p, "Nodos por clasificar"); await esperarTexto(p, /nodos?\./);
  const total0 = Number(sqlq("select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'"));
  t = await texto(p);
  ok(`${tag} D1 la bandeja (${total0} nodos; el tanque La Popa ya es activo) muestra los grupos por sugerencia del modelo y, en cada nodo, lo que es y la sugerencia`,
     total0 === 782 && /Propuesto por el Plan: no crear activo: 500/.test(t) && /Dejar como nodo: 281/.test(t) && /En el modelo: /.test(t) && /Sugerencia: /.test(t), t.slice(0, 700));
  await p.evaluate(() => document.querySelector("[data-sugerencia=crear]").click()); await esperarTexto(p, /Pila-393/);
  t = await texto(p);
  ok(`${tag} D2 el filtro por sugerencia deja solo esos nodos («Crear el activo»: la pila pública, hidrante en el modelo)`, /1 nodo con esa sugerencia/.test(t) && /Hidrante en el modelo/.test(t) && !/S3-437/.test(t), t.slice(0, 500));
  await clicTexto(p, ".dan-opcion", "Todos"); await poner(p, "#nd-buscar", "S3-437"); await esperarTexto(p, /1 nodo con esa búsqueda\.\s+S3-437/);
  await enTarjeta(p, "S3-437", "button", "Ver ficha preliminar"); await esperarTexto(p, /Ficha preliminar · solo lectura[\s\S]*Tramos que llegan al nodo/);
  await p.waitForFunction(() => !!document.querySelector(".nodo-pre-mapa")?.__mapa, { timeout: 20000 });
  await p.waitForFunction(() => { const m = document.querySelector(".nodo-pre-mapa").__mapa; return m.loaded() && m.queryRenderedFeatures({ layers: ["tramos"] }).length > 0 && m.queryRenderedFeatures({ layers: ["nodo"] }).length > 0; }, { timeout: 30000 }).catch(() => {});
  const mini = await p.evaluate(() => { const m = document.querySelector(".nodo-pre-mapa").__mapa; return { tramos: m.queryRenderedFeatures({ layers: ["tramos"] }).length, nodo: m.queryRenderedFeatures({ layers: ["nodo"] }).length,
    alto: document.querySelector(".nodo-pre-mapa").getBoundingClientRect().height }; });
  t = await tarjeta(p, "S3-437");
  const nTr = sqlq("select count(*) from redes.v_tramo_nodos_vigente t join redes.v_nodo_vigente n on n.nodo_id in (t.nodo_ini, t.nodo_fin) where n.nombre_modelo = 'S3-437'");
  ok(`${tag} D3 la ficha preliminar (solo lectura): minimapa con el punto y los ${nTr} tramos que llegan, cada tramo con su código, material y diámetro`,
     mini.tramos > 0 && mini.nodo > 0 && mini.alto >= 200 && new RegExp(`Tramos que conecta\\s*${nTr}`).test(t) && /RED-\d{6}[^\n]*mm/.test(t), JSON.stringify(mini) + t.slice(0, 300));
  ok(`${tag} D4 la ficha preliminar dice lo que es en el modelo, su sector según el Plan, la demanda y la presión «de modelo, no medida», con la sugerencia «no crear activo»`,
     /Tipo en el modelo\s*válvula/i.test(t) && /válvula de sectorización propuesta \(no instalada\)/.test(t) && /Sector según el Plan\s*\d/.test(t)
     && /Sugerencia del modelo: Válvula propuesta por el Plan \(no instalada\): no crear activo/.test(t) && /nada se clasifica solo/.test(t), t.slice(0, 900));
  await p.screenshot({ path: join(CAP, `nodo_preliminar_${ancho}.png`), fullPage: true });
  ok(`${tag} D5 la ficha preliminar no se desborda a ${ancho} px`, await sinDesborde(p));
  const act0 = sqlq("select count(*) from redes.activos");
  await enTarjeta(p, "S3-437", "button", "Confirmar la sugerencia"); await esperarTexto(p, /Cómo queda el nodo/);
  await enTarjeta(p, "S3-437", "button", "Confirmar"); await esperarTexto(p, /Escriba el motivo \(10 caracteres o más\)/);
  await p.evaluate(() => { const s = [...document.querySelectorAll(".tec-tarjeta")].filter((x) => x.innerText.includes("S3-437")).pop(); const el = s.querySelector("input[id^=nm-]");
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, "Válvula del Plan que no se ha instalado"); el.dispatchEvent(new Event("input", { bubbles: true })); });
  await enTarjeta(p, "S3-437", "button", "Confirmar"); await esperarTexto(p, /S3-437 quedó clasificado: propuesto por el plan/i);
  ok(`${tag} D6 «Confirmar la sugerencia» pide el motivo, deja el nodo como «propuesto por el Plan», lo saca de la bandeja y NO crea ningún activo`,
     sqlq("select clase_nodo from redes.v_nodo_vigente where nombre_modelo = 'S3-437'") === "propuesta_plan" && sqlq("select count(*) from redes.activos") === act0
     && sqlq("select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'") === String(total0 - 1)
     && sqlq("select tipo || '|' || clase || '|' || autor from redes.nodo_eventos order by id desc limit 1") === `clasificar|propuesta_plan|${EMAILS.adm}`);
  await p.close();

  }
  // ===== E. Tiempos de las RPC del 9a como las ve producción (service_role, 30 s y 8 s) =====
  if (ancho === 1280) {
    const medir = (nombre, q) => { const t0 = Date.now(); execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", q], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }); tiempos.push(`${nombre} ${Date.now() - t0} ms`); return Date.now() - t0; };
    const peor = Math.max(
      medir("bandeja por verificar", `select public.geoportal_redes_por_verificar('${EMAILS.dist}', null, null, 50)`),
      medir("nodos por clasificar", `select public.geoportal_redes_nodos_por_clasificar('${EMAILS.adm}', null, null, 50)`),
      medir("ficha de una válvula", `select public.geoportal_redes_activo('${EMAILS.dist}', '${VAL[0]}')`),
      medir("tarjeta de la campaña", `select public.geoportal_redes_referencia('${EMAILS.dist}', 'campana_2014', 'CAMP2014-P02')`),
      medir("lista de daños", `select public.geoportal_redes_danos('${EMAILS.dist}', 'todos', 200)`));
    ok(`${tag} E1 las RPC del 9a responden con holgura bajo los topes de producción (la más lenta en local, con el arranque de psql: ${peor} ms)`, peor < 3000, tiempos.join(" · "));
  }
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));
ok("Z3 ninguna RPC de redes respondió con error de servidor", !rpcs.some((r) => r.error500), "");

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`TIEMPOS: ${tiempos.join(" · ")}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
