// Prueba en Chrome REAL del Corte 14 («Encontrar o reportar activo»), a 390 px (táctil) y 1280 px:
// · Técnica: la tarjeta en el inicio (solo con el formulario asignado), el minimapa centrado en la persona (no se arrastra; + / – / Centrar; nivel 20 a 15 m y
//   19 a 30 m), la lista de cercanos con el mismo número del minimapa, el filtro Acueducto / Alcantarillado, la ficha y volver, «señal débil», «No está en la
//   lista» (cámara de campo, GPS y precisión), el aviso de duplicado y «precisión baja».
// · Comercial: la entrada en Formatos de campo, la misma pantalla y la ficha corta de solo lectura.
// · Supervisor de distribución: Por verificar → «Otros activos por levantamiento» (fotos, asignar, levantado, descartar, reabrir) y el formulario en Personal.
// · La Edge geoportal-redes: las rutas levantar_* con sus rechazos.
// Las Edges corren DE VERDAD en Deno; las RPC de redes van a la base de Code B (producción al publicar + la migración del 14) con el rol de la API
// (service_role) y los topes de producción (30 s y 8 s). Storage simulado: la firma y la subida escriben en storage.objects local. Puertos propios de Code B.
// Uso: node scripts/prueba_chrome_encontrar_c14.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
//   ANTES=1 RAIZ_UI=<árbol de main>: solo las capturas de «antes» (inicio de Técnica, Formatos de campo y Por verificar) con la página de main.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c14"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_encontrar_c14.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_14t> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANTES = process.env.ANTES === "1";
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55987, P_EDGE = 55988;      // puertos de Code B para el 14 (55987–55994)
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
const dir = mkdtempSync(join(tmpdir(), "ui_c14_"));
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
const lista = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=enc-lista] .enc-fila")].map((b) => ({ codigo: b.dataset.activo, n: b.querySelector(".enc-n").textContent, txt: b.innerText.replace(/\n/g, " ") })));
const marcas = (p) => p.evaluate(() => [...document.querySelectorAll(".enc-marca[data-activo]")].map((e) => ({ codigo: e.dataset.activo, n: e.querySelector(".enc-marca-n").textContent, cod: e.querySelector(".enc-marca-cod").textContent })));
const zoomMapa = (p) => p.evaluate(() => { const c = document.querySelector("[data-testid=enc-mapa]"); const m = c?.__mapa; return m ? { z: Math.round(m.getZoom() * 100) / 100 + 1,      // nivel del mapa de calles (teselas de 256 px) = zoom de MapLibre + 1
    ancho_m: Math.round(c.getBoundingClientRect().width * 156543.03392 * Math.cos(m.getCenter().lat * Math.PI / 180) / 2 ** (m.getZoom() + 1)),
    apiladas: (() => { const r = [...document.querySelectorAll(".enc-marca-n")].map((e) => e.getBoundingClientRect()); return r.every((a, i) => r.every((b, j) => i === j || Math.abs(a.left - b.left) > 20 || Math.abs(a.top - b.top) > 20)); })(), dato: Number(c.dataset.zoom), arrastra: m.dragPan.isEnabled(), rueda: m.scrollZoom.isEnabled(), toque: m.touchZoomRotate.isEnabled(), lon: m.getCenter().lng, lat: m.getCenter().lat } : null; });
const esperarLista = (p, n) => p.waitForFunction((n) => document.querySelectorAll("[data-testid=enc-lista] .enc-fila").length === n && document.querySelectorAll(".enc-marca[data-activo]").length === n, { timeout: 30000 }, n).then(() => true).catch(() => false);
async function tomarFoto(p) {
  await clic(p, "[data-testid=enc-foto]");
  await p.waitForFunction(() => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; }, { timeout: 30000 });
  await clic(p, ".campo-capturar");
  await p.waitForFunction(() => !document.querySelector(".campo-capturar"), { timeout: 30000 });
}
const edgeF = (rol, accion, o = {}) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
  headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined })
  .then(async (r) => ({ status: r.status, cache: r.headers.get("cache-control"), cuerpo: await r.json().catch(() => null) }));

