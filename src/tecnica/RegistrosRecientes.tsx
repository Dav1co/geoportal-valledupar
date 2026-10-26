import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiDash, textoError, type Catalogo, type FiltrosRegistros, type RegistroFila } from "./apiDashboard";
import { DescargaCancelada, ejecutarDescarga, guardarArchivo, type Progreso } from "./ejecutarDescarga";
import { etiquetaMarca, fmtFecha, fmtInstante, fmtMiles, fmtValor, hoyBogota, mayuscula, periodoARango, textoReferencia, type Periodo } from "./formato";
import { supabase } from "../lib/supabase";

// Dashboard técnico · «Registros recientes». Todo sale de datos del servidor (formularios, plantas, puntos, zonas, variables y unidades); nada escrito en el código.
const PAGINA = 50;
const REFRESCO_MS = 60_000;
type Estado = "todos" | "vigentes" | "excluidos";
type F = { planta: string; formulario: string; punto: string; zona: string; periodo: Periodo; desde: string; hasta: string; estado: Estado };
const INICIAL: F = { planta: "", formulario: "", punto: "", zona: "", periodo: "7d", desde: "", hasta: "", estado: "todos" };
const PERIODOS: { v: Periodo; t: string }[] = [{ v: "hoy", t: "Hoy" }, { v: "7d", t: "Últimos 7 días" }, { v: "mes", t: "Mes en curso" }, { v: "rango", t: "Rango de fechas…" }];

type Accion = { alcance: "registro" | "lote"; accion: "EXCLUIR" | "REINCLUIR"; fila: RegistroFila };

/** Marcas de una fila. Para sumar una marca nueva (p. ej. «durante servicio reducido») basta agregar una entrada aquí: la columna ya las pinta. */
function marcasDe(f: RegistroFila): { clave: string; texto: string; tono: "alerta" | "info" | "gris"; ayuda?: string }[] {
  const m: { clave: string; texto: string; tono: "alerta" | "info" | "gris"; ayuda?: string }[] = [];
  if (f.fuera_de_rango) m.push({ clave: "rango", texto: etiquetaMarca(f.fuera_de_rango), tono: "alerta", ayuda: textoReferencia({ ...f, unidad: f.unidad }) || undefined });
  if (f.fuente === "telemetria") m.push({ clave: "fuente", texto: "Telemetría", tono: "info" });
  if (f.excluido) m.push({ clave: "excluido", texto: "Excluido", tono: "gris" });
  return m;
}

