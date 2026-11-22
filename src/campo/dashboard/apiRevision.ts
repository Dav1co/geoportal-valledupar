import { pedir, ErrorCampo, TEXTO_NO_APLICADO } from "../apiCampo";

// Cliente de las rutas de supervisión de geoportal-campo para la pantalla «Revisión de reportes» (Paso C). Usa el `pedir` de apiCampo (renueva la sesión una vez ante un 401,
// distingue «sin respuesta», traduce 429). Aquí NO hay etiquetas de tipos, grupos, estados ni campos propios: todo llega del catálogo del servidor.

export type Par = { codigo: string; nombre: string };
export type Resultado = "efectivo" | "inefectivo";
/** Una fila de «reportes». Las claves del Paso D (consecutivo, resultado, causal, datos…) son opcionales: un servidor sin el Paso D no las entrega. */
export type FilaReporte = {
  id: string; seq: number; tipo: Par; grupo: Par; subtipo: Par | null; descripcion: string | null; contrato: string | null; contrato_verificado: boolean | null;
  lat: number; lon: number; precision_m: number | null; riesgo_inmediato: boolean; origen: string; fuera_de_zona: boolean; autor?: string; registrado_en: string;
  estado: string; estado_desde: string | null; oculto: boolean; reporte_original_id: string | null; grupo_duplicados: string | null; tamano_grupo: number | null; n_fotos: number;
  consecutivo?: string | null; resultado?: Resultado | null; causal?: Par | null; orden_trabajo_id?: string | null; datos?: Record<string, unknown>; tiene_datos_sensibles?: boolean;
  /** Solo en filas de descarga: hora de pared de Bogotá «AAAA-MM-DDTHH:MM:SS». */
  registrado_local?: string;
  /** Pasada 14/11: hora en que se abrió el formulario (del celular: origen «dispositivo»). Fin = registrado_en. Nulos en los reportes de antes. */
  inicio_en?: string | null; inicio_origen?: "dispositivo" | "servidor" | null;
  /** Solo en filas de descarga (pasada 14/11): inicio en hora de pared de Bogotá y duración en minutos calculada por la base. */
  inicio_local?: string | null; duracion_min?: number | null;
};
export type ListaResp = { reportes: FilaReporte[]; total: number; siguiente: number | null; distancia_duplicados_m: number };
export type FiltrosServidor = {
  tipo?: string; grupo?: string; estado?: string; desde?: string; hasta?: string; riesgo_inmediato?: boolean; ocultos?: "no" | "si" | "todos";
  resultado?: Resultado; causal?: string; consecutivo?: string; cursor?: number; limite?: number;
};

export type TipoDato = "texto" | "entero" | "decimal" | "si_no" | "opcion" | "opciones" | "dia_hora";
export type OpcionDef = { codigo: string; nombre: string; activo?: boolean };
export type CampoDef = { codigo: string; nombre: string; tipo_dato: TipoDato | string; unidad?: string; opciones?: OpcionDef[]; sensible?: boolean; activo?: boolean; orden?: number };
export type FotoDefRev = { codigo: string; nombre: string; activo?: boolean };
export type EstadoDef = { codigo: string; nombre: string; orden: number; activo: boolean; exige_motivo: boolean; cambio_manual: boolean };
export type ParametroDef = { clave: string; valor: number; unidad: string; descripcion: string; minimo: number | null; maximo: number | null; actualizado_en?: string | null; actualizado_por?: string | null };
export type SubtipoCat = { codigo: string; nombre: string; orden: number; activo: boolean };
export type TipoCat = { codigo: string; nombre: string; orden: number; activo: boolean; subtipos: SubtipoCat[]; campos?: CampoDef[] };
export type GrupoCat = { codigo: string; nombre: string; orden: number; activo: boolean; tipos: TipoCat[] };
/** Lo que entrega `formulario` al supervisor y, con incluir_inactivos, al administrador. */
export type FormularioRev = {
  perfil: "admin" | "supervisor" | "reportante";
  puede: { reportar: boolean; crear_desde_escritorio: boolean; supervisar: boolean; administrar_catalogo: boolean };
  limites: { max_fotos: number; max_descripcion?: number };
  zona: { lat_min: number; lat_max: number; lon_min: number; lon_max: number };
  grupos: GrupoCat[]; estados: EstadoDef[] | null; parametros: ParametroDef[] | null;
  definiciones?: { tipo: string; campos: CampoDef[]; fotos: FotoDefRev[] }[] | null;
};

