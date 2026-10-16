// Mapa base del geoportal, compartido con el tablero (mapa de calor): centro de Valledupar y la fuente de calles (OpenStreetMap).
// El geoportal NO tiñe el mapa base: la capa "base" es el ráster de OSM sin ajustes de color.
export const CENTRO_VALLEDUPAR: [number, number] = [-73.2532, 10.4631];

export const FUENTE_BASE_CALLES = {
  type: "raster" as const,
  tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
  tileSize: 256,
  attribution: "© OpenStreetMap",
};
