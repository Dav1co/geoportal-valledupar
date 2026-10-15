import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoConsolidadoAnio,
  comoConsolidadoMes,
  type ConsolidadoAnio,
  type ConsolidadoMes,
} from "../tipos";
import {
  fmtDeltaPct,
  fmtEnteroCompleto,
  fmtPesosCompleto,
  fmtPct,
} from "../formato";
import { TablaPlegable } from "../graficas";
import { ROTULO } from "../rotulos";

// Consolidado NO abrevia: la pantalla se copia a Excel para informes de
// gerencia y un valor abreviado no se puede sumar ni cruzar.
const MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];

type Props = { periodo: string };

export function Consolidado({ periodo }: Props) {
  const [meses, setMeses] = useState<ConsolidadoMes[] | null>(null);
  const [anios, setAnios] = useState<ConsolidadoAnio[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [anioSel, setAnioSel] = useState<number | null>(null);

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([biCache("v_consolidado_mes"), biCache("v_consolidado_anio")])
      .then(([m, a]) => {
        setMeses((m.datos ?? []).map(comoConsolidadoMes));
        setAnios((a.datos ?? []).map(comoConsolidadoAnio));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  // El año del selector global manda como valor inicial; después el
  // usuario puede cambiarlo aquí sin salir de la pantalla.
  const anioPeriodo = Number(periodo.slice(0, 4));
  const anio = anioSel ?? anioPeriodo;

  const delAnio = useMemo(
    () => (meses ?? []).filter((m) => m.anio === anio).sort((a, b) => (a.mes ?? 0) - (b.mes ?? 0)),
    [meses, anio],
  );

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar el consolidado: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando consolidado…</div>;

  const aniosDisponibles = [...new Set(meses.map((m) => m.anio).filter((a): a is number => a != null))].sort();

  return (
    <>
      <div className="dash-aviso">
        Esta pantalla es para <b>detectar</b>, no para profundizar: muestra el
        año completo con todos los frentes cruzados para ver dónde pasó algo, y
        desde ahí conviene ir a la pantalla específica. Las cifras van
        <b> completas y sin abreviar</b>, para poder copiarlas a Excel.
      </div>

      {/* ================= BLOQUE 1 · TENDENCIA POR VIGENCIA ================= */}
      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Tendencia por vigencia</h3>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla dash-tabla-compacta num">
              <thead>
                <tr>
                  <th>Vigencia</th><th>Meses</th><th>Facturado</th><th>Recaudo total</th>
                  <th>% Recaudo</th><th>Corriente</th><th>Recuperación</th>
                  <th>Cartera al cierre</th><th>Δ cartera</th><th>Δ %</th><th>Rotación (meses)</th>
                </tr>
              </thead>
              <tbody>
                {anios.map((a) => (
                  <tr key={a.anio}>
                    <td>
                      <b>{a.anio}</b>
                      {(a.meses_con_datos ?? 12) < 12 && (
                        <span className="dash-marca"> en curso</span>
                      )}
                    </td>
                    <td className="num">{a.meses_con_datos}</td>
                    <td className="num">{fmtPesosCompleto(a.facturado)}</td>
                    <td className="num">{fmtPesosCompleto(a.recaudo_total)}</td>
                    <td className="num"><b>{fmtPct(a.pct_recaudo)}</b></td>
                    <td className="num">{fmtPesosCompleto(a.recaudo_corriente)}</td>
                    <td className="num">{fmtPesosCompleto(a.recuperacion_cartera)}</td>
                    <td className="num">{fmtPesosCompleto(a.cartera_cierre)}</td>
                    <td className={`num ${(a.var_cartera_anual ?? 0) > 0 ? "dash-neg" : ""}`}>
                      {a.var_cartera_anual == null
                        ? "—"
                        : `${a.var_cartera_anual >= 0 ? "+" : "−"}${fmtPesosCompleto(Math.abs(a.var_cartera_anual))}`}
                    </td>
                    <td className={`num ${(a.var_cartera_anual_pct ?? 0) > 0 ? "dash-neg" : ""}`}>
                      {a.var_cartera_anual_pct == null ? "—" : fmtPct(a.var_cartera_anual_pct)}
                    </td>
                    <td className="num">
                      {a.rotacion_cartera?.toLocaleString("es-CO", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="dash-nota">
            La <b>rotación</b> dice a cuántos meses de facturación equivale la
            deuda acumulada: 20 significa que la cartera pesa como veinte meses
            de facturación. Un año con menos de doce meses está en curso, así
            que su facturado y recaudo son parciales — el % de recaudo sí es
            comparable, porque ambos términos cubren el mismo período.
          </div>
        </div>
      </div>

      {/* ================= BLOQUE 2 · MATRIZ MENSUAL ================= */}
      <div className="dash-fila">
        <div className="dash-carta">
          <div className="dash-tope-der" style={{ marginBottom: 12 }}>
            <h3 style={{ margin: 0 }}>Matriz mensual de {anio}</h3>
            <label className="dash-selper">
              <span>Año</span>
              <select value={anio} onChange={(e) => setAnioSel(Number(e.target.value))}>
                {aniosDisponibles.map((a) => (
                  <option key={a} value={a}>{a}</option>
                ))}
              </select>
            </label>
          </div>

          <div className="dash-tabla-scroll">
            <table className="dash-tabla dash-tabla-compacta num">
              <thead>
                <tr>
                  <th>Mes</th>
                  <th>Facturado neto</th>
                  <th>Recaudo total</th>
                  <th>% Recaudo</th>
                  <th>Recaudo corriente</th>
                  <th>Recuperación cartera</th>
                  <th>Cartera al cierre</th>
                  <th>Δ cartera mes</th>
                  <th>Rotación</th>
                  <th>Notas aplicadas</th>
                  <th>m³ facturados</th>
                  <th>Cupones procesados</th>
                  <th>Ticket facturación</th>
                  <th>Ticket pago</th>
                </tr>
              </thead>
              <tbody>
                {delAnio.map((m) => (
                  <tr key={m.periodo}>
                    <td>{MESES[(m.mes ?? 1) - 1]}</td>
                    <td className="num">{fmtPesosCompleto(m.facturado)}</td>
                    <td className="num">{fmtPesosCompleto(m.recaudo_total)}</td>
                    <td className="num">{fmtPct(m.pct_recaudo)}</td>
                    <td className="num">{fmtPesosCompleto(m.recaudo_corriente)}</td>
                    <td className="num">{fmtPesosCompleto(m.recuperacion_cartera)}</td>
                    <td className="num">{fmtPesosCompleto(m.cartera_total)}</td>
                    <td className={`num ${(m.var_cartera_mes ?? 0) > 0 ? "dash-neg" : ""}`}>
                      {m.var_cartera_mes == null
                        ? "—"
                        : `${m.var_cartera_mes >= 0 ? "+" : "−"}${fmtPesosCompleto(Math.abs(m.var_cartera_mes))}`}
                    </td>
                    <td className="num">
                      {m.rotacion_cartera?.toLocaleString("es-CO", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? "—"}
                    </td>
                    <td className="num dash-neg">{fmtPesosCompleto(m.notas_valor)}</td>
                    <td className="num">{fmtEnteroCompleto(m.m3_acueducto)}</td>
                    <td className="num">
                      {m.cupones_procesados == null
                        ? <span className="dash-marca">sin dato</span>
                        : fmtEnteroCompleto(m.cupones_procesados)}
                    </td>
                    <td className="num">
                      {m.ticket_facturacion == null
                        ? <span className="dash-marca">sin dato</span>
                        : fmtPesosCompleto(m.ticket_facturacion)}
                    </td>
                    <td className="num">
                      {m.ticket_pago == null
                        ? <span className="dash-marca">sin dato</span>
                        : fmtPesosCompleto(m.ticket_pago)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="dash-nota">
            <b>Ticket de facturación</b> = facturado ÷ contratos facturados:
            cuánto se le cobra en promedio a cada suscriptor. <b>Ticket de
            pago</b> = valor de cupones ÷ cupones procesados: cuánto paga la
            gente por transacción. No son lo mismo — alguien puede pagar varias
            facturas juntas o abonar parcialmente. Ambos salen del detalle, que
            conserva 6 períodos: fuera de esa ventana van marcados
            <b> sin dato</b>, nunca en cero.
          </div>
        </div>
      </div>

      {/* ================= VARIACIÓN CONTRA EL AÑO ANTERIOR ================= */}
      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Variación contra el mismo mes del año anterior — {anio}</h3>
          <TablaPlegable titulo="Datos: variación interanual" >
            <table className="dash-tabla dash-tabla-compacta num">
              <thead>
                <tr>
                  <th>Mes</th>
                  <th>Facturado {anio - 1}</th><th>Δ facturado</th>
                  <th>Recaudo {anio - 1}</th><th>Δ recaudo</th>
                  <th>Δ % recaudo (pp)</th>
                  <th>Cartera {anio - 1}</th><th>Δ cartera</th>
                  <th>Δ m³</th><th>Δ cupones</th>
                  <th>Δ ticket facturación</th><th>Δ ticket pago</th>
                </tr>
              </thead>
              <tbody>
                {delAnio.map((m) => (
                  <tr key={m.periodo}>
                    <td>{MESES[(m.mes ?? 1) - 1]}</td>
                    <td className="num">{fmtPesosCompleto(m.facturado_ant)}</td>
                    <td className="num">{fmtDeltaPct(m.facturado, m.facturado_ant)}</td>
                    <td className="num">{fmtPesosCompleto(m.recaudo_total_ant)}</td>
                    <td className="num">{fmtDeltaPct(m.recaudo_total, m.recaudo_total_ant)}</td>
                    <td className="num">
                      {m.pct_recaudo != null && m.pct_recaudo_ant != null
                        ? `${m.pct_recaudo - m.pct_recaudo_ant >= 0 ? "+" : "−"}${Math.abs(m.pct_recaudo - m.pct_recaudo_ant).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}`
                        : "—"}
                    </td>
                    <td className="num">{fmtPesosCompleto(m.cartera_total_ant)}</td>
                    <td className={`num ${(m.cartera_total ?? 0) > (m.cartera_total_ant ?? 0) ? "dash-neg" : ""}`}>
                      {fmtDeltaPct(m.cartera_total, m.cartera_total_ant)}
                    </td>
                    <td className="num">{fmtDeltaPct(m.m3_acueducto, m.m3_acueducto_ant)}</td>
                    <td className="num">{fmtDeltaPct(m.cupones_procesados, m.cupones_procesados_ant)}</td>
                    <td className="num">{fmtDeltaPct(m.ticket_facturacion, m.ticket_facturacion_ant)}</td>
                    <td className="num">{fmtDeltaPct(m.ticket_pago, m.ticket_pago_ant)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El % de recaudo se compara en <b>puntos porcentuales</b>, no en
            porcentaje de variación: pasar de 80 % a 84 % son 4 puntos, no un
            5 % de mejora. En cartera, una variación positiva es mala noticia y
            por eso va resaltada: es deuda que creció.
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Cómo leer esta pantalla</h3>
          <p className="dash-nota" style={{ marginTop: 0 }}>
            Si un mes se sale de la línea, la pantalla especializada dice por
            qué: un salto en <b>notas</b> se explica en Notas por causal; una
            caída del <b>% de recaudo</b>, en {ROTULO.recaudoConsolidado} por composición
            de edades; un salto de <b>cartera</b>, en {ROTULO.carteraDesagregada} por
            barrio y antigüedad; y un cambio en <b>cupones</b> o en el ticket de
            pago, en Cupones por canal.
          </p>
        </div>
      </div>
    </>
  );
}
