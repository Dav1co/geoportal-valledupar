// [Code A] PDF de «Reportar anomalía» (27-nov) · prueba de la EDGE REAL por llamada directa y de la PANTALLA de Supervisión en CHROME REAL, sin Supabase:
//   Revision → Detalle reales → Edge REAL geoportal-campo (Deno, de <supabase/functions>) → PostgREST, Auth y Storage mínimos en Node (los PDF y las fotos en memoria)
//   que llaman a las RPC REALES de la base local del Code A (55432): copia de producción con PostGIS real, redes y predios de volumen real y este paquete
//   migrado (base_chrome.py). Cada RPC como service_role con 30 s y 8 s. A 390 px (táctil) y 1280 px. El PDF se revisa por dentro y se rasteriza con pdftoppm.
// Perfiles (5): administrador, supervisora de Comercial, operario de campo, dual (operario de campo y de Técnica, sin supervisión) y sin permisos.
//   node scripts/prueba_chrome_reporte_pdf.mjs [--revision] <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]
//   --revision  no corre las pruebas: deja arriba la revisión local (http://127.0.0.1:55987/?rol=sup; otro puerto con ZTRP_PUERTO_REVISION) hasta Ctrl-C.
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos: pruebas 55983 (app, Auth, PostgREST, Storage) y 55984 (Edge); revisión 55985 y 55986. No chocan con una revisión anterior que siga arriba.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";
const USO = "Uso: node scripts/prueba_chrome_reporte_pdf.mjs [--revision] <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]";
const REVISION = process.argv.includes("--revision");
const args = process.argv.slice(2).filter((a) => a !== "--revision");
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, CAP_ARG] = args;
if (!FUNCIONES) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_reporte_pdf")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
// la revisión toma el primer par libre desde 55987 (las anteriores siguen arriba hasta que David avise); la base de revisión lleva el número del puerto
const PUERTO_REV = Number(process.env.ZTRP_PUERTO_REVISION || 55987);
const P_BASE = REVISION ? PUERTO_REV : 55983, P_EDGE = REVISION ? PUERTO_REV + 1 : 55984, DB = REVISION ? `emdupar_a_rf_ranrev${PUERTO_REV}` : "emdupar_a_rf_ranchrome";
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "ztrp.adm@emdupar.gov.co", sup: "ztrp.sup@emdupar.gov.co", op: "ztrp.op@emdupar.gov.co", dual: "ztrp.dual@emdupar.gov.co", sin: "ztrp.sin@emdupar.gov.co" };
const LAT = 10.476071, LON = -73.251529;

// ---------- 1. Base ----------
execFileSync("python3", ["-I", "-B", join(raiz, "sql/campo_reporte_pdf/pruebas_locales/base_chrome.py"), DB], { stdio: ["ignore", "pipe", "inherit"] });
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('${E.adm}', 'ZTRP Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('${E.sup}', 'ZTRP Supervisora', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('${E.op}', 'ZTRP Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('${E.dual}', 'ZTRP Dual', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('${E.sin}', 'ZTRP Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${E.dual}', 'asignar_formulario', 'anomalia_compartida', '${E.adm}');
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000301', 'ACTIVO', 'ZTRP PERSONA', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 0, '20261123');`);

// max_fotos vale 2 en el catálogo de producción; el encargo mide el tamaño con 6 fotos: solo en esta base local se sube a 6 (la bitácora de parámetros no se usa aquí)
sqlq("set session_replication_role = replica; update campo.parametros set valor = 6 where clave = 'max_fotos'");
// ---------- 2. Rpc a la base y Storage en memoria ----------
const rpcs = [];
function rpcBase(fn, a) {
  const argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", "); const t0 = Date.now();
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${argumentos})`],
      { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
    rpcs.push({ fn, ms: Date.now() - t0 }); let c; try { c = JSON.parse(t); } catch { c = t.trim(); } return { status: 200, cuerpo: c };
  } catch (e) {
    const t = String(e.stderr || ""); rpcs.push({ fn, ms: Date.now() - t0, error: t.slice(0, 300) });
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: (t.match(/HINT:\s+(\S+)/) || [])[1] } };
  }
}
const objetos = new Map();   // "bucket/ruta" → { bytes, tipo }
const subidas = [];
// Registra un reporte como lo hace la Edge: reserva, «sube» cada foto (bytes reales en memoria) y crea
function crearReporte(quien, tipo, fotos, { registro = null, contrato = null, lat = LAT, lon = LON, prec = 6, desc, resultado = null, causal = null, firma = null, subtipo = null, riesgo = false, inicio = null } = {}) {
  const p = rpcBase("geoportal_campo_preparar_subida", { p_solicitante: quien, p_cantidad: fotos.length, p_origen: "campo", p_ip: null, p_tipo: tipo });
  if (p.status !== 200) throw new Error("preparar: " + JSON.stringify(p.cuerpo));
  const id = p.cuerpo.reporte_id, lista = [];
  p.cuerpo.fotos.forEach((f, i) => {
    objetos.set(`campo-fotos/${f.ruta}`, { bytes: fotos[i].bytes, tipo: "image/jpeg" });
    sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', ${lit(f.ruta)}, ${lit({ size: fotos[i].bytes.length, mimetype: "image/jpeg" })})`);
    lista.push({ orden: i + 1, ruta: f.ruta, ...(fotos[i].origen ? { origen: fotos[i].origen } : {}), ...(fotos[i].etiqueta ? { etiqueta: fotos[i].etiqueta } : {}) });
  });
  if (firma) {   // los formatos con PDF exigen la firma del operario antes de registrar (como la pantalla)
    const fi = rpcBase("geoportal_campo_firma_guardar", { p_solicitante: quien, p_esquema: "campo", p_registro_id: id, p_rol: "operario", p_estado: "firmo", p_nombre: null,
      p_imagen: firma.toString("base64"), p_ip: null });
    if (fi.status !== 200) throw new Error("firma: " + JSON.stringify(fi.cuerpo));
  }
  const c = rpcBase("geoportal_campo_crear_reporte", { p_solicitante: quien, p_id: id, p_tipo: tipo, p_subtipo: subtipo, p_descripcion: desc ?? `[PRUEBA ZTRP] ${tipo}`, p_contrato: contrato,
    p_lat: lat, p_lon: lon, p_precision_m: prec, p_riesgo_inmediato: riesgo, p_origen: "campo", p_fotos: lista, p_ip: null, p_registro: registro, p_resultado: resultado, p_causal: causal, p_inicio_dispositivo: inicio });
  if (c.status !== 200) throw new Error("crear: " + JSON.stringify(c.cuerpo));
  return id;
}

