import { pedir } from "./apiTecnica";

// Cliente del Corte 14 («Encontrar o reportar activo») en la Edge geoportal-redes. Quién entra y qué puede lo decide el SERVIDOR: administrador, supervisores,
// el operador de Técnica con el formulario asignado y quien tiene Formularios de campo en Comercial. Ningún dato de suscriptores; «quién» es el funcionario.

export type Servicio = "acueducto" | "alcantarillado";
export type TipoLevantar = "tuberia" | "valvula" | "hidrante" | "pozo" | "caja" | "otro";
export type InicioLevantar = { perfil: "admin" | "supervisor" | "operador" | "comercial"; area: "tecnica" | "comercial"; ficha_completa: boolean; reporta_dano?: boolean;
  radio_min_m: number; radio_max_m: number; duplicado_m: number; min_fotos: number; max_fotos: number;
  servicios: { codigo: Servicio; nombre: string }[]; tipos: { codigo: TipoLevantar; nombre: string }[] };
export type Geometria = { type: string; coordinates: unknown };
export type ActivoCerca = { n: number; codigo: string; prefijo: string; tipo: string; forma: "punto" | "linea" | "area"; material: string | null; diametro_mm: number | null;
  estado: string | null; proyectado: boolean; distancia_m: number; lat: number; lon: number; geometria: Geometria | null };
export type PuntoCerca = { codigo: string; servicio: Servicio; tipo: TipoLevantar; tipo_nombre: string; estado: string; registrado_en: string; distancia_m: number; lat: number; lon: number; posible_duplicado: boolean };
export type Cerca = { servicio: Servicio; radio_m: number; precision_m: number | null; senal_debil: boolean; tope_m: number; duplicado_m: number; total: number; activos: ActivoCerca[]; puntos: PuntoCerca[] };
export type FichaCorta = { codigo: string; prefijo: string; tipo: string; sistema: string; clase: string | null; nombre: string | null; material: string | null; diametro_mm: number | null;
  longitud_m: number | null; profundidad_m: number | null; fecha_instalacion: string | null; estado: string | null; codigo_anterior: string | null; sector: string | null;
  lat: number; lon: number; ficha_completa: boolean };
export type PreparacionLevantar = { punto_id: string; max_bytes_foto: number; tipo_mime: string; fotos: { n: number; ruta: string; url_subida: string; token: string }[] };
export type DatosLevantar = { servicio: Servicio; tipo: TipoLevantar; observacion: string | null; lat: number; lon: number; precision_m: number; fotos: { n: number; ruta: string }[]; no_es_duplicado?: boolean };
export type Duplicado = { codigo: string; servicio: Servicio; tipo: TipoLevantar; tipo_nombre: string; registrado_en: string; distancia_m: number; lat: number; lon: number };
export type LevantarCreado = { creado: true; repetido: boolean; id: string; codigo: string; registrado_en: string; precision_baja: boolean; estado: string }
  | { creado: false; duplicados: Duplicado[]; duplicado_m: number };
export type EstadoLevantar = "reportado" | "asignado" | "levantado" | "descartado";
export type PuntoLevantar = { codigo: string; servicio: Servicio; tipo: TipoLevantar; tipo_nombre: string; observacion: string | null; lat: number; lon: number; precision_m: number; precision_baja: boolean;
  registrado_en: string; area: "tecnica" | "comercial"; quien: string; estado: EstadoLevantar; estado_nombre: string; estado_desde: string; estado_motivo: string | null; estado_quien: string | null;
  activo: string | null; fotos: number; sector: string | null;
  /** Cierre casi automático: un activo NUEVO a pocos metros (posiblemente ya se levantó); lo confirma el supervisor. */
  propuesta?: { activo: string; tipo: string; distancia_m: number; cargado_en: string } | null };
export type PuntoHoja = { n: number; codigo: string; tipo_nombre: string; servicio: Servicio; registrado_en: string; lat: number; lon: number; precision_m: number; precision_baja: boolean;
  observacion: string | null; estado_nombre: string; sector: string | null; foto_url: string | null };
