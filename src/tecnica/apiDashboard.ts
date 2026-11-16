import { pedir, ErrorTec } from "./apiTecnica";
import { TEXTO_NO_APLICADO } from "../campo/apiCampo";
import type { FilaDescarga } from "./descargas";

// Cliente de las rutas del Dashboard técnico de la Edge geoportal-tecnica (supervisor y administrador). Aquí NO hay nombres de formularios, variables, plantas ni puntos: todo viene del servidor.
export type FormularioCat = { clave: string; nombre: string; descripcion: string };
export type PlantaCat = { codigo: string; nombre: string; activa: boolean };
export type PuntoCat = { codigo: string; nombre: string; tipo: string; zona: string | null; planta: string | null; numero_informe: number | null; activo: boolean };
export type Catalogo = {
  formularios: FormularioCat[]; plantas: PlantaCat[]; zonas: string[]; puntos: PuntoCat[];
  descarga_max_filas: number; descarga_pagina_max: number; motivo_min: number; motivo_max: number;
};
export type FiltrosRegistros = { desde?: string; hasta?: string; planta?: string; formulario?: string; punto?: string; zona?: string; estado?: "todos" | "vigentes" | "excluidos" };
export type RegistroFila = {
  registro_id: number; lote_id: string; formulario: string; variable: string; variable_nombre: string; unidad: string; decimales: number; valor: number;
  planta: string | null; planta_nombre: string | null; punto: string | null; punto_nombre: string | null; zona: string | null;
  fecha_muestra: string; hora_muestra: string; registrado_en: string; autor: string; fuente: string; fuera_de_rango: "bajo" | "alto" | null;
  excluido: boolean; exclusion_motivo: string | null; exclusion_autor: string | null; exclusion_en: string | null;
  ref_min: number | null; ref_max: number | null; ref_origen: "norma" | "criterio_planta" | null; ref_fuente: string | null;
  // Hora de inicio (pasada 14/11). Opcionales: con la base sin la migración no llegan y la pantalla los deja vacíos.
  inicio_en?: string | null; inicio_origen?: "dispositivo" | "servidor" | null; duracion_seg?: number | null;
};
export type RegistrosResp = { total: number; devueltos: number; registros: RegistroFila[] };
export type ExcluirCuerpo = { lote_id?: string; registro_id?: number; motivo: string; accion: "EXCLUIR" | "REINCLUIR" };
export type ExcluirResp = { id: number; accion: string; alcance: "registro" | "lote"; afectados: number };

export type PerfilPersona = "operador" | "dual" | "supervisor";
export type Persona = { email: string; nombre: string | null; perfil: PerfilPersona; formularios: string[]; dashboard_tecnico: boolean; captura_todo: boolean; activo_tecnica: boolean; ultimo_cambio: string | null };
export type PersonalResp = { formularios: { clave: string; nombre: string }[]; personas: Persona[] };
export type EventoPersonal = {
  id: number; persona: string; persona_nombre: string | null; tipo_evento: "asignar_formulario" | "quitar_formulario" | "activar_tecnica" | "desactivar_tecnica";
  formulario: string | null; motivo: string | null; autor: string; autor_nombre: string | null; creado_en: string; vigente: boolean;
};
export type HistorialResp = { total: number; devueltos: number; eventos: EventoPersonal[] };
export type CambioResp = { persona: string; formulario?: string; asignado?: boolean; activo?: boolean; cambio: boolean };

export type DescargaIniciada = { descarga_id: number; total: number; max: number; formato: "csv" | "xlsx"; filtros: Record<string, string>; incluir_excluidos: boolean; generado_por: string; generado_en: string };
/** Dosis de coagulante registrada desde Entrada (una por envío y planta). */
export type DosisFila = {
  uso_id: number; lote_id: string; formulario: string; tipo_uso: string; quimico: string; quimico_nombre: string; otro_nombre: string | null; nombre_mostrar: string;
  dosis: number; unidad: string; planta: string; planta_nombre: string; fecha_muestra: string; hora_muestra: string; registrado_en: string; autor: string;
  excluido: boolean; exclusion_motivo: string | null; exclusion_autor: string | null; exclusion_en: string | null;
};
export type DosisResp = { total: number; devueltos: number; dosis: DosisFila[] };
export type DescargaPagina = { registros: FilaDescarga[]; devueltos: number; ultimo_id: number | null; hay_mas: boolean };

