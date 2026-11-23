// Formato colombiano para los textos de la pantalla del módulo SCRR (punto para miles, coma para decimales, fechas dd/mm/aaaa, pesos con «$ »).
export const num = (n: number | string | null | undefined): string => (n === null || n === undefined || n === "" ? "—" : Number(n).toLocaleString("es-CO", { maximumFractionDigits: 2 }));
export const pesos = (n: number | string | null | undefined): string => (n === null || n === undefined || n === "" ? "—" : `$ ${Number(n).toLocaleString("es-CO", { maximumFractionDigits: 0 })}`);
export function fecha(s: string | null | undefined): string {
  if (!s) return "—";
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : s;
}
export function fechaHora(s: string | null | undefined): string {
  if (!s) return "—";
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s;
  return d.toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: true });
}
export const hoyBogota = (): string => new Date().toLocaleDateString("en-CA", { timeZone: "America/Bogota" });
export const ayerBogota = (): string => { const d = new Date(Date.now() - 86400000); return d.toLocaleDateString("en-CA", { timeZone: "America/Bogota" }); };
export const NOMBRE_TIPO: Record<string, string> = { cartera: "Cartera", pagos: "Pagos del día", actividades: "Actividades" };
export const NOMBRE_ESTADO: Record<string, string> = { en_paso: "En proceso", validada: "Validada", aplicando: "Aplicando (a medias)", aplicada: "Aplicada", rechazada: "Rechazada", reemplazada: "Reemplazada", anulada: "Anulada" };
