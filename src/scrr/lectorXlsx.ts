// Lector MÍNIMO de libros Excel (.xlsx) sin dependencias (P5 del 22-nov: lector propio, sin librería nueva). Corre en el Web Worker del modo «Cartera» y en Node.
// Qué hace: lee el índice del ZIP, descomprime con DecompressionStream («deflate-raw»), carga los textos compartidos (sharedStrings) y recorre cada hoja EN FLUJO
// (por trozos de texto, fila por fila), entregando cada fila como una lista de textos. No interpreta estilos: las fechas llegan como número de serie de Excel y
// las convierte quien sabe qué columna es una fecha (lector.ts).
// Lo que no lee: .xls (formato binario viejo) ni libros con contraseña. Para eso el mensaje pide guardarlo como .xlsx o usar la plantilla.

export class ErrorXlsx extends Error { constructor(m: string) { super(m); this.name = "ErrorXlsx"; } }

type EntradaZip = { nombre: string; metodo: number; tamComprimido: number; tamReal: number; posLocal: number };
const DEC = new TextDecoder("utf-8");

function leerIndice(b: Uint8Array): Map<string, EntradaZip> {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let fin = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 66000); i--) if (dv.getUint32(i, true) === 0x06054b50) { fin = i; break; }
  if (fin < 0) {
    if (b.length >= 8 && dv.getUint32(0, false) === 0xd0cf11e0) throw new ErrorXlsx("Es un Excel viejo (.xls). Ábralo y guárdelo como «Libro de Excel (.xlsx)», o use la plantilla.");
    throw new ErrorXlsx("El archivo no es un libro de Excel (.xlsx) válido.");
  }
  const n = dv.getUint16(fin + 10, true); let p = dv.getUint32(fin + 16, true);
  const m = new Map<string, EntradaZip>();
  for (let k = 0; k < n; k++) {
    if (dv.getUint32(p, true) !== 0x02014b50) throw new ErrorXlsx("El índice del libro de Excel está dañado.");
    const flags = dv.getUint16(p + 8, true);
    const metodo = dv.getUint16(p + 10, true), tamComprimido = dv.getUint32(p + 20, true), tamReal = dv.getUint32(p + 24, true);
    const ln = dv.getUint16(p + 28, true), le = dv.getUint16(p + 30, true), lc = dv.getUint16(p + 32, true), posLocal = dv.getUint32(p + 42, true);
    if (flags & 1) throw new ErrorXlsx("El libro de Excel tiene contraseña. Quítela y vuelva a intentar.");
    const nombre = DEC.decode(b.subarray(p + 46, p + 46 + ln));
    m.set(nombre, { nombre, metodo, tamComprimido, tamReal, posLocal });
    p += 46 + ln + le + lc;
  }
  return m;
}

/** Devuelve el contenido de una entrada como flujo de bytes (descomprimido). */
function flujoEntrada(b: Uint8Array, e: EntradaZip): ReadableStream<Uint8Array> {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  if (dv.getUint32(e.posLocal, true) !== 0x04034b50) throw new ErrorXlsx("El libro de Excel está dañado.");
  const ini = e.posLocal + 30 + dv.getUint16(e.posLocal + 26, true) + dv.getUint16(e.posLocal + 28, true);
  const datos = b.subarray(ini, ini + e.tamComprimido);
  const crudo = new ReadableStream<Uint8Array>({ start(c) { const T = 1 << 20; for (let i = 0; i < datos.length; i += T) c.enqueue(datos.subarray(i, Math.min(datos.length, i + T))); c.close(); } });
  if (e.metodo === 0) return crudo;
  if (e.metodo !== 8) throw new ErrorXlsx("El libro de Excel usa una compresión que no se reconoce.");
  if (typeof DecompressionStream === "undefined") throw new ErrorXlsx("Este navegador no puede leer Excel. Actualice el navegador.");
  return crudo.pipeThrough(new DecompressionStream("deflate-raw") as unknown as TransformStream<Uint8Array, Uint8Array>);
}

/** Recorre el texto de una entrada en trozos; «alTrozo» recibe texto completo hasta la última etiqueta de cierre buscada y devuelve lo que sobra. */
async function recorrerTexto(flujo: ReadableStream<Uint8Array>, cierre: string, alTrozo: (t: string) => void): Promise<void> {
  const lector = flujo.getReader(); const dec = new TextDecoder("utf-8"); let resto = "";
  for (;;) {
    const { done, value } = await lector.read();
    if (done) break;
    resto += dec.decode(value, { stream: true });
    const k = resto.lastIndexOf(cierre);
    if (k >= 0) { alTrozo(resto.slice(0, k + cierre.length)); resto = resto.slice(k + cierre.length); }
  }
  resto += dec.decode();
  if (resto) alTrozo(resto);
}

const ENTIDADES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
export const desescapar = (s: string): string =>
  s.indexOf("&") < 0 ? s : s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/g, (_, e: string) =>
    e[0] === "#" ? String.fromCodePoint(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : ENTIDADES[e]);
