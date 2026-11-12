import type { Columna, Contexto } from "./columnas";
import type { FilaDescarga, FilaReporte } from "./apiRevision";
import { fmtMiles } from "./formatoRevision";

// Armado de los archivos de descarga a partir de las filas de la RPC de descarga y del registro de columnas. Lógica PURA (se prueba en Node). Sin rutas de Storage, URLs ni claves.
// CSV: UTF-8 con BOM, «;» como separador y coma decimal (se abre bien en Excel en español). Las fechas ya vienen como texto «día/mes/año hora de Bogotá».

export const BOM = "﻿";
export const MAX_FILAS_EXCEL = 1_048_575;   // 1.048.576 filas de Excel menos la de títulos

/** Texto para CSV: comillas si trae «;», comillas o saltos; y se neutraliza la inyección de fórmulas (=, +, -, @, tab) con un apóstrofo. */
export function textoCsv(t: string | null | undefined): string {
  if (t === null || t === undefined || t === "") return "";
  let s = String(t);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[;"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
export const cabeceraCsv = (cols: Columna[], conJson: boolean): string => [...cols.map((c) => textoCsv(c.etiqueta)), ...(conJson ? ["Datos propios (JSON)"] : [])].join(";") + "\r\n";
export function filaCsv(f: FilaReporte, cols: Columna[], ctx: Contexto, conJson: boolean): string {
  const celdas = cols.map((c) => textoCsv(c.tipo === "numero" && c.origen === "base" && typeof c.valor(f) === "number" ? String(c.valor(f)).replace(".", ",") : c.texto(f, ctx)));
  if (conJson) celdas.push(textoCsv(f.datos && Object.keys(f.datos).length ? JSON.stringify(f.datos) : ""));
  return celdas.join(";") + "\r\n";
}
/** Nombre de archivo sin datos personales: reportes_campo_AAAAMMDD_HHMM.ext a partir de «24/10/2026 10:44». */
export function nombreArchivo(generadoEn: string, ext: "csv" | "xlsx"): string {
  const m = /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/.exec(generadoEn); return m ? `reportes_campo_${m[3]}${m[2]}${m[1]}_${m[4]}${m[5]}.${ext}` : `reportes_campo.${ext}`;
}
/** Nombre de hoja de Excel: máximo 31 caracteres, sin []:*?/\ y único. */
export function nombreHoja(nombre: string, usados: Set<string>): string {
  const base = (nombre.replace(/[\[\]:*?/\\]/g, " ").replace(/\s+/g, " ").trim() || "Reportes").slice(0, 31);
  let n = base, i = 2;
  while (usados.has(n.toLowerCase())) { const suf = ` (${i++})`; n = base.slice(0, 31 - suf.length) + suf; }
  usados.add(n.toLowerCase()); return n;
}
/** Hoja «Léame»: filtros, quién y cuándo, total, qué incluye y advertencias. */
export function hojaLeame(a: { generadoPor: string; generadoEn: string; filas: number; formato: string; filtros: string[]; incluyeAutor: boolean; soloPantalla: string[]; hojasPorTipo: boolean }): string[][] {
  return [
    ["Reportes de campo · Geoportal EMDUPAR", ""],
    ["Descargado por", a.generadoPor], ["Fecha y hora de la descarga (Bogotá)", a.generadoEn], ["Filas (un reporte por fila)", fmtMiles(a.filas)], ["Formato", a.formato === "xlsx" ? "Excel (.xlsx)" : "CSV"],
    ["Filtros aplicados", a.filtros.length ? a.filtros.join("\n") : "Ninguno (todos los reportes)"],
    ["Corte", "Incluye los reportes registrados hasta la fecha y hora de la descarga; el estado y la marca de oculto son los del momento en que se leyó cada página."],
    ["Ocultos", "Si el filtro de ocultos es «incluidos», cada fila trae su marca «Oculto» y su estado: el archivo no tiene sesgo de selección. Nada se borra: ocultar es una marca con motivo."],
    ...(a.soloPantalla.length ? [["No aplicado", `Este archivo no aplica ${a.soloPantalla.join(" ni ")} (solo existen en pantalla)`]] : []),
    ["Autor", a.incluyeAutor ? "Incluye el correo de quien reportó: es información interna de EMDUPAR, no la comparta fuera de la empresa." : "No incluye el correo de quien reportó."],
    ["Privacidad", "El contrato, la descripción y las coordenadas pueden identificar a personas. Los datos sensibles de los formatos y las fotos NO se incluyen."],
    ...(a.hojasPorTipo ? [["Hojas", "Una hoja por tipo de reporte, con las columnas propias de ese tipo."]] : [["Datos propios", "Con un tipo filtrado, una columna por cada campo propio del tipo. Con varios tipos (CSV), una columna «Datos propios (JSON)»."]]),
  ];
}

/** Fila de descarga → forma común del registro de columnas (así tabla, detalle y descarga leen del MISMO registro). */
export function filaDeDescarga(r: FilaDescarga): FilaReporte {
  return {
    id: r.id, seq: r.seq, tipo: { codigo: r.tipo_codigo, nombre: r.tipo_nombre }, grupo: { codigo: "", nombre: r.grupo_nombre }, subtipo: r.subtipo_nombre ? { codigo: "", nombre: r.subtipo_nombre } : null,
    descripcion: r.descripcion, contrato: r.contrato, contrato_verificado: r.contrato_verificado, lat: r.lat, lon: r.lon, precision_m: r.precision_m, riesgo_inmediato: r.riesgo_inmediato, origen: r.origen,
    fuera_de_zona: r.fuera_de_zona, ...(r.autor !== undefined ? { autor: r.autor } : {}), registrado_en: "", registrado_local: r.registrado_local, estado: r.estado, estado_desde: null, oculto: r.oculto,
    reporte_original_id: r.reporte_original_id, grupo_duplicados: r.grupo_duplicados, tamano_grupo: r.tamano_grupo, n_fotos: r.n_fotos, consecutivo: r.consecutivo, resultado: r.resultado,
    causal: r.causal_nombre ? { codigo: "", nombre: r.causal_nombre } : null, orden_trabajo_id: r.orden_trabajo_id, datos: r.datos,
  };
}
