// Análisis de contrato · lógica PURA: src/campo/analisis/logica.ts (teléfonos, periodos y «hace X meses», rótulos de mes, escala y tramos de la gráfica, marcas de la tarjeta,
// Google Maps) y aplicarValoresIniciales de src/campo/formatos/logica.ts (el atajo de submedición abre Instalación de medidor con «Cambio»). Sin red ni navegador. Datos inventados.
// Uso: node scripts/prueba_analisis_logica.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (f) => ts.transpileModule(readFileSync(join(aqui, "../src/campo", f), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");
const L = await import(aUrl(compilar("analisis/logica.ts")));
const urlTipos = aUrl(compilar("formatos/tipos.ts"));
const F = await import(aUrl(compilar("formatos/logica.ts").replace(/from\s+["']\.\/tipos["']/, `from "${urlTipos}"`)));
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- Contrato ----
ok("contrato: solo dígitos, máximo 12", L.limpiarContrato(" 12a3-45 6789012345") === "123456789012" && L.contratoValido("1") && L.contratoValido("123456789012") && !L.contratoValido("1234567890123") && !L.contratoValido("") && !L.contratoValido("12 3"));

// ---- Teléfonos ----
ok("teléfono de 10 dígitos: «300 000 0001»", L.formatoTelefono("3000000001") === "300 000 0001");
ok("teléfono de 7 dígitos: «570 0001»", L.formatoTelefono("5700001") === "570 0001");
ok("teléfono de otra longitud: los dígitos tal cual", L.formatoTelefono("12345") === "12345" && L.formatoTelefono("(605) 570-0001") === "6055700001".replace(/^(\d{3})(\d{3})(\d{4})$/, "$1 $2 $3"));
ok("enlace tel: solo con los dígitos", L.hrefTelefono("300 000 0001") === "tel:3000000001");
ok("teléfonos: máximo 3, celulares de 10 dígitos primero, sin repetidos ni vacíos", igual(L.telefonosVisibles(["5700001", "3000000001", "", "3000000001", "3000000002", "3000000003"]), ["3000000001", "3000000002", "3000000003"]));
ok("teléfonos: el fijo queda después del celular", igual(L.telefonosVisibles(["5700001", "3000000001"]), ["3000000001", "5700001"]) && igual(L.telefonosVisibles(null), []));

// ---- Periodos ----
ok("rótulo de mes: «202605» → «may-2026»; «202612» → «dic-2026»; ilegible → «—»", L.etiquetaMes("202605") === "may-2026" && L.etiquetaMes("202612") === "dic-2026" && L.etiquetaMes("2026") === "—" && L.etiquetaMes("202613") === "—" && L.etiquetaMes(null) === "—");
ok("mes corto del eje: «jun»", L.mesCorto("202606") === "jun");
ok("meses entre periodos, también entre años", L.mesesEntre("202609", "202610") === 1 && L.mesesEntre("202511", "202602") === 3 && L.mesesEntre("202610", "202610") === 0 && L.mesesEntre("x", "202610") === null);
ok("meses entre una fecha AAAA-MM-DD o AAAAMMDD y un periodo", L.mesesEntre("2026-08-15", "202610") === 2 && L.mesesEntre("20260815", "202610") === 2);
ok("«hace X meses»: 1 mes, 2 meses y el mismo periodo", L.haceMeses("202609", "202610") === "hace 1 mes" && L.haceMeses("202608", "202610") === "hace 2 meses" && L.haceMeses("202610", "202610") === "en el último periodo" && L.haceMeses("202611", "202610") === "en el último periodo");
ok("«hace N días»: hoy, 1 día y 57 días", L.haceDias(0) === "hoy" && L.haceDias(1) === "hace 1 día" && L.haceDias(57) === "hace 57 días" && L.haceDias(null) === "");
ok("cortes y fechas: «20261114» → «14/11/2026»; «2026-09-18» → «18/09/2026»", L.fechaCorte("20261114") === "14/11/2026" && L.fechaCorte(null) === "—" && L.fechaCorta("2026-09-18") === "18/09/2026");
ok("un instante con hora se muestra en el día de Bogotá (no UTC): 2026-11-15T03:00Z es el 14/11 en Bogotá", L.fechaCorta("2026-11-15T03:00:00Z") === "14/11/2026" && L.fechaCorta("2026-10-02T15:20:00-05:00") === "02/10/2026");
ok("periodo de hoy en Bogotá: el 1 de diciembre a las 02:00 UTC todavía es noviembre en Bogotá", L.periodoHoyBogota(new Date("2026-12-01T02:00:00Z")) === "202611" && L.periodoHoyBogota(new Date("2026-12-01T06:00:00Z")) === "202612");
ok("periodo de referencia: consumo; si no hay ficha, la cartera; si tampoco, el mes de Bogotá", L.periodoReferencia({ consumo: { periodo_ultimo: "202610" }, cortes: { cartera: "20261114" } }) === "202610"
  && L.periodoReferencia({ consumo: null, cortes: { cartera: "20261114", consumo: null } }) === "202611" && L.periodoReferencia({ consumo: null, cortes: null }, new Date("2026-12-01T02:00:00Z")) === "202611");

// ---- Números ----
ok("pesos con punto de miles: «$ 412.300»", L.pesos(412300) === "$ 412.300" && L.pesos(null) === "—");
ok("m³ con coma decimal: 14,2 · 7 · 7,8", L.m3(14.2) === "14,2" && L.m3(7) === "7" && L.m3(7.8) === "7,8" && L.m3(null) === "—");
ok("años del medidor: «12 años», «1 año», «sin dato»", L.anios(12) === "12 años" && L.anios(1) === "1 año" && L.anios(null) === "sin dato");
ok("tramo de mora en palabras", L.tramoTexto("media") === "mora media" && L.tramoTexto("al_dia") === "al día" && L.tramoTexto(null) === "sin dato");
ok("sin código inicial: «2 Estrato 2» → «Estrato 2»; «1 Residencial» → «Residencial»", L.sinCodigo("2 Estrato 2") === "Estrato 2" && L.sinCodigo("1 Residencial") === "Residencial" && L.sinCodigo(null) === "");
ok("ninguna palabra «tarifa» en la lógica ni en la pantalla", !/tarifa/i.test(readFileSync(join(aqui, "../src/campo/analisis/logica.ts"), "utf8") + readFileSync(join(aqui, "../src/campo/analisis/AnalisisContrato.tsx"), "utf8") + readFileSync(join(aqui, "../src/campo/analisis/GraficaConsumo.tsx"), "utf8")));

// ---- Gráfica ----
const mes = (periodo, m3, extra = {}) => ({ periodo, sin_dato: false, m3, metodo: "lectura", lectura_real: true, causal: "99 LECTURA NORMAL", ...extra });
const CONSUMO = { periodo_ultimo: "202610", maximo: 11, minimo: 5, promedio: 7.8, meses_con_lectura: 4, meses: [
  mes("202605", 7), { periodo: "202606", sin_dato: true, m3: null, metodo: null, lectura_real: false, causal: null }, mes("202607", 9, { metodo: "promedio", lectura_real: false, causal: "21 PREDIO CERRADO" }),
  mes("202608", 11), mes("202609", 5), mes("202610", 6)] };
const PROM = { estrato: { grupo: "Estrato 2", meses: [{ periodo: "202605", media: 8.1, contratos: 20311 }, { periodo: "202606", media: 8.0, contratos: 20000 }, { periodo: "202607", media: 8.3, contratos: 20311 }, { periodo: "202610", media: 8.4, contratos: 20311 }] },
  barrio: { grupo: "BARRIO DE PRUEBA", meses: [{ periodo: "202605", media: 7.4, contratos: 512 }, { periodo: "202608", media: null, contratos: 20 }] }, uso: null };
const filas = L.filasGrafica(CONSUMO, PROM);
ok("gráfica: 6 filas en orden, con rótulos de mes", filas.length === 6 && igual(filas.map((f) => f.etiqueta), ["may-2026", "jun-2026", "jul-2026", "ago-2026", "sep-2026", "oct-2026"]));
ok("gráfica: el mes sin dato (202606) queda vacío, sin m³ ni promedios (no se inventa)", filas[1].sinDato && filas[1].m3 === null && filas[1].estrato === null && filas[1].barrio === null && !filas[1].estimado);
ok("gráfica: el mes estimado se marca como estimado; el de lectura no", filas[2].estimado === true && filas[0].estimado === false);
ok("gráfica: promedios del mismo periodo; null si el grupo no llega a 30 o falta el mes", filas[0].estrato === 8.1 && filas[0].barrio === 7.4 && filas[3].barrio === null && filas[4].estrato === null && filas[0].uso === null);
ok("tabla: método y causal; «estimado (promedio)» y «sin dato»", L.metodoTexto(filas[0]) === "lectura · 99 LECTURA NORMAL" && L.metodoTexto(filas[2]) === "estimado (promedio) · 21 PREDIO CERRADO" && L.metodoTexto(filas[1]) === "sin dato");
ok("gráfica sin consumo (ficha no calculada): sin filas", L.filasGrafica(null, PROM).length === 0);
const e = L.escalaY([7, null, 9, 11, 5, 6, 8.4]);
ok("escala Y: tope redondo que cubre el máximo con aire (11 → 12, pasos de 3) y 5 marcas desde 0", e.max === 12 && e.ticks.length === 5 && e.ticks[0] === 0 && e.ticks[4] === e.max && [1, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8, 10].some((f) => Math.abs(e.ticks[1] / Math.pow(10, Math.floor(Math.log10(e.ticks[1]))) - f) < 1e-9), JSON.stringify(e));
ok("escala Y: sin valores no se divide por cero", L.escalaY([null, null]).max > 0 && L.escalaY([]).max > 0);
ok("escala Y: consumos grandes (230 m³) → tope 300 (pasos de 75); pequeños (0,8 m³) → tope 1,2 (nunca menos de 1 m³)", L.escalaY([230]).max === 300 && L.escalaY([0.8]).max === 1.2, JSON.stringify([L.escalaY([230]), L.escalaY([0.8])]));
ok("líneas: se cortan donde falta el mes", igual(L.tramosLinea([8.1, null, 8.3, 8.2]).map((t) => t.map((p) => p.i)), [[0], [2, 3]]) && L.tramosLinea([null, null]).length === 0);

// ---- Marcas ----
const BASE = { encontrado: true, comodin: false, contrato: "1000001", cupo: { limite: 60, usadas: 1, restantes: 59, sin_limite: false, cobrada: true },
  consumo: CONSUMO, cortes: { cartera: "20261114", consumo: "202610", ficha: "2026-11-14T22:10:00-05:00" }, ficha_disponible: true,
  submedicion: { marca: true, periodo: "202610", consumo: 6, referencia: 14.2, n_nuevos: 1800, estrato: "Estrato 2", anios: 12, motivo: null },
  gestiones: { emd_facturados: [{ codigo: "600", concepto: "600- EMD CORTE DEL SERVICIO", periodo: "202608" }, { codigo: "610", concepto: "610- EMD RECONEXION", periodo: "202609" }], terreno: [],
    pqr: { ultima: { solicitud: "900001", fecha: "2026-09-20", causal: "1021 - COBRO POR CONSUMO", estado: "13 - Registrado", abierta: true }, abiertas: 1, ultimos_12_meses: 2, total: 3 },
    reportes: [], reportes_total: 0, actas: [], pendientes: [{ consecutivo: "RPV-000007", tipo_nombre: "Revisiones generales", fecha: "2026-11-01T08:00:00-05:00", sugiere: "cambio_medidor" }] },
  ubicacion: { predios_total: 2, predios: [{ direccion: "CRA 0 00 00", barrio: "BARRIO DE PRUEBA", lat: 10.4631, lon: -73.2532 }, { direccion: "CL 0 00 00", barrio: "BARRIO DE PRUEBA", lat: null, lon: null }] } };
const mk = L.marcasDe(BASE);
ok("marcas: orden submedición · corte · PQR · predios · revisiones", igual(mk.map((m) => m.clave), ["submedicion", "corte", "pqr", "predios", "pendientes"]), JSON.stringify(mk.map((m) => m.clave)));
ok("marca de submedición con la frase explicativa exacta", mk[0].titulo === "Posible submedición" && mk[0].detalle === "Consumo 6 m³ frente a la referencia 14,2 m³ de los medidores nuevos del estrato 2 (oct-2026); medidor de 12 años.", mk[0].detalle);
ok("marca de corte facturado: «hace 2 meses» contra el último periodo de consumo (no la reconexión)", mk[1].titulo === "Corte facturado hace 2 meses", mk[1].titulo);
ok("marca de PQR abierta con «hace 1 mes»", mk[2].titulo === "PQR abierta (hace 1 mes)", mk[2].titulo);
ok("marca de varios predios", mk[3].titulo === "Este contrato está en 2 predios");
ok("marca de revisiones pendientes que sugieren cambio de medidor", mk[4].titulo === "1 revisión pendiente sugiere cambio de medidor" && /RPV-000007/.test(mk[4].detalle));
ok("sin submedición marcada, sin corte reciente, sin PQR abierta, un predio y sin pendientes: ninguna marca", L.marcasDe({ ...BASE, submedicion: { ...BASE.submedicion, marca: false, motivo: "consumo sobre la referencia" },
  gestiones: { ...BASE.gestiones, emd_facturados: [{ codigo: "600", concepto: "600- EMD CORTE DEL SERVICIO", periodo: "202512" }], pqr: { ...BASE.gestiones.pqr, abiertas: 0 }, pendientes: [] }, ubicacion: { predios_total: 1, predios: [] } }).length === 0);
ok("una suspensión facturada se llama «Suspensión»", L.marcasDe({ ...BASE, submedicion: null, gestiones: { ...BASE.gestiones, emd_facturados: [{ codigo: "605", concepto: "605- EMD SUSPENSION DEL SERVICIO", periodo: "202610" }] } })[0].titulo === "Suspensión facturado en el último periodo");
ok("ficha no calculada (consumo, submedición, pqr y emd en null): no se rompe y cuenta desde la cartera", (() => { const m = L.marcasDe({ ...BASE, ficha_disponible: false, consumo: null, submedicion: null, gestiones: { ...BASE.gestiones, emd_facturados: null, pqr: null, pendientes: [] } }); return igual(m.map((x) => x.clave), ["predios"]); })());

// ---- Ubicación ----
ok("Google Maps con el primer predio con coordenadas", (() => { const p = L.primerPredioConPunto({ ubicacion: { predios_total: 2, predios: [{ lat: null, lon: null }, { lat: 10.4631, lon: -73.2532 }] } }); return !!p && L.urlGoogleMaps(p.lat, p.lon) === "https://www.google.com/maps?q=10.4631,-73.2532"; })());
ok("sin coordenadas: ningún punto", L.primerPredioConPunto({ ubicacion: { predios_total: 1, predios: [{ lat: null, lon: null }] } }) === null && L.primerPredioConPunto({ ubicacion: null }) === null);

// ---- Valores iniciales del formato (atajo de submedición) ----
const camp = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const INST = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", activo: true, fotos: [], campos: [
  camp("inst_modalidad", "Instalación o cambio de medidor", "opcion", { opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor" }, { codigo: "cambio", nombre: "Cambio de medidor" }, { codigo: "viejo", nombre: "Viejo", activo: false }] }),
  camp("hora_inicio", "Hora de inicio", "dia_hora"), camp("calib", "Calibración", "si_no"), camp("lect", "Lectura", "decimal"), camp("apagado", "Apagado", "texto", { activo: false })] };
const base = F.prellenarHoraInicio(INST, "2026-11-14T15:07:00Z");
ok("valores iniciales: «Cambio» queda marcado y la hora de inicio se conserva", igual(F.aplicarValoresIniciales(INST, base, { inst_modalidad: "cambio" }), { hora_inicio: "2026-11-14T10:07", inst_modalidad: "cambio" }));
ok("valores iniciales: sin iniciales no cambia nada", F.aplicarValoresIniciales(INST, base, undefined) === base);
ok("valores iniciales: una opción inexistente o inactiva se ignora", igual(F.aplicarValoresIniciales(INST, {}, { inst_modalidad: "otra" }), {}) && igual(F.aplicarValoresIniciales(INST, {}, { inst_modalidad: "viejo" }), {}));
ok("valores iniciales: campos que el formato no tiene o están inactivos se ignoran", igual(F.aplicarValoresIniciales(INST, {}, { no_existe: "x", apagado: "y" }), {}));
ok("valores iniciales: sí/no y números se convierten al formato del formulario", igual(F.aplicarValoresIniciales(INST, {}, { calib: true, lect: 12.5 }), { calib: "si", lect: "12.5" }));
ok("valores iniciales: solo prellenan; el valor sigue siendo válido para el formato (validación del tipo)", F.validarFormato(INST, { resultado: "", causal: "", subtipo: "", descripcion: "", contrato: "", valores: F.aplicarValoresIniciales(INST, base, { inst_modalidad: "cambio" }), etiquetasConFoto: [], adicionales: 0, topeGeneral: 10 }).every((x) => !x.includes("Instalación o cambio")));

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
