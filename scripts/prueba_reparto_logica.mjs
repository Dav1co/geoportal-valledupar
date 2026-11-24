// Prueba de la lógica PURA del Reparto de facturas (src/campo/reparto/logica.ts) y de sus entradas en Formatos de campo (src/campo/entradas.ts). Sin red ni navegador.
// Uso: node scripts/prueba_reparto_logica.mjs   (usa el paquete typescript del proyecto)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
for (const a of process.argv.slice(2)) { if (a === "-h" || a === "--help") { console.log("Uso: node scripts/prueba_reparto_logica.mjs"); process.exit(0); } console.error(`Opción desconocida: ${a}`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (rel) => ts.transpileModule(readFileSync(join(aqui, "..", rel), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const importar = (rel) => import("data:text/javascript;base64," + Buffer.from(compilar(rel)).toString("base64"));
const L = await importar("src/campo/reparto/logica.ts");
const E = await importar("src/campo/entradas.ts");
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } else console.log(`OK     ${n}`); };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// 1. Las casillas: 10 arriba y 10 bajando; el buscador filtra solo dentro de la ruta
const pend = Array.from({ length: 25 }, (_, i) => ({ c: String(100100 + i * 37), s: i < 2 }));
let d = L.dividir(pend, "");
ok("1.1 sin búsqueda: los 10 siguientes arriba, otros 10 bajando (20 a la mano)", d.arriba.length === 10 && d.abajo.length === 10 && d.arriba[0].c === "100100" && d.abajo[0].c === pend[10].c && d.encontrados === 25);
d = L.dividir(pend, "1002");
ok("1.2 el buscador filtra por parte del código, solo dentro de la ruta", d.encontrados === pend.filter((p) => p.c.includes("1002")).length && d.arriba.every((p) => p.c.includes("1002")), JSON.stringify(d));
ok("1.3 el buscador ignora lo que no es número", L.dividir(pend, "10 01-00").encontrados === pend.filter((p) => p.c.includes("100100")).length);
ok("1.4 los saltados conservan su marca", L.dividir(pend, "").arriba.slice(0, 2).every((p) => p.s));
ok("1.5 sin ruta: el código vale solo con 1 a 12 dígitos", L.codigoValido(" 1234 ") === "1234" && L.codigoValido("12a") === null && L.codigoValido("1234567890123") === null && L.codigoValido("") === null);

// 2. Entregar: sale el código y sube el siguiente; «Entregadas N de T»
const lista = { jornada: { id: 1, total: 25, origen: "anterior" }, entregadas_mias: 0, siguiente: 1, pendientes: pend, ultimas: [] };
const l2 = L.sinEntregada(lista, "100100");
ok("2.1 la entregada sale y sube la siguiente; el consecutivo siguiente aumenta", l2.pendientes.length === 24 && L.dividir(l2.pendientes, "").arriba[0].c === pend[1].c && l2.siguiente === 2 && l2.entregadas_mias === 1);
ok("2.2 «Entregadas N de T» cuenta lo que ya no está pendiente (de quien sea)", L.entregadasDeRuta(l2) === 1 && L.entregadasDeRuta({ ...l2, pendientes: l2.pendientes.slice(5) }) === 6);

// 3. Escoger la ruta: primero el ciclo, luego la ruta; los archivos nuevos primero
const ctx = { periodo: "202610",
  anterior: [{ ciclo: "10", rutas: [{ ruta: "101008", n: 614 }], reparto: { periodo: "202611", desde: "2026-11-05" } }, { ciclo: "2", rutas: [{ ruta: "20101", n: 300 }, { ruta: "20102", n: 10 }], reparto: null }],
  nuevas: [{ id: "u1", nombre_archivo: "r.xlsx", ciclo: "2", ruta: "ZT", filas: 5, cargado_en: "", reparto: null }, { id: "u2", nombre_archivo: "c.xlsx", ciclo: "30", ruta: "300101", filas: 9, cargado_en: "", reparto: { periodo: "202611", desde: "2026-11-02" } },
           { id: "u2", nombre_archivo: "c.xlsx", ciclo: "30", ruta: "300102", filas: 4, cargado_en: "", reparto: { periodo: "202611", desde: "2026-11-02" } }] };
const cs = L.ciclosParaEscoger(ctx);
ok("3.1 ciclos ordenados por número (2, 10, 30), con el ciclo que solo tiene archivo", igual(cs.map((c) => c.ciclo), ["2", "10", "30"]));
ok("3.2 en un ciclo, cada ruta del archivo nuevo va primero (en su orden) y luego las rutas de lectura", igual(cs[0].opciones.map((o) => o.clave), ["n:u1:2:ZT", "a:2:20101", "a:2:20102"]) && cs[0].opciones[0].titulo === "Ruta ZT (archivo nuevo)"
   && igual(cs[2].opciones.map((o) => o.clave), ["n:u2:30:300101", "n:u2:30:300102"]) && cs[2].opciones[1].ruta === "300102", JSON.stringify(cs[2].opciones));
ok("3.3 cada ciclo trae su período de reparto (o nulo: sin fecha)", cs[0].reparto === null && cs[1].reparto.periodo === "202611" && cs[2].reparto.desde === "2026-11-02");
ok("3.4 textos de período y fecha", L.textoPeriodo("202611") === "noviembre de 2026" && L.textoFecha("2026-11-05") === "05/11/2026" && L.textoPeriodo(null) === "—");

// 4. Sin señal: la lista y el toque pendiente sobreviven en la sesión
const mem = new Map(); const A = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, v), removeItem: (k) => mem.delete(k) };
L.guardarLista(A, l2); L.guardarToque(A, { jornada_id: 1, contrato: "100137", id_cliente: "abc", por_buscador: false, lon: -73.25, lat: 10.47, precision_m: 6 });
ok("4.1 la lista y el toque (con su MISMO uuid) se leen igual tras recargar", igual(L.leerLista(A), l2) && L.leerToque(A).id_cliente === "abc");
L.guardarToque(A, null); L.guardarLista(A, null);
ok("4.2 al confirmarse se borran", L.leerToque(A) === null && L.leerLista(A) === null);
mem.set("reparto.lista", "{roto"); ok("4.3 una lista dañada no rompe la pantalla", L.leerLista(A) === null);

