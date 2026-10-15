import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { comoObservacionDim, type ConsumoCicloDim, type ObservacionDim } from "../tipos";
import {
  ETIQ_CON_MEDIDOR,
  ETIQ_CON_MEDIDOR_CAP,
  ETIQ_SIN_MEDIDOR,
  ETIQ_SIN_MEDIDOR_CAP,
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
import { useRama, type Estado } from "../useRama";
import { UMBRAL_CONSUMO_CERO_PCT, resumenConObservacion } from "../lecturaComun";

// Sección de Facturación detallado: contratos por ciclo, medición y consumo
// cero. Fuente: bi.v_consumo_ciclo_dim (consumo_metodo + facturado de
// ACUEDUCTO de facturacion_sspd). Usa los filtros de la pantalla (ciclo, uso,
// estrato) y su selector de período; no usa "Comparar con".

// Porcentaje de contratos con consumo COBRADO en cero (consumo_cargos = 0) a
// partir del cual se marca la fila de la tabla. Es una CONVENCIÓN DEL TABLERO,
// no una norma: una marca visual, sin texto. En 202609 solo la supera el ciclo
// 21 (21,9 %); el resto de ciclos queda por debajo del 12 %.

// Dos medidas de consumo:
//  · "cobrado (cargos)" = consumo_cargos, el consumo de la factura; coincide con
//    el consumo de sspd. Nunca es nulo.
//  · "medido" = consumo_facturado, el consumo que reporta el sistema.

const COLOR_CON_MEDIDOR = "#0A2540";
const COLOR_SIN_MEDIDOR = "#C98A2D";

type Acum = {
  contratos: number;
  conMedidor: number;
  sinMedidor: number;
  cero: number;          // contratos con consumo cobrado (cargos) = 0
  sinMedido: number;     // cobrados por promedio: consumo medido vacío o 0 con cargos > 0
  m3Cargos: number;
  m3Medido: number;
  facturado: number;
  hayFacturado: boolean;
  enSspd: number;
};
const vacio = (): Acum => ({
  contratos: 0, conMedidor: 0, sinMedidor: 0, cero: 0, sinMedido: 0, m3Cargos: 0, m3Medido: 0,
  facturado: 0, hayFacturado: false, enSspd: 0,
});

function sumar(a: Acum, x: ConsumoCicloDim) {
  const c = x.contratos ?? 0;
  a.contratos += c;
  if (x.con_medidor) a.conMedidor += c; else a.sinMedidor += c;
  a.cero += x.contratos_cargos_cero ?? 0;
  a.sinMedido += x.contratos_cobrado_sin_medido ?? 0;
  a.m3Cargos += x.m3_cargos ?? 0;
  a.m3Medido += x.m3_facturados ?? 0;
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

  // Ficha «Con observación de lectura»: viene de v_observacion_dim (las observaciones no
  // están en la tabla de esta sección). biCache comparte la consulta con la sección Lectura.
  const obs = useRama("v_observacion_dim", periodo, comoObservacionDim);

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

  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  const filtrado = useMemo(() => {
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
              <div className="dash-sub2 num">{ETIQ_CON_MEDIDOR} {fmtEntero(total.conMedidor)}</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">{ETIQ_SIN_MEDIDOR_CAP}</div>
              <div className="dash-valor num">{fmtEntero(total.sinMedidor)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.sinMedidor, total.contratos))} de los contratos</div>
            </div>
            <FichaObservacion estado={obs} nCiclo={nCiclo} valores={valores} />
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Consumo cobrado en cero (cargos)</div>
              <div className="dash-valor num">{fmtEntero(total.cero)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.cero, total.contratos))} de los contratos</div>
            </div>
            <div className="dash-carta dash-kpi">
              <div className="dash-eti">Cobrado por promedio sin consumo medido</div>
              <div className="dash-valor num">{fmtEntero(total.sinMedido)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(total.sinMedido, total.contratos))} de los contratos</div>
            </div>
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Contratos por ciclo, {ETIQ_CON_MEDIDOR} y {ETIQ_SIN_MEDIDOR}</h3>
              <BarrasApiladas
                datos={porCiclo.map(([n, a]) => ({
                  etiqueta: n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)",
                  valores: [a.conMedidor, a.sinMedidor],
                }))}
                series={[
                  { nombre: ETIQ_CON_MEDIDOR_CAP, color: COLOR_CON_MEDIDOR },
                  { nombre: ETIQ_SIN_MEDIDOR_CAP, color: COLOR_SIN_MEDIDOR },
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
                      <th>Ciclo</th><th>Contratos</th><th>{ETIQ_CON_MEDIDOR_CAP}</th><th>{ETIQ_SIN_MEDIDOR_CAP}</th>
                      <th>% {ETIQ_SIN_MEDIDOR}</th><th>Consumo cobrado en cero</th><th>% cero</th>
                      <th>Cobrado sin consumo medido</th><th>m³ cobrados (cargos)</th><th>m³ medidos</th>
                      <th>Facturado acueducto</th><th>Promedio acueducto por contrato</th>
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
                          <td className="num">{fmtEntero(a.sinMedido)}</td>
                          <td className="num">{fmtEntero(a.m3Cargos)}</td>
                          <td className="num">{fmtEntero(a.m3Medido)}</td>
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
                      <td className="num">{fmtEntero(total.sinMedido)}</td>
                      <td className="num">{fmtEntero(total.m3Cargos)}</td>
                      <td className="num">{fmtEntero(total.m3Medido)}</td>
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
              <h3>{ETIQ_CON_MEDIDOR_CAP} frente a {ETIQ_SIN_MEDIDOR}</h3>
              <TablaPlegable titulo={`Datos: ${ETIQ_CON_MEDIDOR} y ${ETIQ_SIN_MEDIDOR}`}>
                <table className="dash-tabla num">
                  <thead>
                    <tr>
                      <th>Grupo</th><th>Contratos</th><th>Consumo cobrado en cero</th><th>% cero</th>
                      <th>Promedio acueducto por contrato</th>
                    </tr>
                  </thead>
                  <tbody>
                    {([[ETIQ_CON_MEDIDOR_CAP, conMed], [ETIQ_SIN_MEDIDOR_CAP, sinMed]] as [string, Acum][]).map(([nombre, a]) => (
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
                Medidor vacío = {ETIQ_SIN_MEDIDOR}. Consumo cobrado = consumo de la
                factura (cargos); consumo medido = el que reporta el sistema.
              </div>
            </div>
          </div>
        </>
      )}
    </>
  );
}

// Ficha «Con observación de lectura»: contratos con una observación distinta de
// «99 USUARIO CON LECTURA» y de «Sin medidor». Respeta ciclo, uso y estrato. Porcentaje
// sobre los contratos con medidor; debajo, cuántos tienen consumo cobrado en cero y la
// causal más frecuente. Estado propio: cargando, error con reintento y "—".
function FichaObservacion({
  estado, nCiclo, valores,
}: { estado: Estado<ObservacionDim>; nCiclo: number | null; valores: Record<string, string> }) {
  const r = useMemo(
    () =>
      resumenConObservacion(
        (estado.datos ?? []).filter(
          (x) =>
            (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
            (valores.uso === TODOS || x.categoria === valores.uso) &&
            (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
        ),
      ),
    [estado.datos, nCiclo, valores.uso, valores.subcategoria],
  );
  const titulo = "Con observación de lectura";
  let cuerpo;
  if (estado.error) {
    cuerpo = (
      <>
        <div className="dash-valor num">—</div>
        <div className="dash-sub2">
          No se pudo cargar.{" "}
          <button className="dash-boton" onClick={estado.recargar}>Reintentar</button>
        </div>
      </>
    );
  } else if (estado.datos == null) {
    cuerpo = <div className="dash-valor num">…</div>;
  } else if (estado.datos.length === 0) {
    cuerpo = (
      <>
        <div className="dash-valor num">—</div>
        <div className="dash-sub2">Sin datos de observaciones para este período</div>
      </>
    );
  } else {
    cuerpo = (
      <>
        <div className="dash-valor num">{fmtEntero(r.contratos)}</div>
        <div className="dash-sub2 num">
          {fmtPct(pct(r.contratos, r.conMedidor))} de los {fmtEntero(r.conMedidor)} contratos {ETIQ_CON_MEDIDOR}
        </div>
        <div className="dash-sub2 num">
          {fmtEntero(r.cero)} con consumo cobrado en cero
          {r.causal ? ` · más frecuente: ${r.causal.texto} (${fmtEntero(r.causal.contratos)})` : ""}
        </div>
      </>
    );
  }
  return (
    <div className="dash-carta dash-kpi">
      <div className="dash-eti">{titulo}</div>
      {cuerpo}
    </div>
  );
}
