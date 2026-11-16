import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../lib/mapaBase";
import type { PuntoMapa } from "./apiTecnica";

// Minimapa de PUNTOS (modo punto, 01 §I y adenda §2; Corte 5b): una sola capa, sin interruptores, para ELEGIR TOCANDO el punto de muestreo.
// · Verificada (David, o el GPS del operador aprobado): círculo lleno. Aproximada (centro del barrio): círculo hueco con un halo, porque el punto real está cerca, no ahí.
// · En revisión (hay una ubicación propuesta esperando al supervisor): borde morado.
// · Lo elegido se resalta; el mapa se lleva hasta allá si quedó fuera de la vista. «Yo» (GPS del celular) y «propuesta» (Dashboard PTAP) se dibujan aparte.
// · Sin interacción («onElegir» ausente) sirve de referencia en el Dashboard PTAP. Pensado para 390 px y una mano; sin señal se queda con lo que cargó.

const SEL = "#D6336C";
type Marca = { lat: number; lon: number };
function fc(puntos: PuntoMapa[]): GeoJSON.FeatureCollection {
  return { type: "FeatureCollection", features: puntos.map((p) => ({ type: "Feature", properties: { codigo: p.codigo, exactitud: p.exactitud, en_revision: p.en_revision }, geometry: { type: "Point", coordinates: [p.lon, p.lat] } })) };
}
const unPunto = (m: Marca | null | undefined): GeoJSON.FeatureCollection => ({ type: "FeatureCollection", features: m ? [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [m.lon, m.lat] } }] : [] });

