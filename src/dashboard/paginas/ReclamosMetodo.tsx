import { useMemo, useState, type ReactNode } from "react";
import {
  comoReclamoMetodoBandaDim,
  comoReclamoMetodoCicloDim,
  type ReclamoMetodoBandaDim,
  type ReclamoMetodoCicloDim,
} from "../tipos";
import { etiquetaCiclo, etiquetaPeriodo, fmtDecimal, fmtEntero, numeroCiclo } from "../formato";
import { BarrasApiladas, BarrasHorizontales, TablaPlegable } from "../graficas";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import {
  AVISO_ASOCIACION, BANDAS, FUENTE_A, FUENTE_B, GRUPOS, METODOS, MUESTRA_PEQUENA, MIN_CONTRATOS_MES,
  OTROS_USOS, SIN_BASE, T_LECTURA, T_MODIF, TRAYECTORIAS,
  agrupar, estratoMostrado, etiquetaMetodo, fechaCalculo, porMil, porTrayectoria, sobreLecturaEstable,
  solicitudesCP, solicitudesTotal, sumaVacia, tasaCP, tasaTotal, trayectoriaDe, useVistaBi,
  type Estado, type Suma,
} from "../reclamosMetodo";

// «Reclamos según el método de facturación» (tablas bi.v_reclamo_metodo_banda_dim y _ciclo_dim, sql/40 y 41).
// Solo agregados: contratos-mes y solicitudes distintas por contrato y período. Asociación, no causalidad.

const ACUMULADO = "acumulado";
const OTROS_CICLOS = "Otros (menos de 5 contratos)";
const COLOR = "#0A2540";
const etiquetaBanda = (b: string) =>
  ["0-3", "3-5", "5-10", "10-15"].includes(b) ? `${b} años`
  : b === ">15 (fecha real)" ? "Más de 15 años (fecha real)"
  : b === ">15 (1986-01-01)" ? "Más de 15 años (fecha 1986-01-01)"
  : b;
const t2 = (v: number | null) => (v == null ? "—" : fmtDecimal(v, 2));
const pct1 = (v: number | null) => (v == null ? "—" : `${fmtDecimal(v, 1)} %`);
const nombreTasa = "por 1.000 contratos-mes";
const NOTA_MODIF = "La modificación directa suele ser consecuencia de un reclamo ya atendido, no su causa.";

const PARTES = [
  { id: "resumen", titulo: "Resumen" }, { id: "metodo", titulo: "Tasa por método" }, { id: "trayectorias", titulo: "Trayectorias" },
  { id: "matriz", titulo: "Método anterior × actual" }, { id: "antiguedad", titulo: "Por antigüedad del medidor" },
  { id: "estrato", titulo: "Por estrato y uso" }, { id: "ciclo", titulo: "Por ciclo" },
  { id: "noconsumo", titulo: "Reclamos que no son de consumo" }, { id: "metodologia", titulo: "Metodología y fuentes" },
];

const Kpi = ({ eti, valor, sub }: { eti: string; valor: string; sub?: string }) => (
  <div className="dash-carta dash-kpi">
    <div className="dash-eti">{eti}</div>
    <div className="dash-valor num">{valor}</div>
    {sub ? <div className="dash-sub2">{sub}</div> : null}
  </div>
);
const Carta = ({ titulo, children }: { titulo: string; children: ReactNode }) => (
  <div className="dash-fila"><div className="dash-carta"><h3>{titulo}</h3>{children}</div></div>
);
const Sub = ({ titulo, children }: { titulo: string; children: ReactNode }) => (
  <div className="dash-subparte"><h3>{titulo}</h3>{children}</div>
);
function Parte({ id, titulo, abierta, onCambio, children }: { id: string; titulo: string; abierta: boolean; onCambio: (abierta: boolean) => void; children: ReactNode }) {
  return (
    <div id={`rmet-${id}`} className="dash-fila"><div className="dash-carta">
      <details open={abierta} onToggle={(e) => onCambio((e.currentTarget as HTMLDetailsElement).open)}>
        <summary><b>{titulo}</b></summary>
        {abierta ? children : null}
      </details>
    </div></div>
  );
}
function Pie({ fuente, periodo, calculado, formula }: { fuente: string; periodo: string; calculado: string; formula: string }) {
  return (
    <>
      <div className="dash-nota">Fuente: {fuente}. Período: {periodo}. Calculado: {calculado}.</div>
      <details><summary>ⓘ Cómo se calcula</summary><div className="dash-nota">{formula}</div></details>
    </>
  );
}
function Reintento({ titulo, e }: { titulo: string; e: Estado<unknown> }) {
  if (e.error) {
    return (
      <Carta titulo={titulo}>
        <div className="dash-estado">
          <p>No se pudo cargar esta sección: {e.error}</p>
          <button className="dash-boton" onClick={e.recargar}>Reintentar</button>
        </div>
      </Carta>
    );
  }
  return <Carta titulo={titulo}><div className="dash-estado">Cargando…</div></Carta>;
}
// Celda de tasa: «—» con menos de 5 contratos-mes; «muestra pequeña» con menos de 5.000.
function Tasa({ sol, contratos }: { sol: number; contratos: number }) {
  const t = porMil(sol, contratos);
  if (t == null) return <>—</>;
  return <>{t2(t)}{contratos < MUESTRA_PEQUENA ? <small> · muestra pequeña</small> : null}</>;
}
const valorBarra = (sol: number, contratos: number) => porMil(sol, contratos) ?? 0;
const solicitudesGrupo = (s: Suma, id: string) =>
  id === "consumo" ? s.consumo : id === "promedio" ? s.promedio : id === "medidor" ? s.medidor
  : id === "desocupado" ? s.desocupado : id === "cartera" ? s.cartera : id === "admin" ? s.admin : s.resto;

