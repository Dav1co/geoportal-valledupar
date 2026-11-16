import { supabase, FUNCTIONS_URL } from "../lib/supabase";
import { areaCampo } from "./area";
import type { CuerpoCercanos, RespuestaAnalisis, RespuestaCercanos } from "./analisis/tipos";

// Cliente de la Edge Function geoportal-campo (contrato: edge_contrato.md del Paso A + límite de ritmo del Paso B). Aquí NO hay etiquetas de tipos ni de grupos: todo llega del catálogo del servidor.

export type Subtipo = { codigo: string; nombre: string; orden: number; activo: boolean };
export type Tipo = { codigo: string; nombre: string; orden: number; activo: boolean; exige_texto: boolean; exige_subtipo: boolean; tiene_subtipos: boolean; subtipos: Subtipo[] };
export type Grupo = { codigo: string; nombre: string; orden: number; activo: boolean; tipos: Tipo[] };
export type FormularioCampo = {
  perfil: "admin" | "supervisor" | "reportante";
  puede: { reportar: boolean; crear_desde_escritorio: boolean; supervisar: boolean; administrar_catalogo: boolean };
  limites: { max_fotos: number; min_fotos_campo: number; max_bytes_foto: number; tipo_mime: string; max_descripcion?: number };
  zona: { lat_min: number; lat_max: number; lon_min: number; lon_max: number };
  grupos: Grupo[];
};
export type FotoPreparada = { orden: number; ruta: string; url_subida: string; token: string };
export type Preparacion = { reporte_id: string; max_bytes_foto: number; tipo_mime: string; fotos: FotoPreparada[] };
export type Confirmacion = { id: string; registrado_en: string; repetido: boolean; contrato_verificado: boolean | null; aviso_zona: boolean };
export type CuerpoCrear = {
  reporte_id: string; tipo: string; subtipo?: string | null; descripcion?: string | null; contrato?: string | null;
  lat: number; lon: number; precision_m?: number | null; riesgo_inmediato: boolean; origen: "campo" | "escritorio";
  fotos: { orden: number; ruta: string }[];
  /** Pasada 14/11: hora del celular al abrir el formulario (ISO con zona). */
  inicio_dispositivo?: string;
};

/** Cómo debe reaccionar la pantalla. «red»: sin respuesta (el envío puede o no haber llegado; reintentar con el MISMO reporte_id es seguro). «sesion»: el token venció.
 *  «horario»: autorizar() rechazó por horario, día o pausa. «denegado»: usuario no autorizado. «permiso»: la RPC lo negó. «limite»: límite de ritmo (HTTP 429).
 *  «subida_vencida»: la URL firmada de subida ya no sirve (hay que pedir una nueva preparación). «validacion»: 4xx con mensaje para la persona. «servidor»: 5xx. */
export type TipoError = "red" | "sesion" | "horario" | "denegado" | "permiso" | "limite" | "subida_vencida" | "validacion" | "servidor" | "no_aplicado";
export class ErrorCampo extends Error {
  tipo: TipoError;
  status: number;
  constructor(tipo: TipoError, mensaje: string, status: number) {
    super(mensaje);
    this.name = "ErrorCampo";
    this.tipo = tipo;
    this.status = status;
  }
}

const TEXTO_SIN_PERMISO = "No tiene permiso para esta acción.";
const TEXTO_DENEGADO = "Usuario no autorizado en el geoportal.";

/** Aviso para lo que depende de SQL o de una Edge que aún no está aplicada en el servidor. */
export const TEXTO_NO_APLICADO = "Esta función necesita la actualización del servidor (SQL/Edge) que aún no está aplicada.";
/** ¿El fallo es «la ruta o la función no existe»? Edge vieja («Acción no soportada.» / «ruta desconocida»), pasarela 404 sin mensaje propio, o la base (42883 / PGRST202). */
export function esNoAplicado(status: number, mensaje: string): boolean {
  if (status === 404 && mensaje === "No se pudo completar la operación.") return true;
  return /^acci[oó]n no soportada|^ruta desconocida|funci[oó]n .*no existe|42883|PGRST202/i.test(mensaje) && (status === 400 || status === 404 || status === 500 || status === 501);
}

export function clasificar(status: number, mensaje: string): TipoError {
  if (esNoAplicado(status, mensaje)) return "no_aplicado";
  if (status === 401) return "sesion";
  if (status === 403) {
    if (mensaje === TEXTO_SIN_PERMISO) return "permiso";
    if (mensaje === TEXTO_DENEGADO) return "denegado";
    return "horario";       // «El geoportal está disponible de…», «…temporalmente fuera de servicio.» (textos de autorizar())
  }
  if (status === 429) return "limite";
  if (status >= 500) return "servidor";
  return "validacion";
}

