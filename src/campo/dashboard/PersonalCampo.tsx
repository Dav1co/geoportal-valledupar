import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiRev, textoError, type ActividadPersona, type EventoPersonal, type PersonaActividad, type PersonaCampo, type PersonalResp, type PuedePersonal } from "./apiRevision";
import { fmtInstante } from "./formatoRevision";

// «Supervisión y dashboard» · Personal (pasada 14/11; área, cuadrilla y actividades desde el 21-nov, paquete (a) del Code A). Personas activas con permiso de Formularios de campo o del acta:
// su área, cargo, cuadrilla, actividades (las de su cuadrilla y las propias) y los formularios que puede llenar, con el historial. Las actividades y los formularios SOLO SE REGISTRAN:
// no bloquean la captura. Qué puede cambiar quien consulta lo dice el servidor campo por campo (`puede`); nadie cambia su propia ficha (`propia`). Cada cambio es un evento con quién,
// cuándo y por qué; nada se borra. Un servidor anterior al 21-nov no manda `puede` ni las columnas nuevas: la pantalla se ve como antes (edita el administrador: cargo y formularios).
type Dialogo = { tipo: "editar"; p: PersonaCampo } | { tipo: "revertir"; e: EventoPersonal };
const quien = (p: { nombre: string | null; email?: string; persona?: string | null }) => p.nombre ?? (p.email ?? p.persona ?? "").split("@")[0];
const permisos = (p: PersonaCampo) => [p.permisos.campo && "Formularios de campo", p.permisos.dashboard_campo && "Supervisión de campo", p.permisos.acta && "Acta", p.permisos.dashboard_acta && "Supervisión de actas"].filter(Boolean).join(" · ");
const NADA: PuedePersonal = { cargo: false, area: false, cuadrilla: false, cuadrillas: false, actividades: false, formularios: false, catalogos: false };
/** Lo que puede cambiar quien consulta. Sin `puede` (servidor anterior), el administrador fija el cargo y los formularios, como antes. */
export function puedeDe(d: PersonalResp | null, soloLectura = false): PuedePersonal {
  if (!d || soloLectura) return NADA;
  return d.puede ?? { ...NADA, cargo: d.puede_editar, formularios: d.puede_editar };
}
const ORIGEN: Record<ActividadPersona["origen"], string> = { cuadrilla: "de la cuadrilla", propia: "propia", ambas: "propia y de la cuadrilla" };
const motivoMalo = (m: string) => m.trim().length < 10 || m.trim().length > 300;

