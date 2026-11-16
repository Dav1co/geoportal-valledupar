import { pedir } from "./apiTecnica";

// Cliente del geovisor técnico (Técnica fase 1, Corte 6a) en la Edge geoportal-redes. Qué capas ve cada persona, cuáles se encienden al abrir (N-11) y si es
// solo lectura (operador con la casilla del geovisor, N-13) lo decide el SERVIDOR; aquí solo se dibuja lo que venga.

export type GrupoCapa = "acueducto" | "alcantarillado" | "tecnologia" | "actividades" | "calidad" | "reportes" | "comercial" | "analisis";
export type CapaGeovisor = {
  codigo: string; nombre: string; grupo: GrupoCapa; fuente: "tesela" | "geojson" | "preparada" | "contratos"; estado: "activa" | "por_conectar" | "espera_dato";
  nota: string | null; prefijos: string[]; por_fecha: boolean; encendida: boolean;
};
export type PerfilGeovisor = "supervisor_distribucion" | "supervisor_planta" | "operador_distribucion";
export type ConfigGeovisor = {
  perfil: "admin" | "supervisor" | "operador"; completo: boolean; perfiles: PerfilGeovisor[]; hoy: string; rango_meses: number; max_elementos: number;
  zoom: { min: number; red_completa: number; nodos: number; accesorios: number; contratos?: number }; version: number;
  formularios: { danos_fallas: boolean; mantenimiento: boolean }; ficha: boolean;
  compartir?: boolean; contratos_capa?: { filas: number; calculado_en: string } | null;      // Corte 6b
  capas: CapaGeovisor[]; tipos: Record<string, string>; estados?: Record<string, string>; materiales: { codigo: string; nombre: string }[];
  por_perfil: { perfil: PerfilGeovisor; capa: string; encendida: boolean; actualizado_en: string; actualizado_por: string }[] | null;
};
export type CapaDatos = GeoJSON.FeatureCollection & { capa: string; desde: string | null; hasta: string | null; recortada: boolean };

// Corte 6b. La tarjeta del contrato trae DATO PERSONAL (nombre, dirección y barrio): solo se pinta en pantalla; no se guarda, no se descarga ni se imprime.
export type TarjetaContrato = {
  contrato: string; estado: "activo" | "retirado" | "otro" | "sin_dato"; estado_texto: string | null; uso: string | null;
  consumo: { periodo_ultimo: string; promedio: number | null; meses_con_lectura: number; meses: { periodo: string; m3: number | null; sin_dato: boolean; lectura_real: boolean }[] } | null;
  medidor_anios: number | null; tramo: string | null;
  suscriptor: { nombre: string | null; direccion: string | null; barrio: string | null };
  corte: string | null;
};
export type VistaGuardada = { capas: string[]; colores: "tipo" | "material" | "edad"; periodo: { modo: "hoy" | "semana" | "rango"; desde?: string | null; hasta?: string | null };
  lon: number; lat: number; zoom: number; atenuadas: string[] };
export type VistaAbierta = Omit<VistaGuardada, "periodo"> & { id: string; omitidas: string[]; creada_en: string; fechas_cambiadas: boolean; periodo: { modo: "hoy" | "semana" | "rango"; desde: string; hasta: string } };

const F = { funcion: "geoportal-redes" };
export const apiGeovisor = {
  config: () => pedir<ConfigGeovisor>("geovisor", F),
  capa: (capa: string, desde?: string | null, hasta?: string | null) =>
    pedir<CapaDatos>("geovisor_capa", { ...F, qs: { capa, ...(desde ? { desde } : {}), ...(hasta ? { hasta } : {}) } }),
  tarjetaContrato: (contrato: string) => pedir<TarjetaContrato>("contrato_tarjeta", { ...F, qs: { contrato } }),
  compartir: (v: VistaGuardada) => pedir<{ id: string }>("vista_compartir", { ...F, cuerpo: v }),
  abrirVista: (id: string) => pedir<VistaAbierta>("vista_abrir", { ...F, qs: { id } }),
  fijar: (perfil: PerfilGeovisor, capa: string, encendida: boolean, motivo: string) =>
    pedir<{ cambio: boolean }>("geovisor_capas_fijar", { ...F, cuerpo: { perfil, capa, encendida, motivo } }),
};
