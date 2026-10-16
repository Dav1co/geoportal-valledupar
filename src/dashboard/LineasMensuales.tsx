// Variante de LineasPorDia con el eje horizontal rotulado por mes (ene…dic). Archivo propio: graficas.tsx no se toca.
// El valor de cada punto va en el tooltip nativo (title) junto con el mes y la serie.
type Serie = { nombre: string; color: string; valores: (number | null)[] };

export function LineasMensuales({
  etiquetas, series, formatoValor, formatoEjeY, alto = 300, ocultas, onToggle,
}: {
  etiquetas: string[]; // una por posición de valores
  series: Serie[];
  formatoValor: (v: number) => string;
  formatoEjeY: (v: number) => string;
  alto?: number;
  ocultas?: string[];
  onToggle?: (nombre: string) => void;
}) {
  const ancho = 720;
  const m = { izq: 56, der: 14, arr: 10, aba: 26 };
  const plotW = ancho - m.izq - m.der;
  const plotH = alto - m.arr - m.aba;
  const apagada = (n: string) => (ocultas ?? []).includes(n);
  const visibles = series.filter((s) => !apagada(s.nombre));
  const n = Math.max(etiquetas.length, 1);
  const vals = visibles.flatMap((s) => s.valores.filter((v): v is number => v != null));
  const max = Math.max(1, ...vals);
  const escX = (i: number) => m.izq + (plotW * i) / Math.max(1, n - 1);
  const escY = (v: number) => m.arr + plotH * (1 - v / (max * 1.05));
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => max * 1.05 * f);
  return (
    <div className="dash-grafica">
      <svg viewBox={`0 0 ${ancho} ${alto}`} style={{ width: "100%", height: "auto" }} role="img">
        {ticks.map((t, i) => (
          <g key={i}>
            <line x1={m.izq} x2={ancho - m.der} y1={escY(t)} y2={escY(t)} stroke="#EAF0F4" strokeWidth={1} />
            <text x={m.izq - 6} y={escY(t) + 3.5} textAnchor="end" fontSize={10} fill="#5D6E7E">{formatoEjeY(t)}</text>
          </g>
        ))}
        {etiquetas.map((e, i) => (
          <text key={e + i} x={escX(i)} y={alto - 8} textAnchor="middle" fontSize={9.5} fill="#5D6E7E">{e}</text>
        ))}
        {visibles.map((s) => {
          const d = s.valores
            .map((v, i) => (v == null ? null : `${escX(i)},${escY(v)}`))
            .filter(Boolean)
            .map((p, i) => (i === 0 ? `M ${p}` : `L ${p}`))
            .join(" ");
          return <path key={s.nombre} d={d} fill="none" stroke={s.color} strokeWidth={2} strokeLinecap="round" />;
        })}
        {visibles.map((s) =>
          s.valores.map((v, i) =>
            v == null ? null : (
              <circle key={`${s.nombre}-${i}`} cx={escX(i)} cy={escY(v)} r={4} fill={s.color} fillOpacity={0.9}>
                <title>{`${etiquetas[i]} · ${s.nombre}: ${formatoValor(v)}`}</title>
              </circle>
            ),
          ),
        )}
      </svg>
      <div className="dash-leyenda">
        {series.map((s) => {
          const off = apagada(s.nombre);
          const contenido = (<><i style={{ background: s.color, opacity: off ? 0.25 : 1 }} />{s.nombre}</>);
          return onToggle ? (
            <button key={s.nombre} type="button" className={`dash-leyenda-btn${off ? " off" : ""}`} onClick={() => onToggle(s.nombre)}
              aria-pressed={!off} title={off ? `Mostrar ${s.nombre}` : `Ocultar ${s.nombre}`}>{contenido}</button>
          ) : (<span key={s.nombre}>{contenido}</span>);
        })}
      </div>
    </div>
  );
}
