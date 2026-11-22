// Servidor de REVISIÓN LOCAL (Code B, 22-nov; regla de David 10:39: revisión en local obligatoria antes de publicar). NUNCA toca Supabase:
//   la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado) → las Edges REALES geoportal-admin, geoportal-campo y geoportal-acta en Deno
//   → un PostgREST mínimo en Node que llama las RPC REALES de la base local del Code B (clúster 55442, por psql_b) como service_role con 30 s y 8 s (topes de producción).
//   Base: copia nueva de la plantilla (el doble de Administración del Code A, doble_admin_permisos_4a.sql, b1ca98db…: Comercial del 21-nov + las 4 funciones del Corte 4a +
//   geoportal_admin_guardar + 20 usuarios prueba.*@emdupar.gov.co). La copia se rehace en cada arranque: lo que se cambie en la revisión se pierde al reiniciar.
//   Auth simulado: se entra con el correo de cualquier usuario prueba.* de la lista blanca y CUALQUIER clave (un usuario creado con «Nuevo usuario» entra con la clave que se le dio).
//   Storage simulado en memoria (fotos, firmas y PDF). Las demás Edges (mapa, Técnica, Aseo, tablero) NO están: esas áreas muestran su aviso de error, a propósito.
//   Al arrancar siembra, por las Edges reales y como prueba.op.comercial, una revisión general (con firmas y 2 actividades derivadas, PDF generado) y una instalación de medidor
//   que atiende una de ellas: así «Actas registradas» y «Actividades derivadas» tienen qué mostrar (R3).
// Uso:
//   node scripts/revision_admin.mjs --servir <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <plantilla>
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error. Ctrl+C para terminar.
// Puertos del Code B: 55987 (páginas), 55988 (Auth, Storage y PostgREST), 55989 (Edges).
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/revision_admin.mjs --servir <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <plantilla>";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
if (args[0] !== "--servir") { console.error(`Falta --servir.\n${USO}`); process.exit(2); }
for (const a of args.slice(1)) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
if (args.length !== 7) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [, CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = args;
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const P_WEB = 55987, P_BASE = 55988, P_EDGE = 55989;
const BASE = `http://127.0.0.1:${P_BASE}`;
const DB = `${PLANTILLA}_rev`;
const PGENV = { ...process.env, LC_ALL: "C", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
if (execFileSync(PSQL, ["-AtqX", "-d", "postgres", "-c", "show port"], { env: PGENV, encoding: "utf8" }).trim() !== "55442") { console.error("No es el clúster del Code B (55442)"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 << 20 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);

// ---------- 0. La base: copia nueva de la plantilla ----------
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${DB}`, "-c", `create database ${DB} template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select count(*) from public.geoportal_lista_blanca where email like 'prueba.%@emdupar.gov.co'") !== "20" || sqlq("select pronargs from pg_proc where proname = 'geoportal_admin_permisos'") !== "20") {
  console.error(`La plantilla ${PLANTILLA} no es el doble de Administración del Code A (20 usuarios prueba.* y geoportal_admin_permisos de 20 parámetros)`); process.exit(2);
}
// R3: un supervisor de campo SIN dashboard_acta (los 20 del doble no traen ese caso: prueba.sup.comercial ya tiene dashboard_acta). Solo en la copia; no cuenta en los 20.
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, creado_por, horario, dias, ver_explorar, ver_focalizacion, ver_comercial, ver_rutas, ver_dashboard, ver_campo, ver_dashboard_campo)
      values ('prueba.r3.sup.campo@emdupar.gov.co', 'Prueba R3 supervisor de campo', 'consulta', true, 'prueba.admin@emdupar.gov.co', 'sin_restriccion', 'todos', false, false, false, false, false, true, true)`);
// Solo en la copia de la revisión (como en las pruebas de actas): «Instalación de medidor» y su grupo vienen inactivos en el doble; hacen falta para la derivada sembrada
sqlq(`update campo.tipos_reporte set activo = true where codigo = 'instalacion_medidor'`);
sqlq(`update campo.grupos_reporte set activo = true where id = (select grupo_id from campo.tipos_reporte where codigo = 'instalacion_medidor')`);

// ---------- 1. La app completa (Vite), apuntando a los servidores locales ----------
const DIST = mkdtempSync(join(tmpdir(), "rev_admin_app_"));
const v = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: BASE, VITE_SUPABASE_ANON_KEY: "clave-de-revision", VITE_FUNCTIONS_URL: `http://127.0.0.1:${P_EDGE}/functions/v1` } });
if (v.status !== 0) { console.error("La app no compiló\n" + v.stdout + v.stderr); process.exit(2); }

// Página de siembra (no es la app): el cliente real de las pantallas (apiFormatos, apiDocumentos, apiCampo), con la sesión de ?u=
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const SEM = mkdtempSync(join(tmpdir(), "rev_admin_siembra_"));
await build({
  plugins: [{ name: "doble-supabase", setup(b) {
    b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
    b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
      const u = new URLSearchParams(location.search).get("u");
      export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
      export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + u } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
        storage: { from: (bucket) => ({ uploadToSignedUrl: async (ruta, token, blob) => { const r = await fetch("${BASE}/storage/v1/object/upload/sign/" + bucket + "/" + ruta + "?token=" + token, { method: "PUT", headers: { "content-type": "image/jpeg" }, body: blob }); return { error: r.ok ? null : { message: "HTTP " + r.status } }; } }) } };` }));
  } }],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import { apiDocumentos } from "./src/campo/documentos/apiDocumentos.ts"; import { apiFormatos } from "./src/campo/formatos/apiFormatos.ts"; import { apiCampo } from "./src/campo/apiCampo.ts";
    async function jpeg(w, h, calidad) { const c = document.createElement("canvas"); c.width = w; c.height = h; const g = c.getContext("2d"); g.fillStyle = "#fff"; g.fillRect(0, 0, w, h); g.strokeStyle = "#123"; g.lineWidth = 4;
      g.beginPath(); for (let i = 0; i < 40; i++) g.lineTo(10 + i * (w - 20) / 40, h / 2 + Math.sin(i / 3) * h / 3); g.stroke(); return await new Promise((ok) => c.toBlob(ok, "image/jpeg", calidad)); }
    const b64 = async (blob) => { const s = new Uint8Array(await blob.arrayBuffer()); let t = ""; for (const x of s) t += String.fromCharCode(x); return btoa(t); };
    window.__api = { apiDocumentos, apiFormatos, apiCampo,
      async preparar(tipo, etiquetas) { const p = await apiFormatos.prepararSubida(etiquetas.length, tipo); for (const f of p.fotos) await apiCampo.subirFoto(f.ruta, f.token, await jpeg(640, 480, 0.8));
        return { reporte_id: p.reporte_id, fotos: p.fotos.map((f, i) => ({ orden: f.orden, ruta: f.ruta, etiqueta: etiquetas[i] })) }; },
      firma: async () => b64(await jpeg(400, 140, 0.7)) };
    window.__listo = true;` },
  bundle: true, platform: "browser", format: "iife", outfile: join(SEM, "siembra.js"), jsx: "automatic", logLevel: "error",
  define: { "import.meta.env.VITE_SUPABASE_URL": JSON.stringify(BASE), "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(SEM, "siembra.html"), `<!doctype html><html><head><meta charset="utf-8"></head><body><script src="siembra.js"></script></body></html>`);

// ---------- 2. Auth simulado, Storage en memoria y PostgREST mínimo (RPC reales, como service_role) ----------
const claves = new Map();      // correo → clave (solo los creados con «Nuevo usuario»; los prueba.* entran con cualquier clave)
const cuentasAuth = new Set(sqlq("select string_agg(email, ',') from public.geoportal_lista_blanca").split(","));
const objetos = new Map(), forma = new Map(), registro = [];
const CAB = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer, x-upsert" };
/** Cómo devuelve PostgREST la función: escalar (to_jsonb), conjunto (arreglo) o void (204 sin cuerpo, como producción). */
function formaDe(fn) {
  if (!forma.has(fn)) { const r = sqlq(`select proretset::text || '|' || prorettype::regtype::text from pg_proc where proname = ${lit(fn)} and pronamespace = 'public'::regnamespace limit 1`); forma.set(fn, r || null); }
  return forma.get(fn);
}
function rpcBase(fn, a) {
  const f = formaDe(fn); if (!f) return { status: 404, cuerpo: { code: "PGRST202", message: `no existe public.${fn}` } };
  const [conjunto, tipo] = f.split("|"), argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  const sel = conjunto === "true" ? `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.${fn}(${argumentos}) t` : tipo === "void" ? `select public.${fn}(${argumentos})` : `select to_jsonb(public.${fn}(${argumentos}))`;
  const t0 = Date.now();
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", sel],
      { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 << 20 });
    registro.push({ fn, ms: Date.now() - t0 });
    return tipo === "void" && conjunto !== "true" ? { status: 204 } : { status: 200, cuerpo: JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || ""); registro.push({ fn, ms: Date.now() - t0, error: t.slice(0, 300) });
    console.log(`   RPC ${fn} → error: ${((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || t).slice(0, 160)}`);
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim() } };
  }
}
function guardarObjeto(bucket, ruta, bytes, mime) {
  objetos.set(`${bucket}/${ruta}`, { bytes, mime });
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(bucket)}, ${lit(ruta)}, ${lit({ size: bytes.length, mimetype: mime })}) on conflict do nothing`);
}
const usuario = (email) => ({ id: "u-" + email, email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} });
const sesion = (email) => ({ access_token: "tok-" + email, refresh_token: "r-" + email, token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: usuario(email) });
const base = http.createServer((req, res) => {
  const u = new URL(req.url, BASE), p = decodeURIComponent(u.pathname);
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", ...CAB }); res.end(o === undefined ? "" : JSON.stringify(o)); };
  if (req.method === "OPTIONS") { res.writeHead(204, CAB); return res.end(); }
  if (p === "/siembra.html" || p === "/siembra.js") { res.writeHead(200, { "Content-Type": p.endsWith(".js") ? "text/javascript" : "text/html" }); return res.end(readFileSync(join(SEM, p.slice(1)))); }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos); let b = null; try { b = JSON.parse(cuerpo.toString() || "null"); } catch { /* binario */ }
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    // --- Auth (GoTrue) simulado ---
    if (p === "/auth/v1/token") {
      const g = u.searchParams.get("grant_type");
      if (g === "password") {
        const email = String(b?.email ?? "").trim().toLowerCase();
        if (!cuentasAuth.has(email) || (claves.has(email) && claves.get(email) !== b?.password)) return json(400, { error: "invalid_grant", error_description: "Invalid login credentials" });
        return json(200, sesion(email));
      }
      if (g === "refresh_token") { const email = String(b?.refresh_token ?? "").replace(/^r-/, ""); return cuentasAuth.has(email) ? json(200, sesion(email)) : json(400, { error: "invalid_grant" }); }
    }
    if (p === "/auth/v1/user") { const email = tok.replace(/^tok-/, ""); return cuentasAuth.has(email) ? json(200, usuario(email)) : json(401, { msg: "invalid JWT" }); }
    if (p === "/auth/v1/logout") return json(204);
    if (p === "/auth/v1/admin/users" && req.method === "POST") {
      const email = String(b?.email ?? "").toLowerCase();
      if (cuentasAuth.has(email)) return json(422, { msg: "A user with this email address has already been registered" });
      cuentasAuth.add(email); claves.set(email, String(b?.password ?? "")); console.log(`   Auth simulado: cuenta creada ${email}`); return json(200, usuario(email));
    }
    if (p === "/auth/v1/admin/generate_link") { const email = String(b?.email ?? "").toLowerCase(); return cuentasAuth.has(email) ? json(200, { user: usuario(email) }) : json(404, { msg: "User not found" }); }
    let m;
    if ((m = /^\/auth\/v1\/admin\/users\/u-(.+)$/.exec(p)) && req.method === "PUT") { claves.set(m[1], String(b?.password ?? "")); console.log(`   Auth simulado: clave nueva para ${m[1]}`); return json(200, usuario(m[1])); }
    // --- Storage en memoria ---
    if ((m = /^\/storage\/v1\/object\/upload\/sign\/([^/]+)\/(.+)$/.exec(p))) {
      const [, bucket, ruta] = m;
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/${bucket}/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "PUT") { if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" }); guardarObjeto(bucket, ruta, cuerpo, req.headers["content-type"]); return json(200, { Key: `${bucket}/${ruta}` }); }
    }
    if ((m = /^\/storage\/v1\/object\/sign\/([^/]+)\/(.+)$/.exec(p))) { const [, bucket, ruta] = m; return objetos.has(`${bucket}/${ruta}`) ? json(200, { signedURL: `/object/leer/${bucket}/${ruta}?token=l` }) : json(404, { error: "not_found" }); }
    if ((m = /^\/storage\/v1\/object\/leer\/([^/]+)\/(.+)$/.exec(p))) { const o = objetos.get(`${m[1]}/${m[2]}`); if (!o) return json(404, {}); res.writeHead(200, { "Content-Type": o.mime, ...CAB }); return res.end(o.bytes); }
    if ((m = /^\/storage\/v1\/object\/([^/]+)\/(.+)$/.exec(p))) {
      const [, bucket, ruta] = m;
      if (req.method === "GET") { const o = objetos.get(`${bucket}/${ruta}`); if (!o) return json(404, { error: "not_found" }); res.writeHead(200, { "Content-Type": o.mime, ...CAB }); return res.end(o.bytes); }
      if (req.method === "POST") { if (objetos.has(`${bucket}/${ruta}`) && req.headers["x-upsert"] === "false") return json(409, { error: "Duplicate" }); guardarObjeto(bucket, ruta, cuerpo, req.headers["content-type"]); return json(200, { Key: `${bucket}/${ruta}` }); }
    }
    // --- PostgREST: solo /rest/v1/rpc/<función pública>, como service_role ---
    if (p.startsWith("/rest/v1/rpc/")) { const r = rpcBase(p.slice(13), b ?? {}); return r.status === 204 ? (res.writeHead(204, CAB), res.end()) : json(r.status, r.cuerpo); }
    json(404, { message: "no simulado en la revisión local" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (admin, campo y acta); las demás responden 503 ----------
const servirTs = join(SEM, "servir_edges.ts");
writeFileSync(servirTs, `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-admin", "geoportal-campo", "geoportal-acta"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la revisión local (solo Administración y Formatos de campo)." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servirTs], { env: { ...process.env, SUPABASE_URL: BASE, SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (String(d).includes("edges listas")) ok(); }); edge.on("exit", () => mal(new Error("Deno terminó: " + edgeLog.slice(-600)))); setTimeout(() => mal(new Error("Deno no arrancó: " + edgeLog.slice(-600))), 60000); });

