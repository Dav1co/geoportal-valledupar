import { supabase, FUNCTIONS_URL } from "../lib/supabase";
import { clasificar, ErrorCampo } from "../campo/apiCampo";
import type { Cercana, Confirmacion, CuerpoCrear, FormularioAseo, MapaResp, PlanResp, Preparacion } from "./tipos";
export { ErrorCampo as ErrorAseo, avisoDeError } from "../campo/apiCampo";

// Cliente de la Edge geoportal-aseo. Misma disciplina que el de campo: renueva la sesión una vez ante un 401, distingue «sin respuesta» (reintentar con el mismo auditoria_id es seguro) del resto, nunca registra cuerpos.
// Los errores son los de campo (ErrorCampo / clasificar / avisoDeError): mismos tipos y mismos avisos.

export type Opc = { qs?: Record<string, string>; cuerpo?: unknown; timeoutMs?: number };
export async function pedir<T>(accion: string, o: Opc = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-aseo`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of Object.entries(o.qs ?? {})) url.searchParams.set(k, v);
  for (let intento = 0; intento < 2; intento++) {
    const { data } = await supabase.auth.getSession();
    const t = data.session?.access_token;
    if (!t) throw new ErrorCampo("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), o.timeoutMs ?? 20000);
    let res: Response;
    try {
      res = await fetch(url.toString(), { method: o.cuerpo === undefined ? "GET" : "POST", headers: { Authorization: `Bearer ${t}`, ...(o.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) },
        body: o.cuerpo === undefined ? undefined : JSON.stringify(o.cuerpo), signal: ctl.signal });
    } catch {
      throw new ErrorCampo("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally { clearTimeout(reloj); }
    let cuerpo: { error?: string } & Record<string, unknown> = {};
    try { cuerpo = await res.json(); } catch { if (res.ok) throw new ErrorCampo("red", "No se pudo confirmar la respuesta del servidor.", 0); }
    if (res.ok) return cuerpo as T;
    if (res.status === 401 && intento === 0) { const { error } = await supabase.auth.refreshSession(); if (!error) continue; }
    const mensaje = typeof cuerpo.error === "string" ? cuerpo.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorCampo(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorCampo("sesion", "Su sesión venció.", 401);
}

const BUCKET = "aseo-fotos";
const TIEMPO_SUBIDA_MS = 60000;

export type ResumenCapa = {
  columnas: string[]; columna?: string; filas_recibidas: number; filas_anunciadas: number; completa?: boolean; muestra?: string[]; sin_codigo?: number; con_error?: number; vertices_limpiados?: number;
  errores?: { orden: number; motivo: string }[]; enlazan?: number; rutas_enlazadas?: number; no_enlazan_total?: number; no_enlazan?: { orden: number; crudo: string; normalizado: string }[];
  repetidos_total?: number; repetidos?: { codigo: string; veces: number; mezcla_tipos: boolean; enlaza: boolean }[]; rutas_activas_sin_trazado_despues?: number; aplicada?: boolean;
};
export type ResumenPlan = {
  confirmado: boolean; repetido?: boolean; mensaje?: string; filas?: number; rutas_nuevas?: number; rutas_existentes?: number; rutas_fuera_de_plan?: number; con_errores?: boolean; errores?: { codigo: string; motivo: string }[];
  version?: number; version_siguiente?: number; provisional?: boolean; carga_id?: string;
  barrios?: { pares: number; rutas_con_barrio: number; nombres: number; nombres_coinciden: number; sin_coincidencia: { nombre: string; rutas: number }[] };
};
export type Normalizacion = { recortar?: boolean; quitar_espacios?: boolean; solo_digitos?: boolean; quitar_ceros_izquierda?: boolean; rellenar_ceros?: number };

export const apiAseo = {
  formulario: (incluirInactivos = false) => pedir<FormularioAseo>("formulario", { qs: incluirInactivos ? { incluir_inactivos: "1" } : {} }),
  plan: (actividad: string, modalidad: string, etag?: string) => pedir<PlanResp>("plan", { qs: { actividad, modalidad, ...(etag ? { etag } : {}) } }),
  mapa: (actividad: string, modalidad: string, etag?: string) => pedir<MapaResp>("mapa", { qs: { actividad, modalidad, ...(etag ? { etag } : {}) } }),
  cercanas: (actividad: string, modalidad: string, lat: number, lon: number) => pedir<Cercana[]>("cercanas", { qs: { actividad, modalidad, lat: String(lat), lon: String(lon), limite: "20" } }),
  prepararSubida: (actividad: string, cantidad: number) => pedir<Preparacion>("preparar_subida", { cuerpo: { actividad, cantidad }, timeoutMs: 20000 }),
  /** Un solo envío (patrón del Paso D): crea todo o nada; reintentar con el mismo auditoria_id es seguro. */
  crear: (cuerpo: CuerpoCrear) => pedir<Confirmacion>("crear", { cuerpo, timeoutMs: 30000 }),

  /** Sube UNA foto directo a Storage con la URL firmada (token) que entregó la Edge. No pasa por la Edge ni usa la sesión. Una foto que ya estaba (409) cuenta como subida. */
  async subirFoto(ruta: string, tokenSubida: string, foto: Blob): Promise<void> {
    let resultado;
    try {
      resultado = await Promise.race([supabase.storage.from(BUCKET).uploadToSignedUrl(ruta, tokenSubida, foto, { contentType: "image/jpeg", upsert: false }),
        new Promise<never>((_, rechazar) => setTimeout(() => rechazar(new Error("tiempo")), TIEMPO_SUBIDA_MS))]);
    } catch { throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0); }
    if (!resultado.error) return;
    const e = resultado.error as unknown as { status?: number; statusCode?: string | number };
    const estado = Number(e.status ?? e.statusCode ?? 0);
    if (estado === 409) return;
    if (estado === 400 || estado === 401 || estado === 403 || estado === 404) throw new ErrorCampo("subida_vencida", "El permiso para subir la foto venció.", estado);
    if (estado >= 500) throw new ErrorCampo("servidor", "El servicio de fotos no está disponible. Intente de nuevo.", estado);
    throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0);
  },

  // Administración
  cargarPlan: (cabecera: { nombre: string; sha256: string; provisional: boolean }, filas: unknown[], confirmar: boolean) => pedir<ResumenPlan>("cargar_plan", { cuerpo: { cabecera, filas, confirmar }, timeoutMs: 120000 }),
  geoIniciar: (cabecera: { nombre: string; sha256: string; srid: number; origen: string; filas: number }) => pedir<{ carga_id: string; repetido: boolean; aplicada: boolean; recibidas: number; srid: number; filas: number }>("geo_iniciar", { cuerpo: { cabecera } }),
  geoLote: (cargaId: string, base: number, features: unknown[]) => pedir<{ nuevas: number; con_error: number; recibidas: number }>("geo_lote", { cuerpo: { carga_id: cargaId, base, features }, timeoutMs: 120000 }),
  geoResumen: (cargaId: string, columna: string | null, normalizacion: Normalizacion) => pedir<ResumenCapa>("geo_resumen", { cuerpo: { carga_id: cargaId, columna, normalizacion }, timeoutMs: 60000 }),
  geoAplicar: (cargaId: string, columna: string, normalizacion: Normalizacion, repetidos: "unir" | "omitir", nota: string) =>
    pedir<{ versiones_creadas: number; codigos_repetidos_omitidos: number; codigos_repetidos_unidos: number; geometrias_sin_ruta: number }>("geo_aplicar", { cuerpo: { carga_id: cargaId, columna, normalizacion, repetidos, nota }, timeoutMs: 120000 }),
  cargas: () => pedir<{ cargas: { id: string; tipo: string; version: number | null; provisional: boolean; nombre: string; filas: number; origen: string | null; autor: string; creado_en: string; aplicada: boolean }[];
                        resumen: { rutas: number; puntos: number; con_trazado: number; barrios_sin_coincidencia: number } }>("cargas"),
  regenerarBarrios: () => pedir<{ versiones_creadas: number; incompletas: number; sin_cambios: number; con_trazado_propio: number; sin_barrios: number; sin_geometria_en_capa: number }>("regenerar_barrios", { cuerpo: {}, timeoutMs: 120000 }),
  barriosSinCoincidencia: () => pedir<{ sugerencias_disponibles: boolean; barrios: { nombre: string; rutas: number; ejemplo_ruta: string; sugerencias: string[] }[] }>("barrios_sin_coincidencia"),
  alias: (accion: "crear" | "desactivar", alias: string, barrio: string, motivo: string) => pedir<{ id: number; activo: boolean; rutas_actualizadas?: number }>("alias", { cuerpo: { accion, alias, barrio, motivo } }),
};
