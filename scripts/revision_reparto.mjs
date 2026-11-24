// Servidor de REVISIÓN LOCAL del Reparto de facturas (Code A, 24-nov; regla del encargo: revisión en local obligatoria antes de publicar). NUNCA toca Supabase:
//   la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado) → las Edges REALES geoportal-reparto, geoportal-scrr (el calendario de Cartera),
//   geoportal-campo y geoportal-admin en Deno → un PostgREST mínimo en Node que llama las RPC REALES de una base local del Code A (clúster 55432) como service_role
//   con 30 s y 8 s (topes de producción).
//   Base «reparto_rev»: doble de campo (261bed3c…) + dobles del SCRR + la migración REAL del SCRR (calendario y geoportal-scrr) + dobles de rutas + el paquete
//   sql/reparto_1 + datos SINTÉTICOS (contratos 88…, ciclos 97 y 98; ningún dato real). Siembra, POR LA EDGE REAL: un archivo de ruta del supervisor y 6 entregas en
//   desorden de un repartidor (con XY repartidos por Valledupar y una anulada), para que el avance, el detalle y el mapa tengan qué mostrar.
//   La migración del SCRR crea el rol scrr_refresco (del clúster). Este guion no borra lo que no creó: si ya existen reparto_rev o ese rol, se niega.
//   Al terminar (--comprobar, o Ctrl+C en --servir) borra SOLO su base y el rol que creó.
// Uso:
//   node scripts/revision_reparto.mjs --servir <deno> <supabase/functions> <psql>       → deja todo corriendo en http://127.0.0.1:55006/ (Ctrl+C para terminar)
//   node scripts/revision_reparto.mjs --comprobar <deno> <supabase/functions> <psql>    → arma, siembra, comprueba lo que ve cada usuario y termina
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos del Code A: 55006 (páginas), 55007 (Auth y PostgREST), 55008 (Edges).
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import http from "node:http";

const USO = "Uso: node scripts/revision_reparto.mjs --servir|--comprobar <deno> <supabase/functions> <psql>";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const MODO = args[0];
if (MODO !== "--servir" && MODO !== "--comprobar") { console.error(MODO?.startsWith("-") ? `Opción desconocida: ${MODO}\n${USO}` : `Falta --servir o --comprobar.\n${USO}`); process.exit(2); }
for (const a of args.slice(1)) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
if (args.length !== 4) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [, DENO, FUNCIONES, PSQL] = args;
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, ".."), H = homedir();
const P_WEB = 55006, P_BASE = 55007, P_EDGE = 55008, BASE = `http://127.0.0.1:${P_BASE}`, EDGE = `http://127.0.0.1:${P_EDGE}/functions/v1`;
const DB = "reparto_rev";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
for (const k of ["SUPABASE_RO_URL", "DATABASE_URL", "PGPASSWORD", "PGSERVICE"]) delete PGENV[k];
const psqlIn = (sql, db = DB) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-d", db], { input: sql, env: PGENV, encoding: "utf8", maxBuffer: 256 << 20 }).trim();
const sqlq = (s) => psqlIn(s);
const archivoSql = (f) => execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-d", DB, "-f", f], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const U = { uno: "prueba.reparto.uno@emdupar.gov.co", dos: "prueba.reparto.dos@emdupar.gov.co", sup: "prueba.reparto.sup@emdupar.gov.co",
            supcal: "prueba.sup.comercial@emdupar.gov.co", op: "prueba.op.comercial@emdupar.gov.co", adm: "prueba.admin@emdupar.gov.co" };
const USUARIOS = [
  [U.uno, "Repartidor (actividad «Reparto»)", { rep: true, sup: false }],
  [U.dos, "Repartidor con entregas sembradas (actividad «Reparto»)", { rep: true, sup: false }],
  [U.sup, "Supervisor de reparto (actividad «Supervisión de reparto»; sin dashboard_campo)", { rep: false, sup: true }],
  [U.supcal, "Supervisor comercial con «Supervisión de reparto» (ve «Cambiar en Calendario»)", { rep: false, sup: true }],
  [U.op, "Operario de campo sin las actividades (no ve el reparto)", { rep: false, sup: false }],
  [U.adm, "Administrador (las dos pantallas)", { rep: true, sup: true }],
];

