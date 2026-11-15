// Pasada 14/11 · hora de inicio de los formularios de campo (contrato_inicio.md). Lógica PURA (se prueba en Node).
// El inicio es la hora del CELULAR al abrir el formulario; se envía como `inicio_dispositivo` y el servidor lo rechaza si está adelantado (> 2 min) o es muy viejo (> max_horas_inicio).
// Si el servidor lo rechaza por la hora, el siguiente envío lo recalcula UNA vez: hora actual del celular (ya corregida) menos el tiempo transcurrido desde que se abrió (reloj monotónico,
// que no cambia si la persona corrige la hora). Los reintentos por red o servidor mandan exactamente el mismo valor.

export type RelojInicio = { iso: string; t0: number };
const monotono = () => (typeof performance !== "undefined" ? performance.now() : Date.now());

/** Se llama UNA vez, al abrir el formulario. */
export const abrirReloj = (ahora: number = Date.now(), t0: number = monotono()): RelojInicio => ({ iso: new Date(ahora).toISOString(), t0 });

/** Tras un rechazo por la hora del celular: inicio = hora del celular ahora − tiempo transcurrido desde que se abrió. */
export const recalcularReloj = (r: RelojInicio, ahora: number = Date.now(), t: number = monotono()): RelojInicio =>
  ({ iso: new Date(ahora - Math.max(0, t - r.t0)).toISOString(), t0: r.t0 });

/** ¿El servidor rechazó el registro por la hora de inicio? (textos exactos de la base) */
export const esRechazoPorHora = (mensaje: string | null | undefined): boolean =>
  !!mensaje && (/hora de su celular está adelantada/i.test(mensaje) || /formulario se abrió hace más de/i.test(mensaje));
