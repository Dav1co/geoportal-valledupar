// Investigación y Análisis (Code B, 23-nov) · «Observación sobre este contrato» del Análisis de contrato: lógica PURA (sin red ni React), para probarla aparte.
// Toda observación llega como AVISO al supervisor (Actas registradas → Actividades derivadas, Origen = Análisis de contrato). Los formatos son los mismos de la base
// (campo.f_contacto y campo.f_texto_sin_datos), que vuelve a validarlos: aquí solo se avisa antes de enviar.

export type TipoObservacion = "desocupado" | "direccion_errada" | "actualizacion_datos" | "otra";
export const OBSERVACIONES: { codigo: TipoObservacion; nombre: string; ayuda: string }[] = [
  { codigo: "desocupado", nombre: "Desocupado", ayuda: "El predio está desocupado." },
  { codigo: "direccion_errada", nombre: "Dirección errada", ayuda: "La dirección del contrato no corresponde. Puede escribir la correcta." },
  { codigo: "actualizacion_datos", nombre: "Actualización de datos", ayuda: "Hay que actualizar los datos de quien vive o responde por el predio." },
  { codigo: "otra", nombre: "Otra", ayuda: "Otra observación, en pocas palabras." },
];
export const RELACIONES = [
  { codigo: "propietario", nombre: "Propietario" }, { codigo: "arrendatario", nombre: "Arrendatario" }, { codigo: "familiar", nombre: "Familiar" },
  { codigo: "encargado", nombre: "Encargado" }, { codigo: "otro", nombre: "Otro" },
] as const;

export type Contacto = { nombre: string; cedula: string; telefono: string; correo: string; relacion: string };
export const CONTACTO_VACIO: Contacto = { nombre: "", cedula: "", telefono: "", correo: "", relacion: "" };
export type Borrador = { tipo: TipoObservacion | null; texto: string; direccion: string; contacto: Contacto };
export const BORRADOR_VACIO: Borrador = { tipo: null, texto: "", direccion: "", contacto: CONTACTO_VACIO };

/** El cuerpo que se manda a la Edge (analisis_observar). La clave del correo es «correo_contacto»: la Edge rechaza «correo» en cualquier nivel. */
export type CuerpoObservacion = { contrato: string; tipo: TipoObservacion; texto?: string; direccion?: string;
  contacto?: { nombre?: string; cedula?: string; telefono?: string; correo_contacto?: string; relacion?: string } };

const limpio = (s: string) => s.trim().replace(/\s+/g, " ");
export const soloTelefono = (s: string) => s.replace(/[\s()-]/g, "");
/** Un teléfono o 6 o más dígitos seguidos (una cédula) en un texto libre. */
export const traeDatosPersonales = (s: string) => /\d{6,}/.test(s) || /\d{7,}/.test(s.replace(/[\s().-]/g, ""));

/** Qué le falta o qué está mal antes de enviar (vacío = se puede enviar). */
export function faltasObservacion(b: Borrador): string[] {
  const f: string[] = [];
  if (!b.tipo) return ["Elija la observación."];
  const texto = limpio(b.texto), dir = limpio(b.direccion);
  if (b.tipo === "otra") {
    if (texto.length < 3 || texto.length > 120) f.push("Escriba la observación (entre 3 y 120 caracteres).");
    else if (traeDatosPersonales(texto)) f.push("La observación no puede llevar teléfonos ni cédulas.");
  }
  if (b.tipo === "direccion_errada" && dir) {
    if (dir.length < 3 || dir.length > 120) f.push("La dirección correcta debe tener entre 3 y 120 caracteres.");
    else if (traeDatosPersonales(dir)) f.push("La dirección correcta no puede llevar teléfonos ni cédulas.");
  }
  if (b.tipo === "actualizacion_datos") {
    const c = b.contacto, nombre = limpio(c.nombre), ced = c.cedula.trim(), tel = soloTelefono(c.telefono), correo = c.correo.trim().toLowerCase();
    if (nombre && (nombre.length < 2 || nombre.length > 80 || /\d/.test(nombre))) f.push("El nombre debe tener entre 2 y 80 letras, sin números.");
    if (ced && !/^\d{5,10}$/.test(ced)) f.push("La cédula debe tener solo números, entre 5 y 10.");
    if (tel && !/^(\d{7}|3\d{9}|60\d{8})$/.test(tel)) f.push("El teléfono debe tener 7 o 10 números; si tiene 10, empieza por 3 o por 60.");
    if (correo && (correo.length > 120 || !/^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/.test(correo))) f.push("El correo no tiene un formato válido.");
  }
  return f;
}

