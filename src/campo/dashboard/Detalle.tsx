import type { DireccionContratoDetalle } from "./apiRevision";
import { useCallback, useEffect, useRef, useState } from "react";
import { apiRev, textoError, type Cercano, type DetalleResp, type EventoRep, type FilaReporte, type FormularioRev, type SensiblesResp } from "./apiRevision";
import { columnasBase, paresDeDatos, textoDeDato, textoInicio, textoDuracion, type Contexto } from "./columnas";
import { fmtInstante, fmtNumero } from "./formatoRevision";
import { ErrorCampo } from "../apiCampo";

// Detalle de un reporte: datos completos (la descripción entera), campos propios del tipo, línea de tiempo de eventos (nada se edita), reportes cercanos y fotos BAJO DEMANDA.
// Cada consulta del detalle queda auditada por el servidor (campo_ver_detalle); cada foto y cada lectura de datos sensibles, también. Las URLs de foto duran 60 s: se piden al pulsar,
// se muestran, y al vencer se quitan del DOM («Volver a cargar» pide otra). No se precargan ni se guardan en ningún almacenamiento.
const ROTULO_EVENTO: Record<string, string> = { cambio_estado: "Cambio de estado", ocultar: "Se ocultó el reporte", reincluir: "Se reincluyó el reporte", vincular_duplicado: "Se vinculó como duplicado", nota: "Nota", vincular_acta: "Se vinculó a un acta" };

