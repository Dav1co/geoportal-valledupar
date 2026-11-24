// Reparto de facturas: lógica PURA (sin React, sin red, sin DOM). Se prueba sola en Node (scripts/prueba_reparto_logica.mjs).
import type { Contexto, Lista, Pendiente } from "./apiReparto";

/** Cuántas casillas grandes arriba y cuántas más bajando (decisión 3 del 23-nov: 10 y otros 10). */
export const CASILLAS = 10;

/** Lo que muestra la lista: el buscador filtra SOLO dentro de la ruta activa (por parte del código); sin búsqueda, los 10 siguientes y otros 10 bajando. */
export function dividir(pendientes: Pendiente[], busqueda: string): { arriba: Pendiente[]; abajo: Pendiente[]; encontrados: number } {
  const q = busqueda.replace(/\D/g, "");
  const l = q ? pendientes.filter((p) => p.c.includes(q)) : pendientes;
  return { arriba: l.slice(0, CASILLAS), abajo: l.slice(CASILLAS, CASILLAS * 2), encontrados: l.length };
}

/** Sin ruta: el código escrito es válido para registrar (solo números, de 1 a 12). */
export const codigoValido = (s: string): string | null => (/^\d{1,12}$/.test(s.trim()) ? s.trim() : null);

/** Quita de la lista el contrato recién entregado (antes de que llegue la lista nueva del servidor, para que «suba el siguiente» al instante). */
export function sinEntregada(l: Lista, contrato: string): Lista {
  return { ...l, pendientes: l.pendientes.filter((p) => p.c !== contrato), entregadas_mias: l.entregadas_mias + 1, siguiente: l.siguiente + 1 };
}

/** «Entregadas N de T» de la ruta: lo que ya no está pendiente (de quien sea), sobre el total. */
export const entregadasDeRuta = (l: Lista): number => Math.max(0, l.jornada.total - l.pendientes.length);

// ---------- Escoger la ruta: primero el ciclo, luego la ruta, con los dos orígenes (anterior y nueva) ----------
export type OpcionRuta =
  | { tipo: "anterior"; clave: string; ciclo: string; ruta: string; n: number; titulo: string; detalle: string }
  | { tipo: "nueva"; clave: string; ciclo: string; loteId: string; n: number; titulo: string; detalle: string };
export type CicloOpciones = { ciclo: string; opciones: OpcionRuta[]; reparto: { periodo: string; desde: string } | null };

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
export const textoPeriodo = (p: string | null | undefined): string => (p && /^\d{6}$/.test(p) ? `${MESES[Number(p.slice(4)) - 1]} de ${p.slice(0, 4)}` : "—");
export const textoFecha = (f: string | null | undefined): string => (f && /^\d{4}-\d{2}-\d{2}/.test(f) ? `${f.slice(8, 10)}/${f.slice(5, 7)}/${f.slice(0, 4)}` : "—");
export const textoHora = (iso: string | null | undefined): string => {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleTimeString("es-CO", { hour: "2-digit", minute: "2-digit", timeZone: "America/Bogota" });
};

export function ciclosParaEscoger(ctx: Pick<Contexto, "anterior" | "nuevas" | "periodo">): CicloOpciones[] {
  const m = new Map<string, CicloOpciones>();
  const dar = (ciclo: string, reparto: CicloOpciones["reparto"]) => {
    let c = m.get(ciclo);
    if (!c) { c = { ciclo, opciones: [], reparto }; m.set(ciclo, c); }
    if (!c.reparto && reparto) c.reparto = reparto;
    return c;
  };
  for (const c of ctx.anterior) {
    const x = dar(c.ciclo, c.reparto);
    for (const r of c.rutas) x.opciones.push({ tipo: "anterior", clave: `a:${c.ciclo}:${r.ruta}`, ciclo: c.ciclo, ruta: r.ruta, n: r.n,
      titulo: `Ruta ${r.ruta}`, detalle: `${r.n} facturas · ruta de lectura de ${textoPeriodo(ctx.periodo)}` });
  }
  for (const l of ctx.nuevas) {
    const x = dar(l.ciclo, l.reparto);
    x.opciones.unshift({ tipo: "nueva", clave: `n:${l.id}`, ciclo: l.ciclo, loteId: l.id, n: l.filas,
      titulo: l.tipo === "ruta" ? `Ruta ${l.ruta} (archivo nuevo)` : "Todo el ciclo (archivo nuevo)", detalle: `${l.filas} facturas · ${l.nombre_archivo}` });
  }
  return [...m.values()].sort((a, b) => Number(a.ciclo) - Number(b.ciclo));
}

