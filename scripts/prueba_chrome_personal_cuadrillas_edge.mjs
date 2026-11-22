// Comercial 21-nov · Personal y cuadrillas contra la Edge REAL del Code A (geoportal-campo, rama comercial-personal-cuadrillas e5003b4, sacada con git archive) en Deno y su SQL
// (paquete (a) cf21358) en la base doble que dejó el Code A (doble_comercial_con_personal.sql, cargada en el clúster del Code B). Chrome real a 390 y 1280 px.
// Las RPC geoportal_campo_* van a la base local por psql con set role service_role, statement_timeout 30 s y lock_timeout 8 s (los topes de producción).
//   node scripts/prueba_chrome_personal_cuadrillas_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <base plantilla> [capturas]
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error.
// Cada ancho parte de una copia limpia de la plantilla (<plantilla>_chrome) con sus usuarios de prueba «zt.*»; los conteos son solo de filas de la prueba. Puertos 55989 (base) y 55990 (Edge).
// No prueba: Supabase, un celular físico ni el supervisor de actas dentro de su entrada «Actas registradas» (va con las actas): aquí su Personal se monta suelto.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_personal_cuadrillas_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <base plantilla> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA, CAP_ARG] = args;
if (!PLANTILLA) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_personal_edge")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55989, P_EDGE = 55990;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { adm: "zt.admin@emdupar.gov.co", sup: "zt.sup@emdupar.gov.co", act: "zt.act@emdupar.gov.co", ana: "zt.ana@emdupar.gov.co", beto: "zt.beto@emdupar.gov.co" };
function rehacer() {
  execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  const fila = (email, nombre, rol, campos) => `('${email}', '${nombre}', '${rol}', 'sin_restriccion', 'todos', ${["ver_campo", "ver_dashboard_campo", "ver_acta", "ver_dashboard_acta"].map((c) => (campos.includes(c) ? "true" : "false")).join(", ")})`;
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
    ${fila(E.adm, "ZT Administración", "admin", [])}, ${fila(E.sup, "ZT Sofía Supervisora", "consulta", ["ver_dashboard_campo"])}, ${fila(E.act, "ZT Supervisor de actas", "consulta", ["ver_dashboard_acta"])},
    ${fila(E.ana, "ZT Ana Prueba", "consulta", ["ver_campo", "ver_acta"])}, ${fila(E.beto, "ZT Beto Prueba", "consulta", ["ver_campo"])}`);
}
rehacer();

// ---------- 1. Paquete de la página: «Supervisión y dashboard» (o Personal y Cuadrillas sueltos con ?suelto=1, para el supervisor de actas) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_peredge_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "sup";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css"; import "./src/campo/dashboard/revision.css";
    import Revision from "./src/campo/dashboard/Revision.tsx"; import { PersonalCampo } from "./src/campo/dashboard/PersonalCampo.tsx"; import { Cuadrillas } from "./src/campo/dashboard/Cuadrillas.tsx";
    const q = new URLSearchParams(location.search);
    createRoot(document.getElementById("raiz")).render(<div className="com-modulo">{q.get("suelto") ? <div className="rv"><div className="rv-cuerpo"><PersonalCampo /><Cuadrillas /></div></div> : <Revision correo={q.get("rol") + "@prueba"} onVolver={() => {}} />}</div>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Auth y PostgREST simulados; las RPC de campo van a la base local REAL ----------
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  const t0 = Date.now();
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${argumentos})`],
      { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
    rpcs.push({ fn, ms: Date.now() - t0 });
    let c; try { c = JSON.parse(t); } catch { c = t.trim(); }          // geoportal_estado_acceso responde texto («ok»)
    return { status: 200, cuerpo: c };
  } catch (e) {
    const t = String(e.stderr || ""); rpcs.push({ fn, ms: Date.now() - t0, error: t.slice(0, 300) });
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: (t.match(/HINT:\s+(\S+)/) || [])[1] } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/paquete/.test(u.pathname)) { const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1); res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f))); }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos).toString();
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return E[rol] ? json(200, { id: "u-" + rol, email: E[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (fn === "geoportal_estado_acceso" || fn.startsWith("geoportal_campo_") || fn.startsWith("geoportal_acta_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      desconocidas.push(fn); return json(404, { code: "PGRST202", message: "no existe" });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edge REAL geoportal-campo en Deno ----------
const servir = join(dir, "servir_edge.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edge lista"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", SUPABASE_SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edge lista/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 500)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
let ultima = null;
async function abrir(rol, ancho, extra = "") {
  const pg = await nav.newPage(); ultima = pg;
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${extra}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(400);
  return pg;
}
const texto = (pg, sel = "body") => pg.$eval(sel, (e) => e.innerText);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.click(); return true; } return false; }, sel, t);
const clicEn = (pg, dentro, t) => pg.evaluate((d, x) => { const b = [...document.querySelector(d).querySelectorAll("button")].find((e) => e.textContent.trim() === x && !e.disabled); if (b) { b.click(); return true; } return false; }, dentro, t);
const marcar = (pg, sel) => pg.evaluate((s) => document.querySelector(s).click(), sel);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : i.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const tarjeta = (pg, email) => pg.$eval(`li.rv-per-tarjeta[data-persona="${email}"]`, (e) => e.innerText).catch(() => "");
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const cerrado = (pg) => pg.waitForFunction(() => !document.querySelector(".rv-modal"), { timeout: 20000 });
const idCuad = (nombre) => Number(sqlq(`select id from campo.cuadrillas where nombre = ${lit(nombre)}`));

try {
  for (const ancho of [390, 1280]) {
    if (ancho !== 390) rehacer();
    // ===== Administrador =====
    let pg = await abrir("adm", ancho);
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-testid=cuadrillas] .rv-botones"); await esp(400);
    // Crear cuadrilla con dos actividades
    await clicTexto(pg, "button", "Crear cuadrilla"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "ZT Cuadrilla Norte"); await clicTexto(pg, ".rv-modal button.rv-boton", "Crear"); await cerrado(pg);
    const norte = idCuad("ZT Cuadrilla Norte");
    await pg.waitForSelector(`[data-cuadrilla="${norte}"]`);
    ok(`[${ancho}] adm · crear cuadrilla: queda en campo.cuadrillas y aparece «Sin miembros»`, norte > 0 && (await texto(pg, `[data-cuadrilla="${norte}"]`)).includes("Sin miembros"));
    await clicEn(pg, `[data-cuadrilla="${norte}"]`, "Actividades"); await pg.waitForSelector(".rv-modal input[data-actividad=corte]");
    await marcar(pg, ".rv-modal input[data-actividad=corte]"); await marcar(pg, ".rv-modal input[data-actividad=suspension]");
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await cerrado(pg); await esp(500);
    let t = await texto(pg, `[data-cuadrilla="${norte}"]`);
    ok(`[${ancho}] adm · actividades de la cuadrilla guardadas en la base (Corte y Suspensión)`, t.includes("Corte") && t.includes("Suspensión"), t);
    await clicTexto(pg, "button", "Crear cuadrilla"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "ZT Cuadrilla Norte"); await clicTexto(pg, ".rv-modal button.rv-boton", "Crear"); await pg.waitForSelector(".rv-modal .rv-error");
    ok(`[${ancho}] adm · nombre repetido: el 409 de la Edge tal cual («Ya existe una cuadrilla con ese nombre»)`, (await texto(pg, ".rv-modal .rv-error")).includes("Ya existe una cuadrilla con ese nombre"), await texto(pg, ".rv-modal"));
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    await clicTexto(pg, "button", "Crear cuadrilla"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "ZT Cuadrilla Sur"); await clicTexto(pg, ".rv-modal button.rv-boton", "Crear"); await cerrado(pg);
    const sur = idCuad("ZT Cuadrilla Sur");
    // Áreas y actividades
    await pg.waitForSelector("[data-testid=catalogos] [data-catalogo=actividad]");
    t = await texto(pg, "[data-testid=catalogos]");
    ok(`[${ancho}] adm · «Áreas y actividades» con la semilla del Code A (4 áreas de David y las 10 actividades)`, ["Facturación", "Cartera / SCRR", "Pérdidas", "PQR / Atención al usuario", "Revisión PQR", "Posible pérdida (acta)"].every((x) => t.includes(x)), t.slice(0, 400));
    await clicTexto(pg, "[data-catalogo=actividad] button", "Agregar actividad"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "ZT Toma especial"); await clicTexto(pg, ".rv-modal button.rv-boton", "Agregar"); await cerrado(pg); await esp(400);
    const codNuevo = sqlq(`select codigo from campo.actividades where nombre = 'ZT Toma especial'`);
    ok(`[${ancho}] adm · agregar actividad: el servidor genera el código y la pantalla lo muestra`, !!codNuevo && (await texto(pg, "[data-testid=cuadrillas]")).includes(`(código ${codNuevo})`), codNuevo);
    await clicTexto(pg, "[data-catalogo=actividad] button", "Agregar actividad"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "ZT Toma especial"); await clicTexto(pg, ".rv-modal button.rv-boton", "Agregar"); await pg.waitForSelector(".rv-modal .rv-error");
    ok(`[${ancho}] adm · actividad repetida: «Ya existe una actividad con ese nombre»`, (await texto(pg, ".rv-modal .rv-error")).includes("Ya existe una actividad con ese nombre"));
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    await pg.evaluate((c) => [...document.querySelector(`[data-catalogo=actividad] [data-codigo="${c}"]`).querySelectorAll("button")].find((b) => b.textContent === "Desactivar").click(), codNuevo); await pg.waitForSelector(".rv-modal textarea");
    await escribir(pg, ".rv-modal textarea", "Actividad de prueba que no se usa"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await cerrado(pg); await esp(400);
    ok(`[${ancho}] adm · desactivar actividad con motivo: queda inactiva en la base (no se borra)`, sqlq(`select activa from campo.actividades where codigo = ${lit(codNuevo)}`) === "f");
    await pg.screenshot({ path: join(CAP, `edge_cuadrillas_${ancho}_admin.png`), fullPage: true });

    // Personal: Ana → área, cuadrilla Norte, actividad propia Lectura; Beto → Reparto propio
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector(`li.rv-per-tarjeta[data-persona="${E.ana}"]`); await esp(300);
    t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] adm · Personal desde la Edge real: sus personas de prueba y «Usted puede» con todo`, t.includes("ZT Ana Prueba") && t.includes("ZT Sofía Supervisora") && /Usted puede: fijar el área y el cargo/.test(t), t.slice(0, 400));
    await clicEn(pg, `li.rv-per-tarjeta[data-persona="${E.ana}"]`, "Editar"); await pg.waitForSelector(".rv-modal [data-campo=area]");
    ok(`[${ancho}] adm · la actividad desactivada no se ofrece`, await pg.evaluate((c) => !document.querySelector(`.rv-modal input[data-actividad="${c}"]`), codNuevo));
    await escribir(pg, ".rv-modal [data-campo=area]", "perdidas"); await escribir(pg, ".rv-modal [data-campo=cuadrilla]", String(norte));
    await marcar(pg, ".rv-modal input[data-actividad=lectura]");
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await cerrado(pg); await esp(600);
    let ana = await tarjeta(pg, E.ana);
    ok(`[${ancho}] adm · Ana releída de la Edge: Pérdidas, ZT Cuadrilla Norte, Corte y Suspensión de la cuadrilla, Lectura propia`,
      ana.includes("Pérdidas") && ana.includes("ZT Cuadrilla Norte") && /Corte\s*· de la cuadrilla/.test(ana) && /Suspensión\s*· de la cuadrilla/.test(ana) && /Lectura\s*· propia/.test(ana), ana);
    await clicEn(pg, `li.rv-per-tarjeta[data-persona="${E.beto}"]`, "Editar"); await pg.waitForSelector(".rv-modal [data-campo=cuadrilla]");
    await escribir(pg, ".rv-modal [data-campo=cuadrilla]", String(norte)); await marcar(pg, ".rv-modal input[data-actividad=corte]"); await marcar(pg, ".rv-modal input[data-actividad=reparto]");
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await cerrado(pg); await esp(600);
    let beto = await tarjeta(pg, E.beto);
    ok(`[${ancho}] adm · una actividad propia que también da la cuadrilla sale como «propia y de la cuadrilla» (ambas)`, /Corte\s*· propia y de la cuadrilla/.test(beto) && /Reparto\s*· propia/.test(beto), beto);
    // Quién puede hacer… Corte
    await escribir(pg, "[data-testid=quien-puede] select", "corte"); await pg.waitForSelector(".rv-per-quien-res"); await esp(200);
    t = await texto(pg, "[data-testid=quien-puede]");
    ok(`[${ancho}] adm · «Quién puede hacer… Corte» (personal_actividad): Ana por la cuadrilla, Beto propia y cuadrilla`, t.includes("2 personas pueden hacer «Corte»") && /ZT Ana Prueba · cuadrilla ZT Cuadrilla Norte/.test(t) && /ZT Beto Prueba · propia y cuadrilla ZT Cuadrilla Norte/.test(t), t);
    // Quitar a Beto el Reparto propio y sacarlo de la cuadrilla: un solo motivo
    await clicEn(pg, `li.rv-per-tarjeta[data-persona="${E.beto}"]`, "Editar"); await pg.waitForSelector(".rv-modal [data-campo=cuadrilla]");
    await escribir(pg, ".rv-modal [data-campo=cuadrilla]", ""); await marcar(pg, ".rv-modal input[data-actividad=reparto]");
    await escribir(pg, ".rv-modal textarea", "Pasa a la oficina de facturación"); await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await cerrado(pg); await esp(600);
    beto = await tarjeta(pg, E.beto);
    ok(`[${ancho}] adm · Beto sale de la cuadrilla (con motivo) y se le quita Reparto: conserva Corte propia`, beto.includes("Sin cuadrilla") && /Corte\s*· propia\b/.test(beto) && !beto.includes("Reparto") && !beto.includes("Suspensión"), beto);
    ok(`[${ancho}] adm · los eventos quedaron en la base con su motivo (solo inserción)`, Number(sqlq(`select count(*) from campo.personal_eventos where persona = '${E.beto}' and motivo = 'Pasa a la oficina de facturación'`)) >= 2);
    t = await texto(pg, ".rv-per-hist");
    ok(`[${ancho}] adm · historial con los textos nuevos desde la Edge (área, cuadrilla, actividad propia)`, t.includes("Área: «Pérdidas»") && t.includes("Actividad propia: asignó «Lectura»") && t.includes("Actividad propia: quitó «Reparto»") && t.includes("Motivo: Pasa a la oficina de facturación"), t.slice(0, 700));
    ok(`[${ancho}] adm · Personal sin desborde horizontal`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `edge_personal_${ancho}_admin.png`), fullPage: ancho < 500 });
    // Desactivar la cuadrilla con un miembro: 409 en singular
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector(`[data-cuadrilla="${norte}"]`); await esp(300);
    await clicEn(pg, `[data-cuadrilla="${norte}"]`, "Desactivar"); await pg.waitForSelector(".rv-modal textarea");
    ok(`[${ancho}] adm · aviso antes de desactivar una cuadrilla con 1 miembro («sáquelo»)`, (await texto(pg, ".rv-modal")).includes("La cuadrilla tiene 1 miembro: sáquelo en Personal"));
    await escribir(pg, ".rv-modal textarea", "Se reorganizan las cuadrillas"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await pg.waitForSelector(".rv-modal .rv-error");
    ok(`[${ancho}] adm · si igual se intenta: el 409 de la Edge «La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla»`, (await texto(pg, ".rv-modal .rv-error")).includes("La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla"), await texto(pg, ".rv-modal"));
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    await clicEn(pg, `[data-cuadrilla="${sur}"]`, "Desactivar"); await pg.waitForSelector(".rv-modal textarea");
    await escribir(pg, ".rv-modal textarea", "Fue una cuadrilla de prueba"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await cerrado(pg); await esp(500);
    ok(`[${ancho}] adm · desactivar la vacía: queda inactiva en la base y sale de la lista`, sqlq(`select activa from campo.cuadrillas where id = ${sur}`) === "f" && !(await pg.$(`[data-cuadrilla="${sur}"]`)));
    await pg.evaluate(() => [...document.querySelector(`[data-cuadrilla]`).closest("[data-testid=cuadrillas]").querySelectorAll("label.rv-check")].find((l) => l.textContent.includes("Mostrar las desactivadas")).querySelector("input").click());
    await pg.waitForSelector(`[data-cuadrilla="${sur}"]`); await esp(200);
    await clicEn(pg, `[data-cuadrilla="${sur}"]`, "Volver a activar"); await esp(800);
    ok(`[${ancho}] adm · «Volver a activar»`, sqlq(`select activa from campo.cuadrillas where id = ${sur}`) === "t");
    await pg.evaluate((id) => [...document.querySelector(`[data-cuadrilla="${id}"]`).querySelectorAll("button")].find((b) => b.textContent.includes("historial")).click(), norte);
    await pg.waitForSelector(`[data-cuadrilla="${norte}"] [data-testid=cua-historial] li`); await esp(300);
    t = await texto(pg, `[data-cuadrilla="${norte}"] [data-testid=cua-historial]`);
    ok(`[${ancho}] adm · historial de la cuadrilla (Edge real): creada, actividades, quién entró y quién salió`,
      t.includes("Creó la cuadrilla") && /agregó «(Corte|Suspensión)»/.test(t) && t.includes("Entró a la cuadrilla «ZT Cuadrilla Norte»") && t.includes("Salió de la cuadrilla «ZT Cuadrilla Norte»") && t.includes("ZT Beto Prueba"), t);
    ok(`[${ancho}] adm · Cuadrillas sin desborde horizontal`, await sinDesborde(pg));
    await pg.close();

    // ===== Supervisor de campo =====
    pg = await abrir("sup", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector(`li.rv-per-tarjeta[data-persona="${E.sup}"]`); await esp(300);
    t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] sup · «Usted puede» sin área ni cargo (puede de la Edge)`, /Usted puede: poner a cada persona en una cuadrilla, darle actividades propias y elegir sus formularios/.test(t), t.slice(0, 300));
    const suya = await tarjeta(pg, E.sup);
    ok(`[${ancho}] sup · su ficha: «Usted» y «Es su ficha: no la puede cambiar», sin «Editar»`, suya.includes("Usted") && suya.includes("Es su ficha") && !/\bEditar\b/.test(suya), suya);
    await clicEn(pg, `li.rv-per-tarjeta[data-persona="${E.ana}"]`, "Editar"); await pg.waitForSelector(".rv-modal [data-campo=actividades]");
    ok(`[${ancho}] sup · el diálogo no trae área ni cargo`, await pg.evaluate(() => !document.querySelector(".rv-modal [data-campo=area]") && !document.querySelector(".rv-modal").innerText.includes("Cargo")));
    await marcar(pg, ".rv-modal input[data-actividad=revision_pqr]"); await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await cerrado(pg); await esp(600);
    ok(`[${ancho}] sup · da una actividad propia (Revisión PQR) y queda en la base`, /Revisión PQR\s*· propia/.test(await tarjeta(pg, E.ana)));
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-cuadrilla]"); await esp(300);
    ok(`[${ancho}] sup · Cuadrillas: puede crear; NO ve «Áreas y actividades»`, (await texto(pg, "[data-testid=cuadrillas]")).includes("Crear cuadrilla") && !(await pg.$("[data-testid=catalogos]")));
    await pg.close();

    // ===== Supervisor de actas: solo ve (Personal y Cuadrillas sueltos; su entrada va con las actas) =====
    pg = await abrir("act", ancho, "&suelto=1");
    await pg.waitForSelector(`li.rv-per-tarjeta[data-persona="${E.ana}"]`); await pg.waitForSelector("[data-cuadrilla]"); await esp(300);
    t = await texto(pg, "body");
    ok(`[${ancho}] supervisor de actas · Personal y Cuadrillas en solo lectura desde la Edge (sin Editar, Crear ni Desactivar)`, (t.match(/Solo lectura\./g) || []).length === 2 && !/\bEditar\b|Crear cuadrilla|\bDesactivar\b|Revertir/.test(t) && t.includes("ZT Cuadrilla Norte"), t.slice(0, 500));
    await pg.screenshot({ path: join(CAP, `edge_actas_${ancho}_solo_lectura.png`), fullPage: ancho < 500 });
    await pg.close();
  }
  // Las RPC nuevas, con los topes de producción (local; producción es ~6 veces más lenta)
  const lentas = rpcs.filter((r) => !r.error).sort((a, b) => b.ms - a.ms).slice(0, 3);
  ok(`ninguna RPC llamó a algo desconocido y ninguna tardó más de 2 s en local (más lentas: ${lentas.map((r) => `${r.fn} ${r.ms} ms`).join(", ")})`, desconocidas.length === 0 && lentas.every((r) => r.ms < 2000), JSON.stringify({ desconocidas }));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700));
  if (ultima) { console.log("Pantalla:", (await ultima.evaluate(() => document.body.innerText).catch(() => "")).slice(0, 900)); await ultima.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); }
  console.log("RPC con error:", JSON.stringify(rpcs.filter((r) => r.error).slice(-3)), "Edge:", edgeLog.slice(-600)); }
await nav.close(); srv.close(); edge.kill();
console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