export type EventoRep = { id: number; tipo_evento: string; estado_nuevo: string | null; reporte_original_id: string | null; motivo: string | null; autor: string; creado_en: string };
export type FotoRep = { orden: number; tamano_bytes: number; tipo_mime: string; registrada_en: string; etiqueta?: string | null; etiqueta_nombre?: string | null };
export type Cercano = { id: string; distancia_m: number; registrado_en: string; estado: string };
export type DetalleResp = { reporte: FilaReporte; campos: CampoDef[]; fotos: FotoRep[]; eventos: EventoRep[]; cercanos: Cercano[]; distancia_duplicados_m: number };
export type SensiblesResp = { reporte_id: string; datos: Record<string, unknown>; campos: CampoDef[] };

export type IndicadoresResp = {
  total: number; visibles: number; ocultos: number; corte: string; filtros: FiltrosServidor; serie_recortada: boolean;
  por_dia: { dia: string; n: number }[]; por_tipo: { tipo: Par; grupo: Par; n: number }[]; por_estado: { estado: string; nombre: string; n: number }[];
  revision: { revisados: number; sin_revisar: number; mediana_segundos: number | null; promedio_segundos: number | null; p90_segundos: number | null };
};
export type DescargaIniciada = { descarga_id: number; total: number; formato: "csv" | "xlsx"; filtros: FiltrosServidor; incluir_autor: boolean; hasta_seq: number; generado_por: string; generado_en: string };
/** Fila de la RPC de descarga (plana; el correo del autor solo viene si el administrador lo pidió). Sin rutas de Storage, URLs ni claves. */
export type FilaDescarga = {
  seq: number; id: string; registrado_local: string; tipo_codigo: string; tipo_nombre: string; grupo_nombre: string; subtipo_nombre: string | null; consecutivo: string | null; resultado: Resultado | null;
  causal_nombre: string | null; estado: string; estado_nombre: string | null; oculto: boolean; riesgo_inmediato: boolean; fuera_de_zona: boolean; contrato: string | null; contrato_verificado: boolean | null;
  descripcion: string | null; lat: number; lon: number; precision_m: number | null; origen: string; n_fotos: number; grupo_duplicados: string | null; tamano_grupo: number | null;
  reporte_original_id: string | null; orden_trabajo_id: string | null; datos: Record<string, unknown>; autor?: string;
  inicio_local?: string | null; inicio_origen?: string | null; duracion_min?: number | null;   // pasada 14/11
};
export type DescargaPagina = { registros: FilaDescarga[]; devueltos: number; ultimo_seq: number | null; hay_mas: boolean };
export type CambioParametro = { clave: string; antes: number; despues: number };

/** Pasada 14/11 · lectura completa del supervisor (y del administrador): catálogo con inactivos, parámetros y estado de constancias. No escribe nada. */
export type EstadoConstanciaLectura = { texto: { version: number; borrador: boolean; texto: string } | null; documentos: { documento: string; habilitado: boolean; copias_internas: string[] }[]; cola: Record<string, number>; fallos_ultimos_30_dias: number };
export type CatalogoLectura = FormularioRev & { solo_lectura: boolean; constancias: EstadoConstanciaLectura };

