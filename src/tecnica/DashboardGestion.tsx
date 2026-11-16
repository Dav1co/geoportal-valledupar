import { useEffect, useMemo, useRef, useState } from "react";
import {
  apiGestion, type AccionSugerida, type Area, type GrupoNoCrear, type VistaPreviaGrupo, type CatalogoRedes, type Descarga, type EventoFicha, type GraficasRedes, type NodoPorClasificar, type NodosPorClasificar,
  type Parametro, type ParametrosRedes, type PersonaRedes, type PersonalRedes, type TipoCatalogo,
} from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { NodoPreliminar } from "./NodoPreliminar";

// Dashboard distribución · gestión (Técnica fase 1, Corte 4b): Personal (área, cargo, cuadrilla y la casilla del geovisor del operador, N-13 y §27.3),
// Catálogo (alias N-12 y cuadrillas), Parámetros, Gráficas (D-19), Descargas en Excel (auditadas) y Nodos por clasificar (solo el administrador).
// Quién ve y quién edita lo decide el SERVIDOR en cada ruta; aquí solo se esconde lo que el servidor ya dijo que no se puede. Todo cambio lleva motivo.

const err = (e: unknown, sin: string) => (e instanceof ErrorTec && e.tipo === "permiso" ? sin : e instanceof Error ? e.message : "No se pudo completar.");
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "America/Bogota" });
const AREA: Record<Area, string> = { planta: "Planta", distribucion: "Distribución", ambas: "Planta y distribución" };
const SISTEMA: Record<string, string> = { acueducto: "Acueducto", alcantarillado: "Alcantarillado", tecnologia: "Tecnología" };
const nf = (n: number, dec = 0) => n.toLocaleString("es-CO", { maximumFractionDigits: dec, minimumFractionDigits: 0 });
const pesos = (n: number) => "$ " + nf(Math.round(n));
const MOTIVO_MIN = 10;

function Aviso({ msg, onCerrar }: { msg: { ok: boolean; t: string } | null; onCerrar?: () => void }) {
  if (!msg) return null;
  return <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"} dan-pad-x`} role={msg.ok ? "status" : "alert"}>{msg.t}
    {onCerrar ? <> <button type="button" className="tec-enlace" onClick={onCerrar}>Cerrar</button></> : null}</p>;
}
function CampoMotivo({ id, valor, onCambio }: { id: string; valor: string; onCambio: (v: string) => void }) {
  return <div className="tec-campo"><label htmlFor={id}>Motivo del cambio</label>
    <input id={id} type="text" maxLength={500} value={valor} onChange={(e) => onCambio(e.target.value)} placeholder="Por qué (10 caracteres o más)" /></div>;
}

// =====================================================================
// PERSONAL
// =====================================================================
const FILTROS = [{ c: "todas", n: "Todas" }, { c: "distribucion", n: "Distribución" }, { c: "planta", n: "Planta" }, { c: "sin_area", n: "Sin área" }] as const;
export function Personal() {
  const [filtro, setFiltro] = useState<(typeof FILTROS)[number]["c"]>("todas");
  const [buscar, setBuscar] = useState("");
  const [datos, setDatos] = useState<PersonalRedes | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<{ ok: boolean; t: string } | null>(null);
  const [editando, setEditando] = useState<string | null>(null);
  const [historial, setHistorial] = useState<string | null | undefined>(undefined);
  const ver = useRef(0);
  useEffect(() => {
    const v = ++ver.current; const t = setTimeout(() => {
      apiGestion.personal(buscar.trim(), filtro).then((r) => { if (v === ver.current) { setDatos(r); setError(null); } })
        .catch((e) => { if (v === ver.current) setError(err(e, "Solo el supervisor de distribución o el administrador ven el personal.")); });
    }, 250);
    return () => clearTimeout(t);
  }, [buscar, filtro, vez]);
  const nombreForm = useMemo(() => new Map((datos?.formularios ?? []).map((f) => [f.clave, f.nombre])), [datos]);
  return (
    <>
      <div className="dan-pad-x gest-filtros">
        <div className="dan-fila" role="group" aria-label="Filtro por área">{FILTROS.map((f) => (
          <button key={f.c} type="button" className="dan-opcion" aria-pressed={filtro === f.c} onClick={() => setFiltro(f.c)}>{f.n}</button>))}</div>
        <div className="tec-campo"><label htmlFor="gest-buscar">Buscar persona</label>
          <input id="gest-buscar" type="text" maxLength={80} value={buscar} placeholder="Nombre o correo" onChange={(e) => setBuscar(e.target.value)} /></div>
      </div>
      <p className="tec-ayuda dan-pad-x">El área decide en qué dashboard sale la persona. La casilla del geovisor es solo del operador de distribución: le deja ver la red en solo lectura
        (llega con el geovisor). Aquí se asignan los formularios de distribución; los de planta, en Personal del Dashboard PTAP.</p>
      <Aviso msg={aviso} onCerrar={() => setAviso(null)} />
      {error ? <section className="tec-tarjeta" role="alert"><p>{error}</p></section>
        : !datos ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !datos.personas.length ? <section className="tec-tarjeta"><p className="red-vacio">{buscar ? "Ninguna persona coincide con la búsqueda." : "No hay personas con ese filtro."}</p></section>
        : datos.personas.map((p) => (
          <section key={p.email} className={`tec-tarjeta itv-bandeja${p.activo_tecnica ? "" : " gest-apagada"}`} aria-label={p.nombre ?? p.email}>
            <h2>{p.nombre ?? p.email} <span className="itv-etiqueta">{p.perfil === "supervisor" ? "Supervisor de distribución" : "Operador"}</span>
              {p.dashboard_ptap ? <span className="itv-etiqueta">Dashboard PTAP</span> : null}{!p.activo_tecnica ? <span className="itv-etiqueta itv-etiqueta-dano">Desactivado en Técnica</span> : null}</h2>
            {p.nombre ? <p className="tec-ayuda gest-correo">{p.email}</p> : null}
            <dl className="gest-datos">
              <div><dt>Área</dt><dd>{p.area ? AREA[p.area] : "Sin definir"}</dd></div>
              <div><dt>Cargo</dt><dd>{p.cargo ?? "—"}</dd></div>
              <div><dt>Cuadrilla</dt><dd>{p.cuadrilla ? `${p.cuadrilla.nombre}${p.cuadrilla.activa ? "" : " (desactivada)"}` : "—"}</dd></div>
              <div><dt>Geovisor</dt><dd>{p.geovisor === "por_permiso" ? "Completo, por su permiso de supervisor" : p.geovisor === "si" ? "Sí, en solo lectura" : "No"}</dd></div>
              <div><dt>Formularios</dt><dd>{p.formularios.length ? p.formularios.map((c) => nombreForm.get(c) ?? c).join(" · ") : p.perfil === "supervisor" ? "Captura sin asignación (supervisor)" : "Ninguno de distribución"}</dd></div>
            </dl>
            {editando === p.email ? <EditarFicha p={p} cuadrillas={datos.cuadrillas} formularios={datos.formularios} onCerrar={() => setEditando(null)}
                onListo={(t) => { setEditando(null); setAviso({ ok: true, t }); setVez((v) => v + 1); }} />
              : <div className="dash-acciones">
                  {p.email === datos.yo ? <span className="tec-ayuda">Su propia ficha la cambia otro supervisor o el administrador.</span>
                    : <button type="button" className="tec-boton-sec" onClick={() => setEditando(p.email)}>Editar ficha</button>}
                  <button type="button" className="tec-boton-sec" onClick={() => setHistorial(p.email)}>Historial</button>
                </div>}
          </section>))}
      <div className="dan-pad-x dash-acciones">
        {historial === undefined ? <button type="button" className="tec-boton-sec" onClick={() => setHistorial(null)}>Ver el historial general</button>
          : <button type="button" className="tec-boton-sec" onClick={() => setHistorial(undefined)}>Ocultar el historial</button>}
      </div>
      {historial !== undefined ? <Historial persona={historial} vez={vez} onTodas={() => setHistorial(null)} /> : null}
    </>
  );
}

