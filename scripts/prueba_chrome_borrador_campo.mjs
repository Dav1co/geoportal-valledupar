// Prueba en Chrome REAL del borrador local de «Reportar daño o falla» y «Registrar intervención» (src/tecnica/borradorCampo.ts), a 390 px (táctil) y 1280 px:
// · se llena el formulario (texto, opciones, activo, fotos con la cámara, un PDF), se RECARGA la página a la mitad y, al volver a abrirlo, sale
//   «Tiene un borrador del … ¿Continuar o descartar?»; «Continuar» recupera lo escrito, lo elegido y los archivos, y el registro se guarda de verdad.
// · el borrador se borra al guardar, al descartarlo y al cancelar; es de una sola persona; vence a las 24 horas; el nombre del tercero no se guarda.
// · si el almacenamiento del celular falla (IndexedDB bloqueado), el formulario funciona igual, sin borrador.
// · el minimapa se precarga al abrir el formulario (elegir el sistema ya no descarga módulos).
// · «Encontrar o reportar activo» (19-nov): el reporte «No está en la lista» guarda su borrador (tipo, observación y fotos); avisa si se retoma lejos de donde se empezó.
// Mismo arnés de la prueba del Corte 14: Edges REALES en Deno, RPC de redes a la base de Code B con el rol de la API y los topes de producción, Storage simulado.
// Uso: node scripts/prueba_chrome_borrador_campo.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla, p. ej. emdupar_b_aut> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_borrador"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_borrador_campo.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_aut> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANTES = false;
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55991, P_EDGE = 55992;      // puertos de Code B para el 14 (55987–55994)
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
const dir = mkdtempSync(join(tmpdir(), "ui_borrador_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol, user: { email: "zt." + rol + "@emdupar.gov.co" } } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    import { AreaCampo } from "./src/campo/AreaCampo.tsx";
    const campo = new URLSearchParams(location.search).get("area") === "campo";
    const correo = "zt." + (new URLSearchParams(location.search).get("rol") || "op") + "@emdupar.gov.co";      // cada rol, su correo (el borrador es por persona)
    createRoot(document.getElementById("raiz")).render(campo ? <AreaCampo correo={correo} /> : <AreaTecnica uid="u-prueba" correo={correo} />);
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

// ---------- 5. Ayudantes del borrador ----------
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
/** Lo que hay en IndexedDB (abre con la misma versión y el mismo almacén que la página, para no dejar la base a medias). */
const idb = (p) => p.evaluate(() => new Promise((ok) => { const r = indexedDB.open("geoportal-tec-borradores", 1);
  r.onupgradeneeded = () => r.result.createObjectStore("borradores", { keyPath: "clave" });
  r.onerror = () => ok(null);
  r.onsuccess = () => { const q = r.result.transaction("borradores").objectStore("borradores").getAll();
    q.onsuccess = () => { r.result.close(); ok(q.result.map((x) => ({ clave: x.clave, guardado: x.guardado, datos: x.datos ?? null, archivos: (x.archivos ?? []).map((a) => ({ e: a.etiqueta, n: a.blob.size, nombre: a.nombre ?? null })) }))); }; }; }));
const vaciarIdb = (p) => p.evaluate(() => new Promise((ok) => { const r = indexedDB.deleteDatabase("geoportal-tec-borradores"); r.onsuccess = r.onerror = r.onblocked = () => ok(true); }));
const envejecer = (p, horas) => p.evaluate((h) => new Promise((ok) => { const r = indexedDB.open("geoportal-tec-borradores", 1);
  r.onsuccess = () => { const t = r.result.transaction("borradores", "readwrite"), a = t.objectStore("borradores"); const q = a.getAll();
    q.onsuccess = () => { for (const x of q.result) { x.guardado = Date.now() - h * 3600000; a.put(x); } }; t.oncomplete = () => { r.result.close(); ok(true); }; }; }), horas);
/** Abre el formulario desde el inicio de Técnica y espera a que salga la oferta del borrador o el formulario. Devuelve cuál. */
async function alFormularioSinEspera(p, clave) {
  await p.waitForSelector("[data-tarjeta]", { timeout: 30000 });
  const abierto = await p.evaluate(async (c, tabs) => {      // la tarjeta puede estar en otro modo (el administrador entra por Plantas)
    const buscar = () => document.querySelector(`button[data-tarjeta="${c}"]`); let b = buscar();
    if (!b) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 30)); b = buscar(); if (b) break; }
    if (!b) return false; b.click(); return true; }, clave, TABS_MODO);
  if (!abierto) throw new Error(`no está la tarjeta ${clave}`);
}
async function alFormulario(p, clave) {
  await alFormularioSinEspera(p, clave);
  await p.waitForFunction(() => !!document.querySelector("[data-testid=borrador-oferta]") || !!document.querySelector("#dan-desc, #itv-desc"), { timeout: 30000 });
  return p.evaluate(() => (document.querySelector("[data-testid=borrador-oferta]") ? "oferta" : "formulario"));
}
const oferta = (p) => p.evaluate(() => { const o = document.querySelector("[data-testid=borrador-oferta]"); return o ? { txt: o.querySelector("p").textContent, botones: [...o.querySelectorAll("button")].map((b) => b.textContent.trim()),
  alto: Math.min(...[...o.querySelectorAll("button")].map((b) => b.getBoundingClientRect().height)) } : null; });
