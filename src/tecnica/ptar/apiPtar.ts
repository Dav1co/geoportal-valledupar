import { pedir } from "../apiTecnica";

// Cliente de las rutas de la PTAR (PTAR-1) de la Edge geoportal-tecnica. Quién puede qué lo decide el servidor (alcance PTAP / PTAR, D6); aquí solo se dibuja.
export type InstalacionPtar = { codigo: string; nombre: string; tipo: "potable" | "residual"; elementos: number };
export type PerfilPtar = { perfil: "admin" | "supervisor" | "operador"; activa: boolean; admin: boolean; ptap: boolean; ptar: boolean; instalaciones: InstalacionPtar[] };
export type TipoElemento = "perimetro" | "laguna" | "tramo" | "punto_medicion" | "pozo" | "descarga";
export type PropElemento = { codigo: string; tipo: TipoElemento; nombre: string; alias?: string; orden: number; activo?: string; origen: "dibujo" | "redes";
  tipo_laguna?: string; tren?: string; punto?: string; estado: EstadoElemento };
export type EstadoElemento = "sin_variables" | "sin_registros" | "sin_dato_reciente" | "con_datos" | "fuera";
export type Parametro = { codigo: string; nombre: string; unidad: string; decimales: number; grupo: string; valor?: number | null; muestra_ts?: string | null;
  ref_min?: number | null; ref_max?: number | null; estado: "sin_registros" | "sin_dato_reciente" | "sin_referencia" | "normal" | "fuera" };
export type MapaPtar = {
  instalacion: { codigo: string; nombre: string; tipo: string; horas_sin_dato: number };
  caja: [number, number, number, number] | null; por_tipo: Partial<Record<TipoElemento, number>>; total: number;
  elementos: GeoJSON.FeatureCollection<GeoJSON.Geometry, PropElemento>;
};
export type FichaElemento = {
  codigo: string; tipo: TipoElemento; tipo_texto: string; nombre: string; alias?: string; orden: number; origen: "dibujo" | "redes"; activo?: string;
  atributos: Record<string, unknown>; medida: { area_m2?: number; area_ha?: number; longitud_m?: number; lat?: number; lon?: number };
  instalacion: { codigo: string; nombre: string; tipo: string }; desde?: { codigo: string; nombre: string }; hasta?: { codigo: string; nombre: string };
  punto?: { codigo: string; nombre: string }; versiones: number; alias_historial: { alias: string | null; motivo: string; autor: string; creado_en: string }[];
  estado: EstadoElemento; indicadores: Parametro[]; horas_sin_dato?: number; creado_en: string;
};
export type PersonaAlcance = { persona: string; perfil: string | null; ptap: boolean; ptar: boolean };
export type AlcancesResp = { personas: PersonaAlcance[]; historial: { persona: string; alcance: "ptap" | "ptar"; tipo: "asignar" | "quitar"; motivo: string; autor: string; creado_en: string }[]; regla: string };

export const apiPtar = {
  perfil: () => pedir<PerfilPtar>("ptar_perfil"),
  mapa: (instalacion = "ptar") => pedir<MapaPtar>("ptar_mapa", { qs: { instalacion }, timeoutMs: 40000 }),
  elemento: (codigo: string) => pedir<FichaElemento>("ptar_elemento", { qs: { codigo } }),
  alias: (codigo: string, alias: string, motivo: string) => pedir<{ codigo: string; antes: string | null; alias: string | null }>("ptar_alias", { cuerpo: { codigo, alias, motivo } }),
  alcances: () => pedir<AlcancesResp>("ptar_alcances"),
  alcance: (persona: string, alcance: "ptap" | "ptar", accion: "asignar" | "quitar", motivo: string) =>
    pedir<PersonaAlcance>("ptar_alcance", { cuerpo: { persona, alcance, accion, motivo } }),
};
