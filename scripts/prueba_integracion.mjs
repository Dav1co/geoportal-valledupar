// Prueba de la INTEGRACIÓN de la Torre A en el frontend (lógica pura, sin red ni navegador):
//  1. El reporte general NO ofrece los formatos del Paso D (src/campo/ReporteGeneral.tsx usa sinFormatosD).
//  2. La lista de entradas del área de campo y la visibilidad de la entrada del acta solo con el permiso `acta` (src/campo/entradas.ts).
// Uso: node scripts/prueba_integracion.mjs   (usa el paquete typescript del proyecto)
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const leer = (rel) => readFileSync(join(aqui, "..", rel), "utf8");
const compilar = (rel) => ts.transpileModule(leer(rel), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");
const urlTipos = aUrl(compilar("src/campo/formatos/tipos.ts"));
const T = await import(urlTipos);

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- 1. Filtro de ReporteGeneral ----
const general = (codigo) => ({ codigo, nombre: codigo, orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [], campos: [], fotos: [], genera_resultado: false, usa_consecutivo: false });
const formatoD = (codigo) => ({ ...general(codigo), fotos_min: 2, fotos_max: 4, genera_resultado: true, usa_consecutivo: true, campos: [{ codigo: "lectura", nombre: "Lectura", tipo_dato: "decimal", obligatorio: true, activo: true }], fotos: [{ codigo: "fachada", nombre: "Fachada", obligatoria: true, soporte_inefectiva: true, orden: 1, activo: true }] });
const grupos = [
  { codigo: "comercial_perdidas", nombre: "Pérdidas", orden: 1, activo: true, tipos: [general("fraude"), general("medidor_danado")] },
  { codigo: "cartera_formatos", nombre: "Cartera", orden: 2, activo: true, tipos: [formatoD("suspension"), formatoD("corte")] },
  { codigo: "mixto", nombre: "Mixto", orden: 3, activo: true, tipos: [general("otro"), formatoD("verificacion")] },
];
const visibles = T.sinFormatosD(grupos).filter((g) => g.activo && g.tipos.some((t) => t.activo));
const codigos = visibles.flatMap((g) => g.tipos.map((t) => t.codigo));
ok("filtro: el reporte general conserva sus tipos", igual(codigos, ["fraude", "medidor_danado", "otro"]));
ok("filtro: ningún tipo del Paso D llega al reporte general", !codigos.some((c) => ["suspension", "corte", "verificacion"].includes(c)));
ok("filtro: un grupo solo con formatos del Paso D desaparece", !visibles.some((g) => g.codigo === "cartera_formatos"));
ok("filtro: un grupo mixto se queda solo con lo que el reporte general sabe enviar", igual(visibles.find((g) => g.codigo === "mixto")?.tipos.map((t) => t.codigo), ["otro"]));
ok("filtro: con el servidor sin el Paso D (sin claves nuevas) no cambia nada", igual(T.sinFormatosD([{ codigo: "g", nombre: "g", orden: 1, activo: true, tipos: [{ codigo: "t", nombre: "t", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] }]).flatMap((g) => g.tipos.map((t) => t.codigo)), ["t"]));
ok("filtro: sin grupos devuelve lista vacía", igual(T.sinFormatosD([]), []));
ok("filtro: no modifica los grupos recibidos", grupos[1].tipos.length === 2 && grupos[2].tipos.length === 2);
const rg = leer("src/campo/ReporteGeneral.tsx");
ok("ReporteGeneral.tsx importa sinFormatosD de ./formatos/tipos", /import \{ sinFormatosD \} from "\.\/formatos\/tipos";/.test(rg));
ok("ReporteGeneral.tsx filtra los grupos con sinFormatosD(def.grupos)", /const grupos = useMemo\(\(\) => sinFormatosD\(def\.grupos\)\.filter\(/.test(rg));
ok("ReporteGeneral.tsx ya no usa def.grupos sin filtrar", (rg.match(/def\.grupos/g) ?? []).length === 1);

// ---- 2. Entradas del área de campo y la entrada del acta (solo con el permiso `acta`) ----
const E = await import(aUrl(compilar("src/campo/entradas.ts")));
const ids = (c) => E.entradasDeCampo(c).map((e) => e.id);
ok("entradas: sin permiso de acta NO aparece la entrada del acta", !ids({ puedeReportar: true, hayFormatos: true, puedeActa: false }).includes("acta"));
ok("entradas: con permiso de acta SÍ aparece", ids({ puedeReportar: true, hayFormatos: true, puedeActa: true }).includes("acta"));
ok("entradas (14/11): orden Reportar anomalía, Formatos de actividad, Reportar posible pérdida, Análisis de contrato", igual(ids({ puedeReportar: true, hayFormatos: true, puedeActa: true }), ["reporte_general", "formatos", "acta", "analisis_contrato"]));
ok("entradas: sin formatos activos no aparece «Formatos de actividad» (los formatos nacen inactivos)", igual(ids({ puedeReportar: true, hayFormatos: false, puedeActa: false }), ["reporte_general", "analisis_contrato"]));
ok("entradas: solo permiso de acta y sin formatos: reporte general y acta", igual(ids({ puedeReportar: true, hayFormatos: false, puedeActa: true }), ["reporte_general", "acta", "analisis_contrato"]));
const act = E.entradasDeCampo({ puedeReportar: true, hayFormatos: false, puedeActa: true }).find((e) => e.id === "acta");
ok("entradas: la del acta ya se puede abrir (hay pantalla): habilitada y sin marca de pendiente", act.habilitada === true && !act.pendiente);
ok("entradas: el reporte general se deshabilita si el servidor no deja reportar", E.entradasDeCampo({ puedeReportar: false, hayFormatos: true, puedeActa: false }).every((e) => e.habilitada === false));
ok("entradas (14/11): «Análisis de contrato» es Próximamente (pendiente, no habilitada) y con la descripción pedida", (() => { const a = E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: false }).find((e) => e.id === "analisis_contrato"); return !!a && a.pendiente === true && a.habilitada === false && a.titulo === "Análisis de contrato" && a.descripcion === "Escriba un contrato y vea todo: comercial, medidor, consumos, gestiones y ubicación."; })());
ok("entradas: reporte general y formatos se habilitan si puede reportar", E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: false }).filter((e) => !e.pendiente).every((e) => e.habilitada === true));
ok("entradas: cada entrada tiene título y descripción en español", E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: true }).every((e) => e.titulo.length > 3 && e.descripcion.length > 10));
// Paso C: «Revisión de reportes» solo con el permiso de supervisión (def.puede.supervisar); quien solo reporta nunca la ve
ok("entradas (Paso C): sin puedeSupervisar no hay «Revisión de reportes»", !ids({ puedeReportar: true, hayFormatos: true, puedeActa: false }).includes("revision") && !ids({ puedeReportar: true, hayFormatos: true, puedeActa: false, puedeSupervisar: false }).includes("revision"));
ok("entradas (Paso C): con puedeSupervisar aparece, habilitada, al final", (() => { const l = E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: true, puedeSupervisar: true }); const r = l.at(-1); return r.id === "revision" && r.habilitada === true && !r.pendiente && r.titulo === "Supervisión y dashboard"; })());
ok("entradas (14/11): nombres visibles nuevos y secciones 1·2·3·4 en orden; gestión al final, en color de gestión y sin descripción; solo «Formatos de actividad» lleva flecha", (() => { const l = E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: true, puedeSupervisarActas: true, puedeSupervisar: true }); const t = l.map((e) => e.titulo); const sec = l.map((e) => e.seccion); return igual(t, ["Reportar anomalía", "Formatos de actividad", "Reportar posible pérdida", "Análisis de contrato", "Aperturas sin registrar", "Supervisión y dashboard"]) && igual(sec, [1, 2, 3, 3, 4, 4]) && l.filter((e) => e.gestion).map((e) => e.id).join() === "acta_supervision,revision" && l.filter((e) => e.gestion).every((e) => e.descripcion === "") && l.filter((e) => e.abreMas).map((e) => e.id).join() === "formatos"; })());
ok("entradas (Paso C): el supervisor sin permiso de reportar igual ve la revisión", ids({ puedeReportar: false, hayFormatos: false, puedeActa: false, puedeSupervisar: true }).includes("revision"));
ok("entradas (Paso C): AreaCampo carga la revisión de forma diferida (React.lazy) y solo con puede.supervisar (con def?. porque quien solo tiene acta no pide el formulario)", /lazy\(\(\) => import\("\.\/dashboard\/Revision"\)\)/.test(leer("src/campo/AreaCampo.tsx")) && /abierta === "revision" && def\?\.puede\.supervisar/.test(leer("src/campo/AreaCampo.tsx")));
ok("App.tsx (Paso C): MapView y el Dashboard comercial se cargan de forma diferida (MapLibre no viaja con la página principal)", /const MapView = lazy\(/.test(leer("src/App.tsx")) && /const Dashboard = lazy\(/.test(leer("src/App.tsx")) && !/^import \{[^}]*\bMapView\b[^}]*\} from/m.test(leer("src/App.tsx")));
ok("max_descripcion (Paso C): una sola fuente; ningún 1000 escrito en los formularios ni en la Edge", !/maxLength=\{1000\}|MAX_DESCRIPCION = 1000/.test(leer("src/campo/ReporteGeneral.tsx") + leer("src/campo/formatos/FormularioFormato.tsx")));
const ac = leer("src/campo/AreaCampo.tsx");
ok("AreaCampo.tsx usa la lista de entradas y no deja el estado suelto abiertoFormatos", /entradasDeCampo\(/.test(ac) && !/abiertoFormatos/.test(ac));
ok("AreaCampo.tsx pasa el permiso de acta a la lista (puedeActa: acta)", /puedeActa: acta/.test(ac));
ok("AreaCampo.tsx ya no lista «Acta de inspección» como «Próximamente» para todos", !/PROXIMAMENTE = \[[^\]]*Acta de inspección/.test(ac));
ok("AreaCampo.tsx monta FormatosCampo con la definición del servidor", /<FormatosCampo key=\{version\} def=\{def\} correo=\{correo\}/.test(ac));

// ---- 3. Administración: casillas del acta (comprobaciones sobre el código fuente; el proyecto no tiene ejecutor de pruebas de componentes) ----
const ad = leer("src/components/Admin.tsx"), api = leer("src/lib/api.ts");
ok("Admin: casilla «Acta de inspección técnica» (clave acta)", /\["acta", "Acta de inspección técnica"\]/.test(ad));
ok("Admin: casilla «Supervisor de actas» (clave dashboard_acta)", /\["dashboard_acta", "Supervisor de actas"\]/.test(ad));
ok("Admin: las casillas del acta solo se muestran si el servidor trae ver_acta (conActa)", /const conActa = useMemo\(\(\) => usuarios\.some\(\(u\) => typeof u\.ver_acta === "boolean"\)/.test(ad) && /\{conActa && \(\s*<BloquePermisos/.test(ad));
ok("Admin: el aviso de horario del acta existe y reutiliza el mismo texto que Campo", /avisoHorarioActa\(borrador\)/.test(ad) && /const avisoHorarioCampo = \(b: Borrador\) => avisoHorario\(b, \["campo", "dashboard_campo"\]/.test(ad));
ok("Admin: tras guardar se verifica que el servidor aplicó los permisos de acta", /conActa && !\(await verificarActa\(/.test(ad));
ok("Admin: el perfil técnico conserva los permisos de acta del borrador", /borrador\.acta !== undefined \? \{ acta: borrador\.acta, dashboard_acta: borrador\.dashboard_acta \}/.test(ad));
ok("Admin: la lista muestra las etiquetas de acta y «Sin acceso» las tiene en cuenta", /deActa\.map/.test(ad) && /deCampo\.length === 0 && deActa\.length === 0/.test(ad));
ok("Admin: «Sin ningún modo asignado» cuenta los modos de acta", /\.\.\.\(conActa \? CAMPOS_ACTA : \[\]\)/.test(ad));
ok("api.ts: UsuarioAdmin trae ver_acta y ver_dashboard_acta (opcionales)", /ver_acta\?: boolean;\s*ver_dashboard_acta\?: boolean;/.test(api));
ok("api.ts: permisos() acepta acta y dashboard_acta (opcionales)", /acta\?: boolean;[^\n]*\n\s*dashboard_acta\?: boolean;(\s*\n\s*aseo\?: boolean;[^\n]*\n\s*dashboard_aseo\?: boolean;)?\s*\}\) =>/.test(api));
ok("api.ts: el perfil trae las claves acta y dashboard_acta (opcionales)", /acta\?: boolean; dashboard_acta\?: boolean;/.test(api));

// ---- 4. El permiso de acta llega a AreaCampo (App.tsx) ----
const app = leer("src/App.tsx");
ok("App.tsx: las dos pantallas de campo reciben acta={perfil?.permisos?.acta === true} (lo decide el servidor)", (app.match(/<AreaCampo correo=\{email\} acta=\{perfil\?\.permisos\?\.acta === true\}/g) ?? []).length === 2);
ok("App.tsx: no queda ningún AreaCampo sin el permiso", (app.match(/<AreaCampo /g) ?? []).length === 2);

// ---- 5. Quien solo tiene acta: ve únicamente el acta y AreaCampo no pide el formulario de campo ----
ok("entradas: solo acta (sin campo) ve ÚNICAMENTE la entrada del acta", igual(ids({ puedeReportar: false, hayFormatos: false, puedeActa: true, puedeCampo: false }), ["acta"]));
ok("entradas: solo acta no ve reporte general ni formatos aunque el catálogo tenga formatos", igual(ids({ puedeReportar: true, hayFormatos: true, puedeActa: true, puedeCampo: false }), ["acta"]));
ok("entradas: campo + acta ve las dos entradas", igual(ids({ puedeReportar: true, hayFormatos: true, puedeActa: true, puedeCampo: true }), ["reporte_general", "formatos", "acta", "analisis_contrato"]));
ok("entradas: sin campo y sin acta no hay ninguna entrada", igual(ids({ puedeReportar: false, hayFormatos: false, puedeActa: false, puedeCampo: false }), []));
ok("entradas: sin la opción puedeCampo se comporta como antes (compatibilidad)", igual(ids({ puedeReportar: true, hayFormatos: true, puedeActa: false }), ["reporte_general", "formatos", "analisis_contrato"]));
ok("entradas: el supervisor de actas ve «Aperturas sin registrar» (pantalla mínima, habilitada)", (() => { const e = E.entradasDeCampo({ puedeReportar: false, hayFormatos: false, puedeActa: true, puedeCampo: false, puedeSupervisarActas: true }).find((x) => x.id === "acta_supervision"); return !!e && e.titulo === "Aperturas sin registrar" && !e.pendiente && e.habilitada === true; })());
ok("entradas: sin permiso de supervisión no aparece el marcador del tablero", !ids({ puedeReportar: true, hayFormatos: true, puedeActa: true, puedeCampo: true }).includes("acta_supervision"));
const ac2 = leer("src/campo/AreaCampo.tsx");
ok("AreaCampo.tsx: sin permiso de campo NO pide el formulario de campo (if (!campo) return)", /if \(!campo\) return;/.test(ac2));
ok("AreaCampo.tsx: con campo falso no muestra el error de «Sin acceso a Formatos de campo»", /if \(campo && error\)/.test(ac2) && /if \(campo && !def\)/.test(ac2));
ok("AreaCampo.tsx: «Daños» ya no figura como «Próximamente» (son tipos del Reporte general)", !/PROXIMAMENTE = \[[^\]]*Daños/.test(ac2));
ok("entradas (14/11): «Análisis de contrato» (antes SCRR) solo se ve con campo", !ids({ puedeReportar: false, hayFormatos: false, puedeActa: true, puedeCampo: false }).includes("analisis_contrato") && !/PROXIMAMENTE/.test(ac2));
const app2 = leer("src/App.tsx");
ok("App.tsx: las dos pantallas de campo reciben acta, dashboardActa y campo calculados del perfil", (app2.match(/dashboardActa=\{perfil\?\.permisos\?\.dashboard_acta === true \|\| esAdmin\} campo=\{esAdmin \|\| perfil\?\.permisos\?\.campo === true \|\| perfil\?\.permisos\?\.dashboard_campo === true\}/g) ?? []).length === 2);
const ar = leer("src/areas/areas.ts");
ok("areas.ts: el área de campo cuenta acta y dashboard_acta", /p\.acta === true \|\| p\.dashboard_acta === true/.test(ar));

// ---- 6. La entrada del acta abre la pantalla del acta ----
const ac3 = leer("src/campo/AreaCampo.tsx");
ok("AreaCampo.tsx: la entrada del acta monta PantallaActa solo con el permiso de acta", /abierta === "acta" && acta\) \{\s*return <PantallaActa correo=\{correo\}/.test(ac3) && /import \{ PantallaActa \} from "\.\/acta\/PantallaActa";/.test(ac3));
ok("AreaCampo.tsx: la entrada del supervisor abre AperturasSinRegistrar (solo con dashboardActa)", /abierta === "acta_supervision" && dashboardActa/.test(ac) && /<AperturasSinRegistrar/.test(ac));
// ===== Acta de revisión o instalación: lista «Próximamente» y enlace al acta de inspección =====
const ac4 = leer("src/campo/AreaCampo.tsx"), pa4 = leer("src/campo/acta/PantallaActa.tsx"), ff4 = leer("src/campo/formatos/FormularioFormato.tsx"), fc4 = leer("src/campo/formatos/FormatosCampo.tsx");
ok("«Próximamente» ya no está en AreaCampo: lo único pendiente es «Análisis de contrato» en entradas.ts (Instalación de medidor y Revisión previa ya son formatos de actividad)", !/PROXIMAMENTE/.test(ac4) && E.entradasDeCampo({ puedeReportar: true, hayFormatos: true, puedeActa: true }).filter((e) => e.pendiente).map((e) => e.id).join() === "analisis_contrato");
ok("el enlace al acta pasa el permiso de acta y el contrato: AreaCampo → FormatosCampo → FormularioFormato", /puedeActa=\{acta\} onAbrirActa=/.test(ac4) && /puedeActa=\{puedeActa\} onAbrirActa=\{onAbrirActa\}/.test(fc4) && /puedeActa = false, onAbrirActa/.test(ff4));
ok("AreaCampo abre el acta con el contrato precargado (contratoInicial) y lo limpia al volver", /contratoInicial=\{contratoPuente\}/.test(ac4) && /setContratoPuente\(""\)/.test(ac4));
ok("PantallaActa acepta contratoInicial: abre «Nueva acta» con el contrato escrito y NO verifica sola (sigue el botón Verificar)", /contratoInicial\?: string/.test(pa4) && /useState\(contratoInicial\)/.test(pa4) && !/verificar\(\)[^\n]*contratoInicial/.test(pa4));
ok("el enlace aparece solo después de guardar (en la confirmación) y solo con irregularidad, permiso de acta y contrato: las fotos viven en memoria y no se pierden", /setInvitarActa\(marcoIrr && puedeActa && onAbrirActa/.test(ff4) && /\{invitarActa && \(/.test(ff4));
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
