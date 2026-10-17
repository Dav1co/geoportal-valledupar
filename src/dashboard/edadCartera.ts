// Mapeo ÚNICO de la etiqueta de edad de bi.v_cartera_edad_dim (sql/45) a su rótulo y a su tramo.
// La base guarda la etiqueta CRUDA de hechos.cartera_edades ("0", "30", … "360", "720", "1080", "1440",
// "1800", "1801" y "sin_edad" = financiada); aquí se decide cómo se lee. Cambiar la lectura de los límites
// es cambiar LECTURA_PROVISIONAL, sin tocar la base.
//
// Dos lecturas candidatas (a confirmar con Facturación; la pantalla no se publica hasta confirmar):
//  · "superior": la etiqueta es el LÍMITE SUPERIOR del tramo (360 = 331 a 360; 720 = 361 a 720; 1801 = más de 1.800).
//    Respaldo en los datos: la etiqueta 360 tiene el tamaño de una etiqueta mensual (de 30 días) y la 720 el de un año
//    completo; las etiquetas anuales siguientes decrecen de forma regular.
//  · "inferior": la etiqueta es el LÍMITE INFERIOR (360 = 360 a 719). Es la lectura de sql/13 y la del tablero
//    actual ("Más de 360 días" incluye la etiqueta 360), pero dejaría la etiqueta 360 con un valor mensual para un año entero.

export type LecturaLimites = "superior" | "inferior";

/** Valor por defecto PROVISIONAL (David lo confirma viendo la pantalla). */
export const LECTURA_PROVISIONAL: LecturaLimites = "superior";

/** Etiquetas crudas en el orden de la fuente; "sin_edad" (orden 99 en la base) = cartera financiada. */
export const ETIQUETAS_EDAD = [
  "0", "30", "60", "90", "120", "150", "180", "210", "240", "270", "300", "330", "360",
  "720", "1080", "1440", "1800", "1801", "sin_edad",
] as const;
export type EtiquetaEdad = (typeof ETIQUETAS_EDAD)[number];

/** Etiquetas mensuales (de a 30 días), hasta la 330; la 360 se trata aparte porque su tamaño es mensual. */
const MENSUALES = ["0", "30", "60", "90", "120", "150", "180", "210", "240", "270", "300", "330"];

export const NOTA_ROTULOS =
  "Rótulos según el reporte de origen; límites superiores de cada tramo.";
export const NOTA_ROTULOS_INFERIOR =
  "Rótulos según el reporte de origen; límites inferiores de cada tramo.";

/** Tramos anuales de la pantalla: llave estable, rótulo y etiquetas crudas que contiene, según la lectura. */
export interface TramoAnual {
  llave: "hasta360" | "t2" | "t3" | "t4" | "t5" | "mayor1800" | "financiada";
  rotulo: string;
  etiquetas: EtiquetaEdad[];
}

const SUPERIOR: TramoAnual[] = [
  { llave: "hasta360", rotulo: "Hasta 360 días", etiquetas: ["0", "30", "60", "90", "120", "150", "180", "210", "240", "270", "300", "330", "360"] },
  { llave: "t2", rotulo: "361 a 720 días", etiquetas: ["720"] },
  { llave: "t3", rotulo: "721 a 1.080 días", etiquetas: ["1080"] },
  { llave: "t4", rotulo: "1.081 a 1.440 días", etiquetas: ["1440"] },
  { llave: "t5", rotulo: "1.441 a 1.800 días", etiquetas: ["1800"] },
  { llave: "mayor1800", rotulo: "Más de 1.800 días", etiquetas: ["1801"] },
  { llave: "financiada", rotulo: "Financiada", etiquetas: ["sin_edad"] },
];

const INFERIOR: TramoAnual[] = [
  { llave: "hasta360", rotulo: "Menos de 360 días", etiquetas: ["0", "30", "60", "90", "120", "150", "180", "210", "240", "270", "300", "330"] },
  { llave: "t2", rotulo: "360 a 719 días", etiquetas: ["360"] },
  { llave: "t3", rotulo: "720 a 1.079 días", etiquetas: ["720"] },
  { llave: "t4", rotulo: "1.080 a 1.439 días", etiquetas: ["1080"] },
  { llave: "t5", rotulo: "1.440 a 1.799 días", etiquetas: ["1440"] },
  { llave: "mayor1800", rotulo: "1.800 días o más", etiquetas: ["1800", "1801"] },
  { llave: "financiada", rotulo: "Financiada", etiquetas: ["sin_edad"] },
];

export function tramosAnuales(lectura: LecturaLimites = LECTURA_PROVISIONAL): TramoAnual[] {
  return lectura === "superior" ? SUPERIOR : INFERIOR;
}

export function notaRotulos(lectura: LecturaLimites = LECTURA_PROVISIONAL): string {
  return lectura === "superior" ? NOTA_ROTULOS : NOTA_ROTULOS_INFERIOR;
}

/** Tramo anual de una etiqueta cruda (null si la etiqueta no se conoce). */
export function tramoDeEtiqueta(
  etiqueta: string,
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
): TramoAnual | null {
  return tramosAnuales(lectura).find((t) => (t.etiquetas as string[]).includes(etiqueta)) ?? null;
}

const MILES = new Intl.NumberFormat("es-CO");

/** Rótulo de una etiqueta cruda: mensual (de a 30 días) o anual, según la lectura. */
export function rotuloEtiqueta(
  etiqueta: string,
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
): string {
  if (etiqueta === "sin_edad") return "Financiada";
  const n = Number(etiqueta);
  if (!Number.isFinite(n)) return etiqueta;
  if (lectura === "superior") {
    if (n === 0) return "0 días";
    if (n === 1801) return "Más de 1.800 días";
    const ini =
      MENSUALES.includes(etiqueta) || n === 360 ? n - 29 : n === 720 ? 361 : n - 359;
    return `${MILES.format(ini)} a ${MILES.format(n)} días`;
  }
  if (n === 1801) return "1.801 días o más";
  if (n === 1800) return "1.800 días";
  const fin = MENSUALES.includes(etiqueta) ? n + 29 : n + 359;
  return `${MILES.format(n)} a ${MILES.format(fin)} días`;
}

/** Nombres de uso (códigos de cartera_edades; cruce por contrato con consumo_metodo, 202609). */
export const NOMBRE_USO: Record<string, string> = {
  "1": "Residencial",
  "2": "Industrial",
  "3": "Comercial",
  "5": "Oficial",
  "9": "Especial",
  otros: "Otros / sin clasificar",
};

export function nombreUso(codigo: string): string {
  return NOMBRE_USO[codigo] ?? "Otros / sin clasificar";
}

export function nombreEstrato(codigo: string): string {
  return /^[1-6]$/.test(codigo) ? `Estrato ${codigo}` : "Otros / sin clasificar";
}
