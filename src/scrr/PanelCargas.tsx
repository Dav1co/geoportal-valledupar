import { useCallback, useEffect, useRef, useState } from "react";
import { apiScrr, avisoDeError, ErrorScrr, type CargaFila, type CargasHoy, type ContextoScrr, type ResumenServidor } from "./apiScrr";
import type { Resumen, TipoCarga } from "./lector";
import type { Saliente } from "./lector.worker";
import { descargarPlantilla } from "./plantilla";
import { NOMBRE_ESTADO, NOMBRE_TIPO, ayerBogota, fecha, fechaHora, hoyBogota, num, pesos } from "./formato";

// «Carga del día» del modo «Cartera» (Motor SCRR, corte 2). Flujo: plantilla → elegir el Excel → lectura y validación en un Web Worker (SHA-256, columnas exactas de la
// plantilla) → envío por lotes idempotentes con avance, pausa y reanudación → validación del servidor → confirmar → aplicar POR LOTES → cerrar.
// La cartera actualiza también la cartera de suscripción (P4 del 22-nov): si en el archivo faltan más contratos de los normales, el cierre pide confirmarlo con motivo.
// Una carga de cartera aplicada (o a medias) se puede revertir y anular con motivo; pagos y actividades acumulan y se corrigen con otra carga.

type Fase = "inicio" | "leyendo" | "leido" | "enviando" | "pausada" | "validado" | "aplicando" | "aplicacion_pausada" | "confirmar_salidas" | "aplicada" | "error";
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function conReintentos<T>(f: () => Promise<T>): Promise<T> {
  for (let intento = 0; ; intento++) {
    try { return await f(); }
    catch (e) { const reintentable = e instanceof ErrorScrr && (e.tipo === "red" || e.tipo === "servidor"); if (!reintentable || intento >= 3) throw e; await esperar(1000 * 2 ** intento); }
  }
}
const ETIQUETA: Record<string, string> = {
  historial: "Contratos con saldo al historial", suscripcion_filas_nuevas: "Filas nuevas en la cartera de suscripción", suscripcion_contratos_salientes: "Contratos que salieron de la cartera",
  suscripcion_filas_retiradas: "Filas retiradas (con respaldo)", filas_de_salida_historial: "Contratos que dejaron de tener saldo", pagos_nuevos: "Pagos nuevos",
  pagos_ya_existentes: "Pagos que ya estaban (no se duplican)", actas_nuevas: "Actas nuevas", actas_ya_existentes: "Actas que ya estaban", rechazadas: "Filas rechazadas",
};

