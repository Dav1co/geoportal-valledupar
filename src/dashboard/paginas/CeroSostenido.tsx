import { useMemo } from "react";
import type { DesviacionDim } from "../tipos";
import { etiquetaCiclo, etiquetaPeriodo, fmtEntero, fmtPct, numeroCiclo } from "../formato";
import { TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";

// Cero sostenido: contratos con 6 meses o más en consumo cero. Fuente: bi.v_desviacion_dim (sql/27),
// columna contratos_cero_6m, sobre la línea 2 de facturacion_contratos. Se muestra en Pérdidas con los
// filtros de ciclo, uso y estrato de esa pantalla. Es un indicador aparte de la desviación significativa:
// un mismo contrato puede estar en ambos.

type Acum = { total: number; cero6m: number };
const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);

type Props = {
  periodo: string;
  datos: DesviacionDim[] | null;          // null = cargando
  error: string | null;
  onReintentar: () => void;
  valores: Record<string, string>;        // filtros: ciclo, uso, subcategoria
};

export function CeroSostenido({ periodo, datos, error, onReintentar, valores }: Props) {
  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  const filtrado = useMemo(
    () =>
      (datos ?? []).filter(
        (x) =>
          (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
          (valores.uso === TODOS || x.categoria === valores.uso) &&
          (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
      ),
    [datos, nCiclo, valores.uso, valores.subcategoria],
  );
  const { total, porCiclo, porCategoria, porEstrato } = useMemo(() => {
    const total: Acum = { total: 0, cero6m: 0 };
    const ciclos = new Map<number, Acum>();
    const cats = new Map<string, Acum>();
    const estratos = new Map<string, Acum>();
    const en = <K,>(m: Map<K, Acum>, k: K) => {
      if (!m.has(k)) m.set(k, { total: 0, cero6m: 0 });
      return m.get(k)!;
    };
    const sumar = (a: Acum, c: number, z: number) => { a.total += c; a.cero6m += z; };
    for (const x of filtrado) {
      sumar(total, x.contratos, x.contratos_cero_6m);
      sumar(en(ciclos, numeroCiclo(x.ciclo) ?? -1), x.contratos, x.contratos_cero_6m);
      sumar(en(cats, x.categoria), x.contratos, x.contratos_cero_6m);
      if (x.categoria === "Residencial") sumar(en(estratos, x.subcategoria), x.contratos, x.contratos_cero_6m);
    }
    return {
      total,
      porCiclo: [...ciclos.entries()].sort((a, b) => a[0] - b[0]),
      porCategoria: [...cats.entries()].sort((a, b) => b[1].total - a[1].total),
      porEstrato: [...estratos.entries()].sort((a, b) => a[0].localeCompare(b[0], "es")),
    };
  }, [filtrado]);

  const titulo = <h3>Cero sostenido — {etiquetaPeriodo(periodo)}</h3>;
  if (error) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {titulo}
        <div className="dash-estado">
          <p>No se pudo cargar esta sección: {error}</p>
          <button className="dash-boton" onClick={onReintentar}>Reintentar</button>
        </div>
      </div></div>
    );
  }
  if (datos == null) {
    return <div className="dash-fila"><div className="dash-carta">{titulo}<div className="dash-estado">Cargando…</div></div></div>;
  }
  if (datos.length === 0) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {titulo}
        <div className="dash-estado">
          Sin datos de cero sostenido para este período: se calcula solo para períodos con los 6 anteriores
          en facturación por contrato.
        </div>
      </div></div>
    );
  }
  if (filtrado.length === 0) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {titulo}
        <div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>
      </div></div>
    );
  }
  const fila = (clave: string, nombre: string, a: Acum) => (
    <tr key={clave}>
      <td>{nombre}</td>
      <td className="num">{fmtEntero(a.total)}</td>
      <td className="num">{fmtEntero(a.cero6m)}</td>
      <td className="num">{fmtPct(pct(a.cero6m, a.total))}</td>
    </tr>
  );
  return (
    <>
      <div className="dash-fila">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos con 6 meses o más en consumo cero</div>
          <div className="dash-valor num">{fmtEntero(total.cero6m)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(total.cero6m, total.total))} de los {fmtEntero(total.total)} contratos del período</div>
        </div>
      </div>
      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Cero sostenido por ciclo y por categoría</h3>
          <TablaPlegable titulo="Datos: contratos con 6 meses o más en consumo cero">
            <table className="dash-tabla num">
              <thead>
                <tr><th>Grupo</th><th>Contratos</th><th>Cero sostenido</th><th>% de los contratos</th></tr>
              </thead>
              <tbody>
                {porCiclo.map(([n, a]) => fila(`z-${n}`, n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)", a))}
                {porCategoria.map(([nombre, a]) => fila(`zc-${nombre}`, nombre, a))}
                {porEstrato.map(([nombre, a]) => fila(`ze-${nombre}`, `Residencial · ${nombre}`, a))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Cero sostenido: contratos que existen en la facturación y no tienen consumo (línea 2) en el
            período ni en los 5 anteriores. Es un indicador aparte de la desviación: un mismo contrato
            puede estar en ambos.
          </div>
        </div>
      </div>
    </>
  );
}
