// Geovisor técnico · Corte 2 (Code B, 26-nov): «Cuadernos de análisis». El cuaderno es un vidrio encima de todo el mapa: se le ponen problemas, íconos de
// activo (propuestas: NO crean activos en la red), puntos de referencia, post-its y dibujos. Quién entra lo decide el SERVIDOR (Edge geoportal-analisis):
// leen el autor, los supervisores de Técnica y el administrador; edita solo el autor. Esta pantalla solo lo refleja: si «perfil» da 403, el botón no existe.
// · Modo exploración: el mapa se mueve y las capas cambian; las marcas quedan fijas; no se pinta.  · Modo edición (solo el autor): se agregan o cambian marcas.
// · Cada «Guardar» es una versión nueva. Nada se borra: una marca guardada se anula con motivo. Mientras se edita hay un borrador en el dispositivo.
// · La zona afectada muestra SOLO dos números (predios y contratos), que cuenta el servidor. Sin datos de suscriptores en ninguna parte.
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";
import { createPortal } from "react-dom";
import type maplibregl from "maplibre-gl";
import { ErrorTec } from "../apiTecnica";
import { lienzoVacio, type SobreImpresion } from "../impresion/ImprimirMapa";
import { apiAnalisis, exportarCsv, subirCaptura, type Cambio, type Categoria, type Cuaderno, type CuadernoLista, type Marca, type PerfilAnalisis, type Sistema } from "./apiAnalisis";
import { cargarIconos, urlActivo, urlProblema } from "./iconos";
import { ICONOS_ACTIVO, ICONOS_PROBLEMA } from "./iconos_datos";
import { AVISO_NOTA, COLORES_LIBRES, MOTIVO_GOMA, NOMBRE_CATEGORIA, NOTA_MAX, aligerar, anotar, area, borrarBorrador, cambiosParaGuardar, conAnulacion, conCambio, dentro, deshacer, distancia, encuadre,
  escribirBorrador, figuraDentro, historiaVacia, largo, leerBorrador, linea, marcaNueva, marcasVisibles, miles, pasoDeEncuadre, poligono, punto, rehacer, textoArea, textoDistancia, trasladar, zoomDeEncuadre,
  type Borrador, type Pendientes } from "./modelo";
import { leyendaCuaderno, marcaEn, pintarMarcas, rotulo, type Lienzo } from "./pintar";
import "./cuadernos.css";

/** Lo que el geovisor le pregunta al cuaderno (el geovisor no sabe nada más de él). */
export type PuenteCuaderno = {
  /** Un toque en el mapa: true si el cuaderno se quedó con él (puso una marca, eligió una, etc.). */
  clic: (ev: { point: { x: number; y: number }; lngLat: { lng: number; lat: number } }) => boolean;
  /** Salir del geovisor: si hay cambios sin guardar pregunta (Guardar, Salir sin guardar o Cancelar) y solo entonces sigue. */
  salir: (seguir: () => void) => void;
  /** Las marcas y su leyenda para el PDF de 2 páginas (undefined si no hay cuaderno abierto). */
  sobre: () => SobreImpresion | undefined;
};

type Herr = null | { t: "problema"; sub: string } | { t: "activo"; sub: string; sistema: Sistema } | { t: "referencia" } | { t: "postit" } | { t: "mano" } | { t: "circulo" } | { t: "linea" } | { t: "zona" }
  | { t: "medir"; que: "distancia" | "area" } | { t: "mover" } | { t: "goma" };
type Dialogo = null | { d: "nuevo" } | { d: "salir"; seguir: () => void } | { d: "capturas" } | { d: "capturar" } | { d: "estado" } | { d: "borrador"; b: Borrador } | { d: "postit"; lon: number; lat: number } | { d: "datos" };

const fecha = (v: string) => new Date(v).toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short", timeZone: "America/Bogota" });
const mensaje = (e: unknown, omision: string) => (e instanceof Error && e.message ? e.message : omision);
const R_TIERRA = 6378137;
const mppMapa = (m: maplibregl.Map, lat: number) => (2 * Math.PI * R_TIERRA * Math.cos((lat * Math.PI) / 180)) / (512 * 2 ** m.getZoom());
/** Evita el gesto del navegador solo si se puede (los toques llegan por escuchas pasivas, donde no se puede ni hace falta). */
const noPorOmision = (ev: Event) => { if (ev.cancelable) ev.preventDefault(); };
const ASPECTO_HOJA = (612 - 80) / (792 - 34 - 24 - 120 - 14);      // el marco del mapa en la hoja carta (ImprimirMapa)
const NOMBRE_HERR: Record<string, string> = { referencia: "Punto de referencia", postit: "Post-it", mano: "Mano alzada", circulo: "Círculo", linea: "Flecha o línea", zona: "Zona afectada" };

