import { useEffect, useState, type Dispatch, type SetStateAction } from "react";
import { TODOS } from "./PanelFiltros";
import { numeroCiclo } from "./formato";
import { ESTRATOS_FILTRO, USOS_FILTRO } from "./edadCarteraCalculo";

// Memoria del estado de la pantalla de Pérdidas durante la sesión de la pestaña (sessionStorage, nunca localStorage). Solo se guardan
// banderas abierto/cerrado y valores de filtros, nada que identifique personas. Toda lectura y escritura va en try/catch: si el
// almacenamiento está bloqueado o falla, la pantalla funciona igual que sin memoria. Las claves incluyen el período, así un filtro no
// se arrastra de un período a otro.
const PREFIJO = "geoportal.perdidas.v1.";

function almacen(): Storage | null {
  try { return window.sessionStorage; } catch { return null; }
}
export function leerSesion(clave: string): unknown {
  try {
    const t = almacen()?.getItem(PREFIJO + clave);
    return t == null ? null : JSON.parse(t);
  } catch { return null; }
}
export function guardarSesion(clave: string, valor: unknown) {
  try { almacen()?.setItem(PREFIJO + clave, JSON.stringify(valor)); } catch { /* sin memoria */ }
}

// Estado que se restaura de la sesión (si es válido) y se guarda en cada cambio. `normalizar` devuelve null si el valor guardado no sirve.
export function useEstadoSesion<T>(clave: string, defecto: T, normalizar: (x: unknown) => T | null): [T, Dispatch<SetStateAction<T>>] {
  const [valor, setValor] = useState<T>(() => {
    const x = leerSesion(clave);
    return (x == null ? null : normalizar(x)) ?? defecto;
  });
  useEffect(() => { guardarSesion(clave, valor); }, [clave, valor]);
  return [valor, setValor];
}

const esObjeto = (x: unknown): x is Record<string, unknown> => typeof x === "object" && x !== null && !Array.isArray(x);

// Banderas abierto/cerrado: solo los ids conocidos con valor booleano; lo demás se descarta.
export const normalizarBanderas = (ids: string[], defecto: Record<string, boolean>) => (x: unknown): Record<string, boolean> | null => {
  if (!esObjeto(x)) return null;
  const o: Record<string, boolean> = {};
  for (const id of ids) if (typeof x[id] === "boolean") o[id] = x[id] as boolean;
  return Object.keys(o).length === 0 && Object.keys(defecto).length > 0 ? null : o;
};

const cadena = (x: unknown, max = 60) => (typeof x === "string" && x.length > 0 && x.length <= max ? x : TODOS);
const estratoValido = (x: unknown) => (typeof x === "string" && /^ESTRATO [1-6]$/.test(x) ? x : TODOS);

// Filtros del panel de Lectura (ciclo, uso, estrato). El estrato con un uso no residencial se descarta (regla del paso 2).
export function normalizarFiltrosLectura(x: unknown): Record<string, string> | null {
  if (!esObjeto(x)) return null;
  const ciclo = typeof x.ciclo === "string" && numeroCiclo(x.ciclo) != null ? cadena(x.ciclo, 20) : TODOS;
  const uso = cadena(x.uso, 40);
  const subcategoria = uso === TODOS || uso === "Residencial" ? estratoValido(x.subcategoria) : TODOS;
  return { ciclo, uso, subcategoria };
}
// Filtro del panel de Submedición (solo estrato).
export function normalizarFiltrosSubmedicion(x: unknown): Record<string, string> | null {
  return esObjeto(x) ? { subcategoria: estratoValido(x.subcategoria) } : null;
}

// Filtros compartidos de Cartera desagregada (uso y estrato). Con un uso distinto de «todos» o Residencial, el estrato se descarta (misma regla
// que en Pérdidas). Los nombres se validan contra la lista cerrada de la pantalla.
export function normalizarFiltrosCartera(x: unknown): Record<string, string> | null {
  if (!esObjeto(x)) return null;
  const uso = typeof x.uso === "string" && USOS_FILTRO.some((u) => u.nombre === x.uso) ? x.uso : TODOS;
  const sub = (uso === TODOS || uso === "Residencial") && typeof x.subcategoria === "string" && ESTRATOS_FILTRO.some((e) => e.nombre === x.subcategoria)
    ? x.subcategoria : TODOS;
  return { uso, subcategoria: sub };
}
// Filtros propios de la zona «Por ciclo y barrio» (comuna, barrio, ciclo): textos cortos; el barrio y la comuna se validan contra los datos al usarse.
export function normalizarFiltrosUbicacion(x: unknown): Record<string, string> | null {
  if (!esObjeto(x)) return null;
  return { comuna: cadena(x.comuna, 40), barrio: cadena(x.barrio, 80), ciclo: cadena(x.ciclo, 20) };
}
