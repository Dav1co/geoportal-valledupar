// Geovisor técnico · Corte 1 (26-nov): «Imprimir / PDF» tipo ArcGIS. SIEMPRE 2 páginas, en este orden: 1) Total y 2) Urbano, carta vertical, con las capas
// encendidas en ese momento. Cada página se dibuja en un mapa OCULTO con la extensión y el zoom fijos de config.ts (la tesela de la red: completa desde z14,
// nodos desde z15) y luego se compone en un lienzo: marco con coordenadas en grados, cajetín (logo, título según la temática, lugar, fecha y hora, usuario,
// sistema de referencia y fuente), norte, escala gráfica y numérica calculadas para la hoja, leyenda SOLO de la temática activa (y los sectores aparte si
// están encendidos) y, en la Urbana, un mapa de ubicación pequeño. Si la foto satelital no se puede exportar, se rehace con calles y se avisa.
// Componente reutilizable: los Cuadernos (Corte 2) le pasarán sus marcas como capas del mismo mapa y su propia leyenda.
// Sin datos personales: no lleva tarjetas ni datos de contratos; solo lo que se ve en el mapa.
import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import { supabase } from "../../lib/supabase";
import { pdfDeImagenes, HOJA_CARTA } from "../../lib/pdfMapa";
import { MARGEN_EXTENSION, PAGINAS, TEXTOS_IMPRESION, type Extension, type PaginaImpresion } from "./config";
import logoUrl from "../membrete_logo.png";

export type ItemImpresion = { color: string; texto: string; forma: "linea" | "punto" | "area" };
export type LeyendaImpresion = { tematica: { titulo: string; items: ItemImpresion[]; notas?: string[]; notaSinInstalacion?: string }; sectores: { color: string; texto: string }[]; subsectores: boolean };
/** Lo que queda de cada página para las pruebas (no se usa en la app). */
export type MedidaPagina = { clave: string; zoom: number; extension: Extension; vista: Extension; metrosPorPunto: number; escala: number; fondo: "calles" | "satelite"; mapaPx: [number, number]; notas: string[] };

const DPI = 200, K = DPI / 72;                                 // píxeles del lienzo por punto de la hoja
const M = { izq: 40, der: 40, arriba: 34, abajo: 24, cajetin: 120, sep: 14 };   // márgenes (pt)
const MARCO = { x: M.izq, y: M.arriba, w: HOJA_CARTA.ancho - M.izq - M.der, h: HOJA_CARTA.alto - M.arriba - M.abajo - M.cajetin - M.sep };
const R_TIERRA = 6378137;

/** Los tramos de red que se ven en el mapa y cuántos tienen fecha de instalación (en la tesela: «edad» sin «edad_reg»). Para la nota de la temática «Edad». */
export function tramosConInstalacion(m: maplibregl.Map): { tramos: number; conInstalacion: number } {
  const capas = (m.getStyle().layers ?? []).filter((l) => /^t-.*-l$/.test(l.id) && (l.layout as { visibility?: string } | undefined)?.visibility !== "none").map((l) => l.id);
  if (!capas.length) return { tramos: 0, conInstalacion: 0 };
  const fs = m.queryRenderedFeatures({ layers: capas });
  return { tramos: fs.length, conInstalacion: fs.filter((f) => typeof f.properties?.edad === "number" && !f.properties?.edad_reg).length };
}
const FUENTE = "Helvetica, Arial, sans-serif";

