import { camposActivos, ETIQUETA_ADICIONAL, etiquetasActivas, type CampoDef, type Resultado, type TipoFormato } from "./tipos";

// Campo del catálogo que dispara la invitación a abrir el acta de inspección técnica («¿se encontró irregularidad?»). Convención del formato «Acta de revisión o instalación».
export const CAMPO_ENLACE_ACTA = "irr_hay";

// Lógica PURA del formulario de formatos (sin React, sin red): se prueba sola con scripts/prueba_formatos.mjs.
// Espeja las reglas de la base (campo.f_validar_datos y geoportal_campo_crear_reporte) para avisar ANTES de enviar; la base vuelve a validar todo y manda.

/** Lo que la persona digitó en cada campo propio: texto, «si»/«no»/«» para sí o no, y un arreglo de códigos para «opciones». */
export type ValoresCampos = Record<string, string | string[]>;

/** Interpreta un número con formato colombiano: «1.234,5» (punto de miles, coma decimal), «12,5» o «12.5». Vacío → null; ilegible → NaN. */
export function leerNumero(texto: string): number | null {
  const t = texto.trim().replace(/\s/g, "");
  if (t === "") return null;
  if (/^-?\d{1,3}(\.\d{3})+(,\d+)?$/.test(t)) return Number(t.replace(/\./g, "").replace(",", "."));
  if (/^-?\d+(,\d+)?$/.test(t)) return Number(t.replace(",", "."));
  if (/^-?\d+\.\d+$/.test(t)) return Number(t);
  return Number.NaN;
}

const rangoTexto = (c: CampoDef): string =>
  c.minimo !== undefined && c.maximo !== undefined ? ` (de ${c.minimo.toLocaleString("es-CO")} a ${c.maximo.toLocaleString("es-CO")})`
    : c.minimo !== undefined ? ` (mínimo ${c.minimo.toLocaleString("es-CO")})` : c.maximo !== undefined ? ` (máximo ${c.maximo.toLocaleString("es-CO")})` : "";

type LecturaCampo = { vacio: true } | { vacio: false; valor: unknown } | { error: string };

/** Valor de UN campo ya convertido al tipo que espera la base, o su error. Los campos sensibles se validan igual. */
export function leerCampo(c: CampoDef, v: string | string[] | undefined): LecturaCampo {
  const vacio = v === undefined || (Array.isArray(v) ? v.length === 0 : v.trim() === "");
  if (vacio) return { vacio: true };
  switch (c.tipo_dato) {
    case "texto": {
      const t = String(v).trim();
      const max = c.maximo ?? 300;
      return t.length > max ? { error: `«${c.nombre}» es demasiado largo (máximo ${max} caracteres).` } : { vacio: false, valor: t };
    }
    case "entero":
    case "decimal": {
      const n = leerNumero(String(v));
      if (n === null || Number.isNaN(n)) return { error: `«${c.nombre}» debe ser un número.` };
      if (c.tipo_dato === "entero" && !Number.isInteger(n)) return { error: `«${c.nombre}» debe ser un número entero.` };
      if ((c.minimo !== undefined && n < c.minimo) || (c.maximo !== undefined && n > c.maximo)) return { error: `«${c.nombre}» está fuera del rango permitido${rangoTexto(c)}.` };
      return { vacio: false, valor: n };
    }
    case "si_no":
      return v === "si" ? { vacio: false, valor: true } : v === "no" ? { vacio: false, valor: false } : { error: `«${c.nombre}» debe ser sí o no.` };
    case "opcion": {
      const ok = (c.opciones ?? []).some((o) => o.codigo === v && o.activo !== false);
      return ok ? { vacio: false, valor: String(v) } : { error: `Elija una opción válida en «${c.nombre}».` };
    }
    case "opciones": {
      const arr = Array.isArray(v) ? v : [String(v)];
      const validas = arr.every((x) => (c.opciones ?? []).some((o) => o.codigo === x && o.activo !== false)) && new Set(arr).size === arr.length;
      return validas ? { vacio: false, valor: arr } : { error: `Elija opciones válidas en «${c.nombre}».` };
    }
    case "dia_hora": {
      const t = String(v);
      const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(t);
      if (!m || Number.isNaN(new Date(`${t}:00`).getTime())) return { error: `«${c.nombre}» debe ser un día y una hora válidos.` };
      return Number(m[1]) < 2020 ? { error: `«${c.nombre}» está fuera del rango permitido (desde 2020).` } : { vacio: false, valor: t };
    }
    default:
      return { error: `«${c.nombre}» tiene un tipo de dato que esta versión no conoce. Actualice la página.` };
  }
}

