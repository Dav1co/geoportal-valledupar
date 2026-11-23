// Servidor de REVISIÓN LOCAL del modo «Cartera» (Motor SCRR, corte 2; Code A, 22-nov; regla del encargo: revisión en local obligatoria antes de publicar). NUNCA toca Supabase:
//   la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado) → las Edges REALES geoportal-scrr, geoportal-admin, geoportal-campo y geoportal-acta en Deno
//   → un PostgREST mínimo en Node que llama las RPC REALES de la base local del Code A (clúster 55432) como service_role con 30 s y 8 s (topes de producción).
//   Base «scrr_rev»: copia de la plantilla «scrr_plantilla» (el doble con campo 261bed3c…) + la migración del paquete sql/scrr_corte2 + datos SINTÉTICOS (ningún dato real).
//   Siembra, POR LA EDGE REAL y como el Supervisor comercial: la cartera del día (5.000 contratos), los pagos (300) y las actividades (400, con suspensiones y cortes, para que
//   haya retorno), y refresca el mapa con el rol mínimo scrr_refresco (con una clave SOLO LOCAL). Noviembre trae su calendario; diciembre queda vacío (para «copiar del mes anterior»).
//   Cinco usuarios (cualquier clave): prueba.sup.comercial (Supervisor comercial, sin modos del geovisor) · prueba.op.comercial (operario) · prueba.gestor.cobro (gestor de cobro:
//   formularios de Comercial) · prueba.admin (administrador) · prueba.op.tecnico (solo Técnica).
// Uso:
//   node scripts/revision_cartera.mjs --servir <deno> <supabase/functions> <psql>       → deja todo corriendo en http://127.0.0.1:54991/ (Ctrl+C para terminar)
//   node scripts/revision_cartera.mjs --comprobar <deno> <supabase/functions> <psql>    → arma, siembra, comprueba lo que ve cada uno de los 5 usuarios y termina
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos del Code A: 54991 (páginas), 54992 (Auth y PostgREST), 54993 (Edges).
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/revision_cartera.mjs --servir|--comprobar <deno> <supabase/functions> <psql>";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const MODO = args[0];
if (MODO !== "--servir" && MODO !== "--comprobar") { console.error(MODO?.startsWith("-") ? `Opción desconocida: ${MODO}\n${USO}` : `Falta --servir o --comprobar.\n${USO}`); process.exit(2); }
for (const a of args.slice(1)) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
if (args.length !== 4) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [, DENO, FUNCIONES, PSQL] = args;
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const P_WEB = 54991, P_BASE = 54992, P_EDGE = 54993, BASE = `http://127.0.0.1:${P_BASE}`, EDGE = `http://127.0.0.1:${P_EDGE}/functions/v1`;
const DB = "scrr_rev";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const psqlIn = (sql, db = DB) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-d", db], { input: sql, env: PGENV, encoding: "utf8", maxBuffer: 256 << 20 }).trim();
const sqlq = (s) => psqlIn(s);
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const SUP = "prueba.sup.comercial@emdupar.gov.co";
const USUARIOS = [
  ["prueba.sup.comercial@emdupar.gov.co", "Supervisor comercial (dashboard_campo; sin modos del geovisor)", true],
  ["prueba.op.comercial@emdupar.gov.co", "Operario comercial", false],
  ["prueba.gestor.cobro@emdupar.gov.co", "Gestor de cobro (formularios de Comercial)", false],
  ["prueba.admin@emdupar.gov.co", "Administrador", true],
  ["prueba.op.tecnico@emdupar.gov.co", "Solo Técnica", false],
];