const conMargen = (e: Extension): Extension => {
  const dx = (e.este - e.oeste) * MARGEN_EXTENSION, dy = (e.norte - e.sur) * MARGEN_EXTENSION;
  return { oeste: e.oeste - dx, sur: e.sur - dy, este: e.este + dx, norte: e.norte + dy };
};
const mercY = (lat: number) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) * R_TIERRA;
const mercX = (lon: number) => (lon * Math.PI / 180) * R_TIERRA;
/** Metros de terreno por píxel de mapa a ese zoom y latitud (teselas de 512: el «zoom» de MapLibre). */
const mppZoom = (z: number, lat: number) => (2 * Math.PI * R_TIERRA * Math.cos((lat * Math.PI) / 180)) / (512 * 2 ** z);
const bonito = (n: number) => { const p = 10 ** Math.floor(Math.log10(n)); const f = n / p; return (f < 1.5 ? 1 : f < 3.5 ? 2 : f < 7.5 ? 5 : 10) * p; };
const miles = (n: number) => new Intl.NumberFormat("es-CO", { maximumFractionDigits: 0 }).format(n);
const grados = (v: number, eje: "lon" | "lat") => `${Math.abs(v).toFixed(2).replace(".", ",")}° ${eje === "lon" ? (v < 0 ? "O" : "E") : v < 0 ? "S" : "N"}`;
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

function cargarImagen(src: string): Promise<HTMLImageElement> {
  return new Promise((ok, mal) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => mal(new Error("imagen")); i.src = src; });
}

/** Dibuja el mapa de una página en un contenedor oculto y devuelve el lienzo del mapa y cómo proyectar sobre él. */
async function dibujarMapa(estilo: maplibregl.StyleSpecification, pag: PaginaImpresion, fondo: "calles" | "satelite", subsectores: boolean, token: string | null,
  aspecto: number): Promise<{ lienzo: HTMLCanvasElement; proyectar: (lon: number, lat: number) => [number, number]; ancho: number; alto: number; mpp: number; vista: Extension; fallo: boolean; sinInstalacion: boolean }> {
  const e = conMargen(pag.extension);
  const latC = (e.sur + e.norte) / 2, lonC = (e.oeste + e.este) / 2;
  const mpp = mppZoom(pag.zoom, latC);
  // el mapa cubre TODA la extensión (con margen) y tiene la proporción del marco: lo que sobra se ve a los lados o arriba y abajo
  const wM = (mercX(e.este) - mercX(e.oeste)) * Math.cos((latC * Math.PI) / 180), hM = (mercY(e.norte) - mercY(e.sur)) * Math.cos((latC * Math.PI) / 180);
  let alto = Math.ceil(hM / mpp), ancho = Math.ceil(alto * aspecto);
  if (ancho < wM / mpp) { ancho = Math.ceil(wM / mpp); alto = Math.ceil(ancho / aspecto); }
  const cont = document.createElement("div");
  cont.className = "geo-imprimir-oculto"; cont.style.width = `${ancho}px`; cont.style.height = `${alto}px`;
  document.body.appendChild(cont);
  const s: maplibregl.StyleSpecification = JSON.parse(JSON.stringify(estilo));
  for (const l of s.layers) {
    if (l.id === "base") (l.layout ??= {} as never, (l.layout as Record<string, unknown>).visibility = fondo === "calles" ? "visible" : "none");
    if (l.id === "base-sat") (l.layout ??= {} as never, (l.layout as Record<string, unknown>).visibility = fondo === "satelite" ? "visible" : "none");
    if (l.id === "x-sec-etq-u" && !(pag.etiquetas.subsectores && subsectores)) (l.layout ??= {} as never, (l.layout as Record<string, unknown>).visibility = "none");
    if (l.id === "x-sec-etq-s" && !pag.etiquetas.sectores) (l.layout ??= {} as never, (l.layout as Record<string, unknown>).visibility = "none");
    if (l.id === "x-sec-etq-u" || l.id === "x-sec-etq-s") {
      delete (l as { minzoom?: number }).minzoom;      // la página decide qué etiquetas lleva
      // en la hoja el mapa se reduce (≈ 1.500 px de mapa en 19 cm): las etiquetas se agrandan para que se lean impresas
      const lay = l.layout as Record<string, unknown>, pin = (l.paint ?? {}) as Record<string, unknown>;
      lay["text-size"] = l.id === "x-sec-etq-s" ? 30 : 22; lay["text-allow-overlap"] = true; pin["text-halo-width"] = 3.5; l.paint = pin as never;
    }
  }
  if (s.sources.sel) s.sources.sel = { type: "geojson", data: { type: "FeatureCollection", features: [] } };      // sin lo elegido en pantalla
  let fallo = false;
  const m = new maplibregl.Map({ container: cont, style: s, center: [lonC, latC], zoom: pag.zoom, interactive: false, attributionControl: false, fadeDuration: 0,
    pixelRatio: 1, canvasContextAttributes: { preserveDrawingBuffer: true },
    transformRequest: (url) => (url.includes("accion=geovisor_tesela") && token ? { url, headers: { Authorization: `Bearer ${token}` } } : { url }) } as maplibregl.MapOptions);
  m.on("error", (ev) => { const id = (ev as unknown as { sourceId?: string }).sourceId; if (id === "base-sat" || id === "base") fallo = true; });
  await new Promise<void>((ok) => { let listo = false; const fin = () => { if (!listo) { listo = true; ok(); } }; m.once("idle", fin); setTimeout(fin, 90000); });
  await esperar(150);
  const lienzo = document.createElement("canvas"); lienzo.width = m.getCanvas().width; lienzo.height = m.getCanvas().height;
  lienzo.getContext("2d")!.drawImage(m.getCanvas(), 0, 0);
  const b = m.getBounds();
  const vista = { oeste: b.getWest(), sur: b.getSouth(), este: b.getEast(), norte: b.getNorth() };
  const proy = (lon: number, lat: number): [number, number] => { const p = m.project([lon, lat]); return [p.x, p.y]; };
  // se guardan las esquinas para proyectar después de cerrar el mapa (Mercator: lineal en x y en y de Mercator)
  const [x0, y0] = proy(vista.oeste, vista.norte), [x1, y1] = proy(vista.este, vista.sur);
  const proyectar = (lon: number, lat: number): [number, number] => [x0 + ((mercX(lon) - mercX(vista.oeste)) / (mercX(vista.este) - mercX(vista.oeste))) * (x1 - x0),
    y0 + ((mercY(vista.norte) - mercY(lat)) / (mercY(vista.norte) - mercY(vista.sur))) * (y1 - y0)];
  const ti = tramosConInstalacion(m), sinInstalacion = ti.tramos > 0 && ti.conInstalacion === 0;
  m.remove(); cont.remove();
  return { lienzo, proyectar, ancho, alto, mpp, vista, fallo, sinInstalacion };
}

