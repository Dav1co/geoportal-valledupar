import { pedir } from "./apiTecnica";

// Cliente del geovisor técnico (Técnica fase 1, Corte 6a) en la Edge geoportal-redes. Qué capas ve cada persona, cuáles se encienden al abrir (N-11) y si es
// solo lectura (operador con la casilla del geovisor, N-13) lo decide el SERVIDOR; aquí solo se dibuja lo que venga.

export type GrupoCapa = "acueducto" | "alcantarillado" | "tecnologia" | "actividades" | "calidad" | "reportes" | "comercial" | "analisis";
export type CapaGeovisor = {
  codigo: string; nombre: string; grupo: GrupoCapa; fuente: "tesela" | "geojson" | "preparada"; estado: "activa" | "por_conectar" | "espera_dato";
  nota: string | null; prefijos: string[]; por_fecha: boolean; encendida: boolean;
};
export type PerfilGeovisor = "supervisor_distribucion" | "supervisor_planta" | "operador_distribucion";
export type ConfigGeovisor = {
  perfil: "admin" | "supervisor" | "operador"; completo: boolean; perfiles: PerfilGeovisor[]; hoy: string; rango_meses: number; max_elementos: number;
  zoom: { min: number; red_completa: number; nodos: number; accesorios: number }; version: number;
  formularios: { danos_fallas: boolean; mantenimiento: boolean }; ficha: boolean;
  capas: CapaGeovisor[]; tipos: Record<string, string>; estados?: Record<string, string>; materiales: { codigo: string; nombre: string }[];
  por_perfil: { perfil: PerfilGeovisor; capa: string; encendida: boolean; actualizado_en: string; actualizado_por: string }[] | null;
};
export type CapaDatos = GeoJSON.FeatureCollection & { capa: string; desde: string | null; hasta: string | null; recortada: boolean };

const F = { funcion: "geoportal-redes" };
export const apiGeovisor = {
  config: () => pedir<ConfigGeovisor>("geovisor", F),
  capa: (capa: string, desde?: string | null, hasta?: string | null) =>
    pedir<CapaDatos>("geovisor_capa", { ...F, qs: { capa, ...(desde ? { desde } : {}), ...(hasta ? { hasta } : {}) } }),
  fijar: (perfil: PerfilGeovisor, capa: string, encendida: boolean, motivo: string) =>
    pedir<{ cambio: boolean }>("geovisor_capas_fijar", { ...F, cuerpo: { perfil, capa, encendida, motivo } }),
};
