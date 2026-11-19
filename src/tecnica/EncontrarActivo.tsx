import { useEffect, useMemo, useRef, useState } from "react";
import "./tokens.css";
import "./tecnica.css";
import "./dano.css";
import "./ficha.css";
import "./intervencion.css";
import "./encontrar.css";
import { apiLev, metros, metrosEntre, zoomParaRadio, ZOOM_MAX, ZOOM_MIN, type ActivoCerca, type Cerca, type Duplicado, type FichaCorta, type InicioLevantar, type PreparacionLevantar,
  type MisReportes, type PuntoCerca, type Servicio, type TipoLevantar } from "./apiLevantar";
import { subirFotoDano } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { MiniMapaEncontrar } from "./MiniMapaEncontrar";
import { FichaActivo } from "./FichaActivo";
import { IconoCamara } from "./IconoCamara";
import { ActaLevantar } from "./ActaLevantar";
import { CamaraActa } from "../campo/acta/CamaraActa";
import { useUbicacion } from "../campo/ubicacion";
import { supabase } from "../lib/supabase";
import { borrarBorradorCampo, fechaBorrador, useBorradorCampo, type ArchivoBorrador } from "./borradorCampo";

// «Encontrar o reportar activo» (Corte 14). Para todos los perfiles de campo y de supervisión, de Técnica y de Comercial (quién entra lo decide el SERVIDOR).
// · Minimapa centrado en la persona (no se arrastra), encuadrado en el círculo de búsqueda: 15 m → nivel 20; 30 m → nivel 19; botones + y – (18 a 20) y «Centrar».
// · Encontrar: filtro Acueducto / Alcantarillado y la lista de activos cercanos, con el mismo número que en el minimapa. Tocar uno abre su ficha y se vuelve.
// · Reportar activo («No está en la lista»): servicio, tipo, 1 foto obligatoria y 2 opcionales con la cámara de campo (sello de hora y GPS) y observación.
//   Se guarda la posición y la precisión del GPS. Con señal débil avisa; si igual se envía, queda «precisión baja». Si ya hay uno reportado a pocos metros, pregunta.
// La ficha es de solo lectura, salvo para quien ya podía editarla (supervisor de distribución y administrador: lo decide la ficha de siempre).
const fechaLarga = (iso: string) => new Date(iso).toLocaleDateString("es-CO", { day: "numeric", month: "long", year: "numeric", timeZone: "America/Bogota" });
const SENAL_DEBIL = "Señal débil: espere unos segundos o acérquese a cielo abierto.";
type Foto = { blob: Blob; url: string };
/** Lo que guarda el borrador local del reporte (borradorCampo.ts): lo elegido, la observación y dónde se empezó (para avisar si se retoma lejos). Las fotos van aparte. */
type DatosBorrador = { servicio: Servicio; tipo: TipoLevantar | null; observacion: string; lat: number | null; lon: number | null };
const BORRADOR = "encontrar";
type Vista = { v: "encontrar" } | { v: "mios" } | { v: "ficha"; codigo: string; activo?: { sistema: Servicio; lat: number; lon: number } } | { v: "reportar"; noEsDuplicado: boolean } | { v: "listo"; codigo: string; precisionBaja: boolean };