// ---------- 3. La app (esbuild) con un doble de lib/supabase que da el token del rol ----------
const dir = mkdtempSync(join(tmpdir(), "ui_ranpdf_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "sup";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => ({ error: null }) }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import Revision from "./src/campo/dashboard/Revision.tsx";
    import { ActasRegistradas } from "./src/campo/documentos/ActasRegistradas.tsx";
    const q = new URLSearchParams(location.search), rol = q.get("rol");
    createRoot(document.getElementById("raiz")).render(q.get("p") === "actas"
      ? <div className="com-modulo"><ActasRegistradas correo={rol + "@prueba"} onVolver={() => {}} nombres={new Map()} puedeAperturas={false} puedeCerrarDerivadas={true} /></div>
      : <div className="com-modulo"><Revision correo={rol + "@prueba"} onVolver={() => {}} /></div>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 4. Auth, PostgREST y Storage mínimos ----------
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, x-upsert, apikey" };
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", ...cors }); res.end(JSON.stringify(o)); };
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/paquete/.test(u.pathname)) { const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1); res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f))); }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos), p = decodeURIComponent(u.pathname);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (p === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return E[rol] ? json(200, { id: "u-" + rol, email: E[rol] }) : json(401, {}); }
    if (p.startsWith("/rest/v1/rpc/")) {
      const fn = p.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (fn === "geoportal_estado_acceso" || fn.startsWith("geoportal_campo_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      return json(404, { code: "PGRST202", message: "no existe" });
    }
    if (p.startsWith("/storage/v1/object/sign/") && req.method === "POST") { const k = p.slice(24); return objetos.has(k) ? json(200, { signedURL: `/object/sign/${k}?token=lec-sim` }) : json(404, { statusCode: "404", error: "not_found" }); }
    if (p.startsWith("/storage/v1/object/sign/") && req.method === "GET") { const o = objetos.get(p.slice(24)); if (!o) return json(404, {}); res.writeHead(200, { "Content-Type": o.tipo, ...cors }); return res.end(o.bytes); }
    if (p.startsWith("/storage/v1/object/") && req.method === "GET") { const o = objetos.get(p.slice(19)); if (!o) return json(404, {}); res.writeHead(200, { "Content-Type": o.tipo }); return res.end(o.bytes); }
    if (p.startsWith("/storage/v1/object/") && req.method === "POST") {
      const k = p.slice(19);
      if (objetos.has(k) && req.headers["x-upsert"] !== "true") return json(400, { statusCode: "409", error: "Duplicate", message: "The resource already exists" });
      objetos.set(k, { bytes: cuerpo, tipo: req.headers["content-type"] || "application/octet-stream" }); subidas.push(k); return json(200, { Key: k });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 5. Edge REAL en Deno ----------
const servir = join(dir, "servir_edge.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edge lista"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edge lista/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 8000); });

// ---------- 6. Fotos reales (JPEG del navegador) y reportes de prueba ----------
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000, args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
async function jpeg(semilla, ancho, alto, calidad) {
  const pg = await nav.newPage();
  const b64 = await pg.evaluate((s, w, h, qd) => {
    const c = document.createElement("canvas"); c.width = w; c.height = h; const x = c.getContext("2d"); let r = s;
    const rnd = () => ((r = (r * 1103515245 + 12345) % 2147483648) / 2147483648);
    for (let i = 0; i < w; i += 3) for (let j = 0; j < h; j += 3) { x.fillStyle = `rgb(${Math.floor(90 + rnd() * 120)},${Math.floor(80 + rnd() * 110)},${Math.floor(60 + rnd() * 100)})`; x.fillRect(i, j, 3, 3); }
    x.fillStyle = "#fff"; x.font = "bold 80px sans-serif"; x.fillText("FOTO " + s, 60, 140);
    return c.toDataURL("image/jpeg", qd).split(",")[1];
  }, semilla, ancho, alto, calidad);
  await pg.close(); return Buffer.from(b64, "base64");
}
const fotoChica = await jpeg(1, 1600, 1200, 0.5);
const fotosGrandes = []; for (let i = 0; i < 6; i++) fotosGrandes.push(await jpeg(10 + i, 1600, 1200, 0.72));
const R1 = crearReporte(E.op, "otro", [{ bytes: fotoChica }], { contrato: "991800000301",
  registro: { lat_registro: LAT, lon_registro: LON, precision_registro_m: 6, direccion: "[PRUEBA ZTRP] CRA 9 # 12-32", barrio: "CENTRO", referencia: "Casa de rejas verdes" },
  desc: "[PRUEBA ZTRP] Sigue suspendido, tienen agua. Se ve una conexión directa antes del medidor." });
const R2 = crearReporte(E.sup, "otro", fotosGrandes.map((b) => ({ bytes: b, origen: "galeria" })), { registro: { xy_manual: true, lat_registro: 10.4762, lon_registro: -73.2512, precision_registro_m: 9 }, prec: null });
sqlq(`insert into campo.reporte_datos_sensibles (reporte_id, datos, registrado_en) values ('${R1}', '{"telefono_contacto": "3009876543", "nombre_contacto": "ZTRP CONTACTO SECRETO"}', now())`);
// R4: un reporte con TODOS los campos llenos (Comercial y pérdidas · Posible fraude · subtipo; contrato con dirección comercial y de catastro; dirección, barrio y referencia
// en terreno; riesgo inmediato; XY digitado; inicio del celular; fotos de cámara, galería y archivo). R5–R7: uno de cada grupo restante de «Reportar anomalía»
// (Alcantarillado, Red de acueducto fuera de la zona, Terceros); R1 es «Otros». Facturación solo tiene «Revisiones generales», que es un formato (su PDF es el de Actas).
sqlq(`insert into public.catastro_valledupar (cod_usuario, direccion, barrio, clase_uso) values ('991800000301', 'CARRERA 9 12 30 INTERIOR 2', 'CENTRO HISTORICO', 'RESIDENCIAL')`);
const SUB = sqlq("select s.codigo from campo.subtipos_reporte s join campo.tipos_reporte t on t.id = s.tipo_id where t.codigo = 'fraude' and s.activo order by s.orden limit 1");
const R4 = crearReporte(E.sup, "fraude", [{ bytes: fotoChica }, { bytes: fotosGrandes[0], origen: "galeria" }, { bytes: fotoChica, origen: "archivo" }], { subtipo: SUB, contrato: "991800000301", riesgo: true, prec: null,
  inicio: new Date(Date.now() - 7 * 60000 - 20000).toISOString(),
  registro: { xy_manual: true, lat_registro: 10.4762, lon_registro: -73.2512, precision_registro_m: 9, direccion: "[PRUEBA ZTRP] CLL 16 # 9-40 PISO 2", barrio: "LOPERENA", referencia: "Frente al parque, reja negra" },
  desc: "[PRUEBA ZTRP-COMPLETO] Conexión directa antes del medidor, con manguera negra enterrada." });
const R5 = crearReporte(E.op, "tapa_manhole", [{ bytes: fotoChica }], { desc: "[PRUEBA ZTRP-ALC] Tapa de manhole hundida en la vía." });
const R6 = crearReporte(E.op, "fuga_acometida", [{ bytes: fotoChica }], { lat: 10.58, lon: -73.25, desc: "[PRUEBA ZTRP-ACU] Fuga en acometida, fuera de la zona." });
const R7 = crearReporte(E.op, "dano_obra_terceros", [{ bytes: fotoChica }], { contrato: "991800000301", desc: "[PRUEBA ZTRP-TER] Retroexcavadora rompió la red." });
// R3: un formato (revisión previa), registrado de verdad (reserva, firma del operario, registro): aparece en «Actas registradas» con su PDF pendiente
const R3 = crearReporte(E.op, "revision_previa", [{ bytes: fotoChica, etiqueta: "fachada_predio" }], { contrato: "991800000301", resultado: "inefectivo", causal: "nadie_atiende", firma: await jpeg(99, 300, 120, 0.5) });
const CONS3 = sqlq(`select consecutivo from campo.reportes where id = '${R3}'`);

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 700)}`); };
const llamar = async (rol, accion, cuerpo, metodo = "POST") => {
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-campo?accion=${accion}`, { method: metodo, headers: { Authorization: `Bearer tok-${rol}`, "Content-Type": "application/json" },
    body: metodo === "GET" ? undefined : JSON.stringify(cuerpo) });
  let j = null; try { j = await r.json(); } catch { /* sin cuerpo */ } return { s: r.status, j };
};
const bajar = async (url) => Buffer.from(await (await fetch(url)).arrayBuffer());
const textoPdf = (b) => b.toString("latin1");
const pdftoppm = (archivo, base) => { execFileSync("/opt/homebrew/bin/pdftoppm", ["-png", "-r", "60", archivo, base]); };