/** Arma el cuerpo: solo las casillas del tipo elegido, sin vacíos. */
export function cuerpoObservacion(contrato: string, b: Borrador): CuerpoObservacion {
  if (!b.tipo) throw new Error("sin tipo");
  const cuerpo: CuerpoObservacion = { contrato, tipo: b.tipo };
  if (b.tipo === "otra") cuerpo.texto = limpio(b.texto);
  if (b.tipo === "direccion_errada" && limpio(b.direccion)) cuerpo.direccion = limpio(b.direccion);
  if (b.tipo === "actualizacion_datos") {
    const c = b.contacto, k: NonNullable<CuerpoObservacion["contacto"]> = {};
    if (limpio(c.nombre)) k.nombre = limpio(c.nombre);
    if (c.cedula.trim()) k.cedula = c.cedula.trim();
    if (soloTelefono(c.telefono)) k.telefono = soloTelefono(c.telefono);
    if (c.correo.trim()) k.correo_contacto = c.correo.trim().toLowerCase();
    if (c.relacion) k.relacion = c.relacion;
    if (Object.keys(k).length) cuerpo.contacto = k;
  }
  return cuerpo;
}

/** Sección 7 (vigencia): si es «repetida», el aviso que ya existía (pendiente o cerrado) dentro de la vigencia; no se creó otro y quedó «visto otra vez». */
export type RespuestaObservacion = { repetida: boolean; derivada_id: number; tipo: TipoObservacion; contrato: string; trae_datos?: boolean;
  ya_avisado_en?: string; estado?: string; vistos?: number; vigencia_dias?: number; datos_no_guardados?: boolean;
  /** «vigencia» (Desocupado, 20 días) o «pendiente» (los otros tres: uno pendiente a la vez). David, 24-nov. */
  regla?: "vigencia" | "pendiente"; datos_guardados?: boolean };
const ESTADO_AVISO: Record<string, string> = { pendiente: "pendiente", atendida: "atendido", atendida_fuera: "cerrado: atendido sin formulario", anulada: "cerrado: anulado" };
/** «3 de noviembre de 2026», en hora de Colombia. */
export const fechaLarga = (iso: string) => new Date(iso).toLocaleDateString("es-CO", { timeZone: "America/Bogota", day: "numeric", month: "long", year: "numeric" });
/** El aviso que se muestra después de enviar. */
export function textoEnviada(r: RespuestaObservacion): string {
  const nombre = OBSERVACIONES.find((o) => o.codigo === r.tipo)?.nombre ?? r.tipo;
  if (r.repetida && r.regla === "pendiente") {
    const cuando = r.ya_avisado_en ? ` (avisado el ${fechaLarga(r.ya_avisado_en)})` : "";
    if (r.datos_guardados) return `Ya hay un aviso pendiente «${nombre}» para este contrato${cuando}. Como los datos anteriores fueron anulados, los nuevos se guardaron en ese aviso: solo los verá el supervisor.`;
    return `Ya hay un aviso pendiente «${nombre}» para este contrato${cuando}. No se creó otro.` + (r.datos_no_guardados ? " Lo que escribió no se guardó." : "");
  }
  if (r.repetida) {
    const cuando = r.ya_avisado_en ? ` el ${fechaLarga(r.ya_avisado_en)}` : "";
    const estado = r.estado ? ` (${ESTADO_AVISO[r.estado] ?? r.estado})` : "";
    return `Ya se avisó «${nombre}»${cuando}${estado}. No se creó otro aviso: se anotó que usted lo volvió a ver.`
      + (r.datos_no_guardados ? " Lo que escribió no se guardó." : "");
  }
  return `Quedó en la lista del supervisor: «${nombre}».${r.trae_datos ? " Los datos de contacto solo los verá el supervisor." : ""}`;
}
/** Antigüedad de un aviso (sección 7: los pendientes viejos no se cierran solos). */
export const antiguedadTexto = (dias: number | null | undefined): string =>
  dias === null || dias === undefined ? "" : dias <= 0 ? "hoy" : dias === 1 ? "hace 1 día" : `hace ${dias} días`;
