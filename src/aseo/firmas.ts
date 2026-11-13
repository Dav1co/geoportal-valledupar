// Firmas del acta (Torre C): trazo → JPEG pequeño. Lógica de geometría PURA (se prueba en Node) y exportación a JPEG con canvas (solo navegador).
// El servidor vuelve a validar todo (cabecera JPEG, máximo 40 kB) y calcula la huella; aquí nunca se manda un hash ni un nombre del auditor.
export type Punto = { x: number; y: number };
export type Trazo = Punto[];
export const MAX_BYTES_FIRMA = 40 * 1024;                 // igual que la base (CHECK de aseo.auditoria_firmas.imagen)
export const MIN_LARGO_FIRMA_PX = 90;                     // trazo total mínimo para que no sea un toque o una raya
export const MIN_PUNTOS_FIRMA = 8;

export const largoTrazos = (t: Trazo[]): number => t.reduce((s, tr) => s + tr.slice(1).reduce((a, p, i) => a + Math.hypot(p.x - tr[i].x, p.y - tr[i].y), 0), 0);
export const cantidadPuntos = (t: Trazo[]): number => t.reduce((s, tr) => s + tr.length, 0);
/** Una firma vale si tiene suficientes puntos y largo (rechaza el lienzo vacío, un punto o una raya mínima) y se mueve en dos direcciones. */
export function firmaValida(t: Trazo[]): boolean {
  if (cantidadPuntos(t) < MIN_PUNTOS_FIRMA || largoTrazos(t) < MIN_LARGO_FIRMA_PX) return false;
  const c = cajaDe(t); return c.w >= 12 || c.h >= 12;
}
export function cajaDe(t: Trazo[]): { x: number; y: number; w: number; h: number } {
  const ps = t.flat(); if (ps.length === 0) return { x: 0, y: 0, w: 0, h: 0 };
  const xs = ps.map((p) => p.x), ys = ps.map((p) => p.y), x = Math.min(...xs), y = Math.min(...ys);
  return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
}
/** Escala para meter el trazo (con margen) en un lienzo de salida de ancho máx. × alto máx., sin deformarlo. */
export function escalaSalida(w: number, h: number, maxW = 560, maxH = 200, margen = 12): { k: number; ancho: number; alto: number } {
  const bw = Math.max(w, 1), bh = Math.max(h, 1), k = Math.min((maxW - 2 * margen) / bw, (maxH - 2 * margen) / bh, 3);
  return { k, ancho: Math.round(bw * k + 2 * margen), alto: Math.round(bh * k + 2 * margen) };
}
/** Tamaño en bytes de un base64 sin relleno de líneas. */
export const bytesDeBase64 = (b64: string): number => Math.floor((b64.length * 3) / 4) - (b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0);

export type FirmaJpeg = { b64: string; bytes: number; url: string };
/** Dibuja el trazo en un lienzo blanco y lo exporta a JPEG (base64 sin prefijo). Baja la calidad hasta quedar bajo el tope. */
export async function exportarFirmaJpeg(t: Trazo[]): Promise<FirmaJpeg> {
  const c = cajaDe(t), { k, ancho, alto } = escalaSalida(c.w, c.h);
  const cv = document.createElement("canvas"); cv.width = ancho; cv.height = alto;
  const g = cv.getContext("2d"); if (!g) throw new Error("sin lienzo");
  g.fillStyle = "#fff"; g.fillRect(0, 0, ancho, alto);
  g.strokeStyle = "#000"; g.fillStyle = "#000"; g.lineWidth = Math.max(2.5, 3 * Math.min(k, 1.5)); g.lineCap = "round"; g.lineJoin = "round";
  for (const tr of t) {
    if (tr.length === 1) { g.beginPath(); g.arc((tr[0].x - c.x) * k + 12, (tr[0].y - c.y) * k + 12, g.lineWidth / 2, 0, 7); g.fill(); continue; }
    g.beginPath(); tr.forEach((p, i) => { const X = (p.x - c.x) * k + 12, Y = (p.y - c.y) * k + 12; if (i === 0) g.moveTo(X, Y); else g.lineTo(X, Y); }); g.stroke();
  }
  for (const q of [0.92, 0.85, 0.75, 0.6, 0.45]) {
    const blob: Blob | null = await new Promise((res) => cv.toBlob(res, "image/jpeg", q));
    if (blob && blob.size <= MAX_BYTES_FIRMA) {
      const bytes = new Uint8Array(await blob.arrayBuffer()); let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return { b64: btoa(s), bytes: blob.size, url: URL.createObjectURL(blob) };
    }
  }
  throw new Error("La firma pesa demasiado");
}