// ---------- Corte 4: Resumen (avisos y gráficas) y Eventos (valores fuera de referencia con revisión) ----------
export type EstadoRevision = "sin_revisar" | "revisado" | "reabierto";
export type FueraFila = {
  registro_id: number; lote_id: string; formulario: string; formulario_nombre: string; variable: string; variable_nombre: string; unidad: string; decimales: number; valor: number;
  planta: string | null; planta_nombre: string | null; punto: string | null; punto_nombre: string | null; zona: string | null;
  fecha_muestra: string; hora_muestra: string; registrado_en: string; autor: string; fuera_de_rango: "alto" | "bajo";
  ref_min: number | null; ref_max: number | null; ref_origen: "norma" | "criterio_planta" | null; ref_fuente: string | null;
  estado_revision: EstadoRevision; revision_id: number | null; revision_nota: string | null; revisado_por: string | null; revisado_en: string | null;
};
export type FiltrosFuera = { desde?: string; hasta?: string; planta?: string; formulario?: string; punto?: string; origen?: string; estado?: "todos" | "sin_revisar" | "revisados" };
export type FueraResp = { desde: string; hasta: string; total: number; sin_revisar: number; revisados: number; devueltos: number; registros: FueraFila[] };
export type RevisarResp = { revision_id: number; registro_id: number; estado_revision: "revisado" | "reabierto"; revisado_por: string; revisado_en: string; nota: string | null };
export type RefSerie = { ref_min: number | null; ref_max: number | null; origen: "norma" | "criterio_planta"; fuente: string };
export type PuntoSerie = { t: string; v: number; m: "alto" | "bajo" | null; id?: number };
export type Serie = {
  formulario: string; formulario_nombre: string; variable: string; variable_nombre: string; unidad: string; decimales: number;
  planta: string | null; planta_nombre: string | null; punto: string | null; punto_nombre: string | null;
  referencia: RefSerie | null; n: number; fuera: number; recortada: boolean; ultimo: PuntoSerie | null; puntos: PuntoSerie[];
};
export type SeriesResp = { desde: string; hasta: string; dias: number; max_puntos: number; series: Serie[] };

// ---------- Aviso de turbiedad alta (solo supervisor y administrador) ----------
export type AvisoTurbiedadFila = {
  planta: string; planta_nombre: string; variable: string; valor: number; umbral: number; unidad: string; decimales: number; fecha_muestra: string; hora_muestra: string; muestra: string;
};
export type AvisosTurbiedadResp = { umbrales_activos: number; vigencia_horas: number; avisos: AvisoTurbiedadFila[] };
export type UmbralPlanta = { planta: string; planta_nombre: string; umbral: number | null; activo: boolean; desde: string | null; fijado_por: string | null; motivo: string | null; tope: number };
export type UmbralHistorial = { planta: string; planta_nombre: string; umbral: number; activo: boolean; creado_en: string; creado_por: string; motivo: string | null; desactivado_en: string | null; desactivado_por: string | null; motivo_cierre: string | null };
export type UmbralesResp = { variable: string; unidad: string; plantas: UmbralPlanta[]; historial: UmbralHistorial[] };
export type FijarUmbralResp = { planta: string; umbral: number | null; activo: boolean; id: number | null };

// ---------- Corte 5b: ubicación de los puntos de muestreo (pestaña «Puntos») ----------
export type UbicacionVigente = { lat: number; lon: number; exactitud: "verificada" | "aproximada"; fuente: string };
export type UbicacionPendiente = {
  propuesta_id: number; punto: string; nombre: string; zona: string | null; activo: boolean; lat: number; lon: number; precision_m: number;
  autor: string; autor_nombre: string | null; creado_en: string; propia: boolean; vigente: UbicacionVigente | null; distancia_m: number | null; lejos: boolean;
};
export type PuntoUbicado = { codigo: string; nombre: string; zona: string | null; lat: number | null; lon: number | null; exactitud: "verificada" | "aproximada" | null; fuente: string | null; desde: string | null; en_revision: boolean };
export type UbicacionRevisada = { propuesta_id: number; punto: string; nombre: string; decision: "aprobada" | "rechazada"; motivo: string | null; autor: string; revisor: string; revisada_en: string; precision_m: number };
export type UbicacionesResp = { precision_max_m: number; distancia_aviso_m: number; pendientes: UbicacionPendiente[]; puntos: PuntoUbicado[]; revisadas: UbicacionRevisada[] };
export type RevisarUbicacionResp = { propuesta_id: number; punto: string; decision: "aprobar" | "rechazar"; estado: "aprobada" | "rechazada"; ubicacion_id: number | null };

const sinVacios = <T extends object>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== "")) as Partial<T>;