/** ¿Se muestra el campo con lo digitado hasta ahora? Sin condición, siempre. Un campo cuyo «padre» está sin responder se oculta (también con `no_es`: sin respuesta no se sabe si «no es»). */
export function esVisible(c: CampoDef, valores: ValoresCampos): boolean {
  const cond = c.visible_si;
  if (!cond) return true;
  const padre = valores[cond.campo];
  if (typeof cond.no_es === "string") {
    if (padre === undefined || padre === "" || (Array.isArray(padre) && padre.length === 0)) return false;
    return Array.isArray(padre) ? !padre.includes(cond.no_es) : padre !== cond.no_es;
  }
  if (typeof cond.es === "boolean") return padre === (cond.es ? "si" : "no");
  return Array.isArray(padre) ? padre.includes(cond.es as string) : padre === cond.es;
}
/** Campos activos que se muestran (y por tanto se validan y se envían). Los ocultos por condición se ignoran por completo: no se envían aunque tengan algo digitado.
 *  Si el «padre» de un campo está a su vez oculto, el campo también se oculta (el padre va antes en el orden del catálogo), aunque conserve un valor viejo. */
export const camposVisibles = (t: TipoFormato, valores: ValoresCampos): CampoDef[] => {
  const ocultos = new Set<string>();
  const sal: CampoDef[] = [];
  for (const c of camposActivos(t)) {
    if ((c.visible_si && ocultos.has(c.visible_si.campo)) || !esVisible(c, valores)) ocultos.add(c.codigo); else sal.push(c);
  }
  return sal;
};

export type SeccionCampos = { titulo: string | null; campos: CampoDef[] };
/** Agrupa los campos (ya en el orden del catálogo) en secciones: los consecutivos con el mismo título forman una. Sin títulos: una sola sección sin título (formulario plano, como siempre). */
export function agruparSecciones(campos: CampoDef[]): SeccionCampos[] {
  const salida: SeccionCampos[] = [];
  for (const c of campos) {
    const t = c.seccion?.trim() || null;
    const ult = salida[salida.length - 1];
    if (ult && ult.titulo === t) ult.campos.push(c); else salida.push({ titulo: t, campos: [c] });
  }
  return salida;
}
/** Avance de una sección: campos visibles con respuesta, total y obligatorios que faltan (la visita inefectiva no exige obligatorios). */
export function avanceSeccion(campos: CampoDef[], valores: ValoresCampos, inefectivo: boolean): { respondidos: number; total: number; faltan: number } {
  let respondidos = 0, faltan = 0;
  for (const c of campos) {
    const r = leerCampo(c, valores[c.codigo]);
    const lleno = !("error" in r) && !r.vacio;
    if (lleno) respondidos++; else if (c.obligatorio && !inefectivo) faltan++;
  }
  return { respondidos, total: campos.length, faltan };
}
/** ¿Marcó irregularidad? (invita a abrir el acta de inspección técnica sobre el mismo contrato). */
export const marcoIrregularidad = (t: TipoFormato, valores: ValoresCampos): boolean => camposActivos(t).some((c) => c.codigo === CAMPO_ENLACE_ACTA) && valores[CAMPO_ENLACE_ACTA] === "si";

/** Aplana lo digitado al objeto `datos` que recibe la Edge: solo los campos con valor (los vacíos no se envían), con la clave `codigo`. Errores por campo. */
export function aplanarDatos(t: TipoFormato, valores: ValoresCampos): { datos: Record<string, unknown> | null; errores: Record<string, string> } {
  const datos: Record<string, unknown> = {};
  const errores: Record<string, string> = {};
  for (const c of camposVisibles(t, valores)) {
    const r = leerCampo(c, valores[c.codigo]);
    if ("error" in r) errores[c.codigo] = r.error;
    else if (!r.vacio) datos[c.codigo] = r.valor;
  }
  return { datos: Object.keys(datos).length > 0 ? datos : null, errores };
}

/** Mínimo de fotos de la visita. Inefectiva: una sola (la de soporte). Efectiva: el mínimo del formato. */
export const minimoFotos = (t: TipoFormato, resultado: Resultado | ""): number =>
  resultado === "inefectivo" ? Math.min(t.fotos_min ?? 1, 1) : (t.fotos_min ?? 1);
export const maximoFotos = (t: TipoFormato, tope: number): number => t.fotos_max ?? tope;

/** Contador de fotos para la pantalla: «3 de 6 (mínimo 3)». */
export const contadorFotos = (n: number, minimo: number, maximo: number): string => `${n} de ${maximo} (mínimo ${minimo})`;

