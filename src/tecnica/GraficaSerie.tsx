import { useEffect, useId, useRef, useState } from "react";
import type { PuntoSerie, Serie } from "./apiDashboard";
import { aMs, banda, dominioX, dominioY, fmtPunto, ticksX, ticksY } from "./graficas";
import { etiquetaMarca, etiquetaOrigen, fmtLimite, fmtValor } from "./formato";
import { formatearNumero } from "./numeros";

// Una gráfica por variable y lugar (SVG propio, sin librerías). Un punto por registro vigente (no promedios); banda sombreada con la referencia vigente; los puntos fuera de referencia van en
// ROJO y con FORMA distinta (▲ sobre el máximo, ▼ bajo el mínimo) para no depender solo del color. Accesible: role="img" con descripción y una tabla alternativa plegable con los mismos puntos.
const ALTO = 200, MI = 46, MD = 12, MS = 10, MB = 26;
export const lugarDeSerie = (s: Pick<Serie, "punto_nombre" | "planta_nombre">) => s.punto_nombre ?? s.planta_nombre ?? "Las dos plantas";

function useAncho(ref: React.RefObject<HTMLDivElement>) {
  const [w, setW] = useState(600);
  useEffect(() => {
    const el = ref.current; if (!el) return;
    const act = () => setW(Math.max(260, Math.floor(el.clientWidth)));
    act();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(act) : null; ro?.observe(el);
    window.addEventListener("resize", act);
    return () => { ro?.disconnect(); window.removeEventListener("resize", act); };
  }, [ref]);
  return w;
}

/** Texto de la referencia para el encabezado: «máx. 5.000 NTU · Criterio de planta» o «sin referencia». */
export function textoRef(s: Serie): string {
  const r = s.referencia; if (!r || (r.ref_min === null && r.ref_max === null)) return "sin referencia";
  const lim = [r.ref_min !== null ? `mín. ${fmtLimite(r.ref_min)}` : "", r.ref_max !== null ? `máx. ${fmtLimite(r.ref_max)}` : ""].filter(Boolean).join(" · ");
  return `${lim} ${s.unidad} · ${etiquetaOrigen(r.origen)}`;
}

