import { pedir } from "./apiTecnica";

// Cliente del Corte 9b, Fases 1a y 1b, en la Edge geoportal-redes: la simulación de cierre («¿Qué válvulas cierro?») y el cierre real (válvula cerrada,
// válvula abierta, hora estimada de regreso y las afectaciones vigentes). Quién puede cada cosa lo decide el SERVIDOR. Solo conteos de contratos:
// ningún dato de suscriptores; «quién cerró» es el nombre del funcionario.

export type ValvulaSim = { codigo: string; codigo_anterior?: string | null; clase?: string | null; efecto?: string; distancia_m?: number; por_verificar?: boolean; lat?: number; lon?: number; estado?: string };
export type EscenarioSim = { aislable: boolean; contratos: number; valvulas_total: number; valvulas: ValvulaSim[]; tramos_segmento: number; tramos_sin_agua: number; tramos_aguas_abajo: number; longitud_sin_agua_m: number };
export type NoCierra = { valvula: string; cerrar_en_su_lugar: ValvulaSim[]; valvulas_total: number; tramos_sin_agua: number; contratos: number };
export type Simulacion = {
  ms: number; activo: { codigo: string; tipo: string; codigo_anterior?: string | null; lat: number; lon: number }; rango: boolean; segmento_grande: boolean;
  contratos_min: number; contratos_max: number; estrecho: EscenarioSim; amplio: EscenarioSim; si_no_cierra: NoCierra[]; alternativas: NoCierra[]; dudosas: string[]; notas: string[];
};
export type SimulacionGuardada = Simulacion & { id: number; registro: string };
export type ManiobraHecha = { maniobra: number; valvula: string; estado: "cerrada" | "abierta"; hecho_en: string; en_red: boolean; zona: number | null;
  vigente: { zonas: number; valvulas_cerradas: number; contratos: number; tramos_cerrados: number; tramos_afectados: number } };
export type ZonaCorte = { zona: number; lat: number; lon: number; caja: [number, number, number, number]; contratos: number; tramos: number; desde: string | null; regreso_estimado: string | null;
  por: { registro: string | null; que: string }[] };
export type ValvulaCerrada = { codigo: string; nombre: string; zona: number | null; en_red: boolean; lat: number; lon: number; desde: string; quien: string; registro: string | null; regreso_estimado: string | null };
export type CortesVigentes = { hay: boolean; foto?: { id: number; calculada_en: string; red_huella: string }; resumen?: { zonas: number; valvulas_cerradas: number; contratos: number };
  leyenda?: { clave: "afectado" | "cerrado" | "valvula"; texto: string }[]; zonas: ZonaCorte[]; valvulas: ValvulaCerrada[] };

// «Cierre por aguas arriba» (9b; la base es del Code A): las válvulas por donde entra el agua al tramo, por un criterio (cota del terreno o flujo del modelo) y la
// comprobación por el otro. Si no se puede, «cae_a_total» y trae el aislamiento total (la simulación de siempre). No guarda nada.
export type CriterioSentido = "cota" | "modelo";
export type LadoAguasArriba = { criterio: CriterioSentido; se_puede: boolean; motivo?: string; texto?: string; valvulas_total?: number; valvulas?: ValvulaSim[];
  entra_por?: { codigo?: string; nombre?: string; tipo?: string; clase?: string | null; lat?: number; lon?: number } | null;
  contratos_min?: number; contratos_max?: number; tramos_recorridos?: number; tramos_sin_sentido?: number; tramos_sin_agua_min?: number; tramos_sin_agua_max?: number; longitud_sin_agua_max_m?: number };
export type AguasArriba = { ms: number; metodo: "aguas_arriba" | "aislamiento_total"; criterio: CriterioSentido; cae_a_total: boolean; activo?: Simulacion["activo"];
  aguas_arriba: LadoAguasArriba; comprobacion: LadoAguasArriba & { coincide: boolean }; modelo_horas_coinciden?: boolean | null; aislamiento_total?: Simulacion | null;
  contratos_min: number; contratos_max: number; notas: string[] };

const F = { funcion: "geoportal-redes" };
export const apiCierre = {
  /** «¿Qué válvulas cierro?»: desde un activo o desde una posición (el tramo más cercano). No guarda nada. */
  simular: (ref: { activo: string } | { lat: number; lon: number }) => pedir<Simulacion>("simulacion_cierre", { ...F, cuerpo: ref, timeoutMs: 25000 }),
  /** «Cierre por aguas arriba»: desde un activo o desde una posición. No guarda nada. */
  aguasArriba: (ref: { activo: string } | { lat: number; lon: number }) => pedir<AguasArriba>("simulacion_aguas_arriba", { ...F, cuerpo: ref, timeoutMs: 25000 }),
  guardar: (registro: string, activo?: string | null) => pedir<SimulacionGuardada>("simulacion_guardar", { ...F, cuerpo: { registro, ...(activo ? { activo } : {}) }, timeoutMs: 25000 }),
  maniobra: (valvula: string, tipo: "cerrar" | "abrir", o: { registro?: string | null; motivo?: string; hecho_en?: string | null; regreso?: string | null } = {}) =>
    pedir<ManiobraHecha>("valvula_maniobra", { ...F, timeoutMs: 25000,
      cuerpo: { valvula, tipo, ...(o.registro ? { registro: o.registro } : {}), ...(o.motivo ? { motivo: o.motivo } : {}), ...(o.hecho_en ? { hecho_en: o.hecho_en } : {}), ...(o.regreso ? { regreso: o.regreso } : {}) } }),
  regreso: (valvula: string, regreso: string, motivo?: string) => pedir<{ maniobra: number; regreso_estimado: string }>("corte_regreso", { ...F, cuerpo: { valvula, regreso, ...(motivo ? { motivo } : {}) } }),
  vigentes: () => pedir<CortesVigentes>("cortes_vigentes", F),
  /** El supervisor rehace la foto de las afectaciones (si la red cambió después del último cierre). */
  recalcular: (motivo: string) => pedir<{ foto: number; zonas: number; valvulas_cerradas: number; contratos: number }>("cortes_recalcular", { ...F, cuerpo: { motivo }, timeoutMs: 25000 }),
};

