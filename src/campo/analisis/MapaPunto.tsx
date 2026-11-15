import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import type { Predio } from "./tipos";

// Mapa pequeño del análisis de contrato: un marcador por predio (máximo 5) sobre el mapa base de OpenStreetMap del geoportal (lib/mapaBase.ts).
// MapLibre PROPIO, como MapaReportes: sin teselas comerciales ni consultas a Edge comerciales. Se carga bajo demanda (React.lazy) y solo cuando se abre la sección «Ubicación».
export default function MapaPunto({ predios }: { predios: Predio[] }) {
  const cont = useRef<HTMLDivElement>(null);
  const [fallo, setFallo] = useState<string | null>(null);
  const puntos = predios.filter((p): p is Predio & { lat: number; lon: number } => p.lat !== null && p.lon !== null && Number.isFinite(p.lat) && Number.isFinite(p.lon)).slice(0, 5);
  const clave = puntos.map((p) => `${p.lat},${p.lon}`).join("|");

  useEffect(() => {
    if (!cont.current || puntos.length === 0) return;
    let m: maplibregl.Map;
    try {
      m = new maplibregl.Map({
        container: cont.current, center: puntos[0] ? [puntos[0].lon, puntos[0].lat] : CENTRO_VALLEDUPAR, zoom: 16, attributionControl: { compact: true },
        style: { version: 8, sources: { osm: FUENTE_BASE_CALLES }, layers: [{ id: "fondo", type: "background", paint: { "background-color": "#eef2f5" } }, { id: "osm", type: "raster", source: "osm" }] },
      });
    } catch { setFallo("Este navegador no puede mostrar el mapa. Use «Abrir en Google Maps»."); return; }
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    const marcas = puntos.map((p) => new maplibregl.Marker({ color: "#1e5aa8" }).setLngLat([p.lon, p.lat]).addTo(m));
    if (puntos.length > 1) {
      const b = new maplibregl.LngLatBounds();
      puntos.forEach((p) => b.extend([p.lon, p.lat]));
      m.fitBounds(b, { padding: 40, maxZoom: 17, duration: 0 });
    }
    return () => { marcas.forEach((x) => x.remove()); m.remove(); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave]);

  if (fallo) return <p className="campo-error" role="alert">{fallo}</p>;
  return <div ref={cont} className="ac-mapa" role="application" aria-label={`Mapa con ${puntos.length === 1 ? "el predio" : `${puntos.length} predios`} del contrato`} data-testid="mapa-punto" />;
}
