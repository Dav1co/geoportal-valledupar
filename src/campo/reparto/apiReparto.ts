import { supabase, FUNCTIONS_URL } from "../../lib/supabase";

// Cliente de la Edge geoportal-reparto (Reparto de facturas con XY). La Edge es la única puerta: aquí no hay lógica de permisos (la decide cada RPC).
// Nada de lo que devuelve trae nombre, dirección ni teléfono del suscriptor: solo códigos de contrato.

export type Perfil = { es_repartidor: boolean; es_supervisor: boolean };
export type RepartoPeriodo = { periodo: string; desde: string } | null;
export type CicloAnterior = { ciclo: string; rutas: { ruta: string; n: number }[]; reparto: RepartoPeriodo };
export type LoteVigente = { id: string; nombre_archivo: string; tipo: "ruta" | "ciclo"; ciclo: string; ruta: string | null; filas: number; cargado_en: string; reparto: RepartoPeriodo };
export type JornadaHoy = { id: number; origen: Origen; ciclo: string | null; ruta: string | null; nombre_archivo: string | null; total: number; entregadas: number; ultima: string | null;
  periodo_reparto: string | null; respaldo: boolean };
export type Contexto = { correo: string; es_repartidor: boolean; es_supervisor: boolean; es_admin: boolean; puede_calendario: boolean; hoy: string; periodo: string | null;
  anterior: CicloAnterior[]; nuevas: LoteVigente[]; mis_jornadas_hoy: JornadaHoy[]; parametros: { precision_mala_m: number; respaldo_dias: number; tope_filas_lote: number } };
export type Origen = "anterior" | "nueva" | "inventada";
export type Jornada = { id: number; fecha: string; origen: Origen; periodo: string | null; ciclo: string | null; ruta: string | null; lote_id: string | null; nombre_archivo: string | null;
  total: number; periodo_reparto: string | null; reparto_desde: string | null; respaldo: boolean; aviso: string | null };
export type Pendiente = { c: string; s: boolean };
export type Lista = { jornada: Jornada; entregadas_mias: number; siguiente: number; pendientes: Pendiente[]; ultimas: { id: number; contrato: string; consecutivo: number; hora: string }[]; retomada?: boolean };
export type Entrega = { entrega_id: number; consecutivo: number; contrato: string; registrado_en: string; repetida: boolean; precision_mala?: boolean; periodo_reparto?: string | null;
  respaldo?: boolean; aviso?: string | null };
export type FilaAvance = { jornada_id: number; repartidor: string; nombre: string | null; origen: Origen; periodo: string | null; ciclo: string | null; ruta: string | null;
  nombre_archivo: string | null; total: number; periodo_reparto: string | null; reparto_desde: string | null; respaldo: boolean; entregadas: number; anuladas: number;
  ultima: string | null; pendientes: number | null; saltadas: number | null };
export type EntregaDetalle = { id: number; contrato: string; consecutivo: number; orden_lectura: number | null; periodo_reparto: string | null; hora: string; lon: number; lat: number;
  precision_m: number; por_buscador: boolean; anulada: boolean; motivo_anulacion: string | null; anulada_por: string | null; anulada_en: string | null };
export type Detalle = { jornada: FilaAvance & { nombre: string | null }; entregas: EntregaDetalle[]; saltados: { contrato: string; orden_lectura: number }[]; pendientes: number };
export type Punto = { id: number; jornada_id: number; repartidor: string; contrato: string; consecutivo: number; hora: string; lon: number; lat: number; precision_m: number; anulada: boolean };
export type Mapa = { fecha: string; puntos: Punto[]; anuladas: number[]; ultimo_id: number | null };
export type LoteFila = { id: string; nombre_archivo: string; tipo: "ruta" | "ciclo"; ciclo: string; ruta: string | null; filas: number; autor: string; cargado_en: string; vigente: boolean;
  anulado: boolean; motivo_anulacion: string | null; anulado_por: string | null; anulado_en: string | null; jornadas: number };
export type CargaLote = { ok: true; lote_id: string; repetido: boolean; filas: number; sin_registro: number } | { ok: false; errores: string[] };
export type CalendarioReparto = { periodo: string; hoy: string; puede_cambiar: boolean; ciclos: { ciclo: number; reparto: string | null; en_reparto_hoy: RepartoPeriodo }[] };

export type TipoError = "red" | "sesion" | "horario" | "denegado" | "permiso" | "conflicto" | "validacion" | "servidor";
export class ErrorReparto extends Error {
  tipo: TipoError; status: number;
  constructor(tipo: TipoError, mensaje: string, status: number) { super(mensaje); this.name = "ErrorReparto"; this.tipo = tipo; this.status = status; }
}
const TEXTO_SIN_PERMISO = "No tiene permiso para esta acción.";
const TEXTO_DENEGADO = "Usuario no autorizado en el geoportal.";
export function clasificar(status: number, mensaje: string): TipoError {
  if (status === 401) return "sesion";
  if (status === 403) return mensaje === TEXTO_SIN_PERMISO ? "permiso" : mensaje === TEXTO_DENEGADO ? "denegado" : "horario";
  if (status === 409) return "conflicto";
  if (status >= 500) return "servidor";
  return "validacion";
}

