import { useEffect, useState } from "react";
import { biCache } from "../cacheBi";
import { SinDatos } from "../SinDatos";
import {
  comoCarteraMes,
  comoCarteraRuta,
  comoCarteraServicio,
  comoCarteraTramo,
  type CarteraMes,
  type CarteraRuta,
  type CarteraServicio,
  type CarteraTramo,
  type KpiMes,
} from "../tipos";
import { etiquetaCorta, etiquetaPeriodo, fmtDelta, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasMensuales, Dona, LineasPorcentaje, MESES_CORTO, TablaPlegable, colorAnio } from "../graficas";

// Tramos de edad: rampa secuencial de un solo tono (claro → oscuro),
// porque la edad es una magnitud ORDENADA. La financiada no pertenece a
// ese orden, así que lleva un tono aparte (ocre).
const COLOR_TRAMO: Record<string, string> = {
  "Hasta 60 días": "#8FB4CE",
  "60 a 180 días": "#4FA3C7",
  "180 a 360 días": "#2E7D9E",
  "Más de 360 días": "#0A2540",
  Financiada: "#C98A2D",
};

const COLOR_SERVICIO: Record<string, string> = {
  ACUEDUCTO: "#0A2540",
  ALCANTARILLADO: "#0E7C86",
  PLUVIAL: "#C98A2D",
  TERCERO: "#C9D4DC",
  OTROS: "#7B5EA7",
};

type Props = { periodo: string; comparado: string | null; kpis: KpiMes[] };