export function Detalle({ id, def, ctx, onCerrar, onCambio, onAbrir }: {
  id: string; def: FormularioRev; ctx: Contexto; onCerrar: () => void; onCambio: (id: string, parche: Partial<FilaReporte>) => void; onAbrir: (id: string) => void;
}) {
  const [d, setD] = useState<DetalleResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accion, setAccion] = useState<"estado" | "ocultar" | "reincluir" | "duplicado" | null>(null);
  const [sens, setSens] = useState<SensiblesResp | null>(null); const [sensMsg, setSensMsg] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const cargar = useCallback(async () => { try { setD(await apiRev.reporte(id)); setError(null); } catch (e) { setError(textoError(e).texto); } }, [id]);
  useEffect(() => { setD(null); setSens(null); setSensMsg(null); setAviso(null); void cargar(); }, [cargar]);
  useEffect(() => { const t = (e: KeyboardEvent) => { if (e.key === "Escape" && !accion) onCerrar(); }; window.addEventListener("keydown", t); return () => window.removeEventListener("keydown", t); }, [accion, onCerrar]);

  const r = d?.reporte;
  // consultar direcciones (25-nov): en el detalle, direccion_contrato llega como bloque (en la lista y la descarga es texto plano)
  const dcCrudo = r?.direccion_contrato as unknown;
  const dc = dcCrudo && typeof dcCrudo === "object" ? (dcCrudo as DireccionContratoDetalle) : null;
  const base = columnasBase(true);
  const val = (clave: string) => { const c = base.find((x) => x.clave === clave); return r && c ? c.texto(r, ctx) : ""; };

  async function verSensibles() {
    setSensMsg(null);
    try { setSens(await apiRev.sensibles(id)); } catch (e) { setSensMsg(textoError(e).texto); }
  }

  return (
    <aside className="rv-detalle" role="dialog" aria-label="Detalle del reporte">
      <div className="rv-detalle-cab">
        <h2>{r?.consecutivo ? `${r.consecutivo} · ` : ""}{r?.tipo.nombre ?? "Reporte"}</h2>
        <button type="button" className="rv-boton-sec rv-corto" onClick={onCerrar}>Cerrar</button>
      </div>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => void cargar()}>Reintentar</button></div> : null}
      {!d && !error ? <p className="rv-sub" role="status">Cargando el detalle…</p> : null}
      {aviso ? <div className="rv-aviso rv-aviso-ok" role="status">{aviso}</div> : null}
      {d && r ? (
        <>
          <div className="rv-marcas">
            <span className={`rv-estado rv-estado-${r.estado}`}>{val("estado")}</span>
            {r.riesgo_inmediato ? <span className="rv-marca rv-marca-alerta">⚠ Riesgo inmediato</span> : null}
            {r.oculto ? <span className="rv-marca rv-marca-gris">Oculto</span> : null}
            {r.fuera_de_zona ? <span className="rv-marca rv-marca-info">Fuera de zona</span> : null}
            {r.registro?.xy_manual ? <span className="rv-marca rv-marca-amar" data-rf-detalle-xy>XY digitado — registrado desde otro punto</span> : null}
            {r.registro?.sin_ubicacion_dispositivo ? <span className="rv-marca rv-marca-gris">Sin ubicación del dispositivo</span> : null}
            {d.fotos.some((f) => f.origen && f.origen !== "camara") ? <span className="rv-marca rv-marca-info">Fotos adjuntadas</span> : null}
            {r.contrato && r.contrato_verificado === false ? <span className="rv-marca rv-marca-amar">Contrato sin verificar</span> : null}
            {r.grupo_duplicados ? <span className="rv-marca rv-marca-dup">◎ Posible duplicado ({r.tamano_grupo ?? "?"} en el grupo)</span> : null}
          </div>
          {r.estado === "con_acta" ? <p className="rv-sub">Este reporte tiene un acta vinculada. «Con acta» es solo de lectura: lo asigna el acta, no se cambia a mano.</p> : null}

          <Acciones d={d} def={def} accion={accion} setAccion={setAccion}
            onHecho={(parche, texto) => { onCambio(id, parche); setAviso(texto); setAccion(null); void cargar(); }} refrescar={cargar} />

          <h3 className="rv-h3">Datos del reporte</h3>
          <dl className="rv-dl">
            <dt>Inicio</dt><dd>{textoInicio(r) || "—"}</dd>
            <dt>Registrado (fin)</dt><dd>{fmtInstante(r.registrado_en)} (hora de Bogotá)</dd>
            <dt>Duración</dt><dd>{textoDuracion(r) || "—"}</dd>
            <dt>Grupo y tipo</dt><dd>{r.grupo.nombre} · {r.tipo.nombre}{r.subtipo ? ` · ${r.subtipo.nombre}` : ""}</dd>
            {r.resultado ? <><dt>Resultado</dt><dd>{val("resultado")}{r.causal ? ` · ${r.causal.nombre}` : ""}</dd></> : null}
            <dt>Estado</dt><dd>{val("estado")}{r.estado_desde ? ` (desde ${fmtInstante(r.estado_desde)})` : ""}</dd>
            <dt>Descripción</dt><dd className="rv-descripcion">{r.descripcion ?? "—"}</dd>
            <dt>Contrato</dt><dd>{r.contrato ?? "—"}{r.contrato && r.contrato_verificado !== null ? (r.contrato_verificado ? " (verificado)" : " (no verificado)") : ""}</dd>
            <dt>Autor</dt><dd>{r.autor ?? "—"}</dd>
            <dt>Origen</dt><dd>{val("origen")}</dd>
            <dt>{r.registro?.xy_manual ? "Ubicación (XY digitado)" : "Ubicación"}</dt><dd>{fmtNumero(r.lat, 6)}, {fmtNumero(r.lon, 6)}{r.precision_m !== null && r.precision_m !== undefined ? ` · precisión ±${fmtNumero(r.precision_m, 0)} m` : ""}{r.fuera_de_zona ? " · fuera de la zona" : ""}</dd>
            {r.registro ? <><dt>Registrado desde</dt><dd data-rf-detalle-desde>{r.registro.lat_registro === null || r.registro.lon_registro === null ? "Sin ubicación del dispositivo"
              : `${fmtNumero(r.registro.lat_registro, 6)}, ${fmtNumero(r.registro.lon_registro, 6)}${r.registro.precision_registro_m !== null ? ` · precisión ±${fmtNumero(r.registro.precision_registro_m, 0)} m` : ""}${r.registro.distancia_m !== null ? ` · a ${fmtNumero(r.registro.distancia_m, 0)} m del punto` : ""}`}</dd></> : null}
            {dc ? <><dt>Dirección del contrato</dt><dd data-dc-detalle>{dc.comercial ? [dc.comercial, dc.barrio_comercial].filter(Boolean).join(" · ") : "Sin dato en la base comercial"}
              {dc.catastro && dc.catastro.toUpperCase() !== (dc.comercial ?? "").toUpperCase() ? <><br /><small>En el catastro: {[dc.catastro, dc.barrio_catastro].filter(Boolean).join(" · ")}</small></> : null}</dd></> : null}
            {r.registro?.direccion ? <><dt>{r.contrato ? "Dirección encontrada en terreno" : "Dirección"}</dt><dd>{r.registro.direccion}</dd></> : null}
            {r.registro?.barrio ? <><dt>Barrio</dt><dd>{r.registro.barrio}</dd></> : null}
            {r.registro?.referencia ? <><dt>Referencia</dt><dd>{r.registro.referencia}</dd></> : null}
            {r.orden_trabajo_id ? <><dt>Orden de trabajo</dt><dd>{r.orden_trabajo_id}</dd></> : null}
            {r.reporte_original_id ? <><dt>Duplicado de</dt><dd><button type="button" className="rv-enlace" onClick={() => onAbrir(r.reporte_original_id as string)}>Abrir el reporte original</button></dd></> : null}
          </dl>

          {(() => { const pares = paresDeDatos(r.datos, d.campos); return pares.length ? (
            <><h3 className="rv-h3">Campos del formato</h3>
              <dl className="rv-dl">{pares.map((p, i) => <><dt key={`t${i}`}>{p.etiqueta}</dt><dd key={`v${i}`}>{p.valor}{p.generica ? <span className="rv-tenue"> (campo sin definición)</span> : null}</dd></>)}</dl></>
          ) : null; })()}

          {r.tiene_datos_sensibles ? (
            <div className="rv-sensibles">
              <h3 className="rv-h3">Datos sensibles</h3>
              {!sens ? <>
                <p className="rv-sub">Este reporte tiene datos personales. Cada lectura queda registrada con su nombre, fecha y hora.</p>
                <button type="button" className="rv-boton-sec" onClick={() => void verSensibles()}>Ver datos sensibles</button>
              </> : <>
                <dl className="rv-dl">{d.campos.filter((c) => c.sensible).map((c) => <><dt key={`a${c.codigo}`}>{c.nombre}</dt><dd key={`b${c.codigo}`}>{textoDeDato(c, sens.datos[c.codigo]) || "—"}</dd></>)}
                  {Object.keys(sens.datos).filter((k) => !d.campos.some((c) => c.codigo === k)).map((k) => <><dt key={`c${k}`}>{k}</dt><dd key={`d${k}`}>{String(sens.datos[k])}</dd></>)}</dl>
                <button type="button" className="rv-boton-sec rv-corto" onClick={() => setSens(null)}>Ocultar datos sensibles</button>
              </>}
              {sensMsg ? <p className="rv-error" role="alert">{sensMsg}</p> : null}
            </div>
          ) : null}

          <h3 className="rv-h3">Fotos ({d.fotos.length})</h3>
          {d.fotos.length === 0 ? <p className="rv-sub">Este reporte no tiene fotos.</p> : (
            <div className="rv-fotos">{d.fotos.map((f) => <FotoVisor key={f.orden} id={id} orden={f.orden} rotulo={`${f.etiqueta_nombre ?? `Foto ${f.orden}`}${f.origen === "galeria" ? " · adjuntada desde la galería" : f.origen === "archivo" ? " · adjuntada desde un archivo" : ""}`} />)}</div>
          )}

          <h3 className="rv-h3">Historia</h3>
          <ol className="rv-historia">
            <li><strong>Registrado</strong> por {r.autor ?? "—"} · {fmtInstante(r.registrado_en)}</li>
            {d.eventos.map((e) => <Evento key={e.id} e={e} ctx={ctx} />)}
          </ol>

          <h3 className="rv-h3">Reportes cercanos del mismo tipo ({d.cercanos.length})</h3>
          {d.cercanos.length === 0 ? <p className="rv-sub">No hay reportes del mismo tipo a menos de {fmtNumero(d.distancia_duplicados_m, 0)} m. Los posibles duplicados se sugieren, no se fusionan.</p> : (
            <ul className="rv-lista">{d.cercanos.map((c) => <Cerca key={c.id} c={c} ctx={ctx} onAbrir={onAbrir} />)}</ul>
          )}
        </>
      ) : null}
    </aside>
  );
}

