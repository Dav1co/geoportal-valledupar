// Archivo de rutas para el reparto (David, 24-nov): la plantilla es LA MISMA estructura del archivo de rutas de facturación (encabezados exactos).
// Usa el escritor de Excel de Técnica y el lector propio del modo «Cartera» (sin librerías nuevas). Los archivos son pequeños (≤ 10.000 filas): se leen sin Worker.
// La DIRECCIÓN se exige como columna pero no se envía ni se guarda.
import { ENCABEZADOS, procesarArchivoRuta, type FilaArchivo } from "./logica";

export async function descargarPlantillaReparto(): Promise<void> {
  const { LibroXlsx } = await import("../../tecnica/xlsx");
  const libro = new LibroXlsx({ hoja: "Rutas", encabezados: [...ENCABEZADOS], anchos: [20, 8, 30, 12, 24, 30], leame: [
    ["Plantilla", "Archivo de rutas — Reparto de facturas. Es la misma estructura del archivo de rutas de facturación (INFORME_RUTAS_CONSECUTIVOS)."],
    ["Encabezados", "Exactamente estos seis, en cualquier orden: " + ENCABEZADOS.join(", ") + "."],
    ["Varias rutas", "Un archivo puede traer varias rutas y varios ciclos: cada (ciclo, ruta) le aparece al repartidor como una ruta nueva."],
    ["Orden", "Dentro de cada ruta, por CONSECUTIVO_EN_LA_RUTA y, en el empate, por NÚMERO_CONSECUTIVO_DE_PREDIO."],
    ["Contratos", "Cada contrato una sola vez. Si el CICLO no coincide con el de las rutas de lectura, se avisa pero manda el archivo."],
    ["DIRECCIÓN", "La columna debe estar, pero el geoportal no la guarda ni la muestra."],
    ["Formato", "Guárdelo como «Libro de Excel (.xlsx)». No agregue columnas."],
  ] });
  const blob = await libro.finalizar();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a"); a.href = url; a.download = "plantilla_rutas_reparto.xlsx"; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/** Lee la primera hoja con «CÓDIGO_DEL_CONTRATO» y devuelve las filas para el servidor (sin la dirección), la huella y los errores (la base vuelve a validar). */
export async function leerArchivoRuta(archivo: File, tope: number): Promise<{ filas: FilaArchivo[]; errores: string[]; sha256: string }> {
  if (archivo.size > 3 * 1024 * 1024) return { filas: [], errores: ["El archivo pesa más de 3 MB: un archivo de rutas para el reparto es pequeño. Revise que sea el correcto."], sha256: "" };
  const bytes = new Uint8Array(await archivo.arrayBuffer());
  const [{ leerXlsx, ErrorXlsx }, { sha256Hex }] = await Promise.all([import("../../scrr/lectorXlsx"), import("../../scrr/lector")]);
  const hojas: string[][][] = [];
  try {
    await leerXlsx(bytes, { alFila: (celdas, hoja) => { (hojas[hoja] ??= []).push(celdas); } });
  } catch (e) {
    return { filas: [], errores: [e instanceof ErrorXlsx ? e.message : "No se pudo leer el archivo. Use la plantilla (.xlsx)."], sha256: "" };
  }
  const norm = (c: string) => c.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toUpperCase().replace(/[^A-Z0-9]+/g, " ").trim();
  const hoja = hojas.find((h) => h?.some((f) => f.some((c) => norm(c ?? "") === "CODIGO DEL CONTRATO"))) ?? [];
  const r = procesarArchivoRuta(hoja, tope);
  return { ...r, sha256: await sha256Hex(bytes) };
}
