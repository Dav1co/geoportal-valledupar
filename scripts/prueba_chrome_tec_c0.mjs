// Técnica · Fase 1 · Corte 0 · prueba en CHROME REAL (puppeteer-core + el Chrome instalado) contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase):
//   • Muestreo ya no sale «Próximamente»: se abre con FormularioPorLugar, lista de los 27 puntos (lista desplegable), guarda UN registro del punto elegido, sin planta;
//   • Entrada y Salida siguen habilitadas; Daños y fallas sigue «Próximamente»;
//   • el botón y el título dicen «Dashboard PTAP» (supervisor); el operador no ve el botón.
// A 390 px y en escritorio.
//   node scripts/prueba_chrome_tec_c0.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas]
// No prueba: la Edge ni la base reales, ni un celular físico.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_tec_c0"));
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_tec_c0.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 54983;

// ---------- 1. Paquete de la página (componentes reales; doble de supabase: la URL de funciones lleva el rol simulado) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_tec_c0_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/" + rol + "/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    try { localStorage.clear(); } catch {}
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo={rol === "sup" ? "supervisor@emdupar.gov.co" : "operario@emdupar.gov.co"} />);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor simulado (formas de la Edge geoportal-tecnica; datos ficticios de prueba) ----------
const hoy = new Date().toISOString().slice(0, 10);
const PUNTOS = Array.from({ length: 27 }, (_, i) => { const n = String(i + 1).padStart(2, "0"); return { codigo: `MUE-${n}`, nombre: `Punto de prueba ${n}`, tipo: "muestreo", planta: null, zona: i < 4 ? "norte" : i < 16 ? "sur" : "medio", orden: null }; });
const VARS = [["ph", "pH", "unidades", 2], ["turbiedad", "Turbiedad", "UNT", 2], ["cloro_residual", "Cloro residual libre", "mg/L", 2], ["e_coli", "E. coli", "UFC/100 mL", 0], ["presion", "Presión", "m.c.a.", 1]]
  .map(([codigo, nombre, unidad, decimales], i) => ({ codigo, nombre, unidad, categoria: "fisicoquimico", decimales, orden: i + 1, obligatoria: false, alcance: "por_punto", punto: null, tipo_punto: "muestreo", puntos: PUNTOS.map((p) => p.codigo) }));
const DEF_MUESTREO = { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "Muestreo en la red" }, fecha_hoy: hoy, hora_propuesta: "08:30", plantas: [], puntos: PUNTOS, variables: VARS };
const DEF_ENTRADA = { formulario: { clave: "entrada", nombre: "Entrada", descripcion: "" }, fecha_hoy: hoy, hora_propuesta: "08:00", plantas: [{ codigo: "ZT1", nombre: "Planta de prueba" }], puntos: [],
  variables: [{ codigo: "qi", nombre: "Caudal de entrada", unidad: "L/s", categoria: "caudal", decimales: 1, orden: 1, obligatoria: false, alcance: "por_planta", punto: null }] };
const MIS = (rol) => ({ perfil: rol === "sup" ? "supervisor" : "operador", formularios: [
  { clave: "entrada", nombre: "Entrada", descripcion: "", con_campos: true },
  { clave: "salida", nombre: "Salida", descripcion: "", con_campos: true },
  { clave: "muestreo", nombre: "Muestreo", descripcion: "", con_campos: true },
  { clave: "danos_fallas", nombre: "Daños y fallas", descripcion: "", con_campos: false }] });
