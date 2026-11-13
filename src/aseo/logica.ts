// Lógica PURA de Aseo (sin React, sin red): búsqueda de rutas, programación «hoy y ahora», distancias, validación declarativa del formulario y fotos necesarias.
// Las reglas de validación son las mismas de la Edge (validar_catalogo.ts) y de la base (aseo.f_validar_datos y crear_auditoria); la base es la que decide.
import type { Actividad, Criterio, FotoDef, RutaPlan, SeRealizo } from "./tipos";

/** Minúsculas, sin tildes, espacios colapsados (misma idea que aseo.f_norm de la base). */
export const normalizar = (s: string): string => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Búsqueda de rutas por código, barrio o calle (sectores). Empieza desde `minCaracteres` (5 por catálogo). Todas las palabras deben aparecer.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
export function buscarRutas(rutas: RutaPlan[], texto: string, minCaracteres = 5): RutaPlan[] {
  const q = normalizar(texto);
  if (q.length < minCaracteres) return [];
  const palabras = q.split(" ").filter(Boolean);
  const digitos = q.replace(/\D/g, "");
  return rutas.filter((r) => {
    if (digitos.length >= minCaracteres && digitos === q.replace(/\s/g, "") && r.codigo.includes(digitos)) return true;     // código completo o un fragmento de 5 o más dígitos
    const pajar = normalizar([r.codigo, r.barrios.join(" "), r.sectores ?? "", r.servicio.nombre, r.caracterizacion ?? ""].join(" "));
    return palabras.every((p) => pajar.includes(p));
  });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Programación: ¿está programada hoy y dentro de su franja? (mismas reglas de aseo.f_programacion). `ahora` = hora de Bogotá como texto «AAAA-MM-DDTHH:MM:SS».
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
const aMin = (hm: string) => { const [h, m] = hm.split(":").map(Number); return h * 60 + m; };
export function programacion(r: Pick<RutaPlan, "dias" | "hora_inicio" | "hora_fin">, ahora: string): { fecha_servicio: string; programada_hoy: boolean; en_franja: boolean } {
  const [f, hora] = ahora.split("T");
  const min = aMin(hora.slice(0, 5));
  let fecha = new Date(`${f}T00:00:00Z`);
  let franja = true;
  if (r.hora_inicio && r.hora_fin) {
    const i = aMin(r.hora_inicio), fin = aMin(r.hora_fin);
    if (fin <= i) { if (min < fin) fecha = new Date(fecha.getTime() - 86400000); franja = min >= i || min < fin; } else franja = min >= i && min < fin;
  }
  const iso = ((fecha.getUTCDay() + 6) % 7) + 1;           // 1 = lunes … 7 = domingo
  return { fecha_servicio: fecha.toISOString().slice(0, 10), programada_hoy: r.dias ? r.dias.includes(iso) : true, en_franja: franja };
}

/** Primero las programadas hoy y en su franja, luego las programadas hoy, luego el resto; dentro de cada grupo, por código. */
export function ordenarPorProgramacion(rutas: RutaPlan[], ahora: string): RutaPlan[] {
  const rango = (r: RutaPlan) => { const p = programacion(r, ahora); return p.programada_hoy && p.en_franja ? 0 : p.programada_hoy ? 1 : 2; };
  return [...rutas].sort((a, b) => rango(a) - rango(b) || a.codigo.localeCompare(b.codigo));
}

export function distanciaM(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371008.8, rad = Math.PI / 180, dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/** Texto corto de la distancia: «120 m», «1,4 km». */
export const textoDistancia = (m: number): string => (m < 1000 ? `${Math.round(m).toLocaleString("es-CO")} m` : `${(m / 1000).toLocaleString("es-CO", { maximumFractionDigits: 1 })} km`);

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Formulario del catálogo
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
export type Valores = Record<string, string | string[] | undefined>;       // lo que escribe la persona (texto); «si_no» es «si» o «no»
export const criteriosActivos = (a: Actividad): Criterio[] => (a.criterios ?? []).filter((c) => c.activo !== false);
export const fotosActivas = (a: Actividad): FotoDef[] => (a.fotos ?? []).filter((f) => f.activo !== false);

export function leerNumero(texto: string): number | null {
  const t = texto.trim().replace(/\s/g, "").replace(",", ".");
  if (t === "" || !/^-?\d+(\.\d+)?$/.test(t)) return null;
  return Number(t);
}

/** Convierte lo escrito en el objeto `datos` del servidor (solo preguntas respondidas) y los errores por pregunta. Con «No se realizó» no se registran preguntas. */
export function aplanarDatos(a: Actividad, valores: Valores, seRealizo: SeRealizo | ""): { datos: Record<string, unknown>; errores: Record<string, string>; fotosExigidas: string[] } {
  const datos: Record<string, unknown> = {}, errores: Record<string, string> = {}, exigidas: string[] = [];
  if (seRealizo === "no") return { datos, errores, fotosExigidas: exigidas };
  for (const c of criteriosActivos(a)) {
    const v = valores[c.codigo];
    const vacio = v === undefined || v === "" || (Array.isArray(v) && v.length === 0);
    if (vacio) { if (c.obligatorio) errores[c.codigo] = `Falta responder «${c.nombre}».`; continue; }
    switch (c.tipo_dato) {
      case "si_no": {
        const b = v === "si";
        datos[c.codigo] = b;
        if (c.exige_foto_si && c.etiqueta_foto && b === (c.exige_foto_si === "si")) exigidas.push(c.etiqueta_foto);
        break; }
      case "entero": case "decimal": {
        const n = typeof v === "string" ? leerNumero(v) : null;
        if (n === null) errores[c.codigo] = `«${c.nombre}» debe ser un número.`;
        else if (c.tipo_dato === "entero" && !Number.isInteger(n)) errores[c.codigo] = `«${c.nombre}» debe ser un número entero.`;
        else if ((c.minimo != null && n < c.minimo) || (c.maximo != null && n > c.maximo)) errores[c.codigo] = `«${c.nombre}» está fuera del rango permitido.`;
        else datos[c.codigo] = n;
        break; }
      case "opciones": datos[c.codigo] = Array.isArray(v) ? v : [v]; break;
      default: datos[c.codigo] = typeof v === "string" ? v.trim() : v;
    }
  }
  return { datos, errores, fotosExigidas: exigidas };
}

/** Las fotos que la persona debe tomar según la respuesta a «¿Se realizó?» y las respuestas de SST: etiqueta, nombre, cantidad mínima y máxima. */
export function fotosNecesarias(a: Actividad, seRealizo: SeRealizo | "", exigidas: string[]): { etiqueta: string; nombre: string; min: number; max: number }[] {
  if (!seRealizo) return [];
  const salida: { etiqueta: string; nombre: string; min: number; max: number }[] = [];
  for (const f of fotosActivas(a)) {
    if (f.soporte_no_realizada) { if (seRealizo === "no") salida.push({ etiqueta: f.codigo, nombre: f.nombre, min: Math.max(f.cantidad_min, 1), max: f.cantidad_max }); }
    else if (seRealizo === "no") continue;
    else if (f.condicional) { if (exigidas.includes(f.codigo)) salida.push({ etiqueta: f.codigo, nombre: f.nombre, min: Math.max(f.cantidad_min, 1), max: f.cantidad_max }); }
    else salida.push({ etiqueta: f.codigo, nombre: f.nombre, min: f.cantidad_min, max: f.cantidad_max });
  }
  return salida;
}

export type EstadoEnvio = { seRealizo: SeRealizo | ""; causal: string; valores: Valores; fotosPorEtiqueta: Record<string, number> };
/** Errores que impiden enviar (lista corta para mostrar); vacía = se puede enviar. */
export function erroresDeEnvio(a: Actividad, e: EstadoEnvio): string[] {
  const out: string[] = [];
  if (!e.seRealizo) return ["Indique si se realizó: sí, no o parcial."];
  if (e.seRealizo !== "si" && !e.causal) out.push("Indique la causal.");
  const { errores, fotosExigidas } = aplanarDatos(a, e.valores, e.seRealizo);
  out.push(...Object.values(errores));
  for (const f of fotosNecesarias(a, e.seRealizo, fotosExigidas)) {
    const n = e.fotosPorEtiqueta[f.etiqueta] ?? 0;
    if (n < f.min) out.push(f.min === f.max ? `Falta la foto «${f.nombre}»${f.min > 1 ? ` (${n} de ${f.min})` : ""}.` : `Faltan fotos de «${f.nombre}» (${n} de ${f.min}).`);
  }
  return out;
}

export const contadorFotos = (n: number, min: number, max: number): string => (min === max ? `${n} de ${max}` : `${n} de ${max} (mínimo ${min})`);

/** Plantilla de «a las 7:05 a. m.» para mostrar la hora del servidor («AAAA-MM-DDTHH:MM:SS»). */
export function textoFechaHora(iso: string): string {
  const [f, h] = iso.split("T"); const [a, m, d] = f.split("-"); const hh = Number(h.slice(0, 2)); const mm = h.slice(3, 5);
  const ampm = hh >= 12 ? "p. m." : "a. m."; const h12 = hh % 12 === 0 ? 12 : hh % 12;
  return `${d}/${m}/${a} ${h12}:${mm} ${ampm}`;
}
