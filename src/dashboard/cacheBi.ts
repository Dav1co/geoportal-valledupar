import { api } from "../lib/api";

// Caché de las consultas del tablero, a nivel de MÓDULO: sobrevive al
// desmontaje de las pantallas y del modo Dashboard, así que dura toda
// la sesión de la aplicación.
//
// Por qué existe: cada llamada a geoportal-bi paga el guardián completo
// (token, dominio, lista blanca, horario, permiso) y deja un registro
// de auditoría. Volver a una pestaña ya visitada no debe costar nada.
//
// Clave = vista + filtros, así que un período distinto trae datos
// nuevos por construcción. Las vistas históricas se piden sin filtro
// (traen todos los períodos y el navegador corta), por eso se consultan
// una sola vez por sesión.
//
// Se cachea la PROMESA, no el resultado: dos pantallas que pidan lo
// mismo a la vez comparten una sola llamada. Si falla, la entrada se
// borra para que el botón "Reintentar" vuelva a intentar de verdad.

type Respuesta = { datos: Record<string, unknown>[] };
type Entrada = { promesa: Promise<Respuesta>; nacida: number };

const cache = new Map<string, Entrada>();

// Vencimiento del caché. Los datos solo cambian cuando corre el cargue
// mensual, así que media hora es de sobra: quien deje el tablero abierto
// durante un cargue verá las cifras nuevas sin hacer nada, y el costo en
// llamadas extra es despreciable frente a una sesión de trabajo.
const VENCE_MS = 30 * 60 * 1000;

export function biCache(vista: string, filtros?: Record<string, string>): Promise<Respuesta> {
  const clave = `${vista}|${JSON.stringify(filtros ?? {})}`;
  const guardada = cache.get(clave);
  if (guardada && Date.now() - guardada.nacida < VENCE_MS) return guardada.promesa;

  const promesa = api.bi(vista, filtros).catch((e: unknown) => {
    cache.delete(clave);
    throw e;
  });
  cache.set(clave, { promesa, nacida: Date.now() });
  return promesa;
}

// Vacía el caché para forzar una recarga inmediata: lo usa el botón
// "Actualizar" del encabezado, para quien sabe que acaba de entrar un
// mes nuevo y no quiere esperar al vencimiento.
export function limpiarCacheBi() {
  cache.clear();
}
