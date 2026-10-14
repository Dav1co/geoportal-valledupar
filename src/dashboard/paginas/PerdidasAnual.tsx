import { anioTarifarioDe, type IpufAnual } from "../ipufAnual";
import { etiquetaPeriodo, fmtIpuf, fmtMillonesEnteros, fmtPct } from "../formato";
import { BarrasAnuales, LineasPorcentaje, TablaPlegable } from "../graficas";

// Bloques ANUALES de Pérdidas (por año tarifario, jul-jun). Se agregan a la
// pantalla sin tocar los mensuales. Los cálculos viven en ../ipufAnual.ts.
// Mismos colores que la pantalla mensual.
const COLOR_IPUF = "#0A2540";
const COLOR_META = "#C98A2D";
const COLOR_ESTANDAR = "#9AA7B5";
const COLOR_ICUF = "#0E7C86";

// "2026-27 (parcial, 3 meses)"
const rotulo = (a: IpufAnual) => (a.parcial ? `${a.etiqueta} (parcial, ${a.meses} meses)` : a.etiqueta);
const marca = (a: IpufAnual) => (a.parcial ? `${a.etiqueta}*` : a.etiqueta);
const signo = (v: number | null) =>
  v == null ? "—" : `${v >= 0 ? "+" : "−"}${fmtIpuf(Math.abs(v), false)}`;
// "jun 2025"
const mesAnio = (p: string) => etiquetaPeriodo(p).replace(/^(\p{L}{3})\p{L}*/u, "$1");

