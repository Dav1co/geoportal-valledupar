import { useMemo, type ReactNode } from "react";
import {
  comoConsumoBasicoDim,
  comoConsumoRangoDim,
  type ConsumoBasicoDim,
  type ConsumoRangoDim,
} from "../tipos";
import {
  ETIQ_CON_MEDIDOR,
  ETIQ_SIN_MEDIDOR,
  etiquetaCiclo,
  etiquetaPeriodo,
  fmtEntero,
  fmtPct,
  fmtPesosCompleto,
  numeroCiclo,
} from "../formato";
import { BarrasApiladas, BarrasPareja, TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";
import { useRama, type Estado } from "../useRama";
import { useVacioConsumo } from "../useVacioConsumo";

// Dos secciones de consumo:
//   · Rangos de consumo (bi.v_consumo_rango_dim, sql/31): ciclo, uso y estrato aplican. Se muestra en Pérdidas.
//   · Consumo básico (bi.v_consumo_basico_dim, sql/32): solo Residencial, estratos 1 a 3. Sigue en
//     Facturación desagregada.
// Usan los filtros de su pantalla y su selector de período; no usan "Comparar con".

// Límite del consumo básico, en m³ por contrato y mes. DEBE coincidir con
// c_basico de bi.recalcular_consumo_basico_dim (sql/32_consumo_basico_dim.sql).
export const BASICO_M3 = 16;

// Rangos de consumo, en el orden de la pantalla (etiquetas guardadas en la tabla).
const RANGOS = ["0", "1-5", "6-10", "11-15", "16-20", "21-30", "31-40", "41-60", "61-100", ">100"];
// Rangos que suman "más de 40 m³" y "más de 100 m³".
const RANGOS_MAS_40 = new Set(["41-60", "61-100", ">100"]);
const RANGOS_MAS_100 = new Set([">100"]);

const COLOR = {
  basico: "#0A2540",
  exceso: "#C98A2D",
  contratos: "#0A2540",
  volumen: "#C98A2D",
};

const ESTRATOS_BASICO = ["ESTRATO 1", "ESTRATO 2", "ESTRATO 3"];
const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);
const nombreEstrato = (s: string) => s.replace(/^ESTRATO\s+/i, "Estrato ");

type Props = {
  periodo: string;
  valores: Record<string, string>;     // filtros de la pantalla: ciclo, uso, subcategoria
};

// Contratos y volumen por rango de consumo (se muestra en Pérdidas).
export function ConsumoRangosSeccion({ periodo, valores }: Props) {
  const rango = useRama("v_consumo_rango_dim", periodo, comoConsumoRangoDim);
  const vacio = useVacioConsumo(rango.datos != null && rango.datos.length === 0);
  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  return (
    <Bloque titulo="Rangos de consumo" estado={rango} vacio={vacio}>
      <RangosConsumo
        periodo={periodo}
        filas={(rango.datos ?? []).filter(
          (x) =>
            (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
            (valores.uso === TODOS || x.categoria === valores.uso) &&
            (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
        )}
      />
    </Bloque>
  );
}

// Consumo básico (se queda en Facturación desagregada).
export function ConsumoBasicoSeccion({ periodo, valores }: Props) {
  const basico = useRama("v_consumo_basico_dim", periodo, comoConsumoBasicoDim);
  const vacio = useVacioConsumo(basico.datos != null && basico.datos.length === 0);
  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  return (
    <Bloque titulo={`Consumo básico (hasta ${BASICO_M3} m³)`} estado={basico} vacio={vacio}>
      <ConsumoBasico periodo={periodo} nCiclo={nCiclo} valores={valores} filas={basico.datos ?? []} />
    </Bloque>
  );
}

// Cada bloque maneja su propio estado: cargando, error con reintento.
function Bloque<T>({
  titulo, estado, vacio, children,
}: { titulo: string; estado: Estado<T>; vacio: ReactNode; children: ReactNode }) {
  if (estado.error) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo}</h3>
        <div className="dash-estado">
          <p>No se pudo cargar esta sección: {estado.error}</p>
          <button className="dash-boton" onClick={estado.recargar}>Reintentar</button>
        </div>
      </div></div>
    );
  }
  if (estado.datos == null) {
    return <div className="dash-fila"><div className="dash-carta"><h3>{titulo}</h3><div className="dash-estado">Cargando…</div></div></div>;
  }
  if (estado.datos.length === 0) {
    return <div className="dash-fila"><div className="dash-carta"><h3>{titulo}</h3>{vacio}</div></div>;
  }
  return <>{children}</>;
}

