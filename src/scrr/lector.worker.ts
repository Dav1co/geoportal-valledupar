// Web Worker de lectura de la carga del día (modo «Cartera»): lee el Excel (.xlsx) sin bloquear la pantalla, calcula su SHA-256, valida fila por fila contra la
// plantilla y guarda las filas ya normalizadas. La pantalla le pide después los lotes de a uno. Nada de esto toca la red: el envío lo hace la pantalla.
// Varias hojas: se leen todas las que tengan la columna «Contrato» con el encabezado de la plantilla; las que no la tienen (resúmenes, notas) se omiten y se dice.
import { leerXlsx, ErrorXlsx } from "./lectorXlsx";
import { Acumulador, mapearEncabezados, filaComoObjeto, normalizarEncabezado, sha256Hex, type TipoCarga, type Resumen } from "./lector";

type Entrante =
  | { op: "leer"; tipo: TipoCarga; archivo: File | Blob; nombre: string; comodin: string; tope: number }
  | { op: "lote"; n: number; tamano: number }
  | { op: "liberar" };
export type Saliente =
  | { op: "progreso"; pct: number; filas: number }
  | { op: "listo"; resumen: Resumen; sha256: string; nombre: string; bytes: number; msLectura: number; hojasOmitidas: string[] }
  | { op: "error"; mensaje: string }
  | { op: "lote"; n: number; filas: Record<string, string>[] };

const ctx = globalThis as unknown as { postMessage(m: Saliente): void; onmessage: ((e: MessageEvent<Entrante>) => void) | null };
let acc: Acumulador | null = null; let tipoActual: TipoCarga = "cartera";

export async function leerArchivo(bytes: Uint8Array, tipo: TipoCarga, comodin: string, tope: number, alAvance?: (pct: number, filas: number) => void) {
  let a: Acumulador | null = null; const omitidas: string[] = []; const usadas: string[] = [];
  const encabezadoDe = new Map<number, boolean>();   // hoja → ¿ya se leyó su encabezado y vale?
  let hojasNombres: string[] = [];
  const hojas = await leerXlsx(bytes, {
    alFila: (celdas, h) => {
      if (!encabezadoDe.has(h)) {
        if (celdas.every((c) => !c || !c.trim())) return;                          // filas vacías antes del encabezado
        const tieneContrato = celdas.some((c) => normalizarEncabezado(c ?? "") === "CONTRATO");
        if (!tieneContrato) { encabezadoDe.set(h, false); omitidas.push(String(h)); return; }
        const m = mapearEncabezados(tipo, celdas);
        if ("error" in m) throw new ErrorXlsx(m.error);
        if (a && JSON.stringify(a.mapeo.indices) !== JSON.stringify(m.indices)) throw new ErrorXlsx("Las hojas del libro no tienen las columnas en el mismo orden. Deje los datos en una sola hoja.");
        a ??= new Acumulador(tipo, m, comodin); encabezadoDe.set(h, true); usadas.push(String(h)); return;
      }
      if (!encabezadoDe.get(h)) return;
      a!.agregar(celdas);
      if (a!.filas.length > tope) throw new ErrorXlsx(`El archivo tiene más de ${tope.toLocaleString("es-CO")} filas.`);
    },
    alAvance: (b, total, h) => { if (alAvance && total) alAvance(Math.min(99, Math.round(((h + b / total) * 100) / Math.max(1, hojasNombres.length || 1))), a?.filas.length ?? 0); },
  });
  hojasNombres = hojas.map((x) => x.nombre);
  if (!a) throw new ErrorXlsx("Ninguna hoja del libro tiene la columna «Contrato» con el encabezado de la plantilla.");
  const fin = a as Acumulador;
  if (fin.filas.length === 0) throw new ErrorXlsx("El archivo no tiene filas de datos.");
  return { acumulador: fin, resumen: fin.resumen(usadas.map((i) => hojas[+i].nombre)), hojasOmitidas: omitidas.map((i) => hojas[+i].nombre) };
}

async function leer(m: Extract<Entrante, { op: "leer" }>) {
  acc = null; tipoActual = m.tipo; const t0 = performance.now();
  try {
    if (/\.(xls|csv)$/i.test(m.nombre)) throw new ErrorXlsx("Use un libro de Excel .xlsx con las columnas de la plantilla (descárguela en esta pantalla).");
    const bytes = new Uint8Array(await m.archivo.arrayBuffer());
    const sha = await sha256Hex(bytes);
    let ultimo = 0;
    const r = await leerArchivo(bytes, m.tipo, m.comodin, m.tope, (pct, filas) => { if (pct - ultimo >= 5) { ultimo = pct; ctx.postMessage({ op: "progreso", pct, filas }); } });
    acc = r.acumulador;
    ctx.postMessage({ op: "listo", resumen: r.resumen, sha256: sha, nombre: m.nombre, bytes: bytes.length, msLectura: Math.round(performance.now() - t0), hojasOmitidas: r.hojasOmitidas });
  } catch (e) {
    acc = null;
    ctx.postMessage({ op: "error", mensaje: e instanceof ErrorXlsx ? e.message : "No se pudo leer el archivo." });
  }
}

const enWorker = typeof (globalThis as unknown as { WorkerGlobalScope?: unknown }).WorkerGlobalScope !== "undefined";   // en Node (pruebas) no se engancha
if (enWorker) {
  ctx.onmessage = (ev) => {
    const m = ev.data;
    if (m.op === "leer") void leer(m);
    else if (m.op === "lote") {
      const filas = acc ? acc.filas.slice((m.n - 1) * m.tamano, m.n * m.tamano).map((v) => filaComoObjeto(tipoActual, v)) : [];
      ctx.postMessage({ op: "lote", n: m.n, filas });
    } else acc = null;
  };
}
