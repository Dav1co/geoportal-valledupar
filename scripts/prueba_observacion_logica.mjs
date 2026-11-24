// [Code B] Investigación y Análisis (23-nov) · lógica PURA de «Observación sobre este contrato» (src/campo/analisis/observacion.ts) y del contador de fotos con mínimo 0
// (src/campo/formatos/logica.ts). Sin red ni navegador. Datos inventados. Uso: node scripts/prueba_observacion_logica.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
for (const a of process.argv.slice(2)) { if (a === "-h" || a === "--help") { console.log("Uso: node scripts/prueba_observacion_logica.mjs"); process.exit(0); } console.error(`Opción desconocida: ${a}`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (f) => ts.transpileModule(readFileSync(join(aqui, "../src/campo", f), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");
const O = await import(aUrl(compilar("analisis/observacion.ts")));
const urlTipos = aUrl(compilar("formatos/tipos.ts"));
const F = await import(aUrl(compilar("formatos/logica.ts").replace(/from\s+["']\.\/tipos["']/, `from "${urlTipos}"`)));
let n = 0, malas = 0;
const ok = (nombre, c, d = "") => { n++; if (!c) malas++; console.log(`${c ? "OK   " : "FALLA"} ${nombre}${c ? "" : "  → " + d}`); };
const B = (p) => ({ ...O.BORRADOR_VACIO, ...p, contacto: { ...O.CONTACTO_VACIO, ...(p.contacto ?? {}) } });
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

ok("01 las 4 observaciones, en el orden de David", igual(O.OBSERVACIONES.map((o) => o.codigo), ["desocupado", "direccion_errada", "actualizacion_datos", "otra"]));
ok("02 sin elegir no se envía", igual(O.faltasObservacion(O.BORRADOR_VACIO), ["Elija la observación."]));
ok("03 «Desocupado» se envía sin nada más", O.faltasObservacion(B({ tipo: "desocupado" })).length === 0);
ok("04 «Desocupado»: el cuerpo lleva solo contrato y tipo (aunque haya texto escrito antes)", igual(O.cuerpoObservacion("770001", B({ tipo: "desocupado", texto: "x", direccion: "y" })), { contrato: "770001", tipo: "desocupado" }));
ok("05 «Dirección errada» sin dirección se envía", O.faltasObservacion(B({ tipo: "direccion_errada" })).length === 0
  && igual(O.cuerpoObservacion("1", B({ tipo: "direccion_errada", direccion: "   " })), { contrato: "1", tipo: "direccion_errada" }));
ok("06 «Dirección errada»: la dirección va limpia", igual(O.cuerpoObservacion("1", B({ tipo: "direccion_errada", direccion: "  CRA 9   # 12-30 " })), { contrato: "1", tipo: "direccion_errada", direccion: "CRA 9 # 12-30" }));
ok("07 una dirección con un teléfono no se envía", O.faltasObservacion(B({ tipo: "direccion_errada", direccion: "CRA 9 tel 300 123 4567" })).length === 1);
ok("08 una dirección común con números cortos sí (CRA 9 # 12-30 apto 1203)", O.faltasObservacion(B({ tipo: "direccion_errada", direccion: "CRA 9 # 12-30 apto 1203" })).length === 0);
ok("09 «Otra» exige de 3 a 120 caracteres", O.faltasObservacion(B({ tipo: "otra", texto: "ab" })).length === 1 && O.faltasObservacion(B({ tipo: "otra", texto: "x".repeat(121) })).length === 1
  && O.faltasObservacion(B({ tipo: "otra", texto: "perro bravo" })).length === 0);
ok("10 «Otra» con una cédula (6+ dígitos) o un teléfono con separadores no se envía", O.faltasObservacion(B({ tipo: "otra", texto: "cc 1065123" })).length === 1
  && O.faltasObservacion(B({ tipo: "otra", texto: "llamar 300-123-4567" })).length === 1 && O.faltasObservacion(B({ tipo: "otra", texto: "fijo 570.12.34" })).length === 1);
ok("11 «Otra»: el texto va limpio y nada más", igual(O.cuerpoObservacion("1", B({ tipo: "otra", texto: "  perro   bravo ", direccion: "z" })), { contrato: "1", tipo: "otra", texto: "perro bravo" }));
ok("12 «Actualización de datos» sin casillas se envía y no manda contacto", O.faltasObservacion(B({ tipo: "actualizacion_datos" })).length === 0
  && igual(O.cuerpoObservacion("1", B({ tipo: "actualizacion_datos" })), { contrato: "1", tipo: "actualizacion_datos" }));
const C = { nombre: " Ana  María ", cedula: "1065123456", telefono: "(300) 123-4567", correo: " Ana@Ejemplo.COM ", relacion: "arrendatario" };
ok("13 con las 5 casillas: el correo viaja como «correo_contacto», en minúsculas; el teléfono sin separadores", igual(O.cuerpoObservacion("1", B({ tipo: "actualizacion_datos", contacto: C })),
  { contrato: "1", tipo: "actualizacion_datos", contacto: { nombre: "Ana María", cedula: "1065123456", telefono: "3001234567", correo_contacto: "ana@ejemplo.com", relacion: "arrendatario" } }));
ok("14 Q3 teléfono: 7, celular de 10 con 3 y fijo de 10 con 60 sí; 8, 10 con 2 y 10 con 61 no", ["5701234", "3001234567", "6055701234"].every((t) => O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { telefono: t } })).length === 0)
  && ["57012345", "2123456789", "6123456789"].every((t) => O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { telefono: t } })).length === 1));
ok("15 Q3 cédula: 5 y 10 dígitos sí; 4, 11 y con letras no", ["12345", "1065123456"].every((c) => O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { cedula: c } })).length === 0)
  && ["1234", "12345678901", "12a45"].every((c) => O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { cedula: c } })).length === 1));
