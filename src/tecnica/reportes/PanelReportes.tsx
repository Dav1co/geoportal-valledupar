import { useEffect, useRef, useState } from "react";
import "./reportes.css";
import { ErrorTec } from "../apiTecnica";
import type { DefReporte, FiltroReporte } from "./catalogo";
import { errorPeriodo, hoyBogota, primeroDelMes, type Pedido } from "./armar";
import { fuenteDe, opcionesDistribucion, type Opcion } from "./apiReportes";
import { ejecutarReporte, guardarArchivo, ReporteCancelado, type Progreso } from "./ejecutar";

// La MISMA tarjeta para todos los reportes del Dashboard PTAP («Reportes») y las descargas del Dashboard distribución («Descargas»): nombre, una línea de
// descripción y, al abrirla, el periodo (hasta un año), el filtro que aplique (planta, sector o tipo de activo), «Incluir los excluidos / ocultos» y los
// botones «Descargar Excel» y «Descargar CSV». Una tarjeta abierta a la vez; el periodo y los filtros se conservan al pasar de una a otra.

const nf = (n: number) => n.toLocaleString("es-CO");
const ROTULO: Record<FiltroReporte, { rotulo: string; todos: string }> = {
  planta: { rotulo: "Planta", todos: "Todas las plantas" }, sector: { rotulo: "Sector", todos: "Todos los sectores" }, tipo_activo: { rotulo: "Tipo de activo", todos: "Todos los tipos" },
};
type Msg = { tipo: "ok" | "info" | "error"; t: string };

export function PanelReportes({ titulo, ayuda, reportes, plantas, sinPermiso, prefijo }: {
  titulo: string; ayuda: string; reportes: DefReporte[]; plantas?: Opcion[]; sinPermiso: string; prefijo: string;
}) {
  const [abierta, setAbierta] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [desde, setDesde] = useState(primeroDelMes);
  const [hasta, setHasta] = useState(hoyBogota);
  const [filtro, setFiltro] = useState<Partial<Record<FiltroReporte, string>>>({});
  const [ocultos, setOcultos] = useState(false);
  const [opciones, setOpciones] = useState<{ sector: Opcion[]; tipo_activo: Opcion[] } | null>(null);
  const [opcionesError, setOpcionesError] = useState(false);
  const pideOpciones = reportes.some((r) => r.filtros.includes("sector") || r.filtros.includes("tipo_activo"));
  useEffect(() => {
    if (!pideOpciones) return;
    let vivo = true;
    opcionesDistribucion().then((o) => { if (vivo) setOpciones({ sector: Array.isArray(o.sectores) ? o.sectores : [], tipo_activo: Array.isArray(o.tipos_activo) ? o.tipos_activo : [] }); })
      .catch(() => { if (vivo) setOpcionesError(true); });
    return () => { vivo = false; };
  }, [pideOpciones]);
  const listas: Record<FiltroReporte, Opcion[]> = { planta: plantas ?? [], sector: opciones?.sector ?? [], tipo_activo: opciones?.tipo_activo ?? [] };
  return (
    <section className="td-seccion rep" aria-label={titulo}>
      <div className="td-cab"><div><h2>{titulo}</h2><p className="td-sub">{ayuda}</p></div></div>
      <div className="rep-rejilla">
        {reportes.map((def) => (
          <TarjetaReporte key={def.clave} def={def} abierta={abierta === def.clave} bloqueada={ocupado && abierta !== def.clave} prefijo={prefijo}
            onAbrir={() => setAbierta(abierta === def.clave ? null : def.clave)} onOcupado={setOcupado} sinPermiso={sinPermiso}
            desde={desde} hasta={hasta} setDesde={setDesde} setHasta={setHasta} ocultos={ocultos} setOcultos={setOcultos}
            filtro={filtro} setFiltro={(k, v) => setFiltro((f) => ({ ...f, [k]: v }))} listas={listas} opcionesError={opcionesError} />
        ))}
      </div>
    </section>
  );
}

