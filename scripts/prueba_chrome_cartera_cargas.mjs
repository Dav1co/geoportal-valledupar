// Motor SCRR · corte 2 · commit 1: «Carga del día» del modo «Cartera», de punta a punta en CHROME REAL y SIN Supabase (Code A, 22-nov):
//   la APP COMPLETA compilada con Vite (supabase-js real contra un Auth simulado) → la Edge REAL geoportal-scrr en Deno → un PostgREST mínimo en Node que llama las RPC
//   REALES de la base local del Code A (clúster 55432) como service_role con 30 s y 8 s (topes de producción).
//   Base: copia de la plantilla «scrr_plantilla» (el doble de Administración con el cargo del supervisor: campo 261bed3c…) + la migración del paquete scrr_corte2 +
//   112.000 contratos SINTÉTICOS en cartera_suscripcion (los mismos 93xxxxxxxxxx del archivo, con valores «viejos»). Ningún dato real.
//   Mide la lectura del Excel de 112.000 filas en el navegador (tiempo y memoria del Worker) y el tiempo de cada RPC con ese volumen.
// Uso: node scripts/prueba_chrome_cartera_cargas.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]   ·   -h ayuda
// Puertos del Code A para esta prueba: 54981 (páginas), 54982 (Auth y PostgREST), 54983 (Edge).
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, statSync, mkdirSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_cartera_cargas.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
for (const a of args) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = args;
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(args[5] || join(tmpdir(), "capturas_cartera_cargas")); mkdirSync(CAP, { recursive: true });
const P_WEB = 54981, P_BASE = 54982, P_EDGE = 54983, BASE = `http://127.0.0.1:${P_BASE}`;
const DB = "scrr_chrome";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const psqlIn = (sql, db = DB) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-d", db], { input: sql, env: PGENV, encoding: "utf8", maxBuffer: 256 << 20 }).trim();
const sqlq = (s) => psqlIn(s);
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
let ok = 0, tot = 0; const fallas = [];
const prueba = (n, c, d = "") => { tot++; if (c) { ok++; console.log("OK   ", n); } else { fallas.push(n); console.log("FALLA", n, String(d).slice(0, 500)); } };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- 0. Base: copia de la plantilla + migración + 112.000 contratos sintéticos ----------
if (psqlIn("show port", "postgres") !== "55432") { console.error("No es el clúster del Code A (55432)"); process.exit(2); }
psqlIn(`drop database if exists ${DB}; create database ${DB} template scrr_plantilla;`, "postgres");
const MIG = join(raiz, "sql/scrr_corte2/migracion_scrr_corte2_editor.sql");
execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-d", DB, "-f", MIG], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
sqlq(`insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, saldo_pendiente, ciclo, periodo_carga)
      select (930000000000 + g)::text, 'VIEJO', 'SINTÉTICO VIEJO ' || g, 'CALLE VIEJA', 1, '01', '20261121' from generate_series(1, 112000) g; analyze public.cartera_suscripcion;`);
prueba("0.01 base lista: scrr migrado, 112.000 contratos sintéticos «viejos» en cartera_suscripcion",
  sqlq("select (to_regnamespace('scrr') is not null)::text || '|' || (select count(*) from public.cartera_suscripcion)") === "true|112000");

// ---------- 1. Archivos sintéticos ----------
const ARCH = mkdtempSync(join(tmpdir(), "cartera_xlsx_"));
const gen = (a) => execFileSync(process.execPath, [join(raiz, "scripts/scrr_generar_xlsx.mjs"), ...a], { encoding: "utf8" }).trim();
console.log("   " + gen(["cartera", "112000", join(ARCH, "cartera_del_dia.xlsx")]));
gen(["cartera", "100", join(ARCH, "cartera_con_columna_de_mas.xlsx"), "--columna-extra"]);
gen(["pagos", "5000", join(ARCH, "pagos_del_dia.xlsx")]);
gen(["actividades", "1000", join(ARCH, "actividades.xlsx")]);

