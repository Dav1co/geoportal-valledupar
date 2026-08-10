import { useEffect, useState } from "react";
import { biCache } from "../cacheBi";
import { SinDatos } from "../SinDatos";
import {
  comoFactVsRecaudo,
  comoRecaudoMes,
  comoRecaudoServicio,
  type FactVsRecaudo,
  type KpiAnio,
  type KpiMes,
  type RecaudoMes,
  type RecaudoServicio,
} from "../tipos";
import { etiquetaCorta, etiquetaPeriodo, fmtDelta, fmtMillones, fmtPct } from "../formato";
import { BarrasMensuales, Dona, LineasPorcentaje, MESES_CORTO, TablaPlegable, colorAnio } from "../graficas";

// Meta oficial del recaudo corriente: rojo < 80, ámbar 80–85, verde > 85.
const META_0_30 = 85;

// Mismos colores por servicio que la pantalla de Facturación, para que
// las dos donas sean comparables de un vistazo.
const COLOR_SERVICIO: Record<string, string> = {
  ACUEDUCTO: "#0A2540",
  ALCANTARILLADO: "#0E7C86",
  PLUVIAL: "#C98A2D",
  TERCERO: "#C9D4DC",
  OTROS: "#7B5EA7",
};

// Composición por edades: tinta para el corriente, ocre y gris para los
// dos tramos de recuperación (paleta institucional, pares validados).
const COLOR_TRAMO = { corriente: "#0A2540", recuperacion: "#C98A2D", vieja: "#9AA7B5" };

type Props = {
  periodo: string;
  comparado: string | null;
  kpis: KpiMes[];
  anios: KpiAnio[];
};

