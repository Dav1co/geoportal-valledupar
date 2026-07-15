import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUNCTIONS_URL } from "../lib/supabase";

// Valledupar
const CENTRO: [number, number] = [-73.2532, 10.4631];

export type PredioApilado = {
  id: number;
  cod_usuario: string | null;
  clandestino: boolean;
  direccion?: string | null;
};

export type FiltroContrato = "todos" | "con" | "sin";

type Props = {
  accessToken: string;
  filtro: FiltroContrato;
  mostrarTerrenos: boolean;
  onSeleccionar: (id: number) => void;
  onSeleccionarVarios: (lista: PredioApilado[]) => void;
};

export function MapView({
  accessToken,
  filtro,
  mostrarTerrenos,
  onSeleccionar,
  onSeleccionarVarios,
}: Props) {
  const contenedor = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const listo = useRef(false);
  const tokenRef = useRef(accessToken);
  const onSel = useRef(onSeleccionar);
  const onVarios = useRef(onSeleccionarVarios);

  useEffect(() => { tokenRef.current = accessToken; }, [accessToken]);
  useEffect(() => { onSel.current = onSeleccionar; }, [onSeleccionar]);
  useEffect(() => { onVarios.current = onSeleccionarVarios; }, [onSeleccionarVarios]);

  useEffect(() => {
    if (!contenedor.current || mapa.current) return;

    const map = new maplibregl.Map({
      container: contenedor.current,
      center: CENTRO,
      zoom: 13,
      attributionControl: { compact: true },
      transformRequest: (url) => {
        if (url.includes("/geoportal-tiles/")) {
          return { url, headers: { Authorization: `Bearer ${tokenRef.current}` } };
        }
        return { url };
      },
      style: {
        version: 8,
        glyphs: "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
        sources: {
          base: {
            type: "raster",
            tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
            tileSize: 256,
            attribution: "© OpenStreetMap",
          },
          predios: {
            type: "vector",
            tiles: [`${FUNCTIONS_URL}/geoportal-tiles/{z}/{x}/{y}`],
            minzoom: 15,
            maxzoom: 22,
          },
        },
        layers: [
          { id: "base", type: "raster", source: "base" },
          {
            id: "terrenos-fill",
            type: "fill",
            source: "predios",
            "source-layer": "terrenos",
            paint: { "fill-color": "#8fa3b0", "fill-opacity": 0.12 },
          },
          {
            id: "terrenos-linea",
            type: "line",
            source: "predios",
            "source-layer": "terrenos",
            paint: {
              "line-color": "#7d8f9b",
              "line-width": ["interpolate", ["linear"], ["zoom"], 15, 0.5, 18, 1.2],
              "line-opacity": 0.7,
            },
          },
          {
            id: "predios-normal",
            type: "circle",
            source: "predios",
            "source-layer": "predios",
            filter: ["!=", ["get", "clandestino"], true],
            paint: {
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 3, 18, 7],
              "circle-color": "#2FB6C4",
              "circle-stroke-width": 1,
              "circle-stroke-color": "#0F1B24",
            },
          },
          {
            id: "predios-clandestino",
            type: "circle",
            source: "predios",
            "source-layer": "predios",
            filter: ["==", ["get", "clandestino"], true],
            paint: {
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 4, 18, 8],
              "circle-color": "#E5484D",
              "circle-stroke-width": 1.5,
              "circle-stroke-color": "#2A0E0F",
            },
          },
          {
            id: "predios-labels",
            type: "symbol",
            source: "predios",
            "source-layer": "predios",
            minzoom: 16,
            filter: ["!=", ["get", "clandestino"], true],
            layout: {
              "text-field": ["to-string", ["get", "cod_usuario"]],
              "text-font": ["Open Sans Semibold"],
              "text-size": 11,
              "text-anchor": "top",
              "text-offset": [0, 0.8],
              "text-allow-overlap": false,
            },
            paint: {
              "text-color": "#1e5aa8",
              "text-halo-color": "#ffffff",
              "text-halo-width": 1.5,
            },
          },
        ],
      },
    });

    map.addControl(new maplibregl.NavigationControl(), "top-right");

    map.on("load", () => {
      listo.current = true;
      aplicarFiltro(map, filtro);
      aplicarTerrenos(map, mostrarTerrenos);
    });

    map.on("click", (e) => {
      const margen = 5;
      const bbox: [maplibregl.PointLike, maplibregl.PointLike] = [
        [e.point.x - margen, e.point.y - margen],
        [e.point.x + margen, e.point.y + margen],
      ];
      const capas = ["predios-normal", "predios-clandestino"].filter(
        (id) => map.getLayoutProperty(id, "visibility") !== "none",
      );
      if (capas.length === 0) return;
      const feats = map.queryRenderedFeatures(bbox, { layers: capas });

      const vistos = new Set<number>();
      const lista: PredioApilado[] = [];
      for (const f of feats) {
        const id = Number(f.properties?.id);
        if (!Number.isInteger(id) || vistos.has(id)) continue;
        vistos.add(id);
        lista.push({
          id,
          cod_usuario: (f.properties?.cod_usuario as string | undefined) ?? null,
          clandestino: f.properties?.clandestino === true,
        });
      }

      if (lista.length === 0) return;
      if (lista.length === 1) { onSel.current(lista[0].id); return; }
      lista.sort((a, b) => {
        const na = Number(a.cod_usuario), nb = Number(b.cod_usuario);
        if (Number.isFinite(na) && Number.isFinite(nb)) return na - nb;
        return String(a.cod_usuario).localeCompare(String(b.cod_usuario));
      });
      onVarios.current(lista);
    });

    for (const capa of ["predios-normal", "predios-clandestino"]) {
      map.on("mouseenter", capa, () => (map.getCanvas().style.cursor = "pointer"));
      map.on("mouseleave", capa, () => (map.getCanvas().style.cursor = ""));
    }

    mapa.current = map;
    return () => { map.remove(); mapa.current = null; listo.current = false; };
  }, []);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarFiltro(map, filtro);
  }, [filtro]);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarTerrenos(map, mostrarTerrenos);
  }, [mostrarTerrenos]);

  useEffect(() => {
    (window as unknown as { __geoFly?: (x: number, y: number) => void }).__geoFly =
      (x, y) => mapa.current?.flyTo({ center: [x, y], zoom: 19 });
  }, []);

  return <div ref={contenedor} className="mapa" />;
}

function aplicarFiltro(map: maplibregl.Map, filtro: FiltroContrato) {
  const verNormal = filtro === "todos" || filtro === "con";
  const verSin = filtro === "todos" || filtro === "sin";
  map.setLayoutProperty("predios-normal", "visibility", verNormal ? "visible" : "none");
  map.setLayoutProperty("predios-labels", "visibility", verNormal ? "visible" : "none");
  map.setLayoutProperty("predios-clandestino", "visibility", verSin ? "visible" : "none");
}

function aplicarTerrenos(map: maplibregl.Map, mostrar: boolean) {
  const v = mostrar ? "visible" : "none";
  map.setLayoutProperty("terrenos-fill", "visibility", v);
  map.setLayoutProperty("terrenos-linea", "visibility", v);
}
