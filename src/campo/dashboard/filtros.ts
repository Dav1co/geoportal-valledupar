import type { FilaReporte, FiltrosServidor, FormularioRev } from "./apiRevision";
import { fmtDia, hoyBogota, normalizar, sumarDias } from "./formatoRevision";

// Filtros de la pantalla de Revisión. Tipo, grupo, estado, fechas, riesgo inmediato, ocultos y resultado van al SERVIDOR (cambian el conjunto y el total «M»);
// la zona (dentro/fuera) y la búsqueda de texto se aplican en el NAVEGADOR sobre lo cargado (la zona ya viene en cada fila). Lógica PURA.

export type Periodo = "todo" | "hoy" | "7d" | "30d" | "mes" | "rango";
export type FiltrosUI = {
  tipo: string; grupo: string; estado: string; periodo: Periodo; desde: string; hasta: string;
  riesgo: "" | "si" | "no"; ocultos: "no" | "si" | "todos"; zona: "todas" | "dentro" | "fuera"; resultado: "" | "efectivo" | "inefectivo"; busqueda: string;
};
export const FILTROS_INICIALES: FiltrosUI = { tipo: "", grupo: "", estado: "", periodo: "30d", desde: "", hasta: "", riesgo: "", ocultos: "no", zona: "todas", resultado: "", busqueda: "" };

export function rangoDelPeriodo(p: Periodo, hoy: string, desde: string, hasta: string): { desde?: string; hasta?: string } {
  if (p === "todo") return {};
  if (p === "hoy") return { desde: hoy, hasta: hoy };
  if (p === "7d") return { desde: sumarDias(hoy, -6), hasta: hoy };
  if (p === "30d") return { desde: sumarDias(hoy, -29), hasta: hoy };
  if (p === "mes") return { desde: `${hoy.slice(0, 8)}01`, hasta: hoy };
  return { desde: desde || undefined, hasta: hasta || undefined };
}
export const rangoInvalido = (f: FiltrosUI): boolean => f.periodo === "rango" && !!f.desde && !!f.hasta && f.desde > f.hasta;

export function aFiltrosServidor(f: FiltrosUI, hoy = hoyBogota()): FiltrosServidor {
  const r = rangoDelPeriodo(f.periodo, hoy, f.desde, f.hasta);
  const s: FiltrosServidor = { ocultos: f.ocultos };
  if (f.tipo) s.tipo = f.tipo; if (f.grupo) s.grupo = f.grupo; if (f.estado) s.estado = f.estado;
  if (r.desde) s.desde = r.desde; if (r.hasta) s.hasta = r.hasta;
  if (f.riesgo) s.riesgo_inmediato = f.riesgo === "si";
  if (f.resultado) s.resultado = f.resultado;
  return s;
}

/** Zona y búsqueda de texto (descripción, contrato y consecutivo) en el navegador. */
export function pasaFiltroCliente(fila: FilaReporte, f: Pick<FiltrosUI, "zona" | "busqueda">): boolean {
  if (f.zona === "dentro" && fila.fuera_de_zona) return false;
  if (f.zona === "fuera" && !fila.fuera_de_zona) return false;
  const q = normalizar(f.busqueda.trim());
  if (!q) return true;
  return normalizar(`${fila.descripcion ?? ""} ${fila.contrato ?? ""} ${fila.consecutivo ?? ""}`).includes(q);
}

/** Filtros activos en palabras (también van al «Léame» de las descargas). */
export function filtrosLegibles(f: FiltrosUI, def: Pick<FormularioRev, "grupos" | "estados">, hoy = hoyBogota()): string[] {
  const t: string[] = [];
  const tipos = def.grupos.flatMap((g) => g.tipos);
  if (f.grupo) t.push(`Grupo: ${def.grupos.find((g) => g.codigo === f.grupo)?.nombre ?? f.grupo}`);
  if (f.tipo) t.push(`Tipo: ${tipos.find((x) => x.codigo === f.tipo)?.nombre ?? f.tipo}`);
  if (f.estado) t.push(`Estado: ${def.estados?.find((e) => e.codigo === f.estado)?.nombre ?? f.estado}`);
  if (f.resultado) t.push(`Resultado: ${f.resultado === "efectivo" ? "efectivo" : "inefectivo"}`);
  const r = rangoDelPeriodo(f.periodo, hoy, f.desde, f.hasta);
  t.push(r.desde || r.hasta ? `Fecha de registro (hora de Bogotá): ${r.desde ? `desde el ${fmtDia(r.desde)}` : "sin inicio"}${r.hasta ? ` hasta el ${fmtDia(r.hasta)}` : ""}` : "Fecha de registro: todas");
  if (f.riesgo) t.push(`Riesgo inmediato: ${f.riesgo === "si" ? "sí" : "no"}`);
  t.push(f.ocultos === "no" ? "Ocultos: excluidos" : f.ocultos === "si" ? "Ocultos: solo los ocultos" : "Ocultos: incluidos y marcados");
  if (f.zona !== "todas") t.push(`Zona: ${f.zona === "dentro" ? "dentro de la zona" : "fuera de la zona"}`);
  if (f.busqueda.trim()) t.push(`Texto: «${f.busqueda.trim()}»`);
  return t;
}
/** Filtros que solo existen en pantalla (la descarga no los aplica). */
export const filtrosSoloPantalla = (f: FiltrosUI): string[] => [...(f.zona !== "todas" ? ["zona"] : []), ...(f.busqueda.trim() ? ["búsqueda de texto"] : [])];
