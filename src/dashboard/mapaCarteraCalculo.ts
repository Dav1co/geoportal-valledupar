// Lógica PURA del mapa de calor de cartera (zona «Mapa de calor» de Cartera desagregada), sin React ni MapLibre.
// Reutiliza mapaCalorComun.ts (clasesPorCuantiles, colorClase, cuadrado con lado parametrizable). Nada individual: solo celdas agregadas.
import { clasesPorCuantiles, colorClase, nClases, type Clases } from "./mapaCalorComun";

export type Medida = "deuda" | "gt8" | "gt60" | "part60";
export type Resolucion = "auto" | "100" | "250";

export const MEDIDAS: { id: Medida; nombre: string; corto: string; nota?: string }[] = [
  { id: "deuda", nombre: "Deuda total", corto: "Deuda total" },
  { id: "gt8", nombre: "Contratos con más de 8 facturas vencidas", corto: "Más de 8 facturas",
    nota: "Se muestra la cartera total de esos contratos, no solo la parte vieja de su deuda." },
  { id: "gt60", nombre: "Contratos con más de 60 facturas vencidas", corto: "Más de 60 facturas",
    nota: "Se muestra la cartera total de esos contratos, no solo la parte vieja de su deuda." },
  { id: "part60", nombre: "Participación de los contratos con más de 60 facturas", corto: "% con más de 60 facturas",
    nota: "Porcentaje de la deuda de la celda que pertenece a contratos con más de 60 facturas vencidas (cartera total de esos contratos)." },
];

// Rampa de un solo tono (cartera = ámbar oscuro, más oscuro = más deuda). Se interpola de forma continua entre los cortes por cuantiles.
export const RAMPA_CARTERA = ["#FCEBD0", "#F6CB8C", "#E8A33D", "#C27A12", "#8A5200"];

export type Filtros = { comunas: number[]; barrios: number[]; ciclos: number[]; bandas: number[]; tramos: number[] };
export const FILTROS_VACIO: Filtros = { comunas: [], barrios: [], ciclos: [], bandas: [], tramos: [] };
export const hayFiltro = (f: Filtros) => f.comunas.length + f.barrios.length + f.ciclos.length + f.bandas.length + f.tramos.length > 0;

/** Antigüedad de la deuda DEL CONTRATO por número de facturas vencidas (máximo del contrato). Clasifica CONTRATOS, no pesos: el contrato entra completo, con toda su deuda, en su tramo. */
export const TRAMOS_FV: { id: number; nombre: string }[] = [
  { id: 0, nombre: "0 (sin facturas vencidas)" }, { id: 1, nombre: "1 a 3" }, { id: 2, nombre: "4 a 8" },
  { id: 3, nombre: "9 a 24" }, { id: 4, nombre: "25 a 60" }, { id: 5, nombre: "Más de 60" },
];
export const AYUDA_TRAMOS =
  "Clasifica contratos por su número de facturas vencidas, no la antigüedad de cada peso de la deuda: un contrato con 30 facturas vencidas aparece completo, con toda su deuda, en «25 a 60». Para la edad de cada peso, véase «Edad de la cartera».";

const lista = (v: number[]) => [...v].sort((a, b) => a - b).join(",");
/** Parámetros de la RPC (todos cadenas, orden de claves fijo para que biCache reutilice respuestas). */
export function paramsMapa(periodo: string, medida: Medida, res: Resolucion, f: Filtros): Record<string, string> {
  const p: Record<string, string> = { periodo, parte: "mapa", medida, resolucion: res };
  if (f.comunas.length) p.comunas = lista(f.comunas);
  if (f.barrios.length) p.barrios = lista(f.barrios);
  if (f.ciclos.length) p.ciclos = lista(f.ciclos);
  if (f.bandas.length) p.bandas = lista(f.bandas);
  if (f.tramos.length) p.tramos = lista(f.tramos);
  return p;
}
export const paramsCatalogo = (periodo: string): Record<string, string> => ({ periodo, parte: "catalogo" });

export type Celda = {
  id: string; cx: number; cy: number; lon: number; lat: number;
  n: number; s: number; n8: number | null; s8: number | null; n60: number | null; s60: number | null;
};
export type Concilia = {
  totalS: number; totalN: number; dibujadaS: number; dibujadaN: number; noDibujadaS: number; noDibujadaN: number;
  desglose: boolean; menos5S: number | null; menos5N: number | null; sinCoordS: number | null; sinCoordN: number | null; anilloS: number | null; anilloN: number | null;
};
export type Meta = { lado: number; motivo: string; suficiente: boolean; contratosFiltro: number | null };
export type Cortes = { q1: number; q2: number; q3: number; p95: number; contratos: number; saldo: number };
export type RespuestaMapa = { meta: Meta | null; celdas: Celda[]; concilia: Concilia | null; cortes: Cortes | null };

