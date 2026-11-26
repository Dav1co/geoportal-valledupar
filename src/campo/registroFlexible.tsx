import { useRef, useState } from "react";
import type { FormularioCampo } from "./apiCampo";
import { areaCampo } from "./area";
import { codificar, lienzoEscalado, LADO_FOTO_PX } from "../lib/comprimirFoto";
import { decimal, fechaHoraSello, metros } from "./formato";
import type { Fix } from "./ubicacion";
import "./registro-flexible.css";

// Registro flexible (25-nov, David): el SUPERVISOR de Comercial (y el administrador) puede registrar sin estar en el sitio:
//  · adjuntar fotos desde la galería o desde un archivo (sin obligación de cámara), y
//  · digitar el XY del punto en dos casillas (precargadas con el GPS y validadas contra la zona de Valledupar).
// La regla vive en el servidor (la base rechaza con 403 a quien no es supervisor, y siempre desde Técnica); esta pantalla solo muestra u oculta.
// Para TODOS, el reporte lleva además dónde estaba el dispositivo al registrar (lat_registro/lon_registro), o «sin ubicación del dispositivo».
// La dirección opcional («¿Quiere agregar dirección?») va en Reportar anomalía y en los formatos cuyo contrato no es obligatorio.
// Una foto adjuntada se dibuja de nuevo en un lienzo (se pierden los datos EXIF, incluido el GPS de la foto original), lleva un sello «Adjuntada desde…»
// y se comprime con la regla común (src/lib/comprimirFoto.ts). Como la de la cámara, vive solo en la memoria de la pantalla.

export type OrigenFoto = "camara" | "galeria" | "archivo";
export const TOPES = { direccion: 120, barrio: 80, referencia: 200 } as const;
export type Registro = { xy_manual: boolean; lat_registro: number | null; lon_registro: number | null; precision_registro_m: number | null;
  direccion?: string | null; barrio?: string | null; referencia?: string | null };

/** ¿Esta persona puede usar el registro flexible? Supervisor o administrador de campo, y nunca cuando la pantalla se abre desde Técnica. */
export const puedeFlexible = (def: FormularioCampo): boolean => def.puede.supervisar && areaCampo() !== "tecnica";