// ---------- 4. Páginas de la app ----------
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));

// ---------- 5. Siembra (R3): una revisión con 2 derivadas y PDF, y una instalación que atiende una ----------
const OP = "prueba.op.comercial@emdupar.gov.co";
const ahoraBog = (minAtras) => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(Date.now() - minAtras * 60e3)).replace(", ", "T");
function datosPara(tipo, extra) {
  const campos = JSON.parse(sqlq(`select coalesce(json_agg(json_build_object('codigo', c.codigo, 'tipo', c.tipo_dato, 'opciones', c.opciones, 'visible_si', c.visible_si) order by c.orden), '[]') from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = ${lit(tipo)} and c.activo and c.obligatorio`));
  const d = {};
  for (const c of campos) { if (c.visible_si) continue;
    d[c.codigo] = c.tipo === "texto" ? "Prueba de revisión" : c.tipo === "opcion" ? c.opciones[0].codigo : c.tipo === "opciones" ? [c.opciones[0].codigo] : c.tipo === "si_no" ? false : c.tipo === "dia_hora" ? ahoraBog(c.codigo.includes("final") ? 5 : 40) : 1; }
  return { ...d, ...extra };
}
const fotosDe = (tipo) => sqlq(`select string_agg(tf.codigo, ',' order by tf.orden) from campo.tipo_fotos tf join campo.tipos_reporte t on t.id = tf.tipo_id where t.codigo = ${lit(tipo)} and tf.activo and tf.obligatoria`).split(",");
const generaResultado = (tipo) => sqlq(`select genera_resultado from campo.tipos_reporte where codigo = ${lit(tipo)}`) === "t";
const cuerpoCrear = (reporte_id, tipo, fotos, datos) => ({ reporte_id, tipo, subtipo: null, descripcion: null, contrato: "123456", lat: 10.46, lon: -73.25, precision_m: 5, riesgo_inmediato: false, origen: "campo", fotos, datos,
  resultado: generaResultado(tipo) ? "efectivo" : null, causal: null, inicio_dispositivo: new Date(Date.now() - 40 * 60e3).toISOString() });