export function Cuadernos({ mapa, listo, completo, lista, onLista, puente, ranura, alDisponer, onImprimir }: {
  mapa: maplibregl.Map | null; listo: boolean; completo: boolean; lista: boolean; onLista: (abierta: boolean) => void; puente: MutableRefObject<PuenteCuaderno | null>;
  ranura: HTMLElement | null; alDisponer: (disponible: boolean) => void; onImprimir: () => void;
}) {
  const [perfil, setPerfil] = useState<PerfilAnalisis | null>(null);
  const [cuad, setCuad] = useState<Cuaderno | null>(null);
  const [pend, setPend] = useState<Pendientes>({});
  const [modo, setModo] = useState<"explorar" | "editar">("explorar");
  const [herr, setHerr] = useState<Herr>(null);
  const [menu, setMenu] = useState<"" | "problema" | "activo" | "dibujo" | "mas">("");
  const [sistema, setSistema] = useState<Sistema>("acueducto");
  const [color, setColor] = useState(COLORES_LIBRES[0]);
  const [grosor, setGrosor] = useState(4);
  const [curso, setCurso] = useState<[number, number][]>([]);
  const [sel, setSel] = useState<string | null>(null);
  const [dialogo, setDialogo] = useState<Dialogo>(null);
  const [aviso, setAviso] = useState<{ texto: string; error?: boolean } | null>(null);
  const [ocupado, setOcupado] = useState("");
  const [iconos, setIconos] = useState(false);
  const lienzo = useRef<HTMLCanvasElement | null>(null);
  const hist = useRef(historiaVacia());
  const [, setPaso] = useState(0);      // solo para repintar los botones ↶ ↷

  // ---------- acceso: lo decide el servidor ----------
  useEffect(() => {
    if (!completo) { alDisponer(false); return; }      // el operador y quien no tiene el geovisor completo ni siquiera preguntan (el servidor les daría 403)
    let vivo = true;
    apiAnalisis.perfil().then((p) => { if (vivo) { setPerfil(p); alDisponer(true); } }).catch(() => { if (vivo) alDisponer(false); });
    cargarIconos().then(() => { if (vivo) setIconos(true); });
    return () => { vivo = false; };
  }, [completo]); // eslint-disable-line react-hooks/exhaustive-deps

  const visibles = useMemo(() => (cuad ? marcasVisibles(cuad.marcas, pend) : []), [cuad, pend]);
  const nPend = Object.keys(pend).length;
  const editable = !!cuad && cuad.puede_editar && modo === "editar";
  const marcaSel = sel ? visibles.find((m) => m.id === sel) ?? null : null;
  const decir = (texto: string, error = false) => setAviso({ texto, error });

  // lo último de cada cosa, para los manejadores del mapa (que se registran una vez)
  const E = useRef({ cuad, pend, visibles, herr, curso, editable, color, grosor, sel, perfil, nPend });
  E.current = { cuad, pend, visibles, herr, curso, editable, color, grosor, sel, perfil, nPend };

  // ---------- el vidrio: un lienzo dentro del mapa, debajo de sus controles ----------
  const pintar = useCallback(() => {
    const c = lienzo.current, m = mapa; if (!c || !m) return;
    const cont = m.getContainer(), dpr = window.devicePixelRatio || 1, w = cont.clientWidth, h = cont.clientHeight;
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); c.style.width = `${w}px`; c.style.height = `${h}px`; }
    const x = c.getContext("2d")!; x.setTransform(dpr, 0, 0, dpr, 0, 0); x.clearRect(0, 0, w, h);
    const e = E.current; if (!e.cuad) return;
    const l: Lienzo = { x, proy: (lon, lat) => { const p = m.project([lon, lat]); return [p.x, p.y]; }, k: 1, mpp: (lat) => mppMapa(m, lat) };
    pintarMarcas(l, e.visibles, e.sel);
    if (e.curso.length && e.herr) {      // lo que se está dibujando
      const p = e.curso.map(([lon, lat]) => l.proy(lon, lat)), medir = e.herr.t === "medir", col = medir ? "#111827" : e.herr.t === "zona" ? "#B3261E" : e.color;
      x.save(); x.lineJoin = "round"; x.lineCap = "round"; x.strokeStyle = "#fff"; x.lineWidth = (e.herr.t === "mano" ? e.grosor : 3) + 2;
      const camino = () => { x.beginPath(); p.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py))); if ((e.herr!.t === "zona" || (medir && (e.herr as { que: string }).que === "area")) && p.length > 2) x.closePath(); };
      camino(); x.stroke(); x.strokeStyle = col; x.lineWidth = e.herr.t === "mano" ? e.grosor : 3; if (medir) x.setLineDash([6, 5]); camino(); x.stroke(); x.setLineDash([]);
      if (e.herr.t !== "mano") for (const [px, py] of p) { x.fillStyle = "#fff"; x.strokeStyle = col; x.lineWidth = 2; x.beginPath(); x.arc(px, py, 5, 0, 2 * Math.PI); x.fill(); x.stroke(); }
      x.restore();
    }
  }, [mapa]);

  useEffect(() => {
    if (!mapa || !listo) return;
    const c = document.createElement("canvas"); c.className = "cua-lienzo"; c.setAttribute("data-testid", "cua-lienzo");
    mapa.getCanvasContainer().appendChild(c); lienzo.current = c;
    const redibujar = () => pintar();
    mapa.on("move", redibujar); mapa.on("resize", redibujar);
    return () => { mapa.off("move", redibujar); mapa.off("resize", redibujar); c.remove(); lienzo.current = null; };
  }, [mapa, listo, pintar]);
  useEffect(() => { pintar(); }, [pintar, visibles, sel, curso, herr, color, grosor, iconos, cuad]);
  useEffect(() => { mapa?.resize(); }, [mapa, cuad?.id, modo, herr, menu, nPend, curso.length]);
  // para las pruebas en Chrome (no se usa en la app): lo que hay pintado
  useEffect(() => { (window as unknown as { __cuaderno?: unknown }).__cuaderno = cuad ? { id: cuad.id, version: cuad.version, marcas: visibles, pendientes: nPend, modo, puede_editar: cuad.puede_editar } : null; }, [cuad, visibles, nPend, modo]);

  // ---------- borrador en el dispositivo ----------
  useEffect(() => { if (cuad && cuad.puede_editar && perfil) escribirBorrador(perfil.email, cuad.id, cuad.version, pend); }, [pend, cuad, perfil]);
  useEffect(() => {
    if (!nPend) return;
    const antes = (ev: BeforeUnloadEvent) => { ev.preventDefault(); ev.returnValue = ""; };
    window.addEventListener("beforeunload", antes); return () => window.removeEventListener("beforeunload", antes);
  }, [nPend]);

  // ---------- cambios pendientes, con deshacer y rehacer (solo de pantalla: nada de esto llega al servidor hasta «Guardar») ----------
  /** Todo cambio pasa por aquí. Con la misma `clave` que el anterior es el mismo gesto (escribir una nota, arrastrar, una pasada de la goma) y cuenta como un solo paso. */
  const aplicar = (f: (p: Pendientes) => Pendientes, clave = "") => {
    const antes = E.current.pend, despues = f(antes); if (despues === antes) return;
    anotar(hist.current, antes, clave); E.current.pend = despues; setPend(despues); setPaso((n) => n + 1);
  };
  const sinHistoria = (p: Pendientes) => { hist.current = historiaVacia(); E.current.pend = p; setPend(p); setPaso((n) => n + 1); };
  const irAtras = () => { const p = deshacer(hist.current, E.current.pend); if (p) { E.current.pend = p; setPend(p); setSel(null); setCurso([]); setPaso((n) => n + 1); } };
  const irAdelante = () => { const p = rehacer(hist.current, E.current.pend); if (p) { E.current.pend = p; setPend(p); setSel(null); setPaso((n) => n + 1); } };

  // ---------- abrir, cerrar, guardar ----------
  const soltar = () => { setHerr(null); setCurso([]); setSel(null); setMenu(""); };
  const abrir = async (id: string, version?: number) => {
    setOcupado("Abriendo el cuaderno…"); setAviso(null);
    try {
      const c = await apiAnalisis.cuaderno(id, version);
      setCuad(c); sinHistoria({}); soltar(); setModo("explorar"); onLista(false);
      if (mapa && !version && c.vista && typeof c.vista.lon === "number" && typeof c.vista.lat === "number" && dentro(c.vista.lon, c.vista.lat)) mapa.jumpTo({ center: [c.vista.lon, c.vista.lat], zoom: typeof c.vista.zoom === "number" ? c.vista.zoom : mapa.getZoom() });
      const b = c.puede_editar && perfil ? leerBorrador(perfil.email, c.id) : null;
      if (b) setDialogo({ d: "borrador", b });
    } catch (e) { decir(mensaje(e, "No se pudo abrir el cuaderno."), true); }
    setOcupado("");
  };
  const cerrar = () => { setCuad(null); sinHistoria({}); soltar(); setModo("explorar"); setAviso(null); };
  const guardar = async (): Promise<boolean> => {
    const e = E.current; if (!e.cuad || !e.nPend) return true;
    setOcupado("Guardando…"); setAviso(null);
    try {
      const c = mapa?.getCenter();
      const r = await apiAnalisis.guardar(e.cuad.id, e.cuad.version, cambiosParaGuardar(e.pend), c && mapa ? { lon: Number(c.lng.toFixed(6)), lat: Number(c.lat.toFixed(6)), zoom: Number(mapa.getZoom().toFixed(2)) } : null);
      if (e.perfil) borrarBorrador(e.perfil.email, e.cuad.id);
      setCuad((p) => (p ? { ...p, version: r.version, ultima_version: r.version, marcas: r.marcas, guardado_en: new Date().toISOString(), versiones: [{ version: r.version, creado_en: new Date().toISOString(), titulo: p.titulo }, ...p.versiones] } : p));
      sinHistoria({}); setSel(null); setHerr(null); setCurso([]);
      decir(`Guardado: versión ${r.version}.`); setOcupado(""); return true;
    } catch (err) {
      setOcupado("");
      if (err instanceof ErrorTec && err.status === 409) decir("El cuaderno cambió en otra sesión. Sus cambios siguen aquí, en el borrador: recargue el cuaderno y vuelva a guardar.", true);
      else decir(mensaje(err, "No se pudo guardar."), true);
      return false;
    }
  };
  const conCambiosPendientes = (seguir: () => void) => { if (E.current.nPend) setDialogo({ d: "salir", seguir }); else seguir(); };

  // ---------- poner y cambiar marcas ----------
  const agregar = (c: Cambio) => {
    const e = E.current;
    if (e.visibles.length >= (e.perfil?.topes.marcas_por_cuaderno ?? 500)) { decir(`El cuaderno ya tiene sus ${e.perfil?.topes.marcas_por_cuaderno ?? 500} marcas.`, true); return; }
    aplicar((p) => ({ ...p, [c.marca_id]: c })); setSel(c.marca_id); setAviso(null);
  };
  const cambiar = (id: string, d: Parameters<typeof conCambio>[3], clave = "") => aplicar((p) => (E.current.cuad ? conCambio(E.current.cuad.marcas, p, id, d) : p), clave);
  /** La goma: la marca sin guardar se quita sin más; la guardada queda anulada con el motivo automático (se anula al guardar). */
  const borrar = (id: string, clave: string) => aplicar((p) => (E.current.cuad ? conAnulacion(E.current.cuad.marcas, p, id, MOTIVO_GOMA) : p), clave);
  const lienzoMapa = (): Lienzo | null => (mapa && lienzo.current ? { x: lienzo.current.getContext("2d")!, proy: (a, b) => { const q = mapa.project([a, b]); return [q.x, q.y]; }, k: 1, mpp: (la) => mppMapa(mapa, la) } : null);
  const terminar = () => {
    const e = E.current; if (!e.herr) return;
    if (e.herr.t === "linea" && e.curso.length >= 2) agregar(marcaNueva({ tipo: "linea", geom: linea(e.curso), estilo: { color: e.color, grosor: Math.min(e.grosor, 8) } }));
    else if (e.herr.t === "zona" && e.curso.length >= 3) {
      const km2 = area(e.curso) / 1e6, max = e.perfil?.topes.zona_area_max_km2 ?? 25;
      if (km2 > max) { decir(`La zona es demasiado grande (${km2.toFixed(1).replace(".", ",")} km²; máximo ${max} km²).`, true); return; }
      agregar(marcaNueva({ tipo: "zona", geom: poligono(e.curso) }));
    } else return;
    setCurso([]); setHerr(null);
  };

  // ---------- el puente con el geovisor ----------
  puente.current = !perfil ? null : {
    clic: (ev) => {
      const e = E.current, m = mapa; if (!e.cuad || !m) return false;
      const lon = ev.lngLat.lng, lat = ev.lngLat.lat, h = e.herr;
      if (h && h.t === "medir") { setCurso([...e.curso, [lon, lat]]); return true; }      // medir es de pantalla: vale en exploración y en edición
      if (e.editable && h) {
        if (h.t === "mano") return true;      // la mano alzada va con arrastre
        if (h.t !== "mover" && h.t !== "goma" && !dentro(lon, lat)) { decir("Ese punto está fuera de Valledupar.", true); return true; }
        if (h.t === "problema") agregar(marcaNueva({ tipo: "problema", subtipo: h.sub, geom: punto(lon, lat) }));
        else if (h.t === "activo") agregar(marcaNueva({ tipo: "activo", subtipo: h.sub, sistema: h.sistema, geom: punto(lon, lat) }));
        else if (h.t === "referencia") agregar(marcaNueva({ tipo: "referencia", geom: punto(lon, lat), estilo: { color: e.color } }));
        else if (h.t === "postit") setDialogo({ d: "postit", lon, lat });
        else if (h.t === "mover" || h.t === "goma") {      // un toque sin arrastre: elegir (mover) o borrar (goma) la marca tocada
          const l0 = lienzoMapa(), toc = l0 ? marcaEn(l0, e.visibles, ev.point.x, ev.point.y) : null;
          if (h.t === "mover") setSel(toc ? toc.id : null); else if (toc) { borrar(toc.id, ""); setSel(null); }
          return true;
        }
        else if (h.t === "circulo") {
          if (!e.curso.length) setCurso([[lon, lat]]);
          else {
            const r = Math.round(distancia(e.curso[0], [lon, lat]) * 10) / 10;
            if (r < 1 || r > 5000) decir("El radio del círculo debe estar entre 1 y 5.000 m.", true);
            else { agregar(marcaNueva({ tipo: "circulo", geom: punto(e.curso[0][0], e.curso[0][1]), radio_m: r, estilo: { color: e.color, grosor: Math.min(e.grosor, 8) } })); setHerr(null); }
            setCurso([]);
          }
        } else if (h.t === "linea" || h.t === "zona") { if (e.curso.length < 100) setCurso([...e.curso, [lon, lat]]); }
        return true;
      }
      const l: Lienzo = { x: lienzo.current!.getContext("2d")!, proy: (a, b) => { const p = m.project([a, b]); return [p.x, p.y]; }, k: 1, mpp: (la) => mppMapa(m, la) };
      const tocada = marcaEn(l, e.visibles, ev.point.x, ev.point.y);
      if (tocada) { setSel(tocada.id); setMenu(""); return true; }
      if (e.sel) setSel(null);
      return e.editable;      // en edición, un toque en vacío no abre tarjetas del geovisor; en exploración, sí
    },
    salir: (seguir) => conCambiosPendientes(() => { seguir(); }),
    sobre: () => {
      const e = E.current; if (!e.cuad) return undefined;
      const marcas = e.visibles, caja = encuadre(marcas);
      return {
        paginas: caja ? [{ clave: "detalle" as const, nombre: "Detalle del cuaderno", extension: caja, zoom: zoomDeEncuadre(caja, ASPECTO_HOJA), etiquetas: { sectores: true, subsectores: true }, pasoGrados: pasoDeEncuadre(caja), ubicacion: true }] : [],
        dibujar: (x, aHoja, k, mpp) => pintarMarcas({ x, proy: aHoja, k: k * 0.62, mpp: () => mpp }, marcas),
        leyenda: { titulo: `Cuaderno: ${e.cuad.titulo.slice(0, 38)}`, items: leyendaCuaderno(marcas) },
      };
    },
  };
  useEffect(() => () => { puente.current = null; }, [puente]);

  // ---------- gestos de arrastre: mano alzada, goma y mover ----------
  const gesto = useRef(0);
  useEffect(() => {
    if (!mapa || !editable || !herr) return;
    const dibuja = herr.t === "linea" || herr.t === "zona" || herr.t === "circulo" || herr.t === "mano";
    if (dibuja) mapa.doubleClickZoom.disable();
    if (herr.t !== "mano" && herr.t !== "goma" && herr.t !== "mover") return () => { mapa.doubleClickZoom.enable(); };
    type Ev = { point: { x: number; y: number }; lngLat: { lng: number; lat: number }; originalEvent: Event; preventDefault: () => void };
    const fijo = herr.t !== "mover";      // mano y goma: el mapa quieto todo el tiempo; mover: solo mientras se arrastra una marca
    if (fijo) { mapa.dragPan.disable(); mapa.touchZoomRotate.disable(); }
    let pts: [number, number][] | null = null, clave = "";
    let mov: { id: string; lon: number; lat: number; geom: Marca["geom"]; movio: boolean } | null = null;
    const tocada = (ev: Ev) => { const l0 = lienzoMapa(); return l0 ? marcaEn(l0, E.current.visibles, ev.point.x, ev.point.y) : null; };
    const ini = (ev: Ev) => {
      if (herr.t === "mano") { noPorOmision(ev.originalEvent); pts = [[ev.lngLat.lng, ev.lngLat.lat]]; setCurso(pts); return; }
      clave = `${herr.t}:${++gesto.current}`;
      if (herr.t === "goma") { noPorOmision(ev.originalEvent); pts = []; const m = tocada(ev); if (m) borrar(m.id, clave); return; }
      const m = tocada(ev);
      if (!m) { setSel(null); return; }      // en vacío: el mapa se mueve como siempre
      ev.preventDefault(); noPorOmision(ev.originalEvent); mapa.dragPan.disable(); mapa.touchZoomRotate.disable();
      setSel(m.id); mov = { id: m.id, lon: ev.lngLat.lng, lat: ev.lngLat.lat, geom: m.geom, movio: false };
    };
    const mover = (ev: Ev) => {
      if (herr.t === "mano") { if (!pts) return; noPorOmision(ev.originalEvent); pts = [...pts, [ev.lngLat.lng, ev.lngLat.lat]]; setCurso(pts); return; }
      if (herr.t === "goma") { if (!pts) return; noPorOmision(ev.originalEvent); const m = tocada(ev); if (m) borrar(m.id, clave); return; }
      if (!mov) return; noPorOmision(ev.originalEvent);
      const a = mapa.project([mov.lon, mov.lat]); if (!mov.movio && Math.hypot(ev.point.x - a.x, ev.point.y - a.y) < 4) return;      // un toque no es un arrastre
      mov.movio = true; cambiar(mov.id, { geom: trasladar(mov.geom, ev.lngLat.lng - mov.lon, ev.lngLat.lat - mov.lat) }, clave);
    };
    const fin = () => {
      if (herr.t === "mano") {
        if (!pts) return; const c = aligerar(pts); pts = null; setCurso([]);
        const e = E.current, max = e.perfil?.topes.mano_vertices_max ?? 500;
        if (c.length < 2) return;
        if (c.some(([lon, lat]) => !dentro(lon, lat))) { decir("El trazo se sale de Valledupar.", true); return; }
        if (c.length > max) { decir("El trazo es demasiado largo: divídalo en dos.", true); return; }
        agregar(marcaNueva({ tipo: "mano", geom: linea(c), estilo: { color: e.color, grosor: e.grosor } }));
        return;
      }
      if (herr.t === "goma") { pts = null; return; }
      if (!mov) return; const m0 = mov; mov = null; mapa.dragPan.enable(); mapa.touchZoomRotate.enable();
      if (!m0.movio) return;
      const ahora = E.current.visibles.find((x) => x.id === m0.id);
      if (ahora && !figuraDentro(ahora.geom)) { irAtras(); setSel(m0.id); decir("La marca no puede quedar fuera de Valledupar: volvió a su lugar.", true); }
    };
    mapa.on("mousedown", ini); mapa.on("mousemove", mover); mapa.on("mouseup", fin); mapa.on("touchstart", ini); mapa.on("touchmove", mover); mapa.on("touchend", fin);
    return () => { mapa.off("mousedown", ini); mapa.off("mousemove", mover); mapa.off("mouseup", fin); mapa.off("touchstart", ini); mapa.off("touchmove", mover); mapa.off("touchend", fin);
      mapa.dragPan.enable(); mapa.touchZoomRotate.enable(); mapa.doubleClickZoom.enable(); };
  }, [mapa, editable, herr]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!editable && herr && herr.t !== "medir") { setHerr(null); setCurso([]); } }, [editable, herr]);

  if (!perfil) return null;

  const elegir = (h: Herr) => { setHerr(h); setCurso([]); setMenu(""); setSel(null); setAviso(null); };
  const medida = herr?.t === "medir" && curso.length > 1 ? (herr.que === "distancia" ? `Distancia: ${textoDistancia(largo(curso))}` : curso.length > 2 ? `Área: ${textoArea(area(curso))} · perímetro ${textoDistancia(largo([...curso, curso[0]]))}` : "Marque al menos 3 puntos") : null;
  const ayuda = !herr ? null : herr.t === "mano" ? "Arrastre sobre el mapa para trazar." : herr.t === "circulo" ? (curso.length ? "Toque hasta dónde llega el círculo." : "Toque el centro del círculo.")
    : herr.t === "linea" ? "Toque los puntos de la línea; la flecha queda en el último. Luego «Terminar»." : herr.t === "zona" ? "Toque las esquinas de la zona. Luego «Terminar»: al guardar se cuentan los predios y los contratos."
    : herr.t === "medir" ? "Toque los puntos a medir. La medida es de pantalla: no se guarda." : herr.t === "mover" ? (marcaSel ? `Elegida: ${rotulo(marcaSel)}. Arrástrela a su nuevo lugar.` : "Toque una marca para elegirla y arrástrela completa a su nuevo lugar.")
    : herr.t === "goma" ? "Pase la goma sobre las marcas que quiere quitar. Las ya guardadas se anulan al guardar. Se puede deshacer con ↶." : "Toque el mapa donde va la marca.";
  const nombreHerr = !herr ? "" : herr.t === "problema" ? ICONOS_PROBLEMA.find((i) => i.codigo === herr.sub)?.nombre ?? "" : herr.t === "activo" ? `${ICONOS_ACTIVO.find((i) => i.codigo === herr.sub)?.nombre} · ${herr.sistema === "acueducto" ? "Acueducto" : "Alcantarillado"}`
    : herr.t === "medir" ? (herr.que === "distancia" ? "Medir distancia" : "Medir área") : herr.t === "mover" ? "Seleccionar y mover" : herr.t === "goma" ? "Borrador" : NOMBRE_HERR[herr.t];
  const conEstilo = herr && (herr.t === "referencia" || herr.t === "mano" || herr.t === "linea" || herr.t === "circulo");

  const barra = cuad ? (
    <div className="cua-barra" data-testid="cua-barra" data-modo={modo}>
      <div className="cua-cab">
        <div className="cua-titulo"><strong data-testid="cua-titulo">{cuad.titulo}</strong>
          <span>{cuad.es_mio ? "Mío" : `De ${cuad.autor_nombre ?? cuad.autor}`} · versión {cuad.version}{cuad.version !== cuad.ultima_version ? ` de ${cuad.ultima_version} (anterior, solo lectura)` : ""}{cuad.archivado ? " · archivado" : ""} · {miles(visibles.length)} {visibles.length === 1 ? "marca" : "marcas"}</span></div>
        {cuad.puede_editar ? (
          <div className="geo-seg" role="group" aria-label="Modo del cuaderno" data-testid="cua-modo">
            <button type="button" aria-pressed={modo === "explorar"} onClick={() => { setModo("explorar"); setHerr(null); setCurso([]); setMenu(""); }}>Explorar</button>
            <button type="button" aria-pressed={modo === "editar"} onClick={() => setModo("editar")}>Editar</button>
          </div>) : <span className="cua-lectura" data-testid="cua-lectura">Solo lectura</span>}
        {cuad.puede_editar ? <button type="button" className="tec-boton cua-guardar" data-testid="cua-guardar" disabled={!nPend || !!ocupado} onClick={() => { void guardar(); }}>{nPend ? `Guardar (${nPend})` : "Guardado"}</button> : null}
        <div className="cua-menu">
          <button type="button" className="tec-boton-sec" aria-expanded={menu === "mas"} data-testid="cua-mas" onClick={() => setMenu(menu === "mas" ? "" : "mas")}>Más…</button>
          {menu === "mas" ? (
            <div className="cua-desplegable cua-desplegable-der" role="menu">
              <button type="button" role="menuitem" data-testid="cua-capturar" onClick={() => { setMenu(""); setDialogo({ d: "capturar" }); }}>Captura de la vista…</button>
              <button type="button" role="menuitem" data-testid="cua-capturas" onClick={() => { setMenu(""); setDialogo({ d: "capturas" }); }}>Capturas guardadas ({cuad.capturas.length})</button>
              <button type="button" role="menuitem" data-testid="cua-pdf" onClick={() => { setMenu(""); onImprimir(); }}>Imprimir / PDF con las marcas</button>
              <button type="button" role="menuitem" data-testid="cua-csv" onClick={() => { setMenu(""); setOcupado("Exportando…"); exportarCsv(cuad.id).then((b) => { descargar(b, `cuaderno_${nombreArchivo(cuad.titulo)}.csv`); setOcupado(""); }).catch((e) => { setOcupado(""); decir(mensaje(e, "No se pudo exportar."), true); }); }}>Exportar las marcas (CSV)</button>
              <button type="button" role="menuitem" data-testid="cua-medir-d" className="cua-solo-escritorio" onClick={() => elegir({ t: "medir", que: "distancia" })}>Medir distancia</button>
              <button type="button" role="menuitem" data-testid="cua-medir-a" className="cua-solo-escritorio" onClick={() => elegir({ t: "medir", que: "area" })}>Medir área</button>
              <button type="button" role="menuitem" data-testid="cua-datos" onClick={() => { setMenu(""); setDialogo({ d: "datos" }); }}>Versiones y datos del cuaderno</button>
              {cuad.es_mio && cuad.version === cuad.ultima_version ? <button type="button" role="menuitem" data-testid="cua-estado" disabled={!!nPend} onClick={() => { setMenu(""); setDialogo({ d: "estado" }); }}>{cuad.archivado ? "Reabrir el cuaderno…" : "Archivar el cuaderno…"}</button> : null}
            </div>) : null}
        </div>
        <button type="button" className="tec-boton-sec" data-testid="cua-cerrar" aria-label="Cerrar el cuaderno" onClick={() => conCambiosPendientes(cerrar)}><span className="geo-largo">Cerrar</span><span className="geo-corto" aria-hidden="true">✕</span></button>
      </div>
      {editable ? (
        <div className="cua-herr" role="toolbar" aria-label="Herramientas del cuaderno" data-testid="cua-herr">
          <div className="cua-menu">
            <button type="button" className="cua-h" aria-expanded={menu === "problema"} aria-pressed={herr?.t === "problema"} data-testid="cua-h-problema" onClick={() => setMenu(menu === "problema" ? "" : "problema")}>Problema</button>
            {menu === "problema" ? (
              <div className="cua-desplegable" role="menu" data-testid="cua-lista-problema">
                {ICONOS_PROBLEMA.map((i) => <button key={i.codigo} type="button" role="menuitem" data-sub={i.codigo} onClick={() => elegir({ t: "problema", sub: i.codigo })}><img src={urlProblema(i.codigo)} alt="" width={21} height={27} />{i.nombre}</button>)}
              </div>) : null}
          </div>
          <div className="cua-menu">
            <button type="button" className="cua-h" aria-expanded={menu === "activo"} aria-pressed={herr?.t === "activo"} data-testid="cua-h-activo" onClick={() => setMenu(menu === "activo" ? "" : "activo")}>Activo</button>
            {menu === "activo" ? (
              <div className="cua-desplegable" role="menu" data-testid="cua-lista-activo">
                <div className="geo-seg cua-sistema" role="group" aria-label="Sistema del activo">
                  {(["acueducto", "alcantarillado"] as const).map((s) => <button key={s} type="button" aria-pressed={sistema === s} data-sistema={s} onClick={() => setSistema(s)}>{s === "acueducto" ? "Acueducto" : "Alcantarillado"}</button>)}
                </div>
                <p className="cua-nota">Es una propuesta: no crea un activo en la red.</p>
                <div className="cua-rejilla">
                  {ICONOS_ACTIVO.map((i) => <button key={i.codigo} type="button" role="menuitem" data-sub={i.codigo} onClick={() => elegir({ t: "activo", sub: i.codigo, sistema })}><img src={urlActivo(i.codigo, sistema)} alt="" width={30} height={30} />{i.nombre}</button>)}
                </div>
              </div>) : null}
          </div>
          <button type="button" className="cua-h" aria-pressed={herr?.t === "referencia"} data-testid="cua-h-referencia" onClick={() => elegir(herr?.t === "referencia" ? null : { t: "referencia" })}>Referencia</button>
          <button type="button" className="cua-h" aria-pressed={herr?.t === "postit"} data-testid="cua-h-postit" onClick={() => elegir(herr?.t === "postit" ? null : { t: "postit" })}>Post-it</button>
          <div className="cua-menu cua-solo-escritorio">
            <button type="button" className="cua-h" aria-expanded={menu === "dibujo"} aria-pressed={!!herr && ["mano", "circulo", "linea", "zona"].includes(herr.t)} data-testid="cua-h-dibujo" onClick={() => setMenu(menu === "dibujo" ? "" : "dibujo")}>Dibujo</button>
            {menu === "dibujo" ? (
              <div className="cua-desplegable" role="menu" data-testid="cua-lista-dibujo">
                {(["mano", "circulo", "linea", "zona"] as const).map((t) => <button key={t} type="button" role="menuitem" data-dibujo={t} onClick={() => elegir({ t })}>{NOMBRE_HERR[t]}</button>)}
              </div>) : null}
          </div>
          <button type="button" className="cua-h" aria-pressed={herr?.t === "mover"} data-testid="cua-h-mover" onClick={() => { const s = sel; elegir(herr?.t === "mover" ? null : { t: "mover" }); if (herr?.t !== "mover") setSel(s); }}>Mover</button>
          <button type="button" className="cua-h" aria-pressed={herr?.t === "goma"} data-testid="cua-h-goma" onClick={() => elegir(herr?.t === "goma" ? null : { t: "goma" })}>Borrador</button>
          <span className="cua-pasos" role="group" aria-label="Deshacer y rehacer">
            <button type="button" className="cua-h" data-testid="cua-deshacer-paso" aria-label="Deshacer" title="Deshacer" disabled={!hist.current.pasado.length} onClick={irAtras}>↶</button>
            <button type="button" className="cua-h" data-testid="cua-rehacer-paso" aria-label="Rehacer" title="Rehacer" disabled={!hist.current.futuro.length} onClick={irAdelante}>↷</button>
          </span>
          {herr ? <button type="button" className="cua-h cua-soltar" data-testid="cua-soltar" onClick={() => elegir(null)}>Mover el mapa</button> : null}
        </div>) : null}
      {herr ? (
        <div className="cua-activa" role="status" data-testid="cua-activa">
          <strong>{nombreHerr}</strong><span>{ayuda}</span>
          {conEstilo ? <span className="cua-colores" role="group" aria-label="Color">{COLORES_LIBRES.map((c) => <button key={c} type="button" aria-pressed={color === c} aria-label={`Color ${c}`} style={{ background: c }} onClick={() => setColor(c)} />)}</span> : null}
          {herr.t === "mano" || herr.t === "linea" || herr.t === "circulo" ? <label className="cua-grosor">Grosor <input type="range" min={2} max={herr.t === "mano" ? 12 : 8} value={Math.min(grosor, herr.t === "mano" ? 12 : 8)} onChange={(ev) => setGrosor(Number(ev.target.value))} /></label> : null}
          {medida ? <strong data-testid="cua-medida">{medida}</strong> : null}
          {(herr.t === "linea" && curso.length >= 2) || (herr.t === "zona" && curso.length >= 3) ? <button type="button" className="tec-boton" data-testid="cua-terminar" onClick={terminar}>Terminar</button> : null}
          {curso.length && herr.t !== "mano" ? <button type="button" className="tec-boton-sec" data-testid="cua-deshacer" onClick={() => setCurso(curso.slice(0, -1))}>Quitar el último punto</button> : null}
          {herr.t === "medir" ? <button type="button" className="tec-boton-sec" data-testid="cua-medir-fin" onClick={() => elegir(null)}>Dejar de medir</button> : null}
        </div>) : null}
      {aviso ? <p className={aviso.error ? "cua-aviso cua-aviso-error" : "cua-aviso"} role={aviso.error ? "alert" : "status"} data-testid="cua-aviso">{aviso.texto}<button type="button" className="cua-x" aria-label="Cerrar el aviso" onClick={() => setAviso(null)}>✕</button></p> : null}
      {ocupado ? <p className="cua-aviso" role="status" data-testid="cua-ocupado">{ocupado}</p> : null}
    </div>) : null;

  return (
    <>
      {barra && ranura ? createPortal(barra, ranura) : null}
      {!cuad && (aviso || ocupado) && !lista ? <p className={aviso?.error ? "cua-flotante cua-aviso-error" : "cua-flotante"} role="status">{ocupado || aviso?.texto}</p> : null}
      {lista ? <ListaCuadernos perfil={perfil} abierto={cuad?.id ?? null} onCerrar={() => onLista(false)} onAbrir={(id) => conCambiosPendientes(() => { void abrir(id); })} onNuevo={() => conCambiosPendientes(() => setDialogo({ d: "nuevo" }))} /> : null}
      {marcaSel && cuad && !dialogo && herr?.t !== "mover" && herr?.t !== "goma" ? <FichaMarca key={marcaSel.id} m={marcaSel} editable={editable} guardada={cuad.marcas.some((x) => x.id === marcaSel.id)} categorias={perfil.categorias}
        onCerrar={() => setSel(null)} onCambiar={(d) => cambiar(marcaSel.id, d, "nota" in d ? `nota:${marcaSel.id}` : "")} onMover={() => { setHerr({ t: "mover" }); setCurso([]); setMenu(""); }}
        onQuitar={(motivo) => { aplicar((p) => conAnulacion(cuad.marcas, p, marcaSel.id, motivo)); setSel(null); }} /> : null}
      {dialogo?.d === "nuevo" ? <Nuevo mapa={mapa} onCerrar={() => setDialogo(null)} onCreado={(id) => { setDialogo(null); void abrir(id).then(() => setModo("editar")); }} /> : null}
      {dialogo?.d === "postit" ? <TextoPostit onCerrar={() => setDialogo(null)} onListo={(t) => { agregar(marcaNueva({ tipo: "postit", geom: punto(dialogo.lon, dialogo.lat), nota: t })); setDialogo(null); }} /> : null}
      {dialogo?.d === "salir" ? (
        <Caja titulo="Hay cambios sin guardar" testid="cua-dialogo-salir" onCerrar={() => setDialogo(null)}>
          <p>El cuaderno «{cuad?.titulo}» tiene {nPend} {nPend === 1 ? "cambio" : "cambios"} sin guardar.</p>
          <div className="geo-imprimir-acciones">
            <button type="button" className="tec-boton-sec" data-testid="cua-salir-cancelar" onClick={() => setDialogo(null)}>Cancelar</button>
            <button type="button" className="tec-boton-sec" data-testid="cua-salir-sin" onClick={() => { const s = dialogo.seguir; if (cuad) borrarBorrador(perfil.email, cuad.id); sinHistoria({}); E.current.nPend = 0; setDialogo(null); s(); }}>Salir sin guardar</button>
            <button type="button" className="tec-boton" data-testid="cua-salir-guardar" disabled={!!ocupado} onClick={() => { const s = dialogo.seguir; void guardar().then((bien) => { if (bien) { setDialogo(null); s(); } else setDialogo(null); }); }}>Guardar</button>
          </div>
        </Caja>) : null}
      {dialogo?.d === "borrador" && cuad ? (
        <Caja titulo="Hay un borrador sin guardar" testid="cua-dialogo-borrador" onCerrar={() => setDialogo(null)}>
          <p>En este dispositivo quedó un borrador de este cuaderno, del {fecha(dialogo.b.guardado_en)}, con {Object.keys(dialogo.b.pend).length} {Object.keys(dialogo.b.pend).length === 1 ? "cambio" : "cambios"}.</p>
          {dialogo.b.version_base !== cuad.version ? <p className="geo-imprimir-aviso">El borrador se hizo sobre la versión {dialogo.b.version_base} y el cuaderno ya va en la {cuad.version}: revise las marcas antes de guardar.</p> : null}
          <div className="geo-imprimir-acciones">
            <button type="button" className="tec-boton-sec" data-testid="cua-borrador-descartar" onClick={() => { borrarBorrador(perfil.email, cuad.id); setDialogo(null); }}>Descartar el borrador</button>
            <button type="button" className="tec-boton" data-testid="cua-borrador-recuperar" onClick={() => { sinHistoria(dialogo.b.pend); setModo("editar"); setDialogo(null); }}>Recuperar</button>
          </div>
        </Caja>) : null}
      {dialogo?.d === "capturar" && cuad && mapa ? <Capturar cuad={cuad} mapa={mapa} marcas={visibles} perfil={perfil} onCerrar={() => setDialogo(null)}
        onGuardada={(k) => { setCuad((p) => (p ? { ...p, capturas: [...p.capturas, k] } : p)); }} /> : null}
      {dialogo?.d === "capturas" && cuad ? <Capturas cuad={cuad} tope={perfil.topes.capturas_por_cuaderno} onCerrar={() => setDialogo(null)} onAnulada={(id) => setCuad((p) => (p ? { ...p, capturas: p.capturas.filter((k) => k.id !== id) } : p))} /> : null}
      {dialogo?.d === "estado" && cuad ? <Estado cuad={cuad} onCerrar={() => setDialogo(null)} onHecho={() => { setDialogo(null); void abrir(cuad.id); }} /> : null}
      {dialogo?.d === "datos" && cuad ? (
        <Caja titulo="Versiones y datos del cuaderno" testid="cua-dialogo-datos" onCerrar={() => setDialogo(null)}>
          {cuad.puede_editar ? <Renombrar cuad={cuad} bloqueado={!!nPend} onHecho={() => { setDialogo(null); void abrir(cuad.id); }} /> : <p><strong>{cuad.titulo}</strong>{cuad.descripcion ? ` — ${cuad.descripcion}` : ""}</p>}
          <p>Autor: {cuad.autor_nombre ?? cuad.autor}. Creado el {fecha(cuad.creado_en)}.</p>
          {cuad.eventos.length ? <ul className="cua-lista-simple">{cuad.eventos.map((e, i) => <li key={i}>{e.tipo === "archivar" ? "Archivado" : "Reabierto"} el {fecha(e.creado_en)}: {e.motivo}</li>)}</ul> : null}
          {nPend ? <p className="geo-imprimir-aviso">Guarde los cambios antes de abrir otra versión.</p> : null}
          <ul className="cua-versiones" data-testid="cua-versiones">
            {cuad.versiones.map((v) => <li key={v.version}><span>Versión {v.version} · {fecha(v.creado_en)}</span>
              {v.version === cuad.version ? <em>abierta</em> : <button type="button" className="tec-boton-sec" disabled={!!nPend} data-version={v.version} onClick={() => { setDialogo(null); void abrir(cuad.id, v.version === cuad.ultima_version ? undefined : v.version); }}>{v.version === cuad.ultima_version ? "Volver a la última" : "Ver"}</button>}</li>)}
          </ul>
        </Caja>) : null}
    </>
  );
}

