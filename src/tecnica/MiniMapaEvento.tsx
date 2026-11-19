import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES } from "../lib/mapaBase";
import type { ZonaGeo } from "./apiEventos";
import { BORDE_EVENTO_PX, cajaDeZona, circuloGeo, COLOR_EVENTO, metrosEntrePuntos, puntoA, RELLENO_EVENTO } from "./mapaEvento";

// Minimapa del Corte 15 («Evento de suspensión»). Dos usos:
// · mostrar la zona de un evento o de la vista previa (los sectores escogidos, el círculo o lo que surte una planta), encuadrada;
// · DIBUJAR EL CÍRCULO: se toca el mapa para poner el centro y se arrastra la manija del borde para ajustar el radio (también se puede escribir el radio).
// Sin la red encima: es de referencia sobre el mapa de calles. Carga diferida (MapLibre solo entra al abrir esta pantalla).
const CENTRO_VALLEDUPAR: [number, number] = [-73.2532, 10.4631];
const VACIO = { type: "FeatureCollection" as const, features: [] };
type Circulo = { lat: number; lon: number; radio_m: number };

export function MiniMapaEvento({ zona, circulo, limites, onCirculo, centro }: {
  zona?: ZonaGeo; circulo?: Circulo | null; limites?: { min: number; max: number };
  /** Si viene, el círculo se puede poner y ajustar en el mapa. */
  onCirculo?: (c: Circulo) => void; centro?: { lat: number; lon: number } | null;
}) {
  const cont = useRef<HTMLDivElement>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const manija = useRef<maplibregl.Marker | null>(null);
  const listo = useRef(false);
  const circRef = useRef<Circulo | null>(circulo ?? null); circRef.current = circulo ?? null;
  const alCambiar = useRef(onCirculo); alCambiar.current = onCirculo;
  const lim = useRef(limites); lim.current = limites;
  const editable = !!onCirculo;

  const pintarCirculo = (c: Circulo | null) => {
    const m = mapa.current; if (!m || !listo.current) return;
    (m.getSource("circulo") as maplibregl.GeoJSONSource | undefined)?.setData(c ? { type: "Feature", properties: {}, geometry: circuloGeo(c, c.radio_m) } : VACIO);
    (m.getSource("centro") as maplibregl.GeoJSONSource | undefined)?.setData(c ? { type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [c.lon, c.lat] } } : VACIO);
  };
  const encuadrar = (caja: [number, number, number, number] | null) => { if (caja) mapa.current?.fitBounds([[caja[0], caja[1]], [caja[2], caja[3]]], { padding: 32, maxZoom: 17, duration: 0 }); };

  useEffect(() => {
    if (!cont.current) return;
    const ini = circRef.current ?? centro ?? null;
    const m = new maplibregl.Map({
      container: cont.current, center: ini ? [ini.lon, ini.lat] : CENTRO_VALLEDUPAR, zoom: ini ? 15 : 12.5, minZoom: 10, maxZoom: 19, attributionControl: { compact: true }, dragRotate: false, pitchWithRotate: false, touchPitch: false,
      style: { version: 8, sources: { base: FUENTE_BASE_CALLES, zona: { type: "geojson", data: VACIO }, circulo: { type: "geojson", data: VACIO }, centro: { type: "geojson", data: VACIO } },
        layers: [
          { id: "base", type: "raster", source: "base" },
          { id: "zona-a", type: "fill", source: "zona", paint: { "fill-color": COLOR_EVENTO, "fill-opacity": RELLENO_EVENTO } },
          { id: "zona-l", type: "line", source: "zona", paint: { "line-color": COLOR_EVENTO, "line-width": BORDE_EVENTO_PX } },
          { id: "circulo-a", type: "fill", source: "circulo", paint: { "fill-color": COLOR_EVENTO, "fill-opacity": RELLENO_EVENTO } },
          { id: "circulo-l", type: "line", source: "circulo", paint: { "line-color": COLOR_EVENTO, "line-width": BORDE_EVENTO_PX } },
          { id: "centro-p", type: "circle", source: "centro", paint: { "circle-radius": 5, "circle-color": COLOR_EVENTO, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2 } },
        ] },
    });
    mapa.current = m;
    m.on("error", () => {});      // sin señal, el mapa de calles puede fallar: la zona se sigue viendo
    (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome
    m.once("style.load", () => {      // «style.load» y no «load»: sin señal el mapa de calles no termina de cargar y la zona igual debe pintarse
      listo.current = true;
      (m.getSource("zona") as maplibregl.GeoJSONSource).setData(zonaRef.current ? { type: "Feature", properties: {}, geometry: zonaRef.current as GeoJSON.Geometry } : VACIO);
      pintarCirculo(circRef.current); ponerManija(circRef.current);
      const c = circRef.current;
      encuadrar(c ? cajaDeZona(circuloGeo(c, c.radio_m)) : cajaDeZona(zonaRef.current));
      cont.current?.setAttribute("data-listo", "si");
    });
    if (editable) m.on("click", (e) => {      // tocar el mapa pone (o mueve) el centro; el radio se conserva
      const r = circRef.current?.radio_m ?? 200;
      alCambiar.current?.({ lat: e.lngLat.lat, lon: e.lngLat.lng, radio_m: r });
    });
    return () => { listo.current = false; manija.current?.remove(); manija.current = null; m.remove(); mapa.current = null; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // La manija del borde (al este del centro): arrastrarla cambia el radio. Mientras se arrastra el círculo se redibuja; al soltar se avisa.
  const ponerManija = (c: Circulo | null) => {
    const m = mapa.current; if (!m || !editable) return;
    if (!c) { manija.current?.remove(); manija.current = null; return; }
    const borde = puntoA(c, c.radio_m, 90);
    if (!manija.current) {
      const e = document.createElement("button"); e.type = "button"; e.className = "evs-manija"; e.setAttribute("aria-label", "Arrastre para cambiar el radio del círculo"); e.dataset.testid = "evs-manija";
      const mk = new maplibregl.Marker({ element: e, draggable: true }).setLngLat([borde.lon, borde.lat]).addTo(m);
      const radioDe = () => { const p = mk.getLngLat(), k = circRef.current; if (!k) return null;
        const r = metrosEntrePuntos(k, { lat: p.lat, lon: p.lng }), l = lim.current; return Math.round(Math.max(l?.min ?? 20, Math.min(l?.max ?? 5000, r))); };
      mk.on("drag", () => { const r = radioDe(), k = circRef.current; if (r && k) pintarCirculo({ ...k, radio_m: r }); });
      mk.on("dragend", () => { const r = radioDe(), k = circRef.current; if (r && k) alCambiar.current?.({ ...k, radio_m: r }); });
      manija.current = mk;
    } else manija.current.setLngLat([borde.lon, borde.lat]);
  };

  const zonaRef = useRef<ZonaGeo | undefined>(zona); zonaRef.current = zona;
  const claveZona = zona ? JSON.stringify(cajaDeZona(zona)) + String((zona.coordinates as unknown[] | undefined)?.length ?? 0) : "";
  useEffect(() => {
    const m = mapa.current; if (!m || !listo.current) return;
    (m.getSource("zona") as maplibregl.GeoJSONSource | undefined)?.setData(zona ? { type: "Feature", properties: {}, geometry: zona as GeoJSON.Geometry } : VACIO);
    if (!circRef.current) encuadrar(cajaDeZona(zona));
  }, [claveZona]); // eslint-disable-line react-hooks/exhaustive-deps

  const claveCirc = circulo ? `${circulo.lat.toFixed(6)},${circulo.lon.toFixed(6)},${Math.round(circulo.radio_m)}` : "";
  const radioPrevio = useRef<number | null>(circulo?.radio_m ?? null);
  useEffect(() => {
    pintarCirculo(circulo ?? null); ponerManija(circulo ?? null);
    // se encuadra cuando el círculo aparece o cuando cambia mucho de tamaño (no en cada toque, para no mover el mapa bajo el dedo)
    if (circulo && (radioPrevio.current === null || circulo.radio_m > radioPrevio.current * 1.6 || circulo.radio_m < radioPrevio.current / 1.6)) encuadrar(cajaDeZona(circuloGeo(circulo, circulo.radio_m)));
    radioPrevio.current = circulo?.radio_m ?? null;
  }, [claveCirc]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <figure className="evs-mapa" data-testid="evs-mapa">
      <div ref={cont} className="evs-mapa-lienzo" role={editable ? "application" : "img"}
        aria-label={editable ? "Mapa para poner el círculo: toque el centro y arrastre la manija del borde para ajustar el radio" : "Mapa con la zona del evento"} />
      {editable ? <figcaption>Toque el mapa para poner el centro. Arrastre el punto del borde para ajustar el radio.</figcaption> : null}
    </figure>
  );
}
