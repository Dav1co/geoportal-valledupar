// Selección múltiple con búsqueda (los filtros existentes del tablero son de selección única). El menú es una ventana FLOTANTE dentro del propio
// componente (position: absolute), sin portal: así se ve también cuando la sección está en pantalla completa (un portal a <body> quedaría fuera del
// elemento en pantalla completa) y no empuja el contenido que tiene debajo. Se cierra al pulsar fuera.
import { useEffect, useRef, useState } from "react";

/** `contratos`: número de contratos de la opción; null = menos de 5 (no se publica); sin la propiedad, no se muestra conteo. */
export type OpcionMultiple = { id: number; nombre: string; contratos?: number | null };
const sinTildes = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

const ESTILO_PANEL: React.CSSProperties = {
  position: "absolute", top: "calc(100% + 4px)", zIndex: 60, minWidth: 260, maxWidth: "min(420px, calc(100vw - 32px))",
  background: "var(--dash-carta, #fff)", color: "var(--dash-texto, #22313f)", border: "1px solid var(--dash-linea, #dde5ea)",
  borderRadius: 8, boxShadow: "0 8px 24px rgba(10, 37, 64, 0.18)", padding: "8px 10px", boxSizing: "border-box",
};

export function FiltroMultiple({ etiqueta, opciones, elegidas, onCambio, buscable = false, alinearDerecha = false, ayuda, vacio = "Sin coincidencias." }: {
  etiqueta: string; opciones: OpcionMultiple[]; elegidas: number[]; onCambio: (ids: number[]) => void; buscable?: boolean; alinearDerecha?: boolean; ayuda?: string; vacio?: string;
}) {
  const [q, setQ] = useState("");
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const fuera = (e: PointerEvent) => { const d = ref.current; if (d && d.open && !d.contains(e.target as Node)) d.open = false; };
    document.addEventListener("pointerdown", fuera);
    return () => document.removeEventListener("pointerdown", fuera);
  }, []);
  const visibles = q ? opciones.filter((o) => sinTildes(o.nombre).includes(sinTildes(q))) : opciones;
  const alternar = (id: number) => onCambio(elegidas.includes(id) ? elegidas.filter((x) => x !== id) : [...elegidas, id]);
  return (
    <details ref={ref} className="dash-filtro-multiple" style={{ position: "relative", display: "inline-block" }}>
      <summary style={{ cursor: "pointer", fontSize: 12.5, border: "1px solid var(--dash-linea, #dde5ea)", borderRadius: 6, padding: "4px 10px", background: "var(--dash-carta, #fff)", color: "var(--dash-texto, #22313f)", listStyle: "none" }}>
        {etiqueta}{elegidas.length ? ` (${elegidas.length})` : ""} ▾
      </summary>
      <div style={{ ...ESTILO_PANEL, ...(alinearDerecha ? { right: 0 } : { left: 0 }) }}>
        {ayuda ? <div style={{ fontSize: 11.5, lineHeight: 1.35, color: "var(--dash-texto-suave, #5d6e7e)", marginBottom: 6 }}>{ayuda}</div> : null}
        {buscable ? <input type="search" value={q} placeholder="Buscar…" onChange={(e) => setQ(e.target.value)} aria-label={`Buscar en ${etiqueta}`} style={{ width: "100%", boxSizing: "border-box", marginBottom: 6 }} /> : null}
        <div className="dash-filtro-multiple-lista" style={{ maxHeight: "min(260px, 45vh)", overflow: "auto" }}>
          {visibles.map((o) => (
            <label key={o.id} style={{ display: "block", fontSize: 12.5, padding: "2px 0" }}>
              <input type="checkbox" checked={elegidas.includes(o.id)} onChange={() => alternar(o.id)} /> {o.nombre}
              {o.contratos === undefined ? "" : o.contratos === null ? " · menos de 5 contratos" : ` · ${o.contratos.toLocaleString("es-CO")}`}
            </label>
          ))}
          {!visibles.length ? <div style={{ fontSize: 12, color: "var(--dash-texto-suave, #5d6e7e)" }}>{vacio}</div> : null}
        </div>
        {elegidas.length ? <button type="button" onClick={() => onCambio([])} style={{ marginTop: 6, font: "inherit", fontSize: 12, background: "transparent", border: 0, textDecoration: "underline", cursor: "pointer", color: "inherit", padding: 0 }}>Quitar selección</button> : null}
      </div>
    </details>
  );
}
