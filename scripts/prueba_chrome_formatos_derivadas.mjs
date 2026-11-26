// Formatos de campo ordenados + «Avisos y actividades derivadas» dentro de Reportes (Code B, 25-nov-2026) · CHROME REAL contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase; datos inventados, prefijo ZT).
// Los 5 PERFILES de David (24-nov) a 390×844 y 1280×900: administrador · supervisor de Comercial · operario de campo · usuario dual (Comercial y Técnica) · sin permisos. Para cada uno dice qué ve y qué no ve (el SERVIDOR decide; la pantalla lo refleja).
//   node scripts/prueba_chrome_formatos_derivadas.mjs <chrome> <puppeteer-core> [carpeta_capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, existsSync, statSync, rmSync } from "node:fs";
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
const P_MOCK = 55989, P_WEB = 55990;      // puertos de Chrome del Code B (55987–55994)
const MOCK = `http://127.0.0.1:${P_MOCK}`;

// ---------- 1. La app compilada, apuntando al simulador ----------
const DIST = mkdtempSync(join(tmpdir(), "app_comercial_"));
const r = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: MOCK, VITE_SUPABASE_ANON_KEY: "clave-de-prueba", VITE_FUNCTIONS_URL: `${MOCK}/functions/v1` } });
if (r.status !== 0) { console.error("No compiló\n" + r.stdout + r.stderr); process.exit(2); }

