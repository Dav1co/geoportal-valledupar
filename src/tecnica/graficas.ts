import type { PuntoSerie } from "./apiDashboard";
import { formatearNumero } from "./numeros";

// Geometría de las gráficas del Resumen (LÓGICA PURA, sin React; se prueba en Node). Las gráficas son SVG propio: sin librerías.
// Las horas de los puntos vienen del servidor como hora de Bogotá («AAAA-MM-DDTHH:MM:SS»); se tratan como «reloj de pared» (UTC) para que la posición no dependa de la zona del navegador.

export const aMs = (t: string): number => {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(t);
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) : NaN;
};
export const inicioDia = (iso: string): number => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10));
const DIA = 86_400_000;
/** Eje del tiempo: de las 00:00 del primer día a las 24:00 del último. */
export const dominioX = (desde: string, hasta: string): [number, number] => [inicioDia(desde), inicioDia(hasta) + DIA];

/** Paso «bonito» (1, 2, 2,5, 5 × 10ⁿ) para dividir un rango en unas `aprox` marcas. */
export function pasoBonito(rango: number, aprox = 4): number {
  if (!(rango > 0)) return 1;
  const crudo = rango / aprox, exp = Math.floor(Math.log10(crudo)), f = crudo / Math.pow(10, exp);
  const b = f < 1.5 ? 1 : f < 2.25 ? 2 : f < 3.5 ? 2.5 : f < 7.5 ? 5 : 10;
  return b * Math.pow(10, exp);
}
export const decimalesDePaso = (paso: number): number => { for (let d = 0; d <= 4; d++) if (Math.abs(paso * Math.pow(10, d) - Math.round(paso * Math.pow(10, d))) < 1e-9) return d; return 4; };

export type Limites = { ref_min: number | null; ref_max: number | null } | null;
/** Escala vertical: los datos con un margen. Un límite de la referencia entra a la escala SOLO si está cerca de los datos (a menos de 2 rangos); si no, la banda se recorta
 *  (así una referencia lejana —p. ej. máximo 5.000 con datos de 20— no aplasta la gráfica). Nunca baja de 0 si todos los valores son no negativos. */
export function dominioY(valores: number[], ref: Limites): { min: number; max: number } {
  if (valores.length === 0) return { min: 0, max: 1 };
  let lo = Math.min(...valores), hi = Math.max(...valores);
  const rango = hi - lo || Math.max(Math.abs(hi) * 0.2, 1);
  const cerca = (l: number | null) => l !== null && l >= lo - 2 * rango && l <= hi + 2 * rango;
  const noNeg = lo >= 0;
  if (ref) for (const l of [ref.ref_min, ref.ref_max]) if (l !== null && cerca(l)) { lo = Math.min(lo, l); hi = Math.max(hi, l); }      // un límite cercano entra a la escala por el lado que haga falta
  const pad = (hi - lo || 1) * 0.1;
  lo -= pad; hi += pad;
  if (noNeg && lo < 0) lo = 0;
  return { min: lo, max: hi };
}
/** Marcas del eje Y dentro del dominio. */
export function ticksY(min: number, max: number, aprox = 4): { valores: number[]; decimales: number } {
  const paso = pasoBonito(max - min, aprox); const out: number[] = [];
  for (let v = Math.ceil(min / paso - 1e-9) * paso; v <= max + 1e-9; v += paso) out.push(Math.round(v / paso) * paso);
  return { valores: out, decimales: decimalesDePaso(paso) };
}
/** Banda de la referencia recortada al dominio (en unidades de datos). Un solo límite = banda hasta el borde de la gráfica. Nula si no hay referencia o queda fuera de la escala. */
export function banda(ref: Limites, dom: { min: number; max: number }): { desde: number; hasta: number } | null {
  if (!ref || (ref.ref_min === null && ref.ref_max === null)) return null;
  const lo = Math.max(ref.ref_min ?? dom.min, dom.min), hi = Math.min(ref.ref_max ?? dom.max, dom.max);
  return lo < hi ? { desde: lo, hasta: hi } : null;
}
/** Marcas del eje X: un día de cada `paso` (7 marcas como máximo). Devuelve la posición (ms) y la etiqueta «dd/mm». */
export function ticksX(desde: string, hasta: string): { ms: number; texto: string }[] {
  const [d0, d1] = dominioX(desde, hasta); const dias = Math.round((d1 - d0) / DIA); const paso = Math.max(1, Math.ceil(dias / 7)); const out: { ms: number; texto: string }[] = [];
  for (let i = 0; i < dias; i += paso) { const f = new Date(d0 + i * DIA); out.push({ ms: d0 + i * DIA, texto: `${String(f.getUTCDate()).padStart(2, "0")}/${String(f.getUTCMonth() + 1).padStart(2, "0")}` }); }
  return out;
}
export const fmtPunto = (p: PuntoSerie, decimales: number) => `${p.t.slice(8, 10)}/${p.t.slice(5, 7)}/${p.t.slice(0, 4)} ${p.t.slice(11, 16)} · ${formatearNumero(p.v, decimales)}`;
