import { pedir } from "./apiTecnica";

// Cliente de los avisos de Técnica (Técnica fase 1, Corte 12) en la Edge geoportal-tecnica. Solo supervisores y administrador; quién ve qué lo decide el SERVIDOR.
// Los avisos se calculan en cada consulta (no se guardan ni se marcan como vistos): desaparecen cuando se resuelve la causa.
export type NivelAviso = "rojo" | "naranja" | "info";
export type AreaAviso = "planta" | "distribucion" | "personal";
export type Bandeja = { tablero: "ptap" | "distribucion" | "personal"; pestana: string | null; filtro?: string | null };      // filtro (Corte 14): «levantar» abre Por verificar en «Otros activos por levantamiento»
export type Aviso = { clave: string; area: AreaAviso; nivel: NivelAviso; titulo: string; detalle: string | null; n: number; items: string[]; bandeja: Bandeja; desde: string | null; orden: number };
export type Avisos = { areas: { planta: boolean; distribucion: boolean; personal: boolean }; admin: boolean; avisos: Aviso[]; total: number; rojos: number; naranjas: number; calculado_en: string; ms: number };
export type ParametroAviso = { clave: string; area: "planta" | "distribucion" | "sistema"; nombre: string; descripcion: string; valor: number; minimo: number; maximo: number; unidad: string;
  ultimo: { antes: number; despues: number; motivo: string; autor: string; creado_en: string } | null };
export type MinimoQuimico = { codigo: string; nombre: string; saldo_kg: number | null; minimo_kg: number | null; bajo: boolean;
  ultimo: { minimo_kg: number | null; motivo: string; autor: string; creado_en: string } | null };

export const apiAvisos = {
  avisos: () => pedir<Avisos>("avisos"),
  parametros: () => pedir<{ puede_minimos: boolean; parametros: ParametroAviso[] }>("avisos_parametros"),
  fijarParametro: (clave: string, valor: number, motivo: string) => pedir<{ clave: string; antes: number; valor: number }>("aviso_parametro_fijar", { cuerpo: { clave, valor, motivo } }),
  minimos: () => pedir<{ quimicos: MinimoQuimico[] }>("quimico_minimos"),
  fijarMinimo: (quimico: string, minimo_kg: number | null, motivo: string) => pedir<{ codigo: string; antes: number | null; minimo_kg: number | null }>("quimico_minimo_fijar", { cuerpo: { quimico, minimo_kg, motivo } }),
};
