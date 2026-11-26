import { useEffect, useMemo, useRef, useState } from "react";
import { ErrorCampo } from "../apiCampo";
import { apiDocumentos, type FilaDerivada } from "../documentos/apiDocumentos";
import { TOPE_PENDIENTES } from "../documentos/contadorDerivadas";
import { columnasDerivadas, csvDerivadas, filaDerivada, leameDerivadas, nombreActividad, nombreArchivoDerivadas, rotuloEstado } from "./derivadasDescarga";
import { guardarArchivo } from "./ejecutarDescarga";
import { fmtMiles } from "./formatoRevision";
import { importarConRecarga } from "../../lib/recarga";

// «Actividades derivadas» dentro de Reportes (25-nov, David): CONSULTA y DESCARGA. Atender y cerrar siguen en un solo sitio: Actas registradas → «Avisos y actividades derivadas».
// Misma ruta `derivadas` de apiDocumentos.ts (sin ruta nueva): estado, actividad, origen, contrato y fechas van al servidor. La descarga se arma aquí (sin datos de contacto; ver derivadasDescarga.ts).
const PAGINA = TOPE_PENDIENTES;          // 100: el tamaño que ya usa la pantalla de atención (el servidor puede acotarlo; se sigue por `siguiente`)
const MAX_PAGINAS = 100;                 // 10.000 filas en pantalla; si se llega, se dice
const texto = (e: unknown) => (e instanceof ErrorCampo ? e.message : "No se pudo cargar.");

type Filtros = { estado: string; origen: "" | "registro" | "analisis"; actividad: string; contrato: string; desde: string; hasta: string };
const INICIALES: Filtros = { estado: "pendiente", origen: "", actividad: "", contrato: "", desde: "", hasta: "" };