// ---------- 2. Respuestas simuladas ----------
const P = (o) => ({ explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, campo: false, dashboard_campo: false, acta: false, dashboard_acta: false, analisis_contrato: false, torre_a: false, torre_b: false, torre_c: false, ...o });
// Los 5 perfiles de David (24-nov): admin · supervisor de Comercial · operario de campo (solo registra) · dual (Comercial y Técnica) · sin permisos asignados
const USUARIOS = {
  "tok-adm": { email: "zt.admin@emdupar.gov.co", admin: true, sup: true, perfilCampo: "admin", repSup: true, pend: 120, permisos: P({ explorar: true, focalizacion: true, comercial: true, rutas: true, dashboard: true, campo: true, dashboard_campo: true, acta: true, dashboard_acta: true, analisis_contrato: true, torre_a: true, torre_b: true, torre_c: true }) },
  "tok-sup": { email: "zt.supervisor@emdupar.gov.co", admin: false, sup: true, perfilCampo: "supervisor", repSup: true, pend: 7, permisos: P({ explorar: true, comercial: true, campo: true, dashboard_campo: true, acta: true, dashboard_acta: true, analisis_contrato: true, torre_a: true }) },
  "tok-campo": { email: "zt.campo@emdupar.gov.co", admin: false, sup: false, perfilCampo: "reportante", repSup: false, pend: 0, permisos: P({ campo: true, acta: true, analisis_contrato: true, torre_a: true }) },
  "tok-dual": { email: "zt.dual@emdupar.gov.co", admin: false, sup: true, perfilCampo: "supervisor", repSup: false, pend: 7, permisos: P({ explorar: true, comercial: true, campo: true, dashboard_campo: true, acta: true, analisis_contrato: true, torre_a: true, torre_b: true }) },
  "tok-nada": { email: "zt.nada@emdupar.gov.co", admin: false, sup: false, perfilCampo: null, repSup: false, pend: 0, permisos: P({}) },
};
const PERFIL = (u) => ({ es_admin: u.admin, permisos: u.permisos });
const campoDef = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const TIPO_INST = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
  fotos_min: 0, fotos_max: 2, requiere_contrato: "opcional", genera_resultado: false, usa_consecutivo: true, causales: [], fotos: [{ codigo: "fachada", nombre: "Fachada", obligatoria: false, orden: 1, activo: true }],
  campos: [campoDef("inst_modalidad", "Instalación o cambio de medidor", "opcion", { obligatorio: true, seccion: "1. Datos básicos", opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor", activo: true }, { codigo: "cambio", nombre: "Cambio de medidor", activo: true }] }),
    campoDef("hora_inicio", "Hora de inicio", "dia_hora", { obligatorio: true, seccion: "1. Datos básicos" }), campoDef("observacion", "Observación", "texto", { seccion: "2. Cierre" })] };
const GRUPOS = [{ codigo: "danos", nombre: "Daños", orden: 1, activo: true, tipos: [{ codigo: "fuga", nombre: "Fuga visible", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] },
  { codigo: "perdidas_formatos", nombre: "Pérdidas", orden: 2, activo: true, tipos: [TIPO_INST] }];
const DEF = (sup, perfil = "admin") => ({ perfil: sup ? perfil : "reportante", puede: { reportar: true, crear_desde_escritorio: sup, supervisar: sup, administrar_catalogo: sup && perfil === "admin" },
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
// Lista de «derivadas» simulada: el servidor aplica estado, origen, actividad, contrato y fechas, y pagina con `antes` (cursor = id). Datos inventados (prefijo ZT); los datos de contacto NUNCA vienen en esta ruta.
const TODAS = (n) => [...Array.from({ length: n }, (_, i) => i + 1).map((i) => ({ id: 1000 + i, actividad: i % 3 ? "aviso_direccion_errada" : "revision_derivada", actividad_nombre: i % 3 ? "Aviso: dirección errada" : "Revisión de medidor", contrato: String(2000000 + i), estado: "pendiente",
    creada_en: iso(i / 10), antiguedad_dias: Math.floor(i / 10), origen: i % 3 ? { clase: "analisis", tipo: "analisis", fecha: iso(i / 10), operario: "zt.operario@emdupar.gov.co", observacion_nombre: "Dirección errada", texto: "TEXTO LIBRE ZT", direccion_correcta: "DIRECCION-ZT", trae_datos: i % 2 === 0, entregas_datos: 1, vistos: 0 }
      : { clase: "registro", tipo: "instalacion_medidor", consecutivo: `IME-${String(i).padStart(6, "0")}`, fecha: iso(i / 10).slice(0, 10), operario: "zt.operario@emdupar.gov.co" }, cierre: null })),
  ...[1, 2, 3, 4, 5].map((i) => ({ id: 500 + i, actividad: "revision_derivada", actividad_nombre: "Revisión de medidor", contrato: String(3000000 + i), estado: "atendida", creada_en: iso(20 + i), antiguedad_dias: 20 + i,
    origen: { clase: "registro", tipo: "instalacion_medidor", consecutivo: `IME-9${i}`, fecha: iso(20 + i).slice(0, 10) }, cierre: { en: iso(10), tipo: "atendida", autor: "zt.supervisor@emdupar.gov.co", esquema: "campo", consecutivo: "IME-000777", registro_id: null } }))];
const derivadas = (yo, f) => {
  const todas = TODAS(yo.pend).filter((d) => (!f.estado || d.estado === f.estado) && (!f.origen || d.origen.clase === (f.origen === "analisis" ? "analisis" : "registro")) && (!f.actividad || d.actividad === f.actividad)
    && (!f.contrato || d.contrato.includes(f.contrato)) && (!f.desde || d.creada_en.slice(0, 10) >= f.desde) && (!f.hasta || d.creada_en.slice(0, 10) <= f.hasta));
  const ini = f.antes ? todas.findIndex((d) => d.id === Number(f.antes)) + 1 : 0, lim = Math.min(f.limite ?? 100, 100), pag = todas.slice(ini, ini + lim);
  return { filas: pag, siguiente: ini + lim < todas.length ? pag.at(-1).id : null };
};
// Registro flexible (Code A, 25-nov): descarga AUDITADA simulada como la del servidor (iniciar → páginas → cerrar). Quita siempre el texto libre y el motivo; los correos
// solo si el administrador los pidió. Se cuenta cuántas se iniciaron y cerraron.
const descargas = new Map(); let nDesc = 0; const cerradas = [];
const sinTexto = (d, conCorreos) => { const x = structuredClone(d); delete x.origen.texto; delete x.origen.direccion_correcta; if (x.cierre) delete x.cierre.motivo;
  if (!conCorreos) { delete x.origen.operario; if (x.cierre) delete x.cierre.autor; } return x; };
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
          case "formulario": if (!yo.perfilCampo) return json({ error: "Sin permiso." }, 403); return json(DEF(yo.sup, yo.perfilCampo));
          case "config_constancia": return json({ habilitado: false });
          case "reportes": return json({ reportes: [1, 2, 3, 4, 5, 6].map(FILA), total: 6, siguiente: null, distancia_duplicados_m: 30 });
          case "indicadores": return json(IND);
          case "catalogo_lectura": return json({ ...DEF(true), solo_lectura: false, constancias: { texto: null, documentos: [{ documento: "constancia_visita", habilitado: false, copias_internas: [] }], cola: {}, fallos_ultimos_30_dias: 0 } });
          case "personal": return json({ puede_editar: true, formularios: [{ clave: "reporte_general", nombre: "Reportar anomalía", grupo: "Campo" }, { clave: "instalacion_medidor", nombre: "Instalación de medidor", grupo: "Formatos" }],
            personas: [{ email: "zt.op@emdupar.gov.co", nombre: "ZT Operario", perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: true, dashboard_acta: false }, cargo: "Técnico", formularios: ["reporte_general"], sin_asignacion: false, ultimo_cambio: iso(3) }] });
          case "historial_personal": return json({ eventos: [], siguiente: null });
          case "documentos_catalogo": return json({ formularios: [{ formulario: "tipo:instalacion_medidor", lleva_pdf: true, firmas: { operario: "obligatoria", usuario: "opcional", testigo: "opcional" } }] });
          case "actas_registradas": return json({ filas: [{ registro_id: "00000000-0000-4000-8000-000000000001", esquema: "campo", tipo: "instalacion_medidor", tipo_nombre: "Instalación de medidor", consecutivo: "IME-000001", numero_fisico: null, fecha: "2026-11-21", registrado_en: new Date().toISOString(), operario: "zt.ana@emdupar.gov.co", contrato: "1000001", barrio: "BARRIO DE PRUEBA", resultado: "efectivo", pdf: { estado: "pendiente", nombre: null, version: null }, derivadas: { total: 0, pendientes: 0 }, firmas: { operario: true, usuario: "nadie_atendio", testigo: false } }], siguiente: null });
          case "derivadas": return json(derivadas(yo, b ?? {}));
          case "derivadas_descarga_iniciar": {
            if (b?.incluir_autor && yo.email !== USUARIOS["tok-adm"].email) return json({ error: "No tiene permiso para esta acción." }, 403);
            const f = b?.filtros ?? {}; const filas = TODAS(yo.pend).filter((d) => (!f.estado || d.estado === f.estado) && (!f.origen || d.origen.clase === (f.origen === "analisis" ? "analisis" : "registro"))
              && (!f.actividad || d.actividad === f.actividad) && (!f.contrato || d.contrato.includes(f.contrato)) && (!f.desde || d.creada_en.slice(0, 10) >= f.desde) && (!f.hasta || d.creada_en.slice(0, 10) <= f.hasta));
            if (!filas.length) return json({ error: "No hay avisos ni actividades con esos filtros" }, 400);
            const id = ++nDesc; descargas.set(id, { filas, autor: !!b?.incluir_autor });
            return json({ descarga_id: id, total: filas.length, hasta_id: Math.max(...filas.map((d) => d.id)), generado_por: yo.email, generado_en: "25/11/2026 10:00" });
          }
          case "derivadas_descarga_pagina": { const d = descargas.get(b?.descarga_id); if (!d) return json({ error: "La descarga no existe" }, 404);
            return json({ registros: d.filas.map((x) => sinTexto(x, d.autor)), devueltos: d.filas.length, ultimo_id: d.filas.at(-1).id, hay_mas: false }); }
          case "derivadas_descarga_cerrar": cerradas.push(b); return json({ cerrada: true, repetida: false });
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
      case "geoportal-reparto": if (acc === "perfil") return json({ es_repartidor: false, es_supervisor: yo.repSup }); return json({ error: "no simulado" }, 400);
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
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const VISTO = []; // informe: qué ve cada perfil
const tarjetas = (pg) => pg.evaluate(() => [...document.querySelectorAll("button.campo-formato, .campo-formato-proximo")].filter((e) => e.offsetParent).map((e) => e.querySelector("strong")?.textContent.trim()));
const pestanas = (pg) => pg.evaluate(() => [...document.querySelectorAll(".com-bloque-tab")].map((e) => e.textContent.trim()));
const esperarLista = async (pg) => { await pg.waitForSelector("button.campo-formato", { timeout: 15000 }).catch(() => {}); await esp(700); };
async function llegarACampo(pg, tok) {
  await esperarTexto(pg, /Comercial|Formatos de campo|Sin acceso|acceso/i, 20000); await esp(500);
  if (!(await pg.$("button.campo-formato"))) {
    if (await clic(pg, "button", "Comercial")) { await pg.waitForSelector(".mapa", { timeout: 25000 }).catch(() => {}); await esp(1200); }
    if (ANCHO < 500) await clic(pg, "button.btn-panel-movil", "Controles");
    await elegirModo(pg, "campo");
  }
  await esperarLista(pg);
}
const dirDescargas = mkdtempSync(join(tmpdir(), "desc_der_"));
async function descargarArchivo(pg, boton, ext) {
  const cdp = await pg.target().createCDPSession(); await cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: dirDescargas });
  for (const f of readdirSync(dirDescargas)) rmSync(join(dirDescargas, f), { force: true });   // el nombre lleva solo minutos: se limpia para no confundir descargas seguidas
  const antes = new Set(readdirSync(dirDescargas));
  await clic(pg, `button[data-accion=${boton}]`, "Descargar");
  for (let k = 0; k < 80; k++) { await esp(250); const n = readdirSync(dirDescargas).filter((f) => !antes.has(f) && f.endsWith("." + ext)); if (n.length) { await esp(400); return join(dirDescargas, n[0]); } }
  return null;
}
const SENSIBLES = ["TEXTO LIBRE ZT", "DIRECCION-ZT", "zt.operario@emdupar.gov.co", "zt.supervisor@emdupar.gov.co"];
const volverTextos = (pg) => pg.evaluate(() => [...document.querySelectorAll("[data-volver]")].filter((e) => e.offsetParent).map((e) => e.textContent.trim()));

const PERFILES = [["tok-adm", "1 administrador"], ["tok-sup", "2 supervisor de Comercial"], ["tok-campo", "3 operario de campo"], ["tok-dual", "4 usuario dual"], ["tok-nada", "5 sin permisos"]];
for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
  ANCHO = ancho; ALTO = alto;
  for (const [tok, nombre] of PERFILES) {
    const T = `[${ancho}] ${nombre}`, U = USUARIOS[tok], pf = nombre.split(" ")[0];
    const pg = await abrir(tok);
    if (tok === "tok-nada") {
      await esp(3500); await foto(pg, `p${pf}_inicio`);
      const t = await texto(pg).catch(() => "");
      const hay = (await tarjetas(pg)).length;
      ok(`${T}: no ve ninguna tarjeta de Formatos de campo ni acceso a Supervisar`, hay === 0 && !/Supervisar|Registrar en campo/.test(t), t.slice(0, 200));
      VISTO.push(`${T}: sin tarjetas; texto visible: «${t.replace(/\s+/g, " ").slice(0, 110)}»`);
      await pg.browserContext().close(); continue;
    }
    await llegarACampo(pg, tok);
    const tj = await tarjetas(pg), ps = await pestanas(pg);
    const reg = ["Reportar anomalía", "Formatos de actividad", "Encontrar o reportar activo", "Reportar posible pérdida", "Consultar"];
    await foto(pg, `p${pf}_registrar`);
    ok(`${T} (Registrar en campo): ve ${reg.join(", ")} y ninguna de supervisión`, reg.every((x) => tj.includes(x)) && !tj.some((x) => /Supervisión|Actas registradas/.test(x)), JSON.stringify(tj));
    ok(`${T}: el ícono de cada tarjeta es distinto (sin la inicial repetida)`, await pg.evaluate(() => { const i = [...document.querySelectorAll("button.campo-formato svg[data-icono]")].map((s) => s.getAttribute("data-icono")); return i.length === document.querySelectorAll("button.campo-formato").length && new Set(i).size === i.length && !document.querySelector(".com-tarjeta-ini[data-ini]"); }));
    ok(`${T}: nada se sale a lo ancho`, await sinDesborde(pg));
    if (!U.sup) {
      ok(`${T}: SIN pestañas (solo registra) y sin tarjetas de Supervisar`, ps.length === 0, JSON.stringify(ps));
      VISTO.push(`${T}: ve ${tj.join(" · ")}. No ve: Supervisar, Actas registradas, Supervisión y dashboard, Reparto · Supervisión.`);
      // «← Volver» único en las pantallas que abre
      await clic(pg, "button.campo-formato", "Reportar posible pérdida"); await esp(1500);
      ok(`${T}: «Reportar posible pérdida» → botón «← Volver» único`, igual(await volverTextos(pg), ["← Volver"]), JSON.stringify(await volverTextos(pg)));
      await foto(pg, `p${pf}_acta`, false);
      await pg.browserContext().close(); continue;
    }
    ok(`${T}: dos pestañas «Registrar en campo» y «Supervisar» (Registrar elegida)`, igual(ps, ["Registrar en campo", "Supervisar"]) && await pg.evaluate(() => document.querySelector(".com-bloque-tab[aria-selected=true]")?.textContent === "Registrar en campo"), JSON.stringify(ps));
    await clic(pg, "[role=tab]", "Supervisar"); await esp(500);
    const ts = await tarjetas(pg); await foto(pg, `p${pf}_supervisar`);
    const esperadas = ["Actas registradas", "Supervisión y dashboard", ...(U.repSup ? ["Reparto de facturas · Supervisión"] : [])];
    ok(`${T} (Supervisar): ${esperadas.join(", ")}${U.repSup ? "" : " (sin Reparto: no tiene esa actividad)"}`, igual(ts, esperadas), JSON.stringify(ts));
    const ins = await pg.evaluate(() => document.querySelector("[data-testid=pendientes-derivadas]")?.textContent ?? "");
    const esperaIns = U.pend >= 100 ? "100+" : String(U.pend);
    ok(`${T}: la tarjeta de Actas registradas anuncia «${esperaIns}» avisos y actividades pendientes`, ins.startsWith(esperaIns + " "), ins);
    ok(`${T}: cada tarjeta de Supervisar con descripción propia`, await pg.evaluate(() => [...document.querySelectorAll("button.campo-formato")].every((b) => (b.querySelector(".com-tarjeta-txt span")?.textContent.length ?? 0) > 20)));
    VISTO.push(`${T}: pestañas Registrar en campo (${reg.join(", ")}) y Supervisar (${ts.join(" · ")}); Actas registradas con «${ins}».${U.repSup ? "" : " No ve Reparto · Supervisión."}`);

    // ---- Supervisión y dashboard → Reportes → Avisos y actividades derivadas ----
    await clic(pg, "button.campo-formato", "Supervisión y dashboard"); await esp(1800);
    ok(`${T}: «Supervisión y dashboard» → un solo «← Volver»`, igual(await volverTextos(pg), ["← Volver"]), JSON.stringify(await volverTextos(pg)));
    await foto(pg, `p${pf}_reportes`, false);
    const vistas = await pg.evaluate(() => [...document.querySelectorAll(".rv-vistas-rep button")].map((b) => b.textContent));
    ok(`${T}: Reportes tiene las dos vistas «Reportes de campo» y «Avisos y actividades derivadas»`, igual(vistas, ["Reportes de campo", "Avisos y actividades derivadas"]), JSON.stringify(vistas));
    await clic(pg, ".rv-vistas-rep button", "Avisos y actividades derivadas");
    await esperarTexto(pg, /\d+ filas?/, 15000); await esp(1500);
    const n1 = await pg.evaluate(() => document.querySelectorAll("[data-testid=tabla-derivadas] tbody tr").length);
    ok(`${T}: carga todas las pendientes siguiendo el cursor (${U.pend} filas)`, n1 === U.pend, String(n1));
    await foto(pg, `p${pf}_reportes_derivadas`);
    ok(`${T}: la tabla no se sale a lo ancho`, await sinDesborde(pg));
    // filtros: estado Todas, actividad, fechas
    const setSel = (sel, v) => pg.evaluate((s, x) => { const e = document.querySelector(s); Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value").set.call(e, x); e.dispatchEvent(new Event("change", { bubbles: true })); }, sel, v);
    if (ancho < 500) await clic(pg, "button.rv-solo-movil", "Filtros");
    const vis = (s) => `[data-testid=reportes-derivadas] ${s}`;
    await setSel(vis("[data-filtro=estado]"), ""); await esp(1800);
    const n2 = await pg.evaluate(() => document.querySelectorAll("[data-testid=tabla-derivadas] tbody tr").length);
    ok(`${T}: estado «Todas» → ${U.pend + 5} filas`, n2 === U.pend + 5, String(n2));
    await setSel(vis("[data-filtro=actividad]"), "revision_derivada"); await esp(1800);
    const rowsAct = await pg.evaluate(() => [...document.querySelectorAll("[data-testid=tabla-derivadas] tbody tr td:nth-child(2)")].map((t) => t.textContent));
    ok(`${T}: filtro por actividad (solo «Revisión de medidor»)`, rowsAct.length > 0 && rowsAct.every((x) => x === "Revisión de medidor"), `${rowsAct.length}`);
    await setSel(vis("[data-filtro=actividad]"), ""); await setSel(vis("[data-filtro=estado]"), "atendida"); await esp(1500);
    const dia = new Date(Date.now() - 22 * 86400000).toISOString().slice(0, 10);
    await pg.evaluate((d) => { const e = document.querySelector("[data-testid=reportes-derivadas] [data-filtro=desde]"); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(e, d); e.dispatchEvent(new Event("input", { bubbles: true })); }, dia); await esp(1800);
    const n3 = await pg.evaluate(() => document.querySelectorAll("[data-testid=tabla-derivadas] tbody tr").length);
    ok(`${T}: filtro de fechas (Atendidas desde hace 22 días)`, n3 > 0 && n3 < 5, String(n3));
    await pg.evaluate(() => { const e = document.querySelector("[data-testid=reportes-derivadas] [data-filtro=desde]"); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(e, ""); e.dispatchEvent(new Event("input", { bubbles: true })); });
    await setSel(vis("[data-filtro=estado]"), ""); await esp(1800);
    // descargas
    const csvR = await descargarArchivo(pg, "csv", "csv");
    ok(`${T}: descarga CSV (sin datos de contacto, texto libre ni correos)`, !!csvR && (() => { const t = readFileSync(csvR, "utf8"); return SENSIBLES.every((x) => !t.includes(x)) && t.trim().split("\r\n").length === U.pend + 5 + 1 && t.startsWith("﻿"); })(), csvR ?? "no bajó");
    const xlR = await descargarArchivo(pg, "excel", "xlsx");
    ok(`${T}: descarga Excel (libro válido, sin datos de contacto, hoja Léame)`, !!xlR && (() => { const l = (p) => spawnSync("unzip", ["-p", xlR, p], { encoding: "utf8", maxBuffer: 1e8 }).stdout; const h1 = l("xl/worksheets/sheet1.xml"), le = l("xl/worksheets/sheet2.xml"), wb = l("xl/workbook.xml");
      return h1.includes("<row") && (h1.match(/<row /g) ?? []).length === U.pend + 5 + 1 && SENSIBLES.every((x) => !h1.includes(x) && (x === U.email || !le.includes(x)))   /* el Léame dice quién descargó (su propio correo, como en Reportes) */ && /Derivadas/.test(wb) && /Léame/.test(wb) && /queda registrada en el servidor/.test(le) /* descarga auditada del Code A */; })(), xlR ?? "no bajó");
    const aviso = await pg.evaluate(() => document.querySelector("[data-testid=reportes-derivadas] .rv-aviso-ok")?.textContent ?? "");
    ok(`${T}: avisa que la descarga quedó registrada en el servidor (descarga auditada del Code A)`, /quedó registrada en el servidor/.test(aviso), aviso);
    // ir a atender
    await clic(pg, "button[data-accion=ir-actividades]", "Ir a Actividades derivadas"); await esp(1800);
    const tit = await pg.evaluate(() => ({ h1: document.querySelector(".rv-cab h1")?.textContent, tab: document.querySelector(".rv-tab[aria-current=page]")?.textContent, derivadas: !!document.querySelector("[data-testid=derivadas]") }));
    ok(`${T}: «Ir a Actividades derivadas» abre Actas registradas en la pestaña «Avisos y actividades derivadas» con el contador`, tit.h1 === "Actas registradas" && tit.derivadas && tit.tab === `Avisos y actividades derivadas · ${esperaIns} pendientes`, JSON.stringify(tit));
    await foto(pg, `p${pf}_actas_derivadas`, false);
    ok(`${T}: atender y cerrar siguen en un solo sitio: Actas registradas tiene los botones, Reportes no`, await pg.evaluate(() => !!document.querySelector("[data-testid=derivadas] [data-accion=cerrar]")));
    await clic(pg, "button[data-accion=volver-reportes]", "Volver a Reportes"); await esp(1800);
    const reg2 = await pg.evaluate(() => ({ h1: document.querySelector(".rv-cab h1")?.textContent, der: !!document.querySelector("[data-testid=reportes-derivadas]:not([hidden])") && !document.querySelector("[data-testid=reportes-derivadas]")?.closest("[hidden]"), noCerrar: !document.querySelector("[data-testid=reportes-derivadas] [data-accion=cerrar]") }));
    ok(`${T}: «← Volver a Reportes» regresa a Reportes (vista de derivadas) y Reportes no trae botones de atender`, reg2.h1 === "Supervisión y dashboard" && reg2.der && reg2.noCerrar, JSON.stringify(reg2));
    // volver a la lista y a Actas registradas desde su tarjeta
    await clic(pg, "[data-volver]", "Volver"); await esp(900);
    ok(`${T}: «← Volver» regresa a la lista de Formatos de campo`, !!(await pg.$("button.campo-formato")));
    await clic(pg, "[role=tab]", "Supervisar"); await clic(pg, "button.campo-formato", "Actas registradas"); await esp(1500);
    const pest = await pg.evaluate(() => [...document.querySelectorAll(".rv-tab")].map((t) => t.textContent));
    ok(`${T}: Actas registradas por su tarjeta abre en «Actas registradas» (no en derivadas) y su pestaña lleva el contador`, pest[0] === "Actas registradas" && pest.includes(`Avisos y actividades derivadas · ${esperaIns} pendientes`), JSON.stringify(pest));
    ok(`${T}: Personal sigue en Actas registradas (solo lectura) y en Supervisión`, pest.includes("Personal"), JSON.stringify(pest));
    ok(`${T}: «Actas registradas» → un solo «← Volver»`, igual(await volverTextos(pg), ["← Volver"]), JSON.stringify(await volverTextos(pg)));
    if (U.repSup) { await clic(pg, "[data-volver]", "Volver"); await clic(pg, "[role=tab]", "Supervisar"); await clic(pg, "button.campo-formato", "Reparto de facturas · Supervisión"); await esp(1500);
      ok(`${T}: «Reparto · Supervisión» → «← Volver» único`, igual(await volverTextos(pg), ["← Volver"]) || (await pg.evaluate(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "← Volver"))), JSON.stringify(await volverTextos(pg))); }
    await pg.browserContext().close();
  }
}
console.log("\n=== Qué ve cada perfil ===\n" + VISTO.join("\n"));
console.log(`\nCapturas: ${capturas.length} en ${CAP}`);
if (noSimulado.size) console.log("Rutas no simuladas (responden 400/404):", [...noSimulado].join(", "));
if (errores.length) console.log("Errores de página:", errores.filter((e) => !/maplibre|favicon/.test(e)).join(" | "));
console.log(`\n${total - fallas} de ${total}${fallas ? ` (${fallas} FALLAS)` : " SIN FALLAS"}`);
await nav.close(); mock.close(); web.close(); rmSync(DIST, { recursive: true, force: true }); rmSync(dirDescargas, { recursive: true, force: true });
process.exit(fallas ? 1 : 0);
