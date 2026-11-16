import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import "./geovisor.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import { apiGeovisor, type CapaDatos, type CapaGeovisor, type ConfigGeovisor, type GrupoCapa, type PerfilGeovisor } from "./apiGeovisor";
import { ErrorTec } from "./apiTecnica";
import { FichaActivo } from "./FichaActivo";

// Geovisor técnico (Técnica fase 1, Corte 6a; 01 sección D, N-11, N-13 y N-14).
// · Interruptores por grupo, encendidos al abrir según el perfil (lo decide el servidor) y «Volver a la vista por omisión». Encender o apagar no se guarda.
// · Red en una tesela propia (activos vigentes, con material, diámetro, edad y estado); colores por tipo, por material o por edad.
// · Daños, intervenciones y reportes del bot por fecha (hoy, últimos 7 días o un rango de hasta 12 meses); los puntos de muestreo, verificados o aproximados.
// · Tocar un elemento abre su tarjeta. Desde un activo: «Ver ficha» (supervisores y administrador), «Reportar daño» y «Registrar intervención» (si tiene el formulario).
// · El operador con la casilla del geovisor (N-13) ve solo lectura: la red y las actividades del día, sin ficha ni capas de supervisión.
// · Las capas preparadas (contratos, reportes de Comercial, PQR, presión…) se ven en la lista, apagadas y con su nota: no tienen datos todavía.
// · Sin datos de contratos, nombres, descripciones ni el tercero de un daño.

type ActivoTarjeta = { codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number };
type Tarjeta = { capa: string; props: Record<string, unknown>; lat: number; lon: number };
type Periodo = { modo: "hoy" | "semana" | "rango"; desde: string; hasta: string };
type Colores = "tipo" | "material" | "edad";

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
const EDADES: [number, string, string][] = [[0, "#2E7D32", "Menos de 10 años"], [10, "#9CCC65", "10 a 24 años"], [25, "#F9A825", "25 a 39 años"], [40, "#C62828", "40 años o más"]];
const COLOR_DANO: Record<string, string> = { reportado: "#D32F2F", en_atencion: "#EF6C00", atendido: "#2E7D32" };
const COLOR_ITV: Record<string, string> = { preventivo: "#0277BD", correctivo: "#EF6C00", reparacion: "#6A1B9A", reposicion: "#00838F", inversion: "#2E7D32" };
const NOMBRE_ITV: Record<string, string> = { preventivo: "Preventivo", correctivo: "Correctivo", reparacion: "Reparación", reposicion: "Reposición", inversion: "Inversión" };
const ESTADO_DANO: Record<string, string> = { reportado: "Reportado", en_atencion: "En atención", atendido: "Atendido" };
const ESTADO_CAPA: Record<string, string> = { por_conectar: "Por conectar", espera_dato: "Espera el dato" };
const VACIO: GeoJSON.FeatureCollection = { type: "FeatureCollection", features: [] };
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 1 });
const fechaHora = (v: unknown) => (typeof v === "string" ? new Date(v).toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short", timeZone: "America/Bogota" }) : "—");
const texto = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : String(v).replace(/_/g, " "));
const sumarDias = (iso: string, d: number) => { const x = new Date(iso + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + d); return x.toISOString().slice(0, 10); };
const restarMeses = (iso: string, m: number) => { const x = new Date(iso + "T12:00:00Z"); x.setUTCMonth(x.getUTCMonth() - m); return x.toISOString().slice(0, 10); };

