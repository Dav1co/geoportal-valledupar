// Prueba en Chrome REAL del Corte 5d de Técnica fase 1 (la línea 116), a 390 px (táctil) y 1280 px:
// · El supervisor de distribución carga la 116 en «Cargue de capas» (Excel y luego CSV): el NOMBRE se descarta en la página (no llega en ningún lote), la revisión
//   dice nuevos, con cambio de estado e iguales y cómo se ubicaron, y el cambio de estado queda como evento con fecha.
// · El geovisor del supervisor muestra la capa «Línea 116»: color por servicio y estado, los repetidos del mismo contrato, causal y día en un punto, sin nombre,
//   dirección ni barrio; el operador no la ve.
// · Punto 8: «Reportar anomalía» y «Revisiones generales» se asignan desde Personal del Dashboard distribución.
// Las Edges corren DE VERDAD en Deno; las RPC van a la base de Code B (producción hoy + el 5d) con el rol de la API (service_role) y los topes de producción
// (30 s y 8 s). Archivos sintéticos. Puertos y base propios de Code B.
// Uso: node scripts/prueba_chrome_linea116_c5d.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c5d"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_linea116_c5d.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_5dt> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55991, P_EDGE = 55992;      // puertos de Code B (los de Code A son 5498x)
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
// cada ancho arranca de una copia limpia de la plantilla (9a + carga real del Plan Maestro), en el clúster de Code B
const rehacer = () => execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
rehacer();

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c5d_"));
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
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    // Corte 6c: como las ve producción. Cada RPC entra con el rol de la API (service_role) y los topes de Supabase: statement_timeout 30 s y lock_timeout 8 s.
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
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
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
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 300))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
const texto = (p) => p.evaluate(() => document.body.innerText);
// ---- Corte 11: el inicio de Técnica va por modos (Planta, Redes y Supervisión). Ayudantes de Code A: buscan en cada modo.
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
    if (Date.now() > fin) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)} · errores: ${errores.join(" | ").slice(0, 800)}`); }
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
const abrirFormulario = async (p, nombre) => { await esperarTexto(p, new RegExp(nombre)); if (!(await clicTexto(p, "button.tec-tarjeta-modo", nombre))) throw new Error("no está la tarjeta " + nombre); await p.waitForSelector(".tec-volver-barra"); };
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const visibilidad = (p, capa) => p.evaluate((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility"), capa);
const dibujados = (p, capa) => p.evaluate((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) ? m.queryRenderedFeatures({ layers: [c] }).length : -1; }, capa);
const esperarDibujo = (p, capa, ms = 60000) => p.waitForFunction((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) && m.queryRenderedFeatures({ layers: [c] }).length > 0; }, { timeout: ms }, capa).then(() => true).catch(() => false);
const marcada = (p, capa) => p.evaluate((c) => document.querySelector(`.geo-panel [data-capa=${c}] input`)?.checked ?? null, capa);
async function abrir(ancho, rol, hash, gps) {
  const p = await nav.newPage();
  if (gps) await p.setGeolocation({ latitude: gps[1], longitude: gps[0], accuracy: 6 }); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
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


// ---------- 5. Ayudantes (los del 9a-bis) ----------
const tarjeta = (p, c) => p.evaluate((c) => [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((s) => s.innerText.includes(c)).pop()?.innerText ?? "", c);
const enTarjeta = async (p, c, sel, t) => { if (!(await enTarjeta0(p, c, sel, t))) throw new Error(`no hay «${t}» en la tarjeta de «${c}»: ${(await tarjeta(p, c)).slice(0, 500)}`); return true; };
const enTarjeta0 = (p, c, sel, t) => p.evaluate((c, sel, t) => { const s = [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((x) => x.innerText.includes(c)).pop(); if (!s) return false;
  s.scrollIntoView({ block: "center" }); const b = [...s.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.click(); return true; }, c, sel, t);
const pestana = async (p, n) => { if (!(await clicTexto(p, "[role=tab]", n))) throw new Error(`no está la pestaña ${n}`); };
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
async function panelCapas(p) { await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel"); }
async function cerrarPanel(p) { await clicTexto(p, ".geo-panel button", "✕"); await p.waitForFunction(() => !document.querySelector(".geo-panel")); }
async function encender(p, capa, si = true) {
  await panelCapas(p);
  await p.evaluate((c, si) => { const i = document.querySelector(`.geo-panel [data-capa=${c}] input`); i.scrollIntoView({ block: "center" }); if (i.checked !== si) i.click(); }, capa, si);
  await cerrarPanel(p);
}
const tarjetaGeo = (p) => p.evaluate(() => { const t = document.querySelector(".geo-tarjeta"); return t ? { capa: t.dataset.capa, txt: t.innerText, puntos: Number(t.querySelector(".geo-grafica svg")?.dataset.puntos ?? 0),
  botones: [...t.querySelectorAll("button")].map((b) => b.textContent.trim()), dentro: t.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 } : null; });
async function esperarTarjeta(p, capa, re) {
  await p.waitForFunction((capa, s) => { const t = document.querySelector(".geo-tarjeta"); return t && t.dataset.capa === capa && new RegExp(s).test(t.innerText); }, { timeout: 30000 }, capa, re.source).catch(() => {});
  return tarjetaGeo(p);
}
async function alDashboard(ancho, rol) {
  const p = await abrir(ancho, rol, null);
  await esperarTexto(p, /Dashboard distribución/); await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Dashboard distribución[\s\S]*No identificados/);
  return p;
}
// antes de tocar el mapa se cierra la tarjeta abierta: a 390 px tapa el centro del mapa, y el toque caería sobre ella
async function tocar(p, lon, lat, zoom) {
  await p.evaluate(() => document.querySelector(".geo-tarjeta .geo-cerrar")?.click()); await p.waitForFunction(() => !document.querySelector(".geo-tarjeta"));
  await tocarEn(p, lon, lat, zoom);
}
const coord = (q) => sqlq(q).split("|").map(Number);
const tiempos = [];

// ---------- 6. Los archivos de prueba de la línea 116 (sintéticos; con NOMBRE, que no debe salir de la página) ----------
const NOMBRE_FALSO = "ZT5D NOMBRE QUE NO SE ENVIA";
const R0 = 990150000;
const PRED = sqlq(`select string_agg(x.cod_usuario || '|' || ST_X(x.geom) || '|' || ST_Y(x.geom), ';' order by x.cod_usuario) from (
    select c.cod_usuario, c.geom from public.catastro_valledupar c join redes.activo_vigente_mat m on m.prefijo = 'SEC' and m.clase = 'subsector' and not m.retirado and ST_Intersects(m.geom, c.geom)
     where c.cod_usuario ~ '^[1-9][0-9]{2,7}$' and c.cod_usuario <> '99999999' and (select count(*) from public.catastro_valledupar c2 where c2.cod_usuario = c.cod_usuario) = 1
     order by c.cod_usuario limit 2) x`).split(";").map((s) => s.split("|"));
const [C1, C2] = PRED;
const ARCH = mkdtempSync(join(tmpdir(), "arch_116_"));
const XLSX = join(ARCH, "reportes_116_prueba.xlsx"), CSV = join(ARCH, "reportes_116_prueba_2.csv");
execFileSync("python3", ["-I", "-c", `
import openpyxl, datetime, sys, zoneinfo
hoy = datetime.datetime.now(zoneinfo.ZoneInfo("America/Bogota")).replace(tzinfo=None).replace(hour=0, minute=5, second=0, microsecond=0)
w = openpyxl.Workbook(); h = w.active; h.title = "Hoja1"
h.append(["REPORTE", "ESTADO", "FECHA_REGISTRO", "CONTRATO", "NOMBRE", "DIRECCION", "BARRIO", "COMUNA", "DESC_CAUSAL", "SERVICIO"])
r0, c1, c2, nom = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
h.append([r0 + 1, "Registrado", hoy, c1, nom, "ZT5D DIR UNO", "ZT5D BARRIO", "COMUNA 5", "FUGA EN ACOMETIDA", "Acueducto"])
h.append([r0 + 2, "Registrado", hoy + datetime.timedelta(minutes=2), c1, nom, "ZT5D DIR UNO", "ZT5D BARRIO", "COMUNA 5", "FUGA EN ACOMETIDA", "Acueducto"])
h.append([r0 + 3, "Atendido", hoy + datetime.timedelta(minutes=3), c2, nom, "ZT5D DIR DOS", "ZT5D BARRIO", "COMUNA 5", "REBOSE DE ALCANTARILLA", "Alcantarillado"])
h.append([r0 + 4, "Registrado", hoy + datetime.timedelta(minutes=4), 99515099, nom, "ZT5D SIN CATASTRO", "ZT5D BARRIO QUE NO EXISTE", "COMUNA 5", "SIN AGUA", "Acueducto"])
for c in h["C"][1:]: c.number_format = "dd/mm/yyyy hh:mm:ss"
w.save(sys.argv[1])
`, XLSX, String(R0), C1[0], C2[0], NOMBRE_FALSO]);
const HOYB = sqlq("select to_char((now() at time zone 'America/Bogota')::date, 'DD/MM/YYYY')");
writeFileSync(CSV, `REPORTE;ESTADO;FECHA_REGISTRO;CONTRATO;NOMBRE;DIRECCION;BARRIO;COMUNA;DESC_CAUSAL;SERVICIO\n${R0 + 1};Atendido;${HOYB} 00:05;${C1[0]};${NOMBRE_FALSO};ZT5D DIR UNO;ZT5D BARRIO;COMUNA 5;FUGA EN ACOMETIDA;Acueducto\n${R0 + 5};Registrado;${HOYB} 00:09;${C2[0]};${NOMBRE_FALSO};ZT5D DIR DOS;ZT5D BARRIO;COMUNA 5;SIN AGUA;Incidentes Externos\n`);
const sinNombre = () => !rpcs.some((r) => JSON.stringify(r.a).includes(NOMBRE_FALSO) || (r.fn === "geoportal_redes_carga_lote" && JSON.stringify(r.a).toLowerCase().includes('"nombre"')));
async function alCargue(p) { await pestana(p, "Cargue de capas"); await esperarTexto(p, /Reportes de la línea 116/); }
async function cargar116(p, archivo) {
  await p.evaluate(() => { const b = [...document.querySelectorAll("[data-testid=capa-linea_116] button")].find((x) => /^Cargar versión|^Seguir/.test(x.textContent.trim())); b.scrollIntoView({ block: "center" }); b.click(); });
  await p.waitForSelector("#cg116-archivo");
  await (await p.$("#cg116-archivo")).uploadFile(archivo); await p.waitForSelector("[data-testid=leida]");
}

const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const quiero = (s) => !process.env.SOLO || process.env.SOLO.includes(s);
for (const ancho of ANCHOS) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0;
  sqlq(`select public.geoportal_redes_personal_fijar('${EMAILS.dist}', '${EMAILS.op}', 'geovisor', 'si', 'Necesita ver la red en la calle')`);
  let p, t, tj;
  // ===== A. Cargue de capas: el supervisor de distribución carga la línea 116 (Excel) =====
  p = await alDashboard(ancho, "dist"); await alCargue(p);
  t = await p.evaluate(() => document.querySelector("[data-testid=capa-linea_116]")?.innerText ?? "");
  ok(`${tag} A1 la capa «Reportes de la línea 116» está en el Cargue (CSV o Excel; se reconoce por el número y se ubica por su contrato), sin cargar todavía`,
     /CSV, Excel/.test(t) && /se reconoce por el número de reporte y se ubica por su contrato/.test(t) && /Todavía no se ha cargado/.test(t), t);
  await cargar116(p, XLSX);
  t = await texto(p);
  ok(`${tag} A2 al elegir el Excel: 4 reportes y «No se envían: NOMBRE, DIRECCION, BARRIO» (se descartan en el equipo)`, /4\s*reportes/.test(t) && /No se envían: NOMBRE, DIRECCION, BARRIO/.test(t), t.slice(0, 600));
  await p.screenshot({ path: join(CAP, `cargue_archivo_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Subir y revisar"); await p.waitForSelector("[data-testid=resumen]");
  t = await p.evaluate(() => document.querySelector("[data-testid=resumen]").innerText);
  ok(`${tag} A3 la revisión: 4 nuevos, 0 cambian de estado, 3 en el predio de su contrato y 1 sin ubicar, y «Lista para publicar»`,
     /Nuevos\s*4/.test(t) && /Cambian de estado\s*0/.test(t) && /3 en el predio de su contrato · 1 sin ubicar/.test(t) && /Lista para publicar/.test(t), t);
  ok(`${tag} A4 ni el nombre, ni la dirección ni el barrio salieron de la página (ningún lote los lleva), y el resumen tampoco los trae`,
     sinNombre() && !rpcs.some((r) => /ZT5D DIR|ZT5D BARRIO|"direccion"|"barrio"/i.test(JSON.stringify(r.a))) && rpcs.some((r) => r.fn === "geoportal_redes_carga_lote") && !/ZT5D DIR|ZT5D BARRIO/.test(t));
  await p.screenshot({ path: join(CAP, `cargue_revisar_${ancho}.png`), fullPage: true });
  await clicTexto(p, "button", "Siguiente"); await p.waitForSelector("#cg116-nota");
  await clicTexto(p, "button", "Publicar"); await esperarTexto(p, /Escriba la nota de la carga/);
  await poner(p, "#cg116-nota", `Reportes 116 de prueba del día (${ancho})`); await clicTexto(p, "button", "Publicar");
  await p.waitForSelector("[data-testid=publicada]"); t = await texto(p);
  ok(`${tag} A5 publicar exige la nota y publica: «4 nuevos · 0 con cambio de estado»; en la base, 4 reportes sin nombre`,
     /4 nuevos · 0 con cambio de estado/.test(t) && sqlq(`select count(*) from redes.l116_reportes where reporte between ${R0} and ${R0 + 99}`) === "4", t.slice(0, 300));
  await clicTexto(p, "button", "Volver a las capas"); await esperarTexto(p, /Reportes de la línea 116/);
  await cargar116(p, CSV);
  await clicTexto(p, "button", "Subir y revisar"); await p.waitForSelector("[data-testid=resumen]");
  t = await p.evaluate(() => document.querySelector("[data-testid=resumen]").innerText);
  ok(`${tag} A6 la segunda carga (CSV, fecha DD/MM/AAAA) reconoce el reporte por su número: 1 nuevo y 1 que cambia de estado`, /Nuevos\s*1/.test(t) && /Cambian de estado\s*1/.test(t), t);
  await clicTexto(p, "button", "Siguiente"); await poner(p, "#cg116-nota", `Segunda carga de prueba (${ancho})`); await clicTexto(p, "button", "Publicar");
  await p.waitForSelector("[data-testid=publicada]");
  ok(`${tag} A7 el cambio de estado queda como evento con fecha (registrado → atendido) y nada se borra`,
     sqlq(`select string_agg(e.tipo || ':' || e.estado, ',' order by e.id) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = ${R0 + 1}`) === "alta:registrado,estado:atendido"
     && sinNombre());
  ok(`${tag} A8 el asistente no se desborda y sus botones miden 40 px o más`, (await sinDesborde(p)) && (await minimo(p, ".cg-asistente button")) >= 40);
  await p.close();

  // ===== B. Geovisor del supervisor: la capa «Línea 116» =====
  p = await abrir(ancho, "dist"); await alGeovisor(p);
  await panelCapas(p); t = await p.evaluate(() => document.querySelector(".geo-panel").innerText);
  ok(`${tag} B1 la capa «Línea 116 (reportes)» está en la lista, apagada al abrir`, /Línea 116 \(reportes\)/.test(t) && (await marcada(p, "pqr_116")) === false, t.slice(0, 300));
  await cerrarPanel(p);
  await encender(p, "acu_tramos", false); await encender(p, "acu_nodos", false); await encender(p, "sectores", false);
  await encender(p, "pqr_116");
  await p.evaluate((lon, lat) => document.querySelector(".geo-mapa").__mapa.jumpTo({ center: [lon, lat], zoom: 17 }), Number(C1[1]), Number(C1[2]));
  const hay = await esperarDibujo(p, "g-pqr_116");
  const ley = await p.evaluate(() => document.querySelector("[data-testid=leyenda-116]")?.innerText ?? "");
  ok(`${tag} B2 la capa se dibuja (hoy) y su leyenda dice los colores por servicio, lleno/hueco por estado, y que 1 reporte del periodo no tiene ubicación (su contrato no está en el catastro)`,
     hay && /Acueducto/.test(ley) && /Alcantarillado/.test(ley) && /Lleno: registrado · hueco: atendido/.test(ley) && /1 del periodo sin ubicar/.test(ley), ley);
  await p.screenshot({ path: join(CAP, `geovisor_116_${ancho}.png`) });
  await tocar(p, Number(C1[1]), Number(C1[2]), 18);
  tj = await esperarTarjeta(p, "pqr_116", /línea 116/);
  ok(`${tag} B3 tocar el punto abre una sola tarjeta para los 2 reportes del mismo contrato, causal y día: estado, números, contrato, ubicación y sector`,
     tj && /2 reportes de la línea 116/.test(tj.txt) && /1 de 2 registrados/.test(tj.txt) && tj.txt.includes(String(R0 + 1)) && tj.txt.includes(String(R0 + 2))
     && tj.txt.includes(C1[0]) && /Por el contrato \(punto del predio\)/.test(tj.txt) && /Sector hidráulico/.test(tj.txt) && tj.dentro, JSON.stringify(tj));
  ok(`${tag} B4 la tarjeta no trae nombre, dirección ni barrio`, tj && !tj.txt.includes(NOMBRE_FALSO) && !/ZT5D DIR|ZT5D BARRIO/.test(tj.txt));
  await p.screenshot({ path: join(CAP, `tarjeta_116_${ancho}.png`) });
  ok(`${tag} B5 el geovisor con la capa no se desborda`, await sinDesborde(p));
  await p.close();
  p = await abrir(ancho, "op"); await alGeovisor(p); await panelCapas(p); t = await p.evaluate(() => document.querySelector(".geo-panel").innerText);
  ok(`${tag} B6 el operador en solo lectura no ve la capa de la línea 116`, !/Línea 116/.test(t), t.slice(0, 300));
  await p.close();

  // ===== C. Punto 8: los formularios compartidos en Personal del Dashboard distribución =====
  p = await alDashboard(ancho, "dist"); await pestana(p, "Personal"); await esperarTexto(p, new RegExp(EMAILS.op2.replace(/\./g, "\\.")));
  await enTarjeta(p, EMAILS.op2, "button", "Editar ficha"); await p.waitForSelector("[data-formulario=anomalia_compartida]");
  t = await p.evaluate(() => document.querySelector(".gest-formularios")?.innerText ?? "");
  ok(`${tag} C1 el supervisor de distribución ve «Reportar anomalía» y «Revisiones generales» entre los formularios que asigna`, /Reportar anomalía/.test(t) && /Revisiones generales/.test(t), t);
  await p.evaluate(() => document.querySelector("[data-formulario=anomalia_compartida]").click());
  await p.evaluate(() => { const el = document.querySelector("[id^=mo-]"); const pr = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(pr, "value").set.call(el, "Reporta anomalías desde Técnica"); el.dispatchEvent(new Event("input", { bubbles: true })); });
  await clicTexto(p, "button", "Guardar ("); await esperarTexto(p, /Reportar anomalía/);
  await p.waitForFunction(() => !document.querySelector("[data-formulario=anomalia_compartida]"), { timeout: 15000 }).catch(() => {});
  ok(`${tag} C2 se lo asigna a un operador (queda el evento con su motivo)`,
     sqlq(`select count(*) from tecnica.personal_tecnico_eventos where persona = '${EMAILS.op2}' and formulario = 'anomalia_compartida' and tipo_evento = 'asignar_formulario' and autor = '${EMAILS.dist}'`) === "1");
  await p.screenshot({ path: join(CAP, `personal_${ancho}.png`), fullPage: true });
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
