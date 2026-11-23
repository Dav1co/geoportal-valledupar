// Genera libros de Excel (.xlsx) SINTÉTICOS para probar la carga del día del modo «Cartera» (Motor SCRR, corte 2). Ningún dato real: contratos 93xxxxxxxxxx,
// nombres «SUSCRIPTOR SINTÉTICO n», direcciones «CALLE n». Escribe como lo hace Excel (textos compartidos) o con textos en línea.
//   node scripts/scrr_generar_xlsx.mjs <tipo cartera|pagos|actividades> <filas> <salida.xlsx> [--en-linea] [--columna-extra] [--dos-hojas] [-h]
import { writeFileSync } from "node:fs";
import { deflateRawSync, crc32 as crcZlib } from "node:zlib";

const ayuda = "Uso: node scripts/scrr_generar_xlsx.mjs <cartera|pagos|actividades> <filas> <salida.xlsx> [--en-linea] [--columna-extra] [--dos-hojas]";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(ayuda); process.exit(0); }
const opciones = new Set(["--en-linea", "--columna-extra", "--dos-hojas"]);
for (const a of args.filter((x) => x.startsWith("-"))) if (!opciones.has(a)) { console.error(`Opción desconocida: ${a}\n${ayuda}`); process.exit(2); }
const [tipo, nTxt, salida] = args.filter((x) => !x.startsWith("-"));
if (!["cartera", "pagos", "actividades"].includes(tipo) || !/^\d+$/.test(nTxt ?? "") || !salida) { console.error(ayuda); process.exit(2); }
const N = Number(nTxt), EN_LINEA = args.includes("--en-linea"), EXTRA = args.includes("--columna-extra"), DOS = args.includes("--dos-hojas");

const crc32 = typeof crcZlib === "function" ? (b) => crcZlib(b) >>> 0 : (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return (b) => { let c = ~0 >>> 0; for (let i = 0; i < b.length; i++) c = t[(c ^ b[i]) & 0xff] ^ (c >>> 8); return ~c >>> 0; }; })();
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const col = (i) => { let s = ""; for (let n = i + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s; return s; };
const hoy = new Date(Date.now() - 5 * 3600e3);   // fecha de Bogotá (UTC−5)
const serial = (d) => Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) / 86400000) + 25569;
const S_HOY = serial(hoy);

const ENC = {
  cartera: ["Contrato", "Estado", "No. Identificación", "Nombre", "Correo Electrónico", "Teléfono", "Dirección", "Barrio", "Categoria", "Subcategoria", "Ciclo",
            "Facturas pendientes", "Facturas vencidas", "Deuda total", "Saldo Pendiente", "Saldo a favor", "Valor reclamo", "Saldo financiado", "Elemento medición", "Código reparto", "Ruta"],
  pagos: ["Contrato", "Fecha de pago", "Monto"],
  actividades: ["CONTRATO", "ACTA", "ACTIVIDAD", "DRASTICO", "ESTADO", "ANOMALIA", "OBSERVACION", "FECHA", "HORA INICIAL", "HORA FINAL", "LECTURA", "MEDIDOR", "MARCA", "OPERARIO"],
}[tipo];
const BARRIOS = Array.from({ length: 571 }, (_, i) => `BARRIO SINTÉTICO ${i + 1}`);
function fila(i) {
  const c = 930000000000 + i;
  if (tipo === "cartera") {
    const saldo = i % 2 ? 0 : 20000 + (i % 977) * 1000, venc = i % 2 ? 0 : (i % 30);
    return [c, "ACTIVO", 1000000 + i, `SUSCRIPTOR SINTÉTICO ${i}`, `s${i}@ejemplo.invalid`, "3000000000", `CALLE ${i % 400} # ${i % 90}-${i % 70}`, BARRIOS[i % 571],
            "1 - RESIDENCIAL", `${(i % 6) + 1} - ESTRATO ${(i % 6) + 1}`, String((i % 24) + 1).padStart(2, "0"), venc + 1, venc, saldo + 5000, saldo, 0, i % 97 === 0 ? 15000 : 0, 5000,
            `M${i}`, `R${i % 50}`, `RUTA ${i % 300}`];
  }
  if (tipo === "pagos") return [c, S_HOY - (i % 10), 10000 + (i % 500) * 100];
  return [c, `A${i}`, ["Suspensión", "Corte", "Reinstalación", "Reconexión", "Gestión de cobro"][i % 5], i % 10 === 1 ? "SÍ" : "NO", i % 4 ? 3 : 4, i % 4 ? "" : (i % 17) + 1,
          "SINTÉTICO", S_HOY - 1 - (i % 5), 0.3333, 0.35, 1000 + i, `M${i}`, "MARCA X", `OPERARIO ${i % 30}`];
}
const enc = EXTRA ? [...ENC, "Columna que sobra"] : ENC;
const compartidos = new Map(); const listaComp = [];
const textoCelda = (ref, v) => {
  if (EN_LINEA) return `<c r="${ref}" t="inlineStr"><is><t>${esc(v)}</t></is></c>`;
  let k = compartidos.get(v); if (k === undefined) { k = listaComp.length; compartidos.set(v, k); listaComp.push(v); }
  return `<c r="${ref}" t="s"><v>${k}</v></c>`;
};
function hoja(desde, hasta) {
  const partes = [`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`];
  partes.push(`<row r="1">${enc.map((h, j) => textoCelda(col(j) + "1", h)).join("")}</row>`);
  let r = 2;
  for (let i = desde; i <= hasta; i++, r++) {
    const f = EXTRA ? [...fila(i), "x"] : fila(i);
    partes.push(`<row r="${r}">` + f.map((v, j) => (v === "" ? "" : typeof v === "number" ? `<c r="${col(j)}${r}"><v>${v}</v></c>` : textoCelda(col(j) + r, v))).join("") + "</row>");
  }
  partes.push("</sheetData></worksheet>");
  return Buffer.from(partes.join(""), "utf8");
}
const mitad = DOS ? Math.ceil(N / 2) : N;
const hojas = [hoja(1, mitad)]; if (DOS) hojas.push(hoja(mitad + 1, N));
const ss = Buffer.from(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${listaComp.length}" uniqueCount="${listaComp.length}">`
  + listaComp.map((s) => `<si><t>${esc(s)}</t></si>`).join("") + "</sst>", "utf8");
