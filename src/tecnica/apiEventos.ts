import { pedir } from "./apiTecnica";

// Cliente del Corte 15 «Evento de suspensión» en la Edge geoportal-redes (la lógica es del Code A; la especificación de rutas está en
// paquete_fase1/corte15/ENTRADA_BITACORA.md). Un evento agrupa los reportes de falta de agua de una zona (por sectores, por un círculo o total), los controla y
// los cierra en bloque. Quién puede cada cosa lo decide el SERVIDOR. Solo conteos de contratos: sin nombres; los usuarios sensibles van por contrato y tipo.

export type Alcance = "sectores" | "circulo" | "total";
export type OrigenReporte = "bot" | "l116" | "dano" | "campo";
export type ConteoReportes = { total: number; bot: number; l116: number; danos: number; campo: number };
export type ZonaGeo = { type: "MultiPolygon" | "Polygon"; coordinates: unknown } | null;
/** De dónde salió el evento (corte «origen y tubos», 20-nov): el daño o la intervención, la causal de un trabajo o, en los viejos que no tenían nada, «no registrado». */
export type OrigenEvento = { codigo: "dano" | "intervencion" | "trabajo" | "no_registrado"; nombre: string };
export type CodigoNombre = { codigo: string; nombre: string };
export type Evento = {
  origen?: OrigenEvento; causal?: CodigoNombre | null; tubos?: CodigoNombre[];      // del corte «origen y tubos» (un servidor anterior no los trae)
  codigo: string; estado: "abierto" | "cerrado" | "anulado"; alcance: Alcance; total: "ciudad" | "planta" | null; planta: string | null; zona: string; causa: string; registro: string | null;
  desde: string; regreso_estimado: string | null; declarado_en: string; declarado_por: string; contratos: number; sensibles: number; reportes: ConteoReportes; franja: string;
  fin: { cuando: string; motivo: string; por: string } | null; circulo: { lat: number; lon: number; radio_m: number } | null; sectores: string[]; zona_geojson?: ZonaGeo;
};
export type Asociado = { origen: OrigenReporte; modo: "automatica" | "al_declarar" | "manual"; asociado_en: string; ref: string; rotulo: string; tipo: string | null; cuando: string | null; lat: number | null; lon: number | null };
export type EventoDetalle = Evento & { asociados: Asociado[]; lista_max?: number; sensibles_lista: { contrato: string; tipo: string }[];
  historial: { que: "regreso" | "cerrar" | "anular" | "desasociar" | "asociar_a_mano"; cuando: string; motivo: string | null; por: string }[] };
export type SectorCat = { codigo: string; nombre: string; clase: "sector" | "subsector" };
export type PlantaCat = { codigo: string; nombre: string; sectores: string[] };      // sectores: obsoleta desde el corte «origen y tubos» (siempre vacía)
/** Un tubo de salida (los puntos de distribución de la planta) con los sectores o subsectores que abastece. */
export type TuboCat = { codigo: string; nombre: string; planta: string | null; activo: boolean; sectores: string[] };
/** Causal de un evento declarado como trabajo o actividad. */
export type CausalCat = { codigo: string; nombre: string; activa: boolean };
export type TipoAsociable = { origen: OrigenReporte; codigo: string; nombre: string; clase: string; asocia: boolean };
export type CatalogoEventos = { puede: { zona: boolean; total: boolean; reportes: boolean }; limites: { radio_min_m: number; radio_max_m: number; sectores_max: number; horas_atras_max: number };
  sectores: SectorCat[]; plantas: PlantaCat[]; tipos: TipoAsociable[]; causales?: CausalCat[]; tubos?: TuboCat[] };
/** La zona que se declara, según el alcance. */
export type ZonaPedida = { alcance: "sectores"; sectores: string[] } | { alcance: "tubos"; tubos: string[] } | { alcance: "circulo"; lat: number; lon: number; radio_m: number } | { alcance: "total"; total: "ciudad" } | { alcance: "total"; total: "planta"; planta: string };
export type VistaPrevia = { alcance: Alcance; zona: string; contratos: number; sensibles: number; reportes: ConteoReportes; ya_abierto: string | null; zona_geojson: ZonaGeo };
export type EventosVigentes = { eventos: Evento[]; leyenda: { clave: string; texto: string }[] };

