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
import { BarrasHorizontales, LineasPorDia, TablaPlegable } from "../graficas";

// Pantalla del mes EN CURSO. Se alimenta de las conciliaciones bancarias
// que entran cada día, no del cierre mensual: responde "cómo va el mes",
// no "cómo cerró".
//
// La comparación contra meses anteriores se hace SIEMPRE al mismo día de
// corte. Comparar 10 días contra meses completos no diría nada.

// Único color saturado de las dos gráficas: todo lo demás es gris de
// fondo, así que el mes en curso se identifica sin leer la leyenda.
const COLOR_CURSO = "#0E7C86";

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

export function RecaudoDiario({ periodo, onIrAPeriodo }: Props) {
  const [lotes, setLotes] = useState<RecaudoLote[] | null>(null);
  const [serie, setSerie] = useState<RecaudoDiaMes[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [filtros, setFiltros] = useState<Record<string, string>>({});
  // Series apagadas desde la leyenda. Vive aquí y no dentro de cada
  // gráfica para que las dos compartan el estado: apagar julio en una
  // lo apaga en la otra.
  const [ocultas, setOcultas] = useState<string[]>([]);

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

  // ---- series para las dos gráficas día × mes ----
  // Los meses cerrados son referencia de fondo: gris, de más claro
  // (el más antiguo) a más oscuro. El mes en curso lleva el único
  // color saturado, y la gráfica lo dibuja sólido, grueso y encima.
  const grisDe = (i: number, n: number) => {
    const t = n <= 1 ? 1 : i / (n - 1); // 0 = más antiguo
    const l = Math.round(202 - t * 78); // 202 -> 124
    return `rgb(${l}, ${l + 8}, ${l + 18})`;
  };

  // Último día con dato de cada período: más allá no se dibuja nada,
  // para que el mes en curso termine en el día de corte y no caiga a
  // cero. Dentro del rango, un día sin lote SÍ es cero recaudado.
  const ultimoDiaDe = (per: string) =>
    Math.max(0, ...serie.filter((f) => f.periodo === per).map((f) => f.dia ?? 0));

  const porDia = (per: string, campo: "valor_acumulado" | "valor_dia") => {
    const tope = ultimoDiaDe(per);
    return Array.from({ length: 31 }, (_, i) => {
      if (i + 1 > tope) return null;
      const f = serie.find((x) => x.periodo === per && x.dia === i + 1);
      if (f) return f[campo] ?? 0;
      // Hueco dentro del mes: no hubo recaudo ese día. En el acumulado
      // se deja nulo y la línea lo puentea (el acumulado no baja); en
      // el diario es un cero real y así debe verse.
      return campo === "valor_dia" ? 0 : null;
    });
  };

  const nombreCurso = `${etiquetaPeriodo(enCurso)} (en curso)`;
  const construirSeries = (campo: "valor_acumulado" | "valor_dia") => [
    ...cierres.map((per, i) => ({
      nombre: etiquetaPeriodo(per),
      color: grisDe(i, cierres.length),
      valores: porDia(per, campo),
    })),
    { nombre: nombreCurso, color: COLOR_CURSO, valores: porDia(enCurso, campo) },
  ];
  const seriesAcumulado = construirSeries("valor_acumulado");
  const seriesDiario = construirSeries("valor_dia");

  const alternar = (nombre: string) =>
    setOcultas((prev) =>
      prev.includes(nombre) ? prev.filter((n) => n !== nombre) : [...prev, nombre],
    );

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

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Acumulado día a día: el mes en curso sobre los meses cerrados</h3>
          <LineasPorDia
            series={seriesAcumulado}
            formatoValor={fmtMillones}
            formatoEjeY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            diaCorte={diaCorte}
            destacada={nombreCurso}
            ocultas={ocultas}
            onToggle={alternar}
          />
          <div className="dash-nota">
            Responde <b>cómo va el mes</b>: la distancia vertical entre la
            línea de color y las grises al mismo día es lo que se lleva de
            adelanto o de atraso. La marca vertical señala hasta dónde llega
            el dato de hoy; a su derecha el mes en curso todavía no existe.
          </div>
        </div>

        <div className="dash-carta">
          <h3>Recaudo de cada día, sin acumular</h3>
          <LineasPorDia
            series={seriesDiario}
            formatoValor={fmtMillones}
            formatoEjeY={(v) => (v / 1e6).toLocaleString("es-CO", { maximumFractionDigits: 0 }) + " M"}
            diaCorte={diaCorte}
            destacada={nombreCurso}
            ocultas={ocultas}
            onToggle={alternar}
          />
          <div className="dash-nota">
            La misma serie sin acumular responde otra pregunta: <b>qué días
            entra la plata</b>. Aquí se ven los picos de vencimiento y los
            días sin recaudo, que la curva acumulada esconde porque solo
            puede subir o quedarse plana.
          </div>
        </div>
      </div>

      <div className="dash-nota" style={{ marginTop: "-6px" }}>
        Los meses cerrados van en gris punteado y el mes en curso en color:
        son referencia de fondo, no series equivalentes. Un clic en cualquier
        mes de la leyenda lo enciende o lo apaga <b>en las dos gráficas a la
        vez</b>, y el eje se reajusta a lo que quede visible.
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
