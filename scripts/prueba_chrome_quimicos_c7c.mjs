// Prueba en Chrome REAL del Corte 7c de Técnica fase 1: la foto de la remisión en «Entrada de químicos» (operador), su enlace en el historial del supervisor y la
// sección «Parámetros» de Químicos en el Dashboard PTAP (el desvío de esperado contra usado y los días atrás, con motivo e historial). A 390 px (táctil) y 1280 px.
// · Las Edges corren DE VERDAD en Deno; las RPC van a la base local (redes_local, con el 7a y el 7c) como las ve producción (service_role, 30 s y 8 s). Storage se simula:
//   la foto sube con PUT a la URL firmada y queda en storage.objects. La foto de prueba se genera aquí mismo (un JPEG de 2.400 px), no hay archivos en el repositorio.
// Uso: node scripts/prueba_chrome_quimicos_c7c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh del 7c> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c7c"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_quimicos_c7c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54991, P_EDGE = 54992;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: ["entrada", "entrada_quimicos", "uso_quimicos"] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo", entrada: "Entrada", entrada_quimicos: "Entrada de químicos", uso_quimicos: "Uso de químicos" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c7c_"));
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
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/upload/sign/".length); return json(200, { url: `/object/upload/sign/${ruta}?token=TOKEN` }); }
    if (u.pathname.startsWith("/storage/v1/object/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/sign/".length); firmasLectura.push(ruta); return json(200, { signedURL: `/object/leer/${ruta}?token=LECTURA` }); }
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_quimic/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 300))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
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
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
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


