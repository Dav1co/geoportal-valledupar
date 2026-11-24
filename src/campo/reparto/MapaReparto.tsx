import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import { apiReparto, avisoDeError, type Punto } from "./apiReparto";
import { INTERVALO_MAPA_MS, textoHora, unirPuntos } from "./logica";

// Mapa EN VIVO del supervisor de reparto (David, 23 y 24-nov): puntos numerados por el orden de entrega, que se actualizan solos cada 10 s SOLO con la pestaña
// visible (consulta periódica con el cursor «despues»: solo llegan los nuevos y las anuladas), sin recargar. La línea del recorrido está apagada por omisión.
// MapLibre propio, sin glifos: cada número se dibuja en un canvas la primera vez que se necesita. Nada comercial. Sin nombre ni dirección del suscriptor.
const PALETA = ["#782a27", "#1f5fa8", "#2e7d32", "#8a4300", "#6a1b9a", "#00838f", "#ad1457", "#4e342e"];

function numero(n: number, color: string, anulada: boolean): ImageData {
  const t = n >= 100 ? 40 : 32, c = document.createElement("canvas"); c.width = c.height = t;
  const x = c.getContext("2d")!;
  x.beginPath(); x.arc(t / 2, t / 2, t / 2 - 2, 0, Math.PI * 2); x.fillStyle = anulada ? "#9aa5b1" : color; x.fill();
  x.lineWidth = 2; x.strokeStyle = "#fff"; x.stroke();
  x.fillStyle = "#fff"; x.font = `bold ${n >= 100 ? 13 : 15}px system-ui, sans-serif`; x.textAlign = "center"; x.textBaseline = "middle"; x.fillText(String(n), t / 2, t / 2 + 1);
  if (anulada) { x.strokeStyle = "#7d2118"; x.lineWidth = 3; x.beginPath(); x.moveTo(5, t - 5); x.lineTo(t - 5, 5); x.stroke(); }
  return x.getImageData(0, 0, t, t);
}

