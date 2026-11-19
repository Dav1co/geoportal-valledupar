import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import "./acta.css";
import { avisoDeError, ErrorCampo } from "../apiCampo";
import { fechaHoraSello, megas, metros } from "../formato";
import { useUbicacion } from "../ubicacion";
import { apiActa } from "./apiActa";
import { almacenActa, useAlmacenActa, type Entrada, type FotoLocal } from "./almacenActa";
import { CamaraActa } from "./CamaraActa";
import { IdentificarPredio } from "./IdentificarPredio";
import { PanelCancelarActa } from "./PanelCancelarActa";
import type { Destino, MotivoCancelacion } from "../../components/ConfirmarCancelar";
import { SeccionConstancia } from "../constancia/SeccionConstancia";
import { useConstancia } from "../constancia/useConstancia";
import * as L from "./logica";
import type { BorradorActa, ConfirmacionActa, FormularioActa as Catalogo, Precarga } from "./tipos";
import { fechaBorrador, useBorradorCampo, type ArchivoBorrador } from "../../tecnica/borradorCampo";

// Formulario del acta, por secciones y dibujado desde el catálogo que entrega la Edge (hallazgos, calidades, estados, diámetros, acciones y tipos de foto: nada escrito a mano aquí).
// «Registrar» (no «firmar»): una transacción en el servidor. Las firmas son HECHOS DECLARADOS que constan en el acta física; aquí no hay firma en pantalla, PDF ni imágenes de firma.
// Envío: preparar_subida (todas las fotos de una vez) → subida directa de cada foto → registrar con el MISMO acta_id (repetirlo no duplica ni gasta otro consecutivo).
// Una vez preparada la subida, las fotos quedan fijas (cada ruta corresponde a un orden y un tipo). MALA SEÑAL: todavía no hay modo sin conexión; lo escrito y las fotos siguen en pantalla
// (y en el almacén en memoria) para reintentar.
// BORRADOR LOCAL (19-nov-2026, decisión de David): lo escrito, lo elegido y las fotos del hallazgo se guardan además en IndexedDB de este celular (tecnica/borradorCampo.ts), por persona
// y por 24 horas, para que una recarga no los pierda. Al retomar el registro desde «Mis actas» se pregunta «¿Continuar o descartar?». Se borra al registrar, al descartar y al cancelar.
// SIN datos personales del suscriptor: NO se guardan el nombre de quien atendió, el del testigo, las fotos del acta física firmada (traen nombres y firmas) ni la constancia por correo.

type Fase = "editando" | "confirmando" | "enviando" | "error" | "guardado";
type DestinoFoto = { tipo: string; papel: boolean } | null;
/** Lo que va al borrador local: el acta sin los nombres de las personas, y la precarga del catastro (dirección, barrio, estrato y uso del predio). */
type DatosBorrador = { borrador: Omit<BorradorActa, "atNombre" | "testigo"> | null; precarga: Precarga | null };
const sinNombres = (b: BorradorActa): Omit<BorradorActa, "atNombre" | "testigo"> => { const { atNombre: _a, testigo: _t, ...resto } = b; void _a; void _t; return resto; };

