import { apiRev, type FiltrosServidor, type FormularioRev } from "./apiRevision";
import { BOM, MAX_FILAS_EXCEL, cabeceraCsv, filaCsv, filaDeDescarga, hojaLeame, nombreArchivo, nombreHoja } from "./archivo";
import { columnasBase, columnasDescarga, columnasPropias, camposDelTipo, type Columna, type Contexto } from "./columnas";
import type { Celda } from "../../tecnica/xlsx";
import { importarConRecarga } from "../../lib/recarga";

// Orquesta una descarga AUDITADA y COMPLETA: iniciar (deja la auditoría, fija los filtros y el corte en el servidor) → páginas de 5.000 hasta que `hay_mas` sea falso → arma el archivo en el
// navegador → cerrar (segunda auditoría con las filas entregadas). Sin tope de filas. El archivo nunca incluye rutas de Storage, URLs ni claves, y no se guarda en ningún almacenamiento del navegador.
export class DescargaCancelada extends Error { constructor() { super("Descarga cancelada."); this.name = "DescargaCancelada"; } }
/** Excel no admite más de 1.048.576 filas por hoja: se avisa ANTES de bajar nada y se ofrece el CSV. */
export class ExcelDemasiadoGrande extends Error { total: number; constructor(total: number) { super(`Excel no admite más de ${MAX_FILAS_EXCEL.toLocaleString("es-CO")} filas por hoja y esta descarga tiene ${total.toLocaleString("es-CO")}. Descárguela en CSV.`); this.name = "ExcelDemasiadoGrande"; this.total = total; } }
export type Progreso = { fase: "preparando" | "descargando" | "armando"; hecho: number; total: number };
export type Resultado = { nombre: string; filas: number; blob: Blob };

const anchoDe = (c: Columna) => (c.clave === "descripcion" ? 50 : c.tipo === "fecha_hora" ? 18 : c.clave === "id" ? 38 : c.tipo === "numero" ? 12 : 22);

export async function ejecutarDescarga(a: {
  filtros: FiltrosServidor; formato: "csv" | "xlsx"; incluirAutor: boolean; filtrosTexto: string[]; soloPantalla: string[]; def: FormularioRev; tamanoPagina?: number;
  onProgreso: (p: Progreso) => void; senal: AbortSignal;
}): Promise<Resultado> {
  a.onProgreso({ fase: "preparando", hecho: 0, total: 0 });
  const ini = await apiRev.descargaIniciar(a.filtros, a.formato, a.incluirAutor);          // puede fallar («No hay reportes…», sin permiso): no se escribió nada
  let hechas = 0; let cerrado = false;
  const cerrar = async (res: "completa" | "cancelada" | "error") => { if (cerrado) return; cerrado = true; try { await apiRev.descargaCerrar(ini.descarga_id, hechas, res); } catch { /* el cierre es de mejor esfuerzo */ } };
  try {
    if (a.formato === "xlsx" && ini.total > MAX_FILAS_EXCEL) throw new ExcelDemasiadoGrande(ini.total);
    const ctx: Contexto = { estados: new Map((a.def.estados ?? []).map((e) => [e.codigo, e.nombre])) };
    const base = columnasBase(true);
    const conTipo = !!a.filtros.tipo;
    const propiasDe = (tipo: string) => columnasPropias(camposDelTipo(a.def, tipo));
    const incluirAutor = ini.incluir_autor;
    const xl = a.formato === "xlsx" ? await importarConRecarga(() => import("../../tecnica/xlsx")) : null;
    const libroMod = a.formato === "xlsx" ? await importarConRecarga(() => import("./xlsxRevision")) : null;
    const leame = (hojas: boolean) => hojaLeame({ generadoPor: ini.generado_por, generadoEn: ini.generado_en, filas: ini.total, formato: a.formato, filtros: a.filtrosTexto, incluyeAutor: incluirAutor, soloPantalla: a.soloPantalla, hojasPorTipo: hojas });
    const libro = libroMod ? new libroMod.LibroMulti(leame(!conTipo)) : null;
    const usados = new Set<string>(["léame"]);
    const hojaDe = new Map<string, { cols: Columna[] }>();
    const partes: string[] = [];
    // CSV: con un tipo filtrado, sus columnas propias; con varios, una columna JSON. Se decide con el filtro (no con las filas) para que el encabezado se escriba una sola vez.
    const colsCsv = columnasDescarga(base, conTipo ? propiasDe(a.filtros.tipo as string) : [], { conTipo, incluirAutor });
    if (!libro) partes.push(BOM, cabeceraCsv(colsCsv, !conTipo));
    const celda = (c: Columna, f: ReturnType<typeof filaDeDescarga>): Celda => {
      const v = c.valor(f);
      if (c.tipo === "numero" && typeof v === "number") return v;
      if (c.tipo === "fecha_hora" && typeof v === "string" && xl && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) { const s = xl.serialExcel(v.slice(0, 10), v.slice(11)); return s === null ? c.texto(f, ctx) : { fechaHora: s }; }
      return c.texto(f, ctx);
    };
    let cursor: number | null = null;
    for (;;) {
      if (a.senal.aborted) throw new DescargaCancelada();
      const pag = await apiRev.descargaPagina(ini.descarga_id, cursor, a.tamanoPagina ?? 1000);
      if (pag.registros.length === 0) break;
      const filas = pag.registros.map(filaDeDescarga);
      if (libro) {
        const porHoja = new Map<string, Celda[][]>();
        for (const f of filas) {
          const clave = conTipo ? "unica" : f.tipo.codigo;
          let h = hojaDe.get(clave);
          if (!h) {
            const cols = columnasDescarga(base, propiasDe(conTipo ? (a.filtros.tipo as string) : f.tipo.codigo), { conTipo: true, incluirAutor });
            h = { cols }; hojaDe.set(clave, h);
            libro.hoja(clave, nombreHoja(conTipo ? "Reportes" : f.tipo.nombre, usados), cols.map((c) => c.etiqueta), cols.map(anchoDe));
          }
          const l = porHoja.get(clave) ?? []; l.push(h.cols.map((c) => celda(c, f))); porHoja.set(clave, l);
        }
        for (const [clave, l] of porHoja) await libro.hoja(clave, "", [], []).agregarFilas(l);   // la hoja ya existe: solo se agregan filas
      } else for (const f of filas) partes.push(filaCsv(f, colsCsv, ctx, !conTipo));
      hechas += filas.length; cursor = pag.ultimo_seq;
      a.onProgreso({ fase: "descargando", hecho: hechas, total: ini.total });
      if (!pag.hay_mas || cursor === null) break;
    }
    if (a.senal.aborted) throw new DescargaCancelada();
    a.onProgreso({ fase: "armando", hecho: hechas, total: ini.total });
    const blob = libro ? await libro.finalizar() : new Blob(partes, { type: "text/csv;charset=utf-8" });
    await cerrar("completa");
    return { nombre: nombreArchivo(ini.generado_en, a.formato), filas: hechas, blob };
  } catch (e) {
    await cerrar(e instanceof DescargaCancelada || e instanceof ExcelDemasiadoGrande ? "cancelada" : "error");
    throw e;
  }
}

/** Entrega el archivo al navegador (sin datos personales en el nombre). */
export function guardarArchivo(r: Resultado) {
  const url = URL.createObjectURL(r.blob); const a = document.createElement("a");
  a.href = url; a.download = r.nombre; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
