// Personal de campo «solo operarios» (22-nov): pruebas de las funciones puras de src/campo/dashboard/personalPuede.ts (sin base, sin navegador).
// Uso: node scripts/prueba_personal_puede.mjs      (-h | --help: este uso; cualquier otra opción o argumento es un error)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const USO = "Uso: node scripts/prueba_personal_puede.mjs";
const a = process.argv.slice(2);
if (a.includes("-h") || a.includes("--help")) { console.log(USO); process.exit(0); }
if (a.length) { console.error(`${a[0].startsWith("-") ? "Opción desconocida" : "Argumento de más"}: ${a[0]}\n${USO}`); process.exit(2); }
const ts = createRequire(import.meta.url)("typescript");
const fuente = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../src/campo/dashboard/personalPuede.ts"), "utf8");
const js = ts.transpileModule(fuente, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const P = await import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + d}`); };
const igual = (n, x, y) => ok(n, JSON.stringify(x) === JSON.stringify(y), `${JSON.stringify(x)} ≠ ${JSON.stringify(y)}`);
const TODO = { cargo: true, area: true, cuadrilla: true, cuadrillas: true, actividades: true, formularios: true, catalogos: false };
const SUP = { ...TODO };                                     // lo que el servidor del 22-nov da al supervisor de campo (v_sup) — catalogos solo el administrador
const ADMIN = { ...TODO, catalogos: true };
const persona = (email, perfil, extra = {}) => ({ email, nombre: null, perfil, permisos: { campo: true, dashboard_campo: perfil === "supervisor", acta: false, dashboard_acta: false },
  cargo: null, formularios: [], sin_asignacion: true, ultimo_cambio: null, area: null, cuadrilla: null, actividades: [], ...extra });
const op = persona("op@x", "operario", { puede_area_cargo: true, puede_asignar: true });
const sup = persona("sup@x", "supervisor", { puede_area_cargo: false, puede_asignar: false });
const yo = persona("yo@x", "supervisor", { propia: true, puede_area_cargo: false, puede_asignar: false });
const resp = (puede_editar, puede, personas) => ({ puede_editar, formularios: [], personas, ...(puede ? { puede } : {}) });

// 1. puedeDe (sin cambio de comportamiento)
igual("puedeDe sin datos = nada", P.puedeDe(null), P.NADA);
igual("puedeDe soloLectura = nada aunque el servidor dé todo", P.puedeDe(resp(true, ADMIN, []), true), P.NADA);
igual("servidor anterior al 21-nov, administrador: cargo y formularios", P.puedeDe(resp(true, null, [])), { ...P.NADA, cargo: true, formularios: true });
igual("servidor anterior al 21-nov, supervisor: nada", P.puedeDe(resp(false, null, [])), P.NADA);
igual("servidor nuevo: lo que diga `puede`", P.puedeDe(resp(false, SUP, [])), SUP);

// 2. puedeSobre: supervisor sobre operario sí; sobre supervisor o sí mismo, no
igual("supervisor sobre operario: área, cargo, cuadrilla, actividades y formularios", P.puedeSobre(SUP, op), SUP);
igual("supervisor sobre otro supervisor: nada de la ficha", P.puedeSobre(SUP, sup), { ...P.NADA, cuadrillas: true });
ok("supervisor sobre otro supervisor: editaAlgo = falso", !P.editaAlgo(P.puedeSobre(SUP, sup)));
igual("supervisor sobre sí mismo: nada de la ficha (conserva cuadrillas)", P.puedeSobre(SUP, yo), { ...P.NADA, cuadrillas: true });
igual("administrador sobre un supervisor (el servidor dice sí): todo", P.puedeSobre(ADMIN, { ...sup, puede_area_cargo: true, puede_asignar: true }), ADMIN);
// los dos campos por separado (hoy valen lo mismo, pero la pantalla no lo supone)
igual("solo puede_area_cargo: área y cargo, sin asignaciones", P.puedeSobre(SUP, { ...op, puede_asignar: false }), { ...SUP, cuadrilla: false, actividades: false, formularios: false });
igual("solo puede_asignar: asignaciones, sin área ni cargo", P.puedeSobre(SUP, { ...op, puede_area_cargo: false }), { ...SUP, cargo: false, area: false });
// servidor del 21-nov (sin los campos por persona): como antes
igual("servidor 21-nov (sin campos por persona): un supervisor se edita como antes", P.puedeSobre(SUP, persona("s2@x", "supervisor")), SUP);
igual("servidor 21-nov: la propia ficha sigue cerrada", P.puedeSobre(SUP, persona("s3@x", "supervisor", { propia: true })), { ...P.NADA, cuadrillas: true });
igual("un `puede` sin nada no se agranda con los campos por persona", P.puedeSobre(P.NADA, op), P.NADA);

// 3. porQueNo: el texto en la ficha cuando no hay «Editar»
ok("operario editable: sin texto", P.porQueNo(SUP, op) === null);
ok("otro supervisor: «Es supervisor…»", /^Es supervisor: su área, su cargo y sus asignaciones los cambia el administrador\.$/.test(P.porQueNo(SUP, sup) ?? ""), P.porQueNo(SUP, sup));
ok("la propia: «Es su ficha…»", P.porQueNo(SUP, yo) === "Es su ficha: no la puede cambiar.", P.porQueNo(SUP, yo));
ok("operario que el servidor cierra (otra razón): «Esta ficha la cambia el administrador.»", P.porQueNo(SUP, { ...op, puede_area_cargo: false, puede_asignar: false }) === "Esta ficha la cambia el administrador.");
ok("quien no edita a nadie (solo lectura): sin texto por ficha", P.porQueNo(P.NADA, sup) === null);

// 4. soloOperarios: el aviso en «Usted puede»
ok("supervisor con servidor 22-nov: sí", P.soloOperarios(resp(false, SUP, [op, sup]), SUP));
ok("administrador: no", !P.soloOperarios(resp(true, ADMIN, [op, { ...sup, puede_area_cargo: true, puede_asignar: true }]), ADMIN));
ok("servidor 21-nov (sin campos por persona): no", !P.soloOperarios(resp(false, SUP, [persona("a@x", "operario")]), SUP));
ok("solo lectura: no", !P.soloOperarios(resp(false, SUP, [op]), P.NADA));
ok("sin datos: no", !P.soloOperarios(null, SUP));

// 5. textoRechazo: el 403 al guardar
const GEN = "No tiene permiso para esta acción.";
ok("403 de la Edge, supervisor, área → la regla del área y el cargo",
  P.textoRechazo(403, "permiso", GEN, "fijar_area", false) === "No tiene permiso para este cambio: el área y el cargo de un supervisor o de un administrador los cambia el administrador.");
ok("403, supervisor, cargo → la regla del área y el cargo", /área y el cargo/.test(P.textoRechazo(403, "permiso", GEN, "fijar_cargo", false) ?? ""));
for (const t of ["fijar_cuadrilla", "asignar_actividad", "quitar_actividad", "asignar_formulario", "quitar_formulario"])
  ok(`403, supervisor, ${t} → la regla de las asignaciones`, P.textoRechazo(403, "permiso", GEN, t, false) === "No tiene permiso para este cambio: las asignaciones de un supervisor o de un administrador las hace el administrador.");
ok("403 al administrador → sin la regla de supervisor", P.textoRechazo(403, "permiso", GEN, "fijar_area", true) === "No tiene permiso para este cambio.");
ok("si el servidor algún día manda su texto, va tal cual", P.textoRechazo(403, "permiso", "Las asignaciones de un supervisor las hace el administrador", "asignar_formulario", false) === "Las asignaciones de un supervisor las hace el administrador");
ok("403 «ya no autorizado» → nulo (texto de siempre)", P.textoRechazo(403, "denegado", "Usuario no autorizado en el geoportal.", "fijar_area", false) === null);
ok("403 de horario → nulo (texto de siempre)", P.textoRechazo(403, "horario", "El geoportal está disponible de 6 a 18.", "fijar_area", false) === null);
ok("409 (ya tiene esa área) → nulo", P.textoRechazo(409, "validacion", "Ya tiene esa área", "fijar_area", false) === null);
ok("400 → nulo", P.textoRechazo(400, "validacion", "Esa área no existe", "fijar_area", false) === null);

console.log(`\n${total - fallas} de ${total}${fallas ? ` — ${fallas} FALLA(S)` : " — sin fallas"}`);
process.exit(fallas ? 1 : 0);
