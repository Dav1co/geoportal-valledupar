import { useCallback, useEffect, useState } from "react";
import { apiScrr, avisoDeError, type Calendario, type CicloCalendario } from "./apiScrr";
import { fecha, fechaHora, hoyBogota } from "./formato";

// Calendario de ciclos (decisión 7 del 20-nov; 22-nov: no es fijo, se pueden agregar ciclos). Mandan el «pago oportuno» (define cuándo una factura queda vencida)
// y la «fecha de suspensión» (cuándo el ciclo entra en ventana de suspensión). Las demás etapas son contexto. Cambiar un ciclo ya guardado exige motivo; nada se borra.
const ETAPAS = ["lectura", "critica", "facturacion", "reparto"] as const;
const NOMBRE_ETAPA: Record<string, string> = { lectura: "Lectura", critica: "Crítica", facturacion: "Facturación", reparto: "Reparto" };
const periodoDe = (d: string) => d.slice(0, 4) + d.slice(5, 7);
const textoPeriodo = (p: string) => { const m = ["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"][Number(p.slice(4)) - 1]; return `${m} de ${p.slice(0, 4)}`; };

type Edicion = { ciclo: string; pago_oportuno: string; fecha_suspension: string; etapas: Record<string, string>; motivo: string; nuevo: boolean };

/** Una fecha corrida un mes (el 31 de enero pasa al último día de febrero). */
export function mesSiguiente(f: string): string {
  const [y, m, d] = f.split("-").map(Number); const ny = m === 12 ? y + 1 : y, nm = m === 12 ? 1 : m + 1;
  const ultimo = new Date(Date.UTC(ny, nm, 0)).getUTCDate();
  return `${ny}-${String(nm).padStart(2, "0")}-${String(Math.min(d, ultimo)).padStart(2, "0")}`;
}
const periodoAnterior = (p: string) => { const y = Number(p.slice(0, 4)), m = Number(p.slice(4)); return m === 1 ? `${y - 1}12` : `${y}${String(m - 1).padStart(2, "0")}`; };
type Copia = { ciclo: number; pago_oportuno: string; fecha_suspension: string; etapas: Record<string, string> }[];

