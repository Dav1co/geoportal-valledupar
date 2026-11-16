import { useEffect, useState } from "react";
import "./muestreo.css";
import { apiDash, textoError, type Catalogo, type PuntoUbicado, type UbicacionPendiente, type UbicacionesResp } from "./apiDashboard";
import type { PuntoMapa } from "./apiTecnica";
import { distanciaM, LeyendaPuntos, MiniMapaPuntos } from "./MiniMapaPuntos";

// Dashboard PTAP · pestaña «Puntos» (Corte 5b): la ubicación de los puntos de muestreo.
// · Ubicaciones por revisar: las que tomó un operador con el GPS desde Muestreo. Aprobar las deja como «verificada» (se agrega, no se borra nada); rechazar pide motivo.
//   El supervisor no revisa la que tomó él mismo (la revisa otro supervisor o el administrador); el administrador sí puede (§32.1, Corte 5c).
//   El mapa muestra la ubicación de ahora y la propuesta (morada).
// · Corte 5c (§32.2): «Corregir la ubicación» de un punto verificado, con motivo: tocando el mapa, con coordenadas o con el GPS del equipo. La anterior
//   queda en el historial (se agrega, no se borra nada).
// · Los puntos de muestreo activos con su ubicación, y las últimas revisiones.
// Sin descargas: es una pantalla de revisión.

