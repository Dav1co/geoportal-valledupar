// Áreas del geoportal (Comercial y Técnica) y pantalla inicial de cada usuario. Lógica PURA, sin React.
// Ocultar un área en la interfaz es solo experiencia de usuario: NO sustituye ningún control del servidor (las Edge Functions y la base siguen decidiendo qué se entrega).
import type { PerfilResp } from "../lib/api";

export type Area = "comercial" | "tecnica" | "campo" | "aseo";
export type Pantalla = "entrada" | Area | "sin_modulos";
export type AreasDisponibles = { comercial: boolean; tecnica: boolean; campo: boolean; aseo: boolean };

// El perfil trae los permisos de cada módulo y las áreas ya calculadas en el servidor (torre_a y torre_b). OJO: desde el Paso A del módulo de campo, `torre_a` también es verdadera para quien
// solo tiene permisos de campo (los formatos de campo viven en la Torre A), así que NO basta para saber si hay modos comerciales: se exigen los modos Y (si viene) torre_a.
type PermisosPerfil = Partial<NonNullable<PerfilResp["permisos"]>> & {
  registro_tecnico?: boolean; dashboard_tecnico?: boolean; torre_a?: boolean; torre_b?: boolean; torre_c?: boolean; aseo?: boolean; dashboard_aseo?: boolean;
};

/** «Acceso solo con módulo asignado» (decisión de David): se entra a Comercial solo con algún modo comercial, a Técnica solo con algún permiso técnico, a Formatos de campo solo con algún
 *  permiso de campo o de acta y a la Interventoría de Aseo solo con algún permiso de aseo. El administrador tiene las cuatro. Sin ninguna: «Sin módulos asignados». Si el servidor declara `torre_b`, se respeta para Técnica. */
export function areasDisponibles(perfil: PerfilResp | null): AreasDisponibles {
  if (!perfil) return { comercial: false, tecnica: false, campo: false, aseo: false };
  if (perfil.es_admin) return { comercial: true, tecnica: true, campo: true, aseo: true };
  const p = (perfil.permisos ?? {}) as PermisosPerfil;
  const tecnico = typeof p.torre_b === "boolean" ? p.torre_b : p.registro_tecnico === true || p.dashboard_tecnico === true;
  // Comercial = algún modo comercial real Y, si el servidor declara torre_a, que también sea verdadera. Dos casos lo exigen: «solo campo» tiene torre_a verdadera pero ningún modo
  // (queda fuera por los modos), y el perfil por omisión de un correo que no está en la lista blanca o está inactivo trae explorar = true pero torre_a = false (queda fuera por torre_a).
  const hayModoComercial = p.explorar === true || p.focalizacion === true || p.comercial === true || p.rutas === true || p.dashboard === true;
  const comercial = hayModoComercial && (typeof p.torre_a !== "boolean" || p.torre_a === true);
  // Campo se abre también con un permiso de acta (el acta vive en la Torre A): `acta` (captura; el supervisor de actas también la tiene) o `dashboard_acta` (reconocido; su pantalla aún no existe).
  const campo = p.campo === true || p.dashboard_campo === true || p.acta === true || p.dashboard_acta === true;
  // Aseo (Torre C): `aseo` (captura; el supervisor de aseo también la tiene) o `dashboard_aseo`; si el servidor declara `torre_c`, se respeta.
  const aseo = typeof p.torre_c === "boolean" ? p.torre_c : p.aseo === true || p.dashboard_aseo === true;
  return { comercial, tecnica: tecnico, campo, aseo };
}

/** Tarjetas de la ventana de entrada. «Formatos de campo» solo es una tarjeta aparte cuando NO hay Comercial: con Comercial se llega desde su cabecera (botón «Formatos de campo»),
 *  porque los formatos viven en la Torre A. */
export function tarjetasEntrada(a: AreasDisponibles): Area[] {
  const t: Area[] = [];
  if (a.comercial) t.push("comercial");
  if (a.tecnica) t.push("tecnica");
  if (a.campo && !a.comercial) t.push("campo");
  if (a.aseo) t.push("aseo");
  return t;
}

export const esDual = (a: AreasDisponibles) => tarjetasEntrada(a).length >= 2;

/** Varias tarjetas: ventana de entrada. Una sola: entra directo. Ninguna: «sin módulos asignados». */
export function pantallaInicial(a: AreasDisponibles): Pantalla {
  const t = tarjetasEntrada(a);
  if (t.length >= 2) return "entrada";
  if (t.length === 1) return t[0];
  return "sin_modulos";
}

/** ¿Sigue siendo válida la pantalla actual si cambian las áreas (p. ej. al revalidar el perfil)? */
export function pantallaValida(p: Pantalla, a: AreasDisponibles): boolean {
  const t = tarjetasEntrada(a);
  if (p === "entrada") return t.length >= 2;
  if (p === "sin_modulos") return t.length === 0;
  return t.includes(p);
}