function EditarFicha({ p, cuadrillas, formularios, onCerrar, onListo }: { p: PersonaRedes; cuadrillas: { id: number; nombre: string }[]; formularios: { clave: string; nombre: string }[]; onCerrar: () => void; onListo: (t: string) => void }) {
  const [area, setArea] = useState<string>(p.area ?? "");
  const [cargo, setCargo] = useState(p.cargo ?? "");
  const [cuadrilla, setCuadrilla] = useState(p.cuadrilla ? String(p.cuadrilla.id) : "");
  const [geovisor, setGeovisor] = useState(p.geovisor === "si");
  const [forms, setForms] = useState<Set<string>>(() => new Set(p.formularios));
  const cambiosForm = formularios.filter((f) => forms.has(f.clave) !== p.formularios.includes(f.clave));
  const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [enviando, setEnviando] = useState(false);
  const cambios: [EventoFicha["tipo"], string | null][] = [];
  if (area && area !== (p.area ?? "")) cambios.push(["area", area]);
  if (cargo.trim() !== (p.cargo ?? "")) cambios.push(["cargo", cargo.trim() || null]);
  if (cuadrilla !== (p.cuadrilla ? String(p.cuadrilla.id) : "")) cambios.push(["cuadrilla", cuadrilla || null]);
  if (p.geovisor !== "por_permiso" && geovisor !== (p.geovisor === "si")) cambios.push(["geovisor", geovisor ? "si" : "no"]);
  const id = p.email.replace(/[^a-z0-9]/gi, "-");
  async function guardar() {
    if (!cambios.length && !cambiosForm.length) { setMsg({ ok: false, t: "No hay cambios." }); return; }
    if (cargo.trim() && (cargo.trim().length < 2 || cargo.trim().length > 80)) { setMsg({ ok: false, t: "El cargo lleva de 2 a 80 caracteres." }); return; }
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    setEnviando(true); setMsg(null); let hechos = 0;
    try {
      for (const [tipo, valor] of cambios) { await apiGestion.personalFijar(p.email, tipo, valor, motivo.trim()); hechos++; }
      for (const f of cambiosForm) { await apiGestion.personalFormulario(p.email, f.clave, forms.has(f.clave), motivo.trim()); hechos++; }
      onListo(`Ficha de ${p.nombre ?? p.email} actualizada (${hechos} cambio${hechos === 1 ? "" : "s"}).`);
    } catch (e) {
      setMsg({ ok: false, t: err(e, "No tiene permiso para esta acción.") + (hechos ? ` Se alcanzaron a guardar ${hechos} cambio(s); revise la ficha.` : "") });
    } finally { setEnviando(false); }
  }
  return (
    <div className="itv-nuevo gest-editor">
      <div className="tec-campo"><label htmlFor={`ar-${id}`}>Área</label>
        <select id={`ar-${id}`} value={area} onChange={(e) => setArea(e.target.value)}>
          {!p.area ? <option value="">Sin definir</option> : null}
          <option value="planta">Planta</option><option value="distribucion">Distribución</option><option value="ambas">Planta y distribución</option>
        </select></div>
      <div className="tec-campo"><label htmlFor={`ca-${id}`}>Cargo (opcional)</label>
        <input id={`ca-${id}`} type="text" maxLength={80} value={cargo} onChange={(e) => setCargo(e.target.value)} placeholder="Por ejemplo, fontanero" /></div>
      <div className="tec-campo"><label htmlFor={`cu-${id}`}>Cuadrilla</label>
        <select id={`cu-${id}`} value={cuadrilla} onChange={(e) => setCuadrilla(e.target.value)}>
          <option value="">Sin cuadrilla</option>
          {cuadrillas.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}
          {p.cuadrilla && !cuadrillas.some((c) => c.id === p.cuadrilla!.id) ? <option value={p.cuadrilla.id}>{p.cuadrilla.nombre} (desactivada)</option> : null}
        </select>
        {!cuadrillas.length ? <p className="tec-ayuda">Todavía no hay cuadrillas: las crea el administrador en Catálogo.</p> : null}</div>
      {p.geovisor === "por_permiso" ? <p className="tec-ayuda">Ve el geovisor completo por su permiso de supervisor: no lleva casilla.</p>
        : <label className="dan-check gest-check"><input type="checkbox" checked={geovisor} onChange={(e) => setGeovisor(e.target.checked)} /> Geovisor en solo lectura (ve la red y las actividades del día)</label>}
      {p.perfil === "supervisor" ? <p className="tec-ayuda">Como supervisor de distribución captura los formularios de distribución sin que se le asignen.</p>
        : !p.registro_tecnico ? <p className="tec-ayuda">Sin «Registro técnico»: el administrador debe dárselo antes de asignarle formularios.</p>
        : <fieldset className="gest-formularios"><legend>Formularios de distribución</legend>
            {formularios.map((f) => <label key={f.clave} className="dan-check gest-check"><input type="checkbox" data-formulario={f.clave} checked={forms.has(f.clave)}
              onChange={(e) => { const n = new Set(forms); if (e.target.checked) n.add(f.clave); else n.delete(f.clave); setForms(n); }} /> {f.nombre}</label>)}</fieldset>}
      <CampoMotivo id={`mo-${id}`} valor={motivo} onCambio={setMotivo} />
      <Aviso msg={msg} />
      <div className="tec-acciones">
        <button type="button" className="tec-boton itv-guardar" disabled={enviando} onClick={guardar}>{enviando ? "Guardando…" : `Guardar (${cambios.length + cambiosForm.length} cambio${cambios.length + cambiosForm.length === 1 ? "" : "s"})`}</button>
        <button type="button" className="tec-boton-sec" disabled={enviando} onClick={onCerrar}>Cancelar</button>
      </div>
    </div>
  );
}

const textoEvento = (e: EventoFicha) => e.tipo === "area" ? `Área: ${e.valor ? AREA[e.valor as Area] ?? e.valor : "—"}`
  : e.tipo === "cargo" ? (e.valor ? `Cargo: ${e.valor}` : "Quitó el cargo")
  : e.tipo === "cuadrilla" ? (e.valor ? `Cuadrilla: ${e.valor_nombre ?? e.valor}` : "Quitó la cuadrilla")
  : e.valor === "si" ? "Activó el geovisor en solo lectura" : "Quitó el geovisor";
function Historial({ persona, vez, onTodas }: { persona: string | null; vez: number; onTodas: () => void }) {
  const [ev, setEv] = useState<EventoFicha[] | null>(null); const [total, setTotal] = useState(0); const [error, setError] = useState<string | null>(null);
  useEffect(() => { setEv(null); apiGestion.historial(persona, null).then((r) => { setEv(r.eventos); setTotal(r.total); }).catch((e) => setError(err(e, "Sin permiso."))); }, [persona, vez]);
  return (
    <section className="tec-tarjeta" aria-label="Historial de la ficha del personal">
      <h2>Historial {persona ? `· ${persona}` : "general"}</h2>
      {persona ? <button type="button" className="tec-enlace gest-izq" onClick={onTodas}>Ver el de todas las personas</button> : null}
      {error ? <p role="alert">{error}</p> : !ev ? <p role="status">Cargando…</p> : !ev.length ? <p className="red-vacio">Todavía no hay cambios.</p> : (
        <ul className="gest-eventos">{ev.map((e) => (
          <li key={e.id}><strong>{textoEvento(e)}</strong>{persona ? null : <> · {e.persona_nombre ?? e.persona}</>}
            <span className="tec-ayuda"> {fecha(e.creado_en)} · {e.autor_nombre ?? e.autor}</span><div className="tec-ayuda">Motivo: {e.motivo}</div></li>))}</ul>)}
      {ev && ev.length < total ? <button type="button" className="tec-boton-sec" onClick={() => apiGestion.historial(persona, ev[ev.length - 1].id).then((r) => setEv([...ev, ...r.eventos])).catch(() => {})}>
        Cargar más ({total - ev.length})</button> : null}
    </section>
  );
}

