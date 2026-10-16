import { useEffect, useState } from "react";
import { biCache } from "./cacheBi";
import type { ReclamoMetodoBandaDim, ReclamoMetodoCicloDim } from "./tipos";

// Lógica común de «Reclamos según el método de facturación» (PQR y resumen de Pérdidas).
// Una sola definición de trayectorias, grupos, tasas y la fórmula de «solicitudes por encima de la tasa de lectura estable».

export const MIN_CONTRATOS_MES = 5;       // por debajo: celda «—»
export const MUESTRA_PEQUENA = 5000;      // por debajo: «muestra pequeña»
export const SIN_BASE = "Sin base";
export const POR_MIL = 1000;
export const AVISO_ASOCIACION = "Los resultados muestran asociación, no causalidad.";
export const FUENTE_A = "bi.v_reclamo_metodo_banda_dim (hechos.consumo_metodo y hechos.reclamos)";
export const FUENTE_B = "bi.v_reclamo_metodo_ciclo_dim (hechos.consumo_metodo y hechos.reclamos)";

export const METODOS = ["lectura", "promedio", "promedio_sin_medidor", "modificacion_directa", "otro"] as const;
export const ETIQ_METODO: Record<string, string> = {
  lectura: "Lectura",
  promedio: "Promedio con medidor",
  promedio_sin_medidor: "Promedio sin medidor",
  modificacion_directa: "Modificación directa",
  otro: "Otro",
  sin_dato: "Sin dato",
  [SIN_BASE]: SIN_BASE,
};
export const etiquetaMetodo = (m: string) => ETIQ_METODO[m] ?? m;

export const TRAYECTORIAS = [
  "Estable en lectura",
  "Estable en promedio con medidor",
  "Estable en promedio sin medidor",
  "Lectura → promedio",
  "Promedio → lectura",
  "Modificación directa (cualquier sentido)",
  "Otras",
] as const;
export type Trayectoria = (typeof TRAYECTORIAS)[number];
export const T_LECTURA: Trayectoria = TRAYECTORIAS[0];
export const T_MODIF: Trayectoria = TRAYECTORIAS[5];

// Trayectoria de una fila de A. La modificación directa pesa más que el resto: en cualquier sentido.
export function trayectoriaDe(ant: string, act: string): Trayectoria {
  if (ant === "modificacion_directa" || act === "modificacion_directa") return T_MODIF;
  if (ant === "lectura" && act === "lectura") return T_LECTURA;
  if (ant === "promedio" && act === "promedio") return TRAYECTORIAS[1];
  if (ant === "promedio_sin_medidor" && act === "promedio_sin_medidor") return TRAYECTORIAS[2];
  if (ant === "lectura" && act === "promedio") return TRAYECTORIAS[3];
  if (ant === "promedio" && act === "lectura") return TRAYECTORIAS[4];
  return "Otras";
}

// Grupos de causal en el orden de las barras apiladas.
export const GRUPOS = [
  { id: "consumo", nombre: "Consumo", color: "#0A2540" },
  { id: "promedio", nombre: "Promedio", color: "#0E7C86" },
  { id: "medidor", nombre: "Medidor", color: "#C98A2D" },
  { id: "desocupado", nombre: "Desocupado", color: "#8FB4CE" },
  { id: "cartera", nombre: "Cartera", color: "#7B5EA7" },
  { id: "admin", nombre: "Administrativas", color: "#C0392B" },
  { id: "resto", nombre: "Resto", color: "#9AA7B5" },
] as const;

export type Suma = {
  contratos: number; consumo: number; promedio: number; medidor: number; otras: number;
  desocupado: number; cartera: number; admin: number; resto: number;
  conReclamo: number; conRecConsProm: number;
};
export const sumaVacia = (): Suma => ({
  contratos: 0, consumo: 0, promedio: 0, medidor: 0, otras: 0, desocupado: 0, cartera: 0, admin: 0, resto: 0,
  conReclamo: 0, conRecConsProm: 0,
});
type FilaSuma = {
  contratos: number; solicitudes_consumo: number; solicitudes_promedio: number; solicitudes_medidor: number;
  solicitudes_otras: number; solicitudes_desocupado: number; solicitudes_cartera: number; solicitudes_admin: number;
  contratos_con_reclamo: number; contratos_con_rec_consumo_prom: number;
};
export function acumular(s: Suma, x: FilaSuma) {
  s.contratos += x.contratos;
  s.consumo += x.solicitudes_consumo;
  s.promedio += x.solicitudes_promedio;
  s.medidor += x.solicitudes_medidor;
  s.otras += x.solicitudes_otras;
  s.desocupado += x.solicitudes_desocupado;
  s.cartera += x.solicitudes_cartera;
  s.admin += x.solicitudes_admin;
  s.resto += Math.max(0, x.solicitudes_otras - x.solicitudes_desocupado - x.solicitudes_cartera - x.solicitudes_admin);
  s.conReclamo += x.contratos_con_reclamo;
  s.conRecConsProm += x.contratos_con_rec_consumo_prom;
  return s;
}
export const solicitudesTotal = (s: Suma) => s.consumo + s.promedio + s.medidor + s.otras;
export const solicitudesCP = (s: Suma) => s.consumo + s.promedio;
export const porMil = (sol: number, contratos: number): number | null =>
  contratos >= MIN_CONTRATOS_MES ? (sol * POR_MIL) / contratos : null;