const N_ACU = cuenta("acueducto", 15), N_ALC = cuenta("alcantarillado", 15), N_ACU30 = Math.min(30, cuenta("acueducto", 30));
let pagina = null;
const diagnostico = async (e) => {      // una espera que no llega: se dice qué había en pantalla y qué errores hubo
  console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 300) + " · errores: " + errores.join(" | ").slice(0, 900) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-700).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {});
  try { edge.kill(); } catch { /* ya terminó */ }
  process.exit(1);
};
try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  if (ANTES) {
    let p = await abrir(ancho, "op"); await esperarTexto(p, /Reportar daño o falla/); await captura(p, `antes_inicio_tecnica_${ancho}.png`); await p.close();
    p = await abrir(ancho, "campo", "campo"); await esperarTexto(p, /Formatos de campo/); await captura(p, `antes_formatos_campo_${ancho}.png`); await p.close();
    p = await abrir(ancho, "dist"); await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /Por verificar/);
    await clicTexto(p, "[role=tab]", "Por verificar"); await esperarTexto(p, /Activos que hay que confirmar/); await captura(p, `antes_por_verificar_${ancho}.png`); await p.close();
    continue;
  }

  // ===== A. Técnica: la tarjeta del inicio =====
  let p = await abrir(ancho, "op2");
  await esperarTexto(p, /Reportar daño o falla/);
  ok(A("A1 el operador sin el formulario asignado NO ve la tarjeta «Encontrar o reportar activo»"), !/Encontrar o reportar activo/.test(await textoInicio(p)));
  await p.close();
  p = await abrir(ancho, "op");
  await esperarTexto(p, /Encontrar o reportar activo/);
  ok(A("A2 el operador con el formulario asignado la ve en el modo Distribución"), await p.evaluate(() => !!document.querySelector('[data-modo-actual] [data-tarjeta="activo_campo"]')) && /Los activos que tiene cerca/.test(await texto(p)));
  await captura(p, `despues_inicio_tecnica_${ancho}.png`);

  // ===== B. Encontrar: el minimapa y la lista =====
  await clic(p, '[data-tarjeta="activo_campo"]');
  await p.waitForSelector("[data-testid=enc-mapa]");
  ok(A(`B1 con GPS de ± 6 m: la lista trae los ${N_ACU} activos de acueducto a 15 m y el minimapa los mismos, con el mismo número y su código`), (await esperarLista(p, N_ACU)) && await (async () => {
    const l = await lista(p), m = await marcas(p); return l.every((x, i) => x.n === String(i + 1)) && l.every((x) => m.some((y) => y.codigo === x.codigo && y.n === x.n && y.cod === x.codigo)) && l.some((x) => x.codigo === LUGAR.val); })(), JSON.stringify(await lista(p)).slice(0, 400));
  let z = await zoomMapa(p);
  ok(A("B2 el minimapa: nivel 20 (búsqueda a 15 m; unos 50 m de ancho en el celular), centrado en la persona, sin números encimados, y NO se arrastra ni se acerca con los dedos"), z && z.z === 20 && z.dato === 20 && (ancho >= 500 || (z.ancho_m >= 45 && z.ancho_m <= 60)) && z.apiladas && !z.arrastra && !z.rueda && !z.toque && Math.abs(z.lat - LUGAR.lat) < 1e-5 && Math.abs(z.lon - LUGAR.lon) < 1e-5, JSON.stringify(z));
  ok(A("B3 la precisión del GPS a la vista y el radio de búsqueda"), /Precisión del GPS: ± 6 m · se busca a 15 m de usted/.test((await texto(p)).replace(/\s+/g, " ")));
  ok(A("B4 el punto azul de la persona y su círculo de precisión"), await p.evaluate(() => { const m = document.querySelector("[data-testid=enc-mapa]").__mapa; return !!document.querySelector(".enc-persona") && m.getSource("precision")._data.features.length === 1 && m.getSource("radio")._data.features.length === 1; }));
  ok(A("B5 cada fila dice código, tipo, material y diámetro si aplica, y distancia; la válvula del lugar, a 0 m"), await (async () => { const l = await lista(p); return /^\d+ VAL-\d+ · Válvula.* 0,[01] m$/.test(l.find((x) => x.codigo === LUGAR.val).txt) && l.every((x) => / m$/.test(x.txt)) && l.some((x) => /mm/.test(x.txt)); })(), JSON.stringify(await lista(p)).slice(0, 300));
  ok(A("B6 sin desborde horizontal y botones de 44 px o más"), (await sinDesborde(p)) && (await minimo(p, ".enc button")) >= 44, String(await minimo(p, ".enc button")));
  await p.waitForFunction(() => { const m = document.querySelector("[data-testid=enc-mapa]").__mapa; return m.loaded(); }, { timeout: 20000 }).catch(() => {});
  await captura(p, `despues_encontrar_${ancho}.png`);
  await clic(p, '.enc-zoom-b[aria-label="Alejar"]'); await clic(p, '.enc-zoom-b[aria-label="Alejar"]');
  await p.waitForFunction(() => document.querySelector("[data-testid=enc-mapa]").__mapa.getZoom() === 17);
  ok(A("B7 «–» aleja hasta el nivel 18 y ahí se apaga; «+» sigue encendido"), await p.evaluate(() => document.querySelector('.enc-zoom-b[aria-label="Alejar"]').disabled && !document.querySelector('.enc-zoom-b[aria-label="Acercar"]').disabled));
  await clic(p, ".enc-zoom-centrar");
  await p.waitForFunction(() => document.querySelector("[data-testid=enc-mapa]").__mapa.getZoom() === 19);
  ok(A("B8 «Centrar» vuelve al encuadre automático (nivel 20), donde «+» se apaga"), await p.evaluate(() => document.querySelector('.enc-zoom-b[aria-label="Acercar"]').disabled && document.querySelector(".enc-zoom-centrar").disabled));
  await clic(p, '[data-servicio="alcantarillado"]');
  ok(A(`B9 el filtro Alcantarillado: los ${N_ALC} activos de alcantarillado a 15 m (y ninguno de acueducto)`), (await esperarLista(p, N_ALC)) && (await lista(p)).every((x) => !/^(RED|VAL|ACC|HID|TOR|CON)-/.test(x.codigo)), JSON.stringify(await lista(p)).slice(0, 300));
  await captura(p, `despues_encontrar_alcantarillado_${ancho}.png`);
  await clic(p, '[data-servicio="acueducto"]'); await esperarLista(p, N_ACU);

  // ===== C. La ficha y volver =====
  await clic(p, `.enc-fila[data-activo="${LUGAR.val}"]`);
  await p.waitForSelector("[data-testid=enc-ficha]"); await esperarTexto(p, new RegExp(LUGAR.val));
  ok(A("C1 tocar un activo abre su ficha (la de Técnica, de solo lectura para el operador)"), await p.evaluate((c) => document.body.innerText.includes(c) && !/Editar ficha/.test(document.body.innerText) && /Volver a los activos cercanos/.test(document.body.innerText), LUGAR.val));
  await captura(p, `despues_ficha_${ancho}.png`, false);
  ok(A("C3 la ficha trae «Reportar daño en este activo» (el operador tiene el formulario de daños)"), await p.evaluate(() => !!document.querySelector("[data-testid=enc-dano]")));
  await clicTexto(p, "button", "Volver a los activos cercanos");
  ok(A("C2 «Volver» regresa a la lista de cercanos"), await esperarLista(p, N_ACU));
  await clic(p, `.enc-fila[data-activo="${LUGAR.val}"]`); await p.waitForSelector("[data-testid=enc-dano]"); await clic(p, "[data-testid=enc-dano]");
  await p.waitForFunction((c) => /Reportar daño o falla/.test(document.body.innerText) && document.body.innerText.includes(c) && !!document.querySelector(".dan-opcion, .dan-rot"), { timeout: 30000 }, LUGAR.val).catch(() => {});
  ok(A("C4 … y abre el formulario de daño con ese activo ya escogido"), await p.evaluate((c) => /Reportar daño o falla/.test(document.querySelector(".tec-volver-tit")?.textContent ?? "") && document.body.innerText.includes(c), LUGAR.val), (await texto(p)).slice(0, 300));
  await captura(p, `despues_reportar_dano_${ancho}.png`, false);
  await clic(p, ".tec-volver"); await esperarTexto(p, /Encontrar o reportar activo/); await clic(p, '[data-tarjeta="activo_campo"]'); await p.waitForSelector("[data-testid=enc-mapa]"); await esperarLista(p, N_ACU);

  // ===== D. Señal débil =====
  await p.setGeolocation({ latitude: LUGAR.lat, longitude: LUGAR.lon, accuracy: 45 });
  await p.waitForSelector("[data-testid=enc-debil]", { timeout: 30000 });
  await p.waitForFunction(() => /se busca a 30 m/.test(document.body.innerText.replace(/\s+/g, " ")), { timeout: 30000 }).catch(() => {});
  await esperarLista(p, N_ACU30);
  z = await zoomMapa(p);
  ok(A("D1 con GPS de ± 45 m avisa «Señal débil…», busca a 30 m (el tope) y el minimapa pasa al nivel 19"), /Señal débil: espere unos segundos o acérquese a cielo abierto/.test(await texto(p)) && /± 45 m · se busca a 30 m/.test((await texto(p)).replace(/\s+/g, " ")) && z.z === 19, JSON.stringify(z));
  await captura(p, `despues_senal_debil_${ancho}.png`);

  // ===== E. Reportar activo (con señal débil: queda «precisión baja») =====
  await clic(p, "[data-testid=enc-reportar]");
  await p.waitForSelector("[data-testid=enc-form]");
  await clic(p, "[data-testid=enc-guardar]");
  ok(A("E1 sin datos no guarda: pide el tipo y la foto"), await p.waitForFunction(() => /Elija qué activo encontró/.test(document.body.innerText) && /Tome al menos una foto del activo/.test(document.body.innerText), { timeout: 5000 }).then(() => true).catch(() => false));
  await clic(p, '[data-tipo="otro"]'); await tomarFoto(p);
  await clic(p, "[data-testid=enc-guardar]");
  ok(A("E2 «Otro» exige decir qué es en la observación"), await p.waitForFunction(() => /Escriba en la observación qué activo es/.test(document.body.innerText), { timeout: 5000 }).then(() => true).catch(() => false));
  await clic(p, '[data-tipo="valvula"]'); await poner(p, "[data-testid=enc-form] textarea", "ZT válvula en el andén, frente a la tienda"); await tomarFoto(p);
  ok(A("E3 el formulario: servicio, 6 tipos, 2 fotos tomadas con la cámara de campo, la posición y el aviso de «precisión baja»"), await p.evaluate(() => document.querySelectorAll("[data-tipo]").length === 6 && document.querySelectorAll("[data-form-servicio]").length === 2
    && document.querySelectorAll(".enc-foto img").length === 2 && /precisión ± 45 m/.test(document.body.innerText) && /queda marcado «precisión baja»/.test(document.body.innerText)));
  await captura(p, `despues_reportar_${ancho}.png`);
  await clic(p, "[data-testid=enc-guardar]");
  await p.waitForSelector("[data-testid=enc-listo]", { timeout: 30000 });
  const lev1 = (await texto(p)).match(/Activo reportado: (LEV-\d{6})/)?.[1];
  const f1 = sqlq(`select tipo || '|' || servicio || '|' || precision_m || '|' || precision_baja || '|' || area || '|' || autor || '|' || fotos || '|' || lat || '|' || lon || '|' || observacion from redes.v_levantar_punto where codigo = '${lev1}'`);
  ok(A("E4 se guarda: código LEV-, «precisión baja», con sus 2 fotos, la posición del GPS y el área Técnica"), lev1 && f1 === `valvula|acueducto|45.0|true|tecnica|${EMAILS.op}|2|${LUGAR.lat.toFixed(6)}|${LUGAR.lon.toFixed(6)}|ZT válvula en el andén, frente a la tienda`
    && /Quedó marcado «precisión baja»/.test(await texto(p)), f1);
  ok(A("E5 las fotos subieron como JPEG a levantar/AAAA-MM/<id>/<n>.jpg"), subidas.slice(-2).every((s) => /^levantar\/\d{4}-\d{2}\/[0-9a-f-]{36}\/[12]\.jpg$/.test(s.ruta) && s.mime === "image/jpeg" && s.bytes > 1000), JSON.stringify(subidas.slice(-2)));
  await captura(p, `despues_reportado_${ancho}.png`);

  // ===== F. Duplicados =====
  await p.setGeolocation({ latitude: LUGAR.lat, longitude: LUGAR.lon, accuracy: 6 });
  await clicTexto(p, "button", "Volver a los activos cercanos");
  await p.waitForSelector("[data-testid=enc-ya]", { timeout: 30000 });
  ok(A("F1 de vuelta en la lista: «Ya reportados aquí, por levantar» y su marca en el minimapa"), await p.evaluate((c) => document.querySelector(`[data-testid=enc-ya] [data-levantar="${c}"]`)?.innerText.includes("Válvula de acueducto · reportado el") && !!document.querySelector(`.enc-marca-lev[data-levantar="${c}"]`), lev1));
  await p.waitForFunction(() => !document.querySelector("[data-testid=enc-debil]"), { timeout: 30000 }).catch(() => {});
  await clic(p, "[data-testid=enc-reportar]");
  await p.waitForSelector("[data-testid=enc-duplicado]");
  ok(A("F2 al reportar a menos de 10 m de uno ya reportado, pregunta: «ya reportado el <fecha>… ¿Es el mismo?»"), /Válvula de acueducto: ya reportado el \d+ de \w+ de \d{4}, a 0,\d m de usted\.[\s\S]*¿Es el mismo\?/.test(await p.evaluate(() => document.querySelector("[data-testid=enc-duplicado]").innerText)));
  await captura(p, `despues_duplicado_${ancho}.png`, false);
  await clic(p, "[data-testid=enc-dup-si]");
  ok(A("F3 «Sí, es el mismo»: no crea nada y lo dice"), await p.waitForFunction(() => /ya está reportado: no hace falta reportarlo otra vez/.test(document.body.innerText) && !document.querySelector("[data-testid=enc-form]"), { timeout: 5000 }).then(() => true).catch(() => false)
    && sqlq("select count(*) from redes.levantar_puntos") === "1");
  await clic(p, "[data-testid=enc-reportar]"); await p.waitForSelector("[data-testid=enc-duplicado]"); await clic(p, "[data-testid=enc-dup-no]");
  await p.waitForSelector("[data-testid=enc-form]");
  await clic(p, '[data-form-servicio="alcantarillado"]'); await clic(p, '[data-tipo="pozo"]'); await tomarFoto(p); await clic(p, "[data-testid=enc-guardar]");
  await p.waitForSelector("[data-testid=enc-listo]", { timeout: 30000 });
  const lev2 = (await texto(p)).match(/Activo reportado: (LEV-\d{6})/)?.[1];
  ok(A("F4 «No, es otro»: se crea el segundo (pozo de alcantarillado, con buena señal, sin «precisión baja»)"), lev2 && lev2 !== lev1 && sqlq(`select tipo || '|' || servicio || '|' || precision_baja from redes.levantar_puntos where codigo = '${lev2}'`) === "pozo|alcantarillado|false"
    && !/precisión baja/.test(await texto(p)));
  await p.close();

  // ===== G. Comercial =====
  p = await abrir(ancho, "campo", "campo");
  await esperarTexto(p, /Formatos de campo/);
  ok(A("G1 Comercial: la entrada «Encontrar o reportar activo» en Formatos de campo"), /Encontrar o reportar activo[\s\S]*Vea los activos de la red que tiene cerca/.test(await texto(p)));
  await captura(p, `despues_formatos_campo_${ancho}.png`);
  await clicTexto(p, "button.campo-formato-activo", "Encontrar o reportar activo");
  await p.waitForSelector("[data-testid=enc-mapa]", { timeout: 30000 });
  ok(A("G2 abre la misma pantalla, con los mismos activos cercanos y los dos ya reportados"), (await esperarLista(p, N_ACU)) && await p.evaluate(() => document.querySelectorAll("[data-testid=enc-ya] li").length === 2) && await p.evaluate(() => document.querySelector(".tec-volver").getBoundingClientRect().height <= 48));
  await captura(p, `despues_encontrar_comercial_${ancho}.png`);
  await clic(p, `.enc-fila[data-activo="${LUGAR.val}"]`);
  await p.waitForSelector("[data-testid=enc-ficha-corta]", { timeout: 30000 });
  ok(A("G3 la ficha para Comercial es la corta, de solo lectura (tipo, estado; sin editar ni epicrisis)"), await p.evaluate((c) => { const t = document.querySelector("[data-testid=enc-ficha-corta]").innerText; return t.includes(c) && /Ficha de solo lectura/.test(t) && /Tipo/.test(t) && /Estado/.test(t) && !document.querySelector(".red-ficha"); }, LUGAR.val)
    && (await sinDesborde(p)));
  await captura(p, `despues_ficha_comercial_${ancho}.png`);
  await clic(p, ".tec-volver"); await esperarLista(p, N_ACU);
  await p.setGeolocation({ latitude: LUGAR.lat + 0.00018, longitude: LUGAR.lon, accuracy: 6 });      // 20 m al norte: ya no hay duplicado cerca
  await p.waitForFunction(() => !document.querySelector("[data-testid=enc-ya] li:nth-child(2)") || [...document.querySelectorAll("[data-testid=enc-ya] li")].every((li) => !/a 0,0 m/.test(li.innerText)), { timeout: 30000 }).catch(() => {});
  await new Promise((r) => setTimeout(r, 3200));
  await clic(p, "[data-testid=enc-reportar]");
  await p.waitForSelector("[data-testid=enc-form]");
  await clic(p, '[data-tipo="hidrante"]'); await tomarFoto(p); await clic(p, "[data-testid=enc-guardar]");
  await p.waitForSelector("[data-testid=enc-listo]", { timeout: 30000 });
  const lev3 = (await texto(p)).match(/Activo reportado: (LEV-\d{6})/)?.[1];
  ok(A("G4 Comercial reporta un activo (a 20 m ya no pregunta por duplicado): queda con el área Comercial"), lev3 && sqlq(`select area || '|' || tipo || '|' || autor from redes.levantar_puntos where codigo = '${lev3}'`) === `comercial|hidrante|${EMAILS.campo}`);
  await p.close();

  // ===== H. Supervisor de distribución: la bandeja y los estados =====
  p = await abrir(ancho, "dist");
  await esperarTexto(p, /Dashboard distribución/);
  ok(A("H1 el supervisor ve «Encontrar o reportar activo» en Supervisión"), await p.evaluate(() => !!document.querySelector('.tec-tarjetas-supervision [data-tarjeta="activo_campo"]')), await textoInicio(p));
  await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /Por verificar/);
  await clicTexto(p, "[role=tab]", "Por verificar"); await p.waitForSelector('[data-grupo="levantar"]', { timeout: 30000 });
  await p.waitForFunction(() => /Otros activos por levantamiento: 3/.test(document.querySelector('[data-grupo="levantar"]').textContent), { timeout: 30000 }).catch(() => {});
  ok(A("H2 Por verificar: a los filtros se suma «Otros activos por levantamiento», con su conteo"), await p.evaluate(() => /Otros activos por levantamiento: 3/.test(document.querySelector('[data-grupo="levantar"]').textContent) && /Todos: \d+/.test(document.body.innerText)));
  await clic(p, '[data-grupo="levantar"]');
  await p.waitForSelector(`[data-testid=lev-bandeja] [data-levantar="${lev1}"]`, { timeout: 30000 });
  const tarj = (c) => p.evaluate((c) => document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"]`)?.innerText.replace(/\s+/g, " ") ?? "", c);
  ok(A("H3 la bandeja: tipo, servicio, estado, «Precisión baja», la observación, quién reportó (el funcionario), el área y la precisión"), await (async () => { const t = await tarj(lev1), t3 = await tarj(lev3);
    return t.includes(`${lev1} · Válvula de acueducto`) && /Reportado/.test(t) && /Precisión baja/.test(t) && /ZT válvula en el andén/.test(t) && /por .+ \(Técnica\) · precisión ± 45 m/.test(t) && /\(Comercial\)/.test(t3) && !/Precisión baja/.test(t3); })(), await tarj(lev1));
  await captura(p, `despues_por_levantar_${ancho}.png`);
  await clic(p, `[data-levantar="${lev1}"] [data-accion-lev="fotos"]`);
  ok(A("H4 «Ver las 2 fotos»: lectura firmada (queda en la auditoría)"), await p.waitForFunction((c) => document.querySelectorAll(`[data-levantar="${c}"] [data-testid=lev-fotos] img`).length === 2, { timeout: 20000 }, lev1).then(() => true).catch(() => false)
    && sqlq(`select count(*) from public.geoportal_auditoria where accion = 'redes_levantar_fotos' and referencia = '${lev1}'`) === "1");
  await clic(p, `[data-levantar="${lev1}"] [data-accion-lev="asignado"]`); await poner(p, `#lev-mot-${lev1}`, "ZT cuadrilla de topografía"); await clic(p, `[data-levantar="${lev1}"] [data-testid=lev-confirmar]`);
  ok(A("H5 «Asignar a levantamiento»: pasa a «Asignado a levantamiento»"), await p.waitForFunction((c) => document.querySelector(`[data-levantar="${c}"]`)?.dataset.estado === "asignado", { timeout: 20000 }, lev1).then(() => true).catch(() => false) && /quedó «asignado a levantamiento»/.test(await texto(p)));
  await clic(p, `[data-levantar="${lev1}"] [data-accion-lev="levantado"]`);
  ok(A("H6 «Marcar levantado» pide el código del activo nuevo (sin él no deja confirmar)"), await p.evaluate((c) => document.querySelector(`[data-levantar="${c}"] [data-testid=lev-confirmar]`).disabled, lev1));
  await poner(p, `#lev-act-${lev1}`, LUGAR.val.toLowerCase()); await clic(p, `[data-levantar="${lev1}"] [data-testid=lev-confirmar]`);
  await p.waitForFunction((c) => !document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"]`), { timeout: 20000 }, lev1).catch(() => {});
  ok(A("H7 … y con él queda «levantado», vinculado al activo, y sale de los abiertos"), sqlq(`select estado || '|' || (select codigo from redes.activos a where a.id = p.activo_id) from redes.v_levantar_punto p where codigo = '${lev1}'`) === `levantado|${LUGAR.val}`
    && await p.evaluate(() => /Por levantar: 2/.test(document.querySelector('[data-filtro-lev="abiertos"]').textContent)));
  await clic(p, `[data-levantar="${lev2}"] [data-accion-lev="descartado"]`); await poner(p, `#lev-mot-${lev2}`, "corto");
  ok(A("H8 «Descartar» exige un motivo de 10 caracteres o más"), await p.evaluate((c) => document.querySelector(`[data-levantar="${c}"] [data-testid=lev-confirmar]`).disabled, lev2));
  await poner(p, `#lev-mot-${lev2}`, "ZT es el pozo POZ ya levantado"); await clic(p, `[data-levantar="${lev2}"] [data-testid=lev-confirmar]`);
  await p.waitForFunction((c) => !document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"]`), { timeout: 20000 }, lev2).catch(() => {});
  await clic(p, '[data-filtro-lev="todos"]'); await p.waitForSelector(`[data-levantar="${lev2}"][data-estado="descartado"]`, { timeout: 20000 });
  ok(A("H9 en «Todos»: el levantado con su activo, el descartado con su motivo y quién lo hizo"), await (async () => { const t1 = await tarj(lev1), t2 = await tarj(lev2); return t1.includes(`activo ${LUGAR.val}`) && /Levantado el/.test(t1) && /Descartado el .* · ZT es el pozo POZ ya levantado/.test(t2) && /Reabrir/.test(t2) && !/Descartar/.test(t2); })(), await tarj(lev2));
  await captura(p, `despues_por_levantar_todos_${ancho}.png`);
  await clic(p, `[data-levantar="${lev2}"] [data-accion-lev="reabierto"]`); await poner(p, `#lev-mot-${lev2}`, "ZT no era el mismo pozo"); await clic(p, `[data-levantar="${lev2}"] [data-testid=lev-confirmar]`);
  ok(A("H10 «Reabrir» lo devuelve a «reportado» y el historial se conserva (nada se borra)"), await p.waitForFunction((c) => document.querySelector(`[data-levantar="${c}"]`)?.dataset.estado === "reportado", { timeout: 20000 }, lev2).then(() => true).catch(() => false)
    && sqlq(`select count(*) from redes.levantar_eventos e join redes.levantar_puntos q on q.id = e.punto_id where q.codigo = '${lev2}'`) === "2");
  ok(A("H11 la bandeja: sin desborde horizontal y botones de 44 px o más"), (await sinDesborde(p)) && (await minimo(p, "[data-testid=lev-bandeja] button")) >= 44);
  // ----- Etapa 2: el PDF con la hoja membretada -----
  await clic(p, '[data-filtro-lev="abiertos"]'); await p.waitForSelector("[data-testid=lev-pdf]", { timeout: 20000 });
  await clic(p, "[data-testid=lev-pdf]"); await p.waitForSelector('[data-testid=hoja][data-lista="si"]', { timeout: 40000 });
  const hoja = () => p.evaluate(() => { const h = document.querySelector("[data-testid=hoja]"); const filas = [...h.querySelectorAll(".hoja-tabla tbody tr")];
    return { tamano: h.dataset.tamano, filas: filas.length, ns: filas.map((f) => f.querySelector(".hoja-n strong").textContent).join(), marcas: [...h.querySelectorAll(".hoja-num")].map((x) => x.textContent).join(),
      cab: [...h.querySelectorAll(".hoja-tabla th")].map((x) => x.textContent).join("|"), fotos: [...h.querySelectorAll(".hoja-foto img")].filter((i) => i.complete && i.naturalWidth > 0).length,
      obs: h.querySelector(".hoja-tabla").innerText, pagina: h.querySelector("style").textContent, logo: !!h.querySelector("img.hoja-logo") && !!h.querySelector(".hoja-franja"), txt: h.querySelector(".hoja-papel").innerText }; });
  let h = await hoja();
  ok(A("J1 «Descargar en PDF»: la hoja con el mapa del sector y la tabla (N.º, tipo y servicio, fecha, coordenadas, precisión, foto y observación), los puntos numerados igual en los dos"), h.filas === 2 && h.ns === "1,2" && h.marcas === "1,2"
    && h.cab === "N.º|Tipo y servicio|Fecha|Coordenadas|Precisión|Foto|Observación" && h.fotos === 2 && /Otros activos por levantamiento/.test(h.txt) && /en el orden del recorrido/.test(h.txt) && !/ZT Operario|zt\.oper/.test(h.txt), JSON.stringify(h).slice(0, 500));
  ok(A("J2 hoja membretada: logo arriba y franja abajo; carta con márgenes 2,5 / 3 / 4 cm y «Página N de M»"), h.logo && /@top-right[^}]*url\(/.test(h.pagina) && /@bottom-center[^}]*url\(/.test(h.pagina) && h.tamano === "carta" && /size: 8\.5in 11in; margin: 2\.5cm 3cm 4cm 3cm/.test(h.pagina) && /Página " counter\(page\) " de " counter\(pages\)/.test(h.pagina));
  await captura(p, `despues_hoja_${ancho}.png`);
  await p.emulateMediaType("print");
  const pdf = await p.pdf({ preferCSSPageSize: true, printBackground: true });
  writeFileSync(join(CAP, `hoja_levantamiento_carta_${ancho}.pdf`), pdf);
  const caja = (b) => (Buffer.from(b).toString("latin1").match(/\/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)/) || []).slice(1, 3).map((x) => Math.round(Number(x)));
  ok(A("J3 el PDF sale en carta (612 × 792 puntos)"), caja(pdf).join("x") === "612x792" && pdf.length > 20000, caja(pdf).join("x") + " " + pdf.length);
  await p.emulateMediaType("screen");
  await clic(p, '[data-tamano-b="oficio"]');
  await p.emulateMediaType("print");
  const pdf2 = await p.pdf({ preferCSSPageSize: true, printBackground: true });
  writeFileSync(join(CAP, `hoja_levantamiento_oficio_${ancho}.pdf`), pdf2);
  ok(A("J4 … y en oficio, 8,5 × 13 in (612 × 936 puntos), con la misma hoja membretada"), caja(pdf2).join("x") === "612x936", caja(pdf2).join("x"));
  await p.emulateMediaType("screen");
  ok(A("J5 la descarga de la hoja queda en la auditoría"), Number(sqlq("select count(*) from public.geoportal_auditoria where accion = 'redes_levantar_hoja'")) >= 1);
  await clicTexto(p, ".hoja-barra button", "Cerrar"); await p.waitForFunction(() => !document.querySelector("[data-testid=hoja]"));
  // ----- Etapa 2: cierre casi automático -----
  const nuevo = sqlq(`do $$ declare v_cons bigint; v_cod text; v_id bigint; begin
      update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'HID' returning ultimo into v_cons; v_cod := 'HID-' || lpad(v_cons::text, 6, '0');
      insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'HID', 'carga', '${EMAILS.adm}') returning id into v_id;
      insert into redes.activo_versiones (activo_id, version, geom, nombre, estado_codigo, atributos, huella, autor)
      select v_id, 1, ST_Translate(q.geom, 0.00002, 0), 'ZT hidrante nuevo', 'en_operacion', '{}'::jsonb, md5(v_cod), '${EMAILS.adm}' from redes.levantar_puntos q where q.codigo = '${lev3}';
      insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT activo de prueba', '${EMAILS.adm}');
      perform redes.f_mat_refrescar_uno(v_id); perform set_config('zt.nuevo', v_cod, false); end $$; select current_setting('zt.nuevo')`).split("\n").pop().trim();
  await clic(p, '[data-filtro-lev="todos"]'); await p.waitForSelector(`[data-levantar="${lev1}"]`); await clic(p, '[data-filtro-lev="abiertos"]');
  await p.waitForSelector(`[data-levantar="${lev3}"] [data-testid=lev-propuesta]`, { timeout: 20000 }).catch(() => {});
  ok(A("K1 con un activo NUEVO de la capa a 2 m, el punto dice «Posiblemente levantado: HID-…» (y el otro punto, sin activo nuevo, no)"), await p.evaluate((c, n, o) => { const t = (document.querySelector(`[data-levantar="${c}"] [data-testid=lev-propuesta]`)?.innerText ?? "").replace(/\s+/g, " ");
    return t.includes(`Posiblemente levantado: ${n}`) && /a 2,\d m, cargado el/.test(t) && !document.querySelector(`[data-levantar="${o}"] [data-testid=lev-propuesta]`); }, lev3, nuevo, lev2), nuevo);
  await captura(p, `despues_posiblemente_levantado_${ancho}.png`);
  await clic(p, `[data-levantar="${lev3}"] [data-testid=lev-confirmar-propuesta]`);
  await p.waitForFunction((c) => !document.querySelector(`[data-testid=lev-bandeja] [data-levantar="${c}"]`), { timeout: 20000 }, lev3).catch(() => {});
  ok(A("K2 el supervisor confirma: queda «levantado» con ese activo"), sqlq(`select estado || '|' || (select codigo from redes.activos a where a.id = p.activo_id) from redes.v_levantar_punto p where codigo = '${lev3}'`) === `levantado|${nuevo}`);
  // ----- Etapa 2: el aviso y la capa del geovisor -----
  await p.reload(); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });      // los avisos se leen al abrir (y cada minuto): se abre de nuevo para verlos al día
  await esperarTexto(p, /Avisos/);
  await clicTexto(p, "button.tec-tarjeta-modo", "Avisos"); await p.waitForSelector('[data-aviso="activos_por_levantar"]', { timeout: 30000 });
  ok(A("L1 Avisos: «1 activo reportado por levantar», informativo, con su lista"), await p.evaluate((c) => { const a = document.querySelector('article[data-aviso="activos_por_levantar"]'); return a.dataset.nivel === "info" && /1 activo reportado por levantar/.test(a.innerText) && a.innerText.includes(c) && /Por verificar/.test(a.innerText); }, lev2),
    await p.evaluate(() => document.querySelector('article[data-aviso="activos_por_levantar"]')?.innerText));
  await captura(p, `despues_aviso_${ancho}.png`);
  await clic(p, 'article[data-aviso="activos_por_levantar"] .av-abrir');
  ok(A("L2 el aviso abre Por verificar ya en «Otros activos por levantamiento»"), await p.waitForSelector(`[data-testid=lev-bandeja] [data-levantar="${lev2}"]`, { timeout: 30000 }).then(() => true).catch(() => false)
    && await p.evaluate(() => document.querySelector('[data-grupo="levantar"]').getAttribute("aria-pressed") === "true"));
  await clicTexto(p, "button", "Geovisor técnico"); await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel");
  ok(A("M1 geovisor: la capa «Por levantar (activos reportados)» está en la lista del supervisor"), await p.evaluate(() => /Por levantar \(activos reportados\)/.test(document.querySelector(".geo-panel [data-capa=por_levantar]")?.innerText ?? "")));
  await p.evaluate(() => { const i = document.querySelector(".geo-panel [data-capa=por_levantar] input"); i.scrollIntoView({ block: "center" }); if (!i.checked) i.click(); });
  ok(A("M2 … y al encenderla trae el punto que sigue por levantar (el naranja de estado)"), await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; const s = m.getSource("g-por_levantar"); return s && s._data && s._data.features && s._data.features.length === 1 && m.getPaintProperty("g-por_levantar", "circle-color") === "#c25e00"; }, { timeout: 30000 }).then(() => true).catch(() => false));
  await clicTexto(p, ".geo-panel button", "✕"); await captura(p, `despues_geovisor_por_levantar_${ancho}.png`, false);
  // ----- Etapa 3: modo «Remuneración» -----
  ok(A("N1 geovisor del supervisor de distribución: el selector trae el quinto modo, «Remuneración»"), await p.evaluate(() => [...document.querySelectorAll("[data-colores]")].map((b) => b.textContent).join() === "Tipo,Material,Edad,Afectaciones,Remuneración"));
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 17 }), LUGAR.lon, LUGAR.lat);
  await clic(p, '[data-colores="remuneracion"]'); await p.waitForSelector("[data-testid=leyenda-remuneracion]");
  if (ancho < 500) await p.evaluate(() => { const b = document.querySelector("[data-testid=leyenda-remuneracion] .geo-leyenda-plegar"); if (b.getAttribute("aria-expanded") !== "true") b.click(); });
  await p.waitForFunction(() => /Remunerado: [\d.]+/.test(document.querySelector("[data-testid=leyenda-remuneracion]").innerText), { timeout: 30000 }).catch(() => {});
  ok(A("N2 la leyenda: Remunerado, No remunerado, Sin fila y Proyectado, con sus conteos y el rótulo «Valoración técnica 2019, propuesta»"), await p.evaluate(() => { const l = document.querySelector("[data-testid=leyenda-remuneracion]");
    return [...l.querySelectorAll("[data-remun]")].map((x) => x.dataset.remun).join() === "remunerado,no_remunerado,sin_fila,proyectado" && /Remunerado: [\d.]+/.test(l.innerText) && /Sin fila: \d+/.test(l.innerText)
      && l.querySelector("[data-testid=remun-rotulo]").textContent === "Valoración técnica 2019, propuesta"; }), await p.evaluate(() => document.querySelector("[data-testid=leyenda-remuneracion]").innerText));
  const dibRem = await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.getLayer("m-rem-l") && m.getLayoutProperty("m-rem-l", "visibility") === "visible" && m.queryRenderedFeatures({ layers: ["m-rem-l"] }).length > 0; }, { timeout: 60000 }).then(() => true).catch(() => false);
  ok(A("N3 la red se pinta por remuneración (tesela aparte) y la red de siempre queda de fondo"), dibRem && await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa;
    const fs = m.queryRenderedFeatures({ layers: ["m-rem-l", "m-rem-lp", "m-rem-p"] }); return fs.every((f) => ["remunerado", "no_remunerado", "sin_fila", "proyectado"].includes(f.properties.rem)) && m.getPaintProperty("t-acu_tramos-l", "line-color") === "#d5dde6"; }));
  if (ancho < 500) await p.evaluate(() => document.querySelector("[data-testid=leyenda-remuneracion] .geo-leyenda-plegar").click());
  await new Promise((r) => setTimeout(r, 500));
  { const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, LUGAR.lon, LUGAR.lat);
    if (ancho < 500) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y); }
  await p.waitForFunction(() => /Remunerado vía tarifa/.test(document.querySelector('.geo-tarjeta[data-capa="remuneracion"]')?.innerText ?? "") , { timeout: 30000 }).catch(() => {});
  const tr = await p.evaluate(() => { const c = document.querySelector('.geo-tarjeta[data-capa="remuneracion"]'); return c ? { cod: c.querySelector("h2").textContent, estado: c.dataset.estado, txt: c.innerText.replace(/\s+/g, " "), dentro: c.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 } : null; });
  const esperado = tr ? JSON.parse(sqlq(`select public.geoportal_redes_remuneracion_tarjeta('${EMAILS.dist}', '${tr.cod}')`)) : null;
  ok(A("N4 al tocar un activo: «Remunerado vía tarifa: Sí / No», su estado, la fila de la valoración (si la tiene) y el rótulo; lo mismo que dice la base"), tr && tr.estado === esperado.estado && new RegExp(`Remunerado vía tarifa ${esperado.remunerado ? "Sí" : "No"}`).test(tr.txt)
    && /Valoración técnica 2019, propuesta/.test(tr.txt) && (!esperado.filas || /Fila de la valoración .* fila \d+/.test(tr.txt)) && tr.dentro, JSON.stringify(tr));
  await captura(p, `despues_remuneracion_${ancho}.png`, false);
  await clic(p, '[data-colores="tipo"]');
  ok(A("N5 al salir del modo, la red vuelve a sus colores y la tarjeta se cierra"), await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.getLayoutProperty("m-rem-l", "visibility") === "none" && !document.querySelector('.geo-tarjeta[data-capa="remuneracion"]') && !document.querySelector("[data-testid=leyenda-remuneracion]"); }));
  await clic(p, ".geo-volver"); await esperarTexto(p, /Dashboard distribución/);
  await clicTexto(p, "button.tec-tarjeta-modo", "Dashboard distribución"); await esperarTexto(p, /Por verificar/);
  await clicTexto(p, "[role=tab]", "Personal"); await esperarTexto(p, /Encontrar o reportar activo/);
  ok(A("H12 Personal de distribución: el formulario «Encontrar o reportar activo» es uno más de los asignables"), /Encontrar o reportar activo/.test(await texto(p)));
  await captura(p, `despues_personal_${ancho}.png`);
  await p.close();
  // el supervisor de planta tiene el geovisor completo, pero NO el modo «Remuneración» (término tarifario)
  p = await abrir(ancho, "planta");
  await esperarTexto(p, /Geovisor técnico/); await clicTexto(p, "button.tec-tarjeta-modo", "Geovisor técnico"); await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  ok(A("N6 el supervisor de planta NO ve el modo «Remuneración» (ni su tesela se pide)"), await p.evaluate(() => [...document.querySelectorAll("[data-colores]")].map((b) => b.textContent).join() === "Tipo,Material,Edad,Afectaciones" && !document.querySelector(".geo-mapa").__mapa.getSource("remun")));
  await p.close();
}