const CATALOGO = { formularios: [{ clave: "entrada", nombre: "Entrada", descripcion: "" }], plantas: [{ codigo: "ZT1", nombre: "Planta de prueba", activa: true }], zonas: [], puntos: [], descarga_max_filas: 1000, descarga_pagina_max: 500, motivo_min: 10, motivo_max: 500 };
const envios = [], rutasDesconocidas = [];
// Forma real de geoportal_tec_resumen_operador para Muestreo (Corte 3-b): una fila por variable y ZONA (norte, sur, medio), con zona y zona_nombre; base «registro».
const RESUMEN_MUESTREO = { formulario: "muestreo", ventana_horas: 24, base: "registro", filas: VARS.flatMap((v) => ["norte", "sur", "medio"].map((z, i) => ({
  variable: v.codigo, nombre: v.nombre, unidad: v.unidad, decimales: v.decimales, planta: null, planta_nombre: null, zona: z, zona_nombre: z[0].toUpperCase() + z.slice(1),
  promedio: v.codigo === "ph" && i === 1 ? 7.35 : null, minimo: v.codigo === "ph" && i === 1 ? 7.2 : null, maximo: v.codigo === "ph" && i === 1 ? 7.5 : null, punto: null, punto_nombre: null }))) };
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x"), rol = u.pathname.split("/")[1], accion = u.searchParams.get("accion");
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || u.pathname.startsWith("/paquete")) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  let cuerpo = ""; req.on("data", (c) => (cuerpo += c));
  req.on("end", () => {
    const json = (s, o) => { res.writeHead(s, { ...cors, "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
    const supervisa = rol === "sup";
    switch (accion) {
      case "mis_formularios": return json(200, MIS(rol));
      case "formulario": return json(200, u.searchParams.get("formulario") === "muestreo" ? DEF_MUESTREO : { ...DEF_ENTRADA, formulario: { ...DEF_ENTRADA.formulario, clave: u.searchParams.get("formulario") } });
      case "resumen": return json(200, u.searchParams.get("formulario") === "muestreo" ? RESUMEN_MUESTREO : { formulario: u.searchParams.get("formulario"), ventana_horas: 24, filas: [] });
      case "quimicos": return json(200, { formulario: u.searchParams.get("formulario"), max_ppm: 500, max_nombre: 60, opciones: [] });
      case "registrar": { const c = JSON.parse(cuerpo || "{}"); envios.push(c); return json(200, { lote_id: `00000000-0000-4000-8000-${String(envios.length).padStart(12, "0")}`, formulario: c.formulario, guardados: c.valores?.length ?? 0, duplicado: false, hora_muestra: c.hora }); }
      // Corte 5b: el minimapa de Muestreo (los puntos del formulario, aproximados, alrededor de Valledupar)
      case "puntos_mapa": return json(200, { type: "FeatureCollection", precision_max_m: 30, sin_ubicacion: [],
        features: DEF_MUESTREO.puntos.map((m, i) => ({ type: "Feature", geometry: { type: "Point", coordinates: [-73.28 + (i % 6) * 0.01, 10.44 + Math.floor(i / 6) * 0.008] }, properties: { codigo: m.codigo, nombre: m.nombre, zona: m.zona ?? null, exactitud: "aproximada", fuente: "barrio", en_revision: false, propuesta_mia: false } })) });
      case "catalogo": return supervisa ? json(200, CATALOGO) : json(403, { error: "Sin permiso." });
      case "registros": return supervisa ? json(200, { total: 0, devueltos: 0, registros: [] }) : json(403, { error: "Sin permiso." });
      case "dosis": return supervisa ? json(200, { total: 0, devueltos: 0, dosis: [] }) : json(403, { error: "Sin permiso." });
      default: rutasDesconocidas.push(`${rol}:${accion}`); return json(404, { error: `Ruta simulada no definida: ${accion}` });
    }
  });
});
await new Promise((r) => srv.listen(PUERTO, "127.0.0.1", r));

// ---------- 3. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det }); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check"] });
const errores = [];
async function abrir(rol, ancho) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${rol}/${ancho}: ${e.message}`));
  p.on("console", (m) => { if (m.type() === "error") errores.push(`${rol}/${ancho} consola: ${m.text()}`); });
  await p.goto(`http://127.0.0.1:${PUERTO}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true);
  await p.waitForSelector(".tec-chips"); return p;
}
const chips = (p) => p.$$eval(".tec-chip-form", (bs) => bs.map((b) => ({ t: b.textContent.trim(), dis: b.disabled })));
const clicTexto = (p, sel, texto) => p.evaluate((sel, texto) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(texto)); if (!b) return false; b.click(); return true; }, sel, texto);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

