import { useCallback, useEffect, useRef, useState } from "react";
import { apiSup, textoError, type FilaResumen, type Resumen as ResumenT } from "./api";
import { ErrorCaja, fmtFechaSrv, nombreCorto, ROT_INCIDENCIA, ROT_TIPO } from "./comun";

// «Resumen»: arriba, en ROJO, las no conformidades pendientes de revisar (sin revisar o reabiertas), más recientes primero; «Marcar revisada» de un toque (la nota opcional y «Reabrir» están en «No conformidades»).
// Se actualiza solo cada 60 segundos (casilla para pausar), como el Resumen técnico. Solo supervisor y administrador (el servidor lo verifica).
const REFRESCO_MS = 60_000, MAX = 50;
export function Resumen({ onAbrir, onDatos }: { onAbrir: (id: string) => void; onDatos: (r: ResumenT) => void }) {
  const [r, setR] = useState<ResumenT | null>(null); const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [auto, setAuto] = useState(true); const [revisando, setRevisando] = useState<string | null>(null); const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const cargar = useCallback(async () => { try { const x = await apiSup.resumen(MAX); setR(x); onDatos(x); setError(null); } catch (e) { setError(textoError(e)); } }, [onDatos]);
  useEffect(() => { void cargar(); }, [cargar]);
  const rev = useRef(revisando); rev.current = revisando;
  useEffect(() => { if (!auto) return; const id = setInterval(() => { if (document.visibilityState !== "hidden" && rev.current === null) void cargar(); }, REFRESCO_MS); return () => clearInterval(id); }, [auto, cargar]);

  async function marcar(f: FilaResumen) {
    if (revisando) return; setRevisando(f.id); setMsg(null);
    try { await apiSup.revisar(f.id, "revisar", ""); setMsg({ tipo: "ok", texto: `Marcada como revisada: ${f.consecutivo}. Queda en «No conformidades», donde se puede reabrir.` }); await cargar(); }
    catch (e) { setMsg({ tipo: "error", texto: textoError(e).texto }); await cargar(); } finally { setRevisando(null); }
  }
  return (
    <section className="td-seccion" aria-labelledby="as-res-tit">
      <div className="td-cab"><div><h2 id="as-res-tit">Resumen</h2><p className="td-sub">Lo que hay que revisar primero.</p></div>
        <label className="td-check"><input type="checkbox" checked={auto} onChange={(e) => setAuto(e.target.checked)} /> Actualizar solo cada minuto</label></div>
      <section className="tr-avisos" aria-labelledby="as-nc-tit">
        <h3 id="as-nc-tit" className="td-h3">No conformidades por revisar <span className="tr-contador tr-contador-si" data-testid="nc-pendientes">{r ? r.pendientes : "…"}</span></h3>
        <p className="td-sub">Auditorías no ocultas en las que algo toca reportar: SST con «No», no realizada, realizada en parte, o una respuesta marcada como no conforme. Más recientes primero.</p>
        {msg ? <div className={`td-aviso td-aviso-${msg.tipo === "ok" ? "ok" : "error"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.texto}</div> : null}
        {error ? <ErrorCaja error={error} onReintentar={() => void cargar()} /> : null}
        {!error && r && r.registros.length === 0 ? <p className="tr-vacio" data-testid="sin-avisos">Sin no conformidades por revisar</p> : null}
        {!r && !error ? <p className="td-sub" role="status">Cargando los avisos…</p> : null}
        <ul className="tr-lista">
          {(r?.registros ?? []).map((f) => (
            <li key={f.id} className="tr-aviso" data-auditoria={f.id}>
              <div className="tr-aviso-cuerpo">
                <div className="tr-aviso-linea"><span className="td-marcas">{f.nc_tipos.map((t) => <span key={t} className="td-marca td-marca-alerta">{ROT_TIPO[t]}</span>)}</span> <strong>{f.consecutivo}</strong> · {f.actividad_nombre} {f.modalidad_nombre} · {ROT_INCIDENCIA[f.se_realizo]}{f.nc_estado === "reabierta" ? " · reabierta" : ""}</div>
                <div className="tr-aviso-linea tr-menor">Ruta {f.ruta_codigo} · servicio del {fmtFechaSrv(f.fecha_servicio)} · auditó {nombreCorto(f.autor)}</div>
                <div className="tr-aviso-linea tr-menor">{f.nc_motivos.map((m) => (m.pregunta ? `${m.pregunta}: ${m.respuesta ?? ""}` : m.tipo === "parcial" ? "Se realizó en parte" : "No se realizó")).join(" · ")}</div>
              </div>
              <div className="td-botones"><button type="button" className="td-boton-sec" onClick={() => onAbrir(f.id)}>Abrir</button>
                <button type="button" className="td-boton" onClick={() => void marcar(f)} disabled={revisando !== null} aria-label={`Marcar revisada ${f.consecutivo}`}>{revisando === f.id ? "Guardando…" : "Marcar revisada"}</button></div>
            </li>))}
        </ul>
        {r && r.pendientes > r.registros.length ? <p className="td-sub">Se muestran las {r.registros.length} más recientes de {r.pendientes}. Las demás están en «No conformidades».</p> : null}
      </section>
    </section>
  );
}
