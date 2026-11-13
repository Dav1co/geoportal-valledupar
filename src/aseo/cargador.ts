// Lectura de capas de rutas para el cargador del administrador (PURA: sin React ni red). Acepta GeoJSON y KML. El shapefile se recibe ya convertido (ver MENSAJE_SHAPEFILE).
// El administrador ELIGE después qué columna es el código de ruta: aquí no se supone ningún nombre de columna. TODOS los atributos originales se conservan tal cual.
// Los números de los atributos (p. ej. un código de 13 dígitos escrito como número JSON) viajan como números; el servidor los vuelve texto sin perder precisión. Se avisa si alguno supera los 15 dígitos
// (JavaScript solo representa con exactitud enteros hasta 9.007.199.254.740.991) y en ese caso conviene que el archivo traiga el código como TEXTO.

export type Atributos = Record<string, unknown>;
export type FilaCapa = { atributos: Atributos; geometry: { type: string; coordinates: unknown } | { type: "GeometryCollection"; geometries: unknown[] } };
export type CapaLeida = { origen: "geojson" | "kml"; srid: number; filas: FilaCapa[]; columnas: string[]; advertencias: string[] };

export const MENSAJE_SHAPEFILE =
  "Los shapefile (.shp, .zip) no se leen directamente. Conviértalo antes a GeoJSON (en QGIS: clic derecho en la capa › Exportar › Guardar objetos como… › GeoJSON; deje su sistema de coordenadas original, el sistema lo transforma a 4326) o a KML, y cargue ese archivo. " +
  "Propuesta para después: leer el .zip en el navegador (.shp y .dbf con su .prj) sin servidor, cuando David entregue la capa real.";

const TIPOS = new Set(["Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon"]);

/** SRID declarado en un GeoJSON antiguo (member «crs»): «urn:ogc:def:crs:EPSG::3116», «EPSG:3116» o OGC CRS84 (= 4326). Sin «crs»: 4326 (RFC 7946). */
export function sridDeGeoJSON(o: Record<string, unknown>): number {
  const nombre = (o.crs as { properties?: { name?: string } } | undefined)?.properties?.name;
  if (typeof nombre !== "string") return 4326;
  if (/CRS84/i.test(nombre)) return 4326;
  const m = nombre.match(/EPSG:{1,2}(\d{4,6})/i);
  return m ? Number(m[1]) : 4326;
}

function columnasDe(filas: FilaCapa[]): string[] {
  const s = new Set<string>();
  for (const f of filas) for (const k of Object.keys(f.atributos)) s.add(k);
  return [...s];
}

export function leerGeoJSON(texto: string): CapaLeida {
  let j: unknown;
  try { j = JSON.parse(texto); } catch { throw new Error("El archivo no es un GeoJSON válido (no se pudo leer el texto)."); }
  if (!j || typeof j !== "object") throw new Error("El archivo no es un GeoJSON válido.");
  const o = j as Record<string, unknown>;
  const adv: string[] = [];
  let feats: unknown[];
  if (o.type === "FeatureCollection" && Array.isArray(o.features)) feats = o.features;
  else if (o.type === "Feature") feats = [o];
  else throw new Error("El GeoJSON debe ser una colección de objetos (FeatureCollection) con líneas, polígonos o puntos.");
  const filas: FilaCapa[] = [];
  feats.forEach((f, i) => {
    const x = f as { geometry?: { type?: string; coordinates?: unknown }; properties?: unknown };
    if (!x || !x.geometry || typeof x.geometry.type !== "string" || !TIPOS.has(x.geometry.type)) { adv.push(`El objeto ${i + 1} no tiene una geometría de punto, línea o polígono: se envía y el servidor lo reportará.`); }
    const atributos = x?.properties && typeof x.properties === "object" && !Array.isArray(x.properties) ? (x.properties as Atributos) : {};
    filas.push({ atributos, geometry: (x?.geometry ?? { type: "Desconocida", coordinates: [] }) as FilaCapa["geometry"] });
  });
  if (filas.length === 0) throw new Error("La capa no trae ningún objeto.");
  // Números enteros fuera del rango exacto de JavaScript: el texto original los trae con más dígitos de los que se pueden conservar.
  const grandes = filas.some((f) => Object.values(f.atributos).some((v) => typeof v === "number" && Number.isInteger(v) && !Number.isSafeInteger(v)));
  if (grandes || /"[^"\\]+"\s*:\s*\d{16,}(?![\d.])/.test(texto)) adv.push("Hay atributos numéricos de más de 15 dígitos: JavaScript no los conserva con exactitud. Si uno de ellos es el código de ruta, guárdelo como texto en el archivo.");
  return { origen: "geojson", srid: sridDeGeoJSON(o), filas, columnas: columnasDe(filas), advertencias: adv };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// KML (Google Earth, QGIS): Placemark con name, description, ExtendedData (Data/SimpleData) y Point, LineString, Polygon o MultiGeometry homogénea. Siempre WGS 84.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
const desescapar = (s: string) => s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&").trim();
const coordenadas = (txt: string): number[][] => txt.trim().split(/\s+/).filter(Boolean).map((t) => t.split(",").slice(0, 2).map(Number)).filter((p) => p.length === 2 && p.every(Number.isFinite));
const etiqueta = (bloque: string, tag: string): string[] => [...bloque.matchAll(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, "gi"))].map((m) => m[1]);

