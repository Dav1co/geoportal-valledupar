// Consultar direcciones (25-nov): lectura de las unidades del censo (catastro_valledupar.unih / uninh) para mostrarlas. Lógica PURA (se prueba en Node).
// El valor viene como una LISTA de unidades, cada una terminada en «,», con sus segmentos separados por guiones:
//   «- 4- - - CASA- CS- 1- - - - ,- - - - - APTO- AP- 101- - - - ,-» → 2 unidades: «4 · CASA · CS · 1» y «APTO · AP · 101».
// No se interpreta cada posición: solo se quitan los segmentos vacíos. «NO APLICA» → «No aplica»; vacío → «Sin dato». El original se muestra aparte.
export type LecturaUnidades = { estado: "sin_dato" | "no_aplica" | "unidades"; unidades: string[]; original: string | null };

export function leerUnidades(valor: string | null | undefined): LecturaUnidades {
  const original = valor && valor.trim() ? valor.trim() : null;
  if (!original) return { estado: "sin_dato", unidades: [], original: null };
  if (/^no aplica$/i.test(original.replace(/\s+/g, " "))) return { estado: "no_aplica", unidades: [], original };
  const unidades = original.split(",")
    .map((u) => u.split("-").map((s) => s.trim().replace(/\s+/g, " ")).filter((s) => s !== "").join(" · "))
    .filter((u) => u !== "");
  return unidades.length ? { estado: "unidades", unidades, original } : { estado: "sin_dato", unidades: [], original };
}

/** «1 unidad», «3 unidades». */
export const cuantasUnidades = (n: number) => `${n.toLocaleString("es-CO")} ${n === 1 ? "unidad" : "unidades"}`;
