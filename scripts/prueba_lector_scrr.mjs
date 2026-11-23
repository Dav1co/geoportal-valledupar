// Prueba en Node del lector de Excel y de las plantillas del modo «Cartera» (Motor SCRR, corte 2). Sin red y sin datos reales (libros sintéticos).
//   node scripts/prueba_lector_scrr.mjs [-h]
import { build } from "esbuild";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";

if (process.argv.slice(2).some((a) => a === "-h" || a === "--help")) { console.log("Uso: node scripts/prueba_lector_scrr.mjs"); process.exit(0); }
for (const a of process.argv.slice(2)) { console.error(`Opción desconocida: ${a}`); process.exit(2); }
const raiz = join(dirname(fileURLToPath(import.meta.url)), ".."); const tmp = mkdtempSync(join(tmpdir(), "lector_scrr_"));
await build({ entryPoints: [join(raiz, "src/scrr/lector.worker.ts")], bundle: true, format: "esm", platform: "node", outfile: join(tmp, "w.mjs"), logLevel: "error" });
await build({ entryPoints: [join(raiz, "src/scrr/lector.ts")], bundle: true, format: "esm", platform: "node", outfile: join(tmp, "l.mjs"), logLevel: "error" });
const W = await import(pathToFileURL(join(tmp, "w.mjs")).href); const L = await import(pathToFileURL(join(tmp, "l.mjs")).href);
let ok = 0, tot = 0; const fallas = [];
const prueba = (n, c, d = "") => { tot++; if (c) { ok++; console.log("OK   ", n); } else { fallas.push(n); console.log("FALLA", n, d); } };
const gen = (args) => execFileSync(process.execPath, [join(raiz, "scripts/scrr_generar_xlsx.mjs"), ...args], { encoding: "utf8" }).trim();
const leer = async (f, tipo) => { try { return await W.leerArchivo(new Uint8Array(readFileSync(f)), tipo, "99999999", 250000); } catch (e) { return { error: e.message }; } };

// 1. Funciones puras
prueba("1.01 números: $ 1.234,56 · 1,234.56 · (1,234) · 2052143.2 · 1.5E+3 · 1.234.567", L.numeroCanonico("$ 1.234,56") === "1234.56" && L.numeroCanonico("1,234.56") === "1234.56"
  && L.numeroCanonico("(1,234)") === "-1234" && L.numeroCanonico("2052143.2") === "2052143.2" && L.numeroCanonico("1.5E+3") === "1500" && L.numeroCanonico("1.234.567") === "1234567");
prueba("1.02 números no válidos: «abc», «1,2,3», vacío", L.numeroCanonico("abc") === null && L.numeroCanonico("1.2.3") === null && L.numeroCanonico("") === null);
prueba("1.03 fechas: serial de Excel 46348, 22/11/2026, 2026-11-22T08:00", L.fechaCanonica("46348") === "2026-11-22" && L.fechaCanonica("22/11/2026") === "2026-11-22" && L.fechaCanonica("2026-11-22T08:00") === "2026-11-22");
prueba("1.04 fechas no válidas: 31/02/2026 y 1999", L.fechaCanonica("31/02/2026") === null && L.fechaCanonica("01/01/1999") === null);
prueba("1.05 horas: 8:05, 08:05:30, 2:30 p. m., fracción 0.3333", L.horaCanonica("8:05") === "08:05" && L.horaCanonica("08:05:30") === "08:05" && L.horaCanonica("2:30 p. m.") === "14:30" && L.horaCanonica("0.3333") === "08:00");
prueba("1.06 contrato: 123.0, 1.23E+5, 12A", L.contratoCanonico("123.0") === "123" && L.contratoCanonico("1.23E+5") === "123000" && L.contratoCanonico("12A") === null);
prueba("1.07 drástico: SÍ, si, x → SI; vacío, NO → NO; «tal vez» → no válido", L.siNo("SÍ") === "SI" && L.siNo("si") === "SI" && L.siNo("x") === "SI" && L.siNo("") === "NO" && L.siNo("NO") === "NO" && L.siNo("tal vez") === null);
const encP = L.PLANTILLAS.pagos.map((c) => c.encabezado);
prueba("1.08 encabezados exactos de pagos en otro orden y sin tildes: válido", !("error" in L.mapearEncabezados("pagos", ["MONTO", "contrato", "Fecha de Pago"])));
let m = L.mapearEncabezados("pagos", ["Contrato", "Monto"]);
prueba("1.09 falta una columna: «le falta la columna «Fecha de pago»»", m.error?.includes("le falta la columna «Fecha de pago»"), JSON.stringify(m));
m = L.mapearEncabezados("pagos", [...encP, "Banco"]);
prueba("1.10 sobra una columna: «sobra la columna «Banco»»", m.error?.includes("sobra la columna «Banco»"), JSON.stringify(m));
m = L.mapearEncabezados("pagos", [...encP, "Monto"]);
prueba("1.11 columna repetida: «está repetida la columna «Monto»»", m.error?.includes("está repetida la columna «Monto»"), JSON.stringify(m));