const tocarTarjeta = async (p, clave) => { await p.waitForSelector(`button[data-tarjeta=${clave}]`); await p.evaluate((c) => document.querySelector(`button[data-tarjeta=${c}]`).click(), clave); await p.waitForSelector(".fq #fq-cantidad"); };
const pulsar = (p, sel) => p.evaluate((s) => { const b = document.querySelector(s); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
// una «foto de celular» de prueba: JPEG de 2.400 × 1.800 px con ruido (pesa varios cientos de KB), hecha en el propio Chrome
const FOTO = join(dir, "remision_de_prueba.jpg");
{ const pg = await nav.newPage();
  const b64 = await pg.evaluate(() => { const c = document.createElement("canvas"); c.width = 2400; c.height = 1800; const x = c.getContext("2d"); const im = x.createImageData(2400, 1800);
    for (let i = 0; i < im.data.length; i += 4) { const v = (i * 2654435761) >>> 24; im.data[i] = v; im.data[i + 1] = 255 - v; im.data[i + 2] = (v * 7) & 255; im.data[i + 3] = 255; }
    x.putImageData(im, 0, 0); x.fillStyle = "#fff"; x.fillRect(200, 200, 2000, 500); x.fillStyle = "#000"; x.font = "120px sans-serif"; x.fillText("REMISION R-0099 (prueba)", 260, 500);
    return c.toDataURL("image/jpeg", 0.95).split(",")[1]; });
  writeFileSync(FOTO, Buffer.from(b64, "base64")); await pg.close(); }
const BYTES_ORIGINAL = readFileSync(FOTO).length;

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0; subidas.length = 0;
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('${EMAILS.op2}', 'asignar_formulario', 'uso_quimicos'), ('${EMAILS.op2}', 'asignar_formulario', 'entrada_quimicos')`);

  // ===== A. El operador: entrada con la foto de la remisión =====
  let p = await abrir(ancho, "op2"); await tocarTarjeta(p, "entrada_quimicos");
  let t = await texto(p);
  ok(`${tag} A1 «Entrada de químicos» ofrece la foto de la remisión, como opcional (dentro de «Datos de la remisión (opcionales)»)`, /Foto de la remisión/.test(t) && /Tomar o elegir la foto de la remisión/.test(t));
  ok(`${tag} A1b (7c-bis) el selector acepta imágenes y NO lleva «capture»: el celular ofrece cámara, galería y archivos`,
     (await p.evaluate(() => { const i = document.querySelector("#fq-foto"); return i && i.getAttribute("accept") === "image/*" && !i.hasAttribute("capture"); })) === true);
  await pulsar(p, "[data-quimico=pac]"); await poner(p, "#fq-cantidad", "1,5"); await poner(p, "#fq-remision", "R-0099");
  await (await p.$("#fq-foto")).uploadFile(FOTO); await p.waitForSelector(".fq-foto-vista img", { timeout: 20000 });
  const vista = await p.evaluate(() => { const i = document.querySelector(".fq-foto-vista img"); return { ancho: i.naturalWidth, alto: i.naturalHeight, texto: document.querySelector(".fq-foto-pie").innerText, dentro: i.getBoundingClientRect().right <= document.documentElement.clientWidth }; });
  const kb = Number((vista.texto.match(/(\d+) KB/) || [])[1]);
  ok(`${tag} A2 la foto se achica antes de subir (lado mayor de 1.600 px, JPEG): de ${Math.round(BYTES_ORIGINAL / 1024)} KB a ${kb} KB, se ve en la pantalla y dice que se sube al guardar`,
     vista.ancho === 1600 && vista.alto === 1200 && kb > 20 && kb * 1024 < BYTES_ORIGINAL && kb * 1024 < 3145728 && /se sube al guardar/.test(vista.texto) && vista.dentro, JSON.stringify(vista));
  ok(`${tag} A3 nada se subió todavía (ni se reservó la foto)`, subidas.length === 0 && !rpcs.some((r) => r.fn === "geoportal_tec_quimico_remision_preparar"));
  ok(`${tag} A4 sin desborde y con botones de al menos 44 px`, (await sinDesborde(p)) && (await minimo(p, ".fq button, .fq .fq-foto-boton")) >= 44, String(await minimo(p, ".fq button, .fq .fq-foto-boton")));
  await p.screenshot({ path: join(CAP, `entrada_con_foto_${ancho}.png`), fullPage: true });
  await clicTexto(p, ".fq .tec-boton", "Guardar la entrada"); await esperarTexto(p, /Entrada registrada/);
  const fila = sqlq("select coalesce(string_agg(q.codigo || '|' || m.cantidad_kg || '|' || coalesce(m.remision, '-') || '|' || (m.remision_foto ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}[.]jpg$') || '|' || m.autor, ' ; '), '') from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id where m.tipo = 'entrada'");
  ok(`${tag} A5 al guardar: «Entrada registrada … con la foto de la remisión» y la entrada queda con su foto`, /con la foto de la remisión/.test(await texto(p)) && fila === `pac|1500.0|R-0099|true|${EMAILS.op2}`, fila);
  const obj = sqlq("select coalesce(string_agg(o.bucket_id || '|' || (o.metadata ->> 'mimetype') || '|' || ((o.metadata ->> 'size')::int between 20000 and 3145728), ' ; '), '') from storage.objects o join tecnica.quimico_movimientos m on m.remision_foto = o.name");
  ok(`${tag} A6 la foto quedó en el bucket privado de Técnica, como JPEG y dentro del tamaño; se reservó y se subió una sola vez`, obj === "tecnica-evidencias|image/jpeg|true"
     && rpcs.filter((r) => r.fn === "geoportal_tec_quimico_remision_preparar").length === 1 && subidas.length === 1, obj + " · " + JSON.stringify(subidas).slice(0, 200));
  ok(`${tag} A7 después de guardar, la pantalla queda sin foto, lista para otra entrada`, !(await p.$(".fq-foto-vista")) && !!(await p.$("#fq-foto")));
  await (await p.$("#fq-foto")).uploadFile(FOTO); await p.waitForSelector(".fq-foto-vista img");
  await clicTexto(p, ".fq-foto-pie button", "Quitar la foto"); await p.waitForSelector("#fq-foto");
  await pulsar(p, "[data-unidad=kg]"); await poner(p, "#fq-cantidad", "40");
  await clicTexto(p, ".fq .tec-boton", "Guardar la entrada"); await esperarTexto(p, /Entrada registrada: 40 kg/);
  ok(`${tag} A8 «Quitar la foto» la descarta y la foto es opcional: la segunda entrada se guarda sin foto`, sqlq("select count(*) || '|' || count(remision_foto) from tecnica.quimico_movimientos where tipo = 'entrada'") === "2|1"
     && !/con la foto/.test(await p.evaluate(() => document.querySelector(".tec-aviso-ok").innerText)) && subidas.length === 1);
  await p.close();

  // ===== B. El supervisor de planta: la foto en el historial =====
  p = await abrir(ancho, "planta"); await alQuimicos(p);
  await enTarjeta(p, "pac", "Historial"); await p.waitForSelector("[data-quimico=pac] [data-form=historial] .qm-historial");
  const enlaces = await p.evaluate(() => [...document.querySelectorAll("[data-form=historial] a[data-remision-foto]")].map((a) => ({ t: a.textContent, href: a.getAttribute("href"), fila: a.closest("li").innerText })));
  ok(`${tag} B1 en el historial del PAC, la entrada con remisión R-0099 tiene «Ver la foto de la remisión» (una URL firmada de lectura) y la otra entrada no`,
     enlaces.length === 1 && enlaces[0].t === "Ver la foto de la remisión" && /token=/.test(enlaces[0].href) && /R-0099/.test(enlaces[0].fila) && firmasLectura.some((f) => /remisiones\//.test(f)), JSON.stringify(enlaces));
  ok(`${tag} B2 sin desborde en el historial`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `historial_con_foto_${ancho}.png`), fullPage: true });

  // ===== C. Parámetros =====
  await clicTexto(p, ".qm-seg [role=tab]", "Parámetros"); await p.waitForSelector("[data-parametro=desvio_pct]");
  const ps = await p.evaluate(() => [...document.querySelectorAll("[data-parametro]")].map((a) => `${a.dataset.parametro}:${a.querySelector(".qm-param-valor strong").textContent}`).join(","));
  ok(`${tag} C1 «Parámetros» muestra los 4 que se editan con su valor: desvío 25 %, marca encendida y 7 días atrás`, ps === "desvio_pct:25,marca_esperado_usado:1,dias_atras_uso:7,dias_atras_entrada:7", ps);
  ok(`${tag} C2 cada uno dice su rango y que no tiene cambios`, /entre 1 y 500/.test(await p.evaluate(() => document.querySelector("[data-parametro=desvio_pct]").innerText)) && /Sin cambios/.test(await texto(p)));
  await clicTexto(p, "button", "Cambiar", "[data-parametro=desvio_pct]"); await p.waitForSelector("[data-parametro=desvio_pct] [data-form=parametro]");
  const guardarOff = () => p.evaluate(() => [...document.querySelectorAll("[data-form=parametro] button")].find((b) => b.textContent.startsWith("Guardar"))?.disabled);
  await poner(p, "#qm-p-desvio_pct", "900");
  ok(`${tag} C3 un valor fuera del rango no se deja guardar y dice el rango`, (await guardarOff()) === true && /Debe estar entre 1 y 500/.test(await texto(p)));
  await poner(p, "#qm-p-desvio_pct", "30");
  ok(`${tag} C4 sin motivo tampoco`, (await guardarOff()) === true);
  await poner(p, "#qm-p-m-desvio_pct", "El jefe de planta ajusta el desvío de la marca");
  ok(`${tag} C5 formulario sin desborde, con campos y botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, "[data-form=parametro] input, [data-form=parametro] textarea, [data-form=parametro] button")) >= 44);
  await p.screenshot({ path: join(CAP, `parametros_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Guardar el cambio", "[data-form=parametro]"); await esperarTexto(p, /de 25 a 30/);
  await p.waitForFunction(() => /Último cambio: de 25 a 30/.test(document.querySelector("[data-parametro=desvio_pct]")?.innerText ?? ""), { timeout: 15000 }).catch(() => {});
  ok(`${tag} C6 guarda el cambio: el aviso «de 25 a 30», la tarjeta con 30 y su último cambio (motivo y quién)`,
     /Último cambio: de 25 a 30 · «El jefe de planta ajusta el desvío de la marca» · /.test(await p.evaluate(() => document.querySelector("[data-parametro=desvio_pct]").innerText))
     && sqlq("select valor || '|' || (select antes || '>' || despues || '|' || autor from tecnica.quimico_parametro_eventos order by id desc limit 1) from tecnica.quimico_parametros where clave = 'desvio_pct'") === `30|25>30|${EMAILS.planta}`,
     await p.evaluate(() => document.querySelector("[data-parametro=desvio_pct]").innerText));
  await clicTexto(p, ".qm-seg [role=tab]", "Esperado contra usado"); await p.waitForFunction(() => !/Calculando/.test(document.body.innerText), { timeout: 20000 }).catch(() => {});
  ok(`${tag} C7 «Esperado contra usado» ya trabaja con el 30 %`, /30\s?%/.test(await texto(p)), (await texto(p)).slice(0, 400));
  await p.close();

  // ===== D. Quien no supervisa =====
  ok(`${tag} D1 el operador nunca pidió parámetros ni historial`, !rpcs.some((r) => r.a.p_solicitante === EMAILS.op2 && /parametro|historial/.test(r.fn)));
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