export function FormularioActa({ cat, actaId, correo, onVolver, onRegistrado, motivos = null, destinos, onIrA }: {
  cat: Catalogo; actaId: string; correo: string; onVolver: () => void; onRegistrado: (c: ConfirmacionActa) => void;
  /** Cancelar la apertura: motivos del catálogo y destinos de «me equivoqué de formulario». */
  motivos?: MotivoCancelacion[] | null; destinos?: Destino[]; onIrA?: (destino: string, contrato: string) => void;
}) {
  const { entradas } = useAlmacenActa();
  const entrada: Entrada | undefined = entradas[actaId];
  const ubic = useUbicacion();
  const fix = ubic.fix;
  const [fase, setFase] = useState<Fase>("editando");
  const [errorEnvio, setErrorEnvio] = useState<ErrorCampo | null>(null);
  const [camaraEn, setCamaraEn] = useState<DestinoFoto>(null);
  const [cancelando, setCancelando] = useState(false);
  const [ahora, setAhora] = useState(() => new Date());
  const enviando = useRef(false);
  const cons = useConstancia("acta_inspeccion");     // sección opcional «Constancia por correo»: solo si el documento está habilitado

  useEffect(() => { const t = setInterval(() => setAhora(new Date()), 30000); return () => clearInterval(t); }, []);
  const hayFotos = (entrada?.fotos.length ?? 0) > 0;

  // ---------- borrador local ----------
  const tipoPapelB = cat.tipos_foto.find((t) => t.acta_fisica)?.codigo ?? "acta_fisica";
  const datosBorrador: DatosBorrador = { borrador: entrada ? sinNombres(entrada.borrador) : null, precarga: entrada?.precarga ?? null };
  const fotosEntrada = entrada?.fotos;
  const archivosBorrador = useMemo<ArchivoBorrador[]>(() => (fotosEntrada ?? []).filter((f) => f.tipo !== tipoPapelB).map((f) => ({ blob: f.blob, etiqueta: f.tipo })), [fotosEntrada, tipoPapelB]);
  // Se pregunta solo si el registro llega vacío (recién retomado desde «Mis actas» tras una recarga); si ya trae algo en pantalla, eso ES el borrador.
  const llegaVacio = !!entrada && entrada.fotos.length === 0 && JSON.stringify(entrada.borrador) === JSON.stringify({ ...L.borradorVacio("con_contrato"), fechaFisica: entrada.borrador.fechaFisica });
  const borrador = useBorradorCampo<DatosBorrador>(`acta:${actaId}`, correo, datosBorrador, archivosBorrador, fase === "guardado" || !entrada, undefined, { sinOferta: !llegaVacio, apagado: !entrada });
  const [recuperado, setRecuperado] = useState(false);
  function continuarBorrador() {
    const o = borrador.oferta; if (!o?.datos.borrador) { borrador.resolver(false); return; }
    const d = o.datos.borrador;
    const fotos: FotoLocal[] = o.archivos.filter((a) => a.etiqueta !== tipoPapelB && cat.tipos_foto.some((t) => t.codigo === a.etiqueta))
      .map((a) => ({ id: Math.random().toString(36).slice(2), tipo: a.etiqueta, blob: a.blob, url: URL.createObjectURL(a.blob), subida: false }));
    almacenActa.parchar(actaId, (x) => ({ ...x, prep: null, precarga: o.datos.precarga ?? null, fotos,
      borrador: { ...L.borradorVacio(d.modo === "sin_contrato" ? "sin_contrato" : "con_contrato"), ...d, atNombre: "", testigo: "" } }));
    setRecuperado(true); borrador.resolver(true);
  }
  useEffect(() => {
    if (!hayFotos || fase === "guardado") return;
    const f = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ""; };
    window.addEventListener("beforeunload", f);
    return () => window.removeEventListener("beforeunload", f);
  }, [hayFotos, fase]);

  const lineasSello = useCallback((): string[] => [
    `${fechaHoraSello(new Date())} · hora del celular`,
    fix ? `${fix.lat.toFixed(5)}, ${fix.lon.toFixed(5)} · ${metros(fix.precision_m)}` : "ubicación no disponible",
  ], [fix]);

  if (!entrada) return <div className="tec-pagina"><section className="tec-tarjeta"><p>Este registro ya no está en pantalla. Vuelva a «Mis actas».</p><button type="button" className="tec-boton" onClick={onVolver}>Volver a Mis actas</button></section></div>;

  const b = entrada.borrador;
  const fotosFijas = entrada.prep !== null;                                    // con la subida preparada no se cambian las fotos
  const set = (c: Partial<BorradorActa>) => almacenActa.parchar(actaId, (x) => ({ ...x, borrador: { ...x.borrador, ...c } }));
  const setHallazgo = (codigo: string) => almacenActa.parchar(actaId, (x) => ({ ...x, borrador: L.depurarAcciones(L.alternarHallazgo(x.borrador, cat, codigo), cat) }));
  const faltas = [...L.faltas(b, entrada.fotos, cat, ahora), ...cons.faltas];
  const sin = L.sinIrregularidad(b, cat);
  const cont = L.contadores(b, entrada.fotos, cat);
  const tiposHallazgo = cat.tipos_foto.filter((t) => !t.acta_fisica);
  const tipoPapel = cat.tipos_foto.find((t) => t.acta_fisica)?.codigo ?? "acta_fisica";
  const bloqueado = fase === "enviando" || fase === "guardado";
  const aviso = errorEnvio ? avisoDeError(errorEnvio) : null;
  const vencido = new Date(entrada.vence_en).getTime() < ahora.getTime();

  function guardarFoto(d: NonNullable<DestinoFoto>, blob: Blob) {
    const nueva: FotoLocal = { id: Math.random().toString(36).slice(2), tipo: d.tipo, blob, url: URL.createObjectURL(blob), subida: false };
    almacenActa.parchar(actaId, (x) => ({ ...x, fotos: [...x.fotos, nueva] }));
  }
  function quitarFoto(id: string) {
    almacenActa.parchar(actaId, (x) => { const f = x.fotos.find((y) => y.id === id); if (f) URL.revokeObjectURL(f.url); return { ...x, fotos: x.fotos.filter((y) => y.id !== id) }; });
  }

  async function enviar() {
    if (enviando.current || faltas.length > 0) return;
    enviando.current = true;
    setFase("enviando"); setErrorEnvio(null);
    try {
      const actual = almacenActa.obtener(actaId)!;
      const ordenadas = L.ordenarFotos(actual.fotos, cat);
      const contenido = L.construirContenido(actual.borrador, actual.fotos, cat);
      let conf: ConfirmacionActa | null = null;
      if (ordenadas.length > 0) {
        let p = actual.prep;
        if (!p) {
          try {
            p = await apiActa.prepararSubida(actaId, ordenadas.map((f) => ({ orden: f.orden, tipo: f.tipo })));
            const pp = p;
            almacenActa.parchar(actaId, (x) => ({ ...x, prep: pp }));
          } catch (e) {
            // Si el envío anterior sí llegó y solo se perdió la respuesta, preparar falla («ya fue registrada»): registrar con el mismo acta_id responde «repetido» con el mismo consecutivo.
            if (e instanceof ErrorCampo && e.tipo === "validacion") {
              try { conf = await apiActa.registrar(actaId, contenido, cons.bloque); } catch { throw e; }
            } else throw e;
          }
        }
        if (!conf && p) {
          for (const f of ordenadas) {
            const vigente = almacenActa.obtener(actaId)!.fotos.find((x) => x.id === f.id)!;
            if (vigente.subida) continue;
            const destino = p.fotos.find((x) => x.orden === f.orden);
            if (!destino) throw new ErrorCampo("servidor", "La preparación de las fotos llegó incompleta. Intente de nuevo.", 0);
            await apiActa.subirFoto(destino.url_subida, f.blob);
            almacenActa.parchar(actaId, (x) => ({ ...x, fotos: x.fotos.map((y) => (y.id === f.id ? { ...y, subida: true } : y)) }));
          }
        }
      }
      if (!conf) conf = await apiActa.registrar(actaId, contenido, cons.bloque);
      borrador.terminar();      // registrado: el borrador de este celular ya no hace falta
      setFase("guardado");
      onRegistrado(conf);
    } catch (e) {
      const err = e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo completar el registro.", 0);
      if (err.tipo === "subida_vencida") {
        // La URL firmada venció: se pide una preparación nueva en el siguiente intento (las fotos que ya subieron responden 409 y cuentan como subidas).
        almacenActa.parchar(actaId, (x) => ({ ...x, prep: null }));
      }
      setErrorEnvio(err);
      setFase("error");
    } finally {
      enviando.current = false;
    }
  }

  if (borrador.leyendo) return <div className="tec-pagina"><section className="tec-tarjeta"><p role="status">Cargando…</p></section></div>;
  if (borrador.oferta) {
    const nf = borrador.oferta.archivos.length;
    return (
      <div className="tec-pagina campo-pagina">
        <section className="tec-tarjeta" role="group" aria-label="Borrador guardado" data-testid="borrador-oferta">
          <h1>Reportar posible pérdida</h1>
          <p className="acta-consecutivo-chico">Consecutivo <strong>{entrada.consecutivo}</strong></p>
          <p>Tiene un borrador del {fechaBorrador(borrador.oferta.guardado)}{nf ? ` (con ${nf} ${nf === 1 ? "foto" : "fotos"})` : ""}. ¿Continuar o descartar?</p>
          <button type="button" className="tec-boton campo-enviar" onClick={continuarBorrador}>Continuar</button>
          <button type="button" className="tec-boton-sec" onClick={() => borrador.resolver(false)}>Descartar</button>
        </section>
      </div>
    );
  }

  // ======================= Resumen y confirmación =======================
  if (fase === "confirmando" || fase === "enviando" || fase === "error") {
    return (
      <div className="tec-pagina campo-pagina">
        <section className="tec-tarjeta">
          <h1>Confirme el registro</h1>
          <p className="acta-consecutivo-chico">Consecutivo <strong>{entrada.consecutivo}</strong></p>
          <p className="campo-nota" role="note">{L.TEXTO_PAPEL}</p>
          <ul className="acta-resumen">
            {resumen(b, cat, cont, entrada).map((l) => <li key={l}>{l}</li>)}
          </ul>
          {b.numeroFisico.trim() === "" && <p className="campo-nota" role="alert">No indicó el número del acta física: el consecutivo del sistema ({entrada.consecutivo}) es el que debe quedar escrito en el papel.</p>}
          {b.papelPendiente && <p className="campo-nota" role="alert">Quedó marcado «papel pendiente»: adjunte la foto del acta física firmada desde «Mis actas» en cuanto la tenga.</p>}
          {errorEnvio && aviso && <p className="campo-error" role="alert">{errorEnvio.tipo === "validacion" ? errorEnvio.message : aviso.texto}</p>}
          {cons.bloque && <p className="campo-nota" role="note">Se enviará una constancia de este registro a {cons.bloque.correo_titular}, con su autorización.</p>}
          <p className="campo-sub">Después de registrar no se edita: cualquier corrección la hace la supervisión.</p>
          <button type="button" className="tec-boton campo-enviar" onClick={() => void enviar()} disabled={fase === "enviando" || (fase === "error" && aviso !== null && !aviso.reintentable)}>
            {fase === "enviando" ? "Registrando…" : fase === "error" ? "Reintentar" : "Confirmar y registrar"}
          </button>
          {fase !== "enviando" && <button type="button" className="tec-boton-sec" onClick={() => { setErrorEnvio(null); setFase("editando"); }}>Volver a editar</button>}
          {fase !== "enviando" && <button type="button" className="btn-cancelar" onClick={() => setCancelando(true)}>Cancelar</button>}
          {cancelando && (
            <PanelCancelarActa correo={correo} actaId={actaId} consecutivo={entrada.consecutivo} contrato={b.modo === "con_contrato" ? b.contrato : ""} motivos={motivos} destinos={destinos} onIrA={onIrA}
              onHecho={() => { borrador.terminar(); onVolver(); }} onSeguir={() => setCancelando(false)} />
          )}
        </section>
      </div>
    );
  }

  // ======================= Formulario =======================
  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta acta-form">
        <div className="campo-cab">
          <h1>Reportar posible pérdida</h1>
          <button type="button" className="tec-boton-sec" onClick={onVolver}>Mis actas</button>
          <button type="button" className="btn-cancelar" onClick={() => setCancelando(true)} disabled={bloqueado}>Cancelar</button>
        </div>
        {cancelando && (
          <PanelCancelarActa correo={correo} actaId={actaId} consecutivo={entrada.consecutivo} contrato={b.modo === "con_contrato" ? b.contrato : ""} motivos={motivos} destinos={destinos} onIrA={onIrA}
            onHecho={() => { borrador.terminar(); onVolver(); }} onSeguir={() => setCancelando(false)} />
        )}
        <p className="acta-consecutivo" aria-label="Consecutivo del registro">{entrada.consecutivo}</p>
        {recuperado && <p className="campo-nota" role="status" data-testid="borrador-recuperado">Se recuperó el borrador. Por protección de datos no se guardan el nombre de quien atendió, el del testigo ni las fotos del acta física: vuelva a ponerlos.</p>}
        <p className="campo-nota" role="note"><strong>Escriba este consecutivo en el acta física.</strong> {L.TEXTO_PAPEL}</p>
        <p className="campo-sub">{cat.aviso_registro}</p>
        <p className="campo-sub">Todavía no funciona sin conexión: si se pierde la señal, lo escrito y las fotos siguen en pantalla para reintentar. Si la página se recarga, lo escrito y las fotos del hallazgo quedan en el borrador de este celular; los nombres y las fotos del acta física no.</p>
        {entrada.aviso_zona && <p className="campo-nota" role="note">La ubicación de la apertura quedó fuera de la zona de operación; se registra con esa marca.</p>}
        {vencido && <p className="campo-error" role="alert">Este registro caducó ({L.fechaCO(entrada.vence_en.slice(0, 10))}): ya no se puede registrar. Abra uno nuevo desde «Mis actas».</p>}

        <Seccion titulo="1. Predio">
          <IdentificarPredio
            modo={b.modo} contrato={b.contrato} bloqueado={bloqueado}
            onModo={(modo) => set({ modo, contrato: modo === "sin_contrato" ? "" : b.contrato })}
            onContrato={(contrato) => set({ contrato })}
            precarga={entrada.precarga}
            onPrecarga={(p) => { almacenActa.parchar(actaId, (x) => ({ ...x, precarga: p, borrador: L.conPrecarga(x.borrador, p) })); }}
            opcional
          />
          <Campo etiqueta="Dirección" valor={b.direccion} onCambio={(v) => set({ direccion: v })} bloqueado={bloqueado} max={300} />
          <Campo etiqueta="Barrio" valor={b.barrio} onCambio={(v) => set({ barrio: v })} bloqueado={bloqueado} max={120}
            ayuda={entrada.precarga && entrada.precarga.barrio_en_lista === false ? "El barrio del catastro no está en la lista de barrios; se registra con esa marca." : "Escríbalo como lo conoce. Si no está en la lista de barrios, se registra con esa marca."} />
          <Campo etiqueta="Estrato" valor={b.estrato} onCambio={(v) => set({ estrato: v })} bloqueado={bloqueado} max={20}
            ayuda={b.estrato.trim() !== "" && L.etiquetaEstrato(b.estrato).includes("no estándar") ? "Código no estándar: se registra tal cual, sin interpretarlo." : undefined} />
          <Campo etiqueta="Uso" valor={b.uso} onCambio={(v) => set({ uso: v })} bloqueado={bloqueado} max={80} />
          <Campo etiqueta="Referencia de ubicación (opcional)" valor={b.referencia} onCambio={(v) => set({ referencia: v })} bloqueado={bloqueado} max={300} />
        </Seccion>

        <Seccion titulo="2. Medidor y acometida">
          <SiNo etiqueta="¿El predio tiene medidor?" valor={b.tieneMedidor} onCambio={(v) => set({ tieneMedidor: v })} bloqueado={bloqueado} />
          {b.tieneMedidor === true && <>
            <Campo etiqueta="Serie del medidor (opcional)" valor={b.medidorSerie} onCambio={(v) => set({ medidorSerie: v })} bloqueado={bloqueado} max={40} />
            <Campo etiqueta="Marca (opcional)" valor={b.marca} onCambio={(v) => set({ marca: v })} bloqueado={bloqueado} max={60} />
            <Campo etiqueta="Lectura en m³ (opcional)" valor={b.lectura} onCambio={(v) => set({ lectura: v })} bloqueado={bloqueado} max={14} modo="decimal" />
            <Selector etiqueta="Estado del medidor" valor={b.estadoMedidor} onCambio={(v) => set({ estadoMedidor: v })} opciones={cat.estados_medidor} bloqueado={bloqueado} />
          </>}
          <Selector etiqueta="Estado de los sellos (opcional)" valor={b.estadoSellos} onCambio={(v) => set({ estadoSellos: v })} opciones={cat.estados_sellos} bloqueado={bloqueado} />
          <Campo etiqueta="Serie de los sellos (opcional)" valor={b.serieSellos} onCambio={(v) => set({ serieSellos: v })} bloqueado={bloqueado} max={60} />
          <Selector etiqueta="Diámetro de la acometida (opcional)" valor={b.diametro} onCambio={(v) => set({ diametro: v })} opciones={cat.diametros} bloqueado={bloqueado}
            ayuda="Lista en revisión por el área técnica. Si no está el diámetro, elija «Otro» y descríbalo en las observaciones." />
        </Seccion>

        <Seccion titulo="3. Hallazgos y acciones">
          <p className="campo-sub">Lo hallado es una presunción hasta que la supervisión lo confirme.</p>
          {cat.tipos_hallazgo.map((t) => {
            const marcado = b.hallazgos.find((h) => h.codigo === t.codigo);
            return (
              <div key={t.codigo}>
                <label className="campo-check">
                  <input type="checkbox" checked={!!marcado} onChange={() => setHallazgo(t.codigo)} disabled={bloqueado} />
                  <span>{t.nombre}{t.nota && <small>{t.nota}</small>}</span>
                </label>
                {marcado && t.exige_texto && <Campo etiqueta={`Describa «${t.nombre}»`} valor={marcado.texto} max={300} bloqueado={bloqueado}
                  onCambio={(v) => set({ hallazgos: b.hallazgos.map((h) => (h.codigo === t.codigo ? { ...h, texto: v } : h)) })} />}
              </div>
            );
          })}
          {!sin && <Area etiqueta="Descripción de los hallazgos (mínimo 10 caracteres)" valor={b.descripcion} max={4000} bloqueado={bloqueado} onCambio={(v) => set({ descripcion: v })} />}
          {!sin && b.hallazgos.length > 0 && <>
            <h3 className="acta-sub">Acciones correctivas ejecutadas</h3>
            {cat.acciones.filter((a) => L.accionDisponible(a, b, cat)).map((a) => {
              const marcada = b.acciones.find((x) => x.codigo === a.codigo);
              return (
                <div key={a.codigo}>
                  <label className="campo-check">
                    <input type="checkbox" checked={!!marcada} disabled={bloqueado}
                      onChange={() => set({ acciones: marcada ? b.acciones.filter((x) => x.codigo !== a.codigo) : [...b.acciones, { codigo: a.codigo, detalle: {} }] })} />
                    <span>{a.nombre}</span>
                  </label>
                  {marcada && a.campos.map((c) => (
                    <Campo key={c.clave} etiqueta={`${c.etiqueta}${c.obligatorio ? "" : " (opcional)"}`} valor={marcada.detalle[c.clave] ?? ""} bloqueado={bloqueado} max={300}
                      tipo={c.tipo === "hora" ? "time" : "text"} modo={c.tipo === "numero" ? "decimal" : undefined}
                      onCambio={(v) => set({ acciones: b.acciones.map((x) => (x.codigo === a.codigo ? { ...x, detalle: { ...x.detalle, [c.clave]: v } } : x)) })} />
                  ))}
                </div>
              );
            })}
          </>}
        </Seccion>

        <Seccion titulo="4. Atención de la visita y firmas (lo que consta en el acta física)">
          <p className="campo-nota" role="note">{L.TEXTO_PAPEL} Aquí solo se declara lo que ya consta en el papel; en esta pantalla nadie firma.</p>
          <SiNo etiqueta="¿Atendió alguien la visita?" valor={b.nadieAtendio === null ? null : !b.nadieAtendio} bloqueado={bloqueado}
            onCambio={(atendio) => set({ nadieAtendio: !atendio, ...(atendio ? {} : { atNombre: "", atCalidad: "", atCalidadTexto: "", firmoAtendiente: null, seNego: false }) })} />
          {b.nadieAtendio === false && <>
            <Campo etiqueta="Nombre de quien atendió" valor={b.atNombre} onCambio={(v) => set({ atNombre: v })} bloqueado={bloqueado} max={120} />
            <Selector etiqueta="En calidad de" valor={b.atCalidad} onCambio={(v) => set({ atCalidad: v })} opciones={cat.calidades_atendiente} bloqueado={bloqueado} />
            {cat.calidades_atendiente.find((c) => c.codigo === b.atCalidad)?.exige_texto && <Campo etiqueta="Describa la calidad" valor={b.atCalidadTexto} onCambio={(v) => set({ atCalidadTexto: v })} bloqueado={bloqueado} max={100} />}
            <SiNo etiqueta="¿Se le informaron sus derechos? (opcional)" valor={b.derechosInformados} onCambio={(v) => set({ derechosInformados: v })} bloqueado={bloqueado} />
            <fieldset className="acta-sino" disabled={bloqueado}>
              <legend className="campo-etiqueta">En el acta física, quien atendió…</legend>
              <label className="acta-radio"><input type="radio" name="firma-atendiente" checked={b.firmoAtendiente === true && b.seNego !== true} onChange={() => set({ firmoAtendiente: true, seNego: false })} /> <span>firmó</span></label>
              <label className="acta-radio"><input type="radio" name="firma-atendiente" checked={b.seNego === true} onChange={() => set({ firmoAtendiente: false, seNego: true })} /> <span>se negó a firmar</span></label>
            </fieldset>
          </>}
          {(b.nadieAtendio === true || b.seNego === true) && <Campo etiqueta={b.seNego ? "Nombre del testigo" : "Nombre del testigo (si lo hubo)"} valor={b.testigo} onCambio={(v) => set({ testigo: v })} bloqueado={bloqueado} max={120} />}
          <SiNo etiqueta="¿Firmó el operario en el acta física?" valor={b.firmoOperario} onCambio={(v) => set({ firmoOperario: v })} bloqueado={bloqueado} />
          <Area etiqueta={`Constancia del operario${b.nadieAtendio === true || b.seNego === true || b.firmoOperario === false ? " (obligatoria, mínimo 10 caracteres)" : " (opcional)"}`}
            valor={b.constancia} max={2000} bloqueado={bloqueado} onCambio={(v) => set({ constancia: v })} />
        </Seccion>

        <Seccion titulo="5. Fotos de la visita">
          <p className="campo-sub">Solo con la cámara. Mientras llena el registro, las fotos del hallazgo quedan en el borrador de este celular; se borran al registrar o al cancelar.</p>
          <p className="acta-contador" aria-live="polite">
            Hallazgo: <strong>{cont.hallazgo}</strong> de {cont.maxHallazgo} (mínimo {cont.minHallazgo}){cont.tiposFaltantes.length > 0 ? ` · falta: ${cont.tiposFaltantes.join(", ")}` : ""} · tope {megas(cat.limites.max_bytes_foto)} por foto
          </p>
          {fotosFijas && <p className="campo-sub">La subida ya se preparó: las fotos quedan fijas hasta registrar.</p>}
          <div className="acta-chips">
            {tiposHallazgo.map((t) => (
              <button key={t.codigo} type="button" className="tec-boton-sec acta-chip" onClick={() => setCamaraEn({ tipo: t.codigo, papel: false })}
                disabled={bloqueado || fotosFijas || cont.hallazgo >= cont.maxHallazgo}>
                + {t.nombre}{t.exigida_con_irregularidad && cont.conIrregularidad ? " *" : ""}
              </button>
            ))}
          </div>
          <Miniaturas fotos={entrada.fotos.filter((f) => f.tipo !== tipoPapel)} nombre={(t) => cat.tipos_foto.find((x) => x.codigo === t)?.nombre ?? t} onQuitar={quitarFoto} bloqueado={bloqueado || fotosFijas} />
        </Seccion>

        <Seccion titulo="6. Acta física firmada">
          <Campo etiqueta="Número del acta física (si el papel ya trae uno impreso)" valor={b.numeroFisico} onCambio={(v) => set({ numeroFisico: v })} bloqueado={bloqueado} max={30} />
          {b.numeroFisico.trim() === "" && <p className="campo-nota" role="note">Si el papel no trae número, el que cuenta es el consecutivo de este registro ({entrada.consecutivo}): escríbalo en el acta física. Un mismo número físico no se puede registrar en dos casos.</p>}
          <label className="campo-etiqueta" htmlFor="acta-fecha-fisica">Fecha del acta física <small>(hasta {cat.limites.max_dias_acta_fisica_atras} días atrás)</small></label>
          <input id="acta-fecha-fisica" className="acta-input" type="date" value={b.fechaFisica} disabled={bloqueado}
            min={L.sumarDias(L.hoyBogota(ahora), -cat.limites.max_dias_acta_fisica_atras)} max={L.hoyBogota(ahora)} onChange={(e) => set({ fechaFisica: e.target.value })}
            aria-invalid={L.validarFechaPapel(b.fechaFisica, ahora, cat.limites.max_dias_acta_fisica_atras) !== null} />
          {L.validarFechaPapel(b.fechaFisica, ahora, cat.limites.max_dias_acta_fisica_atras) && <span className="campo-error" role="alert">{L.validarFechaPapel(b.fechaFisica, ahora, cat.limites.max_dias_acta_fisica_atras)}</span>}
          <label className="campo-check">
            <input type="checkbox" checked={b.papelPendiente} disabled={bloqueado || fotosFijas || cont.papel > 0} onChange={(e) => set({ papelPendiente: e.target.checked })} />
            <span>Papel pendiente: todavía no tengo el acta física firmada para fotografiarla<small>La foto se adjunta después, desde «Mis actas». Hasta entonces la supervisión verá una alerta de «registro sin foto del acta física».</small></span>
          </label>
          {!b.papelPendiente && <>
            <p className="acta-contador" aria-live="polite">Páginas del papel: <strong>{cont.papel}</strong> de {cont.maxPapel} (mínimo {cont.minPapel}) · tope {megas(cat.limites.max_bytes_foto_acta_fisica)} por foto</p>
            <button type="button" className="tec-boton campo-boton-foto" onClick={() => setCamaraEn({ tipo: tipoPapel, papel: true })} disabled={bloqueado || fotosFijas || cont.papel >= cont.maxPapel}>
              Fotografiar el acta física firmada
            </button>
            <Miniaturas fotos={entrada.fotos.filter((f) => f.tipo === tipoPapel)} nombre={() => "Acta física"} onQuitar={quitarFoto} bloqueado={bloqueado || fotosFijas} />
          </>}
        </Seccion>

        <Seccion titulo="7. Observaciones">
          <Area etiqueta="Observaciones (opcional)" valor={b.observaciones} max={2000} bloqueado={bloqueado} onCambio={(v) => set({ observaciones: v })} />
        </Seccion>

        <SeccionConstancia config={cons.config} valor={cons.valor} onCambio={cons.setValor} bloqueado={bloqueado} />

        {faltas.length > 0 && (
          <div role="status" aria-live="polite">
            <p className="campo-etiqueta">Para registrar falta:</p>
            <ul className="campo-faltas">{faltas.map((f) => <li key={f}>{f}</li>)}</ul>
          </div>
        )}
        <button type="button" className="tec-boton campo-enviar" disabled={faltas.length > 0 || vencido || bloqueado} onClick={() => setFase("confirmando")}>Revisar y registrar</button>
        <button type="button" className="btn-cancelar" onClick={() => setCancelando(true)} disabled={bloqueado}>Cancelar</button>
        <p className="campo-sub">Sesión de {correo}.</p>
      </section>

      {camaraEn && (
        <CamaraActa
          rotulo={camaraEn.papel ? "Acta física firmada" : cat.tipos_foto.find((t) => t.codigo === camaraEn.tipo)?.nombre ?? "Foto"}
          maxBytes={camaraEn.papel ? cat.limites.max_bytes_foto_acta_fisica : cat.limites.max_bytes_foto}
          sello={lineasSello}
          onFoto={(f) => { guardarFoto(camaraEn, f.blob); setCamaraEn(null); }}
          onCerrar={() => setCamaraEn(null)}
        />
      )}
    </div>
  );
}

