import { useCallback, useEffect, useMemo, useState } from "react";
import { apiConstancia } from "./apiConstancia";
import { VALOR_INICIAL, construirConstancia, faltasConstancia, type BloqueConstancia, type ConfigConstancia, type ValorConstancia } from "./logica";

/** Estado de la sección «Constancia por correo» de un formulario. La configuración se pide una vez por documento; si falla (o el documento está apagado) la sección no aparece
 *  y el registro sigue como siempre: la constancia es opcional y nunca bloquea el registro. El valor vive solo en memoria (no se guarda nada en el navegador). */
/** Documentos de campo que envían constancia (el catálogo del acta de revisión o instalación). El acta de inspección es `acta_inspeccion`. Otros formatos: no hay sección. */
export const DOCUMENTOS_CON_CONSTANCIA = ["acta_inspeccion", "revision_previa", "revision_pqr", "instalacion_medidor", "instalacion_acometida"] as const;
export const enviaConstancia = (codigo: string): boolean => (DOCUMENTOS_CON_CONSTANCIA as readonly string[]).includes(codigo);

export function useConstancia(documento: string | null): {
  config: ConfigConstancia | null; valor: ValorConstancia; setValor: (c: Partial<ValorConstancia>) => void; faltas: string[]; bloque: BloqueConstancia | undefined; reiniciar: () => void;
} {
  const [config, setConfig] = useState<ConfigConstancia | null>(null);
  const [valor, setV] = useState<ValorConstancia>(VALOR_INICIAL);
  useEffect(() => {
    if (documento === null || !enviaConstancia(documento)) { setConfig(null); return; }
    let vivo = true;
    apiConstancia.config(documento).then((c) => { if (vivo) setConfig(c); }).catch(() => { if (vivo) setConfig(null); });
    return () => { vivo = false; };
  }, [documento]);
  const setValor = useCallback((c: Partial<ValorConstancia>) => setV((x) => ({ ...x, ...c })), []);
  const faltas = useMemo(() => faltasConstancia(valor, config), [valor, config]);
  const bloque = useMemo(() => construirConstancia(valor, config), [valor, config]);
  return { config, valor, setValor, faltas, bloque, reiniciar: () => setV(VALOR_INICIAL) };
}
