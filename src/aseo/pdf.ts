// Escritor de PDF propio (PURO, sin librerías) para el ACTA DE SUPERVISIÓN de la prestación del servicio de aseo con el membrete de EMDUPAR. Se genera en el navegador, a partir de lo que ya está en memoria (las fotos recién tomadas):
// NO se guarda en el servidor. Lleva las firmas ELECTRÓNICAS simples (imágenes JPEG del trazo) del auditor y, si la hay, del representante del operador; no es firma digital certificada. Texto en Helvetica/Courier estándar (codificación WinAnsi: tildes y ñ), fotos JPEG incrustadas
// tal cual (DCTDecode, sin recodificar) y el membrete reducido (ver membrete.ts). Hoja Carta, como la plantilla.

export type ImagenJpeg = { bytes: Uint8Array; ancho: number; alto: number };
export type FotoActa = ImagenJpeg & { etiqueta: string };
export type FirmaRepresentanteActa = { estado: "firmo" | "se_nego" | "sin_representante"; nombre: string | null; imagen: ImagenJpeg | null };
export type FirmasActa = { auditor: ImagenJpeg | null; representante: FirmaRepresentanteActa };
/** Texto de la firma electrónica del acta. BORRADOR, PENDIENTE de revisión de jurídica (David): no cambiar la redacción hasta tener su visto bueno. */
export const TEXTO_FIRMA_ELECTRONICA = "Firma electrónica simple (Ley 527 de 1999 y Decreto 2364 de 2012); no es firma digital certificada.";
export type DatosActa = {
  consecutivo: string; registradoEn: string; fechaServicio: string; auditor: { nombre: string; correo: string; cargo: string | null }; firmas: FirmasActa;
  actividad: string; modalidad: string; servicio: string;
  ruta: { codigo: string; sectores: string | null; turno: string | null; horario: string | null; frecuencia: string | null; km: number | null };
  seRealizo: "Sí" | "No" | "Parcial"; causal: string | null; respuestas: { pregunta: string; respuesta: string }[]; observaciones: string | null;
  posicion: { inicio: string | null; fin: string; precision: string | null }; marcas: string[]; fotos: FotoActa[]; sello: string;
};
export type Membrete = { logo: ImagenJpeg; banda: ImagenJpeg };

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Utilidades: codificación WinAnsi, anchos de Helvetica, lectura de JPEG
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
const ESPECIALES: Record<number, number> = { 0x2013: 0x96, 0x2014: 0x97, 0x2018: 0x91, 0x2019: 0x92, 0x201c: 0x93, 0x201d: 0x94, 0x2022: 0x95, 0x2026: 0x85, 0x20ac: 0x80 };
export function winAnsi(s: string): number[] {
  const out: number[] = [];
  for (const ch of s.normalize("NFC")) { const c = ch.codePointAt(0)!; out.push(c < 256 ? (c < 32 ? 32 : c) : ESPECIALES[c] ?? 63); }
  return out;
}
// Anchos de Helvetica (AFM) para 32..126, en milésimas de em
const W = [278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584];
export function anchoTexto(s: string, tam: number, negrita = false, mono = false): number {
  if (mono) return winAnsi(s).length * 0.6 * tam;
  let t = 0;
  for (const c of winAnsi(s)) t += c >= 32 && c <= 126 ? W[c - 32] : 556;
  return (t / 1000) * tam * (negrita ? 1.05 : 1);
}
export function partirLineas(texto: string, maxAncho: number, tam: number, negrita = false): string[] {
  const salida: string[] = [];
  for (const parrafo of texto.split(/\r?\n/)) {
    let linea = "";
    for (const palabra of parrafo.split(" ")) {
      const prueba = linea ? linea + " " + palabra : palabra;
      if (anchoTexto(prueba, tam, negrita) <= maxAncho || !linea) {
        if (!linea && anchoTexto(palabra, tam, negrita) > maxAncho) { let resto = palabra; while (anchoTexto(resto, tam, negrita) > maxAncho) { let k = resto.length; while (k > 1 && anchoTexto(resto.slice(0, k), tam, negrita) > maxAncho) k--; salida.push(resto.slice(0, k)); resto = resto.slice(k); } linea = resto; } else linea = prueba;
      } else { salida.push(linea); linea = palabra; }
    }
    salida.push(linea);
  }
  return salida;
}

