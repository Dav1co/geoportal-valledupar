// Comercial · estandarización visual (rama comercial-estilo, 20-nov-2026) · recorrido en CHROME REAL de la APP COMPLETA (compilada con Vite) contra un servidor
// SIMULADO en 127.0.0.1 (nada llega a Supabase; todo dato es inventado, prefijo ZT). A 390×844 y 1280×900 toma la captura de cada pantalla de Comercial:
//   ventana de entrada · mapa comercial (panel lateral y selector «Modo de trabajo», modos Explorar y Comercial) · (el Dashboard comercial no se toca) ·
//   Formatos de campo dentro de Comercial (lista, Reportar anomalía, Formatos de actividad y un formato, Reportar posible pérdida, Aperturas sin registrar,
//   Supervisión y dashboard con sus 5 secciones, Análisis de contrato con un contrato, Encontrar o reportar activo) · Formatos de campo como área sola.
// Comprueba el modelo visual de la guía (§3–§6) salvo con ANTES=1 (solo captura; para las capturas de antes en main).
//   node scripts/prueba_chrome_comercial_estilo.mjs <chrome> <puppeteer-core> [carpeta_capturas] [prefijo: antes|despues]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, existsSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_comercial_estilo"));
const PREF = process.argv[5] || (process.env.ANTES === "1" ? "antes" : "despues"), SOLO_CAPTURAS = process.env.ANTES === "1";
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_comercial_estilo.mjs <chrome> <puppeteer-core> [capturas] [antes|despues]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const P_MOCK = 55993, P_WEB = 55994;      // puertos de Chrome del Code B (55987–55994)
const MOCK = `http://127.0.0.1:${P_MOCK}`;

// ---------- 1. La app compilada, apuntando al simulador ----------
const DIST = mkdtempSync(join(tmpdir(), "app_comercial_"));
const r = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: MOCK, VITE_SUPABASE_ANON_KEY: "clave-de-prueba", VITE_FUNCTIONS_URL: `${MOCK}/functions/v1` } });
if (r.status !== 0) { console.error("No compiló\n" + r.stdout + r.stderr); process.exit(2); }

// ---------- 2. Respuestas simuladas ----------
const USUARIOS = { "tok-adm": { email: "zt.admin@emdupar.gov.co", admin: true }, "tok-campo": { email: "zt.campo@emdupar.gov.co", admin: false } };
const PERFIL = (u) => u.admin ? { es_admin: true, permisos: { explorar: true, focalizacion: true, comercial: true, rutas: true, dashboard: true, campo: true, dashboard_campo: true, acta: true, dashboard_acta: true, analisis_contrato: true, torre_a: true, torre_b: true, torre_c: true } }
  : { es_admin: false, permisos: { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, campo: true, dashboard_campo: false, acta: true, analisis_contrato: true, torre_a: true, torre_b: false, torre_c: false } };
