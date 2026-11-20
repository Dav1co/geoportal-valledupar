// Reportes del Dashboard PTAP (pestaña «Reportes») y Descargas del Dashboard distribución (20-nov-2026) · prueba en CHROME REAL con los dashboards reales
// contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase). Las rutas tienen la forma PROPUESTA al Code A (reporte_iniciar / reporte_pagina /
// reporte_cerrar en geoportal-tecnica y geoportal-redes, y reportes_opciones en geoportal-redes); Daños y fallas e Intervenciones siguen por su ruta «descarga».
// A 390×844 y 1280×900: cada tarjeta, los filtros que van al servidor, la paginación, las dos auditorías (iniciar y cerrar con su resultado), el periodo de
// hasta un año, cero filas, cancelar, 403, 400 y falla a mitad; y cada archivo se ABRE: el Excel con openpyxl (hojas, encabezados con unidad, fechas reales en
// hora de Bogotá, números, enlaces, «Léame») y el CSV (BOM, «;», coma decimal). Mide el armado con un año de datos simulados. Todo dato es inventado (prefijo ZT).
//   node scripts/prueba_chrome_reportes.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas] [raiz_del_codigo]
//   (raiz_del_codigo: otra copia del código, para las capturas «antes»; con ella solo se toman capturas)
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url));
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_reportes"));
const raiz = resolve(process.argv[5] || join(aqui, "..")), SOLO_ANTES = !!process.argv[5];
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_reportes.mjs <chrome> <puppeteer-core> [capturas] [raiz]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55988;      // puertos de Chrome del Code B (55987–55994): 55988 servidor simulado, 55989 la página

