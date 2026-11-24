import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import "./reparto.css";
import { apiReparto, avisoDeError, ErrorReparto, type Contexto, type Lista } from "./apiReparto";
import { ciclosParaEscoger, codigoValido, dividir, entregadasDeRuta, guardarLista, guardarToque, leerLista, leerToque, sinEntregada, textoFecha, textoHora, textoPeriodo,
         type OpcionRuta, type ToquePendiente } from "./logica";
import { useUbicacion, UMBRAL_PRECISION_MALA_M } from "../ubicacion";

// «Reparto de facturas» del repartidor (celular, 390 px; modelo navegable del 23-nov). El repartidor escoge su ruta (primero el ciclo y luego la ruta) entre la
// anterior (último período de lectura) y la nueva (archivo del supervisor), o reparte sin ruta (solo el buscador; el orden en que entrega es su ruta real).
// Al tocar un código: «¿Entregó esta factura?» → «Sí» registra en ese momento con el XY. El código sale y sube el siguiente; los saltados se quedan arriba.
// Sin señal: avisa claramente, NO pierde la lista (sesión del navegador) y guarda el toque pendiente con su uuid; al volver la señal lo reintenta tal cual.
// Sin nombre, dirección ni teléfono del suscriptor: solo códigos.

const almacen = typeof window !== "undefined" ? window.sessionStorage : null;
const nuevoId = () => (crypto.randomUUID ? crypto.randomUUID() : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (Number(c) ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (Number(c) / 4)))).toString(16)));

export function PantallaRepartidor({ onVolver }: { onVolver: () => void }) {
  const hoy = new Date().toLocaleDateString("sv-SE", { timeZone: "America/Bogota" });
  const [lista, setListaEstado] = useState<Lista | null>(() => { const l = almacen ? leerLista(almacen) : null; return l && l.jornada.fecha === hoy ? l : null; });
  const setLista = useCallback((l: Lista | null) => { setListaEstado(l); if (almacen) guardarLista(almacen, l); }, []);
  return lista
    ? <Lista_ lista={lista} setLista={setLista} onCambiarRuta={() => setLista(null)} onVolver={onVolver} />
    : <Inicio onLista={setLista} onVolver={onVolver} />;
}

function Cabecera({ titulo, sub, onVolver, rotulo = "← Volver" }: { titulo: string; sub?: React.ReactNode; onVolver: () => void; rotulo?: string }) {
  return (
    <header className="campo-cab rep-cab">
      <button type="button" className="tec-boton-sec" onClick={onVolver}>{rotulo}</button>
      <div><h1>{titulo}</h1>{sub ? <p className="campo-sub">{sub}</p> : null}</div>
    </header>
  );
}

