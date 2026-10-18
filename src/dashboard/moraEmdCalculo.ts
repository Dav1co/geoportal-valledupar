// Cálculos PUROS (sin React) de «Movimiento de la mora» (bi.v_cartera_transicion_dim, sql/47) y «Suspensiones y cortes» (bi.v_emd_dim, sql/48). Todo sale de
// las dos dimensiones, ya agregadas y con el mínimo de 5 contratos por celda; aquí solo se suman, se filtran por uso y estrato y se redactan lecturas.
// Es una DESCRIPCIÓN de lo que pasó con los contratos, no una causa.
import type { CarteraTransicionDim, EmdDim } from "./tipos";
import { codigoEstratoDeNombre, codigoUsoDeNombre, TODOS_EDAD } from "./edadCarteraCalculo";

export const GRUPOS_MORA = ["sin_deuda", "al_dia", "v1_2", "v3_8", "v9_24", "v_mas24"] as const;
export const ROTULO_GRUPO: Record<string, string> = {
  sin_deuda: "Sin deuda",
  al_dia: "Al día con deuda",
  v1_2: "1-2 facturas",
  v3_8: "3-8 facturas",
  v9_24: "9-24 facturas",
  v_mas24: "Más de 24 facturas",
  no_estaba: "No estaba (contrato nuevo)",
  no_esta: "Ya no está",
  agrupada: "Agrupada (celdas pequeñas)",
};
/** Rango de gestión drástica = más de 8 facturas vencidas (grupos 9-24 y más de 24). */
export const PROFUNDA = new Set(["v9_24", "v_mas24"]);
/** Con deuda o sin ella pero fuera del rango de gestión drástica y existente en ambos meses. */
const FUERA = new Set(["sin_deuda", "al_dia", "v1_2", "v3_8"]);
const CON_DEUDA = new Set(["al_dia", "v1_2", "v3_8", "v9_24", "v_mas24"]);

export const sumarPeriodo = (p: string, k: number): string => {
  const total = Number(p.slice(0, 4)) * 12 + (Number(p.slice(4)) - 1) + k;
  return `${Math.floor(total / 12)}${String((total % 12) + 1).padStart(2, "0")}`;
};

/** Filtra cualquier dimensión con uso y estrato por los nombres de la pantalla («todos» no filtra). */
export function filtrarUsoEstrato<T extends { uso: string; estrato: string }>(filas: T[], uso: string, estrato: string): T[] {
  const cu = uso === TODOS_EDAD ? null : codigoUsoDeNombre(uso);
  const ce = estrato === TODOS_EDAD ? null : codigoEstratoDeNombre(estrato);
  return filas.filter((f) => (cu == null || f.uso === cu) && (ce == null || f.estrato === ce));
}

const c = (x: number | null) => x ?? 0;

// ---------------- Movimiento de la mora ----------------
export type Movimiento = {
  total: number;                  // contratos con grupo conocido (sin celdas «agrupada» ni vacías)
  profundaOrigen: number;
  profundaDestino: number;
  saldoProfundaDestino: number;
  entradas: number;               // venían fuera de la profunda (existentes) y llegan a ella
  salidas: number;                // venían de la profunda y quedan fuera de ella (existentes)
  permanencia: number;            // profunda en ambos meses
  pasoSinDeuda: number;           // tenían deuda y pasan a «sin deuda»
  pasoSinDeudaDesdeProfunda: number;
  nuevos: number;                 // no estaban en el mes de origen
  yaNoEstan: number;              // ya no están en el mes de destino
  agrupadas: number;              // contratos en celdas «agrupada» (no se asignan a ninguna ficha)
  celdasVacias: number;           // celdas con menos de 5 contratos, publicadas vacías
};

export function movimiento(filas: CarteraTransicionDim[]): Movimiento {
  const m: Movimiento = { total: 0, profundaOrigen: 0, profundaDestino: 0, saldoProfundaDestino: 0, entradas: 0, salidas: 0, permanencia: 0, pasoSinDeuda: 0, pasoSinDeudaDesdeProfunda: 0, nuevos: 0, yaNoEstan: 0, agrupadas: 0, celdasVacias: 0 };
  for (const f of filas) {
    if (f.contratos == null) { m.celdasVacias += 1; continue; }
    const n = f.contratos, o = f.grupo_origen, d = f.grupo_destino;
    if (o === "agrupada" || d === "agrupada") { m.agrupadas += n; continue; }
    m.total += n;
    if (PROFUNDA.has(o)) m.profundaOrigen += n;
    if (PROFUNDA.has(d)) { m.profundaDestino += n; m.saldoProfundaDestino += c(f.saldo_destino); }
    if (o === "no_estaba") m.nuevos += n;
    if (d === "no_esta") m.yaNoEstan += n;
    if (FUERA.has(o) && PROFUNDA.has(d)) m.entradas += n;
    if (PROFUNDA.has(o) && FUERA.has(d)) m.salidas += n;
    if (PROFUNDA.has(o) && PROFUNDA.has(d)) m.permanencia += n;
    if (CON_DEUDA.has(o) && d === "sin_deuda") { m.pasoSinDeuda += n; if (PROFUNDA.has(o)) m.pasoSinDeudaDesdeProfunda += n; }
  }
  return m;
}

