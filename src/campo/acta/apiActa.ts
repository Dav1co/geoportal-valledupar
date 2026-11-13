import { supabase, FUNCTIONS_URL } from "../../lib/supabase";
import { clasificar, ErrorCampo } from "../apiCampo";
import type { BloqueConstancia } from "../constancia/logica";
import type { Apertura, AperturasSinRegistrar, CancelacionActa, ConfirmacionActa, FormularioActa, MisActas, MotivoCancelacionActa, PrediosCercanos, PreparacionActa, Precarga } from "./tipos";

// Cliente de la Edge `geoportal-acta` para la pantalla del acta (mismo estilo que apiFormatos.ts; reutiliza ErrorCampo y clasificar de apiCampo.ts, que no se tocan).
// Rutas que USA la pantalla: formulario, precargar, predios_cercanos, abrir, preparar_subida, registrar, foto_papel y mis_actas.
// NO se llaman `vincular_reporte` ni `actas_de_reporte`: devuelven 400 con gancho hasta que se aplique el enlace con campo (80b). Tampoco las rutas de supervisión (tablero: paso siguiente).
// Nunca se registran cuerpos, rutas, URLs firmadas ni tokens. PORTABILIDAD: las fotos se suben a la `url_subida` firmada que entrega la Edge con un `fetch` común (sin el SDK de Supabase ni
// el nombre del bucket); la lectura de fotos de supervisión también pasa por la Edge. Al migrar a un servidor propio, basta que la Edge firme sus propias URL.

const TEXTO_NO_DISPONIBLE = "El registro de actas aún no está disponible. Intente más tarde.";
const TIEMPO_SUBIDA_MS = 60000;

