import { apiSup, type ActaDatos } from "./api";
import { generarActaPdf, infoJpeg, type DatosActa, type ImagenJpeg } from "../pdf";
import { aBytes, MEMBRETE } from "../ConfirmacionActa";
import { bogotaDeInstante, nombreArchivoActa, textoFechaHora } from "../logica";

// Volver a generar el acta de supervisión desde los datos guardados (supervisor y administrador). El PDF se arma en el navegador y NO se guarda en el servidor; el sello es el MISMO que guardó el servidor al registrar.
// Las fotos se bajan con su URL firmada (60 s). Si el navegador no puede leerlas (por ejemplo por CORS del Storage), se piden en base64 a la Edge, que las baja con la clave de servicio: mismo permiso y misma auditoría.
const coma = (n: number) => n.toFixed(5).replace(".", ",");
const SI_NO = { si: "Sí", no: "No", parcial: "Parcial" } as const;
const aImagen = (b64: string): ImagenJpeg => { const bytes = aBytes(b64.replace(/\s/g, "")); const i = infoJpeg(bytes); return { bytes, ancho: i.ancho, alto: i.alto }; };

/** Arma los DatosActa (sin fotos) a partir de lo que entrega el servidor. Pura (se prueba en Node). */
export function datosDeActa(d: ActaDatos): Omit<DatosActa, "fotos"> {
  const rep = d.representante;
  return {
    consecutivo: d.consecutivo, registradoEn: textoFechaHora(bogotaDeInstante(d.registrado_en)), fechaServicio: d.fecha_servicio.split("-").reverse().join("/"),
    auditor: { nombre: d.auditor.nombre ?? d.auditor.correo.split("@")[0], correo: d.auditor.correo, cargo: d.auditor.cargo },
    firmas: { auditor: d.auditor.imagen_b64 ? aImagen(d.auditor.imagen_b64) : null, representante: { estado: rep.estado, nombre: rep.nombre, imagen: rep.imagen_b64 ? aImagen(rep.imagen_b64) : null } },
    actividad: d.actividad_nombre, modalidad: d.modalidad_nombre, servicio: `${d.servicio} · ${d.servicio_nombre}`,
    ruta: { codigo: d.ruta_codigo, sectores: d.sectores, turno: d.turno_nombre, horario: d.hora_inicio && d.hora_fin ? `${d.hora_inicio} a ${d.hora_fin}` : null, frecuencia: d.frecuencia_nombre, km: d.km },
    seRealizo: SI_NO[d.se_realizo], causal: d.causal_nombre, respuestas: d.respuestas.map((r) => ({ pregunta: r.pregunta, respuesta: r.respuesta ?? "—" })), observaciones: d.observaciones,
    posicion: { inicio: d.lat_inicio != null && d.lon_inicio != null ? `${coma(d.lat_inicio)}, ${coma(d.lon_inicio)}` : null, fin: `${coma(d.lat)}, ${coma(d.lon)}`, precision: d.precision_m != null ? `${Math.round(d.precision_m)} m al enviar` : null },
    marcas: [d.marcas.lejos_de_ruta && "Lejos de la ruta", d.marcas.fuera_de_zona && "Fuera de la zona de operación", d.marcas.fuera_de_horario && "Fuera de la franja horaria de la ruta", d.marcas.no_programada_hoy && "Ruta no programada ese día", d.marcas.sin_trazado && "Ruta sin trazado"].filter((x): x is string => !!x),
    sello: d.sello,
  };
}

export async function bajarFoto(id: string, orden: number, url: string): Promise<{ bytes: Uint8Array; respaldo: boolean }> {
  try {
    const r = await fetch(url);
    if (!r.ok) throw new Error(String(r.status));
    return { bytes: new Uint8Array(await r.arrayBuffer()), respaldo: false };
  } catch {
    const x = await apiSup.fotoBase64(id, orden);
    return { bytes: aBytes(x.b64), respaldo: true };
  }
}

export async function regenerarActa(id: string): Promise<{ nombre: string; blob: Blob; usoRespaldo: boolean }> {
  const [d, f] = await Promise.all([apiSup.actaDatos(id), apiSup.fotos(id)]);
  const base = datosDeActa(d); const fotos = []; let usoRespaldo = false;
  for (const x of f.fotos.sort((a, b) => a.orden - b.orden)) {
    const { bytes, respaldo } = await bajarFoto(id, x.orden, x.url); usoRespaldo ||= respaldo; const i = infoJpeg(bytes);
    fotos.push({ bytes, ancho: i.ancho, alto: i.alto, etiqueta: x.nombre });
  }
  const pdf = generarActaPdf({ ...base, fotos }, MEMBRETE);
  return { nombre: nombreArchivoActa(d.registrado_en, d.consecutivo, d.ruta_codigo), blob: new Blob([pdf as BlobPart], { type: "application/pdf" }), usoRespaldo };
}
export function guardarPdf(r: { nombre: string; blob: Blob }) {
  const url = URL.createObjectURL(r.blob); const a = document.createElement("a"); a.href = url; a.download = r.nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
}
