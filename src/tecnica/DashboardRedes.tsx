import { useEffect, useState } from "react";
import "./ficha.css";
import "./dano.css";
import "./intervencion.css";
import "./dashboard.css";
import { CabeceraDashboard } from "./CabeceraDashboard";
import { apiDano, apiDash, apiItv, type DanoLista, type FormularioDano as DefDano, type IntervencionLista, type ReporteBot } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { FichaActivo } from "./FichaActivo";
import { NoIdentificados, Recursos } from "./IntervencionesSupervisor";
import { Catalogo, Descargas, Graficas, Nodos, Parametros, Personal } from "./DashboardGestion";
import { CargueCapas } from "./cargue/CargueCapas";

// Dashboard distribución (Técnica fase 1, Corte 4a; §7 y §16 de la bitácora). Para el supervisor de distribución (ver_dashboard_redes) y el administrador:
// el servidor lo vuelve a verificar en cada ruta. Pestañas de este corte: no identificados (asociar o crear el activo), intervenciones (recursos por completar,
// ocultar o anular con motivo), daños y fallas (ocultar, reincluir o reabrir con motivo; el nombre del tercero con lectura auditada) y reportes del bot.
// Corte 4b (DashboardGestion.tsx): Personal, Gráficas, Descargas, Catálogo, Parámetros y, solo para el administrador, Nodos por clasificar.
// Corte 5c (cargue/CargueCapas.tsx): Cargue de capas (el supervisor lo lee; carga el administrador). Nada se borra: todo es un evento con motivo.

type Pestana = "no_identificados" | "intervenciones" | "danos" | "bot" | "graficas" | "descargas" | "personal" | "cargue" | "catalogo" | "parametros" | "nodos";
const PESTANAS: { c: Pestana; n: string; admin?: boolean }[] = [{ c: "no_identificados", n: "No identificados" }, { c: "intervenciones", n: "Intervenciones" },
  { c: "danos", n: "Daños y fallas" }, { c: "bot", n: "Reportes del bot" }, { c: "graficas", n: "Gráficas" }, { c: "descargas", n: "Descargas" }, { c: "personal", n: "Personal" },
  { c: "cargue", n: "Cargue de capas" }, { c: "catalogo", n: "Catálogo" }, { c: "parametros", n: "Parámetros" }, { c: "nodos", n: "Nodos por clasificar", admin: true }];
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const ESTADO: Record<string, string> = { reportado: "Reportado", en_atencion: "En atención", atendido: "Atendido", oculto: "Oculto", cerrada: "Cerrada", anulada: "Anulada", oculta: "Oculta",
  recibido: "Recibido", descartado: "Descartado" };
const err = (e: unknown, sin: string) => (e instanceof ErrorTec && e.tipo === "permiso" ? sin : e instanceof Error ? e.message : "No se pudo completar.");

