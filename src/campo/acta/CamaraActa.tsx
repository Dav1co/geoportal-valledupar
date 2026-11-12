import { useEffect, useRef, useState } from "react";
import { abrirCamara, capturarFoto, cerrarCamara, ErrorCamara } from "../camara";
import { megas } from "../formato";

// Cámara del formulario del acta: SOLO cámara (sin galería), en memoria. Misma que la del Paso D (allí no se exporta y esa carpeta no se toca): 1600 px, JPEG 0,72, sello de hora y coordenada
// estampado en la imagen (apoyo, no prueba: el servidor fija su propia hora y la coordenada de la apertura). El tope de peso lo manda el servidor (1,5 MB hallazgo, 2,5 MB papel).
export function CamaraActa({ rotulo, maxBytes, sello, onFoto, onCerrar }: {
  rotulo: string; maxBytes: number; sello: () => string[]; onFoto: (f: { blob: Blob }) => void; onCerrar: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const flujo = useRef<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lista, setLista] = useState(false);
  const [procesando, setProcesando] = useState(false);

  useEffect(() => {
    let vivo = true;
    abrirCamara()
      .then((f) => {
        if (!vivo) { cerrarCamara(f); return; }
        flujo.current = f;
        const v = videoRef.current;
        if (v) { v.srcObject = f; void v.play().catch(() => {}); }
      })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCamara ? e.message : "No se pudo abrir la cámara."); });
    return () => { vivo = false; cerrarCamara(flujo.current); flujo.current = null; };
  }, []);

  async function capturar() {
    const v = videoRef.current;
    if (!v || procesando) return;
    setProcesando(true);
    try {
      const f = await capturarFoto(v, sello(), maxBytes);
      if (!f) { setError(`La foto pesa más de ${megas(maxBytes)} aun reducida. Acérquese o mejore la luz e intente de nuevo.`); return; }
      onFoto(f);
    } catch (e) {
      setError(e instanceof ErrorCamara ? e.message : "No se pudo tomar la foto.");
    } finally {
      setProcesando(false);
    }
  }

  return (
    <div className="campo-camara" role="dialog" aria-modal="true" aria-label={`Cámara · ${rotulo}`}>
      <div className="campo-camara-cab">{rotulo}</div>
      {error ? <div className="campo-camara-error"><p role="alert">{error}</p></div> : <video ref={videoRef} className="campo-video" autoPlay playsInline muted onLoadedMetadata={() => setLista(true)} />}
      <div className="campo-camara-acc">
        <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        {!error && <button type="button" className="tec-boton campo-capturar" onClick={() => void capturar()} disabled={!lista || procesando}>{procesando ? "Procesando…" : "Tomar foto"}</button>}
      </div>
    </div>
  );
}
