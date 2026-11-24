import { pedir as pedirCampo } from "../apiCampo";
import { pedirActa } from "../acta/apiActa";

// Comercial 21-nov · Actas (paquete (b) del Code A): firmas con el dedo, PDF único, actas registradas y actividades derivadas. Las rutas son las mismas en las dos Edges:
// geoportal-campo para los formatos «tipo:…» y geoportal-acta para el acta de inspección (AI). Qué formularios llevan PDF y firmas lo dice el servidor (documentos_catalogo):
// aquí no hay lista fija. Nombres de quien atendió y del testigo, y las firmas, salen solo en pantalla con permiso y en el PDF interno: nunca en las descargas.
export type Esquema = "campo" | "acta";
export type ReglaFirma = "obligatoria" | "opcional" | "no";
export type ReglasFirmas = { operario: ReglaFirma; usuario: ReglaFirma; testigo: ReglaFirma };
export type DocumentoFormulario = { formulario: string; lleva_pdf: boolean; firmas: ReglasFirmas };
export type EstadoUsuario = "firmo" | "no_firmo" | "nadie_atendio";
export type Pdf = { nombre: string; sha256: string; bytes: number; version: number; url: string };
export type TipoActa = "acta" | "revision_previa" | "revision_pqr" | "instalacion_medidor" | "instalacion_acometida" | "suspension" | "corte" | "reinstalacion" | "reconexion_servicio";
export type FiltrosActas = { tipo?: string; desde?: string; hasta?: string; operario?: string; contrato?: string; barrio?: string; resultado?: string; derivadas?: "con" | "pendientes" | "atendidas"; antes?: string | number; limite?: number };
export type FilaActa = {
  registro_id: string; esquema: Esquema; tipo: string; tipo_nombre: string; consecutivo: string | null; numero_fisico: string | null; fecha: string; operario: string; contrato: string | null; barrio: string | null;
  /** Sin PDF: {estado: "pendiente"} (Edges de924af; la 2a249ef lo mandaba nulo, y también se acepta). `fecha` es el día; `registrado_en`, el instante (y el cursor). */
  resultado: string | null; pdf: { estado: "generado" | "pendiente"; nombre: string | null; version: number | null } | null; derivadas: { total: number; pendientes: number }; registrado_en?: string;
  firmas: { operario: boolean; usuario: EstadoUsuario | null; testigo: boolean };
};
export type PaginaActas = { filas: FilaActa[]; siguiente: string | number | null };
/** Origen de una derivada: un registro (revisión, PQR, instalación) o, desde el 23-nov, una observación del Análisis de contrato (aviso al supervisor). */
export type OrigenDerivada = { clase?: "registro" | "analisis"; registro_id?: string; tipo: string; tipo_nombre?: string; consecutivo?: string | null; fecha: string; operario?: string;
  observacion?: string; observacion_nombre?: string; texto?: string | null; direccion_correcta?: string | null; trae_datos?: boolean; datos_anulados?: boolean;
  aviso_id?: number | null; actividad_creada_id?: number | null; entregas_datos?: number; vistos?: number; ultimo_visto?: { en: string; autor: string } | null };
export type Derivada = { id: number; actividad: string; actividad_nombre: string; destinos?: string[]; destino_nombre?: string | null; antiguedad_dias?: number; origen: OrigenDerivada };
/** Datos de contacto de un aviso (Ley 1581): solo el supervisor de campo y el administrador; anulados, solo el motivo. No se guardan en el navegador. */
export type DatosAviso = { derivada_id: number; anulados: boolean; datos?: { nombre?: string; cedula?: string; telefono?: string; correo?: string; relacion?: string };
  motivo?: string; anulados_en?: string; anulados_por?: string; entregas?: number; anuladas?: number };
/** Una fila de «derivadas» (forma de la Edge real 2a249ef): el cierre dice si la atendió un registro (esquema y consecutivo) o se cerró a mano (atendida_fuera o anulada), quién y cuándo. */
export type FilaDerivada = Derivada & { contrato: string | null; estado: string; creada_en?: string;
  cierre: { en: string; tipo: string; autor: string; esquema: Esquema | null; consecutivo: string | null; registro_id: string | null; motivo?: string | null } | null };
export type ActaAbierta = { acta_id: string; consecutivo: string | null; fecha: string; numero_fisico?: string | null };

