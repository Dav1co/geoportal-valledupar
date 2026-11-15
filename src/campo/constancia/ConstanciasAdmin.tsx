import { useCallback, useEffect, useState } from "react";
import { textoError } from "../dashboard/apiRevision";
import { apiConstancia, DOCUMENTOS, type EstadoConstancia } from "./apiConstancia";
import { CORREO_RE } from "./logica";
import "./constancia.css";

/** Administración de la «Constancia por correo» (solo administrador): habilitar por documento, copias internas del supervisor, texto de autorización y estado de la cola.
 *  Todo nace APAGADO y las copias vacías. Mientras el texto sea un borrador no se puede habilitar ningún documento (lo exige la base). Cada cambio queda auditado. No se ven correos de titulares. */
/** `lectura` (pasada 14/11): estado de SOLO LECTURA para el supervisor (viene de «catalogo_lectura»): sin campos editables ni botones; las rutas de administración siguen siendo del administrador. */
export function ConstanciasAdmin({ lectura }: { lectura?: EstadoConstancia } = {}) {
  const soloLectura = !!lectura;
  const [est, setEst] = useState<EstadoConstancia | null>(lectura ?? null);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const cargar = useCallback(async () => { if (soloLectura) return; try { setEst(await apiConstancia.estado()); setError(null); } catch (e) { setError(textoError(e).texto); } }, [soloLectura]);
  useEffect(() => { void cargar(); }, [cargar]);
  const aviso = (m: string) => { setOk(m); setError(null); void cargar(); };

  return (
    <section className="rv-seccion constancia-admin" aria-labelledby="rv-cons-tit">
      <div><h2 id="rv-cons-tit">Constancias por correo</h2>
        <p className="rv-sub">El geoportal solo recoge el correo y la autorización; el envío lo hace el Dell. La <strong>copia interna</strong> va al supervisor en todo registro de un documento habilitado; al titular solo si autoriza. Todo nace apagado.</p></div>
      {error && <div className="rv-aviso rv-aviso-error" role="alert">{error}</div>}
      {ok && <div className="rv-aviso" role="status">{ok}</div>}
      {soloLectura && est ? <LecturaConstancias est={est} /> : !est ? <p className="rv-sub" role="status">Cargando…</p> : (
        <>
          <Texto est={est} onListo={aviso} onError={setError} />
          {DOCUMENTOS.map((d) => <Documento key={d.codigo} d={d} fila={est.documentos.find((x) => x.documento === d.codigo)} onListo={aviso} onError={setError} />)}
          <Cola est={est} onListo={aviso} onError={setError} />
        </>
      )}
    </section>
  );
}

function Texto({ est, onListo, onError }: { est: EstadoConstancia; onListo: (m: string) => void; onError: (m: string) => void }) {
  const [texto, setTexto] = useState(est.texto?.texto ?? "");
  const [borrador, setBorrador] = useState(est.texto?.borrador ?? true);
  const [env, setEnv] = useState(false);
  const cambiado = texto.trim() !== (est.texto?.texto ?? "") || borrador !== (est.texto?.borrador ?? true);
  async function guardar() {
    if (env || texto.trim().length < 20) return;
    if (!borrador && !window.confirm("Un texto nuevo apaga todos los documentos hasta que se habiliten de nuevo. ¿Guardar el texto aprobado?")) return;
    setEnv(true);
    try { await apiConstancia.nuevoTexto(texto.trim(), borrador); onListo("Texto guardado como versión nueva (el anterior se conserva)."); } catch (e) { onError(textoError(e).texto); } finally { setEnv(false); }
  }
  return (
    <div className="constancia-doc">
      <h3>Texto de autorización (Ley 1581 de 2012) · versión {est.texto?.version ?? "—"} {est.texto?.borrador ? "· BORRADOR" : "· aprobado"}</h3>
      <label className="campo-etiqueta" htmlFor="cons-texto">Texto que ve la persona</label>
      <textarea id="cons-texto" value={texto} maxLength={2000} onChange={(e) => setTexto(e.target.value)} />
      <label className="constancia-casilla"><input type="checkbox" checked={borrador} onChange={(e) => setBorrador(e.target.checked)} /><span>Sigue como borrador (pendiente de jurídica)</span></label>
      <p className="rv-sub">Cambiar el texto crea una versión nueva; la anterior queda guardada. Con el texto en borrador no se puede habilitar ningún documento.</p>
      <button type="button" className="rv-boton" disabled={!cambiado || env || texto.trim().length < 20} onClick={() => void guardar()}>{env ? "Guardando…" : "Guardar texto"}</button>
    </div>
  );
}