/** Lo que se muestra en la confirmación (sin datos que no estén ya en el formulario). */
function resumen(b: BorradorActa, cat: Catalogo, c: L.Contadores, e: Entrada): string[] {
  const nombre = (lista: { codigo: string; nombre: string }[], cod: string) => lista.find((x) => x.codigo === cod)?.nombre ?? cod;
  const l: string[] = [];
  l.push(b.modo === "con_contrato" ? `Contrato ${b.contrato}` : "Predio sin contrato");
  l.push(`${b.direccion} · ${b.barrio}${b.estrato.trim() ? ` · estrato ${L.etiquetaEstrato(b.estrato)}` : ""}`);
  l.push(b.tieneMedidor ? `Medidor: ${nombre(cat.estados_medidor, b.estadoMedidor)}${b.lectura.trim() ? ` · lectura ${b.lectura.trim()} m³` : ""}` : "Sin medidor");
  l.push(`Hallazgos: ${b.hallazgos.map((h) => nombre(cat.tipos_hallazgo, h.codigo)).join("; ")}`);
  if (b.acciones.length > 0) l.push(`Acciones: ${b.acciones.map((a) => nombre(cat.acciones, a.codigo)).join("; ")}`);
  l.push(b.nadieAtendio ? "Nadie atendió la visita" : `Atendió: ${b.atNombre.trim()} (${nombre(cat.calidades_atendiente, b.atCalidad)}) · ${b.seNego ? "se negó a firmar" : "firmó el acta física"}`);
  l.push(`Operario: ${b.firmoOperario ? "firmó el acta física" : "no firmó el acta física"}`);
  l.push(`Fotos del hallazgo: ${c.hallazgo} · del acta física: ${b.papelPendiente ? "papel pendiente" : c.papel}`);
  l.push(`Acta física: ${b.numeroFisico.trim() ? `n.º ${b.numeroFisico.trim()}` : "sin número impreso"} · fecha ${L.fechaCO(b.fechaFisica)}`);
  l.push(`Consecutivo del registro: ${e.consecutivo}`);
  return l;
}

