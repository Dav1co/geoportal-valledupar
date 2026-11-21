import { useState } from "react";
import { apiEventos, type CatalogoEventos, type TuboCat } from "./apiEventos";
import { errorEvento } from "./EventoDeclarar";

// Corte «origen y tubos» (decisión de David, 20-nov) · «Tubo de salida → sectores»: qué sectores o subsectores hidráulicos abastece cada tubo de salida de la
// planta (los puntos de distribución, los mismos del formulario de Salida). Reemplaza a «Sectores de cada planta»: el sistema es único (las dos plantas lo
// alimentan) y un evento de planta cubre toda la ciudad. Lo ajustan el supervisor de distribución o el administrador, siempre con motivo (queda el historial en el
// servidor; nada se borra). Los tubos arrancan sin sectores; mientras un tubo no tenga, no se puede declarar un evento «Por tubo» con él.
// En pantalla, cada tubo va por su nombre (Distrito Norte) con el código pequeño al lado (DIS-NORTE).

export function EventoTubos({ cat, alGuardar }: { cat: CatalogoEventos; alGuardar: () => void }) {
  const tubos = cat.tubos ?? [];
  return (
    <div className="evs" data-testid="evs-tubos-sectores">
      <section className="tec-tarjeta">
        <h2>Tubo de salida → sectores</h2>
        <p className="red-texto">Diga qué sectores o subsectores hidráulicos abastece cada tubo de salida de la planta. Con eso se puede declarar un evento «Por tubo»: su zona es la suma de los sectores de los tubos que se marquen.</p>
        <p className="tec-ayuda">Mientras un tubo no tenga sectores asignados, no se puede declarar «Por tubo» con él. Cada cambio pide el motivo y queda en el historial.</p>
        {tubos.length === 0 ? <p className="tec-aviso tec-aviso-info" role="status" data-testid="evs-sin-tubos">No hay tubos de salida en el catálogo de puntos de la planta.</p> : null}
      </section>
      {tubos.map((t) => <Tubo key={t.codigo} t={t} cat={cat} alGuardar={alGuardar} />)}
    </div>
  );
}

const nAsignados = (n: number) => (n === 0 ? "Sin sectores asignados" : n === 1 ? "1 asignado" : `${n} asignados`);

function Tubo({ t, cat, alGuardar }: { t: TuboCat; cat: CatalogoEventos; alGuardar: () => void }) {
  const [base, setBase] = useState<string[]>(t.sectores);      // lo guardado (se actualiza con la respuesta, sin esperar al catálogo)
  const [sel, setSel] = useState<string[]>(t.sectores);
  const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null); const [aviso, setAviso] = useState<string | null>(null);
  const cambio = [...sel].sort().join() !== [...base].sort().join();
  async function guardar() {
    setOcupado(true); setError(null); setAviso(null);
    try {
      const r = await apiEventos.tuboSectores(t.codigo, sel, motivo.trim());
      setBase(r.sectores); setSel(r.sectores);
      setAviso(`${r.nombre}: ${r.sectores.length === 0 ? "quedó sin sectores" : r.sectores.length === 1 ? "1 sector o subsector asignado" : `${r.sectores.length} sectores o subsectores asignados`}.`); setMotivo(""); alGuardar();
    } catch (e) { setError(errorEvento(e)); } finally { setOcupado(false); }
  }
  const grupo = (clase: "sector" | "subsector", titulo: string) => {
    const lista = cat.sectores.filter((s) => s.clase === clase);
    return lista.length ? (
      <fieldset className="evs-sectores" data-clase={clase}><legend className="dan-rot">{titulo}</legend>
        {lista.map((s) => <label key={s.codigo} className="dan-check"><input type="checkbox" checked={sel.includes(s.codigo)} disabled={ocupado || !t.activo} data-sector={s.codigo}
          onChange={(e) => setSel((x) => (e.target.checked ? [...x, s.codigo] : x.filter((c) => c !== s.codigo)))} />{s.nombre}</label>)}
      </fieldset>) : null;
  };
  return (
    <section className="tec-tarjeta" aria-label={`Tubo ${t.nombre}`} data-tubo={t.codigo}>
      <h2><span className="evs-tubo-nom">{t.nombre}</span> <small className="evs-tubo-cod tec-codigo">{t.codigo}</small> <span className="itv-etiqueta" data-testid="evs-tubo-n">{nAsignados(base.length)}</span></h2>
      {!t.activo ? <p className="tec-ayuda">Este tubo está inactivo en el catálogo de puntos: no se le asignan sectores.</p> : null}
      {grupo("sector", "Sectores hidráulicos")}{grupo("subsector", "Subsectores")}
      {cat.sectores.length === 0 ? <p className="tec-aviso tec-aviso-error" role="alert">No hay sectores hidráulicos cargados.</p> : null}
      {aviso ? <p className="tec-aviso tec-aviso-ok" role="status">{aviso}</p> : null}
      {cambio ? (
        <div className="cie-pedir" role="group" aria-label={`Guardar los sectores de ${t.nombre}`}>
          <div className="tec-campo"><label htmlFor={`evs-tbm-${t.codigo}`}>Motivo del cambio (10 caracteres o más)</label>
            <input id={`evs-tbm-${t.codigo}`} type="text" maxLength={300} value={motivo} disabled={ocupado} onChange={(e) => setMotivo(e.target.value)} placeholder="Según el esquema de distribución entregado por la planta." /></div>
          {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
          <div className="tec-acciones">
            <button type="button" className="tec-boton" disabled={ocupado || motivo.trim().length < 10} data-testid="evs-tubo-guardar" onClick={() => void guardar()}>{ocupado ? "Guardando…" : `Guardar los sectores de ${t.nombre}`}</button>
            <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => { setSel(base); setMotivo(""); setError(null); }}>Deshacer</button></div>
        </div>) : null}
    </section>
  );
}