// ---------- Sin señal: la lista y el toque pendiente se guardan en la sesión del navegador (no se pierden al recargar) ----------
export type ToquePendiente = { jornada_id: number; contrato: string; id_cliente: string; por_buscador: boolean; lon: number | null; lat: number | null; precision_m: number | null };
export type Almacen = { getItem(k: string): string | null; setItem(k: string, v: string): void; removeItem(k: string): void };
const CLAVE_LISTA = "reparto.lista", CLAVE_TOQUE = "reparto.toque";
export function guardarLista(a: Almacen, l: Lista | null) { try { if (l) a.setItem(CLAVE_LISTA, JSON.stringify(l)); else a.removeItem(CLAVE_LISTA); } catch { /* sin espacio: no pasa nada */ } }
export function leerLista(a: Almacen): Lista | null { try { const t = a.getItem(CLAVE_LISTA); return t ? (JSON.parse(t) as Lista) : null; } catch { return null; } }
export function guardarToque(a: Almacen, t: ToquePendiente | null) { try { if (t) a.setItem(CLAVE_TOQUE, JSON.stringify(t)); else a.removeItem(CLAVE_TOQUE); } catch { /* */ } }
export function leerToque(a: Almacen): ToquePendiente | null { try { const t = a.getItem(CLAVE_TOQUE); return t ? (JSON.parse(t) as ToquePendiente) : null; } catch { return null; } }

// ---------- Archivo de una ruta o de un ciclo (plantilla: Contrato y, opcional, Orden) ----------
export const ENCABEZADOS = ["Contrato", "Orden"] as const;
const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]+/g, " ").trim();
/** Contrato → solo dígitos (hasta 12) o null. «123.0» y «1.23E+5» (números de Excel) también. */
export function contratoDeCelda(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  let t = String(v).trim();
  if (/^\d+(\.\d+)?e\+\d+$/i.test(t)) { const n = Number(t); if (!Number.isSafeInteger(n)) return null; t = String(n); }
  t = t.replace(/\.0+$/, "");
  return /^\d{1,12}$/.test(t) ? t : null;
}
/** Filas crudas de la hoja (la primera con «Contrato» es el encabezado) → filas para el servidor, o los errores (hasta 20) con su fila de Excel. */
export function procesarArchivoRuta(filas: string[][], tope: number): { filas: { contrato: string | null; orden?: string }[]; errores: string[] } {
  const errores: string[] = [];
  let i = filas.findIndex((f) => f.some((c) => norm(c ?? "") === "CONTRATO"));
  if (i < 0) return { filas: [], errores: ["El archivo no tiene la columna «Contrato». Use la plantilla."] };
  const enc = filas[i].map((c) => norm(c ?? ""));
  const sobran = enc.filter((c) => c && c !== "CONTRATO" && c !== "ORDEN");
  if (sobran.length) return { filas: [], errores: [`El archivo trae columnas que no son de la plantilla: ${sobran.slice(0, 5).join(", ")}. La plantilla lleva solo Contrato y Orden.`] };
  const ic = enc.indexOf("CONTRATO"), io = enc.indexOf("ORDEN");
  const salida: { contrato: string | null; orden?: string }[] = [];
  const vistos = new Set<string>();
  for (let k = i + 1; k < filas.length; k++) {
    const f = filas[k];
    if (!f || f.every((c) => !String(c ?? "").trim())) continue;
    const fila = k + 1, crudo = String(f[ic] ?? "").trim(), c = contratoDeCelda(crudo);
    const orden = io >= 0 ? String(f[io] ?? "").trim().replace(/\.0+$/, "") : "";
    if (!c) errores.push(`Fila ${fila}: el contrato «${crudo.slice(0, 20)}» no es válido (solo números, de 1 a 12).`);
    else if (vistos.has(c)) errores.push(`Fila ${fila}: el contrato ${c} está repetido.`);
    else vistos.add(c);
    if (orden && !/^[1-9]\d{0,6}$/.test(orden)) errores.push(`Fila ${fila}: el Orden «${orden.slice(0, 12)}» no es un entero mayor que cero.`);
    salida.push({ contrato: c, ...(orden ? { orden } : {}) });
  }
  if (!salida.length) errores.push("El archivo no trae contratos debajo del encabezado.");
  if (salida.length > tope) errores.push(`El archivo trae ${salida.length} filas y el tope es ${tope}.`);
  const conOrden = salida.filter((x) => x.orden).length;
  if (conOrden && conOrden !== salida.length) errores.push("La columna Orden debe venir en todas las filas o en ninguna.");
  return { filas: salida, errores: errores.slice(0, 20) };
}

// ---------- Mapa en vivo ----------
/** Une los puntos que ya tiene la pantalla con los nuevos (por id) y marca las anuladas. */
export function unirPuntos<T extends { id: number; anulada: boolean }>(actuales: T[], nuevos: T[], anuladas: number[]): T[] {
  const m = new Map<number, T>(actuales.map((p) => [p.id, p]));
  for (const p of nuevos) m.set(p.id, p);
  const a = new Set(anuladas);
  return [...m.values()].map((p) => (a.has(p.id) && !p.anulada ? { ...p, anulada: true } : p));
}
/** Cada cuánto consulta el mapa en vivo (P2 de David, 24-nov: 10 s y solo con la pestaña visible). */
export const INTERVALO_MAPA_MS = 10000;
