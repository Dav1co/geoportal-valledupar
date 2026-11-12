import { supabase, FUNCTIONS_URL } from "../../lib/supabase";
import { clasificar, ErrorCampo, type Preparacion } from "../apiCampo";
import type { ConfirmacionFormato, CuerpoCrearFormato } from "./tipos";

// Extensión del cliente de geoportal-campo para los formatos del Paso D (apiCampo.ts no se toca). Reutiliza ErrorCampo y clasificar (mismos tipos de error y mismos avisos).
// Misma disciplina que apiCampo.pedir: renueva la sesión una vez ante un 401, distingue «sin respuesta» (reintentar con el mismo reporte_id es seguro) del resto, nunca registra cuerpos.
// Si algún día apiCampo exporta `pedir`, este archivo puede reducirse a dos líneas.

async function pedir<T>(accion: string, cuerpo: unknown, timeoutMs: number): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/geoportal-campo`);
  url.searchParams.set("accion", accion);
  for (let intento = 0; intento < 2; intento++) {
    const { data } = await supabase.auth.getSession();
    const t = data.session?.access_token;
    if (!t) throw new ErrorCampo("sesion", "Su sesión venció.", 401);
    const ctl = new AbortController();
    const reloj = setTimeout(() => ctl.abort(), timeoutMs);
    let res: Response;
    try {
      res = await fetch(url.toString(), { method: "POST", headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json" }, body: JSON.stringify(cuerpo), signal: ctl.signal });
    } catch {
      throw new ErrorCampo("red", ctl.signal.aborted ? "El servidor tardó demasiado en responder." : "No hay conexión con el servidor.", 0);
    } finally {
      clearTimeout(reloj);
    }
    let resp: { error?: string } & Record<string, unknown> = {};
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
    const mensaje = typeof resp.error === "string" ? resp.error : res.status === 401 ? "Su sesión venció." : "No se pudo completar la operación.";
    throw new ErrorCampo(clasificar(res.status, mensaje), mensaje, res.status);   // 429 → «limite», con el mensaje de la base (por ejemplo «podrá enviar otro dentro de 7 minutos»)
  }
  throw new ErrorCampo("sesion", "Su sesión venció.", 401);
}

export const apiFormatos = {
  /** Reserva el reporte_id y las rutas de subida. Con `tipo`, la base aplica el máximo de fotos de ese formato. */
  prepararSubida: (cantidad: number, tipo: string) => pedir<Preparacion>("preparar_subida", { cantidad, origen: "campo", tipo }, 20000),
  /** Crea el reporte (idempotente por reporte_id). La respuesta trae el consecutivo si el formato lo lleva. */
  crear: (cuerpo: CuerpoCrearFormato) => pedir<ConfirmacionFormato>("crear", cuerpo, 30000),
};
