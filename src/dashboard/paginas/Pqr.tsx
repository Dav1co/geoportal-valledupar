import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { comoPqrDim, comoPqrMes, type PqrDim, type PqrMes } from "../tipos";
import { etiquetaCorta, etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasHorizontales, LineasPorcentaje, TablaPlegable } from "../graficas";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { AvisoHuecos, SinDatos, huecosDe } from "../SinDatos";

const TOP = 15;

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

export function Pqr({ periodo, onIrAPeriodo }: Props) {
  const [meses, setMeses] = useState<PqrMes[] | null>(null);
  const [dim, setDim] = useState<PqrDim[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({
    tipo: TODOS, causal: TODOS, area_causante: TODOS, medio_recepcion: TODOS,
  });

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([biCache("v_pqr_mes"), biCache("v_pqr_dim", { periodo })])
      .then(([m, d]) => {
        setMeses((m.datos ?? []).map(comoPqrMes));
        setDim((d.datos ?? []).map(comoPqrDim));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, [periodo]);

  const filtros: DefFiltro[] = useMemo(() => {
    const unicos = (f: (x: PqrDim) => string) =>
      [...new Set(dim.map(f))].sort((a, b) => a.localeCompare(b, "es"));
    return [
      { id: "tipo", etiqueta: "Tipo", opciones: unicos((x) => x.tipo) },
      { id: "causal", etiqueta: "Causal", opciones: unicos((x) => x.causal), buscable: true },
      { id: "area_causante", etiqueta: "Área causante", opciones: unicos((x) => x.area_causante) },
      {
        id: "medio_recepcion",
        etiqueta: "Medio de recepción",
        opciones: unicos((x) => x.medio_recepcion),
        visible: (v) => v.tipo !== "recurso",
        ayuda: "Solo aplica a reclamos",
      },
    ];
  }, [dim]);

  const filtrado = useMemo(
    () =>
      dim.filter(
        (x) =>
          (valores.tipo === TODOS || x.tipo === valores.tipo) &&
          (valores.causal === TODOS || x.causal === valores.causal) &&
          (valores.area_causante === TODOS || x.area_causante === valores.area_causante) &&
          (valores.medio_recepcion === TODOS || x.medio_recepcion === valores.medio_recepcion),
      ),
    [dim, valores],
  );

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar PQR: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando PQR…</div>;

  // ESTÁNDAR DE HUECOS: los períodos disponibles salen de los datos, no
  // del selector global. Si el elegido no está, se dice qué falta.
  const disponibles = meses.map((m) => m.periodo).sort();
  const huecos = huecosDe(disponibles);
  const sel = meses.find((m) => m.periodo === periodo);

  if (!sel) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="reclamos y recursos"
        disponibles={disponibles}
        onIr={onIrAPeriodo}
      />
    );
  }

  const cronologico = [...meses].sort((a, b) => a.periodo.localeCompare(b.periodo));
  // Serie CON HUECOS: se recorre el calendario completo y los meses sin
  // archivo quedan en null — la gráfica los dibuja como corte, no como 0.
  const etiquetas: string[] = [];
  const serieReclamos: (number | null)[] = [];
  const serieAtendidos: (number | null)[] = [];
  if (disponibles.length) {
    let a = Number(disponibles[0].slice(0, 4)), m = Number(disponibles[0].slice(4));
    const fin = disponibles[disponibles.length - 1];
    while (`${a}${String(m).padStart(2, "0")}` <= fin) {
      const p = `${a}${String(m).padStart(2, "0")}`;
      const fila = cronologico.find((x) => x.periodo === p);
      etiquetas.push(etiquetaCorta(p));
      serieReclamos.push(fila?.reclamos ?? null);
      serieAtendidos.push(fila?.pct_atendidos ?? null);
      m += 1;
      if (m > 12) { m = 1; a += 1; }
    }
  }

  const agrupar = (clave: (x: PqrDim) => string) => {
    const mm = new Map<string, number>();
    for (const x of filtrado) mm.set(clave(x), (mm.get(clave(x)) ?? 0) + (x.cantidad ?? 0));
    return [...mm.entries()]
      .map(([etiqueta, valor]) => ({ etiqueta, valor }))
      .sort((p, q) => q.valor - p.valor);
  };

  const porCausal = agrupar((x) => x.causal);
  const porArea = agrupar((x) => x.area_causante);
  const porBarrio = agrupar((x) => x.barrio);
  const porMedio = agrupar((x) => x.medio_recepcion).filter((x) => x.etiqueta !== "(no aplica)");
  const totalFiltrado = filtrado.reduce((s, x) => s + (x.cantidad ?? 0), 0);
  const valorFiltrado = filtrado.reduce((s, x) => s + (x.valor ?? 0), 0);

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={`${fmtEntero(totalFiltrado)} casos · ${fmtMillones(valorFiltrado)}`}
      />

      <div className="dash-con-panel-cuerpo">
        <AvisoHuecos faltantes={huecos} />

        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Reclamos del mes</div>
            <div className="dash-valor num">{fmtEntero(sel.reclamos)}</div>
            <div className="dash-sub2">{etiquetaPeriodo(periodo)}</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Atendidos</div>
            <div className="dash-valor num">{fmtPct(sel.pct_atendidos)}</div>
            <div className="dash-sub2">
              {fmtEntero(sel.reclamos_atendidos)} atendidos ·{" "}
              {fmtEntero(sel.reclamos_pendientes)} aún registrados
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Días de atención</div>
            <div className="dash-valor num">
              {sel.dias_atencion_prom != null
                ? sel.dias_atencion_prom.toLocaleString("es-CO", { maximumFractionDigits: 1 })
                : "—"}
            </div>
            <div className="dash-sub2">promedio entre registro y atención</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Recursos</div>
            <div className="dash-valor num">{fmtEntero(sel.recursos)}</div>
            <div className="dash-sub2">
              {fmtPct(sel.pct_recursos_sobre_reclamos)} de los reclamos escaló
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Valor reclamado</div>
            <div className="dash-valor num">{fmtMillones(sel.valor_reclamado)}</div>
            <div className="dash-sub2">
              {fmtEntero(sel.contratos_reclamantes)} contratos distintos
            </div>
          </div>
        </div>

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Reclamos por mes y porcentaje atendido</h3>
            <LineasPorcentaje
              etiquetas={etiquetas}
              series={[
                { nombre: "% atendidos", color: "#0E7C86", valores: serieAtendidos },
              ]}
            />
            <TablaPlegable titulo="Datos: serie mensual de PQR">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Período</th><th>Reclamos</th><th>Atendidos</th><th>Pendientes</th>
                    <th>% atendido</th><th>Días</th><th>Recursos</th>
                  </tr>
                </thead>
                <tbody>
                  {[...cronologico].reverse().map((f) => (
                    <tr key={f.periodo}>
                      <td>{etiquetaPeriodo(f.periodo)}</td>
                      <td className="num">{fmtEntero(f.reclamos)}</td>
                      <td className="num">{fmtEntero(f.reclamos_atendidos)}</td>
                      <td className="num">{fmtEntero(f.reclamos_pendientes)}</td>
                      <td className="num">{fmtPct(f.pct_atendidos)}</td>
                      <td className="num">
                        {f.dias_atencion_prom?.toLocaleString("es-CO", { maximumFractionDigits: 1 }) ?? "—"}
                      </td>
                      <td className="num">{fmtEntero(f.recursos)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              La tabla solo lista los meses con archivo: los faltantes no
              aparecen como fila en cero, porque no hubo dato, no hubo cero.
            </div>
          </div>
        </div>

        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Causales más frecuentes — {etiquetaPeriodo(periodo)}</h3>
            <BarrasHorizontales datos={porCausal.slice(0, TOP)} formatoValor={fmtEntero} />
            <TablaPlegable titulo={`Datos: causales (${porCausal.length})`}>
              <table className="dash-tabla num">
                <thead><tr><th>Causal</th><th>Casos</th><th>%</th></tr></thead>
                <tbody>
                  {porCausal.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtEntero(c.valor)}</td>
                      <td className="num">{fmtPct(totalFiltrado ? (c.valor / totalFiltrado) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>

          <div className="dash-carta">
            <h3>Área causante</h3>
            <BarrasHorizontales datos={porArea.slice(0, TOP)} formatoValor={fmtEntero} color="#0E7C86" />
            <TablaPlegable titulo="Datos: por área causante">
              <table className="dash-tabla num">
                <thead><tr><th>Área</th><th>Casos</th><th>%</th></tr></thead>
                <tbody>
                  {porArea.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtEntero(c.valor)}</td>
                      <td className="num">{fmtPct(totalFiltrado ? (c.valor / totalFiltrado) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>
        </div>

        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Barrios con más PQR</h3>
            <BarrasHorizontales datos={porBarrio.slice(0, TOP)} formatoValor={fmtEntero} color="#C98A2D" />
            <TablaPlegable titulo={`Datos: por barrio (${porBarrio.length})`}>
              <table className="dash-tabla num">
                <thead><tr><th>Barrio</th><th>Casos</th></tr></thead>
                <tbody>
                  {porBarrio.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtEntero(c.valor)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              El barrio viene del sistema con su código ("455 - DON CARMELO");
              aquí se muestra solo el nombre.
            </div>
          </div>

          <div className="dash-carta">
            <h3>Medio de recepción</h3>
            <BarrasHorizontales datos={porMedio} formatoValor={fmtEntero} color="#8FB4CE" />
            <TablaPlegable titulo="Datos: por medio de recepción">
              <table className="dash-tabla num">
                <thead><tr><th>Medio</th><th>Casos</th><th>%</th></tr></thead>
                <tbody>
                  {porMedio.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtEntero(c.valor)}</td>
                      <td className="num">{fmtPct(totalFiltrado ? (c.valor / totalFiltrado) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>
        </div>
      </div>
    </div>
  );
}
