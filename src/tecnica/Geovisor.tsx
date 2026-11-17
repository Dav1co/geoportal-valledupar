import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import "./geovisor.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import { apiGeovisor, type CapaDatos, type CapaGeovisor, type ConfigGeovisor, type GrupoCapa, type NivelPresion, type PerfilGeovisor, type SerieRef, type TarjetaContrato, type TarjetaRef, type VistaAbierta } from "./apiGeovisor";
import { ErrorTec } from "./apiTecnica";
import { FichaActivo } from "./FichaActivo";
import { apiCierre, apiFlujo, horaClara, instanteDeCampo, nContratos, type CortesVigentes, type FlujoInfo, type FlujoTramo, type ValvulaCerrada, type ZonaCorte } from "./apiCierre";
import { PedirHora } from "./PanelCierre";

// Geovisor técnico (Técnica fase 1, Corte 6a; 01 sección D, N-11, N-13 y N-14).
// · Interruptores por grupo, encendidos al abrir según el perfil (lo decide el servidor) y «Volver a la vista por omisión». Encender o apagar no se guarda.
// · Red en una tesela propia (activos vigentes, con material, diámetro, edad y estado); colores por tipo, por material o por edad.
// · Corte 5d: la línea 116 («pqr_116», solo supervisores) por fecha, color por servicio y estado, los repetidos del mismo contrato, causal y día en un punto;
//   en el predio de su contrato (única forma de ubicar); sin nombre, dirección ni barrio; la leyenda dice cuántos del periodo no tienen ubicación.
// · Daños, intervenciones y reportes del bot por fecha (hoy, últimos 7 días o un rango de hasta 12 meses); los puntos de muestreo, verificados o aproximados.
// · Tocar un elemento abre su tarjeta. Desde un activo: «Ver ficha» (supervisores y administrador), «Reportar daño» y «Registrar intervención» (si tiene el formulario).
// · El operador con la casilla del geovisor (N-13) ve solo lectura: la red y las actividades del día, sin ficha ni capas de supervisión.
// · Las capas preparadas (contratos, reportes de Comercial, PQR, presión…) se ven en la lista, apagadas y con su nota: no tienen datos todavía.
// · Corte 6b: la capa de contratos (supervisores y administrador) y su tarjeta, con el nombre y la dirección pedidos al tocar (DATO PERSONAL: solo en pantalla,
//   la lectura queda registrada en el servidor; nunca en descargas, listados ni PDF; sin teléfono ni deuda); el muestreo coloreado por el último cloro y la
//   turbiedad frente a los rangos de Salida; la capa de reportes de Comercial (azul con contrato, rojo posible clandestino) que se puede atenuar; y
//   «Compartir» con un enlace (quien lo abre inicia sesión y ve solo las capas para las que tiene permiso).
// · Fuera de la tarjeta del contrato, nada de nombres, descripciones ni el tercero de un daño.
// · Corte 9a (Plan Maestro 2014): los sectores y subsectores PROYECTADOS por el Plan (activos SEC, encendidos al abrir) y las capas de REFERENCIA, apagadas al
//   abrir y en tesela propia: válvulas propuestas (no instaladas), red pluvial existente, alternativa pluvial a 2043, presión de MODELO (no medida) y la campaña de
//   presiones de 2014 (la única medida, con su gráfica). No son activos: su tarjeta dice de dónde salen y no ofrece reportar daño ni intervención.

type ActivoTarjeta = { codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number };
type Tarjeta = { capa: string; props: Record<string, unknown>; lat: number; lon: number };
type Periodo = { modo: "hoy" | "semana" | "rango"; desde: string; hasta: string };
type Colores = "tipo" | "material" | "edad" | "afectaciones";      // Corte 9b: «Afectaciones» es el cuarto modo (no una capa que se enciende)
type CorteSel = { tipo: "zona"; zona: number } | { tipo: "valvula"; codigo: string } | { tipo: "dano"; codigo: string } | { tipo: "recalcular" };
type DanoAbierto = { codigo: string; clase: string; tipo: string; sistema: string; estado: string; activo: string | null; cuando: string; riesgo: string; lat: number; lon: number };

const GRUPOS: { c: GrupoCapa; n: string }[] = [
  { c: "acueducto", n: "Acueducto" }, { c: "alcantarillado", n: "Alcantarillado" }, { c: "tecnologia", n: "Tecnología y pérdidas" }, { c: "actividades", n: "Actividades registradas" },
  { c: "calidad", n: "Calidad y PQR" }, { c: "reportes", n: "Reportes" }, { c: "comercial", n: "Comercial" }, { c: "analisis", n: "Análisis y operación" },
];
const PERFILES: { c: PerfilGeovisor; n: string }[] = [
  { c: "supervisor_distribucion", n: "Supervisor de distribución" }, { c: "supervisor_planta", n: "Supervisor de planta" }, { c: "operador_distribucion", n: "Operador con el geovisor" },
];
const COLOR_SISTEMA: Record<string, string> = { acueducto: "#1F5FA8", alcantarillado: "#8A5A2B", tecnologia: "#6D28D9" };
const COLOR_NODO: Record<string, string> = { VAL: "#C2410C", TOR: "#0F766E", HID: "#0F766E", ACC: "#9AA19B", MAC: "#1B1F1D", TAN: "#0A2540", PTA: "#0A2540", CAP: "#0A2540",
  DES: "#0A2540", EBA: "#0A2540", POZ: "#8A5A2B", SUM: "#A16207", VER: "#5B21B6", EBR: "#5B21B6", PTR: "#5B21B6", SEN: "#6D28D9", SCA: "#6D28D9" };
const PALETA = ["#1F77B4", "#D62728", "#2CA02C", "#9467BD", "#FF7F0E", "#8C564B", "#E377C2", "#17BECF", "#BCBD22", "#393B79", "#AD494A", "#637939"];
const SIN_DATO = "#A7ADA9";
// Corte 9b, modo «Afectaciones» (colores aprobados por David el 17-nov; son los de --t-rojo, --t-naranja y --t-borde de la guía):
// tubería cerrada, rojo continuo de 5 px; sin agua, naranja punteado de 3 px; válvula cerrada, punto rojo con borde blanco; la red, de fondo en gris claro
const COLOR_CORTE = { cerrado: "#b3261e", afectado: "#c25e00", fondo: "#d5dde6" };
const CAPAS_CORTE = ["x-corte-valvula", "x-dano-punto", "x-corte-cerrado", "x-corte-afectado"];      // en este orden se busca lo que se toca
// Daños abiertos en «Afectaciones» (agregado de David, 17-nov): el activo del daño con un contorno («Daño reportado») y el punto del daño encima.
// PROPUESTA de color (por aprobar): el contorno en el azul oscuro de los títulos (--t-titulo), distinto del rojo de «tubería cerrada» y del naranja de «sin agua»
const COLOR_DANO_CONTORNO = "#0a2540";
const CAPAS_DANO = ["x-dano-activo-l", "x-dano-activo-p", "x-dano-punto"];
const NINGUNO = ["in", ["get", "codigo"], ["literal", [""]]] as unknown as maplibregl.FilterSpecification;
// Corte 9b, Fase 3: «Flujo del agua (modelo)». Azul del acueducto, grosor por la clase de caudal (1 a 5) y gris para «sin flujo»; flechas a lo largo de la línea
const CAPA_FLUJO = "flujo_modelo";
const COLOR_FLUJO = { agua: "#1F5FA8", sin_flujo: "#7b8b99" };
const GROSOR_FLUJO = [1.5, 2.5, 4, 6, 8];
const teselaFlujo = (hora: "mayor" | "menor", v: number) => `${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela_flujo&hora=${hora}&z={z}&x={x}&y={y}&v=${v}`;
/** La flecha de las líneas de flujo: un triángulo blanco con borde azul que apunta hacia donde va el agua (la línea ya viene orientada). */
function flecha(): ImageData {
  const n = 24, c = document.createElement("canvas"); c.width = n; c.height = n;
  const x = c.getContext("2d")!; x.beginPath(); x.moveTo(5, 4); x.lineTo(20, 12); x.lineTo(5, 20); x.closePath();
  x.fillStyle = "#FFFFFF"; x.fill(); x.lineWidth = 2.5; x.lineJoin = "round"; x.strokeStyle = COLOR_FLUJO.agua; x.stroke();
  return x.getImageData(0, 0, n, n);
}
const NODO_EXPR = ["match", ["get", "prefijo"], ...Object.entries(COLOR_NODO).flat(), "#1B1F1D"] as unknown as string;
const teselaCortes = (v: number) => `${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela_cortes&z={z}&x={x}&y={y}&v=${v}`;
const MIN_REFRESCO_CORTES = 3;      // minutos entre lecturas de las afectaciones vigentes
const SIN_FECHA = "#C9B79C";      // respuesta 2 de David al 6a: «sin fecha» con un gris propio (cálido), distinto del «sin dato» del material
const COLOR_CALIDAD: Record<string, string> = { dentro: "#2E7D32", fuera: "#C62828", sin_rango: "#90A4AE", sin_muestra: "#90A4AE" };
const NOMBRE_CALIDAD: Record<string, string> = { dentro: "Dentro del rango", fuera: "Fuera del rango", sin_rango: "Sin rango", sin_muestra: "Sin muestra reciente" };
// Corte 7a (respuesta 2 de David al 6b): un color por estado del contrato
const COLOR_CONTRATO: Record<string, string> = { activo: "#37474F", suspendido: "#F57C00", cortado: "#7B1FA2", retirado: "#FFFFFF", otro: "#F9A825", sin_dato: "#B0BEC5" };
const ESTADO_CONTRATO: Record<string, string> = { activo: "Activo", suspendido: "Suspendido", cortado: "Cortado", retirado: "Retirado", otro: "Otro", sin_dato: "Sin dato" };
const ATENUABLES = new Set(["reportes_comercial"]);      // §30.4: la capa de reportes de Comercial se puede apagar o atenuar
const EDADES: [number, string, string][] = [[0, "#2E7D32", "Menos de 10 años"], [10, "#9CCC65", "10 a 24 años"], [25, "#F9A825", "25 a 39 años"], [40, "#C62828", "40 años o más"]];
// Corte 5d: la línea 116, color por servicio; lleno si sigue registrado, hueco si ya se atendió; más grande si agrupa varios reportes
const COLOR_116: Record<string, string> = { acueducto: "#1565C0", alcantarillado: "#8D4E1E", otros: "#616161" };
const NOMBRE_SERV_116: Record<string, string> = { acueducto: "Acueducto", alcantarillado: "Alcantarillado", otros: "Otros (incidentes externos, pluvial)" };
const METODO_116: Record<string, string> = { contrato: "Por el contrato (punto del predio)" };
const COLOR_DANO: Record<string, string> = { reportado: "#D32F2F", en_atencion: "#EF6C00", atendido: "#2E7D32" };
const COLOR_ITV: Record<string, string> = { preventivo: "#0277BD", correctivo: "#EF6C00", reparacion: "#6A1B9A", reposicion: "#00838F", inversion: "#2E7D32" };
const NOMBRE_ITV: Record<string, string> = { preventivo: "Preventivo", correctivo: "Correctivo", reparacion: "Reparación", reposicion: "Reposición", inversion: "Inversión" };
const ESTADO_DANO: Record<string, string> = { reportado: "Reportado", en_atencion: "En atención", atendido: "Atendido" };
const ESTADO_CAPA: Record<string, string> = { por_conectar: "Por conectar", espera_dato: "Espera el dato" };
const VACIO: GeoJSON.FeatureCollection = { type: "FeatureCollection", features: [] };
// Corte 9a: colores de la presión frente a los umbrales de Parámetros (el nivel lo calcula el servidor) y de las capas de referencia
const COLOR_NIVEL: Record<NivelPresion, string> = { baja_roja: "#C62828", baja_naranja: "#EF6C00", normal: "#2E7D32", alta_naranja: "#F9A825", alta_roja: "#6A1B9A", sin_dato: "#90A4AE" };
const NOMBRE_NIVEL: Record<NivelPresion, string> = { baja_roja: "Baja (roja)", baja_naranja: "Baja (naranja)", normal: "Dentro del rango", alta_naranja: "Alta (naranja)", alta_roja: "Alta (roja)", sin_dato: "Sin dato" };
const COLOR_REF: Record<string, string> = { plan_valvulas: "#E65100", pluvial: "#00838F", pluvial_2043: "#AD1457" };
const CAPAS_PRESION = new Set(["presion_modelo", "campana_2014"]);
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 1 });
const fechaHora = (v: unknown) => (typeof v === "string" ? new Date(v).toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short", timeZone: "America/Bogota" }) : "—");
const texto = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : String(v).replace(/_/g, " "));
const sumarDias = (iso: string, d: number) => { const x = new Date(iso + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + d); return x.toISOString().slice(0, 10); };
const restarMeses = (iso: string, m: number) => { const x = new Date(iso + "T12:00:00Z"); x.setUTCMonth(x.getUTCMonth() - m); return x.toISOString().slice(0, 10); };

