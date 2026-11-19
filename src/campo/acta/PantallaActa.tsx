import { useCallback, useEffect, useRef, useState } from "react";
import "./acta.css";
import { avisoDeError, ErrorCampo } from "../apiCampo";
import { fechaHora, fechaHoraSello, megas, metros } from "../formato";
import { useUbicacion } from "../ubicacion";
import { apiActa } from "./apiActa";
import { almacenActa, useAlmacenActa } from "./almacenActa";
import { CamaraActa } from "./CamaraActa";
import { FormularioActa } from "./FormularioActa";
import { IdentificarPredio } from "./IdentificarPredio";
import { PanelCancelarActa } from "./PanelCancelarActa";
import type { Destino, MotivoCancelacion } from "../../components/ConfirmarCancelar";
import * as L from "./logica";
import type { ConfirmacionActa, FilaMisActas, FormularioActa as Catalogo, MisActas, Precarga } from "./tipos";

// Pantalla del acta de inspección técnica (entrada «Acta de inspección» del área de campo). El acta digital es el REGISTRO que acompaña al acta física firmada: no se firma aquí,
// no hay PDF ni imágenes de firma. Flujo: «Mis actas» (solo las propias) → «Nueva acta» (contrato verificado o sin contrato → abrir: el servidor entrega el consecutivo) → formulario por
// secciones → confirmar y registrar. Desde «Mis actas» se retoma una apertura vigente sin registrar y se adjunta la foto del papel de un registro con «papel pendiente» tras recargar.

type Vista = { v: "lista" } | { v: "identificar" } | { v: "formulario"; id: string } | { v: "papel"; fila: FilaMisActas } | { v: "confirmado"; conf: ConfirmacionActa; papelPendiente: boolean };

