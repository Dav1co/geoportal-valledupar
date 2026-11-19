// Prueba en Chrome REAL de las pantallas del Corte 15 («Evento de suspensión»), a 390 px (táctil) y 1280 px:
// · Declarar evento: por sectores (los 7 sectores y 29 subsectores reales), por círculo dibujado en el mapa (centro al tocar, radio con la manija o escrito)
//   y total; la vista previa de contratos, usuarios sensibles y reportes que se asociarían; «ya hay un evento abierto para esa zona».
// · Geovisor, modo «Afectaciones»: la zona del evento pintada y la franja «Sin agua en … desde … por …».
// · Detalle: reportes asociados, desasociar, asociar a mano, ajustar el regreso estimado, cerrar en bloque y anular.
// · Catálogos: sectores de cada planta y la lista de lo que se asocia.
// Las Edges corren DE VERDAD en Deno (la del Corte 15 del Code A); las RPC van a la base de Code B con el Corte 15 aplicado, con el rol de la API y los topes de producción.
// Uso: node scripts/prueba_chrome_eventos_c15.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla, p. ej. emdupar_b_15> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c15"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_eventos_c15.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_15> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANTES = false;
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55989, P_EDGE = 55990;      // puertos de Code B para el 14 (55987–55994)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", campo: "zt.campo@emdupar.gov.co", nada: "zt.nada@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.op]: "operador", [EMAILS.op2]: "operador", [EMAILS.planta]: "supervisor" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.op]: ["danos_fallas"], [EMAILS.op2]: ["danos_fallas"], [EMAILS.planta]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención" };
// cada ancho arranca de una copia limpia de la plantilla, con la persona de Comercial y el formulario asignado al operador (como lo haría el supervisor en Personal)
function rehacer() {
  execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('${EMAILS.campo}', 'ZT Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos') on conflict do nothing`);
  if (!ANTES) sqlq(`select public.geoportal_redes_personal_formulario('${EMAILS.dist}', '${EMAILS.op}', 'activo_campo', true, 'Sale a campo a levantar activos')`);
  if (!ANTES) sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'area', 'distribucion', 'Sale a campo con la cuadrilla'), public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'cargo', 'Fontanero', 'Cargo de la persona')`);
  if (!ANTES && sqlq(`select tecnica.f_formulario_asignado('${EMAILS.op}', 'danos_fallas')`) !== "t") sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'danos_fallas', '${EMAILS.adm}')`);
}
rehacer();
// el lugar de la prueba: una válvula real con activos de acueducto y de alcantarillado a menos de 15 m
const LUGAR = (() => {
  const f = sqlq(`select m.codigo || '|' || round(ST_Y(m.geom)::numeric, 6) || '|' || round(ST_X(m.geom)::numeric, 6) from redes.activo_vigente_mat m
    where m.prefijo = 'VAL' and not m.retirado and not m.oculto
      and (select count(*) from redes.activo_vigente_mat x where x.sistema = 'acueducto' and not x.retirado and not x.oculto and x.geom && ST_Expand(m.geom, 0.0003) and ST_DWithin(x.geom::geography, m.geom::geography, 15)) between 3 and 8
      and (select count(*) from redes.activo_vigente_mat x where x.sistema = 'alcantarillado' and not x.retirado and not x.oculto and x.geom && ST_Expand(m.geom, 0.0003) and ST_DWithin(x.geom::geography, m.geom::geography, 15)) between 2 and 8
    order by m.codigo limit 1`).split("|");
  return { val: f[0], lat: Number(f[1]), lon: Number(f[2]) };
})();
const cuenta = (sis, radio) => Number(sqlq(`select count(*) from redes.activo_vigente_mat x where x.sistema = '${sis}' and not x.retirado and not x.oculto and ST_DWithin(x.geom::geography, ST_SetSRID(ST_MakePoint(${LUGAR.lon}, ${LUGAR.lat}), 4326)::geography, ${radio})`));

// ---------- 1. Paquete de la página (?area=campo monta Formatos de campo; si no, Técnica) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c15_"));
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
    import { AreaCampo } from "./src/campo/AreaCampo.tsx";
    const campo = new URLSearchParams(location.search).get("area") === "campo";
    createRoot(document.getElementById("raiz")).render(campo ? <AreaCampo correo="persona@emdupar.gov.co" /> : <AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth, Storage y PostgREST simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], desconocidas = [], subidas = [];
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
function rpcBase(fn, a) {
  // p_sectores es text[] (planta_sectores_fijar): PostgREST lo pasa como arreglo de texto, no como jsonb
  const args = Object.entries(a).map(([k, val]) => `${k} => ${k === "p_sectores" && Array.isArray(val) ? `array[${val.map((x) => lit(String(x))).join(", ")}]::text[]` : lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcOtras(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: false })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_avisos": if (a.p_solicitante === EMAILS.dist) {      // Etapa 2: los avisos de distribución salen de la base (tecnica.f_avisos con el bloque del Corte 14)
      const av = JSON.parse(sqlq("select tecnica.f_avisos(false, true)"));
      return { areas: { planta: false, distribucion: true, personal: true }, admin: false, avisos: av, total: av.length, rojos: av.filter((x) => x.nivel === "rojo").length, naranjas: av.filter((x) => x.nivel === "naranja").length, calculado_en: new Date().toISOString(), ms: 1 };
    }
    return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
    case "geoportal_campo_obtener_formulario": return a.p_solicitante === EMAILS.campo
      ? { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: true, supervisar: false, administrar_catalogo: false }, limites: { max_fotos: 6, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg" },
          zona: { lat_min: 10.1, lat_max: 10.8, lon_min: -73.6, lon_max: -72.9 }, grupos: [] }
      : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } };
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
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/redes-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/redes-evidencias/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT", "Access-Control-Allow-Headers": "content-type, x-upsert" }); return res.end(); }
      if (req.method === "PUT") {
        if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" });
        subidas.push({ ruta, bytes: cuerpo.length, mime: req.headers["content-type"] });
        sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', ${lit(ruta)}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })}) on conflict do nothing`);
        return json(200, { Key: `redes-evidencias/${ruta}` });
      }
    }
    if (u.pathname.startsWith("/storage/v1/object/sign/redes-evidencias/")) {      // lectura firmada (60 s)
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      return json(200, { signedURL: `/object/leer/redes-evidencias/${ruta}?token=l-${ruta.length}` });
    }
    if (u.pathname.startsWith("/storage/v1/object/leer/")) { res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(PNG); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcOtras(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (Técnica, redes y campo) ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const p = new URL(r.url).pathname; return (p.includes("geoportal-redes") ? hs[1] : p.includes("geoportal-campo") ? hs[2] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 400))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
const texto = (p) => p.evaluate(() => document.body.innerText);
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
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1200)} · errores: ${errores.join(" | ").slice(0, 800)}`); }
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
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const clic = (p, sel) => p.evaluate((sel) => { const b = document.querySelector(sel); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const captura = async (p, nombre, completa = true) => { await new Promise((r) => setTimeout(r, 350)); await p.screenshot({ path: join(CAP, nombre), fullPage: completa }); };
async function abrir(ancho, rol, area, precision = 6, pos = LUGAR) {
  const p = await nav.newPage(); pagina = p;
  await p.setGeolocation({ latitude: pos.lat, longitude: pos.lon, accuracy: precision });
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(60000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${area ? "&area=" + area : ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
let pagina = null;
const diagnostico = async (e) => {      // una espera que no llega: se dice qué había en pantalla y qué errores hubo
  console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 300) + " · errores: " + errores.join(" | ").slice(0, 900) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-700).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {});
  try { edge.kill(); } catch { /* ya terminó */ }
  process.exit(1);
};

// ---------- 5. Ayudantes del Corte 15 ----------
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const SUB = "SEC-000008", SUB2 = "SEC-000009";      // Subsector 1.1 y 1.2 (sectores reales de la base)
const nf = new Intl.NumberFormat("es-CO");
const previaBase = (zona) => JSON.parse(sqlq(`select public.geoportal_redes_evento_vista_previa('${EMAILS.dist}', ${lit(zona)})::jsonb - 'zona_geojson'`));
// un tramo de acueducto dentro del Subsector 1.1, para poner un daño que el evento asocie al declararse
const [TRAMO, TLAT, TLON] = sqlq(`select m.codigo || '|' || round(ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom,1),0.5))::numeric,6) || '|' || round(ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom,1),0.5))::numeric,6)
  from redes.activo_vigente_mat m join redes.activo_vigente_mat s on s.codigo = '${SUB}' and ST_Within(m.geom, s.geom) where m.prefijo = 'RED' and m.sistema = 'acueducto' and not m.retirado and not m.oculto order by m.codigo limit 1`).split("|").map((x, i) => (i ? Number(x) : x));
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
function crearDano() {
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", ubicacion_origen: "mapa", activo: TRAMO, lat: TLAT, lon: TLON,
    t_detectado: iso(-20), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`)).codigo;
}
const campoLocal = (min) => { const d = new Date(Date.now() + min * 60000), z = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`; };
async function aSuspensiones(p) {
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /No identificados/);
  await clicTexto(p, "[role=tab]", "Suspensiones"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 });
}
const opcion = (p, c) => clic(p, `[data-testid=eventos] [data-opcion="${c}"]`);
const dato = (p, d, raiz = "[data-testid=evs-previa-datos]") => p.evaluate((d, r) => document.querySelector(`${r} [data-dato="${d}"]`)?.textContent ?? null, d, raiz);
const mapaListo = (p) => p.waitForSelector("[data-testid=evs-mapa] .evs-mapa-lienzo[data-listo=si]", { timeout: 40000 });
const zonaEnMapa = (p, fuente = "zona") => p.evaluate((f) => { const m = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo")?.__mapa; const d = m?.getSource(f)?.serialize?.().data; return d && d.type === "Feature" ? d.geometry.type : d?.features?.length ? "varias" : null; }, fuente);
const pinturaMini = (p) => p.evaluate(() => { const m = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo").__mapa; return [m.getPaintProperty("zona-l", "line-color"), m.getPaintProperty("zona-l", "line-width"), m.getPaintProperty("zona-a", "fill-opacity"), m.getPaintProperty("zona-l", "line-dasharray") ?? null].join("|"); });
const bot = (rad, lat, lon) => JSON.parse(sqlq(`select redes.f_reporte_externo_recibir_evento(${lit({ radicado: rad, canal: "telegram", tipo: "sin_agua", lat, lon })})`));
const repCampo = (lat, lon) => { const id = sqlq(`insert into campo.reportes (id, tipo_id, lat, lon, origen, autor) select gen_random_uuid(), t.id, ${lat}, ${lon}, 'campo', '${EMAILS.campo}' from campo.tipos_reporte t where t.codigo = 'sin_agua' returning id`).split("\n")[0];
  return sqlq(`select 'REP-' || lpad(seq::text, 6, '0') from campo.reportes where id = '${id}'`); };
const eventoBase = (cod) => JSON.parse(sqlq(`select public.geoportal_redes_evento('${EMAILS.dist}', '${cod}')::jsonb - 'zona_geojson'`));
async function alGeovisor(p) { await esperarTexto(p, /Geovisor técnico/); await clicTexto(p, "button.tec-tarjeta-modo", "Geovisor técnico"); await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 }); }
const geo = (p, f, ...a) => p.evaluate(new Function("...a", `const m = document.querySelector(".geo-mapa").__mapa; return (${f})(m, ...a);`), ...a);
const visible = (p, capa) => geo(p, "(m, c) => m.getLayer(c) ? (m.getLayoutProperty(c, 'visibility') ?? 'visible') : 'no existe'", capa);
const modoGeo = async (p, n) => { await clicTexto(p, ".geo-seg button", n); await p.waitForFunction((n) => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === n)?.getAttribute("aria-pressed") === "true", {}, n); };
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? { capa: t.dataset.capa, txt: t.innerText, botones: [...t.querySelectorAll("button")].map((b) => b.textContent.trim()), dentro: t.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 } : null; });
const detalle = (p) => p.evaluate(() => { const d = document.querySelector("[data-testid=evs-detalle]"); if (!d) return null; return { estado: d.dataset.estado, franja: d.querySelector("[data-testid=evs-franja]").textContent, aviso: d.querySelector("[data-testid=evs-aviso]")?.textContent ?? null,
  reportes: d.querySelector('[data-dato="reportes"]').textContent, regreso: d.querySelector('[data-dato="regreso"]').textContent, fin: d.querySelector('[data-dato="fin"]')?.textContent ?? null,
  asociados: [...d.querySelectorAll("[data-asociado]")].map((x) => ({ clave: x.dataset.asociado, txt: x.innerText.replace(/\n/g, " ") })), titulo: d.querySelector("[data-testid=evs-asociados] h2").textContent,
  acciones: [...(d.querySelector("[data-testid=evs-acciones]")?.querySelectorAll("button") ?? [])].map((b) => b.textContent.trim()), historial: [...d.querySelectorAll("[data-testid=evs-historial] li")].map((x) => x.innerText.replace(/\n/g, " ")), txt: d.innerText }; });
const esperarDetalle = (p, re, ms = 40000) => p.waitForFunction((s) => new RegExp(s).test(document.querySelector("[data-testid=evs-detalle]")?.innerText ?? ""), { timeout: ms }, re.source).then(() => true).catch(() => false);
const valor = (p, sel) => p.evaluate((s) => document.querySelector(s)?.value ?? null, sel);
const edgeF = (rol, accion, o = {}) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
  headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined })
  .then(async (r) => ({ status: r.status, cache: r.headers.get("cache-control"), cuerpo: await r.json().catch(() => null) }));
const errorVisto = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=eventos] .tec-aviso-error")].map((x) => x.innerText).join(" · "));
const altoMin = (p, sel) => p.evaluate((s) => Math.min(...[...document.querySelectorAll(s)].filter((b) => b.offsetParent).map((b) => b.getBoundingClientRect().height)), sel);

try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  let p, t, r;
  const DAN = crearDano();

  // ===== A. Declarar evento por sectores, con la vista previa =====
  p = await abrir(ancho, "dist"); await aSuspensiones(p);
  t = await texto(p);
  ok(A("A1 Dashboard distribución → pestaña «Suspensiones»: sin eventos abiertos lo dice, y están «Declarar evento», «Sectores de cada planta» y «Qué reportes se asocian»"),
    /No hay eventos de suspensión abiertos en este momento\./.test(t) && !!(await p.$("[data-testid=evs-nuevo]")) && !!(await p.$("[data-testid=evs-ir-plantas]")) && !!(await p.$("[data-testid=evs-ir-tipos]")), t.slice(-400));
  await captura(p, `despues_eventos_lista_vacia_${ancho}.png`);
  await clic(p, "[data-testid=evs-nuevo]"); await p.waitForSelector("[data-testid=evs-declarar]");
  ok(A("A2 el supervisor de distribución puede «Por sectores» y «Por círculo en el mapa»; «Total» no le sale"), (await p.evaluate(() => [...document.querySelectorAll('[role=group][aria-label="Alcance del evento"] button')].map((b) => b.textContent).join("|"))) === "Por sectores|Por círculo en el mapa");
  await opcion(p, "sectores"); await p.waitForSelector("[data-sector]");
  ok(A("A3 «Por sectores» lista los sectores y, aparte, los subsectores (7 y 29 en la base)"), (await p.evaluate(() => document.querySelectorAll('[data-clase="sector"] [data-sector]').length)) === 7 && (await p.evaluate(() => document.querySelectorAll('[data-clase="subsector"] [data-sector]').length)) === 29
     && /Subsector 1\.1/.test(await p.evaluate(() => document.querySelector('[data-sector="SEC-000008"]').closest("label").textContent)));
  await clic(p, "[data-testid=evs-declarar-boton]"); await pausa(150);
  ok(A("A4 sin llenar, «Declarar evento» dice qué falta y no declara"), /Marque al menos un sector o subsector\./.test(await errorVisto(p)) && /Escriba la causa/.test(await errorVisto(p)) && sqlq("select count(*) from redes.eventos_suspension") === "0", await errorVisto(p));
  await clic(p, `[data-sector="${SUB}"]`); await poner(p, "#evs-causa", "ZT daño en la tubería principal"); await poner(p, "#evs-desde", campoLocal(-120)); await poner(p, "#evs-regreso", campoLocal(240));
  await clic(p, "[data-testid=evs-declarar-boton]"); await pausa(150);
  ok(A("A5 sin la vista previa no declara: «Antes de declarar, pulse «Ver a quién afecta»»"), /Antes de declarar, pulse «Ver a quién afecta»/.test(await errorVisto(p)) && sqlq("select count(*) from redes.eventos_suspension") === "0");
  await clic(p, "[data-testid=evs-ver-previa]"); await p.waitForSelector("[data-testid=evs-previa-datos]", { timeout: 40000 });
  r = previaBase({ alcance: "sectores", sectores: [SUB] });
  t = await p.evaluate(() => document.querySelector("[data-testid=evs-previa-datos]").innerText);
  ok(A("A6 la vista previa: «Sin agua en Subsector 1.1», los contratos de la zona, los usuarios sensibles y «1 (1 daño)» que se asociaría; sin nombres"), /Sin agua en Subsector 1\.1/.test(t) && (await dato(p, "contratos")) === nf.format(r.contratos) && r.contratos > 100
     && (await dato(p, "sensibles")) === nf.format(r.sensibles) && /^1 \(1 daño\)$/.test(await dato(p, "reportes")) && !/@/.test(t), t);
  await mapaListo(p);
  ok(A("A7 la zona se dibuja en el minimapa con el color propuesto: borde continuo #c25e00 de 2 px y relleno al 12 %"), (await zonaEnMapa(p)) === "MultiPolygon" && (await pinturaMini(p)) === "#c25e00|2|0.12|");
  ok(A("A8 la pantalla no desborda y sus botones miden 44 px o más"), (await sinDesborde(p)) && (await altoMin(p, "[data-testid=eventos] button.tec-boton, [data-testid=eventos] button.tec-boton-sec, [data-testid=eventos] button.dan-opcion")) >= 44);
  await captura(p, `despues_eventos_declarar_sectores_${ancho}.png`);
  await clic(p, `[data-sector="${SUB2}"]`); await pausa(200);
  ok(A("A9 al cambiar la zona la vista previa deja de valer: «Cambió la zona o la hora: vuelva a calcular»"), !!(await p.$("[data-testid=evs-previa-vieja]")) && !(await p.$("[data-testid=evs-previa-datos]")));
  await clic(p, `[data-sector="${SUB2}"]`); await pausa(200);
  ok(A("A10 al volver a la misma zona la vista previa vuelve a valer"), !!(await p.$("[data-testid=evs-previa-datos]")));
  await clic(p, "[data-testid=evs-declarar-boton]");
  await p.waitForFunction(() => document.querySelector("[data-testid=eventos]")?.dataset.vista !== "declarar", { timeout: 40000 });
  const EV1 = sqlq("select codigo from redes.eventos_suspension order by id desc limit 1");
  r = JSON.parse(sqlq(`select public.geoportal_redes_evento('${EMAILS.dist}', '${EV1}')::jsonb - 'zona_geojson'`));
  ok(A("A11 «Declarar evento» lo crea (EVS-…): por sectores, con la causa, el regreso estimado y el daño que ya estaba en la zona asociado"), /^EVS-\d{6}$/.test(EV1) && r.estado === "abierto" && r.alcance === "sectores" && r.sectores.join() === SUB && r.causa === "ZT daño en la tubería principal"
     && !!r.regreso_estimado && r.reportes.danos === 1 && r.asociados.some((a) => a.ref === DAN && a.modo === "al_declarar"), JSON.stringify(r).slice(0, 500));
  await p.waitForSelector("[data-testid=evs-detalle]", { timeout: 30000 }); await esperarDetalle(p, /Historial/);
  let d = await detalle(p);
  ok(A("A12 tras declarar abre el detalle con el aviso «Evento EVS-… declarado. 1 reporte que ya estaba en la zona quedó asociado.»"), new RegExp(`^Evento ${EV1} declarado\\. 1 reporte que ya estaba en la zona quedó asociado\\.`).test(d.aviso ?? "") && d.estado === "abierto", JSON.stringify(d).slice(0, 400));
  await p.close();

  // ===== B. Geovisor, modo «Afectaciones»: la franja y la zona del evento =====
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  r = eventoBase(EV1);
  p = await abrir(ancho, "op"); await alGeovisor(p); await p.waitForSelector("[data-testid=franja-eventos]", { timeout: 30000 });
  t = await p.evaluate(() => document.querySelector("[data-testid=franja-eventos]").innerText);
  ok(A("B1 el operador ve la franja del evento con el texto del servidor: «Sin agua en Subsector 1.1 desde … por … Regreso estimado: …»"), t.includes(r.franja) && /^Sin agua en Subsector 1\.1 desde .+ por ZT daño en la tubería principal\. Regreso estimado: .+/.test(r.franja), t + " · " + r.franja);
  ok(A("B2 … con «Ver la zona», y SIN el botón «Eventos de suspensión» (es de supervisores)"), /Ver la zona/.test(t) && !(await p.$("[data-testid=franja-eventos-ir]")));
  ok(A("B3 fuera de «Afectaciones» la zona no se pinta"), (await visible(p, "x-evento-a")) === "none" && (await visible(p, "x-evento-l")) === "none");
  await clicTexto(p, "[data-testid=franja-eventos] button", "Ver la zona"); await p.waitForSelector('.geo-tarjeta[data-capa="evento"]', { timeout: 30000 });
  ok(A("B4 «Ver la zona» pasa a «Afectaciones», encuadra y pinta la zona: borde continuo #c25e00 de 2 px y relleno al 12 %, debajo de las tuberías del 9b"), (await p.evaluate(() => document.querySelector('.geo-seg button[data-colores="afectaciones"]').getAttribute("aria-pressed"))) === "true"
     && (await visible(p, "x-evento-a")) === "visible" && (await geo(p, "(m) => [m.getPaintProperty('x-evento-l','line-color'), m.getPaintProperty('x-evento-l','line-width'), m.getPaintProperty('x-evento-a','fill-opacity'), m.getPaintProperty('x-evento-l','line-dasharray') ?? '', m.getSource('x-eventos').serialize().data.features.length].join('|')")) === "#c25e00|2|0.12||1"
     && (await geo(p, "(m) => { const ids = m.getStyle().layers.map((l) => l.id); return ids.indexOf('x-evento-l') < ids.indexOf('x-corte-afectado'); }")) === true);
  let tj = await tarjetaGeo(p);
  ok(A("B5 la tarjeta de la zona: «Sin agua en Subsector 1.1», el evento, la causa, el regreso, los contratos y «1 reporte asociado (1 daño)»; al operador no le sale «Ver el evento»"), !!tj && /Sin agua en Subsector 1\.1/.test(tj.txt) && tj.txt.includes(EV1)
     && /ZT daño en la tubería principal/.test(tj.txt) && /Contratos en la zona\s*1\.322/.test(tj.txt) && /1 reporte asociado \(1 daño\)/.test(tj.txt) && !tj.botones.includes("Ver el evento") && tj.dentro && !/@/.test(tj.txt), tj?.txt);
  t = await p.evaluate(() => document.querySelector("[data-testid=leyenda-cortes]").innerText);
  ok(A("B6 la leyenda gana «Zona sin agua (evento de suspensión)» y «1 evento de suspensión abierto»"), /Zona sin agua \(evento de suspensión\)/.test(t) && /1 evento de suspensión abierto/.test(t) && !(await p.$("[data-testid=leyenda-eventos-ir]")), t);
  await pausa(1500); await p.screenshot({ path: join(CAP, `despues_geovisor_evento_${ancho}.png`) });
  // la alternativa de color, solo para la captura de comparación (no queda en el código): borde azul oscuro #0a2540 y relleno al 8 %
  await geo(p, "(m) => { m.setPaintProperty('x-evento-l','line-color','#0a2540'); m.setPaintProperty('x-evento-a','fill-color','#0a2540'); m.setPaintProperty('x-evento-a','fill-opacity',0.08); }");
  await pausa(700); await p.screenshot({ path: join(CAP, `comparacion_geovisor_evento_azul_${ancho}.png`) });
  await geo(p, "(m) => { m.setPaintProperty('x-evento-l','line-color','#c25e00'); m.setPaintProperty('x-evento-a','fill-color','#c25e00'); m.setPaintProperty('x-evento-a','fill-opacity',0.12); }");
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar").click());
  await modoGeo(p, "Tipo");
  ok(A("B7 al volver a «Tipo» la zona desaparece y la tarjeta se cierra"), (await visible(p, "x-evento-a")) === "none" && !(await p.$('.geo-tarjeta[data-capa="evento"]')));
  await p.close();
  // dos reportes del bot y uno del formato de campo DENTRO de la zona: se asocian solos
  const b1 = bot(`ZT15-${ancho}-1`, TLAT, TLON), b2 = bot(`ZT15-${ancho}-2`, TLAT + 0.0002, TLON);
  const REP = repCampo(TLAT + 0.0001, TLON);
  ok(A("B8 (base) al bot le responde «Ya sabemos del corte en tu sector. Regreso estimado: …» con el código del evento"), b1.evento === EV1 && /^Ya sabemos del corte en tu sector\. Regreso estimado: /.test(b1.mensaje) && b2.evento === EV1, JSON.stringify(b1));
  p = await abrir(ancho, "dist"); await alGeovisor(p); await p.waitForSelector("[data-testid=franja-eventos-ir]", { timeout: 30000 });
  await clic(p, "[data-testid=franja-eventos-ir]"); await p.waitForSelector(`[data-testid=geo-eventos] [data-evento="${EV1}"]`, { timeout: 30000 });
  t = await p.evaluate((c) => document.querySelector(`[data-testid=geo-eventos] [data-evento="${c}"]`).innerText, EV1);
  ok(A("B9 el supervisor abre «Eventos de suspensión» desde la franja del geovisor: la lista con «4 reportes asociados (2 del bot · 1 daño · 1 de campo)»"), /4 reportes asociados \(2 del bot · 1 daño · 1 de campo\)/.test(t) && /Abierto/i.test(t), t);
  await captura(p, `despues_eventos_lista_${ancho}.png`);
  await clic(p, "[data-testid=geo-eventos] .tec-volver"); await p.waitForFunction(() => !document.querySelector("[data-testid=geo-eventos]"));
  ok(A("B10 «Volver al mapa» cierra la pantalla y el geovisor sigue ahí"), !!(await p.$(".geo-mapa")));
  await p.close();

  // ===== C. Detalle: reportes asociados, desasociar, asociar a mano, regreso estimado y cierre en bloque =====
  p = await abrir(ancho, "dist"); await aSuspensiones(p); await p.waitForSelector(`[data-evento="${EV1}"]`);
  await clicTexto(p, `[data-evento="${EV1}"] button`, "Ver el evento"); await p.waitForSelector("[data-testid=evs-detalle]"); await esperarDetalle(p, /Historial/);
  d = await detalle(p);
  ok(A("C1 el detalle: la franja, los conteos y «4 reportes asociados» con cada uno (rótulo, origen y cómo se asoció); sin correos de ciudadanos ni contratos"), d.franja === r.franja && /^4 \(2 del bot · 1 daño · 1 de campo\)$/.test(d.reportes) && d.titulo === "4 reportes asociados" && d.asociados.length === 4
     && d.asociados.some((a) => a.clave === `dano:${DAN}` && /ya estaba en la zona al declarar/.test(a.txt)) && d.asociados.some((a) => a.clave === `campo:${REP}` && /Formato de campo/.test(a.txt) && /se asoció solo al llegar/.test(a.txt))
     && d.asociados.filter((a) => a.clave.startsWith("bot:")).length === 2, JSON.stringify(d.asociados));
  ok(A("C2 con el evento abierto, el supervisor de distribución tiene «Cerrar el evento (volvió el agua)», «Ajustar el regreso estimado» y «Anular el evento»"), d.acciones.join("|") === "Cerrar el evento (volvió el agua)|Ajustar el regreso estimado|Anular el evento");
  await mapaListo(p);
  ok(A("C3 el minimapa del detalle pinta la zona; la pantalla no desborda y los botones miden 44 px o más"), (await zonaEnMapa(p)) === "MultiPolygon" && (await sinDesborde(p)) && (await altoMin(p, "[data-testid=evs-detalle] button.tec-boton, [data-testid=evs-detalle] button.tec-boton-sec")) >= 44);
  await captura(p, `despues_evento_detalle_${ancho}.png`);
  // desasociar un reporte del bot
  const claveBot = d.asociados.find((a) => a.clave.startsWith("bot:")).clave;
  await clicTexto(p, `[data-asociado="${claveBot}"] button`, "Desasociar"); await p.waitForSelector("#evs-m-quitar");
  ok(A("C4 «Desasociar» pide el motivo y no deja confirmar con menos de 10 caracteres"), await p.evaluate(() => document.querySelector("[data-testid=evs-quitar-confirmar]").disabled));
  await poner(p, "#evs-m-quitar", "ZT es una fuga interna del predio"); await clic(p, "[data-testid=evs-quitar-confirmar]"); await esperarDetalle(p, /3 reportes asociados/);
  d = await detalle(p);
  ok(A("C5 el reporte desasociado sale del evento (3) y queda en el historial con su motivo; en la base vuelve a «Recibido»"), d.asociados.length === 3 && !d.asociados.some((a) => a.clave === claveBot) && d.historial.some((h) => /Se desasoció un reporte: «ZT es una fuga interna del predio»/.test(h))
     && /desasociado: vuelve a su flujo/.test(d.aviso ?? ""), JSON.stringify(d.historial));
  // asociarlo a mano otra vez
  await clic(p, "[data-testid=evs-asociar]"); await p.waitForSelector("[data-testid=evs-f-asociar]");
  await clic(p, '[data-testid=evs-f-asociar] [data-origen="bot"]'); await poner(p, "#evs-ref", "no-existe-zt"); await poner(p, "#evs-m-asociar", "ZT sí es del mismo corte");
  await clic(p, "[data-testid=evs-asociar-confirmar]"); await p.waitForSelector("[data-testid=evs-error-asociar]", { timeout: 30000 });
  ok(A("C6 asociar a mano un reporte que no existe: el error del servidor se muestra y no cambia nada"), (await p.$eval("[data-testid=evs-error-asociar]", (e) => e.textContent.length)) > 5 && (await detalle(p)).asociados.length === 3, await p.$eval("[data-testid=evs-error-asociar]", (e) => e.textContent));
  await poner(p, "#evs-ref", claveBot.slice(4)); await clic(p, "[data-testid=evs-asociar-confirmar]"); await esperarDetalle(p, /4 reportes asociados/);
  d = await detalle(p);
  ok(A("C7 «Asociar un reporte a mano» lo devuelve al evento («asociado a mano»), con su motivo en el historial"), d.asociados.length === 4 && d.asociados.some((a) => a.clave === claveBot && /asociado a mano/.test(a.txt)) && d.historial.some((h) => /Se asoció un reporte a mano: «ZT sí es del mismo corte»/.test(h)), JSON.stringify(d.asociados));
  // regreso estimado
  await clicTexto(p, "[data-testid=evs-acciones] button", "Ajustar el regreso estimado"); await p.waitForSelector("#evs-n-regreso");
  const antesReg = d.regreso;
  await poner(p, "#evs-n-regreso", campoLocal(600)); await poner(p, "#evs-m-regreso", "ZT la reparación tomó más tiempo"); await clicTexto(p, "[data-testid=evs-f-regreso] button", "Guardar la hora"); await esperarDetalle(p, /Regreso estimado ajustado/);
  await p.waitForFunction((x) => document.querySelector('[data-testid=evs-detalle] [data-dato="regreso"]')?.textContent !== x, { timeout: 30000 }, antesReg).catch(() => {});      // el detalle se vuelve a leer después del aviso
  d = await detalle(p);
  ok(A("C8 «Ajustar el regreso estimado» cambia la hora (también en la franja) y queda en el historial"), d.regreso !== antesReg && d.franja !== r.franja && d.historial.some((h) => /Se ajustó el regreso estimado: «ZT la reparación tomó más tiempo»/.test(h))
     && sqlq(`select count(*) from redes.evento_suspension_eventos x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = '${EV1}'`) === "1", d.regreso + " · " + antesReg);
  // cierre en bloque
  await clicTexto(p, "[data-testid=evs-acciones] button", "Cerrar el evento"); await p.waitForSelector("[data-testid=evs-f-cerrar]");
  t = await p.$eval("[data-testid=evs-cierre-explica]", (e) => e.textContent);
  ok(A("C9 «Cerrar el evento» explica: los 3 reportes del bot, la 116 y campo quedan atendidos con el mismo motivo y hora; el daño NO se cierra; nada se borra"), /los 3 reportes del bot, de la línea 116 y de campo quedan atendidos, con este mismo motivo y la misma hora/.test(t) && /El daño asociado NO se cierra: sigue hasta su reparación/.test(t) && /Nada se borra/.test(t)
     && await p.evaluate(() => document.querySelector("[data-testid=evs-cerrar-confirmar]").disabled), t);
  await captura(p, `despues_evento_cerrar_${ancho}.png`);
  await poner(p, "#evs-m-cerrar", "ZT se reparó la tubería y volvió el servicio"); await clic(p, "[data-testid=evs-cerrar-confirmar]"); await esperarDetalle(p, /Evento cerrado\./); await p.waitForSelector('[data-testid=evs-detalle][data-estado="cerrado"]', { timeout: 30000 }).catch(() => {});
  d = await detalle(p);
  ok(A("C10 cierre en bloque: «Evento cerrado. 3 reportes quedaron atendidos (2 del bot · 1 de campo). 1 daño sigue abierto hasta su reparación.»; el evento queda «Cerrado», sin acciones"),
    /^Evento cerrado\. 3 reportes quedaron atendidos \(2 del bot · 1 de campo\)\. 1 daño sigue abierto hasta su reparación\./.test(d.aviso ?? "") && d.estado === "cerrado" && d.acciones.length === 0 && /ZT se reparó la tubería y volvió el servicio/.test(d.fin ?? "")
     && !(await p.$("[data-testid=evs-asociar]")), d.aviso + " · " + d.fin);
  ok(A("C11 (base) los 2 reportes del bot y el de campo quedaron «atendido»; el daño sigue abierto"), sqlq(`select count(*) from redes.v_reporte_externo where radicado in ('ZT15-${ancho}-1', 'ZT15-${ancho}-2') and estado_bot = 'atendido'`) === "2"
     && sqlq(`select estado from campo.v_reportes_estado e join campo.reportes r on r.id = e.id where 'REP-' || lpad(r.seq::text, 6, '0') = '${REP}'`) === "atendido" && sqlq(`select estado from redes.v_dano where codigo = '${DAN}'`) !== "atendido",
    sqlq(`select string_agg(radicado || ':' || estado_bot, ',') from redes.v_reporte_externo where radicado like 'ZT15-${ancho}-%'`));
  await captura(p, `despues_evento_cerrado_${ancho}.png`);
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]"); await pausa(400);
  ok(A("C12 de vuelta en la lista: ya no está entre los abiertos; en «Cerrados» aparece con quién y cuándo lo cerró"), /No hay eventos de suspensión abiertos/.test(await texto(p))
     && await (async () => { await clic(p, '[data-filtro="cerrado"]'); await p.waitForSelector(`[data-evento="${EV1}"][data-estado="cerrado"]`, { timeout: 30000 }).catch(() => {}); return /Cerrado/.test(await p.evaluate((c) => document.querySelector(`[data-evento="${c}"]`)?.innerText ?? "", EV1)); })());
  await p.close();

  // ===== D. Declarar por círculo dibujado en el mapa; anular =====
  p = await abrir(ancho, "dist"); await aSuspensiones(p); await clic(p, "[data-testid=evs-nuevo]"); await p.waitForSelector("[data-testid=evs-declarar]");
  await opcion(p, "circulo"); await mapaListo(p);
  ok(A("D1 «Por círculo en el mapa»: sin centro lo dice, y el radio arranca en 200 m"), /Todavía no hay centro/.test(await texto(p)) && (await valor(p, "#evs-radio")) === "200" && !(await p.$("[data-testid=evs-manija]")));
  // se toca el centro del mapa (como un dedo o un clic)
  let caja = await p.evaluate(() => { const r = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo"); r.scrollIntoView({ block: "center" }); const b = r.getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2 }; });
  if (ancho < 500) await p.touchscreen.tap(caja.x, caja.y); else await p.mouse.click(caja.x, caja.y);
  await p.waitForSelector("[data-testid=evs-manija]", { timeout: 15000 });
  ok(A("D2 al tocar el mapa queda el centro, el círculo dibujado (borde continuo #c25e00 y relleno al 12 %) y la manija del borde, de 44 px"), /Centro: 10\.\d{5}, -73\.\d{5}\./.test(await texto(p)) && (await zonaEnMapa(p, "circulo")) === "Polygon"
     && (await p.evaluate(() => { const m = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo").__mapa; return [m.getPaintProperty("circulo-l", "line-color"), m.getPaintProperty("circulo-a", "fill-opacity")].join("|"); })) === "#c25e00|0.12"
     && (await p.evaluate(() => { const b = document.querySelector("[data-testid=evs-manija]").getBoundingClientRect(); return Math.min(b.width, b.height); })) >= 44);
  // se arrastra la manija hacia afuera: el radio crece
  await pausa(400);
  let man = await p.evaluate(() => { const b = document.querySelector("[data-testid=evs-manija]").getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2 }; });
  if (ancho < 500) { await p.touchscreen.touchStart(man.x, man.y); await p.touchscreen.touchMove(man.x + 20, man.y); await p.touchscreen.touchMove(man.x + 45, man.y); await p.touchscreen.touchEnd(); }
  else { await p.mouse.move(man.x, man.y); await p.mouse.down(); await p.mouse.move(man.x + 20, man.y, { steps: 4 }); await p.mouse.move(man.x + 45, man.y, { steps: 4 }); await p.mouse.up(); }
  await pausa(500);
  const radioArrastrado = Number(await valor(p, "#evs-radio"));
  ok(A("D3 arrastrar la manija del borde hacia afuera agranda el radio, y el campo «Radio» lo muestra"), radioArrastrado > 205 && radioArrastrado <= 5000, String(radioArrastrado));
  await poner(p, "#evs-radio", "10"); await pausa(150); await poner(p, "#evs-causa", "ZT fuga localizada en la esquina"); await clic(p, "[data-testid=evs-declarar-boton]"); await pausa(150);
  ok(A("D4 un radio fuera de los límites no pasa: «El radio va de 20 a 5.000 m»"), /El radio va de 20 a 5\.000 m\./.test(await errorVisto(p)));
  await poner(p, "#evs-radio", "300"); await pausa(300);
  await clic(p, "[data-testid=evs-ver-previa]"); await p.waitForSelector("[data-testid=evs-previa-datos]", { timeout: 40000 });
  t = await p.evaluate(() => document.querySelector("[data-testid=evs-previa-datos]").innerText);
  ok(A("D5 con el radio escrito (300 m) la vista previa dice «un círculo de 300 m en …» y sus contratos"), /Sin agua en un círculo de 300 m/.test(t) && Number((await dato(p, "contratos")).replace(/\./g, "")) > 0 && (await sinDesborde(p)), t);
  await captura(p, `despues_eventos_declarar_circulo_${ancho}.png`);
  await clic(p, "[data-testid=evs-declarar-boton]"); await p.waitForSelector("[data-testid=evs-detalle]", { timeout: 40000 }); await esperarDetalle(p, /Historial/);
  const EV2 = sqlq("select codigo from redes.eventos_suspension order by id desc limit 1");
  r = eventoBase(EV2);
  ok(A("D6 se declara por círculo: queda el centro y el radio de 300 m, sin regreso estimado («Todavía no hay hora estimada»)"), r.alcance === "circulo" && Math.round(r.circulo.radio_m) === 300 && r.regreso_estimado === null && /Todavía no hay hora estimada/.test((await detalle(p)).regreso)
     && /radio 300 m/.test((await detalle(p)).txt), JSON.stringify(r.circulo));
  await clicTexto(p, "[data-testid=evs-acciones] button", "Anular el evento"); await p.waitForSelector("[data-testid=evs-f-anular]");
  ok(A("D7 «Anular» pide el motivo (10 o más)"), await p.evaluate(() => document.querySelector("[data-testid=evs-anular-confirmar]").disabled));
  await poner(p, "#evs-m-anular", "ZT se declaró por error en otro punto"); await clic(p, "[data-testid=evs-anular-confirmar]"); await esperarDetalle(p, /Evento anulado\./);
  await p.waitForSelector('[data-testid=evs-detalle][data-estado="anulado"]', { timeout: 30000 }).catch(() => {});
  d = await detalle(p);
  ok(A("D8 anulado: «Evento anulado. … a su flujo.», estado «Anulado», sin acciones y con el motivo en el historial; nada se borró"), /^Evento anulado\./.test(d.aviso ?? "") && d.estado === "anulado" && d.acciones.length === 0 && d.historial.some((h) => /Se anuló el evento: «ZT se declaró por error en otro punto»/.test(h))
     && sqlq(`select count(*) from redes.eventos_suspension where codigo = '${EV2}'`) === "1", d.aviso);

  // ===== E. Sectores de cada planta =====
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]");
  await clic(p, "[data-testid=evs-ir-plantas]"); await p.waitForSelector("[data-testid=evs-plantas]");
  t = await p.evaluate(() => [...document.querySelectorAll("[data-planta]")].map((x) => x.querySelector("h2").innerText.replace(/\s+/g, " ")).join(" | "));
  ok(A("E1 «Sectores de cada planta»: Huaricha y Gota Fría, las dos «Sin sectores asignados», con los 36 sectores y subsectores para marcar"), /Huaricha Sin sectores asignados \| Gota Fría Sin sectores asignados/i.test(t)
     && (await p.evaluate(() => document.querySelectorAll('[data-planta="huaricha"] [data-sector]').length)) === 36 && !(await p.$("[data-testid=evs-planta-guardar]")), t);
  await clic(p, `[data-planta="huaricha"] [data-sector="${SUB}"]`); await clic(p, `[data-planta="huaricha"] [data-sector="${SUB2}"]`); await p.waitForSelector('[data-planta="huaricha"] [data-testid=evs-planta-guardar]');
  ok(A("E2 al marcar aparece «Guardar los sectores de Huaricha», apagado hasta escribir el motivo"), await p.evaluate(() => document.querySelector('[data-planta="huaricha"] [data-testid=evs-planta-guardar]').disabled));
  await poner(p, "#evs-pm-huaricha", "ZT según el esquema de distribución"); await clic(p, '[data-planta="huaricha"] [data-testid=evs-planta-guardar]');
  await p.waitForFunction(() => /2 asignados/.test(document.querySelector('[data-planta="huaricha"] h2')?.innerText ?? ""), { timeout: 30000 }).catch(() => {});
  ok(A("E3 guarda: «Huaricha: 2 sectores o subsectores asignados.», la etiqueta pasa a «2 asignados» y queda en la base con su motivo"), /Huaricha: 2 sectores o subsectores asignados\./.test(await p.evaluate(() => document.querySelector('[data-planta="huaricha"]').innerText))
     && /2 asignados/i.test(await p.evaluate(() => document.querySelector('[data-planta="huaricha"] h2').innerText)) && JSON.parse(sqlq(`select public.geoportal_redes_evento_catalogo('${EMAILS.dist}')->'plantas'`)).find((x) => x.codigo === "huaricha").sectores.length === 2
     && (await sinDesborde(p)), await p.evaluate(() => document.querySelector('[data-planta="huaricha"]').innerText.slice(-300)));
  await captura(p, `despues_eventos_plantas_${ancho}.png`);

  // ===== F. Qué reportes se asocian =====
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]");
  await clic(p, "[data-testid=evs-ir-tipos]"); await p.waitForSelector("[data-testid=evs-tipos]");
  ok(A("F1 «Qué reportes se asocian»: los 15 tipos por omisión, agrupados por bot (2), línea 116 (9), daños (3) y formato de campo (1), todos «Se asocia»"),
    (await p.evaluate(() => ["bot", "l116", "dano", "campo"].map((o) => document.querySelectorAll(`[data-origen-tipos="${o}"] [data-tipo]`).length).join(","))) === "2,9,3,1" && (await p.evaluate(() => document.querySelectorAll('[data-tipo][data-asocia="no"]').length)) === 0
     && /No tengo agua o tengo baja presión/.test(await p.evaluate(() => document.querySelector('[data-tipo="bot:sin_agua"]').innerText)));
  await clicTexto(p, '[data-tipo="dano:electrica"] button', "Dejar de asociarlo"); await p.waitForSelector('[data-tipo="dano:electrica"] .evs-tipo-motivo');
  await poner(p, '[data-tipo="dano:electrica"] .evs-tipo-motivo', "ZT las fallas eléctricas van aparte"); await clic(p, '[data-tipo="dano:electrica"] [data-testid=evs-tipo-confirmar]');
  await p.waitForSelector('[data-tipo="dano:electrica"][data-asocia="no"]', { timeout: 30000 }).catch(() => {});
  ok(A("F2 «Dejar de asociarlo», con motivo: «Falla eléctrica» queda «No se asocia» (en la base también) y ofrece «Volver a asociarlo»"), (await p.evaluate(() => document.querySelector('[data-tipo="dano:electrica"]').innerText)).includes("No se asocia")
     && /Volver a asociarlo/.test(await p.evaluate(() => document.querySelector('[data-tipo="dano:electrica"]').innerText)) && sqlq("select asocia from redes.evento_tipos_asociables where origen = 'dano' and codigo = 'electrica'") === "f");
  await clic(p, "[data-testid=evs-tipo-nuevo]"); await p.waitForSelector("[data-testid=evs-f-tipo]");
  await clic(p, '[data-testid=evs-f-tipo] [data-origen="l116"]'); await poner(p, "#evs-tn-cod", "zt agua turbia en el sector"); await poner(p, "#evs-tn-nom", "ZT agua turbia en el sector"); await poner(p, "#evs-tn-mot", "ZT también llega con los cortes");
  await clic(p, "[data-testid=evs-tipo-agregar]"); await p.waitForSelector('[data-tipo="l116:zt agua turbia en el sector"]', { timeout: 30000 }).catch(() => {});
  ok(A("F3 «Agregar un tipo a la lista»: una causal nueva de la línea 116 queda en la lista, «Se asocia»"), (await p.evaluate(() => document.querySelector('[data-tipo="l116:zt agua turbia en el sector"]')?.dataset.asocia)) === "si" && (await p.evaluate(() => document.querySelectorAll('[data-origen-tipos="l116"] [data-tipo]').length)) === 10 && (await sinDesborde(p)),
    await p.evaluate(() => document.querySelector("[data-testid=evs-error-tipo]")?.textContent ?? ""));
  await captura(p, `despues_eventos_tipos_${ancho}.png`);
  await p.close();

  // ===== G. Evento total: el supervisor de planta, desde el geovisor =====
  p = await abrir(ancho, "planta"); await alGeovisor(p); await modoGeo(p, "Afectaciones"); await p.waitForSelector("[data-testid=leyenda-eventos-ir]", { timeout: 30000 });
  ok(A("G1 el supervisor de planta llega por el geovisor: en «Afectaciones», la leyenda trae «Eventos de suspensión» y dice «Sin eventos de suspensión abiertos»"), /Sin eventos de suspensión abiertos/.test(await p.evaluate(() => document.querySelector("[data-testid=leyenda-cortes]").innerText)));
  await clic(p, "[data-testid=leyenda-eventos-ir]"); await p.waitForSelector("[data-testid=geo-eventos] [data-testid=evs-lista]", { timeout: 30000 });
  ok(A("G2 puede declarar, pero no ve los dos catálogos (son del supervisor de distribución)"), !!(await p.$("[data-testid=evs-nuevo]")) && !(await p.$("[data-testid=evs-ir-plantas]")) && !(await p.$("[data-testid=evs-ir-tipos]")));
  await clic(p, "[data-testid=evs-nuevo]"); await p.waitForSelector("[data-testid=evs-declarar]");
  ok(A("G3 al supervisor de planta solo le sale «Total», ya elegido"), (await p.evaluate(() => [...document.querySelectorAll('[role=group][aria-label="Alcance del evento"] button')].map((b) => b.textContent + ":" + b.getAttribute("aria-pressed")).join("|"))) === "Total:true");
  await opcion(p, "planta"); await p.waitForSelector("#evs-planta"); await p.select("#evs-planta", "gota_fria"); await p.waitForSelector("[data-testid=evs-planta-sin]");
  ok(A("G4 «Lo que surte una planta» con Gota Fría (sin sectores asignados): lo dice y no deja ver a quién afecta"), /Gota Fría todavía no tiene sectores asignados: no se puede declarar por planta/.test(await p.$eval("[data-testid=evs-planta-sin]", (e) => e.textContent))
     && /Huaricha \(2 sectores\)/.test(await p.evaluate(() => document.querySelector("#evs-planta").innerText)));
  await p.select("#evs-planta", "huaricha"); await poner(p, "#evs-causa", "ZT falla de energía en la planta"); await pausa(200);
  await clic(p, "[data-testid=evs-ver-previa]"); await p.waitForSelector("[data-testid=evs-previa-datos]", { timeout: 40000 });
  r = JSON.parse(sqlq(`select public.geoportal_redes_evento_vista_previa('${EMAILS.planta}', ${lit({ alcance: "total", total: "planta", planta: "huaricha" })})::jsonb - 'zona_geojson'`));
  ok(A("G5 con Huaricha (los 2 subsectores asignados en E): la vista previa con sus contratos y la zona en el minimapa"), (await dato(p, "contratos")) === nf.format(r.contratos) && r.contratos > 1322 && await (async () => { await mapaListo(p); return (await zonaEnMapa(p)) === "MultiPolygon"; })(), JSON.stringify(r));
  await opcion(p, "ciudad"); await pausa(200); await clic(p, "[data-testid=evs-ver-previa]"); await p.waitForSelector("[data-testid=evs-previa-datos]", { timeout: 40000 });
  t = await p.evaluate(() => document.querySelector("[data-testid=evs-previa-datos]").innerText);
  ok(A("G6 «Toda la ciudad»: la vista previa cuenta todos los contratos y dice que no se dibuja una zona"), /Toda la ciudad: no se dibuja una zona en el mapa/.test(t) && Number((await dato(p, "contratos")).replace(/\./g, "")) > 50000, t);
  await clic(p, "[data-testid=evs-declarar-boton]"); await p.waitForSelector("[data-testid=evs-detalle]", { timeout: 40000 }); await esperarDetalle(p, /Historial/);
  const EV3 = sqlq("select codigo from redes.eventos_suspension order by id desc limit 1");
  d = await detalle(p);
  ok(A("G7 el evento total queda declarado; el supervisor de planta lo puede cerrar, ajustar o anular, pero no asociar reportes a mano"), eventoBase(EV3).alcance === "total" && eventoBase(EV3).total === "ciudad" && d.acciones.length === 3 && !(await p.$("[data-testid=evs-asociar]")));
  await captura(p, `despues_evento_total_${ancho}.png`);
  await clic(p, "[data-testid=geo-eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]"); await clic(p, "[data-testid=geo-eventos] .tec-volver"); await p.waitForFunction(() => !document.querySelector("[data-testid=geo-eventos]"));
  await p.waitForSelector("[data-testid=franja-eventos]", { timeout: 30000 });
  t = await p.evaluate(() => document.querySelector("[data-testid=franja-eventos]").innerText);
  ok(A("G8 de vuelta en el mapa, la franja ya muestra el evento total (sin zona que pintar: ofrece «Ver el evento»)"), /ZT falla de energía en la planta/.test(t) && /Ver el evento/.test(t) && !/Ver la zona/.test(t), t);
  await p.close();
  // el supervisor de distribución lo ve, pero no lo puede cerrar ni anular
  p = await abrir(ancho, "dist"); await aSuspensiones(p); await p.waitForSelector(`[data-evento="${EV3}"]`); await clicTexto(p, `[data-evento="${EV3}"] button`, "Ver el evento"); await p.waitForSelector("[data-testid=evs-detalle]"); await esperarDetalle(p, /Historial/);
  ok(A("G9 el supervisor de distribución ve el evento total, sin acciones: «… lo cierra o lo anula el supervisor de planta o el administrador»; sí puede asociar reportes"), (await detalle(p)).acciones.length === 0
     && /Un evento total lo ajusta, lo cierra o lo anula el supervisor de planta o el administrador\./.test(await p.$eval("[data-testid=evs-sin-permiso]", (e) => e.textContent)) && !!(await p.$("[data-testid=evs-asociar]")));
  await p.close();
  // el operador no entra a la pantalla de eventos
  r = await edgeF("op", "evento_catalogo");
  ok(A("G10 (Edge) el operador no lee el catálogo ni la lista de eventos (403); las zonas vigentes sí (200)"), r.status === 403 && (await edgeF("op", "eventos", { qs: { estado: "abierto" } })).status === 403 && (await edgeF("op", "eventos_vigentes")).status === 200, String(r.status));
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC desconocida", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(ANTES ? "capturas de «antes» tomadas" : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(ANTES || bien === resultados.length ? 0 : 1);
