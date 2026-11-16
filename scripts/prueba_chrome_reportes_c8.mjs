// Prueba en Chrome REAL del Corte 8 de Técnica fase 1: los reportes compartidos con Comercial. Desde el inicio por modos (modo Redes) se abren «Reportar anomalía» y
// «Revisiones generales», que son las MISMAS pantallas de Comercial, contra la MISMA Edge geoportal-campo y las mismas tablas; el reporte guarda el área «tecnica».
// A 390 px (táctil) y 1280 px. Cámara y GPS falsos de Chrome. Las Edges geoportal-tecnica, geoportal-redes y geoportal-campo corren DE VERDAD en Deno; las RPC van a la base
// local del Corte 8 (campo_local en localhost:55434: campo de Comercial + Técnica) como las ve producción (service_role, 30 s y 8 s). Storage se simula.
// Uso: node scripts/prueba_chrome_reportes_c8.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <rehacer_base.sh del Corte 8> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c8"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_reportes_c8.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54991, P_EDGE = 54992;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55434", PGUSER: "postgres", PGDATABASE: "campo_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt8.admin@emdupar.gov.co", op: "zt8.oper@emdupar.gov.co", sin: "zt8.oper.sin@emdupar.gov.co", rep: "zt8.reporta@emdupar.gov.co" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c8_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: (bucket) => ({ uploadToSignedUrl: async (ruta, token, blob) => {
        const r = await fetch("http://127.0.0.1:${P_BASE}/subida-simulada?bucket=" + bucket + "&ruta=" + encodeURIComponent(ruta) + "&token=" + token + "&bytes=" + blob.size + "&mime=" + encodeURIComponent(blob.type), { method: "PUT" });
        return r.ok ? { error: null } : { error: { status: r.status } }; } }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
