// Prueba en CHROME REAL de las pantallas del Reparto de facturas (commit 3): la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado)
// → las Edges REALES en Deno (geoportal-reparto, más geoportal-campo, geoportal-admin y geoportal-scrr, que usa el calendario de Cartera) → un PostgREST mínimo
// en Node que llama las RPC reales en una base PROPIA de esta corrida (clúster 55432 del Code A) como service_role con los topes de producción (30 s y 8 s).
// Repartidor a 390 px (celular, con GPS simulado) y supervisor de reparto a 1280 px y a 390 px.
// La base: doble de campo (261bed3c…) + dobles del SCRR + la migración REAL del SCRR (calendario y geoportal-scrr) + dobles de rutas + el paquete reparto_1.
// La migración del SCRR crea el rol scrr_refresco (del clúster): si ya existe, esta prueba se niega; al terminar borra SOLO su base y el rol que ella creó.
// Puertos del Code A: 55003 (páginas), 55004 (Auth y PostgREST), 55005 (Edges).
// Uso: node scripts/prueba_chrome_reparto.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]      (-h: este uso)
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync, mkdirSync, readdirSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_reparto.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
for (const a of args) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = args;
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL || args.length > 6) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(args[5] || mkdtempSync(join(tmpdir(), "capturas_reparto_"))); mkdirSync(CAP, { recursive: true });
const P_WEB = 55003, P_BASE = 55004, P_EDGE = 55005, BASE = `http://127.0.0.1:${P_BASE}`;
const DB = `reparto_chrome_${process.pid}`;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
for (const k of ["SUPABASE_RO_URL", "DATABASE_URL", "PGPASSWORD", "PGSERVICE"]) delete PGENV[k];
const psqlIn = (sql, db = DB) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-d", db], { input: sql, env: PGENV, encoding: "utf8", maxBuffer: 256 << 20 }).trim();
const sqlq = (s) => psqlIn(s);
const archivoSql = (f) => execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-d", DB, "-f", f], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
let ok = 0, tot = 0; const fallas = [];
const prueba = (n, c, d = "") => { tot++; if (c) { ok++; console.log("OK   ", n); } else { fallas.push(n); console.log("FALLA", n, String(d).replace(/\n/g, " ⏎ ").slice(0, 600)); } };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- 0. Base propia ----------
if (psqlIn("show port", "postgres") !== "55432") { console.error("No es el clúster del Code A (55432)"); process.exit(2); }
if (psqlIn(`select count(*) from pg_database where datname = '${DB}'`, "postgres") !== "0") { console.error(`La base ${DB} ya existe: esta prueba no la borra.`); process.exit(2); }
if (psqlIn("select count(*) from pg_roles where rolname = 'scrr_refresco'", "postgres") !== "0") {
  console.error("El rol scrr_refresco ya existe en el clúster (lo usa otra base o quedó de otra corrida): esta prueba no lo toca. Pida permiso para quitarlo."); process.exit(2);
}
psqlIn(`create database ${DB}`, "postgres");
let rolCreado = false, limpio = false;
// SIEMPRE al salir (también si algo falla a mitad de camino): solo la base de ESTA corrida y el rol que ESTA corrida creó (antes no existía: se comprobó arriba)
function limpiar() {
  if (limpio) return; limpio = true;
  try { psqlIn(`drop database if exists ${DB} with (force)`, "postgres"); } catch (e) { console.error("No se pudo borrar " + DB + ": " + e.message); }
  if (rolCreado) try { psqlIn("drop role if exists scrr_refresco", "postgres"); } catch (e) { console.error("No se pudo quitar el rol scrr_refresco: " + e.message); }
}
process.on("exit", limpiar);
process.on("uncaughtException", (e) => { console.error("Error: " + String(e?.stack ?? e).slice(0, 800)); process.exit(1); });
process.on("unhandledRejection", (e) => { console.error("Error: " + String(e?.stack ?? e).slice(0, 800)); process.exit(1); });
const H = homedir();
try {
  archivoSql(join(H, "geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a_con_cargo_supervisor.sql"));
  archivoSql(join(H, "geoportal-emdupar/sql/scrr_corte2/pruebas_locales/doble_base_local.sql"));
  rolCreado = true;   // la migración del SCRR lo crea (si falla a mitad, la transacción no lo deja; «drop role if exists» no hace daño)
  archivoSql(join(H, "geoportal-emdupar/sql/scrr_corte2/migracion_scrr_corte2_editor.sql"));
  archivoSql(join(raiz, "sql/reparto_1/pruebas_locales/doble_rutas_local.sql"));
  psqlIn("do $$ begin if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then create role homelab_lectura nologin; end if; end $$;");
  archivoSql(join(raiz, "sql/reparto_1/migracion_reparto_1_editor.sql"));
} catch (e) { console.error("No se pudo armar la base: " + String(e.stderr || e.message).slice(-1500)); limpiar(); process.exit(2); }