// ---------- 1. Paquete de la página (dashboards reales; doble de supabase) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_reportes_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ data: { session: { access_token: "tok" } }, error: null }), signOut: async () => ({}) },
      storage: { from: () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css";
    import { Dashboard } from "./src/tecnica/Dashboard.tsx"; import { DashboardRedes } from "./src/tecnica/DashboardRedes.tsx";
    const q = new URLSearchParams(location.search), r = createRoot(document.getElementById("raiz"));
    r.render(<div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>{q.get("p") === "dist"
      ? <DashboardRedes correo="supervisor.zt@emdupar.gov.co" onVolver={() => {}} />
      : <Dashboard correo="supervisor.zt@emdupar.gov.co" rotuloPerfil="Supervisor de planta" onVolver={() => {}} />}</div>);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"><style>html,body{margin:0;height:100%}</style></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor simulado (todo inventado; prefijo ZT) ----------
const c = (clave, titulo, tipo, unidad = null, extra = {}) => ({ clave, titulo, tipo, unidad, ...extra });
const BASE_PTAP = [c("envio", "Envío", "texto"), c("planta", "Planta", "texto"), c("fecha_muestra", "Fecha de la muestra", "fecha"), c("hora_muestra", "Hora de la muestra", "hora"),
  c("registrado_en", "Registrado", "fecha_hora"), c("autor", "Registró", "texto")];
const COLS = {
  entrada: [...BASE_PTAP, c("turbiedad", "Turbiedad", "numero", "NTU"), c("color", "Color aparente", "numero", "UPC"), c("ph", "pH", "numero"), c("caudal", "Caudal", "numero", "L/s"), c("excluido", "Excluido", "si_no")],
  salida: [...BASE_PTAP, c("turbiedad", "Turbiedad", "numero", "NTU"), c("cloro", "Cloro residual", "numero", "mg/L"), c("ph", "pH", "numero"), c("excluido", "Excluido", "si_no")],
  muestreo: [...BASE_PTAP, c("punto", "Punto", "texto"), c("zona", "Zona", "texto"), c("cloro", "Cloro residual", "numero", "mg/L"), c("excluido", "Excluido", "si_no")],
  uso_quimicos: [...BASE_PTAP, c("quimico", "Químico", "texto"), c("cantidad", "Cantidad usada", "numero", "kg"), c("dosis", "Dosis", "numero", "mg/L")],
  entrada_quimicos: [c("remision", "Remisión", "texto"), c("bodega", "Bodega", "texto"), c("fecha", "Fecha de la remisión", "fecha"), c("quimico", "Químico", "texto"),
    c("cantidad", "Cantidad", "numero", "kg"), c("lote", "Lote", "texto"), c("vence", "Vence", "fecha"), c("foto", "Foto de la remisión", "enlace", null, { texto_enlace: "Ver foto" })],
  kardex_quimicos: [c("quimico", "Químico", "texto"), c("bodega", "Bodega", "texto"), c("orden", "N.º", "entero"), c("cuando", "Fecha y hora", "fecha_hora"), c("movimiento", "Movimiento", "texto"),
    c("entra", "Entrada", "numero", "kg"), c("sale", "Salida", "numero", "kg"), c("saldo", "Saldo", "numero", "kg")],
  eventos_planta: [c("planta", "Planta", "texto"), c("tipo", "Tipo", "texto"), c("causa", "Causa", "texto"), c("inicio", "Inicio", "fecha_hora"), c("fin", "Fin", "fecha_hora"), c("duracion", "Duración", "numero", "min")],
  fuera_referencia: [...BASE_PTAP, c("variable", "Variable", "texto"), c("valor", "Valor", "numero"), c("ref_max", "Referencia máxima", "numero"), c("estado_revision", "Revisión", "texto"), c("revisado_en", "Revisado", "fecha_hora")],
  levantamientos: [c("codigo", "Código", "texto"), c("tipo_activo", "Tipo de activo", "texto"), c("sector", "Sector", "texto"), c("lat", "Latitud", "numero"), c("lon", "Longitud", "numero"), c("cuando", "Levantado", "fecha_hora"), c("estado", "Cómo quedó", "texto")],
  valvulas_cerradas: [c("valvula", "Válvula", "texto"), c("sector", "Sector", "texto"), c("cierre", "Cierre", "fecha_hora"), c("apertura", "Apertura", "fecha_hora"), c("duracion", "Duración", "numero", "h")],
  eventos_suspension: [c("codigo", "Evento", "texto"), c("zona", "Zona", "texto"), c("inicio", "Inicio", "fecha_hora"), c("regreso_estimado", "Regreso estimado", "fecha_hora"), c("regreso_real", "Regreso real", "fecha_hora"),
    c("contratos", "Contratos afectados", "entero"), c("sensibles", "Usuarios sensibles afectados", "entero"), c("reportes", "Reportes asociados", "entero")],
  linea_116: [c("codigo", "Reporte", "texto"), c("contrato", "Contrato", "texto"), c("sector", "Sector", "texto"), c("cuando", "Recibido", "fecha_hora"), c("estado", "Estado", "texto")],
  reportes_bot: [c("codigo", "Reporte", "texto"), c("contrato", "Contrato", "texto"), c("sector", "Sector", "texto"), c("cuando", "Recibido", "fecha_hora"), c("estado", "Estado", "texto")],
  usuarios_sensibles: [c("contrato", "Contrato", "texto"), c("tipo", "Tipo", "texto"), c("sector", "Sector", "texto"), c("desde", "Desde", "fecha")],
  activos_red: [c("codigo", "Código", "texto"), c("tipo", "Tipo", "texto"), c("sistema", "Sistema", "texto"), c("diametro", "Diámetro", "numero", "pulg"), c("sector", "Sector", "texto"), c("lat", "Latitud", "numero"), c("lon", "Longitud", "numero")],
};
const PLANTAS = [{ codigo: "ZT1", nombre: "ZT Planta Uno", activa: true }, { codigo: "ZT2", nombre: "ZT Planta Dos", activa: true }, { codigo: "ZT9", nombre: "ZT Planta Vieja", activa: false }];
const CATALOGO = { formularios: [{ clave: "entrada", nombre: "Entrada", descripcion: "" }], plantas: PLANTAS, zonas: ["norte"], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
const OPCIONES = { sectores: [{ codigo: "S01", nombre: "Sector 1" }, { codigo: "S02", nombre: "Sector 2" }], tipos_activo: [{ codigo: "VAL", nombre: "Válvula" }, { codigo: "HID", nombre: "Hidrante" }] };
const dias = (d, h) => Math.round((Date.parse(`${h}T00:00:00Z`) - Date.parse(`${d}T00:00:00Z`)) / 86400000) + 1;
const fechaN = (desde, i) => new Date(Date.parse(`${desde}T00:00:00Z`) + i * 86400000).toISOString().slice(0, 10);
/** Cuántas filas da un pedido (un año de Entrada sin planta = 3 plantas × 24 envíos × 365 días). */
function cuantas(b) {
  const n = b.desde ? dias(b.desde, b.hasta) : 0;
  switch (b.reporte) {
    case "entrada": return n * 24 * (b.planta ? 1 : 3);
    case "activos_red": return b.tipo_activo ? 4210 : 35781;
    case "usuarios_sensibles": return 37;
    case "salida": case "muestreo": return n * 2;
    default: return Math.max(1, n);
  }
}
function fila(rep, i, b) {
  const d = b.desde ? fechaN(b.desde, Math.floor(i / 24) % Math.max(1, dias(b.desde, b.hasta))) : "2026-11-20";
  const hh = String(i % 24).padStart(2, "0"), regIso = i === 0 ? `${d}T19:05:00Z` : `${d}T${hh}:10:00-05:00`;
  const base = { envio: `ZT-ENV-${i + 1}`, planta: b.planta ? PLANTAS.find((p) => p.codigo === b.planta).nombre : PLANTAS[i % 3].nombre, fecha_muestra: d, hora_muestra: `${hh}:00`,
    registrado_en: regIso, autor: "operador.zt@emdupar.gov.co" };
  switch (rep) {
    case "entrada": return { ...base, turbiedad: 12.5 + (i % 7), color: 30 + (i % 5), ph: 7.12, caudal: 410.25, excluido: i % 50 === 0 };
    case "salida": return { ...base, turbiedad: 0.8, cloro: 1.35, ph: 7.4, excluido: false };
    case "muestreo": return { ...base, punto: `ZT-P${i % 9}`, zona: "Norte", cloro: 0.9, excluido: false };
    case "uso_quimicos": return { ...base, quimico: "ZT Sulfato", cantidad: 125.5, dosis: 22.3 };
    case "entrada_quimicos": return { remision: `ZT-REM-${i + 1}`, bodega: "ZT Bodega Uno", fecha: d, quimico: "ZT Sulfato", cantidad: 1000, lote: `ZTL${i}`, vence: "2027-06-30",
      foto: i === 1 ? "javascript:alert(1)" : `https://geoportal.example/tecnica/remision/ZT-REM-${i + 1}?foto=1&x="y"` };
    case "kardex_quimicos": return { quimico: "ZT Sulfato", bodega: "ZT Bodega Uno", orden: i + 1, cuando: `${d}T08:30:00`, movimiento: i === 0 ? "Inventario inicial" : i % 3 ? "Uso" : "Entrada",
      entra: i % 3 ? null : 500, sale: i % 3 ? 120.25 : null, saldo: 5000 - i * 10.5 };
    case "eventos_planta": return { planta: base.planta, tipo: i % 2 ? "Reanudación" : "Suspensión", causa: "ZT mantenimiento", inicio: regIso, fin: `${d}T23:00:00-05:00`, duracion: 95.5 };
    case "fuera_referencia": return { ...base, variable: "Turbiedad", valor: 2.4, ref_max: 2, estado_revision: "Revisado", revisado_en: `${d}T20:00:00Z` };
    case "levantamientos": return { codigo: `ZT-LEV-${i + 1}`, tipo_activo: "Válvula", sector: b.sector ?? "S01", lat: 10.46, lon: -73.25, cuando: regIso, estado: "Cargado" };
    case "valvulas_cerradas": return { valvula: `ZT-V${i + 1}`, sector: b.sector ?? "S01", cierre: regIso, apertura: `${d}T23:00:00-05:00`, duracion: 3.5 };
    case "eventos_suspension": return { codigo: `ZT-EVS-${i + 1}`, zona: "Sector 1", inicio: regIso, regreso_estimado: `${d}T18:00:00-05:00`, regreso_real: null, contratos: 1520, sensibles: 3, reportes: 7 };
    case "linea_116": case "reportes_bot": return { codigo: `ZT-R${i + 1}`, contrato: String(1000000 + i), sector: b.sector ?? "S02", cuando: regIso, estado: "Recibido" };
    case "usuarios_sensibles": return { contrato: String(2000000 + i), tipo: "Hospital", sector: b.sector ?? "S01", desde: "2026-01-15" };
    case "activos_red": return { codigo: `ZT-A${i + 1}`, tipo: b.tipo_activo === "HID" ? "Hidrante" : "Válvula", sistema: "Acueducto", diametro: 6, sector: b.sector ?? "S01", lat: 10.46, lon: -73.25 };
    default: return {};
  }
}
const MODO = { iniciar: null, pagina: null, lento: 0, opciones: "ok" };       // los casos de error los fija la prueba
const descargas = new Map(); let sigId = 100;
const peticiones = [];
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json", "Cache-Control": "no-store" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (x) => (cuerpo += x)); q.on("end", () => {
    const url = new URL(q.url, "http://x"), fn = url.pathname.split("/").at(-1), accion = url.searchParams.get("accion");
    let b = null; try { b = cuerpo ? JSON.parse(cuerpo) : null; } catch { /* sin cuerpo */ }
    peticiones.push({ fn, accion, cuerpo: b, en: Date.now() });
    const ok = (x, ms = 0) => setTimeout(() => { if (r.writableEnded) return; r.writeHead(200, cab); r.end(JSON.stringify(x)); }, ms);
    const no = (s, m) => { r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    if (fn === "geoportal-tecnica" && accion === "catalogo") return ok(CATALOGO);
    if (fn === "geoportal-redes" && accion === "mi_perfil") return ok({ perfil: "supervisor", email: "supervisor.zt@emdupar.gov.co" });
    if (fn === "geoportal-redes" && accion === "reportes_opciones") return MODO.opciones === "ok" ? ok(OPCIONES) : no(500, "falla");
    if (fn === "geoportal-redes" && accion === "descarga") {        // la ruta de Daños y fallas e Intervenciones (Corte 4b), sin paginar
      const n = 3; const filas = Array.from({ length: n }, (_, i) => b.conjunto === "danos"
        ? { codigo: `ZT-DAN-${i + 1}`, clase: "Daño", tipo: "Fuga", sistema: "Acueducto", activo: "ZT-V1", prefijo: "VAL", tipo_activo: "Válvula", estado: "Atendido", t_detectado: `${b.desde}T15:00:00Z`,
            respuesta_min: 42, sector: 7, tercero_tipo: "vehiculo", origen: "campo", fotos: 2, lat: 10.46, lon: -73.25, autor: "operador.zt@emdupar.gov.co", registrado_en: `${b.desde}T15:05:00Z` }
        : { codigo: `ZT-ITV-${i + 1}`, tipo: "Reparación", t_inicio: `${b.desde}T13:00:00Z`, t_fin: `${b.desde}T15:00:00Z`, duracion_min: 120, valor_total: 350000, resuelve_dano: true });
      return ok({ conjunto: b.conjunto, desde: b.desde, hasta: b.hasta, incluir_ocultos: b.incluir_ocultos, total: n, generado_en: new Date().toISOString(), generado_por: "supervisor.zt@emdupar.gov.co", filas });
    }
    if (accion === "reporte_iniciar") {
      if (MODO.iniciar === 403) return no(403, "No tiene permiso para esta acción.");
      if (MODO.iniciar === 400) return no(400, "Acote el periodo: con esos filtros pasa de 200.000 filas.");
      const total = MODO.iniciar === "cero" ? 0 : cuantas(b), id = ++sigId;
      descargas.set(id, { b, total, entregadas: 0, cerrada: null });
      return ok({ descarga_id: id, reporte: b.reporte, total, max: 200000, generado_por: "supervisor.zt@emdupar.gov.co", generado_en: new Date().toISOString(), columnas: COLS[b.reporte] ?? [] });
    }
    if (accion === "reporte_pagina") {
      const d = descargas.get(b.descarga_id); if (!d) return no(400, "Descarga desconocida.");
      if (MODO.pagina === "falla" && d.entregadas > 0) return no(500, "Falla simulada a mitad de la descarga.");
      const desde = b.despues_de ?? 0, hasta = Math.min(d.total, desde + Math.min(b.limite, 5000));
      const filas = []; for (let i = desde; i < hasta; i++) filas.push(fila(d.b.reporte, i, d.b));
      d.entregadas = hasta;
      return ok({ filas, ultimo: hasta, hay_mas: hasta < d.total }, MODO.lento);
    }
    if (accion === "reporte_cerrar") { const d = descargas.get(b.descarga_id); if (d) d.cerrada = { filas: b.filas, resultado: b.resultado }; return ok({ cerrada: true }); }
    return no(404, "Acción no soportada.");
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, cond, d = "") => { total++; if (!cond) fallas++; console.log(`${cond ? "OK   " : "FALLA"} ${n}${cond ? "" : " " + d}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
const consola = []; const bloqueadas = [];
let ANCHO = 390, ALTO = 844, BAJADAS = "";
async function abrir(qs) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  await pg.setRequestInterception(true);
  pg.on("request", (q) => { const u = q.url(); if (u.startsWith("http://127.0.0.1:") || u.startsWith("data:") || u.startsWith("blob:")) q.continue(); else { bloqueadas.push(u); q.abort(); } });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("ERROR de página:", String(e).slice(0, 200)); });
  pg.on("console", (m) => consola.push(m.text()));
  const cdp = await pg.createCDPSession(); await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: BAJADAS });
  await pg.goto(`${ORIGEN}/?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(400);
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll(".tdash, .rep-tarjeta")].every((e) => e.scrollWidth <= e.clientWidth + 1));
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().startsWith(x) && !e.disabled); if (b) b.click(); return !!b; }, sel, t);
const pestana = (pg, t) => clicTexto(pg, "[role=tab]", t);
const tarjeta = (pg, clave) => pg.evaluate((k) => { const b = document.querySelector(`[data-reporte="${k}"] .rep-cab`); if (b && !b.disabled) b.click(); return !!b && !b.disabled; }, clave);
const enTarjeta = (pg, clave, t) => clicTexto(pg, `[data-reporte="${clave}"] button`, t);
const fijar = (pg, sel, v) => pg.evaluate((s, x) => { const e = document.querySelector(s); if (!e) return false; const set = Object.getOwnPropertyDescriptor(e.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype, "value").set;
  set.call(e, x); e.dispatchEvent(new Event(e.tagName === "SELECT" ? "change" : "input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); return true; }, sel, v);
const marcar = (pg, clave) => pg.evaluate((k) => { const e = document.querySelector(`[data-reporte="${k}"] input[type=checkbox]`); if (e && !e.checked) e.click(); return !!e; }, clave);
const avisoDe = (pg, clave) => pg.evaluate((k) => document.querySelector(`[data-reporte="${k}"] .td-aviso`)?.textContent ?? "", clave);
const esperarAviso = (pg, clave, ms = 30000) => pg.waitForFunction((k) => !!document.querySelector(`[data-reporte="${k}"] .td-aviso`), { timeout: ms }, clave).catch(() => {});
async function archivoNuevo(antes, ext, ms = 30000) {
  const fin = Date.now() + ms;
  while (Date.now() < fin) { const n = readdirSync(BAJADAS).filter((f) => f.endsWith(ext) && !antes.includes(f)); if (n.length) { await esp(300); return join(BAJADAS, n[0]); } await esp(150); }
  return null;
}
const PY = `
import json, sys, openpyxl, datetime
wb = openpyxl.load_workbook(sys.argv[1])
ws = wb.worksheets[0]
filas = list(ws.iter_rows(values_only=True))
def v(x):
    if isinstance(x, datetime.datetime): return {"dt": x.strftime("%Y-%m-%d %H:%M:%S")}
    if isinstance(x, datetime.time): return {"t": x.strftime("%H:%M")}
    return x
enl = [[c.coordinate, c.hyperlink.target if c.hyperlink else None, c.value] for row in ws.iter_rows(min_row=2, max_row=4) for c in row if c.hyperlink]
le = [[a, b] for a, b in wb.worksheets[1].iter_rows(values_only=True)]
print(json.dumps({"hojas": wb.sheetnames, "enc": list(filas[0]), "n": len(filas) - 1, "f1": [v(x) for x in filas[1]] if len(filas) > 1 else [], "f2": [v(x) for x in filas[2]] if len(filas) > 2 else [],
  "fmt": [ws.cell(row=2, column=i + 1).number_format for i in range(len(filas[0]))], "enl": enl, "leame": le}, default=str))`;
const leerXlsx = (f) => JSON.parse(execFileSync("python3", ["-I", "-c", PY, f], { encoding: "utf8", maxBuffer: 64 << 20 }));
const ultimaDescarga = (rep) => [...descargas.entries()].filter(([, d]) => d.b.reporte === rep).at(-1)?.[1];
const pedidosDe = (acc, rep) => peticiones.filter((p) => p.accion === acc && (!rep || p.cuerpo?.reporte === rep));
const HOY = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota" }).format(new Date());
const tiempos = [];

for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
  ANCHO = ancho; ALTO = alto; const T = `[${ancho}]`;
  BAJADAS = join(CAP, `bajadas_${ancho}`); rmSync(BAJADAS, { recursive: true, force: true }); mkdirSync(BAJADAS, { recursive: true });

  // ===================== PTAP =====================
  let pg = await abrir("p=ptap");
  if (SOLO_ANTES) {
    await pg.screenshot({ path: join(CAP, `antes_ptap_pestanas_${ancho}.png`) });
    await pg.close(); pg = await abrir("p=dist"); await pestana(pg, "Descargas"); await esp(500);
    await pg.screenshot({ path: join(CAP, `antes_descargas_${ancho}.png`), fullPage: true }); await pg.close(); continue;
  }
  const tabRep = await pg.evaluate(() => { const b = [...document.querySelectorAll("[role=tab]")].find((e) => e.textContent.startsWith("Reportes")); return b ? { off: b.disabled, txt: b.textContent } : null; });
  ok(`${T} P1 la pestaña «Reportes» ya no dice «Próximamente» y se puede abrir`, !!tabRep && !tabRep.off && !/Próximamente/.test(tabRep.txt), JSON.stringify(tabRep));
  await pestana(pg, "Reportes"); await pg.waitForSelector(".rep-tarjeta", { timeout: 8000 }).catch(() => {});
  const nombres = await pg.evaluate(() => [...document.querySelectorAll(".rep-tarjeta .rep-nom")].map((e) => e.textContent));
  ok(`${T} P2 ocho tarjetas, en el orden del encargo`, JSON.stringify(nombres) === JSON.stringify(["Entrada", "Salida", "Muestreo", "Uso de químicos", "Entrada de químicos", "Kardex de químicos", "Eventos de planta", "Fuera de referencia"]), JSON.stringify(nombres));
  const caja = await pg.evaluate(() => { const t = [...document.querySelectorAll(".rep-tarjeta")]; const cs = getComputedStyle(t[0]); const ini = getComputedStyle(t[0].querySelector(".rep-ini"));
    return { izq: cs.borderLeftWidth, colIzq: cs.borderLeftColor, radio: cs.borderTopLeftRadius, alto: Math.min(...t.map((e) => e.querySelector(".rep-cab").getBoundingClientRect().height)), ini: ini.backgroundColor,
      cols: new Set(t.map((e) => Math.round(e.getBoundingClientRect().left))).size }; });
  ok(`${T} P3 la tarjeta de la guía: borde izquierdo de 5 px y cuadro con la inicial en el color del PTAP (#0a2540), radio 12 px, toque ≥ 44 px; ${ancho < 500 ? "una columna" : "varias columnas"}`,
     caja.izq === "5px" && caja.colIzq === "rgb(10, 37, 64)" && caja.ini === "rgb(10, 37, 64)" && caja.radio === "12px" && caja.alto >= 44 && (ancho < 500 ? caja.cols === 1 : caja.cols >= 3), JSON.stringify(caja));
  await pg.screenshot({ path: join(CAP, `despues_ptap_reportes_${ancho}.png`), fullPage: true });

  // Entrada en Excel, planta ZT1 y con los excluidos
  await tarjeta(pg, "entrada"); await esp(200);
  const form = await pg.evaluate(() => { const t = document.querySelector('[data-reporte="entrada"]'); return { campos: [...t.querySelectorAll("label")].map((l) => l.textContent.trim()),
    plantas: [...t.querySelectorAll("select option")].map((o) => o.textContent), botones: [...t.querySelectorAll(".rep-form button")].map((b) => b.textContent),
    alto: Math.min(...[...t.querySelectorAll(".rep-form button, .rep-form input[type=date], .rep-form select")].map((e) => e.getBoundingClientRect().height)) }; });
  ok(`${T} P4 al abrirla: Desde, Hasta, Planta (solo las activas), «Incluir los excluidos», «Descargar Excel» y «Descargar CSV»; todo de 44 px o más`,
     ["Desde", "Hasta", "Planta"].every((x) => form.campos.includes(x)) && form.campos.some((x) => x.includes("Incluir los excluidos"))
     && JSON.stringify(form.plantas) === JSON.stringify(["Todas las plantas", "ZT Planta Uno", "ZT Planta Dos"]) && JSON.stringify(form.botones) === JSON.stringify(["Descargar Excel", "Descargar CSV"]) && form.alto >= 44, JSON.stringify(form));
  await pg.screenshot({ path: join(CAP, `despues_ptap_tarjeta_abierta_${ancho}.png`), fullPage: true });
  await fijar(pg, "#rep-entrada-desde", "2026-11-01"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10"); await fijar(pg, "#rep-entrada-planta", "ZT1"); await marcar(pg, "entrada");
  let antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada", "Descargar Excel"); await esperarAviso(pg, "entrada");
  let f = await archivoNuevo(antes, ".xlsx");
  const ini = pedidosDe("reporte_iniciar", "entrada").at(-1)?.cuerpo, d1 = ultimaDescarga("entrada");
  ok(`${T} P5 al servidor va el pedido completo: reporte, periodo, planta, con los excluidos y formato`,
     JSON.stringify(ini) === JSON.stringify({ reporte: "entrada", incluir_ocultos: true, formato: "xlsx", desde: "2026-11-01", hasta: "2026-11-10", planta: "ZT1" }), JSON.stringify(ini));
  ok(`${T} P6 «Listo: 240 filas en Excel» y la auditoría se cierra con «completa» y 240 filas`, /Listo: 240 filas en Excel\. La descarga quedó registrada/.test(await avisoDe(pg, "entrada"))
     && d1?.cerrada?.resultado === "completa" && d1?.cerrada?.filas === 240, JSON.stringify(d1?.cerrada));
  let x = f ? leerXlsx(f) : null;
  ok(`${T} P7 el archivo se llama ptap_entrada_ZT1_2026-11-01_a_2026-11-10.xlsx y abre en openpyxl con las hojas «Entrada» y «Léame»`, !!f && f.endsWith("ptap_entrada_ZT1_2026-11-01_a_2026-11-10.xlsx")
     && JSON.stringify(x?.hojas) === JSON.stringify(["Entrada", "Léame"]), f);
  ok(`${T} P8 encabezados con la unidad: «Turbiedad (NTU)», «Color aparente (UPC)», «Caudal (L/s)»; «pH» sin unidad`, !!x && ["Turbiedad (NTU)", "Color aparente (UPC)", "Caudal (L/s)", "pH"].every((h) => x.enc.includes(h)), JSON.stringify(x?.enc));
  const ci = (h) => x.enc.indexOf(h);
  ok(`${T} P9 fechas de Excel reales en hora de Bogotá: la muestra es fecha, la hora es hora, «Registrado» de un «…T19:05:00Z» queda 14:05; los números son números`,
     !!x && x.f1[ci("Fecha de la muestra")]?.dt === "2026-11-01 00:00:00" && x.fmt[ci("Fecha de la muestra")] === "dd/mm/yyyy" && x.fmt[ci("Hora de la muestra")] === "hh:mm"
     && x.f1[ci("Registrado")]?.dt === "2026-11-01 14:05:00" && x.fmt[ci("Registrado")].startsWith("dd/mm/yyyy") && x.f2[ci("Registrado")]?.dt === "2026-11-01 01:10:00"
     && x.f1[ci("Turbiedad (NTU)")] === 12.5 && x.f1[ci("Caudal (L/s)")] === 410.25 && x.f1[ci("Excluido")] === "Sí" && x.n === 240, JSON.stringify([x?.f1, x?.f2, x?.fmt]));
  const le = Object.fromEntries((x?.leame ?? []).map(([a, b]) => [a, b ?? ""]));
  ok(`${T} P10 «Léame»: qué trae, lo que no va (sin teléfonos ni nombres), filtros (periodo, planta, excluidos), filas, quién descargó y cuándo`,
     !!le["Qué trae"] && /Teléfonos, nombres del suscriptor/.test(le["Lo que no va"]) && /01\/11\/2026 a 10\/11\/2026/.test(le["Filtros"]) && /Planta: ZT Planta Uno/.test(le["Filtros"])
     && /Incluir los excluidos: Sí/.test(le["Filtros"]) && le["Filas"] === "240" && le["Descargado por"] === "supervisor.zt@emdupar.gov.co" && /^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}$/.test(le["Fecha y hora de la descarga (Bogotá)"]), JSON.stringify(le));

  // Salida en CSV
  await tarjeta(pg, "salida"); await esp(200);
  const unaAbierta = await pg.evaluate(() => document.querySelectorAll(".rep-abierta").length === 1 && !!document.querySelector('[data-reporte="salida"].rep-abierta'));
  const conserva = await pg.evaluate(() => [document.querySelector("#rep-salida-desde")?.value, document.querySelector("#rep-salida-planta")?.value]);
  ok(`${T} P11 una tarjeta abierta a la vez; el periodo y la planta se conservan al pasar a otra`, unaAbierta && conserva[0] === "2026-11-01" && conserva[1] === "ZT1", JSON.stringify(conserva));
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "salida", "Descargar CSV"); await esperarAviso(pg, "salida");
  f = await archivoNuevo(antes, ".csv");
  const csv = f ? readFileSync(f, "utf8") : ""; const lineas = csv.split("\r\n");
  ok(`${T} P12 el CSV: BOM, «;», unidad en el encabezado, coma decimal, fechas «dd/mm/aaaa hh:mm» en Bogotá, 20 filas`, csv.startsWith("﻿") && lineas[0].includes("Cloro residual (mg/L)") && lineas[0].split(";").length === COLS.salida.length
     && /;1,35;/.test(lineas[1]) && /;01\/11\/2026 14:05;/.test(lineas[1]) && lineas.filter(Boolean).length === 21 && pedidosDe("reporte_iniciar", "salida").at(-1)?.cuerpo?.formato === "csv", lineas.slice(0, 2).join(" | "));

  // Entrada de químicos: el enlace a la foto (no la foto)
  await tarjeta(pg, "entrada_quimicos"); await esp(150); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada_quimicos", "Descargar Excel"); await esperarAviso(pg, "entrada_quimicos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const enl = x?.enl ?? [];
  ok(`${T} P13 Entrada de químicos: «Ver foto» es un hipervínculo a la remisión (con & y comillas bien escritos); un enlace que no es web queda como texto, sin vínculo`,
     enl.length === 2 && enl[0][1] === 'https://geoportal.example/tecnica/remision/ZT-REM-1?foto=1&x="y"' && enl[0][2] === "Ver foto" && x.f2[x.enc.indexOf("Foto de la remisión")] === "javascript:alert(1)"
     && !enl.some((e) => String(e[1]).startsWith("javascript")), JSON.stringify(enl));

  // Kardex: saldo corrido y fecha y hora sin zona (ya en Bogotá)
  await tarjeta(pg, "kardex_quimicos"); await esp(150); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "kardex_quimicos", "Descargar Excel"); await esperarAviso(pg, "kardex_quimicos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  ok(`${T} P14 Kardex: «Saldo (kg)», «N.º» entero, la fecha y hora sin zona se toma como hora de Bogotá (08:30), y celdas vacías donde no hay entrada`,
     !!x && x.enc.includes("Saldo (kg)") && x.f1[x.enc.indexOf("N.º")] === 1 && x.f1[x.enc.indexOf("Fecha y hora")]?.dt === "2026-11-01 08:30:00" && x.f1[x.enc.indexOf("Saldo (kg)")] === 5000
     && x.f2[x.enc.indexOf("Entrada (kg)")] === null && x.n === 10, JSON.stringify(x?.f1));

  // Periodo: más de un año, y «hasta» antes de «desde»: no se pide nada
  await tarjeta(pg, "eventos_planta"); await esp(150);
  let n0 = peticiones.length;
  await fijar(pg, "#rep-eventos_planta-desde", "2025-01-01"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-10");
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esp(300);
  ok(`${T} P15 un periodo de más de un año: «hasta un año por descarga» y no se pide nada`, /Acórtelo: hasta un año por descarga/.test(await avisoDe(pg, "eventos_planta")) && peticiones.length === n0);
  await fijar(pg, "#rep-eventos_planta-desde", "2026-11-10"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-01");
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esp(300);
  ok(`${T} P16 «hasta» antes de «desde»: lo dice y no pide nada`, /«Hasta» no puede ser antes de «desde»/.test(await avisoDe(pg, "eventos_planta")) && peticiones.length === n0);
  await fijar(pg, "#rep-eventos_planta-desde", "2025-11-11"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-10");     // 365 días justos: se acepta
  MODO.iniciar = "cero"; antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esperarAviso(pg, "eventos_planta"); await esp(300);
  let dz = ultimaDescarga("eventos_planta");
  ok(`${T} P17 un año justo se acepta; sin filas: «No hay registros con esos filtros», sin archivo y la auditoría se cierra con 0`, /No hay registros con esos filtros/.test(await avisoDe(pg, "eventos_planta"))
     && readdirSync(BAJADAS).length === antes.length && dz?.cerrada?.resultado === "completa" && dz?.cerrada?.filas === 0, JSON.stringify(dz?.cerrada));
  MODO.iniciar = 403; await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esperarAviso(pg, "eventos_planta"); await esp(200);
  ok(`${T} P18 403: «Solo el supervisor de planta o el administrador descargan reportes.»`, /Solo el supervisor de planta o el administrador descargan reportes/.test(await avisoDe(pg, "eventos_planta")));
  MODO.iniciar = 400; await enTarjeta(pg, "eventos_planta", "Descargar CSV"); await esp(500);
  ok(`${T} P19 400: el texto del servidor tal cual («Acote el periodo…»)`, /Acote el periodo: con esos filtros pasa de 200\.000 filas/.test(await avisoDe(pg, "eventos_planta")));
  MODO.iniciar = null;

  // Falla a mitad y cancelar
  await tarjeta(pg, "entrada"); await esp(150);
  await fijar(pg, "#rep-entrada-desde", "2026-01-01"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10");
  MODO.pagina = "falla"; antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada", "Descargar Excel"); await esperarAviso(pg, "entrada"); await esp(300);
  let dfa = ultimaDescarga("entrada");
  ok(`${T} P20 si una página falla a mitad: el error en pantalla, sin archivo, y la auditoría se cierra con «error» y las filas que alcanzaron a llegar`,
     /Falla simulada/.test(await avisoDe(pg, "entrada")) && readdirSync(BAJADAS).length === antes.length && dfa?.cerrada?.resultado === "error" && dfa?.cerrada?.filas === 5000, JSON.stringify(dfa?.cerrada));
  MODO.pagina = null; MODO.lento = 700;
  await enTarjeta(pg, "entrada", "Descargar Excel");
  await pg.waitForFunction(() => /Descargando [\d.]+ de [\d.]+ filas/.test(document.querySelector('[data-reporte="entrada"] .rep-progreso')?.textContent ?? ""), { timeout: 8000 }).catch(() => {});
  const prog = await pg.evaluate(() => ({ t: document.querySelector('[data-reporte="entrada"] .rep-progreso')?.textContent ?? "", otras: [...document.querySelectorAll(".rep-tarjeta:not(.rep-abierta) .rep-cab")].every((b) => b.disabled) }));
  ok(`${T} P21 mientras descarga: «Descargando 5.000 de 7.536 filas…» con «Cancelar», y las demás tarjetas no se abren`, /Descargando 5\.000 de 7\.536 filas/.test(prog.t) && /Cancelar/.test(prog.t) && prog.otras, JSON.stringify(prog));
  await pg.screenshot({ path: join(CAP, `despues_ptap_descargando_${ancho}.png`) });
  await clicTexto(pg, '[data-reporte="entrada"] .rep-progreso button', "Cancelar"); await esperarAviso(pg, "entrada"); await esp(1200);
  let dca = ultimaDescarga("entrada");
  ok(`${T} P22 cancelar: «Descarga cancelada», sin archivo, la auditoría se cierra con «cancelada»; las tarjetas se vuelven a abrir`, /Descarga cancelada/.test(await avisoDe(pg, "entrada"))
     && dca?.cerrada?.resultado === "cancelada" && readdirSync(BAJADAS).length === antes.length && await pg.evaluate(() => [...document.querySelectorAll(".rep-cab")].every((b) => !b.disabled)), JSON.stringify(dca?.cerrada));
  MODO.lento = 0;

  // Un año de Entrada, las tres plantas: 26.280 filas en 6 páginas
  await fijar(pg, "#rep-entrada-desde", "2025-11-11"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10"); await fijar(pg, "#rep-entrada-planta", "");
  antes = readdirSync(BAJADAS); let t0 = Date.now(); const p0 = pedidosDe("reporte_pagina").length;
  await enTarjeta(pg, "entrada", "Descargar Excel"); await esperarAviso(pg, "entrada", 120000);
  f = await archivoNuevo(antes, ".xlsx", 60000); let ms = Date.now() - t0;
  x = f ? leerXlsx(f) : null;
  tiempos.push(`[${ancho}] Entrada, un año y tres plantas: 26.280 filas, ${(statSync(f).size / 1024 / 1024).toFixed(1)} MB, ${(ms / 1000).toFixed(1)} s (servidor simulado local)`);
  ok(`${T} P23 un año de Entrada (26.280 filas) en 6 páginas de 5.000: el Excel abre con todas las filas (${(ms / 1000).toFixed(1)} s)`, x?.n === 26280 && pedidosDe("reporte_pagina").length - p0 === 6
     && /Listo: 26\.280 filas/.test(await avisoDe(pg, "entrada")), `${x?.n} ${pedidosDe("reporte_pagina").length - p0}`);
  ok(`${T} P24 la pestaña Reportes no desborda`, await sinDesborde(pg));
  await pg.close();

  // ===================== Distribución =====================
  pg = await abrir("p=dist");
  await pestana(pg, "Descargas"); await pg.waitForSelector(".rep-tarjeta", { timeout: 8000 }).catch(() => {});
  const nd = await pg.evaluate(() => [...document.querySelectorAll(".rep-tarjeta .rep-nom")].map((e) => e.textContent));
  ok(`${T} D1 Descargas: nueve tarjetas, en el orden del encargo`, JSON.stringify(nd) === JSON.stringify(["Daños y fallas", "Intervenciones", "Encontrar o reportar activo", "Válvulas cerradas", "Eventos de suspensión", "Línea 116",
    "Reportes del bot", "Usuarios sensibles", "Activos de la red"]), JSON.stringify(nd));
  const colD = await pg.evaluate(() => { const t = document.querySelector(".rep-tarjeta"); return [getComputedStyle(t).borderLeftColor, getComputedStyle(t.querySelector(".rep-ini")).backgroundColor]; });
  ok(`${T} D2 la misma tarjeta, con el verde de distribución (#0f3d2b)`, colD.every((x) => x === "rgb(15, 61, 43)"), JSON.stringify(colD));
  await pg.screenshot({ path: join(CAP, `despues_descargas_${ancho}.png`), fullPage: true });

  // Daños y fallas: la ruta de siempre, ahora también en CSV
  await tarjeta(pg, "danos"); await esp(150);
  await fijar(pg, "#dsc-danos-desde", "2026-11-01"); await fijar(pg, "#dsc-danos-hasta", "2026-11-10"); await marcar(pg, "danos");
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "danos", "Descargar Excel"); await esperarAviso(pg, "danos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const pd = peticiones.filter((p) => p.accion === "descarga").at(-1)?.cuerpo;
  const led = Object.fromEntries((x?.leame ?? []).map(([a, b]) => [a, b ?? ""]));
  ok(`${T} D3 Daños y fallas sigue por su ruta «descarga» (con los ocultos), con sus columnas de siempre; el «Léame» conserva «Lo que no va» y la nota del tipo de activo`,
     JSON.stringify(pd) === JSON.stringify({ conjunto: "danos", desde: "2026-11-01", hasta: "2026-11-10", incluir_ocultos: true }) && x?.hojas[0] === "Daños y fallas" && x.enc[0] === "Código" && x.enc.includes("Tipo de activo (nombre visible)")
     && x.n === 3 && x.f1[x.enc.indexOf("Detectado")]?.dt === "2026-11-01 10:00:00" && /placa del tercero/.test(led["Lo que no va"]) && /prefijo no cambia/.test(led["Tipo de activo"] ?? "")
     && /Listo: 3 filas en Excel/.test(await avisoDe(pg, "danos")) && f.endsWith("danos_fallas_2026-11-01_a_2026-11-10.xlsx"), JSON.stringify([pd, x?.enc?.slice(0, 3), led["Tipo de activo"]]));
  antes = readdirSync(BAJADAS);
  await tarjeta(pg, "intervenciones"); await esp(150); await enTarjeta(pg, "intervenciones", "Descargar CSV"); await esperarAviso(pg, "intervenciones");
  f = await archivoNuevo(antes, ".csv"); const ci2 = f ? readFileSync(f, "utf8").split("\r\n") : [];
  ok(`${T} D4 Intervenciones ahora también en CSV («Resuelve el daño» = Sí, «Valor total» sin separador de miles)`, ci2[0]?.startsWith("﻿Código;Nace de;") && /;Sí;/.test(ci2[1] ?? "") && /;350000;/.test(ci2[1] ?? ""), ci2.slice(0, 2).join(" | "));

  // Válvulas cerradas con sector (opciones del servidor)
  await tarjeta(pg, "valvulas_cerradas"); await esp(150);
  const sects = await pg.evaluate(() => [...document.querySelectorAll("#dsc-valvulas_cerradas-sector option")].map((o) => o.textContent));
  ok(`${T} D5 Válvulas cerradas: filtro de sector con las opciones del servidor`, JSON.stringify(sects) === JSON.stringify(["Todos los sectores", "Sector 1", "Sector 2"]), JSON.stringify(sects));
  await fijar(pg, "#dsc-valvulas_cerradas-sector", "S02"); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "valvulas_cerradas", "Descargar Excel"); await esperarAviso(pg, "valvulas_cerradas");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const pv = pedidosDe("reporte_iniciar", "valvulas_cerradas").at(-1);
  ok(`${T} D6 va a geoportal-redes con el sector; «Léame» dice «Sector: Sector 2»; «Duración (h)»`, pv?.fn === "geoportal-redes" && pv?.cuerpo?.sector === "S02" && !("planta" in (pv?.cuerpo ?? {}))
     && x?.leame.some(([a, b]) => a === "Filtros" && /Sector: Sector 2/.test(b)) && x?.enc.includes("Duración (h)") && x?.f1[x.enc.indexOf("Sector")] === "S02", JSON.stringify(pv));

  // Usuarios sensibles: la foto de hoy (sin periodo)
  await tarjeta(pg, "usuarios_sensibles"); await esp(150);
  const sinPer = await pg.evaluate(() => { const t = document.querySelector('[data-reporte="usuarios_sensibles"]'); return { fechas: t.querySelectorAll("input[type=date]").length, txt: t.textContent, sector: t.querySelector("select")?.value }; });
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "usuarios_sensibles", "Descargar CSV"); await esperarAviso(pg, "usuarios_sensibles");
  f = await archivoNuevo(antes, ".csv"); const ps = pedidosDe("reporte_iniciar", "usuarios_sensibles").at(-1)?.cuerpo;
  ok(`${T} D7 Usuarios sensibles: sin periodo («Es la foto de hoy»), el pedido no lleva fechas; conserva el sector elegido antes (S02, a la vista); archivo usuarios_sensibles_S02_<hoy>.csv con 37 filas`,
     sinPer.fechas === 0 && /Es la foto de hoy/.test(sinPer.txt) && !("desde" in (ps ?? {})) && !("hasta" in (ps ?? {})) && ps?.sector === "S02" && sinPer.sector === "S02" && !!f && f.endsWith(`usuarios_sensibles_S02_${HOY}.csv`)
     && readFileSync(f, "utf8").split("\r\n").filter(Boolean).length === 38, JSON.stringify([ps, f]));

  // Activos de la red: tipo y sector; todo el inventario (35.781 filas)
  await tarjeta(pg, "activos_red"); await esp(150);
  const fa = await pg.evaluate(() => [...document.querySelectorAll('[data-reporte="activos_red"] label')].map((l) => l.textContent.trim()));
  ok(`${T} D8 Activos de la red: filtros «Tipo de activo» y «Sector», y «Incluir los ocultos y retirados»`, fa.includes("Tipo de activo") && fa.includes("Sector") && fa.some((l) => l.includes("Incluir los ocultos y retirados")), JSON.stringify(fa));
  await fijar(pg, "#dsc-activos_red-tipo_activo", "HID"); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "activos_red", "Descargar Excel"); await esperarAviso(pg, "activos_red", 60000);
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  ok(`${T} D9 por tipo: «Hidrante», 4.210 filas; el nombre lleva el sector y el tipo (activos_red_S02_HID_<hoy>.xlsx)`, x?.n === 4210 && x.f1[1] === "Hidrante" && f.endsWith(`activos_red_S02_HID_${HOY}.xlsx`)
     && pedidosDe("reporte_iniciar", "activos_red").at(-1)?.cuerpo?.tipo_activo === "HID", f);
  await fijar(pg, "#dsc-activos_red-tipo_activo", ""); antes = readdirSync(BAJADAS); t0 = Date.now();
  await enTarjeta(pg, "activos_red", "Descargar Excel"); await esperarAviso(pg, "activos_red", 120000);
  f = await archivoNuevo(antes, ".xlsx", 60000); ms = Date.now() - t0; x = f ? leerXlsx(f) : null;
  tiempos.push(`[${ancho}] Activos de la red, todo el inventario: 35.781 filas, ${(statSync(f).size / 1024 / 1024).toFixed(1)} MB, ${(ms / 1000).toFixed(1)} s (servidor simulado local)`);
  ok(`${T} D10 todo el inventario (35.781 filas, 8 páginas) abre completo (${(ms / 1000).toFixed(1)} s)`, x?.n === 35781, String(x?.n));

  // Eventos de suspensión, Línea 116, Reportes del bot y Encontrar: cada uno a su reporte, con su archivo
  for (const [k, ext, n] of [["eventos_suspension", ".xlsx", 10], ["linea_116", ".csv", 10], ["reportes_bot", ".xlsx", 10], ["levantamientos", ".csv", 10]]) {
    await tarjeta(pg, k); await esp(150); await fijar(pg, `#dsc-${k}-desde`, "2026-11-01"); await fijar(pg, `#dsc-${k}-hasta`, "2026-11-10");
    antes = readdirSync(BAJADAS);
    await enTarjeta(pg, k, ext === ".xlsx" ? "Descargar Excel" : "Descargar CSV"); await esperarAviso(pg, k);
    f = await archivoNuevo(antes, ext);
    const filas = !f ? -1 : ext === ".xlsx" ? leerXlsx(f).n : readFileSync(f, "utf8").split("\r\n").filter(Boolean).length - 1;
    ok(`${T} D11 ${k}: pedido a geoportal-redes, ${n} filas en ${ext}, auditoría cerrada`, filas === n && pedidosDe("reporte_iniciar", k).at(-1)?.fn === "geoportal-redes" && ultimaDescarga(k)?.cerrada?.resultado === "completa", `${f} ${filas}`);
    if (k === "eventos_suspension") {
      const xe = leerXlsx(f);
      ok(`${T} D12 eventos: contratos y sensibles afectados como números; regreso real vacío`, xe.f1[xe.enc.indexOf("Contratos afectados")] === 1520 && xe.f1[xe.enc.indexOf("Usuarios sensibles afectados")] === 3
         && xe.f1[xe.enc.indexOf("Regreso real")] === null, JSON.stringify(xe.f1));
    }
  }
  ok(`${T} D13 Descargas no desborda`, await sinDesborde(pg));
  await pg.screenshot({ path: join(CAP, `despues_descargas_abierta_${ancho}.png`), fullPage: true });
  await pg.close();

  // Sin la lista de sectores (la ruta de opciones falla): el filtro queda en «Todos» y lo dice
  MODO.opciones = "falla"; pg = await abrir("p=dist"); await pestana(pg, "Descargas"); await pg.waitForSelector(".rep-tarjeta", { timeout: 8000 }).catch(() => {});
  await tarjeta(pg, "linea_116"); await esp(200);
  const sinLista = await pg.evaluate(() => ({ ops: [...document.querySelectorAll("#dsc-linea_116-sector option")].map((o) => o.textContent), txt: document.querySelector('[data-reporte="linea_116"]').textContent }));
  ok(`${T} D14 si la lista de sectores no carga: solo «Todos los sectores» y el aviso «se descarga todo»; la descarga sigue disponible`,
     JSON.stringify(sinLista.ops) === JSON.stringify(["Todos los sectores"]) && /No se pudo cargar la lista para filtrar: se descarga todo/.test(sinLista.txt) && /Descargar Excel/.test(sinLista.txt), JSON.stringify(sinLista));
  MODO.opciones = "ok"; await pg.close();
}
if (!SOLO_ANTES) {
  ok("Z1 ningún pedido lleva teléfonos ni nombres (solo códigos y fechas)", !peticiones.some((p) => /telefono|nombre_suscriptor|placa/i.test(JSON.stringify(p.cuerpo ?? {}))));
  ok("Z2 ninguna petición salió de la máquina", bloqueadas.length === 0, bloqueadas.slice(0, 3).join(" "));
  console.log("\nTiempos (armado en el navegador con un año de datos simulados):\n  " + tiempos.join("\n  "));
}
await nav.close(); srv.close(); estatico.close();
console.log(SOLO_ANTES ? `\nCapturas «antes» en ${CAP}` : `\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