const puppeteer = createRequire(import.meta.url)(PUP);
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
try {
  const pg = await nav.newPage();
  await pg.goto(`${BASE}/siembra.html?u=${encodeURIComponent(OP)}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 });
  const ev = (f, ...a) => pg.evaluate(f, ...a);
  const rev = await ev((e) => window.__api.preparar("revision_previa", e), fotosDe("revision_previa"));
  await ev(async (id) => { const A = window.__api; await A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await A.firma() });
    await A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "usuario", estado: "firmo", nombre: "Usuario de prueba", imagen: await A.firma() }); }, rev.reporte_id);
  const c1 = await ev((c) => window.__api.apiFormatos.crear(c), cuerpoCrear(rev.reporte_id, "revision_previa", rev.fotos,
    datosPara("revision_previa", { firma_atendio: "atendio_firmo", atendio_nombre: "Usuario de prueba", da_lugar: ["cambio_medidor", "fuga_externa"], req_cambio_medidor: true })));
  await ev((id) => window.__api.apiDocumentos.pdfGenerar("campo", id), rev.reporte_id);
  const der = await ev(() => window.__api.apiDocumentos.derivadasAbiertas("123456", "tipo:instalacion_medidor"));
  const cm = der.derivadas.find((d) => d.actividad === "cambio_medidor");
  const inst = await ev((e) => window.__api.preparar("instalacion_medidor", e), fotosDe("instalacion_medidor"));
  await ev(async (id) => { const A = window.__api; await A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "operario", estado: "firmo", imagen: await A.firma() });
    await A.apiDocumentos.firmaGuardar("campo", { registro_id: id, rol: "usuario", estado: "nadie_atendio" }); }, inst.reporte_id);
  const c2 = await ev((c) => window.__api.apiFormatos.crear(c), cuerpoCrear(inst.reporte_id, "instalacion_medidor", inst.fotos, datosPara("instalacion_medidor", {})));
  if (cm) await ev((d, id) => window.__api.apiDocumentos.derivadaAtender(d, id), cm.id, inst.reporte_id);
  console.log(`Siembra (como ${OP}, por las Edges reales): revisión ${c1.consecutivo} (firmas, PDF, 2 derivadas) e instalación ${c2.consecutivo} (atiende «cambio de medidor»; «fuga afuera» queda pendiente)`);
} catch (e) { console.log("AVISO: la siembra falló; la revisión sigue, pero «Actas registradas» saldrá vacía:", String(e?.message ?? e).slice(0, 400), edgeLog.slice(-400)); }
await nav.close();

console.log(`
Revisión local lista (base ${DB} en 55442; Edges reales geoportal-admin, geoportal-campo y geoportal-acta; nada va a Supabase).
  Abra  http://127.0.0.1:${P_WEB}/   y entre con un correo prueba.*@emdupar.gov.co y cualquier clave. Ctrl+C para terminar.`);
const fin = () => { try { edge.kill(); } catch { /* ya terminó */ } process.exit(0); };
process.on("SIGINT", fin); process.on("SIGTERM", fin);