const campoDef = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const TIPO_INST = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
  fotos_min: 0, fotos_max: 2, requiere_contrato: "opcional", genera_resultado: false, usa_consecutivo: true, causales: [], fotos: [{ codigo: "fachada", nombre: "Fachada", obligatoria: false, orden: 1, activo: true }],
  campos: [campoDef("inst_modalidad", "Instalación o cambio de medidor", "opcion", { obligatorio: true, seccion: "1. Datos básicos", opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor", activo: true }, { codigo: "cambio", nombre: "Cambio de medidor", activo: true }] }),
    campoDef("hora_inicio", "Hora de inicio", "dia_hora", { obligatorio: true, seccion: "1. Datos básicos" }), campoDef("observacion", "Observación", "texto", { seccion: "2. Cierre" })] };
const GRUPOS = [{ codigo: "danos", nombre: "Daños", orden: 1, activo: true, tipos: [{ codigo: "fuga", nombre: "Fuga visible", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] },
  { codigo: "perdidas_formatos", nombre: "Pérdidas", orden: 2, activo: true, tipos: [TIPO_INST] }];
const DEF = (sup) => ({ perfil: sup ? "admin" : "reportante", puede: { reportar: true, crear_desde_escritorio: sup, supervisar: sup, administrar_catalogo: sup },
  limites: { max_fotos: 2, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
  grupos: GRUPOS, estados: sup ? [{ codigo: "reportado", nombre: "Reportado", orden: 1, activo: true, exige_motivo: false, cambio_manual: true }, { codigo: "atendido", nombre: "Atendido", orden: 2, activo: true, exige_motivo: false, cambio_manual: true }] : null,
  parametros: sup ? [{ clave: "distancia_duplicados_m", valor: 30, unidad: "m", descripcion: "Distancia para posibles duplicados", minimo: 5, maximo: 200 }] : null, definiciones: [] });
const hoy = new Date(), iso = (d) => new Date(hoy.getTime() - d * 86400000).toISOString();
const FILA = (i) => ({ id: `zt-${i}`, seq: 100 + i, tipo: { codigo: "fuga", nombre: "Fuga visible" }, grupo: { codigo: "danos", nombre: "Daños" }, subtipo: null, descripcion: "ZT descripción", contrato: String(1000000 + i), contrato_verificado: true,
  lat: 10.46 + i / 1000, lon: -73.25, precision_m: 8, riesgo_inmediato: i === 1, origen: "campo", fuera_de_zona: false, registrado_en: iso(i), estado: i % 2 ? "reportado" : "atendido", estado_desde: iso(i), oculto: false,
  reporte_original_id: null, grupo_duplicados: null, tamano_grupo: null, n_fotos: 1, consecutivo: `ZT-${String(i).padStart(6, "0")}` });
const IND = { total: 6, visibles: 6, ocultos: 0, corte: iso(0), filtros: {}, serie_recortada: false, por_dia: [0, 1, 2, 3, 4, 5].map((d) => ({ dia: iso(d).slice(0, 10), n: d + 1 })),
  por_tipo: [{ tipo: { codigo: "fuga", nombre: "Fuga visible" }, grupo: { codigo: "danos", nombre: "Daños" }, n: 6 }], por_estado: [{ estado: "reportado", nombre: "Reportado", n: 3 }, { estado: "atendido", nombre: "Atendido", n: 3 }],
  revision: { revisados: 3, sin_revisar: 3, mediana_segundos: 3600, promedio_segundos: 4000, p90_segundos: 9000 } };
const CAT_ACTA = { capacidades: { capturar: true, supervisar: true, administrar: true }, aviso_registro: "Registro digital.", tipos_hallazgo: [{ codigo: "otro", nombre: "Otro", nota: null, exige_texto: true, excluyente: false, habilita_accion: null }],
  calidades_atendiente: [], estados_medidor: [], estados_sellos: [], diametros: [], acciones: [], tipos_foto: [{ codigo: "fachada", nombre: "Fachada", exigida_con_irregularidad: true, acta_fisica: false }],
  limites: { min_fotos_irregularidad: 1, min_fotos_sin_irregularidad: 1, max_fotos: 4, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 } };
const mes = (periodo, m3) => ({ periodo, sin_dato: false, m3, metodo: "lectura", lectura_real: true, causal: "99 LECTURA NORMAL" });
const ANALISIS = { encontrado: true, comodin: false, contrato: "1000001", suscriptor: { nombre: "NOMBRE DE PRUEBA", telefonos: ["3000000001"], telefono_fuente: "censo", corte: "20261114" },
  comercial: { estado: "ACTIVO", categoria: "1 Residencial", subcategoria: "2 Estrato 2", ciclo: "7", ruta: "0701", barrio: "BARRIO DE PRUEBA", direccion: "CRA 0 00 00", deuda_total: 412300, saldo_pendiente: 98000,
    facturas_pendientes: 5, saldo_financiado: 0, valor_reclamo: 0, saldo_a_favor: 0, tramo_mora: "media", estado_predio: "HABITADO", facturas_vencidas: 4, corte: "20261114" },
  medidor: { serial: "A00001", diametro: "1/2", fecha_instalacion: "2014-03-01", fecha_estado: "real", anios: 12, cambio: { confirmado: null, recodificado: null } },
  consumo: { periodo_ultimo: "202610", maximo: 11, minimo: 5, promedio: 7.8, meses_con_lectura: 6, meses: [mes("202605", 7), mes("202606", 8), mes("202607", 9), mes("202608", 11), mes("202609", 5), mes("202610", 6)] },
  promedios: null, submedicion: { marca: true, periodo: "202610", consumo: 6, referencia: 14.2, n_nuevos: 1800, estrato: "Estrato 2", anios: 12, motivo: null }, pago: { fecha: "2026-09-18", valor: 85000, fuente: "cupones", dias: 57 },
  gestiones: { emd_facturados: [], terreno: [], pqr: { ultima: null, abiertas: 0, ultimos_12_meses: 0, total: 0 }, reportes: [], reportes_total: 0, actas: [], pendientes: [] },
  ubicacion: { predios_total: 1, predios: [{ direccion: "CRA 0 00 00", barrio: "BARRIO DE PRUEBA", lat: 10.4631, lon: -73.2532 }] }, fotos: [], cortes: { cartera: "20261114", consumo: "202610", ficha: "2026-11-14T22:10:00-05:00" }, ficha_disponible: true };
// Tablero: 14 meses de KPI inventados; las demás vistas vacías (cada pantalla muestra su «sin datos» dentro del encabezado y las pestañas comunes)
const PERIODOS = Array.from({ length: 14 }, (_, i) => { const d = new Date(Date.UTC(2025, 9 + i, 1)); return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}`; });
const KPI = PERIODOS.map((p, i) => ({ periodo: p, facturado: 9.1e9 + i * 1e8, recaudo_total: 8.2e9 + i * 9e7, recaudo_0_30: 6.1e9, recaudo_60_360: 1.2e9, recaudo_may360: 0.4e9, pct_recaudo_0_30: 0.67, pct_recaudo_mes: 0.9,
  cartera_total: 61e9 - i * 1e8, notas_valor: 2.1e8, contratos_activos: i > 7 ? 111000 + i * 50 : null, contratos_con_cartera: i > 7 ? 52000 : null }));
const ANIOS = [2025, 2026].map((a) => ({ anio: a, facturado: 100e9, recaudo_total: 90e9, notas_valor: 2e9, meses: a === 2025 ? 12 : 11 }));
const FUENTES = ["facturacion_agrupado", "recaudo_agrupado", "cartera_resumen", "facturacion_contratos", "recaudo_detalle", "cartera_edades", "reclamos", "notas", "cupones_pagos"];
function bi(vista) {
  if (vista === "v_kpi_mes") return KPI;
  if (vista === "v_kpi_anio") return ANIOS;
  if (vista === "v_periodos_fuente") return FUENTES.flatMap((f) => PERIODOS.map((p) => ({ fuente: f, periodo: p })));
  return [];
}
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC", "base64");
const CAB = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer", "access-control-allow-methods": "GET, POST, PUT, PATCH, OPTIONS" };
const noSimulado = new Set();
const mock = http.createServer((q, res) => {
  const u = new URL(q.url, MOCK);
  const json = (o, s = 200) => { res.writeHead(s, { ...CAB, "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(o)); };
  if (q.method === "OPTIONS") { res.writeHead(204, CAB); return res.end(); }
  const trozos = []; q.on("data", (c) => trozos.push(c)); q.on("end", () => {
    let b = null; try { b = JSON.parse(Buffer.concat(trozos).toString() || "null"); } catch { /* sin cuerpo */ }
    const tok = (q.headers.authorization ?? "").replace(/^Bearer /, ""), yo = USUARIOS[tok] ?? USUARIOS["tok-adm"];
    if (u.pathname.startsWith("/auth/v1/token")) return json({ access_token: tok, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u", email: yo.email, aud: "authenticated", role: "authenticated" } });
    if (u.pathname.startsWith("/auth/v1/user")) return json({ id: "u", email: yo.email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} });
    if (u.pathname.startsWith("/auth/v1/logout")) return json({});
    if (u.pathname.startsWith("/rest/v1/")) return json(u.pathname.includes("geoportal_estado_acceso") ? "ok" : null);
    const fn = u.pathname.split("/").at(-1), acc = u.searchParams.get("accion");
    if (u.pathname.includes("/geoportal-tiles/")) { res.writeHead(204, CAB); return res.end(); }
    switch (fn) {
      case "geoportal-admin": if (acc === "perfil") return json(PERFIL(yo)); return json({ usuarios: [] });
      case "geoportal-barrios": return json({ barrios: ["BARRIO DE PRUEBA", "OTRO BARRIO ZT"] });
      case "geoportal-causales": return json({ causales: ["99 LECTURA NORMAL", "21 PREDIO CERRADO"] });
      case "geoportal-rutas-lista": return json({ rutas: [{ ruta: "0701", ciclo: "7", nombre: "Ruta 0701", predios: 900 }] });
      case "geoportal-bi": return json({ datos: bi(b?.vista) });
      case "geoportal-campo":
        switch (acc) {
          case "formulario": return json(DEF(yo.admin));
          case "config_constancia": return json({ habilitado: false });
          case "reportes": return json({ reportes: [1, 2, 3, 4, 5, 6].map(FILA), total: 6, siguiente: null, distancia_duplicados_m: 30 });
          case "indicadores": return json(IND);
          case "catalogo_lectura": return json({ ...DEF(true), solo_lectura: false, constancias: { texto: null, documentos: [{ documento: "constancia_visita", habilitado: false, copias_internas: [] }], cola: {}, fallos_ultimos_30_dias: 0 } });
          case "personal": return json({ puede_editar: true, formularios: [{ clave: "reporte_general", nombre: "Reportar anomalía", grupo: "Campo" }, { clave: "instalacion_medidor", nombre: "Instalación de medidor", grupo: "Formatos" }],
            personas: [{ email: "zt.op@emdupar.gov.co", nombre: "ZT Operario", perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: true, dashboard_acta: false }, cargo: "Técnico", formularios: ["reporte_general"], sin_asignacion: false, ultimo_cambio: iso(3) }] });
          case "historial_personal": return json({ eventos: [], siguiente: null });
          case "documentos_catalogo": return json({ formularios: [{ formulario: "tipo:instalacion_medidor", lleva_pdf: true, firmas: { operario: "obligatoria", usuario: "opcional", testigo: "opcional" } }] });
          case "actas_registradas": return json({ filas: [{ registro_id: "00000000-0000-4000-8000-000000000001", esquema: "campo", tipo: "instalacion_medidor", tipo_nombre: "Instalación de medidor", consecutivo: "IME-000001", numero_fisico: null, fecha: "2026-11-21", registrado_en: new Date().toISOString(), operario: "zt.ana@emdupar.gov.co", contrato: "1000001", barrio: "BARRIO DE PRUEBA", resultado: "efectivo", pdf: { estado: "pendiente", nombre: null, version: null }, derivadas: { total: 0, pendientes: 0 }, firmas: { operario: true, usuario: "nadie_atendio", testigo: false } }], siguiente: null });
          case "derivadas": return json({ filas: [], siguiente: null });
          case "cuadrillas": return json({ cuadrillas: [] });
          case "constancia_estado": return json({ texto: null, documentos: [{ documento: "constancia_visita", habilitado: false, copias_internas: [] }], cola: {}, fallos_ultimos_30_dias: 0 });
          case "analisis_contrato": return json(u.searchParams.get("contrato") === "1000001" ? ANALISIS : { encontrado: false, contrato: u.searchParams.get("contrato") });
          case "analisis_cercanos": return json({ radio_m: 300, contratos: [], cupo: { limite: 30, usadas: 0, restantes: 30, sin_limite: false } });
          default: noSimulado.add(`campo:${acc}`); return json({ error: "Acción no soportada." }, 400);
        }
      case "geoportal-acta":
        switch (acc) {
          case "formulario": return json(CAT_ACTA);
          case "mis_actas": return json({ filas: [], hay_mas: false, max_filas: 50 });
          case "motivos_cancelacion": return json({ motivos: [{ codigo: "duplicada", nombre: "Apertura duplicada", activo: true }] });
          case "documentos_catalogo": return json({ formularios: [{ formulario: "acta", lleva_pdf: true, firmas: { operario: "obligatoria", usuario: "opcional", testigo: "opcional" } }] });
          case "actas_registradas": return json({ filas: [], siguiente: null });
          case "aperturas_sin_registrar": return json({ resumen: { en_curso: 1, vencidas: 1, canceladas: 0 }, max_filas: 200,
            filas: [{ acta_id: "a1", consecutivo: "ACT-000101", autor: "zt.op@emdupar.gov.co", abierto_en: iso(0.1), vence_en: iso(-0.4), situacion: "abierta_en_curso" },
                    { acta_id: "a2", consecutivo: "ACT-000099", autor: "zt.op@emdupar.gov.co", abierto_en: iso(2), vence_en: iso(1.5), situacion: "abierta_vencida_sin_registrar" }] });
          default: noSimulado.add(`acta:${acc}`); return json({ error: "Acción no soportada." }, 400);
        }
      case "geoportal-redes":
        switch (acc) {
          case "mi_perfil": return json({ perfil: "operador", email: yo.email });
          case "levantar_mios": return json({ puntos: [], dias: 30 });
          case "levantar_inicio": return json({ perfil: "comercial", area: "comercial", ficha_completa: false, radio_min_m: 10, radio_max_m: 200, duplicado_m: 15, min_fotos: 1, max_fotos: 3,
            servicios: [{ codigo: "acueducto", nombre: "Acueducto" }, { codigo: "alcantarillado", nombre: "Alcantarillado" }], tipos: [{ codigo: "valvula", nombre: "Válvula" }, { codigo: "tuberia", nombre: "Tubería" }] });
          case "levantar_cerca": return json({ activos: [], puntos: [], radio_m: 50 });
          case "evento_contrato": return json({ contrato: u.searchParams.get("contrato"), consultado_en: new Date().toISOString(), ubicado: true, en_evento: false, evento: null, otros_eventos: 0 });
          case "levantar_catalogo": case "catalogo": return json({ tipos: [{ prefijo: "VAL", nombre: "Válvula", nombre_visible: "Válvula", activo: true, sistema: "acueducto" }], servicios: ["acueducto", "alcantarillado"] });
          default: noSimulado.add(`redes:${acc}`); return json({ error: "Acción no soportada." }, 400);
        }
      default: noSimulado.add(fn); return json({ error: "no simulado" }, 404);
    }
  });
});
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => mock.listen(P_MOCK, "127.0.0.1", a)); await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));

// ---------- 3. Recorrido ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { if (SOLO_CAPTURAS) return; total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + String(d).replace(/\n/g, " ").slice(0, 600)}`); };
const esp = (ms) => new Promise((x) => setTimeout(x, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const ORIGEN = `http://127.0.0.1:${P_WEB}`;
await nav.defaultBrowserContext().overridePermissions(ORIGEN, ["geolocation"]);
const errores = [];
let ANCHO = 390, ALTO = 844;
async function abrir(tok) {
  const ctx = await nav.createBrowserContext(); await ctx.overridePermissions(ORIGEN, ["geolocation"]);
  const pg = await ctx.newPage();
  await pg.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  await pg.setGeolocation({ latitude: 10.4631, longitude: -73.2532, accuracy: 8 });
  pg.on("pageerror", (e) => errores.push(`${ANCHO} ${String(e).slice(0, 200)}`));
  pg.on("requestfailed", (q) => { if (q.url().startsWith("http://127.0.0.1")) errores.push(`${ANCHO} falló ${q.url()} ${q.failure()?.errorText}`); });
  pg.on("response", (q) => { if (q.status() >= 400 && q.url().includes(":" + P_WEB)) errores.push(`${ANCHO} ${q.status()} ${q.url()}`); });
  pg.on("console", async (m) => { if (m.type() !== "error" || /Failed to load resource/.test(m.text())) return;
    const t = (await Promise.all(m.args().map((x) => x.evaluate((v) => (v instanceof Error ? `${v.name}: ${v.message} ${String(v.stack).split("\n")[1] ?? ""}` : String(v))).catch(() => "?")))).join(" ");
    errores.push(`${ANCHO} consola: ${t.slice(0, 300)}`); });
  pg.on("framenavigated", (f) => { if (f === pg.mainFrame()) errores.push(`${ANCHO} navegó ${f.url()}`); });
  await pg.evaluateOnNewDocument((t, correo) => {
    if (localStorage.getItem("sb-127-auth-token")) return;
    localStorage.setItem("sb-127-auth-token", JSON.stringify({ access_token: t, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u", email: correo, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} } }));
  }, tok, USUARIOS[tok].email);
  await pg.goto(ORIGEN, { waitUntil: "domcontentloaded" });
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const esperarTexto = async (pg, re, ms = 20000) => { const fin = Date.now() + ms; while (Date.now() < fin) { if (re.test(await texto(pg).catch(() => ""))) return true; await esp(150); } return false; };
const clic = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.replace(/\s+/g, " ").trim().includes(x) && !e.disabled && e.offsetParent !== null); if (b) { b.scrollIntoView({ block: "center" }); b.click(); } return !!b; }, sel, t);
const elegirModo = (pg, v) => pg.evaluate((x) => {
  const b = [...document.querySelectorAll(`.modo-opcion[data-modo="${x}"]`)].find((e) => e.offsetParent !== null) ?? document.querySelector(`.modo-opcion[data-modo="${x}"]`);
  if (b) { b.click(); return true; }
  const s = [...document.querySelectorAll("select.modo-sel")].find((e) => e.offsetParent !== null) ?? document.querySelector("select.modo-sel"); if (!s) return false;
  Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value").set.call(s, x); s.dispatchEvent(new Event("change", { bubbles: true })); return true; }, v);
const capturas = [];
async function foto(pg, nombre, completa = true) { const f = join(CAP, `${PREF}_${nombre}_${ANCHO}.png`); await pg.screenshot({ path: f, fullPage: completa }); capturas.push(f); }
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
/** Colores sueltos: todo color de fondo, borde o texto de lo visible dentro de `sel` que no sea un token de la guía (neutros, estados, Comercial, el azul general). */
const PALETA = ["#782a27", "#f6e8e7", "#ffffff", "#f2f5f8", "#d5dde6", "#7b8b99", "#eef2f5", "#22313f", "#52626f", "#0a2540", "#b3261e", "#fdecea", "#c25e00", "#fff4e5", "#1b6b3a", "#e7f4ec", "#eaf2fb", "#4a90d9", "#1e5aa8", "#000000"];
const fueraDePaleta = (pg, sel) => pg.evaluate((s, pal) => {
  const hex = (c) => { const m = c.match(/rgba?\((\d+), (\d+), (\d+)(?:, ([\d.]+))?\)/); if (!m || m[4] === "0") return null; return "#" + [m[1], m[2], m[3]].map((x) => Number(x).toString(16).padStart(2, "0")).join(""); };
  const raros = new Map();
  for (const e of document.querySelectorAll(`${s} *`)) {
    // se excluyen los colores de leyenda que la guía deja como están (§6): gráficas, mapas, insignias de estado, semáforo de mora y bandas de «Buscar el predio»
    if (!e.offsetParent || e.closest("svg, canvas, .maplibregl-map, .leyenda, .rv-leyenda, .rv-marca, .rv-estado, .rv-grupo-dup, .rv-inactivo, .ac-grafica, .ac-leyenda, .ac-tramo-leve, .ac-tramo-media, .ac-bp, [data-color-propio]")) continue;
    const cs = getComputedStyle(e);
    for (const [prop, v] of [["fondo", cs.backgroundColor], ["borde", cs.borderLeftWidth !== "0px" ? cs.borderLeftColor : "rgba(0, 0, 0, 0)"], ["texto", cs.color]]) {
      const h = hex(v); if (h && !pal.includes(h)) raros.set(`${prop} ${h}`, (e.className && typeof e.className === "string" ? e.className.split(" ")[0] : e.tagName.toLowerCase()));
    }
  }
  return [...raros.entries()].slice(0, 12);
}, sel, PALETA);
const VINO = "rgb(120, 42, 39)";
/** El modelo visual de una pantalla de Campo (guía §2–§5): colores de la guía, una sola fuente, nada se sale a lo ancho; y lo propio de cada pantalla. */
async function revisar(pg, nombre, T) {
  if (SOLO_CAPTURAS) return;
  const raros = await fueraDePaleta(pg, ".campo-contenedor, .cuerpo-campo");
  ok(`${T} ${nombre}: sin colores fuera de la guía`, raros.length === 0, JSON.stringify(raros));
  const fam = await pg.evaluate(() => [...new Set([...document.querySelectorAll(".campo-contenedor *")].filter((e) => e.offsetParent && !e.closest(".maplibregl-ctrl") && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()))
    .map((e) => getComputedStyle(e).fontFamily.split(",")[0].replace(/"/g, "").trim()))]);
  ok(`${T} ${nombre}: una sola fuente (Arial; la monoespaciada solo en códigos)`, fam.every((f) => f === "Arial" || f === "Courier New"), JSON.stringify(fam));
  const ancho = await pg.evaluate(() => { const c = document.querySelector(".campo-contenedor"); return c ? { s: c.scrollWidth, w: c.clientWidth } : null; });
  ok(`${T} ${nombre}: nada se sale a lo ancho`, !!ancho && ancho.s <= ancho.w + 1, JSON.stringify(ancho));
  const cap = await pg.evaluate(() => { const b = [...document.querySelectorAll(".modo-opcion")].filter((e) => e.offsetParent); const s = b.find((e) => e.getAttribute("aria-checked") === "true");
    return { n: b.length, alto: Math.min(...b.map((e) => e.getBoundingClientRect().height)), fondo: s && getComputedStyle(s).backgroundColor, color: s && getComputedStyle(s).color, sel: s?.textContent }; });
  ok(`${T} ${nombre}: el selector «Modo de trabajo» es la cápsula de modos; «Formatos de campo» elegido en el color de Comercial; toques de 44 px`, cap.n >= 2 && cap.sel === "Formatos de campo" && cap.fondo === VINO && cap.color === "rgb(255, 255, 255)" && cap.alto >= 44, JSON.stringify(cap));
}
const fuentes = (pg) => pg.evaluate(() => [...new Set([...document.querySelectorAll("body *")].filter((e) => e.offsetParent && e.childNodes.length && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()))
  .map((e) => getComputedStyle(e).fontFamily.split(",")[0].replace(/"/g, "").trim()))]);

for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
  ANCHO = ancho; ALTO = alto; const T = `[${ancho}]`;
  // ===== Administrador: entrada → Comercial =====
  const pg = await abrir("tok-adm");
  await esperarTexto(pg, /Comercial/); await esp(600);
  await foto(pg, "01_entrada");
  await pg.evaluate(() => { const b = [...document.querySelectorAll("button")].find((e) => /COMERCIAL|Comercial/.test(e.textContent)); b?.click(); });
  await pg.waitForSelector(".mapa", { timeout: 25000 }).catch(() => {}); await esp(1500);
  await foto(pg, "02_mapa_explorar", false);
  if (ancho < 500) { await clic(pg, "button.btn-panel-movil", "Controles"); await esp(500); }
  await foto(pg, "03_panel_explorar", false);
  if (!SOLO_CAPTURAS) {
    const lat = await pg.evaluate(() => { const s = document.querySelector(".lateral .modo-opcion[aria-checked='true']"); const p = document.querySelector(".lateral .leyenda .punto-normal");
      const sel = document.querySelector(".lateral select.modo-sel"); const b = [...document.querySelectorAll(".lateral .modo-opcion")];
      return { sel: s?.textContent, fondo: s && getComputedStyle(s).backgroundColor, leyenda: p && getComputedStyle(p).backgroundColor, campo: sel && getComputedStyle(sel).borderTopColor, opciones: b.map((e) => e.textContent), alto: Math.min(...b.map((e) => e.getBoundingClientRect().height)) }; });
    ok(`${T} M1 panel lateral: cápsula de modos con las 7 opciones (las 6 de antes y «Cartera» del Motor SCRR, 22-nov) y el modo elegido en el color de Comercial (toques de 44 px)`, lat.sel === "Explorar" && lat.fondo === VINO && lat.alto >= 44
       && JSON.stringify(lat.opciones) === JSON.stringify(["Explorar", "Focalización", "Comercial", "Rutas de lectura", "Dashboard", "Cartera", "Formatos de campo"]), JSON.stringify(lat));
    ok(`${T} M2 el mapa queda neutro: la leyenda conserva el azul de su capa; los desplegables del panel, borde de campo neutro`, lat.leyenda === "rgb(30, 90, 168)" && lat.campo === "rgb(123, 139, 153)", JSON.stringify(lat));
  }
  await elegirModo(pg, "comercial"); await esp(900);
  await foto(pg, "04_panel_comercial", false);
  if (ancho < 500) { await clic(pg, "button.btn-cerrar-panel", "Cerrar"); await esp(300); }

  // El Dashboard comercial NO se toca (instrucción de David, 20-nov): no se recorre aquí.

  // ===== Formatos de campo dentro de Comercial =====
  if (ancho < 500) { await clic(pg, "button.btn-panel-movil", "Controles"); await esp(300); }
  await elegirModo(pg, "campo"); await pg.waitForSelector("button.campo-formato", { timeout: 15000 }).catch(() => {}); await esp(600);
  await foto(pg, "20_campo_lista");
  await revisar(pg, "C0 inicio de Formatos de campo", T);
  if (!SOLO_CAPTURAS) {
    const t = await pg.evaluate(() => [...document.querySelectorAll("button.campo-formato")].map((b) => { const cs = getComputedStyle(b), ini = b.querySelector(".com-tarjeta-ini");
      return { izq: cs.borderLeftWidth, col: cs.borderLeftColor, fondo: cs.backgroundColor, radio: cs.borderTopLeftRadius, alto: b.getBoundingClientRect().height, svg: !!b.querySelector(".com-tarjeta-ini svg[data-icono]"), ini: ini && getComputedStyle(ini).backgroundColor, letra: ini && getComputedStyle(ini, "::before").content, txt: b.textContent }; }));
    ok(`${T} C1 cada entrada es la tarjeta de la guía: blanca, borde izquierdo de 5 px del color de Comercial, radio 12 px, cuadro con su ícono SVG; ${t.length} entradas (25-nov: las de «Registrar en campo»)`,
       t.length >= 5 && t.every((x) => x.izq === "5px" && x.col === VINO && x.fondo === "rgb(255, 255, 255)" && x.radio === "12px" && x.alto >= 64 && x.ini === VINO && x.svg), JSON.stringify(t.slice(0, 2)));
    const cols = await pg.evaluate(() => new Set([...document.querySelectorAll("button.campo-formato")].map((b) => Math.round(b.getBoundingClientRect().left))).size);
    ok(`${T} C2 rejilla: ${ancho < 500 ? "una columna en el celular" : "varias columnas en el PC"}`, ancho < 500 ? cols === 1 : cols >= 2, String(cols));
  }
  const ENTRADAS = [["21_reportar_anomalia", "Reportar anomalía"], ["22_formatos", "Formatos de actividad"], ["24_acta", "Reportar posible pérdida"], ["25_actas_registradas", "Actas registradas"],
    ["26_analisis", "Análisis de contrato"], ["27_encontrar", "Encontrar o reportar activo"], ["28_supervision", "Supervisión y dashboard"]];
  for (const [nom, t] of ENTRADAS) {
    // 25-nov: las entradas de gestión están en la pestaña «Supervisar»; las demás, en «Registrar en campo»
    await clic(pg, "[role=tab]", /Actas registradas|Supervisión y dashboard/.test(t) ? "Supervisar" : "Registrar en campo"); await esp(300);
    if (!(await clic(pg, "button.campo-formato, button", t))) { console.log(`(no se encontró la entrada «${t}»)`); continue; }
    await esp(1500);
    if (nom === "22_formatos") { await foto(pg, nom); if (await clic(pg, "button", "Instalación de medidor")) { await esp(900); await foto(pg, "23_formato_abierto"); } }
    else if (nom === "26_analisis") {
      await foto(pg, nom);
      const c = await pg.$("#ac-contrato"); if (c) { await c.type("1000001"); await pg.keyboard.press("Enter"); await esperarTexto(pg, /BARRIO DE PRUEBA|Consumo/); await esp(1200); await foto(pg, "26b_analisis_resultado"); }
    } else if (nom === "25_actas_registradas") {
      await foto(pg, nom);
      for (const [k, s2] of [["b_derivadas", "Avisos y actividades derivadas"], ["c_aperturas", "Aperturas sin registrar"]]) { if (await clic(pg, "button.rv-tab", s2)) { await esp(900); await foto(pg, `25${k}`); } }
    } else if (nom === "28_supervision") {
      await foto(pg, nom);
      for (const [k, s] of [["b_indicadores", "Indicadores"], ["c_catalogo", "Catálogo"], ["d_parametros", "Parámetros"], ["e_personal", "Personal"]]) { if (await clic(pg, "button, [role=tab]", s)) { await esp(900); await foto(pg, `28${k}`); } }
    } else await foto(pg, nom);
    await revisar(pg, `C ${nom}`, T);
    if (!SOLO_CAPTURAS && ["21_reportar_anomalia", "24_acta", "26_analisis"].includes(nom)) {
      const cab = await pg.evaluate(() => { const c = document.querySelector(".campo-cab"); const h = c?.querySelector("h1, h2"); return c ? { fondo: getComputedStyle(c).backgroundColor, color: h && getComputedStyle(h).color } : null; });
      ok(`${T} ${nom}: encabezado de sección en barra del color de Comercial, título en blanco`, cab?.fondo === VINO && cab?.color === "rgb(255, 255, 255)", JSON.stringify(cab));
    }
    if (!SOLO_CAPTURAS && nom === "21_reportar_anomalia") {
      const f = await pg.evaluate(() => { const b = [...document.querySelectorAll("button")].find((e) => /Tomar foto 1/.test(e.textContent)); return { svg: !!b?.querySelector("svg[data-icono=camara]"), emoji: /📷/.test(document.body.innerText), fondo: b && getComputedStyle(b).backgroundColor }; });
      ok(`${T} C3 «Tomar foto»: ícono de cámara en SVG (sin emoji) y botón principal en el color de Comercial`, f.svg && !f.emoji && f.fondo === VINO, JSON.stringify(f));
    }
    if (!SOLO_CAPTURAS && nom === "25_actas_registradas") {
      const h = await pg.evaluate(() => { const c = document.querySelector(".rv-cab"); return { fondo: c && getComputedStyle(c).backgroundColor, n: document.querySelectorAll(".rv-tab").length }; });
      ok(`${T} C5 Actas registradas (21-nov): el mismo encabezado de Supervisión en el color de Comercial, con sus pestañas`, h.fondo === VINO && h.n >= 3, JSON.stringify(h));
    }
    if (!SOLO_CAPTURAS && nom === "28_supervision") {
      const h = await pg.evaluate(() => { const c = document.querySelector(".rv-cab"), a = document.querySelector(".rv-tab[aria-current=page]"); return { fondo: c && getComputedStyle(c).backgroundColor, linea: a && getComputedStyle(a).borderBottomColor }; });
      ok(`${T} C4 Supervisión y dashboard de campo: encabezado común en el color de Comercial y la pestaña activa subrayada en blanco (como los dashboards de Técnica)`, h.fondo === VINO && h.linea === "rgb(255, 255, 255)", JSON.stringify(h));
    }
    // volver a la lista
    for (let v = 0; v < 3 && !(await pg.$("button.campo-formato")); v++) { if (!(await clic(pg, "button", "Volver"))) await clic(pg, "button", "←"); await esp(700); }
  }
  await pg.browserContext().close();

  // ===== Formatos de campo como área sola (quien solo tiene campo) =====
  const pc = await abrir("tok-campo"); await pc.waitForSelector("button.campo-formato", { timeout: 15000 }).catch(() => {}); await esp(800);
  await foto(pc, "30_campo_sola");
  if (!SOLO_CAPTURAS) {
    const s = await pc.evaluate(() => { const b = document.querySelector("button.campo-formato"); return { col: b && getComputedStyle(b).borderLeftColor, n: document.querySelectorAll("button.campo-formato").length }; });
    ok(`${T} C5 Formatos de campo como área sola (quien solo tiene campo): las mismas tarjetas en el color de Comercial`, s.n >= 3 && s.col === VINO, JSON.stringify(s));
  }
  await pc.browserContext().close();
}
console.log(`\nCapturas: ${capturas.length} en ${CAP}`);
if (noSimulado.size) console.log("Rutas no simuladas (responden 400/404):", [...noSimulado].join(", "));
if (errores.length) console.log("Errores de página:", errores.filter((e) => !/maplibre|favicon/.test(e)).join(" | "));
if (!SOLO_CAPTURAS) console.log(`\n${total - fallas} de ${total}${fallas ? ` (${fallas} FALLAS)` : " SIN FALLAS"}`);
await nav.close(); mock.close(); web.close(); rmSync(DIST, { recursive: true, force: true });
process.exit(fallas ? 1 : 0);
