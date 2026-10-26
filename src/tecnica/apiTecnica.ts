import { supabase, FUNCTIONS_URL } from "../lib/supabase";

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
  promedio: number | null; minimo: number | null; maximo: number | null;
};
export type ResumenResp = { formulario: string; ventana_horas: number; filas: FilaResumen[] };
export type RegistrarCuerpo = {
  formulario: string; planta: string | null; hora: string;
  valores: { variable: string; valor: number }[];
  punto?: string | null; clave_envio: string;
};
export type RegistrarResp = { lote_id: string; formulario: string; fecha_muestra?: string; hora_muestra?: string; guardados: number; duplicado: boolean };

/** Cómo debe reaccionar la pantalla. «red»: sin respuesta (el envío puede o no haber llegado: reintentar con la MISMA clave es seguro). «sesion»: el token venció.
 *  «horario»: autorizar() rechazó por horario, día o pausa global. «denegado»: usuario no autorizado. «permiso»: la RPC lo negó (texto fijo). «validacion»: 4xx con mensaje para la persona. «servidor»: 5xx. */
export type TipoError = "red" | "sesion" | "horario" | "denegado" | "permiso" | "validacion" | "servidor";
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

export async function pedir<T>(accion: string, opciones: { qs?: Record<string, string>; cuerpo?: unknown; timeoutMs?: number } = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-tecnica`);
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

export const apiTec = {
  misFormularios: () => pedir<MisFormularios>("mis_formularios"),
  formulario: (clave: string) => pedir<FormularioDef>("formulario", { qs: { formulario: clave } }),
  resumen: (clave: string) => pedir<ResumenResp>("resumen", { qs: { formulario: clave } }),
  // 30 s: un envío lento en señal débil no debe cortarse antes de tiempo; si se corta, el reintento con la misma clave es seguro.
  registrar: (cuerpo: RegistrarCuerpo) => pedir<RegistrarResp>("registrar", { cuerpo, timeoutMs: 30000 }),
};
