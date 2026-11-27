// Cuadernos de análisis: el «vidrio». Las marcas se pintan en un lienzo 2D encima del mapa con UNA sola función, que sirve igual para la pantalla, para la
// captura y para el PDF (cambia el proyector y el tamaño). Aquí también se decide qué marca quedó bajo el dedo.
import type { Marca } from "./apiAnalisis";
import { claveIcono, colorProblema, imagenIcono, nombreActivo, nombreProblema } from "./iconos";
import { COLOR_SISTEMA } from "./iconos_datos";
import { COLOR_POSTIT, miles } from "./modelo";

export type Proyector = (lon: number, lat: number) => [number, number];
/** k: tamaño de los símbolos (1 = pantalla). mpp: metros por píxel del lienzo en esa latitud (para el radio de los círculos). */
export type Lienzo = { x: CanvasRenderingContext2D; proy: Proyector; k: number; mpp: (lat: number) => number };
const FUENTE = "Helvetica, Arial, sans-serif";
const SEL = "#D6336C";
export const colorDe = (m: Pick<Marca, "tipo" | "subtipo" | "sistema" | "estilo">): string =>
  m.tipo === "problema" ? colorProblema(m.subtipo) : m.tipo === "activo" ? COLOR_SISTEMA[m.sistema ?? "acueducto"] : m.tipo === "postit" ? COLOR_POSTIT
    : m.estilo?.color ?? (m.tipo === "zona" ? "#B3261E" : m.tipo === "referencia" ? "#111827" : "#D00000");
const grosorDe = (m: Pick<Marca, "tipo" | "estilo">) => m.estilo?.grosor ?? (m.tipo === "mano" ? 4 : 3);
export const rotulo = (m: Pick<Marca, "tipo" | "subtipo" | "sistema">): string =>
  m.tipo === "problema" ? nombreProblema(m.subtipo) : m.tipo === "activo" ? `${nombreActivo(m.subtipo)} · ${m.sistema === "alcantarillado" ? "Alcantarillado" : "Acueducto"}`
    : m.tipo === "referencia" ? "Punto de referencia" : m.tipo === "postit" ? "Post-it" : m.tipo === "mano" ? "Trazo a mano" : m.tipo === "circulo" ? "Círculo" : m.tipo === "linea" ? "Línea o flecha" : "Zona afectada";

function renglones(x: CanvasRenderingContext2D, t: string, ancho: number, max: number): string[] {
  const res: string[] = []; let act = "";
  for (const pal of t.replace(/\s+/g, " ").trim().split(" ")) {
    const prueba = act ? `${act} ${pal}` : pal;
    if (x.measureText(prueba).width > ancho && act) { res.push(act); act = pal; } else act = prueba;
    if (res.length === max) break;
  }
  if (res.length < max && act) res.push(act);
  else if (res.length === max && act) res[max - 1] = res[max - 1].replace(/.{0,2}$/, "…");
  return res.map((r) => { let s = r; while (s.length > 1 && x.measureText(s).width > ancho) s = s.slice(0, -2) + "…"; return s; });
}
/** La caja del post-it (arriba del punto, con una colita): la misma cuenta para pintarlo y para saber si se tocó. */
function cajaPostit(l: Lienzo, m: Marca): { cx: number; cy: number; x0: number; y0: number; w: number; h: number; lineas: string[]; tam: number } {
  const [cx, cy] = l.proy(m.geom.coordinates[0] as number, m.geom.coordinates[1] as number), tam = 12 * l.k;
  l.x.font = `400 ${tam}px ${FUENTE}`;
  const lineas = renglones(l.x, m.nota ?? "", 150 * l.k, 5);
  const w = Math.max(40 * l.k, ...lineas.map((t) => l.x.measureText(t).width)) + 14 * l.k, h = lineas.length * tam * 1.25 + 12 * l.k;
  return { cx, cy, x0: cx - w / 2, y0: cy - 8 * l.k - h, w, h, lineas, tam };
}

function trazo(l: Lienzo, c: [number, number][], cerrar = false) {
  l.x.beginPath();
  c.forEach(([lon, lat], i) => { const [px, py] = l.proy(lon, lat); if (i) l.x.lineTo(px, py); else l.x.moveTo(px, py); });
  if (cerrar) l.x.closePath();
}

