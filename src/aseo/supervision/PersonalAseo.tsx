import { useCallback, useEffect, useRef, useState } from "react";
import { apiSup, textoError, type EventoPersonal, type Persona, type TipoCambio } from "./api";
import { DialogoMotivo, ErrorCaja, fmtInstanteBogota, nombreCorto } from "./comun";

// «Personal»: cargo del auditor (sale en el acta), actividades que audita cada persona y activación a nivel de Aseo, todo con historial y motivo. EN ESTE CORTE las asignaciones y la activación SOLO SE REGISTRAN:
// no restringen la captura (sin asignación puede todas las actividades activas). Los permisos generales siguen en Administración. Nada se borra: cada cambio es un evento y se puede revertir con otro evento.
type Pendiente = { persona: Persona; tipo: TipoCambio; actividad?: string };
export function PersonalAseo() {
  const [buscar, setBuscar] = useState(""); const [sup, setSup] = useState(false);
  const [datos, setDatos] = useState<Awaited<ReturnType<typeof apiSup.personal>> | null>(null); const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [dlg, setDlg] = useState<Pendiente | null>(null); const [aviso, setAviso] = useState<string | null>(null); const [historial, setHistorial] = useState<string | null | undefined>(undefined);
  const [cargos, setCargos] = useState<Record<string, string>>({}); const version = useRef(0);
  const cargar = useCallback(async () => { const v = ++version.current; try { const r = await apiSup.personal(buscar.trim(), sup); if (v === version.current) { setDatos(r); setError(null); } } catch (e) { if (v === version.current) setError(textoError(e)); } }, [buscar, sup]);
  useEffect(() => { const t = setTimeout(() => void cargar(), 250); return () => clearTimeout(t); }, [cargar]);
  const nombreAct = (c: string) => datos?.actividades.find((a) => a.codigo === c)?.nombre ?? c;
  const quien = (p: { nombre: string | null; email: string }) => p.nombre ?? nombreCorto(p.email);

  async function cambiar(p: Persona, tipo: TipoCambio, o: { actividad?: string; cargo?: string; motivo?: string }, texto: string) {
    try { await apiSup.cambiar(p.email, tipo, o); setAviso(texto); setDlg(null); await cargar(); } catch (e) { throw new Error(textoError(e).texto); }
  }
  async function guardarCargo(p: Persona) {
    const c = (cargos[p.email] ?? p.cargo ?? "").trim(); setAviso(null);
    try { await apiSup.cambiar(p.email, "fijar_cargo", { cargo: c }); setAviso(`Cargo de ${quien(p)} guardado: «${c}».`); setCargos((x) => { const n = { ...x }; delete n[p.email]; return n; }); await cargar(); } catch (e) { setError(textoError(e)); }
  }

  if (historial !== undefined) return <Historial persona={historial} nombreAct={nombreAct} onVolver={() => setHistorial(undefined)} onHecho={(t) => { setAviso(t); void cargar(); }} />;
  return (
    <section className="td-seccion" aria-labelledby="as-per-tit">
      <div className="td-cab"><div><h2 id="as-per-tit">Personal</h2>
        <p className="td-sub">Cargo (sale en el acta), actividades que audita cada persona y activación en Aseo. En este corte las asignaciones y la activación solo se registran: no restringen la captura. Los permisos generales se dan en Administración.</p></div>
        <button type="button" className="td-boton-sec" onClick={() => setHistorial(null)}>Historial de cambios</button></div>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <ErrorCaja error={error} onReintentar={() => void cargar()} /> : null}
      <div className="td-filtros-cuerpo">
        <label className="td-campo">Buscar por nombre o correo<input type="text" value={buscar} maxLength={80} onChange={(e) => setBuscar(e.target.value)} /></label>
        <label className="td-check"><input type="checkbox" checked={sup} onChange={(e) => setSup(e.target.checked)} /> Incluir supervisores</label>
      </div>
      {!datos && !error ? <p className="td-sub" role="status">Cargando el personal…</p> : null}
      {datos && datos.personas.length === 0 ? <p className="tr-vacio">Nadie con acceso a Aseo coincide con la búsqueda</p> : null}
      <ul className="as-personas">
        {(datos?.personas ?? []).map((p) => {
          const cargo = cargos[p.email] ?? p.cargo ?? "";
          return (
            <li key={p.email} className="as-persona" data-persona={p.email}>
              <div className="as-persona-cab"><strong className="td-nombre">{quien(p)}</strong> <span className="td-chico">{p.email} · {p.perfil === "supervisor" ? "Supervisor" : "Auditor"}</span>
                {!p.activo_aseo ? <span className="td-marca td-marca-alerta">Desactivada en Aseo</span> : null}{!p.cargo ? <span className="td-marca td-marca-alerta">Sin cargo</span> : null}</div>
              <div className="as-fila">
                <label className="td-campo">Cargo<input type="text" value={cargo} maxLength={80} onChange={(e) => setCargos((x) => ({ ...x, [p.email]: e.target.value }))} placeholder="Cargo en la interventoría" /></label>
                <button type="button" className="td-boton-sec" disabled={cargo.trim().length < 2 || cargo.trim() === (p.cargo ?? "")} onClick={() => void guardarCargo(p)}>Guardar cargo</button>
              </div>
              <fieldset className="td-casillas"><legend>Actividades que audita</legend>
                {datos!.actividades.map((a) => { const tiene = p.actividades.includes(a.codigo); return (
                  <label key={a.codigo} className="td-check"><input type="checkbox" checked={tiene} onChange={() => (tiene ? setDlg({ persona: p, tipo: "quitar_actividad", actividad: a.codigo }) : void cambiar(p, "asignar_actividad", { actividad: a.codigo }, `Se asignó «${a.nombre}» a ${quien(p)}.`).catch((e: Error) => setError({ texto: e.message, sesion: false })))} /> {a.nombre}{a.activa ? "" : " (aún no activa)"}</label>); })}
                <span className="td-chico">{p.actividades.length === 0 ? "Sin asignación: puede todas las actividades activas." : "Asignada: queda registrado (no restringe todavía)."}</span></fieldset>
              <div className="td-botones">
                <button type="button" className="td-boton-sec" onClick={() => (p.activo_aseo ? setDlg({ persona: p, tipo: "desactivar_aseo" }) : void cambiar(p, "activar_aseo", {}, `Se reactivó a ${quien(p)} en Aseo.`).catch((e: Error) => setError({ texto: e.message, sesion: false })))}>{p.activo_aseo ? "Desactivar en Aseo" : "Reactivar en Aseo"}</button>
                <button type="button" className="td-boton-sec" onClick={() => setHistorial(p.email)}>Historial</button></div>
            </li>); })}
      </ul>
      {dlg ? <DialogoMotivo titulo={dlg.tipo === "quitar_actividad" ? `Quitar «${nombreAct(dlg.actividad ?? "")}»` : "Desactivar en Aseo"} texto={dlg.tipo === "quitar_actividad" ? `Se quita la actividad a ${quien(dlg.persona)}. Queda registrado quién, cuándo y por qué.` : `${quien(dlg.persona)} queda desactivada en Aseo (la cuenta sigue activa en el resto del geoportal). En este corte solo se registra.`}
        rotulo="Motivo" min={10} max={300} boton={dlg.tipo === "quitar_actividad" ? "Quitar" : "Desactivar"} onCerrar={() => setDlg(null)}
        onConfirmar={(m) => cambiar(dlg.persona, dlg.tipo, { actividad: dlg.actividad, motivo: m }, dlg.tipo === "quitar_actividad" ? `Se quitó «${nombreAct(dlg.actividad ?? "")}» a ${quien(dlg.persona)}.` : `${quien(dlg.persona)} quedó desactivada en Aseo.`)} /> : null}
    </section>
  );
}