/** Ancho, alto y componentes de un JPEG (marcador SOFn). */
export function infoJpeg(b: Uint8Array): { ancho: number; alto: number; componentes: number } {
  if (b[0] !== 0xff || b[1] !== 0xd8) throw new Error("La foto no es un JPEG.");
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { i += 2; continue; }
    const largo = (b[i + 2] << 8) | b[i + 3];
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return { alto: (b[i + 5] << 8) | b[i + 6], ancho: (b[i + 7] << 8) | b[i + 8], componentes: b[i + 9] };
    i += 2 + largo;
  }
  throw new Error("No se pudo leer el tamaño del JPEG.");
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Documento
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
const PAG_W = 612, PAG_H = 792, MARGEN_X = 72, TOPE = 112, BASE = 112;      // el pie (banda) ocupa el borde inferior: el texto termina por encima
const bytesDe = (s: string): Uint8Array => Uint8Array.from(s.split("").map((c) => c.charCodeAt(0) & 255));
const num = (n: number) => (Math.round(n * 100) / 100).toString();
const esc = (s: string) => winAnsi(s).map((c) => (c === 40 || c === 41 || c === 92 ? "\\" + String.fromCharCode(c) : c < 127 && c >= 32 ? String.fromCharCode(c) : "\\" + c.toString(8).padStart(3, "0"))).join("");

class Pagina { cont: string[] = []; imgs: number[] = []; }