async function pedir<T>(accion: string, opciones: { metodo?: "GET" | "POST"; cuerpo?: unknown; timeoutMs?: number } = {}): Promise<T> {
  const { metodo = "GET", cuerpo, timeoutMs = 20000 } = opciones;
  const url = new URL(`${FUNCTIONS_URL}/geoportal-acta`);
  url.searchParams.set("accion", accion);
  for (let intento = 0; intento < 2; intento++) {
    const { data } = await supabase.auth.getSession();
    const t = data.session?.access_token;
    if (!t) throw new ErrorCampo("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), timeoutMs);
    let res: Response;
    try {
      res = await fetch(url.toString(), {
        method: metodo, signal: ctl.signal,
        headers: { Authorization: `Bearer ${t}`, ...(metodo === "POST" ? { "Content-Type": "application/json" } : {}) },
        body: metodo === "POST" ? JSON.stringify(cuerpo ?? {}) : undefined,
      });
    } catch {
      throw new ErrorCampo("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally {
      clearTimeout(reloj);
    }
    let resp: { error?: unknown } & Record<string, unknown> = {};
    try {
      resp = await res.json();
    } catch {
      if (res.ok) throw new ErrorCampo("red", "No se pudo confirmar la respuesta del servidor.", 0);
    }
    if (res.ok) return resp as T;
    if (res.status === 401 && intento === 0) {
      const { error } = await supabase.auth.refreshSession();
      if (!error) continue;
    }
    // Un 404 SIN el campo `error` de la Edge lo da la pasarela: la función no está desplegada. (Un 404 con `error` es de la base, con su mensaje para la persona.)
    if (res.status === 404 && typeof resp.error !== "string") throw new ErrorCampo("servidor", TEXTO_NO_DISPONIBLE, 404);
    const mensaje = typeof resp.error === "string" ? resp.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorCampo(clasificar(res.status, mensaje), mensaje, res.status);   // 429 → «limite», con el mensaje de la base
  }
  throw new ErrorCampo("sesion", "Su sesión venció.", 401);
}

export const apiActa = {
  /** Catálogos activos, límites, zona y el aviso del carácter del registro. */
  formulario: () => pedir<FormularioActa>("formulario"),
  /** ¿Existe el contrato? Y, si existe, dirección, barrio, estrato y uso (nunca nombre ni documento). No consume consecutivo. 429 por ritmo. */
  precargar: (contrato: string) => pedir<Precarga>("precargar", { metodo: "POST", cuerpo: { contrato } }),
  /** Contratos a ≤15 m (hasta 5), para sugerir cuando el predio no tiene contrato. */
  prediosCercanos: (lat: number, lon: number) => pedir<PrediosCercanos>("predios_cercanos", { metodo: "POST", cuerpo: { lat, lon } }),
  /** Abre el registro y CONSUME un consecutivo (AI-AAAA-NNNNNN, lo entrega el servidor). Sin llave de idempotencia: tras un fallo de red hay que revisar «mis actas» antes de abrir otra. */
  abrir: (lat: number, lon: number, precision_m: number | null) => pedir<Apertura>("abrir", { metodo: "POST", cuerpo: { lat, lon, ...(precision_m !== null ? { precision_m } : {}) } }),
  /** Rutas firmadas de subida: órdenes contiguos, una sola llamada con todas las fotos. La ruta no llega al navegador. */
  prepararSubida: (acta_id: string, fotos: { orden: number; tipo: string }[]) => pedir<PreparacionActa>("preparar_subida", { metodo: "POST", cuerpo: { acta_id, fotos } }),
  /** Registra (una transacción). Repetir con el mismo acta_id devuelve `repetido: true` con el mismo consecutivo. */
  registrar: (acta_id: string, contenido: Record<string, unknown>, constancia?: BloqueConstancia) => pedir<ConfirmacionActa>("registrar", { metodo: "POST", cuerpo: { acta_id, contenido, ...(constancia ? { constancia } : {}) }, timeoutMs: 60000 }),
  /** Foto del papel DESPUÉS del registro (`papel_pendiente`): la foto ya debe estar subida a la ruta preparada. Solo el autor; repetida → 409 «ya existe». */
  fotoPapel: (acta_id: string, orden: number) => pedir<{ acta_id: string; orden: number }>("foto_papel", { metodo: "POST", cuerpo: { acta_id, orden }, timeoutMs: 60000 }),
  /** SOLO las actas que abrió quien consulta (retomar una apertura, adjuntar el papel). */
  misActas: () => pedir<MisActas>("mis_actas"),
  /** Motivos para cancelar una apertura (catálogo del servidor). */
  motivosCancelacion: () => pedir<{ motivos: MotivoCancelacionActa[] }>("motivos_cancelacion"),
  /** Cancela una apertura SIN registrar (el autor la suya; supervisor y administrador, cualquiera). Evento de solo inserción; el consecutivo queda justificado. Repetir devuelve `repetido`. Lo registrado → 409. */
  cancelar: (acta_id: string, motivo_codigo: string, motivo_texto: string) =>
    pedir<CancelacionActa>("cancelar", { metodo: "POST", cuerpo: { acta_id, motivo_codigo, ...(motivo_texto.trim() ? { motivo_texto: motivo_texto.trim() } : {}) } }),
  /** SUPERVISIÓN: aperturas en curso, vencidas y (si se pide) canceladas con su motivo. */
  aperturasSinRegistrar: (incluirCanceladas: boolean) => pedir<AperturasSinRegistrar>("aperturas_sin_registrar", { metodo: "POST", cuerpo: { incluir_canceladas: incluirCanceladas, limite: 200 } }),

  /** Sube UNA foto a la URL firmada (PUT directo, sin el SDK de Supabase). Una foto que ya estaba (409) cuenta como subida.
   *  PENDIENTE de verificar con una subida real: el formato del cuerpo (FormData con el archivo, como lo manda el SDK) y los códigos de respuesta de Storage. */
  async subirFoto(urlSubida: string, foto: Blob): Promise<void> {
    const cuerpo = new FormData();
    cuerpo.append("cacheControl", "3600");
    cuerpo.append("", foto);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), TIEMPO_SUBIDA_MS);
    let res: Response;
    try {
      res = await fetch(urlSubida, { method: "PUT", body: cuerpo, headers: { "x-upsert": "false" }, signal: ctl.signal });
    } catch {
      throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0);
    } finally {
      clearTimeout(reloj);
    }
    if (res.ok) return;
    let cod = 0;
    try { cod = Number(((await res.json()) as { statusCode?: string | number }).statusCode ?? 0); } catch { /* sin JSON */ }
    const estado = res.status === 400 && cod === 409 ? 409 : res.status;
    if (estado === 409) return;                                                    // ya estaba subida (un intento anterior cuya respuesta se perdió)
    if (estado === 400 || estado === 401 || estado === 403 || estado === 404) throw new ErrorCampo("subida_vencida", "El permiso para subir la foto venció.", estado);
    if (estado >= 500) throw new ErrorCampo("servidor", "El servicio de fotos no está disponible. Intente de nuevo.", estado);
    throw new ErrorCampo("red", "No se pudo subir la foto: revise su señal.", 0);
  },
};