export function pintarMarca(l: Lienzo, m: Marca, elegida = false): void {
  const x = l.x, k = l.k, color = colorDe(m);
  x.save(); x.lineJoin = "round"; x.lineCap = "round";
  if (m.geom.type === "Point") {
    const [lon, lat] = m.geom.coordinates, [cx, cy] = l.proy(lon, lat);
    if (m.tipo === "problema") {
      const img = imagenIcono(claveIcono("problema", m.subtipo ?? "")), w = 28 * k, h = 36 * k;
      if (elegida) { x.strokeStyle = SEL; x.lineWidth = 3 * k; x.beginPath(); x.arc(cx, cy - h * 0.62, 19 * k, 0, 2 * Math.PI); x.stroke(); }
      if (img) x.drawImage(img, cx - w / 2, cy - h * (35 / 36), w, h);
      else { x.fillStyle = color; x.strokeStyle = "#fff"; x.lineWidth = 2 * k; x.beginPath(); x.arc(cx, cy - 12 * k, 10 * k, 0, 2 * Math.PI); x.fill(); x.stroke(); }
    } else if (m.tipo === "activo") {
      const img = imagenIcono(claveIcono("activo", m.subtipo ?? "", m.sistema)), t = 30 * k;
      if (elegida) { x.strokeStyle = SEL; x.lineWidth = 3 * k; x.beginPath(); x.arc(cx, cy, 19 * k, 0, 2 * Math.PI); x.stroke(); }
      if (img) x.drawImage(img, cx - t / 2, cy - t / 2, t, t);
      else { x.fillStyle = color; x.strokeStyle = "#fff"; x.lineWidth = 2 * k; x.fillRect(cx - 8 * k, cy - 8 * k, 16 * k, 16 * k); x.strokeRect(cx - 8 * k, cy - 8 * k, 16 * k, 16 * k); }
    } else if (m.tipo === "referencia") {
      x.fillStyle = color; x.strokeStyle = "#fff"; x.lineWidth = 2.5 * k; x.beginPath(); x.arc(cx, cy, 7 * k, 0, 2 * Math.PI); x.fill(); x.stroke();
      if (elegida) { x.strokeStyle = SEL; x.lineWidth = 3 * k; x.beginPath(); x.arc(cx, cy, 13 * k, 0, 2 * Math.PI); x.stroke(); }
    } else if (m.tipo === "postit") {
      const c = cajaPostit(l, m);
      x.fillStyle = COLOR_POSTIT; x.strokeStyle = elegida ? SEL : "#8a6d00"; x.lineWidth = (elegida ? 3 : 1.2) * k;
      x.shadowColor = "rgba(0,0,0,0.25)"; x.shadowBlur = 5 * k; x.shadowOffsetY = 2 * k;
      x.beginPath(); x.moveTo(c.x0, c.y0); x.lineTo(c.x0 + c.w, c.y0); x.lineTo(c.x0 + c.w, c.y0 + c.h); x.lineTo(c.cx + 6 * k, c.y0 + c.h); x.lineTo(c.cx, c.cy); x.lineTo(c.cx - 6 * k, c.y0 + c.h);
      x.lineTo(c.x0, c.y0 + c.h); x.closePath(); x.fill(); x.shadowColor = "transparent"; x.stroke();
      x.fillStyle = "#1b2733"; x.font = `400 ${c.tam}px ${FUENTE}`; x.textBaseline = "top"; x.textAlign = "left";
      c.lineas.forEach((t, i) => x.fillText(t, c.x0 + 7 * k, c.y0 + 6 * k + i * c.tam * 1.25));
    } else if (m.tipo === "circulo") {
      const r = Math.max(3 * k, (m.radio_m ?? 0) / l.mpp(lat));
      x.fillStyle = color; x.globalAlpha = 0.12; x.beginPath(); x.arc(cx, cy, r, 0, 2 * Math.PI); x.fill(); x.globalAlpha = 1;
      if (elegida) { x.strokeStyle = SEL; x.lineWidth = (grosorDe(m) + 4) * k; x.beginPath(); x.arc(cx, cy, r, 0, 2 * Math.PI); x.stroke(); }
      x.strokeStyle = "#fff"; x.lineWidth = (grosorDe(m) + 2) * k; x.beginPath(); x.arc(cx, cy, r, 0, 2 * Math.PI); x.stroke();
      x.strokeStyle = color; x.lineWidth = grosorDe(m) * k; x.beginPath(); x.arc(cx, cy, r, 0, 2 * Math.PI); x.stroke();
      x.fillStyle = color; x.beginPath(); x.arc(cx, cy, 2.5 * k, 0, 2 * Math.PI); x.fill();
    }
  } else if (m.geom.type === "LineString") {
    const c = m.geom.coordinates, g = grosorDe(m) * k;
    if (elegida) { x.strokeStyle = SEL; x.lineWidth = g + 6 * k; trazo(l, c); x.stroke(); }
    x.strokeStyle = "#fff"; x.lineWidth = g + 2 * k; trazo(l, c); x.stroke();
    x.strokeStyle = color; x.lineWidth = g; trazo(l, c); x.stroke();
    if (m.tipo === "linea" && c.length > 1) {      // punta de flecha en el último vértice: el sentido en que se dibujó
      const [ax, ay] = l.proy(c[c.length - 2][0], c[c.length - 2][1]), [bx, by] = l.proy(c[c.length - 1][0], c[c.length - 1][1]);
      const a = Math.atan2(by - ay, bx - ax), t = Math.max(11 * k, g * 3.2);
      x.fillStyle = color; x.strokeStyle = "#fff"; x.lineWidth = 1.5 * k;
      x.beginPath(); x.moveTo(bx + Math.cos(a) * t * 0.45, by + Math.sin(a) * t * 0.45); x.lineTo(bx - Math.cos(a - 0.5) * t, by - Math.sin(a - 0.5) * t); x.lineTo(bx - Math.cos(a + 0.5) * t, by - Math.sin(a + 0.5) * t);
      x.closePath(); x.fill(); x.stroke();
    }
  } else {
    const c = m.geom.coordinates[0];
    x.fillStyle = color; x.globalAlpha = 0.18; trazo(l, c, true); x.fill(); x.globalAlpha = 1;
    if (elegida) { x.strokeStyle = SEL; x.lineWidth = 7 * k; trazo(l, c, true); x.stroke(); }
    x.strokeStyle = "#fff"; x.lineWidth = 4.5 * k; trazo(l, c, true); x.stroke();
    x.strokeStyle = color; x.lineWidth = 2.5 * k; x.setLineDash([8 * k, 5 * k]); trazo(l, c, true); x.stroke(); x.setLineDash([]);
    if (m.conteo_predios !== null && m.conteo_predios !== undefined) {
      const p = c.slice(0, -1).map(([lon, lat]) => l.proy(lon, lat)), mx = p.reduce((s, q) => s + q[0], 0) / p.length, my = p.reduce((s, q) => s + q[1], 0) / p.length;
      const t = `${miles(m.conteo_predios)} predios · ${miles(m.conteo_contratos ?? 0)} contratos`;
      x.font = `700 ${12 * k}px ${FUENTE}`; x.textAlign = "center"; x.textBaseline = "middle";
      const w = x.measureText(t).width + 12 * k;
      x.fillStyle = "rgba(255,255,255,0.92)"; x.fillRect(mx - w / 2, my - 10 * k, w, 20 * k); x.fillStyle = "#1b2733"; x.fillText(t, mx, my);
    }
  }
  x.restore();
}