/** Pasada 14/11 · Personal de Comercial. */
export type FormularioPersonal = { clave: string; nombre: string; grupo: string };
export type PersonaCampo = {
  email: string; nombre: string | null; perfil: "operario" | "supervisor";
  permisos: { campo: boolean; dashboard_campo: boolean; acta: boolean; dashboard_acta: boolean };
  cargo: string | null; formularios: string[]; sin_asignacion: boolean; ultimo_cambio: string | null;
  /** Personal y cuadrillas (21-nov): llegan con el paquete (a) del Code A; un servidor anterior no los manda. */
  area?: CodigoNombreActivo | null; cuadrilla?: CuadrillaRef | null; actividades?: ActividadPersona[]; propia?: boolean;
  /** 22-nov (Code A, 5972d2d, «solo operarios»): ¿quien consulta le cambia el área y el cargo? ¿y los formularios, la cuadrilla y las actividades? Un servidor anterior no los manda. */
  puede_area_cargo?: boolean; puede_asignar?: boolean;
};
export type CodigoNombre = { codigo: string; nombre: string };
export type CodigoNombreActivo = CodigoNombre & { activa: boolean };
export type CuadrillaRef = { id: number; nombre: string; activa?: boolean };
export type OrigenActividad = "cuadrilla" | "propia" | "ambas";
export type ActividadPersona = CodigoNombreActivo & { origen: OrigenActividad };
/** Qué puede cambiar quien consulta, campo por campo (21-nov). `cuadrilla` = poner o sacar a una persona; `cuadrillas` = gestionar las cuadrillas y sus actividades. */
export type PuedePersonal = { cargo: boolean; area: boolean; cuadrilla: boolean; cuadrillas: boolean; actividades: boolean; formularios: boolean; catalogos: boolean };
export type PersonalResp = {
  puede_editar: boolean; formularios: FormularioPersonal[]; personas: PersonaCampo[];
  yo?: string; areas?: CodigoNombre[]; cuadrillas?: CuadrillaRef[]; actividades?: CodigoNombre[]; puede?: PuedePersonal;
};
export type TipoCambioPersonal = "fijar_cargo" | "asignar_formulario" | "quitar_formulario" | "fijar_area" | "fijar_cuadrilla" | "asignar_actividad" | "quitar_actividad";
export type TipoEventoCuadrilla = "cuadrilla_crear" | "cuadrilla_renombrar" | "cuadrilla_desactivar" | "cuadrilla_activar" | "cuadrilla_agregar_actividad" | "cuadrilla_quitar_actividad";
export type Cuadrilla = { id: number; nombre: string; activa: boolean; miembros: { email: string; nombre: string | null }[]; n_miembros?: number; actividades: CodigoNombre[]; creada_en: string; autor: string };
export type TipoCambioCuadrilla = "crear" | "renombrar" | "desactivar" | "activar" | "agregar_actividad" | "quitar_actividad";
export type ItemCatalogo = { codigo: string; nombre: string; activa: boolean; orden: number };
export type CatalogosResp = { areas: ItemCatalogo[]; actividades: ItemCatalogo[] };
export type PersonaActividad = { email: string; nombre: string | null; cuadrilla: { id: number; nombre: string } | null; origen: OrigenActividad };
export type EventoPersonal = {
  id: number; persona: string | null; nombre: string | null; tipo_evento: TipoCambioPersonal | TipoEventoCuadrilla; formulario: string | null; formulario_nombre: string | null;
  cargo: string | null; motivo: string | null; autor: string; creado_en: string; vigente: boolean;
  /** 21-nov: el área, la cuadrilla, la actividad o el nombre nuevo del cambio (null si no aplica); en los eventos de una cuadrilla, la cuadrilla. */
  valor_codigo?: string | null; valor_nombre?: string | null; cuadrilla?: { id: number; nombre: string } | null;
  /** Llave única en pantalla («p:<id>» de persona, «c:<id>» de cuadrilla: los id de las dos tablas pueden repetirse). En el historial de una cuadrilla, `entra` dice si la persona entró o salió. */
  clave?: string; entra?: boolean;
};
export type HistorialPersonalResp = { eventos: EventoPersonal[]; siguiente: number | null };

const sinVacios = <T extends object>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== "" && v !== null)) as Partial<T>;

