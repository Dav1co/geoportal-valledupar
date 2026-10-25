import { apiDash, type FiltrosRegistros } from "./apiDashboard";
import { ANCHOS_XLSX, BOM, ENCABEZADOS, cabeceraCsv, filaCsv, filaXlsx, hojaLeame, nombreArchivo } from "./descargas";

// Orquesta una descarga AUDITADA: iniciar (deja la auditoría y fija los filtros en el servidor) → páginas de 5.000 → armar el archivo en el navegador → cerrar (segunda auditoría).
// El archivo nunca se arma con más filas que el tope que el servidor declara (50.000). Excel se carga bajo demanda (import dinámico).
export class DescargaCancelada extends Error { constructor() { super("Descarga cancelada."); this.name = "DescargaCancelada"; } }
export type Progreso = { fase: "preparando" | "descargando" | "armando"; hecho: number; total: number };
export type Resultado = { nombre: string; filas: number; blob: Blob };

export async function ejecutarDescarga(a: {
  filtros: FiltrosRegistros; formato: "csv" | "xlsx"; incluirExcluidos: boolean; filtrosTexto: string[];
  onProgreso: (p: Progreso) => void; senal: AbortSignal; tamanoPagina?: number;
}): Promise<Resultado> {
  a.onProgreso({ fase: "preparando", hecho: 0, total: 0 });
  const ini = await apiDash.descargaIniciar(a.filtros, a.formato, a.incluirExcluidos);          // puede fallar con «Acote el periodo»: no se escribió nada
  let hechas = 0; let cerrado = false;
  const cerrar = async (res: "completa" | "cancelada" | "error") => { if (cerrado) return; cerrado = true; try { await apiDash.descargaCerrar(ini.descarga_id, hechas, res); } catch { /* el cierre es de mejor esfuerzo */ } };
  try {
    const xlsx = a.formato === "xlsx" ? await import("./xlsx") : null;
    const libro = xlsx ? new xlsx.LibroXlsx({ hoja: "Registros", encabezados: ENCABEZADOS, anchos: ANCHOS_XLSX,
      leame: hojaLeame({ generadoPor: ini.generado_por, generadoEn: ini.generado_en, filas: ini.total, formato: "xlsx", incluirExcluidos: ini.incluir_excluidos, filtros: a.filtrosTexto }) }) : null;
    const partes: string[] = [BOM, cabeceraCsv()];
    let cursor: number | null = null;
    for (;;) {
      if (a.senal.aborted) throw new DescargaCancelada();
      const pag = await apiDash.descargaPagina(ini.descarga_id, cursor, a.tamanoPagina ?? 5000);
      if (pag.registros.length === 0) break;
      if (libro && xlsx) await libro.agregarFilas(pag.registros.map((f) => filaXlsx(f, xlsx.serialExcel, xlsx.serialHora)));
      else for (const f of pag.registros) partes.push(filaCsv(f));
      hechas += pag.registros.length; cursor = pag.ultimo_id;
      a.onProgreso({ fase: "descargando", hecho: hechas, total: ini.total });
      if (!pag.hay_mas) break;
    }
    if (a.senal.aborted) throw new DescargaCancelada();
    a.onProgreso({ fase: "armando", hecho: hechas, total: ini.total });
    const blob = libro ? await libro.finalizar() : new Blob(partes, { type: "text/csv;charset=utf-8" });
    await cerrar("completa");
    return { nombre: nombreArchivo(ini.generado_en, a.formato), filas: hechas, blob };
  } catch (e) {
    await cerrar(e instanceof DescargaCancelada ? "cancelada" : "error");
    throw e;
  }
}

/** Entrega el archivo al navegador (sin datos personales en el nombre). */
export function guardarArchivo(r: Resultado) {
  const url = URL.createObjectURL(r.blob); const a = document.createElement("a");
  a.href = url; a.download = r.nombre; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
