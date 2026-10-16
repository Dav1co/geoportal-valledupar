import { comoReclamoMetodoBandaDim } from "../tipos";
import { etiquetaPeriodo, fmtDecimal, fmtEntero } from "../formato";
import {
  AVISO_ASOCIACION, FUENTE_A, TRAYECTORIAS, T_LECTURA, T_MODIF, fechaCalculo, porMil, porTrayectoria, solicitudesCP, sumaVacia, tasaCP, useVistaBi,
} from "../reclamosMetodo";

// Resumen en Pérdidas de «Reclamos según el método de facturación». Acumulado de todos los períodos, sin filtros.
// El detalle (nueve partes, filtros y período individual) está en PQR; el botón usa la navegación del tablero.
const t2 = (v: number | null) => (v == null ? "—" : fmtDecimal(v, 2));

export function ReclamosMetodoPerdidas({ onIrAPqr }: { onIrAPqr?: () => void }) {
  const A = useVistaBi("v_reclamo_metodo_banda_dim", comoReclamoMetodoBandaDim);
  if (A.error) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>Reclamos según el método de facturación</h3>
        <div className="dash-estado"><p>No se pudo cargar esta sección: {A.error}</p><button className="dash-boton" onClick={A.recargar}>Reintentar</button></div>
      </div></div>
    );
  }
  if (!A.datos) {
    return <div className="dash-fila"><div className="dash-carta"><h3>Reclamos según el método de facturación</h3><div className="dash-estado">Cargando…</div></div></div>;
  }
  const periodos = [...new Set(A.datos.map((x) => x.periodo))].sort();
  const porTray = porTrayectoria(A.datos);
  const lect = porTray.get(T_LECTURA) ?? sumaVacia();
  const cambian = ["Lectura → promedio", "Promedio → lectura"].reduce((s, t) => {
    const x = porTray.get(t) ?? sumaVacia(); s.contratos += x.contratos; s.consumo += x.consumo; s.promedio += x.promedio; return s;
  }, sumaVacia());
  const modif = porTray.get(T_MODIF) ?? sumaVacia();
  const rl = tasaCP(lect), rc = tasaCP(cambian), rm = tasaCP(modif);
  const veces = rl != null && rl > 0 && rc != null ? rc / rl : null;
  return (
    <div className="dash-fila"><div className="dash-carta">
      <h3>Reclamos según el método de facturación — acumulado de {periodos.length} períodos</h3>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Reclamos por consumo o promedio, por 1.000 contratos-mes</div>
          <div className="dash-valor num">{veces == null ? "—" : `${fmtDecimal(veces, 1)} veces`}</div>
          <div className="dash-sub2">
            {veces == null ? "Sin muestra suficiente."
              : `Los contratos que cambian de método reclaman ${fmtDecimal(veces, 1)} veces lo que reclaman los estables en lectura (${t2(rc)} frente a ${t2(rl)}).`}
          </div>
        </div>
      </div>
      <div className="dash-tabla-scroll">
        <table className="dash-tabla num">
          <thead><tr><th>Trayectoria</th><th>Contratos-mes</th><th>Solicitudes (consumo + promedio)</th><th>Tasa por 1.000 contratos-mes</th></tr></thead>
          <tbody>
            {TRAYECTORIAS.map((t) => {
              const s = porTray.get(t) ?? sumaVacia();
              return <tr key={t}><td>{t}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(solicitudesCP(s))}</td><td className="num">{t2(porMil(solicitudesCP(s), s.contratos))}</td></tr>;
            })}
          </tbody>
        </table>
      </div>
      <div className="dash-nota"><b>{AVISO_ASOCIACION}</b> «Cambian de método»: lectura→promedio y promedio→lectura. Modificación directa, aparte: {t2(rm)} por 1.000 contratos-mes. La modificación directa suele ser consecuencia de un reclamo ya atendido, no su causa.</div>
      <div className="dash-nota">
        Fuente: {FUENTE_A}. Período: acumulado {etiquetaPeriodo(periodos[0])} a {etiquetaPeriodo(periodos[periodos.length - 1])} (sin 202606). Calculado: {fechaCalculo(A.datos)}.
      </div>
      <details><summary>ⓘ Cómo se calcula</summary>
        <div className="dash-nota">Tasa = solicitudes de consumo + promedio × 1.000 ÷ contratos-mes (una solicitud cuenta una vez por contrato y período). Trayectoria = método anterior (período anterior disponible) y método del período; «cambian de método» suma lectura→promedio y promedio→lectura, y «veces» es su tasa ÷ la de estables en lectura. 202606 no existe en la fuente de consumo.</div>
      </details>
      {onIrAPqr ? <button className="dash-boton" onClick={onIrAPqr}>Ir a PQR para más detalle</button> : null}
    </div></div>
  );
}
