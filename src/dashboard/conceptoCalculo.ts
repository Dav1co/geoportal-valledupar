// Cálculos PUROS (sin React) de «Cartera por concepto» sobre bi.v_cartera_concepto_dim (sql/49). Describe la COMPOSICIÓN de la cartera por tipo de concepto, uso, estrato y
// tramo de edad; no es una causa y la fuente no trae contrato (el recargo por contrato no se puede obtener). Neto = suma de todo; bruto = neto sin los subsidios y descuentos.
import type { CarteraConceptoDim } from "./tipos";
import { LECTURA_PROVISIONAL, tramosAnuales, type LecturaLimites } from "./edadCartera";
import { COLOR_TRAMO_EDAD } from "./edadCarteraCalculo";
import { filtrarUsoEstrato } from "./moraEmdCalculo";
import type { TipoConcepto } from "./conceptoTipos";

export const ROTULO_TIPO: Record<TipoConcepto, string> = {
  capital_alcantarillado: "Capital · alcantarillado",
  capital_acueducto: "Capital · acueducto",
  recargo_moratorio: "Recargo moratorio",
  financiacion_capital: "Financiación del capital",
  financiacion_recargo: "Financiación del recargo",
  financiacion_otros: "Financiación de otros cargos",
  interes_financiacion: "Interés de financiación",
  contribucion: "Contribución (solidaridad)",
  corte_susp_reconexion: "Corte, suspensión y reconexión (no EMD)",
  cargos_emd: "Cargos EMD",
  conexion_obras: "Conexión y obras",
  otros: "Otros",
  subsidios_descuentos: "Subsidios y descuentos",
};
/** Tipos que suman al bruto, en el orden de la pantalla. Los subsidios y descuentos (negativos) van aparte. */
export const TIPOS_BRUTO: TipoConcepto[] = [
  "capital_alcantarillado", "capital_acueducto", "recargo_moratorio", "financiacion_capital", "financiacion_recargo", "financiacion_otros",
  "interes_financiacion", "contribucion", "corte_susp_reconexion", "cargos_emd", "conexion_obras", "otros",
];
export const CAPITAL: TipoConcepto[] = ["capital_alcantarillado", "capital_acueducto"];
export const FINANCIACION: TipoConcepto[] = ["financiacion_capital", "financiacion_recargo", "financiacion_otros", "interes_financiacion"];
export const COLOR_TIPO: Record<TipoConcepto, string> = {
  capital_alcantarillado: "#0A2540", capital_acueducto: "#2E7D9E", recargo_moratorio: "#B23A48", financiacion_capital: "#C98A2D", financiacion_recargo: "#D9A441",
  financiacion_otros: "#E4C27A", interes_financiacion: "#8A6A1F", contribucion: "#0E7C86", corte_susp_reconexion: "#7A5C99", cargos_emd: "#4B3A66",
  conexion_obras: "#8A99A8", otros: "#B9C3CD", subsidios_descuentos: "#3E8E5B",
};

const REP: Record<string, string> = { "0_330": "0", "360": "360", "720": "720", "1080": "1080", "1440": "1440", "1800": "1800", "1801": "1801", sin_edad: "sin_edad" };
/** Tramo anual (según la lectura de límites) de un tramo de la dimensión. */
export function tramoAnualDeConcepto(tramo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL) {
  const rep = REP[tramo];
  return tramosAnuales(lectura).find((t) => (t.etiquetas as string[]).includes(rep)) ?? null;
}

export const filtrarConcepto = (filas: CarteraConceptoDim[], uso: string, estrato: string) => filtrarUsoEstrato(filas, uso, estrato);
const sum = (xs: { valor: number }[]) => xs.reduce((s, x) => s + x.valor, 0);

export type ComposicionTipo = { tipo: TipoConcepto; valor: number; pctNeto: number | null; pctBruto: number | null };
export function composicionPorTipo(filas: CarteraConceptoDim[], periodo: string) {
  const del = filas.filter((f) => f.periodo === periodo);
  const por = (t: string) => sum(del.filter((f) => f.tipo === t));
  const neto = sum(del);
  const subsidios = por("subsidios_descuentos");
  const bruto = neto - subsidios;
  const tipos: ComposicionTipo[] = TIPOS_BRUTO.map((t) => ({ tipo: t, valor: por(t), pctNeto: neto ? (por(t) / neto) * 100 : null, pctBruto: bruto ? (por(t) / bruto) * 100 : null }));
  return { neto, bruto, subsidios, tipos, recargo: por("recargo_moratorio"), capital: CAPITAL.reduce((s, t) => s + por(t), 0), financiacion: FINANCIACION.reduce((s, t) => s + por(t), 0) };
}

