// Cuadernos de análisis: lógica PURA (se prueba en Node, sin navegador). Las marcas del servidor más los cambios pendientes dan lo que se ve; los cambios
// pendientes son lo que «Guardar» manda. Nada se borra: una marca guardada se ANULA con motivo; una que aún no se guardó simplemente se descarta.
import type { Cambio, Estilo, GeomMarca, Marca, TipoMarca } from "./apiAnalisis";

export type Pendientes = Record<string, Cambio>;
export const NOMBRE_TIPO: Record<TipoMarca, string> = { problema: "Problema", activo: "Activo (propuesta)", referencia: "Punto de referencia", postit: "Post-it", mano: "Trazo a mano",
  circulo: "Círculo", linea: "Línea o flecha", zona: "Zona afectada" };
export const NOMBRE_CATEGORIA: Record<string, string> = { problema: "Problema", propuesta: "Propuesta", obra: "Obra", observacion: "Observación" };
export const COLORES_LIBRES = ["#D00000", "#E8590C", "#F2C200", "#2B8A3E", "#1F5FA8", "#6D28D9", "#111827"];
export const COLOR_POSTIT = "#FFE066";
export const AVISO_NOTA = "No escriba nombres, cédulas ni teléfonos";
export const NOTA_MAX = 500;

/** Valledupar (la misma caja que valida el servidor, analisis.f_en_valledupar). */
export const CAJA = { oeste: -73.35, sur: 10.33, este: -73.16, norte: 10.56 };
export const dentro = (lon: number, lat: number) => lon >= CAJA.oeste && lon <= CAJA.este && lat >= CAJA.sur && lat <= CAJA.norte;

