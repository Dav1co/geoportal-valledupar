import { importarConRecarga } from "../../lib/recarga";
import type { DefReporte } from "./catalogo";
import { cabeceraCsv, encabezado, ancho, enlazarWeb, filaCsv, filaXlsx, hojaLeame, nombreArchivo, type Enlazar, type Pedido } from "./armar";
import { fechaBogota, type FuenteReporte } from "./apiReportes";

// Una descarga AUDITADA de un reporte: iniciar (primera auditoría, filtros fijos en el servidor) → páginas → armar el archivo en el navegador → cerrar
// (segunda auditoría, con cuántas filas y si terminó, se canceló o falló). Igual que la descarga de «Registros» (ejecutarDescarga.ts).
export class ReporteCancelado extends Error { constructor() { super("Descarga cancelada."); this.name = "ReporteCancelado"; } }
export type Progreso = { fase: "preparando" | "descargando" | "armando"; hecho: number; total: number };
export type Resultado = { nombre: string; filas: number; blob: Blob | null; sinDatos?: string };

/** La página del geoportal que abre la foto de una remisión (contrato del Code A, §2.5): `remision.html?movimiento=N`, junto a la app. Pide sesión iniciada. */
export const urlRemision = (movimiento: string | number, base = `${location.origin}${location.pathname.replace(/[^/]*$/, "")}`) =>
  `${base}remision.html?movimiento=${encodeURIComponent(String(movimiento))}`;
/** «foto_remision» trae el número del movimiento (o null): se vuelve un vínculo «Ver foto» a esa página. Un enlace web que venga tal cual también vale. */
export const enlazarReporte: Enlazar = (c, v) => (c.clave === "foto_remision" && /^\d{1,15}$/.test(String(v)) ? { url: urlRemision(String(v)), texto: "Ver foto" } : enlazarWeb(c, v));

export async function ejecutarReporte(a: {
  def: DefReporte; fuente: FuenteReporte; pedido: Pedido; filtrosTexto: string[]; onProgreso: (p: Progreso) => void; senal: AbortSignal; tamanoPagina?: number;
}): Promise<Resultado> {
  a.onProgreso({ fase: "preparando", hecho: 0, total: 0 });
  const ini = await a.fuente.iniciar(a.pedido);          // puede fallar con el texto del servidor (tope, permiso…): no se escribió nada
  if (ini.sinDatos !== undefined) return { nombre: "", filas: 0, blob: null, sinDatos: ini.sinDatos };      // 404 «No hay datos con esos filtros.»: no se abrió descarga
  let hechas = 0; let cerrado = false;
  const cerrar = async (res: "completa" | "cancelada" | "error") => { if (cerrado) return; cerrado = true; try { await a.fuente.cerrar(ini.descarga_id, hechas, res); } catch { /* el cierre es de mejor esfuerzo */ } };
  try {
    if (!Array.isArray(ini.columnas) || !ini.columnas.length) throw new Error("El servidor no mandó las columnas del reporte.");
    const cols = ini.columnas;
    const xlsx = a.pedido.formato === "xlsx" ? await importarConRecarga(() => import("../xlsx")) : null;
    const libro = xlsx ? new xlsx.LibroXlsx({ hoja: a.def.titulo.slice(0, 31), encabezados: cols.map(encabezado), anchos: cols.map(ancho),
      leame: hojaLeame({ def: a.def, pedido: a.pedido, filtrosTexto: a.filtrosTexto, leame: ini.leame, generadoEn: fechaBogota(ini.leame?.generado_en) || fechaBogota(new Date().toISOString()), filas: ini.total }) }) : null;
    const partes: string[] = [cabeceraCsv(cols)];
    let cursor: string | number | null = null;
    for (let vuelta = 0; ; vuelta++) {
      if (a.senal.aborted) throw new ReporteCancelado();
      const pag = await a.fuente.pagina(ini.descarga_id, cursor, a.tamanoPagina ?? 5000);
      if (a.senal.aborted) throw new ReporteCancelado();
      const filas = Array.isArray(pag.filas) ? pag.filas : [];
      if (libro && xlsx) await libro.agregarFilas(filas.map((f) => filaXlsx(cols, f, xlsx.serialExcel, enlazarReporte)));
      else for (const f of filas) partes.push(filaCsv(cols, f, enlazarReporte));
      hechas += filas.length; cursor = pag.cursor ?? null;
      a.onProgreso({ fase: "descargando", hecho: Math.min(hechas, ini.total), total: ini.total });
      if (cursor === null || !filas.length) break;                // cursor null = no hay más páginas
      if (vuelta > 1000) throw new Error("La descarga no terminó: demasiadas páginas.");
    }
    a.onProgreso({ fase: "armando", hecho: Math.min(hechas, ini.total), total: ini.total });
    const blob = libro ? await libro.finalizar() : new Blob(partes, { type: "text/csv;charset=utf-8" });
    await cerrar("completa");
    return { nombre: nombreArchivo(a.def, a.pedido, ini.archivo), filas: hechas, blob };
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
