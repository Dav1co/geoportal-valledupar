// [Code B] Investigación y Análisis (23-nov) · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   pantallas reales (AnalisisContrato, ActasRegistradas → Actividades derivadas, FormularioFormato de la Investigación) → Edges REALES geoportal-campo y geoportal-acta
//   (Deno, de ~/geoportal-web-inv-analisis) → PostgREST mínimo en Node que llama a las RPC REALES de la base local del Code B (55442) con el paquete SQL migrado:
//   la base es copia exacta de producción (rehacer_doble.py, 163 de 163) y cada RPC corre como service_role con statement_timeout 30 s y lock_timeout 8 s.
// A 390 px y a 1280 px: el analista marca las 4 observaciones (con la dirección correcta y los datos de contacto) y no vuelve a ver los datos; el supervisor ve los
// avisos con el filtro Origen, abre los datos (auditado), los anula, crea la Investigación desde «Dirección errada»; el operario la registra SIN fotos y sin los
// opcionales eligiéndola en «¿Viene de…?», y queda atendida. Sin desborde horizontal, nada personal en localStorage ni sessionStorage.
//   node scripts/prueba_chrome_inv_analisis.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55985 (app, Auth y PostgREST) y 55986 (Edges). No prueba: Supabase, un celular físico ni la cámara (headless no tiene).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";
const USO = "Uso: node scripts/prueba_chrome_inv_analisis.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, CAP_ARG] = args;
if (!FUNCIONES) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_inv_analisis")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55985, P_EDGE = 55986, DB = "emdupar_b_inv_chrome";
const PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql";
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432" || PGENV.PGPORT === "55452") { console.error("Ese clúster es de otro Code: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const E = { ana: "ztch.ana@emdupar.gov.co", sup: "ztch.sup@emdupar.gov.co", op: "ztch.op@emdupar.gov.co", adm: "ztch.adm@emdupar.gov.co" };

// ---------- 1. Base: copia exacta de producción + el paquete migrado + datos propios (ZTCH) ----------
const PAQ = join(raiz, "sql/campo_inv_analisis");
execFileSync("python3", ["-I", "-B", join(PAQ, "pruebas_locales/rehacer_doble.py"), "--csv", join(homedir(), "geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv"), "--db", DB],
  { env: { ...process.env, PGPORT_B: PGENV.PGPORT }, stdio: ["ignore", "pipe", "pipe"] });
execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-f", join(PAQ, "migracion_campo_inv_analisis_editor.sql")], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_analisis_contrato) values
  ('${E.ana}', 'ZTCH Analista', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true), ('${E.sup}', 'ZTCH Supervisora de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false),
  ('${E.op}', 'ZTCH Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false), ('${E.adm}', 'ZTCH Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false)`);

// ---------- 2. La app (esbuild) con un doble de lib/supabase que da el token del rol ----------
const dir = mkdtempSync(join(tmpdir(), "ui_invanalisis_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => ({ error: { message: "sin storage en esta prueba" } }) }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React, { useEffect, useState } from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import AnalisisContrato from "./src/campo/analisis/AnalisisContrato.tsx";
    import { ActasRegistradas } from "./src/campo/documentos/ActasRegistradas.tsx";
    import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx";
    import { apiCampo } from "./src/campo/apiCampo.ts";
    function Formato() {
      const [x, setX] = useState(null);
      useEffect(() => { apiCampo.formulario().then((def) => { const tipo = def.grupos.flatMap((g) => g.tipos).find((t) => t.codigo === "investigacion_ubicacion"); setX({ def, tipo }); }); }, []);
      return x ? <FormularioFormato def={x.def} tipo={x.tipo} correo="${E.op}" onVolver={() => {}} onOtro={() => {}} /> : <p>Cargando…</p>;
    }
    const q = new URLSearchParams(location.search), p = q.get("p"), rol = q.get("rol");
    const raizApp = createRoot(document.getElementById("raiz"));
    if (p === "analisis") raizApp.render(<div className="campo-contenedor com-modulo"><AnalisisContrato onVolver={() => {}} /></div>);
    if (p === "actas") raizApp.render(<div className="com-modulo"><ActasRegistradas correo={rol + "@prueba"} onVolver={() => {}} nombres={new Map()} puedeAperturas={false} puedeCerrarDerivadas={rol === "sup" || rol === "adm"} /></div>);
    if (p === "formato") raizApp.render(<div className="campo-contenedor com-modulo"><Formato /></div>);
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
      { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
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
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 40000); });

// ---------- 5. Chrome ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 600)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 300000, args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation"]);
let ultima = null;
async function abrir(p, rol, ancho) {
  const pg = await nav.newPage(); ultima = pg;
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.setGeolocation({ latitude: 10.46, longitude: -73.25, accuracy: 8 });
  await pg.goto(`http://127.0.0.1:${P_BASE}/?p=${p}&rol=${rol}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(400);
  return pg;
}
const texto = (pg, sel = "body") => pg.$eval(sel, (e) => e.innerText);
const hay = (pg, sel) => pg.$(sel).then((x) => !!x);
const clic = (pg, sel) => pg.evaluate((s) => { const b = document.querySelector(s); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : i.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const esperar = (pg, f, ...a) => pg.waitForFunction(f, { timeout: 15000 }, ...a).then(() => true).catch(() => false);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const almacenLimpio = (pg) => pg.evaluate(() => { const t = JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }); return !/1065123456|3001234567|persona@ejemplo|ZTCH Persona/i.test(t); });
const foto = (pg, n) => pg.screenshot({ path: join(CAP, n + ".png"), fullPage: true });
const PERSONAL = /1065123456|3001234567|persona@ejemplo|ZTCH Persona/i;