export const apiDash = {
  catalogo: () => pedir<Catalogo>("catalogo"),
  registros: (f: FiltrosRegistros, p: { despuesDe?: number | null; limite?: number } = {}) =>
    pedir<RegistrosResp>("registros", { cuerpo: { ...sinVacios(f), ...(p.despuesDe ? { despues_de: p.despuesDe } : {}), limite: p.limite ?? 50 } }),
  excluir: (c: ExcluirCuerpo) => pedir<ExcluirResp>("excluir", { cuerpo: c }),
  personal: (buscar: string, incluirSupervisores: boolean) => pedir<PersonalResp>("personal", { cuerpo: { buscar, incluir_supervisores: incluirSupervisores } }),
  historial: (persona: string | null, despuesDe: number | null = null, limite = 50) =>
    pedir<HistorialResp>("historial", { cuerpo: { ...(persona ? { persona } : {}), ...(despuesDe ? { despues_de: despuesDe } : {}), limite } }),
  asignar: (persona: string, formulario: string, motivo: string) => pedir<CambioResp>("asignar", { cuerpo: { persona, formulario, ...(motivo ? { motivo } : {}) } }),
  quitar: (persona: string, formulario: string, motivo: string) => pedir<CambioResp>("quitar", { cuerpo: { persona, formulario, motivo } }),
  estado: (persona: string, activo: boolean, motivo: string) => pedir<CambioResp>("estado", { cuerpo: { persona, activo, ...(motivo ? { motivo } : {}) } }),
  fueraReferencia: (f: FiltrosFuera, p: { despuesDe?: number | null; limite?: number } = {}) =>
    pedir<FueraResp>("fuera_referencia", { cuerpo: { ...sinVacios(f), ...(p.despuesDe ? { despues_de: p.despuesDe } : {}), limite: p.limite ?? 50 } }),
  revisar: (registroId: number, accion: "revisado" | "reabierto", nota: string) => pedir<RevisarResp>("revisar", { cuerpo: { registro_id: registroId, accion, ...(nota.trim() ? { nota: nota.trim() } : {}) } }),
  series: (dias: number, planta: string, formulario: string) => pedir<SeriesResp>("series", { cuerpo: { dias, ...sinVacios({ planta, formulario }) }, timeoutMs: 40000 }),
  descargaIniciar: (filtros: FiltrosRegistros, formato: "csv" | "xlsx", incluirExcluidos: boolean) =>
    pedir<DescargaIniciada>("descarga_iniciar", { cuerpo: { filtros: sinVacios({ ...filtros, estado: undefined }), formato, incluir_excluidos: incluirExcluidos } }),
  descargaPagina: (id: number, despuesDe: number | null, limite: number) =>
    pedir<DescargaPagina>("descarga_pagina", { cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 60000 }),
  dosis: (f: FiltrosRegistros, p: { despuesDe?: number | null; limite?: number } = {}) =>
    pedir<DosisResp>("dosis", { cuerpo: { ...sinVacios(f), ...(p.despuesDe ? { despues_de: p.despuesDe } : {}), limite: p.limite ?? 50 } }),
  descargaDosisPagina: (id: number, despuesDe: number | null, limite: number) =>
    pedir<DescargaPagina>("descarga_dosis_pagina", { cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 60000 }),
  avisosTurbiedad: () => pedir<AvisosTurbiedadResp>("avisos_turbiedad"),
  umbralesAviso: () => pedir<UmbralesResp>("umbrales_aviso"),
  fijarUmbralAviso: (planta: string, umbral: number | null, motivo: string) => pedir<FijarUmbralResp>("fijar_umbral_aviso", { cuerpo: { planta, umbral, ...(motivo.trim() ? { motivo: motivo.trim() } : {}) } }),
  ubicaciones: () => pedir<UbicacionesResp>("ubicaciones"),
  revisarUbicacion: (propuestaId: number, decision: "aprobar" | "rechazar", motivo: string) =>
    pedir<RevisarUbicacionResp>("ubicacion_revisar", { cuerpo: { propuesta_id: propuestaId, decision, ...(motivo.trim() ? { motivo: motivo.trim() } : {}) } }),
  descargaCerrar: (id: number, filas: number, resultado: "completa" | "cancelada" | "error") => pedir<{ cerrada: boolean }>("descarga_cerrar", { cuerpo: { descarga_id: id, filas, resultado } }),
};

/** Texto para la persona a partir de un fallo del servidor. */
export function textoError(e: unknown): { texto: string; sesion: boolean } {
  if (!(e instanceof ErrorTec)) return { texto: "Ocurrió un error inesperado. Intente de nuevo.", sesion: false };
  switch (e.tipo) {
    case "red": return { texto: `${e.message} Revise su conexión e intente de nuevo.`, sesion: false };
    case "sesion": return { texto: "Su sesión venció. Inicie sesión de nuevo.", sesion: true };
    case "horario": return { texto: `${e.message} Su cuenta no tiene habilitado el servicio en este momento.`, sesion: false };
    case "denegado": return { texto: "Su cuenta ya no está autorizada en el geoportal.", sesion: false };
    case "permiso": return { texto: e.message, sesion: false };
    case "no_aplicado": return { texto: TEXTO_NO_APLICADO, sesion: false };
    case "servidor": return { texto: "El servidor no pudo completar la operación. Intente de nuevo en unos minutos.", sesion: false };
    default: return { texto: e.message, sesion: false };
  }
}
