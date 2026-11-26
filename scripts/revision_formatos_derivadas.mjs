// REVISIÓN LOCAL (Code B, 25-nov-2026): la app compilada de la rama campo-formatos-derivadas contra el servidor SIMULADO en 127.0.0.1 (nada llega a Supabase; datos inventados, prefijo ZT).
// Los 5 perfiles se cambian con /perfiles (la página de inicio del servidor). Se mantiene vivo hasta Ctrl+C.
//   node scripts/revision_formatos_derivadas.mjs      (P_MOCK y P_WEB cambian los puertos)
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, existsSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const P_MOCK = Number(process.env.P_MOCK || 55991), P_WEB = Number(process.env.P_WEB || 55992);   // puertos del Code B (55987–55994)      // puertos de Chrome del Code B (55987–55994)
const MOCK = `http://127.0.0.1:${P_MOCK}`;

// ---------- 1. La app compilada, apuntando al simulador ----------
const DIST = mkdtempSync(join(tmpdir(), "app_revision_formatos_"));
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
const ROTULOS = { "tok-adm": "1 · Administrador", "tok-sup": "2 · Supervisor de Comercial", "tok-campo": "3 · Operario de campo (solo registra)", "tok-dual": "4 · Usuario dual (Comercial y Técnica)", "tok-nada": "5 · Sin permisos asignados" };
const web = http.createServer((q, res) => {
  const ruta = q.url.split("?")[0];
  if (ruta === "/perfiles") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Revisión · perfiles</title><body style="font:18px Arial;max-width:560px;margin:24px auto;padding:0 16px"><h1>Revisión local · 5 perfiles</h1><p>Servidor simulado: nada llega a Supabase. Elija un perfil y se abre la app; para cambiar, vuelva a esta página.</p>`
      + Object.entries(ROTULOS).map(([t, n]) => `<p><a style="display:block;padding:16px;border:2px solid #782a27;border-radius:12px;color:#782a27;font-weight:700;text-decoration:none" href="/cambiar/${t}">${n}</a></p>`).join("") + `</body>`);
  }
  const mc = /^\/cambiar\/(tok-[a-z]+)$/.exec(ruta);
  if (mc && USUARIOS[mc[1]]) {
    const t = mc[1], u = USUARIOS[t];
    res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
    return res.end(`<!doctype html><meta charset="utf-8"><script>localStorage.clear();localStorage.setItem("sb-127-auth-token",JSON.stringify({access_token:${JSON.stringify(t)},refresh_token:"r",token_type:"bearer",expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,user:{id:"u",email:${JSON.stringify(u.email)},aud:"authenticated",role:"authenticated",app_metadata:{},user_metadata:{}}}));location.replace("/");</script>`);
  }
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => mock.listen(P_MOCK, "127.0.0.1", a)); await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));


console.log(`\nREVISIÓN LOCAL lista (la app se compiló contra el simulador; nada llega a Supabase):\n  Perfiles:  http://127.0.0.1:${P_WEB}/perfiles\n  App:       http://127.0.0.1:${P_WEB}/   (entra con el último perfil elegido)\nCtrl+C para apagar.`);
process.on("SIGINT", () => { mock.close(); web.close(); rmSync(DIST, { recursive: true, force: true }); process.exit(0); });
