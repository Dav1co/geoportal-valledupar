// Recarga tras una publicación (18-nov-2026). Cada publicación cambia el nombre de los archivos que la página carga aparte (minimapas, mapas, dashboards,
// la hoja de cálculo). Una página abierta desde antes pide los nombres viejos, que ya no existen: sin esto, la pantalla quedaba en blanco.
// Regla: ante un error de carga de un módulo, la página se recarga SOLA UNA VEZ (deja una marca en sessionStorage para no entrar en bucle); si vuelve a
// fallar, muestra «Hay una versión nueva del geoportal. Toque para recargar» con un botón. Sin conexión no se recarga (el navegador dejaría su página de
// error y se perdería lo que hay en pantalla): se avisa y se espera a que la persona toque el botón.
// Además, un límite de errores general (LimiteDeErrores) y un manejador de errores sin atender: ningún error deja la pantalla en blanco.
import { Component, lazy, useEffect, useState, type ComponentType, type ReactNode } from "react";

export const TEXTO_VERSION = "Hay una versión nueva del geoportal. Toque para recargar.";
export const TEXTO_SIN_RED = "Sin conexión: no se pudo cargar esta parte. Cuando vuelva la señal, toque para recargar.";
export const TEXTO_ERROR = "Ocurrió un error en esta pantalla. Toque para recargar.";

const MARCA = "geoportal.recarga.v1";
const ESPERA_MS = 60_000;     // dos recargas automáticas nunca van a menos de un minuto, pase lo que pase
let recargando = false;

/** ¿Es el error de un módulo de la página que no se pudo traer? (Chrome, Firefox y Safari lo dicen distinto; Vite agrega el de las hojas de estilo.) */
export function esErrorDeCarga(e: unknown): boolean {
  const m = e instanceof Error ? `${e.name} ${e.message}` : typeof e === "string" ? e : String((e as { message?: unknown } | null)?.message ?? "");
  return /Failed to fetch dynamically imported module|error loading dynamically imported module|Importing a module script failed|Unable to preload CSS|Failed to load module script|ChunkLoadError/i.test(m);
}

/** La versión que está corriendo: el archivo de entrada de la página (su nombre cambia con cada publicación). */
function versionActual(): string {
  try { return document.querySelector<HTMLScriptElement>('script[type="module"][src]')?.src ?? ""; } catch { return ""; }
}
const sinRed = () => typeof navigator !== "undefined" && navigator.onLine === false;

/** Recarga la página si todavía no se recargó sola con esta versión. Devuelve si la recarga quedó en marcha.
 *  La marca guarda la versión que falló y la hora: tras recargar, si la versión es la misma (la recarga no trajo nada nuevo) ya no se recarga sola. */
export function recargarUnaVez(): boolean {
  if (recargando) return true;
  if (sinRed()) return false;
  try {
    const previa = JSON.parse(sessionStorage.getItem(MARCA) ?? "null") as { version?: string; ts?: number } | null;
    if (previa && (previa.version === versionActual() || Date.now() - Number(previa.ts ?? 0) < ESPERA_MS)) return false;
    sessionStorage.setItem(MARCA, JSON.stringify({ version: versionActual(), ts: Date.now() }));
  } catch { return false; }     // sin dónde guardar la marca no hay cómo evitar el bucle: no se recarga sola
  recargando = true;
  window.location.reload();
  return true;
}

/** El botón «Recargar»: recarga siempre (deja la marca, para que la página recargada no vuelva a recargarse sola). Sin conexión no hace nada. */
export function recargarAhora(): boolean {
  if (sinRed()) return false;
  try { sessionStorage.setItem(MARCA, JSON.stringify({ version: versionActual(), ts: Date.now() })); } catch { /* sin almacenamiento, igual se recarga: la pidió la persona */ }
  recargando = true;
  window.location.reload();
  return true;
}