export const apiRev = {
  formulario: (incluirInactivos = false) => pedir<FormularioRev>("formulario", incluirInactivos ? { qs: { incluir_inactivos: "1" } } : {}),
  reportes: (f: FiltrosServidor) => pedir<ListaResp>("reportes", { cuerpo: sinVacios(f), timeoutMs: 60000 }),
  reporte: (id: string) => pedir<DetalleResp>("reporte", { qs: { id } }),
  foto: (id: string, orden: number) => pedir<{ url: string; expira_en: string }>("foto", { qs: { id, orden: String(orden) } }),
  sensibles: (id: string) => pedir<SensiblesResp>("datos_sensibles", { qs: { id } }),
  estado: (id: string, estado: string, motivo: string) => pedir<{ id: string; estado: string; estado_anterior: string }>("estado", { cuerpo: { id, estado, motivo } }),
  ocultar: (id: string, motivo: string) => pedir<{ id: string; oculto: boolean }>("ocultar", { cuerpo: { id, motivo } }),
  reincluir: (id: string, motivo: string) => pedir<{ id: string; oculto: boolean }>("reincluir", { cuerpo: { id, motivo } }),
  duplicado: (id: string, originalId: string, motivo: string) => pedir<{ id: string; estado: string; reporte_original_id: string }>("duplicado", { cuerpo: { id, original_id: originalId, motivo } }),
  indicadores: (f: FiltrosServidor) => pedir<IndicadoresResp>("indicadores", { cuerpo: sinVacios(f), timeoutMs: 60000 }),
  descargaIniciar: (filtros: FiltrosServidor, formato: "csv" | "xlsx", incluirAutor: boolean) =>
    pedir<DescargaIniciada>("descarga_iniciar", { cuerpo: { filtros: sinVacios(filtros), formato, incluir_autor: incluirAutor }, timeoutMs: 60000 }),
  descargaPagina: (id: number, despuesDe: number | null, limite: number) => pedir<DescargaPagina>("descarga_pagina", { cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 90000 }),
  descargaCerrar: (id: number, filas: number, resultado: "completa" | "cancelada" | "error") => pedir<{ cerrada: boolean }>("descarga_cerrar", { cuerpo: { descarga_id: id, filas, resultado } }),
  parametro: (cambios: { clave: string; valor: number }[], motivo: string) => pedir<{ cambios: CambioParametro[] }>("parametro", { cuerpo: { cambios, motivo } }),
  catalogoLectura: () => pedir<CatalogoLectura>("catalogo_lectura"),
  personal: (buscar = "") => pedir<PersonalResp>("personal", { cuerpo: buscar.trim() ? { buscar: buscar.trim() } : {} }),
  personalCambiar: (c: { persona: string; tipo: TipoCambioPersonal; formulario?: string | null; cargo?: string | null; motivo?: string | null; area?: string; actividad?: string }) =>
    pedir<{ id: number; cambio: boolean }>("personal_cambiar", { cuerpo: sinVacios(c) }),
  /** `cuadrilla_id: null` saca a la persona de su cuadrilla: va explícito (sinVacios lo quitaría). */
  fijarCuadrilla: (persona: string, cuadrillaId: number | null, motivo: string | null) =>
    pedir<{ id: number; cambio: boolean }>("personal_cambiar", { cuerpo: { persona, tipo: "fijar_cuadrilla", cuadrilla_id: cuadrillaId, ...(motivo ? { motivo } : {}) } }),
  historialPersonal: (f: { persona?: string; cuadrilla_id?: number; despues_de?: number; limite?: number }) => pedir<HistorialPersonalResp>("historial_personal", { cuerpo: sinVacios(f) }),
  cuadrillas: (incluirInactivas = false) => pedir<{ cuadrillas: Cuadrilla[] }>("cuadrillas", { cuerpo: incluirInactivas ? { incluir_inactivas: true } : {} }),
  cuadrillaCambiar: (c: { tipo: TipoCambioCuadrilla; cuadrilla_id?: number; nombre?: string; actividad?: string; motivo?: string }) =>
    pedir<{ id?: number; cambio?: boolean }>("cuadrilla_cambiar", { cuerpo: sinVacios(c) }),
  catalogos: () => pedir<CatalogosResp>("catalogos", { cuerpo: {} }),
  catalogoCambiar: (c: { catalogo: "area" | "actividad"; tipo: "crear" | "renombrar" | "desactivar" | "activar"; codigo?: string; nombre?: string; motivo?: string }) =>
    pedir<{ codigo?: string; cambio?: boolean }>("catalogo_cambiar", { cuerpo: sinVacios(c) }),
  personalActividad: (actividad: string) => pedir<{ personas: PersonaActividad[] }>("personal_actividad", { cuerpo: { actividad } }),
  catalogo: (entidad: string, accion: string, datos: Record<string, unknown>) => pedir<{ entidad: string; accion: string; antes: unknown; despues: unknown }>("catalogo", { cuerpo: { entidad, accion, datos } }),
};

/** Texto para la persona a partir de un fallo del servidor (los mensajes de validación de la base ya vienen en español). */
export function textoError(e: unknown): { texto: string; sesion: boolean } {
  if (!(e instanceof ErrorCampo)) return { texto: "Ocurrió un error inesperado. Intente de nuevo.", sesion: false };
  switch (e.tipo) {
    case "red": return { texto: `${e.message} Revise su conexión e intente de nuevo.`, sesion: false };
    case "sesion": return { texto: "Su sesión venció. Inicie sesión de nuevo.", sesion: true };
    case "horario": return { texto: `${e.message} Su cuenta no tiene habilitado el servicio en este momento.`, sesion: false };
    case "denegado": return { texto: "Su cuenta ya no está autorizada en el geoportal.", sesion: false };
    case "permiso": return { texto: "No tiene permiso para esta acción.", sesion: false };
    case "servidor": return { texto: "El servidor no pudo completar la operación. Intente de nuevo en unos minutos.", sesion: false };
    case "limite": return { texto: e.message, sesion: false };
    case "no_aplicado": return { texto: TEXTO_NO_APLICADO, sesion: false };
    default: return { texto: e.message, sesion: false };
  }
}