// ---------------------------------------------------------------------
// ARRIBA: gráfica pequeña del IPUF anual + tabla resumen por año tarifario.
// ---------------------------------------------------------------------
export function IpufAnualBloque({ anual, periodo }: { anual: IpufAnual[]; periodo: string }) {
  if (anual.length === 0) return null;
  const anioSel = anioTarifarioDe(periodo).inicio;
  const cambios = anual.filter((a) => a.cambioMeta);
  const metaEsEstandar = anual.some((a) => a.meta != null && a.estandar != null && Math.abs(a.meta - a.estandar) < 1e-9);
  const estandar = anual[anual.length - 1].estandar;
  const hayParcial = anual.some((a) => a.parcial);

  return (
    <div className="dash-fila-g2">
      <div className="dash-carta">
        <h3>IPUF anual por año tarifario</h3>
        <BarrasAnuales
          datos={anual.map((a) => ({ etiqueta: marca(a), valor: a.ipuf, meta: a.meta, parcial: a.parcial }))}
          estandar={estandar}
          formatoValor={fmtIpuf}
          formatoCorto={(v) => fmtIpuf(v, false)}
          tituloY="m³/susc·mes"
          nombreValor="IPUF anual"
          nombreMeta="Meta EMDUPAR"
          nombreEstandar="Estándar regulatorio"
          color={COLOR_IPUF}
          colorMeta={COLOR_META}
          colorEstandar={COLOR_ESTANDAR}
        />
        {hayParcial && <div className="dash-nota">* Año parcial: jul–sep 2026 (3 meses).</div>}
      </div>

      <div className="dash-carta">
        <h3>Resumen por año tarifario</h3>
        <div className="dash-tabla-scroll">
          <table className="dash-tabla num">
            <thead>
              <tr>
                <th>Año tarifario</th><th>IPUF anual (m³/susc·mes)</th><th>Meta EMDUPAR</th>
                <th>Diferencia contra la meta</th><th>Estándar</th>
                <th>Pérdida total ($)</th><th>Exceso sobre la meta ($)</th>
              </tr>
            </thead>
            <tbody>
              {[...anual].reverse().map((a) => (
                <tr key={a.inicio} className={a.inicio === anioSel ? "dash-fila-fuerte" : ""}>
                  <td>{rotulo(a)}</td>
                  <td className="num">{fmtIpuf(a.ipuf, false)}</td>
                  <td className="num">{fmtIpuf(a.meta, false)}</td>
                  <td className={`num ${a.difMeta != null && a.difMeta > 0 ? "dash-neg" : ""}`}>{signo(a.difMeta)}</td>
                  <td className="num">{fmtIpuf(a.estandar, false)}</td>
                  <td className="num">{fmtMillonesEnteros(a.pesosTotal)}</td>
                  <td className="num">{fmtMillonesEnteros(a.pesosSobreMeta)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="dash-nota">
          IPUF anual = (agua producida − agua facturada) ÷ (suscriptores promedio × meses), con el
          año tarifario de julio a junio; el año parcial usa solo sus meses. Se muestra desde
          2017-18 (el 2016-17 solo tiene 6 meses).
          {cambios.map((a) => (
            <span key={a.inicio}>
              {" "}La meta de {a.etiqueta} es el promedio ponderado por suscriptores: cambió de{" "}
              {fmtIpuf(a.cambioMeta!.de, false)} a {fmtIpuf(a.cambioMeta!.a, false)} en {mesAnio(a.cambioMeta!.periodo)}.
            </span>
          ))}
          {metaEsEstandar && (
            <> Desde jul 2026 (Res. CRA 1032) no hay meta transitoria: la meta es el estándar regulatorio.</>
          )}
          {" "}Exceso sobre la meta = suma mensual de máx(0, IPUF − meta) × suscriptores × tarifa por m³ del mes.
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// ABAJO: IANC, ICUF e ISUF por año tarifario.
// ---------------------------------------------------------------------
export function IndicesAnualesSeccion({ anual }: { anual: IpufAnual[] }) {
  if (anual.length === 0) return null;
  const etiquetas = anual.map(marca);
  const hayParcial = anual.some((a) => a.parcial);
  const serie = (f: (a: IpufAnual) => number | null) => anual.map(f);

  return (
    <>
      <div className="dash-fila-g2">
        <div className="dash-carta">
          <h3>ICUF, ISUF e IPUF por año tarifario</h3>
          <LineasPorcentaje
            etiquetas={etiquetas}
            series={[
              { nombre: "ISUF (agua producida por suscriptor)", color: COLOR_IPUF, valores: serie((a) => a.isuf) },
              { nombre: "ICUF (agua facturada por suscriptor)", color: COLOR_ICUF, valores: serie((a) => a.icuf) },
              { nombre: "IPUF anual (ISUF − ICUF)", color: COLOR_META, valores: serie((a) => a.ipuf) },
            ]}
            tituloY="m³/susc·mes"
            formatoTick={(t) => t.toLocaleString("es-CO", { maximumFractionDigits: 0 })}
            formatoValor={fmtIpuf}
            sinTope
            paso={4}
            alto={260}
          />
        </div>
        <div className="dash-carta">
          <h3>IANC por año tarifario</h3>
          <LineasPorcentaje
            etiquetas={etiquetas}
            series={[{ nombre: "IANC (agua no contabilizada)", color: COLOR_ESTANDAR, valores: serie((a) => a.ianc) }]}
            alto={260}
          />
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <TablaPlegable titulo="Datos: IANC, ICUF e ISUF por año tarifario">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Año tarifario</th><th>IANC (%)</th><th>ICUF (m³/susc·mes)</th>
                  <th>ISUF (m³/susc·mes)</th><th>IPUF anual = ISUF − ICUF</th>
                </tr>
              </thead>
              <tbody>
                {[...anual].reverse().map((a) => (
                  <tr key={a.inicio}>
                    <td>{rotulo(a)}</td>
                    <td className="num">{fmtPct(a.ianc)}</td>
                    <td className="num">{fmtIpuf(a.icuf, false)}</td>
                    <td className="num">{fmtIpuf(a.isuf, false)}</td>
                    <td className="num">{fmtIpuf(a.ipuf, false)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            ICUF = agua facturada ÷ suscriptores; ISUF = agua producida ÷ suscriptores (ambos del año
            tarifario completo, en m³/suscriptor-mes); IANC = (producida − facturada) ÷ producida, en %.
            ISUF − ICUF = IPUF anual.
            {hayParcial && <> * Año parcial: jul–sep 2026 (3 meses).</>}
          </div>
        </div>
      </div>
    </>
  );
}
