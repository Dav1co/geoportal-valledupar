import { useCallback, useEffect, useMemo, useState } from "react";
import "../dashboard/revision.css";
import "./documentos.css";
import { ErrorCampo } from "../apiCampo";
import { AperturasSinRegistrar } from "../acta/AperturasSinRegistrar";
import { PersonalCampo } from "../dashboard/PersonalCampo";
import { Cuadrillas } from "../dashboard/Cuadrillas";
import { apiDocumentos, type DatosAviso, type Esquema, type FilaActa, type FilaDerivada, type FiltrosActas } from "./apiDocumentos";
import { apiCampo } from "../apiCampo";
import type { TipoFormato } from "../formatos/tipos";
import "../analisis/analisis.css";
import { antiguedadTexto } from "../analisis/observacion";
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

export function ActasRegistradas({ correo, onVolver, nombres, puedeAperturas, puedeCerrarDerivadas }: {
  correo: string; onVolver: () => void;
  /** Nombre de cada formulario por su clave («acta» o el código del formato), del catálogo que ya cargó Formatos de campo. */
  nombres: Map<string, string>;
  puedeAperturas: boolean; puedeCerrarDerivadas: boolean;
}) {
  const [seccion, setSeccion] = useState<Seccion>("actas");
  const secciones: { clave: Seccion; titulo: string }[] = [
    { clave: "actas", titulo: "Actas registradas" }, ...(puedeCerrarDerivadas ? [{ clave: "derivadas" as Seccion, titulo: "Actividades derivadas" }] : []),
    ...(puedeAperturas ? [{ clave: "aperturas" as Seccion, titulo: "Aperturas sin registrar" }] : []), { clave: "personal", titulo: "Personal" },
  ];
  return (
    <div className="rv">
      <div className="rv-cab">
        <div className="rv-ancho">
          <div className="rv-fila"><h1>Actas registradas</h1><button type="button" className="rv-boton-claro" onClick={onVolver}>← Volver a Formatos de campo</button></div>
          <div className="rv-sesion">{correo}</div>
          <nav className="rv-tabs" aria-label="Secciones de las actas">
            {secciones.map((s) => <button key={s.clave} type="button" className="rv-tab" aria-current={seccion === s.clave ? "page" : undefined} onClick={() => setSeccion(s.clave)}>{s.titulo}</button>)}
          </nav>
        </div>
      </div>
      <div className="rv-cuerpo">
        {seccion === "actas" ? <ListaActas nombres={nombres} via={puedeAperturas ? "acta" : "campo"} />
          : seccion === "derivadas" ? <Derivadas puedeCerrar={puedeCerrarDerivadas} />
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

function FilaRegistro({ r, nombreTipo }: { r: FilaActa; nombreTipo: string }) {
  const [pedirPdf, setPedirPdf] = useState(false);
  const firmas = [r.firmas.operario ? "operario" : "sin firma del operario", r.firmas.usuario ? ESTADO_USUARIO[r.firmas.usuario] : null, r.firmas.testigo ? "testigo" : null].filter(Boolean).join(" · ");
  return (
    <li className="rv-per-tarjeta" data-registro={r.registro_id} data-esquema={r.esquema}>
      <div className="rv-per-cab">
        <div><strong>{r.consecutivo ?? "Sin consecutivo"}</strong>{r.numero_fisico ? <span className="rv-tenue"> · papel {r.numero_fisico}</span> : null}<div className="rv-tenue">{r.tipo_nombre || nombreTipo}</div></div>
        <span className={`rv-marca ${pdfListo(r) ? "rv-marca-info" : "rv-marca-amar"}`}>{pdfListo(r) ? "PDF listo" : "PDF pendiente"}</span>
      </div>
      <dl className="rv-per-dl">
        <dt>Fecha</dt><dd>{fecha(r.registrado_en ?? r.fecha)}</dd>
        <dt>Operario</dt><dd>{r.operario}</dd>
        <dt>Contrato</dt><dd>{r.contrato ?? <span className="rv-tenue">Sin contrato</span>}{r.barrio ? ` · ${r.barrio}` : ""}</dd>
        {r.resultado ? <><dt>Resultado</dt><dd>{RESULTADO[r.resultado] ?? r.resultado}</dd></> : null}
        <dt>Firmas</dt><dd data-dato="firmas">{firmas}</dd>
        {r.derivadas.total ? <><dt>Derivadas</dt><dd data-dato="derivadas">{r.derivadas.total} {r.derivadas.total === 1 ? "actividad" : "actividades"}{r.derivadas.pendientes ? ` · ${r.derivadas.pendientes} pendiente${r.derivadas.pendientes === 1 ? "" : "s"}` : " · atendidas"}</dd></> : null}
      </dl>
      {pdfListo(r) ? <PdfRegistro esquema={r.esquema as Esquema} registroId={r.registro_id} soloLeer />
        : pedirPdf ? <PdfRegistro esquema={r.esquema as Esquema} registroId={r.registro_id} />
        : <div className="rv-botones"><button type="button" className="rv-boton-sec" onClick={() => setPedirPdf(true)}>Generar el PDF</button></div>}
    </li>
  );
}

function Derivadas({ puedeCerrar }: { puedeCerrar: boolean }) {
  const [estado, setEstado] = useState("pendiente");
  const [contrato, setContrato] = useState("");
  const [origen, setOrigen] = useState<"" | "registro" | "analisis">("");
  const [filas, setFilas] = useState<FilaDerivada[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [cerrar, setCerrar] = useState<FilaDerivada | null>(null);
  const [crear, setCrear] = useState<FilaDerivada | null>(null);
  const [verDatos, setVerDatos] = useState<FilaDerivada | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => {
    let vivo = true; setFilas(null); setError(null);
    const t = window.setTimeout(() => apiDocumentos.derivadas({ estado: estado || undefined, contrato: contrato || undefined, origen: origen || undefined, limite: 100 })
      .then((r) => { if (vivo) setFilas(r.filas); }).catch((e) => { if (vivo) setError(texto(e)); }), 250);
    return () => { vivo = false; window.clearTimeout(t); };
  }, [estado, contrato, origen, vez]);
  const cuando = useMemo(() => (f: string) => new Date(f).toLocaleDateString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric" }), []);
  const hecho = (t: string) => { setCerrar(null); setCrear(null); setAviso(t); setVez((x) => x + 1); };
  return (
    <section className="rv-seccion" aria-labelledby="doc-der-tit" data-testid="derivadas">
      <div><h2 id="doc-der-tit">Actividades derivadas</h2>
        <p className="rv-sub">Lo que dejaron las revisiones en «¿Da lugar a otras actividades?» y los avisos del Análisis de contrato. Las actividades se marcan atendidas solas cuando el formulario que las atiende se registra sobre el mismo contrato.{puedeCerrar ? " Desde un aviso puede crear la actividad; si se hizo sin formulario, o no procede, ciérrelo con motivo." : ""}</p></div>
      <div className="doc-filtros">
        <label className="rv-campo">Estado<select value={estado} onChange={(e) => setEstado(e.target.value)} data-filtro="estado"><option value="pendiente">Pendientes</option><option value="atendida">Atendidas</option><option value="">Todas</option></select></label>
        <label className="rv-campo">Origen<select value={origen} onChange={(e) => setOrigen(e.target.value as "" | "registro" | "analisis")} data-filtro="origen">
          <option value="">Todos</option><option value="registro">Revisiones</option><option value="analisis">Análisis de contrato</option></select></label>
        <label className="rv-campo">Contrato<input type="text" inputMode="numeric" value={contrato} maxLength={12} onChange={(e) => setContrato(e.target.value.replace(/\D/g, ""))} /></label>
      </div>
      {aviso ? <div className="rv-aviso rv-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {!filas && !error ? <p className="rv-sub" role="status">Cargando…</p> : null}
      {filas && filas.length === 0 ? <div className="rv-vacio">{estado === "pendiente" ? "No hay actividades derivadas pendientes." : "No hay actividades derivadas con ese filtro."}</div> : null}
      <ul className="rv-per-lista">
        {(filas ?? []).map((d) => {
          const o = d.origen, esAviso = d.actividad.startsWith("aviso_"), deAnalisis = o.clase === "analisis";
          return (
          <li key={d.id} className="rv-per-tarjeta" data-derivada={d.id} data-origen={deAnalisis ? "analisis" : "registro"}>
            <div className="rv-per-cab"><div><strong>{d.actividad === "actividad_supervisor" && d.destino_nombre ? `Actividad: ${d.destino_nombre}` : d.actividad_nombre}</strong><div className="rv-tenue">Contrato {d.contrato ?? "—"}</div></div>
              <span className={`rv-marca ${d.estado === "pendiente" ? "rv-marca-amar" : "rv-marca-gris"}`}>{d.estado === "pendiente" ? "Pendiente" : d.estado === "atendida" ? "Atendida" : d.estado === "atendida_fuera" ? "Atendida sin formulario" : d.estado === "anulada" ? "Anulada" : d.estado}</span></div>
            <dl className="rv-per-dl">
              <dt>Viene de</dt><dd>{deAnalisis ? `Análisis de contrato · ${o.observacion_nombre ?? ""} · ${o.operario ?? ""} · ${cuando(o.fecha)}` : `${o.consecutivo ?? o.tipo} · ${cuando(o.fecha)}`}</dd>
              {o.direccion_correcta ? <><dt>Dirección correcta</dt><dd>{o.direccion_correcta}</dd></> : null}
              {o.texto ? <><dt>Observación</dt><dd>{o.texto}</dd></> : null}
              {esAviso && d.antiguedad_dias !== undefined ? <><dt>Antigüedad</dt><dd data-dato="antiguedad">{antiguedadTexto(d.antiguedad_dias)}</dd></> : null}
              {esAviso && o.vistos ? <><dt>Visto otra vez</dt><dd data-dato="vistos">{o.vistos} {o.vistos === 1 ? "vez" : "veces"}{o.ultimo_visto ? ` · último ${cuando(o.ultimo_visto.en)} por ${o.ultimo_visto.autor}` : ""}</dd></> : null}
              {esAviso && o.trae_datos ? <><dt>Datos de contacto</dt><dd>{o.datos_anulados ? "Anulados" : "Sí (se ven al abrirlos)"}</dd></> : null}
              {d.cierre?.tipo === "atendida" ? <><dt>La atendió</dt><dd>{d.cierre.consecutivo ?? "un registro"} · {cuando(d.cierre.en)}</dd></> : null}
              {d.cierre && d.cierre.tipo !== "atendida" ? <><dt>{d.cierre.tipo === "anulada" ? "Anulada" : "Cerrada sin formulario"}</dt><dd>{cuando(d.cierre.en)} · por {d.cierre.autor}</dd></> : null}
              {d.cierre?.motivo ? <><dt>Motivo</dt><dd>{d.cierre.motivo}</dd></> : null}
            </dl>
            {puedeCerrar ? <div className="rv-botones">
              {esAviso && d.estado === "pendiente" ? <button type="button" className="rv-boton" data-accion="crear" onClick={() => { setAviso(null); setCrear(d); }}>Crear actividad</button> : null}
              {esAviso && o.trae_datos ? <button type="button" className="rv-boton-sec" data-accion="datos" onClick={() => { setAviso(null); setVerDatos(d); }}>Ver datos de contacto</button> : null}
              {d.estado === "pendiente" ? <button type="button" className="rv-boton-sec" data-accion="cerrar" onClick={() => { setAviso(null); setCerrar(d); }}>Cerrar sin formulario</button> : null}
            </div> : null}
          </li>); })}
      </ul>
      {cerrar ? <CerrarDerivada d={cerrar} onCancelar={() => setCerrar(null)} onHecho={hecho} /> : null}
      {crear ? <CrearActividad d={crear} onCancelar={() => setCrear(null)} onHecho={hecho} /> : null}
      {verDatos ? <DatosContacto d={verDatos} onCerrar={(cambio) => { setVerDatos(null); if (cambio) setVez((x) => x + 1); }} /> : null}
    </section>
  );
}

/** «Crear actividad» desde un aviso (Q1): el supervisor elige un formulario activo que pida el contrato; el aviso se cierra solo y la actividad queda pendiente
 *  hasta que el operario registre ese formulario con «¿Viene de…?». Una sola por aviso. */
function CrearActividad({ d, onCancelar, onHecho }: { d: FilaDerivada; onCancelar: () => void; onHecho: (t: string) => void }) {
  const [formularios, setFormularios] = useState<{ codigo: string; nombre: string }[] | null>(null);
  const [form, setForm] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    apiCampo.formulario().then((f) => {
      if (!vivo) return;
      const l = f.grupos.filter((g) => g.activo).flatMap((g) => g.tipos as TipoFormato[]).filter((t) => t.activo && t.requiere_contrato === "si").map((t) => ({ codigo: t.codigo, nombre: t.nombre }));
      setFormularios(l); if (d.origen.observacion === "direccion_errada" && l.some((t) => t.codigo === "investigacion_ubicacion")) setForm("investigacion_ubicacion");
    }).catch((e) => { if (vivo) setError(texto(e)); });
    return () => { vivo = false; };
  }, [d]);
  return (
    <div className="rv-modal-fondo"><div className="rv-modal" role="dialog" aria-modal="true" aria-label={`Crear actividad desde ${d.actividad_nombre}`} data-testid="crear-actividad">
      <h3>Crear actividad · contrato {d.contrato}</h3>
      <p className="rv-sub">El aviso «{d.actividad_nombre}» queda cerrado como atendido sin formulario, y la actividad le aparece al operario que abra ese formulario con este contrato.</p>
      {formularios === null && !error ? <p className="rv-sub" role="status">Cargando los formularios…</p> : null}
      {formularios ? <label className="rv-campo">Formulario<select value={form} onChange={(e) => setForm(e.target.value)} data-campo="formulario">
        <option value="">Elija el formulario</option>{formularios.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}</select></label> : null}
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || !form} onClick={() => { setEnviando(true); setError(null);
          apiDocumentos.avisoCrearActividad(d.id, `tipo:${form}`).then((r) => onHecho(`Se creó «${r.actividad.destino_nombre ?? form}» para el contrato ${d.contrato}. El aviso quedó cerrado.`))
            .catch((e) => { setError(texto(e)); setEnviando(false); }); }}>{enviando ? "Creando…" : "Crear"}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </div></div>
  );
}

const RELACION: Record<string, string> = { propietario: "Propietario", arrendatario: "Arrendatario", familiar: "Familiar", encargado: "Encargado", otro: "Otro" };
/** Datos de contacto de un aviso (Ley 1581): se piden al abrir (lectura auditada), no se guardan en el navegador y se olvidan al cerrar. Anulados: solo el motivo. */
function DatosContacto({ d, onCerrar }: { d: FilaDerivada; onCerrar: (cambio: boolean) => void }) {
  const [r, setR] = useState<DatosAviso | null>(null); const [error, setError] = useState<string | null>(null);
  const [anular, setAnular] = useState(false); const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [cambio, setCambio] = useState(false);
  const cargar = useCallback(() => { setError(null); apiDocumentos.avisoDatos(d.id).then(setR).catch((e) => setError(texto(e))); }, [d.id]);
  useEffect(() => { cargar(); return () => setR(null); }, [cargar]);
  const malo = m.trim().length < 10 || m.trim().length > 300;
  const x = r?.datos;
  return (
    <div className="rv-modal-fondo"><div className="rv-modal" role="dialog" aria-modal="true" aria-label="Datos de contacto" data-testid="datos-contacto">
      <h3>Datos de contacto · contrato {d.contrato}</h3>
      <p className="rv-sub"><span className="ac-tag-personal">dato personal</span> Úselos solo para actualizar los datos del suscriptor. No los copie a listas ni descargas.</p>
      {!r && !error ? <p className="rv-sub" role="status">Cargando…</p> : null}
      {r?.anulados ? <div className="rv-aviso" role="status" data-datos="anulados"><strong>Anulados</strong>{r.motivo ? ` · ${r.motivo}` : ""}</div> : null}
      {x ? <dl className="rv-per-dl" data-datos="vigentes">
        {x.nombre ? <><dt>Nombre</dt><dd>{x.nombre}</dd></> : null}
        {x.cedula ? <><dt>Cédula</dt><dd>{x.cedula}</dd></> : null}
        {x.telefono ? <><dt>Teléfono</dt><dd>{x.telefono}</dd></> : null}
        {x.correo ? <><dt>Correo</dt><dd>{x.correo}</dd></> : null}
        {x.relacion ? <><dt>Relación con el predio</dt><dd>{RELACION[x.relacion] ?? x.relacion}</dd></> : null}
      </dl> : null}
      {anular && x ? <label className="rv-campo">Por qué se anulan (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(e) => setM(e.target.value)} /></label> : null}
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        {x && !anular ? <button type="button" className="rv-boton-sec" data-accion="anular" onClick={() => setAnular(true)}>Anular estos datos</button> : null}
        {x && anular ? <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => { setEnviando(true); setError(null);
          apiDocumentos.avisoDatosAnular(d.id, m.trim()).then(() => { setAnular(false); setM(""); setCambio(true); setR(null); cargar(); }).catch((e) => setError(texto(e))).finally(() => setEnviando(false)); }}>{enviando ? "Anulando…" : "Anular"}</button> : null}
        <button type="button" className="rv-boton-sec" onClick={() => { setR(null); onCerrar(cambio); }}>Cerrar</button>
      </div>
    </div></div>
  );
}

function CerrarDerivada({ d, onCancelar, onHecho }: { d: FilaDerivada; onCancelar: () => void; onHecho: (t: string) => void }) {
  const [tipo, setTipo] = useState<"atendida_fuera" | "anulada">("atendida_fuera");
  const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const malo = m.trim().length < 10 || m.trim().length > 300;
  return (
    <div className="rv-modal-fondo"><div className="rv-modal" role="dialog" aria-modal="true" aria-label={`Cerrar ${d.actividad_nombre}`}>
      <h3>Cerrar «{d.actividad_nombre}»</h3>
      <div className="doc-opciones" role="radiogroup" aria-label="Cómo se cierra">
        <label className={`doc-opcion${tipo === "atendida_fuera" ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-cierre" checked={tipo === "atendida_fuera"} onChange={() => setTipo("atendida_fuera")} />Se hizo sin formulario</label>
        <label className={`doc-opcion${tipo === "anulada" ? " doc-opcion-on" : ""}`}><input type="radio" name="doc-cierre" checked={tipo === "anulada"} onChange={() => setTipo("anulada")} />No procede (anular)</label>
      </div>
      <label className="rv-campo">Motivo (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(e) => setM(e.target.value)} /></label>
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => { setEnviando(true); setError(null);
          apiDocumentos.derivadaCerrar(d.id, tipo, m.trim()).then(() => onHecho(`«${d.actividad_nombre}» quedó cerrada. No se borra: queda en el historial.`)).catch((e) => { setError(texto(e)); setEnviando(false); }); }}>{enviando ? "Guardando…" : "Cerrar"}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </div></div>
  );
}
