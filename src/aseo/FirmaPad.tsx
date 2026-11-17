import { useCallback, useEffect, useRef, useState } from "react";
import { exportarFirmaJpeg, firmaValida, type FirmaJpeg, type Trazo } from "./firmas";

// «Momento dedicado» de la firma: capa a pantalla completa (idealmente con el teléfono en horizontal) con Limpiar, Cancelar y OK. Con OK se cierra y la firma queda como miniatura en el formulario, sin editar encima.
// Se intenta pantalla completa y orientación horizontal donde el navegador lo permite (no en todos); si no, se sugiere girar el teléfono. Pointer Events: el mismo código sirve para dedo, lápiz y ratón.
export function FirmaPad({ titulo, onAceptar, onCancelar }: { titulo: string; onAceptar: (f: FirmaJpeg) => void; onCancelar: () => void }) {
  const cvRef = useRef<HTMLCanvasElement>(null);
  const trazos = useRef<Trazo[]>([]);
  const activo = useRef<number | null>(null);
  const [hayTrazo, setHayTrazo] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [vertical, setVertical] = useState(false);
  const [trabajando, setTrabajando] = useState(false);

  const pintar = useCallback(() => {
    const cv = cvRef.current; const g = cv?.getContext("2d"); if (!cv || !g) return;
    g.clearRect(0, 0, cv.width, cv.height); g.fillStyle = "#fff"; g.fillRect(0, 0, cv.width, cv.height);
    g.strokeStyle = "#111"; g.fillStyle = "#111"; g.lineWidth = 3; g.lineCap = "round"; g.lineJoin = "round";
    for (const tr of trazos.current) {
      if (tr.length === 1) { g.beginPath(); g.arc(tr[0].x, tr[0].y, 1.6, 0, 7); g.fill(); continue; }
      g.beginPath(); tr.forEach((p, i) => (i === 0 ? g.moveTo(p.x, p.y) : g.lineTo(p.x, p.y))); g.stroke();
    }
  }, []);

  const ajustar = useCallback(() => {
    const cv = cvRef.current; if (!cv) return;
    const r = cv.getBoundingClientRect(); cv.width = Math.max(1, Math.round(r.width)); cv.height = Math.max(1, Math.round(r.height));
    setVertical(window.innerHeight > window.innerWidth); trazos.current = []; setHayTrazo(false); pintar();           // al girar o redimensionar se parte de cero (las coordenadas cambian)
  }, [pintar]);

  useEffect(() => {
    const doc = document.documentElement; let fs = false;
    void (async () => {
      try { if (doc.requestFullscreen && !document.fullscreenElement) { await doc.requestFullscreen(); fs = true; } } catch { /* no todos los navegadores lo permiten */ }
      try { await (screen.orientation as unknown as { lock?: (o: string) => Promise<void> }).lock?.("landscape"); } catch { /* idem */ }
      ajustar();
    })();
    ajustar();
    const al = () => ajustar(); window.addEventListener("resize", al); window.addEventListener("orientationchange", al);
    const prev = document.body.style.overflow; document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("resize", al); window.removeEventListener("orientationchange", al); document.body.style.overflow = prev;
      try { screen.orientation.unlock?.(); } catch { /* idem */ }
      if (fs && document.fullscreenElement) void document.exitFullscreen().catch(() => {});
    };
  }, [ajustar]);

  const punto = (e: React.PointerEvent<HTMLCanvasElement>) => { const r = e.currentTarget.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const abajo = (e: React.PointerEvent<HTMLCanvasElement>) => { e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId); activo.current = e.pointerId; trazos.current.push([punto(e)]); setError(null); pintar(); };
  const mueve = (e: React.PointerEvent<HTMLCanvasElement>) => { if (activo.current !== e.pointerId) return; e.preventDefault(); trazos.current[trazos.current.length - 1].push(punto(e)); pintar(); };
  const arriba = (e: React.PointerEvent<HTMLCanvasElement>) => { if (activo.current !== e.pointerId) return; activo.current = null; setHayTrazo(trazos.current.length > 0); pintar(); };
  const limpiar = () => { trazos.current = []; setHayTrazo(false); setError(null); pintar(); };

  async function ok() {
    if (!firmaValida(trazos.current)) { setError("La firma es muy corta. Fírmela completa con el dedo y pulse OK."); return; }
    setTrabajando(true);
    try { onAceptar(await exportarFirmaJpeg(trazos.current)); } catch { setError("No se pudo guardar la firma. Pulse Limpiar y vuelva a firmar."); setTrabajando(false); }
  }

  return (
    <div className="aseo-modulo aseo-firma-capa" role="dialog" aria-modal="true" aria-label={titulo}>
      <div className="aseo-firma-cab"><strong>{titulo}</strong>{vertical ? <span className="aseo-firma-giro"> Para firmar con más espacio, gire el teléfono.</span> : null}</div>
      <canvas ref={cvRef} className="aseo-firma-lienzo" aria-label="Espacio para firmar con el dedo" onPointerDown={abajo} onPointerMove={mueve} onPointerUp={arriba} onPointerCancel={arriba} />
      {error ? <p className="aseo-firma-error" role="alert">{error}</p> : null}
      <div className="aseo-firma-acc">
        <button type="button" className="tec-boton-sec" onClick={onCancelar} disabled={trabajando}>Cancelar</button>
        <button type="button" className="tec-boton-sec" onClick={limpiar} disabled={!hayTrazo || trabajando}>Limpiar</button>
        <button type="button" className="tec-boton" onClick={() => void ok()} disabled={!hayTrazo || trabajando}>{trabajando ? "Guardando…" : "OK"}</button>
      </div>
    </div>
  );
}
