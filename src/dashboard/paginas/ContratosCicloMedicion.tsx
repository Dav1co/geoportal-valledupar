import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import type { ConsumoCicloDim } from "../tipos";
import {
  etiquetaCiclo,
  etiquetaPeriodo,
  fmtEntero,
  fmtPct,
  fmtPesosCompleto,
  numeroCiclo,
} from "../formato";
import { BarrasApiladas, TablaPlegable } from "../graficas";
import { SinDatos } from "../SinDatos";
import { TODOS } from "../PanelFiltros";

// Sección de Facturación detallado: contratos por ciclo, medición y consumo
// cero. Fuente: bi.v_consumo_ciclo_dim (consumo_metodo + facturado de
// ACUEDUCTO de facturacion_sspd). Usa los filtros de la pantalla (ciclo, uso,
// estrato) y su selector de período; no usa "Comparar con".

// Porcentaje de contratos con consumo cero a partir del cual se marca la fila
// de la tabla. Es una marca visual, sin texto: en 202609 solo la supera el
// ciclo 21 (18,8 %); el resto de ciclos queda por debajo del 3 %.
export const UMBRAL_CONSUMO_CERO_PCT = 10;

const COLOR_CON_MEDIDOR = "#0A2540";
const COLOR_SIN_MEDIDOR = "#C98A2D";

type Acum = {
  contratos: number;
  conMedidor: number;
  sinMedidor: number;
  cero: number;
  nulo: number;
  m3: number;
  facturado: number;
  hayFacturado: boolean;
  enSspd: number;
};
const vacio = (): Acum => ({
  contratos: 0, conMedidor: 0, sinMedidor: 0, cero: 0, nulo: 0, m3: 0,
  facturado: 0, hayFacturado: false, enSspd: 0,
});

function sumar(a: Acum, x: ConsumoCicloDim) {
  const c = x.contratos ?? 0;
  a.contratos += c;
  if (x.con_medidor) a.conMedidor += c; else a.sinMedidor += c;
  a.cero += x.contratos_consumo_cero ?? 0;
  a.nulo += x.contratos_consumo_nulo ?? 0;
  a.m3 += x.m3_facturados ?? 0;
  if (x.facturado_acueducto != null) {
    a.facturado += x.facturado_acueducto;
    a.hayFacturado = true;
  }
  a.enSspd += x.contratos_en_sspd ?? 0;
}

const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);
// Facturado acueducto: sin dato (NULL o sin contratos en sspd) se muestra "—", nunca 0.
const facturado = (a: Acum) => (a.hayFacturado && a.enSspd > 0 ? fmtPesosCompleto(a.facturado, 0) : "—");
const promedio = (a: Acum) =>
  a.hayFacturado && a.enSspd > 0 ? fmtPesosCompleto(a.facturado / a.enSspd, 0) : "—";

type Props = {
  periodo: string;
  datos: ConsumoCicloDim[] | null;     // null = cargando
  error: string | null;
  onReintentar: () => void;
  valores: Record<string, string>;     // filtros de la pantalla: ciclo, uso, subcategoria
};

