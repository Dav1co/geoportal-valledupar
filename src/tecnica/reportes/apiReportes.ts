import { pedir, ErrorTec } from "../apiTecnica";
import { apiGestion } from "../apiRedes";
import type { ColumnaReporte, DefReporte } from "./catalogo";
import { partesBogota, type Pedido } from "./armar";
import { COLUMNAS_GESTION } from "./columnasGestion";

// Cliente de los reportes con la forma del Code A (paquete_fase1/reportes_ptap_distribucion/ENTRADA_BITACORA.md, §1, 20-nov). La misma en las dos Edges
// (PTAP en geoportal-tecnica, distribución en geoportal-redes):
//   POST ?accion=reporte_iniciar { reporte, desde?, hasta?, formato, incluir_excluidos?, <filtros> }
//        → { descarga_id, reporte, titulo, archivo, total, max, formato, incluir_excluidos, filtros, columnas, leame: { que_trae, que_no_trae, filtros, generado_por, generado_en } }
//        Sin datos → 404 «No hay datos con esos filtros.»; más del tope → 400 con el texto para la pantalla.
//   POST ?accion=reporte_pagina  { descarga_id, cursor, limite } → { filas, devueltos, cursor }   (cursor null = no hay más)
//   POST ?accion=reporte_cerrar  { descarga_id, filas, resultado } → { descarga_id, cerrada, repetida }
//   GET  geoportal-tecnica?accion=reporte_remision_foto&movimiento=N → { movimiento, url, vence_en_s }   (la página de la foto de la remisión)

export type LeameServidor = { que_trae?: string[]; que_no_trae?: string[]; filtros?: string[]; generado_por?: string; generado_en?: string };
export type ReporteIniciado = {
  descarga_id: number | null; reporte: string; titulo?: string; archivo?: string; total: number; max: number;
  columnas: ColumnaReporte[]; leame?: LeameServidor; sinDatos?: string;           // sinDatos: el 404 «No hay datos con esos filtros.» (no se abrió descarga)
};
export type ReportePagina = { filas: Record<string, unknown>[]; devueltos?: number; cursor: string | number | null };

/** Un origen de filas: las rutas paginadas nuevas, o la ruta «descarga» de las dos descargas que ya existían (todo de una vez, ya auditada por el servidor). */
export type FuenteReporte = {
  iniciar: (p: Pedido) => Promise<ReporteIniciado>;
  pagina: (id: number | null, cursor: string | number | null, limite: number) => Promise<ReportePagina>;
  cerrar: (id: number | null, filas: number, resultado: "completa" | "cancelada" | "error") => Promise<void>;
};

/** El cuerpo de «iniciar»: solo los filtros que la tarjeta tiene, y «incluir_excluidos» solo donde aplica (el servidor rechaza un filtro que no corresponde). */
export function cuerpoPedido(def: DefReporte, p: Pedido): Record<string, unknown> {
  const c: Record<string, unknown> = { reporte: def.clave, formato: p.formato };
  if (def.periodo) { c.desde = p.desde; c.hasta = p.hasta; }
  if (def.ocultos) c.incluir_excluidos = p.incluir_excluidos;
  for (const f of def.filtros) { const v = p.filtros[f.clave]; if (v) c[f.clave] = v; }
  return c;
}

export function fuenteDe(def: DefReporte): FuenteReporte {
  if (def.ruta === "gestion") {
    // Daños y fallas, Intervenciones (Corte 4b): la ruta «descarga» devuelve todas las filas y deja su propia auditoría; aquí se presenta como una sola página.
    let filas: Record<string, unknown>[] = [];
    const conjunto = def.clave as "intervenciones" | "danos";
    return {
      iniciar: async (p) => {
        const d = await apiGestion.descarga(conjunto, p.desde!, p.hasta!, p.incluir_excluidos);
        filas = d.filas;
        return { descarga_id: null, reporte: def.clave, total: d.total, max: d.total, columnas: COLUMNAS_GESTION[conjunto],
          leame: { generado_por: d.generado_por, generado_en: d.generado_en }, ...(d.total === 0 ? { sinDatos: "No hay datos con esos filtros." } : {}) };
      },
      pagina: async () => { const f = filas; filas = []; return { filas: f, cursor: null }; },
      cerrar: async () => {},
    };
  }
  const F = { funcion: def.funcion };
  return {
    iniciar: async (p) => {
      try { return await pedir<ReporteIniciado>("reporte_iniciar", { ...F, cuerpo: cuerpoPedido(def, p), timeoutMs: 60000 }); }
      catch (e) {
        if (e instanceof ErrorTec && e.status === 404) return { descarga_id: null, reporte: def.clave, total: 0, max: 0, columnas: [], sinDatos: e.message };
        throw e;
      }
    },
    pagina: (id, cursor, limite) => pedir<ReportePagina>("reporte_pagina", { ...F, cuerpo: { descarga_id: id, cursor, limite }, timeoutMs: 60000 }),
    cerrar: async (id, filas, resultado) => { if (id !== null) await pedir<{ cerrada: boolean }>("reporte_cerrar", { ...F, cuerpo: { descarga_id: id, filas, resultado } }); },
  };
}

/** La URL firmada (60 s) de la foto de una remisión: la usa la página que abre el enlace del Excel. */
export const fotoRemision = (movimiento: string) =>
  pedir<{ movimiento: number; url: string; vence_en_s: number }>("reporte_remision_foto", { qs: { movimiento } });

/** «24/10/2026 10:44» (hora de Bogotá). Acepta un ISO con zona o una hora de Bogotá sin zona (la forma del Code A); si ya viene armado, se deja igual. */
export function fechaBogota(v: string | undefined | null): string {
  if (!v) return "";
  if (/^\d{2}\/\d{2}\/\d{4}/.test(v)) return v;
  const p = partesBogota(v); if (!p) return v;
  return `${p[0].slice(8, 10)}/${p[0].slice(5, 7)}/${p[0].slice(0, 4)} ${p[1].slice(0, 5)}`;
}
