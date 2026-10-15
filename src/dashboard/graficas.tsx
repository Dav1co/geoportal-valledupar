import { useRef, useState, type MouseEvent, type ReactNode } from "react";

// Gráficas SVG del tablero — sin dependencias externas.
// Identidad del mockup: paleta fija de años, sin etiquetas de datos
// sobre las barras, grid suave solo en Y, leyenda siempre presente.
// REGLA DEL TABLERO: toda gráfica lleva su tabla de datos (la gráfica
// da la lectura visual; la tabla, la cifra exacta) y el valor exacto
// aparece al pasar el cursor — nunca etiquetas fijas sobre las barras.

// Paleta de años del mockup, asignada por distancia al año más reciente
// (2026=tinta, 2025=celeste, 2024=ocre, 2023=gris). Así 2027 heredará
// tinta sin reciclar tonos dentro de una misma vista.
const COLORES_ANIO = ["#0A2540", "#4FA3C7", "#C98A2D", "#9AA7B5"];

export function colorAnio(anio: number, anioMax: number): string {
  const d = anioMax - anio;
  return COLORES_ANIO[Math.min(d, COLORES_ANIO.length - 1)];
}

// Tinta: reservada para la serie protagonista de una comparación (el
// período elegido, o el mes en curso). El resto de la paleta queda
// para las series de referencia.
export const COLOR_PROTAGONISTA = COLORES_ANIO[0];
const COLORES_FONDO = COLORES_ANIO.slice(1); // celeste, ocre, gris

// Color de una serie de referencia dentro de una misma vista, con
// `reciente` = 0 para la más cercana al presente. Recorre la paleta del
// mockup y, cuando hay más series que tonos, da otra vuelta aclarando
// hacia el blanco: así cada serie conserva un color propio sin
// introducir colores nuevos. El alfa las deja traslúcidas, para que se
// lean como fondo y no compitan con la protagonista.
export function colorReferencia(reciente: number, alfa = 0.75): string {
  const base = COLORES_FONDO[reciente % COLORES_FONDO.length];
  const vuelta = Math.floor(reciente / COLORES_FONDO.length);
  const mezcla = Math.min(0.5, 0.3 * vuelta);
  const claro = (c: number) => Math.round(c + (255 - c) * mezcla);
  const [r, g, b] = [1, 3, 5].map((i) => claro(parseInt(base.slice(i, i + 2), 16)));
  return `rgba(${r}, ${g}, ${b}, ${alfa})`;
}

export const MESES_CORTO = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"];

// ---------- tooltip compartido ----------
type Tip = { x: number; y: number; titulo: string; valor: string };

function useTip() {
  const ref = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<Tip | null>(null);
  const mover = (e: MouseEvent, titulo: string, valor: string) => {
    const caja = ref.current?.getBoundingClientRect();
    if (!caja) return;
    setTip({ x: e.clientX - caja.left, y: e.clientY - caja.top, titulo, valor });
  };
  const salir = () => setTip(null);
  return { ref, tip, mover, salir };
}

function CapaTip({ tip }: { tip: Tip | null }) {
  if (!tip) return null;
  return (
    <div className="dash-tooltip" style={{ left: tip.x + 12, top: tip.y - 34 }}>
      <span>{tip.titulo}</span>
      <b className="num">{tip.valor}</b>
    </div>
  );
}

// ---------- tabla de datos plegable (estándar del tablero) ----------
// <details> nativo: visible por defecto, plegable sin JS, contenido
// seleccionable y copiable tal cual hacia Excel o correo.
export function TablaPlegable({ titulo = "Datos de la gráfica", children }: { titulo?: string; children: ReactNode }) {
  return (
    <details className="dash-detalle" open>
      <summary>{titulo}</summary>
      <div className="dash-tabla-scroll">{children}</div>
    </details>
  );
}

// ---------- barras mensuales agrupadas por año ----------
type Serie = { nombre: string; color: string; valores: (number | null)[] }; // 12 meses

type BarrasProps = {
  series: Serie[]; // en orden fijo (año ascendente)
  formatoY: (v: number) => string;
  formatoTitulo: (v: number) => string;
  alto?: number;
};