export type HojaLevantar = { generado_en: string; estado: string; total: number; recortada: boolean; puntos: PuntoHoja[] };
export type FiltroLevantar = "abiertos" | EstadoLevantar | "todos";
export type ListaLevantar = { estado: FiltroLevantar; conteos: Partial<Record<EstadoLevantar, number>>; abiertos: number; items: PuntoLevantar[]; siguiente: string | null };
export type FotoLevantar = { n: number; creado_en: string; url: string; expira_en: string };

const F = { funcion: "geoportal-redes" };
export const apiLev = {
  inicio: () => pedir<InicioLevantar>("levantar_inicio", F),
  /** Los activos cercanos a la persona. La posición va en el cuerpo y no se guarda. */
  cerca: (lat: number, lon: number, precision_m: number | null, servicio: Servicio) =>
    pedir<Cerca>("levantar_cerca", { ...F, cuerpo: { lat: Number(lat.toFixed(6)), lon: Number(lon.toFixed(6)), precision_m: precision_m === null ? null : Math.max(0.1, Number(precision_m.toFixed(1))), servicio } }),
  ficha: (codigo: string) => pedir<FichaCorta>("levantar_ficha", { ...F, qs: { codigo } }),
  preparar: (fotos: number) => pedir<PreparacionLevantar>("levantar_preparar", { ...F, cuerpo: { fotos } }),
  crear: (punto_id: string, datos: DatosLevantar) => pedir<LevantarCreado>("levantar_crear", { ...F, cuerpo: { punto_id, datos }, timeoutMs: 25000 }),
  lista: (estado: FiltroLevantar, despues_de: string | null) => pedir<ListaLevantar>("levantar_lista", { ...F, qs: { estado, ...(despues_de ? { despues_de } : {}) } }),
  evento: (codigo: string, tipo: "asignado" | "levantado" | "descartado" | "reabierto", o: { activo?: string | null; motivo?: string | null } = {}) =>
    pedir<{ codigo: string; estado: EstadoLevantar; estado_nombre: string; estado_desde: string; activo: string | null }>("levantar_evento",
      { ...F, cuerpo: { codigo, tipo, ...(o.activo ? { activo: o.activo } : {}), ...(o.motivo ? { motivo: o.motivo } : {}) } }),
  /** La hoja de levantamiento (PDF): los puntos en el orden del recorrido, con la primera foto. La descarga queda en la auditoría. */
  hoja: (estado: "abiertos" | "reportado" | "asignado") => pedir<HojaLevantar>("levantar_hoja", { ...F, cuerpo: { estado }, timeoutMs: 25000 }),
  fotos: (codigo: string) => pedir<{ codigo: string; fotos: FotoLevantar[] }>("levantar_fotos", { ...F, cuerpo: { codigo } }),
};

/** Nivel de zoom del minimapa para que quepa el círculo de búsqueda con margen: 15 m → 20 (la cuadra); 30 m → 19 (con las esquinas). Nunca más cerca de 20 ni más lejos de 18. */
export const ZOOM_MIN = 18, ZOOM_MAX = 20;
export function zoomParaRadio(radio_m: number): number { return radio_m <= 15 ? 20 : radio_m <= 30 ? 19 : 18; }
/** Distancia en metros entre dos posiciones cercanas (aproximación plana; sobra para decidir si la persona se movió). */
export function metrosEntre(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const dy = (a.lat - b.lat) * 110574, dx = (a.lon - b.lon) * 111320 * Math.cos((a.lat * Math.PI) / 180);
  return Math.sqrt(dx * dx + dy * dy);
}
/** Círculo (polígono GeoJSON) de `radio` metros alrededor de un punto: el de precisión del GPS y el de búsqueda. */
export function circulo(lat: number, lon: number, radio: number, pasos = 48): { type: "Polygon"; coordinates: number[][][] } {
  const c: number[][] = [];
  for (let i = 0; i <= pasos; i++) {
    const t = (i / pasos) * 2 * Math.PI;
    c.push([lon + (radio * Math.cos(t)) / (111320 * Math.cos((lat * Math.PI) / 180)), lat + (radio * Math.sin(t)) / 110574]);
  }
  return { type: "Polygon", coordinates: [c] };
}
export const metros = (m: number) => (m < 10 ? `${m.toFixed(1).replace(".", ",")} m` : `${Math.round(m)} m`);