// ---------- 0. Base ----------
if (psqlIn("show port", "postgres") !== "55432") { console.error("No es el clúster del Code A (55432)"); process.exit(2); }
psqlIn(`drop database if exists ${DB}; drop database if exists scrr_chrome;`, "postgres");
psqlIn("drop role if exists scrr_refresco", "postgres");
psqlIn(`create database ${DB} template scrr_plantilla;`, "postgres");
execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-d", DB, "-f", join(raiz, "sql/scrr_corte2/migracion_scrr_corte2_editor.sql")], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
const CLAVE_LOCAL = "solo-local-revision-scrr";
sqlq(`alter role scrr_refresco login password '${CLAVE_LOCAL}'`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, creado_por, horario, dias, ver_campo, ver_acta)
      values ('prueba.gestor.cobro@emdupar.gov.co', 'Prueba gestor de cobro', 'consulta', true, 'prueba.admin@emdupar.gov.co', 'sin_restriccion', 'todos', true, false)`);
sqlq(`insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, saldo_pendiente, ciclo, periodo_carga)
      select (930000000000 + g)::text, 'VIEJO', 'SINTÉTICO VIEJO ' || g, 'CALLE VIEJA', 1, '01', '20261121' from generate_series(1, 5000) g; analyze public.cartera_suscripcion;
      insert into hechos.facturacion_sspd (periodo, contrato) select '202610', (930000000000 + g)::text from generate_series(1, 5000) g where g % 50 <> 0;`);

// ---------- 1. App, Auth simulado, PostgREST mínimo y Edges ----------
const DIST = mkdtempSync(join(tmpdir(), "rev_cartera_app_"));
const v = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: BASE, VITE_SUPABASE_ANON_KEY: "clave-de-revision", VITE_FUNCTIONS_URL: EDGE } });
if (v.status !== 0) { console.error("La app no compiló\n" + v.stdout + v.stderr); process.exit(2); }
const cuentas = new Set(sqlq("select string_agg(email, ',') from public.geoportal_lista_blanca").split(","));
const CAB = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer, x-upsert" };
const forma = new Map();
function rpcBase(fn, a) {
  if (!forma.has(fn)) forma.set(fn, sqlq(`select proretset::text || '|' || prorettype::regtype::text from pg_proc where proname = ${lit(fn)} and pronamespace = 'public'::regnamespace limit 1`) || null);
  const f = forma.get(fn); if (!f) return { status: 404, cuerpo: { code: "PGRST202", message: `no existe public.${fn}` } };
  const [conjunto, tipo] = f.split("|"), argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  const sel = conjunto === "true" ? `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.${fn}(${argumentos}) t` : tipo === "void" ? `select public.${fn}(${argumentos})` : `select to_jsonb(public.${fn}(${argumentos}))`;
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-d", DB], { input: `set role service_role; set statement_timeout = '30s'; set lock_timeout = '8s';\n${sel};\n`,
      env: PGENV, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], maxBuffer: 64 << 20 });
    return tipo === "void" && conjunto !== "true" ? { status: 204 } : { status: 200, cuerpo: JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: (t.match(/HINT:\s+(.*)/) || [])[1]?.trim() } };
  }
}
const usuario = (email) => ({ id: "u-" + email, email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} });
const sesion = (email) => ({ access_token: "tok-" + email, refresh_token: "r-" + email, token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: usuario(email) });
const base = http.createServer((req, res) => {
  const u = new URL(req.url, BASE), p = decodeURIComponent(u.pathname);
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", ...CAB }); res.end(o === undefined ? "" : JSON.stringify(o)); };
  if (req.method === "OPTIONS") { res.writeHead(204, CAB); return res.end(); }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    let b = null; try { b = JSON.parse(Buffer.concat(trozos).toString() || "null"); } catch { /* nada */ }
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (p === "/auth/v1/token") {
      const g = u.searchParams.get("grant_type");
      if (g === "password") { const email = String(b?.email ?? "").trim().toLowerCase(); return cuentas.has(email) ? json(200, sesion(email)) : json(400, { error: "invalid_grant", error_description: "Invalid login credentials" }); }
      if (g === "refresh_token") { const email = String(b?.refresh_token ?? "").replace(/^r-/, ""); return cuentas.has(email) ? json(200, sesion(email)) : json(400, { error: "invalid_grant" }); }
    }
    if (p === "/auth/v1/user") { const email = tok.replace(/^tok-/, ""); return cuentas.has(email) ? json(200, usuario(email)) : json(401, { msg: "invalid JWT" }); }
    if (p === "/auth/v1/logout") return json(204);
    if (p.startsWith("/rest/v1/rpc/")) { const r = rpcBase(p.slice(13), b ?? {}); return r.status === 204 ? (res.writeHead(204, CAB), res.end()) : json(r.status, r.cuerpo); }
    json(404, { message: "no simulado en la revisión local" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));
const SEM = mkdtempSync(join(tmpdir(), "rev_cartera_edges_"));
writeFileSync(join(SEM, "servir_edges.ts"), `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-scrr", "geoportal-admin", "geoportal-campo", "geoportal-acta"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la revisión local (solo Cartera, Administración y Formatos de campo)." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--node-modules-dir=none", "--allow-net", "--allow-env", "--allow-read", "--allow-sys", "--no-check", join(SEM, "servir_edges.ts")], { cwd: SEM,
  env: { ...process.env, SUPABASE_URL: BASE, SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1",
         SCRR_REFRESCO_DB_URL: `postgres://scrr_refresco:${CLAVE_LOCAL}@127.0.0.1:55432/${DB}` }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
