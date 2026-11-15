// Pasada 14/11 · prueba en CHROME REAL (puppeteer-core + el Chrome instalado, cámara simulada de Chrome) de las pantallas de Comercial tocadas, contra un servidor SIMULADO
// en 127.0.0.1 (nada llega a Supabase): «Reportar anomalía» y «Instalación de medidor» envían la hora de inicio; el rechazo por la hora del celular se recalcula; «Hora de inicio»
// del papel nace prellenada; «Instalación / Cambio» muestra u oculta el medidor retirado; «Supervisión y dashboard»: Catálogo, Parámetros y constancias de solo lectura para el
// supervisor, Personal (ver / editar / revertir) e Inicio y Duración en la lista. A 380 px y en escritorio.
//   node scripts/prueba_chrome_p14.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas]
// No prueba: la Edge ni la base reales, ni un celular físico (iOS/Android), ni la cámara ni el GPS reales.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

// Opciones de R como quedaron en la base viva (14/11): 6 campos me_r y mi_r.
const R_OPCIONES = [["r80", "R80"], ["r160", "R160"], ["r200", "R200"], ["r315", "R315"], ["r400", "R400 (o superior)"], ["no_legible", "No legible"]].map(([codigo, nombre]) => ({ codigo, nombre, activo: true }));
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_p14"));
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_p14.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 54981;