export function Geovisor({ onVolver, onReportarDano, onRegistrarIntervencion, vistaId }: {
  onVolver: () => void; onReportarDano?: (a: ActivoTarjeta) => void; onRegistrarIntervencion?: (a: ActivoTarjeta) => void;
  vistaId?: string | null;      // Corte 6b: el código de un enlace compartido
}) {
  const [cfg, setCfg] = useState<ConfigGeovisor | null>(null);
  const [vista, setVista] = useState<VistaAbierta | null | undefined>(vistaId ? undefined : null);
  const [avisoVista, setAvisoVista] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => {
    let vivo = true;
    setError(null);
    apiGeovisor.config().then((c) => {
      if (!vivo) return;
      setCfg(c);
      if (vistaId) apiGeovisor.abrirVista(vistaId).then((v) => { if (vivo) setVista(v); })
        .catch((e) => { if (vivo) { setVista(null); setAvisoVista(`No se pudo abrir la vista compartida: ${e instanceof Error ? e.message : "error"}. Se abrió la vista por omisión.`); } });
    })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene el geovisor técnico. Pídale a su supervisor que se lo active en Personal." : e instanceof Error ? e.message : "No se pudo abrir el geovisor."); });
    return () => { vivo = false; };
  }, [vez]);
  if (error) return <div className="geo geo-msg"><section className="tec-tarjeta" role="alert"><h1>Geovisor técnico</h1><p>{error}</p>
    <div className="dash-acciones"><button type="button" className="tec-boton-sec" onClick={onVolver}>← Volver</button><button type="button" className="tec-boton" onClick={() => setVez((v) => v + 1)}>Reintentar</button></div></section></div>;
  if (!cfg || vista === undefined) return <div className="geo geo-msg"><p className="tec-sub" role="status">Abriendo el geovisor…</p></div>;
  return <GeovisorMapa cfg={cfg} inicial={vista} avisoInicial={avisoVista} onVolver={onVolver} onReportarDano={onReportarDano} onRegistrarIntervencion={onRegistrarIntervencion} onRecargar={() => setVez((v) => v + 1)} />;
}

