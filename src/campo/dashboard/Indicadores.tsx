import { useEffect, useMemo, useState } from "react";
import { apiRev, textoError, type FormularioRev, type IndicadoresResp } from "./apiRevision";
import { FILTROS_INICIALES, aFiltrosServidor, filtrosLegibles, rangoInvalido, type FiltrosUI, type Periodo } from "./filtros";
import { fmtDia, fmtDuracion, fmtMiles } from "./formatoRevision";
import { pasoBonito } from "../../tecnica/graficas";

// Indicadores sencillos (calculados al momento por la base, sin tablas ni copias). SIN juicios de cumplimiento: no hay metas, semáforos ni «a tiempo/tarde». Siempre con el denominador
// y la fecha de corte visibles. «Revisión» = el primer cambio de estado o vínculo de duplicado de cada reporte (decisión de David); ocultar no cuenta.
export function Indicadores({ def }: { def: FormularioRev }) {
  const [f, setF] = useState<FiltrosUI>({ ...FILTROS_INICIALES, periodo: "30d" });
  const [r, setR] = useState<IndicadoresResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const servidor = useMemo(() => aFiltrosServidor(f), [f.tipo, f.grupo, f.estado, f.periodo, f.desde, f.hasta, f.riesgo, f.ocultos, f.resultado]);   // eslint-disable-line react-hooks/exhaustive-deps
  const invalido = rangoInvalido(f);
  useEffect(() => {
    if (invalido) return;
    let vivo = true; setCargando(true); setError(null);
    apiRev.indicadores(servidor).then((x) => { if (vivo) setR(x); }).catch((e) => { if (vivo) setError(textoError(e).texto); }).finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
  }, [servidor, invalido]);
  const tipos = def.grupos.filter((g) => !f.grupo || g.codigo === f.grupo).flatMap((g) => g.tipos);
  const set = <K extends keyof FiltrosUI>(k: K, v: FiltrosUI[K]) => setF((x) => ({ ...x, [k]: v }));
  const maxTipo = Math.max(1, ...(r?.por_tipo.map((x) => x.n) ?? [1]));
  const maxEst = Math.max(1, ...(r?.por_estado.map((x) => x.n) ?? [1]));
  return (
    <section className="rv-seccion" aria-labelledby="rv-ind-tit">
      <div><h2 id="rv-ind-tit">Indicadores</h2><p className="rv-sub">Cifras calculadas en el momento con los mismos filtros de la lista. No miden cumplimiento: no hay metas ni semáforos.</p></div>
      <div className="rv-filtros abierto"><div className="rv-filtros-cuerpo">
        <label className="rv-campo">Fecha de registro<select value={f.periodo} onChange={(e) => set("periodo", e.target.value as Periodo)}>
          <option value="30d">Últimos 30 días</option><option value="7d">Últimos 7 días</option><option value="hoy">Hoy</option><option value="mes">Mes en curso</option><option value="rango">Rango de fechas…</option><option value="todo">Todas las fechas</option></select></label>
        {f.periodo === "rango" ? <>
          <label className="rv-campo">Desde<input type="date" value={f.desde} onChange={(e) => set("desde", e.target.value)} /></label>
          <label className="rv-campo">Hasta<input type="date" value={f.hasta} onChange={(e) => set("hasta", e.target.value)} /></label></> : null}
        <label className="rv-campo">Grupo<select value={f.grupo} onChange={(e) => setF((x) => ({ ...x, grupo: e.target.value, tipo: "" }))}><option value="">Todos</option>{def.grupos.map((g) => <option key={g.codigo} value={g.codigo}>{g.nombre}</option>)}</select></label>
        <label className="rv-campo">Tipo<select value={f.tipo} onChange={(e) => set("tipo", e.target.value)}><option value="">Todos</option>{tipos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}</select></label>
        <label className="rv-campo">Estado<select value={f.estado} onChange={(e) => set("estado", e.target.value)}><option value="">Todos</option>{(def.estados ?? []).map((e) => <option key={e.codigo} value={e.codigo}>{e.nombre}</option>)}</select></label>
        <label className="rv-campo">Riesgo inmediato<select value={f.riesgo} onChange={(e) => set("riesgo", e.target.value as FiltrosUI["riesgo"])}><option value="">Todos</option><option value="si">Solo con riesgo</option><option value="no">Sin riesgo</option></select></label>
      </div></div>
      {invalido ? <p className="rv-error" role="alert">La fecha «Desde» no puede ser posterior a «Hasta».</p> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {cargando && !r ? <p className="rv-sub" role="status">Calculando…</p> : null}
      {r ? (
        <div aria-busy={cargando}>
          <p className="rv-activos">Base de las cifras: {fmtMiles(r.total)} {r.total === 1 ? "reporte" : "reportes"} · {filtrosLegibles(f, def).join(" · ")} · Corte: {r.corte} (hora de Bogotá)</p>
          <div className="rv-tarjetas">
            <Tarjeta titulo="Reportes" valor={fmtMiles(r.total)} nota={`de ${fmtMiles(r.visibles)} no ocultos con este filtro`} />
            <Tarjeta titulo="Ocultos (aparte)" valor={fmtMiles(r.ocultos)} nota="No cuentan en las demás cifras" />
            <Tarjeta titulo="Sin revisar" valor={fmtMiles(r.revision.sin_revisar)} nota={`de ${fmtMiles(r.total)} reportes`} />
            <Tarjeta titulo="Revisados" valor={fmtMiles(r.revision.revisados)} nota={`de ${fmtMiles(r.total)} reportes`} />
          </div>
          <h3 className="rv-h3">Tiempo hasta la revisión</h3>
          <p className="rv-sub">Desde que se registra el reporte hasta su primer cambio de estado o vínculo de duplicado, entre los {fmtMiles(r.revision.revisados)} reportes revisados. Ocultar un reporte no cuenta como revisión.</p>
          <div className="rv-tarjetas">
            <Tarjeta titulo="Mediana" valor={fmtDuracion(r.revision.mediana_segundos)} nota={`de ${fmtMiles(r.revision.revisados)} revisados`} />
            <Tarjeta titulo="Promedio" valor={fmtDuracion(r.revision.promedio_segundos)} nota={`de ${fmtMiles(r.revision.revisados)} revisados`} />
            <Tarjeta titulo="Percentil 90" valor={fmtDuracion(r.revision.p90_segundos)} nota="el 90 % se revisó en este tiempo o menos" />
          </div>
          <h3 className="rv-h3">Reportes por día</h3>
          <GraficaDias datos={r.por_dia} />
          {r.serie_recortada ? <p className="rv-sub">La serie muestra solo los últimos 1.000 días del rango.</p> : null}
          <div className="rv-dos">
            <div><h3 className="rv-h3">Por tipo</h3>
              {r.por_tipo.length === 0 ? <p className="rv-sub">Sin reportes.</p> : <ul className="rv-barras">{r.por_tipo.map((x) => <li key={x.tipo.codigo}><span>{x.tipo.nombre}<small className="rv-tenue"> · {x.grupo.nombre}</small></span><span className="rv-barra-v"><i style={{ width: `${(x.n / maxTipo) * 100}%` }} />{fmtMiles(x.n)}</span></li>)}</ul>}</div>
            <div><h3 className="rv-h3">Por estado</h3>
              {r.por_estado.length === 0 ? <p className="rv-sub">Sin reportes.</p> : <ul className="rv-barras">{r.por_estado.map((x) => <li key={x.estado}><span>{x.nombre}</span><span className="rv-barra-v"><i style={{ width: `${(x.n / maxEst) * 100}%` }} />{fmtMiles(x.n)}</span></li>)}</ul>}</div>
          </div>
        </div>
      ) : null}
    </section>
  );
}

const Tarjeta = ({ titulo, valor, nota }: { titulo: string; valor: string; nota: string }) => <div className="rv-tarjeta"><span className="rv-tarjeta-t">{titulo}</span><span className="rv-tarjeta-v">{valor}</span><span className="rv-tenue">{nota}</span></div>;

/** Barras por día (SVG propio, sin librerías), con una tabla alternativa plegable con los mismos datos. */
function GraficaDias({ datos }: { datos: { dia: string; n: number }[] }) {
  if (datos.length === 0) return <p className="rv-sub">Sin días en el rango.</p>;
  const W = 760, H = 180, mi = 40, mb = 26, ms = 10, md = 8;
  const max = Math.max(1, ...datos.map((d) => d.n)); const paso = pasoBonito(max, 4); const tope = Math.ceil(max / paso) * paso || 1;
  const ancho = (W - mi - md) / datos.length; const y = (v: number) => H - mb - (v / tope) * (H - mb - ms);
  const ticks = Array.from({ length: Math.floor(tope / paso) + 1 }, (_, i) => i * paso);
  const cada = Math.max(1, Math.ceil(datos.length / 8));
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} className="rv-grafica" role="img" aria-label={`Reportes por día: ${datos.length} días, máximo ${max} en un día`}>
        {ticks.map((t) => <g key={t}><line x1={mi} x2={W - md} y1={y(t)} y2={y(t)} stroke="#dde5ea" /><text x={mi - 6} y={y(t) + 4} textAnchor="end" fontSize="11" fill="#52626f">{fmtMiles(t)}</text></g>)}
        {datos.map((d, i) => <rect key={d.dia} x={mi + i * ancho + 1} y={y(d.n)} width={Math.max(1, ancho - 2)} height={H - mb - y(d.n)} fill="#0f766e"><title>{`${fmtDia(d.dia)}: ${fmtMiles(d.n)}`}</title></rect>)}
        {datos.map((d, i) => (i % cada === 0 ? <text key={`x${d.dia}`} x={mi + i * ancho + ancho / 2} y={H - 8} textAnchor="middle" fontSize="11" fill="#52626f">{fmtDia(d.dia).slice(0, 5)}</text> : null))}
      </svg>
      <details className="rv-tabla-alt"><summary>Ver los datos en tabla</summary>
        <table><thead><tr><th>Día</th><th className="rv-der">Reportes</th></tr></thead><tbody>{datos.map((d) => <tr key={d.dia}><td>{fmtDia(d.dia)}</td><td className="rv-der">{fmtMiles(d.n)}</td></tr>)}</tbody></table>
      </details>
    </div>
  );
}
