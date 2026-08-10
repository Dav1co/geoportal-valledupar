import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoCuponesCanal,
  comoCuponesMes,
  type CuponesCanal,
  type CuponesMes,
} from "../tipos";
import { etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasHorizontales, Dona, TablaPlegable } from "../graficas";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { SinDatos } from "../SinDatos";

// Canales: colores fijos por entidad para que se reconozcan entre meses.
const COLOR_ENTIDAD: Record<string, string> = {
  "SUPER GIROS": "#0A2540",
  "BANCO BBVA COLOMBIA": "#0E7C86",
  "EFECTY EFECTIVO LIMITADA": "#C98A2D",
  DAVIVIENDA: "#8FB4CE",
  "BANCO DE BOGOTA": "#7B5EA7",
  BANCOLOMBIA: "#9AA7B5",
  EMDUPAR: "#C9D4DC",
};
const COLOR_OTRO = "#C9D4DC";

// Umbral operativo: por encima de 3 días, la conciliación se considera
// rezagada (la mayoría de canales concilia en menos de un día).
const REZAGO_ALTO = 3;

const fmtPesos = (v: number | null) =>
  v == null ? "—" : `$ ${Math.round(v).toLocaleString("es-CO")}`;

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

export function Cupones({ periodo, onIrAPeriodo }: Props) {
  const [meses, setMeses] = useState<CuponesMes[] | null>(null);
  const [canales, setCanales] = useState<CuponesCanal[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({ entidad: TODOS, agencia: TODOS });

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([biCache("v_cupones_mes"), biCache("v_cupones_canal", { periodo })])
      .then(([m, c]) => {
        setMeses((m.datos ?? []).map(comoCuponesMes));
        setCanales((c.datos ?? []).map(comoCuponesCanal));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, [periodo]);

  const filtros: DefFiltro[] = useMemo(() => {
    const entidades = [...new Set(canales.map((c) => c.entidad))].sort((a, b) => a.localeCompare(b, "es"));
    const agencias = [...new Set(
      canales.filter((c) => valores.entidad === TODOS || c.entidad === valores.entidad)
        .map((c) => c.agencia),
    )].sort((a, b) => a.localeCompare(b, "es"));
    return [
      { id: "entidad", etiqueta: "Entidad recaudadora", opciones: entidades },
      { id: "agencia", etiqueta: "Agencia / cuenta", opciones: agencias, ayuda: "Se acota a la entidad elegida" },
    ];
  }, [canales, valores.entidad]);

  const filtrado = useMemo(
    () =>
      canales.filter(
        (c) =>
          (valores.entidad === TODOS || c.entidad === valores.entidad) &&
          (valores.agencia === TODOS || c.agencia === valores.agencia),
      ),
    [canales, valores],
  );

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar Cupones: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando cupones…</div>;

  const disponibles = meses.map((m) => m.periodo).sort();
  const sel = meses.find((m) => m.periodo === periodo);
  if (!sel) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="cupones de pago (se conservan solo 6 períodos)"
        disponibles={disponibles}
        onIr={onIrAPeriodo}
      />
    );
  }

  // Agregación por entidad (varias agencias por entidad).
  const porEntidad = [...filtrado.reduce((m, c) => {
    const a = m.get(c.entidad) ?? { valor: 0, cupones: 0, rezagoPond: 0 };
    a.valor += c.valor ?? 0;
    a.cupones += c.cupones ?? 0;
    a.rezagoPond += (c.rezago_dias ?? 0) * (c.cupones ?? 0);
    m.set(c.entidad, a);
    return m;
  }, new Map<string, { valor: number; cupones: number; rezagoPond: number }>()).entries()]
    .map(([entidad, a]) => ({
      entidad,
      valor: a.valor,
      cupones: a.cupones,
      ticket: a.cupones ? a.valor / a.cupones : 0,
      // Rezago ponderado por número de cupones: promediar los promedios
      // de cada agencia daría el mismo peso a una con 4 cupones que a
      // otra con 40.000.
      rezago: a.cupones ? a.rezagoPond / a.cupones : 0,
    }))
    .sort((a, b) => b.valor - a.valor);

  const totalValor = porEntidad.reduce((s, e) => s + e.valor, 0);
  const totalCupones = porEntidad.reduce((s, e) => s + e.cupones, 0);

  const donaPartes = porEntidad.slice(0, 6).map((e) => ({
    etiqueta: e.entidad,
    valor: e.valor,
    color: COLOR_ENTIDAD[e.entidad] ?? COLOR_OTRO,
    pct: totalValor ? (e.valor / totalValor) * 100 : null,
  }));

  const rezagados = [...filtrado]
    .filter((c) => (c.rezago_dias ?? 0) >= REZAGO_ALTO)
    .sort((a, b) => (b.rezago_dias ?? 0) - (a.rezago_dias ?? 0));

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={`${fmtEntero(totalCupones)} cupones · ${fmtMillones(totalValor)}`}
      />

      <div className="dash-con-panel-cuerpo">
        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Cupones procesados</div>
            <div className="dash-valor num">{fmtEntero(totalCupones)}</div>
            <div className="dash-sub2">{etiquetaPeriodo(periodo)}</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Valor recaudado</div>
            <div className="dash-valor num">{fmtMillones(totalValor)}</div>
            <div className="dash-sub2">por los canales del corte</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Ticket promedio</div>
            <div className="dash-valor num">
              {fmtPesos(totalCupones ? totalValor / totalCupones : null)}
            </div>
            <div className="dash-sub2 num">
              mediana del mes: {fmtPesos(sel.ticket_mediano)}
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Rezago de conciliación</div>
            <div className="dash-valor num">
              {sel.rezago_dias?.toLocaleString("es-CO", { maximumFractionDigits: 2 }) ?? "—"}
            </div>
            <div className="dash-sub2">
              días promedio entre pago y grabación
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Canales activos</div>
            <div className="dash-valor num">{fmtEntero(porEntidad.length)}</div>
            <div className="dash-sub2">
              {fmtEntero(sel.cupones_rezago_alto)} cupones con más de {REZAGO_ALTO} días
            </div>
          </div>
        </div>

        <div className="dash-fila-g3">
          <div className="dash-carta">
            <h3>Recaudo por entidad — {etiquetaPeriodo(periodo)}</h3>
            <BarrasHorizontales
              datos={porEntidad.map((e) => ({ etiqueta: e.entidad, valor: e.valor }))}
              formatoValor={fmtMillones}
            />
            <TablaPlegable titulo="Datos: por entidad">
              <table className="dash-tabla num">
                <thead>
                  <tr><th>Entidad</th><th>Cupones</th><th>Valor</th><th>%</th><th>Ticket</th><th>Rezago (días)</th></tr>
                </thead>
                <tbody>
                  {porEntidad.map((e) => (
                    <tr key={e.entidad}>
                      <td>
                        <i className="dash-punto" style={{ background: COLOR_ENTIDAD[e.entidad] ?? COLOR_OTRO }} />
                        {e.entidad}
                      </td>
                      <td className="num">{fmtEntero(e.cupones)}</td>
                      <td className="num">{fmtMillones(e.valor)}</td>
                      <td className="num">{fmtPct(totalValor ? (e.valor / totalValor) * 100 : null)}</td>
                      <td className="num">{fmtPesos(e.ticket)}</td>
                      <td className={`num ${e.rezago >= REZAGO_ALTO ? "dash-neg" : ""}`}>
                        {e.rezago.toLocaleString("es-CO", { maximumFractionDigits: 2 })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>

          <div className="dash-carta">
            <h3>Participación</h3>
            <Dona partes={donaPartes} formatoTitulo={fmtMillones} />
            <div className="dash-nota">
              Máximo seis porciones; el resto queda en la tabla de la izquierda.
            </div>
          </div>
        </div>

        {rezagados.length > 0 && (
          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Canales con conciliación lenta</h3>
              <div className="dash-aviso">
                La mayoría de los canales concilia en menos de un día: el pago
                del usuario entra al sistema casi de inmediato. Estos superan
                los {REZAGO_ALTO} días, lo que significa plata ya pagada por el
                usuario que aún no aparece aplicada a su cuenta — y mientras
                tanto figura como deuda.
              </div>
              <div className="dash-tabla-scroll">
                <table className="dash-tabla num">
                  <thead>
                    <tr><th>Entidad</th><th>Agencia</th><th>Cupones</th><th>Valor</th><th>Rezago (días)</th></tr>
                  </thead>
                  <tbody>
                    {rezagados.map((c) => (
                      <tr key={`${c.entidad}-${c.agencia}`}>
                        <td>{c.entidad}</td>
                        <td>{c.agencia}</td>
                        <td className="num">{fmtEntero(c.cupones)}</td>
                        <td className="num">{fmtMillones(c.valor)}</td>
                        <td className="num dash-neg">
                          {c.rezago_dias?.toLocaleString("es-CO", { maximumFractionDigits: 2 })}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Serie mensual de cupones</h3>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Período</th><th>Cupones</th><th>Valor</th>
                    <th>Ticket promedio</th><th>Ticket mediano</th><th>Rezago (días)</th>
                  </tr>
                </thead>
                <tbody>
                  {[...meses].sort((a, b) => b.periodo.localeCompare(a.periodo)).map((m) => (
                    <tr key={m.periodo}>
                      <td>{etiquetaPeriodo(m.periodo)}</td>
                      <td className="num">{fmtEntero(m.cupones)}</td>
                      <td className="num">{fmtMillones(m.valor)}</td>
                      <td className="num">{fmtPesos(m.ticket_promedio)}</td>
                      <td className="num">{fmtPesos(m.ticket_mediano)}</td>
                      <td className="num">
                        {m.rezago_dias?.toLocaleString("es-CO", { maximumFractionDigits: 2 })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="dash-nota">
              El ticket mediano va muy por debajo del promedio (unos $42.000
              contra $64.000): unos pocos pagos grandes elevan la media, así que
              la mediana describe mejor al usuario típico.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
