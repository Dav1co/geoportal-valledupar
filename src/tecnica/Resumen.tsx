import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiDash, textoError, type Catalogo, type FueraFila, type FueraResp, type Serie, type SeriesResp } from "./apiDashboard";
import { GraficaSerie, lugarDeSerie, textoRef } from "./GraficaSerie";
import { etiquetaMarca, fmtFecha, fmtMiles, fmtValor, hoyBogota, periodoARango, textoReferencia } from "./formato";
import { supabase } from "../lib/supabase";

// Dashboard técnico · «Resumen»: AVISOS (valores vigentes fuera de referencia, sin revisar, de los últimos 7 días) y GRÁFICAS de las variables de Entrada y Salida (una por variable y lugar).
// Todo sale de datos del servidor; ningún nombre de variable, planta o punto está escrito en el código. Solo supervisor y administrador (el servidor lo verifica en cada ruta).
const REFRESCO_MS = 60_000, MAX_AVISOS = 50;
const PERIODOS = [{ v: 7, t: "Últimos 7 días" }, { v: 14, t: "Últimos 14 días" }, { v: 30, t: "Últimos 30 días" }];
/** Aviso de error con la salida que corresponde: sesión vencida → volver a entrar; lo demás → reintentar. */
export function ErrorCaja({ error, onReintentar }: { error: { texto: string; sesion: boolean }; onReintentar: () => void }) {
  return (
    <div className="td-aviso td-aviso-error" role="alert">{error.texto}{" "}
      {error.sesion ? <button type="button" className="td-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="td-enlace" onClick={onReintentar}>Reintentar</button>}
    </div>
  );
}
export const lugarTexto = (f: { punto: string | null; punto_nombre: string | null; planta_nombre: string | null }) => f.punto ? (f.punto_nombre ?? f.punto) : (f.planta_nombre ?? "Las dos plantas");

export function Resumen({ catalogo }: { catalogo: Catalogo }) {
  const [dias, setDias] = useState(7);
  const [planta, setPlanta] = useState("");
  const [formulario, setFormulario] = useState("");
  const [auto, setAuto] = useState(true);
  const [avisos, setAvisos] = useState<FueraResp | null>(null);
  const [series, setSeries] = useState<SeriesResp | null>(null);
  const [opcionesForm, setOpcionesForm] = useState<{ clave: string; nombre: string }[]>([]);
  const [cargando, setCargando] = useState(true);
  const [errorAvisos, setErrorAvisos] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [errorSeries, setErrorSeries] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [revisando, setRevisando] = useState<number | null>(null);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const v = useRef(0);

  const cargarAvisos = useCallback(async () => {
    try {
      const r = apiDash.fueraReferencia({ estado: "sin_revisar", ...periodoARango("7d", hoyBogota()) }, { limite: MAX_AVISOS });
      const x = await r; setAvisos(x); setErrorAvisos(null);
    } catch (e) { setErrorAvisos(textoError(e)); }
  }, []);
  const cargarSeries = useCallback(async () => {
    try {
      const x = await apiDash.series(dias, planta, formulario); setSeries(x); setErrorSeries(null);
      if (!planta && !formulario) { const m = new Map<string, string>(); for (const s of x.series) m.set(s.formulario, s.formulario_nombre); setOpcionesForm([...m].map(([clave, nombre]) => ({ clave, nombre }))); }
    } catch (e) { setErrorSeries(textoError(e)); }
  }, [dias, planta, formulario]);
  const cargar = useCallback(async () => { const mi = ++v.current; setCargando(true); await Promise.all([cargarAvisos(), cargarSeries()]); if (mi === v.current) setCargando(false); }, [cargarAvisos, cargarSeries]);
  useEffect(() => { void cargar(); }, [cargar]);
  useEffect(() => {
    if (!auto) return;
    const id = setInterval(() => { if (document.visibilityState !== "hidden" && revisando === null) { void cargarAvisos(); void cargarSeries(); } }, REFRESCO_MS);
    return () => clearInterval(id);
  }, [auto, revisando, cargarAvisos, cargarSeries]);

  async function marcar(f: FueraFila) {
    if (revisando !== null) return;
    setRevisando(f.registro_id); setMsg(null);
    try {
      await apiDash.revisar(f.registro_id, "revisado", "");
      setMsg({ tipo: "ok", texto: `Marcado como revisado: ${f.variable_nombre} ${fmtValor(f.valor, f.decimales)} ${f.unidad} (${lugarTexto(f)}). Queda en «Eventos», donde se puede reabrir.` });
      await cargarAvisos();
    } catch (e) { setMsg({ tipo: "error", texto: textoError(e).texto }); await cargarAvisos(); }
    finally { setRevisando(null); }
  }

  const porFormulario = useMemo(() => {
    const con: Serie[] = [], sin: Serie[] = []; const grupos = new Map<string, { nombre: string; series: Serie[] }>();
    for (const s of series?.series ?? []) {
      if (s.n === 0) { sin.push(s); continue; }
      con.push(s); const g = grupos.get(s.formulario) ?? { nombre: s.formulario_nombre, series: [] }; g.series.push(s); grupos.set(s.formulario, g);
    }
    return { con, sin, grupos: [...grupos] };
  }, [series]);

  return (
    <section className="td-seccion" aria-labelledby="tr-tit">
      <div className="td-cab">
        <div>
          <h2 id="tr-tit">Resumen</h2>
          <p className="td-sub">Qué salió de referencia y cómo evolucionan las variables de Entrada y Salida. Las referencias solo avisan: nunca impiden guardar ni ocultan datos.</p>
        </div>
        <div className="td-botones">
          <label className="td-check"><input type="checkbox" checked={auto} onChange={(e) => setAuto(e.target.checked)} /> Actualizar solo cada 60 s</label>
          <button type="button" className="td-boton-sec td-corto" onClick={() => void cargar()} disabled={cargando}>{cargando ? "Cargando…" : "Actualizar ahora"}</button>
        </div>
      </div>

      {/* ---------- Avisos ---------- */}
      <section className="tr-avisos" aria-labelledby="tr-avisos-tit">
        <h3 id="tr-avisos-tit" className="td-h3">Avisos <span className={`tr-contador${(avisos?.total ?? 0) > 0 ? " tr-contador-si" : ""}`} data-testid="contador-avisos">{avisos ? fmtMiles(avisos.total) : "…"}</span></h3>
        <p className="td-sub">Valores vigentes (no excluidos) de los últimos 7 días que están fuera de su referencia y todavía no se han revisado. Más recientes primero.</p>
        {msg ? <div className={`td-aviso td-aviso-${msg.tipo === "ok" ? "ok" : "error"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.texto}</div> : null}
        {errorAvisos ? <ErrorCaja error={errorAvisos} onReintentar={() => void cargarAvisos()} /> : null}
        {!errorAvisos && avisos && avisos.registros.length === 0 ? <p className="tr-vacio" data-testid="sin-avisos">Sin valores fuera de referencia por revisar</p> : null}
        {!avisos && !errorAvisos ? <p className="td-sub" role="status">Cargando los avisos…</p> : null}
        <ul className="tr-lista">
          {(avisos?.registros ?? []).map((f) => (
            <li key={f.registro_id} className="tr-aviso" data-registro={f.registro_id}>
              <div className="tr-aviso-cuerpo">
                <div className="tr-aviso-linea"><span className="td-marca td-marca-alerta">{f.fuera_de_rango === "alto" ? "▲ " : "▼ "}{etiquetaMarca(f.fuera_de_rango)}</span> <strong>{f.variable_nombre}</strong> <span className="tr-valor">{fmtValor(f.valor, f.decimales)} <span className="td-unidad">{f.unidad}</span></span></div>
                <div className="tr-aviso-linea tr-menor">{f.formulario_nombre} · {lugarTexto(f)} · muestra del {fmtFecha(f.fecha_muestra)} a las {f.hora_muestra}</div>
                <div className="tr-aviso-linea tr-menor">Referencia: {textoReferencia({ ...f, unidad: f.unidad })} · registró {f.autor.split("@")[0]}</div>
              </div>
              <button type="button" className="td-boton" onClick={() => void marcar(f)} disabled={revisando !== null} aria-label={`Marcar revisado: ${f.variable_nombre} ${fmtValor(f.valor, f.decimales)} ${f.unidad}, ${lugarTexto(f)}`}>{revisando === f.registro_id ? "Guardando…" : "Marcar revisado"}</button>
            </li>
          ))}
        </ul>
        {avisos && avisos.total > avisos.registros.length ? <p className="td-sub">Se muestran los {fmtMiles(avisos.registros.length)} más recientes de {fmtMiles(avisos.total)}. Los demás están en «Eventos».</p> : null}
      </section>

      {/* ---------- Gráficas ---------- */}
      <section className="tr-graficas" aria-labelledby="tr-gr-tit">
        <h3 id="tr-gr-tit" className="td-h3">Gráficas</h3>
        <div className="td-filtros-cuerpo">
          <label className="td-campo">Periodo
            <select id="r-dias" value={dias} onChange={(e) => setDias(Number(e.target.value))}>{PERIODOS.map((p) => <option key={p.v} value={p.v}>{p.t}</option>)}</select></label>
          <label className="td-campo">Formulario
            <select id="r-form" value={formulario} onChange={(e) => setFormulario(e.target.value)}><option value="">Todos</option>{opcionesForm.map((x) => <option key={x.clave} value={x.clave}>{x.nombre}</option>)}</select></label>
          <label className="td-campo">Planta
            <select id="r-planta" value={planta} onChange={(e) => setPlanta(e.target.value)}><option value="">Todas</option>{catalogo.plantas.map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label>
        </div>
        <p className="td-sub">Un punto por cada registro vigente (no son promedios). La banda sombreada es la referencia vigente; los puntos fuera de referencia van en rojo con un triángulo (▲ sobre el máximo, ▼ bajo el mínimo).</p>
        {errorSeries ? <ErrorCaja error={errorSeries} onReintentar={() => void cargarSeries()} /> : null}
        {!series && !errorSeries ? <p className="td-sub" role="status">Cargando las gráficas…</p> : null}
        {series && series.series.length === 0 ? <p className="tr-vacio">No hay variables para graficar con esos filtros.</p> : null}
        {series && porFormulario.con.length === 0 && series.series.length > 0 ? <p className="tr-vacio" data-testid="sin-datos">Sin registros en el periodo para esos filtros.</p> : null}
        {series ? porFormulario.grupos.map(([clave, g]) => (
          <div key={clave} className="tr-grupo" data-formulario={clave}>
            <h4 className="tr-grupo-tit">{g.nombre}</h4>
            <div className="tr-rejilla">{g.series.map((s) => <GraficaSerie key={`${s.variable}@${s.planta ?? ""}@${s.punto ?? ""}`} serie={s} desde={series.desde} hasta={series.hasta} />)}</div>
          </div>
        )) : null}
        {series && porFormulario.sin.length > 0 ? (
          <details className="tr-sin-datos">
            <summary>{fmtMiles(porFormulario.sin.length)} {porFormulario.sin.length === 1 ? "variable sin registros" : "variables sin registros"} en el periodo</summary>
            <ul>{porFormulario.sin.map((s) => <li key={`${s.variable}@${s.planta ?? ""}@${s.punto ?? ""}`}>{s.formulario_nombre} · {s.variable_nombre} · {lugarDeSerie(s)} <span className="tr-menor">({textoRef(s)})</span></li>)}</ul>
          </details>
        ) : null}
      </section>
    </section>
  );
}