// ---------- 1. Paquete de la página (componentes reales; doble de supabase: la URL de funciones lleva el rol simulado) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_p14_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "sup";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/" + rol + "/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => { window.__subidas = (window.__subidas || 0) + 1; return { error: null }; } }) } };` }));
} };
const campo = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const TIPO_INST = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
  fotos_min: 0, fotos_max: 2, requiere_contrato: "no", genera_resultado: false, usa_consecutivo: true, causales: [], fotos: [],
  campos: [
    campo("inst_modalidad", "Instalación o cambio de medidor", "opcion", { obligatorio: true, seccion: "1. Datos básicos", opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor", activo: true }, { codigo: "cambio", nombre: "Cambio de medidor", activo: true }] }),
    campo("hora_inicio", "Hora de inicio", "dia_hora", { obligatorio: true, seccion: "1. Datos básicos" }),
    campo("hora_final", "Hora final", "dia_hora", { obligatorio: true, seccion: "1. Datos básicos" }),
    campo("me_lectura", "Medidor retirado · Lectura", "decimal", { obligatorio: true, seccion: "2. Medidor retirado", visible_si: { campo: "inst_modalidad", es: "cambio" }, minimo: 0, maximo: 99999999 }),
    campo("me_r", "Medidor retirado · R del medidor", "opcion", { obligatorio: true, seccion: "2. Medidor retirado", visible_si: { campo: "inst_modalidad", es: "cambio" }, opciones: R_OPCIONES }),
    campo("mi_r", "Medidor instalado · R del medidor", "opcion", { obligatorio: true, seccion: "7. Instalaciones y adecuaciones", opciones: R_OPCIONES }),
    campo("inst_lectura_remota", "Lectura remota", "opciones", { seccion: "7. Instalaciones y adecuaciones", opciones: [{ codigo: "remota", nombre: "Se instaló lectura remota", activo: true }, { codigo: "remota_pila", nombre: "Se instaló lectura remota con pila", activo: true }] }),
  ] };
const DEF = { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: false, supervisar: false, administrar_catalogo: false },
  limites: { max_fotos: 2, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
  grupos: [{ codigo: "danos", nombre: "Daños", orden: 1, activo: true, tipos: [{ codigo: "fuga", nombre: "Fuga visible", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] },
           { codigo: "perdidas_formatos", nombre: "Pérdidas", orden: 2, activo: true, tipos: [TIPO_INST] }] };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React, { Suspense } from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css";
    import { ReporteGeneral } from "./src/campo/ReporteGeneral.tsx"; import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx";
    import Revision from "./src/campo/dashboard/Revision.tsx";
    const def = ${JSON.stringify(DEF)};
    const q = new URLSearchParams(location.search), p = q.get("p"), raiz = createRoot(document.getElementById("raiz"));
    window.__abierto = new Date().toISOString();
    if (p === "rg") raiz.render(<ReporteGeneral def={def} correo="operario@emdupar.gov.co" onVolver={() => {}} onOtro={() => {}} />);
    else if (p === "fmt") raiz.render(<FormularioFormato def={def} tipo={def.grupos[1].tipos[0]} correo="operario@emdupar.gov.co" onVolver={() => {}} onOtro={() => {}} />);
    else raiz.render(<Revision correo={q.get("rol") === "adm" ? "admin@emdupar.gov.co" : "supervisor@emdupar.gov.co"} onVolver={() => {}} />);
    setTimeout(() => { window.__listo = true; }, 500);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor simulado ----------
const ahora = Date.now(), iso = (ms) => new Date(ms).toISOString();
const FORM_REV = (adm) => ({ perfil: adm ? "admin" : "supervisor", puede: { reportar: true, crear_desde_escritorio: true, supervisar: true, administrar_catalogo: adm },
  limites: { max_fotos: 2 }, zona: DEF.zona, estados: [{ codigo: "reportado", nombre: "Reportado", orden: 1, activo: true, exige_motivo: false, cambio_manual: false }],
  grupos: [{ codigo: "perdidas_formatos", nombre: "Pérdidas", orden: 1, activo: true, tipos: [{ ...TIPO_INST, subtipos: [] }] },
           { codigo: "cartera", nombre: "Cartera", orden: 2, activo: true, tipos: [{ codigo: "cambio_medidor", nombre: "Cambio de medidor", orden: 8, activo: false, subtipos: [] }] }],
  parametros: adm ? PARAMS : null, definiciones: [] });
const PARAMS = [{ clave: "max_fotos", valor: 2, unidad: "fotos", descripcion: "Fotos por reporte", minimo: 1, maximo: 10, actualizado_en: null, actualizado_por: null },
                { clave: "max_horas_inicio", valor: 12, unidad: "h", descripcion: "Horas máximas entre la apertura del formulario (hora del celular) y el registro; más antiguo se rechaza", minimo: 1, maximo: 72, actualizado_en: null, actualizado_por: null }];
const CONST = { texto: { version: 1, borrador: true, texto: "BORRADOR pendiente de jurídica." }, documentos: [{ documento: "instalacion_medidor", habilitado: false, copias_internas: ["supervisor@emdupar.gov.co"] }], cola: {}, fallos_ultimos_30_dias: 0 };
const fila = (n, conInicio) => ({ id: `00000000-0000-4000-8000-00000000000${n}`, seq: n, tipo: { codigo: "instalacion_medidor", nombre: "Instalación de medidor" }, grupo: { codigo: "perdidas_formatos", nombre: "Pérdidas" },
  subtipo: null, descripcion: "[PRUEBA]", contrato: null, contrato_verificado: null, lat: 10.46, lon: -73.25, precision_m: 5, riesgo_inmediato: false, origen: "campo", fuera_de_zona: false, autor: "op@emdupar.gov.co",
  registrado_en: iso(ahora - n * 3600e3), estado: "reportado", estado_desde: null, oculto: false, reporte_original_id: null, grupo_duplicados: null, tamano_grupo: null, n_fotos: 0,
  consecutivo: `IME-00000${n}`, resultado: null, causal: null, orden_trabajo_id: null, datos: {}, tiene_datos_sensibles: false,
  ...(conInicio ? { inicio_en: iso(ahora - n * 3600e3 - 30 * 60e3), inicio_origen: "dispositivo" } : { inicio_en: null, inicio_origen: null }) });
let eventos = [{ id: 7, persona: "ana@emdupar.gov.co", nombre: "Ana Prueba", tipo_evento: "asignar_formulario", formulario: "tipo:instalacion_medidor", formulario_nombre: "Instalación de medidor", cargo: null, motivo: null, autor: "admin@emdupar.gov.co", creado_en: iso(ahora - 86400e3), vigente: true },
               { id: 6, persona: "ana@emdupar.gov.co", nombre: "Ana Prueba", tipo_evento: "fijar_cargo", formulario: null, formulario_nombre: null, cargo: "Técnica de pérdidas", motivo: null, autor: "admin@emdupar.gov.co", creado_en: iso(ahora - 2 * 86400e3), vigente: true }];
const PERSONAS = [{ email: "ana@emdupar.gov.co", nombre: "Ana Prueba", perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: true, dashboard_acta: false }, cargo: "Técnica de pérdidas", formularios: ["tipo:instalacion_medidor"], sin_asignacion: false, ultimo_cambio: iso(ahora - 86400e3) },
                  { email: "beto.con.un.correo.bastante.largo@emdupar.gov.co", nombre: null, perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: false, dashboard_acta: false }, cargo: null, formularios: [], sin_asignacion: true, ultimo_cambio: null },
                  { email: "sup@emdupar.gov.co", nombre: "Sofía Supervisora", perfil: "supervisor", permisos: { campo: false, dashboard_campo: true, acta: false, dashboard_acta: false }, cargo: null, formularios: [], sin_asignacion: true, ultimo_cambio: null }];
