import { useEffect, useState } from "react";
import { apiScrr, avisoDeError, type ContextoScrr } from "./apiScrr";
import { PanelCargas } from "./PanelCargas";
import { PanelSeleccion } from "./PanelSeleccion";
import { PanelControl } from "./PanelControl";
import { PanelCalendario } from "./PanelCalendario";
import "./scrr.css";

// Modo de trabajo «Cartera» del Geoportal Comercial (Motor SCRR; decisión 1 del 22-nov). Lo abren el Supervisor comercial (dashboard_campo) y el administrador
// (decisión 3). La cápsula solo lo muestra a ellos; el servidor lo vuelve a decidir en cada llamada.
// Corte 2: «Carga del día» (commit 1); Selección, Contratos con control, Excluidos y Calendario (commit 2). «Retorno» llega en el commit 3.
type Pestana = "carga" | "seleccion" | "control" | "excluidos" | "calendario";
const PESTANAS: [Pestana, string][] = [["carga", "Carga del día"], ["seleccion", "Selección"], ["control", "Contratos con control"], ["excluidos", "Excluidos"], ["calendario", "Calendario"]];

export function ModoCartera() {
  const [ctx, setCtx] = useState<ContextoScrr | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pestana, setPestana] = useState<Pestana>("carga");
  useEffect(() => { apiScrr.contexto().then(setCtx).catch((e) => setError(avisoDeError(e))); }, []);

  if (error) return <div className="scrr-area"><p className="scrr-error" role="alert">{error}</p></div>;
  if (!ctx) return <div className="scrr-area"><p className="scrr-suave">Cargando el modo Cartera…</p></div>;
  return (
    <div className="scrr-area" data-pantalla="cartera">
      <h1>Cartera</h1>
      <p className="scrr-suave">Motor de suspensiones, cortes y reconexiones: la carga del día alimenta la selección y la lista de retorno.</p>
      <nav className="scrr-tabs" aria-label="Pestañas del modo Cartera">
        {PESTANAS.map(([k, t]) => <button key={k} className={pestana === k ? "activa" : ""} onClick={() => setPestana(k)} data-pestana={k}>{t}</button>)}
      </nav>
      {pestana === "carga" && <PanelCargas ctx={ctx} />}
      {pestana === "seleccion" && <PanelSeleccion />}
      {pestana === "control" && <PanelControl ctx={ctx} grupo="control" key="control" />}
      {pestana === "excluidos" && <PanelControl ctx={ctx} grupo="excluido" key="excluido" />}
      {pestana === "calendario" && <PanelCalendario />}
    </div>
  );
}