export function BarrasMensuales({ series, formatoY, formatoTitulo, alto = 280 }: BarrasProps) {
  const { ref, tip, mover, salir } = useTip();
  const ancho = 720;
  const m = { izq: 52, der: 6, arr: 8, aba: 22 };
  const plotW = ancho - m.izq - m.der;
  const plotH = alto - m.arr - m.aba;
  const max = Math.max(1, ...series.flatMap((s) => s.valores.filter((v): v is number => v != null)));
  const escY = (v: number) => m.arr + plotH * (1 - v / (max * 1.05));
  const grupoW = plotW / 12;
  const nBar = Math.max(1, series.length);
  const barW = Math.max(3, (grupoW - 8) / nBar - 2); // 2px de aire entre barras
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => max * 1.05 * f);

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {ticks.map((t, i) => (
          <g key={i}>
            <line x1={m.izq} x2={ancho - m.der} y1={escY(t)} y2={escY(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={escY(t) + 3.5} textAnchor="end" fontSize={10} fill="#5D6E7E">
              {formatoY(t)}
            </text>
          </g>
        ))}
        {MESES_CORTO.map((mes, i) => (
          <text
            key={mes}
            x={m.izq + grupoW * i + grupoW / 2}
            y={alto - 6}
            textAnchor="middle"
            fontSize={10}
            fill="#5D6E7E"
          >
            {mes}
          </text>
        ))}
        {series.map((s, si) =>
          s.valores.map((v, mi) => {
            if (v == null) return null;
            const x = m.izq + grupoW * mi + 4 + si * (barW + 2);
            const y = escY(v);
            return (
              <rect
                key={`${s.nombre}-${mi}`}
                x={x}
                y={y}
                width={barW}
                height={m.arr + plotH - y}
                rx={2}
                fill={s.color}
                onMouseMove={(e) => mover(e, `${MESES_CORTO[mi]} ${s.nombre}`, formatoTitulo(v))}
              />
            );
          }),
        )}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        {series.map((s) => (
          <span key={s.nombre}>
            <i style={{ background: s.color }} /> {s.nombre}
          </span>
        ))}
      </div>
    </div>
  );
}

// ---------- líneas de porcentaje sobre una serie de períodos ----------
// Eje Y AJUSTADO al rango observado (no forzado a 0–100): la
// composición del recaudo se mueve en bandas estrechas y un eje 0–100
// aplastaría el movimiento que la gráfica debe mostrar.
type SerieLinea = { nombre: string; color: string; valores: (number | null)[] };

