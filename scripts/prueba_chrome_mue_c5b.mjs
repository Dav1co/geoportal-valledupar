// Prueba en Chrome REAL del Corte 5b de Técnica fase 1: minimapa de Muestreo sincronizado con la lista, «Guardar la ubicación de este punto» con el GPS
// y la pestaña «Puntos» del Dashboard PTAP (aprobar o rechazar). A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC del 5b (geoportal_tec_punto*, geoportal_tec_puntos_mapa) y las de redes van a la
//   base local REAL (PostGIS de Homebrew con la carga real, la primera carga MUE y el 5b); el resto de planta (formulario, registrar…) se simula como en el Corte 0b.
// · Antes de cada ancho, la base se rehace (base5b.sh con5b), así cada ancho empieza con los 27 puntos (3 verificados) y sin propuestas.
// Uso: node scripts/prueba_chrome_mue_c5b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base5b.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c5b"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL || !BASE) { console.error("Uso: node scripts/prueba_chrome_mue_c5b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base5b.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", sup2: "zt.super2@emdupar.gov.co" };
const PERFIL = { [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.sup2]: "supervisor" };
const rehacer = () => execFileSync("sh", [BASE, "con5b"], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c5b_"));
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
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head><body><div id="raiz" style="display:flex;flex-direction:column;min-height:100vh"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC del 5b y de redes van a la base local REAL ----------
const hoyB = () => new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const HOY = hoyB();
const horaMenos = (min) => new Date(Date.now() - 5 * 3_600_000 - min * 60_000).toISOString().slice(11, 16);
const MUES = sqlq("select string_agg(codigo || '|' || nombre || '|' || coalesce(zona, ''), ';' order by codigo) from tecnica.puntos where tipo = 'muestreo' and activo")
  .split(";").map((x, i) => { const [codigo, nombre, zona] = x.split("|"); return { codigo, nombre, tipo: "muestreo", planta: null, zona: zona || null, orden: i + 1 }; });
const v = (codigo, nombre, unidad, orden) => ({ codigo, nombre, unidad, categoria: "x", decimales: 2, orden, obligatoria: false, alcance: "por_punto", punto: null, tipo_punto: "muestreo", puntos: MUES.map((p) => p.codigo) });
const DEF_MUE = { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "Muestreo en los puntos de la red." }, fecha_hoy: HOY, hora_propuesta: horaMenos(15), dias_atras_max: 7,
  fecha_minima: new Date(Date.parse(HOY + "T12:00:00Z") - 7 * 86_400_000).toISOString().slice(0, 10), plantas: [], puntos: MUES, variables: [v("cloro_libre", "Cloro libre", "mg/L", 1), v("turbiedad", "Turbiedad", "UNT", 2)] };
