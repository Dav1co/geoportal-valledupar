import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useRama, type Estado } from "../useRama";
import { biCache } from "../cacheBi";
import {
  comoLecturaCicloDim,
  comoMedidorAntigDim,
  comoObservacionDim,
  type LecturaCicloDim,
  type MedidorAntigDim,
  type ObservacionDim,
} from "../tipos";
import {
  ETIQ_SIN_MEDIDOR,
  ETIQ_SIN_MEDIDOR_CAP,
  etiquetaCiclo,
  etiquetaPeriodo,
  fmtDecimal,
  fmtEntero,
  fmtPct,
  numeroCiclo,
  rotuloMostrado,
} from "../formato";
import { BarrasApiladas, TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";

// Sección "Lectura" de Facturación detallado: lectura efectiva, tiempos de
// lectura, observaciones de lectura y antigüedad de los medidores. Fuentes:
// bi.v_observacion_dim, bi.v_lectura_ciclo_dim y bi.v_medidor_antig_dim
// (sql/28, 29 y 30; todas de consumo_metodo). Usa los filtros de la pantalla
// (ciclo, uso, estrato) y su selector de período; no usa "Comparar con".
//
// Cada tabla trae SOLO algunas dimensiones, así que cada bloque aplica los
// filtros que su tabla permite y avisa de los que no:
//   · Lectura efectiva y observaciones: ciclo, uso y estrato (v_observacion_dim).
//   · Tiempos de lectura: solo ciclo (v_lectura_ciclo_dim no trae uso ni estrato).
//   · Antigüedad del medidor: uso y estrato (v_medidor_antig_dim no trae ciclo).

// Intervalo regulatorio entre lecturas, en días. Es la ÚNICA definición en el
// front; el SQL (sql/28) clasifica con los mismos límites (28 y 32).
export const LIM_DIAS_MIN = 28;
export const LIM_DIAS_MAX = 32;
// Observaciones con menos de este % de los contratos filtrados se agrupan en
// "Otras" (salvo "Sin medidor" y la observación 99, que siempre se ven).
export const UMBRAL_OTRAS_PCT = 0.3;
export const CODIGO_CON_LECTURA = 99;
export const SIN_MEDIDOR = "Sin medidor";
// Primer período con fecha de instalación en consumo_metodo (antes viene vacía).
export const PRIMER_PERIODO_ANTIGUEDAD = "202605";

const BANDAS_ESCALA = ["0-5", "5-10", "10-15", ">15"];
const BANDAS = [...BANDAS_ESCALA, "Sin fecha", SIN_MEDIDOR];

const COLOR = {
  avance: "#0E7C86",
  igual: "#8FB4CE",
  menor: "#C98A2D",
  sinLectura: "#9AA7B5",
  enRango: "#0E7C86",
  menosMin: "#C98A2D",
  masMax: "#C0392B",
  sinFecha: "#9AA7B5",
  cobrado: "#0A2540",
  cero: "#C98A2D",
};

const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);
export const textoObservacion = (o: string) => o.replace(/^\d+\s+/, "");

type Props = {
  periodo: string;
  valores: Record<string, string>;     // filtros de la pantalla: ciclo, uso, subcategoria
};

type Disponibles = string[] | "error" | null;

