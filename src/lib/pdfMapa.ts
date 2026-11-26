// Geovisor técnico · Corte 1 (26-nov): PDF de mapas, escritor PROPIO sin librerías (el mismo enfoque de src/aseo/pdf.ts, que no se toca: de allí solo se
// reutiliza la lectura del encabezado JPEG). Cada página es una hoja carta vertical (612 × 792 pt) con UNA imagen JPEG a página completa (el mapa con su
// plantilla, ya compuesto en el navegador). El JPEG va tal cual (DCTDecode), sin recodificar. Sin datos personales: solo lo que se ve en el mapa.
import { infoJpeg } from "../aseo/pdf";

export const HOJA_CARTA = { ancho: 612, alto: 792 };      // puntos (1/72 de pulgada)

const bytesDe = (s: string): Uint8Array => Uint8Array.from(s.split("").map((c) => c.charCodeAt(0) & 255));

/** Arma el PDF con una página por imagen (cada una ocupa la hoja completa). */
export function pdfDeImagenes(paginas: Uint8Array[], titulo: string): Uint8Array {
  const objetos: Uint8Array[][] = [];
  const nuevo = () => { objetos.push([]); return objetos.length; };
  const poner = (n: number, ...partes: (string | Uint8Array)[]) => { objetos[n - 1] = partes.map((p) => (typeof p === "string" ? bytesDe(p) : p)); };
  const raiz = nuevo(), arbol = nuevo(), info = nuevo();
  const hojas: number[] = [];
  for (const jpg of paginas) {
    const i = infoJpeg(jpg);
    const img = nuevo(), cont = nuevo(), hoja = nuevo();
    const cs = i.componentes === 1 ? "/DeviceGray" : i.componentes === 4 ? "/DeviceCMYK" : "/DeviceRGB";
    poner(img, `<< /Type /XObject /Subtype /Image /Width ${i.ancho} /Height ${i.alto} /ColorSpace ${cs} /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpg.length} >>\nstream\n`, jpg, "\nendstream");
    const dibujo = `q ${HOJA_CARTA.ancho} 0 0 ${HOJA_CARTA.alto} 0 0 cm /Im0 Do Q`;
    poner(cont, `<< /Length ${dibujo.length} >>\nstream\n${dibujo}\nendstream`);
    poner(hoja, `<< /Type /Page /Parent ${arbol} 0 R /MediaBox [0 0 ${HOJA_CARTA.ancho} ${HOJA_CARTA.alto}] /Resources << /XObject << /Im0 ${img} 0 R >> >> /Contents ${cont} 0 R >>`);
    hojas.push(hoja);
  }
  poner(arbol, `<< /Type /Pages /Kids [${hojas.map((h) => `${h} 0 R`).join(" ")}] /Count ${hojas.length} >>`);
  poner(raiz, `<< /Type /Catalog /Pages ${arbol} 0 R >>`);
  // título en ASCII (sin tildes: el diccionario /Info va en PDFDocEncoding y así no hay sorpresas)
  const ascii = titulo.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\x20-\x7e]/g, "-").replace(/[()\\]/g, "");
  poner(info, `<< /Title (${ascii}) /Producer (Geoportal EMDUPAR) >>`);

  const partes: Uint8Array[] = [bytesDe("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")];
  let pos = partes[0].length;
  const xref: number[] = [];
  objetos.forEach((o, k) => {
    xref.push(pos);
    const cab = bytesDe(`${k + 1} 0 obj\n`), pie = bytesDe("\nendobj\n");
    partes.push(cab, ...o, pie);
    pos += cab.length + o.reduce((t, x) => t + x.length, 0) + pie.length;
  });
  const tabla = `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n${xref.map((x) => `${String(x).padStart(10, "0")} 00000 n \n`).join("")}`
    + `trailer\n<< /Size ${objetos.length + 1} /Root ${raiz} 0 R /Info ${info} 0 R >>\nstartxref\n${pos}\n%%EOF\n`;
  partes.push(bytesDe(tabla));
  const total = new Uint8Array(partes.reduce((t, x) => t + x.length, 0));
  let k = 0; for (const x of partes) { total.set(x, k); k += x.length; }
  return total;
}
