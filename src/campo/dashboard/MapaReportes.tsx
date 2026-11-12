import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import type { FilaReporte, FormularioRev } from "./apiRevision";

// Mapa de reportes del supervisor (Paso C). MapLibre PROPIO: no importa ni monta nada comercial (ni MapView, ni teselas del geoportal, ni consultas a Edge comerciales).
// Mapa base: por omisión SIN calles (fondo liso, el rectángulo de la zona y los puntos); el botón «Mostrar calles» agrega la capa ráster de OpenStreetMap SOLO a pedido.
// Este archivo se carga bajo demanda (React.lazy) y es el único que descarga MapLibre.
// Símbolos: FORMA y COLOR por grupo (nunca solo color); riesgo inmediato = aro rojo grueso; fuera de zona = marca azul; ocultos = atenuados; posibles duplicados = halo morado
// común (un solo halo por punto; su tamaño crece con la cantidad). El grupo de duplicados es el que calcula el servidor: es distinto de cualquier agrupación visual.
export const PALETA = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#B8A800", "#222222"];
export const FORMAS = ["circulo", "cuadrado", "triangulo", "rombo", "cruz", "pentagono", "hexagono", "triangulo_inv"] as const;
export const FORMA_ROTULO: Record<(typeof FORMAS)[number], string> = { circulo: "círculo", cuadrado: "cuadrado", triangulo: "triángulo", rombo: "rombo", cruz: "cruz", pentagono: "pentágono", hexagono: "hexágono", triangulo_inv: "triángulo invertido" };

/** Índice estable de símbolo para un grupo: su posición en el catálogo (máximo 8 formas distintas; más grupos repiten forma con otro color). */
export const indiceGrupo = (grupos: { codigo: string }[], codigo: string): number => { const i = grupos.findIndex((g) => g.codigo === codigo); return i < 0 ? 7 : i % 8; };

function trazar(ctx: CanvasRenderingContext2D, forma: (typeof FORMAS)[number], cx: number, cy: number, r: number) {
  ctx.beginPath();
  const poli = (n: number, rot: number) => { for (let i = 0; i < n; i++) { const a = rot + (i * 2 * Math.PI) / n; const x = cx + r * Math.cos(a), y = cy + r * Math.sin(a); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } ctx.closePath(); };
  switch (forma) {
    case "circulo": ctx.arc(cx, cy, r, 0, Math.PI * 2); break;
    case "cuadrado": ctx.rect(cx - r * 0.85, cy - r * 0.85, r * 1.7, r * 1.7); break;
    case "triangulo": poli(3, -Math.PI / 2); break;
    case "triangulo_inv": poli(3, Math.PI / 2); break;
    case "rombo": poli(4, 0); break;
    case "pentagono": poli(5, -Math.PI / 2); break;
    case "hexagono": poli(6, 0); break;
    case "cruz": { const t = r * 0.38; ctx.moveTo(cx - t, cy - r); ctx.lineTo(cx + t, cy - r); ctx.lineTo(cx + t, cy - t); ctx.lineTo(cx + r, cy - t); ctx.lineTo(cx + r, cy + t); ctx.lineTo(cx + t, cy + t); ctx.lineTo(cx + t, cy + r); ctx.lineTo(cx - t, cy + r); ctx.lineTo(cx - t, cy + t); ctx.lineTo(cx - r, cy + t); ctx.lineTo(cx - r, cy - t); ctx.lineTo(cx - t, cy - t); ctx.closePath(); break; }
  }
}
function icono(forma: (typeof FORMAS)[number], color: string): ImageData {
  const T = 40; const c = document.createElement("canvas"); c.width = T; c.height = T; const ctx = c.getContext("2d") as CanvasRenderingContext2D;
  trazar(ctx, forma, T / 2, T / 2, 15); ctx.fillStyle = color; ctx.fill(); ctx.lineWidth = 3; ctx.strokeStyle = "#ffffff"; ctx.stroke();
  return ctx.getImageData(0, 0, T, T);
}
function iconoFuera(): ImageData {
  const T = 24; const c = document.createElement("canvas"); c.width = T; c.height = T; const ctx = c.getContext("2d") as CanvasRenderingContext2D;
  ctx.fillStyle = "#1d4ed8"; ctx.fillRect(2, 2, T - 4, T - 4); ctx.strokeStyle = "#fff"; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(7, 7); ctx.lineTo(17, 17); ctx.moveTo(17, 7); ctx.lineTo(7, 17); ctx.stroke();
  return ctx.getImageData(0, 0, T, T);
}

