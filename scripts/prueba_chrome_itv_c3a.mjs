// Técnica · Fase 1 · Corte 3a · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada → Edges REALES geoportal-tecnica y geoportal-redes (Deno) → PostgREST mínimo en Node que llama a las RPC REALES de redes en el PostGIS local
//   (redes_local con el 1a, la carga completa de los shapefiles, el Corte 2 y el 3a), más un Storage simulado (firma y subida que escriben en storage.objects local).
// «Registrar intervención» a 390 px y en escritorio: reparación que nace de un daño abierto (el más cercano preseleccionado, daños abiertos del activo, también
// intervenidos propuestos, materiales, contratista, quién aporta, fotos), el daño queda atendido y la epicrisis lo muestra; inversión en un tramo nuevo dibujado
// en el minimapa con un PDF; el supervisor sin fotos («sin evidencia fotográfica») y con valores; la bandeja de no identificados con «Asociar»; los recursos por
// completar; el daño sin fotos del supervisor con «Registrar la reparación»; y «Registrar intervención» desde la ficha.
//   node scripts/prueba_chrome_itv_c3a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
//   node scripts/prueba_chrome_itv_c3a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_itv_c3a"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_itv_c3a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co" };
const PERFIL = { [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor" };

if (Number(sqlq("select count(*) from redes.activo_vigente_mat")) < 35781) throw new Error("La base local no tiene la carga publicada");
if (sqlq("select to_regclass('redes.intervenciones') is not null") !== "t") throw new Error("La base local no tiene el Corte 3a");
const n0 = Number(sqlq("select count(*) from redes.intervenciones"));
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_itv_c3a_"));
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

// ---------- 5. Recorridos del Corte 3a ----------
const PDF = join(dir, "orden_de_trabajo.pdf");
writeFileSync(PDF, Buffer.from("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"));
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
/** Un daño abierto en V85, reportado por el operador con el formulario del Corte 2 (para que la intervención lo atienda). */
function danoEnV85() {
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const d = { clase: "dano", tipo: "fuga", sistema: "acueducto", activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]), ubicacion_origen: "gps", t_detectado: iso(-240),
    tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] };
  return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit(d)})`)).codigo;
}
const local = (min) => { const d = new Date(Date.now() + min * 60000); const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 16); };
const marcar = (p, sel) => p.evaluate((sel) => { const l = [...document.querySelectorAll(".dan-check")].find((x) => new RegExp(sel).test(x.textContent)); l.querySelector("input").click(); return true; }, sel);
const centroMapa = (p, dx = 0, dy = 0) => p.evaluate((dx, dy) => { const el = document.querySelector(".dan-mini-mapa"); el.scrollIntoView({ block: "center" }); const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2 + dx, y: r.top + r.height / 2 + dy }; }, dx, dy);
async function abrirItv(p) {
  await clicTexto(p, "button.tec-tarjeta-modo", "Registrar intervención"); await esperarTexto(p, /1\. De dónde nace y tipo/);
}

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`, movil = ancho < 500;
  // ===== A. Operador: reparación que nace de un daño abierto de V85 =====
  const danoA = danoEnV85();
  let p = await abrir(ancho, "op", [Number(V85[1]), Number(V85[2])]);
  let t = await texto(p);
  ok(`${tag} el operador no ve «Registrar sin evidencia fotográfica» en el daño`, !/Registrar sin evidencia fotográfica/.test(t));
  await abrirItv(p); t = await texto(p);
  ok(`${tag} el chip «Registrar intervención» abre el formulario (sin «Próximamente»), con las 7 secciones de la maqueta`,
     ["1. De dónde nace y tipo", "2. Activo", "3. Fecha y hora", "4. Qué se hizo", "5. Quién la ejecuta", "6. De dónde salen los recursos", "7. Fotos y soportes"].every((x) => t.includes(x)) && !/Próximamente/.test(t));
  const prep0 = rpcs.filter((r) => r.fn === "geoportal_redes_preparar_intervencion").length;
  await clicTexto(p, "button", "Guardar intervención"); await esperarTexto(p, /Falta completar/);
  t = await texto(p);
  ok(`${tag} guardar vacío: lista de lo que falta, sin llamar a la base`, /Elija el tipo de intervención/.test(t) && /Elija el sistema/.test(t) && /Describa qué se hizo/.test(t)
     && /Tome al menos una foto de la intervención/.test(t) && /Escriba el inicio y el fin/.test(t) && rpcs.filter((r) => r.fn === "geoportal_redes_preparar_intervencion").length === prep0);
  await clicTexto(p, ".dan-opcion", "Daño o falla"); t = await texto(p);
  ok(`${tag} «Daño o falla» deja solo correctivo, reparación y reposición, y pide primero el activo (desde el 4a, la lista va después del mapa)`, /se elige después del mapa/.test(t) && /Reparación/.test(t) && /Reposición/.test(t)
     && /Mantenimiento correctivo/.test(t) && !/Mantenimiento preventivo/.test(t) && !/Inversión/.test(t));
  await clicTexto(p, ".dan-opcion", "Acueducto"); await esperarTexto(p, /Se preseleccionó el activo más cercano/);
  await esperarTexto(p, new RegExp(danoA));
  t = await texto(p);
  ok(`${tag} con GPS sobre V85: queda ${V85[0]} y salen los daños abiertos del activo, con ${danoA} como «mismo activo»`, t.includes(V85[0]) && new RegExp(`${danoA}\\s*· Fuga o tubería rota en ${V85[0]}[\\s\\S]{0,80}mismo activo`).test(t), t.match(/Daño o falla que se atiende[\s\S]{0,300}/)?.[0]);
  await clicTexto(p, ".itv-dano", danoA);
  ok(`${tag} elegir el daño lo marca`, await p.evaluate((c) => [...document.querySelectorAll(".itv-dano")].some((b) => b.textContent.startsWith(c) && b.getAttribute("aria-checked") === "true"), danoA));
  ok(`${tag} sin marcar «Con esta queda resuelto el daño», avisa que el daño sigue en atención`, /Sin marcarla, el daño sigue en atención/.test(await texto(p)));
  await marcar(p, "Con esta queda resuelto el daño");
  ok(`${tag} al marcar «Con esta queda resuelto el daño», avisa que quedará atendido`, /Al guardar, el daño queda atendido/.test(await texto(p)));
  await clicTexto(p, ".dan-opcion", "Reparación");
  await esperarRed(p);
  await p.waitForFunction(() => document.querySelectorAll(".itv-propuesto").length > 0, { timeout: 10000 }).catch(() => {});
  const prop = await p.evaluate(() => document.querySelector(".itv-propuesto")?.textContent ?? "");
  ok(`${tag} el minimapa del Corte 2 dibuja la red y se proponen los cercanos como «también intervenidos»`, /^＋ [A-Z]{3}-\d{6}/.test(prop), prop);
  await clicTexto(p, ".itv-propuesto", "＋"); await p.waitForSelector(".itv-chip");
  const tambienCod = await p.evaluate(() => document.querySelector(".itv-chip").firstChild.textContent);
  ok(`${tag} agregar un propuesto lo deja como chip (${tambienCod})`, /^[A-Z]{3}-\d{6}$/.test(tambienCod));
  await poner(p, "#itv-ini", local(-125)); await clicTexto(p, ".itv-fin button", "Ahora");
  await esperarTexto(p, /Duración: 2 h 0[45] min/);
  ok(`${tag} el inicio viene del celular y el fin con «Ahora»: la duración se calcula sola`, true);
  await poner(p, "#itv-desc", `Prueba de Chrome ${ancho}: cambio del empaque de la válvula`);
  await clicTexto(p, "button", "Agregar material");
  await poner(p, '[aria-label="Material 1"]', "Empaque de 4 pulgadas"); await poner(p, '[aria-label="Cantidad 1"]', "2"); await elegirSelect(p, '[aria-label="Unidad 1"]', "und");
  await clicTexto(p, ".dan-opcion", "Contratista"); await poner(p, "#itv-ctrn", `Obras ZT ${ancho}`); await poner(p, "#itv-orden", "OT-77");
  t = await texto(p);
  ok(`${tag} recursos del operario: solo marca quién aporta (sin valor, porcentaje ni soporte, D-8)`, /Marque quién aporta\. El valor, el porcentaje y el soporte los pone el supervisor/.test(t)
     && (await p.$$('[aria-label^="Valor de"]')).length === 0);
  await marcar(p, "Alcaldía de Valledupar");
  ok(`${tag} sin términos tarifarios en la pantalla del operador`, !/tarifa|subsidio|contribuci|estrato/i.test(await texto(p)));
  await foto(p, "Antes"); await foto(p, "Después");
  ok(`${tag} cámara: 2 fotos (antes y después) en miniatura`, /1\. Antes.*2\. Después/.test(await p.evaluate(() => [...document.querySelectorAll(".dan-foto figcaption")].map((f) => f.textContent).join("|"))));
  ok(`${tag} la lista de lo que falta desaparece sola al completar`, !/Falta completar/.test(await texto(p)));
  ok(`${tag} el formulario lleno no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimos(p)) >= 44, String(await minimos(p)));
  await p.screenshot({ path: join(CAP, `itv_reparacion_llena_${ancho}.png`), fullPage: true });
  const s0 = subidas.length;
  await clicTexto(p, "button", "Guardar intervención"); await esperarTexto(p, /Intervención guardada: ITV-\d{6}/, 30000);
  t = await texto(p);
  const itvA = t.match(/ITV-\d{6}/)[0];
  ok(`${tag} guardada ${itvA}: el daño ${danoA} quedó atendido y avisa que el supervisor completa los recursos`, new RegExp(`El daño ${danoA} quedó atendido`).test(t) && /El supervisor completará el valor/.test(t));
  const fa = sqlq(`select i.activo_codigo || '|' || i.dano_codigo || '|' || i.tipo_codigo || '|' || i.estado || '|' || i.recursos || '|' || i.fotos || '|' || i.tambien || '|' || i.ejecutor || '|' || i.contratista || '|' || i.contrato_orden
     || '|' || array_to_string(i.aportantes, ',') || '|' || (select count(*) from redes.intervencion_materiales m where m.intervencion_id = i.id) || '|' || i.inicio_origen || '|' || (d.estado) || '|' || round(i.duracion_s / 60.0)
     from redes.v_intervencion i join redes.v_dano d on d.id = i.dano_id where i.codigo = '${itvA}'`).split("|");
  ok(`${tag} en la base: sobre ${V85[0]}, atiende ${danoA} (atendido), reparación, cerrada, recursos por completar, 2 fotos, 1 también intervenido, contratista, EMDUPAR y alcaldía, 1 material, ~125 min`,
     fa[0] === V85[0] && fa[1] === danoA && fa[2] === "reparacion" && fa[3] === "cerrada" && fa[4] === "por_completar" && fa[5] === "2" && fa[6] === "1" && fa[7] === "contratista" && fa[8] === `Obras ZT ${ancho}`
     && fa[9] === "OT-77" && fa[10] === "EMDUPAR,Alcaldía de Valledupar" && fa[11] === "1" && fa[12] === "dispositivo" && fa[13] === "atendido" && Math.abs(Number(fa[14]) - 125) <= 2, fa.join("|"));
  ok(`${tag} las 2 fotos subieron a su URL firmada (JPEG) bajo intervenciones/`, subidas.length === s0 + 2 && subidas.slice(-2).every((x) => x.mime === "image/jpeg" && x.ruta.startsWith("intervenciones/") && x.bytes > 1000), JSON.stringify(subidas.slice(-2)));
  await p.screenshot({ path: join(CAP, `itv_guardada_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Ver la ficha de"); await esperarTexto(p, /Epicrisis del activo/);
  await esperarTexto(p, new RegExp(`${itvA} · Reparación · atiende ${danoA} \\(lo resuelve\\)`));
  t = await p.evaluate(() => [...document.querySelectorAll(".red-seccion")].find((x) => /Epicrisis del activo/.test(x.innerText))?.innerText ?? "");
  ok(`${tag} la epicrisis de ${V85[0]} muestra la intervención (cerrada) y el daño atendido`, new RegExp(`${itvA} · Reparación · atiende ${danoA} \\(lo resuelve\\) · contratista Obras ZT ${ancho} · duración 2 h 0[45] min · 1 activo\\(s\\) más · 2 foto\\(s\\)`).test(t)
     && /Cerrada/.test(t) && /Intervención/.test(t) && new RegExp(`${danoA} · Fuga[^\\n]*`).test(t), t);
  await p.screenshot({ path: join(CAP, `itv_epicrisis_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== B. Operador: inversión en un tramo nuevo, con un PDF =====
  p = await abrir(ancho, "op", [Number(V85[1]), Number(V85[2])]);
  await abrirItv(p);
  await clicTexto(p, ".dan-opcion", "Inversión"); await esperarTexto(p, /¿Qué tipo de inversión\?/);
  await clicTexto(p, ".dan-opcion", "Activo nuevo"); await clicTexto(p, ".dan-opcion", "Acueducto");
  await esperarTexto(p, /Tipo del activo nuevo/);
  await elegirSelect(p, "#itv-ntipo", "RED"); await elegirSelect(p, "#itv-nmat", "PVC"); await poner(p, "#itv-ndiam", "76"); await poner(p, "#itv-nnom", `Extensión ${ancho}`);
  await esperarTexto(p, /Toque el inicio del tramo nuevo/);
  ok(`${tag} inversión, activo nuevo: pide el tipo, el material y el diámetro, y el mapa pide el inicio del tramo`, true);
  await esperarRed(p);
  let c1 = await centroMapa(p, -60, -30); await tocar(p, c1.x, c1.y, movil); await esperarTexto(p, /Ahora toque el fin del tramo nuevo/);
  c1 = await centroMapa(p, 60, 40); await tocar(p, c1.x, c1.y, movil); await esperarTexto(p, /Tramo marcado/);
  const dib = await p.evaluate(() => document.querySelector(".dan-mini-mapa").__mapa.getSource("dibujo")._data?.features?.length ?? JSON.stringify(document.querySelector(".dan-mini-mapa").__mapa.getStyle().sources.dibujo.data.features.length));
  ok(`${tag} tocar inicio y fin dibuja el tramo nuevo en el minimapa (2 puntos y la línea)`, Number(dib) === 3 && /Puntos marcados: 2 de 2/.test(await texto(p)), String(dib));
  await p.screenshot({ path: join(CAP, `itv_tramo_nuevo_mapa_${ancho}.png`), fullPage: false });
  await poner(p, "#itv-ini", local(-300)); await poner(p, "#itv-fin", local(-30));
  await poner(p, "#itv-desc", "Extensión de red nueva de prueba (Chrome)");
  await foto(p, "Después");
  const h = await p.$("#itv-doc"); await h.uploadFile(PDF); await esperarTexto(p, /📄 orden_de_trabajo\.pdf/);
  ok(`${tag} adjuntar un PDF lo lista con su nombre y tamaño`, true);
  const s1 = subidas.length;
  await clicTexto(p, "button", "Guardar intervención"); await esperarTexto(p, /Intervención guardada: ITV-\d{6}/, 30000);
  t = await texto(p);
  const itvB = t.match(/ITV-\d{6}/)[0], nuevo = (t.match(/activo (RED-\d{6})/) || [])[1];
  ok(`${tag} guardada ${itvB}: crea el tramo ${nuevo} «nuevo, queda por verificar»`, !!nuevo && /\(nuevo, queda por verificar\)/.test(t), t.slice(0, 400));
  const fb = sqlq(`select v.por_verificar || '|' || v.material_codigo || '|' || v.diametro_mm || '|' || (v.longitud_m > 5) || '|' || o.origen || '|' || coalesce(o.aportante_codigo, '') || '|' || (select count(*) from redes.activo_vigente_mat m where m.codigo = v.codigo)
     from redes.v_activo_vigente v join redes.v_activo_origen_vigente o on o.activo_id = v.activo_id where v.codigo = '${nuevo}'`).split("|");
  ok(`${tag} en la base: ${nuevo} por verificar, PVC de 76 mm, con largo, origen EMDUPAR y en la tabla vigente`, fb[0] === "true" && fb[1] === "PVC" && fb[2] === "76" && fb[3] === "true" && fb[4] === "emdupar" && fb[6] === "1", fb.join("|"));
  ok(`${tag} el PDF subió como application/pdf (y la foto como JPEG)`, subidas.length === s1 + 2 && subidas.slice(-2).some((x) => x.mime === "application/pdf" && x.ruta.endsWith(".pdf")) && subidas.slice(-2).some((x) => x.mime === "image/jpeg"),
     JSON.stringify(subidas.slice(-2)));
  await p.close();

  // ===== C. Supervisor: preventivo sin fotos, no identificado, con valores =====
  p = await abrir(ancho, "sup", null);
  t = await texto(p);
  ok(`${tag} desde el Corte 4a (§25.8) el supervisor tampoco ve «Registrar sin evidencia fotográfica»`, !/Registrar sin evidencia fotográfica/.test(t));
  await abrirItv(p);
  await clicTexto(p, ".dan-opcion", "Mantenimiento preventivo"); await clicTexto(p, ".dan-opcion", "Alcantarillado"); await p.waitForSelector(".dan-mini-mapa");
  await p.evaluate((lat, lon) => { const m = document.querySelector(".dan-mini-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: 17 }); }, Number(V85[1]), Number(V85[2]));
  await esperarRed(p);
  await marcar(p, "No puedo identificar el activo"); await esperarTexto(p, /Toque el mapa donde está la intervención/);
  await poner(p, "#itv-quees", `Cámara sin código ${ancho}`);
  c1 = await centroMapa(p); await tocar(p, c1.x, c1.y, movil); await esperarTexto(p, /Punto marcado: /);
  await poner(p, "#itv-ini", local(-90)); await clicTexto(p, ".itv-fin button", "Ahora");
  await poner(p, "#itv-desc", "Limpieza preventiva reportada por llamada");
  t = await texto(p);
  ok(`${tag} recursos del supervisor: valor, porcentaje y soporte por fuente`, /Cada una con su valor o porcentaje y su soporte/.test(t) && (await p.$$('[aria-label="Valor de EMDUPAR"]')).length === 1);
  await poner(p, '[aria-label="Valor de EMDUPAR"]', "1.250.000"); await poner(p, '[aria-label="Soporte de EMDUPAR"]', "Presupuesto de mantenimiento");
  ok(`${tag} la intervención tampoco ofrece «sin evidencia fotográfica» al supervisor (§25.8)`, !/sin evidencia fotográfica/.test(await texto(p)));
  await foto(p, "Después");
  await clicTexto(p, "button", "Guardar intervención"); await esperarTexto(p, /Intervención guardada: ITV-\d{6}/, 30000);
  t = await texto(p);
  const itvC = t.match(/ITV-\d{6}/)[0];
  const fc = sqlq(`select coalesce(activo_codigo, 'nulo') || '|' || no_ident_que_es || '|' || sin_evidencia || '|' || coalesce(sin_evidencia_motivo, '') || '|' || recursos || '|' || ubicacion_origen
     || '|' || (select valor || '/' || soporte from redes.v_intervencion_fuentes f where f.intervencion_id = v.id) from redes.v_intervencion v where codigo = '${itvC}'`).split("|");
  ok(`${tag} guardada ${itvC} con su foto, no identificada (va a la bandeja), con el valor de 1.250.000 y su soporte`, !/sin evidencia fotográfica/.test(t) && /bandeja del supervisor/.test(t)
     && fc[0] === "nulo" && fc[1] === `Cámara sin código ${ancho}` && fc[2] === "false" && fc[4] === "completos" && fc[5] === "mapa" && fc[6] === "1250000.00/Presupuesto de mantenimiento", fc.join("|"));
  await p.close();

  // ===== D. Supervisor: bandeja de no identificados y recursos por completar =====
  p = await abrir(ancho, "sup", null);
  await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Pestañas|No identificados/);      // Corte 4a: la bandeja vive en el Dashboard distribución
  await esperarTexto(p, new RegExp(itvC));
  t = await p.evaluate((c) => [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c))?.innerText ?? "", itvC);
  ok(`${tag} la bandeja trae ${itvC} con «qué es» y los activos más cercanos propuestos`, t.includes(`«Cámara sin código ${ancho}»`) && /Activos propuestos/.test(t) && /(COL|POZ)-\d{6}[\s\S]{0,40}a [\d.]+ m/.test(t), t);
  const propuesto = await p.evaluate((c) => [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c)).querySelector(".itv-prop strong").textContent, itvC);
  await p.evaluate((c) => { const s = [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)); s.scrollIntoView({ block: "center" }); }, itvC);
  const sel = `#mot-${itvC}`;
  await poner(p, sel, "Es la cámara de la esquina, según la visita");
  await p.evaluate((c) => [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)).querySelector(".itv-guardar").click(), itvC);
  await esperarTexto(p, new RegExp(`${itvC} quedó asociado a ${propuesto}`));
  ok(`${tag} «Asociar» deja ${itvC} con ${propuesto} (evento con motivo; la intervención no se reescribe)`, sqlq(`select activo_codigo from redes.v_intervencion where codigo = '${itvC}'`) === propuesto
     && sqlq(`select activo_id is null from redes.intervenciones where codigo = '${itvC}'`) === "t");
  ok(`${tag} la bandeja no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimos(p)) >= 44, String(await minimos(p)));
  await p.screenshot({ path: join(CAP, `bandeja_no_identificados_${ancho}.png`), fullPage: true });
  await clicTexto(p, "[role=tab]", "Intervenciones"); await esperarTexto(p, new RegExp(`${itvA} · Reparación`));
  await p.evaluate((c) => { const s = [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)); s.scrollIntoView({ block: "center" }); }, itvA);
  await poner(p, `[aria-label="Porcentaje de EMDUPAR en ${itvA}"]`, "40");
  await poner(p, `[aria-label="Valor de Alcaldía de Valledupar en ${itvA}"]`, "3.400.000"); await poner(p, `[aria-label="Soporte de Alcaldía de Valledupar en ${itvA}"]`, "Convenio 12 de 2026");
  await p.evaluate((c) => [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)).querySelector(".itv-guardar").click(), itvA);
  await esperarTexto(p, new RegExp(`Recursos de ${itvA} guardados \\(versión 2\\)`));
  ok(`${tag} el supervisor completa los recursos de ${itvA}: versión 2, completos (EMDUPAR 40 % y la alcaldía $ 3.400.000 con su convenio)`,
     sqlq(`select recursos || '|' || (select string_agg(coalesce(valor::text, '') || '/' || coalesce(porcentaje::text, '') || '/' || coalesce(soporte, ''), ',' order by n) from redes.v_intervencion_fuentes f where f.intervencion_id = v.id) from redes.v_intervencion v where codigo = '${itvA}'`)
     === "completos|/40.00/,3400000.00//Convenio 12 de 2026");
  await p.screenshot({ path: join(CAP, `recursos_por_completar_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== E. Supervisor: daño sin fotos y «Registrar la reparación»; «Registrar intervención» desde la ficha =====
  p = await abrir(ancho, "sup", [Number(V85[1]), Number(V85[2])]);
  await clicTexto(p, ".dan-opcion", "Acueducto"); await esperarTexto(p, /Se preseleccionó el activo más cercano/);
  await clicTexto(p, ".dan-opcion", "Falla"); await clicTexto(p, ".dan-opcion", "Válvula que no opera"); await clicTexto(p, ".dan-opcion", "Medio"); await clicTexto(p, ".dan-opcion", "Desconocida");
  await foto(p, "El daño");
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Falla guardado: DAN-\d{6}/, 30000);
  t = await texto(p);
  const danoE = t.match(/DAN-\d{6}/)[0];
  ok(`${tag} el supervisor guarda la falla ${danoE} con su foto (sin «sin evidencia»)`, !/sin evidencia fotográfica/.test(t)
     && sqlq(`select count(*) from redes.dano_fotos f join redes.danos d on d.id = f.dano_id where d.codigo = '${danoE}'`) === "1");
  await clicTexto(p, "button", "Registrar la reparación"); await esperarTexto(p, /1\. De dónde nace y tipo/);
  await esperarTexto(p, new RegExp(`${danoE}\\s*· Válvula que no opera`));
  const est = await p.evaluate((c) => ({
    nace: [...document.querySelectorAll(".dan-opcion")].find((b) => b.textContent === "Daño o falla")?.getAttribute("aria-pressed"),
    dano: [...document.querySelectorAll(".itv-dano")].find((b) => b.textContent.startsWith(c))?.getAttribute("aria-checked"),
    tipo: [...document.querySelectorAll(".dan-opcion")].find((b) => b.textContent === "Reparación")?.getAttribute("aria-pressed"),
    activo: document.querySelector(".itv-elegido strong")?.textContent }), danoE);
  ok(`${tag} «Registrar la reparación» abre la intervención que nace de ${danoE}, ya elegido, como reparación y sobre ${V85[0]}`, est.nace === "true" && est.dano === "true" && est.tipo === "true" && est.activo === V85[0], JSON.stringify(est));
  await p.screenshot({ path: join(CAP, `reparacion_desde_dano_${ancho}.png`), fullPage: true });
  await p.close();
  p = await abrir(ancho, "sup", null);
  await clicTexto(p, "button", "Ficha de activos"); await p.waitForSelector("input");
  await p.focus("#red-codigo"); await p.keyboard.type("V85"); await p.keyboard.press("Enter"); await esperarTexto(p, /Datos del activo/);
  await clicTexto(p, "button", "Registrar intervención"); await esperarTexto(p, /1\. De dónde nace y tipo/);
  await p.waitForFunction((c) => document.querySelector(".itv-elegido strong")?.textContent === c, { timeout: 10000 }, V85[0]).catch(() => {});
  ok(`${tag} «Registrar intervención» desde la ficha de ${V85[0]} abre el formulario con el activo y el sistema elegidos`, (await p.evaluate(() => document.querySelector(".itv-elegido strong")?.textContent)) === V85[0]
     && (await p.evaluate(() => [...document.querySelectorAll(".dan-opcion")].find((b) => b.textContent === "Acueducto")?.getAttribute("aria-pressed"))) === "true");
  await p.close();
}
ok("cada intervención guardada es una (el reenvío no duplica): 3 por ancho", Number(sqlq("select count(*) from redes.intervenciones")) === n0 + 6);
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
