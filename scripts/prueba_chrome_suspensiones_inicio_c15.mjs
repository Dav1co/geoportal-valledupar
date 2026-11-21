// Prueba en Chrome REAL del pase corto del Corte 15 en el inicio de Técnica (Code A, 19-nov), a 390 px (táctil) y 1280 px:
// · La tarjeta «Suspensiones» en el inicio: en Supervisión para el supervisor de distribución y en Plantas para el supervisor de planta; el operador no la tiene.
// · El aviso de un evento de suspensión abre ESE evento (desde la pantalla de Avisos y desde la franja del dashboard), y «Volver» regresa a donde estaba.
// · Al supervisor de planta solo le llega el aviso de los eventos totales.
// Mismo andamio que scripts/prueba_chrome_eventos_c15.mjs (del Code B): las Edges corren DE VERDAD en Deno y las RPC van a una base con el Corte 15 aplicado
// (la plantilla del Code B, p. ej. emdupar_b_15, o una copia suya), con el rol de la API y los topes de producción. El puerto de la base va en PGPORT_B.
// Uso: PGPORT_B=<puerto> node scripts/prueba_chrome_suspensiones_inicio_c15.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c15_inicio"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_eventos_c15.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_15> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANTES = false;
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54981, P_EDGE = 54982;      // puertos de Code A (54971–54996)
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
const dir = mkdtempSync(join(tmpdir(), "ui_c15_"));
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
  // p_sectores es text[] (planta_sectores_fijar): PostgREST lo pasa como arreglo de texto, no como jsonb
  const args = Object.entries(a).map(([k, val]) => `${k} => ${k === "p_sectores" && Array.isArray(val) ? `array[${val.map((x) => lit(String(x))).join(", ")}]::text[]` : lit(val)}`).join(", ");
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
    if (a.p_solicitante === EMAILS.planta) {      // al supervisor de planta: la base de pruebas no tiene las tablas de planta (químicos), así que tecnica.f_avisos(true, false)
      // no corre aquí. Se le dan los avisos de eventos que arma la base, dejando los TOTALES (la regla «al de planta, solo los totales» la prueba el ensayo SQL del Corte 15).
      const av = JSON.parse(sqlq("select tecnica.f_avisos(false, true)")).filter((x) => /^evento_suspension_/.test(x.clave) && sqlq(`select alcance from redes.eventos_suspension where codigo = '${x.bandeja.evento}'`) === "total").map((x) => ({ ...x, area: "planta" }));
      return { areas: { planta: true, distribucion: false, personal: true }, admin: false, avisos: av, total: av.length, rojos: av.filter((x) => x.nivel === "rojo").length, naranjas: av.filter((x) => x.nivel === "naranja").length, calculado_en: new Date().toISOString(), ms: 1 };
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

// ---------- 5. Ayudantes del Corte 15 ----------
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const SUB = "SEC-000008", SUB2 = "SEC-000009";      // Subsector 1.1 y 1.2 (sectores reales de la base)
const nf = new Intl.NumberFormat("es-CO");
const previaBase = (zona) => JSON.parse(sqlq(`select public.geoportal_redes_evento_vista_previa('${EMAILS.dist}', ${lit(zona)})::jsonb - 'zona_geojson'`));
// un tramo de acueducto dentro del Subsector 1.1, para poner un daño que el evento asocie al declararse
const [TRAMO, TLAT, TLON] = sqlq(`select m.codigo || '|' || round(ST_Y(ST_LineInterpolatePoint(ST_GeometryN(m.geom,1),0.5))::numeric,6) || '|' || round(ST_X(ST_LineInterpolatePoint(ST_GeometryN(m.geom,1),0.5))::numeric,6)
  from redes.activo_vigente_mat m join redes.activo_vigente_mat s on s.codigo = '${SUB}' and ST_Within(m.geom, s.geom) where m.prefijo = 'RED' and m.sistema = 'acueducto' and not m.retirado and not m.oculto order by m.codigo limit 1`).split("|").map((x, i) => (i ? Number(x) : x));
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
function crearDano() {
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", ubicacion_origen: "mapa", activo: TRAMO, lat: TLAT, lon: TLON,
    t_detectado: iso(-20), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`)).codigo;
}
const campoLocal = (min) => { const d = new Date(Date.now() + min * 60000), z = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`; };
async function aSuspensiones(p) {
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /No identificados/);
  await clicTexto(p, "[role=tab]", "Suspensiones"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 });
}
const opcion = (p, c) => clic(p, `[data-testid=eventos] [data-opcion="${c}"]`);
const dato = (p, d, raiz = "[data-testid=evs-previa-datos]") => p.evaluate((d, r) => document.querySelector(`${r} [data-dato="${d}"]`)?.textContent ?? null, d, raiz);
const mapaListo = (p) => p.waitForSelector("[data-testid=evs-mapa] .evs-mapa-lienzo[data-listo=si]", { timeout: 40000 });
const zonaEnMapa = (p, fuente = "zona") => p.evaluate((f) => { const m = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo")?.__mapa; const d = m?.getSource(f)?.serialize?.().data; return d && d.type === "Feature" ? d.geometry.type : d?.features?.length ? "varias" : null; }, fuente);
const pinturaMini = (p) => p.evaluate(() => { const m = document.querySelector("[data-testid=evs-mapa] .evs-mapa-lienzo").__mapa; return [m.getPaintProperty("zona-l", "line-color"), m.getPaintProperty("zona-l", "line-width"), m.getPaintProperty("zona-a", "fill-opacity"), m.getPaintProperty("zona-l", "line-dasharray") ?? null].join("|"); });
const bot = (rad, lat, lon) => JSON.parse(sqlq(`select redes.f_reporte_externo_recibir_evento(${lit({ radicado: rad, canal: "telegram", tipo: "sin_agua", lat, lon })})`));
const repCampo = (lat, lon) => { const id = sqlq(`insert into campo.reportes (id, tipo_id, lat, lon, origen, autor) select gen_random_uuid(), t.id, ${lat}, ${lon}, 'campo', '${EMAILS.campo}' from campo.tipos_reporte t where t.codigo = 'sin_agua' returning id`).split("\n")[0];
  return sqlq(`select 'REP-' || lpad(seq::text, 6, '0') from campo.reportes where id = '${id}'`); };
const eventoBase = (cod) => JSON.parse(sqlq(`select public.geoportal_redes_evento('${EMAILS.dist}', '${cod}')::jsonb - 'zona_geojson'`));
async function alGeovisor(p) { await esperarTexto(p, /Geovisor técnico/); await clicTexto(p, "button.tec-tarjeta-modo", "Geovisor técnico"); await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 }); }
const geo = (p, f, ...a) => p.evaluate(new Function("...a", `const m = document.querySelector(".geo-mapa").__mapa; return (${f})(m, ...a);`), ...a);
const visible = (p, capa) => geo(p, "(m, c) => m.getLayer(c) ? (m.getLayoutProperty(c, 'visibility') ?? 'visible') : 'no existe'", capa);
const modoGeo = async (p, n) => { await clicTexto(p, ".geo-seg button", n); await p.waitForFunction((n) => [...document.querySelectorAll(".geo-seg button")].find((b) => b.textContent.trim() === n)?.getAttribute("aria-pressed") === "true", {}, n); };
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? { capa: t.dataset.capa, txt: t.innerText, botones: [...t.querySelectorAll("button")].map((b) => b.textContent.trim()), dentro: t.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 } : null; });
const detalle = (p) => p.evaluate(() => { const d = document.querySelector("[data-testid=evs-detalle]"); if (!d) return null; return { estado: d.dataset.estado, franja: d.querySelector("[data-testid=evs-franja]").textContent, aviso: d.querySelector("[data-testid=evs-aviso]")?.textContent ?? null,
  reportes: d.querySelector('[data-dato="reportes"]').textContent, regreso: d.querySelector('[data-dato="regreso"]').textContent, fin: d.querySelector('[data-dato="fin"]')?.textContent ?? null,
  asociados: [...d.querySelectorAll("[data-asociado]")].map((x) => ({ clave: x.dataset.asociado, txt: x.innerText.replace(/\n/g, " ") })), titulo: d.querySelector("[data-testid=evs-asociados] h2").textContent,
  acciones: [...(d.querySelector("[data-testid=evs-acciones]")?.querySelectorAll("button") ?? [])].map((b) => b.textContent.trim()), historial: [...d.querySelectorAll("[data-testid=evs-historial] li")].map((x) => x.innerText.replace(/\n/g, " ")), txt: d.innerText }; });
