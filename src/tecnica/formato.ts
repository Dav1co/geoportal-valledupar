import { formatearNumero } from "./numeros";

// Formato colombiano para el Dashboard: fechas dd/mm/aaaa, hora de Bogotá, números con punto para miles y coma para decimales. Lógica PURA.
const FMT_BOGOTA = new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false });

/** «2026-10-24» → «24/10/2026». */
export const fmtFecha = (iso: string | null | undefined): string => (iso && /^\d{4}-\d{2}-\d{2}/.test(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : "—");
/** «2026-10-24T15:44:12.331+00:00» (instante) → «24/10/2026 10:44», hora de Bogotá. */
export function fmtInstante(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso); if (Number.isNaN(d.getTime())) return "—";
  const p = Object.fromEntries(FMT_BOGOTA.formatToParts(d).map((x) => [x.type, x.value]));
  return `${p.day}/${p.month}/${p.year} ${p.hour === "24" ? "00" : p.hour}:${p.minute}`;
}
/** Hoy en Bogotá como «AAAA-MM-DD» (solo para armar los periodos del filtro; el servidor decide siempre sobre sus datos). */
export function hoyBogota(ahora = new Date()): string {
  const p = Object.fromEntries(FMT_BOGOTA.formatToParts(ahora).map((x) => [x.type, x.value])); return `${p.year}-${p.month}-${p.day}`;
}
const sumarDias = (iso: string, n: number): string => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

export type Periodo = "hoy" | "7d" | "mes" | "rango";
/** Periodo → {desde, hasta} (por FECHA DE LA MUESTRA). «rango» usa lo que escribió la persona. */
export function periodoARango(p: Periodo, hoy: string, desde?: string, hasta?: string): { desde?: string; hasta?: string } {
  if (p === "hoy") return { desde: hoy, hasta: hoy };
  if (p === "7d") return { desde: sumarDias(hoy, -6), hasta: hoy };
  if (p === "mes") return { desde: `${hoy.slice(0, 8)}01`, hasta: hoy };
  return { desde: desde || undefined, hasta: hasta || undefined };
}
/** Valor con los decimales del catálogo y formato colombiano. */
export const fmtValor = (v: number, decimales: number) => formatearNumero(v, decimales);
export const mayuscula = (s: string | null | undefined) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : "");
export const fmtMiles = (n: number) => formatearNumero(n, 0);