export function ContratosCicloMedicion({ periodo, datos, error, onReintentar, valores }: Props) {
  // Períodos que tiene la fuente: null = aún sin consultar, "error" = no se pudo.
  const [disponibles, setDisponibles] = useState<string[] | "error" | null>(null);
  const vacioPeriodo = datos != null && datos.length === 0;

  // Solo si el período no tiene filas: qué períodos sí tiene esta fuente.
  useEffect(() => {
    if (!vacioPeriodo) return;
    biCache("v_periodos_fuente")
      .then((r) =>
        setDisponibles(
          (r.datos ?? [])
            .filter((x) => String(x.fuente) === "consumo_metodo")
            .map((x) => String(x.periodo)),
        ),
      )
      .catch(() => setDisponibles("error"));
  }, [vacioPeriodo]);

  const filtrado = useMemo(() => {
    const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
    return (datos ?? []).filter(
      (x) =>
        (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
        (valores.uso === TODOS || x.categoria === valores.uso) &&
        (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
    );
  }, [datos, valores]);

  const { total, porCiclo, conMed, sinMed } = useMemo(() => {
    const total = vacio(), conMed = vacio(), sinMed = vacio();
    const m = new Map<number, Acum>();
    for (const x of filtrado) {
      sumar(total, x);
      sumar(x.con_medidor ? conMed : sinMed, x);
      const k = numeroCiclo(x.ciclo) ?? -1;
      if (!m.has(k)) m.set(k, vacio());
      sumar(m.get(k)!, x);
    }
    const porCiclo = [...m.entries()].sort((a, b) => a[0] - b[0]);
    return { total, porCiclo, conMed, sinMed };
  }, [filtrado]);

  const titulo = <h3>Contratos por ciclo, medición y consumo cero — {etiquetaPeriodo(periodo)}</h3>;

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
            <p><b>No hay datos de consumo por contrato (consumo_metodo) para {etiquetaPeriodo(periodo)}.</b></p>
          </div>
        ) : (
          <SinDatos periodo={periodo} fuente="consumo por contrato (consumo_metodo)" disponibles={disponibles} />
        )}
      </div></div>
    );
  }

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
              <div className="dash-eti">Contratos</div>
              <div className="dash-valor num">{fmtEntero(total.contratos)}</div>
              <div className="dash-sub2 num">con medidor {fmtEntero(total.conMedidor)}</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Sin medidor</div>
              <div className="dash-valor num">{fmtEntero(total.sinMedidor)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.sinMedidor, total.contratos))} de los contratos</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Con consumo cero</div>
              <div className="dash-valor num">{fmtEntero(total.cero)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.cero, total.contratos))} de los contratos</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Sin dato de consumo</div>
              <div className="dash-valor num">{fmtEntero(total.nulo)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.nulo, total.contratos))} de los contratos</div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Contratos por ciclo, con y sin medidor</h3>
              <BarrasApiladas
                datos={porCiclo.map(([n, a]) => ({
                  etiqueta: n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)",
                  valores: [a.conMedidor, a.sinMedidor],
                }))}
                series={[
                  { nombre: "Con medidor", color: COLOR_CON_MEDIDOR },
                  { nombre: "Sin medidor", color: COLOR_SIN_MEDIDOR },
                ]}
                formatoValor={(v) => `${fmtEntero(v)} contratos`}
              />
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Detalle por ciclo</h3>
              <div className="dash-tabla-scroll">
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Ciclo</th><th>Contratos</th><th>Con medidor</th><th>Sin medidor</th>
                      <th>% sin medidor</th><th>Consumo cero</th><th>% cero</th><th>Sin dato</th>
                      <th>m³</th><th>Facturado acueducto</th><th>Promedio acueducto por contrato</th>
                    </tr>
                  </thead>
                  <tbody>
                    {porCiclo.map(([n, a]) => {
                      const pCero = pct(a.cero, a.contratos);
                      return (
                        <tr key={n} className={pCero != null && pCero > UMBRAL_CONSUMO_CERO_PCT ? "dash-fila-marca" : ""}>
                          <td>{n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)"}</td>
                          <td className="num">{fmtEntero(a.contratos)}</td>
                          <td className="num">{fmtEntero(a.conMedidor)}</td>
                          <td className="num">{fmtEntero(a.sinMedidor)}</td>
                          <td className="num">{fmtPct(pct(a.sinMedidor, a.contratos))}</td>
                          <td className="num">{fmtEntero(a.cero)}</td>
                          <td className="num">{fmtPct(pCero)}</td>
                          <td className="num">{fmtEntero(a.nulo)}</td>
                          <td className="num">{fmtEntero(a.m3)}</td>
                          <td className="num">{facturado(a)}</td>
                          <td className="num">{promedio(a)}</td>
                        </tr>
                      );
                    })}
                    <tr className="dash-fila-fuerte">
                      <td>Total</td>
                      <td className="num">{fmtEntero(total.contratos)}</td>
                      <td className="num">{fmtEntero(total.conMedidor)}</td>
                      <td className="num">{fmtEntero(total.sinMedidor)}</td>
                      <td className="num">{fmtPct(pct(total.sinMedidor, total.contratos))}</td>
                      <td className="num">{fmtEntero(total.cero)}</td>
                      <td className="num">{fmtPct(pct(total.cero, total.contratos))}</td>
                      <td className="num">{fmtEntero(total.nulo)}</td>
                      <td className="num">{fmtEntero(total.m3)}</td>
                      <td className="num">{facturado(total)}</td>
                      <td className="num">{promedio(total)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Con medidor frente a sin medidor</h3>
              <TablaPlegable titulo="Datos: con y sin medidor">
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Grupo</th><th>Contratos</th><th>Consumo cero</th><th>% cero</th>
                      <th>Promedio acueducto por contrato</th>
                    </tr>
                  </thead>
                  <tbody>
                    {([["Con medidor", conMed], ["Sin medidor", sinMed]] as [string, Acum][]).map(([nombre, a]) => (
                      <tr key={nombre}>
                        <td>{nombre}</td>
                        <td className="num">{fmtEntero(a.contratos)}</td>
                        <td className="num">{fmtEntero(a.cero)}</td>
                        <td className="num">{fmtPct(pct(a.cero, a.contratos))}</td>
                        <td className="num">{promedio(a)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TablaPlegable>
              <div className="dash-nota">
                Ciclo tal como viene en consumo; facturado = acueducto (sspd).
                Medidor vacío = sin medidor.
              </div>
            </div>
          </div>
        </>
      )}
    </>
  );
}