/** El cliente de la Edge que corresponde: geoportal-acta para el acta AI, geoportal-campo para los formatos. */
const pedir = <T>(esquema: Esquema, accion: string, cuerpo: unknown, timeoutMs?: number): Promise<T> =>
  esquema === "acta" ? pedirActa<T>(accion, { metodo: "POST", cuerpo, timeoutMs }) : pedirCampo<T>(accion, { cuerpo, timeoutMs });
const sinVacios = <T extends object>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== "" && v !== null)) as Partial<T>;

export const apiDocumentos = {
  catalogo: (esquema: Esquema) => pedir<{ formularios: DocumentoFormulario[] }>(esquema, "documentos_catalogo", {}),
  firmaGuardar: (esquema: Esquema, c: { registro_id: string; rol: "operario" | "usuario" | "testigo"; estado: EstadoUsuario | "quitar"; nombre?: string; imagen?: string }) =>
    pedir<{ rol: string; estado: string; sha256: string | null }>(esquema, "firma_guardar", sinVacios(c), 30000),
  pdfGenerar: (esquema: Esquema, registro_id: string) => pedir<Pdf>(esquema, "pdf_generar", { registro_id }, 90000),
  pdfUrl: (esquema: Esquema, registro_id: string) => pedir<Pdf>(esquema, "pdf_url", { registro_id }),
  /** La misma lectura en las dos Edges: geoportal-acta para el supervisor de actas, geoportal-campo para el supervisor de campo (el administrador, cualquiera). */
  actasRegistradas: (via: Esquema, f: FiltrosActas) => pedir<PaginaActas>(via, "actas_registradas", sinVacios(f), 60000),
  actasRegistradasDescarga: (via: Esquema, f: FiltrosActas & { despues?: string | number; limite?: number }) => pedir<PaginaActas>(via, "actas_registradas_descarga", sinVacios(f), 90000),
  derivadasAbiertas: (contrato: string, formulario: string) => pedir<{ derivadas: Derivada[] }>("campo", "derivadas_abiertas", { contrato, formulario }),
  derivadaAtender: (derivada_id: number, registro_id: string) => pedir<{ cambio?: boolean }>("campo", "derivada_atender", { derivada_id, registro_id }),
  derivadaCerrar: (derivada_id: number, tipo: "atendida_fuera" | "anulada", motivo: string) => pedir<{ cambio?: boolean }>("campo", "derivada_cerrar", { derivada_id, tipo, motivo }),
  derivadas: (filtros: { estado?: string; contrato?: string; actividad?: string; desde?: string; hasta?: string; antes?: string | number; limite?: number; origen?: "registro" | "analisis" }) =>
    pedir<{ filas: FilaDerivada[]; siguiente: string | number | null }>("campo", "derivadas", sinVacios(filtros), 60000),       // los filtros van en el cuerpo, planos
  actasAbiertas: (contrato: string) => pedir<{ actas: ActaAbierta[] }>("campo", "actas_abiertas", { contrato }),
  // Investigación y Análisis (23-nov): avisos del Análisis de contrato (solo geoportal-campo; supervisor de campo y administrador)
  avisoCrearActividad: (derivada_id: number, formulario: string) => pedir<{ aviso: FilaDerivada; actividad: FilaDerivada }>("campo", "aviso_crear_actividad", { derivada_id, formulario }),
  avisoDatos: (derivada_id: number) => pedir<DatosAviso>("campo", "aviso_datos", { derivada_id }),
  avisoDatosAnular: (derivada_id: number, motivo: string) => pedir<{ anulados: boolean }>("campo", "aviso_datos_anular", { derivada_id, motivo }),
  origenVincular: (registro_id: string, acta_id: string) => pedir<{ cambio?: boolean }>("campo", "origen_vincular", { registro_id, acta_id }),
};

/** Clave del formulario en el catálogo de documentos: «acta» o «tipo:<código>». */
export const claveFormulario = (tipo: string | null) => (tipo === null ? "acta" : `tipo:${tipo}`);

/** firma_guardar después de registrar responde 409 («la firma es definitiva»): pasa cuando un envío anterior sí llegó y solo se perdió la respuesta. Entonces se sigue con
 *  crear/registrar (que responde «repetido») sin repetir las firmas. */
export const esFirmaDefinitiva = (e: unknown) => e instanceof Error && "status" in e && (e as { status: number }).status === 409 && /definitiva/i.test(e.message);