export function generarActaPdf(d: DatosActa, m: Membrete): Uint8Array {
  const objetos: Uint8Array[][] = [];                 // contenido de cada objeto (partes), índice = número - 1
  const nuevo = (): number => { objetos.push([]); return objetos.length; };
  const poner = (n: number, ...partes: (string | Uint8Array)[]) => { objetos[n - 1] = partes.map((p) => (typeof p === "string" ? bytesDe(p) : p)); };

  const raiz = nuevo(), arbol = nuevo(), fHel = nuevo(), fNeg = nuevo(), fMono = nuevo();
  poner(fHel, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
  poner(fNeg, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
  poner(fMono, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>");
  const imagenes: number[] = [];
  const incrustar = (img: ImagenJpeg): number => {
    const info = infoJpeg(img.bytes), n = nuevo();
    const cs = info.componentes === 1 ? "/DeviceGray" : info.componentes === 4 ? "/DeviceCMYK" : "/DeviceRGB";
    poner(n, `<< /Type /XObject /Subtype /Image /Width ${info.ancho} /Height ${info.alto} /ColorSpace ${cs} /BitsPerComponent 8 /Filter /DCTDecode /Length ${img.bytes.length} >>\nstream\n`, img.bytes, "\nendstream");
    imagenes.push(n); return n;
  };
  const objLogo = incrustar(m.logo), objBanda = incrustar(m.banda);

  const paginas: Pagina[] = [];
  let pg!: Pagina, y = 0;
  const nombreImg = (n: number) => `/Im${n}`;
  const nuevaPagina = () => {
    pg = new Pagina(); paginas.push(pg);
    // Pie: la banda completa, pegada al borde inferior y con un poco de sangrado lateral (22 x 4,1 cm en la plantilla)
    const bw = PAG_W + 12, bh = bw * (m.banda.alto / m.banda.ancho);
    pg.cont.push(`q ${num(bw)} 0 0 ${num(bh)} -6 0 cm ${nombreImg(objBanda)} Do Q`); pg.imgs.push(objBanda);
    // Encabezado: el logo recortado, a la derecha (3,5 x 1,2 cm en la plantilla, aquí un poco mayor para que se lea)
    const lw = 150, lh = lw * (m.logo.alto / m.logo.ancho);
    pg.cont.push(`q ${num(lw)} 0 0 ${num(lh)} ${num(PAG_W - MARGEN_X - lw)} ${num(PAG_H - 28 - lh)} cm ${nombreImg(objLogo)} Do Q`); pg.imgs.push(objLogo);
    y = PAG_H - TOPE + 8;
  };
  const asegurar = (alto: number) => { if (y - alto < BASE) nuevaPagina(); };
  const texto = (t: string, x: number, yy: number, tam: number, fuente: "F1" | "F2" | "F3" = "F1", gris = 0) =>
    pg.cont.push(`BT ${gris ? `${gris} g ` : "0 g "}/${fuente} ${tam} Tf ${num(x)} ${num(yy)} Td (${esc(t)}) Tj ET`);
  const linea = (x1: number, y1: number, x2: number, y2: number, gris = 0.6) => pg.cont.push(`${gris} G 0.6 w ${num(x1)} ${num(y1)} m ${num(x2)} ${num(y2)} l S`);
  const parrafo = (t: string, tam = 10, negrita = false, x = MARGEN_X, ancho = PAG_W - 2 * MARGEN_X) => {
    for (const l of partirLineas(t, ancho, tam, negrita)) { asegurar(tam * 1.4); texto(l, x, y, tam, negrita ? "F2" : "F1"); y -= tam * 1.4; }
  };
  const campo = (rotulo: string, valor: string) => {
    const anchoR = 118, largo = anchoTexto(rotulo, 9, true) > anchoR - 8;
    // Un rótulo largo (una pregunta del catálogo) va en su propia línea y el valor debajo; uno corto va a la izquierda del valor
    const ancho = largo ? PAG_W - 2 * MARGEN_X : PAG_W - 2 * MARGEN_X - anchoR, ls = partirLineas(valor || "—", ancho, 10), lr = largo ? partirLineas(rotulo, ancho, 9, true) : [];
    asegurar((lr.length + ls.length) * 14 + 2);
    if (largo) { lr.forEach((l) => { texto(l, MARGEN_X, y, 9, "F2", 0.35); y -= 13; }); ls.forEach((l, i) => texto(l, MARGEN_X + 10, y - i * 14, 10)); y -= ls.length * 14 + 2; return; }
    texto(rotulo, MARGEN_X, y, 9, "F2", 0.35);
    ls.forEach((l, i) => { texto(l, MARGEN_X + anchoR, y - i * 14, 10); }); y -= ls.length * 14 + 2;
  };
  const seccion = (t: string, siguiente = 0) => { asegurar(34 + siguiente); y -= 8; texto(t.toUpperCase(), MARGEN_X, y, 10, "F2"); y -= 4; linea(MARGEN_X, y, PAG_W - MARGEN_X, y); y -= 14; };

  nuevaPagina();
  parrafo("ACTA DE SUPERVISIÓN DE LA PRESTACIÓN DEL SERVICIO DE ASEO", 13, true);
  y -= 2;
  texto(`Consecutivo ${d.consecutivo}`, MARGEN_X, y, 11, "F2"); y -= 16;
  seccion("Registro");
  campo("Fecha y hora", d.registradoEn + " (hora oficial del servidor)"); campo("Fecha de servicio", d.fechaServicio);
  campo("Realizó la supervisión (auditor de la interventoría)", d.auditor.nombre); campo("Correo", d.auditor.correo); campo("Cargo", d.auditor.cargo ?? "Cargo no registrado");
  seccion("Actividad y ruta");
  campo("Actividad", d.actividad); campo("Modalidad", d.modalidad); campo("Servicio", d.servicio);
  campo("Código de ruta", d.ruta.codigo); campo("Sectores atendidos", d.ruta.sectores ?? "—");
  campo("Turno y horario", [d.ruta.turno, d.ruta.horario].filter(Boolean).join(" · ") || "—"); campo("Frecuencia", d.ruta.frecuencia ?? "—");
  if (d.ruta.km != null) campo("Kilómetros de la ruta", d.ruta.km.toLocaleString("es-CO"));
  seccion("Incidencia");
  campo("¿Se realizó?", d.seRealizo); if (d.causal) campo("Causal", d.causal);
  for (const r of d.respuestas) campo(r.pregunta, r.respuesta);
  if (d.observaciones) campo("Observaciones", d.observaciones);
  seccion("Ubicación");
  if (d.posicion.inicio) campo("Al abrir", d.posicion.inicio); campo("Al enviar", d.posicion.fin); if (d.posicion.precision) campo("Precisión", d.posicion.precision);
  if (d.marcas.length) campo("Marcas", d.marcas.join("; "));
  if (d.fotos.length) {
    const caja = { w: (PAG_W - 2 * MARGEN_X - 12) / 2, h: 150 };
    seccion(`Fotos (${d.fotos.length})`, caja.h + 22);
    for (let i = 0; i < d.fotos.length; i += 2) {
      asegurar(caja.h + 22);
      [d.fotos[i], d.fotos[i + 1]].forEach((f, k) => {
        if (!f) return;
        const info = infoJpeg(f.bytes), esc2 = Math.min(caja.w / info.ancho, caja.h / info.alto), w = info.ancho * esc2, h = info.alto * esc2, x = MARGEN_X + k * (caja.w + 12), n = incrustar({ ...f, ancho: info.ancho, alto: info.alto });
        pg.cont.push(`q ${num(w)} 0 0 ${num(h)} ${num(x)} ${num(y - h)} cm ${nombreImg(n)} Do Q`); pg.imgs.push(n);
        texto(`${i + k + 1}. ${f.etiqueta}`, x, y - h - 10, 8, "F1", 0.35);
      });
      y -= caja.h + 22;
    }
  }
  seccion("Integridad", 60);
  parrafo("Registro digital. Sello de integridad (SHA-256 del contenido registrado en el servidor, que incluye las firmas):", 8.5);
  for (const l of [d.sello.slice(0, 32), d.sello.slice(32)]) { asegurar(12); texto(l, MARGEN_X, y, 9, "F3"); y -= 12; }
  // Firmas: dos columnas con el trazo, el nombre, el cargo y la fecha y hora del servidor
  const colW = (PAG_W - 2 * MARGEN_X - 24) / 2, firmaH = 56;
  seccion("Firmas", firmaH + 96);
  const dibujarFirma = (x: number, rotulo: string, img: ImagenJpeg | null, sinImagen: string | null, lineas: string[]) => {
    texto(rotulo, x, y, 8.5, "F2", 0.35);
    const top = y - 6;
    if (img) {
      const info = infoJpeg(img.bytes), k = Math.min(colW / info.ancho, firmaH / info.alto), w = info.ancho * k, h = info.alto * k, n = incrustar({ ...img, ancho: info.ancho, alto: info.alto });
      pg.cont.push(`q ${num(w)} 0 0 ${num(h)} ${num(x)} ${num(top - h)} cm ${nombreImg(n)} Do Q`); pg.imgs.push(n);
    } else if (sinImagen) texto(sinImagen, x, top - 30, 10, "F2");
    linea(x, top - firmaH - 2, x + colW, top - firmaH - 2, 0.2);
    let yy = top - firmaH - 13;
    for (const l of lineas) for (const s of partirLineas(l, colW, 9)) { texto(s, x, yy, 9); yy -= 11; }
  };
  const fr = d.firmas.representante;
  dibujarFirma(MARGEN_X, "Auditor de la interventoría (quien realizó la supervisión)", d.firmas.auditor, d.firmas.auditor ? null : "Sin firma registrada", [d.auditor.nombre, d.auditor.cargo ?? "Cargo no registrado", d.registradoEn + " (hora oficial del servidor)"]);
  dibujarFirma(MARGEN_X + colW + 24, "Representante del operador del servicio", fr.imagen, fr.estado === "se_nego" ? "Se negó a firmar" : fr.estado === "sin_representante" ? "No había representante" : null, [fr.nombre ?? "—"]);
  y -= firmaH + 88;
  asegurar(24); texto(TEXTO_FIRMA_ELECTRONICA, MARGEN_X, y, 8, "F1", 0.45); y -= 10;

  // Páginas y contenido
  const ids: number[] = [];
  const total = paginas.length;
  paginas.forEach((p, i) => {
    const c = nuevo(), pn = nuevo(), contenido = p.cont.join("\n") + `\nBT 0.45 g /F1 8 Tf ${num(PAG_W - MARGEN_X - 70)} ${num(BASE - 6)} Td (${esc(`Página ${i + 1} de ${total}`)}) Tj ET`;
    poner(c, `<< /Length ${contenido.length} >>\nstream\n`, contenido, "\nendstream");     // el contenido es ASCII puro (el texto va escapado en WinAnsi)
    const xo = [...new Set(p.imgs)].map((n) => `${nombreImg(n)} ${n} 0 R`).join(" ");
    poner(pn, `<< /Type /Page /Parent ${arbol} 0 R /MediaBox [0 0 ${PAG_W} ${PAG_H}] /Resources << /Font << /F1 ${fHel} 0 R /F2 ${fNeg} 0 R /F3 ${fMono} 0 R >> /XObject << ${xo} >> >> /Contents ${c} 0 R >>`);
    ids.push(pn);
  });
  poner(arbol, `<< /Type /Pages /Kids [${ids.map((n) => `${n} 0 R`).join(" ")}] /Count ${ids.length} >>`);
  poner(raiz, `<< /Type /Catalog /Pages ${arbol} 0 R >>`);
  const info = nuevo(); poner(info, `<< /Title (${esc("Acta de supervisión " + d.consecutivo)}) /Producer (Geoportal EMDUPAR) >>`);

  // Serialización con tabla de referencias cruzadas
  const partes: Uint8Array[] = [bytesDe("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")]; let pos = partes[0].length; const offs: number[] = [];
  objetos.forEach((o, i) => {
    offs.push(pos); const cab = bytesDe(`${i + 1} 0 obj\n`), pie = bytesDe("\nendobj\n");
    partes.push(cab, ...o, pie); pos += cab.length + o.reduce((s, x) => s + x.length, 0) + pie.length;
  });
  let xref = `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n`;
  for (const o of offs) xref += `${String(o).padStart(10, "0")} 00000 n \n`;
  xref += `trailer\n<< /Size ${objetos.length + 1} /Root ${raiz} 0 R /Info ${info} 0 R >>\nstartxref\n${pos}\n%%EOF\n`;
  partes.push(bytesDe(xref));
  const salida = new Uint8Array(partes.reduce((s, p) => s + p.length, 0)); let k = 0; for (const p of partes) { salida.set(p, k); k += p.length; }
  return salida;
}