export function CarteraAgrupado({ periodo, comparado, kpis }: Props) {
  const [meses, setMeses] = useState<CarteraMes[] | null>(null);
  const [tramos, setTramos] = useState<CarteraTramo[]>([]);
  const [servicios, setServicios] = useState<CarteraServicio[]>([]);
  const [rutas, setRutas] = useState<CarteraRuta[]>([]);
  const [error, setError] = useState<string | null>(null);

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([
      biCache("v_cartera_mes"),
      biCache("v_cartera_tramo"),
      biCache("v_cartera_servicio"),
      biCache("v_cartera_ruta"),
    ])
      .then(([m, t, s, r]) => {
        setMeses((m.datos ?? []).map(comoCarteraMes));
        setTramos((t.datos ?? []).map(comoCarteraTramo));
        setServicios((s.datos ?? []).map(comoCarteraServicio));
        setRutas((r.datos ?? []).map(comoCarteraRuta));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar la cartera: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando cartera…</div>;

  const porPeriodo = new Map(meses.map((f) => [f.periodo, f]));
  const sel = porPeriodo.get(periodo);
  const cmp = comparado ? porPeriodo.get(comparado) : undefined;
  if (!sel) {
    return <SinDatos periodo={periodo} fuente="cartera" disponibles={meses.map((f) => f.periodo)} />;
  }

  const kpiSel = kpis.find((k) => k.periodo === periodo);

  const listaAnios = [...new Set(meses.map((f) => f.anio).filter((a): a is number => a != null))].sort();
  const anioMax = Math.max(...listaAnios);
  const series = listaAnios.map((a) => ({
    nombre: String(a),
    color: colorAnio(a, anioMax),
    valores: Array.from({ length: 12 }, (_, i) => meses.find((f) => f.anio === a && f.mes === i + 1)?.cartera_total ?? null),
  }));

  const donaPartes = tramos
    .filter((t) => t.periodo === periodo)
    .sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0))
    .map((t) => ({
      etiqueta: t.tramo,
      valor: t.valor ?? 0,
      color: COLOR_TRAMO[t.tramo] ?? "#C9D4DC",
      pct: t.pct_periodo,
    }));

  const cronologico = [...meses].sort((a, b) => a.periodo.localeCompare(b.periodo));
  const seriesDeterioro = [
    {
      nombre: "Cartera > 360 días",
      color: "#0A2540",
      valores: cronologico.map((f) => f.pct_may_360),
    },
    {
      nombre: "Cartera financiada",
      color: "#C98A2D",
      valores: cronologico.map((f) => f.pct_financiada),
    },
  ];

  const serviciosSel = servicios
    .filter((s) => s.periodo === periodo)
    .sort((a, b) => (b.cartera ?? 0) - (a.cartera ?? 0));
  const rutasSel = rutas
    .filter((r) => r.periodo === periodo)
    .sort((a, b) => (b.cartera ?? 0) - (a.cartera ?? 0));

  const sub = (delta: string, alterno: string) =>
    cmp ? <span>vs {etiquetaPeriodo(cmp.periodo)}: <b>{delta}</b></span> : alterno;

  return (
    <>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Cartera total</div>
          <div className="dash-valor num">{fmtMillones(sel.cartera_total)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.cartera_total, cmp?.cartera_total ?? null), etiquetaPeriodo(periodo))}
          </div>
        </div>

        <div className="dash-carta dash-kpi dash-kpi-mal">
          <div className="dash-eti">Más de 360 días</div>
          <div className="dash-valor num">{fmtMillones(sel.t_may_360)}</div>
          <div className="dash-sub2">
            {sub(
              fmtDelta(sel.t_may_360, cmp?.t_may_360 ?? null),
              `${fmtPct(sel.pct_may_360)} de la cartera · difícil recaudo`,
            )}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Cartera financiada</div>
          <div className="dash-valor num">{fmtMillones(sel.financiada)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.financiada, cmp?.financiada ?? null), `${fmtPct(sel.pct_financiada)} de la cartera`)}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Cartera no financiada</div>
          <div className="dash-valor num">{fmtMillones(sel.no_financiada)}</div>
          <div className="dash-sub2">la que abre por edades</div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos con deuda</div>
          <div className="dash-valor num">
            {kpiSel?.contratos_con_cartera != null ? fmtEntero(kpiSel.contratos_con_cartera) : "—"}
          </div>
          <div className="dash-sub2">
            {kpiSel?.contratos_con_cartera != null
              ? "según el detalle por contrato"
              : "Sin detalle: fuera de la ventana de 6 meses"}
          </div>
        </div>
      </div>

      <div className="dash-aviso">
        La cartera total se compone de la <b>no financiada</b>, que es la que
        abre por edades, y la <b>financiada</b> (acuerdos de pago vigentes), que
        no tiene edad asignada. Por eso las cubetas de edad nunca suman el total:
        la diferencia no es un faltante, es la deuda con acuerdo de pago.
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Cartera total por mes y año</h3>
          <BarrasMensuales
            series={series}
            formatoY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 0 }) + " mil M"}
            formatoTitulo={fmtMillones}
          />
          <TablaPlegable titulo="Datos: cartera mensual por año">
            <table className="dash-tabla num">
              <thead><tr><th>Mes</th>{listaAnios.map((a) => <th key={a}>{a}</th>)}</tr></thead>
              <tbody>
                {MESES_CORTO.map((mes, i) => (
                  <tr key={mes}>
                    <td>{mes}</td>
                    {listaAnios.map((a) => (
                      <td key={a} className="num">{fmtMillones(series[listaAnios.indexOf(a)].valores[i])}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </div>

        <div className="dash-carta">
          <h3>{etiquetaPeriodo(periodo)} por antigüedad</h3>
          <Dona partes={donaPartes} formatoTitulo={fmtMillones} />
          <TablaPlegable titulo="Datos: composición por antigüedad">
            <table className="dash-tabla num">
              <thead><tr><th>Tramo</th><th>Valor</th><th>%</th></tr></thead>
              <tbody>
                {donaPartes.map((p) => (
                  <tr key={p.etiqueta}>
                    <td>{p.etiqueta}</td>
                    <td className="num">{fmtMillones(p.valor)}</td>
                    <td className="num">{fmtPct(p.pct)}</td>
                  </tr>
                ))}
                <tr className="dash-total">
                  <td>Cartera total</td>
                  <td className="num">{fmtMillones(sel.cartera_total)}</td>
                  <td className="num">100,0 %</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Deterioro estructural: peso de la cartera vieja y de la financiada</h3>
          <LineasPorcentaje
            etiquetas={cronologico.map((f) => etiquetaCorta(f.periodo))}
            series={seriesDeterioro}
          />
          <TablaPlegable titulo="Datos: evolución de la composición (%)">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Período</th><th>Cartera total</th><th>&gt; 360 días</th>
                  <th>% &gt; 360</th><th>Financiada</th><th>% financiada</th><th>Δ vs mes anterior</th>
                </tr>
              </thead>
              <tbody>
                {[...cronologico].reverse().map((f) => (
                  <tr key={f.periodo}>
                    <td>{etiquetaPeriodo(f.periodo)}</td>
                    <td className="num">{fmtMillones(f.cartera_total)}</td>
                    <td className="num">{fmtMillones(f.t_may_360)}</td>
                    <td className="num">{fmtPct(f.pct_may_360)}</td>
                    <td className="num">{fmtMillones(f.financiada)}</td>
                    <td className="num">{fmtPct(f.pct_financiada)}</td>
                    <td className={`num ${f.variacion != null && f.variacion > 0 ? "dash-neg" : ""}`}>
                      {f.variacion == null
                        ? "—"
                        : `${f.variacion >= 0 ? "+" : "−"}${fmtMillones(Math.abs(f.variacion))}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El eje se ajusta al rango observado, no a 0–100. Cuando la línea de
            cartera vieja sube, la deuda envejece más rápido de lo que se
            recupera; cuando sube la financiada, más deuda pasó a acuerdos de
            pago. En cartera, un aumento del total no es una buena noticia: es
            deuda que no se cobró.
          </div>
        </div>
      </div>

      <div className="dash-fila-g2">
        <div className="dash-carta">
          <h3>Cartera por servicio — {etiquetaPeriodo(periodo)}</h3>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla num">
              <thead><tr><th>Servicio</th><th>Cartera</th><th>%</th></tr></thead>
              <tbody>
                {serviciosSel.map((s) => (
                  <tr key={s.servicio}>
                    <td>
                      <i className="dash-punto" style={{ background: COLOR_SERVICIO[s.servicio] ?? COLOR_SERVICIO.OTROS }} />
                      {s.servicio}
                    </td>
                    <td className="num">{fmtMillones(s.cartera)}</td>
                    <td className="num">{fmtPct(s.pct_periodo)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="dash-carta">
          <h3>Ruta contable fina — {etiquetaPeriodo(periodo)}</h3>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla num">
              <thead><tr><th>Categoría</th><th>Cartera</th><th>%</th><th>Δ vs anterior</th></tr></thead>
              <tbody>
                {rutasSel.map((r) => (
                  <tr key={r.ruta_efectiva}>
                    <td>{r.ruta_efectiva}</td>
                    <td className="num">{fmtMillones(r.cartera)}</td>
                    <td className="num">{fmtPct(r.pct_periodo)}</td>
                    <td className={`num ${r.variacion != null && r.variacion > 0 ? "dash-neg" : ""}`}>
                      {r.variacion == null
                        ? "—"
                        : `${r.variacion >= 0 ? "+" : "−"}${fmtMillones(Math.abs(r.variacion))}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </>
  );
}
