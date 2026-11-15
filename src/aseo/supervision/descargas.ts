import type { Celda } from "../../tecnica/xlsx";
import { apiSup, type DescargaIniciada, type FilaDescarga, type Filtros, type TipoNc } from "./api";

// Descargas CSV y Excel de las auditorías POR ACTIVIDAD. Una fila por auditoría: columnas fijas y una columna por cada pregunta del catálogo de esa actividad. Sin fotos ni imágenes de firmas.
// Auditadas en el servidor (iniciar → páginas de hasta 5.000 → cerrar). Lógica pura (se prueba en Node) + orquestador.
export const BOM = "﻿";
const ROT_INC = { si: "Sí", no: "No", parcial: "Parcial" } as const;
const ROT_TIPO: Record<TipoNc, string> = { sst: "SST", no_realizada: "No realizada", parcial: "Parcial", forma_indebida: "Forma indebida" };
const ROT_EST = { sin_revisar: "Sin revisar", revisada: "Revisada", reabierta: "Reabierta" } as const;
const ROT_REP = { firmo: "Firmó", se_nego: "Se negó a firmar", sin_representante: "No había representante" } as const;
export const ENCABEZADOS_FIJOS = ["Consecutivo", "Inicio (Bogotá)", "Fecha y hora de registro (Bogotá)", "Duración (min)", "Origen del inicio", "Fecha de servicio", "Actividad", "Modalidad", "Servicio (código)", "Servicio", "Ruta", "Turno", "Frecuencia", "Barrios",
  "Auditor (correo)", "Nombre del auditor", "Cargo del auditor", "Incidencia", "Causal", "Observaciones", "No conformidades", "Estado de la revisión", "Marcas", "Oculta", "Motivo de ocultar", "Fotos",
  "Latitud", "Longitud", "Representante del operador", "Nombre del representante", "Sello de integridad"];
export const ANCHOS_FIJOS = [16, 20, 20, 10, 12, 12, 14, 12, 10, 26, 16, 10, 16, 36, 30, 26, 26, 12, 30, 40, 26, 20, 34, 8, 36, 7, 11, 11, 22, 26, 66];
export const encabezados = (c: { nombre: string }[]) => [...ENCABEZADOS_FIJOS, ...c.map((x) => x.nombre)];
export const anchos = (c: unknown[]) => [...ANCHOS_FIJOS, ...c.map(() => 28)];

