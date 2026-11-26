import { useCallback, useEffect, useMemo, useState } from "react";
import "../dashboard/revision.css";
import "./documentos.css";
import "../analisis/analisis.css";
import { ErrorCampo, apiCampo } from "../apiCampo";
import { apiDocumentos, type DatosAviso, type FilaDerivada } from "./apiDocumentos";
import type { TipoFormato } from "../formatos/tipos";
import { antiguedadTexto } from "../analisis/observacion";

// «Avisos y actividades derivadas» (23-nov; 25-nov: salió de ActasRegistradas.tsx sin cambiar su comportamiento). Es el ÚNICO sitio donde se atiende y se cierra (Crear actividad,
// Ver datos de contacto, Cerrar sin formulario). «Reportes» (Supervisión y dashboard) solo consulta y descarga; desde allí se llega aquí.
const texto = (e: unknown) => (e instanceof ErrorCampo ? e.message : "No se pudo completar la operación.");

export function Derivadas({ puedeCerrar, onCambio }: { puedeCerrar: boolean; onCambio?: () => void }) {
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
  const hecho = (t: string) => { setCerrar(null); setCrear(null); setAviso(t); setVez((x) => x + 1); onCambio?.(); };
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
              {esAviso && o.trae_datos ? <><dt>Datos de contacto</dt><dd data-dato="entregas">{o.datos_anulados ? "Anulados" : `${o.entregas_datos ?? 1} ${(o.entregas_datos ?? 1) === 1 ? "entrega" : "entregas"}${o.entregas_vigentes !== undefined && o.entregas_vigentes !== o.entregas_datos ? ` (${o.entregas_vigentes} vigente${o.entregas_vigentes === 1 ? "" : "s"})` : ""} · se ven al abrirlos`}</dd></> : null}
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
      {verDatos ? <DatosContacto d={verDatos} onCerrar={(cambio) => { setVerDatos(null); if (cambio) { setVez((x) => x + 1); onCambio?.(); } }} /> : null}
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
/** Datos de contacto de un aviso (Ley 1581): se piden al abrir (lectura auditada), no se guardan en el navegador y se olvidan al cerrar.
 *  7.4 (David, 24-nov): cada entrega con su relación, autor y fecha; las posibles duplicadas marcadas; cada una se anula con motivo. Anuladas: solo el motivo. */
function DatosContacto({ d, onCerrar }: { d: FilaDerivada; onCerrar: (cambio: boolean) => void }) {
  const [r, setR] = useState<DatosAviso | null>(null); const [error, setError] = useState<string | null>(null);
  const [anular, setAnular] = useState<number | null>(null); const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [cambio, setCambio] = useState(false);
  const cargar = useCallback(() => { setError(null); apiDocumentos.avisoDatos(d.id).then(setR).catch((e) => setError(texto(e))); }, [d.id]);
  useEffect(() => { cargar(); return () => setR(null); }, [cargar]);
  const malo = m.trim().length < 10 || m.trim().length > 300;
  const cuando = (f: string) => new Date(f).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  return (
    <div className="rv-modal-fondo"><div className="rv-modal" role="dialog" aria-modal="true" aria-label="Datos de contacto" data-testid="datos-contacto">
      <h3>Datos de contacto · contrato {d.contrato}</h3>
      <p className="rv-sub"><span className="ac-tag-personal">dato personal</span> Úselos solo para actualizar los datos del suscriptor. No los copie a listas ni descargas.</p>
      {!r && !error ? <p className="rv-sub" role="status">Cargando…</p> : null}
      {r ? <p className="rv-sub" data-datos="resumen">{r.total === 1 ? "1 entrega" : `${r.total} entregas`} · {r.vigentes === 1 ? "1 vigente" : `${r.vigentes} vigentes`}</p> : null}
      {(r?.entregas ?? []).map((e, i) => (
        <div key={e.id} className="rv-per-tarjeta" data-entrega={e.id} data-anulada={e.anulada ? "si" : "no"}>
          <div className="rv-per-cab"><div><strong>Entrega {i + 1}{e.relacion ? ` · ${RELACION[e.relacion] ?? e.relacion}` : ""}</strong>
            <div className="rv-tenue">{e.autor} · {cuando(e.registrado_en)}</div></div>
            {e.anulada ? <span className="rv-marca rv-marca-gris">Anulada</span> : e.posible_duplicado ? <span className="rv-marca rv-marca-amar" data-marca="duplicado">Posible duplicado</span> : null}</div>
          {e.anulada ? <p className="rv-sub">Motivo: {e.motivo}{e.anulada_por ? ` · por ${e.anulada_por}` : ""}</p> : (
            <dl className="rv-per-dl">
              {e.datos?.nombre ? <><dt>Nombre</dt><dd>{e.datos.nombre}</dd></> : null}
              {e.datos?.cedula ? <><dt>Cédula</dt><dd>{e.datos.cedula}</dd></> : null}
              {e.datos?.telefono ? <><dt>Teléfono</dt><dd>{e.datos.telefono}</dd></> : null}
              {e.datos?.correo ? <><dt>Correo</dt><dd>{e.datos.correo}</dd></> : null}
              {e.datos?.relacion ? <><dt>Relación con el predio</dt><dd>{RELACION[e.datos.relacion] ?? e.datos.relacion}</dd></> : null}
            </dl>)}
          {!e.anulada && anular !== e.id ? <div className="rv-botones"><button type="button" className="rv-boton-sec" data-accion="anular" onClick={() => { setAnular(e.id); setM(""); }}>Anular esta entrega</button></div> : null}
          {!e.anulada && anular === e.id ? <>
            <label className="rv-campo">Por qué se anula (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(ev) => setM(ev.target.value)} /></label>
            <div className="rv-botones">
              <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => { setEnviando(true); setError(null);
                apiDocumentos.avisoDatosAnular(d.id, e.id, m.trim()).then(() => { setAnular(null); setM(""); setCambio(true); setR(null); cargar(); }).catch((x) => setError(texto(x))).finally(() => setEnviando(false)); }}>{enviando ? "Anulando…" : "Anular"}</button>
              <button type="button" className="rv-boton-sec" disabled={enviando} onClick={() => setAnular(null)}>Cancelar</button>
            </div></> : null}
        </div>))}
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
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
