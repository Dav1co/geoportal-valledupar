import { useCallback, useEffect, useState } from "react";
import { apiScrr, avisoDeError, type Corrida, type Filtros, type OpcionesSeleccion, type Previa } from "./apiScrr";
import { fecha, fechaHora, num, pesos } from "./formato";
import { descargarExcel, imprimir } from "./listas";

// Selección (sección 4 del encargo del 20-nov): un ciclo a la vez, embudo de exclusiones con conteos (la vista previa no muestra contratos ni datos personales),
// filtros del supervisor y la actividad que él escoge (Suspensión, Corte o Gestión de cobro). El motor no clasifica: la guía es referencia, no regla.
// La lista generada se descarga o imprime con nombre y dirección (excepción escrita P2 del 22-nov), con la deuda (P9); cada descarga queda registrada.
const PASOS: [string, string][] = [
  ["p0_comodin", "Comodín del sistema (99999999 o categoría «-1»)"], ["p1_no_facturado_o_sin_ruta", "No facturado en el último período o sin ruta"],
  ["p2_control_vigente", "Contratos con control"], ["p3_reclamo", "Con reclamo (valor en reclamo o reclamo manual)"],
  ["p4_pago_sin_reflejar", "Pago del día que cubre el saldo (sin reflejar en la cartera)"], ["p4_paz_y_salvo_hoy", "A paz y salvo hoy (contado aparte)"],
  ["p5_evento_suspension_agua", "Dentro de un evento de suspensión de agua de Técnica"], ["p6_excluido_manual", "Excluidos manuales"],
  ["p7_saldo_menor_al_minimo", "Saldo menor al monto mínimo"], ["f_fuera_del_rango", "Fuera del rango escogido"], ["f_otro_barrio", "De otro barrio"],
  ["f_fuera_del_segmento", "Fuera del segmento (aproximado)"], ["candidato", "Candidatos a la lista"],
];
const RANGOS: [string, number, number | null][] = [["1 a 6", 1, 6], ["7 a 25", 7, 25], ["26 o más", 26, null]];
export function PanelSeleccion() {
  const [op, setOp] = useState<OpcionesSeleccion | null>(null);
  const [ciclo, setCiclo] = useState<number | null>(null);
  const [f, setF] = useState<Filtros>({ modo: "meses", desde: 1, hasta: 6, monto_minimo: 5000, barrio_id: null, segmento: "todos", n: 8 });
  const [previa, setPrevia] = useState<Previa | null>(null);
  const [actividad, setActividad] = useState<string>("");
  const [corridas, setCorridas] = useState<Corrida[]>([]);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const cargarCorridas = useCallback(async () => { try { setCorridas((await apiScrr.corridas()).corridas.filter((c) => c.tipo !== "retorno")); } catch (e) { setMensaje(avisoDeError(e)); } }, []);
  useEffect(() => {
    apiScrr.opciones().then((o) => { setOp(o); const v = o.ciclos.find((c) => c.en_ventana) ?? o.ciclos[0]; if (v) setCiclo(v.ciclo); }).catch((e) => setMensaje(avisoDeError(e)));
    void cargarCorridas();
  }, [cargarCorridas]);
  useEffect(() => {
    if (ciclo === null) return;
    setPrevia(null); setF((x) => ({ ...x, barrio_id: null }));
    apiScrr.opciones(ciclo).then((o) => setOp((p) => (p ? { ...p, barrios: o.barrios } : o))).catch((e) => setMensaje(avisoDeError(e)));
  }, [ciclo]);

  const cambiar = (x: Partial<Filtros>) => { setF((a) => ({ ...a, ...x })); setPrevia(null); };
  async function verPrevia() {
    if (ciclo === null) return;
    setOcupado(true); setMensaje(null); setOk(null);
    try { setPrevia(await apiScrr.previa(ciclo, f)); } catch (e) { setMensaje(avisoDeError(e)); } finally { setOcupado(false); }
  }
  async function generar() {
    if (ciclo === null || !actividad) return;
    setOcupado(true); setMensaje(null); setOk(null);
    try { const r = await apiScrr.generar(ciclo, f, actividad); setOk(`Lista de ${r.actividad} generada: ${num(r.contratos)} contratos, ${pesos(r.saldo_total)}.`); setPrevia(null); setActividad(""); await cargarCorridas(); }
    catch (e) { setMensaje(avisoDeError(e)); } finally { setOcupado(false); }
  }
  async function salida(c: Corrida, formato: "excel" | "impresion") {
    setMensaje(null);
    // la ventana de impresión se abre en el mismo toque, antes de esperar al servidor (si no, el navegador la bloquea)
    const w = formato === "impresion" ? window.open("", "_blank") : null;
    if (formato === "impresion" && !w) { setMensaje("El navegador bloqueó la ventana de impresión: permita ventanas emergentes para el geoportal."); return; }
    try { const l = await apiScrr.lista(c.corrida_id, formato); if (formato === "excel") await descargarExcel(l); else imprimir(l, w!); }
    catch (e) { w?.close(); setMensaje(avisoDeError(e)); }
  }

  const cicloSel = op?.ciclos.find((c) => c.ciclo === ciclo);
  return (
    <div className="scrr-panel">
      <section className="scrr-tarjeta">
        <h3>Selección</h3>
        {!op ? <p className="scrr-suave">Consultando…</p> : !op.foto ? <p className="scrr-aviso">Todavía no hay una cartera aplicada: cargue la del día en «Carga del día».</p> : (
          <p className="scrr-suave">Cartera del {fecha(op.foto)} · facturación del período {op.facturacion_periodo ?? "—"} · ciclos de {op.ciclos.length ? "este mes" : "—"} según el calendario.</p>
        )}
        {mensaje && <p className="scrr-error" role="alert">{mensaje}</p>}
        {ok && <p className="scrr-suave" role="status" data-bloque="ok">{ok}</p>}
        {op && op.foto && op.ciclos.length === 0 && <p className="scrr-aviso">El calendario no tiene ciclos para este período: agréguelos en «Calendario».</p>}
        {op && op.foto && op.ciclos.length > 0 && <>
          <div className="scrr-fila">
            <label>Ciclo (uno a la vez)
              <select value={ciclo ?? ""} onChange={(e) => setCiclo(Number(e.target.value))} data-campo="ciclo">
                {op.ciclos.map((c) => <option key={c.ciclo} value={c.ciclo}>{String(c.ciclo).padStart(2, "0")} · suspensión {fecha(c.fecha_suspension)}{c.en_ventana ? " · en ventana" : ""} · {num(c.con_saldo)} con saldo</option>)}
              </select></label>
            <label>Barrio
              <select value={f.barrio_id ?? ""} onChange={(e) => cambiar({ barrio_id: e.target.value ? Number(e.target.value) : null })} data-campo="barrio">
                <option value="">Todos</option>{op.barrios.filter((b) => b.id !== null).map((b) => <option key={b.id!} value={b.id!}>{b.nombre} ({num(b.contratos)})</option>)}
              </select></label>
          </div>
          {cicloSel && <p className="scrr-suave">Pago oportuno {fecha(cicloSel.pago_oportuno)} · suspensión {fecha(cicloSel.fecha_suspension)}{cicloSel.en_ventana ? " · el ciclo está en ventana de suspensión" : " · todavía no entra en ventana"}.</p>}
          <div className="scrr-fila">
            <label>Rango sobre
              <select value={f.modo} onChange={(e) => cambiar(e.target.value === "meses" ? { modo: "meses", desde: 1, hasta: 6 } : { modo: "monto", desde: 0, hasta: null })} data-campo="modo">
                <option value="meses">Facturas vencidas</option><option value="monto">Saldo pendiente ($)</option></select></label>
            <label>Desde<input inputMode="numeric" value={f.desde ?? ""} onChange={(e) => cambiar({ desde: e.target.value === "" ? null : Number(e.target.value.replace(/\D/g, "")) })} data-campo="desde" /></label>
            <label>Hasta<input inputMode="numeric" value={f.hasta ?? ""} placeholder="sin tope" onChange={(e) => cambiar({ hasta: e.target.value === "" ? null : Number(e.target.value.replace(/\D/g, "")) })} data-campo="hasta" /></label>
            {f.modo === "meses" && <div className="scrr-rangos">{RANGOS.map(([t, d, h]) => <button key={t} className="scrr-btn scrr-sec" onClick={() => cambiar({ desde: d, hasta: h })}>{t}</button>)}</div>}
          </div>
          <div className="scrr-fila">
            <label>Saldo mínimo
              <select value={f.monto_minimo} onChange={(e) => cambiar({ monto_minimo: Number(e.target.value) })} data-campo="minimo">
                {[5000, 10000, 20000].map((m) => <option key={m} value={m}>{pesos(m)}</option>)}</select></label>
            <label>Segmento (aproximado)
              <select value={f.segmento} onChange={(e) => cambiar({ segmento: e.target.value })} data-campo="segmento">
                <option value="todos">Todos</option><option value="pagaron_mes_pasado_no_este">Pagaron el mes pasado y este no</option>
                <option value="cero_a_un_mes">0 a 1 factura vencida</option><option value="menos_de_n">Menos de N facturas vencidas</option></select></label>
            {f.segmento === "menos_de_n" && <label>N<input inputMode="numeric" value={f.n ?? 8} onChange={(e) => cambiar({ n: Number(e.target.value.replace(/\D/g, "")) || 8 })} /></label>}
          </div>
          <details className="scrr-guia"><summary>Guía (referencia, no regla)</summary>
            <p>Norma (Res. CRA 943 de 2021, art. 2): no pagar después del vencimiento → suspensión; reiteración → corte; autorreconexión o fraude → corte drástico.
               Práctica de EMDUPAR: más de 3 facturas vencidas → corte; más de 8 → corte drástico. La actividad la escoge usted.</p></details>
          <button className="scrr-btn" disabled={ocupado || ciclo === null} onClick={() => void verPrevia()} data-accion="previa">{ocupado && !previa ? "Calculando…" : "Ver vista previa"}</button>
        </>}
        {previa && (
          <div className="scrr-resumen" data-bloque="previa">
            <h4>Vista previa · ciclo {String(previa.ciclo).padStart(2, "0")} · {num(previa.universo)} contratos con saldo</h4>
            <p className="scrr-suave">Solo conteos: la lista con nombre y dirección sale al generarla.</p>
            <div className="scrr-tabla-wrap"><table className="scrr-tabla" data-tabla="embudo"><thead><tr><th>Paso</th><th>Contratos</th><th>Saldo</th></tr></thead>
              <tbody>{PASOS.filter(([k]) => previa.embudo[k]).map(([k, t]) => <tr key={k} data-paso={k} className={k === "candidato" ? "scrr-cand" : ""}><td>{t}</td><td>{num(previa.embudo[k].contratos)}</td><td>{pesos(previa.embudo[k].saldo)}</td></tr>)}</tbody></table></div>
            <dl>
              <dt>Candidatos</dt><dd data-dato="candidatos">{num(previa.candidatos)} · {pesos(previa.saldo_candidatos)}</dd>
              <dt>Abonaron (marcados, no excluidos)</dt><dd>{num(previa.marcados_abono)} desde la fecha del archivo · {num(previa.marcados_abono_desde_suspension)} desde la suspensión</dd>
              <dt>Por facturas vencidas</dt><dd>{Object.entries(previa.por_vencidas).map(([k, v]) => `${k}: ${num(v)}`).join(" · ") || "—"}</dd>
            </dl>
            {previa.candidatos > 0 && <>
              <fieldset className="scrr-actividad"><legend>Actividad a realizar</legend>
                {(op?.actividades ?? []).map((a) => <label key={a.codigo}><input type="radio" name="actividad" value={a.codigo} checked={actividad === a.codigo} onChange={() => setActividad(a.codigo)} data-actividad={a.codigo} /> {a.nombre}</label>)}
              </fieldset>
              <button className="scrr-btn" disabled={ocupado || !actividad} onClick={() => void generar()} data-accion="generar">Generar la lista</button>
            </>}
          </div>
        )}
      </section>
      <section className="scrr-tarjeta">
        <h3>Listas generadas</h3>
        <p className="scrr-suave">Llevan nombre y dirección para la visita y la deuda del contrato. Cada descarga e impresión queda registrada.</p>
        <div className="scrr-tabla-wrap">
          <table className="scrr-tabla" data-tabla="corridas"><thead><tr><th>Generada</th><th>Actividad</th><th>Ciclo</th><th>Contratos</th><th>Saldo</th><th></th></tr></thead>
            <tbody>{corridas.map((c) => (
              <tr key={c.corrida_id} data-corrida={c.corrida_id}><td>{fechaHora(c.creada_en)}</td><td>{c.actividad}</td><td>{String(c.ciclo).padStart(2, "0")}</td><td>{num(c.contratos)}</td><td>{pesos(c.saldo_total)}</td>
                <td><button className="scrr-link" onClick={() => void salida(c, "excel")} data-accion="excel">Descargar Excel</button>
                    <button className="scrr-link" onClick={() => void salida(c, "impresion")} data-accion="imprimir">Imprimir</button></td></tr>))}
              {corridas.length === 0 && <tr><td colSpan={6} className="scrr-suave">Todavía no hay listas.</td></tr>}</tbody></table>
        </div>
      </section>
    </div>
  );
}
