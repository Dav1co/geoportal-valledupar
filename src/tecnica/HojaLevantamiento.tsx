import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import "./hoja.css";
import membrete from "./membrete_logo_y_franja.png";
import logo from "./membrete_logo.png";
import { apiLev, type HojaLevantar } from "./apiLevantar";
import { ErrorTec } from "./apiTecnica";

// Hoja de levantamiento en PDF (Corte 14, Etapa 2): un solo formato, que sirve también para la cuadrilla. Mapa del sector con los puntos numerados y la tabla en
// el orden del recorrido (número, tipo, servicio, fecha, coordenadas, precisión, foto en miniatura y la observación: David, 17-nov, en este PDF sí va).
// Hoja membretada oficial de EMDUPAR (guía visual §9): carta, u oficio (8,5 × 13 in) si la tabla no cabe bien; márgenes 2,5 cm arriba, 3 cm a los lados y 4 cm
// abajo; logo pequeño arriba a la derecha y franja de olas abajo; Arial; encabezado de la tabla repetido y «Página N de M».
// El PDF lo hace el navegador («Imprimir» → «Guardar como PDF»). Sin quién reportó y sin datos de suscriptores. La descarga queda en la auditoría (servidor).
const BASE = { type: "raster" as const, tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], tileSize: 256, maxzoom: 19, attribution: "© OpenStreetMap" };
const fecha = (iso: string) => new Date(iso).toLocaleDateString("es-CO", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Bogota" });
const fechaHora = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "long", year: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Bogota" });
type Tamano = "carta" | "oficio";
// El membrete se repite en cada página con las cajas de margen de @page (Chrome y Edge desde la versión 131). En un navegador sin ellas va una sola vez:
// el logo arriba de la primera página y la franja al final.
const CON_CAJAS = (() => { const m = typeof navigator !== "undefined" ? /(?:Chrome|Edg)\/(\d+)/.exec(navigator.userAgent) : null; return !!m && Number(m[1]) >= 131; })();
const FILAS_CARTA = 6;      // con más puntos, la tabla no cabe bien en carta: se propone oficio

export function HojaLevantamiento({ estado, onCerrar }: { estado: "abiertos" | "reportado" | "asignado"; onCerrar: () => void }) {
  const [d, setD] = useState<HojaLevantar | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tamano, setTamano] = useState<Tamano>("carta");
  const [mapa, setMapa] = useState<{ img: string | null; marcas: { n: number; x: number; y: number }[] } | null>(null);
  const [fotos, setFotos] = useState(0);
  const lienzo = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let vivo = true;
    apiLev.hoja(estado).then((r) => { if (vivo) { setD(r); setTamano(r.puntos.length > FILAS_CARTA ? "oficio" : "carta"); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor de distribución o el administrador descargan la hoja de levantamiento." : e instanceof Error ? e.message : "No se pudo preparar la hoja."); });
    return () => { vivo = false; };
  }, [estado]);

  // El mapa del sector: se dibuja una vez con MapLibre y se convierte en imagen (para que salga igual en el PDF); los números van encima, en HTML.
  useEffect(() => {
    if (!d || !d.puntos.length || !lienzo.current) return;
    let vivo = true; let hecho = false;
    const b = new maplibregl.LngLatBounds([d.puntos[0].lon, d.puntos[0].lat], [d.puntos[0].lon, d.puntos[0].lat]);
    for (const p of d.puntos) b.extend([p.lon, p.lat]);
    const m = new maplibregl.Map({ container: lienzo.current, interactive: false, attributionControl: false, preserveDrawingBuffer: true, bounds: b, fitBoundsOptions: { padding: 48, maxZoom: 17.5 },
      style: { version: 8, sources: { base: BASE, ruta: { type: "geojson", data: { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: d.puntos.map((p) => [p.lon, p.lat]) } } } },
        layers: [{ id: "fondo", type: "background", paint: { "background-color": "#f2f5f8" } }, { id: "base", type: "raster", source: "base" },
                 { id: "ruta", type: "line", source: "ruta", paint: { "line-color": "#0a2540", "line-width": 1.5, "line-dasharray": [2, 2] } }] } });
    m.on("error", () => {});
    const tomar = () => {
      if (!vivo || hecho) return; hecho = true;
      const c = m.getCanvas(); let img: string | null = null;
      try { img = c.toDataURL("image/png"); } catch { img = null; }      // si el mapa base no deja leer el lienzo, quedan el recorrido y los números
      const caja = lienzo.current!.getBoundingClientRect();
      setMapa({ img, marcas: d.puntos.map((p) => { const q = m.project([p.lon, p.lat]); return { n: p.n, x: (q.x / caja.width) * 100, y: (q.y / caja.height) * 100 }; }) });
      m.remove();
    };
    m.once("idle", tomar);
    const reloj = setTimeout(tomar, 6000);      // sin señal el mapa base no llega: la hoja sale igual
    return () => { vivo = false; clearTimeout(reloj); if (!hecho) m.remove(); };
  }, [d]);

  const conFoto = d ? d.puntos.filter((p) => p.foto_url).length : 0;
  const lista = !!d && (d.puntos.length === 0 || (mapa !== null && fotos >= conFoto));
  return createPortal(
    <div className={`hoja-capa${CON_CAJAS ? " hoja-con-cajas" : ""}`} role="dialog" aria-modal="true" aria-label="Hoja de levantamiento" data-testid="hoja" data-tamano={tamano} data-lista={lista ? "si" : "no"}>
      <style>{`@page { size: 8.5in ${tamano === "carta" ? 11 : 13}in; margin: 2.5cm 3cm 4cm 3cm; @top-left { content: "Página " counter(page) " de " counter(pages); font: 9pt Arial, Helvetica, sans-serif; color: #52626f; }
        @top-right { content: ""; width: 6cm; background: url("${logo}") right center / 4.4cm auto no-repeat; }
        @bottom-left-corner { content: ""; background: url("${membrete}") 0 bottom / 21.59cm auto no-repeat; }
        @bottom-center { content: ""; width: 15.59cm; background: url("${membrete}") -3cm bottom / 21.59cm auto no-repeat; }
        @bottom-right-corner { content: ""; background: url("${membrete}") -18.59cm bottom / 21.59cm auto no-repeat; } }`}</style>
      <div className="hoja-barra">
        <strong>Hoja de levantamiento</strong>
        <div className="hoja-barra-acc" role="group" aria-label="Tamaño de la hoja">
          <button type="button" className="dan-opcion" aria-pressed={tamano === "carta"} data-tamano-b="carta" onClick={() => setTamano("carta")}>Carta</button>
          <button type="button" className="dan-opcion" aria-pressed={tamano === "oficio"} data-tamano-b="oficio" onClick={() => setTamano("oficio")}>Oficio (8,5 × 13 in)</button>
        </div>
        <div className="hoja-barra-acc">
          <button type="button" className="tec-boton" disabled={!lista || !d?.puntos.length} data-testid="hoja-imprimir" onClick={() => window.print()}>{lista ? "Imprimir o guardar como PDF" : "Preparando la hoja…"}</button>
          <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cerrar</button>
        </div>
        <p className="hoja-ayuda">En la ventana de impresión elija «Guardar como PDF» y el tamaño {tamano === "carta" ? "carta" : "oficio (8,5 × 13 in)"}, sin encabezados ni pies del navegador.</p>
      </div>
      {error ? <p className="tec-aviso tec-aviso-error hoja-aviso" role="alert">{error}</p> : null}
      {!d && !error ? <p className="hoja-aviso" role="status">Preparando la hoja…</p> : null}
      {d ? (
        <div className={`hoja-papel hoja-${tamano}`}>
          <img className="hoja-logo" src={logo} alt="" aria-hidden="true" />
          <img className="hoja-franja" src={membrete} alt="" aria-hidden="true" />
          <h1>Otros activos por levantamiento</h1>
          <p className="hoja-sub">Hoja de levantamiento · generada el {fechaHora(d.generado_en)} · {d.puntos.length === 1 ? "1 punto" : `${d.puntos.length} puntos`}, numerados en el orden del recorrido
            {d.recortada ? ` (son ${d.total} por levantar: esta hoja trae los ${d.puntos.length} más antiguos)` : ""}.</p>
          {d.puntos.length === 0 ? <p>No hay activos por levantar.</p> : (
            <>
              <figure className="hoja-mapa" data-testid="hoja-mapa">
                {mapa ? <>{mapa.img ? <img className="hoja-mapa-img" src={mapa.img} alt="Mapa del sector con los puntos numerados" /> : <div className="hoja-mapa-img" />}
                  {mapa.marcas.map((x) => <span key={x.n} className="hoja-num" style={{ left: `${x.x}%`, top: `${x.y}%` }}>{x.n}</span>)}</>
                  : <div ref={lienzo} className="hoja-mapa-lienzo" />}
                <figcaption>Mapa del sector. Los números son los de la tabla; la línea punteada es el recorrido sugerido. Mapa base © OpenStreetMap.</figcaption>
              </figure>
              <table className="hoja-tabla">
                <thead><tr><th>N.º</th><th>Tipo y servicio</th><th>Fecha</th><th>Coordenadas</th><th>Precisión</th><th>Foto</th><th>Observación</th></tr></thead>
                <tbody>
                  {d.puntos.map((p) => (
                    <tr key={p.codigo} data-punto={p.codigo}>
                      <td className="hoja-n"><strong>{p.n}</strong><br /><span className="hoja-cod">{p.codigo}</span></td>
                      <td>{p.tipo_nombre}<br />{p.servicio === "acueducto" ? "Acueducto" : "Alcantarillado"}{p.sector ? <><br /><span className="hoja-cod">{p.sector}</span></> : null}</td>
                      <td>{fecha(p.registrado_en)}<br /><span className="hoja-cod">{p.estado_nombre}</span></td>
                      <td className="hoja-coord">{p.lat.toFixed(6)}<br />{p.lon.toFixed(6)}</td>
                      <td>± {Math.round(p.precision_m)} m{p.precision_baja ? <><br /><strong>Precisión baja</strong></> : null}</td>
                      <td className="hoja-foto">{p.foto_url ? <img src={p.foto_url} alt={`Foto de ${p.codigo}`} onLoad={() => setFotos((x) => x + 1)} onError={() => setFotos((x) => x + 1)} /> : "Sin foto"}</td>
                      <td className="hoja-obs">{p.observacion ?? "—"}</td>
                    </tr>))}
                </tbody>
              </table>
            </>)}
        </div>
      ) : null}
    </div>, document.body);
}
