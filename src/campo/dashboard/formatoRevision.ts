// Formato colombiano para la pantalla de Revisión: fechas día/mes/año, hora de Bogotá, punto de miles y coma decimal. Lógica PURA (se prueba en Node).
const BOGOTA = new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

/** Instante ISO (con zona) → «24/10/2026 10:44», hora de Bogotá. */
export function fmtInstante(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso); if (Number.isNaN(d.getTime())) return "—";
  const p = Object.fromEntries(BOGOTA.formatToParts(d).map((x) => [x.type, x.value]));
  return `${p.day}/${p.month}/${p.year} ${p.hour}:${p.minute}`;
}
/** «2026-10-24T10:44:12» (hora de pared de Bogotá) → «24/10/2026 10:44». */
export const fmtLocal = (s: string | null | undefined): string => (s && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(s) ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)} ${s.slice(11, 16)}` : "—");
/** «2026-10-24» → «24/10/2026». */
export const fmtDia = (s: string | null | undefined): string => (s && /^\d{4}-\d{2}-\d{2}/.test(s) ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}` : "—");
export const fmtMiles = (n: number): string => n.toLocaleString("es-CO", { maximumFractionDigits: 0 });
export const fmtNumero = (n: number, dec = 2): string => n.toLocaleString("es-CO", { minimumFractionDigits: 0, maximumFractionDigits: dec });
/** Segundos → «2 h 15 min», «45 min», «3 d 4 h»; sin juicio de valor. */
export function fmtDuracion(seg: number | null | undefined): string {
  if (seg === null || seg === undefined || !Number.isFinite(seg)) return "—";
  const s = Math.max(0, Math.round(seg));
  if (s < 60) return `${s} s`;
  const min = Math.round(s / 60);
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60), m = min % 60;
  if (h < 48) return m ? `${h} h ${m} min` : `${h} h`;
  const d = Math.floor(h / 24), hh = h % 24;
  return hh ? `${d} d ${hh} h` : `${d} d`;
}
/** Hoy en Bogotá «AAAA-MM-DD». */
export function hoyBogota(ahora = new Date()): string {
  const p = Object.fromEntries(BOGOTA.formatToParts(ahora).map((x) => [x.type, x.value])); return `${p.year}-${p.month}-${p.day}`;
}
export function sumarDias(iso: string, n: number): string { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
export const normalizar = (t: string): string => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
