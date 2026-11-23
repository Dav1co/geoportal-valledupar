// Plantillas y validación de los archivos de la carga del día del modo «Cartera» (Motor SCRR, corte 2). LÓGICA PURA (sin React, sin red, sin DOM): corre en el
// Web Worker y se prueba sola con Node. El servidor vuelve a validar todo: esto es rapidez y buena experiencia, no seguridad.
// Decisión 1 del 20-nov: Excel con modelo estandarizado. Al cargar se exige que vengan EXACTAMENTE las columnas de la plantilla (en cualquier orden);
// lo que no cuadre se rechaza con un mensaje claro.

export type TipoCarga = "cartera" | "pagos" | "actividades";
export type Columna = { clave: string; encabezado: string; ancho: number; nota: string };

/** Las plantillas: encabezado que ve la persona → clave que viaja al servidor. Cartera: los encabezados del archivo «Cartera Detallada Por Suscripción» que
 *  ya carga el script (cargar_diario.py) más «Facturas vencidas» (decisión 2 del 20-nov). Pagos: PROVISIONAL de 3 columnas (decisión 7 del 22-nov).
 *  Actividades: decisión 10 del 20-nov, con DRASTICO (decisión 4 del 22-nov). */
export const PLANTILLAS: Record<TipoCarga, Columna[]> = {
  cartera: [
    { clave: "contrato", encabezado: "Contrato", ancho: 12, nota: "Número del contrato (solo dígitos)." },
    { clave: "estado", encabezado: "Estado", ancho: 12, nota: "Estado del contrato en el sistema comercial." },
    { clave: "identificacion", encabezado: "No. Identificación", ancho: 16, nota: "Se guarda solo en la cartera de suscripción, no en el historial del motor." },
    { clave: "nombre", encabezado: "Nombre", ancho: 30, nota: "Ídem." },
    { clave: "correo", encabezado: "Correo Electrónico", ancho: 24, nota: "Ídem." },
    { clave: "telefono", encabezado: "Teléfono", ancho: 14, nota: "Ídem." },
    { clave: "direccion", encabezado: "Dirección", ancho: 30, nota: "Ídem." },
    { clave: "barrio", encabezado: "Barrio", ancho: 20, nota: "" },
    { clave: "categoria", encabezado: "Categoria", ancho: 18, nota: "" },
    { clave: "subcategoria", encabezado: "Subcategoria", ancho: 18, nota: "" },
    { clave: "ciclo", encabezado: "Ciclo", ancho: 8, nota: "Número de ciclo." },
    { clave: "facturas_pendientes", encabezado: "Facturas pendientes", ancho: 12, nota: "Número entero de 0 a 999." },
    { clave: "facturas_vencidas", encabezado: "Facturas vencidas", ancho: 12, nota: "Las que ya están en rango de suspensión o corte (los rangos de la selección van sobre esta)." },
    { clave: "deuda_total", encabezado: "Deuda total", ancho: 14, nota: "Pesos, sin signo $." },
    { clave: "saldo_pendiente", encabezado: "Saldo Pendiente", ancho: 14, nota: "Paz y salvo = saldo pendiente en cero (decisión 11)." },
    { clave: "saldo_a_favor", encabezado: "Saldo a favor", ancho: 12, nota: "" },
    { clave: "valor_reclamo", encabezado: "Valor reclamo", ancho: 12, nota: "Con reclamo no sale a suspensión (decisión 12)." },
    { clave: "saldo_financiado", encabezado: "Saldo financiado", ancho: 14, nota: "" },
    { clave: "serial_medidor", encabezado: "Elemento medición", ancho: 16, nota: "" },
    { clave: "codigo_reparto", encabezado: "Código reparto", ancho: 12, nota: "" },
    { clave: "ruta", encabezado: "Ruta", ancho: 12, nota: "" },
  ],
  pagos: [
    { clave: "contrato", encabezado: "Contrato", ancho: 12, nota: "Número del contrato." },
    { clave: "fecha_pago", encabezado: "Fecha de pago", ancho: 14, nota: "Fecha del pago (dd/mm/aaaa o fecha de Excel)." },
    { clave: "monto", encabezado: "Monto", ancho: 14, nota: "Pesos pagados, sin signo $. Dos pagos iguales del mismo día se cuentan los dos." },
  ],
  actividades: [
    { clave: "contrato", encabezado: "CONTRATO", ancho: 12, nota: "Número del contrato." },
    { clave: "acta", encabezado: "ACTA", ancho: 12, nota: "Número del acta física (opcional)." },
    { clave: "actividad", encabezado: "ACTIVIDAD", ancho: 16, nota: "Suspensión, Corte, Gestión de cobro, Reinstalación, Reconexión o Reconexión drástica." },
    { clave: "drastico", encabezado: "DRASTICO", ancho: 10, nota: "SÍ solo en un Corte drástico; NO en lo demás." },
    { clave: "estado", encabezado: "ESTADO", ancho: 8, nota: "3 = efectiva, 4 = inefectiva." },
    { clave: "anomalia", encabezado: "ANOMALIA", ancho: 10, nota: "Código 1 a 17 (obligatoria si es inefectiva)." },
    { clave: "observacion", encabezado: "OBSERVACION", ancho: 30, nota: "" },
    { clave: "fecha", encabezado: "FECHA", ancho: 12, nota: "Fecha de la visita." },
    { clave: "hora_inicial", encabezado: "HORA INICIAL", ancho: 10, nota: "hh:mm" },
    { clave: "hora_final", encabezado: "HORA FINAL", ancho: 10, nota: "hh:mm" },
    { clave: "lectura", encabezado: "LECTURA", ancho: 10, nota: "" },
    { clave: "medidor", encabezado: "MEDIDOR", ancho: 14, nota: "" },
    { clave: "marca", encabezado: "MARCA", ancho: 12, nota: "Marca del medidor." },
    { clave: "operario", encabezado: "OPERARIO", ancho: 20, nota: "" },
  ],
};
export const CLAVES: Record<TipoCarga, string[]> = {
  cartera: PLANTILLAS.cartera.map((c) => c.clave), pagos: PLANTILLAS.pagos.map((c) => c.clave), actividades: PLANTILLAS.actividades.map((c) => c.clave),
};
export const NOMBRE_ARCHIVO: Record<TipoCarga, string> = { cartera: "Cartera del día", pagos: "Pagos del día", actividades: "Actividades" };

