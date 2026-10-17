import { Fragment, useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { LineasPorDia, TablaPlegable } from "../graficas";
import { LineasMensuales } from "../LineasMensuales";
import { etiquetaPeriodo } from "../formato";
import {
  armarAnio, armarEscenarios, armarTablaFO, comoAnualMes, comoPresupuesto, NOM_ACT, NOM_PRES, comoCumplimientoDia, comoDiaOrigen, comoRecaudoRuta, comoSubsidioMes, comoTotalMes,
  diasDelMes, fm1, fmtExacto, fmtPct1, marcaDia, mesCorto, metaCertificadaPorMes, mm1, periodoEnCurso, resumenMes, semaforo,
  type Anio, type AnualMes, type CumplimientoDia, type Presupuesto, type DiaOrigen, type RecaudoRuta, type SubsidioMes, type TotalMes,
} from "../proyeccionRecaudo";
import "../proyeccionRecaudo.css";

// Proyección y cumplimiento del recaudo 2026. Va debajo de RECAUDO DIARIO y es independiente: si una vista falla, solo se
// afecta su sección. Solo agregados. Los subsidios son informativos y no entran en el cumplimiento ni en el recaudo.

type Estado<T> = { datos: T | null; error: string | null };
const vacio = <T,>(): Estado<T> => ({ datos: null, error: null });

function useVista<T>(vista: string, conv: (r: Record<string, unknown>) => T, intento: number): Estado<T[]> {
  const [e, setE] = useState<Estado<T[]>>(vacio);
  useEffect(() => {
    let vivo = true;
    setE(vacio());
    biCache(vista)
      .then((r) => vivo && setE({ datos: ((r.datos ?? []) as Record<string, unknown>[]).map(conv), error: null }))
      .catch((x: Error) => vivo && setE({ datos: null, error: x.message || "Error de consulta" }));
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, intento]);
  return e;
}

function Falla({ nombre, msg, onReintentar }: { nombre: string; msg: string; onReintentar: () => void }) {
  return (
    <div className="proy-error" role="alert">
      No fue posible cargar {nombre}: {msg}
      <button type="button" onClick={onReintentar}>Reintentar</button>
    </div>
  );
}

const ult = <T,>(v: T[]): T | null => (v.length ? v[v.length - 1] : null);
const Cargando = () => <p className="proy-sub">Cargando…</p>;

function Sem({ pct }: { pct: number | null }) {
  const s = semaforo(pct);
  if (!s) return <span className="proy-sinmeta">Sin meta cargada</span>;
  return <span className={`proy-semaforo proy-${s === "verde" ? "verde" : s === "ambar" ? "ambar" : "rojo"}`}>{fmtPct1(pct)}</span>;
}

const Monto = ({ v }: { v: number | null }) => <span title={fmtExacto(v) || undefined}>{fm1(v)}</span>;

export function ProyeccionRecaudo() {
  const [intento, setIntento] = useState(0);
  const reintentar = () => setIntento((n) => n + 1);
  const cum = useVista<CumplimientoDia>("v_proy_cumplimiento", comoCumplimientoDia, intento);
  const anual = useVista<AnualMes>("v_proy_anual", comoAnualMes, intento);
  const tot = useVista<TotalMes>("v_proy_recaudo_total", comoTotalMes, intento);
  const rutas = useVista<RecaudoRuta>("v_proy_recaudo", comoRecaudoRuta, intento);
  const subs = useVista<SubsidioMes>("v_facturacion_mes", comoSubsidioMes, intento);
  const diario = useVista<DiaOrigen>("v_recaudo_diario_mes", comoDiaOrigen, intento);
  const pres = useVista<Presupuesto>("v_proy_presupuesto_fo", comoPresupuesto, intento);
  const anio = useMemo(() => (anual.datos && pres.datos && subs.datos ? armarAnio(anual.datos, pres.datos, subs.datos) : null), [anual.datos, pres.datos, subs.datos]);
  const cargando = !anual.datos || !pres.datos || !subs.datos;
  const errAnio = anual.error ?? pres.error ?? subs.error;

  return (
    <section className="proy-seccion" aria-label="Proyección y cumplimiento">
      <h2>Proyección y cumplimiento del recaudo</h2>
      <p className="proy-sub">Base principal: sin subsidios. «Ingresos» es el total con subsidios (déficit). Cifras sin terceros salvo donde se indique.</p>
      <MesEnCurso cum={cum} diario={diario} onReintentar={reintentar} />
      <Anual anio={anio} tot={tot} cargando={cargando} err={errAnio} onReintentar={reintentar} />
      <MesAMes anio={anio} rutas={rutas} cum={cum} anual={anual} cargando={cargando} err={errAnio} onReintentar={reintentar} />
      <Subsidios anio={anio} tot={tot} cargando={cargando} err={tot.error ?? errAnio} onReintentar={reintentar} />
      <Escenarios anio={anio} tot={tot} cargando={cargando} err={tot.error ?? errAnio} onReintentar={reintentar} />
    </section>
  );
}

// ---------- A. mes en curso ----------
function MesEnCurso({ cum, diario, onReintentar }: { cum: Estado<CumplimientoDia[]>; diario: Estado<DiaOrigen[]>; onReintentar: () => void }) {
  const sel = useMemo(() => (cum.datos && diario.datos ? periodoEnCurso(cum.datos, diario.datos) : null), [cum.datos, diario.datos]);
  const r = useMemo(() => (cum.datos && sel?.periodo ? resumenMes(cum.datos, sel.periodo) : null), [cum.datos, sel]);
  const err = cum.error ?? diario.error;
  return (
    <div>
      <h3>A. Mes en curso (sin subsidios){sel?.periodo ? ` — ${etiquetaPeriodo(sel.periodo)}` : ""}</h3>
      {err ? <Falla nombre="el cumplimiento del mes" msg={err} onReintentar={onReintentar} /> : !cum.datos || !diario.datos ? <Cargando /> : !sel?.periodo || !r ? (
        <p className="proy-sinmeta">Sin meta cargada para el mes en curso.</p>
      ) : (
        <ContenidoMes r={r} dias={cum.datos.filter((c) => c.periodo === r.periodo)} curso={sel.origen === "curso"} />
      )}
    </div>
  );
}

function ContenidoMes({ r, dias, curso }: { r: NonNullable<ReturnType<typeof resumenMes>>; dias: CumplimientoDia[]; curso: boolean }) {
  const sinMeta = r.metaCertAcum == null && r.metaPropiaAcum == null;
  const n = diasDelMes(r.periodo);
  const porDia = (f: (d: CumplimientoDia) => number | null, hasta?: number) =>
    Array.from({ length: n }, (_, i) => { const d = dias.find((x) => x.dia === i + 1); return d && (hasta == null || d.dia <= hasta) ? f(d) : null; });
  const [ocultas, setOcultas] = useState<string[]>([]);
  const alternar = (nombre: string) => setOcultas((o) => (o.includes(nombre) ? o.filter((x) => x !== nombre) : [...o, nombre]));
  return (
    <>
      {curso && (
        <p className="dash-nota">
          Mes en curso: datos del cargue diario, no del cierre. El acumulado es lectura firme; el detalle por día es referencia.
          Corte al día {r.ultDia}.
        </p>
      )}
      <div className="dash-kpis">
        <div className="dash-carta dash-kpi"><span>Recaudo acumulado al día {r.ultDia}</span><strong><Monto v={r.realAcum} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Meta proyección comercial certificada, acumulada</span><strong>{r.metaCertAcum == null ? <span className="proy-sinmeta">Sin meta cargada</span> : <Monto v={r.metaCertAcum} />}</strong></div>
        <div className="dash-carta dash-kpi"><span>Meta proyección comportamiento actual, acumulada</span><strong>{r.metaPropiaAcum == null ? <span className="proy-sinmeta">Sin meta cargada</span> : <Monto v={r.metaPropiaAcum} />}</strong></div>
        <div className="dash-carta dash-kpi"><span>Cumplimiento frente a la proyección comercial certificada</span><strong><Sem pct={r.cumplCert} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Cumplimiento frente a la proyección comportamiento actual</span><strong><Sem pct={r.cumplPropia} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Falta para la meta del mes (comercial certificada)</span><strong><Monto v={r.faltaCert} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Falta para la meta del mes (comportamiento actual)</span><strong><Monto v={r.faltaPropia} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Cierre estimado (comportamiento actual, corregida con el avance)</span><strong><Monto v={r.cierre} /></strong></div>
        <div className={`dash-carta dash-kpi ${r.difCierreCert != null && r.difCierreCert < 0 ? "dash-kpi-mal" : ""}`}><span>Cierre frente a la meta del mes (comercial certificada)</span><strong><Monto v={r.difCierreCert} /></strong></div>
        <div className={`dash-carta dash-kpi ${r.difCierrePropia != null && r.difCierrePropia < 0 ? "dash-kpi-mal" : ""}`}><span>Cierre frente a la meta del mes (comportamiento actual)</span><strong><Monto v={r.difCierrePropia} /></strong></div>
      </div>
      {sinMeta ? null : (
        <LineasPorDia
          series={[
            { nombre: "Real acumulado", color: "#0E7C86", valores: porDia((d) => d.real_acum, r.ultDia) },
            { nombre: "Meta proyección comercial certificada", color: "#0a2540", valores: porDia((d) => d.meta_certificada_acum) },
            { nombre: "Meta proyección comportamiento actual", color: "#c27a00", valores: porDia((d) => d.meta_propia_acum) },
          ]}
          formatoValor={fm1}
          formatoEjeY={(v) => `${Math.round(v / 1e6).toLocaleString("es-CO")} M`}
          diaCorte={r.ultDia}
          ocultas={ocultas}
          onToggle={alternar}
        />
      )}
      <TablaPlegable titulo={`Días restantes del mes (${r.restantes.length})`}>
        {r.restantes.length === 0 ? <p className="proy-sub">El mes no tiene días restantes.</p> : (
          <table className="dash-tabla proy-tabla">
            <thead><tr><th>Fecha</th><th>Tipo de día</th><th className="num">Exigencia diaria (comercial certificada)</th><th className="num">Exigencia diaria (comportamiento actual)</th></tr></thead>
            <tbody>
              {r.restantes.map((d) => { const m = marcaDia(d.tipo_dia); return (
                <tr key={d.dia}>
                  <td>{d.fecha}</td>
                  <td className={m.clase ? `proy-dia-${m.clase}` : undefined}>{m.texto}</td>
                  <td className="num" title={fmtExacto(d.exigencia_dia_certificada) || undefined}>{fm1(d.exigencia_dia_certificada)}</td>
                  <td className="num" title={fmtExacto(d.exigencia_dia_propia) || undefined}>{fm1(d.exigencia_dia_propia)}</td>
                </tr>); })}
            </tbody>
            <tfoot>
              <tr className="dash-fila-fuerte"><td colSpan={2}>Total</td><td className="num"><Monto v={r.totalExigCert} /></td><td className="num"><Monto v={r.totalExigPropia} /></td></tr>
              <tr><td colSpan={2}>Promedio por día</td><td className="num"><Monto v={r.promExigCert} /></td><td className="num"><Monto v={r.promExigPropia} /></td></tr>
            </tfoot>
          </table>
        )}
      </TablaPlegable>
    </>
  );
}

// ---------- B. año completo: proyecciones frente al presupuesto ----------
type PropsAnio = { anio: Anio | null; cargando: boolean; err: string | null; onReintentar: () => void };

function Anual({ anio, tot, cargando, err, onReintentar }: PropsAnio & { tot: Estado<TotalMes[]> }) {
  const [ocultas, setOcultas] = useState<string[]>([]);
  const [base, setBase] = useState<"sin" | "con">("sin");
  const alternar = (nombre: string) => setOcultas((o) => (o.includes(nombre) ? o.filter((x) => x !== nombre) : [...o, nombre]));
  const conTerceros = tot.datos?.length ? ult([...tot.datos].sort((x, y) => x.periodo.localeCompare(y.periodo)))?.acumConTerceros ?? null : null;
  const anioTxt = anio?.periodos[0]?.slice(0, 4) ?? "";
  const e = err ?? tot.error;
  return (
    <div>
      <h3>B. Año {anioTxt || "en curso"}: proyecciones frente al presupuesto</h3>
      {e ? <Falla nombre="la proyección anual" msg={e} onReintentar={onReintentar} /> : cargando || !tot.datos ? <Cargando /> : !anio ? <p className="proy-sinmeta">Sin datos de proyección.</p> : (
        <>
          <div className="dash-kpis">
            <div className="dash-carta dash-kpi" title="Fuente: formato FO-GF-33, filas 57 a 59">
              <span>{NOM_PRES}</span>
              <strong><Monto v={anio.presTotalSin} /></strong><small>sin subsidios</small>
              <strong><Monto v={anio.presTotalCon} /></strong><small>con subsidios (ingresos)</small>
            </div>
            {anio.proys.map((p) => (
              <div key={p.clave} className="dash-carta dash-kpi">
                <span>{p.nombre}</span>
                <strong><Monto v={p.totalSin} /></strong><small>sin subsidios · {fmtPct1(ult(p.cumplSin) ?? null)} del presupuesto</small>
                <strong><Monto v={p.totalCon} /></strong><small>con subsidios (ingresos) · {fmtPct1(ult(p.cumplCon) ?? null)}</small>
              </div>
            ))}
            <div className="dash-carta dash-kpi">
              <span>Recaudo con terceros, acumulado del año ({NOM_ACT.toLowerCase()})</span>
              <strong><Monto v={conTerceros} /></strong><small>sin subsidios</small>
            </div>
          </div>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead><tr>
                <th>Proyección</th>
                <th className="num">Total sin subsidios</th><th className="num">Diferencia frente al presupuesto</th><th className="num">Cumplimiento anual</th>
                <th className="num">Total con subsidios (ingresos)</th><th className="num">Diferencia frente al presupuesto</th><th className="num">Cumplimiento anual</th>
              </tr></thead>
              <tbody>
                <tr className="proy-subtotal">
                  <td>{NOM_PRES}</td>
                  <td className="num" title={fmtExacto(anio.presTotalSin) || undefined}>{fm1(anio.presTotalSin)}</td><td className="num">—</td><td className="num">—</td>
                  <td className="num" title={fmtExacto(anio.presTotalCon) || undefined}>{fm1(anio.presTotalCon)}</td><td className="num">—</td><td className="num">—</td>
                </tr>
                {anio.proys.map((p) => (
                  <tr key={p.clave}>
                    <td>{p.nombre}</td>
                    <td className="num" title={fmtExacto(p.totalSin) || undefined}>{fm1(p.totalSin)}</td>
                    <td className="num" title={fmtExacto(p.difSin) || undefined}>{fm1(p.difSin)}</td>
                    <td className="num">{fmtPct1(ult(p.cumplSin) ?? null)}</td>
                    <td className="num" title={fmtExacto(p.totalCon) || undefined}>{fm1(p.totalCon)}</td>
                    <td className="num" title={fmtExacto(p.difCon) || undefined}>{fm1(p.difCon)}</td>
                    <td className="num">{fmtPct1(ult(p.cumplCon) ?? null)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="proy-leyenda">
            Meta principal del año: el presupuesto de la vigencia. Cumplimiento anual = acumulado de la proyección ÷ presupuesto de la misma base.
            Diferencia = total de la proyección − presupuesto. La proyección comercial certificada usa el recaudo real cargado de enero a septiembre.
          </p>
          <label className="proy-leyenda">Base del gráfico:{" "}
            <select value={base} onChange={(ev) => setBase(ev.target.value as "sin" | "con")}>
              <option value="sin">Sin subsidios</option><option value="con">Con subsidios (ingresos)</option>
            </select>
          </label>
          <LineasMensuales
            etiquetas={anio.periodos.map((p) => mesCorto(p).toLowerCase())}
            series={[
              ...anio.proys.map((p) => ({ nombre: p.nombre, color: p.color, valores: base === "sin" ? p.acumSin : p.acumCon })),
              { nombre: NOM_PRES, color: "#7a8a99", valores: base === "sin" ? anio.presAcumSin : anio.presAcumCon },
            ]}
            formatoValor={fm1}
            formatoEjeY={(v) => `${Math.round(v / 1e6).toLocaleString("es-CO")} M`}
            ocultas={ocultas}
            onToggle={alternar}
          />
        </>
      )}
    </div>
  );
}

// ---------- C. mes a mes y rutas ----------
function MesAMes({ anio, rutas, cum, anual, cargando, err, onReintentar }: PropsAnio & { rutas: Estado<RecaudoRuta[]>; cum: Estado<CumplimientoDia[]>; anual: Estado<AnualMes[]> }) {
  const tabla = useMemo(() => (rutas.datos && cum.datos ? armarTablaFO(rutas.datos, metaCertificadaPorMes(cum.datos, anual.datos ?? [])) : null), [rutas.datos, cum.datos, anual.datos]);
  const e = err ?? rutas.error ?? cum.error;
  const celda = (v: number | null, i: number, pct = false) => (
    <td key={i} className={`num ${anio?.tipos[i] === "proyectado" ? "proy-proy" : ""}`} title={pct ? undefined : fmtExacto(v) || undefined}>{pct ? fmtPct1(v) : mm1(v)}</td>
  );
  return (
    <div>
      <h3>C. Mes a mes de {anio?.periodos[0]?.slice(0, 4) ?? "2026"} y recaudo por rutas</h3>
      {e ? <Falla nombre="la proyección mes a mes" msg={e} onReintentar={onReintentar} /> : cargando || !rutas.datos || !cum.datos ? <Cargando /> : !anio ? <p className="proy-sinmeta">Sin datos de proyección.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead>
                <tr><th>Concepto</th>{anio.periodos.map((p) => <th key={p} className="num">{mesCorto(p)}</th>)}<th className="num">Total año</th></tr>
                <tr><th></th>{anio.tipos.map((t, i) => <th key={i} className="num">{t === "real" ? "Real" : "Proy."}</th>)}<th></th></tr>
              </thead>
              <tbody>
                {anio.proys.map((p) => (
                  <Fragment key={p.clave}>
                    <tr className="proy-total"><td colSpan={14}>{p.nombre}</td></tr>
                    <tr><td className="proy-rotulo">Sin subsidios</td>{p.sin.map((v, i) => celda(v, i))}<td className="num" title={fmtExacto(p.totalSin) || undefined}>{mm1(p.totalSin)}</td></tr>
                    <tr className="proy-acum"><td className="proy-rotulo">Acumulado sin subsidios</td>{p.acumSin.map((v, i) => celda(v, i))}<td className="num">{mm1(p.totalSin)}</td></tr>
                    <tr className="proy-acum"><td className="proy-rotulo">Cumplimiento anual (sin subsidios)</td>{p.cumplSin.map((v, i) => celda(v, i, true))}<td className="num">{fmtPct1(ult(p.cumplSin) ?? null)}</td></tr>
                    <tr><td className="proy-rotulo">Con subsidios (ingresos)</td>{p.con.map((v, i) => celda(v, i))}<td className="num" title={fmtExacto(p.totalCon) || undefined}>{mm1(p.totalCon)}</td></tr>
                    <tr className="proy-acum"><td className="proy-rotulo">Acumulado con subsidios</td>{p.acumCon.map((v, i) => celda(v, i))}<td className="num">{mm1(p.totalCon)}</td></tr>
                    <tr className="proy-acum"><td className="proy-rotulo">Cumplimiento anual (con subsidios)</td>{p.cumplCon.map((v, i) => celda(v, i, true))}<td className="num">{fmtPct1(ult(p.cumplCon) ?? null)}</td></tr>
                  </Fragment>
                ))}
                <tr className="proy-total"><td colSpan={14}>{NOM_PRES}</td></tr>
                <tr><td className="proy-rotulo">Sin subsidios</td>{anio.presSin.map((v, i) => celda(v, i))}<td className="num">{mm1(anio.presTotalSin)}</td></tr>
                <tr><td className="proy-rotulo">Con subsidios (ingresos)</td>{anio.presCon.map((v, i) => celda(v, i))}<td className="num">{mm1(anio.presTotalCon)}</td></tr>
              </tbody>
            </table>
          </div>
          <p className="proy-leyenda">Cifras en millones de pesos. Columnas sombreadas: meses proyectados. Cumplimiento anual = acumulado ÷ presupuesto anual de la misma base.</p>
          <h4>Recaudo por rutas (sin subsidios ni terceros, salvo la fila de terceros)</h4>
          {!tabla ? <p className="proy-sinmeta">Sin datos de recaudo por ruta.</p> : (
            <>
              <div className="dash-tabla-scroll">
                <table className="dash-tabla proy-tabla">
                  <thead>
                    <tr><th>Concepto</th>{tabla.periodos.map((p) => <th key={p} className="num">{mesCorto(p)}</th>)}<th className="num">Total</th></tr>
                    <tr><th></th>{tabla.estado.map((s, i) => <th key={i} className="num">{s === "real" ? "Real" : "Proy."}</th>)}<th></th></tr>
                  </thead>
                  <tbody>
                    {tabla.filas.map((f) => (
                      <tr key={f.clave} className={f.tipo === "ruta" ? "" : `proy-${f.tipo === "subtotal" ? "subtotal" : f.tipo}`}>
                        <td className="proy-rotulo">{f.etiqueta}</td>
                        {f.valores.map((v, i) => (
                          <td key={i} className={`num ${tabla.estado[i] === "proyectado" ? "proy-proy" : ""}`} title={fmtExacto(v) || undefined}>
                            {f.tipo === "meta" && v == null ? "Sin meta cargada" : mm1(v)}
                          </td>
                        ))}
                        <td className="num" title={fmtExacto(f.total) || undefined}>{f.tipo === "meta" ? "—" : mm1(f.total)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="proy-leyenda">Fuente: formato FO-GF-33. Millones de pesos. Meta de la proyección comercial certificada: septiembre según el cumplimiento diario; octubre a diciembre según la proyección anual.</p>
            </>
          )}
        </>
      )}
    </div>
  );
}

// ---------- D. subsidios ----------
function Subsidios({ anio, tot, cargando, err, onReintentar }: PropsAnio & { tot: Estado<TotalMes[]> }) {
  const filas = useMemo(() => {
    if (!anio || !tot.datos) return null;
    const T = new Map(tot.datos.map((x) => [x.periodo, x]));
    return anio.periodos.map((p, i) => {
      const t = T.get(p), s = anio.subsidio[i];
      return { p, tipo: anio.tipos[i], sub: s, origen: anio.subOrigen[i], rec: t?.conTerceros ?? null, ing: t?.conTerceros != null && s != null ? t.conTerceros + s : null };
    });
  }, [anio, tot.datos]);
  const suma = (k: "sub" | "rec" | "ing") => (filas && filas.every((f) => f[k] != null) ? filas.reduce((a, f) => a + (f[k] as number), 0) : null);
  return (
    <div>
      <h3>D. Subsidios (informativo)</h3>
      {err ? <Falla nombre="los subsidios" msg={err} onReintentar={onReintentar} /> : cargando || !filas ? <Cargando /> : filas.length === 0 ? <p className="proy-sinmeta">Sin datos de subsidios.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead><tr><th>Mes</th><th>Tipo</th><th className="num">Subsidios (déficit)</th><th>Origen del subsidio</th><th className="num">Recaudo (con terceros)</th><th className="num">Ingresos totales</th></tr></thead>
              <tbody>
                {filas.map((f) => (
                  <tr key={f.p} className={f.tipo === "real" ? "" : "proy-proy"}>
                    <td>{mesCorto(f.p)}</td><td>{f.tipo === "real" ? "Real" : "Proyectado"}</td>
                    <td className="num" title={fmtExacto(f.sub) || undefined}>{fm1(f.sub)}</td>
                    <td>{f.origen === "real" ? "Real (déficit de facturación)" : f.origen === "presupuesto FO" ? "Presupuesto FO" : "—"}</td>
                    <td className="num" title={fmtExacto(f.rec) || undefined}>{fm1(f.rec)}</td>
                    <td className="num" title={fmtExacto(f.ing) || undefined}>{fm1(f.ing)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="dash-fila-fuerte"><td colSpan={2}>Total año</td>
                  <td className="num" title={fmtExacto(suma("sub")) || undefined}>{fm1(suma("sub"))}</td><td></td>
                  <td className="num" title={fmtExacto(suma("rec")) || undefined}>{fm1(suma("rec"))}</td>
                  <td className="num" title={fmtExacto(suma("ing")) || undefined}>{fm1(suma("ing"))}</td></tr>
              </tfoot>
            </table>
          </div>
          <p className="proy-leyenda">
            Ingresos totales = recaudo (con terceros) + subsidios (déficit) — informativo. Subsidios reales: {fm1(anio?.subReal ?? null)};
            del presupuesto FO: {fm1(anio?.subFO ?? null)}. Los meses proyectados usan el subsidio del presupuesto FO, no un promedio.
          </p>
        </>
      )}
    </div>
  );
}

// ---------- E. escenarios de 60, 65, 70 y 75 mil millones ----------
function Escenarios({ anio, tot, cargando, err, onReintentar }: PropsAnio & { tot: Estado<TotalMes[]> }) {
  const esc = useMemo(() => (tot.datos ? armarEscenarios(tot.datos, anio) : null), [tot.datos, anio]);
  return (
    <div>
      <h3>E. Escenarios de meta anual (referencia)</h3>
      {err ? <Falla nombre="los escenarios" msg={err} onReintentar={onReintentar} /> : cargando || !tot.datos ? <Cargando /> : !esc ? <p className="proy-sinmeta">Sin meses restantes por proyectar.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead><tr>
                <th>Meta del año</th>
                <th className="num">Recaudo requerido por mes, si la meta es de recaudo</th><th className="num">Brecha (requerido − proyectado; negativo = meta cubierta)</th>
                <th className="num">Recaudo requerido por mes, si la meta es de ingresos</th><th className="num">Brecha (requerido − proyectado; negativo = meta cubierta)</th>
              </tr></thead>
              <tbody>
                {esc.filas.map((f) => (
                  <tr key={f.meta}>
                    <td>{fm1(f.meta)}</td>
                    <td className="num" title={fmtExacto(f.reqRecaudo) || undefined}>{fm1(f.reqRecaudo)}</td>
                    <td className="num" title={fmtExacto(f.difRecaudo) || undefined}>{f.difRecaudo == null ? "—" : `${f.difRecaudo >= 0 ? "+" : "−"}${fm1(Math.abs(f.difRecaudo))}`}</td>
                    <td className="num" title={fmtExacto(f.reqIngresos) || undefined}>{fm1(f.reqIngresos)}</td>
                    <td className="num" title={fmtExacto(f.difIngresos) || undefined}>{f.difIngresos == null ? "—" : `${f.difIngresos >= 0 ? "+" : "−"}${fm1(Math.abs(f.difIngresos))}`}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="proy-leyenda">
            Meses restantes: {esc.restantes} (después de {mesCorto(esc.periodoCorte)}). Recaudo con terceros acumulado a {mesCorto(esc.periodoCorte)}: {fm1(esc.acumConTerceros)}.
            Subsidios del año (reales + presupuesto FO): {fm1(esc.subAnio)}. Promedio mensual proyectado de los meses restantes ({NOM_ACT.toLowerCase()}, con terceros): {fm1(esc.promProyectado)}.
            Si la meta es de ingresos, se descuentan los subsidios del año antes de repartir. En la brecha, un valor positivo indica que se exige más de lo proyectado y uno negativo que la proyección ya cubre la meta.
          </p>
        </>
      )}
    </div>
  );
}