const FORMS = [{ clave: "reporte_general", nombre: "Reportar anomalía", grupo: "Reportar anomalía" }, { clave: "tipo:instalacion_medidor", nombre: "Instalación de medidor", grupo: "Pérdidas" },
               { clave: "tipo:revision_previa", nombre: "Revisiones generales", grupo: "Facturación" }, { clave: "acta", nombre: "Reportar posible pérdida", grupo: "Reportar posible pérdida" }];
const peticiones = []; let rechazarHora = 0;
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (c) => (cuerpo += c)); q.on("end", () => {
    const u = new URL(q.url, "http://x"), rol = u.pathname.split("/")[1], adm = rol === "adm", accion = u.searchParams.get("accion");
    let b = null; try { b = cuerpo ? JSON.parse(cuerpo) : null; } catch { /* sin cuerpo */ }
    peticiones.push({ rol, accion, metodo: q.method, cuerpo: b, en: Date.now() });
    const ok = (x) => { r.writeHead(200, cab); r.end(JSON.stringify(x)); };
    const no = (s, m) => { r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    switch (accion) {
      case "config_constancia": return ok({ habilitado: false });
      case "preparar_subida": return ok({ reporte_id: "11111111-2222-4333-8444-555555555555", max_bytes_foto: 1572864, tipo_mime: "image/jpeg",
        fotos: Array.from({ length: b?.cantidad ?? 0 }, (_, i) => ({ orden: i + 1, ruta: `reportes/2026-11/11111111-2222-4333-8444-555555555555/${i + 1}.jpg`, url_subida: "x", token: "t" })) });
      case "crear":
        if (rechazarHora > 0) { rechazarHora--; return no(400, "La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden."); }
        return ok({ id: "11111111-2222-4333-8444-555555555555", registrado_en: iso(Date.now()), repetido: false, contrato_verificado: null, aviso_zona: false, consecutivo: "IME-000001" });
      case "formulario": return ok(u.searchParams.get("incluir_inactivos") === "1" ? FORM_REV(true) : FORM_REV(adm));
      case "reportes": return ok({ reportes: [fila(1, true), fila(2, false)], total: 2, siguiente: null, distancia_duplicados_m: 15 });
      case "indicadores": return ok({ total: 2, visibles: 2, ocultos: 0, corte: iso(ahora), filtros: {}, serie_recortada: false, por_dia: [], por_tipo: [], por_estado: [], revision: { revisados: 0, sin_revisar: 2, mediana_segundos: null, promedio_segundos: null, p90_segundos: null } });
      case "catalogo_lectura": return adm ? ok({ ...FORM_REV(true), solo_lectura: false, constancias: CONST }) : ok({ ...FORM_REV(false), parametros: PARAMS, solo_lectura: true, constancias: CONST });
      case "constancia_estado": return adm ? ok(CONST) : no(403, "No tiene permiso para esta acción.");
      case "personal": return ok({ puede_editar: adm, formularios: FORMS, personas: PERSONAS });
      case "historial_personal": return ok({ eventos: b?.persona ? eventos.filter((e) => e.persona === b.persona) : eventos, siguiente: null });
      case "personal_cambiar": if (!adm) return no(403, "No tiene permiso para esta acción.");
        eventos = [{ id: 100 + peticiones.length, persona: b.persona, nombre: null, tipo_evento: b.tipo, formulario: b.formulario ?? null, formulario_nombre: null, cargo: b.cargo ?? null, motivo: b.motivo ?? null, autor: "admin@emdupar.gov.co", creado_en: iso(Date.now()), vigente: true }, ...eventos];
        return ok({ id: 100, cambio: true });
      case "reporte": return ok({ reporte: fila(1, true), campos: [], fotos: [], eventos: [], cercanos: [], distancia_duplicados_m: 15 });
      default: return no(404, "Acción no soportada.");
    }
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + d}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"] });
const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
await nav.defaultBrowserContext().overridePermissions(ORIGEN, ["geolocation", "camera"]);
async function abrir(qs, ancho) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  await pg.setGeolocation({ latitude: 10.46, longitude: -73.25, accuracy: 8 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("ERROR de página:", String(e).slice(0, 200)); });
  pg.on("dialog", (d) => void d.accept());
  await pg.goto(`${ORIGEN}/?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(700);
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().startsWith(x) && !e.disabled); if (b) b.click(); return !!b; }, sel, t);
const crearDe = (desde) => peticiones.filter((p) => p.accion === "crear" && p.en >= desde);
async function enviarHasta(pg, desde, n = 1) {
  for (let i = 0; i < 6 && crearDe(desde).length < n; i++) { await clicTexto(pg, "button.campo-enviar", ""); await esp(700); }
}

try {
  for (const ancho of [380, 1280]) {
    // ===== Reportar anomalía: inicio del celular al abrir =====
    let desde = Date.now();
    let pg = await abrir("p=rg&rol=op", ancho);
    const abierto = await pg.evaluate(() => window.__abierto);
    await pg.select("#campo-grupo", "danos"); await esp(150); await pg.select("#campo-tipo", "fuga"); await esp(150);
    await clicTexto(pg, "button.campo-boton-foto", "📷 Tomar foto 1"); await pg.waitForSelector("button.campo-capturar:not([disabled])", { timeout: 10000 }); await esp(400);
    await pg.click("button.campo-capturar"); await esp(1500);
    await enviarHasta(pg, desde);
    let c = crearDe(desde).at(-1)?.cuerpo;
    ok(`[${ancho}] Reportar anomalía: «crear» lleva inicio_dispositivo del momento de abrir`, !!c && Math.abs(Date.parse(c.inicio_dispositivo) - Date.parse(abierto)) < 3000, JSON.stringify(c ?? {}).slice(0, 160));
    ok(`[${ancho}] Reportar anomalía: el inicio es anterior al envío`, !!c && Date.parse(c.inicio_dispositivo) <= crearDe(desde).at(-1).en);
    if (ancho === 380) await pg.screenshot({ path: join(CAP, "anomalia_380_guardado.png") });
    await pg.close();

    // ===== Instalación de medidor: prellenado, Instalación/Cambio, inicio y rechazo por la hora =====
    desde = Date.now();
    pg = await abrir("p=fmt&rol=op", ancho);
    const abierto2 = await pg.evaluate(() => window.__abierto);
    await pg.evaluate(() => document.querySelectorAll("details.campo-seccion").forEach((d) => { d.open = true; })); await esp(200);
    const hi = await pg.evaluate(() => [...document.querySelectorAll("input[type=datetime-local]")].map((i) => i.value));
    const esperado = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(abierto2)).reduce((o, x) => ({ ...o, [x.type]: x.value }), {});
    ok(`[${ancho}] «Hora de inicio» del papel nace con la hora de apertura (Bogotá) y la final vacía`, hi[0] === `${esperado.year}-${esperado.month}-${esperado.day}T${esperado.hour}:${esperado.minute}` && hi[1] === "", JSON.stringify(hi));
    let t = await texto(pg);
    ok(`[${ancho}] sin elegir Instalación o cambio, no aparece el medidor retirado`, !t.includes("Medidor retirado · Lectura"));
    const elegir = (cod) => pg.evaluate((c) => { const i = [...document.querySelectorAll("input[type=radio]")].find((x) => x.value === c && x.name.includes("inst_modalidad")) ?? [...document.querySelectorAll("input[type=radio]")].find((x) => x.value === c); if (i) i.click(); else { const s = [...document.querySelectorAll("select")].find((x) => [...x.options].some((o) => o.value === c)); if (s) { const set = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value").set; set.call(s, c); s.dispatchEvent(new Event("change", { bubbles: true })); } } }, cod);
    await elegir("cambio"); await esp(250); await pg.evaluate(() => document.querySelectorAll("details.campo-seccion").forEach((d) => { d.open = true; })); await esp(150);
    t = await texto(pg);
    ok(`[${ancho}] con «Cambio de medidor» aparecen los datos del medidor retirado (lectura y R)`, t.includes("Medidor retirado · Lectura") && t.includes("Medidor retirado · R del medidor"));
    if (ancho === 380) await pg.screenshot({ path: join(CAP, "instalacion_380_cambio.png"), fullPage: true });
    await elegir("instalacion"); await esp(250);
    t = await texto(pg);
    ok(`[${ancho}] con «Instalación de medidor» se ocultan`, !t.includes("Medidor retirado · Lectura"));
    // hora final anterior → aviso
    const ponerDT = (n, v) => pg.evaluate((i, val) => { const e = document.querySelectorAll("input[type=datetime-local]")[i]; const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; set.call(e, val); e.dispatchEvent(new Event("input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); }, n, v);
    await ponerDT(1, "2000-01-01T00:00"); await esp(200);
    ok(`[${ancho}] hora final anterior a la de inicio: aviso claro`, (await texto(pg)).includes("La hora final no puede ser anterior a la hora de inicio."));
    await ponerDT(1, "2099-01-01T00:00"); await esp(150);
    await elegir("r160"); await esp(150);
    rechazarHora = 1;
    await enviarHasta(pg, desde, 1);
    await esp(400);
    ok(`[${ancho}] el rechazo por la hora del celular se muestra con el texto de la base`, (await texto(pg)).includes("La hora de su celular está adelantada"));
    // la persona corrige la hora del celular (la atrasa 10 min) y vuelve a enviar
    await pg.evaluate(() => { const orig = Date.now.bind(Date); Date.now = () => orig() - 600000; });
    await enviarHasta(pg, desde, 2);
    const cs = crearDe(desde).map((p) => p.cuerpo);
    ok(`[${ancho}] Instalación: el primer «crear» lleva el inicio de la apertura`, cs.length >= 1 && Math.abs(Date.parse(cs[0].inicio_dispositivo) - Date.parse(abierto2)) < 3000, JSON.stringify(cs[0] ?? {}).slice(0, 200));
    ok(`[${ancho}] tras el rechazo y con el reloj corregido (−10 min), el segundo envío RECALCULA el inicio (hora corregida − tiempo transcurrido) y no manda el medidor retirado`,
      cs.length === 2 && Math.abs(Date.parse(cs[0].inicio_dispositivo) - Date.parse(cs[1].inicio_dispositivo) - 600000) < 3000 && !("me_lectura" in (cs[1].datos ?? {})) && cs[1].datos?.inst_modalidad === "instalacion",
      JSON.stringify(cs.map((x) => x.inicio_dispositivo)));
    ok(`[${ancho}] la hora de inicio del papel viaja en datos`, typeof cs.at(-1)?.datos?.hora_inicio === "string");
    ok(`[${ancho}] formularios sin desborde horizontal`, await sinDesborde(pg));
    await pg.close();

    // ===== Supervisión y dashboard · supervisor (solo lectura) =====
    pg = await abrir("p=rev&rol=sup", ancho);
    t = await texto(pg);
    ok(`[${ancho}] supervisor: pestañas Reportes, Indicadores, Catálogo, Parámetros y Personal`, ["Reportes", "Indicadores", "Catálogo", "Parámetros", "Personal"].every((x) => t.includes(x)));
    ok(`[${ancho}] lista: columnas Inicio y Duración, con «(celular)» y «30 min»; vacías en el reporte de antes`, t.includes("Inicio") && t.includes("Duración") && t.includes("(celular)") && t.includes("30 min"), t.slice(0, 300));
    if (ancho === 1280) await pg.screenshot({ path: join(CAP, "supervision_1280_lista.png") });
    await clicTexto(pg, "button.rv-tab", "Catálogo"); await esp(800);
    t = await texto(pg);
    ok(`[${ancho}] Catálogo del supervisor: aviso de solo lectura, ve lo desactivado (Cambio de medidor) y NO hay botones de edición`,
      t.includes("Solo el administrador puede editar el catálogo") && t.includes("Cambio de medidor") && t.includes("Desactivado") && !/Renombrar|\+ Agregar|Reactivar/.test(t));
    ok(`[${ancho}] constancias del supervisor: solo lectura (sin campos ni botones) y sin pedir la ruta de administración`,
      t.includes("Solo el administrador puede cambiar las constancias") && !(await pg.$(".constancia-admin textarea")) && !peticiones.some((p) => p.rol === "sup" && p.accion === "constancia_estado"));
    if (ancho === 380) await pg.screenshot({ path: join(CAP, "supervisor_380_catalogo.png"), fullPage: true });
    await clicTexto(pg, "button.rv-tab", "Parámetros"); await esp(500);
    t = await texto(pg);
    ok(`[${ancho}] Parámetros del supervisor: ve los valores (incluida la hora de inicio, 12 h) sin botón «Cambiar»`, t.includes("Solo el administrador puede cambiar los parámetros") && t.includes("max_horas_inicio") && !/Cambiar/.test(t.replace("Solo el administrador puede cambiar", "")));
    await clicTexto(pg, "button.rv-tab", "Personal"); await esp(800);
    t = await texto(pg);
    ok(`[${ancho}] Personal del supervisor: lista, cargo, formularios («Todos los activos» si no tiene) e historial; sin «Editar» ni «Revertir»`,
      t.includes("Solo el administrador puede editar") && t.includes("Ana Prueba") && t.includes("Técnica de pérdidas") && t.includes("Todos los activos (sin asignación)") && t.includes("Historial") && !/\bEditar\b|Revertir/.test(t.replace("Solo el administrador puede editar", "")));
    ok(`[${ancho}] supervisión sin desborde horizontal (correo largo incluido)`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `supervisor_${ancho}_personal.png`), fullPage: ancho === 380 });
    await pg.close();

    // ===== Supervisión y dashboard · administrador (edita y revierte) =====
    pg = await abrir("p=rev&rol=adm", ancho);
    await clicTexto(pg, "button.rv-tab", "Catálogo"); await esp(800);
    t = await texto(pg);
    ok(`[${ancho}] administrador: el Catálogo conserva sus botones de edición y la administración de constancias`, /Renombrar/.test(t) && !!(await pg.$(".constancia-admin textarea")));
    await clicTexto(pg, "button.rv-tab", "Parámetros"); await esp(400);
    ok(`[${ancho}] administrador: Parámetros con «Cambiar»`, /Cambiar/.test(await texto(pg)));
    await clicTexto(pg, "button.rv-tab", "Personal"); await esp(800);
    const antes = peticiones.length;
    await clicTexto(pg, ".rv-per-tarjeta button", "Editar"); await esp(300);
    await pg.evaluate(() => { const m = document.querySelector(".rv-modal"); const i = m.querySelector("input[type=text]"); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; set.call(i, "Técnica de pérdidas II"); i.dispatchEvent(new Event("input", { bubbles: true })); });
    await pg.evaluate(() => { const l = [...document.querySelectorAll(".rv-modal label.rv-check")]; l.find((x) => x.textContent.includes("Instalación de medidor")).querySelector("input").click(); l.find((x) => x.textContent.includes("Reportar posible pérdida")).querySelector("input").click(); }); await esp(200);
    ok(`[${ancho}] al quitar un formulario se pide el motivo y no se puede guardar sin él`, await pg.evaluate(() => !!document.querySelector(".rv-modal textarea") && [...document.querySelectorAll(".rv-modal button.rv-boton")].some((b) => b.disabled)));
    await pg.type(".rv-modal textarea", "Ya no hace instalaciones de medidor");
    if (ancho === 380) await pg.screenshot({ path: join(CAP, "admin_380_editar_personal.png") });
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await esp(900);
    const cambios = peticiones.slice(antes).filter((p) => p.accion === "personal_cambiar").map((p) => p.cuerpo);
    ok(`[${ancho}] Guardar envía cargo, asignación y retiro (con motivo) como tres cambios`,
      cambios.length === 3 && cambios.some((x) => x.tipo === "fijar_cargo" && x.cargo === "Técnica de pérdidas II") && cambios.some((x) => x.tipo === "asignar_formulario" && x.formulario === "acta")
      && cambios.some((x) => x.tipo === "quitar_formulario" && x.formulario === "tipo:instalacion_medidor" && x.motivo === "Ya no hace instalaciones de medidor"), JSON.stringify(cambios));
    ok(`[${ancho}] aviso de cambios guardados`, (await texto(pg)).includes("Cambios guardados"));
    const antes2 = peticiones.length;
    const hayRev = await clicTexto(pg, ".rv-per-evento button", "Revertir"); await esp(300);
    ok(`[${ancho}] el historial ofrece «Revertir» al administrador`, hayRev);
    await clicTexto(pg, ".rv-modal button.rv-boton", "Revertir"); await esp(700);
    const rev = peticiones.slice(antes2).find((p) => p.accion === "personal_cambiar")?.cuerpo;
    ok(`[${ancho}] Revertir envía el cambio inverso (con «Reversión del cambio n.º …» si es un retiro)`, !!rev && (rev.tipo === "asignar_formulario" || /^Reversión del cambio n\.º \d+/.test(rev.motivo ?? "")), JSON.stringify(rev));
    ok(`[${ancho}] administrador sin desborde horizontal`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `admin_${ancho}_personal.png`), fullPage: ancho === 380 });
    await pg.close();
  }
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 600)); }
await nav.close(); srv.close(); estatico.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