/** `contratoInicial`: contrato que llega desde un formato de actividad (revisión con irregularidad). Si viene, se abre directo «Nueva acta» con el contrato escrito; la persona sigue pulsando «Verificar». */
/** `destinos`/`onIrA`: «me equivoqué de formulario» al cancelar: a qué otros formularios se puede pasar llevando solo el contrato. */
export function PantallaActa({ correo, onVolver, contratoInicial = "", destinos, onIrA }: { correo: string; onVolver: () => void; contratoInicial?: string; destinos?: Destino[]; onIrA?: (destino: string, contrato: string) => void }) {
  almacenActa.alAcceder(correo);
  const { entradas } = useAlmacenActa();
  const [vista, setVista] = useState<Vista>(contratoInicial ? { v: "identificar" } : { v: "lista" });
  const [cat, setCat] = useState<Catalogo | null>(null);
  const [lista, setLista] = useState<MisActas | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [motivos, setMotivos] = useState<MotivoCancelacion[] | null>(null);   // motivos para cancelar (si no cargan, el panel lo dice y no deja cancelar)
  const [cancelandoId, setCancelandoId] = useState<string | null>(null);        // tarjeta de «Mis actas» con el panel de cancelar abierto
  const [cargando, setCargando] = useState(true);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    let vivo = true;
    setCargando(true); setError(null);
    Promise.all([apiActa.formulario(), apiActa.misActas(), apiActa.motivosCancelacion().then((r) => r.motivos, () => null)])
      .then(([c, m, mo]) => { if (vivo) { setCat(c); setLista(m); setMotivos(mo); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cargar.", 0)); })
      .finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
  }, [intento]);
  const recargar = useCallback(() => setIntento((i) => i + 1), []);
  const aLista = useCallback(() => { setVista({ v: "lista" }); recargar(); }, [recargar]);

  if (error) {
    const sinAcceso = error.tipo === "permiso" || error.tipo === "denegado";
    return (
      <div className="tec-pagina campo-pagina">
        <section className="tec-tarjeta" role="alert">
          <h1>{sinAcceso ? "Sin acceso a «Reportar posible pérdida»" : "No se pudo abrir «Reportar posible pérdida»"}</h1>
          <p>{sinAcceso ? "Su cuenta no tiene acceso a «Reportar posible pérdida». Solicítelo a un administrador." : avisoDeError(error).texto}</p>
          {!sinAcceso && error.tipo !== "sesion" && <button type="button" className="tec-boton" onClick={recargar}>Reintentar</button>}
          <button type="button" className="tec-boton-sec" onClick={onVolver}>Volver</button>
        </section>
      </div>
    );
  }
  if (cargando && (!cat || !lista)) return <div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>;
  if (!cat || !lista) return null;

  if (vista.v === "identificar") return <Identificar cat={cat} correo={correo} contratoInicial={contratoInicial} onCancelar={aLista} onAbierta={(id) => setVista({ v: "formulario", id })} onRevisar={aLista} />;
  if (vista.v === "formulario") {
    return <FormularioActa cat={cat} actaId={vista.id} correo={correo} onVolver={aLista} motivos={motivos} destinos={destinos} onIrA={onIrA}
      onRegistrado={(conf) => { const pend = almacenActa.obtener(vista.id)?.borrador.papelPendiente ?? false; almacenActa.quitar(vista.id); setVista({ v: "confirmado", conf, papelPendiente: pend }); }} />;
  }
  if (vista.v === "papel") return <AdjuntarPapel cat={cat} fila={vista.fila} onListo={aLista} onVolver={aLista} />;
  if (vista.v === "confirmado") return <Confirmado conf={vista.conf} papelPendiente={vista.papelPendiente} onVolver={aLista} />;

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <h1>Reportar posible pérdida</h1>
          <button type="button" className="tec-boton-sec" onClick={onVolver}>Volver</button>
        </div>
        <h2 className="campo-grupo-titulo">Mis actas</h2>
        <p className="campo-nota" role="note">{L.TEXTO_PAPEL}</p>
        <p className="campo-sub">{cat.aviso_registro}</p>
        <button type="button" className="tec-boton campo-enviar" onClick={() => setVista({ v: "identificar" })}>Nueva acta</button>
        <p className="campo-sub">{L.AVISO_CONSECUTIVO_ABIERTO}</p>
        <div className="acta-lista-cab">
          <h2 className="acta-titulo">Actas que abrí</h2>
          <button type="button" className="tec-boton-sec" onClick={recargar} disabled={cargando}>{cargando ? "Actualizando…" : "Actualizar"}</button>
        </div>
        {lista.filas.length === 0 && <p className="campo-sub">Todavía no ha abierto ninguna acta.</p>}
        <ul className="acta-lista">
          {lista.filas.map((f) => {
            const accion = L.accionDeFila(f);
            const conBorrador = !!entradas[f.acta_id];
            return (
              <li key={f.acta_id} className="acta-tarjeta">
                <p className="acta-consecutivo-chico"><strong>{f.consecutivo}</strong></p>
                <p className="campo-sub">{L.textoSituacion(f)} · {L.textoContrato(f)}</p>
                <p className="campo-sub">Abierta el {fechaHora(f.abierto_en)}{f.situacion === "abierta_en_curso" ? ` · vence el ${fechaHora(f.vence_en)}` : ""}</p>
                {f.situacion === "abierta_vencida" && <p className="campo-nota" role="note">Caducó sin registrarse: ya no se puede registrar. Si escribió este consecutivo en un papel, avise a la supervisión; para esta visita abra una nueva acta.</p>}
                {accion === "continuar" && (
                  <button type="button" className="tec-boton" onClick={() => {
                    almacenActa.retomar(f, { ...L.borradorVacio("con_contrato"), fechaFisica: L.hoyBogota() });
                    setVista({ v: "formulario", id: f.acta_id });
                  }}>{conBorrador ? "Continuar (borrador en pantalla)" : "Retomar y completar"}</button>
                )}
                {f.puede_cancelar && cancelandoId !== f.acta_id && <button type="button" className="btn-cancelar" onClick={() => setCancelandoId(f.acta_id)}>Cancelar</button>}
                {f.puede_cancelar && cancelandoId === f.acta_id && (
                  <PanelCancelarActa correo={correo} actaId={f.acta_id} consecutivo={f.consecutivo} contrato={f.contrato ?? (entradas[f.acta_id]?.borrador.modo === "con_contrato" ? entradas[f.acta_id]?.borrador.contrato : "") ?? ""} motivos={motivos} destinos={destinos} onIrA={onIrA}
                    onHecho={() => { setCancelandoId(null); recargar(); }} onSeguir={() => setCancelandoId(null)} />
                )}
                {accion === "adjuntar_papel" && <button type="button" className="tec-boton" onClick={() => setVista({ v: "papel", fila: f })}>Adjuntar la foto del acta física</button>}
                {f.situacion === "registrada" && f.papel_pendiente && !f.puede_adjuntar_papel && !f.tiene_foto_papel && <p className="campo-sub">La supervisión corrigió este registro: la foto del papel la gestiona ella.</p>}
              </li>
            );
          })}
        </ul>
        {lista.hay_mas && <p className="campo-sub">Se muestran las {lista.max_filas} más recientes.</p>}
      </section>
    </div>
  );
}

