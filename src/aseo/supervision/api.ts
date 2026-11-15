import { pedir } from "../apiAseo";
import { ErrorCampo, avisoDeError } from "../../campo/apiCampo";

// Cliente de las rutas de SUPERVISIÓN de la Edge geoportal-aseo (supervisor y administrador). Aquí no hay nombres de actividades, preguntas, causales ni barrios: todo viene del servidor.
export type TipoNc = "sst" | "no_realizada" | "parcial" | "forma_indebida";
export type EstadoNc = "sin_revisar" | "revisada" | "reabierta";
export type OrigenInicio = "dispositivo" | "servidor";
export type Motivo = { tipo: TipoNc; criterio: string | null; pregunta: string | null; respuesta: string | null };
export type FilaAuditoria = {
  id: string; seq: number; consecutivo: string; registrado_en: string; fecha_servicio: string; ruta_codigo: string; actividad: string; actividad_nombre: string; modalidad_nombre: string; servicio: string; servicio_nombre: string;
  turno_nombre: string | null; barrios: string | null; se_realizo: "si" | "no" | "parcial"; causal_nombre: string | null; autor: string; lejos_de_ruta: boolean; fuera_de_zona: boolean; fuera_de_horario: boolean;
  no_programada_hoy: boolean; sin_trazado: boolean; oculta: boolean; n_fotos: number; nc_tipos: TipoNc[]; nc_estado: EstadoNc | null;
  /** Hora de inicio (pasada 14/11): ausentes mientras el servidor no tenga la actualización; nulas en lo registrado antes. */
  inicio_en?: string | null; inicio_origen?: OrigenInicio | null; duracion_s?: number | null;
};
export type FilaResumen = { id: string; seq: number; consecutivo: string; registrado_en: string; fecha_servicio: string; ruta_codigo: string; actividad_nombre: string; modalidad_nombre: string; se_realizo: "si" | "no" | "parcial"; causal_nombre: string | null; autor: string; nc_tipos: TipoNc[]; nc_motivos: Motivo[]; nc_estado: EstadoNc };
export type Resumen = { pendientes: number; revisadas: number; turnos: { codigo: number; nombre: string }[]; auditores: { email: string; nombre: string | null }[]; registros: FilaResumen[] };
export type Listado = { total: number; pendientes: number; revisadas: number; devueltos: number; registros: FilaAuditoria[] };
export type Detalle = {
  id: string; consecutivo: string; registrado_en: string; fecha_servicio: string; ruta_codigo: string; actividad: string; actividad_nombre: string; modalidad_nombre: string; servicio_nombre: string; turno_nombre: string | null; frecuencia_nombre: string | null;
  barrios: string | null; se_realizo: "si" | "no" | "parcial"; causal_nombre: string | null; observaciones: string | null; autor: string; lat: number; lon: number; precision_m: number | null; distancia_ruta_m: number | null;
  marcas: { lejos_de_ruta: boolean; fuera_de_zona: boolean; fuera_de_horario: boolean; no_programada_hoy: boolean; sin_trazado: boolean }; oculta: boolean; oculta_motivo: string | null; sello: string;
  respuestas: { codigo: string; pregunta: string; texto: string | null }[]; fotos: { orden: number; etiqueta: string; nombre: string }[]; firmas: { rol: string; estado: string; nombre: string | null; cargo: string | null }[];
  nc_estado: EstadoNc | null; nc_motivos: Motivo[]; revisiones: { id: number; tipo_evento: "revisar" | "reabrir"; nota: string | null; autor: string; creado_en: string }[];
  eventos_visibilidad: { tipo_evento: "ocultar" | "reincluir"; motivo: string; autor: string; creado_en: string }[];
  inicio_en?: string | null; inicio_origen?: OrigenInicio | null; duracion_s?: number | null;
};
export type Indicadores = {
  auditorias: number; rutas_auditadas: number; rutas_plan: number; incidencia: { si: number; no: number; parcial: number };
  no_conformes: { auditorias: number; pendientes: number; revisadas: number; por_tipo: Record<TipoNc, number> };
  marcas: { lejos_de_ruta: number; fuera_de_horario: number; fuera_de_zona: number; no_programada_hoy: number; sin_trazado: number };
};
export type ActaDatos = {
  consecutivo: string; registrado_en: string; fecha_servicio: string; sello: string; sigla: string; ruta_codigo: string; actividad_nombre: string; modalidad_nombre: string; servicio: string; servicio_nombre: string;
  sectores: string | null; turno_nombre: string | null; hora_inicio: string | null; hora_fin: string | null; frecuencia_nombre: string | null; km: number | null; se_realizo: "si" | "no" | "parcial"; causal_nombre: string | null; observaciones: string | null;
  respuestas: { pregunta: string; respuesta: string | null }[]; lat: number; lon: number; precision_m: number | null; lat_inicio: number | null; lon_inicio: number | null;
  marcas: Detalle["marcas"]; auditor: { nombre: string | null; correo: string; cargo: string | null; imagen_b64: string | null };
  representante: { estado: "firmo" | "se_nego" | "sin_representante"; nombre: string | null; imagen_b64: string | null }; fotos: { orden: number; etiqueta: string }[];
  inicio_en?: string | null; inicio_origen?: OrigenInicio | null; duracion_s?: number | null;
};
export type Persona = { email: string; nombre: string | null; perfil: "auditor" | "supervisor"; cargo: string | null; actividades: string[]; activo_aseo: boolean; ultimo_cambio: string | null };
export type TipoCambio = "fijar_cargo" | "asignar_actividad" | "quitar_actividad" | "activar_aseo" | "desactivar_aseo";
export type EventoPersonal = { id: number; persona: string; persona_nombre: string | null; tipo_evento: TipoCambio; actividad: string | null; cargo: string | null; motivo: string | null; autor: string; autor_nombre: string | null; creado_en: string; vigente: boolean };
export type DescargaIniciada = { descarga_id: number; total: number; max: number; formato: "csv" | "xlsx"; filtros: Record<string, string>; generado_por: string; generado_en: string; actividad: { codigo: string; nombre: string }; criterios: { codigo: string; nombre: string; tipo_dato: string }[] };
export type FilaDescarga = {
  id: string; seq: number; consecutivo: string; registrado_local: string; fecha_servicio: string; actividad_nombre: string; modalidad_nombre: string; servicio: string; servicio_nombre: string; ruta_codigo: string; turno_nombre: string | null; frecuencia_nombre: string | null;
  barrios: string | null; autor: string; auditor_nombre: string | null; auditor_cargo: string | null; representante_estado: "firmo" | "se_nego" | "sin_representante"; representante_nombre: string | null;
  incidencia: "si" | "no" | "parcial"; causal_nombre: string | null; observaciones: string | null; marcas: string[]; nc_tipos: TipoNc[]; nc_estado: EstadoNc | null; oculta: boolean; oculta_motivo: string | null;
  n_fotos: number; lat: number; lon: number; sello: string; respuestas: Record<string, string | null>;
  inicio_local?: string | null; inicio_origen?: OrigenInicio | null; duracion_min?: number | null;
};
export type DescargaPagina = { registros: FilaDescarga[]; devueltos: number; ultimo_id: number | null; hay_mas: boolean };

