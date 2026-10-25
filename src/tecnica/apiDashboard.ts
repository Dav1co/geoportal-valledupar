import { pedir, ErrorTec } from "./apiTecnica";
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
export type DescargaPagina = { registros: FilaDescarga[]; devueltos: number; ultimo_id: number | null; hay_mas: boolean };

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
  descargaIniciar: (filtros: FiltrosRegistros, formato: "csv" | "xlsx", incluirExcluidos: boolean) =>
    pedir<DescargaIniciada>("descarga_iniciar", { cuerpo: { filtros: sinVacios({ ...filtros, estado: undefined }), formato, incluir_excluidos: incluirExcluidos } }),
  descargaPagina: (id: number, despuesDe: number | null, limite: number) =>
    pedir<DescargaPagina>("descarga_pagina", { cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 60000 }),
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
    case "servidor": return { texto: "El servidor no pudo completar la operación. Intente de nuevo en unos minutos.", sesion: false };
    default: return { texto: e.message, sesion: false };
  }
}