export function ContratosLectura({ periodo, valores }: Props) {
  const obs = useRama("v_observacion_dim", periodo, comoObservacionDim);
  const lec = useRama("v_lectura_ciclo_dim", periodo, comoLecturaCicloDim);
  const ant = useRama("v_medidor_antig_dim", periodo, comoMedidorAntigDim);

  // Períodos que tiene la fuente: solo se consulta si algún bloque llega vacío.
  const [disponibles, setDisponibles] = useState<Disponibles>(null);
  const hayVacio = [obs.datos, lec.datos, ant.datos].some((d) => d != null && d.length === 0);
  useEffect(() => {
    if (!hayVacio) return;
    biCache("v_periodos_fuente")
      .then((r) =>
        setDisponibles(
          (r.datos ?? [])
            .filter((x) => String(x.fuente) === "consumo_metodo")
            .map((x) => String(x.periodo))
            .sort(),
        ),
      )
      .catch(() => setDisponibles("error"));
  }, [hayVacio]);

  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  const filtraUso = valores.uso !== TODOS || valores.subcategoria !== TODOS;
  const pasaCiclo = (c: string) => nCiclo == null || numeroCiclo(c) === nCiclo;
  const pasaUso = (cat: string, sub: string) =>
    (valores.uso === TODOS || cat === valores.uso) &&
    (valores.subcategoria === TODOS || sub === valores.subcategoria);

  const obsF = useMemo(
    () => (obs.datos ?? []).filter((x) => pasaCiclo(x.ciclo) && pasaUso(x.categoria, x.subcategoria)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [obs.datos, nCiclo, valores.uso, valores.subcategoria],
  );
  const lecF = useMemo(
    () => (lec.datos ?? []).filter((x) => pasaCiclo(x.ciclo)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [lec.datos, nCiclo],
  );
  const antF = useMemo(
    () => (ant.datos ?? []).filter((x) => pasaUso(x.categoria, x.subcategoria)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ant.datos, valores.uso, valores.subcategoria],
  );

  // Sin datos en las tres ramas: UN solo aviso arriba y los bloques quedan ocultos.
  const cargadas = [obs.datos, lec.datos, ant.datos].every((d) => d != null);
  const todasVacias = cargadas && [obs.datos, lec.datos, ant.datos].every((d) => d!.length === 0);
  if (todasVacias) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>Lectura — {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-estado">
          <p><b>Sin datos de lectura para este período.</b></p>
          {disponibles == null ? (
            <p>Verificando los períodos disponibles…</p>
          ) : disponibles === "error" || disponibles.length === 0 ? null : (
            <p>
              Hay datos de lectura desde <b>{etiquetaPeriodo(disponibles[0])}</b> hasta{" "}
              <b>{etiquetaPeriodo(disponibles[disponibles.length - 1])}</b>.
            </p>
          )}
        </div>
      </div></div>
    );
  }
  const vacio = <div className="dash-estado">Sin datos de esta sección para este período.</div>;

  return (
    <>
      <div className="dash-fila"><div className="dash-carta">
        <h3>Lectura — {etiquetaPeriodo(periodo)}</h3>
      </div></div>

      <Bloque titulo="Lectura efectiva" estado={obs} vacio={vacio}>
        <LecturaEfectiva filas={obsF} />
      </Bloque>

      <Bloque titulo="Tiempos de lectura" estado={lec} vacio={vacio}>
        <TiemposLectura filas={lecF} filtraUso={filtraUso} />
      </Bloque>

      <Bloque titulo="Observaciones de lectura" estado={obs} vacio={vacio}>
        <Observaciones filas={obsF} />
      </Bloque>

      <Bloque titulo="Medidores por antigüedad" estado={ant} vacio={vacio}>
        <Antiguedad filas={antF} periodo={periodo} filtraCiclo={nCiclo != null} />
      </Bloque>
    </>
  );
}

// Cada bloque maneja su propio estado: error con reintento, cargando, vacío.
function Bloque<T>({
  titulo, estado, vacio, children,
}: { titulo: string; estado: Estado<T>; vacio: ReactNode; children: ReactNode }) {
  const encabezado = <h3>{titulo}</h3>;
  if (estado.error) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {encabezado}
        <div className="dash-estado">
          <p>No se pudo cargar esta sección: {estado.error}</p>
          <button className="dash-boton" onClick={estado.recargar}>Reintentar</button>
        </div>
      </div></div>
    );
  }
  if (estado.datos == null) {
    return <div className="dash-fila"><div className="dash-carta">{encabezado}<div className="dash-estado">Cargando…</div></div></div>;
  }
  if (estado.datos.length === 0) {
    return <div className="dash-fila"><div className="dash-carta">{encabezado}{vacio}</div></div>;
  }
  return <>{children}</>;
}

const SinFiltrados = () => (
  <div className="dash-fila"><div className="dash-carta">
    <div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>
  </div></div>
);