function TarjetaReporte(p: {
  def: DefReporte; abierta: boolean; bloqueada: boolean; prefijo: string; onAbrir: () => void; onOcupado: (b: boolean) => void; sinPermiso: string;
  desde: string; hasta: string; setDesde: (v: string) => void; setHasta: (v: string) => void; ocultos: boolean; setOcultos: (v: boolean) => void;
  filtro: Partial<Record<FiltroReporte, string>>; setFiltro: (k: FiltroReporte, v: string) => void; listas: Record<FiltroReporte, Opcion[]>; opcionesError: boolean;
}) {
  const { def } = p;
  const [progreso, setProgreso] = useState<Progreso | null>(null);
  const [msg, setMsg] = useState<Msg | null>(null);
  const ctl = useRef<AbortController | null>(null);
  const caja = useRef<HTMLElement>(null);
  const id = `${p.prefijo}-${def.clave}`;
  useEffect(() => { if (p.abierta) caja.current?.scrollIntoView?.({ block: "nearest", behavior: "smooth" }); }, [p.abierta]);
  useEffect(() => () => ctl.current?.abort(), []);

  async function descargar(formato: "xlsx" | "csv") {
    if (def.periodo) { const e = errorPeriodo(p.desde, p.hasta); if (e) { setMsg({ tipo: "error", t: e }); return; } }
    const pedido: Pedido = { formato, incluir_ocultos: !!def.ocultos && p.ocultos };
    if (def.periodo) { pedido.desde = p.desde; pedido.hasta = p.hasta; }
    const filtrosTexto: string[] = [];
    for (const k of def.filtros) {
      const v = p.filtro[k]; if (!v) continue;
      pedido[k] = v;
      filtrosTexto.push(`${ROTULO[k].rotulo}: ${p.listas[k].find((o) => o.codigo === v)?.nombre ?? v}`);
    }
    const c = new AbortController(); ctl.current = c;
    setMsg(null); p.onOcupado(true);
    try {
      const r = await ejecutarReporte({ def, fuente: fuenteDe(def), pedido, filtrosTexto, onProgreso: setProgreso, senal: c.signal });
      if (!r.blob) setMsg({ tipo: "info", t: "No hay registros con esos filtros. No se generó el archivo." });
      else { guardarArchivo(r.nombre, r.blob); setMsg({ tipo: "ok", t: `Listo: ${nf(r.filas)} fila${r.filas === 1 ? "" : "s"} en ${formato === "xlsx" ? "Excel" : "CSV"}. La descarga quedó registrada.` }); }
    } catch (e) {
      setMsg(e instanceof ReporteCancelado ? { tipo: "info", t: "Descarga cancelada. No se generó el archivo." }
        : { tipo: "error", t: e instanceof ErrorTec && e.tipo === "permiso" ? p.sinPermiso : e instanceof Error ? e.message : "No se pudo completar la descarga." });
    } finally { setProgreso(null); p.onOcupado(false); ctl.current = null; }
  }

  const trabajando = progreso !== null;
  return (
    <article ref={caja} className={`rep-tarjeta${p.abierta ? " rep-abierta" : ""}`} data-reporte={def.clave}>
      <button type="button" className="rep-cab" aria-expanded={p.abierta} aria-controls={`${id}-form`} disabled={p.bloqueada} onClick={p.onAbrir}>
        <span className="rep-ini" aria-hidden="true">{def.titulo.charAt(0).toUpperCase()}</span>
        <span className="rep-txt"><span className="rep-nom">{def.titulo}</span><span className="rep-desc">{def.descripcion}</span></span>
      </button>
      {p.abierta ? (
        <div className="rep-form" id={`${id}-form`}>
          <div className="rep-campos">
            {def.periodo ? <>
              <div className="td-campo"><label htmlFor={`${id}-desde`}>Desde</label>
                <input id={`${id}-desde`} type="date" value={p.desde} max={p.hasta || undefined} disabled={trabajando} onChange={(e) => p.setDesde(e.target.value)} /></div>
              <div className="td-campo"><label htmlFor={`${id}-hasta`}>Hasta</label>
                <input id={`${id}-hasta`} type="date" value={p.hasta} min={p.desde || undefined} disabled={trabajando} onChange={(e) => p.setHasta(e.target.value)} /></div>
            </> : null}
            {def.filtros.map((k) => (
              <div key={k} className="td-campo"><label htmlFor={`${id}-${k}`}>{ROTULO[k].rotulo}</label>
                <select id={`${id}-${k}`} value={p.filtro[k] ?? ""} disabled={trabajando} onChange={(e) => p.setFiltro(k, e.target.value)}>
                  <option value="">{ROTULO[k].todos}</option>
                  {p.listas[k].map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}
                </select></div>
            ))}
          </div>
          {def.ocultos ? <label className="td-check rep-check"><input type="checkbox" checked={p.ocultos} disabled={trabajando} onChange={(e) => p.setOcultos(e.target.checked)} /> {def.ocultos}</label> : null}
          <p className="rep-ayuda">
            {def.periodo ? `Hasta un año por descarga, por ${def.periodoPor ?? "la fecha del registro"}. ` : "Es la foto de hoy: no lleva periodo. "}
            Sin teléfonos ni nombres de personas. Cada descarga queda registrada con quién la hizo.
            {p.opcionesError && def.filtros.some((k) => k !== "planta") ? " No se pudo cargar la lista para filtrar: se descarga todo." : ""}
          </p>
          {msg ? <p className={`td-aviso td-aviso-${msg.tipo === "error" ? "error" : msg.tipo === "ok" ? "ok" : "info"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.t}</p> : null}
          {trabajando ? (
            <div className="rep-progreso" role="status">
              <span>{progreso.fase === "preparando" ? "Preparando…" : progreso.fase === "armando" ? "Armando el archivo…" : `Descargando ${nf(progreso.hecho)} de ${nf(progreso.total)} filas…`}</span>
              <button type="button" className="td-boton-sec" onClick={() => ctl.current?.abort()}>Cancelar</button>
            </div>
          ) : (
            <div className="td-botones rep-botones">
              <button type="button" className="td-boton" onClick={() => void descargar("xlsx")}>Descargar Excel</button>
              <button type="button" className="td-boton-sec" onClick={() => void descargar("csv")}>Descargar CSV</button>
            </div>
          )}
        </div>
      ) : null}
    </article>
  );
}
