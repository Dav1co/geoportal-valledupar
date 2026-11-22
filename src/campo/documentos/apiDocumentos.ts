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
  resultado: string | null; pdf: { estado: "generado" | "pendiente"; nombre: string | null; version: number | null }; derivadas: { total: number; pendientes: number };
  firmas: { operario: boolean; usuario: EstadoUsuario | null; testigo: boolean };
};
export type PaginaActas = { filas: FilaActa[]; siguiente: string | number | null };
export type Derivada = { id: number; actividad: string; actividad_nombre: string; origen: { registro_id: string; tipo: string; consecutivo: string | null; fecha: string } };
export type FilaDerivada = Derivada & { contrato: string | null; estado: string; atendida_por?: { registro_id: string; tipo: string; consecutivo: string | null; fecha: string } | null; motivo?: string | null };
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
  derivadas: (filtros: { estado?: string; contrato?: string; actividad?: string; desde?: string; hasta?: string; antes?: string | number; limite?: number }) =>
    pedir<{ filas: FilaDerivada[]; siguiente: string | number | null }>("campo", "derivadas", { filtros: sinVacios(filtros) }, 60000),
  actasAbiertas: (contrato: string) => pedir<{ actas: ActaAbierta[] }>("campo", "actas_abiertas", { contrato }),
  origenVincular: (registro_id: string, acta_id: string) => pedir<{ cambio?: boolean }>("campo", "origen_vincular", { registro_id, acta_id }),
};

/** Clave del formulario en el catálogo de documentos: «acta» o «tipo:<código>». */
export const claveFormulario = (tipo: string | null) => (tipo === null ? "acta" : `tipo:${tipo}`);

/** firma_guardar después de registrar responde 409 («la firma es definitiva»): pasa cuando un envío anterior sí llegó y solo se perdió la respuesta. Entonces se sigue con
 *  crear/registrar (que responde «repetido») sin repetir las firmas. */
export const esFirmaDefinitiva = (e: unknown) => e instanceof Error && "status" in e && (e as { status: number }).status === 409 && /definitiva/i.test(e.message);
