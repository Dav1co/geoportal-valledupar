import { useCallback, useEffect, useState } from "react";
import "./ficha.css";
import "./dano.css";
import "./intervencion.css";
import { apiDano, apiDash, apiItv, type ActivoUbicado, type IntervencionLista, type NoIdentificado, type TipoNuevo } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { FichaActivo } from "./FichaActivo";

// Supervisión de intervenciones (Corte 3a), solo supervisor y administrador (el servidor lo vuelve a verificar en cada ruta).
// · «No identificados»: intervenciones y daños sin activo, con los activos más cercanos propuestos; «Asociar» deja un evento con motivo (no se reescribe nada).
// · «Recursos por completar»: el operario marcó solo quién aporta; aquí se ponen el valor o el porcentaje y el soporte (D-8), como una versión nueva.
// En el Corte 4 estas dos bandejas pasan a las pestañas del Dashboard distribución.

type Pestana = "no_identificados" | "recursos";
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const numeroONulo = (t: string) => { const v = t.trim().replace(/\./g, "").replace(",", "."); if (!v) return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };
const decimalONulo = (t: string) => { const v = t.trim().replace(",", "."); if (!v) return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };
const pesos = (n: number) => n.toLocaleString("es-CO", { maximumFractionDigits: 0 });

export function IntervencionesSupervisor({ onVolver }: { onVolver: () => void }) {
  const [pestana, setPestana] = useState<Pestana>("no_identificados");
  const [ficha, setFicha] = useState<string | null>(null);
  if (ficha) return <FichaActivo codigo={ficha} onAbrir={setFicha} onVolver={() => setFicha(null)} rotuloVolver="Volver a la supervisión" />;
  return (
    <div className="dan itv">
      <button type="button" className="red-volver itv-volver" onClick={onVolver}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
        Volver a Técnica
      </button>
      <header className="dan-cabeza itv-cabeza">
        <h1>Intervenciones · supervisión</h1>
        <p>Bandeja de activos no identificados y recursos por completar. En el Corte 4 pasan al Dashboard distribución.</p>
      </header>
      <div className="dan-fila dan-pad-x" role="tablist" aria-label="Bandejas">
        <button type="button" role="tab" className="dan-opcion" aria-selected={pestana === "no_identificados"} aria-pressed={pestana === "no_identificados"} onClick={() => setPestana("no_identificados")}>No identificados</button>
        <button type="button" role="tab" className="dan-opcion" aria-selected={pestana === "recursos"} aria-pressed={pestana === "recursos"} onClick={() => setPestana("recursos")}>Recursos por completar</button>
      </div>
      {pestana === "no_identificados" ? <NoIdentificados onFicha={setFicha} /> : <Recursos onFicha={setFicha} />}
    </div>
  );
}