const nombreArchivo = (t: string) => t.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 40) || "cuaderno";
function descargar(b: Blob, nombre: string) {
  const url = URL.createObjectURL(b), a = document.createElement("a");
  a.href = url; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function Caja({ titulo, testid, onCerrar, children }: { titulo: string; testid: string; onCerrar: () => void; children: React.ReactNode }) {
  return (
    <div className="geo-imprimir cua-dialogo" role="dialog" aria-modal="true" aria-label={titulo} data-testid={testid}>
      <div className="geo-imprimir-caja">
        <div className="geo-panel-cab"><h2>{titulo}</h2><button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar">✕</button></div>
        {children}
      </div>
    </div>);
}

function ListaCuadernos({ perfil, abierto, onCerrar, onAbrir, onNuevo }: { perfil: PerfilAnalisis; abierto: string | null; onCerrar: () => void; onAbrir: (id: string) => void; onNuevo: () => void }) {
  const [arch, setArch] = useState(false);
  const [d, setD] = useState<CuadernoLista[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setD(null); setError(null); apiAnalisis.cuadernos(arch).then((r) => { if (vivo) setD(r.cuadernos); }).catch((e) => { if (vivo) setError(mensaje(e, "No se pudo cargar la lista.")); }); return () => { vivo = false; }; }, [arch]);
  const grupo = (titulo: string, l: CuadernoLista[], vacio: string) => (
    <section className="geo-grupo"><h3>{titulo}</h3>
      {l.length ? <ul className="cua-lista">{l.map((c) => (
        <li key={c.id}><button type="button" data-cuaderno={c.id} aria-current={abierto === c.id} onClick={() => onAbrir(c.id)}>
          <strong>{c.titulo}</strong>
          <span>{c.es_mio ? "" : `${c.autor_nombre ?? c.autor} · `}versión {c.version} · {miles(c.marcas)} {c.marcas === 1 ? "marca" : "marcas"}{c.capturas ? ` · ${c.capturas} ${c.capturas === 1 ? "captura" : "capturas"}` : ""} · {fecha(c.actualizado_en)}</span>
          {c.descripcion ? <em>{c.descripcion}</em> : null}</button></li>))}</ul> : <p className="tec-ayuda">{vacio}</p>}
    </section>);
  return (
    <aside className="geo-panel cua-panel" aria-label="Cuadernos de análisis" data-testid="cua-panel">
      <div className="geo-panel-cab"><h2>Cuadernos de análisis</h2><button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar los cuadernos">✕</button></div>
      <p className="tec-ayuda">Un cuaderno es un vidrio sobre el mapa para marcar problemas, propuestas y notas. Lo ven su autor y los supervisores de Técnica; lo edita solo su autor.</p>
      <div className="cua-panel-acc">
        {perfil.puede_crear ? <button type="button" className="tec-boton" data-testid="cua-nuevo" onClick={onNuevo}>Nuevo cuaderno</button> : null}
        <div className="geo-seg" role="group" aria-label="Cuadernos que se muestran">
          <button type="button" aria-pressed={!arch} onClick={() => setArch(false)}>Vigentes</button><button type="button" aria-pressed={arch} data-testid="cua-archivados" onClick={() => setArch(true)}>Archivados</button>
        </div>
      </div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      {!d && !error ? <p role="status">Cargando…</p> : null}
      {d ? <>{grupo("Míos", d.filter((c) => c.es_mio), arch ? "No tiene cuadernos archivados." : "Aún no tiene cuadernos.")}{grupo("Del equipo", d.filter((c) => !c.es_mio), arch ? "No hay cuadernos archivados del equipo." : "Aún no hay cuadernos de otras personas.")}</> : null}
    </aside>);
}

