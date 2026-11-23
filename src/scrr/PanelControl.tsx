import { useCallback, useEffect, useState } from "react";
import { apiScrr, avisoDeError, type ContextoScrr, type ControlEvento, type ListaControl } from "./apiScrr";
import { leerXlsx, ErrorXlsx } from "./lectorXlsx";
import { contratoCanonico, normalizarEncabezado } from "./lector";
import { fecha, fechaHora, num } from "./formato";

// «Contratos con control» (reclamo manual, insolvencia, mínimo vital) y «Excluidos» (excluido manual por el supervisor): la misma tabla de eventos con su causa (P6).
// Mientras un contrato esté en una de estas listas no sale en la selección. Alta de uno en uno o por archivo con un motivo común (P10); baja con motivo; nada se borra.
// El motivo no lleva nombres, cédulas ni teléfonos: solo el porqué.
export function PanelControl({ ctx, grupo }: { ctx: ContextoScrr; grupo: "control" | "excluido" }) {
  const causas = ctx.causas_control.filter((c) => (grupo === "excluido" ? c.grupo === "excluido" : c.grupo !== "excluido"));
  const [lista, setLista] = useState<ListaControl | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [alta, setAlta] = useState({ contrato: "", causa: causas[0]?.codigo ?? "", motivo: "" });
  const [archivo, setArchivo] = useState<{ contratos: string[]; nombre: string; malas: number } | null>(null);
  const [lote, setLote] = useState({ causa: causas[0]?.codigo ?? "", motivo: "" });
  const [baja, setBaja] = useState<{ contrato: string; causa: string; motivo: string } | null>(null);
  const [historial, setHistorial] = useState<{ contrato: string; eventos: ControlEvento[] } | null>(null);
  const [buscar, setBuscar] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const titulo = grupo === "excluido" ? "Excluidos manuales" : "Contratos con control";

  const cargar = useCallback(async () => { try { setLista(await apiScrr.controlLista(grupo)); } catch (e) { setMensaje(avisoDeError(e)); } }, [grupo]);
  useEffect(() => { void cargar(); }, [cargar]);

  async function correr(f: () => Promise<string>) {
    setOcupado(true); setMensaje(null); setOk(null);
    try { setOk(await f()); await cargar(); } catch (e) { setMensaje(avisoDeError(e)); } finally { setOcupado(false); }
  }
  async function leerArchivo(f: File | null) {
    setArchivo(null); setMensaje(null); if (!f) return;
    try {
      const contratos: string[] = []; let col = -1; let malas = 0;
      await leerXlsx(new Uint8Array(await f.arrayBuffer()), { alFila: (celdas, h) => {
        if (h > 0) return;
        if (col < 0) { col = celdas.findIndex((c) => normalizarEncabezado(c ?? "") === "CONTRATO"); if (col < 0) throw new ErrorXlsx("La primera fila debe tener la columna «Contrato»."); return; }
        const v = (celdas[col] ?? "").trim(); if (!v) return;
        const c = contratoCanonico(v); if (c) contratos.push(c); else malas++;
      } });
      if (col < 0) throw new ErrorXlsx("El archivo no tiene la columna «Contrato».");
      if (!contratos.length) throw new ErrorXlsx("El archivo no trae contratos.");
      setArchivo({ contratos, nombre: f.name, malas });
    } catch (e) { setMensaje(e instanceof ErrorXlsx ? e.message : "No se pudo leer el archivo."); }
  }
  async function enviarLote() {
    if (!archivo) return;
    await correr(async () => {
      let nuevos = 0, ya = 0, malas = archivo.malas, rep = 0;
      for (let i = 0; i < archivo.contratos.length; i += 5000) {
        const r = await apiScrr.controlLote(archivo.contratos.slice(i, i + 5000), lote.causa, lote.motivo.trim());
        nuevos += r.nuevos; ya += r.ya_estaban; malas += r.no_validos; rep += r.repetidos_en_el_archivo;
      }
      setArchivo(null); setLote({ ...lote, motivo: "" });
      return `Archivo cargado: ${num(nuevos)} nuevos, ${num(ya)} ya estaban${rep ? `, ${num(rep)} repetidos en el archivo` : ""}${malas ? `, ${num(malas)} no válidos` : ""}.`;
    });
  }
  const motivoOk = (m: string) => m.trim().length >= 10;

  return (
    <div className="scrr-panel" data-grupo={grupo}>
      <section className="scrr-tarjeta">
        <h3>{titulo}</h3>
        <p className="scrr-suave">{grupo === "excluido"
          ? "Contratos puntuales que el supervisor saca de la selección, con su motivo. Cuentan aparte en los indicadores."
          : "Reclamo manual, proceso de insolvencia o mínimo vital: mientras esté en la lista, el contrato no sale en ninguna selección."} El motivo no lleva nombres, cédulas ni teléfonos.</p>
        {mensaje && <p className="scrr-error" role="alert">{mensaje}</p>}
        {ok && <p className="scrr-suave" role="status" data-bloque="ok">{ok}</p>}
        <h4>Agregar uno</h4>
        <div className="scrr-fila">
          <label>Contrato<input inputMode="numeric" value={alta.contrato} onChange={(e) => setAlta({ ...alta, contrato: e.target.value.replace(/\D/g, "").slice(0, 12) })} data-campo="alta-contrato" /></label>
          {causas.length > 1 && <label>Causa<select value={alta.causa} onChange={(e) => setAlta({ ...alta, causa: e.target.value })} data-campo="alta-causa">{causas.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></label>}
          <label className="scrr-ancha">Motivo<input type="text" maxLength={200} value={alta.motivo} onChange={(e) => setAlta({ ...alta, motivo: e.target.value })} placeholder="10 a 200 caracteres" data-campo="alta-motivo" /></label>
        </div>
        <button className="scrr-btn" disabled={ocupado || !alta.contrato || !motivoOk(alta.motivo)} data-accion="alta"
          onClick={() => void correr(async () => { await apiScrr.controlAgregar(alta.contrato, alta.causa, alta.motivo.trim()); const c = alta.contrato; setAlta({ ...alta, contrato: "", motivo: "" }); return `Contrato ${c} agregado.`; })}>Agregar</button>
        <h4>Agregar por archivo</h4>
        <p className="scrr-suave">Un Excel (.xlsx) con la columna «Contrato» en la primera fila. Todos quedan con el mismo motivo.</p>
        <div className="scrr-fila">
          <label className="scrr-archivo">Libro de Excel (.xlsx)<input type="file" accept=".xlsx" onChange={(e) => void leerArchivo(e.target.files?.[0] ?? null)} data-campo="archivo-control" /></label>
          {causas.length > 1 && <label>Causa<select value={lote.causa} onChange={(e) => setLote({ ...lote, causa: e.target.value })} data-campo="lote-causa">{causas.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></label>}
          <label className="scrr-ancha">Motivo común<input type="text" maxLength={200} value={lote.motivo} onChange={(e) => setLote({ ...lote, motivo: e.target.value })} placeholder="10 a 200 caracteres" data-campo="lote-motivo" /></label>
        </div>
        {archivo && <p className="scrr-suave">{archivo.nombre}: {num(archivo.contratos.length)} contratos{archivo.malas ? ` (${num(archivo.malas)} filas no son un contrato)` : ""}.</p>}
        <button className="scrr-btn" disabled={ocupado || !archivo || !motivoOk(lote.motivo)} onClick={() => void enviarLote()} data-accion="lote">Agregar los del archivo</button>
      </section>

      <section className="scrr-tarjeta">
        <h3>Vigentes ({num(lista?.total ?? 0)})</h3>
        <div className="scrr-fila">
          <label>Historial de un contrato<input inputMode="numeric" value={buscar} onChange={(e) => setBuscar(e.target.value.replace(/\D/g, "").slice(0, 12))} data-campo="buscar" /></label>
          <button className="scrr-btn scrr-sec" disabled={!buscar} onClick={() => void apiScrr.controlHistorial(buscar).then((r) => setHistorial({ contrato: buscar, eventos: r.historial })).catch((e) => setMensaje(avisoDeError(e)))}>Ver historial</button>
        </div>
        {historial && (
          <div className="scrr-resumen" data-bloque="historial"><h4>Contrato {historial.contrato}</h4>
            {historial.eventos.length === 0 ? <p className="scrr-suave">Sin eventos.</p> :
              <ul className="scrr-hist">{historial.eventos.map((e, i) => <li key={i}><strong>{e.evento === "alta" ? "Alta" : "Baja"}</strong> · {e.causa} · {fechaHora(e.fecha)} · <span>{e.motivo}</span>{e.origen === "archivo" ? " (por archivo)" : ""}</li>)}</ul>}
            <button className="scrr-link" onClick={() => setHistorial(null)}>Cerrar</button></div>
        )}
        <div className="scrr-tabla-wrap">
          <table className="scrr-tabla" data-tabla={grupo}><thead><tr><th>Contrato</th><th>Causa</th><th>Desde</th><th>Agregado por</th><th></th></tr></thead>
            <tbody>{(lista?.vigentes ?? []).map((v) => (
              <tr key={`${v.contrato}-${v.causa}`} data-contrato={v.contrato}><td>{v.contrato}</td><td>{v.causa_nombre}{v.origen === "archivo" ? " · archivo" : ""}</td><td>{fecha(v.desde)}</td><td>{v.autor.split("@")[0]}</td>
                <td><button className="scrr-link" onClick={() => setBaja({ contrato: String(v.contrato), causa: v.causa, motivo: "" })} data-accion="baja">Dar de baja</button></td></tr>))}
              {lista && lista.vigentes.length === 0 && <tr><td colSpan={5} className="scrr-suave">No hay contratos en la lista.</td></tr>}</tbody></table>
        </div>
        {baja && (
          <div className="scrr-reemplazo" data-bloque="baja">
            <p>Contrato {baja.contrato}: vuelve a ser elegible. Queda el historial de la baja con su motivo.</p>
            <input type="text" maxLength={200} placeholder="Motivo (10 a 200 caracteres)" value={baja.motivo} onChange={(e) => setBaja({ ...baja, motivo: e.target.value })} data-campo="baja-motivo" />
            <div><button className="scrr-btn" disabled={ocupado || !motivoOk(baja.motivo)} data-accion="confirmar-baja"
              onClick={() => void correr(async () => { await apiScrr.controlBaja(baja.contrato, baja.causa, baja.motivo.trim()); const c = baja.contrato; setBaja(null); return `Contrato ${c} dado de baja.`; })}>Confirmar la baja</button>
              <button className="scrr-link" onClick={() => setBaja(null)}>Cancelar</button></div>
          </div>
        )}
        {lista && lista.bajas_recientes.length > 0 && (
          <details><summary>Bajas recientes ({lista.bajas_recientes.length})</summary>
            <ul className="scrr-hist">{lista.bajas_recientes.map((b, i) => <li key={i}>{b.contrato} · {b.causa_nombre} · baja el {fecha(b.fecha)} · <span>{b.motivo}</span></li>)}</ul></details>
        )}
      </section>
    </div>
  );
}
