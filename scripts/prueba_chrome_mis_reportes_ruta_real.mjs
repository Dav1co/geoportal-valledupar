// Prueba en Chrome REAL de «Mis reportes» con la ruta levantar_mios DE VERDAD (Code A, 19-nov), a 390 px (táctil) y 1280 px: la pantalla del Code B
// (rama tecnica-campo-mis-reportes; su prueba simula la ruta) contra la Edge geoportal-redes real en Deno y una base con el paquete sql/redes_levantar_mios.
// Comprueba que el contrato de la ruta es el que la pantalla espera: la tarjeta aparece sola, la lista trae solo lo propio con su estado de hoy y los periodos piden lo suyo.
// Mismo andamio que scripts/prueba_chrome_mis_reportes.mjs (del Code B). El puerto de la base va en PGPORT_B y la página en RAIZ_UI (el árbol con la pantalla).
// Uso: PGPORT_B=<puerto> RAIZ_UI=<árbol con «Mis reportes»> node scripts/prueba_chrome_mis_reportes_ruta_real.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla con el paquete> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_mis_reportes_ruta_real"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_mis_reportes.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_15> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANTES = false;
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54989, P_EDGE = 54990;      // puertos de Code A (54971–54996)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", campo: "zt.campo@emdupar.gov.co", nada: "zt.nada@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.op]: "operador", [EMAILS.op2]: "operador", [EMAILS.planta]: "supervisor" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.op]: ["danos_fallas"], [EMAILS.op2]: ["danos_fallas"], [EMAILS.planta]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención" };
// cada ancho arranca de una copia limpia de la plantilla, con la persona de Comercial y el formulario asignado al operador (como lo haría el supervisor en Personal)
function rehacer() {
  execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('${EMAILS.campo}', 'ZT Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos') on conflict do nothing`);
  if (!ANTES) sqlq(`select public.geoportal_redes_personal_formulario('${EMAILS.dist}', '${EMAILS.op}', 'activo_campo', true, 'Sale a campo a levantar activos')`);
  if (!ANTES) sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'area', 'distribucion', 'Sale a campo con la cuadrilla'), public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'cargo', 'Fontanero', 'Cargo de la persona')`);
  if (!ANTES && sqlq(`select tecnica.f_formulario_asignado('${EMAILS.op}', 'danos_fallas')`) !== "t") sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'danos_fallas', '${EMAILS.adm}')`);
}
rehacer();
// el lugar de la prueba: una válvula real con activos de acueducto y de alcantarillado a menos de 15 m
const LUGAR = (() => {
  const f = sqlq(`select m.codigo || '|' || round(ST_Y(m.geom)::numeric, 6) || '|' || round(ST_X(m.geom)::numeric, 6) from redes.activo_vigente_mat m
    where m.prefijo = 'VAL' and not m.retirado and not m.oculto
      and (select count(*) from redes.activo_vigente_mat x where x.sistema = 'acueducto' and not x.retirado and not x.oculto and x.geom && ST_Expand(m.geom, 0.0003) and ST_DWithin(x.geom::geography, m.geom::geography, 15)) between 3 and 8
      and (select count(*) from redes.activo_vigente_mat x where x.sistema = 'alcantarillado' and not x.retirado and not x.oculto and x.geom && ST_Expand(m.geom, 0.0003) and ST_DWithin(x.geom::geography, m.geom::geography, 15)) between 2 and 8
    order by m.codigo limit 1`).split("|");
  return { val: f[0], lat: Number(f[1]), lon: Number(f[2]) };
})();
const cuenta = (sis, radio) => Number(sqlq(`select count(*) from redes.activo_vigente_mat x where x.sistema = '${sis}' and not x.retirado and not x.oculto and ST_DWithin(x.geom::geography, ST_SetSRID(ST_MakePoint(${LUGAR.lon}, ${LUGAR.lat}), 4326)::geography, ${radio})`));

// ---------- 1. Paquete de la página (?area=campo monta Formatos de campo; si no, Técnica) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_misrep_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    import { AreaCampo } from "./src/campo/AreaCampo.tsx";
    const campo = new URLSearchParams(location.search).get("area") === "campo";
    createRoot(document.getElementById("raiz")).render(campo ? <AreaCampo correo="persona@emdupar.gov.co" /> : <AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth, Storage y PostgREST simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], desconocidas = [], subidas = [];
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcOtras(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: false })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_avisos": if (a.p_solicitante === EMAILS.dist) {      // Etapa 2: los avisos de distribución salen de la base (tecnica.f_avisos con el bloque del Corte 14)
      const av = JSON.parse(sqlq("select tecnica.f_avisos(false, true)"));
      return { areas: { planta: false, distribucion: true, personal: true }, admin: false, avisos: av, total: av.length, rojos: av.filter((x) => x.nivel === "rojo").length, naranjas: av.filter((x) => x.nivel === "naranja").length, calculado_en: new Date().toISOString(), ms: 1 };
    }
    return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
    case "geoportal_campo_obtener_formulario": return a.p_solicitante === EMAILS.campo
      ? { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: true, supervisar: false, administrar_catalogo: false }, limites: { max_fotos: 6, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg" },
          zona: { lat_min: 10.1, lat_max: 10.8, lon_min: -73.6, lon_max: -72.9 }, grupos: [] }
      : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } };
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/redes-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/redes-evidencias/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT", "Access-Control-Allow-Headers": "content-type, x-upsert" }); return res.end(); }
      if (req.method === "PUT") {
        if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" });
        subidas.push({ ruta, bytes: cuerpo.length, mime: req.headers["content-type"] });
        sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', ${lit(ruta)}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })}) on conflict do nothing`);
        return json(200, { Key: `redes-evidencias/${ruta}` });
      }
    }
    if (u.pathname.startsWith("/storage/v1/object/sign/redes-evidencias/")) {      // lectura firmada (60 s)
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      return json(200, { signedURL: `/object/leer/redes-evidencias/${ruta}?token=l-${ruta.length}` });
    }
    if (u.pathname.startsWith("/storage/v1/object/leer/")) { res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(PNG); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcOtras(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (Técnica, redes y campo) ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const p = new URL(r.url).pathname; return (p.includes("geoportal-redes") ? hs[1] : p.includes("geoportal-campo") ? hs[2] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 400))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
const texto = (p) => p.evaluate(() => document.body.innerText);
const TABS_MODO = '[role=tablist][aria-label="Modo de trabajo"] [role=tab]';
const esperarTexto = async (p, re, ms = 30000) => {
  const fin = Date.now() + ms;
  for (;;) {
    const esta = await p.evaluate(async (s, sel) => {
      const r = new RegExp(s); if (r.test(document.body.innerText)) return true;
      if (!document.querySelector("[data-modo-actual]")) return false;
      for (const t of document.querySelectorAll(sel)) { t.click(); await new Promise((x) => setTimeout(x, 0)); if (r.test(document.body.innerText)) return true; }
      return false; }, re.source, TABS_MODO).catch(() => false);
    if (esta) return;
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1200)} · errores: ${errores.join(" | ").slice(0, 800)}`); }
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
const textoInicio = (p) => p.evaluate(async (sel) => {
  const tabs = [...document.querySelectorAll(sel)]; if (!tabs.length) return document.body.innerText;
  let s = ""; for (const t of tabs) { t.click(); await new Promise((x) => setTimeout(x, 0)); s += document.body.innerText + "\n"; }
  tabs[0].click(); await new Promise((x) => setTimeout(x, 0)); return s; }, TABS_MODO);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const clic = (p, sel) => p.evaluate((sel) => { const b = document.querySelector(sel); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const captura = async (p, nombre, completa = true) => { await new Promise((r) => setTimeout(r, 350)); await p.screenshot({ path: join(CAP, nombre), fullPage: completa }); };
async function abrir(ancho, rol, area, precision = 6, pos = LUGAR) {
  const p = await nav.newPage(); pagina = p;
  await p.setGeolocation({ latitude: pos.lat, longitude: pos.lon, accuracy: precision });
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(60000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${area ? "&area=" + area : ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
let pagina = null;
const diagnostico = async (e) => {      // una espera que no llega: se dice qué había en pantalla y qué errores hubo
  console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 300) + " · errores: " + errores.join(" | ").slice(0, 900) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-700).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {});
  try { edge.kill(); } catch { /* ya terminó */ }
  process.exit(1);
};

// ---------- 5. Ayudantes ----------
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
/** Un punto por levantar, creado por las RPC reales (como lo deja el formulario). `norte` y `este` en metros desde el lugar de la prueba. */
function crearLev(email, servicio, tipo, norte, este, obs = null) {
  const lat = Number((LUGAR.lat + norte / 110574).toFixed(7)), lon = Number((LUGAR.lon + este / (111320 * Math.cos(LUGAR.lat * Math.PI / 180))).toFixed(7));
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_levantar_preparar('${email}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const r = JSON.parse(sqlq(`select public.geoportal_redes_levantar_crear('${email}', '${prep.punto_id}', ${lit({ servicio, tipo, observacion: obs, lat, lon, precision_m: 5, fotos: [{ n: 1, ruta: prep.fotos[0].ruta }], no_es_duplicado: true })})`));
  if (!r.creado) throw new Error("no se creó el punto: " + JSON.stringify(r));
  return r.codigo;
}
async function aPorLevantar(p) {
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /Por verificar/);
  await clicTexto(p, "[role=tab]", "Por verificar"); await p.waitForSelector('[data-grupo="levantar"]', { timeout: 30000 }); await clic(p, '[data-grupo="levantar"]');
  await p.waitForSelector("[data-testid=lev-bandeja] [data-levantar]", { timeout: 30000 });
}
const punto = (p, c) => p.evaluate((c) => { const s = document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"]`); if (!s) return null; const r = s.querySelector("[data-testid=lev-repetido]");
  return { estado: s.dataset.estado, repetido: r ? r.querySelector("p").textContent : null, original: r?.dataset.original ?? null, botones: [...(r?.querySelectorAll("button") ?? [])].map((b) => b.textContent.trim()) }; }, c);
