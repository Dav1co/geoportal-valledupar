// Cámara del formulario (getUserMedia) y procesamiento de la foto. REGLAS: nada de selector de archivos ni de galería; la foto vive SOLO en memoria (Blob): no se guarda en el
// dispositivo, ni en localStorage/IndexedDB, ni en la galería. Al re-codificar con canvas se pierden los datos EXIF (deseable). El sello lo genera el celular y es falsificable:
// no es prueba; la hora oficial es la del servidor.
// COMPRESIÓN (19-nov-2026): el fotograma se dibuja con su sello y después se comprime con la regla común de src/lib/comprimirFoto.ts (1.600 px, o 2.048 px en el
// acta de Comercial y en las fotos del medidor; JPEG 0,8; meta 250–500 KB). El sello va ANTES de comprimir: queda dentro de la foto que se guarda.
import { codificar, LADO_FOTO_PX } from "../lib/comprimirFoto";

export type TipoErrorCamara = "no_soportada" | "permiso" | "sin_camara" | "ocupada" | "otro";
export class ErrorCamara extends Error {
  tipo: TipoErrorCamara;
  constructor(tipo: TipoErrorCamara, mensaje: string) {
    super(mensaje);
    this.name = "ErrorCamara";
    this.tipo = tipo;
  }
}

export { LADO_FOTO_PX as LADO_MAYOR_PX, LADO_FOTO_DETALLE_PX, esFotoDeDetalle, ladoPara } from "../lib/comprimirFoto";

export const camaraDisponible = () => typeof navigator !== "undefined" && !!navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === "function";

/** `ladoMayor`: el lado largo con que se va a guardar la foto. Para 2.048 px se le pide a la cámara un video más grande (2.560 × 1.440) como IDEAL, no como
 *  exigencia: si el celular no lo tiene, entrega el más grande que tenga y la foto se guarda a ese tamaño, sin agrandarla y sin fallar. */
export async function abrirCamara(ladoMayor: number = LADO_FOTO_PX): Promise<MediaStream> {
  if (!camaraDisponible()) {
    throw new ErrorCamara("no_soportada", window.isSecureContext === false
      ? "Este navegador solo permite la cámara en páginas seguras (https). Abra el geoportal desde su dirección oficial."
      : "Este navegador no permite usar la cámara desde la página. Use Safari en iPhone o Chrome en Android, actualizado.");
  }
  try {
    // Cámara trasera; el navegador usa la que haya si no existe. Sin audio.
    const grande = ladoMayor > 1920;
    return await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: grande ? 2560 : 1920 }, height: { ideal: grande ? 1440 : 1080 } }, audio: false });
  } catch (e) {
    const nombre = e instanceof DOMException ? e.name : "";
    if (nombre === "NotAllowedError" || nombre === "SecurityError" || nombre === "PermissionDeniedError") {
      throw new ErrorCamara("permiso", "No se dio permiso para usar la cámara. Permítala para este sitio en los ajustes del navegador (en iPhone: Ajustes › Safari › Cámara; en Android: toque el candado de la barra de direcciones › Permisos) y vuelva a intentarlo.");
    }
    if (nombre === "NotFoundError" || nombre === "OverconstrainedError" || nombre === "DevicesNotFoundError") throw new ErrorCamara("sin_camara", "No se encontró una cámara en este dispositivo.");
    if (nombre === "NotReadableError" || nombre === "TrackStartError" || nombre === "AbortError") throw new ErrorCamara("ocupada", "La cámara está siendo usada por otra aplicación. Ciérrela y vuelva a intentarlo.");
    throw new ErrorCamara("otro", "No se pudo abrir la cámara. Cierre otras aplicaciones que la usen y vuelva a intentarlo.");
  }
}

export function cerrarCamara(flujo: MediaStream | null) {
  flujo?.getTracks().forEach((t) => t.stop());
}

export type FotoProcesada = { blob: Blob; ancho: number; alto: number; calidad: number; lado: number };

function dibujar(video: HTMLVideoElement, ladoMayor: number, lineasSello: string[]): HTMLCanvasElement {
  const w = video.videoWidth, h = video.videoHeight;
  const escala = Math.min(1, ladoMayor / Math.max(w, h));
  const ancho = Math.round(w * escala), alto = Math.round(h * escala);
  const canvas = document.createElement("canvas");
  canvas.width = ancho;
  canvas.height = alto;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new ErrorCamara("otro", "No se pudo procesar la foto en este navegador.");
  ctx.drawImage(video, 0, 0, ancho, alto);
  // Sello: franja oscura abajo con hora y coordenada (texto blanco). Tamaño proporcional al ancho para que se lea.
  const px = Math.max(14, Math.round(ancho * 0.026));
  ctx.font = `600 ${px}px sans-serif`;
  ctx.textBaseline = "top";
  const franja = lineasSello.length * Math.round(px * 1.35) + Math.round(px * 0.7);
  ctx.fillStyle = "rgba(0,0,0,0.62)";
  ctx.fillRect(0, alto - franja, ancho, franja);
  ctx.fillStyle = "#ffffff";
  lineasSello.forEach((t, i) => ctx.fillText(t, Math.round(px * 0.5), alto - franja + Math.round(px * 0.35) + i * Math.round(px * 1.35)));
  return canvas;
}

/** Captura el fotograma actual del video con su sello y lo comprime (src/lib/comprimirFoto.ts): lado largo `ladoMayor` (1.600 px por omisión; nunca se agranda),
 *  JPEG 0,72 a 1.600 px y 0,8 a 2.048 px; si pasa de 500 KB, se baja hasta 0,65. Devuelve null si ni reduciendo cabe en `maxBytes` (el tope del servidor). */
export async function capturarFoto(video: HTMLVideoElement, lineasSello: string[], maxBytes: number, ladoMayor: number = LADO_FOTO_PX): Promise<FotoProcesada | null> {
  if (!video.videoWidth || !video.videoHeight) throw new ErrorCamara("otro", "La cámara todavía no está lista. Espere un segundo y vuelva a intentarlo.");
  const canvas = dibujar(video, ladoMayor, lineasSello);      // el sello se dibuja AQUÍ, antes de comprimir
  return codificar(canvas, maxBytes, (lado) => dibujar(video, lado, lineasSello), ladoMayor);
}
