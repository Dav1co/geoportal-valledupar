import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES } from "../lib/mapaBase";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import { apiGestion, type NodoPreliminar as Preliminar } from "./apiRedes";

// Ficha PRELIMINAR de un nodo «por clasificar» (Técnica fase 1, Corte 9a; pedido de David del 16-nov, 13:50). Solo lectura: sirve para decidir qué es el nodo
// antes de crear un activo. Muestra dónde está (minimapa con el punto y los tramos que le llegan), cuántos tramos conecta, su cota, su sector según el Plan y lo
// que dice el modelo hidráulico (tipo, demanda y presión DE MODELO, no medida), con una SUGERENCIA de clasificación. Nada se clasifica solo: la confirma quien decide.

const SEL = "#D6336C";
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 2 });
const num = (v: number | undefined, u: string) => (v === undefined || v === null ? null : `${nf.format(v)} ${u}`);

function MiniMapaNodo({ p }: { p: Preliminar }) {
  const cont = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let vivo = true; let m: maplibregl.Map | null = null; let token: string | null = null;
    void supabase.auth.getSession().then(({ data }) => {
      if (!vivo || !cont.current) return;
      token = data.session?.access_token ?? null;
      const tramos: GeoJSON.FeatureCollection = { type: "FeatureCollection", features: p.tramos.map((t) => ({ type: "Feature", properties: { codigo: t.codigo }, geometry: t.linea })) };
      m = new maplibregl.Map({
        container: cont.current, center: [p.lon, p.lat], zoom: 17, maxZoom: 20, minZoom: 13, attributionControl: { compact: true }, dragRotate: false, pitchWithRotate: false, touchPitch: false,
        transformRequest: (url) => (url.includes("accion=tesela") && token ? { url, headers: { Authorization: `Bearer ${token}` } } : { url }),
        style: {
          version: 8,
          sources: { base: FUENTE_BASE_CALLES,
            red: { type: "vector", tiles: [`${FUNCTIONS_URL}/geoportal-redes?accion=tesela&sistema=${p.sistema}&z={z}&x={x}&y={y}&v=1`], minzoom: 15, maxzoom: 18 },
            tramos: { type: "geojson", data: tramos },
            nodo: { type: "geojson", data: { type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [p.lon, p.lat] } } } },
          layers: [
            { id: "base", type: "raster", source: "base" },
            { id: "red", type: "line", source: "red", "source-layer": "red", filter: ["==", ["get", "forma"], "tramo"], paint: { "line-color": "#1F5FA8", "line-width": 2.5, "line-opacity": 0.55 } },
            { id: "tramos", type: "line", source: "tramos", layout: { "line-cap": "round" }, paint: { "line-color": "#0A2540", "line-width": 6 } },
            { id: "nodo", type: "circle", source: "nodo", paint: { "circle-radius": 9, "circle-color": "#FFFFFF", "circle-stroke-color": SEL, "circle-stroke-width": 4 } },
          ],
        },
      });
      m.on("error", () => {});      // sin señal, la base o una tesela pueden fallar: el minimapa es de referencia
      m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
      (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome
    });
    return () => { vivo = false; m?.remove(); };
  }, [p]);
  return <div ref={cont} className="red-minimapa-mapa nodo-pre-mapa" role="img" aria-label={`Ubicación del nodo ${p.nombre_visible} y de los ${p.tramos.length} tramos que le llegan`} />;
}

export function NodoPreliminar({ nodoId, onCerrar }: { nodoId: number; onCerrar: () => void }) {
  const [p, setP] = useState<Preliminar | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    setP(null); setError(null);
    apiGestion.nodoPreliminar(nodoId).then((r) => { if (vivo) setP(r); }).catch((e) => { if (vivo) setError(e instanceof Error ? e.message : "No se pudo cargar la ficha preliminar."); });
    return () => { vivo = false; };
  }, [nodoId]);
  if (error) return <div className="nodo-pre" role="alert"><p className="tec-aviso tec-aviso-error">{error}</p><button type="button" className="tec-boton-sec" onClick={onCerrar}>Cerrar</button></div>;
  if (!p) return <p className="tec-sub" role="status">Cargando la ficha preliminar…</p>;
  const m = p.modelo;
  const filas: [string, string | null][] = [
    ["Tramos que conecta", String(p.tramos.length)],
    ["Sector hidráulico", p.sector ? `${p.sector.sector}${p.sector.subsector ? ` · subsector ${p.sector.subsector}` : ""}` : "Fuera de los sectores"],
    ["Cota", num(m?.cota_m, "m")], ["Ubicación", `${p.lat}, ${p.lon}`],
  ];
  const modelo: [string, string | null][] = m ? [
    ["Tipo en el modelo", m.tipo ?? null], ["Qué es", m.que_es && m.que_es !== "otro" ? m.que_es : null], ["Zona del modelo", m.zona ?? null], ["Nota del modelo", m.nota ?? null],
    ["Demanda (red existente)", num(m.demanda_exist_lps, "L/s")], ["Demanda (red futura del Plan)", num(m.demanda_futura_lps, "L/s")],
    ["Presión de modelo, red existente (mediana)", num(m.pres_exist_mediana, "m.c.a.")], ["Presión de modelo, red futura (mediana)", num(m.pres_futura_mediana, "m.c.a.")],
  ] : [];
  return (
    <div className="nodo-pre" aria-label={`Ficha preliminar del nodo ${p.nombre_visible}`}>
      <div className="red-tit-fila"><h3>Ficha preliminar · solo lectura</h3><button type="button" className="tec-enlace" onClick={onCerrar}>Cerrar</button></div>
      <MiniMapaNodo p={p} />
      {p.sugerencia ? <p className={`nodo-sug nodo-sug-${p.sugerencia.accion}`} role="note"><strong>Sugerencia del modelo:</strong> {p.sugerencia.texto}. <span>La confirma usted: nada se clasifica solo.</span></p>
        : <p className="nodo-sug nodo-sug-revisar" role="note">El modelo cargado no trae datos de este nodo: sin sugerencia.</p>}
      <div className="red-rejilla">{filas.filter(([, v]) => v !== null).map(([k, v]) => <div key={k} className="red-dato"><span className="red-dato-rot">{k}</span><span className="red-dato-val">{v}</span></div>)}</div>
      {modelo.some(([, v]) => v !== null) ? (
        <>
          <h4>Lo que dice el modelo (Plan Maestro 2014)</h4>
          <div className="red-rejilla">{modelo.filter(([, v]) => v !== null).map(([k, v]) => <div key={k} className="red-dato"><span className="red-dato-rot">{k}</span><span className="red-dato-val">{v}</span></div>)}</div>
          {m?.pres_exist_mediana !== undefined || m?.pres_futura_mediana !== undefined ? <p className="red-nota">La presión es de modelo, no medida.</p> : null}
        </>) : null}
      <h4>Tramos que llegan al nodo</h4>
      {p.tramos.length ? (
        <ul className="nodo-pre-tramos">{p.tramos.map((t) => (
          <li key={t.codigo}><strong>{t.codigo}</strong>{t.nombre ? ` · ${t.nombre}` : ""} · {t.material ?? "material sin dato"} · {t.diametro_mm ? `${nf.format(t.diametro_mm)} mm` : "diámetro sin dato"}
            {t.longitud_m ? ` · ${nf.format(t.longitud_m)} m` : ""} · {t.estado}</li>))}</ul>
      ) : <p className="red-nota">Ningún tramo vigente llega a este nodo.</p>}
    </div>
  );
}
