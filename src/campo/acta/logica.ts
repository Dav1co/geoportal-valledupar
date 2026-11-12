import type { AccionCorrectiva, BorradorActa, FilaMisActas, FormularioActa, FotoBasica, LimitesActa, Precarga } from "./tipos";

// Lógica PURA de la pantalla del acta (sin React, sin red): reglas que el servidor también aplica (el servidor sigue siendo la autoridad; aquí solo se anticipan para que la persona
// corrija antes de enviar), armado del contenido que se registra, contadores de fotos, fecha del acta física y textos de la lista.
// Nada de esto sugiere firma digital: las firmas son HECHOS DECLARADOS que constan en el papel.

export const CONTRATO_OK = /^[A-Za-z0-9-]{1,20}$/;
const HORA = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

export function borradorVacio(modo: BorradorActa["modo"] = "con_contrato"): BorradorActa {
  return {
    modo, contrato: "", direccion: "", barrio: "", estrato: "", uso: "", referencia: "",
    tieneMedidor: null, medidorSerie: "", marca: "", lectura: "", estadoMedidor: "", estadoSellos: "", serieSellos: "", diametro: "",
    hallazgos: [], descripcion: "", acciones: [],
    nadieAtendio: null, derechosInformados: null, atNombre: "", atCalidad: "", atCalidadTexto: "", testigo: "",
    firmoOperario: null, firmoAtendiente: null, seNego: null,
    numeroFisico: "", fechaFisica: "", papelPendiente: false, constancia: "", observaciones: "",
  };
}

/** Carga la precarga del catastro en un borrador nuevo (solo dirección, barrio, estrato y uso; la persona los puede corregir). */
export function conPrecarga(b: BorradorActa, p: Precarga): BorradorActa {
  return { ...b, direccion: p.direccion ?? "", barrio: p.barrio ?? "", estrato: p.estrato ?? "", uso: p.uso ?? "" };
}

/** Estratos 0, 9, 99… y cualquiera fuera de 1 a 6 se muestran TAL CUAL, con la etiqueta «código no estándar» (sin interpretarlos). */
export function etiquetaEstrato(estrato: string | null | undefined, noEstandar?: boolean): string {
  const e = (estrato ?? "").trim();
  if (e === "") return "Sin dato";
  const raro = noEstandar ?? !["1", "2", "3", "4", "5", "6"].includes(e);
  return raro ? `${e} (código no estándar)` : e;
}

// ---------------- Fechas (hora de Bogotá, formato colombiano) ----------------
/** Hoy en America/Bogotá como AAAA-MM-DD, sea cual sea la zona del celular. */
export function hoyBogota(ahora: Date = new Date()): string {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(ahora);
  const g = (t: string) => p.find((x) => x.type === t)!.value;
  return `${g("year")}-${g("month")}-${g("day")}`;
}
export function sumarDias(fecha: string, dias: number): string {
  const [a, m, d] = fecha.split("-").map(Number);
  const t = new Date(Date.UTC(a, m - 1, d + dias));
  return `${t.getUTCFullYear()}-${String(t.getUTCMonth() + 1).padStart(2, "0")}-${String(t.getUTCDate()).padStart(2, "0")}`;
}
export const fechaCO = (f: string) => { const [a, m, d] = f.split("-"); return `${d}/${m}/${a}`; };
const FECHA = /^\d{4}-\d{2}-\d{2}$/;
function fechaExiste(f: string): boolean {
  if (!FECHA.test(f)) return false;
  const [a, m, d] = f.split("-").map(Number);
  const t = new Date(Date.UTC(a, m - 1, d));
  return t.getUTCFullYear() === a && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}
/** Fecha del acta física: existe, no es futura y no pasa del tope (`max_dias_acta_fisica_atras`, 30 por omisión). Devuelve el mensaje o null. */
export function validarFechaPapel(fecha: string, ahora: Date, maxDiasAtras: number): string | null {
  if (!fecha.trim()) return "Indique la fecha del acta física.";
  if (!fechaExiste(fecha)) return "La fecha del acta física no es válida.";
  const hoy = hoyBogota(ahora);
  if (fecha > hoy) return "La fecha del acta física no puede ser futura.";
  const limite = sumarDias(hoy, -maxDiasAtras);
  if (fecha < limite) return `La fecha del acta física no puede ser anterior a ${maxDiasAtras} días (desde el ${fechaCO(limite)}).`;
  return null;
}

