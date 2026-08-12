import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { SinDatos } from "../SinDatos";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import {
  comoRecaudoDiaMes,
  comoRecaudoLote,
  type RecaudoDiaMes,
  type RecaudoLote,
} from "../tipos";
import { etiquetaPeriodo, fmtEntero, fmtMillones, fmtPesosCompleto } from "../formato";
import { BarrasHorizontales, LineasPorDia, TablaPlegable, colorAnio } from "../graficas";

// Pantalla del mes EN CURSO. Se alimenta de las conciliaciones bancarias
// que entran cada día, no del cierre mensual: responde "cómo va el mes",
// no "cómo cerró".
//
// La comparación contra meses anteriores se hace SIEMPRE al mismo día de
// corte. Comparar 10 días contra meses completos no diría nada.

const COLOR_CURSO = "#0A2540";

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

export function RecaudoDiario({ periodo, onIrAPeriodo }: Props) {
  const [lotes, setLotes] = useState<RecaudoLote[] | null>(null);
  const [serie, setSerie] = useState<RecaudoDiaMes[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [filtros, setFiltros] = useState<Record<string, string>>({});

  function cargar() {
    setError(null);
    setLotes(null);
    Promise.all([biCache("v_recaudo_diario"), biCache("v_recaudo_diario_mes")])
      .then(([l, s]) => {
        setLotes((l.datos ?? []).map(comoRecaudoLote));
        setSerie((s.datos ?? []).map(comoRecaudoDiaMes));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  // El mes en curso es el que traen las conciliaciones, no el del
  // selector: el selector se mueve sobre los cierres mensuales y este
  // archivo va siempre por delante.
  const enCurso = useMemo(
    () => serie.find((f) => f.origen === "curso")?.periodo ?? null,
    [serie],
  );
  const diaCorte = useMemo(() => {
    const dias = serie.filter((f) => f.origen === "curso").map((f) => f.dia ?? 0);
    return dias.length ? Math.max(...dias) : null;
  }, [serie]);

  const lotesCurso = useMemo(
    () => (lotes ?? []).filter((l) => !enCurso || l.periodo_registro === enCurso),
    [lotes, enCurso],
  );

  const entidades = useMemo(
    () => [...new Set(lotesCurso.map((l) => l.entidad).filter(Boolean))].sort(),
    [lotesCurso],
  );

  const defFiltros: DefFiltro[] = [
    { id: "entidad", etiqueta: "Entidad de recaudo", opciones: entidades, buscable: entidades.length > 8 },
    { id: "cerrada", etiqueta: "Conciliación cerrada", opciones: ["S", "N"] },
  ];

  const lotesFiltrados = useMemo(
    () =>
      lotesCurso.filter(
        (l) =>
          ((filtros.entidad ?? TODOS) === TODOS || l.entidad === filtros.entidad) &&
          ((filtros.cerrada ?? TODOS) === TODOS || l.conciliacion_cerrada === filtros.cerrada),
      ),
    [lotesCurso, filtros],
  );

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar el recaudo diario: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!lotes) return <div className="dash-estado">Cargando recaudo diario…</div>;

  if (!enCurso || lotesCurso.length === 0) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="recaudo diario"
        disponibles={[...new Set(serie.filter((f) => f.origen === "curso").map((f) => f.periodo))]}
        onIr={onIrAPeriodo}
      />
    );
  }

  // ---- totales del mes en curso ----
  const totalCurso = lotesFiltrados.reduce((a, l) => a + (l.valor_procesado ?? 0), 0);
  const cuponesCurso = lotesFiltrados.reduce((a, l) => a + (l.cupones_procesados ?? 0), 0);
  const cerradas = lotesFiltrados.filter((l) => l.conciliacion_cerrada === "S").length;
  const ticket = cuponesCurso > 0 ? totalCurso / cuponesCurso : null;

  // ---- comparación al mismo día de corte ----
  // Para cada período cerrado se toma su acumulado en el mismo día en
  // que va el mes en curso. Es la única comparación honesta.
  const cierres = [...new Set(serie.filter((f) => f.origen === "cierre").map((f) => f.periodo))].sort();
  const acumAlCorte = (per: string): number | null => {
    if (diaCorte == null) return null;
    const hasta = serie
      .filter((f) => f.periodo === per && (f.dia ?? 0) <= diaCorte)
      .sort((a, b) => (b.dia ?? 0) - (a.dia ?? 0))[0];
    return hasta?.valor_acumulado ?? null;
  };
  const comparativa = cierres
    .map((per) => ({ periodo: per, acumulado: acumAlCorte(per) }))
    .filter((c) => c.acumulado != null);
  const promedioPrevios =
    comparativa.length > 0
      ? comparativa.reduce((a, c) => a + (c.acumulado ?? 0), 0) / comparativa.length
      : null;
  const acumCurso = serie
    .filter((f) => f.origen === "curso")
    .sort((a, b) => (b.dia ?? 0) - (a.dia ?? 0))[0]?.valor_acumulado ?? null;
  const brecha =
    acumCurso != null && promedioPrevios != null && promedioPrevios > 0
      ? ((acumCurso - promedioPrevios) / promedioPrevios) * 100
      : null;

  // ---- series para la gráfica día × mes ----
  const anios = cierres.map((p) => Number(p.slice(0, 4)));
  const anioMax = Math.max(...anios, Number(enCurso.slice(0, 4)));
  const porDia = (per: string) =>
    Array.from({ length: 31 }, (_, i) => {
      const f = serie.find((x) => x.periodo === per && x.dia === i + 1);
      return f?.valor_acumulado ?? null;
    });
  const seriesDia = [
    ...cierres.map((per) => ({
      nombre: etiquetaPeriodo(per),
      color: colorAnio(Number(per.slice(0, 4)), anioMax),
      valores: porDia(per),
    })),
    { nombre: `${etiquetaPeriodo(enCurso)} (en curso)`, color: COLOR_CURSO, valores: porDia(enCurso) },
  ];

  // ---- por entidad bancaria ----
  const porEntidad = [...new Map(
    lotesFiltrados.map((l) => [l.entidad, 0]),
  ).keys()]
    .map((ent) => ({
      etiqueta: ent,
      valor: lotesFiltrados.filter((l) => l.entidad === ent).reduce((a, l) => a + (l.valor_procesado ?? 0), 0),
    }))
    .sort((a, b) => b.valor - a.valor);

  // ---- por día del mes en curso ----
  const diasCurso = serie
    .filter((f) => f.origen === "curso")
    .sort((a, b) => (a.dia ?? 0) - (b.dia ?? 0));

  return (
    <>
      <div className="dash-aviso">
        Esta pantalla mide el mes <b>en curso</b> con las conciliaciones
        bancarias del día. Las series de meses anteriores salen del cierre
        mensual (recaudo aplicado al contrato): sirven de referencia al mismo
        día de corte, pero no son la misma medición, así que la diferencia
        entre una y otra no es un descuadre.
      </div>

      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Recaudado en el mes</div>
          <div className="dash-valor num">{fmtMillones(totalCurso)}</div>
          <div className="dash-sub2">
            {etiquetaPeriodo(enCurso)} · {diaCorte ? `al día ${diaCorte}` : "sin corte"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Lotes conciliados</div>
          <div className="dash-valor num">{fmtEntero(lotesFiltrados.length)}</div>
          <div className="dash-sub2">
            {cerradas} cerrados · {lotesFiltrados.length - cerradas} abiertos
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Cupones procesados</div>
          <div className="dash-valor num">{fmtEntero(cuponesCurso)}</div>
          <div className="dash-sub2">
            {ticket != null ? `Ticket promedio ${fmtPesosCompleto(ticket, 0)}` : "—"}
          </div>
        </div>

        <div className={`dash-carta dash-kpi ${brecha != null && brecha < -10 ? "dash-kpi-mal" : ""}`}>
          <div className="dash-eti">Frente al promedio histórico</div>
          <div className="dash-valor num">
            {brecha == null
              ? "—"
              : `${brecha >= 0 ? "+" : "−"}${Math.abs(brecha).toLocaleString("es-CO", { maximumFractionDigits: 1 })} %`}
          </div>
          <div className="dash-sub2">
            {promedioPrevios != null && diaCorte
              ? `${fmtMillones(promedioPrevios)} es el promedio de ${comparativa.length} meses al día ${diaCorte}`
              : "Sin meses cerrados para comparar"}
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Acumulado día a día: el mes en curso sobre los meses cerrados</h3>
          <LineasPorDia
            series={seriesDia}
            formatoValor={fmtMillones}
            formatoEjeY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            diaCorte={diaCorte}
          />
          <div className="dash-nota">
            El eje horizontal es el día del mes, así que las curvas se
            superponen y el mes en curso se lee contra los anteriores en el
            mismo punto del calendario. La línea vertical marca hasta dónde
            llega el dato de hoy: a la derecha de esa marca el mes en curso
            todavía no existe.
          </div>
        </div>
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Comparación al día {diaCorte ?? "—"}</h3>
          <table className="dash-tabla num">
            <thead>
              <tr><th>Período</th><th>Acumulado al día {diaCorte ?? "—"}</th><th>Diferencia</th></tr>
            </thead>
            <tbody>
              <tr className="dash-fila-fuerte">
                <td>{etiquetaPeriodo(enCurso)} <span className="dash-marca">en curso</span></td>
                <td className="num">{fmtMillones(acumCurso)}</td>
                <td className="num">—</td>
              </tr>
              {comparativa.map((c) => {
                const dif = acumCurso != null && c.acumulado != null ? acumCurso - c.acumulado : null;
                return (
                  <tr key={c.periodo}>
                    <td>{etiquetaPeriodo(c.periodo)}</td>
                    <td className="num">{fmtMillones(c.acumulado)}</td>
                    <td className={`num ${dif != null && dif < 0 ? "dash-neg" : ""}`}>
                      {dif == null ? "—" : `${dif >= 0 ? "+" : "−"}${fmtMillones(Math.abs(dif))}`}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div className="dash-carta">
          <h3>Por entidad de recaudo</h3>
          <BarrasHorizontales
            datos={porEntidad.slice(0, 10)}
            formatoValor={fmtMillones}
          />
          <TablaPlegable titulo="Datos: recaudo por entidad">
            <table className="dash-tabla num">
              <thead><tr><th>Entidad</th><th>Recaudado</th><th>Lotes</th></tr></thead>
              <tbody>
                {porEntidad.map((e) => (
                  <tr key={e.etiqueta}>
                    <td>{e.etiqueta}</td>
                    <td className="num">{fmtMillones(e.valor)}</td>
                    <td className="num">
                      {fmtEntero(lotesFiltrados.filter((l) => l.entidad === e.etiqueta).length)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Lotes de conciliación del mes</h3>
          <PanelFiltros
            filtros={defFiltros}
            valores={filtros}
            onCambio={setFiltros}
            resumen={`${fmtEntero(lotesFiltrados.length)} lotes · ${fmtMillones(totalCurso)}`}
          />
          <div className="dash-tabla-scroll">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Día</th><th>Conciliación</th><th>Entidad</th>
                  <th>Cupones</th><th>Valor procesado</th><th>Cerrada</th><th>Automático</th>
                </tr>
              </thead>
              <tbody>
                {lotesFiltrados
                  .slice()
                  .sort((a, b) => b.dia.localeCompare(a.dia))
                  .map((l) => (
                    <tr key={l.conciliacion}>
                      <td>{l.dia.slice(0, 10)}</td>
                      <td>{l.conciliacion}</td>
                      <td>{l.entidad}</td>
                      <td className="num">{fmtEntero(l.cupones_procesados)}</td>
                      <td className="num">{fmtPesosCompleto(l.valor_procesado, 0)}</td>
                      <td>{l.conciliacion_cerrada === "S" ? "Sí" : "No"}</td>
                      <td>{l.cierre_automatico === "S" ? "Sí" : "No"}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
          <div className="dash-nota">
            El valor que cuenta es el <b>procesado</b>, no el informado: el
            informado trae valores de relleno en algunos lotes que inflan el
            total a billones. Por eso esta pantalla no lo muestra.
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Detalle por día</h3>
          <TablaPlegable titulo="Datos: recaudo por día del mes en curso">
            <table className="dash-tabla num">
              <thead>
                <tr><th>Día</th><th>Recaudado</th><th>Acumulado</th><th>Lotes</th></tr>
              </thead>
              <tbody>
                {diasCurso.map((d) => (
                  <tr key={d.fecha}>
                    <td>{d.fecha.slice(0, 10)}</td>
                    <td className="num">{fmtMillones(d.valor_dia)}</td>
                    <td className="num">{fmtMillones(d.valor_acumulado)}</td>
                    <td className="num">{fmtEntero(d.transacciones)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </div>
      </div>
    </>
  );
}