/** Texto de un <si> o <is>: une los <t> (también los de formato enriquecido <r><t>), sin los de fonética <rPh>. */
function textoDe(xml: string): string {
  const sinFonetica = xml.indexOf("<rPh") >= 0 ? xml.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "") : xml;
  let s = ""; const re = /<t(?:\s[^>]*)?>([\s\S]*?)<\/t>|<t(?:\s[^>]*)?\/>/g; let m: RegExpExecArray | null;
  while ((m = re.exec(sinFonetica))) s += m[1] ?? "";
  return desescapar(s);
}
/** «AB12» → 27 (índice de columna desde 0). */
export function columnaDeRef(ref: string): number {
  let n = 0;
  for (let i = 0; i < ref.length; i++) { const c = ref.charCodeAt(i); if (c < 65 || c > 90) break; n = n * 26 + (c - 64); }
  return n - 1;
}

export type HojaInfo = { nombre: string; ruta: string };
export type OpcionesLectura = { alFila: (celdas: string[], hoja: number, fila: number) => void; alAvance?: (bytesHoja: number, totalHoja: number, hoja: number) => void };

/** Lee todas las hojas del libro, en el orden del libro. Devuelve los nombres de las hojas. */
export async function leerXlsx(bytes: Uint8Array, o: OpcionesLectura): Promise<HojaInfo[]> {
  const indice = leerIndice(bytes);
  const texto = async (nombre: string): Promise<string | null> => {
    const e = indice.get(nombre); if (!e) return null;
    let s = ""; await recorrerTexto(flujoEntrada(bytes, e), ">", (t) => { s += t; }); return s;
  };
  const wb = await texto("xl/workbook.xml");
  if (wb === null) throw new ErrorXlsx("El archivo no es un libro de Excel (.xlsx) válido.");
  const rels = (await texto("xl/_rels/workbook.xml.rels")) ?? "";
  const destino = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) {
    const id = /\bId="([^"]+)"/.exec(m[0])?.[1], t = /\bTarget="([^"]+)"/.exec(m[0])?.[1];
    if (id && t) destino.set(id, t.startsWith("/") ? t.slice(1) : "xl/" + t.replace(/^\.\//, ""));
  }
  const hojas: HojaInfo[] = [];
  for (const m of wb.matchAll(/<sheet\b[^>]*>/g)) {
    const nombre = desescapar(/\bname="([^"]*)"/.exec(m[0])?.[1] ?? ""), id = /\br:id="([^"]+)"/.exec(m[0])?.[1] ?? "";
    const ruta = destino.get(id); if (ruta && indice.has(ruta)) hojas.push({ nombre, ruta });
  }
  if (!hojas.length) throw new ErrorXlsx("El libro de Excel no tiene hojas.");
  // Textos compartidos
  const compartidos: string[] = [];
  const ss = indice.get("xl/sharedStrings.xml");
  if (ss) await recorrerTexto(flujoEntrada(bytes, ss), "</si>", (t) => { for (const m of t.matchAll(/<si>([\s\S]*?)<\/si>|<si\/>/g)) compartidos.push(m[1] === undefined ? "" : textoDe(m[1])); });
  // Hojas en flujo
  const reCelda = /<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
  for (let h = 0; h < hojas.length; h++) {
    const e = indice.get(hojas[h].ruta)!; let leidos = 0; let nFila = 0;
    const flujo = flujoEntrada(bytes, e).pipeThrough(new TransformStream<Uint8Array, Uint8Array>({ transform(c, ctl) { leidos += c.length; o.alAvance?.(leidos, e.tamReal, h); ctl.enqueue(c); } }));
    await recorrerTexto(flujo, "</row>", (t) => {
      let i = 0;
      for (;;) {
        const a = t.indexOf("<row", i); if (a < 0) break;
        const fa = t.indexOf(">", a); if (fa < 0) break;
        if (t[fa - 1] === "/") { i = fa + 1; nFila++; continue; }           // <row …/> vacía
        const b = t.indexOf("</row>", fa); if (b < 0) break;
        const cuerpo = t.slice(fa + 1, b); i = b + 6; nFila++;
        const celdas: string[] = []; let pos = 0; reCelda.lastIndex = 0; let m: RegExpExecArray | null;
        while ((m = reCelda.exec(cuerpo))) {
          const atr = m[1], dentro = m[2] ?? "";
          const ref = /\br="([A-Z]+)\d*"/.exec(atr)?.[1]; const col = ref ? columnaDeRef(ref) : pos;
          const tipo = /\bt="([a-zA-Z]+)"/.exec(atr)?.[1] ?? "n";
          let v = "";
          if (tipo === "inlineStr") v = textoDe(/<is>([\s\S]*?)<\/is>/.exec(dentro)?.[1] ?? "");
          else {
            const crudo = /<v>([\s\S]*?)<\/v>/.exec(dentro)?.[1];
            if (crudo !== undefined) v = tipo === "s" ? (compartidos[Number(crudo)] ?? "") : tipo === "b" ? (crudo === "1" ? "VERDADERO" : "FALSO") : desescapar(crudo);
          }
          while (celdas.length < col) celdas.push("");
          celdas[col] = v; pos = col + 1;
        }
        o.alFila(celdas, h, nFila);
      }
    });
  }
  return hojas;
}