// 2. Cartera de 112.000 filas: textos compartidos (como Excel) y textos en línea
const medir = async (f, tipo) => { global.gc?.(); const m0 = process.memoryUsage().rss; let pico = m0; const reloj = setInterval(() => { pico = Math.max(pico, process.memoryUsage().rss); }, 20);
  const t0 = performance.now(); const r = await leer(f, tipo); const ms = performance.now() - t0; clearInterval(reloj); pico = Math.max(pico, process.memoryUsage().rss); return { r, ms, mb: (pico - m0) / 1048576 }; };
const fc = join(tmp, "cartera.xlsx"); console.log("   " + gen(["cartera", "112000", fc]));
let x = await medir(fc, "cartera");
prueba(`2.01 cartera de 112.000 (textos compartidos): 112.000 filas, 0 rechazadas, 56.000 con saldo — ${Math.round(x.ms)} ms, +${x.mb.toFixed(0)} MB en Node`,
  x.r.resumen?.filas === 112000 && x.r.resumen.rechazadas === 0 && x.r.resumen.extra.con_saldo_pendiente === 56000 && x.r.resumen.contratosDistintos === 112000, JSON.stringify(x.r.resumen ?? x.r).slice(0, 400));
prueba("2.02 la fila 1 sale normalizada: contrato, ciclo «03» como viene, pendientes y saldo; sin «facturas vencidas» (la calcula el motor)", (() => { const o = L.filaComoObjeto("cartera", x.r.acumulador.filas[1]); return o.contrato === "930000000002" && o.ciclo === "03" && o.facturas_pendientes === "3" && o.saldo_pendiente === "22000" && o.nombre === "SUSCRIPTOR SINTÉTICO 2" && !("facturas_vencidas" in o); })(),
  JSON.stringify(L.filaComoObjeto("cartera", x.r.acumulador.filas[1])));
const fl = join(tmp, "cartera_linea.xlsx"); console.log("   " + gen(["cartera", "112000", fl, "--en-linea"]));
x = await medir(fl, "cartera");
prueba(`2.03 la misma cartera con textos en línea da lo mismo — ${Math.round(x.ms)} ms, +${x.mb.toFixed(0)} MB`, x.r.resumen?.filas === 112000 && x.r.resumen.extra.con_saldo_pendiente === 56000);
const fd = join(tmp, "cartera_dos.xlsx"); gen(["cartera", "1000", fd, "--dos-hojas"]);
x = await medir(fd, "cartera");
prueba("2.04 una cartera partida en dos hojas se lee completa (1.000 filas, hojas Hoja1 y Hoja2)", x.r.resumen?.filas === 1000 && x.r.resumen.hojas.join(",") === "Hoja1,Hoja2", JSON.stringify(x.r.resumen ?? x.r).slice(0, 300));
const fe = join(tmp, "cartera_extra.xlsx"); gen(["cartera", "100", fe, "--columna-extra"]);
x = await leer(fe, "cartera");
prueba("2.05 con una columna que no es de la plantilla se rechaza el archivo completo con mensaje claro", x.error?.includes("sobra la columna «Columna que sobra»"), x.error);
x = await leer(fc, "pagos");
prueba("2.06 la cartera cargada como «pagos» se rechaza (faltan y sobran columnas)", x.error?.includes("le faltan las columnas «Fecha de pago», «Monto»") && x.error.includes("sobran las columnas") && x.error.includes(" y 13 más."), x.error);
x = await W.leerArchivo(new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, ...new Array(600).fill(0)]), "cartera", "99999999", 250000).catch((e) => ({ error: e.message }));
prueba("2.07 un .xls viejo: «guárdelo como Libro de Excel (.xlsx)»", x.error?.includes("Excel viejo (.xls)"), x.error);
x = await W.leerArchivo(new TextEncoder().encode("Contrato;Monto\n1;2\n"), "pagos", "99999999", 250000).catch((e) => ({ error: e.message }));
prueba("2.08 un CSV o texto no es un .xlsx", x.error?.includes("no es un libro de Excel"), x.error);
x = await W.leerArchivo(new Uint8Array(readFileSync(fc)), "cartera", "99999999", 100000).catch((e) => ({ error: e.message }));
prueba("2.09 más filas que el tope: se detiene con mensaje", x.error?.includes("más de 100.000 filas"), x.error);

