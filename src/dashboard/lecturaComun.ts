import type { ObservacionDim } from "./tipos";
import type { DefFiltro } from "./PanelFiltros";
import { etiquetaCiclo, numeroCiclo } from "./formato";

// Constantes y funciones que comparten las secciones de lectura, medición y consumo
// (ContratosLectura, ContratosCicloMedicion, ContratosDesviacion, IndicadoresLectura y
// las que viven en la pantalla de Pérdidas). Una sola definición.

// Intervalo regulatorio entre lecturas, en días. El SQL (sql/28) clasifica con los mismos límites (28 y 32).
export const LIM_DIAS_MIN = 28;
export const LIM_DIAS_MAX = 32;
// Observaciones con menos de este % de los contratos filtrados se agrupan en "Otras"
// (salvo "Sin medidor" y la observación 99, que siempre se ven).
export const UMBRAL_OTRAS_PCT = 0.3;
export const CODIGO_CON_LECTURA = 99;
export const SIN_MEDIDOR = "Sin medidor";
// Primer período con fecha de instalación en consumo_metodo (antes viene vacía).
export const PRIMER_PERIODO_ANTIGUEDAD = "202605";
// Marcas visuales del tablero (convenciones, no normas): ciclos con más de este % de consumo cobrado en
// cero y ciclos con tasa de desviación sobre este %.
export const UMBRAL_CONSUMO_CERO_PCT = 15;
export const UMBRAL_TASA_DESVIACION_PCT = 15;

export const textoObservacion = (o: string) => o.replace(/^\d+\s+/, "");

// Contratos con una observación de lectura distinta de «99 USUARIO CON LECTURA» y de «Sin medidor»
// (a nivel de las filas recibidas). Lo usa la ficha «Con observación de lectura».
export function resumenConObservacion(filas: ObservacionDim[]) {
  let contratos = 0, cero = 0, conMedidor = 0;
  const m = new Map<string, { texto: string; contratos: number }>();
  for (const x of filas) {
    if (x.con_medidor) conMedidor += x.contratos;
    if (x.observacion === SIN_MEDIDOR || x.codigo_observacion === CODIGO_CON_LECTURA) continue;
    contratos += x.contratos;
    cero += x.contratos_cero;
    const it = m.get(x.observacion) ?? { texto: textoObservacion(x.observacion), contratos: 0 };
    it.contratos += x.contratos;
    m.set(x.observacion, it);
  }
  const causal = [...m.values()].sort((a, b) => b.contratos - a.contratos)[0] ?? null;
  return { contratos, cero, conMedidor, causal };
}

// Filtros de ciclo, uso y estrato con las mismas reglas en Facturación desagregada y en Pérdidas.
// Los ciclos llegan como 'CICLO 05' (facturación) o '5' (consumo): se unen y comparan por número,
// así el 24 se puede filtrar aunque una de las fuentes todavía no lo traiga.
export function filtrosCicloUsoEstrato(
  ciclos: string[],
  usoEstrato: { uso: string; subcategoria: string }[],
): DefFiltro[] {
  const unicos = (xs: string[]) => [...new Set(xs)].sort((a, b) => a.localeCompare(b, "es"));
  return [
    {
      id: "ciclo",
      etiqueta: "Ciclo de facturación",
      opciones: [...new Set(ciclos.map(numeroCiclo).filter((n): n is number => n != null))]
        .sort((a, b) => a - b)
        .map(etiquetaCiclo),
    },
    { id: "uso", etiqueta: "Uso", opciones: unicos(usoEstrato.map((x) => x.uso)) },
    {
      id: "subcategoria",
      etiqueta: "Estrato",
      // Solo con uso Residencial la subcategoría es el estrato; en el resto trae el diámetro de la acometida.
      visible: (v) => v.uso === "Residencial",
      opciones: unicos(usoEstrato.map((x) => (x.uso === "Residencial" ? x.subcategoria : ""))).filter(Boolean),
      ayuda: "Solo aplica a uso Residencial",
    },
  ];
}
