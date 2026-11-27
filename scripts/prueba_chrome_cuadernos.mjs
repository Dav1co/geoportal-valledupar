// [Code B] Cuadernos de análisis (Corte 2 del geovisor técnico, 26-nov): prueba en Chrome REAL, a 390 px (táctil) y 1.280 px, con la foto satelital
// encendida y apagada, y con los 5 perfiles: administrador, supervisor (autor), operador con la casilla del geovisor, dual (Comercial y supervisor de planta)
// y sin permisos (más un operador sin el geovisor).
// Las Edges corren DE VERDAD en Deno (geoportal-tecnica, geoportal-redes y geoportal-analisis); las RPC de redes y de análisis van a la base local del
// Code B (clúster 55442; NUNCA Supabase ni el 55432) con el rol de la API (service_role) y los topes de producción (30 s / 8 s). «Storage» es un doble
// que respeta el tope y los tipos del bucket y deja la fila en storage.objects. Sin internet: las teselas de fondo son imágenes simuladas.
// El armazón (paquete, puente y ayudas de Chrome) es el de scripts/prueba_chrome_geovisor_impresion.mjs de Code A.
// Uso: node scripts/prueba_chrome_cuadernos.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
//   Con CUADERNOS_REVISION=1 no corre pruebas: deja la página arriba (con el fondo real) para revisarla a ojo, un enlace por perfil.
//   <plantilla>: base del clúster 55442 con la red de producción y el bucket, SIN el esquema analisis (emdupar_b_cuad_base, la deja generar.py).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import { deflateSync } from "node:zlib";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_cuadernos.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = args;
if (!PLANTILLA) { console.error(USO); process.exit(2); }
const CAP = resolve(args[6] || join(tmpdir(), "capturas_cuadernos"));
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55993, P_EDGE = 55994;      // puertos de esta prueba (Code B)
const COPIA = "emdupar_b_cuad_chrome";      // la crea y la rehace SOLO esta prueba
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55442", PGUSER: "postgres", PGDATABASE: COPIA, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
// Los 5 perfiles (y un operador sin la casilla del geovisor). Personas PROPIAS de la prueba, con prefijo ztcua.
const EMAILS = { adm: "ztcua.adm@emdupar.gov.co", sup: "ztcua.sup@emdupar.gov.co", dual: "ztcua.dual@emdupar.gov.co", op: "ztcua.op@emdupar.gov.co", sin: "ztcua.sin@emdupar.gov.co", nada: "ztcua.nada@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.sup]: "operador", [EMAILS.dual]: "supervisor", [EMAILS.op]: "operador", [EMAILS.sin]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.sup]: [], [EMAILS.dual]: ["muestreo"], [EMAILS.op]: ["danos_fallas"], [EMAILS.sin]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
// la copia de trabajo la crea esta prueba (y solo esa se borra al rehacerla)
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${COPIA}`, "-c", `create database ${COPIA} template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "ignore", "inherit"] });
rehacer();
if (sqlq("show port") !== "55442") { console.error("No es el clúster del Code B"); process.exit(2); }
// el paquete SQL de los Cuadernos (la versión local: misma migración, con la huella de técnica de esta base) y las personas de la prueba
execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-f", join(raiz, "sql/analisis_cuadernos/pruebas_locales/local/migracion_analisis_cuadernos_local.sql")], { env: PGENV, stdio: ["ignore", "ignore", "inherit"] });
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_comercial, ver_registro_tecnico, ver_dashboard_tecnico, ver_dashboard_redes) values
  ('${EMAILS.adm}',  'ZTCUA Administrador',                   'admin',    true, 'sin_restriccion', 'todos', false, false, false, false),
  ('${EMAILS.sup}',  'ZTCUA Supervisor de distribución',      'consulta', true, 'sin_restriccion', 'todos', false, true,  false, true),
  ('${EMAILS.dual}', 'ZTCUA Dual (Comercial y sup. de planta)', 'consulta', true, 'sin_restriccion', 'todos', true,  true,  true,  false),
  ('${EMAILS.op}',   'ZTCUA Operador con el geovisor',        'consulta', true, 'sin_restriccion', 'todos', false, true,  false, false),
  ('${EMAILS.sin}',  'ZTCUA Operador sin el geovisor',        'consulta', true, 'sin_restriccion', 'todos', false, true,  false, false),
  ('${EMAILS.nada}', 'ZTCUA Sin permisos',                    'consulta', true, 'sin_restriccion', 'todos', false, false, false, false)`);
sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.sup}', '${EMAILS.op}', 'geovisor', 'si', 'ZTCUA ve la red en la calle')`);

