// [Code B] Servidor de REVISIÓN LOCAL de «Investigación de ubicación recortada y avisos del Análisis de contrato» (23-nov; regla del encargo: revisión en local
// obligatoria antes de publicar). NUNCA toca Supabase:
//   la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado) → las Edges REALES geoportal-admin, geoportal-campo y geoportal-acta en Deno
//   (de ~/geoportal-web-inv-analisis, rama campo-inv-analisis) → un PostgREST mínimo en Node que llama las RPC REALES de la base local del Code B (clúster 55442)
//   como service_role con statement_timeout 30 s y lock_timeout 8 s (los topes de producción).
//   Base emdupar_b_inv_rev: se rehace en cada arranque como COPIA EXACTA DE PRODUCCIÓN (rehacer_doble.py con produccion_doble.csv, 163 de 163) + la migración del
//   paquete sql/campo_inv_analisis + 5 usuarios de prueba (ningún dato real). Lo que se haga en la revisión se pierde al reiniciar.
//   Usuarios (cualquier clave): prueba.inv.analista (solo Análisis de contrato) · prueba.inv.sup.campo (supervisor de campo) · prueba.inv.operario (reporta en campo)
//   · prueba.inv.sup.actas (supervisor de actas) · prueba.inv.admin (administrador). Casos en ~/geoportal-consultas/campo/paquete_inv_analisis_1/CASOS_REVISION.md.
//   Storage en memoria (fotos). Las demás Edges (mapa, Técnica, Aseo, tablero) NO están: esas áreas muestran su aviso de error, a propósito.
// Uso:
//   node scripts/revision_inv_analisis.mjs --servir <chrome> <puppeteer-core> <deno> <supabase/functions>     → deja todo en http://127.0.0.1:55995/ (Ctrl+C para terminar)
//   node scripts/revision_inv_analisis.mjs --comprobar <chrome> <puppeteer-core> <deno> <supabase/functions>  → arma todo, comprueba que cada usuario entra y ve lo suyo, y termina
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos del Code B: 55995 (páginas), 55996 (Auth, Storage y PostgREST), 55997 (Edges).
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/revision_inv_analisis.mjs --servir|--comprobar <chrome> <puppeteer-core> <deno> <supabase/functions>";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const MODO = args[0];
if (MODO !== "--servir" && MODO !== "--comprobar") { console.error(`Falta --servir o --comprobar.\n${USO}`); process.exit(2); }
for (const a of args.slice(1)) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
if (args.length !== 5) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [, CHROME, PUP, DENO, FUNCIONES] = args;
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const P_WEB = 55995, P_BASE = 55996, P_EDGE = 55997;
const BASE = `http://127.0.0.1:${P_BASE}`;
const DB = "emdupar_b_inv_rev";
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55442", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 << 20 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const D = "@emdupar.gov.co";
const U = { analista: "prueba.inv.analista", supCampo: "prueba.inv.sup.campo", operario: "prueba.inv.operario", supActas: "prueba.inv.sup.actas", admin: "prueba.inv.admin" };

// ---------- 0. La base: copia exacta de producción + la migración del paquete + 5 usuarios de prueba ----------
const PAQ = join(raiz, "sql/campo_inv_analisis");
const rd = spawnSync("python3", ["-I", "-B", join(PAQ, "pruebas_locales/rehacer_doble.py"), "--csv", join(homedir(), "geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv"), "--db", DB], { encoding: "utf8", env: { ...process.env, PGPORT_B: "55442" } });
if (rd.status !== 0 || !/SIN DIFERENCIAS/.test(rd.stdout)) { console.error("El doble no quedó igual a producción:\n" + rd.stdout + rd.stderr); process.exit(2); }
execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-f", join(PAQ, "migracion_campo_inv_analisis_editor.sql")], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
const fila = (u, nombre, rol, ver) => `('${u}${D}', '${nombre}', '${rol}', true, 'prueba.inv.admin${D}', 'sin_restriccion', 'todos', false, ${["ver_campo", "ver_dashboard_campo", "ver_acta", "ver_dashboard_acta", "ver_analisis_contrato"].map((c) => String(ver.includes(c))).join(", ")})`;
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, creado_por, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_analisis_contrato) values
  ${fila(U.analista, "Prueba analista de contratos", "consulta", ["ver_analisis_contrato"])},
  ${fila(U.supCampo, "Prueba supervisor de campo", "consulta", ["ver_campo", "ver_dashboard_campo"])},
  ${fila(U.operario, "Prueba operario de campo", "consulta", ["ver_campo"])},
  ${fila(U.supActas, "Prueba supervisor de actas", "consulta", ["ver_acta", "ver_dashboard_acta"])},
  ${fila(U.admin, "Prueba administrador", "admin", [])}`);
// Sección 7 (vigencia): dos avisos de PRUEBA fechados hacia atrás en el contrato 123456, para revisar la vigencia sin esperar días:
// «Desocupado» de hace 15 días (vigente: marcarlo da «Ya se avisó el …») y «Otra» de hace 25 días (vencido: marcarlo crea un aviso nuevo; el viejo sigue pendiente).
for (const [tipo, dias, texto] of [["desocupado", 15, null], ["otra", 25, "[PRUEBA] aviso viejo de hace 25 días"]]) {
  sqlq(`with o as (insert into campo.analisis_observaciones (contrato, tipo, texto, autor, creado_en) values ('123456', '${tipo}', ${lit(texto)}, '${U.analista}${D}', clock_timestamp() - interval '${dias} days') returning id, creado_en)
        insert into campo.derivadas (observacion_id, contrato, actividad, creado_en) select id, '123456', 'aviso_${tipo}', creado_en from o`);
}
const HUELLA = sqlq("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')");

// ---------- 1. La app completa (Vite), apuntando a los servidores locales ----------
const DIST = mkdtempSync(join(tmpdir(), "rev_inv_app_"));
const v = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: BASE, VITE_SUPABASE_ANON_KEY: "clave-de-revision", VITE_FUNCTIONS_URL: `http://127.0.0.1:${P_EDGE}/functions/v1` } });
if (v.status !== 0) { console.error("La app no compiló\n" + v.stdout + v.stderr); process.exit(2); }

