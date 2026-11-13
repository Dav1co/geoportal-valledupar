import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiSup, textoError, type FilaAuditoria, type Resumen as ResumenT } from "./api";
import { aServidor, ErrorCaja, FILTROS_INICIALES, FiltrosSup, fmtFechaSrv, nombreCorto, rangoInvalido, ROT_ESTADO, ROT_INCIDENCIA, ROT_TIPO, textoFiltros, type EstadoFiltros } from "./comun";
import { DescargaCancelada, ejecutarDescarga, guardarArchivo, type Progreso } from "./descargas";
import { DetalleAuditoria } from "./DetalleAuditoria";
import type { FormularioAseo } from "../tipos";

// «Auditorías» (todas) y «No conformidades» (modo «nc»: parte de las pendientes). Tabla con filtros, detalle con fotos y acta, y descargas CSV y Excel por actividad con los mismos filtros.
const PAGINA = 50;
export function Auditorias({ def, cat, modo, inicial }: { def: FormularioAseo; cat: Pick<ResumenT, "turnos" | "auditores">; modo: "todas" | "nc"; inicial?: string }) {
  const [f, setF] = useState<EstadoFiltros>({ ...FILTROS_INICIALES, periodo: modo === "nc" ? "rango" : "mes", nc: modo === "nc" ? "pendientes" : "todos" });
  const [filas, setFilas] = useState<FilaAuditoria[]>([]); const [total, setTotal] = useState(0); const [pend, setPend] = useState(0); const [rev, setRev] = useState(0);
  const [cargando, setCargando] = useState(true); const [mas, setMas] = useState(false); const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [abierta, setAbierta] = useState<string | null>(inicial ?? null);
  const [progreso, setProgreso] = useState<Progreso | null>(null); const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const cancelar = useRef<AbortController | null>(null); const version = useRef(0);
  const filtros = useMemo(() => aServidor(f), [f]); const invalido = rangoInvalido(f);

  const cargar = useCallback(async () => {
    if (invalido) return; const v = ++version.current; setCargando(true); setError(null);
    try { const r = await apiSup.registros(filtros, { limite: PAGINA }); if (v !== version.current) return; setFilas(r.registros); setTotal(r.total); setPend(r.pendientes); setRev(r.revisadas); }
    catch (e) { if (v === version.current) setError(textoError(e)); } finally { if (v === version.current) setCargando(false); }
  }, [filtros, invalido]);
  useEffect(() => { void cargar(); }, [cargar]);
  async function cargarMas() { if (mas || !filas.length) return; setMas(true); try { const r = await apiSup.registros(filtros, { despuesDe: filas[filas.length - 1].seq, limite: PAGINA }); setFilas((x) => [...x, ...r.registros]); } catch (e) { setError(textoError(e)); } finally { setMas(false); } }

  async function descargar(formato: "csv" | "xlsx") {
    if (progreso || invalido) return; setMsg(null);
    if (!f.actividad) { setMsg({ tipo: "error", texto: "Elija la actividad en los filtros: cada una se descarga por separado." }); return; }
    cancelar.current = new AbortController();
    try { const r = await ejecutarDescarga({ filtros, formato, filtrosTexto: textoFiltros(f, def, cat.auditores, cat.turnos), onProgreso: setProgreso, senal: cancelar.current.signal }); guardarArchivo(r); setMsg({ tipo: "ok", texto: `Se descargó ${r.nombre} con ${r.filas.toLocaleString("es-CO")} ${r.filas === 1 ? "fila" : "filas"}.` }); }
    catch (e) { setMsg(e instanceof DescargaCancelada ? { tipo: "ok", texto: "Descarga cancelada." } : { tipo: "error", texto: textoError(e).texto }); } finally { setProgreso(null); cancelar.current = null; }
  }

  if (abierta) return <DetalleAuditoria id={abierta} onCerrar={() => setAbierta(null)} onCambio={() => void cargar()} />;
  const titulo = modo === "nc" ? "No conformidades" : "Auditorías";
  return (
    <section className="td-seccion" aria-labelledby="as-aud-tit">
      <div className="td-cab">
        <div><h2 id="as-aud-tit">{titulo}</h2>
          <p className="td-sub">{modo === "nc" ? "Auditorías con alguna no conformidad y su revisión. Nada se borra: cada revisión o reapertura queda con quién, cuándo y la nota." : "Todas las auditorías con filtros. Abra una para ver las fotos, revisarla, ocultarla o volver a generar su acta."}</p></div>
        <div className="td-descargas"><div className="td-botones">
          <button type="button" className="td-boton" disabled={!!progreso || invalido} onClick={() => void descargar("xlsx")}>Descargar Excel</button>
          <button type="button" className="td-boton-sec" disabled={!!progreso || invalido} onClick={() => void descargar("csv")}>Descargar CSV</button></div></div>
      </div>
      <p className="td-privacidad">Las descargas son por actividad (elija la actividad en los filtros), con los mismos filtros, sin fotos ni firmas, e incluyen los correos del personal. Es información interna: no la comparta fuera de la empresa. Cada descarga queda registrada.</p>
      {progreso ? <div className="td-aviso td-aviso-info" role="status">{progreso.fase === "preparando" ? "Preparando la descarga…" : progreso.fase === "armando" ? "Armando el archivo…" : `Descargando ${progreso.hecho.toLocaleString("es-CO")} de ${progreso.total.toLocaleString("es-CO")} filas…`}<button type="button" className="td-boton-sec td-corto" onClick={() => cancelar.current?.abort()}>Cancelar</button></div> : null}
      {msg ? <div className={`td-aviso td-aviso-${msg.tipo === "ok" ? "ok" : "error"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.texto}</div> : null}
      <FiltrosSup idp={modo} def={def} turnos={cat.turnos} auditores={cat.auditores} valor={f} onCambio={setF} />
      {invalido ? <p className="td-error" role="alert">La fecha «Desde» no puede ser posterior a «Hasta».</p> : null}
      {error ? <ErrorCaja error={error} onReintentar={() => void cargar()} /> : null}
      <p className="td-sub" role="status">{cargando ? "Cargando…" : `${total.toLocaleString("es-CO")} ${total === 1 ? "auditoría" : "auditorías"} · ${pend.toLocaleString("es-CO")} pendientes · ${rev.toLocaleString("es-CO")} revisadas`}</p>
      <div className="td-tabla-caja"><table className="td-tabla">
        <thead><tr><th>Consecutivo</th><th>Servicio</th><th>Ruta</th><th>Incidencia</th><th>Auditor</th><th>No conformidades</th><th>Marcas</th><th><span className="td-solo-lectores">Acciones</span></th></tr></thead>
        <tbody>
          {!cargando && filas.length === 0 ? <tr><td colSpan={8} className="td-vacio">Sin auditorías con esos filtros</td></tr> : null}
          {filas.map((x) => (
            <tr key={x.id} className={x.oculta ? "td-excluida" : ""} data-auditoria={x.id}>
              <td><strong className="td-num">{x.consecutivo}</strong><br /><span className="td-chico">{fmtFechaSrv(x.fecha_servicio)} · {x.oculta ? "oculta" : x.actividad_nombre}</span></td>
              <td>{x.servicio_nombre}<br /><span className="td-chico">{x.turno_nombre ?? ""}</span></td>
              <td className="td-num">{x.ruta_codigo}<br /><span className="td-chico">{x.barrios ?? ""}</span></td>
              <td>{ROT_INCIDENCIA[x.se_realizo]}{x.causal_nombre ? <><br /><span className="td-chico">{x.causal_nombre}</span></> : null}</td>
              <td>{nombreCorto(x.autor)}</td>
              <td>{x.nc_estado ? <span className="td-marcas">{x.nc_tipos.map((t) => <span key={t} className="td-marca td-marca-alerta">{ROT_TIPO[t]}</span>)}<span className="td-chico">{ROT_ESTADO[x.nc_estado]}</span></span> : <span className="td-chico">Conforme</span>}</td>
              <td><span className="td-marcas">{[x.lejos_de_ruta && "Lejos", x.fuera_de_horario && "Fuera de horario", x.fuera_de_zona && "Fuera de zona", x.no_programada_hoy && "No programada", x.sin_trazado && "Sin trazado"].filter(Boolean).map((m) => <span key={String(m)} className="td-marca td-marca-aviso">{m}</span>)}</span></td>
              <td><button type="button" className="td-boton-sec td-corto" onClick={() => setAbierta(x.id)} aria-label={`Abrir ${x.consecutivo}`}>Abrir</button></td>
            </tr>))}
        </tbody></table></div>
      {filas.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={() => void cargarMas()} disabled={mas}>{mas ? "Cargando…" : `Cargar más (${filas.length} de ${total})`}</button></div> : null}
    </section>
  );
}