export const normalizarEncabezado = (s: string): string =>
  s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]+/g, " ").trim();

export type Mapeo = { indices: number[] };   // posición en el archivo de cada columna de la plantilla
/** Validación estricta: exactamente las columnas de la plantilla, en cualquier orden. Devuelve el mapeo o el mensaje para la persona. */
export function mapearEncabezados(tipo: TipoCarga, encabezado: string[]): Mapeo | { error: string } {
  const p = PLANTILLAS[tipo]; const pos = new Map<string, number>(); const extra: string[] = []; const repetidas: string[] = [];
  encabezado.forEach((h, i) => {
    const n = normalizarEncabezado(h ?? ""); if (!n) return;
    const col = p.find((c) => normalizarEncabezado(c.encabezado) === n);
    if (!col) extra.push(String(h).trim().slice(0, 40)); else if (pos.has(col.clave)) repetidas.push(col.encabezado); else pos.set(col.clave, i);
  });
  const faltan = p.filter((c) => !pos.has(c.clave)).map((c) => c.encabezado);
  const partes: string[] = [];
  if (faltan.length) partes.push(`${faltan.length === 1 ? "le falta la columna" : "le faltan las columnas"} ${faltan.map((x) => `«${x}»`).join(", ")}`);
  if (extra.length) partes.push(`${extra.length === 1 ? "sobra la columna" : "sobran las columnas"} ${extra.slice(0, 6).map((x) => `«${x}»`).join(", ")}${extra.length > 6 ? ` y ${extra.length - 6} más` : ""}`);
  if (repetidas.length) partes.push(`${repetidas.length === 1 ? "está repetida la columna" : "están repetidas las columnas"} ${repetidas.map((x) => `«${x}»`).join(", ")}`);
  if (partes.length) return { error: `El archivo no tiene las columnas de la plantilla de ${NOMBRE_ARCHIVO[tipo]}: ${partes.join("; ")}. Descargue la plantilla y copie los datos en ella.` };
  return { indices: p.map((c) => pos.get(c.clave)!) };
}

