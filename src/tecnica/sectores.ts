// Geovisor técnico · Corte 1: sectores y subsectores hidráulicos. Lógica PURA (se prueba en Node).
// La tesela de la red trae de cada SEC su «clase» (sector | subsector) y su «nombre», pero NO el sector de cada subsector. La lista completa (leyenda,
// sector de cada uno según su atributo y puntos de las etiquetas) viene del paso 0 de producción (sectores_datos.ts); en la tesela se reconoce por el nombre.
// leerNombreSector es la comprobación cruzada (la prueba exige que los 29 nombres digan el mismo sector que el atributo).
import { COLOR_SECTOR, COLOR_SECTOR_SIN } from "./impresion/config";
import { SECTORES_DATOS, type SectorDato } from "./impresion/sectores_datos";

export type Sector = SectorDato;

/** «Sector 3» → {sector: "3"}; «Subsector 1.3» → {sector: "1", sub: "1.3"}; lo que no se pueda leer → null. */
export function leerNombreSector(nombre: string | null | undefined): { sector: string; sub: string | null } | null {
  const t = (nombre ?? "").trim().replace(/\s+/g, " ");
  let m = /^Subsector (\d{1,2})\.(\d{1,2})$/i.exec(t);
  if (m) return { sector: String(Number(m[1])), sub: `${Number(m[1])}.${Number(m[2])}` };
  m = /^Sector (\d{1,2})$/i.exec(t);
  if (m) return { sector: String(Number(m[1])), sub: null };
  return null;
}

export const SECTORES: Sector[] = SECTORES_DATOS;
export const SOLO_SECTORES = SECTORES.filter((s) => s.clase === "sector").sort((a, b) => Number(a.sector) - Number(b.sector));
export const subsectoresDe = (sector: string) => SECTORES.filter((s) => s.clase === "subsector" && s.sector === sector)
  .sort((a, b) => Number(a.sub!.split(".")[1]) - Number(b.sub!.split(".")[1]));
export const colorSector = (sector: string | null | undefined) => (sector && COLOR_SECTOR[sector]) || COLOR_SECTOR_SIN;

/** Expresión de MapLibre: el color de un SEC por su nombre (sector y subsectores del mismo sector, el mismo color). */
export function exprColorSector(): unknown {
  const pares = SECTORES.flatMap((s) => [s.nombre, colorSector(s.sector)]);
  return pares.length ? ["match", ["get", "nombre"], ...pares, COLOR_SECTOR_SIN] : COLOR_SECTOR_SIN;
}

/** Lo que se ve de los sectores: los dos interruptores generales y los renglones apagados (claves «s:3» para un sector con sus subsectores, «u:1.3» un subsector). */
export type VerSectores = { sectores: boolean; subsectores: boolean; apagados: string[] };
export const VER_SECTORES_INICIAL: VerSectores = { sectores: true, subsectores: true, apagados: [] };

/** Los nombres de los SEC que NO se dibujan según la leyenda. */
export function nombresOcultos(v: VerSectores): string[] {
  const ap = new Set(v.apagados);
  return SECTORES.filter((s) => (s.clase === "sector" ? !v.sectores : !v.subsectores) || ap.has(`s:${s.sector}`) || (s.sub !== null && ap.has(`u:${s.sub}`))).map((s) => s.nombre);
}

/** El texto de la ficha corta de un polígono. */
export function fichaSector(nombre: string | null | undefined): { titulo: string; sector: string | null } | null {
  const d = SECTORES.find((s) => s.nombre === (nombre ?? "").trim());
  const l = d ? { sector: d.sector, sub: d.sub } : leerNombreSector(nombre);
  if (!l) return null;
  return { titulo: l.sub ? `Subsector ${l.sub}` : `Sector ${l.sector}`, sector: `Sector ${l.sector}` };
}

/** Las etiquetas (GeoJSON de puntos): «Sector 3» y «1.3». */
export function etiquetasSectores(): GeoJSON.FeatureCollection {
  return { type: "FeatureCollection", features: SECTORES.map((s) => ({ type: "Feature" as const,
    properties: { nombre: s.nombre, clase: s.clase, texto: s.sub ?? `Sector ${s.sector}`, color: colorSector(s.sector) },
    geometry: { type: "Point" as const, coordinates: [s.lon, s.lat] } })) };
}
