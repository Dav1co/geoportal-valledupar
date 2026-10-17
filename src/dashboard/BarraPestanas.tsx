import { useEffect, useRef, useState } from "react";

// Barra de pestañas del dashboard: cuadrícula alineada de 2 filas dentro de un contenedor con desplazamiento horizontal (sin barra visible).
//   A: «Resumen ejecutivo» a doble alto  |  B, C, D: consolidadas (fila 1) y desagregadas (fila 2)  |  E, F, G: PQR, Notas, Cupones (fila 1)
//   y Recaudo diario, Pérdidas, Consolidado (fila 2). Columnas de la cuadrícula: 1 = A, 2 = espacio, 3 a 5 = B a D, 6 = línea de
//   separación, 7 a 9 = E a G. Cada columna mide lo que mide su rótulo más ancho. El orden del DOM (y del teclado) es el de lectura:
//   fila por fila. La pestaña activa se mantiene a la vista (solo se desplaza la barra, nunca la página).
type Celda = { col: number; fila: number; filas?: number };
const CELDAS: Record<string, Celda> = {
  "resumen": { col: 1, fila: 1, filas: 2 },
  "facturacion-agrupado": { col: 3, fila: 1 }, "recaudo-agrupado": { col: 4, fila: 1 }, "cartera-agrupado": { col: 5, fila: 1 },
  "facturacion-detallado": { col: 3, fila: 2 }, "recaudo-detallado": { col: 4, fila: 2 }, "cartera-detallado": { col: 5, fila: 2 },
  "pqr": { col: 7, fila: 1 }, "notas": { col: 8, fila: 1 }, "cupones": { col: 9, fila: 1 },
  "recaudo-diario": { col: 7, fila: 2 }, "perdidas": { col: 8, fila: 2 }, "consolidado": { col: 9, fila: 2 },
};

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

  // Una pantalla nueva que no esté en el mapa se agrega en columnas siguientes, de a dos por columna.
  let extra = 0;
  const celdas = paginas
    .map((p) => ({ p, c: CELDAS[p.id] ?? { col: 11 + Math.floor(extra / 2), fila: 1 + (extra++ % 2) } }))
    .sort((a, b) => a.c.fila - b.c.fila || a.c.col - b.c.col);
  return (
    <nav ref={nav} onScroll={medir} className={`dash-nav${borde.izq ? " hay-izq" : ""}${borde.der ? " hay-der" : ""}`}>
      <div className="dash-nav-pista">
        <span className="dash-nav-sep" aria-hidden="true" />
        {celdas.map(({ p, c }) => (
          <button
            key={p.id}
            className={`${activa === p.id ? "activa" : ""}${c.filas ? " doble" : ""}`.trim()}
            aria-current={activa === p.id ? "page" : undefined}
            style={{ gridColumn: c.col, gridRow: c.filas ? `${c.fila} / span ${c.filas}` : c.fila }}
            onClick={() => onCambio(p.id)}
          >
            {p.titulo}
          </button>
        ))}
      </div>
    </nav>
  );
}
