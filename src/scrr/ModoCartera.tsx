import { useEffect, useState } from "react";
import { apiScrr, avisoDeError, type ContextoScrr } from "./apiScrr";
import { PanelCargas } from "./PanelCargas";
import { PanelSeleccion } from "./PanelSeleccion";
import { PanelControl } from "./PanelControl";
import { PanelCalendario } from "./PanelCalendario";
import { PanelRetorno } from "./PanelRetorno";
import "./scrr.css";

// Modo de trabajo «Cartera» del Geoportal Comercial (Motor SCRR; decisión 1 del 22-nov). Lo abren el Supervisor comercial (dashboard_campo) y el administrador
// (decisión 3). La cápsula solo lo muestra a ellos; el servidor lo vuelve a decidir en cada llamada.
// Corte 2: «Carga del día» (commit 1); Selección, Contratos con control, Excluidos y Calendario (commit 2); Restablecer (commit 3; internamente «retorno»).
type Pestana = "carga" | "seleccion" | "retorno" | "control" | "excluidos" | "calendario";
const PESTANAS: [Pestana, string][] = [["carga", "Carga del día"], ["seleccion", "Selección"], ["retorno", "Restablecer"], ["control", "Contratos con control"], ["excluidos", "Excluidos"], ["calendario", "Calendario"]];
const MESES = ["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"];

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
      <p className="scrr-suave">Motor de suspensiones, cortes y reconexiones: la carga del día alimenta la selección y la lista para restablecer el servicio.</p>
      {ctx.calendario_actual.ciclos === 0 && (
        // Aviso visible (David, 22-nov 21:21): sin calendario del mes, las vencidas usan la regla prudente y la selección no tiene ciclos
        <p className="scrr-aviso" role="alert" data-bloque="sin-calendario">El calendario de {MESES[Number(ctx.calendario_actual.periodo.slice(4)) - 1]} de {ctx.calendario_actual.periodo.slice(0, 4)} no está cargado:
          las facturas vencidas se calculan con la regla prudente y la selección no tiene ciclos.{" "}
          <button className="scrr-link" onClick={() => setPestana("calendario")} data-accion="ir-calendario">Cargarlo ahora (puede copiar el del mes anterior)</button></p>
      )}
      <nav className="scrr-tabs" aria-label="Pestañas del modo Cartera">
        {PESTANAS.map(([k, t]) => <button key={k} className={pestana === k ? "activa" : ""} onClick={() => setPestana(k)} data-pestana={k}>{t}</button>)}
      </nav>
      {pestana === "carga" && <PanelCargas ctx={ctx} />}
      {pestana === "seleccion" && <PanelSeleccion />}
      {pestana === "retorno" && <PanelRetorno />}
      {pestana === "control" && <PanelControl ctx={ctx} grupo="control" key="control" />}
      {pestana === "excluidos" && <PanelControl ctx={ctx} grupo="excluido" key="excluido" />}
      {pestana === "calendario" && <PanelCalendario onCambio={() => void apiScrr.contexto().then(setCtx).catch(() => {})} />}
    </div>
  );
}