export default function MapaReparto({ fecha, enVivo }: { fecha: string; enVivo: boolean }) {
  const cont = useRef<HTMLDivElement>(null); const mapa = useRef<maplibregl.Map | null>(null); const listo = useRef(false);
  const [puntos, setPuntos] = useState<Punto[]>([]);
  const [ultimo, setUltimo] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [recorrido, setRecorrido] = useState(false);
  const [calles, setCalles] = useState(true);
  const [jornada, setJornada] = useState<number | "">("");
  const [actualizado, setActualizado] = useState<Date | null>(null);
  const [fallo, setFallo] = useState<string | null>(null);
  const ajustado = useRef(false);
  const ultimoRef = useRef<number | null>(null); ultimoRef.current = ultimo;

  // colores por jornada (repartidor y ruta)
  const jornadas = useMemo(() => [...new Map(puntos.map((p) => [p.jornada_id, p.repartidor])).entries()].sort((a, b) => a[0] - b[0]), [puntos]);
  const color = useMemo(() => new Map(jornadas.map(([id], i) => [id, PALETA[i % PALETA.length]])), [jornadas]);
  const visibles = useMemo(() => puntos.filter((p) => jornada === "" || p.jornada_id === jornada), [puntos, jornada]);
  const datos = useMemo(() => ({ type: "FeatureCollection" as const, features: visibles.map((p) => ({ type: "Feature" as const, geometry: { type: "Point" as const, coordinates: [p.lon, p.lat] },
    properties: { id: p.id, img: `n${p.consecutivo}-${(color.get(p.jornada_id) ?? PALETA[0]).slice(1)}${p.anulada ? "-x" : ""}`, anulada: p.anulada ? 1 : 0, consecutivo: p.consecutivo } })) }), [visibles, color]);
  const lineas = useMemo(() => ({ type: "FeatureCollection" as const, features: [...new Set(visibles.map((p) => p.jornada_id))].map((id) => ({ type: "Feature" as const,
    properties: { color: color.get(id) ?? PALETA[0] },
    geometry: { type: "LineString" as const, coordinates: visibles.filter((p) => p.jornada_id === id && !p.anulada).sort((a, b) => a.consecutivo - b.consecutivo).map((p) => [p.lon, p.lat]) } })) }), [visibles, color]);
  const datosRef = useRef(datos); datosRef.current = datos; const lineasRef = useRef(lineas); lineasRef.current = lineas;

  // consulta: la primera trae todo el día; las siguientes, solo lo nuevo (cursor) y las anuladas
  useEffect(() => {
    let vivo = true; setPuntos([]); setUltimo(null); ajustado.current = false; setError(null);
    const pedir = async (completo: boolean) => {
      try {
        const r = await apiReparto.mapa({ fecha, despues: completo ? null : ultimoRef.current });
        if (!vivo) return;
        setPuntos((act) => (completo ? r.puntos : unirPuntos(act, r.puntos, r.anuladas)));
        if (r.ultimo_id !== null) setUltimo(r.ultimo_id);
        setActualizado(new Date()); setError(null);
      } catch (e) { if (vivo) setError(avisoDeError(e)); }
    };
    void pedir(true);
    if (!enVivo) return () => { vivo = false; };
    const reloj = window.setInterval(() => { if (document.visibilityState === "visible") void pedir(false); }, INTERVALO_MAPA_MS);
    const alVolver = () => { if (document.visibilityState === "visible") void pedir(false); };
    document.addEventListener("visibilitychange", alVolver);
    return () => { vivo = false; window.clearInterval(reloj); document.removeEventListener("visibilitychange", alVolver); };
  }, [fecha, enVivo]);

  useEffect(() => {
    if (!cont.current || mapa.current) return;
    let m: maplibregl.Map;
    try {
      m = new maplibregl.Map({ container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 13, attributionControl: { compact: true },
        style: { version: 8, sources: {}, layers: [{ id: "fondo", type: "background", paint: { "background-color": "#eef2f5" } }] } });
    } catch { setFallo("Este navegador no puede mostrar el mapa. Use el avance y el detalle."); return; }
    mapa.current = m;
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    m.on("styleimagemissing", (e) => {
      const r = /^n(\d+)-([0-9a-f]{6})(-x)?$/.exec(e.id); if (!r || m.hasImage(e.id)) return;
      m.addImage(e.id, numero(Number(r[1]), `#${r[2]}`, !!r[3]), { pixelRatio: 2 });
    });
    m.on("load", () => {
      m.addSource("osm", FUENTE_BASE_CALLES); m.addLayer({ id: "osm", type: "raster", source: "osm", paint: { "raster-opacity": 0.85 } });
      m.addSource("recorrido", { type: "geojson", data: lineasRef.current });
      m.addLayer({ id: "recorrido", type: "line", source: "recorrido", layout: { visibility: "none" }, paint: { "line-color": ["get", "color"], "line-width": 2.5, "line-opacity": 0.8 } });
      m.addSource("puntos", { type: "geojson", data: datosRef.current });
      m.addLayer({ id: "puntos", type: "symbol", source: "puntos", layout: { "icon-image": ["get", "img"], "icon-size": 1, "icon-allow-overlap": true, "icon-ignore-placement": true, "symbol-sort-key": ["get", "consecutivo"] } });
      m.on("click", "puntos", (e) => {
        const id = (e.features?.[0]?.properties as { id?: number } | undefined)?.id; const p = puntosRef.current.find((x) => x.id === id); if (!p) return;
        new maplibregl.Popup({ closeButton: true }).setLngLat([p.lon, p.lat])
          .setHTML(`<strong>Entrega ${p.consecutivo}</strong><br>Contrato ${p.contrato}<br>${textoHora(p.hora)} · ± ${Math.round(p.precision_m)} m${p.anulada ? "<br><em>Anulada</em>" : ""}`).addTo(m);
      });
      m.on("mouseenter", "puntos", () => { m.getCanvas().style.cursor = "pointer"; }); m.on("mouseleave", "puntos", () => { m.getCanvas().style.cursor = ""; });
      listo.current = true;
    });
    return () => { listo.current = false; m.remove(); mapa.current = null; };
  }, []);
  const puntosRef = useRef(puntos); puntosRef.current = puntos;

  useEffect(() => {
    const m = mapa.current; if (!m || !listo.current) return;
    (m.getSource("puntos") as maplibregl.GeoJSONSource | undefined)?.setData(datos);
    (m.getSource("recorrido") as maplibregl.GeoJSONSource | undefined)?.setData(lineas);
    if (!ajustado.current && datos.features.length) {
      const b = new maplibregl.LngLatBounds(); for (const f of datos.features) b.extend(f.geometry.coordinates as [number, number]);
      m.fitBounds(b, { padding: 40, maxZoom: 17, duration: 0 }); ajustado.current = true;
    }
  }, [datos, lineas]);
  useEffect(() => { const m = mapa.current; if (m && listo.current) m.setLayoutProperty("recorrido", "visibility", recorrido ? "visible" : "none"); }, [recorrido]);
  useEffect(() => { const m = mapa.current; if (m && listo.current && m.getLayer("osm")) m.setLayoutProperty("osm", "visibility", calles ? "visible" : "none"); }, [calles]);
  useEffect(() => { ajustado.current = false; }, [jornada]);

  if (fallo) return <p className="rep-aviso rep-aviso-error" role="alert">{fallo}</p>;
  return (
    <section className="rep-bloque" aria-label="Mapa en vivo" data-bloque="mapa">
      <div className="rep-mapa-ctl">
        <label className="rep-campo-linea">Repartidor y ruta
          <select value={jornada} onChange={(e) => setJornada(e.target.value ? Number(e.target.value) : "")} data-campo="jornada">
            <option value="">Todos</option>
            {jornadas.map(([id, rep]) => <option key={id} value={id}>{rep} · jornada {id}</option>)}
          </select>
        </label>
        <label className="rep-campo-linea"><input type="checkbox" checked={recorrido} onChange={(e) => setRecorrido(e.target.checked)} data-campo="recorrido" /> Mostrar el recorrido</label>
        <label className="rep-campo-linea"><input type="checkbox" checked={calles} onChange={(e) => setCalles(e.target.checked)} /> Calles</label>
        <span className="rep-suave" data-dato="estado-mapa">{visibles.length} entregas · {enVivo ? `en vivo cada ${INTERVALO_MAPA_MS / 1000} s` : "día cerrado"}{actualizado ? ` · actualizado ${actualizado.toLocaleTimeString("es-CO", { timeZone: "America/Bogota" })}` : ""}</span>
      </div>
      {error ? <p className="rep-aviso rep-aviso-error" role="alert">{error}</p> : null}
      <div ref={cont} className="rep-mapa" role="application" aria-label="Mapa de las entregas" />
    </section>
  );
}
