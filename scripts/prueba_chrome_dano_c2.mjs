// Técnica · Fase 1 · Corte 2 · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada → Edges REALES geoportal-tecnica y geoportal-redes (Deno) → PostgREST mínimo en Node que llama a las RPC REALES de redes en el PostGIS local
//   (redes_local con el 1a, el Corte 2 y la carga completa de los shapefiles), más un Storage simulado (firma y subida que escriben en storage.objects local).
// «Reportar daño o falla» a 390 px y en escritorio: sistema → minimapa (WebGL con SwiftShader; teselas MVT reales; base OSM sustituida por un PNG en blanco),
// activo más cercano preseleccionado (GPS simulado), tocar un tramo → sus nodos, «Ver ficha», búsqueda por código, cámara (dispositivo falso de Chrome),
// validaciones, guardado y su epicrisis; y el «no identificado» marcando el punto en el mapa.
//   node scripts/prueba_chrome_dano_c2.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_dano_c2"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_dano_c2.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co" };
const PERFIL = { [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor" };

if (sqlq("select count(*) from redes.activo_vigente_mat") !== "35781") throw new Error("La base local no tiene la carga publicada");
if (sqlq("select to_regclass('redes.danos') is not null") !== "t") throw new Error("La base local no tiene el Corte 2");
const n0 = Number(sqlq("select count(*) from redes.danos"));
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_dano_c2_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
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
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head><body><div id="raiz" style="display:flex;min-height:100vh"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST + Storage simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], subidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
  try {
    const out = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const t = out.trim();
    return { status: 200, cuerpo: fn === "geoportal_redes_mvt" ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
const PNG_BLANCO = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAACwElEQVR4nO3TMQ0AMAzAsPKnumcagsHoEUsGkCfz7oGsWS+ARQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQNoHNckqBAbZ8j0AAAAASUVORK5CYII=", "base64");   // 256×256 gris claro
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
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, args: a });
      if (fn === "geoportal_tec_mis_formularios") {
        const p = PERFIL[a.p_solicitante];
        return p ? json(200, { perfil: p, formularios: [{ clave: "danos_fallas", nombre: "Daño o falla", descripcion: "", con_campos: false }, { clave: "mantenimiento", nombre: "Registrar intervención", descripcion: "", con_campos: false }] }) : json(403, { code: "42501", message: "Sin permiso" });
      }
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      return json(404, { code: "PGRST202", message: "no existe" });
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
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 700) }); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
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
  // pruebas anteriores al Corte 11: el inicio y el formulario estaban en la misma página; si el botón no está y hay un formulario abierto, se vuelve al inicio
  if (!b && document.querySelector(".tec-volver")) { document.querySelector(".tec-volver").click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); }
  if (!b && document.querySelector("[data-modo-actual]")) for (const m of document.querySelectorAll(tabs)) { m.click(); await new Promise((x) => setTimeout(x, 0)); b = buscar(); if (b) break; }
  if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro, TABS_MODO);
/** Todo lo que la persona tiene en el inicio (la suma de sus modos). */
const textoInicio = (p) => p.evaluate(async (sel) => {
  const tabs = [...document.querySelectorAll(sel)]; if (!tabs.length) return document.body.innerText;
  let s = ""; for (const t of tabs) { t.click(); await new Promise((x) => setTimeout(x, 0)); s += document.body.innerText + "\n"; }
  tabs[0].click(); await new Promise((x) => setTimeout(x, 0)); return s; }, TABS_MODO);