type Composicion = { titulo: string; usuario: string; fecha: string; leyenda: LeyendaImpresion; logo: HTMLImageElement; aviso: string | null; fondo: "calles" | "satelite" };

/** Compone la hoja: el mapa en el marco y la plantilla alrededor. Devuelve el JPEG y las medidas. */
function componer(pag: PaginaImpresion, mapa: Awaited<ReturnType<typeof dibujarMapa>>, c: Composicion, ubicacion: { lienzo: HTMLCanvasElement; caja: [number, number, number, number] } | null) {
  const hoja = document.createElement("canvas"); hoja.width = Math.round(HOJA_CARTA.ancho * K); hoja.height = Math.round(HOJA_CARTA.alto * K);
  const x = hoja.getContext("2d")!;
  x.fillStyle = "#FFFFFF"; x.fillRect(0, 0, hoja.width, hoja.height);
  const P = (pt: number) => pt * K;
  const fx = P(MARCO.x), fy = P(MARCO.y), fw = P(MARCO.w), fh = P(MARCO.h);
  x.drawImage(mapa.lienzo, fx, fy, fw, fh);
  const esc = fw / mapa.ancho;      // píxeles de hoja por píxel de mapa
  const aHoja = (lon: number, lat: number): [number, number] => { const [mx, my] = mapa.proyectar(lon, lat); return [fx + mx * esc, fy + my * esc]; };
  const txt = (t: string, px: number, py: number, tam: number, o: { peso?: string; color?: string; alinear?: CanvasTextAlign; base?: CanvasTextBaseline; max?: number } = {}) => {
    x.font = `${o.peso ?? "400"} ${P(tam)}px ${FUENTE}`; x.fillStyle = o.color ?? "#1b2733"; x.textAlign = o.alinear ?? "left"; x.textBaseline = o.base ?? "alphabetic";
    x.fillText(t, px, py, o.max);
  };
  // ----- marco con las coordenadas en grados en el borde -----
  x.save(); x.strokeStyle = "#1b2733"; x.lineWidth = P(1.2); x.strokeRect(fx, fy, fw, fh);
  const v = mapa.vista, paso = pag.pasoGrados;
  x.lineWidth = P(0.6);
  for (let lon = Math.ceil(v.oeste / paso) * paso; lon <= v.este; lon += paso) {
    const [px] = aHoja(lon, v.norte); if (px < fx + P(4) || px > fx + fw - P(4)) continue;
    x.beginPath(); x.moveTo(px, fy); x.lineTo(px, fy - P(4)); x.moveTo(px, fy + fh); x.lineTo(px, fy + fh + P(4)); x.stroke();
    txt(grados(lon, "lon"), px, fy - P(6), 6.5, { alinear: "center" }); txt(grados(lon, "lon"), px, fy + fh + P(12), 6.5, { alinear: "center" });
  }
  for (let lat = Math.ceil(v.sur / paso) * paso; lat <= v.norte; lat += paso) {
    const [, py] = aHoja(v.oeste, lat); if (py < fy + P(4) || py > fy + fh - P(4)) continue;
    x.beginPath(); x.moveTo(fx, py); x.lineTo(fx - P(4), py); x.moveTo(fx + fw, py); x.lineTo(fx + fw + P(4), py); x.stroke();
    for (const [lx, giro] of [[fx - P(7), -Math.PI / 2], [fx + fw + P(7), Math.PI / 2]] as const) {
      x.save(); x.translate(lx, py); x.rotate(giro); txt(grados(lat, "lat"), 0, 0, 6.5, { alinear: "center", base: "middle" }); x.restore();
    }
  }
  x.restore();
  // ----- norte pequeño (esquina superior derecha del marco) -----
  { const cx = fx + fw - P(22), cy = fy + P(26);
    x.save(); x.fillStyle = "rgba(255,255,255,0.9)"; x.beginPath(); x.arc(cx, cy, P(14), 0, 2 * Math.PI); x.fill();
    x.fillStyle = "#1b2733"; x.beginPath(); x.moveTo(cx, cy - P(10)); x.lineTo(cx + P(5), cy + P(6)); x.lineTo(cx, cy + P(3)); x.lineTo(cx - P(5), cy + P(6)); x.closePath(); x.fill();
    x.restore(); txt("N", cx, cy - P(11.5), 7, { peso: "700", alinear: "center" }); }
  // ----- escala (gráfica y numérica) para el tamaño REAL de la hoja -----
  const metrosPorPunto = (mapa.mpp * mapa.ancho) / MARCO.w;
  const escala = Math.round((metrosPorPunto * 72) / 0.0254);
  const largo = bonito(metrosPorPunto * MARCO.w * 0.22), barra = largo / metrosPorPunto;
  { const bx = fx + P(10), by = fy + fh - P(14);
    x.save(); x.fillStyle = "rgba(255,255,255,0.9)"; x.fillRect(bx - P(6), by - P(16), P(barra + 60), P(24));
    for (let i = 0; i < 4; i++) { x.fillStyle = i % 2 ? "#FFFFFF" : "#1b2733"; x.fillRect(bx + P((barra / 4) * i), by - P(3), P(barra / 4), P(4)); }
    x.strokeStyle = "#1b2733"; x.lineWidth = P(0.6); x.strokeRect(bx, by - P(3), P(barra), P(4)); x.restore();
    txt("0", bx, by - P(6), 6, { alinear: "center" });
    txt(largo >= 1000 ? `${miles(largo / 1000)} km` : `${miles(largo)} m`, bx + P(barra), by - P(6), 6, { alinear: "center" });
    txt(`Escala aprox. 1:${miles(bonito(escala) === escala ? escala : Math.round(escala / 100) * 100)}`, bx + P(barra) + P(10), by + P(1), 6.5, { peso: "700" }); }
  // ----- mapa de ubicación (solo la Urbana) -----
  if (ubicacion) {
    const w = P(96), h = (w * ubicacion.lienzo.height) / ubicacion.lienzo.width, ux = fx + P(8), uy = fy + P(8);
    x.save(); x.fillStyle = "#FFFFFF"; x.fillRect(ux - P(2), uy - P(2), w + P(4), h + P(14));
    x.drawImage(ubicacion.lienzo, ux, uy, w, h); x.strokeStyle = "#1b2733"; x.lineWidth = P(0.6); x.strokeRect(ux, uy, w, h);
    const [a, b, cc, d] = ubicacion.caja, sx = w / ubicacion.lienzo.width;
    x.strokeStyle = "#D6336C"; x.lineWidth = P(1.4); x.strokeRect(ux + a * sx, uy + b * sx, (cc - a) * sx, (d - b) * sx); x.restore();
    txt("Ubicación", ux + w / 2, uy + h + P(9), 6, { alinear: "center", peso: "700" });
  }
  // ----- cajetín -----
  let notasPagina: string[] = [];
  const cy0 = P(HOJA_CARTA.alto - M.abajo - M.cajetin), ch = P(M.cajetin), cx0 = fx, cw = fw;
  x.save(); x.strokeStyle = "#1b2733"; x.lineWidth = P(1); x.strokeRect(cx0, cy0, cw, ch);
  const div = cx0 + P(328); x.beginPath(); x.moveTo(div, cy0); x.lineTo(div, cy0 + ch); x.stroke(); x.restore();
  // leyenda (izquierda): la temática y, aparte, los sectores
  { let lx = cx0 + P(8), ly = cy0 + P(14), derecha = lx; const notas = [...(c.leyenda.tematica.notas ?? []), ...(c.leyenda.tematica.notaSinInstalacion && mapa.sinInstalacion ? [c.leyenda.tematica.notaSinInstalacion] : [])];
    const fila = P(9.5), tope = cy0 + ch - P(5) - notas.length * P(8), limite = div - P(6);
    txt(c.leyenda.tematica.titulo, lx, ly, 8, { peso: "700" }); ly += P(11);
    // cada columna mide lo que mide su texto más largo (así una columna nunca se monta sobre la siguiente)
    const nuevaColumna = () => { lx = derecha + P(12); ly = cy0 + P(25); };
    const ponerItem = (color: string, t: string, forma: ItemImpresion["forma"] | "sector") => {
      if (ly > tope) nuevaColumna();      // salta de columna solo si el renglón ya no cabe
      x.font = `400 ${P(6.5)}px ${FUENTE}`; const ancho = Math.min(x.measureText(t).width, limite - lx - P(18));
      derecha = Math.max(derecha, lx + P(18) + ancho);
      x.save(); x.fillStyle = color; x.strokeStyle = color;
      if (forma === "linea") { x.lineWidth = P(2.4); x.beginPath(); x.moveTo(lx, ly - P(3)); x.lineTo(lx + P(14), ly - P(3)); x.stroke(); }
      else if (forma === "punto") { x.beginPath(); x.arc(lx + P(7), ly - P(3), P(3), 0, 2 * Math.PI); x.fill(); x.strokeStyle = "#FFFFFF"; x.lineWidth = P(0.8); x.stroke(); }
      else { x.globalAlpha = 0.25; x.fillRect(lx, ly - P(7), P(14), P(8)); x.globalAlpha = 1; x.lineWidth = P(1.2); x.strokeRect(lx, ly - P(7), P(14), P(8)); }
      x.restore(); txt(t, lx + P(18), ly, 6.5, { max: Math.max(P(20), limite - lx - P(18)) }); ly += fila;
    };
    for (const it of c.leyenda.tematica.items) ponerItem(it.color, it.texto, it.forma);
    if (c.leyenda.sectores.length) {
      lx = derecha + P(14); ly = cy0 + P(14); txt("Sectores hidráulicos", lx, ly, 8, { peso: "700" }); ly += P(11);
      for (const s of c.leyenda.sectores) ponerItem(s.color, s.texto, "sector");
      if (c.leyenda.subsectores) { if (ly > tope) nuevaColumna(); txt("Subsectores: borde punteado", lx, ly, 6, { color: "#52626f" }); }
    }
    notas.forEach((n, i) => txt(n, cx0 + P(8), cy0 + ch - P(6) - (notas.length - 1 - i) * P(8), 6, { color: "#52626f", max: div - cx0 - P(14) }));
    notasPagina = notas;
  }
  // título y datos (derecha)
  { const rx = div + P(8), rw = cx0 + cw - rx - P(8); let ry = cy0 + P(8);
    const lw = P(56), lh = (lw * c.logo.height) / c.logo.width; x.drawImage(c.logo, rx, ry, lw, lh); ry += lh + P(10);
    x.font = `700 ${P(9)}px ${FUENTE}`;
    const palabras = `${c.titulo} — ${pag.nombre}`.split(" "); let linea = "";
    for (const pal of palabras) { const prueba = linea ? `${linea} ${pal}` : pal; if (x.measureText(prueba).width > rw && linea) { txt(linea, rx, ry, 9, { peso: "700" }); ry += P(11); linea = pal; } else linea = prueba; }
    if (linea) { txt(linea, rx, ry, 9, { peso: "700" }); ry += P(12); }
    for (const t of [TEXTOS_IMPRESION.lugar, c.fecha, `Usuario: ${c.usuario}`, TEXTOS_IMPRESION.referencia, TEXTOS_IMPRESION.fuente,
      c.fondo === "satelite" ? TEXTOS_IMPRESION.atribucionSatelital : TEXTOS_IMPRESION.atribucionCalles]) { txt(t, rx, ry, 6.5, { max: rw }); ry += P(8.5); }
    if (c.aviso) txt(c.aviso, rx, ry + P(2), 6, { color: "#8a3c00", max: rw });
  }
  return { hoja, metrosPorPunto, escala, notas: notasPagina };
}

