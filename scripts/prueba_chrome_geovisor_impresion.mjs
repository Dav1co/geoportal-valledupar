// [Code A] Geovisor único · Corte 1 (26-nov): prueba en Chrome REAL, a 390 px (táctil) y 1280 px, con la foto satelital encendida y apagada.
// · Sectores: color por sector, subsector punteado, etiquetas según el acercamiento, leyenda con interruptores y ficha corta del polígono.
// · «Calles / Satélite», «Diámetro» y la leyenda de «Tipo».
// · «Imprimir / PDF»: siempre 2 páginas (Total y Urbano), extensiones sin cortes, escala comprobada con una distancia conocida, < 10 MB; 3 PDF de muestra
//   (antigüedad, material y tipo) y el aviso cuando la foto satelital no se puede exportar.
// · 5 perfiles: administrador, supervisor de distribución, operador con la casilla del geovisor (solo lectura), dual (supervisor de planta) y sin permisos.
// Las Edges corren DE VERDAD en Deno (geoportal-tecnica y geoportal-redes); las RPC de redes van a la base local (producción de redes, huella 1ba19272…) con el
// rol de la API (service_role) y los topes de producción. Sin internet: las teselas de calles y de la foto satelital son imágenes simuladas (y se puede hacer fallar la foto).
// Uso: node scripts/prueba_chrome_geovisor_impresion.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import { deflateSync } from "node:zlib";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_geovisor_impresion.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = args;
if (!PLANTILLA) { console.error(USO); process.exit(2); }
const CAP = resolve(args[6] || join(tmpdir(), "capturas_geo_impresion"));
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55983, P_EDGE = 55984;      // puertos de esta prueba (Code A)
const COPIA = `${PLANTILLA}_chrome_imp`;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: COPIA, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", sup: "zt.dist@emdupar.gov.co", dual: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", sin: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.sup]: "operador", [EMAILS.dual]: "supervisor", [EMAILS.op]: "operador", [EMAILS.sin]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.sup]: [], [EMAILS.dual]: ["muestreo"], [EMAILS.op]: ["danos_fallas"], [EMAILS.sin]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
// la copia de trabajo la crea esta prueba (y solo esa se borra al rehacerla)
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${COPIA}`, "-c", `create database ${COPIA} template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "ignore", "inherit"] });
rehacer();

