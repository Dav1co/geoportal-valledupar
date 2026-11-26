// Contador de pendientes de «Avisos y actividades derivadas». La ruta `derivadas` no devuelve el total (lo agregará el Code A en la Edge): se pide una página de TOPE filas pendientes y,
// si llena el tope (o trae «siguiente»), se muestra «100+». Lógica pura, sin React: se prueba en scripts/prueba_formatos_derivadas.mjs.
export const TOPE_PENDIENTES = 100;
export type Pendientes = { n: number; tope: boolean };

export const pendientesDe = (filas: number, hayMas: boolean): Pendientes => ({ n: filas, tope: hayMas || filas >= TOPE_PENDIENTES });
/** «100+» o «7». Vacío si no hay nada que decir (nulo, error de lectura o cero). */
export const textoPendientes = (p: Pendientes | null | undefined): string => (!p || p.n <= 0 ? "" : p.tope ? `${TOPE_PENDIENTES}+` : String(p.n));
/** Para el rótulo de la pestaña: « · 7 pendientes». */
export const etiquetaPendientes = (p: Pendientes | null | undefined): string => { const t = textoPendientes(p); return t ? ` · ${t} ${t === "1" ? "pendiente" : "pendientes"}` : ""; };
