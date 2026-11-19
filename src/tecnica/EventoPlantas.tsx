import { useState } from "react";
import { apiEventos, type CatalogoEventos, type PlantaCat } from "./apiEventos";
import { errorEvento } from "./EventoDeclarar";

// Corte 15 · «Sectores de cada planta»: qué sectores o subsectores hidráulicos surte cada planta. Lo ajustan el supervisor de distribución o el administrador,
// siempre con motivo (queda el historial en el servidor; nada se borra). Arranca vacía; sin sectores, el evento total «por planta» no se puede declarar.

export function EventoPlantas({ cat, alGuardar }: { cat: CatalogoEventos; alGuardar: () => void }) {
  return (
    <div className="evs" data-testid="evs-plantas">
      <section className="tec-tarjeta">
        <h2>Sectores de cada planta</h2>
        <p className="red-texto">Diga qué sectores o subsectores hidráulicos surte cada planta. Con eso se puede declarar un evento total «por planta» (falla de planta, de captación o de energía): su zona es la suma de esos sectores.</p>
        <p className="tec-ayuda">Mientras una planta no tenga sectores asignados, el evento «por planta» no se puede declarar. Cada cambio pide el motivo y queda en el historial.</p>
      </section>
      {cat.plantas.map((p) => <Planta key={p.codigo} p={p} cat={cat} alGuardar={alGuardar} />)}
    </div>
  );
}

function Planta({ p, cat, alGuardar }: { p: PlantaCat; cat: CatalogoEventos; alGuardar: () => void }) {
  const [sel, setSel] = useState<string[]>(p.sectores);
  const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null); const [aviso, setAviso] = useState<string | null>(null);
  const cambio = [...sel].sort().join() !== [...p.sectores].sort().join();
  async function guardar() {
    setOcupado(true); setError(null); setAviso(null);
    try { const r = await apiEventos.plantaSectores(p.codigo, sel, motivo.trim()); setAviso(`${r.nombre}: ${r.sectores.length === 0 ? "quedó sin sectores" : r.sectores.length === 1 ? "1 sector o subsector asignado" : `${r.sectores.length} sectores o subsectores asignados`}.`); setMotivo(""); alGuardar(); }
    catch (e) { setError(errorEvento(e)); } finally { setOcupado(false); }
  }
  const grupo = (clase: "sector" | "subsector", titulo: string) => {
    const lista = cat.sectores.filter((s) => s.clase === clase);
    return lista.length ? (
      <fieldset className="evs-sectores" data-clase={clase}><legend className="dan-rot">{titulo}</legend>
        {lista.map((s) => <label key={s.codigo} className="dan-check"><input type="checkbox" checked={sel.includes(s.codigo)} disabled={ocupado} data-sector={s.codigo}
          onChange={(e) => setSel((x) => (e.target.checked ? [...x, s.codigo] : x.filter((c) => c !== s.codigo)))} />{s.nombre}</label>)}
      </fieldset>) : null;
  };
  return (
    <section className="tec-tarjeta" aria-label={`Planta ${p.nombre}`} data-planta={p.codigo}>
      <h2>{p.nombre} <span className="itv-etiqueta" data-testid="evs-planta-n">{p.sectores.length === 0 ? "Sin sectores asignados" : p.sectores.length === 1 ? "1 asignado" : `${p.sectores.length} asignados`}</span></h2>
      {grupo("sector", "Sectores hidráulicos")}{grupo("subsector", "Subsectores")}
      {aviso ? <p className="tec-aviso tec-aviso-ok" role="status">{aviso}</p> : null}
      {cambio ? (
        <div className="cie-pedir" role="group" aria-label={`Guardar los sectores de ${p.nombre}`}>
          <div className="tec-campo"><label htmlFor={`evs-pm-${p.codigo}`}>Motivo del cambio (10 caracteres o más)</label>
            <input id={`evs-pm-${p.codigo}`} type="text" maxLength={300} value={motivo} disabled={ocupado} onChange={(e) => setMotivo(e.target.value)} placeholder="Según el esquema de distribución entregado por Técnica." /></div>
          {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
          <div className="tec-acciones">
            <button type="button" className="tec-boton" disabled={ocupado || motivo.trim().length < 10} data-testid="evs-planta-guardar" onClick={() => void guardar()}>{ocupado ? "Guardando…" : `Guardar los sectores de ${p.nombre}`}</button>
            <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => { setSel(p.sectores); setMotivo(""); setError(null); }}>Deshacer</button></div>
        </div>) : null}
    </section>
  );
}