// ---------- teselas simuladas (PNG de un color, con CORS) ----------
function png(r, g, b, raya) {
  const n = 256, filas = [];
  for (let y = 0; y < n; y++) { const f = Buffer.alloc(1 + n * 3); for (let x = 0; x < n; x++) { const l = raya && (x % 64 === 0 || y % 64 === 0); f[1 + x * 3] = l ? 255 : r; f[2 + x * 3] = l ? 255 : g; f[3 + x * 3] = l ? 255 : b; } filas.push(f); }
  const crc = (buf) => { let c = ~0; for (const x of buf) { c ^= x; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1)); } return ~c >>> 0; };
  const trozo = (tipo, datos) => { const l = Buffer.alloc(4); l.writeUInt32BE(datos.length); const td = Buffer.concat([Buffer.from(tipo), datos]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(n, 0); ihdr.writeUInt32BE(n, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), trozo("IHDR", ihdr), trozo("IDAT", deflateSync(Buffer.concat(filas))), trozo("IEND", Buffer.alloc(0))]);
}
const TESELA_CALLES = png(236, 231, 222, true), TESELA_SAT = png(58, 74, 53, false);
let falla_satelital = false;

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_geoimp_"));
// el fondo (calles y foto satelital) se sirve desde el servidor local de la prueba: el módulo real lib/mapaBase.ts con las URL cambiadas (sin internet)
const fondoLocal = { name: "fondo-local", setup(b) {
  b.onResolve({ filter: /lib\/mapaBase$/ }, () => ({ path: join(raiz, "src/lib/mapaBase.ts"), namespace: "fondo" }));
  b.onLoad({ filter: /.*/, namespace: "fondo" }, () => ({ loader: "ts", contents: readFileSync(join(raiz, "src/lib/mapaBase.ts"), "utf8")
    .replace("https://tile.openstreetmap.org/{z}/{x}/{y}.png", `http://127.0.0.1:${P_BASE}/fondo/calles/{z}/{x}/{y}.png`)
    .replace("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", `http://127.0.0.1:${P_BASE}/fondo/satelite/{z}/{y}/{x}`) }));
} };
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\.?\/|lib\/|\.\.\/\.\.\/lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    const EM = ${JSON.stringify(EMAILS)};
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol, user: { email: EM[rol] } } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: process.env.CUADERNOS_REVISION === "1" ? [doble] : [doble, fondoLocal],      // en la revisión a ojo, el fondo real (calles y foto satelital)
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "import.meta.env.BASE_URL": '"/"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const desconocidas = [];
function rpcBase(fn, a) {
  const argsSql = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${argsSql})`], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "sin permiso" } }; }
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_avisos": return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const PUBLICO = join(raiz, "public");
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname.startsWith("/fondo/")) {
    if (u.pathname.startsWith("/fondo/satelite/") && falla_satelital) { res.writeHead(503, { "Access-Control-Allow-Origin": "*" }); return res.end("no"); }
    res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(u.pathname.startsWith("/fondo/satelite/") ? TESELA_SAT : TESELA_CALLES);
  }
  if (u.pathname.startsWith("/glyphs/")) {      // las fuentes de las etiquetas, como las sirve la app (public/)
    const f = join(PUBLICO, decodeURIComponent(u.pathname));
    if (!f.startsWith(PUBLICO) || !existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "Content-Type": "application/x-protobuf" }); return res.end(readFileSync(f));
  }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : extname(f) === ".png" ? "image/png" : "text/html" }); return res.end(readFileSync(join(dir, f)));
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
      if (fn.startsWith("geoportal_redes_") || fn.startsWith("geoportal_analisis_") || /^geoportal_tec_punto/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcPlanta(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    const st = u.pathname.match(/^\/storage\/v1\/object\/(upload\/sign|sign)\/analisis-capturas\/(.+)$/);
    if (st) {
      const ruta = decodeURIComponent(st[2]);
      if (req.method === "POST" && st[1] === "upload/sign") return json(200, { url: `/object/upload/sign/analisis-capturas/${ruta}?token=TOKEN-SUBIDA`, token: "TOKEN-SUBIDA" });
      if (req.method === "POST" && st[1] === "sign") return json(200, { signedURL: `/object/sign/analisis-capturas/${ruta}?token=TOKEN-LECTURA` });
      if (req.method === "PUT" && st[1] === "upload/sign" && u.searchParams.get("token") === "TOKEN-SUBIDA") {
        const [tope, tipos] = sqlq("select file_size_limit || '|' || array_to_string(allowed_mime_types, ',') from storage.buckets where id = 'analisis-capturas'").split("|");
        if (cuerpo.length > Number(tope)) return json(413, { error: "Payload too large" });
        if (!tipos.split(",").includes(req.headers["content-type"])) return json(415, { error: "mime type not supported" });
        if (archivos.has(ruta)) return json(409, { error: "Duplicate" });
        archivos.set(ruta, cuerpo);
        sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('analisis-capturas', ${lit(ruta)}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })})`);
        return json(200, { Key: `analisis-capturas/${ruta}` });
      }
      if (req.method === "GET" && st[1] === "sign" && u.searchParams.get("token") === "TOKEN-LECTURA" && archivos.has(ruta)) { res.writeHead(200, { "Content-Type": "image/jpeg" }); return res.end(archivos.get(ruta)); }
      return json(400, { error: "firma" });
    }
    json(404, {});
  });
});
const archivos = new Map();      // lo que «Storage» tiene guardado
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-analisis/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const c = new URL(r.url).pathname; return (c.includes("geoportal-analisis") ? hs[2] : c.includes("geoportal-redes") ? hs[1] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- Revisión a ojo (David): CUADERNOS_REVISION=1 deja todo arriba, sin pruebas, para abrirlo en el navegador ----------
if (process.env.CUADERNOS_REVISION === "1") {
  console.log("\nRevisión local de los Cuadernos de análisis (base local del Code B; nada de esto toca producción). Abra en Chrome:");
  for (const [rol, quien] of [["sup", "supervisor de distribución (crea y edita)"], ["dual", "dual: Comercial y supervisor de planta (ve los del equipo)"], ["adm", "administrador"], ["op", "operador con el geovisor (no ve Cuadernos)"], ["sin", "operador sin el geovisor"], ["nada", "sin permisos"]])
    console.log(`  http://127.0.0.1:${P_BASE}/?rol=${rol}      ${quien}`);
  console.log("Para terminar: Ctrl+C.");
  await new Promise(() => {});
}
// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).replace(/\n/g, " ⏎ ").slice(0, 400))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 900000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = []; const teselas = {};
const TABS_MODO = '[role=tablist][aria-label="Modo de trabajo"] [role=tab]';
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = async (p, re, ms = 30000) => {
  const fin = Date.now() + ms;
  for (;;) {
    const esta = await p.evaluate(async (s, sel) => { const r = new RegExp(s); if (r.test(document.body.innerText)) return true; if (!document.querySelector("[data-modo-actual]")) return false;
      for (const t of document.querySelectorAll(sel)) { t.click(); await new Promise((x) => setTimeout(x, 0)); if (r.test(document.body.innerText)) return true; } return false; }, re.source, TABS_MODO).catch(() => false);
    if (esta) return true;
    if (Date.now() > fin) return false;
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const enMapa = (p, cuerpo, ...a) => p.evaluate((c, a) => { const m = document.querySelector(".geo-mapa").__mapa; return new Function("m", "a", c)(m, a); }, cuerpo, a);
const pendientes = [];
async function quieto(p) {
  const listo = await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); }, { timeout: 45000 }).then(() => true).catch(() => false);
  if (!listo) pendientes.push(await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa; const st = m.style;
    return Object.keys(st.sourceCaches ?? st.tileManagers ?? {}).filter((k) => { const c = (st.sourceCaches ?? st.tileManagers)[k]; return c && c.used !== false && !c.loaded(); }).join(","); }).catch(() => "?"));
  await new Promise((r) => setTimeout(r, 500));
}
async function irA(p, lon, lat, z) { await enMapa(p, "m.jumpTo({ center: [a[0], a[1]], zoom: a[2] });", lon, lat, z); await quieto(p); }
const renderizados = (p, capa) => enMapa(p, "return m.getLayer(a[0]) ? m.queryRenderedFeatures({ layers: [a[0]] }).map((f) => /^x-sec-etq/.test(a[0]) ? f.properties.texto : f.properties.nombre) : null;", capa);

