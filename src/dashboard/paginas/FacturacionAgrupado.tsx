import { useEffect, useState } from "react";
import { biCache } from "../cacheBi";
import { SinDatos } from "../SinDatos";
import {
  comoFacturacionMes,
  comoFacturacionRuta,
  comoFacturacionServicio,
  comoTarifaReferencia,
  type FacturacionMes,
  type FacturacionRuta,
  type FacturacionServicio,
  type TarifaReferencia,
} from "../tipos";
import { etiquetaPeriodo, fmtDelta, fmtMillones, fmtPct } from "../formato";
import { BarrasMensuales, Dona, MESES_CORTO, TablaPlegable, colorAnio } from "../graficas";

// Colores de la dona por servicio — fijos por entidad, tomados de las
// donas del mockup (tinta, agua, ocre, gris). PLUVIAL usa el ocre: el
// par agua/celeste no supera el umbral de distinción del validador.
const COLOR_SERVICIO: Record<string, string> = {
  ACUEDUCTO: "#0A2540",
  ALCANTARILLADO: "#0E7C86",
  PLUVIAL: "#C98A2D",
  TERCERO: "#C9D4DC",
  OTROS: "#7B5EA7",
};

const fmtTarifa = (v: number | null) =>
  v == null ? "—" : `$ ${v.toLocaleString("es-CO", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

type Props = { periodo: string; comparado: string | null };

export function FacturacionAgrupado({ periodo, comparado }: Props) {
  const [meses, setMeses] = useState<FacturacionMes[] | null>(null);
  const [servicios, setServicios] = useState<FacturacionServicio[]>([]);
  const [rutas, setRutas] = useState<FacturacionRuta[]>([]);
  const [tarifas, setTarifas] = useState<TarifaReferencia[]>([]);
  const [error, setError] = useState<string | null>(null);

  function cargar() {
    setError(null);
    setMeses(null);
    Promise.all([
      biCache("v_facturacion_mes"),
      biCache("v_facturacion_servicio"),
      biCache("v_facturacion_ruta"),
      biCache("v_tarifa_referencia"),
    ])
      .then(([m, s, r, t]) => {
        setMeses((m.datos ?? []).map(comoFacturacionMes));
        setServicios((s.datos ?? []).map(comoFacturacionServicio));
        setRutas((r.datos ?? []).map(comoFacturacionRuta));
        setTarifas((t.datos ?? []).map(comoTarifaReferencia));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar la facturación: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!meses) return <div className="dash-estado">Cargando facturación…</div>;

  const porPeriodo = new Map(meses.map((f) => [f.periodo, f]));
  const sel = porPeriodo.get(periodo);
  const cmp = comparado ? porPeriodo.get(comparado) : undefined;
  if (!sel) {
    return <SinDatos periodo={periodo} fuente="facturación" disponibles={meses.map((f) => f.periodo)} />;
  }

  // Barras: la NETA mensual por año (sin superponer la bruta).
  const anios = [...new Set(meses.map((f) => f.anio).filter((a): a is number => a != null))].sort();
  const anioMax = Math.max(...anios);
  // En comparación entre años distintos, la tabla suma una columna Δ mes
  // a mes; entre meses del mismo año la Δ va como nota al pie.
  const anioSel = Number(periodo.slice(0, 4));
  const anioCmp = cmp ? Number(cmp.periodo.slice(0, 4)) : null;
  const deltaAnios =
    anioCmp != null && anioCmp !== anioSel && anios.includes(anioSel) && anios.includes(anioCmp);
  const series = anios.map((a) => ({
    nombre: String(a),
    color: colorAnio(a, anioMax),
    valores: Array.from({ length: 12 }, (_, i) => {
      const fila = meses.find((f) => f.anio === a && f.mes === i + 1);
      return fila?.neta ?? null;
    }),
  }));

  const donaPartes = servicios
    .filter((s) => s.periodo === periodo && s.facturado != null)
    .sort((a, b) => (b.facturado ?? 0) - (a.facturado ?? 0))
    .map((s) => ({
      etiqueta: s.servicio,
      valor: s.facturado ?? 0,
      color: COLOR_SERVICIO[s.servicio] ?? COLOR_SERVICIO.OTROS,
      pct: s.pct_periodo,
    }));

  const rutasSel = rutas
    .filter((r) => r.periodo === periodo)
    .sort((a, b) => (b.facturado ?? 0) - (a.facturado ?? 0));

  // La tarifa es la VIGENTE (período ancla), independiente del selector.
  const tarifasVigentes = [...tarifas].sort(
    (a, b) => (a.concepto_num ?? 0) - (b.concepto_num ?? 0),
  );
  const periodoVigente = tarifasVigentes[0]?.periodo ?? null;

  const sub = (delta: string, alterno: string) =>
    cmp ? (
      <span>vs {etiquetaPeriodo(cmp.periodo)}: <b>{delta}</b></span>
    ) : (
      alterno
    );

  return (
    <>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Facturación bruta</div>
          <div className="dash-valor num">{fmtMillones(sel.bruta)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.bruta, cmp?.bruta ?? null), "a tarifa plena, antes de subsidios")}
          </div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Subsidios (26–29)</div>
          <div className="dash-valor num dash-neg">{fmtMillones(sel.subsidios)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.subsidios, cmp?.subsidios ?? null), "estratos 1 a 3")}
          </div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contribuciones (30–33)</div>
          <div className="dash-valor num">{fmtMillones(sel.contribuciones)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.contribuciones, cmp?.contribuciones ?? null), "estratos 5, 6 y no residencial")}
          </div>
        </div>
        <div className="dash-carta dash-kpi dash-kpi-mal">
          <div className="dash-eti">Déficit de subsidios y aportes</div>
          <div className="dash-valor num">{fmtMillones(sel.deficit_abs)}</div>
          <div className="dash-sub2">
            {sub(
              fmtDelta(sel.deficit_abs, cmp?.deficit_abs ?? null),
              `${fmtPct(sel.pct_deficit_bruta)} de la facturación bruta`,
            )}
          </div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Facturación neta</div>
          <div className="dash-valor num">{fmtMillones(sel.neta)}</div>
          <div className="dash-sub2">
            {sub(fmtDelta(sel.neta, cmp?.neta ?? null), "el ingreso real del período")}
          </div>
        </div>
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Facturación neta por mes y año</h3>
          <BarrasMensuales
            series={series}
            formatoY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            formatoTitulo={fmtMillones}
          />
          <TablaPlegable titulo="Datos: neta mensual por año">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Mes</th>
                  {anios.map((a) => <th key={a}>{a}</th>)}
                  {deltaAnios && <th>Δ {anioSel} − {anioCmp}</th>}
                </tr>
              </thead>
              <tbody>
                {MESES_CORTO.map((mes, i) => (
                  <tr key={mes}>
                    <td>{mes}</td>
                    {anios.map((a) => (
                      <td key={a} className="num">
                        {fmtMillones(series[anios.indexOf(a)].valores[i])}
                      </td>
                    ))}
                    {deltaAnios && (
                      <td className="num">
                        {fmtDelta(
                          series[anios.indexOf(anioSel)].valores[i],
                          series[anios.indexOf(anioCmp!)].valores[i],
                        )}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
            {cmp && !deltaAnios && (
              <div className="dash-nota num">
                Δ {etiquetaPeriodo(periodo)} − {etiquetaPeriodo(cmp.periodo)}:{" "}
                {fmtDelta(sel.neta, cmp.neta)}
              </div>
            )}
          </TablaPlegable>
          <div className="dash-nota">
            La neta ya trae aplicado el juego de subsidios y contribuciones.
          </div>
        </div>
        <div className="dash-carta">
          <h3>{etiquetaPeriodo(periodo)} por servicio</h3>
          <Dona partes={donaPartes} formatoTitulo={fmtMillones} />
          <TablaPlegable titulo="Datos: facturado por servicio">
            <table className="dash-tabla num">
              <thead>
                <tr><th>Servicio</th><th>Facturado</th><th>%</th></tr>
              </thead>
              <tbody>
                {donaPartes.map((p) => (
                  <tr key={p.etiqueta}>
                    <td>{p.etiqueta}</td>
                    <td className="num">{fmtMillones(p.valor)}</td>
                    <td className="num">{fmtPct(p.pct)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Cada servicio absorbe sus subsidios y aportes; los "otros ingresos"
            suman a su servicio. Clasificación desde la ruta contable — sin
            categorías vacías.
          </div>
        </div>
      </div>

      <div className="dash-fila-g2">
        <div className="dash-carta">
          <h3>Ruta contable fina — {etiquetaPeriodo(periodo)}</h3>
          <div className="dash-tabla-scroll">
          <table className="dash-tabla num">
            <thead>
              <tr><th>Categoría</th><th>Facturado</th><th>Δ vs anterior</th><th>Δ %</th></tr>
            </thead>
            <tbody>
              {rutasSel.map((r) => (
                <tr key={r.ruta_efectiva}>
                  <td>{r.ruta_efectiva}</td>
                  <td className="num">{fmtMillones(r.facturado)}</td>
                  <td className={`num ${r.variacion != null && r.variacion < 0 ? "dash-neg" : ""}`}>
                    {r.variacion == null
                      ? "—"
                      : `${r.variacion >= 0 ? "+" : "−"}${fmtMillones(Math.abs(r.variacion))}`}
                  </td>
                  <td className={`num ${r.variacion_pct != null && r.variacion_pct < 0 ? "dash-neg" : ""}`}>
                    {r.variacion_pct == null ? "—" : fmtPct(r.variacion_pct)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        </div>

        <div className="dash-carta">
          <h3>
            Tarifa vigente (conceptos 1–4)
            {periodoVigente ? ` — ${etiquetaPeriodo(periodoVigente)}` : ""}
          </h3>
          {tarifasVigentes.length === 0 ? (
            <div className="dash-nota">
              Aún no hay tarifa calculada: se lee del detalle por contrato del
              último mes cargado.
            </div>
          ) : (
            <table className="dash-tabla num">
              <thead>
                <tr><th>Concepto</th><th>Tarifa</th><th>Contratos leídos</th><th>Control</th></tr>
              </thead>
              <tbody>
                {tarifasVigentes.map((t) => (
                  <tr key={t.concepto}>
                    <td>{t.concepto}</td>
                    <td className="num">{fmtTarifa(t.tarifa)}</td>
                    <td className="num">
                      {t.contratos_lectura_directa?.toLocaleString("es-CO") ?? "—"}
                    </td>
                    <td>
                      {t.valores_distintos != null && t.valores_distintos > 1 ? (
                        <span className="dash-semaforo rojo">
                          {t.valores_distintos} valores · fuera de tarifa
                        </span>
                      ) : (
                        <span className="dash-semaforo verde">única</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <div className="dash-nota">
            Tarifa plena única para todos los estratos y usos, leída directo de
            los contratos del último mes cargado
            {periodoVigente && periodo !== periodoVigente
              ? ` (se muestra la vigente aunque el selector esté en ${etiquetaPeriodo(periodo)})`
              : ""}
            ; la progresividad vive en los conceptos 26–33. Si el control marca
            más de un valor, hay cobro fuera de tarifa.
          </div>
        </div>
      </div>
    </>
  );
}
