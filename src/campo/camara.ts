// Cámara del formulario (getUserMedia) y procesamiento de la foto. REGLAS: nada de selector de archivos ni de galería; la foto vive SOLO en memoria (Blob): no se guarda en el
// dispositivo, ni en localStorage/IndexedDB, ni en la galería. Al re-codificar con canvas se pierden los datos EXIF (deseable). El sello lo genera el celular y es falsificable:
// no es prueba; la hora oficial es la del servidor.

export type TipoErrorCamara = "no_soportada" | "permiso" | "sin_camara" | "ocupada" | "otro";
export class ErrorCamara extends Error {
  tipo: TipoErrorCamara;
  constructor(tipo: TipoErrorCamara, mensaje: string) {
    super(mensaje);
    this.name = "ErrorCamara";
    this.tipo = tipo;
  }
}

// PROPUESTAS (parametrizables aquí): lado mayor, calidades de JPEG, en orden de intento, y un último intento a 1280 px.
export const LADO_MAYOR_PX = 1600;
export const CALIDADES = [0.72, 0.6, 0.5];
export const LADO_MAYOR_ULTIMO_INTENTO_PX = 1280;

export const camaraDisponible = () => typeof navigator !== "undefined" && !!navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === "function";

export async function abrirCamara(): Promise<MediaStream> {
  if (!camaraDisponible()) {
    throw new ErrorCamara("no_soportada", window.isSecureContext === false
      ? "Este navegador solo permite la cámara en páginas seguras (https). Abra el geoportal desde su dirección oficial."
      : "Este navegador no permite usar la cámara desde la página. Use Safari en iPhone o Chrome en Android, actualizado.");
  }
  try {
    // Cámara trasera; el navegador usa la que haya si no existe. Sin audio.
    return await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
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

export type FotoProcesada = { blob: Blob; ancho: number; alto: number; calidad: number };

function aBlob(canvas: HTMLCanvasElement, calidad: number): Promise<Blob | null> {
  return new Promise((resolver) => canvas.toBlob((b) => resolver(b), "image/jpeg", calidad));
}

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

/** Captura el fotograma actual del video: lado mayor de 1600 px, JPEG a 0,72; si pesa más de `maxBytes`, 0,6 y 0,5; y como último intento 1280 px a 0,5. Devuelve null si nada cabe. */
export async function capturarFoto(video: HTMLVideoElement, lineasSello: string[], maxBytes: number): Promise<FotoProcesada | null> {
  if (!video.videoWidth || !video.videoHeight) throw new ErrorCamara("otro", "La cámara todavía no está lista. Espere un segundo y vuelva a intentarlo.");
  for (const lado of [LADO_MAYOR_PX, LADO_MAYOR_ULTIMO_INTENTO_PX]) {
    const canvas = dibujar(video, lado, lineasSello);
    for (const calidad of lado === LADO_MAYOR_PX ? CALIDADES : [CALIDADES[CALIDADES.length - 1]]) {
      const blob = await aBlob(canvas, calidad);
      if (blob && blob.size > 0 && blob.size <= maxBytes) return { blob, ancho: canvas.width, alto: canvas.height, calidad };
    }
  }
  return null;
}
