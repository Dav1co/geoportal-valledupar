import { useEffect, useState, type ReactNode } from "react";
import { biCache } from "../cacheBi";
import { comoRecaudoDia, type KpiAnio, type KpiMes, type RecaudoDia } from "../tipos";
import { SinDatos } from "../SinDatos";
import { LineasPorDia, colorAnio } from "../graficas";
import {
  etiquetaPeriodo,
  fmtDelta,
  fmtEntero,
  fmtMillones,
  fmtPct,
} from "../formato";

// Meta oficial de recaudo corriente. Pasará a la tabla de parámetros
// editable (bi_interno.metas) cuando entre la pantalla de Metas.
const META_0_30 = 85;

type Props = {
  filas: KpiMes[]; // ordenadas de más reciente a más antigua
  anios: KpiAnio[]; // bi.v_kpi_anio: acumulado del año por período
  periodo: string;
  comparado: string | null;
};

function deltaPuntos(actual: number | null, base: number | null): string {
  if (actual == null || base == null) return "—";
  const d = actual - base;
  return `${d >= 0 ? "+" : "−"}${Math.abs(d).toLocaleString("es-CO", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })} pp`;
}

export function Resumen({ filas, anios, periodo, comparado }: Props) {
  // La curva diaria sale de bi.v_recaudo_diario_cierre (detalle de recaudos).
  // Es liviana (181 filas) y se cachea, así que no pesa en la carga.
  const [diario, setDiario] = useState<RecaudoDia[]>([]);
  useEffect(() => {
    biCache("v_recaudo_diario_cierre")
      .then((r) => setDiario((r.datos ?? []).map(comoRecaudoDia)))
      .catch(() => setDiario([]));
  }, []);
  const porPeriodo = new Map(filas.map((f) => [f.periodo, f]));
  const sel = porPeriodo.get(periodo);
  const cmp = comparado ? porPeriodo.get(comparado) : undefined;

  // Mes cronológicamente anterior al seleccionado (para Δ cartera).
  const idx = filas.findIndex((f) => f.periodo === periodo);
  const anterior = idx >= 0 && idx + 1 < filas.length ? filas[idx + 1] : undefined;

  if (!sel) {
    return (
      <SinDatos periodo={periodo} fuente="indicadores" disponibles={filas.map((f) => f.periodo)} />
    );
  }

  // Acumulado del año hasta el período elegido: viene de bi.v_kpi_anio
  // (única fuente de verdad; aquí no se acumula nada).
  const delAnio = anios.find((a) => a.periodo === periodo);

  const enVentana = sel.contratos_activos != null;
  const pct030 = sel.pct_recaudo_0_30;
  const semaforo =
    pct030 == null
      ? null
      : pct030 >= META_0_30
        ? { clase: "verde", texto: "en meta" }
        : pct030 >= META_0_30 - 5
          ? { clase: "ambar", texto: "cerca" }
          : { clase: "rojo", texto: "bajo" };

  const subComparado = (
    delta: string,
  ): ReactNode =>
    cmp && (
      <span>
        vs {etiquetaPeriodo(cmp.periodo)}: <b>{delta}</b>
      </span>
    );

  const filaTabla = (
    nombre: string,
    valorDe: (f: KpiMes) => number | null,
    negativoEsMalo = false,
  ) => {
    const v = valorDe(sel);
    const c = cmp ? valorDe(cmp) : null;
    const clase = (x: number | null) =>
      negativoEsMalo && x != null && x < 0 ? "dash-neg" : "";
    return (
      <tr key={nombre}>
        <td>{nombre}</td>
        <td className={`num ${clase(v)}`}>{fmtMillones(v)}</td>
        {cmp && <td className="num">{fmtMillones(c)}</td>}
        {cmp && <td className="num">{fmtDelta(v, c)}</td>}
      </tr>
    );
  };

  // Series de la curva diaria: el período elegido y los dos anteriores
  // con detalle, alineados por día del mes.
  const periodosDiarios = [...new Set(diario.map((d) => d.periodo))].sort();
  const previos = periodosDiarios.filter((p) => p < periodo).slice(-2);
  const anioBase = Number(periodo.slice(0, 4));
  const serieDe = (p: string) => {
    const arr: (number | null)[] = Array.from({ length: 31 }, () => null);
    for (const d of diario) if (d.periodo === p && d.dia != null) arr[d.dia - 1] = d.valor_acumulado;
    return arr;
  };
  const seriesDiarias = periodosDiarios.includes(periodo)
    ? [
        { nombre: etiquetaPeriodo(periodo), color: "#0A2540", valores: serieDe(periodo) },
        ...previos.map((p, i) => ({
          nombre: etiquetaPeriodo(p),
          color: colorAnio(anioBase - (previos.length - i), anioBase),
          valores: serieDe(p),
        })),
      ]
    : [];

  const deltaCartera =
    sel.cartera_total != null && anterior?.cartera_total != null
      ? sel.cartera_total - anterior.cartera_total
      : null;

  return (
    <>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Facturación del mes</div>
          <div className="dash-valor num">{fmtMillones(sel.facturado)}</div>
          <div className="dash-sub2">
            {cmp
              ? subComparado(fmtDelta(sel.facturado, cmp.facturado))
              : etiquetaPeriodo(periodo)}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Recaudo del mes</div>
          <div className="dash-valor num">{fmtMillones(sel.recaudo_total)}</div>
          <div className="dash-sub2">
            {cmp
              ? subComparado(fmtDelta(sel.recaudo_total, cmp.recaudo_total))
              : `${fmtPct(sel.pct_recaudo_mes)} de lo facturado`}
          </div>
        </div>

        <div className={`dash-carta dash-kpi ${semaforo?.clase === "rojo" ? "dash-kpi-mal" : ""}`}>
          <div className="dash-eti">% Recaudo 0–30</div>
          <div className="dash-valor num">{fmtPct(pct030)}</div>
          <div className="dash-sub2">
            {cmp ? (
              subComparado(deltaPuntos(pct030, cmp.pct_recaudo_0_30))
            ) : (
              <>
                Meta: {META_0_30} %{" "}
                {semaforo && (
                  <span className={`dash-semaforo ${semaforo.clase}`}>
                    {semaforo.texto}
                  </span>
                )}
              </>
            )}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">% Recaudo del año</div>
          <div className="dash-valor num">
            {fmtPct(delAnio?.pct_recaudo_anio ?? null)}
          </div>
          <div className="dash-sub2 num">
            {delAnio
              ? `${fmtMillones(delAnio.recaudo_anio)} de ${fmtMillones(delAnio.facturado_anio)}`
              : "Sin acumulado para este período"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Cartera total</div>
          <div className="dash-valor num">{fmtMillones(sel.cartera_total)}</div>
          <div className="dash-sub2">
            {cmp
              ? subComparado(fmtDelta(sel.cartera_total, cmp.cartera_total))
              : enVentana
                ? `${fmtEntero(sel.contratos_con_cartera)} contratos con deuda`
                : "Sin detalle por contrato: fuera de la ventana de 6 meses"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos activos</div>
          <div className="dash-valor num">
            {enVentana ? fmtEntero(sel.contratos_activos) : "—"}
          </div>
          <div className="dash-sub2">
            {enVentana
              ? "facturados en el período (concepto 1, acueducto)"
              : "Sin detalle por contrato: fuera de la ventana de 6 meses"}
          </div>
        </div>
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Recaudo diario acumulado</h3>
          {diario.length === 0 ? (
            <div className="dash-placeholder">
              Sin detalle diario para {etiquetaPeriodo(periodo)}
            </div>
          ) : (
            <>
              <LineasPorDia
                series={seriesDiarias}
                formatoValor={fmtMillones}
                formatoEjeY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
                alto={260}
              />
              <div className="dash-nota">
                Alineado por día del mes: la comparación es siempre al mismo día
                de corte.
              </div>
            </>
          )}
        </div>

        <div className="dash-carta">
          <h3>El mes en una mirada</h3>
          <table className="dash-tabla num">
            {cmp && (
              <thead>
                <tr>
                  <th />
                  <th>{etiquetaPeriodo(periodo)}</th>
                  <th>{etiquetaPeriodo(cmp.periodo)}</th>
                  <th>Δ</th>
                </tr>
              </thead>
            )}
            <tbody>
              {filaTabla("Notas aplicadas", (f) => f.notas_valor, true)}
              {filaTabla("Recaudo corriente (0–30)", (f) => f.recaudo_0_30)}
              {filaTabla("Recuperación de cartera (60–360)", (f) => f.recaudo_60_360)}
              {filaTabla("Recuperación de cartera (> 360)", (f) => f.recaudo_may360)}
              <tr>
                <td>Δ cartera vs. mes anterior</td>
                <td
                  className={`num ${deltaCartera != null && deltaCartera > 0 ? "dash-neg" : ""}`}
                  colSpan={cmp ? 3 : 1}
                >
                  {deltaCartera == null
                    ? "Sin mes anterior cargado"
                    : `${deltaCartera >= 0 ? "+" : "−"}${fmtMillones(Math.abs(deltaCartera))}`}
                </td>
              </tr>
            </tbody>
          </table>
          <div className="dash-nota">
            Saldo a favor y saldo financiado entrarán cuando se conecten las
            fuentes saldos_favor y diferidos.
          </div>
        </div>
      </div>
    </>
  );
}
