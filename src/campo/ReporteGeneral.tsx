import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { IconoCamara } from "../tecnica/IconoCamara";
import { AvisoSinAgua } from "./AvisoSinAgua";
import { apiCampo, avisoDeError, ErrorCampo, type Confirmacion, type FormularioCampo, type Preparacion } from "./apiCampo";
import { maxDescripcion } from "./limites";
import { abrirCamara, camaraDisponible, capturarFoto, cerrarCamara, ErrorCamara } from "./camara";
import { useUbicacion, UMBRAL_PRECISION_MALA_M, type Fix } from "./ubicacion";
import { decimal, fechaHora, fechaHoraSello, megas, metros } from "./formato";
import { sinFormatosD } from "./formatos/tipos";
import { ConfirmarCancelar, type Destino } from "../components/ConfirmarCancelar";
import { abrirReloj, esRechazoPorHora, recalcularReloj, type RelojInicio } from "./inicio";
import { armarRegistro, BotonesAdjuntar, DIRECCION_VACIA, MarcaOrigen, PanelDireccion, PanelXY, puedeFlexible, xyDigitado, type EstadoDireccion, type EstadoXY, type OrigenFoto } from "./registroFlexible";

// Formulario del reporte general de campo. Pensado para el celular (380 px), una mano, buen contraste.
// - Las etiquetas de grupos, tipos y subtipos salen del catálogo que entrega el servidor (nada escrito aquí).
// - Fotos: con la cámara del formulario, SOLO en memoria; nada se guarda en el dispositivo. Registro flexible (25-nov): el supervisor o el administrador de
//   campo también puede adjuntarlas desde la galería o un archivo y digitar el XY del punto (el servidor lo exige; aquí solo se muestra u oculta).
// - Para todos viaja dónde estaba el dispositivo (o «sin ubicación del dispositivo») y la dirección opcional («¿Quiere agregar dirección?»).
// - Envío: preparar_subida (una vez) → subida directa de cada foto a su URL firmada → crear con el mismo reporte_id. Si algo falla, todo queda en pantalla y «Reintentar» reutiliza el mismo reporte_id.
// - Quien reporta solo ve la confirmación; nunca una lista de reportes.

type FotoLocal = { blob: Blob; url: string; subida: boolean; origen: OrigenFoto };
type Fase = "editando" | "enviando" | "error" | "guardado";

