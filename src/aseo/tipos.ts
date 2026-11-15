// Tipos de la interventoría de Aseo (Torre C). Todo llega del catálogo del servidor (ruta «formulario»): aquí NO hay nombres de actividades, preguntas ni causales.

export type TipoDato = "texto" | "entero" | "decimal" | "si_no" | "opcion" | "opciones" | "dia_hora";
export type OpcionCriterio = { codigo: string; nombre: string; activo?: boolean };
export type Criterio = {
  codigo: string; nombre: string; seccion?: string | null; tipo_dato: TipoDato; obligatorio: boolean; opciones?: OpcionCriterio[] | null; minimo?: number | null; maximo?: number | null;
  unidad?: string | null; ayuda?: string | null; exige_foto_si?: "si" | "no" | null; etiqueta_foto?: string | null; orden?: number; activo?: boolean;
};
export type FotoDef = { codigo: string; nombre: string; cantidad_min: number; cantidad_max: number; condicional: boolean; soporte_no_realizada: boolean; orden?: number; activo?: boolean };
export type Causal = { codigo: string; nombre: string; activo?: boolean };
export type ServicioDef = { codigo: string; nombre: string; activo?: boolean };
export type Modalidad = { codigo: string; nombre: string; orden?: number; activa: boolean; servicios: ServicioDef[] };
export type Actividad = {
  codigo: string; nombre: string; orden: number; activa: boolean; fotos_max?: number; usa_consecutivo?: boolean;
  modalidades?: Modalidad[]; criterios?: Criterio[]; fotos?: FotoDef[]; causales?: Causal[];
};
export type FormularioAseo = {
  perfil: "admin" | "supervisor" | "auditor"; correo: string; nombre: string | null;
  puede: { capturar: boolean; supervisar: boolean; administrar: boolean };
  ahora: string;
  limites: { max_bytes_foto: number; busqueda_min_caracteres: number; mapa_zoom_inicial: number; distancia_marca_m: number; precision_aviso_m: number };
  zona: { lat_min: number; lat_max: number; lon_min: number; lon_max: number };
  actividades: Actividad[];
};

export type RutaPlan = {
  id: number; codigo: string; servicio: { codigo: string; nombre: string };
  turno: number | null; turno_nombre: string | null; frecuencia: string | null; frecuencia_nombre: string | null; dias: number[] | null;
  hora_inicio: string | null; hora_fin: string | null; sectores: string | null; caracterizacion: string | null; km_ruta: number | null;
  barrios: string[]; geometria: { id: number; version: number; clase: "punto" | "linea" | "area"; completa: boolean } | null;
};
export type PlanResp = { etag: string; ahora?: string; rutas?: RutaPlan[]; sin_cambios?: boolean };
export type MapaResp = { etag: string; type?: "FeatureCollection"; features?: GeoFeature[]; sin_cambios?: boolean };
export type GeoFeature = { type: "Feature"; geometry: { type: string; coordinates: unknown }; properties: { ruta_id: number; codigo: string; clase: string; version: number; completa: boolean } };
export type Cercana = { ruta_id: number; codigo: string; distancia_m: number; dentro: boolean };

export type FotoPreparada = { orden: number; ruta: string; url_subida: string; token: string };
export type Preparacion = { auditoria_id: string; max_bytes_foto: number; tipo_mime: string; ahora: string; fotos: FotoPreparada[] };
export type SeRealizo = "si" | "no" | "parcial";
export type FotoEnvio = { orden: number; ruta: string; etiqueta: string };
export type CuerpoCrear = {
  auditoria_id: string; actividad: string; modalidad: string; ruta: string; se_realizo: SeRealizo; causal?: string | null; datos: Record<string, unknown>; observaciones?: string | null;
  lat: number; lon: number; precision_m?: number | null; lat_inicio?: number | null; lon_inicio?: number | null; precision_inicio_m?: number | null; fotos: FotoEnvio[];
  firmas: { auditor: { imagen_b64: string }; representante: { estado: "firmo" | "se_nego" | "sin_representante"; nombre?: string; imagen_b64?: string } };
  /** Hora del celular al ABRIR el formulario (ISO con zona). La base la valida contra la hora de registro; fuera del sello. */
  inicio_dispositivo?: string | null;
};
export type Confirmacion = {
  id: string; consecutivo: string; registrado_en: string; fecha_servicio: string; repetido: boolean; lejos_de_ruta: boolean; fuera_de_zona: boolean; fuera_de_horario: boolean;
  no_programada_hoy: boolean; sin_trazado: boolean; sello: string; auditor: { nombre: string; correo: string; cargo: string | null };
  inicio_en?: string | null;
};