// ---------- 2. App completa (Vite), Auth simulado y PostgREST mínimo ----------
const DIST = mkdtempSync(join(tmpdir(), "cartera_app_"));
const v = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: BASE, VITE_SUPABASE_ANON_KEY: "clave-de-revision", VITE_FUNCTIONS_URL: `http://127.0.0.1:${P_EDGE}/functions/v1` } });
if (v.status !== 0) { console.error("La app no compiló\n" + v.stdout + v.stderr); process.exit(2); }
const cuentas = new Set(sqlq("select string_agg(email, ',') from public.geoportal_lista_blanca").split(","));
const registro = [];
const CAB = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer" };
const forma = new Map();
function rpcBase(fn, a) {
  if (!forma.has(fn)) forma.set(fn, sqlq(`select proretset::text || '|' || prorettype::regtype::text from pg_proc where proname = ${lit(fn)} and pronamespace = 'public'::regnamespace limit 1`) || null);
  const f = forma.get(fn); if (!f) return { status: 404, cuerpo: { code: "PGRST202", message: `no existe public.${fn}` } };
  const [conjunto, tipo] = f.split("|"), argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  const sel = conjunto === "true" ? `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.${fn}(${argumentos}) t` : tipo === "void" ? `select public.${fn}(${argumentos})` : `select to_jsonb(public.${fn}(${argumentos}))`;
  const t0 = Date.now();
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-d", DB], { input: `set role service_role; set statement_timeout = '30s'; set lock_timeout = '8s';\n${sel};\n`,
      env: PGENV, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], maxBuffer: 64 << 20 });
    registro.push({ fn, ms: Date.now() - t0, lote: a.p_lote ?? null });
    return tipo === "void" && conjunto !== "true" ? { status: 204 } : { status: 200, cuerpo: JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || ""); registro.push({ fn, ms: Date.now() - t0, error: t.slice(0, 300) });
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
    json(404, { message: "no simulado" });
  });
});
await new Promise((r) => base.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES: geoportal-scrr (la del corte) y geoportal-campo/admin para el perfil; las demás 503 ----------
const SEM = mkdtempSync(join(tmpdir(), "cartera_edges_"));
const servirTs = join(SEM, "servir_edges.ts");
writeFileSync(servirTs, `const real = Deno.serve.bind(Deno); const hs: Record<string, any> = {}; let actual = "";
(Deno as any).serve = (x: any) => { hs[actual] = typeof x === "function" ? x : x.handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
for (const f of ["geoportal-scrr", "geoportal-admin", "geoportal-campo"]) { actual = f; await import("file://" + ${JSON.stringify(resolve(FUNCIONES))} + "/" + f + "/index.ts"); }
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => {
  const f = new URL(r.url).pathname.split("/")[3] ?? "";
  if (hs[f]) return hs[f](r);
  if (r.method === "OPTIONS") return new Response("ok", { headers: cors });
  return new Response(JSON.stringify({ error: "Esta función no está en la prueba local." }), { status: 503, headers: { ...cors, "Content-Type": "application/json" } });
});`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servirTs], { env: { ...process.env, SUPABASE_URL: BASE, SERVICE_ROLE_KEY: "clave-de-revision", SUPABASE_SERVICE_ROLE_KEY: "clave-de-revision", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
await new Promise((a, m) => { edge.stdout.on("data", (d) => { if (String(d).includes("edges listas")) a(); }); edge.on("exit", () => m(new Error("Deno terminó: " + edgeLog.slice(-600)))); setTimeout(() => m(new Error("Deno no arrancó: " + edgeLog.slice(-600))), 60000); });
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));
const edgeDirecta = async (email, accion, cuerpo) => { const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-scrr?accion=${accion}`, { method: cuerpo ? "POST" : "GET",
  headers: { Authorization: `Bearer tok-${email}`, "Content-Type": "application/json" }, body: cuerpo ? JSON.stringify(cuerpo) : undefined }); return { status: r.status, cuerpo: await r.json().catch(() => null) }; };

// ---------- 4. Chrome ----------
const puppeteer = createRequire(import.meta.url)(PUP);
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
const SUP = "prueba.sup.comercial@emdupar.gov.co", OP = "prueba.op.comercial@emdupar.gov.co", ADM = "prueba.admin@emdupar.gov.co", TODO = "prueba.caso.todo@emdupar.gov.co";
async function entrar(email, ancho) {
  const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => errores.push(`${email} ${ancho}: ${e.message}`));
  await pg.goto(`http://127.0.0.1:${P_WEB}/`); await pg.waitForSelector("input[type=password]", { timeout: 20000 });
  const [usr] = await pg.$$("input:not([type=password])"); await usr.type(email.split("@")[0]); await pg.type("input[type=password]", "cualquiera"); await pg.keyboard.press("Enter");
  await pg.waitForFunction(() => !document.querySelector("input[type=password]") && !/Cargando/.test(document.body.innerText) && document.body.innerText.trim().length > 40, { timeout: 30000 });
  await esp(800);
  return { pg, ctx };
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const esperarTexto = async (pg, re, ms = 30000) => { const fin = Date.now() + ms; while (Date.now() < fin) { if (re.test(await texto(pg))) return true; await esp(200); } await pg.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/: ${(await texto(pg)).slice(-800)}`); };
const clicAccion = (pg, a) => pg.evaluate((x) => { const b = document.querySelector(`[data-accion="${x}"]`); if (b && !b.disabled) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, a);
// Sin desborde: ni la página ni el área de Cartera (que tiene su propio desplazamiento) son más anchas que la ventana; solo la tabla puede desplazarse dentro de su marco
const sinDesborde = (pg) => pg.evaluate(() => { const a = document.querySelector(".scrr-area");
  return document.documentElement.scrollWidth <= window.innerWidth + 1 && (!a || a.scrollWidth <= a.clientWidth + 1)
    && [...document.querySelectorAll(".scrr-area h1, .scrr-area p, .scrr-tarjeta, .scrr-hoy li, .scrr-btn")].every((e) => e.getBoundingClientRect().right <= window.innerWidth + 1); });
async function subir(pg, archivo) { const inp = await pg.$('[data-campo="archivo"]'); await inp.uploadFile(archivo); await esp(200); }
async function elegirTipo(pg, t) { await pg.select('[data-campo="tipo"]', t); await esp(200); }

try {
  // ===== A. El Supervisor comercial SIN modos del geovisor entra a «Cartera» (P3) =====
  let { pg, ctx } = await entrar(SUP, 1280);
  const opciones = await pg.evaluate(() => [...document.querySelectorAll(".modo-capsula [data-modo]")].map((b) => b.getAttribute("data-modo")));
  prueba("A.01 el Supervisor comercial sin modos del geovisor ve «Formatos de campo» y «Cartera»", opciones.join(",") === "campo,cartera", opciones.join(","));
  const campoSup = await pg.evaluate(() => { const c = document.querySelector(".campo-contenedor"); return c ? { overflow: getComputedStyle(c).overflowY, alto: c.clientHeight, texto: c.innerText.length } : null; });
  prueba("A.01b en «Formatos de campo» sus pantallas quedan dentro de un contenedor con desplazamiento (no se recortan)", campoSup?.overflow === "auto" && campoSup.alto > 300 && campoSup.texto > 20, JSON.stringify(campoSup));
  await pg.click('.modo-capsula [data-modo="cartera"]');
  await esperarTexto(pg, /¿Falta cargar hoy\?/);
  prueba("A.02 el modo «Cartera» abre «Carga del día» con las tres cargas por hacer",
    (await pg.$$eval(".scrr-hoy li.falta", (l) => l.length)) === 3 && /Cartera del día/.test(await texto(pg)));
  // Plantilla
  const cdp = await pg.createCDPSession(); const DESC = join(CAP, "descargas"); mkdirSync(DESC, { recursive: true });
  await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: DESC });
  await clicAccion(pg, "plantilla");
  let f = null; for (let i = 0; i < 50 && !f; i++) { await esp(200); f = readdirSync(DESC).find((x) => x === "plantilla_cartera.xlsx"); }
  let encab = null;
  if (f) {
    const { build } = createRequire(join(raiz, "package.json"))("esbuild"); const T = mkdtempSync(join(tmpdir(), "lx_"));
    await build({ entryPoints: [join(raiz, "src/scrr/lectorXlsx.ts")], bundle: true, format: "esm", platform: "node", outfile: join(T, "x.mjs"), logLevel: "error" });
    const { leerXlsx } = await import(pathToFileURL(join(T, "x.mjs")).href);
    await leerXlsx(new Uint8Array(readFileSync(join(DESC, f))), { alFila: (c, h, n) => { if (h === 0 && n === 1) encab = c; } });
  }
  prueba("A.03 «Descargar la plantilla» baja un .xlsx con las 21 columnas (con «Facturas vencidas») y su Léame", encab?.length === 21 && encab.includes("Facturas vencidas") && encab[0] === "Contrato", JSON.stringify(encab));
  // Archivo con una columna de más
  await subir(pg, join(ARCH, "cartera_con_columna_de_mas.xlsx")); await clicAccion(pg, "leer");
  await esperarTexto(pg, /sobra la columna «Columna que sobra»/);
  prueba("A.04 un Excel con una columna que no es de la plantilla se rechaza entero con mensaje claro", true);
  await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.includes("Empezar de nuevo"))?.click()); await esp(300);

  // ===== B. Cartera de 112.000 filas: lectura en el navegador (tiempo y memoria) =====
  const heap = { pagina: 0, worker: 0 }; let midiendo = true; const sesiones = [];
  const cdpPg = await pg.createCDPSession(); sesiones.push(["pagina", cdpPg]);
  pg.on("workercreated", (w) => { try { if (w.client) sesiones.push(["worker", w.client]); } catch { /* sin acceso */ } });
  const muestreo = (async () => { while (midiendo) { for (const [k, s] of sesiones) { try { const h = await s.send("Runtime.getHeapUsage"); heap[k] = Math.max(heap[k], h.usedSize); } catch { /* terminó */ } } await esp(50); } })();
  const h0 = (await cdpPg.send("Runtime.getHeapUsage")).usedSize;
  await subir(pg, join(ARCH, "cartera_del_dia.xlsx")); const t0 = Date.now(); await clicAccion(pg, "leer");
  await esperarTexto(pg, /Lo que se leyó en este computador/, 120000); const msLectura = Date.now() - t0;
  midiendo = false; await muestreo;
  const lecturaUI = await pg.$eval('[data-dato="lectura"]', (e) => e.innerText).catch(() => "");
  const mbW = heap.worker / 1048576, mbP = (heap.pagina - h0) / 1048576;
  prueba(`B.01 lee el Excel de 112.000 filas (10,5 MB) en el Worker: ${(msLectura / 1000).toFixed(1)} s (la pantalla dice «${lecturaUI}»); memoria pico del Worker ${mbW.toFixed(0)} MB, página +${mbP.toFixed(0)} MB`,
    msLectura < 15000 && (await pg.$eval('[data-dato="filas"]', (e) => e.innerText)) === "112.000" && (heap.worker === 0 || mbW < 400), JSON.stringify(heap));
  writeFileSync(join(CAP, "medicion_lector.txt"), `Lectura en Chrome (Worker) de una cartera SINTÉTICA de 112.000 filas (10,5 MB, textos compartidos), escritorio 1280 px:\n`
    + `  tiempo desde «Leer» hasta el resumen: ${msLectura} ms (la pantalla: ${lecturaUI})\n  heap pico del Worker: ${mbW.toFixed(1)} MB (CDP Runtime.getHeapUsage, ${heap.worker ? "medido" : "NO medible en esta versión"})\n`
    + `  heap de la página: +${mbP.toFixed(1)} MB sobre ${(h0 / 1048576).toFixed(1)} MB al empezar\n`);
  prueba("B.02 el resumen local cuenta 56.000 con saldo y 0 rechazadas", /Con saldo pendiente\s*56\.000/.test(await texto(pg)) && /Rechazadas\s*0 \(0 %\)/.test(await texto(pg)), (await texto(pg)).slice(0, 600));

  // ===== C. Envío, validación del servidor y aplicación por lotes =====
  const r0 = registro.length; const t1 = Date.now();
  await clicAccion(pg, "enviar");
  await esperarTexto(pg, /Validación del servidor/, 300000); const msEnvio = Date.now() - t1;
  const lotesRpc = registro.slice(r0).filter((x) => x.fn === "geoportal_scrr_carga_lote");
  prueba(`C.01 56 lotes enviados en ${(msEnvio / 1000).toFixed(0)} s; el lote más lento tardó ${Math.max(...lotesRpc.map((x) => x.ms))} ms en la base`,
    lotesRpc.length === 56 && lotesRpc.every((x) => !x.error), JSON.stringify(lotesRpc.filter((x) => x.error)).slice(0, 300));
  prueba("C.02 la validación del servidor coincide: 112.000 recibidas, 0 rechazadas, 56.000 con saldo, 112.000 en la cartera de suscripción hoy",
    /112\.000 \/ 112\.000/.test(await texto(pg)) && /Con saldo pendiente\s*56\.000/.test(await texto(pg)) && /112\.000 filas/.test(await texto(pg)));
  await pg.click('[data-campo="confirmo"]'); const r1 = registro.length; const t2 = Date.now();
  await clicAccion(pg, "aplicar");
  await esperarTexto(pg, /Carga aplicada/, 600000); const msAplicar = Date.now() - t2;
  const apl = registro.slice(r1).filter((x) => x.fn === "geoportal_scrr_carga_aplicar");
  const lentoApl = Math.max(...apl.filter((x) => x.lote).map((x) => x.ms)), cierre = apl.find((x) => !x.lote);
  prueba(`C.03 aplicada por lotes en ${(msAplicar / 1000).toFixed(0)} s: lote más lento ${lentoApl} ms y cierre ${cierre?.ms} ms (tope de producción 30 s)`,
    apl.filter((x) => x.lote).length === 56 && apl.every((x) => !x.error) && lentoApl < 10000 && (cierre?.ms ?? 99999) < 10000, JSON.stringify(apl.filter((x) => x.error)).slice(0, 300));
  const db1 = sqlq(`select (select count(*) from public.cartera_suscripcion where periodo_carga = to_char((now() at time zone 'America/Bogota')::date, 'YYYYMMDD'))
    || '|' || (select count(*) from scrr.v_cartera_vigente) || '|' || (select count(*) from scrr.suscripcion_respaldo) || '|' || (select count(*) from public.cartera_suscripcion)`);
  prueba("C.04 en la base: 112.000 filas nuevas en cartera_suscripcion, 56.000 en el historial, 112.000 contratos con respaldo", db1 === "112000|56000|112000|112000", db1);
  prueba("C.05 la pantalla muestra el resultado («Contratos con saldo al historial: 56.000»)", /Contratos con saldo al historial: 56\.000/.test(await texto(pg)));
  await pg.screenshot({ path: join(CAP, "cartera_aplicada_1280.png"), fullPage: true });
  prueba("C.06 a 1280 px no desborda", await sinDesborde(pg));
  writeFileSync(join(CAP, "tiempos_rpc.txt"), `Tiempos de las RPC en la base local (55432) con 112.000 contratos (en producción ~6 veces más lento):\n`
    + `  envío de 56 lotes: ${msEnvio} ms en total; carga_lote más lento ${Math.max(...lotesRpc.map((x) => x.ms))} ms, promedio ${Math.round(lotesRpc.reduce((a, x) => a + x.ms, 0) / lotesRpc.length)} ms\n`
    + `  validar: ${registro.slice(r0).find((x) => x.fn === "geoportal_scrr_carga_validar")?.ms} ms\n`
    + `  aplicar 56 lotes: ${msAplicar} ms en total; lote más lento ${lentoApl} ms, promedio ${Math.round(apl.filter((x) => x.lote).reduce((a, x) => a + x.ms, 0) / 56)} ms; cierre ${cierre?.ms} ms\n`);

  // ===== D. Pagos y actividades =====
  await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Cargar otro archivo")?.click()); await esp(300);
  await elegirTipo(pg, "pagos"); await subir(pg, join(ARCH, "pagos_del_dia.xlsx")); await clicAccion(pg, "leer");
  await esperarTexto(pg, /Lo que se leyó en este computador/, 60000); await clicAccion(pg, "enviar");
  await esperarTexto(pg, /Validación del servidor/, 60000); await pg.click('[data-campo="confirmo"]'); await clicAccion(pg, "aplicar");
  await esperarTexto(pg, /Carga aplicada/, 60000);
  prueba("D.01 pagos del día (5.000, plantilla provisional) aplicados: 5.000 pagos en la base", sqlq("select count(*) from scrr.pagos_contrato") === "5000" && /Pagos nuevos: 5\.000/.test(await texto(pg)));
  await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Cargar otro archivo")?.click()); await esp(300);
  await elegirTipo(pg, "actividades"); await subir(pg, join(ARCH, "actividades.xlsx")); await clicAccion(pg, "leer");
  await esperarTexto(pg, /Cortes drásticos\s*100/, 60000); await clicAccion(pg, "enviar");
  await esperarTexto(pg, /Validación del servidor/, 60000); await pg.click('[data-campo="confirmo"]'); await clicAccion(pg, "aplicar");
  await esperarTexto(pg, /Carga aplicada/, 60000);
  prueba("D.02 actividades (1.000) aplicadas: 1.000 actas, 100 cortes drásticos y 250 inefectivas con anomalía",
    sqlq("select count(*) || '|' || count(*) filter (where drastico) || '|' || count(*) filter (where resultado = 'inefectiva' and anomalia is not null) from scrr.actas") === "1000|100|250");
  await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Cargar otro archivo")?.click()); await esp(500);
  await esperarTexto(pg, /Al día/);
  prueba("D.03 «¿Falta cargar hoy?»: las tres al día", (await pg.$$eval(".scrr-hoy li.ok", (l) => l.length)) === 3);

  // ===== E. Revertir y anular la cartera (desde la lista) =====
  const cId = sqlq("select id from scrr.cargas where tipo = 'cartera'");
  await pg.evaluate((id) => document.querySelector(`[data-carga="${id}"] [data-accion="deshacer"]`)?.click(), cId); await esp(300);
  await pg.type('[data-campo="motivo-deshacer"]', "Prueba local: el archivo era de otro día");
  const r2 = registro.length; await clicAccion(pg, "confirmar-deshacer");
  await pg.waitForFunction((id) => !document.querySelector('[data-bloque="deshacer"]') && /Anulada/.test(document.querySelector(`[data-carga="${id}"]`)?.innerText ?? ""), { timeout: 300000 }, cId);
  const rev = registro.slice(r2).filter((x) => x.fn === "geoportal_scrr_suscripcion_revertir");
  const db2 = sqlq("select (select count(*) from public.cartera_suscripcion where estado = 'VIEJO') || '|' || (select count(*) from public.cartera_suscripcion) || '|' || scrr.f_estado_carga((select id from scrr.cargas where tipo = 'cartera'))");
  prueba(`E.01 «Revertir y anular»: la cartera de suscripción vuelve a los 112.000 «viejos» en ${rev.length} tandas (la más lenta ${Math.max(...rev.map((x) => x.ms))} ms) y la carga queda anulada`,
    db2 === "112000|112000|anulada" && rev.every((x) => !x.error), db2);
  await ctx.close();

  // ===== F. 390 px =====
  ({ pg, ctx } = await entrar(SUP, 390));
  await pg.screenshot({ path: join(CAP, "supervisor_formatos_390.png"), fullPage: false });
  prueba("F.00 a 390 px «Formatos de campo» del supervisor (con el selector) no desborda", await pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
  await pg.click('.modo-capsula [data-modo="cartera"]'); await esperarTexto(pg, /¿Falta cargar hoy\?/);
  await subir(pg, join(ARCH, "pagos_del_dia.xlsx")); await elegirTipo(pg, "pagos").catch(() => {}); await esp(300);
  prueba("F.01 a 390 px el modo Cartera no desborda", await sinDesborde(pg));
  await pg.screenshot({ path: join(CAP, "cartera_390.png"), fullPage: true });
  await ctx.close();

  // ===== G. Quién NO entra =====
  ({ pg, ctx } = await entrar(OP, 1280));
  const opOp = await pg.evaluate(() => [...document.querySelectorAll(".modo-capsula [data-modo]")].map((b) => b.getAttribute("data-modo")));
  prueba("G.01 el operario no ve «Cartera»", !opOp.includes("cartera"), opOp.join(","));
  await ctx.close();
  let rr = await edgeDirecta(OP, "contexto");
  prueba("G.02 el operario que llama la Edge directo recibe 403", rr.status === 403, JSON.stringify(rr));
  rr = await edgeDirecta("prueba.op.tecnico@emdupar.gov.co", "cargas_hoy");
  prueba("G.03 la persona solo de Técnica recibe 403", rr.status === 403, JSON.stringify(rr));
  rr = await edgeDirecta(SUP, "carga_lote", { carga_id: "00000000-0000-0000-0000-000000000001", tipo: "pagos", lote: 1, filas: [{ contrato: "1", nombre: "X" }] });
  prueba("G.04 una columna personal en un lote de pagos: 400 en la Edge («no se admite»)", rr.status === 400 && /no se admite/.test(rr.cuerpo?.error ?? ""), JSON.stringify(rr));
  rr = await edgeDirecta(SUP, "carga_iniciar", { tipo: "cartera", fecha_dato: "2026-11-22", nombre: "x.xlsx", sha256: "a".repeat(64), filas: 1, autor: "otro@emdupar.gov.co" });
  prueba("G.05 el cuerpo no puede fijar el autor: 400", rr.status === 400, JSON.stringify(rr));
  rr = await edgeDirecta(ADM, "contexto");
  prueba("G.06 el administrador entra por la Edge", rr.status === 200 && rr.cuerpo?.es_admin === true, JSON.stringify(rr).slice(0, 200));

  // ===== H. Con modos del geovisor, «Cartera» está en la cápsula de Comercial =====
  ({ pg, ctx } = await entrar(TODO, 1280));
  await pg.evaluate(() => [...document.querySelectorAll(".area-tarjeta")].find((b) => /Comercial/.test(b.innerText))?.click()); await esp(1500);
  const opTodo = await pg.evaluate(() => [...document.querySelectorAll(".modo-capsula [data-modo]")].map((b) => b.getAttribute("data-modo")));
  prueba("H.01 con modos del geovisor y dashboard_campo, la cápsula de Comercial trae «Cartera» antes de «Formatos de campo»",
    opTodo.indexOf("cartera") > 0 && opTodo.indexOf("cartera") === opTodo.indexOf("campo") - 1, opTodo.join(","));
  await pg.click('.modo-capsula [data-modo="cartera"]'); await esperarTexto(pg, /¿Falta cargar hoy\?/);
  prueba("H.02 y desde ahí abre el modo «Cartera»", true);
  await ctx.close();

  // ===== S. Las sondas propuestas (sondas_propuestas_scrr.json) contra la Edge local, con un usuario por perfil del manifiesto =====
  const SONDAS = join(process.env.HOME, "geoportal-consultas/campo/paquete_scrr_1/corte2_commit1/sondas_propuestas_scrr.json");
  if (existsSync(SONDAS)) {
    const PERF = { A: "rol = 'admin'", D: "ver_comercial, ver_registro_tecnico", S: "ver_registro_tecnico, ver_dashboard_tecnico", O: "ver_registro_tecnico", C: "ver_explorar", N: "", R: "ver_campo",
      V: "ver_dashboard_campo", T: "ver_acta", U: "ver_dashboard_acta", W: "ver_aseo", X: "ver_dashboard_aseo", Y: "ver_registro_tecnico, ver_dashboard_redes" };
    for (const [k, cols] of Object.entries(PERF)) {
      const correo = `sonda.${k.toLowerCase()}@emdupar.gov.co`, lista = cols.startsWith("rol") ? [] : cols.split(",").map((x) => x.trim()).filter(Boolean);
      sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias${lista.map((c) => ", " + c).join("")}) values ('${correo}', 'Sonda ${k}', '${k === "A" ? "admin" : "consulta"}', true, 'sin_restriccion', 'todos'${lista.map(() => ", true").join("")})`);
      cuentas.add(correo);
    }
    const sondas = JSON.parse(readFileSync(SONDAS, "utf8"))["geoportal-scrr"].sondas; const malas = []; let n = 0;
    for (const s of sondas) for (const [k, esperado] of Object.entries(s.esperado)) {
      if (s.solo_denegados && esperado !== "403") continue;
      const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1${s.ruta}`, { method: s.metodo, headers: { Authorization: `Bearer tok-sonda.${k.toLowerCase()}@emdupar.gov.co`, "Content-Type": "application/json" },
        body: s.metodo === "POST" ? JSON.stringify(s.cuerpo ?? {}) : undefined });
      const obtenido = r.status === 403 ? "403" : r.status === 401 ? "401" : "permite"; n++;
      if (obtenido !== esperado) malas.push(`${s.nombre} ${k}: ${r.status}`);
    }
    prueba(`S.01 las 11 sondas propuestas dan lo esperado contra la Edge local (${n} llamadas; A y V permiten, los demás 403)`, malas.length === 0 && n > 100, malas.join(" | "));
  }

  prueba("Z.01 sin errores de JavaScript en las páginas", errores.length === 0, errores.join(" | "));
  prueba("Z.02 la Edge no escribió filas de los lotes en su registro", !/SUSCRIPTOR SINTÉTICO|930000/.test(edgeLog), edgeLog.slice(0, 300));
} catch (e) {
  fallas.push("excepción: " + e.message); console.log("FALLA (excepción)", e.message.slice(0, 1500));
} finally {
  await nav.close(); edge.kill(); base.close(); web.close();
}
console.log(`\nRESULTADO: ${ok} de ${tot + (fallas.some((x) => x.startsWith("excepción")) ? 1 : 0)} pruebas correctas — ${fallas.length ? "FALLAS: " + fallas.join(" | ") : "SIN FALLAS"}`);
console.log(`Capturas y mediciones: ${CAP}`);
process.exit(fallas.length ? 1 : 0);
