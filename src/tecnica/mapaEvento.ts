import type { ZonaGeo } from "./apiEventos";

// Corte 15: cómo se pinta la zona de un evento de suspensión, igual en el geovisor (modo «Afectaciones») y en el minimapa de «Declarar evento».
// PROPUESTA de color (por aprobar de David, con las capturas): el naranja de la guía (--t-naranja, #c25e00, el mismo de «afectada sin agua»), con borde CONTINUO
// de 2 px y relleno al 12 %. Se distingue de la tubería afectada (naranja punteado, una línea) y de la cerrada (rojo): la zona es un área, no un tramo.
export const COLOR_EVENTO = "#c25e00";
export const RELLENO_EVENTO = 0.12;
export const BORDE_EVENTO_PX = 2;

const R_TIERRA = 6371008.8, RAD = Math.PI / 180;
/** Metros entre dos puntos (haversine). */
export function metrosEntrePuntos(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const dLat = (b.lat - a.lat) * RAD, dLon = (b.lon - a.lon) * RAD;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * RAD) * Math.cos(b.lat * RAD) * Math.sin(dLon / 2) ** 2;
  return 2 * R_TIERRA * Math.asin(Math.min(1, Math.sqrt(h)));
}
/** El punto a `m` metros de `c` hacia el rumbo dado (0 = norte, 90 = este). */
export function puntoA(c: { lat: number; lon: number }, m: number, rumbo: number): { lat: number; lon: number } {
  const d = m / R_TIERRA, r = rumbo * RAD, la = c.lat * RAD, lo = c.lon * RAD;
  const lat = Math.asin(Math.sin(la) * Math.cos(d) + Math.cos(la) * Math.sin(d) * Math.cos(r));
  const lon = lo + Math.atan2(Math.sin(r) * Math.sin(d) * Math.cos(la), Math.cos(d) - Math.sin(la) * Math.sin(lat));
  return { lat: lat / RAD, lon: lon / RAD };
}
/** Un círculo como polígono (para dibujarlo mientras se ajusta; el que se guarda lo arma el servidor con el centro y el radio). */
export function circuloGeo(c: { lat: number; lon: number }, radio_m: number, lados = 72): { type: "Polygon"; coordinates: number[][][] } {
  const anillo: number[][] = [];
  for (let i = 0; i <= lados; i++) { const p = puntoA(c, radio_m, (360 * i) / lados); anillo.push([p.lon, p.lat]); }
  return { type: "Polygon", coordinates: [anillo] };
}
/** La caja [oeste, sur, este, norte] de una zona (o nada si no tiene geometría, como «toda la ciudad»). */
export function cajaDeZona(g: ZonaGeo | undefined): [number, number, number, number] | null {
  if (!g) return null;
  let o = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
  const ver = (x: unknown): void => { if (Array.isArray(x) && typeof x[0] === "number" && typeof x[1] === "number") { o = Math.min(o, x[0]); e = Math.max(e, x[0]); s = Math.min(s, x[1]); n = Math.max(n, x[1]); } else if (Array.isArray(x)) x.forEach(ver); };
  ver(g.coordinates);
  return Number.isFinite(o) ? [o, s, e, n] : null;
}