function Cerca({ c, ctx, onAbrir }: { c: Cercano; ctx: Contexto; onAbrir: (id: string) => void }) {
  return <li>A {fmtNumero(c.distancia_m, 1)} m · {fmtInstante(c.registrado_en)} · {ctx.estados.get(c.estado) ?? c.estado} <button type="button" className="rv-enlace" onClick={() => onAbrir(c.id)}>Abrir</button></li>;
}
function Evento({ e, ctx }: { e: EventoRep; ctx: Contexto }) {
  const que = e.tipo_evento === "cambio_estado" ? `Cambio de estado a «${ctx.estados.get(e.estado_nuevo ?? "") ?? e.estado_nuevo}»` : (ROTULO_EVENTO[e.tipo_evento] ?? e.tipo_evento);
  return <li><strong>{que}</strong> por {e.autor} · {fmtInstante(e.creado_en)}{e.motivo ? <span className="rv-motivo">Motivo: {e.motivo}</span> : null}</li>;
}

function FotoVisor({ id, orden, rotulo }: { id: string; orden: number; rotulo: string }) {
  const [url, setUrl] = useState<string | null>(null); const [est, setEst] = useState<"idle" | "cargando" | "lista" | "vencida" | "error">("idle"); const [msg, setMsg] = useState("");
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  async function pedir() {
    setEst("cargando"); setMsg("");
    try {
      const r = await apiRev.foto(id, orden); setUrl(r.url); setEst("lista");
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => { setUrl(null); setEst("vencida"); }, Math.max(1000, new Date(r.expira_en).getTime() - Date.now() - 3000));   // se quita antes de que la URL venza
    } catch (e) { setEst("error"); setMsg(textoError(e).texto); }
  }
  return (
    <figure className="rv-foto">
      <figcaption>{rotulo}</figcaption>
      {est === "lista" && url ? <img src={url} alt={`${rotulo} del reporte`} referrerPolicy="no-referrer" /> : null}
      {est === "idle" || est === "error" ? <button type="button" className="rv-boton-sec" onClick={() => void pedir()}>Ver foto</button> : null}
      {est === "cargando" ? <span role="status">Cargando…</span> : null}
      {est === "vencida" ? <><span className="rv-tenue">La foto se quitó por seguridad (vive 60 segundos).</span> <button type="button" className="rv-boton-sec" onClick={() => void pedir()}>Volver a cargar</button></> : null}
      {est === "lista" ? <span className="rv-tenue">La foto se oculta sola en menos de 1 minuto. Cada vista queda registrada.</span> : null}
      {msg ? <span className="rv-error" role="alert">{msg}</span> : null}
    </figure>
  );
}