export function LineasPorcentaje({
  etiquetas,
  series,
  alto = 300,
  formatoTick = (t) => `${t.toLocaleString("es-CO", { maximumFractionDigits: 0 })} %`,
  formatoValor = (v) => `${v.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`,
  tituloY,
  sinTope = false,
  paso = 5,
}: {
  etiquetas: string[];
  series: SerieLinea[];
  alto?: number;
  // Por defecto la gráfica es de porcentajes (eje 0–100, ticks y tooltip con "%").
  // Para otra unidad (p. ej. IPUF en m³/susc·mes): formatos propios, sin tope de 100,
  // y `paso` = múltiplo al que se redondean los límites del eje.
  formatoTick?: (t: number) => string;
  formatoValor?: (v: number) => string;
  tituloY?: string;
  sinTope?: boolean;
  paso?: number;
}) {
  const { ref, tip, mover, salir } = useTip();
  const ancho = 720;
  const m = { izq: 44, der: 10, arr: tituloY ? 24 : 10, aba: 30 };
  const plotW = ancho - m.izq - m.der;
  const plotH = alto - m.arr - m.aba;
  const vals = series.flatMap((s) => s.valores.filter((v): v is number => v != null));
  const crudoMin = Math.min(...vals), crudoMax = Math.max(...vals);
  const margen = Math.max(1, (crudoMax - crudoMin) * 0.15);
  const min = Math.max(0, Math.floor((crudoMin - margen) / paso) * paso);
  const max = Math.min(sinTope ? Infinity : 100, Math.ceil((crudoMax + margen) / paso) * paso);
  const escX = (i: number) =>
    m.izq + (etiquetas.length <= 1 ? plotW / 2 : (plotW * i) / (etiquetas.length - 1));
  const escY = (v: number) => m.arr + plotH * (1 - (v - min) / (max - min || 1));
  const ticks = Array.from({ length: 5 }, (_, i) => min + ((max - min) * i) / 4);
  const pasoX = Math.max(1, Math.ceil(etiquetas.length / 12));

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {tituloY ? (
          <text x={m.izq - 6} y={11} fontSize={10} fill="#5D6E7E">{tituloY}</text>
        ) : null}
        {ticks.map((t, i) => (
          <g key={i}>
            <line x1={m.izq} x2={ancho - m.der} y1={escY(t)} y2={escY(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={escY(t) + 3.5} textAnchor="end" fontSize={10} fill="#5D6E7E">
              {formatoTick(t)}
            </text>
          </g>
        ))}
        {etiquetas.map((e, i) =>
          i % pasoX === 0 ? (
            <text key={e} x={escX(i)} y={alto - 8} textAnchor="middle" fontSize={9.5} fill="#5D6E7E">
              {e}
            </text>
          ) : null,
        )}
        {series.map((s) => {
          const d = s.valores
            .map((v, i) => (v == null ? null : `${escX(i)},${escY(v)}`))
            .filter(Boolean)
            .map((p, i) => (i === 0 ? `M ${p}` : `L ${p}`))
            .join(" ");
          return <path key={s.nombre} d={d} fill="none" stroke={s.color} strokeWidth={2} />;
        })}
        {/* capa de puntos: objetivo de hover más grande que la marca */}
        {series.map((s) =>
          s.valores.map((v, i) =>
            v == null ? null : (
              <circle
                key={`${s.nombre}-${i}`}
                cx={escX(i)}
                cy={escY(v)}
                r={9}
                fill="transparent"
                onMouseMove={(e) =>
                  mover(e, `${etiquetas[i]} · ${s.nombre}`, formatoValor(v))
                }
              />
            ),
          ),
        )}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        {series.map((s) => (
          <span key={s.nombre}>
            <i style={{ background: s.color }} /> {s.nombre}
          </span>
        ))}
      </div>
    </div>
  );
}

// ---------- líneas por día del mes (comparación entre períodos) ----------
// Eje X = día del mes (1..31), así que meses distintos se superponen y
// se comparan al mismo día. Es la forma correcta de comparar un mes en
// curso contra meses cerrados: al mismo día de corte, no al final.
// Tres props opcionales, todas con el render de siempre por defecto:
//   destacada : nombre de la serie protagonista. Se dibuja sólida, gruesa
//               y por encima; las demás pasan a punteadas y finas, para
//               que se lean como referencia de fondo.
//   ocultas   : series apagadas. Salen del dibujo Y del cálculo del
//               máximo, así que el eje se reajusta al encender y apagar.
//   onToggle  : hace la leyenda interactiva. Sin ella la leyenda es
//               estática, como antes.
export function LineasPorDia({
  series,
  formatoValor,
  formatoEjeY,
  alto = 300,
  diaCorte,
  destacada,
  ocultas,
  onToggle,
}: {
  series: { nombre: string; color: string; valores: (number | null)[] }[]; // índice 0 = día 1
  formatoValor: (v: number) => string;
  formatoEjeY: (v: number) => string;
  alto?: number;
  diaCorte?: number | null;
  destacada?: string;
  ocultas?: string[];
  onToggle?: (nombre: string) => void;
}) {
  const { ref, tip, mover, salir } = useTip();
  const ancho = 720;
  const m = { izq: 56, der: 10, arr: 10, aba: 26 };
  const plotW = ancho - m.izq - m.der;
  const plotH = alto - m.arr - m.aba;
  const apagada = (n: string) => (ocultas ?? []).includes(n);
  const visibles = series.filter((s) => !apagada(s.nombre));
  // Orden de pintado: la destacada al final, para que quede encima.
  const enOrden = [...visibles].sort(
    (a, b) => Number(a.nombre === destacada) - Number(b.nombre === destacada),
  );
  const dias = Math.max(...series.map((s) => s.valores.length), 1);
  const vals = visibles.flatMap((s) => s.valores.filter((v): v is number => v != null));
  const max = Math.max(1, ...vals);
  const escX = (i: number) => m.izq + (plotW * i) / Math.max(1, dias - 1);
  const escY = (v: number) => m.arr + plotH * (1 - v / (max * 1.05));
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => max * 1.05 * f);

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {ticks.map((t, i) => (
          <g key={i}>
            <line x1={m.izq} x2={ancho - m.der} y1={escY(t)} y2={escY(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={escY(t) + 3.5} textAnchor="end" fontSize={10} fill="#5D6E7E">
              {formatoEjeY(t)}
            </text>
          </g>
        ))}
        {Array.from({ length: dias }, (_, i) => i).map((i) =>
          (i + 1) % 5 === 0 || i === 0 ? (
            <text key={i} x={escX(i)} y={alto - 8} textAnchor="middle" fontSize={9.5} fill="#5D6E7E">
              {i + 1}
            </text>
          ) : null,
        )}
        {diaCorte != null && diaCorte < dias && (
          <line
            x1={escX(diaCorte - 1)} x2={escX(diaCorte - 1)}
            y1={m.arr} y2={m.arr + plotH}
            stroke="#B3402A" strokeWidth={1} strokeDasharray="4 3"
          />
        )}
        {enOrden.map((s) => {
          const esta = destacada != null && s.nombre === destacada;
          const fondo = destacada != null && !esta;
          const d = s.valores
            .map((v, i) => (v == null ? null : `${escX(i)},${escY(v)}`))
            .filter(Boolean)
            .map((p, i) => (i === 0 ? `M ${p}` : `L ${p}`))
            .join(" ");
          return (
            <path
              key={s.nombre}
              d={d}
              fill="none"
              stroke={s.color}
              strokeWidth={esta ? 3 : fondo ? 1.5 : 2}
              strokeDasharray={fondo ? "5 4" : undefined}
              strokeLinecap="round"
            />
          );
        })}
        {enOrden.map((s) =>
          s.valores.map((v, i) =>
            v == null ? null : (
              <circle
                key={`${s.nombre}-${i}`}
                cx={escX(i)} cy={escY(v)} r={8}
                fill="transparent"
                onMouseMove={(e) => mover(e, `Día ${i + 1} · ${s.nombre}`, formatoValor(v))}
              />
            ),
          ),
        )}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        {series.map((s) => {
          const off = apagada(s.nombre);
          const contenido = (
            <>
              <i style={{ background: s.color, opacity: off ? 0.25 : 1 }} />
              {s.nombre}
            </>
          );
          return onToggle ? (
            <button
              key={s.nombre}
              type="button"
              className={`dash-leyenda-btn${off ? " off" : ""}`}
              onClick={() => onToggle(s.nombre)}
              aria-pressed={!off}
              title={off ? `Mostrar ${s.nombre}` : `Ocultar ${s.nombre}`}
            >
              {contenido}
            </button>
          ) : (
            <span key={s.nombre}>{contenido}</span>
          );
        })}
      </div>
    </div>
  );
}

// ---------- barras horizontales (categorías con etiqueta larga) ----------
export function BarrasHorizontales({
  datos,
  formatoValor,
  color = "#0A2540",
}: {
  datos: { etiqueta: string; valor: number }[];
  formatoValor: (v: number) => string;
  color?: string;
}) {
  const { ref, tip, mover, salir } = useTip();
  const filaH = 20, gap = 4;
  const ancho = 720, izq = 86, der = 12;
  const alto = Math.max(60, datos.length * (filaH + gap) + 10);
  const max = Math.max(1, ...datos.map((d) => Math.abs(d.valor)));
  const escala = (v: number) => (Math.abs(v) / max) * (ancho - izq - der);

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {datos.map((d, i) => {
          const y = i * (filaH + gap) + 5;
          return (
            <g key={d.etiqueta}>
              <text x={izq - 8} y={y + filaH / 2 + 3.5} textAnchor="end" fontSize={10.5} fill="#5D6E7E">
                {d.etiqueta}
              </text>
              <rect
                x={izq}
                y={y}
                width={Math.max(2, escala(d.valor))}
                height={filaH}
                rx={2}
                fill={color}
                onMouseMove={(e) => mover(e, d.etiqueta, formatoValor(d.valor))}
              />
            </g>
          );
        })}
      </svg>
      <CapaTip tip={tip} />
    </div>
  );
}