// ======================= Piezas del formulario =======================
function Seccion({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return <section className="acta-seccion" aria-label={titulo}><h2 className="acta-titulo">{titulo}</h2>{children}</section>;
}
function Campo({ etiqueta, valor, onCambio, bloqueado, max, modo, tipo = "text", ayuda }: {
  etiqueta: string; valor: string; onCambio: (v: string) => void; bloqueado?: boolean; max?: number; modo?: "decimal" | "numeric"; tipo?: "text" | "time"; ayuda?: string;
}) {
  const id = `acta-${etiqueta.replace(/\W+/g, "-").toLowerCase()}`;
  return (
    <div className="acta-campo">
      <label className="campo-etiqueta" htmlFor={id}>{etiqueta}</label>
      <input id={id} className="acta-input" type={tipo} value={valor} maxLength={max} inputMode={modo} disabled={bloqueado} autoComplete="off" onChange={(e) => onCambio(e.target.value)} />
      {ayuda && <small className="campo-sub">{ayuda}</small>}
    </div>
  );
}
function Area({ etiqueta, valor, onCambio, bloqueado, max }: { etiqueta: string; valor: string; onCambio: (v: string) => void; bloqueado?: boolean; max: number }) {
  const id = `acta-${etiqueta.replace(/\W+/g, "-").toLowerCase()}`;
  return (
    <div className="acta-campo">
      <label className="campo-etiqueta" htmlFor={id}>{etiqueta}</label>
      <textarea id={id} className="campo-texto" value={valor} maxLength={max} disabled={bloqueado} onChange={(e) => onCambio(e.target.value)} />
      <span className="campo-contador">{valor.length.toLocaleString("es-CO")} / {max.toLocaleString("es-CO")}</span>
    </div>
  );
}
function Selector({ etiqueta, valor, onCambio, opciones, bloqueado, ayuda }: {
  etiqueta: string; valor: string; onCambio: (v: string) => void; opciones: { codigo: string; nombre: string }[]; bloqueado?: boolean; ayuda?: string;
}) {
  const id = `acta-${etiqueta.replace(/\W+/g, "-").toLowerCase()}`;
  return (
    <div className="acta-campo">
      <label className="campo-etiqueta" htmlFor={id}>{etiqueta}</label>
      <select id={id} className="acta-input" value={valor} disabled={bloqueado} onChange={(e) => onCambio(e.target.value)}>
        <option value="">Seleccione…</option>
        {opciones.map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}
      </select>
      {ayuda && <small className="campo-sub">{ayuda}</small>}
    </div>
  );
}
function SiNo({ etiqueta, valor, onCambio, bloqueado }: { etiqueta: string; valor: boolean | null; onCambio: (v: boolean) => void; bloqueado?: boolean }) {
  const nombre = `sino-${etiqueta.replace(/\W+/g, "-").toLowerCase()}`;
  return (
    <fieldset className="acta-sino" disabled={bloqueado}>
      <legend className="campo-etiqueta">{etiqueta}</legend>
      <label className="acta-radio"><input type="radio" name={nombre} checked={valor === true} onChange={() => onCambio(true)} /> <span>Sí</span></label>
      <label className="acta-radio"><input type="radio" name={nombre} checked={valor === false} onChange={() => onCambio(false)} /> <span>No</span></label>
    </fieldset>
  );
}
function Miniaturas({ fotos, nombre, onQuitar, bloqueado }: { fotos: FotoLocal[]; nombre: (tipo: string) => string; onQuitar: (id: string) => void; bloqueado: boolean }) {
  if (fotos.length === 0) return <p className="campo-sub">Todavía no hay fotos.</p>;
  return (
    <div className="campo-fotos">
      {fotos.map((f, i) => (
        <div key={f.id} className="campo-foto">
          <span className="campo-foto-n">{nombre(f.tipo)} · {i + 1}{f.subida ? " · subida" : ""}</span>
          <img className="campo-foto-img" src={f.url} alt={`${nombre(f.tipo)}, foto ${i + 1}`} />
          {!bloqueado && <div className="campo-foto-acc"><button type="button" className="tec-boton-sec" onClick={() => onQuitar(f.id)}>Quitar</button></div>}
        </div>
      ))}
    </div>
  );
}