export function GraficaSerie({ serie, desde, hasta }: { serie: Serie; desde: string; hasta: string }) {
  const caja = useRef<HTMLDivElement>(null);
  const ancho = useAncho(caja);
  const [tabla, setTabla] = useState(false);
  const id = useId();
  const lugar = lugarDeSerie(serie);
  const ult = serie.ultimo;
  const ref = serie.referencia ? { ref_min: serie.referencia.ref_min, ref_max: serie.referencia.ref_max } : null;
  const resumen = `${serie.variable_nombre}, ${lugar}: ${serie.n} ${serie.n === 1 ? "registro" : "registros"}${ult ? `, último ${fmtValor(ult.v, serie.decimales)} ${serie.unidad}` : ""}, ${serie.fuera} fuera de referencia, ${textoRef(serie)}.`;

  const cab = (
    <figcaption className="tg-cab">
      <div className="tg-titulo"><strong>{serie.variable_nombre}</strong><span className="tg-lugar">{lugar}</span></div>
      <div className="tg-datos">
        <span className="tg-ultimo">{ult ? <>Último <strong>{fmtValor(ult.v, serie.decimales)} {serie.unidad}</strong></> : "Sin registros en el periodo"}</span>
        <span className="tg-ref">{textoRef(serie)}</span>
        <span className={`tg-fuera${serie.fuera > 0 ? " tg-fuera-si" : ""}`}>{serie.fuera} fuera</span>
      </div>
    </figcaption>
  );
  if (serie.n === 0) return <figure className="tg-fig tg-vacia" data-serie={`${serie.variable}@${serie.planta ?? ""}@${serie.punto ?? ""}`}>{cab}</figure>;

  const [x0, x1] = dominioX(desde, hasta);
  const valores = serie.puntos.map((p) => p.v);
  const dom = dominioY(valores, ref); const tk = ticksY(dom.min, dom.max); const bd = banda(ref, dom);
  const W = ancho, H = ALTO, gw = W - MI - MD, gh = H - MS - MB;
  const px = (ms: number) => MI + ((ms - x0) / (x1 - x0)) * gw;
  const py = (v: number) => MS + (1 - (v - dom.min) / (dom.max - dom.min)) * gh;
  const linea = serie.puntos.map((p) => `${px(aMs(p.t)).toFixed(1)},${py(p.v).toFixed(1)}`).join(" ");
  const estado = (p: PuntoSerie) => (p.m ? etiquetaMarca(p.m) : serie.referencia ? "Dentro de la referencia" : "Sin referencia");

  return (
    <figure className="tg-fig" data-serie={`${serie.variable}@${serie.planta ?? ""}@${serie.punto ?? ""}`}>
      {cab}
      {serie.recortada ? <p className="tg-nota">Se muestran los {formatearNumero(serie.puntos.length, 0)} puntos más recientes de {formatearNumero(serie.n, 0)} del periodo (el contador «fuera» cuenta todos).</p> : null}
      <div className="tg-caja" ref={caja}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} role="img" aria-labelledby={`${id}t ${id}d`} className="tg-svg">
          <title id={`${id}t`}>{resumen}</title>
          <desc id={`${id}d`}>Gráfica de puntos en el tiempo. {serie.fuera > 0 ? `Los ${serie.fuera} puntos fuera de referencia se marcan con triángulos rojos.` : "Ningún punto está fuera de referencia."} Los mismos datos están en la tabla que sigue.</desc>
          {bd ? <rect className="tg-banda" x={MI} y={py(bd.hasta)} width={gw} height={Math.max(1, py(bd.desde) - py(bd.hasta))} /> : null}
          {tk.valores.map((v) => <g key={v}><line className="tg-rejilla" x1={MI} x2={W - MD} y1={py(v)} y2={py(v)} /><text className="tg-eje" x={MI - 6} y={py(v) + 4} textAnchor="end">{formatearNumero(v, tk.decimales)}</text></g>)}
          {ticksX(desde, hasta).map((t) => <g key={t.ms}><line className="tg-rejilla-x" x1={px(t.ms)} x2={px(t.ms)} y1={MS} y2={H - MB} /><text className="tg-eje" x={px(t.ms) + 2} y={H - 8}>{t.texto}</text></g>)}
          {serie.puntos.length > 1 ? <polyline className="tg-linea" points={linea} fill="none" /> : null}
          {serie.puntos.map((p, i) => {
            const cx = px(aMs(p.t)), cy = py(p.v);
            return p.m ? (
              <polygon key={i} className="tg-fuera-punto" data-fuera={p.m} points={p.m === "alto" ? `${cx},${cy - 6} ${cx - 5.5},${cy + 4} ${cx + 5.5},${cy + 4}` : `${cx},${cy + 6} ${cx - 5.5},${cy - 4} ${cx + 5.5},${cy - 4}`}><title>{`${fmtPunto(p, serie.decimales)} ${serie.unidad} · ${etiquetaMarca(p.m)}`}</title></polygon>
            ) : <circle key={i} className="tg-punto" cx={cx} cy={cy} r={3}><title>{`${fmtPunto(p, serie.decimales)} ${serie.unidad}`}</title></circle>;
          })}
        </svg>
      </div>
      <details className="tg-detalle" onToggle={(e) => setTabla((e.currentTarget as HTMLDetailsElement).open)}>
        <summary>Ver los {formatearNumero(serie.puntos.length, 0)} {serie.puntos.length === 1 ? "punto" : "puntos"} en una tabla</summary>
        {tabla ? (
          <div className="tg-tabla-caja"><table className="tg-tabla">
            <caption className="td-solo-lectores">{resumen}</caption>
            <thead><tr><th>Fecha y hora de la muestra</th><th className="td-der">Valor ({serie.unidad})</th><th>Estado</th></tr></thead>
            <tbody>{[...serie.puntos].reverse().map((p, i) => <tr key={i} className={p.m ? "tg-fila-fuera" : undefined}><td className="td-num">{p.t.slice(8, 10)}/{p.t.slice(5, 7)}/{p.t.slice(0, 4)} {p.t.slice(11, 16)}</td><td className="td-der td-valor">{fmtValor(p.v, serie.decimales)}</td><td>{p.m ? (p.m === "alto" ? "▲ " : "▼ ") : ""}{estado(p)}</td></tr>)}</tbody>
          </table></div>
        ) : null}
      </details>
    </figure>
  );
}
