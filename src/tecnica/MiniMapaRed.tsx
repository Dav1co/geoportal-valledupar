import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import { apiDano, type ActivoCorto, type ActivoUbicado, type TramoNodos } from "./apiRedes";

// Minimapa de UNA sola red (01 §I, adenda §2), sin interruptores: para ELEGIR TOCANDO el activo del daño.
// · Tesela liviana propia (geoportal-redes ?accion=tesela): código, prefijo, clase, forma y si va punteado. Nada de material, edad ni origen.
// · Desde el zoom mínimo (15) se ve la red; los accesorios, desde el 17 (los filtra el servidor). Debajo, «Acerque el mapa».
// · Tocar un nodo (válvula, pozo, accesorio…) lo elige. Tocar un tramo lo resalta y muestra sus dos nodos para quedarse con el tramo o con un nodo.
// · Modo «no identificado»: tocar el mapa marca el punto, sin activo.
// · Modo «línea» (Corte 3a, inversión en un tramo nuevo): tocar el inicio y el fin; un tercer toque vuelve a empezar. Lo marcado se dibuja.
// · Pensado para 390 px y una mano: mapa al 55 % del alto, botones de 44 px o más.

export type Eleccion = { tipo: "activo"; activo: ActivoUbicado } | { tipo: "punto"; lat: number; lon: number } | { tipo: "linea"; puntos: { lat: number; lon: number }[] };
const VACIO = { type: "FeatureCollection" as const, features: [] as GeoJSON.Feature[] };
function dibujo(e: Eleccion | null): GeoJSON.FeatureCollection {
  if (e?.tipo === "punto") return { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [e.lon, e.lat] } }] };
  if (e?.tipo === "linea") {
    const f: GeoJSON.Feature[] = e.puntos.map((p, i) => ({ type: "Feature", properties: { n: i + 1 }, geometry: { type: "Point", coordinates: [p.lon, p.lat] } }));
    if (e.puntos.length > 1) f.push({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: e.puntos.map((p) => [p.lon, p.lat]) } });
    return { type: "FeatureCollection", features: f };
  }
  return VACIO;
}
const COLOR: Record<string, string> = { acueducto: "#1F5FA8", alcantarillado: "#8A5A2B" };
const SEL = "#D6336C";

