// Análisis de contrato: lógica PURA (sin React ni red). Se prueba sola en scripts/prueba_analisis_logica.mjs.
// Fechas: los periodos son AAAAMM y los cortes AAAAMMDD; se leen como texto (sin zona horaria). Lo que dependa de «hoy» usa el día de Bogotá, nunca el del navegador ni UTC.
import type { AnalisisCompleto, Consumo, MesConsumo, Promedios, TramoMora } from "./tipos";

const ZONA = "America/Bogota";
export const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

// ---------------- Contrato ----------------
export const MAX_DIGITOS_CONTRATO = 12;
/** Lo que se deja escribir: solo dígitos, hasta 12. */
export const limpiarContrato = (s: string): string => s.replace(/\D/g, "").slice(0, MAX_DIGITOS_CONTRATO);
export const contratoValido = (s: string): boolean => /^\d{1,12}$/.test(s);

// ---------------- Teléfonos ----------------
/** 10 dígitos → «300 123 4567»; 7 dígitos → «570 1234»; otra longitud, los dígitos tal cual. */
export function formatoTelefono(t: string): string {
  const d = t.replace(/\D/g, "");
  if (d.length === 10) return `${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6)}`;
  if (d.length === 7) return `${d.slice(0, 3)} ${d.slice(3)}`;
  return d;
}
export const hrefTelefono = (t: string): string => `tel:${t.replace(/\D/g, "")}`;
/** Máximo 3, primero los celulares de 10 dígitos (el servidor ya los ordena; aquí se asegura), sin vacíos ni repetidos. */
export function telefonosVisibles(lista: string[] | null | undefined): string[] {
  const limpios = [...new Set((lista ?? []).map((t) => t.replace(/\D/g, "")).filter((t) => t.length > 0))];
  const celulares = limpios.filter((t) => t.length === 10);
  return [...celulares, ...limpios.filter((t) => !celulares.includes(t))].slice(0, 3);
}

// ---------------- Periodos y fechas ----------------
const partesPeriodo = (p: string): [number, number] | null => {
  const m = /^(\d{4})(\d{2})/.exec(p ?? "");
  if (!m) return null;
  const mes = Number(m[2]);
  return mes >= 1 && mes <= 12 ? [Number(m[1]), mes] : null;
};
/** «202605» → «may-2026». */
export function etiquetaMes(periodo: string | null | undefined): string {
  const p = partesPeriodo(periodo ?? "");
  return p ? `${MESES_CORTOS[p[1] - 1]}-${p[0]}` : "—";
}
/** «202605» → «may» (eje de la gráfica). */
export function mesCorto(periodo: string): string {
  const p = partesPeriodo(periodo);
  return p ? MESES_CORTOS[p[1] - 1] : "—";
}
/** Meses de `desde` a `hasta` (AAAAMM; también acepta AAAAMMDD o AAAA-MM-DD). null si alguno no se entiende. */
export function mesesEntre(desde: string, hasta: string): number | null {
  const a = partesPeriodo(desde.replace(/-/g, "")), b = partesPeriodo(hasta.replace(/-/g, ""));
  return a && b ? (b[0] * 12 + b[1]) - (a[0] * 12 + a[1]) : null;
}
/** «hace X meses» entre un periodo y el de referencia (consumo.periodo_ultimo). 0 o negativo: «en el último periodo». */
export function haceMeses(periodo: string, referencia: string): string {
  const n = mesesEntre(periodo, referencia);
  if (n === null) return "";
  if (n <= 0) return "en el último periodo";
  return n === 1 ? "hace 1 mes" : `hace ${n} meses`;
}
export function haceDias(dias: number | null | undefined): string {
  if (dias === null || dias === undefined || !Number.isFinite(dias)) return "";
  if (dias <= 0) return "hoy";
  return dias === 1 ? "hace 1 día" : `hace ${dias} días`;
}
/** «20261114» → «14/11/2026». */
export function fechaCorte(c: string | null | undefined): string {
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec(c ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "—";
}
/** «2026-09-18» → «18/09/2026» (fecha sola, sin zona). Un instante con hora («2026-10-02T15:20:00-05:00») se muestra en el día de Bogotá. */
export function fechaCorta(f: string | null | undefined): string {
  if (!f) return "—";
  const solo = /^(\d{4})-(\d{2})-(\d{2})$/.exec(f);
  if (solo) return `${solo[3]}/${solo[2]}/${solo[1]}`;
  const d = new Date(f);
  if (Number.isNaN(d.getTime())) return "—";
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: ZONA, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(d).map((x) => [x.type, x.value]));
  return `${p.day}/${p.month}/${p.year}`;
}
/** AAAAMM de una fecha («2026-10-01» o instante con zona), en el día de Bogotá. */
export function periodoDeFecha(f: string | null | undefined): string | null {
  const c = fechaCorta(f);
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(c);
  return m ? `${m[3]}${m[2]}` : null;
}
/** AAAAMM de hoy en Bogotá. */
export function periodoHoyBogota(ahora: Date = new Date()): string {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: ZONA, year: "numeric", month: "2-digit" }).formatToParts(ahora).map((x) => [x.type, x.value]));
  return `${p.year}${p.month}`;
}
/** Periodo contra el que se cuenta «hace X meses»: el último de consumo; si no hay ficha, el de la cartera diaria; si tampoco, el mes de hoy en Bogotá. */
export function periodoReferencia(r: Pick<AnalisisCompleto, "consumo" | "cortes">, ahora: Date = new Date()): string {
  return r.consumo?.periodo_ultimo ?? r.cortes?.consumo ?? (r.cortes?.cartera ? r.cortes.cartera.slice(0, 6) : null) ?? periodoHoyBogota(ahora);
}

