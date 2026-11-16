import { supabase, FUNCTIONS_URL } from "../lib/supabase";
import { esNoAplicado } from "../campo/apiCampo";

// Cliente de la Edge Function geoportal-tecnica (contrato: edge_contrato.md del Corte 1, Paso A). Aquí NO hay ningún nombre de variable ni de formulario.

export type Planta = { codigo: string; nombre: string };
export type PuntoDef = { codigo: string; nombre: string; tipo: string; planta: string | null; zona?: string | null; orden?: number | null };
export type VariableDef = {
  codigo: string; nombre: string; unidad: string; categoria: string; decimales: number;
  orden: number; obligatoria: boolean; alcance: "por_planta" | "ambas_plantas" | "por_punto";
  punto: { codigo: string; nombre: string } | null;
  tipo_punto?: string | null;        // solo en las «por_punto»: el tipo de punto que admite (tanque, distribucion, muestreo…)
  puntos?: string[] | null;          // solo en las «por_punto»: CÓDIGOS de los puntos activos que admite, en el orden del servidor (los datos de cada punto están en FormularioDef.puntos)
};
export type FormularioDef = {
  formulario: { clave: string; nombre: string; descripcion: string };
  fecha_hoy: string;            // AAAA-MM-DD, día de Bogotá según el servidor
  hora_propuesta: string;       // HH:MM
  dias_atras_max?: number;      // > 0 (Muestreo, 7): la persona elige la fecha de la muestra entre fecha_minima y fecha_hoy. 0 o ausente: la fecha es la de hoy, de solo lectura (Entrada, Salida)
  fecha_minima?: string;        // AAAA-MM-DD = fecha_hoy − dias_atras_max
  plantas: Planta[];
  puntos: PuntoDef[];
  variables: VariableDef[];
};
export type MiFormulario = { clave: string; nombre: string; descripcion: string; con_campos: boolean };
export type MisFormularios = { perfil: "admin" | "supervisor" | "operador"; formularios: MiFormulario[] };
export type FilaResumen = {
  variable: string; nombre: string; unidad: string; decimales: number;
  planta: string | null; planta_nombre: string | null;
  punto?: string | null; punto_nombre?: string | null;      // filas «por punto» (cloro en tanques, caudal de distribución)
  zona?: string | null; zona_nombre?: string | null;        // filas «por zona» (Muestreo: el servidor agrega los puntos de muestreo por zona)
  promedio: number | null; minimo: number | null; maximo: number | null;
};
export type ResumenResp = { formulario: string; ventana_horas: number; filas: FilaResumen[] };
/** Sección opcional «Dosis de coagulante usado» (Entrada). `ppm` es un número (> 0); `otro_nombre` solo con «Otro». */
export type DosisCuerpo = { coagulante: string; otro_nombre?: string; ppm: number };
export type RegistrarCuerpo = {
  formulario: string; planta: string | null; hora: string;
  valores: { variable: string; valor: number }[];
  punto?: string | null; clave_envio: string;
  dosis?: DosisCuerpo;
  inicio_dispositivo?: string;     // ISO con zona: hora del celular al abrir el formulario (contrato común de inicio). Fuera de «valores»; no lleva «fecha» ni «hora» en el nombre
  fecha_muestra?: string;          // AAAA-MM-DD. SOLO en formularios con dias_atras_max > 0 (Muestreo, Corte 0b): la Edge la rechaza en cualquier otro
};
export type RegistrarResp = { lote_id: string; formulario: string; fecha_muestra?: string; hora_muestra?: string; guardados: number; duplicado: boolean; dosis_guardada?: boolean };
/** Opciones de la sección de dosis que entrega el servidor (el catálogo manda: aquí no hay nombres de químicos). Lista vacía = el formulario no tiene la sección. */
export type OpcionQuimico = { codigo: string; nombre: string; pide_nombre: boolean; predeterminado: boolean };
export type QuimicosResp = { formulario: string; max_ppm: number; max_nombre: number; opciones: OpcionQuimico[] };

/** Cómo debe reaccionar la pantalla. «red»: sin respuesta (el envío puede o no haber llegado: reintentar con la MISMA clave es seguro). «sesion»: el token venció.
 *  «horario»: autorizar() rechazó por horario, día o pausa global. «denegado»: usuario no autorizado. «permiso»: la RPC lo negó (texto fijo). «validacion»: 4xx con mensaje para la persona. «servidor»: 5xx. */
export type TipoError = "red" | "sesion" | "horario" | "denegado" | "permiso" | "validacion" | "servidor" | "no_aplicado";
export class ErrorTec extends Error {
  tipo: TipoError;
  status: number;
  constructor(tipo: TipoError, mensaje: string, status: number) {
    super(mensaje);
    this.name = "ErrorTec";
    this.tipo = tipo;
    this.status = status;
  }
}

