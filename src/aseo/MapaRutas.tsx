import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../lib/mapaBase";
import type { GeoFeature } from "./tipos";

// Mapa de rutas de Aseo. MapLibre PROPIO: no importa ni monta nada comercial (ni MapView, ni teselas del geoportal, ni consultas a Edge comerciales). Las rutas llegan como GeoJSON simplificado de la Edge de Aseo.
// Calles de OpenStreetMap activadas por omisión (un auditor sin calles no se orienta; es el mismo ráster que ya usa el geoportal y no trae datos comerciales); botón para ocultarlas. Fondo liso si la red falla.
// Selección por toque: se consultan las capas en un cuadro de ±12 px alrededor del toque y se entregan TODAS las rutas que pasan por ahí (la relación ruta–barrio es de muchos a muchos: puede haber varias).
// Se carga bajo demanda (React.lazy): es el único archivo de Aseo que descarga MapLibre.
export type PropsMapaRutas = {
  features: GeoFeature[]; posicion: { lat: number; lon: number; precision: number } | null; zoomInicial: number; seleccionada: number | null; resaltadas?: number[];
  onToque: (rutaIds: number[]) => void;
};
const COLOR = "#0072B2", COLOR_SEL = "#D55E00";

export default function MapaRutas({ features, posicion, zoomInicial, seleccionada, resaltadas = [], onToque }: PropsMapaRutas) {
  const cont = useRef<HTMLDivElement>(null); const mapa = useRef<maplibregl.Map | null>(null); const listo = useRef(false);
  const [calles, setCalles] = useState(true); const [fallo, setFallo] = useState<string | null>(null);
  const cbToque = useRef(onToque); cbToque.current = onToque;
  const centrado = useRef(false);

  const datos = useMemo(() => ({ type: "FeatureCollection" as const, features: features.map((f) => ({ ...f, properties: { ...f.properties, sel: f.properties.ruta_id === seleccionada ? 1 : 0, res: resaltadas.includes(f.properties.ruta_id) ? 1 : 0 } })) }) as unknown as GeoJSON.FeatureCollection, [features, seleccionada, resaltadas]);
  const datosRef = useRef(datos); datosRef.current = datos;
  const pos = useMemo(() => ({ type: "FeatureCollection" as const, features: posicion ? [{ type: "Feature" as const, properties: { precision: posicion.precision }, geometry: { type: "Point" as const, coordinates: [posicion.lon, posicion.lat] } }] : [] }), [posicion]);
  const posRef = useRef(pos); posRef.current = pos;

  useEffect(() => {
    if (!cont.current || mapa.current) return;
    let m: maplibregl.Map;
    try {
      m = new maplibregl.Map({ container: cont.current, center: posicion ? [posicion.lon, posicion.lat] : CENTRO_VALLEDUPAR, zoom: zoomInicial, attributionControl: { compact: true },
        style: { version: 8, sources: {}, layers: [{ id: "fondo", type: "background", paint: { "background-color": "#eef2f5" } }] } });
    } catch { setFallo("Este navegador no puede mostrar el mapa. Use la búsqueda."); return; }
    mapa.current = m;
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    m.on("load", () => {
      m.addSource("osm", FUENTE_BASE_CALLES); m.addLayer({ id: "osm", type: "raster", source: "osm", paint: { "raster-opacity": 0.85 } });
      m.addSource("rutas", { type: "geojson", data: datosRef.current });
      m.addSource("yo", { type: "geojson", data: posRef.current });
      m.addLayer({ id: "rutas-area", type: "fill", source: "rutas", filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": COLOR, "fill-opacity": ["case", ["==", ["get", "sel"], 1], 0.35, 0.12] } });
      m.addLayer({ id: "rutas-borde", type: "line", source: "rutas", filter: ["==", ["geometry-type"], "Polygon"], paint: { "line-color": ["case", ["==", ["get", "sel"], 1], COLOR_SEL, COLOR], "line-width": ["case", ["==", ["get", "sel"], 1], 3, 1.2] } });
      m.addLayer({ id: "rutas-hit", type: "line", source: "rutas", filter: ["==", ["geometry-type"], "LineString"], layout: { "line-cap": "round" }, paint: { "line-color": "#000", "line-opacity": 0, "line-width": 26 } });    // zona ancha para el dedo
      m.addLayer({ id: "rutas-linea", type: "line", source: "rutas", filter: ["==", ["geometry-type"], "LineString"], layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": ["case", ["==", ["get", "sel"], 1], COLOR_SEL, ["==", ["get", "res"], 1], "#E69F00", COLOR], "line-width": ["case", ["==", ["get", "sel"], 1], 6, 4] } });
      m.addLayer({ id: "rutas-punto", type: "circle", source: "rutas", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 8, "circle-color": ["case", ["==", ["get", "sel"], 1], COLOR_SEL, COLOR], "circle-stroke-color": "#fff", "circle-stroke-width": 2 } });
      m.addLayer({ id: "yo-halo", type: "circle", source: "yo", paint: { "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 6, 18, ["max", 8, ["/", ["get", "precision"], 0.3]]], "circle-color": "#1d4ed8", "circle-opacity": 0.15, "circle-stroke-color": "#1d4ed8", "circle-stroke-width": 1 } });
      m.addLayer({ id: "yo", type: "circle", source: "yo", paint: { "circle-radius": 7, "circle-color": "#1d4ed8", "circle-stroke-color": "#fff", "circle-stroke-width": 3 } });
      m.on("click", (e) => {
        const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[e.point.x - 12, e.point.y - 12], [e.point.x + 12, e.point.y + 12]];
        const ids = new Set<number>();
        for (const f of m.queryRenderedFeatures(caja, { layers: ["rutas-hit", "rutas-area", "rutas-punto"] })) { const id = Number((f.properties as { ruta_id?: number } | null)?.ruta_id); if (Number.isFinite(id)) ids.add(id); }
        cbToque.current([...ids]);
      });
      listo.current = true;
      if (datosRef.current.features.length && !posRef.current.features.length) ajustar(m, features);
    });
    return () => { listo.current = false; m.remove(); mapa.current = null; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => { const m = mapa.current; if (m && listo.current) (m.getSource("rutas") as maplibregl.GeoJSONSource | undefined)?.setData(datos); }, [datos]);
  useEffect(() => {
    const m = mapa.current; if (!m || !listo.current) return;
    (m.getSource("yo") as maplibregl.GeoJSONSource | undefined)?.setData(pos);
    if (posicion && !centrado.current) { centrado.current = true; m.jumpTo({ center: [posicion.lon, posicion.lat], zoom: zoomInicial }); }
  }, [pos, posicion, zoomInicial]);
  useEffect(() => { const m = mapa.current; if (m && listo.current && m.getLayer("osm")) m.setLayoutProperty("osm", "visibility", calles ? "visible" : "none"); }, [calles]);

  if (fallo) return <div className="aseo-aviso" role="alert">{fallo}</div>;
  return (
    <div className="aseo-mapa-caja">
      <div ref={cont} className="aseo-mapa" role="application" aria-label="Mapa de rutas" />
      <div className="aseo-mapa-ctl">
        <button type="button" className="tec-boton-sec aseo-corto" aria-pressed={calles} onClick={() => setCalles((x) => !x)}>{calles ? "Ocultar calles" : "Mostrar calles"}</button>
        <button type="button" className="tec-boton-sec aseo-corto" onClick={() => { const m = mapa.current; if (m && posicion) m.easeTo({ center: [posicion.lon, posicion.lat], zoom: Math.max(m.getZoom(), 16) }); }} disabled={!posicion}>Acercar a mi posición</button>
      </div>
    </div>
  );
}

function ajustar(m: maplibregl.Map, feats: GeoFeature[]) {
  const b = new maplibregl.LngLatBounds();
  const rec = (c: unknown) => { if (Array.isArray(c) && typeof c[0] === "number") b.extend(c as [number, number]); else if (Array.isArray(c)) c.forEach(rec); };
  feats.forEach((f) => rec(f.geometry.coordinates));
  if (!b.isEmpty()) m.fitBounds(b, { padding: 40, maxZoom: 16, duration: 0 });
}