function geometriaKml(bloque: string): FilaCapa["geometry"] {
  const partes: { tipo: "Point" | "LineString" | "Polygon"; coords: unknown }[] = [];
  for (const m of bloque.matchAll(/<Point\b[^>]*>([\s\S]*?)<\/Point>/gi)) { const c = coordenadas(etiqueta(m[1], "coordinates")[0] ?? ""); if (c[0]) partes.push({ tipo: "Point", coords: c[0] }); }
  const sinPoligonos = bloque.replace(/<Polygon\b[\s\S]*?<\/Polygon>/gi, "");
  for (const m of sinPoligonos.matchAll(/<LineString\b[^>]*>([\s\S]*?)<\/LineString>/gi)) { const c = coordenadas(etiqueta(m[1], "coordinates")[0] ?? ""); if (c.length >= 2) partes.push({ tipo: "LineString", coords: c }); }
  for (const m of bloque.matchAll(/<Polygon\b[^>]*>([\s\S]*?)<\/Polygon>/gi)) {
    const anillos = etiqueta(m[1], "LinearRing").map((r) => coordenadas(etiqueta(r, "coordinates")[0] ?? "")).filter((a) => a.length >= 4);
    if (anillos.length) partes.push({ tipo: "Polygon", coords: anillos });
  }
  if (partes.length === 0) return { type: "Desconocida", coordinates: [] };
  if (partes.length === 1) return { type: partes[0].tipo, coordinates: partes[0].coords };
  const t = partes[0].tipo;
  if (partes.every((p) => p.tipo === t)) return { type: `Multi${t}`, coordinates: partes.map((p) => p.coords) };
  return { type: "GeometryCollection", geometries: partes.map((p) => ({ type: p.tipo, coordinates: p.coords })) };
}

export function leerKML(texto: string): CapaLeida {
  const marcas = [...texto.matchAll(/<Placemark\b[^>]*>([\s\S]*?)<\/Placemark>/gi)].map((m) => m[1]);
  if (marcas.length === 0) throw new Error("El KML no trae ningún Placemark.");
  const filas: FilaCapa[] = marcas.map((b) => {
    const atributos: Atributos = {};
    const nombre = etiqueta(b.replace(/<ExtendedData[\s\S]*?<\/ExtendedData>/gi, ""), "name")[0];
    const desc = etiqueta(b, "description")[0];
    if (nombre !== undefined) atributos.name = desencadenar(nombre);
    if (desc !== undefined) atributos.description = desencadenar(desc);
    for (const m of b.matchAll(/<(?:Data|SimpleData)\b[^>]*\bname="([^"]*)"[^>]*>([\s\S]*?)<\/(?:Data|SimpleData)>/gi)) {
      const v = desencadenar(m[2].replace(/<\/?value>/gi, ""));
      atributos[desescapar(m[1])] = v;
    }
    return { atributos, geometry: geometriaKml(b) };
  });
  return { origen: "kml", srid: 4326, filas, columnas: columnasDe(filas), advertencias: ["En un KML todos los valores llegan como texto (incluido el código de ruta)."] };
}
const desencadenar = desescapar;

/** Detecta el tipo por la extensión y el contenido y lee la capa. */
export function leerCapa(texto: string, nombreArchivo: string): CapaLeida {
  const n = nombreArchivo.toLowerCase();
  if (n.endsWith(".zip") || n.endsWith(".shp") || n.endsWith(".dbf")) throw new Error(MENSAJE_SHAPEFILE);
  if (n.endsWith(".kml") || /^\s*<\?xml|^\s*<kml/i.test(texto)) return leerKML(texto);
  return leerGeoJSON(texto);
}

/** Huella SHA-256 (hex) del contenido del archivo: sirve para que recargar el mismo archivo no duplique nada. */
export async function sha256Hex(datos: ArrayBuffer | Uint8Array): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", datos as BufferSource);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Divide la capa en lotes de hasta 200 geometrías y ~300 KB de JSON (el servidor admite 512 KB por solicitud). */
export function lotes(filas: FilaCapa[], maxFilas = 200, maxBytes = 300_000): { base: number; filas: FilaCapa[] }[] {
  const salida: { base: number; filas: FilaCapa[] }[] = [];
  let actual: FilaCapa[] = [], bytes = 0, base = 1;
  filas.forEach((f, i) => {
    const t = JSON.stringify(f).length;
    if (actual.length > 0 && (actual.length >= maxFilas || bytes + t > maxBytes)) { salida.push({ base, filas: actual }); actual = []; bytes = 0; base = i + 1; }
    actual.push(f); bytes += t;
  });
  if (actual.length) salida.push({ base, filas: actual });
  return salida;
}

/** Valores de ejemplo de una columna (para que el administrador reconozca cuál es el código). */
export const muestraColumna = (filas: FilaCapa[], col: string, n = 3): string[] => filas.slice(0, n).map((f) => { const v = f.atributos[col]; return v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v); });
