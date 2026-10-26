import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiDash, textoError, type Catalogo, type EstadoRevision, type FiltrosFuera, type FueraFila } from "./apiDashboard";
import { etiquetaMarca, etiquetaOrigen, fmtFecha, fmtInstante, fmtMiles, fmtValor, hoyBogota, periodoARango, textoReferencia, type Periodo } from "./formato";
import { ErrorCaja, lugarTexto } from "./Resumen";

// Dashboard técnico · «Eventos». En este corte, «Eventos» = valores fuera de referencia con su historial de revisión (los eventos de daños, mantenimiento y cambios de servicio vienen después).
// Marcar revisado (nota opcional, hasta 500) y Reabrir (motivo obligatorio, 10 a 500). Solo supervisor y administrador. Nada se borra: cada cambio es un evento con quién, cuándo y la nota.
const PAGINA = 50, NOTA_MAX = 500, MOTIVO_MIN = 10;
type EstadoFiltro = "todos" | "sin_revisar" | "revisados";
type F = { formulario: string; planta: string; periodo: Periodo; desde: string; hasta: string; origen: string; estado: EstadoFiltro };
const INICIAL: F = { formulario: "", planta: "", periodo: "7d", desde: "", hasta: "", origen: "", estado: "todos" };
const PERIODOS: { v: Periodo; t: string }[] = [{ v: "hoy", t: "Hoy" }, { v: "7d", t: "Últimos 7 días" }, { v: "mes", t: "Mes en curso" }, { v: "rango", t: "Rango de fechas…" }];
type Accion = { tipo: "revisado" | "reabierto"; fila: FueraFila };
const textoEstado = (e: EstadoRevision) => (e === "revisado" ? "Revisado" : e === "reabierto" ? "Reabierto (sin revisar)" : "Sin revisar");

