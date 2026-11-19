import { useState } from "react";
import { apiEventos, NOMBRE_ORIGEN, type CatalogoEventos, type OrigenReporte, type TipoAsociable } from "./apiEventos";
import { errorEvento } from "./EventoDeclarar";

// Corte 15 · «Qué reportes se asocian»: qué tipos del bot, causales de la línea 116, tipos de daño y tipos del formato de campo se asocian solos a un evento
// abierto. Lo ajustan el supervisor de distribución o el administrador, siempre con motivo (queda el historial en el servidor; nada se borra).
const CLASE: Record<string, string> = { sin_agua: "Falta de agua o baja presión", dano_red: "Daño en la red", otro: "Otro" };
const ORIGENES: OrigenReporte[] = ["bot", "l116", "dano", "campo"];
const TITULO_ORIGEN: Record<OrigenReporte, string> = { bot: "Bot de reportes", l116: "Línea 116 (causales)", dano: "Daños y fallas (formulario)", campo: "Formato de campo de Comercial" };

export function EventoTipos({ cat, alGuardar }: { cat: CatalogoEventos; alGuardar: () => void }) {
  const [nuevo, setNuevo] = useState(false);
  return (
    <div className="evs" data-testid="evs-tipos">
      <section className="tec-tarjeta">
        <h2>Qué reportes se asocian</h2>
        <p className="red-texto">Un reporte que llega dentro de la zona de un evento abierto se asocia solo si su tipo está en esta lista. Lo demás sigue su flujo de siempre.</p>
        <p className="tec-ayuda">Cada cambio pide el motivo y queda en el historial. No afecta los reportes que ya están asociados.</p>
        {!nuevo ? <button type="button" className="tec-boton-sec" data-testid="evs-tipo-nuevo" onClick={() => setNuevo(true)}>Agregar un tipo a la lista</button> : <TipoNuevo cat={cat} onCerrar={() => setNuevo(false)} alGuardar={alGuardar} />}
      </section>
      {ORIGENES.map((o) => { const lista = cat.tipos.filter((t) => t.origen === o); return (
        <section key={o} className="tec-tarjeta" aria-label={TITULO_ORIGEN[o]} data-origen-tipos={o}>
          <h2>{TITULO_ORIGEN[o]}</h2>
          {lista.length === 0 ? <p className="red-vacio">Ninguno en la lista.</p> : null}
          <ul className="evs-items">{lista.map((t) => <Tipo key={`${t.origen}:${t.codigo}`} t={t} alGuardar={alGuardar} />)}</ul>
        </section>); })}
    </div>
  );
}

function Tipo({ t, alGuardar }: { t: TipoAsociable; alGuardar: () => void }) {
  const [abierto, setAbierto] = useState(false); const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  async function cambiar() {
    setOcupado(true); setError(null);
    try { await apiEventos.tipoFijar({ origen: t.origen, codigo: t.codigo, asocia: !t.asocia, motivo: motivo.trim() }); setAbierto(false); setMotivo(""); alGuardar(); }
    catch (e) { setError(errorEvento(e)); } finally { setOcupado(false); }
  }
  return (
    <li data-tipo={`${t.origen}:${t.codigo}`} data-asocia={t.asocia ? "si" : "no"}>
      <p><strong>{t.nombre}</strong> <span className={`itv-etiqueta ${t.asocia ? "evs-estado-cerrado" : "evs-estado-anulado"}`}>{t.asocia ? "Se asocia" : "No se asocia"}</span></p>
      <p className="tec-ayuda">{CLASE[t.clase] ?? t.clase}</p>
      {!abierto ? <button type="button" className="tec-enlace" onClick={() => { setAbierto(true); setError(null); }}>{t.asocia ? "Dejar de asociarlo" : "Volver a asociarlo"}</button> : (
        <div className="cie-pedir" role="group" aria-label={`Cambiar ${t.nombre}`}>
          <div className="tec-campo"><label htmlFor={`evs-tm-${t.origen}-${t.codigo}`}>Motivo (10 caracteres o más)</label>
            <input id={`evs-tm-${t.origen}-${t.codigo}`} className="evs-tipo-motivo" type="text" maxLength={300} value={motivo} disabled={ocupado} onChange={(e) => setMotivo(e.target.value)} /></div>
          {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
          <div className="tec-acciones">
            <button type="button" className="tec-boton" disabled={ocupado || motivo.trim().length < 10} data-testid="evs-tipo-confirmar" onClick={() => void cambiar()}>{ocupado ? "Guardando…" : t.asocia ? "Dejar de asociarlo" : "Volver a asociarlo"}</button>
            <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => setAbierto(false)}>Cancelar</button></div>
        </div>)}
    </li>
  );
}

