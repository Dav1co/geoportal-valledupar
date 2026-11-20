import { useEffect, useState } from "react";
import { FUNCTIONS_URL, supabase } from "../lib/supabase";
import "./aviso-sin-agua.css";

// Aviso «sin agua» en Campo (19-nov-2026): cuando se identifica un contrato (acta, formatos de actividad, reporte general y análisis de contrato) y el predio está
// dentro de un evento de suspensión ACTIVO (Corte 15), se avisa: «Sin prestación del servicio en este momento. Regreso estimado: <hora>», y se sugiere llamar al
// usuario y reprogramar si la actividad necesita agua. SOLO INFORMA: no bloquea guardar ni avanzar.
// Si la consulta falla, no existe todavía o tarda más de 2 s, NO se muestra nada y todo sigue normal (el aviso nunca estorba el trabajo de campo).
//
// RUTA PROVISIONAL: la hace el Code A. Mientras tanto la pantalla consulta `geoportal-redes?accion=evento_contrato&contrato=…` y espera la forma simulada
// {en_evento, codigo, tipo, desde, regreso_estimado, alcance}. Todo lo que depende de la ruta está en `consultarEventoContrato` y en el tipo `EventoContrato`:
// cuando el Code A entregue la forma final, se cambia solo aquí.

export type EventoContrato = { en_evento: boolean; codigo?: string | null; tipo?: string | null; desde?: string | null; regreso_estimado?: string | null; alcance?: string | null };
export const ESPERA_MAX_MS = 2000;
/** Un contrato «identificado»: solo dígitos (o el formato del acta), de 4 a 20 caracteres. Uno más corto todavía se está escribiendo. */
export const contratoConsultable = (c: string | null | undefined) => !!c && /^[A-Za-z0-9-]{4,20}$/.test(c.trim());

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
    return j && typeof j.en_evento === "boolean" ? j : null;
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
  if (!ev?.en_evento) return null;
  const regreso = ev.regreso_estimado ? horaClara(ev.regreso_estimado) : "";
  return (
    <div className="aviso-sin-agua" role="status" data-testid="aviso-sin-agua" data-evento={ev.codigo ?? ""}>
      <p className="aviso-sin-agua-tit"><strong>Sin prestación del servicio en este momento.</strong> {regreso ? <>Regreso estimado: <strong>{regreso}</strong>{regreso.endsWith(".") ? "" : "."}</> : "Todavía no hay hora estimada de regreso."}</p>
      <p className="aviso-sin-agua-sug">Llame al usuario y reprograme si la actividad necesita agua.</p>
    </div>
  );
}