// ---------------- Hallazgos y acciones (desde el catálogo) ----------------
/** ¿Hay un hallazgo excluyente («Sin irregularidad») marcado? La irregularidad se DERIVA del catálogo, no se pregunta. */
export function sinIrregularidad(b: BorradorActa, cat: FormularioActa): boolean {
  return b.hallazgos.some((h) => cat.tipos_hallazgo.find((t) => t.codigo === h.codigo)?.excluyente);
}
/** Marca o desmarca un hallazgo respetando la exclusión: «Sin irregularidad» no se combina con otros (marcarlo quita los demás y viceversa). */
export function alternarHallazgo(b: BorradorActa, cat: FormularioActa, codigo: string): BorradorActa {
  const t = cat.tipos_hallazgo.find((x) => x.codigo === codigo);
  if (!t) return b;
  if (b.hallazgos.some((h) => h.codigo === codigo)) return { ...b, hallazgos: b.hallazgos.filter((h) => h.codigo !== codigo) };
  if (t.excluyente) return { ...b, hallazgos: [{ codigo, texto: "" }], acciones: [] };
  const sin = b.hallazgos.filter((h) => !cat.tipos_hallazgo.find((x) => x.codigo === h.codigo)?.excluyente);
  return { ...b, hallazgos: [...sin, { codigo, texto: "" }] };
}
/** Una acción que algún hallazgo activo «habilita» solo procede si ese hallazgo está marcado (regla del servidor). */
export function accionDisponible(a: AccionCorrectiva, b: BorradorActa, cat: FormularioActa): boolean {
  if (sinIrregularidad(b, cat)) return false;
  const habilitadores = cat.tipos_hallazgo.filter((t) => t.habilita_accion === a.codigo);
  return habilitadores.length === 0 || habilitadores.some((t) => b.hallazgos.some((h) => h.codigo === t.codigo));
}
/** Quita las acciones que dejaron de estar disponibles (por ejemplo, tras desmarcar el hallazgo que las habilitaba). */
export function depurarAcciones(b: BorradorActa, cat: FormularioActa): BorradorActa {
  const ok = b.acciones.filter((x) => { const a = cat.acciones.find((y) => y.codigo === x.codigo); return !!a && accionDisponible(a, b, cat); });
  return ok.length === b.acciones.length ? b : { ...b, acciones: ok };
}

// ---------------- Fotos: contadores ----------------
export type Contadores = {
  hallazgo: number; papel: number; minHallazgo: number; maxHallazgo: number; minPapel: number; maxPapel: number;
  tiposFaltantes: string[]; conIrregularidad: boolean;
};
export function contadores(b: BorradorActa, fotos: FotoBasica[], cat: FormularioActa): Contadores {
  const L = cat.limites, esPapel = (tipo: string) => !!cat.tipos_foto.find((t) => t.codigo === tipo)?.acta_fisica;
  const conIrr = !sinIrregularidad(b, cat) && b.hallazgos.length > 0;
  const hallazgo = fotos.filter((f) => !esPapel(f.tipo)).length, papel = fotos.filter((f) => esPapel(f.tipo)).length;
  const exigidos = conIrr ? cat.tipos_foto.filter((t) => t.exigida_con_irregularidad && !t.acta_fisica) : [];
  const tiposFaltantes = exigidos.filter((t) => !fotos.some((f) => f.tipo === t.codigo)).map((t) => t.nombre);
  return {
    hallazgo, papel, conIrregularidad: conIrr, tiposFaltantes,
    minHallazgo: conIrr ? L.min_fotos_irregularidad : L.min_fotos_sin_irregularidad, maxHallazgo: L.max_fotos,
    minPapel: b.papelPendiente ? 0 : 1, maxPapel: b.papelPendiente ? 0 : L.max_fotos_acta_fisica,
  };
}
/** Orden de envío: primero las fotos del hallazgo (en el orden en que se tomaron) y después las del papel; 1, 2, 3… sin saltos. */
export function ordenarFotos<T extends FotoBasica>(fotos: T[], cat: FormularioActa): (T & { orden: number })[] {
  const esPapel = (tipo: string) => !!cat.tipos_foto.find((t) => t.codigo === tipo)?.acta_fisica;
  return [...fotos.filter((f) => !esPapel(f.tipo)), ...fotos.filter((f) => esPapel(f.tipo))].map((f, i) => ({ ...f, orden: i + 1 }));
}

