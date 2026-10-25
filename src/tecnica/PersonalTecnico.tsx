import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiDash, textoError, type Catalogo, type EventoPersonal, type Persona, type PersonalResp } from "./apiDashboard";
import { fmtInstante } from "./formato";
import { supabase } from "../lib/supabase";

// Dashboard técnico · «Personal técnico». Formularios, perfiles y nombres salen del servidor. Los cambios son eventos (quién, cuándo, por qué) y se pueden revertir.
const ROTULO_PERFIL = { operador: "Operador", dual: "Dual", supervisor: "Supervisor" } as const;
type Dialogo =
  | { tipo: "formularios"; p: Persona }
  | { tipo: "estado"; p: Persona }
  | { tipo: "revertir"; e: EventoPersonal };

export function PersonalTecnico({ catalogo }: { catalogo: Catalogo }) {
  const [buscar, setBuscar] = useState("");
  const [conSup, setConSup] = useState(false);
  const [datos, setDatos] = useState<PersonalResp | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [verHistorial, setVerHistorial] = useState<string | null | undefined>(undefined);   // undefined = cerrado · null = general · correo = de esa persona
  const [versionHist, setVersionHist] = useState(0);
  const version = useRef(0);

  const cargar = useCallback(async () => {
    const v = ++version.current; setCargando(true);
    try { const r = await apiDash.personal(buscar.trim(), conSup); if (v === version.current) { setDatos(r); setError(null); } }
    catch (e) { if (v === version.current) setError(textoError(e)); } finally { if (v === version.current) setCargando(false); }
  }, [buscar, conSup]);
  useEffect(() => { const t = setTimeout(() => void cargar(), 250); return () => clearTimeout(t); }, [cargar]);

  const nombreForm = useMemo(() => new Map(catalogo.formularios.map((x) => [x.clave, x.nombre])), [catalogo]);
  const hecho = (texto: string) => { setDialogo(null); setAviso(texto); setVersionHist((x) => x + 1); void cargar(); };

  return (
    <section className="td-seccion" aria-labelledby="td-per-tit">
      <div className="td-cab">
        <div>
          <h2 id="td-per-tit">Personal técnico</h2>
          <p className="td-sub">Aquí aparecen los usuarios activos con perfil operador o dual. Los administradores no figuran{conSup ? "" : " (ni, por ahora, los supervisores)"}.</p>
        </div>
        <div className="td-descargas">
          <label className="td-campo">Buscar persona<input id="buscar" type="text" placeholder="Nombre o correo" value={buscar} maxLength={80} onChange={(e) => setBuscar(e.target.value)} /></label>
          <label className="td-check"><input type="checkbox" checked={conSup} onChange={(e) => setConSup(e.target.checked)} /> Incluir supervisores</label>
        </div>
      </div>
      <div className="td-cajitas">
        <div className="td-cajita"><strong>Usted puede:</strong> elegir los formularios de cada persona y desactivar su acceso al área técnica.</div>
        <div className="td-cajita"><strong>Solo el administrador puede:</strong> dar o quitar el acceso al Dashboard técnico, desde Administración general.</div>
      </div>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <div className="td-aviso td-aviso-error" role="alert">{error.texto}{" "}{error.sesion ? <button type="button" className="td-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="td-enlace" onClick={() => void cargar()}>Reintentar</button>}</div> : null}

      <div className="td-tabla-caja">
        <table className="td-tabla td-tabla-personal">
          <caption className="td-solo-lectores">Personal técnico</caption>
          <thead><tr>
            <th>Persona</th><th>Perfil</th>
            {(datos?.formularios ?? catalogo.formularios).map((x) => <th key={x.clave} className="td-centro td-vertical">{x.nombre}</th>)}
            <th>Dashboard técnico</th><th>Estado en Técnica</th>
          </tr></thead>
          <tbody>
            {(datos?.personas ?? []).map((p) => (
              <tr key={p.email} className={p.activo_tecnica ? undefined : "td-excluida"}>
                <td>
                  <div className="td-nombre">{p.nombre ?? p.email}</div>
                  {p.nombre ? <div className="td-chico">{p.email}</div> : <div className="td-chico">Sin nombre registrado</div>}
                  {p.captura_todo ? <div className="td-chico">Captura todos los formularios por su permiso de Dashboard.</div> : null}
                  <div className="td-acciones"><button type="button" className="td-enlace" onClick={() => setDialogo({ tipo: "formularios", p })}>Editar formularios</button>
                    <button type="button" className="td-enlace" onClick={() => setVerHistorial(p.email)}>Historial</button></div>
                </td>
                <td>{ROTULO_PERFIL[p.perfil]}</td>
                {(datos?.formularios ?? []).map((x) => { const si = p.formularios.includes(x.clave); return <td key={x.clave} className={`td-centro ${si ? "td-si" : "td-no"}`}>{si ? "Sí" : "No"}</td>; })}
                <td><span className={`td-marca ${p.dashboard_tecnico ? "td-marca-ok" : "td-marca-gris"}`}>{p.dashboard_tecnico ? "Con acceso" : "Sin acceso"}</span></td>
                <td><div className="td-estado"><span className={`td-marca ${p.activo_tecnica ? "td-marca-ok" : "td-marca-gris"}`}>{p.activo_tecnica ? "Activo" : "Desactivado en Técnica"}</span>
                  <button type="button" className="td-boton-sec td-corto" onClick={() => setDialogo({ tipo: "estado", p })}>{p.activo_tecnica ? "Desactivar en Técnica" : "Reactivar en Técnica"}</button></div></td>
              </tr>
            ))}
            {!cargando && (datos?.personas.length ?? 0) === 0 && !error ? <tr><td colSpan={4 + (datos?.formularios.length ?? 0)} className="td-vacio">{buscar ? "Ninguna persona coincide con la búsqueda." : "No hay personal técnico para mostrar."}</td></tr> : null}
          </tbody>
        </table>
      </div>
      {cargando && !datos ? <p className="td-sub" role="status">Cargando…</p> : null}

      <div className="td-cajitas">
        <div className="td-cajita"><strong>Editar formularios de una persona</strong><br />Al pulsar «Editar formularios» se abre la lista con una casilla por formulario. El cambio queda con quién, cuándo y por qué, y se puede revertir desde el historial.</div>
        <div className="td-cajita"><strong>Desactivar en Técnica</strong><br />Bloquea al instante la captura y la vista del Dashboard. La cuenta sigue activa en el resto del geoportal y se puede reactivar.</div>
      </div>

      <div className="td-barra"><h3 className="td-h3">Historial de cambios</h3>
        {verHistorial === undefined ? <button type="button" className="td-boton-sec td-corto" onClick={() => setVerHistorial(null)}>Ver historial general</button> : <button type="button" className="td-boton-sec td-corto" onClick={() => setVerHistorial(undefined)}>Ocultar historial</button>}</div>
      {verHistorial !== undefined ? <Historial persona={verHistorial} version={versionHist} nombreForm={nombreForm} onCambiarPersona={setVerHistorial} personas={datos?.personas ?? []} onRevertir={(e) => setDialogo({ tipo: "revertir", e })} /> : null}

      {dialogo?.tipo === "formularios" ? <DialogoFormularios p={dialogo.p} formularios={datos?.formularios ?? []} onCerrar={() => setDialogo(null)} onHecho={hecho} onRefrescar={() => { setVersionHist((x) => x + 1); void cargar(); }} /> : null}
      {dialogo?.tipo === "estado" ? <DialogoEstado p={dialogo.p} onCerrar={() => setDialogo(null)} onHecho={hecho} /> : null}
      {dialogo?.tipo === "revertir" ? <DialogoRevertir e={dialogo.e} nombreForm={nombreForm} onCerrar={() => setDialogo(null)} onHecho={hecho} /> : null}
    </section>
  );
}

function Fondo({ titulo, onCerrar, ocupado, children }: { titulo: string; onCerrar: () => void; ocupado: boolean; children: React.ReactNode }) {
  useEffect(() => { const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && !ocupado) onCerrar(); }; window.addEventListener("keydown", esc); return () => window.removeEventListener("keydown", esc); }, [onCerrar, ocupado]);
  return <div className="td-fondo" role="presentation"><div className="td-dialogo" role="dialog" aria-modal="true" aria-labelledby="td-dlg-tit"><h3 id="td-dlg-tit">{titulo}</h3>{children}</div></div>;
}
const quien = (p: { nombre: string | null; email: string }) => p.nombre ?? p.email;

