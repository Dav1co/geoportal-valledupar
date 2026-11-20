import type { CeldaConEnlace as Celda } from "../xlsx";
import type { ColumnaReporte, DefReporte } from "./catalogo";
import type { LeameServidor } from "./apiReportes";
import { BOM, numeroCsv, textoCsv } from "../descargas";

// Armado PURO de los reportes (se prueba en Chrome con los archivos abiertos en openpyxl): encabezados con la unidad, celdas de Excel (números, fechas de
// Excel en hora de Bogotá, enlaces) y de CSV (UTF-8 con BOM, «;», coma decimal, igual que la descarga de «Registros»), la hoja «Léame», el periodo y el nombre.

export const DIAS_MAX = 366;                    // «máximo 366 días» por descarga (contrato del Code A, §1.1)

// ---------- fechas en hora de Bogotá ----------
const BOGOTA = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
/** «AAAA-MM-DD» y «HH:MM:SS» de Bogotá. Un texto SIN zona ya es hora de Bogotá (la forma del Code A) y se toma tal cual; uno CON zona («…Z», «…-05:00») se pasa a Bogotá. */
export function partesBogota(v: string): [string, string] | null {
  const s = v.trim();
  const local = /^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2})(?::(\d{2}))?(?:\.\d+)?)?$/.exec(s);
  if (local) return [local[1], `${local[2] ?? "00:00"}:${local[3] ?? "00"}`];
  const d = new Date(s); if (Number.isNaN(d.getTime())) return null;
  const p = Object.fromEntries(BOGOTA.formatToParts(d).map((x) => [x.type, x.value]));
  return [`${p.year}-${p.month}-${p.day}`, `${p.hour}:${p.minute}:${p.second}`];
}
export const hoyBogota = () => partesBogota(new Date().toISOString())![0];
export const primeroDelMes = () => hoyBogota().slice(0, 8) + "01";

/** Revisa el periodo: las dos fechas, «hasta» no antes de «desde» y hasta 366 días. Devuelve el texto del error o null. */
export function errorPeriodo(desde: string, hasta: string): string | null {
  const re = /^\d{4}-\d{2}-\d{2}$/;
  if (!re.test(desde) || !re.test(hasta)) return "Elija las dos fechas del periodo.";
  if (hasta < desde) return "«Hasta» no puede ser antes de «desde».";
  const dias = (Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)) / 86400000 + 1;
  if (dias > DIAS_MAX) return "El periodo pasa de un año. Acórtelo: hasta un año por descarga.";
  return null;
}

// ---------- encabezados ----------
/** «Turbiedad de ingreso (Ti) (NTU)»: titulo + « (unidad)» cuando hay unidad (§1.2 del contrato), salvo que el título ya la traiga. */
export function encabezado(c: ColumnaReporte): string {
  const u = (c.unidad ?? "").trim();
  return u && !c.titulo.endsWith(`(${u})`) ? `${c.titulo} (${u})` : c.titulo;
}
const ANCHO: Record<string, number> = { texto: 18, decimal: 12, numero: 12, entero: 10, fecha: 12, hora: 8, fecha_hora: 17, si_no: 9, enlace: 12 };
export const ancho = (c: ColumnaReporte) => c.ancho ?? Math.min(40, Math.max(ANCHO[c.tipo] ?? 14, Math.ceil(encabezado(c).length * 0.9)));

// ---------- valores ----------
const vacio = (v: unknown) => v === null || v === undefined || v === "";
const aNumero = (v: unknown): number | null => { const n = typeof v === "number" ? v : Number(String(v).replace(",", ".")); return Number.isFinite(n) ? n : null; };
const siNo = (v: unknown) => (v === true || v === "true" || v === "t" || v === 1 ? "Sí" : v === false || v === "false" || v === "f" || v === 0 ? "No" : String(v));
/** Solo enlaces web (http/https) sin espacios ni < >: cualquier otra cosa va como texto, sin vínculo. */
export const enlaceValido = (v: unknown) => typeof v === "string" && /^https?:\/\/[^\s<>]+$/i.test(v) && v.length <= 2000;
/** Convierte el valor de una columna «enlace» en un vínculo { url, texto } (o null: va como texto). */
export type Enlazar = (c: ColumnaReporte, v: unknown) => { url: string; texto: string } | null;
export const enlazarWeb: Enlazar = (_c, v) => (enlaceValido(v) ? { url: String(v), texto: "Abrir" } : null);

/** Celda de Excel según el tipo de la columna. Lo que no se puede leer como su tipo va como texto (no se pierde). */
export function celdaXlsx(c: ColumnaReporte, v: unknown, serialExcel: (fecha: string, hora?: string) => number | null, enlazar: Enlazar = enlazarWeb): Celda {
  if (vacio(v)) return null;
  switch (c.tipo) {
    case "decimal": case "numero": case "entero": { const n = aNumero(v); return n === null ? String(v) : n; }
    case "fecha": { const p = partesBogota(String(v)); const s = p ? serialExcel(p[0]) : null; return s === null ? String(v) : { fecha: s }; }
    case "hora": { const h = /^(\d{2}):(\d{2})/.exec(String(v)); return h ? { hora: (+h[1] * 60 + +h[2]) / 1440 } : String(v); }
    case "fecha_hora": { const p = partesBogota(String(v)); const s = p ? serialExcel(p[0], p[1]) : null; return s === null ? String(v) : { fechaHora: s }; }
    case "si_no": return siNo(v);
    case "enlace": { const e = enlazar(c, v); return e ? { enlace: e.url, texto: e.texto } : String(v); }
    default: return typeof v === "boolean" ? siNo(v) : String(v);
  }
}
export const filaXlsx = (cols: ColumnaReporte[], f: Record<string, unknown>, serialExcel: (fecha: string, hora?: string) => number | null, enlazar?: Enlazar): Celda[] =>
  cols.map((c) => celdaXlsx(c, f[c.clave], serialExcel, enlazar));

