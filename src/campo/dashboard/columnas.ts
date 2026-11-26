import type { CampoDef, FilaReporte, FormularioRev, OpcionDef } from "./apiRevision";
import { fmtDuracion, fmtInstante, fmtLocal, fmtNumero } from "./formatoRevision";

// REGISTRO DE COLUMNAS (Paso C, sección 7 del encargo): la tabla, el detalle, el filtro de tipo y las descargas leen de AQUÍ. Las columnas base son las que existen para todo formato
// (contrato de D, §4); las propias de cada tipo se GENERAN de las definiciones del catálogo (`campos[]`): agregar un campo al catálogo agrega su columna sin tocar pantallas.
// Una clave desconocida en `datos` se muestra genérica (nunca falla). Lógica PURA: se prueba en Node (scripts/prueba_revision.mjs).

export type TipoColumna = "texto" | "numero" | "fecha_hora" | "logico" | "estado" | "etiqueta" | "etiquetas";
export type Contexto = { estados: Map<string, string> };
export type Columna = {
  clave: string; etiqueta: string; tipo: TipoColumna; origen: "base" | "dato";
  porOmision: boolean; ordenable: boolean; filtrable: boolean; enDescarga: boolean;
  /** Valor crudo para ordenar y para el Excel (número, texto, booleano o fecha ISO). */
  valor: (f: FilaReporte) => string | number | boolean | null;
  /** Texto para pantalla y CSV. */
  texto: (f: FilaReporte, c: Contexto) => string;
  unidad?: string;
};

const si = (b: boolean | null | undefined) => (b === null || b === undefined ? "" : b ? "Sí" : "No");
const nombreEstado = (f: FilaReporte, c: Contexto) => c.estados.get(f.estado) ?? f.estado;
const fecha = (f: FilaReporte) => (f.registrado_local ? fmtLocal(f.registrado_local) : fmtInstante(f.registrado_en));
/** Pasada 14/11 · inicio (hora en que se abrió el formulario) y duración hasta el registro (fin). Vacíos en los reportes de antes. */
const hayInicio = (f: FilaReporte) => !!(f.inicio_local || f.inicio_en);
export const textoInicio = (f: FilaReporte): string => !hayInicio(f) ? "" : `${f.inicio_local ? fmtLocal(f.inicio_local) : fmtInstante(f.inicio_en)}${f.inicio_origen === "dispositivo" ? " (celular)" : ""}`;
export function duracionMin(f: FilaReporte): number | null {
  if (f.duracion_min !== undefined && f.duracion_min !== null) return f.duracion_min;
  if (!f.inicio_en || !f.registrado_en) return null;
  const ms = Date.parse(f.registrado_en) - Date.parse(f.inicio_en);
  return Number.isFinite(ms) ? Math.round(ms / 6000) / 10 : null;
}
export const textoDuracion = (f: FilaReporte): string => { const m = duracionMin(f); return m === null ? "" : fmtDuracion(Math.max(0, m) * 60); };

/** Registro flexible (25-nov): «XY digitado — registrado desde otro punto», «Sin ubicación del dispositivo» o «En el sitio (GPS)»; vacío en los reportes anteriores. */
export function textoRegistro(f: Pick<FilaReporte, "xy_manual" | "sin_ubicacion_dispositivo">): string {
  if (f.xy_manual === null || f.xy_manual === undefined) return "";
  const partes = [f.xy_manual ? "XY digitado — registrado desde otro punto" : "En el sitio (GPS)"];
  if (f.sin_ubicacion_dispositivo) partes.push("sin ubicación del dispositivo");
  return partes.join(" · ");
}

