// Captura y presentación de números de la pantalla de Técnica (formato colombiano). Lógica PURA, sin React.
// Regla aprobada: se acepta UN solo separador decimal (coma o punto) y NINGÚN separador de miles. Lo ambiguo no se adivina: se pide corregir.

export type Interpretado =
  | { tipo: "vacio" }
  | { tipo: "ok"; valor: number; decimales: number }
  | { tipo: "error"; motivo: string };

/** Interpreta lo que la persona escribió. Devuelve el número (con punto como separador interno) o el motivo por el que no se puede aceptar. */
export function interpretarNumero(entrada: string): Interpretado {
  const t = entrada.trim();
  if (t === "") return { tipo: "vacio" };
  if (/\s/.test(t)) return { tipo: "error", motivo: "Escriba el número sin espacios." };
  if (/[^0-9.,+-]/.test(t)) return { tipo: "error", motivo: "Escriba solo cifras, con coma o punto decimal." };
  const m = /^(-?)(\d+)(?:([.,])(\d+))?$/.exec(t);
  if (!m) {
    if (/[.,].*[.,]/.test(t)) return { tipo: "error", motivo: "Use un solo separador decimal y no escriba separador de miles (por ejemplo 1480,5)." };
    return { tipo: "error", motivo: "Ese valor no es un número. Escríbalo con cifras, por ejemplo 7,6." };
  }
  const [, signo, entero, sep, dec = ""] = m;
  // «1.480» o «1,480»: tres cifras tras el separador y de una a tres antes (sin cero inicial) se leen como miles en unos países y como decimales en otros. No se adivina.
  if (sep && dec.length === 3 && entero.length <= 3 && !entero.startsWith("0")) {
    return {
      tipo: "error",
      motivo: `«${t}» es ambiguo. Si son ${entero}${dec} unidades, escriba ${entero}${dec} sin separador; si es ${entero},${dec.replace(/0+$/, "") || "0"}, escríbalo con ese decimal.`,
    };
  }
  const valor = Number(`${signo}${entero}${dec ? "." + dec : ""}`);
  if (!Number.isFinite(valor)) return { tipo: "error", motivo: "Ese valor no es un número." };
  return { tipo: "ok", valor, decimales: dec.length };
}

/** Formato colombiano: punto para miles, coma para decimales. Se arma a mano (Intl «es» no agrupa los números de 4 cifras). */
export function formatearNumero(valor: number, decimales: number): string {
  const d = Math.max(0, Math.min(6, Math.trunc(decimales)));
  const [ent, dec] = Math.abs(valor).toFixed(d).split(".");
  const miles = ent.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const negativo = valor < 0 && Number(`${ent}.${dec ?? "0"}`) !== 0;
  return `${negativo ? "-" : ""}${miles}${dec ? "," + dec : ""}`;
}

/** Para el resumen: valor del servidor (o nulo) con los decimales de la variable; «—» si no hay dato. */
export function formatearOGuion(valor: number | null | undefined, decimales: number): string {
  return valor === null || valor === undefined ? "—" : formatearNumero(valor, decimales);
}

/** Para la confirmación: al menos los decimales de la variable y, si la persona escribió más, esos (hasta 6). */
export const decimalesAMostrar = (decimalesVariable: number, escritos: number) => Math.min(6, Math.max(decimalesVariable, escritos));
