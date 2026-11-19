import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { importarConRecarga, lazyConRecarga } from "../lib/recarga";
import { fechaBorrador, useBorradorCampo, type ArchivoBorrador } from "./borradorCampo";
import { IconoCamara } from "./IconoCamara";
import "./ficha.css";
import "./dano.css";
import { apiDano, apiRedes, subirFotoDano, type DanoGuardado, type Ficha, type FormularioDano as Def, type PreparacionDano } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { useUbicacion, UMBRAL_PRECISION_MALA_M } from "../campo/ubicacion";
import { abrirReloj, esRechazoPorHora, recalcularReloj, type RelojInicio } from "../campo/inicio";
import { CamaraActa } from "../campo/acta/CamaraActa";
import { ConfirmarCancelar } from "../components/ConfirmarCancelar";
import { PanelCierre } from "./PanelCierre";
import { FichaActivo } from "./FichaActivo";
import type { Eleccion } from "./MiniMapaRed";

// «Reportar daño o falla» (Corte 2), como la maqueta Dano.dc.html. Lo llena el personal de Técnica con el formulario asignado (danos_fallas).
// 1 activo y ubicación (primero el sistema; minimapa de UNA red con el activo más cercano preseleccionado; tocar un tramo muestra sus nodos;
//   «no identificado» marcando el punto) · 2 qué pasó · 3 tiempos (se calculan solos) · 4 tamaño y posible pérdida · 5 afectación y riesgo · 6 causa · 7 fotos.
// Las reglas las vuelve a decidir el servidor. El nombre o la placa del tercero es un dato personal: va aparte y solo lo ve el supervisor.
// Sin términos tarifarios. La pérdida no se calcula aquí: sin la tabla de caudales de Técnica, el daño queda «sin tabla».

const MiniMapaRed = lazyConRecarga(() => import("./MiniMapaRed").then((m) => ({ default: m.MiniMapaRed })));
/** Lo que guarda el borrador local (borradorCampo.ts). El nombre o la placa del tercero NO va: es un dato personal y no se deja en el celular. */
type DatosBorrador = { sistema: "acueducto" | "alcantarillado" | null; eleccion: Eleccion | null; noIdent: boolean; queEs: string; clase: "dano" | "falla"; tipo: string;
  tIni: string; tDet: string; tRep: string; tRes: string; rotura: string; largo: string; presion: string; usuarios: string; sector: string; sectorAuto: boolean; riesgo: string; marcas: string[];
  causaClase: string; causa: string; terceroTipo: string; descripcion: string; yaReparado: boolean; inicio: string };
type Foto = { blob: Blob; momento: "dano" | "entorno" | "reparado"; url: string };
const MOMENTOS = [{ c: "dano", n: "El daño" }, { c: "entorno", n: "Entorno" }, { c: "reparado", n: "Reparado" }] as const;
const RIESGOS = [{ c: "bajo", n: "Bajo" }, { c: "medio", n: "Medio" }, { c: "alto", n: "Alto" }] as const;
const CAUSAS = [{ c: "propia", n: "Propia" }, { c: "terceros", n: "De terceros" }, { c: "desconocida", n: "Desconocida" }] as const;

const aLocal = (d: Date) => { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 16); };
const aIso = (v: string) => (v ? new Date(v).toISOString() : null);
function duracion(desde: string, hasta: string): string | null {
  if (!desde || !hasta) return null;
  const s = (new Date(hasta).getTime() - new Date(desde).getTime()) / 1000;
  if (!Number.isFinite(s) || s < 0) return null;
  const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
  return `${h} h ${String(m).padStart(2, "0")} min`;
}
const numeroONulo = (t: string) => { const v = t.trim().replace(",", "."); if (!v) return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };

export function FormularioDano({ correo, onSalir, onRegistrarReparacion, activoInicial }: {
  correo: string; onSalir?: () => void;
  activoInicial?: { codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number } | null;      // Corte 6a: «Reportar daño» desde la tarjeta del geovisor
  onRegistrarReparacion?: (d: { codigo: string; sistema: "acueducto" | "alcantarillado"; activo: string | null; lat: number; lon: number }) => void;   // Corte 3a
}) {
  const [def, setDef] = useState<Def | null>(null);
  const [errorDef, setErrorDef] = useState<string | null>(null);
  const ubic = useUbicacion();
  const reloj = useRef<RelojInicio>(abrirReloj());
  const [sistema, setSistema] = useState<"acueducto" | "alcantarillado" | null>(activoInicial?.sistema ?? null);
  const [eleccion, setEleccion] = useState<Eleccion | null>(activoInicial
    ? { tipo: "activo", activo: { codigo: activoInicial.codigo, prefijo: activoInicial.codigo.slice(0, 3), tipo: "", estado: "", estado_codigo: "", retirado: false, lat: activoInicial.lat, lon: activoInicial.lon } } : null);
  const [detalle, setDetalle] = useState<Ficha | null>(null);
  const [noIdent, setNoIdent] = useState(false);
  const [queEs, setQueEs] = useState("");
  const [buscar, setBuscar] = useState("");
  const [resultados, setResultados] = useState<{ codigo: string; tipo: string; clase?: string; codigo_anterior?: string; lat: number; lon: number; prefijo: string }[] | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [clase, setClase] = useState<"dano" | "falla">("dano");
  const [tipo, setTipo] = useState("");
  const ahora = useMemo(() => aLocal(new Date()), []);
  const [tIni, setTIni] = useState(""); const [tDet, setTDet] = useState(ahora); const [tRep, setTRep] = useState(""); const [tRes, setTRes] = useState("");
  const [rotura, setRotura] = useState(""); const [largo, setLargo] = useState(""); const [presion, setPresion] = useState("");
  const [sectorProp, setSectorProp] = useState<{ sector: number | null; subsector: string | null } | null>(null);      // 9a-bis: el de la ubicación
  const sectorAuto = useRef(true);      // mientras la persona no escriba otro, el campo sigue a la ubicación
  const [usuarios, setUsuarios] = useState(""); const [sector, setSector] = useState(""); const [riesgo, setRiesgo] = useState(""); const [marcas, setMarcas] = useState<string[]>([]);
  const [causaClase, setCausaClase] = useState(""); const [causa, setCausa] = useState(""); const [terceroTipo, setTerceroTipo] = useState(""); const [terceroNombre, setTerceroNombre] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [fotos, setFotos] = useState<Foto[]>([]);
  const sinFotos = false;      // §25.8 (Corte 4a): nadie registra «sin evidencia fotográfica»; lo que llega sin foto entra por el reporte de anomalías
  const [yaReparado, setYaReparado] = useState(false);      // §25 (Corte 4a): los tiempos de reparación solo si el daño se registra ya reparado; si no, la reparación va con «Registrar intervención»
  const ubicGuardada = useRef<{ lat: number; lon: number } | null>(null);
  const [camara, setCamara] = useState<Foto["momento"] | null>(null);
  const [intentado, setIntentado] = useState(false);       // tras el primer «Guardar», la lista de lo que falta se recalcula en vivo
  const [enviando, setEnviando] = useState<string | null>(null);
  const [errorEnvio, setErrorEnvio] = useState<string | null>(null);
  const prep = useRef<PreparacionDano | null>(null);
  const subidas = useRef<Set<number>>(new Set());
  const [guardado, setGuardado] = useState<DanoGuardado | null>(null);
  const [cancelar, setCancelar] = useState(false);
  const [ficha, setFicha] = useState<string | null>(null);
  const cercanosPedidos = useRef<string | null>(activoInicial?.sistema ?? null);      // con el activo del geovisor no se preselecciona el más cercano

  // Borrador local (18-nov): lo escrito, lo elegido y las fotos quedan en este celular mientras se llena; se borra al guardar o al cancelar.
  const datosBorrador: DatosBorrador = { sistema, eleccion, noIdent, queEs, clase, tipo, tIni, tDet, tRep, tRes, rotura, largo, presion, usuarios, sector, sectorAuto: sectorAuto.current, riesgo, marcas,
    causaClase, causa, terceroTipo, descripcion, yaReparado, inicio: reloj.current.iso };
  const archivosBorrador = useMemo<ArchivoBorrador[]>(() => fotos.map((f) => ({ blob: f.blob, etiqueta: f.momento })), [fotos]);
  // «sin tocar»: no cuentan la hora de inicio ni el sector que se propone solo desde la ubicación
  const borrador = useBorradorCampo<DatosBorrador>("dano", correo, datosBorrador, archivosBorrador, !!guardado, { ...datosBorrador, inicio: "", sector: sectorAuto.current ? "" : sector });
  function continuarBorrador() {
    const b = borrador.oferta; if (!b) return;
    const d = b.datos, txt = (v: unknown) => (typeof v === "string" ? v : "");
    if (d.sistema === "acueducto" || d.sistema === "alcantarillado") { setSistema(d.sistema); cercanosPedidos.current = d.sistema; }
    setEleccion(d.eleccion ?? null); setNoIdent(!!d.noIdent); setQueEs(txt(d.queEs)); setClase(d.clase === "falla" ? "falla" : "dano"); setTipo(txt(d.tipo));
    setTIni(txt(d.tIni)); setTDet(txt(d.tDet) || ahora); setTRep(txt(d.tRep)); setTRes(txt(d.tRes)); setRotura(txt(d.rotura)); setLargo(txt(d.largo)); setPresion(txt(d.presion));
    setUsuarios(txt(d.usuarios)); sectorAuto.current = d.sectorAuto !== false; setSector(txt(d.sector)); setRiesgo(txt(d.riesgo)); setMarcas(Array.isArray(d.marcas) ? d.marcas.filter((x) => typeof x === "string") : []);
    setCausaClase(txt(d.causaClase)); setCausa(txt(d.causa)); setTerceroTipo(txt(d.terceroTipo)); setDescripcion(txt(d.descripcion)); setYaReparado(!!d.yaReparado);
    // la hora de inicio del formulario es la del borrador mientras el servidor todavía la acepte; si no, la de ahora
    const t = Date.parse(txt(d.inicio)), maxMs = (def?.reglas.max_horas_inicio ?? 12) * 3_600_000;
    if (Number.isFinite(t) && t <= Date.now() && Date.now() - t < maxMs - 600_000) reloj.current = abrirReloj(t, performance.now() - (Date.now() - t));
    setFotos(b.archivos.filter((a) => MOMENTOS.some((m) => m.c === a.etiqueta)).map((a) => ({ blob: a.blob, momento: a.etiqueta as Foto["momento"], url: URL.createObjectURL(a.blob) })));
    borrador.resolver(true);
  }

  // Precarga del minimapa al abrir: si tras una publicación ya no está, la página se recarga ahora (sin nada escrito) y no en la mitad del formulario.
  useEffect(() => { void importarConRecarga(() => import("./MiniMapaRed")).catch(() => {}); }, []);
  useEffect(() => {
    apiDano.formulario().then(setDef).catch((e) => setErrorDef(e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene asignado el formulario de daños y fallas." : e instanceof Error ? e.message : "No se pudo cargar."));
  }, []);

  // activo más cercano preseleccionado (una vez por sistema, cuando hay GPS)
  useEffect(() => {
    if (!sistema || !ubic.fix || cercanosPedidos.current === sistema || eleccion) return;
    cercanosPedidos.current = sistema;
    apiRedes.cercanos(ubic.fix.lat, ubic.fix.lon, sistema, def?.reglas.radio_cercanos_m)
      .then((r) => { const a = r.activos[0]; if (a) { setEleccion({ tipo: "activo", activo: { ...a, lat: ubic.fix!.lat, lon: ubic.fix!.lon } }); setAviso(`Se preseleccionó el activo más cercano (${a.codigo}, a ${Math.round(a.distancia_m ?? 0)} m). Si no es, toque otro en el mapa.`); }
                      else setAviso(`No hay activos de ${sistema} a ${r.radio_m} m. Toque el activo en el mapa o búsquelo por código.`); })
      .catch(() => setAviso("No se pudo buscar el activo más cercano. Tóquelo en el mapa o búsquelo por código."));
  }, [sistema, ubic.fix, def]); // eslint-disable-line react-hooks/exhaustive-deps

  // datos del activo elegido (tipo, clase, material…) para la tarjeta
  useEffect(() => {
    setDetalle(null);
    if (eleccion?.tipo !== "activo") return;
    let vivo = true;
    apiRedes.activo(eleccion.activo.codigo).then((f) => { if (vivo) setDetalle(f); }).catch(() => {});
    return () => { vivo = false; };
  }, [eleccion?.tipo === "activo" ? eleccion.activo.codigo : null]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => () => fotos.forEach((f) => URL.revokeObjectURL(f.url)), []); // eslint-disable-line react-hooks/exhaustive-deps

  // 9a-bis (David, 16-nov): el sector hidráulico de la ubicación es el oficial. Se propone desde el mismo punto que se guarda con el daño (el marcado en el mapa,
  // el GPS o el activo); lo que la persona escriba queda de respaldo y ya no se pisa. El servidor también lo toma de la ubicación si llega vacío.
  const puntoSector = noIdent && eleccion?.tipo === "punto" ? { lat: eleccion.lat, lon: eleccion.lon } : ubic.fix ? { lat: ubic.fix.lat, lon: ubic.fix.lon }
    : eleccion?.tipo === "activo" ? { lat: eleccion.activo.lat, lon: eleccion.activo.lon } : null;
  const claveSector = puntoSector ? `${puntoSector.lat.toFixed(4)},${puntoSector.lon.toFixed(4)}` : "";
  useEffect(() => {
    if (!puntoSector) return;
    let vivo = true;
    apiRedes.sectorEn(puntoSector.lat, puntoSector.lon).then((r) => {
      if (!vivo) return;
      setSectorProp(r);
      if (sectorAuto.current) setSector(r.sector ? String(r.sector) : "");
    }).catch(() => {});
    return () => { vivo = false; };
  }, [claveSector]); // eslint-disable-line react-hooks/exhaustive-deps

  if (ficha) return <FichaActivo codigo={ficha} onAbrir={setFicha} onVolver={() => setFicha(null)} rotuloVolver="Volver al daño" />;
  if (errorDef) return <section className="tec-tarjeta" role="alert"><h2>Daño o falla</h2><p>{errorDef}</p></section>;
  if (!def || borrador.leyendo) return <p className="tec-sub dan-pad" role="status">Cargando el formulario…</p>;
  if (borrador.oferta) return (
    <section className="tec-tarjeta" role="group" aria-label="Borrador guardado" data-testid="borrador-oferta">
      <h2>Daño o falla</h2>
      <p>Tiene un borrador del {fechaBorrador(borrador.oferta.guardado)}{borrador.oferta.archivos.length ? ` (con ${borrador.oferta.archivos.length} ${borrador.oferta.archivos.length === 1 ? "foto" : "fotos"})` : ""}. ¿Continuar o descartar?</p>
      <div className="tec-acciones">
        <button type="button" className="tec-boton" onClick={continuarBorrador}>Continuar</button>
        <button type="button" className="tec-boton-sec" onClick={() => borrador.resolver(false)}>Descartar</button>
      </div>
    </section>);

  const tipos = def.tipos.filter((t) => t.clase === clase && (!sistema || t.sistemas.includes(sistema)));
  const tipoSel = def.tipos.find((t) => t.codigo === tipo) ?? null;
  const respuesta = duracion(tDet, tRep), reparacion = duracion(tRep, tRes), total = duracion(tIni || tDet, tRes);
  const fotosDano = fotos.filter((f) => f.momento === "dano").length;

  function elegirSistema(s: "acueducto" | "alcantarillado") {
    if (s === sistema) return;
    setSistema(s); setEleccion(null); setResultados(null); setAviso(null); setNoIdent(false);
    if (tipoSel && !tipoSel.sistemas.includes(s)) setTipo("");
  }
  async function hacerBusqueda() {
    if (!sistema || buscar.trim().length < 2) return;
    try { setResultados((await apiDano.buscar(buscar.trim(), sistema)).activos); } catch (e) { setAviso(e instanceof Error ? e.message : "No se pudo buscar."); }
  }
  function validar(): string[] {
    const m: string[] = [];
    if (!sistema) m.push("Elija el sistema: acueducto o alcantarillado.");
    if (noIdent) { if (queEs.trim().length < 3) m.push("Diga qué es el activo no identificado (3 caracteres o más)."); if (eleccion?.tipo !== "punto") m.push("Toque el mapa donde está el daño."); }
    else if (eleccion?.tipo !== "activo") m.push("Elija el activo en el mapa (o márquelo como no identificado).");
    if (!tipo) m.push("Elija qué pasó.");
    if (!tDet) m.push("Escriba cuándo se detectó.");
    if (yaReparado && !tRep) m.push("Escriba el inicio de la reparación (o desmarque «El daño ya se reparó»).");
    if (yaReparado && tRes && tRep && new Date(tRes) < new Date(tRep)) m.push("El servicio restablecido no puede ser antes del inicio de la reparación.");
    if (tipoSel?.pide_rotura && !rotura) m.push("Elija el tipo de rotura.");
    // §25.4 (Corte 4a): todos los topes se revisan aquí antes de enviar (los mismos de la base)
    for (const [t, r, min, max, entero] of [[largo, "El largo afectado", 0, 10000, false], [presion, "La presión", 0, 300, false], [usuarios, "Los usuarios sin servicio", 0, 1000000, true],
                                            [sector, "El sector", 1, 100, true]] as const) {
      const n = numeroONulo(t);
      if (Number.isNaN(n)) m.push(`${r} debe ser un número.`);
      else if (n !== null && (n < min || n > max || (entero && !Number.isInteger(n)))) m.push(`${r} va de ${min} a ${max.toLocaleString("es-CO")}${entero ? ", sin decimales" : ""}.`);
    }
    if (causaClase === "terceros" && terceroNombre.trim().length === 1) m.push("El nombre, la empresa o la placa lleva de 2 a 120 caracteres.");
    if (!riesgo) m.push("Elija el riesgo.");
    if (!causaClase) m.push("Elija la causa: propia, de terceros o desconocida.");
    if (causaClase === "propia" && !causa) m.push("Elija la causa propia.");
    if (causaClase === "terceros" && !terceroTipo) m.push("Elija quién lo causó.");
    if (fotosDano < 1) m.push("Tome al menos una foto del daño.");
    if (fotos.length > def!.reglas.max_fotos) m.push(`Máximo ${def!.reglas.max_fotos} fotos.`);
    if (!ubic.fix && eleccion?.tipo !== "activo" && eleccion?.tipo !== "punto") m.push("Falta la ubicación del daño.");
    return m;
  }

  async function guardar() {
    const fotosTomadas = fotos;
    const m = validar(); setIntentado(true); setErrorEnvio(null);
    if (m.length) { document.querySelector(".dan-errores")?.scrollIntoView?.({ block: "center" }); return; }
    try {
      const fotos = sinFotos ? [] : fotosTomadas;
      if (!prep.current || prep.current.fotos.length !== fotos.length) { setEnviando("Preparando el envío…"); prep.current = await apiDano.preparar(fotos.length); subidas.current = new Set(); }
      const p = prep.current;
      for (let i = 0; i < fotos.length; i++) {
        if (subidas.current.has(i + 1)) continue;
        setEnviando(`Subiendo la foto ${i + 1} de ${fotos.length}…`);
        if (fotos[i].blob.size > p.max_bytes_foto) throw new Error(`La foto ${i + 1} pesa más de lo permitido.`);
        await subirFotoDano(p.fotos[i].url_subida, fotos[i].blob);
        subidas.current.add(i + 1);
      }
      setEnviando("Guardando el daño…");
      const punto = noIdent && eleccion?.tipo === "punto" ? { lat: eleccion.lat, lon: eleccion.lon, origen: "mapa", precision: null }
        : ubic.fix ? { lat: ubic.fix.lat, lon: ubic.fix.lon, origen: "gps", precision: Math.round(ubic.fix.precision_m) }
        : eleccion?.tipo === "activo" ? { lat: eleccion.activo.lat, lon: eleccion.activo.lon, origen: "activo", precision: null } : null;
      const datos = {
        clase, tipo, sistema, activo: !noIdent && eleccion?.tipo === "activo" ? eleccion.activo.codigo : null, no_identificado: noIdent ? queEs.trim() : null,
        lat: Number(punto!.lat.toFixed(6)), lon: Number(punto!.lon.toFixed(6)), precision_m: punto!.precision, ubicacion_origen: punto!.origen,
        t_inicio_dano: aIso(tIni), t_detectado: aIso(tDet), t_inicio_reparacion: yaReparado ? aIso(tRep) : null, t_restablecido: yaReparado ? aIso(tRes) : null, inicio_dispositivo: reloj.current.iso,
        tipo_rotura: tipoSel?.pide_rotura ? rotura : null, largo_afectado_m: tipoSel?.pide_rotura ? numeroONulo(largo) : null, presion_mca: tipoSel?.pide_rotura ? numeroONulo(presion) : null,
        usuarios_sin_servicio: numeroONulo(usuarios), sector: numeroONulo(sector), riesgo, marcas, causa_clase: causaClase,
        causa: causaClase === "propia" ? causa : null, tercero_tipo: causaClase === "terceros" ? terceroTipo : null,
        tercero_nombre: causaClase === "terceros" && terceroNombre.trim() ? terceroNombre.trim() : null, descripcion: descripcion.trim() || null,
        fotos: fotos.map((f, i) => ({ n: i + 1, momento: f.momento, ruta: p.fotos[i].ruta })),
      };
      ubicGuardada.current = { lat: datos.lat, lon: datos.lon };
      const hecho = await apiDano.crear(p.dano_id, datos);
      borrador.terminar();      // guardado con éxito: el borrador de este celular ya no hace falta
      setGuardado(hecho);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "No se pudo guardar.";
      if (msg === "vencida") { prep.current = null; setErrorEnvio("El permiso para subir las fotos venció. Pulse «Guardar» de nuevo: se pide uno nuevo."); }
      else if (esRechazoPorHora(msg)) { reloj.current = recalcularReloj(reloj.current); setErrorEnvio(msg); }
      else if (e instanceof ErrorTec && e.tipo === "red") setErrorEnvio("No hay señal o la conexión se cortó. Lo escrito y las fotos siguen aquí: pulse «Guardar» de nuevo (no se duplica).");
      else setErrorEnvio(msg);
    } finally { setEnviando(null); }
  }

  const errores = intentado ? validar() : [];

  if (guardado) {
    return (
      <>
      <section className="tec-tarjeta dan-listo" role="status">
        <h2>{clase === "dano" ? "Daño" : "Falla"} guardado: {guardado.codigo}</h2>
        <p>Estado: <strong>{guardado.estado === "reportado" ? "Reportado" : guardado.estado === "en_atencion" ? "En atención" : "Atendido"}</strong>{guardado.activo ? <> · activo <strong>{guardado.activo}</strong> (va a su epicrisis)</> : <> · activo no identificado (va a la bandeja del supervisor)</>}.</p>
        {guardado.fuera_de_zona ? <p className="tec-aviso tec-aviso-info">La ubicación quedó fuera de Valledupar: se guardó con esa marca.</p> : null}
        {guardado.sin_evidencia ? <p className="tec-aviso tec-aviso-info">Quedó marcado «sin evidencia fotográfica».</p> : null}
        <div className="tec-acciones">
          {onRegistrarReparacion && guardado.estado !== "atendido" && sistema ? (
            <button type="button" className="tec-boton" onClick={() => onRegistrarReparacion({ codigo: guardado.codigo, sistema, activo: guardado.activo, lat: ubicGuardada.current?.lat ?? 0, lon: ubicGuardada.current?.lon ?? 0 })}>
              Registrar la reparación</button>) : null}
          {guardado.activo ? <button type="button" className="tec-boton-sec" onClick={() => setFicha(guardado.activo!)}>Ver la ficha de {guardado.activo}</button> : null}
          <button type="button" className="tec-boton" onClick={() => onSalir?.()}>Reportar otro daño o falla</button>
        </div>
      </section>
      {/* Corte 9b: con el daño guardado ya se pueden marcar las válvulas cerradas y abiertas (solo acueducto) */}
      {sistema === "acueducto" ? <PanelCierre registro={guardado.codigo} activo={guardado.activo} punto={ubicGuardada.current} /> : null}
      </>
    );
  }

  const opcion = (sel: boolean, txt: string, f: () => void, key?: string) => <button key={key ?? txt} type="button" className="dan-opcion" aria-pressed={sel} onClick={f}>{txt}</button>;

  return (
    <div className="dan">
      <header className="dan-cabeza">
        <h1>Daño o falla</h1>
        <p>Lo registra el personal de Técnica. Va a la epicrisis del activo.</p>
      </header>

      <section className="tec-tarjeta" aria-labelledby="dan-t1">
        <h2 id="dan-t1">1. Activo y ubicación</h2>
        <div className="dan-fila" role="group" aria-label="Sistema">
          {def.sistemas.map((s) => opcion(sistema === s.codigo, s.nombre, () => elegirSistema(s.codigo as "acueducto" | "alcantarillado"), s.codigo))}
        </div>
        {!sistema ? <p className="tec-ayuda">Elija primero el sistema: el mapa muestra solo esa red.</p> : (
          <>
            <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
              <MiniMapaRed key={sistema} sistema={sistema} centro={ubic.fix ? { lat: ubic.fix.lat, lon: ubic.fix.lon } : null} eleccion={eleccion} modoPunto={noIdent}
                zoomMin={def.reglas.zoom_min} onElegir={(e) => { setEleccion(e); setAviso(null); }} />
            </Suspense>
            {aviso ? <p className="tec-aviso tec-aviso-info dan-aviso">{aviso}</p> : null}
            {!noIdent && eleccion?.tipo === "activo" ? (
              <div className="dan-elegido" aria-live="polite">
                <span className="red-icono" aria-hidden="true" />
                <div className="dan-elegido-txt">
                  <strong>{eleccion.activo.codigo}</strong>
                  <span>{detalle ? [detalle.activo.tipo, detalle.activo.clase, detalle.activo.material, detalle.activo.codigo_anterior].filter(Boolean).join(" · ") : "…"}</span>
                </div>
                <button type="button" className="tec-enlace" onClick={() => setFicha(eleccion.activo.codigo)}>Ver ficha</button>
              </div>
            ) : null}
            <div className="dan-buscar">
              <label htmlFor="dan-buscar" className="dan-rot">¿No aparece? Búsquelo por código</label>
              <div className="dan-buscar-fila">
                <input id="dan-buscar" type="text" autoComplete="off" maxLength={60} placeholder="RED-000123, V85, P1902…" value={buscar} onChange={(e) => setBuscar(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void hacerBusqueda(); } }} />
                <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => void hacerBusqueda()}>Buscar</button>
              </div>
              {resultados ? (resultados.length ? (
                <div className="red-lista">{resultados.map((r) => (
                  <button key={r.codigo} type="button" className="red-fila" onClick={() => { setEleccion({ tipo: "activo", activo: { ...r, estado: "", estado_codigo: "", retirado: false } }); setResultados(null); setNoIdent(false); }}>
                    <span className="red-icono" aria-hidden="true" /><span className="red-fila-txt"><span className="red-fila-cod">{r.codigo}</span><span className="red-fila-sub">{r.tipo}{r.clase ? ` · ${r.clase}` : ""}{r.codigo_anterior ? ` · ${r.codigo_anterior}` : ""}</span></span>
                  </button>))}</div>
              ) : <p className="tec-ayuda">No se encontró nada con «{buscar}» en {sistema}.</p>) : null}
            </div>
            <label className="dan-check">
              <input type="checkbox" checked={noIdent} onChange={(e) => { setNoIdent(e.target.checked); setEleccion(null); }} />
              No identifico el activo (marco el punto en el mapa; va a la bandeja del supervisor)
            </label>
            {noIdent ? (
              <div className="tec-campo">
                <label htmlFor="dan-quees">¿Qué es, según usted?</label>
                <input id="dan-quees" type="text" maxLength={120} value={queEs} onChange={(e) => setQueEs(e.target.value)} placeholder="Tubo que no sale en el mapa, cámara…" />
                {eleccion?.tipo === "punto" ? <span className="tec-ayuda">Punto marcado: {eleccion.lat.toFixed(5)}, {eleccion.lon.toFixed(5)}</span> : null}
              </div>
            ) : null}
            <p className="tec-ayuda">
              {ubic.fix ? <>Punto exacto del daño: GPS del celular · precisión ±{Math.round(ubic.fix.precision_m)} m{ubic.fix.precision_m > UMBRAL_PRECISION_MALA_M ? " (mala: si puede, espere a cielo abierto)" : ""}.</>
                : ubic.mensaje ? ubic.mensaje : "Buscando la ubicación del celular…"}
            </p>
          </>
        )}
      </section>

      {/* Corte 9b: «¿Qué válvulas cierro?» desde el activo o el punto elegido (solo la simulación; las válvulas se marcan con el daño guardado) */}
      {sistema === "acueducto" && (eleccion?.tipo === "activo" || eleccion?.tipo === "punto")
        ? <PanelCierre activo={eleccion.tipo === "activo" ? eleccion.activo.codigo : null} punto={eleccion.tipo === "punto" ? { lat: eleccion.lat, lon: eleccion.lon } : null} /> : null}

      <section className="tec-tarjeta" aria-labelledby="dan-t2">
        <h2 id="dan-t2">2. Qué pasó</h2>
        <div className="dan-fila" role="group" aria-label="Clase">
          {opcion(clase === "dano", "Daño", () => { setClase("dano"); setTipo(""); })}
          {opcion(clase === "falla", "Falla", () => { setClase("falla"); setTipo(""); })}
        </div>
        <p className="tec-ayuda">{clase === "dano" ? "Algo se rompió: la red pierde agua o el alcantarillado rebosa." : "Algo dejó de funcionar sin romperse: un equipo, una bomba o una válvula."}</p>
        <div className="dan-fila" role="group" aria-label="Qué pasó">{tipos.map((t) => opcion(tipo === t.codigo, t.nombre, () => setTipo(t.codigo), t.codigo))}</div>
      </section>

      <section className="tec-tarjeta" aria-labelledby="dan-t3">
        <h2 id="dan-t3">3. Tiempos</h2>
        {[["dan-tini", "Inicio del daño (si se sabe)", tIni, setTIni, "Cuándo empezó, según vecinos o PQR."], ["dan-tdet", "Detectado", tDet, setTDet, `Cuándo se supo del daño (hasta ${def.reglas.dias_atras_max} días atrás).`],
          ...(yaReparado ? [["dan-trep", "Inicio de la reparación", tRep, setTRep, "Llegada de la cuadrilla y comienzo del trabajo."], ["dan-tres", "Servicio restablecido", tRes, setTRes, "Fin de la reparación."]] : [])].map(([id, rot, v, set, ayuda]) => (
          <div className="tec-campo" key={id as string}>
            <label htmlFor={id as string}>{rot as string}</label>
            <input id={id as string} type="datetime-local" className="dan-hora" max={ahora} value={v as string} onChange={(e) => (set as (x: string) => void)(e.target.value)} />
            <span className="tec-ayuda">{ayuda as string}</span>
          </div>
        ))}
        <label className="dan-check"><input type="checkbox" checked={yaReparado} onChange={(e) => setYaReparado(e.target.checked)} />El daño ya se reparó (registrar los tiempos de la reparación)</label>
        <p className="tec-ayuda">{yaReparado ? "Con el servicio restablecido, el daño queda atendido de una vez." : "Lo normal: la reparación se registra después con «Registrar intervención», y ahí el daño queda atendido."}</p>
        <div className="dan-calculo">
          <div><span>Respuesta</span><strong>{respuesta ?? "—"}</strong></div>
          <div><span>Reparación</span><strong>{reparacion ?? "—"}</strong></div>
          <div><span>Total del daño</span><strong>{total ?? "corre"}</strong></div>
        </div>
        <p className="tec-ayuda">Se calculan solos. Mientras no haya servicio restablecido, el total corre.</p>
      </section>

      {tipoSel?.pide_rotura ? (
        <section className="tec-tarjeta" aria-labelledby="dan-t4">
          <h2 id="dan-t4">4. Tamaño del daño y posible pérdida</h2>
          <span className="dan-rot">Tipo de rotura</span>
          <div className="dan-fila" role="group" aria-label="Tipo de rotura">{def.roturas.map((r) => opcion(rotura === r.codigo, r.nombre, () => setRotura(r.codigo), r.codigo))}</div>
          <div className="dan-dos">
            <div className="tec-campo"><label htmlFor="dan-largo">Largo afectado (m)</label><input id="dan-largo" type="text" inputMode="decimal" value={largo} onChange={(e) => setLargo(e.target.value)} /></div>
            <div className="tec-campo"><label htmlFor="dan-presion">Presión en la zona (opcional, m.c.a.)</label><input id="dan-presion" type="text" inputMode="decimal" value={presion} onChange={(e) => setPresion(e.target.value)} /></div>
          </div>
          <p className="dan-perdida">{def.hay_tabla_caudales ? "La posible pérdida de agua se calcula al guardar, con la tabla de caudales de Técnica." : "Posible pérdida de agua: sin tabla. Se calculará cuando Técnica entregue la tabla de caudales por diámetro, tipo de rotura y presión."}</p>
        </section>
      ) : null}

      <section className="tec-tarjeta" aria-labelledby="dan-t5">
        <h2 id="dan-t5">{tipoSel?.pide_rotura ? "5" : "4"}. Afectación y riesgo</h2>
        <div className="dan-dos">
          <div className="tec-campo"><label htmlFor="dan-usuarios">Usuarios sin servicio (aprox.)</label><input id="dan-usuarios" type="text" inputMode="numeric" value={usuarios} onChange={(e) => setUsuarios(e.target.value)} /></div>
          <div className="tec-campo"><label htmlFor="dan-sector">Sector hidráulico (sale de la ubicación)</label>
            <input id="dan-sector" type="text" inputMode="numeric" maxLength={3} placeholder="1 a 100" value={sector}
              onChange={(e) => { const v = e.target.value.replace(/[^0-9]/g, ""); sectorAuto.current = v === ""; setSector(v); }} />
            {sectorProp?.sector ? (
              sector === String(sectorProp.sector)
                ? <p className="dan-sector-prop" data-sector-propuesto>Por la ubicación: sector {sectorProp.sector}{sectorProp.subsector ? `, subsector ${sectorProp.subsector}` : ""}.</p>
                : <p className="dan-sector-prop dan-sector-prop-dif" data-sector-propuesto>Por la ubicación sería el sector {sectorProp.sector}{sectorProp.subsector ? ` (${sectorProp.subsector})` : ""}. Queda el que usted escribió.</p>
            ) : sectorProp ? <p className="dan-sector-prop dan-sector-prop-dif" data-sector-propuesto>La ubicación no cae en ningún sector: escríbalo si lo sabe.</p> : null}
          </div>
        </div>
        <span className="dan-rot">Riesgo</span>
        <div className="dan-fila" role="group" aria-label="Riesgo">{RIESGOS.map((r) => opcion(riesgo === r.c, r.n, () => setRiesgo(r.c), r.c))}</div>
        <div className="dan-marcas">{def.marcas.map((m) => (
          <label key={m.codigo} className="dan-check"><input type="checkbox" checked={marcas.includes(m.codigo)} onChange={(e) => setMarcas((x) => e.target.checked ? [...x, m.codigo] : x.filter((c) => c !== m.codigo))} />{m.nombre}</label>))}</div>
      </section>

      <section className="tec-tarjeta" aria-labelledby="dan-t6">
        <h2 id="dan-t6">{tipoSel?.pide_rotura ? "6" : "5"}. Causa</h2>
        <div className="dan-fila" role="group" aria-label="Causa">{CAUSAS.map((c) => opcion(causaClase === c.c, c.n, () => setCausaClase(c.c), c.c))}</div>
        {causaClase === "propia" ? (
          <div className="tec-campo"><label htmlFor="dan-causa">Causa propia</label>
            <select id="dan-causa" value={causa} onChange={(e) => setCausa(e.target.value)}><option value="">Elija…</option>{def.causas.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
        ) : null}
        {causaClase === "terceros" ? (
          <>
            <div className="tec-campo"><label htmlFor="dan-tercero">Quién lo causó</label>
              <select id="dan-tercero" value={terceroTipo} onChange={(e) => setTerceroTipo(e.target.value)}><option value="">Elija…</option>{def.terceros.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
            <div className="tec-campo"><label htmlFor="dan-tnombre">Nombre, empresa o placa (si se sabe)</label>
              <input id="dan-tnombre" type="text" maxLength={120} autoComplete="off" value={terceroNombre} onChange={(e) => setTerceroNombre(e.target.value)} />
              <span className="tec-ayuda">Es un dato personal: se guarda aparte y solo lo ve el supervisor. Las fotos y los tiempos sirven de soporte para el cobro o la reclamación.</span></div>
          </>
        ) : null}
      </section>

      <section className="tec-tarjeta" aria-labelledby="dan-t7">
        <h2 id="dan-t7">{tipoSel?.pide_rotura ? "7" : "6"}. Fotos</h2>
        <p className="tec-ayuda">{sinFotos ? "Sin fotos: queda marcado «sin evidencia fotográfica»." : `Al menos una del daño. Máximo ${def.reglas.max_fotos}. Solo cámara. Mientras llena el formulario, las fotos quedan en el borrador de este celular; se borran al guardar o al cancelar.`}</p>
        {!sinFotos ? <div className="dan-fila">{MOMENTOS.map((m) => (
          <button key={m.c} type="button" className="tec-boton-sec" disabled={fotos.length >= def.reglas.max_fotos || !!enviando} onClick={() => setCamara(m.c)}><IconoCamara />Foto: {m.n}</button>))}</div> : null}
        {camara ? (
          <CamaraActa rotulo={`Foto: ${MOMENTOS.find((m) => m.c === camara)!.n.toLowerCase()}`} maxBytes={def.reglas.max_bytes_foto}
            sello={() => [new Date().toLocaleString("es-CO"), ubic.fix ? `${ubic.fix.lat.toFixed(5)}, ${ubic.fix.lon.toFixed(5)}` : "sin GPS"]}
            onFoto={({ blob }) => { setFotos((f) => [...f, { blob, momento: camara, url: URL.createObjectURL(blob) }]); prep.current = null; setCamara(null); }}
            onCerrar={() => setCamara(null)} />
        ) : null}
        {fotos.length && !sinFotos ? <div className="dan-fotos">{fotos.map((f, i) => (
          <figure key={f.url} className="dan-foto">
            <img src={f.url} alt={`Foto ${i + 1}: ${MOMENTOS.find((m) => m.c === f.momento)!.n}`} />
            <figcaption>{i + 1}. {MOMENTOS.find((m) => m.c === f.momento)!.n}
              <button type="button" className="tec-enlace" disabled={!!enviando} onClick={() => { URL.revokeObjectURL(f.url); setFotos((x) => x.filter((_, j) => j !== i)); prep.current = null; }}>Quitar</button></figcaption>
          </figure>))}</div> : null}
        <div className="tec-campo"><label htmlFor="dan-desc">Descripción (opcional)</label>
          <textarea id="dan-desc" className="dan-texto" maxLength={1000} rows={3} value={descripcion} onChange={(e) => setDescripcion(e.target.value)} /></div>
      </section>

      {errores.length ? <div className="tec-aviso tec-aviso-error dan-errores dan-pad-x" role="alert"><strong>Falta completar:</strong><ul>{errores.map((e) => <li key={e}>{e}</li>)}</ul></div> : null}
      {errorEnvio ? <p className="tec-aviso tec-aviso-error dan-pad-x" role="alert">{errorEnvio}</p> : null}
      {cancelar ? (
        <div className="dan-pad-x">
          <ConfirmarCancelar titulo="¿Cancelar este daño o falla?" mensaje="Se borra lo escrito y las fotos de este celular. En el servidor no queda nada." onSeguir={() => setCancelar(false)}
            onConfirmar={() => { setCancelar(false); borrador.terminar(); onSalir?.(); }} />
        </div>
      ) : (
        <div className="tec-acciones dan-pad-x">
          <button type="button" className="tec-boton dan-guardar" disabled={!!enviando} onClick={() => void guardar()}>{enviando ?? "Guardar daño o falla"}</button>
          <button type="button" className="tec-boton-sec" disabled={!!enviando} onClick={() => setCancelar(true)}>Cancelar</button>
        </div>
      )}
      <p className="tec-sub dan-pad-x">Sesión de {correo}</p>
    </div>
  );
}