/** Columnas base. `conPasoD`: hay datos del Paso D en la respuesta (consecutivo, resultado, causal, datos propios): se muestran por omisión solo entonces. */
export function columnasBase(conPasoD = false): Columna[] {
  const c = (x: Omit<Columna, "origen" | "filtrable"> & { filtrable?: boolean }): Columna => ({ origen: "base", filtrable: false, ...x });
  return [
    c({ clave: "registrado_en", etiqueta: "Fecha y hora", tipo: "fecha_hora", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.registrado_local ?? f.registrado_en, texto: (f) => fecha(f) }),
    c({ clave: "inicio", etiqueta: "Inicio", tipo: "fecha_hora", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.inicio_local ?? f.inicio_en ?? null, texto: textoInicio }),
    c({ clave: "duracion", etiqueta: "Duración", tipo: "numero", porOmision: true, ordenable: true, enDescarga: true, unidad: "min", valor: (f) => duracionMin(f), texto: textoDuracion }),
    c({ clave: "inicio_origen", etiqueta: "Origen del inicio", tipo: "etiqueta", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.inicio_origen ?? null,
        texto: (f) => (f.inicio_origen === "dispositivo" ? "Celular" : f.inicio_origen === "servidor" ? "Servidor" : "") }),
    c({ clave: "consecutivo", etiqueta: "Consecutivo", tipo: "texto", porOmision: conPasoD, ordenable: true, enDescarga: true, valor: (f) => f.consecutivo ?? null, texto: (f) => f.consecutivo ?? "" }),
    c({ clave: "tipo", etiqueta: "Tipo", tipo: "etiqueta", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.tipo.nombre, texto: (f) => f.tipo.nombre }),
    c({ clave: "grupo", etiqueta: "Grupo", tipo: "etiqueta", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.grupo.nombre, texto: (f) => f.grupo.nombre }),
    c({ clave: "subtipo", etiqueta: "Subtipo", tipo: "etiqueta", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.subtipo?.nombre ?? null, texto: (f) => f.subtipo?.nombre ?? "" }),
    c({ clave: "resultado", etiqueta: "Resultado", tipo: "etiqueta", porOmision: conPasoD, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.resultado ?? null, texto: (f) => (f.resultado === "efectivo" ? "Efectivo" : f.resultado === "inefectivo" ? "Inefectivo" : "") }),
    c({ clave: "causal", etiqueta: "Causal", tipo: "etiqueta", porOmision: conPasoD, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.causal?.nombre ?? null, texto: (f) => f.causal?.nombre ?? "" }),
    c({ clave: "estado", etiqueta: "Estado", tipo: "estado", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.estado, texto: nombreEstado }),
    c({ clave: "riesgo_inmediato", etiqueta: "Riesgo inmediato", tipo: "logico", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.riesgo_inmediato, texto: (f) => si(f.riesgo_inmediato) }),
    c({ clave: "oculto", etiqueta: "Oculto", tipo: "logico", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.oculto, texto: (f) => si(f.oculto) }),
    c({ clave: "fuera_de_zona", etiqueta: "Fuera de zona", tipo: "logico", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.fuera_de_zona, texto: (f) => si(f.fuera_de_zona) }),
    c({ clave: "contrato", etiqueta: "Contrato", tipo: "texto", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.contrato ?? null, texto: (f) => f.contrato ?? "" }),
    c({ clave: "contrato_verificado", etiqueta: "Contrato verificado", tipo: "logico", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.contrato_verificado ?? null, texto: (f) => si(f.contrato_verificado) }),
    c({ clave: "n_fotos", etiqueta: "Fotos", tipo: "numero", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.n_fotos, texto: (f) => String(f.n_fotos) }),
    c({ clave: "grupo_duplicados", etiqueta: "Posibles duplicados", tipo: "texto", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.tamano_grupo ?? 0,
        texto: (f) => (f.grupo_duplicados ? `${f.tamano_grupo ?? "?"} en el grupo` : "") }),
    c({ clave: "origen", etiqueta: "Origen", tipo: "etiqueta", porOmision: true, ordenable: true, enDescarga: true, valor: (f) => f.origen, texto: (f) => (f.origen === "campo" ? "Campo" : f.origen === "escritorio" ? "Escritorio" : f.origen) }),
    // Registro flexible (25-nov): la marca va en la tabla por omisión; la ubicación del dispositivo y la distancia, solo en la descarga y el detalle
    c({ clave: "registro_desde", etiqueta: "Registro", tipo: "etiqueta", porOmision: true, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => textoRegistro(f) || null, texto: (f) => textoRegistro(f) }),
    c({ clave: "fotos_adjuntadas", etiqueta: "Fotos adjuntadas", tipo: "numero", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.fotos_adjuntadas ?? 0, texto: (f) => (f.fotos_adjuntadas ? String(f.fotos_adjuntadas) : "") }),
    // Consultar direcciones (25-nov): las dos direcciones del contrato al registrar, junto a la encontrada en terreno
    c({ clave: "direccion_contrato", etiqueta: "Dirección del contrato", tipo: "texto", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.direccion_contrato ?? null, texto: (f) => f.direccion_contrato ?? "" }),
    c({ clave: "barrio_contrato", etiqueta: "Barrio del contrato", tipo: "texto", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.barrio_contrato ?? null, texto: (f) => f.barrio_contrato ?? "" }),
    c({ clave: "direccion_catastro", etiqueta: "Dirección del contrato en el catastro", tipo: "texto", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.direccion_catastro ?? null, texto: (f) => f.direccion_catastro ?? "" }),
    c({ clave: "barrio_catastro", etiqueta: "Barrio en el catastro", tipo: "texto", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.barrio_catastro ?? null, texto: (f) => f.barrio_catastro ?? "" }),
    c({ clave: "direccion", etiqueta: "Dirección", tipo: "texto", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.direccion ?? null, texto: (f) => f.direccion ?? "" }),
    c({ clave: "barrio", etiqueta: "Barrio", tipo: "texto", porOmision: false, ordenable: true, filtrable: true, enDescarga: true, valor: (f) => f.barrio ?? null, texto: (f) => f.barrio ?? "" }),
    c({ clave: "referencia", etiqueta: "Referencia", tipo: "texto", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.referencia ?? null, texto: (f) => f.referencia ?? "" }),
    c({ clave: "autor", etiqueta: "Autor", tipo: "texto", porOmision: true, ordenable: true, enDescarga: false, valor: (f) => f.autor ?? null, texto: (f) => f.autor ?? "" }),
    c({ clave: "descripcion", etiqueta: "Descripción", tipo: "texto", porOmision: true, ordenable: false, enDescarga: true, valor: (f) => f.descripcion ?? null, texto: (f) => f.descripcion ?? "" }),
    c({ clave: "precision_m", etiqueta: "Precisión (m)", tipo: "numero", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.precision_m ?? null, texto: (f) => (f.precision_m === null || f.precision_m === undefined ? "" : fmtNumero(f.precision_m, 1)) }),
    c({ clave: "orden_trabajo_id", etiqueta: "Orden de trabajo", tipo: "texto", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.orden_trabajo_id ?? null, texto: (f) => f.orden_trabajo_id ?? "" }),
    c({ clave: "lat", etiqueta: "Latitud", tipo: "numero", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.lat, texto: (f) => fmtNumero(f.lat, 6) }),
    c({ clave: "lon", etiqueta: "Longitud", tipo: "numero", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.lon, texto: (f) => fmtNumero(f.lon, 6) }),
    c({ clave: "lat_registro", etiqueta: "Latitud del dispositivo", tipo: "numero", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.lat_registro ?? null, texto: (f) => (f.lat_registro == null ? "" : fmtNumero(f.lat_registro, 6)) }),
    c({ clave: "lon_registro", etiqueta: "Longitud del dispositivo", tipo: "numero", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.lon_registro ?? null, texto: (f) => (f.lon_registro == null ? "" : fmtNumero(f.lon_registro, 6)) }),
    c({ clave: "distancia_registro_m", etiqueta: "Distancia al punto (m)", tipo: "numero", porOmision: false, ordenable: true, enDescarga: true, valor: (f) => f.distancia_registro_m ?? null, texto: (f) => (f.distancia_registro_m == null ? "" : fmtNumero(f.distancia_registro_m, 0)) }),
    c({ clave: "id", etiqueta: "Identificador", tipo: "texto", porOmision: false, ordenable: false, enDescarga: true, valor: (f) => f.id, texto: (f) => f.id }),
  ];
}

