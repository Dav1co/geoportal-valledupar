// Prueba de la lógica PURA de áreas (src/areas/areas.ts): perfil → pantalla inicial, con los perfiles de hoy (que NO deben cambiar) y los casos nuevos de Formatos de campo.
// Sin red ni navegador. Uso: node scripts/prueba_areas.mjs   (usa el paquete typescript del proyecto)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const js = ts.transpileModule(readFileSync(join(aqui, "../src/areas/areas.ts"), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const { areasDisponibles, pantallaInicial, tarjetasEntrada, esDual, pantallaValida } = await import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));

// Permisos tal como los entrega geoportal_mis_permisos (incluye torre_a/torre_b calculadas por el servidor, con la regla nueva donde un permiso de campo abre la Torre A)
const P = (m = {}) => {
  const b = { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, registro_tecnico: false, dashboard_tecnico: false, campo: false, dashboard_campo: false, acta: false, dashboard_acta: false, ...m };
  const comercial = b.explorar || b.focalizacion || b.comercial || b.rutas || b.dashboard;
  return { es_admin: !!m.admin, permisos: { ...b, torre_a: !!m.admin || comercial || b.campo || b.dashboard_campo || b.acta || b.dashboard_acta, torre_b: !!m.admin || b.registro_tecnico || b.dashboard_tecnico } };
};
// Perfil por omisión de geoportal_mis_permisos para un correo fuera de la lista blanca o inactivo: rol consulta, explorar = true, todo lo demás falso, torres falsas.
const POR_OMISION = { es_admin: false, permisos: { rol: "consulta", explorar: true, focalizacion: false, comercial: false, rutas: false, dashboard: false, registro_tecnico: false, dashboard_tecnico: false, campo: false, dashboard_campo: false, torre_a: false, torre_b: false } };
const casos = [
  // [nombre, perfil, pantalla inicial esperada, tarjetas de la ventana de entrada, ¿opción «Formatos de campo» en el selector «Modo de trabajo» de Comercial?]
  ["PERFILES DE HOY (sin campo)", null],
  ["Administrador (sin campo asignado, pero admin lo tiene)", P({ admin: true }), "entrada", "comercial+tecnica+aseo", true],
  ["Solo comercial (Explorar)", P({ explorar: true }), "comercial", "comercial", false],
  ["Comercial con Rutas y Dashboard", P({ explorar: true, rutas: true, dashboard: true }), "comercial", "comercial", false],
  ["Dual (comercial + técnica)", P({ comercial: true, registro_tecnico: true }), "entrada", "comercial+tecnica", false],
  ["Operador técnico (solo técnica)", P({ registro_tecnico: true }), "tecnica", "tecnica", false],
  ["Supervisor técnico (solo técnica)", P({ registro_tecnico: true, dashboard_tecnico: true }), "tecnica", "tecnica", false],
  ["Sin módulos", P({}), "sin_modulos", "", false],
  ["Perfil por omisión (fuera de la lista blanca o inactivo: explorar=true, torre_a=false)", POR_OMISION, "sin_modulos", "", false],
  ["CASOS NUEVOS (con campo)", null],
  ["Solo campo (reporta)", P({ campo: true }), "campo", "campo", false],
  ["Supervisor de reportes de campo, solo campo", P({ dashboard_campo: true }), "campo", "campo", false],
  ["Reporta + supervisor de campo, solo campo", P({ campo: true, dashboard_campo: true }), "campo", "campo", false],
  ["Comercial + campo", P({ explorar: true, campo: true }), "comercial", "comercial", true],
  ["Comercial + técnica + campo", P({ comercial: true, registro_tecnico: true, campo: true }), "entrada", "comercial+tecnica", true],
  ["Técnica + campo (sin comercial)", P({ registro_tecnico: true, campo: true }), "entrada", "tecnica+campo", false],
  ["Técnica supervisora + supervisor de campo", P({ registro_tecnico: true, dashboard_tecnico: true, dashboard_campo: true }), "entrada", "tecnica+campo", false],
  ["CASOS NUEVOS (con acta de inspección)", null],
  ["Solo acta (captura)", P({ acta: true }), "campo", "campo", false],
  ["Solo supervisor de actas (reconocido, sin pantalla propia aún)", P({ dashboard_acta: true }), "campo", "campo", false],
  ["Acta + supervisor de actas, solo acta", P({ acta: true, dashboard_acta: true }), "campo", "campo", false],
  ["Campo + acta", P({ campo: true, acta: true }), "campo", "campo", false],
  ["Comercial + acta (el acta vive en el área de campo, dentro de Comercial)", P({ explorar: true, acta: true }), "comercial", "comercial", true],
  ["Técnica + acta (sin comercial)", P({ registro_tecnico: true, acta: true }), "entrada", "tecnica+campo", false],
  ["Comercial + técnica + acta", P({ comercial: true, registro_tecnico: true, acta: true }), "entrada", "comercial+tecnica", true],
  ["CASOS NUEVOS (análisis de contrato, decisión 12)", null],
  ["Comercial + análisis de contrato (sin campo)", P({ comercial: true, analisis_contrato: true }), "comercial", "comercial", true],
  ["Explorar + análisis de contrato", P({ explorar: true, analisis_contrato: true }), "comercial", "comercial", true],
  ["Solo análisis de contrato (sin comercial ni campo)", P({ analisis_contrato: true }), "campo", "campo", false],
  ["Técnica + análisis de contrato", P({ registro_tecnico: true, analisis_contrato: true }), "entrada", "tecnica+campo", false],
];
let total = 0, fallas = 0;
const filas = [];
for (const [nombre, perfil, esperada, tarjetas, botonCampo] of casos) {
  if (perfil === null) { filas.push(`\n${nombre}`); continue; }
  const a = areasDisponibles(perfil);
  const pant = pantallaInicial(a), tj = tarjetasEntrada(a).join("+"), boton = a.campo && a.comercial;
  const bien = pant === esperada && tj === tarjetas && boton === botonCampo;
  total++; if (!bien) fallas++;
  filas.push(`${bien ? "OK    " : "FALLA "} ${nombre.padEnd(52)} → pantalla «${pant}»; tarjetas [${tj}]; opción «Formatos de campo» en el selector «Modo de trabajo» de Comercial: ${boton ? "sí" : "no"}`);
}
console.log(filas.join("\n"));
// Reglas adicionales
// Compatibilidad: sin torre_a declarada (servidor anterior) se sigue calculando de los modos, como antes.
const sinTorres = { es_admin: false, permisos: { explorar: true, focalizacion: false, comercial: false, rutas: false, dashboard: false } };
const ok = (n, c) => { total++; if (!c) { fallas++; console.log("FALLA  " + n); } };
ok("servidor que no declara torre_a: comercial se calcula de los modos (como antes)", pantallaInicial(areasDisponibles(sinTorres)) === "comercial");
ok("perfil por omisión: ningún área disponible", JSON.stringify(areasDisponibles(POR_OMISION)) === JSON.stringify({ comercial: false, tecnica: false, campo: false, aseo: false }));
ok("sin perfil: nada disponible", JSON.stringify(areasDisponibles(null)) === JSON.stringify({ comercial: false, tecnica: false, campo: false, aseo: false }) && pantallaInicial(areasDisponibles(null)) === "sin_modulos");
ok("solo campo NO tiene comercial aunque el servidor diga torre_a = true", areasDisponibles(P({ campo: true })).comercial === false);
ok("pantalla «comercial» no es válida para quien solo tiene campo (no se monta el mapa)", pantallaValida("comercial", areasDisponibles(P({ campo: true }))) === false);
ok("pantalla «campo» es válida para solo campo y la ventana de entrada no", pantallaValida("campo", areasDisponibles(P({ campo: true }))) && !pantallaValida("entrada", areasDisponibles(P({ campo: true }))));
ok("un comercial al que le quitan campo no queda en pantalla «campo»", pantallaValida("campo", areasDisponibles(P({ explorar: true }))) === false);
ok("esDual: comercial+campo no es dual (campo va en la cabecera), técnica+campo sí", !esDual(areasDisponibles(P({ explorar: true, campo: true }))) && esDual(areasDisponibles(P({ registro_tecnico: true, campo: true }))));
ok("solo acta entra al área de campo y no tiene comercial ni técnica", JSON.stringify(areasDisponibles(P({ acta: true }))) === JSON.stringify({ comercial: false, tecnica: false, campo: true, aseo: false }));
ok("solo dashboard_acta: área de campo reconocida", areasDisponibles(P({ dashboard_acta: true })).campo === true);
ok("sin ningún permiso (ni acta): «Sin módulos asignados»", pantallaInicial(areasDisponibles(P({}))) === "sin_modulos");
ok("acta = false y dashboard_acta = false explícitos no abren campo", areasDisponibles(P({ acta: false, dashboard_acta: false })).campo === false);
ok("el perfil por omisión (acta no declarada) sigue sin áreas", JSON.stringify(areasDisponibles(POR_OMISION)) === JSON.stringify({ comercial: false, tecnica: false, campo: false, aseo: false }));
ok("servidor anterior (sin las claves acta): los perfiles de siempre no cambian", areasDisponibles({ es_admin: false, permisos: { explorar: true, focalizacion: false, comercial: false, rutas: false, dashboard: false, campo: true, dashboard_campo: false } }).campo === true
  && areasDisponibles({ es_admin: false, permisos: { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false } }).campo === false);