async function token(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

export async function pedir<T>(accion: string, opciones: { qs?: Record<string, string>; cuerpo?: unknown; timeoutMs?: number } = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-campo`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of Object.entries(opciones.qs ?? {})) url.searchParams.set(k, v);
  const area = areaCampo();      // Corte 8 de Técnica: la misma pantalla abierta desde Técnica (nulo = Comercial, sin cambios)
  if (area) url.searchParams.set("area", area);

  // Un 401 puede ser solo un token vencido: se renueva la sesión UNA vez y se repite la misma petición (crear lleva reporte_id: repetirlo no duplica).
  for (let intento = 0; intento < 2; intento++) {
    const t = await token();
    if (!t) throw new ErrorCampo("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), opciones.timeoutMs ?? 20000);
    let res: Response;
    try {
      res = await fetch(url.toString(), {
        method: opciones.cuerpo === undefined ? "GET" : "POST",
        headers: { Authorization: `Bearer ${t}`, ...(opciones.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) },
        body: opciones.cuerpo === undefined ? undefined : JSON.stringify(opciones.cuerpo),
        signal: ctl.signal,
      });
    } catch {
      throw new ErrorCampo("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally {
      clearTimeout(reloj);
    }
    let cuerpo: { error?: string } & Record<string, unknown> = {};
    try {
      cuerpo = await res.json();
    } catch {
      // Respuesta 200 cortada o ilegible: el servidor PUDO haber guardado. Se trata como falta de confirmación (reintentar con el mismo reporte_id es seguro).
      if (res.ok) throw new ErrorCampo("red", "No se pudo confirmar la respuesta del servidor.", 0);
    }
    if (res.ok) return cuerpo as T;
    if (res.status === 401 && intento === 0) {
      const { error } = await supabase.auth.refreshSession();
      if (!error) continue;
    }
    const mensaje = typeof cuerpo.error === "string" ? cuerpo.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorCampo(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorCampo("sesion", "Su sesión venció.", 401);
}

const BUCKET = "campo-fotos";
const TIEMPO_SUBIDA_MS = 60000;

export const apiCampo = {
  formulario: () => pedir<FormularioCampo>("formulario"),
  prepararSubida: (cantidad: number, origen: "campo" | "escritorio") => pedir<Preparacion>("preparar_subida", { cuerpo: { cantidad, origen } }),
  // 30 s: un envío lento en señal débil no debe cortarse antes de tiempo; si se corta, el reintento con el mismo reporte_id es seguro.
  crear: (cuerpo: CuerpoCrear) => pedir<Confirmacion>("crear", { cuerpo, timeoutMs: 30000 }),
  /** Análisis de contrato (solo lectura). Trae nombre y teléfono (dato personal): la respuesta NO se guarda ni se reutiliza; cada consulta va al servidor (Cache-Control: no-store). */
  analisisContrato: (contrato: string) => pedir<RespuestaAnalisis>("analisis_contrato", { qs: { contrato } }),
  /** «Contratos cerca de mí»: la posición va en el cuerpo (POST), solo para esta búsqueda. La lista NO trae nombre ni teléfono. */
  analisisCercanos: (lat: number, lon: number, precision_m?: number) => {
    const cuerpo: CuerpoCercanos = { lat, lon, ...(precision_m !== undefined && Number.isFinite(precision_m) ? { precision_m: Math.round(precision_m) } : {}) };
    return pedir<RespuestaCercanos>("analisis_cercanos", { cuerpo });
  },

  /** Sube UNA foto directo a Storage con la URL firmada (token) que entregó la Edge. No pasa por la Edge ni usa la sesión. Una foto que ya estaba (409) cuenta como subida. */
  async subirFoto(ruta: string, tokenSubida: string, foto: Blob): Promise<void> {
    let resultado;
    try {
      resultado = await Promise.race([
        supabase.storage.from(BUCKET).uploadToSignedUrl(ruta, tokenSubida, foto, { contentType: "image/jpeg", upsert: false }),
        new Promise<never>((_, rechazar) => setTimeout(() => rechazar(new Error("tiempo")), TIEMPO_SUBIDA_MS)),
      ]);
    } catch {
      throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0);
    }
    if (!resultado.error) return;
    const e = resultado.error as unknown as { status?: number; statusCode?: string | number };
    const estado = Number(e.status ?? e.statusCode ?? 0);
    if (estado === 409) return;                                                    // ya estaba subida (un intento anterior cuya respuesta se perdió)
    if (estado === 400 || estado === 401 || estado === 403 || estado === 404) throw new ErrorCampo("subida_vencida", "El permiso para subir la foto venció.", estado);
    if (estado >= 500) throw new ErrorCampo("servidor", "El servicio de fotos no está disponible. Intente de nuevo.", estado);
    throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0);
  },
};

/** Texto y qué hacer para cada tipo de error (mensajes en español para la persona). */
export function avisoDeError(e: ErrorCampo): { texto: string; reintentable: boolean } {
  switch (e.tipo) {
    case "red": return { texto: "No hay señal o la conexión se cortó. Sus datos y fotos siguen aquí: cuando tenga señal, pulse «Reintentar».", reintentable: true };
    case "servidor": return { texto: "El servidor no pudo atender el envío en este momento. Sus datos siguen aquí: pulse «Reintentar» en un momento.", reintentable: true };
    case "subida_vencida": return { texto: "El permiso para subir las fotos venció. Pulse «Reintentar»: se pedirá uno nuevo y se enviará todo de nuevo.", reintentable: true };
    case "limite": return { texto: e.message, reintentable: true };
    case "sesion": return { texto: "Su sesión venció. Vuelva a iniciar sesión; sus datos de este formulario se perderán.", reintentable: false };
    case "horario": return { texto: e.message, reintentable: false };
    case "denegado": return { texto: "Su cuenta no está autorizada en el geoportal.", reintentable: false };
    case "permiso": return { texto: "Su cuenta no tiene permiso para enviar reportes de campo. Solicítelo a un administrador.", reintentable: false };
    case "no_aplicado": return { texto: TEXTO_NO_APLICADO, reintentable: false };
    default: return { texto: e.message, reintentable: true };
  }
}