// ---------- 2. Auth simulado, Storage en memoria y PostgREST mínimo (RPC reales, como service_role) ----------
const cuentasAuth = new Set(sqlq("select string_agg(email, ',') from public.geoportal_lista_blanca").split(","));
const objetos = new Map(), forma = new Map(), registro = [];
const CAB = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer, x-upsert" };
function formaDe(fn) {
  if (!forma.has(fn)) { const r = /^[a-z_][a-z0-9_]{1,62}$/.test(fn) ? sqlq(`select proretset::text || '|' || prorettype::regtype::text from pg_proc where proname = ${lit(fn)} and pronamespace = 'public'::regnamespace limit 1`) : ""; forma.set(fn, r || null); }
  return forma.get(fn);
}
function rpcBase(fn, a) {
  const f = formaDe(fn); if (!f) return { status: 404, cuerpo: { code: "PGRST202", message: `no existe public.${fn}` } };
  for (const k of Object.keys(a)) if (!/^[a-z_][a-z0-9_]{1,62}$/.test(k)) return { status: 400, cuerpo: { code: "PGRST", message: "parámetro" } };
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
    console.log(`   RPC ${fn} → ${((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || t).slice(0, 160)}`);
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: (t.match(/HINT:\s+(\S+)/) || [])[1] } };
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
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos); let b = null; try { b = JSON.parse(cuerpo.toString() || "null"); } catch { /* binario */ }
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (p === "/auth/v1/token") {
      const g = u.searchParams.get("grant_type");
      if (g === "password") { const email = String(b?.email ?? "").trim().toLowerCase(); return cuentasAuth.has(email) ? json(200, sesion(email)) : json(400, { error: "invalid_grant", error_description: "Invalid login credentials" }); }
      if (g === "refresh_token") { const email = String(b?.refresh_token ?? "").replace(/^r-/, ""); return cuentasAuth.has(email) ? json(200, sesion(email)) : json(400, { error: "invalid_grant" }); }
    }
    if (p === "/auth/v1/user") { const email = tok.replace(/^tok-/, ""); return cuentasAuth.has(email) ? json(200, usuario(email)) : json(401, { msg: "invalid JWT" }); }
    if (p === "/auth/v1/logout") return json(204);
    let m;
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
    if (p.startsWith("/rest/v1/rpc/")) { const r = rpcBase(p.slice(13), b ?? {}); return r.status === 204 ? (res.writeHead(204, CAB), res.end()) : json(r.status, r.cuerpo); }
    json(404, { message: "no simulado en la revisión local" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (admin, campo y acta); las demás responden 503 ----------
const SEM = mkdtempSync(join(tmpdir(), "rev_inv_edges_"));
const servirTs = join(SEM, "servir_edges.ts");
writeFileSync(servirTs, `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-admin", "geoportal-campo", "geoportal-acta"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la revisión local (solo Administración, Formatos de campo y actas)." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servirTs], { env: { ...process.env, SUPABASE_URL: BASE, SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
const fin = () => { try { edge.kill(); } catch { /* ya terminó */ } process.exit(0); };
process.on("SIGINT", fin); process.on("SIGTERM", fin);
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (String(d).includes("edges listas")) ok(); }); edge.on("exit", () => mal(new Error("Deno terminó: " + edgeLog.slice(-600)))); setTimeout(() => mal(new Error("Deno no arrancó: " + edgeLog.slice(-600))), 60000); });

// ---------- 4. Páginas de la app ----------
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));

const contratos = sqlq("select string_agg(c, ', ') from (select distinct s.contrato as c from public.cartera_suscripcion s where s.contrato ~ '^[0-9]{4,12}$' and s.contrato <> '99999999' order by 1 limit 3) x");
const resumen = `Revisión local lista: base ${DB} (copia exacta de producción + el paquete; huella de campo ${HUELLA.slice(0, 8)}…) en 55442; Edges reales geoportal-admin, geoportal-campo y geoportal-acta. Nada va a Supabase.
  Abra  http://127.0.0.1:${P_WEB}/   y entre con cualquiera de estos correos y cualquier clave:
    ${Object.values(U).map((x) => x + D).join("\n    ")}
  Contratos que existen en la copia (para el Análisis): 123456${contratos ? ", " + contratos : ""}. Comodín: 99999999.`;

if (MODO === "--servir") {
  console.log("\n" + resumen + "\n  Ctrl+C para terminar.");
} else {
  // --comprobar: cada usuario entra por la pantalla de ingreso real y ve (o no) lo suyo
  const puppeteer = createRequire(import.meta.url)(PUP);
  const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
  let total = 0, fallas = 0; const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + String(d).replace(/\s+/g, " ").slice(0, 400)}`); };
  async function entrar(u) {
    const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage(); await pg.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    await pg.goto(`http://127.0.0.1:${P_WEB}/`); await pg.waitForSelector("input[type=password]", { timeout: 20000 });
    const [usr] = await pg.$$("input:not([type=password])"); await usr.type(u); await pg.type("input[type=password]", "cualquiera"); await pg.keyboard.press("Enter");
    await pg.waitForFunction(() => !document.querySelector("input[type=password]"), { timeout: 20000 }).catch(() => {});
    await new Promise((r) => setTimeout(r, 1500));
    return { pg, ctx, texto: await pg.evaluate(() => document.body.innerText) };
  }
  const tieneBoton = (pg, t) => pg.evaluate((x) => [...document.querySelectorAll("button, a")].some((b) => b.textContent.includes(x)), t);
  for (const [clave, u] of Object.entries(U)) {
    const { pg, ctx, texto } = await entrar(u);
    ok(`${u}: entra con cualquier clave`, !/Invalid login|no autorizado/i.test(texto) && texto.length > 20, texto);
    if (clave === "analista") ok(`${u}: ve «Análisis de contrato»`, await tieneBoton(pg, "Análisis de contrato"), texto);
    if (clave === "operario" || clave === "supCampo" || clave === "admin") ok(`${u}: ve «Formatos de campo»`, /Formatos de campo|Formularios de campo|Formato/.test(texto), texto);
    await ctx.close();
  }
  // Por las Edges reales: lo esencial del paquete está en esta base
  const edgeLlama = async (u, accion, cuerpo, metodo = "POST") => { const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-campo?accion=${accion}`, { method: metodo, headers: { authorization: `Bearer tok-${u}${D}`, "content-type": "application/json" }, body: metodo === "POST" ? JSON.stringify(cuerpo ?? {}) : undefined }); return { s: r.status, j: await r.json().catch(() => null) }; };
  let r = await edgeLlama(U.operario, "formulario", null, "GET");
  const inv = r.j?.grupos?.flatMap((g) => g.tipos).find((t) => t.codigo === "investigacion_ubicacion");
  ok("la Investigación llega con 0 a 6 fotos y sin resultado", r.s === 200 && inv?.fotos_min === 0 && inv?.genera_resultado === false, JSON.stringify(inv)?.slice(0, 200));
  r = await edgeLlama(U.supCampo, "derivadas", { origen: "analisis" });
  ok("el supervisor de campo abre la lista con Origen = Análisis de contrato: los 2 avisos sembrados (hace 15 y 25 días)", r.s === 200 && Array.isArray(r.j?.filas)
    && r.j.filas.map((f) => f.antiguedad_dias).sort((a, b) => a - b).join(",") === "15,25", JSON.stringify(r).slice(0, 300));
  r = await edgeLlama(U.analista, "analisis_observar", { contrato: "123456", tipo: "desocupado" });
  ok("el analista no marca sin consultar antes el contrato (409)", r.s === 409, JSON.stringify(r));
  await nav.close(); edge.kill(); base.close(); web.close();
  console.log(`\n${resumen}\n\nRESULTADO: ${total - fallas} de ${total} comprobaciones correctas${fallas ? "" : " — SIN FALLAS"}`);
  process.exit(fallas ? 1 : 0);
}