/** El aviso con su botón. Va en el lugar de lo que no cargó (el resto de la pantalla, por ejemplo un formulario a medio llenar, sigue ahí). */
export function AvisoRecarga({ texto }: { texto?: string }) {
  const [desconectado, setDesconectado] = useState(sinRed());
  useEffect(() => {
    const ver = () => setDesconectado(sinRed());
    window.addEventListener("online", ver); window.addEventListener("offline", ver);
    return () => { window.removeEventListener("online", ver); window.removeEventListener("offline", ver); };
  }, []);
  return (
    <div className="aviso-recarga" role="alert" data-testid="aviso-recarga">
      <p>{desconectado ? TEXTO_SIN_RED : texto ?? TEXTO_VERSION}</p>
      <button type="button" className="aviso-recarga-boton" disabled={desconectado} onClick={() => { if (!recargarAhora()) setDesconectado(true); }}>Recargar</button>
    </div>
  );
}
const AvisoVersion = () => <AvisoRecarga />;

/** Como `lazy` de React, con la regla de recarga: si el módulo no carga, recarga una vez; si ya se recargó, deja el aviso en su lugar. */
export function lazyConRecarga<T extends ComponentType<any>>(cargar: () => Promise<{ default: T }>) {
  return lazy<T>(() => cargar().catch((e: unknown) => {
    if (!esErrorDeCarga(e)) throw e;
    if (recargarUnaVez()) return new Promise<{ default: T }>(() => { /* la página se está recargando: sigue el «Cargando…» */ });
    return { default: AvisoVersion as unknown as T };
  }));
}

/** Para los `import()` sueltos (la hoja de cálculo de las descargas): recarga una vez; si no se puede, el error lleva el texto claro. */
export async function importarConRecarga<M>(cargar: () => Promise<M>): Promise<M> {
  try { return await cargar(); } catch (e) {
    if (!esErrorDeCarga(e)) throw e;
    if (!recargarUnaVez() && !sinRed()) avisoGeneral(TEXTO_VERSION);
    throw new Error(sinRed() ? TEXTO_SIN_RED : "Hay una versión nueva del geoportal. Recargue la página y vuelva a intentarlo.");
  }
}

/** Aviso fijo al pie, fuera de React (para errores que nadie atendió). Uno solo a la vez. */
function avisoGeneral(texto: string) {
  if (recargando || document.getElementById("aviso-recarga-general")) return;
  const caja = document.createElement("div");
  caja.id = "aviso-recarga-general"; caja.className = "aviso-recarga aviso-recarga-fijo"; caja.setAttribute("role", "alert"); caja.dataset.testid = "aviso-recarga";
  const p = document.createElement("p"); p.textContent = texto;
  const b = document.createElement("button"); b.type = "button"; b.className = "aviso-recarga-boton"; b.textContent = "Recargar";
  b.addEventListener("click", () => { if (!recargarAhora()) p.textContent = TEXTO_SIN_RED; });
  caja.append(p, b); document.body.append(caja);
}

/** Manejador general: un módulo que no cargó y nadie atendió (una promesa suelta o un error global) sigue la misma regla. Se instala una vez, al arrancar. */
export function instalarManejadorDeCarga() {
  const atender = (e: unknown) => { if (esErrorDeCarga(e) && !recargarUnaVez()) avisoGeneral(sinRed() ? TEXTO_SIN_RED : TEXTO_VERSION); };
  window.addEventListener("unhandledrejection", (ev) => atender(ev.reason));
  window.addEventListener("error", (ev) => atender(ev.error ?? ev.message));
}

/** Límite de errores de toda la página: si una pantalla falla al dibujarse, en vez de quedar en blanco se muestra el aviso con el botón.
 *  Si fue un módulo que no cargó, primero la recarga única. */
export class LimiteDeErrores extends Component<{ children: ReactNode }, { fallo: "" | "carga" | "otro"; recargando: boolean }> {
  state = { fallo: "" as "" | "carga" | "otro", recargando: false };
  static getDerivedStateFromError(e: unknown) { return { fallo: esErrorDeCarga(e) ? "carga" as const : "otro" as const }; }
  componentDidCatch(e: unknown) {
    if (esErrorDeCarga(e) && recargarUnaVez()) this.setState({ recargando: true });
    else console.error(e);
  }
  render() {
    if (!this.state.fallo) return this.props.children;
    if (this.state.recargando) return <div className="pantalla-carga" role="status">Cargando…</div>;
    return <div className="aviso-recarga-pagina"><AvisoRecarga texto={this.state.fallo === "carga" ? TEXTO_VERSION : TEXTO_ERROR} /></div>;
  }
}
