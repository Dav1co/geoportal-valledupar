// Técnica · Fase 1 · Corte 3b · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada → Edges REALES geoportal-tecnica y geoportal-redes (Deno) → PostgREST mínimo en Node que llama a las RPC REALES de redes en el PostGIS local
//   (redes_local con el 1a, la carga completa, los Cortes 2, 3a y 3b), más un Storage simulado (firma de subida y de lectura, subida y descarga).
// La ficha como «perfil» a 390 px y en escritorio: minimapa estático con el activo resaltado, foto principal, galería (supervisor y administrador),
// «Editar ficha» del administrador (versión nueva, alias, placa, origen, de A a B con motivo), la foto principal subida, la búsqueda por placa y alias,
// y lo que ven el supervisor y el operador (sin editar; el operador sin galería ni foto).
//   node scripts/prueba_chrome_ficha_c3b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_ficha_c3b"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_ficha_c3b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", adm: "zt.admin@emdupar.gov.co" };
const PERFIL = { [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.adm]: "admin" };

if (Number(sqlq("select count(*) from redes.activo_vigente_mat")) < 35781) throw new Error("La base local no tiene la carga publicada");
if (sqlq("select to_regclass('redes.ficha_ediciones') is not null") !== "t") throw new Error("La base local no tiene el Corte 3b");
const n0 = Number(sqlq("select count(*) from redes.ficha_ediciones"));
const guardados = new Map();      // ruta → bytes subidos (para servir la lectura firmada)
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_ficha_c3b_"));
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
const rpcs = [], subidas = [], lecturas = [];
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
    if (u.pathname.startsWith("/storage/v1/object/sign/redes-evidencias/")) {       // lectura firmada (Corte 3b): firmar (POST) y descargar (GET)
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") { lecturas.push(ruta); return json(200, { signedURL: `/object/sign/redes-evidencias/${ruta}?token=l-${ruta.length}` }); }
      if (u.searchParams.get("token") !== `l-${ruta.length}`) return json(400, { error: "token" });
      const b = guardados.get(ruta); res.writeHead(200, { "Content-Type": b ? "image/jpeg" : "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(b ?? PNG_BLANCO);
    }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/redes-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/redes-evidencias/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT", "Access-Control-Allow-Headers": "content-type, x-upsert" }); return res.end(); }
      if (req.method === "PUT") {
        if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" });
        subidas.push({ ruta, bytes: cuerpo.length, mime: req.headers["content-type"] }); guardados.set(ruta, cuerpo);
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
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });      // si la prueba se cae a mitad, no deja la Edge escuchando
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

// ---------- 5. Recorridos del Corte 3b ----------
const PNG = join(dir, "foto_tanque.png"); writeFileSync(PNG, PNG_BLANCO);
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
// Un daño y una reparación con fotos sobre V85 (Cortes 2 y 3a), para que la ficha tenga galería y foto principal.
function hechosEnV85() {
  const p1 = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${p1.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const dano = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${p1.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]),
    ubicacion_origen: "gps", t_detectado: iso(-300), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: p1.fotos[0].ruta }] })})`)).codigo;
  const p2 = JSON.parse(sqlq(`select public.geoportal_redes_preparar_intervencion('${EMAILS.op}', 1, 0)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${p2.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const itv = JSON.parse(sqlq(`select public.geoportal_redes_crear_intervencion('${EMAILS.op}', '${p2.intervencion_id}', ${lit({ nace_de: "dano", dano, resuelve_dano: true, tipo: "reparacion", sistema: "acueducto",
    activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]), ubicacion_origen: "gps", t_inicio: iso(-180), t_fin: iso(-120), descripcion: "Cambio del empaque de la válvula", ejecutor: "emdupar",
    fuentes: [{ aportante: "emdupar" }], archivos: [{ n: 1, clase: "despues", ruta: p2.fotos[0].ruta }] })})`)).codigo;
  return { dano, itv };
}
const { dano: DANO, itv: ITV } = hechosEnV85();
const minimosFicha = (p) => p.evaluate(() => Math.min(...[...document.querySelectorAll(".red-ficha .tec-boton, .red-ficha .tec-boton-sec, .red-volver, .red-minimapa")].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)));
const imagenCargada = (p, sel) => p.waitForFunction((sel) => { const i = document.querySelector(sel); return i && i.complete && i.naturalWidth > 0; }, { timeout: 15000 }, sel).then(() => true, () => false);
async function abrirFichaPorBusqueda(p, texto) {
  await clicTexto(p, "button", "Ficha de activos"); await p.waitForSelector("#red-codigo");
  await poner(p, "#red-codigo", texto); await clicTexto(p, "button", "Abrir la ficha");
}
const estatico = (p) => p.waitForFunction((c) => { const m = document.querySelector(".red-minimapa-mapa")?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["sel-nodo"] }).some((f) => f.properties.codigo === c); },
  { timeout: 30000 }, V85[0]).then(() => true, () => false);

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  // ===== A. Administrador: el perfil completo y la edición =====
  let p = await abrir(ancho, "adm", null);
  await abrirFichaPorBusqueda(p, "V85"); await esperarTexto(p, /Datos del activo/);
  ok(`${tag} buscar «V85» (código de la capa) abre la ficha de ${V85[0]}`, (await texto(p)).includes(V85[0]));
  ok(`${tag} minimapa estático arriba, con ${V85[0]} resaltado en su red (sin interacción)`, await estatico(p) && await p.evaluate(() => !document.querySelector(".red-minimapa-mapa").__mapa.dragPan.isEnabled()));
  await esperarTexto(p, /Galería/);
  // en la primera vuelta la principal es la «después» de la reparación; en la segunda ya es la de perfil que se subió en la primera
  ok(`${tag} foto principal: ${ancho === 390 ? `la «después» de ${ITV}` : "la de perfil subida antes (gana a la de la intervención)"}, con su URL firmada`, await imagenCargada(p, ".red-foto-principal img")
     && (ancho === 390 ? new RegExp(`Intervención · ${ITV} · después`) : /Foto de perfil/).test(await texto(p)));
  let t = await texto(p);
  ok(`${tag} el administrador ve «Editar ficha» y «Cambiar foto principal»`, /Editar ficha/.test(t) && /Cambiar foto principal/.test(t));
  await clicTexto(p, "button", "Ver las fotos"); await p.waitForSelector(".red-gal-foto img");
  ok(`${tag} galería: la foto del daño ${DANO} y la de la intervención, cargadas`, await imagenCargada(p, ".red-gal-foto:nth-child(2) img") && (await p.$$(".red-gal-foto")).length >= 2
     && new RegExp(`Daño · ${DANO}`).test(await texto(p)) && /vencen al minuto/.test(await texto(p)));
  await clicTexto(p, ".red-gal-foto button", ""); await p.waitForSelector(".red-visor img");
  ok(`${tag} tocar una foto la abre en grande y «Cerrar» vuelve`, await imagenCargada(p, ".red-visor img"));
  await clicTexto(p, ".red-visor button", "Cerrar");
  ok(`${tag} la ficha (portada, galería) no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimosFicha(p)) >= 44, String(await minimosFicha(p)));
  await p.screenshot({ path: join(CAP, `ficha_perfil_${ancho}.png`), fullPage: true });
  // editar
  await clicTexto(p, "button", "Editar ficha"); await esperarTexto(p, /Editar la ficha/);
  const d0 = await p.evaluate(() => document.querySelector("#fe-diametro_mm")?.value ?? "");
  await poner(p, "#fe-alias", `Válvula de la glorieta ${ancho}`); await poner(p, "#fe-placa", `INV-ZT-${ancho}`);
  await poner(p, "#fe-diametro_mm", String(100 + ancho % 7)); await poner(p, "#fe-observaciones", "Revisada en campo");
  t = await texto(p);
  ok(`${tag} la vista previa dice qué cambia, de A a B`, new RegExp(`Diámetro: de «${d0 || "sin dato"}» a «${100 + ancho % 7}»`).test(t) && new RegExp(`Alias del activo \\(nombre propio\\): de «[^»]*» a «Válvula de la glorieta ${ancho}»`).test(t), t.match(/Se cambiará[\s\S]{0,400}/)?.[0]);
  await clicTexto(p, "button", "Guardar cambios"); await esperarTexto(p, /Escriba el motivo del cambio/);
  ok(`${tag} sin motivo no guarda`, Number(sqlq("select count(*) from redes.ficha_ediciones")) === n0 + (ancho === 390 ? 0 : 2));
  await poner(p, "#fe-motivo", "Revisión de la válvula en campo");
  await clicTexto(p, "button", "Guardar cambios"); await esperarTexto(p, /Ficha guardada: versión \d+\./);
  await esperarTexto(p, new RegExp(`Válvula de la glorieta ${ancho}`)); t = await texto(p);
  const fv = sqlq(`select v.version || '|' || coalesce(v.carga_id::text, 'ficha') || '|' || v.diametro_mm || '|' || i.alias || '|' || i.placa from redes.v_activo_vigente v join redes.v_activo_identificadores i on i.activo_id = v.activo_id where v.codigo = '${V85[0]}'`).split("|");
  ok(`${tag} guardado: versión nueva hecha en la ficha, con el diámetro, el alias y la placa; la cabecera los muestra`, fv[1] === "ficha" && fv[2] === String(100 + ancho % 7) && fv[3] === `Válvula de la glorieta ${ancho}`
     && fv[4] === `INV-ZT-${ancho}` && new RegExp(`Placa: INV-ZT-${ancho}`).test(t), fv.join("|"));
  await esperarTexto(p, /Cambio de la ficha/);
  t = await p.evaluate(() => [...document.querySelectorAll(".red-seccion")].find((x) => /Epicrisis del activo/.test(x.innerText))?.innerText ?? "");
  ok(`${tag} el muro trae el cambio de la ficha («de A a B» y el motivo) junto al daño y la intervención`, new RegExp(`Diámetro \\(mm\\): de «[^»]+» a «${100 + ancho % 7}»`).test(t) && /Revisión de la válvula en campo/.test(t)
     && t.includes(ITV) && t.includes(DANO), t);
  // foto principal
  await clicTexto(p, "button", "Cambiar foto principal"); await p.waitForSelector("#fp-archivo");
  await (await p.$("#fp-archivo")).uploadFile(PNG); await p.waitForSelector(".red-foto-vista");
  await poner(p, "#fp-motivo", "Foto de la válvula en la visita");
  const s0 = subidas.length;
  await clicTexto(p, "button", "Guardar foto"); await esperarTexto(p, /Foto principal guardada\./);
  await esperarTexto(p, /Foto de perfil/);
  ok(`${tag} la foto subida (PNG convertido a JPEG, menos de 1,5 MB) queda como principal`, subidas.length === s0 + 1 && subidas.at(-1).mime === "image/jpeg" && subidas.at(-1).ruta.startsWith("activos/")
     && subidas.at(-1).bytes < 1572864 && await imagenCargada(p, ".red-foto-principal img"), JSON.stringify(subidas.at(-1)));
  await p.screenshot({ path: join(CAP, `ficha_editada_${ancho}.png`), fullPage: true });
  await p.close();
  // búsqueda por placa y por alias
  p = await abrir(ancho, "adm", null);
  await abrirFichaPorBusqueda(p, `inv-zt-${ancho}`); await esperarTexto(p, /Datos del activo/);
  ok(`${tag} buscar la placa (en minúsculas) abre la ficha de ${V85[0]}`, (await texto(p)).includes(V85[0]));
  await p.close();
  p = await abrir(ancho, "adm", null);
  await abrirFichaPorBusqueda(p, "glorieta"); await esperarTexto(p, new RegExp(`${V85[0]} · Válvula de la glorieta ${ancho}`));
  ok(`${tag} buscar por el alias lista la válvula con su alias y su placa`, new RegExp(`placa INV-ZT-${ancho}`).test(await texto(p)));
  await p.close();

  // ===== B. Supervisor de distribución (Corte 4a, §26.2): edita todo menos el origen =====
  p = await abrir(ancho, "sup", null);
  await abrirFichaPorBusqueda(p, V85[0]); await esperarTexto(p, /Galería/);
  t = await texto(p);
  ok(`${tag} el supervisor de distribución ve la foto, la galería y «Editar ficha»`, await imagenCargada(p, ".red-foto-principal img") && /Ver las fotos \(\d+\)/.test(t) && /Editar ficha/.test(t) && /Cambiar foto principal/.test(t));
  await clicTexto(p, "button", "Editar ficha"); await esperarTexto(p, /Editar la ficha/);
  ok(`${tag} el editor del supervisor de distribución no trae el origen (solo el administrador lo corrige)`, !/Origen \(solo lo corrige el administrador\)/.test(await texto(p)) && !(await p.$("#fe-origen")));
  await p.close();

  // ===== C. Operador: desde el minimapa del daño =====
  p = await abrir(ancho, "op", [Number(V85[1]), Number(V85[2])]);
  await clicTexto(p, ".dan-opcion", "Acueducto"); await esperarTexto(p, /Se preseleccionó el activo más cercano/);
  await clicTexto(p, ".dan-elegido button", "Ver ficha"); await esperarTexto(p, /Datos del activo/);
  await esperarTexto(p, /Cambio de la ficha/);
  t = await texto(p);
  ok(`${tag} el operador ve el minimapa estático, el alias y el muro con el cambio de la ficha`, await estatico(p) && new RegExp(`Válvula de la glorieta ${ancho}`).test(t) && /Revisión de la válvula en campo/.test(t));
  ok(`${tag} el operador ve la foto principal y la galería (§26.1), sin los botones de edición`, await imagenCargada(p, ".red-foto-principal img") && /Galería/.test(t) && !/Editar ficha/.test(t));
  ok(`${tag} la ficha del operador no desborda`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `ficha_operador_${ancho}.png`), fullPage: true });
  await p.close();
}
ok("ediciones guardadas: 2 por ancho (los datos y la foto)", Number(sqlq("select count(*) from redes.ficha_ediciones")) === n0 + 4);
ok("la galería se leyó con URL firmadas de lectura y quedó auditada", lecturas.length > 0 && Number(sqlq("select count(*) from public.geoportal_auditoria where accion = 'redes_galeria'")) >= 2);
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