export function RegistrosRecientes({ catalogo }: { catalogo: Catalogo }) {
  const [f, setF] = useState<F>(INICIAL);
  const [filas, setFilas] = useState<RegistroFila[]>([]);
  const [total, setTotal] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [cargandoMas, setCargandoMas] = useState(false);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [auto, setAuto] = useState(true);
  const [hayNuevos, setHayNuevos] = useState(false);
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false);
  const [accion, setAccion] = useState<Accion | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [incluirExcl, setIncluirExcl] = useState(false);
  const [progreso, setProgreso] = useState<Progreso | null>(null);
  const [descMsg, setDescMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const cancelar = useRef<AbortController | null>(null);
  const version = useRef(0);                 // descarta respuestas de consultas viejas cuando cambian los filtros

  const filtrosServidor = useMemo<FiltrosRegistros>(() => {
    const r = periodoARango(f.periodo, hoyBogota(), f.desde, f.hasta);
    return { planta: f.planta, formulario: f.formulario, punto: f.punto, zona: f.zona, estado: f.estado, desde: r.desde, hasta: r.hasta };
  }, [f]);
  const rangoInvalido = f.periodo === "rango" && !!f.desde && !!f.hasta && f.desde > f.hasta;

  const cargarPrimera = useCallback(async (silencioso = false) => {
    if (rangoInvalido) return;
    const v = ++version.current;
    if (!silencioso) { setCargando(true); setError(null); }
    try {
      const r = await apiDash.registros(filtrosServidor, { limite: PAGINA });
      if (v !== version.current) return;
      setFilas(r.registros); setTotal(r.total); setHayNuevos(false); setError(null);
    } catch (e) { if (v === version.current && !silencioso) setError(textoError(e)); }
    finally { if (v === version.current) setCargando(false); }
  }, [filtrosServidor, rangoInvalido]);
  useEffect(() => { void cargarPrimera(); }, [cargarPrimera]);

  // «Se actualiza solo»: consulta cada 60 s (pausable). Si la persona ya cargó más páginas, no se le mueve la lista: se avisa que hay registros nuevos.
  useEffect(() => {
    if (!auto || accion || rangoInvalido) return;
    const id = setInterval(async () => {
      if (document.visibilityState === "hidden") return;
      try {
        const r = await apiDash.registros(filtrosServidor, { limite: PAGINA });
        if (filas.length <= PAGINA) { setFilas(r.registros); setTotal(r.total); setHayNuevos(false); }
        else { setTotal(r.total); setHayNuevos((r.registros[0]?.registro_id ?? 0) > (filas[0]?.registro_id ?? 0)); }
      } catch { /* una consulta periódica fallida no molesta: la siguiente lo reintenta */ }
    }, REFRESCO_MS);
    return () => clearInterval(id);
  }, [auto, accion, rangoInvalido, filtrosServidor, filas]);

  async function cargarMas() {
    if (cargandoMas || filas.length === 0) return;
    setCargandoMas(true);
    try {
      const r = await apiDash.registros(filtrosServidor, { despuesDe: filas[filas.length - 1].registro_id, limite: PAGINA });
      setFilas((x) => [...x, ...r.registros]); setTotal(r.total);
    } catch (e) { setError(textoError(e)); } finally { setCargandoMas(false); }
  }

  const nombreForm = (c: string) => catalogo.formularios.find((x) => x.clave === c)?.nombre ?? c;
  const puntosVisibles = catalogo.puntos.filter((p) => !f.zona || p.zona === f.zona);
  const filtrosTexto = useMemo(() => {
    const t: string[] = [];
    if (f.formulario) t.push(`Formulario: ${nombreForm(f.formulario)}`);
    if (f.planta) t.push(`Planta: ${catalogo.plantas.find((p) => p.codigo === f.planta)?.nombre ?? f.planta}`);
    if (f.zona) t.push(`Zona: ${mayuscula(f.zona)}`);
    if (f.punto) { const p = catalogo.puntos.find((x) => x.codigo === f.punto); t.push(`Punto: ${f.punto}${p ? ` · ${p.nombre}` : ""}`); }
    const { desde, hasta } = periodoARango(f.periodo, hoyBogota(), f.desde, f.hasta);
    t.push(`Fecha de la muestra: ${desde ? `desde el ${fmtFecha(desde)}` : "sin inicio"}${hasta ? ` hasta el ${fmtFecha(hasta)}` : ""}`);
    return t;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [f, catalogo]);

  async function descargar(formato: "csv" | "xlsx") {
    if (progreso || rangoInvalido) return;
    setDescMsg(null); cancelar.current = new AbortController();
    try {
      const r = await ejecutarDescarga({ filtros: filtrosServidor, formato, incluirExcluidos: incluirExcl, filtrosTexto, onProgreso: setProgreso, senal: cancelar.current.signal });
      guardarArchivo(r);
      setDescMsg({ tipo: "ok", texto: `Se descargó ${r.nombre} con ${fmtMiles(r.filas)} ${r.filas === 1 ? "fila" : "filas"}.` });
    } catch (e) {
      if (e instanceof DescargaCancelada) setDescMsg({ tipo: "ok", texto: "Descarga cancelada." });
      else setDescMsg({ tipo: "error", texto: textoError(e).texto });
    } finally { setProgreso(null); cancelar.current = null; }
  }

  return (
    <section className="td-seccion" aria-labelledby="td-reg-tit">
      <div className="td-cab">
        <div>
          <h2 id="td-reg-tit">Registros recientes</h2>
          <p className="td-sub">Se muestran todos los datos. Las marcas avisan, pero nunca impiden guardar.</p>
        </div>
        <div className="td-descargas">
          <div className="td-botones">
            <button type="button" className="td-boton" disabled={!!progreso || rangoInvalido} onClick={() => descargar("xlsx")}>Descargar Excel</button>
            <button type="button" className="td-boton-sec" disabled={!!progreso || rangoInvalido} onClick={() => descargar("csv")}>Descargar CSV</button>
          </div>
          <label className="td-check"><input type="checkbox" checked={incluirExcl} disabled={!!progreso} onChange={(e) => setIncluirExcl(e.target.checked)} /> Incluir excluidos</label>
        </div>
      </div>
      <p className="td-privacidad">Los archivos incluyen los correos de las personas que registraron y excluyeron datos y se descargan con los filtros de abajo (hasta {fmtMiles(catalogo.descarga_max_filas)} filas). Es información interna: no la comparta fuera de la empresa. Cada descarga queda registrada.</p>
      {progreso ? (
        <div className="td-aviso td-aviso-info" role="status">
          {progreso.fase === "preparando" ? "Preparando la descarga…" : progreso.fase === "armando" ? "Armando el archivo…" : `Descargando ${fmtMiles(progreso.hecho)} de ${fmtMiles(progreso.total)} filas…`}
          <button type="button" className="td-boton-sec td-corto" onClick={() => cancelar.current?.abort()}>Cancelar</button>
        </div>
      ) : null}
      {descMsg ? <div className={`td-aviso td-aviso-${descMsg.tipo === "ok" ? "ok" : "error"}`} role={descMsg.tipo === "error" ? "alert" : "status"}>{descMsg.texto}</div> : null}

      <div className={`td-filtros${filtrosAbiertos ? " abierto" : ""}`}>
        <button type="button" className="td-boton-sec td-solo-movil" aria-expanded={filtrosAbiertos} onClick={() => setFiltrosAbiertos((x) => !x)}>Filtros{filtrosAbiertos ? " ▲" : " ▼"}</button>
        <div className="td-filtros-cuerpo">
          <label className="td-campo">Formulario
            <select id="f-form" value={f.formulario} onChange={(e) => setF({ ...f, formulario: e.target.value })}><option value="">Todos</option>{catalogo.formularios.map((x) => <option key={x.clave} value={x.clave}>{x.nombre}</option>)}</select></label>
          <label className="td-campo">Planta
            <select id="f-planta" value={f.planta} onChange={(e) => setF({ ...f, planta: e.target.value })}><option value="">Todas</option>{catalogo.plantas.map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label>
          <label className="td-campo">Zona
            <select id="f-zona" value={f.zona} onChange={(e) => setF({ ...f, zona: e.target.value, punto: "" })}><option value="">Todas</option>{catalogo.zonas.map((z) => <option key={z} value={z}>{mayuscula(z)}</option>)}</select></label>
          <label className="td-campo">Punto
            <select id="f-punto" value={f.punto} onChange={(e) => setF({ ...f, punto: e.target.value })}><option value="">Todos</option>{puntosVisibles.map((p) => <option key={p.codigo} value={p.codigo}>{p.codigo} · {p.nombre}{p.activo ? "" : " (inactivo)"}</option>)}</select></label>
          <label className="td-campo">Periodo (fecha de la muestra)
            <select id="f-per" value={f.periodo} onChange={(e) => setF({ ...f, periodo: e.target.value as Periodo })}>{PERIODOS.map((p) => <option key={p.v} value={p.v}>{p.t}</option>)}</select></label>
          {f.periodo === "rango" ? (
            <>
              <label className="td-campo">Desde<input id="f-desde" type="date" value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></label>
              <label className="td-campo">Hasta<input id="f-hasta" type="date" value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></label>
            </>
          ) : null}
          <label className="td-campo">Estado
            <select id="f-estado" value={f.estado} onChange={(e) => setF({ ...f, estado: e.target.value as Estado })}><option value="todos">Todos</option><option value="vigentes">Vigentes</option><option value="excluidos">Excluidos</option></select></label>
        </div>
      </div>
      {rangoInvalido ? <p className="td-error" role="alert">La fecha inicial no puede ser posterior a la final.</p> : null}

      <div className="td-barra">
        <span role="status" aria-live="polite">{cargando ? "Cargando…" : `Mostrando ${fmtMiles(filas.length)} de ${fmtMiles(total)} ${total === 1 ? "registro" : "registros"}`}</span>
        <label className="td-check"><input type="checkbox" checked={auto} onChange={(e) => setAuto(e.target.checked)} /> Actualizar solo cada 60 s</label>
        <button type="button" className="td-boton-sec td-corto" onClick={() => void cargarPrimera()} disabled={cargando}>Actualizar ahora</button>
      </div>
      {hayNuevos ? <div className="td-aviso td-aviso-info" role="status">Hay registros más recientes que los de esta lista. <button type="button" className="td-enlace" onClick={() => void cargarPrimera()}>Ver los más recientes</button></div> : null}
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      {error ? (
        <div className="td-aviso td-aviso-error" role="alert">{error.texto}{" "}
          {error.sesion ? <button type="button" className="td-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="td-enlace" onClick={() => void cargarPrimera()}>Reintentar</button>}
        </div>
      ) : null}

      <div className="td-tabla-caja">
        <table className="td-tabla">
          <caption className="td-solo-lectores">Registros de Técnica</caption>
          <thead><tr><th>Muestra</th><th>Registro (servidor)</th><th>Planta o punto</th><th>Variable</th><th className="td-der">Valor</th><th>Autor</th><th>Marcas</th><th>Acción</th></tr></thead>
          <tbody>
            {filas.map((r) => (
              <FilaRegistro key={r.registro_id} r={r} onAccion={(alcance) => { setAviso(null); setAccion({ alcance, accion: r.excluido ? "REINCLUIR" : "EXCLUIR", fila: r }); }} />
            ))}
            {!cargando && filas.length === 0 && !error ? <tr><td colSpan={8} className="td-vacio">No hay registros con esos filtros.</td></tr> : null}
          </tbody>
        </table>
      </div>
      {filas.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={cargarMas} disabled={cargandoMas}>{cargandoMas ? "Cargando…" : `Cargar más (${fmtMiles(total - filas.length)} restantes)`}</button></div> : null}
      <p className="td-pie">Excluir un registro lo saca de las gráficas y del procesamiento, pero no lo borra. Queda quién lo excluyó, cuándo y por qué, y se puede reincluir.</p>

      {accion ? (
        <DialogoExclusion accion={accion} catalogo={catalogo} filasVisibles={filas.filter((x) => x.lote_id === accion.fila.lote_id).length} nombreForm={nombreForm}
          onCerrar={() => setAccion(null)}
          onHecho={(texto) => { setAccion(null); setAviso(texto); void cargarPrimera(true); }} />
      ) : null}
    </section>
  );
}

function FilaRegistro({ r, onAccion }: { r: RegistroFila; onAccion: (a: "registro" | "lote") => void }) {
  const marcas = marcasDe(r);
  const lugar = r.punto ? `${r.punto_nombre ?? r.punto}${r.zona ? ` · ${mayuscula(r.zona)}` : ""}` : (r.planta_nombre ?? "Ambas plantas");
  return (
    <>
      <tr className={r.excluido ? "td-excluida" : undefined}>
        <td className="td-num">{fmtFecha(r.fecha_muestra)} {r.hora_muestra}</td>
        <td className="td-num">{fmtInstante(r.registrado_en)}</td>
        <td>{lugar}{r.punto ? <span className="td-chico">{r.punto}</span> : null}</td>
        <td>{r.variable_nombre}</td>
        <td className="td-der td-valor">{fmtValor(r.valor, r.decimales)} <span className="td-unidad">{r.unidad}</span></td>
        <td title={r.autor}>{r.autor.split("@")[0]}</td>
        <td><div className="td-marcas">{marcas.map((m) => <span key={m.clave} className={`td-marca td-marca-${m.tono}`} title={m.ayuda}>{m.texto}</span>)}</div></td>
        <td><div className="td-acciones">
          <button type="button" className="td-enlace" onClick={() => onAccion("registro")}>{r.excluido ? "Reincluir valor…" : "Excluir valor…"}</button>
          <button type="button" className="td-enlace" onClick={() => onAccion("lote")}>{r.excluido ? "Reincluir envío…" : "Excluir envío…"}</button>
        </div></td>
      </tr>
      {r.excluido ? (
        <tr className="td-excluida td-excluida-motivo"><td colSpan={8}>Excluido por {r.exclusion_autor?.split("@")[0] ?? "—"} el {fmtInstante(r.exclusion_en)} porque «{r.exclusion_motivo}».</td></tr>
      ) : null}
    </>
  );
}

function DialogoExclusion({ accion, catalogo, filasVisibles, nombreForm, onCerrar, onHecho }: {
  accion: Accion; catalogo: Catalogo; filasVisibles: number; nombreForm: (c: string) => string; onCerrar: () => void; onHecho: (texto: string) => void;
}) {
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { ref.current?.focus(); const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && !enviando) onCerrar(); }; window.addEventListener("keydown", esc); return () => window.removeEventListener("keydown", esc); }, [onCerrar, enviando]);
  const { fila } = accion; const excluye = accion.accion === "EXCLUIR"; const lote = accion.alcance === "lote";
  const largo = motivo.trim().length; const valido = largo >= catalogo.motivo_min && largo <= catalogo.motivo_max;
  const donde = fila.punto ? `${fila.punto_nombre ?? fila.punto}` : (fila.planta_nombre ?? "las dos plantas");
  async function confirmar() {
    if (!valido || enviando) return;
    setEnviando(true); setError(null);
    try {
      const r = await apiDash.excluir({ ...(lote ? { lote_id: fila.lote_id } : { registro_id: fila.registro_id }), motivo: motivo.trim(), accion: accion.accion });
      onHecho(`${excluye ? "Se excluyó" : "Se reincluyó"} ${fmtMiles(r.afectados)} ${r.afectados === 1 ? "valor" : "valores"}${lote ? " del envío" : ""}. Queda el motivo, quién y cuándo.`);
    } catch (e) { setError(textoError(e).texto); setEnviando(false); }
  }
  return (
    <div className="td-fondo" role="presentation">
      <div className="td-dialogo" role="dialog" aria-modal="true" aria-labelledby="td-dlg-tit">
        <h3 id="td-dlg-tit">{excluye ? "Excluir" : "Reincluir"} {lote ? "el envío completo" : "este valor"}</h3>
        <p className="td-sub">
          {lote
            ? <>Afecta a <strong>todos los valores del envío</strong> de {nombreForm(fila.formulario)} ({donde}, muestra del {fmtFecha(fila.fecha_muestra)}, registrado por {fila.autor.split("@")[0]}){filasVisibles > 0 ? <>; en esta lista se ven {filasVisibles}.</> : "."}</>
            : <>Afecta solo a <strong>{fila.variable_nombre}: {fmtValor(fila.valor, fila.decimales)} {fila.unidad}</strong> ({donde}, muestra del {fmtFecha(fila.fecha_muestra)}).</>}
        </p>
        <p className="td-sub">{excluye ? "No se borra nada: el dato sigue guardado, pero deja de contar en el resumen del operador, las gráficas y el procesamiento." : "El dato vuelve a contar en el resumen, las gráficas y el procesamiento."} Queda quién lo hizo, cuándo y por qué.</p>
        <label className="td-campo td-ancho">Motivo (obligatorio, de {catalogo.motivo_min} a {fmtMiles(catalogo.motivo_max)} caracteres)
          <textarea ref={ref} id="td-motivo" rows={3} value={motivo} maxLength={catalogo.motivo_max} onChange={(e) => setMotivo(e.target.value)} aria-invalid={largo > 0 && !valido} aria-describedby="td-motivo-ayuda" /></label>
        <span id="td-motivo-ayuda" className={`td-chico${largo > 0 && !valido ? " td-error" : ""}`}>{largo} caracteres{largo > 0 && largo < catalogo.motivo_min ? ` · faltan ${catalogo.motivo_min - largo}` : ""}</span>
        {error ? <p className="td-error" role="alert">{error}</p> : null}
        <div className="td-dialogo-acciones">
          <button type="button" className="td-boton" onClick={confirmar} disabled={!valido || enviando}>{enviando ? "Guardando…" : excluye ? "Excluir" : "Reincluir"}</button>
          <button type="button" className="td-boton-sec" onClick={onCerrar} disabled={enviando}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}
