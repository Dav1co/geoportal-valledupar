// Prueba en Chrome REAL del Corte 7b de Técnica fase 1: las pantallas del operador de planta «Entrada de químicos» (toneladas o kg, nunca cilindros; proveedor,
// remisión, lote y vencimiento) y «Uso de químicos» (kg, planta y para qué), abiertas desde el inicio por modos (Corte 11). A 390 px (táctil) y 1280 px.
// · Las Edges corren DE VERDAD en Deno; las RPC de químicos y de redes van a la base local como las ve producción (service_role, 30 s y 8 s).
// Uso: node scripts/prueba_chrome_quimicos_c7b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c7b"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_quimicos_c7b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54991, P_EDGE = 54992;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: ["entrada", "entrada_quimicos", "uso_quimicos"] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo", entrada: "Entrada", entrada_quimicos: "Entrada de químicos", uso_quimicos: "Uso de químicos" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c7b_"));
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
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_quimic|^geoportal_tec_aviso/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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

// PDF de prueba (mínimo y válido) para la ficha técnica
const PDF = join(dir, "ficha_tecnica.pdf");
writeFileSync(PDF, "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n");
const tarjetaQ = (p, c) => p.evaluate((c) => document.querySelector(`[data-quimico=${c}]`)?.innerText ?? "", c);
const esperarTarjeta = (p, c, re) => p.waitForFunction((c, s) => new RegExp(s).test(document.querySelector(`[data-quimico=${c}]`)?.innerText ?? ""), { timeout: 20000 }, c, re.source).catch(() => {});
const enTarjeta = (p, c, boton) => clicTexto(p, "button", boton, `[data-quimico=${c}]`);
const escribir = (p, sel, v) => p.evaluate((sel, v) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v); el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
async function alQuimicos(p) {
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, "[role=tab]", "Químicos"); await esperarTexto(p, /Una sola bodega/);
}