// ---------- Acciones del supervisor ----------
type Accion = "estado" | "ocultar" | "reincluir" | "duplicado";
function Acciones({ d, def, accion, setAccion, onHecho, refrescar }: {
  d: DetalleResp; def: FormularioRev; accion: Accion | null; setAccion: (a: Accion | null) => void; onHecho: (parche: Partial<FilaReporte>, texto: string) => void; refrescar: () => Promise<void>;
}) {
  const r = d.reporte;
  const estados = (def.estados ?? []).filter((e) => e.activo && e.cambio_manual && e.codigo !== r.estado);
  const [estadoSel, setEstadoSel] = useState(""); const [originalSel, setOriginalSel] = useState(""); const [originalTxt, setOriginalTxt] = useState("");
  useEffect(() => { setEstadoSel(estados[0]?.codigo ?? ""); setOriginalSel(d.cercanos[0]?.id ?? ""); setOriginalTxt(""); }, [d.reporte.id, d.reporte.estado, d.cercanos.length]);   // eslint-disable-line react-hooks/exhaustive-deps
  const puedeDuplicar = r.estado !== "duplicado";
  const ahora = () => new Date().toISOString();

  async function confirmar(motivo: string): Promise<string | null> {
    try {
      if (accion === "estado") { const x = await apiRev.estado(r.id, estadoSel, motivo); onHecho({ estado: x.estado, estado_desde: ahora() }, `El estado cambió a «${def.estados?.find((e) => e.codigo === x.estado)?.nombre ?? x.estado}».`); }
      else if (accion === "ocultar") { await apiRev.ocultar(r.id, motivo); onHecho({ oculto: true }, "El reporte quedó oculto (se conserva y se puede reincluir)."); }
      else if (accion === "reincluir") { await apiRev.reincluir(r.id, motivo); onHecho({ oculto: false }, "El reporte se reincluyó."); }
      else if (accion === "duplicado") {
        const orig = (originalTxt.trim() || originalSel).toLowerCase();
        const x = await apiRev.duplicado(r.id, orig, motivo); onHecho({ estado: x.estado, estado_desde: ahora(), reporte_original_id: x.reporte_original_id }, "Quedó vinculado como duplicado del reporte original.");
      }
      return null;
    } catch (e) {
      // Conflicto (otro supervisor actuó antes): el servidor responde 409 con el motivo; se vuelve a leer lo vigente para que la persona vea el estado actual.
      if (e instanceof ErrorCampo && e.status === 409) { void refrescar(); return `${e.message} Se actualizó la información con lo vigente.`; }
      return textoError(e).texto;
    }
  }
  return (
    <div className="rv-acciones">
      <button type="button" className="rv-boton-sec" disabled={estados.length === 0} onClick={() => setAccion("estado")}>Cambiar estado</button>
      {r.oculto ? <button type="button" className="rv-boton-sec" onClick={() => setAccion("reincluir")}>Reincluir</button> : <button type="button" className="rv-boton-sec" onClick={() => setAccion("ocultar")}>Ocultar</button>}
      <button type="button" className="rv-boton-sec" disabled={!puedeDuplicar} onClick={() => setAccion("duplicado")}>Vincular como duplicado</button>
      {accion ? (
        <ModalAccion
          titulo={accion === "estado" ? "Cambiar estado" : accion === "ocultar" ? "Ocultar el reporte" : accion === "reincluir" ? "Reincluir el reporte" : "Vincular como duplicado"}
          efecto={accion === "ocultar" ? "El reporte sigue existiendo y se ve atenuado cuando se piden los ocultos; deja de contar en la lista normal y en los indicadores. Se puede reincluir con otro motivo."
            : accion === "reincluir" ? "El reporte vuelve a la lista normal y a los indicadores."
            : accion === "duplicado" ? "El reporte queda en estado «Duplicado» y apunta al original. No se fusiona nada: la historia de ambos se conserva."
            : "Se agrega un evento a la historia con su nombre y el motivo. Nada se edita ni se borra."}
          deshabilitado={accion === "estado" ? !estadoSel : accion === "duplicado" ? !(originalTxt.trim() || originalSel) : false}
          onConfirmar={confirmar} onCancelar={() => setAccion(null)}>
          {accion === "estado" ? (
            <label className="rv-campo">Nuevo estado
              <select value={estadoSel} onChange={(e) => setEstadoSel(e.target.value)}>{estados.map((e) => <option key={e.codigo} value={e.codigo}>{e.nombre}{e.exige_motivo ? " (exige motivo)" : ""}</option>)}</select>
            </label>
          ) : null}
          {accion === "duplicado" ? (<>
            <label className="rv-campo">Reporte original (entre los cercanos)
              <select value={originalSel} onChange={(e) => setOriginalSel(e.target.value)} disabled={d.cercanos.length === 0}>
                {d.cercanos.length === 0 ? <option value="">No hay reportes cercanos</option> : null}
                {d.cercanos.map((c) => <option key={c.id} value={c.id}>A {fmtNumero(c.distancia_m, 1)} m · {fmtInstante(c.registrado_en)}</option>)}
              </select>
            </label>
            <label className="rv-campo">O pegue el identificador del original
              <input type="text" value={originalTxt} onChange={(e) => setOriginalTxt(e.target.value)} placeholder="00000000-0000-0000-0000-000000000000" autoComplete="off" />
            </label>
          </>) : null}
        </ModalAccion>
      ) : null}
    </div>
  );
}