function DialogoFormularios({ p, formularios, onCerrar, onHecho, onRefrescar }: { p: Persona; formularios: { clave: string; nombre: string }[]; onCerrar: () => void; onHecho: (t: string) => void; onRefrescar: () => void }) {
  const [marcados, setMarcados] = useState<Set<string>>(new Set(p.formularios));
  const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const aQuitar = p.formularios.filter((c) => !marcados.has(c)); const aDar = [...marcados].filter((c) => !p.formularios.includes(c));
  const motivoOk = aQuitar.length === 0 || motivo.trim().length >= 10;
  async function guardar() {
    if (ocupado || (aQuitar.length === 0 && aDar.length === 0) || !motivoOk) return;
    setOcupado(true); setError(null); const hechos: string[] = [];
    try {
      for (const c of aDar) { await apiDash.asignar(p.email, c, motivo.trim()); hechos.push(c); }
      for (const c of aQuitar) { await apiDash.quitar(p.email, c, motivo.trim()); hechos.push(c); }
      onHecho(`Formularios de ${quien(p)} actualizados (${aDar.length} asignados, ${aQuitar.length} quitados).`);
    } catch (e) {
      setError(`${textoError(e).texto}${hechos.length ? ` Se alcanzaron a aplicar ${hechos.length} cambio(s) antes del fallo; revise la lista.` : ""}`); setOcupado(false);
      if (hechos.length) onRefrescar();
    }
  }
  return (
    <Fondo titulo={`Editar formularios · ${quien(p)}`} onCerrar={onCerrar} ocupado={ocupado}>
      {p.captura_todo ? <p className="td-sub">Esta persona tiene permiso de Dashboard técnico: captura todos los formularios sin que se le asignen. Las casillas solo afectan si ese permiso se retira.</p> : null}
      <fieldset className="td-casillas"><legend>Formularios que puede diligenciar</legend>
        {formularios.map((x) => <label key={x.clave} className="td-check"><input type="checkbox" checked={marcados.has(x.clave)} disabled={ocupado} onChange={(e) => { const n = new Set(marcados); if (e.target.checked) n.add(x.clave); else n.delete(x.clave); setMarcados(n); }} /> {x.nombre}</label>)}
      </fieldset>
      <label className="td-campo td-ancho">Motivo {aQuitar.length ? "(obligatorio al quitar, mínimo 10 caracteres)" : "(opcional)"}<textarea rows={2} value={motivo} maxLength={1000} onChange={(e) => setMotivo(e.target.value)} disabled={ocupado} /></label>
      {error ? <p className="td-error" role="alert">{error}</p> : null}
      <div className="td-dialogo-acciones"><button type="button" className="td-boton" onClick={guardar} disabled={ocupado || !motivoOk || (aQuitar.length === 0 && aDar.length === 0)}>{ocupado ? "Guardando…" : `Guardar (${aDar.length} por dar, ${aQuitar.length} por quitar)`}</button>
        <button type="button" className="td-boton-sec" onClick={onCerrar} disabled={ocupado}>Cancelar</button></div>
    </Fondo>
  );
}

