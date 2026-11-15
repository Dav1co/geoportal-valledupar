import { supabase, FUNCTIONS_URL } from "../../lib/supabase";
import { clasificar, ErrorCampo } from "../apiCampo";
import type { ConfigConstancia } from "./logica";

// Cliente de la «Constancia por correo». Lectura de la configuración (cualquier capturista) y administración (solo administrador). Misma disciplina que apiFormatos: renueva la sesión una
// vez ante un 401, nunca registra cuerpos (hay correos y celulares) y no guarda nada en el navegador.
async function pedir<T>(funcion: "geoportal-acta" | "geoportal-campo", accion: string, metodo: "GET" | "POST", cuerpo?: unknown, query = ""): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/${funcion}`);
  url.searchParams.set("accion", accion);
  for (const [k, v] of new URLSearchParams(query)) url.searchParams.set(k, v);
  for (let intento = 0; intento < 2; intento++) {
    const { data } = await supabase.auth.getSession();
    const t = data.session?.access_token;
    if (!t) throw new ErrorCampo("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), 20000);
    let res: Response;
    try {
      res = await fetch(url.toString(), { method: metodo, signal: ctl.signal, headers: { Authorization: `Bearer ${t}`, ...(metodo === "POST" ? { "Content-Type": "application/json" } : {}) }, body: metodo === "POST" ? JSON.stringify(cuerpo ?? {}) : undefined });
    } catch {
      throw new ErrorCampo("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally {
      clearTimeout(reloj);
    }
    let resp: { error?: unknown } & Record<string, unknown> = {};
    try { resp = await res.json(); } catch { if (res.ok) throw new ErrorCampo("red", "No se pudo confirmar la respuesta del servidor.", 0); }
    if (res.ok) return resp as T;
    if (res.status === 401 && intento === 0) { const { error } = await supabase.auth.refreshSession(); if (!error) continue; }
    const mensaje = typeof resp.error === "string" ? resp.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorCampo(clasificar(res.status, mensaje), mensaje, res.status);
  }
  throw new ErrorCampo("sesion", "Su sesión venció.", 401);
}

export const DOCUMENTOS = [
  { codigo: "acta_inspeccion", nombre: "Acta de inspección técnica" },
  { codigo: "revision_previa", nombre: "Revisiones generales" },
  { codigo: "revision_pqr", nombre: "Revisión PQR" },
  { codigo: "instalacion_medidor", nombre: "Instalación de medidor" },
  { codigo: "instalacion_acometida", nombre: "Instalación de acometida" },
] as const;

export type EstadoConstancia = {
  texto: { version: number; borrador: boolean; texto: string } | null;
  documentos: { documento: string; habilitado: boolean; copias_internas: string[] }[];
  cola: Record<string, number>;
  fallos_ultimos_30_dias: number;
};

export const apiConstancia = {
  /** Configuración del documento para quien captura: si envía constancia y el texto de autorización vigente. */
  config: (documento: string): Promise<ConfigConstancia> =>
    documento === "acta_inspeccion" ? pedir("geoportal-acta", "config_constancia", "GET") : pedir("geoportal-campo", "config_constancia", "GET", undefined, `tipo=${encodeURIComponent(documento)}`),
  estado: () => pedir<EstadoConstancia>("geoportal-campo", "constancia_estado", "GET"),
  guardarConfig: (documento: string, habilitado: boolean, copias: string[]) => pedir<unknown>("geoportal-campo", "constancia_config", "POST", { documento, habilitado, copias }),
  nuevoTexto: (texto: string, borrador: boolean) => pedir<{ version: number; borrador: boolean }>("geoportal-campo", "constancia_texto", "POST", { texto, borrador }),
  depurar: (solo_contar: boolean) => pedir<{ envios: number; contactos_sin_envio: number; aplicado: boolean }>("geoportal-campo", "constancia_depurar", "POST", { solo_contar }),
};
