// Cálculos PUROS (sin React) de «Edad de la cartera» sobre bi.v_cartera_edad_dim. Todo sale de la misma dimensión, así que las fichas, las
// tablas y las gráficas no pueden divergir entre sí. La lectura de los límites (superior o inferior) llega por parámetro y se resuelve en
// edadCartera.ts; aquí no hay rótulos de tramo escritos a mano.
import type { CarteraEdadDim } from "./tipos";
import { LECTURA_PROVISIONAL, tramosAnuales, type LecturaLimites } from "./edadCartera";

export const TODOS_EDAD = "todos";
export const OTROS = "Otros / sin clasificar";

/** Usos que ofrece el filtro: nombre en pantalla y código en la dimensión de edad. «Otros» agrupa los demás usos (2 industrial, -1…). */
export const USOS_FILTRO: { nombre: string; codigo: string }[] = [
  { nombre: "Residencial", codigo: "1" },
  { nombre: "Comercial", codigo: "3" },
  { nombre: "Oficial", codigo: "5" },
  { nombre: "Especial", codigo: "9" },
  { nombre: OTROS, codigo: "otros" },
];
export const ESTRATOS_FILTRO: { nombre: string; codigo: string }[] = [
  ...["1", "2", "3", "4", "5", "6"].map((e) => ({ nombre: `Estrato ${e}`, codigo: e })),
  { nombre: OTROS, codigo: "otros" },
];

const CODIGOS_USO = ["1", "3", "5", "9"];
const CODIGOS_ESTRATO = ["1", "2", "3", "4", "5", "6"];

export const codigoUsoDeNombre = (nombre: string): string | null =>
  USOS_FILTRO.find((u) => u.nombre === nombre)?.codigo ?? null;
export const codigoEstratoDeNombre = (nombre: string): string | null =>
  ESTRATOS_FILTRO.find((e) => e.nombre === nombre)?.codigo ?? null;

/** ¿El código de uso de v_cartera_detalle_dim ('1','2','3','5','9','-1') pertenece al uso elegido? «Otros» = cualquiera fuera de 1, 3, 5, 9. */
export function usoDetalleCoincide(codigoDetalle: string, nombre: string): boolean {
  if (nombre === TODOS_EDAD) return true;
  const c = codigoUsoDeNombre(nombre);
  return c === "otros" ? !CODIGOS_USO.includes(codigoDetalle) : c === codigoDetalle;
}
/** Igual para el estrato de v_cartera_detalle_dim ('1'..'8','-1'): «Otros» = fuera de 1 a 6. */
export function estratoDetalleCoincide(codigoDetalle: string, nombre: string): boolean {
  if (nombre === TODOS_EDAD) return true;
  const c = codigoEstratoDeNombre(nombre);
  return c === "otros" ? !CODIGOS_ESTRATO.includes(codigoDetalle) : c === codigoDetalle;
}

/** Filtra la dimensión de edad por uso y estrato (nombres de pantalla; «todos» no filtra). */
export function filtrarEdad(filas: CarteraEdadDim[], uso: string, estrato: string): CarteraEdadDim[] {
  const cu = uso === TODOS_EDAD ? null : codigoUsoDeNombre(uso);
  const ce = estrato === TODOS_EDAD ? null : codigoEstratoDeNombre(estrato);
  return filas.filter((f) => (cu == null || f.uso === cu) && (ce == null || f.estrato === ce));
}

export const sumar = (filas: { valor: number }[]) => filas.reduce((s, f) => s + f.valor, 0);

/** Valor por etiqueta cruda (las 19, aunque alguna valga 0). */
export function valorPorEtiqueta(filas: CarteraEdadDim[], etiquetas: readonly string[]): Record<string, number> {
  const m: Record<string, number> = Object.fromEntries(etiquetas.map((e) => [e, 0]));
  for (const f of filas) if (f.etiqueta in m) m[f.etiqueta] += f.valor;
  return m;
}

/** Colores de los tramos anuales: rampa de un tono para la edad (más oscuro = más viejo) y un tono aparte para la financiada. */
export const COLOR_TRAMO_EDAD: Record<string, string> = {
  hasta360: "#8FB4CE",
  t2: "#4FA3C7",
  t3: "#2E7D9E",
  t4: "#1A5F80",
  t5: "#12476A",
  mayor1800: "#0A2540",
  financiada: "#C98A2D",
};

export type TramoValor = { llave: string; rotulo: string; valor: number; pct: number | null; color: string };

/** Los tramos anuales (7) con su valor y su % del total, según la lectura de límites. */
export function tramosConValor(
  filas: CarteraEdadDim[],
  etiquetas: readonly string[],
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
): TramoValor[] {
  const porEt = valorPorEtiqueta(filas, etiquetas);
  const tramos = tramosAnuales(lectura).map((t) => ({
    llave: t.llave,
    rotulo: t.rotulo,
    valor: t.etiquetas.reduce((s, e) => s + (porEt[e] ?? 0), 0),
    color: COLOR_TRAMO_EDAD[t.llave],
  }));
  const total = tramos.reduce((s, t) => s + t.valor, 0);
  return tramos.map((t) => ({ ...t, pct: total ? (t.valor / total) * 100 : null }));
}

