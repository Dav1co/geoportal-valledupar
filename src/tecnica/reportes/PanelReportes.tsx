import { useEffect, useRef, useState } from "react";
import "./reportes.css";
import { ErrorTec } from "../apiTecnica";
import type { DefReporte, FiltroReporte, FuenteFiltro, Opcion } from "./catalogo";
import { errorPeriodo, hoyBogota, primeroDelMes, type Pedido } from "./armar";
import { fuenteDe } from "./apiReportes";
import { ejecutarReporte, guardarArchivo, ReporteCancelado, type Progreso } from "./ejecutar";

// La MISMA tarjeta para todos los reportes del Dashboard PTAP («Reportes») y las descargas del Dashboard distribución («Descargas»): nombre, una línea de
// descripción y, al abrirla, el periodo (hasta un año; los inventarios a hoy no lo llevan), los filtros del reporte, «Incluir…» donde aplica y los botones
// «Descargar Excel» y «Descargar CSV». Una tarjeta abierta a la vez; el periodo y los filtros se conservan al pasar de una a otra.

const nf = (n: number) => n.toLocaleString("es-CO");
type Msg = { tipo: "ok" | "info" | "error"; t: string };
export type Listas = Partial<Record<FuenteFiltro, Opcion[]>>;

export function PanelReportes({ titulo, ayuda, reportes, listas, listasConError = [], sinPermiso, prefijo }: {
  titulo: string; ayuda: string; reportes: DefReporte[]; listas: Listas; listasConError?: FuenteFiltro[]; sinPermiso: string; prefijo: string;
}) {
  const [abierta, setAbierta] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [desde, setDesde] = useState(primeroDelMes);
  const [hasta, setHasta] = useState(hoyBogota);
  const [filtros, setFiltros] = useState<Record<string, string>>({});
  const [ocultos, setOcultos] = useState(false);
  return (
    <section className="td-seccion rep" aria-label={titulo}>
      <div className="td-cab"><div><h2>{titulo}</h2><p className="td-sub">{ayuda}</p></div></div>
      <div className="rep-rejilla">
        {reportes.map((def) => (
          <TarjetaReporte key={def.clave} def={def} abierta={abierta === def.clave} bloqueada={ocupado && abierta !== def.clave} prefijo={prefijo}
            onAbrir={() => setAbierta(abierta === def.clave ? null : def.clave)} onOcupado={setOcupado} sinPermiso={sinPermiso}
            desde={desde} hasta={hasta} setDesde={setDesde} setHasta={setHasta} ocultos={ocultos} setOcultos={setOcultos}
            filtros={filtros} setFiltro={(k, v) => setFiltros((f) => ({ ...f, [k]: v }))} listas={listas} listasConError={listasConError} />
        ))}
      </div>
    </section>
  );
}

/** Opciones de un filtro: las de la lista fija o las del dashboard. */
const opcionesDe = (f: FiltroReporte, listas: Listas): Opcion[] => (f.fuente === "fija" ? f.opciones ?? [] : listas[f.fuente] ?? []);
/** El valor de un filtro se guarda por clave Y fuente: «tipo» de Usuarios sensibles (lista fija) y «tipo» de Activos (prefijos) no se mezclan. */
const claveEstado = (f: FiltroReporte) => `${f.clave}|${f.fuente}`;

function TarjetaReporte(p: {
  def: DefReporte; abierta: boolean; bloqueada: boolean; prefijo: string; onAbrir: () => void; onOcupado: (b: boolean) => void; sinPermiso: string;
  desde: string; hasta: string; setDesde: (v: string) => void; setHasta: (v: string) => void; ocultos: boolean; setOcultos: (v: boolean) => void;
  filtros: Record<string, string>; setFiltro: (k: string, v: string) => void; listas: Listas; listasConError: FuenteFiltro[];
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
    const pedido: Pedido = { formato, incluir_excluidos: !!def.ocultos && p.ocultos, filtros: {} };
    if (def.periodo) { pedido.desde = p.desde; pedido.hasta = p.hasta; }
    const filtrosTexto: string[] = [];
    for (const f of def.filtros) {
      const v = (p.filtros[claveEstado(f)] ?? "").trim(); if (!v) continue;
      const o = opcionesDe(f, p.listas).find((x) => x.codigo === v); if (!o) continue;      // un valor que ya no está en la lista no se manda
      pedido.filtros[f.clave] = v; filtrosTexto.push(`${f.rotulo}: ${o.nombre.replace(/^— /, "")}`);
    }
    const c = new AbortController(); ctl.current = c;
    setMsg(null); p.onOcupado(true);
    try {
      const r = await ejecutarReporte({ def, fuente: fuenteDe(def), pedido, filtrosTexto, onProgreso: setProgreso, senal: c.signal });
      if (!r.blob) setMsg({ tipo: "info", t: `${r.sinDatos || "No hay datos con esos filtros."} No se generó el archivo.` });
      else { guardarArchivo(r.nombre, r.blob); setMsg({ tipo: "ok", t: `Listo: ${nf(r.filas)} fila${r.filas === 1 ? "" : "s"} en ${formato === "xlsx" ? "Excel" : "CSV"}. La descarga quedó registrada.` }); }
    } catch (e) {
      setMsg(e instanceof ReporteCancelado ? { tipo: "info", t: "Descarga cancelada. No se generó el archivo." }
        : { tipo: "error", t: e instanceof ErrorTec && e.tipo === "permiso" ? p.sinPermiso : e instanceof Error ? e.message : "No se pudo completar la descarga." });
    } finally { setProgreso(null); p.onOcupado(false); ctl.current = null; }
  }

  const trabajando = progreso !== null;
  const sinLista = def.filtros.filter((f) => f.fuente !== "fija" && p.listasConError.includes(f.fuente)).map((f) => `«${f.rotulo}»`);
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
            {def.filtros.map((f) => (
              <div key={f.clave} className="td-campo"><label htmlFor={`${id}-${f.clave}`}>{f.rotulo}</label>
                <select id={`${id}-${f.clave}`} value={opcionesDe(f, p.listas).some((o) => o.codigo === p.filtros[claveEstado(f)]) ? p.filtros[claveEstado(f)] : ""} disabled={trabajando}
                  onChange={(e) => p.setFiltro(claveEstado(f), e.target.value)}>
                  <option value="">{f.todos}</option>
                  {opcionesDe(f, p.listas).map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}
                </select></div>
            ))}
          </div>
          {def.ocultos ? <label className="td-check rep-check"><input type="checkbox" checked={p.ocultos} disabled={trabajando} onChange={(e) => p.setOcultos(e.target.checked)} /> {def.ocultos}</label> : null}
          <p className="rep-ayuda">
            {def.periodo ? `Hasta un año por descarga, por ${def.periodoPor ?? "la fecha del registro"}. ` : "Es el inventario de hoy: no lleva periodo. "}
            {def.filtros.some((f) => f.fuente === "sectores") ? "Sector: un sector o uno de sus subsectores. " : ""}
            Sin teléfonos ni nombres de personas. Cada descarga queda registrada con quién la hizo.
            {sinLista.length ? ` No se pudo cargar la lista ${sinLista.join(" y ")}: se descarga sin ese filtro.` : ""}
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