const num = (v: unknown): number => Number(v);
const numN = (v: unknown): number | null => (v == null ? null : Number(v));

export function leerMapa(filas: Record<string, unknown>[]): RespuestaMapa {
  const r: RespuestaMapa = { meta: null, celdas: [], concilia: null, cortes: null };
  for (const x of filas) {
    if (x.tipo === "meta") r.meta = { lado: num(x.lado), motivo: String(x.motivo_resolucion ?? ""), suficiente: x.suficiente === true, contratosFiltro: numN(x.contratos_filtro) };
    else if (x.tipo === "celda") r.celdas.push({ id: `${x.cx}_${x.cy}`, cx: num(x.cx), cy: num(x.cy), lon: num(x.lon), lat: num(x.lat), n: num(x.n), s: num(x.s), n8: numN(x.n8), s8: numN(x.s8), n60: numN(x.n60), s60: numN(x.s60) });
    else if (x.tipo === "concilia") r.concilia = { totalS: num(x.total_s), totalN: num(x.total_n), dibujadaS: num(x.dibujada_s), dibujadaN: num(x.dibujada_n), noDibujadaS: num(x.no_dibujada_s), noDibujadaN: num(x.no_dibujada_n), desglose: x.desglose === true, menos5S: numN(x.menos5_s), menos5N: numN(x.menos5_n), sinCoordS: numN(x.sin_coord_s), sinCoordN: numN(x.sin_coord_n), anilloS: numN(x.anillo_s), anilloN: numN(x.anillo_n) };
    else if (x.tipo === "corte") r.cortes = { q1: num(x.q1), q2: num(x.q2), q3: num(x.q3), p95: num(x.p95), contratos: num(x.contratos), saldo: num(x.saldo) };
  }
  return r;
}

/** `contratos`: número de contratos; null = menos de 5 (no se publica); undefined = sin conteo (opción por defecto). */
export type Opcion = { id: number; nombre: string; contratos?: number | null; comuna?: number };
export type Catalogo = { comunas: Opcion[]; barrios: Opcion[]; ciclos: Opcion[]; tramos: Opcion[] };
export function leerCatalogo(filas: Record<string, unknown>[]): Catalogo {
  const c: Catalogo = { comunas: [], barrios: [], ciclos: [], tramos: [] };
  for (const x of filas) {
    const o: Opcion = { id: num(x.id), nombre: String(x.nombre ?? ""), contratos: numN(x.contratos), comuna: x.comuna == null ? undefined : num(x.comuna) };
    if (x.tipo === "comuna") c.comunas.push(o); else if (x.tipo === "barrio") c.barrios.push(o); else if (x.tipo === "ciclo") c.ciclos.push(o);
    else if (x.tipo === "tramo") c.tramos.push({ ...o, nombre: TRAMOS_FV.find((t) => t.id === o.id)?.nombre ?? String(o.id) });
  }
  c.comunas.sort((a, b) => (a.id || 99) - (b.id || 99));
  c.ciclos.sort((a, b) => (a.id || 99) - (b.id || 99));
  // Los seis tramos son una lista FIJA: se completan con el catálogo cuando trae su conteo, pero el menú nunca queda vacío (p. ej. con un catálogo en caché anterior a la columna del tramo).
  for (const t of TRAMOS_FV) if (!c.tramos.some((x) => x.id === t.id)) c.tramos.push({ id: t.id, nombre: t.nombre });
  c.tramos.sort((a, b) => a.id - b.id);
  c.barrios.sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
  return c;
}

/** Cascada: con comunas elegidas, solo los barrios de esas comunas; al cambiar las comunas se descartan los barrios que ya no aplican. */
export const barriosVisibles = (cat: Catalogo, comunas: number[]) => (comunas.length ? cat.barrios.filter((b) => b.comuna != null && comunas.includes(b.comuna)) : cat.barrios);
/** Rótulo del barrio en el filtro: si el nombre se repite en más de una comuna (o es «Otros barrios»/«Sin barrio», que hay uno por comuna), se agrega la comuna. */
export function rotuloBarrio(cat: Catalogo, b: Opcion): string {
  const repetido = cat.barrios.filter((x) => x.nombre === b.nombre).length > 1;
  return repetido && b.comuna != null ? `${b.nombre} (${b.comuna === 0 ? "sin comuna" : `comuna ${b.comuna}`})` : b.nombre;
}
export function depurarBarrios(cat: Catalogo, f: Filtros): Filtros {
  if (!f.comunas.length) return f;
  const ok = new Set(barriosVisibles(cat, f.comunas).map((b) => b.id));
  const barrios = f.barrios.filter((b) => ok.has(b));
  return barrios.length === f.barrios.length ? f : { ...f, barrios };
}