const sinVacios = <T extends object>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== "")) as Partial<T>;
export type Filtros = { desde?: string; hasta?: string; actividad?: string; modalidad?: string; servicio?: string; turno?: string; barrio?: string; auditor?: string; incidencia?: string; nc?: string; ocultos?: string };

export const apiSup = {
  resumen: (limite = 50) => pedir<Resumen>("resumen", { qs: { limite: String(limite) } }),
  registros: (f: Filtros, p: { despuesDe?: number | null; limite?: number } = {}) => pedir<Listado>("registros", { cuerpo: { ...sinVacios(f), ...(p.despuesDe ? { despues_de: p.despuesDe } : {}), limite: p.limite ?? 50 } }),
  revisar: (id: string, accion: "revisar" | "reabrir", nota: string) => pedir<{ evento: number; nc_estado: EstadoNc }>("revisar", { cuerpo: { id, accion, ...(nota.trim() ? { nota: nota.trim() } : {}) } }),
  detalle: (id: string) => pedir<Detalle>("detalle", { qs: { id } }),
  fotos: (id: string) => pedir<{ fotos: { orden: number; etiqueta: string; nombre: string; url: string }[] }>("fotos_acta", { qs: { id } }),
  fotoBase64: (id: string, orden: number) => pedir<{ b64: string }>("foto_base64", { qs: { id, orden: String(orden) }, timeoutMs: 40000 }),
  actaDatos: (id: string) => pedir<ActaDatos>("acta_datos", { qs: { id } }),
  gestionar: (id: string, accion: "ocultar" | "reincluir", motivo: string) => pedir<{ evento: number; oculta: boolean }>("gestionar_auditoria", { cuerpo: { id, accion, motivo: motivo.trim() } }),
  indicadores: (f: Filtros) => pedir<Indicadores>("indicadores", { cuerpo: sinVacios(f), timeoutMs: 40000 }),
  personal: (buscar: string, incluirSupervisores: boolean) => pedir<{ actividades: { codigo: string; nombre: string; activa: boolean }[]; personas: Persona[] }>("personal", { cuerpo: { buscar, incluir_supervisores: incluirSupervisores } }),
  cambiar: (persona: string, tipo: TipoCambio, o: { actividad?: string; cargo?: string; motivo?: string } = {}) => pedir<{ evento: number }>("personal_cambiar", { cuerpo: { persona, tipo, ...sinVacios(o) } }),
  historial: (persona: string | null, despuesDe: number | null = null, limite = 50) => pedir<{ total: number; devueltos: number; eventos: EventoPersonal[] }>("historial_personal", { cuerpo: { ...(persona ? { persona } : {}), ...(despuesDe ? { despues_de: despuesDe } : {}), limite } }),
  descargaIniciar: (filtros: Filtros, formato: "csv" | "xlsx") => pedir<DescargaIniciada>("descarga_iniciar", { cuerpo: { filtros: sinVacios(filtros), formato } }),
  descargaPagina: (id: number, despuesDe: number | null, limite: number) => pedir<DescargaPagina>("descarga_pagina", { cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 60000 }),
  descargaCerrar: (id: number, filas: number, resultado: "completa" | "cancelada" | "error") => pedir<{ cerrada: boolean }>("descarga_cerrar", { cuerpo: { descarga_id: id, filas, resultado } }),
};

/** Texto para la persona a partir de un fallo (mismos tipos y avisos que el resto de Aseo). */
export function textoError(e: unknown): { texto: string; sesion: boolean } {
  if (!(e instanceof ErrorCampo)) return { texto: "Ocurrió un error inesperado. Intente de nuevo.", sesion: false };
  return { texto: avisoDeError(e).texto, sesion: e.tipo === "sesion" };
}
