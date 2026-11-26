import type { FilaDerivada } from "../documentos/apiDocumentos";
import { BOM, textoCsv } from "./archivo";

// Descarga de «Avisos y actividades derivadas» desde Reportes (25-nov). Lógica PURA (se prueba en Node, scripts/prueba_formatos_derivadas.mjs).
// Se arma en el navegador con lo que devuelve la ruta `derivadas` de geoportal-campo. ADVERTENCIA (pendiente del Code A): esta descarga NO queda auditada en el servidor como la de Reportes
// (descargaIniciar/descargaCerrar); cuando exista la ruta auditada se cambia solo el origen de las filas.
// NO incluye nunca: datos de contacto de los avisos (`aviso_datos`: nombre, cédula, teléfono, correo del suscriptor), ni el texto libre de la observación, ni la dirección correcta, ni el motivo de cierre
// (texto libre de personas). Del aviso solo dice SI trae datos de contacto y cuántas entregas, sin su contenido. El correo de quien registró o cerró solo va si el administrador lo pide.

export const ESTADOS: Record<string, string> = { pendiente: "Pendiente", atendida: "Atendida", atendida_fuera: "Atendida sin formulario", anulada: "Anulada" };
const CIERRES: Record<string, string> = { atendida: "Atendida por un registro", atendida_fuera: "Cerrada sin formulario", anulada: "Anulada" };
export const rotuloEstado = (e: string) => ESTADOS[e] ?? e;
export const nombreActividad = (d: FilaDerivada) => (d.actividad === "actividad_supervisor" && d.destino_nombre ? `Actividad: ${d.destino_nombre}` : d.actividad_nombre);
const fechaHora = (f: string | null | undefined) => (f ? new Date(f).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }).replace(", ", " ") : "");
const fechaDia = (f: string | null | undefined) => (!f ? "" : /^\d{4}-\d{2}-\d{2}$/.test(f) ? f.split("-").reverse().join("/") : new Date(f).toLocaleDateString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric" }));

export type CeldaD = string | number;
export function columnasDerivadas(incluirAutor: boolean): string[] {
  return ["Id", "Contrato", "Origen", "Actividad", "Estado", "Viene de", "Fecha de origen", "Creada", "Antigüedad (días)", "Visto otra vez (veces)", "Trae datos de contacto", "Entregas de datos", "Cierre", "Fecha de cierre", "La atendió (registro)",
    ...(incluirAutor ? ["Quién la originó (correo)", "Quién la cerró (correo)"] : [])];
}
export function filaDerivada(d: FilaDerivada, incluirAutor: boolean): CeldaD[] {
  const o = d.origen, analisis = o.clase === "analisis", c = d.cierre;
  return [d.id, d.contrato ?? "", analisis ? "Análisis de contrato" : "Revisión", nombreActividad(d), rotuloEstado(d.estado),
    analisis ? (o.observacion_nombre ?? "") : (o.consecutivo ?? o.tipo_nombre ?? o.tipo ?? ""), fechaDia(o.fecha), fechaHora(d.creada_en), d.antiguedad_dias ?? "", o.vistos ?? "",
    o.trae_datos ? (o.datos_anulados ? "Sí (anulados)" : "Sí") : "No", o.trae_datos ? (o.entregas_datos ?? "") : "",
    c ? (CIERRES[c.tipo] ?? c.tipo) : "", c ? fechaHora(c.en) : "", c?.tipo === "atendida" ? (c.consecutivo ?? "") : "",
    ...(incluirAutor ? [o.operario ?? "", c?.autor ?? ""] : [])];
}
export function csvDerivadas(filas: FilaDerivada[], incluirAutor: boolean): string {
  const l = [columnasDerivadas(incluirAutor).map(textoCsv).join(";"), ...filas.map((d) => filaDerivada(d, incluirAutor).map((v) => textoCsv(typeof v === "number" ? String(v) : v)).join(";"))];
  return BOM + l.join("\r\n") + "\r\n";
}
export const nombreArchivoDerivadas = (ahora: Date, ext: "csv" | "xlsx") => {
  const p = (n: number) => String(n).padStart(2, "0");
  return `avisos_y_actividades_derivadas_${ahora.getFullYear()}${p(ahora.getMonth() + 1)}${p(ahora.getDate())}_${p(ahora.getHours())}${p(ahora.getMinutes())}.${ext}`;
};
export function leameDerivadas(a: { generadoPor: string; generadoEn: string; filas: number; filtros: string[]; incluyeAutor: boolean }): string[][] {
  return [
    ["Avisos y actividades derivadas · Geoportal EMDUPAR", ""],
    ["Descargado por", a.generadoPor], ["Fecha y hora de la descarga (Bogotá)", a.generadoEn], ["Filas (una actividad o aviso por fila)", String(a.filas)],
    ["Filtros aplicados", a.filtros.length ? a.filtros.join("\n") : "Ninguno"],
    ["Datos de contacto", "NO incluye los datos de contacto de los avisos (nombre, cédula, teléfono, correo del suscriptor): se consultan solo en pantalla, con lectura auditada. Solo se indica si el aviso trae datos y cuántas entregas."],
    ["Texto libre", "No incluye la observación escrita, la dirección correcta ni el motivo de cierre."],
    ["Correos", a.incluyeAutor ? "Incluye el correo de quien originó y de quien cerró: información interna de EMDUPAR, no la comparta fuera de la empresa." : "No incluye el correo de quien originó ni de quien cerró."],
    ["Auditoría", "Esta descarga se armó en el navegador con la lista de «Avisos y actividades derivadas»; todavía no queda auditada en el servidor."],
  ];
}