export type FilaTramo = { llave: string; rotulo: string; color: string; valores: Record<string, number> };
/** Valor por tipo en cada tramo anual (7) de un periodo. */
export function valoresPorTramo(filas: CarteraConceptoDim[], periodo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL): FilaTramo[] {
  const tr = tramosAnuales(lectura);
  const filasT: FilaTramo[] = tr.map((t) => ({ llave: t.llave, rotulo: t.rotulo, color: COLOR_TRAMO_EDAD[t.llave], valores: {} }));
  for (const f of filas) {
    if (f.periodo !== periodo) continue;
    const t = tramoAnualDeConcepto(f.tramo, lectura);
    const fila = filasT.find((x) => x.llave === t?.llave);
    if (fila) fila.valores[f.tipo] = (fila.valores[f.tipo] ?? 0) + f.valor;
  }
  return filasT;
}
export const totalFila = (f: FilaTramo, tipos?: string[]) => Object.entries(f.valores).filter(([t]) => !tipos || tipos.includes(t)).reduce((s, [, v]) => s + v, 0);

export type RecargoTramo = { llave: string; rotulo: string; recargo: number; capital: number; neto: number; razon: number | null; pctNeto: number | null };
/** Recargo moratorio frente al capital (acueducto + alcantarillado, bruto) por tramo anual. */
export function recargoVsCapital(filas: CarteraConceptoDim[], periodo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL): RecargoTramo[] {
  return valoresPorTramo(filas, periodo, lectura).map((f) => {
    const recargo = f.valores["recargo_moratorio"] ?? 0;
    const capital = CAPITAL.reduce((s, t) => s + (f.valores[t] ?? 0), 0);
    const neto = totalFila(f);
    return { llave: f.llave, rotulo: f.rotulo, recargo, capital, neto, razon: capital ? (recargo / capital) * 100 : null, pctNeto: neto ? (recargo / neto) * 100 : null };
  });
}

export function evolucionRecargo(filas: CarteraConceptoDim[], periodos: string[]) {
  return periodos.map((p) => {
    const c = composicionPorTipo(filas, p);
    return { periodo: p, recargo: c.recargo, capital: c.capital, neto: c.neto, bruto: c.bruto, pctNeto: c.neto ? (c.recargo / c.neto) * 100 : null, pctBruto: c.bruto ? (c.recargo / c.bruto) * 100 : null, razon: c.capital ? (c.recargo / c.capital) * 100 : null };
  });
}

/** Perfil de edad de cada tipo: % de su valor en cada tramo anual (solo tipos con valor positivo). */
export function perfilEdadPorTipo(filas: CarteraConceptoDim[], periodo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL) {
  const ft = valoresPorTramo(filas, periodo, lectura);
  return TIPOS_BRUTO.map((tipo) => {
    const valores = ft.map((f) => f.valores[tipo] ?? 0);
    const total = valores.reduce((s, v) => s + v, 0);
    return { tipo, total, tramos: ft.map((f, i) => ({ llave: f.llave, rotulo: f.rotulo, color: f.color, valor: valores[i], pct: total ? (valores[i] / total) * 100 : null })) };
  }).filter((x) => x.total > 0);
}

export const ESTRATOS = ["1", "2", "3", "4", "5", "6", "otros"];
/** Subsidios y descuentos por estrato (valor y % del bruto de cada estrato) en un periodo. */
export function subsidiosPorEstrato(filas: CarteraConceptoDim[], periodo: string) {
  const del = filas.filter((f) => f.periodo === periodo);
  return ESTRATOS.map((e) => {
    const sub = sum(del.filter((f) => f.estrato === e && f.tipo === "subsidios_descuentos"));
    const bruto = sum(del.filter((f) => f.estrato === e && f.tipo !== "subsidios_descuentos"));
    return { estrato: e, subsidios: sub, bruto, pct: bruto ? (sub / bruto) * 100 : null };
  }).filter((x) => x.subsidios !== 0 || x.bruto !== 0);
}
export function subsidiosPorEdad(filas: CarteraConceptoDim[], periodo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL) {
  return valoresPorTramo(filas, periodo, lectura).map((f) => {
    const sub = f.valores["subsidios_descuentos"] ?? 0;
    const bruto = totalFila(f) - sub;
    return { llave: f.llave, rotulo: f.rotulo, subsidios: sub, bruto, pct: bruto ? (sub / bruto) * 100 : null };
  });
}

/** La franja más vieja («mayor1800») separada: valor por tipo, % de su bruto y de su neto. */
export function franjaMasVieja(filas: CarteraConceptoDim[], periodo: string, lectura: LecturaLimites = LECTURA_PROVISIONAL) {
  const f = valoresPorTramo(filas, periodo, lectura).find((x) => x.llave === "mayor1800");
  if (!f) return null;
  const neto = totalFila(f);
  const sub = f.valores["subsidios_descuentos"] ?? 0;
  const bruto = neto - sub;
  const tipos = TIPOS_BRUTO.map((t) => ({ tipo: t, valor: f.valores[t] ?? 0, pctBruto: bruto ? ((f.valores[t] ?? 0) / bruto) * 100 : null })).filter((x) => x.valor !== 0);
  return { rotulo: f.rotulo, neto, bruto, subsidios: sub, tipos };
}