const F = { funcion: "geoportal-redes" };
export const apiEventos = {
  catalogo: () => pedir<CatalogoEventos>("evento_catalogo", F),
  /** Contratos, usuarios sensibles y reportes que quedarían asociados. No guarda nada. */
  vistaPrevia: (zona: ZonaPedida, desde?: string | null) => pedir<VistaPrevia>("evento_vista_previa", { ...F, cuerpo: { ...zona, ...(desde ? { desde } : {}) }, timeoutMs: 25000 }),
  /** El origen va como `registro` (DAN-… o ITV-…) o como `causal`, nunca los dos; `causa` es la observación (obligatoria siempre). */
  declarar: (zona: ZonaPedida, d: { causa: string; registro?: string | null; causal?: string | null; desde?: string | null; regreso?: string | null }) =>
    pedir<Evento & { asociados_al_declarar: number }>("evento_declarar", { ...F, timeoutMs: 25000,
      cuerpo: { ...zona, causa: d.causa, ...(d.registro ? { registro: d.registro } : {}), ...(d.causal ? { causal: d.causal } : {}), ...(d.desde ? { desde: d.desde } : {}), ...(d.regreso ? { regreso: d.regreso } : {}) } }),
  regreso: (evento: string, regreso: string, motivo?: string) => pedir<Evento>("evento_regreso", { ...F, cuerpo: { evento, regreso, ...(motivo ? { motivo } : {}) } }),
  cerrar: (evento: string, motivo: string, hecho_en?: string | null) =>
    pedir<Evento & { cerrados: { bot: number; l116: number; campo: number }; danos_siguen_abiertos: number }>("evento_cerrar", { ...F, cuerpo: { evento, motivo, ...(hecho_en ? { hecho_en } : {}) }, timeoutMs: 25000 }),
  anular: (evento: string, motivo: string) => pedir<Evento & { reportes_liberados: number }>("evento_anular", { ...F, cuerpo: { evento, motivo }, timeoutMs: 25000 }),
  asociar: (evento: string, origen: OrigenReporte, ref: string, motivo: string) => pedir<Evento>("evento_asociar", { ...F, cuerpo: { evento, origen, ref, motivo } }),
  desasociar: (evento: string, origen: OrigenReporte, ref: string, motivo: string) => pedir<Evento>("evento_desasociar", { ...F, cuerpo: { evento, origen, ref, motivo } }),
  /** Zonas y franja para el mapa (todo Técnica). */
  vigentes: () => pedir<EventosVigentes>("eventos_vigentes", F),
  lista: (estado: "abierto" | "cerrado" | "anulado" | "todos", limite = 50) => pedir<{ estado: string; eventos: Evento[] }>("eventos", { ...F, qs: { estado, limite: String(limite) } }),
  detalle: (codigo: string) => pedir<EventoDetalle>("evento", { ...F, qs: { codigo } }),
  tipoFijar: (t: { origen: OrigenReporte; codigo: string; asocia: boolean; motivo: string; nombre?: string; clase?: string }) => pedir<TipoAsociable>("evento_tipo_fijar", { ...F, cuerpo: t }),
  /** «Tubo de salida → sectores»: la lista completa cada vez, con motivo (reemplaza a «Sectores de cada planta»: el sistema es único). */
  tuboSectores: (tubo: string, sectores: string[], motivo: string) => pedir<{ tubo: string; nombre: string; sectores: string[] }>("tubo_sectores_fijar", { ...F, cuerpo: { tubo, sectores, motivo } }),
  /** Causales de trabajo: sin `codigo` crea; con `codigo`, cambia el nombre o la activa o desactiva. Motivo de 10 a 500. */
  causalFijar: (c: { codigo?: string; nombre: string; activa: boolean; motivo: string }) => pedir<CausalCat>("evento_causal_fijar", { ...F, cuerpo: c }),
};

export const NOMBRE_ORIGEN: Record<OrigenReporte, string> = { bot: "Bot de reportes", l116: "Línea 116", dano: "Daño o falla", campo: "Formato de campo" };
/** «3 del bot · 2 de la línea 116 · 1 daño · 1 de campo» (solo lo que hay). */
export function textoReportes(r: ConteoReportes): string {
  const p = [r.bot ? `${r.bot} del bot` : "", r.l116 ? `${r.l116} de la línea 116` : "", r.danos ? `${r.danos} ${r.danos === 1 ? "daño" : "daños"}` : "", r.campo ? `${r.campo} de campo` : ""].filter(Boolean);
  return p.join(" · ");
}
export const nReportes = (n: number) => (n === 1 ? "1 reporte asociado" : `${new Intl.NumberFormat("es-CO").format(n)} reportes asociados`);

/** Cómo se dice el alcance de un evento: «Por tubo» cuando salió de tubos (el servidor lo guarda como sectores). */
export function textoAlcance(e: Pick<Evento, "alcance" | "total" | "tubos">): string {
  if (e.tubos && e.tubos.length) return "Por tubo";
  return e.alcance === "sectores" ? "Por sectores" : e.alcance === "circulo" ? "Por círculo" : e.total === "planta" ? "Por planta (toda la ciudad)" : "Toda la ciudad";
}
/** «Distrito Norte (DIS-NORTE), Nevada 1 (NEV-1)» para textos corridos. */
export const textoTubos = (t: CodigoNombre[]) => t.map((x) => `${x.nombre} (${x.codigo})`).join(", ");

/** «Daño · DAN-000123», «Trabajo · Trabajo programado en redes» o «No registrado (anterior al cambio)». */
export function textoOrigen(e: Pick<Evento, "origen" | "causal" | "registro">): string {
  if (!e.origen) return e.registro ?? "";
  if (e.origen.codigo === "trabajo") return `${e.origen.nombre}${e.causal ? ` · ${e.causal.nombre}` : ""}`;
  if (e.origen.codigo === "dano" || e.origen.codigo === "intervencion") return `${e.origen.nombre}${e.registro ? ` · ${e.registro}` : ""}`;
  return e.origen.nombre;
}