/** Abre un formulario desde su tarjeta del inicio (antes el primero se abría solo). */
const abrirFormulario = async (p, nombre) => { await esperarTexto(p, new RegExp(nombre)); if (!(await clicTexto(p, "button.tec-tarjeta-modo", nombre))) throw new Error("no está la tarjeta " + nombre); await p.waitForSelector(".tec-volver-barra"); };
/** Pruebas anteriores al Corte 11: el formulario de daño se abría solo al entrar. Aquí se abre desde su tarjeta, si la persona la tiene. */
const abrirDanoComoAntes = async (p) => {
  await esperarTexto(p, /Sesión de/);
  const hay = await p.evaluate(async (sel) => { const b = () => document.querySelector("button[data-tarjeta=danos_fallas]");
    if (!b()) for (const m of document.querySelectorAll(sel)) { m.click(); await new Promise((x) => setTimeout(x, 0)); if (b()) break; }
    if (!b()) return false; b().click(); return true; }, TABS_MODO);
  if (hay) await esperarTexto(p, /1\. Activo y ubicación/);
};
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const elegirSelect = (p, sel, valor) => p.select(sel, valor);
const minimos = (p) => p.evaluate(() => Math.min(...[...document.querySelectorAll(".dan-opcion:not(.dan-opcion-off), .dan .tec-boton, .dan .tec-boton-sec, .dan-check")].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)));
async function abrir(ancho, rol, gps) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  // Sin intercepción de peticiones: con ella, las peticiones del worker de MapLibre (las teselas vectoriales) quedan en pausa. La base de OSM se bloquea con
  // --host-resolver-rules (sin red externa) y sus fallos se ignoran: no son de la app.
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("response", (r) => { if (r.url().includes("accion=tesela")) teselas.push(`${r.status()} ${r.url().split("?")[1]}`); });
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let t = m.text();
    if (/JSHandle@/.test(t)) t = (await Promise.all(m.args().map((a) => a.evaluate((x) => (x instanceof Error ? `${x.name}: ${x.message} ${x.url ?? ""} ${x.status ?? ""}` : String(x))).catch(() => "?")))).join(" ");
    if (!/status of 40[034]|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError: Failed to fetch|^TypeError: Failed to fetch/.test(t)) errores.push(`${ancho} ${rol} consola ${m.type()}: ${t}`);
  });
  if (gps) await p.setGeolocation({ latitude: gps[0], longitude: gps[1], accuracy: 6 });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true);
  await abrirDanoComoAntes(p); return p;
}
/** Espera a que el minimapa tenga red dibujada. */
const teselas = [];
const esperarRed = async (p) => {
  try { await p.waitForFunction(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["tramos", "nodos"] }).length > 0; }, { timeout: 30000 }); }
  catch {
    const est = await p.evaluate(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; if (!m) return "sin mapa"; return JSON.stringify({ cargado: m.loaded(), zoom: m.getZoom(), centro: m.getCenter(), fuente: m.isSourceLoaded("red"), feats: m.queryRenderedFeatures().length, errores: window.__errMapa ?? [] }); });
    await p.screenshot({ path: join(CAP, "fallo_mapa.png") });
    throw new Error(`la red no se dibujó: ${est} · teselas: ${JSON.stringify(teselas.slice(-6))} · mvt en la base: ${rpcs.filter((r) => r.fn === "geoportal_redes_mvt").length} · ejemplo: ${JSON.stringify(rpcs.filter((r) => r.fn === "geoportal_redes_mvt").slice(0, 2))} · consola: ${errores.join(" | ").slice(0, 1500)}`);
  }
};
/** Punto en pantalla de un tramo visible (a mitad de su primer segmento), lejos de los nodos. */
const puntoDeTramo = (p) => p.evaluate(() => {
  const el = document.querySelector(".dan-mini-mapa"); el.scrollIntoView({ block: "center" }); const m = el.__mapa; const r = el.getBoundingClientRect();
  for (const f of m.queryRenderedFeatures({ layers: ["tramos"] })) {
    const c = f.geometry.type === "LineString" ? f.geometry.coordinates : f.geometry.coordinates[0];
    for (let i = 0; i + 1 < c.length; i++) {
      const px = m.project([(c[i][0] + c[i + 1][0]) / 2, (c[i][1] + c[i + 1][1]) / 2]);
      if (px.x < 30 || px.y < 30 || px.x > r.width - 30 || px.y > r.height - 30) continue;
      if (m.queryRenderedFeatures([[px.x - 16, px.y - 16], [px.x + 16, px.y + 16]], { layers: ["nodos"] }).length) continue;
      return { x: r.left + px.x, y: r.top + px.y, codigo: f.properties.codigo };
    }
  }
  return null;
});
const tocar = async (p, x, y, movil) => { if (movil) await p.touchscreen.tap(x, y); else await p.mouse.click(x, y); };
async function foto(p, momento) {
  await clicTexto(p, "button", `📷 ${momento}`); await p.waitForSelector(".campo-capturar:not([disabled])", { timeout: 15000 });
  const n = await p.evaluate(() => document.querySelectorAll(".dan-foto").length);
  await p.click(".campo-capturar"); await p.waitForFunction((n) => document.querySelectorAll(".dan-foto").length === n + 1, { timeout: 15000 }, n);
}

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`, movil = ancho < 500;
  // ===== Operador: daño sobre un activo identificado =====
  let p = await abrir(ancho, "op", [Number(V85[1]), Number(V85[2])]);
  let t = await texto(p);
  ok(`${tag} el chip «Daño o falla» abre el formulario (sin «Próximamente») y pide primero el sistema`, /Daño o falla/.test(t) && /Elija primero el sistema/.test(t) && /1\. Activo y ubicación/.test(t) && /7\. Fotos|6\. Fotos/.test(t));
  ok(`${tag} el operador no ve la entrada a la ficha de activos (David, 1b)`, !/Ficha de activos/.test(t));
  const prep0 = rpcs.filter((r) => r.fn === "geoportal_redes_preparar_dano").length;
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Falta completar/);
  t = await texto(p);
  ok(`${tag} guardar vacío: lista de lo que falta, sin llamar a la base`, /Elija el sistema/.test(t) && /Elija qué pasó/.test(t) && /Tome al menos una foto del daño/.test(t) && rpcs.filter((r) => r.fn === "geoportal_redes_preparar_dano").length === prep0);
  await clicTexto(p, ".dan-opcion", "Acueducto"); await esperarTexto(p, /Se preseleccionó el activo más cercano/);
  await esperarTexto(p, new RegExp(`${V85[0]}[\\s\\S]*Válvula · Cierre`));
  ok(`${tag} con GPS sobre V85: queda preseleccionada ${V85[0]} (Válvula · Cierre · V85)`, (await texto(p)).includes(`${V85[0]}`) && /Válvula · Cierre[^\n]*V85/.test(await texto(p)));
  await esperarRed(p);
  const zoomIni = await p.evaluate(() => document.querySelector(".dan-mini-mapa").__mapa.getZoom());
  const capas = await p.evaluate(() => [...new Set(document.querySelector(".dan-mini-mapa").__mapa.queryRenderedFeatures({ layers: ["tramos", "nodos", "tramos-punteados"] }).map((f) => f.properties.prefijo))].sort());
  ok(`${tag} minimapa: red de acueducto real dibujada desde la tesela (z ${zoomIni.toFixed(1)}), sin alcantarillado`, capas.includes("RED") && capas.includes("VAL") && !capas.includes("POZ") && !capas.includes("COL"), capas.join(","));
  const resaltada = (c, capa) => p.waitForFunction((c, capa) => document.querySelector(".dan-mini-mapa").__mapa.queryRenderedFeatures({ layers: [capa] }).some((f) => f.properties.codigo === c), { timeout: 8000 }, c, capa).then(() => true, () => false);
  ok(`${tag} la válvula preseleccionada se resalta en el mapa`, await resaltada(V85[0], "sel-nodo"),
     await p.evaluate((c) => { const m = document.querySelector(".dan-mini-mapa").__mapa; return JSON.stringify({ filtro: m.getFilter("sel-nodo"), zoom: m.getZoom(), enNodos: m.queryRenderedFeatures({ layers: ["nodos"] }).filter((f) => f.properties.codigo === c).length, centro: m.getCenter() }); }, V85[0]));
  await p.screenshot({ path: join(CAP, `minimapa_preseleccion_${ancho}.png`), fullPage: false });
  // tocar un tramo → sus nodos
  const pt = await puntoDeTramo(p);
  ok(`${tag} hay un tramo para tocar en el mapa`, !!pt);
  if (pt) {
    await tocar(p, pt.x, pt.y, movil); await esperarTexto(p, /Eligió el tramo/);
    t = await p.evaluate(() => document.querySelector(".dan-tramo")?.innerText ?? "");
    ok(`${tag} tocar el tramo ${pt.codigo}: aparecen sus dos nodos («Desde» y «Hasta»)`, t.includes(`Eligió el tramo ${pt.codigo}`) && /Desde: /.test(t) && /Hasta: /.test(t), t);
    ok(`${tag} y el tramo tocado se resalta en el mapa`, await resaltada(pt.codigo, "sel-tramo"));
    await p.screenshot({ path: join(CAP, `minimapa_tramo_nodos_${ancho}.png`), fullPage: false });
    const elegidoNodo = await p.evaluate(() => { const b = [...document.querySelectorAll(".dan-tramo .dan-opcion")].find((x) => x.tagName === "BUTTON" && /^Desde|^Hasta/.test(x.textContent)); if (!b) return null; b.click(); return b.textContent; });
    if (elegidoNodo) {
      await p.waitForFunction(() => /^(ACC|VAL|TOR|MAC|TAN|PTA)-/.test(document.querySelector(".dan-elegido strong")?.textContent ?? ""), { timeout: 8000 });
      ok(`${tag} elegir un nodo del tramo (${elegidoNodo.trim()}) cambia el activo elegido`, /^(ACC|VAL|TOR|MAC|TAN|PTA)-/.test(await p.evaluate(() => document.querySelector(".dan-elegido strong").textContent)));
    }
    await clicTexto(p, ".dan-tramo .dan-opcion", "Tramo"); await p.waitForFunction((c) => document.querySelector(".dan-elegido strong")?.textContent === c, { timeout: 8000 }, pt.codigo);
    ok(`${tag} y volver al tramo deja elegido ${pt.codigo}`, (await p.evaluate(() => document.querySelector(".dan-elegido strong").textContent)) === pt.codigo);
  }
  // buscar por código y «Ver ficha»
  await poner(p, "#dan-buscar", "V85"); await clicTexto(p, ".dan-buscar button", "Buscar"); await esperarTexto(p, /No identifico|V85/);
  await p.waitForFunction(() => document.querySelectorAll(".dan-buscar .red-fila").length > 0, { timeout: 8000 });
  await clicTexto(p, ".dan-buscar .red-fila", V85[0]); await p.waitForFunction((c) => document.querySelector(".dan-elegido strong")?.textContent === c, { timeout: 8000 }, V85[0]);
  ok(`${tag} buscar «V85» y elegirlo`, (await p.evaluate(() => document.querySelector(".dan-elegido strong").textContent)) === V85[0]);
  await clicTexto(p, ".dan-elegido button", "Ver ficha"); await esperarTexto(p, /Datos del activo/);
  ok(`${tag} «Ver ficha» abre la ficha del activo desde el minimapa (David, 1b)`, /Volver al daño/.test(await texto(p)) && (await texto(p)).includes(V85[0]));
  await p.evaluate(() => document.querySelector(".red-volver").click()); await esperarTexto(p, /1\. Activo y ubicación/);
  ok(`${tag} al volver de la ficha, el daño sigue igual (activo elegido)`, (await p.evaluate(() => document.querySelector(".dan-elegido strong")?.textContent)) === V85[0]);
  // qué pasó, tiempos, rotura, riesgo, causa, fotos
  await clicTexto(p, ".dan-opcion", "Falla"); t = await texto(p);
  ok(`${tag} «Falla» muestra sus tipos de acueducto (sin los de alcantarillado)`, /Válvula que no opera/.test(t) && !/Obstrucción/.test(t) && !/Rebose/.test(t));
  await clicTexto(p, ".dan-opcion", "Daño"); await clicTexto(p, ".dan-opcion", "Fuga o tubería rota"); await esperarTexto(p, /Tipo de rotura/);
  ok(`${tag} una fuga pide rotura, largo y presión, y avisa «sin tabla» de caudales`, /Posible pérdida de agua: sin tabla/.test(await texto(p)));
  await clicTexto(p, ".dan-opcion", "Rotura parcial"); await poner(p, "#dan-largo", "2,5");
  const ahora = await p.evaluate(() => document.querySelector("#dan-tdet").value);
  const menos = (min) => { const d = new Date(ahora + ":00"); d.setMinutes(d.getMinutes() - min); const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 16); };
  // Corte 4a (§25): los tiempos de la reparación se piden solo si se marca «El daño ya se reparó»
  await p.evaluate(() => [...document.querySelectorAll(".dan-check")].find((l) => /El daño ya se reparó/.test(l.textContent)).querySelector("input").click()); await p.waitForSelector("#dan-trep");
  await poner(p, "#dan-tini", menos(180)); await poner(p, "#dan-tdet", menos(150)); await poner(p, "#dan-trep", menos(75)); await poner(p, "#dan-tres", menos(10));
  t = await texto(p);
  ok(`${tag} los tiempos se calculan solos (respuesta 1 h 15 min, reparación 1 h 05 min, total 2 h 50 min)`, /Respuesta\s*1 h 15 min/.test(t) && /Reparación\s*1 h 05 min/.test(t) && /Total del daño\s*2 h 50 min/.test(t), t.match(/Respuesta[\s\S]{0,80}/)?.[0]);
  await poner(p, "#dan-usuarios", "40"); await clicTexto(p, ".dan-opcion", "Alto");
  await p.evaluate(() => [...document.querySelectorAll(".dan-check")].find((l) => /Hueco o hundimiento/.test(l.textContent)).querySelector("input").click());
  await clicTexto(p, ".dan-opcion", "De terceros"); await elegirSelect(p, "#dan-tercero", "vehiculo"); await poner(p, "#dan-tnombre", `Placa ZT${ancho}`);
  ok(`${tag} causa de terceros: avisa que el nombre o la placa es un dato personal`, /Es un dato personal: se guarda aparte y solo lo ve el supervisor/.test(await texto(p)));
  await foto(p, "El daño"); await foto(p, "Entorno");
  ok(`${tag} cámara: 2 fotos (el daño y el entorno) en miniatura`, (await p.evaluate(() => [...document.querySelectorAll(".dan-foto figcaption")].map((f) => f.textContent).join("|"))).match(/1\. El daño.*2\. Entorno/));
  await poner(p, "#dan-desc", "Prueba de Chrome: fuga en la válvula");
  ok(`${tag} la lista de lo que falta desaparece sola al completar el formulario`, !/Falta completar/.test(await texto(p)));
  ok(`${tag} el formulario lleno no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimos(p)) >= 44, String(await minimos(p)));
  await p.screenshot({ path: join(CAP, `dano_lleno_${ancho}.png`), fullPage: true });
  const s0 = subidas.length;
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Daño guardado: DAN-\d{6}/, 30000);
  t = await texto(p);
  const cod = t.match(/DAN-\d{6}/)[0];
  const fila = sqlq(`select d.activo_codigo || '|' || d.estado || '|' || d.ubicacion_origen || '|' || d.tipo_rotura || '|' || d.causa_clase || '|' || d.riesgo || '|' || coalesce(s.tercero_nombre, '') || '|' || (select count(*) from redes.dano_fotos f where f.dano_id = d.id) || '|' || d.respuesta_s || '|' || d.total_s || '|' || d.usuarios_sin_servicio || '|' || d.largo_afectado_m || '|' || array_to_string(d.marcas, ',') || '|' || d.inicio_origen
                       from redes.v_dano d left join redes.dano_datos_sensibles s on s.dano_id = d.id where d.codigo = '${cod}'`).split("|");
  ok(`${tag} guardado ${cod}: sobre ${V85[0]}, atendido, GPS, rotura parcial, terceros, riesgo alto, 2 fotos, 40 usuarios, 2,5 m, marca vía y hora de apertura`,
     fila[0] === V85[0] && fila[1] === "atendido" && fila[2] === "gps" && fila[3] === "parcial" && fila[4] === "terceros" && fila[5] === "alto" && fila[7] === "2" && fila[8] === "4500" && fila[9] === "10200"
     && fila[10] === "40" && fila[11] === "2.5" && fila[12] === "via" && fila[13] === "dispositivo", fila.join("|"));
  ok(`${tag} la placa quedó solo en dano_datos_sensibles`, fila[6] === `Placa ZT${ancho}` && !sqlq(`select detalle::text from public.geoportal_auditoria where referencia = '${cod}'`).includes("Placa"));
  ok(`${tag} las 2 fotos subieron a su URL firmada (JPEG, menos de 1,5 MB) y quedaron en Storage`, subidas.length === s0 + 2 && subidas.slice(-2).every((x) => x.mime === "image/jpeg" && x.bytes > 1000 && x.bytes < 1572864), JSON.stringify(subidas.slice(-2)));
  await p.screenshot({ path: join(CAP, `dano_guardado_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Ver la ficha de"); await esperarTexto(p, /Epicrisis del activo/);
  await esperarTexto(p, new RegExp(`${cod} · Fuga o tubería rota`));
  t = await p.evaluate(() => [...document.querySelectorAll(".red-seccion")].find((x) => /Epicrisis del activo/.test(x.innerText))?.innerText ?? "");
  ok(`${tag} la epicrisis del activo muestra el daño (hecho), con duración y sin la placa`, t.includes(`${cod} · Fuga o tubería rota · Rotura parcial · riesgo alto · causa de terceros · duración 2 h 50 min`) && /· Atendido ⏎ Daño ⏎|· Atendido\nDaño\n/.test(t) && !/Placa ZT/.test(t) && !/Todavía no hay daños/.test(t), t);
  await p.screenshot({ path: join(CAP, `epicrisis_con_dano_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== Operador: «no identificado» marcando el punto, en alcantarillado =====
  p = await abrir(ancho, "op", null);
  await clicTexto(p, ".dan-opcion", "Alcantarillado"); await p.waitForSelector(".dan-mini-mapa");
  await p.evaluate((lat, lon) => { const m = document.querySelector(".dan-mini-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: 13 }); }, Number(V85[1]), Number(V85[2]));
  await esperarTexto(p, /Acerque el mapa para ver la red/);
  ok(`${tag} bajo el zoom 15: «Acerque el mapa para ver la red»`, true);
  await p.evaluate((lat, lon) => { const m = document.querySelector(".dan-mini-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: 17 }); }, Number(V85[1]), Number(V85[2]));
  await esperarRed(p);
  const capas2 = await p.evaluate(() => [...new Set(document.querySelector(".dan-mini-mapa").__mapa.queryRenderedFeatures({ layers: ["tramos", "nodos", "tramos-punteados"] }).map((f) => f.properties.prefijo))].sort());
  ok(`${tag} alcantarillado: solo colectores y pozos en el minimapa`, capas2.every((x) => ["COL", "POZ", "VER"].includes(x)) && capas2.includes("COL"), capas2.join(","));
  await p.evaluate(() => [...document.querySelectorAll(".dan-check")].find((l) => /No identifico el activo/.test(l.textContent)).querySelector("input").click());
  await esperarTexto(p, /Toque el mapa donde está el daño/);
  await poner(p, "#dan-quees", "Cámara que no sale en el mapa");
  const centro = await p.evaluate(() => { const el = document.querySelector(".dan-mini-mapa"); el.scrollIntoView({ block: "center" }); const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await tocar(p, centro.x, centro.y, movil); await esperarTexto(p, /Punto marcado: /);
  await clicTexto(p, ".dan-opcion", "Rebose de alcantarillado"); await clicTexto(p, ".dan-opcion", "Bajo"); await clicTexto(p, ".dan-opcion", "Desconocida");
  await foto(p, "El daño");
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Daño guardado: DAN-\d{6}/, 30000);
  t = await texto(p);
  const cod2 = t.match(/DAN-\d{6}/)[0];
  const f2 = sqlq(`select coalesce(activo_codigo, 'nulo') || '|' || no_ident_que_es || '|' || ubicacion_origen || '|' || sistema || '|' || estado from redes.v_dano where codigo = '${cod2}'`).split("|");
  ok(`${tag} «no identificado» guardado (${cod2}): sin activo, con «qué es», punto del mapa, alcantarillado, reportado; avisa que va a la bandeja`,
     f2[0] === "nulo" && f2[1] === "Cámara que no sale en el mapa" && f2[2] === "mapa" && f2[3] === "alcantarillado" && f2[4] === "reportado" && /bandeja del supervisor/.test(t), f2.join("|"));
  await p.screenshot({ path: join(CAP, `no_identificado_guardado_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Reportar otro daño"); await esperarTexto(p, /Elija primero el sistema/);
  ok(`${tag} «Reportar otro» abre un formulario en blanco`, !(await texto(p)).includes("Punto marcado"));
  await p.close();
}
ok("cada daño guardado es uno (el reenvío no duplica) y todos los del navegador quedaron en la base", Number(sqlq("select count(*) from redes.danos")) === n0 + 4);
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