for (const ancho of [390, 1280]) {
  // --- Operador ---
  const p = await abrir("op", ancho);
  const c = await chips(p);
  ok(`[${ancho}] operador: Entrada, Salida y Muestreo habilitados`, ["Entrada", "Salida", "Muestreo"].every((n) => c.find((x) => x.t === n && !x.dis)), JSON.stringify(c));
  ok(`[${ancho}] operador: Daños y fallas sigue «Próximamente»`, c.find((x) => x.t.startsWith("Daños") && x.dis && /Próximamente/.test(x.t)));
  ok(`[${ancho}] operador: no ve «Dashboard PTAP»`, !(await p.evaluate(() => /Dashboard PTAP/.test(document.body.innerText))));
  ok(`[${ancho}] operador: ningún texto «Dashboard técnico» en pantalla`, !(await p.evaluate(() => /Dashboard t[eé]cnic/i.test(document.body.innerText))));
  await clicTexto(p, ".tec-chip-form", "Muestreo");
  await p.waitForFunction(() => /Puntos de muestreo/.test(document.body.innerText));
  const sel = await p.$$eval("select", (ss) => ss.map((s) => s.options.length));
  ok(`[${ancho}] Muestreo: una lista con los 27 puntos (+ «Elija…»)`, sel.length === 1 && sel[0] === 28, JSON.stringify(sel));
  ok(`[${ancho}] Muestreo: sin selector de planta`, !(await p.evaluate(() => /Elija la planta/.test(document.body.innerText))));
  ok(`[${ancho}] Muestreo: sin desborde horizontal`, await sinDesborde(p));
  await p.waitForFunction(() => /Por zona, sin autor/.test(document.body.innerText));
  const filasRes = await p.$$eval('[aria-label="Resumen de las últimas 24 horas"] .tec-fila:not(.tec-fila-cab) [role=cell]:first-child', (cs) => cs.map((c) => c.textContent));
  ok(`[${ancho}] Muestreo: el resumen de 24 h sale por zona (15 filas distintas, «Zona Norte/Sur/Medio»)`, filasRes.length === 15 && new Set(filasRes).size === 15 && filasRes.some((t) => /Zona Sur/.test(t)), JSON.stringify(filasRes.slice(0, 4)));
  await p.screenshot({ path: join(CAP, `muestreo_vacio_${ancho}.png`), fullPage: true });
  await p.select("select", "MUE-03");
  await p.waitForSelector("input[inputmode]");
  const campos = await p.$$("input[inputmode]");
  await campos[0].type("7.4"); await campos[1].type("0.35");
  await p.screenshot({ path: join(CAP, `muestreo_lleno_${ancho}.png`), fullPage: true });
  const antes = envios.length;
  await clicTexto(p, "button", "Guardar registro");
  await p.waitForFunction(() => /Va a guardar/.test(document.body.innerText));
  await clicTexto(p, "button", "Confirmar y guardar");
  await p.waitForFunction((n) => /✔/.test(document.body.innerText), {}, antes);
  const e = envios[envios.length - 1];
  ok(`[${ancho}] Muestreo: guarda UN registro del punto elegido, sin planta`, envios.length === antes + 1 && e.formulario === "muestreo" && e.punto === "MUE-03" && e.planta === null && e.valores.length === 2, JSON.stringify(e));
  ok(`[${ancho}] Muestreo: envía la hora de inicio y la clave de envío`, typeof e.inicio_dispositivo === "string" && typeof e.clave_envio === "string" && e.clave_envio.length > 8);
  await p.screenshot({ path: join(CAP, `muestreo_guardado_${ancho}.png`), fullPage: true });
  await p.close();

  // --- Supervisor ---
  const s = await abrir("sup", ancho);
  ok(`[${ancho}] supervisor: botón «Dashboard PTAP»`, await clicTexto(s, "button", "Dashboard PTAP"));
  await s.waitForSelector(".tdash h1");
  ok(`[${ancho}] supervisor: título «Dashboard PTAP»`, (await s.$eval(".tdash h1", (h) => h.textContent)) === "Dashboard PTAP");
  ok(`[${ancho}] supervisor: nav con aria-label «Secciones del Dashboard PTAP»`, !!(await s.$('nav[aria-label="Secciones del Dashboard PTAP"]')));
  ok(`[${ancho}] supervisor: ningún «Dashboard técnico» en pantalla`, !(await s.evaluate(() => /Dashboard t[eé]cnic/i.test(document.body.innerText))));
  await s.screenshot({ path: join(CAP, `dashboard_ptap_${ancho}.png`), fullPage: false });
  await s.close();
}
ok("ninguna ruta pedida fuera de las simuladas", rutasDesconocidas.length === 0, rutasDesconocidas.join(", "));
ok("sin errores de página ni de consola", errores.length === 0, errores.join(" | "));
await nav.close(); srv.close();

const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "✔" : "✖"} ${r.nombre}${r.ok || !r.det ? "" : `  →  ${r.det}`}`);
console.log(`\n${bien} de ${resultados.length} · capturas en ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
