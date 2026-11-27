// [Code A] Etiqueta del último pago (27-nov) · prueba de la EDGE REAL por llamada directa y de la PANTALLA «Análisis de contrato» en CHROME REAL, sin Supabase:
//   AnalisisContrato real → Edge REAL geoportal-campo (Deno, de <supabase/functions>; sin cambios en este paquete) → PostgREST y Auth mínimos en Node que llaman a
//   las RPC REALES de la base local del Code A (55432): copia de producción (huella de campo c476f14d…) CON este paquete y, en una segunda base, SIN él (la
//   pantalla nueva con la base de antes debe seguir mostrando el periodo del consumo). Cada RPC como service_role con 30 s y 8 s. A 390 px (táctil) y 1280 px.
// Perfiles (5): administrador, supervisor de Comercial, operador de campo (sin Análisis), dual (campo y Análisis) y sin permisos.
// Contratos de prueba 9918000001NN (solo en la base local): 101 pago por cupones (corte 202610), 102 pago de la cartera mensual (corte 202609), 103 sin pago.
//   node scripts/prueba_chrome_etiqueta_pago.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]
//   --revision  no corre las pruebas: deja arriba la revisión local (http://127.0.0.1:55971/?rol=dual, base CON el paquete; ?rol=antes, la base de antes) hasta Ctrl-C.
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55971 (app, Auth, PostgREST) y 55972 (Edge).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";
const USO = "Uso: node scripts/prueba_chrome_etiqueta_pago.mjs [--revision] <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]";
const REVISION = process.argv.includes("--revision");
const args = process.argv.slice(2).filter((a) => a !== "--revision");
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, CAP_ARG] = args;
if (!FUNCIONES) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_etiqueta_pago")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55971, P_EDGE = 55972;
const BASES = { con: "emdupar_a_rf_pagochrome", sin: "emdupar_a_rf_pagochrome_sin" };
let DB = BASES.con;
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const pgenv = () => ({ ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" });
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: pgenv(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "ztpag.adm@emdupar.gov.co", sup: "ztpag.sup@emdupar.gov.co", op: "ztpag.op@emdupar.gov.co", dual: "ztpag.dual@emdupar.gov.co", sin: "ztpag.sin@emdupar.gov.co", antes: "ztpag.antes@emdupar.gov.co" };

// ---------- 1. Las dos bases ----------
const MESES = JSON.stringify(["202604", "202605", "202606", "202607", "202608", "202609"].map((p, k) => ({ periodo: p, sin_dato: false, m3: 10 + k, metodo: "lectura", lectura_real: true, causal: "99 LECTURA NORMAL" })));
for (const [modo, db] of Object.entries(BASES)) {
  execFileSync("python3", ["-I", "-B", join(raiz, "sql/campo_etiqueta_pago/pruebas_locales/base_chrome.py"), db, modo], { stdio: ["ignore", "pipe", "inherit"] });
  DB = db;
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
    ('${E.adm}', 'ZTPAG Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
    ('${E.sup}', 'ZTPAG Supervisora', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
    ('${E.op}', 'ZTPAG Operario sin Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
    ('${E.dual}', 'ZTPAG Dual', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true),
    ('${E.sin}', 'ZTPAG Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false),
    ('${E.antes}', 'ZTPAG Dual (revisión con la base de antes)', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true);
    insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga, categoria, subcategoria, ciclo) values
      ('991800000101', 'ACTIVO', 'ZTPAG PERSONA UNO', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 45000, '20261123', '1 - Residencial', '2', '15'),
      ('991800000102', 'ACTIVO', 'ZTPAG PERSONA DOS', '3002223344', 'CLL 5 # 3-10', 'LOS MAYALES', 0, '20261123', '1 - Residencial', '2', '15'),
      ('991800000103', 'ACTIVO', 'ZTPAG PERSONA TRES', null, 'MZ 4 CASA 7', 'PRIMERO DE MAYO', 0, '20261123', '1 - Residencial', '2', '15');
    insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, estrato, consumo_meses, meses_con_lectura, medidor_fecha_estado, ultimo_pago) values
      ('991800000101', '202609', 'Residencial', 'Estrato 2', ${lit(JSON.parse(MESES))}, 6, 'sin_dato', '{"fecha": "2026-10-20", "valor": 45000, "fuente": "cupones", "corte": "202610"}'),
      ('991800000102', '202609', 'Residencial', 'Estrato 2', ${lit(JSON.parse(MESES))}, 6, 'sin_dato', '{"fecha": "2026-09-03", "valor": 30000, "fuente": "cartera", "corte": "202609"}'),
      ('991800000103', '202609', 'Residencial', 'Estrato 2', ${lit(JSON.parse(MESES))}, 6, 'sin_dato', null);
    insert into bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms) values (1, 'prueba-local', 3, '2026-11-26 06:00-05', 1000) on conflict (id) do nothing;`);
}
DB = BASES.con;

// ---------- 2. La app (esbuild) con un doble de lib/supabase que da el token del rol ----------
const dir = mkdtempSync(join(tmpdir(), "ui_pago_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => ({ error: null }) }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css"; import "./src/campo/analisis/analisis.css";
    import AnalisisContrato from "./src/campo/analisis/AnalisisContrato.tsx";
    createRoot(document.getElementById("raiz")).render(<div className="campo-contenedor com-modulo"><AnalisisContrato onVolver={() => {}} /></div>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 3. Auth y PostgREST mínimos; las RPC van a la base local REAL ----------
const rpcs = [];
function rpcBase(fn, a) {
  const argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", "); const t0 = Date.now();
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${argumentos})`],
      { env: pgenv(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
    rpcs.push({ fn, ms: Date.now() - t0 }); let c; try { c = JSON.parse(t); } catch { c = t.trim(); } return { status: 200, cuerpo: c };
  } catch (e) {
    const t = String(e.stderr || ""); rpcs.push({ fn, ms: Date.now() - t0, error: t.slice(0, 300) });
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: (t.match(/HINT:\s+(\S+)/) || [])[1] } };
  }
}
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
      if (REVISION) DB = a.p_solicitante === E.antes ? BASES.sin : BASES.con;   // revisión: «antes» consulta la base sin el paquete
      if (fn === "geoportal_log") return json(200, null);
      if (fn === "geoportal_estado_acceso" || fn.startsWith("geoportal_campo_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      return json(404, { code: "PGRST202", message: "no existe" });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 4. Edge REAL en Deno ----------
const servir = join(dir, "servir_edge.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edge lista"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edge lista/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 8000); });

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 700)}`); };
const llamar = async (rol, contrato) => {
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-campo?accion=analisis_contrato&contrato=${contrato}`, { headers: { Authorization: `Bearer tok-${rol}` } });
  let j = null; try { j = await r.json(); } catch { /* sin cuerpo */ } return { s: r.status, j };
};
if (REVISION) { console.log(`revisión local: http://127.0.0.1:${P_BASE}/?rol=dual (con el paquete) · http://127.0.0.1:${P_BASE}/?rol=antes (la base de antes) · contratos 991800000101, 102, 103`); await new Promise(() => {}); }
console.log("— Edge por llamada directa (base CON el paquete) —");
{
  let r = await llamar("dual", "991800000101");
  ok("E01 dual: pago por cupones con corte 202610", r.s === 200 && r.j.pago?.fuente === "cupones" && r.j.pago?.corte === "202610", JSON.stringify(r.j?.pago));
  r = await llamar("dual", "991800000102");
  ok("E02 dual: pago de la cartera mensual con corte 202609", r.s === 200 && r.j.pago?.fuente === "cartera" && r.j.pago?.corte === "202609", JSON.stringify(r.j?.pago));
  r = await llamar("dual", "991800000103");
  ok("E03 dual: sin pago → null", r.s === 200 && r.j.pago === null, JSON.stringify(r.j?.pago));
  r = await llamar("adm", "991800000101");
  ok("E04 administrador: la consulta responde como antes del paquete (mismo estado)", r.s === 200 || r.s === 403, `${r.s} ${JSON.stringify(r.j)}`);
  const sAdm = r.s;
  for (const rol of ["sup", "op", "sin"]) {
    r = await llamar(rol, "991800000101");
    ok(`E05 ${rol}: sin permiso de Análisis → 403`, r.s === 403, `${r.s} ${JSON.stringify(r.j)}`);
  }
  DB = BASES.sin;
  r = await llamar("adm", "991800000101");
  ok("E06 administrador: mismo estado con la base de antes", r.s === sAdm, `${r.s} vs ${sAdm}`);
  r = await llamar("dual", "991800000101");
  ok("E07 base SIN el paquete: el pago llega sin corte (la de producción hoy)", r.s === 200 && r.j.pago && !("corte" in r.j.pago), JSON.stringify(r.j?.pago));
  DB = BASES.con;
}