/** Valor que se pinta en una celda según la medida (null = no se pinta). */
export function valorCelda(c: Celda, m: Medida): number | null {
  if (m === "deuda") return c.s;
  if (m === "gt8") return c.s8;
  if (m === "gt60") return c.s60;
  return c.s60 == null || c.s <= 0 ? null : (c.s60 / c.s) * 100;
}

/** Cortes por cuantiles de lo VISIBLE y paradas de color continuas (estrictamente crecientes) para MapLibre. */
export function escalaVisible(valores: number[]): { clases: Clases | null; paradas: (number | string)[] } {
  const clases = clasesPorCuantiles(valores);
  if (!clases) return { clases: null, paradas: [] };
  const k = nClases(clases);
  const puntos = [clases.min, ...clases.cortes, clases.max];
  const paradas: (number | string)[] = [];
  let ultimo = -Infinity;
  puntos.forEach((v, i) => {
    if (v > ultimo) { paradas.push(v, colorClase(Math.min(i, k - 1), k, RAMPA_CARTERA)); ultimo = v; }
  });
  return { clases, paradas };
}

/** Rótulos de los cuatro cuartiles con los cortes que devuelve la RPC (cuartil 4 opcionalmente dividido en 75 a 95 % y 5 % superior). */
export function rotulosBandas(c: Cortes | null, pesos: (v: number) => string): { id: number; nombre: string }[] {
  // Sin los cortes (todavía no llega el mapa), las cinco opciones salen sin pesos para que el menú nunca quede vacío; los pesos aparecen al llegar el mapa.
  if (!c) return [
    { id: 1, nombre: "Cuartil 1 (menor deuda)" }, { id: 2, nombre: "Cuartil 2" }, { id: 3, nombre: "Cuartil 3" },
    { id: 4, nombre: "Cuartil 4 (75 a 95 %)" }, { id: 5, nombre: "Cuartil 4 (5 % superior)" },
  ];
  return [
    { id: 1, nombre: `Cuartil 1: hasta ${pesos(c.q1)}` },
    { id: 2, nombre: `Cuartil 2: de ${pesos(c.q1)} a ${pesos(c.q2)}` },
    { id: 3, nombre: `Cuartil 3: de ${pesos(c.q2)} a ${pesos(c.q3)}` },
    { id: 4, nombre: `Cuartil 4 (75 a 95 %): de ${pesos(c.q3)} a ${pesos(c.p95)}` },
    { id: 5, nombre: `Cuartil 4 (5 % superior): más de ${pesos(c.p95)}` },
  ];
}

/** Caja que encierra las celdas (para ajustar el mapa): [oeste, sur, este, norte] en grados, con medio lado de margen. */
export function cajaCeldas(celdas: Celda[], lado: number): [number, number, number, number] | null {
  if (!celdas.length) return null;
  const mLat = lado / 2 / 111320;
  let o = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
  for (const c of celdas) {
    const mLon = lado / 2 / (111320 * Math.cos((c.lat * Math.PI) / 180));
    o = Math.min(o, c.lon - mLon); e = Math.max(e, c.lon + mLon); s = Math.min(s, c.lat - mLat); n = Math.max(n, c.lat + mLat);
  }
  return [o, s, e, n];
}

// ---------- Capa «Calor suave» ----------
// La paleta, el radio, los pesos y la intensidad viven en mapaCalorCapas.ts (los usan también el mapa de Pérdidas); se vuelven a exportar para no cambiar las importaciones.
export {
  pesosPorCuantil, pesoCalor, ANCLAS_CALOR, colorCalor, COLORES_CALOR, DEGRADE_CALOR_CSS, FACTOR_RADIO_CALOR, radioCalorMetros, LATITUD_CALOR, METROS_POR_PIXEL_Z0,
  metrosPorPixel, radioCalor, intensidadBaseCalor, intensidadCalor,
} from "./mapaCalorCapas";
export type { CapasMapa } from "./mapaCalorCapas";
import type { CapasMapa } from "./mapaCalorCapas";

/** Capas efectivas: la participación (un porcentaje) solo existe como celdas; fuerza Celdas y apaga Calor suave. */
export function capasEfectivas(c: CapasMapa, medida: Medida): CapasMapa {
  return medida === "part60" ? { celdas: true, calor: false } : c;
}
