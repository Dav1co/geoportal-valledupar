import { pedir } from "../apiTecnica";
import { supabase, FUNCTIONS_URL } from "../../lib/supabase";

// Cliente de los «Cuadernos de análisis» (Corte 2 del geovisor técnico; Code B, 26-nov) en la Edge geoportal-analisis. Quién entra lo decide el SERVIDOR:
// leen el autor, los supervisores de Técnica y el administrador; edita solo el autor; el operador y quien no tiene permisos reciben 403. Aquí solo se refleja.

export type TipoMarca = "problema" | "activo" | "referencia" | "postit" | "mano" | "circulo" | "linea" | "zona";
export type Sistema = "acueducto" | "alcantarillado";
export type Categoria = "problema" | "propuesta" | "obra" | "observacion";
export type Estilo = { color?: string; grosor?: number };
export type GeomMarca = { type: "Point"; coordinates: [number, number] } | { type: "LineString"; coordinates: [number, number][] } | { type: "Polygon"; coordinates: [number, number][][] };
export type Marca = {
  id: string; version: number; creada_en_version: number; tipo: TipoMarca; subtipo: string | null; sistema: Sistema | null; categoria: Categoria | null; nota: string | null;
  estilo: Estilo | null; geom: GeomMarca; radio_m: number | null; conteo_predios: number | null; conteo_contratos: number | null; activo_codigo: string | null;
  sector: string | null; subsector: string | null;
};
export type Cambio = { op: "nueva" | "cambia" | "anula"; marca_id: string; tipo?: TipoMarca; subtipo?: string | null; sistema?: Sistema | null; categoria?: Categoria | null;
  nota?: string | null; estilo?: Estilo | null; geom?: GeomMarca; radio_m?: number | null; motivo?: string };
export type PerfilAnalisis = {
  email: string; admin: boolean; puede_crear: boolean;
  catalogo: { grupo: "problema" | "activo"; codigo: string; nombre: string; color: string | null; orden: number }[];
  sistemas: Record<Sistema, string>; categorias: Categoria[];
  topes: { capturas_por_cuaderno: number; captura_lado_max_px: number; captura_bytes_max: number; marcas_por_cuaderno: number; mano_vertices_max: number;
    zona_area_max_km2: number; zona_conteos_por_hora: number; cambios_por_guardado: number };
};
export type CuadernoLista = { id: string; titulo: string; descripcion: string | null; autor: string; autor_nombre: string | null; creado_en: string; version: number; actualizado_en: string;
  es_mio: boolean; archivado: boolean; marcas: number; capturas: number };
export type VistaCuaderno = { lon?: number; lat?: number; zoom?: number };
export type CapturaCuaderno = { id: string; titulo: string; extension: [number, number, number, number]; ancho: number; alto: number; bytes: number; creado_en: string };
export type Cuaderno = {
  id: string; modulo: string; autor: string; autor_nombre: string | null; creado_en: string; es_mio: boolean; archivado: boolean; version: number; ultima_version: number;
  titulo: string; descripcion: string | null; vista: VistaCuaderno | null; guardado_en: string; puede_editar: boolean;
  versiones: { version: number; creado_en: string; titulo: string }[]; marcas: Marca[]; capturas: CapturaCuaderno[];
  eventos: { tipo: string; motivo: string | null; creado_en: string }[];
};

