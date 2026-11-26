import { useEffect, useRef, useState } from "react";
import { apiCampo, ErrorCampo } from "./apiCampo";
import { PanelDireccion, type EstadoDireccion } from "./registroFlexible";

// Dirección del contrato en los formatos y en Reportar anomalía (25-nov, David): el operario no podía saber si la dirección en terreno es distinta porque al
// escribir el contrato no veía la del contrato (solo en «Consultar», que exige el permiso de Análisis). Al dejar de escribir un contrato válido, se piden a la
// Edge (ruta direccion_contrato) sus DOS direcciones, la de la base comercial y la del catastro, cada una con su barrio; nada más (ni nombre, ni teléfono).
// La consulta queda en la bitácora del servidor y tiene un tope por hora. Se recuerda en memoria mientras la pantalla está abierta (nada en el dispositivo).
// Un contrato que no existe no muestra nada.

export type Direccion = { direccion: string | null; barrio: string | null; corte?: string | null };
export type RespuestaDireccion =
  | { encontrado: true; comodin?: false; contrato: string; comercial: Direccion | null; catastro: Direccion | null; predios_total: number; distintas: boolean }
  | { encontrado: true; comodin: true; contrato: string }
  | { encontrado: false; contrato: string };

const ESPERA_MS = 600;
const memoria = new Map<string, RespuestaDireccion>();

/** Pide la dirección del contrato cuando se deja de escribir (600 ms). Estado: null mientras no hay nada que mostrar. */
export function useDireccionContrato(contrato: string): { r: RespuestaDireccion | null; buscando: boolean; aviso: string | null } {
  const [r, setR] = useState<RespuestaDireccion | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);
  const version = useRef(0);
  useEffect(() => {
    const c = contrato.trim();
    const v = ++version.current;
    setAviso(null);
    if (!/^\d{1,12}$/.test(c)) { setR(null); setBuscando(false); return; }
    const guardada = memoria.get(c);
    if (guardada) { setR(guardada); setBuscando(false); return; }
    setR(null); setBuscando(true);
    const t = window.setTimeout(async () => {
      try {
        const x = await apiCampo.direccionContrato(c);
        memoria.set(c, x);
        if (v === version.current) setR(x);
      } catch (e) {
        if (v !== version.current) return;
        // límite por hora: se dice; sin permiso, ruta aún no publicada o red: no se muestra nada (el formulario sigue igual)
        if (e instanceof ErrorCampo && e.tipo === "limite") setAviso(e.message);
        setR(null);
      } finally { if (v === version.current) setBuscando(false); }
    }, ESPERA_MS);
    return () => window.clearTimeout(t);
  }, [contrato]);
  return { r, buscando, aviso };
}

const linea = (d: Direccion | null | undefined) => (d?.direccion ? [d.direccion, d.barrio].filter(Boolean).join(" · ") : null);

/** Debajo del número de contrato: «Dirección del contrato: … · barrio» y, si es distinta, «En el catastro: …». Nada si el contrato no existe. */
export function DireccionDelContrato({ estado }: { estado: ReturnType<typeof useDireccionContrato> }) {
  const { r, buscando, aviso } = estado;
  if (aviso) return <p className="campo-sub dc-aviso" role="status">{aviso}</p>;
  if (buscando) return <p className="campo-sub dc-buscando" role="status">Buscando la dirección del contrato…</p>;
  if (!r || !r.encontrado || r.comodin) return null;
  const com = linea(r.comercial), cat = linea(r.catastro);
  if (!com && !cat) return null;
  return (
    <div className="dc-direccion" data-dc-direccion role="status">
      {com ? <p><span className="dc-rotulo">Dirección del contrato:</span> {com}</p> : <p><span className="dc-rotulo">Dirección del contrato:</span> {cat}</p>}
      {com && cat && r.distintas ? <p data-dc-catastro><span className="dc-rotulo">En el catastro:</span> {cat}</p> : null}
      {r.predios_total > 1 ? <p className="campo-sub">{r.predios_total} predios en el censo para este contrato.</p> : null}
    </div>
  );
}

/** ¿El contrato escrito existe y tiene alguna dirección? Entonces la casilla es «La dirección en terreno es distinta». */
export const contratoConDireccion = (r: RespuestaDireccion | null): boolean =>
  !!r && r.encontrado && !r.comodin && !!(r.comercial?.direccion || r.catastro?.direccion);

/** La casilla «La dirección en terreno es distinta» (abre Dirección, Barrio y Referencia: el mismo panel del registro flexible). */
export function PanelDireccionTerreno({ estado, onCambio, deshabilitado }: { estado: EstadoDireccion; onCambio: (e: EstadoDireccion) => void; deshabilitado?: boolean }) {
  return <PanelDireccion estado={estado} onCambio={onCambio} deshabilitado={deshabilitado}
    rotulo="La dirección en terreno es distinta" ayuda="Marque si la dirección que encontró no es la del contrato y escriba la que ve en el sitio. Si la desmarca, no se envía." />;
}