/** «2026-10-24» → «24/10/2026»; con hora, «24/10/2026 10:44» (Excel en español lo abre como fecha). */
const fmtFecha = (p: [string, string], conHora: boolean) => `${p[0].slice(8, 10)}/${p[0].slice(5, 7)}/${p[0].slice(0, 4)}${conHora ? ` ${p[1].slice(0, 5)}` : ""}`;
export function celdaCsv(c: ColumnaReporte, v: unknown, enlazar: Enlazar = enlazarWeb): string {
  if (vacio(v)) return "";
  switch (c.tipo) {
    case "decimal": case "numero": case "entero": { const n = aNumero(v); return n === null ? textoCsv(String(v)) : numeroCsv(n); }
    case "fecha": { const p = partesBogota(String(v)); return p ? fmtFecha(p, false) : textoCsv(String(v)); }
    case "hora": { const h = /^(\d{2}):(\d{2})/.exec(String(v)); return h ? `${h[1]}:${h[2]}` : textoCsv(String(v)); }
    case "fecha_hora": { const p = partesBogota(String(v)); return p ? fmtFecha(p, true) : textoCsv(String(v)); }
    case "si_no": return siNo(v);
    case "enlace": { const e = enlazar(c, v); return textoCsv(e ? e.url : String(v)); }
    default: return textoCsv(typeof v === "boolean" ? siNo(v) : String(v));
  }
}
export const filaCsv = (cols: ColumnaReporte[], f: Record<string, unknown>, enlazar?: Enlazar) => cols.map((c) => celdaCsv(c, f[c.clave], enlazar)).join(";") + "\r\n";
export const cabeceraCsv = (cols: ColumnaReporte[]) => BOM + cols.map((c) => textoCsv(encabezado(c))).join(";") + "\r\n";
// El CSV trae solo los datos (un «Léame» al comienzo rompería las columnas); el «Léame» va en la segunda hoja del Excel.

// ---------- «Léame» ----------
export type Pedido = { desde?: string; hasta?: string; filtros: Record<string, string>; incluir_excluidos: boolean; formato: "xlsx" | "csv" };
const fechaCorta = (s: string) => `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}`;
/** Las líneas las redacta el servidor (`leame`, §1.2 del contrato); la pantalla agrega el formato, las filas y el resto. Si el servidor no las trae, van las de la tarjeta. */
export function hojaLeame(a: { def: DefReporte; pedido: Pedido; filtrosTexto: string[]; leame?: LeameServidor; generadoEn: string; filas: number }): string[][] {
  const { def, pedido } = a, s = a.leame ?? {};
  const lineas = (x: string[] | undefined) => (Array.isArray(x) && x.length ? x.join("\n") : "");
  const filtros = lineas(s.filtros) || [
    def.periodo && pedido.desde && pedido.hasta ? `Periodo: ${fechaCorta(pedido.desde)} a ${fechaCorta(pedido.hasta)} (${def.periodoPor ?? "fecha del registro"}; hora de Bogotá)` : "Inventario a hoy (sin periodo)",
    ...a.filtrosTexto,
    def.ocultos ? `${def.ocultos}: ${pedido.incluir_excluidos ? "sí" : "no"}` : "",
  ].filter(Boolean).join("\n");
  return [
    [`${def.titulo} · Geoportal EMDUPAR`, ""],
    ["Qué trae", lineas(s.que_trae) || def.trae],
    ["Lo que no va", lineas(s.que_no_trae) || def.noTrae],
    ["Filtros", filtros],
    ["Filas", String(a.filas).replace(/\B(?=(\d{3})+(?!\d))/g, ".")],
    ["Formato", pedido.formato === "xlsx" ? "Excel (.xlsx)" : "CSV (UTF-8, separado por «;», coma decimal)"],
    ["Descargado por", s.generado_por ?? ""],
    ["Fecha y hora de la descarga (Bogotá)", a.generadoEn],
    ["Auditoría", "La descarga queda registrada con quién la hizo, cuándo, qué reporte y con qué filtros."],
    ["Cómo leerlo", "Una fila por envío o registro y cada variable en su columna, con la unidad en el encabezado. Las fechas y horas están en hora de Bogotá; en Excel son fechas reales (se pueden ordenar y filtrar)."],
    ...(def.notas ?? []),
    ["Privacidad", "Contiene los correos de los funcionarios que registraron, revisaron o cerraron. Es información interna de EMDUPAR: no lo comparta fuera de la empresa."],
  ];
}

// ---------- nombre del archivo (sin datos personales) ----------
/** El del servidor (`archivo`, sin extensión) si viene y es seguro; si no, el de la tarjeta con el periodo y los filtros. */
export function nombreArchivo(def: DefReporte, pedido: Pedido, delServidor?: string, hoy = hoyBogota()): string {
  if (delServidor && /^[\w.-]{1,120}$/.test(delServidor)) return `${delServidor}.${pedido.formato}`;
  const rango = def.periodo && pedido.desde && pedido.hasta ? `${pedido.desde}_a_${pedido.hasta}` : hoy;
  const filtro = def.filtros.map((f) => pedido.filtros[f.clave]).filter(Boolean).map((x) => String(x).replace(/[^\w-]+/g, "")).filter(Boolean);
  return `${def.archivo}${filtro.length ? `_${filtro.join("_")}` : ""}_${rango}.${pedido.formato}`;
}