export const ORIGENES = ["no_estaba", "sin_deuda", "al_dia", "v1_2", "v3_8", "v9_24", "v_mas24", "agrupada"];
export const DESTINOS = ["sin_deuda", "al_dia", "v1_2", "v3_8", "v9_24", "v_mas24", "no_esta", "agrupada"];

export type CeldaMatriz = { contratos: number; saldoOrigen: number; saldoDestino: number };
export function matrizTransicion(filas: CarteraTransicionDim[]) {
  const celdas = new Map<string, CeldaMatriz>();
  for (const f of filas) {
    if (f.contratos == null) continue;
    const k = `${f.grupo_origen}|${f.grupo_destino}`;
    const a = celdas.get(k) ?? { contratos: 0, saldoOrigen: 0, saldoDestino: 0 };
    a.contratos += f.contratos; a.saldoOrigen += c(f.saldo_origen); a.saldoDestino += c(f.saldo_destino);
    celdas.set(k, a);
  }
  const celda = (o: string, d: string): CeldaMatriz => celdas.get(`${o}|${d}`) ?? { contratos: 0, saldoOrigen: 0, saldoDestino: 0 };
  const origenes = ORIGENES.filter((o) => DESTINOS.some((d) => celda(o, d).contratos > 0));
  const destinos = DESTINOS.filter((d) => ORIGENES.some((o) => celda(o, d).contratos > 0));
  const totalFila = (o: string) => destinos.reduce((s, d) => s + celda(o, d).contratos, 0);
  const totalCol = (d: string) => origenes.reduce((s, o) => s + celda(o, d).contratos, 0);
  return { origenes, destinos, celda, totalFila, totalCol, total: origenes.reduce((s, o) => s + totalFila(o), 0) };
}

export type Cohorte = {
  base: number;            // contratos en el rango de gestión drástica en el mes base (los que se pueden clasificar)
  siguen: number;
  bajan: number;           // a 8 facturas o menos, con deuda
  sinDeuda: number;
  yaNoEstan: number;
  agrupados: number;       // de la cohorte, en celdas con destino «agrupada»
  saldoBase: number;
  saldoDestino: number;
};
/** Contratos que estaban en el rango de gestión drástica en el mes base y dónde están en `periodo` (filas de referencia 'base' de ese periodo). */
export function cohorte(filas: CarteraTransicionDim[]): Cohorte {
  const k: Cohorte = { base: 0, siguen: 0, bajan: 0, sinDeuda: 0, yaNoEstan: 0, agrupados: 0, saldoBase: 0, saldoDestino: 0 };
  for (const f of filas) {
    if (f.contratos == null || !PROFUNDA.has(f.grupo_origen)) continue;
    const n = f.contratos, d = f.grupo_destino;
    k.base += n; k.saldoBase += c(f.saldo_origen); k.saldoDestino += c(f.saldo_destino);
    if (PROFUNDA.has(d)) k.siguen += n;
    else if (d === "sin_deuda") k.sinDeuda += n;
    else if (d === "no_esta") k.yaNoEstan += n;
    else if (d === "agrupada") k.agrupados += n;
    else k.bajan += n;
  }
  return k;
}

export function evolucionMovimiento(filas: CarteraTransicionDim[]) {
  const periodos = [...new Set(filas.filter((f) => f.referencia === "anterior").map((f) => f.periodo))].sort();
  return periodos.map((p) => ({ periodo: p, ...movimiento(filas.filter((f) => f.periodo === p && f.referencia === "anterior")) }));
}

// ---------------- Suspensiones y cortes (EMD) ----------------
export const PRIMER_PERIODO_EMD = "202605";
export const CODIGOS_EMD = [
  { codigo: "600", nombre: "Corte sencillo", clase: "corte" },
  { codigo: "602", nombre: "Suspensión sencilla", clase: "corte" },
  { codigo: "603", nombre: "Reinstalación sencilla", clase: "reinstalacion" },
  { codigo: "605", nombre: "Corte drástico", clase: "corte" },
  { codigo: "606", nombre: "Reconexión drástica", clase: "reinstalacion" },
] as const;
const CORTE_SUSP = new Set(["600", "602", "605"]);
export const ROTULO_ESTADO: Record<string, string> = {
  activo: "Activo", retirado: "Retirado", coactivo: "Bloqueo coactivo", suspendido: "Suspendido", otro: "Otro", sin_cartera: "Sin cartera", agrupada: "Agrupada (celdas pequeñas)",
};
export const ESTADOS_ORDEN = ["activo", "suspendido", "coactivo", "retirado", "otro", "sin_cartera", "agrupada"];
export const MORAS_EMD = [...GRUPOS_MORA, "sin_cartera", "agrupada"] as string[];

