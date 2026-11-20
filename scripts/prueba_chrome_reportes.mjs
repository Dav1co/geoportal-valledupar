// Reportes del Dashboard PTAP (pestaña «Reportes») y Descargas del Dashboard distribución (20-nov-2026) · prueba en CHROME REAL con los dashboards reales
// contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase). Las rutas tienen la forma del CONTRATO DEL CODE A (paquete_fase1/reportes_ptap_distribucion/
// ENTRADA_BITACORA.md, §1–3): reporte_iniciar / reporte_pagina / reporte_cerrar en geoportal-tecnica y geoportal-redes, y reporte_remision_foto; el simulador
// RECHAZA lo que el contrato rechaza (un filtro que no aplica, una clave desconocida, un periodo sin fechas) y responde 404 sin datos. Daños y fallas e
// Intervenciones siguen por su ruta «descarga».
// A 390×844 y 1280×900: cada tarjeta, los filtros que van al servidor, la paginación por cursor, las dos auditorías (iniciar y cerrar con su resultado), el
// periodo de hasta un año, sin datos, cancelar, 403, 400 y falla a mitad; cada archivo se ABRE: el Excel con openpyxl (hojas, encabezados con unidad, fechas
// reales en hora de Bogotá, números, el vínculo «Ver foto», «Léame» del servidor) y el CSV (BOM, «;», coma decimal); la página remision.html con y sin sesión.
// Mide el armado con un año de datos simulados. Todo dato es inventado (prefijo ZT).
//   node scripts/prueba_chrome_reportes.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas] [raiz_del_codigo]
//   (raiz_del_codigo: otra copia del código, para las capturas «antes»; con ella solo se toman capturas)
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, statSync, existsSync } from "node:fs";
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

// ---------- 1. Paquetes de las páginas (dashboards reales y remision.html; doble de supabase: «?sinsesion=1» = sin sesión iniciada) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_reportes_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const sin = new URLSearchParams(location.search).get("sinsesion") === "1";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: sin ? null : { access_token: "tok" } } }), refreshSession: async () => ({ data: { session: null }, error: sin ? { message: "x" } : null }), signOut: async () => ({}) },
      storage: { from: () => ({}) } };` }));
} };
const opcionesBuild = (salida) => ({ plugins: [doble], bundle: true, platform: "browser", format: "iife", outfile: join(dir, salida), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' } });
await build({ ...opcionesBuild("paquete.js"),
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css";
    import { Dashboard } from "./src/tecnica/Dashboard.tsx"; import { DashboardRedes } from "./src/tecnica/DashboardRedes.tsx";
    const q = new URLSearchParams(location.search), r = createRoot(document.getElementById("raiz"));
    r.render(<div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>{q.get("p") === "dist"
      ? <DashboardRedes correo="supervisor.zt@emdupar.gov.co" onVolver={() => {}} />
      : <Dashboard correo="supervisor.zt@emdupar.gov.co" rotuloPerfil="Supervisor de planta" onVolver={() => {}} />}</div>);
    setTimeout(() => { window.__listo = true; }, 400);` } });
