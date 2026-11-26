import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { lazyConRecarga } from "../../lib/recarga";
import { apiRev, textoError, type FilaReporte, type FormularioRev } from "./apiRevision";
import { camposDelTipo, columnasBase, columnasPropias, columnasTabla, hayPasoD, ordenar, type Contexto } from "./columnas";
import { FILTROS_INICIALES, aFiltrosServidor, filtrosLegibles, filtrosSoloPantalla, pasaFiltroCliente, rangoInvalido, type FiltrosUI, type Periodo } from "./filtros";
import { fmtMiles } from "./formatoRevision";
import { TablaReportes } from "./TablaReportes";
import { Detalle } from "./Detalle";
import { DerivadasReporte } from "./DerivadasReporte";
import { DescargaCancelada, ExcelDemasiadoGrande, ejecutarDescarga, guardarArchivo, type Progreso } from "./ejecutarDescarga";

// El mapa (y MapLibre con él) se descarga SOLO cuando la persona abre la vista «Mapa».
const MapaReportes = lazyConRecarga(() => import("./MapaReportes"));
const PAGINA = 5000;

/** «Reportes» con dos vistas (25-nov): los reportes de campo y «Avisos y actividades derivadas» (solo consulta y descarga; se atiende en Actas registradas). La de derivadas solo la ve el supervisor y se monta al abrirla. */
export function Reportes({ def, correo = "", onIrAAtender, vistaInicial = "reportes" }: { def: FormularioRev; correo?: string; onIrAAtender?: () => void; vistaInicial?: "reportes" | "derivadas" }) {
  const [vista, setVista] = useState<"reportes" | "derivadas">(vistaInicial);
  const [vistaDer, setVistaDer] = useState(vistaInicial === "derivadas");
  const veDerivadas = def.puede.supervisar === true;
  return (
    <>
      {veDerivadas ? (
        <div className="rv-vistas rv-vistas-rep" role="group" aria-label="Qué ver en Reportes">
          <button type="button" className="rv-boton-sec rv-corto" aria-pressed={vista === "reportes"} onClick={() => setVista("reportes")} data-vista="reportes">Reportes de campo</button>
          <button type="button" className="rv-boton-sec rv-corto" aria-pressed={vista === "derivadas"} onClick={() => { setVista("derivadas"); setVistaDer(true); }} data-vista="derivadas">Avisos y actividades derivadas</button>
        </div>
      ) : null}
      <div hidden={vista !== "reportes"}><ListaReportes def={def} /></div>
      {veDerivadas && vistaDer ? <div hidden={vista !== "derivadas"}><DerivadasReporte correo={correo} admin={def.perfil === "admin"} onIrAAtender={onIrAAtender} /></div> : null}
    </>
  );
}

