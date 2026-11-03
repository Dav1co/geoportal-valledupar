// Formato colombiano: fecha día/mes/año, hora local de Bogotá en 12 horas, coma decimal. Todo con Intl; nada se calcula a mano.
const ZONA = "America/Bogota";

export function fechaHora(d: Date | string): string {
  const f = typeof d === "string" ? new Date(d) : d;
  if (Number.isNaN(f.getTime())) return "—";
  return new Intl.DateTimeFormat("es-CO", { timeZone: ZONA, day: "2-digit", month: "2-digit", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true }).format(f);
}

/** Para el sello de la foto: día/mes/año y hora de 24 horas con segundos. */
export function fechaHoraSello(d: Date): string {
  const p = new Intl.DateTimeFormat("es-CO", { timeZone: ZONA, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).format(d);
  return p.replace(",", "");
}

export const decimal = (n: number, dec: number) => n.toLocaleString("es-CO", { minimumFractionDigits: dec, maximumFractionDigits: dec });
export const metros = (n: number) => `±${Math.round(n).toLocaleString("es-CO")} m`;
export const megas = (bytes: number) => `${(bytes / 1048576).toLocaleString("es-CO", { maximumFractionDigits: 1 })} MB`;
