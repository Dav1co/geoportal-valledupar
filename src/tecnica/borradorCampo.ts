// Borrador local de los formularios de campo: «Reportar daño o falla» y «Registrar intervención» (18-nov-2026); el acta de Comercial («Reportar posible pérdida»)
// y «Encontrar o reportar activo» (19-nov-2026).
// Lo escrito, lo elegido y los archivos (fotos con su sello ya puesto, y los PDF adjuntos) se guardan EN ESTE CELULAR mientras se llena el formulario, para que una
// recarga (la automática tras una publicación, o que el navegador cierre la pestaña) no los pierda. Al volver a abrir el formulario se ofrece continuar o descartar.
// · Todo va en IndexedDB (los archivos no caben en sessionStorage ni en localStorage). Dos registros por formulario y persona: los datos y los archivos (los archivos
//   solo se reescriben cuando cambian, no con cada tecla).
// · Es de UNA persona: la clave lleva una huella del correo (el correo no se guarda). Vence a las 24 horas. No guarda tokens ni claves.
// · Se borra al guardar con éxito, al descartarlo o al cancelar el formulario.
// · Si el almacenamiento falla (modo privado, sin espacio, bloqueado) o no responde en 2,5 s, NADA de aquí lanza un error ni deja esperando: el formulario sigue
//   funcionando, sin borrador.
import { useCallback, useEffect, useRef, useState } from "react";

export type ArchivoBorrador = { blob: Blob; etiqueta: string; nombre?: string };
export type BorradorCampo<D> = { guardado: number; datos: D; archivos: ArchivoBorrador[] };
type RegDatos = { clave: string; v: 1; guardado: number; datos: unknown };
type RegArchivos = { clave: string; v: 1; guardado: number; archivos: ArchivoBorrador[] };

const BASE = "geoportal-tec-borradores", ALMACEN = "borradores";
export const VIGENCIA_BORRADOR_MS = 24 * 60 * 60 * 1000;

/** Huella corta del correo (no reversible a simple vista; solo separa los borradores de dos personas en el mismo celular). */
function huella(correo: string): string {
  let h = 5381;
  for (const c of correo.trim().toLowerCase()) h = ((h << 5) + h + c.charCodeAt(0)) >>> 0;
  return h.toString(36);
}
const claveDe = (formulario: string, correo: string) => `${formulario}:${huella(correo)}`;

/** Tope de espera para abrir la base. En algunos celulares IndexedDB no responde nunca (ni éxito ni error): sin tope, el formulario se quedaría en «Cargando…». */
const ESPERA_ABRIR_MS = 2500;
function abrir(): Promise<IDBDatabase> {
  return new Promise((ok, mal) => {
    let resuelto = false;
    const reloj = setTimeout(() => { if (!resuelto) { resuelto = true; mal(new Error("IndexedDB no respondió")); } }, ESPERA_ABRIR_MS);
    const fin = (f: () => void) => { if (resuelto) return false; resuelto = true; clearTimeout(reloj); f(); return true; };
    try {
      const p = indexedDB.open(BASE, 1);
      p.onupgradeneeded = () => { if (!p.result.objectStoreNames.contains(ALMACEN)) p.result.createObjectStore(ALMACEN, { keyPath: "clave" }); };
      p.onsuccess = () => { if (!fin(() => ok(p.result))) p.result.close(); };      // llegó tarde: ya se siguió sin borrador
      p.onerror = () => { fin(() => mal(p.error)); }; p.onblocked = () => { fin(() => mal(new Error("bloqueado"))); };
    } catch (e) { fin(() => mal(e)); }
  });
}
/** Una transacción sobre el almacén; cierra la base al terminar. Rechaza si algo falla (quien llama lo atrapa). */
async function tx<T>(modo: IDBTransactionMode, f: (a: IDBObjectStore) => IDBRequest<T> | null): Promise<T | undefined> {
  const base = await abrir();
  try {
    return await new Promise<T | undefined>((ok, mal) => {
      const t = base.transaction(ALMACEN, modo); const r = f(t.objectStore(ALMACEN));
      t.oncomplete = () => ok(r ? r.result : undefined); t.onerror = () => mal(t.error); t.onabort = () => mal(t.error ?? new Error("abortada"));
    });
  } finally { base.close(); }
}

/** Lee el borrador vigente de esta persona. Los vencidos (de cualquiera) se borran de paso. Nunca lanza: sin almacenamiento, no hay borrador. */
export async function leerBorradorCampo<D>(formulario: string, correo: string, ahora = Date.now()): Promise<BorradorCampo<D> | null> {
  try {
    const todos = (await tx<(RegDatos | RegArchivos)[]>("readonly", (a) => a.getAll())) ?? [];
    const vencidos = todos.filter((r) => r?.v !== 1 || typeof r.guardado !== "number" || ahora - r.guardado > VIGENCIA_BORRADOR_MS).map((r) => r.clave);
    if (vencidos.length) await tx("readwrite", (a) => { vencidos.forEach((c) => a.delete(c)); return null; }).catch(() => {});
    const clave = claveDe(formulario, correo);
    const d = todos.find((r) => r.clave === clave && !vencidos.includes(r.clave)) as RegDatos | undefined;
    if (!d || typeof d.datos !== "object" || d.datos === null) return null;
    const f = todos.find((r) => r.clave === `${clave}:archivos` && !vencidos.includes(r.clave)) as RegArchivos | undefined;
    const archivos = (f?.archivos ?? []).filter((x) => x && x.blob instanceof Blob && typeof x.etiqueta === "string");
    return { guardado: d.guardado, datos: d.datos as D, archivos };
  } catch { return null; }
}
export async function guardarDatosBorrador(formulario: string, correo: string, datos: unknown): Promise<boolean> {
  try { await tx("readwrite", (a) => a.put({ clave: claveDe(formulario, correo), v: 1, guardado: Date.now(), datos } satisfies RegDatos)); return true; } catch { return false; }
}
export async function guardarArchivosBorrador(formulario: string, correo: string, archivos: ArchivoBorrador[]): Promise<boolean> {
  try { await tx("readwrite", (a) => a.put({ clave: `${claveDe(formulario, correo)}:archivos`, v: 1, guardado: Date.now(), archivos } satisfies RegArchivos)); return true; } catch { return false; }
}
export async function borrarBorradorCampo(formulario: string, correo: string): Promise<void> {
  try { const c = claveDe(formulario, correo); await tx("readwrite", (a) => { a.delete(c); a.delete(`${c}:archivos`); return null; }); } catch { /* sin almacenamiento no hay nada que borrar */ }
}