// Contratos con una observación de lectura distinta de «99 USUARIO CON LECTURA» y de
// «Sin medidor» (a nivel de las filas recibidas). Lo usa la ficha «Con observación de
// lectura» de la sección de contratos por ciclo y medición.
export function resumenConObservacion(filas: ObservacionDim[]) {
  let contratos = 0, cero = 0, conMedidor = 0;
  const m = new Map<string, { texto: string; contratos: number }>();
  for (const x of filas) {
    if (x.con_medidor) conMedidor += x.contratos;
    if (x.observacion === SIN_MEDIDOR || x.codigo_observacion === CODIGO_CON_LECTURA) continue;
    contratos += x.contratos;
    cero += x.contratos_cero;
    const it = m.get(x.observacion) ?? { texto: textoObservacion(x.observacion), contratos: 0 };
    it.contratos += x.contratos;
    m.set(x.observacion, it);
  }
  const causal = [...m.values()].sort((a, b) => b.contratos - a.contratos)[0] ?? null;
  return { contratos, cero, conMedidor, causal };
}

// ---------------------------------------------------------------------
// a) Lectura efectiva (v_observacion_dim: trae ciclo, uso, estrato y medidor)
// ---------------------------------------------------------------------
function LecturaEfectiva({ filas }: { filas: ObservacionDim[] }) {
  const { total, avance, igual, menor, sinCon, sinSin, porCiclo } = useMemo(() => {
    let total = 0, avance = 0, igual = 0, menor = 0, sinCon = 0, sinSin = 0;
    const m = new Map<number, number[]>();   // ciclo -> [avance, igual, menor, sin lectura]
    for (const x of filas) {
      const c = x.contratos;
      total += c;
      const k = numeroCiclo(x.ciclo) ?? -1;
      if (!m.has(k)) m.set(k, [0, 0, 0, 0]);
      const v = m.get(k)!;
      if (x.resultado_lectura === "avance") { avance += c; v[0] += c; }
      else if (x.resultado_lectura === "igual") { igual += c; v[1] += c; }
      else if (x.resultado_lectura === "menor") { menor += c; v[2] += c; }
      else {
        v[3] += c;
        if (x.con_medidor) sinCon += c; else sinSin += c;
      }
    }
    return { total, avance, igual, menor, sinCon, sinSin, porCiclo: [...m.entries()].sort((a, b) => a[0] - b[0]) };
  }, [filas]);

  if (filas.length === 0) return <SinFiltrados />;
  const tarjeta = (eti: string, v: number, ayuda?: string) => (
    <div className="dash-carta dash-kpi">
      <div className="dash-eti">{eti}</div>
      <div className="dash-valor num">{fmtEntero(v)}</div>
      <div className="dash-sub2 num">{fmtPct(pct(v, total))} de los contratos{ayuda ? ` · ${ayuda}` : ""}</div>
    </div>
  );
  return (
    <>
      <div className="dash-kpis">
        {tarjeta("Con avance de lectura", avance)}
        {tarjeta("Lectura igual a la anterior", igual)}
        {tarjeta("Lectura menor a la anterior", menor)}
        {tarjeta("Sin lectura, con medidor", sinCon)}
        {tarjeta(`Sin lectura, ${ETIQ_SIN_MEDIDOR}`, sinSin)}
      </div>
      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Resultado de lectura por ciclo</h3>
          <BarrasApiladas
            datos={porCiclo.map(([n, v]) => ({
              etiqueta: n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)",
              valores: v,
            }))}
            series={[
              { nombre: "Con avance", color: COLOR.avance },
              { nombre: "Igual a la anterior", color: COLOR.igual },
              { nombre: "Menor a la anterior", color: COLOR.menor },
              { nombre: "Sin lectura", color: COLOR.sinLectura },
            ]}
            formatoValor={(v) => `${fmtEntero(v)} contratos`}
          />
          <TablaPlegable titulo="Datos: lectura efectiva por ciclo">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Ciclo</th><th>Contratos</th><th>Con avance</th><th>Igual</th><th>Menor</th>
                  <th>Sin lectura</th><th>% con avance</th>
                </tr>
              </thead>
              <tbody>
                {porCiclo.map(([n, v]) => {
                  const t = v[0] + v[1] + v[2] + v[3];
                  return (
                    <tr key={n}>
                      <td>{n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)"}</td>
                      <td className="num">{fmtEntero(t)}</td>
                      <td className="num">{fmtEntero(v[0])}</td>
                      <td className="num">{fmtEntero(v[1])}</td>
                      <td className="num">{fmtEntero(v[2])}</td>
                      <td className="num">{fmtEntero(v[3])}</td>
                      <td className="num">{fmtPct(pct(v[0], t))}</td>
                    </tr>
                  );
                })}
                <tr className="dash-fila-fuerte">
                  <td>Total</td>
                  <td className="num">{fmtEntero(total)}</td>
                  <td className="num">{fmtEntero(avance)}</td>
                  <td className="num">{fmtEntero(igual)}</td>
                  <td className="num">{fmtEntero(menor)}</td>
                  <td className="num">{fmtEntero(sinCon + sinSin)}</td>
                  <td className="num">{fmtPct(pct(avance, total))}</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El resultado sale de comparar la lectura actual con la anterior: avance
            (actual mayor), igual, menor (vuelta de medidor o error) o sin lectura
            (falta alguna de las dos; incluye los contratos {ETIQ_SIN_MEDIDOR}).
          </div>
        </div>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------
// b) Tiempos de lectura (v_lectura_ciclo_dim: solo ciclo)
// ---------------------------------------------------------------------
type AcumT = {
  contratos: number; enRango: number; menos: number; mas: number; sinFecha: number;
  conDias: number; diasSuma: number; min: number | null; max: number | null;
  modal: number | null; modalPeso: number;
};
const vacioT = (): AcumT => ({
  contratos: 0, enRango: 0, menos: 0, mas: 0, sinFecha: 0, conDias: 0, diasSuma: 0,
  min: null, max: null, modal: null, modalPeso: 0,
});

function TiemposLectura({ filas, filtraUso }: { filas: LecturaCicloDim[]; filtraUso: boolean }) {
  const { total, porCiclo } = useMemo(() => {
    const total = vacioT();
    const m = new Map<number, AcumT>();
    const sumar = (a: AcumT, x: LecturaCicloDim) => {
      a.contratos += x.contratos;
      if (x.rango_dias === "en_rango") a.enRango += x.contratos;
      else if (x.rango_dias === "menos_min") a.menos += x.contratos;
      else if (x.rango_dias === "mas_max") a.mas += x.contratos;
      else a.sinFecha += x.contratos;
      a.conDias += x.contratos_con_dias;
      a.diasSuma += x.dias_suma ?? 0;
      if (x.dias_min != null) a.min = a.min == null ? x.dias_min : Math.min(a.min, x.dias_min);
      if (x.dias_max != null) a.max = a.max == null ? x.dias_max : Math.max(a.max, x.dias_max);
      // Día modal del ciclo = el de la fila con más contratos con fecha.
      if (x.dia_modal != null && x.contratos_con_dias > a.modalPeso) {
        a.modal = x.dia_modal;
        a.modalPeso = x.contratos_con_dias;
      }
    };
    for (const x of filas) {
      sumar(total, x);
      const k = numeroCiclo(x.ciclo) ?? -1;
      if (!m.has(k)) m.set(k, vacioT());
      sumar(m.get(k)!, x);
    }
    return { total, porCiclo: [...m.entries()].sort((a, b) => a[0] - b[0]) };
  }, [filas]);

  if (filas.length === 0) return <SinFiltrados />;
  const conFecha = (a: AcumT) => a.enRango + a.menos + a.mas;
  const prom = (a: AcumT) => (a.conDias > 0 ? a.diasSuma / a.conDias : null);
  const rango = `${LIM_DIAS_MIN} a ${LIM_DIAS_MAX} días`;
  return (
    <>
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Dentro del intervalo ({rango})</div>
          <div className="dash-valor num">{fmtEntero(total.enRango)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(total.enRango, conFecha(total)))} de los contratos con fecha</div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Menos de {LIM_DIAS_MIN} días</div>
          <div className="dash-valor num">{fmtEntero(total.menos)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(total.menos, conFecha(total)))} de los contratos con fecha</div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Más de {LIM_DIAS_MAX} días</div>
          <div className="dash-valor num">{fmtEntero(total.mas)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(total.mas, conFecha(total)))} de los contratos con fecha</div>
        </div>
        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Sin fecha de lectura</div>
          <div className="dash-valor num">{fmtEntero(total.sinFecha)}</div>
          <div className="dash-sub2 num">{fmtPct(pct(total.sinFecha, total.contratos))} de los contratos</div>
        </div>
      </div>
      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Cumplimiento del intervalo de lectura por ciclo</h3>
          {filtraUso && (
            <div className="dash-nota">
              Los tiempos de lectura se desagregan solo por ciclo: los filtros de uso y
              estrato no aplican a este bloque.
            </div>
          )}
          <BarrasApiladas
            datos={porCiclo.map(([n, a]) => ({
              etiqueta: n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)",
              valores: [a.enRango, a.menos, a.mas, a.sinFecha],
            }))}
            series={[
              { nombre: `Dentro del intervalo (${rango})`, color: COLOR.enRango },
              { nombre: `Menos de ${LIM_DIAS_MIN} días`, color: COLOR.menosMin },
              { nombre: `Más de ${LIM_DIAS_MAX} días`, color: COLOR.masMax },
              { nombre: "Sin fecha", color: COLOR.sinFecha },
            ]}
            formatoValor={(v) => `${fmtEntero(v)} contratos`}
          />
          <TablaPlegable titulo="Datos: tiempos de lectura por ciclo">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Ciclo</th><th>Contratos</th><th>Con fecha de lectura</th><th>Días promedio</th>
                  <th>Mínimo</th><th>Máximo</th><th>Día modal de lectura</th>
                  <th>Dentro del intervalo</th><th>% dentro</th>
                </tr>
              </thead>
              <tbody>
                {porCiclo.map(([n, a]) => (
                  <tr key={n}>
                    <td>{n >= 0 ? etiquetaCiclo(n) : "(sin ciclo)"}</td>
                    <td className="num">{fmtEntero(a.contratos)}</td>
                    <td className="num">{fmtEntero(a.conDias)}</td>
                    <td className="num">{fmtDecimal(prom(a))}</td>
                    <td className="num">{fmtEntero(a.min)}</td>
                    <td className="num">{fmtEntero(a.max)}</td>
                    <td className="num">{fmtEntero(a.modal)}</td>
                    <td className="num">{fmtEntero(a.enRango)}</td>
                    <td className="num">{fmtPct(pct(a.enRango, conFecha(a)))}</td>
                  </tr>
                ))}
                <tr className="dash-fila-fuerte">
                  <td>Total</td>
                  <td className="num">{fmtEntero(total.contratos)}</td>
                  <td className="num">{fmtEntero(total.conDias)}</td>
                  <td className="num">{fmtDecimal(prom(total))}</td>
                  <td className="num">{fmtEntero(total.min)}</td>
                  <td className="num">{fmtEntero(total.max)}</td>
                  <td className="num">—</td>
                  <td className="num">{fmtEntero(total.enRango)}</td>
                  <td className="num">{fmtPct(pct(total.enRango, conFecha(total)))}</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Días entre la lectura anterior y la actual; el intervalo regulatorio es de{" "}
            {rango}. Las fechas de lectura siguen un calendario programado por ciclo; el
            cumplimiento refleja la programación, no necesariamente la fecha real de lectura.
          </div>
        </div>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------
