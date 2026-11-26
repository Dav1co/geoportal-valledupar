import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { BotonVolver } from "../BotonVolver";
import { IconoCamara } from "../../tecnica/IconoCamara";
import { AvisoSinAgua } from "../AvisoSinAgua";
import "./formatos.css";
import { ConfirmarCancelar, type Destino as DestinoCancelar } from "../../components/ConfirmarCancelar";
import { avisoDeError, apiCampo, ErrorCampo, type FormularioCampo, type Preparacion } from "../apiCampo";
import { maxDescripcion } from "../limites";
import { abrirCamara, camaraDisponible, capturarFoto, cerrarCamara, ErrorCamara, ladoPara, LADO_MAYOR_PX } from "../camara";
import { useUbicacion, UMBRAL_PRECISION_MALA_M, type Fix } from "../ubicacion";
import { contratoConDireccion, DireccionDelContrato, PanelDireccionTerreno, useDireccionContrato } from "../direccionContrato";
import { armarRegistro, BotonesAdjuntar, DIRECCION_VACIA, MarcaOrigen, PanelDireccion, PanelXY, puedeFlexible, xyDigitado, type EstadoDireccion, type EstadoXY, type OrigenFoto } from "../registroFlexible";
import { decimal, fechaHora, fechaHoraSello, megas, metros } from "../formato";
import { apiFormatos } from "./apiFormatos";
import { SeccionConstancia } from "../constancia/SeccionConstancia";
import { useConstancia } from "../constancia/useConstancia";
import { abrirReloj, esRechazoPorHora, recalcularReloj, type RelojInicio } from "../inicio";
import { aplicarValoresIniciales, prellenarHoraInicio, agruparSecciones, aplanarDatos, avanceSeccion, camposVisibles, contadorFotos, fotosParaCrear, marcoIrregularidad, maximoFotos, minimoFotos, ordenarFotos, rotuloObservaciones, validarFormato, type ValoresCampos } from "./logica";
import { etiquetasActivas, type CampoDef, type ConfirmacionFormato, type Resultado, type TipoFormato } from "./tipos";
import { FirmasRegistro } from "../documentos/FirmasRegistro";
import { estadoDeFirmaAtendio, faltasFirmas, FIRMAS_VACIAS, guardarFirmas, SIN_FUENTE, type FirmasLocal, type FuenteFormulario } from "../documentos/firmasLogica";
import { PdfRegistro, SIN_ORIGEN, useDocumento, VieneDe, vincularOrigen, type Origen } from "../documentos/Registro";
import { esFirmaDefinitiva } from "../documentos/apiDocumentos";

// Formulario de UN formato del Paso D (campos propios, fotos con etiqueta, resultado y causal, consecutivo). Pensado para el celular (380 px) y una mano.
// - Todo (campos, fotos mínimas y máximas, causales) sale del catálogo que entrega el servidor; aquí no hay nombres de formatos.
// - Fotos: con la cámara del formulario (1600 px, JPEG 0,72, sello, tope de bytes del servidor), SOLO en memoria. Registro flexible (25-nov): el supervisor o el
//   administrador de campo también puede adjuntarlas desde la galería o un archivo y digitar el XY (el servidor lo exige). Para todos viaja dónde estaba el
//   dispositivo; la dirección opcional, en los formatos cuyo contrato no es obligatorio.
// - Envío: preparar_subida (con el tipo) → subida directa de cada foto → crear con el mismo reporte_id. «Reintentar» reutiliza el reporte_id: no duplica ni gasta otro consecutivo.
// - Visita inefectiva: no se exigen campos ni fotos obligatorias; se pide la causal, la foto de fachada o predio (soporte) y la precisión de la ubicación.
// - MALA SEÑAL: no hay modo sin conexión todavía. Si el envío falla por red, todo queda en pantalla para reintentar. GANCHO: `alFallarRed` recibe el cuerpo sin fotos cuando el
//   fallo es de red; un modo sin conexión futuro podría encolarlo. Guardar fotos en el dispositivo está prohibido por ahora (solo memoria).

type FotoLocal = { blob: Blob; url: string; subida: boolean; origen: OrigenFoto };
type Fase = "editando" | "enviando" | "error" | "guardado";
type Destino = { tipo: "etiqueta"; codigo: string; nombre: string } | { tipo: "adicional"; indice: number | null; nombre: string };

export type EnvioPendiente = { tipo: string; resultado: Resultado | null; causal: string | null; datos: Record<string, unknown> | null; reporte_id: string | null };

