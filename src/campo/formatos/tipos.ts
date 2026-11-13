import type { Grupo, Tipo } from "../apiCampo";

// Formatos de campo del Paso D: tipos de reporte con campos propios, fotos con etiqueta, resultado y consecutivo.
// Todo llega del catálogo del servidor (ruta «formulario»); aquí NO hay nombres de formatos, campos ni causales. Los tipos del reporte general traen estas claves vacías.

export type TipoDato = "texto" | "entero" | "decimal" | "si_no" | "opcion" | "opciones" | "dia_hora";
export type OpcionCampo = { codigo: string; nombre: string; activo?: boolean };
/** Condición de pantalla: el campo se muestra solo si el campo `campo` (del mismo formato) vale `es` (true/false para sí-no; un código para una opción). La base NO la verifica. */
export type VisibleSi = { campo: string; es: boolean | string };
export type CampoDef = {
  codigo: string; nombre: string; tipo_dato: TipoDato; obligatorio: boolean; opciones?: OpcionCampo[];
  minimo?: number; maximo?: number; unidad?: string; ayuda?: string; sensible?: boolean; orden?: number; activo?: boolean;
  /** Título de la sección en pantalla (los campos consecutivos con el mismo título forman una sección). Ausente = sin sección (el formulario se pinta plano, como siempre). */
  seccion?: string; visible_si?: VisibleSi;
};
export type FotoDef = { codigo: string; nombre: string; obligatoria: boolean; soporte_inefectiva: boolean; orden: number; activo: boolean };
export type Causal = { codigo: string; nombre: string };
export type Resultado = "efectivo" | "inefectivo";

/** Tipo de reporte con la extensión del Paso D (todo opcional: un servidor sin el Paso D no la entrega). */
export type TipoFormato = Tipo & {
  fotos_min?: number; fotos_max?: number; requiere_contrato?: "si" | "no" | "opcional";
  genera_resultado?: boolean; usa_consecutivo?: boolean;
  campos?: CampoDef[]; fotos?: FotoDef[]; causales?: Causal[];
};

/** Etiqueta reservada para las fotos de más (no se limita a una por reporte; las demás no se repiten). */
export const ETIQUETA_ADICIONAL = "adicional";

/** Respuesta de «crear» con el consecutivo del Paso D (nulo en los tipos que no lo llevan). */
export type ConfirmacionFormato = { id: string; registrado_en: string; repetido: boolean; contrato_verificado: boolean | null; aviso_zona: boolean; consecutivo: string | null; constancia?: string };
export type CuerpoCrearFormato = {
  reporte_id: string; tipo: string; subtipo?: string | null; descripcion?: string | null; contrato?: string | null;
  lat: number; lon: number; precision_m?: number | null; riesgo_inmediato: boolean; origen: "campo" | "escritorio";
  fotos: { orden: number; ruta: string; etiqueta?: string }[];
  datos?: Record<string, unknown> | null; resultado?: Resultado | null; causal?: string | null; orden_trabajo_id?: string | null;
  /** Constancia por correo (opcional; solo en los 4 formatos del acta de revisión o instalación). */
  constancia?: import("../constancia/logica").BloqueConstancia;
};

const lista = <T,>(v: T[] | undefined): T[] => (Array.isArray(v) ? v : []);
export const camposActivos = (t: TipoFormato): CampoDef[] => lista(t.campos).filter((c) => c.activo !== false);
export const etiquetasActivas = (t: TipoFormato): FotoDef[] => lista(t.fotos).filter((f) => f.activo);

/** ¿Es un formato del Paso D? Los del reporte general traen campos y fotos vacíos, sin resultado ni consecutivo. */
export const esFormatoD = (t: TipoFormato): boolean => lista(t.campos).length > 0 || lista(t.fotos).length > 0 || t.genera_resultado === true || t.usa_consecutivo === true;

/** Grupos con solo sus formatos del Paso D activos (los grupos sin ninguno se omiten). Tolera un servidor sin el Paso D: devuelve []. */
export function formatosDisponibles(grupos: Grupo[] | undefined): { grupo: Grupo; tipos: TipoFormato[] }[] {
  const salida: { grupo: Grupo; tipos: TipoFormato[] }[] = [];
  for (const g of grupos ?? []) {
    if (!g.activo) continue;
    const tipos = (g.tipos as TipoFormato[]).filter((t) => t.activo && esFormatoD(t));
    if (tipos.length > 0) salida.push({ grupo: g, tipos });
  }
  return salida;
}

/** Lo contrario: los grupos y tipos que el reporte general SÍ sabe enviar (sin los formatos del Paso D). Para que ReporteGeneral no ofrezca un formato que no sabe pedir. */
export function sinFormatosD(grupos: Grupo[]): Grupo[] {
  return grupos.map((g) => ({ ...g, tipos: g.tipos.filter((t) => !esFormatoD(t as TipoFormato)) })).filter((g) => g.tipos.length > 0);
}