// §34: el mismo armado y estilo que el Dashboard PTAP (encabezado común, pestañas, cuerpo); la única diferencia es el color verde oscuro (tdash-verde).
export function DashboardRedes({ correo, selector, onVolver, onGeovisor }: { correo: string; selector?: React.ReactNode; onVolver: () => void; onGeovisor?: () => void }) {
  const [pestana, setPestana] = useState<Pestana>("no_identificados");
  const [ficha, setFicha] = useState<string | null>(null);
  const [admin, setAdmin] = useState(false);
  const [rotulo, setRotulo] = useState("");
  useEffect(() => { apiDash.miPerfil().then((p) => { setAdmin(p.perfil === "admin"); setRotulo(p.perfil === "admin" ? "Administrador" : "Supervisor de distribución"); }).catch(() => {}); }, []);
  if (ficha) return <FichaActivo codigo={ficha} onAbrir={setFicha} onVolver={() => setFicha(null)} rotuloVolver="Volver al Dashboard distribución" />;
  return (
    <div className="tdash tdash-verde">
      <CabeceraDashboard titulo="Dashboard distribución" sesion={rotulo ? `${correo} · ${rotulo}` : correo} onVolver={onVolver} onGeovisor={onGeovisor} selector={selector} etiqueta="Pestañas del Dashboard distribución"
        pestanas={PESTANAS.filter((p) => !p.admin || admin).map((p) => ({ clave: p.c, titulo: p.n }))} activa={pestana} onElegir={(c) => setPestana(c as Pestana)} />
      <div className="tdash-cuerpo dan itv dash-redes">
      {pestana === "no_identificados" ? <NoIdentificados onFicha={setFicha} /> : null}
      {pestana === "intervenciones" ? <Intervenciones onFicha={setFicha} /> : null}
      {pestana === "danos" ? <Danos onFicha={setFicha} /> : null}
      {pestana === "bot" ? <ReportesBot /> : null}
      {pestana === "graficas" ? <Graficas onFicha={setFicha} /> : null}
      {pestana === "descargas" ? <Descargas /> : null}
      {pestana === "personal" ? <Personal /> : null}
      {pestana === "cargue" ? <CargueCapas /> : null}
      {pestana === "catalogo" ? <Catalogo /> : null}
      {pestana === "parametros" ? <Parametros /> : null}
      {pestana === "nodos" && admin ? <Nodos onFicha={setFicha} /> : null}
      </div>
    </div>
  );
}

/** Acción con motivo (ocultar, reabrir, anular…): botón que abre el motivo y lo envía. */
function ConMotivo({ rotulo, id, onEnviar, avisar }: { rotulo: string; id: string; onEnviar: (motivo: string) => Promise<string>; avisar?: (t: string) => void }) {
  const [abierto, setAbierto] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [enviando, setEnviando] = useState(false);
  if (!abierto) return <button type="button" className="tec-boton-sec" onClick={() => { setAbierto(true); setMsg(null); }}>{rotulo}</button>;
  return (
    <div className="dash-motivo">
      <label htmlFor={id}>Motivo ({rotulo.toLowerCase()})</label>
      <input id={id} type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por qué (10 caracteres o más)" />
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      <div className="tec-acciones">
        <button type="button" className="tec-boton itv-guardar" disabled={enviando} onClick={async () => {
          if (motivo.trim().length < 10) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
          setEnviando(true); setMsg(null);
          try { const t = await onEnviar(motivo.trim()); if (avisar) { avisar(t); setAbierto(false); setMotivo(""); } else setMsg({ ok: true, t }); } catch (e) { setMsg({ ok: false, t: err(e, "No tiene permiso para esta acción.") }); } finally { setEnviando(false); }
        }}>{enviando ? "Guardando…" : `Confirmar: ${rotulo.toLowerCase()}`}</button>
        <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => setAbierto(false)}>Cancelar</button>
      </div>
    </div>
  );
}

