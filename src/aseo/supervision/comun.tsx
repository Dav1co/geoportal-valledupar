import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../../lib/supabase";
import { hoyBogota, periodoARango, type Periodo } from "../../tecnica/formato";
import type { FormularioAseo } from "../tipos";
import type { EstadoNc, Filtros, TipoNc } from "./api";

// Piezas compartidas de «Supervisión y dashboard»: aviso de error, diálogo de motivo, filtros y rótulos. Las clases visuales son las del Dashboard técnico (dashboard.css), sin modificarlas.
export const ROT_INCIDENCIA = { si: "Sí", no: "No", parcial: "Parcial" } as const;
export const ROT_TIPO: Record<TipoNc, string> = { sst: "SST", no_realizada: "No realizada", parcial: "Parcial", forma_indebida: "Forma indebida" };
export const ROT_ESTADO: Record<EstadoNc, string> = { sin_revisar: "Sin revisar", revisada: "Revisada", reabierta: "Reabierta (sin revisar)" };
export const nombreCorto = (correo: string) => correo.split("@")[0];
export const fmtFechaSrv = (iso: string) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : "");
/** «2026-11-13T15:30:00+00:00» → «13/11/2026 10:30» (Bogotá, UTC−5 fijo). */
export function fmtInstanteBogota(iso: string | null | undefined): string {
  if (!iso) return ""; const d = new Date(new Date(iso).getTime() - 5 * 3600000).toISOString();
  return `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)} ${d.slice(11, 16)}`;
}

/** Duración entre inicio y fin: «1 h 05 min», «12 min», «45 s». Vacía sin inicio. Una diferencia negativa (reloj del celular hasta 2 min adelantado) se muestra «0 s». */
export function fmtDuracion(seg: number | null | undefined): string {
  if (seg === null || seg === undefined || !Number.isFinite(seg)) return "";
  const s = Math.max(0, Math.round(seg));
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")} min`;
}
/** Inicio en hora de Bogotá, con «(celular)» cuando lo tomó el celular. Vacío si no hay. */
export function fmtInicio(iso: string | null | undefined, origen: string | null | undefined): string {
  if (!iso) return "";
  return `${fmtInstanteBogota(iso)}${origen === "dispositivo" ? " (celular)" : ""}`;
}

export function ErrorCaja({ error, onReintentar }: { error: { texto: string; sesion: boolean }; onReintentar: () => void }) {
  return (
    <div className="td-aviso td-aviso-error" role="alert">{error.texto}{" "}
      {error.sesion ? <button type="button" className="td-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="td-enlace" onClick={onReintentar}>Reintentar</button>}
    </div>
  );
}

/** Diálogo con un motivo (o nota). min = 0 → opcional. Escape cierra; el foco va al texto. */
export function DialogoMotivo({ titulo, texto, rotulo, min, max, boton, onConfirmar, onCerrar }: {
  titulo: string; texto: React.ReactNode; rotulo: string; min: number; max: number; boton: string; onConfirmar: (motivo: string) => Promise<void>; onCerrar: () => void;
}) {
  const [motivo, setMotivo] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { ref.current?.focus(); const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && !enviando) onCerrar(); }; window.addEventListener("keydown", esc); return () => window.removeEventListener("keydown", esc); }, [onCerrar, enviando]);
  const largo = motivo.trim().length, valido = largo >= min && largo <= max;
  async function ir() { if (!valido || enviando) return; setEnviando(true); setError(null); try { await onConfirmar(motivo.trim()); } catch (e) { setError(e instanceof Error ? e.message : "No se pudo completar."); setEnviando(false); } }
  return (
    <div className="td-fondo" role="presentation">
      <div className="td-dialogo" role="dialog" aria-modal="true" aria-labelledby="as-dlg-tit">
        <h3 id="as-dlg-tit">{titulo}</h3>
        <div className="td-sub">{texto}</div>
        <label className="td-campo td-ancho">{rotulo}{min > 0 ? ` (obligatorio, de ${min} a ${max} caracteres)` : ` (opcional, hasta ${max} caracteres)`}
          <textarea ref={ref} rows={3} value={motivo} maxLength={max} onChange={(e) => setMotivo(e.target.value)} aria-invalid={largo > 0 && !valido} /></label>
        <span className={`td-chico${largo > 0 && !valido ? " td-error" : ""}`}>{largo} caracteres{largo > 0 && largo < min ? ` · faltan ${min - largo}` : ""}</span>
        {error ? <p className="td-error" role="alert">{error}</p> : null}
        <div className="td-dialogo-acciones">
          <button type="button" className="td-boton" onClick={() => void ir()} disabled={!valido || enviando}>{enviando ? "Guardando…" : boton}</button>
          <button type="button" className="td-boton-sec" onClick={onCerrar} disabled={enviando}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}

