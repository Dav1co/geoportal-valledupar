import { useEffect, useMemo, useState, type ReactNode } from "react";
import { biCache } from "../cacheBi";
import { comoCambioMedidorDim, type CambioMedidorDim } from "../tipos";
import {
  etiquetaCiclo,
  etiquetaCorta,
  etiquetaPeriodo,
  fmtDecimal,
  fmtEntero,
  numeroCiclo,
  rotuloMostrado,
} from "../formato";
import { BarrasApiladas, BarrasHorizontales, LineasPorcentaje, TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";

// Cambios de medidor entre periodos consecutivos (bi.v_cambio_medidor_dim, sql/38). Una sola carga SIN
// periodo (7 periodos, unos 2,3 MB), guardada en memoria por biCache y filtrada en el navegador. El periodo
// del selector global es el periodo ACTUAL de cada par (se compara con el anterior disponible en la fuente).
// Solo agregados: sin contratos ni seriales; minimo de 5 por celda (el resto en «Otros»).
//
// Un cambio de serial (medidor distinto entre los dos periodos, con medidor en ambos) NO siempre es un cambio fisico: en 202609
// el 97,5 % conserva la continuidad de la lectura (recodificacion). Solo «reposicion_confirmada» (la lectura reinicia a 10 m3 o
// menos) cuenta como reposicion. Antes: «Reposicion» = serial de medidor distinto entre los dos periodos, con medidor en ambos: puede ser un
// recambio fisico o una reasignacion del catalogo. «Sin cambio» (mismo serial) es el control.

const MIN_CELDA = 5;            // celdas con menos de 5 se suman en «Otros»
// En pantalla, la columna contratos_pareados de la base se rotula «Contratos comparables» (mismo dato, nombre interno sin cambio).
const MUESTRA_PEQUENA = 30;     // contratos comparables (contratos_pareados) por debajo de los cuales se marca «muestra pequeña»
const OTROS = "Otros (menos de 5 contratos)";
const COLOR = { tinta: "#0A2540", agua: "#0E7C86", ambar: "#C98A2D", gris: "#9AA7B5" };
const BANDAS = ["0-5", "5-10", "10-15", ">15 (fecha real)", ">15 (1986-01-01)", "Sin fecha"];
const etiquetaBanda = (b: string) =>
  b === "0-5" || b === "5-10" || b === "10-15" ? `${b} años`
  : b === ">15 (fecha real)" ? "Más de 15 años (fecha real)"
  : b === ">15 (1986-01-01)" ? "Más de 15 años (fecha 1986-01-01)"
  : rotuloMostrado(b);
const TEXTO = {
  titulo: "Cambios de medidor",
  definicion:
    "Contratos cuyo medidor cambió de serial entre un período y el anterior disponible, clasificados según la continuidad de la lectura, junto con las instalaciones nuevas y los retiros. Cada período se compara con el anterior; los contratos sin cambio de serial sirven de control.",
  hallazgo:
    "Un cambio de serial no siempre es un cambio físico de medidor. En 202609, de 2.519 cambios de serial, el 97,5 % de los que tienen lectura evaluable conserva la continuidad de la lectura —igual que los contratos sin cambio—: es una recodificación masiva de seriales, y 968 cambios no tienen lectura evaluable. Solo se cuenta como reposición confirmada el cambio de serial cuya lectura reinicia a 10 m³ o menos.",
  dosMeses:
    "En el par de dos meses (202605→202607) la continuidad de la lectura no es evaluable: solo se detecta el reinicio de la lectura a 10 m³ o menos (reposición confirmada) y el resto de los cambios de serial queda como «no concluyente».",
  sinPar601: "no tiene un período anterior en la fuente: la comparación empieza en 202602.",
  sinPar606: "no existe en la fuente de consumo, así que no hay par para ese mes. 202607 se compara con 202605.",
  antiguedad: "La antigüedad del medidor existe desde 202605; antes, todos los medidores aparecen en «Sin fecha». La banda «Más de 15 años (fecha 1986-01-01)» indica fecha desconocida o por defecto.",
  cicloSeparado: "En 202609 el ciclo 5 se separó en el 5 y el 24.",
  comparables:
    "Contratos con medidor registrado en el período y en el período disponible anterior; son los únicos sobre los que se puede comparar el consumo antes y después. Además deben tener lectura real (observación 99 y función CALCCODL) y consumo facturado en ambos meses.",
  notaConsumo:
    "Solo contratos con lectura real en ambos meses. El primer mes tras el cambio suele facturarse por promedio, así que el efecto se confirma en los meses siguientes. Reposición confirmada = serial distinto con la lectura reiniciada a 10 m³ o menos. Son diferencias de un mes, sin error estándar: indicativas.",
};
const pct1 = (v: number | null) => (v == null ? "—" : `${fmtDecimal(v, 1)} %`);
const pct2 = (v: number | null) => (v == null ? "—" : `${fmtDecimal(v, 2)} %`);
const porMil = (v: number | null) => (v == null ? "—" : fmtDecimal(v, 1));
const ratio = (a: number, b: number) => (b > 0 ? a / b : null);

type Acum = { repo: number; cont: number; sinLec: number; otros: number; cambios: number; conMed: number; inst: number; ret: number; sinCambio: number; conMedSin: number };
const vacio = (): Acum => ({ repo: 0, cont: 0, sinLec: 0, otros: 0, cambios: 0, conMed: 0, inst: 0, ret: 0, sinCambio: 0, conMedSin: 0 });
function sumar(a: Acum, x: CambioMedidorDim) {
  a.conMed += x.contratos_con_medidor_ant;
  const c = x.contratos;
  switch (x.tipo_evento) {
    case "reposicion_confirmada": a.repo += c; a.cambios += c; break;
    case "cambio_serial_continuo": a.cont += c; a.cambios += c; break;
    case "reposicion_sin_lectura": a.sinLec += c; a.cambios += c; break;
    case "cambio_serial_retroceso":
    case "cambio_serial_lectura_mayor":
    case "no_concluyente": a.otros += c; a.cambios += c; break;
    case "instalacion_nueva": a.inst += c; break;
    case "retiro": a.ret += c; break;
    case "sin_cambio": a.sinCambio += c; a.conMedSin += x.contratos_con_medidor_ant; break;
  }
}
const tasaMil = (a: Acum) => { const r = ratio(a.repo, a.conMed); return r == null ? null : r * 1000; };

// Agrupa por clave; los grupos con menos de MIN_CELDA cambios de serial se suman en «Otros».
function agrupar(filas: CambioMedidorDim[], clave: (x: CambioMedidorDim) => string, ordenar: (a: [string, Acum], b: [string, Acum]) => number) {
  const m = new Map<string, Acum>();
  for (const x of filas) { const k = clave(x); const a = m.get(k) ?? vacio(); sumar(a, x); m.set(k, a); }
  const grandes: [string, Acum][] = [];
  const otros = vacio();
  let hayOtros = false;
  for (const [k, a] of m) {
    if (a.cambios < MIN_CELDA) {
      hayOtros = true;
      otros.repo += a.repo; otros.cont += a.cont; otros.sinLec += a.sinLec; otros.otros += a.otros; otros.cambios += a.cambios;
      otros.conMed += a.conMed; otros.inst += a.inst; otros.ret += a.ret;
      otros.sinCambio += a.sinCambio; otros.conMedSin += a.conMedSin;
    } else grandes.push([k, a]);
  }
  grandes.sort(ordenar);
  return hayOtros ? [...grandes, [OTROS, otros] as [string, Acum]] : grandes;
}

type Props = { periodo: string; valores: Record<string, string> };

export function CambiosMedidor({ periodo, valores }: Props) {
  const [filas, setFilas] = useState<CambioMedidorDim[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    let vivo = true;
    setFilas(null);
    setError(null);
    biCache("v_cambio_medidor_dim")
      .then((r) => { if (vivo) setFilas((r.datos ?? []).map(comoCambioMedidorDim)); })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
  }, [intento]);

  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  // Filtros de ciclo, uso y estrato (el estrato solo existe con uso Residencial, como en el resto de Pérdidas).
  const filtradas = useMemo(
    () => (filas ?? []).filter(
      (x) =>
        (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo) &&
        (valores.uso === TODOS || x.uso === valores.uso) &&
        (valores.subcategoria === TODOS || x.estrato === valores.subcategoria),
    ),
    [filas, nCiclo, valores.uso, valores.subcategoria],
  );
  const periodos = useMemo(() => [...new Set((filas ?? []).map((x) => x.periodo))].sort(), [filas]);
  const delPeriodo = useMemo(() => filtradas.filter((x) => x.periodo === periodo), [filtradas, periodo]);

  const encabezado = (
    <>
      <h3>{TEXTO.titulo} — {etiquetaPeriodo(periodo)}</h3>
      <div className="dash-nota">{TEXTO.definicion}</div>
    </>
  );
  const tarjeta = (cuerpo: ReactNode) => <div className="dash-fila"><div className="dash-carta">{encabezado}{cuerpo}</div></div>;

  if (error) {
    return tarjeta(
      <div className="dash-estado">
        <p>No se pudo cargar esta sección: {error}</p>
        <button className="dash-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button>
      </div>,
    );
  }
  if (filas == null) return tarjeta(<div className="dash-estado">Cargando…</div>);
  if (filas.length === 0) return tarjeta(<div className="dash-estado">Sin datos de cambios de medidor.</div>);

  // Periodo sin par: el motivo, no una pantalla vacía.
  if (!periodos.includes(periodo)) {
    const motivo =
      periodo === "202601" ? `${etiquetaPeriodo(periodo)} ${TEXTO.sinPar601}`
      : periodo === "202606" ? `${etiquetaPeriodo(periodo)} ${TEXTO.sinPar606}`
      : `No hay cambios de medidor calculados para ${etiquetaPeriodo(periodo)}.`;
    return tarjeta(
      <div className="dash-estado">
        <p>{motivo}</p>
        <p>Hay datos de {etiquetaPeriodo(periodos[0])} a {etiquetaPeriodo(periodos[periodos.length - 1])}.</p>
      </div>,
    );
  }
  if (delPeriodo.length === 0) {
    return tarjeta(<div className="dash-nota">No hay contratos con los filtros elegidos en este período.</div>);
  }

  const meses = delPeriodo[0].meses_intervalo;
  const periodoAnt = delPeriodo[0].periodo_ant;
  const tot = vacio();
  for (const x of delPeriodo) sumar(tot, x);
  const repoPromedio = delPeriodo.filter((x) => x.tipo_evento === "reposicion_confirmada" && x.metodo_act === "promedio").reduce((s, x) => s + x.contratos, 0);
  const tasa = ratio(tot.repo, tot.conMed);

  // ----- serie por periodo (respeta los filtros) -----
  const serie = periodos.map((p) => {
    const a = vacio(); let m = 1;
    for (const x of filtradas) if (x.periodo === p) { sumar(a, x); m = x.meses_intervalo; }
    const t = ratio(a.repo, a.conMed);
    return { p, repo: a.repo, cont: a.cont, sinLec: a.sinLec, otros: a.otros, meses: m, tasaMensual: t == null ? null : (t * 100) / m };
  });

  // ----- por ciclo, uso, estrato, banda y método (periodo actual) -----
  const porCiclo = agrupar(delPeriodo, (x) => { const n = numeroCiclo(x.ciclo); return n == null ? x.ciclo : etiquetaCiclo(n); },
    (a, b) => (tasaMil(b[1]) ?? -1) - (tasaMil(a[1]) ?? -1));
  const porUso = agrupar(delPeriodo, (x) => x.uso, (a, b) => b[1].repo - a[1].repo);
  const resid = delPeriodo.filter((x) => x.uso === "Residencial");
  const porEstrato = agrupar(resid, (x) => x.estrato.replace(/^ESTRATO\s+/i, "Estrato "), (a, b) => a[0].localeCompare(b[0], "es"));
  const porBanda = (() => {
    const m = new Map<string, Acum>();
    for (const x of delPeriodo) if (x.banda_ant !== "Sin medidor") { const a = m.get(x.banda_ant) ?? vacio(); sumar(a, x); m.set(x.banda_ant, a); }
    return BANDAS.filter((b) => m.has(b)).map((b) => [b, m.get(b)!] as [string, Acum]);
  })();
  const metodos = ["lectura", "promedio", "otro"];
  const porMetodo = (tipo: string) => {
    const m: Record<string, number> = { lectura: 0, promedio: 0, otro: 0 };
    for (const x of delPeriodo) if (x.tipo_evento === tipo) m[x.metodo_act] = (m[x.metodo_act] ?? 0) + x.contratos;
    const tot = metodos.reduce((s, k) => s + m[k], 0);
    return { m, tot };
  };
  const metRepo = porMetodo("reposicion_confirmada");
  const metCtl = porMetodo("sin_cambio");

  // ----- consumo antes y después (reposicion frente al control sin cambio) -----
  type Par = { n: number; ant: number; act: number };
  const sumPar = (xs: CambioMedidorDim[], tipo: string): Par => {
    const p = { n: 0, ant: 0, act: 0 };
    for (const x of xs) if (x.tipo_evento === tipo) { p.n += x.contratos_pareados; p.ant += x.m3_ant ?? 0; p.act += x.m3_act ?? 0; }
    return p;
  };
  const filaConsumo = (nombre: string, xs: CambioMedidorDim[]) => {
    const A = sumPar(xs, "reposicion_confirmada"), B = sumPar(xs, "sin_cambio");
    const dif = (p: Par) => (p.n > 0 ? (p.act - p.ant) / p.n : null);
    const dA = dif(A), dB = dif(B);
    return {
      nombre, n: A.n, antes: A.n > 0 ? A.ant / A.n : null, despues: A.n > 0 ? A.act / A.n : null,
      dif: dA, control: dB, neto: dA != null && dB != null ? dA - dB : null,
    };
  };
  const agruparConsumo = (xs: CambioMedidorDim[], clave: (x: CambioMedidorDim) => string, orden: string[] | null) => {
    const g = new Map<string, CambioMedidorDim[]>();
    for (const x of xs) { const k = clave(x); (g.get(k) ?? g.set(k, []).get(k)!).push(x); }
    const grandes: ReturnType<typeof filaConsumo>[] = [];
    const resto: CambioMedidorDim[] = [];
    for (const [k, v] of g) {
      if (sumPar(v, "reposicion_confirmada").n < MIN_CELDA) resto.push(...v); else grandes.push(filaConsumo(k, v));
    }
    grandes.sort((a, b) => (orden ? orden.indexOf(a.nombre) - orden.indexOf(b.nombre) : a.nombre.localeCompare(b.nombre, "es")));
    const o = resto.length ? filaConsumo(OTROS, resto) : null;
    return o && o.n > 0 ? [...grandes, o] : grandes;
  };
  const consumoEstrato = agruparConsumo(resid, (x) => x.estrato.replace(/^ESTRATO\s+/i, "Estrato "), null);
  const consumoBanda = agruparConsumo(delPeriodo.filter((x) => x.banda_ant !== "Sin medidor"), (x) => x.banda_ant, BANDAS);
  const consumoTotal = filaConsumo("Total", delPeriodo);
  const dif2 = (v: number | null) => (v == null ? "—" : `${v > 0 ? "+" : ""}${fmtDecimal(v, 2)}`);
  const m3 = (v: number | null) => (v == null ? "—" : fmtDecimal(v, 1));
  const TablaConsumo = ({ titulo, filas: fs, fmt }: { titulo: string; filas: ReturnType<typeof filaConsumo>[]; fmt?: (k: string) => string }) => (
    <>
      <h3>{titulo}</h3>
      {fs.length === 0 ? <div className="dash-nota">Sin contratos comparables con los filtros elegidos.</div> : (
        <div className="dash-tabla-scroll">
          <table className="dash-tabla num">
            <thead>
              <tr>
                <th>Grupo</th><th>Contratos comparables</th><th>Promedio antes (m³)</th><th>Promedio después (m³)</th>
                <th>Diferencia (m³)</th><th>Diferencia del control (m³)</th><th>Efecto neto (m³)</th>
              </tr>
            </thead>
            <tbody>
              {[...fs, consumoTotal].map((f) => (
                <tr key={f.nombre} className={f.nombre === "Total" ? "dash-fila-fuerte" : undefined}>
                  <td>{fmt ? fmt(f.nombre) : f.nombre}{f.nombre !== "Total" && f.n < MUESTRA_PEQUENA ? " · muestra pequeña" : ""}</td>
                  <td className="num">{fmtEntero(f.n)}</td>
                  <td className="num">{m3(f.antes)}</td>
                  <td className="num">{m3(f.despues)}</td>
                  <td className="num">{dif2(f.dif)}</td>
                  <td className="num">{dif2(f.control)}</td>
                  <td className="num">{dif2(f.neto)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );

  const Kpi = ({ eti, valor, sub }: { eti: string; valor: string; sub?: string }) => (
    <div className="dash-carta dash-kpi">
      <div className="dash-eti">{eti}</div>
      <div className="dash-valor num">{valor}</div>
      {sub ? <div className="dash-sub2">{sub}</div> : null}
    </div>
  );
  const filaTabla = (k: string, a: Acum) => (
    <tr key={k}>
      <td>{k}</td>
      <td className="num">{fmtEntero(a.repo)}</td>
      <td className="num">{fmtEntero(a.cambios)}</td>
      <td className="num">{fmtEntero(a.conMed)}</td>
      <td className="num">{porMil(tasaMil(a))}</td>
      <td className="num">{fmtEntero(a.inst)}</td>
    </tr>
  );
  const tablaGrupo = (primera: string, filasG: [string, Acum][], fmtNombre?: (k: string) => string) => (
    <div className="dash-tabla-scroll">
      <table className="dash-tabla num">
        <thead><tr><th>{primera}</th><th>Reposiciones confirmadas</th><th>Cambios de serial (todos)</th><th>Contratos con medidor anterior</th><th>Tasa confirmada por 1.000</th><th>Instalaciones nuevas</th></tr></thead>
        <tbody>{filasG.map(([k, a]) => filaTabla(fmtNombre ? fmtNombre(k) : k, a))}</tbody>
      </table>
    </div>
  );
  const barras = (filasG: [string, Acum][], fmtNombre?: (k: string) => string) => (
    <BarrasHorizontales
      datos={filasG.map(([k, a]) => ({ etiqueta: fmtNombre ? fmtNombre(k) : k, valor: tasaMil(a) ?? 0 }))}
      formatoValor={(v) => `${fmtDecimal(v, 1)} por 1.000`}
      color={COLOR.tinta}
    />
  );
  const pctDe = (v: number, t: number) => (t > 0 ? (v / t) * 100 : null);

  return (
    <>
      {/* 1) Fichas */}
      <div className="dash-fila"><div className="dash-carta">
        {encabezado}
        <div className="dash-nota">
          Se compara {etiquetaPeriodo(periodo)} con {etiquetaPeriodo(periodoAnt)}
          {meses > 1 ? ` (intervalo de ${meses} meses: 202606 no existe en la fuente).` : "."}
        </div>
        <div className="dash-nota" style={{ borderLeft: "3px solid #C98A2D", paddingLeft: 8 }}><b>Aviso:</b> {TEXTO.hallazgo}{meses > 1 ? ` ${TEXTO.dosMeses}` : ""}</div>
        <div className="dash-kpis">
          <Kpi eti="Reposiciones confirmadas" valor={fmtEntero(tot.repo)} sub="serial distinto y lectura que reinicia a 10 m³ o menos" />
          <Kpi eti="Tasa de reposición confirmada" valor={`${porMil(tasaMil(tot))} por 1.000`}
            sub={`${pct2(tasa == null ? null : tasa * 100)} de ${fmtEntero(tot.conMed)} contratos con medidor anterior${
              meses > 1 ? ` · equivalente mensual: ${porMil(tasa == null ? null : (tasa * 1000) / meses)} por 1.000` : ""}`} />
          <Kpi eti="Cambios de serial con lectura continua (probable recodificación)" valor={fmtEntero(tot.cont)} sub={meses > 1 ? "no evaluable en un par de dos meses" : "lectura anterior = lectura actual previa"} />
          <Kpi eti="Sin lectura evaluable" valor={fmtEntero(tot.sinLec)} sub="cambio de serial con alguna lectura vacía" />
          <Kpi eti={meses > 1 ? "No concluyente" : "Otros cambios de serial"} valor={fmtEntero(tot.otros)} sub={meses > 1 ? "par de dos meses" : "lectura que retrocede sin reiniciar o que sube"} />
          <Kpi eti="Instalaciones nuevas" valor={fmtEntero(tot.inst)} sub="sin medidor antes, con medidor ahora" />
          <Kpi eti="Retiros" valor={fmtEntero(tot.ret)} sub="con medidor antes, sin medidor ahora" />
          <Kpi eti="Reposiciones confirmadas facturadas por promedio" valor={pct1(pctDe(repoPromedio, tot.repo))}
            sub={`${fmtEntero(repoPromedio)} de ${fmtEntero(tot.repo)} en ${etiquetaPeriodo(periodo)}`} />
        </div>
      </div></div>

      {/* 2) Serie por periodo */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Cambios de serial por período y tasa mensual de reposición confirmada</h3>
        <BarrasApiladas
          datos={serie.map((s2) => ({ etiqueta: `${etiquetaCorta(s2.p)}${s2.meses > 1 ? ` (${s2.meses} meses)` : ""}`, valores: [s2.repo, s2.cont, s2.sinLec, s2.otros] }))}
          series={[{ nombre: "Reposiciones confirmadas", color: COLOR.agua }, { nombre: "Lectura continua (probable recodificación)", color: COLOR.gris },
            { nombre: "Sin lectura evaluable", color: COLOR.ambar }, { nombre: "Otros / no concluyente", color: COLOR.tinta }]}
          formatoValor={(v) => `${fmtEntero(v)} contratos`}
          margenIzq={130}
        />
        <LineasPorcentaje
          etiquetas={serie.map((s) => etiquetaCorta(s.p))}
          series={[{ nombre: "Tasa mensual de reposición confirmada", color: COLOR.tinta, valores: serie.map((s) => s.tasaMensual) }]}
          sinTope
          paso={1}
          formatoTick={(t) => `${fmtDecimal(t, 1)} %`}
          formatoValor={(v) => `${fmtDecimal(v, 2)} %`}
        />
        <TablaPlegable titulo="Datos: cambios de serial y tasa por período">
          <table className="dash-tabla num">
            <thead><tr><th>Período</th><th>Meses del intervalo</th><th>Reposiciones confirmadas</th><th>Lectura continua</th><th>Sin lectura</th><th>Otros / no concluyente</th><th>Tasa del intervalo</th><th>Tasa mensual</th></tr></thead>
            <tbody>
              {serie.map((s) => {
                const a = vacio(); for (const x of filtradas) if (x.periodo === s.p) sumar(a, x);
                const t = ratio(a.repo, a.conMed);
                return (
                  <tr key={s.p}>
                    <td>{etiquetaCorta(s.p)}</td><td className="num">{s.meses}</td><td className="num">{fmtEntero(s.repo)}</td><td className="num">{fmtEntero(s.cont)}</td><td className="num">{fmtEntero(s.sinLec)}</td><td className="num">{fmtEntero(s.otros)}</td>
                    <td className="num">{pct2(t == null ? null : t * 100)}</td><td className="num">{pct2(s.tasaMensual)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </TablaPlegable>
        <div className="dash-nota">
          La tasa es la de las reposiciones confirmadas; la mensual es la tasa del intervalo dividida entre sus meses: 202607 se compara con 202605 porque
          202606 no existe en la fuente. Respeta los filtros de ciclo, uso y estrato.
        </div>
      </div></div>

      {/* 3) Por ciclo */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Reposiciones confirmadas por ciclo — {etiquetaPeriodo(periodo)}</h3>
        {barras(porCiclo)}
        {tablaGrupo("Ciclo", porCiclo)}
        <div className="dash-nota">Ordenado por la tasa de reposición confirmada. Los ciclos con menos de {MIN_CELDA} cambios de serial se suman en «{OTROS}». {TEXTO.cicloSeparado}</div>
      </div></div>

      {/* 4) Por uso y por estrato */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Reposiciones confirmadas por uso{valores.uso === "Residencial" ? " y por estrato" : ""}</h3>
        {barras(porUso)}
        {tablaGrupo("Uso", porUso)}
        {valores.uso === "Residencial" ? (
          <>
            <h3>Residencial por estrato</h3>
            {barras(porEstrato)}
            {tablaGrupo("Estrato", porEstrato)}
          </>
        ) : null}
      </div></div>

      {/* 5) Por banda de antigüedad del medidor anterior */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Reposiciones confirmadas por antigüedad del medidor anterior</h3>
        {porBanda.length === 0 ? <div className="dash-nota">Sin datos de antigüedad para este período.</div> : (
          <>
            {barras(porBanda, etiquetaBanda)}
            {tablaGrupo("Antigüedad del medidor anterior", porBanda, etiquetaBanda)}
          </>
        )}
        <div className="dash-nota">{TEXTO.antiguedad}</div>
      </div></div>

      {/* 6) Método de facturación en el período actual */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Cómo se factura el período actual: reposición frente a sin cambio</h3>
        <div className="dash-tabla-scroll">
          <table className="dash-tabla num">
            <thead><tr><th>Método de facturación</th><th>Reposiciones confirmadas</th><th>% de las confirmadas</th><th>Sin cambio (control)</th><th>% del control</th></tr></thead>
            <tbody>
              {[["lectura", "Lectura"], ["promedio", "Promedio"], ["otro", "Otro"]].map(([k, nombre]) => (
                <tr key={k}>
                  <td>{nombre}</td>
                  <td className="num">{fmtEntero(metRepo.m[k])}</td><td className="num">{pct1(pctDe(metRepo.m[k], metRepo.tot))}</td>
                  <td className="num">{fmtEntero(metCtl.m[k])}</td><td className="num">{pct1(pctDe(metCtl.m[k], metCtl.tot))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="dash-nota">
          Lectura = observación 99 y función CALCCODL; promedio = consumo promedio (OBTECOPP, OBTECOPS y [FAMC]); otro = el resto.
          Sirve para ver si los medidores recién cambiados se facturan más por promedio.
        </div>
      </div></div>

      {/* 7) Consumo antes y después */}
      <div className="dash-fila"><div className="dash-carta">
        <h3>Consumo antes y después del cambio — {etiquetaPeriodo(periodo)}</h3>
        {consumoTotal.n < MUESTRA_PEQUENA ? <div className="dash-nota"><b>Muestra pequeña:</b> solo {fmtEntero(consumoTotal.n)} contratos comparables entre las reposiciones confirmadas (con lectura real en ambos meses). Las diferencias son indicativas y se confirmarán con más períodos.</div> : null}
        <TablaConsumo titulo="Por estrato (residencial)" filas={consumoEstrato} />
        <TablaConsumo titulo="Por antigüedad del medidor anterior" filas={consumoBanda} fmt={etiquetaBanda} />
        <div className="dash-nota">
          Solo reposiciones confirmadas frente a sin cambio. Efecto neto = diferencia de las reposiciones confirmadas menos la diferencia del control (contratos sin cambio de serial, con los mismos filtros).
          Los grupos con menos de {MIN_CELDA} contratos comparables se suman en «{OTROS}»; con menos de {MUESTRA_PEQUENA}, «muestra pequeña». {TEXTO.notaConsumo}
        </div>
        <details><summary>ⓘ Cómo se calcula</summary><div className="dash-nota">{TEXTO.comparables} Promedio antes y después = m³ del período anterior y del actual ÷ contratos comparables. Diferencia = promedio después − promedio antes; efecto neto = diferencia de las reposiciones confirmadas − diferencia del control (sin cambio de serial).</div></details>
      </div></div>
    </>
  );
}
