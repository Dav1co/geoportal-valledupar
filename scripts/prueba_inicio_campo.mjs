// Pasada 14/11 · lógica PURA de la hora de inicio en los formularios de campo: src/campo/inicio.ts (reloj de apertura y recálculo tras un rechazo por la hora)
// y src/campo/formatos/logica.ts (prellenado de «Hora de inicio» del papel y orden de las horas; condiciones «Instalación / Cambio de medidor»). Sin red ni navegador.
// Uso: node scripts/prueba_inicio_campo.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (f) => ts.transpileModule(readFileSync(join(aqui, "../src/campo", f), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const urlTipos = "data:text/javascript;base64," + Buffer.from(compilar("formatos/tipos.ts")).toString("base64");
const L = await import("data:text/javascript;base64," + Buffer.from(compilar("formatos/logica.ts").replace(/from\s+["']\.\/tipos["']/, `from "${urlTipos}"`)).toString("base64"));
const I = await import("data:text/javascript;base64," + Buffer.from(compilar("inicio.ts")).toString("base64"));
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };

// ---- Reloj de apertura ----
const t0 = Date.parse("2026-11-14T15:00:00Z");
const r = I.abrirReloj(t0, 1000);
ok("abrirReloj: ISO con zona (Z) del momento de abrir", r.iso === "2026-11-14T15:00:00.000Z" && r.t0 === 1000);
const r2 = I.recalcularReloj(r, Date.parse("2026-11-14T15:10:00Z"), 1000 + 4 * 60000);
ok("recalcular tras corregir la hora: hora del celular ahora − tiempo transcurrido (4 min) desde que se abrió", r2.iso === "2026-11-14T15:06:00.000Z" && r2.t0 === 1000, r2.iso);
ok("recalcular nunca da un inicio posterior a «ahora» aunque el reloj monotónico retroceda", I.recalcularReloj(r, t0, 0).iso === "2026-11-14T15:00:00.000Z");
ok("reconoce el rechazo por hora adelantada (texto exacto de la base)", I.esRechazoPorHora("La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden."));
ok("reconoce el rechazo por formulario de más de 12 h", I.esRechazoPorHora("Este formulario se abrió hace más de 12 horas. Revise la hora de su celular o ábralo de nuevo."));
ok("no confunde otros errores con un rechazo por la hora", !I.esRechazoPorHora("Falta «Hora de inicio»") && !I.esRechazoPorHora(null));

// ---- Hora del papel ----
const camp = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const rev = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", activo: true, campos: [
  camp("inst_modalidad", "Instalación o cambio de medidor", "opcion", { obligatorio: true, opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor" }, { codigo: "cambio", nombre: "Cambio de medidor" }] }),
  camp("hora_inicio", "Hora de inicio", "dia_hora", { obligatorio: true }), camp("hora_final", "Hora final", "dia_hora", { obligatorio: true }),
  camp("me_lectura", "Medidor retirado · Lectura", "decimal", { obligatorio: true, visible_si: { campo: "inst_modalidad", es: "cambio" } }),
  camp("calib_realizada", "Calibración", "si_no", { visible_si: { campo: "inst_modalidad", es: "cambio" } }),
  camp("calib_vol_patron", "Volumen del patrón", "decimal", { visible_si: { campo: "calib_realizada", es: true } }),
], fotos: [], requiere_contrato: "no", genera_resultado: false };
ok("prellenado: «Hora de inicio» nace con la hora de apertura en Bogotá (UTC−5)", JSON.stringify(L.prellenarHoraInicio(rev, "2026-11-14T15:07:59.000Z")) === JSON.stringify({ hora_inicio: "2026-11-14T10:07" }));
ok("prellenado: a medianoche de Bogotá cambia el día correctamente", L.prellenarHoraInicio(rev, "2026-11-15T04:30:00Z").hora_inicio === "2026-11-14T23:30");
ok("prellenado: un formato sin «Hora de inicio» no recibe nada", JSON.stringify(L.prellenarHoraInicio({ ...rev, campos: [camp("x", "X", "texto")] }, "2026-11-14T15:00:00Z")) === "{}");
ok("prellenado: «Hora de inicio» de otro tipo de dato no se toca", JSON.stringify(L.prellenarHoraInicio({ ...rev, campos: [camp("hora_inicio", "Hora", "texto")] }, "2026-11-14T15:00:00Z")) === "{}");
const est = (valores) => ({ resultado: "", causal: "", subtipo: "", descripcion: "", contrato: "", valores, etiquetasConFoto: [], adicionales: 0, topeGeneral: 10 });
const faltas = (v) => L.validarFormato(rev, est(v));
ok("horas en orden: sin aviso", !faltas({ inst_modalidad: "instalacion", hora_inicio: "2026-11-14T10:00", hora_final: "2026-11-14T10:40" }).some((x) => x.includes("hora final")));
ok("hora final anterior a la de inicio: aviso claro", faltas({ inst_modalidad: "instalacion", hora_inicio: "2026-11-14T10:00", hora_final: "2026-11-14T09:40" }).includes("La hora final no puede ser anterior a la hora de inicio."));
// ---- Instalación / Cambio (catálogo nuevo, misma regla de pantalla que la base) ----
ok("«Instalación»: los datos del medidor retirado no se ven ni se exigen", !L.camposVisibles(rev, { inst_modalidad: "instalacion" }).some((c) => c.codigo === "me_lectura")
   && !faltas({ inst_modalidad: "instalacion", hora_inicio: "2026-11-14T10:00", hora_final: "2026-11-14T10:40" }).some((x) => x.includes("retirado")));
ok("«Cambio»: aparecen y se exige la lectura del retirado", L.camposVisibles(rev, { inst_modalidad: "cambio" }).some((c) => c.codigo === "me_lectura")
   && faltas({ inst_modalidad: "cambio", hora_inicio: "2026-11-14T10:00", hora_final: "2026-11-14T10:40" }).includes("Falta «Medidor retirado · Lectura»."));
ok("en cadena: con «Instalación», la calibración y sus hijos se ocultan aunque quede «sí» de antes", !L.camposVisibles(rev, { inst_modalidad: "instalacion", calib_realizada: "si" }).some((c) => c.codigo === "calib_vol_patron"));
ok("sin elegir la opción, se pide (y el medidor retirado no aparece)", faltas({ hora_inicio: "2026-11-14T10:00", hora_final: "2026-11-14T10:40" }).includes("Falta «Instalación o cambio de medidor».")
   && !L.camposVisibles(rev, {}).some((c) => c.codigo === "me_lectura"));
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