/** Todas las marcas: primero las áreas, luego los trazos y encima los puntos (así un pin nunca queda tapado por una zona). */
export function pintarMarcas(l: Lienzo, marcas: Marca[], elegida?: string | null): void {
  const orden = (m: Marca) => (m.geom.type === "Polygon" ? 0 : m.tipo === "circulo" ? 1 : m.geom.type === "LineString" ? 2 : m.tipo === "postit" ? 4 : 3);
  for (const m of [...marcas].sort((a, b) => orden(a) - orden(b))) pintarMarca(l, m, m.id === elegida);
}

const aSegmento = (px: number, py: number, a: [number, number], b: [number, number]) => {
  const dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy, t = l2 ? Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2)) : 0;
  return Math.hypot(px - a[0] - t * dx, py - a[1] - t * dy);
};
/** La marca bajo el dedo (px, py en píxeles del lienzo): los puntos ganan a los trazos y estos a las áreas. */
export function marcaEn(l: Lienzo, marcas: Marca[], px: number, py: number, tol = 14): Marca | null {
  let mejor: { m: Marca; d: number; nivel: number } | null = null;
  const probar = (m: Marca, d: number, nivel: number) => { if (!mejor || nivel > mejor.nivel || (nivel === mejor.nivel && d < mejor.d)) mejor = { m, d, nivel }; };
  for (const m of marcas) {
    if (m.geom.type === "Point") {
      const [lon, lat] = m.geom.coordinates, [cx, cy] = l.proy(lon, lat);
      if (m.tipo === "postit") { const c = cajaPostit(l, m); if (px >= c.x0 - 4 && px <= c.x0 + c.w + 4 && py >= c.y0 - 4 && py <= c.cy + 4) probar(m, Math.hypot(px - cx, py - cy), 3); }
      else if (m.tipo === "problema") { if (Math.abs(px - cx) <= 16 * l.k + tol / 2 && py >= cy - 38 * l.k - tol / 2 && py <= cy + tol / 2) probar(m, Math.hypot(px - cx, py - (cy - 20 * l.k)), 3); }
      else if (m.tipo === "circulo") { const r = (m.radio_m ?? 0) / l.mpp(lat), d = Math.hypot(px - cx, py - cy); if (d <= r + tol) probar(m, Math.abs(d - r), Math.abs(d - r) <= tol ? 2 : 1); }
      else { const d = Math.hypot(px - cx, py - cy); if (d <= 15 * l.k + tol / 2) probar(m, d, 3); }
    } else if (m.geom.type === "LineString") {
      const p = m.geom.coordinates.map(([lon, lat]) => l.proy(lon, lat)); let d = Infinity;
      for (let i = 1; i < p.length; i++) d = Math.min(d, aSegmento(px, py, p[i - 1], p[i]));
      if (d <= tol) probar(m, d, 2);
    } else {
      const p = m.geom.coordinates[0].map(([lon, lat]) => l.proy(lon, lat)); let adentro = false;
      for (let i = 0, j = p.length - 1; i < p.length; j = i++) if ((p[i][1] > py) !== (p[j][1] > py) && px < ((p[j][0] - p[i][0]) * (py - p[i][1])) / (p[j][1] - p[i][1]) + p[i][0]) adentro = !adentro;
      if (adentro) probar(m, 0, 0);
    }
  }
  return mejor ? (mejor as { m: Marca }).m : null;
}