export const tasaTotal = (s: Suma) => porMil(solicitudesTotal(s), s.contratos);
export const tasaCP = (s: Suma) => porMil(solicitudesCP(s), s.contratos);

export function agrupar<T>(filas: T[], clave: (x: T) => string, suma: (x: T) => FilaSuma): Map<string, Suma> {
  const m = new Map<string, Suma>();
  for (const x of filas) {
    const k = clave(x);
    let s = m.get(k);
    if (!s) { s = sumaVacia(); m.set(k, s); }
    acumular(s, suma(x));
  }
  return m;
}

// Estrato mostrado: «ESTRATO 3» → «Estrato 3»; en los usos no residenciales trae diámetros u otros códigos → «Otros usos».
export const OTROS_USOS = "Otros usos";
export function estratoMostrado(estrato: string, uso: string): string {
  if (uso === SIN_BASE) return SIN_BASE;
  const m = /^ESTRATO\s+(\d)/i.exec(estrato);
  return m ? `Estrato ${m[1]}` : OTROS_USOS;
}

export const BANDAS = ["0-3", "3-5", "5-10", "10-15", ">15 (fecha real)", ">15 (1986-01-01)", "Sin fecha"];

// Referencia: tasa de consumo + promedio de «estable en lectura» y solicitudes por encima de ella, trayectoria a trayectoria.
export type Exceso = { traj: Trayectoria; contratos: number; solicitudes: number; esperadas: number; encima: number };
export function sobreLecturaEstable(porTray: Map<string, Suma>): { filas: Exceso[]; sinMod: number; conMod: number; tasaRef: number | null } {
  const ref = porTray.get(T_LECTURA);
  const tasaRef = ref && ref.contratos > 0 ? solicitudesCP(ref) / ref.contratos : null;
  const filas: Exceso[] = [];
  for (const t of TRAYECTORIAS) {
    if (t === T_LECTURA) continue;
    const s = porTray.get(t) ?? sumaVacia();
    const esperadas = tasaRef == null ? 0 : s.contratos * tasaRef;
    filas.push({ traj: t, contratos: s.contratos, solicitudes: solicitudesCP(s), esperadas, encima: solicitudesCP(s) - esperadas });
  }
  const conMod = filas.reduce((a, f) => a + f.encima, 0);
  const sinMod = filas.filter((f) => f.traj !== T_MODIF).reduce((a, f) => a + f.encima, 0);
  return { filas, sinMod, conMod, tasaRef };
}

// ---------- carga sin filtro (todos los períodos), guardada en biCache, con error y reintento ----------
export type Estado<T> = { datos: T[] | null; error: string | null; recargar: () => void };
export function useVistaBi<T>(vista: string, convertir: (r: Record<string, unknown>) => T): Estado<T> {
  const [datos, setDatos] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    let vivo = true;
    setDatos(null);
    setError(null);
    biCache(vista)
      .then((r) => { if (vivo) setDatos((r.datos ?? []).map(convertir)); })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, intento]);
  return { datos, error, recargar: () => setIntento((i) => i + 1) };
}

export const fechaCalculo = (xs: { calculado_en: string }[]) => {
  const f = xs.map((x) => x.calculado_en).filter(Boolean).sort().pop();
  return f ? new Date(f).toLocaleString("es-CO") : "—";
};

// Resumen por trayectoria de A ya filtrado (períodos/estrato/uso aplicados por quien llama).
// La fila «Sin base» (reclamos de contratos fuera de consumo_metodo, sin contratos-mes) no tiene trayectoria.
export function porTrayectoria(filas: ReclamoMetodoBandaDim[]): Map<string, Suma> {
  return agrupar(filas.filter((x) => x.uso !== SIN_BASE), (x) => trayectoriaDe(x.metodo_ant, x.metodo_act), (x) => x);
}
export type { ReclamoMetodoBandaDim, ReclamoMetodoCicloDim };
