// Lógica PURA de la «Constancia por correo» (sin React ni red; se prueba sola). La base y la Edge vuelven a validar todo: esto solo avisa antes de enviar.
// El geoportal NO envía nada: deja el contacto y la autorización, y la base los encola para el Dell.

export type ConfigConstancia = { habilitado: false } | { habilitado: true; texto_version: number; texto: string; partes: { codigo: string; nombre: string }[] };
export type ValorConstancia = { autoriza: boolean; correo: string; celular: string; parte: string };
/** Lo que viaja en el cuerpo (nombres con «_titular» para no chocar con las claves prohibidas del servidor). */
export type BloqueConstancia = { correo_titular: string; celular_titular?: string; parte: string; autoriza: true; texto_version: number };

export const VALOR_INICIAL: ValorConstancia = { autoriza: false, correo: "", celular: "", parte: "" };
export const CORREO_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export const limpiarCelular = (s: string): string => s.replace(/[ .-]/g, "");
export const correoValido = (s: string): boolean => { const c = s.trim(); return c.length <= 254 && CORREO_RE.test(c); };
/** Celular colombiano: 10 dígitos que empiezan por 3. Vacío es válido (es opcional). */
export const celularValido = (s: string): boolean => { const c = limpiarCelular(s); return c === "" || /^3[0-9]{9}$/.test(c); };
export const activa = (c: ConfigConstancia | null): c is Extract<ConfigConstancia, { habilitado: true }> => !!c && c.habilitado === true;

/** Lo que falta para poder enviar. Sin la casilla marcada no se exige nada (la constancia es opcional y no se envía). */
export function faltasConstancia(v: ValorConstancia, c: ConfigConstancia | null): string[] {
  if (!activa(c) || !v.autoriza) return [];
  const f: string[] = [];
  if (!correoValido(v.correo)) f.push("Constancia: escriba un correo válido (o quite la autorización)");
  if (!celularValido(v.celular)) f.push("Constancia: el celular debe tener 10 dígitos y empezar por 3");
  if (v.parte === "") f.push("Constancia: indique a quién va la constancia");
  return f;
}

/** Bloque para el cuerpo, o undefined si no hay constancia (documento apagado, casilla sin marcar o datos incompletos). */
export function construirConstancia(v: ValorConstancia, c: ConfigConstancia | null): BloqueConstancia | undefined {
  if (!activa(c) || !v.autoriza || faltasConstancia(v, c).length > 0) return undefined;
  const cel = limpiarCelular(v.celular);
  return { correo_titular: v.correo.trim().toLowerCase(), ...(cel !== "" ? { celular_titular: cel } : {}), parte: v.parte, autoriza: true, texto_version: c.texto_version };
}