const grupo = (p, rotulo, n = 0) => p.evaluate((r, n) => { const b = document.querySelectorAll(`[role=group][aria-label="${r}"] button`)[n]; if (!b) return null; b.scrollIntoView({ block: "center" }); b.click(); return b.textContent.trim(); }, rotulo, n);
const elegidoEn = (p, rotulo) => p.evaluate((r) => [...document.querySelectorAll(`[role=group][aria-label="${r}"] button[aria-pressed=true]`)].map((b) => b.textContent.trim()).join(","), rotulo);
const valor = (p, sel) => p.evaluate((s) => document.querySelector(s)?.value ?? null, sel);
const activoElegido = (p) => p.evaluate(() => document.querySelector(".dan-elegido strong")?.textContent ?? null);
const fotosEnPantalla = (p) => p.evaluate(async () => Promise.all([...document.querySelectorAll(".dan-foto")].map(async (f) => { const i = f.querySelector("img"); if (!i.complete) await new Promise((r) => { i.onload = i.onerror = r; });
  return { pie: f.querySelector("figcaption").textContent.trim(), ancho: i.naturalWidth, bytes: (await (await fetch(i.src)).blob()).size }; })));
async function foto(p, rotulo) {
  await clicTexto(p, "button", `Foto: ${rotulo}`);
  await p.waitForFunction(() => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; }, { timeout: 30000 });
  await clic(p, ".campo-capturar"); await p.waitForFunction(() => !document.querySelector(".campo-capturar"), { timeout: 30000 });
}
const trozos = (p) => p.evaluate(() => performance.getEntriesByType("resource").filter((r) => /\/trozo-[^/]+\.js$/.test(r.name)).length);
const PDF = join(dir, "orden_de_trabajo.pdf"); writeFileSync(PDF, "%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n");
const DESC = "ZT fuga en la esquina, sale agua por el andén";
/** Llena lo obligatorio del daño (menos las fotos). Devuelve lo elegido. */
async function llenarDano(p) {
  await grupo(p, "Sistema", 0);
  await p.waitForFunction(() => !!document.querySelector(".dan-elegido strong"), { timeout: 40000 });
  const tipo = await grupo(p, "Qué pasó", 0);
  await pausa(100); const rotura = await grupo(p, "Tipo de rotura", 0);
  await grupo(p, "Riesgo", 1);
  return { activo: await activoElegido(p), tipo, rotura };
}

