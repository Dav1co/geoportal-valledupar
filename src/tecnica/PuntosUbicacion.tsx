import { useEffect, useState } from "react";
import "./muestreo.css";
import { apiDash, textoError, type Catalogo, type UbicacionPendiente, type UbicacionesResp } from "./apiDashboard";
import type { PuntoMapa } from "./apiTecnica";
import { LeyendaPuntos, MiniMapaPuntos } from "./MiniMapaPuntos";

// Dashboard PTAP · pestaña «Puntos» (Corte 5b): la ubicación de los puntos de muestreo.
// · Ubicaciones por revisar: las que tomó un operador con el GPS desde Muestreo. Aprobar las deja como «verificada» (se agrega, no se borra nada); rechazar pide motivo.
//   Nadie revisa la que tomó él mismo (la revisa otro supervisor o el administrador). El mapa muestra la ubicación de ahora y la propuesta (morada).
// · Los puntos de muestreo activos con su ubicación, y las últimas revisiones.
// Sin descargas: es una pantalla de revisión.

const fecha = (iso: string | null) => (iso ? new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const FUENTE: Record<string, string> = { david: "dada por David", barrio: "centro del barrio", gps_operador: "GPS del operador (aprobada)", carga: "archivo de la capa" };
const comoPunto = (codigo: string, lat: number, lon: number, exactitud: "verificada" | "aproximada"): PuntoMapa =>
  ({ codigo, nombre: codigo, zona: null, exactitud, fuente: "", en_revision: false, propuesta_mia: false, lat, lon });

export function PuntosUbicacion(_: { catalogo: Catalogo }) {
  const [datos, setDatos] = useState<UbicacionesResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => { let vivo = true; setError(null);
    apiDash.ubicaciones().then((d) => { if (vivo) setDatos(d); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [intento]);

  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => setIntento((x) => x + 1)}>Reintentar</button></div>;
  if (!datos) return <p className="td-sub" role="status">Cargando los puntos…</p>;
  const ubicados = datos.puntos.filter((p) => p.lat !== null && p.lon !== null && p.exactitud)
    .map((p) => ({ ...comoPunto(p.codigo, p.lat!, p.lon!, p.exactitud!), nombre: p.nombre, en_revision: p.en_revision }));

  return (
    <div className="pto-lista">
      {aviso ? <div className={`td-aviso td-aviso-${aviso.tipo}`} role={aviso.tipo === "error" ? "alert" : "status"}>{aviso.texto}</div> : null}
      <section aria-labelledby="pto-pend-tit" className="pto-lista">
        <h2 id="pto-pend-tit">Ubicaciones por revisar ({datos.pendientes.length})</h2>
        <p className="td-sub">Las tomó un operador con el GPS del celular, desde Muestreo (se exige una precisión de {datos.precision_max_m} m o menos). Al aprobarla, el punto queda con la ubicación verificada; la de antes se conserva en el historial.</p>
        {datos.pendientes.length === 0 ? <p className="td-sub" data-testid="sin-pendientes">No hay ubicaciones por revisar.</p> : null}
        {datos.pendientes.map((p) => (
          <TarjetaPendiente key={p.propuesta_id} p={p} avisoLejos={datos.distancia_aviso_m}
            onHecho={(t) => { setAviso({ tipo: "ok", texto: t }); setIntento((x) => x + 1); }} onError={(t) => setAviso({ tipo: "error", texto: t })} />
        ))}
      </section>

      <section aria-labelledby="pto-todos-tit" className="pto-lista">
        <h2 id="pto-todos-tit">Puntos de muestreo ({datos.puntos.length})</h2>
        {ubicados.length ? <MiniMapaPuntos puntos={ubicados} elegido="" etiqueta="Mapa de los puntos de muestreo" /> : null}
        <LeyendaPuntos />
        <div className="pto-tabla-env">
          <table className="pto-tabla">
            <thead><tr><th>Punto</th><th>Zona</th><th>Ubicación</th><th>Desde</th></tr></thead>
            <tbody>
              {datos.puntos.map((p) => (
                <tr key={p.codigo}>
                  <td><strong>{p.codigo}</strong> {p.nombre}</td>
                  <td>{p.zona ?? "—"}</td>
                  <td>{p.exactitud ? `${p.exactitud === "verificada" ? "Verificada" : "Aproximada"} · ${FUENTE[p.fuente ?? ""] ?? p.fuente}` : "Sin ubicación"}{p.en_revision ? " · en revisión" : ""}</td>
                  <td>{fecha(p.desde)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section aria-labelledby="pto-rev-tit" className="pto-lista">
        <h2 id="pto-rev-tit">Últimas revisiones</h2>
        {datos.revisadas.length === 0 ? <p className="td-sub">Todavía no hay revisiones.</p> : (
          <div className="pto-tabla-env">
            <table className="pto-tabla">
              <thead><tr><th>Punto</th><th>Decisión</th><th>La tomó · la revisó</th><th>Cuándo</th></tr></thead>
              <tbody>
                {datos.revisadas.map((r) => (
                  <tr key={r.propuesta_id}>
                    <td><strong>{r.punto}</strong> {r.nombre}</td>
                    <td>{r.decision === "aprobada" ? "Aprobada" : "Rechazada"}{r.motivo ? ` · ${r.motivo}` : ""}</td>
                    <td>{r.autor} · {r.revisor}</td>
                    <td>{fecha(r.revisada_en)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

function TarjetaPendiente({ p, avisoLejos, onHecho, onError }: { p: UbicacionPendiente; avisoLejos: number; onHecho: (t: string) => void; onError: (t: string) => void }) {
  const [modo, setModo] = useState<"ver" | "aprobar" | "rechazar">("ver");
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const vigente = p.vigente ? [comoPunto(p.punto, p.vigente.lat, p.vigente.lon, p.vigente.exactitud)] : [];
  async function decidir() {
    const m = motivo.trim();
    if (modo === "rechazar" && m.length < 10) { setErr("Escriba el motivo del rechazo (10 caracteres o más)."); return; }
    if (modo === "aprobar" && m.length > 0 && m.length < 10) { setErr("El motivo, si lo escribe, debe tener 10 caracteres o más."); return; }
    setEnviando(true); setErr(null);
    try {
      const r = await apiDash.revisarUbicacion(p.propuesta_id, modo === "aprobar" ? "aprobar" : "rechazar", m);
      onHecho(r.estado === "aprobada" ? `Se aprobó la ubicación de ${p.punto} ${p.nombre}: ya es la verificada.` : `Se rechazó la ubicación propuesta de ${p.punto} ${p.nombre}.`);
    } catch (e) { const t = textoError(e).texto; setErr(t); onError(t); }
    finally { setEnviando(false); }
  }
  return (
    <article className="pto-tarjeta" data-testid={`pendiente-${p.punto}`}>
      <h3>{p.punto} · {p.nombre}{p.zona ? ` (${p.zona})` : ""}</h3>
      <p className="pto-meta">La tomó {p.autor_nombre ? `${p.autor_nombre} (${p.autor})` : p.autor} el {fecha(p.creado_en)}, con una precisión de {Math.round(p.precision_m)} m.</p>
      <p className="pto-meta">
        {p.vigente ? `Queda a ${p.distancia_m ?? "?"} m de la ubicación de ahora (${p.vigente.exactitud === "verificada" ? "verificada" : "aproximada, " + (FUENTE[p.vigente.fuente] ?? p.vigente.fuente)}).` : "El punto no tenía ubicación."}
        {p.lejos ? <span className="pto-lejos" title={`Más de ${avisoLejos} m`}>Lejos: revise antes de aprobar</span> : null}
        {!p.activo ? <span className="pto-lejos">Punto desactivado</span> : null}
      </p>
      <MiniMapaPuntos puntos={vigente} elegido="" propuesta={{ lat: p.lat, lon: p.lon }} bajo etiqueta={`Ubicación de ahora y ubicación propuesta de ${p.punto}`} />
      <p className="td-sub">Morado: la ubicación propuesta. {p.vigente ? "El otro círculo es la de ahora." : ""}</p>
      {p.propia ? <p className="td-sub" data-testid="propia">Esta ubicación la tomó usted: la revisa otro supervisor o el administrador.</p> : modo === "ver" ? (
        <div className="pto-acciones">
          <button type="button" className="td-boton" disabled={!p.activo} onClick={() => { setModo("aprobar"); setMotivo(""); setErr(null); }}>Aprobar</button>
          <button type="button" className="td-boton-sec" onClick={() => { setModo("rechazar"); setMotivo(""); setErr(null); }}>Rechazar</button>
        </div>
      ) : (
        <div className="td-campo">
          <label htmlFor={`pto-mot-${p.propuesta_id}`}>{modo === "rechazar" ? "Motivo del rechazo (obligatorio)" : "Nota de la aprobación (opcional)"}</label>
          <textarea id={`pto-mot-${p.propuesta_id}`} rows={2} maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} disabled={enviando} />
          {err ? <span className="td-error" role="alert">{err}</span> : null}
          <div className="pto-acciones">
            <button type="button" className="td-boton" onClick={() => void decidir()} disabled={enviando} aria-busy={enviando}>{enviando ? "Guardando…" : modo === "aprobar" ? "Confirmar la aprobación" : "Confirmar el rechazo"}</button>
            <button type="button" className="td-boton-sec" onClick={() => setModo("ver")} disabled={enviando}>Volver</button>
          </div>
        </div>
      )}
    </article>
  );
}
