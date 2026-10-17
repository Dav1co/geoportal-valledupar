import { useCallback, useState, type ReactNode } from "react";
import { TODOS } from "./PanelFiltros";
import "./plegable.css";

// Plegable controlado por estado: encabezado en forma de barra (como una carta) y, debajo, el contenido con sus propias cartas. Al estar controlado, un
// enlace puede abrirlo (usePlegables().abrirYIr). `marca` va en el encabezado, visible aunque esté cerrado (p. ej. «Filtro activo»).
// `diferido`: si es true, el contenido no se monta hasta abrirlo (lo usará la Fase 2; por defecto se monta siempre).
export function Plegable({ id, titulo, abierto, onCambio, marca, diferido = false, children }: {
  id: string; titulo: ReactNode; abierto: boolean; onCambio: (abierto: boolean) => void; marca?: ReactNode; diferido?: boolean; children: ReactNode;
}) {
  return (
    <div id={id} className="dash-fila dash-plegable">
      <details open={abierto} onToggle={(e) => { const o = (e.currentTarget as HTMLDetailsElement).open; if (o !== abierto) onCambio(o); }}>
        <summary><b>{titulo}</b>{marca}</summary>
        {!diferido || abierto ? <div className="dash-plegable-cuerpo">{children}</div> : null}
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
export function irCuandoExista(idDestino: string, topeMs = 5000) {
  const ir = (el: HTMLElement) => el.scrollIntoView({ behavior: "smooth", block: "start" });
  const intentar = () => {
    const el = document.getElementById(idDestino);
    if (el) { requestAnimationFrame(() => ir(el)); return true; }
    return false;
  };
  if (intentar()) return;
  const obs = new MutationObserver(() => { if (intentar()) { obs.disconnect(); window.clearTimeout(t); } });
  const t = window.setTimeout(() => obs.disconnect(), topeMs);
  obs.observe(document.body, { childList: true, subtree: true });
}

// Estado abierto/cerrado de varios plegables, solo en memoria.
export function usePlegables(inicial: Record<string, boolean>) {
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>(inicial);
  const cambiar = useCallback((id: string, abierto: boolean) => setAbiertos((a) => (a[id] === abierto ? a : { ...a, [id]: abierto })), []);
  // Abre los plegables indicados (el que contiene el destino primero) y desplaza al destino cuando ya esté montado.
  const abrirYIr = useCallback((ids: string[], destino?: string) => {
    setAbiertos((a) => ids.reduce((acc, id) => (acc[id] ? acc : { ...acc, [id]: true }), a));
    if (destino) irCuandoExista(destino);
  }, []);
  return { abiertos, cambiar, abrirYIr };
}
