// Íconos de los Cuadernos (hoja aprobada por David, 26-nov): SVG armados desde iconos_datos.ts. Activos: una forma por tipo y DOS colores (el sistema);
// problemas: pin de color fijo con su glifo blanco. Se usan como <img> en la barra y como imagen en el lienzo de las marcas, en la captura y en el PDF.
import { COLOR_SISTEMA, ICONOS_ACTIVO, ICONOS_PROBLEMA, PIN } from "./iconos_datos";

const HALO = 3;
const ENV_ACTIVO = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
const ENV_GLIFO = 'fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"';

export function svgActivo(codigo: string, sistema: "acueducto" | "alcantarillado", px = 24): string | null {
  const ic = ICONOS_ACTIVO.find((i) => i.codigo === codigo); if (!ic) return null;
  const halo = ic.svg.replace(/fill="currentColor"/g, 'fill="#fff"').replace(/stroke-width="([\d.]+)"/g, (_, w) => `stroke-width="${Number(w) + HALO}"`);
  const fondo = ic.fondo ? `<g fill="#fff" stroke="#fff" stroke-width="${HALO}" stroke-linejoin="round">${ic.fondo}</g>` : "";
  // margen de 3 unidades para que el halo no se corte
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="-3 -3 30 30"><g fill="none" stroke="#fff" stroke-width="${2 + HALO}" stroke-linecap="round" stroke-linejoin="round">${halo}</g>${fondo}` +
    `<g ${ENV_ACTIVO} color="${COLOR_SISTEMA[sistema]}">${ic.svg}</g></svg>`;
}
export function svgProblema(codigo: string, ancho = 28): string | null {
  const ic = ICONOS_PROBLEMA.find((i) => i.codigo === codigo); if (!ic) return null;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ancho}" height="${(ancho * 36) / 28}" viewBox="${PIN.viewBox}"><g color="${ic.color}">${PIN.svg}</g>` +
    `<g transform="${PIN.glifo_transform}" color="${PIN.glifo_color}" ${ENV_GLIFO}>${ic.glifo}</g></svg>`;
}
export const aUrl = (svg: string) => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
export const urlActivo = (codigo: string, sistema: "acueducto" | "alcantarillado") => { const s = svgActivo(codigo, sistema, 48); return s ? aUrl(s) : ""; };
export const urlProblema = (codigo: string) => { const s = svgProblema(codigo, 56); return s ? aUrl(s) : ""; };
export const nombreActivo = (codigo: string | null) => ICONOS_ACTIVO.find((i) => i.codigo === codigo)?.nombre ?? "Activo";
export const nombreProblema = (codigo: string | null) => ICONOS_PROBLEMA.find((i) => i.codigo === codigo)?.nombre ?? "Problema";
export const colorProblema = (codigo: string | null) => ICONOS_PROBLEMA.find((i) => i.codigo === codigo)?.color ?? "#B3261E";

// ---------- imágenes para el lienzo (se cargan una vez; grandes, para que el PDF no las pixele) ----------
const cache = new Map<string, HTMLImageElement>();
const esperando = new Map<string, Promise<HTMLImageElement>>();
function cargar(clave: string, svg: string | null): Promise<HTMLImageElement | null> {
  if (!svg) return Promise.resolve(null);
  const ya = cache.get(clave); if (ya) return Promise.resolve(ya);
  let p = esperando.get(clave);
  if (!p) {
    p = new Promise<HTMLImageElement>((ok, mal) => { const i = new Image(); i.onload = () => { cache.set(clave, i); ok(i); }; i.onerror = () => mal(new Error("ícono")); i.src = aUrl(svg); });
    esperando.set(clave, p);
  }
  return p.catch(() => null);
}
export const claveIcono = (tipo: "problema" | "activo", subtipo: string, sistema?: string | null) => (tipo === "problema" ? `p:${subtipo}` : `a:${subtipo}:${sistema ?? "acueducto"}`);
/** La imagen ya cargada (o undefined si aún no). */
export const imagenIcono = (clave: string) => cache.get(clave);
/** Carga TODOS los íconos (33 imágenes pequeñas) y avisa al terminar. */
export function cargarIconos(): Promise<void> {
  const ps: Promise<unknown>[] = [];
  for (const p of ICONOS_PROBLEMA) ps.push(cargar(claveIcono("problema", p.codigo), svgProblema(p.codigo, 112)));
  for (const a of ICONOS_ACTIVO) for (const s of ["acueducto", "alcantarillado"] as const) ps.push(cargar(claveIcono("activo", a.codigo, s), svgActivo(a.codigo, s, 120)));
  return Promise.all(ps).then(() => undefined);
}
