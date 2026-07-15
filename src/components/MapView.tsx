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
export type FiltroEstado = "" | "DEMOLIDO" | "EN CONSTRUCCION" | "DESOCUPADO";
export type Conteo = { disponible: boolean; con: number; sin: number };
export type BaseMapa = "calles" | "satelital";
export type TerrenoInfo = { codigo: string | null; matricula: string | null };

type Props = {
  accessToken: string;
  inicial?: { lng: number; lat: number; zoom: number } | null;
  filtro: FiltroContrato;
  estado: FiltroEstado;
  mostrarTerrenos: boolean;
  base: BaseMapa;
  modoTerrenos: boolean;
  onSeleccionar: (id: number) => void;
  onSeleccionarVarios: (lista: PredioApilado[]) => void;
  onConteo: (c: Conteo) => void;
  onTerreno: (info: TerrenoInfo | null) => void;
};

export function MapView({
  accessToken,
  inicial,
  filtro,
  estado,
  mostrarTerrenos,
  base,
  modoTerrenos,
  onSeleccionar,
  onSeleccionarVarios,
  onConteo,
  onTerreno,
}: Props) {
  const contenedor = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const listo = useRef(false);
  const tokenRef = useRef(accessToken);
  const onSel = useRef(onSeleccionar);
  const onVarios = useRef(onSeleccionarVarios);
  const onCont = useRef(onConteo);
  const onTerr = useRef(onTerreno);
  const modoRef = useRef(modoTerrenos);

  useEffect(() => { tokenRef.current = accessToken; }, [accessToken]);
  useEffect(() => { onSel.current = onSeleccionar; }, [onSeleccionar]);
  useEffect(() => { onVarios.current = onSeleccionarVarios; }, [onSeleccionarVarios]);
  useEffect(() => { onCont.current = onConteo; }, [onConteo]);
  useEffect(() => { onTerr.current = onTerreno; }, [onTerreno]);
  useEffect(() => { modoRef.current = modoTerrenos; }, [modoTerrenos]);

  useEffect(() => {
    if (!contenedor.current || mapa.current) return;

    const map = new maplibregl.Map({
      container: contenedor.current,
      center: inicial ? [inicial.lng, inicial.lat] : CENTRO,
      zoom: inicial ? inicial.zoom : 13,
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
          satelital: {
            type: "raster",
            tiles: [
              "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
            ],
            tileSize: 256,
            attribution: "Esri, Maxar, Earthstar Geographics",
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
            id: "satelital",
            type: "raster",
            source: "satelital",
            layout: { visibility: "none" },
          },
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
            // Terreno seleccionado (resaltado). Vacío hasta que se clica uno.
            id: "terreno-sel",
            type: "fill",
            source: "predios",
            "source-layer": "terrenos",
            filter: ["==", ["get", "codigo"], "__NINGUNO__"],
            paint: { "fill-color": "#1e5aa8", "fill-opacity": 0.35 },
          },
          {
            id: "terreno-sel-linea",
            type: "line",
            source: "predios",
            "source-layer": "terrenos",
            filter: ["==", ["get", "codigo"], "__NINGUNO__"],
            paint: { "line-color": "#1e5aa8", "line-width": 2.5 },
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
              "circle-opacity": 1,
              "circle-stroke-opacity": 1,
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
              "circle-opacity": 1,
              "circle-stroke-opacity": 1,
            },
          },
          {
            id: "predios-estado",
            type: "circle",
            source: "predios",
            "source-layer": "predios",
            filter: ["==", ["get", "estado"], "__NINGUNO__"],
            paint: {
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 6, 18, 12],
              "circle-color": "#c026d3",
              "circle-stroke-width": 2,
              "circle-stroke-color": "#ffffff",
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
      aplicarEstado(map, estado);
      aplicarTerrenos(map, mostrarTerrenos);
      aplicarBase(map, base);
      aplicarModo(map, modoTerrenos);
      recontar(map);
    });

    map.on("moveend", () => recontar(map));
    map.on("idle", () => recontar(map));

    map.on("click", (e) => {
      // MODO TERRENOS: seleccionar el polígono clicado, mostrar su código.
      if (modoRef.current) {
        const feats = map.queryRenderedFeatures(e.point, { layers: ["terrenos-fill"] });
        const props = feats[0]?.properties;
        const cod = props?.codigo;
        const mat = props?.matricula;
        const codigo = cod != null ? String(cod) : null;
        const matricula = mat != null && String(mat).trim() !== "" ? String(mat) : null;
        map.setFilter("terreno-sel", ["==", ["get", "codigo"], codigo ?? "__NINGUNO__"]);
        map.setFilter("terreno-sel-linea", ["==", ["get", "codigo"], codigo ?? "__NINGUNO__"]);
        onTerr.current(codigo ? { codigo, matricula } : null);
        return;
      }

      // MODO NORMAL: predios (apilados)
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
      map.on("mouseenter", capa, () => {
        if (!modoRef.current) map.getCanvas().style.cursor = "pointer";
      });
      map.on("mouseleave", capa, () => {
        if (!modoRef.current) map.getCanvas().style.cursor = "";
      });
    }

    mapa.current = map;
    return () => { map.remove(); mapa.current = null; listo.current = false; };
  }, []);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) { aplicarFiltro(map, filtro); recontar(map); }
  }, [filtro]);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarEstado(map, estado);
  }, [estado]);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarTerrenos(map, mostrarTerrenos);
  }, [mostrarTerrenos]);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarBase(map, base);
  }, [base]);

  useEffect(() => {
    const map = mapa.current;
    if (map && listo.current) aplicarModo(map, modoTerrenos);
  }, [modoTerrenos]);

  useEffect(() => {
    const w = window as unknown as {
      __geoFly?: (x: number, y: number) => void;
      __geoVista?: () => { lng: number; lat: number; zoom: number } | null;
    };
    w.__geoFly = (x, y) => mapa.current?.flyTo({ center: [x, y], zoom: 19 });
    w.__geoVista = () => {
      const m = mapa.current;
      if (!m) return null;
      const c = m.getCenter();
      return { lng: c.lng, lat: c.lat, zoom: m.getZoom() };
    };
  }, []);

  function recontar(map: maplibregl.Map) {
    if (map.getZoom() < 15) {
      onCont.current({ disponible: false, con: 0, sin: 0 });
      return;
    }
    let feats: maplibregl.MapGeoJSONFeature[] = [];
    try {
      feats = map.queryRenderedFeatures({
        layers: ["predios-normal", "predios-clandestino"],
      });
    } catch {
      onCont.current({ disponible: false, con: 0, sin: 0 });
      return;
    }
    const con = new Set<number>();
    const sin = new Set<number>();
    for (const f of feats) {
      const id = Number(f.properties?.id);
      if (!Number.isInteger(id)) continue;
      if (f.properties?.clandestino === true) sin.add(id);
      else con.add(id);
    }
    onCont.current({ disponible: true, con: con.size, sin: sin.size });
  }

  return <div ref={contenedor} className="mapa" />;
}