// ---------------------------------------------------------------- Inicio: escoger la ruta ----------------------------------------------------------------
function Inicio({ onLista, onVolver }: { onLista: (l: Lista) => void; onVolver: () => void }) {
  const [ctx, setCtx] = useState<Contexto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ciclo, setCiclo] = useState("");
  const [opcion, setOpcion] = useState<OpcionRuta | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const cargar = useCallback(() => { setError(null); apiReparto.contexto().then(setCtx).catch((e) => setError(avisoDeError(e))); }, []);
  useEffect(cargar, [cargar]);
  const ciclos = useMemo(() => (ctx ? ciclosParaEscoger(ctx) : []), [ctx]);
  const elegido = ciclos.find((c) => c.ciclo === ciclo) ?? null;

  const empezar = async (c: Parameters<typeof apiReparto.empezar>[0]) => {
    setOcupado(true); setError(null);
    try { onLista(await apiReparto.empezar(c)); } catch (e) { setError(avisoDeError(e)); } finally { setOcupado(false); }
  };
  const retomar = async (id: number) => {
    setOcupado(true); setError(null);
    try { onLista(await apiReparto.lista(id)); } catch (e) { setError(avisoDeError(e)); } finally { setOcupado(false); }
  };

  return (
    <div className="tec-pagina campo-pagina rep-pagina" data-pantalla="reparto-inicio">
      <Cabecera titulo="Reparto de facturas" sub="Escoja la ruta que va a repartir hoy" onVolver={onVolver} />
      {error ? <p className="rep-aviso rep-aviso-error" role="alert">{error} <button type="button" className="rep-link" onClick={cargar}>Reintentar</button></p> : null}
      {!ctx && !error ? <p className="rep-suave">Cargando rutas…</p> : null}
      {ctx && ctx.mis_jornadas_hoy.length > 0 ? (
        <section className="rep-bloque" aria-label="Siga donde iba">
          <h2>Siga donde iba</h2>
          {ctx.mis_jornadas_hoy.map((j) => (
            <button key={j.id} type="button" className="rep-opcion" disabled={ocupado} onClick={() => void retomar(j.id)} data-jornada={j.id}>
              <strong>{j.origen === "inventada" ? "Sin ruta" : j.origen === "nueva" ? `Ciclo ${j.ciclo} · ${j.ruta ? `Ruta ${j.ruta}` : "todo el ciclo"} (archivo)` : `Ciclo ${j.ciclo} · Ruta ${j.ruta}`}</strong>
              <span>{j.origen === "inventada" ? `${j.entregadas} entregadas` : `${j.entregadas} entregadas de ${j.total}`} · última {textoHora(j.ultima)}</span>
            </button>
          ))}
        </section>
      ) : null}
      {ctx ? (
        <section className="rep-bloque" aria-label="Escoger ruta">
          <h2>Escoja su ruta</h2>
          <label className="rep-campo">1. Ciclo
            <select value={ciclo} onChange={(e) => { setCiclo(e.target.value); setOpcion(null); }} data-campo="ciclo">
              <option value="">Escoja el ciclo…</option>
              {ciclos.map((c) => <option key={c.ciclo} value={c.ciclo}>Ciclo {c.ciclo}</option>)}
            </select>
          </label>
          {elegido ? (
            <>
              {elegido.reparto
                ? <p className="rep-suave" data-bloque="reparto">Se reparte la facturación de {textoPeriodo(elegido.reparto.periodo)} (desde el {textoFecha(elegido.reparto.desde)}).</p>
                : <p className="rep-aviso" role="status" data-bloque="sin-fecha">Al ciclo {elegido.ciclo} le falta la fecha de reparto en el calendario: se toman como entregadas las facturas de los últimos {ctx.parametros.respaldo_dias} días.</p>}
              <p className="rep-rotulo">2. Ruta</p>
              <div className="rep-opciones" role="radiogroup" aria-label="Ruta">
                {elegido.opciones.map((o) => (
                  <button key={o.clave} type="button" role="radio" aria-checked={opcion?.clave === o.clave} className="rep-opcion" onClick={() => setOpcion(o)} data-opcion={o.clave}>
                    <strong>{o.titulo}</strong><span>{o.detalle}</span>
                  </button>
                ))}
              </div>
            </>
          ) : null}
          <button type="button" className="tec-boton rep-grande" disabled={!opcion || ocupado} data-accion="empezar"
            onClick={() => opcion && void empezar(opcion.tipo === "anterior" ? { origen: "anterior", ciclo: opcion.ciclo, ruta: opcion.ruta } : { origen: "nueva", lote_id: opcion.loteId })}>
            {ocupado ? "Abriendo…" : "Empezar reparto"}
          </button>
          <button type="button" className="tec-boton-sec rep-medio" disabled={ocupado} onClick={() => void empezar({ origen: "inventada" })} data-accion="sin-ruta">Repartir sin ruta (solo buscador)</button>
        </section>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------- La lista ----------------------------------------------------------------
function Lista_({ lista, setLista, onCambiarRuta, onVolver }: { lista: Lista; setLista: (l: Lista) => void; onCambiarRuta: () => void; onVolver: () => void }) {
  const j = lista.jornada, sinRuta = j.origen === "inventada";
  const { estado: gps, fix, actualizar, mensaje: msjGps } = useUbicacion();
  const [buscar, setBuscar] = useState("");
  const [confirmar, setConfirmar] = useState<{ contrato: string; porBuscador: boolean } | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; tipo: "ok" | "error" | "info" } | null>(null);
  const [toque, setToqueEstado] = useState<ToquePendiente | null>(() => (almacen ? leerToque(almacen) : null));
  const [enviando, setEnviando] = useState(false);
  const [enLinea, setEnLinea] = useState(typeof navigator === "undefined" ? true : navigator.onLine);
  const [anular, setAnular] = useState<{ id: number; contrato: string } | null>(null);
  const [motivo, setMotivo] = useState("");
  const setToque = (t: ToquePendiente | null) => { setToqueEstado(t); if (almacen) guardarToque(almacen, t); };
  const listaRef = useRef(lista); listaRef.current = lista;

  const refrescar = useCallback(async () => {
    try { setLista(await apiReparto.lista(listaRef.current.jornada.id)); } catch { /* sin señal: se queda la lista guardada */ }
  }, [setLista]);

  const enviar = useCallback(async (t: ToquePendiente) => {
    setEnviando(true);
    try {
      const r = await apiReparto.entregar({ jornada_id: t.jornada_id, contrato: t.contrato, lon: t.lon, lat: t.lat, precision_m: t.precision_m, por_buscador: t.por_buscador, id_cliente: t.id_cliente });
      setToque(null);
      setLista(sinEntregada(listaRef.current, r.contrato));
      setBuscar("");
      setAviso({ tipo: "ok", texto: `Entrega ${r.consecutivo} guardada: contrato ${r.contrato} con su XY.${r.precision_mala ? " La ubicación era imprecisa: quedó marcada." : ""}${r.aviso ? " " + r.aviso : ""}` });
      void refrescar();
    } catch (e) {
      if (e instanceof ErrorReparto && (e.tipo === "red" || e.tipo === "servidor")) {
        setAviso(null);   // el aviso del toque pendiente (arriba) ya lo dice, con «Reintentar» y «Descartar»
      } else {
        setToque(null);   // el servidor la rechazó con su motivo (ya registrada, no es de la ruta, sin GPS…): no se reintenta
        setAviso({ tipo: "error", texto: avisoDeError(e) });
        void refrescar();
      }
    } finally { setEnviando(false); }
  }, [refrescar, setLista]);

  // la señal: aviso claro y reintento del toque pendiente al volver
  useEffect(() => {
    const en = () => { setEnLinea(true); const t = almacen ? leerToque(almacen) : null; if (t) void enviar(t); else void refrescar(); };
    const fuera = () => setEnLinea(false);
    window.addEventListener("online", en); window.addEventListener("offline", fuera);
    return () => { window.removeEventListener("online", en); window.removeEventListener("offline", fuera); };
  }, [enviar, refrescar]);
  useEffect(() => { if (!aviso || aviso.tipo !== "ok") return; const r = setTimeout(() => setAviso(null), 6000); return () => clearTimeout(r); }, [aviso]);

  const { arriba, abajo, encontrados } = dividir(lista.pendientes, sinRuta ? "" : buscar);
  const codigoSinRuta = sinRuta ? codigoValido(buscar) : null;
  const tocar = (contrato: string, porBuscador: boolean) => { if (toque) return; setAviso(null); setConfirmar({ contrato, porBuscador }); };
  const si = () => {
    if (!confirmar || !fix) return;
    const t: ToquePendiente = { jornada_id: j.id, contrato: confirmar.contrato, id_cliente: nuevoId(), por_buscador: confirmar.porBuscador,
      lon: Number(fix.lon.toFixed(6)), lat: Number(fix.lat.toFixed(6)), precision_m: Math.round(fix.precision_m * 10) / 10 };
    setToque(t); setConfirmar(null); void enviar(t);
  };
  const hacerAnular = async () => {
    if (!anular) return;
    try { await apiReparto.anular(anular.id, motivo.trim()); setAviso({ tipo: "info", texto: `Entrega del contrato ${anular.contrato} anulada. Vuelve a la lista.` }); setAnular(null); setMotivo(""); void refrescar(); }
    catch (e) { setAviso({ tipo: "error", texto: avisoDeError(e) }); }
  };
  const titulo = sinRuta ? "Sin ruta" : j.origen === "nueva" ? `Ciclo ${j.ciclo} · ${j.ruta ? `Ruta ${j.ruta}` : "todo el ciclo"}` : `Ciclo ${j.ciclo} · Ruta ${j.ruta}`;
  const precisionMala = fix && fix.precision_m > UMBRAL_PRECISION_MALA_M;

  return (
    <div className="tec-pagina campo-pagina rep-pagina" data-pantalla="reparto-lista" data-jornada={j.id}>
      <Cabecera titulo="Reparto de facturas" onVolver={onVolver} />
      <p className="rep-estado" data-bloque="estado"><span data-dato="ruta">{titulo}</span>
        <strong data-dato="entregadas">{sinRuta ? `Entregadas hoy: ${lista.entregadas_mias}` : `Entregadas ${entregadasDeRuta(lista)} de ${j.total}`}</strong></p>
      {!enLinea ? <p className="rep-aviso rep-aviso-error" role="alert" data-bloque="sin-senal">Sin señal. La lista no se pierde; las entregas no se guardan hasta que vuelva la conexión.</p> : null}
      {toque ? (
        <p className="rep-aviso rep-aviso-error" role="alert" data-bloque="toque-pendiente">La entrega del contrato <strong>{toque.contrato}</strong> todavía NO se ha guardado: se reintenta sola al volver la señal.{" "}
          <button type="button" className="rep-link" disabled={enviando} onClick={() => void enviar(toque)} data-accion="reintentar">{enviando ? "Enviando…" : "Reintentar"}</button>{" "}
          <button type="button" className="rep-link" disabled={enviando} onClick={() => { setToque(null); setAviso(null); }} data-accion="descartar">Descartar</button></p>
      ) : null}
      {j.aviso ? <p className="rep-aviso" role="status" data-bloque="respaldo">{j.aviso}</p> : null}
      <p className={`rep-gps${gps === "ok" && !precisionMala ? "" : " rep-gps-mal"}`} data-bloque="gps">
        {gps === "ok" && fix ? `Ubicación: ± ${Math.round(fix.precision_m)} m${precisionMala ? " (imprecisa: se guarda marcada)" : ""}` : gps === "buscando" ? "Buscando la ubicación…" : msjGps ?? "Sin ubicación."}
        {gps !== "ok" ? <button type="button" className="rep-link" onClick={actualizar}>Actualizar ubicación</button> : null}
      </p>
      {aviso ? <p className={`rep-aviso ${aviso.tipo === "ok" ? "rep-aviso-ok" : aviso.tipo === "error" ? "rep-aviso-error" : ""}`} role="status" data-bloque="aviso">{aviso.texto}</p> : null}

      <label className="rep-campo">{sinRuta ? "Buscar contrato" : "Buscar en esta ruta"}
        <input type="search" inputMode="numeric" autoComplete="off" value={buscar} onChange={(e) => setBuscar(e.target.value.replace(/\D/g, "").slice(0, 12))}
          placeholder="Escriba el código del contrato" data-campo="buscar" />
      </label>
      {!sinRuta && buscar ? <p className="rep-suave" data-bloque="encontrados">{encontrados === 1 ? "1 contrato encontrado" : `${encontrados} contratos encontrados`}</p> : null}
      {sinRuta ? (
        codigoSinRuta
          ? <button type="button" className="tec-boton rep-grande" disabled={!!toque} onClick={() => tocar(codigoSinRuta, true)} data-accion="registrar-sin-ruta">Registrar entrega del contrato {codigoSinRuta}</button>
          : <p className="rep-suave">Sin ruta: escriba el código del contrato en el buscador para marcar la entrega. El orden en que entrega queda como su ruta.</p>
      ) : (
        <>
          {arriba.length === 0 ? <p className="rep-suave" data-bloque="vacia">{buscar ? "Ningún contrato pendiente de esta ruta tiene ese código." : "Todas las facturas de esta ruta están entregadas."}</p> : null}
          <div className="rep-rejilla" data-bloque="arriba">
            {arriba.map((p) => (
              <button key={p.c} type="button" className={`rep-casilla rep-casilla-grande${p.s ? " rep-saltado" : ""}`} aria-label={`Contrato ${p.c}${p.s ? ", saltado" : ""}`}
                disabled={!!toque} onClick={() => tocar(p.c, !!buscar)} data-contrato={p.c}>
                <span className="rep-codigo">{p.c}</span>{p.s ? <span className="rep-insignia">Saltado</span> : null}
              </button>
            ))}
          </div>
          {abajo.length > 0 ? (
            <>
              <p className="rep-separa" aria-hidden="true"><span>Siguientes 10 (bajando)</span></p>
              <div className="rep-rejilla" data-bloque="abajo">
                {abajo.map((p) => (
                  <button key={p.c} type="button" className={`rep-casilla${p.s ? " rep-saltado" : ""}`} aria-label={`Contrato ${p.c}${p.s ? ", saltado" : ""}`}
                    disabled={!!toque} onClick={() => tocar(p.c, !!buscar)} data-contrato={p.c}>
                    <span className="rep-codigo">{p.c}</span>{p.s ? <span className="rep-insignia">Saltado</span> : null}
                  </button>
                ))}
              </div>
            </>
          ) : null}
        </>
      )}

      {lista.ultimas.length > 0 ? (
        <section className="rep-bloque" aria-label="Sus últimas entregas">
          <h2>Sus últimas entregas</h2>
          <ul className="rep-ultimas">
            {lista.ultimas.map((u) => (
              <li key={u.id}><span>Entrega {u.consecutivo} · <strong>{u.contrato}</strong> · {textoHora(u.hora)}</span>
                <button type="button" className="rep-link" onClick={() => { setAnular({ id: u.id, contrato: u.contrato }); setMotivo(""); }} data-anular={u.id}>Anular</button></li>
            ))}
          </ul>
        </section>
      ) : null}
      <div className="rep-pie">
        <button type="button" className="tec-boton-sec" onClick={onCambiarRuta} data-accion="cambiar-ruta">Cambiar de ruta</button>
        <button type="button" className="tec-boton-sec" onClick={() => void refrescar()}>Actualizar lista</button>
      </div>

      {confirmar ? (
        <div className="rep-velo" onClick={() => setConfirmar(null)}>
          <div className="rep-hoja" role="dialog" aria-modal="true" aria-label="Confirmar entrega" onClick={(e) => e.stopPropagation()} data-dialogo="confirmar">
            <span className="rep-suave">¿Entregó esta factura?</span>
            <span className="rep-codigo-gigante">{confirmar.contrato}</span>
            {fix
              ? <span className="rep-suave">Se guarda con su ubicación (XY) y como entrega número {lista.siguiente}.</span>
              : <span className="rep-aviso rep-aviso-error">Sin ubicación del GPS: no se puede guardar. Active la ubicación y toque «Actualizar ubicación».</span>}
            <button type="button" className="tec-boton rep-grande" disabled={!fix} onClick={si} data-accion="si">Sí, entregué</button>
            <button type="button" className="tec-boton-sec rep-medio" onClick={() => setConfirmar(null)} data-accion="cancelar">Cancelar</button>
          </div>
        </div>
      ) : null}
      {anular ? (
        <div className="rep-velo" onClick={() => setAnular(null)}>
          <div className="rep-hoja" role="dialog" aria-modal="true" aria-label="Anular entrega" onClick={(e) => e.stopPropagation()} data-dialogo="anular">
            <span className="rep-suave">Anular la entrega del contrato</span>
            <span className="rep-codigo-gigante">{anular.contrato}</span>
            <label className="rep-campo">Motivo (10 a 300 caracteres)
              <textarea value={motivo} maxLength={300} rows={3} onChange={(e) => setMotivo(e.target.value)} data-campo="motivo" />
            </label>
            <button type="button" className="tec-boton rep-grande" disabled={motivo.trim().length < 10} onClick={() => void hacerAnular()} data-accion="confirmar-anular">Anular entrega</button>
            <button type="button" className="tec-boton-sec rep-medio" onClick={() => setAnular(null)}>Cancelar</button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
