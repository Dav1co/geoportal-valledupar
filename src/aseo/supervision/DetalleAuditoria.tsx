import { useCallback, useEffect, useState } from "react";
import { apiSup, textoError, type Detalle } from "./api";
import { DialogoMotivo, ErrorCaja, fmtDuracion, fmtFechaSrv, fmtInicio, fmtInstanteBogota, nombreCorto, ROT_ESTADO, ROT_INCIDENCIA, ROT_TIPO } from "./comun";
import { guardarPdf, regenerarActa } from "./actaSupervision";

// Detalle de una auditoría: datos, respuestas, fotos (URL firmada de 60 s), firmas (solo quién y cómo, sin imagen), no conformidades con su revisión (Marcar revisada / Reabrir, con historial),
// ocultar y reincluir con motivo (como «excluir» en Técnica) y la GESTIÓN DEL ACTA: volver a generar el PDF con el mismo sello. Nada se borra.
export function DetalleAuditoria({ id, onCerrar, onCambio }: { id: string; onCerrar: () => void; onCambio: () => void }) {
  const [d, setD] = useState<Detalle | null>(null);
  const [fotos, setFotos] = useState<{ orden: number; nombre: string; url: string }[]>([]);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [dlg, setDlg] = useState<"revisar" | "reabrir" | "ocultar" | "reincluir" | null>(null);
  const [acta, setActa] = useState<"idle" | "generando">("idle");

  const cargar = useCallback(async () => {
    setError(null);
    try { const x = await apiSup.detalle(id); setD(x); if (x.fotos.length) { try { setFotos((await apiSup.fotos(id)).fotos); } catch { setFotos([]); } } else setFotos([]); }
    catch (e) { setError(textoError(e)); }
  }, [id]);
  useEffect(() => { setD(null); void cargar(); }, [cargar]);

  async function descargarActa() {
    setActa("generando"); setAviso(null);
    try { const r = await regenerarActa(id); guardarPdf(r); setAviso(`Se generó ${r.nombre} con el mismo sello del registro.${r.usoRespaldo ? " Las fotos se pidieron por la vía de respaldo." : ""}`); }
    catch (e) { setError(textoError(e)); } finally { setActa("idle"); }
  }
  const hecho = async (texto: string) => { setDlg(null); setAviso(texto); await cargar(); onCambio(); };

  if (error && !d) return <section className="td-seccion"><ErrorCaja error={error} onReintentar={() => void cargar()} /><button type="button" className="td-boton-sec" onClick={onCerrar}>Cerrar</button></section>;
  if (!d) return <p className="td-sub" role="status">Cargando la auditoría…</p>;
  const marcas = [d.marcas.lejos_de_ruta && "Lejos de la ruta", d.marcas.fuera_de_zona && "Fuera de la zona", d.marcas.fuera_de_horario && "Fuera de horario", d.marcas.no_programada_hoy && "No programada ese día", d.marcas.sin_trazado && "Sin trazado"].filter(Boolean) as string[];
  return (
    <section className="td-seccion as-detalle" aria-labelledby="as-det-tit">
      <div className="td-cab">
        <div><h2 id="as-det-tit">{d.consecutivo}{d.oculta ? " · oculta" : ""}</h2>
          <p className="td-sub">{d.actividad_nombre} · {d.modalidad_nombre} · ruta <span className="td-num">{d.ruta_codigo}</span> · servicio del {fmtFechaSrv(d.fecha_servicio)} · registrada el {fmtInstanteBogota(d.registrado_en)} por {nombreCorto(d.autor)}</p></div>
        <div className="td-botones">
          <button type="button" className="td-boton" onClick={() => void descargarActa()} disabled={acta === "generando"}>{acta === "generando" ? "Generando…" : "Descargar acta (PDF)"}</button>
          <button type="button" className="td-boton-sec" onClick={onCerrar}>Cerrar detalle</button>
        </div>
      </div>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <ErrorCaja error={error} onReintentar={() => void cargar()} /> : null}

      <div className="td-tabla-caja"><dl className="as-dl">
        <div><dt>Inicio</dt><dd data-campo="inicio">{fmtInicio(d.inicio_en, d.inicio_origen) || "No registrado (auditoría anterior a la hora de inicio)"}</dd></div>
        <div><dt>Fin</dt><dd data-campo="fin">{fmtInstanteBogota(d.registrado_en)}</dd></div>
        <div><dt>Duración</dt><dd data-campo="duracion">{fmtDuracion(d.duracion_s) || "—"}</dd></div>
        <div><dt>Incidencia</dt><dd>{ROT_INCIDENCIA[d.se_realizo]}{d.causal_nombre ? ` · ${d.causal_nombre}` : ""}</dd></div>
        <div><dt>Servicio</dt><dd>{d.servicio_nombre}</dd></div>
        <div><dt>Turno y frecuencia</dt><dd>{[d.turno_nombre, d.frecuencia_nombre].filter(Boolean).join(" · ") || "—"}</dd></div>
        <div><dt>Barrios</dt><dd>{d.barrios ?? "—"}</dd></div>
        {d.respuestas.map((x) => <div key={x.codigo}><dt>{x.pregunta}</dt><dd>{x.texto ?? "—"}</dd></div>)}
        {d.observaciones ? <div><dt>Observaciones</dt><dd>{d.observaciones}</dd></div> : null}
        <div><dt>Ubicación</dt><dd>{d.lat.toFixed(5).replace(".", ",")}, {d.lon.toFixed(5).replace(".", ",")}{d.distancia_ruta_m != null ? ` · a ${Math.round(d.distancia_ruta_m)} m de la ruta` : ""}</dd></div>
        <div><dt>Marcas</dt><dd>{marcas.length ? <span className="td-marcas">{marcas.map((m) => <span key={m} className="td-marca td-marca-alerta">{m}</span>)}</span> : "Ninguna"}</dd></div>
        <div><dt>Firmas</dt><dd>{d.firmas.length === 0 ? "Registro anterior a las firmas" : d.firmas.map((f) => f.rol === "auditor" ? `Auditor: ${f.nombre ?? ""}${f.cargo ? ` (${f.cargo})` : " (cargo no registrado)"}` : `Representante: ${f.estado === "firmo" ? "firmó" : f.estado === "se_nego" ? "se negó a firmar" : "no había representante"}${f.nombre ? ` · ${f.nombre}` : ""}`).join(" · ")}</dd></div>
        <div><dt>Sello (SHA-256)</dt><dd className="td-num as-sello">{d.sello}</dd></div>
      </dl></div>

      {d.fotos.length ? <div><h3 className="td-h3">Fotos ({d.fotos.length})</h3>
        <p className="td-sub">Las direcciones de las fotos duran un minuto; si una no carga, vuelva a abrir el detalle.</p>
        <div className="as-fotos">{d.fotos.map((f) => { const u = fotos.find((x) => x.orden === f.orden); return (
          <figure key={f.orden} className="as-foto">{u ? <a href={u.url} target="_blank" rel="noreferrer"><img src={u.url} alt={`${f.orden}. ${f.nombre}`} loading="lazy" /></a> : <div className="as-foto-vacia">Sin vista previa</div>}<figcaption>{f.orden}. {f.nombre}</figcaption></figure>); })}</div></div> : null}

      <div><h3 className="td-h3">No conformidades · revisión</h3>
        {d.nc_motivos.length === 0 ? <p className="td-sub">Esta auditoría no tiene no conformidades.</p> : <>
          <ul className="as-motivos">{d.nc_motivos.map((m, i) => <li key={i}><span className="td-marca td-marca-alerta">{ROT_TIPO[m.tipo]}</span> {m.pregunta ? `${m.pregunta}: ${m.respuesta ?? ""}` : m.tipo === "parcial" ? "Se realizó en parte" : "No se realizó"}</li>)}</ul>
          <p className="td-sub">Estado: <strong>{d.nc_estado ? ROT_ESTADO[d.nc_estado] : ""}</strong></p>
          {!d.oculta ? <div className="td-botones">
            {d.nc_estado !== "revisada" ? <button type="button" className="td-boton" onClick={() => setDlg("revisar")}>Marcar revisada</button> : <button type="button" className="td-boton-sec" onClick={() => setDlg("reabrir")}>Reabrir</button>}</div> : <p className="td-sub">Reincluya la auditoría para poder revisarla.</p>}
          {d.revisiones.length ? <ul className="td-eventos">{d.revisiones.map((r) => <li key={r.id}><strong>{r.tipo_evento === "revisar" ? "Revisada" : "Reabierta"}</strong> el {fmtInstanteBogota(r.creado_en)} por {nombreCorto(r.autor)}{r.nota ? ` · ${r.nota}` : ""}</li>)}</ul> : null}</>}
      </div>

      <div><h3 className="td-h3">Visibilidad</h3>
        <p className="td-sub">{d.oculta ? `Oculta: ${d.oculta_motivo ?? ""}. No cuenta en indicadores ni en no conformidades; nada se borra.` : "Visible. Ocultarla la saca de los indicadores y de las no conformidades (queda el motivo, quién y cuándo)."}</p>
        <div className="td-botones"><button type="button" className="td-boton-sec" onClick={() => setDlg(d.oculta ? "reincluir" : "ocultar")}>{d.oculta ? "Reincluir" : "Ocultar"}</button></div>
        {d.eventos_visibilidad.length ? <ul className="td-eventos">{d.eventos_visibilidad.map((e, i) => <li key={i}><strong>{e.tipo_evento === "ocultar" ? "Ocultada" : "Reincluida"}</strong> el {fmtInstanteBogota(e.creado_en)} por {nombreCorto(e.autor)} · {e.motivo}</li>)}</ul> : null}
      </div>

      {dlg === "revisar" ? <DialogoMotivo titulo="Marcar revisada" texto="La no conformidad queda revisada, con quién y cuándo. Se puede reabrir después." rotulo="Nota" min={0} max={500} boton="Marcar revisada" onCerrar={() => setDlg(null)} onConfirmar={async (n) => { try { await apiSup.revisar(id, "revisar", n); await hecho("Marcada como revisada."); } catch (e) { throw new Error(textoError(e).texto); } }} /> : null}
      {dlg === "reabrir" ? <DialogoMotivo titulo="Reabrir la revisión" texto="Vuelve a quedar pendiente. El historial conserva la revisión anterior." rotulo="Motivo" min={10} max={500} boton="Reabrir" onCerrar={() => setDlg(null)} onConfirmar={async (n) => { try { await apiSup.revisar(id, "reabrir", n); await hecho("Revisión reabierta."); } catch (e) { throw new Error(textoError(e).texto); } }} /> : null}
      {dlg === "ocultar" || dlg === "reincluir" ? <DialogoMotivo titulo={dlg === "ocultar" ? "Ocultar la auditoría" : "Reincluir la auditoría"} texto={dlg === "ocultar" ? "Sale de indicadores y no conformidades. No se borra nada." : "Vuelve a contar en indicadores y no conformidades."} rotulo="Motivo" min={10} max={1000} boton={dlg === "ocultar" ? "Ocultar" : "Reincluir"} onCerrar={() => setDlg(null)}
        onConfirmar={async (n) => { try { await apiSup.gestionar(id, dlg, n); await hecho(dlg === "ocultar" ? "La auditoría quedó oculta." : "La auditoría volvió a ser visible."); } catch (e) { throw new Error(textoError(e).texto); } }} /> : null}
    </section>
  );
}
