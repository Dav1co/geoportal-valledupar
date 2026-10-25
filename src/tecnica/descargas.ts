import type { Celda } from "./xlsx";
import { fmtFecha, mayuscula } from "./formato";

// Armado de los archivos de descarga (CSV y Excel) a partir de las filas que entrega geoportal_tec_descarga_pagina. Lógica PURA (se prueba en Node).
export type FilaDescarga = {
  registro_id: number; lote_id: string; formulario: string; formulario_nombre: string; variable: string; variable_nombre: string; unidad: string; decimales: number; valor: number;
  planta: string | null; planta_nombre: string | null; punto: string | null; punto_nombre: string | null; zona: string | null;
  fecha_muestra: string; hora_muestra: string; registrado_local: string; autor: string; fuente: string; fuera_de_rango: string | null;
  excluido: boolean; exclusion_motivo: string | null; exclusion_autor: string | null; exclusion_local: string | null;
};

export const ENCABEZADOS = ["Formulario", "Código de la variable", "Variable", "Unidad", "Valor", "Planta", "Punto (código)", "Punto", "Zona", "Fecha de la muestra", "Hora de la muestra",
  "Fecha y hora de registro (Bogotá)", "Autor", "Fuente", "Excluido", "Motivo de la exclusión", "Excluido por", "Fecha y hora de la exclusión (Bogotá)"];
export const ANCHOS_XLSX = [18, 22, 30, 12, 14, 14, 14, 24, 9, 14, 11, 20, 32, 12, 10, 40, 32, 20];

const fuenteTexto = (f: string) => (f === "telemetria" ? "Telemetría" : "Manual");
/** «2026-10-24T10:44:12» → «24/10/2026 10:44». */
const fmtLocal = (s: string | null) => (s ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)} ${s.slice(11, 16)}` : "");
/** Nombre de archivo sin datos personales: registros_tecnica_AAAAMMDD_HHMM.ext a partir de «24/10/2026 10:44». */
export function nombreArchivo(generadoEn: string, ext: "csv" | "xlsx"): string {
  const m = /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/.exec(generadoEn); return m ? `registros_tecnica_${m[3]}${m[2]}${m[1]}_${m[4]}${m[5]}.${ext}` : `registros_tecnica.${ext}`;
}

// ---------- CSV: UTF-8 con BOM, «;» como separador, coma decimal; una fila por valor ----------
export const BOM = "﻿";
/** Texto para CSV: comillas si trae «;», comillas, saltos de línea; y se neutraliza la inyección de fórmulas de Excel (=, +, -, @, tab) anteponiendo un apóstrofo. */
export function textoCsv(t: string | null | undefined): string {
  if (t === null || t === undefined || t === "") return "";
  let s = String(t);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[;"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
/** Número con coma decimal y SIN separador de miles (se abre bien en Excel en español y no pierde precisión). */
export const numeroCsv = (v: number): string => String(v).replace(".", ",");
export function filaCsv(f: FilaDescarga): string {
  return [
    f.formulario_nombre, f.variable, f.variable_nombre, f.unidad, numeroCsv(f.valor), f.planta_nombre ?? "", f.punto ?? "", f.punto_nombre ?? "", mayuscula(f.zona),
    fmtFecha(f.fecha_muestra), f.hora_muestra, fmtLocal(f.registrado_local), f.autor, fuenteTexto(f.fuente), f.excluido ? "Sí" : "No", f.exclusion_motivo ?? "", f.exclusion_autor ?? "", fmtLocal(f.exclusion_local),
  ].map((x, i) => (i === 4 ? x : textoCsv(x))).join(";") + "\r\n";
}
export const cabeceraCsv = () => ENCABEZADOS.map(textoCsv).join(";") + "\r\n";

// ---------- Excel: celdas numéricas y fechas reales ----------
export function filaXlsx(f: FilaDescarga, serialExcel: (fecha: string, hora?: string) => number | null, serialHora: (h: string) => number | null): Celda[] {
  const sf = serialExcel(f.fecha_muestra), sh = serialHora(f.hora_muestra);
  const rl = f.registrado_local ? serialExcel(f.registrado_local.slice(0, 10), f.registrado_local.slice(11)) : null;
  const el = f.exclusion_local ? serialExcel(f.exclusion_local.slice(0, 10), f.exclusion_local.slice(11)) : null;
  return [f.formulario_nombre, f.variable, f.variable_nombre, f.unidad, f.valor, f.planta_nombre, f.punto, f.punto_nombre, mayuscula(f.zona) || null,
    sf === null ? null : { fecha: sf }, sh === null ? null : { hora: sh }, rl === null ? null : { fechaHora: rl }, f.autor, fuenteTexto(f.fuente), f.excluido ? "Sí" : "No",
    f.exclusion_motivo, f.exclusion_autor, el === null ? null : { fechaHora: el }];
}

/** Hoja «Léame»: filtros aplicados, quién y cuándo descargó, número de filas y advertencias. */
export function hojaLeame(a: { generadoPor: string; generadoEn: string; filas: number; formato: string; incluirExcluidos: boolean; filtros: string[] }): string[][] {
  return [
    ["Registros de Técnica · Geoportal EMDUPAR", ""],
    ["Descargado por", a.generadoPor], ["Fecha y hora de la descarga (Bogotá)", a.generadoEn], ["Filas (un valor por fila)", String(a.filas).replace(/\B(?=(\d{3})+(?!\d))/g, ".")], ["Formato", a.formato === "xlsx" ? "Excel (.xlsx)" : "CSV"],
    ["Incluye registros excluidos", a.incluirExcluidos ? "Sí (columna «Excluido», con motivo y autor)" : "No"],
    ["Filtros aplicados", a.filtros.length ? a.filtros.join("\n") : "Ninguno (todos los registros)"],
    ["", ""],
    ["Cómo leerlo", "«Valor» es el número tal como se guardó (no está redondeado). Las fechas y horas están en hora de Bogotá. La fecha de la muestra y la de registro pueden diferir (p. ej. resultados de laboratorio)."],
    ["Privacidad", "Este archivo contiene los correos de las personas que registraron y excluyeron datos. Es información interna de EMDUPAR: no lo comparta fuera de la empresa."],
  ];
}
