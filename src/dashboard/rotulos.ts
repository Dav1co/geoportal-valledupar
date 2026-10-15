// Rótulos de las pestañas "consolidada" y "desagregada" del tablero. UNA sola definición:
// la barra de pestañas, el título de cada página y los textos que remiten a ellas leen de
// aquí. Solo es texto mostrado: las llaves de pestaña (p. ej. "facturacion-agrupado"), las
// rutas, los componentes y las claves guardadas NO cambian, para que los enlaces y los
// filtros guardados sigan funcionando.
export const ROTULO = {
  facturacionConsolidada: "Facturación consolidada",
  facturacionDesagregada: "Facturación desagregada",
  recaudoConsolidado: "Recaudo consolidado",
  recaudoDesagregado: "Recaudo desagregado",
  carteraConsolidada: "Cartera consolidada",
  carteraDesagregada: "Cartera desagregada",
} as const;