const enPunto = (p, c, sel) => p.evaluate((c, sel) => { const b = document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"] ${sel}`); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, c, sel);
const visibles = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=lev-bandeja] [data-levantar]")].map((x) => x.dataset.levantar));
const altoMin = (p, sel) => p.evaluate((s) => Math.min(...[...document.querySelectorAll(s)].filter((b) => b.offsetParent).map((b) => b.getBoundingClientRect().height)), sel);
const MIOS = (cods) => ({ dias: 30, total: cods.length, recortada: false, items: cods.map((c, i) => ({ codigo: c, registrado_en: new Date(Date.now() - i * 86400000).toISOString(), servicio: "alcantarillado", tipo: "pozo", tipo_nombre: "Pozo",
  estado: i === 1 ? "descartado" : "reportado", estado_nombre: i === 1 ? "Descartado" : "Reportado", estado_desde: new Date().toISOString(), activo: null })) });


try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  let p, t;
  if (sqlq("select coalesce(to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)')::text, '')") === "") throw new Error("la plantilla no tiene el paquete redes_levantar_mios");
  // dos reportes del operador hoy, uno de hace 40 días (inserción directa: la fecha no se puede cambiar) y uno ajeno
  const P1 = crearLev(EMAILS.op, "alcantarillado", "pozo", 60, 0, "ZT pozo de la esquina"), P2 = crearLev(EMAILS.op, "acueducto", "valvula", 120, 0), AJENO = crearLev(EMAILS.adm, "alcantarillado", "pozo", 180, 0);
  sqlq(`insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
        select gen_random_uuid(), 'LEV-980001', 'acueducto', 'hidrante', lat, lon + 0.002, ST_Translate(geom, 0.002, 0), 5, false, 'tecnica', '${EMAILS.op}', clock_timestamp() - interval '40 days' from redes.levantar_puntos where codigo = '${P1}'`);
  const pedidos = [];
  p = await abrir(ancho, "op");
  p.on("response", (q) => { const u = q.url(); if (u.includes("accion=levantar_mios") && q.request().method() === "GET") pedidos.push(`${new URL(u).searchParams.get("dias")}:${q.status()}`); });
  await esperarTexto(p, /Encontrar o reportar activo/); await clic(p, '[data-tarjeta="activo_campo"]'); await p.waitForSelector("[data-testid=enc-mios-entrada]", { timeout: 40000 });
  ok(A("R1 con la ruta real, la tarjeta «Mis reportes» aparece sola y dice «Ver mis reportes (2 en los últimos 30 días)»"), (await p.$eval("[data-testid=enc-mios]", (e) => e.textContent)) === "Ver mis reportes (2 en los últimos 30 días)", await p.$eval("[data-testid=enc-mios]", (e) => e.textContent));
  await clic(p, "[data-testid=enc-mios]"); await p.waitForSelector("[data-testid=enc-mios-lista] [data-mio]");
  const filas = () => p.evaluate(() => [...document.querySelectorAll("[data-testid=enc-mios-lista] [data-mio]")].map((x) => ({ c: x.dataset.mio, e: x.dataset.estado, t: x.innerText.replace(/\n/g, " ") })));
  t = await filas();
  ok(A("R2 la lista de 30 días: sus 2 reportes, el último primero, con tipo, servicio, «Reportado» y la fecha; el ajeno y el viejo no"), t.map((x) => x.c).join() === [P2, P1].join() && t.every((x) => x.e === "reportado" && /Reportado\s+Reportado el \d+ de \w+ de \d{4}/.test(x.t))
     && /de acueducto/.test(t[0].t) && /de alcantarillado/.test(t[1].t) && !t.some((x) => /@|undefined|null|Invalid/.test(x.t)), JSON.stringify(t));
  ok(A("R3 la lista no desborda y sus botones miden 44 px o más"), (await sinDesborde(p)) && (await altoMin(p, "[data-testid=enc-mios-lista] button")) >= 44);
  await captura(p, `mis_reportes_ruta_real_${ancho}.png`);
  // el supervisor descarta uno: al volver a pedir, «Mis reportes» lo dice
  sqlq(`select public.geoportal_redes_levantar_evento('${EMAILS.dist}', '${P1}', 'descartado', null, 'ZT repetido de otro reporte', '127.0.0.1')`);
  await clic(p, '[data-testid=enc-mios-lista] [data-dias="90"]'); await p.waitForFunction(() => document.querySelectorAll("[data-testid=enc-mios-lista] [data-mio]").length === 3, { timeout: 15000 }).catch(() => {});
  t = await filas();
  ok(A("R4 «Últimos 90 días»: entran los 3 (también el de hace 40 días) y el descartado ya dice «Descartado», sin el motivo"), t.map((x) => x.c).join() === [P2, P1, "LEV-980001"].join() && t[1].e === "descartado" && /Descartado/.test(t[1].t) && !/repetido/.test(t[1].t) && /Hidrante/i.test(t[2].t), JSON.stringify(t));
  await clic(p, '[data-testid=enc-mios-lista] [data-dias="0"]'); await pausa(1500); t = await filas();
  ok(A("R5 «Todos»: los mismos 3, nunca el ajeno; la pantalla pidió 30, 90 y 0 y la ruta respondió 200 cada vez"), t.length === 3 && !t.some((x) => x.c === AJENO) && ["30:200", "90:200", "0:200"].every((x) => pedidos.includes(x)) && !pedidos.some((x) => !x.endsWith(":200")), JSON.stringify(pedidos));
  ok(A("R6 «Ver acta (PDF)» de un reporte propio de la lista abre su acta (la ruta publicada)"), await clic(p, `[data-mio="${P2}"] [data-testid=enc-mio-acta]`) && !!(await p.waitForFunction((c) => new RegExp(c).test(document.body.innerText) && !document.querySelector(".tec-aviso-error"), { timeout: 30000 }, P2).catch(() => null)));
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC desconocida", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
