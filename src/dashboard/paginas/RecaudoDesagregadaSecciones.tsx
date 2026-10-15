import { useEffect, useMemo, useState, type ReactNode } from "react";
import { biCache } from "../cacheBi";
import {
  comoNotasCausalDim,
  comoRecaudoEdadDim,
  comoRecaudoEficienciaDim,
  comoRecaudoEntidadDim,
  comoRecaudoRitmoDim,
  type NotasCausalDim,
  type RecaudoEdadDim,
  type RecaudoEficienciaDim,
  type RecaudoEntidadDim,
  type RecaudoRitmoDim,
} from "../tipos";
import {
  etiquetaCiclo,
  etiquetaCorta,
  etiquetaPeriodo,
  fmtEntero,
  fmtMillones,
  fmtPct,
  numeroCiclo,
} from "../formato";
import { BarrasApiladas, BarrasHorizontales, LineasPorcentaje, LineasPorDia, TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";
import { useRama, type Estado } from "../useRama";

// Cinco secciones de Recaudo desagregada, debajo del detalle diario:
//   · % recaudo total (bi.v_recaudo_eficiencia_dim, sql/33)
//   · Ritmo del mes (bi.v_recaudo_ritmo_dim, sql/34)
//   · Recaudo corriente y rezagado (bi.v_recaudo_edad_dim, sql/35)
//   · Notas por causal (bi.v_notas_causal_dim, sql/36)
//   · Recaudo por entidad y agencia (bi.v_recaudo_entidad_dim, sql/37)
// Cada bloque carga por su cuenta (cargando / error con reintento) y tiene sus
// propios filtros; el período es el del selector del tablero. Solo agregados.

// Textos y constantes en un solo lugar.
const META_PCT = 85;                 // meta del % recaudo 0-30 (recaudo de 0 a 30 días ÷ facturado del mes)
const MESES_BANDA = 3;               // meses completos anteriores que forman la banda
const MESES_SERIE = 12;              // meses de la serie de corriente y rezagado
const TEXTO = {
  noAplica: "Este bloque no aplica a este filtro.",
  porGrabacion: "por fecha de grabación",
  sinMesEnCurso: "Sin recaudo grabado en este mes todavía.",
  sinDatos: "Sin datos de esta sección para este período.",
  otros: "Otros",
  otrasCeldas: "Otras celdas (menos de 5 contratos por ciclo y uso)",
} as const;
const esOtros = (v: string) => v === "(Otros)";
const COLOR = { tinta: "#0A2540", agua: "#0E7C86", ambar: "#C98A2D", gris: "#8A99A8" };

const TRAMOS_CORRIENTE = new Set(["0", "30"]);
const fmtMesCorto = etiquetaCorta;

// ---------- utilidades ----------
function sumarMeses(p: string, k: number): string {
  const total = Number(p.slice(0, 4)) * 12 + (Number(p.slice(4)) - 1) + k;
  return `${Math.floor(total / 12)}${String((total % 12) + 1).padStart(2, "0")}`;
}
const pct = (parte: number, total: number): number | null => (total > 0 ? (parte / total) * 100 : null);
const nombreEstrato = (s: string) => s.replace(/^ESTRATO\s+/i, "Estrato ");

// Rama con rango de períodos (desde/hasta), con su propio estado.
function useSerie<T>(
  vista: string,
  desde: string,
  hasta: string,
  convertir: (r: Record<string, unknown>) => T,
): Estado<T> {
  const [datos, setDatos] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    let vivo = true;
    setDatos(null);
    setError(null);
    biCache(vista, { desde, hasta })
      .then((r) => { if (vivo) setDatos((r.datos ?? []).map(convertir)); })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, desde, hasta, intento]);
  return { datos, error, recargar: () => setIntento((i) => i + 1) };
}

