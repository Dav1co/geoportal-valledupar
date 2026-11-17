import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { circulo, type ActivoCerca, type PuntoCerca, type Servicio } from "./apiLevantar";

// Minimapa de «Encontrar o reportar activo» (Corte 14). Siempre centrado en la persona: NO se arrastra ni se mueve el punto; el nivel de zoom lo pone la
// pantalla (encuadre del círculo de búsqueda, entre 18 y 20). Dibuja el punto azul con su círculo de precisión, el círculo de búsqueda, los activos cercanos
// (los manda el servidor ya recortados) con su número de la lista y su código, y los puntos por levantar que ya hay ahí. Los nombres de las calles vienen
// del mapa base (OpenStreetMap, que llega hasta el nivel 19: en el 20 se ve ampliado). Números y códigos son marcas de HTML (sin fuentes de mapa).
// Los niveles del encargo (18 a 20) son los del mapa de calles (teselas de 256 px: nivel 20 ≈ 57 m de ancho en 390 px). MapLibre cuenta con teselas de
// 512 px, así que su zoom es ese nivel menos 1 (DESFASE).
const DESFASE = 1;
const COLOR: Record<Servicio, string> = { acueducto: "#1F5FA8", alcantarillado: "#8A5A2B" };      // los del geovisor
const PERSONA = "#4a90d9", POR_LEVANTAR = "#c25e00";
const BASE = { type: "raster" as const, tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], tileSize: 256, maxzoom: 19, attribution: "© OpenStreetMap" };
type FC = { type: "FeatureCollection"; features: { type: "Feature"; properties: Record<string, unknown>; geometry: unknown }[] };
const fc = (features: FC["features"]): FC => ({ type: "FeatureCollection", features });