export function FormularioFormato({ def, tipo: tipoServidor, correo, onVolver, onOtro, alFallarRed, puedeActa = false, onAbrirActa, contratoInicial = "", destinos, onIrA, valoresIniciales }: {
  def: FormularioCampo; tipo: TipoFormato; correo: string; onVolver: () => void; onOtro: () => void; alFallarRed?: (envio: EnvioPendiente) => void;
  /** Permiso `acta` (lo decide el servidor): solo con él se ofrece abrir el acta de inspección técnica. `onAbrirActa` recibe el contrato para precargarlo. */
  puedeActa?: boolean; onAbrirActa?: (contrato: string) => void;
  /** Cancelar: contrato que llega de otro formulario y a qué otros se puede pasar llevando solo el contrato («me equivoqué de formulario»). */
  contratoInicial?: string; destinos?: DestinoCancelar[]; onIrA?: (destino: string, contrato: string) => void;
  /** Valores que llegan ya marcados (atajo de «Análisis de contrato»: Instalación de medidor con «Cambio»). Se aplican sobre la hora de inicio; solo prellenan. */
  valoresIniciales?: Record<string, unknown>;
}) {
  // Comercial 21-nov (D13): en las revisiones, «¿Se requiere cambio de medidor?» se oculta y se llena solo con «¿Da lugar a otras actividades?» (cambio_medidor ∈ da_lugar).
  const tipo = useMemo(() => sinReqCambio(tipoServidor), [tipoServidor]);
  const reqDerivado = tipo !== tipoServidor;
  const [resultado, setResultado] = useState<Resultado | "">("");
  const [causal, setCausal] = useState("");
  const [subtipo, setSubtipo] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [contrato, setContrato] = useState(contratoInicial);
  const [cancelando, setCancelando] = useState(false);
  const recalcularInicio = useRef(false);
  const inicio = useRef<RelojInicio>(abrirReloj());   // pasada 14/11: hora del celular al abrir este formato
  // Decisión 10: «Hora de inicio» (la del papel) nace con la hora de apertura; la persona la puede cambiar
  const [valores, setValores] = useState<ValoresCampos>(() => aplicarValoresIniciales(tipo, prellenarHoraInicio(tipo, inicio.current.iso), valoresIniciales));
  const [porEtiqueta, setPorEtiqueta] = useState<Record<string, FotoLocal | null>>({});
  const [adicionales, setAdicionales] = useState<FotoLocal[]>([]);
  const [camaraEn, setCamaraEn] = useState<Destino | null>(null);
  const [fase, setFase] = useState<Fase>("editando");
  const [errorEnvio, setErrorEnvio] = useState<ErrorCampo | null>(null);
  const [confirmacion, setConfirmacion] = useState<ConfirmacionFormato | null>(null);
  const [invitarActa, setInvitarActa] = useState<{ contrato: string } | null>(null);   // se fija al guardar: irregularidad marcada y contrato con que se guardó
  const [abiertas, setAbiertas] = useState<Record<string, boolean>>({});              // secciones abiertas o cerradas por la persona; sin tocar, solo la primera está abierta
  const [preparada, setPreparada] = useState(false);
  const [ahora, setAhora] = useState(() => new Date());
  const ubic = useUbicacion();
  const flexible = puedeFlexible(def);                          // registro flexible: solo supervisor o administrador de campo, y no desde Técnica
  const conDireccion = tipo.requiere_contrato !== "si";        // la dirección opcional solo donde el contrato no es obligatorio (David, 25-nov)
  const [xy, setXy] = useState<EstadoXY>({ activo: false, lat: "", lon: "" });
  const [dir, setDir] = useState<EstadoDireccion>(DIRECCION_VACIA);
  const dirContrato = useDireccionContrato(tipo.requiere_contrato === "no" ? "" : contrato);   // consultar direcciones (25-nov)
  const conDireccionTerreno = contratoConDireccion(dirContrato.r);    // con un contrato que existe: «La dirección en terreno es distinta» (cualquier formato)
  const prep = useRef<Preparacion | null>(null);
  const enviando = useRef(false);
  const cons = useConstancia(tipo.codigo);
  // Comercial 21-nov: firmas con el dedo y PDF si el servidor dice que este formulario los lleva (documentos_catalogo); «¿Viene de…?» con las derivadas pendientes del contrato.
  const doc = useDocumento("campo", `tipo:${tipo.codigo}`);
  const reglas = doc?.firmas ?? null;
  const [firmas, setFirmas] = useState<FirmasLocal>(FIRMAS_VACIAS);
  const firmasEnviadas = useRef(new Set<string>());
  const [origen, setOrigen] = useState<Origen>(SIN_ORIGEN);
  const [registroId, setRegistroId] = useState<string | null>(null);
  const [avisoOrigen, setAvisoOrigen] = useState<string | null>(null);     // «Constancia por correo»: solo en los 4 formatos del acta de revisión o instalación y si el documento está habilitado
  const refEtq = useRef(porEtiqueta); refEtq.current = porEtiqueta;
  const refAdic = useRef(adicionales); refAdic.current = adicionales;

  const etiquetas = useMemo(() => etiquetasActivas(tipo), [tipo]);
  const subtipos = tipo.subtipos.filter((s) => s.activo);
  const usaEtiquetas = etiquetas.length > 0;
  const fix: Fix | null = ubic.fix;
  const bloqueado = fase === "enviando" || fase === "guardado";
  const fotosFijas = bloqueado || preparada;
  const inefectivo = resultado === "inefectivo";

  useEffect(() => { const r = window.setInterval(() => setAhora(new Date()), 15000); return () => window.clearInterval(r); }, []);
  const soltarTodo = () => { Object.values(refEtq.current).forEach((f) => f && URL.revokeObjectURL(f.url)); refAdic.current.forEach((f) => URL.revokeObjectURL(f.url)); };
  useEffect(() => soltarTodo, []);
  const nFotos = Object.values(porEtiqueta).filter(Boolean).length + adicionales.length;
  useEffect(() => {
    if (nFotos === 0 || fase === "guardado") return;
    const f = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ""; };
    window.addEventListener("beforeunload", f);
    return () => window.removeEventListener("beforeunload", f);
  }, [nFotos, fase]);

  const tope = def.limites.max_fotos;
  const maxDesc = maxDescripcion(def.limites);   // un solo tope: el de la base (limites.max_descripcion)
  const minimo = minimoFotos(tipo, resultado);
  const maximo = maximoFotos(tipo, tope);
  const xyOk = flexible && xy.activo ? xyDigitado(xy, def.zona) : null;
  const xyListo = !!xyOk && !("falta" in xyOk);
  const faltasFormato = validarFormato(tipo, {
    resultado, causal, subtipo, descripcion, contrato, valores,
    etiquetasConFoto: etiquetas.filter((e) => porEtiqueta[e.codigo]).map((e) => e.codigo),
    // Sin etiquetas en el catálogo, todas las fotos van en «adicionales» (sin etiqueta): cuentan igual.
    // con el XY digitado (supervisor) la ubicación es la digitada y la visita inefectiva no exige la precisión del GPS (David, 25-nov)
    adicionales: adicionales.length, tieneUbicacion: !!fix || xyListo, tienePrecision: xyListo || (!!fix && Number.isFinite(fix.precision_m)), topeGeneral: tope,
  });
  if (xyOk && "falta" in xyOk) faltasFormato.push(xyOk.falta);
  const tiene = (c: string) => (tipo.campos ?? []).some((x) => x.codigo === c && x.activo !== false);
  const fuente: FuenteFormulario = reglas ? { estado: tiene("firma_atendio") ? estadoDeFirmaAtendio(valores.firma_atendio) : undefined, nombre: tiene("atendio_nombre") ? String(valores.atendio_nombre ?? "") : undefined } : SIN_FUENTE;
  const faltasDoc = doc === undefined ? ["Cargando lo que lleva este formulario…"] : faltasFirmas(reglas, firmas, fuente);
  const faltas = [...faltasFormato, ...cons.faltas, ...faltasDoc];
  const { errores } = aplanarDatos(tipo, valores);
  const visibles = useMemo(() => camposVisibles(tipo, valores), [tipo, valores]);
  const secciones = useMemo(() => agruparSecciones(visibles), [visibles]);
  const conSecciones = secciones.some((x) => x.titulo !== null);
  const marcoIrr = marcoIrregularidad(tipo, valores);
  const sinSenal = typeof navigator !== "undefined" && navigator.onLine === false;

  function ponerValor(codigo: string, v: string | string[]) { setValores((p) => ({ ...p, [codigo]: v })); }

  function guardarFoto(d: Destino, blob: Blob, origen: OrigenFoto = "camara") {
    const nueva: FotoLocal = { blob, url: URL.createObjectURL(blob), subida: false, origen };
    if (d.tipo === "etiqueta") {
      setPorEtiqueta((p) => { if (p[d.codigo]) URL.revokeObjectURL(p[d.codigo]!.url); return { ...p, [d.codigo]: nueva }; });
    } else {
      setAdicionales((p) => {
        const sig = [...p];
        if (d.indice !== null && sig[d.indice]) { URL.revokeObjectURL(sig[d.indice].url); sig[d.indice] = nueva; } else sig.push(nueva);
        return sig;
      });
    }
  }
  function quitarEtiqueta(codigo: string) { setPorEtiqueta((p) => { if (p[codigo]) URL.revokeObjectURL(p[codigo]!.url); return { ...p, [codigo]: null }; }); }
  function quitarAdicional(i: number) { setAdicionales((p) => { URL.revokeObjectURL(p[i].url); return p.filter((_, j) => j !== i); }); }

  const lineasSello = useCallback((): string[] => [
    `${fechaHoraSello(new Date())} · hora del celular`,
    fix ? `${fix.lat.toFixed(5)}, ${fix.lon.toFixed(5)} · ${metros(fix.precision_m)}` : "ubicación no disponible",
  ], [fix]);

  async function enviar() {
    const punto = xyOk && !("falta" in xyOk) ? xyOk : null;      // XY digitado (solo supervisor) o el del GPS
    if (enviando.current || faltas.length > 0 || (!punto && !fix)) return;                  // sin doble pulsación
    enviando.current = true;
    setFase("enviando");
    setErrorEnvio(null);
    if (recalcularInicio.current) { inicio.current = recalcularReloj(inicio.current); recalcularInicio.current = false; }
    const { datos } = aplanarDatos(tipo, valores);
    if (reqDerivado && datos) datos.req_cambio_medidor = Array.isArray(datos.da_lugar) && datos.da_lugar.includes("cambio_medidor");   // sí/no viaja como booleano
    try {
      const ordenadas = ordenarFotos<FotoLocal>(tipo, refEtq.current, refAdic.current);
      let p = prep.current;
      if (!p) {
        p = await apiFormatos.prepararSubida(ordenadas.length, tipo.codigo);
        prep.current = p;
        setPreparada(true);
      }
      const rutas = new Map<number, string>();
      for (const o of ordenadas) {
        const destino = p.fotos.find((x) => x.orden === o.orden);
        if (!destino) throw new ErrorCampo("servidor", "El servidor no preparó todas las fotos.", 500);
        rutas.set(o.orden, destino.ruta);
        if (o.foto.subida) continue;                                              // las ya subidas no se repiten
        await apiCampo.subirFoto(destino.ruta, destino.token, o.foto.blob);
        o.foto.subida = true;
      }
      if (reglas) await guardarFirmas("campo", p.reporte_id, reglas, firmas, fuente, firmasEnviadas.current)   // antes de registrar; repetirla reemplaza
        .catch((e) => { if (!esFirmaDefinitiva(e)) throw e; });                                              // ya estaba registrado: crear responde «repetido»
      const conf = await apiFormatos.crear({
        reporte_id: p.reporte_id, tipo: tipo.codigo, subtipo: subtipo || null, descripcion: descripcion.trim() || null,
        contrato: tipo.requiere_contrato === "no" ? null : contrato || null,
        ...(punto ? { lat: punto.lat, lon: punto.lon, precision_m: null } : { lat: Number(fix!.lat.toFixed(6)), lon: Number(fix!.lon.toFixed(6)), precision_m: Math.round(fix!.precision_m * 10) / 10 }),
        riesgo_inmediato: false, origen: "campo",
        fotos: fotosParaCrear(ordenadas, rutas).map((x, i) => ({ ...x, origen: ordenadas[i].foto.origen })),
        registro: armarRegistro(!!punto, fix, conDireccion || conDireccionTerreno ? dir : null),
        datos, resultado: tipo.genera_resultado ? (resultado || null) : null, causal: inefectivo ? causal : null,
        ...(cons.bloque ? { constancia: cons.bloque } : {}),
        inicio_dispositivo: inicio.current.iso,
      });
      soltarTodo();
      setRegistroId(p.reporte_id);
      setAvisoOrigen(await vincularOrigen(p.reporte_id, origen));
      setInvitarActa(marcoIrr && puedeActa && onAbrirActa && tipo.requiere_contrato !== "no" && contrato ? { contrato } : null);
      setPorEtiqueta({});
      setAdicionales([]);
      setConfirmacion(conf);
      setFase("guardado");
    } catch (e) {
      const err = e instanceof ErrorCampo ? e : new ErrorCampo("red", "No se pudo completar el envío.", 0);
      if (esRechazoPorHora(err.message)) recalcularInicio.current = true;   // la persona corrige la hora del celular: el SIGUIENTE envío recalcula el inicio (una vez)
      if (err.tipo === "subida_vencida") {
        prep.current = null;                                                      // se pide una preparación nueva y se suben todas las fotos de nuevo
        setPreparada(false);
        Object.values(refEtq.current).forEach((f) => { if (f) f.subida = false; });
        refAdic.current.forEach((f) => { f.subida = false; });
      }
      if (err.tipo === "red") alFallarRed?.({ tipo: tipo.codigo, resultado: resultado || null, causal: causal || null, datos, reporte_id: prep.current?.reporte_id ?? null });
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
          <p className="campo-sub">{tipo.nombre}</p>
          {confirmacion.consecutivo && (
            <div>
              <p className="campo-sub">Consecutivo</p>
              <p className="campo-consecutivo">{confirmacion.consecutivo}</p>
            </div>
          )}
          {confirmacion.repetido && <p className="campo-nota" role="note">Este reporte ya estaba guardado; no se duplicó.</p>}
          {doc?.lleva_pdf && registroId ? <PdfRegistro esquema="campo" registroId={registroId} /> : null}
          {avisoOrigen ? <p className="campo-nota" role="alert">{avisoOrigen} El reporte sí quedó guardado; avísele al supervisor.</p> : null}
          <p className="campo-hora">Registrado el {fechaHora(confirmacion.registrado_en)}</p>
          {confirmacion.contrato_verificado === false && <p className="campo-nota" role="note">El número de contrato no se encontró; verifique que esté bien digitado.</p>}
          {confirmacion.aviso_zona && <p className="campo-nota" role="note">La ubicación está fuera de la zona de operación; el reporte se guardó y el supervisor lo revisará.</p>}
          {invitarActa && (
            <div className="campo-nota" role="note">
              <p>Marcó que se encontró una irregularidad. Este formato no reemplaza el acta de inspección técnica: ábrala ahora sobre el contrato {invitarActa.contrato}.</p>
              <button type="button" className="tec-boton" onClick={() => onAbrirActa?.(invitarActa.contrato)}>Ir a «Reportar posible pérdida»</button>
            </div>
          )}
          <button type="button" className="tec-boton" onClick={onOtro}>Hacer otro reporte</button>
          <BotonVolver onClick={onVolver} descripcion="Formatos de actividad" />
        </section>
      </div>
    );
  }

  const aviso = errorEnvio ? avisoDeError(errorEnvio) : null;
  const precisionMala = !!fix && fix.precision_m > UMBRAL_PRECISION_MALA_M;
  const contador = contadorFotos(nFotos, minimo, maximo);
  const contadorOk = nFotos >= minimo && nFotos <= maximo;
  const puedeMas = !fotosFijas && nFotos < maximo;
  const hayInterac = nFotos > 0 || resultado !== "" || Object.keys(valores).length > 0;
  // «Cancelar»: el consecutivo se toma al REGISTRAR (no antes), así que solo se descarta lo del teléfono. Sin nada escrito sale directo; con algo, pide confirmación.
  const hayDatos = hayInterac || causal !== "" || subtipo !== "" || descripcion.trim() !== "" || contrato !== contratoInicial || preparada || xy.activo
    || dir.direccion.trim() !== "" || dir.barrio.trim() !== "" || dir.referencia.trim() !== "";
  const pedirCancelar = () => { if (hayDatos) setCancelando(true); else onVolver(); };

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <BotonVolver onClick={pedirCancelar} deshabilitado={bloqueado} descripcion="Formatos de actividad" />
          <h1>{tipo.nombre}</h1>
          <button type="button" className="btn-cancelar" onClick={pedirCancelar} disabled={bloqueado}>Cancelar</button>
        </div>
        {cancelando && (
          <ConfirmarCancelar titulo="¿Cancelar este registro?"
            mensaje={`Se descarta lo escrito${nFotos > 0 ? ` y ${nFotos === 1 ? "la foto tomada" : `las ${nFotos} fotos tomadas`}` : ""}. No se guarda nada ni se gasta ningún consecutivo${preparada ? "; las fotos ya reservadas quedan sin usar" : ""}.`}
            destinos={destinos} onIrA={onIrA ? (d) => onIrA(d, contrato) : undefined}
            onConfirmar={() => onVolver()} onSeguir={() => setCancelando(false)} />
        )}
        {tipo.usa_consecutivo && <p className="campo-sub">Al enviar se le asignará un número consecutivo.</p>}

        {/* Resultado */}
        {tipo.genera_resultado && (
          <div className="tec-campo">
            <span className="campo-etiqueta" id="fp-res-rot">Resultado de la visita</span>
            <div className="campo-res" role="radiogroup" aria-labelledby="fp-res-rot">
              <label><input type="radio" name="fp-res" value="efectivo" checked={resultado === "efectivo"} onChange={() => { setResultado("efectivo"); setCausal(""); }} disabled={bloqueado || preparada} />Efectiva</label>
              <label className="campo-res-no"><input type="radio" name="fp-res" value="inefectivo" checked={resultado === "inefectivo"} onChange={() => setResultado("inefectivo")} disabled={bloqueado || preparada} />Inefectiva</label>
            </div>
            {inefectivo && (
              <>
                <label htmlFor="fp-causal">Causal de la visita inefectiva</label>
                <select id="fp-causal" value={causal} onChange={(e) => setCausal(e.target.value)} disabled={bloqueado}>
                  <option value="">Elija la causal…</option>
                  {(tipo.causales ?? []).map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}
                </select>
                <p className="campo-nota" role="note">Visita inefectiva: no se exigen los campos ni las fotos obligatorias. Tome la foto de la fachada o del predio y espere a que la ubicación muestre su precisión.</p>
              </>
            )}
          </div>
        )}

        {tipo.subtipos.length > 0 && subtipos.length > 0 && (
          <div className="tec-campo">
            <label htmlFor="fp-subtipo">Subtipo{tipo.exige_subtipo ? "" : " (opcional)"}</label>
            <select id="fp-subtipo" value={subtipo} onChange={(e) => setSubtipo(e.target.value)} disabled={bloqueado}>
              <option value="">{tipo.exige_subtipo ? "Elija el subtipo…" : "Sin subtipo"}</option>
              {subtipos.map((s) => <option key={s.codigo} value={s.codigo}>{s.nombre}</option>)}
            </select>
          </div>
        )}

        {tipo.requiere_contrato !== "no" && (
          <div className="tec-campo">
            <label htmlFor="fp-contrato">Número de contrato{tipo.requiere_contrato === "si" ? " (obligatorio)" : " (opcional)"}</label>
            <input id="fp-contrato" type="text" inputMode="numeric" pattern="[0-9]*" autoComplete="off" maxLength={20} value={contrato} onChange={(e) => setContrato(e.target.value.replace(/\D/g, ""))} disabled={bloqueado} />
            <AvisoSinAgua contrato={contrato} />
            <DireccionDelContrato estado={dirContrato} />
          </div>
        )}
        {tipo.requiere_contrato !== "no" && <VieneDe contrato={contrato} formulario={`tipo:${tipo.codigo}`} conActas={tiene("da_lugar")} valor={origen} onCambio={setOrigen} deshabilitado={bloqueado} />}

        {/* Campos propios del formato */}
        {!conSecciones && visibles.map((c) => <CampoPropio key={c.codigo} c={c} valor={valores[c.codigo]} error={errores[c.codigo]} obligatorio={c.obligatorio && !inefectivo} deshabilitado={bloqueado} onCambio={(v) => ponerValor(c.codigo, v)} />)}
        {conSecciones && secciones.map((sec, i) => {
          const clave = sec.titulo ?? `sin-titulo-${i}`;
          const av = avanceSeccion(sec.campos, valores, inefectivo);
          const abierta = abiertas[clave] ?? i === 0;
          return (
            <details key={clave} className="campo-seccion" open={abierta} onToggle={(e) => { const a = (e.currentTarget as HTMLDetailsElement).open; if (a !== abierta) setAbiertas((p) => ({ ...p, [clave]: a })); }}>
              <summary>
                <span className="campo-seccion-titulo">{sec.titulo ?? "Otros datos"}</span>
                <span className={`campo-seccion-estado${av.faltan > 0 ? " campo-seccion-falta" : ""}`}>{av.faltan > 0 ? `faltan ${av.faltan}` : `${av.respondidos} de ${av.total}`}</span>
              </summary>
              {sec.campos.map((c) => <CampoPropio key={c.codigo} c={c} valor={valores[c.codigo]} error={errores[c.codigo]} obligatorio={c.obligatorio && !inefectivo} deshabilitado={bloqueado} onCambio={(v) => ponerValor(c.codigo, v)} />)}
            </details>
          );
        })}
        {marcoIrr && <p className="campo-nota" role="note">{puedeActa && tipo.requiere_contrato !== "no" ? "Marcó una irregularidad: al guardar el reporte podrá abrir el acta de inspección técnica sobre el mismo contrato (este formato no la reemplaza)." : "Marcó una irregularidad: avise a su supervisor para que se levante el acta de inspección técnica (este formato no la reemplaza)."}</p>}

        <div className="tec-campo">
          <label htmlFor="fp-desc">{rotuloObservaciones(tipo.codigo, tipo.exige_texto)}</label>
          <textarea id="fp-desc" className="campo-texto" rows={3} maxLength={maxDesc} value={descripcion} onChange={(e) => setDescripcion(e.target.value)} disabled={bloqueado} />
          <span className="campo-contador">{descripcion.length.toLocaleString("es-CO")} de {maxDesc.toLocaleString("es-CO")}</span>
        </div>

        {/* Fotos */}
        <div className="tec-campo">
          <span className="campo-etiqueta">Fotos <small>(máximo {megas(def.limites.max_bytes_foto)} cada una)</small></span>
          <span className={`campo-contador-fotos${contadorOk ? " campo-contador-ok" : ""}`} aria-live="polite">Fotos: {contador}</span>
          {/* Investigación y Análisis (23-nov): con un mínimo de 0 fotos (Investigación de ubicación) el formulario se envía sin cámara; el aviso solo bloquea si hay mínimo */}
          {!camaraDisponible() && flexible && <p className="campo-sub" role="status">Este navegador no permite usar la cámara desde la página: adjunte las fotos desde la galería o desde un archivo.</p>}
          {!camaraDisponible() && !flexible && (minimo > 0
            ? <p className="campo-error" role="alert">Este navegador no permite usar la cámara desde la página, y sin las fotos no se puede enviar. Use Safari en iPhone o Chrome en Android, actualizado, y abra el geoportal desde su dirección oficial (https).</p>
            : <p className="campo-sub" role="status">Este navegador no permite usar la cámara desde la página. Las fotos de este formato son opcionales: puede enviarlo sin ellas.</p>)}
          <div className="campo-fotos">
            {etiquetas.map((e) => {
              const f = porEtiqueta[e.codigo] ?? null;
              const requerida = inefectivo ? e.soporte_inefectiva && !etiquetas.some((x) => x.soporte_inefectiva && porEtiqueta[x.codigo]) : e.obligatoria;
              return (
                <div key={e.codigo} className={`campo-foto${inefectivo && e.soporte_inefectiva ? " campo-foto-soporte" : ""}`}>
                  <span className="campo-foto-n">{e.nombre}{requerida ? " (obligatoria)" : " (opcional)"}{inefectivo && e.soporte_inefectiva ? " · soporte de la visita inefectiva" : ""}</span>
                  {f ? (
                    <>
                      <img src={f.url} alt={`Foto: ${e.nombre}`} className="campo-foto-img" />
                      <MarcaOrigen origen={f.origen} />
                      {!fotosFijas && (
                        <div className="campo-foto-acc">
                          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => setCamaraEn({ tipo: "etiqueta", codigo: e.codigo, nombre: e.nombre })} disabled={!camaraDisponible()}>Repetir</button>
                          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => quitarEtiqueta(e.codigo)}>Quitar</button>
                        </div>
                      )}
                    </>
                  ) : (
                    <>
                      <button type="button" className="tec-boton campo-boton-foto" onClick={() => setCamaraEn({ tipo: "etiqueta", codigo: e.codigo, nombre: e.nombre })} disabled={fotosFijas || !camaraDisponible() || nFotos >= maximo}><IconoCamara />Tomar foto</button>
                      {flexible && <BotonesAdjuntar rotulo={e.nombre} maxBytes={def.limites.max_bytes_foto} ladoMayor={ladoPara(e.codigo, e.nombre)} deshabilitado={fotosFijas || nFotos >= maximo}
                        onFoto={(blob, o) => guardarFoto({ tipo: "etiqueta", codigo: e.codigo, nombre: e.nombre }, blob, o)} />}
                    </>
                  )}
                </div>
              );
            })}
            {adicionales.map((f, i) => (
              <div key={f.url} className="campo-foto">
                <span className="campo-foto-n">{usaEtiquetas ? `Foto adicional ${i + 1}` : `Foto ${i + 1}`}</span>
                <img src={f.url} alt={`Foto adicional ${i + 1}`} className="campo-foto-img" />
                <MarcaOrigen origen={f.origen} />
                {!fotosFijas && (
                  <div className="campo-foto-acc">
                    <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => setCamaraEn({ tipo: "adicional", indice: i, nombre: `Foto adicional ${i + 1}` })} disabled={!camaraDisponible()}>Repetir</button>
                    <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => quitarAdicional(i)}>Quitar</button>
                  </div>
                )}
              </div>
            ))}
          </div>
          {(usaEtiquetas || adicionales.length === 0) && (
            <button type="button" className="tec-boton-sec" onClick={() => setCamaraEn({ tipo: "adicional", indice: null, nombre: usaEtiquetas ? "Foto adicional" : `Foto ${adicionales.length + 1}` })} disabled={!puedeMas || !camaraDisponible()}>
              <IconoCamara />{usaEtiquetas ? "Agregar foto adicional" : "Tomar foto"}
            </button>
          )}
          {!usaEtiquetas && adicionales.length > 0 && (
            <button type="button" className="tec-boton-sec" onClick={() => setCamaraEn({ tipo: "adicional", indice: null, nombre: `Foto ${adicionales.length + 1}` })} disabled={!puedeMas || !camaraDisponible()}><IconoCamara />Agregar otra foto</button>
          )}
          {flexible && <BotonesAdjuntar rotulo={usaEtiquetas ? "Foto adicional" : `Foto ${adicionales.length + 1}`} maxBytes={def.limites.max_bytes_foto} deshabilitado={!puedeMas}
            onFoto={(blob, o) => guardarFoto({ tipo: "adicional", indice: null, nombre: "Foto adicional" }, blob, o)} />}
          {preparada && fase !== "guardado" && <p className="campo-sub">Las fotos y el resultado ya están reservados para este envío; no se pueden cambiar hasta enviarlo.</p>}
          <p className="campo-sub">{flexible ? "Las fotos (de la cámara o adjuntadas) quedan solo en la memoria de esta pantalla: no se guardan en el celular. Las adjuntadas quedan marcadas en el reporte."
                                             : "Las fotos se toman con la cámara y quedan solo en la memoria de esta pantalla: no se guardan en el celular ni en la galería."}</p>
        </div>

        {conDireccionTerreno ? <PanelDireccionTerreno estado={dir} onCambio={setDir} deshabilitado={bloqueado} />
          : conDireccion && <PanelDireccion estado={dir} onCambio={setDir} deshabilitado={bloqueado} />}
        {flexible && <PanelXY estado={xy} onCambio={setXy} fix={fix} zona={def.zona} deshabilitado={bloqueado} />}

        <SeccionConstancia config={cons.config} valor={cons.valor} onCambio={cons.setValor} bloqueado={bloqueado} />
        {reglas ? <FirmasRegistro reglas={reglas} valor={firmas} onCambio={setFirmas} fuente={fuente} deshabilitado={bloqueado} nombreOperario={correo} /> : null}

        {/* Automáticos */}
        <dl className="campo-auto">
          <div>
            <dt>{xyListo ? "Ubicación del dispositivo" : "Ubicación"}</dt>
            <dd>
              {fix ? `${decimal(fix.lat, 5)}, ${decimal(fix.lon, 5)} (${metros(fix.precision_m)})` : ubic.estado === "buscando" ? "Buscando…" : "No disponible"}
              <button type="button" className="campo-enlace" onClick={ubic.actualizar} disabled={bloqueado}>Actualizar ubicación</button>
            </dd>
          </div>
          <div><dt>Fecha y hora</dt><dd>{fechaHora(ahora)} <small>(la oficial será la del servidor)</small></dd></div>
          <div><dt>Usuario</dt><dd>{correo}</dd></div>
        </dl>
        {ubic.mensaje && <p className="campo-error" role="alert">{ubic.mensaje}</p>}
        {precisionMala && <p className="campo-nota" role="note">La ubicación es poco precisa (más de {UMBRAL_PRECISION_MALA_M} m). Espere unos segundos o salga a cielo abierto y pulse «Actualizar ubicación».{inefectivo ? " En una visita inefectiva la precisión queda registrada como prueba." : " Puede enviar igualmente."}</p>}

        {faltasFormato.length > 0 && fase === "editando" && hayInterac && <ul className="campo-faltas">{faltasFormato.map((m) => <li key={m}>{m}</li>)}</ul>}
        {cons.faltas.length > 0 && fase === "editando" && <ul className="campo-faltas">{cons.faltas.map((m) => <li key={m}>{m}</li>)}</ul>}
        {faltasDoc.length > 0 && fase === "editando" && <ul className="campo-faltas" data-testid="faltas-firmas">{faltasDoc.map((m) => <li key={m}>{m}</li>)}</ul>}
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
        <PanelCamara rotulo={camaraEn.nombre} maxBytes={def.limites.max_bytes_foto} sello={lineasSello}
          // las fotos del medidor (y de su lectura, serial o sellos) y de placas van a 2.048 px para que se lean; las demás, a 1.600
          ladoMayor={camaraEn.tipo === "etiqueta" ? ladoPara(camaraEn.codigo, camaraEn.nombre) : LADO_MAYOR_PX}
          onFoto={(f) => { guardarFoto(camaraEn, f.blob); setCamaraEn(null); }} onCerrar={() => setCamaraEn(null)} />
      )}
    </div>
  );
}

