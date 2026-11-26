import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import "./reparto.css";
import { lazyConRecarga } from "../../lib/recarga";
import { apiReparto, avisoDeError, type CalendarioReparto, type CargaLote, type Detalle, type FilaAvance, type LoteFila } from "./apiReparto";
import { ENCABEZADOS, textoFecha, textoHora, textoPeriodo, type FilaArchivo } from "./logica";
import { BotonVolver } from "../BotonVolver";
import { descargarPlantillaReparto, leerArchivoRuta } from "./plantilla";

// «Reparto de facturas · Supervisión» (escritorio; modelo navegable del 23-nov, ajustado el 23-nov: el repartidor escoge su ruta, no hay asignación).
// El supervisor de reparto (actividad supervision_reparto) carga los archivos de ruta o de ciclo, ve el avance por repartidor y ruta, el detalle (orden real frente
// al de lectura, saltados y anuladas con su motivo), el mapa EN VIVO de los XY y el calendario de reparto en solo lectura. El enlace «Cambiar en Calendario»
// abre el MISMO calendario del modo Cartera (PanelCalendario y geoportal-scrr), solo si la persona tiene dashboard_campo (decisión de David, 23-nov).
const MapaReparto = lazyConRecarga(() => import("./MapaReparto"));
// el calendario de Cartera trae sus estilos (scrr.css), que de otro modo solo carga el modo Cartera
const PanelCalendario = lazyConRecarga(() => Promise.all([import("../../scrr/PanelCalendario"), import("../../scrr/scrr.css")]).then(([m]) => ({ default: m.PanelCalendario })));

type Pestana = "avance" | "mapa" | "archivos" | "calendario";
const PESTANAS: [Pestana, string][] = [["avance", "Avance"], ["mapa", "Mapa en vivo"], ["archivos", "Archivos de ruta"], ["calendario", "Calendario"]];
const hoyBogota = () => new Date().toLocaleDateString("sv-SE", { timeZone: "America/Bogota" });
export const rutaDeFila = (f: Pick<FilaAvance, "origen" | "ciclo" | "ruta" | "nombre_archivo">) =>
  f.origen === "inventada" ? "Sin ruta" : f.origen === "nueva" ? `Ciclo ${f.ciclo} · Ruta ${f.ruta} · archivo ${f.nombre_archivo ?? ""}` : `Ciclo ${f.ciclo} · Ruta ${f.ruta}`;

export function PantallaSupervisor({ onVolver }: { onVolver: () => void }) {
  const [pestana, setPestana] = useState<Pestana>("avance");
  const [fecha, setFecha] = useState(hoyBogota());
  return (
    <div className="tec-pagina campo-pagina rep-pagina rep-sup" data-pantalla="reparto-supervisor">
      <header className="campo-cab rep-cab">
        <BotonVolver onClick={onVolver} />
        <div><h1>Reparto de facturas · Supervisión</h1><p className="campo-sub">Archivos de ruta, avance, mapa y calendario de reparto</p></div>
      </header>
      <nav className="rep-tabs" aria-label="Secciones">
        {PESTANAS.map(([k, t]) => <button key={k} type="button" aria-pressed={pestana === k} className={pestana === k ? "activa" : ""} onClick={() => setPestana(k)} data-pestana={k}>{t}</button>)}
        {pestana === "avance" || pestana === "mapa" ? (
          <label className="rep-fecha">Fecha <input type="date" value={fecha} max={hoyBogota()} onChange={(e) => e.target.value && setFecha(e.target.value)} data-campo="fecha" /></label>
        ) : null}
      </nav>
      {pestana === "avance" ? <Avance fecha={fecha} /> : null}
      {pestana === "mapa" ? (
        <Suspense fallback={<p className="rep-suave">Cargando el mapa…</p>}><MapaReparto fecha={fecha} enVivo={fecha === hoyBogota()} /></Suspense>
      ) : null}
      {pestana === "archivos" ? <Archivos /> : null}
      {pestana === "calendario" ? <Calendario /> : null}
    </div>
  );
}