const aJpeg = (c: HTMLCanvasElement, q: number): Promise<Uint8Array> => new Promise((ok, mal) => c.toBlob((b) => (b ? b.arrayBuffer().then((a) => ok(new Uint8Array(a)), mal) : mal(new Error("jpeg"))), "image/jpeg", q));

export function ImprimirMapa({ mapa, titulo, leyenda, fondo, onCerrar }: { mapa: maplibregl.Map | null; titulo: string; leyenda: LeyendaImpresion; fondo: "calles" | "satelite"; onCerrar: () => void }) {
  const [estado, setEstado] = useState<{ fase: "trabajando"; texto: string } | { fase: "listo"; url: string; nombre: string; kb: number; aviso: string | null } | { fase: "error"; texto: string }>({ fase: "trabajando", texto: "Preparando la página 1 de 2 (Total)…" });
  const urlRef = useRef<string | null>(null);
  useEffect(() => {
    let vivo = true;
    (async () => {
      try {
        if (!mapa) throw new Error("El mapa aún no está listo.");
        const { data } = await supabase.auth.getSession();
        const token = data.session?.access_token ?? null, usuario = data.session?.user?.email ?? "—";
        const fecha = new Date().toLocaleString("es-CO", { dateStyle: "long", timeStyle: "short", timeZone: "America/Bogota" });
        const logo = await cargarImagen(logoUrl);
        const estilo = mapa.getStyle();
        let usado: "calles" | "satelite" = fondo, aviso: string | null = null;
        const jpgs: Uint8Array[] = [], medidas: MedidaPagina[] = [];
        let ubic: { lienzo: HTMLCanvasElement; proyectar: (lon: number, lat: number) => [number, number] } | null = null;
        for (let i = 0; i < PAGINAS.length; i++) {
          const pag = PAGINAS[i];
          if (vivo) setEstado({ fase: "trabajando", texto: `Preparando la página ${i + 1} de ${PAGINAS.length} (${pag.nombre})…` });
          let m = await dibujarMapa(estilo, pag, usado, leyenda.subsectores, token, MARCO.w / MARCO.h);
          if (m.fallo && usado === "satelite") { usado = "calles"; aviso = TEXTOS_IMPRESION.sinSatelital; m = await dibujarMapa(estilo, pag, usado, leyenda.subsectores, token, MARCO.w / MARCO.h); }
          if (!vivo) return;
          let caja: [number, number, number, number] | null = null;
          if (pag.ubicacion && ubic) { const e = pag.extension; const [a, b] = ubic.proyectar(e.oeste, e.norte), [c2, d] = ubic.proyectar(e.este, e.sur); caja = [a, b, c2, d]; }
          const { hoja, metrosPorPunto, escala, notas } = componer(pag, m, { titulo, usuario, fecha, leyenda, logo, aviso, fondo: usado }, pag.ubicacion && ubic && caja ? { lienzo: ubic.lienzo, caja } : null);
          if (i === 0) ubic = { lienzo: m.lienzo, proyectar: m.proyectar };
          jpgs.push(await aJpeg(hoja, 0.85));
          medidas.push({ clave: pag.clave, zoom: pag.zoom, extension: pag.extension, vista: m.vista, metrosPorPunto, escala, fondo: usado, mapaPx: [m.ancho, m.alto], notas });
        }
        const pdf = pdfDeImagenes(jpgs, titulo);
        const blob = new Blob([pdf as Uint8Array<ArrayBuffer>], { type: "application/pdf" });
        const url = URL.createObjectURL(blob); urlRef.current = url;
        const hoy = new Date().toISOString().slice(0, 10);
        const nombre = `geovisor_${titulo.split(" — ").pop()!.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "_")}_${hoy}.pdf`;
        (window as unknown as { __impresion?: unknown }).__impresion = { medidas, bytes: pdf.length, paginas: jpgs.length, nombre, titulo, marco: MARCO, cajetin: M.cajetin };      // para las pruebas en Chrome
        if (vivo) setEstado({ fase: "listo", url, nombre, kb: Math.round(pdf.length / 1024), aviso });
      } catch (e) {
        if (vivo) setEstado({ fase: "error", texto: e instanceof Error ? e.message : "No se pudo preparar el PDF." });
      }
    })();
    return () => { vivo = false; if (urlRef.current) URL.revokeObjectURL(urlRef.current); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className="geo-imprimir" role="dialog" aria-modal="true" aria-label="Imprimir o guardar en PDF" data-testid="dialogo-imprimir">
      <div className="geo-imprimir-caja">
        <h2>{TEXTOS_IMPRESION.boton}</h2>
        <p>{titulo}. Dos páginas en carta vertical: 1) Total y 2) Urbano, con las capas encendidas ahora.</p>
        {estado.fase === "trabajando" ? <p role="status" data-testid="imprimir-estado">{estado.texto}</p> : null}
        {estado.fase === "error" ? <p className="tec-error-caja" role="alert">{estado.texto}</p> : null}
        {estado.fase === "listo" ? <>
          {estado.aviso ? <p className="geo-imprimir-aviso" role="status" data-testid="imprimir-aviso">{estado.aviso}</p> : null}
          <p role="status" data-testid="imprimir-listo">Listo: {estado.nombre} ({estado.kb >= 1024 ? `${(estado.kb / 1024).toFixed(1).replace(".", ",")} MB` : `${estado.kb} KB`}).</p>
          <div className="geo-imprimir-acciones">
            <a className="tec-boton-sec" href={estado.url} target="_blank" rel="noopener" data-testid="imprimir-abrir">Abrir</a>
            <a className="tec-boton" href={estado.url} download={estado.nombre} data-testid="imprimir-descargar">Descargar PDF</a>
          </div>
        </> : null}
        <div className="geo-imprimir-acciones"><button type="button" className="tec-boton-sec" onClick={onCerrar}>{estado.fase === "trabajando" ? "Cancelar" : "Cerrar"}</button></div>
      </div>
    </div>
  );
}