const conRemision = existsSync(join(raiz, "src/remision/FotoRemision.tsx"));
if (conRemision) await build({ ...opcionesBuild("remision.js"), stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client"; import { FotoRemision } from "./src/remision/FotoRemision.tsx";
    createRoot(document.getElementById("root")).render(<FotoRemision />); setTimeout(() => { window.__listo = true; }, 300);` } });
const html = (js, css, raizId) => `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${css}"><style>html,body{margin:0;height:100%}</style></head><body><div id="${raizId}"></div><script src="${js}"></script></body></html>`;
writeFileSync(join(dir, "index.html"), html("paquete.js", "paquete.css", "raiz"));
if (conRemision) writeFileSync(join(dir, "remision.html"), html("remision.js", "remision.css", "root"));
// una «foto» de prueba (PNG de 2×2, inventado) para la URL firmada simulada
writeFileSync(join(dir, "foto_zt.png"), Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGNgYGD4z8DAwMDAwMAAAA8AAf+ZqgQAAAAASUVORK5CYII=", "base64"));

// ---------- 2. Servidor simulado con el contrato del Code A (todo inventado; prefijo ZT) ----------
const c = (clave, titulo, tipo, unidad = null, extra = {}) => ({ clave, titulo, unidad, tipo, ...extra });
const VARS_ENTRADA = [c("v_turbiedad_ingreso", "Turbiedad de ingreso (Ti)", "decimal", "NTU", { decimales: 1 }), c("v_color", "Color aparente", "decimal", "UPC", { decimales: 0 }),
  c("v_ph", "pH", "decimal", null, { decimales: 2 }), c("v_caudal", "Caudal", "decimal", "L/s", { decimales: 1 })];
const COLS = {
  entrada: [c("muestra", "Fecha y hora de la muestra", "fecha_hora"), c("planta", "Planta", "texto"), ...VARS_ENTRADA, c("coagulante", "Coagulante", "texto"), c("dosis_ppm", "Dosis", "decimal", "ppm"),
    c("fuera_referencia", "Valores fuera de referencia", "entero"), c("estado", "Estado", "texto"), c("fuente", "Fuente", "texto"), c("registrado", "Registrado", "fecha_hora"), c("registro", "Registró", "texto"), c("envio", "Envío", "texto")],
  salida: [c("muestra", "Fecha y hora de la muestra", "fecha_hora"), c("planta", "Planta", "texto"), c("v_turbiedad", "Turbiedad", "decimal", "NTU"), c("v_cloro", "Cloro residual", "decimal", "mg/L"),
    c("estado", "Estado", "texto"), c("registrado", "Registrado", "fecha_hora"), c("registro", "Registró", "texto"), c("envio", "Envío", "texto")],
  muestreo: [c("muestra", "Fecha y hora de la muestra", "fecha_hora"), c("punto", "Punto", "texto"), c("zona", "Zona", "texto"), c("numero_informe", "N.º de informe", "entero"), c("v_cloro", "Cloro residual", "decimal", "mg/L"), c("estado", "Estado", "texto")],
  uso_quimicos: [c("movimiento", "Movimiento", "entero"), c("dia", "Día", "fecha"), c("quimico", "Químico", "texto"), c("planta", "Planta", "texto"), c("cantidad_kg", "Cantidad", "decimal", "kg"), c("dosis_optima_ppm", "Dosis óptima", "decimal", "ppm")],
  entrada_quimicos: [c("movimiento", "Movimiento", "entero"), c("dia", "Día", "fecha"), c("quimico", "Químico", "texto"), c("cantidad_kg", "Cantidad", "decimal", "kg"), c("proveedor", "Proveedor", "texto"),
    c("remision", "Remisión", "texto"), c("vence", "Vence", "fecha"), c("foto_remision", "Foto de la remisión", "enlace"), c("registrado", "Registrado", "fecha_hora")],
  kardex_quimicos: [c("quimico", "Químico", "texto"), c("bodega", "Bodega", "texto"), c("dia", "Día", "fecha"), c("movimiento", "Movimiento", "entero"), c("tipo", "Tipo", "texto"),
    c("entra_kg", "Entra", "decimal", "kg"), c("sale_kg", "Sale", "decimal", "kg"), c("saldo_kg", "Saldo", "decimal", "kg")],
  eventos_planta: [c("evento", "Evento", "texto"), c("planta", "Planta", "texto"), c("estado", "Estado", "texto"), c("suspendido", "Suspendido", "fecha_hora"), c("reanudado", "Reanudado", "fecha_hora"), c("duracion_h", "Duración", "decimal", "h")],
  fuera_referencia: [c("muestra", "Fecha y hora de la muestra", "fecha_hora"), c("variable", "Variable", "texto"), c("valor", "Valor", "decimal"), c("ref_max", "Referencia máxima", "decimal"), c("revision", "Revisión", "texto"), c("revisado_en", "Revisado", "fecha_hora")],
  levantamientos: [c("codigo", "Código", "texto"), c("reportado", "Reportado", "fecha_hora"), c("tipo", "Tipo", "texto"), c("estado", "Estado", "texto"), c("precision_m", "Precisión", "decimal", "m"), c("sector", "Sector", "entero"), c("lat", "Latitud", "decimal"), c("lon", "Longitud", "decimal")],
  valvulas: [c("valvula", "Válvula", "texto"), c("cerrada", "Cerrada", "fecha_hora"), c("abierta", "Abierta", "fecha_hora"), c("duracion_h", "Duración", "decimal", "h"), c("estado", "Estado", "texto"), c("sector", "Sector", "entero")],
  eventos: [c("evento", "Evento", "texto"), c("alcance", "Alcance", "texto"), c("zona", "Zona", "texto"), c("desde", "Desde", "fecha_hora"), c("regreso_estimado", "Regreso estimado", "fecha_hora"), c("fin", "Fin", "fecha_hora"),
    c("contratos", "Contratos afectados", "entero"), c("sensibles", "Usuarios sensibles afectados", "entero"), c("reportes", "Reportes asociados", "entero")],
  l116: [c("reporte", "Reporte", "texto"), c("registrado_116", "Registrado en la 116", "fecha_hora"), c("contrato", "Contrato", "texto"), c("estado", "Estado", "texto"), c("sector", "Sector", "entero"), c("oculto", "Oculto", "si_no")],
  bot: [c("radicado", "Radicado", "texto"), c("recibido", "Recibido", "fecha_hora"), c("estado", "Estado", "texto"), c("sector", "Sector", "entero")],
  sensibles: [c("contrato", "Contrato", "texto"), c("tipo", "Tipo", "texto"), c("estado", "Estado", "texto"), c("desde", "Desde", "fecha_hora"), c("sector", "Sector", "entero")],
  activos: [c("codigo", "Código", "texto"), c("tipo", "Tipo", "texto"), c("prefijo", "Prefijo", "texto"), c("sistema", "Sistema", "texto"), c("diametro_mm", "Diámetro", "decimal", "mm"), c("sector", "Sector", "entero"), c("lat", "Latitud", "decimal"), c("lon", "Longitud", "decimal")],
};
// Filtros que acepta cada reporte e «Incluir excluidos» (tablas §2 y §3 del contrato). «no aplica» en distribución: se rechaza aquí, para que la pantalla no lo mande.
const ACEPTA = { entrada: ["planta"], salida: ["planta"], muestreo: ["punto", "zona"], uso_quimicos: ["planta", "quimico"], entrada_quimicos: ["quimico"], kardex_quimicos: ["quimico"],
  eventos_planta: ["planta"], fuera_referencia: ["planta", "formulario", "punto"], levantamientos: ["sector"], valvulas: ["sector"], eventos: ["sector"], l116: ["sector"], bot: ["sector"],
  sensibles: ["tipo"], activos: ["tipo", "sistema"] };
const SIN_EXCLUIDOS = new Set(["valvulas"]);
const INVENTARIO = new Set(["sensibles", "activos"]);
const PLANTAS = [{ codigo: "ZT1", nombre: "ZT Planta Uno", activa: true }, { codigo: "ZT2", nombre: "ZT Planta Dos", activa: true }, { codigo: "ZT9", nombre: "ZT Planta Vieja", activa: false }];
const CATALOGO = { formularios: [{ clave: "entrada", nombre: "Entrada", descripcion: "" }], plantas: PLANTAS, zonas: ["norte", "sur"],
  puntos: [{ codigo: "ZT-P1", nombre: "ZT Punto Uno", tipo: "red", zona: "norte", planta: "ZT1", numero_informe: 1, activo: true }, { codigo: "ZT-P9", nombre: "ZT Punto Viejo", tipo: "red", zona: "sur", planta: null, numero_informe: 9, activo: false }],
  descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
const QUIMICOS = { quimicos: [{ codigo: "pac", nombre: "ZT PAC", activo: true }, { codigo: "cloro", nombre: "ZT Cloro gaseoso", activo: true }, { codigo: "viejo", nombre: "ZT Viejo", activo: false }], parametros: {}, puede_editar: false };
const TIPOS = { puede_editar: false, tipos: [{ prefijo: "VAL", nombre: "Válvula", nombre_visible: "Válvula", activo: true, sistema: "acueducto" }, { prefijo: "HID", nombre: "Hidrante", nombre_visible: "Hidrante", activo: true, sistema: "acueducto" },
  { prefijo: "XXX", nombre: "Retirado", nombre_visible: "Retirado", activo: false, sistema: "acueducto" }], materiales: [], estados: [], contratistas: [], aportantes: [], tipos_intervencion: [], tipos_dano: [] };
const dias = (d, h) => Math.round((Date.parse(`${h}T00:00:00Z`) - Date.parse(`${d}T00:00:00Z`)) / 86400000) + 1;
const fechaN = (desde, i) => new Date(Date.parse(`${desde}T00:00:00Z`) + i * 86400000).toISOString().slice(0, 10);
/** Cuántas filas da un pedido (un año de Entrada sin planta = 3 plantas × 24 envíos × 365 días). */
function cuantas(b) {
  const n = b.desde ? dias(b.desde, b.hasta) : 0;
  switch (b.reporte) {
    case "entrada": return n * 24 * (b.planta ? 1 : 3);
    case "activos": return b.tipo ? 4210 : 35781;
    case "sensibles": return 37;
    case "salida": case "muestreo": return n * 2;
    default: return Math.max(1, n);
  }
}
function fila(rep, i, b) {
  const d = b.desde ? fechaN(b.desde, Math.floor(i / 24) % Math.max(1, dias(b.desde, b.hasta))) : "2026-11-20";
  const hh = String(i % 24).padStart(2, "0"), loc = `${d}T${hh}:10:00`;       // fecha_hora de Bogotá, SIN zona (contrato §1.2)
  const planta = b.planta ? PLANTAS.find((p) => p.codigo === b.planta).nombre : PLANTAS[i % 3].nombre;
  switch (rep) {
    case "entrada": return { muestra: loc, planta, v_turbiedad_ingreso: 12.5 + (i % 7), v_color: 30, v_ph: i % 50 === 0 ? null : 7.12, v_caudal: 410.25, coagulante: "ZT PAC", dosis_ppm: 22.4,
      fuera_referencia: i % 10 === 0 ? 1 : 0, estado: i % 50 === 0 ? "Excluido en parte" : "Vigente", fuente: "Manual", registrado: `${d}T${hh}:12:30`, registro: "operador.zt@emdupar.gov.co", envio: `ZT-ENV-${i + 1}` };
    case "salida": return { muestra: loc, planta, v_turbiedad: 0.8, v_cloro: 1.35, estado: "Vigente", registrado: loc, registro: "operador.zt@emdupar.gov.co", envio: `ZT-ENV-${i + 1}` };
    case "muestreo": return { muestra: loc, punto: b.punto ?? "ZT-P1", zona: b.zona ?? "norte", numero_informe: 1, v_cloro: 0.9, estado: "Vigente" };
    case "uso_quimicos": return { movimiento: 100 + i, dia: d, quimico: "ZT PAC", planta, cantidad_kg: 125.5, dosis_optima_ppm: 22 };
    case "entrada_quimicos": return { movimiento: 7 + i, dia: d, quimico: "ZT PAC", cantidad_kg: 1000, proveedor: "ZT Proveedor S. A.", remision: `ZT-REM-${i + 1}`, vence: "2027-06-30",
      foto_remision: i === 1 ? null : 7 + i, registrado: loc };
    case "kardex_quimicos": return { quimico: "ZT PAC", bodega: "Bodega de químicos", dia: d, movimiento: i === 0 ? null : 200 + i, tipo: i === 0 ? "Saldo inicial" : i % 3 ? "Uso" : "Entrada",
      entra_kg: i % 3 ? null : 500, sale_kg: i % 3 && i ? 120.25 : null, saldo_kg: 5000 - i * 10.5 };
    case "eventos_planta": return { evento: `ZT-EVS-${i + 1}`, planta, estado: "Cerrado", suspendido: loc, reanudado: `${d}T23:00:00`, duracion_h: 4.8 };
    case "fuera_referencia": return { muestra: loc, variable: "Turbiedad", valor: 2.4, ref_max: 2, revision: "Revisado", revisado_en: `${d}T20:00:00` };
    case "levantamientos": return { codigo: `ZT-LEV-${i + 1}`, reportado: loc, tipo: "Válvula", estado: "Levantado", precision_m: 4.5, sector: Number(b.sector ?? 5), lat: 10.46, lon: -73.25 };
    case "valvulas": return { valvula: `ZT-V${i + 1}`, cerrada: loc, abierta: `${d}T23:00:00`, duracion_h: 3.5, estado: "Abierta", sector: Number(b.sector ?? 5) };
    case "eventos": return { evento: `ZT-EVS-${i + 1}`, alcance: "Sectores", zona: "los sectores 5 y 6", desde: loc, regreso_estimado: `${d}T18:00:00`, fin: null, contratos: 1520, sensibles: 3, reportes: 7 };
    case "l116": return { reporte: `ZT-116-${i + 1}`, registrado_116: loc, contrato: String(1000000 + i), estado: "Registrado", sector: Number(b.sector ?? 6), oculto: false };
    case "bot": return { radicado: `ZT-BOT-${i + 1}`, recibido: loc, estado: "Recibido", sector: Number(b.sector ?? 6) };
    case "sensibles": return { contrato: String(2000000 + i), tipo: "Hospital", estado: "Confirmado", desde: "2026-01-15T08:00:00", sector: 5 };
    case "activos": return { codigo: `ZT-A${i + 1}`, tipo: b.tipo === "HID" ? "Hidrante" : "Válvula", prefijo: b.tipo ?? "VAL", sistema: b.sistema ?? "acueducto", diametro_mm: 150, sector: 5, lat: 10.46, lon: -73.25 };
    default: return {};
  }
}
const CLAVES_CUERPO = new Set(["reporte", "desde", "hasta", "formato", "incluir_excluidos", "planta", "punto", "zona", "quimico", "formulario", "sector", "tipo", "sistema"]);
const MODO = { iniciar: null, pagina: null, lento: 0, quimicos: "ok", foto: "ok" };       // los casos de error los fija la prueba
const descargas = new Map(); let sigId = 100;
const peticiones = [];
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json", "Cache-Control": "no-store" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (x) => (cuerpo += x)); q.on("end", () => {
    const url = new URL(q.url, "http://x"), fn = url.pathname.split("/").at(-1), accion = url.searchParams.get("accion");
    let b = null; try { b = cuerpo ? JSON.parse(cuerpo) : null; } catch { /* sin cuerpo */ }
    peticiones.push({ fn, accion, cuerpo: b, qs: Object.fromEntries(url.searchParams), en: Date.now() });
    const ok = (x, ms = 0) => setTimeout(() => { if (r.writableEnded) return; r.writeHead(200, cab); r.end(JSON.stringify(x)); }, ms);
    const no = (s, m) => { if (s === 400 && accion === "reporte_iniciar") peticiones.at(-1).rechazo = m; r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    if (fn === "geoportal-tecnica" && accion === "catalogo") return ok(CATALOGO);
    if (fn === "geoportal-tecnica" && accion === "quimicos_catalogo") return MODO.quimicos === "ok" ? ok(QUIMICOS) : no(500, "falla");
    if (fn === "geoportal-tecnica" && accion === "reporte_remision_foto") {
      if (MODO.foto === 403) return no(403, "No tiene permiso para esta acción.");
      if (url.searchParams.get("movimiento") === "404") return no(404, "Ese movimiento no tiene foto de la remisión.");
      return ok({ movimiento: Number(url.searchParams.get("movimiento")), url: `http://127.0.0.1:${PUERTO + 1}/foto_zt.png?firma=zt`, vence_en_s: 60 });
    }
    if (fn === "geoportal-redes" && accion === "mi_perfil") return ok({ perfil: "supervisor", email: "supervisor.zt@emdupar.gov.co" });
    if (fn === "geoportal-redes" && accion === "catalogo") return ok(TIPOS);
    if (fn === "geoportal-redes" && accion === "descarga") {        // la ruta de Daños y fallas e Intervenciones (Corte 4b), sin paginar
      const n = 3; const filas = Array.from({ length: n }, (_, i) => b.conjunto === "danos"
        ? { codigo: `ZT-DAN-${i + 1}`, clase: "Daño", tipo: "Fuga", sistema: "Acueducto", activo: "ZT-V1", prefijo: "VAL", tipo_activo: "Válvula", estado: "Atendido", t_detectado: `${b.desde}T15:00:00Z`,
            respuesta_min: 42, sector: 7, tercero_tipo: "vehiculo", origen: "campo", fotos: 2, lat: 10.46, lon: -73.25, autor: "operador.zt@emdupar.gov.co", registrado_en: `${b.desde}T15:05:00Z` }
        : { codigo: `ZT-ITV-${i + 1}`, tipo: "Reparación", t_inicio: `${b.desde}T13:00:00Z`, t_fin: `${b.desde}T15:00:00Z`, duracion_min: 120, valor_total: 350000, resuelve_dano: true });
      return ok({ conjunto: b.conjunto, desde: b.desde, hasta: b.hasta, incluir_ocultos: b.incluir_ocultos, total: n, generado_en: new Date().toISOString(), generado_por: "supervisor.zt@emdupar.gov.co", filas });
    }
    if (accion === "reporte_iniciar") {
      if (MODO.iniciar === 403) return no(403, "No tiene permiso para esta acción.");
      if (MODO.iniciar === "tope") { r.writeHead(400, cab); return r.end(JSON.stringify({ error: "La descarga supera el máximo de 50.000 filas (hay 61200). Acote el periodo o los filtros." })); }
      if (!COLS[b?.reporte]) return no(400, "Ese reporte no existe.");
      if (Object.keys(b).some((k) => !CLAVES_CUERPO.has(k))) return no(400, "La solicitud trae un dato que no corresponde.");
      if (Object.keys(b).some((k) => !["reporte", "desde", "hasta", "formato", "incluir_excluidos"].includes(k) && !ACEPTA[b.reporte].includes(k))) return no(400, "Ese filtro no aplica a este reporte.");
      if (SIN_EXCLUIDOS.has(b.reporte) && "incluir_excluidos" in b) return no(400, "Ese filtro no aplica a este reporte.");
      if (!INVENTARIO.has(b.reporte) && (!b.desde || !b.hasta || dias(b.desde, b.hasta) > 366)) return no(400, "El periodo es obligatorio y de 366 días como máximo.");
      if (b.sector !== undefined && !/^\d+$/.test(b.sector)) return no(400, "El sector es un número.");
      const total = MODO.iniciar === "cero" ? 0 : cuantas(b);
      if (total === 0) return no(404, "No hay datos con esos filtros.");
      if (total > 50000) return no(400, `La descarga supera el máximo de 50.000 filas (hay ${total}). Acote el periodo o los filtros.`);
      const id = ++sigId; descargas.set(id, { b, total, entregadas: 0, cerrada: null, fn });
      const filtrosTxt = [b.desde ? `Periodo: ${b.desde.split("-").reverse().join("/")} a ${b.hasta.split("-").reverse().join("/")} (servidor)` : "Inventario a hoy (servidor)",
        ...ACEPTA[b.reporte].filter((k) => b[k]).map((k) => `${k}: ${b[k]} (servidor)`)];
      return ok({ descarga_id: id, reporte: b.reporte, titulo: b.reporte, archivo: `${b.reporte}${ACEPTA[b.reporte].filter((k) => b[k]).map((k) => `_${b[k]}`).join("")}_${b.desde ?? "hoy"}_a_${b.hasta ?? "hoy"}_srv`, total, max: 50000, formato: b.formato,
        incluir_excluidos: !!b.incluir_excluidos, filtros: { desde: b.desde, hasta: b.hasta }, columnas: COLS[b.reporte],
        leame: { que_trae: [`ZT qué trae ${b.reporte} (servidor).`, "Segunda línea del servidor."], que_no_trae: ["ZT sin textos libres (servidor)."], filtros: filtrosTxt,
          generado_por: "supervisor.zt@emdupar.gov.co", generado_en: "2026-11-20T10:31:05" } });
    }
    if (accion === "reporte_pagina") {
      const d = descargas.get(b.descarga_id); if (!d) return no(404, "La descarga no existe.");
      if (d.cerrada) return no(409, "La descarga ya terminó. Vuelva a iniciarla.");
      if (MODO.pagina === "falla" && d.entregadas > 0) return no(500, "Falla simulada a mitad de la descarga.");
      const desde = b.cursor === null ? 0 : Number(String(b.cursor).replace(/^zt:/, "")), hasta = Math.min(d.total, desde + Math.min(b.limite, 5000));
      const filas = []; for (let i = desde; i < hasta; i++) filas.push(fila(d.b.reporte, i, d.b));
      d.entregadas = hasta;
      return ok({ filas, devueltos: filas.length, cursor: hasta < d.total ? `zt:${hasta}` : null }, MODO.lento);
    }
    if (accion === "reporte_cerrar") { const d = descargas.get(b.descarga_id); const rep = !!d?.cerrada; if (d && !rep) d.cerrada = { filas: b.filas, resultado: b.resultado }; return ok({ descarga_id: b.descarga_id, cerrada: true, repetida: rep }); }
    return no(404, "Acción no soportada.");
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : f.endsWith(".png") ? "image/png" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, cond, d = "") => { total++; if (!cond) fallas++; console.log(`${cond ? "OK   " : "FALLA"} ${n}${cond ? "" : " " + d}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
const consola = []; const bloqueadas = [];
let ANCHO = 390, ALTO = 844, BAJADAS = "";
async function abrir(qs, pagina = "") {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  await pg.setRequestInterception(true);
  pg.on("request", (q) => { const u = q.url(); if (u.startsWith("http://127.0.0.1:") || u.startsWith("data:") || u.startsWith("blob:")) q.continue(); else { bloqueadas.push(u); q.abort(); } });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("ERROR de página:", String(e).slice(0, 200)); });
  pg.on("console", (m) => consola.push(m.text()));
  const cdp = await pg.createCDPSession(); await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: BAJADAS });
  await pg.goto(`${ORIGEN}/${pagina}?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(400);
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll(".tdash, .rep-tarjeta, .rem")].every((e) => e.scrollWidth <= e.clientWidth + 1));
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().startsWith(x) && !e.disabled); if (b) b.click(); return !!b; }, sel, t);
const pestana = (pg, t) => clicTexto(pg, "[role=tab]", t);
const tarjeta = (pg, clave) => pg.evaluate((k) => { const b = document.querySelector(`[data-reporte="${k}"] .rep-cab`); if (b && !b.disabled) b.click(); return !!b && !b.disabled; }, clave);
const enTarjeta = (pg, clave, t) => clicTexto(pg, `[data-reporte="${clave}"] button`, t);
const fijar = (pg, sel, v) => pg.evaluate((s, x) => { const e = document.querySelector(s); if (!e) return false; const set = Object.getOwnPropertyDescriptor(e.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype, "value").set;
  set.call(e, x); e.dispatchEvent(new Event(e.tagName === "SELECT" ? "change" : "input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); return true; }, sel, v);
const marcar = (pg, clave) => pg.evaluate((k) => { const e = document.querySelector(`[data-reporte="${k}"] input[type=checkbox]`); if (e && !e.checked) e.click(); return !!e; }, clave);
const avisoDe = (pg, clave) => pg.evaluate((k) => document.querySelector(`[data-reporte="${k}"] .td-aviso`)?.textContent ?? "", clave);
const esperarAviso = (pg, clave, ms = 30000) => pg.waitForFunction((k) => !!document.querySelector(`[data-reporte="${k}"] .td-aviso`), { timeout: ms }, clave).catch(() => {});
const opcionesDe = (pg, sel) => pg.evaluate((s) => [...document.querySelectorAll(`${s} option`)].map((o) => o.textContent), sel);
const rotulos = (pg, k) => pg.evaluate((x) => [...document.querySelectorAll(`[data-reporte="${x}"] label`)].map((l) => l.textContent.trim()), k);
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
const leameDe = (x) => Object.fromEntries((x?.leame ?? []).map(([a, b]) => [a, b ?? ""]));
const ultimaDescarga = (rep) => [...descargas.values()].filter((d) => d.b.reporte === rep).at(-1);
const pedidosDe = (acc, rep) => peticiones.filter((p) => p.accion === acc && (!rep || p.cuerpo?.reporte === rep));
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
  const ini = pedidosDe("reporte_iniciar", "entrada").at(-1), d1 = ultimaDescarga("entrada");
  ok(`${T} P5 a geoportal-tecnica va el pedido del contrato: reporte, formato, periodo, «incluir_excluidos» y la planta`,
     ini?.fn === "geoportal-tecnica" && JSON.stringify(ini?.cuerpo) === JSON.stringify({ reporte: "entrada", formato: "xlsx", desde: "2026-11-01", hasta: "2026-11-10", incluir_excluidos: true, planta: "ZT1" }), JSON.stringify(ini));
  const pags = pedidosDe("reporte_pagina").filter((p) => p.cuerpo.descarga_id === [...descargas.entries()].find(([, d]) => d === d1)?.[0]);
  ok(`${T} P6 páginas por cursor (null, luego el opaco), «Listo: 240 filas en Excel» y la auditoría se cierra con «completa» y 240`,
     pags.length === 1 && pags[0].cuerpo.cursor === null && pags[0].cuerpo.limite === 5000 && /Listo: 240 filas en Excel\. La descarga quedó registrada/.test(await avisoDe(pg, "entrada"))
     && d1?.cerrada?.resultado === "completa" && d1?.cerrada?.filas === 240, JSON.stringify([pags.map((p) => p.cuerpo), d1?.cerrada]));
  let x = f ? leerXlsx(f) : null;
  ok(`${T} P7 el archivo lleva el nombre que da el servidor (entrada_ZT1_2026-11-01_a_2026-11-10_srv.xlsx) y abre en openpyxl con las hojas «Entrada» y «Léame»`,
     !!f && f.endsWith("entrada_ZT1_2026-11-01_a_2026-11-10_srv.xlsx") && JSON.stringify(x?.hojas) === JSON.stringify(["Entrada", "Léame"]), f);
  ok(`${T} P8 las columnas en el orden del servidor y con la unidad: «Turbiedad de ingreso (Ti) (NTU)», «Caudal (L/s)», «Dosis (ppm)»; «pH» sin unidad`,
     !!x && x.enc.length === COLS.entrada.length && x.enc[0] === "Fecha y hora de la muestra" && ["Turbiedad de ingreso (Ti) (NTU)", "Color aparente (UPC)", "Caudal (L/s)", "pH", "Dosis (ppm)"].every((h) => x.enc.includes(h)), JSON.stringify(x?.enc));
  const ci = (h) => x.enc.indexOf(h);
  ok(`${T} P9 fecha y hora de Bogotá SIN zona como fecha de Excel tal cual (00:10, 00:12:30), números como números, un valor vacío queda vacío`,
     !!x && x.f1[0]?.dt === "2026-11-01 00:10:00" && x.fmt[0].startsWith("dd/mm/yyyy") && x.f1[ci("Registrado")]?.dt === "2026-11-01 00:12:30" && x.f2[0]?.dt === "2026-11-01 01:10:00"
     && x.f1[ci("Turbiedad de ingreso (Ti) (NTU)")] === 12.5 && x.f1[ci("Caudal (L/s)")] === 410.25 && x.f1[ci("pH")] === null && x.f2[ci("pH")] === 7.12 && x.f1[ci("Valores fuera de referencia")] === 1 && x.n === 240,
     JSON.stringify([x?.f1, x?.fmt]));
  let le = leameDe(x);
  ok(`${T} P10 «Léame» con las líneas del servidor (qué trae, qué no, filtros, quién y cuándo: 20/11/2026 10:31) y lo de la pantalla (filas, formato, auditoría)`,
     le["Qué trae"] === "ZT qué trae entrada (servidor).\nSegunda línea del servidor." && le["Lo que no va"] === "ZT sin textos libres (servidor)." && /planta: ZT1 \(servidor\)/.test(le["Filtros"])
     && le["Filas"] === "240" && le["Descargado por"] === "supervisor.zt@emdupar.gov.co" && le["Fecha y hora de la descarga (Bogotá)"] === "20/11/2026 10:31" && /Excel/.test(le["Formato"]) && !!le["Auditoría"], JSON.stringify(le));

  // Salida en CSV
  await tarjeta(pg, "salida"); await esp(200);
  const unaAbierta = await pg.evaluate(() => document.querySelectorAll(".rep-abierta").length === 1 && !!document.querySelector('[data-reporte="salida"].rep-abierta'));
  const conserva = await pg.evaluate(() => [document.querySelector("#rep-salida-desde")?.value, document.querySelector("#rep-salida-planta")?.value]);
  ok(`${T} P11 una tarjeta abierta a la vez; el periodo y la planta se conservan al pasar a otra`, unaAbierta && conserva[0] === "2026-11-01" && conserva[1] === "ZT1", JSON.stringify(conserva));
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "salida", "Descargar CSV"); await esperarAviso(pg, "salida");
  f = await archivoNuevo(antes, ".csv");
  const csv = f ? readFileSync(f, "utf8") : ""; const lineas = csv.split("\r\n");
  ok(`${T} P12 el CSV: BOM, «;», unidad en el encabezado, coma decimal, fechas «dd/mm/aaaa hh:mm», 20 filas; el pedido dice «csv»`, csv.startsWith("﻿") && lineas[0].includes("Cloro residual (mg/L)") && lineas[0].split(";").length === COLS.salida.length
     && /;1,35;/.test(lineas[1]) && lineas[1].startsWith("01/11/2026 00:10;") && lineas.filter(Boolean).length === 21 && pedidosDe("reporte_iniciar", "salida").at(-1)?.cuerpo?.formato === "csv", lineas.slice(0, 2).join(" | "));

  // Muestreo: punto y zona (sin planta)
  await tarjeta(pg, "muestreo"); await esp(150);
  const fm = await rotulos(pg, "muestreo");
  ok(`${T} P13 Muestreo: filtros «Punto» (solo los activos) y «Zona», sin «Planta»`, fm.includes("Punto") && fm.includes("Zona") && !fm.includes("Planta")
     && JSON.stringify(await opcionesDe(pg, "#rep-muestreo-punto")) === JSON.stringify(["Todos los puntos", "ZT-P1 · ZT Punto Uno"]) && JSON.stringify(await opcionesDe(pg, "#rep-muestreo-zona")) === JSON.stringify(["Todas las zonas", "Norte", "Sur"]), JSON.stringify(fm));
  await fijar(pg, "#rep-muestreo-zona", "sur"); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "muestreo", "Descargar Excel"); await esperarAviso(pg, "muestreo");
  ok(`${T} P14 Muestreo pide solo la zona (la planta elegida en otra tarjeta no se manda: el servidor la rechazaría)`, JSON.stringify(pedidosDe("reporte_iniciar", "muestreo").at(-1)?.cuerpo) === JSON.stringify({ reporte: "muestreo", formato: "xlsx", desde: "2026-11-01", hasta: "2026-11-10", incluir_excluidos: true, zona: "sur" })
     && /Listo: 20 filas/.test(await avisoDe(pg, "muestreo")), await avisoDe(pg, "muestreo"));

  // Uso de químicos: planta y químico; sin «Incluir…»
  await tarjeta(pg, "uso_quimicos"); await esp(150);
  const fu = await rotulos(pg, "uso_quimicos");
  ok(`${T} P15 Uso de químicos: «Planta» y «Químico» (solo los activos, de la pestaña Químicos); sin la casilla «Incluir…» (no aplica)`, fu.includes("Planta") && fu.includes("Químico") && !fu.some((l) => l.startsWith("Incluir"))
     && JSON.stringify(await opcionesDe(pg, "#rep-uso_quimicos-quimico")) === JSON.stringify(["Todos los químicos", "ZT PAC", "ZT Cloro gaseoso"]), JSON.stringify(fu));
  await fijar(pg, "#rep-uso_quimicos-quimico", "pac");
  await enTarjeta(pg, "uso_quimicos", "Descargar CSV"); await esperarAviso(pg, "uso_quimicos");
  ok(`${T} P16 el pedido no lleva «incluir_excluidos» y sí planta y químico`, JSON.stringify(pedidosDe("reporte_iniciar", "uso_quimicos").at(-1)?.cuerpo) === JSON.stringify({ reporte: "uso_quimicos", formato: "csv", desde: "2026-11-01", hasta: "2026-11-10", planta: "ZT1", quimico: "pac" })
     && /Listo/.test(await avisoDe(pg, "uso_quimicos")), await avisoDe(pg, "uso_quimicos"));

  // Entrada de químicos: el vínculo «Ver foto» a remision.html
  await tarjeta(pg, "entrada_quimicos"); await esp(150); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada_quimicos", "Descargar Excel"); await esperarAviso(pg, "entrada_quimicos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const enl = x?.enl ?? [], cf = x ? x.enc.indexOf("Foto de la remisión") : -1;
  ok(`${T} P17 Entrada de químicos: «Ver foto» es un hipervínculo a remision.html?movimiento=N (el número que manda el servidor); sin foto, la celda queda vacía`,
     enl.length === 2 && enl[0][1] === `${ORIGEN}/remision.html?movimiento=7` && enl[0][2] === "Ver foto" && enl[1][1] === `${ORIGEN}/remision.html?movimiento=9` && x.f2[cf] === null, JSON.stringify([enl, x?.f2?.[cf]]));
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada_quimicos", "Descargar CSV"); await esperarAviso(pg, "entrada_quimicos");
  f = await archivoNuevo(antes, ".csv");
  ok(`${T} P18 en el CSV la columna de la foto trae la dirección de la página`, !!f && readFileSync(f, "utf8").split("\r\n")[1].includes(`;${ORIGEN}/remision.html?movimiento=7;`), f);

  // Kardex: saldo corrido; filas de saldo sin movimiento
  await tarjeta(pg, "kardex_quimicos"); await esp(150); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "kardex_quimicos", "Descargar Excel"); await esperarAviso(pg, "kardex_quimicos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  ok(`${T} P19 Kardex: «Saldo (kg)», la fila «Saldo inicial» sin movimiento, la fecha como fecha de Excel, celdas vacías donde no hay entrada`,
     !!x && x.enc.includes("Saldo (kg)") && x.f1[x.enc.indexOf("Tipo")] === "Saldo inicial" && x.f1[x.enc.indexOf("Movimiento")] === null && x.f1[x.enc.indexOf("Día")]?.dt === "2026-11-01 00:00:00"
     && x.fmt[x.enc.indexOf("Día")] === "dd/mm/yyyy" && x.f1[x.enc.indexOf("Saldo (kg)")] === 5000 && x.f2[x.enc.indexOf("Entra (kg)")] === null && x.n === 10, JSON.stringify(x?.f1));

  // Periodo: más de un año, y «hasta» antes de «desde»: no se pide nada
  await tarjeta(pg, "eventos_planta"); await esp(150);
  ok(`${T} P20 Eventos de planta: «Incluir los anulados»`, (await rotulos(pg, "eventos_planta")).some((l) => l.includes("Incluir los anulados")));
  let n0 = peticiones.length;
  await fijar(pg, "#rep-eventos_planta-desde", "2025-01-01"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-10");
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esp(300);
  ok(`${T} P21 un periodo de más de un año: «hasta un año por descarga» y no se pide nada`, /Acórtelo: hasta un año por descarga/.test(await avisoDe(pg, "eventos_planta")) && peticiones.length === n0);
  await fijar(pg, "#rep-eventos_planta-desde", "2026-11-10"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-01");
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esp(300);
  ok(`${T} P22 «hasta» antes de «desde»: lo dice y no pide nada`, /«Hasta» no puede ser antes de «desde»/.test(await avisoDe(pg, "eventos_planta")) && peticiones.length === n0);
  await fijar(pg, "#rep-eventos_planta-desde", "2025-11-11"); await fijar(pg, "#rep-eventos_planta-hasta", "2026-11-10");     // 365 días justos: se acepta
  MODO.iniciar = "cero"; antes = readdirSync(BAJADAS); const c0 = pedidosDe("reporte_cerrar").length;
  await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esperarAviso(pg, "eventos_planta"); await esp(300);
  ok(`${T} P23 un año justo se acepta; sin datos (404): «No hay datos con esos filtros. No se generó el archivo.», sin archivo y sin «cerrar» (no se abrió descarga)`,
     /No hay datos con esos filtros\. No se generó el archivo/.test(await avisoDe(pg, "eventos_planta")) && readdirSync(BAJADAS).length === antes.length && pedidosDe("reporte_cerrar").length === c0, await avisoDe(pg, "eventos_planta"));
  MODO.iniciar = 403; await enTarjeta(pg, "eventos_planta", "Descargar Excel"); await esperarAviso(pg, "eventos_planta"); await esp(200);
  ok(`${T} P24 403: «Solo el supervisor de planta o el administrador descargan reportes.»`, /Solo el supervisor de planta o el administrador descargan reportes/.test(await avisoDe(pg, "eventos_planta")));
  MODO.iniciar = null;

  // Más del tope (400 del servidor), falla a mitad y cancelar
  await tarjeta(pg, "entrada"); await esp(150);
  await fijar(pg, "#rep-entrada-desde", "2025-11-11"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10"); await fijar(pg, "#rep-entrada-planta", "");
  MODO.iniciar = "tope"; antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada", "Descargar Excel"); await pg.waitForFunction(() => /supera el máximo/.test(document.querySelector('[data-reporte="entrada"] .td-aviso')?.textContent ?? ""), { timeout: 10000 }).catch(() => {});
  ok(`${T} P25 más del tope (400): el texto del servidor tal cual («…supera el máximo de 50.000 filas… Acote el periodo o los filtros.»), como error y sin archivo`,
     /supera el máximo de 50\.000 filas \(hay 61200\)\. Acote el periodo o los filtros\./.test(await avisoDe(pg, "entrada")) && await pg.evaluate(() => !!document.querySelector('[data-reporte="entrada"] .td-aviso-error'))
     && readdirSync(BAJADAS).length === antes.length, await avisoDe(pg, "entrada"));
  MODO.iniciar = null;
  await fijar(pg, "#rep-entrada-desde", "2026-01-01"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10"); await fijar(pg, "#rep-entrada-planta", "ZT1");
  MODO.pagina = "falla"; antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "entrada", "Descargar Excel"); await pg.waitForFunction(() => /Falla simulada/.test(document.querySelector('[data-reporte="entrada"] .td-aviso')?.textContent ?? ""), { timeout: 20000 }).catch(() => {}); await esp(300);
  let dfa = ultimaDescarga("entrada");
  ok(`${T} P26 si una página falla a mitad: el error en pantalla, sin archivo, y la auditoría se cierra con «error» y las filas que alcanzaron a llegar`,
     /Falla simulada/.test(await avisoDe(pg, "entrada")) && readdirSync(BAJADAS).length === antes.length && dfa?.cerrada?.resultado === "error" && dfa?.cerrada?.filas === 5000, JSON.stringify(dfa?.cerrada));
  MODO.pagina = null; MODO.lento = 700;
  await enTarjeta(pg, "entrada", "Descargar Excel");
  await pg.waitForFunction(() => /Descargando [\d.]+ de [\d.]+ filas/.test(document.querySelector('[data-reporte="entrada"] .rep-progreso')?.textContent ?? ""), { timeout: 8000 }).catch(() => {});
  const prog = await pg.evaluate(() => ({ t: document.querySelector('[data-reporte="entrada"] .rep-progreso')?.textContent ?? "", otras: [...document.querySelectorAll(".rep-tarjeta:not(.rep-abierta) .rep-cab")].every((b) => b.disabled) }));
  ok(`${T} P27 mientras descarga: «Descargando 5.000 de 7.536 filas…» con «Cancelar», y las demás tarjetas no se abren`, /Descargando 5\.000 de 7\.536 filas/.test(prog.t) && /Cancelar/.test(prog.t) && prog.otras, JSON.stringify(prog));
  await pg.screenshot({ path: join(CAP, `despues_ptap_descargando_${ancho}.png`) });
  await clicTexto(pg, '[data-reporte="entrada"] .rep-progreso button', "Cancelar"); await pg.waitForFunction(() => /cancelada/.test(document.querySelector('[data-reporte="entrada"] .td-aviso')?.textContent ?? ""), { timeout: 8000 }).catch(() => {}); await esp(1200);
  let dca = ultimaDescarga("entrada");
  ok(`${T} P28 cancelar: «Descarga cancelada», sin archivo, la auditoría se cierra con «cancelada»; las tarjetas se vuelven a abrir`, /Descarga cancelada/.test(await avisoDe(pg, "entrada"))
     && dca?.cerrada?.resultado === "cancelada" && readdirSync(BAJADAS).length === antes.length && await pg.evaluate(() => [...document.querySelectorAll(".rep-cab")].every((b) => !b.disabled)), JSON.stringify(dca?.cerrada));
  MODO.lento = 0;

  // Un año de Entrada, las tres plantas: 26.280 filas en 6 páginas
  await fijar(pg, "#rep-entrada-desde", "2025-11-11"); await fijar(pg, "#rep-entrada-hasta", "2026-11-10"); await fijar(pg, "#rep-entrada-planta", "");
  antes = readdirSync(BAJADAS); let t0 = Date.now(); const p0 = pedidosDe("reporte_pagina").length;
  await enTarjeta(pg, "entrada", "Descargar Excel"); await pg.waitForFunction(() => /Listo/.test(document.querySelector('[data-reporte="entrada"] .td-aviso')?.textContent ?? ""), { timeout: 120000 }).catch(() => {});
  f = await archivoNuevo(antes, ".xlsx", 60000); let ms = Date.now() - t0;
  x = f ? leerXlsx(f) : null;
  tiempos.push(`[${ancho}] Entrada, un año y tres plantas: 26.280 filas, ${f ? (statSync(f).size / 1024 / 1024).toFixed(1) : "?"} MB, ${(ms / 1000).toFixed(1)} s (servidor simulado local)`);
  ok(`${T} P29 un año de Entrada (26.280 filas) en 6 páginas de 5.000: el Excel abre con todas las filas (${(ms / 1000).toFixed(1)} s)`, x?.n === 26280 && pedidosDe("reporte_pagina").length - p0 === 6
     && /Listo: 26\.280 filas/.test(await avisoDe(pg, "entrada")), `${x?.n} ${pedidosDe("reporte_pagina").length - p0}`);
  ok(`${T} P30 la pestaña Reportes no desborda`, await sinDesborde(pg));
  await pg.close();

  // Sin la lista de químicos: el filtro queda en «Todos» y lo dice
  MODO.quimicos = "falla"; pg = await abrir("p=ptap"); await pestana(pg, "Reportes"); await pg.waitForSelector(".rep-tarjeta", { timeout: 8000 }).catch(() => {});
  await tarjeta(pg, "kardex_quimicos"); await esp(200);
  const sinQ = await pg.evaluate(() => ({ ops: [...document.querySelectorAll("#rep-kardex_quimicos-quimico option")].map((o) => o.textContent), txt: document.querySelector('[data-reporte="kardex_quimicos"]').textContent }));
  ok(`${T} P31 si la lista de químicos no carga: solo «Todos los químicos» y el aviso; la descarga sigue disponible`,
     JSON.stringify(sinQ.ops) === JSON.stringify(["Todos los químicos"]) && /No se pudo cargar la lista «Químico»: se descarga sin ese filtro/.test(sinQ.txt) && /Descargar Excel/.test(sinQ.txt), JSON.stringify(sinQ));
  MODO.quimicos = "ok"; await pg.close();

  // ===================== Distribución =====================
  pg = await abrir("p=dist");
  await pestana(pg, "Descargas"); await pg.waitForSelector(".rep-tarjeta", { timeout: 8000 }).catch(() => {});
  const nd = await pg.evaluate(() => [...document.querySelectorAll(".rep-tarjeta .rep-nom")].map((e) => e.textContent));
  ok(`${T} D1 Descargas: nueve tarjetas, en el orden del encargo`, JSON.stringify(nd) === JSON.stringify(["Daños y fallas", "Intervenciones", "Encontrar o reportar activo", "Válvulas cerradas", "Eventos de suspensión", "Línea 116",
    "Reportes del bot", "Usuarios sensibles", "Activos de la red"]), JSON.stringify(nd));
  const colD = await pg.evaluate(() => { const t = document.querySelector(".rep-tarjeta"); return [getComputedStyle(t).borderLeftColor, getComputedStyle(t.querySelector(".rep-ini")).backgroundColor]; });
  ok(`${T} D2 la misma tarjeta, con el verde de distribución (#0f3d2b)`, colD.every((v) => v === "rgb(15, 61, 43)"), JSON.stringify(colD));
  await pg.screenshot({ path: join(CAP, `despues_descargas_${ancho}.png`), fullPage: true });

  // Daños y fallas: la ruta de siempre, ahora también en CSV
  await tarjeta(pg, "danos"); await esp(150);
  await fijar(pg, "#dsc-danos-desde", "2026-11-01"); await fijar(pg, "#dsc-danos-hasta", "2026-11-10"); await marcar(pg, "danos");
  antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "danos", "Descargar Excel"); await esperarAviso(pg, "danos");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const pd = peticiones.filter((p) => p.accion === "descarga").at(-1)?.cuerpo;
  const led = leameDe(x);
  ok(`${T} D3 Daños y fallas sigue por su ruta «descarga» (con los ocultos), con sus columnas de siempre; el «Léame» conserva «Lo que no va» y la nota del tipo de activo`,
     JSON.stringify(pd) === JSON.stringify({ conjunto: "danos", desde: "2026-11-01", hasta: "2026-11-10", incluir_ocultos: true }) && x?.hojas[0] === "Daños y fallas" && x.enc[0] === "Código" && x.enc.includes("Tipo de activo (nombre visible)")
     && x.n === 3 && x.f1[x.enc.indexOf("Detectado")]?.dt === "2026-11-01 10:00:00" && /placa del tercero/.test(led["Lo que no va"]) && /prefijo no cambia/.test(led["Tipo de activo"] ?? "")
     && /Listo: 3 filas en Excel/.test(await avisoDe(pg, "danos")) && f.endsWith("danos_fallas_2026-11-01_a_2026-11-10.xlsx"), JSON.stringify([pd, x?.enc?.slice(0, 3), led["Tipo de activo"]]));
  antes = readdirSync(BAJADAS);
  await tarjeta(pg, "intervenciones"); await esp(150); await enTarjeta(pg, "intervenciones", "Descargar CSV"); await esperarAviso(pg, "intervenciones");
  f = await archivoNuevo(antes, ".csv"); const ci2 = f ? readFileSync(f, "utf8").split("\r\n") : [];
  ok(`${T} D4 Intervenciones ahora también en CSV («Resuelve el daño» = Sí, «Valor total» sin separador de miles)`, ci2[0]?.startsWith("﻿Código;Nace de;") && /;Sí;/.test(ci2[1] ?? "") && /;350000;/.test(ci2[1] ?? ""), ci2.slice(0, 2).join(" | "));

  // Válvulas cerradas: sector escrito; sin «Incluir…» (no aplica)
  await tarjeta(pg, "valvulas"); await esp(150);
  const fv = await rotulos(pg, "valvulas");
  ok(`${T} D5 Válvulas cerradas: el sector se escribe (número; vacío = todos); sin la casilla «Incluir…»`, fv.includes("Sector") && !fv.some((l) => l.startsWith("Incluir"))
     && await pg.evaluate(() => { const e = document.querySelector("#dsc-valvulas-sector"); return e?.getAttribute("inputmode") === "numeric" && e.placeholder === "Todos"; }), JSON.stringify(fv));
  await pg.type("#dsc-valvulas-sector", "5a"); antes = readdirSync(BAJADAS);
  const escrito = await pg.evaluate(() => document.querySelector("#dsc-valvulas-sector").value);
  await enTarjeta(pg, "valvulas", "Descargar Excel"); await esperarAviso(pg, "valvulas");
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  const pv = pedidosDe("reporte_iniciar", "valvulas").at(-1);
  ok(`${T} D6 solo deja números («5a» queda «5»); va a geoportal-redes como texto «5», sin «incluir_excluidos»; «Duración (h)»`, escrito === "5" && pv?.fn === "geoportal-redes"
     && JSON.stringify(pv?.cuerpo) === JSON.stringify({ reporte: "valvulas", formato: "xlsx", desde: "2026-11-01", hasta: "2026-11-10", sector: "5" }) && x?.enc.includes("Duración (h)") && x?.f1[x.enc.indexOf("Sector")] === 5, JSON.stringify(pv));

  // Usuarios sensibles: inventario a hoy, con su tipo
  await tarjeta(pg, "sensibles"); await esp(150);
  const sinPer = await pg.evaluate(() => { const t = document.querySelector('[data-reporte="sensibles"]'); return { fechas: t.querySelectorAll("input[type=date]").length, txt: t.textContent }; });
  ok(`${T} D7 Usuarios sensibles: sin periodo («Es el inventario de hoy»), filtro «Tipo» con hospital, clínica, colegio, sede propia y otro; «Incluir los descartados»`,
     sinPer.fechas === 0 && /Es el inventario de hoy/.test(sinPer.txt) && /Incluir los descartados/.test(sinPer.txt)
     && JSON.stringify(await opcionesDe(pg, "#dsc-sensibles-tipo")) === JSON.stringify(["Todos los tipos", "Hospital", "Clínica o centro de salud", "Colegio", "Sede propia", "Otro"]), sinPer.txt);
  await fijar(pg, "#dsc-sensibles-tipo", "hospital"); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "sensibles", "Descargar CSV"); await esperarAviso(pg, "sensibles");
  f = await archivoNuevo(antes, ".csv"); const ps = pedidosDe("reporte_iniciar", "sensibles").at(-1)?.cuerpo;
  ok(`${T} D8 el pedido no lleva fechas ni el sector de otra tarjeta: solo el tipo; 37 filas`, JSON.stringify(ps) === JSON.stringify({ reporte: "sensibles", formato: "csv", incluir_excluidos: true, tipo: "hospital" })
     && !!f && readFileSync(f, "utf8").split("\r\n").filter(Boolean).length === 38, JSON.stringify([ps, f]));

  // Activos de la red: tipo (prefijo) y sistema; todo el inventario (35.781 filas)
  await tarjeta(pg, "activos"); await esp(150);
  const fa = await rotulos(pg, "activos");
  const tiposOp = await opcionesDe(pg, "#dsc-activos-tipo");
  ok(`${T} D9 Activos de la red: «Tipo de activo» (del catálogo de redes, solo los activos, con su prefijo), «Sistema» e «Incluir los retirados y ocultos»`, fa.includes("Tipo de activo") && fa.includes("Sistema")
     && fa.some((l) => l.includes("Incluir los retirados y ocultos")) && JSON.stringify(tiposOp) === JSON.stringify(["Todos los tipos", "Hidrante (HID)", "Válvula (VAL)"]), JSON.stringify([fa, tiposOp]));
  // el tipo de Usuarios sensibles («hospital») no es una opción de Activos: el select no lo muestra y no se manda
  await fijar(pg, "#dsc-activos-tipo", "HID"); await fijar(pg, "#dsc-activos-sistema", "acueducto"); antes = readdirSync(BAJADAS);
  await enTarjeta(pg, "activos", "Descargar Excel"); await esperarAviso(pg, "activos", 60000);
  f = await archivoNuevo(antes, ".xlsx"); x = f ? leerXlsx(f) : null;
  ok(`${T} D10 por tipo y sistema: «Hidrante», 4.210 filas; el pedido lleva tipo «HID» y sistema`, x?.n === 4210 && x.f1[1] === "Hidrante"
     && JSON.stringify(pedidosDe("reporte_iniciar", "activos").at(-1)?.cuerpo) === JSON.stringify({ reporte: "activos", formato: "xlsx", incluir_excluidos: true, tipo: "HID", sistema: "acueducto" }), f);
  await fijar(pg, "#dsc-activos-tipo", ""); await fijar(pg, "#dsc-activos-sistema", ""); antes = readdirSync(BAJADAS); t0 = Date.now();
  await enTarjeta(pg, "activos", "Descargar Excel"); await pg.waitForFunction(() => /Listo: 35/.test(document.querySelector('[data-reporte="activos"] .td-aviso')?.textContent ?? ""), { timeout: 120000 }).catch(() => {});
  f = await archivoNuevo(antes, ".xlsx", 60000); ms = Date.now() - t0; x = f ? leerXlsx(f) : null;
  tiempos.push(`[${ancho}] Activos de la red, todo el inventario: 35.781 filas, ${f ? (statSync(f).size / 1024 / 1024).toFixed(1) : "?"} MB, ${(ms / 1000).toFixed(1)} s (servidor simulado local)`);
  ok(`${T} D11 todo el inventario (35.781 filas, 8 páginas) abre completo (${(ms / 1000).toFixed(1)} s)`, x?.n === 35781, `${x?.n} ${await avisoDe(pg, "activos")} ${JSON.stringify(pedidosDe("reporte_iniciar", "activos").at(-1))}`);

  // Eventos de suspensión, Línea 116, Reportes del bot y Encontrar: cada uno con su clave del contrato y su archivo
  for (const [k, ext, n, ocu] of [["eventos", ".xlsx", 10, "Incluir los anulados"], ["l116", ".csv", 10, "Incluir los ocultos"], ["bot", ".xlsx", 10, "Incluir los descartados"], ["levantamientos", ".csv", 10, "Incluir los descartados"]]) {
    await tarjeta(pg, k); await esp(150); await fijar(pg, `#dsc-${k}-desde`, "2026-11-01"); await fijar(pg, `#dsc-${k}-hasta`, "2026-11-10"); await fijar(pg, `#dsc-${k}-sector`, "6");
    antes = readdirSync(BAJADAS);
    await enTarjeta(pg, k, ext === ".xlsx" ? "Descargar Excel" : "Descargar CSV"); await esperarAviso(pg, k);
    f = await archivoNuevo(antes, ext);
    const filas = !f ? -1 : ext === ".xlsx" ? leerXlsx(f).n : readFileSync(f, "utf8").split("\r\n").filter(Boolean).length - 1;
    const pk = pedidosDe("reporte_iniciar", k).at(-1);
    ok(`${T} D12 ${k}: «${ocu}», pedido a geoportal-redes con el sector «6», ${n} filas en ${ext}, auditoría cerrada`, filas === n && pk?.fn === "geoportal-redes" && pk?.cuerpo?.sector === "6"
       && (await rotulos(pg, k)).some((l) => l.includes(ocu)) && ultimaDescarga(k)?.cerrada?.resultado === "completa", `${f} ${filas} ${await avisoDe(pg, k)}`);
    if (k === "eventos") {
      const xe = leerXlsx(f);
      ok(`${T} D13 eventos: contratos y sensibles afectados como números; «Fin» vacío`, xe.f1[xe.enc.indexOf("Contratos afectados")] === 1520 && xe.f1[xe.enc.indexOf("Usuarios sensibles afectados")] === 3
         && xe.f1[xe.enc.indexOf("Fin")] === null, JSON.stringify(xe.f1));
    }
  }
  await fijar(pg, "#dsc-levantamientos-sector", ""); await pg.type("#dsc-levantamientos-sector", "12345");
  ok(`${T} D14 el sector admite hasta 4 cifras`, (await pg.evaluate(() => document.querySelector("#dsc-levantamientos-sector").value)) === "1234");
  ok(`${T} D15 Descargas no desborda`, await sinDesborde(pg));
  await pg.screenshot({ path: join(CAP, `despues_descargas_abierta_${ancho}.png`), fullPage: true });
  ok(`${T} D16 ningún pedido de reportes fue rechazado por el servidor simulado (filtros y claves del contrato)`, !peticiones.some((p) => p.accion === "reporte_iniciar" && p.rechazo && !/supera el máximo/.test(p.rechazo)),
     JSON.stringify(peticiones.filter((p) => p.rechazo).map((p) => [p.cuerpo, p.rechazo])));
  await pg.close();

  // ===================== remision.html (el vínculo «Ver foto») =====================
  if (conRemision) {
    pg = await abrir("movimiento=7", "remision.html");
    await pg.waitForSelector(".rem-foto", { timeout: 8000 }).catch(() => {});
    const rf = await pg.evaluate(() => { const i = document.querySelector(".rem-foto"); return { src: i?.getAttribute("src"), carga: !!i && i.complete && i.naturalWidth > 0, txt: document.body.innerText,
      boton: Math.min(...[...document.querySelectorAll(".rem-boton, .rem-boton-sec")].map((b) => b.getBoundingClientRect().height)), cab: getComputedStyle(document.querySelector(".rem-cab")).backgroundColor }; });
    const pf = peticiones.filter((p) => p.accion === "reporte_remision_foto").at(-1);
    ok(`${T} R1 remision.html?movimiento=7: pide reporte_remision_foto (GET, movimiento 7) y muestra la foto firmada; botones de 44 px; encabezado de Plantas`,
       pf?.fn === "geoportal-tecnica" && pf?.qs?.movimiento === "7" && rf.carga && /foto_zt\.png\?firma=zt/.test(rf.src ?? "") && /Movimiento 7/.test(rf.txt) && /dura 60 segundos/.test(rf.txt) && rf.boton >= 44 && rf.cab === "rgb(10, 37, 64)", JSON.stringify(rf));
    ok(`${T} R2 la página de la foto no desborda`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `despues_remision_${ancho}.png`), fullPage: true }); await pg.close();
    pg = await abrir("movimiento=404", "remision.html"); await pg.waitForSelector(".rem-aviso", { timeout: 8000 }).catch(() => {});
    ok(`${T} R3 sin foto (404): el texto del servidor y «Reintentar»`, /Ese movimiento no tiene foto de la remisión/.test(await texto(pg)) && /Reintentar/.test(await texto(pg)) && !(await pg.$(".rem-foto"))); await pg.close();
    const nf0 = peticiones.filter((p) => p.accion === "reporte_remision_foto").length;
    pg = await abrir("movimiento=7&sinsesion=1", "remision.html"); await pg.waitForSelector(".rem-aviso", { timeout: 8000 }).catch(() => {});
    ok(`${T} R4 sin sesión: «inicie sesión en el geoportal…», «Ir al geoportal», y no pide nada`, /inicie sesión en el geoportal en este navegador/.test(await texto(pg)) && /Ir al geoportal/.test(await texto(pg))
       && peticiones.filter((p) => p.accion === "reporte_remision_foto").length === nf0);
    await pg.screenshot({ path: join(CAP, `despues_remision_sin_sesion_${ancho}.png`) }); await pg.close();
    MODO.foto = 403; pg = await abrir("movimiento=7", "remision.html"); await pg.waitForSelector(".rem-aviso", { timeout: 8000 }).catch(() => {});
    ok(`${T} R5 sin permiso (403): «Solo el supervisor de planta o el administrador ven la foto de la remisión.»`, /Solo el supervisor de planta o el administrador ven la foto/.test(await texto(pg))); await pg.close(); MODO.foto = "ok";
    pg = await abrir("movimiento=7x", "remision.html"); await esp(300);
    ok(`${T} R6 un movimiento que no es número: lo dice y no pide nada`, /no trae un número de movimiento válido/.test(await texto(pg))); await pg.close();
  }
}
if (!SOLO_ANTES) {
  ok("Z1 ningún pedido lleva teléfonos ni nombres (solo códigos y fechas)", !peticiones.some((p) => /telefono|nombre_suscriptor|placa/i.test(JSON.stringify(p.cuerpo ?? {}))));
  ok("Z2 ninguna petición salió de la máquina", bloqueadas.length === 0, bloqueadas.slice(0, 3).join(" "));
  console.log("\nTiempos (armado en el navegador con un año de datos simulados):\n  " + tiempos.join("\n  "));
}
await nav.close(); srv.close(); estatico.close();
console.log(SOLO_ANTES ? `\nCapturas «antes» en ${CAP}` : `\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