async function consultar(pg, contrato) {
  await escribir(pg, "#ac-contrato", contrato); await clicTexto(pg, "button", "Consultar");
  return esperar(pg, () => !!document.querySelector('[data-testid="observacion"]'));
}
async function observar(pg, tipo, llenar) {
  await clic(pg, `input[data-obs="${tipo}"]`); await esp(150);
  if (llenar) await llenar();
  const habilitado = await pg.$eval("[data-obs-pedir]", (b) => !b.disabled).catch(() => false);
  if (!habilitado) return { habilitado };
  await clic(pg, "[data-obs-pedir]"); await esperar(pg, () => !!document.querySelector("[data-obs-enviar]")); await clic(pg, "[data-obs-enviar]");
  await esperar(pg, () => !!document.querySelector("[data-obs-aviso]"));
  return { habilitado, aviso: await pg.$eval("[data-obs-aviso]", (e) => e.textContent).catch(() => "") };
}

try {
  // ===== A. El analista marca las 4 observaciones (390 px) =====
  let pg = await abrir("analisis", "ana", 390);
  ok("A01 (390) el analista consulta el contrato y ve «Observación sobre este contrato» al final de la ficha", await consultar(pg, "123456"), await texto(pg));
  let r = await observar(pg, "desocupado");
  ok("A02 «Desocupado» → confirmar → «Quedó en la lista del supervisor»", r.habilitado && /Quedó en la lista del supervisor: «Desocupado»/.test(r.aviso), JSON.stringify(r));
  r = await observar(pg, "direccion_errada", () => escribir(pg, "#ac-obs-dir", "[PRUEBA ZTCH] CRA 9 # 12-30"));
  ok("A03 «Dirección errada» con la dirección correcta", r.habilitado && /Dirección errada/.test(r.aviso), JSON.stringify(r));
  r = await observar(pg, "direccion_errada", () => escribir(pg, "#ac-obs-dir", "[PRUEBA ZTCH] CRA 10 # 1-1"));
  ok("A03b repetir «Dirección errada» con el aviso pendiente: «Ya hay un aviso pendiente… No se creó otro. Lo que escribió no se guardó.»",
    /Ya hay un aviso pendiente «Dirección errada» para este contrato \(avisado el .*\)\. No se creó otro\. Lo que escribió no se guardó\./.test(r.aviso ?? ""), JSON.stringify(r));
  await clic(pg, 'input[data-obs="actualizacion_datos"]'); await esp(150);
  ok("A04 «Actualización de datos» muestra las 5 casillas opcionales con la marca «dato personal»", await hay(pg, "#ac-obs-nombre") && await hay(pg, "#ac-obs-cedula") && await hay(pg, "#ac-obs-tel")
    && await hay(pg, "#ac-obs-correo") && await hay(pg, "#ac-obs-rel") && /dato personal/.test(await texto(pg, '[data-testid="observacion"]')));
  await escribir(pg, "#ac-obs-tel", "2123456789"); await esp(150);
  ok("A05 un teléfono que no cumple (10 que empieza por 2): se avisa y no se deja enviar", await pg.$eval("[data-obs-pedir]", (b) => b.disabled)
    && /7 o 10 números/.test(await texto(pg, '[data-testid="observacion"]')));
  await foto(pg, "A05_datos_390");
  r = await observar(pg, "actualizacion_datos", async () => {
    await escribir(pg, "#ac-obs-nombre", "ZTCH Persona"); await escribir(pg, "#ac-obs-cedula", "1065123456"); await escribir(pg, "#ac-obs-tel", "300 123 4567");
    await escribir(pg, "#ac-obs-correo", "Persona@Ejemplo.com"); await escribir(pg, "#ac-obs-rel", "propietario"); await esp(150); });
  ok("A06 con los 5 datos se envía y dice que solo los verá el supervisor", r.habilitado && /solo los verá el supervisor/.test(r.aviso), JSON.stringify(r));
  ok("A07 al enviar, los datos de contacto ya no están en la pantalla", !PERSONAL.test(await texto(pg)) && !(await hay(pg, "#ac-obs-cedula")));
  r = await observar(pg, "otra", () => escribir(pg, "#ac-obs-texto", "llamar al 3001234567"));
  ok("A08 «Otra» con un teléfono no se deja enviar", !r.habilitado);
  r = await observar(pg, "otra", () => escribir(pg, "#ac-obs-texto", "[PRUEBA ZTCH] perro bravo"));
  ok("A09 «Otra» con texto corto se envía", r.habilitado && /«Otra»/.test(r.aviso), JSON.stringify(r));
  r = await observar(pg, "desocupado");
  ok("A10 repetir «Desocupado» (sección 7): «Ya se avisó … el <fecha> (pendiente)» y no se crea otro", /Ya se avisó «Desocupado» el \d{1,2} de \w+ de \d{4} \(pendiente\)\. No se creó otro aviso/.test(r.aviso ?? ""), JSON.stringify(r));
  ok("A11 (390) sin desborde horizontal", await sinDesborde(pg)); await foto(pg, "A11_analisis_390");
  ok("A12 nada personal en localStorage ni sessionStorage", await almacenLimpio(pg));
  ok("A13 en la base: 4 observaciones y los datos de contacto aparte, con el correo en minúsculas",
    sqlq(`select count(*) from campo.analisis_observaciones where autor = '${E.ana}'`) === "4"
    && sqlq(`select x.datos ->> 'correo' from campo.analisis_observacion_datos x join campo.analisis_observaciones o on o.id = x.observacion_id where o.autor = '${E.ana}'`) === "persona@ejemplo.com");
  await pg.close();
  pg = await abrir("analisis", "ana", 1280);
  ok("A14 (1280) la tarjeta se ve en escritorio, sin desborde", await consultar(pg, "123456") && await sinDesborde(pg)); await foto(pg, "A14_analisis_1280");
  await pg.close();
  pg = await abrir("actas", "ana", 1280);
  ok("A15 el analista no tiene la pestaña «Actividades derivadas»", await pg.evaluate(() => ![...document.querySelectorAll("button, [role=tab]")].some((b) => b.textContent.trim() === "Actividades derivadas")), await texto(pg));
  await pg.close();

  // ===== B. El supervisor de campo (1280 y 390) =====
  pg = await abrir("actas", "sup", 1280);
  await clicTexto(pg, "button, [role=tab]", "Actividades derivadas");
  ok("B01 el supervisor abre «Actividades derivadas»", await esperar(pg, () => !!document.querySelector('[data-testid="derivadas"]')));
  await escribir(pg, 'select[data-filtro="origen"]', "analisis");
  ok("B02 con Origen = Análisis de contrato ve los 4 avisos", await esperar(pg, () => document.querySelectorAll('[data-origen="analisis"]').length === 4), await texto(pg));
  let t = await texto(pg, '[data-testid="derivadas"]');
  ok("B03 cada aviso dice de dónde viene (Análisis de contrato · observación · quién) y la lista NO trae los datos de contacto",
    /Análisis de contrato · Dirección errada/.test(t) && /Aviso: actualización de datos/.test(t) && /Sí \(se ven al abrirlos\)/.test(t) && !PERSONAL.test(t), t.slice(0, 900));
  ok("B04 muestra la dirección correcta y el texto de «Otra»", /\[PRUEBA ZTCH\] CRA 9 # 12-30/.test(t) && /perro bravo/.test(t));
  const idDes = sqlq(`select d.id from campo.derivadas d where d.actividad = 'aviso_desocupado' and d.contrato = '123456'`);
  const tDes = await texto(pg, `[data-derivada="${idDes}"]`);
  ok("B04b (sección 7) el aviso muestra su antigüedad («hoy») y «Visto otra vez: 1 vez · último … por el analista»", /Antigüedad\s+hoy/.test(tDes) && /Visto otra vez\s+1 vez · último .* por ztch\.ana@emdupar\.gov\.co/.test(tDes), tDes);
  await foto(pg, "B04_derivadas_1280");
  const idAct = sqlq(`select d.id from campo.derivadas d where d.actividad = 'aviso_actualizacion_datos' and d.contrato = '123456'`);
  await clic(pg, `[data-derivada="${idAct}"] [data-accion="datos"]`);
  ok("B05 «Ver datos de contacto» abre los datos (lectura auditada)", await esperar(pg, () => /1065123456/.test(document.querySelector('[data-testid="datos-contacto"]')?.innerText ?? ""))
    && sqlq(`select count(*) from public.geoportal_auditoria where accion = 'campo_ver_datos_contacto' and email = '${E.sup}'`) === "1");
  t = await texto(pg, '[data-testid="datos-contacto"]');
  ok("B06 con nombre, cédula, teléfono, correo y relación", /ZTCH Persona/.test(t) && /3001234567/.test(t) && /persona@ejemplo\.com/.test(t) && /Propietario/.test(t), t);
  await foto(pg, "B06_datos_1280");
  await clic(pg, '[data-testid="datos-contacto"] [data-accion="anular"]'); await esp(150);
  await escribir(pg, '[data-testid="datos-contacto"] textarea', "[PRUEBA ZTCH] la cédula no corresponde"); await clicTexto(pg, '[data-testid="datos-contacto"] button', "Anular");
  ok("B07 al anularlos se ve «Anulados» y el motivo, sin los valores", await esperar(pg, () => { const x = document.querySelector('[data-testid="datos-contacto"]')?.innerText ?? ""; return /Anulados/.test(x) && /no corresponde/.test(x) && !/1065123456/.test(x); }));
  await clicTexto(pg, '[data-testid="datos-contacto"] button', "Cerrar"); await esp(400);
  ok("B08 al cerrar, los datos no quedan en la página ni en el navegador", !PERSONAL.test(await pg.evaluate(() => document.documentElement.outerHTML)) && await almacenLimpio(pg));
  const idDir = sqlq(`select d.id from campo.derivadas d where d.actividad = 'aviso_direccion_errada' and d.contrato = '123456'`);
  await clic(pg, `[data-derivada="${idDir}"] [data-accion="crear"]`);
  ok("B09 «Crear actividad» ofrece los formularios que piden contrato y trae elegida la Investigación", await esperar(pg, () => document.querySelector('[data-campo="formulario"]')?.value === "investigacion_ubicacion")
    && await pg.$$eval('[data-campo="formulario"] option', (o) => !o.some((x) => /Reportar posible pérdida|Posible fraude|Cambio de medidor/.test(x.textContent))));
  await foto(pg, "B09_crear_1280");
  await clicTexto(pg, '[data-testid="crear-actividad"] button', "Crear");
  ok("B10 se crea y el aviso se cierra solo", await esperar(pg, () => /Se creó «Investigación de ubicación del predio»/.test(document.body.innerText))
    && sqlq(`select campo.f_derivada_estado(${idDir})`) === "atendida_fuera", await texto(pg).then((x) => x.slice(0, 400)));
  ok("B11 (1280) sin desborde", await sinDesborde(pg));
  await pg.close();
  pg = await abrir("actas", "sup", 390);
  await clicTexto(pg, "button, [role=tab]", "Actividades derivadas"); await esperar(pg, () => !!document.querySelector('[data-testid="derivadas"]'));
  await escribir(pg, 'select[data-filtro="origen"]', "analisis"); await escribir(pg, 'select[data-filtro="estado"]', "");
  ok("B12 (390) todos los avisos y la actividad creada, con su estado", await esperar(pg, () => document.querySelectorAll('[data-origen="analisis"]').length === 5)
    && /Actividad: Investigación de ubicación del predio/.test(await texto(pg)) && /Atendida sin formulario/.test(await texto(pg)), await texto(pg).then((x) => x.slice(0, 600)));
  ok("B13 (390) sin desborde horizontal", await sinDesborde(pg)); await foto(pg, "B13_derivadas_390");
  await escribir(pg, 'select[data-filtro="origen"]', "registro");
  ok("B14 con Origen = Revisiones no aparecen", await esperar(pg, () => document.querySelectorAll('[data-origen="analisis"]').length === 0 && /No hay actividades derivadas/.test(document.body.innerText)));
  await pg.close();

  // ===== C. El operario registra la Investigación sin fotos y la atiende (390) =====
  pg = await abrir("formato", "op", 390);
  await esperar(pg, () => !!document.querySelector("#fp-contrato"));
  t = await texto(pg);
  ok("C01 la Investigación no pide efectiva/inefectiva ni causal", !(await hay(pg, 'input[name="fp-res"]')) && !/Inefectiva/.test(t), t.slice(0, 500));
  ok("C02 campos: dirección obligatoria; hallazgo, barrio, habitado, tipo de predio, medidor y observación opcionales; sin despeje ni cita",
    /Dirección encontrada en terreno \(obligatorio\)/.test(t) && /Hallazgo \(opcional\)/.test(t) && /Barrio \(opcional\)/.test(t) && /¿El predio está habitado\? \(opcional\)/.test(t)
    && /Tipo de predio \(opcional\)/.test(t) && /Número del medidor \(si se ve\) \(opcional\)/.test(t) && !/despeje/i.test(t) && !/Día y hora acordados/.test(t), t.slice(0, 1500));
  ok("C02b una sola caja de texto: «Observaciones (no escriba nombres, cédulas ni teléfonos)», sin el campo «Observación» del catálogo",
    /Observaciones \(no escriba nombres, cédulas ni teléfonos\) \(opcional\)/.test(t) && !(await hay(pg, "#fp-observacion")) && (await pg.$$("textarea")).length === 1, t.slice(0, 1500));
  ok("C03 las fotos son opcionales («0 de 6 (opcionales)») y sin cámara no bloquea", /0 de 6 \(opcionales\)/.test(t) && !/sin las fotos no se puede enviar/.test(t), t.slice(0, 1500));
  await escribir(pg, "#fp-contrato", "123456");
  ok("C04 «¿Viene de…?» ofrece la actividad que creó el supervisor, con la dirección correcta", await esperar(pg, () => /Investigación de ubicación del predio\s*· de Análisis de contrato \(Dirección errada\)/.test(document.body.innerText))
    && /dirección correcta: \[PRUEBA ZTCH\] CRA 9 # 12-30/.test(await texto(pg)), await texto(pg).then((x) => x.slice(0, 800)));
  const idNueva = sqlq(`select id from campo.derivadas where actividad = 'actividad_supervisor' and contrato = '123456'`);
  await clic(pg, `input[data-derivada="${idNueva}"]`);
  await escribir(pg, "#fp-direccion_encontrada", "[PRUEBA ZTCH] CRA 9 # 12-30");
  ok("C05 con contrato, dirección y ubicación (sin fotos ni opcionales) el botón queda habilitado", await esperar(pg, () => [...document.querySelectorAll("button")].some((b) => /Enviar reporte/.test(b.textContent) && !b.disabled)));
  await foto(pg, "C05_investigacion_390");
  ok("C06 (390) sin desborde horizontal", await sinDesborde(pg));
  await clicTexto(pg, "button", "Enviar reporte");
  ok("C07 se registra con su consecutivo INV", await esperar(pg, () => /INV/.test(document.body.innerText) && /(registr|Registr|guard)/.test(document.body.innerText)), await texto(pg).then((x) => x.slice(0, 600)));
  ok("C08 en la base: el registro sin fotos ni resultado, y la actividad quedó «atendida» por él",
    sqlq(`select count(*) from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where t.codigo = 'investigacion_ubicacion' and r.resultado is null and not exists (select 1 from campo.reporte_fotos f where f.reporte_id = r.id)`) === "1"
    && await esperar(pg, () => true) && sqlq(`select campo.f_derivada_estado(${idNueva})`) === "atendida");
  await foto(pg, "C08_registrada_390");
  await pg.close();
  pg = await abrir("formato", "op", 1280); await esperar(pg, () => !!document.querySelector("#fp-contrato"));
  ok("C09 (1280) el formulario se ve en escritorio, sin desborde", await sinDesborde(pg)); await foto(pg, "C09_investigacion_1280");
  await pg.close();
  ok("Z1 ninguna RPC tardó más de 2 s (local)", rpcs.every((x) => x.ms < 2000), JSON.stringify(rpcs.filter((x) => x.ms >= 2000)));
  ok("Z2 ninguna RPC terminó en un error inesperado", rpcs.filter((x) => x.error && !/55000|42501|P0002|22023/.test(x.error)).length === 0, JSON.stringify(rpcs.filter((x) => x.error)).slice(0, 600));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700)); if (ultima) console.log("Pantalla:", (await ultima.evaluate(() => document.body.innerText).catch(() => "")).slice(0, 700)); console.log("Edge:", edgeLog.slice(-800)); }
await nav.close(); srv.close(); edge.kill();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas${fallas ? "" : " — SIN FALLAS"}  (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
