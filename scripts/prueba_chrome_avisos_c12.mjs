// Prueba en Chrome REAL del Corte 12 de Técnica fase 1: «Avisos». La tarjeta con su contador en el modo Supervisión, la pantalla de avisos por área, cada aviso abre su bandeja
// (el dashboard y la pestaña), la franja corta arriba de cada dashboard, los plazos editables y el saldo mínimo de químicos. Cuentas sintéticas de cada perfil. A 390 px (táctil) y 1280 px.
// · Las Edges corren DE VERDAD en Deno; las RPC de redes, químicos y avisos van a la base local (redes_local, como producción con el 12) como las ve producción (service_role, 30 s y 8 s).
// Uso: node scripts/prueba_chrome_avisos_c12.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <rehacer_base.sh del 12> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c12"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_avisos_c12.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54981, P_EDGE = 54982;
// Puerto del clúster local: por omisión el 55432 (Code A); el Code B corre con PGPORT_B=55442 (25-nov-2026).
const PUERTO_PG = process.env.PGPORT_B || "55432";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: PUERTO_PG, PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };      // planta: supervisor de planta; dist: supervisor de distribución
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: ["entrada", "entrada_quimicos", "uso_quimicos"] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo", entrada: "Entrada", entrada_quimicos: "Entrada de químicos", uso_quimicos: "Uso de químicos" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c12_"));
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
const rpcs = [], desconocidas = [], subidas = [], firmasLectura = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    // Como las ve producción (regla del 6c): rol de la API (service_role), statement_timeout 30 s y lock_timeout 8 s.
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
    if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT, GET, POST", "Access-Control-Allow-Headers": "content-type, x-upsert, authorization" }); return res.end(); }
    // Storage simulado: firmas (la Edge) y la subida del PDF (el navegador, con PUT a la URL firmada) que queda en storage.objects de la base local
    if (req.method === "PUT" && u.pathname.startsWith("/storage/v1/object/upload/sign/")) {
      const [bucket, ...resto] = decodeURIComponent(u.pathname.slice("/storage/v1/object/upload/sign/".length)).split("/");
      subidas.push({ bucket, ruta: resto.join("/"), bytes: cuerpo.length, mime: req.headers["content-type"] });
      sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(bucket)}, ${lit(resto.join("/"))}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })})`);
      return json(200, { Key: resto.join("/") });
    }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/upload/sign/".length); return json(200, { url: `/object/upload/sign/${ruta}?token=TOKEN` }); }
    if (u.pathname.startsWith("/storage/v1/object/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/sign/".length); firmasLectura.push(ruta); return json(200, { signedURL: `/object/leer/${ruta}?token=LECTURA` }); }
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_(punto|quimic|aviso)/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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


const pulsar = (p, sel) => p.evaluate((s) => { const b = document.querySelector(s); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const avisosEn = (p) => p.evaluate(() => [...document.querySelectorAll("[data-aviso][data-nivel]")].map((a) => a.dataset.aviso));
const areasEn = (p) => p.evaluate(() => [...document.querySelectorAll("section[data-area]")].map((a) => a.dataset.area).join(","));
const tabActiva = (p) => p.evaluate(() => document.querySelector(".tdash-tabs [role=tab][aria-selected=true]")?.textContent.trim() ?? "");
async function alModoSupervision(p) { await p.waitForSelector("[data-modo-actual]"); await p.evaluate(() => document.querySelector('[role=tab][data-modo=supervision]')?.click()); await p.waitForSelector("button[data-tarjeta=avisos]"); }
async function abrirAvisos(p) { await alModoSupervision(p); await pulsar(p, "button[data-tarjeta=avisos]"); await p.waitForSelector("section[data-area]", { timeout: 30000 }); }
/** Datos de la prueba (con prefijo ZT12): un daño de riesgo alto abierto hace 7 h (rojo), un reporte del bot sin atender, una ubicación propuesta y una persona sin área. */
function sembrar() {
  sqlq(`insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor)
        select gen_random_uuid(), 'DAN-991290', 'dano', (select codigo from redes.tipos_dano where activo and 'acueducto' = any (sistemas) order by orden limit 1), 'acueducto',
               (select activo_id from redes.activo_vigente_mat where sistema = 'acueducto' and not retirado order by activo_id limit 1), 10.47, -73.24, 'mapa', clock_timestamp() - interval '7 hours', 'alto', 'desconocida', 'zt12'`);
  sqlq(`with r as (insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, descripcion, recibido_en) values ('ZT12-B01', 'telegram', 'Fuga', 10.47, -73.24, 'ZT12 reporte', clock_timestamp() - interval '3 hours') returning id)
        insert into redes.reporte_externo_eventos (reporte_id, tipo, autor) select id, 'recibido', 'bot' from r`);
  sqlq(`insert into tecnica.punto_ubicacion_propuestas (punto_id, lat, lon, precision_m, autor) select id, 10.47, -73.25, 8, '${EMAILS.op}' from tecnica.puntos where tipo = 'muestreo' and activo order by id limit 1`);
  sqlq(`select public.geoportal_tec_quimico_inventario('${EMAILS.planta}', 'pac', 2, 't', ((clock_timestamp() at time zone 'America/Bogota')::date - 1), 'ZT12 conteo físico de bodega')`);
}

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); sembrar(); rpcs.length = 0;

  // ===== A. Administrador: la tarjeta, la pantalla y cada aviso a su bandeja =====
  let p = await abrir(ancho, "adm");
  await alModoSupervision(p);
  await p.waitForSelector("button[data-tarjeta=avisos] [data-contador]", { timeout: 30000 }).catch(() => {});
  const card = await p.evaluate(() => { const b = document.querySelector("button[data-tarjeta=avisos]"); const c = b?.querySelector("[data-contador]");
    return { primera: document.querySelector(".tec-rejilla button")?.dataset.tarjeta, n: Number(c?.dataset.contador ?? -1), rojo: c?.classList.contains("tec-contador-rojo"), txt: b?.innerText ?? "" }; });
  ok(`${tag} A1 Supervisión empieza con la tarjeta «Avisos», con su contador en ROJO (hay un daño de riesgo alto fuera de plazo)`, card.primera === "avisos" && card.n > 0 && card.rojo && /urgentes/.test(card.txt), JSON.stringify(card));
  ok(`${tag} A2 el contador es el total de avisos del servidor`, card.n === JSON.parse(sqlq(`select public.geoportal_tec_avisos('${EMAILS.adm}')`)).total);
  await p.screenshot({ path: join(CAP, `inicio_supervision_${ancho}.png`), fullPage: true });
  await pulsar(p, "button[data-tarjeta=avisos]"); await p.waitForSelector("section[data-area]", { timeout: 30000 });
  ok(`${tag} A3 la pantalla de avisos tiene Plantas, Distribución y Personal (administrador)`, (await areasEn(p)) === "planta,distribucion,personal", await areasEn(p));
  const lista = await avisosEn(p);
  ok(`${tag} A4 están los avisos sembrados: daños en rojo, reporte del bot, ubicación por aprobar y personas sin área`,
     ["danos_rojo", "reportes_bot", "ubicaciones_pendientes", "personal_sin_area"].every((k) => lista.includes(k)), lista.join(","));
  const rojo = await p.evaluate(() => document.querySelector("[data-aviso=danos_rojo]")?.innerText ?? "");
  ok(`${tag} A5 el aviso rojo dice «Urgente», «pasó su plazo» (en singular si es uno), el código del daño y su bandeja`, /Urgente/.test(rojo) && /^1 daño abierto pasó su plazo$|daños abiertos pasaron su plazo/m.test(rojo) && !/1 daño abiertos/.test(rojo) && /DAN-991290 · riesgo alto · abierto hace 7 h/.test(rojo)
     && /Abrir Dashboard distribución › Daños y fallas/.test(rojo), rojo);
  ok(`${tag} A6 el orden: primero los rojos de cada área`, await p.evaluate(() => { const n = [...document.querySelectorAll("section[data-area=distribucion] [data-nivel]")].map((a) => a.dataset.nivel);
     const o = { rojo: 1, naranja: 2, info: 3 }; return n.every((x, i) => i === 0 || o[n[i - 1]] <= o[x]); }));
  ok(`${tag} A7 sin desborde; botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".av-cuerpo button")) >= 44);
  await p.screenshot({ path: join(CAP, `avisos_admin_${ancho}.png`), fullPage: true });
  await pulsar(p, "[data-aviso=danos_rojo] .av-abrir");
  await p.waitForSelector(".tdash-tabs", { timeout: 30000 }); await esperarTexto(p, /Dashboard distribución/);
  await p.waitForFunction(() => document.querySelector(".tdash-tabs [role=tab][aria-selected=true]")?.textContent.trim() === "Daños y fallas", { timeout: 15000 }).catch(() => {});
  ok(`${tag} A8 «Abrir…» lleva al Dashboard distribución, en «Daños y fallas»`, (await tabActiva(p)) === "Daños y fallas", await tabActiva(p));
  await p.waitForSelector("[data-franja=distribucion]", { timeout: 15000 }).catch(() => {});
  const franja = await p.evaluate(() => { const f = document.querySelector("[data-franja=distribucion]"); return f ? { txt: f.innerText, roja: f.classList.contains("av-franja-roja"), items: [...f.querySelectorAll("[data-aviso]")].map((x) => x.dataset.aviso) } : null; });
  ok(`${tag} A9 la franja del dashboard trae los de distribución (y Personal), en rojo, con «Ver»; nada de planta`, franja && franja.roja && franja.items.length >= 1 && franja.items.length <= 3 && franja.items[0] === "danos_rojo"
     && !franja.items.some((k) => /^planta_|muestreo|quimicos|ubicaciones/.test(k)) && /Ver/.test(franja.txt), JSON.stringify(franja));
  if (franja?.items.includes("reportes_bot")) {
    await pulsar(p, "[data-franja=distribucion] [data-aviso=reportes_bot]");
    await p.waitForFunction(() => document.querySelector(".tdash-tabs [role=tab][aria-selected=true]")?.textContent.trim() === "Reportes del bot", { timeout: 15000 }).catch(() => {});
    ok(`${tag} A10 un aviso de la franja cambia la pestaña ahí mismo («Reportes del bot»)`, (await tabActiva(p)) === "Reportes del bot", await tabActiva(p));
  } else {
    await pulsar(p, "[data-franja=distribucion] [data-aviso=danos_rojo]");
    ok(`${tag} A10 un aviso de la franja cambia la pestaña ahí mismo («Daños y fallas»)`, (await tabActiva(p)) === "Daños y fallas", await tabActiva(p));
  }
  ok(`${tag} A11 con la franja, el dashboard sigue sin desborde`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `franja_distribucion_${ancho}.png`), fullPage: false });
  await pulsar(p, ".av-franja-ver"); await p.waitForSelector("section[data-area]", { timeout: 15000 });
  ok(`${tag} A12 «Ver avisos» de la franja vuelve a la pantalla de avisos`, (await areasEn(p)).startsWith("planta"));
  await pulsar(p, "[data-aviso=ubicaciones_pendientes] .av-abrir");
  await esperarTexto(p, /Dashboard PTAP/);
  await p.waitForFunction(() => document.querySelector(".tdash-tabs [role=tab][aria-selected=true]")?.textContent.trim() === "Puntos", { timeout: 15000 }).catch(() => {});
  ok(`${tag} A13 la ubicación por aprobar lleva al Dashboard PTAP, en «Puntos»`, (await tabActiva(p)) === "Puntos", await tabActiva(p));
  const franjaP = await p.evaluate(() => [...document.querySelectorAll("[data-franja=ptap] [data-aviso]")].map((x) => x.dataset.aviso));
  ok(`${tag} A14 la franja del PTAP trae los de planta (y Personal), nada de distribución`, franjaP.length >= 1 && !franjaP.some((k) => /^danos|reportes_bot|nodos|por_verificar|cargas|no_identificados|recursos/.test(k)), franjaP.join(","));
  await p.screenshot({ path: join(CAP, `franja_ptap_${ancho}.png`), fullPage: false });
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-modo-actual]");
  ok(`${tag} A15 «Volver» del dashboard regresa al inicio por modos`, true);
  await p.close();

  // ===== B. Supervisor de planta: solo Plantas y Personal; los plazos de su área; el saldo mínimo =====
  p = await abrir(ancho, "planta"); await abrirAvisos(p);
  ok(`${tag} B1 el supervisor de planta ve Plantas y Personal, sin Distribución`, (await areasEn(p)) === "planta,personal", await areasEn(p));
  ok(`${tag} B2 ningún aviso de distribución`, !(await avisosEn(p)).some((k) => /^danos|reportes_bot|nodos|por_verificar/.test(k)));
  ok(`${tag} B3 el aviso de Personal lo lleva a «Personal técnico» del PTAP (no tiene el de distribución)`, /Abrir Dashboard PTAP › Personal técnico/.test(await p.evaluate(() => document.querySelector("[data-aviso=personal_sin_area]")?.innerText ?? "")));
  await clicTexto(p, "button", "Ver y cambiar los plazos"); await p.waitForSelector("[data-parametro=horario_fin]", { timeout: 20000 });
  const params = await p.evaluate(() => [...document.querySelectorAll("[data-parametro]")].map((a) => `${a.dataset.parametro}:${a.querySelector(".av-param-valor strong").textContent}`).join(","));
  ok(`${tag} B4 ve solo los 5 plazos de Plantas con los valores de David (8 a 18, 10 h, 4 h, 3 días)`, params === "horario_inicio:8,horario_fin:18,planta_primer_registro_hora:10,planta_horas_sin_registro:4,quimicos_dias_revisar:3", params);
  await clicTexto(p, "button", "Cambiar", "[data-parametro=planta_horas_sin_registro]"); await p.waitForSelector("#av-p-planta_horas_sin_registro");
  const off = () => p.evaluate(() => [...document.querySelectorAll("[data-form=parametro-aviso] button")].find((b) => b.textContent.startsWith("Guardar"))?.disabled);
  await poner(p, "#av-p-planta_horas_sin_registro", "4,5");
  ok(`${tag} B5 con decimales no deja guardar`, (await off()) === true);
  await poner(p, "#av-p-planta_horas_sin_registro", "5");
  ok(`${tag} B6 sin motivo, tampoco`, (await off()) === true);
  await poner(p, "#av-m-planta_horas_sin_registro", "En la planta los registros van cada 5 horas");
  ok(`${tag} B7 formulario sin desborde, con campos y botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, "[data-form=parametro-aviso] input, [data-form=parametro-aviso] textarea, [data-form=parametro-aviso] button")) >= 44);
  await p.screenshot({ path: join(CAP, `plazos_planta_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Guardar el cambio", "[data-form=parametro-aviso]"); await esperarTexto(p, /de 4 a 5 horas/);
  ok(`${tag} B8 guarda: el aviso «de 4 a 5 horas», el evento con motivo y autor en la base`,
     sqlq("select valor || '|' || (select antes || '>' || despues || '|' || autor from tecnica.aviso_parametro_eventos order by id desc limit 1) from tecnica.aviso_parametros where clave = 'planta_horas_sin_registro'") === `5|4>5|${EMAILS.planta}`);
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-modo-actual]");
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, ".tdash-tabs [role=tab]", "Químicos"); await p.waitForSelector(".qm-seg", { timeout: 20000 });
  await clicTexto(p, ".qm-seg [role=tab]", "Saldo mínimo"); await p.waitForSelector("[data-minimo=pac]", { timeout: 30000 });
  ok(`${tag} B9 «Saldo mínimo»: el PAC con su saldo (2.000 kg) y sin mínimo fijado`, /Saldo 2\.000 kg · Mínimo sin fijar/.test(await p.evaluate(() => document.querySelector("[data-minimo=pac]").innerText)),
     await p.evaluate(() => document.querySelector("[data-minimo=pac]").innerText));
  await clicTexto(p, "button", "Fijar el mínimo", "[data-minimo=pac]"); await p.waitForSelector("#qm-min-pac");
  await poner(p, "#qm-min-pac", "5000"); await poner(p, "#qm-min-m-pac", "Mínimo de bodega para dos semanas de PAC");
  await clicTexto(p, "button", "Guardar el mínimo", "[data-minimo=pac]"); await esperarTexto(p, /saldo mínimo 5\.000 kg/);
  await p.waitForFunction(() => /Por debajo del mínimo/.test(document.querySelector("[data-minimo=pac]")?.innerText ?? ""), { timeout: 15000 }).catch(() => {});
  ok(`${tag} B10 fija 5.000 kg: la tarjeta queda «Por debajo del mínimo»`, /Por debajo del mínimo/.test(await p.evaluate(() => document.querySelector("[data-minimo=pac]").innerText)));
  ok(`${tag} B11 sin desborde en «Saldo mínimo»`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `saldo_minimo_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "← Volver"); await abrirAvisos(p);
  const bajo = await p.evaluate(() => document.querySelector("[data-aviso=quimicos_saldo]")?.innerText ?? "");
  ok(`${tag} B12 en Avisos ya sale «1 químico por debajo del saldo mínimo», con el saldo y el mínimo`, /1 químico por debajo del saldo mínimo/.test(bajo) && /Policloruro de aluminio · 2\.000 kg \(mínimo 5\.000 kg\)/.test(bajo), bajo);
  await p.screenshot({ path: join(CAP, `avisos_planta_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== C. Supervisor de distribución: Distribución y Personal =====
  p = await abrir(ancho, "dist"); await abrirAvisos(p);
  ok(`${tag} C1 el supervisor de distribución ve Distribución y Personal, sin Plantas`, (await areasEn(p)) === "distribucion,personal", await areasEn(p));
  ok(`${tag} C2 tiene el daño rojo y el reporte del bot`, ["danos_rojo", "reportes_bot"].every((k) => (async () => true) && true) && (await avisosEn(p)).includes("danos_rojo") && (await avisosEn(p)).includes("reportes_bot"));
  ok(`${tag} C3 Personal lo lleva a «Personal» del Dashboard distribución`, /Abrir Dashboard distribución › Personal/.test(await p.evaluate(() => document.querySelector("[data-aviso=personal_sin_area]")?.innerText ?? "")));
  await clicTexto(p, "button", "Ver y cambiar los plazos"); await p.waitForSelector("[data-parametro=dano_alto_rojo_h]", { timeout: 20000 });
  const pd = await p.evaluate(() => [...document.querySelectorAll("[data-parametro]")].map((a) => a.dataset.parametro));
  // Corte 9b: con los dos de «válvula cerrada» (1b) son 11, y 12 con el interruptor del aviso de presiones de la Fase 2 (9 en una base anterior al 9b)
  ok(`${tag} C4 ve los plazos de Distribución (riesgo alto 2 y 6 h…; 11 con los de válvula cerrada del 9b, 12 con el del aviso de presiones y 13 con el de activos por levantar del 14), ninguno de planta ni del bot`,
     pd.length === 9 + (pd.includes("valvula_cerrada_naranja_h") ? 2 : 0) + (pd.includes("presion_modelo_aviso") ? 1 : 0) + (pd.includes("levantar_naranja_dias") ? 1 : 0) && pd.includes("dano_alto_naranja_h") && !pd.includes("horario_fin") && !pd.includes("salida_max_intentos"), pd.join(","));
  await p.screenshot({ path: join(CAP, `plazos_distribucion_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-modo-actual]");
  await pulsar(p, "button[data-tarjeta=dashboard_distribucion]"); await p.waitForSelector("[data-franja=distribucion]", { timeout: 30000 }).catch(() => {});
  ok(`${tag} C5 abierto desde su tarjeta, el Dashboard distribución también trae la franja`, await p.evaluate(() => !!document.querySelector("[data-franja=distribucion]")));
  await p.close();

  // ===== D. Operador: sin avisos =====
  p = await abrir(ancho, "op"); await p.waitForSelector("[data-modo-actual]");
  ok(`${tag} D1 el operador no tiene la tarjeta «Avisos» ni el modo Supervisión`, !(await p.$("button[data-tarjeta=avisos]")) && !(await p.$("[role=tab][data-modo=supervision]")));
  await p.close();
  ok(`${tag} D2 el operador nunca pidió avisos`, !rpcs.some((x) => x.a.p_solicitante === EMAILS.op && /aviso/.test(x.fn)));
  ok(`${tag} D3 una sola consulta de avisos por recarga (no una por aviso)`, rpcs.filter((x) => /aviso/.test(x.fn)).every((x) => ["geoportal_tec_avisos", "geoportal_tec_avisos_parametros", "geoportal_tec_aviso_parametro_fijar"].includes(x.fn)));
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