// ============ Un campo propio, según su tipo de dato ============
function CampoPropio({ c, valor, error, obligatorio, deshabilitado, onCambio }: {
  c: CampoDef; valor: string | string[] | undefined; error?: string; obligatorio: boolean; deshabilitado: boolean; onCambio: (v: string | string[]) => void;
}) {
  const id = `fp-${c.codigo}`;
  const texto = typeof valor === "string" ? valor : "";
  const arreglo = Array.isArray(valor) ? valor : [];
  const opciones = (c.opciones ?? []).filter((o) => o.activo !== false);
  const rango = c.minimo !== undefined && c.maximo !== undefined ? `de ${c.minimo.toLocaleString("es-CO")} a ${c.maximo.toLocaleString("es-CO")}` : c.minimo !== undefined ? `mínimo ${c.minimo.toLocaleString("es-CO")}` : c.maximo !== undefined && (c.tipo_dato === "entero" || c.tipo_dato === "decimal") ? `máximo ${c.maximo.toLocaleString("es-CO")}` : "";
  const nota = [c.unidad ? `Unidad: ${c.unidad}` : "", rango, c.ayuda ?? ""].filter(Boolean).join(" · ");
  const rotulo = (
    <>{c.nombre}{c.unidad && (c.tipo_dato === "entero" || c.tipo_dato === "decimal") ? ` (${c.unidad})` : ""}{obligatorio ? " (obligatorio)" : " (opcional)"}
      {c.sensible && <span className="campo-sensible">dato sensible</span>}</>
  );
  const invalido = !!error;
  let control: JSX.Element;
  switch (c.tipo_dato) {
    case "si_no":
      control = (
        <select id={id} value={texto} onChange={(e) => onCambio(e.target.value)} disabled={deshabilitado} aria-invalid={invalido}>
          <option value="">Sin responder</option><option value="si">Sí</option><option value="no">No</option>
        </select>
      );
      break;
    case "opcion":
      control = (
        <select id={id} value={texto} onChange={(e) => onCambio(e.target.value)} disabled={deshabilitado} aria-invalid={invalido}>
          <option value="">Elija…</option>
          {opciones.map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}
        </select>
      );
      break;
    case "opciones":
      control = (
        <div className="campo-opciones" role="group" aria-labelledby={`${id}-rot`}>
          {opciones.map((o) => (
            <label key={o.codigo}>
              <input type="checkbox" checked={arreglo.includes(o.codigo)} disabled={deshabilitado}
                onChange={(e) => onCambio(e.target.checked ? [...arreglo, o.codigo] : arreglo.filter((x) => x !== o.codigo))} />{o.nombre}
            </label>
          ))}
        </div>
      );
      break;
    case "dia_hora":
      control = <input id={id} type="datetime-local" value={texto} onChange={(e) => onCambio(e.target.value)} disabled={deshabilitado} aria-invalid={invalido} />;
      break;
    case "entero":
    case "decimal":
      control = <input id={id} type="text" inputMode={c.tipo_dato === "entero" ? "numeric" : "decimal"} autoComplete="off" value={texto} onChange={(e) => onCambio(e.target.value)} disabled={deshabilitado} aria-invalid={invalido} />;
      break;
    default:
      control = <input id={id} type="text" autoComplete="off" maxLength={c.maximo ?? 300} value={texto} onChange={(e) => onCambio(e.target.value)} disabled={deshabilitado} aria-invalid={invalido} />;
  }
  return (
    <div className="tec-campo campo-propio">
      {c.tipo_dato === "opciones" ? <span className="campo-etiqueta" id={`${id}-rot`}>{rotulo}</span> : <label htmlFor={id}>{rotulo}</label>}
      {control}
      {nota && <span className="campo-unidad">{nota}</span>}
      {error && (texto !== "" || arreglo.length > 0) ? <span className="campo-error" role="alert">{error}</span> : null}
    </div>
  );
}

