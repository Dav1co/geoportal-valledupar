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
  respuesta_s?: number | null; reparacion_s?: number | null; total_s?: number | null; perdida_estado?: string; sin_evidencia?: boolean };

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

// ---------- Corte 3a: registrar intervención; supervisor (lista, recursos, no identificados y «asociar activo») ----------
export type TipoIntervencion = Opcion & { admite_dano: boolean; es_inversion: boolean };
export type TipoNuevo = { prefijo: string; nombre: string; sistema: string; geometria: "punto" | "linea"; clases: Opcion[]; clase_obligatoria: boolean; lleva_diametro: boolean };
export type FormularioIntervencion = {
  perfil: "admin" | "supervisor" | "operador"; sistemas: Opcion[]; tipos: TipoIntervencion[]; aportantes: Opcion[]; contratistas: Opcion[]; unidades: Opcion[];
  tipos_nuevo: TipoNuevo[]; materiales: Opcion[];
  reglas: { dias_atras_max: number | null; max_horas: number | null; min_fotos: number; puede_sin_fotos: boolean; pone_valores: boolean; max_fotos: number; max_documentos: number;
            max_bytes_foto: number; max_bytes_documento: number; max_horas_inicio: number; radio_cercanos_m: number; radio_danos_m: number; max_tambien: number;
            max_materiales: number; zoom_min: number; zoom_accesorios: number };
  ahora: string;
};
export type DanoAbierto = { codigo: string; clase: "dano" | "falla"; tipo: string; activo: string | null; no_identificado: string | null; t_detectado: string; estado: string;
  mismo_activo: boolean; distancia_m: number };
export type ArchivoSubida = { n: number; ruta: string; tipo_mime: string; url_subida: string; token: string };
export type PreparacionIntervencion = { intervencion_id: string; max_bytes_foto: number; max_bytes_documento: number; fotos: ArchivoSubida[]; documentos: ArchivoSubida[] };
export type Fuente = { aportante: string; entidad?: string | null; valor?: number | null; porcentaje?: number | null; soporte?: string | null };
export type IntervencionGuardada = { id: string; codigo: string; registrado_en: string; estado: string; activo: string | null; activo_creado: boolean; dano: string | null;
  dano_estado?: string | null; recursos?: string; sin_evidencia: boolean; fuera_de_zona: boolean; duracion_s?: number; repetido: boolean };
export type IntervencionLista = { codigo: string; tipo: string; inversion_modo?: string | null; sistema: string; activo: string | null; no_identificado: string | null; dano: string | null;
  t_fin: string; ejecutor: string; contratista: string | null; autor: string; recursos: "completos" | "por_completar"; sin_evidencia: boolean; fotos: number; estado: string;
  fuentes: (Fuente & { n: number; aportante_nombre: string })[] };
export type NoIdentificado = { clase: "intervencion" | "dano"; codigo: string; sistema: string; que_es: string; resumen: string; estado: string; cuando: string; autor: string;
  lat: number; lon: number; propuestos: (ActivoCorto & { distancia_m: number })[] };

export const apiItv = {
  formulario: () => pedir<FormularioIntervencion>("formulario_intervencion", F),
  danosAbiertos: (sistema: string, ref: { activo: string } | { lat: number; lon: number }) => pedir<{ radio_m: number; danos: DanoAbierto[] }>("danos_abiertos", { ...F, cuerpo: { sistema, ...ref } }),
  preparar: (fotos: number, documentos: number) => pedir<PreparacionIntervencion>("preparar_intervencion", { ...F, cuerpo: { fotos, documentos } }),
  // 30 s, como el daño: el reintento con el mismo intervencion_id no duplica.
  crear: (intervencion_id: string, datos: Record<string, unknown>) => pedir<IntervencionGuardada>("crear_intervencion", { ...F, cuerpo: { intervencion_id, datos }, timeoutMs: 30000 }),
  lista: (filtro: "recientes" | "recursos_por_completar") => pedir<{ filtro: string; intervenciones: IntervencionLista[] }>("intervenciones", { ...F, qs: { filtro } }),
  recursos: (codigo: string, fuentes: Fuente[], motivo: string | null) => pedir<{ codigo: string; version: number; recursos: string }>("intervencion_recursos", { ...F, cuerpo: { codigo, fuentes, motivo } }),
  noIdentificados: () => pedir<{ radio_m: number; pendientes: number; items: NoIdentificado[] }>("no_identificados", F),
  asociar: (clase: "intervencion" | "dano", codigo: string, activo: string, motivo: string) => pedir<{ clase: string; codigo: string; activo: string }>("asociar_activo", { ...F, cuerpo: { clase, codigo, activo, motivo } }),
};

/** Sube un archivo (foto JPEG o documento PDF) a su URL firmada, con su tipo. Mismo contrato que subirFotoDano. */
export async function subirArchivo(url: string, archivo: Blob, tipo: "image/jpeg" | "application/pdf"): Promise<void> {
  let r: Response;
  const ctl = new AbortController();
  const reloj = setTimeout(() => ctl.abort(), 90000);
  try {
    r = await fetch(url, { method: "PUT", headers: { "Content-Type": tipo, "x-upsert": "false" }, body: archivo, signal: ctl.signal });
  } catch {
    throw new Error(tipo === "application/pdf" ? "No se pudo subir el documento: revise su señal." : "No se pudo subir la foto: revise su señal.");
  } finally {
    clearTimeout(reloj);
  }
  if (r.ok || r.status === 409) return;
  if (r.status === 400 || r.status === 401 || r.status === 403) throw new Error("vencida");
  throw new Error("El servicio de archivos no está disponible. Intente de nuevo.");
}
