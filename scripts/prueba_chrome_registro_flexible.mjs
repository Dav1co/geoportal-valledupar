// [Code A] Registro flexible (25-nov) · prueba de la EDGE REAL por llamada directa y de las PANTALLAS en CHROME REAL, sin Supabase:
//   pantallas reales (ReporteGeneral, FormularioFormato, FormatosCampo, Revision → Reportes y Detalle, Avisos y actividades derivadas) → Edges REALES geoportal-campo y
//   geoportal-acta (Deno, de ~/geoportal-web-regflex) → PostgREST, Auth y Storage mínimos en Node que llaman a las RPC REALES de la base local del Code A (55432):
//   copia de producción (rehacer_doble.py + Investigación y Análisis publicada) con el paquete migrado (base_chrome.py). Cada RPC corre como service_role con
//   statement_timeout 30 s y lock_timeout 8 s. Cámara y GPS falsos de Chrome.
// Los 5 perfiles (David, 24-nov): administrador, supervisor de Comercial, operador de campo, dual (supervisor de Comercial y operador de Técnica) y sin permisos;
// además el operador de planta (Técnica, «entrada» y «Reportar anomalía»). A 390 px (táctil) y 1280 px.
//   node scripts/prueba_chrome_registro_flexible.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55971 (app, Auth, PostgREST y Storage) y 55972 (Edges). No prueba: Supabase, un celular físico ni la galería real del sistema (el archivo se entrega al <input>).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";
const USO = "Uso: node scripts/prueba_chrome_registro_flexible.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, CAP_ARG] = args;
if (!FUNCIONES) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_registro_flexible")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55971, P_EDGE = 55972, DB = "emdupar_a_rf_chrome";
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "ztrfc.adm@emdupar.gov.co", sup: "ztrfc.sup@emdupar.gov.co", op: "ztrfc.op@emdupar.gov.co", dual: "ztrfc.dual@emdupar.gov.co", sin: "ztrfc.sin@emdupar.gov.co", planta: "ztrfc.planta@emdupar.gov.co" };

