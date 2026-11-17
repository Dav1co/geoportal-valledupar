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

const F = { funcion: "geoportal-redes" };
export const apiCierre = {
  /** «¿Qué válvulas cierro?»: desde un activo o desde una posición (el tramo más cercano). No guarda nada. */
  simular: (ref: { activo: string } | { lat: number; lon: number }) => pedir<Simulacion>("simulacion_cierre", { ...F, cuerpo: ref, timeoutMs: 25000 }),
  guardar: (registro: string, activo?: string | null) => pedir<SimulacionGuardada>("simulacion_guardar", { ...F, cuerpo: { registro, ...(activo ? { activo } : {}) }, timeoutMs: 25000 }),
  maniobra: (valvula: string, tipo: "cerrar" | "abrir", o: { registro?: string | null; motivo?: string; hecho_en?: string | null; regreso?: string | null } = {}) =>
    pedir<ManiobraHecha>("valvula_maniobra", { ...F, timeoutMs: 25000,
      cuerpo: { valvula, tipo, ...(o.registro ? { registro: o.registro } : {}), ...(o.motivo ? { motivo: o.motivo } : {}), ...(o.hecho_en ? { hecho_en: o.hecho_en } : {}), ...(o.regreso ? { regreso: o.regreso } : {}) } }),
  regreso: (valvula: string, regreso: string, motivo?: string) => pedir<{ maniobra: number; regreso_estimado: string }>("corte_regreso", { ...F, cuerpo: { valvula, regreso, ...(motivo ? { motivo } : {}) } }),
  vigentes: () => pedir<CortesVigentes>("cortes_vigentes", F),
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