// ---------------- Números ----------------
/** Lectura en m³ con coma o punto decimal («120,5» o «120.5»); null si no es un número. Los puntos de miles se aceptan solo con coma decimal. */
export function numeroCO(texto: string): number | null {
  const t = texto.trim();
  if (t === "") return null;
  const limpio = t.includes(",") ? t.replace(/\./g, "").replace(",", ".") : t;
  if (!/^-?\d+(\.\d+)?$/.test(limpio)) return null;
  return Number(limpio);
}

// ---------------- Reglas del servidor, anticipadas ----------------
const ft = (s: string) => s.trim();
/** Lo que falta o está mal. Vacío = se puede enviar. Los mensajes dicen qué hacer. El servidor vuelve a validar todo. */
export function faltas(b: BorradorActa, fotos: FotoBasica[], cat: FormularioActa, ahora: Date = new Date()): string[] {
  const m: string[] = [];
  const sin = sinIrregularidad(b, cat);
  // Predio
  if (b.modo === "con_contrato") {
    if (!ft(b.contrato)) m.push("Indique el contrato o cambie a «sin contrato».");
    else if (!CONTRATO_OK.test(ft(b.contrato))) m.push("El contrato solo puede llevar letras, números y guiones (máximo 20).");
  }
  if (ft(b.direccion).length < 3) m.push("Escriba la dirección del predio.");
  if (!ft(b.barrio)) m.push("Escriba el barrio.");
  // Medidor
  if (b.tieneMedidor === null) m.push("Indique si el predio tiene medidor.");
  if (b.tieneMedidor === true) {
    if (!b.estadoMedidor) m.push("Indique el estado del medidor.");
    if (ft(b.lectura) !== "") {
      const n = numeroCO(b.lectura);
      if (n === null || n < 0 || n > 99999999) m.push("La lectura debe ser un número entre 0 y 99.999.999 m³.");
    }
  }
  // Hallazgos
  if (b.hallazgos.length === 0) m.push("Marque al menos un hallazgo (o «Sin irregularidad»).");
  for (const h of b.hallazgos) {
    const t = cat.tipos_hallazgo.find((x) => x.codigo === h.codigo);
    if (t?.exige_texto && ft(h.texto).length < 3) m.push(`«${t.nombre}» exige describirlo.`);
  }
  if (!sin && b.hallazgos.length > 0 && ft(b.descripcion).length < 10) m.push("Describa los hallazgos (mínimo 10 caracteres).");
  // Acciones
  if (!sin) for (const x of b.acciones) {
    const a = cat.acciones.find((y) => y.codigo === x.codigo);
    if (!a) continue;
    for (const c of a.campos) {
      const v = ft(x.detalle[c.clave] ?? "");
      if (v === "") { if (c.obligatorio) m.push(`En «${a.nombre}» falta «${c.etiqueta}».`); continue; }
      if (c.tipo === "numero" && numeroCO(v) === null) m.push(`En «${a.nombre}», «${c.etiqueta}» debe ser un número.`);
      if (c.tipo === "hora" && !HORA.test(v)) m.push(`En «${a.nombre}», «${c.etiqueta}» debe ser una hora HH:MM.`);
    }
  }
  // Atención de la visita y firmas DECLARADAS (hechos que constan en el papel)
  if (b.nadieAtendio === null) m.push("Indique si alguien atendió la visita.");
  if (b.firmoOperario === null) m.push("Indique si el operario firmó el acta física.");
  const nadie = b.nadieAtendio === true, neg = b.seNego === true;
  if (nadie && neg) m.push("No puede ser a la vez «nadie atendió» y «se negó a firmar».");
  if (b.nadieAtendio === false) {
    if (ft(b.atNombre).length < 2) m.push("Escriba el nombre de quien atendió la visita.");
    const cal = cat.calidades_atendiente.find((c) => c.codigo === b.atCalidad);
    if (!cal) m.push("Indique en calidad de qué atendió.");
    else if (cal.exige_texto && ft(b.atCalidadTexto).length < 2) m.push(`«${cal.nombre}» exige describirlo.`);
    if (!neg && b.firmoAtendiente !== true) m.push("Marque que quien atendió firmó el acta física, o que se negó a firmar.");
    if (neg && b.firmoAtendiente === true) m.push("Si se negó a firmar, no puede constar que firmó.");
  }
  if ((nadie || neg) && ft(b.constancia).length < 10) m.push(nadie ? "Si nadie atendió, escriba la constancia del operario (mínimo 10 caracteres)." : "Si se negó a firmar, escriba la constancia del operario (mínimo 10 caracteres).");
  if (neg && ft(b.testigo).length < 2) m.push("Si se negó a firmar, escriba el nombre del testigo.");
  if (b.firmoOperario === false && ft(b.constancia).length < 10) m.push("Si el operario no firmó, escriba el motivo en la constancia (mínimo 10 caracteres).");
  // Acta física
  const fp = validarFechaPapel(b.fechaFisica, ahora, cat.limites.max_dias_acta_fisica_atras);
  if (fp) m.push(fp);
  // Fotos
  const c = contadores(b, fotos, cat);
  if (b.hallazgos.length > 0) {
    if (c.hallazgo < c.minHallazgo) m.push(c.conIrregularidad ? `Con irregularidad se necesitan al menos ${c.minHallazgo} fotos del hallazgo.` : `Tome al menos ${c.minHallazgo} foto(s) del predio.`);
    if (c.tiposFaltantes.length > 0) m.push(`Faltan fotos obligatorias: ${c.tiposFaltantes.join(", ")}.`);
  }
  if (c.hallazgo > c.maxHallazgo) m.push(`Máximo ${c.maxHallazgo} fotos del hallazgo.`);
  if (b.papelPendiente) { if (c.papel > 0) m.push("Quite la marca «papel pendiente»: ya tomó la foto del acta física."); }
  else if (c.papel < 1) m.push("Falta la foto del acta física firmada (o marque «papel pendiente» y adjúntela al volver).");
  if (c.papel > cat.limites.max_fotos_acta_fisica) m.push(`Máximo ${cat.limites.max_fotos_acta_fisica} fotos del acta física.`);
  return m;
}

