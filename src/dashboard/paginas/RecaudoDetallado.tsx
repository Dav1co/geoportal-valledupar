import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoConceptoMapa,
  comoRecaudoDetalleDim,
  comoRecaudoDia,
  type ConceptoMapa,
  type RecaudoDetalleDim,
  type RecaudoDia,
} from "../tipos";
import { etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasHorizontales, LineasPorDia, TablaPlegable, colorAnio } from "../graficas";
import { SinDatos } from "../SinDatos";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { ROTULO } from "../rotulos";

const DIAS_SEMANA = ["", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];

type Props = { periodo: string };

export function RecaudoDetallado({ periodo }: Props) {
  const [dias, setDias] = useState<RecaudoDia[] | null>(null);
  const [detalle, setDetalle] = useState<RecaudoDetalleDim[]>([]);
  const [mapa, setMapa] = useState<ConceptoMapa[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({ servicio: TODOS, concepto: TODOS });

  function cargar() {
    setError(null);
    setDias(null);
    Promise.all([
      biCache("v_recaudo_diario_cierre"),
      biCache("v_recaudo_detalle_dim", { periodo }),
      biCache("v_concepto_mapa"),
    ])
      .then(([d, x, m]) => {
        setDias((d.datos ?? []).map(comoRecaudoDia));
        setDetalle((x.datos ?? []).map(comoRecaudoDetalleDim));
        setMapa((m.datos ?? []).map(comoConceptoMapa));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, [periodo]);

  // concepto → servicio y nombre, para filtrar y rotular sin más llamadas.
  const porConcepto = useMemo(() => {
    const m = new Map<number, ConceptoMapa>();
    for (const c of mapa) if (c.concepto_num != null) m.set(c.concepto_num, c);
    return m;
  }, [mapa]);

  const filtros: DefFiltro[] = useMemo(() => {
    const servicios = [...new Set(
      detalle.map((d) => (d.concepto_num != null ? porConcepto.get(d.concepto_num)?.servicio : null))
        .filter((s): s is string => !!s),
    )].sort();
    const conceptos = [...new Set(detalle.map((d) => d.concepto_num).filter((c): c is number => c != null))]
      .filter((c) => valores.servicio === TODOS || porConcepto.get(c)?.servicio === valores.servicio)
      .sort((a, b) => a - b)
      .map((c) => `${c} · ${porConcepto.get(c)?.nombre ?? "sin nombre"}`);
    return [
      { id: "servicio", etiqueta: "Servicio", opciones: servicios },
      {
        id: "concepto",
        etiqueta: "Concepto",
        opciones: conceptos,
        ayuda: "Se acota al servicio elegido",
      },
    ];
  }, [detalle, porConcepto, valores.servicio]);

  const filtrado = useMemo(() => {
    return detalle.filter((d) => {
      if (d.concepto_num == null) return false;
      const info = porConcepto.get(d.concepto_num);
      if (valores.servicio !== TODOS && info?.servicio !== valores.servicio) return false;
      if (valores.concepto !== TODOS && !valores.concepto.startsWith(`${d.concepto_num} ·`)) return false;
      return true;
    });
  }, [detalle, porConcepto, valores]);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar el {ROTULO.recaudoDesagregado.toLowerCase()}: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!dias) return <div className="dash-estado">Cargando detalle diario…</div>;

  const disponibles = [...new Set(dias.map((d) => d.periodo))].sort();
  if (!disponibles.includes(periodo)) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="detalle diario de recaudo"
        disponibles={disponibles}
      />
    );
  }

  // Serie diaria del período elegido y de los anteriores, alineadas por
  // DÍA DEL MES para compararlas al mismo día de corte.
  const porDia = (p: string, campo: "valor_dia" | "valor_acumulado") => {
    const arr: (number | null)[] = Array.from({ length: 31 }, () => null);
    for (const d of dias) {
      if (d.periodo === p && d.dia != null) arr[d.dia - 1] = d[campo];
    }
    return arr;
  };

  const delPeriodo = dias.filter((d) => d.periodo === periodo);
  const diaCorte = Math.max(...delPeriodo.map((d) => d.dia ?? 0));
  const anteriores = disponibles.filter((p) => p < periodo).slice(-2);
  const anioMax = Number(periodo.slice(0, 4));

  const seriesAcum = [
    { nombre: etiquetaPeriodo(periodo), color: "#0A2540", valores: porDia(periodo, "valor_acumulado") },
    ...anteriores.map((p, i) => ({
      nombre: etiquetaPeriodo(p),
      color: colorAnio(anioMax - (anteriores.length - i), anioMax),
      valores: porDia(p, "valor_acumulado"),
    })),
  ];

  // KPIs del período (el filtro afecta a los montos por concepto).
  const totalFiltrado = filtrado.reduce((s, d) => s + (d.valor ?? 0), 0);
  const trxFiltradas = filtrado.reduce((s, d) => s + (d.transacciones ?? 0), 0);
  const totalPeriodo = delPeriodo.reduce((s, d) => s + (d.valor_dia ?? 0), 0);
  const diasConRecaudo = delPeriodo.length;
  const promedioDiario = diasConRecaudo ? totalFiltrado / diasConRecaudo : 0;
  const mejorDia = [...delPeriodo].sort((a, b) => (b.valor_dia ?? 0) - (a.valor_dia ?? 0))[0];
  const contratosMax = Math.max(...delPeriodo.map((d) => d.contratos_pagaron ?? 0));

  // Patrón por día de la semana, sobre todos los períodos disponibles.
  const porDiaSemana = [1, 2, 3, 4, 5, 6, 7].map((n) => {
    const delDia = dias.filter((d) => d.dia_semana === n);
    return {
      etiqueta: DIAS_SEMANA[n],
      valor: delDia.reduce((s, d) => s + (d.valor_dia ?? 0), 0),
    };
  });

  // Recaudo por concepto en el corte filtrado.
  const porConceptoTabla = [...filtrado.reduce((m, d) => {
    const k = d.concepto_num ?? 0;
    const a = m.get(k) ?? { valor: 0, trx: 0 };
    a.valor += d.valor ?? 0;
    a.trx += d.transacciones ?? 0;
    m.set(k, a);
    return m;
  }, new Map<number, { valor: number; trx: number }>()).entries()]
    .sort((a, b) => b[1].valor - a[1].valor)
    .slice(0, 25);

  const diarioFiltrado = Array.from({ length: 31 }, (_, i) => {
    const dia = i + 1;
    const fechas = new Set(delPeriodo.filter((d) => d.dia === dia).map((d) => d.fecha));
    const v = filtrado.filter((d) => fechas.has(d.fecha)).reduce((s, d) => s + (d.valor ?? 0), 0);
    return fechas.size ? v : null;
  });

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={`${fmtMillones(totalFiltrado)} · ${fmtEntero(trxFiltradas)} transacciones`}
      />

      <div className="dash-con-panel-cuerpo">
        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Recaudo del corte</div>
            <div className="dash-valor num">{fmtMillones(totalFiltrado)}</div>
            <div className="dash-sub2">
              {totalFiltrado < totalPeriodo
                ? `${fmtPct((totalFiltrado / totalPeriodo) * 100)} del total del mes`
                : "todos los conceptos"}
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Días con recaudo</div>
            <div className="dash-valor num">{fmtEntero(diasConRecaudo)}</div>
            <div className="dash-sub2">último día con pagos: {diaCorte}</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Promedio diario</div>
            <div className="dash-valor num">{fmtMillones(promedioDiario)}</div>
            <div className="dash-sub2">sobre los días con recaudo</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Mejor día del mes</div>
            <div className="dash-valor num">{fmtMillones(mejorDia?.valor_dia ?? null)}</div>
            <div className="dash-sub2">día {mejorDia?.dia ?? "—"}</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Transacciones</div>
            <div className="dash-valor num">{fmtEntero(trxFiltradas)}</div>
            <div className="dash-sub2">
              pico de {fmtEntero(contratosMax)} contratos en un día
            </div>
          </div>
        </div>

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Recaudo acumulado día a día — comparación al mismo día</h3>
            <LineasPorDia
              series={seriesAcum}
              formatoValor={fmtMillones}
              formatoEjeY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            />
            <TablaPlegable titulo="Datos: acumulado por día">
              <table className="dash-tabla num">
                <thead>
                  <tr><th>Día</th>{seriesAcum.map((s) => <th key={s.nombre}>{s.nombre}</th>)}</tr>
                </thead>
                <tbody>
                  {Array.from({ length: 31 }, (_, i) => i).map((i) => (
                    <tr key={i}>
                      <td>{i + 1}</td>
                      {seriesAcum.map((s) => (
                        <td key={s.nombre} className="num">{fmtMillones(s.valores[i])}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              Las curvas se alinean por día del mes, no por fecha: así un mes en
              curso se compara con los anteriores al mismo día de corte y no
              contra su cierre completo, que siempre sería mayor.
            </div>
          </div>
        </div>

        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Recaudo por día — {etiquetaPeriodo(periodo)}</h3>
            <LineasPorDia
              series={[{ nombre: "Recaudo del día", color: "#0E7C86", valores: diarioFiltrado }]}
              formatoValor={fmtMillones}
              formatoEjeY={(v) => (v / 1e6).toLocaleString("es-CO", { maximumFractionDigits: 0 }) + " M"}
              alto={240}
            />
            <TablaPlegable titulo="Datos: recaudo por día">
              <table className="dash-tabla num">
                <thead><tr><th>Día</th><th>Recaudo</th><th>Transacciones</th><th>Contratos</th></tr></thead>
                <tbody>
                  {delPeriodo
                    .slice()
                    .sort((a, b) => (a.dia ?? 0) - (b.dia ?? 0))
                    .map((d) => (
                      <tr key={d.fecha}>
                        <td>{d.dia}</td>
                        <td className="num">{fmtMillones(d.valor_dia)}</td>
                        <td className="num">{fmtEntero(d.transacciones)}</td>
                        <td className="num">{fmtEntero(d.contratos_pagaron)}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>

          <div className="dash-carta">
            <h3>Patrón por día de la semana</h3>
            <BarrasHorizontales datos={porDiaSemana} formatoValor={fmtMillones} color="#0A2540" />
            <TablaPlegable titulo="Datos: recaudo por día de la semana">
              <table className="dash-tabla num">
                <thead><tr><th>Día</th><th>Recaudo</th><th>%</th></tr></thead>
                <tbody>
                  {porDiaSemana.map((d) => {
                    const tot = porDiaSemana.reduce((s, x) => s + x.valor, 0);
                    return (
                      <tr key={d.etiqueta}>
                        <td>{d.etiqueta}</td>
                        <td className="num">{fmtMillones(d.valor)}</td>
                        <td className="num">{fmtPct(tot ? (d.valor / tot) * 100 : null)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              Acumulado de todos los períodos con detalle. Sirve para dimensionar
              la atención en caja y los cierres de banco por día.
            </div>
          </div>
        </div>

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Recaudo por concepto — {etiquetaPeriodo(periodo)}</h3>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr><th>Concepto</th><th>Servicio</th><th>Recaudo</th><th>Transacciones</th></tr>
                </thead>
                <tbody>
                  {porConceptoTabla.map(([num, a]) => (
                    <tr key={num}>
                      <td>{num} · {porConcepto.get(num)?.nombre ?? "sin nombre"}</td>
                      <td>{porConcepto.get(num)?.servicio ?? "—"}</td>
                      <td className="num">{fmtMillones(a.valor)}</td>
                      <td className="num">{fmtEntero(a.trx)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="dash-nota">
              Los 25 conceptos de mayor recaudo del corte. El servicio sale de la
              ruta contable oficial; los conceptos sin ficha en la maestra caen a
              "otros ingresos de acueducto" por la regla de respaldo.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
