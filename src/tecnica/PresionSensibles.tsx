import { useEffect, useState } from "react";
import "./cierre.css";
import { apiFase2, type AlertasPresion as Alertas, type EstadoSensible, type NivelAlerta, type Sensible, type Sensibles } from "./apiCierre";
import { ErrorTec } from "./apiTecnica";

// Corte 9b, Fase 2 (la base es del Code A): dos lecturas del supervisor de distribución y del administrador en el Dashboard distribución.
//   · Alertas de presión: presión de MODELO (Plan Maestro 2014), NO medida, clasificada con los cuatro parámetros editables. Siempre lo dice.
//   · Usuarios sensibles: la bandeja (hospitales, clínicas, colegios…). El supervisor confirma, corrige el tipo, descarta con motivo o agrega uno a mano.
//     Aquí nunca hay nombres: contrato, tipo y la palabra que coincidió. El nombre solo se ve en la tarjeta auditada del contrato del geovisor.
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 1 });
const err = (e: unknown) => (e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor de distribución o el administrador ven esta sección." : e instanceof Error ? e.message : "No se pudo completar.");
const NIVELES: { c: NivelAlerta; n: string; signo: string; clase: string }[] = [
  { c: "baja_roja", n: "Presión baja crítica", signo: "menos de", clase: "ps-rojo" }, { c: "baja_naranja", n: "Presión baja", signo: "menos de", clase: "ps-naranja" },
  { c: "alta_naranja", n: "Presión alta", signo: "más de", clase: "ps-naranja" }, { c: "alta_roja", n: "Presión alta crítica", signo: "más de", clase: "ps-rojo" }];

export function AlertasPresion() {
  const [esc, setEsc] = useState<"existente" | "futura">("existente");
  const [d, setD] = useState<Alertas | null>(null); const [error, setError] = useState<string | null>(null); const [todos, setTodos] = useState(false);
  useEffect(() => { let vivo = true; setD(null); setError(null); setTodos(false); apiFase2.alertas(esc).then((r) => { if (vivo) setD(r); }).catch((e) => { if (vivo) setError(err(e)); }); return () => { vivo = false; }; }, [esc]);
  const fuera = d ? NIVELES.reduce((s, n) => s + (d.niveles[n.c] ?? 0), 0) : 0;
  const peores = d ? (todos ? d.peores : d.peores.slice(0, 15)) : [];
  return (
    <>
      <section className="tec-tarjeta ps" aria-labelledby="ps-tit" data-testid="alertas-presion">
        <h2 id="ps-tit">Alertas de presión</h2>
        <p className="tec-aviso tec-aviso-info ps-modelo" role="note" data-testid="ps-modelo"><strong>Modelo, no medido.</strong> Son presiones calculadas por el modelo hidráulico{d ? ` (${d.fuente})` : ""}: no vienen de sensores ni de mediciones de hoy.</p>
        <div className="dan-fila" role="group" aria-label="Red del modelo">
          {(["existente", "futura"] as const).map((e) => <button key={e} type="button" className="dan-opcion" aria-pressed={esc === e} onClick={() => setEsc(e)}>{e === "existente" ? "Red existente" : "Red futura"}</button>)}
        </div>
        {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : !d ? <p className="tec-sub" role="status">Cargando…</p> : !d.cargado ? <p className="red-vacio">Todavía no está cargada la presión del modelo.</p> : (
          <>
            <p className="red-texto">De {nf.format(d.nodos)} nodos del modelo, <strong>{nf.format(fuera)}</strong> quedan fuera del rango.</p>
            <dl className="ps-niveles">{NIVELES.map((n) => (
              <div key={n.c} className={n.clase} data-nivel={n.c}><dt>{n.n}<span>{n.signo} {nf.format(d.umbrales[n.c])} m.c.a.</span></dt><dd>{nf.format(d.niveles[n.c] ?? 0)}</dd></div>))}</dl>
            <p className="tec-ayuda">Los cuatro límites se cambian en la pestaña Parámetros.</p>
          </>)}
      </section>
      {d?.cargado && d.peores.length ? (
        <section className="tec-tarjeta ps" aria-labelledby="ps-peores">
          <h2 id="ps-peores">Nodos más alejados del rango</h2>
          <div className="ps-tabla-caja"><table className="ps-tabla">
            <thead><tr><th scope="col">Nodo del modelo</th><th scope="col">Alerta</th><th scope="col">Mínima del día</th><th scope="col">Máxima del día</th></tr></thead>
            <tbody>{peores.map((p) => { const n = NIVELES.find((x) => x.c === p.nivel); return (
              <tr key={p.nodo}><th scope="row">{p.nodo}</th><td><span className={`ps-marca ${n?.clase ?? ""}`}>{n?.n ?? p.nivel}</span></td><td>{nf.format(p.p_min)} m.c.a.</td><td>{nf.format(p.p_max)} m.c.a.</td></tr>); })}</tbody>
          </table></div>
          {d.peores.length > 15 ? <button type="button" className="tec-boton-sec" onClick={() => setTodos((x) => !x)}>{todos ? "Ver menos" : `Ver los ${d.peores.length}`}</button> : null}
          <p className="tec-ayuda">En el geovisor, la capa «Presión de modelo (no medida)» los muestra en el mapa.</p>
        </section>) : null}
      {d?.cargado ? (
        <section className="tec-tarjeta ps" aria-labelledby="ps-mat">
          <h2 id="ps-mat">Presión contra la que aguanta el material</h2>
          <p className="red-texto">{d.por_material.n === 0 ? "Ningún nodo pasa la presión de trabajo de los tramos que llegan a él." : `${nf.format(d.por_material.n)} nodos pasan la presión de trabajo de un tramo que llega a ellos.`}</p>
          <p className="tec-ayuda">{d.por_material.nota}</p>
        </section>) : null}
    </>
  );
}

const ESTADOS: { c: EstadoSensible | ""; n: string }[] = [{ c: "por_confirmar", n: "Por confirmar" }, { c: "confirmado", n: "Confirmados" }, { c: "descartado", n: "Descartados" }, { c: "", n: "Todos" }];
const NOMBRE_ESTADO: Record<EstadoSensible, string> = { por_confirmar: "Por confirmar", confirmado: "Confirmado", descartado: "Descartado" };
const ORIGEN: Record<string, string> = { manual: "Agregado a mano", propuesta: "Propuesto por la palabra del nombre", nombre: "Propuesto por la palabra del nombre" };

export function UsuariosSensibles() {
  const [estado, setEstado] = useState<EstadoSensible | "">("por_confirmar");
  const [d, setD] = useState<Sensibles | null>(null); const [items, setItems] = useState<Sensible[]>([]);
  const [error, setError] = useState<string | null>(null); const [aviso, setAviso] = useState<string | null>(null); const [vez, setVez] = useState(0); const [cargandoMas, setCargandoMas] = useState(false);
  useEffect(() => { let vivo = true; setD(null); setItems([]); setError(null);
    apiFase2.sensibles(estado).then((r) => { if (vivo) { setD(r); setItems(r.items); } }).catch((e) => { if (vivo) setError(err(e)); }); return () => { vivo = false; }; }, [estado, vez]);
  const refrescar = (t: string) => { setAviso(t); setVez((v) => v + 1); };
  const mas = () => { if (!d?.siguiente) return; setCargandoMas(true);
    apiFase2.sensibles(estado, d.siguiente).then((r) => { setD(r); setItems((x) => [...x, ...r.items]); }).catch((e) => setError(err(e))).finally(() => setCargandoMas(false)); };
  const total = (e: EstadoSensible) => d?.totales[e] ?? 0;
  return (
    <>
      <section className="tec-tarjeta ps" aria-labelledby="us-tit" data-testid="usuarios-sensibles">
        <h2 id="us-tit">Usuarios sensibles</h2>
        <p className="red-texto">Hospitales, clínicas, colegios y otros contratos que conviene avisar primero cuando una zona queda sin agua. Confirme los que sí lo son y descarte los que no.</p>
        <p className="tec-ayuda" data-testid="us-sin-nombres">Aquí no se guardan ni se muestran nombres: solo el contrato, el tipo y la palabra que coincidió.</p>
        {d ? <p className="red-texto" data-testid="us-totales">{nf.format(total("por_confirmar"))} por confirmar · {nf.format(total("confirmado"))} confirmados · {nf.format(total("descartado"))} descartados</p> : null}
        <div className="dan-fila" role="group" aria-label="Estado">{ESTADOS.map((e) => <button key={e.c || "todos"} type="button" className="dan-opcion" aria-pressed={estado === e.c} onClick={() => setEstado(e.c)}>{e.n}</button>)}</div>
        {aviso ? <p className="tec-aviso tec-aviso-ok" role="status">{aviso}</p> : null}
        {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      </section>
      {!d && !error ? <p className="tec-sub dan-pad" role="status">Cargando…</p> : null}
      {d && items.length === 0 ? <section className="tec-tarjeta"><p className="red-vacio">No hay usuarios sensibles con ese estado.</p></section> : null}
      {items.map((u) => <ItemSensible key={u.contrato} u={u} tipos={d?.tipos ?? []} onHecho={refrescar} />)}
      {d?.siguiente ? <button type="button" className="tec-boton-sec" disabled={cargandoMas} onClick={mas}>{cargandoMas ? "Cargando…" : "Ver más"}</button> : null}
      {d ? <AgregarSensible tipos={d.tipos} onHecho={refrescar} /> : null}
    </>
  );
}

function ItemSensible({ u, tipos, onHecho }: { u: Sensible; tipos: { codigo: string; nombre: string }[]; onHecho: (t: string) => void }) {
  const [tipo, setTipo] = useState(u.tipo); const [modo, setModo] = useState<"" | "descartar">(""); const [motivo, setMotivo] = useState("");
  const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const enviar = async (accion: "confirmar" | "descartar") => {
    setOcupado(true); setError(null);
    try { const r = await apiFase2.fijar(u.contrato, accion, accion === "confirmar" ? { tipo } : { motivo: motivo.trim() });
      onHecho(r.cambio ? `Contrato ${u.contrato}: ${accion === "confirmar" ? "confirmado" : "descartado"}.` : `El contrato ${u.contrato} ya estaba así.`); }
    catch (e) { setError(err(e)); } finally { setOcupado(false); }
  };
  return (
    <section className="tec-tarjeta itv-bandeja ps" aria-label={`Contrato ${u.contrato}`} data-contrato={u.contrato}>
      <h2>Contrato <span className="mono">{u.contrato}</span> <span className="itv-etiqueta">{NOMBRE_ESTADO[u.estado]}</span></h2>
      <p className="red-texto">{u.tipo_nombre}{u.palabra ? <> · coincidió «{u.palabra}»</> : null} · {ORIGEN[u.origen] ?? u.origen}</p>
      <p className="tec-ayuda">{u.tramo ? `Tramo ${u.tramo}` : "Sin tramo cercano en la red"} · desde {new Date(u.desde).toLocaleDateString("es-CO", { day: "numeric", month: "short", year: "numeric" })}</p>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      {modo === "descartar" ? (
        <div className="dash-motivo">
          <label htmlFor={`us-m-${u.contrato}`}>Motivo (descartar)</label>
          <input id={`us-m-${u.contrato}`} type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por qué no es un usuario sensible (10 letras o más)" />
          <div className="tec-acciones">
            <button type="button" className="tec-boton itv-guardar" disabled={ocupado || motivo.trim().length < 10} onClick={() => void enviar("descartar")}>{ocupado ? "Guardando…" : "Descartar"}</button>
            <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => setModo("")}>Cancelar</button>
          </div>
        </div>) : (
        <div className="dash-acciones ps-acciones">
          <label className="ps-tipo">Tipo<select value={tipo} onChange={(e) => setTipo(e.target.value)} aria-label={`Tipo del contrato ${u.contrato}`}>{tipos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}</select></label>
          {u.estado !== "confirmado" || tipo !== u.tipo ? <button type="button" className="tec-boton" disabled={ocupado} onClick={() => void enviar("confirmar")}>{u.estado === "confirmado" ? "Corregir el tipo" : "Confirmar"}</button> : null}
          {u.estado !== "descartado" ? <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => setModo("descartar")}>Descartar</button> : null}
        </div>)}
    </section>
  );
}

