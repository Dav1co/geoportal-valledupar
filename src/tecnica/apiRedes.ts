import { pedir } from "./apiTecnica";

// Cliente de la Edge geoportal-redes (Técnica fase 1, Corte 1b). Solo lectura. Lo que recibe cada perfil lo decide el SERVIDOR:
// el origen y los datos del modelo hidráulico solo llegan a supervisor y administrador; aquí solo se dibuja lo que venga.

export type ActivoCorto = {
  codigo: string; prefijo: string; tipo: string; clase?: string; estado: string; estado_codigo: string; retirado: boolean;
  codigo_anterior?: string; distancia_m?: number; sistema?: string;
};
export type Campo = { clave: string; rotulo: string; unidad?: string; valor?: string | number | boolean };
export type Ficha = {
  perfil: "admin" | "supervisor" | "operador";
  activo: {
    codigo: string; prefijo: string; tipo: string; tipo_catalogo: string; sistema: string; sistema_nombre: string; etapa: string; geometria: string;
    nombre?: string; clase?: string; estado: string; estado_codigo: string; cuenta_vigente: boolean; punteado: boolean; retirado: boolean; oculto: boolean; por_verificar: boolean;
    material?: string; fecha_instalacion?: string; barrio_sector?: string; codigo_anterior?: string; version: number; version_creada_en: string;
    lat: number; lon: number; campos: Campo[];
  };
  origen?: { origen: "emdupar" | "tercero" | "mixto"; aportante?: string; aportante_nombre?: string; tiene_soporte: boolean; nota?: string };
  modelo?: Record<string, unknown>;
  nodo?: { nombre_modelo?: string; nombre_visible: string; tramos: number };
  tramo?: { metodo: string; inicio?: { nombre: string; activo?: ActivoCorto }; fin?: { nombre: string; activo?: ActivoCorto } };
  contratos_enlazados?: number;
  componentes: ActivoCorto[]; parte_de: ActivoCorto[]; admite_componentes: boolean;
  epicrisis: { hechos: number; registro: number };
};
export type Cursor = { cuando: string; clase: string; ref_id: number };
export type EventoEpicrisis = { cuando: string; clase: string; ref_id: number; grupo: "hecho" | "registro"; resumen: string; estado?: string; autor?: string };
export type Epicrisis = { codigo: string; items: EventoEpicrisis[]; siguiente: Cursor | null };
export type Cercanos = { radio_m: number; sistema: string | null; activos: ActivoCorto[] };

const F = { funcion: "geoportal-redes" };
export const apiRedes = {
  activo: (codigo: string) => pedir<Ficha>("activo", { ...F, qs: { codigo } }),
  cercanos: (lat: number, lon: number, sistema: string | null, radio_m?: number) =>
    pedir<Cercanos>("activos_cerca", { ...F, cuerpo: { lat, lon, sistema, radio_m: radio_m ?? null, limite: 15 } }),
  epicrisis: (codigo: string, cursor?: Cursor | null) => pedir<Epicrisis>("epicrisis", { ...F, cuerpo: { codigo, cursor: cursor ?? null } }),
};
