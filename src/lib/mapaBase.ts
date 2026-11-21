// Mapa base del geoportal, compartido con el tablero (mapa de calor): centro de Valledupar y la fuente de calles (OpenStreetMap).
// El geoportal NO tiñe el mapa base: la capa "base" es el ráster de OSM sin ajustes de color.
export const CENTRO_VALLEDUPAR: [number, number] = [-73.2532, 10.4631];

export const FUENTE_BASE_CALLES = {
  type: "raster" as const,
  tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
  tileSize: 256,
  attribution: "© OpenStreetMap",
};

// PTAR-2 (Code C, 21-nov): la foto satelital (ESRI World Imagery, D8), la MISMA fuente y atribución que ya usa el mapa comercial (components/MapView.tsx).
export const FUENTE_BASE_SATELITAL = {
  type: "raster" as const,
  tiles: ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
  tileSize: 256,
  maxzoom: 19,
  attribution: "Esri, Maxar, Earthstar Geographics",
};