try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  let p = await abrir(ancho, "op"); await vaciarIdb(p); await p.close();

  // ===== A. Daño: llenar, recargar a la mitad y recuperar =====
  p = await abrir(ancho, "op");
  ok(A("A1 sin borrador, «Reportar daño o falla» abre el formulario directo (sin pregunta)"), (await alFormulario(p, "danos_fallas")) === "formulario");
  await pausa(1500); const antesMapa = await trozos(p);
  const d = await llenarDano(p);
  await p.waitForSelector(".red-minimapa, .maplibregl-map", { timeout: 30000 }).catch(() => {});
  ok(A("A2 el minimapa se precarga al abrir: elegir el sistema ya no descarga módulos de la página"), antesMapa > 0 && (await trozos(p)) === antesMapa, `${antesMapa} → ${await trozos(p)}`);
  await grupo(p, "Causa", 1); await p.waitForSelector("#dan-tercero");
  await p.select("#dan-tercero", await p.evaluate(() => document.querySelector("#dan-tercero").options[1].value));
  await poner(p, "#dan-tnombre", "ZT Placa ABC123"); await poner(p, "#dan-usuarios", "25"); await poner(p, "#dan-desc", DESC);
  await foto(p, "El daño"); await foto(p, "Entorno");
  await pausa(900);
  let b = await idb(p);
  const regD = b?.find((x) => /^dano:[a-z0-9]+$/.test(x.clave)), regF = b?.find((x) => /^dano:[a-z0-9]+:archivos$/.test(x.clave));
  ok(A("A3 mientras se llena, el borrador queda en IndexedDB: los datos y, aparte, las 2 fotos (nada en sessionStorage ni en localStorage)"), !!regD && regD.datos.descripcion === DESC && regD.datos.usuarios === "25" && regF?.archivos.length === 2
     && regF.archivos.every((x) => x.n > 1000) && await p.evaluate(() => ![...Object.keys(sessionStorage), ...Object.keys(localStorage)].some((k) => /borrador/.test(k) && /dano|interv/.test(k))), JSON.stringify(b).slice(0, 500));
  ok(A("A4 el borrador no guarda el correo ni el nombre o la placa del tercero (dato personal)"), !!regD && !/@|ABC123/.test(JSON.stringify(b)) && regD.datos.terceroTipo !== "" && !("terceroNombre" in regD.datos));
  const bytesAntes = regF?.archivos.map((x) => x.n).join(",");
  await captura(p, `despues_dano_llenando_${ancho}.png`);

  // otra persona en el mismo celular no ve ese borrador
  let q = await abrir(ancho, "adm");
  ok(A("A5 el borrador es de una persona: a otra cuenta en el mismo celular no se le ofrece"), (await alFormulario(q, "danos_fallas")) === "formulario");
  await q.close();

  await p.reload(); await p.waitForFunction(() => window.__listo === true);
  ok(A("A6 tras RECARGAR la página, al abrir el formulario sale la pregunta en vez del formulario vacío"), (await alFormulario(p, "danos_fallas")) === "oferta");
  let o = await oferta(p);
  ok(A("A7 «Tiene un borrador del <fecha y hora> (con 2 fotos). ¿Continuar o descartar?», con «Continuar» y «Descartar» de 44 px o más, sin desbordar"),
    /^Tiene un borrador del \d{1,2} de [a-zñ]{3,5}\.?, \d{1,2}:\d{2}\s?[ap]\.\s?m\. \(con 2 fotos\)\. ¿Continuar o descartar\?$/.test(o.txt) && o.botones.join("|") === "Continuar|Descartar" && o.alto >= 44 && (await sinDesborde(p)), JSON.stringify(o));
  await captura(p, `despues_dano_oferta_${ancho}.png`);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Continuar"); await p.waitForSelector("#dan-desc");
  await p.waitForFunction(() => !!document.querySelector(".dan-elegido strong"), { timeout: 30000 });
  ok(A("A8 «Continuar» recupera lo escrito y lo elegido: sistema, activo, qué pasó, rotura, riesgo, causa, quién lo causó, usuarios y descripción"),
    (await valor(p, "#dan-desc")) === DESC && (await valor(p, "#dan-usuarios")) === "25" && (await elegidoEn(p, "Sistema")) !== "" && (await activoElegido(p)) === d.activo && (await elegidoEn(p, "Qué pasó")) === d.tipo
     && (d.rotura === null || (await elegidoEn(p, "Tipo de rotura")) === d.rotura) && (await elegidoEn(p, "Riesgo")) === "Medio" && (await elegidoEn(p, "Causa")) === "De terceros" && (await valor(p, "#dan-tercero")) !== "" && (await valor(p, "#dan-tnombre")) === "",
    JSON.stringify({ desc: await valor(p, "#dan-desc"), act: await activoElegido(p), esperado: d, tipo: await elegidoEn(p, "Qué pasó"), riesgo: await elegidoEn(p, "Riesgo"), causa: await elegidoEn(p, "Causa") }));
  let fs = await fotosEnPantalla(p);
  ok(A("A9 … y las 2 fotos, en su orden y con su clase, completas (los mismos bytes que se tomaron, con el sello ya puesto)"), fs.length === 2 && fs[0].pie.startsWith("1. El daño") && fs[1].pie.startsWith("2. Entorno") && fs.every((f) => f.ancho > 100)
     && fs.map((f) => f.bytes).join(",") === bytesAntes, JSON.stringify(fs) + " · antes " + bytesAntes);
  await captura(p, `despues_dano_recuperado_${ancho}.png`);
  subidas.length = 0;
  await clicTexto(p, "button", "Guardar daño o falla"); await p.waitForSelector(".dan-listo", { timeout: 60000 });
  const DAN = (await texto(p)).match(/guardad[oa]: (DAN-\d{6})/)?.[1];
  ok(A("A10 el daño recuperado se guarda de verdad, con sus 2 fotos subidas"), !!DAN && subidas.length === 2 && sqlq(`select count(*) from redes.danos where codigo = '${DAN}' and descripcion = '${DESC}'`) === "1", `${DAN} · ${subidas.length} subidas · ${(await texto(p)).slice(0, 300)}`);
  await pausa(500);
  ok(A("A11 al guardar con éxito, el borrador se borra del celular"), ((await idb(p)) ?? [null]).filter((x) => x?.clave.startsWith("dano:")).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await clicTexto(p, "button", "Reportar otro daño o falla");
  await p.waitForFunction(() => !!document.querySelector("[data-testid=borrador-oferta]") || !!document.querySelector("#dan-desc"));
  ok(A("A12 «Reportar otro daño o falla» abre un formulario limpio, sin pregunta"), !(await p.$("[data-testid=borrador-oferta]")) && (await valor(p, "#dan-desc")) === "");

  // ===== B. Descartar, cancelar, sin tocar y vencido =====
  await pausa(900);
  ok(A("B1 un formulario abierto y sin tocar no deja borrador"), ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await poner(p, "#dan-desc", "ZT para descartar"); await pausa(900);
  await p.reload(); await p.waitForFunction(() => window.__listo === true);
  ok(A("B2 con solo texto (sin fotos) también se ofrece, y no menciona fotos"), (await alFormulario(p, "danos_fallas")) === "oferta" && /^Tiene un borrador del [^()]+\. ¿Continuar o descartar\?$/.test((await oferta(p)).txt), (await oferta(p))?.txt);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Descartar"); await p.waitForSelector("#dan-desc"); await pausa(600);
  ok(A("B3 «Descartar» abre el formulario vacío y borra el borrador"), (await valor(p, "#dan-desc")) === "" && ((await idb(p)) ?? [null]).length === 0);
  await poner(p, "#dan-desc", "ZT para cancelar"); await pausa(900);
  ok(A("B4 (hay borrador otra vez)"), (await idb(p))?.length === 1);
  await clicTexto(p, ".tec-acciones button", "Cancelar"); await pausa(200);
  await p.evaluate(() => [...document.querySelectorAll("button")].filter((x) => /cancelar/i.test(x.textContent) && !/Seguir|No/i.test(x.textContent)).pop().click());
  await p.waitForFunction(() => (document.querySelector("#dan-desc")?.value ?? "") === "", { timeout: 15000 }); await pausa(700);
  ok(A("B5 «Cancelar» (confirmado) borra el borrador"), ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await poner(p, "#dan-desc", "ZT viejo"); await pausa(900); await envejecer(p, 25);
  await p.reload(); await p.waitForFunction(() => window.__listo === true);
  ok(A("B6 un borrador de más de 24 horas no se ofrece y se limpia"), (await alFormulario(p, "danos_fallas")) === "formulario" && ((await idb(p)) ?? [null]).length === 0);
  await p.close();

  // ===== C. Intervención: texto, material, foto y PDF; recargar y recuperar =====
  p = await abrir(ancho, "adm");
  ok(A("C1 sin borrador, «Registrar intervención» abre el formulario directo"), (await alFormulario(p, "mantenimiento")) === "formulario");
  let tipoItv = null;
  for (let i = 0; i < 6; i++) { tipoItv = await grupo(p, "Tipo de intervención", i); await pausa(100); if (tipoItv && !(await p.$('[role=group][aria-label="Tipo de inversión"]'))) break; }
  await grupo(p, "Sistema", 0); await p.waitForFunction(() => !!document.querySelector(".dan-elegido strong"), { timeout: 40000 });
  const actItv = await activoElegido(p);
  const DESC2 = "ZT se cambió un tramo de tres metros de tubo";
  await poner(p, "#itv-desc", DESC2); await clicTexto(p, "button", "Ahora");
  await clicTexto(p, "button", "Agregar material"); await p.waitForSelector('[aria-label="Material 1"]');
  await poner(p, '[aria-label="Material 1"]', "Tubo PVC"); await poner(p, '[aria-label="Cantidad 1"]', "3");
  await poner(p, "#itv-comp", "ZT cuadrilla dos");
  await foto(p, "Antes");
  await (await p.$("#itv-doc")).uploadFile(PDF); await p.waitForSelector(".itv-docs li");
  await pausa(900);
  b = await idb(p); const rI = b?.find((x) => /^intervencion:[a-z0-9]+:archivos$/.test(x.clave));
  ok(A("C2 el borrador de la intervención guarda la foto y el PDF"), rI?.archivos.map((x) => x.e).join(",") === "antes,documento" && rI.archivos[1].nombre === "orden_de_trabajo.pdf", JSON.stringify(b).slice(0, 400));
  await p.reload(); await p.waitForFunction(() => window.__listo === true);
  ok(A("C3 tras recargar, la pregunta: «Tiene un borrador del … (con 2 archivos). ¿Continuar o descartar?»"), (await alFormulario(p, "mantenimiento")) === "oferta" && /\(con 2 archivos\)\. ¿Continuar o descartar\?$/.test((await oferta(p)).txt) && (await sinDesborde(p)), (await oferta(p))?.txt);
  await captura(p, `despues_intervencion_oferta_${ancho}.png`);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Continuar"); await p.waitForSelector("#itv-desc");
  await p.waitForFunction(() => !!document.querySelector(".dan-elegido strong"), { timeout: 30000 });
  fs = await fotosEnPantalla(p);
  ok(A("C4 «Continuar» recupera tipo, sistema, activo, inicio y fin, descripción, el material con su cantidad, la cuadrilla, la foto y el PDF"),
    (await elegidoEn(p, "Tipo de intervención")) === tipoItv && (await activoElegido(p)) === actItv && (await valor(p, "#itv-desc")) === DESC2 && (await valor(p, "#itv-fin")) !== "" && (await valor(p, '[aria-label="Material 1"]')) === "Tubo PVC"
     && (await valor(p, '[aria-label="Cantidad 1"]')) === "3" && (await valor(p, "#itv-comp")) === "ZT cuadrilla dos" && fs.length === 1 && fs[0].pie.startsWith("1. Antes") && fs[0].ancho > 100
     && /orden_de_trabajo\.pdf/.test(await p.evaluate(() => document.querySelector(".itv-docs")?.innerText ?? "")), JSON.stringify({ tipo: await elegidoEn(p, "Tipo de intervención"), tipoItv, act: await activoElegido(p), actItv, fs }));
  await captura(p, `despues_intervencion_recuperada_${ancho}.png`);
  subidas.length = 0;
  await clicTexto(p, "button", "Guardar intervención"); await p.waitForSelector(".itv-listo", { timeout: 60000 }).catch(() => {});
  const ITV = (await texto(p)).match(/Intervención guardada: ([A-Z]+-\d{6})/)?.[1];
  ok(A("C5 la intervención recuperada se guarda de verdad, con la foto y el PDF subidos"), !!ITV && subidas.length === 2 && subidas.some((s) => /pdf/.test(s.mime)), `${ITV} · ${JSON.stringify(subidas).slice(0, 200)} · ${(await p.evaluate(() => document.querySelector(".dan-errores, .tec-aviso-error")?.innerText ?? "")).slice(0, 300)}`);
  await pausa(500);
  ok(A("C6 al guardar, el borrador de la intervención se borra"), ((await idb(p)) ?? [null]).length === 0);
  await p.close();

  // ===== D. Si el almacenamiento del celular falla, el formulario sigue funcionando sin borrador =====
  p = await nav.newPage(); pagina = p;
  await p.evaluateOnNewDocument(() => { Object.defineProperty(window, "indexedDB", { configurable: true, get() { return { open() { throw new DOMException("almacenamiento bloqueado", "SecurityError"); }, deleteDatabase() { throw new DOMException("bloqueado", "SecurityError"); } }; } }); });
  await p.setGeolocation({ latitude: LUGAR.lat, longitude: LUGAR.lon, accuracy: 6 });
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 }); p.setDefaultTimeout(60000);
  const erroresD = []; p.on("pageerror", (e) => erroresD.push(e.message)); p.on("console", (m) => { if (m.type() !== "error") return; let t = m.text(); if (/JSHandle@/.test(t)) t = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");
    if (!/Failed to load resource|status of|WebGL|GL Driver|GPU stall|openstreetmap|AJAXError|Failed to fetch/.test(t)) erroresD.push(t.slice(0, 200)); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=op`); await p.waitForFunction(() => window.__listo === true);
  ok(A("D1 con IndexedDB bloqueado, el formulario abre igual"), (await alFormulario(p, "danos_fallas")) === "formulario");
  await llenarDano(p); await grupo(p, "Causa", 2); await poner(p, "#dan-desc", "ZT sin almacenamiento"); await foto(p, "El daño"); await pausa(700);
  await clicTexto(p, "button", "Guardar daño o falla"); await p.waitForSelector(".dan-listo", { timeout: 60000 }).catch(() => {});
  ok(A("D2 … se llena, toma la foto y GUARDA el daño, sin errores de JavaScript"), /guardad[oa]: DAN-\d{6}/.test(await texto(p)) && erroresD.length === 0, erroresD.join(" | ") + " · " + (await texto(p)).slice(-300));
  await p.reload(); await p.waitForFunction(() => window.__listo === true);
  ok(A("D3 … y tras recargar no hay pregunta (no había borrador)"), (await alFormulario(p, "danos_fallas")) === "formulario");
  await p.close();

  // ===== E. «Encontrar o reportar activo»: el reporte «No está en la lista» =====
  const alReporte = async (q) => {      // de la lista de cercanos al formulario del reporte (o a la pregunta del borrador)
    await q.waitForSelector("[data-testid=enc-reportar]:not([disabled])", { timeout: 40000 }); await clic(q, "[data-testid=enc-reportar]");
    await q.waitForFunction(() => !!document.querySelector("[data-testid=borrador-oferta], [data-testid=enc-form], [data-testid=enc-duplicado]"), { timeout: 30000 });
    if (await q.$("[data-testid=enc-duplicado]")) { await clic(q, "[data-testid=enc-dup-no]"); await q.waitForFunction(() => !!document.querySelector("[data-testid=borrador-oferta], [data-testid=enc-form]")); }
    return q.evaluate(() => (document.querySelector("[data-testid=borrador-oferta]") ? "oferta" : "formulario"));
  };
  const alEncontrar = async (q) => { await alFormularioSinEspera(q, "activo_campo"); await q.waitForSelector("[data-testid=encontrar]", { timeout: 30000 }); };
  const fotoEnc = async (q) => { await clic(q, "[data-testid=enc-foto]"); await q.waitForFunction(() => { const x = document.querySelector(".campo-capturar"); return x && !x.disabled; }, { timeout: 30000 });
    await clic(q, ".campo-capturar"); await q.waitForFunction(() => !document.querySelector(".campo-capturar"), { timeout: 30000 }); };
  const fotosEnc = (q) => q.evaluate(async () => Promise.all([...document.querySelectorAll(".enc-foto img")].map(async (i) => { if (!i.complete) await new Promise((r) => { i.onload = i.onerror = r; }); return { ancho: i.naturalWidth, bytes: (await (await fetch(i.src)).blob()).size }; })));
  const encIdb = async (q) => ((await idb(q)) ?? []).filter((x) => x.clave.startsWith("encontrar:"));
  p = await abrir(ancho, "op"); await alEncontrar(p);
  ok(A("E1 sin borrador, «No está en la lista» abre el formulario del reporte directo"), (await alReporte(p)) === "formulario");
  await pausa(900);
  ok(A("E2 el reporte abierto y sin tocar no deja borrador"), (await encIdb(p)).length === 0, JSON.stringify(await encIdb(p)));
  await clic(p, '[data-tipo="hidrante"]'); await pausa(900);
  await p.reload(); await p.waitForFunction(() => window.__listo === true); await alEncontrar(p);
  ok(A("E3 con solo el tipo elegido, tras recargar pregunta (sin mencionar fotos)"), (await alReporte(p)) === "oferta" && /^Tiene un borrador del [^()]+\. ¿Continuar o descartar\?$/.test((await oferta(p)).txt), (await oferta(p))?.txt);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Descartar"); await p.waitForSelector("[data-testid=enc-form]"); await pausa(600);
  ok(A("E4 «Descartar» abre el reporte limpio y borra el borrador"), (await p.evaluate(() => document.querySelectorAll("[data-tipo][aria-pressed=true]").length)) === 0 && (await encIdb(p)).length === 0);
  await clic(p, '[data-tipo="hidrante"]'); await poner(p, "[data-testid=enc-form] textarea", "ZT para cancelar"); await pausa(900);
  await clicTexto(p, "[data-testid=enc-form] button", "Cancelar"); await p.waitForSelector("[data-testid=enc-reportar]"); await pausa(600);
  ok(A("E5 «Cancelar» borra el borrador"), (await encIdb(p)).length === 0, JSON.stringify(await encIdb(p)));
  await alReporte(p);
  await clic(p, '[data-form-servicio="acueducto"]'); await clic(p, '[data-tipo="hidrante"]'); await poner(p, "[data-testid=enc-form] textarea", "ZT hidrante sin tapa en la esquina");
  await fotoEnc(p); await fotoEnc(p); await pausa(900);
  b = await encIdb(p); const eD = b.find((x) => /^encontrar:[a-z0-9]+$/.test(x.clave)), eF = b.find((x) => /:archivos$/.test(x.clave));
  ok(A("E6 mientras se llena: tipo, observación, dónde se empezó y las 2 fotos, en IndexedDB y sin el correo"), !!eD && eD.datos.tipo === "hidrante" && eD.datos.observacion === "ZT hidrante sin tapa en la esquina" && Math.abs(eD.datos.lat - LUGAR.lat) < 0.0001
     && eF?.archivos.length === 2 && !/@/.test(JSON.stringify(b)), JSON.stringify(b).slice(0, 400));
  const bytesEnc = eF?.archivos.map((x) => x.n).join(",");
  // se retoma lejos de donde se empezó (unos 330 m al norte)
  await p.setGeolocation({ latitude: LUGAR.lat + 0.003, longitude: LUGAR.lon, accuracy: 6 });
  await p.reload(); await p.waitForFunction(() => window.__listo === true); await alEncontrar(p);
  ok(A("E7 tras RECARGAR lejos de donde se empezó: la pregunta (con 2 fotos) y el aviso «se empezó a … de aquí… continúe solo si está junto al activo»"), (await alReporte(p)) === "oferta" && /\(con 2 fotos\)\. ¿Continuar o descartar\?/.test((await oferta(p)).txt)
     && /Ese borrador se empezó a 3[0-9]{2} m de aquí\. El reporte se guarda con su posición de ahora: continúe solo si está junto al activo\./.test(await p.evaluate(() => document.querySelector("[data-testid=borrador-lejos]")?.textContent ?? "")) && (await sinDesborde(p)),
    await p.evaluate(() => document.querySelector("[data-testid=borrador-oferta]")?.innerText ?? ""));
  await captura(p, `despues_encontrar_oferta_lejos_${ancho}.png`);
  await p.setGeolocation({ latitude: LUGAR.lat, longitude: LUGAR.lon, accuracy: 6 });
  await p.reload(); await p.waitForFunction(() => window.__listo === true); await alEncontrar(p);
  ok(A("E8 de vuelta junto al activo: la pregunta sin el aviso de distancia; botones de 44 px o más"), (await alReporte(p)) === "oferta" && !(await p.$("[data-testid=borrador-lejos]")) && (await oferta(p)).alto >= 44);
  await captura(p, `despues_encontrar_oferta_${ancho}.png`);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Continuar"); await p.waitForSelector("[data-testid=enc-form]");
  fs = await fotosEnc(p);
  ok(A("E9 «Continuar» recupera el servicio, el tipo, la observación y las 2 fotos (los mismos bytes)"), (await p.evaluate(() => document.querySelector("[data-tipo][aria-pressed=true]")?.dataset.tipo)) === "hidrante"
     && (await valor(p, "[data-testid=enc-form] textarea")) === "ZT hidrante sin tapa en la esquina" && fs.length === 2 && fs.every((x) => x.ancho > 100) && fs.map((x) => x.bytes).join(",") === bytesEnc, JSON.stringify(fs) + " · " + bytesEnc);
  await captura(p, `despues_encontrar_recuperado_${ancho}.png`);
  subidas.length = 0;
  await clic(p, "[data-testid=enc-guardar]"); await p.waitForSelector("[data-testid=enc-listo]", { timeout: 40000 });
  const LEV = (await texto(p)).match(/Activo reportado: (LEV-\d{6})/)?.[1];
  await pausa(500);
  ok(A("E10 el reporte recuperado se guarda de verdad (2 fotos subidas) y el borrador se borra"), !!LEV && subidas.length === 2 && sqlq(`select count(*) from redes.levantar_puntos where codigo = '${LEV}' and tipo = 'hidrante'`) === "1" && (await encIdb(p)).length === 0, `${LEV} · ${subidas.length}`);
  await p.close();
  // Comercial: la misma pantalla desde Formatos de campo
  p = await abrir(ancho, "campo", "campo"); await esperarTexto(p, /Formatos de campo/);
  await clicTexto(p, "button.campo-formato-activo", "Encontrar o reportar activo"); await p.waitForSelector("[data-testid=encontrar]", { timeout: 30000 });
  await alReporte(p); await clic(p, '[data-tipo="valvula"]'); await poner(p, "[data-testid=enc-form] textarea", "ZT desde Comercial"); await pausa(900);
  await p.reload(); await p.waitForFunction(() => window.__listo === true); await esperarTexto(p, /Formatos de campo/);
  await clicTexto(p, "button.campo-formato-activo", "Encontrar o reportar activo"); await p.waitForSelector("[data-testid=encontrar]", { timeout: 30000 });
  ok(A("E11 en Comercial (Formatos de campo) el reporte también guarda y ofrece su borrador, y es de esa persona (otra clave)"), (await alReporte(p)) === "oferta" && (await encIdb(p)).length === 1);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Continuar"); await p.waitForSelector("[data-testid=enc-form]");
  ok(A("E12 … y lo recupera"), (await valor(p, "[data-testid=enc-form] textarea")) === "ZT desde Comercial" && (await p.evaluate(() => document.querySelector("[data-tipo][aria-pressed=true]")?.dataset.tipo)) === "valvula");
  await clicTexto(p, "[data-testid=enc-form] button", "Cancelar"); await pausa(500);
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
console.log(ANTES ? "capturas de «antes» tomadas" : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(ANTES || bien === resultados.length ? 0 : 1);