// ---------- teselas simuladas (PNG de un color, con CORS) ----------
function png(r, g, b, raya) {
  const n = 256, filas = [];
  for (let y = 0; y < n; y++) { const f = Buffer.alloc(1 + n * 3); for (let x = 0; x < n; x++) { const l = raya && (x % 64 === 0 || y % 64 === 0); f[1 + x * 3] = l ? 255 : r; f[2 + x * 3] = l ? 255 : g; f[3 + x * 3] = l ? 255 : b; } filas.push(f); }
  const crc = (buf) => { let c = ~0; for (const x of buf) { c ^= x; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1)); } return ~c >>> 0; };
  const trozo = (tipo, datos) => { const l = Buffer.alloc(4); l.writeUInt32BE(datos.length); const td = Buffer.concat([Buffer.from(tipo), datos]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(n, 0); ihdr.writeUInt32BE(n, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), trozo("IHDR", ihdr), trozo("IDAT", deflateSync(Buffer.concat(filas))), trozo("IEND", Buffer.alloc(0))]);
}
const TESELA_CALLES = png(236, 231, 222, true), TESELA_SAT = png(58, 74, 53, false);
let falla_satelital = false;

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_geoimp_"));
// el fondo (calles y foto satelital) se sirve desde el servidor local de la prueba: el módulo real lib/mapaBase.ts con las URL cambiadas (sin internet)
const fondoLocal = { name: "fondo-local", setup(b) {
  b.onResolve({ filter: /lib\/mapaBase$/ }, () => ({ path: join(raiz, "src/lib/mapaBase.ts"), namespace: "fondo" }));
  b.onLoad({ filter: /.*/, namespace: "fondo" }, () => ({ loader: "ts", contents: readFileSync(join(raiz, "src/lib/mapaBase.ts"), "utf8")
    .replace("https://tile.openstreetmap.org/{z}/{x}/{y}.png", `http://127.0.0.1:${P_BASE}/fondo/calles/{z}/{x}/{y}.png`)
    .replace("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", `http://127.0.0.1:${P_BASE}/fondo/satelite/{z}/{y}/{x}`) }));
} };
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\.?\/|lib\/|\.\.\/\.\.\/lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    const EM = ${JSON.stringify(EMAILS)};
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol, user: { email: EM[rol] } } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble, fondoLocal],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "import.meta.env.BASE_URL": '"/"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const desconocidas = [];
function rpcBase(fn, a) {
  const argsSql = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${argsSql})`], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "sin permiso" } }; }
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_avisos": return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const PUBLICO = join(raiz, "public");
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname.startsWith("/fondo/")) {
    if (u.pathname.startsWith("/fondo/satelite/") && falla_satelital) { res.writeHead(503, { "Access-Control-Allow-Origin": "*" }); return res.end("no"); }
    res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(u.pathname.startsWith("/fondo/satelite/") ? TESELA_SAT : TESELA_CALLES);
  }
  if (u.pathname.startsWith("/glyphs/")) {      // las fuentes de las etiquetas, como las sirve la app (public/)
    const f = join(PUBLICO, decodeURIComponent(u.pathname));
    if (!f.startsWith(PUBLICO) || !existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "Content-Type": "application/x-protobuf" }); return res.end(readFileSync(f));
  }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : extname(f) === ".png" ? "image/png" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcPlanta(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).replace(/\n/g, " ⏎ ").slice(0, 400))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 900000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = []; const teselas = {};
const TABS_MODO = '[role=tablist][aria-label="Modo de trabajo"] [role=tab]';
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = async (p, re, ms = 30000) => {
  const fin = Date.now() + ms;
  for (;;) {
    const esta = await p.evaluate(async (s, sel) => { const r = new RegExp(s); if (r.test(document.body.innerText)) return true; if (!document.querySelector("[data-modo-actual]")) return false;
      for (const t of document.querySelectorAll(sel)) { t.click(); await new Promise((x) => setTimeout(x, 0)); if (r.test(document.body.innerText)) return true; } return false; }, re.source, TABS_MODO).catch(() => false);
    if (esta) return true;
    if (Date.now() > fin) return false;
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const enMapa = (p, cuerpo, ...a) => p.evaluate((c, a) => { const m = document.querySelector(".geo-mapa").__mapa; return new Function("m", "a", c)(m, a); }, cuerpo, a);
const pendientes = [];
async function quieto(p) {
  const listo = await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); }, { timeout: 45000 }).then(() => true).catch(() => false);
  if (!listo) pendientes.push(await p.evaluate(() => { const m = document.querySelector(".geo-mapa").__mapa; const st = m.style;
    return Object.keys(st.sourceCaches ?? st.tileManagers ?? {}).filter((k) => { const c = (st.sourceCaches ?? st.tileManagers)[k]; return c && c.used !== false && !c.loaded(); }).join(","); }).catch(() => "?"));
  await new Promise((r) => setTimeout(r, 500));
}
async function irA(p, lon, lat, z) { await enMapa(p, "m.jumpTo({ center: [a[0], a[1]], zoom: a[2] });", lon, lat, z); await quieto(p); }
const renderizados = (p, capa) => enMapa(p, "return m.getLayer(a[0]) ? m.queryRenderedFeatures({ layers: [a[0]] }).map((f) => /^x-sec-etq/.test(a[0]) ? f.properties.texto : f.properties.nombre) : null;", capa);

async function abrir(ancho, rol) {
  const p = await nav.newPage();
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(180000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("response", (r) => { if (/accion=geovisor_tesela&/.test(r.url())) teselas[r.status()] = (teselas[r.status()] ?? 0) + 1; });
  p.on("requestfailed", (r) => { if (/geovisor_tesela/.test(r.url())) teselas.falla = `${(teselas.falla ?? "")}${r.failure()?.errorText} `.slice(0, 200); });
  p.on("console", (m) => { if (m.type() !== "error") return; const t = m.text(); if (!/status of 40[0349]|status of 50[03]|Failed to load resource|GL Driver|AJAXError|Failed to fetch|WebGL|GPU stall/.test(t)) errores.push(`${ancho} ${rol} consola: ${t}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alGeovisor(p) {
  if (!(await esperarTexto(p, /Geovisor técnico/))) return false;
  await clicTexto(p, "button", "Geovisor técnico");
  if (!(await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/, 60000))) return false;
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
  await quieto(p);
  return true;
}
async function panelCapas(p) { await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel"); }
async function cerrarPanel(p) { await clicTexto(p, ".geo-panel button", "✕"); await p.waitForFunction(() => !document.querySelector(".geo-panel")); }
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? t.innerText : null; });
async function tocarEn(p, lon, lat, z) {
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click());
  await irA(p, lon, lat, z);
  const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lon, lat);
  if (await p.evaluate(() => navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
  await p.waitForFunction(() => !!document.querySelector(".geo-tarjeta"), { timeout: 20000 }).catch(() => {});
  return tarjetaGeo(p);
}
// Datos de los sectores (los del paso 0, como los ve la app)
const SECT = (() => { const t = readFileSync(join(raiz, "src/tecnica/impresion/sectores_datos.ts"), "utf8");
  return [...t.matchAll(/codigo: "([^"]+)", nombre: "([^"]+)", clase: "(\w+)", sector: "(\d+)", sub: (null|"[\d.]+"), lon: ([-\d.]+), lat: ([\d.]+)/g)]
    .map((m) => ({ codigo: m[1], nombre: m[2], clase: m[3], sector: m[4], sub: m[5] === "null" ? null : m[5].replace(/"/g, ""), lon: Number(m[6]), lat: Number(m[7]) })); })();
const CENTRO = [-73.2532, 10.4631];
const haversine = (lon1, lat1, lon2, lat2) => { const R = 6371008.8, r = Math.PI / 180, dφ = (lat2 - lat1) * r, dλ = (lon2 - lon1) * r;
  const h = Math.sin(dφ / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dλ / 2) ** 2; return 2 * R * Math.asin(Math.sqrt(h)); };
const EXT = { total: { oeste: -73.29679, sur: 10.38185, este: -73.21382, norte: 10.50684 }, urbano: { oeste: -73.28887, sur: 10.4254, este: -73.22844, norte: 10.49198 } };
const MARCO_W_PT = 612 - 40 - 40;

async function imprimir(p, ancho, nombre) {
  await p.evaluate(() => { delete window.__impresion; });
  await clicTexto(p, ".geo-barra button", "Imprimir / PDF");
  await p.waitForSelector("[data-testid=dialogo-imprimir]");
  const t0 = Date.now();
  await p.waitForFunction(() => !!document.querySelector("[data-testid=imprimir-listo]") || !!document.querySelector("[data-testid=dialogo-imprimir] [role=alert]"), { timeout: 600000 });
  const seg = Math.round((Date.now() - t0) / 1000);
  const r = await p.evaluate(async () => { const a = document.querySelector("[data-testid=imprimir-descargar]"); const err = document.querySelector("[data-testid=dialogo-imprimir] [role=alert]")?.innerText;
    if (!a) return { err };
    const b = new Uint8Array(await (await fetch(a.href)).arrayBuffer()); let s = ""; for (let i = 0; i < b.length; i += 32768) s += String.fromCharCode(...b.subarray(i, i + 32768));
    return { b64: btoa(s), info: window.__impresion, aviso: document.querySelector("[data-testid=imprimir-aviso]")?.innerText ?? null, descarga: a.getAttribute("download"), listo: document.querySelector("[data-testid=imprimir-listo]").innerText }; });
  await p.screenshot({ path: join(CAP, `${nombre}_dialogo_${ancho}.png`) });
  if (r.err || !r.b64) return { err: r.err ?? "sin PDF", seg };
  const pdf = Buffer.from(r.b64, "base64"); writeFileSync(join(CAP, `${nombre}.pdf`), pdf);
  // las imágenes de las páginas, para revisarlas a ojo (el PDF es una imagen JPEG por hoja)
  let k = 0, desde = 0; const jpgs = [];
  for (;;) { const i = pdf.indexOf(Buffer.from([0xff, 0xd8, 0xff]), desde); if (i < 0) break; const j = pdf.indexOf(Buffer.from([0xff, 0xd9]), i); const fin = pdf.indexOf(Buffer.from("\nendstream"), i);
    const jp = pdf.subarray(i, fin); jpgs.push(jp); writeFileSync(join(CAP, `${nombre}_pagina${++k}.jpg`), jp); desde = fin; if (j < 0) break; }
  await clicTexto(p, "[data-testid=dialogo-imprimir] button", "Cerrar");
  return { pdf, info: r.info, aviso: r.aviso, descarga: r.descarga, listo: r.listo, jpgs, seg };
}
function revisarPdf(tag, nombre, r, fondoEsperado) {
  if (r.err) { ok(`${tag} ${nombre}: se genera el PDF`, false, r.err); return; }
  const t = r.pdf.toString("latin1");
  const paginas = (t.match(/\/Type \/Page\b/g) || []).length;
  ok(`${tag} ${nombre}: PDF válido con 2 páginas carta vertical (${(r.pdf.length / 1048576).toFixed(1)} MB en ${r.seg} s)`, t.startsWith("%PDF-1.4") && t.trimEnd().endsWith("%%EOF") && paginas === 2
    && (t.match(/\/MediaBox \[0 0 612 792\]/g) || []).length === 2 && r.info?.paginas === 2, `páginas ${paginas}`);
  ok(`${tag} ${nombre}: cajetín bajo (${r.info?.cajetin} pt) y el mapa más alto (${r.info?.marco?.h} pt de 792)`, r.info?.cajetin <= 120 && r.info?.marco?.h >= 600, JSON.stringify(r.info?.marco));
  ok(`${tag} ${nombre}: orden 1) Total y 2) Urbano, a z14 y z15`, r.info.medidas[0].clave === "total" && r.info.medidas[1].clave === "urbano" && r.info.medidas[0].zoom === 14 && r.info.medidas[1].zoom === 15);
  const cubre = r.info.medidas.every((m) => { const e = EXT[m.clave], v = m.vista; return v.oeste <= e.oeste && v.este >= e.este && v.sur <= e.sur && v.norte >= e.norte; });
  ok(`${tag} ${nombre}: sin cortes: cada página cubre su extensión completa (norte y sur incluidos, con margen)`, cubre, JSON.stringify(r.info.medidas.map((m) => [m.clave, m.vista])));
  // escala: el ancho del mapa en la hoja, medido como distancia REAL (haversine sobre el centro), frente a la escala que dice el PDF
  const esc = r.info.medidas.map((m) => { const latC = (m.vista.sur + m.vista.norte) / 2; const dist = haversine(m.vista.oeste, latC, m.vista.este, latC);
    const escalaReal = dist / ((MARCO_W_PT / 72) * 0.0254); return { clave: m.clave, dice: m.escala, real: Math.round(escalaReal), error: Math.abs(m.escala - escalaReal) / escalaReal }; });
  ok(`${tag} ${nombre}: escala verificada con una distancia conocida (error < 1 %: ${esc.map((e) => `${e.clave} 1:${e.dice} frente a 1:${e.real}`).join(" · ")})`, esc.every((e) => e.error < 0.01), JSON.stringify(esc));
  ok(`${tag} ${nombre}: menos de 10 MB`, r.pdf.length < 10 * 1048576, r.pdf.length);
  ok(`${tag} ${nombre}: fondo ${fondoEsperado}`, r.info.medidas.every((m) => m.fondo === fondoEsperado), JSON.stringify(r.info.medidas.map((m) => m.fondo)));
  ok(`${tag} ${nombre}: el nombre del archivo dice la temática`, /^geovisor_[a-z_]+_\d{4}-\d{2}-\d{2}\.pdf$/.test(r.descarga ?? ""), r.descarga);
}

const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer();
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.sup}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);

  // ===== A. Supervisor de distribución =====
  let p = await abrir(ancho, "sup");
  ok(`${tag} A0 el supervisor abre el geovisor`, await alGeovisor(p), (await texto(p)).slice(0, 300));
  ok(`${tag} A1 selector «Calles / Satélite»: abre en calles`, await p.$("[data-testid=fondo]") && (await enMapa(p, "return [m.getLayoutProperty('base', 'visibility'), m.getLayoutProperty('base-sat', 'visibility')].join();")) === "visible,none");
  await clicTexto(p, "[data-testid=fondo] button", "Satélite"); await quieto(p);
  ok(`${tag} A2 «Satélite» cambia el fondo (uno a la vez)`, (await enMapa(p, "return [m.getLayoutProperty('base', 'visibility'), m.getLayoutProperty('base-sat', 'visibility')].join();")) === "none,visible");
  await irA(p, CENTRO[0], CENTRO[1], 13.6);
  await p.screenshot({ path: join(CAP, `sectores_satelite_${ancho}.png`) });
  await clicTexto(p, "[data-testid=fondo] button", "Calles"); await quieto(p);
  // sectores: capas, color, punteado
  const est = await enMapa(p, `const g = (id) => m.getLayer(id); return { a: !!g('t-sectores-a'), ab: !!g('t-sectores-ab'), as: !!g('t-sectores-as'), dash: m.getPaintProperty('t-sectores-as', 'line-dasharray'),
    color: JSON.stringify(m.getPaintProperty('t-sectores-a', 'fill-color')), op: JSON.stringify(m.getPaintProperty('t-sectores-a', 'fill-opacity')), glifos: m.getStyle().glyphs };`);
  ok(`${tag} A3 sectores: relleno y borde continuo por sector, subsector punteado del color de su sector`, est.a && est.ab && est.as && Array.isArray(est.dash) && /Sector 1/.test(est.color) && /#C2185B/i.test(est.color) && /0\.18/.test(est.op) && /0\.06/.test(est.op), JSON.stringify(est).slice(0, 300));
  ok(`${tag} A4 las fuentes de las etiquetas se sirven desde la misma app`, est.glifos?.startsWith(`http://127.0.0.1:${P_BASE}/glyphs/`), est.glifos);
  await irA(p, CENTRO[0], CENTRO[1], 13.2);
  const nombres = [...new Set((await renderizados(p, "t-sectores-a")) ?? [])];
  ok(`${tag} A5 la tesela trae los SEC con nombre y todos están en la lista del paso 0 (${nombres.length} a la vista)`, nombres.length >= 20 && nombres.every((n) => SECT.some((s) => s.nombre === n)), nombres.filter((n) => !SECT.some((s) => s.nombre === n)).join() + " · teselas " + JSON.stringify(teselas) + " · " + edgeLog.slice(-400));
  // revisión 26-nov: un SEC que no está en el paso 0 (en local, los dobles «ZTBASE Sector 1–3» de doble_planta_sectores.sql) viene en la tesela pero no se dibuja
  await irA(p, -73.24, 10.499, 14);
  const ajenos = await enMapa(p, `const n = new Set(a[0]); const fuente = m.querySourceFeatures("red", { sourceLayer: "activos" }).filter((f) => f.properties.prefijo === "SEC" && !n.has(f.properties.nombre)).map((f) => f.properties.codigo + " " + f.properties.nombre);
    const dib = m.queryRenderedFeatures({ layers: ["t-sectores-a", "t-sectores-ab", "t-sectores-as"] }).filter((f) => !n.has(f.properties.nombre)).map((f) => f.properties.nombre);
    return { fuente: [...new Set(fuente)], dib: [...new Set(dib)] };`, SECT.map((s) => s.nombre));
  ok(`${tag} A5b un SEC ajeno al paso 0 viene en la tesela pero no se dibuja (${ajenos.fuente.join(", ") || "ninguno a la vista"})`, ajenos.fuente.length > 0 && ajenos.dib.length === 0, JSON.stringify(ajenos));
  await irA(p, CENTRO[0], CENTRO[1], 13.2);
  if (process.env.PARAR_A5) { console.log("errores:", errores.join(" | ").slice(0, 1500)); console.log("capas:", await enMapa(p, "return m.getStyle().layers.map((l) => l.id + \":\" + (l.layout?.visibility ?? \"v\")).join(\" \");")); process.exit(0); }
  ok(`${tag} A6 desde lejos (z13,2), sin texto`, ((await renderizados(p, "x-sec-etq-s")) ?? []).length === 0 && ((await renderizados(p, "x-sec-etq-u")) ?? []).length === 0);
  await irA(p, CENTRO[0], CENTRO[1], 14);
  const e14 = { s: (await renderizados(p, "x-sec-etq-s")) ?? [], u: (await renderizados(p, "x-sec-etq-u")) ?? [] };
  ok(`${tag} A7 acercamiento medio (z14): el sector sí («Sector N»), el subsector no`, e14.s.length > 0 && e14.s.every((t) => /^Sector \d$/.test(t)) && e14.u.length === 0, JSON.stringify(e14));
  const sub = SECT.find((s) => s.clase === "subsector" && s.sub === "1.1") ?? SECT.find((s) => s.clase === "subsector");
  await irA(p, sub.lon, sub.lat, 15.6);
  const e15 = (await renderizados(p, "x-sec-etq-u")) ?? [];
  ok(`${tag} A8 más acercamiento (z15,6): el subsector («${sub.sub}»)`, e15.includes(sub.sub), JSON.stringify(e15));
  const halo = await enMapa(p, "return [m.getPaintProperty('x-sec-etq-u', 'text-halo-color'), m.getPaintProperty('x-sec-etq-u', 'text-halo-width')].join();");
  ok(`${tag} A9 halo blanco en las etiquetas`, halo === "#FFFFFF,2", halo);
  await p.screenshot({ path: join(CAP, `sectores_etiquetas_z15_${ancho}.png`) });
  // ficha corta
  // como en la prueba del Corte 10: solo los sectores encendidos al tocar (un punto de la red gana sobre un área, a propósito)
  const otras = await enMapa(p, "const l = m.getStyle().layers.filter((x) => /^t-/.test(x.id) && !/^t-sectores-/.test(x.id) && m.getLayoutProperty(x.id, 'visibility') !== 'none').map((x) => x.id); l.forEach((id) => m.setLayoutProperty(id, 'visibility', 'none')); return l;");
  const fic = await tocarEn(p, sub.lon, sub.lat, 15.6);
  await enMapa(p, "a[0].forEach((id) => m.setLayoutProperty(id, 'visibility', 'visible'));", otras);
  ok(`${tag} A10 clic en un subsector: ficha corta con su nombre y el sector al que pertenece`, fic && fic.includes(sub.nombre) && new RegExp(`Sector\\s+Sector ${sub.sector}`).test(fic) && /Plan Maestro 2014/.test(fic) && !/Edad|Estado/.test(fic), fic);
  await p.screenshot({ path: join(CAP, `ficha_subsector_${ancho}.png`) });
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click());
  // leyenda de sectores (en Capas, bajo «Sectores hidráulicos»)
  await irA(p, CENTRO[0], CENTRO[1], 14);
  await panelCapas(p);
  const ley = await p.evaluate(() => { const l = document.querySelector("[data-testid=leyenda-sectores]"); return l ? { filas: l.querySelectorAll("[data-sector]").length, gen: l.querySelectorAll("[data-sec-gen]").length } : null; });
  ok(`${tag} A11 leyenda de sectores: interruptor de «Sectores», de «Subsectores» y uno por sector (7)`, ley?.filas === 7 && ley?.gen === 2, JSON.stringify(ley));
  await p.evaluate(() => document.querySelector("[data-sector='1'] .geo-sector-pliegue").click());
  const subs1 = await p.evaluate(() => [...document.querySelectorAll("[data-sector='1'] .geo-subsectores li")].map((l) => l.innerText.trim()));
  ok(`${tag} A12 el sector 1 se despliega en sus subsectores, cada uno con interruptor`, subs1.length === SECT.filter((s) => s.clase === "subsector" && s.sector === "1").length && subs1.every((t) => /^Subsector 1\.\d+$/.test(t)), JSON.stringify(subs1));
  await p.evaluate(() => document.querySelector("[data-testid=leyenda-sectores]").scrollIntoView({ block: "start" }));
  await p.screenshot({ path: join(CAP, `leyenda_sectores_${ancho}.png`) });
  await p.evaluate(() => document.querySelector("[data-sec-gen=subsectores]").click());
  await cerrarPanel(p); await quieto(p);
  const sinSub = { as: ((await renderizados(p, "t-sectores-as")) ?? []).length, a: ((await renderizados(p, "t-sectores-a")) ?? []).filter((n) => /^Subsector/.test(n)).length };
  ok(`${tag} A13 «Subsectores» apagado: no se dibuja ningún subsector y siguen los sectores`, sinSub.as === 0 && sinSub.a === 0 && ((await renderizados(p, "t-sectores-ab")) ?? []).length > 0, JSON.stringify(sinSub));
  await panelCapas(p);
  await p.evaluate(() => { document.querySelector("[data-sec-gen=subsectores]").click(); document.querySelector("[data-sec='s:1']").click(); });
  await cerrarPanel(p); await irA(p, SECT.find((s) => s.nombre === "Sector 1").lon, SECT.find((s) => s.nombre === "Sector 1").lat, 14);
  const sin1 = ((await renderizados(p, "t-sectores-a")) ?? []);
  ok(`${tag} A14 el renglón del sector 1 lo apaga con sus subsectores (los demás siguen)`, !sin1.some((n) => n === "Sector 1" || /^Subsector 1\./.test(n)) && sin1.length > 0, JSON.stringify([...new Set(sin1)]));
  await panelCapas(p); await p.evaluate(() => document.querySelector("[data-sec='s:1']").click()); await cerrarPanel(p);
  // temáticas: Diámetro y la leyenda de Tipo
  await clicTexto(p, ".geo-seg button", "Diámetro"); await p.waitForSelector(".geo-leyenda[data-leyenda=diametro]");
  const dia = await p.evaluate(() => document.querySelector(".geo-leyenda[data-leyenda=diametro]").innerText);
  const dexp = JSON.stringify(await enMapa(p, "return m.getPaintProperty('t-acu_tramos-l', 'line-color');"));
  ok(`${tag} A15 temática «Diámetro»: leyenda de 6 clases y «Sin dato»; la red se colorea por el diámetro`, /Menos de 100 mm/.test(dia) && /600 mm o más/.test(dia) && /Sin dato/.test(dia) && /diametro/.test(dexp), dia + " · " + dexp.slice(0, 120));
  await p.screenshot({ path: join(CAP, `diametro_${ancho}.png`) });
  await clicTexto(p, ".geo-seg button", "Tipo"); await p.waitForSelector(".geo-leyenda[data-leyenda=tipo]");
  const plegadaTipo = await p.evaluate(() => document.querySelector(".geo-leyenda[data-leyenda=tipo]").dataset.abierta === "no");
  ok(`${tag} A16a la leyenda de «Tipo» abre ${ancho < 500 ? "plegada en el celular" : "abierta en escritorio"}`, plegadaTipo === (ancho < 500));
  if (plegadaTipo) await p.evaluate(() => document.querySelector(".geo-leyenda[data-leyenda=tipo] .geo-leyenda-titulo").click());
  const tip = await p.evaluate(() => document.querySelector(".geo-leyenda[data-leyenda=tipo]").innerText);
  ok(`${tag} A16 «Tipo» también lleva leyenda (redes y nodos)`, /Red de acueducto/.test(tip) && /Red de alcantarillado/.test(tip) && /Válvula/i.test(tip), tip);
  ok(`${tag} A17 sin desborde horizontal`, await sinDesborde(p));
  const barra = await p.evaluate(() => { const t = document.querySelector(".geo-titulo").getBoundingClientRect(); const b = [...document.querySelectorAll(".geo-barra button")].filter((x) => !x.classList.contains("geo-volver")).map((x) => x.getBoundingClientRect());
    return { choca: b.some((r) => r.left < t.right - 1 && r.right > t.left), bajo: Math.min(...b.map((r) => r.height)) }; });
  ok(`${tag} A18 la barra: el título no se monta sobre los botones y los botones miden 44 px o más`, !barra.choca && barra.bajo >= 44, JSON.stringify(barra));
  await p.screenshot({ path: join(CAP, `barra_${ancho}.png`) });
  const alcance = await p.evaluate(() => { const g = document.querySelector('[aria-label="Colores de la red"]'); const r = g.getBoundingClientRect();
    return { dentro: r.right <= window.innerWidth + 1, desliza: g.scrollWidth <= g.clientWidth + 1 || getComputedStyle(g).overflowX === "auto", botones: g.querySelectorAll("button").length }; });
  ok(`${tag} A19 el selector de temáticas cabe o se desliza: ningún botón (${alcance.botones}) queda fuera de alcance`, alcance.dentro && alcance.desliza, JSON.stringify(alcance));
  // ===== B. Imprimir / PDF =====
  const casos = ancho < 500 ? [["Edad", "antiguedad", "satelite"]] : [["Edad", "antiguedad", "calles"], ["Material", "material", "satelite"], ["Tipo", "tipo", "calles"]];
  for (const [boton, nombre, fondo] of casos) {
    await clicTexto(p, ".geo-seg button", boton);
    await clicTexto(p, "[data-testid=fondo] button", fondo === "satelite" ? "Satélite" : "Calles"); await quieto(p);
    const NOTA_REG = "Edad según fecha regulatoria de la valoración cuando no hay fecha de instalación", NOTA_SIN = "Ningún tramo tiene fecha de instalación cargada";
    if (nombre === "antiguedad") {      // 26-nov (David): las dos notas de «Edad» (en local, como en producción, ningún tramo tiene fecha de instalación)
      const ley = await p.evaluate(() => document.querySelector("[data-leyenda=edad]")?.innerText ?? "");
      ok(`${tag} B10 leyenda «Edad» en pantalla: «${NOTA_REG}» y «${NOTA_SIN}»`, ley.includes(NOTA_REG) && ley.includes(NOTA_SIN), ley);
    }
    const r = await imprimir(p, ancho, `pdf_${nombre}_${fondo}_${ancho}`);
    revisarPdf(tag, `PDF ${nombre} (${fondo})`, r, fondo);
    if (!r.err) ok(`${tag} B11 PDF ${nombre}: ${nombre === "antiguedad" ? "las dos notas de «Edad» al pie de la leyenda, en las 2 páginas" : "sin notas de «Edad»"}`,
      r.info.medidas.every((m) => nombre === "antiguedad" ? m.notas.includes(NOTA_REG) && m.notas.includes(NOTA_SIN) : m.notas.length === 0), JSON.stringify(r.info.medidas.map((m) => m.notas)));
    const esperado = { antiguedad: "Antigüedad de tuberías", material: "Material de tuberías", tipo: "Tipo de activo" }[nombre];
    if (!r.err) ok(`${tag} PDF ${nombre}: título «${r.info.titulo} — Total / Urbano»`, /^Redes? de (acueducto|alcantarillado|acueducto y alcantarillado) — /.test(r.info.titulo) && r.info.titulo.endsWith(esperado), r.info.titulo);
  }
  if (ancho >= 500) {
    falla_satelital = true;
    await clicTexto(p, "[data-testid=fondo] button", "Satélite"); await quieto(p);
    const r = await imprimir(p, ancho, `pdf_sin_satelital_${ancho}`);
    falla_satelital = false;
    ok(`${tag} B9 si la foto satelital no se puede exportar, sale con calles y lo avisa`, !r.err && r.aviso && /calles/.test(r.aviso) && r.info.medidas.every((m) => m.fondo === "calles"), r.err ?? r.aviso);
    await clicTexto(p, "[data-testid=fondo] button", "Calles");
  }
  await p.close();

  // ===== C. Operador con la casilla del geovisor (solo lectura) =====
  p = await abrir(ancho, "op");
  ok(`${tag} C1 el operador con la casilla abre el geovisor (solo lectura)`, await alGeovisor(p) && /Solo lectura/.test(await texto(p)));
  ok(`${tag} C2 el operador ve los sectores, el selector de fondo y «Imprimir / PDF»`, !!(await p.$("[data-testid=fondo]")) && !!(await p.$("[data-testid=imprimir]")) && (await enMapa(p, "return m.getLayoutProperty('t-sectores-a', 'visibility');")) === "visible");
  ok(`${tag} C3 sin desborde (operador)`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `operador_${ancho}.png`) });
  await p.close();
  // ===== D. Dual (supervisor de planta) y administrador =====
  for (const rol of ["dual", "adm"]) {
    p = await abrir(ancho, rol);
    const abre = await alGeovisor(p);
    ok(`${tag} D ${rol === "adm" ? "el administrador" : "el dual (supervisor de planta)"} abre el geovisor con sectores, fondo, «Diámetro» e «Imprimir / PDF»`, abre && !!(await p.$("[data-testid=imprimir]")) && !!(await p.$("[data-colores=diametro]")), (await texto(p)).slice(0, 200));
    await p.close();
  }
  // ===== E. Sin permisos: no ve el geovisor =====
  p = await abrir(ancho, "sin");
  await new Promise((r) => setTimeout(r, 2500));
  const veBoton = await p.evaluate(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim().startsWith("Geovisor técnico")));
  let veMapa = false;
  if (veBoton) { await clicTexto(p, "button", "Geovisor técnico"); await new Promise((r) => setTimeout(r, 3000)); veMapa = !!(await p.$(".geo-mapa")); }
  ok(`${tag} E1 sin permisos (operador sin la casilla): no abre el geovisor`, !veMapa, await texto(p));
  await p.close();
}
await nav.close(); srv.close();
const fallas = resultados.filter((r) => !r.ok).length;
if (desconocidas.length) console.log("RPC simuladas no conocidas:", [...new Set(desconocidas)].join(", "));
if (pendientes.length) console.log("Fuentes que no terminaron de cargar:", pendientes.join(" | "));
if (errores.length) console.log("Errores de página:", errores.slice(0, 10).join(" | "));
console.log(`\nCapturas y PDF: ${CAP}`);
console.log(`\nRESULTADO: ${resultados.length - fallas} de ${resultados.length}${fallas ? "" : " — SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
