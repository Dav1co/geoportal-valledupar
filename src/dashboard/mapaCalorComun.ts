import type { MapaCalorDim } from "./tipos";

// Lógica pura del mapa de calor (sin React ni MapLibre): sumas, porcentajes, clases por cuantiles y cuadrados de 250 m.
// Los NULL de las columnas de capa y de cartera son conteos suprimidos (1 a 4): se tratan como «desconocido», nunca como 0.
// Las columnas «_cartera» cuentan los contratos que SE MANTIENEN con el interruptor: sin mora profunda (sin más de 8 facturas vencidas, o sin registro).

export type CapaId = "sin_medidor_obs" | "consumo_bajo";
export const CAPAS: { id: CapaId; nombre: string; ramp: string[] }[] = [
  { id: "sin_medidor_obs", nombre: "Sin medidor o con observación", ramp: ["#FCEBD0", "#F6CB8C", "#E8A33D", "#C27A12", "#8A5200"] },
  { id: "consumo_bajo", nombre: "Consumo bajo (5 m³ o menos)", ramp: ["#DCEAF6", "#A9CBE6", "#6FA3CC", "#2F72A8", "#0A2540"] },
];
export const COLOR_SUPRIMIDA = "#B5BCC4";
export const MIN_CONTRATOS = 5;
export const LADO_M = 250;
export const M_POR_GRADO = 111320;

export const capaDe = (id: string) => CAPAS.find((c) => c.id === id) ?? CAPAS[0];

// Conteo de la capa de una celda según el interruptor de cartera: con él, los contratos de la capa que se mantienen (null = suprimido).
export const conteoCapa = (c: MapaCalorDim, cartera: boolean) => (cartera ? c.contratos_capa_cartera : c.contratos_capa);
// Porcentaje de la celda: conteo de la capa ÷ contratos de la base (null si el conteo está suprimido).
export function pctCelda(c: MapaCalorDim, cartera: boolean): number | null {
  const v = conteoCapa(c, cartera);
  return v == null || c.contratos_base <= 0 ? null : (v / c.contratos_base) * 100;
}

// Contratos en la capa = suma de las celdas publicadas con conteo conocido (los suprimidos no se suman).
export const sumaCapa = (celdas: MapaCalorDim[], cartera: boolean) =>
  celdas.reduce((s, c) => s + (conteoCapa(c, cartera) ?? 0), 0);
export const nSuprimidas = (celdas: MapaCalorDim[], cartera: boolean) => celdas.filter((c) => conteoCapa(c, cartera) == null).length;

// Cinco clases por cuantiles de los porcentajes conocidos. Con empates (muchos ceros) se funden las clases repetidas.
export type Clases = { cortes: number[]; min: number; max: number };
export function clasesPorCuantiles(pcts: number[]): Clases | null {
  if (!pcts.length) return null;
  const v = [...pcts].sort((a, b) => a - b);
  const q = (k: number) => v[Math.min(v.length - 1, Math.floor((k * v.length) / 5))];
  const min = v[0], max = v[v.length - 1];
  const cortes = [...new Set([q(1), q(2), q(3), q(4)])].filter((x) => x > min && x <= max).sort((a, b) => a - b);
  return { cortes, min, max };
}
export const claseDe = (p: number, k: Clases) => k.cortes.filter((c) => p >= c).length;
export const nClases = (k: Clases) => k.cortes.length + 1;
// Color de la clase i de k existentes: la primera (que incluye los ceros) usa SIEMPRE el tono más claro de la escala y las
// demás se reparten entre el resto de la escala, así 2 o 3 clases siguen distinguiéndose.
export function colorClase(i: number, k: number, ramp: string[]): string {
  if (k <= 1 || i <= 0) return ramp[0];
  return ramp[Math.min(ramp.length - 1, Math.round((i * (ramp.length - 1)) / (k - 1)))];
}
export function intervalos(k: Clases): { desde: number; hasta: number; ultima: boolean }[] {
  const e = [k.min, ...k.cortes, k.max];
  return e.slice(0, -1).map((d, i) => ({ desde: d, hasta: e[i + 1], ultima: i === e.length - 2 }));
}

// Cuadrado de 250 m centrado en la celda, en grados (anillo cerrado lon/lat).
export function cuadrado(lon: number, lat: number): [number, number][] {
  const dlat = (LADO_M / 2) / M_POR_GRADO;
  const dlon = (LADO_M / 2) / (M_POR_GRADO * Math.cos((lat * Math.PI) / 180));
  return [[lon - dlon, lat - dlat], [lon + dlon, lat - dlat], [lon + dlon, lat + dlat], [lon - dlon, lat + dlat], [lon - dlon, lat - dlat]];
}
