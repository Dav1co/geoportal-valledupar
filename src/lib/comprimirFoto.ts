// Compresión de las fotos EN EL CELULAR antes de subirlas (19-nov-2026, encargo de David). La usan todas las cámaras de campo (Técnica, Comercial, Aseo, el acta
// y Encontrar: src/campo/camara.ts) y los botones de foto que eligen un archivo (remisión de químicos, foto principal de la ficha).
// · Lado largo: 1.600 px; 2.048 px en el acta de Comercial y en las fotos del medidor, para que se lean los números y los sellos.
// · JPEG a calidad 0,8. Meta: 250–500 KB por foto. Si a 0,8 pasa de 500 KB se baja la calidad (0,72 y 0,65, no menos: la foto tiene que leerse); si aun así pasa,
//   se acepta mientras quepa en el tope del servidor. Solo si ni eso cabe se baja a 0,5 y, por último, se achica el lado.
// · El SELLO (hora y GPS) se dibuja ANTES de comprimir: va dentro de la imagen comprimida (lo hace camara.ts al dibujar el fotograma).
// · La huella SHA-256 de la foto, donde existe (acta de Comercial), la calcula el servidor sobre el archivo que se guarda: el comprimido. Aquí no se calcula.
// · Si la foto ya es más pequeña (lado y peso) no se toca: no se agranda nunca y un JPEG pequeño de archivo se sube tal cual.

export const LADO_FOTO_PX = 1600;
export const LADO_FOTO_DETALLE_PX = 2048;
export const CALIDAD_FOTO = 0.8;
/** Calidades que se prueban, en orden, para llegar a la meta. */
export const CALIDADES_META = [0.8, 0.72, 0.65];
export const META_MAX_BYTES = 500 * 1024;
export const META_MIN_BYTES = 250 * 1024;      // de referencia: una foto más liviana no se «engorda»
const CALIDAD_EMERGENCIA = 0.5;

/** ¿Va a 2.048 px? Las fotos del medidor (y las de su lectura, su serial o sus sellos), por su código o su nombre. */
export const esFotoDeDetalle = (...textos: (string | null | undefined)[]) => textos.some((t) => !!t && /medidor|lectura|serial|sello/i.test(t));

export type FotoComprimida = { blob: Blob; ancho: number; alto: number; calidad: number; lado: number; original_bytes: number | null; sin_cambios: boolean };

export function aBlob(canvas: HTMLCanvasElement, calidad: number): Promise<Blob | null> {
  return new Promise((resolver) => canvas.toBlob((b) => resolver(b), "image/jpeg", calidad));
}

/** Codifica un lienzo ya dibujado (con su sello, si lo lleva) siguiendo la regla de arriba. Devuelve null si ni con todo cabe en `maxBytes`.
 *  `redibujar(lado)`: vuelve a dibujar a un lado menor para el último intento. */
export async function codificar(canvas: HTMLCanvasElement, maxBytes: number, redibujar: (lado: number) => HTMLCanvasElement): Promise<Omit<FotoComprimida, "original_bytes" | "sin_cambios"> | null> {
  const lado = Math.max(canvas.width, canvas.height);
  let ultima: { blob: Blob; calidad: number } | null = null;
  for (const calidad of CALIDADES_META) {
    const blob = await aBlob(canvas, calidad);
    if (!blob || blob.size === 0) continue;
    if (blob.size <= META_MAX_BYTES) return { blob, ancho: canvas.width, alto: canvas.height, calidad, lado };
    ultima = { blob, calidad };
  }
  // la meta no se alcanzó ni a 0,65: se acepta esa (la más cercana a la meta sin bajar de 0,65) si cabe en el tope del servidor; que se lea vale más que unos KB
  if (ultima && ultima.blob.size <= maxBytes) return { blob: ultima.blob, ancho: canvas.width, alto: canvas.height, calidad: ultima.calidad, lado };
  // emergencia: no cabe ni a 0,65
  const e = await aBlob(canvas, CALIDAD_EMERGENCIA);
  if (e && e.size > 0 && e.size <= maxBytes) return { blob: e, ancho: canvas.width, alto: canvas.height, calidad: CALIDAD_EMERGENCIA, lado };
  const chico = redibujar(Math.round(lado * 0.8));
  const c = await aBlob(chico, CALIDAD_EMERGENCIA);
  if (c && c.size > 0 && c.size <= maxBytes) return { blob: c, ancho: chico.width, alto: chico.height, calidad: CALIDAD_EMERGENCIA, lado: Math.max(chico.width, chico.height) };
  return null;
}

/** Lienzo con la imagen escalada para que su lado largo no pase de `ladoMayor` (nunca se agranda). */
export function lienzoEscalado(origen: CanvasImageSource, w: number, h: number, ladoMayor: number): HTMLCanvasElement {
  const escala = Math.min(1, ladoMayor / Math.max(w, h));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(w * escala)); canvas.height = Math.max(1, Math.round(h * escala));
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("No se pudo procesar la foto en este navegador.");
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(origen, 0, 0, canvas.width, canvas.height);
  return canvas;
}

/** Una foto que llega como ARCHIVO (botón «Tomar o elegir la foto»): la gira según su EXIF, la reduce y la pasa a JPEG con la misma regla.
 *  Un JPEG que ya cabe (lado ≤ `ladoMayor` y peso ≤ 500 KB) se devuelve tal cual. */
export async function comprimirArchivo(archivo: Blob, maxBytes: number, ladoMayor = LADO_FOTO_PX): Promise<FotoComprimida> {
  let img: ImageBitmap;
  try { img = await createImageBitmap(archivo, { imageOrientation: "from-image" }); }
  catch { throw new Error("Ese archivo no es una foto que se pueda leer. Tome la foto de nuevo."); }
  try {
    if (archivo.type === "image/jpeg" && Math.max(img.width, img.height) <= ladoMayor && archivo.size <= META_MAX_BYTES && archivo.size <= maxBytes)
      return { blob: archivo, ancho: img.width, alto: img.height, calidad: 1, lado: Math.max(img.width, img.height), original_bytes: archivo.size, sin_cambios: true };
    const canvas = lienzoEscalado(img, img.width, img.height, ladoMayor);
    const r = await codificar(canvas, maxBytes, (l) => lienzoEscalado(img, img.width, img.height, l));
    if (!r) throw new Error(`La foto pesa más de ${Math.round(maxBytes / 1048576 * 10) / 10} MB aun reducida.`);
    return { ...r, original_bytes: archivo.size, sin_cambios: false };
  } finally { img.close?.(); }
}