export function PanelCargas({ ctx }: { ctx: ContextoScrr }) {
  const [hoy, setHoy] = useState<CargasHoy | null>(null);
  const [lista, setLista] = useState<CargaFila[]>([]);
  const [tipo, setTipo] = useState<TipoCarga>("cartera");
  const [fechaDato, setFechaDato] = useState(hoyBogota());
  const [archivo, setArchivo] = useState<File | null>(null);
  const [fase, setFase] = useState<Fase>("inicio");
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [pct, setPct] = useState(0);
  const [local, setLocal] = useState<{ resumen: Resumen; sha256: string; nombre: string; bytes: number; msLectura: number; hojasOmitidas: string[] } | null>(null);
  const [servidor, setServidor] = useState<ResumenServidor | null>(null);
  const [cargaId, setCargaId] = useState<string | null>(null);
  const [lotes, setLotes] = useState<{ hechos: number; total: number }>({ hechos: 0, total: 0 });
  const [resultado, setResultado] = useState<Record<string, unknown> | null>(null);
  const [reemplazo, setReemplazo] = useState<{ id: string; motivo: string } | null>(null);
  const [confirmo, setConfirmo] = useState(false);
  const [salidas, setSalidas] = useState<{ mensaje: string; motivo: string } | null>(null);
  const [deshacer, setDeshacer] = useState<{ carga: CargaFila; motivo: string; avance: string | null } | null>(null);
  const worker = useRef<Worker | null>(null);
  const pausar = useRef(false);
  const esperaLote = useRef<((f: Record<string, string>[]) => void) | null>(null);
  const p = ctx.parametros;

  const refrescar = useCallback(async () => {
    try { const [h, l] = await Promise.all([apiScrr.cargasHoy(), apiScrr.cargas(30)]); setHoy(h); setLista(l.cargas); } catch (e) { setMensaje(avisoDeError(e)); }
  }, []);
  useEffect(() => { void refrescar(); return () => { worker.current?.terminate(); }; }, [refrescar]);
  useEffect(() => { setFechaDato(tipo === "cartera" ? hoyBogota() : ayerBogota()); }, [tipo]);

  function reiniciar() {
    worker.current?.terminate(); worker.current = null; setFase("inicio"); setArchivo(null); setLocal(null); setServidor(null); setCargaId(null); setPct(0); setLotes({ hechos: 0, total: 0 });
    setResultado(null); setReemplazo(null); setConfirmo(false); setSalidas(null); setMensaje(null); pausar.current = false;
  }

  function leerArchivo() {
    if (!archivo) return;
    setMensaje(null); setLocal(null); setServidor(null); setFase("leyendo"); setPct(0);
    worker.current?.terminate();
    const w = new Worker(new URL("./lector.worker.ts", import.meta.url), { type: "module" });
    worker.current = w;
    w.onmessage = (ev: MessageEvent<Saliente>) => {
      const m = ev.data;
      if (m.op === "progreso") setPct(m.pct);
      else if (m.op === "listo") { setLocal({ resumen: m.resumen, sha256: m.sha256, nombre: m.nombre, bytes: m.bytes, msLectura: m.msLectura, hojasOmitidas: m.hojasOmitidas }); setPct(100); setFase("leido"); }
      else if (m.op === "error") { setMensaje(m.mensaje); setFase("error"); }
      else if (m.op === "lote") { esperaLote.current?.(m.filas); esperaLote.current = null; }
    };
    w.onerror = () => { setMensaje("No se pudo leer el archivo en este navegador."); setFase("error"); };
    w.postMessage({ op: "leer", tipo, archivo, nombre: archivo.name, comodin: String(p.comodin_contrato), tope: p.tope_filas_archivo });
  }
  const pedirLote = (n: number, tamano: number) => new Promise<Record<string, string>[]>((res) => { esperaLote.current = res; worker.current?.postMessage({ op: "lote", n, tamano }); });

  async function enviar(reemplaza?: { id: string; motivo: string }) {
    if (!local) return;
    setMensaje(null); setFase("enviando"); pausar.current = false;
    try {
      const ini = await apiScrr.iniciar({ tipo, fecha_dato: fechaDato, nombre: local.nombre, sha256: local.sha256, filas: local.resumen.filas, reemplaza: reemplaza?.id ?? null, motivo: reemplaza?.motivo ?? null });
      setCargaId(ini.carga_id); setReemplazo(null);
      const est = await apiScrr.estado(ini.carga_id);
      const recibidos = new Set(est.lotes_recibidos);
      setLotes({ hechos: recibidos.size, total: ini.lotes });
      for (let n = 1; n <= ini.lotes; n++) {
        if (recibidos.has(n)) continue;
        if (pausar.current) { setFase("pausada"); return; }
        const filas = await pedirLote(n, ini.lote_filas);
        await conReintentos(() => apiScrr.lote(ini.carga_id, tipo, n, filas));
        recibidos.add(n); setLotes({ hechos: recibidos.size, total: ini.lotes });
      }
      const v = await conReintentos(() => apiScrr.validar(ini.carga_id));
      setServidor(v); setFase("validado");
    } catch (e) {
      if (e instanceof ErrorScrr && e.tipo === "conflicto" && /reemplazarla/i.test(e.message)) {
        const vigente = lista.find((c) => c.tipo === tipo && c.fecha_dato === fechaDato && c.estado === "aplicada");
        if (vigente && tipo === "cartera") { setReemplazo({ id: vigente.carga_id, motivo: "" }); setMensaje(e.message); setFase("leido"); return; }
      }
      setMensaje(avisoDeError(e)); setFase(lotes.hechos > 0 ? "pausada" : "leido");
    }
  }

  /** Aplica los lotes que falten y cierra. Sirve también para continuar una carga que quedó «aplicando» (no necesita el archivo). */
  async function aplicar(id: string, confirmarSalidas?: string) {
    setFase("aplicando"); setMensaje(null); pausar.current = false; setCargaId(id);
    try {
      const est = await apiScrr.estado(id);
      const total = Number((est.resumen as { lotes?: number } | null)?.lotes ?? Math.ceil(est.filas / p.lote_filas));
      const hechos = new Set(est.lotes_aplicados);
      setLotes({ hechos: hechos.size, total });
      for (let n = 1; n <= total; n++) {
        if (hechos.has(n)) continue;
        if (pausar.current) { setFase("aplicacion_pausada"); void refrescar(); return; }
        await conReintentos(() => apiScrr.aplicarLote(id, n));
        hechos.add(n); setLotes({ hechos: hechos.size, total });
      }
      const r = await apiScrr.cerrar(id, confirmarSalidas !== undefined, confirmarSalidas ?? null);
      setResultado(r.resultado); setSalidas(null); setFase("aplicada"); void refrescar();
    } catch (e) {
      if (e instanceof ErrorScrr && e.tipo === "conflicto" && /no vienen en el archivo/.test(e.message)) { setSalidas({ mensaje: e.message, motivo: "" }); setFase("confirmar_salidas"); return; }
      setMensaje(avisoDeError(e)); setFase("aplicacion_pausada"); void refrescar();
    }
  }

  /** Cartera aplicada o a medias: devolver la cartera de suscripción a como estaba (por tandas) y anular la carga. Pagos y actividades: anular si no se aplicaron. */
  async function deshacerCarga() {
    if (!deshacer) return;
    const { carga, motivo } = deshacer;
    setDeshacer((d) => d && { ...d, avance: "Procesando…" });
    try {
      if (carga.tipo === "cartera" && ["aplicada", "aplicando"].includes(carga.estado)) {
        for (let i = 0; i < 200; i++) {
          const r = await conReintentos(() => apiScrr.revertir(carga.carga_id, motivo));
          setDeshacer((d) => d && { ...d, avance: `Devolviendo la cartera de suscripción… quedan ${num(r.pendientes)} contratos` });
          if (r.pendientes === 0) break;
        }
      }
      await apiScrr.anular(carga.carga_id, motivo);
      setDeshacer(null); if (carga.carga_id === cargaId) reiniciar(); void refrescar();
    } catch (e) { setMensaje(avisoDeError(e)); setDeshacer((d) => d && { ...d, avance: null }); }
  }

  const r = local?.resumen;
  const bloqueado = ["leyendo", "enviando", "aplicando"].includes(fase);
  const avance = lotes.total ? Math.round((lotes.hechos * 100) / lotes.total) : 0;
  const abiertas = (hoy?.tipos ?? []).filter((t) => t.abierta);

  return (
    <div className="scrr-panel">
      <section className="scrr-tarjeta">
        <h3>¿Falta cargar hoy?</h3>
        {!hoy ? <p className="scrr-suave">Consultando…</p> : (
          <ul className="scrr-hoy">
            {hoy.tipos.map((t) => (
              <li key={t.tipo} className={t.al_dia ? "ok" : "falta"} data-tipo={t.tipo}>
                <strong>{NOMBRE_TIPO[t.tipo]}</strong>
                <span>{t.al_dia ? "Al día" : "Falta cargar"} · último dato: {fecha(t.ultima_fecha_dato)}{t.aplicada_en ? ` (aplicado ${fechaHora(t.aplicada_en)})` : ""} · se espera desde {fecha(t.requerida_desde)}</span>
                {t.abierta && <em>Hay una carga abierta sin terminar.</em>}
              </li>
            ))}
          </ul>
        )}
        <p className="scrr-suave">Orden diario: primero la cartera, después los pagos y por último las actividades. Hora de Bogotá.</p>
      </section>

      {p.carga_pausada && <p className="scrr-aviso">Las cargas están en pausa. Por ahora solo se puede consultar.</p>}

      <section className="scrr-tarjeta">
        <h3>Nueva carga</h3>
        <div className="scrr-fila">
          <label>Archivo
            <select value={tipo} disabled={bloqueado || fase !== "inicio"} onChange={(e) => setTipo(e.target.value as TipoCarga)} data-campo="tipo">
              <option value="cartera">Cartera del día</option><option value="pagos">Pagos del día</option><option value="actividades">Actividades (efectivas e inefectivas)</option>
            </select>
          </label>
          <label>Fecha del dato
            <input type="date" value={fechaDato} max={hoyBogota()} disabled={bloqueado || fase !== "inicio"} onChange={(e) => setFechaDato(e.target.value)} data-campo="fecha" />
          </label>
          <label className="scrr-archivo">Libro de Excel (.xlsx)
            <input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" disabled={bloqueado || fase !== "inicio"} onChange={(e) => setArchivo(e.target.files?.[0] ?? null)} data-campo="archivo" />
          </label>
        </div>
        <p className="scrr-suave">
          Use la plantilla: el archivo debe traer <strong>exactamente</strong> sus columnas. <button className="scrr-link" onClick={() => void descargarPlantilla(tipo)} data-accion="plantilla">Descargar la plantilla de {NOMBRE_TIPO[tipo].toLowerCase()}</button>
          {tipo === "cartera" && <> La cartera también actualiza la cartera de suscripción (con nombre y dirección), que reemplaza al cargue por script.</>}
          {tipo === "pagos" && <> Plantilla provisional (contrato, fecha de pago y monto) mientras llega el archivo real.</>}
        </p>

        {fase === "inicio" && <button className="scrr-btn" disabled={!archivo} onClick={leerArchivo} data-accion="leer">Leer y validar archivo</button>}
        {(fase === "leyendo" || fase === "enviando" || fase === "aplicando") && (
          <div className="scrr-progreso" role="progressbar" aria-valuenow={fase === "leyendo" ? pct : avance} aria-valuemin={0} aria-valuemax={100}>
            <div style={{ width: `${fase === "leyendo" ? pct : avance}%` }} />
            <span>{fase === "leyendo" ? `Leyendo el archivo… ${pct} %` : fase === "enviando" ? `Enviando lote ${num(lotes.hechos)} de ${num(lotes.total)}` : `Aplicando lote ${num(lotes.hechos)} de ${num(lotes.total)}`}</span>
          </div>
        )}
        {(fase === "enviando" || fase === "aplicando") && <button className="scrr-btn scrr-sec" onClick={() => { pausar.current = true; }} data-accion="pausar">Pausar después de este lote</button>}

        {r && !["inicio", "leyendo", "error"].includes(fase) && (
          <div className="scrr-resumen" data-bloque="local">
            <h4>Lo que se leyó en este computador</h4>
            <dl>
              <dt>Filas leídas</dt><dd data-dato="filas">{num(r.filas)}</dd>
              <dt>Rechazadas</dt><dd>{num(r.rechazadas)} ({num(r.pctRechazadas)} %)</dd>
              <dt>Contratos distintos válidos</dt><dd>{num(r.contratosDistintos)}</dd>
              {r.tipo === "cartera" && <><dt>Con saldo pendiente</dt><dd>{num(r.extra.con_saldo_pendiente)}</dd><dt>Con facturas vencidas</dt><dd>{num(r.extra.con_facturas_vencidas)}</dd>
                <dt>Con valor en reclamo</dt><dd>{num(r.extra.con_reclamo)}</dd><dt>Comodín o categoría «-1»</dt><dd>{num(r.extra.comodin_o_categoria_menos_1)}</dd></>}
              {r.tipo === "pagos" && <><dt>Pagos de</dt><dd>{fecha(String(r.extra.primera_fecha ?? ""))} a {fecha(String(r.extra.ultima_fecha ?? ""))}</dd><dt>Monto total</dt><dd>{pesos(r.extra.monto_total)}</dd></>}
              {r.tipo === "actividades" && <><dt>Efectivas / inefectivas</dt><dd>{num(r.extra.efectivas)} / {num(r.extra.inefectivas)}</dd><dt>Cortes drásticos</dt><dd>{num(r.extra.cortes_drasticos)}</dd></>}
              <dt>Hojas leídas</dt><dd>{r.hojas.join(", ")}{local && local.hojasOmitidas.length > 0 ? ` (sin la columna Contrato, se omiten: ${local.hojasOmitidas.join(", ")})` : ""}</dd>
              <dt>Huella del archivo</dt><dd className="mono">{local?.sha256.slice(0, 16)}…</dd>
              <dt>Lectura</dt><dd data-dato="lectura">{num(Math.round((local?.msLectura ?? 0) / 100) / 10)} s · {num(Math.round((local?.bytes ?? 0) / 1048576 * 10) / 10)} MB</dd>
            </dl>
            {Object.keys(r.causas).length > 0 && <ul className="scrr-causas">{Object.entries(r.causas).map(([c, n]) => <li key={c}>{num(n)} × {c}</li>)}</ul>}
          </div>
        )}

        {fase === "leido" && !reemplazo && <button className="scrr-btn" disabled={r?.filas === 0} onClick={() => void enviar()} data-accion="enviar">Enviar al servidor y validar</button>}
        {reemplazo && (
          <div className="scrr-reemplazo">
            <p>Ya hay una cartera aplicada con esa fecha. Para reemplazarla escriba el motivo (queda registrado; la anterior se oculta, no se borra).</p>
            <input type="text" placeholder="Motivo (10 a 300 caracteres)" value={reemplazo.motivo} onChange={(e) => setReemplazo({ ...reemplazo, motivo: e.target.value })} maxLength={300} data-campo="motivo-reemplazo" />
            <button className="scrr-btn" disabled={reemplazo.motivo.trim().length < 10} onClick={() => void enviar({ id: reemplazo.id, motivo: reemplazo.motivo.trim() })}>Reemplazar la carga vigente</button>
          </div>
        )}
        {fase === "pausada" && <button className="scrr-btn" onClick={() => void enviar()} data-accion="reanudar">Reanudar el envío</button>}

        {servidor && fase === "validado" && (
          <div className="scrr-resumen" data-bloque="servidor">
            <h4>Validación del servidor</h4>
            <dl>
              <dt>Filas recibidas / esperadas</dt><dd>{num(servidor.filas_en_paso)} / {num(servidor.filas_esperadas)}</dd>
              <dt>Rechazadas</dt><dd>{num(servidor.filas_rechazadas)} ({num(servidor.pct_rechazadas)} %)</dd>
              {servidor.lotes_faltantes.length > 0 && <><dt>Lotes faltantes</dt><dd>{servidor.lotes_faltantes.join(", ")}</dd></>}
              {tipo === "cartera" && <><dt>Con saldo pendiente</dt><dd>{num(servidor.con_saldo_pendiente as number)}</dd>
                <dt>Foto anterior</dt><dd>{servidor.foto_anterior ? `${fecha(String(servidor.foto_anterior))} (${num(servidor.con_saldo_en_la_anterior as number)} con saldo)` : "no hay"}</dd>
                <dt>Cartera de suscripción hoy</dt><dd>{num(servidor.filas_en_cartera_suscripcion_hoy as number)} filas</dd></>}
              {tipo === "pagos" && <><dt>Monto total</dt><dd>{pesos(servidor.monto_total as number)}</dd><dt>Idénticos dentro del archivo</dt><dd>{num(servidor.identicos_en_el_archivo as number)}</dd></>}
              {tipo === "actividades" && <><dt>Repetidas dentro del archivo</dt><dd>{num(servidor.repetidas_en_el_archivo as number)}</dd></>}
            </dl>
            {Object.keys(servidor.causas_rechazo).length > 0 && <ul className="scrr-causas">{Object.entries(servidor.causas_rechazo).map(([c, n]) => <li key={c}>{num(n)} × {c}</li>)}</ul>}
            {servidor.puede_aplicar ? (
              <>
                <label className="scrr-confirma"><input type="checkbox" checked={confirmo} onChange={(e) => setConfirmo(e.target.checked)} data-campo="confirmo" /> Revisé el resumen y confirmo que este archivo es el del {fecha(fechaDato)}.</label>
                <button className="scrr-btn" disabled={!confirmo} onClick={() => cargaId && void aplicar(cargaId)} data-accion="aplicar">Aplicar</button>
              </>
            ) : <p className="scrr-error">El servidor no permite aplicar este archivo: revise las filas rechazadas o los lotes faltantes. Puede anular la carga y corregir el archivo.</p>}
          </div>
        )}
        {fase === "aplicacion_pausada" && cargaId && <button className="scrr-btn" onClick={() => void aplicar(cargaId)} data-accion="continuar">Continuar la aplicación</button>}
        {fase === "confirmar_salidas" && salidas && cargaId && (
          <div className="scrr-reemplazo" data-bloque="salidas">
            <p className="scrr-aviso">{salidas.mensaje}</p>
            <p>Si es correcto (por ejemplo, contratos retirados), escriba el motivo: esos contratos salen de la cartera de suscripción con respaldo y se pueden devolver.</p>
            <input type="text" placeholder="Motivo (10 a 300 caracteres)" value={salidas.motivo} onChange={(e) => setSalidas({ ...salidas, motivo: e.target.value })} maxLength={300} data-campo="motivo-salidas" />
            <button className="scrr-btn" disabled={salidas.motivo.trim().length < 10} onClick={() => void aplicar(cargaId, salidas.motivo.trim())} data-accion="confirmar-salidas">Confirmar y cerrar la carga</button>
          </div>
        )}
        {fase === "aplicada" && resultado && (
          <div className="scrr-resumen scrr-ok" data-bloque="aplicada"><h4>Carga aplicada</h4>
            <ul>{Object.entries(resultado).filter(([, v]) => typeof v === "number").map(([k, v]) => <li key={k}>{ETIQUETA[k] ?? k.replace(/_/g, " ")}: {num(v as number)}</li>)}</ul>
            <button className="scrr-btn" onClick={reiniciar}>Cargar otro archivo</button></div>
        )}
        {mensaje && <p className="scrr-error" role="alert">{mensaje}</p>}
        {fase !== "inicio" && !bloqueado && !["aplicada", "aplicacion_pausada", "confirmar_salidas"].includes(fase) && <button className="scrr-link" onClick={reiniciar}>Empezar de nuevo con otro archivo</button>}
      </section>

      {abiertas.length > 0 && fase === "inicio" && (
        <section className="scrr-tarjeta" data-bloque="abiertas">
          <h3>Cargas sin terminar</h3>
          {abiertas.map((t) => { const c = lista.find((x) => x.carga_id === t.abierta); return c ? (
            <p key={t.tipo}>{NOMBRE_TIPO[t.tipo]} del {fecha(c.fecha_dato)} ({NOMBRE_ESTADO[c.estado] ?? c.estado}).{" "}
              {c.estado === "aplicando" || c.estado === "validada" ? <button className="scrr-link" onClick={() => void aplicar(c.carga_id)}>Continuar la aplicación</button>
                : <span className="scrr-suave">Vuelva a elegir el mismo archivo para seguir enviándolo, o anúlela.</span>}</p>) : null; })}
        </section>
      )}

      <section className="scrr-tarjeta">
        <h3>Últimas cargas</h3>
        <div className="scrr-tabla-wrap">
          <table className="scrr-tabla"><thead><tr><th>Archivo</th><th>Tipo</th><th>Fecha del dato</th><th>Filas</th><th>Estado</th><th>Creada</th><th></th></tr></thead>
            <tbody>
              {lista.map((c) => (
                <tr key={c.carga_id} data-carga={c.carga_id}><td>{c.archivo}{c.version > 1 ? ` (v${c.version})` : ""}</td><td>{NOMBRE_TIPO[c.tipo]}</td><td>{fecha(c.fecha_dato)}</td><td>{num(c.filas)}</td>
                  <td>{NOMBRE_ESTADO[c.estado] ?? c.estado}</td><td>{fechaHora(c.creada_en)}</td>
                  <td>{(["en_paso", "validada"].includes(c.estado) || (c.tipo === "cartera" && ["aplicada", "aplicando"].includes(c.estado))) &&
                    <button className="scrr-link" onClick={() => setDeshacer({ carga: c, motivo: "", avance: null })} data-accion="deshacer">{c.tipo === "cartera" && ["aplicada", "aplicando"].includes(c.estado) ? "Revertir y anular" : "Anular"}</button>}</td></tr>
              ))}
              {lista.length === 0 && <tr><td colSpan={7} className="scrr-suave">Todavía no hay cargas.</td></tr>}
            </tbody></table>
        </div>
        {deshacer && (
          <div className="scrr-reemplazo" data-bloque="deshacer">
            <p>{deshacer.carga.tipo === "cartera" && ["aplicada", "aplicando"].includes(deshacer.carga.estado)
              ? "La cartera de suscripción vuelve a como estaba antes de esta carga y la carga queda anulada (su historial se oculta, no se borra). Exige un motivo."
              : "Anular exige un motivo (queda registrado; nada se borra)."}</p>
            <input type="text" placeholder="Motivo (10 a 300 caracteres)" value={deshacer.motivo} onChange={(e) => setDeshacer({ ...deshacer, motivo: e.target.value })} maxLength={300} data-campo="motivo-deshacer" />
            {deshacer.avance && <p className="scrr-suave">{deshacer.avance}</p>}
            <button className="scrr-btn" disabled={deshacer.motivo.trim().length < 10 || deshacer.avance !== null} onClick={() => void deshacerCarga()} data-accion="confirmar-deshacer">Confirmar</button>
            <button className="scrr-link" onClick={() => setDeshacer(null)}>Cancelar</button>
          </div>
        )}
      </section>
    </div>
  );
}