// ---------------- Filtros ----------------
export type EstadoFiltros = { periodo: Periodo; desde: string; hasta: string; actividad: string; modalidad: string; servicio: string; turno: string; barrio: string; auditor: string; incidencia: string; nc: string; ocultos: string };
export const FILTROS_INICIALES: EstadoFiltros = { periodo: "mes", desde: "", hasta: "", actividad: "", modalidad: "", servicio: "", turno: "", barrio: "", auditor: "", incidencia: "", nc: "todos", ocultos: "no" };
const PERIODOS: { v: Periodo; t: string }[] = [{ v: "hoy", t: "Hoy" }, { v: "7d", t: "Últimos 7 días" }, { v: "mes", t: "Mes en curso" }, { v: "rango", t: "Rango de fechas…" }];
export const rangoInvalido = (f: EstadoFiltros) => f.periodo === "rango" && !!f.desde && !!f.hasta && f.desde > f.hasta;

export function aServidor(f: EstadoFiltros): Filtros {
  const r = periodoARango(f.periodo, hoyBogota(), f.desde, f.hasta);
  return { desde: r.desde, hasta: r.hasta, actividad: f.actividad, modalidad: f.modalidad, servicio: f.servicio, turno: f.turno, barrio: f.barrio.trim(), auditor: f.auditor, incidencia: f.incidencia, nc: f.nc === "todos" ? "" : f.nc, ocultos: f.ocultos };
}
/** Texto de los filtros para la hoja Léame de las descargas. */
export function textoFiltros(f: EstadoFiltros, def: FormularioAseo, auditores: { email: string; nombre: string | null }[], turnos: { codigo: number; nombre: string }[]): string[] {
  const r = periodoARango(f.periodo, hoyBogota(), f.desde, f.hasta), out: string[] = [];
  const act = def.actividades.find((a) => a.codigo === f.actividad), mod = act?.modalidades?.find((m) => m.codigo === f.modalidad);
  out.push(`Periodo (fecha de servicio): ${r.desde ? fmtFechaSrv(r.desde) : "sin límite"} a ${r.hasta ? fmtFechaSrv(r.hasta) : "sin límite"}`);
  if (act) out.push(`Actividad: ${act.nombre}`); if (mod) out.push(`Modalidad: ${mod.nombre}`);
  if (f.servicio) out.push(`Servicio: ${f.servicio}`); if (f.turno) out.push(`Turno: ${turnos.find((t) => String(t.codigo) === f.turno)?.nombre ?? f.turno}`);
  if (f.barrio.trim()) out.push(`Barrio: ${f.barrio.trim()} (barrio actual de la ruta)`);
  if (f.auditor) out.push(`Auditor: ${auditores.find((a) => a.email === f.auditor)?.nombre ?? f.auditor}`);
  if (f.incidencia) out.push(`Incidencia: ${ROT_INCIDENCIA[f.incidencia as "si"]}`);
  if (f.nc !== "todos") out.push(`No conformidades: ${({ con: "con no conformidad", sin: "sin no conformidad", pendientes: "pendientes de revisión", revisadas: "revisadas" } as Record<string, string>)[f.nc]}`);
  out.push(`Auditorías ocultas: ${({ no: "no se incluyen", si: "solo las ocultas", todos: "se incluyen" } as Record<string, string>)[f.ocultos]}`);
  return out;
}