/** Contenido que se registra (SIN rutas ni autor/fecha del servidor; la Edge completa las rutas). Lo vacío no se envía; los datos que no aplican se quitan (sin medidor, sin atendiente…). */
export function construirContenido(b: BorradorActa, fotos: FotoBasica[], cat: FormularioActa): Record<string, unknown> {
  const c: Record<string, unknown> = {};
  const poner = (k: string, v: string) => { const t = ft(v); if (t !== "") c[k] = t; };
  c.modo_identificacion = b.modo;
  if (b.modo === "con_contrato") c.contrato = ft(b.contrato);
  poner("direccion", b.direccion); poner("barrio", b.barrio); poner("estrato", b.estrato); poner("uso", b.uso); poner("referencia_ubicacion", b.referencia);
  c.tiene_medidor = b.tieneMedidor === true;
  if (b.tieneMedidor === true) {
    poner("medidor_serie", b.medidorSerie); poner("marca", b.marca); poner("estado_medidor", b.estadoMedidor);
    const n = numeroCO(b.lectura); if (n !== null) c.lectura_m3 = n;
  }
  poner("estado_sellos", b.estadoSellos); poner("serie_sellos", b.serieSellos); poner("diametro", b.diametro);
  const sin = sinIrregularidad(b, cat);
  c.hallazgos = b.hallazgos.map((h) => { const t = cat.tipos_hallazgo.find((x) => x.codigo === h.codigo); return t?.exige_texto ? { codigo: h.codigo, texto_otro: ft(h.texto) } : { codigo: h.codigo }; });
  poner("descripcion_hallazgos", b.descripcion);
  if (!sin) c.acciones = b.acciones.map((x) => {
    const a = cat.acciones.find((y) => y.codigo === x.codigo);
    const detalle: Record<string, unknown> = {};
    for (const campo of a?.campos ?? []) {
      const v = ft(x.detalle[campo.clave] ?? "");
      if (v === "") continue;
      detalle[campo.clave] = campo.tipo === "numero" ? numeroCO(v) : v;
    }
    return { codigo: x.codigo, detalle };
  });
  const nadie = b.nadieAtendio === true, neg = b.seNego === true;
  c.nadie_atendio = nadie;
  if (b.derechosInformados !== null) c.derechos_informados = b.derechosInformados;
  if (!nadie) {
    const at: Record<string, string> = { nombre: ft(b.atNombre), calidad: b.atCalidad };
    if (cat.calidades_atendiente.find((x) => x.codigo === b.atCalidad)?.exige_texto) at.calidad_texto = ft(b.atCalidadTexto);
    c.atendiente = at;
  }
  if ((nadie || neg) && ft(b.testigo) !== "") c.testigo = { nombre: ft(b.testigo) };
  c.firmo_operario = b.firmoOperario === true;
  c.firmo_atendiente = !nadie && b.firmoAtendiente === true && !neg;
  c.se_nego_a_firmar = neg;
  poner("numero_acta_fisica", b.numeroFisico);
  c.fecha_acta_fisica = ft(b.fechaFisica);
  c.papel_pendiente = b.papelPendiente;
  poner("constancia_operario", b.constancia); poner("observaciones", b.observaciones);
  c.fotos = ordenarFotos(fotos, cat).map((f) => ({ orden: f.orden, tipo: f.tipo }));
  return c;
}

