import { pedir } from "../apiTecnica";
import { apiGestion } from "../apiRedes";
import type { ColumnaReporte, DefReporte } from "./catalogo";
import type { Pedido } from "./armar";
import { COLUMNAS_GESTION } from "./columnasGestion";

// Cliente de los reportes (PTAP en geoportal-tecnica, distribución en geoportal-redes). FORMA PROPUESTA al Code A mientras deja la suya en
// paquete_fase1/reportes_ptap_distribucion/ENTRADA_BITACORA.md; si cambia, se ajusta SOLO aquí. Es el mismo ciclo auditado de la descarga de «Registros»:
//   POST ?accion=reporte_iniciar  { reporte, desde?, hasta?, planta?, sector?, tipo_activo?, incluir_ocultos, formato }
//        → { descarga_id, reporte, total, max, generado_por, generado_en, columnas: [{ clave, titulo, tipo, unidad?, texto_enlace? }], filtros_texto?, leame? }
//        (deja la primera auditoría y fija los filtros en el servidor; si pasa del tope o de un año, 400 con el texto para la pantalla)
//   POST ?accion=reporte_pagina   { descarga_id, despues_de, limite } → { filas: [{ <clave>: valor }], ultimo, hay_mas }   (paginado en el servidor)
//   POST ?accion=reporte_cerrar   { descarga_id, filas, resultado: "completa" | "cancelada" | "error" } → { cerrada }     (segunda auditoría)
//   GET  geoportal-redes?accion=reportes_opciones → { sectores: [{ codigo, nombre }], tipos_activo: [{ codigo, nombre }] }   (opciones de los filtros de distribución)

export type ReporteIniciado = {
  descarga_id: number | null; reporte: string; total: number; max: number; generado_por: string; generado_en: string;
  columnas: ColumnaReporte[]; filtros_texto?: string[]; leame?: [string, string][];
};
export type ReportePagina = { filas: Record<string, unknown>[]; ultimo: string | number | null; hay_mas: boolean };
export type Opcion = { codigo: string; nombre: string };
export type OpcionesDistribucion = { sectores: Opcion[]; tipos_activo: Opcion[] };

/** Un origen de filas: o las rutas paginadas nuevas, o la ruta «descarga» de las dos descargas que ya existían (todo de una vez, ya auditada por el servidor). */
export type FuenteReporte = {
  iniciar: (p: Pedido) => Promise<ReporteIniciado>;
  pagina: (id: number | null, despuesDe: string | number | null, limite: number) => Promise<ReportePagina>;
  cerrar: (id: number | null, filas: number, resultado: "completa" | "cancelada" | "error") => Promise<void>;
};

const cuerpoPedido = (def: DefReporte, p: Pedido) => {
  const c: Record<string, unknown> = { reporte: def.clave, incluir_ocultos: p.incluir_ocultos, formato: p.formato };
  if (def.periodo) { c.desde = p.desde; c.hasta = p.hasta; }
  for (const k of ["planta", "sector", "tipo_activo"] as const) if (p[k] && def.filtros.includes(k)) c[k] = p[k];
  return c;
};

export function fuenteDe(def: DefReporte): FuenteReporte {
  if (def.ruta === "gestion") {
    // Daños y fallas, Intervenciones (Corte 4b): la ruta «descarga» devuelve todas las filas y ya deja su auditoría; aquí se presenta como una sola página.
    let filas: Record<string, unknown>[] = [];
    const conjunto = def.clave as "intervenciones" | "danos";
    return {
      iniciar: async (p) => {
        const d = await apiGestion.descarga(conjunto, p.desde!, p.hasta!, p.incluir_ocultos);
        filas = d.filas;
        return { descarga_id: null, reporte: def.clave, total: d.total, max: d.total, generado_por: d.generado_por, generado_en: fechaBogota(d.generado_en), columnas: COLUMNAS_GESTION[conjunto] };
      },
      pagina: async () => { const f = filas; filas = []; return { filas: f, ultimo: null, hay_mas: false }; },
      cerrar: async () => {},
    };
  }
  const F = { funcion: def.funcion };
  return {
    iniciar: (p) => pedir<ReporteIniciado>("reporte_iniciar", { ...F, cuerpo: cuerpoPedido(def, p), timeoutMs: 60000 }),
    pagina: (id, despuesDe, limite) => pedir<ReportePagina>("reporte_pagina", { ...F, cuerpo: { descarga_id: id, despues_de: despuesDe, limite }, timeoutMs: 60000 }),
    cerrar: async (id, filas, resultado) => { await pedir<{ cerrada: boolean }>("reporte_cerrar", { ...F, cuerpo: { descarga_id: id, filas, resultado } }); },
  };
}

export const opcionesDistribucion = () => pedir<OpcionesDistribucion>("reportes_opciones", { funcion: "geoportal-redes" });

/** «24/10/2026 10:44» (hora de Bogotá) a partir de un ISO; si ya viene armado, se deja igual. */
export function fechaBogota(v: string): string {
  if (/^\d{2}\/\d{2}\/\d{4}/.test(v)) return v;
  const d = new Date(v); if (Number.isNaN(d.getTime())) return v;
  return d.toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).replace(",", "");
}