// 5. Archivo de rutas: la estructura del archivo de facturación (encabezados exactos; la DIRECCIÓN se exige pero no viaja)
const ENC = ["CÓDIGO_DEL_CONTRATO", "CICLO", "DIRECCIÓN", "RUTA", "CONSECUTIVO_EN_LA_RUTA", "NÚMERO_CONSECUTIVO_DE_PREDIO"];
let r = L.procesarArchivoRuta([ENC, ["1001", "98", "CALLE 1", "131013", "2000000", "5"], ["1.002E+3", "098", "CALLE 2", "131013", "1000000.0", ""], ["", "", "", "", "", ""]], 10);
ok("5.1 la plantilla de facturación: cada fila con su ciclo y su ruta, consecutivos enteros, SIN la dirección", r.errores.length === 0
   && igual(r.filas, [{ contrato: "1001", ciclo: "98", ruta: "131013", consecutivo_ruta: "2000000", consecutivo_predio: "5" }, { contrato: "1002", ciclo: "98", ruta: "131013", consecutivo_ruta: "1000000" }])
   && !JSON.stringify(r.filas).includes("CALLE"), JSON.stringify(r));
r = L.procesarArchivoRuta([ENC, ["1001", "98", "x", "R", "1", ""], ["1002", "98", "x", "R", "2", ""], ["1001", "97", "x", "S", "3", ""]], 10);
ok("5.2 contratos repetidos: el error con la lista (y sus filas)", r.errores[0] === "El archivo trae contratos repetidos: cada contrato va una sola vez." && r.errores[1] === "El contrato 1001 está repetido (filas 2, 4).", JSON.stringify(r.errores));
ok("5.3 falta la DIRECCIÓN o sobra una columna: se rechaza con el detalle",
   /Faltan las columnas DIRECCIÓN/.test(L.procesarArchivoRuta([ENC.filter((e) => e !== "DIRECCIÓN"), ["1", "98", "R", "1", ""]], 10).errores[0])
   && /sobran las columnas NOMBRE/.test(L.procesarArchivoRuta([[...ENC, "NOMBRE"], ["1", "98", "x", "R", "1", "", "y"]], 10).errores[0]));
