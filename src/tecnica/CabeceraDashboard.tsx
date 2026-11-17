import { useEffect, type ReactNode } from "react";
import "./dashboard.css";
import { FranjaAvisos } from "./Avisos";

// Encabezado común del Dashboard PTAP y del Dashboard distribución (§34 de la bitácora): el mismo armado, las mismas fuentes, pestañas y botones; solo cambia el
// color (PTAP azul oscuro, distribución verde oscuro: clase «tdash-verde» en la raíz). El selector PTAP | distribución va DENTRO del encabezado: antes iba
// como un bloque hermano del dashboard y los dos se repartían el alto de la pantalla (la franja vacía arriba y el contenido cortado abajo).

export type PestanaDash = { clave: string; titulo: string; pronto?: boolean };

// Corte 12: un aviso abre su bandeja. Quien abre el dashboard pide la pestaña antes de montarlo; el encabezado la elige UNA vez al montarse (así los dashboards no cambian).
let pestanaPedida: string | null = null;
export function pedirPestana(clave: string | null) { pestanaPedida = clave; }

export function CabeceraDashboard({ titulo, sesion, onVolver, selector, pestanas, activa, onElegir, etiqueta, onGeovisor }: {
  titulo: string; sesion: string; onVolver: () => void; selector?: ReactNode; onGeovisor?: () => void;      // Corte 6b: entrada al geovisor desde el dashboard
  pestanas: PestanaDash[]; activa: string; onElegir: (clave: string) => void; etiqueta: string;
}) {
  useEffect(() => {
    const c = pestanaPedida; pestanaPedida = null;
    if (c && c !== activa && pestanas.some((s) => s.clave === c && !s.pronto)) onElegir(c);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
    <div className="tdash-cab">
      <div className="tdash-ancho">
        {selector}
        <div className="tdash-fila">
          <h1>{titulo}</h1>
          <button type="button" className="td-boton-claro" onClick={onVolver}>← Volver al inicio</button>
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
    {/* Corte 12: la franja corta con los avisos de este dashboard (solo si AreaTecnica la da y hay avisos) */}
    <FranjaAvisos onElegir={onElegir} pestanas={pestanas.filter((s) => !s.pronto).map((s) => s.clave)} />
    </>
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