// Ficha: título, definición breve y el estado propio del bloque.
function Ficha<T>({
  titulo, definicion, estado, children,
}: { titulo: string; definicion: string; estado: Estado<T>; children: ReactNode }) {
  let cuerpo: ReactNode;
  if (estado.error) {
    cuerpo = (
      <div className="dash-estado">
        <p>No se pudo cargar esta sección: {estado.error}</p>
        <button className="dash-boton" onClick={estado.recargar}>Reintentar</button>
      </div>
    );
  } else if (estado.datos == null) {
    cuerpo = <div className="dash-estado">Cargando…</div>;
  } else if (estado.datos.length === 0) {
    cuerpo = <div className="dash-estado">{TEXTO.sinDatos}</div>;
  } else {
    cuerpo = children;
  }
  return (
    <div className="dash-fila"><div className="dash-carta">
      <h3>{titulo}</h3>
      <div className="dash-nota">{definicion}</div>
      {cuerpo}
    </div></div>
  );
}

function Selector({
  etiqueta, valor, opciones, onCambio,
}: { etiqueta: string; valor: string; opciones: { v: string; t: string }[]; onCambio: (v: string) => void }) {
  return (
    <label>
      {etiqueta}
      <select value={valor} onChange={(e) => onCambio(e.target.value)}>
        <option value={TODOS}>Todos</option>
        {opciones.map((o) => <option key={o.v} value={o.v}>{o.t}</option>)}
      </select>
    </label>
  );
}

const Kpi = ({ eti, valor, sub }: { eti: string; valor: string; sub?: string }) => (
  <div className="dash-carta dash-kpi">
    <div className="dash-eti">{eti}</div>
    <div className="dash-valor num">{valor}</div>
    {sub ? <div className="dash-sub2">{sub}</div> : null}
  </div>
);

// Barra del % recaudo total (sin meta ni semáforo). El grupo de celdas pequeñas va solo en pesos.
function BarraPct({ etiqueta, valor }: { etiqueta: string; valor: number | null }) {
  const tope = 120;
  const ancho = valor == null ? 0 : Math.min(Math.max(valor, 0), tope) / tope * 100;
  return (
    <div className="dash-meta-fila">
      <span>{etiqueta}</span>
      <div className="dash-meta-pista">
        <div className="dash-meta-relleno" style={{ width: `${ancho}%` }} />
      </div>
      <span className="num">{fmtPct(valor)}</span>
    </div>
  );
}

type Props = { periodo: string };

export function RecaudoDesagregadaSecciones({ periodo }: Props) {
  return (
    <>
      <Eficiencia periodo={periodo} />
      <Ritmo periodo={periodo} />
      <CorrienteRezagado periodo={periodo} />
      <NotasCausal periodo={periodo} />
      <Entidades periodo={periodo} />
    </>
  );
}

type GrupoPct = { fact: number; rec: number };
function FilaPct({ etiqueta, otros, g }: { etiqueta: string; otros: boolean; g: GrupoPct }) {
  if (otros) {
    return (
      <div className="dash-meta-fila">
        <span>{TEXTO.otrasCeldas}</span>
        <span className="num">Facturado {fmtMillones(g.fact)} · Recaudo {fmtMillones(g.rec)}</span>
        <span />
      </div>
    );
  }
  return <BarraPct etiqueta={etiqueta} valor={pct(g.rec, g.fact)} />;
}

