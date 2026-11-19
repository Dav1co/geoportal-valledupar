import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES } from "../lib/mapaBase";

// Minimapa de unos pocos puntos con su código (19-nov): para ver juntos un activo por levantar y sus posibles repetidos (los que están a pocos metros) y decidir
// cuál se descarta. Sobre el mapa de calles, encuadrado en los puntos; se puede acercar y mover. Las marcas son de HTML (sin fuentes). Carga diferida.
export type PuntoRepetido = { codigo: string; lat: number; lon: number; principal?: boolean };

export function MiniMapaRepetidos({ puntos }: { puntos: PuntoRepetido[] }) {
  const cont = useRef<HTMLDivElement>(null);
  const clave = puntos.map((p) => `${p.codigo}:${p.lat}:${p.lon}`).join("|");
  useEffect(() => {
    if (!cont.current || !puntos.length) return;
    const m = new maplibregl.Map({ container: cont.current, center: [puntos[0].lon, puntos[0].lat], zoom: 19, minZoom: 14, maxZoom: 22, attributionControl: { compact: true }, dragRotate: false, pitchWithRotate: false, touchPitch: false,
      style: { version: 8, sources: { base: FUENTE_BASE_CALLES }, layers: [{ id: "base", type: "raster", source: "base" }] } });
    m.on("error", () => {});      // sin señal el mapa de calles puede fallar: las marcas se siguen viendo
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    const b = new maplibregl.LngLatBounds([puntos[0].lon, puntos[0].lat], [puntos[0].lon, puntos[0].lat]); for (const p of puntos) b.extend([p.lon, p.lat]);
    m.fitBounds(b, { padding: 90, maxZoom: 21.5, duration: 0 });
    // Las etiquetas no se montan: a cada una se le busca un lado libre (arriba, abajo, derecha, izquierda) según dónde quedaron los puntos tras encuadrar.
    const ANCHO = 100, ALTO = 28, SEP = 10;
    const caja = (x: number, y: number, lado: string) => lado === "bottom" ? [x - ANCHO / 2, y - SEP - ALTO, x + ANCHO / 2, y - SEP] : lado === "top" ? [x - ANCHO / 2, y + SEP, x + ANCHO / 2, y + SEP + ALTO]
      : lado === "left" ? [x + SEP, y - ALTO / 2, x + SEP + ANCHO, y + ALTO / 2] : [x - SEP - ANCHO, y - ALTO / 2, x - SEP, y + ALTO / 2];
    const choca = (p: number[], q: number[]) => p[0] < q[2] && q[0] < p[2] && p[1] < q[3] && q[1] < p[3];
    const puestas: number[][] = puntos.map((p) => { const q = m.project([p.lon, p.lat]); return [q.x - 7, q.y - 7, q.x + 7, q.y + 7]; });      // los puntos mismos también ocupan sitio
    for (const p of puntos) {
      const q = m.project([p.lon, p.lat]);
      const lado = (["bottom", "top", "left", "right"] as const).find((l) => !puestas.some((o) => choca(caja(q.x, q.y, l), o))) ?? "bottom";
      puestas.push(caja(q.x, q.y, lado));
      const e = document.createElement("span"); e.className = `lev-marca lev-marca-${lado}${p.principal ? " lev-marca-principal" : ""}`; e.dataset.punto = p.codigo; e.textContent = p.codigo;
      new maplibregl.Marker({ element: e, anchor: lado, offset: lado === "bottom" ? [0, -SEP] : lado === "top" ? [0, SEP] : lado === "left" ? [SEP, 0] : [-SEP, 0] }).setLngLat([p.lon, p.lat]).addTo(m);
      const c = document.createElement("span"); c.className = "lev-marca-centro"; c.setAttribute("aria-hidden", "true");
      new maplibregl.Marker({ element: c }).setLngLat([p.lon, p.lat]).addTo(m);
    }
    (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = m;      // para las pruebas en Chrome
    cont.current.setAttribute("data-listo", "si");
    return () => m.remove();
  }, [clave]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <figure className="lev-mapa" data-testid="lev-mapa">
      <div ref={cont} className="lev-mapa-lienzo" role="img" aria-label={`Mapa con ${puntos.map((p) => p.codigo).join(", ")}`} />
      <figcaption>Cada marca lleva su código. Acerque o mueva el mapa para compararlos.</figcaption>
    </figure>
  );
}
