import { useEffect, useState } from "react";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import "./aviso-sin-agua.css";

// Aviso «sin agua» en Campo (19-nov-2026): cuando se identifica un contrato (acta, formatos de actividad, reporte general y análisis de contrato) y el predio está
// dentro de un evento de suspensión ACTIVO (Corte 15), se avisa: «Sin prestación del servicio en este momento. Regreso estimado: <hora>», y se sugiere llamar al
// usuario y reprogramar si la actividad necesita agua. SOLO INFORMA: no bloquea guardar ni avanzar.
// Si la consulta falla, no existe todavía o tarda más de 2 s, NO se muestra nada y todo sigue normal (el aviso nunca estorba el trabajo de campo).
//
// RUTA (Code A, rama `redes-aviso-evento-contrato`; forma en paquete_fase1/aviso_evento_contrato/ENTRADA_BITACORA.md): GET `geoportal-redes?accion=evento_contrato&contrato=…`
// (solo números, 1 a 15). Siempre trae 6 claves: contrato, consultado_en, ubicado, en_evento, evento (el más específico, o null) y otros_eventos (cuántos más lo
// tocan). Aquí se usan en_evento, evento.regreso_estimado y otros_eventos. Un 403 (perfil sin permiso: por ejemplo, quien solo tiene el acta) = sin aviso.

export type EventoDelContrato = { codigo: string; tipo: "dano" | "intervencion" | "suspension" | string; tipo_nombre: string; causa: string; zona: "sectores" | "circulo" | "planta" | "ciudad" | string;
  zona_nombre: string; desde: string; regreso_estimado: string | null; texto: string };
export type EventoContrato = { contrato: string; consultado_en: string; ubicado: boolean; en_evento: boolean; evento: EventoDelContrato | null; otros_eventos: number };
export const ESPERA_MAX_MS = 2000;
/** Un contrato «identificado»: de 4 a 15 dígitos (lo que acepta la ruta). Uno más corto todavía se está escribiendo; uno con letras (posible en el acta) no se consulta. */
export const contratoConsultable = (c: string | null | undefined) => !!c && /^\d{4,15}$/.test(c.trim());

/** Pregunta si el contrato está en un evento de suspensión activo. Nunca lanza: ante cualquier falla o si pasan 2 s, devuelve null. */
export async function consultarEventoContrato(contrato: string, senal?: AbortSignal): Promise<EventoContrato | null> {
  const ctl = new AbortController();
  const reloj = setTimeout(() => ctl.abort(), ESPERA_MAX_MS);
  const cortar = () => ctl.abort(); senal?.addEventListener("abort", cortar);
  try {
    const { data } = await supabase.auth.getSession();
    const t = data.session?.access_token; if (!t) return null;
    const url = new URL(`${FUNCTIONS_URL}/geoportal-redes`); url.searchParams.set("accion", "evento_contrato"); url.searchParams.set("contrato", contrato.trim());
    const r = await fetch(url.toString(), { headers: { Authorization: `Bearer ${t}` }, signal: ctl.signal });
    if (!r.ok) return null;
    const j = (await r.json()) as EventoContrato;
    // la forma de la ruta: se descarta cualquier otra cosa (y una respuesta de otro contrato)
    return j && typeof j.en_evento === "boolean" && (j.evento === null || typeof j.evento === "object") && String(j.contrato ?? "") === contrato.trim() ? j : null;
  } catch { return null; } finally { clearTimeout(reloj); senal?.removeEventListener("abort", cortar); }
}

/** «9:40 p. m.» si es hoy; si no, «20 nov, 9:40 a. m.» (hora de Bogotá). */
function horaClara(v: string): string {
  const d = new Date(v), z = { timeZone: "America/Bogota" } as const;
  if (Number.isNaN(d.getTime())) return "";
  const hora = d.toLocaleTimeString("es-CO", { ...z, hour: "numeric", minute: "2-digit" });
  const dia = (x: Date) => x.toLocaleDateString("es-CO", { ...z, year: "numeric", month: "2-digit", day: "2-digit" });
  return dia(d) === dia(new Date()) ? hora : `${d.toLocaleDateString("es-CO", { ...z, day: "numeric", month: "short" })}, ${hora}`;
}

/** El aviso. Consulta cuando el contrato cambia (con una espera corta mientras se escribe) y se dibuja solo si el predio está en un evento activo. */
export function AvisoSinAgua({ contrato, espera = 600 }: { contrato: string | null | undefined; espera?: number }) {
  const [ev, setEv] = useState<EventoContrato | null>(null);
  const c = (contrato ?? "").trim();
  useEffect(() => {
    setEv(null);
    if (!contratoConsultable(c)) return;
    const ctl = new AbortController();
    const t = window.setTimeout(() => { void consultarEventoContrato(c, ctl.signal).then((r) => { if (!ctl.signal.aborted) setEv(r); }); }, espera);
    return () => { window.clearTimeout(t); ctl.abort(); };
  }, [c, espera]);
  if (!ev?.en_evento || !ev.evento) return null;
  const regreso = ev.evento.regreso_estimado ? horaClara(ev.evento.regreso_estimado) : "";
  const otros = Number.isInteger(ev.otros_eventos) && ev.otros_eventos > 0 ? ev.otros_eventos : 0;
  return (
    <div className="aviso-sin-agua" role="status" data-testid="aviso-sin-agua" data-evento={ev.evento.codigo}>
      <p className="aviso-sin-agua-tit"><strong>Sin prestación del servicio en este momento.</strong> {regreso ? <>Regreso estimado: <strong>{regreso}</strong>{regreso.endsWith(".") ? "" : "."}</> : "Todavía no hay hora estimada de regreso."}
        {otros ? ` (y ${otros === 1 ? "1 evento más" : `${otros} eventos más`})` : ""}</p>
      <p className="aviso-sin-agua-sug">Llame al usuario y reprograme si la actividad necesita agua.</p>
    </div>
  );
}