/** Lee una coordenada digitada (acepta coma o punto decimal). Nulo si no es un número. */
export function leerCoordenada(t: string): number | null {
  const s = t.trim().replace(",", ".");
  if (!/^-?\d{1,3}(\.\d{1,8})?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

export type EstadoXY = { activo: boolean; lat: string; lon: string };
/** El XY digitado ya validado, o el motivo por el que no sirve (dentro de la zona de Valledupar, como lo exige el servidor). */
export function xyDigitado(e: EstadoXY, zona: FormularioCampo["zona"]): { lat: number; lon: number } | { falta: string } {
  const lat = leerCoordenada(e.lat), lon = leerCoordenada(e.lon);
  if (lat === null || lon === null) return { falta: "Digite la latitud y la longitud del punto (por ejemplo 10,46321 y -73,25012)." };
  if (lat < zona.lat_min || lat > zona.lat_max || lon < zona.lon_min || lon > zona.lon_max) {
    return { falta: `El XY digitado está fuera de la zona de Valledupar (latitud ${decimal(zona.lat_min, 2)} a ${decimal(zona.lat_max, 2)}; longitud ${decimal(zona.lon_min, 2)} a ${decimal(zona.lon_max, 2)}).` };
  }
  return { lat: Number(lat.toFixed(6)), lon: Number(lon.toFixed(6)) };
}

export type EstadoDireccion = { activa: boolean; direccion: string; barrio: string; referencia: string };
export const DIRECCION_VACIA: EstadoDireccion = { activa: false, direccion: "", barrio: "", referencia: "" };

/** El bloque `registro` que viaja a la Edge. La dirección solo si la casilla está marcada (desmarcada no se envía). */
export function armarRegistro(xyManual: boolean, fix: Fix | null, dir: EstadoDireccion | null): Registro {
  const r: Registro = {
    xy_manual: xyManual,
    lat_registro: fix ? Number(fix.lat.toFixed(6)) : null, lon_registro: fix ? Number(fix.lon.toFixed(6)) : null,
    precision_registro_m: fix && Number.isFinite(fix.precision_m) ? Math.round(fix.precision_m * 10) / 10 : null,
  };
  if (dir?.activa) {
    const t = (s: string) => (s.trim() === "" ? null : s.trim());
    r.direccion = t(dir.direccion); r.barrio = t(dir.barrio); r.referencia = t(dir.referencia);
  }
  return r;
}

/** Foto que llega de la galería o de un archivo: se redibuja (sin EXIF) con su sello y se comprime. Nulo si ni reducida cabe en `maxBytes`. */
export async function prepararAdjunta(archivo: Blob, origen: Exclude<OrigenFoto, "camara">, maxBytes: number, ladoMayor: number = LADO_FOTO_PX): Promise<Blob | null> {
  let img: ImageBitmap;
  try { img = await createImageBitmap(archivo, { imageOrientation: "from-image" }); }
  catch { throw new Error("Ese archivo no es una foto que se pueda leer (use JPEG, PNG o HEIC)."); }
  try {
    const sello = [`Adjuntada desde ${origen === "galeria" ? "la galería" : "un archivo"} · ${fechaHoraSello(new Date())}`, "No tomada con la cámara del formulario"];
    const dibujar = (lado: number) => {
      const c = lienzoEscalado(img, img.width, img.height, lado);
      const ctx = c.getContext("2d");
      if (!ctx) throw new Error("No se pudo procesar la foto en este navegador.");
      const px = Math.max(14, Math.round(c.width * 0.026));
      ctx.font = `600 ${px}px sans-serif`; ctx.textBaseline = "top";
      const franja = sello.length * Math.round(px * 1.35) + Math.round(px * 0.7);
      ctx.fillStyle = "rgba(0,0,0,0.62)"; ctx.fillRect(0, c.height - franja, c.width, franja);
      ctx.fillStyle = "#ffffff";
      sello.forEach((s, i) => ctx.fillText(s, Math.round(px * 0.5), c.height - franja + Math.round(px * 0.35) + i * Math.round(px * 1.35)));
      return c;
    };
    const r = await codificar(dibujar(ladoMayor), maxBytes, dibujar, ladoMayor);
    return r ? r.blob : null;
  } finally { img.close?.(); }
}

/** Dos botones: «Desde la galería» y «Desde un archivo». Cada uno abre el selector del sistema; la foto se prepara (sello y compresión) antes de entregarla. */
export function BotonesAdjuntar({ rotulo, maxBytes, ladoMayor, deshabilitado, onFoto }: {
  rotulo: string; maxBytes: number; ladoMayor?: number; deshabilitado?: boolean; onFoto: (blob: Blob, origen: Exclude<OrigenFoto, "camara">) => void;
}) {
  const galeria = useRef<HTMLInputElement>(null);
  const archivo = useRef<HTMLInputElement>(null);
  const [procesando, setProcesando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function elegir(origen: Exclude<OrigenFoto, "camara">, f: File | undefined) {
    if (!f) return;
    setProcesando(true); setError(null);
    try {
      const b = await prepararAdjunta(f, origen, maxBytes, ladoMayor);
      if (!b) setError("La foto pesa demasiado aun reducida. Elija otra.");
      else onFoto(b, origen);
    } catch (e) { setError(e instanceof Error ? e.message : "No se pudo leer la foto."); }
    finally { setProcesando(false); }
  }
  return (
    <div className="rf-adjuntar" data-rf-adjuntar>
      <div className="campo-foto-acc">
        <button type="button" className="tec-boton-sec tec-boton-corto" data-rf-galeria disabled={deshabilitado || procesando} onClick={() => galeria.current?.click()}
          aria-label={`${rotulo}: adjuntar desde la galería`}>Desde la galería</button>
        <button type="button" className="tec-boton-sec tec-boton-corto" data-rf-archivo disabled={deshabilitado || procesando} onClick={() => archivo.current?.click()}
          aria-label={`${rotulo}: adjuntar desde un archivo`}>Desde un archivo</button>
      </div>
      <input ref={galeria} type="file" accept="image/*" hidden data-rf-input="galeria" onChange={(e) => { void elegir("galeria", e.target.files?.[0]); e.target.value = ""; }} />
      <input ref={archivo} type="file" accept="image/jpeg,image/png,image/heic,image/heif,image/webp" hidden data-rf-input="archivo" onChange={(e) => { void elegir("archivo", e.target.files?.[0]); e.target.value = ""; }} />
      {procesando && <p className="campo-sub" role="status">Preparando la foto…</p>}
      {error && <p className="campo-error" role="alert">{error}</p>}
    </div>
  );
}

/** Rótulo pequeño bajo una foto adjuntada. */
export const MarcaOrigen = ({ origen }: { origen: OrigenFoto }) =>
  origen === "camara" ? null : <span className="rf-marca" data-rf-marca={origen}>Adjuntada desde {origen === "galeria" ? "la galería" : "un archivo"}</span>;

/** Casilla «Digitar el XY del punto» y las dos casillas, precargadas con el GPS. Solo para quien puede (puedeFlexible). */
export function PanelXY({ estado, onCambio, fix, zona, deshabilitado }: {
  estado: EstadoXY; onCambio: (e: EstadoXY) => void; fix: Fix | null; zona: FormularioCampo["zona"]; deshabilitado?: boolean;
}) {
  const v = estado.activo ? xyDigitado(estado, zona) : null;
  function activar(a: boolean) {
    onCambio(a ? { activo: true, lat: estado.lat || (fix ? decimal(fix.lat, 6).replace(/\./g, "") : ""), lon: estado.lon || (fix ? decimal(fix.lon, 6).replace(/\./g, "") : "") } : { ...estado, activo: false });
  }
  return (
    <div className="rf-panel" data-rf-xy>
      <label className="campo-check rf-check">
        <input type="checkbox" checked={estado.activo} onChange={(e) => activar(e.target.checked)} disabled={deshabilitado} data-rf-xy-activar />
        <span><strong>Digitar el XY del punto</strong><small>Para registrar desde otro lugar. Quedará marcado «XY digitado — registrado desde otro punto».</small></span>
      </label>
      {estado.activo && (
        <div className="rf-xy">
          <div className="tec-campo">
            <label htmlFor="rf-lat">Latitud</label>
            <input id="rf-lat" type="text" inputMode="decimal" autoComplete="off" value={estado.lat} onChange={(e) => onCambio({ ...estado, lat: e.target.value })} disabled={deshabilitado} />
          </div>
          <div className="tec-campo">
            <label htmlFor="rf-lon">Longitud</label>
            <input id="rf-lon" type="text" inputMode="decimal" autoComplete="off" value={estado.lon} onChange={(e) => onCambio({ ...estado, lon: e.target.value })} disabled={deshabilitado} />
          </div>
          {v && "falta" in v && (estado.lat !== "" || estado.lon !== "") && <p className="campo-error rf-xy-nota" role="alert">{v.falta}</p>}
          <p className="campo-sub rf-xy-nota">
            {fix ? `Su dispositivo está en ${decimal(fix.lat, 5)}, ${decimal(fix.lon, 5)} (${metros(fix.precision_m)}): esa posición también queda en el registro.`
                 : "Su dispositivo no da ubicación: quedará «sin ubicación del dispositivo»."}
          </p>
        </div>
      )}
    </div>
  );
}

/** «¿Quiere agregar dirección?»: desmarcada por omisión; al marcarla aparecen Dirección, Barrio y Referencia (opcionales). */
export function PanelDireccion({ estado, onCambio, deshabilitado }: { estado: EstadoDireccion; onCambio: (e: EstadoDireccion) => void; deshabilitado?: boolean }) {
  const campo = (k: "direccion" | "barrio" | "referencia", rotulo: string) => (
    <div className="tec-campo">
      <label htmlFor={`rf-${k}`}>{rotulo} (opcional)</label>
      <input id={`rf-${k}`} type="text" autoComplete="off" maxLength={TOPES[k]} value={estado[k]} onChange={(e) => onCambio({ ...estado, [k]: e.target.value })} disabled={deshabilitado} />
    </div>
  );
  return (
    <div className="rf-panel" data-rf-direccion>
      <label className="campo-check rf-check">
        <input type="checkbox" checked={estado.activa} onChange={(e) => onCambio({ ...estado, activa: e.target.checked })} disabled={deshabilitado} data-rf-direccion-activar />
        <span><strong>¿Quiere agregar dirección?</strong><small>Dirección, barrio y referencia del sitio. Si la desmarca, no se envían.</small></span>
      </label>
      {estado.activa && <div className="rf-direccion">{campo("direccion", "Dirección")}{campo("barrio", "Barrio")}{campo("referencia", "Referencia")}</div>}
    </div>
  );
}
