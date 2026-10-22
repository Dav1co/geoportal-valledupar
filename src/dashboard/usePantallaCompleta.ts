// Pantalla completa de la sección de un mapa (Cartera desagregada y Pérdidas): la API del navegador (con prefijo webkit para Safari) sobre el contenedor de la
// sección; sin ella (o si el navegador la niega), un contenedor fijo (position: fixed; inset: 0) con la misma disposición. Modo: "normal" | "api" | "fijo".
// En pantalla completa el mapa ocupa el alto que dejan los controles y la leyenda (el resto de la sección se desplaza dentro de sí misma), y el mapa se
// reajusta (resize) al cambiar de tamaño su contenedor: conserva encuadre y capas. Nada de esto consulta datos.
import { useEffect, useRef, useState, type RefObject } from "react";

export type ModoPantalla = "normal" | "api" | "fijo";
type DocFS = Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => Promise<void> | void };
type ElFS = HTMLElement & { webkitRequestFullscreen?: () => Promise<void> | void };
const elementoEnPantallaCompleta = () => (document as DocFS).fullscreenElement ?? (document as DocFS).webkitFullscreenElement ?? null;

export function usePantallaCompleta({ seccion, cont, top, ley, redimensionar, reiniciar }: {
  seccion: RefObject<HTMLElement | null>;      // contenedor de TODA la sección (es el que pasa a pantalla completa)
  cont: RefObject<HTMLElement | null>;         // contenedor del mapa
  top?: RefObject<HTMLElement | null>;         // parte de arriba (controles), para volver a medir si se reacomoda
  ley?: RefObject<HTMLElement | null>;         // leyenda, cuyo alto se descuenta del mapa
  redimensionar: () => void;                   // map.resize()
  reiniciar?: unknown;                         // si cambia (p. ej. el mapa se recrea tras un error), se vuelve a observar el contenedor del mapa
}) {
  const [modo, setModo] = useState<ModoPantalla>("normal");
  const [altoMapa, setAltoMapa] = useState<number | null>(null);   // solo en pantalla completa: el alto que dejan los controles
  const redimRef = useRef(redimensionar);
  redimRef.current = redimensionar;

  // 1) El navegador avisa cuando entra o sale (también con Esc): el estado sigue al navegador.
  useEffect(() => {
    const alCambiar = () => {
      if (elementoEnPantallaCompleta() === seccion.current) setModo("api");
      else setModo((m) => (m === "api" ? "normal" : m));
    };
    document.addEventListener("fullscreenchange", alCambiar);
    document.addEventListener("webkitfullscreenchange", alCambiar);
    return () => { document.removeEventListener("fullscreenchange", alCambiar); document.removeEventListener("webkitfullscreenchange", alCambiar); };
  }, []);
  // 2) Con el contenedor fijo (respaldo) no hay Esc nativo: se atiende aquí.
  useEffect(() => {
    if (modo !== "fijo") return;
    const tecla = (e: KeyboardEvent) => { if (e.key === "Escape") setModo("normal"); };
    document.addEventListener("keydown", tecla);
    return () => document.removeEventListener("keydown", tecla);
  }, [modo]);
  // 3) Si la sección se desmonta en pantalla completa, se sale (no deja el navegador en pantalla completa sin contenido).
  useEffect(() => () => {
    if (elementoEnPantallaCompleta() === seccion.current) { const d = document as DocFS; (d.exitFullscreen ?? d.webkitExitFullscreen)?.call(d); }
  }, []);
  async function alternar() {
    if (modo !== "normal") {
      if (modo === "api") { const d = document as DocFS; await (d.exitFullscreen ?? d.webkitExitFullscreen)?.call(d); }
      else setModo("normal");
      return;
    }
    const el = seccion.current as ElFS | null;
    if (!el) return;
    const pedir = el.requestFullscreen ?? el.webkitRequestFullscreen;
    if (!pedir) { setModo("fijo"); return; }
    try { await pedir.call(el); } catch { setModo("fijo"); }   // permiso negado o no disponible: contenedor fijo
  }
  // 4) En pantalla completa el mapa ocupa todo el alto que dejan los controles (y la leyenda). Se mide al entrar y cuando cambia el tamaño de la ventana o de la
  //    parte de arriba (controles que se reacomodan).
  useEffect(() => {
    const r = seccion.current, m = cont.current;
    if (modo === "normal" || !r || !m) { setAltoMapa(null); return; }
    const medir = () => {
      const y = m.getBoundingClientRect().top - r.getBoundingClientRect().top + r.scrollTop;
      const l = (ley?.current?.offsetHeight ?? 0) + 6;
      setAltoMapa(Math.max(300, Math.round(r.clientHeight - y - l - 28)));
    };
    medir();
    const ro = new ResizeObserver(medir);
    ro.observe(r);
    if (top?.current) ro.observe(top.current);
    if (ley?.current) ro.observe(ley.current);
    return () => ro.disconnect();
  }, [modo, reiniciar]);
  // 5) El mapa se reajusta a su contenedor siempre que este cambie de tamaño (entrar, salir, girar, cambiar la ventana): conserva centro, zoom y capas.
  useEffect(() => {
    const m = cont.current;
    if (!m) return;
    const ro = new ResizeObserver(() => redimRef.current());
    ro.observe(m);
    return () => ro.disconnect();
  }, [reiniciar]);
  useEffect(() => {
    const id = requestAnimationFrame(() => requestAnimationFrame(() => redimRef.current()));
    return () => cancelAnimationFrame(id);
  }, [modo, altoMapa]);

  return { modo, enPantalla: modo !== "normal", altoMapa, alternar };
}
