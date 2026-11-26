// [Code A] Consultar direcciones (25-nov) · prueba de la EDGE REAL por llamada directa y de las PANTALLAS en CHROME REAL, sin Supabase:
//   pantallas reales (AnalisisContrato, ReporteGeneral, FormularioFormato, Revision → Detalle) → Edges REALES geoportal-campo y geoportal-acta (Deno, de
//   ~/geoportal-web-dirs) → PostgREST, Auth y Storage mínimos en Node que llaman a las RPC REALES de la base local del Code A (55432): copia de producción con el
//   registro flexible publicado y este paquete migrado (base_chrome.py). Cada RPC como service_role con 30 s y 8 s. A 390 px (táctil) y 1280 px.
// Perfiles: administrador, supervisor de Comercial, operador de campo SIN Análisis, analista (campo y Análisis), dual (supervisor de Comercial y operador de Técnica),
// sin permisos, y el operador de planta (Técnica). Contratos de prueba de 12 dígitos 9918000000NN en cartera y censo (solo en la base local).
//   node scripts/prueba_chrome_consultar_direcciones.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55961 (app, Auth, PostgREST, Storage) y 55962 (Edges).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";
const USO = "Uso: node scripts/prueba_chrome_consultar_direcciones.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, CAP_ARG] = args;
if (!FUNCIONES) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_consultar_direcciones")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55961, P_EDGE = 55962, DB = "emdupar_a_rf_dirchrome";
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "ztdc.adm@emdupar.gov.co", sup: "ztdc.sup@emdupar.gov.co", op: "ztdc.op@emdupar.gov.co", ana: "ztdc.ana@emdupar.gov.co", dual: "ztdc.dual@emdupar.gov.co", sin: "ztdc.sin@emdupar.gov.co", planta: "ztdc.planta@emdupar.gov.co" };