// ---------------------------------------------------------------------------------------------------- números, fechas, horas y contratos
/** Texto monetario o numérico → número canónico (punto decimal, sin miles) o null. «$ 1,234.00», «1.234,56», «(1,234)», «2052143.2», «-5», «1.5E+3». */
export function numeroCanonico(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  let t = String(v).trim().replace(/ /g, " ");
  if (t === "" || /^(nan|null|none|-|n\/a)$/i.test(t)) return null;
  if (/^-?\d+(\.\d+)?e[+-]?\d+$/i.test(t)) { const n = Number(t); if (!Number.isFinite(n)) return null; t = String(Math.round(n * 10000) / 10000); }
  let neg = false;
  if (/^\(.*\)$/.test(t)) { neg = true; t = t.slice(1, -1); }
  t = t.replace(/[$\s]/g, "");
  if (t.startsWith("-")) { neg = true; t = t.slice(1); }
  if (t === "" || /[^0-9.,]/.test(t)) return null;
  const c = (t.match(/,/g) ?? []).length, p = (t.match(/\./g) ?? []).length;
  if (c && p) {
    if (t.lastIndexOf(".") > t.lastIndexOf(",")) t = t.replace(/,/g, "");
    else t = t.replace(/\./g, "").replace(",", ".");
  } else if (c) {
    t = /^\d{1,3}(,\d{3})+$/.test(t) ? t.replace(/,/g, "") : t.replace(",", ".");
  } else if (p > 1) {
    if (!/^\d{1,3}(\.\d{3})+$/.test(t)) return null; t = t.replace(/\./g, "");
  }
  if (!/^\d+(\.\d+)?$/.test(t)) return null;
  const [e, d = ""] = t.split(".");
  if (e.replace(/^0+/, "").length > 12) return null;
  t = d.length > 4 ? `${e}.${d.slice(0, 4)}` : t;
  const n = t.replace(/^0+(?=\d)/, "").replace(/\.0+$/, "");
  return (neg && Number(n) !== 0 ? "-" : "") + n;
}

/** Fecha → «aaaa-mm-dd» o null. Acepta número de serie de Excel, ISO (con hora) y dd/mm/aaaa (con hora). */
export function fechaCanonica(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const t = String(v).trim();
  if (t === "") return null;
  let y: number, m: number, d: number; let r: RegExpMatchArray | null;
  if ((r = t.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ].*)?$/))) { y = +r[1]; m = +r[2]; d = +r[3]; }
  else if ((r = t.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})(?:[T ].*)?$/))) { d = +r[1]; m = +r[2]; y = +r[3]; }
  else if (/^\d{5}(\.\d+)?$/.test(t) && +t > 36000 && +t < 80000) {
    const f = new Date(Date.UTC(1899, 11, 30) + Math.floor(+t) * 86400000); y = f.getUTCFullYear(); m = f.getUTCMonth() + 1; d = f.getUTCDate();
  } else return null;
  const f = new Date(Date.UTC(y, m - 1, d));
  if (f.getUTCFullYear() !== y || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d || y < 2020 || y > 2100) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Hora → «hh:mm» o null. Acepta «8:05», «08:05:30», «8:05 a. m.» y la fracción de día de Excel (0,3402…). */
export function horaCanonica(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const t = String(v).trim().toLowerCase().replace(/\s+/g, " ");
  if (t === "") return null;
  let h: number, mi: number; let r: RegExpMatchArray | null;
  if ((r = t.match(/^(\d{1,2}):(\d{2})(?::\d{2})?\s*(a\.? ?m\.?|p\.? ?m\.?)?$/))) {
    h = +r[1]; mi = +r[2];
    if (r[3]) { const pm = r[3].startsWith("p"); if (h < 1 || h > 12) return null; h = (h % 12) + (pm ? 12 : 0); }
  } else if (/^0?\.\d+$|^0$/.test(t)) { const min = Math.round(+t * 1440); h = Math.floor(min / 60) % 24; mi = min % 60; }
  else return null;
  if (h > 23 || mi > 59) return null;
  return `${String(h).padStart(2, "0")}:${String(mi).padStart(2, "0")}`;
}