function Nuevo({ mapa, onCerrar, onCreado }: { mapa: maplibregl.Map | null; onCerrar: () => void; onCreado: (id: string) => void }) {
  const [titulo, setTitulo] = useState(""); const [desc, setDesc] = useState(""); const [error, setError] = useState<string | null>(null); const [ocupado, setOcupado] = useState(false);
  const crear = async () => {
    setOcupado(true); setError(null);
    try {
      const c = mapa?.getCenter();
      const r = await apiAnalisis.crear(titulo.trim(), desc.trim() || null, c && mapa ? { lon: Number(c.lng.toFixed(6)), lat: Number(c.lat.toFixed(6)), zoom: Number(mapa.getZoom().toFixed(2)) } : null);
      onCreado(r.id);
    } catch (e) { setError(mensaje(e, "No se pudo crear el cuaderno.")); setOcupado(false); }
  };
  return (
    <Caja titulo="Nuevo cuaderno" testid="cua-dialogo-nuevo" onCerrar={onCerrar}>
      <div className="tec-campo"><label htmlFor="cua-n-titulo">Título</label><input id="cua-n-titulo" value={titulo} maxLength={120} onChange={(e) => setTitulo(e.target.value)} placeholder="Por ejemplo: Baja presión en el sector 3" /></div>
      <div className="tec-campo"><label htmlFor="cua-n-desc">Descripción (opcional)</label><textarea id="cua-n-desc" value={desc} maxLength={1000} rows={3} onChange={(e) => setDesc(e.target.value)} /><small className="cua-aviso-nota">{AVISO_NOTA}.</small></div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      <div className="geo-imprimir-acciones"><button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        <button type="button" className="tec-boton" data-testid="cua-crear" disabled={ocupado || titulo.trim().length < 3} onClick={() => { void crear(); }}>{ocupado ? "Creando…" : "Crear y editar"}</button></div>
    </Caja>);
}

