import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";

// Minimapa de la simulación de cierre (Corte 9b): la red de acueducto, el activo que se quiere aislar resaltado y las válvulas por cerrar numeradas en el
// mismo orden de la lista. Sin interacción (es de referencia); usa la tesela liviana del minimapa del Corte 2. Los números son marcas de HTML (sin fuentes).
const ACUEDUCTO = "#1F5FA8", SEL = "#D6336C";

export function MiniMapaCierre({ activo, lat, lon, valvulas }: { activo: string; lat: number; lon: number; valvulas: { codigo: string; lat?: number; lon?: number }[] }) {
  const cont = useRef<HTMLDivElement>(null);
  const clave = valvulas.map((v) => v.codigo).join(",");
  useEffect(() => {
    let vivo = true; let m: maplibregl.Map | null = null; let token: string | null = null;
    void supabase.auth.getSession().then(({ data }) => {
      if (!vivo || !cont.current) return;
      token = data.session?.access_token ?? null;
      const puntos = valvulas.filter((v) => typeof v.lat === "number" && typeof v.lon === "number") as { codigo: string; lat: number; lon: number }[];
      m = new maplibregl.Map({
        container: cont.current, center: [lon, lat], zoom: 16.5, interactive: false, attributionControl: { compact: true },
        transformRequest: (url) => (url.includes("accion=tesela") && token ? { url, headers: { Authorization: `Bearer ${token}` } } : { url }),
        style: {
          version: 8,
          sources: { base: FUENTE_BASE_CALLES, red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=tesela&sistema=acueducto&z={z}&x={x}&y={y}&v=1`], minzoom: 15, maxzoom: 18 } },
          layers: [
            { id: "base", type: "raster", source: "base" },
            { id: "tramos", type: "line", source: "red", "source-layer": "red", filter: ["==", ["get", "forma"], "tramo"], paint: { "line-color": ACUEDUCTO, "line-width": 2.5, "line-opacity": 0.75 } },
            { id: "sel-tramo", type: "line", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "tramo"], ["==", ["get", "codigo"], activo]], paint: { "line-color": SEL, "line-width": 7 } },
            { id: "sel-nodo", type: "circle", source: "red", "source-layer": "red", filter: ["all", ["==", ["get", "forma"], "nodo"], ["==", ["get", "codigo"], activo]],
              paint: { "circle-radius": 10, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": SEL, "circle-stroke-width": 4 } },
          ],
        },
      });
      m.on("error", () => {});      // sin señal, la base de calles o una tesela pueden fallar: el minimapa es de referencia
      puntos.forEach((v, i) => {
        const e = document.createElement("span"); e.className = "cie-mapa-num"; e.textContent = String(valvulas.findIndex((x) => x.codigo === v.codigo) + 1); e.dataset.valvula = v.codigo; e.setAttribute("aria-hidden", "true");
        new maplibregl.Marker({ element: e }).setLngLat([v.lon, v.lat]).addTo(m!);
        void i;
      });
      if (puntos.length) {
        const b = new maplibregl.LngLatBounds([lon, lat], [lon, lat]); for (const v of puntos) b.extend([v.lon, v.lat]);
        m.fitBounds(b, { padding: 36, maxZoom: 17.5, minZoom: 15, duration: 0 } as maplibregl.FitBoundsOptions);
        if (m.getZoom() < 15) m.setZoom(15);      // por debajo de 15 la tesela liviana no trae la red
      }
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome
    });
    return () => { vivo = false; m?.remove(); };
  }, [activo, lat, lon, clave]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <figure className="cie-mapa" data-testid="cie-mapa">
      <div ref={cont} className="cie-mapa-lienzo" role="img" aria-label={`Mapa de ${activo} con las ${valvulas.length} válvulas por cerrar, numeradas como en la lista`} />
      <figcaption>El activo va resaltado; los números son las válvulas de la lista.</figcaption>
    </figure>
  );
}