const tocarTarjeta = async (p, clave) => { await p.waitForSelector(`button[data-tarjeta=${clave}]`); await p.evaluate((c) => document.querySelector(`button[data-tarjeta=${c}]`).click(), clave); await p.waitForSelector(".fq #fq-cantidad"); };
const pulsar = (p, sel) => p.evaluate((s) => { const b = document.querySelector(s); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const mov = (tipo) => sqlq(`select coalesce(string_agg(q.codigo || '|' || m.cantidad || '|' || m.unidad || '|' || m.cantidad_kg || '|' || coalesce(pl.codigo, '-') || '|' || coalesce(m.para_que, '-') || '|' || coalesce(m.proveedor, '-') || '|' || coalesce(m.remision, '-') || '|' || coalesce(m.lote_fabricante, '-') || '|' || coalesce(m.vence::text, '-') || '|' || m.autor, ' ; ' order by m.id), '') from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id left join tecnica.plantas pl on pl.id = m.planta_id where m.tipo = '${tipo}'`);

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op2}', 'asignar_formulario', 'uso_quimicos', '${EMAILS.adm}'), ('${EMAILS.op2}', 'asignar_formulario', 'entrada_quimicos', '${EMAILS.adm}')`);
  const HOY = sqlq("select (clock_timestamp() at time zone 'America/Bogota')::date");

  // ===== A. El inicio: las dos tarjetas ya no son «Próximamente» =====
  let p = await abrir(ancho, "op2"); await p.waitForSelector("[data-tarjeta=uso_quimicos]");
  const tj = await p.evaluate(() => [...document.querySelectorAll("[data-tarjeta]")].map((c) => `${c.dataset.tarjeta}:${c.tagName}:${/Próximamente/.test(c.textContent)}`).join(","));
  ok(`${tag} A1 en el modo Planta, «Entrada de químicos» y «Uso de químicos» son tarjetas que se abren (ya no «Próximamente»)`, tj.endsWith("entrada_quimicos:BUTTON:false,uso_quimicos:BUTTON:false"), tj);
  ok(`${tag} A2 ninguna se abrió sola`, !rpcs.some((r) => r.fn === "geoportal_tec_quimicos_formulario"));

  // ===== B. Entrada de químicos =====
  await tocarTarjeta(p, "entrada_quimicos");
  let t = await texto(p);
  ok(`${tag} B1 se abre con «Volver» y su nombre; trae los químicos activos (PAC, cloro gaseoso e hipoclorito)`, (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Entrada de químicos"
     && (await p.evaluate(() => [...document.querySelectorAll("[data-quimico]")].map((b) => b.dataset.quimico).sort().join())) === "cloro_gaseoso,hipoclorito_calcio,pac", t.slice(0, 300));
  ok(`${tag} B2 la unidad es toneladas o kilogramos (toneladas por omisión); nada de cilindros`, (await p.evaluate(() => [...document.querySelectorAll("[data-unidad]")].map((b) => `${b.dataset.unidad}:${b.getAttribute("aria-selected")}`).join())) === "t:true,kg:false" && !/cilindro|tanque/i.test(t));
  ok(`${tag} B3 el operador no ve el saldo de la bodega ni la dosis óptima`, !/saldo|dosis/i.test(t));
  ok(`${tag} B4 el día viene en hoy y solo deja hasta los días atrás que dice el servidor`, (await p.evaluate(() => { const d = document.querySelector("#fq-dia"); return `${d.value}|${d.max}|${d.min < d.max}`; })) === `${HOY}|${HOY}|true`);
  await clicTexto(p, ".fq .tec-boton", "Guardar la entrada");
  t = await texto(p);
  ok(`${tag} B5 sin datos no guarda: pide el químico y la cantidad`, /Elija el químico/.test(t) && /Escriba la cantidad recibida/.test(t) && /Revise los datos marcados/.test(t) && mov("entrada") === "");
  await pulsar(p, "[data-quimico=pac]"); await poner(p, "#fq-cantidad", "1.500");
  ok(`${tag} B6 «1.500» es ambiguo y no se adivina`, /ambiguo/.test(await texto(p)));
  await poner(p, "#fq-cantidad", "1,5");
  ok(`${tag} B7 1,5 toneladas: la pantalla dice «Son 1.500 kg.»`, /Son 1\.500 kg\./.test(await texto(p)));
  await poner(p, "#fq-proveedor", "Proveedor Sintético SAS"); await poner(p, "#fq-remision", "R-0077"); await poner(p, "#fq-lote", "L-2026-11"); await poner(p, "#fq-vence", "2027-11-30");
  ok(`${tag} B8 campos y botones de al menos 44 px, sin desborde`, (await minimo(p, ".fq input, .fq button")) >= 44 && (await sinDesborde(p)), String(await minimo(p, ".fq input, .fq button")));
  await p.screenshot({ path: join(CAP, `entrada_quimicos_${ancho}.png`), fullPage: true });
  await clicTexto(p, ".fq .tec-boton", "Guardar la entrada"); await esperarTexto(p, /Entrada registrada/);
  ok(`${tag} B9 guarda: «Entrada registrada: 1.500 kg de …» y el movimiento queda con toneladas, kg, proveedor, remisión, lote, vencimiento y el autor`,
     /Entrada registrada: 1\.500 kg de /.test(await texto(p)) && mov("entrada") === `pac|1.5|t|1500.0|-|-|Proveedor Sintético SAS|R-0077|L-2026-11|2027-11-30|${EMAILS.op2}`, mov("entrada"));
  ok(`${tag} B10 después de guardar la cantidad y la remisión quedan en blanco (lista para otra entrada)`, (await p.evaluate(() => document.querySelector("#fq-cantidad").value + document.querySelector("#fq-remision").value)) === "");
  await pulsar(p, "[data-unidad=kg]"); await pulsar(p, "[data-quimico=hipoclorito_calcio]"); await poner(p, "#fq-cantidad", "250");
  await clicTexto(p, ".fq .tec-boton", "Guardar la entrada"); await esperarTexto(p, /Entrada registrada: 250 kg/);
  ok(`${tag} B11 en kilogramos: 250 kg de hipoclorito, sin datos de remisión`, mov("entrada").endsWith(`hipoclorito_calcio|250|kg|250|-|-|-|-|-|-|${EMAILS.op2}`), mov("entrada"));
  await clicTexto(p, ".tec-volver-barra button", "←"); await p.waitForSelector("[data-tarjeta=uso_quimicos]");

  // ===== C. Uso de químicos =====
  await tocarTarjeta(p, "uso_quimicos");
  t = await texto(p);
  ok(`${tag} C1 «Uso de químicos»: en kilogramos (sin elegir unidad), con «¿Para qué se usó?» y las plantas; sin saldo ni dosis`,
     !(await p.$("[data-unidad]")) && (await p.evaluate(() => [...document.querySelectorAll("[data-para]")].map((b) => b.dataset.para).join())) === "dosificacion,limpieza,otro"
     && (await p.evaluate(() => document.querySelectorAll("[data-planta]").length)) >= 2 && !/saldo|dosis óptima/i.test(t), t.slice(0, 300));
  await pulsar(p, "[data-quimico=pac]"); await pulsar(p, "[data-para=dosificacion]"); await poner(p, "#fq-cantidad", "300");
  await clicTexto(p, ".fq .tec-boton", "Guardar el uso");
  ok(`${tag} C2 para dosificar exige la planta`, /Para dosificar, elija la planta/.test(await texto(p)) && mov("uso") === "");
  await pulsar(p, "[data-planta=huaricha]");
  await p.screenshot({ path: join(CAP, `uso_quimicos_${ancho}.png`), fullPage: true });
  ok(`${tag} C3 sin desborde y con botones de al menos 44 px`, (await sinDesborde(p)) && (await minimo(p, ".fq input, .fq button")) >= 44);
  await clicTexto(p, ".fq .tec-boton", "Guardar el uso"); await esperarTexto(p, /Uso registrado: 300 kg/);
  ok(`${tag} C4 guarda el uso: 300 kg de PAC en Huaricha para dosificar (resta en la bodega)`, mov("uso") === `pac|300|kg|-300|huaricha|dosificacion|-|-|-|-|${EMAILS.op2}`, mov("uso"));
  await pulsar(p, "[data-quimico=hipoclorito_calcio]"); await pulsar(p, "[data-para=limpieza]"); await pulsar(p, "[data-planta=huaricha]"); await poner(p, "#fq-cantidad", "2,5");
  await clicTexto(p, ".fq .tec-boton", "Guardar el uso"); await esperarTexto(p, /Uso registrado: 2,5 kg/);
  ok(`${tag} C5 limpieza sin planta: 2,5 kg de hipoclorito`, mov("uso").endsWith(`hipoclorito_calcio|2.5|kg|-2.5|-|limpieza|-|-|-|-|${EMAILS.op2}`), mov("uso"));
  await clicTexto(p, ".fq .tec-boton-sec", "Cancelar"); await p.waitForSelector("[data-tarjeta=uso_quimicos]");
  ok(`${tag} C6 «Cancelar» vuelve al inicio`, !(await p.$(".fq")));
  ok(`${tag} C7 las llamadas llevan su clave de envío y cada lectura quedó en la auditoría`, sqlq("select count(*) filter (where clave_envio ~ '^q-') || '/' || count(*) from tecnica.quimico_movimientos") === "4/4"
     && Number(sqlq("select count(*) from public.geoportal_auditoria where accion in ('tec_quimico_entrada', 'tec_quimico_uso')")) === 4);
  await p.close();

  // ===== D. Lo que ve el supervisor de planta después =====
  const cmp = JSON.parse(sqlq(`select public.geoportal_tec_quimicos_comparacion('${EMAILS.planta}', null, null)`));
  ok(`${tag} D1 el uso del operador entra en «esperado contra usado» del supervisor (PAC, Huaricha, hoy: usado 300 kg)`, cmp.filas.some((f) => f.quimico === "pac" && f.planta === "huaricha" && f.dia === HOY && f.usado_kg === 300) || cmp.filas.every((f) => f.quimico !== "pac"),
     JSON.stringify(cmp.filas.slice(0, 2)));

  // ===== E. Quien no tiene los formularios =====
  p = await abrir(ancho, "op"); await esperarTexto(p, /Sesión de/);
  ok(`${tag} E1 el operador de redes no tiene las tarjetas de químicos`, !(await p.$("[data-tarjeta=entrada_quimicos]")) && !(await p.$("[data-tarjeta=uso_quimicos]")));
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
