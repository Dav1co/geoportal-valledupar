// «Compartir vista» del mapa comercial (#v=lng,lat,zoom y, opcionales, c, e, b, t). Lógica PURA, sin React ni MapLibre, para probarla aparte.
// El enlace solo dice DÓNDE mirar: abrir el mapa sigue exigiendo sesión, y lo que se ve lo decide el servidor (teselas con el token de quien lo abre).
import { pantallaInicial, pantallaValida, type AreasDisponibles, type Pantalla } from "./areas";

export type VistaMapa = { lng: number; lat: number; zoom: number };
export type EstadoHash = {
  inicial: VistaMapa | null;
  filtro: "todos" | "con" | "sin";
  estado: "" | "DEMOLIDO" | "EN CONSTRUCCION" | "DESOCUPADO";
  base: "calles" | "satelital";
  terrenos: boolean;
};

/** Lee el hash de la URL tal como lo arma «Compartir vista». Sin hash: null (todo como siempre). `inicial` solo con una vista válida (números y rangos sensatos). */
export function leerHash(hash: string): EstadoHash | null {
  const h = hash.replace(/^#/, "");
  if (!h) return null;
  const p = new URLSearchParams(h);
  const v = p.get("v");
  let inicial: VistaMapa | null = null;
  if (v) {
    const partes = v.split(",");
    const [lng, lat, zoom] = partes.map((x) => (x.trim() === "" ? NaN : Number(x)));
    if (partes.length === 3 && [lng, lat, zoom].every(Number.isFinite) && Math.abs(lng) <= 180 && Math.abs(lat) <= 90 && zoom >= 0 && zoom <= 24) inicial = { lng, lat, zoom };
  }
  const c = p.get("c"), e = p.get("e"), b = p.get("b"), t = p.get("t");
  return {
    inicial,
    filtro: c === "con" || c === "sin" ? c : "todos",
    estado: e === "DEMOLIDO" || e === "EN CONSTRUCCION" || e === "DESOCUPADO" ? e : "",
    base: b === "satelital" ? "satelital" : "calles",
    terrenos: t !== "0",
  };
}

/** ¿El hash trae una vista del mapa comercial (v= válida)? */
export const esEnlaceVista = (hash: string) => leerHash(hash)?.inicial != null;

export const AVISO_SIN_COMERCIAL = "Este enlace es del mapa Comercial y su usuario no tiene acceso a él.";

/** Pantalla al abrir el geoportal (o al llegar un enlace con la página abierta):
 *  - enlace del geovisor técnico y Técnica disponible → Técnica (como siempre);
 *  - enlace de vista y Comercial disponible → el mapa comercial directo, sin la ventana de entrada;
 *  - enlace de vista SIN Comercial → su pantalla de siempre, con el aviso;
 *  - sin enlace → la de siempre. */
export function pantallaConEnlace(a: AreasDisponibles, enlace: { vista: boolean; geovisor: boolean }): { pantalla: Pantalla; aviso: string | null } {
  if (enlace.geovisor && pantallaValida("tecnica", a)) return { pantalla: "tecnica", aviso: null };
  if (enlace.vista && pantallaValida("comercial", a)) return { pantalla: "comercial", aviso: null };
  return { pantalla: pantallaInicial(a), aviso: enlace.vista ? AVISO_SIN_COMERCIAL : null };
}
