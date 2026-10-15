import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import type { DesviacionDim } from "../tipos";
import { etiquetaCiclo, etiquetaPeriodo, fmtEntero, fmtPct, numeroCiclo } from "../formato";
import { BarrasHorizontales, TablaPlegable } from "../graficas";
import { SinDatos } from "../SinDatos";
import { TODOS } from "../PanelFiltros";
import { UMBRAL_TASA_DESVIACION_PCT } from "../lecturaComun";

// Sección de Facturación detallado: contratos con desviación significativa de
// consumo (Res. CRA 943 de 2021, art. 1.13.1.6). Los contratos con 6 meses o más
// en consumo cero (cero sostenido) se muestran ahora en Pérdidas (CeroSostenido.tsx).
// Fuente: bi.v_desviacion_dim (sql/27), calculada
// sobre la línea 2 de facturacion_contratos.
//
// Usa los filtros de la pantalla (ciclo, uso, estrato) y su selector de período;
// no usa "Comparar con".

// Tasa de desviación (desviados / evaluables) a partir de la cual se marca la
// fila de un ciclo en la tabla. Es una CONVENCIÓN DEL TABLERO, no una norma:
// una marca visual, sin texto. Referencia en 202609: promedio 11,6 %; superan
// el 15 % los ciclos 1, 3, 12 y 20 (el 12 llega a 19 %; en 202608, 21 %).

const COLOR_TASA = "#C0392B";

const CATEGORIAS_EVALUABLES = new Set(["sin_desviacion", "positiva", "negativa"]);

type Acum = {
  total: number;
  sinDesviacion: number;
  positiva: number;
  negativa: number;
  sinHistorial: number;
  sinPromedio: number;
  ge40: { evaluables: number; positiva: number; negativa: number };
  lt40: { evaluables: number; positiva: number; negativa: number };
};
const vacio = (): Acum => ({
  total: 0, sinDesviacion: 0, positiva: 0, negativa: 0, sinHistorial: 0, sinPromedio: 0,
  ge40: { evaluables: 0, positiva: 0, negativa: 0 },
  lt40: { evaluables: 0, positiva: 0, negativa: 0 },
});

function sumar(a: Acum, x: DesviacionDim) {
  const c = x.contratos;
  a.total += c;
  switch (x.tipo_desviacion) {
    case "sin_desviacion": a.sinDesviacion += c; break;
    case "positiva": a.positiva += c; break;
    case "negativa": a.negativa += c; break;
    case "sin_historial": a.sinHistorial += c; break;
    case "sin_promedio": a.sinPromedio += c; break;
  }
  const g = x.grupo_umbral === "ge40" ? a.ge40 : x.grupo_umbral === "lt40" ? a.lt40 : null;
  if (g && CATEGORIAS_EVALUABLES.has(x.tipo_desviacion)) {
    g.evaluables += c;
    if (x.tipo_desviacion === "positiva") g.positiva += c;
    if (x.tipo_desviacion === "negativa") g.negativa += c;
  }
}

const evaluables = (a: Acum) => a.sinDesviacion + a.positiva + a.negativa;
const desviados = (a: Acum) => a.positiva + a.negativa;
const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);

type Props = {
  periodo: string;
  datos: DesviacionDim[] | null;          // null = cargando
  error: string | null;
  onReintentar: () => void;
  valores: Record<string, string>;        // filtros de la pantalla: ciclo, uso, subcategoria
};

// Períodos para los que esta sección SÍ tiene datos: los que tienen en
// facturacion_contratos los 6 períodos anteriores (misma regla del cargador).
function conSeisAnteriores(existentes: string[]): string[] {
  const set = new Set(existentes);
  const mes = (p: string, k: number) => {
    const t = Number(p.slice(0, 4)) * 12 + Number(p.slice(4)) - 1 + k;
    return `${Math.floor(t / 12)}${String((t % 12) + 1).padStart(2, "0")}`;
  };
  return existentes.filter((p) => [1, 2, 3, 4, 5, 6].every((k) => set.has(mes(p, -k))));
}

