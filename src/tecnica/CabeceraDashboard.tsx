import type { ReactNode } from "react";
import "./dashboard.css";

// Encabezado común del Dashboard PTAP y del Dashboard distribución (§34 de la bitácora): el mismo armado, las mismas fuentes, pestañas y botones; solo cambia el
// color (PTAP azul oscuro, distribución verde oscuro: clase «tdash-verde» en la raíz). El selector PTAP | distribución va DENTRO del encabezado: antes iba
// como un bloque hermano del dashboard y los dos se repartían el alto de la pantalla (la franja vacía arriba y el contenido cortado abajo).

export type PestanaDash = { clave: string; titulo: string; pronto?: boolean };

export function CabeceraDashboard({ titulo, sesion, onVolver, selector, pestanas, activa, onElegir, etiqueta, onGeovisor }: {
  titulo: string; sesion: string; onVolver: () => void; selector?: ReactNode; onGeovisor?: () => void;      // Corte 6b: entrada al geovisor desde el dashboard
  pestanas: PestanaDash[]; activa: string; onElegir: (clave: string) => void; etiqueta: string;
}) {
  return (
    <div className="tdash-cab">
      <div className="tdash-ancho">
        {selector}
        <div className="tdash-fila">
          <h1>{titulo}</h1>
          <button type="button" className="td-boton-claro" onClick={onVolver}>← Volver a mis formularios</button>
          {onGeovisor ? <button type="button" className="td-boton-claro" onClick={onGeovisor}>Geovisor técnico</button> : null}
        </div>
        <div className="tdash-sesion">{sesion}</div>
        <nav className="tdash-tabs" aria-label={etiqueta} role="tablist">
          {pestanas.map((s) => s.pronto
            ? <button key={s.clave} type="button" role="tab" aria-selected={false} className="tdash-tab tdash-tab-pronto" disabled aria-disabled="true" title="Próximamente">{s.titulo}<span className="td-pronto">Próximamente</span></button>
            : <button key={s.clave} type="button" role="tab" aria-selected={activa === s.clave} className="tdash-tab" aria-current={activa === s.clave ? "page" : undefined}
                onClick={() => onElegir(s.clave)}>{s.titulo}</button>)}
        </nav>
      </div>
    </div>
  );
}

/** El selector «Dashboard PTAP | Dashboard distribución», para quien tiene los dos. Va dentro del encabezado de cada uno. */
export function SelectorDashboards({ actual, onElegir }: { actual: "ptap" | "distribucion"; onElegir: (d: "ptap" | "distribucion") => void }) {
  return (
    <div className="tdash-selector" role="group" aria-label="Dashboard">
      <button type="button" className="tdash-sel" aria-pressed={actual === "ptap"} onClick={() => onElegir("ptap")}>Dashboard PTAP</button>
      <button type="button" className="tdash-sel" aria-pressed={actual === "distribucion"} onClick={() => onElegir("distribucion")}>Dashboard distribución</button>
    </div>
  );
}
