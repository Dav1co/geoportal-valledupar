import { useCallback, useEffect, useState } from "react";
import "../dashboard/revision.css";
import "./documentos.css";
import { ErrorCampo } from "../apiCampo";
import { AperturasSinRegistrar } from "../acta/AperturasSinRegistrar";
import { PersonalCampo } from "../dashboard/PersonalCampo";
import { Cuadrillas } from "../dashboard/Cuadrillas";
import { apiDocumentos, type Esquema, type FilaActa, type FiltrosActas } from "./apiDocumentos";
import { Derivadas } from "./Derivadas";
import { BotonVolver } from "../BotonVolver";
import { etiquetaPendientes } from "./contadorDerivadas";
import { PdfRegistro } from "./Registro";

// «Actas registradas» (Comercial 21-nov; decisiones B2 y D11 de David): la entrada del supervisor de actas (y del supervisor de campo y el administrador). Pestañas:
// - Actas registradas: las del acta de posible pérdida y los 8 formatos con valor probatorio, con un selector de tipo y filtros; estado del PDF (descargar o generar) y descarga CSV
//   SIN nombres de quien atendió ni del testigo, sin firmas, sin texto libre ni teléfono (la ruta ya los excluye; aquí no se agrega nada).
// - Actividades derivadas (solo el supervisor de campo y el administrador: la ruta vive en geoportal-campo): lo que dejaron las revisiones, pendientes o atendidas; se cierran con motivo.
//   Desde el 23-nov también los AVISOS del Análisis de contrato (filtro Origen): «Crear actividad», «Ver datos de contacto» (Ley 1581, lectura auditada) y cerrarlos.
// - Aperturas sin registrar (la pantalla de siempre, solo con el permiso del acta) y Personal y Cuadrillas en solo lectura.
type Seccion = "actas" | "derivadas" | "aperturas" | "personal";
const texto = (e: unknown) => (e instanceof ErrorCampo ? e.message : "No se pudo completar la operación.");
/** El instante si llega (registrado_en); si solo hay el día (AAAA-MM-DD), el día sin hora. */
const fecha = (f: string) => (/^\d{4}-\d{2}-\d{2}$/.test(f) ? new Date(`${f}T12:00:00`).toLocaleDateString("es-CO", { day: "2-digit", month: "short", year: "numeric" })
  : new Date(f).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }));
const pdfListo = (r: FilaActa) => r.pdf?.estado === "generado";
const RESULTADO: Record<string, string> = { efectivo: "Visita efectiva", inefectivo: "Visita inefectiva" };
const ESTADO_USUARIO: Record<string, string> = { firmo: "firmó el usuario", no_firmo: "el usuario no firmó", nadie_atendio: "nadie atendió" };

