import { useEffect, useState } from "react";
import { biCache } from "./cacheBi";

// Carga de UNA rama del tablero con su propio estado (datos, error, reintento),
// para que un fallo no afecte al resto de la pantalla. Compartido por la sección
// "Lectura" de Facturación detallado y los indicadores de lectura de Pérdidas.
export type Estado<T> = { datos: T[] | null; error: string | null; recargar: () => void };

export function useRama<T>(
  vista: string,
  periodo: string,
  convertir: (r: Record<string, unknown>) => T,
): Estado<T> {
  const [datos, setDatos] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    let vivo = true;
    setDatos(null);
    setError(null);
    biCache(vista, { periodo })
      .then((r) => { if (vivo) setDatos((r.datos ?? []).map(convertir)); })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, periodo, intento]);
  return { datos, error, recargar: () => setIntento((i) => i + 1) };
}