// c) Observaciones de lectura (v_observacion_dim)
// ---------------------------------------------------------------------
type ItemObs = {
  texto: string; codigo: number | null; contratos: number; cero: number;
  detalle?: ItemObs[];   // solo en «Otras»: las observaciones que agrupa
};

function Observaciones({ filas }: { filas: ObservacionDim[] }) {
  const { total, items } = useMemo(() => {
    const m = new Map<string, ItemObs>();
    let total = 0;
    for (const x of filas) {
      total += x.contratos;
      if (!m.has(x.observacion)) {
        m.set(x.observacion, {
          texto: x.observacion === SIN_MEDIDOR ? SIN_MEDIDOR : textoObservacion(x.observacion),
          codigo: x.codigo_observacion, contratos: 0, cero: 0,
        });
      }
      const it = m.get(x.observacion)!;
      it.contratos += x.contratos;
      it.cero += x.contratos_cero;
    }
    // "Sin medidor" y la observación 99 nunca se agrupan; el resto, si pesa menos del umbral.
    const minimo = (total * UMBRAL_OTRAS_PCT) / 100;
    const visibles: ItemObs[] = [];
    const otras: ItemObs = { texto: "Otras", codigo: null, contratos: 0, cero: 0, detalle: [] };
    for (const it of m.values()) {
      const fija = it.texto === SIN_MEDIDOR || it.codigo === CODIGO_CON_LECTURA;
      if (fija || it.contratos >= minimo) visibles.push(it);
      else { otras.contratos += it.contratos; otras.cero += it.cero; otras.detalle!.push(it); }
    }
    otras.detalle!.sort((a, b) => b.contratos - a.contratos || (a.codigo ?? -1) - (b.codigo ?? -1));
    // Mayor a menor; el código solo desempata. "Otras" va siempre al final.
    visibles.sort((a, b) => b.contratos - a.contratos || (a.codigo ?? -1) - (b.codigo ?? -1));
    if (otras.detalle!.length > 0) visibles.push(otras);
    return { total, items: visibles };
  }, [filas]);

  if (filas.length === 0) return <SinFiltrados />;
  const otras = items.find((it) => it.detalle);
  return (
    <div className="dash-fila">
      <div className="dash-carta">
        <h3>Observaciones de lectura</h3>
        <BarrasApiladas
          datos={items.map((it) => ({
            etiqueta: rotuloMostrado(it.texto),
            valores: [it.contratos - it.cero, it.cero],
          }))}
          series={[
            { nombre: "Consumo cobrado mayor que cero", color: COLOR.cobrado },
            { nombre: "Consumo cobrado en cero", color: COLOR.cero },
          ]}
          formatoValor={(v) => `${fmtEntero(v)} contratos`}
          margenIzq={230}
        />
        <TablaPlegable titulo="Datos: observaciones de lectura">
          <table className="dash-tabla num">
            <thead>
              <tr>
                <th>Observación</th><th>Contratos</th><th>% del total</th>
                <th>Consumo cobrado en cero</th><th>% en cero</th>
              </tr>
            </thead>
            <tbody>
              {items.map((it) => (
                <tr key={it.texto}>
                  <td>{rotuloMostrado(it.texto)}</td>
                  <td className="num">{fmtEntero(it.contratos)}</td>
                  <td className="num">{fmtPct(pct(it.contratos, total))}</td>
                  <td className="num">{fmtEntero(it.cero)}</td>
                  <td className="num">{fmtPct(pct(it.cero, it.contratos))}</td>
                </tr>
              ))}
              <tr className="dash-fila-fuerte">
                <td>Total</td>
                <td className="num">{fmtEntero(total)}</td>
                <td className="num">{fmtPct(total > 0 ? 100 : null)}</td>
                <td className="num">{fmtEntero(items.reduce((s, it) => s + it.cero, 0))}</td>
                <td className="num">{fmtPct(pct(items.reduce((s, it) => s + it.cero, 0), total))}</td>
              </tr>
            </tbody>
          </table>
        </TablaPlegable>
        {otras && otras.detalle && (
          <details className="dash-detalle">
            <summary>
              Ver detalle de «Otras» ({otras.detalle.length}{" "}
              {otras.detalle.length === 1 ? "observación" : "observaciones"})
            </summary>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Observación</th><th>Contratos</th><th>% del total</th>
                    <th>Consumo cobrado en cero</th><th>% en cero</th>
                  </tr>
                </thead>
                <tbody>
                  {otras.detalle.map((it) => (
                    <tr key={it.texto}>
                      <td>{it.texto}</td>
                      <td className="num">{fmtEntero(it.contratos)}</td>
                      <td className="num">{fmtPct(pct(it.contratos, total))}</td>
                      <td className="num">{fmtEntero(it.cero)}</td>
                      <td className="num">{fmtPct(pct(it.cero, it.contratos))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
        )}
        <div className="dash-nota">
          Observación registrada por el lector. «{ETIQ_SIN_MEDIDOR_CAP}» agrupa los contratos
          {" "}{ETIQ_SIN_MEDIDOR}; las observaciones que pesan menos de {fmtPct(UMBRAL_OTRAS_PCT)} de los
          contratos se agrupan en «Otras» (con su detalle desplegable). El consumo en cero
          es el consumo cobrado.
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// d) Medidores por antigüedad (v_medidor_antig_dim: uso y estrato, sin ciclo)
// ---------------------------------------------------------------------
function Antiguedad({
  filas, periodo, filtraCiclo,
}: { filas: MedidorAntigDim[]; periodo: string; filtraCiclo: boolean }) {
  const { total, porBanda, conEscala } = useMemo(() => {
    const m = new Map<string, { contratos: number; cero: number }>();
    for (const b of BANDAS) m.set(b, { contratos: 0, cero: 0 });
    let total = 0;
    for (const x of filas) {
      total += x.contratos;
      const a = m.get(x.banda_antiguedad) ?? { contratos: 0, cero: 0 };
      a.contratos += x.contratos;
      a.cero += x.contratos_cero;
      m.set(x.banda_antiguedad, a);
    }
    const porBanda = BANDAS.map((b) => [b, m.get(b)!] as const);
    const conEscala = BANDAS_ESCALA.some((b) => (m.get(b)?.contratos ?? 0) > 0);
    return { total, porBanda, conEscala };
  }, [filas]);

  // Sin fecha de instalación en el período (202601-202604): no se grafica.
  const sinAntiguedad = periodo < PRIMER_PERIODO_ANTIGUEDAD;
  if (sinAntiguedad) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>Medidores por antigüedad</h3>
        <div className="dash-estado">
          La antigüedad del medidor está disponible desde {PRIMER_PERIODO_ANTIGUEDAD}.
        </div>
      </div></div>
    );
  }
  if (filas.length === 0) return <SinFiltrados />;
  return (
    <div className="dash-fila">
      <div className="dash-carta">
        <h3>Medidores por antigüedad</h3>
        {filtraCiclo && (
          <div className="dash-nota">
            La antigüedad no se desagrega por ciclo: se muestran todos los ciclos, con los
            filtros de uso y estrato.
          </div>
        )}
        {!conEscala ? (
          <div className="dash-estado">
            La antigüedad del medidor está disponible desde {PRIMER_PERIODO_ANTIGUEDAD}.
          </div>
        ) : (
          <>
            <BarrasApiladas
              datos={porBanda.map(([b, a]) => ({
                etiqueta: b === "Sin fecha" || b === SIN_MEDIDOR ? rotuloMostrado(b) : `${b} años`,
                valores: [a.contratos - a.cero, a.cero],
              }))}
              series={[
                { nombre: "Consumo cobrado mayor que cero", color: COLOR.cobrado },
                { nombre: "Consumo cobrado en cero", color: COLOR.cero },
              ]}
              formatoValor={(v) => `${fmtEntero(v)} contratos`}
            />
            <TablaPlegable titulo="Datos: medidores por antigüedad">
              <table className="dash-tabla num">
                <thead>
                  <tr>
                    <th>Antigüedad</th><th>Contratos</th><th>% del total</th>
                    <th>Consumo cobrado en cero</th><th>% en cero</th>
                  </tr>
                </thead>
                <tbody>
                  {porBanda.map(([b, a]) => (
                    <tr key={b}>
                      <td>{b === "Sin fecha" || b === SIN_MEDIDOR ? rotuloMostrado(b) : `${b} años`}</td>
                      <td className="num">{fmtEntero(a.contratos)}</td>
                      <td className="num">{fmtPct(pct(a.contratos, total))}</td>
                      <td className="num">{fmtEntero(a.cero)}</td>
                      <td className="num">{fmtPct(pct(a.cero, a.contratos))}</td>
                    </tr>
                  ))}
                  <tr className="dash-fila-fuerte">
                    <td>Total</td>
                    <td className="num">{fmtEntero(total)}</td>
                    <td className="num">{fmtPct(total > 0 ? 100 : null)}</td>
                    <td className="num">{fmtEntero(porBanda.reduce((s, [, a]) => s + a.cero, 0))}</td>
                    <td className="num">{fmtPct(pct(porBanda.reduce((s, [, a]) => s + a.cero, 0), total))}</td>
                  </tr>
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              Antigüedad = años cumplidos entre la fecha de instalación del medidor y el
              primer día del mes evaluado. «Sin fecha» incluye los medidores sin fecha de
              instalación y los de fecha posterior al período.
            </div>
          </>
        )}
      </div>
    </div>
  );
}
