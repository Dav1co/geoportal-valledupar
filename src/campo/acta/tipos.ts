// Tipos de la pantalla del acta de inspección técnica. Reflejan lo que entrega la Edge `geoportal-acta` (contrato: edge_contrato_acta.md).
// El acta digital es el REGISTRO que acompaña al acta física firmada; aquí no hay firma, ni PDF, ni imágenes de firma.

export type ItemCatalogo = { codigo: string; nombre: string };
export type TipoHallazgo = ItemCatalogo & { nota: string | null; exige_texto: boolean; excluyente: boolean; habilita_accion: string | null };
export type CalidadAtendiente = ItemCatalogo & { exige_texto: boolean };
export type CampoAccion = { clave: string; etiqueta: string; tipo: "texto" | "numero" | "hora"; obligatorio: boolean };
export type AccionCorrectiva = ItemCatalogo & { campos: CampoAccion[] };
export type TipoFotoActa = ItemCatalogo & { exigida_con_irregularidad: boolean; acta_fisica: boolean };

export type LimitesActa = {
  min_fotos_irregularidad: number; min_fotos_sin_irregularidad: number; max_fotos: number; max_fotos_acta_fisica: number;
  max_bytes_foto: number; max_bytes_foto_acta_fisica: number; vigencia_apertura_horas: number; max_dias_acta_fisica_atras: number;
};

/** Respuesta de `formulario`: todo el formulario se dibuja desde aquí (no hay listas escritas en la pantalla). */
export type FormularioActa = {
  capacidades: { capturar: boolean; supervisar: boolean; administrar: boolean };
  aviso_registro: string;
  tipos_hallazgo: TipoHallazgo[]; calidades_atendiente: CalidadAtendiente[]; estados_medidor: ItemCatalogo[]; estados_sellos: ItemCatalogo[];
  diametros: ItemCatalogo[]; acciones: AccionCorrectiva[]; tipos_foto: TipoFotoActa[];
  limites: LimitesActa;
  zona: { lat_min: number; lat_max: number; lon_min: number; lon_max: number };
};

export type Precarga = {
  existe: boolean; direccion?: string | null; barrio?: string | null; barrio_en_lista?: boolean; estrato?: string | null; estrato_codigo_no_estandar?: boolean;
  uso?: string | null; predios_con_ese_contrato?: number;
};
export type PrediosCercanos = { hay_predios_cercanos: boolean; cantidad: number; contratos: string[]; distancia_m: number };
export type Apertura = { acta_id: string; consecutivo: string; abierto_en: string; vence_en: string; aviso_zona: boolean };

export type FotoPreparadaActa = { orden: number; tipo: string; url_subida: string; token: string };
export type PreparacionActa = { acta_id: string; fotos: FotoPreparadaActa[] };
export type ConfirmacionActa = { acta_id: string; consecutivo: string; version: number; registrado_en: string; repetido: boolean; aviso_zona: boolean };

export type SituacionActa = "abierta_en_curso" | "abierta_vencida" | "registrada";
/** Una fila de «mis actas»: SOLO las que abrió quien consulta. Sin rutas, coordenadas ni nombres. */
export type FilaMisActas = {
  acta_id: string; consecutivo: string; situacion: SituacionActa; abierto_en: string; vence_en: string; registrado_en: string | null;
  estado: string | null; estado_nombre: string | null; modo_identificacion: "con_contrato" | "sin_contrato" | null; contrato: string | null;
  papel_pendiente: boolean; fotos_papel: number; tiene_foto_papel: boolean; max_fotos_papel: number; puede_adjuntar_papel: boolean; siguiente_orden_foto: number | null;
};
export type MisActas = { filas: FilaMisActas[]; hay_mas: boolean; max_filas: number };

/** Hallazgo marcado en el formulario. `texto` solo se envía si el tipo lo exige («Otro»). */
export type HallazgoMarcado = { codigo: string; texto: string };
export type AccionMarcada = { codigo: string; detalle: Record<string, string> };

/** Todo lo que la persona escribe (en memoria durante la sesión). Los «sí/no» nacen en null: hay que contestarlos. */
export type BorradorActa = {
  modo: "con_contrato" | "sin_contrato"; contrato: string;
  direccion: string; barrio: string; estrato: string; uso: string; referencia: string;
  tieneMedidor: boolean | null; medidorSerie: string; marca: string; lectura: string; estadoMedidor: string; estadoSellos: string; serieSellos: string; diametro: string;
  hallazgos: HallazgoMarcado[]; descripcion: string; acciones: AccionMarcada[];
  nadieAtendio: boolean | null; derechosInformados: boolean | null; atNombre: string; atCalidad: string; atCalidadTexto: string; testigo: string;
  firmoOperario: boolean | null; firmoAtendiente: boolean | null; seNego: boolean | null;
  numeroFisico: string; fechaFisica: string; papelPendiente: boolean; constancia: string; observaciones: string;
};

/** De cada foto solo importa su tipo para las reglas (el archivo vive en memoria en la pantalla). */
export type FotoBasica = { tipo: string };