type ActivoDano = { codigo: string; sistema: Servicio; lat: number; lon: number };
export function EncontrarActivo({ onVolver, rotuloVolver = "Volver", onReportarDano }: { onVolver: () => void; rotuloVolver?: string;
  /** «Reportar daño en este activo»: abre el formulario de daño con el activo ya escogido (solo en Técnica, para quien tiene ese formulario: lo dice el servidor). */
  onReportarDano?: (a: ActivoDano) => void }) {
  const [inicio, setInicio] = useState<InicioLevantar | null>(null);
  const [errorInicio, setErrorInicio] = useState<ErrorTec | null>(null);
  const [intento, setIntento] = useState(0);
  const ubic = useUbicacion();
  const [servicio, setServicio] = useState<Servicio>("acueducto");
  const [cerca, setCerca] = useState<Cerca | null>(null);
  const [errorCerca, setErrorCerca] = useState<string | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [vez, setVez] = useState(0);                         // sube al guardar un reporte: se vuelve a buscar
  const [zoomManual, setZoomManual] = useState<number | null>(null);
  const [vista, setVista] = useState<Vista>({ v: "encontrar" });
  const [pregunta, setPregunta] = useState<(PuntoCerca | Duplicado)[] | null>(null);      // «Ya reportado el … ¿Es el mismo?»
  const [aviso, setAviso] = useState<string | null>(null);
  const [acta, setActa] = useState<string | null>(null);      // el acta (PDF) del punto recién reportado o de uno de «Mis reportes»
  // «Mis reportes» (19-nov): los puntos que reportó esta persona. Necesita la ruta `levantar_mios` (propuesta al Code A): mientras la Edge no la tenga, la
  // tarjeta no aparece. Se prueba una vez al abrir; si responde, se muestra.
  const [mios, setMios] = useState<MisReportes | null>(null);
  const [diasMios, setDiasMios] = useState(30);
  const [errorMios, setErrorMios] = useState<string | null>(null);
  const [hayMios, setHayMios] = useState(false);
  useEffect(() => { let vivo = true; setErrorMios(null);
    apiLev.mios(diasMios).then((r) => { if (vivo) { setMios(r); setHayMios(true); } }).catch((e) => { if (vivo) { setMios(null); if (hayMios) setErrorMios(e instanceof Error ? e.message : "No se pudo cargar."); } });
    return () => { vivo = false; }; }, [diasMios, vez]); // eslint-disable-line react-hooks/exhaustive-deps
  const ultima = useRef<{ lat: number; lon: number; radio: number; servicio: Servicio; vez: number; t: number } | null>(null);
  // De quién es el borrador del reporte: el correo de la sesión (no se guarda; solo su huella en la clave). Sin sesión conocida no hay borrador.
  const [persona, setPersona] = useState<string | null>(null);
  useEffect(() => { let vivo = true; void supabase.auth.getSession().then((r) => { if (vivo) setPersona((r.data.session as { user?: { email?: string } } | null)?.user?.email ?? ""); }, () => { if (vivo) setPersona(""); }); return () => { vivo = false; }; }, []);

  useEffect(() => {
    let vivo = true; setErrorInicio(null);
    apiLev.inicio().then((r) => { if (vivo) setInicio(r); }).catch((e) => { if (vivo) setErrorInicio(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento]);

  const fix = ubic.fix;
  const radioLocal = inicio && fix ? Math.max(inicio.radio_min_m, Math.min(fix.precision_m, inicio.radio_max_m)) : inicio?.radio_min_m ?? 15;
  const senalDebil = !!(inicio && fix && fix.precision_m > inicio.radio_max_m);

  // Buscar los cercanos: al tener posición, al cambiar el servicio y cuando la persona se mueve más de 3 m (o cambia el radio). Como mucho una búsqueda cada 2,5 s.
  // El GPS avisa seguido: la búsqueda en curso no se descarta por un aviso nuevo; vale la respuesta de la última que se pidió.
  const fixRef = useRef(fix); fixRef.current = fix;
  const pedido = useRef(0);
  const reloj = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { pedido.current = -1; if (reloj.current) clearTimeout(reloj.current); }, []);
  useEffect(() => {
    if (!inicio || !fix) return;
    const u = ultima.current;
    const cambio = !u || u.servicio !== servicio || u.vez !== vez;
    if (!cambio && metrosEntre(u, fix) <= 3 && Math.abs(u.radio - radioLocal) < 2) return;
    if (reloj.current) clearTimeout(reloj.current);
    reloj.current = setTimeout(() => {
      reloj.current = null;
      const f = fixRef.current; if (!f || pedido.current < 0) return;
      const radio = Math.max(inicio.radio_min_m, Math.min(f.precision_m, inicio.radio_max_m));
      ultima.current = { lat: f.lat, lon: f.lon, radio, servicio, vez, t: Date.now() };
      const n = ++pedido.current;
      setBuscando(true);
      apiLev.cerca(f.lat, f.lon, f.precision_m, servicio)
        .then((r) => { if (n === pedido.current) { setCerca(r); setErrorCerca(null); } })
        .catch((e) => { if (n === pedido.current) setErrorCerca(e instanceof ErrorTec && e.tipo === "red" ? "No hay señal: no se pudieron buscar los activos cercanos." : e instanceof Error ? e.message : "No se pudo buscar."); })
        .finally(() => { if (n === pedido.current) setBuscando(false); });
    }, cambio ? 0 : Math.max(0, 2500 - (Date.now() - u.t)));
  }, [inicio, fix, servicio, vez, radioLocal]);

  const actual = cerca && cerca.servicio === servicio ? cerca : null;
  const radio = actual?.radio_m ?? radioLocal;
  const zoomAuto = zoomParaRadio(radio);
  const zoom = zoomManual ?? zoomAuto;
  // 19-nov (David): si la pantalla muestra «Ya reportados aquí», no se pasa de largo: se pregunta por TODOS los que hay cerca (no solo los que están a menos de
  // la distancia de duplicado) y, para seguir, hay que tocar «Es otro activo». Primero los más cercanos.
  const yaReportados = useMemo(() => [...(actual?.puntos ?? [])].sort((a, b) => a.distancia_m - b.distancia_m), [actual]);

  if (errorInicio) {
    const sinAcceso = errorInicio.tipo === "permiso" || errorInicio.tipo === "denegado";
    return (
      <div className="tec-pagina tec-modo-distribucion enc">
        <Barra onVolver={onVolver} rotulo={rotuloVolver} />
        <section className="tec-tarjeta" role="alert">
          <h2>{sinAcceso ? "Sin acceso a «Encontrar o reportar activo»" : "No se pudo abrir"}</h2>
          <p>{sinAcceso ? "Pídale a su supervisor que le asigne el formulario «Encontrar o reportar activo»." : errorInicio.message}</p>
          {errorInicio.tipo === "sesion" ? <button type="button" className="tec-boton" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button>
            : !sinAcceso ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
        </section>
      </div>
    );
  }
  if (!inicio) return <div className="tec-pagina tec-modo-distribucion enc"><Barra onVolver={onVolver} rotulo={rotuloVolver} /><p className="tec-sub enc-pad" role="status">Cargando…</p></div>;

  if (vista.v === "ficha") {
    const volver = () => setVista({ v: "encontrar" });
    const a = vista.activo;
    const dano = onReportarDano && inicio.reporta_dano && a
      ? <div className="enc-accion-ficha"><button type="button" className="tec-boton" data-testid="enc-dano" onClick={() => onReportarDano({ codigo: vista.codigo, ...a })}>Reportar daño en este activo</button></div> : null;
    return inicio.ficha_completa
      ? <div className="tec-envoltura tec-modo-distribucion" data-testid="enc-ficha">{dano ? <div className="tec-pagina tec-modo-distribucion enc enc-barra-dano">{dano}</div> : null}<FichaActivo key={vista.codigo} codigo={vista.codigo} onVolver={volver} onAbrir={(c) => setVista({ v: "ficha", codigo: c })} rotuloVolver="Volver a los activos cercanos" /></div>
      : <div className="tec-pagina tec-modo-distribucion enc"><Barra onVolver={volver} rotulo="Volver a la lista" /><FichaSoloLectura codigo={vista.codigo} /></div>;
  }

  const abrirReportar = () => {
    setAviso(null);
    if (yaReportados.length) setPregunta(yaReportados); else setVista({ v: "reportar", noEsDuplicado: false });
  };

  return (
    <div className="tec-pagina tec-modo-distribucion enc" data-testid="encontrar">
      <Barra onVolver={vista.v === "encontrar" ? onVolver : () => setVista({ v: "encontrar" })} rotulo={vista.v === "encontrar" ? rotuloVolver : "Volver a la lista"} />

      <section className="tec-tarjeta enc-mapa" aria-label="Su posición y los activos cercanos">
        {fix ? (
          <div className="enc-mapa-caja">
            <MiniMapaEncontrar lat={fix.lat} lon={fix.lon} precision_m={fix.precision_m} radio_m={radio} zoom={zoom} servicio={servicio} activos={actual?.activos ?? []} puntos={actual?.puntos ?? []} />
            <div className="enc-zoom" role="group" aria-label="Acercar o alejar el mapa">
              <button type="button" className="enc-zoom-b" aria-label="Acercar" disabled={zoom >= ZOOM_MAX} onClick={() => setZoomManual(Math.min(ZOOM_MAX, zoom + 1))}>+</button>
              <button type="button" className="enc-zoom-b" aria-label="Alejar" disabled={zoom <= ZOOM_MIN} onClick={() => setZoomManual(Math.max(ZOOM_MIN, zoom - 1))}>–</button>
              <button type="button" className="enc-zoom-b enc-zoom-centrar" disabled={zoomManual === null || zoomManual === zoomAuto} onClick={() => setZoomManual(null)}>Centrar</button>
            </div>
          </div>
        ) : (
          <div className="enc-mapa-sin" role="status">
            <p>{ubic.estado === "buscando" ? "Buscando su ubicación…" : ubic.mensaje ?? "No se pudo obtener la ubicación."}</p>
            {ubic.estado !== "buscando" ? <button type="button" className="tec-boton-sec" onClick={ubic.actualizar}>Actualizar ubicación</button> : null}
          </div>
        )}
        {fix ? <p className="enc-gps" data-testid="enc-gps">Precisión del GPS: <strong>± {Math.round(fix.precision_m)} m</strong> · se busca a <strong>{Math.round(radio)} m</strong> de usted</p> : null}
        {senalDebil ? <p className="tec-aviso enc-debil" role="status" data-testid="enc-debil">{SENAL_DEBIL}</p> : null}
        <p className="tec-ayuda">El mapa siempre queda centrado en usted: no se arrastra.</p>
      </section>

      {aviso ? <p className="tec-aviso tec-aviso-ok enc-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}

      {vista.v === "encontrar" ? (
        <>
          <section className="tec-tarjeta" aria-labelledby="enc-t-lista">
            <h2 id="enc-t-lista">Activos cercanos</h2>
            <div className="dan-fila" role="group" aria-label="Servicio">
              {inicio.servicios.map((s) => <button key={s.codigo} type="button" className="dan-opcion" aria-pressed={servicio === s.codigo} data-servicio={s.codigo} onClick={() => setServicio(s.codigo)}>{s.nombre}</button>)}
            </div>
            {errorCerca ? <p className="tec-aviso tec-aviso-error" role="alert">{errorCerca} <button type="button" className="tec-enlace" onClick={() => { ultima.current = null; setVez((x) => x + 1); }}>Reintentar</button></p> : null}
            {!fix ? <p className="tec-ayuda">Cuando haya ubicación se listan los activos que están a su alrededor.</p>
              : !actual ? <p className="tec-sub" role="status">{buscando || !errorCerca ? "Buscando los activos cercanos…" : ""}</p>
              : actual.activos.length === 0 ? <p className="enc-vacio" data-testid="enc-vacio">No hay activos de {servicio} registrados a {Math.round(actual.radio_m)} m de usted.</p>
              : (
                <>
                  <ol className="enc-lista" data-testid="enc-lista">
                    {actual.activos.map((a) => <FilaActivo key={a.codigo} a={a} servicio={servicio} onAbrir={() => setVista({ v: "ficha", codigo: a.codigo, activo: { sistema: servicio, lat: a.lat, lon: a.lon } })} />)}
                  </ol>
                  {actual.total > actual.activos.length ? <p className="tec-ayuda">Se muestran los {actual.activos.length} más cercanos de {actual.total}.</p> : null}
                </>
              )}
            {actual?.puntos.length ? (
              <div className="enc-ya" data-testid="enc-ya">
                <h3>Ya reportados aquí, por levantar</h3>
                <ul>{actual.puntos.map((p) => <li key={p.codigo} data-levantar={p.codigo}><strong>{p.tipo_nombre}</strong> de {p.servicio} · reportado el {fechaLarga(p.registrado_en)} · a {metros(p.distancia_m)}</li>)}</ul>
              </div>
            ) : null}
          </section>
          {hayMios ? (
            <section className="tec-tarjeta" aria-labelledby="enc-t-mios" data-testid="enc-mios-entrada">
              <h2 id="enc-t-mios">Mis reportes</h2>
              <p className="tec-ayuda">Los activos que usted reportó, con su estado y su acta.</p>
              <button type="button" className="tec-boton-sec" data-testid="enc-mios" onClick={() => setVista({ v: "mios" })}>Ver mis reportes{mios && diasMios === 30 ? ` (${mios.total} en los últimos 30 días)` : ""}</button>
            </section>) : null}
          <section className="tec-tarjeta" aria-labelledby="enc-t-rep">
            <h2 id="enc-t-rep">¿No está en la lista?</h2>
            <p className="tec-ayuda">Si encontró un activo que no aparece (una tubería, una válvula, un hidrante, un pozo, una caja), repórtelo con una foto para que lo levanten.</p>
            <button type="button" className="tec-boton" disabled={!fix || (!actual && !errorCerca)} data-testid="enc-reportar" onClick={abrirReportar}>No está en la lista: reportar activo</button>
            {fix && !actual && !errorCerca ? <p className="tec-ayuda">Un momento: se está mirando si ya hay algo reportado aquí.</p> : null}
          </section>
        </>
      ) : null}

      {vista.v === "mios" ? (
        <section className="tec-tarjeta" aria-labelledby="enc-t-mios2" data-testid="enc-mios-lista">
          <h2 id="enc-t-mios2">Mis reportes</h2>
          <div className="dan-fila" role="group" aria-label="De cuándo">
            {[{ d: 30, n: "Últimos 30 días" }, { d: 90, n: "Últimos 90 días" }, { d: 0, n: "Todos" }].map((x) => <button key={x.d} type="button" className="dan-opcion" aria-pressed={diasMios === x.d} data-dias={x.d} onClick={() => setDiasMios(x.d)}>{x.n}</button>)}
          </div>
          {errorMios ? <p className="tec-aviso tec-aviso-error" role="alert">{errorMios}</p> : null}
          {!mios && !errorMios ? <p className="tec-sub" role="status">Cargando…</p> : null}
          {mios && mios.items.length === 0 ? <p className="enc-vacio" data-testid="enc-mios-vacio">{diasMios ? `No ha reportado activos en los últimos ${diasMios} días.` : "Todavía no ha reportado activos."}</p> : null}
          {mios?.items.length ? (
            <ul className="enc-mios">
              {mios.items.map((r) => (
                <li key={r.codigo} data-mio={r.codigo} data-estado={r.estado}>
                  <p><strong className="tec-codigo">{r.codigo}</strong> · {r.tipo_nombre} de {r.servicio} <span className={`itv-etiqueta${r.estado === "levantado" ? " lev-etq-ok" : ""}`}>{r.estado_nombre}</span></p>
                  <p className="tec-ayuda">Reportado el {fechaLarga(r.registrado_en)}{r.activo ? ` · quedó como ${r.activo}` : ""}</p>
                  <button type="button" className="tec-boton-sec" data-testid="enc-mio-acta" onClick={() => setActa(r.codigo)}>Ver acta (PDF)</button>
                </li>))}
            </ul>) : null}
          {mios?.recortada ? <p className="tec-ayuda">Se muestran los {mios.items.length} más recientes de {mios.total}.</p> : null}
        </section>
      ) : null}

      {vista.v === "reportar" && persona === null ? <p className="tec-sub enc-pad" role="status">Cargando…</p> : null}
      {vista.v === "reportar" && persona !== null ? (
        <Reportar key={`rep-${vez}`} persona={persona} inicio={inicio} servicioInicial={servicio} fix={fix} senalDebil={senalDebil} noEsDuplicado={vista.noEsDuplicado}
          onCancelar={() => setVista({ v: "encontrar" })} onDuplicado={(d) => setPregunta(d)}
          onGuardado={(codigo, baja) => { ultima.current = null; setVez((x) => x + 1); setVista({ v: "listo", codigo, precisionBaja: baja }); window.scrollTo?.(0, 0); }} />
      ) : null}

      {vista.v === "listo" ? (
        <section className="tec-tarjeta dan-listo" role="status" data-testid="enc-listo">
          <h2>Activo reportado: {vista.codigo}</h2>
          <p>Estado: <strong>Reportado</strong>. Le llega al supervisor de distribución para que lo manden a levantar.</p>
          {vista.precisionBaja ? <p className="tec-aviso enc-debil">Quedó marcado «precisión baja»: la señal del GPS era débil al reportar.</p> : null}
          <div className="dan-fila">
            <button type="button" className="tec-boton" data-testid="enc-acta" onClick={() => setActa(vista.codigo)}>Descargar acta (PDF)</button>
            <button type="button" className="tec-boton-sec" onClick={() => setVista({ v: "encontrar" })}>Volver a los activos cercanos</button>
            <button type="button" className="tec-boton-sec" onClick={() => setVista({ v: "reportar", noEsDuplicado: false })}>Reportar otro activo</button>
          </div>
        </section>
      ) : null}

      {acta ? <ActaLevantar codigo={acta} onCerrar={() => setActa(null)} /> : null}
      {pregunta ? (
        <div className="enc-fondo" role="presentation">
          <div className="enc-dialogo" role="dialog" aria-modal="true" aria-labelledby="enc-dlg-tit" data-testid="enc-duplicado">
            <h3 id="enc-dlg-tit">{pregunta.length === 1 ? "Ya hay un activo reportado aquí" : `Ya hay ${pregunta.length} activos reportados aquí`}</h3>
            <ul>{pregunta.map((p) => <li key={p.codigo}><strong>{p.tipo_nombre}</strong> de {p.servicio}: ya reportado el {fechaLarga(p.registrado_en)}, a {metros(p.distancia_m)} de usted.</li>)}</ul>
            <p><strong>{pregunta.length === 1 ? "¿Es el mismo?" : "¿Es alguno de esos?"}</strong> Si lo es, no hace falta reportarlo otra vez.</p>
            <div className="dan-fila">
              <button type="button" className="tec-boton" data-testid="enc-dup-si" onClick={() => { setPregunta(null); setVista({ v: "encontrar" }); if (persona) void borrarBorradorCampo(BORRADOR, persona); setAviso("Ese activo ya está reportado: no hace falta reportarlo otra vez."); }}>{pregunta.length === 1 ? "Sí, es el mismo" : "Sí, es uno de esos"}</button>
              <button type="button" className="tec-boton-sec" data-testid="enc-dup-no" onClick={() => { setPregunta(null); setVista({ v: "reportar", noEsDuplicado: true }); }}>Es otro activo</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function Barra({ onVolver, rotulo }: { onVolver: () => void; rotulo: string }) {
  return (
    <div className="tec-volver-barra">
      <button type="button" className="tec-volver" onClick={onVolver}><span aria-hidden="true">←</span> {rotulo}</button>
      <span className="tec-volver-tit">Encontrar o reportar activo</span>
    </div>
  );
}

function FilaActivo({ a, servicio, onAbrir }: { a: ActivoCerca; servicio: Servicio; onAbrir: () => void }) {
  const detalle = [a.material, a.diametro_mm ? `${Number(a.diametro_mm).toLocaleString("es-CO")} mm` : null, a.proyectado ? a.estado : null].filter(Boolean).join(" · ");
  return (
    <li>
      <button type="button" className="enc-fila" data-activo={a.codigo} onClick={onAbrir}>
        <span className={`enc-n enc-n-${servicio}`} aria-hidden="true">{a.n}</span>
        <span className={`enc-ico enc-ico-${a.forma}`} aria-hidden="true" />
        <span className="enc-fila-txt">
          <span className="enc-fila-tit"><span className="tec-codigo">{a.codigo}</span> · {a.tipo}</span>
          {detalle ? <span className="enc-fila-det">{detalle}</span> : null}
        </span>
        <span className="enc-fila-dist">{metros(a.distancia_m)}</span>
      </button>
    </li>
  );
}

function FichaSoloLectura({ codigo }: { codigo: string }) {
  const [f, setF] = useState<FichaCorta | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true; setF(null); setError(null);
    apiLev.ficha(codigo).then((r) => { if (vivo) setF(r); }).catch((e) => { if (vivo) setError(e instanceof Error ? e.message : "No se pudo cargar la ficha."); });
    return () => { vivo = false; };
  }, [codigo]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!f) return <p className="tec-sub enc-pad" role="status">Cargando la ficha…</p>;
  const filas: [string, string | null][] = [
    ["Tipo", f.clase ? `${f.tipo} · ${f.clase}` : f.tipo], ["Servicio", f.sistema === "acueducto" ? "Acueducto" : f.sistema === "alcantarillado" ? "Alcantarillado" : f.sistema],
    ["Nombre", f.nombre], ["Material", f.material], ["Diámetro", f.diametro_mm ? `${Number(f.diametro_mm).toLocaleString("es-CO")} mm` : null],
    ["Longitud", f.longitud_m ? `${Number(f.longitud_m).toLocaleString("es-CO")} m` : null], ["Profundidad", f.profundidad_m ? `${Number(f.profundidad_m).toLocaleString("es-CO")} m` : null],
    ["Instalado", f.fecha_instalacion ? fechaLarga(`${f.fecha_instalacion}T12:00:00-05:00`) : null], ["Estado", f.estado], ["Sector hidráulico", f.sector], ["Código anterior", f.codigo_anterior],
  ];
  return (
    <section className="tec-tarjeta" aria-labelledby="enc-ficha-tit" data-testid="enc-ficha-corta">
      <h2 id="enc-ficha-tit"><span className="tec-codigo">{f.codigo}</span></h2>
      <p className="tec-ayuda">Ficha de solo lectura.</p>
      <dl className="enc-dl">{filas.filter(([, v]) => v).map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}</dl>
    </section>
  );
}

function Reportar({ persona, inicio, servicioInicial, fix, senalDebil, noEsDuplicado, onCancelar, onGuardado, onDuplicado }: {
  persona: string; inicio: InicioLevantar; servicioInicial: Servicio; fix: { lat: number; lon: number; precision_m: number } | null; senalDebil: boolean; noEsDuplicado: boolean;
  onCancelar: () => void; onGuardado: (codigo: string, precisionBaja: boolean) => void; onDuplicado: (d: Duplicado[]) => void;
}) {
  const [servicio, setServicio] = useState<Servicio>(servicioInicial);
  const [tipo, setTipo] = useState<TipoLevantar | null>(null);
  const [fotos, setFotos] = useState<Foto[]>([]);
  const [camara, setCamara] = useState(false);
  const [observacion, setObservacion] = useState("");
  const [intentado, setIntentado] = useState(false);
  const [enviando, setEnviando] = useState<string | null>(null);
  const [errorEnvio, setErrorEnvio] = useState<string | null>(null);
  const prep = useRef<PreparacionLevantar | null>(null);
  const subidas = useRef<Set<number>>(new Set());
  const fixRef = useRef(fix); fixRef.current = fix;
  useEffect(() => () => { for (const f of fotos) URL.revokeObjectURL(f.url); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Borrador local (19-nov): lo elegido, la observación y las fotos quedan en este celular mientras se llena; se borra al guardar o al cancelar.
  const [guardadoYa, setGuardadoYa] = useState(false);
  const dondeEmpezo = useRef<{ lat: number; lon: number } | null>(null);
  if (!dondeEmpezo.current && fix) dondeEmpezo.current = { lat: Number(fix.lat.toFixed(6)), lon: Number(fix.lon.toFixed(6)) };
  const datosBorrador: DatosBorrador = { servicio, tipo, observacion, lat: dondeEmpezo.current?.lat ?? null, lon: dondeEmpezo.current?.lon ?? null };
  const archivosBorrador = useMemo<ArchivoBorrador[]>(() => fotos.map((f) => ({ blob: f.blob, etiqueta: "foto" })), [fotos]);
  // «sin tocar»: el servicio viene del filtro de la lista y la posición la pone el GPS; cuentan el tipo, la observación y las fotos
  const borrador = useBorradorCampo<DatosBorrador>(BORRADOR, persona, datosBorrador, archivosBorrador, guardadoYa, { tipo, observacion }, { apagado: persona === "" });
  function continuarBorrador() {
    const b = borrador.oferta; if (!b) return;
    const d = b.datos;
    if (inicio.servicios.some((s) => s.codigo === d.servicio)) setServicio(d.servicio);
    setTipo(inicio.tipos.some((t) => t.codigo === d.tipo) ? d.tipo : null);
    setObservacion(typeof d.observacion === "string" ? d.observacion : "");
    setFotos(b.archivos.slice(0, inicio.max_fotos).map((a) => ({ blob: a.blob, url: URL.createObjectURL(a.blob) })));
    borrador.resolver(true);
  }

  const obs = observacion.trim();
  const errores: string[] = [];
  if (!tipo) errores.push("Elija qué activo encontró.");
  if (fotos.length < inicio.min_fotos) errores.push("Tome al menos una foto del activo.");
  if (tipo === "otro" && obs.length < 3) errores.push("Escriba en la observación qué activo es.");
  if (obs.length > 0 && obs.length < 3) errores.push("La observación lleva al menos 3 caracteres.");
  if (!fix) errores.push("Falta la ubicación del GPS.");

  async function guardar() {
    setIntentado(true); setErrorEnvio(null);
    if (errores.length || !tipo || !fix) { document.querySelector(".enc-errores")?.scrollIntoView?.({ block: "center" }); return; }
    try {
      if (!prep.current || prep.current.fotos.length !== fotos.length) { setEnviando("Preparando el envío…"); prep.current = await apiLev.preparar(fotos.length); subidas.current = new Set(); }
      const p = prep.current;
      for (let i = 0; i < fotos.length; i++) {
        if (subidas.current.has(i + 1)) continue;
        setEnviando(`Subiendo la foto ${i + 1} de ${fotos.length}…`);
        if (fotos[i].blob.size > p.max_bytes_foto) throw new Error(`La foto ${i + 1} pesa más de lo permitido.`);
        await subirFotoDano(p.fotos[i].url_subida, fotos[i].blob);
        subidas.current.add(i + 1);
      }
      setEnviando("Guardando el reporte…");
      const g = fixRef.current ?? fix;
      const r = await apiLev.crear(p.punto_id, { servicio, tipo, observacion: obs || null, lat: Number(g.lat.toFixed(6)), lon: Number(g.lon.toFixed(6)),
        precision_m: Math.max(0.1, Number(g.precision_m.toFixed(1))), fotos: p.fotos.map((f) => ({ n: f.n, ruta: f.ruta })), no_es_duplicado: noEsDuplicado });
      if (r.creado) { borrador.terminar(); setGuardadoYa(true); onGuardado(r.codigo, r.precision_baja); }
      else onDuplicado(r.duplicados);      // alguien lo reportó mientras se llenaba: se pregunta (las fotos siguen aquí)
    } catch (e) {
      const msg = e instanceof Error ? e.message : "No se pudo guardar.";
      if (msg === "vencida") { prep.current = null; setErrorEnvio("El permiso para subir las fotos venció. Pulse «Guardar» de nuevo: se pide uno nuevo."); }
      else if (e instanceof ErrorTec && e.tipo === "red") setErrorEnvio("No hay señal o la conexión se cortó. Lo escrito y las fotos siguen aquí: pulse «Guardar» de nuevo (no se duplica).");
      else setErrorEnvio(msg);
    } finally { setEnviando(null); }
  }

  if (borrador.leyendo) return <p className="tec-sub enc-pad" role="status">Cargando…</p>;
  if (borrador.oferta) {
    const o = borrador.oferta, nf = o.archivos.length;
    const lejos = fix && typeof o.datos.lat === "number" && typeof o.datos.lon === "number" ? metrosEntre({ lat: o.datos.lat, lon: o.datos.lon }, fix) : 0;
    return (
      <section className="tec-tarjeta" role="group" aria-label="Borrador guardado" data-testid="borrador-oferta">
        <h2>Reportar activo que no está en la lista</h2>
        <p>Tiene un borrador del {fechaBorrador(o.guardado)}{nf ? ` (con ${nf} ${nf === 1 ? "foto" : "fotos"})` : ""}. ¿Continuar o descartar?</p>
        {lejos > inicio.radio_max_m ? <p className="tec-aviso enc-debil" role="note" data-testid="borrador-lejos">Ese borrador se empezó a {metros(lejos)} de aquí. El reporte se guarda con su posición de ahora: continúe solo si está junto al activo.</p> : null}
        <div className="tec-acciones">
          <button type="button" className="tec-boton" onClick={continuarBorrador}>Continuar</button>
          <button type="button" className="tec-boton-sec" onClick={() => borrador.resolver(false)}>Descartar</button>
        </div>
      </section>);
  }
  return (
    <section className="tec-tarjeta" aria-labelledby="enc-t-form" data-testid="enc-form">
      <h2 id="enc-t-form">Reportar activo que no está en la lista</h2>
      <div className="enc-campo"><span className="dan-rot" id="enc-r-serv">Servicio</span>
        <div className="dan-fila" role="group" aria-labelledby="enc-r-serv">
          {inicio.servicios.map((s) => <button key={s.codigo} type="button" className="dan-opcion" aria-pressed={servicio === s.codigo} data-form-servicio={s.codigo} disabled={!!enviando} onClick={() => setServicio(s.codigo)}>{s.nombre}</button>)}
        </div></div>
      <div className="enc-campo"><span className="dan-rot" id="enc-r-tipo">¿Qué activo encontró?</span>
        <div className="dan-fila" role="group" aria-labelledby="enc-r-tipo">
          {inicio.tipos.map((t) => <button key={t.codigo} type="button" className="dan-opcion" aria-pressed={tipo === t.codigo} data-tipo={t.codigo} disabled={!!enviando} onClick={() => setTipo(t.codigo)}>{t.nombre}</button>)}
        </div></div>
      <div className="enc-campo"><span className="dan-rot">Fotos</span>
        <p className="tec-ayuda">Una obligatoria y hasta dos más. Solo cámara, con sello de hora y GPS. Mientras llena el reporte, las fotos quedan en el borrador de este celular; se borran al guardar o al cancelar.</p>
        <div className="dan-fila">
          <button type="button" className="tec-boton-sec" disabled={fotos.length >= inicio.max_fotos || !!enviando} data-testid="enc-foto" onClick={() => setCamara(true)}><IconoCamara />{fotos.length === 0 ? "Tomar la foto" : "Tomar otra foto"}</button>
        </div>
        {camara ? (
          <CamaraActa rotulo="Foto del activo" maxBytes={prep.current?.max_bytes_foto ?? 1572864}
            sello={() => [new Date().toLocaleString("es-CO"), fixRef.current ? `${fixRef.current.lat.toFixed(5)}, ${fixRef.current.lon.toFixed(5)} ± ${Math.round(fixRef.current.precision_m)} m` : "sin GPS"]}
            onFoto={({ blob }) => { setFotos((f) => [...f, { blob, url: URL.createObjectURL(blob) }]); prep.current = null; setCamara(false); }}
            onCerrar={() => setCamara(false)} />
        ) : null}
        {fotos.length ? <div className="dan-fotos">{fotos.map((f, i) => (
          <figure key={f.url} className="enc-foto"><img src={f.url} alt={`Foto ${i + 1} del activo`} />
            <button type="button" className="tec-enlace" disabled={!!enviando} onClick={() => { URL.revokeObjectURL(f.url); setFotos((x) => x.filter((y) => y !== f)); prep.current = null; }}>Quitar</button></figure>))}</div> : null}
      </div>
      <label className="enc-campo"><span className="dan-rot">Observación {tipo === "otro" ? "(diga qué activo es)" : "(opcional)"}</span>
        <textarea rows={3} maxLength={500} value={observacion} disabled={!!enviando} onChange={(e) => setObservacion(e.target.value)} placeholder="Por ejemplo: frente a la tienda, en el andén, tapa partida…" /></label>
      <p className="enc-gps">{fix ? <>Se guarda su posición: {fix.lat.toFixed(5)}, {fix.lon.toFixed(5)} · precisión <strong>± {Math.round(fix.precision_m)} m</strong></> : "Todavía no hay ubicación del GPS."}</p>
      {senalDebil ? <p className="tec-aviso enc-debil" role="status">{SENAL_DEBIL} Si lo envía así, el punto queda marcado «precisión baja».</p> : null}
      {intentado && errores.length ? <ul className="tec-aviso tec-aviso-error enc-errores" role="alert">{errores.map((e) => <li key={e}>{e}</li>)}</ul> : null}
      {errorEnvio ? <p className="tec-aviso tec-aviso-error" role="alert">{errorEnvio}</p> : null}
      {enviando ? <p className="tec-sub" role="status">{enviando}</p> : null}
      <div className="dan-fila">
        <button type="button" className="tec-boton" disabled={!!enviando} data-testid="enc-guardar" onClick={() => void guardar()}>{enviando ? "Guardando…" : "Guardar el reporte"}</button>
        <button type="button" className="tec-boton-sec" disabled={!!enviando} onClick={() => { borrador.terminar(); onCancelar(); }}>Cancelar</button>
      </div>
    </section>
  );
}