// ---------------------------------------------------------------------
// 1) % recaudo total
// ---------------------------------------------------------------------
function Eficiencia({ periodo }: Props) {
  const rama = useRama("v_recaudo_eficiencia_dim", periodo, comoRecaudoEficienciaDim);
  const [f, setF] = useState({ ciclo: TODOS, uso: TODOS, estrato: TODOS });
  const filas = rama.datos ?? [];

  const ciclos = useMemo(
    () => [...new Set(filas.map((x) => x.ciclo))]
      .sort((a, b) => (numeroCiclo(a) ?? 999) - (numeroCiclo(b) ?? 999)),
    [filas],
  );
  const usos = useMemo(() => [...new Set(filas.map((x) => x.categoria))].sort(), [filas]);
  const estratos = useMemo(
    () => [...new Set(filas.filter((x) => /^ESTRATO/i.test(x.subcategoria)).map((x) => x.subcategoria))].sort(),
    [filas],
  );
  const verEstrato = f.uso === TODOS || /resid/i.test(f.uso);
  const etiqCiclo = (c: string) => { if (esOtros(c)) return TEXTO.otrasCeldas; const n = numeroCiclo(c); return n == null ? c : etiquetaCiclo(n); };

  const sel = useMemo(
    () => filas.filter(
      (x) =>
        (f.ciclo === TODOS || x.ciclo === f.ciclo) &&
        (f.uso === TODOS || x.categoria === f.uso) &&
        (!verEstrato || f.estrato === TODOS || x.subcategoria === f.estrato),
    ),
    [filas, f, verEstrato],
  );

  const sumar = (xs: RecaudoEficienciaDim[]) => ({
    fact: xs.reduce((s, x) => s + (x.facturado ?? 0), 0),
    rec: xs.reduce((s, x) => s + (x.recaudo_neto ?? 0), 0),
    cf: xs.reduce((s, x) => s + x.contratos_facturados, 0),
    cp: xs.reduce((s, x) => s + x.contratos_pagadores, 0),
    p1: xs.reduce((s, x) => s + x.contratos_pago_1, 0),
    p2: xs.reduce((s, x) => s + x.contratos_pago_2mas, 0),
  });
  const tot = sumar(sel);
  const efTot = pct(tot.rec, tot.fact);

  const agrupar = (clave: (x: RecaudoEficienciaDim) => string | null) => {
    const m = new Map<string, RecaudoEficienciaDim[]>();
    for (const x of sel) { const k = clave(x); if (k == null) continue; (m.get(k) ?? m.set(k, []).get(k)!).push(x); }
    return [...m.entries()].map(([k, xs]) => ({ k, ...sumar(xs) }));
  };
  const porCiclo = agrupar((x) => x.ciclo)
    .sort((a, b) => (numeroCiclo(a.k) ?? 999) - (numeroCiclo(b.k) ?? 999));
  const porUso = agrupar((x) => x.categoria).sort((a, b) => b.fact - a.fact);
  const porEstrato = agrupar((x) => (/^ESTRATO/i.test(x.subcategoria) && /resid/i.test(x.categoria) ? x.subcategoria : null))
    .sort((a, b) => a.k.localeCompare(b.k));

  return (
    <Ficha
      titulo={`% recaudo total — ${etiquetaPeriodo(periodo)}`}
      definicion="% recaudo total = recaudo total del mes (neto de los subsidios aplicados) ÷ facturación total del mes. Cada contrato cuenta en el ciclo, uso y estrato con que se factura; las celdas con menos de 5 contratos se agrupan en «Otras celdas»."
      estado={rama}
    >
      <div className="dash-filtros-bloque">
        <Selector etiqueta="Ciclo" valor={f.ciclo} opciones={ciclos.map((c) => ({ v: c, t: etiqCiclo(c) }))}
          onCambio={(v) => setF({ ...f, ciclo: v })} />
        <Selector etiqueta="Uso" valor={f.uso} opciones={usos.map((u) => ({ v: u, t: esOtros(u) ? TEXTO.otrasCeldas : u }))}
          onCambio={(v) => setF({ ...f, uso: v, estrato: TODOS })} />
        {verEstrato ? (
          <Selector etiqueta="Estrato" valor={f.estrato} opciones={estratos.map((s) => ({ v: s, t: nombreEstrato(s) }))}
            onCambio={(v) => setF({ ...f, estrato: v })} />
        ) : null}
      </div>

      {sel.length === 0 ? (
        <div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>
      ) : (
        <>
          <div className="dash-kpis">
            <Kpi eti="% recaudo total" valor={fmtPct(efTot)} sub="recaudo del mes ÷ facturado del mes" />
            <Kpi eti="Facturado" valor={fmtMillones(tot.fact)} sub={`${fmtEntero(tot.cf)} contratos`} />
            <Kpi eti="Recaudo neto" valor={fmtMillones(tot.rec)} sub={`${fmtEntero(tot.cp)} contratos pagaron`} />
            <Kpi eti="Pagaron una vez" valor={fmtPct(pct(tot.p1, tot.p1 + tot.p2))}
              sub={`${fmtEntero(tot.p2)} contratos con dos o más pagos`} />
          </div>

          <h3>Por ciclo</h3>
          {porCiclo.map((g) => <FilaPct key={g.k} etiqueta={etiqCiclo(g.k)} otros={esOtros(g.k)} g={g} />)}
          <h3>Por uso</h3>
          {porUso.map((g) => <FilaPct key={g.k} etiqueta={g.k} otros={esOtros(g.k)} g={g} />)}
          {porEstrato.length > 0 ? (
            <>
              <h3>Residencial por estrato</h3>
              {porEstrato.map((g) => <FilaPct key={g.k} etiqueta={nombreEstrato(g.k)} otros={esOtros(g.k)} g={g} />)}
            </>
          ) : null}

          <h3>Contratos con un pago y con dos o más pagos, por ciclo</h3>
          <BarrasApiladas
            datos={porCiclo.map((g) => ({ etiqueta: etiqCiclo(g.k), valores: [g.p1, g.p2] }))}
            series={[{ nombre: "Un pago", color: COLOR.tinta }, { nombre: "Dos o más pagos", color: COLOR.ambar }]}
            formatoValor={fmtEntero}
          />
          <TablaPlegable titulo="Datos: % recaudo total por ciclo">
            <table className="dash-tabla num">
              <thead><tr><th>Ciclo</th><th>Facturado</th><th>Recaudo neto</th><th>% recaudo total</th><th>Contratos</th><th>Pagaron</th></tr></thead>
              <tbody>
                {porCiclo.map((g) => (
                  <tr key={g.k}>
                    <td>{etiqCiclo(g.k)}</td>
                    <td className="num">{fmtMillones(g.fact)}</td>
                    <td className="num">{fmtMillones(g.rec)}</td>
                    <td className="num">{esOtros(g.k) ? "—" : fmtPct(pct(g.rec, g.fact))}</td>
                    <td className="num">{fmtEntero(g.cf)}</td>
                    <td className="num">{fmtEntero(g.cp)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El mes de los pagos es el de su fecha de grabación.
          </div>
        </>
      )}
    </Ficha>
  );
}

// ---------------------------------------------------------------------
// 2) Ritmo del mes
// ---------------------------------------------------------------------
function Ritmo({ periodo }: Props) {
  const desde = sumarMeses(periodo, -(MESES_BANDA + 2));
  const rama = useSerie("v_recaudo_ritmo_dim", desde, periodo, comoRecaudoRitmoDim);
  const filas = rama.datos ?? [];

  const calc = useMemo(() => {
    const porMes = new Map<string, RecaudoRitmoDim[]>();
    for (const x of filas) (porMes.get(x.periodo) ?? porMes.set(x.periodo, []).get(x.periodo)!).push(x);
    const arr = (p: string) => {
      const v: (number | null)[] = Array.from({ length: 31 }, () => null);
      for (const x of porMes.get(p) ?? []) if (x.dia >= 1 && x.dia <= 31 && x.pct_acumulado_del_facturado != null) v[x.dia - 1] = x.pct_acumulado_del_facturado * 100;
      return v;
    };
    const actual = porMes.get(periodo) ?? [];
    const previos = [...porMes.keys()].filter((p) => p < periodo && (porMes.get(p) ?? []).every((x) => x.mes_completo)).sort().slice(-MESES_BANDA);
    const curva = arr(periodo);
    const curvasPrev = previos.map(arr);
    const dCorte = actual.length ? (actual[0].ultimo_dia_con_datos ?? 0) : 0;
    const dias = actual.length ? actual.length : 0;
    const banda = (f: (...n: number[]) => number) =>
      Array.from({ length: 31 }, (_, i) => {
        const vs = curvasPrev.map((c) => c[i]).filter((v): v is number => v != null);
        return vs.length ? f(...vs) : null;
      });
    return {
      actual, previos, curva, dCorte, dias,
      min: banda(Math.min), max: banda(Math.max),
      acum: actual.length ? actual.reduce((m, x) => Math.max(m, x.recaudo_acumulado ?? 0), 0) : 0,
      fact: actual.length ? actual[0].facturado_mes : null,
      avance: dCorte > 0 ? curva[dCorte - 1] : null,
    };
  }, [filas, periodo]);

  // Sin filas del mes elegido (p. ej. el mes en curso sin recaudo grabado): se dice, no se inventa.
  const sinMes = rama.datos != null && !rama.error && calc.actual.length === 0;
  const estado: Estado<unknown> = sinMes ? { ...rama, datos: [{}] } : rama;

  return (
    <Ficha
      titulo={`Ritmo del recaudo del mes — ${etiquetaPeriodo(periodo)} (${TEXTO.porGrabacion})`}
      definicion={`Recaudo acumulado día a día como porcentaje de lo facturado en el mes (% recaudo total), frente a la banda de los ${MESES_BANDA} meses cerrados anteriores (mínimo y máximo de cada día). Cada pago cuenta en el día de su fecha de grabación.`}
      estado={estado}
    >
      {sinMes ? (
        <div className="dash-nota">{TEXTO.sinMesEnCurso} {etiquetaPeriodo(periodo)} aún no tiene recaudo con fecha de grabación.</div>
      ) : (
        <>
          <div className="dash-kpis">
            <Kpi eti="Avance a la fecha de corte" valor={fmtPct(calc.avance)} sub={`día ${calc.dCorte} · ${fmtMillones(calc.acum)} de ${fmtMillones(calc.fact)} facturados`} />
          </div>
          <LineasPorDia
            series={[
              { nombre: etiquetaPeriodo(periodo), color: COLOR.tinta, valores: calc.curva },
              { nombre: "Mínimo de meses anteriores", color: COLOR.gris, valores: calc.min },
              { nombre: "Máximo de meses anteriores", color: COLOR.agua, valores: calc.max },
            ]}
            formatoValor={(v) => fmtPct(v)}
            formatoEjeY={(v) => `${v.toLocaleString("es-CO", { maximumFractionDigits: 0 })} %`}
            destacada={etiquetaPeriodo(periodo)}
            diaCorte={calc.dCorte || null}
          />
          <TablaPlegable titulo="Datos: avance acumulado por día">
            <table className="dash-tabla num">
              <thead><tr><th>Día</th><th>{etiquetaPeriodo(periodo)}</th><th>Mínimo anteriores</th><th>Máximo anteriores</th></tr></thead>
              <tbody>
                {calc.curva.map((v, i) => (v == null && calc.min[i] == null ? null : (
                  <tr key={i}>
                    <td>{i + 1}</td>
                    <td className="num">{fmtPct(v)}</td>
                    <td className="num">{fmtPct(calc.min[i])}</td>
                    <td className="num">{fmtPct(calc.max[i])}</td>
                  </tr>
                )))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Meses de la banda: {calc.previos.length ? calc.previos.map(fmtMesCorto).join(", ") : "sin meses cerrados anteriores"}.
          </div>
        </>
      )}
    </Ficha>
  );
}

// ---------------------------------------------------------------------
// 3) Recaudo corriente y rezagado
// ---------------------------------------------------------------------
type Kpi030 = { periodo: string; pct030: number | null };
function CorrienteRezagado({ periodo }: Props) {
  const desde = sumarMeses(periodo, -(MESES_SERIE - 1));
  const rama = useSerie("v_recaudo_edad_dim", desde, periodo, comoRecaudoEdadDim);
  // % recaudo 0-30 (recaudo de 0 a 30 días ÷ facturado de cada mes): lo define v_kpi_mes, igual que Resumen.
  const kpi = useSerie("v_kpi_mes", desde, periodo, (r): Kpi030 => ({
    periodo: String(r.periodo ?? ""),
    pct030: r.pct_recaudo_0_30 == null ? null : Number(r.pct_recaudo_0_30),
  }));
  const [servicio, setServicio] = useState(TODOS);
  const filas: RecaudoEdadDim[] = rama.datos ?? [];
  const servicios = useMemo(() => [...new Set(filas.map((x) => x.servicio))].sort(), [filas]);
  const conMeta = servicio === TODOS;   // la meta aplica al total; por servicio solo se muestra la participación

  const serie = useMemo(() => {
    const m = new Map<string, { cor: number; rez: number }>();
    for (const x of filas) {
      if (servicio !== TODOS && x.servicio !== servicio) continue;
      const a = m.get(x.periodo) ?? { cor: 0, rez: 0 };
      if (TRAMOS_CORRIENTE.has(x.tramo)) a.cor += x.recaudo ?? 0; else a.rez += x.recaudo ?? 0;
      m.set(x.periodo, a);
    }
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [filas, servicio]);

  const actual = serie.find(([p]) => p === periodo)?.[1];
  const pct030 = new Map((kpi.datos ?? []).map((k) => [k.periodo, k.pct030]));
  const p030Actual = pct030.get(periodo) ?? null;
  const verMeta = conMeta && kpi.datos != null && kpi.datos.length > 0;

  return (
    <Ficha
      titulo={`Recaudo corriente y rezagado — últimos ${MESES_SERIE} meses`}
      definicion="Corriente: lo pagado de facturas de 0 y 30 días de edad. Rezagado: lo pagado de deudas de 60 días o más. % recaudo 0-30 = recaudo de 0 a 30 días ÷ facturación del mes. Cada mes es el de la fecha de grabación del pago."
      estado={rama}
    >
      <div className="dash-filtros-bloque">
        <Selector etiqueta="Servicio" valor={servicio} opciones={servicios.map((s) => ({ v: s, t: s }))} onCambio={setServicio} />
      </div>
      {actual ? (
        <div className="dash-kpis">
          {verMeta ? (
            <Kpi eti="% recaudo 0-30" valor={fmtPct(p030Actual)}
              sub={`meta ${META_PCT} % · recaudo de 0 a 30 días ÷ facturado del mes`} />
          ) : null}
          <Kpi eti="Participación del corriente en el recaudo" valor={fmtPct(pct(actual.cor, actual.cor + actual.rez))}
            sub={`corriente ${fmtMillones(actual.cor)} de ${fmtMillones(actual.cor + actual.rez)}`} />
          <Kpi eti="Rezagado" valor={fmtMillones(actual.rez)} sub={`${fmtPct(pct(actual.rez, actual.cor + actual.rez))} del recaudo`} />
        </div>
      ) : (
        <div className="dash-nota">{etiquetaPeriodo(periodo)} no tiene datos en esta serie.</div>
      )}
      {verMeta ? (
        <>
          <h3>% recaudo 0-30 frente a la meta</h3>
          <LineasPorcentaje
            etiquetas={serie.map(([p]) => etiquetaCorta(p))}
            series={[
              { nombre: "% recaudo 0-30", color: COLOR.tinta, valores: serie.map(([p]) => pct030.get(p) ?? null) },
              { nombre: `Meta ${META_PCT} %`, color: COLOR.ambar, valores: serie.map(() => META_PCT) },
            ]}
            sinTope
            paso={5}
          />
        </>
      ) : null}
      <h3>Corriente y rezagado por mes</h3>
      <BarrasApiladas
        datos={serie.map(([p, a]) => ({ etiqueta: etiquetaCorta(p), valores: [a.cor, a.rez] }))}
        series={[{ nombre: "Corriente", color: COLOR.tinta }, { nombre: "Rezagado", color: COLOR.ambar }]}
        formatoValor={fmtMillones}
      />
      <TablaPlegable titulo="Datos: corriente y rezagado por mes">
        <table className="dash-tabla num">
          <thead>
            <tr>
              <th>Mes</th><th>Corriente</th><th>Rezagado</th><th>Participación del corriente</th>
              {verMeta ? <th>% recaudo 0-30</th> : null}
            </tr>
          </thead>
          <tbody>
            {serie.map(([p, a]) => (
              <tr key={p}>
                <td>{etiquetaCorta(p)}</td>
                <td className="num">{fmtMillones(a.cor)}</td>
                <td className="num">{fmtMillones(a.rez)}</td>
                <td className="num">{fmtPct(pct(a.cor, a.cor + a.rez))}</td>
                {verMeta ? <td className="num">{fmtPct(pct030.get(p) ?? null)}</td> : null}
              </tr>
            ))}
          </tbody>
        </table>
      </TablaPlegable>
      <div className="dash-nota">
        {conMeta
          ? `La meta de ${META_PCT} % aplica al % recaudo 0-30 del total; por servicio solo se muestra la participación. `
          : "La meta no se muestra por servicio: aplica al total. "}
        El alcantarillado pluvial está incluido en Alcantarillado.
      </div>
    </Ficha>
  );
}

// ---------------------------------------------------------------------
// 4) Notas por causal
// ---------------------------------------------------------------------
function NotasCausal({ periodo }: Props) {
  const rama = useRama("v_notas_causal_dim", periodo, comoNotasCausalDim);
  const [f, setF] = useState({ ciclo: TODOS, uso: TODOS });
  const filas: NotasCausalDim[] = rama.datos ?? [];
  const ciclos = useMemo(
    () => [...new Set(filas.map((x) => x.ciclo))].sort((a, b) => (numeroCiclo(a) ?? 999) - (numeroCiclo(b) ?? 999)),
    [filas],
  );
  const usos = useMemo(() => [...new Set(filas.map((x) => x.categoria))].sort(), [filas]);
  const etiqCiclo = (c: string) => { const n = numeroCiclo(c); return n == null ? c : etiquetaCiclo(n); };

  const porCausal = useMemo(() => {
    const m = new Map<string, { notas: number; cred: number; deb: number }>();
    for (const x of filas) {
      if ((f.ciclo !== TODOS && x.ciclo !== f.ciclo) || (f.uso !== TODOS && x.categoria !== f.uso)) continue;
      const a = m.get(x.causal) ?? { notas: 0, cred: 0, deb: 0 };
      a.notas += x.notas; a.cred += Math.abs(x.valor_credito ?? 0); a.deb += Math.abs(x.valor_debito ?? 0);
      m.set(x.causal, a);
    }
    return [...m.entries()].map(([k, a]) => ({ k, ...a })).sort((a, b) => b.cred + b.deb - (a.cred + a.deb));
  }, [filas, f]);
  const totNotas = porCausal.reduce((s, x) => s + x.notas, 0);
  const totCred = porCausal.reduce((s, x) => s + x.cred, 0);
  const totDeb = porCausal.reduce((s, x) => s + x.deb, 0);

  return (
    <Ficha
      titulo={`Notas por causal — ${etiquetaPeriodo(periodo)}`}
      definicion="Notas crédito y débito del mes agrupadas por la causal que las originó. Los valores crédito y débito se muestran en valor absoluto. Las causales con menos de 5 notas se agrupan en «Otros»."
      estado={rama}
    >
      <div className="dash-filtros-bloque">
        <Selector etiqueta="Ciclo" valor={f.ciclo} opciones={ciclos.map((c) => ({ v: c, t: etiqCiclo(c) }))} onCambio={(v) => setF({ ...f, ciclo: v })} />
        <Selector etiqueta="Uso" valor={f.uso} opciones={usos.map((u) => ({ v: u, t: u }))} onCambio={(v) => setF({ ...f, uso: v })} />
      </div>
      {porCausal.length === 0 ? (
        <div className="dash-nota">No hay notas con los filtros elegidos en este período.</div>
      ) : (
        <>
          <div className="dash-kpis">
            <Kpi eti="Notas" valor={fmtEntero(totNotas)} />
            <Kpi eti="Valor crédito" valor={fmtMillones(totCred)} />
            <Kpi eti="Valor débito" valor={fmtMillones(totDeb)} />
          </div>
          <BarrasHorizontales
            datos={porCausal.slice(0, 12).map((x) => ({ etiqueta: x.k, valor: x.cred + x.deb }))}
            formatoValor={fmtMillones}
            color={COLOR.tinta}
          />
          <TablaPlegable titulo="Datos: notas por causal">
            <table className="dash-tabla num">
              <thead><tr><th>Causal</th><th>Notas</th><th>Crédito</th><th>Débito</th></tr></thead>
              <tbody>
                {porCausal.map((x) => (
                  <tr key={x.k}>
                    <td>{x.k}</td>
                    <td className="num">{fmtEntero(x.notas)}</td>
                    <td className="num">{fmtMillones(x.cred)}</td>
                    <td className="num">{fmtMillones(x.deb)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </>
      )}
    </Ficha>
  );
}

// ---------------------------------------------------------------------
// 5) Recaudo por entidad y agencia
// ---------------------------------------------------------------------
function Entidades({ periodo }: Props) {
  const rama = useRama("v_recaudo_entidad_dim", periodo, comoRecaudoEntidadDim);
  const [uso, setUso] = useState(TODOS);
  const filas: RecaudoEntidadDim[] = rama.datos ?? [];
  const usos = useMemo(() => [...new Set(filas.map((x) => x.categoria))].sort(), [filas]);
  const sel = useMemo(() => filas.filter((x) => uso === TODOS || x.categoria === uso), [filas, uso]);

  const total = sel.reduce((s, x) => s + (x.valor ?? 0), 0);
  const enLinea = sel.filter((x) => x.en_linea).reduce((s, x) => s + (x.valor ?? 0), 0);
  const porEntidad = useMemo(() => {
    const m = new Map<string, { valor: number; cupones: number }>();
    for (const x of sel) {
      const a = m.get(x.entidad) ?? { valor: 0, cupones: 0 };
      a.valor += x.valor ?? 0; a.cupones += x.cupones;
      m.set(x.entidad, a);
    }
    // «Otros» al final, aunque pese más que alguna entidad.
    return [...m.entries()].map(([k, a]) => ({ k, ...a }))
      .sort((a, b) => (a.k === TEXTO.otros ? 1 : b.k === TEXTO.otros ? -1 : b.valor - a.valor));
  }, [sel]);
  const porAgencia = useMemo(() => {
    const m = new Map<string, { entidad: string; agencia: string; valor: number; cupones: number }>();
    for (const x of sel) {
      const k = `${x.entidad}|${x.agencia}`;
      const a = m.get(k) ?? { entidad: x.entidad, agencia: x.agencia, valor: 0, cupones: 0 };
      a.valor += x.valor ?? 0; a.cupones += x.cupones;
      m.set(k, a);
    }
    return [...m.values()].sort((a, b) => b.valor - a.valor).slice(0, 15);
  }, [sel]);

  return (
    <Ficha
      titulo={`Recaudo por entidad y agencia — ${etiquetaPeriodo(periodo)}`}
      definicion="Valor de los cupones pagados en el mes según la entidad recaudadora y su agencia. Las entidades o agencias con menos de 5 cupones se agrupan en «Otros»."
      estado={rama}
    >
      <div className="dash-filtros-bloque">
        <Selector etiqueta="Uso" valor={uso} opciones={usos.map((u) => ({ v: u, t: u }))} onCambio={setUso} />
      </div>
      {sel.length === 0 ? (
        <div className="dash-nota">{TEXTO.noAplica}</div>
      ) : (
        <>
          <div className="dash-kpis">
            <Kpi eti="Valor de cupones" valor={fmtMillones(total)} sub={`${fmtEntero(sel.reduce((s, x) => s + x.cupones, 0))} cupones`} />
            <Kpi eti="Pagos en línea" valor={fmtPct(pct(enLinea, total))} sub="del valor, por PSE" />
          </div>
          <BarrasHorizontales
            datos={porEntidad.slice(0, 12).map((x) => ({ etiqueta: x.k, valor: x.valor }))}
            formatoValor={fmtMillones}
            color={COLOR.agua}
          />
          <TablaPlegable titulo="Datos: entidades y agencias de mayor valor">
            <table className="dash-tabla num">
              <thead><tr><th>Entidad</th><th>Agencia</th><th>Cupones</th><th>Valor</th><th>% del valor</th></tr></thead>
              <tbody>
                {porAgencia.map((x) => (
                  <tr key={`${x.entidad}|${x.agencia}`}>
                    <td>{x.entidad}</td>
                    <td>{x.agencia}</td>
                    <td className="num">{fmtEntero(x.cupones)}</td>
                    <td className="num">{fmtMillones(x.valor)}</td>
                    <td className="num">{fmtPct(pct(x.valor, total))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
        </>
      )}
    </Ficha>
  );
}