export function Eventos({ catalogo }: { catalogo: Catalogo }) {
  const [f, setF] = useState<F>(INICIAL);
  const [filas, setFilas] = useState<FueraFila[]>([]);
  const [total, setTotal] = useState(0);
  const [pend, setPend] = useState(0);
  const [rev, setRev] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [cargandoMas, setCargandoMas] = useState(false);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false);
  const [accion, setAccion] = useState<Accion | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const version = useRef(0);

  const filtrosServidor = useMemo<FiltrosFuera>(() => {
    const r = periodoARango(f.periodo, hoyBogota(), f.desde, f.hasta);
    return { formulario: f.formulario, planta: f.planta, origen: f.origen, estado: f.estado, desde: r.desde, hasta: r.hasta };
  }, [f]);
  const rangoInvalido = f.periodo === "rango" && !!f.desde && !!f.hasta && f.desde > f.hasta;

  const cargarPrimera = useCallback(async (silencioso = false) => {
    if (rangoInvalido) return;
    const v = ++version.current;
    if (!silencioso) { setCargando(true); setError(null); }
    try {
      const r = await apiDash.fueraReferencia(filtrosServidor, { limite: PAGINA });
      if (v !== version.current) return;
      setFilas(r.registros); setTotal(r.total); setPend(r.sin_revisar); setRev(r.revisados); setError(null);
    } catch (e) { if (v === version.current && !silencioso) setError(textoError(e)); }
    finally { if (v === version.current) setCargando(false); }
  }, [filtrosServidor, rangoInvalido]);
  useEffect(() => { void cargarPrimera(); }, [cargarPrimera]);

  async function cargarMas() {
    if (cargandoMas || filas.length === 0) return;
    setCargandoMas(true);
    try {
      const r = await apiDash.fueraReferencia(filtrosServidor, { despuesDe: filas[filas.length - 1].registro_id, limite: PAGINA });
      setFilas((x) => [...x, ...r.registros]); setTotal(r.total); setPend(r.sin_revisar); setRev(r.revisados);
    } catch (e) { setError(textoError(e)); } finally { setCargandoMas(false); }
  }

  const nombreForm = (c: string) => catalogo.formularios.find((x) => x.clave === c)?.nombre ?? c;

  return (
    <section className="td-seccion" aria-labelledby="te-tit">
      <div className="td-cab">
        <div>
          <h2 id="te-tit">Eventos</h2>
          <p className="td-sub">Valores fuera de referencia y su revisión. Nada se borra: cada revisión o reapertura queda con quién, cuándo y la nota.</p>
        </div>
      </div>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <ErrorCaja error={error} onReintentar={() => void cargarPrimera()} /> : null}

      <div className={`td-filtros${filtrosAbiertos ? " abierto" : ""}`}>
        <button type="button" className="td-boton-sec td-solo-movil" aria-expanded={filtrosAbiertos} onClick={() => setFiltrosAbiertos((x) => !x)}>Filtros{filtrosAbiertos ? " ▲" : " ▼"}</button>
        <div className="td-filtros-cuerpo">
          <label className="td-campo">Periodo (fecha de la muestra)
            <select id="e-per" value={f.periodo} onChange={(e) => setF({ ...f, periodo: e.target.value as Periodo })}>{PERIODOS.map((p) => <option key={p.v} value={p.v}>{p.t}</option>)}</select></label>
          {f.periodo === "rango" ? (
            <>
              <label className="td-campo">Desde<input id="e-desde" type="date" value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></label>
              <label className="td-campo">Hasta<input id="e-hasta" type="date" value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></label>
            </>
          ) : null}
          <label className="td-campo">Formulario
            <select id="e-form" value={f.formulario} onChange={(e) => setF({ ...f, formulario: e.target.value })}><option value="">Todos</option>{catalogo.formularios.map((x) => <option key={x.clave} value={x.clave}>{x.nombre}</option>)}</select></label>
          <label className="td-campo">Planta
            <select id="e-planta" value={f.planta} onChange={(e) => setF({ ...f, planta: e.target.value })}><option value="">Todas</option>{catalogo.plantas.map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label>
          <label className="td-campo">Origen de la referencia
            <select id="e-origen" value={f.origen} onChange={(e) => setF({ ...f, origen: e.target.value })}><option value="">Todos</option><option value="norma">Norma</option><option value="criterio_planta">Criterio de planta</option></select></label>
          <label className="td-campo">Estado de revisión
            <select id="e-estado" value={f.estado} onChange={(e) => setF({ ...f, estado: e.target.value as EstadoFiltro })}><option value="todos">Todos</option><option value="sin_revisar">Sin revisar</option><option value="revisados">Revisados</option></select></label>
        </div>
      </div>
      {rangoInvalido ? <p className="td-error" role="alert">La fecha inicial no puede ser posterior a la final.</p> : null}

      <div className="td-barra">
        <span role="status" aria-live="polite">{cargando ? "Cargando…" : `Mostrando ${fmtMiles(filas.length)} de ${fmtMiles(total)} ${total === 1 ? "valor" : "valores"}`}</span>
        {!cargando ? <span data-testid="conteo-revision">{fmtMiles(pend)} sin revisar · {fmtMiles(rev)} revisados (con estos filtros, sin contar el estado)</span> : null}
        <button type="button" className="td-boton-sec td-corto" onClick={() => void cargarPrimera()} disabled={cargando}>Actualizar ahora</button>
      </div>

      <div className="td-tabla-caja">
        <table className="td-tabla td-tabla-eventos">
          <caption className="td-solo-lectores">Valores fuera de referencia</caption>
          <thead><tr><th>Muestra</th><th className="td-col-form">Formulario</th><th>Planta o punto</th><th>Variable</th><th className="td-der">Valor</th><th>Referencia</th><th>Origen</th><th>Registró</th><th>Revisión</th><th>Acción</th></tr></thead>
          <tbody>
            {filas.map((r) => {
              const revisado = r.estado_revision === "revisado";
              return (
                <tr key={r.registro_id} className={revisado ? "te-revisado" : undefined} data-registro={r.registro_id}>
                  <td className="td-num">{fmtFecha(r.fecha_muestra)} {r.hora_muestra}<span className="td-etiqueta-form">{nombreForm(r.formulario)}</span></td>
                  <td className="td-col-form">{nombreForm(r.formulario)}</td>
                  <td>{lugarTexto(r)}{r.punto ? <span className="td-chico">{r.punto}</span> : null}</td>
                  <td>{r.variable_nombre}</td>
                  <td className="td-der td-valor">{fmtValor(r.valor, r.decimales)} <span className="td-unidad">{r.unidad}</span><span className="td-chico te-marca">{r.fuera_de_rango === "alto" ? "▲ " : "▼ "}{etiquetaMarca(r.fuera_de_rango)}</span></td>
                  <td title={r.ref_fuente ?? undefined}>{textoReferencia({ ...r, unidad: r.unidad, ref_fuente: null })}</td>
                  <td>{etiquetaOrigen(r.ref_origen)}</td>
                  <td title={r.autor}>{r.autor.split("@")[0]}</td>
                  <td>
                    <span className={`td-marca ${revisado ? "td-marca-ok" : r.estado_revision === "reabierto" ? "td-marca-info" : "td-marca-alerta"}`} data-estado={r.estado_revision}>{textoEstado(r.estado_revision)}</span>
                    {r.revisado_por ? <span className="td-chico">{r.estado_revision === "reabierto" ? "Reabrió" : "Revisó"} {r.revisado_por.split("@")[0]} el {fmtInstante(r.revisado_en)}</span> : null}
                    {r.revision_nota ? <span className="td-chico te-nota" title={r.revision_nota}>«{r.revision_nota}»</span> : null}
                  </td>
                  <td><div className="td-acciones">
                    {revisado
                      ? <button type="button" className="td-enlace" onClick={() => { setAviso(null); setAccion({ tipo: "reabierto", fila: r }); }}>Reabrir…</button>
                      : <button type="button" className="td-enlace" onClick={() => { setAviso(null); setAccion({ tipo: "revisado", fila: r }); }}>Marcar revisado…</button>}
                  </div></td>
                </tr>
              );
            })}
            {!cargando && filas.length === 0 && !error ? <tr><td colSpan={10} className="td-vacio">No hay valores fuera de referencia con esos filtros.</td></tr> : null}
          </tbody>
        </table>
      </div>
      {filas.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={cargarMas} disabled={cargandoMas}>{cargandoMas ? "Cargando…" : `Cargar más (${fmtMiles(total - filas.length)} restantes)`}</button></div> : null}
      <p className="td-pie">Las referencias solo avisan: nunca impiden guardar ni ocultan datos. Un valor excluido deja de aparecer aquí; si cambia el límite de la referencia, cambia qué valores están fuera.</p>

      {accion ? <DialogoRevision accion={accion} onCerrar={() => setAccion(null)}
        onHecho={(texto) => { setAccion(null); setAviso(texto); void cargarPrimera(true); }} /> : null}
    </section>
  );
}