await new Promise((a, m) => { edge.stdout.on("data", (d) => { if (String(d).includes("edges listas")) a(); }); edge.on("exit", () => m(new Error("Deno terminó: " + edgeLog.slice(-600)))); setTimeout(() => m(new Error("Deno no arrancó: " + edgeLog.slice(-600))), 90000); });
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));
const llamar = async (email, accion, cuerpo, qs = "") => {
  const r = await fetch(`${EDGE}/geoportal-scrr?accion=${accion}${qs}`, { method: cuerpo ? "POST" : "GET", headers: { Authorization: `Bearer tok-${email}`, "Content-Type": "application/json" }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  return { status: r.status, cuerpo: await r.json().catch(() => null) };
};

// ---------- 2. Siembra por la Edge real, como el Supervisor comercial (el mismo lector de Excel del navegador, en Node) ----------
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const T = mkdtempSync(join(tmpdir(), "rev_cartera_lector_"));
await build({ entryPoints: [join(raiz, "src/scrr/lector.worker.ts")], bundle: true, format: "esm", platform: "node", outfile: join(T, "w.mjs"), logLevel: "error" });
await build({ entryPoints: [join(raiz, "src/scrr/lector.ts")], bundle: true, format: "esm", platform: "node", outfile: join(T, "l.mjs"), logLevel: "error" });
const W = await import(pathToFileURL(join(T, "w.mjs")).href), L = await import(pathToFileURL(join(T, "l.mjs")).href);
const hoy = new Date(Date.now() - 5 * 3600e3).toISOString().slice(0, 10), ayer = new Date(Date.now() - 29 * 3600e3).toISOString().slice(0, 10);
async function cargar(tipo, filas, fecha) {
  const f = join(T, `${tipo}.xlsx`);
  execFileSync(process.execPath, [join(raiz, "scripts/scrr_generar_xlsx.mjs"), tipo, String(filas), f]);
  const bytes = new Uint8Array(readFileSync(f)); const r = await W.leerArchivo(bytes, tipo, "99999999", 250000); const sha = await L.sha256Hex(bytes);
  const ini = (await llamar(SUP, "carga_iniciar", { tipo, fecha_dato: fecha, nombre: `${tipo}_sintetico.xlsx`, sha256: sha, filas: r.resumen.filas })).cuerpo;
  for (let n = 1; n <= ini.lotes; n++) await llamar(SUP, "carga_lote", { carga_id: ini.carga_id, tipo, lote: n, filas: r.acumulador.filas.slice((n - 1) * ini.lote_filas, n * ini.lote_filas).map((x) => L.filaComoObjeto(tipo, x)) });
  await llamar(SUP, "carga_validar", { carga_id: ini.carga_id });
  for (let n = 1; n <= ini.lotes; n++) await llamar(SUP, "carga_aplicar", { carga_id: ini.carga_id, lote: n });
  const c = await llamar(SUP, "carga_aplicar", { carga_id: ini.carga_id });
  if (c.status !== 200) throw new Error(`No se pudo sembrar ${tipo}: ${JSON.stringify(c)}`);
  return ini.carga_id;
}
const cCartera = await cargar("cartera", 5000, hoy);
await cargar("pagos", 300, ayer);
await cargar("actividades", 400, ayer);
const mapa = await llamar(SUP, "refrescar_mapa", { carga_id: cCartera });
console.log(`Siembra: cartera 5.000 · pagos 300 · actividades 400 · mapa ${mapa.status === 200 ? "refrescado" : "NO refrescado " + JSON.stringify(mapa.cuerpo)} · retorno ${(await llamar(SUP, "retorno")).cuerpo?.pendientes ?? "?"} pendientes`);

// ---------- 3. Comprobar o servir ----------
if (MODO === "--comprobar") {
  let ok = 0, tot = 0; const fallas = [];
  const prueba = (n, c, d = "") => { tot++; if (c) { ok++; console.log("OK   ", n); } else { fallas.push(n); console.log("FALLA", n, String(d).slice(0, 300)); } };
  for (const [email, papel, entra] of USUARIOS) {
    const r = await llamar(email, "contexto");
    prueba(`${papel}: ${entra ? "entra" : "no entra (403)"} al modo Cartera`, entra ? r.status === 200 : r.status === 403, JSON.stringify(r));
  }
  prueba("la cartera sembrada quedó vigente y el mapa se refrescó", sqlq("select count(*) from scrr.v_cartera_vigente") !== "0" && mapa.status === 200, JSON.stringify(mapa));
  prueba("la selección del ciclo 15 tiene candidatos y el retorno tiene pendientes",
    Number((await llamar(SUP, "seleccion_previa", { ciclo: 15, filtros: { modo: "meses", desde: 1, hasta: 25 } })).cuerpo?.candidatos ?? 0) > 0
    && Number((await llamar(SUP, "retorno")).cuerpo?.pendientes ?? 0) > 0);
  const pagina = await fetch(`http://127.0.0.1:${P_WEB}/`);
  prueba("la app compilada responde", pagina.status === 200 && /<div id="root">/.test(await pagina.text()));
  console.log(`\nRESULTADO: ${ok} de ${tot} comprobaciones correctas — ${fallas.length ? "FALLAS: " + fallas.join(" | ") : "SIN FALLAS"}`);
  edge.kill(); base.close(); web.close(); psqlIn(`drop database ${DB}`, "postgres"); psqlIn("drop role if exists scrr_refresco", "postgres");
  process.exit(fallas.length ? 1 : 0);
}
console.log(`
Revisión local del modo «Cartera» lista (base ${DB} en 55432; Edges reales geoportal-scrr, geoportal-admin, geoportal-campo y geoportal-acta; nada va a Supabase).
  Abra  http://127.0.0.1:${P_WEB}/  y entre con cualquiera de estos correos y cualquier clave:
${USUARIOS.map(([e, p]) => `    ${e.split("@")[0].padEnd(24)} ${p}`).join("\n")}
  Casos para revisar: ~/geoportal-consultas/campo/paquete_scrr_1/corte2_commit3/CASOS_REVISION.md   ·   Ctrl+C para terminar.`);
const fin = () => { try { edge.kill(); } catch { /* ya terminó */ } process.exit(0); };
process.on("SIGINT", fin); process.on("SIGTERM", fin);
