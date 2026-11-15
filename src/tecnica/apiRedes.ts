import { pedir } from "./apiTecnica";

// Cliente de la Edge geoportal-redes (Técnica fase 1, Corte 1b). Solo lectura. Lo que recibe cada perfil lo decide el SERVIDOR:
// el origen y los datos del modelo hidráulico solo llegan a supervisor y administrador; aquí solo se dibuja lo que venga.

export type ActivoCorto = {
  codigo: string; prefijo: string; tipo: string; clase?: string; estado: string; estado_codigo: string; retirado: boolean;
  codigo_anterior?: string; distancia_m?: number; sistema?: string;
};
export type Campo = { clave: string; rotulo: string; unidad?: string; valor?: string | number | boolean };
export type Ficha = {
  perfil: "admin" | "supervisor" | "operador";
  activo: {
    codigo: string; prefijo: string; tipo: string; tipo_catalogo: string; sistema: string; sistema_nombre: string; etapa: string; geometria: string;
    nombre?: string; clase?: string; estado: string; estado_codigo: string; cuenta_vigente: boolean; punteado: boolean; retirado: boolean; oculto: boolean; por_verificar: boolean;
    material?: string; fecha_instalacion?: string; barrio_sector?: string; codigo_anterior?: string; version: number; version_creada_en: string;
    lat: number; lon: number; campos: Campo[];
  };
  origen?: { origen: "emdupar" | "tercero" | "mixto"; aportante?: string; aportante_nombre?: string; tiene_soporte: boolean; nota?: string };
  modelo?: Record<string, unknown>;
  nodo?: { nombre_modelo?: string; nombre_visible: string; tramos: number };
  tramo?: { metodo: string; inicio?: { nombre: string; activo?: ActivoCorto }; fin?: { nombre: string; activo?: ActivoCorto } };
  contratos_enlazados?: number;
  componentes: ActivoCorto[]; parte_de: ActivoCorto[]; admite_componentes: boolean;
  epicrisis: { hechos: number; registro: number };
};
export type Cursor = { cuando: string; clase: string; ref_id: number };
export type EventoEpicrisis = { cuando: string; clase: string; ref_id: number; grupo: "hecho" | "registro"; resumen: string; estado?: string; autor?: string };
export type Epicrisis = { codigo: string; items: EventoEpicrisis[]; siguiente: Cursor | null };
export type Cercanos = { radio_m: number; sistema: string | null; activos: ActivoCorto[] };

const F = { funcion: "geoportal-redes" };
export const apiRedes = {
  activo: (codigo: string) => pedir<Ficha>("activo", { ...F, qs: { codigo } }),
  cercanos: (lat: number, lon: number, sistema: string | null, radio_m?: number) =>
    pedir<Cercanos>("activos_cerca", { ...F, cuerpo: { lat, lon, sistema, radio_m: radio_m ?? null, limite: 15 } }),
  epicrisis: (codigo: string, cursor?: Cursor | null) => pedir<Epicrisis>("epicrisis", { ...F, cuerpo: { codigo, cursor: cursor ?? null } }),
};

// ---------- Corte 2: daño o falla y minimapa ----------
export type Opcion = { codigo: string; nombre: string };
export type TipoDano = Opcion & { clase: "dano" | "falla"; sistemas: string[]; pide_rotura: boolean };
export type FormularioDano = {
  perfil: "admin" | "supervisor" | "operador"; sistemas: Opcion[]; tipos: TipoDano[]; roturas: Opcion[]; causas: Opcion[]; terceros: Opcion[]; marcas: Opcion[];
  reglas: { dias_atras_max: number; min_fotos: number; max_fotos: number; max_bytes_foto: number; max_horas_inicio: number; radio_cercanos_m: number; zoom_min: number; zoom_accesorios: number };
  hay_tabla_caudales: boolean; ahora: string;
};
export type ActivoUbicado = ActivoCorto & { lat: number; lon: number; sistema?: string };
export type NodoTramo = { rol: "inicio" | "fin"; nombre: string; lat: number; lon: number; activo?: ActivoCorto | null };
export type TramoNodos = { tramo: ActivoCorto & { sistema: string; longitud_m?: number; diametro_mm?: number }; nodos: NodoTramo[] };
export type FotoSubida = { n: number; ruta: string; url_subida: string; token: string };
export type PreparacionDano = { dano_id: string; max_bytes_foto: number; tipo_mime: string; fotos: FotoSubida[] };
export type DatosDano = Record<string, unknown> & { fotos: { n: number; momento: string; ruta: string }[] };
export type DanoGuardado = { id: string; codigo: string; registrado_en: string; estado: string; activo: string | null; fuera_de_zona: boolean; repetido: boolean;
  respuesta_s?: number | null; reparacion_s?: number | null; total_s?: number | null; perdida_estado?: string };

export const apiDano = {
  formulario: () => pedir<FormularioDano>("formulario_dano", F),
  preparar: (fotos: number) => pedir<PreparacionDano>("preparar_dano", { ...F, cuerpo: { fotos } }),
  // 30 s: un envío lento en señal débil no debe cortarse antes de tiempo; el reintento con el mismo dano_id no duplica.
  crear: (dano_id: string, datos: DatosDano) => pedir<DanoGuardado>("crear_dano", { ...F, cuerpo: { dano_id, datos }, timeoutMs: 30000 }),
  buscar: (texto: string, sistema: string) => pedir<{ activos: ActivoUbicado[] }>("activo_buscar", { ...F, qs: { texto, sistema } }),
  tramoNodos: (codigo: string) => pedir<TramoNodos>("tramo_nodos", { ...F, qs: { codigo } }),
};

/** Sube una foto a su URL firmada (PUT directo a Storage; la URL vale para esa ruta exacta). 409 = ya estaba subida (reintento). */
export async function subirFotoDano(url: string, foto: Blob): Promise<void> {
  let r: Response;
  const ctl = new AbortController();
  const reloj = setTimeout(() => ctl.abort(), 60000);
  try {
    r = await fetch(url, { method: "PUT", headers: { "Content-Type": "image/jpeg", "x-upsert": "false" }, body: foto, signal: ctl.signal });
  } catch {
    throw new Error("No se pudo subir la foto: revise su señal.");
  } finally {
    clearTimeout(reloj);
  }
  if (r.ok || r.status === 409) return;
  if (r.status === 400 || r.status === 401 || r.status === 403) throw new Error("vencida");
  throw new Error("El servicio de fotos no está disponible. Intente de nuevo.");
}