/** `contratoInicial`: contrato que llega de otro formulario («me equivoqué de formulario»). `destinos`/`onIrA`: a qué otros formularios se puede pasar llevando solo el contrato. */
export function ReporteGeneral({ def, correo, onVolver, onOtro, contratoInicial = "", destinos, onIrA }: {
  def: FormularioCampo; correo: string; onVolver: () => void; onOtro: () => void; contratoInicial?: string; destinos?: Destino[]; onIrA?: (destino: string, contrato: string) => void;
}) {
  const [grupo, setGrupo] = useState("");
  const [tipo, setTipo] = useState("");
  const [subtipo, setSubtipo] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [contrato, setContrato] = useState(contratoInicial);
  const [cancelando, setCancelando] = useState(false);          // panel «¿Cancelar este registro?»
  const [riesgo, setRiesgo] = useState(false);
  const flexible = puedeFlexible(def);                          // registro flexible: solo supervisor o administrador de campo, y no desde Técnica
  const [xy, setXy] = useState<EstadoXY>({ activo: false, lat: "", lon: "" });
  const [dir, setDir] = useState<EstadoDireccion>(DIRECCION_VACIA);
  const maxDesc = maxDescripcion(def.limites);   // un solo tope: el de la base (limites.max_descripcion)
  const [fotos, setFotos] = useState<(FotoLocal | null)[]>(() => Array.from({ length: Math.max(1, def.limites.max_fotos) }, () => null));
  const [camaraEn, setCamaraEn] = useState<number | null>(null);
  const [fase, setFase] = useState<Fase>("editando");
  const [errorEnvio, setErrorEnvio] = useState<ErrorCampo | null>(null);
  const [confirmacion, setConfirmacion] = useState<Confirmacion | null>(null);
  const [preparada, setPreparada] = useState(false);          // ya se reservó el reporte_id: las fotos quedan fijas hasta enviar
  const [ahora, setAhora] = useState(() => new Date());
  const ubic = useUbicacion();
  const prep = useRef<Preparacion | null>(null);
  const enviando = useRef(false);
  const recalcularInicio = useRef(false);
  const inicio = useRef<RelojInicio>(abrirReloj());   // pasada 14/11: hora del celular al abrir (el formulario nace de nuevo con cada reporte)
  const fotosRef = useRef(fotos);
  fotosRef.current = fotos;

  useEffect(() => { const r = window.setInterval(() => setAhora(new Date()), 15000); return () => window.clearInterval(r); }, []);
  // Al salir de la pantalla se sueltan las fotos de la memoria.
  useEffect(() => () => { fotosRef.current.forEach((f) => f && URL.revokeObjectURL(f.url)); }, []);
  // Aviso del navegador si intenta cerrar la pestaña con fotos sin enviar (las fotos NO se guardan: se perderían).
  useEffect(() => {
    const hayFotos = fotos.some((f) => f) && fase !== "guardado";
    if (!hayFotos) return;
    const f = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ""; };
    window.addEventListener("beforeunload", f);
    return () => window.removeEventListener("beforeunload", f);
  }, [fotos, fase]);

  // Los formatos del Paso D (campos propios, resultado, consecutivo) los envía «Formatos de actividad», no este formulario: aquí no se ofrecen, aunque el servidor los traiga activos.
  const grupos = useMemo(() => sinFormatosD(def.grupos).filter((g) => g.activo && g.tipos.some((t) => t.activo)), [def]);
  const tiposDelGrupo = useMemo(() => grupos.find((g) => g.codigo === grupo)?.tipos.filter((t) => t.activo) ?? [], [grupos, grupo]);
  const tipoDef = tiposDelGrupo.find((t) => t.codigo === tipo) ?? null;
  const subtipos = tipoDef?.subtipos.filter((s) => s.activo) ?? [];

  const nFotos = fotos.filter(Boolean).length;
  const fix: Fix | null = ubic.fix;
  const bloqueado = fase === "enviando" || fase === "guardado";
  const fotosFijas = bloqueado || preparada;
  // «Cancelar»: sin consecutivo ni nada en el servidor, así que solo se descarta lo del teléfono. Sin nada escrito sale directo; con algo, pide confirmación.
  const hayDatos = grupo !== "" || tipo !== "" || descripcion.trim() !== "" || contrato !== contratoInicial || riesgo || nFotos > 0 || preparada || xy.activo
    || dir.direccion.trim() !== "" || dir.barrio.trim() !== "" || dir.referencia.trim() !== "";
  const pedirCancelar = () => { if (hayDatos) setCancelando(true); else onVolver(); };

  // ----- validación -----
  const faltas: string[] = [];
  if (!tipoDef) faltas.push("Elija el tipo de reporte.");
  if (tipoDef?.exige_texto && descripcion.trim().length < 3) faltas.push("Este tipo exige que describa lo que encontró.");
  if (tipoDef?.exige_subtipo && !subtipo) faltas.push("Elija el subtipo.");
  if (!fotos[0]) faltas.push(flexible ? "Agregue la foto 1 (con la cámara o adjuntada)." : "Tome la foto 1.");
  const xyOk = flexible && xy.activo ? xyDigitado(xy, def.zona) : null;
  if (xyOk && "falta" in xyOk) faltas.push(xyOk.falta);
  else if (!xyOk && !fix) faltas.push(ubic.estado === "buscando" ? "Esperando la ubicación del celular…" : "Sin ubicación no se puede enviar.");
  const sinSenal = typeof navigator !== "undefined" && navigator.onLine === false;

  function elegirGrupo(g: string) { setGrupo(g); setTipo(""); setSubtipo(""); }
  function elegirTipo(t: string) { setTipo(t); setSubtipo(""); }

  function ponerFoto(i: number, f: { blob: Blob }, origen: OrigenFoto = "camara") {
    setFotos((prev) => {
      const sig = [...prev];
      if (sig[i]) URL.revokeObjectURL(sig[i]!.url);
      sig[i] = { blob: f.blob, url: URL.createObjectURL(f.blob), subida: false, origen };
      return sig;
    });
  }
  function quitarFoto(i: number) {
    setFotos((prev) => {
      const sig = [...prev];
      if (sig[i]) URL.revokeObjectURL(sig[i]!.url);
      sig[i] = null;
      return sig;
    });
  }

  const lineasSello = useCallback((): string[] => {
    const f = fix;
    return [
      `${fechaHoraSello(new Date())} · hora del celular`,
      f ? `${f.lat.toFixed(5)}, ${f.lon.toFixed(5)} · ${metros(f.precision_m)}` : "ubicación no disponible",
    ];
  }, [fix]);

  async function enviar() {
    const punto = xyOk && !("falta" in xyOk) ? xyOk : null;      // XY digitado (solo supervisor) o el del GPS
    if (enviando.current || faltas.length > 0 || !tipoDef || (!punto && !fix)) return;       // sin doble pulsación
    enviando.current = true;
    setFase("enviando");
    setErrorEnvio(null);
    if (recalcularInicio.current) { inicio.current = recalcularReloj(inicio.current); recalcularInicio.current = false; }
    try {
      const lista = fotosRef.current.map((f, i) => ({ f, orden: i + 1 })).filter((x): x is { f: FotoLocal; orden: number } => x.f !== null);
      // 1. Preparar (una sola vez; si ya existe, se reutiliza el mismo reporte_id)
      let p = prep.current;
      if (!p) {
        p = await apiCampo.prepararSubida(lista.length, "campo");
        prep.current = p;
        setPreparada(true);
      }
      // 2. Subir las fotos que falten (las ya subidas no se repiten)
      for (const { f, orden } of lista) {
        if (f.subida) continue;
        const destino = p.fotos.find((x) => x.orden === orden);
        if (!destino) throw new ErrorCampo("servidor", "El servidor no preparó todas las fotos.", 500);
        await apiCampo.subirFoto(destino.ruta, destino.token, f.blob);
        f.subida = true;
      }
      // 3. Crear con el mismo reporte_id
      const rutas = lista.map(({ f, orden }) => ({ orden, ruta: p!.fotos.find((x) => x.orden === orden)!.ruta, origen: f.origen }));
      const conf = await apiCampo.crear({
        reporte_id: p.reporte_id, tipo: tipoDef.codigo, subtipo: subtipo || null, descripcion: descripcion.trim() || null, contrato: contrato || null,
        ...(punto ? { lat: punto.lat, lon: punto.lon, precision_m: null } : { lat: Number(fix!.lat.toFixed(6)), lon: Number(fix!.lon.toFixed(6)), precision_m: Math.round(fix!.precision_m * 10) / 10 }),
        riesgo_inmediato: riesgo, origen: "campo", fotos: rutas,
        inicio_dispositivo: inicio.current.iso,
        registro: armarRegistro(!!punto, fix, dir),
      });
      fotosRef.current.forEach((f) => f && URL.revokeObjectURL(f.url));
      setFotos(Array.from({ length: fotos.length }, () => null));
      setConfirmacion(conf);
      setFase("guardado");
    } catch (e) {
      const err = e instanceof ErrorCampo ? e : new ErrorCampo("red", "No se pudo completar el envío.", 0);
      if (esRechazoPorHora(err.message)) recalcularInicio.current = true;   // la persona corrige la hora del celular: el SIGUIENTE envío recalcula el inicio (una vez)
      if (err.tipo === "subida_vencida") {
        // La URL de subida venció: la próxima vez se pide una preparación nueva y se suben todas las fotos de nuevo.
        prep.current = null;
        setPreparada(false);
        fotosRef.current.forEach((f) => { if (f) f.subida = false; });
      }
      setErrorEnvio(err);
      setFase("error");
    } finally {
      enviando.current = false;
    }
  }

  // ===================== Confirmación =====================
  if (fase === "guardado" && confirmacion) {
    return (
      <div className="tec-pagina campo-pagina">
        <section className="tec-tarjeta campo-confirmacion" role="status" aria-live="polite">
          <h1>Reporte guardado</h1>
          <p className="campo-hora">Registrado el {fechaHora(confirmacion.registrado_en)}</p>
          {confirmacion.contrato_verificado === false && (
            <p className="campo-nota" role="note">El número de contrato no se encontró; verifique que esté bien digitado.</p>
          )}
          {confirmacion.aviso_zona && (
            <p className="campo-nota" role="note">La ubicación está fuera de la zona de operación; el reporte se guardó y el supervisor lo revisará.</p>
          )}
          <button type="button" className="tec-boton" onClick={onOtro}>Hacer otro reporte</button>
        </section>
      </div>
    );
  }

  const aviso = errorEnvio ? avisoDeError(errorEnvio) : null;
  const precisionMala = !!fix && fix.precision_m > UMBRAL_PRECISION_MALA_M;

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={pedirCancelar} disabled={bloqueado}>← Formatos</button>
          <h1>Reportar anomalía</h1>
          <button type="button" className="btn-cancelar" onClick={pedirCancelar} disabled={bloqueado}>Cancelar</button>
        </div>
        {cancelando && (
          <ConfirmarCancelar titulo="¿Cancelar este registro?"
            mensaje={`Se descarta lo escrito${nFotos > 0 ? ` y ${nFotos === 1 ? "la foto tomada" : `las ${nFotos} fotos tomadas`}` : ""}. No se guarda nada en el servidor${preparada ? "; las fotos ya reservadas quedan sin usar" : ""}.`}
            destinos={destinos} onIrA={onIrA ? (d) => onIrA(d, contrato) : undefined}
            onConfirmar={() => onVolver()} onSeguir={() => setCancelando(false)} />
        )}

        {/* 1. Tipo */}
        <div className="tec-campo">
          <label htmlFor="campo-grupo">Tipo de reporte</label>
          <select id="campo-grupo" value={grupo} onChange={(e) => elegirGrupo(e.target.value)} disabled={bloqueado}>
            <option value="">Elija el grupo…</option>
            {grupos.map((g) => <option key={g.codigo} value={g.codigo}>{g.nombre}</option>)}
          </select>
          <select id="campo-tipo" aria-label="Tipo" value={tipo} onChange={(e) => elegirTipo(e.target.value)} disabled={bloqueado || !grupo}>
            <option value="">{grupo ? "Elija el tipo…" : "Primero elija el grupo"}</option>
            {tiposDelGrupo.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre}</option>)}
          </select>
        </div>
        {tipoDef && subtipos.length > 0 && (
          <div className="tec-campo">
            <label htmlFor="campo-subtipo">Subtipo{tipoDef.exige_subtipo ? "" : " (opcional)"}</label>
            <select id="campo-subtipo" value={subtipo} onChange={(e) => setSubtipo(e.target.value)} disabled={bloqueado}>
              <option value="">{tipoDef.exige_subtipo ? "Elija el subtipo…" : "Sin subtipo"}</option>
              {subtipos.map((s) => <option key={s.codigo} value={s.codigo}>{s.nombre}</option>)}
            </select>
          </div>
        )}

        {/* 2. Qué encontró */}
        <div className="tec-campo">
          <label htmlFor="campo-desc">¿Qué encontró?{tipoDef?.exige_texto ? " (obligatorio)" : " (opcional)"}</label>
          <textarea id="campo-desc" className="campo-texto" rows={4} maxLength={maxDesc} value={descripcion} onChange={(e) => setDescripcion(e.target.value)} disabled={bloqueado} aria-invalid={!!tipoDef?.exige_texto && descripcion.trim().length < 3 && descripcion.length > 0} />
          <span className="campo-contador">{descripcion.length.toLocaleString("es-CO")} de {maxDesc.toLocaleString("es-CO")}</span>
        </div>

        {/* 3. Fotos */}
        <div className="tec-campo">
          <span className="campo-etiqueta">Fotos <small>(la 1 es obligatoria; hasta {def.limites.max_fotos}; máximo {megas(def.limites.max_bytes_foto)} cada una)</small></span>
          {!camaraDisponible() && (flexible
            ? <p className="campo-sub" role="status">Este navegador no permite usar la cámara desde la página: adjunte las fotos desde la galería o desde un archivo.</p>
            : <p className="campo-error" role="alert">Este navegador no permite usar la cámara desde la página, y sin la foto 1 no se puede enviar. Use Safari en iPhone o Chrome en Android, actualizado, y abra el geoportal desde su dirección oficial (https).</p>
          )}
          <div className="campo-fotos">
            {fotos.map((f, i) => (
              <div key={i} className="campo-foto">
                <span className="campo-foto-n">Foto {i + 1}{i === 0 ? " (obligatoria)" : " (opcional)"}</span>
                {f ? (
                  <>
                    <img src={f.url} alt={`Foto ${i + 1} ${f.origen === "camara" ? "tomada" : "adjuntada"}`} className="campo-foto-img" />
                    <MarcaOrigen origen={f.origen} />
                    {!fotosFijas && (
                      <div className="campo-foto-acc">
                        <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => setCamaraEn(i)} disabled={!camaraDisponible()}>Repetir</button>
                        {i > 0 && <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => quitarFoto(i)}>Quitar</button>}
                      </div>
                    )}
                  </>
                ) : (
                  <>
                    <button type="button" className="tec-boton campo-boton-foto" onClick={() => setCamaraEn(i)} disabled={fotosFijas || !camaraDisponible() || (i > 0 && !fotos[0])}>
                      <IconoCamara />Tomar foto {i + 1}
                    </button>
                    {flexible && <BotonesAdjuntar rotulo={`Foto ${i + 1}`} maxBytes={def.limites.max_bytes_foto} deshabilitado={fotosFijas || (i > 0 && !fotos[0])}
                      onFoto={(blob, origen) => ponerFoto(i, { blob }, origen)} />}
                  </>
                )}
              </div>
            ))}
          </div>
          {preparada && fase !== "guardado" && <p className="campo-sub">Las fotos ya están reservadas para este envío; no se pueden cambiar hasta enviarlo.</p>}
          <p className="campo-sub">{flexible ? "Las fotos (de la cámara o adjuntadas) quedan solo en la memoria de esta pantalla: no se guardan en el celular. Las adjuntadas quedan marcadas en el reporte."
                                             : "Las fotos se toman con la cámara y quedan solo en la memoria de esta pantalla: no se guardan en el celular ni en la galería."}</p>
        </div>

        {/* 4. Contrato */}
        <div className="tec-campo">
          <label htmlFor="campo-contrato">Número de contrato (opcional)</label>
          <input id="campo-contrato" type="text" inputMode="numeric" pattern="[0-9]*" autoComplete="off" maxLength={20} value={contrato} onChange={(e) => setContrato(e.target.value.replace(/\D/g, ""))} disabled={bloqueado} />
          <AvisoSinAgua contrato={contrato} />
        </div>

        {/* 4b. Dirección opcional (registro flexible, 25-nov) */}
        <PanelDireccion estado={dir} onCambio={setDir} deshabilitado={bloqueado} />

        {/* 5. Riesgo inmediato */}
        <label className="campo-check">
          <input type="checkbox" checked={riesgo} onChange={(e) => setRiesgo(e.target.checked)} disabled={bloqueado} />
          <span><strong>Hay riesgo inmediato</strong> para personas o bienes<small>Queda marcado en el reporte para quien lo revise. Si es una emergencia, avise también a su supervisor.</small></span>
        </label>

        {/* 5b. XY digitado (solo supervisor o administrador de campo) */}
        {flexible && <PanelXY estado={xy} onCambio={setXy} fix={fix} zona={def.zona} deshabilitado={bloqueado} />}

        {/* 6. Automáticos */}
        <dl className="campo-auto">
          <div>
            <dt>{xyOk && !("falta" in xyOk) ? "Ubicación del dispositivo" : "Ubicación"}</dt>
            <dd>
              {fix ? `${decimal(fix.lat, 5)}, ${decimal(fix.lon, 5)} (${metros(fix.precision_m)})` : ubic.estado === "buscando" ? "Buscando…" : "No disponible"}
              <button type="button" className="campo-enlace" onClick={ubic.actualizar} disabled={bloqueado}>Actualizar ubicación</button>
            </dd>
          </div>
          <div><dt>Fecha y hora</dt><dd>{fechaHora(ahora)} <small>(la oficial será la del servidor)</small></dd></div>
          <div><dt>Usuario</dt><dd>{correo}</dd></div>
        </dl>
        {ubic.mensaje && <p className="campo-error" role="alert">{ubic.mensaje}</p>}
        {precisionMala && (
          <p className="campo-nota" role="note">La ubicación es poco precisa (más de {UMBRAL_PRECISION_MALA_M} m). Espere unos segundos o salga a cielo abierto y pulse «Actualizar ubicación». Puede enviar el reporte igualmente.</p>
        )}

        {/* Errores y envío */}
        {faltas.length > 0 && fase === "editando" && (nFotos > 0 || tipo) && <ul className="campo-faltas">{faltas.map((m) => <li key={m}>{m}</li>)}</ul>}
        {sinSenal && <p className="campo-error" role="alert">No hay señal en este momento. Sus datos y fotos siguen aquí; envíe cuando recupere la conexión.</p>}
        {fase === "error" && aviso && <p className="campo-error" role="alert">{aviso.texto}</p>}
        {fase === "error" && errorEnvio?.tipo === "sesion" ? null : (
          <button type="button" className="tec-boton campo-enviar" onClick={() => void enviar()} disabled={fase === "enviando" || faltas.length > 0 || (fase === "error" && aviso !== null && !aviso.reintentable)}>
            {fase === "enviando" ? "Enviando…" : fase === "error" ? "Reintentar" : "Enviar reporte"}
          </button>
        )}
        <button type="button" className="btn-cancelar" onClick={pedirCancelar} disabled={fase === "enviando"}>Cancelar</button>
      </section>

      {camaraEn !== null && (
        <PanelCamara
          rotulo={`Foto ${camaraEn + 1}`}
          maxBytes={def.limites.max_bytes_foto}
          sello={lineasSello}
          onFoto={(f) => { ponerFoto(camaraEn, f); setCamaraEn(null); }}
          onCerrar={() => setCamaraEn(null)}
        />
      )}
    </div>
  );
}