// ---------- barras horizontales apiladas ----------
// Una fila por categoría (p. ej. ciclo) con los valores de cada serie uno
// a continuación del otro (p. ej. contratos con y sin medidor). Mismo
// trazo, tooltip y leyenda que las barras horizontales simples.
export function BarrasApiladas({
  datos,
  series,
  formatoValor,
  margenIzq = 86,
}: {
  datos: { etiqueta: string; valores: number[] }[]; // un valor por serie, en su orden
  series: { nombre: string; color: string }[];
  formatoValor: (v: number) => string;
  margenIzq?: number;   // ancho reservado a las etiquetas (más si son textos largos)
}) {
  const { ref, tip, mover, salir } = useTip();
  const filaH = 20, gap = 4;
  const ancho = 720, izq = margenIzq, der = 12;
  const alto = Math.max(60, datos.length * (filaH + gap) + 10);
  const max = Math.max(1, ...datos.map((d) => d.valores.reduce((s, v) => s + Math.max(0, v), 0)));
  const escala = (v: number) => (Math.max(0, v) / max) * (ancho - izq - der);

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {datos.map((d, i) => {
          const y = i * (filaH + gap) + 5;
          let x = izq;
          return (
            <g key={d.etiqueta}>
              <text x={izq - 8} y={y + filaH / 2 + 3.5} textAnchor="end" fontSize={10.5} fill="#5D6E7E">
                {d.etiqueta}
              </text>
              {series.map((s, k) => {
                const w = escala(d.valores[k] ?? 0);
                const x0 = x;
                x += w;
                return w > 0 ? (
                  <rect
                    key={s.nombre}
                    x={x0}
                    y={y}
                    width={w}
                    height={filaH}
                    fill={s.color}
                    onMouseMove={(e) => mover(e, `${d.etiqueta} · ${s.nombre}`, formatoValor(d.valores[k] ?? 0))}
                  />
                ) : null;
              })}
            </g>
          );
        })}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        {series.map((s) => (
          <span key={s.nombre}>
            <i style={{ background: s.color }} /> {s.nombre}
          </span>
        ))}
      </div>
    </div>
  );
}

