import { pedir } from "./apiTecnica";

// Cliente de químicos de planta (Técnica fase 1, Corte 7a; §29) en la Edge geoportal-tecnica. Todo en kg; una sola bodega. Quién puede qué lo decide el SERVIDOR
// (catálogo, saldo, inventario, ajuste y comparación: supervisor de planta y administrador). La ficha técnica en PDF llega como URL firmada de 60 s.
export type Ficha = { url: string; expira_en: string } | null;
export type Quimico = {
  codigo: string; nombre: string; rol: "coagulante" | "desinfectante" | "auxiliar" | "otro"; activo: boolean; dosis_optima_ppm: number | null; potabilizacion: boolean;
  ficha: Ficha; ficha_en: string | null; saldo_kg: number | null; inventario_dia: string | null; ultimo_movimiento: string | null;
};
export type Catalogo = { quimicos: Quimico[]; parametros: Record<string, number>; puede_editar: boolean };
export type Historial = {
  codigo: string; nombre: string;
  eventos: { tipo: string; dosis_optima_ppm: number | null; potabilizacion: boolean | null; activo: boolean | null; ficha: Ficha; motivo: string; autor: string; creado_en: string }[];
  movimientos: { tipo: string; dia: string; cantidad: number; unidad: string; cantidad_kg: number; planta: string | null; para_que: string | null; dosis_optima_ppm: number | null;
    proveedor: string | null; remision: string | null; lote: string | null; vence: string | null; motivo: string | null; autor: string; registrado_en: string;
    remision_foto?: Ficha }[];      // Corte 7c: la foto de la remisión, como URL firmada de 60 s (solo en el historial del supervisor)
};
export type FilaComparacion = { dia: string; planta: string; planta_nombre: string; quimico: string; quimico_nombre: string; qi_lps: number; volumen_m3: number;
  dosis_optima_ppm: number | null; esperado_kg: number | null; usado_kg: number; desvio_pct: number | null; marca: boolean | null };
export type Comparacion = { desde: string; hasta: string; desvio_pct: number; marca_activa: boolean; filas: FilaComparacion[] };

// Corte 7b: formularios del operador (Entrada y Uso de químicos). Sin saldo ni dosis óptima: el operador no los ve.
export type FormularioQuimicos = { formulario: string; hoy: string; unidades?: string[]; dias_atras: number; quimicos: { codigo: string; nombre: string; potabilizacion: boolean }[];
  plantas: { codigo: string; nombre: string }[]; para_que: string[] | null };
export type MovimientoGuardado = { movimiento_id: number; cantidad_kg: number; repetido: boolean };

// Corte 7c: parámetros de químicos que se editan desde la pantalla (supervisor de planta y administrador), con su rango y su último cambio.
export type ParametroQuimico = { clave: string; valor: number; minimo: number; maximo: number; descripcion: string;
  ultimo: { antes: number; despues: number; motivo: string; autor: string; creado_en: string } | null };

export const apiQuimicos = {
  parametros: () => pedir<{ parametros: ParametroQuimico[] }>("quimico_parametros"),
  fijarParametro: (clave: string, valor: number, motivo: string) => pedir<{ clave: string; antes: number; valor: number }>("quimico_parametro_fijar", { cuerpo: { clave, valor, motivo } }),
  prepararRemision: () => pedir<{ ruta: string; max_bytes: number; url_subida: string; token: string }>("quimico_remision_preparar", { cuerpo: {} }),
  formulario: (formulario: "entrada_quimicos" | "uso_quimicos") => pedir<FormularioQuimicos>("quimicos_formulario", { qs: { formulario } }),
  entrada: (datos: { quimico: string; cantidad: number; unidad: "t" | "kg"; dia: string; proveedor: string | null; remision: string | null; lote: string | null; vence: string | null; foto?: string }, clave_envio: string) =>
    pedir<MovimientoGuardado>("quimico_entrada", { cuerpo: { datos, clave_envio } }),
  uso: (datos: { quimico: string; cantidad: number; unidad: "kg"; dia: string; para_que: string; planta: string | null }, clave_envio: string) =>
    pedir<MovimientoGuardado>("quimico_uso", { cuerpo: { datos, clave_envio } }),
  catalogo: () => pedir<Catalogo>("quimicos_catalogo"),
  historial: (quimico: string) => pedir<Historial>("quimico_historial", { qs: { quimico } }),
  prepararFicha: () => pedir<{ ruta: string; max_bytes: number; url_subida: string; token: string }>("quimico_ficha_preparar", { cuerpo: {} }),
  crear: (d: { nombre: string; rol: string; potabilizacion: boolean; dosis_optima_ppm: number | null; ficha: string; motivo: string }) => pedir<{ codigo: string }>("quimico_crear", { cuerpo: d }),
  fijar: (quimico: string, cambios: Record<string, unknown>, ficha: string | null, motivo: string) => pedir<{ cambios: string[] }>("quimico_fijar", { cuerpo: { quimico, cambios, ficha, motivo } }),
  inventario: (quimico: string, cantidad: number, unidad: "kg" | "t", corte: string, motivo: string) => pedir<{ saldo_kg: number }>("quimico_inventario", { cuerpo: { quimico, cantidad, unidad, corte, motivo } }),
  ajuste: (quimico: string, kg: number, motivo: string) => pedir<{ saldo_kg: number }>("quimico_ajuste", { cuerpo: { quimico, kg, motivo } }),
  comparacion: (desde: string, hasta: string) => pedir<Comparacion>("quimicos_comparacion", { qs: { desde, hasta } }),
};