const U = { rep1: "prueba.reparto.uno@emdupar.gov.co", rep2: "prueba.reparto.dos@emdupar.gov.co", sup: "prueba.reparto.sup@emdupar.gov.co",
            supcal: "prueba.sup.comercial@emdupar.gov.co", scrr: "prueba.op.comercial@emdupar.gov.co" };
// ver_explorar vale verdadero por omisión en la lista blanca: estas personas solo tienen Formatos de campo (como el operario de Comercial del doble)
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo) values
  ('${U.rep1}', 'Prueba Repartidor uno', 'consulta', true, 'sin_restriccion', 'todos', false, true), ('${U.rep2}', 'Prueba Repartidor dos', 'consulta', true, 'sin_restriccion', 'todos', false, true),
  ('${U.sup}', 'Prueba Supervisor de reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true)`);
sqlq(`insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values ('${U.rep1}', 'asignar_actividad', 'reparto', 'prueba.admin@emdupar.gov.co'),
  ('${U.rep2}', 'asignar_actividad', 'reparto', 'prueba.admin@emdupar.gov.co'), ('${U.sup}', 'asignar_actividad', 'supervision_reparto', 'prueba.admin@emdupar.gov.co'),
  ('${U.supcal}', 'asignar_actividad', 'supervision_reparto', 'prueba.admin@emdupar.gov.co')`);
// Rutas de prueba: ciclo 98 ruta 880101 con 25 contratos (casillas: 10 + 10 + 5) y ciclo 97 (sin fecha de reparto: respaldo). Período 202610.
const C = (i) => String(880000000100 + i);
sqlq(`insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo) select '98', (g * 1000000)::text, '880101', (880000000100 + g)::text, 'CALLE PRUEBA', g::text, '202610' from generate_series(1, 25) g;
      insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo) select '97', (g * 1000000)::text, '970101', (880000000500 + g)::text, 'CALLE PRUEBA', g::text, '202610' from generate_series(1, 3) g;
      insert into public.cartera_suscripcion (contrato, estado, ciclo, periodo_carga) values ('880000000301', 'ACTIVO', '98', '20261124');
      insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor)
        select to_char(h, 'YYYYMM'), 98, h + 10, h + 15, jsonb_build_object('reparto', (h - 1)::text), 'prueba.admin@emdupar.gov.co' from (select (now() at time zone 'America/Bogota')::date as h) x;
      analyze hechos.rutas_consecutivos;`);
prueba("0.01 base lista: reparto y scrr migrados, rutas de prueba, calendario del ciclo 98", sqlq("select (to_regnamespace('reparto') is not null and to_regnamespace('scrr') is not null)::text || '|' || (select count(*) from bi.v_rutas_geoportal)") === "true|28");

// ---------- 1. App, Auth y PostgREST simulados ----------
const DIST = mkdtempSync(join(tmpdir(), "reparto_app_"));
const v = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: BASE, VITE_SUPABASE_ANON_KEY: "clave-de-revision", VITE_FUNCTIONS_URL: `http://127.0.0.1:${P_EDGE}/functions/v1` } });
if (v.status !== 0) { console.error("La app no compiló\n" + v.stdout + v.stderr); limpiar(); process.exit(2); }
const cuentas = new Set(sqlq("select string_agg(email, ',') from public.geoportal_lista_blanca").split(","));
const CAB = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer" };
const forma = new Map(); const llamadas = [];
function rpcBase(fn, a) {
  if (!forma.has(fn)) forma.set(fn, sqlq(`select proretset::text || '|' || prorettype::regtype::text from pg_proc where proname = ${lit(fn)} and pronamespace = 'public'::regnamespace limit 1`) || null);
  const f = forma.get(fn); if (!f) return { status: 404, cuerpo: { code: "PGRST202", message: `no existe public.${fn}` } };
  const [conjunto, tipo] = f.split("|"), argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  const sel = conjunto === "true" ? `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.${fn}(${argumentos}) t` : tipo === "void" ? `select public.${fn}(${argumentos})` : `select to_jsonb(public.${fn}(${argumentos}))`;
  llamadas.push(fn);
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
    json(404, { message: "no simulado" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));

// ---------- 2. Edges REALES ----------
const SEM = mkdtempSync(join(tmpdir(), "reparto_edges_"));
const servirTs = join(SEM, "servir_edges.ts");
writeFileSync(servirTs, `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-reparto", "geoportal-scrr", "geoportal-admin", "geoportal-campo"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la prueba local." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--node-modules-dir=none", "--allow-net", "--allow-env", "--allow-read", "--allow-sys", "--no-check", servirTs], { cwd: SEM, env: { ...process.env, SUPABASE_URL: BASE,
  SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
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
const ORIGEN = `http://127.0.0.1:${P_WEB}`;
const edgeDirecta = async (email, accion, cuerpo, qs = "") => { const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-reparto?accion=${accion}${qs}`, { method: cuerpo ? "POST" : "GET",
  headers: { Authorization: `Bearer tok-${email}`, "Content-Type": "application/json" }, body: cuerpo ? JSON.stringify(cuerpo) : undefined }); return { status: r.status, cuerpo: await r.json().catch(() => null) }; };

// Archivos Excel de prueba con el escritor de la app (src/tecnica/xlsx.ts)
const { build } = createRequire(join(raiz, "package.json"))("esbuild"); const TX = mkdtempSync(join(tmpdir(), "rx_"));
await build({ entryPoints: [join(raiz, "src/tecnica/xlsx.ts")], bundle: true, format: "esm", platform: "node", outfile: join(TX, "x.mjs"), logLevel: "error" });
await build({ entryPoints: [join(raiz, "src/scrr/lectorXlsx.ts")], bundle: true, format: "esm", platform: "node", outfile: join(TX, "l.mjs"), logLevel: "error" });
const { LibroXlsx } = await import(pathToFileURL(join(TX, "x.mjs")).href); const { leerXlsx } = await import(pathToFileURL(join(TX, "l.mjs")).href);
async function xlsx(nombre, encab, filas) { const l = new LibroXlsx({ hoja: "Ruta", encabezados: encab, anchos: encab.map(() => 14), leame: [["x", "y"]] }); await l.agregarFilas(filas); const b = await l.finalizar(); const f = join(TX, nombre); writeFileSync(f, Buffer.from(await b.arrayBuffer())); return f; }
const ARCH_BIEN = await xlsx("ruta_nueva.xlsx", ["Contrato", "Orden"], [["880000000203", "3"], ["880000000201", "1"], ["880000000202", "2"]]);
const ARCH_MAL = await xlsx("ruta_mala.xlsx", ["Contrato", "Nombre"], [["880000000201", "x"]]);

// ---------- 3. Chrome ----------
const puppeteer = createRequire(import.meta.url)(PUP);
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
async function entrar(email, ancho, gps = true) {
  const ctx = await nav.createBrowserContext();
  if (gps) await ctx.overridePermissions(ORIGEN, ["geolocation"]);
  const pg = await ctx.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  if (gps) await pg.setGeolocation({ latitude: 10.4702, longitude: -73.2531, accuracy: 7 });
  pg.on("pageerror", (e) => errores.push(`${email} ${ancho}: ${e.message}`));
  await pg.goto(ORIGEN + "/"); await pg.waitForSelector("input[type=password]", { timeout: 20000 });
  const [usr] = await pg.$$("input:not([type=password])"); await usr.type(email.split("@")[0]); await pg.type("input[type=password]", "cualquiera"); await pg.keyboard.press("Enter");
  await pg.waitForFunction(() => !document.querySelector("input[type=password]") && !/Cargando/.test(document.body.innerText) && document.body.innerText.trim().length > 40, { timeout: 30000 });
  await esp(800);
  return { pg, ctx };
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const esperar = async (pg, fn, arg, ms = 20000, nombre = "condición") => { try { await pg.waitForFunction(fn, { timeout: ms }, arg); return true; } catch { await pg.screenshot({ path: join(CAP, `fallo_${nombre.replace(/\W+/g, "_")}.png`), fullPage: true }).catch(() => {}); return false; } };
const esperarTexto = (pg, re, ms = 20000) => esperar(pg, (s) => new RegExp(s).test(document.body.innerText), re.source, ms, re.source.slice(0, 30));
const clic = (pg, sel) => pg.evaluate((s) => { const b = document.querySelector(s); if (b && !b.disabled) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel);
const clicTexto = (pg, t) => pg.evaluate((x) => { const b = [...document.querySelectorAll("button")].find((e) => e.innerText.trim().startsWith(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, t);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1
  && [...document.querySelectorAll(".rep-pagina h1, .rep-pagina p, .rep-casilla, .rep-opcion, .rep-pagina button")].every((e) => { const r = e.getBoundingClientRect(); return r.width === 0 || r.right <= window.innerWidth + 1; }));
const casillas = (pg, bloque) => pg.$$eval(`[data-bloque="${bloque}"] .rep-casilla`, (l) => l.map((b) => ({ c: b.getAttribute("data-contrato"), s: b.classList.contains("rep-saltado"), alto: b.getBoundingClientRect().height })));
const entregasDe = (c) => sqlq(`select count(*) from reparto.entregas where contrato = '${c}'`);

try {
  // ===== R. El repartidor en el celular (390 px) =====
  let { pg, ctx } = await entrar(U.rep1, 390);
  await esperar(pg, () => [...document.querySelectorAll(".campo-formato")].some((b) => b.innerText.startsWith("Reparto de facturas")), null, 15000, "entrada_reparto");
  await pg.screenshot({ path: join(CAP, "r00_formatos_390.png"), fullPage: true });
  const entradas = await pg.$$eval(".campo-formato", (l) => l.map((b) => b.innerText.split("\n")[0]));
  prueba("R.01 Formatos de campo muestra «Reparto de facturas» al repartidor (y no la supervisión)", entradas.includes("Reparto de facturas") && !entradas.some((x) => /Supervisión/.test(x) && /Reparto/.test(x)), entradas.join(" | "));
  await clicTexto(pg, "Reparto de facturas");
  await esperar(pg, () => !!document.querySelector('[data-campo="ciclo"] option[value="98"]'), null, 30000, "ciclos");
  await pg.screenshot({ path: join(CAP, "r01_inicio_390.png"), fullPage: true });
  await pg.select('[data-campo="ciclo"]', "97");
  await esperarTexto(pg, /le falta la fecha de reparto/);
  prueba("R.02 el ciclo sin fecha de reparto avisa el respaldo de 15 días", /Al ciclo 97 le falta la fecha de reparto en el calendario: se toman como entregadas las facturas de los últimos 15 días/.test(await texto(pg)));
  await pg.select('[data-campo="ciclo"]', "98");
  await esperarTexto(pg, /Se reparte la facturación de/);
  await clic(pg, '[data-opcion="a:98:880101"]'); await clic(pg, '[data-accion="empezar"]');
  await esperar(pg, () => document.querySelectorAll('[data-bloque="arriba"] .rep-casilla').length === 10, null, 30000, "lista");
  let ar = await casillas(pg, "arriba"), ab = await casillas(pg, "abajo");
  prueba("R.03 la lista: 10 casillas grandes arriba y otros 10 bajando, en orden de ruta, solo con el código (sin número de orden)",
    ar.length === 10 && ab.length === 10 && ar[0].c === C(1) && ab[0].c === C(11) && /Siguientes 10 \(bajando\)/.test(await texto(pg)) && /Entregadas 0 de 25/.test(await texto(pg))
    && !(await pg.$$eval('[data-bloque="arriba"] .rep-casilla', (l) => l.some((b) => /\b1\./.test(b.innerText)))), JSON.stringify(ar.slice(0, 3)));
  prueba("R.04 casillas para el dedo: las de arriba de 76 px o más; las de abajo de 64 px o más; sin desborde a 390 px",
    ar.every((x) => x.alto >= 76) && ab.every((x) => x.alto >= 64) && (await sinDesborde(pg)), JSON.stringify([ar[0].alto, ab[0].alto]));
  const forma = await pg.evaluate(() => {
    const cab = document.querySelector(".rep-cab").getBoundingClientRect();
    const dentro = [...document.querySelectorAll(".rep-cab *")].every((e) => { const r = e.getBoundingClientRect(); return r.height === 0 || (r.top >= cab.top - 1 && r.bottom <= cab.bottom + 1); });
    const est = document.querySelector('[data-bloque="estado"]').getBoundingClientRect();
    return { dentro, estadoVisible: est.height > 20 && est.top >= cab.bottom - 1, buscar: document.querySelector('[data-campo="buscar"]').getBoundingClientRect().width, ancho: window.innerWidth };
  });
  prueba("R.04b el encabezado contiene todo su texto; «Entregadas N de T» va en su barra, debajo; el buscador ocupa el ancho (menos los márgenes)",
    forma.dentro && forma.estadoVisible && forma.buscar >= forma.ancho - 40, JSON.stringify(forma));
  await pg.screenshot({ path: join(CAP, "r03_lista_390.png"), fullPage: true });
  // entregar la 4.ª
  await clic(pg, `[data-contrato="${C(4)}"]`);
  await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "confirmar");
  const dialogo = await pg.$eval('[data-dialogo="confirmar"]', (e) => e.innerText);
  prueba("R.05 al tocar: «¿Entregó esta factura?» con el código y «entrega número 1»", /¿Entregó esta factura\?/.test(dialogo) && dialogo.includes(C(4)) && /entrega número 1/.test(dialogo), dialogo);
  await pg.screenshot({ path: join(CAP, "r05_confirmar_390.png") });
  await clic(pg, '[data-accion="si"]');
  await esperarTexto(pg, /Entrega 1 guardada/);
  await esperar(pg, (c) => !document.querySelector(`[data-contrato="${c}"]`) && document.querySelectorAll('[data-bloque="arriba"] .rep-saltado').length === 3, C(4), 15000, "saltados");
  ar = await casillas(pg, "arriba");
  const fila1 = sqlq(`select lon || '|' || lat || '|' || precision_m || '|' || consecutivo || '|' || orden_lectura || '|' || coalesce(periodo_reparto, '') from reparto.entregas where contrato = '${C(4)}'`);
  prueba("R.06 «Sí»: se registra con el XY del celular; sale de la lista, sube la siguiente y las 3 que se saltó quedan arriba marcadas «Saltado»",
    !ar.some((x) => x.c === C(4)) && ar.slice(0, 3).every((x) => x.s) && ar[3].c === C(5) && ar[9].c === C(11) && fila1.startsWith("-73.253100|10.470200|7.0|1|4|") && /Entregadas 1 de 25/.test(await texto(pg)), fila1 + " " + JSON.stringify(ar.slice(0, 4)));
  // el buscador
  await pg.type('[data-campo="buscar"]', "0000000117");
  await esperar(pg, () => document.querySelectorAll('[data-bloque="arriba"] .rep-casilla').length === 1, null, 5000, "buscar");
  prueba("R.07 el buscador busca solo dentro de la ruta activa", (await casillas(pg, "arriba"))[0]?.c === C(17) && /1 contrato encontrado/.test(await texto(pg)));
  await clic(pg, `[data-contrato="${C(17)}"]`); await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "c17"); await clic(pg, '[data-accion="si"]');
  await esperarTexto(pg, /Entrega 2 guardada/);
  prueba("R.08 entrega desde el buscador: queda marcada «por buscador» y el buscador se limpia", sqlq(`select por_buscador from reparto.entregas where contrato = '${C(17)}'`) === "t" && (await pg.$eval('[data-campo="buscar"]', (e) => e.value)) === "");
  // sin señal: no se pierde y no se duplica
  await pg.setOfflineMode(true); await esp(300);
  await clic(pg, `[data-contrato="${C(1)}"]`); await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "c1"); await clic(pg, '[data-accion="si"]');
  const sinSenal = await esperar(pg, () => !!document.querySelector('[data-bloque="toque-pendiente"]') && !!document.querySelector('[data-bloque="sin-senal"]'), null, 20000, "sin_senal");
  await pg.screenshot({ path: join(CAP, "r09_sin_senal_390.png"), fullPage: true });
  const pendienteGuardado = await pg.evaluate(() => sessionStorage.getItem("reparto.toque"));
  prueba("R.09 sin señal: aviso claro, la entrega queda «sin confirmar» (guardada en la sesión con su uuid), la lista sigue ahí y no se registró nada",
    sinSenal && !!pendienteGuardado && JSON.parse(pendienteGuardado).contrato === C(1) && entregasDe(C(1)) === "0" && (await casillas(pg, "arriba")).length === 10, pendienteGuardado);
  await pg.setOfflineMode(false);
  await esperarTexto(pg, /Entrega 3 guardada/, 30000);
  prueba("R.10 al volver la señal reintenta EL MISMO toque solo: una sola fila, con el uuid guardado", entregasDe(C(1)) === "1"
    && sqlq(`select id_cliente from reparto.entregas where contrato = '${C(1)}'`) === JSON.parse(pendienteGuardado).id_cliente && (await pg.evaluate(() => sessionStorage.getItem("reparto.toque"))) === null);
  // recargar la página: la lista sigue
  await pg.reload(); await esperar(pg, () => !/Cargando/.test(document.body.innerText) && document.body.innerText.length > 40, null, 30000, "recarga");
  await clicTexto(pg, "Reparto de facturas");
  await esperar(pg, () => document.querySelectorAll('[data-bloque="arriba"] .rep-casilla').length === 10, null, 20000, "tras_recargar");
  prueba("R.11 al recargar la página vuelve a la misma lista (sin escoger otra vez la ruta)", /Entregadas 3 de 25/.test(await texto(pg)) && (await casillas(pg, "arriba"))[0].c === C(2));
  // anular la última (suya, de hoy) con motivo
  await clic(pg, `[data-anular]`); await esperar(pg, () => !!document.querySelector('[data-dialogo="anular"]'), null, 5000, "anular");
  await pg.type('[data-campo="motivo"]', "Prueba: toqué la que no era");
  await clic(pg, '[data-accion="confirmar-anular"]'); await esperarTexto(pg, /anulada\. Vuelve a la lista/);
  await esperar(pg, (c) => !!document.querySelector(`[data-contrato="${c}"]`), C(1), 10000, "vuelve");
  prueba("R.12 anular la propia entrega de hoy con motivo: vuelve a la lista y la fila sigue (anulada, no borrada)", sqlq(`select count(*) || '|' || count(a.entrega_id) from reparto.entregas e left join reparto.entregas_anuladas a on a.entrega_id = e.id where e.contrato = '${C(1)}'`) === "1|1");
  // sin ruta
  await clic(pg, '[data-accion="cambiar-ruta"]'); await esperar(pg, () => !!document.querySelector('[data-accion="sin-ruta"]'), null, 20000, "inicio");
  prueba("R.13 «Siga donde iba» ofrece la jornada abierta de hoy", /Siga donde iba/.test(await texto(pg)) && /3 entregadas de 25|2 entregadas de 25/.test(await texto(pg)), (await texto(pg)).slice(0, 400));
  await clic(pg, '[data-accion="sin-ruta"]'); await esperar(pg, () => !!document.querySelector('[data-campo="buscar"]'), null, 20000, "sin_ruta");
  await pg.type('[data-campo="buscar"]', "880000000301");
  await clic(pg, '[data-accion="registrar-sin-ruta"]'); await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "c301"); await clic(pg, '[data-accion="si"]');
  await esperarTexto(pg, /Entrega 1 guardada: contrato 880000000301/);
  prueba("R.14 repartir sin ruta: busca el contrato, lo registra, y el orden en que entrega es su ruta (entrega 1)", sqlq("select consecutivo || '|' || coalesce(orden_lectura::text, 'sin') from reparto.entregas where contrato = '880000000301'") === "1|sin");
  await pg.type('[data-campo="buscar"]', "880000000999");
  await clic(pg, '[data-accion="registrar-sin-ruta"]'); await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "c999"); await clic(pg, '[data-accion="si"]');
  await esperarTexto(pg, /No hay ningún contrato con el código 880000000999/);
  prueba("R.15 sin ruta, un código que no existe: el mensaje del servidor, sin registrar", entregasDe("880000000999") === "0");
  await pg.screenshot({ path: join(CAP, "r14_sin_ruta_390.png"), fullPage: true });
  await ctx.close();
  // sin GPS
  ({ pg, ctx } = await entrar(U.rep2, 390, false));
  await clicTexto(pg, "Reparto de facturas"); await esperar(pg, () => !!document.querySelector('[data-campo="ciclo"] option[value="98"]'), null, 30000, "ciclos2");
  await pg.select('[data-campo="ciclo"]', "98"); await clic(pg, '[data-opcion="a:98:880101"]'); await clic(pg, '[data-accion="empezar"]');
  await esperar(pg, () => document.querySelectorAll('[data-bloque="arriba"] .rep-casilla').length > 0, null, 30000, "lista2");
  await clic(pg, `[data-contrato="${C(2)}"]`); await esperar(pg, () => !!document.querySelector('[data-dialogo="confirmar"]'), null, 5000, "sin_gps");
  prueba("R.16 sin permiso de ubicación: el diálogo lo dice y «Sí, entregué» queda deshabilitado (sin XY no se registra)",
    /Sin ubicación del GPS: no se puede guardar/.test(await pg.$eval('[data-dialogo="confirmar"]', (e) => e.innerText)) && (await pg.$eval('[data-accion="si"]', (b) => b.disabled)));
  prueba("R.17 la lista del segundo repartidor en la misma ruta ya descuenta lo entregado por el primero", !(await casillas(pg, "arriba")).some((x) => [C(4), C(17)].includes(x.c)));
  await ctx.close();

  // ===== S. El supervisor de reparto (1280 px) =====
  ({ pg, ctx } = await entrar(U.sup, 1280));
  await esperar(pg, () => [...document.querySelectorAll(".campo-formato")].some((b) => b.innerText.startsWith("Reparto de facturas")), null, 15000, "entrada_sup");
  const entS = await pg.$$eval(".campo-formato", (l) => l.map((b) => b.innerText.split("\n")[0]));
  prueba("S.01 el supervisor de reparto ve «Reparto de facturas · Supervisión» (gestión) y no la del repartidor", entS.includes("Reparto de facturas · Supervisión") && !entS.includes("Reparto de facturas"), entS.join(" | "));
  await clicTexto(pg, "Reparto de facturas · Supervisión");
  await esperar(pg, () => document.querySelectorAll('[data-tabla="avance"] tbody tr').length >= 3, null, 30000, "avance");
  const filas = await pg.$$eval('[data-tabla="avance"] tbody tr', (l) => l.map((r) => r.innerText.replace(/\s+/g, " ")));
  prueba("S.02 avance de hoy por repartidor y ruta: entregadas, pendientes, saltadas, anuladas y la última entrega; el período de reparto",
    filas.some((f) => /Prueba Repartidor uno Ciclo 98 · Ruta 880101/.test(f) && /2 de 25/.test(f) && /noviembre|diciembre|enero|octubre/.test(f)) && filas.some((f) => /Sin ruta/.test(f)), filas.join(" || "));
  const tabla = await pg.evaluate(() => { const c = document.querySelector('[data-tabla="avance"]').parentElement; return { caja: c.clientWidth, contenido: c.scrollWidth }; });
  prueba("S.02b en escritorio la tabla del avance se ve entera (sin recortar columnas) y usa el ancho", tabla.caja >= 1000 && tabla.contenido <= tabla.caja + 1, JSON.stringify(tabla));
  await pg.screenshot({ path: join(CAP, "s02_avance_1280.png"), fullPage: true });
  await clic(pg, `[data-detalle="${sqlq(`select id from reparto.jornadas where repartidor = '${U.rep1}' and origen = 'anterior'`)}"]`);
  await esperar(pg, () => !!document.querySelector('[data-tabla="detalle"]'), null, 15000, "detalle");
  const det = await pg.$$eval('[data-tabla="detalle"] tbody tr', (l) => l.map((r) => r.innerText.replace(/\s+/g, " ")));
  prueba("S.03 detalle: el orden real frente al de lectura, la anulada con su motivo y los saltados", det.length === 3 && /^1 880000000104 4/.test(det[0]) && det.some((d) => /Anulada: Prueba: toqué la que no era/.test(d))
    && /Saltados/.test(await texto(pg)), det.join(" || "));
  // archivos
  await clic(pg, '[data-pestana="archivos"]'); await esperar(pg, () => !!document.querySelector('[data-campo="archivo"]'), null, 10000, "archivos");
  const cdp = await pg.createCDPSession(); const DESC = join(CAP, "descargas"); mkdirSync(DESC, { recursive: true });
  await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: DESC });
  await clic(pg, '[data-accion="plantilla"]');
  let fp = null; for (let i = 0; i < 50 && !fp; i++) { await esp(200); fp = readdirSync(DESC).find((x) => x === "plantilla_ruta_reparto.xlsx"); }
  let encab = null; if (fp) await leerXlsx(new Uint8Array(readFileSync(join(DESC, fp))), { alFila: (c, h, n) => { if (h === 0 && n === 1) encab = c; } });
  prueba("S.04 «Descargar plantilla» baja un .xlsx con Contrato y Orden", JSON.stringify(encab) === '["Contrato","Orden"]', JSON.stringify(encab));
  await pg.type('[data-campo="ciclo"]', "98"); await pg.type('[data-campo="ruta"]', "ZT-NUEVA");
  await (await pg.$('[data-campo="archivo"]')).uploadFile(ARCH_MAL); await esp(200); await clic(pg, '[data-accion="cargar"]');
  await esperar(pg, () => !!document.querySelector('[data-bloque="errores"]'), null, 15000, "errores");
  prueba("S.05 un archivo con una columna que no es de la plantilla se rechaza entero, con mensaje claro", /columnas que no son de la plantilla: NOMBRE/.test(await texto(pg)) && sqlq("select count(*) from reparto.lotes") === "0");
  await (await pg.$('[data-campo="archivo"]')).uploadFile(ARCH_BIEN); await esp(200); await clic(pg, '[data-accion="cargar"]');
  await esperar(pg, () => !!document.querySelector('[data-bloque="cargado"]'), null, 20000, "cargado");
  prueba("S.06 el archivo bueno se carga (3 facturas, en su orden) y aparece en la lista de archivos", /Archivo cargado: 3 facturas/.test(await texto(pg))
    && sqlq("select string_agg(right(contrato, 3), ',' order by orden) from reparto.lote_filas") === "201,202,203" && (await pg.$$('[data-tabla="lotes"] tbody tr')).length === 1);
  await pg.screenshot({ path: join(CAP, "s06_archivos_1280.png"), fullPage: true });
  const ctxRep = await edgeDirecta(U.rep2, "contexto");
  prueba("S.07 el repartidor ya ve ese archivo como «nueva» en el ciclo 98", ctxRep.cuerpo?.nuevas?.some((l) => l.ruta === "ZT-NUEVA" && l.filas === 3), JSON.stringify(ctxRep.cuerpo?.nuevas));
  // mapa en vivo
  const pedidosMapa = []; pg.on("request", (r) => { if (/accion=mapa/.test(r.url())) pedidosMapa.push({ t: Date.now(), despues: new URL(r.url()).searchParams.get("despues") }); });
  await clic(pg, '[data-pestana="mapa"]'); await esperar(pg, () => /entregas · en vivo cada 10 s/.test(document.body.innerText), null, 30000, "mapa");
  const n0 = Number((await pg.$eval('[data-dato="estado-mapa"]', (e) => e.innerText)).split(" ")[0]);
  prueba("S.08 mapa en vivo: los puntos del día, «en vivo cada 10 s», y la línea del recorrido apagada por omisión", n0 === 4 && !(await pg.$eval('[data-campo="recorrido"]', (e) => e.checked)), String(n0));
  await pg.screenshot({ path: join(CAP, "s08_mapa_1280.png") });
  const jr = sqlq(`select id from reparto.jornadas where repartidor = '${U.rep1}' and origen = 'anterior'`);
  await edgeDirecta(U.rep1, "entregar", { jornada_id: Number(jr), contrato: C(9), lon: -73.252, lat: 10.471, precision_m: 5, por_buscador: false, id_cliente: "11111111-2222-4333-8444-555555555555" });
  const t0 = Date.now();
  const llego = await esperar(pg, () => /^5 entregas/.test(document.querySelector('[data-dato="estado-mapa"]')?.innerText ?? ""), null, 15000, "mapa_vivo");
  const conCursor = pedidosMapa.filter((p) => p.despues !== null);
  prueba(`S.09 sin recargar: la entrega nueva aparece sola en ${((Date.now() - t0) / 1000).toFixed(1)} s, pidiendo solo lo nuevo (con el cursor)`, llego && conCursor.length >= 1, JSON.stringify(pedidosMapa));
  // pestaña oculta: no consulta
  await pg.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, get: () => "hidden" }); document.dispatchEvent(new Event("visibilitychange")); });
  const antes = pedidosMapa.length; await esp(12500);
  prueba("S.10 con la pestaña oculta no consulta (12,5 s sin pedidos); al volver, consulta de una vez", pedidosMapa.length === antes
    && (await pg.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, get: () => "visible" }); document.dispatchEvent(new Event("visibilitychange")); return true; }))
    && (await (async () => { await esp(1500); return pedidosMapa.length > antes; })()), `${antes} → ${pedidosMapa.length}`);
  await clic(pg, '[data-campo="recorrido"]'); await esp(400);
  prueba("S.11 «Mostrar el recorrido» se puede prender", await pg.$eval('[data-campo="recorrido"]', (e) => e.checked));
  // calendario: solo lectura, sin enlace (no tiene dashboard_campo)
  await clic(pg, '[data-pestana="calendario"]'); await esperar(pg, () => !!document.querySelector('[data-tabla="calendario"]'), null, 15000, "calendario");
  const fila98 = await pg.$eval('[data-tabla="calendario"] tr[data-ciclo="98"]', (r) => r.innerText.replace(/\s+/g, " ")).catch(() => "");
  prueba("S.12 calendario en solo lectura: el ciclo 98 con su fecha de reparto (los 24 de la semilla del SCRR, sin fecha: «falta» y respaldo); SIN «Cambiar en Calendario» (no tiene dashboard_campo)",
    /^98 \d{2}\/\d{2}\/\d{4} /.test(fila98) && (await pg.$$('[data-tabla="calendario"] tbody tr')).length === 25
    && (await pg.$eval('[data-tabla="calendario"] tr[data-ciclo="1"]', (r) => r.innerText)).includes("falta") && !(await pg.$('[data-accion="cambiar-calendario"]')), fila98);
  prueba("S.13 sin desborde a 1280 px", await sinDesborde(pg));
  await pg.setViewport({ width: 390, height: 900, deviceScaleFactor: 2, isMobile: true, hasTouch: true }); await esp(600);
  await clic(pg, '[data-pestana="avance"]'); await esp(1500);
  prueba("S.14 la supervisión también a 390 px: sin desborde de la página (las tablas se desplazan en su marco)", await sinDesborde(pg));
  await pg.screenshot({ path: join(CAP, "s14_supervisor_390.png"), fullPage: true });
  await ctx.close();
  // el supervisor de reparto que además tiene dashboard_campo: el enlace abre el MISMO calendario de Cartera
  ({ pg, ctx } = await entrar(U.supcal, 1280));
  await pg.evaluate(() => [...document.querySelectorAll('.modo-capsula [data-modo="campo"]')][0]?.click()); await esp(800);
  await clicTexto(pg, "Reparto de facturas · Supervisión"); await esperar(pg, () => !!document.querySelector('[data-pestana="calendario"]'), null, 20000, "sup2");
  await clic(pg, '[data-pestana="calendario"]'); await esperar(pg, () => !!document.querySelector('[data-accion="cambiar-calendario"]'), null, 15000, "enlace");
  prueba("S.15 con dashboard_campo aparece «Cambiar en Calendario»", !!(await pg.$('[data-accion="cambiar-calendario"]')));
  await clic(pg, '[data-accion="cambiar-calendario"]');
  const abre = await esperar(pg, () => !!document.querySelector('[data-bloque="calendario-cartera"] [data-tabla="calendario"]') && /Pago oportuno/.test(document.querySelector('[data-bloque="calendario-cartera"]').innerText), null, 20000, "cal_cartera");
  prueba("S.16 el enlace abre el calendario de Cartera (el mismo componente y la misma Edge geoportal-scrr), con el ciclo 98", abre && llamadas.includes("geoportal_scrr_calendario_lista"), llamadas.filter((x) => /scrr/.test(x)).join());
  await pg.screenshot({ path: join(CAP, "s16_calendario_cartera_1280.png"), fullPage: true });
  await ctx.close();
  // el supervisor del SCRR sin «Supervisión de reparto»
  ({ pg, ctx } = await entrar(U.scrr, 1280));
  const entO = await texto(pg);
  prueba("S.17 alguien de campo sin las actividades no ve ninguna entrada de reparto", !/Reparto de facturas/.test(entO));
  await ctx.close();
  prueba("Z.01 ningún error de JavaScript en las páginas", errores.length === 0, errores.join(" | "));
} catch (e) { console.log("FALLA (se detuvo)", String(e?.stack ?? e).slice(0, 900)); fallas.push("se detuvo"); tot++; }

await nav.close().catch(() => {}); edge.kill(); base.close(); web.close();
limpiar();
writeFileSync(join(CAP, "resultado.txt"), `${ok} de ${tot}\n${fallas.join("\n")}\n`);
console.log(`RESULTADO: ${ok} de ${tot} — ${fallas.length ? "FALLAS: " + fallas.join(", ") : "SIN FALLAS"}  (capturas en ${CAP})`);
process.exit(fallas.length ? 1 : 0);