export function MiniMapaRed({ sistema, centro, eleccion, modoPunto, modoLinea = false, textoPunto = "Toque el mapa donde está el daño", zoomMin, onElegir }: {
  sistema: "acueducto" | "alcantarillado"; centro: { lat: number; lon: number } | null; eleccion: Eleccion | null; modoPunto: boolean; modoLinea?: boolean; textoPunto?: string; zoomMin: number;
  onElegir: (e: Eleccion) => void;
}) {
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const token = useRef<string | null>(null);
  const modoRef = useRef(modoPunto);
  const lineaRef = useRef(modoLinea);
  const elegirRef = useRef(onElegir);
  const eleccionRef = useRef(eleccion);
  const [zoom, setZoom] = useState(17);
  const [tramo, setTramo] = useState<TramoNodos | null>(null);
  const [cargandoTramo, setCargandoTramo] = useState(false);
  const [error, setError] = useState<string | null>(null);
  modoRef.current = modoPunto;
  lineaRef.current = modoLinea;
  elegirRef.current = onElegir;
  eleccionRef.current = eleccion;

  useEffect(() => {
    let vivo = true;
    let m: maplibregl.Map | null = null;
    void supabase.auth.getSession().then(({ data }) => {
      if (!vivo || !cont.current) return;
      token.current = data.session?.access_token ?? null;
      const c = centro ?? { lat: CENTRO_VALLEDUPAR[1], lon: CENTRO_VALLEDUPAR[0] };
      m = new maplibregl.Map({
        container: cont.current, center: [c.lon, c.lat], zoom: centro ? 17.5 : 15, maxZoom: 20, minZoom: 12, attributionControl: { compact: true },
        dragRotate: false, pitchWithRotate: false, touchPitch: false,
        transformRequest: (url) => (url.includes("accion=tesela") && token.current ? { url, headers: { Authorization: `Bearer ${token.current}` } } : { url }),
        style: {
          version: 8,
          sources: {
            base: FUENTE_BASE_CALLES,
            red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=tesela&sistema=${sistema}&z={z}&x={x}&y={y}&v=1`], minzoom: zoomMin, maxzoom: 18 },
            dibujo: { type: "geojson", data: dibujo(eleccionRef.current) },
          },
          layers: [
            { id: "base", type: "raster", source: "base" },
            { id: "tramos", type: "line", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "tramo"], ["!", ["get", "punteado"]]],
              paint: { "line-color": COLOR[sistema], "line-width": ["interpolate", ["linear"], ["zoom"], 15, 2, 19, 6] } },
            { id: "tramos-punteados", type: "line", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "tramo"], ["get", "punteado"]],
              paint: { "line-color": COLOR[sistema], "line-width": ["interpolate", ["linear"], ["zoom"], 15, 2, 19, 5], "line-dasharray": [2, 2], "line-opacity": 0.75 } },
            { id: "sel-tramo", type: "line", source: "red", "source-layer": "red", filter: ["==", ["get", "codigo"], ""], paint: { "line-color": SEL, "line-width": 8, "line-opacity": 0.85 } },
            { id: "nodos", type: "circle", source: "red", "source-layer": "red", filter: ["==", ["get", "forma"], "nodo"],
              paint: {
                "circle-radius": ["interpolate", ["linear"], ["zoom"], 15, ["match", ["get", "prefijo"], "ACC", 2, 3.5], 19, ["match", ["get", "prefijo"], "ACC", 5, 8]],
                "circle-color": ["match", ["get", "prefijo"], "VAL", "#C2410C", "TOR", "#0F766E", "ACC", "#9AA19B", "POZ", "#8A5A2B", "VER", "#5B21B6", "#1B1F1D"],
                "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 1.5 } },
            { id: "sel-nodo", type: "circle", source: "red", "source-layer": "red", filter: ["==", ["get", "codigo"], ""],
              paint: { "circle-radius": 11, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": SEL, "circle-stroke-width": 4 } },
            { id: "dibujo-linea", type: "line", source: "dibujo", filter: ["==", ["geometry-type"], "LineString"], paint: { "line-color": "#4B2A8A", "line-width": 5, "line-dasharray": [1.5, 1] } },
            { id: "dibujo-punto", type: "circle", source: "dibujo", filter: ["==", ["geometry-type"], "Point"],
              paint: { "circle-radius": 8, "circle-color": "#4B2A8A", "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2.5 } },
          ],
        },
      });
      mapa.current = m;
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;     // para las pruebas en Chrome (no se usa en la app)
      m.on("zoomend", () => setZoom(m!.getZoom()));
      setListo(true);
      m.on("click", (ev) => {
        if (!m) return;
        if (lineaRef.current) {
          const prev = eleccionRef.current?.tipo === "linea" ? eleccionRef.current.puntos : [];
          setTramo(null);
          elegirRef.current({ tipo: "linea", puntos: prev.length >= 2 ? [{ lat: ev.lngLat.lat, lon: ev.lngLat.lng }] : [...prev, { lat: ev.lngLat.lat, lon: ev.lngLat.lng }] });
          return;
        }
        if (modoRef.current) { setTramo(null); elegirRef.current({ tipo: "punto", lat: ev.lngLat.lat, lon: ev.lngLat.lng }); return; }
        const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[ev.point.x - 14, ev.point.y - 14], [ev.point.x + 14, ev.point.y + 14]];
        const feats = m.queryRenderedFeatures(caja, { layers: ["nodos", "tramos", "tramos-punteados"] });
        const nodo = feats.find((f) => f.properties?.forma === "nodo");
        if (nodo && nodo.geometry.type === "Point") {
          const [lon, lat] = nodo.geometry.coordinates as [number, number];
          setTramo(null);
          elegirRef.current({ tipo: "activo", activo: aActivo(nodo.properties as Record<string, unknown>, lat, lon) });
          return;
        }
        const t = feats.find((f) => f.properties?.forma === "tramo");
        if (t) {
          const props = t.properties as Record<string, unknown>;
          elegirRef.current({ tipo: "activo", activo: aActivo(props, ev.lngLat.lat, ev.lngLat.lng) });
          setCargandoTramo(true); setError(null);
          apiDano.tramoNodos(String(props.codigo)).then(setTramo).catch(() => setError("No se pudieron cargar los nodos del tramo.")).finally(() => setCargandoTramo(false));
        }
      });
    });
    return () => { vivo = false; m?.remove(); mapa.current = null; };
    // El mapa se crea una vez por sistema (cambiar de sistema monta otro minimapa).
  }, [sistema]); // eslint-disable-line react-hooks/exhaustive-deps

  // resaltar lo elegido y llevar el mapa hasta allá si quedó fuera de la vista (también cuando el mapa termina de crearse después de la preselección)
  const [listo, setListo] = useState(false);
  useEffect(() => {
    const m = mapa.current;
    if (!m) return;
    const aplicar = () => {
      const eleccion = eleccionRef.current;
      const cod = eleccion?.tipo === "activo" ? eleccion.activo.codigo : "";
      if (m.getLayer("sel-nodo")) {
        m.setFilter("sel-nodo", ["all", ["==", ["get", "forma"], "nodo"], ["==", ["get", "codigo"], cod]]);
        m.setFilter("sel-tramo", ["all", ["==", ["get", "forma"], "tramo"], ["==", ["get", "codigo"], cod]]);
      }
      (m.getSource("dibujo") as maplibregl.GeoJSONSource | undefined)?.setData(dibujo(eleccion));
      const p = eleccion?.tipo === "activo" ? eleccion.activo : eleccion?.tipo === "punto" ? eleccion : null;     // la línea se dibuja sin mover el mapa
      if (p && (!m.getBounds().contains([p.lon, p.lat]) || m.getZoom() < zoomMin)) m.easeTo({ center: [p.lon, p.lat], zoom: Math.max(m.getZoom(), 17.5), duration: 0 });
    };
    // las capas existen apenas se lee el estilo (aunque la base de calles no haya cargado, p. ej. sin señal): no se espera el evento «load»
    if (m.getLayer("sel-nodo")) aplicar(); else m.once("styledata", aplicar);
    if (eleccion?.tipo !== "activo" || (tramo && tramo.tramo.codigo !== eleccion.activo.codigo && !tramo.nodos.some((n) => n.activo?.codigo === eleccion.activo.codigo))) setTramo(null);
  }, [eleccion, zoomMin, listo]); // eslint-disable-line react-hooks/exhaustive-deps

  const elegirDelTramo = (a: ActivoCorto, lat: number, lon: number) => onElegir({ tipo: "activo", activo: { ...a, lat, lon } });

  return (
    <div className="dan-mini">
      <div ref={cont} className="dan-mini-mapa" role="application" aria-label={`Mapa de la red de ${sistema}: toque un tramo o un nodo`} data-zoom={zoom.toFixed(1)} />
      {zoom < zoomMin ? <div className="dan-mini-aviso" role="status">Acerque el mapa para ver la red</div> : null}
      {modoLinea ? <div className="dan-mini-aviso dan-mini-aviso-punto" role="status">{eleccion?.tipo === "linea" && eleccion.puntos.length === 1 ? "Ahora toque el fin del tramo nuevo" : eleccion?.tipo === "linea" && eleccion.puntos.length >= 2 ? "Tramo marcado (otro toque vuelve a empezar)" : "Toque el inicio del tramo nuevo"}</div>
        : modoPunto ? <div className="dan-mini-aviso dan-mini-aviso-punto" role="status">{textoPunto}</div> : null}
      {cargandoTramo ? <p className="tec-sub" role="status">Cargando los nodos del tramo…</p> : null}
      {error ? <p className="tec-error-caja">{error}</p> : null}
      {tramo ? (
        <div className="dan-tramo" aria-label="Tramo y sus nodos">
          <p className="dan-tramo-tit">Eligió el tramo <strong>{tramo.tramo.codigo}</strong>. ¿El daño está en el tramo o en uno de sus nodos?</p>
          <div className="dan-tramo-opciones">
            <button type="button" className="dan-opcion" aria-pressed={eleccion?.tipo === "activo" && eleccion.activo.codigo === tramo.tramo.codigo}
              onClick={() => { const p = eleccion?.tipo === "activo" ? eleccion.activo : null; elegirDelTramo(tramo.tramo, p?.lat ?? tramo.nodos[0]?.lat ?? 0, p?.lon ?? tramo.nodos[0]?.lon ?? 0); }}>
              Tramo {tramo.tramo.codigo}
            </button>
            {tramo.nodos.map((n) => n.activo
              ? <button key={n.rol} type="button" className="dan-opcion" aria-pressed={eleccion?.tipo === "activo" && eleccion.activo.codigo === n.activo.codigo}
                  onClick={() => elegirDelTramo(n.activo!, n.lat, n.lon)}>{n.rol === "inicio" ? "Desde" : "Hasta"}: {n.nombre} ({n.activo.tipo})</button>
              : <span key={n.rol} className="dan-opcion dan-opcion-off">{n.rol === "inicio" ? "Desde" : "Hasta"}: {n.nombre} (nodo sin activo)</span>)}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function aActivo(p: Record<string, unknown>, lat: number, lon: number): ActivoUbicado {
  return { codigo: String(p.codigo), prefijo: String(p.prefijo), tipo: String(p.prefijo), clase: p.clase ? String(p.clase) : undefined,
           estado: "", estado_codigo: "", retirado: false, lat, lon };
}
