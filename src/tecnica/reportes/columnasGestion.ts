import type { ColumnaReporte } from "./catalogo";

// Columnas de las dos descargas que ya existían en el Dashboard distribución (Corte 4b; antes en DashboardGestion.tsx): su ruta («descarga» de geoportal-redes)
// entrega las filas sin columnas, así que aquí se conservan tal cual. Las descargas nuevas reciben sus columnas del servidor.
type Col = [clave: string, titulo: string, ancho: number, tipo?: "fechaHora" | "num"];
const COL_ITV: Col[] = [["codigo", "Código", 12], ["nace_de", "Nace de", 11], ["dano", "Daño que atiende", 13], ["tipo", "Tipo", 22], ["inversion_modo", "Inversión", 10],
  ["sistema", "Sistema", 14], ["activo", "Activo", 13], ["prefijo", "Prefijo", 8], ["tipo_activo", "Tipo de activo (nombre visible)", 24], ["no_identificado", "No identificado", 22],
  ["t_inicio", "Inicio", 17, "fechaHora"], ["t_fin", "Fin", 17, "fechaHora"], ["duracion_min", "Duración (min)", 12, "num"], ["ejecutor", "Ejecutor", 12], ["contratista", "Contratista", 22],
  ["contrato_orden", "Contrato u orden", 16], ["estado", "Estado", 11], ["resuelve_dano", "Resuelve el daño", 10], ["fotos", "Fotos", 7, "num"], ["documentos", "Documentos", 9, "num"],
  ["recursos", "Recursos", 13], ["aportantes", "Aportantes", 26], ["valor_total", "Valor total", 14, "num"], ["lat", "Latitud", 11, "num"], ["lon", "Longitud", 11, "num"],
  ["autor", "Registró", 28], ["registrado_en", "Registrado", 17, "fechaHora"]];
const COL_DAN: Col[] = [["codigo", "Código", 12], ["clase", "Clase", 8], ["tipo", "Tipo", 22], ["sistema", "Sistema", 14], ["activo", "Activo", 13], ["prefijo", "Prefijo", 8],
  ["tipo_activo", "Tipo de activo (nombre visible)", 24], ["no_identificado", "No identificado", 22], ["estado", "Estado", 12], ["t_inicio_dano", "Inicio del daño", 17, "fechaHora"],
  ["t_detectado", "Detectado", 17, "fechaHora"], ["t_inicio_reparacion", "Inicio de la reparación", 17, "fechaHora"], ["t_restablecido", "Servicio restablecido", 17, "fechaHora"],
  ["respuesta_min", "Respuesta (min)", 11, "num"], ["reparacion_min", "Reparación (min)", 11, "num"], ["total_min", "Total (min)", 11, "num"], ["tipo_rotura", "Rotura", 12],
  ["largo_afectado_m", "Largo afectado (m)", 11, "num"], ["presion_mca", "Presión (mca)", 10, "num"], ["usuarios_sin_servicio", "Usuarios sin servicio", 11, "num"], ["sector", "Sector", 8, "num"],
  ["riesgo", "Riesgo", 8], ["causa_clase", "Causa (clase)", 12], ["causa", "Causa", 18], ["tercero_tipo", "Tipo de tercero", 16], ["origen", "Origen", 11],
  ["intervenciones", "Intervenciones", 10, "num"], ["fotos", "Fotos", 7, "num"], ["lat", "Latitud", 11, "num"], ["lon", "Longitud", 11, "num"], ["autor", "Registró", 28],
  ["registrado_en", "Registrado", 17, "fechaHora"]];

const aColumna = ([clave, titulo, ancho, tipo]: Col): ColumnaReporte => ({ clave, titulo, ancho, tipo: tipo === "fechaHora" ? "fecha_hora" : tipo === "num" ? "numero" : "texto" });
export const COLUMNAS_GESTION: Record<"intervenciones" | "danos", ColumnaReporte[]> = { intervenciones: COL_ITV.map(aColumna), danos: COL_DAN.map(aColumna) };