const SinFiltrados = ({ titulo }: { titulo: string }) => (
  <div className="dash-fila"><div className="dash-carta">
    <h3>{titulo}</h3>
    <div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>
  </div></div>
);

// ---------------------------------------------------------------------
// a) Rangos de consumo
// ---------------------------------------------------------------------
type AcumR = { contratos: number; m3: number; fact: number; hayFact: boolean; conMed: number; sinMed: number };
const vacioR = (): AcumR => ({ contratos: 0, m3: 0, fact: 0, hayFact: false, conMed: 0, sinMed: 0 });

function RangosConsumo({ periodo, filas }: { periodo: string; filas: ConsumoRangoDim[] }) {
  const { total, porRango, sinDato } = useMemo(() => {
    const total = vacioR();
    const m = new Map<string, AcumR>(RANGOS.map((r) => [r, vacioR()]));
    const sinDato = vacioR();
    for (const x of filas) {
      const a = m.get(x.rango_consumo) ?? (x.rango_consumo === "Sin dato" ? sinDato : null);
      if (!a) continue;
      for (const t of [a, total]) {
        t.contratos += x.contratos;
        t.m3 += x.m3_cargos ?? 0;
        if (x.facturado_acueducto != null) { t.fact += x.facturado_acueducto; t.hayFact = true; }
        if (x.con_medidor) t.conMed += x.contratos; else t.sinMed += x.contratos;
      }
    }
    return { total, porRango: RANGOS.map((r) => [r, m.get(r)!] as const), sinDato };
  }, [filas]);

  const titulo = "Rangos de consumo";
  if (filas.length === 0) return <SinFiltrados titulo={titulo} />;

  const suma = (conjunto: Set<string>) =>
    porRango.reduce(
      (s, [r, a]) => (conjunto.has(r) ? { c: s.c + a.contratos, m3: s.m3 + a.m3 } : s),
      { c: 0, m3: 0 },
    );
  const cero = porRango[0][1];
  const mas40 = suma(RANGOS_MAS_40);
  const mas100 = suma(RANGOS_MAS_100);
  const factTxt = (a: AcumR) => (a.hayFact ? fmtPesosCompleto(a.fact, 0) : "—");

  return (
    <>
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo} — {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-nota">Rangos de consumo cobrado por contrato y mes.</div>
      </div></div>

      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos con consumo cero</div>
          <div className="dash-valor num">{fmtEntero(cero.contratos)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(cero.contratos, total.contratos))} de los contratos</div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos con más de 40 m³</div>
          <div className="dash-valor num">{fmtEntero(mas40.c)}</div>
          <div className="dash-sub2 num">
            {fmtPct(pct(mas40.c, total.contratos))} de los contratos ·{" "}
            <b>{fmtPct(pct(mas40.m3, total.m3))}</b> del volumen total
          </div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contratos con más de 100 m³</div>
          <div className="dash-valor num">{fmtEntero(mas100.c)}</div>
          <div className="dash-sub2 num">
            {fmtPct(pct(mas100.c, total.contratos))} de los contratos ·{" "}
            <b>{fmtPct(pct(mas100.m3, total.m3))}</b> del volumen total
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Contratos y volumen por rango</h3>
          <BarrasPareja
            datos={porRango.map(([r, a]) => ({
              etiqueta: `${r} m³`,
              a: pct(a.contratos, total.contratos) ?? 0,
              b: pct(a.m3, total.m3) ?? 0,
              textoA: `${fmtEntero(a.contratos)} · ${fmtPct(pct(a.contratos, total.contratos))}`,
              textoB: `${fmtPct(pct(a.m3, total.m3))} de los m³`,
            }))}
            nombreA="Contratos"
            nombreB="Volumen (m³)"
            colorA={COLOR.contratos}
            colorB={COLOR.volumen}
          />
          <TablaPlegable titulo="Datos: rangos de consumo">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Rango (m³)</th><th>Contratos</th><th>% contratos</th><th>m³</th><th>% m³</th>
                  <th>Facturado acueducto</th>
                  <th>Contratos {ETIQ_CON_MEDIDOR}</th><th>Contratos {ETIQ_SIN_MEDIDOR}</th>
                </tr>
              </thead>
              <tbody>
                {porRango.map(([r, a]) => (
                  <tr key={r}>
                    <td>{r}</td>
                    <td className="num">{fmtEntero(a.contratos)}</td>
                    <td className="num">{fmtPct(pct(a.contratos, total.contratos))}</td>
                    <td className="num">{fmtEntero(a.m3)}</td>
                    <td className="num">{fmtPct(pct(a.m3, total.m3))}</td>
                    <td className="num">{factTxt(a)}</td>
                    <td className="num">{fmtEntero(a.conMed)}</td>
                    <td className="num">{fmtEntero(a.sinMed)}</td>
                  </tr>
                ))}
                {sinDato.contratos > 0 && (
                  <tr>
                    <td>Sin dato</td>
                    <td className="num">{fmtEntero(sinDato.contratos)}</td>
                    <td className="num">{fmtPct(pct(sinDato.contratos, total.contratos))}</td>
                    <td className="num">—</td><td className="num">—</td><td className="num">—</td>
                    <td className="num">{fmtEntero(sinDato.conMed)}</td>
                    <td className="num">{fmtEntero(sinDato.sinMed)}</td>
                  </tr>
                )}
                <tr className="dash-fila-fuerte">
                  <td>Total</td>
                  <td className="num">{fmtEntero(total.contratos)}</td>
                  <td className="num">{fmtPct(total.contratos > 0 ? 100 : null)}</td>
                  <td className="num">{fmtEntero(total.m3)}</td>
                  <td className="num">{fmtPct(total.m3 > 0 ? 100 : null)}</td>
                  <td className="num">{factTxt(total)}</td>
                  <td className="num">{fmtEntero(total.conMed)}</td>
                  <td className="num">{fmtEntero(total.sinMed)}</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Límite superior inclusivo: el rango 6-10 va de más de 5 hasta 10 m³. El consumo es
            el cobrado en la factura de acueducto; el facturado, el de acueducto del mismo período
            (solo hay desde 202606).
          </div>
        </div>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------
// b) Consumo básico (residencial, estratos 1 a 3)
// ---------------------------------------------------------------------
type AcumB = {
  contratos: number; sobre: number; m3Total: number; m3Basico: number; m3Exceso: number;
  conMed: number; sobreCon: number;
};
const vacioB = (): AcumB => ({
  contratos: 0, sobre: 0, m3Total: 0, m3Basico: 0, m3Exceso: 0, conMed: 0, sobreCon: 0,
});
function sumarB(a: AcumB, x: ConsumoBasicoDim) {
  a.contratos += x.contratos;
  a.sobre += x.contratos_sobre_basico;
  a.m3Total += x.m3_total ?? 0;
  a.m3Basico += x.m3_basico ?? 0;
  a.m3Exceso += x.m3_exceso ?? 0;
  if (x.con_medidor) { a.conMed += x.contratos; a.sobreCon += x.contratos_sobre_basico; }
}

function ConsumoBasico({
  periodo, nCiclo, valores, filas,
}: { periodo: string; nCiclo: number | null; valores: Record<string, string>; filas: ConsumoBasicoDim[] }) {
  const titulo = `Consumo básico (hasta ${BASICO_M3} m³)`;
  // La tabla solo trae Residencial, estratos 1 a 3: otro uso o estrato no tiene filas.
  const aplica =
    (valores.uso === TODOS || valores.uso === "Residencial") &&
    (valores.subcategoria === TODOS || ESTRATOS_BASICO.includes(valores.subcategoria));

  const filtradas = useMemo(
    () =>
      filas.filter(
        (x) =>
          (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
          (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
      ),
    [filas, nCiclo, valores.subcategoria],
  );

  const { total, porEstrato, porCiclo } = useMemo(() => {
    const total = vacioB();
    const e = new Map<string, AcumB>(ESTRATOS_BASICO.map((k) => [k, vacioB()]));
    const c = new Map<number, AcumB>();
    for (const x of filtradas) {
      sumarB(total, x);
      if (e.has(x.subcategoria)) sumarB(e.get(x.subcategoria)!, x);
      const k = numeroCiclo(x.ciclo) ?? -1;
      if (!c.has(k)) c.set(k, vacioB());
      sumarB(c.get(k)!, x);
    }
    return {
      total,
      porEstrato: ESTRATOS_BASICO.map((k) => [k, e.get(k)!] as const).filter(([, a]) => a.contratos > 0),
      porCiclo: [...c.entries()].sort((a, b) => a[0] - b[0]),
    };
  }, [filtradas]);

  if (!aplica) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo}</h3>
        <div className="dash-estado">Esta sección aplica solo al uso Residencial, estratos 1 a 3.</div>
      </div></div>
    );
  }
  if (filtradas.length === 0) return <SinFiltrados titulo={titulo} />;

  const ficha = (nombre: string, a: AcumB) => (
    <div className="dash-carta dash-kpi" key={nombre}>
      <div className="dash-eti">{nombre}</div>
      <div className="dash-valor num">{fmtPct(pct(a.sobreCon, a.conMed))}</div>
      <div className="dash-sub2 num">
        de los {fmtEntero(a.conMed)} contratos {ETIQ_CON_MEDIDOR} pasa de {BASICO_M3} m³
      </div>
      <div className="dash-sub2 num">
        Total de {fmtEntero(a.contratos)} contratos: {fmtPct(pct(a.sobre, a.contratos))} pasa
      </div>
      <div className="dash-sub2 num">
        {fmtEntero(a.m3Exceso)} m³ por encima de {BASICO_M3} ({fmtPct(pct(a.m3Exceso, a.m3Total))} de sus m³)
      </div>
    </div>
  );

  return (
    <>
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo} — {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-nota">
          Consumo básico: hasta {BASICO_M3} m³ por contrato y mes. Los contratos {ETIQ_SIN_MEDIDOR} se
          facturan por promedio.
        </div>
      </div></div>

      <div className="dash-kpis">
        {porEstrato.map(([k, a]) => ficha(nombreEstrato(k), a))}
        {ficha("Total", total)}
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>m³ dentro del básico y por encima de {BASICO_M3} m³, por estrato</h3>
          <BarrasApiladas
            datos={porEstrato.map(([k, a]) => ({
              etiqueta: nombreEstrato(k),
              valores: [a.m3Basico, a.m3Exceso],
            }))}
            series={[
              { nombre: `Dentro del básico (hasta ${BASICO_M3} m³)`, color: COLOR.basico },
              { nombre: `Por encima de ${BASICO_M3} m³`, color: COLOR.exceso },
            ]}
            formatoValor={(v) => `${fmtEntero(v)} m³`}
          />
          <TablaPlegable titulo="Datos: consumo básico por ciclo">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Ciclo</th><th>Contratos</th><th>Pasan de {BASICO_M3} m³</th><th>% que pasa</th>
                  <th>Contratos {ETIQ_CON_MEDIDOR}</th><th>% que pasa ({ETIQ_CON_MEDIDOR})</th>
                </tr>
              </thead>
              <tbody>
                {porCiclo.map(([n, a]) => (
                  <tr key={n}>
                    <td>{n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)"}</td>
                    <td className="num">{fmtEntero(a.contratos)}</td>
                    <td className="num">{fmtEntero(a.sobre)}</td>
                    <td className="num">{fmtPct(pct(a.sobre, a.contratos))}</td>
                    <td className="num">{fmtEntero(a.conMed)}</td>
                    <td className="num">{fmtPct(pct(a.sobreCon, a.conMed))}</td>
                  </tr>
                ))}
                <tr className="dash-fila-fuerte">
                  <td>Total</td>
                  <td className="num">{fmtEntero(total.contratos)}</td>
                  <td className="num">{fmtEntero(total.sobre)}</td>
                  <td className="num">{fmtPct(pct(total.sobre, total.contratos))}</td>
                  <td className="num">{fmtEntero(total.conMed)}</td>
                  <td className="num">{fmtPct(pct(total.sobreCon, total.conMed))}</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Aplica al uso Residencial, estratos 1 a 3. La cifra principal de cada ficha es el % sobre los
            contratos {ETIQ_CON_MEDIDOR}; el total incluye los {ETIQ_SIN_MEDIDOR}, que casi nunca pasan
            de {BASICO_M3} m³ porque se facturan por promedio. El filtro de ciclo y el de estrato aplican.
          </div>
        </div>
      </div>
    </>
  );
}