const TEXTO_EV: Record<TipoCambio, string> = { fijar_cargo: "Cargo", asignar_actividad: "Se asignó", quitar_actividad: "Se quitó", activar_aseo: "Se reactivó en Aseo", desactivar_aseo: "Se desactivó en Aseo" };
function Historial({ persona, nombreAct, onVolver, onHecho }: { persona: string | null; nombreAct: (c: string) => string; onVolver: () => void; onHecho: (t: string) => void }) {
  const [ev, setEv] = useState<EventoPersonal[]>([]); const [total, setTotal] = useState(0); const [error, setError] = useState<string | null>(null); const [rev, setRev] = useState<EventoPersonal | null>(null);
  const cargar = useCallback(() => { apiSup.historial(persona, null, 50).then((r) => { setEv(r.eventos); setTotal(r.total); setError(null); }).catch((e) => setError(textoError(e).texto)); }, [persona]);
  useEffect(() => { cargar(); }, [cargar]);
  async function mas() { try { const r = await apiSup.historial(persona, ev[ev.length - 1]?.id ?? null, 50); setEv((x) => [...x, ...r.eventos]); } catch (e) { setError(textoError(e).texto); } }
  const inverso = (e: EventoPersonal): TipoCambio | null => (e.tipo_evento === "asignar_actividad" ? "quitar_actividad" : e.tipo_evento === "quitar_actividad" ? "asignar_actividad" : e.tipo_evento === "activar_aseo" ? "desactivar_aseo" : e.tipo_evento === "desactivar_aseo" ? "activar_aseo" : null);
  return (
    <section className="td-seccion" aria-labelledby="as-his-tit">
      <div className="td-cab"><div><h2 id="as-his-tit">Historial de cambios{persona ? ` · ${nombreCorto(persona)}` : ""}</h2><p className="td-sub">Nada se borra. «Revertir» crea un evento nuevo que deja la actividad o el estado como antes (el cargo se corrige guardando otro).</p></div>
        <button type="button" className="td-boton-sec" onClick={onVolver}>← Volver al personal</button></div>
      {error ? <div className="td-aviso td-aviso-error" role="alert">{error}</div> : null}
      <div className="td-historial"><ul className="td-eventos">
        {ev.length === 0 ? <li className="td-vacio">Sin cambios registrados</li> : null}
        {ev.map((e) => (<li key={e.id}><strong>{TEXTO_EV[e.tipo_evento]}{e.actividad ? ` «${nombreAct(e.actividad)}»` : ""}{e.cargo ? ` «${e.cargo}»` : ""}</strong> · {e.persona_nombre ?? nombreCorto(e.persona)} · {fmtInstanteBogota(e.creado_en)} · por {e.autor_nombre ?? nombreCorto(e.autor)}{e.motivo ? ` · ${e.motivo}` : ""}
          {e.vigente && inverso(e) ? <> <button type="button" className="td-enlace" onClick={() => setRev(e)}>Revertir</button></> : null}</li>))}</ul>
        {ev.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={() => void mas()}>Cargar más ({ev.length} de {total})</button></div> : null}</div>
      {rev ? <DialogoMotivo titulo="Revertir el cambio" texto={`Se creará un evento nuevo que deshace «${TEXTO_EV[rev.tipo_evento]}${rev.actividad ? ` ${nombreAct(rev.actividad)}` : ""}» de ${rev.persona_nombre ?? nombreCorto(rev.persona)}.`} rotulo="Motivo" min={10} max={300} boton="Revertir" onCerrar={() => setRev(null)}
        onConfirmar={async (m) => { try { await apiSup.cambiar(rev.persona, inverso(rev)!, { ...(rev.actividad ? { actividad: rev.actividad } : {}), motivo: m }); setRev(null); onHecho("Cambio revertido."); cargar(); } catch (e) { throw new Error(textoError(e).texto); } }} /> : null}
    </section>
  );
}
