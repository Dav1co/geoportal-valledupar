// Prueba de la lógica PURA de «Supervisión y dashboard» de Aseo (src/aseo/supervision): descargas (CSV, Excel y Léame), filtros, formato de fechas, datos del acta regenerada y PDF con firmas. Sin red ni navegador.
// Las pantallas se prueban en Chrome real (scripts/prueba_chrome_supervision.mjs). Uso: node scripts/prueba_supervision.mjs
import { createRequire } from "node:module";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const salida = join(mkdtempSync(join(tmpdir(), "sup_front_")), "paquete.mjs");
const dobleSupabase = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "supabase-doble", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `export const FUNCTIONS_URL = "http://sim.local/functions/v1"; export const DOMINIO = "@emdupar.gov.co"; export const supabase = { auth: { getSession: async () => ({ data: { session: null } }), signOut: async () => {} }, storage: {} };` }));
} };
await build({ plugins: [dobleSupabase], stdin: { resolveDir: raiz, loader: "ts", contents: `
  export * as D from "./src/aseo/supervision/descargas.ts"; export * as A from "./src/aseo/supervision/actaSupervision.ts"; export * as C from "./src/aseo/supervision/comun.tsx"; export * as P from "./src/aseo/pdf.ts"; export * as M from "./src/aseo/membrete.ts"; export * as X from "./src/tecnica/xlsx.ts";` },
  bundle: true, platform: "node", format: "esm", outfile: salida, jsx: "automatic", logLevel: "error", loader: { ".css": "empty" },
  banner: { js: 'import { createRequire as __cr } from "node:module"; const require = __cr(import.meta.url);' }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"anon-falsa"', "import.meta.env.VITE_FUNCTIONS_URL": '"http://sim.local/functions/v1"' } });
const { D, A, C, P, M, X } = await import(pathToFileURL(salida).href);
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };

// ---------- Descargas ----------
const crit = [{ codigo: "sst_herramientas", nombre: "¿Cuenta con las herramientas?", tipo_dato: "si_no" }, { codigo: "sst_epp", nombre: "¿Usa los EPP?", tipo_dato: "si_no" }];
const fila = (o = {}) => ({ id: "1", seq: 1, consecutivo: "BAR-000001", registrado_local: "2026-11-13T10:30:15", fecha_servicio: "2026-11-13", actividad_nombre: "Barrido", modalidad_nombre: "Manual", servicio: "12", servicio_nombre: "Barrido Manual", ruta_codigo: "2010011207003",
  turno_nombre: "Día", frecuencia_nombre: "L-D", barrios: "Centro, El Carmen", autor: "aud@emdupar.gov.co", auditor_nombre: "Aud Prueba", auditor_cargo: null, representante_estado: "se_nego", representante_nombre: "Pedro; \"P\"", incidencia: "parcial", causal_nombre: "Clima",
  observaciones: "=SUMA(1;2)", marcas: ["Lejos de la ruta"], nc_tipos: ["sst", "parcial"], nc_estado: "sin_revisar", oculta: false, oculta_motivo: null, n_fotos: 4, lat: 10.47078, lon: -73.24365, sello: "ab".repeat(32), respuestas: { sst_herramientas: "Sí", sst_epp: "No" }, ...o });
const h = D.encabezados(crit), l = D.filaCsv(fila(), crit).trimEnd().split(";");
ok("encabezados: 31 fijas (con Inicio, Duración y Origen del inicio) + una por pregunta del catálogo", h.length === 31 + 2 && h[31] === "¿Cuenta con las herramientas?" && D.anchos(crit).length === h.length);
ok("encabezados: dice «Incidencia» y no «Resultado»", h.includes("Incidencia") && !h.some((x) => /Resultado/.test(x)));
ok("CSV: una celda por encabezado (con «;» dentro de comillas)", D.filaCsv(fila(), crit).trimEnd().match(/("([^"]|"")*"|[^;]*)(;|$)/g).length >= h.length);
ok("CSV: cargo faltante = «Cargo no registrado»; incidencia legible; fórmulas neutralizadas con apóstrofo", D.filaCsv(fila(), crit).includes("Cargo no registrado") && D.filaCsv(fila(), crit).includes(";Parcial;") && D.filaCsv(fila(), crit).includes("\"'=SUMA(1;2)\""));
ok("CSV: coordenadas con coma decimal y sin comillas; fechas dd/mm/aaaa", l.includes("10,47078") && l.includes("-73,24365") && l[2] === "13/11/2026 10:30" && l[5] === "13/11/2026");
ok("CSV: el representante entra solo con estado y nombre, sin imagen, y el nombre con comillas se escapa", D.filaCsv(fila(), crit).includes("Se negó a firmar;\"Pedro; \"\"P\"\"\"") && !/imagen|b64/i.test(D.filaCsv(fila(), crit)));
ok("CSV: tipos de no conformidad y estado en español", D.filaCsv(fila(), crit).includes("\"SST; Parcial\";Sin revisar") && D.filaCsv(fila({ nc_estado: null, nc_tipos: [] }), crit).includes("Sin no conformidades"));
ok("CSV: respuestas por pregunta al final", l.slice(-2).join("|") === "Sí|No" && D.filaCsv(fila({ respuestas: {} }), crit).trimEnd().endsWith(";;"));
ok("CSV: cabecera con BOM aparte y separador «;»", D.BOM === "﻿" && D.cabeceraCsv(crit).startsWith("Consecutivo;Inicio (Bogotá);Fecha y hora de registro (Bogotá);Duración (min);Origen del inicio;Fecha de servicio;"));
const x = D.filaXlsx(fila(), crit, X.serialExcel);
ok("Excel: fecha y hora reales, números y mismo largo que los encabezados", x.length === h.length && x[1] === null && typeof x[2] === "object" && "fechaHora" in x[2] && "fecha" in x[5] && x[h.indexOf("Latitud")] === 10.47078 && x[h.indexOf("Fotos")] === 4 && x[3] === null);
// ---------- Hora de inicio (pasada 14/11) ----------
const fi = fila({ inicio_local: "2026-11-13T10:05:09", inicio_origen: "dispositivo", duracion_min: 25.1 }), li = D.filaCsv(fi, crit).trimEnd().split(";");
ok("CSV con inicio: Inicio, Fin, Duración (número con coma, sin comillas) y Origen «Celular»", li[1] === "13/11/2026 10:05" && li[2] === "13/11/2026 10:30" && li[3] === "25,1" && li[4] === "Celular", li.slice(0, 6));
ok("CSV sin inicio (registro anterior o servidor sin actualizar): las tres celdas vacías", l[1] === "" && l[3] === "" && l[4] === "");
const xi = D.filaXlsx(fi, crit, X.serialExcel);
ok("Excel con inicio: Inicio como fecha y hora real y Duración numérica", typeof xi[1] === "object" && "fechaHora" in xi[1] && xi[1].fechaHora < xi[2].fechaHora && xi[3] === 25.1 && xi[4] === "Celular");
ok("Excel: la duración negativa (reloj hasta 2 min adelantado) se descarga tal cual", D.filaXlsx(fila({ inicio_local: "2026-11-13T10:31:00", inicio_origen: "dispositivo", duracion_min: -0.8 }), crit, X.serialExcel)[3] === -0.8);
ok("duración en pantalla: «1 h 05 min», «12 min», «45 s», vacía sin inicio y 0 s si es negativa", C.fmtDuracion(3900) === "1 h 05 min" && C.fmtDuracion(725) === "12 min" && C.fmtDuracion(45) === "45 s" && C.fmtDuracion(null) === "" && C.fmtDuracion(undefined) === "" && C.fmtDuracion(-30) === "0 s" && C.fmtDuracion(3600) === "1 h 00 min");
ok("inicio en pantalla: hora de Bogotá con «(celular)»; vacío sin inicio", C.fmtInicio("2026-11-13T15:05:00+00:00", "dispositivo") === "13/11/2026 10:05 (celular)" && C.fmtInicio("2026-11-13T15:05:00+00:00", "servidor") === "13/11/2026 10:05" && C.fmtInicio(null, null) === "");
ok("nombre del archivo sin datos personales", D.nombreArchivo("barrido", "13/11/2026 10:44", "xlsx") === "auditorias_barrido_20261113_1044.xlsx" && D.nombreArchivo("corte_cesped", "xx", "csv") === "auditorias_corte_cesped.csv");
const leame = D.hojaLeame({ generadoPor: "sup@emdupar.gov.co", generadoEn: "13/11/2026 10:44", filas: 12345, formato: "csv", actividad: "Barrido", filtros: ["Actividad: Barrido"] });
ok("Léame: filtros, quién y cuándo, filas con puntos, privacidad, barrio actual", leame.some((r) => r[0] === "Filas (una por auditoría)" && r[1] === "12.345") && leame.some((r) => /Privacidad/.test(r[0])) && leame.some((r) => /Barrio/.test(r[0]) && /actual/.test(r[1])) && leame.some((r) => /sin imágenes|No se incluyen imágenes/.test(r[1])) && leame.some((r) => /Inicio, fin y duración/.test(r[0]) && /celular/.test(r[1])));

// ---------- Filtros y fechas ----------
const f0 = C.FILTROS_INICIALES;
ok("filtros: valores por defecto (mes en curso, ocultas fuera, sin filtro de no conformidades)", f0.periodo === "mes" && f0.ocultos === "no" && f0.nc === "todos");
const s = C.aServidor({ ...f0, periodo: "rango", desde: "2026-11-01", hasta: "2026-11-13", actividad: "barrido", turno: "2", barrio: "  Centro ", nc: "pendientes", incidencia: "parcial" });
ok("filtros al servidor: rango, turno como texto, barrio recortado, nc y incidencia", s.desde === "2026-11-01" && s.hasta === "2026-11-13" && s.turno === "2" && s.barrio === "Centro" && s.nc === "pendientes" && s.incidencia === "parcial" && C.aServidor(f0).nc === "");
ok("rango inválido: desde posterior a hasta", C.rangoInvalido({ ...f0, periodo: "rango", desde: "2026-11-13", hasta: "2026-11-01" }) && !C.rangoInvalido(f0));
ok("hora de Bogotá a partir de un instante UTC", C.fmtInstanteBogota("2026-11-13T15:30:00+00:00") === "13/11/2026 10:30" && C.fmtInstanteBogota("2026-11-14T02:05:00+00:00") === "13/11/2026 21:05" && C.fmtInstanteBogota(null) === "");
ok("rótulos: incidencia y tipos", C.ROT_INCIDENCIA.parcial === "Parcial" && C.ROT_TIPO.sst === "SST" && C.ROT_ESTADO.reabierta.includes("sin revisar"));
const def = { actividades: [{ codigo: "barrido", nombre: "Barrido", activa: true, modalidades: [{ codigo: "manual", nombre: "Manual", servicios: [] }] }] };
ok("texto de filtros para el Léame", C.textoFiltros({ ...f0, actividad: "barrido", modalidad: "manual", nc: "pendientes", ocultos: "todos" }, def, [], []).join("\n").match(/Actividad: Barrido[\s\S]*Modalidad: Manual[\s\S]*pendientes de revisión[\s\S]*se incluyen/) !== null);

// ---------- Acta regenerada ----------
const logo = M.LOGO; const jpg = logo.b64;
const datos = { consecutivo: "BAR-000123", registrado_en: "2026-11-13T15:30:15+00:00", fecha_servicio: "2026-11-13", sello: "cd".repeat(32), sigla: "BAR", ruta_codigo: "2010011207003", actividad_nombre: "Barrido", modalidad_nombre: "Manual", servicio: "12", servicio_nombre: "Barrido Manual",
  sectores: "Centro", turno_nombre: "Día", hora_inicio: "06:00", hora_fin: "14:00", frecuencia_nombre: "L-D", km: 3.9, se_realizo: "parcial", causal_nombre: "Clima", observaciones: null, respuestas: [{ pregunta: "¿Usa los EPP?", respuesta: "No" }], lat: 10.47, lon: -73.24, precision_m: 8, lat_inicio: null, lon_inicio: null,
  marcas: { lejos_de_ruta: true, fuera_de_zona: false, fuera_de_horario: false, no_programada_hoy: false, sin_trazado: false }, auditor: { nombre: "Aud Prueba", correo: "aud@emdupar.gov.co", cargo: null, imagen_b64: jpg }, representante: { estado: "sin_representante", nombre: null, imagen_b64: null }, fotos: [] };
const d = A.datosDeActa(datos);
ok("acta regenerada: el MISMO sello, hora de Bogotá y fecha dd/mm/aaaa", d.sello === datos.sello && d.registradoEn === "13/11/2026 10:30 a. m." && d.fechaServicio === "13/11/2026");
ok("acta regenerada: cargo nulo, auditor con imagen, representante sin imagen, marcas y servicio", d.auditor.cargo === null && d.firmas.auditor?.ancho > 0 && d.firmas.representante.imagen === null && d.marcas[0] === "Lejos de la ruta" && d.servicio === "12 · Barrido Manual" && d.seRealizo === "Parcial");
const pdf = P.generarActaPdf({ ...d, fotos: [] }, { logo: { bytes: Uint8Array.from(atob(M.LOGO.b64), (c) => c.charCodeAt(0)), ancho: M.LOGO.ancho, alto: M.LOGO.alto }, banda: { bytes: Uint8Array.from(atob(M.BANDA.b64), (c) => c.charCodeAt(0)), ancho: M.BANDA.ancho, alto: M.BANDA.alto } });
const dir = mkdtempSync(join(tmpdir(), "acta_sup_")); const ruta = join(dir, "a.pdf"); writeFileSync(ruta, pdf);
const py = spawnSync("python3", ["-I", "-c", `import sys; from pypdf import PdfReader; r=PdfReader(sys.argv[1]); t=' '.join(p.extract_text() for p in r.pages); print('OK' if all(s in t for s in ['ACTA DE SUPERVISI','INCIDENCIA','Cargo no registrado','No hab','Firma electr','cdcdcdcd']) and 'Resultado' not in t and 'AUDITOR' not in t.split('INCIDENCIA')[0] else 'FALTA: '+t[:600])`, ruta], { encoding: "utf8" });
if (py.status === 0) ok("PDF regenerado: título «Acta de supervisión», «Incidencia», cargo no registrado, sin representante y texto de la firma electrónica (pypdf)", py.stdout.trim() === "OK", py.stdout + py.stderr); else console.log("(sin python3/pypdf: se omite la lectura independiente)");
if (process.env.GUARDAR_ACTA) writeFileSync(process.env.GUARDAR_ACTA, pdf);
console.log(fallas === 0 ? `RESULTADO: ${total} de ${total} pruebas correctas — SIN FALLAS` : `RESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas} FALLA(S)`);
process.exit(fallas === 0 ? 0 : 1);
