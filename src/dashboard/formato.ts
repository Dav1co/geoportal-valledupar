// Formato es-CO del tablero. Regla: nunca celdas vacías ni "(En blanco)";
// cuando un dato no existe se muestra "—" o un texto que explica por qué.

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

export function etiquetaPeriodo(p: string): string {
  if (!/^\d{6}$/.test(p)) return p;
  const mes = MESES[Number(p.slice(4)) - 1] ?? p.slice(4);
  return `${mes} ${p.slice(0, 4)}`;
}

export function etiquetaCorta(p: string): string {
  const larga = etiquetaPeriodo(p);
  return larga.length > 4 ? `${larga.slice(0, 3)} ${p.slice(0, 4)}` : larga;
}

// $ 5.983,96 M — montos en millones; sin decimales desde 10.000 M.
export function fmtMillones(v: number | null): string {
  if (v == null) return "—";
  const m = v / 1e6;
  const dec = Math.abs(m) >= 10_000 ? 0 : 2;
  return `$ ${m.toLocaleString("es-CO", {
    minimumFractionDigits: dec,
    maximumFractionDigits: dec,
  })} M`;
}

// Ciclos: la facturación los trae como 'CICLO 05' y consumo_metodo como '5'.
// Se comparan por número; la etiqueta usa el formato de la facturación.
export function numeroCiclo(c: string): number | null {
  const m = /\d+/.exec(c);
  return m ? Number(m[0]) : null;
}
export function etiquetaCiclo(n: number): string {
  return `CICLO ${String(n).padStart(2, "0")}`;
}

// Pesos en millones SIN decimales, para columnas de tabla donde fmtMillones
// mezclaría cifras con y sin decimales: $ 26.870 M.
export function fmtMillonesEnteros(v: number | null): string {
  if (v == null) return "—";
  return `$ ${(v / 1e6).toLocaleString("es-CO", { maximumFractionDigits: 0 })} M`;
}

export function fmtEntero(v: number | null): string {
  return v == null ? "—" : v.toLocaleString("es-CO", { maximumFractionDigits: 0 });
}

// Rótulos de pantalla para la presencia de medidor. UNA sola definición: las
// secciones nuevas (rangos y consumo básico) no escriben "medidor" a mano.
export const ETIQ_CON_MEDIDOR = "con medidor registrado";
export const ETIQ_SIN_MEDIDOR = "sin medidor registrado";

// Número con decimales fijos y coma decimal: 30,6.
export function fmtDecimal(v: number | null, decimales = 1): string {
  return v == null
    ? "—"
    : v.toLocaleString("es-CO", { minimumFractionDigits: decimales, maximumFractionDigits: decimales });
}

export function fmtPct(v: number | null): string {
  if (v == null) return "—";
  return `${v.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`;
}

// IPUF: m³ por suscriptor-mes, NO un porcentaje. "13,68 m³/susc·mes".
// conUnidad=false deja solo el número (encabezados de tabla que ya traen la unidad).
export function fmtIpuf(v: number | null, conUnidad = true): string {
  if (v == null) return "—";
  const n = v.toLocaleString("es-CO", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return conUnidad ? `${n} m³/susc·mes` : n;
}

// Diferencia entre dos valores: "+$ 12,3 M (+2,1 %)".
export function fmtDelta(
  actual: number | null,
  base: number | null,
  formato: (v: number | null) => string = fmtMillones,
): string {
  if (actual == null || base == null) return "—";
  const d = actual - base;
  const signo = d >= 0 ? "+" : "−";
  const abs = formato(Math.abs(d));
  const pct =
    base !== 0
      ? ` (${signo}${(Math.abs(d / base) * 100).toLocaleString("es-CO", {
          minimumFractionDigits: 1,
          maximumFractionDigits: 1,
        })} %)`
      : "";
  return `${signo}${abs}${pct}`;
}

// CIFRAS COMPLETAS, sin abreviar: $ 5.983.961.190,61 en vez de
// "$ 5.983,96 M". Es el formato de la pantalla Consolidado, que se copia
// a Excel para informes de gerencia — un valor abreviado no se puede
// sumar ni cruzar. La abreviación se queda en las tarjetas de KPI de las
// otras pantallas, donde el espacio manda y nadie copia el número.
export function fmtPesosCompleto(v: number | null, decimales = 2): string {
  if (v == null) return "—";
  // \u00A0 = espacio de no separación: mantiene el "$" pegado a la cifra
  // para que nunca quede colgando en la línea anterior.
  return `$\u00A0${v.toLocaleString("es-CO", {
    minimumFractionDigits: decimales,
    maximumFractionDigits: decimales,
  })}`;
}

// Entero completo con separador de miles (m³, cupones, contratos).
export function fmtEnteroCompleto(v: number | null): string {
  return v == null ? "—" : v.toLocaleString("es-CO", { maximumFractionDigits: 0 });
}

// Variación absoluta en cifras completas, con signo explícito.
export function fmtDeltaCompleto(actual: number | null, base: number | null): string {
  if (actual == null || base == null) return "—";
  const d = actual - base;
  return `${d >= 0 ? "+" : "−"}${fmtPesosCompleto(Math.abs(d))}`;
}

// Variación porcentual con signo.
export function fmtDeltaPct(actual: number | null, base: number | null): string {
  if (actual == null || base == null || base === 0) return "—";
  const d = ((actual - base) / Math.abs(base)) * 100;
  return `${d >= 0 ? "+" : "−"}${Math.abs(d).toLocaleString("es-CO", {
    minimumFractionDigits: 1, maximumFractionDigits: 1,
  })} %`;
}