function TextoPostit({ onCerrar, onListo }: { onCerrar: () => void; onListo: (t: string) => void }) {
  const [t, setT] = useState("");
  return (
    <Caja titulo="Post-it" testid="cua-dialogo-postit" onCerrar={onCerrar}>
      <div className="tec-campo"><label htmlFor="cua-postit">Texto del post-it</label><textarea id="cua-postit" autoFocus value={t} maxLength={NOTA_MAX} rows={4} onChange={(e) => setT(e.target.value)} /><small className="cua-aviso-nota" data-testid="cua-aviso-nota">{AVISO_NOTA}.</small></div>
      <div className="geo-imprimir-acciones"><button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button><button type="button" className="tec-boton" data-testid="cua-postit-poner" disabled={!t.trim()} onClick={() => onListo(t.trim())}>Pegar</button></div>
    </Caja>);
}

function FichaMarca({ m, editable, guardada, categorias, onCerrar, onCambiar, onMover, onQuitar }: {
  m: Marca & { pendiente?: boolean }; editable: boolean; guardada: boolean; categorias: Categoria[]; onCerrar: () => void;
  onCambiar: (d: { nota?: string | null; categoria?: Categoria | null; estilo?: { color?: string; grosor?: number } | null }) => void; onMover: () => void; onQuitar: (motivo: string) => void;
}) {
  const [quitar, setQuitar] = useState(false); const [motivo, setMotivo] = useState("");
  const [conteo, setConteo] = useState<{ predios: number; contratos: number } | string | null>(null);
  const conColor = m.tipo === "referencia" || m.tipo === "mano" || m.tipo === "linea" || m.tipo === "circulo" || m.tipo === "zona";
  const c = m.geom.type === "LineString" ? m.geom.coordinates : m.geom.type === "Polygon" ? m.geom.coordinates[0] : null;
  return (
    <div className="geo-tarjeta cua-ficha" role="dialog" aria-label={`Marca: ${rotulo(m)}`} data-testid="cua-ficha" data-tipo={m.tipo}>
      <div className="geo-tarjeta-cab"><div><h2>{rotulo(m)}</h2><p>{m.pendiente ? "Sin guardar" : `Guardada en la versión ${m.version}`}{m.sector ? ` · Sector ${m.sector}${m.subsector ? ` · ${m.subsector}` : ""}` : ""}</p></div>
        <button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la marca">✕</button></div>
      <dl>
        {m.tipo === "circulo" ? <><dt>Radio</dt><dd>{textoDistancia(m.radio_m ?? 0)}</dd></> : null}
        {m.geom.type === "LineString" && c ? <><dt>Longitud</dt><dd>{textoDistancia(largo(c))}</dd></> : null}
        {m.tipo === "zona" && c ? <><dt>Área</dt><dd>{textoArea(area(c.slice(0, -1)))}</dd><dt>Predios y contratos</dt>
          <dd data-testid="cua-conteo">{m.conteo_predios !== null ? `${miles(m.conteo_predios)} predios · ${miles(m.conteo_contratos ?? 0)} contratos`
            : conteo && typeof conteo === "object" ? `${miles(conteo.predios)} predios · ${miles(conteo.contratos)} contratos (al guardar queda en el cuaderno)` : typeof conteo === "string" ? conteo : "Se cuentan al guardar"}</dd></> : null}
        {!editable && m.categoria ? <><dt>Categoría</dt><dd>{NOMBRE_CATEGORIA[m.categoria]}</dd></> : null}
      </dl>
      {editable ? <>
        <div className="tec-campo"><label htmlFor="cua-f-nota">{m.tipo === "postit" ? "Texto" : "Nota"}</label>
          <textarea id="cua-f-nota" data-testid="cua-nota" rows={3} maxLength={NOTA_MAX} value={m.nota ?? ""} onChange={(e) => onCambiar({ nota: e.target.value || null })} />
          <small className="cua-aviso-nota" data-testid="cua-aviso-nota">{AVISO_NOTA}.</small></div>
        <div className="tec-campo"><label htmlFor="cua-f-cat">Categoría</label>
          <select id="cua-f-cat" data-testid="cua-categoria" value={m.categoria ?? ""} onChange={(e) => onCambiar({ categoria: (e.target.value || null) as Categoria | null })}>
            <option value="">Sin categoría</option>{categorias.map((k) => <option key={k} value={k}>{NOMBRE_CATEGORIA[k] ?? k}</option>)}</select></div>
        {conColor ? <div className="cua-colores" role="group" aria-label="Color de la marca">{COLORES_LIBRES.map((k) => <button key={k} type="button" aria-pressed={m.estilo?.color === k} aria-label={`Color ${k}`} style={{ background: k }} onClick={() => onCambiar({ estilo: { ...(m.estilo ?? {}), color: k } })} />)}</div> : null}
      </> : m.nota ? <p className="cua-nota-leida" data-testid="cua-nota-leida">{m.nota}</p> : null}
      {editable && !quitar ? (
        <div className="geo-tarjeta-acc">
          <button type="button" className="tec-boton-sec" data-testid="cua-mover" onClick={onMover}>Mover</button>
          {m.tipo === "zona" && m.conteo_predios === null ? <button type="button" className="tec-boton-sec" data-testid="cua-contar" disabled={conteo === "Contando…"}
            onClick={() => { setConteo("Contando…"); apiAnalisis.zona(m.geom).then(setConteo).catch((e) => setConteo(mensaje(e, "No se pudo contar."))); }}>Contar ahora</button> : null}
          <button type="button" className="tec-boton-sec" data-testid="cua-quitar" onClick={() => (guardada ? setQuitar(true) : onQuitar(""))}>{guardada ? "Anular…" : "Quitar"}</button>
        </div>) : null}
      {editable && quitar ? (
        <div className="tec-campo"><label htmlFor="cua-f-motivo">Motivo para anular la marca (no se borra: queda en el historial)</label>
          <input id="cua-f-motivo" data-testid="cua-motivo" value={motivo} maxLength={300} onChange={(e) => setMotivo(e.target.value)} />
          <div className="geo-tarjeta-acc"><button type="button" className="tec-boton-sec" onClick={() => setQuitar(false)}>Cancelar</button>
            <button type="button" className="tec-boton" data-testid="cua-anular" disabled={motivo.trim().length < 5} onClick={() => onQuitar(motivo.trim())}>Anular la marca</button></div></div>) : null}
    </div>);
}