export function DerivadasReporte({ correo, admin, onIrAAtender }: { correo: string; admin: boolean; onIrAAtender?: () => void }) {
  const [f, setF] = useState<Filtros>(INICIALES);
  const [filas, setFilas] = useState<FilaDerivada[]>([]);
  const [cargando, setCargando] = useState(true);
  const [truncado, setTruncado] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [conocidas, setConocidas] = useState<Map<string, string>>(new Map());   // actividades vistas (código → nombre) para el filtro «Actividad»
  const [incluirAutor, setIncluirAutor] = useState(false);
  const [bajando, setBajando] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false);
  const version = useRef(0);
  const invalido = !!f.desde && !!f.hasta && f.desde > f.hasta;

  useEffect(() => {
    if (invalido) return;
    const v = ++version.current; setCargando(true); setError(null); setFilas([]); setTruncado(false);
    const t = window.setTimeout(async () => {
      try {
        let antes: string | number | undefined; let acc: FilaDerivada[] = [];
        for (let p = 0; p < MAX_PAGINAS; p++) {
          const r = await apiDocumentos.derivadas({ estado: f.estado || undefined, origen: f.origen || undefined, actividad: f.actividad || undefined, contrato: f.contrato || undefined,
            desde: f.desde || undefined, hasta: f.hasta || undefined, antes, limite: PAGINA });
          if (v !== version.current) return;
          acc = acc.concat(r.filas); setFilas(acc);
          if (r.siguiente === null || r.siguiente === undefined || r.filas.length === 0) break;
          if (p === MAX_PAGINAS - 1) setTruncado(true);
          antes = r.siguiente;
        }
        if (v === version.current) setConocidas((m) => { const n = new Map(m); for (const d of acc) n.set(d.actividad, nombreActividad(d)); return n; });
      } catch (e) { if (v === version.current) setError(texto(e)); }
      finally { if (v === version.current) setCargando(false); }
    }, 250);
    return () => window.clearTimeout(t);
  }, [f, invalido]);

  const legibles = useMemo(() => [
    `Estado: ${f.estado ? rotuloEstado(f.estado) : "todos"}`, f.origen ? `Origen: ${f.origen === "analisis" ? "Análisis de contrato" : "Revisiones"}` : "",
    f.actividad ? `Actividad: ${conocidas.get(f.actividad) ?? f.actividad}` : "", f.contrato ? `Contrato: ${f.contrato}` : "", f.desde ? `Desde: ${f.desde}` : "", f.hasta ? `Hasta: ${f.hasta}` : "",
  ].filter(Boolean), [f, conocidas]);
  const set = <K extends keyof Filtros>(k: K, v: Filtros[K]) => setF((x) => ({ ...x, [k]: v }));
  const pendientes = filas.filter((d) => d.estado === "pendiente").length;

  async function descargar(formato: "csv" | "xlsx") {
    if (bajando || filas.length === 0) return;
    setMsg(null); setBajando(formato === "xlsx" ? "Armando el Excel…" : "Armando el CSV…");
    try {
      const ahora = new Date(); const nombre = nombreArchivoDerivadas(ahora, formato);
      const generadoEn = ahora.toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false });
      const quien = admin && incluirAutor;
      let blob: Blob;
      if (formato === "csv") blob = new Blob([csvDerivadas(filas, quien)], { type: "text/csv;charset=utf-8" });
      else {
        const m = await importarConRecarga(() => import("./xlsxRevision"));
        const libro = new m.LibroMulti(leameDerivadas({ generadoPor: correo, generadoEn, filas: filas.length, filtros: legibles, incluyeAutor: quien }));
        const cols = columnasDerivadas(quien);
        const h = libro.hoja("d", "Derivadas", cols, cols.map((c) => (c === "Actividad" || c === "Viene de" ? 34 : c.startsWith("Quién") ? 30 : 18)));
        await h.agregarFilas(filas.map((d) => filaDerivada(d, quien)));
        blob = await libro.finalizar();
      }
      guardarArchivo({ nombre, filas: filas.length, blob });
      setMsg({ tipo: "ok", texto: `Se descargó ${nombre} con ${fmtMiles(filas.length)} ${filas.length === 1 ? "fila" : "filas"}. Sin datos de contacto. Esta descarga aún no queda auditada en el servidor.` });
    } catch (e) { setMsg({ tipo: "error", texto: e instanceof Error ? e.message : "No se pudo armar el archivo." }); }
    finally { setBajando(null); }
  }

  return (
    <section className="rv-seccion" aria-labelledby="rv-der-tit" data-testid="reportes-derivadas">
      <div className="rv-cab-sec">
        <div><h2 id="rv-der-tit">Avisos y actividades derivadas</h2>
          <p className="rv-sub">Aquí se consulta y se descarga. Para atender, crear la actividad, ver los datos de contacto o cerrar, vaya a Actas registradas: es el único sitio donde se atiende.</p></div>
        <div className="rv-descargas">
          <div className="rv-botones">
            <button type="button" className="rv-boton" disabled={!!bajando || cargando || filas.length === 0 || invalido} onClick={() => void descargar("xlsx")} data-accion="excel">Descargar Excel</button>
            <button type="button" className="rv-boton-sec" disabled={!!bajando || cargando || filas.length === 0 || invalido} onClick={() => void descargar("csv")} data-accion="csv">Descargar CSV</button>
          </div>
          {admin ? <label className="rv-check"><input type="checkbox" checked={incluirAutor} onChange={(e) => setIncluirAutor(e.target.checked)} /> Incluir el correo de quien originó y de quien cerró
            <small>{incluirAutor ? " Advertencia: es información interna." : " Por omisión los archivos no llevan correos."}</small></label> : null}
        </div>
      </div>
      <p className="rv-privacidad">Los archivos no incluyen los datos de contacto de los avisos (nombre, cédula, teléfono, correo), el texto libre ni el motivo de cierre.</p>
      {onIrAAtender ? <div className="rv-botones"><button type="button" className="rv-boton" onClick={onIrAAtender} data-accion="ir-actividades">Ir a Actividades derivadas</button></div> : null}
      {bajando ? <div className="rv-aviso rv-aviso-info" role="status">{bajando}</div> : null}
      {msg ? <div className={`rv-aviso rv-aviso-${msg.tipo === "ok" ? "ok" : "error"}`} role={msg.tipo === "error" ? "alert" : "status"}>{msg.texto}</div> : null}

      <div className={`rv-filtros${filtrosAbiertos ? " abierto" : ""}`}>
        <button type="button" className="rv-boton-sec rv-solo-movil" aria-expanded={filtrosAbiertos} onClick={() => setFiltrosAbiertos((x) => !x)}>Filtros{filtrosAbiertos ? " ▲" : " ▼"}</button>
        <div className="rv-filtros-cuerpo">
          <label className="rv-campo">Estado<select value={f.estado} onChange={(e) => set("estado", e.target.value)} data-filtro="estado"><option value="pendiente">Pendientes</option><option value="atendida">Atendidas</option><option value="">Todas</option></select></label>
          <label className="rv-campo">Origen<select value={f.origen} onChange={(e) => set("origen", e.target.value as Filtros["origen"])} data-filtro="origen"><option value="">Todos</option><option value="registro">Revisiones</option><option value="analisis">Análisis de contrato</option></select></label>
          <label className="rv-campo">Actividad<select value={f.actividad} onChange={(e) => set("actividad", e.target.value)} data-filtro="actividad"><option value="">Todas</option>
            {[...conocidas.entries()].sort((a, b) => a[1].localeCompare(b[1], "es")).map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></label>
          <label className="rv-campo">Contrato<input type="text" inputMode="numeric" maxLength={12} value={f.contrato} onChange={(e) => set("contrato", e.target.value.replace(/\D/g, ""))} /></label>
          <label className="rv-campo">Desde<input type="date" value={f.desde} onChange={(e) => set("desde", e.target.value)} data-filtro="desde" /></label>
          <label className="rv-campo">Hasta<input type="date" value={f.hasta} onChange={(e) => set("hasta", e.target.value)} data-filtro="hasta" /></label>
          <button type="button" className="rv-boton-sec rv-corto" onClick={() => setF(INICIALES)}>Quitar filtros</button>
        </div>
      </div>
      {invalido ? <p className="rv-error" role="alert">La fecha «Desde» no puede ser posterior a «Hasta».</p> : null}
      <p className="rv-activos" aria-label="Filtros activos">{legibles.join(" · ")}</p>
      <div className="rv-barra" role="status" aria-live="polite">
        <strong>{fmtMiles(filas.length)} {filas.length === 1 ? "fila" : "filas"}</strong>{pendientes && f.estado !== "pendiente" ? <span className="rv-tenue"> · {fmtMiles(pendientes)} pendientes</span> : null}
        {cargando ? <span className="rv-tenue"> · cargando…</span> : null}
        {truncado ? <span className="rv-tenue"> · se muestran las primeras {fmtMiles(MAX_PAGINAS * PAGINA)}; afine los filtros</span> : null}
      </div>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {!cargando && !error && filas.length === 0 ? <div className="rv-vacio">No hay avisos ni actividades derivadas con esos filtros.</div> : null}
      {filas.length ? (
        <div className="rv-der-envoltura"><table className="rv-der-tabla" data-testid="tabla-derivadas">
          <thead><tr><th>Contrato</th><th>Actividad</th><th>Estado</th><th>Origen</th><th>Viene de</th><th>Fecha de origen</th><th>Antigüedad</th></tr></thead>
          <tbody>{filas.map((d) => { const x = filaDerivada(d, false); return (
            <tr key={d.id} data-derivada={d.id}><td data-etiqueta="Contrato">{x[1]}</td><td data-etiqueta="Actividad">{x[3]}</td><td data-etiqueta="Estado">{x[4]}</td><td data-etiqueta="Origen">{x[2]}</td>
              <td data-etiqueta="Viene de">{x[5]}</td><td data-etiqueta="Fecha de origen">{x[6]}</td><td data-etiqueta="Antigüedad">{x[8] === "" ? "—" : `${x[8]} d`}</td></tr>); })}</tbody>
        </table></div>
      ) : null}
    </section>
  );
}