function ModalAccion({ titulo, efecto, deshabilitado, children, onConfirmar, onCancelar }: {
  titulo: string; efecto: string; deshabilitado: boolean; children?: React.ReactNode; onConfirmar: (motivo: string) => Promise<string | null>; onCancelar: () => void;
}) {
  const [motivo, setMotivo] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const largo = motivo.trim().length; const valido = largo >= 10 && largo <= 1000;
  async function enviar() {
    if (enviando || !valido || deshabilitado) return;       // bloquea la doble pulsación
    setEnviando(true); setError(null);
    const e = await onConfirmar(motivo.trim());
    if (e) { setError(e); setEnviando(false); }
  }
  return (
    <div className="rv-modal-fondo" onMouseDown={(e) => { if (e.target === e.currentTarget && !enviando) onCancelar(); }}>
      <div className="rv-modal" role="dialog" aria-modal="true" aria-label={titulo}>
        <h3>{titulo}</h3>
        <p className="rv-sub">{efecto}</p>
        {children}
        <label className="rv-campo">Motivo (de 10 a 1.000 caracteres)
          <textarea rows={3} value={motivo} maxLength={1000} onChange={(e) => setMotivo(e.target.value)} disabled={enviando} aria-invalid={largo > 0 && !valido} autoFocus />
          <span className="rv-tenue">{largo.toLocaleString("es-CO")} de 1.000{largo > 0 && largo < 10 ? " · faltan " + (10 - largo) + " para el mínimo" : ""}</span>
        </label>
        {error ? <p className="rv-error" role="alert">{error}</p> : null}
        <div className="rv-botones">
          <button type="button" className="rv-boton" disabled={enviando || !valido || deshabilitado} onClick={() => void enviar()}>{enviando ? "Guardando…" : "Confirmar"}</button>
          <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}