// =====================================================================
// CATÁLOGO
// =====================================================================
export function Catalogo() {
  const [c, setC] = useState<CatalogoRedes | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<{ ok: boolean; t: string } | null>(null);
  useEffect(() => { apiGestion.catalogo().then((r) => { setC(r); setError(null); }).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven el catálogo."))); }, [vez]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!c) return <p className="tec-sub dan-pad" role="status">Cargando…</p>;
  const listo = (t: string) => { setAviso({ ok: true, t }); setVez((v) => v + 1); };
  const sistemas = [...new Set(c.tipos.map((t) => t.sistema))];
  return (
    <>
      <p className="tec-ayuda dan-pad-x">{c.puede_editar ? "Usted puede cambiar el nombre visible de cada tipo (el prefijo y los códigos no cambian) y las cuadrillas." : c.puede_cuadrillas ? "Usted puede crear y cambiar las cuadrillas. El nombre visible de los tipos lo cambia el administrador." : "Solo lectura: el nombre visible y las cuadrillas los cambia el administrador."}</p>
      <Aviso msg={aviso} onCerrar={() => setAviso(null)} />
      <section className="tec-tarjeta" aria-label="Cuadrillas">
        <h2>Cuadrillas</h2>
        {!c.cuadrillas.length ? <p className="red-vacio">Todavía no hay cuadrillas.</p> : (
          <ul className="gest-lista">{c.cuadrillas.map((q) => <Cuadrilla key={q.id} q={q} editable={c.puede_editar || !!c.puede_cuadrillas} onListo={listo} />)}</ul>)}
        {c.puede_editar || c.puede_cuadrillas ? <NuevaCuadrilla onListo={listo} /> : null}
      </section>
      {sistemas.map((s) => (
        <section key={s} className="tec-tarjeta" aria-label={`Tipos de activo de ${SISTEMA[s] ?? s}`}>
          <h2>Tipos de activo · {SISTEMA[s] ?? s}</h2>
          <ul className="gest-lista">{c.tipos.filter((t) => t.sistema === s).map((t) => <TipoItem key={t.prefijo} t={t} editable={c.puede_editar} onListo={listo} />)}</ul>
        </section>))}
      <section className="tec-tarjeta" aria-label="Otros catálogos">
        <h2>Otros catálogos (solo lectura)</h2>
        {([["Materiales", c.materiales], ["Estados del activo", c.estados], ["Tipos de intervención", c.tipos_intervencion], ["Daños y fallas", c.tipos_dano],
           ["Causas", c.causas], ["Entidades aportantes", c.aportantes], ["Contratistas", c.contratistas]] as [string, { codigo: string; nombre: string; activo?: boolean }[]][]).map(([n, l]) => (
          <details key={n} className="gest-detalle"><summary>{n} ({l.length})</summary>
            <ul>{l.map((x) => <li key={x.codigo}>{x.nombre}{x.activo === false ? " (desactivado)" : ""}</li>)}</ul></details>))}
      </section>
    </>
  );
}

function TipoItem({ t, editable, onListo }: { t: TipoCatalogo; editable: boolean; onListo: (t: string) => void }) {
  const [abierto, setAbierto] = useState(false); const [alias, setAlias] = useState(t.alias ?? ""); const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null); const [hist, setHist] = useState<{ alias: string | null; motivo: string; autor: string; creado_en: string }[] | null>(null);
  async function enviar(valor: string | null) {
    if (valor !== null && (valor.trim().length < 2 || valor.trim().length > 60)) { setMsg({ ok: false, t: "El nombre visible lleva de 2 a 60 caracteres." }); return; }
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    try { await apiGestion.aliasFijar("tipo", t.prefijo, valor?.trim() ?? null, motivo.trim()); setAbierto(false); onListo(valor ? `${t.prefijo} se ve ahora como «${valor.trim()}».` : `${t.prefijo} volvió a su nombre original.`); }
    catch (e) { setMsg({ ok: false, t: err(e, "Solo el administrador cambia el nombre visible.") }); }
  }
  return (
    <li className="gest-item">
      <div><strong>{t.nombre_visible}</strong> <span className="itv-etiqueta">{t.prefijo}</span>{!t.activo ? <span className="itv-etiqueta">Desactivado</span> : null}
        <div className="tec-ayuda">{t.alias ? `Nombre original: ${t.nombre} · ` : ""}{t.geometria === "linea" ? "Línea" : t.geometria === "punto" ? "Punto" : t.geometria} · {nf(t.vigentes)} vigente{t.vigentes === 1 ? "" : "s"}</div></div>
      <div className="dash-acciones">
        {editable && !abierto ? <button type="button" className="tec-boton-sec" onClick={() => setAbierto(true)}>Nombre visible</button> : null}
        <button type="button" className="tec-enlace" onClick={() => hist ? setHist(null) : apiGestion.aliasHistorial("tipo", t.prefijo).then((r) => setHist(r.eventos)).catch(() => setHist([]))}>{hist ? "Ocultar historial" : "Historial"}</button>
      </div>
      {abierto ? (
        <div className="itv-nuevo">
          <div className="tec-campo"><label htmlFor={`al-${t.prefijo}`}>Nombre visible de {t.prefijo}</label>
            <input id={`al-${t.prefijo}`} type="text" maxLength={60} value={alias} onChange={(e) => setAlias(e.target.value)} placeholder={t.nombre} /></div>
          <CampoMotivo id={`alm-${t.prefijo}`} valor={motivo} onCambio={setMotivo} />
          <Aviso msg={msg} />
          <div className="tec-acciones">
            <button type="button" className="tec-boton itv-guardar" onClick={() => enviar(alias)}>Guardar</button>
            {t.alias ? <button type="button" className="tec-boton-sec" onClick={() => enviar(null)}>Volver al nombre original</button> : null}
            <button type="button" className="tec-boton-sec" onClick={() => setAbierto(false)}>Cancelar</button>
          </div>
        </div>) : null}
      {hist ? (!hist.length ? <p className="tec-ayuda">Sin cambios de nombre.</p> : <ul className="gest-eventos">{hist.map((h, i) => (
        <li key={i}>{h.alias ? `«${h.alias}»` : "Nombre original"} <span className="tec-ayuda">· {fecha(h.creado_en)} · {h.autor}</span><div className="tec-ayuda">Motivo: {h.motivo}</div></li>))}</ul>) : null}
    </li>
  );
}

function Cuadrilla({ q, editable, onListo }: { q: CatalogoRedes["cuadrillas"][number]; editable: boolean; onListo: (t: string) => void }) {
  const [abierto, setAbierto] = useState(false); const [nombre, setNombre] = useState(q.nombre); const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  async function enviar(activa: boolean | null) {
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    try { const r = await apiGestion.cuadrillaFijar(q.id, activa === null && nombre.trim() !== q.nombre ? nombre.trim() : null, activa, motivo.trim());
      setAbierto(false); onListo(`Cuadrilla «${r.nombre}» ${r.activa ? "activa" : "desactivada"}.`); }
    catch (e) { setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador cambian las cuadrillas.") }); }
  }
  return (
    <li className="gest-item">
      <div><strong>{q.nombre}</strong> {!q.activa ? <span className="itv-etiqueta">Desactivada</span> : null}<div className="tec-ayuda">{q.personas} persona{q.personas === 1 ? "" : "s"}</div></div>
      {editable && !abierto ? <div className="dash-acciones"><button type="button" className="tec-boton-sec" onClick={() => setAbierto(true)}>Cambiar</button></div> : null}
      {abierto ? (
        <div className="itv-nuevo">
          <div className="tec-campo"><label htmlFor={`cq-${q.id}`}>Nombre</label><input id={`cq-${q.id}`} type="text" maxLength={60} value={nombre} onChange={(e) => setNombre(e.target.value)} /></div>
          <CampoMotivo id={`cqm-${q.id}`} valor={motivo} onCambio={setMotivo} />
          <Aviso msg={msg} />
          <div className="tec-acciones">
            <button type="button" className="tec-boton itv-guardar" onClick={() => enviar(null)}>Guardar el nombre</button>
            <button type="button" className="tec-boton-sec" onClick={() => enviar(!q.activa)}>{q.activa ? "Desactivar" : "Activar"}</button>
            <button type="button" className="tec-boton-sec" onClick={() => setAbierto(false)}>Cancelar</button>
          </div>
        </div>) : null}
    </li>
  );
}

function NuevaCuadrilla({ onListo }: { onListo: (t: string) => void }) {
  const [nombre, setNombre] = useState(""); const [motivo, setMotivo] = useState(""); const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  return (
    <div className="itv-nuevo">
      <div className="tec-campo"><label htmlFor="cq-nueva">Cuadrilla nueva</label><input id="cq-nueva" type="text" maxLength={60} value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Por ejemplo, Cuadrilla Norte" /></div>
      <CampoMotivo id="cq-nueva-m" valor={motivo} onCambio={setMotivo} />
      <Aviso msg={msg} />
      <button type="button" className="tec-boton-sec" onClick={async () => {
        if (nombre.trim().length < 2) { setMsg({ ok: false, t: "Escriba el nombre (2 a 60 caracteres)." }); return; }
        if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
        try { const r = await apiGestion.cuadrillaFijar(null, nombre.trim(), null, motivo.trim()); setNombre(""); setMotivo(""); setMsg(null); onListo(`Cuadrilla «${r.nombre}» creada.`); }
        catch (e) { setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador crean cuadrillas.") }); }
      }}>Crear la cuadrilla</button>
    </div>
  );
}

// =====================================================================
// PARÁMETROS
// =====================================================================
export function Parametros() {
  const [d, setD] = useState<ParametrosRedes | null>(null); const [error, setError] = useState<string | null>(null); const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<{ ok: boolean; t: string } | null>(null);
  useEffect(() => { apiGestion.parametros().then(setD).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven los parámetros."))); }, [vez]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!d) return <p className="tec-sub dan-pad" role="status">Cargando…</p>;
  return (
    <>
      <p className="tec-ayuda dan-pad-x">{d.puede_editar ? "Cada cambio queda con su valor anterior, el nuevo, el motivo y quién lo hizo. La caja de Valledupar no se cambia desde aquí."
        : "Solo lectura: los parámetros los cambia el administrador."}</p>
      <Aviso msg={aviso} onCerrar={() => setAviso(null)} />
      <section className="tec-tarjeta" aria-label="Parámetros de redes">
        <h2>Parámetros de redes</h2>
        <ul className="gest-lista">{d.parametros.map((p) => <ParametroItem key={p.clave} p={p} onListo={(t) => { setAviso({ ok: true, t }); setVez((v) => v + 1); }} />)}</ul>
      </section>
      <section className="tec-tarjeta" aria-label="Últimos cambios de parámetros">
        <h2>Últimos cambios</h2>
        {!d.historial.length ? <p className="red-vacio">Todavía no hay cambios.</p> : <ul className="gest-eventos">{d.historial.map((h) => (
          <li key={h.id}><strong>{h.clave}</strong>: {h.antes ?? "—"} → {h.despues ?? "—"} <span className="tec-ayuda">· {fecha(h.creado_en)} · {h.autor}</span><div className="tec-ayuda">Motivo: {h.motivo}</div></li>))}</ul>}
      </section>
    </>
  );
}

function ParametroItem({ p, onListo }: { p: Parametro; onListo: (t: string) => void }) {
  const [abierto, setAbierto] = useState(false); const [valor, setValor] = useState(p.valor === null ? "" : String(p.valor)); const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const rango = `${p.minimo ?? "—"} a ${p.maximo ?? "—"} ${p.unidad}`;
  async function guardar() {
    const n = Number(valor.replace(",", "."));
    if (valor.trim() === "" || !Number.isFinite(n)) { setMsg({ ok: false, t: "Escriba un número." }); return; }
    if (p.entero && !Number.isInteger(n)) { setMsg({ ok: false, t: `Va en ${p.unidad} enteros.` }); return; }
    if ((p.minimo !== null && n < p.minimo) || (p.maximo !== null && n > p.maximo)) { setMsg({ ok: false, t: `El valor va de ${rango}.` }); return; }
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    try { await apiGestion.parametroFijar(p.clave, n, motivo.trim()); setAbierto(false); onListo(`«${p.clave}» quedó en ${n} ${p.unidad}.`); }
    catch (e) { setMsg({ ok: false, t: err(e, "Solo el administrador cambia los parámetros.") }); }
  }
  return (
    <li className="gest-item">
      <div><strong>{p.descripcion}</strong>
        <div className="tec-ayuda"><code>{p.clave}</code> · <strong>{p.valor ?? "sin valor"} {p.unidad}</strong> · rango {rango}{p.estado !== "vigente" ? ` · ${p.estado}` : ""}</div></div>
      {p.editable && !abierto ? <div className="dash-acciones"><button type="button" className="tec-boton-sec" onClick={() => setAbierto(true)}>Cambiar</button></div> : null}
      {abierto ? (
        <div className="itv-nuevo">
          <div className="tec-campo"><label htmlFor={`pv-${p.clave}`}>Valor nuevo ({p.unidad})</label>
            <input id={`pv-${p.clave}`} type="text" inputMode="decimal" maxLength={20} value={valor} onChange={(e) => setValor(e.target.value)} /></div>
          <CampoMotivo id={`pm-${p.clave}`} valor={motivo} onCambio={setMotivo} />
          <Aviso msg={msg} />
          <div className="tec-acciones"><button type="button" className="tec-boton itv-guardar" onClick={guardar}>Guardar</button>
            <button type="button" className="tec-boton-sec" onClick={() => setAbierto(false)}>Cancelar</button></div>
        </div>) : null}
    </li>
  );
}

// =====================================================================
// GRÁFICAS (D-19): una serie por gráfica (barras de un solo color, con su valor escrito) y la tabla con los mismos datos.
// =====================================================================
const MES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const nombreMes = (m: string) => `${MES[Number(m.slice(5, 7)) - 1]} ${m.slice(2, 4)}`;
const CAUSA: Record<string, string> = { propia: "Propia", terceros: "Terceros", desconocida: "Desconocida", sin_dato: "Sin dato" };
const minutos = (m: number | null) => m === null ? "—" : m < 60 ? `${nf(m)} min` : `${nf(Math.floor(m / 60))} h ${String(Math.round(m % 60)).padStart(2, "0")} min`;

function Barras({ titulo, filas, formato }: { titulo: string; filas: { etiqueta: string; valor: number; nota?: string }[]; formato: (n: number) => string }) {
  const max = Math.max(1, ...filas.map((f) => f.valor));
  return (
    <div className="gest-barras" role="img" aria-label={`${titulo}: ${filas.map((f) => `${f.etiqueta} ${formato(f.valor)}`).join("; ")}`}>
      {filas.map((f) => (
        <div key={f.etiqueta} className="gest-barra" title={`${f.etiqueta}: ${formato(f.valor)}${f.nota ? ` · ${f.nota}` : ""}`}>
          <span className="gest-barra-et">{f.etiqueta}</span>
          <span className="gest-barra-pista"><span className={`gest-barra-relleno${f.valor ? "" : " gest-barra-cero"}`} style={{ width: `${(f.valor / max) * 100}%` }} /></span>
          <span className="gest-barra-val">{formato(f.valor)}</span>
        </div>))}
    </div>
  );
}

export function Graficas({ onFicha }: { onFicha: (c: string) => void }) {
  const [meses, setMeses] = useState(12); const [g, setG] = useState<GraficasRedes | null>(null); const [error, setError] = useState<string | null>(null);
  useEffect(() => { setG(null); apiGestion.graficas(meses).then(setG).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven las gráficas."))); }, [meses]);
  const porMes = useMemo(() => g ? g.meses.map((m) => ({ etiqueta: nombreMes(m), valor: g.intervenciones_mes.filter((x) => x.mes === m).reduce((a, x) => a + x.n, 0) })) : [], [g]);
  const porTipo = useMemo(() => {
    if (!g) return [];
    const k = new Map<string, number>(); for (const x of g.intervenciones_mes) { const c = `${x.tipo_nombre} · ${SISTEMA[x.sistema] ?? x.sistema}`; k.set(c, (k.get(c) ?? 0) + x.n); }
    return [...k.entries()].sort((a, b) => b[1] - a[1]).map(([etiqueta, valor]) => ({ etiqueta, valor }));
  }, [g]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  return (
    <>
      <div className="dan-fila dan-pad-x" role="group" aria-label="Rango de las gráficas">{[3, 6, 12, 24].map((m) => (
        <button key={m} type="button" className="dan-opcion" aria-pressed={meses === m} onClick={() => setMeses(m)}>{m} meses</button>))}</div>
      <p className="tec-ayuda dan-pad-x">Sin los registros ocultos ni las intervenciones anuladas.</p>
      {!g ? <p className="tec-sub dan-pad" role="status">Cargando…</p> : (
        <>
          <section className="tec-tarjeta" aria-label="Intervenciones por mes">
            <h2>Intervenciones por mes</h2>
            {porMes.every((x) => !x.valor) ? <p className="red-vacio">No hay intervenciones en el rango.</p> : <>
              <Barras titulo="Intervenciones por mes" filas={porMes} formato={(n) => nf(n)} />
              <h3 className="gest-h3">Por tipo y sistema</h3>
              <Barras titulo="Intervenciones por tipo y sistema" filas={porTipo} formato={(n) => nf(n)} />
              <details className="gest-detalle"><summary>Ver la tabla</summary>
                <table className="gest-tabla"><thead><tr><th>Mes</th><th>Tipo</th><th>Sistema</th><th>N.º</th></tr></thead>
                  <tbody>{g.intervenciones_mes.map((x, i) => <tr key={i}><td>{nombreMes(x.mes)}</td><td>{x.tipo_nombre}</td><td>{SISTEMA[x.sistema] ?? x.sistema}</td><td>{x.n}</td></tr>)}</tbody></table></details>
            </>}
          </section>
          <section className="tec-tarjeta" aria-label="Valor por fuente de recursos">
            <h2>Valor por fuente de recursos</h2>
            {!g.valor_fuente.length ? <p className="red-vacio">No hay recursos en el rango.</p> : <>
              <Barras titulo="Valor por fuente" filas={g.valor_fuente.map((x) => ({ etiqueta: x.nombre, valor: x.valor ?? 0, nota: `${x.intervenciones} intervención(es)` }))} formato={pesos} />
              {g.valor_fuente.some((x) => x.sin_valor) ? <p className="tec-ayuda">Sin valor todavía: {g.valor_fuente.filter((x) => x.sin_valor).map((x) => `${x.nombre} (${x.sin_valor})`).join(" · ")}. Se completan en Intervenciones → Recursos por completar.</p> : null}
            </>}
          </section>
          <section className="tec-tarjeta" aria-label="Daños y fallas por clase y causa">
            <h2>Daños y fallas por causa</h2>
            {!g.danos_causa.length ? <p className="red-vacio">No hay daños ni fallas en el rango.</p> : (
              <div className="gest-tabla-caja"><table className="gest-tabla"><thead><tr><th>Clase</th><th>Causa</th><th>N.º</th><th>Atendidos</th><th>Respuesta media</th><th>Reparación media</th></tr></thead>
                <tbody>{g.danos_causa.map((x, i) => <tr key={i}><td>{x.clase === "dano" ? "Daño" : "Falla"}</td><td>{CAUSA[x.causa_clase] ?? x.causa_clase}</td><td>{x.n}</td><td>{x.atendidos}</td>
                  <td>{minutos(x.respuesta_media_min)}</td><td>{minutos(x.reparacion_media_min)}</td></tr>)}</tbody></table></div>)}
          </section>
          <section className="tec-tarjeta" aria-label="Activos con más correctivos">
            <h2>Los 10 activos con más correctivos</h2>
            <p className="tec-ayuda">Correctivos, reparaciones y reposiciones del rango.</p>
            {!g.top_correctivos.length ? <p className="red-vacio">No hay correctivos en el rango.</p> : <>
              <Barras titulo="Activos con más correctivos" filas={g.top_correctivos.map((x) => ({ etiqueta: `${x.activo}${x.tipo ? ` · ${x.tipo}` : ""}`, valor: x.n }))} formato={(n) => nf(n)} />
              <div className="dash-acciones">{g.top_correctivos.map((x) => <button key={x.activo} type="button" className="tec-enlace" onClick={() => onFicha(x.activo)}>{x.activo}</button>)}</div>
            </>}
          </section>
        </>)}
    </>
  );
}

// =====================================================================
// DESCARGAS EN EXCEL (los datos salen solo por la ruta auditada; el archivo se arma en el navegador)
// =====================================================================
type Col = [clave: string, titulo: string, ancho: number, tipo?: "fechaHora" | "num"];
const COL_ITV: Col[] = [["codigo", "Código", 12], ["nace_de", "Nace de", 11], ["dano", "Daño que atiende", 13], ["tipo", "Tipo", 22], ["inversion_modo", "Inversión", 10],
  ["sistema", "Sistema", 14], ["activo", "Activo", 13], ["prefijo", "Prefijo", 8], ["tipo_activo", "Tipo de activo (nombre visible)", 24], ["no_identificado", "No identificado", 22],
  ["t_inicio", "Inicio", 17, "fechaHora"], ["t_fin", "Fin", 17, "fechaHora"], ["duracion_min", "Duración (min)", 12, "num"], ["ejecutor", "Ejecutor", 12], ["contratista", "Contratista", 22],
  ["contrato_orden", "Contrato u orden", 16], ["estado", "Estado", 11], ["resuelve_dano", "Resuelve el daño", 10], ["fotos", "Fotos", 7, "num"], ["documentos", "Documentos", 9, "num"],
  ["recursos", "Recursos", 13], ["aportantes", "Aportantes", 26], ["valor_total", "Valor total", 14, "num"], ["lat", "Latitud", 11, "num"], ["lon", "Longitud", 11, "num"],
  ["autor", "Registró", 28], ["registrado_en", "Registrado", 17, "fechaHora"]];
const COL_DAN: Col[] = [["codigo", "Código", 12], ["clase", "Clase", 8], ["tipo", "Tipo", 22], ["sistema", "Sistema", 14], ["activo", "Activo", 13], ["prefijo", "Prefijo", 8],
  ["tipo_activo", "Tipo de activo (nombre visible)", 24], ["no_identificado", "No identificado", 22], ["estado", "Estado", 12], ["t_inicio_dano", "Inicio del daño", 17, "fechaHora"],
  ["t_detectado", "Detectado", 17, "fechaHora"], ["t_inicio_reparacion", "Inicio de la reparación", 17, "fechaHora"], ["t_restablecido", "Servicio restablecido", 17, "fechaHora"],
  ["respuesta_min", "Respuesta (min)", 11, "num"], ["reparacion_min", "Reparación (min)", 11, "num"], ["total_min", "Total (min)", 11, "num"], ["tipo_rotura", "Rotura", 12],
  ["largo_afectado_m", "Largo afectado (m)", 11, "num"], ["presion_mca", "Presión (mca)", 10, "num"], ["usuarios_sin_servicio", "Usuarios sin servicio", 11, "num"], ["sector", "Sector", 8, "num"],
  ["riesgo", "Riesgo", 8], ["causa_clase", "Causa (clase)", 12], ["causa", "Causa", 18], ["tercero_tipo", "Tipo de tercero", 16], ["origen", "Origen", 11],
  ["intervenciones", "Intervenciones", 10, "num"], ["fotos", "Fotos", 7, "num"], ["lat", "Latitud", 11, "num"], ["lon", "Longitud", 11, "num"], ["autor", "Registró", 28],
  ["registrado_en", "Registrado", 17, "fechaHora"]];
const BOGOTA = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
function partesBogota(iso: string): [string, string] | null {
  const d = new Date(iso); if (Number.isNaN(d.getTime())) return null;
  const p = Object.fromEntries(BOGOTA.formatToParts(d).map((x) => [x.type, x.value]));
  return [`${p.year}-${p.month}-${p.day}`, `${p.hour}:${p.minute}:${p.second}`];
}
const hoyBogota = () => partesBogota(new Date().toISOString())![0];

export function Descargas() {
  const [conjunto, setConjunto] = useState<"intervenciones" | "danos">("intervenciones");
  const [desde, setDesde] = useState(() => hoyBogota().slice(0, 8) + "01");
  const [hasta, setHasta] = useState(hoyBogota);
  const [ocultos, setOcultos] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [trabajando, setTrabajando] = useState(false);
  async function descargar() {
    if (!desde || !hasta || hasta < desde) { setMsg({ ok: false, t: "Elija el rango: «hasta» no puede ser antes de «desde»." }); return; }
    setTrabajando(true); setMsg(null);
    try {
      const d: Descarga = await apiGestion.descarga(conjunto, desde, hasta, ocultos);
      const cols = conjunto === "intervenciones" ? COL_ITV : COL_DAN;
      const { LibroXlsx, serialExcel } = await import("./xlsx");
      const libro = new LibroXlsx({ hoja: conjunto === "intervenciones" ? "Intervenciones" : "Daños y fallas", encabezados: cols.map((c) => c[1]), anchos: cols.map((c) => c[2]),
        leame: [["Qué es", conjunto === "intervenciones" ? "Intervenciones de distribución (Técnica)" : "Daños y fallas de distribución (Técnica)"],
          ["Rango", `${desde} a ${hasta} (${conjunto === "intervenciones" ? "por la fecha de fin" : "por la fecha de detección"}; hora de Bogotá)`],
          ["Ocultos", ocultos ? "Incluidos (columna Estado)" : "No incluidos"], ["Filas", String(d.total)],
          ["Generado", `${fecha(d.generado_en)} por ${d.generado_por}. La descarga queda registrada en la auditoría.`],
          ["Tipo de activo", "Va el nombre visible y el prefijo: el prefijo no cambia aunque cambie el nombre visible."],
          ["Lo que no va", "El nombre o la placa del tercero (dato personal), las descripciones y los compañeros (texto libre). Se ven en la pantalla."]] });
      const filas = d.filas.map((f) => cols.map(([k, , , tipo]) => {
        const v = f[k]; if (v === null || v === undefined) return null;
        if (tipo === "fechaHora") { const p = partesBogota(String(v)); const s = p ? serialExcel(p[0], p[1]) : null; return s === null ? String(v) : { fechaHora: s }; }
        if (tipo === "num") return typeof v === "number" ? v : Number(v);
        if (typeof v === "boolean") return v ? "Sí" : "No";
        return String(v);
      }));
      for (let i = 0; i < filas.length; i += 2000) await libro.agregarFilas(filas.slice(i, i + 2000));
      const blob = await libro.finalizar();
      const url = URL.createObjectURL(blob); const a = document.createElement("a");
      a.href = url; a.download = `${conjunto === "intervenciones" ? "intervenciones" : "danos_fallas"}_${desde}_a_${hasta}.xlsx`; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
      setMsg({ ok: true, t: `Listo: ${nf(d.total)} fila${d.total === 1 ? "" : "s"}. La descarga quedó registrada.` });
    } catch (e) { setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador descargan.") }); } finally { setTrabajando(false); }
  }
  return (
    <section className="tec-tarjeta" aria-label="Descargar en Excel">
      <h2>Descargar en Excel</h2>
      <div className="dan-fila" role="group" aria-label="Qué descargar">
        <button type="button" className="dan-opcion" aria-pressed={conjunto === "intervenciones"} onClick={() => setConjunto("intervenciones")}>Intervenciones</button>
        <button type="button" className="dan-opcion" aria-pressed={conjunto === "danos"} onClick={() => setConjunto("danos")}>Daños y fallas</button>
      </div>
      <div className="gest-fechas">
        <div className="tec-campo"><label htmlFor="ds-desde">Desde</label><input id="ds-desde" type="date" value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)} /></div>
        <div className="tec-campo"><label htmlFor="ds-hasta">Hasta</label><input id="ds-hasta" type="date" value={hasta} min={desde} onChange={(e) => setHasta(e.target.value)} /></div>
      </div>
      <label className="dan-check gest-check"><input type="checkbox" checked={ocultos} onChange={(e) => setOcultos(e.target.checked)} /> Incluir los ocultos</label>
      <p className="tec-ayuda">Hasta un año por descarga. No lleva el nombre ni la placa del tercero, ni las descripciones. Cada descarga queda registrada con quién la hizo.</p>
      <Aviso msg={msg} />
      <button type="button" className="tec-boton itv-guardar" disabled={trabajando} onClick={descargar}>{trabajando ? "Preparando…" : "Descargar Excel"}</button>
    </section>
  );
}

// =====================================================================
// NODOS POR CLASIFICAR (solo el administrador; N-3)
// =====================================================================
// Corte 9a: cada nodo trae lo que dice el modelo y una SUGERENCIA (que se confirma con motivo; nada se clasifica solo), y abre su ficha preliminar de solo lectura.
const SUGERENCIA: Record<AccionSugerida, string> = { no_crear: "Propuesto por el Plan: no crear activo", dejar_nodo: "Dejar como nodo", crear: "Crear el activo", revisar: "Revisar en campo", sin_modelo: "Sin datos del modelo" };
const CLASE_NODO = { nodo_calculo: "Dejar como nodo (no es un activo)", propuesta_plan: "Propuesto por el Plan, no instalado (no crear activo)" } as const;
// 9a-bis (respuestas de David del 16-nov): la bandeja la usan el supervisor de distribución y el administrador; el nombre visible de un nodo (catálogo) sigue
// siendo solo del administrador. Los grupos de «no crear activo» se confirman de una vez, con vista previa (cuántos, cuáles y en qué sectores) y un motivo.
export function Nodos({ onFicha, admin = false }: { onFicha: (c: string) => void; admin?: boolean }) {
  const [sug, setSug] = useState<AccionSugerida | null>(null);
  const [buscar, setBuscar] = useState(""); const [d, setD] = useState<NodosPorClasificar | null>(null); const [items, setItems] = useState<NodoPorClasificar[]>([]);
  const [error, setError] = useState<string | null>(null); const [vez, setVez] = useState(0); const [aviso, setAviso] = useState<{ ok: boolean; t: string; activo?: string } | null>(null);
  const ver = useRef(0);
  const consulta = sug ? `sugerencia:${sug}` : buscar.trim();
  useEffect(() => {
    const v = ++ver.current; const t = setTimeout(() => {
      apiGestion.nodos(consulta, null).then((r) => { if (v === ver.current) { setD(r); setItems(r.items); setError(null); } })
        .catch((e) => { if (v === ver.current) setError(err(e, "La bandeja de nodos por clasificar es del supervisor de distribución y del administrador.")); });
    }, 250);
    return () => clearTimeout(t);
  }, [consulta, vez]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  return (
    <>
      <p className="tec-ayuda dan-pad-x">Nodos del modelo de acueducto sin activo (S, J, M, Pila, Módulos). Abra la ficha preliminar para ver qué es cada uno; luego confirme la sugerencia, póngale un nombre visible o cree el activo que es: queda enlazado al nodo y el nombre del modelo no cambia.</p>
      {d ? <p className="dan-pad-x gest-grupos">{d.grupos.map((g) => <span key={g.grupo} className="itv-etiqueta">{g.grupo}: {nf(g.n)}</span>)}</p> : null}
      {d?.grupos_no_crear?.length ? <GruposNoCrear grupos={d.grupos_no_crear} onListo={(t) => { setAviso({ ok: true, t }); setVez((v) => v + 1); }} /> : null}
      {d?.sugerencias?.length ? (
        <div className="dan-fila dan-pad-x" role="group" aria-label="Filtrar por la sugerencia del modelo">
          <button type="button" className="dan-opcion" aria-pressed={sug === null} onClick={() => setSug(null)}>Todos</button>
          {d.sugerencias.map((s) => <button key={s.accion} type="button" className="dan-opcion" aria-pressed={sug === s.accion} data-sugerencia={s.accion}
            onClick={() => { setSug(s.accion); setBuscar(""); }}>{SUGERENCIA[s.accion] ?? s.accion}: {nf(s.n)}</button>)}
        </div>) : null}
      <div className="dan-pad-x"><div className="tec-campo"><label htmlFor="nd-buscar">Buscar nodo</label>
        <input id="nd-buscar" type="text" maxLength={60} value={buscar} placeholder="Nombre del modelo, nombre visible, ID o lo que es (válvula, cálculo…)" onChange={(e) => { setSug(null); setBuscar(e.target.value); }} /></div></div>
      {aviso ? <p className={`tec-aviso ${aviso.ok ? "tec-aviso-info" : "tec-aviso-error"} dan-pad-x`} role="status">{aviso.t}
        {aviso.activo ? <> <button type="button" className="tec-enlace" onClick={() => onFicha(aviso.activo!)}>Ver la ficha de {aviso.activo}</button></> : null}
        {" "}<button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {!d ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !items.length ? <section className="tec-tarjeta"><p className="red-vacio">{buscar ? "Ningún nodo coincide." : "No quedan nodos por clasificar."}</p></section>
        : <>
            <p className="tec-ayuda dan-pad-x">{nf(d.total)} nodo{d.total === 1 ? "" : "s"}{sug ? " con esa sugerencia" : buscar ? " con esa búsqueda" : ""}.</p>
            {items.map((n) => <NodoItem key={n.nodo_id} n={n} admin={admin} tipos={d.tipos.filter((t) => t.sistema === n.sistema)}
              onListo={(t, activo) => { setAviso({ ok: true, t, activo }); setVez((v) => v + 1); }} />)}
            {items.length < d.total ? <div className="dan-pad-x"><button type="button" className="tec-boton-sec" onClick={() => apiGestion.nodos(consulta, items[items.length - 1].nodo_id)
              .then((r) => setItems([...items, ...r.items])).catch(() => {})}>Cargar más ({nf(d.total - items.length)})</button></div> : null}
          </>}
    </>
  );
}

function GruposNoCrear({ grupos, onListo }: { grupos: NonNullable<NodosPorClasificar["grupos_no_crear"]>; onListo: (t: string) => void }) {
  const [abierto, setAbierto] = useState<GrupoNoCrear | null>(null);
  const [vista, setVista] = useState<VistaPreviaGrupo | null>(null);
  const [motivo, setMotivo] = useState(""); const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null); const [enviando, setEnviando] = useState(false);
  const ver = (g: GrupoNoCrear) => { setAbierto(g); setVista(null); setMsg(null); setMotivo("");
    apiGestion.grupoVistaPrevia(g).then(setVista).catch((e) => setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador clasifican nodos.") })); };
  async function confirmar() {
    if (!vista) return;
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    setEnviando(true); setMsg(null);
    try {
      const r = await apiGestion.grupoConfirmar(vista.grupo, vista.huella, motivo.trim());
      setAbierto(null); setVista(null); onListo(`Se clasificaron ${nf(r.n)} nodos de una vez: ${r.texto?.replace(/: no crear activo$/, "") ?? r.grupo}. No se creó ningún activo.`);
    } catch (e) {
      setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador clasifican nodos.") });
      if (e instanceof Error && /cambió desde la vista previa/.test(e.message)) apiGestion.grupoVistaPrevia(vista.grupo).then(setVista).catch(() => {});
    } finally { setEnviando(false); }
  }
  return (
    <section className="tec-tarjeta itv-bandeja nodo-grupos" aria-label="Confirmar por grupo">
      <h2>Confirmar por grupo</h2>
      <p className="tec-ayuda">Solo los grupos que el modelo sugiere «no crear activo». Primero vea cuáles son; luego confirme con un motivo. No se crea ningún activo.</p>
      {grupos.map((g) => (
        <div key={g.grupo} className="nodo-grupo" data-grupo-nodos={g.grupo}>
          <div className="nodo-grupo-cab"><span className="nodo-grupo-txt">{g.texto.replace(/: no crear activo$/, "")} · <strong>{nf(g.n)}</strong></span>
            {abierto !== g.grupo ? <button type="button" className="tec-boton-sec" onClick={() => ver(g.grupo)}>Ver vista previa</button> : null}</div>
          {abierto === g.grupo ? (
            <div className="itv-nuevo">
              {!vista ? (msg ? null : <p className="tec-sub" role="status">Cargando la vista previa…</p>) : (
                <>
                  <p className="nodo-sug nodo-sug-no_crear" role="note">Se van a clasificar <strong>{nf(vista.n)}</strong> nodos como «propuesto por el Plan, no instalado». Salen de la bandeja; no se crea ningún activo.</p>
                  <p className="tec-ayuda">Por sector: {vista.por_sector.map((s) => `${s.sector === null ? "fuera de los sectores" : `sector ${s.sector}`}: ${nf(s.n)}`).join(" · ")}</p>
                  <p className="tec-ayuda nodo-muestra">{vista.muestra.map((m) => m.nombre).join(", ")}{vista.n > vista.muestra.length ? ` y ${nf(vista.n - vista.muestra.length)} más` : ""}</p>
                  <CampoMotivo id={`ng-${g.grupo}`} valor={motivo} onCambio={setMotivo} />
                </>)}
              <Aviso msg={msg} />
              <div className="tec-acciones">
                {vista && vista.n > 0 ? <button type="button" className="tec-boton itv-guardar" disabled={enviando} onClick={confirmar}>{enviando ? "Guardando…" : `Confirmar ${nf(vista.n)} nodos`}</button> : null}
                <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => { setAbierto(null); setVista(null); setMsg(null); }}>Cancelar</button>
              </div>
            </div>) : null}
        </div>))}
    </section>
  );
}

function NodoItem({ n, tipos, onListo, admin }: { n: NodoPorClasificar; tipos: NodosPorClasificar["tipos"]; onListo: (t: string, activo?: string) => void; admin: boolean }) {
  const [modo, setModo] = useState<null | "alias" | "activo" | "clasificar">(null);
  const [pre, setPre] = useState(false);
  const [claseNodo, setClaseNodo] = useState<keyof typeof CLASE_NODO>(n.sugerencia?.clase ?? "nodo_calculo");
  const [alias, setAlias] = useState(n.alias ?? ""); const [prefijo, setPrefijo] = useState(n.sugerencia?.accion === "crear" ? n.sugerencia.prefijo ?? "" : ""); const [clase, setClase] = useState(""); const [nombre, setNombre] = useState("");
  const [motivo, setMotivo] = useState(""); const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null); const [enviando, setEnviando] = useState(false);
  const tipo = tipos.find((t) => t.prefijo === prefijo);
  async function enviar() {
    if (motivo.trim().length < MOTIVO_MIN) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    setEnviando(true); setMsg(null);
    try {
      if (modo === "alias") {
        if (alias.trim() && (alias.trim().length < 2 || alias.trim().length > 60)) { setMsg({ ok: false, t: "El nombre visible lleva de 2 a 60 caracteres." }); return; }
        await apiGestion.aliasFijar("nodo", String(n.nodo_id), alias.trim() || null, motivo.trim());
        onListo(alias.trim() ? `${n.nombre_modelo ?? n.llave_modelo} se ve ahora como «${alias.trim()}».` : `${n.nombre_modelo ?? n.llave_modelo} volvió a su nombre del modelo.`);
      } else if (modo === "clasificar") {
        await apiGestion.nodoClasificar(n.nodo_id, claseNodo, motivo.trim());
        onListo(`${n.nombre_modelo ?? n.llave_modelo} quedó clasificado: ${CLASE_NODO[claseNodo].toLowerCase()}. Sale de la bandeja; no se creó ningún activo.`);
      } else {
        if (!tipo) { setMsg({ ok: false, t: "Elija el tipo de activo." }); return; }
        if (tipo.pide_clase && !clase) { setMsg({ ok: false, t: `Elija la clase (${tipo.nombre}).` }); return; }
        const r = await apiGestion.nodoCrearActivo(n.nodo_id, tipo.prefijo, clase || null, nombre.trim() || null, motivo.trim());
        onListo(`${r.nombre_modelo} es ahora ${r.activo} (${r.tipo}).`, r.activo);
      }
    } catch (e) { setMsg({ ok: false, t: err(e, "Solo el supervisor de distribución o el administrador clasifican nodos.") }); } finally { setEnviando(false); }
  }
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={`Nodo ${n.nombre_modelo ?? n.llave_modelo}`}>
      <h2>{n.nombre_visible} {n.alias ? <span className="itv-etiqueta">Modelo: {n.nombre_modelo}</span> : null}</h2>
      <p className="tec-ayuda">ID del modelo {n.llave_modelo} · {n.tramos} tramo{n.tramos === 1 ? "" : "s"} · {n.lat}, {n.lon}</p>
      {n.que_es || n.tipo_modelo ? <p className="nodo-sug-linea">En el modelo: <strong>{n.que_es ?? n.tipo_modelo}</strong></p> : null}
      {n.sugerencia ? <p className={`nodo-sug nodo-sug-${n.sugerencia.accion}`} role="note"><strong>Sugerencia:</strong> {n.sugerencia.texto}</p> : null}
      {pre ? <NodoPreliminar nodoId={n.nodo_id} onCerrar={() => setPre(false)} /> : null}
      {!modo ? <div className="dash-acciones">
          {!pre ? <button type="button" className="tec-boton-sec" onClick={() => setPre(true)}>Ver ficha preliminar</button> : null}
          {n.sugerencia?.clase ? <button type="button" className="tec-boton-sec" onClick={() => { setClaseNodo(n.sugerencia!.clase!); setModo("clasificar"); }}>Confirmar la sugerencia</button>
            : <button type="button" className="tec-boton-sec" onClick={() => setModo("clasificar")}>No es un activo</button>}
          {admin ? <button type="button" className="tec-boton-sec" onClick={() => setModo("alias")}>Nombre visible</button> : null}
          <button type="button" className="tec-boton-sec" onClick={() => setModo("activo")}>Crear el activo</button></div>
        : <div className="itv-nuevo">
            {modo === "clasificar" ? <>
                <div className="tec-campo"><label htmlFor={`nk-${n.nodo_id}`}>Cómo queda el nodo</label>
                  <select id={`nk-${n.nodo_id}`} value={claseNodo} onChange={(e) => setClaseNodo(e.target.value as keyof typeof CLASE_NODO)}>
                    {(Object.keys(CLASE_NODO) as (keyof typeof CLASE_NODO)[]).map((k) => <option key={k} value={k}>{CLASE_NODO[k]}</option>)}</select></div>
                <p className="tec-ayuda">No se crea ningún activo y el nodo sale de esta bandeja. Queda registrado quién lo confirmó y por qué.</p>
              </> : modo === "alias" ? <div className="tec-campo"><label htmlFor={`na-${n.nodo_id}`}>Nombre visible (vacío = el del modelo)</label>
                <input id={`na-${n.nodo_id}`} type="text" maxLength={60} value={alias} onChange={(e) => setAlias(e.target.value)} placeholder={n.nombre_modelo ?? ""} /></div>
              : <>
                  <div className="tec-campo"><label htmlFor={`nt-${n.nodo_id}`}>Tipo de activo</label>
                    <select id={`nt-${n.nodo_id}`} value={prefijo} onChange={(e) => { setPrefijo(e.target.value); setClase(""); }}><option value="">Elija…</option>
                      {tipos.map((t) => <option key={t.prefijo} value={t.prefijo}>{t.nombre} ({t.prefijo})</option>)}</select></div>
                  {tipo && tipo.clases.length ? <div className="tec-campo"><label htmlFor={`nc-${n.nodo_id}`}>Clase{tipo.pide_clase ? "" : " (opcional)"}</label>
                    <select id={`nc-${n.nodo_id}`} value={clase} onChange={(e) => setClase(e.target.value)}><option value="">Elija…</option>
                      {tipo.clases.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div> : null}
                  <div className="tec-campo"><label htmlFor={`nn-${n.nodo_id}`}>Nombre (opcional)</label>
                    <input id={`nn-${n.nodo_id}`} type="text" maxLength={120} value={nombre} onChange={(e) => setNombre(e.target.value)} /></div>
                  <p className="tec-ayuda">Se crea en la posición del nodo, con «{n.nombre_modelo}» como código anterior.</p>
                </>}
            <CampoMotivo id={`nm-${n.nodo_id}`} valor={motivo} onCambio={setMotivo} />
            <Aviso msg={msg} />
            <div className="tec-acciones">
              <button type="button" className="tec-boton itv-guardar" disabled={enviando} onClick={enviar}>{enviando ? "Guardando…" : modo === "alias" ? "Guardar el nombre" : modo === "clasificar" ? "Confirmar" : "Crear el activo"}</button>
              <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => { setModo(null); setMsg(null); }}>Cancelar</button>
            </div>
          </div>}
    </section>
  );
}
