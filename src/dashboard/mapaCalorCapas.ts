// Piezas COMUNES de la capa «Calor suave» (heatmap de MapLibre) de los mapas de Cartera desagregada y de Pérdidas: pesos por percentil, paleta continua,
// radio en metros (2,75 veces el lado de la celda) e intensidad. Lógica PURA, sin React ni MapLibre. Cada mapa pone sus propias medidas y capas;
// aquí solo vive lo que no depende de la medida.

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