// ======================= Paso 1: identificar el predio y abrir =======================
function Identificar({ cat, correo, contratoInicial = "", onCancelar, onAbierta, onRevisar }: { cat: Catalogo; correo: string; contratoInicial?: string; onCancelar: () => void; onAbierta: (id: string) => void; onRevisar: () => void }) {
  const [modo, setModo] = useState<"con_contrato" | "sin_contrato">("con_contrato");
  const [contrato, setContrato] = useState(contratoInicial);
  const [precarga, setPrecarga] = useState<Precarga | null>(null);
  const [verificado, setVerificado] = useState<string | null>(null);
  const [abriendo, setAbriendo] = useState(false);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const ubic = useUbicacion();
  const fix = ubic.fix;
  const bloqueo = useRef(false);

  const contratoListo = modo === "sin_contrato" || (precarga?.existe === true && verificado === contrato.trim() && contrato.trim() !== "");
  const aviso = fix ? L.avisoPrecision(fix.precision_m) : null;

  async function abrir() {
    if (bloqueo.current || !contratoListo || !fix) return;      // sin doble pulsación; sin contrato verificado o sin ubicación no se abre
    bloqueo.current = true; setAbriendo(true); setError(null);
    try {
      const a = await apiActa.abrir(fix.lat, fix.lon, Number.isFinite(fix.precision_m) ? Math.round(fix.precision_m * 10) / 10 : null);
      const base = L.borradorVacio(modo);
      const b = modo === "con_contrato" && precarga ? { ...L.conPrecarga(base, precarga), contrato: contrato.trim() } : base;
      almacenActa.crear(a, { ...b, fechaFisica: L.hoyBogota() }, modo === "con_contrato" ? precarga : null);
      onAbierta(a.acta_id);
    } catch (e) {
      setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo abrir el registro.", 0));
    } finally {
      bloqueo.current = false; setAbriendo(false);
    }
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <h1>Nueva acta</h1>
          <button type="button" className="tec-boton-sec" onClick={onCancelar}>Cancelar</button>
        </div>
        <p className="campo-nota" role="note">{L.TEXTO_PAPEL}</p>
        <IdentificarPredio modo={modo} contrato={contrato} bloqueado={abriendo}
          onModo={setModo} onContrato={(c) => { setContrato(c); if (c.trim() !== verificado) setPrecarga(null); }}
          precarga={precarga} onPrecarga={(p, c) => { setPrecarga(p); setVerificado(c); }} ubicacion={fix ? { lat: fix.lat, lon: fix.lon } : null} />
        <div className="acta-ubicacion" role="status" aria-live="polite">
          {ubic.estado === "buscando" && <p className="campo-sub">Buscando su ubicación… (el registro se abre en el lugar de la visita).</p>}
          {fix && <p className="campo-sub">Ubicación lista · {metros(fix.precision_m)} · {fechaHoraSello(fix.tomado)}</p>}
          {aviso && <p className="campo-nota" role="note">{aviso}</p>}
          {(ubic.estado === "denegada" || ubic.estado === "no_disponible" || ubic.estado === "error") && (
            <p className="campo-error" role="alert">{ubic.mensaje ?? "No se pudo obtener la ubicación."} El registro se abre con la coordenada del lugar: permita la ubicación y reintente.
              <button type="button" className="campo-enlace" onClick={ubic.actualizar}>Reintentar ubicación</button></p>
          )}
        </div>
        <p className="campo-sub">{L.AVISO_CONSECUTIVO_ABIERTO}</p>
        {error && (
          error.tipo === "red"
            ? <div className="campo-error" role="alert">
                <p>No sabemos si el registro se abrió (se cortó la conexión). Revise «Mis actas» antes de abrir otro, para no gastar un consecutivo de más.</p>
                <button type="button" className="tec-boton" onClick={onRevisar}>Revisar Mis actas</button>
              </div>
            : <p className="campo-error" role="alert">{error.tipo === "validacion" || error.tipo === "limite" ? error.message : avisoDeError(error).texto}</p>
        )}
        {!contratoListo && modo === "con_contrato" && <p className="campo-sub">Verifique el contrato para poder abrir el registro, o elija «sin contrato».</p>}
        <button type="button" className="tec-boton campo-enviar" onClick={() => void abrir()} disabled={!contratoListo || !fix || abriendo || error?.tipo === "red"}>
          {abriendo ? "Abriendo…" : "Abrir registro"}
        </button>
        <p className="campo-sub">Sesión de {correo}. Vigencia del registro: {cat.limites.vigencia_apertura_horas} horas.</p>
      </section>
    </div>
  );
}

