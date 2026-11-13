import { useCallback, useEffect, useMemo, useState } from "react";
import { apiSup, textoError, type Indicadores as IndT, type Resumen as ResumenT } from "./api";
import { aServidor, ErrorCaja, FILTROS_INICIALES, FiltrosSup, rangoInvalido, ROT_TIPO, type EstadoFiltros } from "./comun";
import type { FormularioAseo } from "../tipos";

// «Indicadores» del primer corte, con filtros de periodo, actividad, modalidad, servicio, turno, barrio y auditor. Conteos y porcentajes con barras de ancho proporcional y su valor escrito (no solo color).
const pct = (n: number, d: number) => (d > 0 ? `${((n / d) * 100).toLocaleString("es-CO", { maximumFractionDigits: 1 })} %` : "—");
const num = (n: number) => n.toLocaleString("es-CO");
function Barra({ nombre, n, total, tono }: { nombre: string; n: number; total: number; tono: string }) {
  return (<div className="as-barra"><span className="as-barra-n">{nombre}</span><span className="as-barra-caja" aria-hidden="true"><span className={`as-barra-rel as-${tono}`} style={{ width: total > 0 ? `${Math.max((n / total) * 100, n > 0 ? 2 : 0)}%` : "0%" }} /></span><span className="as-barra-v">{num(n)} · {pct(n, total)}</span></div>);
}
export function Indicadores({ def, cat }: { def: FormularioAseo; cat: Pick<ResumenT, "turnos" | "auditores"> }) {
  const [f, setF] = useState<EstadoFiltros>({ ...FILTROS_INICIALES, ocultos: "no" });
  const [d, setD] = useState<IndT | null>(null); const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const invalido = rangoInvalido(f); const filtros = useMemo(() => ({ ...aServidor(f), nc: undefined, ocultos: "no" }), [f]);
  const cargar = useCallback(async () => { if (invalido) return; setD(null); setError(null); try { setD(await apiSup.indicadores(filtros)); } catch (e) { setError(textoError(e)); } }, [filtros, invalido]);
  useEffect(() => { void cargar(); }, [cargar]);
  const inc = d?.incidencia, ti = d ? d.incidencia.si + d.incidencia.no + d.incidencia.parcial : 0, nc = d?.no_conformes;
  return (
    <section className="td-seccion" aria-labelledby="as-ind-tit">
      <div className="td-cab"><div><h2 id="as-ind-tit">Indicadores</h2><p className="td-sub">Las auditorías ocultas no cuentan. «Rutas del plan» es el total de rutas activas de la actividad y modalidad elegidas (no depende de barrio, turno ni auditor).</p></div></div>
      <FiltrosSup idp="ind" def={def} turnos={cat.turnos} auditores={cat.auditores} valor={f} onCambio={setF} conNc={false} conOcultas={false} />
      {invalido ? <p className="td-error" role="alert">La fecha «Desde» no puede ser posterior a «Hasta».</p> : null}
      {error ? <ErrorCaja error={error} onReintentar={() => void cargar()} /> : null}
      {!d && !error ? <p className="td-sub" role="status">Calculando…</p> : null}
      {d && inc && nc ? <>
        <div className="td-cajitas">
          <div className="td-cajita"><strong data-testid="ind-auditorias">{num(d.auditorias)}</strong><span>Auditorías realizadas</span></div>
          <div className="td-cajita"><strong>{num(d.rutas_auditadas)} de {num(d.rutas_plan)}</strong><span>Rutas auditadas frente al plan ({pct(d.rutas_auditadas, d.rutas_plan)})</span></div>
          <div className="td-cajita"><strong>{num(nc.auditorias)}</strong><span>Con no conformidad ({pct(nc.auditorias, d.auditorias)})</span></div>
          <div className="td-cajita"><strong>{num(nc.pendientes)} / {num(nc.revisadas)}</strong><span>No conformidades pendientes / revisadas</span></div>
        </div>
        <div className="as-grupo"><h3 className="td-h3">Incidencia</h3>
          <Barra nombre="Sí (se realizó)" n={inc.si} total={ti} tono="ok" /><Barra nombre="Parcial" n={inc.parcial} total={ti} tono="aviso" /><Barra nombre="No se realizó" n={inc.no} total={ti} tono="mal" /></div>
        <div className="as-grupo"><h3 className="td-h3">No conformidades por tipo</h3>
          <p className="td-sub">Cada auditoría cuenta una vez por tipo; una misma auditoría puede tener varios.</p>
          {(Object.keys(ROT_TIPO) as (keyof typeof ROT_TIPO)[]).map((t) => <Barra key={t} nombre={ROT_TIPO[t]} n={nc.por_tipo[t]} total={d.auditorias} tono="mal" />)}</div>
        <div className="as-grupo"><h3 className="td-h3">Marcas del registro</h3>
          <p className="td-sub">Las marcas avisan; no impiden nada.</p>
          <Barra nombre="Lejos de la ruta" n={d.marcas.lejos_de_ruta} total={d.auditorias} tono="aviso" /><Barra nombre="Fuera de horario" n={d.marcas.fuera_de_horario} total={d.auditorias} tono="aviso" />
          <Barra nombre="Fuera de zona" n={d.marcas.fuera_de_zona} total={d.auditorias} tono="aviso" /><Barra nombre="No programada ese día" n={d.marcas.no_programada_hoy} total={d.auditorias} tono="aviso" /><Barra nombre="Sin trazado" n={d.marcas.sin_trazado} total={d.auditorias} tono="aviso" /></div>
      </> : null}
    </section>
  );
}