// ---------------- Lista «Mis actas» ----------------
export type AccionFila = "continuar" | "adjuntar_papel" | "ninguna";
/** Qué se puede hacer con una fila: retomar una apertura sin registrar (vigente) o adjuntar la foto del papel pendiente. Una apertura caducada ya no se registra. */
export function accionDeFila(f: FilaMisActas): AccionFila {
  if (f.situacion === "abierta_en_curso") return "continuar";
  if (f.situacion === "registrada" && f.puede_adjuntar_papel) return "adjuntar_papel";
  return "ninguna";
}
export function textoSituacion(f: FilaMisActas): string {
  if (f.situacion === "abierta_en_curso") return "Abierta: falta registrarla";
  if (f.situacion === "abierta_vencida") return "Caducó sin registrarse";
  if (f.papel_pendiente && !f.tiene_foto_papel) return `Registrada${f.estado_nombre ? ` · ${f.estado_nombre}` : ""} · falta la foto del papel`;
  return `Registrada${f.estado_nombre ? ` · ${f.estado_nombre}` : ""}`;
}
export function textoContrato(f: FilaMisActas): string {
  if (f.modo_identificacion === "sin_contrato") return "Sin contrato";
  return f.contrato ? `Contrato ${f.contrato}` : "Contrato por indicar";
}
/** Aviso del consecutivo que puede quedar abierto sin registrar si se abandona (conciliación periódica papel ↔ sistema). */
export const AVISO_CONSECUTIVO_ABIERTO =
  "Al abrir el registro el sistema le entrega un consecutivo. Si abandona sin registrarlo, ese número queda abierto sin registrar hasta que caduca; la supervisión lo ve en la conciliación entre el papel y el sistema.";
export const TEXTO_PAPEL = "El acta física firmada sigue siendo el documento con valor probatorio. Este registro digital la acompaña; no la reemplaza ni la firma.";

/** Aviso de precisión del GPS al abrir (el servidor no rechaza por ubicación: guarda con marca). */
export function avisoPrecision(precision_m: number | null | undefined, umbral = 30): string | null {
  if (precision_m === null || precision_m === undefined || !Number.isFinite(precision_m)) return "No se conoce la precisión de la ubicación.";
  return precision_m > umbral ? `La ubicación es poco precisa (±${Math.round(precision_m)} m). Conviene esperar unos segundos a cielo abierto.` : null;
}
export type { LimitesActa };
