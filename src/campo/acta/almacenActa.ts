import { useSyncExternalStore } from "react";
import type { Apertura, BorradorActa, PreparacionActa, Precarga } from "./tipos";

// Almacén EN MEMORIA de los borradores del acta mientras dura la sesión de la página (el módulo vive lo que viva la pestaña). Así, volver a «Mis actas» o a otra entrada del área
// NO borra lo escrito ni las fotos ya tomadas. Este almacén no escribe nada en el navegador y una recarga lo vacía. Desde el 19-nov-2026 (decisión de David) el formulario guarda
// ADEMÁS un borrador local en IndexedDB (tecnica/borradorCampo.ts, enchufado en FormularioActa): lo escrito y las fotos del hallazgo, sin los nombres de las personas ni las fotos del
// acta física. Pertenece a UNA persona: si cambia el correo, se descarta.

export type FotoLocal = { id: string; tipo: string; blob: Blob; url: string; subida: boolean };
export type Entrada = {
  acta_id: string; consecutivo: string; abierto_en: string; vence_en: string; aviso_zona: boolean;
  borrador: BorradorActa; fotos: FotoLocal[];
  /** Preparación de subida vigente (URL firmadas): una vez pedida, las fotos quedan fijas (cada ruta corresponde a un orden y un tipo). */
  prep: PreparacionActa | null;
  /** Contrato ya verificado contra el catastro (para mostrar la precarga). */
  precarga: Precarga | null;
};
type Estado = { correo: string | null; entradas: Record<string, Entrada> };

let estado: Estado = { correo: null, entradas: {} };
const oyentes = new Set<() => void>();
const emitir = () => { estado = { ...estado, entradas: { ...estado.entradas } }; oyentes.forEach((f) => f()); };
const liberar = (e: Entrada) => e.fotos.forEach((f) => URL.revokeObjectURL(f.url));

export const almacenActa = {
  /** Se llama al montar la pantalla: si cambió la persona, se descartan (y se liberan) los borradores de la anterior. */
  alAcceder(correo: string) {
    if (estado.correo === correo) return;
    Object.values(estado.entradas).forEach(liberar);
    estado = { correo, entradas: {} };
  },
  obtener: (acta_id: string): Entrada | undefined => estado.entradas[acta_id],
  /** Un borrador NUEVO recién abierto (el consecutivo y el acta_id los entregó el servidor). */
  crear(a: Apertura, borrador: BorradorActa, precarga: Precarga | null) {
    estado.entradas[a.acta_id] = { acta_id: a.acta_id, consecutivo: a.consecutivo, abierto_en: a.abierto_en, vence_en: a.vence_en, aviso_zona: a.aviso_zona, borrador, fotos: [], prep: null, precarga };
    emitir();
  },
  /** Retomar una apertura que sigue vigente pero cuyo borrador se perdió (recarga): vacío, con los datos que sí conoce el servidor. */
  retomar(f: { acta_id: string; consecutivo: string; abierto_en: string; vence_en: string }, borrador: BorradorActa): Entrada {
    const e = estado.entradas[f.acta_id];
    if (e) return e;
    estado.entradas[f.acta_id] = { acta_id: f.acta_id, consecutivo: f.consecutivo, abierto_en: f.abierto_en, vence_en: f.vence_en, aviso_zona: false, borrador, fotos: [], prep: null, precarga: null };
    emitir();
    return estado.entradas[f.acta_id];
  },
  parchar(acta_id: string, cambio: (e: Entrada) => Entrada) {
    const e = estado.entradas[acta_id];
    if (!e) return;
    estado.entradas[acta_id] = cambio(e);
    emitir();
  },
  quitar(acta_id: string) {
    const e = estado.entradas[acta_id];
    if (!e) return;
    liberar(e);
    delete estado.entradas[acta_id];
    emitir();
  },
  /** ¿Hay fotos tomadas sin registrar? (para avisar antes de cerrar la página) */
  hayFotos: () => Object.values(estado.entradas).some((e) => e.fotos.length > 0),
};

export function useAlmacenActa(): Estado {
  return useSyncExternalStore((f) => { oyentes.add(f); return () => { oyentes.delete(f); }; }, () => estado, () => estado);
}