/** Contrato → solo dígitos (hasta 12) o null. «123.0» y «1.23E+5» (números de Excel) también. */
export function contratoCanonico(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  let t = String(v).trim();
  if (/^\d+(\.\d+)?e\+\d+$/i.test(t)) { const n = Number(t); if (!Number.isSafeInteger(n)) return null; t = String(n); }
  t = t.replace(/\.0+$/, "");
  return /^\d{1,12}$/.test(t) ? t : null;
}
/** SÍ/NO → «SI», «NO» o null. */
export function siNo(v: unknown): string | null {
  const t = String(v ?? "").trim().toUpperCase().replace("Í", "I");
  if (["", "NO", "N", "0", "FALSO", "FALSE"].includes(t)) return "NO";
  if (["SI", "S", "1", "X", "VERDADERO", "TRUE"].includes(t)) return "SI";
  return null;
}
const texto = (v: unknown, max: number): string | null => {
  if (v === null || v === undefined) return null;
  const t = String(v).trim();
  return t === "" ? null : t.slice(0, max);
};
const ACTIVIDADES = /SUSPEN|CORTE|COBRO|GESTION|REINSTAL|RECONEX|RECONECC/;
const sinTildes = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();

export type FilaProcesada = { valores: (string | null)[]; error: string | null };
/** Convierte una fila cruda en los valores canónicos de CLAVES[tipo] y dice por qué se rechazaría (el servidor decide). */
export function procesarFila(tipo: TipoCarga, mapeo: Mapeo, cruda: string[]): FilaProcesada {
  const claves = CLAVES[tipo]; const g = (clave: string): string | undefined => cruda[mapeo.indices[claves.indexOf(clave)]];
  const v: Record<string, string | null> = {}; let error: string | null = null;
  const rechazar = (m: string) => { if (!error) error = m; };
  v.contrato = contratoCanonico(g("contrato")); if (v.contrato === null) rechazar("Contrato ausente o no numérico");
  if (tipo === "cartera") {
    for (const [c, max] of [["estado", 60], ["identificacion", 40], ["nombre", 200], ["correo", 200], ["telefono", 60], ["direccion", 200], ["barrio", 80], ["categoria", 80],
                            ["subcategoria", 80], ["serial_medidor", 60], ["codigo_reparto", 40], ["ruta", 80]] as const) v[c] = texto(g(c), max);
    const ci = g("ciclo"); v.ciclo = texto(ci, 10);
    if (v.ciclo !== null && numeroCanonico(v.ciclo) === null) rechazar("Ciclo no válido");   // se guarda tal como viene («05» sigue siendo «05», como lo deja hoy el script)
    for (const c of ["facturas_pendientes", "facturas_vencidas"]) {
      const n = numeroCanonico(g(c)); v[c] = n;
      if (n === null || !Number.isInteger(Number(n)) || Number(n) < 0 || Number(n) > 999) rechazar(c === "facturas_pendientes" ? "Facturas pendientes ausentes o no válidas" : "Facturas vencidas ausentes o no válidas");
    }
    for (const c of ["deuda_total", "saldo_pendiente", "saldo_a_favor", "valor_reclamo", "saldo_financiado"]) { v[c] = numeroCanonico(g(c)); if (v[c] === null) rechazar("Cifra obligatoria ausente o con formato no válido"); }
  } else if (tipo === "pagos") {
    v.fecha_pago = fechaCanonica(g("fecha_pago")); if (v.fecha_pago === null) rechazar("Fecha de pago ausente o no válida");
    v.monto = numeroCanonico(g("monto")); if (v.monto === null || Number(v.monto) === 0) rechazar("Monto ausente, en cero o no válido");
  } else {
    v.acta = texto(g("acta"), 40);
    v.actividad = texto(g("actividad"), 60); if (v.actividad === null || !ACTIVIDADES.test(sinTildes(v.actividad))) rechazar("Actividad no reconocida");
    const d = siNo(g("drastico")); v.drastico = d ?? texto(g("drastico"), 10); if (d === null) rechazar("Drástico debe ser SÍ o NO");
    if (d === "SI" && v.actividad && !/CORTE/.test(sinTildes(v.actividad))) rechazar("La marca de drástico solo aplica a Corte");
    const est = numeroCanonico(g("estado")); v.estado = est; if (est !== "3" && est !== "4") rechazar("Estado distinto de 3 (efectiva) o 4 (inefectiva)");
    v.anomalia = texto(g("anomalia"), 10);
    if (v.anomalia !== null) { const n = numeroCanonico(v.anomalia); if (n === null || !Number.isInteger(Number(n)) || Number(n) < 1 || Number(n) > 17) rechazar("Anomalía fuera del catálogo (1 a 17)"); else v.anomalia = n; }
    else if (est === "4") rechazar("Inefectiva sin anomalía");
    v.observacion = texto(g("observacion"), 300);
    v.fecha = fechaCanonica(g("fecha")); if (v.fecha === null) rechazar("Fecha ausente o no válida");
    for (const c of ["hora_inicial", "hora_final"]) { const t = texto(g(c), 20); v[c] = t === null ? null : horaCanonica(t); if (t !== null && v[c] === null) rechazar(c === "hora_inicial" ? "Hora inicial no válida" : "Hora final no válida"); }
    const lec = texto(g("lectura"), 20); v.lectura = lec === null ? null : numeroCanonico(lec); if (lec !== null && (v.lectura === null || !Number.isInteger(Number(v.lectura)) || Number(v.lectura) < 0)) rechazar("Lectura no válida");
    v.medidor = texto(g("medidor"), 40); v.marca = texto(g("marca"), 40); v.operario = texto(g("operario"), 80);
  }
  return { valores: claves.map((c) => v[c] ?? null), error };
}
export function filaComoObjeto(tipo: TipoCarga, valores: (string | null)[]): Record<string, string> {
  const o: Record<string, string> = {};
  CLAVES[tipo].forEach((c, i) => { if (valores[i] !== null) o[c] = valores[i] as string; });
  return o;
}