function ListaReportes({ def }: { def: FormularioRev }) {
  const [f, setF] = useState<FiltrosUI>(FILTROS_INICIALES);
  const [filas, setFilas] = useState<FilaReporte[]>([]);
  const [total, setTotal] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [vista, setVista] = useState<"tabla" | "mapa">("tabla");
  const [orden, setOrden] = useState<{ clave: string; dir: "asc" | "desc" } | null>({ clave: "registrado_en", dir: "desc" });
  const [sel, setSel] = useState<string | null>(null);
  const [grupoSel, setGrupoSel] = useState<string | null>(null);
  const [ajusteN, setAjusteN] = useState(0);
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false);
  const [progreso, setProgreso] = useState<Progreso | null>(null);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string; csv?: boolean } | null>(null);
  const [incluirAutor, setIncluirAutor] = useState(false);
  const cancelar = useRef<AbortController | null>(null);
  const version = useRef(0);

  const ctx = useMemo<Contexto>(() => ({ estados: new Map((def.estados ?? []).map((e) => [e.codigo, e.nombre])) }), [def.estados]);
  const servidor = useMemo(() => aFiltrosServidor(f), [f.tipo, f.grupo, f.estado, f.periodo, f.desde, f.hasta, f.riesgo, f.ocultos, f.resultado]);   // eslint-disable-line react-hooks/exhaustive-deps
  const invalido = rangoInvalido(f);

  // Carga por cursor hasta que `siguiente` sea nulo: el reporte entrega TODOS los datos del filtro (la paginación solo es transporte). Nada se guarda en el navegador.
  useEffect(() => {
    if (invalido) return;
    const v = ++version.current; setCargando(true); setError(null); setFilas([]); setSel(null); setGrupoSel(null);
    (async () => {
      let cursor: number | null = null; let acc: FilaReporte[] = [];
      try {
        for (;;) {
          const r = await apiRev.reportes({ ...servidor, limite: PAGINA, ...(cursor !== null ? { cursor } : {}) });
          if (v !== version.current) return;
          acc = acc.concat(r.reportes); setFilas(acc); setTotal(r.total);
          if (r.siguiente === null || r.reportes.length === 0) break;
          cursor = r.siguiente;
        }
        if (v === version.current) setAjusteN((n) => n + 1);
      } catch (e) { if (v === version.current) setError(textoError(e)); }
      finally { if (v === version.current) setCargando(false); }
    })();
  }, [servidor, invalido]);

  const visibles = useMemo(() => filas.filter((x) => pasaFiltroCliente(x, f)), [filas, f.zona, f.busqueda]);   // eslint-disable-line react-hooks/exhaustive-deps
  const conPasoD = useMemo(() => hayPasoD(filas), [filas]);
  const base = useMemo(() => columnasBase(conPasoD), [conPasoD]);
  const propias = useMemo(() => (f.tipo ? columnasPropias(camposDelTipo(def, f.tipo)) : []), [def, f.tipo]);
  const cols = useMemo(() => columnasTabla(base, propias, !!f.tipo), [base, propias, f.tipo]);
  const ordenadas = useMemo(() => ordenar(visibles, [...base, ...propias].find((c) => c.clave === orden?.clave) ?? null, orden?.dir ?? "asc"), [visibles, base, propias, orden]);

  const tipos = def.grupos.filter((g) => !f.grupo || g.codigo === f.grupo).flatMap((g) => g.tipos.map((t) => ({ ...t, grupo: g.nombre })));
  const set = <K extends keyof FiltrosUI>(k: K, v: FiltrosUI[K]) => setF((x) => ({ ...x, [k]: v, ...(k === "grupo" && x.tipo && !def.grupos.find((g) => g.codigo === v)?.tipos.some((t) => t.codigo === x.tipo) && v ? { tipo: "" } : {}) }));
  const legibles = filtrosLegibles(f, def);
  const parche = (id: string, p: Partial<FilaReporte>) => setFilas((xs) => xs.map((x) => (x.id === id ? { ...x, ...p } : x)));
  const soloPantalla = filtrosSoloPantalla(f);
  const miembros = grupoSel ? filas.filter((x) => x.grupo_duplicados === grupoSel) : [];

  async function descargar(formato: "csv" | "xlsx") {
    if (progreso || invalido) return;
    setMsg(null); cancelar.current = new AbortController();
    try {
      const r = await ejecutarDescarga({ filtros: servidor, formato, incluirAutor, filtrosTexto: legibles, soloPantalla, def, onProgreso: setProgreso, senal: cancelar.current.signal });
      guardarArchivo(r);
      setMsg({ tipo: "ok", texto: `Se descargó ${r.nombre} con ${fmtMiles(r.filas)} ${r.filas === 1 ? "fila" : "filas"}.` });
    } catch (e) {
      if (e instanceof DescargaCancelada) setMsg({ tipo: "ok", texto: "Descarga cancelada." });
      else if (e instanceof ExcelDemasiadoGrande) setMsg({ tipo: "error", texto: e.message, csv: true });
      else setMsg({ tipo: "error", texto: textoError(e).texto });
    } finally { setProgreso(null); cancelar.current = null; }
  }

  return (
    <section className="rv-seccion" aria-labelledby="rv-rep-tit">
      <div className="rv-cab-sec">
        <div><h2 id="rv-rep-tit">Reportes</h2><p className="rv-sub">Se muestran todos los reportes del filtro. Los posibles duplicados se sugieren: usted decide si los vincula.</p></div>
        <div className="rv-descargas">
          <div className="rv-botones">
            <button type="button" className="rv-boton" disabled={!!progreso || invalido || total === 0} onClick={() => void descargar("xlsx")}>Descargar Excel</button>
            <button type="button" className="rv-boton-sec" disabled={!!progreso || invalido || total === 0} onClick={() => void descargar("csv")}>Descargar CSV</button>
          </div>
          {def.perfil === "admin" ? (
            <label className="rv-check"><input type="checkbox" checked={incluirAutor} disabled={!!progreso} onChange={(e) => setIncluirAutor(e.target.checked)} /> Incluir el correo de quien reportó
              <small>{incluirAutor ? " Advertencia: es información interna y queda auditado quién lo descargó." : " Por omisión los archivos no llevan el correo."}</small></label>
          ) : null}
        </div>
      </div>
      <p className="rv-privacidad">Los archivos traen todas las filas del filtro (con los ocultos marcados) y no incluyen fotos, rutas de almacenamiento, datos sensibles ni, salvo que el administrador lo pida, el correo de quien reportó. Cada descarga queda auditada.</p>
      {soloPantalla.length ? <p className="rv-sub">La descarga no aplica {soloPantalla.join(" ni ")}: solo existen en pantalla.</p> : null}
      {progreso ? (
        <div className="rv-aviso rv-aviso-info" role="status">
          {progreso.fase === "preparando" ? "Preparando la descarga…" : progreso.fase === "armando" ? "Armando el archivo…" : `Descargando ${fmtMiles(progreso.hecho)} de ${fmtMiles(progreso.total)} filas…`}
          <button type="button" className="rv-boton-sec rv-corto" onClick={() => cancelar.current?.abort()}>Cancelar</button>
        </div>
      ) : null}
      {msg ? <div className={`rv-aviso rv-aviso-${msg.tipo === "ok" ? "ok" : "error"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.texto}{msg.csv ? <button type="button" className="rv-boton-sec rv-corto" onClick={() => void descargar("csv")}>Descargar en CSV</button> : null}</div> : null}

      <div className={`rv-filtros${filtrosAbiertos ? " abierto" : ""}`}>
        <button type="button" className="rv-boton-sec rv-solo-movil" aria-expanded={filtrosAbiertos} onClick={() => setFiltrosAbiertos((x) => !x)}>Filtros{filtrosAbiertos ? " ▲" : " ▼"}</button>
        <div className="rv-filtros-cuerpo">
          <label className="rv-campo">Grupo<select value={f.grupo} onChange={(e) => set("grupo", e.target.value)}><option value="">Todos</option>{def.grupos.map((g) => <option key={g.codigo} value={g.codigo}>{g.nombre}</option>)}</select></label>
          <label className="rv-campo">Tipo<select value={f.tipo} onChange={(e) => set("tipo", e.target.value)}><option value="">Todos</option>{tipos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}</select></label>
          <label className="rv-campo">Estado<select value={f.estado} onChange={(e) => set("estado", e.target.value)}><option value="">Todos</option>{(def.estados ?? []).map((e) => <option key={e.codigo} value={e.codigo}>{e.nombre}</option>)}</select></label>
          <label className="rv-campo">Fecha de registro<select value={f.periodo} onChange={(e) => set("periodo", e.target.value as Periodo)}>
            <option value="30d">Últimos 30 días</option><option value="7d">Últimos 7 días</option><option value="hoy">Hoy</option><option value="mes">Mes en curso</option><option value="rango">Rango de fechas…</option><option value="todo">Todas las fechas</option></select></label>
          {f.periodo === "rango" ? <>
            <label className="rv-campo">Desde<input type="date" value={f.desde} onChange={(e) => set("desde", e.target.value)} /></label>
            <label className="rv-campo">Hasta<input type="date" value={f.hasta} onChange={(e) => set("hasta", e.target.value)} /></label></> : null}
          <label className="rv-campo">Riesgo inmediato<select value={f.riesgo} onChange={(e) => set("riesgo", e.target.value as FiltrosUI["riesgo"])}><option value="">Todos</option><option value="si">Solo con riesgo</option><option value="no">Sin riesgo</option></select></label>
          <label className="rv-campo">Ocultos<select value={f.ocultos} onChange={(e) => set("ocultos", e.target.value as FiltrosUI["ocultos"])}><option value="no">Excluir</option><option value="todos">Incluir (marcados)</option><option value="si">Solo ocultos</option></select></label>
          <label className="rv-campo">Zona<select value={f.zona} onChange={(e) => set("zona", e.target.value as FiltrosUI["zona"])}><option value="todas">Todas</option><option value="dentro">Dentro de la zona</option><option value="fuera">Fuera de la zona</option></select></label>
          {conPasoD ? <label className="rv-campo">Resultado<select value={f.resultado} onChange={(e) => set("resultado", e.target.value as FiltrosUI["resultado"])}><option value="">Todos</option><option value="efectivo">Efectivo</option><option value="inefectivo">Inefectivo</option></select></label> : null}
          <label className="rv-campo rv-ancho-campo">Buscar en descripción y contrato<input type="search" value={f.busqueda} onChange={(e) => set("busqueda", e.target.value)} placeholder="Texto…" autoComplete="off" /></label>
          <button type="button" className="rv-boton-sec rv-corto" onClick={() => setF(FILTROS_INICIALES)}>Quitar filtros</button>
        </div>
      </div>
      {invalido ? <p className="rv-error" role="alert">La fecha «Desde» no puede ser posterior a «Hasta».</p> : null}
      <p className="rv-activos" aria-label="Filtros activos">{legibles.join(" · ")}</p>

      <div className="rv-barra" role="status" aria-live="polite">
        <strong>{fmtMiles(visibles.length)} de {fmtMiles(total)} reportes</strong>
        {f.zona !== "todas" || f.busqueda.trim() ? <span className="rv-tenue"> (de {fmtMiles(filas.length)} cargados; la zona y el texto se aplican en pantalla)</span> : null}
        {cargando ? <span className="rv-tenue"> · cargando {fmtMiles(filas.length)} de {fmtMiles(total)}…</span> : null}
        <span className="rv-vistas" role="group" aria-label="Vista">
          <button type="button" className="rv-boton-sec rv-corto" aria-pressed={vista === "tabla"} onClick={() => setVista("tabla")}>Tabla</button>
          <button type="button" className="rv-boton-sec rv-corto" aria-pressed={vista === "mapa"} onClick={() => setVista("mapa")}>Mapa</button>
        </span>
      </div>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error.texto}</div> : null}

      <div className={`rv-split${sel ? " con-detalle" : ""}`}>
        <div className="rv-principal">
          {vista === "tabla"
            ? <TablaReportes filas={ordenadas} columnas={cols} ctx={ctx} orden={orden} seleccionada={sel} onSeleccion={setSel}
                onOrden={(clave) => setOrden((o) => (o?.clave === clave ? { clave, dir: o.dir === "asc" ? "desc" : "asc" } : { clave, dir: "asc" }))} />
            : <Suspense fallback={<p className="rv-sub" role="status">Cargando el mapa…</p>}>
                <MapaReportes filas={visibles} def={def} ajusteN={ajusteN} seleccionada={sel} onSeleccion={setSel} onGrupo={setGrupoSel} />
              </Suspense>}
          {grupoSel ? (
            <div className="rv-grupo-dup">
              <strong>Posibles duplicados: {miembros.length} reportes en el grupo</strong> <button type="button" className="rv-enlace" onClick={() => setGrupoSel(null)}>Cerrar</button>
              <ul className="rv-lista">{miembros.map((m) => <li key={m.id}>{new Date(m.registrado_en).toLocaleDateString("es-CO", { timeZone: "America/Bogota" })} · {m.tipo.nombre} · {ctx.estados.get(m.estado) ?? m.estado}{m.oculto ? " · oculto" : ""} <button type="button" className="rv-enlace" onClick={() => setSel(m.id)}>Abrir</button></li>)}</ul>
            </div>
          ) : null}
        </div>
        {sel ? <Detalle id={sel} def={def} ctx={ctx} onCerrar={() => setSel(null)} onCambio={parche} onAbrir={(id) => setSel(id)} /> : null}
      </div>
    </section>
  );
}
