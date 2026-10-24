// Borrador local de lo que la persona está escribiendo, para que NO se pierda si la sesión vence, se recarga la página o se cae la señal.
// Vive solo en este equipo (localStorage del navegador). No contiene correos, tokens ni claves: solo lo escrito, la planta, la hora y la clave del envío en curso.
// Se descarta si es de otra persona (uid), de otro día del servidor o si tiene más de 24 horas. La marca «ya enviada» caduca a los 45 minutos.

/** «Ya enviada»: hora de la muestra enviada (para mostrar) y marca de tiempo del envío (para que CADUQUE). */
export type MarcaEnviada = { hora: string; ts: number };

export type Borrador = {
  v: 2; uid: string; dia: string; guardado: number;
  planta: string | null; hora: string;
  textos: Record<string, string>;          // clave: «codigo» (para las dos plantas) o «codigo@planta» (por planta)
  claveEnvio: string;
  comunEnviada: MarcaEnviada | null;       // el bloque «Para las dos plantas» ya se envió; se pliega solo mientras la marca esté vigente
};

const PREFIJO = "geoportal.tec.borrador.v2.";
const VIGENCIA_MS = 24 * 60 * 60 * 1000;
/** Plazo del plegado del bloque «Para las dos plantas»: pasado este tiempo reaparece completo (la calidad del agua cruda cambia). */
export const PLAZO_COMUN_MS = 45 * 60 * 1000;

/** ¿Sigue vigente la marca «ya enviada»? Una marca ilegible, futura o vencida no vale. */
export function comunVigente(m: MarcaEnviada | null | undefined, ahora = Date.now()): m is MarcaEnviada {
  return !!m && typeof m.ts === "number" && Number.isFinite(m.ts) && m.ts <= ahora + 60_000 && ahora - m.ts < PLAZO_COMUN_MS;
}

const tieneTexto = (t: Record<string, string>) => Object.values(t).some((x) => typeof x === "string" && x.trim() !== "");

/** Lee el borrador de esta persona y de hoy. La marca «ya enviada» vencida se descarta; si con ello no queda nada escrito, el borrador entero se borra. */
export function leerBorrador(formulario: string, uid: string, dia: string, ahora = Date.now()): Borrador | null {
  try {
    const crudo = localStorage.getItem(PREFIJO + formulario);
    if (!crudo) return null;
    const b = JSON.parse(crudo) as Borrador;
    if (b?.v !== 2 || b.uid !== uid || b.dia !== dia || ahora - b.guardado > VIGENCIA_MS) return null;
    const comun = comunVigente(b.comunEnviada, ahora) ? b.comunEnviada : null;
    if (!tieneTexto(b.textos ?? {}) && comun === null) { borrarBorrador(formulario); return null; }
    const limpio = { ...b, textos: b.textos ?? {}, comunEnviada: comun };
    if (b.comunEnviada && comun === null) localStorage.setItem(PREFIJO + formulario, JSON.stringify(limpio));   // la marca vencida no se conserva en el almacenamiento
    return limpio;
  } catch {
    return null;
  }
}

export function guardarBorrador(formulario: string, b: Omit<Borrador, "v" | "guardado">, ahora = Date.now()) {
  try {
    // Un borrador sin nada escrito y sin marca vigente no se conserva.
    if (!tieneTexto(b.textos) && !comunVigente(b.comunEnviada, ahora)) { localStorage.removeItem(PREFIJO + formulario); return; }
    localStorage.setItem(PREFIJO + formulario, JSON.stringify({ ...b, comunEnviada: comunVigente(b.comunEnviada, ahora) ? b.comunEnviada : null, v: 2, guardado: ahora }));
  } catch { /* almacenamiento lleno o bloqueado: la pantalla sigue funcionando sin borrador */ }
}

export function borrarBorrador(formulario: string) {
  try {
    localStorage.removeItem(PREFIJO + formulario);
  } catch { /* nada */ }
}

/** Clave única de un envío (se reutiliza si hay que reintentar). */
export function nuevaClaveEnvio(): string {
  const c = globalThis.crypto;
  if (c?.randomUUID) return c.randomUUID();
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}
