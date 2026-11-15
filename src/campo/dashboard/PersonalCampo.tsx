import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiRev, textoError, type EventoPersonal, type PersonaCampo, type PersonalResp } from "./apiRevision";
import { fmtInstante } from "./formatoRevision";

// «Supervisión y dashboard» · Personal (pasada 14/11). Personas activas con permiso de Formularios de campo o del acta: qué formularios puede llenar cada una, su cargo y el historial.
// Sin asignación, la persona puede llenar todos los formularios activos. En este corte la asignación SOLO SE REGISTRA: no bloquea la captura (lo decide el servidor, que también decide quién edita).
// Cada cambio es un evento (quién, cuándo y por qué) y se puede revertir; nada se borra. Nombres de formularios, personas y permisos salen del servidor.
type Dialogo = { tipo: "editar"; p: PersonaCampo } | { tipo: "revertir"; e: EventoPersonal };
const quien = (p: { nombre: string | null; email?: string; persona?: string }) => p.nombre ?? (p.email ?? p.persona ?? "").split("@")[0];
const permisos = (p: PersonaCampo) => [p.permisos.campo && "Formularios de campo", p.permisos.dashboard_campo && "Supervisión de campo", p.permisos.acta && "Acta", p.permisos.dashboard_acta && "Supervisión de actas"].filter(Boolean).join(" · ");

