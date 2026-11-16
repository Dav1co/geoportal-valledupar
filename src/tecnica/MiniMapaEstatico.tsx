import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";

// Minimapa ESTÁTICO de la ficha (Corte 3b, §22): el activo resaltado con su red alrededor (una sola red, la misma tesela liviana del minimapa del
// Corte 2), sin interacción. «Abrir en el geovisor» llega con el geovisor (Corte 6); por ahora un toque lo acerca o lo aleja.

const COLOR: Record<string, string> = { acueducto: "#1F5FA8", alcantarillado: "#8A5A2B" };
const SEL = "#D6336C";

export function MiniMapaEstatico({ sistema, codigo, lat, lon }: { sistema: "acueducto" | "alcantarillado"; codigo: string; lat: number; lon: number }) {
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const [cerca, setCerca] = useState(true);
  useEffect(() => {
    let vivo = true; let m: maplibregl.Map | null = null; let token: string | null = null;
    void supabase.auth.getSession().then(({ data }) => {
      if (!vivo || !cont.current) return;
      token = data.session?.access_token ?? null;
      m = new maplibregl.Map({
        container: cont.current, center: [lon, lat], zoom: 17.5, interactive: false, attributionControl: { compact: true },
        transformRequest: (url) => (url.includes("accion=tesela") && token ? { url, headers: { Authorization: `Bearer ${token}` } } : { url }),
        style: {
          version: 8,
          sources: { base: FUENTE_BASE_CALLES, red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=tesela&sistema=${sistema}&z={z}&x={x}&y={y}&v=1`], minzoom: 15, maxzoom: 18 } },
          layers: [
            { id: "base", type: "raster", source: "base" },
            { id: "tramos", type: "line", source: "red", "source-layer": "red", filter: ["==", ["get", "forma"], "tramo"],
              paint: { "line-color": COLOR[sistema], "line-width": 3, "line-opacity": 0.8 } },
            { id: "sel-tramo", type: "line", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "tramo"], ["==", ["get", "codigo"], codigo]],
              paint: { "line-color": SEL, "line-width": 8 } },
            { id: "nodos", type: "circle", source: "red", "source-layer": "red", filter: ["==", ["get", "forma"], "nodo"],
              paint: { "circle-radius": ["match", ["get", "prefijo"], "ACC", 2.5, 4.5], "circle-color": "#1B1F1D", "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 1 } },
            { id: "sel-nodo", type: "circle", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "nodo"], ["==", ["get", "codigo"], codigo]],
              paint: { "circle-radius": 10, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": SEL, "circle-stroke-width": 4 } },
          ],
        },
      });
      // sin señal, la base de calles o una tesela pueden fallar: el minimapa es de referencia y se queda con lo que cargó (sin errores en la consola)
      m.on("error", () => {});
      mapa.current = m;
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;     // para las pruebas en Chrome
    });
    return () => { vivo = false; m?.remove(); mapa.current = null; };
  }, [sistema, codigo, lat, lon]);
  const alternar = () => { const n = !cerca; setCerca(n); mapa.current?.jumpTo({ center: [lon, lat], zoom: n ? 17.5 : 16 }); };
  return (
    <button type="button" className="red-minimapa" onClick={alternar} aria-label={`Ubicación de ${codigo} en la red de ${sistema}. Toque para ${cerca ? "alejar" : "acercar"}.`}>
      <div ref={cont} className="red-minimapa-mapa" aria-hidden="true" />
      <span className="red-minimapa-nota">{cerca ? "Toque para ver más red" : "Toque para acercar"}</span>
    </button>
  );
}
