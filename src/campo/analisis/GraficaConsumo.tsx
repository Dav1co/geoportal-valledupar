import { escalaY, m3, tramosLinea, type FilaGrafica } from "./logica";

// Gráfica de consumo del análisis de contrato: SVG propio, en el estilo de las gráficas del Tablero (dashboard/graficas.tsx): grid suave solo en Y, sin etiquetas sobre las barras,
// leyenda siempre presente y la tabla debajo (la pone AnalisisContrato). Pensada para leerse a 390 px.
// - Barras: m³ del contrato. Mes con lectura real = barra llena; mes estimado = barra hueca (solo el contorno) y «estimado» en la tabla.
// - Líneas: promedio del estrato (rayas) y del barrio (puntos). El mes sin dato de la fuente queda vacío, con el rótulo «sin dato», y las líneas se cortan ahí: no se inventa.
const TINTA = "#0A2540";       // serie protagonista (la del contrato)
const OCRE = "#C98A2D";        // promedio del estrato
const CELESTE = "#2F7FA3";     // promedio del barrio (un poco más oscuro que el celeste del tablero para que la línea punteada se lea sobre blanco)
const GRIS = "#5D6E7E";

export function GraficaConsumo({ filas, grupoEstrato, grupoBarrio }: { filas: FilaGrafica[]; grupoEstrato: string | null; grupoBarrio: string | null }) {
  const ancho = 360, alto = 210;
  const m = { izq: 34, der: 8, arr: 16, aba: 34 };
  const plotW = ancho - m.izq - m.der, plotH = alto - m.arr - m.aba;
  const n = Math.max(1, filas.length);
  const slot = plotW / n;
  const barW = Math.min(30, slot * 0.52);
  const { max, ticks } = escalaY(filas.flatMap((f) => [f.m3, f.estrato, f.barrio]));
  const y = (v: number) => m.arr + plotH * (1 - v / max);
  const cx = (i: number) => m.izq + slot * i + slot / 2;
  const base = m.arr + plotH;
  const linea = (valores: (number | null)[]) => tramosLinea(valores).map((t) => t.map((p) => `${cx(p.i).toFixed(1)},${y(p.v).toFixed(1)}`).join(" "));
  const hayEstrato = filas.some((f) => f.estrato !== null), hayBarrio = filas.some((f) => f.barrio !== null), hayEstimado = filas.some((f) => f.estimado), haySinDato = filas.some((f) => f.sinDato);
  const resumen = filas.map((f) => `${f.etiqueta}: ${f.sinDato ? "sin dato" : `${m3(f.m3)} m³${f.estimado ? " estimado" : ""}`}`).join("; ");

  return (
    <figure className="ac-grafica">
      <svg viewBox={`0 0 ${ancho} ${alto}`} role="img" aria-label={`Consumo del contrato por mes. ${resumen}`} data-testid="grafica-consumo">
        <text x={m.izq - 6} y={10} textAnchor="end" fontSize={10} fill={GRIS}>m³</text>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={m.izq} x2={ancho - m.der} y1={y(t)} y2={y(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={y(t) + 3.5} textAnchor="end" fontSize={10} fill={GRIS}>{m3(t)}</text>
          </g>
        ))}
        {filas.map((f, i) => {
          const x = cx(i) - barW / 2;
          if (f.sinDato) {
            return (
              <g key={f.periodo} data-mes={f.periodo} data-sin-dato="1">
                <rect x={x} y={m.arr} width={barW} height={plotH} fill="#F6F8FA" stroke="#C3CED6" strokeDasharray="3 3" rx={2} />
                <text x={cx(i)} y={base - 6 - 11} textAnchor="middle" fontSize={9.5} fill={GRIS}>sin</text>
                <text x={cx(i)} y={base - 6} textAnchor="middle" fontSize={9.5} fill={GRIS}>dato</text>
                <title>{`${f.etiqueta}: sin dato en la fuente`}</title>
              </g>
            );
          }
          if (f.m3 === null) return null;
          const yy = y(f.m3), h = Math.max(f.m3 > 0 ? 1 : 0, base - yy);
          return (
            <rect key={f.periodo} data-mes={f.periodo} data-estimado={f.estimado ? "1" : "0"} x={f.estimado ? x + 0.75 : x} y={base - h + (f.estimado ? 0.75 : 0)} width={f.estimado ? barW - 1.5 : barW}
              height={f.estimado ? Math.max(0, h - 0.75) : h} rx={2} fill={f.estimado ? "#FFFFFF" : TINTA} stroke={TINTA} strokeWidth={f.estimado ? 1.5 : 0}>
              <title>{`${f.etiqueta}: ${m3(f.m3)} m³${f.estimado ? " (estimado)" : ""}`}</title>
            </rect>
          );
        })}
        {hayEstrato && linea(filas.map((f) => f.estrato)).map((pts, k) => <polyline key={`e${k}`} points={pts} fill="none" stroke={OCRE} strokeWidth={2} strokeDasharray="6 4" data-serie="estrato" />)}
        {hayBarrio && linea(filas.map((f) => f.barrio)).map((pts, k) => <polyline key={`b${k}`} points={pts} fill="none" stroke={CELESTE} strokeWidth={2.2} strokeDasharray="1.5 3.5" strokeLinecap="round" data-serie="barrio" />)}
        {filas.map((f, i) => (
          <g key={`p${f.periodo}`}>
            {f.estrato !== null ? <circle cx={cx(i)} cy={y(f.estrato)} r={2.6} fill={OCRE}><title>{`${f.etiqueta} · promedio del estrato: ${m3(f.estrato)} m³`}</title></circle> : null}
            {f.barrio !== null ? <rect x={cx(i) - 2.4} y={y(f.barrio) - 2.4} width={4.8} height={4.8} fill={CELESTE}><title>{`${f.etiqueta} · promedio del barrio: ${m3(f.barrio)} m³`}</title></rect> : null}
          </g>
        ))}
        <line x1={m.izq} x2={ancho - m.der} y1={base} y2={base} stroke="#C3CED6" />
        {filas.map((f, i) => (
          <g key={`x${f.periodo}`}>
            <text x={cx(i)} y={base + 14} textAnchor="middle" fontSize={10.5} fill="#22313F">{f.corto}</text>
            <text x={cx(i)} y={base + 26} textAnchor="middle" fontSize={9} fill={GRIS}>{f.periodo.slice(0, 4)}</text>
          </g>
        ))}
      </svg>
      <figcaption className="ac-leyenda">
        <span><i className="ac-ley-barra" aria-hidden="true" /> Contrato (lectura)</span>
        {hayEstimado ? <span><i className="ac-ley-hueca" aria-hidden="true" /> Estimado</span> : null}
        {hayEstrato ? <span><i className="ac-ley-raya" aria-hidden="true" /> Promedio {grupoEstrato ? `del ${grupoEstrato.replace(/^Estrato/, "estrato")}` : "del estrato"}</span> : null}
        {hayBarrio ? <span><i className="ac-ley-punto" aria-hidden="true" /> Promedio del barrio{grupoBarrio ? ` ${grupoBarrio}` : ""}</span> : null}
        {haySinDato ? <span><i className="ac-ley-vacio" aria-hidden="true" /> Sin dato en la fuente</span> : null}
      </figcaption>
    </figure>
  );
}