function GeovisorMapa({ cfg, inicial, avisoInicial, onVolver, onReportarDano, onRegistrarIntervencion, onRecargar }: {
  cfg: ConfigGeovisor; inicial?: VistaAbierta | null; avisoInicial?: string | null; onVolver: () => void; onReportarDano?: (a: ActivoTarjeta) => void; onRegistrarIntervencion?: (a: ActivoTarjeta) => void; onRecargar: () => void;
}) {
  const omision = useMemo(() => new Set(cfg.capas.filter((c) => c.encendida && c.fuente !== "preparada").map((c) => c.codigo)), [cfg]);
  const [on, setOn] = useState<Set<string>>(inicial ? new Set(inicial.capas) : omision);
  const [colores, setColores] = useState<Colores>(inicial?.colores ?? "tipo");
  const [periodo, setPeriodo] = useState<Periodo>(inicial ? { modo: inicial.periodo.modo, desde: inicial.periodo.desde, hasta: inicial.periodo.hasta } : { modo: "hoy", desde: cfg.hoy, hasta: cfg.hoy });
  const [atenuadas, setAtenuadas] = useState<Set<string>>(new Set(inicial?.atenuadas ?? []));
  const [compartir, setCompartir] = useState(false);
  const [avisoAbierto, setAvisoAbierto] = useState<string | null>(avisoInicial ?? (inicial ? [
    "Vista compartida.",
    inicial.omitidas.length ? `No se muestran ${inicial.omitidas.join(", ")}: no tiene permiso para esas capas.` : "",
    inicial.fechas_cambiadas ? "Se muestran las actividades de hoy (su geovisor es de solo lectura)." : ""].filter(Boolean).join(" ") : null));
  const [panel, setPanel] = useState<"" | "capas" | "omision">("");
  const [tarjeta, setTarjeta] = useState<Tarjeta | null>(null);
  const [cortes, setCortes] = useState<CortesVigentes | null>(null);      // Corte 9b: las afectaciones vigentes (franja, tarjetas y leyenda)
  const [corteSel, setCorteSel] = useState<CorteSel | null>(null);
  const [danosAb, setDanosAb] = useState<DanoAbierto[] | null>(null);      // daños abiertos (reportados o en atención) para el modo «Afectaciones»
  const [flujo, setFlujo] = useState<FlujoInfo | null>(null);      // Fase 3: rótulo, horas y leyenda de «Flujo del agua (modelo)»
  const [horaFlujo, setHoraFlujo] = useState<"mayor" | "menor">("mayor");
  const flujoPuesto = useRef("");
  const coloresRef = useRef(colores);
  coloresRef.current = colores;
  const [ficha, setFicha] = useState<string[]>([]);
  const [zoom, setZoom] = useState(14);
  const [datos, setDatos] = useState<Record<string, CapaDatos | { error: string } | "cargando">>({});
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const token = useRef<string | null>(null);
  const [listo, setListo] = useState(false);
  const capasRef = useRef(cfg.capas);
  const inicialRef = useRef(inicial);
  const onRef = useRef(on);
  onRef.current = on;
  const teselas = cfg.capas.filter((c) => c.fuente === "tesela");
  const referencias = cfg.capas.filter((c) => c.fuente === "referencia");
  const geojson = cfg.capas.filter((c) => c.fuente === "geojson");
  const hayPorFecha = geojson.some((c) => c.por_fecha && on.has(c.codigo));

  // ---------- el mapa (una vez) ----------
  useEffect(() => {
    let vivo = true;
    let m: maplibregl.Map | null = null;
    const sub = supabase.auth.onAuthStateChange?.((_e: unknown, s: { access_token?: string } | null) => { token.current = s?.access_token ?? token.current; });
    void supabase.auth.getSession().then(({ data }) => {
      if (!vivo || !cont.current) return;
      token.current = data.session?.access_token ?? null;
      const capasTesela = capasRef.current.filter((c) => c.fuente === "tesela");
      const capasGeo = capasRef.current.filter((c) => c.fuente === "geojson");
      const capas: maplibregl.LayerSpecification[] = [{ id: "base", type: "raster", source: "base" }];
      for (const c of capasTesela) {
        const f = ["in", ["get", "prefijo"], ["literal", c.prefijos]];
        const vis = onRef.current.has(c.codigo) ? "visible" : "none";
        // áreas (sectores hidráulicos, Corte 9a): el relleno suave solo en los subsectores (o en lo que no diga su clase), para que no se sume con el del sector;
        // el borde del sector, grueso, y el del subsector, fino
        capas.push({ id: `t-${c.codigo}-a`, type: "fill", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "area"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis }, paint: { "fill-color": COLOR_SISTEMA.tecnologia, "fill-opacity": ["case", ["==", ["get", "clase"], "sector"], 0, 0.07] } });
        capas.push({ id: `t-${c.codigo}-ab`, type: "line", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "area"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis }, paint: { "line-color": COLOR_SISTEMA.tecnologia, "line-width": ["case", ["==", ["get", "clase"], "subsector"], 1, 2.6], "line-opacity": 0.75 } });
        capas.push({ id: `t-${c.codigo}-l`, type: "line", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "tramo"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis, "line-cap": "round" },
                     paint: { "line-color": COLOR_SISTEMA.acueducto, "line-width": ["interpolate", ["linear"], ["zoom"], 13, 1.2, 16, 3, 19, 6],
                              "line-opacity": ["case", ["get", "punteado"], 0.5, 0.95] } });
        capas.push({ id: `t-${c.codigo}-p`, type: "circle", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "nodo"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis },
                     paint: { "circle-radius": ["interpolate", ["linear"], ["zoom"], 13, ["match", ["get", "prefijo"], "ACC", 1.5, 3], 19, ["match", ["get", "prefijo"], "ACC", 5, 8]],
                              "circle-color": ["match", ["get", "prefijo"], ...Object.entries(COLOR_NODO).flat(), "#1B1F1D"] as unknown as string,
                              "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 1.2 } });
      }
      const fuentesGeo: Record<string, maplibregl.SourceSpecification> = {};
      for (const c of capasGeo) {
        fuentesGeo[`g-${c.codigo}`] = { type: "geojson", data: VACIO };
        const vis = onRef.current.has(c.codigo) ? "visible" : "none";
        const color = c.codigo === "danos" ? ["match", ["get", "estado"], ...Object.entries(COLOR_DANO).flat(), "#D32F2F"]
          : c.codigo === "intervenciones" ? ["match", ["get", "tipo_codigo"], ...Object.entries(COLOR_ITV).flat(), "#455A64"]
          : c.codigo === "muestreo" ? ["case", ["==", ["get", "exactitud"], "verificada"], ["match", ["get", "calidad"], ...Object.entries(COLOR_CALIDAD).flat(), "#90A4AE"], "rgba(255,255,255,0.9)"]
          : c.codigo === "reportes_comercial" ? ["case", ["get", "con_contrato"], "#1565C0", "#C62828"]
          : c.codigo === "pqr_116" ? ["case", ["==", ["get", "estado"], "registrado"], ["match", ["get", "grupo_servicio"], ...Object.entries(COLOR_116).flat(), "#616161"], "#FFFFFF"] : "#7B1FA2";
        const borde = c.codigo === "muestreo" ? ["match", ["get", "calidad"], ...Object.entries(COLOR_CALIDAD).flat(), "#90A4AE"]
          : c.codigo === "pqr_116" ? ["match", ["get", "grupo_servicio"], ...Object.entries(COLOR_116).flat(), "#616161"] : "#FFFFFF";
        const radio = c.codigo === "muestreo" ? 7 : c.codigo === "pqr_116" ? ["min", 13, ["+", 5.5, ["*", 1.5, ["get", "n"]]]] : 6.5;
        capas.push({ id: `g-${c.codigo}`, type: "circle", source: `g-${c.codigo}`, layout: { visibility: vis },
                     paint: { "circle-radius": radio as unknown as number, "circle-color": color as unknown as string,
                              "circle-stroke-color": borde as unknown as string, "circle-stroke-width": c.codigo === "muestreo" || c.codigo === "pqr_116" ? 2.5 : 2 } });
      }
      // Corte 9a: capas de referencia, cada una con su fuente (solo pide teselas cuando está encendida)
      const capasReferencia = capasRef.current.filter((c) => c.fuente === "referencia");
      const fuentesRef: Record<string, maplibregl.SourceSpecification> = {};
      for (const c of capasReferencia) {
        fuentesRef[`r-${c.codigo}`] = { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela_ref&capa=${c.codigo}&z={z}&x={x}&y={y}&v=${cfg.version}`], minzoom: cfg.zoom.min, maxzoom: 18 };
        const vis = onRef.current.has(c.codigo) ? "visible" : "none";
        const presion = CAPAS_PRESION.has(c.codigo);
        const colorNivel = ["match", ["get", "nivel"], ...Object.entries(COLOR_NIVEL).flat(), COLOR_NIVEL.sin_dato] as unknown as string;
        const color = COLOR_REF[c.codigo] ?? "#455A64";
        capas.push({ id: `r-${c.codigo}-l`, type: "line", source: `r-${c.codigo}`, "source-layer": "ref", filter: ["==", ["get", "forma"], "tramo"], layout: { visibility: vis, "line-cap": "round" },
                     paint: { "line-color": c.codigo === "pluvial_2043" ? ["match", ["get", "estado"], "Existente", "#78909C", color] as unknown as string : color,
                              "line-width": ["interpolate", ["linear"], ["zoom"], 13, 1.4, 16, 3, 19, 6], "line-opacity": 0.9, ...(c.codigo === "pluvial_2043" ? { "line-dasharray": [2, 1.5] } : {}) } });
        capas.push({ id: `r-${c.codigo}-p`, type: "circle", source: `r-${c.codigo}`, "source-layer": "ref", filter: ["==", ["get", "forma"], "nodo"], layout: { visibility: vis },
                     paint: c.codigo === "campana_2014" ? { "circle-radius": 9, "circle-color": colorNivel, "circle-stroke-color": "#1B1F1D", "circle-stroke-width": 2.5 }
                       : presion ? { "circle-radius": ["interpolate", ["linear"], ["zoom"], 13, 2.5, 16, 5, 19, 8], "circle-color": colorNivel, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 0.8, "circle-opacity": 0.9 }
                       : c.codigo === "plan_valvulas" ? { "circle-radius": ["interpolate", ["linear"], ["zoom"], 15, 4, 19, 8], "circle-color": "#FFFFFF", "circle-stroke-color": color, "circle-stroke-width": 2.5 }
                       : { "circle-radius": ["interpolate", ["linear"], ["zoom"], 15, 3, 19, 7], "circle-color": color, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 1.2 } });
      }
      const conContratos = capasRef.current.some((c) => c.fuente === "contratos");
      if (conContratos) {
        capas.push({ id: "c-contratos", type: "circle", source: "contratos", "source-layer": "contratos", layout: { visibility: onRef.current.has("contratos") ? "visible" : "none" },
                     paint: { "circle-radius": ["interpolate", ["linear"], ["zoom"], 16, 3.5, 19, 7], "circle-color": ["match", ["get", "estado"], ...Object.entries(COLOR_CONTRATO).flat(), "#B0BEC5"] as unknown as string,
                              "circle-stroke-color": ["match", ["get", "estado"], "retirado", "#B71C1C", "#FFFFFF"] as unknown as string, "circle-stroke-width": 1.5 } });
        const i = capas.findIndex((x) => x.id.startsWith("g-"));
        if (i > 0) capas.splice(i, 0, capas.pop()!);      // debajo de las actividades y del muestreo
      }
      // Corte 9b, Fase 3: el flujo del modelo (solo supervisores; se enciende desde la lista de capas)
      capas.push({ id: "f-flujo-l", type: "line", source: "flujo", "source-layer": "flujo_modelo", layout: { visibility: "none", "line-cap": "round" },
                   paint: { "line-color": ["case", ["get", "sin_flujo"], COLOR_FLUJO.sin_flujo, COLOR_FLUJO.agua] as unknown as string,
                            "line-width": ["case", ["get", "sin_flujo"], 1.5, ["match", ["get", "clase"], 1, GROSOR_FLUJO[0], 2, GROSOR_FLUJO[1], 3, GROSOR_FLUJO[2], 4, GROSOR_FLUJO[3], GROSOR_FLUJO[4]]] as unknown as number } });
      capas.push({ id: "f-flujo-s", type: "symbol", source: "flujo", "source-layer": "flujo_modelo", filter: ["!", ["get", "sin_flujo"]] as unknown as maplibregl.FilterSpecification,
                   layout: { visibility: "none", "symbol-placement": "line", "symbol-spacing": 90, "icon-image": "flecha", "icon-allow-overlap": true, "icon-ignore-placement": true,
                             "icon-size": ["match", ["get", "clase"], 1, 0.45, 2, 0.55, 3, 0.7, 4, 0.85, 1] as unknown as number } });
      // Corte 9b: las afectaciones (solo se ven en su modo; la fuente no pide teselas mientras sus capas están apagadas)
      capas.push({ id: "x-corte-afectado", type: "line", source: "cortes", "source-layer": "corte_tramos", filter: ["==", ["get", "papel"], "afectado"], layout: { visibility: "none", "line-cap": "butt" },
                   paint: { "line-color": COLOR_CORTE.afectado, "line-width": 3, "line-dasharray": [2, 1.5] } });
      capas.push({ id: "x-corte-cerrado", type: "line", source: "cortes", "source-layer": "corte_tramos", filter: ["==", ["get", "papel"], "cerrado"], layout: { visibility: "none", "line-cap": "round" },
                   paint: { "line-color": COLOR_CORTE.cerrado, "line-width": 5 } });
      capas.push({ id: "x-corte-valvula", type: "circle", source: "cortes", "source-layer": "corte_valvulas", layout: { visibility: "none" },
                   paint: { "circle-radius": 5, "circle-color": COLOR_CORTE.cerrado, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2 } });
      // … y los daños abiertos: el contorno del activo del daño (sale de la tesela de la red) y el punto del daño encima de todo
      capas.push({ id: "x-dano-activo-l", type: "line", source: "red", "source-layer": "activos", filter: NINGUNO, layout: { visibility: "none", "line-cap": "round" },
                   paint: { "line-color": COLOR_DANO_CONTORNO, "line-width": 2, "line-gap-width": 7 } });
      capas.push({ id: "x-dano-activo-p", type: "circle", source: "red", "source-layer": "activos", filter: NINGUNO, layout: { visibility: "none" },
                   paint: { "circle-radius": 11, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": COLOR_DANO_CONTORNO, "circle-stroke-width": 2.5 } });
      capas.push({ id: "x-dano-punto", type: "circle", source: "x-danos", layout: { visibility: "none" },
                   paint: { "circle-radius": 6.5, "circle-color": ["match", ["get", "estado"], ...Object.entries(COLOR_DANO).flat(), "#D32F2F"] as unknown as string, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2 } });
      capas.push({ id: "sel", type: "circle", source: "sel", paint: { "circle-radius": 13, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": "#D6336C", "circle-stroke-width": 3.5 } });
      m = new maplibregl.Map({
        container: cont.current, center: inicialRef.current ? [inicialRef.current.lon, inicialRef.current.lat] : CENTRO_VALLEDUPAR, zoom: inicialRef.current?.zoom ?? 14, maxZoom: 20, minZoom: 11, attributionControl: { compact: true },
        dragRotate: false, pitchWithRotate: false, touchPitch: false,
        // «accion=geovisor_tesela» cubre también geovisor_tesela_contratos y geovisor_tesela_ref
        transformRequest: (url) => (url.includes("accion=geovisor_tesela") && token.current ? { url, headers: { Authorization: `Bearer ${token.current}` } } : { url }),
        style: {
          version: 8,
          sources: {
            base: FUENTE_BASE_CALLES,
            red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela&z={z}&x={x}&y={y}&v=${cfg.version}&p=${cfg.completo ? "c" : "o"}`], minzoom: cfg.zoom.min, maxzoom: 18 },
            ...(conContratos ? { contratos: { type: "vector" as const, tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela_contratos&z={z}&x={x}&y={y}&v=${encodeURIComponent(cfg.hoy)}`],
                                              minzoom: cfg.zoom.contratos ?? 16, maxzoom: 18 } } : {}),
            ...fuentesGeo,
            ...fuentesRef,
            cortes: { type: "vector", tiles: [teselaCortes(0)], minzoom: 10, maxzoom: 18 },
            "x-danos": { type: "geojson", data: VACIO },
            flujo: { type: "vector", tiles: [teselaFlujo("mayor", 0)], minzoom: cfg.zoom.min, maxzoom: 18 },
            sel: { type: "geojson", data: VACIO },
          },
          layers: capas,
        },
      });
      mapa.current = m;
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome (no se usa en la app)
      m.on("load", () => { if (m && !m.hasImage("flecha")) m.addImage("flecha", flecha()); });
      m.on("styleimagemissing", (e) => { if (m && e.id === "flecha" && !m.hasImage("flecha")) m.addImage("flecha", flecha()); });
      m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
      m.on("zoomend", () => setZoom(m!.getZoom()));
      m.on("click", (ev) => {
        if (!m) return;
        const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[ev.point.x - 14, ev.point.y - 14], [ev.point.x + 14, ev.point.y + 14]];
        if (coloresRef.current === "afectaciones") {      // Corte 9b: en «Afectaciones» se toca una válvula cerrada o una zona sin agua
          const fc = m.queryRenderedFeatures(caja, { layers: CAPAS_CORTE.filter((id) => m!.getLayer(id)) });
          const c = CAPAS_CORTE.map((id) => fc.find((x) => x.layer.id === id)).find(Boolean);
          if (c) {
            setTarjeta(null);
            setCorteSel(c.layer.id === "x-corte-valvula" ? { tipo: "valvula", codigo: String(c.properties?.codigo) } : c.layer.id === "x-dano-punto" ? { tipo: "dano", codigo: String(c.properties?.codigo) }
              : { tipo: "zona", zona: Number(c.properties?.zona) });
            return;
          }
          setCorteSel(null);      // nada de afectaciones en ese punto: sigue a lo de siempre (p. ej. la válvula que el supervisor va a cerrar)
        }
        // primero lo puntual (actividades, campaña y demás referencias, contratos y nodos), luego los tramos y, al final, las áreas (sectores)
        const orden = [...capasGeo.map((c) => `g-${c.codigo}`), ...capasReferencia.map((c) => `r-${c.codigo}-p`), "c-contratos", ...capasTesela.map((c) => `t-${c.codigo}-p`),
                       "f-flujo-l", ...capasTesela.map((c) => `t-${c.codigo}-l`), ...capasReferencia.map((c) => `r-${c.codigo}-l`), ...capasTesela.map((c) => `t-${c.codigo}-a`)]
          .filter((id) => m!.getLayer(id) && m!.getLayoutProperty(id, "visibility") !== "none");
        const feats = m.queryRenderedFeatures(caja, { layers: orden });
        // en las áreas, el subsector antes que el sector que lo contiene
        const f = orden.map((id) => feats.filter((x) => x.layer.id === id).sort((a, b) => Number(b.properties?.clase === "subsector") - Number(a.properties?.clase === "subsector"))[0]).find(Boolean);
        if (!f) { setTarjeta(null); return; }
        const id = f.layer.id;
        const capa = id.startsWith("g-") ? id.slice(2) : id.startsWith("r-") ? `ref:${id.slice(2, -2)}` : id === "c-contratos" ? "contrato" : id === "f-flujo-l" ? "flujo" : "activo";
        const [lon, lat] = f.geometry.type === "Point" ? (f.geometry.coordinates as [number, number]) : [ev.lngLat.lng, ev.lngLat.lat];
        setTarjeta({ capa, props: f.properties as Record<string, unknown>, lat, lon });
      });
      setListo(true);
    });
    return () => { vivo = false; sub?.data?.subscription?.unsubscribe?.(); m?.remove(); mapa.current = null; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- encender y apagar ----------
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    const aplicar = () => {
      for (const c of teselas) for (const s of ["-a", "-ab", "-l", "-p"]) if (m.getLayer(`t-${c.codigo}${s}`)) m.setLayoutProperty(`t-${c.codigo}${s}`, "visibility", on.has(c.codigo) ? "visible" : "none");
      for (const c of geojson) if (m.getLayer(`g-${c.codigo}`)) m.setLayoutProperty(`g-${c.codigo}`, "visibility", on.has(c.codigo) ? "visible" : "none");
      if (m.getLayer("c-contratos")) m.setLayoutProperty("c-contratos", "visibility", on.has("contratos") ? "visible" : "none");
      for (const c of referencias) for (const s of ["-l", "-p"]) if (m.getLayer(`r-${c.codigo}${s}`)) m.setLayoutProperty(`r-${c.codigo}${s}`, "visibility", on.has(c.codigo) ? "visible" : "none");
      for (const id of ["f-flujo-l", "f-flujo-s"]) if (m.getLayer(id)) m.setLayoutProperty(id, "visibility", on.has(CAPA_FLUJO) ? "visible" : "none");
      for (const c of ATENUABLES) if (m.getLayer(`g-${c}`)) { const o = atenuadas.has(c) ? 0.3 : 1; m.setPaintProperty(`g-${c}`, "circle-opacity", o); m.setPaintProperty(`g-${c}`, "circle-stroke-opacity", o); }
    };
    if (m.getLayer("sel")) aplicar(); else m.once("styledata", aplicar);
  }, [on, atenuadas, listo]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- colores de los tramos ----------
  const materiales = useMemo(() => cfg.materiales.map((x, i) => ({ ...x, color: PALETA[i % PALETA.length] })), [cfg]);
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    const expr = colores === "material" ? ["match", ["get", "material"], ...materiales.flatMap((x) => [x.codigo, x.color]), SIN_DATO]
      : colores === "edad" ? ["case", ["!", ["has", "edad"]], SIN_FECHA, ["step", ["get", "edad"], EDADES[0][1], EDADES[1][0], EDADES[1][1], EDADES[2][0], EDADES[2][1], EDADES[3][0], EDADES[3][1]]]
      : ["match", ["get", "sistema"], "alcantarillado", COLOR_SISTEMA.alcantarillado, "tecnologia", COLOR_SISTEMA.tecnologia, COLOR_SISTEMA.acueducto];
    const afect = colores === "afectaciones";
    const aplicar = () => {
      for (const c of teselas) {
        if (m.getLayer(`t-${c.codigo}-l`)) m.setPaintProperty(`t-${c.codigo}-l`, "line-color", afect ? COLOR_CORTE.fondo : expr as unknown as string);
        if (m.getLayer(`t-${c.codigo}-p`)) { m.setPaintProperty(`t-${c.codigo}-p`, "circle-color", afect ? COLOR_CORTE.fondo : NODO_EXPR); m.setPaintProperty(`t-${c.codigo}-p`, "circle-stroke-width", afect ? 0 : 1.2); }
      }
      for (const id of [...CAPAS_CORTE, ...CAPAS_DANO]) if (m.getLayer(id)) m.setLayoutProperty(id, "visibility", afect ? "visible" : "none");
    };
    if (m.getLayer("sel")) aplicar(); else m.once("styledata", aplicar);
    if (!afect) setCorteSel(null); else setTarjeta(null);
  }, [colores, listo]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- Corte 9b: las afectaciones vigentes (al abrir y cada pocos minutos; la tesela cambia con el número de la foto) ----------
  const leerCortes = useMemo(() => () => { apiCierre.vigentes().then(setCortes).catch(() => { /* sin la lista, el geovisor sigue: no hay franja */ }); }, []);
  useEffect(() => { leerCortes(); const r = window.setInterval(leerCortes, MIN_REFRESCO_CORTES * 60000); return () => window.clearInterval(r); }, [leerCortes]);
  const fotoCortes = cortes?.foto?.id ?? 0;
  const fotoPuesta = useRef(0);
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    if (fotoPuesta.current === fotoCortes) return;      // solo si cambió la foto: reponer la fuente corta las teselas que vienen en camino
    const poner = () => { fotoPuesta.current = fotoCortes; (m.getSource("cortes") as maplibregl.VectorTileSource | undefined)?.setTiles([teselaCortes(fotoCortes)]); };
    if (m.getLayer("sel")) poner(); else m.once("styledata", poner);
  }, [fotoCortes, listo]);
  // Daños abiertos para «Afectaciones». Supervisores y administrador: TODOS los abiertos o en atención, sin límite de fecha (ruta afectaciones_danos, del
  // ajuste final del 9b). El geovisor de solo lectura: los de hoy, de la capa de daños por fecha (la base no le entrega otros días).
  const hayCapaDanos = cfg.capas.some((c) => c.codigo === "danos");
  useEffect(() => {
    if (colores !== "afectaciones" || !hayCapaDanos) return;
    let vivo = true;
    (cfg.completo ? apiGeovisor.danosAbiertos() : apiGeovisor.capa("danos", cfg.hoy, cfg.hoy))
      .then((r) => { if (vivo) setDanosAb(r.features.filter((f) => f.geometry.type === "Point" && ["reportado", "en_atencion"].includes(String(f.properties?.estado)))
        .map((f) => ({ ...(f.properties as Omit<DanoAbierto, "lat" | "lon">), lon: (f.geometry as GeoJSON.Point).coordinates[0], lat: (f.geometry as GeoJSON.Point).coordinates[1] }))); })
      .catch(() => { if (vivo) setDanosAb([]); });
    return () => { vivo = false; };
  }, [colores, fotoCortes, hayCapaDanos]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    const poner = () => {
      const ds = danosAb ?? [], cods = ds.map((d) => d.activo).filter((c): c is string => !!c);
      (m.getSource("x-danos") as maplibregl.GeoJSONSource | undefined)?.setData({ type: "FeatureCollection", features: ds.map((d) => ({ type: "Feature" as const, properties: { codigo: d.codigo, estado: d.estado }, geometry: { type: "Point" as const, coordinates: [d.lon, d.lat] } })) });
      const f = (forma: string) => (cods.length ? ["all", ["==", ["get", "forma"], forma], ["in", ["get", "codigo"], ["literal", cods]]] : NINGUNO) as unknown as maplibregl.FilterSpecification;
      if (m.getLayer("x-dano-activo-l")) m.setFilter("x-dano-activo-l", f("tramo"));
      if (m.getLayer("x-dano-activo-p")) m.setFilter("x-dano-activo-p", f("nodo"));
    };
    if (m.getLayer("sel")) poner(); else m.once("styledata", poner);
  }, [danosAb, listo]);

  // ---------- Corte 9b, Fase 3: «Flujo del agua (modelo)»: la información al encender la capa; la tesela cambia con la hora y con la versión de la carga ----------
  const flujoOn = on.has(CAPA_FLUJO);
  useEffect(() => { if (flujoOn && !flujo) apiFlujo.info().then(setFlujo).catch(() => { /* sin la información no hay leyenda ni selector; la capa sigue */ }); }, [flujoOn, flujo]);
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo || !flujoOn) return;
    const clave = `${horaFlujo}|${flujo?.version ?? 0}`;
    if (flujoPuesto.current === clave) return;
    const poner = () => { flujoPuesto.current = clave; (m.getSource("flujo") as maplibregl.VectorTileSource | undefined)?.setTiles([teselaFlujo(horaFlujo, flujo?.version ?? 0)]); };
    if (m.getLayer("sel")) poner(); else m.once("styledata", poner);
  }, [flujoOn, horaFlujo, flujo, listo]);

  const zonas = cortes?.hay ? cortes.zonas : [];
  const irACaja = (c: [number, number, number, number]) => mapa.current?.fitBounds([[c[0], c[1]], [c[2], c[3]]], { padding: 70, maxZoom: 17, duration: 0 });
  const verAfectaciones = (z?: ZonaCorte) => {
    setColores("afectaciones"); setPanel("");
    const cs = z ? [z.caja] : zonas.map((x) => x.caja);
    if (cs.length) irACaja([Math.min(...cs.map((c) => c[0])), Math.min(...cs.map((c) => c[1])), Math.max(...cs.map((c) => c[2])), Math.max(...cs.map((c) => c[3]))]);
    window.setTimeout(() => setCorteSel(z ? { tipo: "zona", zona: z.zona } : null), 0);      // después del cambio de modo (que cierra lo elegido)
  };

  // ---------- capas en GeoJSON: se piden al encenderlas y al cambiar el período ----------
  const clavePeriodo = `${periodo.desde}|${periodo.hasta}`;
  useEffect(() => {
    let vivo = true;
    for (const c of geojson) {
      if (!on.has(c.codigo)) continue;
      const actual = datos[c.codigo];
      if (actual && actual !== "cargando" && !("error" in actual) && (!c.por_fecha || (actual.desde === periodo.desde && actual.hasta === periodo.hasta))) continue;
      setDatos((d) => ({ ...d, [c.codigo]: "cargando" }));
      apiGeovisor.capa(c.codigo, c.por_fecha ? periodo.desde : null, c.por_fecha ? periodo.hasta : null)
        .then((r) => { if (vivo) setDatos((d) => ({ ...d, [c.codigo]: r })); })
        .catch((e) => { if (vivo) setDatos((d) => ({ ...d, [c.codigo]: { error: e instanceof Error ? e.message : "No se pudo cargar." } })); });
    }
    return () => { vivo = false; };
  }, [on, clavePeriodo]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    for (const c of geojson) {
      const d = datos[c.codigo];
      (m.getSource(`g-${c.codigo}`) as maplibregl.GeoJSONSource | undefined)?.setData(d && d !== "cargando" && !("error" in d) ? d : VACIO);
    }
  }, [datos, listo]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- lo elegido ----------
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    (m.getSource("sel") as maplibregl.GeoJSONSource | undefined)?.setData(tarjeta
      ? { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [tarjeta.lon, tarjeta.lat] } }] } : VACIO);
  }, [tarjeta, listo]);
  useEffect(() => { if (!ficha.length) mapa.current?.resize(); }, [ficha.length]);

  const conmutar = (c: string) => setOn((s) => { const n = new Set(s); if (n.has(c)) n.delete(c); else n.add(c); return n; });
  const cambiado = on.size !== omision.size || [...on].some((c) => !omision.has(c));
  const avisos = geojson.filter((c) => on.has(c.codigo)).map((c) => ({ c, d: datos[c.codigo] }))
    .filter((x) => x.d && (x.d === "cargando" || "error" in x.d || x.d.recortada));

  return (
    <div className="geo" data-perfil={cfg.perfil}>
      <header className="geo-barra">
        <button type="button" className="geo-volver" onClick={onVolver} aria-label="Volver a Técnica">←</button>
        <div className="geo-titulo"><h1>Geovisor técnico</h1><span>{cfg.completo ? (cfg.perfil === "admin" ? "Administrador" : "Supervisor") : "Solo lectura"}</span></div>
        {cfg.compartir ? <button type="button" className="geo-boton geo-boton-sec" onClick={() => setCompartir(true)}>Compartir</button> : null}
        <button type="button" className="geo-boton" aria-expanded={panel === "capas"} onClick={() => setPanel((p) => (p === "capas" ? "" : "capas"))}>Capas</button>
      </header>

      <div className="geo-herr">
        <div className="geo-seg" role="group" aria-label="Colores de la red">
          {(["tipo", "material", "edad", "afectaciones"] as Colores[]).map((k) => <button key={k} type="button" aria-pressed={colores === k} onClick={() => setColores(k)}>{k === "tipo" ? "Tipo" : k === "material" ? "Material" : k === "edad" ? "Edad" : "Afectaciones"}</button>)}
        </div>
        {hayPorFecha ? <SelectorPeriodo cfg={cfg} periodo={periodo} onCambiar={setPeriodo} /> : null}
        {flujoOn ? (
          <div className="geo-seg" role="group" aria-label="Hora del flujo del modelo" data-testid="hora-flujo">
            {(["mayor", "menor"] as const).map((h) => <button key={h} type="button" aria-pressed={horaFlujo === h} onClick={() => setHoraFlujo(h)}>
              {flujo?.horas.find((x) => x.cual === h)?.texto ?? (h === "mayor" ? "Hora de mayor consumo (17:00)" : "Hora de menor consumo (23:00)")}</button>)}
          </div>) : null}
      </div>

      {zonas.length ? (
        <div className="geo-franja" role="status" data-testid="franja-cortes">
          <strong>{zonas.length === 1 ? "1 zona sin agua en este momento" : `${zonas.length} zonas sin agua en este momento`}</strong>
          <div className="geo-franja-zonas">
            {zonas.slice(0, 6).map((z, i) => <button key={z.zona} type="button" className="geo-franja-zona" onClick={() => verAfectaciones(z)}>Zona {i + 1} · {nContratos(z.contratos)}</button>)}
            {zonas.length > 6 ? <span className="geo-franja-mas">y {zonas.length - 6} más</span> : null}
          </div>
          <button type="button" className="geo-franja-ver" onClick={() => verAfectaciones()}>Ver afectaciones</button>
        </div>) : null}

      <div className="geo-cuerpo">
        <div ref={cont} className="geo-mapa" role="application" aria-label="Mapa del geovisor técnico" data-zoom={zoom.toFixed(1)} />
        {zoom < cfg.zoom.min ? <div className="geo-aviso" role="status">Acerque el mapa para ver la red</div>
          : zoom < cfg.zoom.red_completa ? <div className="geo-aviso geo-aviso-suave" role="status">Red principal · acerque para ver todos los tramos</div> : null}
        {avisos.length ? (
          <div className="geo-avisos" role="status">
            {avisos.map(({ c, d }) => <p key={c.codigo}>{d === "cargando" ? `Cargando ${c.nombre.toLowerCase()}…` : d && "error" in d ? `${c.nombre}: ${d.error}`
              : `${c.nombre}: se muestran los ${cfg.max_elementos} más recientes. Acorte el rango de fechas.`}</p>)}
          </div>) : null}
        {flujoOn ? <LeyendaFlujo info={flujo} derecha={colores !== "tipo"} /> : null}
        {colores === "afectaciones" ? <LeyendaCortes cortes={cortes} danos={danosAb} hoy={!cfg.completo} onRecalcular={cfg.completo && cortes?.hay ? () => { setTarjeta(null); setCorteSel({ tipo: "recalcular" }); } : undefined} /> : colores !== "tipo" ? <Leyenda colores={colores} materiales={materiales} edadRef={cfg.edad_ref === true} /> : null}
        {on.has("pqr_116") ? <Leyenda116 derecha={colores !== "tipo" || [...CAPAS_PRESION].some((c) => on.has(c))}
          sinUbicar={(() => { const d = datos.pqr_116; return d && d !== "cargando" && !("error" in d) ? (d as { sin_ubicar?: number }).sin_ubicar ?? 0 : 0; })()} /> : null}
        {[...CAPAS_PRESION].some((c) => on.has(c)) ? <LeyendaPresion modelo={on.has("presion_modelo")} medida={on.has("campana_2014")} arriba={colores !== "tipo"} /> : null}
        {on.has("contratos") && zoom < (cfg.zoom.contratos ?? 16) && zoom >= cfg.zoom.min ? <div className="geo-aviso geo-aviso-suave geo-aviso-abajo" role="status">Acerque más para ver los contratos</div> : null}
        {avisoAbierto ? <div className="geo-vista-aviso" role="status"><span>{avisoAbierto}</span><button type="button" className="geo-cerrar" onClick={() => setAvisoAbierto(null)} aria-label="Cerrar el aviso">✕</button></div> : null}
        {compartir ? <Compartir cfg={cfg} mapa={mapa.current} on={on} colores={colores === "afectaciones" ? "tipo" : colores} periodo={periodo} atenuadas={atenuadas} onCerrar={() => setCompartir(false)} /> : null}
        {tarjeta && tarjeta.capa === "flujo" ? <TarjetaFlujo codigo={String(tarjeta.props.codigo)} onCerrar={() => setTarjeta(null)} />
          : tarjeta ? <TarjetaElemento t={tarjeta} cfg={cfg} onCerrar={() => setTarjeta(null)} onVerFicha={(c) => setFicha([c])}
          onReportarDano={onReportarDano} onRegistrarIntervencion={onRegistrarIntervencion} cortes={cortes}
          onCierre={(codigo) => { leerCortes(); setTarjeta(null); setColores("afectaciones"); window.setTimeout(() => setCorteSel({ tipo: "valvula", codigo }), 600); }} /> : null}
        {corteSel && (cortes?.hay || corteSel.tipo === "dano") ? <TarjetaCorte sel={corteSel} cortes={cortes ?? { hay: false, zonas: [], valvulas: [] }} zonas={zonas} danos={danosAb ?? []}
          puede={cfg.completo || cfg.formularios.danos_fallas || cfg.formularios.mantenimiento}
          onElegir={setCorteSel} onCerrar={() => setCorteSel(null)} onCambio={leerCortes} /> : null}

        {panel === "capas" ? (
          <aside className="geo-panel" aria-label="Capas del geovisor">
            <div className="geo-panel-cab"><h2>Capas</h2><button type="button" className="geo-cerrar" onClick={() => setPanel("")} aria-label="Cerrar las capas">✕</button></div>
            <button type="button" className="tec-boton-sec geo-omision" disabled={!cambiado} onClick={() => setOn(new Set(omision))}>Volver a la vista por omisión</button>
            {!cfg.completo ? <p className="tec-ayuda">Geovisor en solo lectura: la red y las actividades del día.</p> : null}
            {GRUPOS.map((g) => {
              const cs = cfg.capas.filter((c) => c.grupo === g.c);
              if (!cs.length) return null;
              return (
                <section key={g.c} className="geo-grupo" aria-labelledby={`geo-g-${g.c}`}>
                  <h3 id={`geo-g-${g.c}`}>{g.n}</h3>
                  {cs.map((c) => <FilaCapa key={c.codigo} c={c} encendida={on.has(c.codigo)} onConmutar={() => conmutar(c.codigo)} corte={c.codigo === "contratos" ? fechaCorte(cfg.contratos_corte) : null}
                    atenuada={ATENUABLES.has(c.codigo) ? atenuadas.has(c.codigo) : undefined}
                    onAtenuar={() => setAtenuadas((s) => { const n = new Set(s); if (n.has(c.codigo)) n.delete(c.codigo); else n.add(c.codigo); return n; })} />)}
                </section>);
            })}
            {cfg.por_perfil ? <button type="button" className="tec-boton-sec geo-omision" onClick={() => setPanel("omision")}>Capas al abrir, por perfil…</button> : null}
          </aside>) : null}
        {panel === "omision" && cfg.por_perfil ? <EditarOmision cfg={cfg} onCerrar={(cambio) => { setPanel(""); if (cambio) onRecargar(); }} /> : null}
      </div>

      {ficha.length ? (
        <div className="geo-ficha">
          <FichaActivo key={ficha[ficha.length - 1]} codigo={ficha[ficha.length - 1]} onAbrir={(c) => setFicha((p) => [...p, c])}
            rotuloVolver={ficha.length > 1 ? `Volver a ${ficha[ficha.length - 2]}` : "Volver al mapa"} onVolver={() => setFicha((p) => p.slice(0, -1))}
            onRegistrarIntervencion={cfg.formularios.mantenimiento ? onRegistrarIntervencion : undefined} />
        </div>) : null}
    </div>
  );
}

// Corte 7a (David, 16-nov): la capa de contratos dice de qué día es la cartera de la que sale el estado del contrato. «20261114» → «14-nov-2026».
const MESES_CORTE = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
export function fechaCorte(c?: string | null): string | null {
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec(c ?? "");
  return m && MESES_CORTE[Number(m[2]) - 1] ? `${Number(m[3])}-${MESES_CORTE[Number(m[2]) - 1]}-${m[1]}` : null;
}

function FilaCapa({ c, encendida, onConmutar, atenuada, onAtenuar, corte }: { c: CapaGeovisor; encendida: boolean; onConmutar: () => void; atenuada?: boolean; onAtenuar?: () => void; corte?: string | null }) {
  // «Flujo del agua (modelo)» (9b, Fase 3) llega como capa «preparada»: se puede encender cuando la base la pasa a «activa»
  const preparada = c.fuente === "preparada" && !(c.codigo === CAPA_FLUJO && c.estado === "activa");
  return (
    <div className="geo-capa-fila">
    <label className={`geo-capa${preparada ? " geo-capa-off" : ""}`} data-capa={c.codigo}>
      <input type="checkbox" checked={encendida && !preparada} disabled={preparada} onChange={onConmutar} />
      <span className="geo-capa-txt">
        <span className="geo-capa-nom">{c.nombre}{c.estado !== "activa" ? <span className="geo-est">{ESTADO_CAPA[c.estado]}</span> : null}</span>
        {c.nota ? <span className="geo-capa-nota">{c.nota}</span> : null}
        {corte ? <span className="geo-capa-nota geo-capa-corte" data-corte={c.codigo}>Estado según la cartera del {corte}</span> : null}
      </span>
    </label>
    {atenuada !== undefined && encendida ? <button type="button" className="geo-atenuar" aria-pressed={atenuada} onClick={onAtenuar} data-atenuar={c.codigo}>{atenuada ? "Atenuada" : "Atenuar"}</button> : null}
    </div>
  );
}

function SelectorPeriodo({ cfg, periodo, onCambiar }: { cfg: ConfigGeovisor; periodo: Periodo; onCambiar: (p: Periodo) => void }) {
  const [desde, setDesde] = useState(periodo.desde);
  const [hasta, setHasta] = useState(periodo.hasta);
  const minimo = restarMeses(cfg.hoy, cfg.rango_meses);
  const malo = !desde || !hasta ? "Elija las dos fechas." : desde > hasta ? "La fecha inicial es posterior a la final." : hasta > cfg.hoy ? "La fecha final no puede ser futura."
    : desde < restarMeses(hasta, cfg.rango_meses) ? `El rango es de máximo ${cfg.rango_meses} meses.` : null;
  if (!cfg.completo) return <p className="geo-periodo-fijo">Actividades de hoy</p>;
  return (
    <div className="geo-periodo">
      <div className="geo-seg" role="group" aria-label="Fechas de las actividades">
        <button type="button" aria-pressed={periodo.modo === "hoy"} onClick={() => onCambiar({ modo: "hoy", desde: cfg.hoy, hasta: cfg.hoy })}>Hoy</button>
        <button type="button" aria-pressed={periodo.modo === "semana"} onClick={() => onCambiar({ modo: "semana", desde: sumarDias(cfg.hoy, -6), hasta: cfg.hoy })}>7 días</button>
        <button type="button" aria-pressed={periodo.modo === "rango"} onClick={() => onCambiar({ ...periodo, modo: "rango" })}>Rango</button>
      </div>
      {periodo.modo === "rango" ? (
        <div className="geo-rango">
          <label>Desde <input type="date" value={desde} min={minimo} max={cfg.hoy} onChange={(e) => setDesde(e.target.value)} /></label>
          <label>Hasta <input type="date" value={hasta} min={minimo} max={cfg.hoy} onChange={(e) => setHasta(e.target.value)} /></label>
          <button type="button" className="tec-boton-sec" disabled={!!malo} onClick={() => onCambiar({ modo: "rango", desde, hasta })}>Ver</button>
          {malo && desde && hasta ? <p className="tec-error-caja" role="alert">{malo}</p> : null}
        </div>) : null}
    </div>
  );
}

function Leyenda({ colores, materiales, edadRef }: { colores: Exclude<Colores, "afectaciones">; materiales: { codigo: string; nombre: string; color: string }[]; edadRef?: boolean }) {
  const items = colores === "material" ? [...materiales.map((x) => [x.color, x.nombre]), [SIN_DATO, "Sin dato"]] : [...EDADES.map((e) => [e[1], e[2]]), [SIN_FECHA, "Sin fecha de instalación"]];
  return (
    <div className="geo-leyenda" aria-label={colores === "material" ? "Colores por material" : "Colores por edad"}>
      <strong>{colores === "material" ? "Material" : "Edad"}</strong>
      <ul>{items.map(([c, n]) => <li key={n}><span style={{ background: c }} aria-hidden="true" />{n}</li>)}</ul>
      {colores === "edad" && edadRef ? <p className="geo-leyenda-nota" data-testid="leyenda-edad-reg">Si el activo no tiene fecha de instalación, la edad sale de la fecha regulatoria, no de instalación.</p> : null}
    </div>
  );
}

// Corte 9b. Leyenda del modo «Afectaciones», en palabras sencillas (los textos vienen del servidor), y cuántas válvulas, contratos y daños hay ahora
function LeyendaCortes({ cortes, danos, hoy, onRecalcular }: { cortes: CortesVigentes | null; danos: DanoAbierto[] | null; hoy: boolean; onRecalcular?: () => void }) {
  const texto = (k: string, t: string) => cortes?.leyenda?.find((x) => x.clave === k)?.texto ?? t;
  return (
    <div className="geo-leyenda geo-leyenda-cortes" aria-label="Afectaciones" data-testid="leyenda-cortes">
      <strong>Afectaciones</strong>
      <ul>
        <li><span className="geo-corte-afectado" aria-hidden="true" />{texto("afectado", "Sin agua")}</li>
        <li><span className="geo-corte-cerrado" aria-hidden="true" />{texto("cerrado", "Tubería cerrada")}</li>
        <li><span className="geo-leyenda-punto geo-corte-valvula" aria-hidden="true" />{texto("valvula", "Válvula cerrada")}</li>
        <li><span className="geo-corte-dano" aria-hidden="true" />Daño reportado</li>
      </ul>
      {cortes?.hay && cortes.resumen
        ? <p className="geo-leyenda-nota">{cortes.resumen.valvulas_cerradas === 1 ? "1 válvula cerrada" : `${cortes.resumen.valvulas_cerradas} válvulas cerradas`} · {nContratos(cortes.resumen.contratos)} sin agua</p>
        : <p className="geo-leyenda-nota">{cortes ? "No hay válvulas cerradas en este momento." : "Cargando…"}</p>}
      {danos ? <p className="geo-leyenda-nota" data-testid="leyenda-danos">{danos.length === 0 ? "Sin daños abiertos" : danos.length === 1 ? "1 daño abierto" : `${danos.length} daños abiertos`}
        {hoy ? " reportados hoy" : danos.length ? ", sin límite de fecha" : ""} (acueducto y alcantarillado)</p> : null}
      {onRecalcular ? <button type="button" className="geo-leyenda-accion" onClick={onRecalcular}>Volver a calcular</button> : null}
    </div>
  );
}

// Corte 9b, Fase 3. Leyenda de «Flujo del agua (modelo)»: grosor por caudal, gris sin flujo y el rótulo «Modelo, no medido»
function LeyendaFlujo({ info, derecha }: { info: FlujoInfo | null; derecha: boolean }) {
  // en el celular llega plegada (deja libre el mapa); el rótulo «Modelo, no medido» queda siempre a la vista
  const [abierta, setAbierta] = useState(() => typeof window === "undefined" || window.innerWidth >= 700);
  return (
    <div className={`geo-leyenda geo-leyenda-flujo${derecha ? " geo-leyenda-2" : ""}`} aria-label="Flujo del agua (modelo)" data-testid="leyenda-flujo">
      <button type="button" className="geo-leyenda-plegar" aria-expanded={abierta} onClick={() => setAbierta((x) => !x)}>{info?.leyenda.titulo ?? "Caudal según el modelo"}{info ? ` (${info.leyenda.unidad})` : ""}</button>
      {abierta ? (
        <>
          <ul>
            {(info?.leyenda.clases ?? []).map((c) => <li key={c.clase}><span style={{ background: COLOR_FLUJO.agua, height: GROSOR_FLUJO[c.clase - 1] }} aria-hidden="true" />{c.texto}</li>)}
            <li><span style={{ background: COLOR_FLUJO.sin_flujo, height: 1.5 }} aria-hidden="true" />{info?.leyenda.sin_flujo ?? "Sin flujo en el modelo"}</li>
          </ul>
          <p className="geo-leyenda-nota">La flecha va hacia donde corre el agua. {info?.leyenda.sin_dato ?? ""}</p>
        </>) : null}
      <p className="geo-adv tec-aviso tec-aviso-info" data-testid="flujo-rotulo">{info?.rotulo ?? "Modelo, no medido (modeloV1, Plan Maestro 2014)"}</p>
    </div>
  );
}

// Corte 9b, Fase 3. Tarjeta de un tramo de «Flujo del agua (modelo)»: caudal y velocidad en las dos horas
function TarjetaFlujo({ codigo, onCerrar }: { codigo: string; onCerrar: () => void }) {
  const [d, setD] = useState<FlujoTramo | null>(null); const [error, setError] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setD(null); setError(null); apiFlujo.tramo(codigo).then((r) => { if (vivo) setD(r); }).catch((e) => { if (vivo) setError(e instanceof Error ? e.message : "No se pudo cargar."); }); return () => { vivo = false; }; }, [codigo]);
  const num = (n: number) => new Intl.NumberFormat("es-CO", { maximumFractionDigits: 2 }).format(n);
  return (
    <section className="geo-tarjeta" aria-label={`Flujo del modelo en ${codigo}`} data-capa="flujo">
      <div className="geo-tarjeta-cab"><div><h2>{codigo}</h2><p>Flujo del agua según el modelo</p></div><button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la tarjeta">✕</button></div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : !d ? <p className="tec-sub" role="status">Cargando…</p> : !d.en_modelo || !d.horas ? <p className="tec-ayuda">Este tramo no está en el modelo.</p> : (
        <>
          <dl>{d.horas.map((h) => (
            <div key={h.cual}><dt>{h.cual === "mayor" ? "Mayor consumo" : "Menor consumo"} ({h.hora}:00)</dt>
              <dd>{h.sentido === "sin_flujo" ? "Sin flujo" : `${num(h.caudal_lps)} L/s · ${num(h.velocidad_mps)} m/s`}</dd></div>))}</dl>
          {d.cambia_de_sentido ? <p className="tec-ayuda">El agua cambia de sentido entre las dos horas.</p> : null}
        </>)}
      <p className="geo-adv tec-aviso tec-aviso-info">{d?.rotulo ?? "Modelo, no medido (modeloV1, Plan Maestro 2014)"}</p>
    </section>
  );
}

// Corte 9b. El supervisor o el administrador marcan una válvula cerrada sin daño ni intervención (la base exige el motivo)
function CierreSupervisor({ valvula, cerrada, onHecho }: { valvula: string; cerrada: boolean; onHecho: () => void }) {
  const [abierto, setAbierto] = useState(false); const [motivo, setMotivo] = useState(""); const [hecho, setHecho] = useState(""); const [regreso, setRegreso] = useState("");
  const [ocupado, setOcupado] = useState(false); const [error, setError] = useState<string | null>(null);
  if (cerrada) return <p className="tec-ayuda geo-cierre-sup" data-testid="cierre-sup">Esta válvula está cerrada: véala en «Afectaciones».</p>;
  if (!abierto) return <div className="geo-tarjeta-acc geo-cierre-sup" data-testid="cierre-sup"><button type="button" className="tec-boton-sec" onClick={() => setAbierto(true)}>Marcar válvula cerrada</button></div>;
  const enviar = async () => {
    setOcupado(true); setError(null);
    try { await apiCierre.maniobra(valvula, "cerrar", { motivo: motivo.trim(), hecho_en: instanteDeCampo(hecho), regreso: instanteDeCampo(regreso) }); onHecho(); }
    catch (e) { setError(e instanceof Error ? e.message : "No se pudo completar. Intente de nuevo."); } finally { setOcupado(false); }
  };
  return (
    <div className="cie-pedir geo-cierre-sup" role="group" aria-label={`Cerrar la válvula ${valvula} sin daño ni intervención`} data-testid="cierre-sup">
      <p className="tec-ayuda">Sin daño ni intervención (maniobra de operación). Si hay un daño, ciérrela desde el daño o la intervención.</p>
      <div className="tec-campo"><label htmlFor="geo-cs-motivo">Motivo <span className="tec-oblig">(10 letras o más)</span></label>
        <input id="geo-cs-motivo" type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></div>
      <div className="tec-campo"><label htmlFor="geo-cs-hecho">¿A qué hora? <span className="tec-oblig">(vacío si fue ahora)</span></label>
        <input id="geo-cs-hecho" type="datetime-local" value={hecho} onChange={(e) => setHecho(e.target.value)} /></div>
      <div className="tec-campo"><label htmlFor="geo-cs-regreso">Regreso estimado del servicio <span className="tec-oblig">(opcional)</span></label>
        <input id="geo-cs-regreso" type="datetime-local" value={regreso} onChange={(e) => setRegreso(e.target.value)} /></div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      <div className="cie-pedir-acc">
        <button type="button" className="tec-boton" disabled={ocupado || motivo.trim().length < 10} onClick={() => void enviar()}>{ocupado ? "Registrando el cierre…" : "Confirmar el cierre"}</button>
        <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => setAbierto(false)}>Cancelar</button>
      </div>
    </div>
  );
}

// Corte 9b. Tarjetas del modo «Afectaciones», en lenguaje claro: la zona sin agua y la válvula cerrada. Solo conteos; «quién» es el funcionario.
function TarjetaCorte({ sel, cortes, zonas, danos, puede, onElegir, onCerrar, onCambio }: {
  sel: CorteSel; cortes: CortesVigentes; zonas: ZonaCorte[]; danos: DanoAbierto[]; puede: boolean; onElegir: (s: CorteSel) => void; onCerrar: () => void; onCambio: () => void;
}) {
  const [accion, setAccion] = useState<"" | "abrir" | "regreso">("");
  const [regreso, setRegreso] = useState(""); const [ocupado, setOcupado] = useState<string | null>(null); const [error, setError] = useState<string | null>(null);
  const [motivo, setMotivo] = useState("");
  const clave = sel.tipo === "zona" ? `z${sel.zona}` : sel.tipo === "recalcular" ? "r" : `${sel.tipo}${sel.codigo}`;
  useEffect(() => { setAccion(""); setError(null); setRegreso(""); }, [clave]);
  const cab = (titulo: string, sub: string) => (
    <div className="geo-tarjeta-cab"><div><h2>{titulo}</h2><p>{sub}</p></div><button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la tarjeta">✕</button></div>);
  const hacer = async (f: () => Promise<unknown>, texto: string) => {
    setOcupado(texto); setError(null);
    try { await f(); setAccion(""); onCambio(); return true; } catch (e) { setError(e instanceof Error ? e.message : "No se pudo completar. Intente de nuevo."); return false; } finally { setOcupado(null); }
  };
  if (sel.tipo === "dano") {      // daño abierto, con o sin cierre: tipo, desde cuándo, riesgo y si ya tiene válvulas cerradas
    const d = danos.find((x) => x.codigo === sel.codigo);
    if (!d) return null;
    const vs = cortes.valvulas.filter((v) => v.registro === d.codigo);
    return (
      <section className="geo-tarjeta geo-tarjeta-dano" aria-label={`Daño reportado ${d.codigo}`} data-capa="corte_dano">
        {cab(`${d.clase === "falla" ? "Falla reportada" : "Daño reportado"} ${d.codigo}`, d.tipo)}
        <dl>
          <div><dt>Desde</dt><dd>{horaClara(d.cuando)}</dd></div>
          <div><dt>Riesgo</dt><dd>{d.riesgo ? d.riesgo.charAt(0).toUpperCase() + d.riesgo.slice(1) : "—"}</dd></div>
          <div><dt>Estado</dt><dd>{d.estado === "en_atencion" ? "En atención" : "Reportado"}</dd></div>
          <div><dt>{d.sistema === "alcantarillado" ? "Activo de alcantarillado" : "Activo de acueducto"}</dt><dd>{d.activo ?? "Sin activo seleccionado"}</dd></div>
          <div><dt>Válvulas cerradas</dt><dd>{d.sistema !== "acueducto" ? "No aplica" : vs.length === 0 ? "Todavía ninguna" : vs.length === 1 ? "1 cerrada" : `${vs.length} cerradas`}</dd></div>
        </dl>
        {vs.length ? <div className="geo-tarjeta-acc">{vs.map((v) => <button key={v.codigo} type="button" className="tec-boton-sec" onClick={() => onElegir({ tipo: "valvula", codigo: v.codigo })}>Válvula {v.nombre || v.codigo}</button>)}</div> : null}
      </section>);
  }
  if (sel.tipo === "recalcular") {
    return (
      <section className="geo-tarjeta geo-tarjeta-corte" aria-label="Volver a calcular las afectaciones" data-capa="corte_recalcular">
        {cab("Volver a calcular", "Las zonas sin agua con las válvulas cerradas ahora")}
        <p className="tec-ayuda">Úselo si la red cambió (una carga nueva o una ficha corregida) después del último cierre. No abre ni cierra ninguna válvula.</p>
        <div className="tec-campo"><label htmlFor="geo-recalc">Motivo <span className="tec-oblig">(10 letras o más)</span></label>
          <input id="geo-recalc" type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></div>
        {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
        <div className="geo-tarjeta-acc">
          <button type="button" className="tec-boton" disabled={!!ocupado || motivo.trim().length < 10} onClick={() => void hacer(() => apiCierre.recalcular(motivo.trim()), "Calculando…").then((b) => { if (b) onCerrar(); })}>{ocupado ?? "Volver a calcular"}</button>
        </div>
      </section>);
  }
  if (sel.tipo === "zona") {
    const i = zonas.findIndex((z) => z.zona === sel.zona), z = zonas[i];
    if (!z) return null;
    const valvulas = cortes.valvulas.filter((v) => v.zona === z.zona);
    return (
      <section className="geo-tarjeta geo-tarjeta-corte" aria-label={`Zona ${i + 1} sin agua`} data-capa="corte_zona">
        {cab(`Zona ${i + 1} sin agua`, z.desde ? `Sin agua desde ${horaClara(z.desde).includes(",") ? "el" : "las"} ${horaClara(z.desde)}` : "Sin agua")}
        <dl>
          <div><dt>Por</dt><dd>{z.por.length ? z.por.map((x) => [x.que, x.registro].filter(Boolean).join(" · ")).join("; ") : "—"}</dd></div>
          <div><dt>Contratos afectados</dt><dd>{new Intl.NumberFormat("es-CO").format(z.contratos)}</dd></div>
          {z.regreso_estimado ? <div><dt>Regreso estimado del servicio</dt><dd>{horaClara(z.regreso_estimado)}</dd></div> : null}
        </dl>
        {valvulas.length ? <div className="geo-tarjeta-acc">{valvulas.map((v) => <button key={v.codigo} type="button" className="tec-boton-sec" onClick={() => onElegir({ tipo: "valvula", codigo: v.codigo })}>Válvula {v.nombre || v.codigo}</button>)}</div> : null}
      </section>);
  }
  const v: ValvulaCerrada | undefined = cortes.valvulas.find((x) => x.codigo === sel.codigo);
  if (!v) return null;
  return (
    <section className="geo-tarjeta geo-tarjeta-corte" aria-label={`Válvula cerrada ${v.codigo}`} data-capa="corte_valvula">
      {cab(`Válvula cerrada ${v.codigo}`, v.nombre && v.nombre !== v.codigo ? v.nombre : "Válvula de acueducto")}
      <dl>
        <div><dt>Cerrada desde</dt><dd>{horaClara(v.desde)}</dd></div>
        <div><dt>Por</dt><dd>{v.quien}</dd></div>
        <div><dt>Daño o intervención</dt><dd>{v.registro ?? "Maniobra del supervisor"}</dd></div>
        {v.regreso_estimado ? <div><dt>Regreso estimado del servicio</dt><dd>{horaClara(v.regreso_estimado)}</dd></div> : null}
      </dl>
      {!v.en_red ? <p className="tec-ayuda">Esta válvula no está en la red en operación: su cierre no deja tramos sin agua en el cálculo.</p> : null}
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      {accion === "abrir" ? <PedirHora valvula={v.codigo} tipo="abrir" ocupado={ocupado} onCancelar={() => setAccion("")}
        onConfirmar={(h) => void hacer(() => apiCierre.maniobra(v.codigo, "abrir", { hecho_en: instanteDeCampo(h) }), "Registrando la apertura…")} /> : null}
      {accion === "regreso" ? (
        <div className="cie-pedir" role="group" aria-label="Ajustar la hora de regreso">
          <div className="tec-campo"><label htmlFor="geo-regreso">Regreso estimado del servicio</label>
            <input id="geo-regreso" type="datetime-local" value={regreso} onChange={(e) => setRegreso(e.target.value)} /></div>
          <div className="cie-pedir-acc">
            <button type="button" className="tec-boton" disabled={!!ocupado || !instanteDeCampo(regreso)} onClick={() => void hacer(() => apiCierre.regreso(v.codigo, instanteDeCampo(regreso)!), "Guardando…")}>{ocupado ?? "Guardar la hora"}</button>
            <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setAccion("")}>Cancelar</button>
          </div>
        </div>) : null}
      {puede && !accion ? (
        <div className="geo-tarjeta-acc">
          <button type="button" className="tec-boton-sec" onClick={() => setAccion("abrir")}>Válvula abierta</button>
          <button type="button" className="tec-boton-sec" onClick={() => setAccion("regreso")}>Ajustar hora de regreso</button>
        </div>) : null}
    </section>
  );
}

// Corte 5d. Leyenda de la línea 116 (y cuántos reportes del periodo no están en el mapa por no tener ubicación)
function Leyenda116({ derecha, sinUbicar }: { derecha: boolean; sinUbicar: number }) {
  return (
    <div className={`geo-leyenda geo-leyenda-presion${derecha ? " geo-leyenda-2" : ""}`} aria-label="Colores de la línea 116" data-testid="leyenda-116">
      <strong>Línea 116</strong>
      <ul>{Object.entries(COLOR_116).map(([k, c]) => <li key={k}><span className="geo-leyenda-punto" style={{ background: c }} aria-hidden="true" />{NOMBRE_SERV_116[k]}</li>)}</ul>
      <p className="geo-leyenda-nota">Lleno: registrado · hueco: atendido · más grande: varios reportes del mismo contrato, causal y día</p>
      {sinUbicar > 0 ? <p className="geo-leyenda-nota">{nf.format(sinUbicar)} del periodo sin ubicar (su contrato no está en el catastro; no están en el mapa)</p> : null}
    </div>
  );
}

function TarjetaElemento({ t, cfg, onCerrar, onVerFicha, onReportarDano, onRegistrarIntervencion, cortes, onCierre }: {
  cortes?: CortesVigentes | null; onCierre?: (codigo: string) => void;
  t: Tarjeta; cfg: ConfigGeovisor; onCerrar: () => void; onVerFicha: (c: string) => void;
  onReportarDano?: (a: ActivoTarjeta) => void; onRegistrarIntervencion?: (a: ActivoTarjeta) => void;
}) {
  const p = t.props;
  const filas: [string, string][] = [];
  let titulo = texto(p.codigo), sub = "", activo: string | null = null;
  if (t.capa === "activo") {
    sub = cfg.tipos[String(p.prefijo)] ?? String(p.prefijo);
    if (p.clase) filas.push(["Clase", texto(p.clase)]);
    if (p.material) filas.push(["Material", cfg.materiales.find((x) => x.codigo === p.material)?.nombre ?? texto(p.material)]);
    if (typeof p.diametro === "number") filas.push(["Diámetro", `${nf.format(p.diametro)} mm`]);
    filas.push(["Edad", typeof p.edad === "number" ? `${p.edad} años${p.edad_reg ? " (fecha regulatoria, no de instalación)" : ""}` : "Sin fecha de instalación"]);      // Corte 10
    filas.push(["Estado", cfg.estados?.[String(p.estado)] ?? texto(p.estado)]);
    if (p.nombre) filas.unshift(["Nombre", texto(p.nombre)]);      // Corte 9a: sectores e instalaciones
    if (p.prefijo === "SEC") filas.push(["Origen", "Plan Maestro 2014 · sectores con que se opera"]);      // 9a-bis (David, 16-nov): son los de hoy
    activo = String(p.codigo);
  } else if (t.capa.startsWith("ref:")) {
    return <TarjetaReferencia capa={t.capa.slice(4)} llave={String(p.llave)} nombre={texto(p.nombre)} cfg={cfg} onCerrar={onCerrar} onVerFicha={onVerFicha} />;
  } else if (t.capa === "danos") {
    sub = `${p.clase === "falla" ? "Falla" : "Daño"} · ${texto(p.tipo)}`;
    filas.push(["Estado", ESTADO_DANO[String(p.estado)] ?? texto(p.estado)], ["Detectado", fechaHora(p.cuando)], ["Riesgo", texto(p.riesgo)], ["Activo", texto(p.activo)]);
    activo = p.activo ? String(p.activo) : null;
  } else if (t.capa === "intervenciones") {
    sub = `Intervención · ${NOMBRE_ITV[String(p.tipo_codigo)] ?? texto(p.tipo)}`;
    filas.push(["Inicio", fechaHora(p.cuando)], ["Fin", fechaHora(p.fin)], ["Ejecutor", texto(p.ejecutor)], ["Activo", texto(p.activo)]);
    if (p.dano) filas.push(["Atiende el daño", texto(p.dano)]);
    activo = p.activo ? String(p.activo) : null;
  } else if (t.capa === "muestreo") {
    sub = `Punto de muestreo · ${texto(p.nombre)}`;
    filas.push(["Calidad", NOMBRE_CALIDAD[String(p.calidad)] ?? "Sin muestra reciente"], ["Zona", texto(p.zona)], ["Ubicación", p.exactitud === "verificada" ? "Verificada" : "Aproximada (por barrio)"]);
    const medidas = (typeof p.medidas === "string" ? JSON.parse(p.medidas) : p.medidas ?? []) as { nombre: string; unidad: string; valor: number; cuando: string; reciente: boolean; min: number | null; max: number | null; rango: string | null }[];
    for (const x of medidas) {
      const rango = x.rango ? ` · rango ${x.min ?? "—"} a ${x.max ?? "—"} (${x.rango === "salida" ? "Salida" : "Muestreo"})` : " · sin rango";
      filas.push([x.nombre, `${nf.format(x.valor)} ${x.unidad}${rango} · ${fechaHora(x.cuando)}${x.reciente ? "" : " (vieja)"}`]);
    }
  } else if (t.capa === "reportes_comercial") {
    sub = `Reporte de Comercial · ${texto(p.tipo)}`;
    filas.push(["Contrato", p.con_contrato === true || p.con_contrato === "true" ? "Con código de contrato" : "Sin contrato (posible clandestino)"], ["Subtipo", texto(p.subtipo)],
               ["Área", texto(p.area)], ["Estado", texto(p.estado)], ["Registrado", fechaHora(p.cuando)]);
  } else if (t.capa === "pqr_116") {      // Corte 5d: sin nombre, dirección ni barrio
    const reps = (typeof p.reportes === "string" ? JSON.parse(p.reportes) : p.reportes ?? []) as number[];
    const danos = (typeof p.danos === "string" ? JSON.parse(p.danos) : p.danos ?? []) as string[] | null;
    const nRep = Number(p.n ?? 1), reg = Number(p.registrados ?? 0);
    titulo = nRep > 1 ? `${nRep} reportes de la línea 116` : `Reporte ${texto(p.codigo)} de la línea 116`;
    sub = `${NOMBRE_SERV_116[String(p.grupo_servicio)] ?? texto(p.servicio)} · ${texto(p.causal)}`;
    filas.push(["Estado", nRep > 1 ? (reg ? `${reg} de ${nRep} registrados (sin atender)` : "Todos atendidos") : reg ? "Registrado (sin atender)" : "Atendido"]);
    filas.push([nRep > 1 ? "Reportes" : "Reporte", reps.map((r) => String(r)).join(", ") + (nRep > reps.length ? ` y ${nRep - reps.length} más` : "")]);
    filas.push(["Registrado", nRep > 1 && p.ultimo !== p.cuando ? `${fechaHora(p.cuando)} a ${fechaHora(p.ultimo)}` : fechaHora(p.cuando)]);
    if (p.contrato) filas.push(["Contrato", texto(p.contrato)]);
    filas.push(["Ubicación", METODO_116[String(p.metodo)] ?? texto(p.metodo)]);
    if (p.sector) filas.push(["Sector hidráulico", p.subsector ? `${p.sector} (subsector ${p.subsector})` : String(p.sector)]);
    if (danos && danos.length) filas.push(["Convertido en", danos.join(", ")]);
  } else if (t.capa === "contrato") {
    return <TarjetaDeContrato contrato={String(p.contrato)} cfg={cfg} onCerrar={onCerrar} onVerFicha={onVerFicha} />;
  } else if (t.capa === "reportes_bot") {
    sub = `Reporte del bot · ${texto(p.tipo)}`;
    filas.push(["Estado", texto(p.estado)], ["Recibido", fechaHora(p.cuando)], ["Canal", texto(p.canal)]);
    if (p.dano) filas.push(["Convertido en", texto(p.dano)]);
  }
  const sistema = t.capa === "activo" ? String(p.sistema) : String(p.sistema ?? "");
  const red = sistema === "acueducto" || sistema === "alcantarillado";
  const desde = t.capa === "activo" && red ? { codigo: String(p.codigo), sistema: sistema as ActivoTarjeta["sistema"], lat: t.lat, lon: t.lon } : null;
  return (
    <section className="geo-tarjeta" aria-label={`Tarjeta de ${titulo}`} data-capa={t.capa}>
      <div className="geo-tarjeta-cab">
        <div><h2>{titulo}</h2><p>{sub}</p></div>
        <button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la tarjeta">✕</button>
      </div>
      <dl>{filas.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}</dl>
      <div className="geo-tarjeta-acc">
        {activo && cfg.ficha ? <button type="button" className="tec-boton-sec" onClick={() => onVerFicha(activo!)}>{t.capa === "activo" ? "Ver ficha" : "Ficha del activo"}</button> : null}
        {desde && cfg.formularios.danos_fallas && onReportarDano ? <button type="button" className="tec-boton-sec" onClick={() => onReportarDano(desde)}>Reportar daño</button> : null}
        {desde && cfg.formularios.mantenimiento && onRegistrarIntervencion ? <button type="button" className="tec-boton-sec" onClick={() => onRegistrarIntervencion(desde)}>Registrar intervención</button> : null}
      </div>
      {/* Corte 9b: el supervisor o el administrador cierran una válvula de acueducto sin daño ni intervención, con motivo */}
      {t.capa === "activo" && cfg.completo && sistema === "acueducto" && String(p.prefijo) === "VAL" && onCierre
        ? <CierreSupervisor valvula={String(p.codigo)} cerrada={!!cortes?.valvulas.some((v) => v.codigo === String(p.codigo))} onHecho={() => onCierre(String(p.codigo))} /> : null}
    </section>
  );
}

function EditarOmision({ cfg, onCerrar }: { cfg: ConfigGeovisor; onCerrar: (cambio: boolean) => void }) {
  const [perfil, setPerfil] = useState<PerfilGeovisor>("supervisor_distribucion");
  const vigente = (pf: PerfilGeovisor, c: string) => cfg.por_perfil?.some((x) => x.perfil === pf && x.capa === c && x.encendida) ?? false;
  const [marcas, setMarcas] = useState<Record<string, boolean>>({});
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const capas = cfg.capas.filter((c) => c.fuente !== "preparada");
  const clave = (c: string) => `${perfil}|${c}`;
  const cambios = Object.entries(marcas).filter(([k, v]) => { const [pf, c] = k.split("|"); return v !== vigente(pf as PerfilGeovisor, c); });
  async function guardar() {
    setEnviando(true); setError(null);
    try {
      for (const [k, v] of cambios) { const [pf, c] = k.split("|"); await apiGeovisor.fijar(pf as PerfilGeovisor, c, v, motivo.trim()); }
      onCerrar(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo guardar.");
    } finally { setEnviando(false); }
  }
  return (
    <aside className="geo-panel" aria-label="Capas al abrir, por perfil">
      <div className="geo-panel-cab"><h2>Capas al abrir</h2><button type="button" className="geo-cerrar" onClick={() => onCerrar(false)} aria-label="Cerrar">✕</button></div>
      <p className="tec-ayuda">Lo que cada perfil ve encendido al abrir el geovisor. El administrador abre con las de los dos supervisores. El operador no ve muestreo ni reportes.</p>
      <label className="geo-campo">Perfil
        <select value={perfil} onChange={(e) => setPerfil(e.target.value as PerfilGeovisor)}>{PERFILES.map((x) => <option key={x.c} value={x.c}>{x.n}</option>)}</select>
      </label>
      {capas.map((c) => {
        const v = marcas[clave(c.codigo)] ?? vigente(perfil, c.codigo);
        return (
          <label key={c.codigo} className="geo-capa" data-omision={c.codigo}>
            <input type="checkbox" checked={v} onChange={(e) => setMarcas((m) => ({ ...m, [clave(c.codigo)]: e.target.checked }))} />
            <span className="geo-capa-txt"><span className="geo-capa-nom">{c.nombre}</span></span>
          </label>);
      })}
      <label className="geo-campo">Motivo del cambio
        <textarea rows={2} value={motivo} maxLength={1000} onChange={(e) => setMotivo(e.target.value)} placeholder="Por ejemplo: el supervisor de planta también revisa la red" />
      </label>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      <button type="button" className="tec-boton" disabled={!cambios.length || motivo.trim().length < 10 || enviando} aria-busy={enviando} onClick={() => void guardar()}>
        {enviando ? "Guardando…" : cambios.length ? `Guardar ${cambios.length} cambio${cambios.length > 1 ? "s" : ""}` : "Sin cambios"}
      </button>
    </aside>
  );
}

// Corte 9a. Leyenda de la presión: los colores salen de los umbrales de Parámetros (15, 10, 50 y 60 m.c.a. por omisión). La del modelo lleva su advertencia.
function LeyendaPresion({ modelo, medida, arriba }: { modelo: boolean; medida: boolean; arriba: boolean }) {
  return (
    <div className={`geo-leyenda geo-leyenda-presion${arriba ? " geo-leyenda-2" : ""}`} aria-label="Colores de la presión">
      <strong>Presión (m.c.a.)</strong>
      {modelo ? <p className="geo-adv" role="note">Presión de modelo, no medida</p> : null}
      {medida ? <p className="geo-leyenda-nota">Borde negro: medida en la campaña de 2014</p> : null}
      <ul>{(["baja_roja", "baja_naranja", "normal", "alta_naranja", "alta_roja"] as NivelPresion[]).map((n) => <li key={n}><span className="geo-leyenda-punto" style={{ background: COLOR_NIVEL[n] }} aria-hidden="true" />{NOMBRE_NIVEL[n]}</li>)}</ul>
    </div>
  );
}

// Corte 9a. Tarjeta de un elemento de REFERENCIA (no es un activo): se pide al tocarlo. Dice de dónde sale y, si es presión, si es de modelo o medida.
function TarjetaReferencia({ capa, llave, nombre, cfg, onCerrar, onVerFicha }: { capa: string; llave: string; nombre: string; cfg: ConfigGeovisor; onCerrar: () => void; onVerFicha: (c: string) => void }) {
  const [d, setD] = useState<TarjetaRef | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    setD(null); setError(null);
    apiGeovisor.referencia(capa, llave).then((r) => { if (vivo) setD(r); }).catch((e) => { if (vivo) setError(e instanceof Error ? e.message : "No se pudo cargar."); });
    return () => { vivo = false; };
  }, [capa, llave]);
  const nombreCapa = cfg.capas.find((c) => c.codigo === capa)?.nombre ?? "Capa de referencia";
  return (
    <section className="geo-tarjeta" aria-label={`Tarjeta de ${d?.titulo ?? nombre}`} data-capa={`ref-${capa}`}>
      <div className="geo-tarjeta-cab">
        <div><h2>{d?.titulo ?? nombre}</h2><p>{d ? d.subtitulo ?? nombreCapa : "Cargando…"}</p></div>
        <button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la tarjeta">✕</button>
      </div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      {d ? (
        <>
          {d.advertencia ? <p className={`geo-adv${capa === "campana_2014" ? " geo-adv-medida" : ""}`} role="note">{d.advertencia}</p> : null}
          {d.nivel ? <p className="geo-nivel"><span className="geo-leyenda-punto" style={{ background: COLOR_NIVEL[d.nivel] }} aria-hidden="true" />{NOMBRE_NIVEL[d.nivel]}</p> : null}
          {(d.series ?? []).some((s) => (s.puntos?.length ?? s.valores?.length ?? 0) > 1) ? <GraficaRef series={d.series!} /> : null}
          <dl>{d.filas.map((f) => <div key={f.r}><dt>{f.r}</dt><dd>{typeof f.v === "number" ? nf.format(f.v) : f.v}{f.u ? ` ${f.u}` : ""}</dd></div>)}</dl>
          {d.origen ? <p className="geo-origen">Origen: {d.origen}</p> : null}
          {d.activo && cfg.ficha ? <div className="geo-tarjeta-acc"><button type="button" className="tec-boton-sec" onClick={() => onVerFicha(d.activo!)}>Ficha de {d.activo}</button></div> : null}
        </>) : null}
    </section>
  );
}

// Gráfica de líneas en SVG (sin librerías): la serie de 15 min de la campaña (eje de tiempo) o el perfil horario del modelo (0 a 24 h). Las líneas de 15 y 10 m.c.a. de referencia.
const COLOR_SERIE = ["#1F5FA8", "#AD1457", "#2E7D32"];
function GraficaRef({ series }: { series: SerieRef[] }) {
  const W = 340, H = 150, ml = 30, mr = 6, mt = 8, mb = 20;
  const datos = series.map((s) => (s.eje === "hora" ? (s.valores ?? []).map((v, i) => [i, v] as [number, number]) : (s.puntos ?? []).map(([t, v]) => [Date.parse(t + ":00Z"), v] as [number, number])))
    .filter((p) => p.length > 1);
  if (!datos.length) return null;
  const xs = datos.flat().map((p) => p[0]), ys = datos.flat().map((p) => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(0, ...ys), y1 = Math.max(16, ...ys) * 1.05;
  const X = (x: number) => ml + ((x - x0) / Math.max(1, x1 - x0)) * (W - ml - mr), Y = (y: number) => mt + (1 - (y - y0) / Math.max(1e-9, y1 - y0)) * (H - mt - mb);
  const hora = series[0].eje === "hora";
  const marcasX = hora ? [0, 6, 12, 18, 24] : Array.from({ length: Math.floor((x1 - x0) / 86400000) + 2 }, (_, i) => (Math.floor(x0 / 86400000) + i) * 86400000).filter((t) => t >= x0 && t <= x1);
  // las líneas de 0, 10 y 15 van siempre; un rótulo se calla si queda a menos de 11 px de uno ya puesto (0 y 15 mandan sobre el 10 y sobre los extremos)
  const marcasY = [0, 15, 10, y0 < 0 ? Math.ceil(y0) : null, Math.floor(y1)].filter((v, i, a): v is number => v !== null && a.indexOf(v) === i && v >= y0 && v <= y1);
  const conRotulo = marcasY.filter((v, i) => marcasY.slice(0, i).every((w) => Math.abs(Y(w) - Y(v)) >= 11));
  return (
    <figure className="geo-grafica">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${series.map((s) => s.nombre).join(" y ")}, en ${series[0].unidad}`} data-puntos={datos.reduce((n, p) => n + p.length, 0)}>
        {marcasY.map((v) => <g key={`y${v}`}><line x1={ml} x2={W - mr} y1={Y(v)} y2={Y(v)} stroke={v === 15 ? "#EF6C00" : v === 10 ? "#C62828" : "#dbe3e8"} strokeDasharray={v === 15 || v === 10 ? "4 3" : undefined} strokeWidth="1" />
          {conRotulo.includes(v) ? <text x={ml - 4} y={Y(v) + 4} textAnchor="end" fontSize="10" fill="#5b6b77">{v}</text> : null}</g>)}
        {marcasX.map((v) => <text key={`x${v}`} x={X(v)} y={H - 5} textAnchor="middle" fontSize="10" fill="#5b6b77">{hora ? `${v} h` : new Date(v).toLocaleDateString("es-CO", { day: "numeric", month: "short", timeZone: "UTC" })}</text>)}
        {datos.map((p, i) => <polyline key={i} fill="none" stroke={COLOR_SERIE[i % COLOR_SERIE.length]} strokeWidth="1.6" strokeLinejoin="round" points={p.map(([x, y]) => `${X(x).toFixed(1)},${Y(y).toFixed(1)}`).join(" ")} />)}
      </svg>
      <figcaption>{series.map((s, i) => <span key={s.nombre}><i style={{ background: COLOR_SERIE[i % COLOR_SERIE.length] }} aria-hidden="true" />{s.nombre}</span>)}<span className="geo-grafica-ref">Líneas punteadas: 15 y 10 m.c.a.</span></figcaption>
    </figure>
  );
}

// Tarjeta del contrato (§30.1). El nombre, la dirección y el barrio son DATO PERSONAL: se piden al tocar, viven solo en el estado de esta tarjeta y se
// descartan al cerrarla. No se guardan, no se descargan ni se imprimen. Sin teléfono ni deuda. El servidor registra la lectura.
function TarjetaDeContrato({ contrato, cfg, onCerrar, onVerFicha }: { contrato: string; cfg: ConfigGeovisor; onCerrar: () => void; onVerFicha: (c: string) => void }) {
  const [d, setD] = useState<TarjetaContrato | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    setD(null); setError(null);
    apiGeovisor.tarjetaContrato(contrato).then((r) => { if (vivo) setD(r); }).catch((e) => { if (vivo) setError(e instanceof Error ? e.message : "No se pudo cargar el contrato."); });
    return () => { vivo = false; setD(null); };
  }, [contrato]);
  const meses = d?.consumo?.meses ?? [];
  const tope = Math.max(1, ...meses.map((m) => m.m3 ?? 0));
  return (
    <section className="geo-tarjeta" aria-label={`Contrato ${contrato}`} data-capa="contrato">
      <div className="geo-tarjeta-cab">
        <div><h2>Contrato {contrato}</h2><p>{d ? `${ESTADO_CONTRATO[d.estado] ?? d.estado}${d.estado_texto && d.estado === "otro" ? ` (${d.estado_texto.toLowerCase()})` : ""} · ${d.uso ?? "uso sin dato"}` : "Cargando…"}</p></div>
        <button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar la tarjeta">✕</button>
      </div>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : null}
      {d ? (
        <>
          {d.datos_personales !== false ? (
            <div className="geo-personal" aria-label="Datos del suscriptor">
              <span className="geo-personal-rotulo">Dato personal · solo en pantalla</span>
              <dl>
                <div><dt>Suscriptor</dt><dd data-personal="nombre">{d.suscriptor.nombre ?? "Sin dato"}</dd></div>
                <div><dt>Dirección</dt><dd data-personal="direccion">{d.suscriptor.direccion ?? "Sin dato"}</dd></div>
                <div><dt>Barrio</dt><dd>{d.suscriptor.barrio ?? "Sin dato"}</dd></div>
              </dl>
            </div>) : (
            <dl data-sin-personal="si">
              <div><dt>Barrio</dt><dd>{d.suscriptor.barrio ?? "Sin dato"}</dd></div>
              <div><dt>Suscriptor</dt><dd className="tec-ayuda">El nombre y la dirección los ve el supervisor de distribución</dd></div>
            </dl>)}
          <dl>
            <div><dt>Medidor</dt><dd>{d.medidor_anios === null ? "Sin fecha real" : `${d.medidor_anios} años`}</dd></div>
            <div><dt>Tramo de acueducto</dt><dd>{d.tramo ?? "Sin enlazar"}</dd></div>
            {d.sector_hidraulico ? <div><dt>Sector hidráulico</dt><dd>{d.sector_hidraulico.sector}{d.sector_hidraulico.subsector ? ` · subsector ${d.sector_hidraulico.subsector}` : ""}</dd></div> : null}
          </dl>
          {d.consumo ? (
            <div className="geo-consumo" aria-label="Perfil de consumo de 6 meses">
              <p className="geo-consumo-tit">Consumo (m³) · promedio {d.consumo.promedio === null ? "—" : nf.format(d.consumo.promedio)}</p>
              <div className="geo-barras">
                {meses.map((m) => (
                  <div key={m.periodo} className="geo-barra-mes" title={`${m.periodo}: ${m.sin_dato ? "sin dato" : `${m.m3} m³`}`}>
                    <span className="geo-barra-val">{m.sin_dato || m.m3 === null ? "—" : m.m3}</span>
                    <span className={`geo-barra-col${m.lectura_real ? "" : " geo-barra-est"}`} style={{ height: `${m.sin_dato || m.m3 === null ? 0 : Math.max(4, (m.m3 / tope) * 56)}px` }} />
                    <span className="geo-barra-per">{m.periodo.slice(4)}/{m.periodo.slice(2, 4)}</span>
                  </div>))}
              </div>
            </div>) : <p className="tec-ayuda">Sin perfil de consumo en la ficha del contrato.</p>}
          {d.tramo && cfg.ficha ? <div className="geo-tarjeta-acc"><button type="button" className="tec-boton-sec" onClick={() => onVerFicha(d.tramo!)}>Ficha del tramo</button></div> : null}
        </>) : null}
    </section>
  );
}

// «Compartir» (§30.2): guarda la vista (capas, colores, fechas, centro y zoom; nada personal) y da un enlace. Quien lo abre inicia sesión y ve solo lo que puede.
function Compartir({ cfg, mapa, on, colores, periodo, atenuadas, onCerrar }: {
  cfg: ConfigGeovisor; mapa: maplibregl.Map | null; on: Set<string>; colores: Exclude<Colores, "afectaciones">; periodo: Periodo; atenuadas: Set<string>; onCerrar: () => void;
}) {
  const [enlace, setEnlace] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);
  useEffect(() => {
    if (!mapa) return;
    const c = mapa.getCenter();
    const capas = [...on].filter((x) => cfg.capas.some((k) => k.codigo === x && k.fuente !== "preparada"));
    apiGeovisor.compartir({ capas, colores, periodo: periodo.modo === "rango" ? periodo : { modo: periodo.modo }, lon: Number(c.lng.toFixed(6)), lat: Number(c.lat.toFixed(6)),
                            zoom: Number(Math.min(20, Math.max(10, mapa.getZoom())).toFixed(2)), atenuadas: [...atenuadas] })
      .then((r) => setEnlace(`${window.location.origin}${window.location.pathname}#geovisor=${r.id}`))
      .catch((e) => setError(e instanceof Error ? e.message : "No se pudo compartir."));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const copiar = () => { if (enlace) void navigator.clipboard?.writeText(enlace).then(() => setCopiado(true)).catch(() => setCopiado(false)); };
  const nav = navigator as Navigator & { share?: (d: { title?: string; url?: string }) => Promise<void> };
  return (
    <div className="geo-compartir" role="dialog" aria-label="Compartir la vista">
      <div className="geo-panel-cab"><h2>Compartir la vista</h2><button type="button" className="geo-cerrar" onClick={onCerrar} aria-label="Cerrar">✕</button></div>
      <p className="tec-ayuda">El enlace abre el geovisor con estas capas, colores, fechas y este lugar del mapa. Quien lo abra debe iniciar sesión y solo verá las capas para las que tiene permiso. No lleva datos personales.</p>
      {error ? <p className="tec-error-caja" role="alert">{error}</p> : !enlace ? <p className="tec-sub" role="status">Creando el enlace…</p> : (
        <>
          <input className="geo-enlace" readOnly value={enlace} aria-label="Enlace de la vista" onFocus={(e) => e.currentTarget.select()} />
          <div className="geo-tarjeta-acc">
            <button type="button" className="tec-boton-sec" onClick={copiar}>{copiado ? "Copiado" : "Copiar enlace"}</button>
            {nav.share ? <button type="button" className="tec-boton-sec" onClick={() => void nav.share!({ title: "Geovisor técnico", url: enlace }).catch(() => {})}>Enviar…</button> : null}
          </div>
        </>)}
    </div>
  );
}