export function MiniMapaEncontrar({ lat, lon, precision_m, radio_m, zoom, servicio, activos, puntos, resaltado }: {
  lat: number; lon: number; precision_m: number | null; radio_m: number; zoom: number; servicio: Servicio; activos: ActivoCerca[]; puntos: PuntoCerca[]; resaltado?: string | null;
}) {
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const marcas = useRef<maplibregl.Marker[]>([]);
  const persona = useRef<maplibregl.Marker | null>(null);
  const listo = useRef(false);
  const ultimo = useRef({ lat, lon, precision_m, radio_m, zoom, servicio, activos, puntos, resaltado });
  ultimo.current = { lat, lon, precision_m, radio_m, zoom, servicio, activos, puntos, resaltado };

  function pintar() {
    const m = mapa.current; if (!m || !listo.current) return;
    const u = ultimo.current;
    m.jumpTo({ center: [u.lon, u.lat], zoom: u.zoom - DESFASE });
    (m.getSource("precision") as maplibregl.GeoJSONSource | undefined)?.setData(fc(u.precision_m ? [{ type: "Feature", properties: {}, geometry: circulo(u.lat, u.lon, u.precision_m) }] : []) as never);
    (m.getSource("radio") as maplibregl.GeoJSONSource | undefined)?.setData(fc([{ type: "Feature", properties: {}, geometry: circulo(u.lat, u.lon, u.radio_m) }]) as never);
    (m.getSource("activos") as maplibregl.GeoJSONSource | undefined)?.setData(fc(u.activos.filter((a) => a.geometria).map((a) => (
      { type: "Feature", properties: { codigo: a.codigo, forma: a.forma, sel: a.codigo === u.resaltado }, geometry: a.geometria }))) as never);
    for (const capa of ["act-linea", "act-area", "act-punto"]) if (m.getLayer(capa)) m.setPaintProperty(capa, capa === "act-linea" ? "line-color" : capa === "act-area" ? "fill-color" : "circle-color", COLOR[u.servicio]);
    persona.current?.setLngLat([u.lon, u.lat]);
    for (const x of marcas.current) x.remove();
    marcas.current = [];
    // varios activos pueden tocar el mismo punto (una válvula y los tramos que llegan a ella): sus marcas se apilan hacia abajo para que se lean todas
    const puestas: { x: number; y: number }[] = [];
    const bajar = (lon: number, lat: number) => {
      const q = m.project([lon, lat]); let dy = 0;
      while (puestas.some((o) => Math.abs(o.x - q.x) < 90 && Math.abs(o.y - (q.y + dy)) < 22)) dy += 24;
      puestas.push({ x: q.x, y: q.y + dy }); return dy;
    };
    for (const a of u.activos) {
      const e = document.createElement("span"); e.className = `enc-marca${a.codigo === u.resaltado ? " enc-marca-sel" : ""}`; e.dataset.activo = a.codigo; e.setAttribute("aria-hidden", "true");
      const n = document.createElement("span"); n.className = "enc-marca-n"; n.textContent = String(a.n); n.style.background = COLOR[u.servicio];
      const c = document.createElement("span"); c.className = "enc-marca-cod"; c.textContent = a.codigo;
      e.append(n, c);
      marcas.current.push(new maplibregl.Marker({ element: e, anchor: "left", offset: [-11, bajar(a.lon, a.lat)] }).setLngLat([a.lon, a.lat]).addTo(m));
    }
    for (const p of u.puntos) {
      const e = document.createElement("span"); e.className = "enc-marca enc-marca-lev"; e.dataset.levantar = p.codigo; e.setAttribute("aria-hidden", "true");
      const n = document.createElement("span"); n.className = "enc-marca-n"; n.textContent = "?"; n.style.background = POR_LEVANTAR;
      const c = document.createElement("span"); c.className = "enc-marca-cod"; c.textContent = "Por levantar";
      e.append(n, c);
      marcas.current.push(new maplibregl.Marker({ element: e, anchor: "left", offset: [-11, bajar(p.lon, p.lat)] }).setLngLat([p.lon, p.lat]).addTo(m));
    }
  }

  useEffect(() => {
    if (!cont.current) return;
    const u = ultimo.current;
    const m = new maplibregl.Map({
      container: cont.current, center: [u.lon, u.lat], zoom: u.zoom - DESFASE, interactive: false, attributionControl: { compact: true }, maxZoom: 20 - DESFASE, minZoom: 18 - DESFASE,
      style: {
        version: 8,
        sources: { base: BASE, precision: { type: "geojson", data: fc([]) as never }, radio: { type: "geojson", data: fc([]) as never }, activos: { type: "geojson", data: fc([]) as never } },
        layers: [
          { id: "base", type: "raster", source: "base" },
          { id: "precision", type: "fill", source: "precision", paint: { "fill-color": PERSONA, "fill-opacity": 0.14 } },
          { id: "radio", type: "line", source: "radio", paint: { "line-color": "#0a2540", "line-width": 1.5, "line-dasharray": [3, 2] } },
          { id: "act-area", type: "fill", source: "activos", filter: ["==", ["get", "forma"], "area"], paint: { "fill-color": COLOR[u.servicio], "fill-opacity": 0.25 } },
          { id: "act-linea-sel", type: "line", source: "activos", filter: ["all", ["==", ["get", "forma"], "linea"], ["==", ["get", "sel"], true]], paint: { "line-color": "#D6336C", "line-width": 9, "line-opacity": 0.55 } },
          { id: "act-linea", type: "line", source: "activos", filter: ["==", ["get", "forma"], "linea"], paint: { "line-color": COLOR[u.servicio], "line-width": 4 } },
          { id: "act-punto", type: "circle", source: "activos", filter: ["==", ["get", "forma"], "punto"],
            paint: { "circle-radius": 6, "circle-color": COLOR[u.servicio], "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } },
        ],
      },
    });
    m.on("error", () => {});      // sin señal el mapa base puede fallar: los activos y el punto se siguen viendo
    const yo = document.createElement("span"); yo.className = "enc-persona"; yo.setAttribute("aria-hidden", "true");
    persona.current = new maplibregl.Marker({ element: yo }).setLngLat([u.lon, u.lat]).addTo(m);
    mapa.current = m;
    // «style.load» y no «load»: el estilo va en línea y queda listo sin esperar las teselas del mapa base (sin señal, «load» puede tardar o no llegar)
    m.once("style.load", () => { listo.current = true; pintar(); });
    (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome
    return () => { listo.current = false; for (const x of marcas.current) x.remove(); marcas.current = []; m.remove(); mapa.current = null; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { pintar(); }, [lat, lon, precision_m, radio_m, zoom, servicio, activos, puntos, resaltado]); // eslint-disable-line react-hooks/exhaustive-deps

  return <div ref={cont} className="enc-mapa-lienzo" data-testid="enc-mapa" data-zoom={zoom} role="img"
    aria-label={`Mapa centrado en su posición, con ${activos.length} activos cercanos numerados como en la lista${puntos.length ? ` y ${puntos.length} por levantar` : ""}`} />;
}