export type EmdMes = { periodo: string; sinDatos: boolean; porCodigo: Record<string, { contratos: number; valor: number }>; agrupado: { contratos: number; valor: number; vacio: boolean }; corteSusp: number; reinstRecon: number; valorTotal: number };
export function emdPorMes(filas: EmdDim[], periodos: string[]): EmdMes[] {
  return periodos.map((p) => {
    const del = filas.filter((f) => f.periodo === p);
    const sinDatos = p < PRIMER_PERIODO_EMD || del.some((f) => f.codigo === "sin_datos");
    const porCodigo: EmdMes["porCodigo"] = Object.fromEntries(CODIGOS_EMD.map((x) => [x.codigo, { contratos: 0, valor: 0 }]));
    const agrupado = { contratos: 0, valor: 0, vacio: false };
    for (const f of del) {
      if (f.codigo === "sin_datos") continue;
      if (f.codigo === "agrupado") { agrupado.contratos += c(f.contratos); agrupado.valor += c(f.valor_facturado); if (f.contratos == null) agrupado.vacio = true; continue; }
      const a = porCodigo[f.codigo]; if (a) { a.contratos += c(f.contratos); a.valor += c(f.valor_facturado); }
    }
    const corteSusp = CODIGOS_EMD.filter((x) => CORTE_SUSP.has(x.codigo)).reduce((s, x) => s + porCodigo[x.codigo].contratos, 0);
    const reinstRecon = CODIGOS_EMD.filter((x) => !CORTE_SUSP.has(x.codigo)).reduce((s, x) => s + porCodigo[x.codigo].contratos, 0);
    const valorTotal = Object.values(porCodigo).reduce((s, x) => s + x.valor, 0) + agrupado.valor;
    return { periodo: p, sinDatos, porCodigo, agrupado, corteSusp, reinstRecon, valorTotal };
  });
}

/** Matriz código × valor de `campo` (mora o estado_producto) en un periodo, en contratos (pares contrato-código). */
export function emdCruce(filas: EmdDim[], periodo: string, campo: "mora" | "estado_producto") {
  const del = filas.filter((f) => f.periodo === periodo && f.codigo !== "sin_datos" && f.contratos != null);
  const m = new Map<string, number>();
  for (const f of del) { const k = `${f.codigo}|${f[campo]}`; m.set(k, (m.get(k) ?? 0) + c(f.contratos)); }
  const get = (cod: string, v: string) => m.get(`${cod}|${v}`) ?? 0;
  const codigos = [...CODIGOS_EMD.map((x) => x.codigo as string), "agrupado"].filter((cod) => del.some((f) => f.codigo === cod));
  return { codigos, get, totalCodigo: (cod: string, vs: string[]) => vs.reduce((s, v) => s + get(cod, v), 0) };
}

/** De los contratos con corte o suspensión facturado (600, 602, 605), cuántos están en cada estado del producto y en el rango de gestión drástica. */
export function corteSuspensionDetalle(filas: EmdDim[], periodo: string) {
  const del = filas.filter((f) => f.periodo === periodo && CORTE_SUSP.has(f.codigo) && f.contratos != null);
  const total = del.reduce((s, f) => s + c(f.contratos), 0);
  const porEstado = (e: string) => del.filter((f) => f.estado_producto === e).reduce((s, f) => s + c(f.contratos), 0);
  const profunda = del.filter((f) => PROFUNDA.has(f.mora)).reduce((s, f) => s + c(f.contratos), 0);
  return { total, activos: porEstado("activo"), suspendidos: porEstado("suspendido"), coactivos: porEstado("coactivo"), retirados: porEstado("retirado"), profunda };
}

/** Rango de gestión drástica con y sin corte o suspensión facturado en el mes: «con» sale de v_emd_dim; el universo del rango de gestión drástica, de la transición (destino). */
export function profundaConSin(emd: EmdDim[], trans: CarteraTransicionDim[], periodo: string) {
  const con = corteSuspensionDetalle(emd, periodo).profunda;
  const universo = movimiento(trans.filter((f) => f.periodo === periodo && f.referencia === "anterior")).profundaDestino;
  return { con, universo, sin: Math.max(0, universo - con) };
}