export type PropsMapa = {
  filas: FilaReporte[]; def: FormularioRev; ajusteN: number; seleccionada: string | null; onSeleccion: (id: string) => void; onGrupo: (grupo: string | null) => void;
};
export default function MapaReportes({ filas, def, ajusteN, seleccionada, onSeleccion, onGrupo }: PropsMapa) {
  const cont = useRef<HTMLDivElement>(null); const mapa = useRef<maplibregl.Map | null>(null); const listo = useRef(false);
  const [calles, setCalles] = useState(false); const [fallo, setFallo] = useState<string | null>(null); const [leyenda, setLeyenda] = useState(true);
  const cbSel = useRef(onSeleccion); const cbGrupo = useRef(onGrupo); cbSel.current = onSeleccion; cbGrupo.current = onGrupo;

  const datos = useMemo(() => ({
    type: "FeatureCollection" as const,
    features: filas.filter((f) => Number.isFinite(f.lat) && Number.isFinite(f.lon)).map((f) => ({
      type: "Feature" as const, geometry: { type: "Point" as const, coordinates: [f.lon, f.lat] },
      properties: { id: f.id, g: indiceGrupo(def.grupos, f.grupo.codigo), riesgo: f.riesgo_inmediato ? 1 : 0, fuera: f.fuera_de_zona ? 1 : 0, oculto: f.oculto ? 1 : 0, dup: f.grupo_duplicados ? (f.tamano_grupo ?? 2) : 0, grupo: f.grupo_duplicados ?? "", sel: f.id === seleccionada ? 1 : 0 },
    })),
  }), [filas, def.grupos, seleccionada]);
  const datosRef = useRef(datos); datosRef.current = datos;
  const zonaGeo = useMemo(() => { const z = def.zona; return { type: "Feature" as const, properties: {}, geometry: { type: "LineString" as const, coordinates: [[z.lon_min, z.lat_min], [z.lon_max, z.lat_min], [z.lon_max, z.lat_max], [z.lon_min, z.lat_max], [z.lon_min, z.lat_min]] } }; }, [def.zona]);

  useEffect(() => {
    if (!cont.current || mapa.current) return;
    let m: maplibregl.Map;
    try {
      m = new maplibregl.Map({
        container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 11, attributionControl: { compact: true },
        // Sin glyphs ni teselas: no hay ninguna petición de red hasta que se pida «Mostrar calles». Nada comercial.
        style: { version: 8, sources: {}, layers: [{ id: "fondo", type: "background", paint: { "background-color": "#eef2f5" } }] },
      });
    } catch { setFallo("Este navegador no puede mostrar el mapa. Use la tabla."); return; }
    mapa.current = m;
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    m.on("load", () => {
      FORMAS.forEach((f, i) => m.addImage(`g${i}`, icono(f, PALETA[i]), { pixelRatio: 2 }));
      m.addImage("fuera", iconoFuera(), { pixelRatio: 2 });
      m.addSource("zona", { type: "geojson", data: zonaGeo });
      m.addSource("reportes", { type: "geojson", data: datosRef.current });
      m.addLayer({ id: "zona-linea", type: "line", source: "zona", paint: { "line-color": "#52626f", "line-width": 1.5, "line-dasharray": [3, 2] } });
      m.addLayer({ id: "dup-halo", type: "circle", source: "reportes", filter: [">", ["get", "dup"], 0],
        paint: { "circle-radius": ["interpolate", ["linear"], ["get", "dup"], 2, 15, 10, 26], "circle-color": "#7e22ce", "circle-opacity": 0.18, "circle-stroke-color": "#7e22ce", "circle-stroke-width": 2 } });
      m.addLayer({ id: "riesgo-aro", type: "circle", source: "reportes", filter: ["==", ["get", "riesgo"], 1],
        paint: { "circle-radius": 12, "circle-color": "#ffffff", "circle-opacity": 0, "circle-stroke-color": "#b91c1c", "circle-stroke-width": 3.5, "circle-stroke-opacity": ["case", ["==", ["get", "oculto"], 1], 0.45, 1] } });
      m.addLayer({ id: "sel-aro", type: "circle", source: "reportes", filter: ["==", ["get", "sel"], 1], paint: { "circle-radius": 17, "circle-color": "#ffffff", "circle-opacity": 0, "circle-stroke-color": "#111827", "circle-stroke-width": 2.5 } });
      m.addLayer({ id: "puntos", type: "symbol", source: "reportes", layout: { "icon-image": ["concat", "g", ["get", "g"]], "icon-size": 0.5, "icon-allow-overlap": true, "icon-ignore-placement": true },
        paint: { "icon-opacity": ["case", ["==", ["get", "oculto"], 1], 0.35, 1] } });
      m.addLayer({ id: "fuera-marca", type: "symbol", source: "reportes", filter: ["==", ["get", "fuera"], 1], layout: { "icon-image": "fuera", "icon-size": 0.5, "icon-offset": [14, -14], "icon-allow-overlap": true, "icon-ignore-placement": true } });
      m.on("click", "puntos", (e) => { const p = e.features?.[0]?.properties as { id?: string; grupo?: string } | undefined; if (p?.id) { cbSel.current(p.id); cbGrupo.current(p.grupo ? p.grupo : null); } });
      m.on("mouseenter", "puntos", () => { m.getCanvas().style.cursor = "pointer"; }); m.on("mouseleave", "puntos", () => { m.getCanvas().style.cursor = ""; });
      listo.current = true; ajustar(m, datosRef.current, def.zona);
    });
    return () => { listo.current = false; m.remove(); mapa.current = null; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => { const m = mapa.current; if (m && listo.current) (m.getSource("reportes") as maplibregl.GeoJSONSource | undefined)?.setData(datos); }, [datos]);
  useEffect(() => { const m = mapa.current; if (m && listo.current) ajustar(m, datosRef.current, def.zona); }, [ajusteN, def.zona]);
  useEffect(() => {
    const m = mapa.current; if (!m) return;
    const aplicar = () => {
      if (calles && !m.getSource("osm")) { m.addSource("osm", FUENTE_BASE_CALLES); m.addLayer({ id: "osm", type: "raster", source: "osm", paint: { "raster-opacity": 0.85 } }, "zona-linea"); }
      if (!calles && m.getLayer("osm")) { m.removeLayer("osm"); m.removeSource("osm"); }
    };
    if (listo.current) aplicar(); else m.once("load", aplicar);
  }, [calles]);

  if (fallo) return <div className="rv-aviso rv-aviso-error" role="alert">{fallo}</div>;
  return (
    <div className="rv-mapa-caja">
      <div ref={cont} className="rv-mapa" role="application" aria-label="Mapa de reportes" />
      <div className="rv-mapa-ctl">
        <button type="button" className="rv-boton-sec rv-corto" aria-pressed={calles} onClick={() => setCalles((x) => !x)}>{calles ? "Ocultar calles" : "Mostrar calles"}</button>
        <button type="button" className="rv-boton-sec rv-corto" aria-expanded={leyenda} onClick={() => setLeyenda((x) => !x)}>Leyenda {leyenda ? "▲" : "▼"}</button>
      </div>
      {leyenda ? <Leyenda def={def} /> : null}
    </div>
  );
}

function ajustar(m: maplibregl.Map, datos: { features: { geometry: { coordinates: number[] } }[] }, z: FormularioRev["zona"]) {
  const pts = datos.features.map((f) => f.geometry.coordinates);
  const b = new maplibregl.LngLatBounds();
  if (pts.length) pts.forEach((p) => b.extend(p as [number, number])); else { b.extend([z.lon_min, z.lat_min]); b.extend([z.lon_max, z.lat_max]); }
  m.fitBounds(b, { padding: 48, maxZoom: pts.length ? 17 : 12, duration: 0 });
}

function Leyenda({ def }: { def: FormularioRev }) {
  const grupos = def.grupos.slice(0, 8);
  return (
    <div className="rv-leyenda" aria-label="Leyenda del mapa">
      <strong>Grupo (forma y color)</strong>
      <ul>
        {grupos.map((g, i) => (
          <li key={g.codigo}><svg width="18" height="18" viewBox="0 0 40 40" aria-hidden="true"><Forma forma={FORMAS[i % 8]} color={PALETA[i % 8]} /></svg> {g.nombre}<span className="rv-tenue"> · {FORMA_ROTULO[FORMAS[i % 8]]}</span></li>
        ))}
      </ul>
      <ul>
        <li><svg width="18" height="18" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="14" fill="none" stroke="#b91c1c" strokeWidth="5" /></svg> Riesgo inmediato (aro rojo)</li>
        <li><svg width="18" height="18" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="16" fill="#7e22ce" fillOpacity=".18" stroke="#7e22ce" strokeWidth="3" /></svg> Posibles duplicados (halo morado: crece con la cantidad)</li>
        <li><svg width="18" height="18" viewBox="0 0 40 40" aria-hidden="true"><rect x="4" y="4" width="32" height="32" fill="#1d4ed8" /><path d="M12 12l16 16M28 12L12 28" stroke="#fff" strokeWidth="4" /></svg> Fuera de zona</li>
        <li><svg width="18" height="18" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="14" fill="#0072B2" fillOpacity=".35" /></svg> Oculto (atenuado)</li>
        <li><span className="rv-tenue">Rectángulo punteado: zona de operación</span></li>
        {/* La atribución de OpenStreetMap la muestra el propio mapa al activar las calles */}
      </ul>
    </div>
  );
}
function Forma({ forma, color }: { forma: (typeof FORMAS)[number]; color: string }) {
  const poli = (n: number, rot: number) => Array.from({ length: n }, (_, i) => { const a = rot + (i * 2 * Math.PI) / n; return `${20 + 15 * Math.cos(a)},${20 + 15 * Math.sin(a)}`; }).join(" ");
  const p = { fill: color, stroke: "#fff", strokeWidth: 2 };
  switch (forma) {
    case "circulo": return <circle cx="20" cy="20" r="15" {...p} />;
    case "cuadrado": return <rect x="7" y="7" width="26" height="26" {...p} />;
    case "triangulo": return <polygon points={poli(3, -Math.PI / 2)} {...p} />;
    case "triangulo_inv": return <polygon points={poli(3, Math.PI / 2)} {...p} />;
    case "rombo": return <polygon points={poli(4, 0)} {...p} />;
    case "pentagono": return <polygon points={poli(5, -Math.PI / 2)} {...p} />;
    case "hexagono": return <polygon points={poli(6, 0)} {...p} />;
    default: return <path d="M14 5h12v9h9v12h-9v9H14v-9H5V14h9z" {...p} />;
  }
}