// ---------- leyenda del cuaderno (PDF): solo lo que el cuaderno usa ----------
export type ItemLeyendaCuaderno = { texto: string; dibujar: (x: CanvasRenderingContext2D, cx: number, cy: number, lado: number) => void };
export function leyendaCuaderno(marcas: Marca[]): ItemLeyendaCuaderno[] {
  const vistos = new Map<string, Marca>();
  for (const m of marcas) { const kx = m.tipo === "problema" || m.tipo === "activo" ? `${m.tipo}:${m.subtipo}:${m.sistema ?? ""}` : m.tipo; if (!vistos.has(kx)) vistos.set(kx, m); }
  const orden = ["problema", "activo", "referencia", "postit", "linea", "mano", "circulo", "zona"];
  return [...vistos.values()].sort((a, b) => orden.indexOf(a.tipo) - orden.indexOf(b.tipo)).map((m) => ({
    texto: rotulo(m),
    dibujar: (x, cx, cy, lado) => {
      x.save();
      const img = m.tipo === "problema" ? imagenIcono(claveIcono("problema", m.subtipo ?? "")) : m.tipo === "activo" ? imagenIcono(claveIcono("activo", m.subtipo ?? "", m.sistema)) : undefined;
      const color = m.tipo === "referencia" || m.tipo === "mano" || m.tipo === "linea" || m.tipo === "circulo" ? "#1b2733" : colorDe(m);
      if (img && m.tipo === "problema") x.drawImage(img, cx - (lado * 28) / 72, cy - lado / 2, (lado * 28) / 36, lado);
      else if (img) x.drawImage(img, cx - lado / 2, cy - lado / 2, lado, lado);
      else if (m.tipo === "referencia") { x.fillStyle = color; x.beginPath(); x.arc(cx, cy, lado * 0.28, 0, 2 * Math.PI); x.fill(); }
      else if (m.tipo === "postit") { x.fillStyle = COLOR_POSTIT; x.strokeStyle = "#8a6d00"; x.lineWidth = lado * 0.06; x.fillRect(cx - lado * 0.4, cy - lado * 0.3, lado * 0.8, lado * 0.6); x.strokeRect(cx - lado * 0.4, cy - lado * 0.3, lado * 0.8, lado * 0.6); }
      else if (m.tipo === "circulo") { x.strokeStyle = color; x.lineWidth = lado * 0.1; x.beginPath(); x.arc(cx, cy, lado * 0.34, 0, 2 * Math.PI); x.stroke(); }
      else if (m.tipo === "zona") { x.fillStyle = color; x.globalAlpha = 0.2; x.fillRect(cx - lado * 0.45, cy - lado * 0.3, lado * 0.9, lado * 0.6); x.globalAlpha = 1; x.strokeStyle = color; x.lineWidth = lado * 0.08; x.setLineDash([lado * 0.18, lado * 0.12]); x.strokeRect(cx - lado * 0.45, cy - lado * 0.3, lado * 0.9, lado * 0.6); }
      else { x.strokeStyle = color; x.lineWidth = lado * 0.12; x.lineCap = "round"; x.beginPath(); x.moveTo(cx - lado * 0.45, cy + lado * 0.15);
        if (m.tipo === "mano") x.quadraticCurveTo(cx - lado * 0.1, cy - lado * 0.5, cx + lado * 0.05, cy + lado * 0.05), x.quadraticCurveTo(cx + lado * 0.2, cy + lado * 0.4, cx + lado * 0.45, cy - lado * 0.15);
        else x.lineTo(cx + lado * 0.45, cy - lado * 0.15);
        x.stroke();
        if (m.tipo === "linea") { x.fillStyle = color; x.beginPath(); x.moveTo(cx + lado * 0.5, cy - lado * 0.17); x.lineTo(cx + lado * 0.2, cy - lado * 0.25); x.lineTo(cx + lado * 0.28, cy + lado * 0.05); x.closePath(); x.fill(); } }
      x.restore();
    },
  }));
}
