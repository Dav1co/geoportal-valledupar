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
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
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
  await p.close();
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