/** Los cuatro grupos principales de la evolución y de los cortes: hasta el primer año, tramos intermedios, el más viejo y financiada. */
export type GrupoEdad = { llave: string; rotulo: string; color: string; tramos: string[] };
export function gruposPrincipales(lectura: LecturaLimites = LECTURA_PROVISIONAL): GrupoEdad[] {
  const t = Object.fromEntries(tramosAnuales(lectura).map((x) => [x.llave, x.rotulo]));
  const sup = lectura === "superior";
  return [
    { llave: "mayor", rotulo: t.mayor1800, color: COLOR_TRAMO_EDAD.mayor1800, tramos: ["mayor1800"] },
    {
      llave: "medio",
      rotulo: sup ? "361 a 1.800 días" : "360 a 1.799 días",
      color: COLOR_TRAMO_EDAD.t3,
      tramos: ["t2", "t3", "t4", "t5"],
    },
    { llave: "hasta", rotulo: t.hasta360, color: COLOR_TRAMO_EDAD.hasta360, tramos: ["hasta360"] },
    { llave: "fin", rotulo: t.financiada, color: COLOR_TRAMO_EDAD.financiada, tramos: ["financiada"] },
  ];
}

export function valorGrupo(tramos: TramoValor[], g: GrupoEdad): number {
  return tramos.filter((t) => g.tramos.includes(t.llave)).reduce((s, t) => s + t.valor, 0);
}

/** Períodos presentes, ordenados, y el inmediatamente anterior a uno dado (null si es el primero). */
export const periodosDe = (filas: CarteraEdadDim[]) => [...new Set(filas.map((f) => f.periodo))].sort();
export function periodoAnterior(periodos: string[], periodo: string): string | null {
  const i = periodos.indexOf(periodo);
  return i > 0 ? periodos[i - 1] : null;
}

export type ResumenEdad = {
  total: number;
  noFinanciada: number;
  financiada: number;
  mayor360: number; // todo lo que supera el primer año según la lectura (excluye financiada)
  mayor1800: number;
  tramos: TramoValor[];
};

export function resumenPeriodo(
  filas: CarteraEdadDim[],
  periodo: string,
  etiquetas: readonly string[],
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
): ResumenEdad {
  const del = filas.filter((f) => f.periodo === periodo);
  const tramos = tramosConValor(del, etiquetas, lectura);
  const val = (k: string) => tramos.find((t) => t.llave === k)?.valor ?? 0;
  const total = tramos.reduce((s, t) => s + t.valor, 0);
  const financiada = val("financiada");
  return {
    total,
    financiada,
    noFinanciada: total - financiada,
    mayor360: ["t2", "t3", "t4", "t5", "mayor1800"].reduce((s, k) => s + val(k), 0),
    mayor1800: val("mayor1800"),
    tramos,
  };
}

/** Evolución: % del total de cada grupo principal en cada período. */
export function evolucionGrupos(
  filas: CarteraEdadDim[],
  periodos: string[],
  etiquetas: readonly string[],
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
) {
  const grupos = gruposPrincipales(lectura);
  const filasPorPeriodo = periodos.map((p) => {
    const r = resumenPeriodo(filas, p, etiquetas, lectura);
    return { periodo: p, total: r.total, valores: grupos.map((g) => valorGrupo(r.tramos, g)) };
  });
  return { grupos, filas: filasPorPeriodo };
}

export type CorteFila = { codigo: string; nombre: string; valor: number; pct: number | null; tramos: TramoValor[] };

/** Valor, participación y mezcla de tramos por uso o por estrato en un período (sobre las filas ya filtradas). */
export function cortePor(
  filas: CarteraEdadDim[],
  periodo: string,
  clave: "uso" | "estrato",
  etiquetas: readonly string[],
  lectura: LecturaLimites = LECTURA_PROVISIONAL,
): CorteFila[] {
  const del = filas.filter((f) => f.periodo === periodo);
  const catalogo = clave === "uso" ? USOS_FILTRO : ESTRATOS_FILTRO;
  const total = sumar(del);
  return catalogo
    .map((c) => {
      const sub = del.filter((f) => f[clave] === c.codigo);
      const tramos = tramosConValor(sub, etiquetas, lectura);
      const valor = sumar(sub);
      return { codigo: c.codigo, nombre: c.nombre, valor, pct: total ? (valor / total) * 100 : null, tramos };
    })
    .filter((c) => c.valor !== 0);
}

/** Matriz uso × estrato en pesos para un período. */
export function cruceUsoEstrato(filas: CarteraEdadDim[], periodo: string) {
  const del = filas.filter((f) => f.periodo === periodo);
  const usos = USOS_FILTRO.filter((u) => del.some((f) => f.uso === u.codigo));
  const estratos = ESTRATOS_FILTRO.filter((e) => del.some((f) => f.estrato === e.codigo));
  const celdas = usos.map((u) =>
    estratos.map((e) => sumar(del.filter((f) => f.uso === u.codigo && f.estrato === e.codigo))),
  );
  return { usos, estratos, celdas, total: sumar(del) };
}

/** $ 1.234,5 M — pesos en millones con UN decimal (las cifras de control de la pantalla se leen así). */
export function fmtMillonesUno(v: number | null): string {
  if (v == null) return "—";
  return `$ ${(v / 1e6).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} M`;
}

/** Variación en millones con signo: «+$ 1,2 M» / «−$ 1,2 M». */
export function fmtVariacionMillones(v: number | null): string {
  if (v == null) return "—";
  const m = Math.abs(v) / 1e6;
  return `${v < 0 ? "−" : "+"}$ ${m.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} M`;
}

/** Variación en puntos porcentuales con signo: «+0,3 pp». */
export function fmtPuntos(v: number | null): string {
  if (v == null) return "—";
  const r = Math.round(Math.abs(v) * 10) / 10;
  if (r === 0) return "0,0 pp";
  return `${v < 0 ? "−" : "+"}${r.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} pp`;
}