// ---------------- Números ----------------
export const pesos = (n: number | null | undefined): string => (n === null || n === undefined ? "—" : `$ ${Math.round(n).toLocaleString("es-CO")}`);
export const m3 = (n: number | null | undefined): string => (n === null || n === undefined ? "—" : n.toLocaleString("es-CO", { maximumFractionDigits: 1 }));
export const anios = (n: number | null | undefined): string => (n === null || n === undefined ? "sin dato" : n === 1 ? "1 año" : `${n} años`);
const TRAMOS: Record<TramoMora, string> = { al_dia: "al día", leve: "mora leve", media: "mora media", alta: "mora alta", cronica: "mora crónica" };
export const tramoTexto = (t: TramoMora | null | undefined): string => (t ? TRAMOS[t] ?? t : "sin dato");
export const plural = (n: number, uno: string, varios: string) => `${n.toLocaleString("es-CO")} ${n === 1 ? uno : varios}`;
/** «2 Estrato 2» → «Estrato 2»; «1 Residencial» → «Residencial» (se quita el código inicial). */
// 26-nov: la cartera trae «1 - Residencial» (código, guion, nombre): se quita también el guion separador, que antes quedaba suelto («- Residencial»).
// Un valor que solo es guiones («-», «--») se trata como vacío.
export const sinCodigo = (s: string | null | undefined): string => {
  const t = (s ?? "").replace(/^\s*\d+\s*-\s*|^\s*\d+\s+(?=\D)/, "").trim();
  return /^-+$/.test(t) ? "" : t;
};