// ---------- 1. Base: copia de producción + el paquete migrado + datos propios (ZTRFC) ----------
execFileSync("python3", ["-I", "-B", join(raiz, "sql/campo_registro_flexible/pruebas_locales/base_chrome.py"), DB], { stdio: ["ignore", "pipe", "inherit"] });
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico) values
  ('${E.adm}', 'ZTRFC Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('${E.sup}', 'ZTRFC Supervisora de Comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false),
  ('${E.op}', 'ZTRFC Operario de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false),
  ('${E.dual}', 'ZTRFC Dual', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true),
  ('${E.sin}', 'ZTRFC Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('${E.planta}', 'ZTRFC Operador de planta', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${E.dual}', 'asignar_formulario', 'anomalia_compartida', '${E.adm}'),
  ('${E.planta}', 'asignar_formulario', 'entrada', '${E.adm}'), ('${E.planta}', 'asignar_formulario', 'anomalia_compartida', '${E.adm}');`);
const GRUPO_OTRO = sqlq("select g.codigo from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = 'otro'");

// ---------- 2. La app (esbuild) con un doble de lib/supabase que da el token del rol y sube al Storage simulado ----------
const dir = mkdtempSync(join(tmpdir(), "ui_regflex_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: (bucket) => ({ uploadToSignedUrl: async (ruta, token, blob) => {
        const r = await fetch("http://127.0.0.1:${P_BASE}/subida-simulada?bucket=" + bucket + "&ruta=" + encodeURIComponent(ruta) + "&bytes=" + blob.size + "&mime=" + encodeURIComponent(blob.type), { method: "PUT", body: blob });
        return r.ok ? { error: null } : { error: { status: r.status } }; } }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React, { useEffect, useState } from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import { ReporteGeneral } from "./src/campo/ReporteGeneral.tsx";
    import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx";
    import { FormatosCampo } from "./src/campo/formatos/FormatosCampo.tsx";
    import Revision from "./src/campo/dashboard/Revision.tsx";
    import { apiCampo } from "./src/campo/apiCampo.ts";
    import { fijarAreaCampo } from "./src/campo/area.ts";
    const q = new URLSearchParams(location.search), p = q.get("p"), rol = q.get("rol"), correo = rol + "@prueba";
    if (q.get("area") === "tecnica") fijarAreaCampo("tecnica");
    function ConDef({ hijo }) {
      const [d, setD] = useState(null); const [err, setErr] = useState(null);
      useEffect(() => { apiCampo.formulario().then(setD).catch((e) => setErr(e.message || "error")); }, []);
      if (err) return <p className="campo-error" data-error-formulario>{err}</p>;
      return d ? hijo(d) : <p>Cargando…</p>;
    }
    const raizApp = createRoot(document.getElementById("raiz"));
    const tipoDe = (d, c) => d.grupos.flatMap((g) => g.tipos).find((t) => t.codigo === c);
    if (p === "reporte") raizApp.render(<div className="campo-contenedor com-modulo"><ConDef hijo={(d) => <ReporteGeneral def={d} correo={correo} onVolver={() => { window.__volvio = true; }} onOtro={() => {}} />} /></div>);
    if (p === "formato") raizApp.render(<div className="campo-contenedor com-modulo"><ConDef hijo={(d) => tipoDe(d, q.get("tipo")) ? <FormularioFormato def={d} tipo={tipoDe(d, q.get("tipo"))} correo={correo} onVolver={() => {}} onOtro={() => {}} /> : <p data-sin-tipo>sin el formato</p>} /></div>);
    if (p === "formatos") raizApp.render(<div className="campo-contenedor com-modulo"><ConDef hijo={(d) => <FormatosCampo def={d} correo={correo} onVolver={() => {}} />} /></div>);
    if (p === "revision") raizApp.render(<div className="com-modulo"><Revision correo={correo} onVolver={() => {}} abrirDerivadas={q.get("der") === "1"} /></div>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 3. Auth, PostgREST y Storage mínimos; las RPC van a la base local REAL ----------
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
const firmas = new Map();   // ruta → «jpeg» si los bytes subidos empiezan con FF D8 FF
const JPEG_1PX = Buffer.from("/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==", "base64");
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
    if (p === "/subida-simulada") {   // el navegador «sube» la foto: queda como objeto de Storage con su tamaño y tipo (lo que lee crear_reporte), y se mira su firma
      firmas.set(u.searchParams.get("ruta"), cuerpo.length >= 3 && cuerpo[0] === 0xff && cuerpo[1] === 0xd8 && cuerpo[2] === 0xff ? "jpeg" : "otra");
      sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(u.searchParams.get("bucket"))}, ${lit(u.searchParams.get("ruta"))}, ${lit({ size: Number(u.searchParams.get("bytes")), mimetype: u.searchParams.get("mime") })})`);
      return json(200, { Key: u.searchParams.get("ruta") });
    }
    if (p.startsWith("/storage/v1/object/upload/sign/")) return json(200, { url: `/object/upload/sign/${p.slice(31)}?token=tk-sim`, token: "tk-sim" });
    if (p.startsWith("/storage/v1/object/sign/")) return json(200, { signedURL: `/object/sign/${p.slice(24)}?token=lec-sim` });
    if (p.startsWith("/storage/v1/object/sign") || p.startsWith("/object/sign/")) { res.writeHead(200, { "Content-Type": "image/jpeg", ...cors }); return res.end(JPEG_1PX); }
    if (p === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return E[rol] ? json(200, { id: "u-" + rol, email: E[rol] }) : json(401, {}); }
    if (p.startsWith("/rest/v1/rpc/")) {
      const fn = p.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (fn === "geoportal_estado_acceso" || fn.startsWith("geoportal_campo_") || fn.startsWith("geoportal_acta_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      return json(404, { code: "PGRST202", message: "no existe" });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 4. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-acta/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-acta") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 8000); });

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 700)}`); };

// ---------- 5. EDGE por llamada directa (lo que haría alguien que se salta la pantalla) ----------
const llamar = async (rol, accion, cuerpo, qs = "") => {
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-campo?accion=${accion}${qs}`, { method: cuerpo === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer tok-${rol}`, "Content-Type": "application/json" }, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  let j = null; try { j = await r.json(); } catch { /* sin cuerpo */ } return { s: r.status, j };
};
async function crearDirecto(rol, { fotos = [{}], registro, lat = 10.46, lon = -73.25, precision_m = 5, area = "" } = {}) {
  const qs = area ? `&area=${area}` : "";
  const p = await llamar(rol, "preparar_subida", { cantidad: fotos.length, tipo: "otro" }, qs);
  if (p.s !== 200) return p;
  for (const f of p.j.fotos) sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', ${lit(f.ruta)}, '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const cuerpo = { reporte_id: p.j.reporte_id, tipo: "otro", descripcion: "[PRUEBA ZTRFC] directa", lat, lon, precision_m, riesgo_inmediato: false, origen: "campo",
    fotos: p.j.fotos.map((f, i) => ({ orden: f.orden, ruta: f.ruta, ...fotos[i] })), ...(registro !== undefined ? { registro } : {}) };
  const r = await llamar(rol, "crear", cuerpo, qs); return { ...r, id: p.j.reporte_id };
}
const G = { lat_registro: 10.4601, lon_registro: -73.2502, precision_registro_m: 7 };
const filaReg = (id) => sqlq(`select coalesce((select xy_manual::text || '|' || coalesce(lat_registro::text, '-') || '|' || coalesce(direccion, '-') from campo.reporte_registro where reporte_id = '${id}'), 'sin fila')`);
const origenes = (id) => sqlq(`select string_agg(origen, ',' order by orden) from campo.reporte_fotos where reporte_id = '${id}'`);
const cuantos = (quien) => Number(sqlq(`select count(*) from campo.reportes where autor = '${quien}'`));
console.log("— Edge por llamada directa —");
{
  const n0 = cuantos(E.op);
  let r = await crearDirecto("op", { fotos: [{ origen: "galeria" }], registro: G });
  ok("E01 operador: foto de la GALERÍA por llamada directa → 403 del servidor", r.s === 403, JSON.stringify(r.j));
  r = await crearDirecto("op", { fotos: [{ origen: "archivo" }], registro: G });
  ok("E02 operador: foto de un ARCHIVO → 403", r.s === 403, JSON.stringify(r.j));
  r = await crearDirecto("op", { registro: { ...G, xy_manual: true }, precision_m: null });
  ok("E03 operador: XY DIGITADO → 403", r.s === 403, JSON.stringify(r.j));
  ok("E04 los rechazos no dejaron reportes", cuantos(E.op) === n0);
  r = await crearDirecto("op", { fotos: [{ origen: "camara" }], registro: G });
  ok("E05 operador con cámara y GPS → 200, con la ubicación del dispositivo guardada", r.s === 200 && filaReg(r.id) === "false|10.460100|-", `${r.s} ${filaReg(r.id)}`);
  r = await crearDirecto("op", { registro: { ...G, inventada: 1 } });
  ok("E06 una clave desconocida en «registro» → 400 que la nombra", r.s === 400 && /inventada/.test(r.j?.error ?? JSON.stringify(r.j)), JSON.stringify(r.j));
  r = await crearDirecto("op", { fotos: [{ origen: "selfie" }], registro: G });
  ok("E07 un origen de foto inventado → 400", r.s === 400, JSON.stringify(r.j));
  r = await crearDirecto("op", { registro: { ...G, direccion: "x".repeat(121) } });
  ok("E08 dirección de 121 caracteres → 400 (tope 120)", r.s === 400, JSON.stringify(r.j));
  r = await crearDirecto("sup", { fotos: [{ origen: "galeria" }, { origen: "archivo" }], registro: { ...G, xy_manual: true, direccion: "[PRUEBA ZTRFC] CRA 7 # 8-9" }, lat: 10.4712, lon: -73.2611, precision_m: null });
  ok("E09 supervisor: galería, archivo, XY digitado y dirección → 200 y queda marcado", r.s === 200 && filaReg(r.id) === "true|10.460100|[PRUEBA ZTRFC] CRA 7 # 8-9" && origenes(r.id) === "galeria,archivo", `${r.s} ${JSON.stringify(r.j)} ${filaReg(r.id)}`);
  r = await crearDirecto("sup", { registro: { xy_manual: true }, lat: 4.7, lon: -74.07, precision_m: null });
  ok("E10 supervisor: XY digitado fuera de Valledupar → 400 con el rango", r.s === 400 && /Valledupar/.test(JSON.stringify(r.j)), JSON.stringify(r.j));
  r = await crearDirecto("adm", { fotos: [{ origen: "archivo" }], registro: { xy_manual: true }, precision_m: null });
  ok("E11 administrador: archivo y XY digitado sin ubicación del dispositivo → 200 («sin ubicación»)", r.s === 200 && filaReg(r.id) === "true|-|-", `${r.s} ${filaReg(r.id)}`);
  r = await crearDirecto("dual", { fotos: [{ origen: "galeria" }], registro: { ...G, xy_manual: true }, precision_m: null, area: "tecnica" });
  ok("E12 dual desde TÉCNICA con galería y XY → 403 (la Edge, sin llegar a la base)", r.s === 403 && /Técnica/.test(JSON.stringify(r.j)), JSON.stringify(r.j));
  r = await crearDirecto("dual", { fotos: [{ origen: "galeria" }], registro: { ...G, xy_manual: true }, precision_m: null });
  ok("E13 dual desde COMERCIAL (es supervisor de Comercial) → 200", r.s === 200, JSON.stringify(r.j));
  r = await crearDirecto("planta", { fotos: [{ origen: "camara" }], registro: { ...G, direccion: "[PRUEBA ZTRFC] Planta" }, area: "tecnica" });
  ok("E14 operador de planta desde Técnica con cámara, ubicación y dirección → 200 (área técnica)", r.s === 200 && r.j?.area === "tecnica" && filaReg(r.id) === "false|10.460100|[PRUEBA ZTRFC] Planta", `${r.s} ${JSON.stringify(r.j)}`);
  r = await crearDirecto("planta", { fotos: [{ origen: "archivo" }], registro: G, area: "tecnica" });
  ok("E15 operador de planta desde Técnica con un archivo → 403", r.s === 403, JSON.stringify(r.j));
  r = await crearDirecto("sin", { registro: G });
  ok("E16 sin permisos → 403", r.s === 403, JSON.stringify(r.j));
  r = await crearDirecto("op");
  ok("E17 la llamada de antes (sin «registro») sigue funcionando y no deja fila", r.s === 200 && filaReg(r.id) === "sin fila", `${r.s} ${filaReg(r.id)}`);
  // derivadas: conteo y descarga auditada
  const idSup = sqlq(`select id from campo.reportes where autor = '${E.sup}' order by seq limit 1`);
  sqlq(`insert into campo.derivadas (origen_id, contrato, actividad) values ('${idSup}', '991777', 'cambio_medidor'), ('${idSup}', '991777', 'accesorios')`);
  r = await llamar("sup", "derivadas", { estado: "pendiente", limite: 1 });
  ok("E18 derivadas: «total» y «pendientes» exactos aunque la página sea de 1", r.s === 200 && r.j.total === 2 && r.j.pendientes === 2 && r.j.filas.length === 1, JSON.stringify(r.j).slice(0, 300));
  r = await llamar("sup", "derivadas_descarga_iniciar", { filtros: { contrato: "991777" }, formato: "csv" });
  const did = r.j?.descarga_id;
  ok("E19 descarga de derivadas: iniciar → 200 con 2 filas y queda en la auditoría", r.s === 200 && r.j.total === 2 && sqlq(`select count(*) from public.geoportal_auditoria where id = ${did || 0} and accion = 'campo_derivadas_descarga_iniciar'`) === "1", JSON.stringify(r.j));
  r = await llamar("sup", "derivadas_descarga_pagina", { descarga_id: did });
  ok("E20 página: 2 filas, sin correos ni texto libre", r.s === 200 && r.j.devueltos === 2 && !/ztrfc\.|"texto"|"motivo"/.test(JSON.stringify(r.j)), JSON.stringify(r.j).slice(0, 300));
  r = await llamar("sup", "derivadas_descarga_cerrar", { descarga_id: did, filas: 2, resultado: "completa" });
  ok("E21 cerrar → 200", r.s === 200 && r.j.cerrada === true, JSON.stringify(r.j));
  r = await llamar("sup", "derivadas_descarga_iniciar", { filtros: { contrato: "991777", inventado: 1 }, formato: "csv" });
  ok("E22 un filtro desconocido en la descarga → 400 que lo nombra", r.s === 400 && /inventado/.test(JSON.stringify(r.j)), JSON.stringify(r.j));
  r = await llamar("op", "derivadas_descarga_iniciar", { filtros: {}, formato: "csv" });
  ok("E23 el operador no descarga derivadas → 403", r.s === 403, JSON.stringify(r.j));
  r = await llamar("sup", "derivadas_descarga_iniciar", { filtros: { contrato: "991777" }, formato: "xlsx", incluir_autor: true });
  ok("E24 el supervisor no puede pedir los correos → 403", r.s === 403, JSON.stringify(r.j));
}

// ---------- 6. Chrome ----------
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000,
  args: ["--no-sandbox", "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
// la «foto de la galería»: un JPEG de 1.200 × 900 px que dibuja el propio Chrome (con EXIF nulo: lo que importa es que se redibuje y comprima)
const FOTO = join(dir, "foto_galeria.jpg");
// Fotos de prueba en varios formatos (las dibuja el propio Chrome): JPEG, PNG y WebP. Y un «HEIC» (cabecera ftypheic) que Chrome no sabe abrir.
const FORMATOS = { jpeg: join(dir, "foto.jpg"), png: join(dir, "foto.png"), webp: join(dir, "foto.webp") };
{ const pg0 = await nav.newPage(); await pg0.goto(`http://127.0.0.1:${P_BASE}/?p=nada`);
  for (const [f, ruta] of Object.entries({ ...FORMATOS, base: FOTO })) {
    const b64 = await pg0.evaluate((tipo) => { const c = document.createElement("canvas"); c.width = 1200; c.height = 900; const x = c.getContext("2d");
      const g = x.createLinearGradient(0, 0, 1200, 900); g.addColorStop(0, "#3b7"); g.addColorStop(1, "#246"); x.fillStyle = g; x.fillRect(0, 0, 1200, 900);
      x.fillStyle = "#fff"; x.font = "bold 80px sans-serif"; x.fillText("FACHADA " + tipo.toUpperCase(), 120, 450); return c.toDataURL("image/" + (tipo === "base" ? "jpeg" : tipo), 0.9).split(",")[1]; }, f);
    writeFileSync(ruta, Buffer.from(b64, "base64"));
  }
  await pg0.close(); }