// ---------- barras en pareja (dos participaciones por categoría) ----------
// Una fila por categoría con DOS barras finas en la misma escala de porcentaje
// (p. ej. % de contratos y % del volumen por rango de consumo), cada una con su
// cifra al final. Sirve para ver cuándo una categoría pesa más en una medida que
// en la otra.
export function BarrasPareja({
  datos,
  nombreA,
  nombreB,
  colorA = "#0A2540",
  colorB = "#C98A2D",
  margenIzq = 70,
}: {
  datos: { etiqueta: string; a: number; b: number; textoA: string; textoB: string }[];
  nombreA: string;
  nombreB: string;
  colorA?: string;
  colorB?: string;
  margenIzq?: number;
}) {
  const { ref, tip, mover, salir } = useTip();
  const barH = 10, gapBar = 2, gapFila = 8;
  const filaH = barH * 2 + gapBar;
  const ancho = 720, izq = margenIzq, der = 96;
  const alto = Math.max(60, datos.length * (filaH + gapFila) + 8);
  const max = Math.max(1, ...datos.flatMap((d) => [d.a, d.b]));
  const escala = (v: number) => (Math.max(0, v) / max) * (ancho - izq - der);

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {datos.map((d, i) => {
          const y = i * (filaH + gapFila) + 4;
          return (
            <g key={d.etiqueta}>
              <text x={izq - 8} y={y + filaH / 2 + 3.5} textAnchor="end" fontSize={10.5} fill="#5D6E7E">
                {d.etiqueta}
              </text>
              <rect x={izq} y={y} width={Math.max(2, escala(d.a))} height={barH} rx={2} fill={colorA}
                    onMouseMove={(e) => mover(e, `${d.etiqueta} · ${nombreA}`, d.textoA)} />
              <text x={izq + Math.max(2, escala(d.a)) + 5} y={y + barH - 1.5} fontSize={9.5} fill="#5D6E7E" className="num">
                {d.textoA}
              </text>
              <rect x={izq} y={y + barH + gapBar} width={Math.max(2, escala(d.b))} height={barH} rx={2} fill={colorB}
                    onMouseMove={(e) => mover(e, `${d.etiqueta} · ${nombreB}`, d.textoB)} />
              <text x={izq + Math.max(2, escala(d.b)) + 5} y={y + barH * 2 + gapBar - 1.5} fontSize={9.5} fill="#5D6E7E" className="num">
                {d.textoB}
              </text>
            </g>
          );
        })}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        <span><i style={{ background: colorA }} /> {nombreA}</span>
        <span><i style={{ background: colorB }} /> {nombreB}</span>
      </div>
    </div>
  );
}