// ---------- 0. Base ----------
if (psqlIn("show port", "postgres") !== "55432") { console.error("No es el clúster del Code A (55432)"); process.exit(2); }
for (const puerto of [P_WEB, P_BASE, P_EDGE]) {
  const libre = await new Promise((r) => { const s = http.createServer(); s.once("error", () => r(false)); s.listen(puerto, "127.0.0.1", () => s.close(() => r(true))); });
  if (!libre) { console.error(`El puerto ${puerto} está ocupado: ya hay un servidor de revisión corriendo. Deténgalo (Ctrl+C en su terminal) antes de arrancar otro; no se tocó la base.`); process.exit(2); }
}
{ const resto = psqlIn(`select count(*) from pg_database where datname = '${DB}'`, "postgres") !== "0";
  const rol = psqlIn("select count(*) from pg_roles where rolname = 'scrr_refresco'", "postgres") !== "0";
  if (resto || rol) { console.error(`Quedaron restos de otra corrida (base ${DB}: ${resto ? "sí" : "no"}; rol scrr_refresco: ${rol ? "sí" : "no"}). Este guion no los borra: pida permiso y bórrelos a mano.`); process.exit(2); } }
// Producción de HOY (24-nov): el doble con el catálogo de producción del Code B (rehacer_doble.py, 163 de 163 iguales) + su migración publicada
if (psqlIn("select count(*) from pg_database where datname = 'emdupar_b_inv_para_reparto'", "postgres") === "0") {
  console.error("Falta la base emdupar_b_inv_para_reparto: PGPORT_B=55432 python3 -I sql/campo_inv_analisis/pruebas_locales/rehacer_doble.py --csv ~/geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv --db emdupar_b_inv_para_reparto"); process.exit(2);
}
psqlIn(`create database ${DB} template emdupar_b_inv_para_reparto`, "postgres");
let rolCreado = false, limpio = false;
const limpiarLoCreado = () => {
  if (limpio) return; limpio = true;
  try { psqlIn(`drop database if exists ${DB} with (force)`, "postgres"); } catch (e) { console.error("No se pudo borrar la base:", String(e.message).slice(0, 200)); }
  if (rolCreado) try { psqlIn("drop role if exists scrr_refresco", "postgres"); } catch (e) { console.error("No se pudo quitar el rol:", String(e.message).slice(0, 200)); }
};
process.on("exit", limpiarLoCreado);
process.on("uncaughtException", (e) => { console.error("Error: " + String(e?.stack ?? e).slice(0, 800)); process.exit(1); });
process.on("unhandledRejection", (e) => { console.error("Error: " + String(e?.stack ?? e).slice(0, 800)); process.exit(1); });
archivoSql(join(H, "geoportal-emdupar/sql/scrr_corte2/pruebas_locales/doble_base_local.sql"));
rolCreado = true;
archivoSql(join(H, "geoportal-emdupar/sql/scrr_corte2/migracion_scrr_corte2_editor.sql"));
archivoSql(join(raiz, "sql/campo_inv_analisis/migracion_campo_inv_analisis_editor.sql"));   // el paquete de B, publicado DESPUÉS del SCRR (como en producción)
archivoSql(join(raiz, "sql/reparto_1/pruebas_locales/doble_rutas_local.sql"));
psqlIn("do $$ begin if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then create role homelab_lectura nologin; end if; end $$;");
archivoSql(join(raiz, "sql/reparto_1/migracion_reparto_1_editor.sql"));
// Personas (cualquier clave). ver_explorar vale verdadero por omisión: estas solo tienen Formatos de campo.
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo) values
  ('${U.uno}', 'Prueba Repartidor uno', 'consulta', true, 'sin_restriccion', 'todos', false, true), ('${U.dos}', 'Prueba Repartidor dos', 'consulta', true, 'sin_restriccion', 'todos', false, true),
  ('${U.sup}', 'Prueba Supervisor de reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true);
  update public.geoportal_lista_blanca set horario = 'sin_restriccion' where email in ('${U.supcal}', '${U.op}', '${U.adm}');`);
sqlq(`insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values ('${U.uno}', 'asignar_actividad', 'reparto', '${U.adm}'), ('${U.dos}', 'asignar_actividad', 'reparto', '${U.adm}'),
  ('${U.sup}', 'asignar_actividad', 'supervision_reparto', '${U.adm}'), ('${U.supcal}', 'asignar_actividad', 'supervision_reparto', '${U.adm}')`);
// Rutas sintéticas del período 202610: ciclo 98 (rutas 880101 de 40 y 880102 de 15; con fecha de reparto ayer) y ciclo 97 (ruta 970101 de 5; SIN fecha: respaldo).
sqlq(`insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo)
        select '98', (g * 1000000)::text, '880101', (880000000100 + g)::text, 'CALLE SINTÉTICA', g::text, '202610' from generate_series(1, 40) g
  union all select '98', (g * 1000000)::text, '880102', (880000000200 + g)::text, 'CALLE SINTÉTICA', g::text, '202610' from generate_series(1, 15) g
  union all select '97', (g * 1000000)::text, '970101', (880000000500 + g)::text, 'CALLE SINTÉTICA', g::text, '202610' from generate_series(1, 5) g;
  insert into public.cartera_suscripcion (contrato, estado, ciclo, periodo_carga) values ('880000000301', 'ACTIVO', '98', '20261124'), ('880000000302', 'ACTIVO', '9999', '20261124');
  insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor)
    select to_char(h, 'YYYYMM'), 98, h + 10, h + 15, jsonb_build_object('reparto', (h - 1)::text), '${U.adm}' from (select (now() at time zone 'America/Bogota')::date as h) x;
  analyze hechos.rutas_consecutivos;`);

// ---------- 1. App, Auth simulado, PostgREST mínimo y Edges ----------
const DIST = mkdtempSync(join(tmpdir(), "rev_reparto_app_"));
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
    if (p.startsWith("/rest/v1/rpc/")) { const fn = p.slice(13); if (fn === "geoportal_log") return json(200, null); const r = rpcBase(fn, b ?? {}); return r.status === 204 ? (res.writeHead(204, CAB), res.end()) : json(r.status, r.cuerpo); }
    json(404, { message: "no simulado en la revisión local" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));
const SEM = mkdtempSync(join(tmpdir(), "rev_reparto_edges_"));
writeFileSync(join(SEM, "servir_edges.ts"), `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-reparto", "geoportal-scrr", "geoportal-admin", "geoportal-campo"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la revisión local (solo Reparto, Cartera, Administración y Formatos de campo)." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--node-modules-dir=none", "--allow-net", "--allow-env", "--allow-read", "--allow-sys", "--no-check", join(SEM, "servir_edges.ts")], { cwd: SEM,
  env: { ...process.env, SUPABASE_URL: BASE, SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* */ } });