/** «18 de nov, 9:15 p. m.» para la pregunta «Tiene un borrador del …». */
export const fechaBorrador = (ts: number) => new Date(ts).toLocaleString("es-CO", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });

/** El borrador de un formulario abierto.
 *  · `oferta`: el borrador encontrado al abrir (hasta que la persona elija continuar o descartar); `leyendo` mientras se busca.
 *  · Mientras `activo` (ya se eligió y no se ha guardado), cada cambio de `datos` o de `archivos` se guarda solo, con una espera corta.
 *    Un formulario sin tocar no deja borrador: `toque` es la parte de los datos que solo cambia la persona (sin lo que el formulario propone solo, como el sector
 *    de la ubicación); mientras sea igual a la de apertura y no haya archivos, no se guarda nada.
 *  · `terminar()` lo borra (al guardar con éxito o al cancelar).
 *  · `opciones.sinOferta`: lo que hay en pantalla ya es el borrador (se volvió al formulario sin recargar): no se pregunta, se sigue guardando.
 *  · `opciones.apagado`: no se sabe de quién es la sesión: no se lee ni se guarda nada. */
export function useBorradorCampo<D>(formulario: string, correo: string, datos: D, archivos: ArchivoBorrador[], pausado: boolean, toque?: unknown, opciones?: { sinOferta?: boolean; apagado?: boolean }) {
  const sinLeer = !!opciones?.sinOferta || !!opciones?.apagado;
  const sinLeerInicial = useRef(sinLeer);       // se decide al abrir: lo que pase después en pantalla no cambia si se preguntó o no
  const [leyendo, setLeyendo] = useState(!sinLeer);
  const [oferta, setOferta] = useState<BorradorCampo<D> | null>(null);
  const [activo, setActivo] = useState(!!opciones?.sinOferta && !opciones?.apagado);
  const terminado = useRef(false);
  const json = JSON.stringify(datos);
  const jsonToque = toque === undefined ? json : JSON.stringify(toque);
  const inicial = useRef(jsonToque);            // lo que trae el formulario recién abierto, antes de tocar nada
  const tocado = useRef(false);

  useEffect(() => {
    if (sinLeerInicial.current) return;
    let vivo = true;
    void leerBorradorCampo<D>(formulario, correo).then((b) => { if (!vivo) return; if (b) setOferta(b); else setActivo(true); setLeyendo(false); });
    return () => { vivo = false; };
  }, [formulario, correo]);

  // datos: con cada cambio, tras una espera corta (y de inmediato si la página se oculta o se va)
  useEffect(() => {
    if (!activo || pausado || terminado.current) return;
    if (!tocado.current && jsonToque === inicial.current && archivos.length === 0) return;
    tocado.current = true;
    const escribir = () => { if (!terminado.current) void guardarDatosBorrador(formulario, correo, JSON.parse(json)); };
    const t = window.setTimeout(escribir, 400);
    const alOcultar = () => { if (document.visibilityState === "hidden") { window.clearTimeout(t); escribir(); } };
    document.addEventListener("visibilitychange", alOcultar); window.addEventListener("pagehide", escribir);
    return () => { window.clearTimeout(t); document.removeEventListener("visibilitychange", alOcultar); window.removeEventListener("pagehide", escribir); };
  }, [activo, pausado, json, jsonToque, archivos.length, formulario, correo]);

  // archivos: solo cuando cambia la lista (una foto nueva o quitada), de inmediato
  const firma = archivos.map((a) => `${a.etiqueta}:${a.blob.size}:${a.nombre ?? ""}`).join("|");
  const firmaGuardada = useRef("");
  useEffect(() => {
    if (!activo || pausado || terminado.current || firma === firmaGuardada.current) return;
    firmaGuardada.current = firma; tocado.current = true;
    void guardarArchivosBorrador(formulario, correo, archivos.map((a) => ({ blob: a.blob, etiqueta: a.etiqueta, nombre: a.nombre })));
    void guardarDatosBorrador(formulario, correo, JSON.parse(json));      // que nunca queden archivos sin sus datos
  }, [activo, pausado, firma]); // eslint-disable-line react-hooks/exhaustive-deps

  /** La persona eligió: continuar (quien llama ya aplicó `oferta` al formulario) o descartar. */
  const resolver = useCallback((continuar: boolean) => {
    if (continuar && oferta) { tocado.current = true; firmaGuardada.current = oferta.archivos.map((a) => `${a.etiqueta}:${a.blob.size}:${a.nombre ?? ""}`).join("|"); }
    else void borrarBorradorCampo(formulario, correo);
    setOferta(null); setActivo(true);
  }, [oferta, formulario, correo]);
  const apagado = !!opciones?.apagado;
  const terminar = useCallback(() => { terminado.current = true; if (!apagado) void borrarBorradorCampo(formulario, correo); }, [formulario, correo, apagado]);

  return { leyendo, oferta, resolver, terminar };
}