// ---------------------------------------------------------------- Avance y detalle ----------------------------------------------------------------
function Avance({ fecha }: { fecha: string }) {
  const [filas, setFilas] = useState<FilaAvance[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [abierta, setAbierta] = useState<number | null>(null);
  const cargar = useCallback(() => { setError(null); apiReparto.avance(fecha).then((r) => setFilas(r.filas)).catch((e) => setError(avisoDeError(e))); }, [fecha]);
  useEffect(() => { setFilas(null); setAbierta(null); cargar(); }, [cargar]);
  return (
    <section className="rep-bloque" aria-label="Avance">
      <div className="rep-fila-tit"><h2>Avance {fecha === hoyBogota() ? "de hoy" : `del ${textoFecha(fecha)}`}</h2><button type="button" className="tec-boton-sec" onClick={cargar} data-accion="actualizar">Actualizar</button></div>
      {error ? <p className="rep-aviso rep-aviso-error" role="alert">{error}</p> : null}
      {filas === null && !error ? <p className="rep-suave">Cargando…</p> : null}
      {filas && filas.length === 0 ? <p className="rep-suave">Nadie ha empezado a repartir este día.</p> : null}
      {filas && filas.length > 0 ? (
        <div className="rep-tabla-caja">
          <table className="rep-tabla" data-tabla="avance">
            <thead><tr><th>Repartidor</th><th>Ruta o archivo</th><th>Período de reparto</th><th className="n">Entregadas</th><th className="n">Pendientes</th><th className="n">Saltadas</th><th className="n">Anuladas</th><th>Última entrega</th><th /></tr></thead>
            <tbody>
              {filas.map((f) => (
                <tr key={f.jornada_id} data-jornada={f.jornada_id} className={abierta === f.jornada_id ? "rep-sel" : ""}>
                  <td>{f.nombre ?? f.repartidor}</td>
                  <td>{rutaDeFila(f)}</td>
                  <td>{f.origen === "inventada" ? "por contrato" : f.respaldo ? <span className="rep-chip-aviso" title="Al ciclo le falta la fecha de reparto en el calendario">sin fecha (respaldo)</span> : textoPeriodo(f.periodo_reparto)}</td>
                  <td className="n"><strong>{f.entregadas}</strong>{f.origen !== "inventada" ? ` de ${f.total}` : ""}</td>
                  <td className="n">{f.pendientes ?? "—"}</td>
                  <td className="n rep-saltadas">{f.saltadas ?? "—"}</td>
                  <td className="n">{f.anuladas}</td>
                  <td>{textoHora(f.ultima)}</td>
                  <td><button type="button" className="rep-link" onClick={() => setAbierta(abierta === f.jornada_id ? null : f.jornada_id)} data-detalle={f.jornada_id}>{abierta === f.jornada_id ? "Cerrar" : "Ver detalle"}</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
      {abierta !== null ? <DetalleJornada jornada={abierta} onCambio={cargar} /> : null}
    </section>
  );
}

function DetalleJornada({ jornada, onCambio }: { jornada: number; onCambio: () => void }) {
  const [d, setD] = useState<Detalle | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [anular, setAnular] = useState<{ id: number; contrato: string } | null>(null);
  const [motivo, setMotivo] = useState("");
  const cargar = useCallback(() => { apiReparto.detalle(jornada).then(setD).catch((e) => setError(avisoDeError(e))); }, [jornada]);
  useEffect(() => { setD(null); setError(null); cargar(); }, [cargar]);
  const hacer = async () => {
    if (!anular) return;
    try { await apiReparto.anular(anular.id, motivo.trim()); setAnular(null); setMotivo(""); cargar(); onCambio(); } catch (e) { setError(avisoDeError(e)); }
  };
  if (error) return <p className="rep-aviso rep-aviso-error" role="alert">{error}</p>;
  if (!d) return <p className="rep-suave">Cargando el detalle…</p>;
  const vigentes = d.entregas.filter((e) => !e.anulada && e.orden_lectura !== null).map((e) => e.orden_lectura as number).sort((a, b) => a - b);
  const posLectura = (o: number | null) => (o === null ? null : vigentes.indexOf(o) + 1);   // lugar que habría tenido siguiendo la ruta de lectura (entre las entregadas)
  return (
    <div className="rep-detalle" data-bloque="detalle">
      <h3>Detalle · {d.jornada.nombre ?? d.jornada.repartidor} · {rutaDeFila(d.jornada)}</h3>
      <p className="rep-suave">El orden real de entrega frente al de la ruta de lectura. {d.jornada.origen === "inventada" ? "Sin ruta: el orden real es su ruta." : `${d.pendientes} pendientes.`}</p>
      {d.entregas.length === 0 ? <p className="rep-suave">Aún no hay entregas.</p> : (
        <div className="rep-tabla-caja">
          <table className="rep-tabla" data-tabla="detalle">
            <thead><tr><th className="n">Orden real</th><th>Contrato</th><th className="n">Orden de lectura</th><th className="n">Habría sido</th><th>Hora</th><th className="n">Precisión</th><th>Cómo</th><th>Estado</th><th /></tr></thead>
            <tbody>
              {d.entregas.map((e) => {
                const habria = e.anulada ? null : posLectura(e.orden_lectura);
                return (
                  <tr key={e.id} className={e.anulada ? "rep-anulada" : habria !== null && habria !== e.consecutivo ? "rep-desorden" : ""} data-entrega={e.id}>
                    <td className="n">{e.consecutivo}</td><td className="mono">{e.contrato}</td><td className="n">{e.orden_lectura ?? "—"}</td><td className="n">{habria ?? "—"}</td>
                    <td>{textoHora(e.hora)}</td><td className="n">{Math.round(e.precision_m)} m{e.precision_m > 30 ? " ⚠" : ""}</td><td>{e.por_buscador ? "buscador" : "casilla"}</td>
                    <td>{e.anulada ? <span title={`${e.anulada_por ?? ""} · ${textoHora(e.anulada_en)}`}>Anulada: {e.motivo_anulacion}</span> : "Entregada"}</td>
                    <td>{e.anulada ? null : <button type="button" className="rep-link" onClick={() => { setAnular({ id: e.id, contrato: e.contrato }); setMotivo(""); }} data-anular={e.id}>Anular</button>}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {d.saltados.length > 0 ? <p data-bloque="saltados"><strong>Saltados ({d.saltados.length}):</strong> {d.saltados.map((s) => s.contrato).join(", ")}</p> : null}
      {anular ? (
        <div className="rep-anular" role="group" aria-label="Anular entrega">
          <label className="rep-campo">Motivo para anular la entrega del contrato {anular.contrato} (10 a 300 caracteres)
            <input value={motivo} maxLength={300} onChange={(e) => setMotivo(e.target.value)} data-campo="motivo" />
          </label>
          <button type="button" className="tec-boton" disabled={motivo.trim().length < 10} onClick={() => void hacer()} data-accion="confirmar-anular">Anular entrega</button>
          <button type="button" className="tec-boton-sec" onClick={() => setAnular(null)}>Cancelar</button>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------- Archivos de ruta ----------------------------------------------------------------
function Archivos() {
  // David, 24-nov: el archivo es LA MISMA estructura del archivo de rutas de facturación. Ciclo y ruta salen de cada fila (puede traer varias); la DIRECCIÓN
  // se exige como columna pero no se envía. «Revisar archivo» muestra las rutas y los avisos sin escribir nada; «Cargar archivo» confirma.
  const [archivo, setArchivo] = useState<File | null>(null);
  const [errores, setErrores] = useState<string[]>([]);
  const [ok, setOk] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [lotes, setLotes] = useState<LoteFila[] | null>(null);
  const [anular, setAnular] = useState<LoteFila | null>(null); const [motivo, setMotivo] = useState("");
  const [leido, setLeido] = useState<{ filas: FilaArchivo[]; sha256: string } | null>(null);
  const [previa, setPrevia] = useState<Extract<CargaLote, { ok: true }> | null>(null);
  const entrada = useRef<HTMLInputElement>(null);
  const cargarLotes = useCallback(() => { apiReparto.lotes().then((r) => setLotes(r.lotes)).catch((e) => setErrores([avisoDeError(e)])); }, []);
  useEffect(cargarLotes, [cargarLotes]);
  const revisar = async () => {
    if (!archivo) return;
    setOcupado(true); setErrores([]); setOk(null); setPrevia(null);
    try {
      const l = await leerArchivoRuta(archivo, 10000);
      if (l.errores.length) { setErrores(l.errores); return; }
      setLeido({ filas: l.filas, sha256: l.sha256 });
      const r = await apiReparto.loteCargar({ nombre: archivo.name, sha256: l.sha256, filas: l.filas, confirmar: false });
      if (!r.ok) { setErrores(r.errores); return; }
      setPrevia(r);
    } catch (e) { setErrores([avisoDeError(e)]); } finally { setOcupado(false); }
  };
  const cargar = async () => {
    if (!archivo || !leido || !previa) return;
    setOcupado(true); setErrores([]);
    try {
      const r = await apiReparto.loteCargar({ nombre: archivo.name, sha256: leido.sha256, filas: leido.filas, confirmar: true });
      if (!r.ok) { setErrores(r.errores); return; }
      setOk(`${r.repetido ? "Ese archivo ya estaba cargado hoy" : "Archivo cargado"}: ${r.filas} facturas en ${r.rutas.length} ${r.rutas.length === 1 ? "ruta" : "rutas"}.`
        + `${r.otro_ciclo ? ` ${r.otro_ciclo} con un ciclo distinto al de las rutas de lectura (manda el archivo).` : ""}${r.sin_registro ? ` ${r.sin_registro} no están en las rutas ni en la cartera.` : ""} Los repartidores ya las ven como rutas nuevas.`);
      setArchivo(null); setLeido(null); setPrevia(null); if (entrada.current) entrada.current.value = "";
      cargarLotes();
    } catch (e) { setErrores([avisoDeError(e)]); } finally { setOcupado(false); }
  };
  const hacerAnular = async () => {
    if (!anular) return;
    try { await apiReparto.loteAnular(anular.id, motivo.trim()); setAnular(null); setMotivo(""); cargarLotes(); } catch (e) { setErrores([avisoDeError(e)]); }
  };
  return (
    <section className="rep-bloque rep-dos" aria-label="Archivos de ruta">
      <div className="rep-tarjeta">
        <h2>Cargar archivo de rutas</h2>
        <p className="rep-suave">La misma estructura del archivo de rutas de facturación: {ENCABEZADOS.join(", ")}. Puede traer varias rutas y varios ciclos: cada (ciclo, ruta) le aparece al repartidor como una ruta nueva. La dirección no se guarda.</p>
        <button type="button" className="rep-link" onClick={() => void descargarPlantillaReparto()} data-accion="plantilla">Descargar plantilla (.xlsx)</button>
        <label className="rep-campo">Archivo (.xlsx)<input ref={entrada} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={(e) => { setArchivo(e.target.files?.[0] ?? null); setLeido(null); setPrevia(null); setErrores([]); setOk(null); }} data-campo="archivo" /></label>
        <button type="button" className="tec-boton-sec" disabled={!archivo || ocupado} onClick={() => void revisar()} data-accion="revisar">{ocupado && !previa ? "Revisando…" : "Revisar archivo"}</button>
        {previa ? (
          <div className="rep-aviso rep-aviso-ok" role="status" data-bloque="previa">
            <strong>{previa.filas} facturas en {previa.rutas.length} {previa.rutas.length === 1 ? "ruta" : "rutas"}:</strong>
            <ul>{previa.rutas.map((x) => <li key={x.ciclo + "|" + x.ruta}>Ciclo {x.ciclo} · Ruta {x.ruta} · {x.filas} facturas</li>)}</ul>
            {previa.sin_registro ? <p className="rep-suave">{previa.sin_registro} contratos no están en las rutas ni en la cartera (se aceptan con aviso).</p> : null}
          </div>
        ) : null}
        {previa && previa.otro_ciclo ? (
          <div className="rep-aviso" role="status" data-bloque="otro-ciclo">
            <strong>{previa.otro_ciclo} {previa.otro_ciclo === 1 ? "contrato tiene" : "contratos tienen"} un CICLO distinto al de las rutas de lectura</strong> (se cargan así: manda el archivo):
            <ul>{previa.otro_ciclo_lista.map((x) => <li key={x.contrato}>{x.contrato}: el archivo dice {x.ciclo_archivo}; las rutas, {x.ciclo_rutas}</li>)}</ul>
            {previa.otro_ciclo > previa.otro_ciclo_lista.length ? <p className="rep-suave">… y {previa.otro_ciclo - previa.otro_ciclo_lista.length} más.</p> : null}
          </div>
        ) : null}
        <button type="button" className="tec-boton" disabled={!previa || ocupado} onClick={() => void cargar()} data-accion="cargar">{ocupado && previa ? "Cargando…" : "Cargar archivo"}</button>
        {errores.length ? <div className="rep-aviso rep-aviso-error" role="alert" data-bloque="errores"><strong>El archivo no se cargó:</strong><ul>{errores.map((x, i) => <li key={i}>{x}</li>)}</ul></div> : null}
        {ok ? <p className="rep-aviso rep-aviso-ok" role="status" data-bloque="cargado">{ok}</p> : null}
      </div>
      <div className="rep-tarjeta">
        <h2>Archivos de los últimos 60 días</h2>
        {lotes === null ? <p className="rep-suave">Cargando…</p> : lotes.length === 0 ? <p className="rep-suave">Todavía no hay archivos.</p> : (
          <div className="rep-tabla-caja">
            <table className="rep-tabla" data-tabla="lotes">
              <thead><tr><th>Archivo</th><th>Rutas</th><th className="n">Facturas</th><th>Avisos</th><th>Cargado</th><th>Estado</th><th /></tr></thead>
              <tbody>
                {lotes.map((l) => (
                  <tr key={l.id} data-lote={l.id} className={l.anulado ? "rep-anulada" : ""}>
                    <td>{l.nombre_archivo}</td>
                    <td>{(l.rutas ?? []).map((x) => `${x.ciclo} · ${x.ruta} (${x.filas})`).join("; ")}</td>
                    <td className="n">{l.filas}</td>
                    <td>{[l.otro_ciclo ? `${l.otro_ciclo} de otro ciclo` : "", l.sin_registro ? `${l.sin_registro} sin registro` : ""].filter(Boolean).join(" · ") || "—"}</td>
                    <td>{textoFecha(l.cargado_en)} {textoHora(l.cargado_en)}</td>
                    <td>{l.anulado ? `Anulado: ${l.motivo_anulacion}` : l.vigente ? `Vigente · ${l.jornadas} jornadas` : "Vencido"}</td>
                    <td>{!l.anulado ? <button type="button" className="rep-link" onClick={() => { setAnular(l); setMotivo(""); }} data-anular-lote={l.id}>Anular</button> : null}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {anular ? (
          <div className="rep-anular" role="group" aria-label="Anular archivo">
            <label className="rep-campo">Motivo para anular «{anular.nombre_archivo}» (10 a 300 caracteres)<input value={motivo} maxLength={300} onChange={(e) => setMotivo(e.target.value)} data-campo="motivo-lote" /></label>
            <button type="button" className="tec-boton" disabled={motivo.trim().length < 10} onClick={() => void hacerAnular()} data-accion="confirmar-anular-lote">Anular archivo</button>
            <button type="button" className="tec-boton-sec" onClick={() => setAnular(null)}>Cancelar</button>
          </div>
        ) : null}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- Calendario (solo lectura; el enlace abre el de Cartera) ----------------------------------------------------------------
function Calendario() {
  const [periodo, setPeriodo] = useState(hoyBogota().slice(0, 7).replace("-", ""));
  const [cal, setCal] = useState<CalendarioReparto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cambiar, setCambiar] = useState(false);
  const cargar = useCallback(() => { setError(null); apiReparto.calendario(periodo).then(setCal).catch((e) => setError(avisoDeError(e))); }, [periodo]);
  useEffect(() => { setCal(null); cargar(); }, [cargar]);
  const mover = (d: number) => { const y = Number(periodo.slice(0, 4)), m = Number(periodo.slice(4)) - 1 + d; const f = new Date(Date.UTC(y, m, 1)); setPeriodo(`${f.getUTCFullYear()}${String(f.getUTCMonth() + 1).padStart(2, "0")}`); };
  return (
    <section className="rep-bloque" aria-label="Calendario de reparto">
      <div className="rep-fila-tit">
        <h2>Fechas de reparto · {textoPeriodo(periodo)}</h2>
        <span><button type="button" className="tec-boton-sec" onClick={() => mover(-1)}>‹ Mes anterior</button> <button type="button" className="tec-boton-sec" onClick={() => mover(1)}>Mes siguiente ›</button></span>
      </div>
      <p className="rep-suave">Solo lectura. El calendario es uno solo: se llena en Cartera → Calendario («Otras etapas» → reparto). Al ciclo que no tenga fecha se le aplica el respaldo de 15 días.</p>
      {error ? <p className="rep-aviso rep-aviso-error" role="alert">{error}</p> : null}
      {cal ? (
        <>
          {cal.ciclos.length === 0 ? <p className="rep-aviso" data-bloque="sin-calendario">{textoPeriodo(periodo)} no tiene calendario cargado.</p> : (
            <div className="rep-tabla-caja">
              <table className="rep-tabla" data-tabla="calendario">
                <thead><tr><th className="n">Ciclo</th><th>Fecha de reparto</th><th>Hoy se reparte</th></tr></thead>
                <tbody>{cal.ciclos.map((c) => (
                  <tr key={c.ciclo} data-ciclo={c.ciclo}><td className="n">{c.ciclo}</td><td>{c.reparto ? textoFecha(c.reparto) : <span className="rep-chip-aviso">falta</span>}</td>
                    <td>{c.en_reparto_hoy ? `${textoPeriodo(c.en_reparto_hoy.periodo)} (desde ${textoFecha(c.en_reparto_hoy.desde)})` : <span className="rep-chip-aviso">respaldo de 15 días</span>}</td></tr>
                ))}</tbody>
              </table>
            </div>
          )}
          {cal.puede_cambiar ? (
            cambiar ? (
              <div className="rep-calendario-cartera" data-bloque="calendario-cartera">
                <div className="rep-fila-tit"><h3>Calendario (el mismo de Cartera)</h3><button type="button" className="tec-boton-sec" onClick={() => { setCambiar(false); cargar(); }} data-accion="cerrar-calendario">Cerrar</button></div>
                <Suspense fallback={<p className="rep-suave">Cargando el calendario…</p>}><PanelCalendario onCambio={cargar} /></Suspense>
              </div>
            ) : <button type="button" className="rep-link" onClick={() => setCambiar(true)} data-accion="cambiar-calendario">Cambiar en Calendario</button>
          ) : null}
        </>
      ) : !error ? <p className="rep-suave">Cargando…</p> : null}
    </section>
  );
}
