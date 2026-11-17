// Prueba en Chrome REAL del Corte 13 de Técnica fase 1: estandarización visual. Mide en el navegador (no en el código) la fuente de cada texto, el color de cada modo
// (selector, tarjetas, encabezados, botones principales y bordes), los nombres de los modos, los textos corregidos, que no haya emojis ni degradados, el geovisor neutro
// y el correo del encabezado en Arial/Helvetica. Toma capturas de cada pantalla. A 390 px (táctil) y 1280 px, con cuentas de cada perfil.
// · Con SOLO_CAPTURAS=1 solo toma las capturas (sirve para las de «antes», corriéndola sobre la rama del 12).
// Uso: node scripts/prueba_chrome_estilo_c13.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <rehacer_base.sh del 12> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c13"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_estilo_c13.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54971, P_EDGE = 54972;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };      // planta: supervisor de planta; dist: supervisor de distribución
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: ["entrada", "entrada_quimicos", "uso_quimicos"] };
const DESC_SERVIDOR = { danos_fallas: "Daños o fallas en la planta", mantenimiento: "Mantenimiento, reparación e inversión" };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo", entrada: "Entrada", entrada_quimicos: "Entrada de químicos", uso_quimicos: "Uso de químicos" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c13_"));
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
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><header class="barra" style="height:54px;flex:0 0 auto"><div class="barra-marca">Geoportal</div><div class="barra-usuario"><span class="mono barra-correo">persona</span></div></header><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

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
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: DESC_SERVIDOR[c] ?? "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
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
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_(punto|quimic|aviso)/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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



