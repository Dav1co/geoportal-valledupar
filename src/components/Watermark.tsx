import { useEffect, useRef, type RefObject } from "react";

// Marca de agua repetida con el correo del usuario. No impide la captura de
// pantalla, pero deja identificada cualquier foto que se reenvíe.
//
// variante "visor" (por defecto, la de siempre): capa absoluta sobre el mapa del geoportal.
// variante "fija": capa FIJA tenue y sin clics (Dashboard y secciones en pantalla completa). Con `area` se ajusta a la parte VISIBLE de ese elemento
// (su rectángulo recortado a la ventana; se recalcula al desplazar o cambiar de tamaño, sin volver a renderizar), de modo que cualquier captura sale marcada
// y no solo el primer alto de ventana; sin `area` cubre la ventana (el elemento en pantalla completa).
export function Watermark({ email, variante = "visor", area }: { email: string; variante?: "visor" | "fija"; area?: RefObject<HTMLElement | null> }) {
  const sello = `${email} · ${new Date().toLocaleDateString("es-CO")}`;
  const filas = Array.from({ length: 8 });
  const capa = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (variante !== "fija" || !area) return;
    let raf = 0;
    const medir = () => {
      raf = 0;
      const el = area.current, d = capa.current;
      if (!el || !d) return;
      const r = el.getBoundingClientRect();
      const arriba = Math.max(0, r.top), izq = Math.max(0, r.left);
      const abajo = Math.min(window.innerHeight, r.bottom), der = Math.min(window.innerWidth, r.right);
      d.style.top = `${arriba}px`;
      d.style.left = `${izq}px`;
      d.style.width = `${Math.max(0, der - izq)}px`;
      d.style.height = `${Math.max(0, abajo - arriba)}px`;
    };
    const pedir = () => { if (!raf) raf = requestAnimationFrame(medir); };
    medir();
    window.addEventListener("scroll", pedir, true);   // en captura: también el desplazamiento de cualquier contenedor interno
    window.addEventListener("resize", pedir);
    const ro = new ResizeObserver(pedir);
    if (area.current) ro.observe(area.current);
    return () => {
      if (raf) cancelAnimationFrame(raf);
      window.removeEventListener("scroll", pedir, true);
      window.removeEventListener("resize", pedir);
      ro.disconnect();
    };
  }, [variante, area]);

  return (
    <div ref={capa} className={variante === "fija" ? "watermark watermark-fija" : "watermark"} aria-hidden="true">
      {filas.map((_, i) => (
        <div className="watermark-fila" key={i}>
          {Array.from({ length: 6 }).map((__, j) => (
            <span key={j}>{sello}</span>
          ))}
        </div>
      ))}
    </div>
  );
}
