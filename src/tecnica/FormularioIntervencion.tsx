import { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
import "./ficha.css";
import "./dano.css";
import "./intervencion.css";
import { apiDano, apiItv, apiRedes, subirArchivo, type ActivoCorto, type ActivoUbicado, type DanoAbierto, type Ficha, type FormularioIntervencion as Def,
  type IntervencionGuardada, type PreparacionIntervencion } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { useUbicacion, UMBRAL_PRECISION_MALA_M } from "../campo/ubicacion";
import { abrirReloj, esRechazoPorHora, recalcularReloj, type RelojInicio } from "../campo/inicio";
import { CamaraActa } from "../campo/acta/CamaraActa";
import { ConfirmarCancelar } from "../components/ConfirmarCancelar";
import { FichaActivo } from "./FichaActivo";
import type { Eleccion } from "./MiniMapaRed";

// «Registrar intervención» (Corte 3a), como la maqueta Intervencion.dc.html. Formulario «mantenimiento» de Técnica · distribución. Flujo A (D-6): se registra después de hecha.
// 1 de dónde nace (programada o mejora, o el daño abierto del activo o de los cercanos) y tipo (inversión: activo nuevo o mejora) · 2 activo (el mismo minimapa del
//   Corte 2; «no identificado» marcando el punto; en una inversión con activo nuevo, se marca dónde quedó) y los también intervenidos · 3 inicio y fin · 4 qué se hizo
//   y materiales · 5 quién la ejecuta · 6 de dónde salen los recursos (el operario marca solo quién aporta; el supervisor pone valor, porcentaje y soporte, D-8) ·
//   7 fotos de antes, durante y después y documentos PDF.
// En la calle, siempre al menos una foto; sin fotos solo el supervisor o el administrador, con el motivo («sin evidencia fotográfica»). Las reglas las decide el servidor.
// Sin términos tarifarios. Al cerrar una intervención que nace de un daño, el daño queda atendido con sus tiempos.

const MiniMapaRed = lazy(() => import("./MiniMapaRed").then((m) => ({ default: m.MiniMapaRed })));
type Clase = "antes" | "durante" | "despues";
type Foto = { blob: Blob; clase: Clase; url: string };
type Doc = { archivo: File };
type Material = { id: number; material: string; cantidad: string; unidad: string };
type FuenteSel = { aportante: string; entidad: string; valor: string; porcentaje: string; soporte: string };
export type DesdeDano = { codigo: string; sistema: "acueducto" | "alcantarillado"; activo: string | null; lat: number; lon: number };
const CLASES: { c: Clase; n: string }[] = [{ c: "antes", n: "Antes" }, { c: "durante", n: "Durante" }, { c: "despues", n: "Después" }];

const aLocal = (d: Date) => { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 16); };
const aIso = (v: string) => (v ? new Date(v).toISOString() : null);
function duracion(desde: string, hasta: string): string | null {
  if (!desde || !hasta) return null;
  const s = (new Date(hasta).getTime() - new Date(desde).getTime()) / 1000;
  if (!Number.isFinite(s) || s < 0) return null;
  const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
  return `${h} h ${String(m).padStart(2, "0")} min`;
}
const numeroONulo = (t: string) => { const v = t.trim().replace(/\./g, "").replace(",", "."); if (!v) return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };
const decimalONulo = (t: string) => { const v = t.trim().replace(",", "."); if (!v) return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };
const fechaCorta = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export function FormularioIntervencion({ correo, desdeDano, activoInicial, onSalir }: {
  correo: string; desdeDano?: DesdeDano | null; activoInicial?: { codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number } | null; onSalir?: () => void;
}) {
  const [def, setDef] = useState<Def | null>(null);
  const [errorDef, setErrorDef] = useState<string | null>(null);
  const ubic = useUbicacion();
  const reloj = useRef<RelojInicio>(abrirReloj());
  const apertura = useMemo(() => aLocal(new Date()), []);
  // 1. de dónde nace y tipo
  const [nace, setNace] = useState<"programada" | "dano">(desdeDano ? "dano" : "programada");
  const [tipo, setTipo] = useState<string>(desdeDano ? "reparacion" : "");
  const [modo, setModo] = useState<"nuevo" | "mejora" | "">("");
  const [danos, setDanos] = useState<DanoAbierto[] | null>(null);
  const [dano, setDano] = useState<string>(desdeDano?.codigo ?? "");
  const [resuelve, setResuelve] = useState(false);      // «Con esta queda resuelto el daño» (David, respuesta 2 al 3a): sin marcarla, el daño sigue en atención
  // 2. activo
  const ini = desdeDano ?? activoInicial ?? null;
  const [sistema, setSistema] = useState<"acueducto" | "alcantarillado" | null>(ini?.sistema ?? null);
  const inicialActivo = desdeDano?.activo ?? activoInicial?.codigo ?? null;
  const [eleccion, setEleccion] = useState<Eleccion | null>(inicialActivo && ini
    ? { tipo: "activo", activo: { codigo: inicialActivo, prefijo: inicialActivo.slice(0, 3), tipo: "", estado: "", estado_codigo: "", retirado: false, lat: ini.lat, lon: ini.lon } }
    : desdeDano ? { tipo: "punto", lat: desdeDano.lat, lon: desdeDano.lon } : null);
  const [noIdent, setNoIdent] = useState(!!desdeDano && !desdeDano.activo);
  const [queEs, setQueEs] = useState("");
  const [detalle, setDetalle] = useState<Ficha | null>(null);
  const [buscar, setBuscar] = useState("");
  const [resultados, setResultados] = useState<ActivoUbicado[] | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [nuevoTipo, setNuevoTipo] = useState(""); const [nuevoClase, setNuevoClase] = useState(""); const [nuevoMaterial, setNuevoMaterial] = useState("");
  const [nuevoDiam, setNuevoDiam] = useState(""); const [nuevoNombre, setNuevoNombre] = useState("");
  const [tambien, setTambien] = useState<ActivoCorto[]>([]);
  const [cercanos, setCercanos] = useState<ActivoCorto[]>([]);
  const [buscarT, setBuscarT] = useState(""); const [resultadosT, setResultadosT] = useState<ActivoUbicado[] | null>(null);
  // 3 a 7
  const [tIni, setTIni] = useState(apertura); const [tFin, setTFin] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [materiales, setMateriales] = useState<Material[]>([]);
  const sigMat = useRef(1);
  const [ejecutor, setEjecutor] = useState<"emdupar" | "contratista">("emdupar");
  const [contratista, setContratista] = useState(""); const [contratistaNombre, setContratistaNombre] = useState(""); const [orden, setOrden] = useState(""); const [companeros, setCompaneros] = useState("");
  const [fuentes, setFuentes] = useState<FuenteSel[]>([{ aportante: "emdupar", entidad: "", valor: "", porcentaje: "", soporte: "" }]);
  const [fotos, setFotos] = useState<Foto[]>([]);
  const [docs, setDocs] = useState<Doc[]>([]);
  const [camara, setCamara] = useState<Clase | null>(null);
  const [sinFotos, setSinFotos] = useState(false); const [sinFotosMotivo, setSinFotosMotivo] = useState("");
  const [intentado, setIntentado] = useState(false);
  const [enviando, setEnviando] = useState<string | null>(null);
  const [errorEnvio, setErrorEnvio] = useState<string | null>(null);
  const prep = useRef<PreparacionIntervencion | null>(null);
  const subidas = useRef<Set<number>>(new Set());
  const [guardado, setGuardado] = useState<IntervencionGuardada | null>(null);
  const [cancelar, setCancelar] = useState(false);
  const [ficha, setFicha] = useState<string | null>(null);
  const cercanoPedido = useRef<string | null>(inicialActivo ? "ya" : null);

  useEffect(() => {
    apiItv.formulario().then(setDef).catch((e) => setErrorDef(e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene asignado el formulario de intervenciones." : e instanceof Error ? e.message : "No se pudo cargar."));
  }, []);

  const esInversion = !!def?.tipos.find((t) => t.codigo === tipo)?.es_inversion;
  const esNuevo = esInversion && modo === "nuevo";
  const tipoNuevo = def?.tipos_nuevo.find((t) => t.prefijo === nuevoTipo) ?? null;
  const activoSel = !noIdent && !esNuevo && eleccion?.tipo === "activo" ? eleccion.activo : null;

  // activo más cercano preseleccionado (una vez por sistema, con GPS), como en el daño
  useEffect(() => {
    if (!sistema || !ubic.fix || cercanoPedido.current === sistema || eleccion || noIdent || esNuevo) return;
    cercanoPedido.current = sistema;
    apiRedes.cercanos(ubic.fix.lat, ubic.fix.lon, sistema, def?.reglas.radio_cercanos_m)
      .then((r) => { const a = r.activos[0]; if (a) { setEleccion({ tipo: "activo", activo: { ...a, lat: ubic.fix!.lat, lon: ubic.fix!.lon } }); setAviso(`Se preseleccionó el activo más cercano (${a.codigo}, a ${Math.round(a.distancia_m ?? 0)} m). Si no es, toque otro en el mapa.`); }
                      else setAviso(`No hay activos de ${sistema} a ${r.radio_m} m. Toque el activo en el mapa o búsquelo por código.`); })
      .catch(() => setAviso("No se pudo buscar el activo más cercano. Tóquelo en el mapa o búsquelo por código."));
  }, [sistema, ubic.fix, def, noIdent, esNuevo]); // eslint-disable-line react-hooks/exhaustive-deps

  // tarjeta del activo elegido y propuesta de «también intervenidos» (los más cercanos al elegido)
  useEffect(() => {
    setDetalle(null); setCercanos([]);
    if (!activoSel || !sistema) return;
    let vivo = true;
    apiRedes.activo(activoSel.codigo).then((f) => {
      if (!vivo) return;
      setDetalle(f);
      apiRedes.cercanos(f.activo.lat, f.activo.lon, sistema, 40).then((r) => { if (vivo) setCercanos(r.activos.filter((x) => x.codigo !== activoSel.codigo).slice(0, 6)); }).catch(() => {});
    }).catch(() => {});
    return () => { vivo = false; };
  }, [activoSel?.codigo, sistema]); // eslint-disable-line react-hooks/exhaustive-deps

  // daños abiertos que puede atender: del activo o de los cercanos (o cerca del punto marcado o del GPS)
  const refDanos = activoSel ? `a:${activoSel.codigo}` : eleccion?.tipo === "punto" ? `p:${eleccion.lat.toFixed(5)},${eleccion.lon.toFixed(5)}` : ubic.fix ? `p:${ubic.fix.lat.toFixed(4)},${ubic.fix.lon.toFixed(4)}` : "";
  useEffect(() => {
    if (nace !== "dano" || !sistema || !refDanos) { setDanos(null); return; }
    let vivo = true;
    const ref = activoSel ? { activo: activoSel.codigo } : eleccion?.tipo === "punto" ? { lat: eleccion.lat, lon: eleccion.lon } : { lat: ubic.fix!.lat, lon: ubic.fix!.lon };
    apiItv.danosAbiertos(sistema, ref).then((r) => { if (vivo) setDanos(r.danos); }).catch(() => { if (vivo) setDanos([]); });
    return () => { vivo = false; };
  }, [nace, sistema, refDanos]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => () => fotos.forEach((f) => URL.revokeObjectURL(f.url)), []); // eslint-disable-line react-hooks/exhaustive-deps

  if (ficha) return <FichaActivo codigo={ficha} onAbrir={setFicha} onVolver={() => setFicha(null)} rotuloVolver="Volver a la intervención" />;
  if (errorDef) return <section className="tec-tarjeta" role="alert"><h2>Registrar intervención</h2><p>{errorDef}</p></section>;
  if (!def) return <p className="tec-sub dan-pad" role="status">Cargando el formulario…</p>;
  const reglas = def.reglas;
  const tipos = def.tipos.filter((t) => nace === "programada" || t.admite_dano);
  const tiposNuevo = def.tipos_nuevo.filter((t) => t.sistema === sistema);
  const dur = duracion(tIni, tFin);
  const apoderado = reglas.pone_valores;

  function elegirSistema(s: "acueducto" | "alcantarillado") {
    if (s === sistema) return;
    setSistema(s); setEleccion(null); setResultados(null); setAviso(null); setTambien([]); setDano(""); setNuevoTipo(""); setNuevoClase("");
  }
  function elegirNace(n: "programada" | "dano") {
    setNace(n); setDano("");
    const t = def!.tipos.find((x) => x.codigo === tipo);
    if (n === "dano" && t && !t.admite_dano) { setTipo("reparacion"); setModo(""); }
  }
  function elegirTipo(c: string) {
    setTipo(c);
    if (!def!.tipos.find((t) => t.codigo === c)?.es_inversion) setModo("");
  }
  function elegirModo(m: "nuevo" | "mejora") {
    setModo(m); setEleccion(null); setNoIdent(false); setAviso(null);
  }
  async function hacerBusqueda(texto: string, set: (r: ActivoUbicado[] | null) => void) {
    if (!sistema || texto.trim().length < 2) return;
    try { set((await apiDano.buscar(texto.trim(), sistema)).activos); } catch (e) { setAviso(e instanceof Error ? e.message : "No se pudo buscar."); }
  }
  function agregarTambien(a: ActivoCorto) {
    if (a.codigo === activoSel?.codigo || tambien.some((x) => x.codigo === a.codigo) || tambien.length >= reglas.max_tambien) return;
    setTambien((t) => [...t, a]);
  }
  const fotosN = fotos.length;

  function validar(): string[] {
    const m: string[] = [];
    if (!tipo) m.push("Elija el tipo de intervención.");
    if (esInversion && !modo) m.push("Diga si la inversión es un activo nuevo o la mejora de uno existente.");
    if (nace === "dano" && !dano) m.push("Elija el daño o falla que se atiende.");
    if (!sistema) m.push("Elija el sistema: acueducto o alcantarillado.");
    if (esNuevo) {
      if (!tipoNuevo) m.push("Elija el tipo del activo nuevo.");
      else {
        if (tipoNuevo.clase_obligatoria && !nuevoClase) m.push(`Elija la clase del activo nuevo (${tipoNuevo.nombre}).`);
        if (tipoNuevo.geometria === "linea" && !(eleccion?.tipo === "linea" && eleccion.puntos.length >= 2)) m.push("Toque en el mapa el inicio y el fin del tramo nuevo.");
        if (tipoNuevo.geometria === "punto" && eleccion?.tipo !== "punto") m.push("Toque en el mapa dónde quedó el activo nuevo.");
      }
      if (Number.isNaN(decimalONulo(nuevoDiam))) m.push("El diámetro debe ser un número.");
    } else if (noIdent) { if (queEs.trim().length < 3) m.push("Diga qué es el activo no identificado (3 caracteres o más)."); if (eleccion?.tipo !== "punto") m.push("Toque el mapa donde está la intervención."); }
    else if (eleccion?.tipo !== "activo") m.push("Elija el activo en el mapa (o márquelo como no identificado).");
    if (!tIni || !tFin) m.push("Escriba el inicio y el fin de la intervención.");
    else if (new Date(tFin) < new Date(tIni)) m.push("El fin no puede ser antes del inicio.");
    if (descripcion.trim().length < 10) m.push("Describa qué se hizo (10 caracteres o más).");
    for (const x of materiales) {
      if (x.material.trim().length < 2) m.push("Cada material lleva su nombre.");
      const c = decimalONulo(x.cantidad); if (c === null || Number.isNaN(c) || c <= 0) m.push(`Escriba la cantidad de «${x.material || "material"}».`);
    }
    if (ejecutor === "contratista" && !contratista && contratistaNombre.trim().length < 2) m.push("Elija o escriba el contratista.");
    if (!fuentes.length) m.push("Marque quién aporta los recursos.");
    if (fuentes.some((f) => f.aportante === "otro" && f.entidad.trim().length < 2)) m.push("Diga cuál es la otra entidad que aporta.");
    if (apoderado) for (const f of fuentes) { if (Number.isNaN(numeroONulo(f.valor))) m.push("El valor debe ser un número."); if (Number.isNaN(decimalONulo(f.porcentaje))) m.push("El porcentaje debe ser un número."); }
    if (sinFotos) { if (sinFotosMotivo.trim().length < 10) m.push("Escriba por qué no hay evidencia fotográfica (10 caracteres o más)."); }
    else if (fotosN < Math.max(1, reglas.min_fotos)) m.push("Tome al menos una foto de la intervención.");
    if (fotosN > reglas.max_fotos) m.push(`Máximo ${reglas.max_fotos} fotos.`);
    if (!ubic.fix && !(eleccion?.tipo === "activo" || eleccion?.tipo === "punto" || eleccion?.tipo === "linea")) m.push("Falta la ubicación de la intervención.");
    return m;
  }

  async function guardar() {
    const m = validar(); setIntentado(true); setErrorEnvio(null);
    if (m.length) { document.querySelector(".dan-errores")?.scrollIntoView?.({ block: "center" }); return; }
    const fs = sinFotos ? [] : fotos;
    try {
      if (!prep.current || prep.current.fotos.length !== fs.length || prep.current.documentos.length !== docs.length) {
        setEnviando("Preparando el envío…"); prep.current = await apiItv.preparar(fs.length, docs.length); subidas.current = new Set();
      }
      const p = prep.current;
      for (let i = 0; i < fs.length; i++) {
        if (subidas.current.has(p.fotos[i].n)) continue;
        setEnviando(`Subiendo la foto ${i + 1} de ${fs.length}…`);
        if (fs[i].blob.size > p.max_bytes_foto) throw new Error(`La foto ${i + 1} pesa más de lo permitido.`);
        await subirArchivo(p.fotos[i].url_subida, fs[i].blob, "image/jpeg");
        subidas.current.add(p.fotos[i].n);
      }
      for (let i = 0; i < docs.length; i++) {
        if (subidas.current.has(p.documentos[i].n)) continue;
        setEnviando(`Subiendo el documento ${i + 1} de ${docs.length}…`);
        if (docs[i].archivo.size > p.max_bytes_documento) throw new Error(`El documento «${docs[i].archivo.name}» pesa más de ${Math.round(p.max_bytes_documento / 1048576)} MB.`);
        await subirArchivo(p.documentos[i].url_subida, docs[i].archivo, "application/pdf");
        subidas.current.add(p.documentos[i].n);
      }
      setEnviando("Guardando la intervención…");
      const marcado = eleccion?.tipo === "punto" ? eleccion : eleccion?.tipo === "linea" ? eleccion.puntos[0] : null;
      const punto = (noIdent || esNuevo) && marcado ? { lat: marcado.lat, lon: marcado.lon, origen: "mapa", precision: null as number | null }
        : ubic.fix ? { lat: ubic.fix.lat, lon: ubic.fix.lon, origen: "gps", precision: Math.round(ubic.fix.precision_m) }
        : eleccion?.tipo === "activo" ? { lat: eleccion.activo.lat, lon: eleccion.activo.lon, origen: "activo", precision: null } : null;
      const r6 = (n: number) => Number(n.toFixed(6));
      const datos: Record<string, unknown> = {
        nace_de: nace, dano: nace === "dano" ? dano : null, resuelve_dano: nace === "dano" && resuelve, tipo, inversion_modo: esInversion ? modo : null, sistema,
        activo: activoSel?.codigo ?? null, no_identificado: noIdent && !esNuevo ? queEs.trim() : null,
        nuevo: esNuevo && tipoNuevo ? { prefijo: tipoNuevo.prefijo, clase: nuevoClase || null, material: nuevoMaterial || null, diametro_mm: decimalONulo(nuevoDiam), nombre: nuevoNombre.trim() || null,
          puntos: (eleccion?.tipo === "linea" ? eleccion.puntos : eleccion?.tipo === "punto" ? [eleccion] : []).map((x) => [r6(x.lat), r6(x.lon)]) } : null,
        lat: r6(punto!.lat), lon: r6(punto!.lon), precision_m: punto!.precision, ubicacion_origen: punto!.origen,
        t_inicio: aIso(tIni), t_fin: aIso(tFin), inicio_dispositivo: reloj.current.iso, descripcion: descripcion.trim(),
        materiales: materiales.map((x) => ({ material: x.material.trim(), cantidad: decimalONulo(x.cantidad), unidad: x.unidad })),
        ejecutor, contratista: ejecutor === "contratista" && contratista ? contratista : null,
        contratista_nombre: ejecutor === "contratista" && !contratista ? contratistaNombre.trim() || null : null, contrato_orden: orden.trim() || null, companeros: companeros.trim() || null,
        tambien: tambien.map((t) => t.codigo),
        fuentes: fuentes.map((f) => ({ aportante: f.aportante, entidad: f.entidad.trim() || null,
          ...(apoderado ? { valor: numeroONulo(f.valor), porcentaje: decimalONulo(f.porcentaje), soporte: f.soporte.trim() || null } : {}) })),
        sin_evidencia_motivo: sinFotos ? sinFotosMotivo.trim() : null,
        archivos: [...fs.map((f, i) => ({ n: p.fotos[i].n, clase: f.clase, ruta: p.fotos[i].ruta })), ...docs.map((_, i) => ({ n: p.documentos[i].n, clase: "documento", ruta: p.documentos[i].ruta }))],
      };
      setGuardado(await apiItv.crear(p.intervencion_id, datos));
    } catch (e) {
      const msg = e instanceof Error ? e.message : "No se pudo guardar.";
      if (msg === "vencida") { prep.current = null; setErrorEnvio("El permiso para subir los archivos venció. Pulse «Guardar» de nuevo: se pide uno nuevo."); }
      else if (esRechazoPorHora(msg)) { reloj.current = recalcularReloj(reloj.current); setErrorEnvio(msg); }
      else if (e instanceof ErrorTec && e.tipo === "red") setErrorEnvio("No hay señal o la conexión se cortó. Lo escrito y las fotos siguen aquí: pulse «Guardar» de nuevo (no se duplica).");
      else setErrorEnvio(msg);
    } finally { setEnviando(null); }
  }

  const errores = intentado ? validar() : [];

  if (guardado) {
    return (
      <section className="tec-tarjeta dan-listo itv-listo" role="status">
        <h2>Intervención guardada: {guardado.codigo}</h2>
        <p>Estado: <strong>Cerrada</strong>{guardado.activo ? <> · activo <strong>{guardado.activo}</strong>{guardado.activo_creado ? " (nuevo, queda por verificar)" : ""} (va a su epicrisis)</> : <> · activo no identificado (va a la bandeja del supervisor)</>}.</p>
        {guardado.dano ? (guardado.dano_estado === "atendido"
          ? <p>El daño <strong>{guardado.dano}</strong> quedó <strong>atendido</strong>, con los tiempos de esta intervención.</p>
          : <p>El daño <strong>{guardado.dano}</strong> sigue <strong>en atención</strong>: quedará atendido con la intervención que lo resuelva.</p>) : null}
        {guardado.sin_evidencia ? <p className="tec-aviso tec-aviso-info">Quedó marcada «sin evidencia fotográfica».</p> : null}
        {guardado.recursos === "por_completar" ? <p className="tec-ayuda">El supervisor completará el valor, el porcentaje y el soporte de los recursos.</p> : null}
        {guardado.fuera_de_zona ? <p className="tec-aviso tec-aviso-info">La ubicación quedó fuera de Valledupar: se guardó con esa marca.</p> : null}
        <div className="tec-acciones">
          {guardado.activo ? <button type="button" className="tec-boton-sec" onClick={() => setFicha(guardado.activo!)}>Ver la ficha de {guardado.activo}</button> : null}
          <button type="button" className="tec-boton" onClick={() => onSalir?.()}>Registrar otra intervención</button>
        </div>
      </section>
    );
  }

  const opcion = (sel: boolean, txt: string, f: () => void, key?: string, extra = "") => <button key={key ?? txt} type="button" className={`dan-opcion ${extra}`} aria-pressed={sel} onClick={f}>{txt}</button>;
  const modoMapa: "activo" | "punto" | "linea" = esNuevo ? (tipoNuevo?.geometria === "linea" ? "linea" : "punto") : noIdent ? "punto" : "activo";

  return (
    <div className="dan itv">
      <header className="dan-cabeza itv-cabeza">
        <h1>Registrar intervención</h1>
        <p>Se registra cuando ya se hizo. Va a la epicrisis del activo.</p>
      </header>

      <section className="tec-tarjeta" aria-labelledby="itv-t1">
        <h2 id="itv-t1">1. De dónde nace y tipo</h2>
        <div className="dan-fila" role="group" aria-label="De dónde nace">
          {opcion(nace === "programada", "Programada o mejora", () => elegirNace("programada"))}
          {opcion(nace === "dano", "Daño o falla", () => elegirNace("dano"), undefined, "itv-op-dano")}
        </div>
        {nace === "dano" ? (
          <div className="itv-danos" role="radiogroup" aria-label="Daño o falla que se atiende">
            <span className="dan-rot">Daño o falla que se atiende</span>
            {!sistema || !refDanos ? <p className="tec-ayuda">Elija primero el sistema y el activo (sección 2): salen los daños abiertos de ese activo o de los cercanos.</p>
              : danos === null ? <p className="tec-sub" role="status">Buscando los daños abiertos…</p>
              : danos.length === 0 ? <p className="tec-ayuda">No hay daños abiertos de este activo ni a {reglas.radio_danos_m} m. Si el daño no está reportado, repórtelo primero en «Daño o falla».</p>
              : danos.map((d) => (
                <button key={d.codigo} type="button" role="radio" aria-checked={dano === d.codigo} className="itv-dano" onClick={() => setDano(d.codigo)}>
                  <strong>{d.codigo}</strong> · {d.tipo}{d.activo ? ` en ${d.activo}` : d.no_identificado ? ` (${d.no_identificado})` : ""}
                  <span>{fechaCorta(d.t_detectado)} · {d.estado === "en_atencion" ? "en atención" : "reportado"} · {d.mismo_activo ? "mismo activo" : `a ${d.distancia_m} m`}</span>
                </button>))}
            <p className="tec-ayuda">Solo salen los daños abiertos de este activo o de los cercanos. Un daño puede tener varias intervenciones.</p>
            <label className="dan-check itv-resuelve"><input type="checkbox" checked={resuelve} onChange={(e) => setResuelve(e.target.checked)} />Con esta queda resuelto el daño</label>
            <p className="tec-ayuda">{resuelve ? "Al guardar, el daño queda atendido con el fin de esta intervención como servicio restablecido." : "Sin marcarla, el daño sigue en atención (por ejemplo, si falta otra cuadrilla o la reposición)."}</p>
          </div>
        ) : null}
        <span className="dan-rot">Tipo</span>
        <div className="dan-fila" role="group" aria-label="Tipo de intervención">{tipos.map((t) => opcion(tipo === t.codigo, t.nombre, () => elegirTipo(t.codigo), t.codigo))}</div>
        {esInversion ? (
          <>
            <span className="dan-rot">¿Qué tipo de inversión?</span>
            <div className="dan-fila" role="group" aria-label="Tipo de inversión">
              {opcion(modo === "nuevo", "Activo nuevo", () => elegirModo("nuevo"), undefined, "itv-op-inv")}
              {opcion(modo === "mejora", "Mejora de un activo existente", () => elegirModo("mejora"), undefined, "itv-op-inv")}
            </div>
            {modo ? <p className="tec-ayuda">{modo === "nuevo" ? "Se crea el activo con su ficha al guardar; el supervisor lo verifica." : "La inversión queda en la epicrisis del activo que elija abajo."}</p> : null}
          </>
        ) : null}
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t2">
        <h2 id="itv-t2">2. {esNuevo ? "Activo nuevo" : "Activo"}</h2>
        <div className="dan-fila" role="group" aria-label="Sistema">
          {def.sistemas.map((s) => opcion(sistema === s.codigo, s.nombre, () => elegirSistema(s.codigo as "acueducto" | "alcantarillado"), s.codigo))}
        </div>
        {!sistema ? <p className="tec-ayuda">Elija primero el sistema: el mapa muestra solo esa red.</p> : (
          <>
            {esNuevo ? (
              <div className="itv-nuevo">
                <div className="tec-campo"><label htmlFor="itv-ntipo">Tipo del activo nuevo</label>
                  <select id="itv-ntipo" value={nuevoTipo} onChange={(e) => { setNuevoTipo(e.target.value); setNuevoClase(""); setEleccion(null); }}>
                    <option value="">Elija…</option>{tiposNuevo.map((t) => <option key={t.prefijo} value={t.prefijo}>{t.nombre} ({t.prefijo})</option>)}</select></div>
                {tipoNuevo?.clases.length ? (
                  <div className="tec-campo"><label htmlFor="itv-nclase">Clase{tipoNuevo.clase_obligatoria ? "" : " (opcional)"}</label>
                    <select id="itv-nclase" value={nuevoClase} onChange={(e) => setNuevoClase(e.target.value)}><option value="">Elija…</option>{tipoNuevo.clases.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
                ) : null}
                <div className="dan-dos">
                  <div className="tec-campo"><label htmlFor="itv-nmat">Material (opcional)</label>
                    <select id="itv-nmat" value={nuevoMaterial} onChange={(e) => setNuevoMaterial(e.target.value)}><option value="">Sin dato</option>{def.materiales.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
                  {tipoNuevo?.lleva_diametro !== false ? <div className="tec-campo"><label htmlFor="itv-ndiam">Diámetro (mm, opcional)</label><input id="itv-ndiam" type="text" inputMode="decimal" value={nuevoDiam} onChange={(e) => setNuevoDiam(e.target.value)} /></div> : null}
                </div>
                <div className="tec-campo"><label htmlFor="itv-nnom">Nombre (opcional)</label><input id="itv-nnom" type="text" maxLength={120} value={nuevoNombre} onChange={(e) => setNuevoNombre(e.target.value)} placeholder="Extensión calle 20, válvula del parque…" /></div>
                {tipoNuevo ? <p className="tec-ayuda">{tipoNuevo.geometria === "linea" ? "Toque en el mapa el inicio y el fin del tramo nuevo." : "Toque en el mapa dónde quedó el activo nuevo."} Queda «por verificar» hasta que el supervisor lo revise.</p> : null}
              </div>
            ) : null}
            {!esNuevo || tipoNuevo ? (
              <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
                <MiniMapaRed key={`${sistema}-${modoMapa}`} sistema={sistema} centro={ini ? { lat: ini.lat, lon: ini.lon } : ubic.fix ? { lat: ubic.fix.lat, lon: ubic.fix.lon } : null} eleccion={eleccion}
                  modoPunto={modoMapa === "punto"} modoLinea={modoMapa === "linea"} textoPunto={esNuevo ? "Toque el mapa donde quedó el activo nuevo" : "Toque el mapa donde está la intervención"}
                  zoomMin={reglas.zoom_min} onElegir={(e) => { setEleccion(e); setAviso(null); }} />
              </Suspense>
            ) : null}
            {aviso ? <p className="tec-aviso tec-aviso-info dan-aviso">{aviso}</p> : null}
            {activoSel ? (
              <div className="dan-elegido itv-elegido" aria-live="polite">
                <span className="red-icono" aria-hidden="true" />
                <div className="dan-elegido-txt">
                  <strong>{activoSel.codigo}</strong>
                  <span>{detalle ? [detalle.activo.tipo, detalle.activo.clase, detalle.activo.material, detalle.activo.codigo_anterior].filter(Boolean).join(" · ") : "…"}</span>
                </div>
                <button type="button" className="tec-enlace" onClick={() => setFicha(activoSel.codigo)}>Ver ficha</button>
              </div>
            ) : null}
            {!esNuevo ? (
              <>
                <div className="dan-buscar">
                  <label htmlFor="itv-buscar" className="dan-rot">¿No aparece? Búsquelo por código</label>
                  <div className="dan-buscar-fila">
                    <input id="itv-buscar" type="text" autoComplete="off" maxLength={60} placeholder="RED-000123, V85, P1902…" value={buscar} onChange={(e) => setBuscar(e.target.value)}
                      onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void hacerBusqueda(buscar, setResultados); } }} />
                    <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => void hacerBusqueda(buscar, setResultados)}>Buscar</button>
                  </div>
                  {resultados ? (resultados.length ? (
                    <div className="red-lista">{resultados.map((r) => (
                      <button key={r.codigo} type="button" className="red-fila" onClick={() => { setEleccion({ tipo: "activo", activo: { ...r, estado: "", estado_codigo: "", retirado: false } }); setResultados(null); setNoIdent(false); }}>
                        <span className="red-icono" aria-hidden="true" /><span className="red-fila-txt"><span className="red-fila-cod">{r.codigo}</span><span className="red-fila-sub">{r.tipo}{r.clase ? ` · ${r.clase}` : ""}{r.codigo_anterior ? ` · ${r.codigo_anterior}` : ""}</span></span>
                      </button>))}</div>
                  ) : <p className="tec-ayuda">No se encontró nada con «{buscar}» en {sistema}.</p>) : null}
                </div>
                <label className="dan-check">
                  <input type="checkbox" checked={noIdent} onChange={(e) => { setNoIdent(e.target.checked); setEleccion(null); setTambien([]); }} />
                  No puedo identificar el activo (marco el punto en el mapa; va a la bandeja del supervisor)
                </label>
                {noIdent ? (
                  <div className="tec-campo">
                    <label htmlFor="itv-quees">¿Qué es, según usted?</label>
                    <input id="itv-quees" type="text" maxLength={120} value={queEs} onChange={(e) => setQueEs(e.target.value)} placeholder="Tubería de acueducto, válvula, pozo de inspección…" />
                    {eleccion?.tipo === "punto" ? <span className="tec-ayuda">Punto marcado: {eleccion.lat.toFixed(5)}, {eleccion.lon.toFixed(5)}</span> : null}
                  </div>
                ) : null}
              </>
            ) : eleccion?.tipo === "linea" || eleccion?.tipo === "punto" ? (
              <p className="tec-ayuda">{eleccion.tipo === "linea" ? `Puntos marcados: ${eleccion.puntos.length} de 2.` : `Punto marcado: ${eleccion.lat.toFixed(5)}, ${eleccion.lon.toFixed(5)}.`}</p>
            ) : null}
            {activoSel ? (
              <div className="itv-tambien">
                <span className="dan-rot">Activos también intervenidos (opcional)</span>
                {tambien.length ? <div className="itv-chips">{tambien.map((t) => (
                  <span key={t.codigo} className="itv-chip">{t.codigo}<button type="button" aria-label={`Quitar ${t.codigo}`} onClick={() => setTambien((x) => x.filter((y) => y.codigo !== t.codigo))}>×</button></span>))}</div> : null}
                {cercanos.filter((c) => !tambien.some((t) => t.codigo === c.codigo)).length ? (
                  <div className="dan-fila" aria-label="Cercanos propuestos">{cercanos.filter((c) => !tambien.some((t) => t.codigo === c.codigo)).map((c) => (
                    <button key={c.codigo} type="button" className="dan-opcion itv-propuesto" onClick={() => agregarTambien(c)}>＋ {c.codigo} <small>{c.tipo}{c.distancia_m !== undefined ? `, ${Math.round(c.distancia_m)} m` : ""}</small></button>))}</div>
                ) : null}
                <div className="dan-buscar-fila">
                  <input aria-label="Agregar otro activo por código" type="text" autoComplete="off" maxLength={60} placeholder="Agregar por código" value={buscarT} onChange={(e) => setBuscarT(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void hacerBusqueda(buscarT, setResultadosT); } }} />
                  <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => void hacerBusqueda(buscarT, setResultadosT)}>Buscar</button>
                </div>
                {resultadosT?.length ? <div className="red-lista">{resultadosT.filter((r) => r.codigo !== activoSel.codigo).map((r) => (
                  <button key={r.codigo} type="button" className="red-fila" onClick={() => { agregarTambien(r); setResultadosT(null); setBuscarT(""); }}>
                    <span className="red-icono" aria-hidden="true" /><span className="red-fila-txt"><span className="red-fila-cod">{r.codigo}</span><span className="red-fila-sub">{r.tipo}</span></span>
                  </button>))}</div> : null}
              </div>
            ) : null}
            <p className="tec-ayuda">
              {ubic.fix ? <>Ubicación: GPS del celular · precisión ±{Math.round(ubic.fix.precision_m)} m{ubic.fix.precision_m > UMBRAL_PRECISION_MALA_M ? " (mala: si puede, espere a cielo abierto)" : ""}.</>
                : ubic.mensaje ? ubic.mensaje : "Buscando la ubicación del celular…"}
            </p>
          </>
        )}
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t3">
        <h2 id="itv-t3">3. Fecha y hora</h2>
        <div className="dan-dos">
          <div className="tec-campo"><label htmlFor="itv-ini">Inicio</label><input id="itv-ini" type="datetime-local" className="dan-hora" max={aLocal(new Date())} value={tIni} onChange={(e) => setTIni(e.target.value)} /></div>
          <div className="tec-campo"><label htmlFor="itv-fin">Fin</label>
            <div className="itv-fin"><input id="itv-fin" type="datetime-local" className="dan-hora" max={aLocal(new Date())} value={tFin} onChange={(e) => setTFin(e.target.value)} />
              <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => setTFin(aLocal(new Date()))}>Ahora</button></div></div>
        </div>
        <p className="tec-ayuda">El inicio se toma del celular al abrir el formulario; cámbielo si el trabajo empezó antes{reglas.dias_atras_max ? ` (hasta ${reglas.dias_atras_max} días atrás)` : " (sin tope: las obras largas se registran desde aquí)"}. Duración: <strong>{dur ?? "—"}</strong>{reglas.max_horas ? ` (máximo ${reglas.max_horas} h)` : ""}.</p>
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t4">
        <h2 id="itv-t4">4. Qué se hizo</h2>
        <div className="tec-campo"><label htmlFor="itv-desc">Descripción</label>
          <textarea id="itv-desc" className="dan-texto" maxLength={2000} rows={3} value={descripcion} onChange={(e) => setDescripcion(e.target.value)} placeholder="Se cambió un tramo de 3 m de tubo de 3 pulgadas…" /></div>
        <span className="dan-rot">Materiales</span>
        {materiales.map((x, i) => (
          <div key={x.id} className="itv-material">
            <input aria-label={`Material ${i + 1}`} type="text" maxLength={80} placeholder="Material" value={x.material} onChange={(e) => setMateriales((ms) => ms.map((y) => y.id === x.id ? { ...y, material: e.target.value } : y))} />
            <input aria-label={`Cantidad ${i + 1}`} type="text" inputMode="decimal" placeholder="Cantidad" value={x.cantidad} onChange={(e) => setMateriales((ms) => ms.map((y) => y.id === x.id ? { ...y, cantidad: e.target.value } : y))} />
            <select aria-label={`Unidad ${i + 1}`} value={x.unidad} onChange={(e) => setMateriales((ms) => ms.map((y) => y.id === x.id ? { ...y, unidad: e.target.value } : y))}>
              {def.unidades.map((u) => <option key={u.codigo} value={u.codigo}>{u.nombre}</option>)}</select>
            <button type="button" className="tec-enlace" onClick={() => setMateriales((ms) => ms.filter((y) => y.id !== x.id))}>Quitar</button>
          </div>))}
        <button type="button" className="tec-boton-sec" disabled={materiales.length >= reglas.max_materiales}
          onClick={() => setMateriales((ms) => [...ms, { id: sigMat.current++, material: "", cantidad: "", unidad: def.unidades[0]?.codigo ?? "und" }])}>Agregar material</button>
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t5">
        <h2 id="itv-t5">5. Quién la ejecuta</h2>
        <div className="dan-fila" role="group" aria-label="Ejecutor">
          {opcion(ejecutor === "emdupar", "EMDUPAR", () => setEjecutor("emdupar"))}
          {opcion(ejecutor === "contratista", "Contratista", () => setEjecutor("contratista"))}
        </div>
        {ejecutor === "contratista" ? (
          def.contratistas.length ? (
            <div className="tec-campo"><label htmlFor="itv-ctr">Contratista</label>
              <select id="itv-ctr" value={contratista} onChange={(e) => setContratista(e.target.value)}><option value="">Otro (escribirlo)</option>{def.contratistas.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select>
              {!contratista ? <input aria-label="Nombre del contratista" type="text" maxLength={120} value={contratistaNombre} onChange={(e) => setContratistaNombre(e.target.value)} placeholder="Nombre del contratista" /> : null}</div>
          ) : (
            <div className="tec-campo"><label htmlFor="itv-ctrn">Contratista</label><input id="itv-ctrn" type="text" maxLength={120} value={contratistaNombre} onChange={(e) => setContratistaNombre(e.target.value)} placeholder="Nombre de la empresa" /></div>
          )
        ) : null}
        <div className="dan-dos">
          <div className="tec-campo"><label htmlFor="itv-orden">Contrato u orden (si lo tiene)</label><input id="itv-orden" type="text" maxLength={60} value={orden} onChange={(e) => setOrden(e.target.value)} /></div>
          <div className="tec-campo"><label htmlFor="itv-comp">Cuadrilla: compañeros (opcional)</label><input id="itv-comp" type="text" maxLength={200} value={companeros} onChange={(e) => setCompaneros(e.target.value)} placeholder="Además de quien registra" /></div>
        </div>
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t6">
        <h2 id="itv-t6">6. De dónde salen los recursos</h2>
        <p className="tec-ayuda">{apoderado ? "Puede haber varias fuentes. Cada una con su valor o porcentaje y su soporte." : "Marque quién aporta. El valor, el porcentaje y el soporte los pone el supervisor."}</p>
        <div className="dan-marcas">{def.aportantes.map((ap) => {
          const f = fuentes.find((x) => x.aportante === ap.codigo);
          return (
            <div key={ap.codigo} className="itv-fuente">
              <label className="dan-check"><input type="checkbox" checked={!!f} onChange={(e) => setFuentes((fs) => e.target.checked ? [...fs, { aportante: ap.codigo, entidad: "", valor: "", porcentaje: "", soporte: "" }] : fs.filter((x) => x.aportante !== ap.codigo))} />{ap.nombre}</label>
              {f && ap.codigo === "otro" ? <input aria-label="Cuál otra entidad" type="text" maxLength={120} placeholder="¿Cuál?" value={f.entidad} onChange={(e) => setFuentes((fs) => fs.map((x) => x.aportante === "otro" ? { ...x, entidad: e.target.value } : x))} /> : null}
              {f && apoderado ? (
                <div className="itv-valores">
                  <input aria-label={`Valor de ${ap.nombre}`} type="text" inputMode="numeric" placeholder="Valor ($)" value={f.valor} onChange={(e) => setFuentes((fs) => fs.map((x) => x.aportante === ap.codigo ? { ...x, valor: e.target.value } : x))} />
                  <input aria-label={`Porcentaje de ${ap.nombre}`} type="text" inputMode="decimal" placeholder="o %" value={f.porcentaje} onChange={(e) => setFuentes((fs) => fs.map((x) => x.aportante === ap.codigo ? { ...x, porcentaje: e.target.value } : x))} />
                  <input aria-label={`Soporte de ${ap.nombre}`} type="text" maxLength={200} placeholder="Soporte (convenio o resolución)" value={f.soporte} onChange={(e) => setFuentes((fs) => fs.map((x) => x.aportante === ap.codigo ? { ...x, soporte: e.target.value } : x))} />
                </div>
              ) : null}
            </div>);
        })}</div>
      </section>

      <section className="tec-tarjeta" aria-labelledby="itv-t7">
        <h2 id="itv-t7">7. Fotos y soportes</h2>
        <p className="tec-ayuda">{sinFotos ? "Sin fotos: queda marcada «sin evidencia fotográfica»." : `Al menos una foto. Máximo ${reglas.max_fotos}. Solo cámara; la foto no se guarda en el celular.`}</p>
        {!sinFotos ? <div className="dan-fila">{CLASES.map((m) => (
          <button key={m.c} type="button" className="tec-boton-sec" disabled={fotos.length >= reglas.max_fotos || !!enviando} onClick={() => setCamara(m.c)}>📷 {m.n}</button>))}</div> : null}
        {camara ? (
          <CamaraActa rotulo={`Foto: ${CLASES.find((m) => m.c === camara)!.n.toLowerCase()}`} maxBytes={reglas.max_bytes_foto}
            sello={() => [new Date().toLocaleString("es-CO"), ubic.fix ? `${ubic.fix.lat.toFixed(5)}, ${ubic.fix.lon.toFixed(5)}` : "sin GPS"]}
            onFoto={({ blob }) => { setFotos((f) => [...f, { blob, clase: camara, url: URL.createObjectURL(blob) }]); prep.current = null; setCamara(null); }}
            onCerrar={() => setCamara(null)} />
        ) : null}
        {fotos.length && !sinFotos ? <div className="dan-fotos">{fotos.map((f, i) => (
          <figure key={f.url} className="dan-foto">
            <img src={f.url} alt={`Foto ${i + 1}: ${CLASES.find((m) => m.c === f.clase)!.n}`} />
            <figcaption>{i + 1}. {CLASES.find((m) => m.c === f.clase)!.n}
              <button type="button" className="tec-enlace" disabled={!!enviando} onClick={() => { URL.revokeObjectURL(f.url); setFotos((x) => x.filter((_, j) => j !== i)); prep.current = null; }}>Quitar</button></figcaption>
          </figure>))}</div> : null}
        {reglas.puede_sin_fotos ? (
          <>
            <label className="dan-check"><input type="checkbox" checked={sinFotos} onChange={(e) => { setSinFotos(e.target.checked); prep.current = null; }} />Registrar sin evidencia fotográfica (por ejemplo, llegó por la 116 o por llamada)</label>
            {sinFotos ? <div className="tec-campo"><label htmlFor="itv-sinf">¿Por qué no hay fotos?</label><input id="itv-sinf" type="text" maxLength={300} value={sinFotosMotivo} onChange={(e) => setSinFotosMotivo(e.target.value)} /></div> : null}
          </>
        ) : null}
        <div className="tec-campo">
          <label htmlFor="itv-doc">Adjuntar documento (orden, acta, factura; PDF, hasta {reglas.max_documentos})</label>
          <input id="itv-doc" type="file" accept="application/pdf" disabled={docs.length >= reglas.max_documentos || !!enviando}
            onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (!f) return;
              if (f.type !== "application/pdf") { setErrorEnvio("El documento debe ser PDF."); return; }
              if (f.size > reglas.max_bytes_documento) { setErrorEnvio(`El documento pesa más de ${Math.round(reglas.max_bytes_documento / 1048576)} MB.`); return; }
              setErrorEnvio(null); setDocs((d) => [...d, { archivo: f }]); prep.current = null; }} />
          {docs.length ? <ul className="itv-docs">{docs.map((d, i) => <li key={i}>📄 {d.archivo.name} ({Math.round(d.archivo.size / 1024)} KB) <button type="button" className="tec-enlace" onClick={() => { setDocs((x) => x.filter((_, j) => j !== i)); prep.current = null; }}>Quitar</button></li>)}</ul> : null}
        </div>
      </section>

      {errores.length ? <div className="tec-aviso tec-aviso-error dan-errores dan-pad-x" role="alert"><strong>Falta completar:</strong><ul>{errores.map((e) => <li key={e}>{e}</li>)}</ul></div> : null}
      {errorEnvio ? <p className="tec-aviso tec-aviso-error dan-pad-x" role="alert">{errorEnvio}</p> : null}
      {cancelar ? (
        <div className="dan-pad-x">
          <ConfirmarCancelar titulo="¿Cancelar esta intervención?" mensaje="Se borra lo escrito, las fotos y los documentos de este celular. En el servidor no queda nada." onSeguir={() => setCancelar(false)}
            onConfirmar={() => { setCancelar(false); onSalir?.(); }} />
        </div>
      ) : (
        <div className="tec-acciones dan-pad-x">
          <button type="button" className="tec-boton itv-guardar" disabled={!!enviando} onClick={() => void guardar()}>{enviando ?? "Guardar intervención"}</button>
          <button type="button" className="tec-boton-sec" disabled={!!enviando} onClick={() => setCancelar(true)}>Cancelar</button>
        </div>
      )}
      <p className="tec-sub dan-pad-x">Sesión de {correo}</p>
    </div>
  );
}
