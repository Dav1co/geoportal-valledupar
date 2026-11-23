import { supabase, FUNCTIONS_URL } from "../lib/supabase";
import type { TipoCarga } from "./lector";

// Cliente de la Edge Function geoportal-scrr (modo «Cartera»). La Edge es la única puerta: aquí no hay lógica de permisos (la decide el servidor en cada llamada).

export type ContextoScrr = {
  correo: string; es_admin: boolean;
  parametros: { lote_filas: number; tope_filas_archivo: number; comodin_contrato: string | number; carga_pausada: boolean; ventana_dias_historial: number;
                retencion_meses_pagos: number; tope_rechazo_pct: number; tope_salidas_suscripcion_pct: number };
  tipos_actividad: { id: number; codigo: string; nombre: string; seleccionable: boolean; admite_drastico: boolean }[];
  anomalias: { codigo: number; nombre: string; provisional: boolean }[];
};
export type TipoHoy = { tipo: TipoCarga; ultima_fecha_dato: string | null; aplicada_en: string | null; requerida_desde: string; al_dia: boolean; abierta: string | null };
export type CargasHoy = { hoy: string; tipos: TipoHoy[] };
export type CargaFila = { carga_id: string; tipo: TipoCarga; fecha_dato: string; version: number; archivo: string; filas: number; estado: string; creada_en: string; autor: string };
export type IniciarResp = { carga_id: string; lote_filas: number; lotes: number; version?: number; repetido: boolean };
export type ResumenServidor = Record<string, unknown> & { puede_aplicar: boolean; filas_en_paso: number; filas_esperadas: number; filas_rechazadas: number; pct_rechazadas: number;
  lotes_faltantes: number[]; causas_rechazo: Record<string, number>; lotes: number };
export type EstadoCarga = { carga_id: string; tipo: TipoCarga; fecha_dato: string; estado: string; filas: number; lotes_recibidos: number[]; lotes_aplicados: number[];
  resumen: Record<string, unknown> | null; respaldo_pendiente: number };

export type TipoError = "red" | "sesion" | "horario" | "denegado" | "permiso" | "pausa" | "conflicto" | "validacion" | "servidor";
export class ErrorScrr extends Error {
  tipo: TipoError; status: number;
  constructor(tipo: TipoError, mensaje: string, status: number) { super(mensaje); this.name = "ErrorScrr"; this.tipo = tipo; this.status = status; }
}
const TEXTO_SIN_PERMISO = "No tiene permiso para esta acción.";
const TEXTO_DENEGADO = "Usuario no autorizado en el geoportal.";
export function clasificar(status: number, mensaje: string): TipoError {
  if (status === 401) return "sesion";
  if (status === 403) return mensaje === TEXTO_SIN_PERMISO ? "permiso" : mensaje === TEXTO_DENEGADO ? "denegado" : "horario";
  if (status === 503) return "pausa";
  if (status === 409) return "conflicto";
  if (status >= 500) return "servidor";
  return "validacion";
}

async function token(): Promise<string | null> { const { data } = await supabase.auth.getSession(); return data.session?.access_token ?? null; }

async function pedir<T>(accion: string, o: { qs?: Record<string, string>; cuerpo?: unknown; timeoutMs?: number } = {}): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-scrr`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of Object.entries(o.qs ?? {})) url.searchParams.set(k, v);
  for (let intento = 0; intento < 2; intento++) {
    const t = await token();
    if (!t) throw new ErrorScrr("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), o.timeoutMs ?? 30000);
    let res: Response;
    try {
      res = await fetch(url.toString(), {
        method: o.cuerpo === undefined ? "GET" : "POST",
        headers: { Authorization: `Bearer ${t}`, ...(o.cuerpo === undefined ? {} : { "Content-Type": "application/json" }) },
        body: o.cuerpo === undefined ? undefined : JSON.stringify(o.cuerpo), signal: ctl.signal,
      });
    } catch {
      throw new ErrorScrr("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally { clearTimeout(reloj); }
    let cuerpo: { error?: string } & Record<string, unknown> = {};
    try { cuerpo = await res.json(); } catch { if (res.ok) throw new ErrorScrr("red", "No se pudo confirmar la respuesta del servidor.", 0); }
    if (res.ok) return cuerpo as T;
    if (res.status === 401 && intento === 0) { const { error } = await supabase.auth.refreshSession(); if (!error) continue; }
    const mensaje = typeof cuerpo.error === "string" ? cuerpo.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorScrr(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorScrr("sesion", "Su sesión venció.", 401);
}

export const apiScrr = {
  contexto: () => pedir<ContextoScrr>("contexto", { timeoutMs: 15000 }),
  cargasHoy: () => pedir<CargasHoy>("cargas_hoy"),
  cargas: (limite = 30) => pedir<{ cargas: CargaFila[] }>("cargas", { qs: { limite: String(limite) } }),
  iniciar: (c: { tipo: TipoCarga; fecha_dato: string; nombre: string; sha256: string; filas: number; reemplaza?: string | null; motivo?: string | null }) => pedir<IniciarResp>("carga_iniciar", { cuerpo: c }),
  estado: (id: string) => pedir<EstadoCarga>("carga_estado", { qs: { carga_id: id } }),
  // Un lote de 2.000 filas de cartera completa pesa ~1,2 MB: 60 s para señal débil. Reenviar el mismo lote es seguro (idempotente).
  lote: (carga_id: string, tipo: TipoCarga, lote: number, filas: unknown[]) => pedir<{ lote: number; repetido: boolean }>("carga_lote", { cuerpo: { carga_id, tipo, lote, filas }, timeoutMs: 60000 }),
  validar: (id: string) => pedir<ResumenServidor>("carga_validar", { cuerpo: { carga_id: id }, timeoutMs: 60000 }),
  aplicarLote: (id: string, lote: number) => pedir<Record<string, unknown> & { repetido: boolean }>("carga_aplicar", { cuerpo: { carga_id: id, lote }, timeoutMs: 60000 }),
  cerrar: (id: string, confirmar_salidas = false, motivo: string | null = null) =>
    pedir<{ ok: boolean; tipo: TipoCarga; fecha_dato: string; resultado: Record<string, unknown> }>("carga_aplicar", { cuerpo: { carga_id: id, confirmar_salidas, motivo }, timeoutMs: 60000 }),
  anular: (id: string, motivo: string) => pedir<{ ok: boolean }>("carga_anular", { cuerpo: { carga_id: id, motivo } }),
  revertir: (id: string, motivo: string) => pedir<{ filas_quitadas: number; filas_restauradas: number; pendientes: number }>("suscripcion_revertir", { cuerpo: { carga_id: id, motivo }, timeoutMs: 60000 }),
  vaciarPaso: () => pedir<{ cargas: number; filas: number }>("vaciar_paso", { cuerpo: {} }),
};

/** Texto para la persona según el tipo de error. */
export function avisoDeError(e: unknown): string {
  if (!(e instanceof ErrorScrr)) return "Ocurrió un error inesperado.";
  switch (e.tipo) {
    case "red": return "No hay señal o la conexión se cortó. Puede reintentar: lo ya enviado no se duplica.";
    case "servidor": return "El servidor no pudo atender la solicitud en este momento. Intente de nuevo en un momento.";
    case "sesion": return "Su sesión venció. Vuelva a iniciar sesión.";
    case "permiso": return "Su cuenta no tiene permiso para el modo Cartera.";
    case "denegado": return "Su cuenta no está autorizada en el geoportal.";
    default: return e.message;
  }
}