const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000, args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
async function abrir(rol, ancho) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(500);
  return pg;
}
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(i, val); i.dispatchEvent(new Event("input", { bubbles: true })); }, sel, v);
const esperar = (pg, f, ...a) => pg.waitForFunction(f, { timeout: 20000 }, ...a).then(() => true).catch(() => false);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const foto = (pg, n) => pg.screenshot({ path: join(CAP, n + ".png"), fullPage: true });
const lineaPago = (pg) => pg.evaluate(() => [...document.querySelectorAll(".ac-lineas li")].find((l) => /Último pago/.test(l.innerText))?.innerText ?? "");
const etiquetaPago = (pg) => pg.evaluate(() => [...document.querySelectorAll(".ac-lineas li")].find((l) => /Último pago/.test(l.innerText))?.querySelector(".ac-corte")?.innerText ?? null);
async function consultar(pg, c) {
  await escribir(pg, "#ac-contrato", c); await clicTexto(pg, "button", "Consultar");
  return esperar(pg, (x) => document.querySelector('[data-testid="tarjeta"]') && [...document.querySelectorAll(".ac-lineas li")].some((l) => /Último pago/.test(l.innerText)) && document.body.innerText.includes(x.slice(-3)), c);
}

try {
  for (const ancho of [390, 1280]) {
    console.log(`— Chrome a ${ancho} px (base CON el paquete) —`);
    DB = BASES.con;
    let pg = await abrir("dual", ancho);
    ok(`C${ancho}.01 cupones: «pagos a oct-2026»`, await consultar(pg, "991800000101") && (await etiquetaPago(pg)) === "pagos a oct-2026", await lineaPago(pg));
    ok(`C${ancho}.02 la línea conserva fecha, días y valor`, /Último pago: 20\/10\/2026 \(hace \d+ días\) · \$ 45\.000/.test(await lineaPago(pg)), await lineaPago(pg));
    ok(`C${ancho}.03 la ficha sigue «a sep-2026» (consumo), distinta del pago`, /ficha a sep-2026/.test(await pg.$eval('[data-testid="tarjeta"]', (e) => e.innerText)));
    ok(`C${ancho}.04 sin desborde horizontal`, await sinDesborde(pg));
    await foto(pg, `${ancho}_con_cupones`);
    ok(`C${ancho}.05 cartera mensual: «cartera mensual a sep-2026»`, await consultar(pg, "991800000102") && (await etiquetaPago(pg)) === "cartera mensual a sep-2026", await lineaPago(pg));
    await foto(pg, `${ancho}_con_cartera`);
    ok(`C${ancho}.06 sin pago: «Último pago: sin dato» y sin etiqueta`, await consultar(pg, "991800000103") && /Último pago: sin dato/.test(await lineaPago(pg)) && (await etiquetaPago(pg)) === null, await lineaPago(pg));
    await pg.close();
    for (const rol of ["sup", "op", "sin"]) {
      pg = await abrir(rol, ancho);
      await escribir(pg, "#ac-contrato", "991800000101"); await clicTexto(pg, "button", "Consultar"); await esp(1500);
      const t = await pg.$eval("body", (e) => e.innerText);
      ok(`C${ancho}.07 ${rol}: no ve la ficha ni el pago`, !(await pg.$('[data-testid="tarjeta"]')) && !/Último pago/.test(t), t.slice(0, 300));
      await pg.close();
    }
    pg = await abrir("adm", ancho);
    await escribir(pg, "#ac-contrato", "991800000101"); await clicTexto(pg, "button", "Consultar"); await esp(1500);
    const tAdm = await pg.$eval("body", (e) => e.innerText);
    ok(`C${ancho}.08 administrador: si ve la ficha, la etiqueta es «pagos a oct-2026»`, !/Último pago/.test(tAdm) || (await etiquetaPago(pg)) === "pagos a oct-2026", tAdm.slice(0, 300));
    await pg.close();
    console.log(`— Chrome a ${ancho} px (base SIN el paquete: la de producción hoy) —`);
    DB = BASES.sin;
    pg = await abrir("dual", ancho);
    ok(`C${ancho}.09 sin «corte» en la respuesta: sigue «pagos a sep-2026» (periodo del consumo), como hoy`, await consultar(pg, "991800000101") && (await etiquetaPago(pg)) === "pagos a sep-2026", await lineaPago(pg));
    ok(`C${ancho}.10 cartera sin «corte»: «cartera mensual a sep-2026»`, await consultar(pg, "991800000102") && (await etiquetaPago(pg)) === "cartera mensual a sep-2026", await lineaPago(pg));
    await foto(pg, `${ancho}_sin_paquete`);
    await pg.close();
  }
} finally {
  await nav.close(); srv.close(); edge.kill();
}
const lentas = rpcs.filter((r) => r.fn === "geoportal_campo_analisis_contrato").map((r) => r.ms);
ok(`T01 la RPC del análisis (incluye arrancar psql) tarda menos de 2 s (máx ${Math.max(...lentas)} ms en ${lentas.length})`, Math.max(...lentas) < 2000);
console.log(`\nRESULTADO: ${total - fallas} de ${total}${fallas ? " — CON FALLAS" : " — SIN FALLAS"} · capturas en ${CAP}`);
process.exit(fallas ? 1 : 0);