function DialogoEstado({ p, onCerrar, onHecho }: { p: Persona; onCerrar: () => void; onHecho: (t: string) => void }) {
  const desactiva = p.activo_tecnica; const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const ok = !desactiva || motivo.trim().length >= 10;
  async function confirmar() { if (!ok || ocupado) return; setOcupado(true); setError(null);
    try { await apiDash.estado(p.email, !desactiva, motivo.trim()); onHecho(`Se ${desactiva ? "desactivó" : "reactivó"} el acceso a Técnica de ${quien(p)}. La cuenta sigue activa en el resto del geoportal.`); }
    catch (e) { setError(textoError(e).texto); setOcupado(false); } }
  return (
    <Fondo titulo={`${desactiva ? "Desactivar" : "Reactivar"} en Técnica · ${quien(p)}`} onCerrar={onCerrar} ocupado={ocupado}>
      <p className="td-sub">{desactiva ? "Bloquea al instante la captura y la vista del Dashboard de esta persona. Su cuenta sigue activa en el resto del geoportal y se puede reactivar." : "Le devuelve el acceso a Técnica con los formularios que tenía asignados."}</p>
      <label className="td-campo td-ancho">Motivo {desactiva ? "(obligatorio, mínimo 10 caracteres)" : "(opcional)"}<textarea rows={2} value={motivo} maxLength={1000} onChange={(e) => setMotivo(e.target.value)} disabled={ocupado} /></label>
      {error ? <p className="td-error" role="alert">{error}</p> : null}
      <div className="td-dialogo-acciones"><button type="button" className="td-boton" onClick={confirmar} disabled={!ok || ocupado}>{ocupado ? "Guardando…" : desactiva ? "Desactivar en Técnica" : "Reactivar en Técnica"}</button>
        <button type="button" className="td-boton-sec" onClick={onCerrar} disabled={ocupado}>Cancelar</button></div>
    </Fondo>
  );
}

const textoEvento = (e: EventoPersonal, nombreForm: Map<string, string>) =>
  e.tipo_evento === "asignar_formulario" ? `Asignó el formulario «${nombreForm.get(e.formulario ?? "") ?? e.formulario}»`
  : e.tipo_evento === "quitar_formulario" ? `Quitó el formulario «${nombreForm.get(e.formulario ?? "") ?? e.formulario}»`
  : e.tipo_evento === "desactivar_tecnica" ? "Desactivó en Técnica" : "Reactivó en Técnica";