function DialogoRevision({ accion, onCerrar, onHecho }: { accion: Accion; onCerrar: () => void; onHecho: (texto: string) => void }) {
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ref = useRef<HTMLTextAreaElement>(null);
  const reabre = accion.tipo === "reabierto"; const { fila } = accion;
  useEffect(() => { ref.current?.focus(); const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && !enviando) onCerrar(); }; window.addEventListener("keydown", esc); return () => window.removeEventListener("keydown", esc); }, [onCerrar, enviando]);
  const largo = nota.trim().length; const valido = reabre ? largo >= MOTIVO_MIN && largo <= NOTA_MAX : largo <= NOTA_MAX;
  async function confirmar() {
    if (!valido || enviando) return;
    setEnviando(true); setError(null);
    try {
      await apiDash.revisar(fila.registro_id, accion.tipo, nota);
      onHecho(reabre ? "Se reabrió el valor: vuelve a los avisos del Resumen. Queda el motivo, quién y cuándo." : "Se marcó como revisado. Queda quién, cuándo y la nota (si la hay); se puede reabrir.");
    } catch (e) { setError(textoError(e).texto); setEnviando(false); }
  }
  return (
    <div className="td-fondo" role="presentation">
      <div className="td-dialogo" role="dialog" aria-modal="true" aria-labelledby="te-dlg-tit">
        <h3 id="te-dlg-tit">{reabre ? "Reabrir la revisión" : "Marcar como revisado"}</h3>
        <p className="td-sub"><strong>{fila.variable_nombre}: {fmtValor(fila.valor, fila.decimales)} {fila.unidad}</strong> ({fila.formulario_nombre} · {lugarTexto(fila)}, muestra del {fmtFecha(fila.fecha_muestra)} a las {fila.hora_muestra}). {etiquetaMarca(fila.fuera_de_rango)}; referencia {textoReferencia({ ...fila, unidad: fila.unidad, ref_fuente: null })}.</p>
        <p className="td-sub">{reabre ? "El valor vuelve a la lista de avisos como sin revisar. No se borra nada: queda el historial." : "No cambia el dato ni lo excluye: solo deja constancia de que alguien lo revisó."}</p>
        <label className="td-campo td-ancho">{reabre ? `Motivo (obligatorio, de ${MOTIVO_MIN} a ${NOTA_MAX} caracteres)` : `Nota (opcional, hasta ${NOTA_MAX} caracteres)`}
          <textarea ref={ref} id="te-nota" rows={3} value={nota} maxLength={NOTA_MAX} onChange={(e) => setNota(e.target.value)} aria-invalid={reabre ? largo > 0 && !valido : undefined} aria-describedby="te-nota-ayuda" /></label>
        <span id="te-nota-ayuda" className={`td-chico${reabre && largo > 0 && !valido ? " td-error" : ""}`}>{largo} caracteres{reabre && largo < MOTIVO_MIN ? ` · faltan ${MOTIVO_MIN - largo}` : ""}</span>
        {error ? <p className="td-error" role="alert">{error}</p> : null}
        <div className="td-dialogo-acciones">
          <button type="button" className="td-boton" onClick={confirmar} disabled={!valido || enviando}>{enviando ? "Guardando…" : reabre ? "Reabrir" : "Marcar revisado"}</button>
          <button type="button" className="td-boton-sec" onClick={onCerrar} disabled={enviando}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}