export function ReclamosMetodo({ periodo }: { periodo: string }) {
  const A = useVistaBi("v_reclamo_metodo_banda_dim", comoReclamoMetodoBandaDim);
  const B = useVistaBi("v_reclamo_metodo_ciclo_dim", comoReclamoMetodoCicloDim);
  const [sel, setSel] = useState<string>(ACUMULADO);
  const [valores, setValores] = useState<Record<string, string>>({ uso: TODOS, estrato: TODOS, ciclo: TODOS });
  const [abiertas, setAbiertas] = useState<Record<string, boolean>>({ resumen: true, trayectorias: true, metodologia: true });
  const [estratoBanda, setEstratoBanda] = useState(false);
  function cambiar(id: string, abierta: boolean) { setAbiertas((a) => (a[id] === abierta ? a : { ...a, [id]: abierta })); }
  function abrir(id: string) {
    cambiar(id, true);
    window.setTimeout(() => document.getElementById(`rmet-${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
  }

  const filasA: ReclamoMetodoBandaDim[] = A.datos ?? [];
  const filasB: ReclamoMetodoCicloDim[] = B.datos ?? [];
  const periodos = useMemo(() => [...new Set(filasA.map((x) => x.periodo))].sort(), [filasA]);

  const filtros: DefFiltro[] = useMemo(() => {
    const unicos = (xs: string[]) => [...new Set(xs)].sort((a, b) => a.localeCompare(b, "es"));
    return [
      { id: "uso", etiqueta: "Uso", opciones: unicos(filasA.map((x) => x.uso).filter((u) => u !== SIN_BASE)) },
      {
        id: "estrato", etiqueta: "Estrato",
        opciones: unicos(filasA.map((x) => estratoMostrado(x.estrato, x.uso)).filter((e) => e !== SIN_BASE)),
        ayuda: "En los usos no residenciales el estrato trae diámetros: se agrupan en «Otros usos»",
      },
      {
        id: "ciclo", etiqueta: "Ciclo de facturación",
        opciones: [...new Set(filasB.map((x) => numeroCiclo(x.ciclo)).filter((n): n is number => n != null))].sort((a, b) => a - b).map(etiquetaCiclo),
        ayuda: "Solo afecta a la parte «Por ciclo»",
      },
    ];
  }, [filasA, filasB]);

  const sinFiltroAB = valores.uso === TODOS && valores.estrato === TODOS;
  const nCiclo = valores.ciclo === TODOS ? null : numeroCiclo(valores.ciclo);
  const enPeriodo = (p: string) => sel === ACUMULADO || p === sel;

  // A con período, uso y estrato aplicados. «Sin base» solo entra sin filtros (no tiene uso ni estrato).
  const a = useMemo(
    () => filasA.filter((x) =>
      enPeriodo(x.periodo)
      && (x.uso === SIN_BASE ? sinFiltroAB : (valores.uso === TODOS || x.uso === valores.uso)
        && (valores.estrato === TODOS || estratoMostrado(x.estrato, x.uso) === valores.estrato))),
    [filasA, sel, valores.uso, valores.estrato, sinFiltroAB], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const b = useMemo(
    () => filasB.filter((x) => enPeriodo(x.periodo) && (nCiclo == null || numeroCiclo(x.ciclo) === nCiclo)),
    [filasB, sel, nCiclo], // eslint-disable-line react-hooks/exhaustive-deps
  );

  const porMetodo = useMemo(() => agrupar(a, (x) => x.metodo_act, (x) => x), [a]);
  const porTray = useMemo(() => porTrayectoria(a), [a]);
  const todo = useMemo(() => agrupar(a, () => "t", (x) => x).get("t") ?? sumaVacia(), [a]);
  const sobre = useMemo(() => sobreLecturaEstable(porTray), [porTray]);

  if (A.error || B.error) return <Reintento titulo="Reclamos según el método de facturación" e={A.error ? A : B} />;
  if (!A.datos || !B.datos) return <Reintento titulo="Reclamos según el método de facturación" e={A} />;

  const etiquetaSel = sel === ACUMULADO ? `Acumulado (${periodos.length} períodos)` : etiquetaPeriodo(sel);
  const calculado = fechaCalculo(a.length ? a : filasA);
  const periodoTxt = sel === ACUMULADO ? `acumulado de ${periodos.length} períodos (${periodos.map(etiquetaPeriodo).join(", ")})` : etiquetaPeriodo(sel);
  const unSoloMes = sel !== ACUMULADO;

  // Motivo cuando el período del tablero no está en el análisis
  const motivoTablero = (() => {
    if (periodos.includes(periodo)) return null;
    if (periodo === "202606") return "202606 no existe en la fuente de consumo (consumo_metodo), así que no hay método de facturación para ese mes y sus reclamos no se usan.";
    if (periodo < periodos[0]) return `El análisis necesita el método del período anterior; antes de ${etiquetaPeriodo(periodos[0])} no hay período anterior en consumo_metodo.`;
    return `No hay datos calculados para ${etiquetaPeriodo(periodo)} (consumo_metodo aún no los trae).`;
  })();

  const mostrarFiltroNota = nCiclo != null || !sinFiltroAB;

  // ---------- trayectorias ----------
  const tray = (t: string) => porTray.get(t) ?? sumaVacia();
  const lect = tray(T_LECTURA);
  const cambian = ["Lectura → promedio", "Promedio → lectura"].reduce((s, t) => {
    const x = tray(t); s.contratos += x.contratos; s.consumo += x.consumo; s.promedio += x.promedio; return s;
  }, sumaVacia());
  const modif = tray(T_MODIF);
  const veces = (x: Suma) => {
    const r = tasaCP(lect), c = tasaCP(x);
    return r != null && r > 0 && c != null ? c / r : null;
  };
  const vecesCambian = veces(cambian);
  const vecesModif = veces(modif);
  const solTotal = solicitudesTotal(todo);
  const mensaje = vecesCambian == null
    ? "Sin muestra suficiente para comparar con la lectura estable."
    : `Los contratos que cambian de método reclaman ${fmtDecimal(vecesCambian, 1)} veces lo que reclaman los estables en lectura.`;

  return (
    <div className="dash-con-panel">
      <PanelFiltros filtros={filtros} valores={valores} onCambio={setValores}
        resumen={`${fmtEntero(solTotal)} solicitudes · ${fmtEntero(todo.contratos)} contratos-mes`} />
      <div className="dash-con-panel-cuerpo">
        <div className="dash-fila"><div className="dash-carta">
          <h3>Reclamos según el método de facturación — {etiquetaSel}</h3>
          <div className="dash-nota">
            Compara cuántos reclamos llegan por cada 1.000 contratos-mes según cómo se facturó el consumo: lectura, promedio,
            modificación directa u otro. <b>{AVISO_ASOCIACION}</b>
          </div>
          <div className="dash-filtros-bloque">
            <label>
              Período
              <select value={sel} onChange={(e) => setSel(e.target.value)}>
                <option value={ACUMULADO}>Acumulado ({periodos.length} períodos)</option>
                {periodos.map((p) => <option key={p} value={p}>{etiquetaPeriodo(p)}</option>)}
              </select>
            </label>
          </div>
          <div className="dash-nota">
            Períodos con datos: {periodos.map(etiquetaPeriodo).join(", ")}. 202606 no existe en la fuente de consumo; antes de {etiquetaPeriodo(periodos[0])} no hay método anterior con el cual comparar.
          </div>
          {unSoloMes ? <div className="dash-nota"><b>Las tasas de un solo mes son más ruidosas:</b> con pocas solicitudes por celda, una más o una menos mueve mucho la tasa. Para decidir, mire el acumulado.</div> : null}
          {motivoTablero ? <div className="dash-nota">El período del tablero ({etiquetaPeriodo(periodo)}) no tiene este análisis: {motivoTablero}</div> : null}
          {mostrarFiltroNota ? (
            <div className="dash-nota">
              Los filtros de uso y estrato afectan a todas las partes salvo «Por ciclo»; el filtro de ciclo solo afecta a «Por ciclo» (la tabla por ciclo no trae uso ni estrato).
              {!sinFiltroAB ? " Con uso o estrato filtrados no se incluye la fila «Sin base» (2 solicitudes de contratos fuera de consumo_metodo)." : ""}
            </div>
          ) : null}
        </div></div>

        <div className="dash-fila"><div className="dash-carta">
          <nav className="dash-indice" aria-label="Contenido de la sección">
            <b>Contenido:</b>
            {PARTES.map((x) => <button key={x.id} className="dash-boton-indice" onClick={() => abrir(x.id)}>{x.titulo}</button>)}
          </nav>
        </div></div>

        {/* 1. Resumen */}
        <Parte id="resumen" titulo="Resumen" abierta={!!abiertas.resumen} onCambio={(o) => cambiar("resumen", o)}>
          <div className="dash-kpis">
            <Kpi eti={`Solicitudes (${unSoloMes ? "período" : "acumulado"})`} valor={fmtEntero(solTotal)}
              sub={`${t2(tasaTotal(todo))} ${nombreTasa} · ${fmtEntero(todo.contratos)} contratos-mes`} />
            <Kpi eti="Tasa en lectura estable" valor={t2(tasaCP(lect))}
              sub={`consumo + promedio, ${nombreTasa} · ${fmtEntero(lect.contratos)} contratos-mes`} />
            <Kpi eti="Tasa en cambio de método" valor={t2(tasaCP(cambian))}
              sub={vecesCambian == null ? "sin muestra" : `${fmtDecimal(vecesCambian, 1)} veces la de lectura estable · lectura→promedio y promedio→lectura`} />
            <Kpi eti="Tasa en modificación directa (aparte)" valor={t2(tasaCP(modif))}
              sub={vecesModif == null ? "sin muestra" : `${fmtDecimal(vecesModif, 1)} veces la de lectura estable · ${fmtEntero(solicitudesCP(modif))} solicitudes`} />
            <Kpi eti="Solicitudes por encima (sin modificación directa)" valor={fmtEntero(Math.round(sobre.sinMod))}
              sub={`${pct1(solTotal ? (sobre.sinMod / solTotal) * 100 : null)} de las solicitudes totales`} />
            <Kpi eti="Solicitudes por encima (con modificación directa)" valor={fmtEntero(Math.round(sobre.conMod))}
              sub={`${pct1(solTotal ? (sobre.conMod / solTotal) * 100 : null)} de las solicitudes totales`} />
            <Kpi eti="Contratos con al menos un reclamo" valor={pct1(todo.contratos ? (todo.conReclamo / todo.contratos) * 100 : null)}
              sub={`${fmtEntero(todo.conReclamo)} de ${fmtEntero(todo.contratos)} contratos-mes`} />
          </div>
          <div className="dash-nota"><b>{AVISO_ASOCIACION}</b> «Cambio de método» = lectura→promedio y promedio→lectura; la modificación directa se muestra aparte. {NOTA_MODIF} «Por encima» es una referencia aproximada, no una estimación causal.</div>
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula={`Tasa = solicitudes × 1.000 ÷ contratos-mes (una solicitud cuenta una vez por contrato y período). La tasa de lectura estable, la de cambio de método (solo lectura→promedio y promedio→lectura) y la de modificación directa usan solicitudes de consumo + promedio. «Veces» = tasa del grupo ÷ tasa en lectura estable. «Por encima»: para cada trayectoria distinta de «estable en lectura», solicitudes de consumo + promedio menos contratos-mes × tasa de consumo + promedio de «estable en lectura»; se suman sin la modificación directa y con ella, y se expresan como % de las solicitudes totales (${fmtEntero(solTotal)}). Es una referencia aproximada, no una estimación causal: supone que, sin el cambio de método, esos contratos reclamarían como los estables en lectura.`} />
        </Parte>

        {/* 2. Por método del período */}
        <Parte id="metodo" titulo="Tasa por método de facturación del período" abierta={!!abiertas.metodo} onCambio={(o) => cambiar("metodo", o)}>
          <BarrasApiladas
            datos={METODOS.map((m) => {
              const s = porMetodo.get(m) ?? sumaVacia();
              return { etiqueta: etiquetaMetodo(m), valores: GRUPOS.map((g) => valorBarra(solicitudesGrupo(s, g.id), s.contratos)) };
            })}
            series={GRUPOS.map((g) => ({ nombre: g.nombre, color: g.color }))}
            formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} margenIzq={140}
          />
          <TablaPlegable titulo="Datos: tasa por método de facturación">
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead><tr><th>Método</th><th>Contratos-mes</th><th>Solicitudes</th><th>Tasa {nombreTasa}</th></tr></thead>
                <tbody>
                  {METODOS.map((m) => {
                    const s = porMetodo.get(m) ?? sumaVacia();
                    return <tr key={m}><td>{etiquetaMetodo(m)}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(solicitudesTotal(s))}</td><td className="num"><Tasa sol={solicitudesTotal(s)} contratos={s.contratos} /></td></tr>;
                  })}
                  {(porMetodo.get(SIN_BASE)?.contratos !== undefined) ? (() => {
                    const s = porMetodo.get(SIN_BASE) ?? sumaVacia();
                    return <tr key="sb"><td>{SIN_BASE} (contratos fuera de consumo_metodo)</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(solicitudesTotal(s))}</td><td className="num">—</td></tr>;
                  })() : null}
                </tbody>
              </table>
            </div>
          </TablaPlegable>
          <div className="dash-nota">Las barras suman la tasa total del método; cada color es un grupo de causal. «Muestra pequeña»: menos de {fmtEntero(MUESTRA_PEQUENA)} contratos-mes.</div>
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Método del período = método con que se facturó el consumo del mes. Cada barra es solicitudes del grupo de causal × 1.000 ÷ contratos-mes del método; el total del método es la suma de los grupos. Resto = causales fuera de los grupos nombrados." />
        </Parte>

        {/* 3. Trayectorias */}
        <Parte id="trayectorias" titulo="Trayectorias" abierta={!!abiertas.trayectorias} onCambio={(o) => cambiar("trayectorias", o)}>
          <div className="dash-nota"><b>{mensaje}</b>
            {` Cambian de método: lectura→promedio y promedio→lectura.`} {AVISO_ASOCIACION}</div>
          <div className="dash-nota">Modificación directa (aparte): {t2(tasaCP(modif))} {nombreTasa}{vecesModif == null ? "" : `, ${fmtDecimal(vecesModif, 1)} veces la de lectura estable`}. {NOTA_MODIF}</div>
          <BarrasHorizontales
            datos={TRAYECTORIAS.map((t) => ({ etiqueta: t, valor: tasaCP(tray(t)) ?? 0 }))}
            formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} color={COLOR}
          />
          <TablaPlegable titulo="Datos: trayectorias (consumo + promedio)">
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead><tr><th>Trayectoria</th><th>Contratos-mes</th><th>Solicitudes (consumo + promedio)</th><th>Tasa {nombreTasa}</th><th>Veces la lectura estable</th></tr></thead>
                <tbody>
                  {TRAYECTORIAS.map((t) => {
                    const s = tray(t);
                    const v = t === T_LECTURA ? null : veces(s);
                    return (
                      <tr key={t}><td>{t}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(solicitudesCP(s))}</td>
                        <td className="num"><Tasa sol={solicitudesCP(s)} contratos={s.contratos} /></td>
                        <td className="num">{v == null ? "—" : fmtDecimal(v, 1)}</td></tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </TablaPlegable>
          <div className="dash-nota">{NOTA_MODIF}</div>
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Trayectoria = método anterior (período anterior disponible) y método del período. Modificación directa: cualquiera de los dos es modificación directa. Otras: el resto de combinaciones (incluye método anterior sin dato u otro). Tasa = solicitudes de consumo + promedio × 1.000 ÷ contratos-mes. Las 7 trayectorias suman todos los contratos-mes." />
        </Parte>

        {/* 4. Matriz */}
        <Parte id="matriz" titulo="Método anterior × método del período" abierta={!!abiertas.matriz} onCambio={(o) => cambiar("matriz", o)}>
          {(() => {
            const filas = ["lectura", "promedio", "promedio_sin_medidor", "modificacion_directa", "otro", "sin_dato"];
            const m = agrupar(a.filter((x) => x.uso !== SIN_BASE), (x) => `${x.metodo_ant}|${x.metodo_act}`, (x) => x);
            return (
              <>
                <div className="dash-tabla-scroll">
                  <table className="dash-tabla num">
                    <thead><tr><th>Método anterior ↓ / del período →</th>{METODOS.map((c) => <th key={c}>{etiquetaMetodo(c)}</th>)}</tr></thead>
                    <tbody>
                      {filas.map((f) => (
                        <tr key={f}><td>{etiquetaMetodo(f)}</td>
                          {METODOS.map((c) => {
                            const s = m.get(`${f}|${c}`) ?? sumaVacia();
                            return (
                              <td key={c} className="num">
                                {s.contratos < MIN_CONTRATOS_MES ? "—" : <><Tasa sol={solicitudesCP(s)} contratos={s.contratos} /><br /><small>{fmtEntero(s.contratos)} contratos-mes</small></>}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="dash-nota">Cada celda: tasa de consumo + promedio {nombreTasa} y contratos-mes. «—»: menos de {MIN_CONTRATOS_MES} contratos-mes. «Muestra pequeña»: menos de {fmtEntero(MUESTRA_PEQUENA)}.</div>
              </>
            );
          })()}
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Filas: método del período anterior disponible (202607 se compara con 202605). Columnas: método del período. Tasa = solicitudes de consumo + promedio × 1.000 ÷ contratos-mes de la celda." />
        </Parte>

        {/* 5. Antigüedad */}
        <Parte id="antiguedad" titulo="Por antigüedad del medidor" abierta={!!abiertas.antiguedad} onCambio={(o) => cambiar("antiguedad", o)}>
          {[T_LECTURA, TRAYECTORIAS[1]].map((t) => {
            const m = agrupar(a.filter((x) => trayectoriaDe(x.metodo_ant, x.metodo_act) === t), (x) => x.banda_antig, (x) => x);
            const bandas = BANDAS.filter((bb) => m.has(bb));
            return (
              <Sub key={t} titulo={t}>
                <BarrasApiladas
                  datos={bandas.map((bb) => { const s = m.get(bb)!; return { etiqueta: etiquetaBanda(bb), valores: GRUPOS.map((g) => valorBarra(solicitudesGrupo(s, g.id), s.contratos)) }; })}
                  series={GRUPOS.map((g) => ({ nombre: g.nombre, color: g.color }))}
                  formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} margenIzq={200}
                />
                <TablaPlegable titulo={`Datos: ${t.toLowerCase()} por antigüedad`}>
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Antigüedad</th><th>Contratos-mes</th><th>Tasa de consumo</th>{GRUPOS.map((g) => <th key={g.id}>{g.nombre}</th>)}</tr></thead>
                      <tbody>
                        {bandas.map((bb) => {
                          const s = m.get(bb)!;
                          return (
                            <tr key={bb}><td>{etiquetaBanda(bb)}</td><td className="num">{fmtEntero(s.contratos)}</td>
                              <td className="num"><Tasa sol={s.consumo} contratos={s.contratos} /></td>
                              {GRUPOS.map((g) => <td key={g.id} className="num">{t2(porMil(solicitudesGrupo(s, g.id), s.contratos))}</td>)}</tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </TablaPlegable>
              </Sub>
            );
          })}
          <div className="dash-nota"><b>Hipótesis, no hallazgo.</b> Con lectura real, la tasa de reclamos por consumo no aumenta con la antigüedad; es mayor en los medidores de 0 a 3 años. Puede deberse a que un medidor nuevo registra más consumo, o a que se instaló tras un reclamo; con estos datos no se puede separar.</div>
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Banda = años desde la fecha de instalación del medidor al cierre del período (las fechas 1986-01-01 se separan porque son una fecha por defecto, no real). Tasa de consumo = solicitudes del grupo consumo × 1.000 ÷ contratos-mes. El desglose muestra la tasa de cada grupo de causal. Solo para contratos estables en lectura y estables en promedio con medidor." />
        </Parte>

        {/* 6. Estrato y uso */}
        <Parte id="estrato" titulo="Por estrato y uso (estable en lectura)" abierta={!!abiertas.estrato} onCambio={(o) => cambiar("estrato", o)}>
          {(() => {
            const base = a.filter((x) => trayectoriaDe(x.metodo_ant, x.metodo_act) === T_LECTURA);
            const porEstr = agrupar(base, (x) => estratoMostrado(x.estrato, x.uso), (x) => x);
            const porUso = agrupar(base, (x) => x.uso, (x) => x);
            const estratos = [...porEstr.keys()].sort((p, q) => (p === OTROS_USOS ? 1 : q === OTROS_USOS ? -1 : p.localeCompare(q, "es")));
            const usos = [...porUso.keys()].sort((p, q) => p.localeCompare(q, "es"));
            const m = agrupar(base, (x) => `${estratoMostrado(x.estrato, x.uso)}|${x.banda_antig}`, (x) => x);
            const bandas = BANDAS.filter((bb) => estratos.some((e) => m.has(`${e}|${bb}`)));
            return (
              <>
                <div className="dash-fila-g2">
                  <div><h3>Por estrato</h3>
                    <BarrasHorizontales datos={estratos.map((e) => ({ etiqueta: e, valor: tasaOConsumo(porEstr.get(e)!) }))} formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} color={COLOR} /></div>
                  <div><h3>Por uso</h3>
                    <BarrasHorizontales datos={usos.map((u) => ({ etiqueta: u, valor: tasaOConsumo(porUso.get(u)!) }))} formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} color="#0E7C86" /></div>
                </div>
                <TablaPlegable titulo="Datos: estrato y uso (tasa de consumo)">
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Grupo</th><th>Contratos-mes</th><th>Solicitudes de consumo</th><th>Tasa de consumo</th></tr></thead>
                      <tbody>
                        {estratos.map((e) => { const s = porEstr.get(e)!; return <tr key={`e${e}`}><td>{e}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(s.consumo)}</td><td className="num"><Tasa sol={s.consumo} contratos={s.contratos} /></td></tr>; })}
                        {usos.map((u) => { const s = porUso.get(u)!; return <tr key={`u${u}`}><td>Uso: {u}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(s.consumo)}</td><td className="num"><Tasa sol={s.consumo} contratos={s.contratos} /></td></tr>; })}
                      </tbody>
                    </table>
                  </div>
                </TablaPlegable>
                <label className="dash-nota"><input type="checkbox" checked={estratoBanda} onChange={(e) => setEstratoBanda(e.target.checked)} /> Ver estrato × antigüedad del medidor</label>
                {estratoBanda ? (
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Estrato</th>{bandas.map((bb) => <th key={bb}>{etiquetaBanda(bb)}</th>)}</tr></thead>
                      <tbody>
                        {estratos.map((e) => (
                          <tr key={e}><td>{e}</td>
                            {bandas.map((bb) => {
                              const s = m.get(`${e}|${bb}`);
                              return <td key={bb} className="num">{!s || s.contratos <= MUESTRA_PEQUENA ? <small>muestra pequeña</small> : t2(porMil(s.consumo, s.contratos))}</td>;
                            })}</tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : null}
                {estratoBanda ? <div className="dash-nota">Tasa de consumo {nombreTasa}. Solo se muestran celdas con más de {fmtEntero(MUESTRA_PEQUENA)} contratos-mes; el resto, «muestra pequeña».</div> : null}
              </>
            );
          })()}
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Contratos estables en lectura. Tasa de consumo = solicitudes del grupo consumo × 1.000 ÷ contratos-mes. Estrato: en los usos no residenciales la fuente trae diámetros de acometida y otros códigos; se agrupan en «Otros usos»." />
        </Parte>

        {/* 7. Ciclo */}
        <Parte id="ciclo" titulo="Por ciclo" abierta={!!abiertas.ciclo} onCambio={(o) => cambiar("ciclo", o)}>
          {(() => {
            const porC = agrupar(b, (x) => x.ciclo, (x) => x);
            const grandes = [...porC.entries()].filter(([, s]) => s.contratos >= MIN_CONTRATOS_MES);
            const chicos = [...porC.entries()].filter(([, s]) => s.contratos < MIN_CONTRATOS_MES);
            const otros = chicos.reduce((s, [, x]) => { for (const k of Object.keys(s) as (keyof Suma)[]) s[k] += x[k]; return s; }, sumaVacia());
            const orden = grandes.sort((p, q) => (numeroCiclo(p[0]) ?? 999) - (numeroCiclo(q[0]) ?? 999));
            const filas: [string, Suma][] = chicos.length ? [...orden, [OTROS_CICLOS, otros]] : orden;
            const etq = (c: string) => (c === OTROS_CICLOS ? c : numeroCiclo(c) != null ? etiquetaCiclo(numeroCiclo(c)!) : c);
            const m = agrupar(b, (x) => `${x.ciclo}|${x.metodo_act}`, (x) => x);
            const pareto = [...filas].sort((p, q) => solicitudesTotal(q[1]) - solicitudesTotal(p[1]));
            const totSol = pareto.reduce((s, [, x]) => s + solicitudesTotal(x), 0);
            let acum = 0;
            return (
              <>
                {nCiclo != null ? <div className="dash-nota">Filtro de ciclo activo: solo se muestra {etiquetaCiclo(nCiclo)}. Este filtro no afecta a las demás partes.</div> : null}
                {!sinFiltroAB ? <div className="dash-nota">Esta parte no aplica los filtros de uso ni estrato: la tabla por ciclo no los trae.</div> : null}
                <Sub titulo="Tasa total por ciclo">
                  <BarrasHorizontales datos={filas.map(([c, s]) => ({ etiqueta: etq(c), valor: tasaTotal(s) ?? 0 }))} formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} color={COLOR} />
                </Sub>
                <Sub titulo="Pareto de solicitudes por ciclo">
                  <BarrasHorizontales datos={pareto.map(([c, s]) => ({ etiqueta: etq(c), valor: solicitudesTotal(s) }))} formatoValor={(v) => `${fmtEntero(v)} solicitudes`} color="#C98A2D" />
                </Sub>
                <TablaPlegable titulo="Datos: ciclo y método (tasa total)">
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Ciclo</th><th>Contratos-mes</th><th>Solicitudes</th><th>Tasa</th>{METODOS.map((mm) => <th key={mm}>Tasa · {etiquetaMetodo(mm)}</th>)}<th>% acumulado (Pareto)</th></tr></thead>
                      <tbody>
                        {pareto.map(([c, s]) => {
                          acum += solicitudesTotal(s);
                          return (
                            <tr key={c}><td>{etq(c)}</td><td className="num">{fmtEntero(s.contratos)}</td><td className="num">{fmtEntero(solicitudesTotal(s))}</td>
                              <td className="num"><Tasa sol={solicitudesTotal(s)} contratos={s.contratos} /></td>
                              {METODOS.map((mm) => {
                                // el ciclo «Otros» no tiene celdas por método: se suma de sus ciclos
                                const sm = c === OTROS_CICLOS
                                  ? chicos.reduce((z, [cc]) => { const q = m.get(`${cc}|${mm}`); if (q) for (const k of Object.keys(z) as (keyof Suma)[]) z[k] += q[k]; return z; }, sumaVacia())
                                  : m.get(`${c}|${mm}`) ?? sumaVacia();
                                return <td key={mm} className="num"><Tasa sol={solicitudesTotal(sm)} contratos={sm.contratos} /></td>;
                              })}
                              <td className="num">{pct1(totSol ? (acum / totSol) * 100 : null)}</td></tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </TablaPlegable>
                <div className="dash-nota">Los ciclos con menos de {MIN_CONTRATOS_MES} contratos en el período elegido se agrupan en «{OTROS_CICLOS}» (incluye las solicitudes de contratos «Sin base»). En 202609 el ciclo 5 se separó en el 5 y el 24.</div>
              </>
            );
          })()}
          <Pie fuente={FUENTE_B} periodo={periodoTxt} calculado={fechaCalculo(b.length ? b : filasB)}
            formula="Tasa por ciclo y método = solicitudes totales × 1.000 ÷ contratos-mes del ciclo y método del período. Pareto: ciclos ordenados por solicitudes, con el porcentaje acumulado del total. Usa la tabla por ciclo, que no trae uso ni estrato." />
        </Parte>

        {/* 8. No consumo */}
        <Parte id="noconsumo" titulo="Reclamos que no son de consumo" abierta={!!abiertas.noconsumo} onCambio={(o) => cambiar("noconsumo", o)}>
          {(() => {
            const gs = GRUPOS.filter((g) => ["desocupado", "cartera", "admin", "resto"].includes(g.id));
            return (
              <>
                <BarrasApiladas
                  datos={METODOS.map((m) => { const s = porMetodo.get(m) ?? sumaVacia(); return { etiqueta: etiquetaMetodo(m), valores: gs.map((g) => valorBarra(solicitudesGrupo(s, g.id), s.contratos)) }; })}
                  series={gs.map((g) => ({ nombre: g.nombre, color: g.color }))}
                  formatoValor={(v) => `${fmtDecimal(v, 2)} ${nombreTasa}`} margenIzq={140}
                />
                <TablaPlegable titulo="Datos: reclamos que no son de consumo por método">
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Método</th><th>Contratos-mes</th>{gs.map((g) => <th key={g.id}>{g.nombre} (solicitudes)</th>)}{gs.map((g) => <th key={`t${g.id}`}>Tasa · {g.nombre}</th>)}</tr></thead>
                      <tbody>
                        {METODOS.map((m) => {
                          const s = porMetodo.get(m) ?? sumaVacia();
                          return (
                            <tr key={m}><td>{etiquetaMetodo(m)}</td><td className="num">{fmtEntero(s.contratos)}</td>
                              {gs.map((g) => <td key={g.id} className="num">{fmtEntero(solicitudesGrupo(s, g.id))}</td>)}
                              {gs.map((g) => <td key={`t${g.id}`} className="num">{t2(porMil(solicitudesGrupo(s, g.id), s.contratos))}</td>)}</tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </TablaPlegable>
              </>
            );
          })()}
          <div className="dash-nota">Desocupado, cartera y administrativas no dependen del método de facturación del consumo; se muestran para comprobar que no explican la diferencia.</div>
          <Pie fuente={FUENTE_A} periodo={periodoTxt} calculado={calculado}
            formula="Grupos: desocupado (1114), cartera (1111), administrativas (1315) y resto (las demás causales fuera de consumo, promedio y medidor). Tasa = solicitudes del grupo × 1.000 ÷ contratos-mes del método del período." />
        </Parte>

        {/* 9. Metodología */}
        <Parte id="metodologia" titulo="Metodología y fuentes" abierta={!!abiertas.metodologia} onCambio={(o) => cambiar("metodologia", o)}>
          <Sub titulo="Qué mide y qué no">
            <div className="dash-nota">
              Mide cuántas solicitudes de reclamo llegan, por cada 1.000 contratos-mes, según cómo se facturó el consumo del contrato ese mes.
              <b> No mide causa y efecto:</b> {AVISO_ASOCIACION} No dice si el método genera el reclamo, si el reclamo cambia el método, o si ambos dependen de otro problema del contrato.
            </div>
          </Sub>
          <Sub titulo="Método de facturación">
            <ul className="dash-nota">
              <li><b>Lectura:</b> observación 99 y CALCCODL.</li>
              <li><b>Promedio con medidor:</b> OBTECOPP, OBTECOPS o [FAMC], con medidor registrado.</li>
              <li><b>Promedio sin medidor:</b> las mismas funciones, sin medidor registrado.</li>
              <li><b>Modificación directa:</b> [FOVC], [FAJF].</li>
              <li><b>Otro:</b> el resto.</li>
            </ul>
          </Sub>
          <Sub titulo="Grupos de causal">
            <ul className="dash-nota">
              <li><b>Consumo:</b> 1102, 1121, 1127, 1129, 1101. <b>Promedio:</b> 1120. <b>Medidor:</b> 1110. <b>Desocupado:</b> 1114. <b>Cartera:</b> 1111. <b>Administrativas:</b> 1315. <b>Resto:</b> las demás.</li>
              <li>Los reclamos con causal 1102 incluyen consumo alto real y fugas internas, no solo falla del medidor.</li>
            </ul>
          </Sub>
          <Sub titulo="Unidad y método anterior">
            <div className="dash-nota">
              Unidad: solicitudes distintas por contrato y período; tasa por 1.000 contratos-mes. Método anterior = período anterior disponible
              (202607 se compara con 202605). 202606 no existe en consumo_metodo y sus reclamos no se usan. Una fila «Sin base» recoge reclamos de contratos que no están en consumo_metodo (no tienen contratos-mes).
            </div>
          </Sub>
          <Sub titulo="Conciliación por período (sin filtros)">
            {(() => {
              const tA = agrupar(filasA, (x) => x.periodo, (x) => x);
              const tB = agrupar(filasB, (x) => x.periodo, (x) => x);
              const sb = agrupar(filasA.filter((x) => x.uso === SIN_BASE), (x) => x.periodo, (x) => x);
              const ps = [...new Set([...tA.keys(), ...tB.keys()])].sort();
              const fila = (p: string) => {
                const a1 = tA.get(p) ?? sumaVacia(), b1 = tB.get(p) ?? sumaVacia();
                const ok = a1.contratos === b1.contratos && solicitudesTotal(a1) === solicitudesTotal(b1);
                return { a1, b1, ok, sb: sb.get(p) ?? sumaVacia() };
              };
              const filas = ps.map((p) => ({ p, ...fila(p) }));
              const todoOk = filas.every((f) => f.ok);
              const suma = (xs: Suma[]) => xs.reduce((z, x) => { z.contratos += x.contratos; z.consumo += x.consumo; z.promedio += x.promedio; z.medidor += x.medidor; z.otras += x.otras; return z; }, sumaVacia());
              const tA2 = suma(filas.map((f) => f.a1)), tB2 = suma(filas.map((f) => f.b1)), tSb = suma(filas.map((f) => f.sb));
              return (
                <>
                  <div className="dash-tabla-scroll">
                    <table className="dash-tabla num">
                      <thead><tr><th>Período</th><th>Contratos-mes (A)</th><th>Solicitudes (A)</th><th>Contratos-mes (B)</th><th>Solicitudes (B)</th><th>¿Coinciden A y B?</th><th>De ellas, «Sin base» (solicitudes)</th></tr></thead>
                      <tbody>
                        {filas.map((f) => (
                          <tr key={f.p}><td>{etiquetaPeriodo(f.p)}</td><td className="num">{fmtEntero(f.a1.contratos)}</td><td className="num">{fmtEntero(solicitudesTotal(f.a1))}</td>
                            <td className="num">{fmtEntero(f.b1.contratos)}</td><td className="num">{fmtEntero(solicitudesTotal(f.b1))}</td>
                            <td className="num">{f.ok ? "Sí" : "No"}</td><td className="num">{fmtEntero(solicitudesTotal(f.sb))}</td></tr>
                        ))}
                        <tr><td><b>Total</b></td><td className="num"><b>{fmtEntero(tA2.contratos)}</b></td><td className="num"><b>{fmtEntero(solicitudesTotal(tA2))}</b></td>
                          <td className="num"><b>{fmtEntero(tB2.contratos)}</b></td><td className="num"><b>{fmtEntero(solicitudesTotal(tB2))}</b></td>
                          <td className="num"><b>{todoOk ? "Sí" : "No"}</b></td><td className="num"><b>{fmtEntero(solicitudesTotal(tSb))}</b></td></tr>
                      </tbody>
                    </table>
                  </div>
                  <div className="dash-nota">{todoOk ? "A y B coinciden en todos los períodos." : "Atención: A y B no coinciden en algún período."} La fila «Sin base» recoge reclamos de contratos que no están en consumo_metodo (sin contratos-mes). Los períodos salen de los datos cargados.</div>
                </>
              );
            })()}
            <div className="dash-nota">El cargador verifica en cada carga que las solicitudes totales por período coincidan con las solicitudes distintas de hechos.reclamos.</div>
          </Sub>
          <Sub titulo="Límites">
            <ul className="dash-nota">
              <li>Asociación, no causalidad.</li>
              <li>{NOTA_MODIF}</li>
              <li>Los contratos que cambian de método pueden tener otros problemas que explican el reclamo.</li>
              <li>Muestras pequeñas: con menos de {fmtEntero(MUESTRA_PEQUENA)} contratos-mes las tasas son inestables; con menos de {MIN_CONTRATOS_MES} no se calculan.</li>
              <li>Un solo mes es más ruidoso que el acumulado.</li>
            </ul>
          </Sub>
          <Pie fuente={`${FUENTE_A}; ${FUENTE_B}`} periodo={periodoTxt} calculado={fechaCalculo(filasA)}
            formula="Las tablas resumen se calculan en la base a partir de hechos.consumo_metodo (método de facturación, antigüedad, uso, estrato, ciclo) y hechos.reclamos (solo período, contrato, solicitud y causal). Nunca se muestran contratos, números de solicitud ni datos personales." />
        </Parte>
      </div>
    </div>
  );
}

// Tasa de consumo de un grupo para las barras (0 si no hay muestra).
function tasaOConsumo(s: Suma): number {
  return porMil(s.consumo, s.contratos) ?? 0;
}
