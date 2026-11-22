// Personal de campo · qué puede cambiar quien consulta, en general y persona por persona (funciones puras, sin React: las prueban scripts/prueba_personal_puede.mjs y las pruebas de Chrome).
// 22-nov (David, 11:11 y 11:25; SQL del Code A, rama comercial-cargo-supervisor 5972d2d): el supervisor de campo cambia SOLO a los operarios. Cada persona trae del servidor
//   · puede_area_cargo → el área y el cargo;
//   · puede_asignar    → los formularios, la cuadrilla (poner o sacar) y las actividades propias.
// Los dos son falsos para un supervisor (dashboard_campo o dashboard_acta), para un administrador y para la propia ficha; el administrador los tiene verdaderos para todos los demás.
// Un servidor anterior no los manda: entonces vale solo lo general (`puede`) y la regla de siempre «nadie cambia su propia ficha».
import type { PersonaCampo, PersonalResp, PuedePersonal, TipoCambioPersonal } from "./apiRevision";

export const NADA: PuedePersonal = { cargo: false, area: false, cuadrilla: false, cuadrillas: false, actividades: false, formularios: false, catalogos: false };

/** Lo que puede cambiar quien consulta, en general. Sin `puede` (servidor anterior al 21-nov), el administrador fija el cargo y los formularios, como antes. */
export function puedeDe(d: PersonalResp | null, soloLectura = false): PuedePersonal {
  if (!d || soloLectura) return NADA;
  return d.puede ?? { ...NADA, cargo: d.puede_editar, formularios: d.puede_editar };
}

/** ¿Cambia algo de una ficha? (las cuadrillas y los catálogos no son de una persona: no cuentan). */
export const editaAlgo = (q: PuedePersonal) => q.cargo || q.area || q.cuadrilla || q.actividades || q.formularios;

/** Lo que quien consulta puede cambiarle a ESTA persona: lo general, recortado por lo que el servidor dice de ella. */
export function puedeSobre(puede: PuedePersonal, p: PersonaCampo): PuedePersonal {
  if (p.propia) return { ...NADA, cuadrillas: puede.cuadrillas, catalogos: puede.catalogos };
  const ac = p.puede_area_cargo !== false, as = p.puede_asignar !== false;     // ausente (servidor anterior) = sin recorte
  return { ...puede, cargo: puede.cargo && ac, area: puede.area && ac, cuadrilla: puede.cuadrilla && as, actividades: puede.actividades && as, formularios: puede.formularios && as };
}

/** Por qué no aparece «Editar» en una ficha. Nulo si se puede editar, o si quien consulta no edita a nadie (ya lo dice el aviso de «Solo lectura»). */
export function porQueNo(puede: PuedePersonal, p: PersonaCampo): string | null {
  if (!editaAlgo(puede) || editaAlgo(puedeSobre(puede, p))) return null;
  if (p.propia) return "Es su ficha: no la puede cambiar.";
  if (p.perfil === "supervisor") return "Es supervisor: su área, su cargo y sus asignaciones los cambia el administrador.";
  return "Esta ficha la cambia el administrador.";
}

/** ¿El servidor recorta por persona y quien consulta no es administrador? (para decirlo en «Usted puede»). */
export function soloOperarios(d: PersonalResp | null, puede: PuedePersonal): boolean {
  if (!d || d.puede_editar || !editaAlgo(puede)) return false;
  return d.personas.some((p) => p.puede_area_cargo !== undefined || p.puede_asignar !== undefined);
}

const TEXTO_SIN_PERMISO = "No tiene permiso para esta acción.";     // el texto fijo que la Edge geoportal-campo pone a todo 403 (rpc.ts: «no se reenvía el de la base»)

/** Lo que el servidor diría si rechaza el cambio de un supervisor sobre un supervisor o un administrador (los textos de geoportal_campo_personal_fijar, 5972d2d). */
export function textoSoloOperarios(tipo: TipoCambioPersonal): string {
  return tipo === "fijar_cargo" || tipo === "fijar_area"
    ? "el área y el cargo de un supervisor o de un administrador los cambia el administrador."
    : "las asignaciones de un supervisor o de un administrador las hace el administrador.";
}

/**
 * Texto para un 403 al guardar en Personal (nulo si no es ese caso: entonces va el texto de siempre).
 * Si el servidor manda un texto propio, se muestra tal cual. Hoy la Edge lo cambia por «No tiene permiso para esta acción.»: a quien no es administrador se le explica la regla.
 */
export function textoRechazo(status: number, tipoError: string, mensaje: string, tipo: TipoCambioPersonal, admin: boolean): string | null {
  if (status !== 403 || tipoError === "denegado" || tipoError === "horario") return null;
  if (mensaje && mensaje !== TEXTO_SIN_PERMISO) return mensaje;
  return admin ? "No tiene permiso para este cambio." : `No tiene permiso para este cambio: ${textoSoloOperarios(tipo)}`;
}