export function PanelCalendario({ onCambio }: { onCambio?: () => void }) {
  const [periodo, setPeriodo] = useState(periodoDe(hoyBogota()));
  const [cal, setCal] = useState<Calendario | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [ed, setEd] = useState<Edicion | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [copia, setCopia] = useState<Copia | null>(null);

  const cargar = useCallback(async () => {
    try { setCal(await apiScrr.calendario(periodo)); setMensaje(null); } catch (e) { setMensaje(avisoDeError(e)); }
  }, [periodo]);
  useEffect(() => { void cargar(); }, [cargar]);

  // «Copiar del mes anterior» (David, 22-nov 21:21): las fechas del mes anterior corridas un mes, editables; solo se crean los ciclos que faltan
  async function copiarAnterior() {
    setMensaje(null); setOk(null);
    try {
      const ant = await apiScrr.calendario(periodoAnterior(periodo));
      const ya = new Set((cal?.ciclos ?? []).map((c) => c.ciclo));
      const filas = ant.ciclos.filter((c) => !ya.has(c.ciclo)).map((c) => ({ ciclo: c.ciclo, pago_oportuno: mesSiguiente(c.pago_oportuno), fecha_suspension: mesSiguiente(c.fecha_suspension),
        etapas: Object.fromEntries(Object.entries(c.etapas ?? {}).filter(([, v]) => /^\d{4}-\d{2}-\d{2}$/.test(v)).map(([k, v]) => [k, mesSiguiente(v)])) }));
      if (!filas.length) { setMensaje(ant.ciclos.length ? "Este mes ya tiene todos los ciclos del mes anterior." : `El mes anterior (${textoPeriodo(periodoAnterior(periodo))}) no tiene calendario.`); return; }
      setCopia(filas);
    } catch (e) { setMensaje(avisoDeError(e)); }
  }
  async function guardarCopia() {
    if (!copia) return;
    setGuardando(true); setMensaje(null); setOk(null);
    try { const r = await apiScrr.calendarioGuardarLote(periodo, copia); setOk(`${r.nuevos} ciclos guardados en ${textoPeriodo(periodo)}.`); setCopia(null); await cargar(); onCambio?.(); }
    catch (e) { setMensaje(avisoDeError(e)); } finally { setGuardando(false); }
  }
  const copiaValida = copia?.every((c) => c.pago_oportuno && c.fecha_suspension && c.fecha_suspension >= c.pago_oportuno) ?? false;

  const editar = (c: CicloCalendario) => setEd({ ciclo: String(c.ciclo), pago_oportuno: c.pago_oportuno, fecha_suspension: c.fecha_suspension, etapas: { ...c.etapas }, motivo: "", nuevo: false });
  const nuevo = () => setEd({ ciclo: "", pago_oportuno: "", fecha_suspension: "", etapas: {}, motivo: "", nuevo: true });

  async function guardar() {
    if (!ed) return;
    setGuardando(true); setMensaje(null); setOk(null);
    try {
      const etapas = Object.fromEntries(Object.entries(ed.etapas).filter(([, v]) => v));
      await apiScrr.calendarioGuardar({ periodo, ciclo: Number(ed.ciclo), pago_oportuno: ed.pago_oportuno, fecha_suspension: ed.fecha_suspension, etapas, motivo: ed.motivo.trim() || null });
      setOk(`Ciclo ${ed.ciclo} guardado.`); setEd(null); await cargar(); onCambio?.();
    } catch (e) { setMensaje(avisoDeError(e)); } finally { setGuardando(false); }
  }

  const existe = (n: string) => cal?.ciclos.some((c) => String(c.ciclo) === n.trim()) ?? false;
  const valido = ed && /^\d{1,2}$/.test(ed.ciclo.trim()) && Number(ed.ciclo) >= 1 && ed.pago_oportuno && ed.fecha_suspension && ed.fecha_suspension >= ed.pago_oportuno
    && (ed.nuevo && !existe(ed.ciclo) ? true : ed.motivo.trim().length >= 5);

  return (
    <div className="scrr-panel">
      <section className="scrr-tarjeta">
        <h3>Calendario de ciclos</h3>
        <p className="scrr-suave">El <strong>pago oportuno</strong> define cuándo la factura del mes queda vencida; la <strong>fecha de suspensión</strong>, cuándo el ciclo entra en la ventana de suspensión. Los cambios quedan con su motivo y su historial.</p>
        <div className="scrr-fila">
          <label>Período
            <input type="month" value={`${periodo.slice(0, 4)}-${periodo.slice(4)}`} onChange={(e) => e.target.value && setPeriodo(e.target.value.replace("-", ""))} data-campo="periodo" />
          </label>
          <button className="scrr-btn scrr-sec" onClick={nuevo} data-accion="agregar-ciclo">Agregar un ciclo</button>
          <button className="scrr-btn scrr-sec" onClick={() => void copiarAnterior()} data-accion="copiar-anterior">Copiar del mes anterior</button>
        </div>
        {copia && (
          <div className="scrr-reemplazo" data-bloque="copia">
            <h4>{copia.length} ciclos de {textoPeriodo(periodoAnterior(periodo))}, corridos un mes. Corrija las fechas y guarde.</h4>
            <div className="scrr-tabla-wrap"><table className="scrr-tabla" data-tabla="copia"><thead><tr><th>Ciclo</th><th>Pago oportuno</th><th>Suspensión</th></tr></thead>
              <tbody>{copia.map((c, i) => (
                <tr key={c.ciclo} data-ciclo={c.ciclo}><td>{String(c.ciclo).padStart(2, "0")}</td>
                  <td><input type="date" value={c.pago_oportuno} onChange={(e) => setCopia(copia.map((x, j) => (j === i ? { ...x, pago_oportuno: e.target.value } : x)))} /></td>
                  <td><input type="date" value={c.fecha_suspension} min={c.pago_oportuno} onChange={(e) => setCopia(copia.map((x, j) => (j === i ? { ...x, fecha_suspension: e.target.value } : x)))} /></td></tr>))}</tbody></table></div>
            {!copiaValida && <p className="scrr-error">Revise las fechas: la suspensión no puede ser anterior al pago oportuno.</p>}
            <div><button className="scrr-btn" disabled={guardando || !copiaValida} onClick={() => void guardarCopia()} data-accion="guardar-copia">{guardando ? "Guardando…" : `Guardar los ${copia.length} ciclos`}</button>
              <button className="scrr-link" onClick={() => setCopia(null)}>Cancelar</button></div>
          </div>
        )}
        {mensaje && <p className="scrr-error" role="alert">{mensaje}</p>}
        {ok && <p className="scrr-suave" role="status">{ok}</p>}
        {ed && (
          <div className="scrr-reemplazo" data-bloque="editar-ciclo">
            <h4>{ed.nuevo ? `Ciclo nuevo en ${textoPeriodo(periodo)}` : `Ciclo ${ed.ciclo} · ${textoPeriodo(periodo)}`}</h4>
            <div className="scrr-fila">
              <label>Ciclo<input inputMode="numeric" value={ed.ciclo} disabled={!ed.nuevo} onChange={(e) => setEd({ ...ed, ciclo: e.target.value.replace(/\D/g, "").slice(0, 2) })} data-campo="ciclo" /></label>
              <label>Pago oportuno<input type="date" value={ed.pago_oportuno} onChange={(e) => setEd({ ...ed, pago_oportuno: e.target.value })} data-campo="pago-oportuno" /></label>
              <label>Fecha de suspensión<input type="date" value={ed.fecha_suspension} min={ed.pago_oportuno || undefined} onChange={(e) => setEd({ ...ed, fecha_suspension: e.target.value })} data-campo="fecha-suspension" /></label>
            </div>
            <details><summary>Otras etapas (contexto)</summary>
              <div className="scrr-fila">{ETAPAS.map((k) => (
                <label key={k}>{NOMBRE_ETAPA[k]}<input type="date" value={ed.etapas[k] ?? ""} onChange={(e) => setEd({ ...ed, etapas: { ...ed.etapas, [k]: e.target.value } })} /></label>))}</div>
            </details>
            {(!ed.nuevo || existe(ed.ciclo)) && <input type="text" placeholder="Motivo del cambio (5 a 300 caracteres)" maxLength={300} value={ed.motivo} onChange={(e) => setEd({ ...ed, motivo: e.target.value })} data-campo="motivo-ciclo" />}
            {ed.fecha_suspension && ed.pago_oportuno && ed.fecha_suspension < ed.pago_oportuno && <p className="scrr-error">La fecha de suspensión no puede ser anterior al pago oportuno.</p>}
            <div><button className="scrr-btn" disabled={!valido || guardando} onClick={() => void guardar()} data-accion="guardar-ciclo">{guardando ? "Guardando…" : "Guardar"}</button>
              <button className="scrr-link" onClick={() => setEd(null)}>Cancelar</button></div>
          </div>
        )}
        {!cal ? <p className="scrr-suave">Consultando…</p> : cal.ciclos.length === 0 ? <p className="scrr-suave">No hay ciclos cargados para {textoPeriodo(periodo)}. Agréguelos con «Agregar un ciclo».</p> : (
          <div className="scrr-tabla-wrap">
            <table className="scrr-tabla" data-tabla="calendario"><thead><tr><th>Ciclo</th><th>Pago oportuno</th><th>Suspensión</th><th>Estado hoy</th><th>Último cambio</th><th></th></tr></thead>
              <tbody>{cal.ciclos.map((c) => (
                <tr key={c.ciclo} data-ciclo={c.ciclo}><td>{String(c.ciclo).padStart(2, "0")}</td><td>{fecha(c.pago_oportuno)}</td><td>{fecha(c.fecha_suspension)}</td>
                  <td>{c.en_ventana ? "En ventana de suspensión" : "Aún no"}</td><td>{c.versiones > 1 ? `${fechaHora(c.ultimo_cambio)} (${c.motivo ?? "sin motivo"})` : "—"}</td>
                  <td><button className="scrr-link" onClick={() => editar(c)} data-accion="editar-ciclo">Cambiar</button></td></tr>))}</tbody></table>
          </div>
        )}
      </section>
    </div>
  );
}