// la página imita la app: .app de alto 100 % con la barra de 54 px (como la prueba de los dashboards del §34)
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const rpcs = [], desconocidas = [], subidas = [], firmasLectura = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    // Como las ve producción (regla del 6c): rol de la API (service_role), statement_timeout 30 s y lock_timeout 8 s.
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7, fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
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
    if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT, GET, POST", "Access-Control-Allow-Headers": "content-type, x-upsert, authorization" }); return res.end(); }
    // Storage simulado: firmas (la Edge) y la subida del PDF (el navegador, con PUT a la URL firmada) que queda en storage.objects de la base local
    if (req.method === "PUT" && u.pathname.startsWith("/storage/v1/object/upload/sign/")) {
      const [bucket, ...resto] = decodeURIComponent(u.pathname.slice("/storage/v1/object/upload/sign/".length)).split("/");
      subidas.push({ bucket, ruta: resto.join("/"), bytes: cuerpo.length, mime: req.headers["content-type"] });
      sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(bucket)}, ${lit(resto.join("/"))}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })})`);
      return json(200, { Key: resto.join("/") });
    }
    if (req.method === "PUT" && u.pathname === "/subida-simulada") {
      subidas.push({ bucket: u.searchParams.get("bucket"), ruta: u.searchParams.get("ruta"), token: u.searchParams.get("token") });
      sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(u.searchParams.get("bucket"))}, ${lit(u.searchParams.get("ruta"))}, ${lit({ size: Number(u.searchParams.get("bytes")), mimetype: u.searchParams.get("mime") })})`);
      return json(200, {});
    }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/upload/sign/".length); return json(200, { url: `/object/upload/sign/${ruta}?token=TOKEN` }); }
    if (u.pathname.startsWith("/storage/v1/object/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/sign/".length); firmasLectura.push(ruta); return json(200, { signedURL: `/object/leer/${ruta}?token=LECTURA` }); }
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn === "geoportal_redes_mi_perfil") return json(200, { dashboard_redes: false, geovisor: false });      // esta base no tiene redes
      const r = rpcBase(fn, a); return json(r.status, r.cuerpo);
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
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-campo/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const p = new URL(r.url).pathname; return (p.includes("geoportal-campo") ? hs[2] : p.includes("geoportal-redes") ? hs[1] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 300))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
const texto = (p) => p.evaluate(() => document.body.innerText);
// ---- Corte 11: el inicio de Técnica va por modos (Planta, Redes y Supervisión) y ningún formulario se abre solo. Estos ayudantes buscan en cada modo.
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
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)}`); }
    await new Promise((x) => setTimeout(x, 150));
  }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate(async (sel, t, dentro, tabs) => {
  const buscar = () => [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled);
  let b = buscar();
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
/** Todo lo que la persona tiene en el inicio (la suma de sus modos). */
const textoInicio = (p) => p.evaluate(async (sel) => {
  const tabs = [...document.querySelectorAll(sel)]; if (!tabs.length) return document.body.innerText;
  let s = ""; for (const t of tabs) { t.click(); await new Promise((x) => setTimeout(x, 0)); s += document.body.innerText + "\n"; }
  tabs[0].click(); await new Promise((x) => setTimeout(x, 0)); return s; }, TABS_MODO);
/** Abre un formulario desde su tarjeta del inicio (antes el primero se abría solo). */
const abrirFormulario = async (p, nombre) => { await esperarTexto(p, new RegExp(nombre)); if (!(await clicTexto(p, "button.tec-tarjeta-modo", nombre))) throw new Error("no está la tarjeta " + nombre); await p.waitForSelector(".tec-volver-barra"); };
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const visibilidad = (p, capa) => p.evaluate((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility"), capa);
const dibujados = (p, capa) => p.evaluate((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) ? m.queryRenderedFeatures({ layers: [c] }).length : -1; }, capa);
const esperarDibujo = (p, capa, ms = 60000) => p.waitForFunction((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) && m.queryRenderedFeatures({ layers: [c] }).length > 0; }, { timeout: ms }, capa).then(() => true).catch(() => false);
const marcada = (p, capa) => p.evaluate((c) => document.querySelector(`.geo-panel [data-capa=${c}] input`)?.checked ?? null, capa);
async function abrir(ancho, rol, hash) {
  await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
  const p = await nav.newPage(); await p.setGeolocation({ latitude: 10.46, longitude: -73.25, accuracy: 8 }); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(120000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");      // sin evaluar: la página puede estar cerrándose
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${hash ?? ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alGeovisor(p, boton = "Geovisor técnico") {
  await esperarTexto(p, new RegExp(boton.replace(/[()]/g, "\\$&"))); await clicTexto(p, "button", boton); await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
}
/** Lleva el mapa a un punto y toca la pantalla allí (como un dedo). */
async function tocarEn(p, lon, lat, zoom = 17.5) {
  await p.evaluate((lon, lat, z) => { const m = document.querySelector(".geo-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: z }); }, lon, lat, zoom);
  await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); }, { timeout: 60000 }).catch(() => {});
  await new Promise((r) => setTimeout(r, 400));
  const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lon, lat);
  if (await p.evaluate(() => matchMedia("(hover: none)").matches || navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
}

// PDF de prueba (mínimo y válido) para la ficha técnica
const PDF = join(dir, "ficha_tecnica.pdf");
writeFileSync(PDF, "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n");
const tarjetaQ = (p, c) => p.evaluate((c) => document.querySelector(`[data-quimico=${c}]`)?.innerText ?? "", c);
const esperarTarjeta = (p, c, re) => p.waitForFunction((c, s) => new RegExp(s).test(document.querySelector(`[data-quimico=${c}]`)?.innerText ?? ""), { timeout: 20000 }, c, re.source).catch(() => {});
const enTarjeta = (p, c, boton) => clicTexto(p, "button", boton, `[data-quimico=${c}]`);
const escribir = (p, sel, v) => p.evaluate((sel, v) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v); el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
async function alQuimicos(p) {
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, "[role=tab]", "Químicos"); await esperarTexto(p, /Una sola bodega/);
}


const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const tocar = async (p, clave) => { await p.waitForSelector(`button[data-tarjeta=${clave}]`); await p.evaluate((c) => document.querySelector(`button[data-tarjeta=${c}]`).click(), clave); };
const modoA = async (p, m) => { await p.evaluate((m) => document.querySelector(`[role=tab][data-modo=${m}]`)?.click(), m); await p.waitForFunction((m) => document.querySelector("[data-modo-actual]")?.dataset.modoActual === m, {}, m); };
const tarjetas = (p) => p.evaluate(() => [...document.querySelectorAll("[data-tarjeta]")].map((c) => `${c.dataset.tarjeta}:${c.tagName === "BUTTON"}`).join(","));
const fns = (correo) => rpcs.filter((r) => r.a.p_solicitante === correo).map((r) => r.fn);

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0; subidas.length = 0;
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('${EMAILS.adm}', 'ZT8 Admin', 'admin', 'sin_restriccion', 'todos');
        insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('${EMAILS.op}', 'ZT8 Operador', 'consulta', true, 'sin_restriccion', 'todos'), ('${EMAILS.sin}', 'ZT8 Sin compartidos', 'consulta', true, 'sin_restriccion', 'todos');
        insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('${EMAILS.rep}', 'ZT8 Reportante', 'consulta', true, 'sin_restriccion', 'todos');
        insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'anomalia_compartida', '${EMAILS.adm}'),
          ('${EMAILS.op}', 'asignar_formulario', 'revision_compartida', '${EMAILS.adm}'), ('${EMAILS.op}', 'asignar_formulario', 'entrada', '${EMAILS.adm}'), ('${EMAILS.sin}', 'asignar_formulario', 'entrada', '${EMAILS.adm}')`);
  const N0 = Number(sqlq("select count(*) from campo.reportes"));

  // ===== A. El inicio de Técnica: las dos entradas en el modo Redes =====
  let p = await abrir(ancho, "op"); await p.waitForSelector("[role=tab][data-modo=redes]");
  await modoA(p, "redes");
  ok(`${tag} A1 el operador con los formularios asignados ve, en el modo Redes, «Reportar anomalía» y «Revisiones generales» como tarjetas que se abren`, (await tarjetas(p)) === "anomalia_compartida:true,revision_compartida:true", await tarjetas(p));
  ok(`${tag} A2 con el nombre de siempre y diciendo que es el mismo de Comercial`, /Reportar anomalía[\s\S]*El mismo reporte de anomalías de Comercial[\s\S]*Revisiones generales/.test(await texto(p)));
  ok(`${tag} A3 al entrar no se pidió nada a la Edge de campo`, !fns(EMAILS.op).some((f) => f.startsWith("geoportal_campo")));
  await p.screenshot({ path: join(CAP, `inicio_redes_${ancho}.png`) });

  // ===== B. Reportar anomalía: la misma pantalla de Comercial =====
  await tocar(p, "anomalia_compartida"); await p.waitForSelector("#campo-grupo");
  const grupos = await p.evaluate(() => [...document.querySelectorAll("#campo-grupo option")].map((o) => o.value).filter(Boolean));
  ok(`${tag} B1 se abre la pantalla de Comercial (su selector de grupo y tipo), con «Volver» arriba y el nombre del formulario`, grupos.includes("red_acueducto")
     && (await p.evaluate(() => document.querySelector(".tec-volver-tit").textContent)) === "Reportar anomalía", grupos.join());
  ok(`${tag} B2 el formulario se pidió por la puerta de Técnica (geoportal_campo_tec_formulario) y no por la de Comercial`, fns(EMAILS.op).includes("geoportal_campo_tec_formulario") && !fns(EMAILS.op).includes("geoportal_campo_obtener_formulario"));
  ok(`${tag} B3 es el mismo catálogo: sin los grupos de formatos de actividad (cartera, PQR, facturación)`, !grupos.includes("cartera") && !grupos.includes("pqr") && !grupos.includes("facturacion") && grupos.includes("comercial_perdidas"), grupos.join());
  await p.select("#campo-grupo", "red_acueducto"); await esp(200);
  const tipos = await p.evaluate(() => [...document.querySelectorAll("#campo-tipo option")].map((o) => o.textContent.trim()).filter((x) => x && !/Elija|Seleccione/.test(x)));
  ok(`${tag} B4 en «Red de acueducto» están los tipos de antes y los dos nuevos: «Fuga en acometida» y «Caja de medidor dañada»`,
     tipos.includes("Fuga en acometida") && tipos.includes("Caja de medidor dañada") && tipos.includes("Daño en la red (fuga visible)") && tipos.length === 4, tipos.join(" | "));
  await p.select("#campo-tipo", "fuga_acometida"); await esp(200);
  await clicTexto(p, "button.campo-boton-foto", "📷 Tomar foto 1"); await p.waitForSelector("button.campo-capturar:not([disabled])", { timeout: 15000 }); await esp(500);
  await p.click("button.campo-capturar"); await esp(1500);
  ok(`${tag} B5 sin desborde con la foto tomada`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `anomalia_tecnica_${ancho}.png`), fullPage: true });
  for (let k = 0; k < 8 && !fns(EMAILS.op).includes("geoportal_campo_tec_crear_reporte"); k++) { await clicTexto(p, "button.campo-enviar", ""); await esp(900); }
  await p.waitForFunction(() => /Reporte (enviado|guardado|registrado)|quedó registrad|Registrado/i.test(document.body.innerText), { timeout: 20000 }).catch(() => {});
  const fila = sqlq(`select coalesce(string_agg(r.area || '|' || r.autor || '|' || t.codigo || '|' || r.origen || '|' || (select count(*) from campo.reporte_fotos f where f.reporte_id = r.id), ' ; '), '') from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id`);
  ok(`${tag} B6 al guardar, el reporte queda en campo.reportes (la misma tabla) con el área «tecnica», su autor, el tipo y su foto`, fila === `tecnica|${EMAILS.op}|fuga_acometida|campo|1`, fila + " · " + (await texto(p)).slice(-300));
  ok(`${tag} B7 la foto subió al bucket de campo y todo fue por las RPC de Técnica (preparar y crear), nunca por las de Comercial`,
     subidas.length === 1 && subidas[0].bucket === "campo-fotos" && fns(EMAILS.op).includes("geoportal_campo_tec_preparar_subida") && fns(EMAILS.op).includes("geoportal_campo_tec_crear_reporte")
     && !fns(EMAILS.op).some((f) => ["geoportal_campo_preparar_subida", "geoportal_campo_crear_reporte"].includes(f)), JSON.stringify(subidas) + fns(EMAILS.op).join());
  ok(`${tag} B8 la persona ve la confirmación`, /enviado|guardado|registrad/i.test(await texto(p)), (await texto(p)).slice(-300));
  await p.screenshot({ path: join(CAP, `anomalia_guardada_${ancho}.png`), fullPage: true });
  ok(`${tag} B9 el reporte ya está en la capa del geovisor (rojo: sin contrato), sin autor ni descripción`,
     sqlq("select string_agg(area || ':' || con_contrato || ':' || tipo, ',') from redes.v_reportes_comercial") === "tecnica:false:Fuga en acometida");
  await clicTexto(p, ".tec-volver-barra button", "←"); await p.waitForSelector("[data-tarjeta=revision_compartida]");

  // ===== C. Revisiones generales: el mismo formato de Comercial =====
  rpcs.length = 0;
  await tocar(p, "revision_compartida"); await esperarTexto(p, /Revisiones generales/); await p.waitForSelector(".campo-pagina, .campo-seccion, form", { timeout: 15000 }).catch(() => {});
  await esp(600);
  const tRev = await texto(p);
  ok(`${tag} C1 «Revisiones generales» abre el formato de Comercial con sus secciones y campos`, (await p.evaluate(() => document.querySelectorAll("details.campo-seccion, .campo-seccion").length)) >= 3 && /contrato/i.test(tRev), tRev.slice(0, 300));
  ok(`${tag} C2 desde Técnica no se ofrece la constancia por correo (ni se consulta su configuración)`, !/Constancia por correo/i.test(tRev) && !rpcs.some((r) => /geoportal_envio/.test(r.fn)));
  ok(`${tag} C3 sin desborde`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `revision_tecnica_${ancho}.png`) });
  await p.close();

  // ===== D. Quien no tiene los formularios, y Comercial =====
  p = await abrir(ancho, "sin"); await esperarTexto(p, /Sesión de/);
  ok(`${tag} D1 un operador de Técnica sin los formularios compartidos no tiene las tarjetas`, !(await p.$("[data-tarjeta=anomalia_compartida]")) && !(await p.$("[data-tarjeta=revision_compartida]")));
  await p.close();
  const directo = sqlq(`select count(*) from campo.reportes where area is null`);
  ok(`${tag} D2 no se creó ningún reporte sin área por este camino y el total subió en uno solo`, directo === String(N0) && Number(sqlq("select count(*) from campo.reportes")) === N0 + 1);
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