export function ContratosDesviacion({ periodo, datos, error, onReintentar, valores }: Props) {
  const [disponibles, setDisponibles] = useState<string[] | "error" | null>(null);
  const vacioPeriodo = datos != null && datos.length === 0;

  useEffect(() => {
    if (!vacioPeriodo) return;
    biCache("v_periodos_fuente")
      .then((r) =>
        setDisponibles(
          conSeisAnteriores(
            (r.datos ?? [])
              .filter((x) => String(x.fuente) === "facturacion_contratos")
              .map((x) => String(x.periodo)),
          ),
        ),
      )
      .catch(() => setDisponibles("error"));
  }, [vacioPeriodo]);

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
    const total = vacio();
    const ciclos = new Map<number, Acum>();
    const cats = new Map<string, Acum>();
    const estratos = new Map<string, Acum>();
    const en = <K,>(m: Map<K, Acum>, k: K) => {
      if (!m.has(k)) m.set(k, vacio());
      return m.get(k)!;
    };
    for (const x of filtrado) {
      sumar(total, x);
      sumar(en(ciclos, numeroCiclo(x.ciclo) ?? -1), x);
      sumar(en(cats, x.categoria), x);
      if (x.categoria === "Residencial") sumar(en(estratos, x.subcategoria), x);
    }
    return {
      total,
      porCiclo: [...ciclos.entries()].sort((a, b) => a[0] - b[0]),
      porCategoria: [...cats.entries()].sort((a, b) => b[1].total - a[1].total),
      porEstrato: [...estratos.entries()].sort((a, b) => a[0].localeCompare(b[0], "es")),
    };
  }, [filtrado]);

  const titulo = <h3>Contratos con desviación significativa — {etiquetaPeriodo(periodo)}</h3>;

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
        {disponibles == null ? (
          <div className="dash-estado">Verificando los períodos disponibles…</div>
        ) : disponibles === "error" ? (
          <div className="dash-estado">
            <p><b>No hay datos de desviación de consumo para {etiquetaPeriodo(periodo)}.</b></p>
            <p>Se calcula solo para períodos con los 6 anteriores en facturación por contrato.</p>
          </div>
        ) : (
          <>
            <SinDatos
              periodo={periodo}
              fuente="desviación de consumo (requiere los 6 períodos anteriores de facturación por contrato)"
              disponibles={disponibles}
            />
          </>
        )}
      </div></div>
    );
  }

  const eva = evaluables(total);
  const des = desviados(total);

  return (
    <>
      <div className="dash-fila"><div className="dash-carta">{titulo}</div></div>

      {filtrado.length === 0 ? (
        <div className="dash-fila"><div className="dash-carta">
          <div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>
        </div></div>
      ) : (
        <>
          <div className="dash-kpis">
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Con desviación significativa</div>
              <div className="dash-valor num">{fmtEntero(des)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(des, eva))} de {fmtEntero(eva)} contratos evaluables</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Desviación positiva (consumo por encima)</div>
              <div className="dash-valor num">{fmtEntero(total.positiva)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.positiva, eva))} de los evaluables</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Desviación negativa (consumo por debajo)</div>
              <div className="dash-valor num">{fmtEntero(total.negativa)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.negativa, eva))} de los evaluables</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Sin historial suficiente</div>
              <div className="dash-valor num">{fmtEntero(total.sinHistorial)}</div>
              <div className="dash-sub2">no existían en los 6 períodos anteriores; no se evalúan</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Sin promedio de referencia</div>
              <div className="dash-valor num">{fmtEntero(total.sinPromedio)}</div>
              <div className="dash-sub2">promedio de los 6 anteriores en cero y consumo en el período; no se evalúan</div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Tasa de desviación por ciclo</h3>
              <BarrasHorizontales
                datos={porCiclo.map(([n, a]) => ({
                  etiqueta: n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)",
                  valor: pct(desviados(a), evaluables(a)) ?? 0,
                }))}
                formatoValor={(v) => fmtPct(v)}
                color={COLOR_TASA}
              />
              <TablaPlegable titulo="Datos: desviación por ciclo">
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Ciclo</th><th>Contratos</th><th>Evaluables</th><th>Positiva</th><th>Negativa</th>
                      <th>Con desviación</th><th>Tasa</th><th>Sin historial</th><th>Sin promedio</th>
                    </tr>
                  </thead>
                  <tbody>
                    {porCiclo.map(([n, a]) => {
                      const t = pct(desviados(a), evaluables(a));
                      return (
                        <tr key={n} className={t != null && t > UMBRAL_TASA_DESVIACION_PCT ? "dash-fila-marca" : ""}>
                          <td>{n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)"}</td>
                          <td className="num">{fmtEntero(a.total)}</td>
                          <td className="num">{fmtEntero(evaluables(a))}</td>
                          <td className="num">{fmtEntero(a.positiva)}</td>
                          <td className="num">{fmtEntero(a.negativa)}</td>
                          <td className="num">{fmtEntero(desviados(a))}</td>
                          <td className="num">{fmtPct(t)}</td>
                          <td className="num">{fmtEntero(a.sinHistorial)}</td>
                          <td className="num">{fmtEntero(a.sinPromedio)}</td>
                        </tr>
                      );
                    })}
                    <tr className="dash-fila-fuerte">
                      <td>Total</td>
                      <td className="num">{fmtEntero(total.total)}</td>
                      <td className="num">{fmtEntero(eva)}</td>
                      <td className="num">{fmtEntero(total.positiva)}</td>
                      <td className="num">{fmtEntero(total.negativa)}</td>
                      <td className="num">{fmtEntero(des)}</td>
                      <td className="num">{fmtPct(pct(des, eva))}</td>
                      <td className="num">{fmtEntero(total.sinHistorial)}</td>
                      <td className="num">{fmtEntero(total.sinPromedio)}</td>
                    </tr>
                  </tbody>
                </table>
              </TablaPlegable>
              <div className="dash-nota">
                Tasa = contratos con desviación (positiva + negativa) sobre los
                evaluables (sin desviación + positiva + negativa). Se marca el
                ciclo cuya tasa supera {fmtPct(UMBRAL_TASA_DESVIACION_PCT)}: es una
                convención del tablero, no una norma. El ciclo 24 aparece como
                CICLO 05 porque así llega de la fuente.
              </div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Por categoría y por estrato residencial</h3>
              <TablaPlegable titulo="Datos: desviación por categoría y estrato">
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Grupo</th><th>Evaluables</th><th>Positiva</th><th>Negativa</th>
                      <th>Con desviación</th><th>Tasa</th>
                    </tr>
                  </thead>
                  <tbody>
                    {porCategoria.map(([nombre, a]) => (
                      <tr key={`c-${nombre}`}>
                        <td>{nombre}</td>
                        <td className="num">{fmtEntero(evaluables(a))}</td>
                        <td className="num">{fmtEntero(a.positiva)}</td>
                        <td className="num">{fmtEntero(a.negativa)}</td>
                        <td className="num">{fmtEntero(desviados(a))}</td>
                        <td className="num">{fmtPct(pct(desviados(a), evaluables(a)))}</td>
                      </tr>
                    ))}
                    {porEstrato.map(([nombre, a]) => (
                      <tr key={`e-${nombre}`}>
                        <td>Residencial · {nombre}</td>
                        <td className="num">{fmtEntero(evaluables(a))}</td>
                        <td className="num">{fmtEntero(a.positiva)}</td>
                        <td className="num">{fmtEntero(a.negativa)}</td>
                        <td className="num">{fmtEntero(desviados(a))}</td>
                        <td className="num">{fmtPct(pct(desviados(a), evaluables(a)))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TablaPlegable>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Por grupo de consumo promedio</h3>
              <TablaPlegable titulo="Datos: desviación por grupo de promedio">
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Promedio de los 6 períodos anteriores</th><th>Umbral</th><th>Evaluables</th>
                      <th>Positiva</th><th>% positiva</th><th>Negativa</th><th>% negativa</th>
                    </tr>
                  </thead>
                  <tbody>
                    {([
                      ["De 40 m³ o más", "35 %", total.ge40],
                      ["Menos de 40 m³", "65 %", total.lt40],
                    ] as [string, string, Acum["ge40"]][]).map(([nombre, umbral, g]) => (
                      <tr key={nombre}>
                        <td>{nombre}</td>
                        <td className="num">{umbral}</td>
                        <td className="num">{fmtEntero(g.evaluables)}</td>
                        <td className="num">{fmtEntero(g.positiva)}</td>
                        <td className="num">{fmtPct(pct(g.positiva, g.evaluables))}</td>
                        <td className="num">{fmtEntero(g.negativa)}</td>
                        <td className="num">{fmtPct(pct(g.negativa, g.evaluables))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TablaPlegable>
              <div className="dash-nota">
                Los contratos con promedio en cero no tienen grupo de umbral y
                no entran en esta tabla.
              </div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <div className="dash-nota">
                Resolución CRA 943 de 2021, art. 1.13.1.6: hay desviación
                significativa cuando el consumo del período se aparta del
                promedio de los seis períodos anteriores del mismo contrato en
                más de 35 % si ese promedio es de 40 m³ o más, o en más de 65 %
                si es menor de 40 m³. Consumo = m³ del concepto de consumo de
                acueducto; un contrato sin ese concepto en el período cuenta
                como consumo cero. Los períodos sin los seis anteriores en la
                fuente no se calculan.
              </div>
            </div>
          </div>
        </>
      )}
    </>
  );
}