const esperarDetalle = (p, re, ms = 40000) => p.waitForFunction((s) => new RegExp(s).test(document.querySelector("[data-testid=evs-detalle]")?.innerText ?? ""), { timeout: ms }, re.source).then(() => true).catch(() => false);
const valor = (p, sel) => p.evaluate((s) => document.querySelector(s)?.value ?? null, sel);
const edgeF = (rol, accion, o = {}) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
  headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined })
  .then(async (r) => ({ status: r.status, cache: r.headers.get("cache-control"), cuerpo: await r.json().catch(() => null) }));
const errorVisto = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=eventos] .tec-aviso-error")].map((x) => x.innerText).join(" · "));
const altoMin = (p, sel) => p.evaluate((s) => Math.min(...[...document.querySelectorAll(s)].filter((b) => b.offsetParent).map((b) => b.getBoundingClientRect().height)), sel);


// desde el corte de eventos (20-nov) declarar exige el origen: aquí, una causal de catálogo
const declarar = (quien, zona) => JSON.parse(sqlq(`select public.geoportal_redes_evento_declarar('${EMAILS[quien]}', ${lit(zona)})`)).codigo;
const enInicio = (p, modo) => p.evaluate(async (modo, sel) => {      // las tarjetas de un modo del inicio (o del único que haya)
  const tab = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim() === modo); if (tab) { tab.click(); await new Promise((x) => setTimeout(x, 50)); }
  const panel = document.querySelector("[data-modo-actual]"); if (!panel) return null;
  const unico = panel.querySelector(".tec-modo-unico")?.textContent.trim() ?? null;
  if (!tab && unico !== modo) return { modo: unico, tarjetas: [] };
  return { modo: tab ? modo : unico, tarjetas: [...panel.querySelectorAll("[data-tarjeta]")].map((x) => x.dataset.tarjeta), alto: Math.min(...[...panel.querySelectorAll("button[data-tarjeta]")].map((x) => x.getBoundingClientRect().height)),
           txt: panel.querySelector("[data-tarjeta=suspensiones]")?.innerText ?? null };
}, modo, TABS_MODO);
const barra = (p) => p.evaluate(() => ({ volver: document.querySelector("[data-testid=eventos] .tec-volver")?.textContent.trim() ?? null, titulo: document.querySelector("[data-testid=eventos] .tec-volver-tit")?.textContent.trim() ?? null, vista: document.querySelector("[data-testid=eventos]")?.dataset.vista ?? null }));
const lista = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=evs-lista] [data-evento], [data-testid=eventos] [data-evento]")].map((x) => x.dataset.evento).filter((v, i, l) => l.indexOf(v) === i).sort().join(","));
const avisoDe = (p, cod) => p.evaluate((c) => { const a = document.querySelector(`[data-aviso="evento_suspension_${c.toLowerCase()}"]`); return a ? { boton: a.querySelector(".av-abrir")?.textContent.trim() ?? null, titulo: a.querySelector("h3")?.textContent.trim() ?? null } : null; }, cod);
const avisosEvento = (p) => p.evaluate(() => [...document.querySelectorAll("article[data-aviso^=evento_suspension_]")].map((x) => x.dataset.aviso.replace("evento_suspension_", "").toUpperCase()).sort().join(","));