function Documento({ d, fila, onListo, onError }: { d: { codigo: string; nombre: string }; fila?: { habilitado: boolean; copias_internas: string[] }; onListo: (m: string) => void; onError: (m: string) => void }) {
  const [hab, setHab] = useState(fila?.habilitado ?? false);
  const [copias, setCopias] = useState((fila?.copias_internas ?? []).join("\n"));
  const [env, setEnv] = useState(false);
  const lista = copias.split(/[\n,;]+/).map((x) => x.trim()).filter(Boolean);
  const malas = lista.filter((x) => !CORREO_RE.test(x));
  const cambiado = hab !== (fila?.habilitado ?? false) || lista.join("|") !== (fila?.copias_internas ?? []).join("|");
  async function guardar() {
    if (env || malas.length > 0 || lista.length > 10) return;
    setEnv(true);
    try { await apiConstancia.guardarConfig(d.codigo, hab, lista); onListo(`«${d.nombre}» guardado.`); } catch (e) { onError(textoError(e).texto); } finally { setEnv(false); }
  }
  return (
    <div className="constancia-doc">
      <h3>{d.nombre}</h3>
      <label className="constancia-casilla"><input type="checkbox" checked={hab} onChange={(e) => setHab(e.target.checked)} /><span>Envía constancia ({hab ? "habilitado" : "apagado"})</span></label>
      <label className="campo-etiqueta" htmlFor={`cons-cop-${d.codigo}`}>Copia interna (un correo por línea, hasta 10)</label>
      <textarea id={`cons-cop-${d.codigo}`} value={copias} onChange={(e) => setCopias(e.target.value)} placeholder="supervisor@emdupar.gov.co" />
      {malas.length > 0 && <p className="campo-error" role="alert">No es un correo válido: {malas.join(", ")}</p>}
      {lista.length > 10 && <p className="campo-error" role="alert">Máximo 10 correos.</p>}
      {hab && lista.length === 0 && <p className="rv-sub">Sin copia interna, solo se enviará a quien autorice.</p>}
      <button type="button" className="rv-boton" disabled={!cambiado || env || malas.length > 0 || lista.length > 10} onClick={() => void guardar()}>{env ? "Guardando…" : "Guardar"}</button>
    </div>
  );
}

function Cola({ est, onListo, onError }: { est: EstadoConstancia; onListo: (m: string) => void; onError: (m: string) => void }) {
  const [env, setEnv] = useState(false);
  async function depurar(soloContar: boolean) {
    if (env) return;
    if (!soloContar && !window.confirm("Se enmascararán los correos y celulares de los envíos terminados hace más de 6 meses. Los eventos no se borran. ¿Continuar?")) return;
    setEnv(true);
    try { const r = await apiConstancia.depurar(soloContar); onListo(soloContar ? `Por depurar hoy: ${r.envios} envíos y ${r.contactos_sin_envio} contactos sin envío.` : `Depurados: ${r.envios} envíos y ${r.contactos_sin_envio} contactos sin envío.`); } catch (e) { onError(textoError(e).texto); } finally { setEnv(false); }
  }
  const estados = Object.entries(est.cola);
  return (
    <div className="constancia-doc">
      <h3>Cola de envíos</h3>
      <p>{estados.length === 0 ? "Sin envíos todavía." : estados.map(([k, n]) => `${k}: ${n}`).join(" · ")}</p>
      {est.fallos_ultimos_30_dias > 0 && <p className="campo-error" role="alert">{est.fallos_ultimos_30_dias} fallos al encolar en los últimos 30 días: avise a sistemas.</p>}
      <p className="rv-sub">Retención: los correos y celulares se enmascaran 6 meses después del último envío exitoso o de la anulación.</p>
      <button type="button" className="rv-boton-sec" disabled={env} onClick={() => void depurar(true)}>Ver cuántos se depurarían</button>{" "}
      <button type="button" className="rv-boton-sec" disabled={env} onClick={() => void depurar(false)}>Depurar ahora</button>
    </div>
  );
}

/** Pasada 14/11: lo mismo que ve el administrador, sin poder cambiarlo. */
function LecturaConstancias({ est }: { est: EstadoConstancia }) {
  const estados = Object.entries(est.cola);
  return (
    <>
      <div className="rv-aviso rv-aviso-info" role="note">Solo el administrador puede cambiar las constancias. Aquí ve su estado.</div>
      <div className="constancia-doc">
        <h3>Texto de autorización · versión {est.texto?.version ?? "—"} {est.texto?.borrador ? "· BORRADOR" : "· aprobado"}</h3>
        <p className="constancia-texto-lectura">{est.texto?.texto ?? "Sin texto."}</p>
      </div>
      {DOCUMENTOS.map((d) => { const f = est.documentos.find((x) => x.documento === d.codigo); return (
        <div key={d.codigo} className="constancia-doc">
          <h3>{d.nombre}</h3>
          <p>{f?.habilitado ? "Envía constancia (habilitado)" : "Apagado"}</p>
          <p className="rv-sub">Copia interna: {f && f.copias_internas.length ? f.copias_internas.join(", ") : "ninguna"}</p>
        </div>); })}
      <div className="constancia-doc">
        <h3>Cola de envíos</h3>
        <p>{estados.length === 0 ? "Sin envíos todavía." : estados.map(([k, n]) => `${k}: ${n}`).join(" · ")}</p>
        {est.fallos_ultimos_30_dias > 0 && <p className="campo-error" role="alert">{est.fallos_ultimos_30_dias} fallos al encolar en los últimos 30 días.</p>}
      </div>
    </>
  );
}