export type EstadoFormato = {
  resultado: Resultado | ""; causal: string; subtipo: string; descripcion: string; contrato: string; valores: ValoresCampos;
  /** Códigos de las etiquetas del catálogo que ya tienen foto. */
  etiquetasConFoto: string[];
  /** Cantidad de fotos «adicional». */
  adicionales: number;
  /** Ubicación del celular (la base exige coordenada; para inefectiva, también su precisión). */
  tieneUbicacion: boolean; tienePrecision: boolean;
  /** Tope general de fotos (límites del formulario) cuando el tipo no trae el suyo. */
  topeGeneral: number;
};

/** Lo que falta antes de poder enviar (mensajes para la persona). Lista vacía = se puede enviar. */
export function validarFormato(t: TipoFormato, e: EstadoFormato): string[] {
  const f: string[] = [];
  const inefectivo = e.resultado === "inefectivo";
  if (t.genera_resultado) {
    if (!e.resultado) f.push("Indique si la visita fue efectiva o inefectiva.");
    else if (inefectivo) {
      if (!e.causal) f.push("Elija la causal de la visita inefectiva.");
      else if (!(t.causales ?? []).some((c) => c.codigo === e.causal)) f.push("La causal elegida no aplica a este formato.");
    }
  }
  if (t.exige_subtipo && !e.subtipo) f.push("Elija el subtipo.");
  if (t.exige_texto && e.descripcion.trim().length < 3) f.push("Este formato exige que describa lo que encontró.");
  if (t.requiere_contrato === "si" && !e.contrato.trim()) f.push("Este formato necesita el número de contrato.");

  // Campos propios: lo digitado siempre se valida; los obligatorios solo se exigen si la visita NO es inefectiva.
  for (const c of camposVisibles(t, e.valores)) {
    const r = leerCampo(c, e.valores[c.codigo]);
    if ("error" in r) f.push(r.error);
    else if (r.vacio && c.obligatorio && !inefectivo) f.push(`Falta «${c.nombre}».`);
  }

  // Fotos
  const etiquetas = etiquetasActivas(t);
  const n = e.etiquetasConFoto.length + e.adicionales;
  const min = minimoFotos(t, e.resultado);
  const max = maximoFotos(t, e.topeGeneral);
  if (n < min) f.push(`Faltan fotos: lleva ${n} y necesita al menos ${min}.`);
  if (n > max) f.push(`Hay más fotos de las permitidas (máximo ${max}).`);
  if (etiquetas.length > 0 && !inefectivo) {
    for (const x of etiquetas) if (x.obligatoria && !e.etiquetasConFoto.includes(x.codigo)) f.push(`Falta la foto obligatoria: «${x.nombre}».`);
  }
  if (inefectivo) {
    const soportes = etiquetas.filter((x) => x.soporte_inefectiva);
    if (soportes.length > 0 && !soportes.some((x) => e.etiquetasConFoto.includes(x.codigo))) {
      f.push(`Visita inefectiva: tome la foto de ${soportes.map((x) => `«${x.nombre}»`).join(" o ")}.`);
    }
    if (!e.tienePrecision) f.push("Visita inefectiva: espere la ubicación del celular con su precisión.");
  }
  if (!e.tieneUbicacion) f.push("Sin ubicación no se puede enviar.");
  return f;
}

/** Ordena las fotos para enviar: primero las de etiqueta del catálogo (en el orden del catálogo), después las «adicional». El orden resultante es 1, 2, 3… sin saltos (lo exige la base). */
export function ordenarFotos<T>(t: TipoFormato, porEtiqueta: Record<string, T | null | undefined>, adicionales: T[]): { orden: number; etiqueta: string | null; foto: T }[] {
  const salida: { etiqueta: string | null; foto: T }[] = [];
  const etiquetas = etiquetasActivas(t);
  for (const x of etiquetas) { const foto = porEtiqueta[x.codigo]; if (foto) salida.push({ etiqueta: x.codigo, foto }); }
  for (const foto of adicionales) salida.push({ etiqueta: etiquetas.length > 0 ? ETIQUETA_ADICIONAL : null, foto });
  return salida.map((s, i) => ({ orden: i + 1, ...s }));
}

/** Cuerpo de las fotos para «crear»: la etiqueta solo viaja si el formato usa etiquetas (la base rechaza etiquetas en formatos que no las usan). */
export const fotosParaCrear = (ordenadas: { orden: number; etiqueta: string | null }[], rutas: Map<number, string>): { orden: number; ruta: string; etiqueta?: string }[] =>
  ordenadas.map((o) => ({ orden: o.orden, ruta: rutas.get(o.orden) ?? "", ...(o.etiqueta ? { etiqueta: o.etiqueta } : {}) }));
