import { useEffect, useRef, useState } from "react";
import { ErrorCampo } from "../apiCampo";
import { apiDocumentos, type ActaAbierta, type Derivada, type DocumentoFormulario, type Esquema, type Pdf } from "./apiDocumentos";
import "./documentos.css";

// Piezas de los formularios con valor probatorio (Comercial 21-nov): qué lleva cada formulario (catálogo del servidor), el PDF después de registrar y «¿Viene de…?»
// (actividades derivadas pendientes y actas de posible pérdida del mismo contrato).

const cacheCatalogo = new Map<Esquema, Promise<DocumentoFormulario[]>>();
/** Lo que lleva un formulario según el servidor (documentos_catalogo). `undefined` mientras carga; `null` si no lleva nada o el servidor aún no tiene la ruta. */
export function useDocumento(esquema: Esquema, clave: string): DocumentoFormulario | null | undefined {
  const [doc, setDoc] = useState<DocumentoFormulario | null | undefined>(undefined);
  useEffect(() => {
    let vivo = true;
    let p = cacheCatalogo.get(esquema);
    if (!p) { p = apiDocumentos.catalogo(esquema).then((r) => r.formularios); cacheCatalogo.set(esquema, p); p.catch(() => cacheCatalogo.delete(esquema)); }
    p.then((fs) => { if (vivo) setDoc(fs.find((f) => f.formulario === clave) ?? null); })
      .catch(() => { if (vivo) setDoc(null); });            // sin la ruta (servidor anterior) o sin red: el formulario sigue como hoy, sin firmas
    return () => { vivo = false; };
  }, [esquema, clave]);
  return doc;
}

const texto = (e: unknown) => (e instanceof ErrorCampo ? e.message : "No se pudo completar la operación.");
const kb = (b: number) => (b >= 1048576 ? `${(b / 1048576).toLocaleString("es-CO", { maximumFractionDigits: 1 })} MB` : `${Math.max(1, Math.round(b / 1024)).toLocaleString("es-CO")} KB`);

/** El PDF de un registro: se pide UNA vez al montarse (pdf_generar; si ya existe devuelve el mismo) o, con `soloLeer`, se lee (pdf_url). Si falla, el registro no se pierde: «Reintentar». */
export function PdfRegistro({ esquema, registroId, soloLeer = false }: { esquema: Esquema; registroId: string; soloLeer?: boolean }) {
  const [pdf, setPdf] = useState<Pdf | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(!soloLeer);
  const pedido = useRef(false);
  const generar = () => {
    setCargando(true); setError(null);
    apiDocumentos.pdfGenerar(esquema, registroId).then(setPdf).catch((e) => setError(texto(e))).finally(() => setCargando(false));
  };
  useEffect(() => { if (!soloLeer && !pedido.current) { pedido.current = true; generar(); } }, []);    // eslint-disable-line react-hooks/exhaustive-deps
  const abrir = async () => {
    try { const p = await apiDocumentos.pdfUrl(esquema, registroId); setPdf(p); window.open(p.url, "_blank", "noopener"); }
    catch (e) { setError(texto(e)); }
  };
  return (
    <div className="doc-pdf" data-testid="pdf-registro">
      {cargando ? <p className="campo-sub" role="status">Preparando el PDF del acta…</p> : null}
      {pdf ? <>
        <p className="campo-sub" role="status">PDF listo: <span className="doc-pdf-nombre">{pdf.nombre}</span> ({kb(pdf.bytes)}{pdf.version > 1 ? `, versión ${pdf.version}` : ""}).</p>
        <button type="button" className="tec-boton-sec" onClick={() => void abrir()}>Descargar el PDF</button></> : null}
      {error ? <>
        <p className="campo-nota" role="alert">{error} El registro quedó guardado; el PDF se puede pedir otra vez aquí o desde «Actas registradas».</p>
        <button type="button" className="tec-boton-sec" onClick={generar} disabled={cargando}>Reintentar el PDF</button></> : null}
      {soloLeer && !pdf && !error ? <button type="button" className="tec-boton-sec" onClick={() => void abrir()}>Descargar el PDF</button> : null}
    </div>
  );
}