/** Sube el PDF de la ficha técnica a su URL firmada (PUT directo a Storage, esa ruta exacta). Devuelve la ruta para crear o cambiar el químico. */
export async function subirFicha(archivo: File): Promise<string> {
  if (archivo.type !== "application/pdf" && !archivo.name.toLowerCase().endsWith(".pdf")) throw new Error("La ficha técnica debe ser un PDF.");
  const p = await apiQuimicos.prepararFicha();
  if (archivo.size > p.max_bytes) throw new Error(`El PDF pasa de ${Math.round(p.max_bytes / 1048576)} MB.`);
  let r: Response;
  try {
    r = await fetch(p.url_subida, { method: "PUT", headers: { "Content-Type": "application/pdf", "x-upsert": "false" }, body: archivo });
  } catch {
    throw new Error("No se pudo subir el PDF: revise su conexión.");
  }
  if (!r.ok && r.status !== 409) throw new Error("El servicio de archivos no recibió el PDF. Intente de nuevo.");
  return p.ruta;
}

/** Corte 7c: achica la foto del celular (lado mayor de 1.600 px, JPEG) para que pese poco y suba con mala señal. Devuelve un JPEG. */
export async function reducirFoto(archivo: Blob, ladoMax = 1600, calidad = 0.82): Promise<Blob> {
  let img: ImageBitmap;
  try { img = await createImageBitmap(archivo); } catch { throw new Error("Ese archivo no es una foto que se pueda leer. Tome la foto de nuevo."); }
  const escala = Math.min(1, ladoMax / Math.max(img.width, img.height));
  const lienzo = document.createElement("canvas");
  lienzo.width = Math.max(1, Math.round(img.width * escala)); lienzo.height = Math.max(1, Math.round(img.height * escala));
  const ctx = lienzo.getContext("2d");
  if (!ctx) throw new Error("No se pudo preparar la foto.");
  ctx.drawImage(img, 0, 0, lienzo.width, lienzo.height);
  img.close?.();
  const blob = await new Promise<Blob | null>((ok) => lienzo.toBlob(ok, "image/jpeg", calidad));
  if (!blob) throw new Error("No se pudo preparar la foto.");
  return blob;
}

/** Corte 7c: reserva la ruta de la foto de la remisión y la sube a su URL firmada (PUT directo a Storage). Devuelve la ruta para la entrada. */
export async function subirRemision(foto: Blob): Promise<string> {
  const p = await apiQuimicos.prepararRemision();
  if (foto.size > p.max_bytes) throw new Error(`La foto pasa de ${Math.round(p.max_bytes / 1048576)} MB.`);
  let r: Response;
  try {
    r = await fetch(p.url_subida, { method: "PUT", headers: { "Content-Type": "image/jpeg", "x-upsert": "false" }, body: foto });
  } catch {
    throw new Error("No se pudo subir la foto: revise su conexión.");
  }
  if (!r.ok && r.status !== 409) throw new Error("El servicio de archivos no recibió la foto. Intente de nuevo.");
  return p.ruta;
}
