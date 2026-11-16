// Prueba en Chrome REAL del arreglo de los dashboards (§34 de la bitácora): el Dashboard PTAP sin franjas (el selector PTAP | distribución dentro del encabezado)
// y el Dashboard distribución con el mismo estilo que el PTAP, en verde oscuro. A 390 px (táctil) y 1280 px. La página imita la de la app: .app de alto 100 % con
// la barra de arriba (54 px), como App.tsx. Infraestructura copiada de la prueba del Corte 5c (Edges reales en Deno y base local real).
// (Encabezado original:) Prueba en Chrome REAL del Corte 5c de Técnica fase 1: la pantalla del Cargue de capas (Dashboard distribución) y, en el Dashboard PTAP › Puntos,
// el administrador que aprueba lo suyo (§32.1) y «Corregir la ubicación» de un punto verificado (§32.2). A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC de redes y las de puntos (geoportal_tec_punto*) van a la base local REAL
//   (PostGIS de Homebrew con la carga real, la primera carga MUE y el 5c); el resto de planta (formularios, registros) se simula como en el 5b.
// · Los archivos son REALES, armados con ogr2ogr desde los shapefiles de origen (pozos en 9377, acueducto en 4326, GeoPackage con 3 capas, KML, Excel y CSV).
// · Antes de cada ancho, la base se rehace (base_chrome.sh).
// Uso: node scripts/prueba_chrome_cargue_c5c.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> <archivos> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_dashboards"));
if (!PSQL) { console.error("Uso: node scripts/prueba_chrome_dashboards.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54975, P_EDGE = 54976;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", sup2: "zt.super2@emdupar.gov.co", op: "zt.oper@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.sup2]: "supervisor", [EMAILS.op]: "operador" };

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c5c_"));
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
    createRoot(document.getElementById("raiz")).render(<><header className="barra" data-testid="barra"><strong style={{ color: "#fff" }}>Geoportal</strong></header><AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" /></>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><style>#raiz{height:100%}</style><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head><body><div id="raiz" class="app"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes y de puntos van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: fn === "geoportal_redes_mvt" ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "", con_campos: true }] } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_catalogo_filtros": return { formularios: [{ clave: "muestreo", nombre: "Muestreo", descripcion: "" }], plantas: [], zonas: ["norte", "sur", "medio"], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7,
      fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
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
      rpcs.push({ fn, bytes: cuerpo.length });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_puntos_mapa$|^geoportal_tec_aviso/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
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
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 700) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 400))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
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
async function abrir(ancho, rol) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", (m) => { if ((m.type() === "error" || m.type() === "warn") && !/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(m.text())) errores.push(`${ancho} ${rol} consola: ${m.text()}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
/** La geometría del dashboard en pantalla: los hijos de .app debajo de la barra, dónde empieza y termina el dashboard y si la página (no el dashboard) se desplaza. */
const geometria = (p) => p.evaluate(() => {
  const app = document.querySelector(".app"), barra = document.querySelector("[data-testid=barra]");
  const hijos = [...app.children].filter((e) => e !== barra);
  const d = document.querySelector(".tdash"), cab = d?.querySelector(".tdash-cab"), h1 = cab?.querySelector("h1");
  const r = (e) => { if (!e) return null; const b = e.getBoundingClientRect(); return { top: Math.round(b.top), bottom: Math.round(b.bottom), left: Math.round(b.left), right: Math.round(b.right) }; };
  return { hijos: hijos.map((e) => e.className), barraAbajo: r(barra).bottom, dash: r(d), cab: r(cab), h1: r(h1), alto: window.innerHeight, ancho: window.innerWidth,
           paginaSeDesplaza: document.scrollingElement.scrollHeight > window.innerHeight + 1, desbordeX: document.documentElement.scrollWidth > window.innerWidth + 1 };
});
/** Lleva el dashboard hasta el final y dice si lo último del contenido queda a la vista (sin franja que lo tape). */
const finalVisible = (p) => p.evaluate(async () => {
  const d = document.querySelector(".tdash"); d.scrollTop = d.scrollHeight; await new Promise((r) => setTimeout(r, 150));
  const cuerpo = d.querySelector(".tdash-cuerpo"); const ultimos = [...cuerpo.querySelectorAll("*")].filter((e) => e.offsetParent && e.getBoundingClientRect().height > 0);
  const u = ultimos.reduce((a, b) => (b.getBoundingClientRect().bottom > a.getBoundingClientRect().bottom ? b : a), cuerpo);
  const ub = u.getBoundingClientRect().bottom, db = d.getBoundingClientRect().bottom;
  const tapa = document.elementFromPoint(Math.min(window.innerWidth - 2, Math.max(2, u.getBoundingClientRect().left + 2)), Math.min(window.innerHeight - 2, Math.max(0, ub - 2)));
  return { ultimoAbajo: Math.round(ub), dashAbajo: Math.round(db), alto: window.innerHeight, dentro: d.contains(tapa) || u.contains(tapa) };
});
/** Estilos del encabezado y de lo común, para comparar los dos dashboards. */
const estilos = (p) => p.evaluate(() => {
  const cs = (sel, props) => { const e = document.querySelector(sel); if (!e) return null; const s = getComputedStyle(e); return Object.fromEntries(props.map((k) => [k, s[k]])); };
  const T = ["fontFamily", "fontSize", "fontWeight", "color", "lineHeight"], B = ["fontFamily", "fontSize", "fontWeight", "color", "backgroundColor", "borderRadius", "height", "paddingLeft", "borderTopWidth"];
  const tab = [...document.querySelectorAll(".tdash-tab")].find((e) => e.getAttribute("aria-current") !== "page" && !e.disabled);
  const tabSel = document.querySelector('.tdash-tab[aria-current="page"]');
  const sel = [...document.querySelectorAll(".tdash-sel")]; const selOn = sel.find((e) => e.getAttribute("aria-pressed") === "true"), selOff = sel.find((e) => e.getAttribute("aria-pressed") !== "true");
  const g = (e, props) => { if (!e) return null; const s = getComputedStyle(e); return Object.fromEntries(props.map((k) => [k, s[k]])); };
  return {
    fondoCab: getComputedStyle(document.querySelector(".tdash-cab")).backgroundColor,
    cab: cs(".tdash-cab", ["paddingTop", "paddingBottom"]), ancho: cs(".tdash-ancho", ["maxWidth", "paddingTop", "paddingLeft", "paddingRight"]),
    h1: cs(".tdash-cab h1", T), sesion: cs(".tdash-sesion", T), volver: cs(".tdash-cab .td-boton-claro", B),
    tab: g(tab, [...B, "borderBottomColor"]), tabSel: g(tabSel, [...B, "borderBottomColor"]), selOn: g(selOn, B), selOff: g(selOff, B),
    cuerpo: cs(".tdash-cuerpo", ["maxWidth", "paddingTop", "paddingLeft", "rowGap", "fontFamily"]), fondo: cs(".tdash", ["backgroundColor", "fontFamily", "color"]),
    selector: !!document.querySelector(".tdash-cab .tdash-selector"), volverTexto: document.querySelector(".tdash-cab .td-boton-claro")?.textContent.trim(),
  };
});

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  let p = await abrir(ancho, "adm");
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Sección|Registros/);
  await p.waitForFunction(() => !/Cargando el Dashboard/.test(document.body.innerText), { timeout: 30000 }).catch(() => {});
  let g = await geometria(p);
  await p.screenshot({ path: join(CAP, `ptap_${ancho}.png`) });
  ok(`${tag} P1 Dashboard PTAP: un solo bloque debajo de la barra (el selector va dentro del encabezado), sin franja vacía arriba`, g.hijos.length === 1 && /tdash/.test(g.hijos[0])
     && Math.abs(g.dash.top - g.barraAbajo) < 1 && Math.abs(g.cab.top - g.barraAbajo) < 1, JSON.stringify(g));
  ok(`${tag} P2 el encabezado azul se ve entero (el título dentro del encabezado y en pantalla)`, g.h1 && g.h1.top >= g.cab.top && g.h1.bottom <= g.cab.bottom && g.h1.top >= g.barraAbajo, JSON.stringify({ h1: g.h1, cab: g.cab }));
  ok(`${tag} P3 el dashboard llega hasta abajo de la pantalla (sin franja blanca) y la página no se desplaza por fuera`, Math.abs(g.dash.bottom - g.alto) < 1 && !g.paginaSeDesplaza && !g.desbordeX, JSON.stringify(g));
  await clicTexto(p, ".tdash-tab", "Personal técnico"); await esperarTexto(p, /Personal/); await new Promise((r) => setTimeout(r, 800));
  let f = await finalVisible(p);
  ok(`${tag} P4 al bajar hasta el final, lo último del contenido queda a la vista y nada lo tapa`, f.ultimoAbajo <= f.alto && f.dentro, JSON.stringify(f));
  const ePtap = await estilos(p);
  ok(`${tag} P5 el selector PTAP | distribución va en el encabezado, con el PTAP marcado`, ePtap.selector && ePtap.selOn && /PTAP/.test(await p.evaluate(() => document.querySelector('.tdash-sel[aria-pressed="true"]')?.textContent ?? "")));
  await p.evaluate(() => { document.querySelector(".tdash").scrollTop = 0; });
  await p.screenshot({ path: join(CAP, `ptap_personal_${ancho}.png`), fullPage: false });

  await clicTexto(p, ".tdash-sel", "Dashboard distribución"); await esperarTexto(p, /Cargue de capas/);
  await new Promise((r) => setTimeout(r, 800));
  g = await geometria(p);
  await p.screenshot({ path: join(CAP, `distribucion_${ancho}.png`) });
  ok(`${tag} D1 Dashboard distribución: el mismo armado (un solo bloque, encabezado entero, hasta abajo, sin desplazar la página)`, g.hijos.length === 1 && /tdash/.test(g.hijos[0])
     && Math.abs(g.cab.top - g.barraAbajo) < 1 && g.h1.top >= g.barraAbajo && Math.abs(g.dash.bottom - g.alto) < 1 && !g.paginaSeDesplaza && !g.desbordeX, JSON.stringify(g));
  const eRed = await estilos(p);
  // el texto del botón marcado del selector toma el color del dashboard: es la única diferencia permitida (se compara sin el color)
  const sinColor = (o) => (o ? { ...o, color: undefined } : o);
  const iguales = ["cab", "ancho", "h1", "sesion", "volver", "tab", "tabSel", "selOff", "cuerpo", "volverTexto"].filter((k) => JSON.stringify(eRed[k]) !== JSON.stringify(ePtap[k]))
    .concat(JSON.stringify(sinColor(eRed.selOn)) !== JSON.stringify(sinColor(ePtap.selOn)) ? ["selOn"] : []);
  ok(`${tag} D2 encabezado, título, sesión, «Volver a mis formularios», pestañas, selector y cuerpo con los MISMOS estilos que el PTAP`, iguales.length === 0 && eRed.selector,
     iguales.map((k) => `${k}: PTAP ${JSON.stringify(ePtap[k])} / dist ${JSON.stringify(eRed[k])}`).join(" | "));
  ok(`${tag} D3 la única diferencia es el color: el PTAP azul oscuro y distribución verde oscuro`, ePtap.fondoCab === "rgb(10, 37, 64)" && /^rgb\((\d+), (\d+), (\d+)\)$/.test(eRed.fondoCab)
     && (() => { const [r, gg, b] = eRed.fondoCab.match(/\d+/g).map(Number); return gg > r && gg > b && gg < 90; })(), `${ePtap.fondoCab} / ${eRed.fondoCab}`);
  // tarjetas y botones del contenido: los de distribución con la misma letra, alto y radio que los del PTAP
  const boton = (sel) => p.evaluate((sel) => { const e = [...document.querySelectorAll(sel)].find((x) => x.offsetParent); if (!e) return null; const s = getComputedStyle(e); return [s.fontFamily, s.fontSize, s.fontWeight, s.borderRadius, s.minHeight].join("|"); }, sel);
  await clicTexto(p, ".tdash-tab", "Cargue de capas"); await esperarTexto(p, /capas en 5 grupos/);
  const botDist = await boton(".tdash-cuerpo .tec-boton-sec");
  await clicTexto(p, ".tdash-tab", "Personal"); await new Promise((r) => setTimeout(r, 800));
  const tarjDist = await p.evaluate(() => { const e = [...document.querySelectorAll(".tdash-cuerpo .tec-tarjeta")].find((x) => x.offsetParent); if (!e) return null; const s = getComputedStyle(e); return [s.backgroundColor, s.borderRadius, s.borderTopColor, s.marginLeft].join("|"); });
  f = await finalVisible(p);
  ok(`${tag} D4 al bajar hasta el final de Personal, lo último queda a la vista`, f.ultimoAbajo <= f.alto && f.dentro, JSON.stringify(f));
  await p.evaluate(() => { document.querySelector(".tdash").scrollTop = 0; });
  await p.screenshot({ path: join(CAP, `distribucion_personal_${ancho}.png`) });
  await clicTexto(p, ".tdash-sel", "Dashboard PTAP"); await esperarTexto(p, /Personal técnico/);
  await p.waitForFunction(() => !/Cargando el Dashboard/.test(document.body.innerText), { timeout: 30000 }).catch(() => {});
  await clicTexto(p, ".tdash-tab", "Registros"); await esperarTexto(p, /Descargar CSV/);
  const botPtap = await boton(".tdash-cuerpo .td-boton-sec");
  const tarjPtap = await p.evaluate(() => { const e = [...document.querySelectorAll(".tdash-cuerpo .td-tarjeta, .tdash-cuerpo .tpers-tarjeta, .tdash-cuerpo .tec-tarjeta")].find((x) => x.offsetParent); if (!e) return null; const s = getComputedStyle(e); return [s.backgroundColor, s.borderRadius, s.borderTopColor, s.marginLeft].join("|"); });
  ok(`${tag} D5 los botones secundarios del contenido son iguales en los dos (letra, tamaño, peso, radio y alto)`, botDist && botDist === botPtap, `${botPtap} / ${botDist}`);
  ok(`${tag} D6 las tarjetas del contenido de distribución: blancas, borde gris claro, radio de 12 px y alineadas con el cuerpo del PTAP (sin margen propio)`,
     tarjDist === "rgb(255, 255, 255)|12px|rgb(221, 229, 234)|0px", `${tarjPtap} / ${tarjDist}`);
  const vuelta = await clicTexto(p, ".td-boton-claro", "← Volver a mis formularios");
  await esperarTexto(p, /Sesión de/);
  ok(`${tag} D7 «← Volver a mis formularios» vuelve a los formularios`, vuelta);
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