/** La vista con las marcas, en JPEG: lado mayor de hasta `lado` px y peso bajo `maxBytes` (se baja la calidad y, si no alcanza, el tamaño). */
async function capturarVista(mapa: maplibregl.Map, marcas: Marca[], titulo: string, lado: number, maxBytes: number): Promise<{ blob: Blob; ancho: number; alto: number; extension: [number, number, number, number] }> {
  // El lienzo del mapa (WebGL, sin preserveDrawingBuffer) solo se puede copiar en el MISMO turno en que se pinta: se le obliga a pintar y se copia enseguida.
  // Antes se espera (hasta 8 s) a que las teselas de la vista estén cargadas, para que no salga a medias.
  for (let fin = Date.now() + 8000; Date.now() < fin && !(mapa.loaded() && mapa.areTilesLoaded());) { mapa.redraw(); await new Promise((r) => setTimeout(r, 150)); }
  mapa.redraw();
  const o = mapa.getCanvas(), origen = document.createElement("canvas"); origen.width = o.width; origen.height = o.height; origen.getContext("2d")!.drawImage(o, 0, 0);
  if (lienzoVacio(origen)) throw new Error("El mapa no se pudo copiar. Deje esta pestaña a la vista y vuelva a intentarlo.");
  const cont = mapa.getContainer(), w = cont.clientWidth, h = cont.clientHeight, b = mapa.getBounds();
  const extension: [number, number, number, number] = [Number(b.getWest().toFixed(6)), Number(b.getSouth().toFixed(6)), Number(b.getEast().toFixed(6)), Number(b.getNorth().toFixed(6))];
  let s = Math.min(lado / Math.max(w, h), 2);
  for (let intento = 0; intento < 5; intento++) {
    const c = document.createElement("canvas"); c.width = Math.round(w * s); c.height = Math.round(h * s);
    const x = c.getContext("2d")!; x.fillStyle = "#fff"; x.fillRect(0, 0, c.width, c.height); x.drawImage(origen, 0, 0, c.width, c.height);
    pintarMarcas({ x, proy: (lon, lat) => { const p = mapa.project([lon, lat]); return [p.x * s, p.y * s]; }, k: s, mpp: (lat) => mppMapa(mapa, lat) / s }, marcas);
    const t = `${titulo} · ${new Date().toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short", timeZone: "America/Bogota" })} · EMDUPAR, geovisor técnico`;
    x.font = `600 ${Math.max(10, 12 * s)}px Helvetica, Arial, sans-serif`; x.textBaseline = "middle";
    const alto = Math.max(18, 22 * s); x.fillStyle = "rgba(255,255,255,0.88)"; x.fillRect(0, c.height - alto, Math.min(c.width, x.measureText(t).width + 16 * s), alto); x.fillStyle = "#1b2733"; x.fillText(t, 8 * s, c.height - alto / 2, c.width - 16 * s);
    for (const q of [0.82, 0.72, 0.62, 0.52]) {
      const blob = await new Promise<Blob | null>((ok) => c.toBlob(ok, "image/jpeg", q));
      if (!blob) throw new Error("No se pudo preparar la imagen.");
      if (blob.size <= Math.min(maxBytes, 360 * 1024) || (q === 0.52 && blob.size <= maxBytes)) return { blob, ancho: c.width, alto: c.height, extension };
    }
    s *= 0.8;
  }
  throw new Error("La imagen quedó demasiado pesada: aleje menos capas o use el mapa de calles.");
}
const sha256 = async (b: Blob) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", await b.arrayBuffer()))].map((x) => x.toString(16).padStart(2, "0")).join("");