try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  let p, r, b;
  const EV1 = declarar("dist", { alcance: "sectores", sectores: [SUB], causa: "ZT daño en la tubería principal del sector", causal: "trabajo_programado" });
  const EV2 = declarar("planta", { alcance: "total", total: "ciudad", causa: "ZT parada de la planta por turbiedad", causal: "parametros_entrada" });

  // ===== A. Supervisor de distribución: la tarjeta en Supervisión =====
  p = await abrir(ancho, "dist"); await esperarTexto(p, /Dashboard distribución/);
  r = await enInicio(p, "Supervisión");
  ok(A("A1 el supervisor de distribución tiene la tarjeta «Suspensiones» en Supervisión, antes del Dashboard distribución, de 44 px o más"), !!r && r.tarjetas.includes("suspensiones") && r.tarjetas.indexOf("suspensiones") < r.tarjetas.indexOf("dashboard_distribucion") && r.alto >= 44 && /Suspensiones[\s\S]*Eventos de suspensión del servicio/.test(r.txt ?? ""), JSON.stringify(r));
  ok(A("A2 el inicio con la tarjeta nueva no desborda"), await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `inicio_dist_${ancho}.png`) });
  await clic(p, "[data-modo-actual] [data-tarjeta=suspensiones]"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 }); await p.waitForSelector(`[data-testid=eventos] [data-evento="${EV1}"]`, { timeout: 30000 });
  b = await barra(p); r = await lista(p);
  ok(A("A3 abre la lista de eventos, con los dos abiertos y la barra «Volver»"), b.vista === "lista" && b.volver === "← Volver" && b.titulo === "Eventos de suspensión" && r === [EV1, EV2].sort().join(","), JSON.stringify(b) + " " + r);
  ok(A("A4 la lista abierta desde el inicio no desborda y le ofrece declarar y los dos catálogos"), await sinDesborde(p) && !!(await p.$("[data-testid=evs-nuevo]")) && !!(await p.$("[data-testid=evs-ir-plantas]")) && !!(await p.$("[data-testid=evs-ir-tipos]")));
  await p.screenshot({ path: join(CAP, `suspensiones_dist_${ancho}.png`) });
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-modo-actual]");
  ok(A("A5 «Volver» regresa al inicio"), !(await p.$("[data-testid=eventos]")) && !!(await p.$("[data-tarjeta=suspensiones]")));

  // ===== B. El aviso de un evento abre ese evento (pantalla de Avisos) =====
  await clic(p, "[data-modo-actual] [data-tarjeta=avisos]"); await p.waitForSelector(`[data-aviso="evento_suspension_${EV1.toLowerCase()}"]`, { timeout: 30000 });
  r = await avisoDe(p, EV1);
  ok(A(`B1 en Avisos, el del evento dice «Abrir el evento ${EV1}» (ya no «Abrir Dashboard distribución»)`), r?.boton === `Abrir el evento ${EV1}` && (await avisoDe(p, EV2))?.boton === `Abrir el evento ${EV2}` && (await avisosEvento(p)) === [EV1, EV2].sort().join(","), JSON.stringify(r));
  await p.screenshot({ path: join(CAP, `avisos_evento_${ancho}.png`) });
  await clic(p, `[data-aviso="evento_suspension_${EV1.toLowerCase()}"] .av-abrir`); await p.waitForSelector(`[data-testid=evs-detalle][data-evento="${EV1}"]`, { timeout: 40000 });
  b = await barra(p);
  ok(A("B2 tocar el aviso abre el detalle de ESE evento"), b.vista === "detalle" && b.titulo === `Evento ${EV1}` && (await p.evaluate(() => document.querySelector("[data-testid=evs-detalle]").dataset.estado)) === "abierto", JSON.stringify(b));
  ok(A("B3 el detalle abierto desde el aviso no desborda"), await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `evento_desde_aviso_${ancho}.png`) });
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 });
  b = await barra(p);
  ok(A("B4 «Volver a los eventos» lleva a la lista, y de ahí «Volver a los avisos» regresa a Avisos"), b.vista === "lista" && b.volver === "← Volver a los avisos");
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector(`[data-aviso="evento_suspension_${EV2.toLowerCase()}"]`, { timeout: 30000 });
  ok(A("B5 de vuelta en Avisos, el otro evento abre el suyo"), await clic(p, `[data-aviso="evento_suspension_${EV2.toLowerCase()}"] .av-abrir`) && !!(await p.waitForSelector(`[data-testid=evs-detalle][data-evento="${EV2}"]`, { timeout: 40000 })));
  await p.close();

  // ===== C. Desde la franja de avisos del Dashboard distribución =====
  p = await abrir(ancho, "dist"); await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /No identificados/);
  await p.waitForSelector("[data-franja=distribucion] [data-aviso^=evento_suspension_]", { timeout: 30000 });
  r = await p.evaluate(() => { const x = document.querySelector("[data-franja=distribucion] [data-aviso^=evento_suspension_]"); x.scrollIntoView({ block: "center" }); const c = x.dataset.aviso.replace("evento_suspension_", "").toUpperCase(); x.click(); return c; });
  await p.waitForSelector(`[data-testid=evs-detalle][data-evento="${r}"]`, { timeout: 40000 });
  ok(A("C1 en la franja del dashboard, tocar el aviso del evento abre ese evento"), [EV1, EV2].includes(r) && (await barra(p)).titulo === `Evento ${r}`, r);
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 }); await clic(p, "[data-testid=eventos] .tec-volver"); await esperarTexto(p, /No identificados/);
  ok(A("C2 al volver queda otra vez en el Dashboard distribución"), !(await p.$("[data-testid=eventos]")) && !!(await p.$("[data-franja=distribucion]")));
  await p.close();

  // ===== D. Supervisor de planta: la tarjeta en Plantas y solo el aviso del evento total =====
  p = await abrir(ancho, "planta"); await esperarTexto(p, /Suspensiones/);
  r = await enInicio(p, "Plantas");
  ok(A("D1 el supervisor de planta tiene «Suspensiones» en el modo Plantas"), !!r && r.modo === "Plantas" && r.tarjetas.includes("suspensiones") && r.alto >= 44, JSON.stringify(r));
  await p.screenshot({ path: join(CAP, `inicio_planta_${ancho}.png`) });
  await clic(p, "[data-modo-actual] [data-tarjeta=suspensiones]"); await p.waitForSelector("[data-testid=evs-lista]", { timeout: 30000 }); await p.waitForSelector(`[data-testid=eventos] [data-evento="${EV2}"]`, { timeout: 30000 });
  ok(A("D2 abre la lista: puede declarar y no ve los dos catálogos (son del supervisor de distribución)"), !!(await p.$("[data-testid=evs-nuevo]")) && !(await p.$("[data-testid=evs-ir-plantas]")) && !(await p.$("[data-testid=evs-ir-tipos]")) && await sinDesborde(p));
  await clic(p, "[data-testid=eventos] .tec-volver"); await p.waitForSelector("[data-modo-actual]");
  await clicTexto(p, "button.tec-tarjeta-modo", "Avisos"); await p.waitForSelector(`[data-aviso="evento_suspension_${EV2.toLowerCase()}"]`, { timeout: 30000 });
  ok(A("D3 en sus Avisos, el del evento total dice «Abrir el evento …» (aviso del área de planta)"), (await avisosEvento(p)) === EV2 && (await avisoDe(p, EV2))?.boton === `Abrir el evento ${EV2}`, await avisosEvento(p));
  await clic(p, `[data-aviso="evento_suspension_${EV2.toLowerCase()}"] .av-abrir`); await p.waitForSelector(`[data-testid=evs-detalle][data-evento="${EV2}"]`, { timeout: 40000 });
  ok(A("D4 su aviso abre el evento total (no lo manda a un dashboard que no tiene)"), (await barra(p)).titulo === `Evento ${EV2}` && await sinDesborde(p));
  await p.close();

  // ===== E. El operador no tiene la tarjeta =====
  p = await abrir(ancho, "op"); await esperarTexto(p, /Reportar daño o falla/);
  r = await textoInicio(p);
  ok(A("E1 el operador no tiene «Suspensiones» en ningún modo"), !/Suspensiones/.test(r) && !(await p.$("[data-tarjeta=suspensiones]")));
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC desconocida", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