export function ActasRegistradas({ correo, onVolver, nombres, puedeAperturas, puedeCerrarDerivadas, pendientes = null, onRecontar, abrirEn = "actas", onIrAReportes }: {
  correo: string; onVolver: () => void;
  /** Pendientes de «Avisos y actividades derivadas» (consulta de AreaCampo; nulo = no se pudo leer o no aplica: no se muestra nada). `onRecontar`: se llama al atender o cerrar. `abrirEn`: pestaña inicial. */
  pendientes?: { n: number; tope: boolean } | null; onRecontar?: () => void; abrirEn?: "actas" | "derivadas";
  /** Botón de regreso a Reportes (Supervisión y dashboard) desde «Avisos y actividades derivadas». */
  onIrAReportes?: () => void;
  /** Nombre de cada formulario por su clave («acta» o el código del formato), del catálogo que ya cargó Formatos de campo. */
  nombres: Map<string, string>;
  puedeAperturas: boolean; puedeCerrarDerivadas: boolean;
}) {
  const [seccion, setSeccion] = useState<Seccion>(abrirEn === "derivadas" && puedeCerrarDerivadas ? "derivadas" : "actas");
  const secciones: { clave: Seccion; titulo: string }[] = [
    { clave: "actas", titulo: "Actas registradas" }, ...(puedeCerrarDerivadas ? [{ clave: "derivadas" as Seccion, titulo: `Avisos y actividades derivadas${etiquetaPendientes(pendientes)}` }] : []),
    ...(puedeAperturas ? [{ clave: "aperturas" as Seccion, titulo: "Aperturas sin registrar" }] : []), { clave: "personal", titulo: "Personal" },
  ];
  return (
    <div className="rv">
      <div className="rv-cab">
        <div className="rv-ancho">
          <div className="rv-fila rv-fila-volver"><BotonVolver variante="claro" onClick={onVolver} /><h1>Actas registradas</h1></div>
          <div className="rv-sesion">{correo}</div>
          <nav className="rv-tabs" aria-label="Secciones de las actas">
            {secciones.map((s) => <button key={s.clave} type="button" className="rv-tab" aria-current={seccion === s.clave ? "page" : undefined} onClick={() => setSeccion(s.clave)}>{s.titulo}</button>)}
          </nav>
        </div>
      </div>
      <div className="rv-cuerpo">
        {seccion === "actas" ? <ListaActas nombres={nombres} via={puedeAperturas ? "acta" : "campo"} />
          : seccion === "derivadas" ? <>{onIrAReportes ? <div className="rv-botones"><button type="button" className="rv-boton-sec" onClick={onIrAReportes} data-accion="volver-reportes">← Volver a Reportes</button></div> : null}<Derivadas puedeCerrar={puedeCerrarDerivadas} onCambio={onRecontar} /></>
          : seccion === "aperturas" ? <AperturasSinRegistrar onVolver={() => setSeccion("actas")} incrustada />
          : <><PersonalCampo soloLectura /><Cuadrillas soloLectura /></>}
      </div>
    </div>
  );
}