export function uuid(): string {
  const c = globalThis.crypto as Crypto;
  if (typeof c.randomUUID === "function") return c.randomUUID();
  const b = new Uint8Array(16); c.getRandomValues(b); b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

const r7 = (n: number) => Math.round(n * 1e7) / 1e7;
export const punto = (lon: number, lat: number): GeomMarca => ({ type: "Point", coordinates: [r7(lon), r7(lat)] });
export const linea = (c: [number, number][]): GeomMarca => ({ type: "LineString", coordinates: c.map(([a, b]) => [r7(a), r7(b)] as [number, number]) });
/** Polígono cerrado (repite el primer vértice al final). */
export const poligono = (c: [number, number][]): GeomMarca => { const v = c.map(([a, b]) => [r7(a), r7(b)] as [number, number]); return { type: "Polygon", coordinates: [[...v, v[0]]] }; };

/** Una marca nueva (aún sin guardar) con la forma de las del servidor, para pintarla igual. */
export function marcaNueva(d: { tipo: TipoMarca; geom: GeomMarca; subtipo?: string | null; sistema?: "acueducto" | "alcantarillado" | null; nota?: string | null; estilo?: Estilo | null; radio_m?: number | null }): Cambio {
  return { op: "nueva", marca_id: uuid(), tipo: d.tipo, geom: d.geom, subtipo: d.subtipo ?? null, sistema: d.sistema ?? null, categoria: null, nota: d.nota ?? null, estilo: d.estilo ?? null, radio_m: d.radio_m ?? null };
}

const comoMarca = (c: Cambio, base?: Marca): Marca => ({
  id: c.marca_id, version: base?.version ?? 0, creada_en_version: base?.creada_en_version ?? 0, tipo: (c.tipo ?? base?.tipo) as TipoMarca, subtipo: c.subtipo ?? null, sistema: c.sistema ?? null,
  categoria: c.categoria ?? null, nota: c.nota ?? null, estilo: c.estilo ?? null, geom: (c.geom ?? base?.geom) as GeomMarca, radio_m: c.radio_m ?? null,
  // una zona que se movió pierde su conteo hasta guardar (lo vuelve a contar el servidor)
  conteo_predios: base && JSON.stringify(base.geom) === JSON.stringify(c.geom) ? base.conteo_predios : null,
  conteo_contratos: base && JSON.stringify(base.geom) === JSON.stringify(c.geom) ? base.conteo_contratos : null,
  activo_codigo: base?.activo_codigo ?? null, sector: base && JSON.stringify(base.geom) === JSON.stringify(c.geom) ? base.sector : null,
  subsector: base && JSON.stringify(base.geom) === JSON.stringify(c.geom) ? base.subsector : null,
});

/** Lo que se ve: las marcas guardadas con los cambios pendientes encima (las anuladas no salen). */
export function marcasVisibles(guardadas: Marca[], pend: Pendientes): (Marca & { pendiente?: boolean })[] {
  const ids = new Set(guardadas.map((m) => m.id));
  const res: (Marca & { pendiente?: boolean })[] = [];
  for (const m of guardadas) {
    const c = pend[m.id];
    if (!c) res.push(m);
    else if (c.op === "cambia") res.push({ ...comoMarca(c, m), pendiente: true });
  }
  for (const c of Object.values(pend)) if (c.op === "nueva" && !ids.has(c.marca_id)) res.push({ ...comoMarca(c), pendiente: true });
  return res;
}

/** Cambia datos de una marca: si es nueva sigue siendo «nueva»; si ya estaba guardada queda como «cambia». */
export function conCambio(guardadas: Marca[], pend: Pendientes, id: string, d: Partial<Pick<Cambio, "nota" | "categoria" | "estilo" | "geom" | "radio_m">>): Pendientes {
  const previo = pend[id];
  if (previo && previo.op !== "anula") return { ...pend, [id]: { ...previo, ...d } };
  const m = guardadas.find((x) => x.id === id);
  if (!m) return pend;
  return { ...pend, [id]: { op: "cambia", marca_id: id, tipo: m.tipo, subtipo: m.subtipo, sistema: m.sistema, categoria: m.categoria, nota: m.nota, estilo: m.estilo, geom: m.geom, radio_m: m.radio_m, ...d } };
}

/** Quita una marca: la que no se ha guardado se descarta; la guardada se anula con motivo. */
export function conAnulacion(guardadas: Marca[], pend: Pendientes, id: string, motivo: string): Pendientes {
  const n = { ...pend };
  if (!guardadas.some((m) => m.id === id)) { delete n[id]; return n; }
  n[id] = { op: "anula", marca_id: id, motivo };
  return n;
}

/** Lo que se manda al servidor: sin nulos (el servidor los toma como «sin dato») y solo las claves que conoce. */
export function cambiosParaGuardar(pend: Pendientes): Cambio[] {
  return Object.values(pend).map((c) => {
    if (c.op === "anula") return { op: c.op, marca_id: c.marca_id, motivo: c.motivo };
    const l: Record<string, unknown> = { op: c.op, marca_id: c.marca_id, tipo: c.tipo, geom: c.geom };
    for (const k of ["subtipo", "sistema", "categoria", "nota", "radio_m"] as const) if (c[k] !== null && c[k] !== undefined && c[k] !== "") l[k] = c[k];
    if (c.estilo && Object.keys(c.estilo).length) l.estilo = c.estilo;
    return l as unknown as Cambio;
  });
}

// ---------- medidas (de pantalla; no se guardan) ----------
const R = 6371008.8, rad = (g: number) => (g * Math.PI) / 180;
export function distancia(a: [number, number], b: [number, number]): number {
  const dLat = rad(b[1] - a[1]), dLon = rad(b[0] - a[0]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}
export const largo = (c: [number, number][]) => c.slice(1).reduce((s, p, i) => s + distancia(c[i], p), 0);
/** Área de un polígono pequeño (m²): proyección local equirrectangular; suficiente a la escala de una ciudad. */
export function area(c: [number, number][]): number {
  if (c.length < 3) return 0;
  const lat0 = rad(c.reduce((s, p) => s + p[1], 0) / c.length);
  const xy = c.map(([lon, lat]) => [R * rad(lon) * Math.cos(lat0), R * rad(lat)]);
  let s = 0;
  for (let i = 0; i < xy.length; i++) { const [x1, y1] = xy[i], [x2, y2] = xy[(i + 1) % xy.length]; s += x1 * y2 - x2 * y1; }
  return Math.abs(s) / 2;
}
const nf = (n: number, d = 0) => new Intl.NumberFormat("es-CO", { maximumFractionDigits: d, minimumFractionDigits: d }).format(n);
export const textoDistancia = (m: number) => (m >= 1000 ? `${nf(m / 1000, 2)} km` : `${nf(m)} m`);
export const textoArea = (m2: number) => (m2 >= 10000 ? `${nf(m2 / 10000, 2)} ha` : `${nf(m2)} m²`);
export const miles = (n: number) => nf(n);

/** Aligera un trazo a mano en pantalla (Douglas-Peucker en grados; ~1 m) para no mandar miles de puntos. El servidor lo vuelve a simplificar. */
export function aligerar(c: [number, number][], tol = 0.00001): [number, number][] {
  if (c.length < 3) return c;
  const d2 = (p: [number, number], a: [number, number], b: [number, number]) => {
    const dx = b[0] - a[0], dy = b[1] - a[1]; const l = dx * dx + dy * dy;
    const t = l ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l)) : 0;
    return (p[0] - a[0] - t * dx) ** 2 + (p[1] - a[1] - t * dy) ** 2;
  };
  const guarda = new Uint8Array(c.length); guarda[0] = 1; guarda[c.length - 1] = 1;
  const pila: [number, number][] = [[0, c.length - 1]];
  while (pila.length) {
    const [i, j] = pila.pop()!; let max = 0, k = -1;
    for (let n = i + 1; n < j; n++) { const d = d2(c[n], c[i], c[j]); if (d > max) { max = d; k = n; } }
    if (k > 0 && max > tol * tol) { guarda[k] = 1; pila.push([i, k], [k, j]); }
  }
  return c.filter((_, n) => guarda[n]);
}

// ---------- borrador en el dispositivo ----------
export type Borrador = { cuaderno: string; version_base: number; pend: Pendientes; guardado_en: string };
const clave = (correo: string, id: string) => `geoportal.cuaderno.borrador.${correo}.${id}`;
export function leerBorrador(correo: string, id: string): Borrador | null {
  try {
    const t = localStorage.getItem(clave(correo, id)); if (!t) return null;
    const b = JSON.parse(t) as Borrador;
    return b && b.cuaderno === id && typeof b.version_base === "number" && b.pend && typeof b.pend === "object" && Object.keys(b.pend).length ? b : null;
  } catch { return null; }
}
export function escribirBorrador(correo: string, id: string, version_base: number, pend: Pendientes): void {
  try {
    if (!Object.keys(pend).length) { localStorage.removeItem(clave(correo, id)); return; }
    localStorage.setItem(clave(correo, id), JSON.stringify({ cuaderno: id, version_base, pend, guardado_en: new Date().toISOString() } satisfies Borrador));
  } catch { /* sin espacio o sin permiso: el borrador es una ayuda, no bloquea */ }
}
export function borrarBorrador(correo: string, id: string): void { try { localStorage.removeItem(clave(correo, id)); } catch { /* nada */ } }