/** Tipos de dato que el registro sabe formatear. Uno nuevo (que el servidor agregue mañana) se muestra como texto y se avisa en consola: nunca es un error. */
const TIPOS_CONOCIDOS = ["texto", "entero", "decimal", "si_no", "opcion", "opciones", "dia_hora"];
const avisados = new Set<string>();
const avisar = (m: string) => { if (!avisados.has(m)) { avisados.add(m); console.warn(m); } };

const nombreOpcion = (ops: OpcionDef[] | undefined, cod: unknown) => ops?.find((o) => o.codigo === cod)?.nombre ?? String(cod);
/** «2026-11-05T14:30» → «05/11/2026 14:30». */
const diaHora = (v: unknown) => { const s = String(v); return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(s) ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)} ${s.slice(11, 16)}` : s; };

/** Texto de UN valor de campo propio según su tipo de dato. Lo ausente es vacío. */
export function textoDeDato(def: Pick<CampoDef, "tipo_dato" | "opciones" | "unidad">, v: unknown): string {
  if (v === null || v === undefined || v === "") return "";
  const u = def.unidad ? ` ${def.unidad}` : "";
  switch (def.tipo_dato) {
    case "entero": case "decimal": return typeof v === "number" ? `${fmtNumero(v, def.tipo_dato === "entero" ? 0 : 4)}${u}` : String(v);
    case "si_no": return v === true || v === "true" ? "Sí" : v === false || v === "false" ? "No" : String(v);
    case "opcion": return nombreOpcion(def.opciones, v);
    case "opciones": return Array.isArray(v) ? v.map((x) => nombreOpcion(def.opciones, x)).join("; ") : String(v);
    case "dia_hora": return diaHora(v);
    default:
      if (!TIPOS_CONOCIDOS.includes(def.tipo_dato)) avisar(`Tipo de dato desconocido «${def.tipo_dato}»: se muestra como texto.`);
      return typeof v === "object" ? JSON.stringify(v) : String(v);
  }
}
const tipoColumna = (t: string): TipoColumna => (t === "entero" || t === "decimal" ? "numero" : t === "si_no" ? "logico" : t === "dia_hora" ? "fecha_hora" : t === "opcion" ? "etiqueta" : t === "opciones" ? "etiquetas" : "texto");

/** Columnas propias del tipo (campos NO sensibles; los sensibles nunca llegan en `datos`). */
export function columnasPropias(campos: CampoDef[] | undefined): Columna[] {
  return (campos ?? []).filter((d) => !d.sensible).map((d) => ({
    clave: `dato:${d.codigo}`, etiqueta: d.unidad ? `${d.nombre} (${d.unidad})` : d.nombre, tipo: tipoColumna(d.tipo_dato), origen: "dato" as const,
    porOmision: false, ordenable: true, filtrable: d.tipo_dato === "opcion" || d.tipo_dato === "si_no", enDescarga: true,
    valor: (f: FilaReporte) => { const v = f.datos?.[d.codigo]; return v === undefined || v === null ? null : typeof v === "number" || typeof v === "boolean" ? v : Array.isArray(v) ? v.join("; ") : String(v); },
    texto: (f: FilaReporte) => textoDeDato(d, f.datos?.[d.codigo]),
  }));
}

/** Definiciones de campos por tipo: de `definiciones` (supervisor: incluye los desactivados) y, si el servidor aún no las trae, de `grupos[].tipos[].campos` (solo activos). */
export function camposDelTipo(def: Pick<FormularioRev, "grupos"> & Partial<Pick<FormularioRev, "definiciones">>, tipo: string): CampoDef[] {
  const d = def.definiciones?.find((x) => x.tipo === tipo);
  if (d) return d.campos;
  for (const g of def.grupos) for (const t of g.tipos) if (t.codigo === tipo) return t.campos ?? [];
  return [];
}
export function fotosDelTipo(def: Pick<FormularioRev, "grupos"> & Partial<Pick<FormularioRev, "definiciones">>, tipo: string): { codigo: string; nombre: string }[] {
  return def.definiciones?.find((x) => x.tipo === tipo)?.fotos ?? [];
}

/** Pares etiqueta/valor de TODOS los datos propios de un reporte, en el orden del catálogo; las claves que el catálogo no conoce van al final como genéricas (código = valor). */
export function paresDeDatos(datos: Record<string, unknown> | undefined, campos: CampoDef[]): { etiqueta: string; valor: string; generica: boolean }[] {
  const salida: { etiqueta: string; valor: string; generica: boolean }[] = [];
  const d = datos ?? {};
  for (const c of campos) { if (c.sensible) continue; const t = textoDeDato(c, d[c.codigo]); if (t !== "") salida.push({ etiqueta: c.nombre, valor: t, generica: false }); }
  for (const k of Object.keys(d)) {
    if (campos.some((c) => c.codigo === k)) continue;
    avisar(`Clave desconocida en los datos del reporte: «${k}» (se muestra genérica).`);
    salida.push({ etiqueta: k, valor: typeof d[k] === "object" ? JSON.stringify(d[k]) : String(d[k]), generica: true });
  }
  return salida;
}

/** Columnas de la TABLA: las base de la lista (con `conPasoD` según los datos), más las propias del tipo solo cuando hay un filtro de tipo activo. */
export const MAX_PROPIAS_TABLA = 10;
export function columnasTabla(base: Columna[], propias: Columna[], conFiltroTipo: boolean): Columna[] {
  // Con formatos de ~60 campos (acta de revisión o instalación) la tabla muestra solo las primeras MAX_PROPIAS_TABLA propias; el detalle y las descargas traen todas.
  return [...base.filter((c) => c.porOmision), ...(conFiltroTipo ? propias.slice(0, MAX_PROPIAS_TABLA) : [])];
}

/** Columnas de la DESCARGA: base marcadas `enDescarga` (el autor solo si se pidió y el servidor lo envía) y, con un tipo filtrado, sus columnas propias. */
export function columnasDescarga(base: Columna[], propias: Columna[], opciones: { conTipo: boolean; incluirAutor: boolean }): Columna[] {
  const b = base.filter((c) => c.enDescarga || (c.clave === "autor" && opciones.incluirAutor));
  return [...b, ...(opciones.conTipo ? propias.filter((c) => c.enDescarga) : [])];
}

/** ¿Alguna fila trae algo del Paso D? (para mostrar consecutivo, resultado y causal). */
export const hayPasoD = (filas: FilaReporte[]): boolean => filas.some((f) => f.consecutivo || f.resultado || f.causal || (f.datos && Object.keys(f.datos).length > 0));

const colador = new Intl.Collator("es", { sensitivity: "base", numeric: true });
/** Orden estable por columna; vacíos al final en ambos sentidos. */
export function ordenar(filas: FilaReporte[], col: Columna | null, dir: "asc" | "desc"): FilaReporte[] {
  if (!col) return filas;
  const k = dir === "asc" ? 1 : -1;
  return filas.map((f, i) => ({ f, i, v: col.valor(f) })).sort((a, b) => {
    const va = a.v, vb = b.v;
    if (va === null || va === "") return vb === null || vb === "" ? a.i - b.i : 1;
    if (vb === null || vb === "") return -1;
    const r = typeof va === "number" && typeof vb === "number" ? va - vb : typeof va === "boolean" && typeof vb === "boolean" ? Number(va) - Number(vb) : colador.compare(String(va), String(vb));
    return r !== 0 ? r * k : a.i - b.i;
  }).map((x) => x.f);
}