await new Promise((a, m) => { edge.stdout.on("data", (d) => { if (String(d).includes("edges listas")) a(); }); edge.on("exit", () => m(new Error("Deno terminó: " + edgeLog.slice(-600)))); setTimeout(() => m(new Error("Deno no arrancó: " + edgeLog.slice(-600))), 90000); });
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));
const llamar = async (email, accion, cuerpo, qs = "") => {
  const r = await fetch(`${EDGE}/geoportal-reparto?accion=${accion}${qs}`, { method: cuerpo ? "POST" : "GET", headers: { Authorization: `Bearer tok-${email}`, "Content-Type": "application/json" }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  return { status: r.status, cuerpo: await r.json().catch(() => null) };
};

// ---------- 2. Siembra por la Edge real ----------
// a) el supervisor de reparto carga un archivo de rutas (la estructura del de facturación; la dirección no viaja): ciclo 98 «ZT-ARCHIVO» (8 contratos de la ruta 880101
//    en otro orden) y ciclo 97 «ZT-ARCHIVO-97» (2 contratos; el 880000000140 es del 98 en las rutas: queda el aviso de otro ciclo)
const lote = await llamar(U.sup, "lote_cargar", { nombre: "rutas_noviembre.xlsx", sha256: "b".repeat(64), filas: [
  ...[133, 131, 135, 132, 134, 136, 138, 137].map((n, i) => ({ contrato: String(880000000000 + n), ciclo: "98", ruta: "ZT-ARCHIVO", consecutivo_ruta: String((i + 1) * 1000000), consecutivo_predio: String(i + 1) })),
  { contrato: "880000000503", ciclo: "97", ruta: "ZT-ARCHIVO-97", consecutivo_ruta: "1000000" }, { contrato: "880000000140", ciclo: "97", ruta: "ZT-ARCHIVO-97", consecutivo_ruta: "2000000" }] });
// b) el repartidor dos reparte la ruta 880102 en desorden (1, 4, 2, 6, 3 con el buscador, 9) y anula una; XY repartidos por el centro de Valledupar
const emp = await llamar(U.dos, "empezar", { origen: "anterior", ciclo: "98", ruta: "880102" });
const jdos = emp.cuerpo?.jornada?.id;
const orden = [1, 4, 2, 6, 3, 9], ids = [];
for (const [i, n] of orden.entries()) {
  const r = await llamar(U.dos, "entregar", { jornada_id: jdos, contrato: String(880000000200 + n), lon: Number((-73.2532 + i * 0.0011).toFixed(6)), lat: Number((10.4631 + (i % 3) * 0.0009).toFixed(6)),
    precision_m: i === 3 ? 42 : 6 + i, por_buscador: n === 3, id_cliente: randomUUID() });
  ids.push(r.cuerpo?.entrega_id);
}
await llamar(U.dos, "anular", { entrega_id: ids[3], motivo: "Revisión: toqué la que no era" });
console.log(`Siembra: archivo de rutas ${lote.cuerpo?.ok ? "cargado (10 facturas, 2 rutas, 1 de otro ciclo)" : "NO cargado " + JSON.stringify(lote.cuerpo)} · ${ids.filter(Boolean).length} entregas del repartidor dos (una anulada)`);

// ---------- 3. Comprobar o servir ----------
if (MODO === "--comprobar") {
  let ok = 0, tot = 0; const fallas = [];
  const prueba = (n, c, d = "") => { tot++; if (c) { ok++; console.log("OK   ", n); } else { fallas.push(n); console.log("FALLA", n, String(d).slice(0, 300)); } };
  for (const [email, papel, esp] of USUARIOS) {
    const r = await llamar(email, "perfil");
    prueba(`${papel}: ${esp.rep ? "repartidor" : "—"} / ${esp.sup ? "supervisor" : "—"}`, r.status === 200 && r.cuerpo.es_repartidor === esp.rep && r.cuerpo.es_supervisor === esp.sup, JSON.stringify(r));
  }
  prueba("la siembra: el archivo de rutas (2 rutas, 1 de otro ciclo) y 6 entregas (1 anulada)", lote.cuerpo?.ok === true && lote.cuerpo?.rutas?.length === 2 && lote.cuerpo?.otro_ciclo === 1 && sqlq("select count(*) || '|' || count(a.entrega_id) from reparto.entregas e left join reparto.entregas_anuladas a on a.entrega_id = e.id") === "6|1");
  const av = await llamar(U.sup, "avance");
  prueba("el avance del supervisor muestra la jornada sembrada con su período de reparto", av.cuerpo?.filas?.some((f) => f.jornada_id === jdos && f.entregadas === 5 && f.anuladas === 1 && /^\d{6}$/.test(f.periodo_reparto ?? "")), JSON.stringify(av.cuerpo));
  const ctx = await llamar(U.uno, "contexto");
  prueba("el repartidor ve el ciclo 98 (con fecha), el 97 (sin fecha) y el archivo nuevo", ctx.cuerpo?.anterior?.some((c) => c.ciclo === "98" && c.reparto) && ctx.cuerpo?.anterior?.some((c) => c.ciclo === "97" && !c.reparto)
    && ctx.cuerpo?.nuevas?.some((l) => l.ruta === "ZT-ARCHIVO" && l.ciclo === "98") && ctx.cuerpo?.nuevas?.some((l) => l.ruta === "ZT-ARCHIVO-97" && l.ciclo === "97"), JSON.stringify(ctx.cuerpo).slice(0, 400));
  prueba("el calendario: con enlace para prueba.sup.comercial (dashboard_campo), sin enlace para prueba.reparto.sup",
    (await llamar(U.supcal, "calendario")).cuerpo?.puede_cambiar === true && (await llamar(U.sup, "calendario")).cuerpo?.puede_cambiar === false);
  const pagina = await fetch(`http://127.0.0.1:${P_WEB}/`);
  prueba("la app compilada responde", pagina.status === 200 && /<div id="root">/.test(await pagina.text()));
  console.log(`\nRESULTADO: ${ok} de ${tot} comprobaciones correctas — ${fallas.length ? "FALLAS: " + fallas.join(" | ") : "SIN FALLAS"}`);
  edge.kill(); base.close(); web.close(); await new Promise((r) => setTimeout(r, 500)); limpiarLoCreado();
  process.exit(fallas.length ? 1 : 0);
}
console.log(`
Revisión local del Reparto de facturas lista (base ${DB} en 55432; Edges reales geoportal-reparto, geoportal-scrr, geoportal-campo y geoportal-admin; nada va a Supabase).
  Abra  http://127.0.0.1:${P_WEB}/  y entre con cualquiera de estos usuarios y cualquier clave:
${USUARIOS.map(([e, p]) => `    ${e.split("@")[0].padEnd(24)} ${p}`).join("\n")}
  Casos para revisar: ~/geoportal-consultas/campo/paquete_reparto_1/commit4/CASOS_REVISION.md   ·   Ctrl+C para terminar (borra la base y el rol que creó).`);
const fin = () => { try { edge.kill(); } catch { /* ya terminó */ } base.close(); web.close(); setTimeout(() => { limpiarLoCreado(); console.log("Servidor detenido; se borró lo que creó esta corrida (su base y el rol)."); process.exit(0); }, 500); };
process.on("SIGINT", fin); process.on("SIGTERM", fin);
