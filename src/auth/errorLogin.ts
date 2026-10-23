// Clasifica el fallo de iniciar sesión para decir la verdad al usuario: sin conexión no es lo mismo que clave equivocada.
// Lógica PURA (sin React). Solo se habla de credenciales cuando Supabase Auth respondió 400/401 por credenciales.
import { isAuthApiError, isAuthRetryableFetchError } from "@supabase/supabase-js";

export type MotivoLogin = "red" | "servidor" | "credenciales" | "otro";

export const MENSAJES_LOGIN: Record<MotivoLogin, string> = {
  red: "No hay conexión con el servidor. Revisa tu internet e inténtalo de nuevo.",
  servidor: "El servidor no está disponible en este momento. Inténtalo de nuevo en unos minutos.",
  credenciales: "Correo o contraseña incorrectos.",
  otro: "No se pudo iniciar sesión. Inténtalo de nuevo.",
};

/** Tiempo máximo de espera de la respuesta de Auth; pasado ese tiempo se trata como falla de red. */
export const ESPERA_LOGIN_MS = 20_000;

export class EsperaAgotada extends Error {
  constructor() { super("Tiempo de espera agotado"); this.name = "EsperaAgotada"; }
}

export function clasificarErrorLogin(e: unknown): MotivoLogin {
  if (isAuthRetryableFetchError(e)) return !e.status || e.status === 0 ? "red" : "servidor";   // 0 = el fetch falló (sin red, DNS, conexión rechazada); 502/503/504 = servidor
  if (isAuthApiError(e)) {
    if ((e.status === 400 || e.status === 401) && (!e.code || e.code === "invalid_credentials")) return "credenciales";
    if (e.status >= 500 || e.status === 429) return "servidor";
    return "otro";
  }
  // Cualquier otra excepción (TypeError de fetch, tiempo agotado, etc.) es de red.
  return "red";
}