function TipoNuevo({ cat, onCerrar, alGuardar }: { cat: CatalogoEventos; onCerrar: () => void; alGuardar: () => void }) {
  const [origen, setOrigen] = useState<OrigenReporte>("l116"); const [codigo, setCodigo] = useState(""); const [nombre, setNombre] = useState(""); const [clase, setClase] = useState("sin_agua");
  const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const clases = [...new Set(["sin_agua", "dano_red", "otro", ...cat.tipos.map((t) => t.clase)])];
  async function guardar() {
    setOcupado(true); setError(null);
    try { await apiEventos.tipoFijar({ origen, codigo: codigo.trim(), asocia: true, motivo: motivo.trim(), nombre: nombre.trim(), clase }); alGuardar(); onCerrar(); }
    catch (e) { setError(errorEvento(e)); } finally { setOcupado(false); }
  }
  return (
    <div className="cie-pedir" role="group" aria-label="Agregar un tipo a la lista" data-testid="evs-f-tipo">
      <div className="dan-fila" role="group" aria-label="De dónde es">{ORIGENES.map((o) => <button key={o} type="button" className="dan-opcion" aria-pressed={origen === o} data-origen={o} disabled={ocupado} onClick={() => setOrigen(o)}>{NOMBRE_ORIGEN[o]}</button>)}</div>
      <div className="tec-campo"><label htmlFor="evs-tn-cod">{origen === "l116" ? "Causal de la línea 116, tal como viene en el archivo" : "Código del tipo"}</label>
        <input id="evs-tn-cod" type="text" maxLength={120} autoComplete="off" value={codigo} disabled={ocupado} onChange={(e) => setCodigo(e.target.value)} />
        <span className="tec-ayuda">{origen === "l116" ? "Se compara sin distinguir mayúsculas." : "El código que usa el sistema para ese tipo (no el nombre)."}</span></div>
      <div className="tec-campo"><label htmlFor="evs-tn-nom">Nombre para mostrar</label><input id="evs-tn-nom" type="text" maxLength={120} value={nombre} disabled={ocupado} onChange={(e) => setNombre(e.target.value)} /></div>
      <div className="tec-campo"><label htmlFor="evs-tn-clase">Clase</label>
        <select id="evs-tn-clase" value={clase} disabled={ocupado} onChange={(e) => setClase(e.target.value)}>{clases.map((c) => <option key={c} value={c}>{CLASE[c] ?? c}</option>)}</select></div>
      <div className="tec-campo"><label htmlFor="evs-tn-mot">Motivo (10 caracteres o más)</label><input id="evs-tn-mot" type="text" maxLength={300} value={motivo} disabled={ocupado} onChange={(e) => setMotivo(e.target.value)} /></div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert" data-testid="evs-error-tipo">{error}</p> : null}
      <div className="tec-acciones">
        <button type="button" className="tec-boton" disabled={ocupado || !codigo.trim() || nombre.trim().length < 3 || motivo.trim().length < 10} data-testid="evs-tipo-agregar" onClick={() => void guardar()}>{ocupado ? "Guardando…" : "Agregar a la lista"}</button>
        <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={onCerrar}>Cancelar</button></div>
    </div>
  );
}