// ============ Cámara dentro del formulario (misma de ReporteGeneral; allí no se exporta y ese archivo no se toca) ============
function PanelCamara({ rotulo, maxBytes, sello, onFoto, onCerrar, ladoMayor }: {
  rotulo: string; maxBytes: number; sello: () => string[]; onFoto: (f: { blob: Blob }) => void; onCerrar: () => void; ladoMayor: number;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const flujo = useRef<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lista, setLista] = useState(false);
  const [procesando, setProcesando] = useState(false);

  useEffect(() => {
    let vivo = true;
    abrirCamara(ladoMayor)
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
      const f = await capturarFoto(v, sello(), maxBytes, ladoMayor);
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
      {error ? <div className="campo-camara-error"><p role="alert">{error}</p></div> : <video ref={videoRef} className="campo-video" autoPlay playsInline muted onLoadedMetadata={() => setLista(true)} />}
      <div className="campo-camara-acc">
        <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        {!error && <button type="button" className="tec-boton campo-capturar" onClick={() => void capturar()} disabled={!lista || procesando}>{procesando ? "Procesando…" : "Tomar foto"}</button>}
      </div>
    </div>
  );
}

/** D13 (Comercial 21-nov): si el formato trae «¿Da lugar a otras actividades?» (da_lugar), «¿Se requiere cambio de medidor?» (req_cambio_medidor) no se pinta ni se valida: se llena al
 *  enviar con cambio_medidor ∈ da_lugar (la base rechaza el registro si no coinciden). Si el formato no trae da_lugar (servidor anterior), se deja como estaba. */
function sinReqCambio(t: TipoFormato): TipoFormato {
  const cs = t.campos ?? [];
  if (!cs.some((c) => c.codigo === "da_lugar" && c.activo !== false) || !cs.some((c) => c.codigo === "req_cambio_medidor")) return t;
  return { ...t, campos: cs.filter((c) => c.codigo !== "req_cambio_medidor") };
}