ok("pantalla «campo» es válida para solo acta y deja de serlo si le quitan el permiso", pantallaValida("campo", areasDisponibles(P({ acta: true }))) && !pantallaValida("campo", areasDisponibles(P({}))));
ok("el administrador ve las cuatro áreas (comercial, técnica, campo y aseo)", JSON.stringify(areasDisponibles(P({ admin: true }))) === JSON.stringify({ comercial: true, tecnica: true, campo: true, aseo: true }));
// Interventoría de Aseo (Torre C): permisos `aseo` y `dashboard_aseo`, y `torre_c` calculada por el servidor
const PA = (m = {}) => { const x = P(m); return { ...x, permisos: { ...x.permisos, aseo: !!m.aseo || !!m.dashboard_aseo, dashboard_aseo: !!m.dashboard_aseo, torre_c: !!m.admin || !!m.aseo || !!m.dashboard_aseo } }; };
ok("solo aseo (captura) entra directo al área de Aseo: sin comercial, técnica ni campo", JSON.stringify(areasDisponibles(PA({ aseo: true }))) === JSON.stringify({ comercial: false, tecnica: false, campo: false, aseo: true }) && pantallaInicial(areasDisponibles(PA({ aseo: true }))) === "aseo");
ok("solo el supervisor de aseo también entra directo a Aseo", pantallaInicial(areasDisponibles(PA({ dashboard_aseo: true }))) === "aseo" && tarjetasEntrada(areasDisponibles(PA({ dashboard_aseo: true }))).join() === "aseo");
ok("comercial + aseo: ventana de entrada con las dos tarjetas", pantallaInicial(areasDisponibles(PA({ explorar: true, aseo: true }))) === "entrada" && tarjetasEntrada(areasDisponibles(PA({ explorar: true, aseo: true }))).join() === "comercial,aseo");
ok("técnica + aseo: ventana de entrada; campo + aseo: también (campo es tarjeta propia sin comercial)", tarjetasEntrada(areasDisponibles(PA({ registro_tecnico: true, aseo: true }))).join() === "tecnica,aseo" && tarjetasEntrada(areasDisponibles(PA({ campo: true, aseo: true }))).join() === "campo,aseo");
ok("aseo NO abre la Torre A (torre_a falsa) ni la técnica", areasDisponibles(PA({ aseo: true })).comercial === false && areasDisponibles(PA({ aseo: true })).tecnica === false);
ok("sin permiso de aseo, la pantalla «aseo» no es válida; con él sí", !pantallaValida("aseo", areasDisponibles(PA({ campo: true }))) && pantallaValida("aseo", areasDisponibles(PA({ aseo: true }))));
ok("servidor anterior (sin las claves de aseo): nadie ve Aseo salvo el administrador", areasDisponibles(P({ explorar: true })).aseo === false && areasDisponibles(P({ admin: true })).aseo === true);
ok("análisis de contrato: comercial sin campo ve el área de campo (con solo esa tarjeta) desde la cabecera de Comercial", areasDisponibles(P({ comercial: true, analisis_contrato: true })).campo === true && areasDisponibles(P({ comercial: true })).campo === false);
ok("análisis de contrato = false explícito no abre campo", areasDisponibles(P({ explorar: true, analisis_contrato: false })).campo === false);
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
