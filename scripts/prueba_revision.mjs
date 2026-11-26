// Prueba de la lógica PURA de la pantalla «Revisión de reportes» (Paso C): registro de columnas, filtros, armado de CSV, escritor de Excel con varias hojas, formato colombiano
// y el ejemplo de un campo ficticio que aparece en detalle, tabla y descarga SIN reescribir pantallas. Sin red ni navegador.
// Uso: node scripts/prueba_revision.mjs [--medir]     (usa el paquete typescript del proyecto; --medir agrega la medición de memoria del Excel con muchas filas)
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const out = mkdtempSync(join(tmpdir(), "revision_"));
const dir = join(aqui, "..", "src", "campo", "dashboard");
for (const f of ["formatoRevision", "columnas", "filtros", "archivo", "xlsxRevision"]) {
  const js = ts.transpileModule(readFileSync(join(dir, f + ".ts"), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText.replace(/(from\s+["']\.\/[a-zA-Z]+)(["'])/g, "$1.js$2");
  writeFileSync(join(out, f + ".js"), js);
}
const imp = (f) => import(pathToFileURL(join(out, f + ".js")).href);
const F = await imp("formatoRevision"), C = await imp("columnas"), FI = await imp("filtros"), A = await imp("archivo"), X = await imp("xlsxRevision");
const avisos = []; const cw = console.warn; console.warn = (...a) => avisos.push(a.join(" "));
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---------- Formato colombiano ----------
ok("fecha del instante en Bogotá (UTC-5)", F.fmtInstante("2026-11-01T04:59:59Z") === "31/10/2026 23:59" && F.fmtInstante("2026-11-01T05:00:00Z") === "01/11/2026 00:00");
ok("hoy en Bogotá respeta la frontera de día", F.hoyBogota(new Date("2026-11-02T04:59:00Z")) === "2026-11-01" && F.hoyBogota(new Date("2026-11-02T05:00:00Z")) === "2026-11-02");
ok("miles con punto y decimales con coma", F.fmtMiles(12345) === "12.345" && F.fmtNumero(1234.5, 2) === "1.234,5" && F.fmtNumero(0.25, 2) === "0,25");
ok("duraciones sin juicio: 45 s, 45 min, 2 h 15 min, 3 d 4 h", F.fmtDuracion(45) === "45 s" && F.fmtDuracion(2700) === "45 min" && F.fmtDuracion(8100) === "2 h 15 min" && F.fmtDuracion(3 * 86400 + 4 * 3600) === "3 d 4 h" && F.fmtDuracion(null) === "—");
ok("fechas locales y de día", F.fmtLocal("2026-11-01T00:00:00") === "01/11/2026 00:00" && F.fmtDia("2026-11-12") === "12/11/2026" && F.fmtLocal(null) === "—");
ok("sumar días cruza el mes", F.sumarDias("2026-11-02", -3) === "2026-10-30");
ok("normalizar quita tildes y mayúsculas", F.normalizar("Daño EN la Red") === "dano en la red");

// ---------- Registro de columnas ----------
const fila = (o = {}) => ({ id: "11111111-2222-4333-8444-555555555555", seq: 10, tipo: { codigo: "visita_x", nombre: "Visita de prueba" }, grupo: { codigo: "g1", nombre: "Grupo 1" }, subtipo: null, descripcion: "Se ve fuga", contrato: "123456", contrato_verificado: true,
  lat: 10.46, lon: -73.25, precision_m: 8.5, riesgo_inmediato: false, origen: "campo", fuera_de_zona: false, autor: "a@x.co", registrado_en: "2026-11-01T05:00:00Z", estado: "reportado", estado_desde: null, oculto: false, reporte_original_id: null,
  grupo_duplicados: null, tamano_grupo: null, n_fotos: 2, ...o });
const ctx = { estados: new Map([["reportado", "Reportado"], ["en_revision", "En revisión"]]) };
const base = C.columnasBase(false), baseD = C.columnasBase(true);
ok("las columnas base son las 34 (23 del contrato + inicio, duración y origen del inicio de la pasada 14/11 + 8 del registro flexible del 25-nov), con clave única", base.length === 34 && new Set(base.map((c) => c.clave)).size === 34);
{ // Pasada 14/11: inicio y duración
  const ctx0 = { estados: new Map() };
  const f0 = { registrado_en: "2026-11-14T15:30:00Z", inicio_en: "2026-11-14T15:00:00Z", inicio_origen: "dispositivo" };
  const ci = base.find((c) => c.clave === "inicio"), cd = base.find((c) => c.clave === "duracion"), co = base.find((c) => c.clave === "inicio_origen");
  ok("inicio: hora de Bogotá con la marca «(celular)»", ci.texto(f0, ctx0) === "14/11/2026 10:00 (celular)", ci.texto(f0, ctx0));
  ok("duración: 30 min (valor numérico en minutos para el Excel)", cd.texto(f0, ctx0) === "30 min" && cd.valor(f0) === 30, cd.texto(f0, ctx0));
  ok("inicio y duración vacíos en reportes de antes (sin inicio)", ci.texto({ registrado_en: "2026-11-14T15:30:00Z" }, ctx0) === "" && cd.valor({ registrado_en: "2026-11-14T15:30:00Z" }) === null);
  ok("descarga: usa inicio_local y duracion_min de la base", ci.texto({ inicio_local: "2026-11-14T10:00:00", inicio_origen: "dispositivo", duracion_min: 12.5 }, ctx0) === "14/11/2026 10:00 (celular)" && cd.valor({ duracion_min: 12.5 }) === 12.5);
  ok("origen del inicio: Celular / Servidor / vacío", co.texto(f0, ctx0) === "Celular" && co.texto({ inicio_origen: "servidor" }, ctx0) === "Servidor" && co.texto({}, ctx0) === "");
}
ok("sin datos del Paso D no se muestran por omisión consecutivo, resultado ni causal; con ellos sí", !base.filter((c) => ["consecutivo", "resultado", "causal"].includes(c.clave)).some((c) => c.porOmision) && baseD.filter((c) => ["consecutivo", "resultado", "causal"].includes(c.clave)).every((c) => c.porOmision));
ok("hay columnas por omisión de fecha, tipo, grupo, subtipo, estado, riesgo, oculto, fuera de zona, contrato, fotos, duplicados, origen, autor y descripción", ["registrado_en", "tipo", "grupo", "subtipo", "estado", "riesgo_inmediato", "oculto", "fuera_de_zona", "contrato", "n_fotos", "grupo_duplicados", "origen", "autor", "descripcion"].every((k) => base.find((c) => c.clave === k)?.porOmision));
ok("el autor NO va en las descargas por omisión y las coordenadas y el identificador sí", !base.find((c) => c.clave === "autor").enDescarga && base.find((c) => c.clave === "lat").enDescarga && base.find((c) => c.clave === "id").enDescarga);
ok("ninguna columna base lee rutas de Storage ni URLs", !base.some((c) => /ruta|storage|url/i.test(c.clave)));
const f1 = fila({ fuera_de_zona: true, riesgo_inmediato: true, oculto: true, grupo_duplicados: "g", tamano_grupo: 3, estado: "en_revision" });
const txt = (k, f = f1) => base.find((c) => c.clave === k).texto(f, ctx);
ok("textos de columnas: Sí/No, estado con nombre, duplicados con cantidad, fecha en Bogotá", txt("riesgo_inmediato") === "Sí" && txt("oculto") === "Sí" && txt("estado") === "En revisión" && txt("grupo_duplicados") === "3 en el grupo" && txt("registrado_en") === "01/11/2026 00:00" && txt("origen") === "Campo");
ok("contrato no verificado queda en su propia columna", base.find((c) => c.clave === "contrato_verificado").texto(fila({ contrato_verificado: false }), ctx) === "No");

// Campos propios: de las definiciones del catálogo
const campos = [
  { codigo: "lectura", nombre: "Lectura", tipo_dato: "decimal", unidad: "m³", orden: 1, activo: true },
  { codigo: "sellos", nombre: "Sellos", tipo_dato: "entero", orden: 2, activo: true },
  { codigo: "caja", nombre: "Despeje de caja", tipo_dato: "si_no", orden: 3, activo: true },
  { codigo: "diametro", nombre: "Diámetro", tipo_dato: "opcion", opciones: [{ codigo: "d12", nombre: "1/2 pulgada" }], orden: 4, activo: true },
  { codigo: "materiales", nombre: "Materiales", tipo_dato: "opciones", opciones: [{ codigo: "pvc", nombre: "PVC" }, { codigo: "cu", nombre: "Cobre" }], orden: 5, activo: true },
  { codigo: "cuando", nombre: "Cuándo", tipo_dato: "dia_hora", orden: 6, activo: true },
  { codigo: "nota", nombre: "Nota", tipo_dato: "texto", orden: 7, activo: false },
  { codigo: "telefono", nombre: "Teléfono", tipo_dato: "texto", sensible: true, orden: 8, activo: true },
];
const datos = { lectura: 1234.5, sellos: 2, caja: true, diametro: "d12", materiales: ["pvc", "cu"], cuando: "2026-11-05T14:30", nota: "texto desactivado" };
const propias = C.columnasPropias(campos);
ok("las columnas propias salen del catálogo (los campos sensibles NUNCA)", propias.length === 7 && !propias.some((c) => c.clave === "dato:telefono") && propias.every((c) => c.origen === "dato" && c.clave.startsWith("dato:")));
const fd = fila({ datos });
const t = (k) => propias.find((c) => c.clave === "dato:" + k).texto(fd, ctx);
ok("cada tipo de dato se formatea: decimal con unidad, entero, sí/no, opción por nombre, opciones, día y hora", t("lectura") === "1.234,5 m³" && t("sellos") === "2" && t("caja") === "Sí" && t("diametro") === "1/2 pulgada" && t("materiales") === "PVC; Cobre" && t("cuando") === "05/11/2026 14:30");
ok("la etiqueta de la columna lleva la unidad", propias.find((c) => c.clave === "dato:lectura").etiqueta === "Lectura (m³)");
ok("sin filtro de tipo la tabla NO trae columnas propias; con filtro de tipo sí", C.columnasTabla(base, propias, false).every((c) => c.origen === "base") && C.columnasTabla(base, propias, true).filter((c) => c.origen === "dato").length === 7);
const pares = C.paresDeDatos({ ...datos, clave_rara: 7, telefono: "300" }, campos);
ok("detalle: pares etiqueta/valor en el orden del catálogo, sin sensibles, y la clave desconocida va genérica sin fallar", pares.length === 8 && pares[0].etiqueta === "Lectura" && pares.at(-1).etiqueta === "clave_rara" && pares.at(-1).generica === true && !pares.some((p) => p.etiqueta === "Teléfono") && avisos.some((a) => a.includes("clave_rara")));
ok("tipo de dato desconocido: se muestra como texto con aviso, nunca error", C.textoDeDato({ tipo_dato: "geografia" }, "POINT") === "POINT" && avisos.some((a) => a.includes("geografia")));
ok("valores ausentes son vacíos", C.textoDeDato({ tipo_dato: "entero" }, null) === "" && C.paresDeDatos(undefined, campos).length === 0);
const def = { grupos: [{ codigo: "g1", nombre: "G", tipos: [{ codigo: "visita_x", nombre: "V", campos: [campos[0]] }] }], definiciones: [{ tipo: "visita_x", campos, fotos: [{ codigo: "a", nombre: "Medidor" }] }] };
ok("definiciones del supervisor incluyen campos desactivados; sin ellas se usan los del tipo en el formulario", C.camposDelTipo(def, "visita_x").length === 8 && C.camposDelTipo({ grupos: def.grupos }, "visita_x").length === 1 && C.camposDelTipo(def, "otro").length === 0);
ok("las etiquetas de foto por tipo se leen de las definiciones", C.fotosDelTipo(def, "visita_x")[0].nombre === "Medidor");
ok("hayPasoD detecta consecutivo, resultado, causal o datos", !C.hayPasoD([fila()]) && C.hayPasoD([fila({ consecutivo: "SUS-000001" })]) && C.hayPasoD([fila({ datos: { a: 1 } })]) && !C.hayPasoD([fila({ datos: {} })]));
// Orden
const ord = (col, dir, filas) => C.ordenar(filas, base.find((c) => c.clave === col), dir).map((f) => f.id);
const fs = [fila({ id: "a", n_fotos: 3, contrato: "b" }), fila({ id: "b", n_fotos: 1, contrato: null }), fila({ id: "c", n_fotos: 2, contrato: "a" })];
ok("orden numérico ascendente y descendente", igual(ord("n_fotos", "asc", fs), ["b", "c", "a"]) && igual(ord("n_fotos", "desc", fs), ["a", "c", "b"]));
ok("los vacíos van al final en ambos sentidos", ord("contrato", "asc", fs).at(-1) === "b" && ord("contrato", "desc", fs).at(-1) === "b");
ok("el orden es estable y sin columna deja el orden", igual(C.ordenar(fs, null, "asc").map((f) => f.id), ["a", "b", "c"]));
ok("orden de 20.000 filas en menos de 1 s", (() => { const g = Array.from({ length: 20000 }, (_, i) => fila({ id: String(i), n_fotos: (i * 7919) % 1000 })); const t0 = Date.now(); C.ordenar(g, base.find((c) => c.clave === "n_fotos"), "asc"); return Date.now() - t0 < 1000; })());

// ---------- El campo FICTICIO: aparece en detalle, tabla y descarga sin tocar pantallas ----------
const ficticio = { codigo: "diametro_acometida", nombre: "Diámetro de la acometida", tipo_dato: "entero", unidad: "mm", orden: 10, activo: true };
const defFic = { grupos: [{ codigo: "g", nombre: "G", tipos: [] }], definiciones: [{ tipo: "ejemplo_simulado", campos: [ficticio], fotos: [] }] };
const filaFic = fila({ tipo: { codigo: "ejemplo_simulado", nombre: "Ejemplo simulado" }, datos: { diametro_acometida: 25 } });
const filaRara = fila({ tipo: { codigo: "ejemplo_simulado", nombre: "Ejemplo simulado" }, datos: { clave_rara: 1 } });
const propFic = C.columnasPropias(C.camposDelTipo(defFic, "ejemplo_simulado"));
const cTabla = C.columnasTabla(base, propFic, true).find((c) => c.clave === "dato:diametro_acometida");
ok("campo ficticio: aparece en la TABLA con filtro de tipo, con su etiqueta y unidad, ordenable", cTabla?.etiqueta === "Diámetro de la acometida (mm)" && cTabla.texto(filaFic, ctx) === "25 mm" && cTabla.ordenable);
ok("campo ficticio: aparece en el DETALLE como «Diámetro de la acometida: 25 mm»", igual(C.paresDeDatos(filaFic.datos, [ficticio]).map((p) => `${p.etiqueta}: ${p.valor}`), ["Diámetro de la acometida: 25 mm"]));
const colsDesc = C.columnasDescarga(base, propFic, { conTipo: true, incluirAutor: false });
ok("campo ficticio: aparece en la DESCARGA (CSV con encabezado y valor)", A.cabeceraCsv(colsDesc, false).includes("Diámetro de la acometida (mm)") && A.filaCsv(filaFic, colsDesc, ctx, false).includes(";25 mm;") === false && A.filaCsv(filaFic, colsDesc, ctx, false).includes("25 mm"));
ok("campo ficticio: una clave que el catálogo no conoce se muestra genérica sin romper nada", C.paresDeDatos(filaRara.datos, [ficticio]).at(-1).generica === true);

// ---------- Filtros ----------
const hoy = "2026-11-12";
const fi = (o) => ({ ...FI.FILTROS_INICIALES, ...o });
ok("por omisión: últimos 30 días y ocultos excluidos", igual(FI.aFiltrosServidor(fi({}), hoy), { ocultos: "no", desde: "2014-10-14".replace("2014-10-14", "2026-10-14"), hasta: hoy }));
ok("los filtros del servidor: tipo, grupo, estado, fechas, riesgo, ocultos, resultado", igual(FI.aFiltrosServidor(fi({ tipo: "t", grupo: "g", estado: "e", periodo: "rango", desde: "2026-11-01", hasta: "2026-11-05", riesgo: "si", ocultos: "todos", resultado: "efectivo" }), hoy), { ocultos: "todos", tipo: "t", grupo: "g", estado: "e", desde: "2026-11-01", hasta: "2026-11-05", riesgo_inmediato: true, resultado: "efectivo" }));
ok("la zona y la búsqueda NO van al servidor", !("zona" in FI.aFiltrosServidor(fi({ zona: "fuera", busqueda: "x" }), hoy)) && !("busqueda" in FI.aFiltrosServidor(fi({ zona: "fuera", busqueda: "x" }), hoy)));
ok("periodos: hoy, 7 días, mes en curso, todo", igual(FI.rangoDelPeriodo("hoy", hoy), { desde: hoy, hasta: hoy }) && FI.rangoDelPeriodo("7d", hoy).desde === "2026-11-06" && FI.rangoDelPeriodo("mes", hoy).desde === "2026-11-01" && igual(FI.rangoDelPeriodo("todo", hoy), {}));
ok("rango invertido es inválido", FI.rangoInvalido(fi({ periodo: "rango", desde: "2026-11-05", hasta: "2026-11-01" })) && !FI.rangoInvalido(fi({})));
ok("zona dentro/fuera en el navegador", FI.pasaFiltroCliente(fila({ fuera_de_zona: true }), { zona: "fuera", busqueda: "" }) && !FI.pasaFiltroCliente(fila({ fuera_de_zona: true }), { zona: "dentro", busqueda: "" }) && FI.pasaFiltroCliente(fila(), { zona: "todas", busqueda: "" }));
ok("búsqueda en descripción, contrato y consecutivo, sin tildes ni mayúsculas", FI.pasaFiltroCliente(fila({ descripcion: "Fuga en la Esquina" }), { zona: "todas", busqueda: "ESQUINA" }) && FI.pasaFiltroCliente(fila(), { zona: "todas", busqueda: "1234" }) && FI.pasaFiltroCliente(fila({ consecutivo: "SUS-000123" }), { zona: "todas", busqueda: "sus-0001" }) && !FI.pasaFiltroCliente(fila(), { zona: "todas", busqueda: "zzz" }));
const dd = { grupos: [{ codigo: "g", nombre: "Grupo G", tipos: [{ codigo: "t", nombre: "Tipo T" }] }], estados: [{ codigo: "e", nombre: "Estado E" }] };
const leg = FI.filtrosLegibles(fi({ tipo: "t", estado: "e", riesgo: "si", zona: "fuera", busqueda: "fuga" }), dd, hoy);
ok("filtros activos legibles en español", leg.includes("Tipo: Tipo T") && leg.includes("Estado: Estado E") && leg.includes("Riesgo inmediato: sí") && leg.some((x) => x.startsWith("Fecha de registro (hora de Bogotá): desde el 14/10/2026 hasta el 12/11/2026")) && leg.includes("Ocultos: excluidos") && leg.includes("Zona: fuera de la zona") && leg.includes("Texto: «fuga»"));
ok("la descarga avisa lo que no aplica (zona y texto)", igual(FI.filtrosSoloPantalla(fi({ zona: "fuera", busqueda: "x" })), ["zona", "búsqueda de texto"]) && igual(FI.filtrosSoloPantalla(fi({})), []));

// ---------- CSV ----------
ok("BOM y separador «;»", A.BOM === "﻿" && A.cabeceraCsv(base.filter((c) => ["tipo", "estado"].includes(c.clave)), false) === "Tipo;Estado\r\n");
ok("CSV neutraliza fórmulas (=, +, -, @)", A.textoCsv("=SUMA(A1)") === "'=SUMA(A1)" && A.textoCsv("+57") === "'+57" && A.textoCsv("@x") === "'@x" && A.textoCsv("-1") === "'-1");
ok("CSV pone comillas con «;», comillas o saltos de línea y duplica las comillas", A.textoCsv('a;b') === '"a;b"' && A.textoCsv('di "x"') === '"di ""x"""' && A.textoCsv("a\nb") === '"a\nb"' && A.textoCsv(null) === "");
const colsCsv = C.columnasDescarga(base, [], { conTipo: false, incluirAutor: false });
const filaC = A.filaCsv(fila({ descripcion: "Fuga; grande", datos: { a: 1 } }), colsCsv, ctx, true).trimEnd().split(";");
ok("fila CSV: cantidad de columnas = encabezados + JSON, y descripción con «;» entre comillas", A.cabeceraCsv(colsCsv, true).trimEnd().split(";").length === colsCsv.length + 1 && A.filaCsv(fila({ descripcion: "Fuga; grande" }), colsCsv, ctx, true).includes('"Fuga; grande"') && filaC.at(-1) === '"{""a"":1}"');
ok("coordenadas y precisión con coma decimal en el CSV", A.filaCsv(fila(), colsCsv, ctx, false).includes("10,46") && A.filaCsv(fila(), colsCsv, ctx, false).includes("-73,25") && !A.filaCsv(fila(), colsCsv, ctx, false).includes("10.46"));
ok("sin el correo del autor salvo que se pida (columna autor)", !colsCsv.some((c) => c.clave === "autor") && C.columnasDescarga(base, [], { conTipo: false, incluirAutor: true }).some((c) => c.clave === "autor"));
ok("ninguna fila CSV contiene rutas ni URLs", !/reportes\/20|https?:/.test(A.filaCsv(fila(), colsCsv, ctx, true)));
ok("nombre de archivo sin datos personales", A.nombreArchivo("24/10/2026 10:44", "xlsx") === "reportes_campo_20261024_1044.xlsx" && A.nombreArchivo("raro", "csv") === "reportes_campo.csv");
const usados = new Set();
ok("nombres de hoja: máx. 31, sin []:*?/\\ y únicos", A.nombreHoja("Reconexión [1]: a/b?", usados) === "Reconexión 1 a b" && A.nombreHoja("Reconexión [1]: a/b?", usados) === "Reconexión 1 a b (2)" && A.nombreHoja("x".repeat(50), new Set()).length === 31 && A.nombreHoja("", new Set()) === "Reportes");
const filaD = { seq: 5, id: "i", registrado_local: "2026-11-01T00:00:00", tipo_codigo: "t", tipo_nombre: "Tipo", grupo_nombre: "Grupo", subtipo_nombre: null, consecutivo: "SUS-000001", resultado: "efectivo", causal_nombre: null, estado: "reportado", estado_nombre: "Reportado", oculto: true,
  riesgo_inmediato: false, fuera_de_zona: false, contrato: "1", contrato_verificado: true, descripcion: "d", lat: 1, lon: 2, precision_m: null, origen: "campo", n_fotos: 1, grupo_duplicados: null, tamano_grupo: null, reporte_original_id: null, orden_trabajo_id: null, datos: { a: 1 } };
const adaptada = A.filaDeDescarga(filaD);
ok("la fila de descarga se adapta al registro común (fecha local de Bogotá, oculto marcado, sin autor)", base.find((c) => c.clave === "registrado_en").texto(adaptada, ctx) === "01/11/2026 00:00" && base.find((c) => c.clave === "oculto").texto(adaptada, ctx) === "Sí" && !("autor" in adaptada) && adaptada.consecutivo === "SUS-000001");
const leame = A.hojaLeame({ generadoPor: "s@x.co", generadoEn: "12/11/2026 10:00", filas: 12345, formato: "xlsx", filtros: ["Tipo: T"], incluyeAutor: false, soloPantalla: ["zona"], hojasPorTipo: true });
ok("hoja Léame: filas con punto de miles, filtros, corte, ocultos, lo no aplicado y privacidad", leame.some((r) => r[0] === "Filas (un reporte por fila)" && r[1] === "12.345") && leame.some((r) => r[0] === "Filtros aplicados" && r[1] === "Tipo: T") && leame.some((r) => r[0] === "Corte") && leame.some((r) => r[0] === "No aplicado" && r[1].includes("zona")) && leame.some((r) => r[0] === "Autor" && r[1].includes("No incluye")) && leame.some((r) => r[0] === "Privacidad"));
ok("Excel: el tope por hoja es 1.048.575 filas de datos", A.MAX_FILAS_EXCEL === 1048575);

// ---------- Excel con varias hojas ----------
const libro = new X.LibroMulti(leame);
const h1 = libro.hoja("a", "Hoja A", ["Col 1", "Col 2", "Fecha"], [10, 10, 18]); const h2 = libro.hoja("b", "Hoja B", ["X"], [10]);
await h1.agregarFilas([["uno", 2, { fechaHora: 46327.5 }], ["a&b <c>", 3.5, null]]); await h2.agregarFilas([["solo"]]);
const blob = await libro.finalizar(); const arch = join(out, "prueba.xlsx"); writeFileSync(arch, Buffer.from(await blob.arrayBuffer()));
const py = spawnSync("python3", ["-I", "-c", "import zipfile,sys,json;z=zipfile.ZipFile(sys.argv[1]);print(json.dumps([str(z.testzip()),'|'.join(sorted(z.namelist())),z.read('xl/workbook.xml').decode(),z.read('xl/worksheets/sheet1.xml').decode(),z.read('xl/worksheets/sheet3.xml').decode()[:400]]))", arch], { encoding: "utf8" });
const [rzip, nombres, wb, s1, s3] = JSON.parse(py.stdout || "[\"\",\"\",\"\",\"\",\"\"]");
ok("Excel: el zip es íntegro (CRC) y trae 2 hojas de datos + Léame + estilos + tipos", rzip === "None" && nombres.split("|").length === 8 && nombres.includes("xl/worksheets/sheet3.xml"), py.stderr.slice(0, 200));
ok("Excel: las hojas se llaman Hoja A, Hoja B y Léame", wb.includes('name="Hoja A"') && wb.includes('name="Hoja B"') && wb.includes('name="Léame"'));
ok("Excel: celdas numéricas y de fecha reales, texto escapado, encabezado en negrita", s1.includes("<c r=\"B2\"><v>2</v></c>") && s1.includes('s="4"><v>46327.5</v>') && s1.includes("a&amp;b &lt;c&gt;") && s1.includes('s="1"') && s1.includes('<autoFilter ref="A1:C3"/>'));
ok("Excel: la hoja Léame es de texto", s3.includes("Reportes de campo"));

// ---------- Medición de memoria del Excel (opcional) ----------
if (process.argv.includes("--medir")) {
  for (const n of [50000, 100000, 200000]) {
    global.gc?.(); const m0 = process.memoryUsage().heapUsed; let pico = m0; const t0 = Date.now();
    const l = new X.LibroMulti([["x", "y"]]); const h = l.hoja("a", "Reportes", Array.from({ length: 24 }, (_, i) => `Col ${i}`), Array(24).fill(14));
    for (let i = 0; i < n; i += 5000) {
      const filas = Array.from({ length: Math.min(5000, n - i) }, (_, k) => Array.from({ length: 24 }, (_, c) => (c % 3 === 0 ? i + k : c % 3 === 1 ? "Texto de ejemplo para la fila " + (i + k) : { fechaHora: 46327.5 + k / 1000 })));
      await h.agregarFilas(filas); pico = Math.max(pico, process.memoryUsage().heapUsed);
    }
    const b = await l.finalizar(); const fin = process.memoryUsage();
    console.log(`MEDICIÓN Excel ${n.toLocaleString("es-CO")} filas × 24 columnas: ${(Date.now() - t0) / 1000} s · archivo ${(b.size / 1048576).toFixed(1)} MB · pico del montón ≈ ${((pico - m0) / 1048576).toFixed(0)} MB · RSS final ${(fin.rss / 1048576).toFixed(0)} MB (Node, no navegador)`);
  }
}
console.warn = cw;
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