const rpcs = [], desconocidas = [];
let sinSql5b = false;            // simula la base sin el SQL del 5b (Edge ya desplegada)
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    return { status: 200, cuerpo: fn === "geoportal_redes_mvt" ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "", con_campos: true }] } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_obtener_formulario": return a.p_formulario === "muestreo" ? DEF_MUE : { status: 400, cuerpo: { code: "22023", message: "Formulario no disponible", hint: "msg_usuario" } };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_registrar_medicion": return { lote_id: "00000000-0000-4000-8000-000000000001", formulario: a.p_formulario, fecha_muestra: a.p_fecha_muestra ?? HOY, hora_muestra: a.p_hora_muestra, guardados: a.p_valores.length, duplicado: false };
    case "geoportal_tec_catalogo_filtros": return { formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "" }], plantas: [], zonas: ["norte", "sur", "medio"], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
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
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, args: a });
      if (/^geoportal_tec_punto|^geoportal_tec_puntos_mapa$/.test(fn)) {
        if (sinSql5b) return json(404, { code: "PGRST202", message: `Could not find the function public.${fn}` });
        const r = rpcBase(fn, a); return json(r.status, r.cuerpo);
      }
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation"]);
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
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const tocar = async (p, x, y, movil) => { if (movil) await p.touchscreen.tap(x, y); else await p.mouse.click(x, y); };
const ubic = (c) => sqlq(`select u.lat || '|' || u.lon || '|' || u.exactitud || '|' || u.fuente || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = '${c}'`).split("|");
async function abrir(ancho, rol, gps) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", (m) => { if ((m.type() === "error" || m.type() === "warn") && !/status of 40[034]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(m.text())) errores.push(`${ancho} ${rol} consola: ${m.text()}`); });
  if (gps) await p.setGeolocation(gps);
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
/** Espera a que el minimapa (el primero, o el del selector) tenga puntos dibujados; devuelve cuántos. */
const esperarPuntos = async (p, sel = ".mue-mapa") => {
  await p.waitForFunction((sel) => { const m = document.querySelector(sel)?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["puntos"] }).length > 0; }, { timeout: 30000 }, sel);
  return p.evaluate((sel) => document.querySelector(sel).__mapa.queryRenderedFeatures({ layers: ["puntos"] }).length, sel);
};
/** Pixel en pantalla de un punto del minimapa. */
const pixelDe = (p, lat, lon) => p.evaluate((lat, lon) => { const el = document.querySelector(".mue-mapa"); el.scrollIntoView({ block: "center" }); const m = el.__mapa; const r = el.getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lat, lon);
const seleccionado = (p) => p.evaluate(() => document.querySelector("select[id^='tec-sel-punto']")?.value ?? null);
const filtroSel = (p) => p.evaluate(() => JSON.stringify(document.querySelector(".mue-mapa").__mapa.getFilter("sel")));

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`; const movil = ancho < 500;
  rehacer(); rpcs.length = 0;           // cada ancho empieza con la base y las RPC anotadas en limpio
  const [l05, o05] = ubic("MUE-05"); const [l11, o11] = ubic("MUE-11");
  const gpsCerca = { latitude: Number(l05) + 0.0003, longitude: Number(o05) - 0.0002, accuracy: 45 };

  // ===== A. el operador en Muestreo =====
  let p = await abrir(ancho, "op", gpsCerca);
  await esperarTexto(p, /Muestreo/); await clicTexto(p, "button.tec-tarjeta-modo", "Muestreo"); await esperarTexto(p, /Puntos de muestreo/);
  const n = await esperarPuntos(p);
  ok(`${tag} A1 el minimapa de Muestreo dibuja los 27 puntos (sin pedir el GPS al abrir)`, n === 27 && !rpcs.some((r) => r.fn === "geoportal_tec_punto_ubicacion_proponer"), `dibujados ${n}`);
  ok(`${tag} A2 con la leyenda (verificada, aproximada y en revisión) y sin el aviso de puntos sin ubicación`, /Ubicación verificada/.test(await texto(p)) && /Aproximada \(centro del barrio\)/.test(await texto(p)) && !(await p.$("[data-testid=sin-ubicacion]")));
  await p.screenshot({ path: join(CAP, `operador_mapa_${ancho}.png`), fullPage: true });
  let px = await pixelDe(p, Number(l11), Number(o11)); await tocar(p, px.x, px.y, movil);
  await p.waitForFunction(() => document.querySelector("select[id^='tec-sel-punto']")?.value === "MUE-11", { timeout: 5000 }).catch(() => {});
  ok(`${tag} A3 tocar MUE-11 en el mapa lo elige en la lista y dice «verificada», sin el botón de guardar ubicación`, (await seleccionado(p)) === "MUE-11" && /Ubicación verificada\./.test(await texto(p))
     && !/Guardar la ubicación de este punto/.test(await texto(p)), `${await seleccionado(p)}`);
  ok(`${tag} A4 y aparecen los campos del punto elegido`, /Cloro libre · Los Cocos/.test(await texto(p)));
  await p.select("select[id^='tec-sel-punto']", "MUE-05");
  await p.waitForFunction(() => /MUE-05/.test(JSON.stringify(document.querySelector(".mue-mapa").__mapa.getFilter("sel"))), { timeout: 5000 }).catch(() => {});
  ok(`${tag} A5 elegir MUE-05 en la lista lo resalta en el mapa; dice «aproximada» y ofrece guardar la ubicación`, /MUE-05/.test(await filtroSel(p)) && /Ubicación aproximada/.test(await texto(p))
     && /Guardar la ubicación de este punto/.test(await texto(p)), await filtroSel(p));
  await clicTexto(p, "button", "Ver dónde estoy"); await esperarTexto(p, /El punto más cercano es/);
  ok(`${tag} A6 «Ver dónde estoy» marca el GPS y propone el punto más cercano (OGB), sin cambiar lo elegido`, /El punto más cercano es OGB/.test(await texto(p)) && (await seleccionado(p)) === "MUE-05", (await texto(p)).match(/El punto más cercano[^\n]*/)?.[0]);
  await clicTexto(p, "button", "Guardar la ubicación de este punto"); await esperarTexto(p, /Precisión del GPS/);
  ok(`${tag} A7 con 45 m de precisión no deja guardar y dice cuánto se necesita`, /se necesita 30 m o menos/.test(await texto(p))
     && await p.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Guardar esta ubicación")?.disabled === true));
  await p.screenshot({ path: join(CAP, `operador_gps_impreciso_${ancho}.png`), fullPage: true });
  await p.setGeolocation({ ...gpsCerca, accuracy: 6 });
  await p.waitForFunction(() => /Precisión del GPS: 6 m ✔/.test(document.body.innerText), { timeout: 10000 }).catch(() => {});
  ok(`${tag} A8 con 6 m de precisión sí deja guardar`, /Precisión del GPS: 6 m ✔/.test(await texto(p)), (await texto(p)).match(/Precisión del GPS[^\n]*/)?.[0]);
  await clicTexto(p, "button", "Guardar esta ubicación"); await esperarTexto(p, /Va a enviar la ubicación del GPS/);
  ok(`${tag} A9 la confirmación dice la precisión y la distancia a la ubicación aproximada (~40 m), y que nada cambia hasta que el supervisor apruebe`,
     /precisión 6 m\), a (3\d|4\d) m de la ubicación aproximada/.test(await texto(p)) && /hasta que el supervisor la apruebe/.test(await texto(p)), (await texto(p)).match(/Va a enviar[^\n]*/)?.[0]);
  await p.screenshot({ path: join(CAP, `operador_confirmar_ubicacion_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Confirmar y enviar"); await esperarTexto(p, /Ubicación enviada/);
  const prop = sqlq("select x.autor || '|' || x.estado || '|' || x.precision_m from tecnica.v_punto_propuestas x join tecnica.puntos t on t.id = x.punto_id where t.codigo = 'MUE-05'");
  ok(`${tag} A10 queda pendiente en la base, a nombre del operador, con su precisión; la vigente sigue aproximada`, prop === `${EMAILS.op}|pendiente|6.0` && ubic("MUE-05")[2] === "aproximada", prop);
  const rp = [...rpcs].reverse().find((r) => r.fn === "geoportal_tec_punto_ubicacion_proponer");
  ok(`${tag} A11 la Edge pasó solo el correo del token, el punto, lat, lon, precisión e IP`, rp && rp.args.p_solicitante === EMAILS.op && rp.args.p_punto === "MUE-05" && Object.keys(rp.args).sort().join() === "p_ip,p_lat,p_lon,p_precision_m,p_punto,p_solicitante", JSON.stringify(rp?.args));
  await clicTexto(p, "button", "Cerrar");
  await p.waitForFunction(() => /Usted ya envió la ubicación de este punto/.test(document.body.innerText), { timeout: 8000 }).catch(() => {});
  ok(`${tag} A12 el punto queda «en revisión» (texto y borde morado en el mapa) y ya no ofrece guardar`, /Usted ya envió la ubicación de este punto: está en revisión/.test(await texto(p))
     && !/Guardar la ubicación de este punto/.test(await texto(p))
     && await p.evaluate(() => document.querySelector(".mue-mapa").__mapa.querySourceFeatures("puntos").some((f) => f.properties.codigo === "MUE-05" && f.properties.en_revision)));
  ok(`${tag} A13 sin desborde a lo ancho; los botones del minimapa miden 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".mue button")) >= 44, `${await minimo(p, ".mue button")}`);
  // el registro de Muestreo sigue igual con el punto elegido en el mapa
  await poner(p, "input[id^='tec-c-cloro_libre@MUE-05']", "1,2");
  await clicTexto(p, "button", "Guardar registro"); await esperarTexto(p, /Va a guardar 1 registro/); await clicTexto(p, "button", "Confirmar y guardar"); await esperarTexto(p, /Registro guardado/);
  const rg = [...rpcs].reverse().find((r) => r.fn === "geoportal_tec_registrar_medicion");
  ok(`${tag} A14 el registro de Muestreo sale igual que antes (punto MUE-05, con la fecha de la muestra)`, rg && rg.args.p_punto === "MUE-05" && rg.args.p_formulario === "muestreo" && rg.args.p_fecha_muestra === HOY
     && rg.args.p_valores?.[0]?.valor === 1.2, JSON.stringify(rg?.args));
  await p.screenshot({ path: join(CAP, `operador_en_revision_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== B. el supervisor en el Dashboard PTAP · Puntos =====
  // una ubicación que toma el mismo supervisor (para ver que no puede revisarla)
  sqlq(`select public.geoportal_tec_punto_ubicacion_proponer('${EMAILS.sup}', 'MUE-06', ${Number(ubic("MUE-06")[0]) + 0.006}, ${ubic("MUE-06")[1]}, 5)`);
  p = await abrir(ancho, "sup");
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Secciones|Registros/);
  await clicTexto(p, ".tdash-tab", "Puntos"); await esperarTexto(p, /Ubicaciones por revisar \(2\)/);
  const t5 = await p.evaluate(() => document.querySelector("[data-testid=pendiente-MUE-05]")?.innerText ?? "");
  ok(`${tag} B1 la pestaña «Puntos» lista 2 por revisar; MUE-05 dice quién la tomó, la precisión y la distancia a la aproximada`, /La tomó .*zt\.oper@emdupar\.gov\.co/.test(t5) && /precisión de 6 m/.test(t5) && /Queda a \d+ m de la ubicación de ahora \(aproximada/.test(t5), t5);
  const t6 = await p.evaluate(() => document.querySelector("[data-testid=pendiente-MUE-06]")?.innerText ?? "");
  ok(`${tag} B2 la que tomó él mismo (MUE-06) dice «Lejos» y no tiene Aprobar ni Rechazar`, /Lejos/.test(t6) && /la tomó usted/.test(t6) && !/Aprobar|Rechazar/.test(t6), t6);
  await p.waitForFunction(() => { const m = document.querySelector("[data-testid=pendiente-MUE-05] .mue-mapa")?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["propuesta"] }).length === 1 && m.queryRenderedFeatures({ layers: ["puntos"] }).length === 1; }, { timeout: 30000 }).catch(() => {});
  ok(`${tag} B3 su minimapa dibuja la ubicación de ahora y la propuesta`, await p.evaluate(() => { const m = document.querySelector("[data-testid=pendiente-MUE-05] .mue-mapa")?.__mapa; return !!m && m.queryRenderedFeatures({ layers: ["propuesta"] }).length === 1 && m.queryRenderedFeatures({ layers: ["puntos"] }).length === 1; }));
  ok(`${tag} B4 la tabla de puntos trae los 27 con su ubicación (3 verificadas)`, await p.evaluate(() => { const f = [...document.querySelectorAll("#pto-todos-tit ~ .pto-tabla-env tbody tr")]; return f.length === 27 && f.filter((x) => /Verificada/.test(x.innerText)).length === 3; }));
  await p.screenshot({ path: join(CAP, `supervisor_puntos_${ancho}.png`), fullPage: true });
  ok(`${tag} B5 sin desborde a lo ancho (la tabla se desplaza dentro de su caja)`, await sinDesborde(p));
  // rechazar sin motivo no se puede
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-05] button")].find((b) => b.textContent.trim() === "Rechazar").click());
  await p.waitForSelector("[data-testid=pendiente-MUE-05] textarea");
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-05] button")].find((b) => b.textContent.trim() === "Confirmar el rechazo").click());
  await esperarTexto(p, /Escriba el motivo del rechazo/);
  ok(`${tag} B6 rechazar sin motivo: lo pide y no llama al servidor`, !rpcs.some((r) => r.fn === "geoportal_tec_punto_ubicacion_revisar"));
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-05] button")].find((b) => b.textContent.trim() === "Volver").click());
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-05] button")].find((b) => b.textContent.trim() === "Aprobar").click());
  await p.waitForSelector("[data-testid=pendiente-MUE-05] textarea");
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-05] button")].find((b) => b.textContent.trim() === "Confirmar la aprobación").click());
  await esperarTexto(p, /Se aprobó la ubicación de MUE-05/);
  const u5 = ubic("MUE-05");
  ok(`${tag} B7 aprobada: MUE-05 queda verificada, del GPS del operador (autor: el operador) y la lista baja a 1`, u5[2] === "verificada" && u5[3] === "gps_operador" && u5[4] === EMAILS.op
     && /Ubicaciones por revisar \(1\)/.test(await texto(p)), u5.join("|"));
  ok(`${tag} B8 la tabla muestra MUE-05 «Verificada · GPS del operador» y la revisión en «Últimas revisiones»`, await p.evaluate(() => [...document.querySelectorAll("tbody tr")].some((x) => /MUE-05/.test(x.innerText) && /Verificada · GPS del operador/.test(x.innerText))
     && [...document.querySelectorAll("tbody tr")].some((x) => /MUE-05/.test(x.innerText) && /Aprobada/.test(x.innerText) && /zt\.super@/.test(x.innerText))));
  await p.screenshot({ path: join(CAP, `supervisor_aprobada_${ancho}.png`), fullPage: true });
  await p.close();
  // otro supervisor rechaza la de MUE-06 con motivo
  p = await abrir(ancho, "sup2");
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, ".tdash-tab", "Puntos"); await esperarTexto(p, /Ubicaciones por revisar \(1\)/);
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-06] button")].find((b) => b.textContent.trim() === "Rechazar").click());
  await p.waitForSelector("[data-testid=pendiente-MUE-06] textarea");
  await poner(p, "[data-testid=pendiente-MUE-06] textarea", "Queda a 600 m: es la casa de enfrente del parque");
  await p.evaluate(() => [...document.querySelectorAll("[data-testid=pendiente-MUE-06] button")].find((b) => b.textContent.trim() === "Confirmar el rechazo").click());
  await esperarTexto(p, /Se rechazó la ubicación propuesta de MUE-06/);
  ok(`${tag} B9 otro supervisor rechaza la de MUE-06 con motivo: queda «No hay ubicaciones por revisar» y la de MUE-06 sigue aproximada`, !!(await p.$("[data-testid=sin-pendientes]")) && ubic("MUE-06")[2] === "aproximada"
     && sqlq("select motivo from tecnica.punto_ubicacion_revisiones order by id desc limit 1") === "Queda a 600 m: es la casa de enfrente del parque");
  await p.close();

  // ===== C. el operador después de la aprobación, y la base sin el SQL del 5b =====
  p = await abrir(ancho, "op");
  await esperarTexto(p, /Muestreo/); await clicTexto(p, "button.tec-tarjeta-modo", "Muestreo"); await esperarTexto(p, /Puntos de muestreo/); await esperarPuntos(p);
  await p.select("select[id^='tec-sel-punto']", "MUE-05");
  await esperarTexto(p, /Ubicación verificada \(GPS del operador/);
  ok(`${tag} C1 MUE-05 sale verificada (GPS del operador, aprobada) y ya no ofrece guardar`, !/Guardar la ubicación de este punto/.test(await texto(p))
     && await p.evaluate(() => document.querySelector(".mue-mapa").__mapa.querySourceFeatures("puntos").some((f) => f.properties.codigo === "MUE-05" && f.properties.exactitud === "verificada")));
  await clicTexto(p, "button", "Ocultar el mapa");
  ok(`${tag} C2 «Ocultar el mapa» lo quita y la lista sigue`, !(await p.$(".mue-mapa")) && !!(await p.$("select[id^='tec-sel-punto']")));
  await p.close();
  sinSql5b = true;
  p = await abrir(ancho, "op");
  await esperarTexto(p, /Muestreo/); await clicTexto(p, "button.tec-tarjeta-modo", "Muestreo"); await esperarTexto(p, /Puntos de muestreo/);
  await esperarTexto(p, /No se pudo cargar el mapa de los puntos/);
  await p.select("select[id^='tec-sel-punto']", "MUE-07");
  ok(`${tag} C3 con la base sin el SQL del 5b: avisa que no cargó el mapa y la lista funciona como antes`, (await seleccionado(p)) === "MUE-07" && /Cloro libre · Don Carmelo/.test(await texto(p)));
  sinSql5b = false;
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