if (REVISION) {
  console.log(`revisión local: http://127.0.0.1:${P_BASE}/?rol=sup (Supervisión → un reporte «Otro»: «Descargar PDF del reporte»; la revisión previa ${CONS3}: el PDF del formato)`);
  await new Promise(() => {});
}
const auditoria = (quien, accion, id) => Number(sqlq(`select count(*) from public.geoportal_auditoria where email = '${quien}' and accion = '${accion}' and referencia = '${id}'`));

try {
  console.log("— Edge por llamada directa —");
  for (const rol of ["op", "dual", "sin"]) { const r = await llamar(rol, "ran_pdf", { reporte_id: R1 }); ok(`E01 ${rol}: 403`, r.s === 403, `${r.s} ${JSON.stringify(r.j)}`); }
  ok("E02 ningún denegado dejó PDF ni auditoría", subidas.length === 0 && Number(sqlq("select count(*) from campo.reporte_pdf")) === 0);
  let r = await llamar("sup", "ran_pdf", { reporte_id: R3 }); ok("E03 un formato: 400 (tiene su propio PDF)", r.s === 400 && /formato/.test(JSON.stringify(r.j)), `${r.s} ${JSON.stringify(r.j)}`);
  r = await llamar("sup", "ran_pdf", { reporte_id: "00000000-0000-0000-0000-000000000000" }); ok("E04 un reporte que no existe: 404", r.s === 404, `${r.s}`);
  r = await llamar("sup", "ran_pdf", { reporte_id: R1, extra: 1 }); ok("E05 una clave que no conoce: 400", r.s === 400, `${r.s} ${JSON.stringify(r.j)}`);
  r = await llamar("sup", "ran_pdf", null, "GET"); ok("E06 GET: 405", r.s === 405, `${r.s}`);
  let t0 = Date.now(); r = await llamar("sup", "ran_pdf", { reporte_id: R1 }); const ms1 = Date.now() - t0;
  ok(`E07 supervisora: genera la versión 1 (${ms1} ms)`, r.s === 200 && r.j.version === 1 && r.j.nuevo === true && /^\d{14}-RAN-\d{6}\.pdf$/.test(r.j.nombre), JSON.stringify(r.j));
  const n1 = r.j.nombre, sha1 = r.j.sha256;
  const pdf1 = await bajar(r.j.url); writeFileSync(join(CAP, "R1_v1.pdf"), pdf1);
  const t1 = textoPdf(pdf1);
  ok("E08 el PDF es un PDF, del tamaño y sha256 registrados", t1.startsWith("%PDF-1.4") && pdf1.length === r.j.bytes && execFileSync("shasum", ["-a", "256", join(CAP, "R1_v1.pdf")]).toString().startsWith(sha1));
  ok("E09 título, número, versión, tipo, estado, contrato, direcciones y referencia", t1.includes("(Reporte de anomal\\355a)") && t1.includes(`N.\\272 RAN-`) && t1.includes("versi\\363n 1")
    && t1.includes("(Reportado)") && t1.includes("(991800000301 \\(no verificado\\))") && t1.includes("[PRUEBA ZTRP] CRA 9 # 12-32") && t1.includes("(Casa de rejas verdes)") && t1.includes("Direcci\\363n base comercial"));
  ok("E09b número RAN seguido (RAN-000001 es el primero) y el número interno aparte, en letra pequeña", /N\.\\272 RAN-000001 /.test(t1)
    && t1.includes(`(N\\372mero interno del reporte en el Geoportal: ${sqlq(`select seq from campo.reportes where id = '${R1}'`)})`) && t1.includes("/F1 7.5 Tf"));
  ok("E10 el nombre del operario (no su correo); quien generó, por nombre", t1.includes("ZTRP Operario") && !t1.includes("ztrp.op@") && t1.includes("por ZTRP Supervisora"));
  ok("E11 nunca los datos sensibles ni las rutas de almacenamiento", !t1.includes("3009876543") && !t1.includes("SECRETO") && !/reportes\/\d{4}-\d{2}\//.test(t1) && !t1.includes("campo-fotos"));
  ok("E12 sin firmas ni la leyenda del acta física", !t1.includes("(FIRMAS)") && !t1.includes("valor probatorio") && !t1.includes("Firma electr"));
  ok("E13 mapa vectorial con acueducto, alcantarillado, predios, punto, escala y leyenda", t1.includes("0 0.36 0.78 RG 1.2 w") && t1.includes("0.55 0.33 0.12 RG 0.9 w [3 2] 0 d") && t1.includes(" re W n")
    && (t1.match(/ 1\.8 1\.8 re f/g) ?? []).length > 50 && t1.includes("(50 m)") && t1.includes("(Acueducto)") && t1.includes("(Punto del reporte)"));
  ok("E14 historial, foto con su origen, descripción y sello", t1.includes("(HISTORIAL)") && t1.includes("tomada con la c\\341mara") && t1.includes("conexi\\363n directa") && t1.includes("(INTEGRIDAD)"));
  pdftoppm(join(CAP, "R1_v1.pdf"), join(CAP, "R1_v1"));
  ok("E15 el PDF se rasteriza (pdftoppm) en sus páginas", existsSync(join(CAP, "R1_v1-1.png")));
  ok("E16 auditado: una generación", auditoria(E.sup, "campo_ran_pdf_generar", R1) === 1);
  r = await llamar("adm", "ran_pdf", { reporte_id: R1 });
  ok("E17 el administrador pide el mismo: la misma versión, sin generar otra, auditada como descarga", r.s === 200 && r.j.nombre === n1 && r.j.sha256 === sha1 && r.j.nuevo === false
    && subidas.length === 1 && auditoria(E.adm, "campo_ran_pdf_descargar", R1) === 1, JSON.stringify(r.j));
  r = await llamar("sup", "estado", { id: R1, estado: "en_revision", motivo: "[PRUEBA ZTRP] se revisa en terreno" });
  ok("E18 la supervisora cambia el estado", r.s === 200, JSON.stringify(r.j));
  r = await llamar("sup", "ran_pdf", { reporte_id: R1 });
  ok("E19 el reporte cambió: versión 2 con -v2, nuevo archivo; la 1 sigue", r.s === 200 && r.j.version === 2 && /-v2\.pdf$/.test(r.j.nombre) && r.j.nuevo && subidas.length === 2
    && Number(sqlq(`select count(*) from campo.reporte_pdf where reporte_id = '${R1}'`)) === 2, JSON.stringify(r.j));
  const t2 = textoPdf(await bajar(r.j.url));
  ok("E20 la versión 2 trae el estado y el historial nuevos", t2.includes("(En revisi\\363n)") && t2.includes("Cambio de estado a En revisi\\363n") && t2.includes("se revisa en") && t2.includes("versi\\363n 2"));
  t0 = Date.now(); r = await llamar("sup", "ran_pdf", { reporte_id: R2 }); const ms2 = Date.now() - t0;
  const pdf2 = r.s === 200 ? await bajar(r.j.url) : Buffer.alloc(0); writeFileSync(join(CAP, "R2.pdf"), pdf2);
  const t3 = textoPdf(pdf2);
  const pesoFotos = fotosGrandes.reduce((s, b) => s + b.length, 0);
  ok(`E21 6 fotos de la galería (${Math.round(pesoFotos / 1024)} KB): PDF de ${Math.round(pdf2.length / 1024)} KB < 2 MB en ${ms2} ms`, r.s === 200 && pdf2.length < 2 * 1024 * 1024, `${r.s} ${JSON.stringify(r.j)}`);
  const omit = (t3.match(/Foto omitida por tama\\361o; disponible en el/g) ?? []).length;
  ok(`E22 las que no caben llevan la nota (${omit}) y quedan contadas en la fila`, omit >= 1 && Number(sqlq(`select fotos_omitidas from campo.reporte_pdf where reporte_id = '${R2}'`)) === omit);
  ok("E23 galería y XY digitado: «adjuntada desde la galería», «XY digitado» y el punto de registro en el mapa", t3.includes("adjuntada desde la galer\\355a") && t3.includes("XY digitado \\227 registrado desde otro punto") && t3.includes("(Registrado desde \\(XY digitado\\))"));
  pdftoppm(join(CAP, "R2.pdf"), join(CAP, "R2"));
  const maxRpc = Math.max(...rpcs.filter((x) => x.fn.startsWith("geoportal_campo_ran_")).map((x) => x.ms));
  ok(`E24 cada RPC del PDF (con psql) tarda menos de 2 s (máx ${maxRpc} ms)`, maxRpc < 2000);

  // historial completo para R4: cambio de estado, ocultar y reincluir (por la Edge, como la pantalla)
  for (const [acc, cuerpo] of [["estado", { id: R4, estado: "en_revision", motivo: "[PRUEBA ZTRP] se revisa en terreno" }], ["ocultar", { id: R4, motivo: "[PRUEBA ZTRP] se oculta un momento" }],
                               ["reincluir", { id: R4, motivo: "[PRUEBA ZTRP] vuelve a la lista" }]]) {
    const x = await llamar("sup", acc, cuerpo); ok(`E25 historial de R4: ${acc}`, x.s === 200, `${x.s} ${JSON.stringify(x.j)}`);
  }
  // ---------- Chrome ----------
  const esp = (ms) => new Promise((res) => setTimeout(res, ms));
  async function abrir(rol, ancho, pagina = "") {
    const pg = await nav.newPage();
    await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
    pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
    await pg.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${pagina}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(1500);
    return pg;
  }
  const esperar = (pg, f, ...a) => pg.waitForFunction(f, { timeout: 30000 }, ...a).then(() => true).catch(() => false);
  const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
  const foto = (pg, n) => pg.screenshot({ path: join(CAP, n + ".png"), fullPage: true });
  const abrirFila = (pg, texto) => pg.evaluate((t) => { const f = [...document.querySelectorAll('[role="row"]')].find((e) => e.innerText.includes(t)); if (f) { f.click(); return true; } return false; }, texto);
  // Regresión de «Actas registradas» (su marca y su botón ahora son componentes compartidos): antes de generar, el formato está «PDF pendiente» con «Generar el PDF»
  {
    const pg = await abrir("sup", 1280, "&p=actas");
    const vio = await esperar(pg, (id) => !!document.querySelector(`[data-registro="${id}"]`), R3);
    const fila = vio ? await pg.$eval(`[data-registro="${R3}"]`, (e) => e.innerText) : "";
    ok("A01 Actas registradas (antes): el formato aparece «PDF pendiente» con «Generar el PDF»", /PDF pendiente/.test(fila) && /Generar el PDF/.test(fila), fila.slice(0, 300));
    await pg.close();
  }
  for (const ancho of [390, 1280]) {
    console.log(`— Chrome a ${ancho} px —`);
    for (const rol of ["sup", "adm"]) {
      const pg = await abrir(rol, ancho);
      await esperar(pg, () => [...document.querySelectorAll('[role="row"]')].length > 1);
      const abrio = await abrirFila(pg, "Otro") && await esperar(pg, () => !!document.querySelector(".rv-detalle .rv-acciones"));
      const tieneBoton = abrio && await esperar(pg, () => !!document.querySelector("[data-ran-pdf] button"));
      ok(`C${ancho}.01 ${rol}: en el detalle de un reporte de «Reportar anomalía», el botón «Descargar PDF del reporte» junto a las acciones`, tieneBoton
        && /Descargar PDF del reporte/.test(await pg.$eval("[data-ran-pdf] button", (e) => e.innerText)), (await pg.$eval("body", (e) => e.innerText)).slice(0, 400));
      await pg.click("[data-ran-pdf] button");
      const listo = await esperar(pg, () => !!document.querySelector("[data-ran-pdf-listo]"));
      const txt = listo ? await pg.$eval("[data-ran-pdf-listo]", (e) => e.innerText) : await pg.$eval("[data-ran-pdf]", (e) => e.innerText);
      ok(`C${ancho}.02 ${rol}: «PDF listo» con nombre, tamaño y versión, y el enlace «Abrir el PDF»`, listo && /RAN-\d{6}/.test(txt) && /(KB|MB)/.test(txt) && !!(await pg.$("[data-ran-pdf-abrir]")), txt);
      const href = listo ? await pg.$eval("[data-ran-pdf-abrir]", (e) => e.getAttribute("href")) : "";
      ok(`C${ancho}.03 ${rol}: el enlace abre un PDF`, !!href && textoPdf(await bajar(href)).startsWith("%PDF-1.4"));
      ok(`C${ancho}.04 ${rol}: sin desborde horizontal`, await sinDesborde(pg));
      await pg.evaluate(() => document.querySelector("[data-ran-pdf]")?.scrollIntoView({ block: "center" })); await foto(pg, `${ancho}_${rol}_detalle_pdf`);
      // un formato: no sale el PDF del reporte; sale el MISMO de «Actas registradas» (estado y botón)
      const abrioF = await abrirFila(pg, CONS3) && await esperar(pg, (c) => (document.querySelector(".rv-detalle h2")?.textContent ?? "").includes(c), CONS3);
      const estadoF = abrioF && await esperar(pg, () => !!document.querySelector('[data-pdf-formato="fila"] [data-pdf-estado]'));
      const marca = estadoF ? await pg.$eval('[data-pdf-formato="fila"] [data-pdf-estado]', (e) => e.innerText) : "";
      ok(`C${ancho}.05 ${rol}: en un formato no sale «Descargar PDF del reporte»; sale el estado de Actas registradas (${marca})`, estadoF && !(await pg.$("[data-ran-pdf]"))
        && (marca === "PDF listo" || marca === "PDF pendiente"), (await pg.$eval("body", (e) => e.innerText)).slice(0, 500));
      if (marca === "PDF pendiente") {
        ok(`C${ancho}.06 ${rol}: «PDF pendiente» con «Generar el PDF», como allá`, !!(await pg.$('[data-pdf-formato="fila"] button')) && /Generar el PDF/.test(await pg.$eval('[data-pdf-formato="fila"] button', (e) => e.innerText)));
        await pg.click('[data-pdf-formato="fila"] button');
      }
      const listoF = await esperar(pg, () => /Descargar el PDF/.test(document.querySelector('[data-pdf-formato="fila"]')?.innerText ?? ""));
      ok(`C${ancho}.07 ${rol}: el PDF del formato queda con «Descargar el PDF» (el mismo componente de Actas registradas)`, listoF, await pg.$eval('[data-pdf-formato="fila"]', (e) => e.innerText).catch(() => ""));
      ok(`C${ancho}.08 ${rol}: sin desborde (formato)`, await sinDesborde(pg));
      await pg.evaluate(() => document.querySelector('[data-pdf-formato]')?.scrollIntoView({ block: "center" })); await foto(pg, `${ancho}_${rol}_formato_pdf`);
      await pg.close();
    }
    for (const rol of ["op", "dual", "sin"]) {
      const pg = await abrir(rol, ancho); await esp(1500);
      ok(`C${ancho}.09 ${rol}: no llega al detalle de Supervisión ni a los botones`, !(await pg.$("[data-ran-pdf]")) && !(await pg.$(".rv-detalle")));
      await pg.close();
    }
  }
  {
    const pg = await abrir("sup", 390, "&p=actas");
    await esperar(pg, (id) => !!document.querySelector(`[data-registro="${id}"]`), R3);
    const fila = await pg.$eval(`[data-registro="${R3}"]`, (e) => e.innerText).catch(() => "");
    ok("A02 Actas registradas (después, a 390 px): el mismo formato «PDF listo» con «Descargar el PDF»", /PDF listo/.test(fila) && /Descargar el PDF/.test(fila), fila.slice(0, 300));
    ok("A03 sin desborde (Actas registradas)", await sinDesborde(pg));
    await pg.close();
  }
  // ---------- Detalle de Supervisión contra el PDF, campo por campo (1.280 px, supervisora) ----------
  const textoDelPdf = (b) => {
    const s = b.toString("latin1"), out = [], re = /\(((?:\\.|[^\\)])*)\) Tj/g; let m;
    const W = { 0x96: "–", 0x97: "—", 0x95: "•", 0x93: "“", 0x94: "”", 0x91: "‘", 0x92: "’", 0x85: "…", 0x80: "€" };
    while ((m = re.exec(s))) out.push(m[1].replace(/\\([0-7]{3})/g, (_, o) => { const c = parseInt(o, 8); return W[c] ?? String.fromCharCode(c); }).replace(/\\([()\\])/g, "$1"));
    return out.join(" ").replace(/\s+/g, " ");
  };
  const casos = [["R1 Otros (contrato, terreno)", "conexión directa"], ["R2 Otros (galería, XY digitado)", "[PRUEBA ZTRP] otro"], ["R4 Comercial y pérdidas, COMPLETO", "ZTRP-COMPLETO"],
                 ["R5 Alcantarillado", "ZTRP-ALC"], ["R6 Red de acueducto, fuera de zona", "ZTRP-ACU"], ["R7 Terceros", "ZTRP-TER"]];
  const informe = [];
  for (const [nombre, marca] of casos) {
    const pg = await abrir("sup", 1280);
    await esperar(pg, () => [...document.querySelectorAll('[role="row"]')].length > 1);
    const abrio = await abrirFila(pg, marca) && await esperar(pg, (mk) => (document.querySelector(".rv-detalle .rv-descripcion")?.textContent ?? "").includes(mk) || mk === "[PRUEBA ZTRP] otro", marca)
      && await esperar(pg, () => !!document.querySelector("[data-ran-pdf] button"));
    const pares = abrio ? await pg.evaluate(() => { const dl = [...document.querySelectorAll(".rv-detalle .rv-dl")][0]; const r = []; let k = null;
      for (const e of dl.children) { if (e.tagName === "DT") k = e.innerText.trim(); else if (e.tagName === "DD" && k) r.push([k, e.innerText.trim()]); } return r; }) : [];
    await pg.click("[data-ran-pdf] button");
    await esperar(pg, () => !!document.querySelector("[data-ran-pdf-abrir]"));
    const href = await pg.$eval("[data-ran-pdf-abrir]", (e) => e.getAttribute("href")).catch(() => "");
    const pdf = href ? await bajar(href) : Buffer.alloc(0); writeFileSync(join(CAP, `comparar_${nombre.split(" ")[0]}.pdf`), pdf);
    const txt = textoDelPdf(pdf), faltan = [], filas = [];
    const esta = (x) => txt.includes(x.replace(/\s+/g, " ").trim());
    for (const [k, val] of pares) {
      let piezas;
      if (k === "Autor") { piezas = []; filas.push(`${k}: correo en pantalla → nombre en el PDF (regla de David)`); }
      else if (k === "Grupo y tipo") piezas = val.split(" · ");
      else if (k === "Estado") piezas = [val.replace(/ \(desde .*\)$/, "")];
      else if (k === "Dirección del contrato") piezas = val.split("\n").map((l) => l.replace(/^En el catastro: /, "")).filter(Boolean);
      else piezas = [val];
      for (const pz of piezas) if (pz !== "—" && !esta(pz)) faltan.push(`${k}: «${pz}»`);
    }
    // los campos fijos salen siempre, aunque la pantalla no los muestre si están vacíos
    for (const fijo of ["Grupo", "Tipo", "Subtipo", "Contrato", "Resultado", "Riesgo inmediato", "Zona", "Origen", "Dirección base comercial", "Dirección catastro",
                        "Dirección encontrada en terreno", "Barrio", "Referencia", "Inicio", "Fin (registrado)", "Duración", "Coordenadas", "Registrado desde", "¿QUÉ ENCONTRÓ?", "RESPUESTAS DEL FORMULARIO"])
      if (!esta(fijo)) faltan.push(`fijo ausente: ${fijo}`);
    informe.push(`${nombre}: ${pares.length} campos del detalle; ${faltan.length ? "FALTAN " + faltan.join("; ") : "todos en el PDF"}`);
    ok(`K ${nombre}: los ${pares.length} campos del detalle de Supervisión están en el PDF, y los fijos también`, abrio && pares.length >= 6 && faltan.length === 0, faltan.join(" | "));
    if (marca === "ZTRP-COMPLETO") ok("K R4: la versión del PDF trae el historial completo (estado, ocultar, reincluir) y los datos sensibles no", esta("Cambio de estado a En revisión") && esta("Se ocultó el reporte")
      && esta("Se reincluyó el reporte") && esta("Riesgo inmediato Sí") && esta("Zona Dentro de la zona de servicio") && esta(SUB === "" ? "Subtipo" : "Subtipo"), txt.slice(0, 600));
    if (marca === "ZTRP-ACU") ok("K R6: «Fuera de la zona de servicio»", esta("Zona Fuera de la zona de servicio"));
    await pg.close();
  }
  writeFileSync(join(CAP, "comparacion_detalle_pdf.txt"), informe.join("\n") + "\n");
  console.log(informe.map((l) => "   · " + l).join("\n"));
  const fnsF = new Set(rpcs.map((x) => x.fn));
  ok("F01 el PDF del formato usó las mismas RPC de Actas registradas (actas_registradas, pdf_datos, pdf_registrar) y no las del reporte",
    ["geoportal_campo_actas_registradas", "geoportal_campo_pdf_datos", "geoportal_campo_pdf_registrar"].every((f) => fnsF.has(f)) && Number(sqlq(`select count(*) from campo.documentos_pdf where registro_id = '${R3}'`)) === 1
    && Number(sqlq(`select count(*) from campo.reporte_pdf where reporte_id = '${R3}'`)) === 0, [...fnsF].join(", "));
  ok("F02 auditado como los PDF de los formatos (campo_pdf_generar)", Number(sqlq(`select count(*) from public.geoportal_auditoria where accion = 'campo_pdf_generar' and referencia = '${R3}'`)) === 1);
} finally {
  await nav.close(); srv.close(); edge.kill();
}
console.log(`\nRESULTADO: ${total - fallas} de ${total}${fallas ? " — CON FALLAS" : " — SIN FALLAS"} · capturas y PDF en ${CAP}`);
process.exit(fallas ? 1 : 0);