function Capturar({ cuad, mapa, marcas, perfil, onCerrar, onGuardada }: { cuad: Cuaderno; mapa: maplibregl.Map; marcas: Marca[]; perfil: PerfilAnalisis; onCerrar: () => void; onGuardada: (k: Cuaderno["capturas"][number]) => void }) {
  const [titulo, setTitulo] = useState(""); const [estado, setEstado] = useState(""); const [error, setError] = useState<string | null>(null); const [hecho, setHecho] = useState<string | null>(null);
  const lleno = cuad.capturas.length >= perfil.topes.capturas_por_cuaderno;
  const puedeGuardar = cuad.es_mio && !cuad.archivado && cuad.version === cuad.ultima_version;
  const hacer = async (guardar: boolean) => {
    setError(null); setHecho(null); setEstado("Preparando la imagen…");
    try {
      const t = titulo.trim() || cuad.titulo;
      const k = await capturarVista(mapa, marcas, t, perfil.topes.captura_lado_max_px, perfil.topes.captura_bytes_max);
      (window as unknown as { __captura?: unknown }).__captura = { ancho: k.ancho, alto: k.alto, bytes: k.blob.size, guardar };      // para las pruebas en Chrome
      if (!guardar) { descargar(k.blob, `captura_${nombreArchivo(t)}.jpg`); setHecho(`Descargada (${Math.round(k.blob.size / 1024)} KB, ${k.ancho} × ${k.alto} px).`); setEstado(""); return; }
      setEstado("Guardando en el cuaderno…");
      const f = await apiAnalisis.capturaFirmar({ id: cuad.id, titulo: t, extension: k.extension, ancho: k.ancho, alto: k.alto, bytes: k.blob.size, sha256: await sha256(k.blob) });
      await subirCaptura(f.url_subida, k.blob);
      await apiAnalisis.capturaConfirmar(f.captura_id);
      onGuardada({ id: f.captura_id, titulo: t, extension: k.extension, ancho: k.ancho, alto: k.alto, bytes: k.blob.size, creado_en: new Date().toISOString() });
      setHecho(`Guardada en el cuaderno (${Math.round(k.blob.size / 1024)} KB).`); setEstado("");
    } catch (e) { setEstado(""); setError(e instanceof DOMException ? "El navegador no dejó copiar la foto satelital: cambie a «Calles» e intente de nuevo." : mensaje(e, "No se pudo hacer la captura.")); }
  };
  return (
    <Caja titulo="Captura de la vista" testid="cua-dialogo-capturar" onCerrar={onCerrar}>
      <p>La imagen lleva el mapa como se ve ahora y las marcas del cuaderno. No lleva tarjetas ni datos de contratos.</p>
      <div className="tec-campo"><label htmlFor="cua-c-titulo">Título de la captura</label><input id="cua-c-titulo" data-testid="cua-captura-titulo" value={titulo} maxLength={120} placeholder={cuad.titulo} onChange={(e) => setTitulo(e.target.value)} /></div>
      {puedeGuardar ? <p className="tec-ayuda" data-testid="cua-captura-cupo">Capturas guardadas: {cuad.capturas.length} de {perfil.topes.capturas_por_cuaderno}.</p> : <p className="tec-ayuda">Solo el autor guarda capturas en el cuaderno{cuad.archivado ? " (y está archivado)" : ""}; usted puede descargarla.</p>}
      {estado ? <p role="status" data-testid="cua-captura-estado">{estado}</p> : null}
      {hecho ? <p role="status" data-testid="cua-captura-hecho">{hecho}</p> : null}
      {error ? <p className="tec-error-caja" role="alert" data-testid="cua-captura-error">{error}</p> : null}
      <div className="geo-imprimir-acciones">
        <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cerrar</button>
        <button type="button" className="tec-boton-sec" data-testid="cua-captura-descargar" disabled={!!estado} onClick={() => { void hacer(false); }}>Descargar</button>
        {puedeGuardar ? <button type="button" className="tec-boton" data-testid="cua-captura-guardar" disabled={!!estado || lleno || (titulo.trim().length > 0 && titulo.trim().length < 3)} onClick={() => { void hacer(true); }}>{lleno ? "Cupo lleno" : "Guardar en el cuaderno"}</button> : null}
      </div>
    </Caja>);
}