// ---------------- Gráfica ----------------
export type FilaGrafica = {
  periodo: string; etiqueta: string; corto: string;
  m3: number | null; sinDato: boolean; estimado: boolean; metodo: string | null; causal: string | null;
  estrato: number | null; barrio: number | null; uso: number | null;
};
/** Una fila por mes de `consumo.meses` (siempre 6, del más antiguo al más reciente), con los promedios del mismo periodo. El mes sin dato queda vacío: no se inventa. */
export function filasGrafica(consumo: Consumo | null | undefined, promedios: Promedios | null | undefined): FilaGrafica[] {
  const media = (g: keyof Promedios, p: string) => promedios?.[g]?.meses.find((x) => x.periodo === p)?.media ?? null;
  return (consumo?.meses ?? []).map((m: MesConsumo) => ({
    periodo: m.periodo, etiqueta: etiquetaMes(m.periodo), corto: mesCorto(m.periodo),
    m3: m.sin_dato ? null : m.m3, sinDato: m.sin_dato, estimado: !m.sin_dato && !m.lectura_real, metodo: m.metodo, causal: m.causal,
    estrato: m.sin_dato ? null : media("estrato", m.periodo), barrio: m.sin_dato ? null : media("barrio", m.periodo), uso: m.sin_dato ? null : media("uso", m.periodo),
  }));
}
/** Texto de la columna método/causal de la tabla. */
export function metodoTexto(f: FilaGrafica): string {
  if (f.sinDato) return "sin dato";
  const base = f.estimado ? `estimado${f.metodo ? ` (${f.metodo})` : ""}` : f.metodo ?? "lectura";
  return f.causal ? `${base} · ${f.causal}` : base;
}
/** Eje Y «redondo» que cubre el máximo (con 5 % de aire): 4 tramos iguales de 1; 1,5; 2; 2,5; 3; 4; 5; 6; 7,5 u 8 × 10^k. */
const PASOS_EJE = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8, 10];
export function escalaY(valores: (number | null)[], tramos = 4): { max: number; ticks: number[] } {
  const v = valores.filter((x): x is number => x !== null && Number.isFinite(x) && x >= 0);
  const crudo = Math.max(1, ...v) * 1.05 / tramos;
  const pot = Math.pow(10, Math.floor(Math.log10(crudo)));
  const paso = PASOS_EJE.map((f) => f * pot).find((p) => p >= crudo) ?? 10 * pot;
  const max = Math.round(paso * tramos * 1000) / 1000;
  return { max, ticks: Array.from({ length: tramos + 1 }, (_, i) => Math.round(paso * i * 1000) / 1000) };
}
/** Tramos de una línea: se corta donde falta el valor (el mes sin dato rompe la línea). */
export function tramosLinea(valores: (number | null)[]): { i: number; v: number }[][] {
  const salida: { i: number; v: number }[][] = [];
  let actual: { i: number; v: number }[] = [];
  valores.forEach((v, i) => {
    if (v === null || !Number.isFinite(v)) { if (actual.length) salida.push(actual); actual = []; } else actual.push({ i, v });
  });
  if (actual.length) salida.push(actual);
  return salida;
}

// ---------------- Marcas ----------------
export type Marca = { clave: "submedicion" | "corte" | "pqr" | "predios" | "pendientes"; titulo: string; detalle?: string; alerta?: boolean };
const RE_CORTE = /CORTE|SUSPENS/i;
/** Meses hacia atrás en que un corte o suspensión facturado cuenta como «reciente». */
export const VENTANA_CORTE_MESES = 6;

export function textoSubmedicion(s: NonNullable<AnalisisCompleto["submedicion"]>): string {
  const estrato = s.estrato ? sinCodigo(s.estrato).replace(/^Estrato/, "estrato") : "estrato";
  return `Consumo ${m3(s.consumo)} m³ frente a la referencia ${m3(s.referencia)} m³ de los medidores nuevos del ${estrato} (${etiquetaMes(s.periodo)}); medidor de ${anios(s.anios)}.`;
}

/** Marcas de la tarjeta, en orden: posible submedición · corte o suspensión facturado reciente · PQR abierta · varios predios · revisiones que sugieren cambio de medidor. */
export function marcasDe(r: AnalisisCompleto, ahora: Date = new Date()): Marca[] {
  const ref = periodoReferencia(r, ahora);
  const marcas: Marca[] = [];
  if (r.submedicion?.marca === true) marcas.push({ clave: "submedicion", titulo: "Posible submedición", detalle: textoSubmedicion(r.submedicion), alerta: true });
  const cortes = (r.gestiones?.emd_facturados ?? []).filter((e) => RE_CORTE.test(e.concepto))
    .sort((a, b) => b.periodo.localeCompare(a.periodo));
  const ultimo = cortes[0];
  if (ultimo) {
    const n = mesesEntre(ultimo.periodo, ref);
    if (n !== null && n <= VENTANA_CORTE_MESES) {
      const que = /SUSPENS/i.test(ultimo.concepto) ? "Suspensión" : "Corte";
      marcas.push({ clave: "corte", titulo: `${que} facturado ${haceMeses(ultimo.periodo, ref)}`, detalle: `${ultimo.concepto} (${etiquetaMes(ultimo.periodo)})` });
    }
  }
  const pqr = r.gestiones?.pqr;
  if (pqr && pqr.abiertas > 0) {
    const p = periodoDeFecha(pqr.ultima?.abierta ? pqr.ultima.fecha : null);
    marcas.push({ clave: "pqr", titulo: pqr.abiertas === 1 ? `PQR abierta${p ? ` (${haceMeses(p, ref)})` : ""}` : `${pqr.abiertas} PQR abiertas`, detalle: pqr.ultima?.causal ?? undefined });
  }
  const predios = r.ubicacion?.predios_total ?? 0;
  if (predios > 1) marcas.push({ clave: "predios", titulo: `Este contrato está en ${predios} predios` });
  const pend = (r.gestiones?.pendientes ?? []).filter((x) => x.sugiere === "cambio_medidor");
  if (pend.length > 0) marcas.push({
    clave: "pendientes",
    titulo: pend.length === 1 ? "1 revisión pendiente sugiere cambio de medidor" : `${pend.length} revisiones pendientes sugieren cambio de medidor`,
    detalle: pend.map((x) => `${x.tipo_nombre}${x.consecutivo ? ` ${x.consecutivo}` : ""} (${fechaCorta(x.fecha)})`).join(" · "),
  });
  return marcas;
}