ok("5.4 sin la columna CÓDIGO_DEL_CONTRATO, o vacío", L.procesarArchivoRuta([["Contrato"], ["1"]], 10).errores[0].includes("«CÓDIGO_DEL_CONTRATO»") && L.procesarArchivoRuta([ENC], 10).errores.includes("El archivo no trae contratos debajo del encabezado."));
r = L.procesarArchivoRuta([ENC, ["88A", "C1", "x", "", "y", "z"]], 10);
ok("5.5 errores por fila: contrato, ciclo, ruta y consecutivos", r.errores.length === 5 && r.errores.every((e) => e.startsWith("Fila 2:")), JSON.stringify(r.errores));
ok("5.6 encabezados sin tildes, en otro orden y con filas antes del encabezado; más filas que el tope",
   L.procesarArchivoRuta([["Rutas de noviembre"], ["RUTA", "codigo_del_contrato", "ciclo", "direccion", "consecutivo en la ruta", "numero consecutivo de predio"], ["R1", "7", "5", "x", "9", ""]], 10).filas[0]?.contrato === "7"
   && L.procesarArchivoRuta([ENC, ["1", "1", "x", "R", "1", ""], ["2", "1", "x", "R", "2", ""], ["3", "1", "x", "R", "3", ""]], 2).errores.includes("El archivo trae 3 filas y el tope es 2."));

// 6. Mapa en vivo
const p = (id, an = false) => ({ id, anulada: an });
ok("6.1 unir: los nuevos se agregan, ninguno se repite y las anuladas se tachan", igual(L.unirPuntos([p(1), p(2)], [p(2), p(3)], [1]).map((x) => [x.id, x.anulada]), [[1, true], [2, false], [3, false]]));
ok("6.2 cada 10 s (P2 de David)", L.INTERVALO_MAPA_MS === 10000);

// 7. Entradas de Formatos de campo
const ids = (c) => E.entradasDeCampo(c).map((e) => e.id);
const base = { puedeReportar: true, hayFormatos: true, puedeActa: false };
ok("7.1 sin las actividades, sin entradas de reparto (como antes)", !ids(base).some((i) => i.startsWith("reparto")));
const rep = E.entradasDeCampo({ ...base, puedeRepartir: true }).find((e) => e.id === "reparto");
ok("7.2 el repartidor ve «Reparto de facturas» en el bloque de formatos", !!rep && rep.seccion === 2 && rep.habilitada && !rep.gestion && rep.titulo === "Reparto de facturas");
const sup = E.entradasDeCampo({ ...base, puedeSupervisarReparto: true }).find((e) => e.id === "reparto_supervision");
ok("7.3 el supervisor de reparto la ve como entrada de gestión", !!sup && sup.seccion === 4 && sup.gestion === true && !ids({ ...base, puedeSupervisarReparto: true }).includes("reparto"));
ok("7.4 sin el modo campo no aparecen aunque llegaran las marcas", !ids({ ...base, puedeCampo: false, puedeRepartir: true, puedeSupervisarReparto: true }).some((i) => i.startsWith("reparto")));
ok("7.5 el orden de siempre se conserva (reparto después de los formatos)", igual(ids({ ...base, puedeRepartir: true, puedeActivoCampo: true }), ["reporte_general", "formatos", "activo_campo", "reparto"]));

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? "FALLAS" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