export function Geovisor({ onVolver, onReportarDano, onRegistrarIntervencion }: {
  onVolver: () => void; onReportarDano?: (a: ActivoTarjeta) => void; onRegistrarIntervencion?: (a: ActivoTarjeta) => void;
}) {
  const [cfg, setCfg] = useState<ConfigGeovisor | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => {
    let vivo = true;
    setError(null);
    apiGeovisor.config().then((c) => { if (vivo) setCfg(c); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene el geovisor técnico. Pídale a su supervisor que se lo active en Personal." : e instanceof Error ? e.message : "No se pudo abrir el geovisor."); });
    return () => { vivo = false; };
  }, [vez]);
  if (error) return <div className="geo geo-msg"><section className="tec-tarjeta" role="alert"><h1>Geovisor técnico</h1><p>{error}</p>
    <div className="dash-acciones"><button type="button" className="tec-boton-sec" onClick={onVolver}>← Volver</button><button type="button" className="tec-boton" onClick={() => setVez((v) => v + 1)}>Reintentar</button></div></section></div>;
  if (!cfg) return <div className="geo geo-msg"><p className="tec-sub" role="status">Abriendo el geovisor…</p></div>;
  return <GeovisorMapa cfg={cfg} onVolver={onVolver} onReportarDano={onReportarDano} onRegistrarIntervencion={onRegistrarIntervencion} onRecargar={() => setVez((v) => v + 1)} />;
}

function GeovisorMapa({ cfg, onVolver, onReportarDano, onRegistrarIntervencion, onRecargar }: {
  cfg: ConfigGeovisor; onVolver: () => void; onReportarDano?: (a: ActivoTarjeta) => void; onRegistrarIntervencion?: (a: ActivoTarjeta) => void; onRecargar: () => void;
}) {
  const omision = useMemo(() => new Set(cfg.capas.filter((c) => c.encendida && c.fuente !== "preparada").map((c) => c.codigo)), [cfg]);
  const [on, setOn] = useState<Set<string>>(omision);
  const [colores, setColores] = useState<Colores>("tipo");
  const [periodo, setPeriodo] = useState<Periodo>({ modo: "hoy", desde: cfg.hoy, hasta: cfg.hoy });
  const [panel, setPanel] = useState<"" | "capas" | "omision">("");
  const [tarjeta, setTarjeta] = useState<Tarjeta | null>(null);
  const [ficha, setFicha] = useState<string[]>([]);
  const [zoom, setZoom] = useState(14);
  const [datos, setDatos] = useState<Record<string, CapaDatos | { error: string } | "cargando">>({});
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const token = useRef<string | null>(null);
  const [listo, setListo] = useState(false);
  const capasRef = useRef(cfg.capas);
  const onRef = useRef(on);
  onRef.current = on;
  const teselas = cfg.capas.filter((c) => c.fuente === "tesela");
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
        capas.push({ id: `t-${c.codigo}-a`, type: "fill", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "area"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis }, paint: { "fill-color": COLOR_SISTEMA.tecnologia, "fill-opacity": 0.08 } });
        capas.push({ id: `t-${c.codigo}-ab`, type: "line", source: "red", "source-layer": "activos", filter: ["all", f, ["==", ["get", "forma"], "area"]] as unknown as maplibregl.FilterSpecification,
                     layout: { visibility: vis }, paint: { "line-color": COLOR_SISTEMA.tecnologia, "line-width": 2, "line-opacity": 0.7 } });
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
          : c.codigo === "muestreo" ? ["case", ["==", ["get", "exactitud"], "verificada"], "#00897B", "rgba(255,255,255,0.85)"] : "#7B1FA2";
        capas.push({ id: `g-${c.codigo}`, type: "circle", source: `g-${c.codigo}`, layout: { visibility: vis },
                     paint: { "circle-radius": c.codigo === "muestreo" ? 7 : 6.5, "circle-color": color as unknown as string,
                              "circle-stroke-color": c.codigo === "muestreo" ? "#00897B" : "#FFFFFF", "circle-stroke-width": c.codigo === "muestreo" ? 2.5 : 2 } });
      }
      capas.push({ id: "sel", type: "circle", source: "sel", paint: { "circle-radius": 13, "circle-color": "rgba(0,0,0,0)", "circle-stroke-color": "#D6336C", "circle-stroke-width": 3.5 } });
      m = new maplibregl.Map({
        container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 14, maxZoom: 20, minZoom: 11, attributionControl: { compact: true },
        dragRotate: false, pitchWithRotate: false, touchPitch: false,
        transformRequest: (url) => (url.includes("accion=geovisor_tesela") && token.current ? { url, headers: { Authorization: `Bearer ${token.current}` } } : { url }),
        style: {
          version: 8,
          sources: {
            base: FUENTE_BASE_CALLES,
            red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=geovisor_tesela&z={z}&x={x}&y={y}&v=${cfg.version}`], minzoom: cfg.zoom.min, maxzoom: 18 },
            ...fuentesGeo,
            sel: { type: "geojson", data: VACIO },
          },
          layers: capas,
        },
      });
      mapa.current = m;
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome (no se usa en la app)
      m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
      m.on("zoomend", () => setZoom(m!.getZoom()));
      m.on("click", (ev) => {
        if (!m) return;
        const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[ev.point.x - 14, ev.point.y - 14], [ev.point.x + 14, ev.point.y + 14]];
        const orden = [...capasGeo.map((c) => `g-${c.codigo}`), ...capasTesela.map((c) => `t-${c.codigo}-p`), ...capasTesela.map((c) => `t-${c.codigo}-l`), ...capasTesela.map((c) => `t-${c.codigo}-a`)]
          .filter((id) => m!.getLayer(id) && m!.getLayoutProperty(id, "visibility") !== "none");
        const feats = m.queryRenderedFeatures(caja, { layers: orden });
        const f = orden.map((id) => feats.find((x) => x.layer.id === id)).find(Boolean);
        if (!f) { setTarjeta(null); return; }
        const id = f.layer.id;
        const capa = id.startsWith("g-") ? id.slice(2) : "activo";
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
    };
    if (m.getLayer("sel")) aplicar(); else m.once("styledata", aplicar);
  }, [on, listo]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- colores de los tramos ----------
  const materiales = useMemo(() => cfg.materiales.map((x, i) => ({ ...x, color: PALETA[i % PALETA.length] })), [cfg]);
  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo) return;
    const expr = colores === "material" ? ["match", ["get", "material"], ...materiales.flatMap((x) => [x.codigo, x.color]), SIN_DATO]
      : colores === "edad" ? ["case", ["!", ["has", "edad"]], SIN_DATO, ["step", ["get", "edad"], EDADES[0][1], EDADES[1][0], EDADES[1][1], EDADES[2][0], EDADES[2][1], EDADES[3][0], EDADES[3][1]]]
      : ["match", ["get", "sistema"], "alcantarillado", COLOR_SISTEMA.alcantarillado, "tecnologia", COLOR_SISTEMA.tecnologia, COLOR_SISTEMA.acueducto];
    const aplicar = () => { for (const c of teselas) if (m.getLayer(`t-${c.codigo}-l`)) m.setPaintProperty(`t-${c.codigo}-l`, "line-color", expr as unknown as string); };
    if (m.getLayer("sel")) aplicar(); else m.once("styledata", aplicar);
  }, [colores, listo]); // eslint-disable-line react-hooks/exhaustive-deps

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
        <button type="button" className="geo-boton" aria-expanded={panel === "capas"} onClick={() => setPanel((p) => (p === "capas" ? "" : "capas"))}>Capas</button>
      </header>

      <div className="geo-herr">
        <div className="geo-seg" role="group" aria-label="Colores de la red">
          {(["tipo", "material", "edad"] as Colores[]).map((k) => <button key={k} type="button" aria-pressed={colores === k} onClick={() => setColores(k)}>{k === "tipo" ? "Tipo" : k === "material" ? "Material" : "Edad"}</button>)}
        </div>
        {hayPorFecha ? <SelectorPeriodo cfg={cfg} periodo={periodo} onCambiar={setPeriodo} /> : null}
      </div>

      <div className="geo-cuerpo">
        <div ref={cont} className="geo-mapa" role="application" aria-label="Mapa del geovisor técnico" data-zoom={zoom.toFixed(1)} />
        {zoom < cfg.zoom.min ? <div className="geo-aviso" role="status">Acerque el mapa para ver la red</div>
          : zoom < cfg.zoom.red_completa ? <div className="geo-aviso geo-aviso-suave" role="status">Red principal · acerque para ver todos los tramos</div> : null}
        {avisos.length ? (
          <div className="geo-avisos" role="status">
            {avisos.map(({ c, d }) => <p key={c.codigo}>{d === "cargando" ? `Cargando ${c.nombre.toLowerCase()}…` : d && "error" in d ? `${c.nombre}: ${d.error}`
              : `${c.nombre}: se muestran los ${cfg.max_elementos} más recientes. Acorte el rango de fechas.`}</p>)}
          </div>) : null}
        {colores !== "tipo" ? <Leyenda colores={colores} materiales={materiales} /> : null}
        {tarjeta ? <TarjetaElemento t={tarjeta} cfg={cfg} onCerrar={() => setTarjeta(null)} onVerFicha={(c) => setFicha([c])}
          onReportarDano={onReportarDano} onRegistrarIntervencion={onRegistrarIntervencion} /> : null}

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
                  {cs.map((c) => <FilaCapa key={c.codigo} c={c} encendida={on.has(c.codigo)} onConmutar={() => conmutar(c.codigo)} />)}
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

function FilaCapa({ c, encendida, onConmutar }: { c: CapaGeovisor; encendida: boolean; onConmutar: () => void }) {
  const preparada = c.fuente === "preparada";
  return (
    <label className={`geo-capa${preparada ? " geo-capa-off" : ""}`} data-capa={c.codigo}>
      <input type="checkbox" checked={encendida && !preparada} disabled={preparada} onChange={onConmutar} />
      <span className="geo-capa-txt">
        <span className="geo-capa-nom">{c.nombre}{c.estado !== "activa" ? <span className="geo-est">{ESTADO_CAPA[c.estado]}</span> : null}</span>
        {c.nota ? <span className="geo-capa-nota">{c.nota}</span> : null}
      </span>
    </label>
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

function Leyenda({ colores, materiales }: { colores: Colores; materiales: { codigo: string; nombre: string; color: string }[] }) {
  const items = colores === "material" ? [...materiales.map((x) => [x.color, x.nombre]), [SIN_DATO, "Sin dato"]] : [...EDADES.map((e) => [e[1], e[2]]), [SIN_DATO, "Sin fecha de instalación"]];
  return (
    <div className="geo-leyenda" aria-label={colores === "material" ? "Colores por material" : "Colores por edad"}>
      <strong>{colores === "material" ? "Material" : "Edad"}</strong>
      <ul>{items.map(([c, n]) => <li key={n}><span style={{ background: c }} aria-hidden="true" />{n}</li>)}</ul>
    </div>
  );
}

function TarjetaElemento({ t, cfg, onCerrar, onVerFicha, onReportarDano, onRegistrarIntervencion }: {
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
    filas.push(["Edad", typeof p.edad === "number" ? `${p.edad} años` : "Sin fecha de instalación"]);
    filas.push(["Estado", cfg.estados?.[String(p.estado)] ?? texto(p.estado)]);
    activo = String(p.codigo);
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
    filas.push(["Zona", texto(p.zona)], ["Ubicación", p.exactitud === "verificada" ? "Verificada" : "Aproximada (por barrio)"]);
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
