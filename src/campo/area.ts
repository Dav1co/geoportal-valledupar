// Área desde la que se abren las pantallas de campo (Técnica fase 1, Corte 8: reportes compartidos con Comercial).
// «Reportar anomalía» y «Revisiones generales» son las MISMAS pantallas, la misma Edge (geoportal-campo) y las mismas tablas para Comercial y para Técnica.
// Cuando se abren desde Técnica, las peticiones de formulario, preparar_subida y crear llevan ?area=tecnica: la base autoriza por el formulario de Técnica
// y el reporte guarda su área. Comercial nunca fija nada aquí (nulo = Comercial, todo igual que siempre).
export type AreaCampoActiva = "tecnica" | null;
let activa: AreaCampoActiva = null;
export const fijarAreaCampo = (a: AreaCampoActiva): void => { activa = a; };
export const areaCampo = (): AreaCampoActiva => activa;
