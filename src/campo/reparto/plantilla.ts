// Archivo de una ruta o de un ciclo para el reparto: plantilla descargable (Contrato y Orden, con su hoja «Léame») y lectura del Excel en el navegador.
// Usa el escritor de Excel de Técnica y el lector propio del modo «Cartera» (sin librerías nuevas). Los archivos son pequeños (≤ 10.000 filas): se leen sin Worker.
import { procesarArchivoRuta } from "./logica";

export async function descargarPlantillaReparto(): Promise<void> {
  const { LibroXlsx } = await import("../../tecnica/xlsx");
  const libro = new LibroXlsx({ hoja: "Ruta de reparto", encabezados: ["Contrato", "Orden"], anchos: [16, 10], leame: [
    ["Plantilla", "Archivo de una ruta o de un ciclo — Reparto de facturas"],
    ["Contrato", "Obligatorio. Solo números, sin repetir."],
    ["Orden", "Opcional. Entero desde 1, sin repetir. Si lo deja vacío en todas las filas, el orden es el de las filas."],
    ["Ciclo y ruta", "No van en el archivo: se escogen en la pantalla al cargarlo."],
    ["Formato", "Guárdelo como «Libro de Excel (.xlsx)». No agregue columnas."],
  ] });
  const blob = await libro.finalizar();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a"); a.href = url; a.download = "plantilla_ruta_reparto.xlsx"; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/** Lee la primera hoja con «Contrato» y devuelve las filas para el servidor, la huella y los errores (la base vuelve a validar todo). */
export async function leerArchivoRuta(archivo: File, tope: number): Promise<{ filas: { contrato: string | null; orden?: string }[]; errores: string[]; sha256: string }> {
  if (archivo.size > 3 * 1024 * 1024) return { filas: [], errores: ["El archivo pesa más de 3 MB: un archivo de ruta o de ciclo es pequeño. Revise que sea el correcto."], sha256: "" };
  const bytes = new Uint8Array(await archivo.arrayBuffer());
  const [{ leerXlsx, ErrorXlsx }, { sha256Hex }] = await Promise.all([import("../../scrr/lectorXlsx"), import("../../scrr/lector")]);
  const hojas: string[][][] = [];
  try {
    await leerXlsx(bytes, { alFila: (celdas, hoja) => { (hojas[hoja] ??= []).push(celdas); } });
  } catch (e) {
    return { filas: [], errores: [e instanceof ErrorXlsx ? e.message : "No se pudo leer el archivo. Use la plantilla (.xlsx)."], sha256: "" };
  }
  const hoja = hojas.find((h) => h?.some((f) => f.some((c) => /^\s*contrato\s*$/i.test(c ?? "")))) ?? [];
  const r = procesarArchivoRuta(hoja, tope);
  return { ...r, sha256: await sha256Hex(bytes) };
}
