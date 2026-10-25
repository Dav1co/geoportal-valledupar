// Escritor MÍNIMO de libros Excel (.xlsx) sin dependencias, para la descarga del Dashboard. Se carga BAJO DEMANDA (import dinámico) al pulsar «Descargar Excel».
// Qué escribe: una hoja de datos con celdas NUMÉRICAS y de FECHA reales, fila de títulos en negrita con filtro y panel inmovilizado, y una segunda hoja de texto («Léame»).
// Cómo: cada hoja es XML; el libro es un ZIP (CRC-32 propio). La hoja grande se comprime en flujo con CompressionStream («deflate-raw») para no tener 50.000 filas
// de XML en memoria; si el navegador no lo tiene, se guarda sin comprimir (el archivo pesa más pero abre igual).

export type Celda = string | number | null | { fecha: number } | { hora: number } | { fechaHora: number };

const ENC = new TextEncoder();
const XML_CABECERA = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

// ---------- utilidades ----------
const TABLA_CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(datos: Uint8Array, previo = 0): number {
  let c = ~previo >>> 0;
  for (let i = 0; i < datos.length; i++) c = TABLA_CRC[(c ^ datos[i]) & 0xff] ^ (c >>> 8);
  return ~c >>> 0;
}
/** Quita los caracteres que XML 1.0 no admite y escapa lo demás. */
const esc = (s: string) => s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
function nombreColumna(i: number): string { let s = ""; for (let n = i + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s; return s; }

// Estilos: 0 normal · 1 negrita · 2 fecha · 3 hora · 4 fecha y hora · 5 texto que ajusta línea
const ESTILO_FECHA = 2, ESTILO_HORA = 3, ESTILO_FECHAHORA = 4;
const STYLES = XML_CABECERA + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
  + '<numFmts count="3"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="hh:mm"/><numFmt numFmtId="166" formatCode="dd/mm/yyyy\\ hh:mm"/></numFmts>'
  + '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
  + '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
  + '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
  + '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
  + '<cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
  + '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
  + '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
  + '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
  + '<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
  + '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>'
  + '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
const NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
const CONTENT_TYPES = XML_CABECERA + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
  + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
  + '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
  + '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
  + '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>';
const RELS = XML_CABECERA + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
const WB_RELS = XML_CABECERA + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
  + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
  + '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';

function celdaXml(ref: string, c: Celda, estilo = 0): string {
  if (c === null || c === undefined || c === "") return "";
  if (typeof c === "number") return Number.isFinite(c) ? `<c r="${ref}"${estilo ? ` s="${estilo}"` : ""}><v>${c}</v></c>` : "";
  if (typeof c === "string") return `<c r="${ref}"${estilo ? ` s="${estilo}"` : ""} t="inlineStr"><is><t xml:space="preserve">${esc(c)}</t></is></c>`;
  if ("fecha" in c) return `<c r="${ref}" s="${ESTILO_FECHA}"><v>${c.fecha}</v></c>`;
  if ("hora" in c) return `<c r="${ref}" s="${ESTILO_HORA}"><v>${c.hora}</v></c>`;
  return `<c r="${ref}" s="${ESTILO_FECHAHORA}"><v>${c.fechaHora}</v></c>`;
}

/** Número de serie de Excel para una fecha «AAAA-MM-DD» (y, opcionalmente, «HH:MM[:SS]»). Hora de pared de Bogotá: Excel no maneja zona horaria. */
export function serialExcel(fecha: string, hora?: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(fecha); if (!m) return null;
  const dias = Date.UTC(+m[1], +m[2] - 1, +m[3]) / 86400000 + 25569;
  const h = hora ? /^(\d{2}):(\d{2})(?::(\d{2}))?/.exec(hora) : null;
  return h ? dias + (+h[1] * 3600 + +h[2] * 60 + (h[3] ? +h[3] : 0)) / 86400 : dias;
}
export const serialHora = (hhmm: string): number | null => { const h = /^(\d{2}):(\d{2})/.exec(hhmm); return h ? (+h[1] * 60 + +h[2]) / 1440 : null; };

type Entrada = { nombre: string; datos: Uint8Array; crc: number; usize: number; comprimido: boolean };

export class LibroXlsx {
  private n = 0;                                    // filas de datos escritas
  private crc = 0; private usize = 0;
  private escritor: WritableStreamDefaultWriter<Uint8Array> | null = null;
  private lectura: Promise<Uint8Array[]> | null = null;
  private crudo: Uint8Array[] = [];                 // si no hay CompressionStream
  private listo: Promise<void>;
  constructor(private o: { hoja: string; encabezados: string[]; anchos: number[]; leame: string[][] }) {
    const cols = o.anchos.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("");
    const cabecera = XML_CABECERA + `<worksheet ${NS}><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>`
      + `<sheetFormatPr defaultRowHeight="15"/><cols>${cols}</cols><sheetData>`
      + `<row r="1">${o.encabezados.map((t, i) => celdaXml(`${nombreColumna(i)}1`, t, 1)).join("")}</row>`;
    if (typeof CompressionStream !== "undefined") {
      const cs = new CompressionStream("deflate-raw");
      this.escritor = cs.writable.getWriter() as WritableStreamDefaultWriter<Uint8Array>;
      const lector = cs.readable.getReader();
      this.lectura = (async () => { const partes: Uint8Array[] = []; for (;;) { const { done, value } = await lector.read(); if (done) break; partes.push(value); } return partes; })();
    }
    this.listo = this.escribir(cabecera);
  }
  private async escribir(texto: string) {
    const b = ENC.encode(texto); this.crc = crc32(b, this.crc); this.usize += b.length;
    if (this.escritor) await this.escritor.write(b); else this.crudo.push(b);
  }
  /** Agrega filas de datos (las columnas del mismo orden que los encabezados). */
  async agregarFilas(filas: Celda[][]) {
    await this.listo;
    let xml = "";
    for (const f of filas) {
      this.n++; const r = this.n + 1;
      xml += `<row r="${r}">` + f.map((c, i) => celdaXml(`${nombreColumna(i)}${r}`, c)).join("") + "</row>";
    }
    this.listo = this.escribir(xml); await this.listo;
  }
  get filas() { return this.n; }
  async finalizar(): Promise<Blob> {
    await this.listo;
    const ultima = `${nombreColumna(this.o.encabezados.length - 1)}${this.n + 1}`;
    await this.escribir(`</sheetData><autoFilter ref="A1:${ultima}"/></worksheet>`);
    let datos1: Uint8Array; let comprimido = false;
    if (this.escritor && this.lectura) {
      await this.escritor.close(); const partes = await this.lectura; comprimido = true;
      datos1 = new Uint8Array(partes.reduce((a, p) => a + p.length, 0)); let o = 0; for (const p of partes) { datos1.set(p, o); o += p.length; }
    } else { datos1 = new Uint8Array(this.crudo.reduce((a, p) => a + p.length, 0)); let o = 0; for (const p of this.crudo) { datos1.set(p, o); o += p.length; } }
    const leame = XML_CABECERA + `<worksheet ${NS}><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="34" customWidth="1"/><col min="2" max="2" width="90" customWidth="1"/></cols><sheetData>`
      + this.o.leame.map((fila, i) => `<row r="${i + 1}">` + fila.map((t, j) => celdaXml(`${nombreColumna(j)}${i + 1}`, t, j === 0 ? 1 : 5)).join("") + "</row>").join("") + "</sheetData></worksheet>";
    const workbook = XML_CABECERA + `<workbook ${NS} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${esc(this.o.hoja)}" sheetId="1" r:id="rId1"/><sheet name="Léame" sheetId="2" r:id="rId2"/></sheets></workbook>`;
    const peq = (nombre: string, texto: string): Entrada => { const d = ENC.encode(texto); return { nombre, datos: d, crc: crc32(d), usize: d.length, comprimido: false }; };
    return zip([peq("[Content_Types].xml", CONTENT_TYPES), peq("_rels/.rels", RELS), peq("xl/workbook.xml", workbook), peq("xl/_rels/workbook.xml.rels", WB_RELS),
      peq("xl/styles.xml", STYLES), { nombre: "xl/worksheets/sheet1.xml", datos: datos1, crc: this.crc, usize: this.usize, comprimido }, peq("xl/worksheets/sheet2.xml", leame)]);
  }
}

function zip(entradas: Entrada[]): Blob {
  const partes: BlobPart[] = []; const central: Uint8Array[] = []; let pos = 0;
  for (const e of entradas) {
    const nombre = ENC.encode(e.nombre); const metodo = e.comprimido ? 8 : 0;
    const cab = new DataView(new ArrayBuffer(30));
    cab.setUint32(0, 0x04034b50, true); cab.setUint16(4, 20, true); cab.setUint16(6, 0x0800, true); cab.setUint16(8, metodo, true); cab.setUint16(10, 0, true); cab.setUint16(12, 0x0021, true);
    cab.setUint32(14, e.crc, true); cab.setUint32(18, e.datos.length, true); cab.setUint32(22, e.usize, true); cab.setUint16(26, nombre.length, true); cab.setUint16(28, 0, true);
    partes.push(cab.buffer, nombre as BlobPart, e.datos as BlobPart);
    const c = new DataView(new ArrayBuffer(46));
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true); c.setUint16(10, metodo, true); c.setUint16(12, 0, true); c.setUint16(14, 0x0021, true);
    c.setUint32(16, e.crc, true); c.setUint32(20, e.datos.length, true); c.setUint32(24, e.usize, true); c.setUint16(28, nombre.length, true);
    c.setUint16(30, 0, true); c.setUint16(32, 0, true); c.setUint16(34, 0, true); c.setUint16(36, 0, true); c.setUint32(38, 0, true); c.setUint32(42, pos, true);
    const bloque = new Uint8Array(46 + nombre.length); bloque.set(new Uint8Array(c.buffer), 0); bloque.set(nombre, 46); central.push(bloque);
    pos += 30 + nombre.length + e.datos.length;
  }
  const tamCentral = central.reduce((a, b) => a + b.length, 0);
  const fin = new DataView(new ArrayBuffer(22));
  fin.setUint32(0, 0x06054b50, true); fin.setUint16(8, entradas.length, true); fin.setUint16(10, entradas.length, true); fin.setUint32(12, tamCentral, true); fin.setUint32(16, pos, true);
  return new Blob([...partes, ...(central as BlobPart[]), fin.buffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
}