const HEIC = join(dir, "foto_iphone.heic");
writeFileSync(HEIC, Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from("ftypheic\0\0\0\0mif1heic"), Buffer.alloc(400, 7)]));
ok("F00 las fotos de prueba se generaron en su formato (PNG con su firma, WebP con RIFF)", readFileSync(FORMATOS.png).subarray(1, 4).toString() === "PNG" && readFileSync(FORMATOS.webp).subarray(8, 12).toString() === "WEBP");
async function abrir(qs, ancho) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.setGeolocation({ latitude: 10.4601, longitude: -73.2502, accuracy: 8 });
  await pg.goto(`http://127.0.0.1:${P_BASE}/?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(900);
  return pg;
}
const texto = (pg) => pg.$eval("body", (e) => e.innerText);
const hay = (pg, sel) => pg.$(sel).then((x) => !!x);
const clic = (pg, sel) => pg.evaluate((s) => { const b = document.querySelector(s); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "SELECT" ? HTMLSelectElement.prototype : i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const esperar = (pg, f, ...a) => pg.waitForFunction(f, { timeout: 20000 }, ...a).then(() => true).catch(() => false);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const foto = (pg, n) => pg.screenshot({ path: join(CAP, n + ".png"), fullPage: true });
const volverUnico = (pg) => pg.evaluate(() => { const b = [...document.querySelectorAll("[data-volver]")]; return b.length >= 1 && b.every((x) => x.textContent.trim() === "← Volver") && !/← Formatos|Volver a los formatos/.test(document.body.innerText); });

try {
  for (const ancho of [390, 1280]) {
    console.log(`— Chrome a ${ancho} px —`);
    // ===== Supervisor de Comercial: Reportar anomalía con galería, XY digitado y dirección =====
    let pg = await abrir("p=reporte&rol=sup", ancho);
    ok(`C${ancho}.01 supervisor: ve «Desde la galería», «Desde un archivo» y «Digitar el XY del punto»`, await hay(pg, "[data-rf-galeria]") && await hay(pg, "[data-rf-archivo]") && await hay(pg, "[data-rf-xy]"));
    ok(`C${ancho}.02 «← Volver» único en Reportar anomalía`, await volverUnico(pg));
    ok(`C${ancho}.03 «¿Quiere agregar dirección?» desmarcada y sin los campos`, await hay(pg, "[data-rf-direccion]") && !(await hay(pg, "#rf-direccion")));
    await escribir(pg, "#campo-grupo", GRUPO_OTRO); await esp(150); await escribir(pg, "#campo-tipo", "otro"); await esp(150);
    await escribir(pg, "#campo-desc", "[PRUEBA ZTRFC] registrado por el supervisor desde la oficina"); await esp(100);
    const entrada = await pg.$('input[data-rf-input="galeria"]'); await entrada.uploadFile(FOTO);
    ok(`C${ancho}.04 la foto de la galería queda puesta y marcada «Adjuntada desde la galería»`, await esperar(pg, () => !!document.querySelector('[data-rf-marca="galeria"]')));
    await clic(pg, "[data-rf-xy-activar]"); await esp(200);
    const pre = await pg.$eval("#rf-lat", (i) => i.value);
    ok(`C${ancho}.05 el XY se precarga con el GPS (coma decimal)`, /^10,4601/.test(pre), pre);
    await escribir(pg, "#rf-lat", "4,7"); await esp(150);
    ok(`C${ancho}.06 un XY fuera de Valledupar avisa y no deja enviar`, /fuera de la zona de Valledupar/.test(await texto(pg)) && await pg.$eval(".campo-enviar", (b) => b.disabled));
    await escribir(pg, "#rf-lat", "10,47123"); await escribir(pg, "#rf-lon", "-73,26111"); await esp(150);
    await clic(pg, "[data-rf-direccion-activar]"); await esp(150);
    ok(`C${ancho}.07 al marcar la dirección aparecen Dirección, Barrio y Referencia`, await hay(pg, "#rf-direccion") && await hay(pg, "#rf-barrio") && await hay(pg, "#rf-referencia"));
    await escribir(pg, "#rf-direccion", `[PRUEBA ZTRFC] CLL ${ancho}`); await escribir(pg, "#rf-barrio", "Los Mayales"); await esp(150);
    ok(`C${ancho}.08 sin desborde horizontal (supervisor, formulario lleno)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_sup_reporte`);
    await clic(pg, ".campo-enviar");
    ok(`C${ancho}.09 el supervisor envía: «Reporte guardado»`, await esperar(pg, () => /Reporte guardado/.test(document.body.innerText)), (await texto(pg)).slice(0, 400));
    const ult = sqlq(`select x.lat || '|' || x.lon || '|' || coalesce(x.precision_m::text, '-') || '|' || rr.xy_manual || '|' || rr.lat_registro || '|' || coalesce(rr.direccion, '-') || '|' || coalesce(rr.barrio, '-') || '|' || (select string_agg(origen, ',') from campo.reporte_fotos f where f.reporte_id = x.id)
                      from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id where x.autor = '${E.sup}' order by x.seq desc limit 1`);
    ok(`C${ancho}.10 en la base: XY digitado como punto, sin precisión, ubicación del dispositivo, dirección y foto de galería`,
      ult === `10.471230|-73.261110|-|true|10.460100|[PRUEBA ZTRFC] CLL ${ancho}|Los Mayales|galeria`, ult);
    await pg.close();

    // ===== Operador de campo: sigue igual (solo cámara), con dirección opcional =====
    pg = await abrir("p=reporte&rol=op", ancho);
    ok(`C${ancho}.11 operador: NO ve adjuntar ni XY`, !(await hay(pg, "[data-rf-galeria]")) && !(await hay(pg, "[data-rf-xy]")));
    ok(`C${ancho}.12 operador: sí ve «¿Quiere agregar dirección?»`, await hay(pg, "[data-rf-direccion]"));
    await escribir(pg, "#campo-grupo", GRUPO_OTRO); await esp(150); await escribir(pg, "#campo-tipo", "otro"); await esp(150);
    await escribir(pg, "#campo-desc", "[PRUEBA ZTRFC] el operario en el sitio"); await esp(100);
    await clicTexto(pg, "button", "Tomar foto 1");
    const lista = await esperar(pg, () => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; });
    if (lista) { await clic(pg, ".campo-capturar"); }
    ok(`C${ancho}.13 operador toma la foto con la cámara`, lista && await esperar(pg, () => !!document.querySelector(".campo-foto-img")));
    await clic(pg, "[data-rf-direccion-activar]"); await esp(100); await escribir(pg, "#rf-direccion", "[PRUEBA ZTRFC] escrita y desmarcada"); await clic(pg, "[data-rf-direccion-activar]"); await esp(150);
    ok(`C${ancho}.14 sin desborde horizontal (operador)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_op_reporte`);
    await clic(pg, ".campo-enviar");
    ok(`C${ancho}.15 el operador envía con cámara y GPS`, await esperar(pg, () => /Reporte guardado/.test(document.body.innerText)), (await texto(pg)).slice(0, 300));
    const uo = sqlq(`select rr.xy_manual || '|' || rr.lat_registro || '|' || coalesce(rr.direccion, '-') || '|' || (select string_agg(origen, ',') from campo.reporte_fotos f where f.reporte_id = x.id) || '|' || coalesce(x.precision_m::text, '-')
                     from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id where x.autor = '${E.op}' order by x.seq desc limit 1`);
    ok(`C${ancho}.16 en la base: GPS como punto con precisión, foto de cámara, y la dirección desmarcada NO se envió`, /^false\|10\.460100\|-\|camara\|\d/.test(uo), uo);
    await pg.close();

    // ===== Administrador =====
    pg = await abrir("p=reporte&rol=adm", ancho);
    ok(`C${ancho}.17 administrador: ve adjuntar y XY`, await hay(pg, "[data-rf-galeria]") && await hay(pg, "[data-rf-xy]"));
    await pg.close();
    // ===== Dual: en Comercial sí; desde Técnica no =====
    pg = await abrir("p=reporte&rol=dual", ancho);
    ok(`C${ancho}.18 dual en Comercial: ve adjuntar y XY`, await hay(pg, "[data-rf-galeria]") && await hay(pg, "[data-rf-xy]"));
    await pg.close();
    pg = await abrir("p=reporte&rol=dual&area=tecnica", ancho);
    ok(`C${ancho}.19 dual desde Técnica: NO ve adjuntar ni XY (sí la dirección)`, !(await hay(pg, "[data-rf-galeria]")) && !(await hay(pg, "[data-rf-xy]")) && await hay(pg, "[data-rf-direccion]"), (await texto(pg)).slice(0, 200));
    await pg.close();
    pg = await abrir("p=reporte&rol=planta&area=tecnica", ancho);
    ok(`C${ancho}.20 operador de planta desde Técnica: formulario sin adjuntar ni XY`, await hay(pg, "#campo-grupo") && !(await hay(pg, "[data-rf-galeria]")) && !(await hay(pg, "[data-rf-xy]")));
    await pg.close();
    // ===== Sin permisos =====
    pg = await abrir("p=reporte&rol=sin", ancho);
    ok(`C${ancho}.21 sin permisos: no se abre el formulario (403 del servidor)`, await hay(pg, "[data-error-formulario]") && !(await hay(pg, "#campo-grupo")), (await texto(pg)).slice(0, 200));
    await pg.close();

    // ===== Formatos de actividad =====
    pg = await abrir("p=formato&tipo=instalacion_acometida&rol=sup", ancho);
    ok(`C${ancho}.22 formato con contrato opcional (instalación de acometida): dirección, adjuntar por etiqueta y XY para el supervisor`,
      await hay(pg, "[data-rf-direccion]") && (await pg.$$("[data-rf-galeria]")).length >= 2 && await hay(pg, "[data-rf-xy]"));
    ok(`C${ancho}.23 «← Volver» único en el formato`, await volverUnico(pg));
    ok(`C${ancho}.24 sin desborde horizontal (formato del supervisor)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_sup_formato_acometida`);
    await pg.close();
    pg = await abrir("p=formato&tipo=revision_previa&rol=sup", ancho);
    ok(`C${ancho}.25 formato con contrato obligatorio (revisión previa): sin dirección; adjuntar y XY sí`, !(await hay(pg, "[data-rf-direccion]")) && await hay(pg, "[data-rf-galeria]") && await hay(pg, "[data-rf-xy]"));
    await pg.close();
    pg = await abrir("p=formato&tipo=revision_previa&rol=op", ancho);
    ok(`C${ancho}.26 operador en un formato: solo cámara (sin adjuntar ni XY)`, !(await hay(pg, "[data-rf-galeria]")) && !(await hay(pg, "[data-rf-xy]")));
    await pg.close();
    pg = await abrir("p=formatos&rol=sup", ancho);
    ok(`C${ancho}.27 «← Volver» único en la lista de formatos de actividad`, await volverUnico(pg), (await texto(pg)).slice(0, 200));
    await pg.close();

    // ===== Supervisión: lista, detalle y derivadas =====
    pg = await abrir("p=revision&rol=sup", ancho);
    const vioLista = await esperar(pg, () => /XY digitado — registrado desde otro punto/.test(document.body.innerText));
    ok(`C${ancho}.28 la lista de Reportes marca «XY digitado — registrado desde otro punto»`, vioLista, (await texto(pg)).slice(0, 500));
    ok(`C${ancho}.29 sin desborde horizontal (Supervisión)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_sup_lista`);
    const abrio = await pg.evaluate(() => { const f = [...document.querySelectorAll('[role="row"]')].find((e) => /XY digitado — registrado desde otro punto/.test(e.innerText));
      if (f) { f.scrollIntoView({ block: "center" }); f.click(); return true; } return false; });
    ok(`C${ancho}.30 el detalle muestra la marca, «Registrado desde» y la foto adjuntada`, abrio && await esperar(pg, () => !!document.querySelector("[data-rf-detalle-xy]") && !!document.querySelector("[data-rf-detalle-desde]") && /adjuntada desde/.test(document.body.innerText)),
      (await texto(pg)).slice(0, 600));
    await foto(pg, `${ancho}_sup_detalle`);
    await pg.close();
    pg = await abrir("p=revision&rol=sup&der=1", ancho);
    const cdp = await pg.target().createCDPSession(); const bajadas = mkdtempSync(join(tmpdir(), "bajadas_rf_"));
    await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: bajadas }).catch(() => cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: bajadas }));
    const vioDer = await esperar(pg, () => !!document.querySelector('[data-testid="reportes-derivadas"]') && !/cargando…/.test(document.querySelector('[data-testid="reportes-derivadas"]').innerText));
    ok(`C${ancho}.31 «Avisos y actividades derivadas» en Reportes, con el total del servidor`, vioDer && /\b2 filas\b/.test(await texto(pg)), (await texto(pg)).slice(0, 500));
    const audAntes = Number(sqlq("select count(*) from public.geoportal_auditoria where accion = 'campo_derivadas_descarga_cerrar'"));
    await clic(pg, '[data-accion="csv"]');
    const bajo = await esperar(pg, () => /quedó registrada en el servidor/.test(document.body.innerText));
    ok(`C${ancho}.32 la descarga CSV pasa por el servidor y queda auditada (iniciar y cerrar)`, bajo && Number(sqlq("select count(*) from public.geoportal_auditoria where accion = 'campo_derivadas_descarga_cerrar'")) === audAntes + 1,
      (await texto(pg)).slice(0, 400));
    await esp(600);
    ok(`C${ancho}.33 el archivo se descargó`, readdirSync(bajadas).some((f) => f.endsWith(".csv")), readdirSync(bajadas).join(","));
    ok(`C${ancho}.34 sin desborde horizontal (derivadas)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_sup_derivadas`);
    await pg.close();
  }
  // ===== Formatos de entrada (Chrome de escritorio, 1280 px): la foto adjuntada SIEMPRE se sube como JPEG; HEIC ilegible da un mensaje claro =====
  console.log("— Formatos de la foto adjuntada (1280 px) —");
  for (const [formato, archivo, boton] of [["jpeg", FORMATOS.jpeg, "galeria"], ["png", FORMATOS.png, "galeria"], ["webp", FORMATOS.webp, "archivo"]]) {
    const pg = await abrir("p=reporte&rol=sup", 1280);
    await escribir(pg, "#campo-grupo", GRUPO_OTRO); await esp(150); await escribir(pg, "#campo-tipo", "otro"); await esp(150);
    await escribir(pg, "#campo-desc", `[PRUEBA ZTRFC] foto adjuntada en ${formato}`); await esp(100);
    await (await pg.$(`input[data-rf-input="${boton}"]`)).uploadFile(archivo);
    const puesta = await esperar(pg, () => !!document.querySelector("[data-rf-marca]"));
    await clic(pg, ".campo-enviar");
    const guardo = puesta && await esperar(pg, () => /Reporte guardado/.test(document.body.innerText));
    const f = sqlq(`select f.ruta_storage || '|' || f.tipo_mime || '|' || f.origen from campo.reportes x join campo.reporte_fotos f on f.reporte_id = x.id where x.autor = '${E.sup}' and x.descripcion like '%en ${formato}' order by x.seq desc limit 1`);
    const [ruta, mime, origen] = f.split("|");
    ok(`F.${formato} una foto ${formato.toUpperCase()} adjuntada (${boton}) se guarda como JPEG (tipo image/jpeg y bytes FF D8 FF)`, guardo && mime === "image/jpeg" && firmas.get(ruta) === "jpeg" && origen === boton,
      `${f} firma=${firmas.get(ruta)} ${(await texto(pg)).slice(0, 300)}`);
    await pg.close();
  }
  {
    const pg = await abrir("p=reporte&rol=sup", 1280);
    await (await pg.$('input[data-rf-input="archivo"]')).uploadFile(HEIC);
    const msg = await esperar(pg, () => /Este navegador no puede abrir fotos HEIC\. Exporte la foto como JPEG o adjúntela desde el celular\./.test(document.body.innerText));
    ok("F.heic una foto HEIC que Chrome no puede leer: mensaje claro y no queda puesta", msg && !(await hay(pg, "[data-rf-marca]")), (await texto(pg)).slice(0, 300));
    await foto(pg, "1280_heic_mensaje");
    await pg.close();
  }
} catch (e) { total++; fallas++; console.log("FALLA excepción:", e?.stack ?? e); }
await nav.close(); srv.close(); edge.kill();
const lentas = rpcs.filter((r) => r.ms > 2000);
console.log(`RPC llamadas: ${rpcs.length}; la más lenta ${Math.max(...rpcs.map((r) => r.ms))} ms${lentas.length ? ` (lentas: ${lentas.map((r) => r.fn).join(", ")})` : ""}`);
console.log(`\nRESULTADO: ${total - fallas} de ${total}${fallas ? "" : " — SIN FALLAS"}`);
console.log(`Capturas en ${CAP}`);
process.exit(fallas ? 1 : 0);
