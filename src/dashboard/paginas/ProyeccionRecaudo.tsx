import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { LineasPorDia, TablaPlegable } from "../graficas";
import { LineasMensuales } from "../LineasMensuales";
import { etiquetaPeriodo } from "../formato";
import {
  armarSubsidios, armarTablaFO, comoAnualMes, comoCumplimientoDia, comoDiaOrigen, comoRecaudoRuta, comoSubsidioMes, comoTotalMes,
  diasDelMes, fm1, fmtExacto, fmtPct1, marcaDia, mesCorto, metaCertificadaPorMes, mm1, periodoEnCurso, resumenMes, semaforo,
  type AnualMes, type CumplimientoDia, type DiaOrigen, type RecaudoRuta, type SubsidioMes, type TotalMes,
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

  return (
    <section className="proy-seccion" aria-label="Proyección y cumplimiento">
      <h2>Proyección y cumplimiento del recaudo</h2>
      <p className="proy-sub">Cifras sin terceros salvo donde se indique. Los subsidios no entran en el cumplimiento ni en el recaudo.</p>
      <MesEnCurso cum={cum} diario={diario} onReintentar={reintentar} />
      <Anual anual={anual} tot={tot} onReintentar={reintentar} />
      <FormatoFO rutas={rutas} cum={cum} anual={anual} onReintentar={reintentar} />
      <Subsidios tot={tot} subs={subs} onReintentar={reintentar} />
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
      <h3>A. Mes en curso{sel?.periodo ? ` — ${etiquetaPeriodo(sel.periodo)}` : ""}</h3>
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
        <div className="dash-carta dash-kpi"><span>Meta certificada acumulada</span><strong>{r.metaCertAcum == null ? <span className="proy-sinmeta">Sin meta cargada</span> : <Monto v={r.metaCertAcum} />}</strong></div>
        <div className="dash-carta dash-kpi"><span>Meta propia acumulada</span><strong>{r.metaPropiaAcum == null ? <span className="proy-sinmeta">Sin meta cargada</span> : <Monto v={r.metaPropiaAcum} />}</strong></div>
        <div className="dash-carta dash-kpi"><span>Cumplimiento (certificada)</span><strong><Sem pct={r.cumplCert} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Cumplimiento (propia)</span><strong><Sem pct={r.cumplPropia} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Falta para la meta del mes (certificada)</span><strong><Monto v={r.faltaCert} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Falta para la meta del mes (propia)</span><strong><Monto v={r.faltaPropia} /></strong></div>
        <div className="dash-carta dash-kpi"><span>Cierre corregido con avance</span><strong><Monto v={r.cierre} /></strong></div>
        <div className={`dash-carta dash-kpi ${r.difCierreCert != null && r.difCierreCert < 0 ? "dash-kpi-mal" : ""}`}><span>Cierre frente a meta certificada del mes</span><strong><Monto v={r.difCierreCert} /></strong></div>
        <div className={`dash-carta dash-kpi ${r.difCierrePropia != null && r.difCierrePropia < 0 ? "dash-kpi-mal" : ""}`}><span>Cierre frente a meta propia del mes</span><strong><Monto v={r.difCierrePropia} /></strong></div>
      </div>
      {sinMeta ? null : (
        <LineasPorDia
          series={[
            { nombre: "Real acumulado", color: "#0E7C86", valores: porDia((d) => d.real_acum, r.ultDia) },
            { nombre: "Meta certificada acumulada", color: "#0a2540", valores: porDia((d) => d.meta_certificada_acum) },
            { nombre: "Meta propia acumulada", color: "#c27a00", valores: porDia((d) => d.meta_propia_acum) },
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
            <thead><tr><th>Fecha</th><th>Tipo de día</th><th className="num">Exigencia diaria certificada</th><th className="num">Exigencia diaria propia</th></tr></thead>
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

// ---------- B. año ----------
function Anual({ anual, tot, onReintentar }: { anual: Estado<AnualMes[]>; tot: Estado<TotalMes[]>; onReintentar: () => void }) {
  const [ocultas, setOcultas] = useState<string[]>([]);
  const alternar = (nombre: string) => setOcultas((o) => (o.includes(nombre) ? o.filter((x) => x !== nombre) : [...o, nombre]));
  const err = anual.error ?? tot.error;
  const a = anual.datos ? [...anual.datos].sort((x, y) => x.periodo.localeCompare(y.periodo)) : null;
  const t = tot.datos ? [...tot.datos].sort((x, y) => x.periodo.localeCompare(y.periodo)) : null;
  const anio = a?.[0]?.periodo.slice(0, 4) ?? "";
  return (
    <div>
      <h3>B. Año {anio || "en curso"}: real y proyectado</h3>
      {err ? <Falla nombre="la proyección anual" msg={err} onReintentar={onReintentar} /> : !a || !t ? <Cargando /> : a.length === 0 ? <p className="proy-sinmeta">Sin datos de proyección.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead><tr>
                <th>Mes</th><th>Tipo</th><th className="num">Propia</th><th className="num">Propia corregida</th><th className="num">Certificada</th>
                <th className="num">Acum. propia</th><th className="num">Acum. corregida</th><th className="num">Acum. certificada</th><th className="num">Con terceros</th>
              </tr></thead>
              <tbody>
                {a.map((m) => { const c = t.find((x) => x.periodo === m.periodo); return (
                  <tr key={m.periodo} className={m.tipo === "real" ? "" : "proy-proy"}>
                    <td>{mesCorto(m.periodo)}</td><td>{m.tipo === "real" ? "Real" : "Proyectado"}</td>
                    <td className="num" title={fmtExacto(m.propia) || undefined}>{fm1(m.propia)}</td>
                    <td className="num" title={fmtExacto(m.corregida) || undefined}>{fm1(m.corregida)}</td>
                    <td className="num" title={fmtExacto(m.certificada) || undefined}>{m.certificada == null ? "—" : fm1(m.certificada)}</td>
                    <td className="num" title={fmtExacto(m.acumPropia) || undefined}>{fm1(m.acumPropia)}</td>
                    <td className="num" title={fmtExacto(m.acumCorregida) || undefined}>{fm1(m.acumCorregida)}</td>
                    <td className="num" title={fmtExacto(m.acumCertificada) || undefined}>{m.acumCertificada == null ? "—" : fm1(m.acumCertificada)}</td>
                    <td className="num" title={fmtExacto(c?.conTerceros ?? null) || undefined}>{fm1(c?.conTerceros ?? null)}</td>
                  </tr>); })}
              </tbody>
            </table>
          </div>
          <p className="proy-leyenda">Filas sombreadas: meses proyectados. «Con terceros» viene de la proyección total y se muestra aparte.</p>
          <LineasMensuales
            etiquetas={a.map((m) => mesCorto(m.periodo).toLowerCase())}
            series={[
              { nombre: "Acumulado propio", color: "#0E7C86", valores: a.map((m) => m.acumPropia) },
              { nombre: "Acumulado propio corregido", color: "#c27a00", valores: a.map((m) => m.acumCorregida) },
              { nombre: "Acumulado certificado", color: "#0a2540", valores: a.map((m) => m.acumCertificada) },
              { nombre: "Acumulado con terceros", color: "#7a8a99", valores: t.map((m) => m.acumConTerceros) },
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

// ---------- C. FO-GF-33 ----------
function FormatoFO({ rutas, cum, anual, onReintentar }: { rutas: Estado<RecaudoRuta[]>; cum: Estado<CumplimientoDia[]>; anual: Estado<AnualMes[]>; onReintentar: () => void }) {
  const err = rutas.error ?? cum.error ?? anual.error;
  const tabla = useMemo(() => (rutas.datos && cum.datos ? armarTablaFO(rutas.datos, metaCertificadaPorMes(cum.datos, anual.datos ?? [])) : null), [rutas.datos, cum.datos, anual.datos]);
  return (
    <div>
      <h3>C. Formato FO-GF-33</h3>
      {err ? <Falla nombre="el formato FO-GF-33" msg={err} onReintentar={onReintentar} /> : !rutas.datos || !cum.datos || !anual.datos ? <Cargando /> : !tabla ? <p className="proy-sinmeta">Sin datos de recaudo por ruta.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead>
                <tr><th>Concepto</th>{tabla.periodos.map((p) => <th key={p} className="num">{mesCorto(p)}</th>)}<th className="num">Total</th></tr>
                <tr><th></th>{tabla.estado.map((e, i) => <th key={i} className="num">{e === "real" ? "Real" : "Proy."}</th>)}<th></th></tr>
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
          <p className="proy-leyenda">Cifras en millones de pesos. Columnas sombreadas: meses proyectados. Meta certificada: septiembre según el cumplimiento diario; octubre a diciembre según la proyección anual.</p>
        </>
      )}
    </div>
  );
}

// ---------- D. subsidios ----------
function Subsidios({ tot, subs, onReintentar }: { tot: Estado<TotalMes[]>; subs: Estado<SubsidioMes[]>; onReintentar: () => void }) {
  const err = tot.error ?? subs.error;
  const filas = useMemo(() => (tot.datos && subs.datos ? armarSubsidios(tot.datos, subs.datos) : null), [tot.datos, subs.datos]);
  return (
    <div>
      <h3>D. Subsidios (informativo)</h3>
      {err ? <Falla nombre="los subsidios" msg={err} onReintentar={onReintentar} /> : !filas ? <Cargando /> : filas.length === 0 ? <p className="proy-sinmeta">Sin datos de subsidios en los meses con recaudo real.</p> : (
        <>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla proy-tabla">
              <thead><tr><th>Mes</th><th className="num">Recaudo (con terceros)</th><th className="num">Subsidios (déficit)</th><th className="num">Ingresos totales</th></tr></thead>
              <tbody>
                {filas.map((f) => (
                  <tr key={f.periodo}>
                    <td>{mesCorto(f.periodo)}</td>
                    <td className="num" title={fmtExacto(f.recaudoConTerceros) || undefined}>{fm1(f.recaudoConTerceros)}</td>
                    <td className="num" title={fmtExacto(f.deficit) || undefined}>{fm1(f.deficit)}</td>
                    <td className="num" title={fmtExacto(f.ingresosTotales) || undefined}>{fm1(f.ingresosTotales)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="proy-leyenda">Ingresos totales = recaudo (con terceros) + subsidios (déficit) — informativo. Solo meses con dato real de subsidios.</p>
        </>
      )}
    </div>
  );
}