export function MiniMapaPuntos({ puntos, elegido, onElegir, yo, propuesta, bajo = false, etiqueta = "Mapa de los puntos de muestreo: toque un punto para elegirlo" }: {
  puntos: PuntoMapa[]; elegido: string; onElegir?: (codigo: string) => void; yo?: Marca | null; propuesta?: Marca | null; bajo?: boolean; etiqueta?: string;
}) {
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const elegirRef = useRef(onElegir);
  elegirRef.current = onElegir;
  const [listo, setListo] = useState(false);

  useEffect(() => {
    if (!cont.current) return;
    const m = new maplibregl.Map({
      container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 12.5, maxZoom: 19, minZoom: 10, attributionControl: { compact: true },
      interactive: !!onElegir || !bajo, dragRotate: false, pitchWithRotate: false, touchPitch: false,
      style: {
        version: 8,
        sources: { base: FUENTE_BASE_CALLES, puntos: { type: "geojson", data: fc(puntos) }, yo: { type: "geojson", data: unPunto(yo) }, propuesta: { type: "geojson", data: unPunto(propuesta) } },
        layers: [
          { id: "base", type: "raster", source: "base" },
          { id: "yo-halo", type: "circle", source: "yo", paint: { "circle-radius": 14, "circle-color": "rgba(37,99,235,0.18)" } },
          { id: "yo", type: "circle", source: "yo", paint: { "circle-radius": 6, "circle-color": "#2563EB", "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2 } },
          { id: "halo-aprox", type: "circle", source: "puntos", filter: ["==", ["get", "exactitud"], "aproximada"],
            paint: { "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 10, 17, 26], "circle-color": "rgba(194,65,12,0.10)", "circle-stroke-color": "rgba(194,65,12,0.35)", "circle-stroke-width": 1 } },
          { id: "puntos", type: "circle", source: "puntos",
            paint: {
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 6, 17, 10],
              "circle-color": ["match", ["get", "exactitud"], "verificada", "#0F766E", "#FFFFFF"],
              "circle-stroke-color": ["case", ["get", "en_revision"], "#6D28D9", ["==", ["get", "exactitud"], "verificada"], "#FFFFFF", "#C2410C"],
              "circle-stroke-width": ["case", ["get", "en_revision"], 4, 2.5] } },
          { id: "sel", type: "circle", source: "puntos", filter: ["==", ["get", "codigo"], ""],
            paint: { "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 12, 17, 16], "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": SEL, "circle-stroke-width": 4 } },
          { id: "propuesta", type: "circle", source: "propuesta", paint: { "circle-radius": 8, "circle-color": "#6D28D9", "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2.5 } },
        ],
      },
    });
    m.on("error", () => {});      // sin señal, la base de calles puede fallar: los puntos se dibujan igual
    mapa.current = m;
    (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;     // para las pruebas en Chrome (no se usa en la app)
    const enmarcar = () => {
      const pts = [...puntos.map((p) => [p.lon, p.lat] as [number, number]), ...(propuesta ? [[propuesta.lon, propuesta.lat] as [number, number]] : [])];
      if (pts.length === 1) m.jumpTo({ center: pts[0], zoom: 16 });
      else if (pts.length > 1) {
        const b = pts.reduce((c, p) => c.extend(p), new maplibregl.LngLatBounds(pts[0], pts[0]));
        m.fitBounds(b, { padding: 36, maxZoom: 17, duration: 0 });
      }
    };
    enmarcar();
    m.on("click", (ev) => {
      if (!elegirRef.current) return;
      const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[ev.point.x - 18, ev.point.y - 18], [ev.point.x + 18, ev.point.y + 18]];
      const feats = m.queryRenderedFeatures(caja, { layers: ["puntos"] });
      if (!feats.length) return;
      const d = (f: maplibregl.MapGeoJSONFeature) => { const c = (f.geometry as GeoJSON.Point).coordinates; const p = m.project([c[0], c[1]]); return (p.x - ev.point.x) ** 2 + (p.y - ev.point.y) ** 2; };
      const cerca = feats.reduce((a, b) => (d(b) < d(a) ? b : a));
      elegirRef.current(String(cerca.properties?.codigo));
    });
    setListo(true);
    return () => { m.remove(); mapa.current = null; setListo(false); };
    // El mapa se crea una vez; los datos se actualizan abajo.
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // datos, marcas y lo elegido
  useEffect(() => {
    const m = mapa.current;
    if (!m) return;
    const aplicar = () => {
      (m.getSource("puntos") as maplibregl.GeoJSONSource | undefined)?.setData(fc(puntos));
      (m.getSource("yo") as maplibregl.GeoJSONSource | undefined)?.setData(unPunto(yo));
      (m.getSource("propuesta") as maplibregl.GeoJSONSource | undefined)?.setData(unPunto(propuesta));
      if (m.getLayer("sel")) m.setFilter("sel", ["==", ["get", "codigo"], elegido]);
      const p = puntos.find((x) => x.codigo === elegido);
      if (p && !m.getBounds().contains([p.lon, p.lat])) m.easeTo({ center: [p.lon, p.lat], zoom: Math.max(m.getZoom(), 15), duration: 0 });
    };
    if (m.getLayer("sel")) aplicar(); else m.once("styledata", aplicar);
  }, [puntos, elegido, yo, propuesta, listo]);

  // «yo» nuevo: el mapa va hasta allá
  useEffect(() => { if (yo && mapa.current) mapa.current.easeTo({ center: [yo.lon, yo.lat], zoom: Math.max(mapa.current.getZoom(), 16), duration: 0 }); }, [yo?.lat, yo?.lon]); // eslint-disable-line react-hooks/exhaustive-deps

  return <div ref={cont} className={bajo ? "mue-mapa mue-mapa-bajo" : "mue-mapa"} role="application" aria-label={etiqueta} />;
}

/** Distancia en metros entre dos puntos (haversine). */
export function distanciaM(a: Marca, b: Marca): number {
  const r = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/** La leyenda del minimapa (los mismos símbolos que el mapa). */
export function LeyendaPuntos() {
  return (
    <ul className="mue-leyenda" aria-label="Qué significa cada símbolo">
      <li><span className="mue-simb mue-simb-ver" aria-hidden="true" /> Ubicación verificada</li>
      <li><span className="mue-simb mue-simb-aprox" aria-hidden="true" /> Aproximada (centro del barrio)</li>
      <li><span className="mue-simb mue-simb-rev" aria-hidden="true" /> En revisión del supervisor</li>
    </ul>
  );
}