// ---------- Fase 2: alertas de presión (MODELO, no medida) y usuarios sensibles (supervisores y administrador) ----------
export type NivelAlerta = "baja_roja" | "baja_naranja" | "alta_naranja" | "alta_roja";
export type AlertasPresion = { cargado: boolean; aviso: string; fuente: string; horas_excluidas?: number[]; nota_horas?: string | null;      // ajuste final del 9b: horas en que el modelo no es confiable
  escenario: "existente" | "futura"; nodos: number; niveles: Partial<Record<NivelAlerta, number>>;
  umbrales: Record<NivelAlerta, number>; peores: { nodo: string; zona: string | null; nivel: NivelAlerta; p_min: number; p_max: number; lat: number; lon: number }[];
  por_material: { n: number; nota: string; nodos: { nodo: string; material?: string; p_max?: number; presion_trabajo?: number }[] } };
export type EstadoSensible = "por_confirmar" | "confirmado" | "descartado";
export type Sensible = { contrato: string; tipo: string; tipo_nombre: string; palabra: string | null; origen: string; estado: EstadoSensible; desde: string; tramo: string | null; lat: number | null; lon: number | null };
export type Sensibles = { tipos: { codigo: string; nombre: string }[]; totales: Partial<Record<EstadoSensible, number>>; items: Sensible[]; siguiente: string | null };
export const apiFase2 = {
  alertas: (escenario: "existente" | "futura") => pedir<AlertasPresion>("alertas_presion", { ...F, qs: { escenario } }),
  sensibles: (estado: EstadoSensible | "", despuesDe?: string | null) => pedir<Sensibles>("sensibles", { ...F, qs: { ...(estado ? { estado } : {}), ...(despuesDe ? { despues_de: despuesDe } : {}), limite: "50" } }),
  /** Confirmar (con o sin corregir el tipo), descartar (con motivo) o agregar a mano (confirmar un contrato que no está en la lista, con tipo y motivo). Nunca viaja el nombre. */
  fijar: (contrato: string, accion: "confirmar" | "descartar", o: { tipo?: string | null; motivo?: string } = {}) =>
    pedir<{ contrato: string; estado: EstadoSensible; tipo: string | null; cambio: boolean }>("sensible_fijar", { ...F, cuerpo: { contrato, accion, ...(o.tipo ? { tipo: o.tipo } : {}), ...(o.motivo ? { motivo: o.motivo } : {}) } }),
};

// ---------- Fase 3: capa «Flujo del agua (modelo)» ----------
export type FlujoInfo = { cargado: boolean; rotulo: string; origen: string; nota: string; version: number; horas: { cual: "mayor" | "menor"; hora: number; texto: string; consumo_lps: number }[];
  leyenda: { titulo: string; unidad: string; clases: { clase: number; texto: string }[]; sin_flujo: string; sin_dato: string };
  cobertura: { con_tramo: number; sin_tramo: number; tramos_red: number; tubos_modelo: number } };
export type FlujoTramo = { rotulo: string; en_modelo: boolean; cambia_de_sentido?: boolean; tramo: { codigo: string; tipo: string; codigo_anterior?: string | null };
  horas?: { cual: "mayor" | "menor"; hora: number; sentido: string; caudal_lps: number; velocidad_mps: number }[] };
export const apiFlujo = {
  info: () => pedir<FlujoInfo>("flujo_modelo", F),
  tramo: (codigo: string) => pedir<FlujoTramo>("flujo_tramo", { ...F, qs: { codigo } }),
};

/** «9:40 a. m.» si es de hoy; si no, «16 nov, 9:40 a. m.» (hora de Bogotá). */
export function horaClara(v: string | null | undefined): string {
  if (!v) return "—";
  const d = new Date(v), z = { timeZone: "America/Bogota" } as const;
  const hora = d.toLocaleTimeString("es-CO", { ...z, hour: "numeric", minute: "2-digit" });
  const dia = (x: Date) => x.toLocaleDateString("es-CO", { ...z, year: "numeric", month: "2-digit", day: "2-digit" });
  return dia(d) === dia(new Date()) ? hora : `${d.toLocaleDateString("es-CO", { ...z, day: "numeric", month: "short" })}, ${hora}`;
}
/** Lo escrito en un campo de fecha y hora del celular (hora local) → instante ISO con zona, o nada. */
export function instanteDeCampo(v: string): string | null {
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
export const nContratos = (n: number) => `${new Intl.NumberFormat("es-CO").format(n)} ${n === 1 ? "contrato" : "contratos"}`;