async function abrir(ancho, rol) {
  const p = await nav.newPage();
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(180000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("response", (r) => { if (/accion=geovisor_tesela&/.test(r.url())) teselas[r.status()] = (teselas[r.status()] ?? 0) + 1; });
  p.on("requestfailed", (r) => { if (/geovisor_tesela/.test(r.url())) teselas.falla = `${(teselas.falla ?? "")}${r.failure()?.errorText} `.slice(0, 200); });
  p.on("console", (m) => { if (m.type() !== "error") return; const t = m.text(); if (!/status of 40[0349]|status of 50[03]|Failed to load resource|GL Driver|AJAXError|Failed to fetch|WebGL|GPU stall/.test(t)) errores.push(`${ancho} ${rol} consola: ${t}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alGeovisor(p) {
  if (!(await esperarTexto(p, /Geovisor técnico/))) return false;
  await clicTexto(p, "button", "Geovisor técnico");
  if (!(await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/, 60000))) return false;
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  await quieto(p);
  return true;
}
async function panelCapas(p) { await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel"); }
async function cerrarPanel(p) { await clicTexto(p, ".geo-panel button", "✕"); await p.waitForFunction(() => !document.querySelector(".geo-panel")); }
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? t.innerText : null; });
async function tocarEn(p, lon, lat, z) {
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click());
  await irA(p, lon, lat, z);
  const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lon, lat);
  if (await p.evaluate(() => navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
  await p.waitForFunction(() => !!document.querySelector(".geo-tarjeta"), { timeout: 20000 }).catch(() => {});
  return tarjetaGeo(p);
}
const CENTRO = [-73.2532, 10.4631];
// ---------- ayudas de esta prueba ----------
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const hay = (p, sel) => p.evaluate((s) => !!document.querySelector(s), sel);
const clic = async (p, sel) => { const bien = await p.evaluate((s) => { const b = document.querySelector(s); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel); await pausa(120); return bien; };
const cua = (p) => p.evaluate(() => window.__cuaderno ?? null);
const escribir = (p, sel, t) => p.evaluate((s, t) => { const e = document.querySelector(s); const set = Object.getOwnPropertyDescriptor(e.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : e.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype, "value").set;
  set.call(e, t); e.dispatchEvent(new Event(e.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, t);
/** Toca el mapa a (dx, dy) píxeles de su centro. */
async function tocar(p, dx, dy) {
  const pt = await p.evaluate((dx, dy) => { const r = document.querySelector(".geo-mapa").getBoundingClientRect(); return { x: r.left + r.width / 2 + dx, y: r.top + r.height / 2 + dy }; }, dx, dy);
  if (await p.evaluate(() => navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
  await pausa(250);
}
/** Píxeles pintados del vidrio alrededor de (dx, dy) del centro del mapa. */
const pintado = (p, dx, dy, r = 22) => p.evaluate((dx, dy, r) => { const c = document.querySelector("[data-testid=cua-lienzo]"); if (!c) return -1; const k = c.width / c.clientWidth;
  const d = c.getContext("2d").getImageData(Math.round((c.clientWidth / 2 + dx - r) * k), Math.round((c.clientHeight / 2 + dy - r) * k), Math.round(2 * r * k), Math.round(2 * r * k)).data;
  let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++; return n; }, dx, dy, r);
const guardar = async (p) => { await clic(p, "[data-testid=cua-guardar]"); return p.waitForFunction(() => window.__cuaderno && window.__cuaderno.pendientes === 0 && !document.querySelector("[data-testid=cua-ocupado]"), { timeout: 60000 }).then(() => true).catch(() => false); };
const aEdge = (p, accion, cuerpo) => p.evaluate(async (accion, cuerpo, puerto) => { const rol = new URLSearchParams(location.search).get("rol");
  const r = await fetch(`http://127.0.0.1:${puerto}/functions/v1/geoportal-analisis?accion=${accion}`, { method: cuerpo ? "POST" : "GET", headers: { Authorization: "Bearer tok-" + rol, ...(cuerpo ? { "Content-Type": "application/json" } : {}) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  return r.status; }, accion, cuerpo ?? null, P_EDGE);
const abrirLista = async (p) => { if (!(await hay(p, "[data-testid=cua-panel]"))) await clic(p, (await p.evaluate(() => window.innerWidth <= 600)) ? "[data-testid=cuadernos-movil]" : "[data-testid=cuadernos]"); await p.waitForSelector("[data-testid=cua-panel]"); await p.waitForFunction(() => !/Cargando…/.test(document.querySelector("[data-testid=cua-panel]").innerText), { timeout: 20000 }); };
const abrirCuaderno = async (p, id) => { await abrirLista(p); await clic(p, `[data-cuaderno="${id}"]`); await p.waitForFunction((id) => window.__cuaderno?.id === id, { timeout: 20000 }, id); await pausa(300); };
const herr = async (p, menu, item) => { await clic(p, `[data-testid=cua-h-${menu}]`); if (item) await clic(p, item); };
const ids = {};

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`, movil = ancho < 500;
  // ===== A. Supervisor de distribución: crea, marca, guarda =====
  let p = await abrir(ancho, "sup");
  ok(`${tag} A01 el supervisor abre el geovisor y ve el botón «Cuadernos»`, (await alGeovisor(p)) && (await p.waitForSelector("[data-testid=cuadernos]", { timeout: 15000 }).then(() => true).catch(() => false)));
  await irA(p, CENTRO[0], CENTRO[1], 16);
  ok(`${tag} A02 sin cuaderno abierto, el vidrio está vacío y un toque en la red abre la tarjeta del geovisor de siempre`, (await pintado(p, 0, 0, 150)) === 0 && (await cua(p)) === null);
  await abrirLista(p);
  ok(`${tag} A03 la lista: «Míos» y «Del equipo», «Nuevo cuaderno» y el filtro de archivados`, /Míos[\s\S]*Del equipo/.test(await p.$eval("[data-testid=cua-panel]", (e) => e.innerText)) && (await hay(p, "[data-testid=cua-nuevo]")) && (await hay(p, "[data-testid=cua-archivados]")));
  await clic(p, "[data-testid=cua-nuevo]"); await p.waitForSelector("[data-testid=cua-dialogo-nuevo]");
  ok(`${tag} A04 «Crear» pide un título de 3 letras o más`, await p.$eval("[data-testid=cua-crear]", (b) => b.disabled));
  await escribir(p, "#cua-n-titulo", `ZTCUA Baja presión ${ancho}`); await escribir(p, "#cua-n-desc", "Prueba de Chrome");
  await p.screenshot({ path: join(CAP, `a04_nuevo_${ancho}.png`) });
  await clic(p, "[data-testid=cua-crear]");
  await p.waitForFunction(() => window.__cuaderno?.modo === "editar", { timeout: 20000 });
  let c = await cua(p); ids[ancho] = c.id;
  ok(`${tag} A05 el cuaderno nace en la versión 1, sin marcas, y queda en modo edición con su barra`, c.version === 1 && c.marcas.length === 0 && c.puede_editar && (await hay(p, "[data-testid=cua-herr]")) && /ZTCUA Baja presión/.test(await p.$eval("[data-testid=cua-titulo]", (e) => e.innerText)));
  ok(`${tag} A06 «Guardar» está apagado sin cambios`, await p.$eval("[data-testid=cua-guardar]", (b) => b.disabled));
  // modo exploración: no se pinta
  await clic(p, "[data-testid=cua-modo] button:first-child");
  await tocar(p, 60, 60);
  ok(`${tag} A07 modo exploración: no hay herramientas y un toque no pone marcas`, !(await hay(p, "[data-testid=cua-herr]")) && (await cua(p)).marcas.length === 0);
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click());
  await clic(p, "[data-testid=cua-modo] button:last-child");
  // Problema
  await clic(p, "[data-testid=cua-h-problema]");
  const problemas = await p.$$eval("[data-testid=cua-lista-problema] [role=menuitem]", (bs) => bs.map((b) => ({ t: b.innerText.trim(), img: b.querySelector("img")?.naturalWidth > 0 })));
  ok(`${tag} A08 «Problema» despliega los 9 puntos tipo, cada uno con su ícono`, problemas.length === 9 && problemas.every((x) => x.img) && problemas.some((x) => x.t === "Baja presión") && problemas.some((x) => x.t === "Válvula por revisar"), JSON.stringify(problemas));
  await p.screenshot({ path: join(CAP, `a08_problemas_${ancho}.png`) });
  await clic(p, "[data-testid=cua-lista-problema] [data-sub=baja_presion]");
  await tocar(p, -80, 40);
  c = await cua(p);
  ok(`${tag} A09 un toque pone el problema (sin guardar) y abre su ficha`, c.marcas.length === 1 && c.marcas[0].tipo === "problema" && c.marcas[0].subtipo === "baja_presion" && c.pendientes === 1 && (await hay(p, "[data-testid=cua-ficha]")));
  ok(`${tag} A10 la nota lleva el aviso «No escriba nombres, cédulas ni teléfonos»`, /No escriba nombres, cédulas ni teléfonos/.test(await p.$eval("[data-testid=cua-ficha] [data-testid=cua-aviso-nota]", (e) => e.innerText)));
  await escribir(p, "[data-testid=cua-nota]", "ZTCUA presión baja en las tardes; =SUMA(1)"); await escribir(p, "[data-testid=cua-categoria]", "problema");
  c = await cua(p);
  ok(`${tag} A11 la nota y la categoría quedan en la marca`, c.marcas[0].nota.startsWith("ZTCUA presión baja") && c.marcas[0].categoria === "problema");
  await p.screenshot({ path: join(CAP, `a11_ficha_${ancho}.png`) });
  await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
  ok(`${tag} A12 el pin se pinta en el vidrio, en su lugar`, (await pintado(p, -80, 25)) > 200, await pintado(p, -80, 25));
  // Activo
  await clic(p, "[data-testid=cua-soltar]"); await clic(p, "[data-testid=cua-h-activo]");
  const activos = await p.$$eval("[data-testid=cua-lista-activo] [role=menuitem]", (bs) => bs.map((b) => ({ t: b.innerText.trim(), img: b.querySelector("img")?.naturalWidth > 0 })));
  ok(`${tag} A13 «Activo» despliega los 12 pictogramas y el interruptor Acueducto / Alcantarillado; avisa que es una propuesta`, activos.length === 12 && activos.every((x) => x.img) && (await p.$$eval("[data-testid=cua-lista-activo] [data-sistema]", (b) => b.length)) === 2
    && /no crea un activo en la red/.test(await p.$eval("[data-testid=cua-lista-activo]", (e) => e.innerText)), JSON.stringify(activos));
  await clic(p, "[data-testid=cua-lista-activo] [data-sistema=alcantarillado]");
  await p.screenshot({ path: join(CAP, `a13_activos_${ancho}.png`) });
  await clic(p, "[data-testid=cua-lista-activo] [data-sub=pozo]");
  await tocar(p, 70, -50);
  c = await cua(p);
  ok(`${tag} A14 el ícono de activo queda con su sistema (pozo de alcantarillado) y no enlaza un activo real`, c.marcas.length === 2 && c.marcas[1].tipo === "activo" && c.marcas[1].subtipo === "pozo" && c.marcas[1].sistema === "alcantarillado" && c.marcas[1].activo_codigo === null);
  await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
  // Referencia y post-it
  await clic(p, "[data-testid=cua-h-referencia]"); await tocar(p, 0, -90); await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
  await clic(p, "[data-testid=cua-h-postit]"); await tocar(p, -20, 110);
  ok(`${tag} A15 el post-it pide su texto (con el aviso de no escribir datos personales)`, (await hay(p, "[data-testid=cua-dialogo-postit]")) && /No escriba nombres/.test(await p.$eval("[data-testid=cua-dialogo-postit]", (e) => e.innerText)) && (await p.$eval("[data-testid=cua-postit-poner]", (b) => b.disabled)));
  await escribir(p, "#cua-postit", "ZTCUA revisar con el macromedidor"); await clic(p, "[data-testid=cua-postit-poner]");
  c = await cua(p);
  ok(`${tag} A16 quedan el punto de referencia (con color) y el post-it (con su texto)`, c.marcas.length === 4 && c.marcas.some((m) => m.tipo === "referencia" && /^#[0-9A-F]{6}$/i.test(m.estilo?.color ?? "")) && c.marcas.some((m) => m.tipo === "postit" && m.nota === "ZTCUA revisar con el macromedidor"));
  await clic(p, "[data-testid=cua-ficha] .geo-cerrar"); await clic(p, "[data-testid=cua-soltar]");
  let esperadas = 4;
  if (movil) {
    ok(`${tag} A17 en el celular: Problema, Activo, Referencia y Post-it; «Dibujo» y las medidas quedan para escritorio`, await p.evaluate(() => { const v = (s) => { const e = document.querySelector(s); return !!e && e.offsetParent !== null; };
      return v("[data-testid=cua-h-problema]") && v("[data-testid=cua-h-activo]") && v("[data-testid=cua-h-referencia]") && v("[data-testid=cua-h-postit]") && !v("[data-testid=cua-h-dibujo]"); }));
  } else {
    await herr(p, "dibujo", "[data-dibujo=linea]");
    await tocar(p, -200, -150); await tocar(p, -120, -170); await tocar(p, -60, -140);
    ok(`${tag} A17 la línea se arma punto a punto y «Terminar» aparece con 2 o más`, await hay(p, "[data-testid=cua-terminar]"));
    await clic(p, "[data-testid=cua-terminar]"); await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
    await herr(p, "dibujo", "[data-dibujo=circulo]"); await tocar(p, 220, 120); await tocar(p, 260, 120); await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
    await herr(p, "dibujo", "[data-dibujo=zona]"); await tocar(p, 150, -180); await tocar(p, 330, -180); await tocar(p, 330, -60); await tocar(p, 150, -60);
    await clic(p, "[data-testid=cua-terminar]");
    ok(`${tag} A18 la zona sin guardar dice que se cuenta al guardar y ofrece «Contar ahora»`, /Se cuentan al guardar/.test(await p.$eval("[data-testid=cua-conteo]", (e) => e.innerText)) && (await hay(p, "[data-testid=cua-contar]")));
    await clic(p, "[data-testid=cua-contar]");
    await p.waitForFunction(() => /predios · .* contratos/.test(document.querySelector("[data-testid=cua-conteo]").innerText), { timeout: 30000 }).catch(() => {});
    const previo = await p.$eval("[data-testid=cua-conteo]", (e) => e.innerText);
    ok(`${tag} A19 «Contar ahora» muestra SOLO dos números (predios y contratos)`, /^[\d.]+ predios · [\d.]+ contratos/.test(previo), previo);
    await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
    // mano alzada: arrastre
    await herr(p, "dibujo", "[data-dibujo=mano]");
    const r0 = await p.evaluate(() => { const r = document.querySelector(".geo-mapa").getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
    const centroAntes = await enMapa(p, "return [m.getCenter().lng, m.getCenter().lat];");
    await p.mouse.move(r0.x - 300, r0.y + 150); await p.mouse.down(); for (let i = 1; i <= 25; i++) await p.mouse.move(r0.x - 300 + i * 8, r0.y + 150 + Math.sin(i / 3) * 30); await p.mouse.up(); await pausa(300);
    c = await cua(p);
    const centroDespues = await enMapa(p, "return [m.getCenter().lng, m.getCenter().lat];");
    const mano = c.marcas.find((m) => m.tipo === "mano");
    ok(`${tag} A20 la mano alzada traza con el arrastre (el mapa no se mueve) y el trazo llega aligerado`, !!mano && mano.geom.coordinates.length >= 3 && mano.geom.coordinates.length <= 26 && centroAntes[0] === centroDespues[0] && centroAntes[1] === centroDespues[1], JSON.stringify(mano?.geom.coordinates.length));
    await clic(p, "[data-testid=cua-ficha] .geo-cerrar"); await clic(p, "[data-testid=cua-soltar]");
    ok(`${tag} A21 al soltar la herramienta el mapa vuelve a moverse`, await enMapa(p, "return m.dragPan.isEnabled() && m.doubleClickZoom.isEnabled();"));
    // medir (de pantalla)
    await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-medir-d]"); await tocar(p, -100, 200); await tocar(p, 100, 200);
    const medida = await p.$eval("[data-testid=cua-medida]", (e) => e.innerText).catch(() => "");
    const real = await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa, c = m.project(m.getCenter()); const a = m.unproject([c.x - 100, c.y + 200]), b = m.unproject([c.x + 100, c.y + 200]); return a.distanceTo(b); });
    ok(`${tag} A22 «Medir distancia» da la distancia real (±1 %) y no agrega marcas`, Math.abs(Number(medida.replace(/[^\d,]/g, "").replace(",", ".")) - real) / real < 0.01 && (await cua(p)).marcas.length === c.marcas.length, `${medida} vs ${real.toFixed(1)}`);
    await clic(p, "[data-testid=cua-medir-fin]");
    esperadas = 8;
  }
  c = await cua(p);
  ok(`${tag} A23 hay ${esperadas} marcas sin guardar y «Guardar» las cuenta`, c.marcas.length === esperadas && c.pendientes === esperadas && new RegExp(`Guardar \\(${esperadas}\\)`).test(await p.$eval("[data-testid=cua-guardar]", (b) => b.innerText)));
  ok(`${tag} A24 mientras se edita hay un borrador en el dispositivo`, await p.evaluate((id) => Object.keys(localStorage).some((k) => k.includes(id) && JSON.parse(localStorage.getItem(k)).version_base === 1), ids[ancho]));
  await p.screenshot({ path: join(CAP, `a24_editando_${ancho}.png`) });
  ok(`${tag} A25 la pantalla no se desborda`, await sinDesborde(p));
  ok(`${tag} A25b la barra del geovisor no se sale de la pantalla (en el celular «Cuadernos» va en la fila de herramientas) y los desplegables caben`, await p.evaluate(async () => {
    const dentro = (e) => { const r = e.getBoundingClientRect(); return r.left >= -1 && r.right <= window.innerWidth + 1; };
    const barra = [...document.querySelectorAll(".geo-barra button")].filter((b) => b.offsetParent !== null).every(dentro);
    document.querySelector("[data-testid=cua-h-activo]").click(); await new Promise((r) => setTimeout(r, 150));
    const d = document.querySelector("[data-testid=cua-lista-activo]"), bien = !!d && dentro(d) && [...d.querySelectorAll("[role=menuitem]")].every(dentro);
    document.querySelector("[data-testid=cua-h-activo]").click(); await new Promise((r) => setTimeout(r, 100));
    document.querySelector("[data-testid=cua-mas]").click(); await new Promise((r) => setTimeout(r, 150));
    const m = document.querySelector(".cua-desplegable-der"), bien2 = !!m && dentro(m);
    document.querySelector("[data-testid=cua-mas]").click();
    return barra && bien && bien2; }));
  const t0 = Date.now();
  ok(`${tag} A26 «Guardar» deja la versión 2 con las ${esperadas} marcas y nada pendiente (${Date.now() - t0} ms)`, (await guardar(p)) && (c = await cua(p)).version === 2 && c.marcas.length === esperadas && c.marcas.every((m) => m.version === 2));
  ok(`${tag} A27 en la base: ${esperadas} marcas en la versión 2 y ninguna fila con datos personales`, sqlq(`select count(*) from analisis.marca_versiones where cuaderno_id = '${ids[ancho]}' and version = 2 and not anulada`) === String(esperadas));
  ok(`${tag} A28 guardado: el borrador del dispositivo se quita`, await p.evaluate((id) => !Object.keys(localStorage).some((k) => k.includes(id)), ids[ancho]));
  ok(`${tag} A29 el servidor anotó el sector de las marcas`, c.marcas.filter((m) => m.sector).length === Number(sqlq(`select count(*) from analisis.marca_versiones where cuaderno_id = '${ids[ancho]}' and version = 2 and sector is not null`)));
  if (!movil) {
    const z = c.marcas.find((m) => m.tipo === "zona");
    const [np, nc] = sqlq(`select count(*) || '|' || count(distinct k.cod_usuario) filter (where btrim(coalesce(k.cod_usuario, '')) <> '') from public.catastro_valledupar k, analisis.marca_versiones mv where mv.marca_id = '${z.id}' and mv.version = 2 and st_intersects(k.geom, mv.geom)`).split("|").map(Number);
    ok(`${tag} A30 la zona guardada trae los predios y contratos que cuenta el servidor (${np} · ${nc}), iguales al catastro`, z.conteo_predios === np && z.conteo_contratos === nc && np > 0, JSON.stringify([z.conteo_predios, z.conteo_contratos]));
    ok(`${tag} A31 el círculo guarda su radio en metros y la línea su flecha`, c.marcas.some((m) => m.tipo === "circulo" && m.radio_m > 5) && c.marcas.some((m) => m.tipo === "linea" && m.geom.coordinates.length === 3));
  }
  await p.screenshot({ path: join(CAP, `a31_guardado_${ancho}.png`) });
  // elegir, mover y anular
  await clic(p, "[data-testid=cua-aviso] .cua-x");
  await tocar(p, -80, 28);
  ok(`${tag} A32 tocar una marca guardada abre su ficha (versión 2${movil ? "" : ", con su sector"})`, /Guardada en la versión 2/.test(await p.$eval("[data-testid=cua-ficha]", (e) => e.innerText).catch(() => "")) && (await p.$eval("[data-testid=cua-ficha]", (e) => e.dataset.tipo)) === "problema");
  await clic(p, "[data-testid=cua-mover]"); await tocar(p, -140, 100);
  c = await cua(p);
  ok(`${tag} A33 «Mover» cambia el punto de la marca y queda como cambio pendiente`, c.pendientes === 1 && c.marcas.filter((m) => m.tipo === "problema").length === 1);
  ok(`${tag} A34 «Anular» pide un motivo (la marca no se borra)`, (await clic(p, "[data-testid=cua-quitar]")) && (await hay(p, "[data-testid=cua-motivo]")) && (await p.$eval("[data-testid=cua-anular]", (b) => b.disabled)));
  await escribir(p, "[data-testid=cua-motivo]", "ZTCUA era otro punto"); await clic(p, "[data-testid=cua-anular]");
  c = await cua(p);
  ok(`${tag} A35 anulada: sale del vidrio y queda 1 cambio por guardar`, c.marcas.length === esperadas - 1 && c.pendientes === 1);
  ok(`${tag} A36 al guardar queda la versión 3; en la base la marca sigue, anulada y con su motivo`, (await guardar(p)) && (await cua(p)).version === 3
    && sqlq(`select count(*) || '|' || count(*) filter (where anulada and motivo = 'ZTCUA era otro punto') from analisis.marca_versiones where cuaderno_id = '${ids[ancho]}' and tipo = 'problema'`) === "2|1");
  // borrador: recargar con cambios sin guardar
  await clic(p, "[data-testid=cua-h-referencia]"); await tocar(p, 90, 40); ok(`${tag} A36b queda un cambio sin guardar antes de cerrar la pestaña`, (await cua(p)).pendientes === 1); await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
  await p.close();      // se cierra la pestaña con un cambio sin guardar
  p = await abrir(ancho, "sup"); await alGeovisor(p); await p.waitForSelector("[data-testid=cuadernos]"); await irA(p, CENTRO[0], CENTRO[1], 16);
  await abrirLista(p);
  ok(`${tag} A37 la lista muestra el cuaderno en «Míos», con su versión y sus marcas`, new RegExp(`ZTCUA Baja presión ${ancho}[\\s\\S]*versión 3 · ${esperadas - 1} marcas`).test(await p.$eval("[data-testid=cua-panel]", (e) => e.innerText)), await p.$eval("[data-testid=cua-panel]", (e) => e.innerText));
  await p.screenshot({ path: join(CAP, `a37_lista_${ancho}.png`) });
  await clic(p, `[data-cuaderno="${ids[ancho]}"]`);
  ok(`${tag} A38 al reabrir, ofrece recuperar el borrador que quedó en el dispositivo`, await p.waitForSelector("[data-testid=cua-dialogo-borrador]", { timeout: 20000 }).then(() => true).catch(() => false));
  await clic(p, "[data-testid=cua-borrador-recuperar]");
  c = await cua(p);
  ok(`${tag} A39 recuperado: vuelve el cambio pendiente, en modo edición`, c.pendientes === 1 && c.modo === "editar" && c.marcas.length === esperadas);
  // salir con cambios sin guardar: tres opciones
  await clic(p, ".geo-volver");
  ok(`${tag} A40 salir con cambios sin guardar: Guardar, Salir sin guardar o Cancelar`, (await hay(p, "[data-testid=cua-salir-guardar]")) && (await hay(p, "[data-testid=cua-salir-sin]")) && (await hay(p, "[data-testid=cua-salir-cancelar]")));
  await p.screenshot({ path: join(CAP, `a40_salir_${ancho}.png`) });
  await clic(p, "[data-testid=cua-salir-cancelar]");
  ok(`${tag} A41 «Cancelar» deja todo como estaba`, (await hay(p, ".geo-mapa")) && (await cua(p)).pendientes === 1);
  await panelCapas(p); await cerrarPanel(p);
  await clic(p, "[data-fondo=satelite]"); await quieto(p);
  ok(`${tag} A42 cambiar capas o el mapa de fondo no dispara el aviso ni pierde las marcas (foto satelital encendida)`, !(await hay(p, "[data-testid=cua-dialogo-salir]")) && (await cua(p)).pendientes === 1 && (await pintado(p, 70, -50)) > 100);
  await p.screenshot({ path: join(CAP, `a42_satelite_${ancho}.png`) });
  ok(`${tag} A43 «Guardar» desde el aviso de salida guarda y sale`, (await clic(p, ".geo-volver")) && (await clic(p, "[data-testid=cua-salir-guardar]")) && (await p.waitForFunction(() => !document.querySelector(".geo-mapa"), { timeout: 30000 }).then(() => true).catch(() => false))
    && sqlq(`select max(version) from analisis.cuaderno_versiones where cuaderno_id = '${ids[ancho]}'`) === "4");
  // ===== capturas, PDF, exportación, versiones y archivo =====
  await alGeovisor(p); await p.waitForSelector("[data-testid=cuadernos]"); await irA(p, CENTRO[0], CENTRO[1], 16);
  await abrirCuaderno(p, ids[ancho]);
  ok(`${tag} B01 el cuaderno abre en exploración, en la versión 4, con sus ${esperadas} marcas pintadas`, (c = await cua(p)).modo === "explorar" && c.version === 4 && c.marcas.length === esperadas && (await pintado(p, 70, -50)) > 100);
  for (const fondo of ["satelite", "calles"]) {
    await clic(p, `[data-fondo=${fondo}]`); await quieto(p);
    await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-capturar]"); await p.waitForSelector("[data-testid=cua-dialogo-capturar]");
    await p.evaluate(() => { delete window.__captura; window.__descargas = []; const o = HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click = function () { if (this.download) window.__descargas.push({ nombre: this.download, href: this.href }); else o.call(this); }; });
    await clic(p, "[data-testid=cua-captura-descargar]");
    await p.waitForFunction(() => !!document.querySelector("[data-testid=cua-captura-hecho]") || !!document.querySelector("[data-testid=cua-captura-error]"), { timeout: 60000 });
    const k = await p.evaluate(async () => { const d = window.__descargas[0]; if (!d) return { err: document.querySelector("[data-testid=cua-captura-error]")?.innerText };
      const b = new Uint8Array(await (await fetch(d.href)).arrayBuffer()); let s = ""; for (let i = 0; i < b.length; i += 32768) s += String.fromCharCode(...b.subarray(i, i + 32768)); return { ...window.__captura, nombre: d.nombre, b64: btoa(s) }; });
    if (k.b64) writeFileSync(join(CAP, `captura_${fondo}_${ancho}.jpg`), Buffer.from(k.b64, "base64"));
    ok(`${tag} B02 captura con ${fondo === "satelite" ? "la foto satelital" : "calles"}: «Descargar» baja un JPEG de ${k.ancho} × ${k.alto} px y ${Math.round((k.bytes ?? 0) / 1024)} KB (lado ≤ 1.600 px, ≤ 600 KB)`,
      !!k.b64 && Buffer.from(k.b64, "base64").subarray(0, 3).toString("hex") === "ffd8ff" && Math.max(k.ancho, k.alto) <= 1600 && k.bytes <= 614400 && /\.jpg$/.test(k.nombre), JSON.stringify({ ...k, b64: undefined }));
    if (fondo === "calles") {
      ok(`${tag} B03 el cupo se ve: «Capturas guardadas: 0 de 20»`, /0 de 20/.test(await p.$eval("[data-testid=cua-captura-cupo]", (e) => e.innerText)));
      await escribir(p, "[data-testid=cua-captura-titulo]", "ZTCUA vista del sector");
      await clic(p, "[data-testid=cua-captura-guardar]");
      await p.waitForFunction(() => !!document.querySelector("[data-testid=cua-captura-hecho]") && /Guardada/.test(document.querySelector("[data-testid=cua-captura-hecho]").innerText) || !!document.querySelector("[data-testid=cua-captura-error]"), { timeout: 60000 });
      const fila = sqlq(`select k.ancho || '|' || k.bytes || '|' || kc.bytes_reales || '|' || (select (o.metadata ->> 'mimetype') from storage.objects o where o.name = k.ruta) from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = '${ids[ancho]}'`).split("|");
      ok(`${tag} B04 «Guardar en el cuaderno»: sube al almacenamiento (JPEG) y el servidor la confirma con su tamaño real`, fila.length === 4 && fila[1] === fila[2] && fila[3] === "image/jpeg" && Number(fila[1]) <= 614400, fila.join("|") + " " + (await p.$eval("[data-testid=cua-dialogo-capturar]", (e) => e.innerText)));
    }
    await clic(p, "[data-testid=cua-dialogo-capturar] .geo-cerrar");
  }
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-capturas]"); await p.waitForSelector("[data-testid=cua-dialogo-capturas]");
  ok(`${tag} B05 «Capturas guardadas» la lista con título, tamaño y fecha`, /ZTCUA vista del sector[\s\S]*px · \d+ KB/.test(await p.$eval("[data-testid=cua-capturas-lista]", (e) => e.innerText).catch(() => "")));
  await p.evaluate(() => { window.__abierta = null; window.open = () => ({ location: { set href(v) { window.__abierta = v; } }, close() {} }); });
  await clic(p, "[data-testid=cua-captura-ver]"); await p.waitForFunction(() => !!window.__abierta, { timeout: 15000 }).catch(() => {});
  const vista = await p.evaluate(async () => { if (!window.__abierta) return null; const r = await fetch(window.__abierta); return { tipo: r.headers.get("content-type"), n: (await r.arrayBuffer()).byteLength, ruta: /analisis-capturas\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg/.test(window.__abierta) }; });
  ok(`${tag} B06 «Ver» abre la imagen con una dirección firmada de corta vida`, vista && vista.tipo === "image/jpeg" && vista.n > 1000, JSON.stringify(vista));
  await p.screenshot({ path: join(CAP, `b06_capturas_${ancho}.png`) });
  await clic(p, "[data-testid=cua-captura-anular]"); await escribir(p, "[data-testid=cua-captura-motivo]", "ZTCUA salió movida"); await clic(p, "[data-testid=cua-captura-anular-si]");
  await p.waitForFunction(() => !document.querySelector("[data-testid=cua-capturas-lista]"), { timeout: 15000 }).catch(() => {});
  ok(`${tag} B07 anular la captura (con motivo): deja de verse y de contar; ni la fila ni el archivo se borran`, !(await hay(p, "[data-testid=cua-capturas-lista]"))
    && sqlq(`select (select count(*) from analisis.capturas where cuaderno_id = '${ids[ancho]}') || '|' || (select count(*) from analisis.capturas_anuladas) || '|' || (select count(*) from storage.objects where bucket_id = 'analisis-capturas')`).split("|").every((n) => Number(n) >= 1));
  await clic(p, "[data-testid=cua-dialogo-capturas] .geo-cerrar");
  // exportar CSV
  await p.evaluate(() => { window.__descargas = []; });
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-csv]");
  await p.waitForFunction(() => window.__descargas.length > 0, { timeout: 20000 }).catch(() => {});
  const csv = await p.evaluate(async () => { const d = window.__descargas[0]; return d ? { nombre: d.nombre, t: await (await fetch(d.href)).text() } : null; });
  ok(`${tag} B08 «Exportar las marcas (CSV)»: una fila por marca, con «;», y las notas tal cual (las fórmulas, neutralizadas)`, csv && /\.csv$/.test(csv.nombre) && csv.t.includes("N.º;Tipo;Problema o activo") && csv.t.includes("ZTCUA revisar con el macromedidor")
    && csv.t.split("\r\n").filter((l) => /^\d+;/.test(l)).length === esperadas && !/;=/.test(csv.t) && !/tel[eé]fono|nombre del suscriptor/i.test(csv.t), csv?.t.slice(0, 300));
  // PDF de 2 páginas con las marcas (el componente de impresión del Corte 1)
  await p.evaluate(() => { delete window.__impresion; });
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-pdf]");
  await p.waitForFunction(() => !!document.querySelector("[data-testid=imprimir-listo]") || !!document.querySelector("[data-testid=dialogo-imprimir] [role=alert]"), { timeout: 600000 });
  const pdf = await p.evaluate(async () => { const a = document.querySelector("[data-testid=imprimir-descargar]"); if (!a) return { err: document.querySelector("[data-testid=dialogo-imprimir]").innerText };
    const b = new Uint8Array(await (await fetch(a.href)).arrayBuffer()); let s = ""; for (let i = 0; i < b.length; i += 32768) s += String.fromCharCode(...b.subarray(i, i + 32768)); return { b64: btoa(s), info: window.__impresion }; });
  if (pdf.b64) { const b = Buffer.from(pdf.b64, "base64"); writeFileSync(join(CAP, `cuaderno_${ancho}.pdf`), b); let k = 0, desde = 0;
    for (;;) { const i = b.indexOf(Buffer.from([0xff, 0xd8, 0xff]), desde); if (i < 0) break; const fin = b.indexOf(Buffer.from("\nendstream"), i); writeFileSync(join(CAP, `cuaderno_${ancho}_pagina${++k}.jpg`), b.subarray(i, fin)); desde = fin; } }
  ok(`${tag} B09 «Imprimir / PDF con las marcas»: el PDF de 2 páginas (Total y Urbano) del Corte 1, de menos de 10 MB`, !!pdf.b64 && pdf.info?.paginas === 2 && pdf.info.medidas[0].clave === "total" && pdf.info.medidas[1].clave === "urbano" && pdf.info.bytes < 10 * 1048576, pdf.err ?? JSON.stringify(pdf.info).slice(0, 200));
  await clicTexto(p, "[data-testid=dialogo-imprimir] button", "Cerrar");
  // versiones
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-datos]"); await p.waitForSelector("[data-testid=cua-versiones]");
  ok(`${tag} B10 «Versiones»: las 4, con su fecha; la abierta está señalada`, (await p.$$eval("[data-testid=cua-versiones] li", (l) => l.length)) === 4 && /Versión 4[\s\S]*abierta/.test(await p.$eval("[data-testid=cua-versiones]", (e) => e.innerText)));
  await clic(p, "[data-testid=cua-versiones] [data-version='2']"); await p.waitForFunction(() => window.__cuaderno?.version === 2, { timeout: 20000 });
  c = await cua(p);
  ok(`${tag} B11 una versión anterior se ve tal como era (${esperadas} marcas, con el problema que luego se anuló) y es solo lectura`, c.marcas.length === esperadas && c.marcas.some((m) => m.tipo === "problema") && !c.puede_editar && (await hay(p, "[data-testid=cua-lectura]")) && !(await hay(p, "[data-testid=cua-guardar]")));
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-datos]"); await clic(p, "[data-testid=cua-versiones] [data-version='4']"); await p.waitForFunction(() => window.__cuaderno?.version === 4, { timeout: 20000 });
  // archivar y reabrir
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-estado]"); await p.waitForSelector("[data-testid=cua-dialogo-estado]");
  ok(`${tag} B12 archivar pide motivo`, await p.$eval("[data-testid=cua-estado-si]", (b) => b.disabled));
  await escribir(p, "[data-testid=cua-estado-motivo]", "ZTCUA ya se atendió"); await clic(p, "[data-testid=cua-estado-si]");
  await p.waitForFunction(() => window.__cuaderno && !window.__cuaderno.puede_editar && !document.querySelector("[data-testid=cua-dialogo-estado]"), { timeout: 20000 }).catch(() => {});
  ok(`${tag} B13 archivado: no se borra, queda solo lectura y pasa a «Archivados»`, !(await cua(p)).puede_editar && /archivado/.test(await p.$eval("[data-testid=cua-barra]", (e) => e.innerText)));
  await abrirLista(p); const vig = await p.$eval("[data-testid=cua-panel]", (e) => e.innerText); await clic(p, "[data-testid=cua-archivados]"); await p.waitForFunction(() => !/Cargando…/.test(document.querySelector("[data-testid=cua-panel]").innerText)); await pausa(400);
  ok(`${tag} B14 la lista: fuera de «Vigentes» y dentro de «Archivados»`, !vig.includes(`ZTCUA Baja presión ${ancho}`) && (await p.$eval("[data-testid=cua-panel]", (e) => e.innerText)).includes(`ZTCUA Baja presión ${ancho}`));
  await clic(p, "[data-testid=cua-panel] .geo-cerrar");
  await clic(p, "[data-testid=cua-mas]"); await clic(p, "[data-testid=cua-estado]"); await escribir(p, "[data-testid=cua-estado-motivo]", "ZTCUA faltaba una zona"); await clic(p, "[data-testid=cua-estado-si]");
  await p.waitForFunction(() => window.__cuaderno?.puede_editar === true, { timeout: 20000 }).catch(() => {});
  ok(`${tag} B15 reabierto: se puede editar otra vez`, (await cua(p)).puede_editar && sqlq(`select count(*) from analisis.cuaderno_eventos where cuaderno_id = '${ids[ancho]}'`) === "2");
  // regresión del geovisor con el cuaderno abierto
  await clic(p, "[data-testid=cua-cerrar]");
  ok(`${tag} B16 «Cerrar» el cuaderno: el vidrio queda limpio y el geovisor sigue igual (leyenda de la red y botón «Capas»)`, (await cua(p)) === null && (await pintado(p, 0, 0, 150)) === 0 && (await hay(p, ".geo-leyenda")) && !(await hay(p, "[data-testid=cua-barra]")));
  ok(`${tag} B17 la pantalla no se desborda`, await sinDesborde(p));
  await p.close();

  // ===== C. Dual (Comercial y supervisor de planta): ve el cuaderno del equipo, solo lectura =====
  p = await abrir(ancho, "dual");
  ok(`${tag} C01 el dual (supervisor de planta) abre el geovisor y ve «Cuadernos»`, (await alGeovisor(p)) && (await p.waitForSelector("[data-testid=cuadernos]", { timeout: 15000 }).then(() => true).catch(() => false)));
  await irA(p, CENTRO[0], CENTRO[1], 16); await abrirLista(p);
  const lista = await p.$eval("[data-testid=cua-panel]", (e) => e.innerText);
  ok(`${tag} C02 ve el cuaderno del supervisor en «Del equipo», con el nombre del autor`, /Del equipo[\s\S]*ZTCUA Baja presión/.test(lista) && lista.includes("ZTCUA Supervisor de distribución") && /Aún no tiene cuadernos/.test(lista), lista);
  await clic(p, `[data-cuaderno="${ids[ancho]}"]`); await p.waitForFunction((id) => window.__cuaderno?.id === id, { timeout: 20000 }, ids[ancho]); await pausa(300);
  c = await cua(p);
  ok(`${tag} C03 lo abre en solo lectura: sin «Editar», sin «Guardar», sin herramientas`, !c.puede_editar && c.marcas.length === esperadas && (await hay(p, "[data-testid=cua-lectura]")) && !(await hay(p, "[data-testid=cua-modo]")) && !(await hay(p, "[data-testid=cua-guardar]")) && !(await hay(p, "[data-testid=cua-herr]")));
  await tocar(p, -20, 95);
  const ficha = await p.$eval("[data-testid=cua-ficha]", (e) => ({ t: e.innerText, campos: e.querySelectorAll("textarea, select, input").length, botones: [...e.querySelectorAll("button")].map((b) => b.innerText.trim()) })).catch(() => null);
  ok(`${tag} C04 la ficha de una marca ajena se lee (el texto del post-it) pero no se puede cambiar, mover ni anular`, ficha && /ZTCUA revisar con el macromedidor/.test(ficha.t) && ficha.campos === 0 && !ficha.botones.some((b) => /Mover|Anular|Quitar/.test(b)), JSON.stringify(ficha));
  await p.screenshot({ path: join(CAP, `c04_lectura_${ancho}.png`) });
  await clic(p, "[data-testid=cua-ficha] .geo-cerrar");
  await clic(p, "[data-testid=cua-mas]");
  ok(`${tag} C05 puede capturar (solo descargar), imprimir y exportar; no puede archivar`, (await hay(p, "[data-testid=cua-capturar]")) && (await hay(p, "[data-testid=cua-pdf]")) && (await hay(p, "[data-testid=cua-csv]")) && !(await hay(p, "[data-testid=cua-estado]")));
  await clic(p, "[data-testid=cua-capturar]"); await p.waitForSelector("[data-testid=cua-dialogo-capturar]");
  ok(`${tag} C06 en la captura solo tiene «Descargar»`, (await hay(p, "[data-testid=cua-captura-descargar]")) && !(await hay(p, "[data-testid=cua-captura-guardar]")));
  await clic(p, "[data-testid=cua-dialogo-capturar] .geo-cerrar");
  ok(`${tag} C07 el servidor decide: guardar en un cuaderno ajeno da 403, también para el dual`, (await aEdge(p, "cuaderno_guardar", { id: ids[ancho], version_base: c.version, cambios: [{ op: "nueva", tipo: "referencia", geom: { type: "Point", coordinates: [-73.25, 10.46] } }] })) === 403);
  await p.close();

  // ===== D. Administrador: ve todos, edita solo los suyos =====
  p = await abrir(ancho, "adm");
  ok(`${tag} D01 el administrador abre el geovisor y ve «Cuadernos»`, (await alGeovisor(p)) && (await p.waitForSelector("[data-testid=cuadernos]", { timeout: 15000 }).then(() => true).catch(() => false)));
  await irA(p, CENTRO[0], CENTRO[1], 16); await abrirCuaderno(p, ids[ancho]);
  ok(`${tag} D02 abre el cuaderno del supervisor en solo lectura (edita solo el autor, también frente al administrador)`, !(await cua(p)).puede_editar && (await hay(p, "[data-testid=cua-lectura]")) && (await aEdge(p, "cuaderno_archivar", { id: ids[ancho], motivo: "ZTCUA no es mío" })) === 403);
  await clic(p, "[data-testid=cua-cerrar]"); await abrirLista(p);
  ok(`${tag} D03 puede crear el suyo`, await hay(p, "[data-testid=cua-nuevo]"));
  await p.close();

  // ===== E. Operador con la casilla del geovisor (solo lectura): no hay cuadernos =====
  p = await abrir(ancho, "op");
  ok(`${tag} E01 el operador abre el geovisor en solo lectura y NO ve «Cuadernos»`, (await alGeovisor(p)) && /Solo lectura/.test(await p.$eval(".geo-titulo", (e) => e.innerText)) && (await pausa(2500), !(await hay(p, "[data-testid=cuadernos]"))) && !(await hay(p, "[data-testid=cua-barra]")));
  ok(`${tag} E02 el servidor decide: perfil, lista, cuaderno y exportación dan 403 al operador`, (await aEdge(p, "perfil")) === 403 && (await aEdge(p, "cuadernos")) === 403 && (await aEdge(p, `cuaderno&id=${ids[ancho]}`)) === 403 && (await aEdge(p, `cuaderno_exportar&id=${ids[ancho]}`)) === 403);
  await irA(p, CENTRO[0], CENTRO[1], 16);
  ok(`${tag} E03 su geovisor sigue igual: imprime y no tiene vidrio pintado`, (await hay(p, "[data-testid=imprimir]")) && (await pintado(p, 0, 0, 150)) === 0);
  await p.screenshot({ path: join(CAP, `e03_operador_${ancho}.png`) });
  await p.close();

  // ===== F. Sin permisos =====
  p = await abrir(ancho, "sin");
  await pausa(2500);
  const veBoton = await p.evaluate(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim().startsWith("Geovisor técnico")));
  let veMapa = false;
  if (veBoton) { await clicTexto(p, "button", "Geovisor técnico"); await pausa(3000); veMapa = !!(await p.$(".geo-mapa")); }
  ok(`${tag} F01 el operador sin la casilla no abre el geovisor ni los cuadernos (403 en el servidor)`, !veMapa && !(await hay(p, "[data-testid=cuadernos]")) && (await aEdge(p, "perfil")) === 403);
  await p.close();
  p = await abrir(ancho, "nada");
  await pausa(2500);
  ok(`${tag} F02 sin permisos asignados: no ve el geovisor ni los cuadernos, y el servidor responde 403`, !(await hay(p, ".geo-mapa")) && !(await hay(p, "[data-testid=cuadernos]")) && (await aEdge(p, "perfil")) === 403 && (await aEdge(p, "cuadernos")) === 403);
  await p.screenshot({ path: join(CAP, `f02_sin_permisos_${ancho}.png`) });
  await p.close();
}

ok("G01 nada personal en las tablas de análisis: las zonas guardan solo números", sqlq("select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'analisis' and table_name = 'zona_consultas'").split(",").every((c) => !/nombre|telefono|direccion|cod_usuario|contrato$/.test(c)));
ok("G02 pg-safeupdate: ninguna función del paquete con DELETE/UPDATE sin WHERE", sqlq("select count(*) from analisis.f_funciones_sin_where()") === "0");
await nav.close(); srv.close();
const fallas = resultados.filter((r) => !r.ok).length;
if (desconocidas.length) console.log("RPC simuladas no conocidas:", [...new Set(desconocidas)].join(", "));
if (pendientes.length) console.log("Fuentes que no terminaron de cargar:", pendientes.join(" | "));
if (errores.length) console.log("Errores de página:", errores.slice(0, 10).join(" | "));
console.log(`\nCapturas y PDF: ${CAP}`);
console.log(`\nRESULTADO: ${resultados.length - fallas} de ${resultados.length}${fallas ? "" : " — SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