const TEXTO_SIN_PERMISO = "No tiene permiso para esta acción.";
const TEXTO_DENEGADO = "Usuario no autorizado en el geoportal.";

export function clasificar(status: number, mensaje: string): TipoError {
  if (esNoAplicado(status, mensaje)) return "no_aplicado";
  if (status === 401) return "sesion";
  if (status === 403) {
    if (mensaje === TEXTO_SIN_PERMISO) return "permiso";
    if (mensaje === TEXTO_DENEGADO) return "denegado";
    return "horario";       // «El geoportal está disponible de…», «…temporalmente fuera de servicio.» (textos de autorizar())
  }
  if (status >= 500) return "servidor";
  return "validacion";
}

async function token(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

/** `funcion`: la Edge que se llama (por omisión geoportal-tecnica; geoportal-redes la usa la ficha de activos, Corte 1b). */
export async function pedir<T>(accion: string, opciones: { qs?: Record<string, string>; cuerpo?: unknown; timeoutMs?: number; funcion?: string } = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/${opciones.funcion ?? "geoportal-tecnica"}`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of Object.entries(opciones.qs ?? {})) url.searchParams.set(k, v);

  // Un 401 puede ser solo un token vencido: se renueva la sesión UNA vez y se repite la misma petición (las escrituras llevan clave_envio: repetirlas no duplica).
  for (let intento = 0; intento < 2; intento++) {
    const t = await token();
    if (!t) throw new ErrorTec("sesion", "Su sesión venció.", 401);
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
      throw new ErrorTec("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally {
      clearTimeout(reloj);
    }
    let cuerpo: { error?: string } & Record<string, unknown> = {};
    try {
      cuerpo = await res.json();
    } catch {
      // Respuesta 200 que se cortó o no se pudo leer: el servidor PUDO haber guardado. Se trata como falta de confirmación (reintentar con la misma clave es seguro).
      if (res.ok) throw new ErrorTec("red", "No se pudo confirmar la respuesta del servidor.", 0);
    }
    if (res.ok) return cuerpo as T;
    if (res.status === 401 && intento === 0) {
      const { error } = await supabase.auth.refreshSession();
      if (!error) continue;
    }
    // Un 401/403 de la PLATAFORMA (verify_jwt) no trae «error» sino «message»: se trata igual, con texto propio.
    const mensaje = typeof cuerpo.error === "string" ? cuerpo.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorTec(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorTec("sesion", "Su sesión venció.", 401);
}

// ---------- Corte 5b: minimapa de Muestreo y «Guardar la ubicación de este punto» ----------
/** exactitud: «verificada» (David, o el GPS del operador aprobado por el supervisor) o «aproximada» (centro del barrio). */
export type PuntoMapa = { codigo: string; nombre: string; zona: string | null; exactitud: "verificada" | "aproximada"; fuente: string; en_revision: boolean; propuesta_mia: boolean; lat: number; lon: number };
export type PuntosMapaResp = {
  type: "FeatureCollection"; precision_max_m: number;
  features: { type: "Feature"; geometry: { type: "Point"; coordinates: [number, number] }; properties: Omit<PuntoMapa, "lat" | "lon"> }[];
  sin_ubicacion: { codigo: string; nombre: string; en_revision: boolean }[];
};
export type ProponerResp = { propuesta_id: number; punto: string; estado: "pendiente"; duplicado: boolean; lat: number; lon: number; precision_m: number; distancia_m?: number | null };
/** Los puntos del GeoJSON, planos (con lat y lon). */
export const puntosDelMapa = (r: PuntosMapaResp): PuntoMapa[] => r.features.map((f) => ({ ...f.properties, lon: f.geometry.coordinates[0], lat: f.geometry.coordinates[1] }));

export const apiTec = {
  misFormularios: () => pedir<MisFormularios>("mis_formularios"),
  formulario: (clave: string) => pedir<FormularioDef>("formulario", { qs: { formulario: clave } }),
  resumen: (clave: string) => pedir<ResumenResp>("resumen", { qs: { formulario: clave } }),
  quimicos: (clave: string) => pedir<QuimicosResp>("quimicos", { qs: { formulario: clave } }),
  // 30 s: un envío lento en señal débil no debe cortarse antes de tiempo; si se corta, el reintento con la misma clave es seguro.
  registrar: (cuerpo: RegistrarCuerpo) => pedir<RegistrarResp>("registrar", { cuerpo, timeoutMs: 30000 }),
  puntosMapa: () => pedir<PuntosMapaResp>("puntos_mapa"),
  proponerUbicacion: (punto: string, lat: number, lon: number, precision_m: number) =>
    pedir<ProponerResp>("ubicacion_proponer", { cuerpo: { punto, lat: Number(lat.toFixed(6)), lon: Number(lon.toFixed(6)), precision_m: Math.max(0.1, Math.round(precision_m * 10) / 10) }, timeoutMs: 30000 }),
};