export function NoIdentificados({ onFicha }: { onFicha: (c: string) => void }) {
  const [datos, setDatos] = useState<{ radio_m: number; pendientes: number; items: NoIdentificado[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [tipos, setTipos] = useState<TipoNuevo[]>([]);      // tipos de PUNTO que se pueden crear desde la bandeja (Corte 4a)
  useEffect(() => { apiItv.formulario().then((f) => setTipos(f.tipos_nuevo.filter((t) => t.geometria === "punto"))).catch(() => {}); }, []);
  const cargar = useCallback(() => {
    setError(null);
    apiItv.noIdentificados().then(setDatos).catch((e) => setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor o el administrador ven esta bandeja." : e instanceof Error ? e.message : "No se pudo cargar."));
  }, []);
  useEffect(cargar, [cargar, vez]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!datos) return <p className="tec-sub dan-pad" role="status">Cargando la bandeja…</p>;
  if (!datos.items.length) return <section className="tec-tarjeta"><p className="red-vacio">No hay intervenciones ni daños con el activo sin identificar.</p></section>;
  return (
    <>
      <p className="tec-sub dan-pad-x">{datos.pendientes} pendiente(s). Se proponen los activos del mismo sistema a {datos.radio_m} m o menos.</p>
      {datos.items.map((n) => <ItemNoIdentificado key={`${n.clase}-${n.codigo}`} n={n} tipos={tipos.filter((t) => t.sistema === n.sistema)} onFicha={onFicha} onListo={() => setVez((v) => v + 1)} />)}
    </>
  );
}

function ItemNoIdentificado({ n, tipos, onFicha, onListo }: { n: NoIdentificado; tipos: TipoNuevo[]; onFicha: (c: string) => void; onListo: () => void }) {
  const [modo, setModo] = useState<"asociar" | "crear">("asociar");
  const [nuevoTipo, setNuevoTipo] = useState(""); const [nuevoClase, setNuevoClase] = useState(""); const [nuevoNombre, setNuevoNombre] = useState("");
  const tipoSel = tipos.find((t) => t.prefijo === nuevoTipo);
  const [activo, setActivo] = useState<string>(n.propuestos[0]?.codigo ?? "");
  const [motivo, setMotivo] = useState("");
  const [buscar, setBuscar] = useState(""); const [res, setRes] = useState<ActivoUbicado[] | null>(null);
  const [estado, setEstado] = useState<"" | "enviando">("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  async function asociar() {
    if (modo === "asociar" && !activo) { setMsg({ ok: false, t: "Elija el activo." }); return; }
    if (modo === "crear" && !tipoSel) { setMsg({ ok: false, t: "Elija el tipo del activo nuevo." }); return; }
    if (modo === "crear" && tipoSel?.clase_obligatoria && !nuevoClase) { setMsg({ ok: false, t: "Elija la clase del activo nuevo." }); return; }
    if (motivo.trim().length < 10) { setMsg({ ok: false, t: "Escriba el motivo (10 caracteres o más)." }); return; }
    setEstado("enviando"); setMsg(null);
    try {
      const r = modo === "asociar" ? await apiItv.asociar(n.clase, n.codigo, activo, motivo.trim())
        : await apiDash.crearActivoBandeja(n.clase, n.codigo, nuevoTipo, nuevoClase || null, nuevoNombre.trim() || null, motivo.trim());
      setMsg({ ok: true, t: modo === "asociar" ? `${r.codigo} quedó asociado a ${r.activo}.` : `Se creó ${r.activo} («por verificar») y ${r.codigo} quedó sobre él.` }); setTimeout(onListo, 900);
    }
    catch (e) { setMsg({ ok: false, t: e instanceof Error ? e.message : "No se pudo asociar." }); }
    finally { setEstado(""); }
  }
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={`${n.codigo}: ${n.que_es}`}>
      <h2><span className={`itv-etiqueta itv-etiqueta-${n.clase}`}>{n.clase === "intervencion" ? "Intervención" : "Daño"}</span> {n.codigo}</h2>
      <p className="red-texto"><strong>«{n.que_es}»</strong> · {n.resumen} · {n.sistema}</p>
      <p className="tec-ayuda">{fecha(n.cuando)} · {n.autor} · {n.lat.toFixed(5)}, {n.lon.toFixed(5)}</p>
      <div className="dan-fila" role="group" aria-label={`Qué hacer con ${n.codigo}`}>
        <button type="button" className="dan-opcion" aria-pressed={modo === "asociar"} onClick={() => setModo("asociar")}>Asociar a un activo</button>
        <button type="button" className="dan-opcion" aria-pressed={modo === "crear"} onClick={() => setModo("crear")}>Crear el activo</button>
      </div>
      {modo === "crear" ? (
        <div className="itv-nuevo">
          <div className="tec-campo"><label htmlFor={`nt-${n.codigo}`}>Tipo del activo nuevo (de punto)</label>
            <select id={`nt-${n.codigo}`} value={nuevoTipo} onChange={(e) => { setNuevoTipo(e.target.value); setNuevoClase(""); }}><option value="">Elija…</option>
              {tipos.map((t) => <option key={t.prefijo} value={t.prefijo}>{t.nombre} ({t.prefijo})</option>)}</select></div>
          {tipoSel?.clases.length ? <div className="tec-campo"><label htmlFor={`nc-${n.codigo}`}>Clase</label>
            <select id={`nc-${n.codigo}`} value={nuevoClase} onChange={(e) => setNuevoClase(e.target.value)}><option value="">Elija…</option>{tipoSel.clases.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div> : null}
          <div className="tec-campo"><label htmlFor={`nn-${n.codigo}`}>Nombre (opcional)</label><input id={`nn-${n.codigo}`} type="text" maxLength={120} value={nuevoNombre} onChange={(e) => setNuevoNombre(e.target.value)} /></div>
          <p className="tec-ayuda">Se crea en el punto del registro, «por verificar». Un tramo nuevo se dibuja en el Cargue de capas.</p>
        </div>
      ) : null}
      {modo === "asociar" ? <>
      <span className="dan-rot">Activos propuestos (los más cercanos)</span>
      {n.propuestos.length ? (
        <div className="itv-danos" role="radiogroup" aria-label="Activo propuesto">{n.propuestos.map((p) => (
          <button key={p.codigo} type="button" role="radio" aria-checked={activo === p.codigo} className="itv-dano itv-prop" onClick={() => setActivo(p.codigo)}>
            <strong>{p.codigo}</strong> · {p.tipo}{p.clase ? ` · ${p.clase}` : ""}<span>a {p.distancia_m} m{p.codigo_anterior ? ` · ${p.codigo_anterior}` : ""}</span>
          </button>))}</div>
      ) : <p className="tec-ayuda">No hay activos cerca: búsquelo por código.</p>}
      <div className="dan-buscar-fila">
        <input aria-label={`Buscar otro activo para ${n.codigo}`} type="text" maxLength={60} placeholder="Otro activo por código" value={buscar} onChange={(e) => setBuscar(e.target.value)} />
        <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => { if (buscar.trim().length >= 2) apiDano.buscar(buscar.trim(), n.sistema).then((r) => setRes(r.activos)).catch(() => setRes([])); }}>Buscar</button>
      </div>
      {res ? (res.length ? <div className="red-lista">{res.map((r) => (
        <button key={r.codigo} type="button" className="red-fila" onClick={() => { setActivo(r.codigo); setRes(null); }}>
          <span className="red-icono" aria-hidden="true" /><span className="red-fila-txt"><span className="red-fila-cod">{r.codigo}</span><span className="red-fila-sub">{r.tipo}</span></span></button>))}</div>
        : <p className="tec-ayuda">No se encontró nada con «{buscar}».</p>) : null}
      {activo ? <p className="tec-ayuda">Elegido: <strong>{activo}</strong> · <button type="button" className="tec-enlace" onClick={() => onFicha(activo)}>Ver ficha</button></p> : null}
      </> : null}
      <div className="tec-campo"><label htmlFor={`mot-${n.codigo}`}>Motivo</label>
        <input id={`mot-${n.codigo}`} type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por qué es este activo (lo vi en la visita, según el plano…)" /></div>
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      <div className="tec-acciones"><button type="button" className="tec-boton itv-guardar" disabled={estado === "enviando"} onClick={() => void asociar()}>{estado === "enviando" ? "Guardando…" : modo === "crear" ? "Crear y asociar" : `Asociar a ${activo || "…"}`}</button></div>
    </section>
  );
}

export function Recursos({ onFicha }: { onFicha: (c: string) => void }) {
  const [lista, setLista] = useState<IntervencionLista[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => {
    setError(null);
    apiItv.lista("recursos_por_completar").then((r) => setLista(r.intervenciones)).catch((e) => setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor o el administrador completan los recursos." : e instanceof Error ? e.message : "No se pudo cargar."));
  }, [vez]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!lista) return <p className="tec-sub dan-pad" role="status">Cargando…</p>;
  if (!lista.length) return <section className="tec-tarjeta"><p className="red-vacio">No hay intervenciones con los recursos por completar.</p></section>;
  return <>{lista.map((i) => <ItemRecursos key={i.codigo} i={i} onFicha={onFicha} onListo={() => setVez((v) => v + 1)} />)}</>;
}

function ItemRecursos({ i, onFicha, onListo }: { i: IntervencionLista; onFicha: (c: string) => void; onListo: () => void }) {
  const [filas, setFilas] = useState(i.fuentes.map((f) => ({ aportante: f.aportante, nombre: f.entidad ?? f.aportante_nombre, entidad: f.entidad ?? null,
    valor: f.valor != null ? String(f.valor) : "", porcentaje: f.porcentaje != null ? String(f.porcentaje) : "", soporte: f.soporte ?? "" })));
  const [estado, setEstado] = useState<"" | "enviando">("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const suma = filas.reduce((s, f) => s + (Number.isFinite(decimalONulo(f.porcentaje) ?? 0) ? (decimalONulo(f.porcentaje) ?? 0) : 0), 0);
  async function guardar() {
    const malas = filas.filter((f) => (numeroONulo(f.valor) === null && decimalONulo(f.porcentaje) === null) || Number.isNaN(numeroONulo(f.valor)) || Number.isNaN(decimalONulo(f.porcentaje)));
    if (malas.length) { setMsg({ ok: false, t: "Cada fuente lleva su valor o su porcentaje (en números)." }); return; }
    if (suma > 100) { setMsg({ ok: false, t: "Los porcentajes suman más de 100." }); return; }
    setEstado("enviando"); setMsg(null);
    try {
      const r = await apiItv.recursos(i.codigo, filas.map((f) => ({ aportante: f.aportante, entidad: f.entidad, valor: numeroONulo(f.valor), porcentaje: decimalONulo(f.porcentaje), soporte: f.soporte.trim() || null })), null);
      setMsg({ ok: true, t: `Recursos de ${r.codigo} guardados (versión ${r.version}).` }); setTimeout(onListo, 900);
    } catch (e) { setMsg({ ok: false, t: e instanceof Error ? e.message : "No se pudo guardar." }); }
    finally { setEstado(""); }
  }
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={`Recursos de ${i.codigo}`}>
      <h2>{i.codigo} · {i.tipo}{i.inversion_modo === "nuevo" ? " (activo nuevo)" : i.inversion_modo === "mejora" ? " (mejora)" : ""}</h2>
      <p className="red-texto">{i.activo ? <button type="button" className="tec-enlace" onClick={() => onFicha(i.activo!)}>{i.activo}</button> : <>«{i.no_identificado}» (no identificado)</>}
        {i.dano ? <> · atiende {i.dano}</> : null} · {i.ejecutor === "emdupar" ? "EMDUPAR" : `contratista${i.contratista ? ` ${i.contratista}` : ""}`}</p>
      <p className="tec-ayuda">{fecha(i.t_fin)} · {i.autor} · {i.sin_evidencia ? "sin evidencia fotográfica" : `${i.fotos} foto(s)`}</p>
      {filas.map((f, k) => (
        <div key={f.aportante + k} className="itv-fuente">
          <span className="dan-rot">{f.nombre}</span>
          <div className="itv-valores">
            <input aria-label={`Valor de ${f.nombre} en ${i.codigo}`} type="text" inputMode="numeric" placeholder="Valor ($)" value={f.valor} onChange={(e) => setFilas((x) => x.map((y, j) => j === k ? { ...y, valor: e.target.value } : y))} />
            <input aria-label={`Porcentaje de ${f.nombre} en ${i.codigo}`} type="text" inputMode="decimal" placeholder="o %" value={f.porcentaje} onChange={(e) => setFilas((x) => x.map((y, j) => j === k ? { ...y, porcentaje: e.target.value } : y))} />
            <input aria-label={`Soporte de ${f.nombre} en ${i.codigo}`} type="text" maxLength={200} placeholder="Soporte (convenio, resolución, contrato)" value={f.soporte} onChange={(e) => setFilas((x) => x.map((y, j) => j === k ? { ...y, soporte: e.target.value } : y))} />
          </div>
          {numeroONulo(f.valor) ? <span className="tec-ayuda">$ {pesos(numeroONulo(f.valor) as number)}</span> : null}
        </div>))}
      {suma > 0 ? <p className="tec-ayuda">Suma de porcentajes: {suma} %</p> : null}
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      <div className="tec-acciones"><button type="button" className="tec-boton itv-guardar" disabled={estado === "enviando"} onClick={() => void guardar()}>{estado === "enviando" ? "Guardando…" : "Guardar recursos"}</button></div>
    </section>
  );
}