const nombresHojas = DOS ? ["Hoja1", "Hoja2"] : ["Datos"];
const ent = [
  ["[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${hojas.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}${EN_LINEA ? "" : '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'}</Types>`],
  ["_rels/.rels", `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
  ["xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${nombresHojas.map((n, i) => `<sheet name="${n}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets></workbook>`],
  ["xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${hojas.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rIdS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>`],
  ...hojas.map((h, i) => [`xl/worksheets/sheet${i + 1}.xml`, h]),
  ...(EN_LINEA ? [] : [["xl/sharedStrings.xml", ss]]),
];
const partes = [], central = []; let pos = 0;
for (const [nombre, contenido] of ent) {
  const datos = Buffer.isBuffer(contenido) ? contenido : Buffer.from(contenido, "utf8"); const comp = deflateRawSync(datos, { level: 6 }); const nb = Buffer.from(nombre, "utf8");
  const l = Buffer.alloc(30); l.writeUInt32LE(0x04034b50, 0); l.writeUInt16LE(20, 4); l.writeUInt16LE(0x0800, 6); l.writeUInt16LE(8, 8); l.writeUInt32LE(crc32(datos), 14); l.writeUInt32LE(comp.length, 18); l.writeUInt32LE(datos.length, 22); l.writeUInt16LE(nb.length, 26);
  partes.push(l, nb, comp);
  const c = Buffer.alloc(46); c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x0800, 8); c.writeUInt16LE(8, 10); c.writeUInt32LE(crc32(datos), 16); c.writeUInt32LE(comp.length, 20); c.writeUInt32LE(datos.length, 24); c.writeUInt16LE(nb.length, 28); c.writeUInt32LE(pos, 42);
  central.push(c, nb); pos += 30 + nb.length + comp.length;
}
const tc = central.reduce((a, b) => a + b.length, 0); const fin = Buffer.alloc(22); fin.writeUInt32LE(0x06054b50, 0); fin.writeUInt16LE(ent.length, 8); fin.writeUInt16LE(ent.length, 10); fin.writeUInt32LE(tc, 12); fin.writeUInt32LE(pos, 16);
const todo = Buffer.concat([...partes, ...central, fin]); writeFileSync(salida, todo);
console.log(`${salida}: ${N.toLocaleString("es-CO")} filas de ${tipo}, ${(todo.length / 1048576).toFixed(1)} MB${EN_LINEA ? ", textos en línea" : ", textos compartidos"}${EXTRA ? ", con una columna de más" : ""}${DOS ? ", en dos hojas" : ""}`);
