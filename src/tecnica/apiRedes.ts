import { pedir } from "./apiTecnica";

// Cliente de la Edge geoportal-redes (Técnica fase 1, Corte 1b). Solo lectura. Lo que recibe cada perfil lo decide el SERVIDOR:
// el origen y los datos del modelo hidráulico solo llegan a supervisor y administrador; aquí solo se dibuja lo que venga.

export type ActivoCorto = {
  codigo: string; prefijo: string; tipo: string; clase?: string; estado: string; estado_codigo: string; retirado: boolean;
  codigo_anterior?: string; distancia_m?: number; sistema?: string;
};
export type SectorPlan = { sector: number; subsector?: string | null; codigo?: string; nombre?: string };
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
  // Corte 9a (Plan Maestro 2014): nada de esto es de la ficha oficial. El sector se calcula por geometría; «referencia» viene de tablas aparte, ya rotulada.
  sector_plan?: SectorPlan;
  referencia?: { titulo: string; origen?: string; advertencia?: string; filas: { r: string; v: string | number; u?: string }[] }[];
  por_verificar_motivo?: string;
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
export type IntervencionLista = { sector_plan?: SectorPlan | null; codigo: string; tipo: string; inversion_modo?: string | null; sistema: string; activo: string | null; no_identificado: string | null; dano: string | null;
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

// ---------- Corte 3b: la ficha como «perfil» (alias, placa, foto principal, galería y edición con versiones) ----------
export type FotoFirmada = { origen: "perfil" | "dano" | "intervencion"; codigo?: string | null; clase?: string; cuando: string; url: string; expira_en: string };
export type EdicionFicha = {
  valores: Record<string, string | number | null | undefined>;
  campos_tipo: { clave: string; rotulo: string; tipo: string; unidad?: string; valor?: string | number | null }[];
  lleva: { diametro_mm: boolean; capacidad: boolean; profundidad_m: boolean; clase: boolean; efecto: boolean };
  estados: Opcion[]; materiales: Opcion[]; clases: Opcion[]; efectos: Opcion[]; aportantes: Opcion[]; max_bytes_foto: number;
  puede_origen?: boolean;      // Corte 4a (§26.2): solo el administrador corrige el origen
};
export type Perfil = { codigo: string; alias?: string; placa?: string; sistema: string; geometria: string; perfil: "admin" | "supervisor" | "operador"; editable: boolean;
  foto_principal?: FotoFirmada; fotos?: number; edicion?: EdicionFicha };
export type Galeria = { codigo: string; total: number; principal: FotoFirmada | null; fotos: FotoFirmada[] };
export type CambiosFicha = Record<string, unknown>;

export const apiPerfil = {
  perfil: (codigo: string) => pedir<Perfil>("perfil", { ...F, qs: { codigo } }),
  galeria: (codigo: string) => pedir<Galeria>("galeria", { ...F, cuerpo: { codigo } }),
  editar: (codigo: string, cambios: CambiosFicha, motivo: string) =>
    pedir<{ codigo: string; version: number; version_nueva: boolean; cambios: { campo: string; rotulo: string; antes?: string | null; despues?: string | null }[] }>("ficha_editar", { ...F, cuerpo: { codigo, cambios, motivo } }),
  fotoPreparar: (codigo: string) => pedir<{ ruta: string; tipo_mime: string; max_bytes_foto: number; url_subida: string; token: string }>("foto_perfil_preparar", { ...F, cuerpo: { codigo } }),
  // búsqueda en toda la red: código del geoportal o de la capa, placa (o número de inventario) y alias
  buscar: (texto: string) => pedir<{ activos: (ActivoUbicado & { alias?: string; placa?: string })[] }>("activo_buscar", { ...F, qs: { texto } }),
  fotoFijar: (codigo: string, ruta: string, motivo: string) => pedir<{ codigo: string; repetido: boolean }>("foto_perfil_fijar", { ...F, cuerpo: { codigo, ruta, motivo } }),
};

// ---------- Corte 4a: Dashboard distribución (supervisor de distribución y administrador; el servidor lo vuelve a verificar) ----------
export type MiPerfilRedes = { perfil: "admin" | "supervisor" | "operador"; dashboard_redes: boolean; dashboard_ptap: boolean; geovisor?: boolean };   // geovisor: Corte 6a
export type DanoLista = { codigo: string; clase: "dano" | "falla"; tipo: string; sistema: string; activo: string | null; no_identificado: string | null; estado: string;
  t_detectado: string; riesgo: string; causa_clase: string; sector: number | null; sector_plan?: SectorPlan | null; origen: string; autor: string; total_s: number; fotos: number; intervenciones: number; tiene_tercero: boolean };
export type ReporteBot = { id: string; radicado: string; canal: string; tipo: string; lat: number | null; lon: number | null; direccion: string | null; descripcion: string | null;
  recibido_en: string; estado_bot: string; dano: string | null; fotos: number };
// Corte 9a: bandeja «Por verificar» (lo que dejó el Plan Maestro y los activos nuevos de una inversión)
export type GrupoVerificar = "estado" | "valvula" | "pozo" | "otros";
export type PorVerificar = { activo_id: number; codigo: string; prefijo: string; tipo: string; nombre: string | null; sistema: string; estado: string; grupo: GrupoVerificar; motivo: string; desde: string; lat: number; lon: number };
export type ListaPorVerificar = { grupos: { grupo: GrupoVerificar; n: number }[]; total: number; items: PorVerificar[]; siguiente: number | null };
export const apiDash = {
  porVerificar: (grupo: GrupoVerificar | null, despues_de: number | null) =>
    pedir<ListaPorVerificar>("por_verificar", { ...F, qs: { ...(grupo ? { grupo } : {}), ...(despues_de ? { despues_de: String(despues_de) } : {}) } }),
  activoVerificar: (codigo: string, motivo: string) => pedir<{ codigo: string; por_verificar: boolean }>("activo_verificar", { ...F, cuerpo: { codigo, motivo } }),
  miPerfil: () => pedir<MiPerfilRedes>("mi_perfil", F),
  danos: (filtro: "abiertos" | "todos" | "ocultos" | "no_identificados") => pedir<{ filtro: string; danos: DanoLista[] }>("danos", { ...F, qs: { filtro } }),
  danoEvento: (codigo: string, tipo: "ocultar" | "reincluir" | "reabrir", motivo: string) => pedir<{ codigo: string; estado: string }>("dano_evento", { ...F, cuerpo: { codigo, tipo, motivo } }),
  danoTercero: (codigo: string) => pedir<{ codigo: string; tercero: string }>("dano_tercero", { ...F, cuerpo: { codigo } }),
  intervencionEvento: (codigo: string, tipo: "ocultar" | "reincluir" | "anulada", motivo: string) =>
    pedir<{ codigo: string; estado: string; aviso?: string | null }>("intervencion_evento", { ...F, cuerpo: { codigo, tipo, motivo } }),
  reportesBot: (filtro: "pendientes" | "todos") => pedir<{ filtro: string; reportes: ReporteBot[] }>("reportes_bot", { ...F, qs: { filtro } }),
  reporteConvertir: (id: string, datos: Record<string, string | null>) => pedir<{ reporte: string; dano_codigo: string; estado_bot: string }>("reporte_convertir", { ...F, cuerpo: { id, datos } }),
  reporteDescartar: (id: string, motivo: string) => pedir<{ reporte: string; estado_bot: string }>("reporte_descartar", { ...F, cuerpo: { id, motivo } }),
  crearActivoBandeja: (clase: "intervencion" | "dano", codigo: string, prefijo: string, clase_activo: string | null, nombre: string | null, motivo: string) =>
    pedir<{ codigo: string; activo: string }>("crear_activo_bandeja", { ...F, cuerpo: { clase, codigo, prefijo, clase_activo, nombre, motivo } }),
};

// ---------- Corte 4b: gestión del Dashboard distribución (Personal, Catálogo, Parámetros, Gráficas, Descargas y Nodos por clasificar) ----------
export type Area = "planta" | "distribucion" | "ambas";
export type PersonaRedes = {
  email: string; nombre: string | null; perfil: "supervisor" | "operador"; dashboard_redes: boolean; dashboard_ptap: boolean; registro_tecnico: boolean;
  area: Area | null; cargo: string | null; cuadrilla: { id: number; nombre: string; activa: boolean } | null; geovisor: "si" | "no" | "por_permiso";
  formularios: string[]; activo_tecnica: boolean; ultimo_cambio: string | null;
};
export type PersonalRedes = { filtro: string; yo: string; formularios: { clave: string; nombre: string }[]; cuadrillas: { id: number; nombre: string }[]; personas: PersonaRedes[] };
export type EventoFicha = { id: number; persona: string; persona_nombre: string | null; tipo: "area" | "cargo" | "cuadrilla" | "geovisor"; valor: string | null; valor_nombre: string | null;
  motivo: string; autor: string; autor_nombre: string | null; creado_en: string };
export type TipoCatalogo = { prefijo: string; nombre: string; nombre_visible: string; alias: string | null; sistema: string; geometria: string; es_base: boolean; activo: boolean; vigentes: number };
export type CatalogoRedes = {
  puede_editar: boolean; puede_cuadrillas?: boolean; tipos: TipoCatalogo[];
  materiales: (Opcion & { activo: boolean })[]; estados: (Opcion & { cuenta_vigente: boolean })[]; contratistas: (Opcion & { activo: boolean })[];
  aportantes: (Opcion & { activo: boolean })[]; tipos_intervencion: (Opcion & { activo: boolean })[]; tipos_dano: (Opcion & { clase: string; activo: boolean })[];
  causas: (Opcion & { activo: boolean })[]; cuadrillas: { id: number; nombre: string; activa: boolean; personas: number }[];
};
export type EventoAlias = { id: number; alias: string | null; motivo: string; autor: string; creado_en: string };
export type Parametro = { clave: string; valor: number | null; unidad: string; minimo: number | null; maximo: number | null; estado: string; descripcion: string; entero: boolean; editable: boolean; ultimo_cambio: string | null };
export type ParametrosRedes = { puede_editar: boolean; parametros: Parametro[]; historial: { id: number; clave: string; antes: number | null; despues: number | null; motivo: string; autor: string; creado_en: string }[] };
export type GraficasRedes = {
  meses: string[]; desde: string;
  intervenciones_mes: { mes: string; tipo: string; tipo_nombre: string; sistema: string; n: number }[];
  valor_fuente: { aportante: string; nombre: string; valor: number | null; intervenciones: number; sin_valor: number }[];
  danos_causa: { clase: "dano" | "falla"; causa_clase: string; n: number; atendidos: number; respuesta_media_min: number | null; reparacion_media_min: number | null }[];
  top_correctivos: { activo: string; tipo: string | null; n: number }[];
};
export type Descarga = { conjunto: "intervenciones" | "danos"; desde: string; hasta: string; incluir_ocultos: boolean; total: number; generado_en: string; generado_por: string; filas: Record<string, unknown>[] };
// Corte 9a: lo que dice el modelo de cada nodo y la SUGERENCIA de clasificación (la confirma el administrador; nada se clasifica solo)
export type AccionSugerida = "crear" | "no_crear" | "dejar_nodo" | "revisar" | "sin_modelo";
export type SugerenciaNodo = { accion: Exclude<AccionSugerida, "sin_modelo">; texto: string; prefijo?: string; clase?: "nodo_calculo" | "propuesta_plan" };
export type NodoPorClasificar = { nodo_id: number; sistema: string; llave_modelo: string; nombre_modelo: string | null; nombre_visible: string; alias: string | null; lat: number; lon: number; tramos: number;
  tipo_modelo?: string; que_es?: string; sugerencia?: SugerenciaNodo };
export type NodoPreliminar = {
  nodo_id: number; sistema: "acueducto" | "alcantarillado"; llave_modelo: string; nombre_modelo?: string; nombre_visible: string; clase_nodo: string; lat: number; lon: number;
  sector?: SectorPlan; sugerencia?: SugerenciaNodo;
  modelo?: { tipo?: string; que_es?: string; zona?: string; nota?: string; estado_modelo?: string; cota_m?: number; demanda_exist_lps?: number; demanda_futura_lps?: number;
    pres_exist_mediana?: number; pres_exist_min?: number; pres_exist_max?: number; pres_futura_mediana?: number; pres_futura_min?: number; pres_futura_max?: number };
  tramos: { codigo: string; prefijo: string; nombre?: string; material?: string; diametro_mm?: number; longitud_m?: number; estado: string; extremo: "inicio" | "fin"; linea: GeoJSON.LineString | GeoJSON.MultiLineString }[];
};
export type NodosPorClasificar = {
  grupos: { grupo: string; n: number }[]; sugerencias?: { accion: AccionSugerida; n: number }[]; total: number; items: NodoPorClasificar[]; siguiente: number | null;
  tipos: { prefijo: string; nombre: string; sistema: string; pide_clase: boolean; clases: Opcion[] }[];
};

export const apiGestion = {
  personal: (buscar: string, filtro: string) => pedir<PersonalRedes>("personal", { ...F, qs: { buscar, filtro } }),
  personalFijar: (persona: string, tipo: EventoFicha["tipo"], valor: string | null, motivo: string) =>
    pedir<{ evento_id: number; antes: string | null; despues: string | null }>("personal_fijar", { ...F, cuerpo: { persona, tipo, valor, motivo } }),
  historial: (persona: string | null, despues_de: number | null) => pedir<{ total: number; eventos: EventoFicha[] }>("personal_historial", { ...F, cuerpo: { persona, despues_de } }),
  catalogo: () => pedir<CatalogoRedes>("catalogo", F),
  aliasFijar: (objeto: "tipo" | "nodo", ref: string, alias: string | null, motivo: string) => pedir<{ alias: string | null }>("alias_fijar", { ...F, cuerpo: { objeto, ref, alias, motivo } }),
  aliasHistorial: (objeto: "tipo" | "nodo", ref: string) => pedir<{ eventos: EventoAlias[] }>("alias_historial", { ...F, cuerpo: { objeto, ref } }),
  // Corte 5a (§28.2): el supervisor de distribución asigna o quita los formularios de distribución
  personalFormulario: (persona: string, formulario: string, asignar: boolean, motivo: string) =>
    pedir<{ persona: string; formulario: string; nombre: string; asignado: boolean }>("personal_formulario", { ...F, cuerpo: { persona, formulario, asignar, motivo } }),
  cuadrillaFijar: (id: number | null, nombre: string | null, activa: boolean | null, motivo: string) =>
    pedir<{ id: number; nombre: string; activa: boolean; nueva: boolean }>("cuadrilla_fijar", { ...F, cuerpo: { id, nombre, activa, motivo } }),
  parametros: () => pedir<ParametrosRedes>("parametros", F),
  parametroFijar: (clave: string, valor: number, motivo: string) => pedir<{ antes: number | null; despues: number; unidad: string }>("parametro_fijar", { ...F, cuerpo: { clave, valor, motivo } }),
  graficas: (meses: number) => pedir<GraficasRedes>("graficas", { ...F, qs: { meses: String(meses) } }),
  descarga: (conjunto: "intervenciones" | "danos", desde: string, hasta: string, incluir_ocultos: boolean) =>
    pedir<Descarga>("descarga", { ...F, cuerpo: { conjunto, desde, hasta, incluir_ocultos }, timeoutMs: 60000 }),
  nodos: (buscar: string, despues_de: number | null) => pedir<NodosPorClasificar>("nodos_por_clasificar", { ...F, qs: { buscar, ...(despues_de ? { despues_de: String(despues_de) } : {}) } }),
  nodoPreliminar: (nodo: number) => pedir<NodoPreliminar>("nodo_preliminar", { ...F, qs: { nodo: String(nodo) } }),
  nodoClasificar: (nodo: number, clase: "nodo_calculo" | "propuesta_plan" | "por_clasificar", motivo: string) =>
    pedir<{ nodo_id: number; nombre_modelo: string | null; clase_nodo: string }>("nodo_clasificar", { ...F, cuerpo: { nodo, clase, motivo } }),
  nodoCrearActivo: (nodo: number, prefijo: string, clase_activo: string | null, nombre: string | null, motivo: string) =>
    pedir<{ activo: string; tipo: string; nombre_modelo: string }>("nodo_crear_activo", { ...F, cuerpo: { nodo, prefijo, clase_activo, nombre, motivo } }),
};