function Capturas({ cuad, tope, onCerrar, onAnulada }: { cuad: Cuaderno; tope: number; onCerrar: () => void; onAnulada: (id: string) => void }) {
  const [error, setError] = useState<string | null>(null); const [anular, setAnular] = useState<string | null>(null); const [motivo, setMotivo] = useState(""); const [ocupado, setOcupado] = useState(false);
  const ver = async (id: string) => {
    setError(null); const v = window.open("", "_blank");      // la pestaña se abre con el toque; la dirección (60 s) llega después
    try { const r = await apiAnalisis.capturaUrl(id); if (v) v.location.href = r.url; else window.location.href = r.url; } catch (e) { v?.close(); setError(mensaje(e, "No se pudo abrir la captura.")); }
  };
  return (
    <Caja titulo="Capturas guardadas" testid="cua-dialogo-capturas" onCerrar={onCerrar}>
      <p className="tec-ayuda">{cuad.capturas.length} de {tope}. Las ve quien puede ver el cuaderno. Una captura no se borra: se anula con motivo y deja de contar.</p>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      {cuad.capturas.length ? <ul className="cua-versiones" data-testid="cua-capturas-lista">{cuad.capturas.map((k) => (
        <li key={k.id} data-captura={k.id}><span><strong>{k.titulo}</strong><br />{fecha(k.creado_en)} · {k.ancho} × {k.alto} px · {Math.round(k.bytes / 1024)} KB</span>
          <span className="cua-fila-acc"><button type="button" className="tec-boton-sec" data-testid="cua-captura-ver" onClick={() => { void ver(k.id); }}>Ver</button>
            {cuad.es_mio && !cuad.archivado ? <button type="button" className="tec-boton-sec" data-testid="cua-captura-anular" onClick={() => { setAnular(k.id); setMotivo(""); }}>Anular…</button> : null}</span>
          {anular === k.id ? <div className="tec-campo cua-ancho"><label htmlFor="cua-k-motivo">Motivo para anular la captura</label><input id="cua-k-motivo" data-testid="cua-captura-motivo" value={motivo} maxLength={300} onChange={(e) => setMotivo(e.target.value)} />
            <div className="geo-imprimir-acciones"><button type="button" className="tec-boton-sec" onClick={() => setAnular(null)}>Cancelar</button>
              <button type="button" className="tec-boton" data-testid="cua-captura-anular-si" disabled={ocupado || motivo.trim().length < 5}
                onClick={() => { setOcupado(true); setError(null); apiAnalisis.capturaAnular(k.id, motivo.trim()).then(() => { onAnulada(k.id); setAnular(null); }).catch((e) => setError(mensaje(e, "No se pudo anular."))).finally(() => setOcupado(false)); }}>Anular la captura</button></div></div> : null}
        </li>))}</ul> : <p>Este cuaderno aún no tiene capturas guardadas.</p>}
    </Caja>);
}

function Renombrar({ cuad, bloqueado, onHecho }: { cuad: Cuaderno; bloqueado: boolean; onHecho: () => void }) {
  const [titulo, setTitulo] = useState(cuad.titulo); const [desc, setDesc] = useState(cuad.descripcion ?? ""); const [error, setError] = useState<string | null>(null); const [ocupado, setOcupado] = useState(false);
  const igual = titulo.trim() === cuad.titulo && desc.trim() === (cuad.descripcion ?? "");
  return (
    <div className="cua-renombrar" data-testid="cua-renombrar">
      <div className="tec-campo"><label htmlFor="cua-r-titulo">Título</label><input id="cua-r-titulo" data-testid="cua-r-titulo" value={titulo} maxLength={120} onChange={(e) => setTitulo(e.target.value)} /></div>
      <div className="tec-campo"><label htmlFor="cua-r-desc">Descripción</label><textarea id="cua-r-desc" data-testid="cua-r-desc" rows={2} value={desc} maxLength={1000} onChange={(e) => setDesc(e.target.value)} /><small className="cua-aviso-nota">{AVISO_NOTA}.</small></div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      <div className="geo-imprimir-acciones"><button type="button" className="tec-boton" data-testid="cua-r-guardar" disabled={ocupado || bloqueado || igual || titulo.trim().length < 3}
        onClick={() => { setOcupado(true); setError(null); apiAnalisis.renombrar(cuad.id, cuad.version, titulo.trim(), desc.trim()).then(onHecho).catch((e) => { setError(mensaje(e, "No se pudo cambiar el nombre.")); setOcupado(false); }); }}>Guardar el nombre (versión nueva)</button></div>
    </div>);
}

function Estado({ cuad, onCerrar, onHecho }: { cuad: Cuaderno; onCerrar: () => void; onHecho: () => void }) {
  const [motivo, setMotivo] = useState(""); const [error, setError] = useState<string | null>(null); const [ocupado, setOcupado] = useState(false);
  const archivar = !cuad.archivado;
  return (
    <Caja titulo={archivar ? "Archivar el cuaderno" : "Reabrir el cuaderno"} testid="cua-dialogo-estado" onCerrar={onCerrar}>
      <p>{archivar ? "El cuaderno no se borra: sale de la lista de vigentes y queda en «Archivados», sin poder editarse hasta reabrirlo." : "El cuaderno vuelve a la lista de vigentes y se puede editar otra vez."}</p>
      <div className="tec-campo"><label htmlFor="cua-e-motivo">Motivo</label><input id="cua-e-motivo" data-testid="cua-estado-motivo" value={motivo} maxLength={300} onChange={(e) => setMotivo(e.target.value)} /></div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      <div className="geo-imprimir-acciones"><button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        <button type="button" className="tec-boton" data-testid="cua-estado-si" disabled={ocupado || motivo.trim().length < 5}
          onClick={() => { setOcupado(true); setError(null); (archivar ? apiAnalisis.archivar : apiAnalisis.reabrir)(cuad.id, motivo.trim()).then(onHecho).catch((e) => { setError(mensaje(e, "No se pudo cambiar el estado.")); setOcupado(false); }); }}>{archivar ? "Archivar" : "Reabrir"}</button></div>
    </Caja>);
}