async function token(): Promise<string | null> { const { data } = await supabase.auth.getSession(); return data.session?.access_token ?? null; }

async function pedir<T>(accion: string, o: { qs?: Record<string, string | null | undefined>; cuerpo?: unknown; timeoutMs?: number } = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-reparto`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of Object.entries(o.qs ?? {})) if (v !== null && v !== undefined && v !== "") url.searchParams.set(k, v);
  for (let intento = 0; intento < 2; intento++) {
    const t = await token();
    if (!t) throw new ErrorReparto("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), o.timeoutMs ?? 20000);
    let res: Response;
    try {
      res = await fetch(url.toString(), {
        method: o.cuerpo === undefined ? "GET" : "POST",
        headers: { Authorization: `Bearer ${t}`, ...(o.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) },
        body: o.cuerpo === undefined ? undefined : JSON.stringify(o.cuerpo), signal: ctl.signal, cache: "no-store",
      });
    } catch {
      throw new ErrorReparto("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally { clearTimeout(reloj); }
    let cuerpo: { error?: string } & Record<string, unknown> = {};
    try { cuerpo = await res.json(); } catch { if (res.ok) throw new ErrorReparto("red", "No se pudo confirmar la respuesta del servidor.", 0); }
    if (res.ok) return cuerpo as T;
    if (res.status === 401 && intento === 0) { const { error } = await supabase.auth.refreshSession(); if (!error) continue; }
    const mensaje = typeof cuerpo.error === "string" ? cuerpo.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorReparto(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorReparto("sesion", "Su sesión venció.", 401);
}

export const apiReparto = {
  perfil: () => pedir<Perfil>("perfil", { timeoutMs: 10000 }),
  contexto: () => pedir<Contexto>("contexto", { timeoutMs: 30000 }),
  empezar: (c: { origen: Origen; ciclo?: string; ruta?: string; lote_id?: string }) => pedir<Lista>("empezar", { cuerpo: c, timeoutMs: 30000 }),
  lista: (jornada_id: number) => pedir<Lista>("lista", { qs: { jornada_id: String(jornada_id) } }),
  // Un toque: el mismo id_cliente se reenvía igual en cada reintento (el servidor devuelve la misma entrega: no se duplica)
  entregar: (c: { jornada_id: number; contrato: string; lon: number | null; lat: number | null; precision_m: number | null; por_buscador: boolean; id_cliente: string }) =>
    pedir<Entrega>("entregar", { cuerpo: c, timeoutMs: 15000 }),
  anular: (entrega_id: number, motivo: string) => pedir<{ ok: boolean; entrega_id: number; contrato: string }>("anular", { cuerpo: { entrega_id, motivo } }),
  loteCargar: (c: { nombre: string; sha256: string; tipo: "ruta" | "ciclo"; ciclo: string; ruta?: string | null; filas: { contrato: string | null; orden?: string }[] }) =>
    pedir<CargaLote>("lote_cargar", { cuerpo: c, timeoutMs: 60000 }),
  loteAnular: (lote_id: string, motivo: string) => pedir<{ ok: boolean }>("lote_anular", { cuerpo: { lote_id, motivo } }),
  lotes: () => pedir<{ lotes: LoteFila[] }>("lotes"),
  avance: (fecha?: string) => pedir<{ fecha: string; filas: FilaAvance[] }>("avance", { qs: { fecha } }),
  detalle: (jornada_id: number) => pedir<Detalle>("detalle", { qs: { jornada_id: String(jornada_id) } }),
  mapa: (o: { fecha?: string; jornada_id?: number | null; despues?: number | null }) =>
    pedir<Mapa>("mapa", { qs: { fecha: o.fecha, jornada_id: o.jornada_id ? String(o.jornada_id) : null, despues: o.despues !== null && o.despues !== undefined ? String(o.despues) : null }, timeoutMs: 15000 }),
  calendario: (periodo?: string) => pedir<CalendarioReparto>("calendario", { qs: { periodo } }),
};

/** Texto para la persona según el tipo de error. */
export function avisoDeError(e: unknown): string {
  if (!(e instanceof ErrorReparto)) return "Ocurrió un error inesperado.";
  switch (e.tipo) {
    case "red": return "Sin conexión: no se guardó. Revise la señal y vuelva a intentar (lo que ya se envió no se duplica).";
    case "servidor": return "El servidor no pudo atender la solicitud en este momento. Intente de nuevo en un momento.";
    case "sesion": return "Su sesión venció. Vuelva a iniciar sesión.";
    case "permiso": return "Su cuenta no tiene permiso para el reparto de facturas.";
    case "denegado": return "Su cuenta no está autorizada en el geoportal.";
    default: return e.message;
  }
}
