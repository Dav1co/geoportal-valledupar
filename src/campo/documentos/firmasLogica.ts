import type { FirmaJpeg } from "../../aseo/firmas";
import { apiDocumentos, type EstadoUsuario, type Esquema, type ReglasFirmas } from "./apiDocumentos";

// Firmas con el dedo de los formularios con valor probatorio (Comercial 21-nov; decisión B5 de David): la del operario de EMDUPAR es obligatoria para registrar; la del usuario
// (quien atendió) y la del testigo, opcionales. El testigo solo va si el usuario no quiso firmar. Lógica pura (sin React): se prueba sola.
// Si el formulario ya pregunta «Firma de quien atendió» (firma_atendio) y «Nombre de quien atendió» (atendio_nombre), la sección toma de ahí el estado y el nombre:
// no se pregunta dos veces y el PDF dice lo mismo que el formulario.
export type FirmasLocal = {
  operario: FirmaJpeg | null;
  usuario: { estado: EstadoUsuario | null; nombre: string; imagen: FirmaJpeg | null };
  testigo: { nombre: string; imagen: FirmaJpeg | null };
};
export const FIRMAS_VACIAS: FirmasLocal = { operario: null, usuario: { estado: null, nombre: "", imagen: null }, testigo: { nombre: "", imagen: null } };
/** Lo que ya dice el formulario: el estado (de firma_atendio) y el nombre de quien atendió. Null si el formulario no lo pregunta. */
export type FuenteFormulario = { estado: EstadoUsuario | null | undefined; nombre: string | null | undefined; testigoNombre?: string | null };
export const SIN_FUENTE: FuenteFormulario = { estado: undefined, nombre: undefined };

/** firma_atendio del formulario (papel) → estado del usuario. */
export function estadoDeFirmaAtendio(v: unknown): EstadoUsuario | null {
  return v === "atendio_firmo" ? "firmo" : v === "atendio_se_nego" ? "no_firmo" : v === "nadie_atendio" ? "nadie_atendio" : null;
}
export const ESTADO_TEXTO: Record<EstadoUsuario, string> = { firmo: "Firmó el usuario", no_firmo: "El usuario no quiso firmar", nadie_atendio: "Nadie atendió" };

/** Estado y nombre efectivos: los del formulario si los pregunta; si no, los de la sección. */
export function efectivo(f: FirmasLocal, fuente: FuenteFormulario): { estado: EstadoUsuario | null; nombre: string } {
  return { estado: fuente.estado !== undefined ? fuente.estado : f.usuario.estado, nombre: (fuente.nombre !== undefined ? fuente.nombre ?? "" : f.usuario.nombre).trim() };
}

/** Lo que falta para poder registrar (textos para la persona). Vacío = se puede. */
export function faltasFirmas(reglas: ReglasFirmas | null, f: FirmasLocal, fuente: FuenteFormulario): string[] {
  if (!reglas) return [];
  const faltas: string[] = [];
  if (reglas.operario === "obligatoria" && !f.operario) faltas.push("Falta la firma del operario.");
  if (reglas.usuario !== "no") {
    const { estado, nombre } = efectivo(f, fuente);
    if (reglas.usuario === "obligatoria" && !estado) faltas.push("Diga si el usuario firmó.");
    if (estado === "firmo") {
      if (!f.usuario.imagen) faltas.push("Falta la firma del usuario.");
      if (nombre.length < 2 || nombre.length > 120) faltas.push(fuente.nombre !== undefined ? "Escriba el nombre de quien atendió (en el formulario)." : "Escriba el nombre de quien firma.");
    }
    if (estado === "no_firmo" && reglas.testigo !== "no") {
      const t = f.testigo, tn = testigoNombre(f, fuente);
      if (t.imagen && (tn.length < 2 || tn.length > 120)) faltas.push(fuente.testigoNombre !== undefined ? "Escriba el nombre del testigo (en el acta)." : "Escriba el nombre del testigo.");
      if (!t.imagen && tn.length > 0 && fuente.testigoNombre === undefined) faltas.push("Falta la firma del testigo (o borre su nombre).");
    }
  }
  return faltas;
}

/** Guarda las firmas en el servidor ANTES de registrar (firma_guardar; repetirla reemplaza). `enviadas` recuerda qué roles opcionales se mandaron a este registro para quitarlos si se borran. */
export async function guardarFirmas(esquema: Esquema, registroId: string, reglas: ReglasFirmas, f: FirmasLocal, fuente: FuenteFormulario, enviadas: Set<string>): Promise<void> {
  if (reglas.operario !== "no" && f.operario) { await apiDocumentos.firmaGuardar(esquema, { registro_id: registroId, rol: "operario", estado: "firmo", imagen: f.operario.b64 }); }
  if (reglas.usuario === "no") return;
  const { estado, nombre } = efectivo(f, fuente);
  const clave = (rol: string) => `${registroId}:${rol}`;
  if (estado) {
    await apiDocumentos.firmaGuardar(esquema, { registro_id: registroId, rol: "usuario", estado, ...(estado === "firmo" ? { nombre, imagen: f.usuario.imagen?.b64 } : {}) });
    enviadas.add(clave("usuario"));
  } else if (enviadas.has(clave("usuario"))) { await apiDocumentos.firmaGuardar(esquema, { registro_id: registroId, rol: "usuario", estado: "quitar" }); enviadas.delete(clave("usuario")); }
  const conTestigo = estado === "no_firmo" && reglas.testigo !== "no" && !!f.testigo.imagen;
  if (conTestigo) {
    await apiDocumentos.firmaGuardar(esquema, { registro_id: registroId, rol: "testigo", estado: "firmo", nombre: testigoNombre(f, fuente), imagen: f.testigo.imagen!.b64 });
    enviadas.add(clave("testigo"));
  } else if (enviadas.has(clave("testigo"))) { await apiDocumentos.firmaGuardar(esquema, { registro_id: registroId, rol: "testigo", estado: "quitar" }); enviadas.delete(clave("testigo")); }
}

/** Nombre del testigo: el del formulario si lo pregunta (el acta), si no el de la sección. */
export const testigoNombre = (f: FirmasLocal, fuente: FuenteFormulario) => (fuente.testigoNombre !== undefined ? fuente.testigoNombre ?? "" : f.testigo.nombre).trim();

/** Lo que ya declara el acta de posible pérdida: quién atendió, si firmó o se negó, y el testigo. */
export function fuenteDelActa(b: { nadieAtendio: boolean | null; seNego: boolean | null; firmoAtendiente: boolean | null; atNombre: string; testigo: string }): FuenteFormulario {
  const estado: EstadoUsuario | null = b.nadieAtendio === true ? "nadie_atendio" : b.nadieAtendio === false ? (b.seNego ? "no_firmo" : b.firmoAtendiente === true ? "firmo" : null) : null;
  return { estado, nombre: b.atNombre, testigoNombre: b.testigo };
}