export type Origen = { derivada: number | null; acta: string | null };
export const SIN_ORIGEN: Origen = { derivada: null, acta: null };
/** «¿Viene de…?»: con el contrato escrito, las actividades derivadas pendientes que este formulario atiende (derivadas_abiertas) y, en las revisiones, las actas de posible pérdida
 *  del mismo contrato (actas_abiertas). La persona marca una o «Ninguna». El enlace se guarda DESPUÉS de registrar (derivada_atender / origen_vincular). */
export function VieneDe({ contrato, formulario, conActas, valor, onCambio, deshabilitado }: {
  contrato: string; formulario: string; conActas: boolean; valor: Origen; onCambio: (o: Origen) => void; deshabilitado: boolean;
}) {
  const [der, setDer] = useState<Derivada[]>([]);
  const [actas, setActas] = useState<ActaAbierta[]>([]);
  useEffect(() => {
    const c = contrato.trim(); setDer([]); setActas([]);
    if (!/^\d{3,12}$/.test(c)) return;
    let vivo = true;
    const t = window.setTimeout(() => {
      apiDocumentos.derivadasAbiertas(c, formulario).then((r) => { if (vivo) setDer(r.derivadas); }).catch(() => { /* sin la ruta o sin red: no se ofrece */ });
      if (conActas) apiDocumentos.actasAbiertas(c).then((r) => { if (vivo) setActas(r.actas); }).catch(() => { /* idem */ });
    }, 400);
    return () => { vivo = false; window.clearTimeout(t); };
  }, [contrato, formulario, conActas]);
  if (der.length === 0 && actas.length === 0) return null;
  const fecha = (f: string) => new Date(f).toLocaleDateString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric" });
  return (
    <fieldset className="campo-fieldset" disabled={deshabilitado} data-testid="viene-de">
      <legend className="campo-etiqueta">¿Viene de otra actividad?</legend>
      {der.length ? <>
        <p className="campo-sub">Este contrato tiene actividades pendientes que este formulario atiende. Si esta visita atiende una, márquela: quedará como atendida.</p>
        <div className="doc-opciones" role="radiogroup" aria-label="Actividad pendiente que atiende">
          {der.map((d) => <label key={d.id} className={`doc-opcion${valor.derivada === d.id ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-derivada" data-derivada={d.id} checked={valor.derivada === d.id} onChange={() => onCambio({ ...valor, derivada: d.id })} />
            {d.actividad_nombre} <small className="campo-sub">· de {d.origen.consecutivo ?? d.origen.tipo} del {fecha(d.origen.fecha)}</small></label>)}
          <label className={`doc-opcion${valor.derivada === null ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-derivada" data-derivada="ninguna" checked={valor.derivada === null} onChange={() => onCambio({ ...valor, derivada: null })} />Ninguna</label>
        </div></> : null}
      {actas.length ? <>
        <p className="campo-sub">¿Viene de un reporte de posible pérdida de este contrato?</p>
        <div className="doc-opciones" role="radiogroup" aria-label="Reporte de posible pérdida de origen">
          {actas.map((a) => <label key={a.acta_id} className={`doc-opcion${valor.acta === a.acta_id ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-acta" data-acta={a.acta_id} checked={valor.acta === a.acta_id} onChange={() => onCambio({ ...valor, acta: a.acta_id })} />
            {a.consecutivo ?? "Acta"} <small className="campo-sub">· {fecha(a.fecha)}</small></label>)}
          <label className={`doc-opcion${valor.acta === null ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-acta" data-acta="ninguna" checked={valor.acta === null} onChange={() => onCambio({ ...valor, acta: null })} />No</label>
        </div></> : null}
    </fieldset>
  );
}

/** Guarda el enlace con el origen DESPUÉS de registrar. Devuelve el texto de lo que no se pudo (se puede reintentar), o null. */
export async function vincularOrigen(registroId: string, o: Origen): Promise<string | null> {
  const fallas: string[] = [];
  if (o.derivada !== null) await apiDocumentos.derivadaAtender(o.derivada, registroId).catch((e) => fallas.push(`la actividad pendiente (${texto(e)})`));
  if (o.acta !== null) await apiDocumentos.origenVincular(registroId, o.acta).catch((e) => fallas.push(`el reporte de posible pérdida (${texto(e)})`));
  return fallas.length ? `No se pudo marcar ${fallas.join(" ni ")}.` : null;
}