// ---------- barras anuales con referencias ----------
// Una barra por año (p. ej. IPUF anual) con una línea de META que sigue a cada
// año, una línea punteada de ESTÁNDAR y, opcionalmente, barras PARCIALES
// (menos de 12 meses) dibujadas más claras y con borde punteado.
export function BarrasAnuales({
  datos,
  estandar,
  formatoValor,
  formatoCorto,
  tituloY,
  nombreValor = "Valor",
  nombreMeta = "Meta",
  nombreEstandar = "Estándar",
  color = "#0A2540",
  colorMeta = "#C98A2D",
  colorEstandar = "#9AA7B5",
  alto = 230,
}: {
  datos: { etiqueta: string; etiquetaLarga?: string; valor: number | null; meta?: number | null; parcial?: boolean }[];
  estandar?: number | null;
  formatoValor: (v: number) => string;   // tooltip
  formatoCorto: (v: number) => string;   // sobre la barra
  tituloY?: string;
  nombreValor?: string;
  nombreMeta?: string;
  nombreEstandar?: string;
  color?: string;
  colorMeta?: string;
  colorEstandar?: string;
  alto?: number;
}) {
  const { ref, tip, mover, salir } = useTip();
  const ancho = 720;
  const m = { izq: 44, der: 10, arr: tituloY ? 24 : 12, aba: 30 };
  const plotW = ancho - m.izq - m.der;
  const plotH = alto - m.arr - m.aba;
  const crudo = Math.max(
    1,
    ...datos.flatMap((d) => [d.valor ?? 0, d.meta ?? 0]),
    estandar ?? 0,
  );
  // Escala "bonita": hasta 5 marcas, con 12 % de aire para la cifra sobre la barra.
  const paso = [1, 2, 5, 10, 20, 50, 100].find((p) => (crudo * 1.12) / p <= 5) ?? 100;
  const max = Math.ceil((crudo * 1.12) / paso) * paso;
  const escY = (v: number) => m.arr + plotH * (1 - v / max);
  const ticks = Array.from({ length: Math.round(max / paso) + 1 }, (_, i) => i * paso);
  const slot = plotW / Math.max(1, datos.length);
  const barW = Math.min(46, slot * 0.62);
  const cx = (i: number) => m.izq + slot * (i + 0.5);
  const puntosMeta = datos
    .map((d, i) => (d.meta != null ? `${cx(i)},${escY(d.meta)}` : null))
    .filter(Boolean)
    .join(" ");

  return (
    <div ref={ref} className="dash-grafica" onMouseLeave={salir}>
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {tituloY ? <text x={m.izq - 6} y={11} fontSize={10} fill="#5D6E7E">{tituloY}</text> : null}
        {ticks.map((t) => (
          <g key={t}>
            <line x1={m.izq} x2={ancho - m.der} y1={escY(t)} y2={escY(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={escY(t) + 3.5} textAnchor="end" fontSize={10} fill="#5D6E7E">
              {t.toLocaleString("es-CO", { maximumFractionDigits: 0 })}
            </text>
          </g>
        ))}
        {datos.map((d, i) =>
          d.valor == null ? null : (
            <g key={d.etiqueta}>
              <rect
                x={cx(i) - barW / 2}
                y={escY(d.valor)}
                width={barW}
                height={Math.max(1, escY(0) - escY(d.valor))}
                rx={2}
                fill={color}
                fillOpacity={d.parcial ? 0.4 : 1}
                stroke={d.parcial ? color : "none"}
                strokeDasharray={d.parcial ? "4 3" : undefined}
                onMouseMove={(e) => mover(e, `${d.etiquetaLarga ?? d.etiqueta} · ${nombreValor}`, formatoValor(d.valor!))}
              />
              <text x={cx(i)} y={escY(d.valor) - 5} textAnchor="middle" fontSize={10} fill="#0A2540" className="num">
                {formatoCorto(d.valor)}
              </text>
            </g>
          ),
        )}
        {estandar != null ? (
          <line x1={m.izq} x2={ancho - m.der} y1={escY(estandar)} y2={escY(estandar)}
                stroke={colorEstandar} strokeWidth={1.5} strokeDasharray="5 4" />
        ) : null}
        {puntosMeta ? <polyline points={puntosMeta} fill="none" stroke={colorMeta} strokeWidth={2} /> : null}
        {datos.map((d, i) =>
          d.meta == null ? null : (
            <circle key={`m-${d.etiqueta}`} cx={cx(i)} cy={escY(d.meta)} r={4} fill={colorMeta} stroke="#fff" strokeWidth={1}
                    onMouseMove={(e) => mover(e, `${d.etiquetaLarga ?? d.etiqueta} · ${nombreMeta}`, formatoValor(d.meta!))} />
          ),
        )}
        {datos.map((d, i) => (
          <text key={`x-${d.etiqueta}`} x={cx(i)} y={alto - 10} textAnchor="middle" fontSize={9.5} fill="#5D6E7E">
            {d.etiqueta}
          </text>
        ))}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda">
        <span><i style={{ background: color }} /> {nombreValor}</span>
        <span><i style={{ background: colorMeta }} /> {nombreMeta}</span>
        {estandar != null && <span><i style={{ background: colorEstandar }} /> {nombreEstandar}</span>}
        {datos.some((d) => d.parcial) && (
          <span><i style={{ background: color, opacity: 0.4 }} /> Año parcial (menos de 12 meses)</span>
        )}
      </div>
    </div>
  );
}

// ---------- dona ----------
type Parte = { etiqueta: string; valor: number; color: string; pct: number | null };

// Corte 58% (mockup) y anillo blanco de 2px entre porciones. La
// identidad no descansa solo en el color: la leyenda trae etiqueta y %.
export function Dona({ partes, formatoTitulo }: { partes: Parte[]; formatoTitulo: (v: number) => string }) {
  const { ref, tip, mover, salir } = useTip();
  const R = 100, r = 58, cx = 110, cy = 110;
  const total = partes.reduce((s, p) => s + Math.max(0, p.valor), 0);
  let ang = -Math.PI / 2;
  const arcos = partes.map((p) => {
    const frac = total > 0 ? Math.max(0, p.valor) / total : 0;
    const a0 = ang, a1 = ang + frac * Math.PI * 2;
    ang = a1;
    const grande = a1 - a0 > Math.PI ? 1 : 0;
    const punto = (a: number, rad: number) => `${cx + rad * Math.cos(a)},${cy + rad * Math.sin(a)}`;
    const d =
      `M ${punto(a0, R)} A ${R} ${R} 0 ${grande} 1 ${punto(a1, R)} ` +
      `L ${punto(a1, r)} A ${r} ${r} 0 ${grande} 0 ${punto(a0, r)} Z`;
    return { ...p, d };
  });
  return (
    <div ref={ref} className="dash-grafica dash-dona" onMouseLeave={salir}>
      <svg viewBox="0 0 220 220" style={{ width: "min(220px, 100%)", height: "auto" }} role="img">
        {arcos.map((a) => (
          <path
            key={a.etiqueta}
            d={a.d}
            fill={a.color}
            stroke="#fff"
            strokeWidth={2}
            onMouseMove={(e) => mover(e, a.etiqueta, formatoTitulo(a.valor))}
          />
        ))}
      </svg>
      <CapaTip tip={tip} />
      <div className="dash-leyenda dash-leyenda-col">
        {partes.map((p) => (
          <span key={p.etiqueta}>
            <i style={{ background: p.color }} /> {p.etiqueta}
            {p.pct != null && <b className="num"> {p.pct.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %</b>}
          </span>
        ))}
      </div>
    </div>
  );
}
