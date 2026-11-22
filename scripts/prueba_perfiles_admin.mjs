// Administración por geoportal (encargo v2, 22-nov) · lógica PURA de src/components/perfilesAdmin.ts: perfil ↔ casillas, «Personalizado», resumen, envío y verificación.
// Sin red ni navegador. Los usuarios de prueba son los 20 del doble del Code A (doble_admin_permisos_4a.sql, b1ca98db…), con sus casillas tal cual.
// Uso: node scripts/prueba_perfiles_admin.mjs      (-h | --help: este uso; cualquier otra opción es un error)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const a = process.argv.slice(2);
if (a.includes("-h") || a.includes("--help")) { console.log("Uso: node scripts/prueba_perfiles_admin.mjs"); process.exit(0); }
if (a.length) { console.error(`Opción desconocida: ${a[0]}\nUso: node scripts/prueba_perfiles_admin.mjs`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const js = ts.transpileModule(readFileSync(join(aqui, "../src/components/perfilesAdmin.ts"), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const P = await import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (x, y) => JSON.stringify(x) === JSON.stringify(y);

// ---- Los 20 del doble (orden de columnas: explorar focalizacion comercial rutas dashboard campo dashboard_campo acta dashboard_acta analisis_contrato registro_tecnico dashboard_tecnico dashboard_redes aseo dashboard_aseo)
const ORDEN = ["explorar", "focalizacion", "comercial", "rutas", "dashboard", "campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato", "registro_tecnico", "dashboard_tecnico", "dashboard_redes", "aseo", "dashboard_aseo"];
const U = (email, rol, bits, horario = "sin_restriccion", dias = "todos", activo = true) => ({ email: `${email}@emdupar.gov.co`, nombre: null, rol, activo, creado_en: "2026-11-22", horario, dias,
  ...Object.fromEntries(ORDEN.map((c, i) => [`ver_${c}`, bits[i] === "t"])) });
const DOBLE = [
  U("prueba.admin", "admin", "fffffffffffffff"), U("prueba.admin2", "admin", "fffffffffffffff"),
  U("prueba.auditor.aseo", "consulta", "ffffffffffffftf"), U("prueba.caso.mixto", "consulta", "tffff" + "fffff" + "ttf" + "tt"),
  U("prueba.caso.todo", "consulta", "ttttttttttttttt", "extendido"), U("prueba.consulta.explorar", "consulta", "tffffffffffffff"),
  U("prueba.consulta.modos", "consulta", "tttttffffffffff", "laboral", "habiles"), U("prueba.inactivo", "consulta", "tffffffffffffff", "laboral", "habiles", false),
  U("prueba.op.comercial", "consulta", "ffffftftftfffff"), U("prueba.op.tecnico", "consulta", "fffffffffftffff"),
  U("prueba.perso.campo.sin.acta", "consulta", "tffffffffffffff".slice(0, 5) + "tffff" + "fffff"), U("prueba.perso.consulta.analisis", "consulta", "tffff" + "fffft" + "fffff"),
  U("prueba.perso.solo.dashboard.aseo", "consulta", "ffffffffffffff" + "t"), U("prueba.perso.sup.sin.registro", "consulta", "ffffffffff" + "ftf" + "ff"),
  U("prueba.sin.acceso", "consulta", "fffffffffffffff"), U("prueba.sup.aseo", "consulta", "fffffffffffff" + "tt"),
  U("prueba.sup.comercial", "consulta", "fffff" + "ttttt" + "fffff"), U("prueba.sup.distribucion", "consulta", "ffffffffff" + "tft" + "ff"),
  U("prueba.sup.plantas.distribucion", "consulta", "ffffffffff" + "ttt" + "ff"), U("prueba.sup.plantas", "consulta", "ffffffffff" + "ttf" + "ff"),
];
const por = (e) => DOBLE.find((u) => u.email === `${e}@emdupar.gov.co`);
const C = (e) => P.casillasDe(por(e));
const DISP = P.disponibles(DOBLE);
ok("fixture: 20 usuarios, 15 casillas cada uno", DOBLE.length === 20 && DOBLE.every((u) => Object.keys(u).filter((k) => k.startsWith("ver_")).length === 15));
ok("fixture: caso mixto = Explorar + registro y dashboard técnico + aseo y supervisor de aseo (lsilva)", igual(ORDEN.filter((c) => C("prueba.caso.mixto")[c]), ["explorar", "registro_tecnico", "dashboard_tecnico", "aseo", "dashboard_aseo"]), JSON.stringify(ORDEN.filter((c) => C("prueba.caso.mixto")[c])));
ok("disponibles: las 15 casillas (el doble trae todas las columnas)", DISP.size === 15);
ok("disponibles (R11): un servidor sin ver_dashboard_redes no la lista", (() => { const s = P.disponibles(DOBLE.map(({ ver_dashboard_redes, ...r }) => r)); return s.size === 14 && !s.has("dashboard_redes"); })());

// ---- 1. Cada perfil de cada geoportal: las casillas exactas (§0.2, §0.3, §0.4) ----
const encendidas = (c) => ORDEN.filter((x) => c[x]);
const base = P.sinNada();
ok("Comercial · Sin formularios: campo, dashboard_campo, acta, dashboard_acta y análisis en falso", igual(encendidas(P.aplicarFormularios({ ...base, campo: true, acta: true, analisis_contrato: true, explorar: true }, "sin")), ["explorar"]));
ok("Comercial · Operario comercial: campo, acta, análisis (SIN Explorar)", igual(encendidas(P.aplicarFormularios(base, "operario")), ["campo", "acta", "analisis_contrato"]));
ok("Comercial · Supervisor comercial: campo, dashboard_campo, acta, dashboard_acta, análisis (sin modos)", igual(encendidas(P.aplicarFormularios(base, "supervisor")), ["campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato"]));
ok("Comercial · el Operario NO recibe Explorar salvo que el administrador lo marque", !P.aplicarFormularios(base, "operario").explorar && P.aplicarFormularios(P.ponerModo(base, "explorar", true), "operario").explorar);
ok("Comercial · los modos son casillas sueltas: escoger formularios no los toca", igual(MODOS(P.aplicarFormularios({ ...base, rutas: true, dashboard: true }, "supervisor")), ["rutas", "dashboard"]));
function MODOS(c) { return P.MODOS.filter((m) => c[m]); }
ok("Comercial · ponerModo solo acepta los 5 modos", igual(P.ponerModo(base, "campo", true), base) && P.ponerModo(base, "focalizacion", true).focalizacion);
ok("Técnica · Operario técnico: registro_tecnico", igual(encendidas(P.aplicarTecnica(base, "operario")), ["registro_tecnico"]));
ok("Técnica · Supervisor de plantas: registro_tecnico y dashboard_tecnico", igual(encendidas(P.aplicarTecnica(base, "sup_plantas")), ["registro_tecnico", "dashboard_tecnico"]));
ok("Técnica · Supervisor de distribución: registro_tecnico y dashboard_redes", igual(encendidas(P.aplicarTecnica(base, "sup_distribucion")), ["registro_tecnico", "dashboard_redes"]));
ok("Técnica · Supervisor de plantas y distribución: las tres", igual(encendidas(P.aplicarTecnica(base, "sup_ambas")), ["registro_tecnico", "dashboard_tecnico", "dashboard_redes"]));
ok("Técnica · NUNCA un supervisor sin registro_tecnico", Object.values(P.PERFILES_TECNICA).every((p) => p.casillas.length === 0 || p.casillas.includes("registro_tecnico")));
ok("Técnica · Sin acceso apaga las tres", igual(encendidas(P.aplicarTecnica({ ...base, registro_tecnico: true, dashboard_tecnico: true, dashboard_redes: true }, "sin")), []));
ok("Aseo · Auditor: aseo / Supervisor: aseo y dashboard_aseo / Sin acceso: nada", igual(encendidas(P.aplicarAseo(base, "auditor")), ["aseo"]) && igual(encendidas(P.aplicarAseo(base, "supervisor")), ["aseo", "dashboard_aseo"])
  && igual(encendidas(P.aplicarAseo({ ...base, aseo: true, dashboard_aseo: true }, "sin")), []));
ok("escoger un perfil cambia SOLO su grupo (Técnica no toca Comercial ni Aseo, y al revés)", (() => {
  const c = C("prueba.caso.todo");
  const t = P.aplicarTecnica(c, "sin"), s = P.aplicarAseo(c, "sin"), f = P.aplicarFormularios(c, "sin");
  return ORDEN.every((x) => (P.CASILLAS_DE.tecnica.includes(x) ? !t[x] : t[x] === c[x])) && ORDEN.every((x) => (P.CASILLAS_DE.aseo.includes(x) ? !s[x] : s[x] === c[x]))
    && ORDEN.every((x) => (P.FORMULARIOS_COMERCIAL.includes(x) ? !f[x] : f[x] === c[x]));
})());

// ---- 2. Reconocer a los 20 del doble ----
const R = (e) => P.reconocer(C(e));
const esperado = {
  "prueba.consulta.explorar": ["sin", "sin", "sin"], "prueba.consulta.modos": ["sin", "sin", "sin"], "prueba.op.comercial": ["operario", "sin", "sin"], "prueba.sup.comercial": ["supervisor", "sin", "sin"],
  "prueba.op.tecnico": ["sin", "operario", "sin"], "prueba.sup.plantas": ["sin", "sup_plantas", "sin"], "prueba.sup.distribucion": ["sin", "sup_distribucion", "sin"], "prueba.sup.plantas.distribucion": ["sin", "sup_ambas", "sin"],
  "prueba.auditor.aseo": ["sin", "sin", "auditor"], "prueba.sup.aseo": ["sin", "sin", "supervisor"], "prueba.caso.mixto": ["sin", "sup_plantas", "supervisor"], "prueba.caso.todo": ["supervisor", "sup_ambas", "supervisor"],
  "prueba.sin.acceso": ["sin", "sin", "sin"], "prueba.inactivo": ["sin", "sin", "sin"],
  "prueba.perso.campo.sin.acta": [null, "sin", "sin"], "prueba.perso.consulta.analisis": [null, "sin", "sin"], "prueba.perso.sup.sin.registro": ["sin", null, "sin"], "prueba.perso.solo.dashboard.aseo": ["sin", "sin", null],
};
for (const [e, [f, t, s]] of Object.entries(esperado)) ok(`reconocer ${e}: formularios ${f ?? "Personalizado"} · Técnica ${t ?? "Personalizado"} · Aseo ${s ?? "Personalizado"}`, igual(Object.values(R(e)), [f, t, s]), JSON.stringify(R(e)));
ok("Personalizado: exactamente los 4 «perso» del doble, cada uno en su geoportal", igual(DOBLE.filter((u) => u.rol !== "admin" && P.esPersonalizado(P.casillasDe(u)).length).map((u) => [u.email.split("@")[0], P.esPersonalizado(P.casillasDe(u))]),
  [["prueba.perso.campo.sin.acta", ["comercial"]], ["prueba.perso.consulta.analisis", ["comercial"]], ["prueba.perso.solo.dashboard.aseo", ["aseo"]], ["prueba.perso.sup.sin.registro", ["tecnica"]]]));
ok("Personalizado: registro_tecnico + dashboard_tecnico calza (Supervisor de plantas), ya no es «Personalizado» como en la v1", R("prueba.sup.plantas").tecnica === "sup_plantas");

// ---- 3. Ida y vuelta: abrir → guardar sin cambios → mismas casillas (a los 20) ----
for (const u of DOBLE) {
  const c = P.casillasDe(u), e = P.envio(u.email, c, u.horario, u.dias, DISP);
  ok(`ida y vuelta ${u.email.split("@")[0]}: el envío lleva las 15 casillas como booleano, iguales a las de hoy, y el resumen sale vacío`,
    ORDEN.every((x) => typeof e[x] === "boolean" && e[x] === u[`ver_${x}`]) && e.horario === u.horario && e.dias === u.dias && P.resumen(c, c, { nombre: "", horario: u.horario, dias: u.dias, rol: u.rol }, { nombre: "", horario: u.horario, dias: u.dias, rol: u.rol }, DISP).vacio);
}
ok("ida y vuelta con «Personalizado»: guardar sin tocar el renglón envía las casillas tal cual (perso.sup.sin.registro conserva dashboard_tecnico sin registro)", (() => { const e = P.envio("x", C("prueba.perso.sup.sin.registro"), "sin_restriccion", "todos", DISP); return e.dashboard_tecnico === true && e.registro_tecnico === false; })());

// ---- 4. Los casos del 22-nov ----
// lsilva: Consulta Explorar + Supervisor de plantas + Supervisor de aseo; cambiar solo Técnica NO apaga los modos comerciales ni el análisis (el error de «Aplicar perfil…»)
{
  const c0 = { ...C("prueba.caso.mixto"), analisis_contrato: false }, c1 = P.aplicarTecnica(c0, "sup_ambas");
  ok("lsilva: cambiar Técnica a «plantas y distribución» deja Explorar, el aseo y todo lo comercial como estaba", c1.explorar && c1.aseo && c1.dashboard_aseo && c1.dashboard_redes && P.FORMULARIOS_COMERCIAL.every((x) => c1[x] === c0[x]));
  const e = P.envio("lsilva@x", c1, "sin_restriccion", "todos", DISP);
  ok("lsilva: el envío trae analisis_contrato EXPLÍCITO (el 22-nov faltaba y el servidor conservaba el viejo)", Object.hasOwn(e, "analisis_contrato") && e.analisis_contrato === false);
  ok("lsilva: la línea de la lista dice «Comercial: Consulta (Explorar) · Técnica: Supervisor de plantas · Aseo: Supervisor de aseo»", P.lineaUsuario(por("prueba.caso.mixto")) === "Comercial: Consulta (Explorar) · Técnica: Supervisor de plantas · Aseo: Supervisor de aseo", P.lineaUsuario(por("prueba.caso.mixto")));
}
// anieto: todo
ok("anieto (todo): Supervisor comercial con los 5 modos · Supervisor de plantas y distribución · Supervisor de aseo; nada Personalizado", P.lineaUsuario(por("prueba.caso.todo")) === "Comercial: Supervisor comercial (Explorar, Focalización, Comercial, Rutas, Dashboard) · Técnica: Supervisor de plantas y distribución · Aseo: Supervisor de aseo" && P.esPersonalizado(C("prueba.caso.todo")).length === 0, P.lineaUsuario(por("prueba.caso.todo")));
ok("anieto: pasar Técnica a «Sin acceso» deja Comercial y Aseo intactos y el resumen apaga solo 3 casillas (en rojo)", (() => { const c = C("prueba.caso.todo"), r = P.resumen(c, P.aplicarTecnica(c, "sin"), { nombre: "", horario: "extendido", dias: "todos", rol: "consulta" }, { nombre: "", horario: "extendido", dias: "todos", rol: "consulta" }, DISP);
  return r.cambios.length === 3 && r.cambios.every((x) => !x.enciende && x.geoportal === "tecnica") && igual(r.renglones, [{ geoportal: "tecnica", antes: "Supervisor de plantas y distribución", despues: "Sin acceso" }]); })());
// Solo Técnica (o solo Aseo) nunca recibe el análisis de contrato
ok("solo Técnica: ningún perfil de Técnica enciende analisis_contrato", Object.keys(P.PERFILES_TECNICA).every((p) => !P.aplicarTecnica(P.sinNada(), p).analisis_contrato));
ok("solo Aseo: ningún perfil de Aseo enciende analisis_contrato", Object.keys(P.PERFILES_ASEO).every((p) => !P.aplicarAseo(P.sinNada(), p).analisis_contrato));
ok("«Consulta» (solo modos) nunca lleva análisis: el análisis va solo con formularios de Comercial (Operario o Supervisor)", !P.aplicarFormularios(P.ponerModo(C("prueba.perso.consulta.analisis"), "explorar", true), "sin").analisis_contrato
  && Object.entries(P.PERFILES_FORMULARIOS).every(([p, d]) => d.casillas.includes("analisis_contrato") === (p !== "sin")));
// «Consulta sin ningún modo» (§8 de la v1): en la v2 no es un error, es «Sin acceso» en Comercial
ok("v2: Comercial sin modos y «Sin formularios» = «Sin acceso» (no se rechaza: es quitar el geoportal)", P.textoComercial(P.sinNada()) === "Sin acceso" && P.lineaUsuario(por("prueba.sin.acceso")) === "Sin acceso");

ok("solo acta (sin campo): la lista NO dice «Sin acceso»: Comercial «Personalizado» (el acta cuenta)", P.lineaUsuario({ ...por("prueba.sin.acceso"), ver_acta: true }) === "Comercial: Personalizado");

// ---- 5. Resumen (rojo y verde, destacados, datos) ----
{
  const c0 = C("prueba.op.comercial"), c1 = P.ponerModo(P.aplicarFormularios(c0, "supervisor"), "explorar", true);
  const d = { nombre: "Ana", horario: "sin_restriccion", dias: "todos", rol: "consulta" };
  const r = P.resumen(c0, c1, d, { ...d, nombre: "Ana María", horario: "laboral" }, DISP);
  ok("resumen: Operario → Supervisor con Explorar enciende Explorar, dashboard_campo y dashboard_acta (verde) y no apaga nada", igual(r.cambios.map((x) => [x.casilla, x.enciende]), [["explorar", true], ["dashboard_campo", true], ["dashboard_acta", true]]));
  ok("resumen: el renglón «Operario comercial → Supervisor comercial (Explorar)»", igual(r.renglones, [{ geoportal: "comercial", antes: "Operario comercial", despues: "Supervisor comercial (Explorar)" }]), JSON.stringify(r.renglones));
  ok("resumen: destaca la entrada al mapa comercial", r.destacados.some((t) => t.includes("mapa comercial") && t.includes("Explorar")));
  ok("resumen: nombre y horario cambiados", igual(r.datos.map((x) => x.campo), ["nombre", "horario"]) && r.datos[1].despues.startsWith("Laboral"));
  const r2 = P.resumen(C("prueba.consulta.explorar"), P.aplicarFormularios(C("prueba.consulta.explorar"), "operario"), d, d, DISP);
  ok("resumen: encender el análisis de contrato lo destaca (datos personales)", r2.destacados.some((t) => t.includes("Análisis de contrato")));
  const r3 = P.resumen(C("prueba.sup.comercial"), P.aplicarFormularios(C("prueba.sup.comercial"), "sin"), d, d, DISP);
  ok("resumen: Supervisor comercial → Sin formularios apaga 5 (rojo) y el renglón dice «Sin acceso»", r3.cambios.length === 5 && r3.cambios.every((x) => !x.enciende) && r3.renglones[0].despues === "Sin acceso");
  const r4 = P.resumen(base, base, { ...d, rol: "admin" }, d, DISP);
  ok("resumen: «Hacer consulta» muestra el rol Administrador → Usuario", igual(r4.datos.map((x) => [x.campo, x.antes, x.despues]), [["rol", "Administrador", "Usuario (por geoportal)"]]) && !r4.vacio);
  const disp14 = new Set([...DISP].filter((x) => x !== "dashboard_redes"));
  ok("resumen (R11): una casilla que el servidor no lista no aparece en el resumen", P.resumen(base, { ...base, dashboard_redes: true }, d, d, disp14).vacio);
}

// ---- 6. Envío (R11) y verificación ----
{
  const disp14 = new Set([...DISP].filter((x) => x !== "dashboard_redes"));
  const e = P.envio("a@b", { ...base, dashboard_redes: true }, "laboral", "habiles", disp14);
  ok("envío (R11): sin la columna en el servidor, dashboard_redes NO se envía; los 5 modos siempre", !Object.hasOwn(e, "dashboard_redes") && P.MODOS.every((m) => e[m] === false) && Object.keys(e).length === 3 + 14);
  ok("perfilDisponible (R11): «Supervisor de distribución» no se puede escoger sin dashboard_redes; «de plantas» sí", !P.perfilDisponible(P.PERFILES_TECNICA.sup_distribucion.casillas, disp14) && P.perfilDisponible(P.PERFILES_TECNICA.sup_plantas.casillas, disp14));
  const u = por("prueba.caso.mixto"), c = P.casillasDe(u), d = { nombre: "", horario: u.horario, dias: u.dias, rol: u.rol };
  ok("verificar: lo que se envió quedó → sin faltas", igual(P.verificar(u.email, c, d, DISP, DOBLE), []));
  const leidoMal = DOBLE.map((x) => (x.email === u.email ? { ...x, ver_analisis_contrato: true, ver_explorar: false } : x));
  ok("verificar: el caso del 22-nov (el servidor conservó el análisis y apagó Explorar) → un solo aviso con la lista exacta", igual(P.verificar(u.email, c, d, DISP, leidoMal), ["Explorar (encender)", "Análisis de contrato (datos personales) (apagar)"]), JSON.stringify(P.verificar(u.email, c, d, DISP, leidoMal)));
  ok("verificar: también el rol, el horario, los días, el nombre (si se pidió) y el estado activo", igual(P.verificar(u.email, c, { nombre: "Otro", horario: "laboral", dias: "habiles", rol: "admin", activo: false }, DISP, DOBLE, { nombre: true }),
    ["rol (Administrador)", "horario (Laboral (7:50–18:00))", "días (Lunes a viernes)", "nombre", "desactivar la cuenta"]), JSON.stringify(P.verificar(u.email, c, { nombre: "Otro", horario: "laboral", dias: "habiles", rol: "admin", activo: false }, DISP, DOBLE, { nombre: true })));
  ok("verificar: un correo que no está en la lista", igual(P.verificar("nadie@x", c, d, DISP, DOBLE), ["el usuario no aparece en la lista"]));
  ok("verificar: el correo se compara en minúsculas y sin espacios", igual(P.verificar("  PRUEBA.CASO.MIXTO@EMDUPAR.GOV.CO ", c, d, DISP, DOBLE), []));
}

// ---- 7. Avisos de horario ----
ok("aviso de horario: Técnica con horario laboral avisa; sin restricción y todos los días no", !!P.avisoHorario(P.aplicarTecnica(base, "operario"), "laboral", "habiles") && P.avisoHorario(P.aplicarTecnica(base, "operario"), "sin_restriccion", "todos") === null);
ok("aviso de horario: solo modos del geovisor (oficina) no avisa", P.avisoHorario(C("prueba.consulta.modos"), "laboral", "habiles") === null);
ok("aviso de horario: menciona cada geoportal afectado", (() => { const t = P.avisoHorario(C("prueba.caso.todo"), "extendido", "todos"); return t.includes("campo") && t.includes("Técnica") && t.includes("Aseo"); })());

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
