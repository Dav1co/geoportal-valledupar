import { useCallback, useEffect, useState } from "react";
import { apiScrr, avisoDeError, type Corrida, type Retorno } from "./apiScrr";
import { descargarExcel, imprimir } from "./listas";
import { fecha, fechaHora, num, pesos } from "./formato";

// Retorno (decisiones 8, 11 y 12 del 20-nov): la única decisión del sistema. Un contrato que quedó sin agua y ya está a paz y salvo (saldo pendiente en cero en la
// cartera del día) sale aquí con su actividad subsanadora: reinstalación (tras suspensión), reconexión (tras corte) o reconexión drástica (con aviso).
// «Por confirmar»: pagó pero la cartera aún muestra saldo; no sale hasta que la cartera lo confirme. El supervisor puede agregar a mano, con motivo.
const ESTADO: Record<string, string> = { suspendido: "Suspendido", cortado: "Cortado", cortado_drastico: "Cortado drástico", sin_dato: "Sin acta cargada" };

export function PanelRetorno() {
  const [r, setR] = useState<Retorno | null>(null);
  const [corridas, setCorridas] = useState<Corrida[]>([]);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [alta, setAlta] = useState({ contrato: "", actividad: "reconexion", motivo: "" });
  const [quitar, setQuitar] = useState<{ contrato: string; motivo: string } | null>(null);

  const cargar = useCallback(async () => {
    try { const [x, c] = await Promise.all([apiScrr.retorno(), apiScrr.corridas()]); setR(x); setCorridas(c.corridas.filter((k) => k.tipo === "retorno")); }
    catch (e) { setMensaje(avisoDeError(e)); }
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);
  async function correr(f: () => Promise<string>) {
    setOcupado(true); setMensaje(null); setOk(null);
    try { setOk(await f()); await cargar(); } catch (e) { setMensaje(avisoDeError(e)); } finally { setOcupado(false); }
  }
  async function salida(c: Corrida, formato: "excel" | "impresion") {
    setMensaje(null);
    const w = formato === "impresion" ? window.open("", "_blank") : null;
    if (formato === "impresion" && !w) { setMensaje("El navegador bloqueó la ventana de impresión: permita ventanas emergentes para el geoportal."); return; }
    try { const l = await apiScrr.lista(c.corrida_id, formato); if (formato === "excel") await descargarExcel(l); else imprimir(l, w!); }
    catch (e) { w?.close(); setMensaje(avisoDeError(e)); }
  }
  const pendientes = (r?.proponer ?? []).filter((x) => !x.ya_en_lista);
  const listados = (r?.proponer ?? []).filter((x) => x.ya_en_lista);

  return (
    <div className="scrr-panel">
      <section className="scrr-tarjeta">
        <h3>A reinstalar o reconectar</h3>
        <p className="scrr-suave">Contratos que quedaron sin agua y hoy están a paz y salvo (saldo pendiente en cero en la cartera {r?.foto ? `del ${fecha(r.foto)}` : "del día"}). Un pago no basta: tiene que reflejarse en la cartera.</p>
        {mensaje && <p className="scrr-error" role="alert">{mensaje}</p>}
        {ok && <p className="scrr-suave" role="status" data-bloque="ok">{ok}</p>}
        {!r ? <p className="scrr-suave">Consultando…</p> : <>
          <div className="scrr-tabla-wrap">
            <table className="scrr-tabla" data-tabla="retorno"><thead><tr><th>Contrato</th><th>Actividad</th><th>Estado</th><th>Desde</th><th>Origen</th><th>Ruta</th><th></th></tr></thead>
              <tbody>{pendientes.map((x) => (
                <tr key={x.contrato} data-contrato={x.contrato} data-origen={x.origen}><td>{x.contrato}</td>
                  <td>{x.actividad}{x.aviso && <div className="scrr-aviso-celda">{x.aviso}</div>}</td><td>{ESTADO[x.estado] ?? x.estado}</td><td>{fecha(x.desde)}</td>
                  <td>{x.origen === "manual" ? <span title={x.motivo ?? ""}>Manual{x.saldo && x.saldo > 0 ? ` · debe ${pesos(x.saldo)}` : ""}</span> : "Automático"}</td><td>{x.ruta ?? "—"}</td>
                  <td>{x.origen === "manual" && <button className="scrr-link" onClick={() => setQuitar({ contrato: x.contrato, motivo: "" })} data-accion="quitar">Quitar</button>}</td></tr>))}
                {pendientes.length === 0 && <tr><td colSpan={7} className="scrr-suave">No hay contratos pendientes de reinstalar o reconectar.</td></tr>}</tbody></table>
          </div>
          {pendientes.length > 0 && <button className="scrr-btn" disabled={ocupado} data-accion="generar-retorno"
            onClick={() => void correr(async () => { const g = await apiScrr.retornoGenerar(); return `Lista de retorno generada: ${num(g.contratos)} contratos.`; })}>Generar la lista de retorno ({num(pendientes.length)})</button>}
          {listados.length > 0 && <p className="scrr-suave">{num(listados.length)} ya están en una lista de retorno generada (no vuelven a salir).</p>}
          {quitar && (
            <div className="scrr-reemplazo" data-bloque="quitar">
              <p>Contrato {quitar.contrato}: deja de proponerse. Queda el historial con el motivo.</p>
              <input type="text" maxLength={200} placeholder="Motivo (10 a 200 caracteres)" value={quitar.motivo} onChange={(e) => setQuitar({ ...quitar, motivo: e.target.value })} data-campo="quitar-motivo" />
              <div><button className="scrr-btn" disabled={ocupado || quitar.motivo.trim().length < 10} data-accion="confirmar-quitar"
                onClick={() => void correr(async () => { await apiScrr.retornoQuitar(quitar.contrato, quitar.motivo.trim()); const c = quitar.contrato; setQuitar(null); return `Contrato ${c} quitado del retorno.`; })}>Confirmar</button>
                <button className="scrr-link" onClick={() => setQuitar(null)}>Cancelar</button></div>
            </div>
          )}
        </>}
      </section>

      <section className="scrr-tarjeta" data-bloque="por-confirmar">
        <h3>Por confirmar ({num(r?.por_confirmar.length ?? 0)})</h3>
        <p className="scrr-suave">Siguen sin agua y pagaron desde la fecha de la cartera, pero la cartera aún muestra saldo. Saldrán solos cuando la cartera los muestre en cero.</p>
        {r && r.por_confirmar.length > 0 && (
          <div className="scrr-tabla-wrap"><table className="scrr-tabla" data-tabla="por-confirmar"><thead><tr><th>Contrato</th><th>Estado</th><th>Saldo en la cartera</th><th>Pagado desde la cartera</th></tr></thead>
            <tbody>{r.por_confirmar.map((x) => <tr key={x.contrato} data-contrato={x.contrato}><td>{x.contrato}</td><td>{ESTADO[x.estado] ?? x.estado}</td><td>{pesos(x.saldo)}</td><td>{pesos(x.pagado_desde_cartera)}</td></tr>)}</tbody></table></div>
        )}
      </section>

      <section className="scrr-tarjeta">
        <h3>Agregar a mano</h3>
        <p className="scrr-suave">Un contrato que sigue en deuda pero corresponde reconectar (por ejemplo, un reclamo que no está registrado en el sistema). Queda con su motivo y auditado.</p>
        <div className="scrr-fila">
          <label>Contrato<input inputMode="numeric" value={alta.contrato} onChange={(e) => setAlta({ ...alta, contrato: e.target.value.replace(/\D/g, "").slice(0, 12) })} data-campo="retorno-contrato" /></label>
          <label>Actividad<select value={alta.actividad} onChange={(e) => setAlta({ ...alta, actividad: e.target.value })} data-campo="retorno-actividad">
            <option value="reinstalacion">Reinstalación</option><option value="reconexion">Reconexión</option><option value="reconexion_drastica">Reconexión drástica</option></select></label>
          <label className="scrr-ancha">Motivo<input type="text" maxLength={200} value={alta.motivo} onChange={(e) => setAlta({ ...alta, motivo: e.target.value })} placeholder="10 a 200 caracteres" data-campo="retorno-motivo" /></label>
        </div>
        <button className="scrr-btn" disabled={ocupado || !alta.contrato || alta.motivo.trim().length < 10} data-accion="retorno-agregar"
          onClick={() => void correr(async () => { await apiScrr.retornoAgregar(alta.contrato, alta.actividad, alta.motivo.trim()); const c = alta.contrato; setAlta({ ...alta, contrato: "", motivo: "" }); return `Contrato ${c} agregado al retorno.`; })}>Agregar</button>
      </section>

      <section className="scrr-tarjeta">
        <h3>Listas de retorno generadas</h3>
        <div className="scrr-tabla-wrap">
          <table className="scrr-tabla" data-tabla="corridas-retorno"><thead><tr><th>Generada</th><th>Contratos</th><th>Por</th><th></th></tr></thead>
            <tbody>{corridas.map((c) => (
              <tr key={c.corrida_id} data-corrida={c.corrida_id}><td>{fechaHora(c.creada_en)}</td><td>{num(c.contratos)}</td><td>{c.autor.split("@")[0]}</td>
                <td><button className="scrr-link" onClick={() => void salida(c, "excel")} data-accion="excel">Descargar Excel</button>
                    <button className="scrr-link" onClick={() => void salida(c, "impresion")} data-accion="imprimir">Imprimir</button></td></tr>))}
              {corridas.length === 0 && <tr><td colSpan={4} className="scrr-suave">Todavía no hay listas de retorno.</td></tr>}</tbody></table>
        </div>
      </section>
    </div>
  );
}
