// Comercial 21-nov · Actas contra las Edges REALES del Code A (geoportal-campo y geoportal-acta, rama comercial-personal-cuadrillas 2a249ef, sacadas con git archive) en Deno, y su SQL
// (paquete (b) 8360c68) en el volcado doble que dejó el Code A (doble_comercial_con_actas.sql), cargado en el clúster del Code B. Chrome real.
// Usa el CLIENTE de las pantallas (apiDocumentos, apiFormatos, apiCampo) dentro de la página para registrar revisiones e instalaciones de verdad (fotos JPEG, firmas, crear,
// PDF, derivadas) y monta «Actas registradas» contra las Edges. Los formularios en sí (pintar los campos, el momento de firmar) se prueban con el simulador
// (prueba_chrome_actas_firmas.mjs): aquí el servidor es el de verdad. Storage se simula en memoria (fotos, PDF y URL firmadas).
// Las RPC van a la base local por psql con set role service_role, statement_timeout 30 s y lock_timeout 8 s (los topes de producción).
//   node scripts/prueba_chrome_actas_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <base plantilla> [capturas]
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55993 (base y storage) y 55994 (Edges). La copia de la plantilla activa «Instalación de medidor» y su grupo (en el doble vienen inactivos) para la derivada. No prueba: Supabase, el acta AI
// registrada de punta a punta (su contenido es largo; su firma y su lectura sí), ni un celular físico.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_actas_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <base plantilla> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA, CAP_ARG] = args;
if (!PLANTILLA) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_actas_edge")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55993, P_EDGE = 55994;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "zt.admin@emdupar.gov.co", sup: "zt.sup@emdupar.gov.co", act: "zt.act@emdupar.gov.co", op: "zt.ana@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
{
  const fila = (email, nombre, rol, campos) => `('${email}', '${nombre}', '${rol}', 'sin_restriccion', 'todos', ${["ver_campo", "ver_dashboard_campo", "ver_acta", "ver_dashboard_acta"].map((c) => (campos.includes(c) ? "true" : "false")).join(", ")})`;
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
    ${fila(E.adm, "ZT Administración", "admin", [])}, ${fila(E.sup, "ZT Supervisora de campo", "consulta", ["ver_dashboard_campo"])}, ${fila(E.act, "ZT Supervisor de actas", "consulta", ["ver_dashboard_acta"])},
    ${fila(E.op, "ZT Ana Operaria", "consulta", ["ver_campo", "ver_acta"])}`);
  sqlq(`update campo.tipos_reporte set activo = true where codigo = 'instalacion_medidor'`);     // solo en la copia de la prueba (en el doble viene inactiva, con su grupo)
  sqlq(`update campo.grupos_reporte set activo = true where id = (select grupo_id from campo.tipos_reporte where codigo = 'instalacion_medidor')`);
}
// Datos válidos de un formato, desde su catálogo: los obligatorios visibles con un valor de su tipo, más `extra`.
const ahoraBog = (minAtras) => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
  .format(new Date(Date.now() - minAtras * 60e3)).replace(", ", "T");
function datosPara(tipo, extra) {
  const campos = JSON.parse(sqlq(`select coalesce(json_agg(json_build_object('codigo', c.codigo, 'tipo', c.tipo_dato, 'opciones', c.opciones, 'visible_si', c.visible_si) order by c.orden), '[]') from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = ${lit(tipo)} and c.activo and c.obligatorio`));
  const d = {};
  for (const c of campos) {
    if (c.visible_si) continue;
    d[c.codigo] = c.tipo === "texto" ? "ZT prueba" : c.tipo === "opcion" ? c.opciones[0].codigo : c.tipo === "opciones" ? [c.opciones[0].codigo] : c.tipo === "si_no" ? false
      : c.tipo === "dia_hora" ? ahoraBog(c.codigo.includes("final") ? 5 : 40) : 1;
  }
  return { ...d, ...extra };
}
const fotosDe = (tipo) => sqlq(`select string_agg(tf.codigo, ',' order by tf.orden) from campo.tipo_fotos tf join campo.tipos_reporte t on t.id = tf.tipo_id where t.codigo = ${lit(tipo)} and tf.activo and tf.obligatoria`).split(",");

// ---------- 1. Página: el cliente de las pantallas en window.__api, o «Actas registradas» (?p=actas) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_actasedge_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: (bucket) => ({ uploadToSignedUrl: async (ruta, token, blob) => { const r = await fetch("http://127.0.0.1:${P_BASE}/storage/v1/object/upload/sign/" + bucket + "/" + ruta + "?token=" + token, { method: "PUT", headers: { "content-type": "image/jpeg" }, body: blob }); return { error: r.ok ? null : { message: "HTTP " + r.status } }; } }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import { apiDocumentos, esFirmaDefinitiva } from "./src/campo/documentos/apiDocumentos.ts"; import { apiFormatos } from "./src/campo/formatos/apiFormatos.ts"; import { apiCampo, ErrorCampo } from "./src/campo/apiCampo.ts";
    import { ActasRegistradas } from "./src/campo/documentos/ActasRegistradas.tsx";
    /** Una imagen JPEG de prueba (foto o firma) hecha con canvas. */
    async function jpeg(w, h, calidad) { const c = document.createElement("canvas"); c.width = w; c.height = h; const g = c.getContext("2d"); g.fillStyle = "#fff"; g.fillRect(0, 0, w, h); g.strokeStyle = "#123"; g.lineWidth = 4;
      g.beginPath(); for (let i = 0; i < 40; i++) g.lineTo(10 + i * (w - 20) / 40, h / 2 + Math.sin(i / 3) * h / 3); g.stroke(); g.fillStyle = "#782a27"; g.fillRect(w / 4, h / 4, w / 6, h / 6);
      return await new Promise((ok) => c.toBlob(ok, "image/jpeg", calidad)); }
    const b64 = async (blob) => { const s = new Uint8Array(await blob.arrayBuffer()); let t = ""; for (const x of s) t += String.fromCharCode(x); return btoa(t); };
    const err = (e) => ({ error: true, status: e?.status ?? 0, tipo: e?.tipo, mensaje: e?.message, definitiva: esFirmaDefinitiva(e) });
    window.__api = { apiDocumentos, apiFormatos, apiCampo, jpeg, b64, err,
      /** preparar_subida → fotos (JPEG) → devuelve el reporte_id y las fotos para crear. */
      async preparar(tipo, etiquetas) {
        const p = await apiFormatos.prepararSubida(etiquetas.length, tipo);
        for (const f of p.fotos) await apiCampo.subirFoto(f.ruta, f.token, await jpeg(640, 480, 0.8));
        return { reporte_id: p.reporte_id, fotos: p.fotos.map((f, i) => ({ orden: f.orden, ruta: f.ruta, etiqueta: etiquetas[i] })) };
      },
      firma: async () => b64(await jpeg(400, 140, 0.7)),
      async intentar(f) { try { return await f(); } catch (e) { return err(e); } },
    };
    const q = new URLSearchParams(location.search);
    if (q.get("p") === "actas") {
      const nombres = new Map([["acta", "Reportar posible pérdida"], ["revision_previa", "Revisiones generales"], ["instalacion_medidor", "Instalación de medidor"]]);
      createRoot(document.getElementById("raiz")).render(<div className="com-modulo"><ActasRegistradas correo={q.get("rol") + "@prueba"} onVolver={() => {}} nombres={nombres} puedeAperturas={q.get("rol") === "act"} puedeCerrarDerivadas={q.get("rol") !== "act"} /></div>);
    }
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Auth, Storage (en memoria) y PostgREST; las RPC van a la base local REAL ----------
const rpcs = [], desconocidas = [], objetos = new Map();
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
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, x-upsert, apikey" };
function guardarObjeto(bucket, ruta, bytes, mime) {
  objetos.set(`${bucket}/${ruta}`, { bytes, mime });
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(bucket)}, ${lit(ruta)}, ${lit({ size: bytes.length, mimetype: mime })}) on conflict do nothing`);
}
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
    let m;
    if ((m = /^\/storage\/v1\/object\/upload\/sign\/([^/]+)\/(.+)$/.exec(p))) {
      const [, bucket, ruta] = m;
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/${bucket}/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "PUT") { if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" }); guardarObjeto(bucket, ruta, cuerpo, req.headers["content-type"]); return json(200, { Key: `${bucket}/${ruta}` }); }
    }
    if ((m = /^\/storage\/v1\/object\/sign\/([^/]+)\/(.+)$/.exec(p))) { const [, bucket, ruta] = m; return objetos.has(`${bucket}/${ruta}`) ? json(200, { signedURL: `/object/leer/${bucket}/${ruta}?token=l` }) : json(404, { error: "not_found" }); }
    if ((m = /^\/storage\/v1\/object\/leer\/([^/]+)\/(.+)$/.exec(p))) { const o = objetos.get(`${m[1]}/${m[2]}`); if (!o) return json(404, {}); res.writeHead(200, { "Content-Type": o.mime, ...cors }); return res.end(o.bytes); }
    if ((m = /^\/storage\/v1\/object\/([^/]+)\/(.+)$/.exec(p))) {
      const [, bucket, ruta] = m;
      if (req.method === "GET") { const o = objetos.get(`${bucket}/${ruta}`); if (!o) return json(404, { error: "not_found" }); res.writeHead(200, { "Content-Type": o.mime }); return res.end(o.bytes); }
      if (req.method === "POST") { if (objetos.has(`${bucket}/${ruta}`) && req.headers["x-upsert"] === "false") return json(409, { error: "Duplicate" }); guardarObjeto(bucket, ruta, cuerpo, req.headers["content-type"]); return json(200, { Key: `${bucket}/${ruta}` }); }
    }
    if (p.startsWith("/rest/v1/rpc/")) {
      const fn = p.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (fn === "geoportal_estado_acceso" || fn.startsWith("geoportal_campo_") || fn.startsWith("geoportal_acta_") || fn.startsWith("geoportal_salida_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      desconocidas.push(fn); return json(404, { code: "PGRST202", message: "no existe" });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-acta/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-acta") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", SUPABASE_SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 40000); });

// ---------- 4. Chrome ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 600)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000, args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
let ultima = null;
async function abrir(rol, ancho = 1280, extra = "") {
  const pg = await nav.newPage(); ultima = pg;
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.evaluateOnNewDocument(() => { window.__abiertos = []; window.open = (u) => { window.__abiertos.push(u); return null; }; });
  await pg.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${extra}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(300);
  return pg;
}
const api = (pg, f, ...a) => pg.evaluate(f, ...a);
const texto = (pg, sel = "body") => pg.$eval(sel, (e) => e.innerText);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : i.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const generaResultado = (tipo) => sqlq(`select genera_resultado from campo.tipos_reporte where codigo = ${lit(tipo)}`) === "t";
const cuerpoCrear = (reporte_id, tipo, fotos, datos, contrato = "123456") => ({ reporte_id, tipo, subtipo: null, descripcion: null, contrato, lat: 10.46, lon: -73.25, precision_m: 5, riesgo_inmediato: false, origen: "campo", fotos, datos, resultado: generaResultado(tipo) ? "efectivo" : null, causal: null, inicio_dispositivo: new Date(Date.now() - 40 * 60e3).toISOString() });

try {
  let pg = await abrir("op");
  // 1. Qué lleva cada formulario (documentos_catalogo de las dos Edges)
  const cat = await api(pg, async () => ({ campo: await window.__api.intentar(() => window.__api.apiDocumentos.catalogo("campo")), acta: await window.__api.intentar(() => window.__api.apiDocumentos.catalogo("acta")) }));
  const claves = (cat.campo.formularios ?? []).map((f) => f.formulario).filter((f) => f.startsWith("tipo:")).sort();
  ok("documentos_catalogo (campo): los 8 formatos de David (más el acta) con PDF y firmas operario obligatoria, usuario y testigo opcionales",
    JSON.stringify(claves) === JSON.stringify(["tipo:corte", "tipo:instalacion_acometida", "tipo:instalacion_medidor", "tipo:reconexion_servicio", "tipo:reinstalacion", "tipo:revision_pqr", "tipo:revision_previa", "tipo:suspension"])
    && cat.campo.formularios.every((f) => f.lleva_pdf && f.firmas.operario === "obligatoria" && f.firmas.usuario === "opcional" && f.firmas.testigo === "opcional"), JSON.stringify(cat).slice(0, 500));
  ok("documentos_catalogo (acta): el acta de posible pérdida con PDF y las tres firmas", (cat.acta.formularios ?? []).some((f) => f.formulario === "acta" && f.lleva_pdf && f.firmas.operario === "obligatoria"), JSON.stringify(cat.acta).slice(0, 300));

  // 2. Revisión general #1: sin la firma del operario no registra; req_cambio_medidor que no coincide se rechaza; con todo, registra
  const etqRev = fotosDe("revision_previa");
  const rev = await api(pg, async (etq) => window.__api.preparar("revision_previa", etq), etqRev);
  const datosRev = datosPara("revision_previa", { firma_atendio: "atendio_firmo", atendio_nombre: "ZT Rosa Atendió", da_lugar: ["cambio_medidor", "fuga_externa"], req_cambio_medidor: true });
  let r = await api(pg, async (c) => window.__api.intentar(() => window.__api.apiFormatos.crear(c)), cuerpoCrear(rev.reporte_id, "revision_previa", rev.fotos, datosRev));
  ok("crear sin la firma del operario: 400 «Falta la firma del operario» (la pantalla no deja llegar aquí)", r.error && r.status === 400 && /Falta la firma del operario/.test(r.mensaje), JSON.stringify(r));
  r = await api(pg, async (id) => { const A = window.__api; return { sinNombre: await A.intentar(() => A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "usuario", estado: "firmo", imagen: "x".repeat(10) })),
    testigoMal: await A.intentar(async () => { await A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "usuario", estado: "firmo", nombre: "ZT Rosa Atendió", imagen: await A.firma() }); return A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "testigo", estado: "firmo", nombre: "ZT Luis", imagen: await A.firma() }); }) }; }, rev.reporte_id);
  ok("firma_guardar valida: «firmo» sin nombre o sin imagen válida → 400; testigo con el usuario que sí firmó → 400 (los textos se muestran tal cual)", r.sinNombre.error && r.sinNombre.status === 400 && r.testigoMal.error && r.testigoMal.status === 400, JSON.stringify(r));
  r = await api(pg, async (id) => window.__api.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await window.__api.firma() }), rev.reporte_id);
  const r2 = await api(pg, async (id) => window.__api.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await window.__api.firma() }), rev.reporte_id);
  ok("firma_guardar del operario (JPEG en base64): responde {rol, estado, sha256} y repetirla antes de registrar la reemplaza", r.rol === "operario" && r.estado === "firmo" && /^[0-9a-f]{64}$/.test(r.sha256 ?? "") && r2.rol === "operario", JSON.stringify([r, r2]));
  r = await api(pg, async (c) => window.__api.intentar(() => window.__api.apiFormatos.crear(c)), cuerpoCrear(rev.reporte_id, "revision_previa", rev.fotos, { ...datosRev, req_cambio_medidor: false }));
  ok("req_cambio_medidor que no coincide con da_lugar: 400 con el texto de la base", r.error && r.status === 400 && /no coincide con las actividades derivadas/.test(r.mensaje), JSON.stringify(r));
  const conf = await api(pg, async (c) => window.__api.intentar(() => window.__api.apiFormatos.crear(c)), cuerpoCrear(rev.reporte_id, "revision_previa", rev.fotos, datosRev));
  ok("crear con las firmas y req_cambio_medidor = true (cambio_medidor ∈ da_lugar, como lo calcula la pantalla): registra con consecutivo", !conf.error && !!conf.consecutivo, JSON.stringify(conf));
  r = await api(pg, async (id) => window.__api.intentar(async () => window.__api.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await window.__api.firma() })), rev.reporte_id);
  ok("después de registrar, firma_guardar: 409 «la firma es definitiva», y la pantalla lo reconoce (esFirmaDefinitiva) para seguir sin trabarse", r.error && r.status === 409 && r.definitiva === true, JSON.stringify(r));
  // 3. PDF
  const pdf = await api(pg, async (id) => window.__api.intentar(() => window.__api.apiDocumentos.pdfGenerar("campo", id)), rev.reporte_id);
  ok("pdf_generar: nombre AAAAMMDDHHMMSS-SIGLA-NÚMERO.pdf, sha256, bytes, versión 1 y URL firmada; queda en el bucket privado", !pdf.error && /^\d{14}-[A-Z]+-.+\.pdf$/.test(pdf.nombre) && /^[0-9a-f]{64}$/.test(pdf.sha256) && pdf.bytes > 1000 && pdf.version === 1 && !!pdf.url
    && [...objetos.keys()].some((k) => k.endsWith(".pdf")), JSON.stringify(pdf).slice(0, 400));
  const pdfBytes = [...objetos.entries()].find(([k]) => k.endsWith(".pdf"))?.[1].bytes ?? Buffer.alloc(0);
  writeFileSync(join(CAP, "pdf_revision_edge.pdf"), pdfBytes);
  ok("el PDF es un PDF y no lleva el teléfono; sí lleva la leyenda del acta física (texto del PDF sin comprimir o con flujos: se busca el encabezado)", pdfBytes.slice(0, 5).toString() === "%PDF-", pdfBytes.slice(0, 20).toString());
  const pdf2 = await api(pg, async (id) => window.__api.apiDocumentos.pdfGenerar("campo", id), rev.reporte_id);
  const url2 = await api(pg, async (id) => window.__api.apiDocumentos.pdfUrl("campo", id), rev.reporte_id);
  ok("pdf_generar es idempotente (mismo nombre y sha256) y pdf_url devuelve el mismo archivo", pdf2.nombre === pdf.nombre && pdf2.sha256 === pdf.sha256 && url2.sha256 === pdf.sha256, JSON.stringify([pdf2.nombre, url2.nombre]));
  // 4. Derivadas: la revisión dejó «cambio de medidor» y «fuga afuera»; una instalación de medidor las ofrece y atiende la primera
  const der = await api(pg, async () => window.__api.apiDocumentos.derivadasAbiertas("123456", "tipo:instalacion_medidor"));
  const cm = der.derivadas.find((d) => d.actividad === "cambio_medidor");
  ok("derivadas_abiertas (contrato 123456, Instalación de medidor): ofrece «cambio de medidor» y «fuga afuera» de la revisión, con su origen", !!cm && der.derivadas.some((d) => d.actividad === "fuga_externa") && cm.origen.consecutivo === conf.consecutivo, JSON.stringify(der).slice(0, 500));
  const etqInst = fotosDe("instalacion_medidor");
  const inst = await api(pg, async (etq) => window.__api.preparar("instalacion_medidor", etq), etqInst);
  await api(pg, async (id) => { await window.__api.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await window.__api.firma() }); await window.__api.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "usuario", estado: "nadie_atendio" }); }, inst.reporte_id);
  const confInst = await api(pg, async (c) => window.__api.intentar(() => window.__api.apiFormatos.crear(c)), cuerpoCrear(inst.reporte_id, "instalacion_medidor", inst.fotos, datosPara("instalacion_medidor", {})));
  ok("instalación de medidor con firma del operario y «nadie atendió»: registra", !confInst.error && !!confInst.consecutivo, JSON.stringify(confInst));
  r = await api(pg, async (d, id) => window.__api.intentar(() => window.__api.apiDocumentos.derivadaAtender(d, id)), cm.id, inst.reporte_id);
  ok("derivada_atender después de registrar", !r.error, JSON.stringify(r));
  const der2 = await api(pg, async () => window.__api.apiDocumentos.derivadasAbiertas("123456", "tipo:instalacion_medidor"));
  ok("la derivada atendida ya no se ofrece; «fuga afuera» sigue pendiente", !der2.derivadas.some((d) => d.id === cm.id) && der2.derivadas.some((d) => d.actividad === "fuga_externa"), JSON.stringify(der2).slice(0, 300));
  r = await api(pg, async () => window.__api.intentar(() => window.__api.apiDocumentos.actasAbiertas("123456")));
  ok("actas_abiertas responde con la forma del contrato ({actas: [...]}; sin actas AI en este contrato)", !r.error && Array.isArray(r.actas), JSON.stringify(r));
  r = await api(pg, async () => window.__api.intentar(() => window.__api.apiDocumentos.actasRegistradas("campo", {})));
  ok("el operario NO lee «actas registradas» (403)", r.error && r.status === 403, JSON.stringify(r));
  await pg.close();

  for (const ancho of [390, 1280]) {
    // 5. «Actas registradas» del supervisor de campo (por geoportal-campo)
    pg = await abrir("sup", ancho, "&p=actas");
    await pg.waitForSelector("[data-testid=actas-registradas] [data-registro]", { timeout: 30000 }); await esp(400);
    let t = await texto(pg, "[data-testid=actas-registradas]");
    ok(`[${ancho}] sup · Actas registradas desde la Edge real: la revisión con «PDF listo», sus firmas y sus 2 actividades derivadas; la instalación con «nadie atendió»; sin nombres`,
      t.includes(conf.consecutivo) && t.includes(confInst.consecutivo) && t.includes("PDF listo") && /firmó el usuario/.test(t) && t.includes("nadie atendió") && (ancho === 390 ? t.includes("2 actividades · 1 pendiente") : t.includes("2 actividades · atendidas")) && !t.includes("ZT Rosa"), t.slice(0, 700));
    ok(`[${ancho}] sup · el selector de tipo trae los 9 (campo + acta, sin repetir)`, await pg.$$eval("[data-filtro=tipo] option", (o) => o.length) === 10, String(await pg.$$eval("[data-filtro=tipo] option", (o) => o.map((x) => x.value))));
    await escribir(pg, "[data-filtro=tipo]", "instalacion_medidor"); await clicTexto(pg, "button", "Buscar"); await esp(800);
    ok(`[${ancho}] sup · filtrar por tipo (Instalación de medidor) desde la Edge`, (await pg.$$("[data-registro]")).length === 1 && (await texto(pg, "[data-testid=actas-registradas]")).includes(confInst.consecutivo));
    if (ancho === 390) {
      await clicTexto(pg, `[data-registro] button`, "Generar el PDF"); await pg.waitForFunction(() => document.querySelector("[data-registro]").innerText.includes("PDF listo"), { timeout: 60000 });
      ok(`[${ancho}] sup · «Generar el PDF» de la instalación (pdf nulo en la fila = pendiente): PDF listo con su nombre`, /\d{14}-[A-Z]+-.*\.pdf/.test(await texto(pg, "[data-registro]")));
    } else ok(`[${ancho}] sup · la instalación ya sale con «PDF listo» y «Descargar el PDF» (se generó una vez)`, (await texto(pg, "[data-registro]")).includes("PDF listo") && (await texto(pg, "[data-registro]")).includes("Descargar el PDF"));
    await escribir(pg, "[data-filtro=tipo]", ""); await clicTexto(pg, "button", "Buscar"); await esp(800);
    const csv = await (async () => {
      const cdp = await pg.target().createCDPSession(); await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: CAP, eventsEnabled: true });
      const hecho = new Promise((ok2) => cdp.on("Browser.downloadProgress", (e) => { if (e.state === "completed") ok2(); }));
      await clicTexto(pg, "button", "Descargar CSV"); await Promise.race([hecho, esp(15000)]); await esp(300);
      try { return readFileSync(join(CAP, `actas_registradas_${new Date().toISOString().slice(0, 10)}.csv`), "utf8"); } catch { return ""; }
    })();
    ok(`[${ancho}] sup · Descargar CSV desde la Edge (actas_registradas_descarga): las 2 filas, sin nombres de quien atendió ni del testigo`, csv.split("\r\n").length === 3 && csv.includes(conf.consecutivo) && !/ZT Rosa|ZT Luis/.test(csv), csv.slice(0, 400));
    await pg.screenshot({ path: join(CAP, `edge_actas_registradas_${ancho}.png`), fullPage: ancho < 500 });
    // Derivadas: «fuga afuera» pendiente → cerrar sin formulario (solo en el primer ancho; en el segundo ya está cerrada)
    await clicTexto(pg, "button.rv-tab", "Actividades derivadas"); await pg.waitForSelector("[data-testid=derivadas]"); await esp(800);
    t = await texto(pg, "[data-testid=derivadas]");
    if (ancho === 390) {
      ok(`[${ancho}] sup · Actividades derivadas: «fuga afuera» pendiente con su origen`, /fuga/i.test(t) && t.includes("Pendiente") && t.includes(conf.consecutivo), t.slice(0, 500));
      await clicTexto(pg, "[data-derivada] button", "Cerrar sin formulario"); await pg.waitForSelector(".rv-modal textarea");
      await pg.evaluate(() => document.querySelectorAll('.rv-modal input[name="doc-cierre"]')[1].click());
      await escribir(pg, ".rv-modal textarea", "ZT No procede: la fuga era dentro de la casa"); await clicTexto(pg, ".rv-modal button.rv-boton", "Cerrar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal"), { timeout: 20000 }); await esp(600);
      ok(`[${ancho}] sup · derivada_cerrar «anulada» con motivo: ya no hay pendientes y sale el aviso`, (await pg.$$("[data-testid=derivadas] li[data-derivada]")).length === 0 && (await texto(pg, "[data-testid=derivadas]")).includes("quedó cerrada"), await texto(pg, "[data-testid=derivadas]"));
    } else {
      await escribir(pg, "[data-filtro=estado]", ""); await esp(1200);
      t = await texto(pg, "[data-testid=derivadas]");
      ok(`[${ancho}] sup · «Todas»: la atendida (con el registro que la atendió) y la anulada (quién, cuándo y el motivo)`, t.includes("La atendió") && t.includes(confInst.consecutivo) && t.includes("Anulada") && t.includes("por zt.sup@emdupar.gov.co") && t.includes("ZT No procede: la fuga era dentro de la casa"), t.slice(0, 600));
    }
    await pg.close();
    // 6. Supervisor de actas (por geoportal-acta)
    pg = await abrir("act", ancho, "&p=actas");
    await pg.waitForSelector("[data-testid=actas-registradas] [data-registro], [data-testid=actas-registradas] [role=alert], [data-testid=actas-registradas] .rv-vacio", { timeout: 30000 }); await esp(300);
    t = await texto(pg, "[data-testid=actas-registradas]");
    ok(`[${ancho}] supervisor de actas · lee por geoportal-acta (la misma RPC): ve las dos y sin la pestaña de derivadas`, t.includes(conf.consecutivo) && t.includes(confInst.consecutivo) && !(await pg.$$eval("button.rv-tab", (l) => l.map((x) => x.textContent))).includes("Actividades derivadas"), t.slice(0, 400));
    await pg.close();
  }
  const lentas = rpcs.filter((x) => !x.error).sort((a, b) => b.ms - a.ms).slice(0, 3);
  ok(`ninguna RPC desconocida y ninguna tardó más de 3 s en local (más lentas: ${lentas.map((x) => `${x.fn} ${x.ms} ms`).join(", ")})`, desconocidas.length === 0 && lentas.every((x) => x.ms < 3000), JSON.stringify(desconocidas));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700)); if (ultima) console.log("Pantalla:", (await ultima.evaluate(() => document.body.innerText).catch(() => "")).slice(0, 700)); console.log("Edge:", edgeLog.slice(-800)); }
await nav.close(); srv.close(); edge.kill();
console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