export function RecaudoAgrupado({ periodo, comparado, kpis, anios }: Props) {
  const [meses, setMeses] = useState<RecaudoMes[] | null>(null);
  const [servicios, setServicios] = useState<RecaudoServicio[]>([]);
  const [cruce, setCruce] = useState<FactVsRecaudo[]>([]);
  const [error, setError] = useState<string | null>(null);

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([
      biCache("v_recaudo_mes"),
      biCache("v_recaudo_servicio"),
      biCache("v_fact_vs_recaudo_servicio"),
    ])
      .then(([m, s, c]) => {
        setMeses((m.datos ?? []).map(comoRecaudoMes));
        setServicios((s.datos ?? []).map(comoRecaudoServicio));
        setCruce((c.datos ?? []).map(comoFactVsRecaudo));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar el recaudo: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando recaudo…</div>;

  const porPeriodo = new Map(meses.map((f) => [f.periodo, f]));
  const sel = porPeriodo.get(periodo);
  const cmp = comparado ? porPeriodo.get(comparado) : undefined;
  if (!sel) {
    return <SinDatos periodo={periodo} fuente="recaudo" disponibles={meses.map((f) => f.periodo)} />;
  }

  // % sobre facturado: NO se recalculan aquí — vienen de v_kpi_mes /
  // v_kpi_anio, que ya los definen (una sola fuente de verdad).
  const kpiSel = kpis.find((k) => k.periodo === periodo);
  const kpiCmp = comparado ? kpis.find((k) => k.periodo === comparado) : undefined;
  const anioSel = anios.find((a) => a.periodo === periodo);

  const pct030 = kpiSel?.pct_recaudo_0_30 ?? null;
  const semaforo =
    pct030 == null
      ? null
      : pct030 > META_0_30
        ? { clase: "verde", texto: "en meta" }
        : pct030 >= 80
          ? { clase: "ambar", texto: "cerca" }
          : { clase: "rojo", texto: "bajo" };

  // Barras: recaudo total por mes y año.
  const listaAnios = [...new Set(meses.map((f) => f.anio).filter((a): a is number => a != null))].sort();
  const anioMax = Math.max(...listaAnios);
  const series = listaAnios.map((a) => ({
    nombre: String(a),
    color: colorAnio(a, anioMax),
    valores: Array.from({ length: 12 }, (_, i) => meses.find((f) => f.anio === a && f.mes === i + 1)?.recaudo_total ?? null),
  }));

  // Evolución del mix: serie completa ordenada por período.
  const cronologico = [...meses].sort((a, b) => a.periodo.localeCompare(b.periodo));
  const etiquetasMix = cronologico.map((f) => etiquetaCorta(f.periodo));
  const seriesMix = [
    { nombre: "Corriente (0–30)", color: COLOR_TRAMO.corriente, valores: cronologico.map((f) => f.pct_0_30) },
    { nombre: "Recuperación (60–360)", color: COLOR_TRAMO.recuperacion, valores: cronologico.map((f) => f.pct_60_360) },
    { nombre: "Recuperación (> 360)", color: COLOR_TRAMO.vieja, valores: cronologico.map((f) => f.pct_may360) },
  ];

  const donaPartes = servicios
    .filter((s) => s.periodo === periodo && s.recaudo != null)
    .sort((a, b) => (b.recaudo ?? 0) - (a.recaudo ?? 0))
    .map((s) => ({
      etiqueta: s.servicio,
      valor: s.recaudo ?? 0,
      color: COLOR_SERVICIO[s.servicio] ?? COLOR_SERVICIO.OTROS,
      pct: s.pct_periodo,
    }));

  const cruceSel = cruce
    .filter((c) => c.periodo === periodo)
    .sort((a, b) => (b.facturado ?? 0) - (a.facturado ?? 0));

  const sub = (delta: string, alterno: string) =>
    cmp ? <span>vs {etiquetaPeriodo(cmp.periodo)}: <b>{delta}</b></span> : alterno;

  return (
    <>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Recaudo total</div>
          <div className="dash-valor num">{fmtMillones(sel.recaudo_total)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.recaudo_total, cmp?.recaudo_total ?? null), etiquetaPeriodo(periodo))}
          </div>
        </div>

        <div className={`dash-carta dash-kpi ${semaforo?.clase === "rojo" ? "dash-kpi-mal" : ""}`}>
          <div className="dash-eti">% Recaudo 0–30</div>
          <div className="dash-valor num">{fmtPct(pct030)}</div>
          <div className="dash-sub2">
            {cmp && kpiCmp ? (
              <span>
                vs {etiquetaPeriodo(kpiCmp.periodo)}:{" "}
                <b>
                  {pct030 != null && kpiCmp.pct_recaudo_0_30 != null
                    ? `${pct030 - kpiCmp.pct_recaudo_0_30 >= 0 ? "+" : "−"}${Math.abs(pct030 - kpiCmp.pct_recaudo_0_30).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} pp`
                    : "—"}
                </b>
              </span>
            ) : (
              <>
                Meta: {META_0_30} % sobre lo facturado{" "}
                {semaforo && <span className={`dash-semaforo ${semaforo.clase}`}>{semaforo.texto}</span>}
              </>
            )}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">% Recaudo del mes</div>
          <div className="dash-valor num">{fmtPct(kpiSel?.pct_recaudo_mes ?? null)}</div>
          <div className="dash-sub2">sobre lo facturado del mes</div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">% Recaudo del año</div>
          <div className="dash-valor num">{fmtPct(anioSel?.pct_recaudo_anio ?? null)}</div>
          <div className="dash-sub2 num">
            {anioSel
              ? `${fmtMillones(anioSel.recaudo_anio)} de ${fmtMillones(anioSel.facturado_anio)}`
              : "Sin acumulado para este período"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Recuperación de cartera</div>
          <div className="dash-valor num">{fmtMillones(sel.recuperacion_cartera)}</div>
          <div className="dash-sub2">
            {sub(
              fmtDelta(sel.recuperacion_cartera, cmp?.recuperacion_cartera ?? null),
              `${fmtPct(sel.pct_recuperacion)} del recaudo · tramos 60–360 y > 360`,
            )}
          </div>
        </div>
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Recaudo total por mes y año</h3>
          <BarrasMensuales
            series={series}
            formatoY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            formatoTitulo={fmtMillones}
          />
          <TablaPlegable titulo="Datos: recaudo mensual por año">
            <table className="dash-tabla num">
              <thead>
                <tr><th>Mes</th>{listaAnios.map((a) => <th key={a}>{a}</th>)}</tr>
              </thead>
              <tbody>
                {MESES_CORTO.map((mes, i) => (
                  <tr key={mes}>
                    <td>{mes}</td>
                    {listaAnios.map((a) => (
                      <td key={a} className="num">
                        {fmtMillones(series[listaAnios.indexOf(a)].valores[i])}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </div>

        <div className="dash-carta">
          <h3>{etiquetaPeriodo(periodo)} por servicio</h3>
          <Dona partes={donaPartes} formatoTitulo={fmtMillones} />
          <TablaPlegable titulo="Datos: recaudo por servicio">
            <table className="dash-tabla num">
              <thead><tr><th>Servicio</th><th>Recaudo</th><th>%</th></tr></thead>
              <tbody>
                {donaPartes.map((p) => (
                  <tr key={p.etiqueta}>
                    <td>{p.etiqueta}</td>
                    <td className="num">{fmtMillones(p.valor)}</td>
                    <td className="num">{fmtPct(p.pct)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>¿De qué vive el recaudo? Composición por edades, mes a mes</h3>
          <LineasPorcentaje etiquetas={etiquetasMix} series={seriesMix} />
          <TablaPlegable titulo="Datos: composición por edades (%)">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Período</th><th>Recaudo total</th>
                  <th>Corriente 0–30</th><th>60–360</th><th>&gt; 360</th><th>Recuperación</th>
                </tr>
              </thead>
              <tbody>
                {[...cronologico].reverse().map((f) => (
                  <tr key={f.periodo}>
                    <td>{etiquetaPeriodo(f.periodo)}</td>
                    <td className="num">{fmtMillones(f.recaudo_total)}</td>
                    <td className="num">{fmtPct(f.pct_0_30)}</td>
                    <td className="num">{fmtPct(f.pct_60_360)}</td>
                    <td className="num">{fmtPct(f.pct_may360)}</td>
                    <td className="num">{fmtPct(f.pct_recuperacion)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El eje se ajusta al rango observado, no a 0–100: la composición se
            mueve en una banda estrecha (corriente entre 80 % y 88 % en los 43
            períodos) y un eje completo escondería justo el movimiento que
            importa. Cuando la línea de recuperación sube, la empresa está
            viviendo más del cobro de mora que del pago corriente.
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Facturado vs. recaudado por servicio — {etiquetaPeriodo(periodo)}</h3>
          {/* La advertencia va ANTES de la tabla: quien vea un 151 % debe
              haber leído por qué antes de reportarlo como error o citarlo
              como eficiencia de cobro. */}
          <div className="dash-aviso">
            El recaudo de un mes incluye pagos de facturas de meses anteriores,
            así que un servicio puede superar el 100 % cuando entra mora vieja:
            este porcentaje compara dos flujos del período, no mide la cobranza
            de la facturación de ese mes.
          </div>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla num">
              <thead>
                <tr><th>Servicio</th><th>Facturado</th><th>Recaudado</th><th>% Recaudo</th><th>Diferencia</th></tr>
              </thead>
              <tbody>
                {cruceSel.map((c) => (
                  <tr key={c.servicio}>
                    <td>{c.servicio}</td>
                    <td className="num">{fmtMillones(c.facturado)}</td>
                    <td className="num">{fmtMillones(c.recaudo)}</td>
                    <td className="num">
                      {fmtPct(c.pct_recaudo)}
                      {c.pct_recaudo != null && c.pct_recaudo > 100 && (
                        <span className="dash-marca"> incluye mora vieja</span>
                      )}
                    </td>
                    <td className={`num ${c.diferencia != null && c.diferencia < 0 ? "dash-neg" : ""}`}>
                      {c.diferencia == null
                        ? "—"
                        : `${c.diferencia >= 0 ? "+" : "−"}${fmtMillones(Math.abs(c.diferencia))}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="dash-nota">
            Para medir la cobranza real de una facturación concreta hace falta
            la curva de cosecha (qué porcentaje de lo facturado en un mes se
            recauda en ese mes, al siguiente y al subsiguiente), que se
            construye sobre el detalle por contrato.
          </div>
        </div>
      </div>
    </>
  );
}