function AgregarSensible({ tipos, onHecho }: { tipos: { codigo: string; nombre: string }[]; onHecho: (t: string) => void }) {
  const [contrato, setContrato] = useState(""); const [tipo, setTipo] = useState(""); const [motivo, setMotivo] = useState("");
  const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  const listo = /^\d{1,15}$/.test(contrato.trim()) && !!tipo && motivo.trim().length >= 10;
  const enviar = async () => {
    setOcupado(true); setError(null);
    try { await apiFase2.fijar(contrato.trim(), "confirmar", { tipo, motivo: motivo.trim() }); onHecho(`Contrato ${contrato.trim()}: agregado y confirmado.`); setContrato(""); setTipo(""); setMotivo(""); }
    catch (e) { setError(err(e)); } finally { setOcupado(false); }
  };
  return (
    <section className="tec-tarjeta ps" aria-labelledby="us-agregar" data-testid="us-agregar">
      <h2 id="us-agregar">Agregar un contrato</h2>
      <p className="tec-ayuda">Para uno que no salió en la lista. Debe estar en el catastro.</p>
      <div className="ps-form">
        <div className="tec-campo"><label htmlFor="us-contrato">Contrato</label><input id="us-contrato" type="text" inputMode="numeric" maxLength={15} value={contrato} onChange={(e) => setContrato(e.target.value)} /></div>
        <div className="tec-campo"><label htmlFor="us-tipo">Tipo</label><select id="us-tipo" value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="">Elija…</option>{tipos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}</select></div>
        <div className="tec-campo ps-form-ancho"><label htmlFor="us-motivo">Motivo <span className="tec-oblig">(10 letras o más)</span></label><input id="us-motivo" type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></div>
      </div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      <div className="tec-acciones"><button type="button" className="tec-boton" disabled={ocupado || !listo} onClick={() => void enviar()}>{ocupado ? "Guardando…" : "Agregar y confirmar"}</button></div>
    </section>
  );
}