// ======================= Foto del acta física después del registro (papel pendiente) =======================
function AdjuntarPapel({ cat, fila, onListo, onVolver }: { cat: Catalogo; fila: FilaMisActas; onListo: () => void; onVolver: () => void }) {
  const [foto, setFoto] = useState<{ blob: Blob; url: string } | null>(null);
  const [camara, setCamara] = useState(false);
  const [fase, setFase] = useState<"editando" | "enviando" | "error" | "hecho">("editando");
  const [error, setError] = useState<ErrorCampo | null>(null);
  const prep = useRef<{ url: string } | null>(null);
  const bloqueo = useRef(false);
  const ubic = useUbicacion();
  const fix = ubic.fix;
  const tipoPapel = cat.tipos_foto.find((t) => t.acta_fisica)?.codigo ?? "acta_fisica";
  const orden = fila.siguiente_orden_foto ?? 1;

  useEffect(() => () => { if (foto) URL.revokeObjectURL(foto.url); }, [foto]);

  async function subir() {
    if (bloqueo.current || !foto) return;
    bloqueo.current = true; setFase("enviando"); setError(null);
    try {
      let u = prep.current;
      if (!u) {
        const p = await apiActa.prepararSubida(fila.acta_id, [{ orden, tipo: tipoPapel }]);
        const d = p.fotos.find((x) => x.orden === orden);
        if (!d) throw new ErrorCampo("servidor", "La preparación de la foto llegó incompleta. Intente de nuevo.", 0);
        u = { url: d.url_subida }; prep.current = u;
      }
      await apiActa.subirFoto(u.url, foto.blob);
      await apiActa.fotoPapel(fila.acta_id, orden);
      setFase("hecho");
    } catch (e) {
      const err = e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo adjuntar la foto.", 0);
      if (err.tipo === "subida_vencida") prep.current = null;
      setError(err); setFase("error");
    } finally {
      bloqueo.current = false;
    }
  }

  if (fase === "hecho") {
    return (
      <div className="tec-pagina campo-pagina">
        <section className="tec-tarjeta campo-confirmacion" role="status">
          <h1>Foto adjuntada</h1>
          <p className="acta-consecutivo">{fila.consecutivo}</p>
          <p className="campo-sub">La foto del acta física quedó adjunta al registro. {L.TEXTO_PAPEL}</p>
          <button type="button" className="tec-boton" onClick={onListo}>Volver a Mis actas</button>
        </section>
      </div>
    );
  }
  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <h1>Foto del acta física</h1>
          <button type="button" className="tec-boton-sec" onClick={onVolver} disabled={fase === "enviando"}>Mis actas</button>
        </div>
        <p className="acta-consecutivo">{fila.consecutivo}</p>
        <p className="campo-nota" role="note">{L.TEXTO_PAPEL}</p>
        <p className="campo-sub">Fotografíe el acta física ya firmada (páginas del papel). Tope {megas(cat.limites.max_bytes_foto_acta_fisica)} por foto; esta será la foto n.º {orden} (máximo {fila.max_fotos_papel}).</p>
        {foto && <img className="campo-foto-img" src={foto.url} alt="Foto del acta física" />}
        <button type="button" className="tec-boton campo-boton-foto" onClick={() => setCamara(true)} disabled={fase === "enviando"}>{foto ? "Tomar otra vez" : "Fotografiar el acta física"}</button>
        {error && <p className="campo-error" role="alert">{error.tipo === "validacion" || error.tipo === "limite" ? error.message : avisoDeError(error).texto}
          {error.status === 409 && <button type="button" className="campo-enlace" onClick={onListo}>Actualizar Mis actas</button>}</p>}
        <button type="button" className="tec-boton campo-enviar" onClick={() => void subir()} disabled={!foto || fase === "enviando"}>{fase === "enviando" ? "Subiendo…" : fase === "error" ? "Reintentar" : "Adjuntar al registro"}</button>
      </section>
      {camara && (
        <CamaraActa rotulo="Acta física firmada" maxBytes={cat.limites.max_bytes_foto_acta_fisica}
          sello={() => [`${fechaHoraSello(new Date())} · hora del celular`, fix ? `${fix.lat.toFixed(5)}, ${fix.lon.toFixed(5)} · ${metros(fix.precision_m)}` : "ubicación no disponible"]}
          onFoto={(f) => { setFoto((p) => { if (p) URL.revokeObjectURL(p.url); return { blob: f.blob, url: URL.createObjectURL(f.blob) }; }); prep.current = null; setCamara(false); }}
          onCerrar={() => setCamara(false)} />
      )}
    </div>
  );
}

// ======================= Confirmación =======================
function Confirmado({ conf, papelPendiente, onVolver }: { conf: ConfirmacionActa; papelPendiente: boolean; onVolver: () => void }) {
  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta campo-confirmacion" role="status">
        <h1>{conf.repetido ? "Este registro ya estaba guardado" : "Registro guardado"}</h1>
        <p className="campo-sub">Reportar posible pérdida</p>
        <p className="acta-consecutivo" aria-label="Consecutivo">{conf.consecutivo}</p>
        <p className="campo-hora">Registrado el {fechaHora(conf.registrado_en)} (hora del servidor).</p>
        <p className="campo-nota" role="note"><strong>Verifique que este consecutivo esté escrito en el acta física.</strong> {L.TEXTO_PAPEL}</p>
        {papelPendiente && <p className="campo-nota" role="alert">Quedó marcado «papel pendiente»: adjunte la foto del acta física firmada desde «Mis actas» en cuanto la tenga.</p>}
        {conf.aviso_zona && <p className="campo-sub">La ubicación quedó fuera de la zona de operación; se registró con esa marca.</p>}
        <button type="button" className="tec-boton" onClick={onVolver}>Volver a Mis actas</button>
      </section>
    </div>
  );
}