const SOLO = process.env.SOLO_CAPTURAS === "1";
const pulsar = (p, sel) => p.evaluate((s) => { const b = document.querySelector(s); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const RGB = { plantas: "rgb(10, 37, 64)", distribucion: "rgb(15, 61, 43)", supervision: "rgb(30, 90, 168)", geo: "rgb(107, 98, 88)" };
/** Todo texto visible de la pantalla debe estar en Arial/Helvetica (salvo códigos con .tec-codigo y los controles del mapa). Devuelve los que no. */
const fuentesMal = (p) => p.evaluate(() => {
  const mal = new Set();
  const w = document.createTreeWalker(document.getElementById("raiz"), NodeFilter.SHOW_TEXT);
  for (let n = w.nextNode(); n; n = w.nextNode()) {
    if (!n.textContent.trim()) continue; const el = n.parentElement; if (!el || !el.offsetParent) continue;
    if (el.closest(".tec-codigo, .maplibregl-ctrl, .maplibregl-ctrl-attrib")) continue;
    const f = getComputedStyle(el).fontFamily.split(",")[0].trim().replace(/"/g, "");
    if (!/^(Arial|Helvetica)$/.test(f)) mal.add(`${f}: ${n.textContent.trim().slice(0, 30)}`);
  }
  return [...mal].slice(0, 8); });
const emojis = (p) => p.evaluate(() => { const r = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u2714\u2716\u2705\u274C\u2B50]/u;      // ← y ✕ (flecha y cerrar) no cuentan
  return document.getElementById("raiz").innerText.split("\n").filter((l) => r.test(l)).slice(0, 5); });
const degradados = (p) => p.evaluate(() => [...document.querySelectorAll("#raiz *")].filter((e) => e.offsetParent && /gradient/.test(getComputedStyle(e).backgroundImage)).length);
const estilo = (p, sel, props) => p.evaluate((s, ps) => { const e = document.querySelector(s); if (!e) return null; const c = getComputedStyle(e); return Object.fromEntries(ps.map((k) => [k, c[k]])); }, sel, props);
const textoDe = (p, sel) => p.evaluate((s) => document.querySelector(s)?.innerText ?? "", sel);
const limpio = async (tag, nombre, p) => {
  const f = await fuentesMal(p), e = await emojis(p), d = await degradados(p);
  ok(`${tag} ${nombre}: todo el texto en Arial/Helvetica, sin emojis y sin degradados`, f.length === 0 && e.length === 0 && d === 0, JSON.stringify({ f, e, d }));
};
/** Botones de foto: cada uno lleva delante el ícono de cámara de línea (SVG de 18 px, del color del texto del botón; sin emoji). */
const iconos = (p, sel) => p.evaluate((sel) => [...document.querySelectorAll(sel)].filter((b) => b.offsetParent).map((b) => {
  const s = b.querySelector("svg[data-icono=camara]"); if (!s) return { txt: b.textContent.trim(), ok: false };
  const cb = getComputedStyle(b).color, cs = getComputedStyle(s).stroke ?? s.getAttribute("stroke"), r = s.getBoundingClientRect();
  return { txt: b.textContent.trim(), ok: b.firstElementChild === s && Math.round(r.width) === 18 && Math.round(r.height) === 18 && (cs === cb || s.getAttribute("stroke") === "currentColor") && s.getAttribute("aria-hidden") === "true" };
}), sel);
const capturar = (p, nombre, ancho, todo = true) => p.screenshot({ path: join(CAP, `${nombre}_${ancho}.png`), fullPage: todo });
const modoA = async (p, m) => { await p.evaluate((m) => document.querySelector(`[role=tab][data-modo=${m}]`)?.click(), m); await p.waitForSelector(`[data-modo-actual=${m}]`); };

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op2}', 'asignar_formulario', 'uso_quimicos', '${EMAILS.adm}'), ('${EMAILS.op2}', 'asignar_formulario', 'entrada_quimicos', '${EMAILS.adm}')`);

  // ===== A. Inicio por modos: nombres y colores =====
  let p = await abrir(ancho, "adm"); await p.waitForSelector("[data-modo-actual]");
  const tabs = await p.evaluate(() => [...document.querySelectorAll('[role=tab][data-modo]')].map((t) => t.textContent.trim()).join(","));
  if (!SOLO) ok(`${tag} A1 los modos se llaman «Distribución» y «Supervisión» (el administrador no tiene formularios de planta)`, tabs === "Distribución,Supervisión", tabs);
  await modoA(p, "redes"); await capturar(p, "inicio_distribucion", ancho, false);
  const tr = await estilo(p, "[role=tab][data-modo=redes]", ["backgroundColor"]), cr = await estilo(p, ".tec-tarjeta-modo", ["borderLeftColor", "borderLeftWidth"]), ir = await estilo(p, ".tec-tarjeta-ini", ["backgroundColor"]);
  const descs = await p.evaluate(() => Object.fromEntries([...document.querySelectorAll("[data-tarjeta]")].map((t) => [t.dataset.tarjeta, t.querySelector(".tec-tarjeta-desc")?.textContent ?? ""])));
  if (!SOLO) {
    ok(`${tag} A2 Distribución: selector, borde izquierdo grueso (5 px) y cuadro de la inicial en verde oscuro #0f3d2b`, tr?.backgroundColor === RGB.distribucion && cr?.borderLeftColor === RGB.distribucion && cr?.borderLeftWidth === "5px" && ir?.backgroundColor === RGB.distribucion, JSON.stringify({ tr, cr, ir }));
    ok(`${tag} A3 los textos corregidos: el daño habla de la red y la intervención dice para qué sirve (no repite el nombre)`,
       descs.danos_fallas === "Un daño o una falla en la red de acueducto o alcantarillado" && descs.mantenimiento === "Registrar una reparación, un mantenimiento o una obra", JSON.stringify(descs));
  }
  await modoA(p, "supervision"); await capturar(p, "inicio_supervision", ancho, false);
  const ts = await estilo(p, "[role=tab][data-modo=supervision]", ["backgroundColor"]), cs = await estilo(p, ".tec-tarjeta-modo", ["borderLeftColor"]);
  const cols = await p.evaluate(() => new Set([...document.querySelectorAll(".tec-rejilla > *")].map((e) => Math.round(e.getBoundingClientRect().left))).size);
  if (!SOLO) {
    ok(`${tag} A4 Supervisión en azul #1e5aa8`, ts?.backgroundColor === RGB.supervision && cs?.borderLeftColor === RGB.supervision, JSON.stringify({ ts, cs }));
    ok(`${tag} A5 la rejilla: ${ancho < 500 ? "una columna en el celular" : "4 columnas en el PC"}`, cols === (ancho < 500 ? 1 : 4), String(cols));
    await limpio(tag, "A6 inicio", p);
    const correo = await estilo(p, ".barra-correo", ["fontFamily", "fontWeight", "color"]);
    ok(`${tag} A7 el correo del encabezado en Arial/Helvetica, peso normal y gris claro (ya no Courier)`, /^Arial/.test(correo?.fontFamily ?? "") && correo?.fontWeight === "400" && correo?.color === "rgb(201, 216, 234)", JSON.stringify(correo));
    ok(`${tag} A8 la página ya no pide Space Grotesk ni IBM Plex Mono`, !(await p.evaluate(() => [...document.querySelectorAll("link")].some((l) => /Space\+Grotesk|IBM\+Plex\+Mono/.test(l.href)))));
  }

  // ===== B. Avisos (Supervisión) =====
  await pulsar(p, "button[data-tarjeta=avisos]"); await p.waitForSelector("section[data-area]", { timeout: 30000 });
  await capturar(p, "avisos", ancho);
  if (!SOLO) { const b = await estilo(p, ".av-abrir", ["borderTopColor", "minHeight"]); ok(`${tag} B1 Avisos en el color de Supervisión, botones de 44 px`, b?.borderTopColor === RGB.supervision && parseFloat(b.minHeight) >= 44, JSON.stringify(b)); await limpio(tag, "B2 avisos", p); }
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-modo-actual]");

  // ===== C. Dashboard distribución (verde) y el PTAP (azul oscuro) =====
  await modoA(p, "supervision"); await pulsar(p, "button[data-tarjeta=dashboard_distribucion]"); await p.waitForSelector(".tdash-cab", { timeout: 30000 }); await esperarTexto(p, /No identificados/);
  await capturar(p, "dashboard_distribucion", ancho, false);
  if (!SOLO) {
    const cab = await estilo(p, ".tdash-cab", ["backgroundColor"]), act = await estilo(p, ".tdash-tab[aria-current=page]", ["borderBottomColor"]);
    ok(`${tag} C1 Dashboard distribución: encabezado verde oscuro y la pestaña activa subrayada en blanco (sin el turquesa)`, cab?.backgroundColor === RGB.distribucion && act?.borderBottomColor === "rgb(255, 255, 255)", JSON.stringify({ cab, act }));
    ok(`${tag} C2 «← Volver al inicio»`, /← Volver al inicio/.test(await textoDe(p, ".tdash-cab")));
    await clicTexto(p, ".tdash-tabs [role=tab]", "Daños y fallas"); await new Promise((x) => setTimeout(x, 800));
    const bot = await estilo(p, ".dash-redes .dan-opcion[aria-pressed=true], .dash-redes [role=tab][aria-selected=true], .dash-redes [aria-pressed=true], .dash-redes .tec-boton, .dash-redes .tec-boton-sec", ["backgroundColor", "borderTopColor", "color"]);
    ok(`${tag} C3 los botones del dashboard toman el verde (no el turquesa de antes)`, bot && [bot.backgroundColor, bot.borderTopColor, bot.color].includes(RGB.distribucion), JSON.stringify(bot));
    await limpio(tag, "C4 dashboard distribución", p);
  }
  await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, ".tdash-tabs [role=tab]", "Químicos"); await p.waitForSelector(".qm-seg", { timeout: 20000 });
  await capturar(p, "dashboard_ptap_quimicos", ancho);
  if (!SOLO) {
    const cab = await estilo(p, ".tdash-cab", ["backgroundColor"]), seg = await estilo(p, ".qm-seg [aria-selected=true]", ["backgroundColor"]), tar = await estilo(p, ".qm-tarjeta", ["borderLeftColor", "borderLeftWidth"]);
    ok(`${tag} C5 Dashboard PTAP: encabezado, selección y tarjetas en azul oscuro #0a2540, con el borde grueso`, cab?.backgroundColor === RGB.plantas && seg?.backgroundColor === RGB.plantas && tar?.borderLeftColor === RGB.plantas && tar?.borderLeftWidth === "5px", JSON.stringify({ cab, seg, tar }));
    await limpio(tag, "C6 dashboard PTAP", p);
  }
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector("[data-modo-actual]");

  // ===== D. Geovisor: neutro, gris tirando a sepia =====
  await modoA(p, "supervision"); await pulsar(p, "button[data-tarjeta=geovisor]"); await p.waitForSelector(".geo-barra", { timeout: 30000 });
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 }).catch(() => {});
  await capturar(p, "geovisor", ancho, false);
  if (!SOLO) { const g = await estilo(p, ".geo-barra", ["backgroundColor"]); ok(`${tag} D1 el geovisor es neutro: barra gris tirando a sepia (#6b6258), no el verde de distribución`, g?.backgroundColor === RGB.geo, JSON.stringify(g)); await limpio(tag, "D2 geovisor", p); }
  await pulsar(p, ".geo-volver"); await p.waitForSelector("[data-modo-actual]");

  // ===== E. Ficha de activos (Distribución) =====
  await modoA(p, "supervision"); await pulsar(p, "button[data-tarjeta=ficha_editar]"); await new Promise((x) => setTimeout(x, 1200));
  await capturar(p, "ficha_buscar", ancho);
  if (!SOLO) await limpio(tag, "E1 ficha de activos", p);
  await p.close();

  // ===== F. Formulario de distribución: daño o falla =====
  p = await abrir(ancho, "op"); await p.waitForSelector("[data-modo-actual], .tec-tarjetas");
  const unico = await p.evaluate(() => document.querySelector(".tec-modo-unico")?.textContent ?? "");
  if (!SOLO) ok(`${tag} F1 el operador de redes, con un solo modo, lo ve nombrado «Distribución»`, unico === "Distribución", unico);
  await pulsar(p, "button[data-tarjeta=danos_fallas]"); await p.waitForSelector(".dan-cabeza", { timeout: 30000 });
  await capturar(p, "form_dano", ancho);
  await p.evaluate(() => [...document.querySelectorAll("button")].find((b) => /^Foto: /.test(b.textContent.trim()))?.scrollIntoView({ block: "center" })); await capturar(p, "form_dano_fotos", ancho, false);
  if (!SOLO) {
    const cab = await estilo(p, ".dan-cabeza", ["backgroundColor"]), sec = await estilo(p, ".dan .tec-tarjeta", ["borderLeftColor", "borderLeftWidth", "backgroundColor"]);
    const fotos = await p.evaluate(() => [...document.querySelectorAll("button")].map((b) => b.textContent.trim()).filter((t) => /^Foto: /.test(t)));
    ok(`${tag} F2 «Reportar daño o falla»: encabezado verde de distribución (antes, rojo ladrillo) y cada sección como tarjeta blanca con su borde verde`, cab?.backgroundColor === RGB.distribucion && sec?.borderLeftColor === RGB.distribucion && sec?.borderLeftWidth === "5px" && sec?.backgroundColor === "rgb(255, 255, 255)", JSON.stringify({ cab, sec }));
    ok(`${tag} F3 los botones de fotos dicen «Foto: …» (sin el emoji de la cámara)`, fotos.length === 3 && fotos[0] === "Foto: El daño", fotos.join(","));
    const ic = await iconos(p, ".dan button.tec-boton-sec");
    const icF = ic.filter((x) => /^Foto: /.test(x.txt));
    ok(`${tag} F3b cada botón de foto del daño lleva delante el ícono de cámara de línea (SVG de 18 px, del color del texto)`, icF.length === 3 && icF.every((x) => x.ok), JSON.stringify(icF));
    ok(`${tag} F4 botones de 44 px o más`, (await minimo(p, ".dan button.tec-boton, .dan button.tec-boton-sec, .dan button.dan-opcion")) >= 44);
    ok(`${tag} F5 sin desborde`, await sinDesborde(p));
    await limpio(tag, "F6 formulario de daño", p);
  }
  await clicTexto(p, "button", "← Volver"); await p.waitForSelector(".tec-tarjetas");
  await pulsar(p, "button[data-tarjeta=mantenimiento]"); await p.waitForSelector(".itv-cabeza", { timeout: 30000 });
  await capturar(p, "form_intervencion", ancho);
  await p.evaluate(() => [...document.querySelectorAll("button")].find((b) => /^Foto: /.test(b.textContent.trim()))?.scrollIntoView({ block: "center" })); await capturar(p, "form_intervencion_fotos", ancho, false);
  if (!SOLO) { const icI = (await iconos(p, ".itv button.tec-boton-sec, .dan button.tec-boton-sec")).filter((x) => /^Foto: /.test(x.txt));
    ok(`${tag} F7b los botones de foto de la intervención («Foto: Antes», «Durante», «Después») con el ícono de cámara`, icI.length === 3 && icI.every((x) => x.ok), JSON.stringify(icI)); }
  if (!SOLO) { const cab = await estilo(p, ".itv-cabeza", ["backgroundColor"]); ok(`${tag} F7 «Registrar intervención» también en verde (antes, azul)`, cab?.backgroundColor === RGB.distribucion, JSON.stringify(cab)); await limpio(tag, "F8 formulario de intervención", p); }
  await p.close();

  // ===== G. Formulario de planta: entrada de químicos =====
  p = await abrir(ancho, "op2"); await p.waitForSelector(".tec-tarjetas");
  const unico2 = await p.evaluate(() => document.querySelector(".tec-modo-unico")?.textContent ?? "");
  if (!SOLO) ok(`${tag} G1 el operador de planta lo ve nombrado «Plantas»`, unico2 === "Plantas", unico2);
  await pulsar(p, "button[data-tarjeta=entrada_quimicos]"); await p.waitForSelector(".fq #fq-cantidad", { timeout: 30000 });
  await capturar(p, "form_entrada_quimicos", ancho);
  if (!SOLO) {
    const b = await estilo(p, ".fq .tec-boton", ["backgroundColor", "minHeight"]), op = await estilo(p, ".fq-opcion[aria-pressed=true], .tec-planta[aria-pressed=true]", ["backgroundColor"]), sec = await estilo(p, ".fq .tec-tarjeta, .tec-pagina .tec-tarjeta", ["borderLeftColor"]);
    ok(`${tag} G2 «Entrada de químicos»: botón principal, opción elegida y bordes en azul oscuro de Plantas (antes, turquesa)`, b?.backgroundColor === RGB.plantas && parseFloat(b.minHeight) >= 44 && (!op || op.backgroundColor === RGB.plantas) && sec?.borderLeftColor === RGB.plantas, JSON.stringify({ b, op, sec }));
    await limpio(tag, "G3 formulario de químicos", p);
    const icR = await iconos(p, "label.fq-foto-boton");
    ok(`${tag} G4 «Tomar o elegir la foto de la remisión» con el ícono de cámara delante`, icR.length === 1 && icR[0].ok, JSON.stringify(icR));
    await p.evaluate(() => document.querySelector("label.fq-foto-boton")?.scrollIntoView({ block: "center" })); await capturar(p, "form_remision_boton", ancho, false);
  }
  await p.close();
}
if (!SOLO) {
  ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
  ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));
}
await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(SOLO ? `CAPTURAS en ${CAP}` : `RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(SOLO || bien === resultados.length ? 0 : 1);
