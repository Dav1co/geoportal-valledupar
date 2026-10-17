import { useCallback, useRef, type ReactNode } from "react";
import { normalizarBanderas, useEstadoSesion } from "./memoriaSesion";
import { TODOS } from "./PanelFiltros";
import "./plegable.css";

// Plegable controlado por estado: encabezado en forma de barra (como una carta) y, debajo, el contenido con sus propias cartas. Al estar controlado, un
// enlace puede abrirlo (usePlegables().abrirYIr). `marca` va en el encabezado, visible aunque esté cerrado (p. ej. «Filtro activo»).
// `diferido`: el contenido no se monta ni consulta hasta la primera apertura (por defecto se monta siempre).
export function Plegable({ id, titulo, abierto, onCambio, marca, diferido = false, children }: {
  id: string; titulo: ReactNode; abierto: boolean; onCambio: (abierto: boolean) => void; marca?: ReactNode; diferido?: boolean; children: ReactNode;
}) {
  // Con `diferido`, el contenido se monta en la primera apertura y ya no se desmonta (conserva su estado; los datos quedan en biCache).
  const visto = useRef(false);
  if (abierto) visto.current = true;
  const montar = !diferido || visto.current;
  return (
    <div id={id} className="dash-fila dash-plegable">
      <details open={abierto} onToggle={(e) => { const o = (e.currentTarget as HTMLDetailsElement).open; if (o !== abierto) onCambio(o); }}>
        <summary><b>{titulo}</b>{marca}</summary>
        {montar ? <div className="dash-plegable-cuerpo">{children}</div> : null}
      </details>
    </div>
  );
}

// «● Filtro activo: …» con los valores distintos de «todos». En un encabezado cerrado va sin botón; en una pieza abierta, con «Limpiar».
export function MarcaFiltro({ valores, onLimpiar }: { valores: Record<string, string>; onLimpiar?: () => void }) {
  const activos = Object.values(valores).filter((v) => v && v !== TODOS);
  if (!activos.length) return null;
  return (
    <span className="dash-marca-filtro">
      ● Filtro activo: {activos.join(" · ")}
      {onLimpiar ? <button type="button" onClick={onLimpiar}>Limpiar</button> : null}
    </span>
  );
}

// Desplaza hasta el elemento en cuanto exista en el DOM (sin temporizador fijo): si ya está, tras el siguiente cuadro; si no, espera
// a que React monte el contenido con un MutationObserver (con un tope por si el elemento nunca aparece).
export function irCuandoExista(idDestino: string, esperarContenido = false, topeMs = 5000) {
  const ir = (el: HTMLElement) => el.scrollIntoView({ behavior: "smooth", block: "start" });
  // Con esperarContenido, el destino es una parte plegable: se espera a que su cuerpo (lo que sigue al <summary>) ya esté montado.
  const listo = (el: HTMLElement) => !esperarContenido || (el.querySelector("details")?.children.length ?? 0) > 1;
  const intentar = () => {
    const el = document.getElementById(idDestino);
    if (el && listo(el)) { requestAnimationFrame(() => ir(el)); return true; }
    return false;
  };
  if (intentar()) return;
  const obs = new MutationObserver(() => { if (intentar()) { obs.disconnect(); window.clearTimeout(t); } });
  const t = window.setTimeout(() => obs.disconnect(), topeMs);
  obs.observe(document.body, { childList: true, subtree: true });
}

// Estado abierto/cerrado de varios plegables; se recuerda durante la sesión de la pestaña (ver memoriaSesion.ts).
export function usePlegables(inicial: Record<string, boolean>, clave: string, ids: string[]) {
  const [abiertos, setAbiertos] = useEstadoSesion<Record<string, boolean>>(clave, inicial, normalizarBanderas(ids, inicial));
  const cambiar = useCallback((id: string, abierto: boolean) => setAbiertos((a) => (a[id] === abierto ? a : { ...a, [id]: abierto })), []);
  // Abre los plegables indicados (el que contiene el destino primero) y desplaza al destino cuando ya esté montado.
  const abrirYIr = useCallback((ids: string[], destino?: string) => {
    setAbiertos((a) => ids.reduce((acc, id) => (acc[id] ? acc : { ...acc, [id]: true }), a));
    if (destino) irCuandoExista(destino);
  }, []);
  return { abiertos, cambiar, abrirYIr };
}
