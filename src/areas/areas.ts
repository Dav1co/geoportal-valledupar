// Áreas del geoportal (Comercial y Técnica) y pantalla inicial de cada usuario. Lógica PURA, sin React.
// Ocultar un área en la interfaz es solo experiencia de usuario: NO sustituye ningún control del servidor (las Edge Functions y la base siguen decidiendo qué se entrega).
import type { PerfilResp } from "../lib/api";

export type Area = "comercial" | "tecnica" | "campo";
export type Pantalla = "entrada" | Area | "sin_modulos";
export type AreasDisponibles = { comercial: boolean; tecnica: boolean; campo: boolean };

// El perfil trae los permisos de cada módulo y las áreas ya calculadas en el servidor (torre_a y torre_b). OJO: desde el Paso A del módulo de campo, `torre_a` también es verdadera para quien
// solo tiene permisos de campo (los formatos de campo viven en la Torre A), así que ya NO sirve para saber si hay modos comerciales: eso se calcula de los modos.
type PermisosPerfil = Partial<NonNullable<PerfilResp["permisos"]>> & {
  registro_tecnico?: boolean; dashboard_tecnico?: boolean; torre_a?: boolean; torre_b?: boolean;
};

/** «Acceso solo con módulo asignado» (decisión de David): se entra a Comercial solo con algún modo comercial, a Técnica solo con algún permiso técnico y a Formatos de campo solo con algún
 *  permiso de campo. El administrador tiene las tres. Sin ninguna: «Sin módulos asignados». Si el servidor declara `torre_b`, se respeta para Técnica. */
export function areasDisponibles(perfil: PerfilResp | null): AreasDisponibles {
  if (!perfil) return { comercial: false, tecnica: false, campo: false };
  if (perfil.es_admin) return { comercial: true, tecnica: true, campo: true };
  const p = (perfil.permisos ?? {}) as PermisosPerfil;
  const tecnico = typeof p.torre_b === "boolean" ? p.torre_b : p.registro_tecnico === true || p.dashboard_tecnico === true;
  const comercial = p.explorar === true || p.focalizacion === true || p.comercial === true || p.rutas === true || p.dashboard === true;
  const campo = p.campo === true || p.dashboard_campo === true;
  return { comercial, tecnica: tecnico, campo };
}

/** Tarjetas de la ventana de entrada. «Formatos de campo» solo es una tarjeta aparte cuando NO hay Comercial: con Comercial se llega desde su cabecera (botón «Formatos de campo»),
 *  porque los formatos viven en la Torre A. */
export function tarjetasEntrada(a: AreasDisponibles): Area[] {
  const t: Area[] = [];
  if (a.comercial) t.push("comercial");
  if (a.tecnica) t.push("tecnica");
  if (a.campo && !a.comercial) t.push("campo");
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
