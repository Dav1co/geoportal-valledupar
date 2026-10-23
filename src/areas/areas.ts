// Áreas del geoportal (Comercial y Técnica) y pantalla inicial de cada usuario. Lógica PURA, sin React.
// Ocultar un área en la interfaz es solo experiencia de usuario: NO sustituye ningún control del servidor (las Edge Functions y la base siguen decidiendo qué se entrega).
import type { PerfilResp } from "../lib/api";

export type Area = "comercial" | "tecnica";
export type Pantalla = "entrada" | Area | "sin_modulos";
export type AreasDisponibles = { comercial: boolean; tecnica: boolean };

// El perfil de hoy no trae permisos técnicos; la fase 2 los agrega (y las áreas ya calculadas en el servidor: torre_a y torre_b).
type PermisosPerfil = Partial<NonNullable<PerfilResp["permisos"]>> & {
  registro_tecnico?: boolean; dashboard_tecnico?: boolean; torre_a?: boolean; torre_b?: boolean;
};

/** «Acceso solo con módulo asignado» (decisión de David; su par es el «Acceso heredado», el de antes): se entra a Comercial solo con algún modo comercial, y a Técnica solo con algún
 *  permiso técnico. El administrador tiene ambas áreas. Sin ninguna: «Sin módulos asignados». Si el servidor declara las áreas (torre_a y torre_b), se respetan. */
export function areasDisponibles(perfil: PerfilResp | null): AreasDisponibles {
  if (!perfil) return { comercial: false, tecnica: false };
  if (perfil.es_admin) return { comercial: true, tecnica: true };
  const p = (perfil.permisos ?? {}) as PermisosPerfil;
  if (typeof p.torre_a === "boolean" && typeof p.torre_b === "boolean") return { comercial: p.torre_a, tecnica: p.torre_b };
  const tecnico = p.registro_tecnico === true || p.dashboard_tecnico === true;
  const comercial = p.explorar === true || p.focalizacion === true || p.comercial === true || p.rutas === true || p.dashboard === true;
  return { comercial, tecnica: tecnico };
}

export const esDual = (a: AreasDisponibles) => a.comercial && a.tecnica;

/** Dos áreas: ventana de entrada. Una sola: entra directo. Ninguna: «sin módulos asignados». */
export function pantallaInicial(a: AreasDisponibles): Pantalla {
  if (a.comercial && a.tecnica) return "entrada";
  if (a.comercial) return "comercial";
  if (a.tecnica) return "tecnica";
  return "sin_modulos";
}

/** ¿Sigue siendo válida la pantalla actual si cambian las áreas (p. ej. al revalidar el perfil)? */
export function pantallaValida(p: Pantalla, a: AreasDisponibles): boolean {
  if (p === "entrada") return esDual(a);
  if (p === "comercial") return a.comercial;
  if (p === "tecnica") return a.tecnica;
  return !a.comercial && !a.tecnica;
}