const fecha = (iso: string | null) => (iso ? new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const FUENTE: Record<string, string> = { david: "dada por David", barrio: "centro del barrio", gps_operador: "GPS del operador (aprobada)", carga: "archivo de la capa",
  correccion: "corregida en el Dashboard" };
const METODO: Record<string, string> = { mapa: "en el mapa", coordenadas: "con coordenadas", gps: "con el GPS" };
const comoPunto = (codigo: string, lat: number, lon: number, exactitud: "verificada" | "aproximada"): PuntoMapa =>
  ({ codigo, nombre: codigo, zona: null, exactitud, fuente: "", en_revision: false, propuesta_mia: false, lat, lon });

export function PuntosUbicacion(_: { catalogo: Catalogo }) {
  const [datos, setDatos] = useState<UbicacionesResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [intento, setIntento] = useState(0);
  const [corregir, setCorregir] = useState<string>("");
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
          <TarjetaPendiente key={p.propuesta_id} p={p} avisoLejos={datos.distancia_aviso_m} soyAdmin={!!datos.soy_admin}
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
        <CorregirUbicacion puntos={datos.puntos} elegido={corregir} onElegir={setCorregir} precisionMax={datos.precision_max_m}
          onHecho={(t) => { setAviso({ tipo: "ok", texto: t }); setCorregir(""); setIntento((x) => x + 1); }} />
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

      {datos.correcciones && datos.correcciones.length ? (
        <section aria-labelledby="pto-cor-tit" className="pto-lista">
          <h2 id="pto-cor-tit">Últimas correcciones</h2>
          <div className="pto-tabla-env">
            <table className="pto-tabla">
              <thead><tr><th>Punto</th><th>Motivo</th><th>Quién · cómo</th><th>Cuándo</th></tr></thead>
              <tbody>
                {datos.correcciones.map((c) => (
                  <tr key={c.id}>
                    <td><strong>{c.punto}</strong> {c.nombre}</td>
                    <td>{c.motivo} ({Math.round(c.distancia_m)} m)</td>
                    <td>{c.autor} · {METODO[c.metodo] ?? c.metodo}</td>
                    <td>{fecha(c.creado_en)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}
    </div>
  );
}

/** §32.2: corregir la ubicación de un punto VERIFICADO (con motivo). La nueva se toma tocando el mapa, escribiendo las coordenadas o con el GPS del equipo. */
function CorregirUbicacion({ puntos, elegido, onElegir, precisionMax, onHecho }: { puntos: PuntoUbicado[]; elegido: string; onElegir: (c: string) => void; precisionMax: number; onHecho: (t: string) => void }) {
  const verificados = puntos.filter((p) => p.exactitud === "verificada" && p.lat !== null && p.lon !== null);
  const p = verificados.find((x) => x.codigo === elegido) ?? null;
  const [nueva, setNueva] = useState<{ lat: number; lon: number; metodo: "mapa" | "coordenadas" | "gps"; precision: number | null } | null>(null);
  const [lat, setLat] = useState(""); const [lon, setLon] = useState("");
  const [motivo, setMotivo] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [gps, setGps] = useState<string | null>(null);
  useEffect(() => { setNueva(null); setLat(""); setLon(""); setMotivo(""); setErr(null); setGps(null); }, [elegido]);
  if (!verificados.length) return null;
  const poner = (la: number, lo: number, metodo: "mapa" | "coordenadas" | "gps", precision: number | null = null) => {
    setNueva({ lat: la, lon: lo, metodo, precision }); if (metodo !== "coordenadas") { setLat(la.toFixed(6)); setLon(lo.toFixed(6)); } setErr(null);
  };
  function tomarGps() {
    if (!navigator.geolocation) { setGps("Este equipo no da la ubicación."); return; }
    setGps("Buscando la ubicación…");
    navigator.geolocation.getCurrentPosition((pos) => {
      const prec = pos.coords.accuracy;
      if (prec > precisionMax) { setGps(`El GPS tiene una precisión de ${Math.ceil(prec)} m y se necesita de ${precisionMax} m o menos. Espere a cielo abierto y vuelva a intentarlo.`); return; }
      setGps(`Ubicación tomada con una precisión de ${Math.round(prec)} m.`);
      poner(pos.coords.latitude, pos.coords.longitude, "gps", prec);
    }, () => setGps("No se pudo tomar la ubicación (revise el permiso de ubicación del navegador)."), { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 });
  }
  async function guardar() {
    if (!p || !nueva) { setErr("Marque la ubicación nueva."); return; }
    if (motivo.trim().length < 10) { setErr("Escriba el motivo de la corrección (10 caracteres o más)."); return; }
    setEnviando(true); setErr(null);
    try {
      const r = await apiDash.corregirUbicacion(p.codigo, nueva.lat, nueva.lon, nueva.metodo, nueva.metodo === "gps" ? nueva.precision : null, motivo);
      onHecho(`Se corrigió la ubicación de ${p.codigo} ${p.nombre} (${Math.round(r.distancia_m)} m de la anterior). La anterior queda en el historial.`);
    } catch (e) { setErr(textoError(e).texto); } finally { setEnviando(false); }
  }
  const dist = p && nueva ? Math.round(distanciaM({ lat: p.lat!, lon: p.lon! }, nueva)) : null;
  return (
    <div className="pto-corregir" data-testid="corregir">
      <h3>Corregir una ubicación verificada</h3>
      <p className="td-sub">Si la ubicación verificada de un punto está mal. Pide motivo; la anterior queda en el historial. Las aproximadas se cambian con «Guardar la ubicación de este punto», en Muestreo.</p>
      <div className="td-campo">
        <label htmlFor="pto-cor-punto">Punto</label>
        <select id="pto-cor-punto" value={elegido} onChange={(e) => onElegir(e.target.value)}>
          <option value="">Elija un punto verificado…</option>
          {verificados.map((x) => <option key={x.codigo} value={x.codigo} disabled={x.en_revision}>{x.codigo} {x.nombre}{x.en_revision ? " (tiene una ubicación en revisión)" : ""}</option>)}
        </select>
      </div>
      {p ? (
        <>
          <MiniMapaPuntos puntos={[{ ...comoPunto(p.codigo, p.lat!, p.lon!, "verificada"), nombre: p.nombre }]} elegido="" propuesta={nueva ? { lat: nueva.lat, lon: nueva.lon } : null}
            onTocarMapa={(la, lo) => poner(la, lo, "mapa")} etiqueta={`Toque el mapa donde está de verdad ${p.codigo}`} />
          <p className="td-sub">Toque el mapa donde está el punto (morado: la ubicación nueva), escriba las coordenadas o use el GPS de este equipo.</p>
          <div className="pto-coords">
            <div className="td-campo"><label htmlFor="pto-cor-lat">Latitud</label>
              <input id="pto-cor-lat" type="text" inputMode="decimal" value={lat} onChange={(e) => { setLat(e.target.value); const a = Number(e.target.value.replace(",", ".")), b = Number(lon.replace(",", ".")); if (Number.isFinite(a) && Number.isFinite(b) && a && b) setNueva({ lat: a, lon: b, metodo: "coordenadas", precision: null }); }} /></div>
            <div className="td-campo"><label htmlFor="pto-cor-lon">Longitud</label>
              <input id="pto-cor-lon" type="text" inputMode="decimal" value={lon} onChange={(e) => { setLon(e.target.value); const a = Number(lat.replace(",", ".")), b = Number(e.target.value.replace(",", ".")); if (Number.isFinite(a) && Number.isFinite(b) && a && b) setNueva({ lat: a, lon: b, metodo: "coordenadas", precision: null }); }} /></div>
          </div>
          <button type="button" className="td-boton-sec" onClick={tomarGps}>Usar la ubicación de este equipo (GPS)</button>
          {gps ? <p className="td-sub" role="status">{gps}</p> : null}
          {nueva ? <p className="pto-meta">Nueva: {nueva.lat.toFixed(6)}, {nueva.lon.toFixed(6)} ({METODO[nueva.metodo]}) · a {dist} m de la de ahora.</p> : null}
          <div className="td-campo">
            <label htmlFor="pto-cor-mot">Motivo de la corrección (obligatorio)</label>
            <textarea id="pto-cor-mot" rows={2} maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} disabled={enviando} />
            {err ? <span className="td-error" role="alert">{err}</span> : null}
          </div>
          <div className="pto-acciones">
            <button type="button" className="td-boton" onClick={() => void guardar()} disabled={enviando || !nueva} aria-busy={enviando}>{enviando ? "Guardando…" : "Guardar la corrección"}</button>
            <button type="button" className="td-boton-sec" onClick={() => onElegir("")} disabled={enviando}>Cancelar</button>
          </div>
        </>
      ) : null}
    </div>
  );
}

function TarjetaPendiente({ p, avisoLejos, soyAdmin, onHecho, onError }: { p: UbicacionPendiente; avisoLejos: number; soyAdmin: boolean; onHecho: (t: string) => void; onError: (t: string) => void }) {
  const puede = p.puede_revisar ?? !p.propia;
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
      {p.propia && puede && soyAdmin ? <p className="td-sub" data-testid="propia-admin">Esta ubicación la tomó usted. Como administrador, puede revisarla.</p> : null}
      {!puede ? <p className="td-sub" data-testid="propia">Esta ubicación la tomó usted: la revisa otro supervisor o el administrador.</p> : modo === "ver" ? (
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
