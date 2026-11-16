import { pedir } from "../apiTecnica";
import type { FilaLote } from "./lectores";

// Cliente del Cargue de capas (Técnica fase 1, Corte 5c) en la Edge geoportal-redes. Quién puede qué lo decide el SERVIDOR:
// la lista y el historial los ven el supervisor de distribución y el administrador; abrir, subir, revisar, publicar, anular, revertir y devolver campos, solo el administrador.

export type EstadoCapa = "al_dia" | "desactualizada" | "sin_cargar" | "derivada" | "otro_modulo";
export type CapaCargue = {
  codigo: string; nombre: string; grupo: "acueducto" | "alcantarillado" | "tecnologia_perdidas" | "calidad_pqr" | "base"; sistema: string | null;
  geometria: "punto" | "linea" | "poligono" | "mixta"; prefijo: string | null; fuente: string; derivada_de: string | null; columna_llave: string | null;
  formatos: string[]; lector: "modelo" | "generico" | "muestreo" | null; version: number; vigentes: number; estado: EstadoCapa;
  puede_cargar?: boolean; solo_admin?: boolean;      // Corte 6a: el supervisor de distribución carga las que no vienen del modelo (lo decide el servidor)
  ultima: { carga_id: number; publicada_en: string; autor: string; formato: string; filas: number; nota: string | null; motivo: string | null } | null;
  abierta: { carga_id: number; creado_en: string; autor: string; formato: string; filas: number; recibidas: number; sha256: string; columna_llave: string; srid: number; masiva: boolean } | null;
};
export type CapasResp = { puede_cargar: boolean; max_filas: number; lote_max_filas: number; tolerancia_geometria_m: number; caja: [number, number, number, number]; capas: CapaCargue[] };
export type EventoCarga = { tipo: "publicar" | "revertir" | "anular"; version_capa: number | null; nuevos: number | null; cambiados: number | null; iguales: number | null;
  retirados: number | null; reactivados: number | null; motivo: string; autor: string; creado_en: string };
export type CargaHistorial = { carga_id: number; estado: "abierta" | "publicada" | "revertida" | "anulada"; formato: string; srid: number; columna_llave: string; filas: number;
  nota: string | null; autor: string; creado_en: string; masiva: boolean; eventos: EventoCarga[] };
export type Choque = { codigo: string; campo: string; ficha: string | null; capa: string | null };
export type PuntoMue = { orden: number; codigo: string | null; nombre: string | null; barrio: string | null; exactitud: string; fuente: string; lat: number | null; lon: number | null; accion: string; error: string | null };
export type Resumen = {
  carga_id: number; capa: string; estado: string; recibidas: number; esperadas: number; errores?: number; llaves_nulas?: number; llaves_repetidas?: number;
  por_prefijo?: Record<string, number>; frente_a_vigente: Record<string, number>; retirados?: number; detalle?: Record<string, unknown>;
  avisos: string[]; bloqueos: string[]; lista_para_publicar: boolean; choques?: Choque[];
  desactivar?: { codigo: string; nombre: string }[]; puntos?: PuntoMue[];       // capa MUE
};
export type Muestra = { carga_id: number; capa: string; esperadas: number; recibidas: number; con_geometria: number; con_error: number;
  errores: { orden: number; llave: string | null; error: string }[]; caja: [number, number, number, number] | null; muestra: GeoJSON.FeatureCollection };
export type Publicada = { carga_id: number; capa: string; version_capa: number; nuevos: number; cambiados: number; iguales?: number; retirados?: number; reactivados?: number;
  desactivados?: number; segundos?: number };

const F = { funcion: "geoportal-redes" };
export const apiCargue = {
  capas: () => pedir<CapasResp>("cargue_capas", F),
  historial: (capa: string) => pedir<{ capa: string; cargas: CargaHistorial[] }>("cargue_historial", { ...F, qs: { capa } }),
  iniciar: (d: { capa: string; sha256: string; formato: string; srid: number; columna_llave: string; filas: number; nota?: string | null; masiva?: string | null }) =>
    pedir<{ carga_id: number; nueva: boolean; recibidas: number }>("cargue_iniciar", { ...F, cuerpo: d }),
  // 60 s: un lote grande en una red lenta; repetirlo no duplica (la base ignora un «orden» que ya llegó)
  lote: (carga: number, filas: FilaLote[]) => pedir<{ nuevas: number; repetidas: number; recibidas: number }>("cargue_lote", { ...F, cuerpo: { carga, filas }, timeoutMs: 60000 }),
  resumen: (carga: number) => pedir<Resumen>("cargue_resumen", { ...F, qs: { carga: String(carga) }, timeoutMs: 120000 }),
  muestra: (carga: number) => pedir<Muestra>("cargue_muestra", { ...F, qs: { carga: String(carga) }, timeoutMs: 60000 }),
  publicar: (carga: number, motivo: string) => pedir<Publicada>("cargue_publicar", { ...F, cuerpo: { carga, motivo }, timeoutMs: 150000 }),
  anular: (carga: number, motivo: string) => pedir<{ carga_id: number; anulada: boolean }>("cargue_anular", { ...F, cuerpo: { carga, motivo } }),
  revertir: (capa: string, motivo: string) => pedir<{ carga_id: number; capa: string; reactivados?: number; retirados?: number }>("cargue_revertir", { ...F, cuerpo: { capa, motivo }, timeoutMs: 150000 }),
  devolverCampo: (carga: number, codigo: string, campo: string, motivo: string) =>
    pedir<{ devolucion_id: number; codigo: string; campo: string; valor_ficha: string | null }>("cargue_devolver_campo", { ...F, cuerpo: { carga, codigo, campo, motivo } }),
};
