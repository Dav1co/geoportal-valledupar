import { useEffect, useRef, useState } from "react";

// Barra de pestañas del dashboard: dos líneas fijas dentro de un mismo contenedor con desplazamiento horizontal compartido (las dos
// líneas se mueven juntas). Sin barra de desplazamiento visible; con rueda, gesto táctil o arrastre del trackpad. La pestaña activa se
// mantiene a la vista (solo se desplaza la barra, nunca la página).
const LINEA_1 = new Set<string>([
  "resumen", "facturacion-agrupado", "recaudo-agrupado", "cartera-agrupado", "facturacion-detallado", "recaudo-detallado", "cartera-detallado",
]);

export function BarraPestanas<T extends string>({ paginas, activa, onCambio }: {
  paginas: readonly { id: T; titulo: string }[]; activa: T; onCambio: (id: T) => void;
}) {
  const nav = useRef<HTMLElement>(null);
  const primera = useRef(true);
  const [borde, setBorde] = useState({ izq: false, der: false });

  // Qué lados tienen contenido fuera de vista (para el desvanecido de los bordes).
  function medir() {
    const n = nav.current;
    if (!n) return;
    const izq = n.scrollLeft > 1, der = n.scrollLeft + n.clientWidth < n.scrollWidth - 1;
    setBorde((b) => (b.izq === izq && b.der === der ? b : { izq, der }));
  }
  // Deja la pestaña activa a la vista, centrada si hace falta. Solo mueve el scroll horizontal de la barra.
  function mostrarActiva(suave: boolean) {
    const n = nav.current, b = n?.querySelector<HTMLElement>("button.activa");
    if (!n || !b) return;
    const rn = n.getBoundingClientRect(), rb = b.getBoundingClientRect(), margen = 24;
    if (rb.left >= rn.left + margen && rb.right <= rn.right - margen) return;
    n.scrollTo({ left: Math.max(0, n.scrollLeft + (rb.left - rn.left) - (rn.width - rb.width) / 2), behavior: suave ? "smooth" : "auto" });
  }

  useEffect(() => { mostrarActiva(!primera.current); primera.current = false; medir(); }, [activa]);   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const n = nav.current;
    if (!n) return;
    const alCambiarTamano = () => { mostrarActiva(false); medir(); };
    // Con un ratón, la rueda vertical sobre la barra la desplaza de lado (solo si hay contenido fuera de vista y no se llegó al extremo).
    const alRueda = (e: WheelEvent) => {
      if (n.scrollWidth <= n.clientWidth || Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
      const max = n.scrollWidth - n.clientWidth;
      if ((e.deltaY > 0 && n.scrollLeft >= max - 1) || (e.deltaY < 0 && n.scrollLeft <= 0)) return;
      e.preventDefault();
      n.scrollLeft += e.deltaY;
    };
    n.addEventListener("wheel", alRueda, { passive: false });
    window.addEventListener("resize", alCambiarTamano);
    medir();
    return () => { n.removeEventListener("wheel", alRueda); window.removeEventListener("resize", alCambiarTamano); };
  }, []);

  const linea1 = paginas.filter((p) => LINEA_1.has(p.id)), linea2 = paginas.filter((p) => !LINEA_1.has(p.id));
  return (
    <nav ref={nav} onScroll={medir} className={`dash-nav${borde.izq ? " hay-izq" : ""}${borde.der ? " hay-der" : ""}`}>
      <div className="dash-nav-pista">
        {[linea1, linea2].map((linea, i) => (
          <div className="dash-nav-fila" key={i}>
            {linea.map((p) => (
              <button key={p.id} className={activa === p.id ? "activa" : ""} aria-current={activa === p.id ? "page" : undefined} onClick={() => onCambio(p.id)}>
                {p.titulo}
              </button>
            ))}
          </div>
        ))}
      </div>
    </nav>
  );
}
