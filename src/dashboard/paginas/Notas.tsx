import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoNotasDim,
  comoNotasMes,
  comoNotasVsPqr,
  type NotasDim,
  type NotasMes,
  type NotasVsPqr,
} from "../tipos";
import { etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasHorizontales, BarrasMensuales, TablaPlegable, colorAnio } from "../graficas";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { SinDatos } from "../SinDatos";

const COLOR_SERVICIO: Record<string, string> = {
  ACUEDUCTO: "#0A2540",
  ALCANTARILLADO: "#0E7C86",
  PLUVIAL: "#C98A2D",
  TERCERO: "#C9D4DC",
  OTROS: "#7B5EA7",
};

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

export function Notas({ periodo, onIrAPeriodo }: Props) {
  const [meses, setMeses] = useState<NotasMes[] | null>(null);
  const [dim, setDim] = useState<NotasDim[]>([]);
  const [cruce, setCruce] = useState<NotasVsPqr[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({
    causal: TODOS, signo: TODOS, servicio: TODOS,
  });

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([
      biCache("v_notas_mes"),
      biCache("v_notas_dim", { periodo }),
      biCache("v_notas_vs_pqr"),
    ])
      .then(([m, d, c]) => {
        setMeses((m.datos ?? []).map(comoNotasMes));
        setDim((d.datos ?? []).map(comoNotasDim));
        setCruce((c.datos ?? []).map(comoNotasVsPqr));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, [periodo]);

  const filtros: DefFiltro[] = useMemo(() => {
    const unicos = (f: (x: NotasDim) => string) =>
      [...new Set(dim.map(f))].sort((a, b) => a.localeCompare(b, "es"));
    return [
      { id: "causal", etiqueta: "Causal", opciones: unicos((x) => x.causal), buscable: true },
      { id: "signo", etiqueta: "Tipo", opciones: unicos((x) => x.signo), ayuda: "CR descuenta al usuario · DB le cobra" },
      { id: "servicio", etiqueta: "Servicio", opciones: unicos((x) => x.servicio) },
    ];
  }, [dim]);

  const filtrado = useMemo(
    () =>
      dim.filter(
        (x) =>
          (valores.causal === TODOS || x.causal === valores.causal) &&
          (valores.signo === TODOS || x.signo === valores.signo) &&
          (valores.servicio === TODOS || x.servicio === valores.servicio),
      ),
    [dim, valores],
  );

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar Notas: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando notas…</div>;

  const disponibles = meses.map((m) => m.periodo).sort();
  const sel = meses.find((m) => m.periodo === periodo);
  if (!sel) {
    return (
      <SinDatos periodo={periodo} fuente="notas" disponibles={disponibles} onIr={onIrAPeriodo} />
    );
  }

  const listaAnios = [...new Set(meses.map((m) => m.anio).filter((a): a is number => a != null))].sort();
  const anioMax = Math.max(...listaAnios);
  // Barras del valor CRÉDITO en positivo: es la magnitud del ajuste a
  // favor del usuario, que es lo que interesa dimensionar.
  const series = listaAnios.map((a) => ({
    nombre: String(a),
    color: colorAnio(a, anioMax),
    valores: Array.from({ length: 12 }, (_, i) =>
      meses.find((m) => m.anio === a && m.mes === i + 1)?.valor_credito_abs ?? null),
  }));

  const agrupar = (clave: (x: NotasDim) => string, campo: "cantidad" | "valor") => {
    const m = new Map<string, number>();
    for (const x of filtrado) m.set(clave(x), (m.get(clave(x)) ?? 0) + (x[campo] ?? 0));
    return [...m.entries()].map(([etiqueta, valor]) => ({ etiqueta, valor }));
  };

  const porCausalValor = agrupar((x) => x.causal, "valor")
    .map((c) => ({ ...c, valor: Math.abs(c.valor) }))
    .sort((a, b) => b.valor - a.valor);
  const porCausalCant = new Map(agrupar((x) => x.causal, "cantidad").map((c) => [c.etiqueta, c.valor]));
  const porServicio = agrupar((x) => x.servicio, "valor")
    .map((c) => ({ ...c, valor: Math.abs(c.valor) }))
    .sort((a, b) => b.valor - a.valor);

  const totalCant = filtrado.reduce((s, x) => s + (x.cantidad ?? 0), 0);
  const totalValor = filtrado.reduce((s, x) => s + (x.valor ?? 0), 0);

  const cruceOrdenado = [...cruce]
    .filter((c) => c.notas != null && c.reclamos != null)
    .sort((a, b) => b.periodo.localeCompare(a.periodo));

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={`${fmtEntero(totalCant)} notas · ${fmtMillones(totalValor)}`}
      />

      <div className="dash-con-panel-cuerpo">
        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Notas del mes</div>
            <div className="dash-valor num">{fmtEntero(sel.notas)}</div>
            <div className="dash-sub2">
              {fmtEntero(sel.notas_credito)} crédito · {fmtEntero(sel.notas_debito)} débito
            </div>
          </div>
          <div className="dash-carta dash-kpi dash-kpi-mal">
            <div className="dash-eti">Valor neto ajustado</div>
            <div className="dash-valor num">{fmtMillones(sel.valor_neto)}</div>
            <div className="dash-sub2">negativo = se descontó al usuario</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Notas crédito</div>
            <div className="dash-valor num">{fmtMillones(sel.valor_credito_abs)}</div>
            <div className="dash-sub2">facturación que hubo que devolver</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Notas débito</div>
            <div className="dash-valor num">{fmtMillones(sel.valor_debito)}</div>
            <div className="dash-sub2">cobro adicional al usuario</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Contratos afectados</div>
            <div className="dash-valor num">{fmtEntero(sel.contratos_afectados)}</div>
            <div className="dash-sub2">recibieron al menos una nota</div>
          </div>
        </div>

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Notas crédito por mes y año</h3>
            <BarrasMensuales
              series={series}
              formatoY={(v) => (v / 1e6).toLocaleString("es-CO", { maximumFractionDigits: 0 }) + " M"}
              formatoTitulo={fmtMillones}
            />
            <TablaPlegable titulo="Datos: serie mensual de notas">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Período</th><th>Notas</th><th>Crédito</th><th>Débito</th>
                    <th>Valor crédito</th><th>Valor neto</th><th>Contratos</th>
                  </tr>
                </thead>
                <tbody>
                  {[...meses].sort((a, b) => b.periodo.localeCompare(a.periodo)).map((m) => (
                    <tr key={m.periodo}>
                      <td>{etiquetaPeriodo(m.periodo)}</td>
                      <td className="num">{fmtEntero(m.notas)}</td>
                      <td className="num">{fmtEntero(m.notas_credito)}</td>
                      <td className="num">{fmtEntero(m.notas_debito)}</td>
                      <td className="num">{fmtMillones(m.valor_credito_abs)}</td>
                      <td className="num dash-neg">{fmtMillones(m.valor_neto)}</td>
                      <td className="num">{fmtEntero(m.contratos_afectados)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              Las barras muestran el crédito en positivo para poder dimensionarlo;
              en la tabla el valor conserva su signo original, como viene del
              sistema.
            </div>
          </div>
        </div>

        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Causales por monto — {etiquetaPeriodo(periodo)}</h3>
            <BarrasHorizontales datos={porCausalValor.slice(0, 12)} formatoValor={fmtMillones} />
            <TablaPlegable titulo={`Datos: causales (${porCausalValor.length})`}>
              <table className="dash-tabla num">
                <thead><tr><th>Causal</th><th>Notas</th><th>Valor</th><th>% del monto</th></tr></thead>
                <tbody>
                  {porCausalValor.map((c) => {
                    const tot = porCausalValor.reduce((s, x) => s + x.valor, 0);
                    return (
                      <tr key={c.etiqueta}>
                        <td>{c.etiqueta}</td>
                        <td className="num">{fmtEntero(porCausalCant.get(c.etiqueta) ?? 0)}</td>
                        <td className="num">{fmtMillones(c.valor)}</td>
                        <td className="num">{fmtPct(tot ? (c.valor / tot) * 100 : null)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              Ordenado por monto absoluto: una causal con pocas notas de alto
              valor pesa más que muchas notas pequeñas.
            </div>
          </div>

          <div className="dash-carta">
            <h3>Por servicio</h3>
            <BarrasHorizontales
              datos={porServicio}
              formatoValor={fmtMillones}
              color={COLOR_SERVICIO.ALCANTARILLADO}
            />
            <TablaPlegable titulo="Datos: por servicio">
              <table className="dash-tabla num">
                <thead><tr><th>Servicio</th><th>Valor</th></tr></thead>
                <tbody>
                  {porServicio.map((s) => (
                    <tr key={s.etiqueta}>
                      <td>
                        <i className="dash-punto" style={{ background: COLOR_SERVICIO[s.etiqueta] ?? "#C9D4DC" }} />
                        {s.etiqueta}
                      </td>
                      <td className="num">{fmtMillones(s.valor)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              El servicio sale de la ruta contable del concepto ajustado.
            </div>
          </div>
        </div>

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>¿Las notas responden a reclamos?</h3>
            <div className="dash-aviso">
              Esto muestra <b>co-ocurrencia en el tiempo</b>, no causalidad: que
              un mes tenga muchas notas y muchos reclamos no prueba que un
              reclamo concreto haya originado una nota concreta. Para eso habría
              que cruzar por contrato y fecha, que es posible pero es otro
              trabajo. Los catálogos de causal de notas y de reclamos son
              distintos, así que tampoco se emparejan por texto.
            </div>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Período</th><th>Notas</th><th>Valor crédito</th>
                    <th>Reclamos</th><th>Valor reclamado</th><th>Notas por reclamo</th>
                  </tr>
                </thead>
                <tbody>
                  {cruceOrdenado.map((c) => (
                    <tr key={c.periodo}>
                      <td>{etiquetaPeriodo(c.periodo)}</td>
                      <td className="num">{fmtEntero(c.notas)}</td>
                      <td className="num">{fmtMillones(c.valor_credito_abs)}</td>
                      <td className="num">{fmtEntero(c.reclamos)}</td>
                      <td className="num">{fmtMillones(c.valor_reclamado)}</td>
                      <td className="num">
                        {c.notas_por_reclamo?.toLocaleString("es-CO", { maximumFractionDigits: 2 }) ?? "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="dash-nota">
              Solo aparecen los meses en que ambas fuentes tienen datos: notas
              llega desde 2023 y PQR desde 2025, con huecos propios.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