/** `via`: la Edge por la que se lee (el supervisor de actas por geoportal-acta; el de campo por geoportal-campo). */
function ListaActas({ nombres, via }: { nombres: Map<string, string>; via: Esquema }) {
  const [tipos, setTipos] = useState<string[]>([]);
  const [f, setF] = useState<FiltrosActas>({});
  const [aplicados, setAplicados] = useState<FiltrosActas>({});
  const [filas, setFilas] = useState<FilaActa[] | null>(null);
  const [siguiente, setSiguiente] = useState<string | number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [descarga, setDescarga] = useState<string | null>(null);
  useEffect(() => {        // los tipos que llevan PDF: los que dice el servidor (documentos_catalogo de las dos Edges)
    let vivo = true;
    Promise.all([apiDocumentos.catalogo("campo").then((r) => r.formularios).catch(() => []), apiDocumentos.catalogo("acta").then((r) => r.formularios).catch(() => [])])
      .then(([c, a]) => { if (vivo) setTipos([...new Set([...a, ...c].filter((x) => x.lleva_pdf).map((x) => x.formulario.replace(/^tipo:/, "")))]); });
    return () => { vivo = false; };
  }, []);
  const cargar = useCallback(async (filtros: FiltrosActas, antes: string | number | null) => {
    setError(null); if (!antes) setFilas(null);
    try { const r = await apiDocumentos.actasRegistradas(via, { ...filtros, antes: antes ?? undefined, limite: 50 }); setFilas((x) => (antes ? [...(x ?? []), ...r.filas] : r.filas)); setSiguiente(r.siguiente); }
    catch (e) { setError(texto(e)); setFilas((x) => x ?? []); }
  }, [via]);
  useEffect(() => { void cargar(aplicados, null); }, [aplicados, cargar]);
  const nombreTipo = (c: string) => nombres.get(c) ?? c;
  const poner = (k: keyof FiltrosActas, v: string) => setF((x) => ({ ...x, [k]: v || undefined }));
  async function descargar() {
    setDescarga("Preparando la descarga…");
    try {
      const todas: FilaActa[] = []; let despues: string | number | null = null;
      do { const r = await apiDocumentos.actasRegistradasDescarga(via, { ...aplicados, despues: despues ?? undefined, limite: 5000 }); todas.push(...r.filas); despues = r.siguiente; setDescarga(`Preparando la descarga… ${todas.length.toLocaleString("es-CO")} filas`); } while (despues);
      const col = ["Consecutivo", "Número físico", "Tipo", "Fecha", "Operario", "Contrato", "Barrio", "Resultado", "PDF", "Nombre del PDF", "Derivadas", "Derivadas pendientes", "Firma del operario", "Usuario", "Firma de testigo"];
      const q = (v: unknown) => { const t = v === null || v === undefined ? "" : String(v); return /[";\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t; };
      const lineas = todas.map((r) => [r.consecutivo, r.numero_fisico, r.tipo_nombre, r.fecha, r.operario, r.contrato, r.barrio, r.resultado, pdfListo(r) ? "generado" : "pendiente", r.pdf?.nombre ?? "", r.derivadas.total, r.derivadas.pendientes,
        r.firmas.operario ? "sí" : "no", r.firmas.usuario ? ESTADO_USUARIO[r.firmas.usuario] ?? r.firmas.usuario : "", r.firmas.testigo ? "sí" : "no"].map(q).join(";"));
      const blob = new Blob(["﻿" + [col.join(";"), ...lineas].join("\r\n")], { type: "text/csv;charset=utf-8" });
      const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `actas_registradas_${new Date().toISOString().slice(0, 10)}.csv`; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
      setDescarga(`Descarga lista: ${todas.length.toLocaleString("es-CO")} filas, sin nombres ni firmas.`);
    } catch (e) { setDescarga(`No se pudo descargar: ${texto(e)}`); }
  }
  return (
    <section className="rv-seccion" aria-labelledby="doc-actas-tit" data-testid="actas-registradas">
      <div><h2 id="doc-actas-tit">Actas registradas</h2>
        <p className="rv-sub">Los registros con valor probatorio: el acta de posible pérdida, las revisiones, las instalaciones y SCRR. El PDF se genera una sola vez y no cambia; la descarga no lleva nombres, firmas ni texto libre.</p></div>
      <form className="doc-filtros" onSubmit={(e) => { e.preventDefault(); setAplicados({ ...f }); }}>
        <label className="rv-campo">Tipo de acta<select value={f.tipo ?? ""} onChange={(e) => poner("tipo", e.target.value)} data-filtro="tipo">
          <option value="">Todas</option>{tipos.map((t) => <option key={t} value={t}>{nombreTipo(t)}</option>)}</select></label>
        <label className="rv-campo">Desde<input type="date" value={f.desde ?? ""} onChange={(e) => poner("desde", e.target.value)} /></label>
        <label className="rv-campo">Hasta<input type="date" value={f.hasta ?? ""} onChange={(e) => poner("hasta", e.target.value)} /></label>
        <label className="rv-campo">Contrato<input type="text" inputMode="numeric" value={f.contrato ?? ""} maxLength={12} onChange={(e) => poner("contrato", e.target.value.replace(/\D/g, ""))} data-filtro="contrato" /></label>
        <label className="rv-campo">Operario<input type="text" value={f.operario ?? ""} maxLength={80} placeholder="Correo" onChange={(e) => poner("operario", e.target.value)} /></label>
        <label className="rv-campo">Actividades derivadas<select value={f.derivadas ?? ""} onChange={(e) => poner("derivadas", e.target.value)} data-filtro="derivadas">
          <option value="">Todas</option><option value="con">Con actividades derivadas</option><option value="pendientes">Con derivadas pendientes</option><option value="atendidas">Con derivadas atendidas</option></select></label>
        <div className="rv-botones"><button type="submit" className="rv-boton">Buscar</button><button type="button" className="rv-boton-sec" onClick={() => void descargar()} disabled={!filas || filas.length === 0}>Descargar CSV</button></div>
      </form>
      {descarga ? <div className="rv-aviso rv-aviso-ok" role="status">{descarga}</div> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => void cargar(aplicados, null)}>Reintentar</button></div> : null}
      {!filas && !error ? <p className="rv-sub" role="status">Cargando…</p> : null}
      {filas && filas.length === 0 && !error ? <div className="rv-vacio">No hay registros con esos filtros.</div> : null}
      <ul className="rv-per-lista">
        {(filas ?? []).map((r) => <FilaRegistro key={`${r.esquema}:${r.registro_id}`} r={r} nombreTipo={nombreTipo(r.tipo)} />)}
      </ul>
      {siguiente ? <button type="button" className="rv-boton-sec" onClick={() => void cargar(aplicados, siguiente)}>Ver más</button> : null}
    </section>
  );
}

/** Estado del PDF de un registro con valor probatorio: la MISMA marca en «Actas registradas» y en el detalle de Supervisión (27-nov). */
export function MarcaPdf({ r }: { r: FilaActa }) {
  return <span className={`rv-marca ${pdfListo(r) ? "rv-marca-info" : "rv-marca-amar"}`} data-pdf-estado={pdfListo(r) ? "listo" : "pendiente"}>{pdfListo(r) ? "PDF listo" : "PDF pendiente"}</span>;
}
/** El botón del PDF de un registro, el MISMO en «Actas registradas» y en el detalle de Supervisión (27-nov): con PDF, «Descargar el PDF» (pdf_url, auditado);
 *  sin PDF, «Generar el PDF» (pdf_generar). Mismas llamadas, mismo permiso y misma auditoría: los decide el servidor. */
export function PdfDeFila({ r }: { r: FilaActa }) {
  const [pedirPdf, setPedirPdf] = useState(false);
  return pdfListo(r) ? <PdfRegistro esquema={r.esquema as Esquema} registroId={r.registro_id} soloLeer />
    : pedirPdf ? <PdfRegistro esquema={r.esquema as Esquema} registroId={r.registro_id} />
    : <div className="rv-botones"><button type="button" className="rv-boton-sec" onClick={() => setPedirPdf(true)}>Generar el PDF</button></div>;
}

function FilaRegistro({ r, nombreTipo }: { r: FilaActa; nombreTipo: string }) {
  const firmas = [r.firmas.operario ? "operario" : "sin firma del operario", r.firmas.usuario ? ESTADO_USUARIO[r.firmas.usuario] : null, r.firmas.testigo ? "testigo" : null].filter(Boolean).join(" · ");
  return (
    <li className="rv-per-tarjeta" data-registro={r.registro_id} data-esquema={r.esquema}>
      <div className="rv-per-cab">
        <div><strong>{r.consecutivo ?? "Sin consecutivo"}</strong>{r.numero_fisico ? <span className="rv-tenue"> · papel {r.numero_fisico}</span> : null}<div className="rv-tenue">{r.tipo_nombre || nombreTipo}</div></div>
        <MarcaPdf r={r} />
      </div>
      <dl className="rv-per-dl">
        <dt>Fecha</dt><dd>{fecha(r.registrado_en ?? r.fecha)}</dd>
        <dt>Operario</dt><dd>{r.operario}</dd>
        <dt>Contrato</dt><dd>{r.contrato ?? <span className="rv-tenue">Sin contrato</span>}{r.barrio ? ` · ${r.barrio}` : ""}</dd>
        {r.resultado ? <><dt>Resultado</dt><dd>{RESULTADO[r.resultado] ?? r.resultado}</dd></> : null}
        <dt>Firmas</dt><dd data-dato="firmas">{firmas}</dd>
        {r.derivadas.total ? <><dt>Derivadas</dt><dd data-dato="derivadas">{r.derivadas.total} {r.derivadas.total === 1 ? "actividad" : "actividades"}{r.derivadas.pendientes ? ` · ${r.derivadas.pendientes} pendiente${r.derivadas.pendientes === 1 ? "" : "s"}` : " · atendidas"}</dd></> : null}
      </dl>
      <PdfDeFila r={r} />
    </li>
  );
}
