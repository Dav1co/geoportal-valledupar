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
  const b = { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, registro_tecnico: false, dashboard_tecnico: false, campo: false, dashboard_campo: false, ...m };
  const comercial = b.explorar || b.focalizacion || b.comercial || b.rutas || b.dashboard;
  return { es_admin: !!m.admin, permisos: { ...b, torre_a: !!m.admin || comercial || b.campo || b.dashboard_campo, torre_b: !!m.admin || b.registro_tecnico || b.dashboard_tecnico } };
};
// Perfil por omisión de geoportal_mis_permisos para un correo fuera de la lista blanca o inactivo: rol consulta, explorar = true, todo lo demás falso, torres falsas.
const POR_OMISION = { es_admin: false, permisos: { rol: "consulta", explorar: true, focalizacion: false, comercial: false, rutas: false, dashboard: false, registro_tecnico: false, dashboard_tecnico: false, campo: false, dashboard_campo: false, torre_a: false, torre_b: false } };
const casos = [
  // [nombre, perfil, pantalla inicial esperada, tarjetas de la ventana de entrada, ¿modo «Formatos de campo» en la barra de modos de Comercial?]
  ["PERFILES DE HOY (sin campo)", null],
  ["Administrador (sin campo asignado, pero admin lo tiene)", P({ admin: true }), "entrada", "comercial+tecnica", true],
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
];
let total = 0, fallas = 0;
const filas = [];
for (const [nombre, perfil, esperada, tarjetas, botonCampo] of casos) {
  if (perfil === null) { filas.push(`\n${nombre}`); continue; }
  const a = areasDisponibles(perfil);
  const pant = pantallaInicial(a), tj = tarjetasEntrada(a).join("+"), boton = a.campo && a.comercial;
  const bien = pant === esperada && tj === tarjetas && boton === botonCampo;
  total++; if (!bien) fallas++;
  filas.push(`${bien ? "OK    " : "FALLA "} ${nombre.padEnd(52)} → pantalla «${pant}»; tarjetas [${tj}]; modo «Formatos de campo» en la barra de modos de Comercial: ${boton ? "sí" : "no"}`);
}
console.log(filas.join("\n"));
// Reglas adicionales
// Compatibilidad: sin torre_a declarada (servidor anterior) se sigue calculando de los modos, como antes.
const sinTorres = { es_admin: false, permisos: { explorar: true, focalizacion: false, comercial: false, rutas: false, dashboard: false } };
const ok = (n, c) => { total++; if (!c) { fallas++; console.log("FALLA  " + n); } };
ok("servidor que no declara torre_a: comercial se calcula de los modos (como antes)", pantallaInicial(areasDisponibles(sinTorres)) === "comercial");
ok("perfil por omisión: ningún área disponible", JSON.stringify(areasDisponibles(POR_OMISION)) === JSON.stringify({ comercial: false, tecnica: false, campo: false }));
ok("sin perfil: nada disponible", JSON.stringify(areasDisponibles(null)) === JSON.stringify({ comercial: false, tecnica: false, campo: false }) && pantallaInicial(areasDisponibles(null)) === "sin_modulos");
ok("solo campo NO tiene comercial aunque el servidor diga torre_a = true", areasDisponibles(P({ campo: true })).comercial === false);
ok("pantalla «comercial» no es válida para quien solo tiene campo (no se monta el mapa)", pantallaValida("comercial", areasDisponibles(P({ campo: true }))) === false);
ok("pantalla «campo» es válida para solo campo y la ventana de entrada no", pantallaValida("campo", areasDisponibles(P({ campo: true }))) && !pantallaValida("entrada", areasDisponibles(P({ campo: true }))));
ok("un comercial al que le quitan campo no queda en pantalla «campo»", pantallaValida("campo", areasDisponibles(P({ explorar: true }))) === false);
ok("esDual: comercial+campo no es dual (campo va en la cabecera), técnica+campo sí", !esDual(areasDisponibles(P({ explorar: true, campo: true }))) && esDual(areasDisponibles(P({ registro_tecnico: true, campo: true }))));
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
