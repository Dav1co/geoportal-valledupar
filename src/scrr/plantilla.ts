// Plantillas descargables de la carga del día (decisión 1 del 20-nov): un libro de Excel con SOLO las columnas que el motor exige, en orden, y una hoja «Léame».
// Usa el escritor de Excel ya publicado en Técnica (sin dependencias); se carga bajo demanda.
import { PLANTILLAS, NOMBRE_ARCHIVO, type TipoCarga } from "./lector";

const LEAME_COMUN: string[][] = [
  ["Cómo se usa", "Copie los datos debajo de los títulos, sin cambiar los títulos ni agregar columnas. El geoportal rechaza el archivo si falta o sobra una columna."],
  ["Formato", "Guárdelo como «Libro de Excel (.xlsx)». Los archivos .xls viejos y los CSV no se aceptan."],
  ["Varias hojas", "Si los datos no caben en una hoja, use otra hoja con los mismos títulos en el mismo orden."],
];

export async function descargarPlantilla(tipo: TipoCarga): Promise<void> {
  const { LibroXlsx } = await import("../tecnica/xlsx");
  const cols = PLANTILLAS[tipo];
  const libro = new LibroXlsx({ hoja: NOMBRE_ARCHIVO[tipo], encabezados: cols.map((c) => c.encabezado), anchos: cols.map((c) => c.ancho),
    leame: [["Plantilla", `${NOMBRE_ARCHIVO[tipo]} — Motor SCRR, modo «Cartera»`], ...LEAME_COMUN, ...cols.map((c) => [c.encabezado, c.nota || "—"]),
            ...(tipo === "pagos" ? [["Provisional", "Plantilla de 3 columnas mientras llega el archivo real de pagos del día (decisión de David del 22-nov)."]] : []),
            ...(tipo === "actividades" ? [["Anomalías", "Catálogo de 17 códigos: 1 PAGO EFECTUADO … 17 OTRO MEDIDOR (obligatoria si la visita es inefectiva)."],
                                      ["Fuera de las listas", "Se cargan también las visitas que no salieron de una lista y lo ya realizado antes de arrancar el motor (ajuste inicial)."]] : [])] });
  const blob = await libro.finalizar();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a"); a.href = url; a.download = `plantilla_${tipo}.xlsx`; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}