// ---------- 1. Base ----------
execFileSync("python3", ["-I", "-B", join(raiz, "sql/campo_consultar_direcciones/pruebas_locales/base_chrome.py"), DB], { stdio: ["ignore", "pipe", "inherit"] });
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('${E.adm}', 'ZTDC Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('${E.sup}', 'ZTDC Supervisora', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('${E.op}', 'ZTDC Operario sin Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('${E.ana}', 'ZTDC Analista', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true),
  ('${E.dual}', 'ZTDC Dual', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true, false),
  ('${E.sin}', 'ZTDC Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('${E.planta}', 'ZTDC Planta', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, false);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${E.dual}', 'asignar_formulario', 'anomalia_compartida', '${E.adm}'),
   ('${E.planta}', 'asignar_formulario', 'entrada', '${E.adm}'), ('${E.planta}', 'asignar_formulario', 'anomalia_compartida', '${E.adm}');
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000001', 'ACTIVO', 'ZTDC PERSONA UNO', '3001112233', 'CRA 9 # 12-30 TORRE 2 APTO 301', 'CENTRO', 123456, '20261123'),
    ('991800000002', 'ACTIVO', 'ZTDC PERSONA DOS', '3002223344', 'CLL 5 # 3-10', 'LOS MAYALES', 0, '20261123');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, clase_uso, act_eco, unih, uninh, telefono) values
    ('991800000001', 'CRA 9 12 30', 'CENTRO', 'RESIDENCIAL RESIDENCIAL', 'NO APLICA', '- 4- - - CASA- CS- 1- - - - ,- - - - - APTO- AP- 101- - - - ,- ', 'NO APLICA', '3009998877');`);
const GRUPO_OTRO = sqlq("select g.codigo from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = 'otro'");

// ---------- 2. La app (esbuild) con un doble de lib/supabase que da el token del rol y sube al Storage simulado ----------
const dir = mkdtempSync(join(tmpdir(), "ui_dirs_"));
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
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css"; import "./src/campo/analisis/analisis.css";
    import { ReporteGeneral } from "./src/campo/ReporteGeneral.tsx";
    import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx";
    import { FormatosCampo } from "./src/campo/formatos/FormatosCampo.tsx";
    import Revision from "./src/campo/dashboard/Revision.tsx";
    import AnalisisContrato from "./src/campo/analisis/AnalisisContrato.tsx";
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
    if (p === "consultar") raizApp.render(<div className="campo-contenedor com-modulo"><AnalisisContrato onVolver={() => {}} /></div>);
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
const llamar = async (rol, accion, qs = "", cuerpo) => {
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-campo?accion=${accion}${qs}`, { method: cuerpo === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer tok-${rol}`, "Content-Type": "application/json" }, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  let j = null; try { j = await r.json(); } catch { /* sin cuerpo */ } return { s: r.status, j };
};
console.log("— Edge por llamada directa —");
{
  let r = await llamar("op", "direccion_contrato", "&contrato=991800000001");
  ok("E01 operario SIN Análisis: ve las dos direcciones del contrato", r.s === 200 && r.j.comercial?.direccion === "CRA 9 # 12-30 TORRE 2 APTO 301" && r.j.catastro?.direccion === "CRA 9 12 30" && r.j.distintas === true, JSON.stringify(r.j));
  ok("E02 nada más: ni nombre, ni teléfono, ni deuda", !/ZTDC PERSONA|300111|300999|123456|nombre|telefono|deuda/.test(JSON.stringify(r.j)), JSON.stringify(r.j));
  r = await llamar("op", "analisis_contrato", "&contrato=991800000001");
  ok("E03 pero no puede «Consultar» (403)", r.s === 403, JSON.stringify(r.j));
  r = await llamar("op", "direccion_contrato", "&contrato=991800000099");
  ok("E04 contrato inexistente: «no encontrado» y nada más", r.s === 200 && r.j.encontrado === false && Object.keys(r.j).length === 2, JSON.stringify(r.j));
  r = await llamar("op", "direccion_contrato", "&contrato=12A");
  ok("E05 contrato con letras: 400 desde la Edge", r.s === 400, JSON.stringify(r.j));
  r = await llamar("sin", "direccion_contrato", "&contrato=991800000001");
  ok("E06 sin permisos: 403", r.s === 403, JSON.stringify(r.j));
  r = await llamar("planta", "direccion_contrato", "&contrato=991800000001&area=tecnica");
  ok("E07 operador de planta desde Técnica: la ve", r.s === 200 && r.j.comercial?.barrio === "CENTRO", JSON.stringify(r.j));
  r = await llamar("planta", "direccion_contrato", "&contrato=991800000001");
  ok("E08 operador de planta por la ruta de Comercial: 403", r.s === 403, JSON.stringify(r.j));
  r = await llamar("op", "direccion_contrato", "&contrato=991800000001", {});
  ok("E09 la ruta es GET (POST → 405)", r.s === 405, JSON.stringify(r.j));
  r = await llamar("ana", "analisis_contrato", "&contrato=991800000001");
  ok("E10 «Consultar» trae las dos direcciones y el predio", r.s === 200 && r.j.direcciones?.comercial?.direccion === "CRA 9 # 12-30 TORRE 2 APTO 301" && r.j.predio?.clase_uso === "RESIDENCIAL", JSON.stringify(r.j?.predio));
  sqlq("update campo.parametros set valor = 3 where clave = 'limite_direccion_hora'");
  const n0 = Number(sqlq(`select count(*) from campo.consultas_analisis where autor = '${E.op}' and via = 'formato'`));
  for (let i = n0; i < 3; i++) await llamar("op", "direccion_contrato", "&contrato=991800000002");
  r = await llamar("op", "direccion_contrato", "&contrato=991800000002");
  ok("E11 el tope por hora responde 429 con el mensaje", r.s === 429 && /límite de 3 consultas/.test(JSON.stringify(r.j)), `${r.s} ${JSON.stringify(r.j)}`);
  sqlq("update campo.parametros set valor = 60 where clave = 'limite_direccion_hora'; delete from campo.consultas_analisis where false");
}
// el operario vuelve a tener cupo: sus consultas de prueba pasan a la hora anterior (solo en la base local; la bitácora no se modifica en producción)
sqlq(`alter table campo.consultas_analisis disable trigger consultas_analisis_inmutable; update campo.consultas_analisis set consultado_en = consultado_en - interval '2 hours' where autor like 'ztdc.%'; alter table campo.consultas_analisis enable trigger consultas_analisis_inmutable`);

const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000,
  args: ["--no-sandbox", "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
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

try {
  for (const ancho of [390, 1280]) {
    console.log(`— Chrome a ${ancho} px —`);
    // ===== Consultar (analista): Predio =====
    let pg = await abrir("p=consultar&rol=ana", ancho);
    await escribir(pg, "#ac-contrato", "991800000001"); await clicTexto(pg, "button", "Consultar");
    const vio = await esperar(pg, () => !!document.querySelector('[data-seccion="predio"]'));
    ok(`C${ancho}.01 Consultar: sección «Predio» con las dos direcciones por separado`, vio && await pg.$eval('[data-predio="dir-comercial"]', (e) => e.innerText) === "CRA 9 # 12-30 TORRE 2 APTO 301 · CENTRO"
      && await pg.$eval('[data-predio="dir-catastro"]', (e) => e.innerText) === "CRA 9 12 30 · CENTRO", (await texto(pg)).slice(0, 500));
    const unih = await pg.$eval('[data-predio="unih"]', (e) => e.innerText).catch(() => "");
    ok(`C${ancho}.02 unidades habitacionales: «2 unidades», cada una en su renglón y el original debajo`, /2 unidades/.test(unih) && /4 · CASA · CS · 1/.test(unih) && /APTO · AP · 101/.test(unih) && /En el censo:/.test(unih), unih);
    ok(`C${ancho}.03 no habitacionales «No aplica», clase de uso «RESIDENCIAL», actividad «NO APLICA»`, await pg.$eval('[data-predio="uninh"]', (e) => e.innerText) === "No aplica"
      && await pg.$eval('[data-predio="clase-uso"]', (e) => e.innerText) === "RESIDENCIAL" && await pg.$eval('[data-predio="act-eco"]', (e) => e.innerText) === "NO APLICA");
    ok(`C${ancho}.04 sin desborde horizontal (Consultar)`, await sinDesborde(pg));
    await pg.evaluate(() => document.querySelector('[data-seccion="predio"]').scrollIntoView()); await foto(pg, `${ancho}_consultar_predio`);
    await escribir(pg, "#ac-contrato", "991800000002"); await clicTexto(pg, "button", "Consultar");
    await esperar(pg, () => /CLL 5 # 3-10/.test(document.querySelector('[data-predio="dir-comercial"]')?.innerText ?? ""));
    ok(`C${ancho}.05 sin predio en el censo: catastro y predio «Sin dato»`, await pg.$eval('[data-predio="dir-catastro"]', (e) => e.innerText) === "Sin dato" && /no tiene predio en el censo/.test(await texto(pg)));
    await pg.close();
    // ===== Operario sin Análisis, en un formato con contrato obligatorio =====
    pg = await abrir("p=formato&tipo=revision_previa&rol=op", ancho);
    ok(`C${ancho}.06 formato con contrato obligatorio, sin contrato: no hay casilla de dirección`, !(await hay(pg, "[data-rf-direccion]")));
    await escribir(pg, "#fp-contrato", "991800000001");
    const dc = await esperar(pg, () => !!document.querySelector("[data-dc-direccion]"));
    ok(`C${ancho}.07 al escribir el contrato: «Dirección del contrato» y «En el catastro» (operario sin Análisis)`, dc && /Dirección del contrato:\s*CRA 9 # 12-30 TORRE 2 APTO 301 · CENTRO/.test(await pg.$eval("[data-dc-direccion]", (e) => e.innerText))
      && await hay(pg, "[data-dc-catastro]"), await texto(pg).then((t) => t.slice(0, 600)));
    ok(`C${ancho}.08 y aparece «La dirección en terreno es distinta» (desmarcada)`, /La dirección en terreno es distinta/.test(await texto(pg)) && !(await hay(pg, "#rf-direccion")));
    await clic(pg, "[data-rf-direccion-activar]"); await esp(150);
    ok(`C${ancho}.09 al marcarla se abren Dirección, Barrio y Referencia`, await hay(pg, "#rf-direccion") && await hay(pg, "#rf-barrio") && await hay(pg, "#rf-referencia"));
    ok(`C${ancho}.10 sin desborde horizontal (formato)`, await sinDesborde(pg));
    await pg.evaluate(() => document.querySelector("[data-dc-direccion]").scrollIntoView()); await foto(pg, `${ancho}_op_formato_direccion`);
    await escribir(pg, "#fp-contrato", "991800000099"); await esp(1500);
    ok(`C${ancho}.11 contrato inexistente: no se muestra nada (ni dirección ni casilla)`, !(await hay(pg, "[data-dc-direccion]")) && !(await hay(pg, "[data-rf-direccion]")), (await texto(pg)).slice(0, 300));
    await pg.close();
    // ===== Reportar anomalía con contrato (operario): registra con la dirección en terreno =====
    pg = await abrir("p=reporte&rol=op", ancho);
    ok(`C${ancho}.12 Reportar anomalía sin contrato: «¿Quiere agregar dirección?»`, /¿Quiere agregar dirección\?/.test(await texto(pg)));
    await escribir(pg, "#campo-grupo", GRUPO_OTRO); await esp(150); await escribir(pg, "#campo-tipo", "otro"); await esp(150);
    await escribir(pg, "#campo-desc", `[PRUEBA ZTDC] ${ancho}`); await escribir(pg, "#campo-contrato", "991800000001");
    await esperar(pg, () => !!document.querySelector("[data-dc-direccion]"));
    ok(`C${ancho}.13 con contrato: la dirección del contrato y «La dirección en terreno es distinta»`, /La dirección en terreno es distinta/.test(await texto(pg)) && !/¿Quiere agregar dirección\?/.test(await texto(pg)));
    await clic(pg, "[data-rf-direccion-activar]"); await esp(150); await escribir(pg, "#rf-direccion", `[PRUEBA ZTDC] CRA 9 # 12-32 (${ancho})`); await escribir(pg, "#rf-barrio", "CENTRO");
    await clicTexto(pg, "button", "Tomar foto 1");
    if (await esperar(pg, () => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; })) await clic(pg, ".campo-capturar");
    await esperar(pg, () => !!document.querySelector(".campo-foto-img"));
    await clic(pg, ".campo-enviar");
    ok(`C${ancho}.14 se registra`, await esperar(pg, () => /Reporte guardado/.test(document.body.innerText)), (await texto(pg)).slice(0, 300));
    const fila = sqlq(`select dc.direccion_comercial || '|' || coalesce(dc.direccion_catastro, '-') || '|' || rr.direccion from campo.reportes x join campo.reporte_direccion_contrato dc on dc.reporte_id = x.id
                       join campo.reporte_registro rr on rr.reporte_id = x.id where x.autor = '${E.op}' order by x.seq desc limit 1`);
    ok(`C${ancho}.15 en la base: la foto de las dos direcciones del contrato y la encontrada en terreno`, fila === `CRA 9 # 12-30 TORRE 2 APTO 301|CRA 9 12 30|[PRUEBA ZTDC] CRA 9 # 12-32 (${ancho})`, fila);
    await pg.close();
    // ===== Perfiles: supervisor, administrador, dual, sin permisos; y el operador de planta desde Técnica =====
    for (const rol of ["sup", "adm", "dual"]) {
      pg = await abrir(`p=reporte&rol=${rol}`, ancho);
      await escribir(pg, "#campo-contrato", "991800000002");
      ok(`C${ancho}.16 ${rol}: ve la dirección del contrato en Reportar anomalía`, await esperar(pg, () => /CLL 5 # 3-10 · LOS MAYALES/.test(document.querySelector("[data-dc-direccion]")?.innerText ?? "")));
      await pg.close();
    }
    pg = await abrir("p=reporte&rol=sin", ancho);
    ok(`C${ancho}.17 sin permisos: no se abre el formulario`, await hay(pg, "[data-error-formulario]") && !(await hay(pg, "#campo-contrato")));
    await pg.close();
    pg = await abrir("p=reporte&rol=planta&area=tecnica", ancho);
    await escribir(pg, "#campo-contrato", "991800000001");
    ok(`C${ancho}.18 operador de planta desde Técnica: ve la dirección del contrato`, await esperar(pg, () => /CRA 9 # 12-30/.test(document.querySelector("[data-dc-direccion]")?.innerText ?? "")));
    ok(`C${ancho}.19 una sola cabecera «← Volver» en el formulario`, (await pg.$$("[data-volver]")).length === 1);
    await pg.close();
    // ===== Supervisión: detalle =====
    pg = await abrir("p=revision&rol=sup", ancho);
    await esperar(pg, () => [...document.querySelectorAll('[role="row"]')].some((e) => /PRUEBA ZTDC/.test(e.innerText) || true));
    const abrio = await pg.evaluate((a) => { const f = [...document.querySelectorAll('[role="row"]')].find((e) => e.getAttribute("aria-rowindex") === "2"); if (f) { f.click(); return true; } return false; }, ancho);
    ok(`C${ancho}.20 el detalle muestra la dirección del contrato junto a la encontrada en terreno`, abrio && await esperar(pg, () => !!document.querySelector("[data-dc-detalle]") && /Dirección encontrada en terreno/.test(document.body.innerText)),
      (await texto(pg)).slice(0, 600));
    ok(`C${ancho}.21 sin desborde horizontal (Supervisión)`, await sinDesborde(pg));
    await foto(pg, `${ancho}_sup_detalle`);
    await pg.close();
  }
} catch (e) { total++; fallas++; console.log("FALLA excepción:", e?.stack ?? e); }
await nav.close(); srv.close(); edge.kill();
console.log(`\nRESULTADO: ${total - fallas} de ${total}${fallas ? "" : " — SIN FALLAS"}`);
console.log(`Capturas en ${CAP}`);
process.exit(fallas ? 1 : 0);