// ============ Cámara dentro del formulario ============
function PanelCamara({ rotulo, maxBytes, sello, onFoto, onCerrar }: {
  rotulo: string; maxBytes: number; sello: () => string[]; onFoto: (f: { blob: Blob }) => void; onCerrar: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const flujo = useRef<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lista, setLista] = useState(false);
  const [procesando, setProcesando] = useState(false);

  useEffect(() => {
    let vivo = true;
    abrirCamara()
      .then((f) => {
        if (!vivo) { cerrarCamara(f); return; }
        flujo.current = f;
        const v = videoRef.current;
        if (v) { v.srcObject = f; void v.play().catch(() => {}); }
      })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCamara ? e.message : "No se pudo abrir la cámara."); });
    return () => { vivo = false; cerrarCamara(flujo.current); flujo.current = null; };
  }, []);

  async function capturar() {
    const v = videoRef.current;
    if (!v || procesando) return;
    setProcesando(true);
    try {
      const f = await capturarFoto(v, sello(), maxBytes);
      if (!f) { setError(`La foto pesa más de ${megas(maxBytes)} aun reducida. Acérquese al objeto o mejore la luz e intente de nuevo.`); return; }
      onFoto(f);
    } catch (e) {
      setError(e instanceof ErrorCamara ? e.message : "No se pudo tomar la foto.");
    } finally {
      setProcesando(false);
    }
  }

  return (
    <div className="campo-camara" role="dialog" aria-modal="true" aria-label={`Cámara · ${rotulo}`}>
      <div className="campo-camara-cab">{rotulo}</div>
      {error ? (
        <div className="campo-camara-error"><p role="alert">{error}</p></div>
      ) : (
        <video ref={videoRef} className="campo-video" autoPlay playsInline muted onLoadedMetadata={() => setLista(true)} />
      )}
      <div className="campo-camara-acc">
        <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        {!error && <button type="button" className="tec-boton campo-capturar" onClick={() => void capturar()} disabled={!lista || procesando}>{procesando ? "Procesando…" : "Tomar foto"}</button>}
      </div>
    </div>
  );
}
