import { pedir } from "./apiTecnica";

// Cliente del geovisor técnico (Técnica fase 1, Corte 6a) en la Edge geoportal-redes. Qué capas ve cada persona, cuáles se encienden al abrir (N-11) y si es
// solo lectura (operador con la casilla del geovisor, N-13) lo decide el SERVIDOR; aquí solo se dibuja lo que venga.

export type GrupoCapa = "acueducto" | "alcantarillado" | "tecnologia" | "actividades" | "calidad" | "reportes" | "comercial" | "analisis";
export type CapaGeovisor = {
  codigo: string; nombre: string; grupo: GrupoCapa; fuente: "tesela" | "geojson" | "preparada" | "contratos" | "referencia";      // «referencia» (Corte 9a): capas del Plan Maestro, en tesela propia; no son activos
  estado: "activa" | "por_conectar" | "espera_dato";
  nota: string | null; prefijos: string[]; por_fecha: boolean; encendida: boolean;
};
export type PerfilGeovisor = "supervisor_distribucion" | "supervisor_planta" | "operador_distribucion";
export type ConfigGeovisor = {
  perfil: "admin" | "supervisor" | "operador"; completo: boolean; perfiles: PerfilGeovisor[]; hoy: string; rango_meses: number; max_elementos: number;
  zoom: { min: number; red_completa: number; nodos: number; accesorios: number; contratos?: number }; version: number;
  formularios: { danos_fallas: boolean; mantenimiento: boolean }; ficha: boolean;
  edad_ref?: boolean | null;      // Corte 10: hay amarre con la valoración (la edad de los activos sin fecha de instalación sale de la fecha regulatoria); solo supervisores
  contratos_corte?: string | null;      // Corte 7a: AAAAMMDD del último corte de la cartera diaria (solo supervisores)
  compartir?: boolean;      // Corte 6b. Corte 6c: ya no hay «contratos_capa»: la tesela de contratos se arma al vuelo, siempre al día
  capas: CapaGeovisor[]; tipos: Record<string, string>; estados?: Record<string, string>; materiales: { codigo: string; nombre: string }[];
  por_perfil: { perfil: PerfilGeovisor; capa: string; encendida: boolean; actualizado_en: string; actualizado_por: string }[] | null;
};
export type CapaDatos = GeoJSON.FeatureCollection & { capa: string; desde: string | null; hasta: string | null; recortada: boolean };

// Corte 6b. La tarjeta del contrato trae DATO PERSONAL (nombre, dirección y barrio): solo se pinta en pantalla; no se guarda, no se descarga ni se imprime.
export type TarjetaContrato = {
  contrato: string; estado: "activo" | "suspendido" | "cortado" | "retirado" | "otro" | "sin_dato"; estado_texto: string | null; uso: string | null;
  datos_personales?: boolean;      // Corte 7a: false para el supervisor de planta (sin nombre ni dirección)
  consumo: { periodo_ultimo: string; promedio: number | null; meses_con_lectura: number; meses: { periodo: string; m3: number | null; sin_dato: boolean; lectura_real: boolean }[] } | null;
  medidor_anios: number | null; tramo: string | null;
  sector_hidraulico?: { sector: number; subsector?: string | null } | null;      // Corte 9a: el sector del contrato es el de su tramo (por geometría); 9a-bis: el oficial
  suscriptor: { nombre: string | null; direccion: string | null; barrio: string | null };
  corte: string | null;
};
export type VistaGuardada = { capas: string[]; colores: "tipo" | "material" | "edad"; periodo: { modo: "hoy" | "semana" | "rango"; desde?: string | null; hasta?: string | null };
  lon: number; lat: number; zoom: number; atenuadas: string[] };
export type VistaAbierta = Omit<VistaGuardada, "periodo"> & { id: string; omitidas: string[]; creada_en: string; fechas_cambiadas: boolean; periodo: { modo: "hoy" | "semana" | "rango"; desde: string; hasta: string } };

// Corte 9a. Tarjeta de un elemento de una capa de referencia (Plan Maestro 2014). Las filas llegan ya rotuladas; «series» trae la campaña medida de 2014
// (puntos [fecha, m.c.a.]) o el perfil horario del modelo (25 valores, hora 0 a 24). La presión del modelo NO es una medición: «advertencia» lo dice.
export type NivelPresion = "baja_roja" | "baja_naranja" | "normal" | "alta_naranja" | "alta_roja" | "sin_dato";
export type FilaRef = { r: string; v: string | number; u?: string };
export type SerieRef = { nombre: string; unidad: string; eje: "tiempo" | "hora"; escenario?: string; puntos?: [string, number][]; valores?: number[] };
export type TarjetaRef = { capa: string; llave: string; titulo: string; subtitulo?: string; origen?: string; advertencia?: string; nivel?: NivelPresion; activo?: string;
  filas: FilaRef[]; series?: SerieRef[] };

const F = { funcion: "geoportal-redes" };
export const apiGeovisor = {
  referencia: (capa: string, llave: string) => pedir<TarjetaRef>("geovisor_referencia", { ...F, qs: { capa, llave } }),
  config: () => pedir<ConfigGeovisor>("geovisor", F),
  capa: (capa: string, desde?: string | null, hasta?: string | null) =>
    pedir<CapaDatos>("geovisor_capa", { ...F, qs: { capa, ...(desde ? { desde } : {}), ...(hasta ? { hasta } : {}) } }),
  /** Corte 9b (ajuste final): TODOS los daños abiertos o en atención, sin límite de fecha, para el modo «Afectaciones» (solo supervisores y administrador). */
  danosAbiertos: () => pedir<GeoJSON.FeatureCollection & { capa: string; total: number; recortada: boolean }>("afectaciones_danos", F),
  tarjetaContrato: (contrato: string) => pedir<TarjetaContrato>("contrato_tarjeta", { ...F, qs: { contrato } }),
  compartir: (v: VistaGuardada) => pedir<{ id: string }>("vista_compartir", { ...F, cuerpo: v }),
  abrirVista: (id: string) => pedir<VistaAbierta>("vista_abrir", { ...F, qs: { id } }),
  fijar: (perfil: PerfilGeovisor, capa: string, encendida: boolean, motivo: string) =>
    pedir<{ cambio: boolean }>("geovisor_capas_fijar", { ...F, cuerpo: { perfil, capa, encendida, motivo } }),
};