export function PersonalCampo({ soloLectura = false }: { soloLectura?: boolean }) {
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
  const puede = puedeDe(datos, soloLectura);
  const nuevo = !!datos?.puede;                              // servidor con área, cuadrilla y actividades
  const edita = Object.entries(puede).some(([k, v]) => v && k !== "cuadrillas" && k !== "catalogos");
  const lo = [puede.cargo && puede.area ? "fijar el área y el cargo" : puede.cargo ? "fijar el cargo" : puede.area ? "fijar el área" : null,
    puede.cuadrilla && "poner a cada persona en una cuadrilla", puede.actividades && "darle actividades propias", puede.formularios && "elegir sus formularios"].filter(Boolean) as string[];

  return (
    <section className="rv-seccion" aria-labelledby="rv-per-tit" data-testid="personal">
      <div>
        <h2 id="rv-per-tit">Personal</h2>
        <p className="rv-sub">Personas activas con permiso de Formularios de campo o del acta. <strong>Sin asignación pueden llenar todos los formularios activos.</strong> {nuevo ? "Por ahora las actividades y los formularios solo se registran: no bloquean la captura." : "Por ahora la asignación solo se registra: no bloquea la captura."}</p>
      </div>
      <div className="rv-per-cajitas">
        {edita ? <div className="rv-per-cajita"><strong>Usted puede:</strong> {lo.join(", ").replace(/, ([^,]*)$/, " y $1")}. Cada cambio queda con quién, cuándo y por qué{puede.formularios ? ", y los formularios se pueden revertir" : ""}.{nuevo ? " Nadie cambia su propia ficha." : ""}</div>
          : nuevo || soloLectura ? <div className="rv-per-cajita"><strong>Solo lectura.</strong> Usted ve el personal, su área, cargo, cuadrilla, actividades, formularios y el historial.</div>
          : <div className="rv-per-cajita"><strong>Solo el administrador puede editar.</strong> Usted ve el personal, sus formularios, su cargo y el historial.</div>}
      </div>
      <div className="rv-per-filtros">
        <label className="rv-campo rv-per-buscar">Buscar persona<input type="text" placeholder="Nombre o correo" value={buscar} maxLength={80} onChange={(e) => setBuscar(e.target.value)} /></label>
        {nuevo && (datos?.actividades ?? []).length ? <QuienPuede actividades={datos?.actividades ?? []} version={versionHist} /> : null}
      </div>
      {aviso ? <div className="rv-aviso rv-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => void cargar()}>Reintentar</button></div> : null}
      {!datos && !error ? <p className="rv-sub" role="status">Cargando el personal…</p> : null}
      {datos && datos.personas.length === 0 ? <div className="rv-vacio">No hay personas con permiso de Formularios de campo o del acta{buscar.trim() ? " que coincidan con la búsqueda" : ""}.</div> : null}
      <ul className="rv-per-lista">
        {(datos?.personas ?? []).map((p) => (
          <li key={p.email} className="rv-per-tarjeta" data-persona={p.email}>
            <div className="rv-per-cab">
              <div><strong>{quien(p)}</strong>{p.propia ? <span className="rv-marca rv-marca-gris rv-per-usted">Usted</span> : null}<div className="rv-tenue">{p.email}</div></div>
              <span className={`rv-marca ${p.perfil === "supervisor" ? "rv-marca-info" : "rv-marca-gris"}`}>{p.perfil === "supervisor" ? "Supervisor" : "Operario"}</span>
            </div>
            <dl className="rv-per-dl">
              {nuevo ? <><dt>Área</dt><dd data-dato="area">{p.area ? <>{p.area.nombre}{p.area.activa ? null : <span className="rv-per-desact"> (desactivada)</span>}</> : <span className="rv-tenue">Sin área</span>}</dd></> : null}
              <dt>Cargo</dt><dd>{p.cargo ?? <span className="rv-tenue">Sin cargo registrado</span>}</dd>
              {nuevo ? <><dt>Cuadrilla</dt><dd data-dato="cuadrilla">{p.cuadrilla ? <>{p.cuadrilla.nombre}{p.cuadrilla.activa === false ? <span className="rv-per-desact"> (desactivada)</span> : null}</> : <span className="rv-tenue">Sin cuadrilla</span>}</dd>
                <dt>Actividades</dt>
                <dd data-dato="actividades">{(p.actividades ?? []).length === 0 ? <span className="rv-tenue">Ninguna</span>
                  : <span className="rv-per-chips">{(p.actividades ?? []).map((a) => <span key={a.codigo} className={`rv-per-chip${a.activa ? "" : " rv-per-chip-off"}`} data-actividad={a.codigo} data-origen={a.origen}>{a.nombre} <small className="rv-per-origen">· {ORIGEN[a.origen]}{a.activa ? "" : " · desactivada"}</small></span>)}</span>}</dd></> : null}
              <dt>Formularios</dt>
              <dd>{p.sin_asignacion ? <span className="rv-per-todos">Todos los activos (sin asignación)</span>
                : <span className="rv-per-chips">{p.formularios.map((f) => <span key={f} className="rv-per-chip">{nombreForm.get(f) ?? f}</span>)}</span>}</dd>
              <dt>Permisos</dt><dd className="rv-tenue">{permisos(p)}</dd>
            </dl>
            <div className="rv-botones">
              {edita && !p.propia ? <button type="button" className="rv-boton-sec" onClick={() => { setAviso(null); setDlg({ tipo: "editar", p }); }}>Editar</button> : null}
              {edita && p.propia ? <span className="rv-tenue">Es su ficha: no la puede cambiar.</span> : null}
              <button type="button" className="rv-enlace" onClick={() => setHistDe(p.email)}>Ver su historial</button>
            </div>
          </li>
        ))}
      </ul>
      <Historial personas={datos?.personas ?? []} persona={histDe} onPersona={setHistDe} version={versionHist} puedeRevertir={puede.formularios} onRevertir={(e) => { setAviso(null); setDlg({ tipo: "revertir", e }); }} />
      {dlg?.tipo === "editar" && datos ? <DialogoEditar p={dlg.p} datos={datos} puede={puede} onHecho={hecho} onCancelar={() => setDlg(null)} /> : null}
      {dlg?.tipo === "revertir" ? <DialogoRevertir e={dlg.e} onHecho={hecho} onCancelar={() => setDlg(null)} /> : null}
    </section>
  );
}

/** «Quién puede hacer…»: las personas que tienen una actividad, por su cuadrilla o como propia (ruta personal_actividad). Es la consulta que usarán SCRR, lectura y reparto. */
function QuienPuede({ actividades, version }: { actividades: { codigo: string; nombre: string }[]; version: number }) {
  const [act, setAct] = useState("");
  const [res, setRes] = useState<PersonaActividad[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    if (!act) { setRes(null); setError(null); return; }
    let vivo = true; setRes(null); setError(null);
    apiRev.personalActividad(act).then((r) => { if (vivo) setRes(r.personas); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; };
  }, [act, version]);                                        // se vuelve a pedir después de cada cambio guardado
  const nombre = actividades.find((a) => a.codigo === act)?.nombre ?? act;
  return (
    <div className="rv-per-quien" data-testid="quien-puede">
      <label className="rv-campo rv-per-buscar">Quién puede hacer…
        <select value={act} onChange={(e) => setAct(e.target.value)}>
          <option value="">Elija una actividad</option>
          {actividades.map((a) => <option key={a.codigo} value={a.codigo}>{a.nombre}</option>)}
        </select>
      </label>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {act && !res && !error ? <p className="rv-sub" role="status">Buscando…</p> : null}
      {res ? (res.length === 0 ? <div className="rv-vacio">Nadie tiene la actividad «{nombre}».</div> : (
        <div className="rv-per-quien-res" role="status">
          <strong>{res.length === 1 ? "1 persona puede" : `${res.length} personas pueden`} hacer «{nombre}»:</strong>
          <ul>{res.map((p) => <li key={p.email} data-quien={p.email}>{quien(p)} <span className="rv-tenue">· {p.origen === "propia" ? "propia" : p.origen === "cuadrilla" ? `cuadrilla ${p.cuadrilla?.nombre ?? ""}` : `propia y cuadrilla ${p.cuadrilla?.nombre ?? ""}`}</span></li>)}</ul>
        </div>)) : null}
    </div>
  );
}

function DialogoEditar({ p, datos, puede, onHecho, onCancelar }: { p: PersonaCampo; datos: PersonalResp; puede: PuedePersonal; onHecho: (t: string) => void; onCancelar: () => void }) {
  const [cargo, setCargo] = useState(p.cargo ?? "");
  const [area, setArea] = useState(p.area?.codigo ?? "");
  const [cuadrilla, setCuadrilla] = useState<string>(p.cuadrilla ? String(p.cuadrilla.id) : "");
  const propiasAntes = useMemo(() => (p.actividades ?? []).filter((a) => a.origen !== "cuadrilla").map((a) => a.codigo), [p]);
  const [propias, setPropias] = useState<Set<string>>(new Set(propiasAntes));
  const [marcados, setMarcados] = useState<Set<string>>(new Set(p.formularios));
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const quitar = puede.formularios ? p.formularios.filter((f) => !marcados.has(f)) : [];
  const asignar = puede.formularios ? [...marcados].filter((f) => !p.formularios.includes(f)) : [];
  const actQuitar = puede.actividades ? propiasAntes.filter((a) => !propias.has(a)) : [];
  const actAsignar = puede.actividades ? [...propias].filter((a) => !propiasAntes.includes(a)) : [];
  const cambiaCargo = puede.cargo && cargo.trim() !== (p.cargo ?? "") && cargo.trim().length > 0;
  const cargoMal = puede.cargo && cargo.trim().length > 0 && (cargo.trim().length < 2 || cargo.trim().length > 80);
  const cambiaArea = puede.area && area !== "" && area !== (p.area?.codigo ?? "");
  const cuadAntes = p.cuadrilla ? String(p.cuadrilla.id) : "";
  const cambiaCuad = puede.cuadrilla && cuadrilla !== cuadAntes;
  const sacaOCambia = cambiaCuad && cuadAntes !== "";     // salir de una cuadrilla o pasar a otra exige motivo
  const pideMotivo = quitar.length > 0 || actQuitar.length > 0 || sacaOCambia;
  const motivoMal = pideMotivo && motivoMalo(motivo);
  const nada = !cambiaCargo && !cambiaArea && !cambiaCuad && quitar.length === 0 && asignar.length === 0 && actQuitar.length === 0 && actAsignar.length === 0;
  const alternar = (c: string) => setMarcados((m) => { const n = new Set(m); if (n.has(c)) n.delete(c); else n.add(c); return n; });
  const alternarAct = (c: string) => setPropias((m) => { const n = new Set(m); if (n.has(c)) n.delete(c); else n.add(c); return n; });
  // Los grupos de formularios se muestran en el orden del servidor
  const grupos = useMemo(() => { const g = new Map<string, typeof datos.formularios>(); for (const f of datos.formularios) g.set(f.grupo, [...(g.get(f.grupo) ?? []), f]); return [...g.entries()]; }, [datos]);
  // Actividades para marcar: las activas del catálogo, más las propias desactivadas que ya tiene (solo para poder quitarlas)
  const deCuadrilla = new Map((p.actividades ?? []).filter((a) => a.origen !== "propia").map((a) => [a.codigo, a]));
  const actOpciones = [...(datos.actividades ?? []).map((a) => ({ ...a, activa: true })), ...(p.actividades ?? []).filter((a) => !a.activa && a.origen !== "cuadrilla" && !(datos.actividades ?? []).some((x) => x.codigo === a.codigo))];
  async function guardar() {
    if (enviando || nada || cargoMal || motivoMal) return;
    setEnviando(true); setError(null);
    let hechos = 0; const m = motivo.trim();
    try {
      if (cambiaCargo) { await apiRev.personalCambiar({ persona: p.email, tipo: "fijar_cargo", cargo: cargo.trim() }); hechos++; }
      if (cambiaArea) { await apiRev.personalCambiar({ persona: p.email, tipo: "fijar_area", area }); hechos++; }
      if (cambiaCuad) { await apiRev.fijarCuadrilla(p.email, cuadrilla === "" ? null : Number(cuadrilla), sacaOCambia ? m : null); hechos++; }
      for (const a of actAsignar) { await apiRev.personalCambiar({ persona: p.email, tipo: "asignar_actividad", actividad: a }); hechos++; }
      for (const a of actQuitar) { await apiRev.personalCambiar({ persona: p.email, tipo: "quitar_actividad", actividad: a, motivo: m }); hechos++; }
      for (const f of asignar) { await apiRev.personalCambiar({ persona: p.email, tipo: "asignar_formulario", formulario: f }); hechos++; }
      for (const f of quitar) { await apiRev.personalCambiar({ persona: p.email, tipo: "quitar_formulario", formulario: f, motivo: m }); hechos++; }
      onHecho(`Cambios guardados para ${quien(p)} (${hechos}). Quedaron en el historial.`);
    } catch (e) {
      setError(`${textoError(e).texto}${hechos ? ` Se alcanzaron a guardar ${hechos} cambio(s); revise el historial.` : ""}`); setEnviando(false);
    }
  }
  const que = [quitar.length ? (quitar.length === 1 ? "quitar el formulario" : `quitar ${quitar.length} formularios`) : null,
    actQuitar.length ? (actQuitar.length === 1 ? "quitar la actividad" : `quitar ${actQuitar.length} actividades`) : null,
    sacaOCambia ? (cuadrilla === "" ? "sacarla de la cuadrilla" : "cambiarla de cuadrilla") : null].filter(Boolean).join(", ");
  return (
    <div className="rv-modal-fondo" onMouseDown={(e) => { if (e.target === e.currentTarget && !enviando) onCancelar(); }}>
      <div className="rv-modal" role="dialog" aria-modal="true" aria-label={`Editar a ${quien(p)}`}>
        <h3>Editar a {quien(p)}</h3>
        {puede.area ? (
          <label className="rv-campo">Área
            <select value={area} onChange={(e) => setArea(e.target.value)} data-campo="area">
              {p.area ? null : <option value="">Sin área (elija una)</option>}
              {p.area && !p.area.activa ? <option value={p.area.codigo} disabled>{p.area.nombre} (desactivada)</option> : null}
              {(datos.areas ?? []).map((a) => <option key={a.codigo} value={a.codigo}>{a.nombre}</option>)}
            </select>
          </label>) : null}
        {puede.cargo ? <>
          <label className="rv-campo">Cargo<input type="text" value={cargo} maxLength={80} onChange={(e) => setCargo(e.target.value)} placeholder="Ejemplo: Técnico de pérdidas" aria-invalid={cargoMal} /></label>
          <p className="rv-tenue">El cargo no se revierte: para corregirlo, escriba el correcto.</p></> : null}
        {puede.cuadrilla ? (
          <label className="rv-campo">Cuadrilla
            <select value={cuadrilla} onChange={(e) => setCuadrilla(e.target.value)} data-campo="cuadrilla">
              <option value="">Sin cuadrilla</option>
              {p.cuadrilla && p.cuadrilla.activa === false ? <option value={String(p.cuadrilla.id)} disabled>{p.cuadrilla.nombre} (desactivada)</option> : null}
              {(datos.cuadrillas ?? []).map((c) => <option key={c.id} value={String(c.id)}>{c.nombre}</option>)}
            </select>
            <small className="rv-tenue">En una cuadrilla, la persona hace las actividades de la cuadrilla y además las propias que se le den.</small>
          </label>) : null}
        {puede.actividades ? (
          <fieldset className="rv-per-forms" data-campo="actividades">
            <legend>Actividades propias</legend>
            <p className="rv-tenue">Las de su cuadrilla no se marcan aquí: se quitan en la cuadrilla.</p>
            {actOpciones.length === 0 ? <p className="rv-tenue">No hay actividades en el catálogo.</p> : null}
            {actOpciones.map((a) => {
              const cuad = deCuadrilla.get(a.codigo);
              return <label key={a.codigo} className="rv-check"><input type="checkbox" data-actividad={a.codigo} checked={propias.has(a.codigo)} disabled={!a.activa && !propias.has(a.codigo)} onChange={() => alternarAct(a.codigo)} /> {a.nombre}
                {!a.activa ? <span className="rv-per-desact"> (desactivada)</span> : null}{cuad ? <small className="rv-per-origen"> · también por su cuadrilla</small> : null}</label>;
            })}
          </fieldset>) : null}
        {puede.formularios ? (
          <fieldset className="rv-per-forms">
            <legend>Formularios que puede llenar</legend>
            <p className="rv-tenue">{marcados.size === 0 ? "Ninguno marcado: puede llenar todos los formularios activos." : `${marcados.size} marcado(s): solo estos quedan registrados como asignados.`}</p>
            {grupos.map(([g, fs]) => (
              <div key={g} className="rv-per-grupo">
                {fs.length > 1 || fs[0].nombre !== g ? <div className="rv-per-grupo-t">{g}</div> : null}
                {fs.map((f) => <label key={f.clave} className="rv-check"><input type="checkbox" checked={marcados.has(f.clave)} onChange={() => alternar(f.clave)} /> {f.nombre}</label>)}
              </div>
            ))}
          </fieldset>) : null}
        {pideMotivo ? <label className="rv-campo">Motivo para {que} (de 10 a 300 caracteres)
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

/** Texto de un evento del historial (de una persona o de una cuadrilla). */
export function textoEvento(e: EventoPersonal): string {
  const v = e.valor_nombre ?? e.valor_codigo ?? "";
  const c = e.cuadrilla?.nombre ?? v;
  switch (e.tipo_evento) {
    case "fijar_cargo": return `Cargo: «${e.cargo}»`;
    case "asignar_formulario": return `Asignó «${e.formulario_nombre ?? e.formulario}»`;
    case "quitar_formulario": return `Quitó «${e.formulario_nombre ?? e.formulario}»`;
    case "fijar_area": return `Área: «${v}»`;
    case "fijar_cuadrilla": return e.entra === true ? `Entró a la cuadrilla «${e.cuadrilla?.nombre ?? v}»` : e.entra === false ? `Salió de la cuadrilla «${e.cuadrilla?.nombre ?? ""}»` : v ? `Cuadrilla: «${v}»` : "Salió de la cuadrilla";
    case "asignar_actividad": return `Actividad propia: asignó «${v}»`;
    case "quitar_actividad": return `Actividad propia: quitó «${v}»`;
    case "cuadrilla_crear": return `Creó la cuadrilla «${c}»`;
    case "cuadrilla_renombrar": return `Renombró la cuadrilla a «${v}»`;
    case "cuadrilla_desactivar": return `Desactivó la cuadrilla «${e.cuadrilla?.nombre ?? ""}»`;
    case "cuadrilla_activar": return `Volvió a activar la cuadrilla «${e.cuadrilla?.nombre ?? ""}»`;
    case "cuadrilla_agregar_actividad": return `Cuadrilla «${e.cuadrilla?.nombre ?? ""}»: agregó «${v}»`;
    case "cuadrilla_quitar_actividad": return `Cuadrilla «${e.cuadrilla?.nombre ?? ""}»: quitó «${v}»`;
    default: return String(e.tipo_evento);
  }
}
/** Una fila del historial (se usa también en la cuadrilla). */
export function FilaEvento({ e, puedeRevertir, onRevertir }: { e: EventoPersonal; puedeRevertir?: boolean; onRevertir?: (e: EventoPersonal) => void }) {
  const deFormulario = e.tipo_evento === "asignar_formulario" || e.tipo_evento === "quitar_formulario";
  return (
    <li className="rv-per-evento" data-evento={e.tipo_evento}>
      <div className="rv-per-ev-cab"><strong>{textoEvento(e)}</strong>{e.vigente ? <span className="rv-marca rv-marca-info">Vigente</span> : null}</div>
      <div className="rv-tenue">n.º {e.id} · {e.persona ? quien(e) : e.cuadrilla?.nombre ?? "Cuadrilla"} · {fmtInstante(e.creado_en)} · por {e.autor}</div>
      {e.motivo ? <div className="rv-motivo">Motivo: {e.motivo}</div> : null}
      {puedeRevertir && e.vigente && deFormulario && onRevertir ? <button type="button" className="rv-enlace" onClick={() => onRevertir(e)}>Revertir</button> : null}
    </li>
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
        {(eventos ?? []).map((e) => <FilaEvento key={e.clave ?? e.id} e={e} puedeRevertir={puedeRevertir} onRevertir={onRevertir} />)}
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
  const malo = quitar && motivoMalo(motivo);
  async function aplicar() {
    if (enviando || malo || !e.persona) return; setEnviando(true); setError(null);
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