function aplicarFiltro(map: maplibregl.Map, filtro: FiltroContrato) {
  const verNormal = filtro === "todos" || filtro === "con";
  const verSin = filtro === "todos" || filtro === "sin";
  map.setLayoutProperty("predios-normal", "visibility", verNormal ? "visible" : "none");
  map.setLayoutProperty("predios-labels", "visibility", verNormal ? "visible" : "none");
  map.setLayoutProperty("predios-clandestino", "visibility", verSin ? "visible" : "none");
}

function aplicarEstado(map: maplibregl.Map, estado: FiltroEstado) {
  if (!estado) {
    map.setFilter("predios-estado", ["==", ["get", "estado"], "__NINGUNO__"]);
    map.setPaintProperty("predios-normal", "circle-opacity", 1);
    map.setPaintProperty("predios-normal", "circle-stroke-opacity", 1);
    map.setPaintProperty("predios-clandestino", "circle-opacity", 1);
    map.setPaintProperty("predios-clandestino", "circle-stroke-opacity", 1);
    return;
  }
  map.setFilter("predios-estado", ["==", ["get", "estado"], estado]);
  map.setPaintProperty("predios-normal", "circle-opacity", 0.25);
  map.setPaintProperty("predios-normal", "circle-stroke-opacity", 0.25);
  map.setPaintProperty("predios-clandestino", "circle-opacity", 0.25);
  map.setPaintProperty("predios-clandestino", "circle-stroke-opacity", 0.25);
}

function aplicarTerrenos(map: maplibregl.Map, mostrar: boolean) {
  const v = mostrar ? "visible" : "none";
  map.setLayoutProperty("terrenos-fill", "visibility", v);
  map.setLayoutProperty("terrenos-linea", "visibility", v);
}

function aplicarBase(map: maplibregl.Map, base: BaseMapa) {
  map.setLayoutProperty("base", "visibility", base === "calles" ? "visible" : "none");
  map.setLayoutProperty("satelital", "visibility", base === "satelital" ? "visible" : "none");
}

function aplicarModo(map: maplibregl.Map, modo: boolean) {
  // En modo terrenos: atenuar puntos y cambiar cursor.
  const op = modo ? 0.35 : 1;
  map.setPaintProperty("predios-normal", "circle-opacity", op);
  map.setPaintProperty("predios-clandestino", "circle-opacity", op);
  map.getCanvas().style.cursor = modo ? "crosshair" : "";
  if (!modo) {
    // Al salir del modo, limpiar la selección de terreno.
    map.setFilter("terreno-sel", ["==", ["get", "codigo"], "__NINGUNO__"]);
    map.setFilter("terreno-sel-linea", ["==", ["get", "codigo"], "__NINGUNO__"]);
  }
}