/** «2026-11-13T10:30:12» → «13/11/2026 10:30». */
const fmtLocal = (s: string | null) => (s ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)} ${s.slice(11, 16)}` : "");
const fmtFecha = (s: string) => `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}`;
/** Nombre sin datos personales: auditorias_<actividad>_AAAAMMDD_HHMM.ext a partir de «13/11/2026 10:44». */
export function nombreArchivo(actividad: string, generadoEn: string, ext: "csv" | "xlsx"): string {
  const m = /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/.exec(generadoEn); const a = actividad.replace(/[^a-z0-9_]/g, "");
  return m ? `auditorias_${a}_${m[3]}${m[2]}${m[1]}_${m[4]}${m[5]}.${ext}` : `auditorias_${a}.${ext}`;
}
export function textoCsv(t: string | null | undefined): string {
  if (t === null || t === undefined || t === "") return "";
  let s = String(t); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[;"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
export const numeroCsv = (v: number): string => String(v).replace(".", ",");
const ROT_ORIGEN = { dispositivo: "Celular", servidor: "Servidor" } as const;
const textos = (f: FilaDescarga, c: { codigo: string }[]): (string | null)[] => [
  f.consecutivo, fmtLocal(f.inicio_local ?? null), fmtLocal(f.registrado_local), null, f.inicio_origen ? ROT_ORIGEN[f.inicio_origen] : null, fmtFecha(f.fecha_servicio), f.actividad_nombre, f.modalidad_nombre, f.servicio, f.servicio_nombre, f.ruta_codigo, f.turno_nombre, f.frecuencia_nombre, f.barrios,
  f.autor, f.auditor_nombre, f.auditor_cargo ?? "Cargo no registrado", ROT_INC[f.incidencia], f.causal_nombre, f.observaciones, f.nc_tipos.map((t) => ROT_TIPO[t]).join("; "), f.nc_estado ? ROT_EST[f.nc_estado] : "Sin no conformidades",
  f.marcas.join("; "), f.oculta ? "Sí" : "No", f.oculta_motivo, String(f.n_fotos), null, null, ROT_REP[f.representante_estado], f.representante_nombre, f.sello,
  ...c.map((x) => f.respuestas[x.codigo] ?? null)];
// Posiciones dentro de las fijas (se buscan por el encabezado: agregar columnas no las corre)
const COL = (n: string) => ENCABEZADOS_FIJOS.indexOf(n);
const LAT = COL("Latitud"), LON = COL("Longitud"), DUR = COL("Duración (min)"), INI = COL("Inicio (Bogotá)"), REG = COL("Fecha y hora de registro (Bogotá)"), SRV = COL("Fecha de servicio"), FOT = COL("Fotos");
const duracion = (f: FilaDescarga) => (typeof f.duracion_min === "number" && Number.isFinite(f.duracion_min) ? f.duracion_min : null);
export function filaCsv(f: FilaDescarga, c: { codigo: string }[]): string {
  const t = textos(f, c); t[LAT] = numeroCsv(f.lat); t[LON] = numeroCsv(f.lon); const d = duracion(f); t[DUR] = d === null ? null : numeroCsv(d);
  return t.map((x, i) => (i === LAT || i === LON || i === DUR ? (x ?? "") : textoCsv(x))).join(";") + "\r\n";
}
export const cabeceraCsv = (c: { nombre: string }[]) => encabezados(c).map(textoCsv).join(";") + "\r\n";
export function filaXlsx(f: FilaDescarga, c: { codigo: string }[], serialExcel: (fecha: string, hora?: string) => number | null): Celda[] {
  const t = textos(f, c) as Celda[]; const sf = serialExcel(f.fecha_servicio), rl = f.registrado_local ? serialExcel(f.registrado_local.slice(0, 10), f.registrado_local.slice(11)) : null;
  const il = f.inicio_local ? serialExcel(f.inicio_local.slice(0, 10), f.inicio_local.slice(11)) : null;
  t[INI] = il === null ? null : { fechaHora: il }; t[REG] = rl === null ? null : { fechaHora: rl }; t[SRV] = sf === null ? null : { fecha: sf }; t[LAT] = f.lat; t[LON] = f.lon; t[FOT] = f.n_fotos; t[DUR] = duracion(f); return t;
}
export function hojaLeame(a: { generadoPor: string; generadoEn: string; filas: number; formato: string; actividad: string; filtros: string[] }): string[][] {
  return [
    [`Auditorías de ${a.actividad} · Interventoría de Aseo · Geoportal EMDUPAR`, ""],
    ["Descargado por", a.generadoPor], ["Fecha y hora de la descarga (Bogotá)", a.generadoEn], ["Filas (una por auditoría)", String(a.filas).replace(/\B(?=(\d{3})+(?!\d))/g, ".")], ["Formato", a.formato === "xlsx" ? "Excel (.xlsx)" : "CSV"],
    ["Filtros aplicados", a.filtros.length ? a.filtros.join("\n") : "Ninguno"],
    ["Inicio, fin y duración", "Inicio: hora en que se abrió el formulario, tomada del celular («Origen del inicio»: Celular). Fin: la fecha y hora de registro, que fija el servidor. Duración = fin − inicio, en minutos con un decimal. Vacías en las auditorías registradas antes de que existiera la hora de inicio."],
    ["Incidencia", "«Sí» se realizó, «No» no se realizó, «Parcial» se realizó en parte (con su causal)."],
    ["No conformidades", "Una auditoría es no conforme si no se realizó, se realizó en parte, o una respuesta está marcada como no conforme en el catálogo. Se evalúa con las marcas vigentes cuando se registró la auditoría. «Estado de la revisión»: lo que decidió el supervisor."],
    ["Preguntas", "Las últimas columnas son las preguntas del catálogo de esta actividad; si una auditoría no la respondió, la celda queda vacía."],
    ["Representante del operador", "Solo se descarga si firmó, se negó a firmar o no había representante, y su nombre si lo dio. No se incluyen imágenes de firmas ni fotos."],
    ["Barrio", "Es el barrio actual de la ruta (las capas de rutas se recargan por versión); el turno es el del plan vigente cuando se auditó."],
    ["Privacidad", "Este archivo contiene los correos del personal que audita. Es información interna de EMDUPAR: no lo comparta fuera de la empresa."],
  ];
}

// ---------------- Orquestador ----------------
export class DescargaCancelada extends Error { constructor() { super("Descarga cancelada."); this.name = "DescargaCancelada"; } }
export type Progreso = { fase: "preparando" | "descargando" | "armando"; hecho: number; total: number };
export type Resultado = { nombre: string; filas: number; blob: Blob };

export async function ejecutarDescarga(a: { filtros: Filtros; formato: "csv" | "xlsx"; filtrosTexto: string[]; onProgreso: (p: Progreso) => void; senal: AbortSignal; tamanoPagina?: number }): Promise<Resultado> {
  a.onProgreso({ fase: "preparando", hecho: 0, total: 0 });
  const ini: DescargaIniciada = await apiSup.descargaIniciar(a.filtros, a.formato);
  let hechas = 0, cerrado = false;
  const cerrar = async (res: "completa" | "cancelada" | "error") => { if (cerrado) return; cerrado = true; try { await apiSup.descargaCerrar(ini.descarga_id, hechas, res); } catch { /* el cierre es de mejor esfuerzo */ } };
  try {
    const xlsx = a.formato === "xlsx" ? await import("../../tecnica/xlsx") : null;
    const libro = xlsx ? new xlsx.LibroXlsx({ hoja: "Auditorías", encabezados: encabezados(ini.criterios), anchos: anchos(ini.criterios),
      leame: hojaLeame({ generadoPor: ini.generado_por, generadoEn: ini.generado_en, filas: ini.total, formato: "xlsx", actividad: ini.actividad.nombre, filtros: a.filtrosTexto }) }) : null;
    const partes: string[] = [BOM, cabeceraCsv(ini.criterios)]; let cursor: number | null = null;
    for (;;) {
      if (a.senal.aborted) throw new DescargaCancelada();
      const pag = await apiSup.descargaPagina(ini.descarga_id, cursor, a.tamanoPagina ?? 5000);
      if (pag.registros.length === 0) break;
      if (libro && xlsx) await libro.agregarFilas(pag.registros.map((f) => filaXlsx(f, ini.criterios, xlsx.serialExcel))); else for (const f of pag.registros) partes.push(filaCsv(f, ini.criterios));
      hechas += pag.registros.length; cursor = pag.ultimo_id; a.onProgreso({ fase: "descargando", hecho: hechas, total: ini.total });
      if (!pag.hay_mas) break;
    }
    if (a.senal.aborted) throw new DescargaCancelada();
    a.onProgreso({ fase: "armando", hecho: hechas, total: ini.total });
    const blob = libro ? await libro.finalizar() : new Blob(partes, { type: "text/csv;charset=utf-8" });
    await cerrar("completa");
    return { nombre: nombreArchivo(ini.actividad.codigo, ini.generado_en, a.formato), filas: hechas, blob };
  } catch (e) { await cerrar(e instanceof DescargaCancelada ? "cancelada" : "error"); throw e; }
}
export function guardarArchivo(r: Resultado) {
  const url = URL.createObjectURL(r.blob); const a = document.createElement("a"); a.href = url; a.download = r.nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