ok("16 correo y nombre mal escritos no se envían", O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { correo: "ana@ejemplo" } })).length === 1
  && O.faltasObservacion(B({ tipo: "actualizacion_datos", contacto: { nombre: "Ana 2" } })).length === 1);
ok("17 los datos de contacto solo viajan con «Actualización de datos»", !("contacto" in O.cuerpoObservacion("1", B({ tipo: "otra", texto: "abc", contacto: C }))));
ok("18 el aviso de enviada y el de repetida", O.textoEnviada({ repetida: false, derivada_id: 1, tipo: "desocupado", contrato: "1" }) === "Quedó en la lista del supervisor: «Desocupado»."
  && O.textoEnviada({ repetida: true, derivada_id: 1, tipo: "otra", contrato: "1" }).startsWith("Ya se avisó «Otra». No se creó otro aviso")
  && O.textoEnviada({ repetida: false, derivada_id: 1, tipo: "actualizacion_datos", contrato: "1", trae_datos: true }).includes("solo los verá el supervisor"));
ok("18b sección 7: «Ya se avisó el <fecha> (<estado>)», y si escribió algo, que no se guardó",
  O.textoEnviada({ repetida: true, derivada_id: 1, tipo: "desocupado", contrato: "1", ya_avisado_en: "2026-11-03T15:00:00Z", estado: "pendiente" })
    === "Ya se avisó «Desocupado» el 3 de noviembre de 2026 (pendiente). No se creó otro aviso: se anotó que usted lo volvió a ver."
  && O.textoEnviada({ repetida: true, derivada_id: 1, tipo: "actualizacion_datos", contrato: "1", ya_avisado_en: "2026-11-20T15:00:00Z", estado: "atendida_fuera", datos_no_guardados: true })
    === "Ya se avisó «Actualización de datos» el 20 de noviembre de 2026 (cerrado: atendido sin formulario). No se creó otro aviso: se anotó que usted lo volvió a ver. Lo que escribió no se guardó.",
  O.textoEnviada({ repetida: true, derivada_id: 1, tipo: "desocupado", contrato: "1", ya_avisado_en: "2026-11-03T15:00:00Z", estado: "pendiente" }));
ok("18d David 24-nov: «uno pendiente a la vez» (Dirección errada, Actualización de datos, Otra) y la excepción de los datos anulados",
  O.textoEnviada({ repetida: true, regla: "pendiente", derivada_id: 1, tipo: "direccion_errada", contrato: "1", ya_avisado_en: "2026-11-03T15:00:00Z", datos_no_guardados: true })
    === "Ya hay un aviso pendiente «Dirección errada» para este contrato (avisado el 3 de noviembre de 2026). No se creó otro. Lo que escribió no se guardó."
  && O.textoEnviada({ repetida: true, regla: "pendiente", derivada_id: 1, tipo: "actualizacion_datos", contrato: "1", ya_avisado_en: "2026-11-03T15:00:00Z", datos_guardados: true })
    === "Ya hay un aviso pendiente «Actualización de datos» para este contrato (avisado el 3 de noviembre de 2026). Como los datos anteriores fueron anulados, los nuevos se guardaron en ese aviso: solo los verá el supervisor."
  && O.textoEnviada({ repetida: true, regla: "vigencia", derivada_id: 1, tipo: "desocupado", contrato: "1", ya_avisado_en: "2026-11-03T15:00:00Z", estado: "pendiente" }).startsWith("Ya se avisó «Desocupado» el 3 de noviembre"));
ok("18c antigüedad: hoy, hace 1 día, hace 45 días", O.antiguedadTexto(0) === "hoy" && O.antiguedadTexto(1) === "hace 1 día" && O.antiguedadTexto(45) === "hace 45 días" && O.antiguedadTexto(undefined) === "");
ok("19 relación: las 5 de la lista", igual(O.RELACIONES.map((r) => r.codigo), ["propietario", "arrendatario", "familiar", "encargado", "otro"]));
// Investigación de ubicación: mínimo 0 de fotos
const INV = { codigo: "investigacion_ubicacion", fotos_min: 0, fotos_max: 6, genera_resultado: false };
ok("20 la Investigación: mínimo 0 fotos y el contador dice «(opcionales)»", F.minimoFotos(INV, "") === 0 && F.contadorFotos(0, 0, 6) === "0 de 6 (opcionales)");
ok("21 los demás formatos siguen con su mínimo", F.minimoFotos({ fotos_min: 3 }, "") === 3 && F.contadorFotos(1, 3, 6) === "1 de 6 (mínimo 3)" && F.minimoFotos({}, "") === 1);
ok("22 «Observaciones» de la Investigación lleva el aviso de datos personales; la de los demás formatos no cambia",
  F.rotuloObservaciones("investigacion_ubicacion", false) === "Observaciones (no escriba nombres, cédulas ni teléfonos) (opcional)"
  && F.rotuloObservaciones("suspension", false) === "Observaciones (opcional)" && F.rotuloObservaciones("fraude", true) === "Observaciones (obligatorio)");

console.log(`\nRESULTADO: ${n - malas} de ${n} pruebas correctas${malas ? "" : " — SIN FALLAS"}`);
process.exit(malas ? 1 : 0);