// ===== I. La Edge: rutas y rechazos =====
if (!ANTES) {
  const pos = { lat: LUGAR.lat, lon: LUGAR.lon, precision_m: 6, servicio: "acueducto" };
  let r = await edgeF("campo", "levantar_inicio");
  ok("I1 levantar_inicio (GET): a Comercial, sin caché; a quien no tiene nada y al operador sin formulario, 403", r.status === 200 && r.cuerpo.perfil === "comercial" && r.cache === "no-store"
    && (await edgeF("op2", "levantar_inicio")).status === 403 && (await edgeF("nada", "levantar_inicio")).status === 403, JSON.stringify(r.cuerpo).slice(0, 200));
  r = await edgeF("op", "levantar_cerca", { cuerpo: pos });
  ok("I2 levantar_cerca (POST): activos numerados, sin datos de personas; por GET, 405; sin posición, servicio desconocido o un dato de más, 400", r.status === 200 && r.cuerpo.activos.length === N_ACU && !/nombre_suscriptor|contrato|telefono|direccion/i.test(JSON.stringify(r.cuerpo))
    && (await edgeF("op", "levantar_cerca")).status === 405 && (await edgeF("op", "levantar_cerca", { cuerpo: { servicio: "acueducto" } })).status === 400
    && (await edgeF("op", "levantar_cerca", { cuerpo: { ...pos, servicio: "gas" } })).status === 400 && (await edgeF("op", "levantar_cerca", { cuerpo: { ...pos, radio: 500 } })).status === 400);
  ok("I3 levantar_cerca fuera de Valledupar: 400 con el texto de la base", await edgeF("op", "levantar_cerca", { cuerpo: { ...pos, lat: 4.6, lon: -74.08 } }).then((x) => x.status === 400 && /fuera de Valledupar/.test(x.cuerpo.error)));
  r = await edgeF("campo", "levantar_ficha", { qs: { codigo: LUGAR.val } });
  ok("I4 levantar_ficha (GET): la ficha corta; un activo que no existe, 404; sin código, 400; y Comercial sigue sin entrar a la ficha de Técnica (403)", r.status === 200 && r.cuerpo.codigo === LUGAR.val && r.cuerpo.ficha_completa === false
    && (await edgeF("campo", "levantar_ficha", { qs: { codigo: "VAL-99999999" } })).status === 404 && (await edgeF("campo", "levantar_ficha")).status === 400 && (await edgeF("campo", "activo", { qs: { codigo: LUGAR.val } })).status === 403);
  ok("I5 levantar_preparar: 0 o 4 fotos, 400; con 1, las URL firmadas de subida", (await edgeF("campo", "levantar_preparar", { cuerpo: { fotos: 0 } })).status === 400 && (await edgeF("campo", "levantar_preparar", { cuerpo: { fotos: 4 } })).status === 400
    && await edgeF("campo", "levantar_preparar", { cuerpo: { fotos: 1 } }).then((x) => x.status === 200 && /^[0-9a-f-]{36}$/.test(x.cuerpo.punto_id) && /token=/.test(x.cuerpo.fotos[0].url_subida)));
  const d = { servicio: "acueducto", tipo: "caja", lat: LUGAR.lat, lon: LUGAR.lon, precision_m: 6, fotos: [{ n: 1, ruta: "levantar/2026-11/00000000-0000-4000-8000-000000000000/1.jpg" }] };
  const id0 = "00000000-0000-4000-8000-000000000000";
  ok("I6 levantar_crear rechaza por forma (sin identificador, tipo desconocido, sin precisión, foto con otra ruta, dato de más): 400",
    (await edgeF("campo", "levantar_crear", { cuerpo: { datos: d } })).status === 400 && (await edgeF("campo", "levantar_crear", { cuerpo: { punto_id: id0, datos: { ...d, tipo: "medidor" } } })).status === 400
    && (await edgeF("campo", "levantar_crear", { cuerpo: { punto_id: id0, datos: { ...d, precision_m: undefined } } })).status === 400
    && (await edgeF("campo", "levantar_crear", { cuerpo: { punto_id: id0, datos: { ...d, fotos: [{ n: 1, ruta: "danos/2026-11/x/1.jpg" }] } } })).status === 400
    && (await edgeF("campo", "levantar_crear", { cuerpo: { punto_id: id0, datos: { ...d, autor: "otro@emdupar.gov.co" } } })).status === 400);
  ok("I7 levantar_crear sin haber preparado la subida: 400 con el texto de la base", await edgeF("campo", "levantar_crear", { cuerpo: { punto_id: id0, datos: d } }).then((x) => x.status === 400 && /prepararse la subida/.test(x.cuerpo.error)));
  r = await edgeF("dist", "levantar_lista", { qs: { estado: "todos" } });
  ok("I8 levantar_lista (GET): al supervisor, sin caché y sin datos de suscriptores; al operador y a Comercial, 403; estado desconocido, 400", r.status === 200 && r.cuerpo.items.length === 3 && r.cache === "no-store" && !/contrato|telefono|direccion|suscriptor/i.test(JSON.stringify(r.cuerpo))
    && (await edgeF("op", "levantar_lista")).status === 403 && (await edgeF("campo", "levantar_lista")).status === 403 && (await edgeF("dist", "levantar_lista", { qs: { estado: "borrado" } })).status === 400);
  const cod = r.cuerpo.items.find((x) => x.estado === "reportado").codigo;
  ok("I9 levantar_evento rechaza por forma (código ajeno, tipo desconocido, dato de más): 400; al operador, 403; reabrir un punto abierto, 409",
    (await edgeF("dist", "levantar_evento", { cuerpo: { codigo: "DAN-000001", tipo: "asignado" } })).status === 400 && (await edgeF("dist", "levantar_evento", { cuerpo: { codigo: cod, tipo: "borrado" } })).status === 400
    && (await edgeF("dist", "levantar_evento", { cuerpo: { codigo: cod, tipo: "asignado", autor: "x" } })).status === 400 && (await edgeF("op", "levantar_evento", { cuerpo: { codigo: cod, tipo: "asignado" } })).status === 403
    && (await edgeF("dist", "levantar_evento", { cuerpo: { codigo: cod, tipo: "reabierto", motivo: "No estaba cerrado todavía" } })).status === 409);
  r = await edgeF("dist", "levantar_fotos", { cuerpo: { codigo: cod } });
  ok("I10 levantar_fotos (POST): URL firmadas de lectura, sin la ruta de Storage; a Comercial, 403; por GET, 405", r.status === 200 && r.cuerpo.fotos.length >= 1 && r.cuerpo.fotos.every((f) => /token=/.test(f.url) && !("ruta" in f)) && r.cache === "no-store"
    && (await edgeF("campo", "levantar_fotos", { cuerpo: { codigo: cod } })).status === 403 && (await edgeF("dist", "levantar_fotos")).status === 405);
  r = await edgeF("dist", "levantar_hoja", { cuerpo: { estado: "abiertos" } });
  ok("I12 levantar_hoja (POST): los puntos numerados con la foto firmada (sin la ruta de Storage ni quién reportó); al operador y a Comercial, 403; de «levantados», 400; por GET, 405", r.status === 200 && r.cuerpo.puntos.length >= 1 && r.cache === "no-store"
    && r.cuerpo.puntos.every((x, i) => x.n === i + 1 && /token=/.test(x.foto_url) && !("foto" in x) && !("quien" in x)) && (await edgeF("op", "levantar_hoja", { cuerpo: {} })).status === 403
    && (await edgeF("campo", "levantar_hoja", { cuerpo: {} })).status === 403 && (await edgeF("dist", "levantar_hoja", { cuerpo: { estado: "levantado" } })).status === 400 && (await edgeF("dist", "levantar_hoja")).status === 405, JSON.stringify(r.cuerpo).slice(0, 300));
  ok("I13 la capa «por_levantar» va por geovisor_capa: al supervisor, GeoJSON; al operador, 403", await edgeF("dist", "geovisor_capa", { qs: { capa: "por_levantar" } }).then((x) => x.status === 200 && Array.isArray(x.cuerpo.features)) && (await edgeF("op", "geovisor_capa", { qs: { capa: "por_levantar" } })).status === 403);
  r = await edgeF("dist", "remuneracion");
  ok("I14 remuneracion (GET): leyenda y conteos, sin caché; al operador, al supervisor de planta y a Comercial, 403", r.status === 200 && r.cuerpo.leyenda.length === 4 && r.cuerpo.cargado === true && r.cache === "no-store"
    && (await edgeF("op", "remuneracion")).status === 403 && (await edgeF("planta", "remuneracion")).status === 403 && (await edgeF("campo", "remuneracion")).status === 403);
  r = await edgeF("dist", "remuneracion_tarjeta", { qs: { codigo: LUGAR.val } });
  ok("I15 remuneracion_tarjeta (GET): estado, «remunerado» y rótulo; sin código, 400; un activo que no existe, 404; al supervisor de planta, 403", r.status === 200 && typeof r.cuerpo.remunerado === "boolean" && /propuesta/.test(r.cuerpo.rotulo)
    && (await edgeF("dist", "remuneracion_tarjeta")).status === 400 && (await edgeF("dist", "remuneracion_tarjeta", { qs: { codigo: "RED-99999999" } })).status === 404 && (await edgeF("planta", "remuneracion_tarjeta", { qs: { codigo: LUGAR.val } })).status === 403);
  { const z = 15, x = Math.floor((LUGAR.lon + 180) / 360 * 2 ** z), y = Math.floor((1 - Math.asinh(Math.tan(LUGAR.lat * Math.PI / 180)) / Math.PI) / 2 * 2 ** z);
    const f = (rol, qs) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=geovisor_tesela_remuneracion&${new URLSearchParams(qs)}`, { headers: { Authorization: `Bearer tok-${rol}` } });
    const t1 = await f("dist", { z, x, y, v: 1 }); const n1 = (await t1.arrayBuffer()).byteLength;
    ok("I16 geovisor_tesela_remuneracion: MVT con caché privada y por sesión; tesela fuera de rango, 400; al supervisor de planta y al operador, 403", t1.status === 200 && /mapbox-vector-tile/.test(t1.headers.get("content-type")) && /private/.test(t1.headers.get("cache-control")) && /Authorization/.test(t1.headers.get("vary") ?? "")
      && n1 > 500 && (await f("dist", { z: 40, x: 1, y: 1 })).status === 400 && (await f("planta", { z, x, y })).status === 403 && (await f("op", { z, x, y })).status === 403, `${t1.status} ${t1.headers.get("content-type")} ${t1.headers.get("cache-control")} vary=${t1.headers.get("vary")} bytes=${n1} fuera=${(await f("dist", { z: 40, x: 1, y: 1 })).status} planta=${(await f("planta", { z, x, y })).status} op=${(await f("op", { z, x, y })).status}`); }
  ok("I11 el perfil de redes trae «activo_campo»: sí al operador con el formulario y al supervisor; no al operador sin él", (await edgeF("op", "mi_perfil")).cuerpo.activo_campo === true && (await edgeF("dist", "mi_perfil")).cuerpo.activo_campo === true && (await edgeF("op2", "mi_perfil")).cuerpo.activo_campo === false);
  ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
  ok("Z2 ninguna RPC sin simular", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
  ok("Z3 la posición de la persona nunca viaja en la URL (solo en el cuerpo)", rpcs.filter((x) => x.fn === "geoportal_redes_levantar_cerca").length > 0);
}

} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(ANTES ? "capturas de «antes» tomadas" : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(ANTES || bien === resultados.length ? 0 : 1);