export function PersonalCampo() {
  const [buscar, setBuscar] = useState("");
  const [datos, setDatos] = useState<PersonalResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [dlg, setDlg] = useState<Dialogo | null>(null);
  const [histDe, setHistDe] = useState<string>("");        // "" = todas las personas
  const [versionHist, setVersionHist] = useState(0);
  const version = useRef(0);

  const cargar = useCallback(async () => {
    const v = ++version.current;
    try { const r = await apiRev.personal(buscar); if (v === version.current) { setDatos(r); setError(null); } }
    catch (e) { if (v === version.current) setError(textoError(e).texto); }
  }, [buscar]);
  useEffect(() => { const t = setTimeout(() => void cargar(), 250); return () => clearTimeout(t); }, [cargar]);
  const nombreForm = useMemo(() => new Map((datos?.formularios ?? []).map((f) => [f.clave, f.nombre])), [datos]);
  const hecho = (t: string) => { setDlg(null); setAviso(t); setVersionHist((x) => x + 1); void cargar(); };
  const editar = datos?.puede_editar === true;

  return (
    <section className="rv-seccion" aria-labelledby="rv-per-tit">
      <div>
        <h2 id="rv-per-tit">Personal</h2>
        <p className="rv-sub">Personas activas con permiso de Formularios de campo o del acta. <strong>Sin asignación pueden llenar todos los formularios activos.</strong> Por ahora la asignación solo se registra: no bloquea la captura.</p>
      </div>
      <div className="rv-per-cajitas">
        {editar ? <div className="rv-per-cajita"><strong>Usted puede:</strong> fijar el cargo y elegir los formularios de cada persona. Cada cambio queda con quién, cuándo y por qué, y se puede revertir.</div>
          : <div className="rv-per-cajita"><strong>Solo el administrador puede editar.</strong> Usted ve el personal, sus formularios, su cargo y el historial.</div>}
      </div>
      <label className="rv-campo rv-per-buscar">Buscar persona<input type="text" placeholder="Nombre o correo" value={buscar} maxLength={80} onChange={(e) => setBuscar(e.target.value)} /></label>
      {aviso ? <div className="rv-aviso rv-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => void cargar()}>Reintentar</button></div> : null}
      {!datos && !error ? <p className="rv-sub" role="status">Cargando el personal…</p> : null}
      {datos && datos.personas.length === 0 ? <div className="rv-vacio">No hay personas con permiso de Formularios de campo o del acta{buscar.trim() ? " que coincidan con la búsqueda" : ""}.</div> : null}
      <ul className="rv-per-lista">
        {(datos?.personas ?? []).map((p) => (
          <li key={p.email} className="rv-per-tarjeta">
            <div className="rv-per-cab">
              <div><strong>{quien(p)}</strong><div className="rv-tenue">{p.email}</div></div>
              <span className={`rv-marca ${p.perfil === "supervisor" ? "rv-marca-info" : "rv-marca-gris"}`}>{p.perfil === "supervisor" ? "Supervisor" : "Operario"}</span>
            </div>
            <dl className="rv-per-dl">
              <dt>Cargo</dt><dd>{p.cargo ?? <span className="rv-tenue">Sin cargo registrado</span>}</dd>
              <dt>Formularios</dt>
              <dd>{p.sin_asignacion ? <span className="rv-per-todos">Todos los activos (sin asignación)</span>
                : <span className="rv-per-chips">{p.formularios.map((f) => <span key={f} className="rv-per-chip">{nombreForm.get(f) ?? f}</span>)}</span>}</dd>
              <dt>Permisos</dt><dd className="rv-tenue">{permisos(p)}</dd>
            </dl>
            <div className="rv-botones">
              {editar ? <button type="button" className="rv-boton-sec" onClick={() => { setAviso(null); setDlg({ tipo: "editar", p }); }}>Editar</button> : null}
              <button type="button" className="rv-enlace" onClick={() => setHistDe(p.email)}>Ver su historial</button>
            </div>
          </li>
        ))}
      </ul>
      <Historial personas={datos?.personas ?? []} persona={histDe} onPersona={setHistDe} version={versionHist} puedeRevertir={editar} onRevertir={(e) => { setAviso(null); setDlg({ tipo: "revertir", e }); }} />
      {dlg?.tipo === "editar" && datos ? <DialogoEditar p={dlg.p} datos={datos} onHecho={hecho} onCancelar={() => setDlg(null)} /> : null}
      {dlg?.tipo === "revertir" ? <DialogoRevertir e={dlg.e} onHecho={hecho} onCancelar={() => setDlg(null)} /> : null}
    </section>
  );
}

function DialogoEditar({ p, datos, onHecho, onCancelar }: { p: PersonaCampo; datos: PersonalResp; onHecho: (t: string) => void; onCancelar: () => void }) {
  const [cargo, setCargo] = useState(p.cargo ?? "");
  const [marcados, setMarcados] = useState<Set<string>>(new Set(p.formularios));
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const quitar = p.formularios.filter((f) => !marcados.has(f));
  const asignar = [...marcados].filter((f) => !p.formularios.includes(f));
  const cambiaCargo = cargo.trim() !== (p.cargo ?? "") && cargo.trim().length > 0;
  const cargoMal = cargo.trim().length > 0 && (cargo.trim().length < 2 || cargo.trim().length > 80);
  const motivoMal = quitar.length > 0 && (motivo.trim().length < 10 || motivo.trim().length > 300);
  const nada = !cambiaCargo && quitar.length === 0 && asignar.length === 0;
  const alternar = (c: string) => setMarcados((m) => { const n = new Set(m); if (n.has(c)) n.delete(c); else n.add(c); return n; });
  // Los grupos de formularios se muestran en el orden del servidor
  const grupos = useMemo(() => { const g = new Map<string, typeof datos.formularios>(); for (const f of datos.formularios) g.set(f.grupo, [...(g.get(f.grupo) ?? []), f]); return [...g.entries()]; }, [datos]);
  async function guardar() {
    if (enviando || nada || cargoMal || motivoMal) return;
    setEnviando(true); setError(null);
    let hechos = 0;
    try {
      if (cambiaCargo) { await apiRev.personalCambiar({ persona: p.email, tipo: "fijar_cargo", cargo: cargo.trim() }); hechos++; }
      for (const f of asignar) { await apiRev.personalCambiar({ persona: p.email, tipo: "asignar_formulario", formulario: f }); hechos++; }
      for (const f of quitar) { await apiRev.personalCambiar({ persona: p.email, tipo: "quitar_formulario", formulario: f, motivo: motivo.trim() }); hechos++; }
      onHecho(`Cambios guardados para ${quien(p)} (${hechos}). Quedaron en el historial.`);
    } catch (e) {
      setError(`${textoError(e).texto}${hechos ? ` Se alcanzaron a guardar ${hechos} cambio(s); revise el historial.` : ""}`); setEnviando(false);
    }
  }
  return (
    <div className="rv-modal-fondo" onMouseDown={(e) => { if (e.target === e.currentTarget && !enviando) onCancelar(); }}>
      <div className="rv-modal" role="dialog" aria-modal="true" aria-label={`Editar a ${quien(p)}`}>
        <h3>Editar a {quien(p)}</h3>
        <label className="rv-campo">Cargo<input type="text" value={cargo} maxLength={80} onChange={(e) => setCargo(e.target.value)} placeholder="Ejemplo: Técnico de pérdidas" aria-invalid={cargoMal} /></label>
        <p className="rv-tenue">El cargo no se revierte: para corregirlo, escriba el correcto.</p>
        <fieldset className="rv-per-forms">
          <legend>Formularios que puede llenar</legend>
          <p className="rv-tenue">{marcados.size === 0 ? "Ninguno marcado: puede llenar todos los formularios activos." : `${marcados.size} marcado(s): solo estos quedan registrados como asignados.`}</p>
          {grupos.map(([g, fs]) => (
            <div key={g} className="rv-per-grupo">
              {fs.length > 1 || fs[0].nombre !== g ? <div className="rv-per-grupo-t">{g}</div> : null}
              {fs.map((f) => <label key={f.clave} className="rv-check"><input type="checkbox" checked={marcados.has(f.clave)} onChange={() => alternar(f.clave)} /> {f.nombre}</label>)}
            </div>
          ))}
        </fieldset>
        {quitar.length > 0 ? <label className="rv-campo">Motivo para quitar {quitar.length === 1 ? "el formulario" : `${quitar.length} formularios`} (de 10 a 300 caracteres)
          <textarea rows={2} maxLength={300} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></label> : null}
        {error ? <p className="rv-error" role="alert">{error}</p> : null}
        <div className="rv-botones">
          <button type="button" className="rv-boton" disabled={enviando || nada || cargoMal || motivoMal} onClick={() => void guardar()}>{enviando ? "Guardando…" : "Guardar"}</button>
          <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}

function Historial({ personas, persona, onPersona, version, puedeRevertir, onRevertir }: {
  personas: PersonaCampo[]; persona: string; onPersona: (p: string) => void; version: number; puedeRevertir: boolean; onRevertir: (e: EventoPersonal) => void;
}) {
  const [eventos, setEventos] = useState<EventoPersonal[] | null>(null);
  const [siguiente, setSiguiente] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const cargar = useCallback(async (mas: number | null) => {
    try {
      const r = await apiRev.historialPersonal({ persona: persona || undefined, despues_de: mas ?? undefined, limite: 50 });
      setEventos((ev) => (mas ? [...(ev ?? []), ...r.eventos] : r.eventos)); setSiguiente(r.siguiente); setError(null);
    } catch (e) { setError(textoError(e).texto); }
  }, [persona]);
  useEffect(() => { setEventos(null); void cargar(null); }, [cargar, version]);
  const texto = (e: EventoPersonal) => e.tipo_evento === "fijar_cargo" ? `Cargo: «${e.cargo}»` : `${e.tipo_evento === "asignar_formulario" ? "Asignó" : "Quitó"} «${e.formulario_nombre ?? e.formulario}»`;
  return (
    <div className="rv-per-hist">
      <h3 className="rv-h3">Historial</h3>
      <label className="rv-campo rv-per-buscar">Persona
        <select value={persona} onChange={(e) => onPersona(e.target.value)}>
          <option value="">Todas</option>
          {personas.map((p) => <option key={p.email} value={p.email}>{quien(p)}</option>)}
        </select>
      </label>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {eventos && eventos.length === 0 ? <div className="rv-vacio">Sin cambios registrados.</div> : null}
      <ol className="rv-per-eventos">
        {(eventos ?? []).map((e) => (
          <li key={e.id} className="rv-per-evento">
            <div className="rv-per-ev-cab"><strong>{texto(e)}</strong>{e.vigente ? <span className="rv-marca rv-marca-info">Vigente</span> : null}</div>
            <div className="rv-tenue">n.º {e.id} · {quien(e)} · {fmtInstante(e.creado_en)} · por {e.autor}</div>
            {e.motivo ? <div className="rv-motivo">Motivo: {e.motivo}</div> : null}
            {puedeRevertir && e.vigente && e.tipo_evento !== "fijar_cargo" ? <button type="button" className="rv-enlace" onClick={() => onRevertir(e)}>Revertir</button> : null}
          </li>
        ))}
      </ol>
      {siguiente ? <button type="button" className="rv-boton-sec" onClick={() => void cargar(siguiente)}>Ver más</button> : null}
    </div>
  );
}

function DialogoRevertir({ e, onHecho, onCancelar }: { e: EventoPersonal; onHecho: (t: string) => void; onCancelar: () => void }) {
  const quitar = e.tipo_evento === "asignar_formulario";      // revertir una asignación = quitarla (con motivo); revertir un retiro = volver a asignar
  const [motivo, setMotivo] = useState(`Reversión del cambio n.º ${e.id}`);
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const malo = quitar && (motivo.trim().length < 10 || motivo.trim().length > 300);
  async function aplicar() {
    if (enviando || malo) return; setEnviando(true); setError(null);
    try {
      await apiRev.personalCambiar({ persona: e.persona, tipo: quitar ? "quitar_formulario" : "asignar_formulario", formulario: e.formulario, motivo: quitar ? motivo.trim() : null });
      onHecho(`Cambio n.º ${e.id} revertido.`);
    } catch (x) { setError(textoError(x).texto); setEnviando(false); }
  }
  return (
    <div className="rv-modal-fondo" onMouseDown={(x) => { if (x.target === x.currentTarget && !enviando) onCancelar(); }}>
      <div className="rv-modal" role="dialog" aria-modal="true" aria-label={`Revertir el cambio n.º ${e.id}`}>
        <h3>Revertir el cambio n.º {e.id}</h3>
        <p className="rv-sub">{quitar ? `Se quitará «${e.formulario_nombre ?? e.formulario}» a ${quien(e)}.` : `Se volverá a asignar «${e.formulario_nombre ?? e.formulario}» a ${quien(e)}.`} El cambio original se conserva en el historial.</p>
        {quitar ? <label className="rv-campo">Motivo (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={motivo} onChange={(x) => setMotivo(x.target.value)} /></label> : null}
        {error ? <p className="rv-error" role="alert">{error}</p> : null}
        <div className="rv-botones">
          <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => void aplicar()}>{enviando ? "Revirtiendo…" : "Revertir"}</button>
          <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}