function Historial({ persona, version, nombreForm, personas, onCambiarPersona, onRevertir }: { persona: string | null; version: number; nombreForm: Map<string, string>; personas: Persona[]; onCambiarPersona: (p: string | null) => void; onRevertir: (e: EventoPersonal) => void }) {
  const [eventos, setEventos] = useState<EventoPersonal[]>([]); const [total, setTotal] = useState(0); const [error, setError] = useState<string | null>(null); const [cargando, setCargando] = useState(true);
  useEffect(() => { let vivo = true; setCargando(true);
    apiDash.historial(persona, null, 50).then((r) => { if (vivo) { setEventos(r.eventos); setTotal(r.total); setError(null); } }).catch((e) => { if (vivo) setError(textoError(e).texto); }).finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; }; }, [persona, version]);
  async function mas() { try { const r = await apiDash.historial(persona, eventos[eventos.length - 1]?.id ?? null, 50); setEventos((x) => [...x, ...r.eventos]); } catch (e) { setError(textoError(e).texto); } }
  return (
    <div className="td-historial">
      <label className="td-campo">Persona<select value={persona ?? ""} onChange={(e) => onCambiarPersona(e.target.value || null)}><option value="">Todas</option>{personas.map((p) => <option key={p.email} value={p.email}>{quien(p)}</option>)}{persona && !personas.some((p) => p.email === persona) ? <option value={persona}>{persona}</option> : null}</select></label>
      {error ? <p className="td-error" role="alert">{error}</p> : null}
      <ul className="td-eventos">
        {eventos.map((e) => (
          <li key={e.id}><div><strong>{textoEvento(e, nombreForm)}</strong> · {persona ? "" : <>{quien({ nombre: e.persona_nombre, email: e.persona })} · </>}<span className="td-chico">{fmtInstante(e.creado_en)} por {quien({ nombre: e.autor_nombre, email: e.autor })}</span></div>
            <div className="td-chico">{e.motivo ? `Motivo: ${e.motivo}` : "Sin motivo registrado"}</div>
            {e.vigente ? <button type="button" className="td-enlace" onClick={() => onRevertir(e)}>Revertir este cambio…</button> : <span className="td-chico">Ya reemplazado por un cambio posterior</span>}</li>
        ))}
        {!cargando && eventos.length === 0 ? <li className="td-vacio">Todavía no hay cambios registrados.</li> : null}
      </ul>
      {eventos.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={mas}>Cargar más ({total - eventos.length} restantes)</button></div> : null}
    </div>
  );
}

function DialogoRevertir({ e, nombreForm, onCerrar, onHecho }: { e: EventoPersonal; nombreForm: Map<string, string>; onCerrar: () => void; onHecho: (t: string) => void }) {
  const [motivo, setMotivo] = useState(`Reversión del cambio n.º ${e.id}`); const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const ok = motivo.trim().length >= 10;
  async function confirmar() { if (!ok || ocupado) return; setOcupado(true); setError(null);
    try {
      if (e.tipo_evento === "asignar_formulario") await apiDash.quitar(e.persona, e.formulario ?? "", motivo.trim());
      else if (e.tipo_evento === "quitar_formulario") await apiDash.asignar(e.persona, e.formulario ?? "", motivo.trim());
      else await apiDash.estado(e.persona, e.tipo_evento === "desactivar_tecnica", motivo.trim());
      onHecho(`Se revirtió el cambio n.º ${e.id}.`);
    } catch (x) { setError(textoError(x).texto); setOcupado(false); } }
  return (
    <Fondo titulo="Revertir un cambio" onCerrar={onCerrar} ocupado={ocupado}>
      <p className="td-sub">Se hará lo contrario de: <strong>{textoEvento(e, nombreForm)}</strong> ({quien({ nombre: e.persona_nombre, email: e.persona })}). El cambio original no se borra: queda un nuevo cambio en el historial.</p>
      <label className="td-campo td-ancho">Motivo (obligatorio, mínimo 10 caracteres)<textarea rows={2} value={motivo} maxLength={1000} onChange={(x) => setMotivo(x.target.value)} disabled={ocupado} /></label>
      {error ? <p className="td-error" role="alert">{error}</p> : null}
      <div className="td-dialogo-acciones"><button type="button" className="td-boton" onClick={confirmar} disabled={!ok || ocupado}>{ocupado ? "Guardando…" : "Revertir"}</button><button type="button" className="td-boton-sec" onClick={onCerrar} disabled={ocupado}>Cancelar</button></div>
    </Fondo>
  );
}