// ---------------- Ubicación ----------------
export function primerPredioConPunto(r: Pick<AnalisisCompleto, "ubicacion">): { lat: number; lon: number } | null {
  const p = (r.ubicacion?.predios ?? []).find((x) => Number.isFinite(x.lat) && Number.isFinite(x.lon) && x.lat !== null && x.lon !== null);
  return p ? { lat: p.lat as number, lon: p.lon as number } : null;
}
export const urlGoogleMaps = (lat: number, lon: number): string => `https://www.google.com/maps?q=${lat},${lon}`;

// ---------------- Cercanía (agregado del 14/11): todo se calcula en el celular ----------------
const RADIO_TIERRA_M = 6371008.8;
/** Distancia en metros entre dos puntos (fórmula de haversine, Tierra esférica de radio medio). */
export function haversineM(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const rad = (g: number) => (g * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * RADIO_TIERRA_M * Math.asin(Math.min(1, Math.sqrt(h)));
}
/** «120 m» por debajo de 1000 m (redondeado al metro); desde 1000 m, «1,2 km» (un decimal). */
export function distanciaCorta(m: number): string {
  if (!Number.isFinite(m) || m < 0) return "—";
  const r = Math.round(m);
  if (r < 1000) return `${r.toLocaleString("es-CO")} m`;
  return `${(m / 1000).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} km`;
}
export const distanciaTexto = (m: number): string => `A ${distanciaCorta(m)}`;
/** Por encima de esta precisión (m) se avisa que la distancia es aproximada. */
export const PRECISION_BUENA_M = 50;
export function avisoPrecision(precision: number | null | undefined): string | null {
  if (precision === null || precision === undefined || !Number.isFinite(precision) || precision <= PRECISION_BUENA_M) return null;
  return `Precisión del GPS baja (± ${Math.round(precision).toLocaleString("es-CO")} m): la distancia es aproximada.`;
}
/** Predio con coordenadas más cercano a la posición, con su distancia; null si ninguno tiene coordenadas. */
export function predioMasCercano<P extends { lat: number | null; lon: number | null }>(pos: { lat: number; lon: number }, predios: P[] | null | undefined): { predio: P; distancia_m: number } | null {
  let mejor: { predio: P; distancia_m: number } | null = null;
  for (const p of predios ?? []) {
    if (p.lat === null || p.lon === null || !Number.isFinite(p.lat) || !Number.isFinite(p.lon)) continue;
    const d = haversineM(pos, { lat: p.lat, lon: p.lon });
    if (!mejor || d < mejor.distancia_m) mejor = { predio: p, distancia_m: d };
  }
  return mejor;
}
export function textoCupoCercanos(c: { restantes: number | null; sin_limite: boolean } | null | undefined): string {
  if (!c || c.sin_limite || c.restantes === null || c.restantes === undefined) return "";
  return c.restantes === 1 ? "Le queda 1 búsqueda cercana hoy." : `Le quedan ${c.restantes.toLocaleString("es-CO")} búsquedas cercanas hoy.`;
}

// ---------------- «Buscar el predio» (modo AirTag, addendum §4): todo en el celular ----------------
/** Lleva un ángulo a [0, 360). */
export function normalizarGrados(g: number): number {
  const r = g % 360;
  return r < 0 ? r + 360 : r === 0 ? 0 : r;
}
/** Rumbo inicial (0 = norte, 90 = este) de `desde` hacia `hacia`. */
export function rumboGrados(desde: { lat: number; lon: number }, hacia: { lat: number; lon: number }): number {
  const rad = (g: number) => (g * Math.PI) / 180;
  const f1 = rad(desde.lat), f2 = rad(hacia.lat), dl = rad(hacia.lon - desde.lon);
  const y = Math.sin(dl) * Math.cos(f2), x = Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dl);
  return normalizarGrados((Math.atan2(y, x) * 180) / Math.PI);
}
/** Giro de la flecha: rumbo al predio menos el rumbo del celular, en [0, 360). Sin brújula (rumbo del celular null), la flecha apunta respecto al norte: el giro es el rumbo. */
export const giroFlecha = (rumbo: number, rumboCelular: number | null): number => normalizarGrados(rumbo - (rumboCelular ?? 0));
const CARDINALES = ["norte", "noreste", "este", "sureste", "sur", "suroeste", "oeste", "noroeste"];
export const nombreCardinal = (g: number): string => CARDINALES[Math.round(normalizarGrados(g) / 45) % 8];
export const textoRumbo = (g: number): string => `hacia el ${nombreCardinal(g)} (${Math.round(normalizarGrados(g)) % 360}°)`;
/** Rumbo del celular a partir de un evento de orientación: `webkitCompassHeading` (iPhone) o 360 − alpha cuando la lectura es absoluta (Android). Sin dato confiable, null. */
export function rumboDeOrientacion(e: { webkitCompassHeading?: number | null; alpha?: number | null; absolute?: boolean | null }): number | null {
  if (typeof e.webkitCompassHeading === "number" && Number.isFinite(e.webkitCompassHeading)) return normalizarGrados(e.webkitCompassHeading);
  if (e.absolute === true && typeof e.alpha === "number" && Number.isFinite(e.alpha)) return normalizarGrados(360 - e.alpha);
  return null;
}
export type Banda = "lejos" | "cerca" | "llego";
/** Umbrales del addendum: verde (llegó) a menos de 15 m, amarillo a menos de 50 m, gris desde 50 m. */
export const UMBRAL_LLEGO_M = 15, UMBRAL_CERCA_M = 50, HISTERESIS_M = 5;
export const bandaCercania = (d: number): Banda => (d < UMBRAL_LLEGO_M ? "llego" : d < UMBRAL_CERCA_M ? "cerca" : "lejos");
export const TEXTO_BANDA: Record<Banda, string> = { lejos: "Lejos", cerca: "Cerca", llego: "Llegó: el predio debería estar a la vista" };
/** Vibración al llegar, con histéresis: vibra al entrar a «llegó» si está armada; se vuelve a armar solo al alejarse a 20 m o más (15 + 5), así el temblor del GPS no la repite. */
export function pasoVibracion(armada: boolean, d: number): { vibrar: boolean; armada: boolean } {
  if (armada && d < UMBRAL_LLEGO_M) return { vibrar: true, armada: false };
  if (!armada && d >= UMBRAL_LLEGO_M + HISTERESIS_M) return { vibrar: false, armada: true };
  return { vibrar: false, armada };
}
/** Precisión peor que la distancia que falta: el GPS ya no puede afinar más. */
export const precisionInsuficiente = (d: number, precision: number | null | undefined): boolean => typeof precision === "number" && Number.isFinite(precision) && precision > d;
/** Anuncio para lectores de pantalla: al cambiar de banda o cada 5 s como mínimo. */
export const anunciarAhora = (ultimoMs: number, ahoraMs: number, cambioBanda: boolean): boolean => cambioBanda || ahoraMs - ultimoMs >= 5000;
export const urlGoogleMapsAPie = (lat: number, lon: number): string => `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}&travelmode=walking`;