// ---------------------------------------------------------------------------------------------------- Resumen del archivo completo
export type Resumen = {
  tipo: TipoCarga; filas: number; rechazadas: number; pctRechazadas: number; causas: Record<string, number>; contratosDistintos: number; hojas: string[];
  extra: Record<string, number | string | null>;
};
export class Acumulador {
  readonly filas: (string | null)[][] = [];   // TODAS las filas (también las rechazadas: el servidor las vuelve a validar y registra su causa)
  rechazadas = 0; private causas: Record<string, number> = {}; private contratos = new Set<string>();
  private extra: Record<string, number> = { con_saldo_pendiente: 0, con_facturas_vencidas: 0, con_reclamo: 0, comodin_o_categoria_menos_1: 0, monto_total: 0, efectivas: 0, inefectivas: 0, cortes_drasticos: 0 };
  private minFecha: string | null = null; private maxFecha: string | null = null;
  constructor(readonly tipo: TipoCarga, readonly mapeo: Mapeo, private comodin = "99999999") {}
  agregar(cruda: string[]): void {
    if (cruda.every((c) => (c ?? "").trim() === "")) return;
    const p = procesarFila(this.tipo, this.mapeo, cruda);
    this.filas.push(p.valores);
    if (p.error) { this.rechazadas++; this.causas[p.error] = (this.causas[p.error] ?? 0) + 1; return; }
    const k = CLAVES[this.tipo]; const val = (c: string) => p.valores[k.indexOf(c)];
    const con = val("contrato"); if (con) this.contratos.add(con);
    const fecha = (f: string | null) => { if (f) { if (!this.minFecha || f < this.minFecha) this.minFecha = f; if (!this.maxFecha || f > this.maxFecha) this.maxFecha = f; } };
    if (this.tipo === "cartera") {
      if (Number(val("saldo_pendiente")) > 0) this.extra.con_saldo_pendiente++;
      if (Number(val("facturas_vencidas")) > 0) this.extra.con_facturas_vencidas++;
      if (Number(val("valor_reclamo")) > 0) this.extra.con_reclamo++;
      if (con === this.comodin || (val("categoria") ?? "").startsWith("-1")) this.extra.comodin_o_categoria_menos_1++;
    } else if (this.tipo === "pagos") { this.extra.monto_total += Number(val("monto")); fecha(val("fecha_pago")); }
    else { if (val("estado") === "3") this.extra.efectivas++; else this.extra.inefectivas++; if (val("drastico") === "SI") this.extra.cortes_drasticos++; fecha(val("fecha")); }
  }
  resumen(hojas: string[]): Resumen {
    const filas = this.filas.length;
    return { tipo: this.tipo, filas, rechazadas: this.rechazadas, pctRechazadas: filas ? Math.round((this.rechazadas * 10000) / filas) / 100 : 0, causas: { ...this.causas },
             contratosDistintos: this.contratos.size, hojas, extra: { ...this.extra, primera_fecha: this.minFecha, ultima_fecha: this.maxFecha } };
  }
}

/** Huella SHA-256 (hex) de los bytes del archivo. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const h = await crypto.subtle.digest("SHA-256", bytes as unknown as BufferSource);
  return Array.from(new Uint8Array(h), (x) => x.toString(16).padStart(2, "0")).join("");
}
