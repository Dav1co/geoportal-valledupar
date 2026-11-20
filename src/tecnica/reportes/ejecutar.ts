import { importarConRecarga } from "../../lib/recarga";
import type { DefReporte } from "./catalogo";
import { cabeceraCsv, encabezado, ancho, filaCsv, filaXlsx, hojaLeame, nombreArchivo, type Pedido } from "./armar";
import { fechaBogota, type FuenteReporte } from "./apiReportes";

// Una descarga AUDITADA de un reporte: iniciar (primera auditoría, filtros fijos en el servidor) → páginas → armar el archivo en el navegador → cerrar
// (segunda auditoría, con cuántas filas y si terminó, se canceló o falló). Igual que la descarga de «Registros» (ejecutarDescarga.ts).
export class ReporteCancelado extends Error { constructor() { super("Descarga cancelada."); this.name = "ReporteCancelado"; } }
export type Progreso = { fase: "preparando" | "descargando" | "armando"; hecho: number; total: number };
export type Resultado = { nombre: string; filas: number; blob: Blob | null };

export async function ejecutarReporte(a: {
  def: DefReporte; fuente: FuenteReporte; pedido: Pedido; filtrosTexto: string[]; onProgreso: (p: Progreso) => void; senal: AbortSignal; tamanoPagina?: number;
}): Promise<Resultado> {
  a.onProgreso({ fase: "preparando", hecho: 0, total: 0 });
  const ini = await a.fuente.iniciar(a.pedido);          // puede fallar con el texto del servidor («Acote el periodo», permiso…): no se escribió nada
  let hechas = 0; let cerrado = false;
  const cerrar = async (res: "completa" | "cancelada" | "error") => { if (cerrado) return; cerrado = true; try { await a.fuente.cerrar(ini.descarga_id, hechas, res); } catch { /* el cierre es de mejor esfuerzo */ } };
  try {
    if (!Array.isArray(ini.columnas) || !ini.columnas.length) throw new Error("El servidor no mandó las columnas del reporte.");
    if (ini.total === 0) { await cerrar("completa"); return { nombre: "", filas: 0, blob: null }; }
    const cols = ini.columnas;
    const xlsx = a.pedido.formato === "xlsx" ? await importarConRecarga(() => import("../xlsx")) : null;
    const libro = xlsx ? new xlsx.LibroXlsx({ hoja: a.def.titulo.slice(0, 31), encabezados: cols.map(encabezado), anchos: cols.map(ancho),
      leame: hojaLeame({ def: a.def, pedido: a.pedido, filtrosTexto: ini.filtros_texto?.length ? ini.filtros_texto : a.filtrosTexto, generadoPor: ini.generado_por,
        generadoEn: fechaBogota(ini.generado_en), filas: ini.total, extra: ini.leame }) }) : null;
    const partes: string[] = [cabeceraCsv(cols)];
    let cursor: string | number | null = null;
    for (;;) {
      if (a.senal.aborted) throw new ReporteCancelado();
      const pag = await a.fuente.pagina(ini.descarga_id, cursor, a.tamanoPagina ?? 5000);
      if (a.senal.aborted) throw new ReporteCancelado();
      if (!pag.filas.length) break;
      if (libro && xlsx) await libro.agregarFilas(pag.filas.map((f) => filaXlsx(cols, f, xlsx.serialExcel)));
      else for (const f of pag.filas) partes.push(filaCsv(cols, f));
      hechas += pag.filas.length; cursor = pag.ultimo;
      a.onProgreso({ fase: "descargando", hecho: Math.min(hechas, ini.total), total: ini.total });
      if (!pag.hay_mas) break;
    }
    a.onProgreso({ fase: "armando", hecho: Math.min(hechas, ini.total), total: ini.total });
    const blob = libro ? await libro.finalizar() : new Blob(partes, { type: "text/csv;charset=utf-8" });
    await cerrar("completa");
    return { nombre: nombreArchivo(a.def, a.pedido), filas: hechas, blob };
  } catch (e) {
    await cerrar(e instanceof ReporteCancelado ? "cancelada" : "error");
    throw e;
  }
}

/** Entrega el archivo al navegador. */
export function guardarArchivo(nombre: string, blob: Blob) {
  const url = URL.createObjectURL(blob); const el = document.createElement("a");
  el.href = url; el.download = nombre; document.body.appendChild(el); el.click(); el.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