export function FiltrosSup({ def, turnos, auditores, valor, onCambio, conNc = true, conOcultas = true, idp }: {
  def: FormularioAseo; turnos: { codigo: number; nombre: string }[]; auditores: { email: string; nombre: string | null }[]; valor: EstadoFiltros; onCambio: (f: EstadoFiltros) => void; conNc?: boolean; conOcultas?: boolean; idp: string;
}) {
  const [abiertos, setAbiertos] = useState(false);
  const act = def.actividades.find((a) => a.codigo === valor.actividad);
  const modalidades = act?.modalidades ?? [];
  const servicios = useMemo(() => (modalidades.find((m) => m.codigo === valor.modalidad)?.servicios ?? modalidades.flatMap((m) => m.servicios)), [modalidades, valor.modalidad]);
  const set = (p: Partial<EstadoFiltros>) => onCambio({ ...valor, ...p });
  return (
    <div className={`td-filtros${abiertos ? " abierto" : ""}`}>
      <button type="button" className="td-boton-sec td-solo-movil" aria-expanded={abiertos} onClick={() => setAbiertos((x) => !x)}>Filtros{abiertos ? " ▲" : " ▼"}</button>
      <div className="td-filtros-cuerpo">
        <label className="td-campo">Periodo (fecha de servicio)<select id={`${idp}-per`} value={valor.periodo} onChange={(e) => set({ periodo: e.target.value as Periodo })}>{PERIODOS.map((p) => <option key={p.v} value={p.v}>{p.t}</option>)}</select></label>
        {valor.periodo === "rango" ? <>
          <label className="td-campo">Desde<input id={`${idp}-desde`} type="date" value={valor.desde} onChange={(e) => set({ desde: e.target.value })} /></label>
          <label className="td-campo">Hasta<input id={`${idp}-hasta`} type="date" value={valor.hasta} onChange={(e) => set({ hasta: e.target.value })} /></label></> : null}
        <label className="td-campo">Actividad<select id={`${idp}-act`} value={valor.actividad} onChange={(e) => set({ actividad: e.target.value, modalidad: "", servicio: "" })}><option value="">Todas</option>{def.actividades.map((a) => <option key={a.codigo} value={a.codigo}>{a.nombre}</option>)}</select></label>
        <label className="td-campo">Modalidad<select id={`${idp}-mod`} value={valor.modalidad} disabled={!act} onChange={(e) => set({ modalidad: e.target.value, servicio: "" })}><option value="">Todas</option>{modalidades.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}</select></label>
        <label className="td-campo">Servicio<select id={`${idp}-srv`} value={valor.servicio} disabled={!act} onChange={(e) => set({ servicio: e.target.value })}><option value="">Todos</option>{servicios.map((s) => <option key={s.codigo} value={s.codigo}>{s.nombre}</option>)}</select></label>
        <label className="td-campo">Turno<select id={`${idp}-tur`} value={valor.turno} onChange={(e) => set({ turno: e.target.value })}><option value="">Todos</option>{turnos.map((t) => <option key={t.codigo} value={String(t.codigo)}>{t.nombre}</option>)}</select></label>
        <label className="td-campo">Barrio<input id={`${idp}-bar`} type="text" value={valor.barrio} maxLength={120} placeholder="Nombre del barrio" onChange={(e) => set({ barrio: e.target.value })} /></label>
        <label className="td-campo">Auditor<select id={`${idp}-aud`} value={valor.auditor} onChange={(e) => set({ auditor: e.target.value })}><option value="">Todos</option>{auditores.map((a) => <option key={a.email} value={a.email}>{a.nombre ?? nombreCorto(a.email)}</option>)}</select></label>
        <label className="td-campo">Incidencia<select id={`${idp}-inc`} value={valor.incidencia} onChange={(e) => set({ incidencia: e.target.value })}><option value="">Todas</option><option value="si">Sí (se realizó)</option><option value="parcial">Parcial</option><option value="no">No se realizó</option></select></label>
        {conNc ? <label className="td-campo">No conformidades<select id={`${idp}-nc`} value={valor.nc} onChange={(e) => set({ nc: e.target.value })}><option value="todos">Todas las auditorías</option><option value="con">Con no conformidad</option><option value="pendientes">Pendientes de revisión</option><option value="revisadas">Revisadas</option><option value="sin">Sin no conformidad</option></select></label> : null}
        {conOcultas ? <label className="td-campo">Ocultas<select id={`${idp}-ocu`} value={valor.ocultos} onChange={(e) => set({ ocultos: e.target.value })}><option value="no">No incluir</option><option value="todos">Incluir</option><option value="si">Solo las ocultas</option></select></label> : null}
      </div>
    </div>
  );
}
