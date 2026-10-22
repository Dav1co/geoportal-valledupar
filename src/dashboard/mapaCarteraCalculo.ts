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

// ---------- Capa «Calor suave» (heatmap de MapLibre) ----------
/** Peso normalizado POR CUANTILES: el rango percentil de cada valor (los empates comparten el rango medio), llevado a [0,1]. Así unas pocas celdas muy grandes no apagan al resto. */
export function pesosPorCuantil(valores: number[]): number[] {
  const n = valores.length;
  if (n === 0) return [];
  if (n === 1) return [1];
  const orden = valores.map((v, i) => [v, i] as const).sort((a, b) => a[0] - b[0]);
  const rango = new Array<number>(n);
  let i = 0;
  while (i < n) {
    let j = i;
    while (j + 1 < n && orden[j + 1][0] === orden[i][0]) j++;
    const medio = (i + j) / 2;
    for (let k = i; k <= j; k++) rango[orden[k][1]] = medio / (n - 1);
    i = j + 1;
  }
  return rango;
}
/** El peso mínimo evita que la celda más baja desaparezca del calor: todo lo visible aporta. */
export const pesoCalor = (p: number) => 0.1 + 0.9 * p;

/** Paleta continua del calor (calibrada con la imagen de referencia, un heatmap translúcido sobre mapa claro): azul → cian → verde → amarillo → naranja → rojo → magenta, con un
 *  rosa claro en el máximo (el núcleo de la referencia). Se interpola en RGB entre estas anclas (densidad 0 a 1). */
export const ANCLAS_CALOR: [number, [number, number, number]][] = [
  [0.0, [66, 110, 235]], [0.15, [60, 215, 240]], [0.32, [70, 225, 120]], [0.48, [250, 236, 60]], [0.64, [250, 150, 40]], [0.78, [235, 60, 50]], [0.9, [215, 40, 170]], [1.0, [248, 196, 230]],
];
/** Opacidad por densidad: 0 en densidad 0 (donde no hay datos no se pinta), sube deprisa hasta ~0,55 en los primeros pasos y llega a 1 en 0,30; la opacidad general (0,78) hace el resto. */
const alfaCalor = (d: number) => (d <= 0.01 ? 0 : d >= 0.3 ? 1 : d < 0.06 ? ((d - 0.01) / 0.05) * 0.55 : 0.55 + ((d - 0.06) / 0.24) * 0.45);
export function colorCalor(d: number): [number, number, number, number] {
  const a = ANCLAS_CALOR;
  let k = 0;
  while (k < a.length - 2 && d > a[k + 1][0]) k++;
  const t = Math.max(0, Math.min(1, (d - a[k][0]) / (a[k + 1][0] - a[k][0])));
  const rgb = a[k][1].map((v, j) => Math.round(v + (a[k + 1][1][j] - v) * t)) as [number, number, number];
  return [...rgb, Math.round(alfaCalor(d) * 1000) / 1000];
}
/** 33 pasos (densidad 0 a 1) para heatmap-color: transparente en 0 y degradé continuo sin saltos visibles. */
export const COLORES_CALOR: (number | string)[] = Array.from({ length: 33 }, (_, i) => i / 32).flatMap((d) => {
  const [r, g, b, al] = colorCalor(d);
  return [d, `rgba(${r},${g},${b},${al})`];
});
/** Mismo degradé sin transparencia, para la leyenda. */
export const DEGRADE_CALOR_CSS = `linear-gradient(to right, ${ANCLAS_CALOR.map(([d, c]) => `rgb(${c.join(",")}) ${Math.round(d * 100)}%`).join(", ")})`;

/** Radio de la mancha: 2,75 veces el lado de la celda activa (rango pedido: 2,5 a 3). Con menos de ~2 lados se empieza a insinuar la malla. */
export const FACTOR_RADIO_CALOR = 2.75;
export const radioCalorMetros = (lado: number) => FACTOR_RADIO_CALOR * lado;
/** Metros por píxel en el zoom 0 a la latitud de Valledupar. MapLibre GL dibuja con teselas de 512 px (el mundo mide 512 × 2^zoom px), así que la constante es
 *  156543,03 / 2 × cos(10,47°); 156543,03 corresponde a teselas de 256 px. */
export const LATITUD_CALOR = 10.47;
export const METROS_POR_PIXEL_Z0 = (156543.03 / 2) * Math.cos((LATITUD_CALOR * Math.PI) / 180);
export const metrosPorPixel = (zoom: number) => METROS_POR_PIXEL_Z0 / 2 ** zoom;
/** heatmap-radius en píxeles como expresión interpolate exponencial base 2 sobre el zoom: píxeles = metros / (metros por píxel), así la mancha mantiene su tamaño
 *  geográfico al acercarte o alejarte. La interpolación exponencial de base 2 entre dos zooms reproduce exactamente c · 2^zoom. Por encima del zoom 16 (máximo del encuadre) el radio se queda en píxeles. */
export function radioCalor(lado: number): unknown[] {
  const m = radioCalorMetros(lado);
  const stops = [8, 10, 12, 14, 16].flatMap((z) => [z, Math.max(0.5, m / metrosPorPixel(z))]);
  return ["interpolate", ["exponential", 2], ["zoom"], ...stops];
}
/** Intensidad BASE: con el radio en metros la geometría del calor no cambia con el zoom, así que se normaliza una vez con los datos: la densidad máxima esperada
 *  (suma de los núcleos gaussianos de MapLibre, peso · intensidad · 0,3989 · exp(−4,5 · (d/R)²), de las celdas vecinas) se lleva a ≈ 0,95 para que llegue al color más alto sin saturar ni apagarse. */
/** Coeficiente del núcleo gaussiano del heatmap de MapLibre: 1 / raíz(2π). */
const GAUSS_COEF = 1 / Math.sqrt(2 * Math.PI);
export function intensidadBaseCalor(celdas: { cx: number; cy: number; peso: number }[], lado: number): number {
  if (!celdas.length) return 1;
  const mapa = new Map<string, number>();
  for (const c of celdas) mapa.set(`${c.cx},${c.cy}`, c.peso);
  const R = radioCalorMetros(lado), k = Math.ceil(R / lado);
  let maximo = 0;
  for (const c of celdas) {
    let suma = 0;
    for (let dx = -k; dx <= k; dx++) for (let dy = -k; dy <= k; dy++) {
      const w = mapa.get(`${c.cx + dx},${c.cy + dy}`);
      if (w == null) continue;
      const d = lado * Math.hypot(dx, dy);
      if (d <= R) suma += w * Math.exp(-4.5 * (d / R) ** 2);
    }
    maximo = Math.max(maximo, suma);
  }
  return maximo > 0 ? 0.95 / (GAUSS_COEF * maximo) : 1;
}
/** Intensidad por zoom: la base, con un refuerzo suave al alejarse (por debajo del zoom 11 la mancha mide pocos píxeles y se apaga). */
export const intensidadCalor = (base: number): unknown[] => ["interpolate", ["linear"], ["zoom"], 8, base * 1.5, 11, base * 1.15, 13, base];

export type CapasMapa = { celdas: boolean; calor: boolean };
/** Capas efectivas: la participación (un porcentaje) solo existe como celdas; fuerza Celdas y apaga Calor suave. */
export function capasEfectivas(c: CapasMapa, medida: Medida): CapasMapa {
  return medida === "part60" ? { celdas: true, calor: false } : c;
}