prueba("2.10 cifras vacías valen cero (la fila 13 trae «Saldo a favor» vacío) y un texto en una cifra se rechaza",
  (() => { const m = L.mapearEncabezados("cartera", L.PLANTILLAS.cartera.map((c) => c.encabezado)); const base = L.PLANTILLAS.cartera.map(() => "");
    base[0] = "123"; const ok = L.procesarFila("cartera", m, base); const mal = L.procesarFila("cartera", m, base.map((v, i) => (i === L.CLAVES.cartera.indexOf("deuda_total") ? "mil" : v)));
    return ok.error === null && L.filaComoObjeto("cartera", ok.valores).saldo_pendiente === "0" && L.filaComoObjeto("cartera", ok.valores).facturas_pendientes === "0"
      && mal.error === "Cifra con formato no válido (vacío vale cero)"; })()
  && L.filaComoObjeto("cartera", (await leer(fc, "cartera")).acumulador.filas[12]).saldo_a_favor === "0");
prueba("2.11 la plantilla de cartera tiene 20 columnas, sin «Facturas vencidas»", L.PLANTILLAS.cartera.length === 20 && !L.PLANTILLAS.cartera.some((c) => /vencidas/i.test(c.encabezado)));

// 3. Pagos y actividades
const fp = join(tmp, "pagos.xlsx"); gen(["pagos", "5000", fp]);
x = await leer(fp, "pagos");
prueba("3.01 pagos de 5.000 filas: fechas de Excel convertidas, sin rechazos", x.resumen?.filas === 5000 && x.resumen.rechazadas === 0 && /^\d{4}-\d{2}-\d{2}$/.test(String(x.resumen.extra.primera_fecha)), JSON.stringify(x.resumen ?? x).slice(0, 300));
const fa = join(tmp, "act.xlsx"); gen(["actividades", "1000", fa]);
x = await leer(fa, "actividades");
prueba("3.02 actividades: 1.000 filas, 100 cortes drásticos (SÍ solo en Corte), horas 08:00 y 08:24, inefectivas con anomalía",
  x.resumen?.filas === 1000 && x.resumen.rechazadas === 0 && x.resumen.extra.cortes_drasticos === 100 && x.resumen.extra.inefectivas === 250
  && (() => { const o = L.filaComoObjeto("actividades", x.acumulador.filas[0]); return o.hora_inicial === "08:00" && o.hora_final === "08:24" && o.drastico === "SI" && o.actividad === "Corte"; })(),
  JSON.stringify(x.resumen ?? x).slice(0, 400) + " " + JSON.stringify(x.acumulador ? L.filaComoObjeto("actividades", x.acumulador.filas[0]) : null));
const map = L.mapearEncabezados("actividades", L.PLANTILLAS.actividades.map((c) => c.encabezado));
const pf = (o) => L.procesarFila("actividades", map, L.CLAVES.actividades.map((k) => o[k] ?? ""));
prueba("3.03 actividad: drástico en una Suspensión se rechaza", pf({ contrato: "1", actividad: "Suspensión", drastico: "SÍ", estado: "3", fecha: "2026-11-20" }).error === "La marca de drástico solo aplica a Corte");
prueba("3.04 actividad: inefectiva sin anomalía se rechaza; con anomalía 18 también", pf({ contrato: "1", actividad: "Corte", drastico: "NO", estado: "4", fecha: "2026-11-20" }).error === "Inefectiva sin anomalía"
  && pf({ contrato: "1", actividad: "Corte", drastico: "NO", estado: "4", anomalia: "18", fecha: "2026-11-20" }).error === "Anomalía fuera del catálogo (1 a 17)");
prueba("3.05 actividad: «Lectura» no es una actividad del motor", pf({ contrato: "1", actividad: "Lectura", drastico: "NO", estado: "3", fecha: "2026-11-20" }).error === "Actividad no reconocida");

console.log(`\nRESULTADO: ${ok} de ${tot} pruebas correctas — ${fallas.length ? "FALLAS: " + fallas.join(" | ") : "SIN FALLAS"}`);
process.exit(fallas.length ? 1 : 0);