const F = { funcion: "geoportal-analisis" };
export const apiAnalisis = {
  perfil: () => pedir<PerfilAnalisis>("perfil", F),
  cuadernos: (archivados: boolean) => pedir<{ cuadernos: CuadernoLista[] }>("cuadernos", { ...F, qs: { archivados: archivados ? "1" : "0" } }),
  cuaderno: (id: string, version?: number) => pedir<Cuaderno>("cuaderno", { ...F, qs: { id, ...(version ? { version: String(version) } : {}) } }),
  crear: (titulo: string, descripcion: string | null, vista: VistaCuaderno | null) => pedir<{ id: string; version: number }>("cuaderno_crear", { ...F, cuerpo: { titulo, descripcion, vista } }),
  /** Cada guardado es una versión nueva. 409 si otra pestaña guardó antes: hay que recargar. Puede tardar (conteo de zonas): 45 s. */
  guardar: (id: string, version_base: number, cambios: Cambio[], vista: VistaCuaderno | null) =>
    pedir<{ id: string; version: number; marcas: Marca[] }>("cuaderno_guardar", { ...F, cuerpo: { id, version_base, cambios, ...(vista ? { vista } : {}) }, timeoutMs: 45000 }),
  renombrar: (id: string, version_base: number, titulo: string, descripcion: string | null) =>
    pedir<{ id: string; version: number; marcas: Marca[] }>("cuaderno_guardar", { ...F, cuerpo: { id, version_base, titulo, descripcion: descripcion ?? "" } }),
  archivar: (id: string, motivo: string) => pedir<{ id: string; archivado: boolean }>("cuaderno_archivar", { ...F, cuerpo: { id, motivo } }),
  reabrir: (id: string, motivo: string) => pedir<{ id: string; archivado: boolean }>("cuaderno_reabrir", { ...F, cuerpo: { id, motivo } }),
  /** Solo los dos números. Tiene tope por hora (429). */
  zona: (geom: GeomMarca) => pedir<{ predios: number; contratos: number }>("cuaderno_zona", { ...F, cuerpo: { geom }, timeoutMs: 30000 }),
  capturaFirmar: (c: { id: string; titulo: string; extension: [number, number, number, number]; ancho: number; alto: number; bytes: number; sha256: string }) =>
    pedir<{ captura_id: string; url_subida: string; token: string; tipo: string }>("cuaderno_captura_firmar", { ...F, cuerpo: c }),
  capturaConfirmar: (captura_id: string) => pedir<{ captura_id: string; confirmada: boolean }>("cuaderno_captura_confirmar", { ...F, cuerpo: { captura_id } }),
  capturaAnular: (captura_id: string, motivo: string) => pedir<{ captura_id: string; anulada: boolean }>("cuaderno_captura_anular", { ...F, cuerpo: { captura_id, motivo } }),
  capturaUrl: (captura: string) => pedir<{ captura_id: string; titulo: string; url: string; expira_en: string }>("cuaderno_captura_url", { ...F, qs: { captura } }),
};

/** Sube el JPEG a la URL firmada (un solo archivo, esa ruta). */
export async function subirCaptura(url: string, jpg: Blob): Promise<void> {
  let r: Response;
  try {
    r = await fetch(url, { method: "PUT", headers: { "Content-Type": "image/jpeg", "x-upsert": "false" }, body: jpg });
  } catch {
    throw new Error("No hay conexión para subir la captura.");
  }
  if (!r.ok) throw new Error("No se pudo subir la captura.");
}

/** La lista de marcas en CSV (la arma la Edge: sin fórmulas, con «;» y BOM). Las notas salen tal cual: por eso el campo de nota avisa que no se escriban datos personales. */
export async function exportarCsv(id: string): Promise<Blob> {
  const { data } = await supabase.auth.getSession();
  const t = data.session?.access_token;
  if (!t) throw new Error("Su sesión venció.");
  let r: Response;
  try {
    r = await fetch(`${FUNCTIONS_URL}/geoportal-analisis?accion=cuaderno_exportar&formato=csv&id=${encodeURIComponent(id)}`, { headers: { Authorization: `Bearer ${t}` } });
  } catch {
    throw new Error("No hay conexión con el servidor.");
  }
  if (!r.ok) { let m = "No se pudo exportar el cuaderno."; try { const j = await r.json(); if (typeof j.error === "string") m = j.error; } catch { /* sin cuerpo */ } throw new Error(m); }
  return await r.blob();
}
