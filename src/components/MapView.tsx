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

// Filtro comercial: expresión MapLibre ya construida (o null = sin filtro).
// Modo activo: define qué filtros mandan sobre el mapa.
export type ModoMapa = "explorar" | "focalizacion" | "comercial" | "rutas";
export type ConteoComercial = { disponible: boolean; total: number };
export type PuntoRutaMap = { orden: number; x: number; y: number; m: number; contrato: string };
export type FiltroCatastroRuta = "con" | "sin" | "ninguno";
export type StatsComercial = {
  disponible: boolean;
  total: number;
  conDeuda: number;
  sinMedidor: number;
  consumoAlto: number;
  medicion: Record<string, number>;
  facturacion: Record<string, number>;
  consumo: Record<string, number>;
  mora: Record<string, number>;
  ciclo: Record<string, number>;
  barrio: Record<string, number>;
};

export type HeatMetrica =
  | "deuda"
  | "facturas"
  | "consumo_bajo"
  | "sin_medidor";

type Props = {
  accessToken: string;
  inicial?: { lng: number; lat: number; zoom: number } | null;
  filtro: FiltroContrato;
  estado: FiltroEstado;
  mostrarTerrenos: boolean;
  base: BaseMapa;
  modoTerrenos: boolean;
  modoActivo: ModoMapa;
  filtroComercial: unknown[] | null;
  heatMetrica: HeatMetrica | null;
  puntosRuta: PuntoRutaMap[] | null;
  filtroCatastroRuta: FiltroCatastroRuta;
  onSeleccionar: (id: number) => void;
  onSeleccionarVarios: (lista: PredioApilado[]) => void;
  onConteo: (c: Conteo) => void;
  onConteoComercial: (c: ConteoComercial) => void;
  onStatsComercial: (s: StatsComercial) => void;
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
  modoActivo,
  filtroComercial,
  heatMetrica,
  puntosRuta,
  filtroCatastroRuta,
  onSeleccionar,
  onSeleccionarVarios,
  onConteo,
  onConteoComercial,
  onStatsComercial,
  onTerreno,
}: Props) {
  const contenedor = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const listo = useRef(false);
  const heatRef = useRef<string | null>(heatMetrica);
  const tokenRef = useRef(accessToken);
  const onSel = useRef(onSeleccionar);
  const onVarios = useRef(onSeleccionarVarios);
  const onCont = useRef(onConteo);
  const onContCom = useRef(onConteoComercial);
  const onStatsCom = useRef(onStatsComercial);
  const modoRef2 = useRef(modoActivo);
  const puntosRutaRef = useRef(puntosRuta);
  const filtroCatRutaRef = useRef(filtroCatastroRuta);
  const onTerr = useRef(onTerreno);
  const modoRef = useRef(modoTerrenos);

  useEffect(() => { tokenRef.current = accessToken; }, [accessToken]);
  useEffect(() => { onSel.current = onSeleccionar; }, [onSeleccionar]);
  useEffect(() => { onVarios.current = onSeleccionarVarios; }, [onSeleccionarVarios]);
  useEffect(() => { onCont.current = onConteo; }, [onConteo]);
  useEffect(() => { onContCom.current = onConteoComercial; }, [onConteoComercial]);
  useEffect(() => { onStatsCom.current = onStatsComercial; }, [onStatsComercial]);
  useEffect(() => { modoRef2.current = modoActivo; }, [modoActivo]);
  useEffect(() => {
    puntosRutaRef.current = puntosRuta;
    const map = mapa.current;
    if (map && listo.current) pintarRuta(map, puntosRuta);
  }, [puntosRuta]);
  useEffect(() => {
    filtroCatRutaRef.current = filtroCatastroRuta;
    const map = mapa.current;
    if (map && listo.current && modoRef2.current === "rutas") {
      aplicarPorModo(map, "rutas", null, filtroCatRutaRef.current);
    }
  }, [filtroCatastroRuta]);
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
            id: "heatmap-comercial",
            type: "heatmap",
            source: "predios",
            "source-layer": "predios",
            layout: { visibility: "none" },
            paint: {
              "heatmap-weight": 0,
              "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 12, 1, 18, 3],
              "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 12, 15, 18, 40],
              "heatmap-opacity": 0.75,
              "heatmap-color": [
                "interpolate", ["linear"], ["heatmap-density"],
                0, "rgba(0,0,255,0)",
                0.2, "rgba(0,150,255,0.5)",
                0.4, "rgba(0,255,150,0.7)",
                0.6, "rgba(255,255,0,0.8)",
                0.8, "rgba(255,150,0,0.9)",
                1, "rgba(255,0,0,1)"
              ],
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

    // Botón "Mi ubicación": toggle con seguimiento. Útil en terreno desde el celular.
    // Primer toque: ubica y sigue tu movimiento. Segundo toque: suelta.
    map.addControl(
      new maplibregl.GeolocateControl({
        positionOptions: { enableHighAccuracy: true },
        trackUserLocation: true,
        showUserLocation: true,
        showAccuracyCircle: true,
      }),
      "bottom-right",
    );

    map.on("load", () => {
      listo.current = true;
      aplicarFiltro(map, filtro);
      aplicarPorModo(map, modoActivo, filtroComercial, filtroCatRutaRef.current, heatRef.current);
      aplicarEstado(map, estado);
      aplicarTerrenos(map, mostrarTerrenos);
      aplicarBase(map, base);
      aplicarModo(map, modoTerrenos);
      recontar(map);

      // Fuentes y capas del modo Rutas (vacías hasta que se elija una ruta).
      map.addSource("ruta-linea", { type: "geojson", data: geojsonVacio() as never });
      map.addSource("ruta-puntos", { type: "geojson", data: geojsonVacio() as never });
      // Línea del recorrido: azul los tramos normales, rojo grueso los > 100 m.
      map.addLayer({
        id: "ruta-linea-normal", type: "line", source: "ruta-linea",
        filter: ["<=", ["get", "m"], 100],
        paint: { "line-color": "#1e5aa8", "line-width": 2, "line-opacity": 0.85 },
      });
      map.addLayer({
        id: "ruta-linea-larga", type: "line", source: "ruta-linea",
        filter: [">", ["get", "m"], 100],
        paint: { "line-color": "#e5484d", "line-width": 3.5, "line-opacity": 0.9 },
      });
      // Puntos de la ruta: verde el inicio, amarillo el fin, azul el resto.
      map.addLayer({
        id: "ruta-puntos-capa", type: "circle", source: "ruta-puntos",
        paint: {
          "circle-radius": [
            "match", ["get", "hito"],
            "inicio", 7, "fin", 7,
            4,
          ],
          "circle-color": [
            "match", ["get", "hito"],
            "inicio", "#2e7d32",
            "fin", "#f5b301",
            "#1e5aa8",
          ],
          "circle-stroke-color": "#fff",
          "circle-stroke-width": [
            "match", ["get", "hito"],
            "inicio", 2, "fin", 2,
            1,
          ],
        },
      });
      // Números de orden del recorrido (1, 2, 3...). Colisión activada:
      // alejado se ven algunos, al acercarte aparecen todos.
      map.addLayer({
        id: "ruta-puntos-orden", type: "symbol", source: "ruta-puntos",
        layout: {
          "text-field": ["to-string", ["get", "orden"]],
          "text-font": ["Open Sans Semibold"],
          "text-size": 10,
          "text-offset": [0, -0.9],
          "text-allow-overlap": false,
        },
        paint: {
          "text-color": "#12263a",
          "text-halo-color": "#ffffff",
          "text-halo-width": 1.5,
        },
      });
      // Aplicar la ruta si ya venía una
      pintarRuta(map, puntosRutaRef.current);
    });

    map.on("moveend", () => recontar(map));
    map.on("idle", () => recontar(map));
    map.on("moveend", () => recontarComercial(map));
    map.on("idle", () => recontarComercial(map));

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
    if (map && listo.current) {
      aplicarPorModo(map, modoActivo, filtroComercial, filtroCatRutaRef.current, heatRef.current);
      // (así la visibilidad de los sin-contrato queda coherente).
      if (modoActivo !== "comercial") aplicarFiltro(map, filtro);
      recontarComercial(map);
    }
  }, [modoActivo, filtroComercial]);

  useEffect(() => {
    heatRef.current = heatMetrica;
    const map = mapa.current;
    if (map && listo.current) {
      aplicarPorModo(map, modoActivo, filtroComercial, filtroCatRutaRef.current, heatMetrica);
    }
  }, [heatMetrica]);

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

  // Cuenta los predios que cumplen el filtro comercial en pantalla,
  // y agrupa por cada categoría para el panel de indicadores.
  function recontarComercial(map: maplibregl.Map) {
    if (modoRef2.current !== "comercial") return;
    const vacio = {
      disponible: false, total: 0, conDeuda: 0, sinMedidor: 0, consumoAlto: 0,
      medicion: {}, facturacion: {}, consumo: {}, mora: {}, ciclo: {}, barrio: {},
    };
    if (map.getZoom() < 15) {
      onContCom.current({ disponible: false, total: 0 });
      onStatsCom.current(vacio);
      return;
    }
    let feats: maplibregl.MapGeoJSONFeature[] = [];
    try {
      feats = map.queryRenderedFeatures({ layers: ["predios-normal"] });
    } catch {
      onContCom.current({ disponible: false, total: 0 });
      onStatsCom.current(vacio);
      return;
    }
    const vistos = new Set<number>();
    const medicion: Record<string, number> = {};
    const facturacion: Record<string, number> = {};
    const consumo: Record<string, number> = {};
    const mora: Record<string, number> = {};
    const ciclo: Record<string, number> = {};
    const barrio: Record<string, number> = {};
    let conDeuda = 0, sinMedidor = 0, consumoAlto = 0;
    const inc = (o: Record<string, number>, k: unknown) => {
      if (k === undefined || k === null || k === "") return;
      const s = String(k);
      o[s] = (o[s] ?? 0) + 1;
    };
    for (const f of feats) {
      const id = Number(f.properties?.id);
      if (!Number.isInteger(id) || vistos.has(id)) continue;
      vistos.add(id);
      const p = f.properties ?? {};
      inc(medicion, p.estado_medidor);
      inc(facturacion, p.determinacion_consumo);
      inc(consumo, p.clase_consumo);
      inc(mora, p.tramo_mora);
      inc(ciclo, p.ciclo);
      inc(barrio, p.barrio);
      if (p.tiene_deuda === true || p.tiene_deuda === "true") conDeuda++;
      if (String(p.estado_medidor) === "3") sinMedidor++;
      if (p.clase_consumo === "elevado" || p.clase_consumo === "grandes") consumoAlto++;
    }
    const total = vistos.size;
    onContCom.current({ disponible: true, total });
    onStatsCom.current({
      disponible: true, total, conDeuda, sinMedidor, consumoAlto,
      medicion, facturacion, consumo, mora, ciclo, barrio,
    });
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

// Filtros base de cada capa (según si es clandestino o no).
const BASE_NORMAL = ["!=", ["get", "clandestino"], true];
const BASE_CLAND = ["==", ["get", "clandestino"], true];

// Aplica el estado del mapa según el MODO activo.
// - comercial: filtro comercial combinado sobre predios con contrato; oculta clandestinos.
// - otros modos: restaura el filtro base normal.
function pesoHeat(metrica: string): unknown {
  if (metrica === "deuda") {
    return ["interpolate", ["linear"], ["to-number", ["get", "deuda_total"], 0], 0, 0, 2000000, 1];
  }
  if (metrica === "facturas") {
    return ["interpolate", ["linear"], ["to-number", ["get", "facturas_pendientes"], 0], 0, 0, 60, 1];
  }
  if (metrica === "consumo_bajo") {
    return ["case",
      ["any", ["==", ["get", "clase_consumo"], "cero"], ["==", ["get", "clase_consumo"], "muy_bajo"]],
      1, 0];
  }
  return ["case", ["==", ["get", "estado_medidor"], "3"], 1, 0];
}

function aplicarHeat(
  map: maplibregl.Map,
  metrica: string | null,
  filtroComercial: unknown[] | null,
) {
  if (!map.getLayer("heatmap-comercial")) return;
  if (!metrica) {
    map.setLayoutProperty("heatmap-comercial", "visibility", "none");
    return;
  }
  const filtroBase: unknown[] = ["!=", ["get", "clandestino"], true];
  const filtro = filtroComercial && filtroComercial.length > 0
    ? ["all", filtroBase, ...filtroComercial]
    : filtroBase;
  map.setFilter("heatmap-comercial", filtro as never);
  map.setPaintProperty("heatmap-comercial", "heatmap-weight", pesoHeat(metrica) as never);
  map.setLayoutProperty("heatmap-comercial", "visibility", "visible");
}

function aplicarPorModo(
  map: maplibregl.Map,
  modo: string,
  filtroComercial: unknown[] | null,
  filtroCatRuta: FiltroCatastroRuta = "ninguno",
  heatMetrica: string | null = null,
) {
  if (modo === "comercial") {
    // Los sin-contrato no tienen datos comerciales: se ocultan.
    map.setLayoutProperty("predios-clandestino", "visibility", "none");
    map.setLayoutProperty("predios-labels", "visibility", "none");
    // Si el mapa de calor está activo, ocultamos los puntos (se ve solo el calor).
    map.setLayoutProperty("predios-normal", "visibility", heatMetrica ? "none" : "visible");
    aplicarHeat(map, heatMetrica, filtroComercial);
    // Combinar filtro base con el comercial (lógica Y).
    if (filtroComercial && filtroComercial.length > 0) {
      map.setFilter("predios-normal", ["all", BASE_NORMAL, ...filtroComercial] as never);
    } else {
      map.setFilter("predios-normal", BASE_NORMAL as never);
    }
    // (heat solo aplica en comercial)
  } else if (modo === "rutas") {
    aplicarHeat(map, null, null);
    // En modo Rutas, los puntos del catastro se controlan con el filtro:
    // "con" = solo con contrato, "sin" = solo sin contrato, "ninguno" = ocultar todos.
    // El recorrido de la ruta (línea + puntos) siempre se ve.
    const fcr = filtroCatRuta;
    map.setLayoutProperty("predios-labels", "visibility", "none");
    map.setLayoutProperty("predios-normal", "visibility", fcr === "con" ? "visible" : "none");
    map.setLayoutProperty("predios-clandestino", "visibility", fcr === "sin" ? "visible" : "none");
    map.setFilter("predios-normal", BASE_NORMAL as never);
    map.setFilter("predios-clandestino", BASE_CLAND as never);
    // Atenuar los puntos de catastro que sí se muestran, para que no compitan con la ruta.
    map.setPaintProperty("predios-normal", "circle-opacity", 0.3);
    map.setPaintProperty("predios-clandestino", "circle-opacity", 0.3);
  } else {
    aplicarHeat(map, null, null);
    // Restaurar filtro base y visibilidad (los sin-contrato vuelven a verse).
    map.setFilter("predios-normal", BASE_NORMAL as never);
    map.setFilter("predios-clandestino", BASE_CLAND as never);
    map.setLayoutProperty("predios-normal", "visibility", "visible");
    map.setLayoutProperty("predios-clandestino", "visibility", "visible");
    // Restaurar opacidad normal (por si venía del modo rutas).
    map.setPaintProperty("predios-normal", "circle-opacity", 1);
    map.setPaintProperty("predios-clandestino", "circle-opacity", 1);
  }
}


// GeoJSON vacío inicial para las fuentes de ruta.
function geojsonVacio() {
  return { type: "FeatureCollection", features: [] };
}

// Pinta (o limpia) el recorrido de una ruta en el mapa.
// Construye segmentos de línea (cada uno con su distancia 'm') y puntos.
function pintarRuta(
  map: maplibregl.Map,
  puntos: { orden: number; x: number; y: number; m: number; contrato: string }[] | null,
) {
  const srcLinea = map.getSource("ruta-linea") as maplibregl.GeoJSONSource | undefined;
  const srcPuntos = map.getSource("ruta-puntos") as maplibregl.GeoJSONSource | undefined;
  if (!srcLinea || !srcPuntos) return;

  if (!puntos || puntos.length === 0) {
    srcLinea.setData(geojsonVacio() as never);
    srcPuntos.setData(geojsonVacio() as never);
    return;
  }

  // Ordenar por 'orden' por si acaso
  const orden = [...puntos].sort((a, b) => a.orden - b.orden);

  // Segmentos: cada par consecutivo es una línea con la distancia del segundo punto.
  const segmentos: unknown[] = [];
  for (let i = 1; i < orden.length; i++) {
    const a = orden[i - 1];
    const b = orden[i];
    segmentos.push({
      type: "Feature",
      properties: { m: b.m },
      geometry: { type: "LineString", coordinates: [[a.x, a.y], [b.x, b.y]] },
    });
  }
  srcLinea.setData({ type: "FeatureCollection", features: segmentos } as never);

  const pts: unknown[] = orden.map((p, i) => ({
    type: "Feature",
    properties: {
      orden: p.orden,
      contrato: p.contrato,
      m: p.m,
      hito: i === 0 ? "inicio" : i === orden.length - 1 ? "fin" : "normal",
    },
    geometry: { type: "Point", coordinates: [p.x, p.y] },
  }));
  srcPuntos.setData({ type: "FeatureCollection", features: pts } as never);

  // Encuadrar el mapa a la ruta
  const xs = orden.map((p) => p.x);
  const ys = orden.map((p) => p.y);
  const bounds: [[number, number], [number, number]] = [
    [Math.min(...xs), Math.min(...ys)],
    [Math.max(...xs), Math.max(...ys)],
  ];
  map.fitBounds(bounds, { padding: 60, maxZoom: 17, duration: 600 });
}