// ---------- Intervenciones ----------
function Intervenciones({ onFicha }: { onFicha: (c: string) => void }) {
  const [vista, setVista] = useState<"recursos" | "recientes">("recursos");
  const [lista, setLista] = useState<IntervencionLista[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<string | null>(null);
  useEffect(() => {
    if (vista !== "recientes") return;
    setLista(null); setError(null);
    apiItv.lista("recientes").then((r) => setLista(r.intervenciones)).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven las intervenciones.")));
  }, [vista, vez]);
  return (
    <>
      <div className="dan-fila dan-pad-x" role="group" aria-label="Qué intervenciones ver">
        <button type="button" className="dan-opcion" aria-pressed={vista === "recursos"} onClick={() => setVista("recursos")}>Recursos por completar</button>
        <button type="button" className="dan-opcion" aria-pressed={vista === "recientes"} onClick={() => setVista("recientes")}>Recientes</button>
      </div>
      {aviso ? <p className="tec-aviso tec-aviso-info dan-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {vista === "recursos" ? <Recursos onFicha={onFicha} /> : error ? <section className="tec-tarjeta" role="alert"><p>{error}</p></section>
        : !lista ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !lista.length ? <section className="tec-tarjeta"><p className="red-vacio">No hay intervenciones.</p></section>
        : lista.map((i) => (
          <section key={i.codigo} className="tec-tarjeta itv-bandeja" aria-label={i.codigo}>
            <h2>{i.codigo} · {i.tipo} <span className="itv-etiqueta">{ESTADO[i.estado] ?? i.estado}</span></h2>
            <p className="red-texto">{i.activo ? <button type="button" className="tec-enlace" onClick={() => onFicha(i.activo!)}>{i.activo}</button> : <>«{i.no_identificado}» (no identificado)</>}
              {i.dano ? <> · atiende {i.dano}</> : null} · {i.ejecutor === "emdupar" ? "EMDUPAR" : `contratista${i.contratista ? ` ${i.contratista}` : ""}`}</p>
            <p className="tec-ayuda">{fecha(i.t_fin)} · {i.autor} · {i.fotos} foto(s) · recursos {i.recursos === "completos" ? "completos" : "por completar"}</p>
            <div className="dash-acciones">
              <ConMotivo rotulo="Ocultar" id={`oc-${i.codigo}`} avisar={setAviso} onEnviar={async (m) => { const r = await apiDash.intervencionEvento(i.codigo, "ocultar", m); setVez((v) => v + 1); return `${r.codigo} quedó oculta.`; }} />
              {i.estado === "cerrada" ? <ConMotivo rotulo="Anular" id={`an-${i.codigo}`} avisar={setAviso} onEnviar={async (m) => { const r = await apiDash.intervencionEvento(i.codigo, "anulada", m); setVez((v) => v + 1); return `${r.codigo} quedó anulada.${r.aviso ? " " + r.aviso : ""}`; }} /> : null}
            </div>
          </section>))}
    </>
  );
}

// ---------- Daños y fallas ----------
const FILTROS_DANO = [{ c: "abiertos", n: "Abiertos" }, { c: "no_identificados", n: "No identificados" }, { c: "ocultos", n: "Ocultos" }, { c: "todos", n: "Todos" }] as const;
function Danos({ onFicha }: { onFicha: (c: string) => void }) {
  const [filtro, setFiltro] = useState<(typeof FILTROS_DANO)[number]["c"]>("abiertos");
  const [lista, setLista] = useState<DanoLista[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [terceros, setTerceros] = useState<Record<string, string>>({});
  const [aviso, setAviso] = useState<string | null>(null);

  useEffect(() => {
    setLista(null); setError(null);
    apiDash.danos(filtro).then((r) => setLista(r.danos)).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven los daños.")));
  }, [filtro, vez]);
  const refrescar = () => setVez((v) => v + 1);
  return (
    <>
      <div className="dan-fila dan-pad-x" role="group" aria-label="Filtro de daños">{FILTROS_DANO.map((f) => (
        <button key={f.c} type="button" className="dan-opcion" aria-pressed={filtro === f.c} onClick={() => setFiltro(f.c)}>{f.n}</button>))}</div>
      {aviso ? <p className="tec-aviso tec-aviso-info dan-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {error ? <section className="tec-tarjeta" role="alert"><p>{error}</p></section>
        : !lista ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !lista.length ? <section className="tec-tarjeta"><p className="red-vacio">No hay daños ni fallas con ese filtro.</p></section>
        : lista.map((d) => (
          <section key={d.codigo} className="tec-tarjeta itv-bandeja" aria-label={d.codigo}>
            <h2><span className={`itv-etiqueta itv-etiqueta-dano`}>{d.clase === "dano" ? "Daño" : "Falla"}</span> {d.codigo} · {d.tipo} <span className="itv-etiqueta">{ESTADO[d.estado] ?? d.estado}</span></h2>
            <p className="red-texto">{d.activo ? <button type="button" className="tec-enlace" onClick={() => onFicha(d.activo!)}>{d.activo}</button> : <>«{d.no_identificado}» (no identificado)</>}
              {" "}· {d.sistema} · riesgo {d.riesgo}{d.sector ? ` · sector ${d.sector}` : ""}</p>
            <p className="tec-ayuda">Detectado {fecha(d.t_detectado)} · {d.autor} · {d.fotos} foto(s) · {d.intervenciones} intervención(es){d.origen === "bot" ? " · del bot" : ""}</p>
            {d.tiene_tercero ? (
              terceros[d.codigo] ? <p className="red-texto">Tercero: <strong>{terceros[d.codigo]}</strong> <span className="tec-ayuda">(dato personal; la lectura quedó registrada)</span></p>
                : <button type="button" className="tec-enlace" onClick={() => apiDash.danoTercero(d.codigo).then((r) => setTerceros((t) => ({ ...t, [d.codigo]: r.tercero }))).catch(() => {})}>Ver el nombre o la placa del tercero (queda registrado)</button>
            ) : null}
            <div className="dash-acciones">
              {d.estado !== "oculto" ? <ConMotivo rotulo="Ocultar" id={`do-${d.codigo}`} avisar={setAviso} onEnviar={async (m) => { await apiDash.danoEvento(d.codigo, "ocultar", m); refrescar(); return `${d.codigo} quedó oculto.`; }} />
                : <ConMotivo rotulo="Reincluir" id={`dr-${d.codigo}`} avisar={setAviso} onEnviar={async (m) => { await apiDash.danoEvento(d.codigo, "reincluir", m); refrescar(); return `${d.codigo} volvió a estar visible.`; }} />}
              {d.estado === "atendido" ? <ConMotivo rotulo="Reabrir" id={`da-${d.codigo}`} avisar={setAviso} onEnviar={async (m) => { await apiDash.danoEvento(d.codigo, "reabrir", m); refrescar(); return `${d.codigo} quedó en atención.`; }} /> : null}
            </div>
          </section>))}
    </>
  );
}

// ---------- Reportes del bot (N-14) ----------
function ReportesBot() {
  const [filtro, setFiltro] = useState<"pendientes" | "todos">("pendientes");
  const [lista, setLista] = useState<ReporteBot[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [def, setDef] = useState<DefDano | null>(null);
  useEffect(() => { apiDano.formulario().then(setDef).catch(() => {}); }, []);
  useEffect(() => {
    setLista(null); setError(null);
    apiDash.reportesBot(filtro).then((r) => setLista(r.reportes)).catch((e) => setError(err(e, "Solo el supervisor de distribución o el administrador ven los reportes del bot.")));
  }, [filtro, vez]);
  return (
    <>
      <div className="dan-fila dan-pad-x" role="group" aria-label="Filtro de reportes">
        <button type="button" className="dan-opcion" aria-pressed={filtro === "pendientes"} onClick={() => setFiltro("pendientes")}>Pendientes</button>
        <button type="button" className="dan-opcion" aria-pressed={filtro === "todos"} onClick={() => setFiltro("todos")}>Todos</button>
      </div>
      <p className="tec-ayuda dan-pad-x">Los reportes llegan del bot de Telegram (y luego WhatsApp) cuando se conecte, sin nombre ni teléfono de quien reporta.</p>
      {error ? <section className="tec-tarjeta" role="alert"><p>{error}</p></section>
        : !lista ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !lista.length ? <section className="tec-tarjeta"><p className="red-vacio">{filtro === "pendientes" ? "No hay reportes del bot pendientes." : "Todavía no hay reportes del bot."}</p></section>
        : lista.map((r) => <ItemBot key={r.id} r={r} def={def} onListo={() => setTimeout(() => setVez((v) => v + 1), 900)} />)}
    </>
  );
}

function ItemBot({ r, def, onListo }: { r: ReporteBot; def: DefDano | null; onListo: () => void }) {
  const [convertir, setConvertir] = useState(false);
  const [sistema, setSistema] = useState(""); const [tipo, setTipo] = useState(""); const [riesgo, setRiesgo] = useState(""); const [activo, setActivo] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const tipoSel = def?.tipos.find((t) => t.codigo === tipo);
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={`Reporte ${r.radicado}`}>
      <h2>{r.radicado} · {r.tipo} <span className="itv-etiqueta">{ESTADO[r.estado_bot] ?? r.estado_bot}</span></h2>
      <p className="red-texto">{r.descripcion ?? "Sin descripción"}{r.direccion ? ` · ${r.direccion}` : ""}</p>
      <p className="tec-ayuda">{fecha(r.recibido_en)} · {r.canal} · {r.fotos} foto(s){r.lat !== null ? ` · ${r.lat}, ${r.lon}` : " · sin ubicación"}{r.dano ? ` · daño ${r.dano}` : ""}</p>
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      {r.estado_bot === "recibido" ? (
        <>
          {convertir && def ? (
            <div className="itv-nuevo">
              <div className="tec-campo"><label htmlFor={`bs-${r.id}`}>Sistema</label>
                <select id={`bs-${r.id}`} value={sistema} onChange={(e) => { setSistema(e.target.value); setTipo(""); }}><option value="">Elija…</option>{def.sistemas.map((s) => <option key={s.codigo} value={s.codigo}>{s.nombre}</option>)}</select></div>
              <div className="tec-campo"><label htmlFor={`bt-${r.id}`}>Qué pasó</label>
                <select id={`bt-${r.id}`} value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="">Elija…</option>
                  {def.tipos.filter((t) => !sistema || t.sistemas.includes(sistema)).map((t) => <option key={t.codigo} value={t.codigo}>{t.clase === "dano" ? "Daño" : "Falla"}: {t.nombre}</option>)}</select></div>
              <div className="tec-campo"><label htmlFor={`br-${r.id}`}>Riesgo</label>
                <select id={`br-${r.id}`} value={riesgo} onChange={(e) => setRiesgo(e.target.value)}><option value="">Elija…</option><option value="bajo">Bajo</option><option value="medio">Medio</option><option value="alto">Alto</option></select></div>
              <div className="tec-campo"><label htmlFor={`ba-${r.id}`}>Activo (código, opcional)</label><input id={`ba-${r.id}`} type="text" maxLength={20} value={activo} onChange={(e) => setActivo(e.target.value)} /></div>
              <div className="tec-acciones">
                <button type="button" className="tec-boton itv-guardar" onClick={async () => {
                  if (!sistema || !tipoSel || !riesgo) { setMsg({ ok: false, t: "Elija el sistema, qué pasó y el riesgo." }); return; }
                  try { const x = await apiDash.reporteConvertir(r.id, { clase: tipoSel.clase, tipo, sistema, riesgo, activo: activo.trim() || null }); setMsg({ ok: true, t: `Quedó como el daño ${x.dano_codigo}.` }); onListo(); }
                  catch (e) { setMsg({ ok: false, t: err(e, "No tiene permiso para esta acción.") }); }
                }}>Convertir en daño o falla</button>
                <button type="button" className="tec-boton-sec" onClick={() => setConvertir(false)}>Cancelar</button>
              </div>
            </div>
          ) : (
            <div className="dash-acciones">
              <button type="button" className="tec-boton-sec" onClick={() => setConvertir(true)}>Convertir en daño o falla</button>
              <ConMotivo rotulo="Descartar" id={`bd-${r.id}`} onEnviar={async (m) => { await apiDash.reporteDescartar(r.id, m); onListo(); return `${r.radicado} quedó descartado.`; }} />
            </div>
          )}
        </>
      ) : null}
    </section>
  );
}
