// Prueba de la LÓGICA PURA y del CLIENTE DE API de la pantalla del acta (src/campo/acta/logica.ts y apiActa.ts). Sin navegador ni red real: `fetch` y la sesión están simulados.
// Uso: node scripts/prueba_acta.mjs   (usa el paquete typescript del proyecto)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (rel) => ts.transpileModule(readFileSync(join(aqui, "..", rel), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---------- Carga de módulos ----------
const urlLogica = aUrl(compilar("src/campo/acta/logica.ts").replace(/from\s+["']\.\/tipos["']/g, 'from "data:text/javascript,"'));
const L = await import(urlLogica);

// Sesión y fetch simulados para el cliente de API
let respuestas = [], llamadas = [], sesion = true, refrescos = 0;
const stubSupabase = aUrl(`export const FUNCTIONS_URL = "http://sim.local/functions/v1"; export const supabase = { auth: {
  getSession: async () => ({ data: { session: globalThis.__sesion ? { access_token: "tok-falso" } : null } }),
  refreshSession: async () => { globalThis.__refrescos++; return { error: globalThis.__refrescoFalla ? new Error("x") : null }; } } };`);
globalThis.__sesion = true; globalThis.__refrescos = 0;
const urlApiCampo = aUrl(compilar("src/campo/apiCampo.ts").replace(/from\s+["']\.\.\/lib\/supabase["']/g, `from "${stubSupabase}"`));
const jsApi = compilar("src/campo/acta/apiActa.ts").replace(/from\s+["']\.\.\/\.\.\/lib\/supabase["']/g, `from "${stubSupabase}"`).replace(/from\s+["']\.\.\/apiCampo["']/g, `from "${urlApiCampo}"`);
const A = await import(aUrl(jsApi));
const { ErrorCampo } = await import(urlApiCampo);
globalThis.fetch = async (url, init = {}) => {
  llamadas.push({ url: String(url), init });
  const r = respuestas.shift();
  if (r === "RED") throw new TypeError("fallo de red");
  return new Response(r.cuerpo === undefined ? null : (typeof r.cuerpo === "string" ? r.cuerpo : JSON.stringify(r.cuerpo)), { status: r.s });
};
const sim = (...r) => { respuestas = r; llamadas = []; };
const intenta = async (f) => { try { return { v: await f() }; } catch (e) { return { e }; } };

// ---------- Catálogo de ejemplo (misma forma que `formulario`) ----------
const cat = {
  capacidades: { capturar: true, supervisar: false, administrar: false }, aviso_registro: "x",
  tipos_hallazgo: [
    { codigo: "conexion_directa", nombre: "Posible conexión directa", nota: null, exige_texto: false, excluyente: false, habilita_accion: null },
    { codigo: "reconexion_no_autorizada", nombre: "Posible reconexión no autorizada", nota: null, exige_texto: false, excluyente: false, habilita_accion: "corte_taponamiento" },
    { codigo: "otro", nombre: "Otro", nota: null, exige_texto: true, excluyente: false, habilita_accion: null },
    { codigo: "sin_irregularidad", nombre: "Sin irregularidad", nota: null, exige_texto: false, excluyente: true, habilita_accion: null },
  ],
  calidades_atendiente: [{ codigo: "propietario", nombre: "Propietario", exige_texto: false }, { codigo: "otro", nombre: "Otro", exige_texto: true }],
  estados_medidor: [{ codigo: "funcionando", nombre: "Funcionando" }], estados_sellos: [{ codigo: "rotos", nombre: "Rotos" }], diametros: [{ codigo: "d_1_2", nombre: "1/2 pulgada" }],
  acciones: [
    { codigo: "retiro_medidor", nombre: "Retiro de medidor", campos: [{ clave: "serie_retirada", etiqueta: "Serie", tipo: "texto", obligatorio: true }, { clave: "lectura_retiro", etiqueta: "Lectura", tipo: "numero", obligatorio: true }] },
    { codigo: "corte_taponamiento", nombre: "Corte o taponamiento", campos: [{ clave: "realizado_a_las", etiqueta: "Hora", tipo: "hora", obligatorio: true }] },
  ],
  tipos_foto: [
    { codigo: "fachada", nombre: "Fachada", exigida_con_irregularidad: true, acta_fisica: false }, { codigo: "hallazgo", nombre: "Hallazgo", exigida_con_irregularidad: true, acta_fisica: false },
    { codigo: "medidor", nombre: "Medidor", exigida_con_irregularidad: false, acta_fisica: false }, { codigo: "acta_fisica", nombre: "Acta física", exigida_con_irregularidad: false, acta_fisica: true },
  ],
  limites: { min_fotos_irregularidad: 2, min_fotos_sin_irregularidad: 1, max_fotos: 10, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
};
const AHORA = new Date("2026-11-11T15:00:00-05:00");                       // 11/11/2026, 3:00 p. m. en Bogotá
const hoy = L.hoyBogota(AHORA);
const fotos = (...t) => t.map((tipo) => ({ tipo }));
const bien = () => ({
  ...L.borradorVacio("con_contrato"), contrato: "123456", direccion: "CRA 10 # 5-20", barrio: "Centro", estrato: "3", uso: "RESIDENCIAL",
  tieneMedidor: true, medidorSerie: "M-1", marca: "X", lectura: "120,5", estadoMedidor: "funcionando",
  hallazgos: [{ codigo: "conexion_directa", texto: "" }], descripcion: "Conexión directa antes del medidor",
  nadieAtendio: false, atNombre: "Persona Prueba", atCalidad: "propietario", firmoAtendiente: true, seNego: false, firmoOperario: true, fechaFisica: hoy,
});
const FB = fotos("fachada", "hallazgo", "acta_fisica");

// ================= 1. Fecha del acta física (Bogotá, tope de 30 días) =================
ok("fecha: hoy en Bogotá aunque el celular esté en otra zona (3:00 a. m. del 12 UTC = 10:00 p. m. del 11 en Bogotá)", L.hoyBogota(new Date("2026-11-12T03:00:00Z")) === "2026-11-11");
ok("fecha: medianoche UTC del 12 aún es 11 en Bogotá", L.hoyBogota(new Date("2026-11-12T00:00:00Z")) === "2026-11-11");
ok("fecha: hoy es válida", L.validarFechaPapel(hoy, AHORA, 30) === null);
ok("fecha: hace exactamente 30 días es válida", L.validarFechaPapel(L.sumarDias(hoy, -30), AHORA, 30) === null);
ok("fecha: hace 31 días se rechaza con mensaje claro y la fecha límite", /no puede ser anterior a 30 días \(desde el 12\/10\/2026\)/.test(L.validarFechaPapel(L.sumarDias(hoy, -31), AHORA, 30) ?? ""), L.validarFechaPapel(L.sumarDias(hoy, -31), AHORA, 30));
ok("fecha: mañana se rechaza (futura)", L.validarFechaPapel(L.sumarDias(hoy, 1), AHORA, 30) === "La fecha del acta física no puede ser futura.");
ok("fecha: vacía, mal formada o inexistente se rechazan", L.validarFechaPapel("", AHORA, 30) !== null && L.validarFechaPapel("11/11/2026", AHORA, 30) !== null && L.validarFechaPapel("2026-02-30", AHORA, 30) !== null);
ok("fecha: el tope sale del servidor (con 7 días, hace 8 se rechaza)", L.validarFechaPapel(L.sumarDias(hoy, -8), AHORA, 7) !== null && L.validarFechaPapel(L.sumarDias(hoy, -7), AHORA, 7) === null);
ok("fecha: sumarDias cruza el fin de mes y de año", L.sumarDias("2026-12-31", 1) === "2027-01-01" && L.sumarDias("2026-03-01", -1) === "2026-02-28");
ok("fecha: formato colombiano DD/MM/AAAA", L.fechaCO("2026-11-05") === "05/11/2026");

// ================= 2. Estrato y precarga =================
ok("estrato: 9 y 99 se muestran tal cual con «código no estándar»", L.etiquetaEstrato("9") === "9 (código no estándar)" && L.etiquetaEstrato("99", true) === "99 (código no estándar)");
ok("estrato: 0 también es no estándar; 1 a 6 se muestran normales", L.etiquetaEstrato("0") === "0 (código no estándar)" && ["1", "2", "3", "4", "5", "6"].every((e) => L.etiquetaEstrato(e) === e));
ok("estrato: sin dato", L.etiquetaEstrato(null) === "Sin dato" && L.etiquetaEstrato("  ") === "Sin dato");
ok("precarga: solo dirección, barrio, estrato y uso, y la persona puede corregirlos", (() => { const b = L.conPrecarga(L.borradorVacio(), { existe: true, direccion: "CALLE 1", barrio: "NORTE", estrato: "2", uso: "RESIDENCIAL", nombre: "NO", documento: "NO" }); return b.direccion === "CALLE 1" && b.barrio === "NORTE" && b.estrato === "2" && b.uso === "RESIDENCIAL" && !("nombre" in b) && !("documento" in b); })());

// ================= 3. Hallazgos y acciones =================
{
  let b = L.borradorVacio();
  b = L.alternarHallazgo(b, cat, "conexion_directa"); b = L.alternarHallazgo(b, cat, "otro");
  ok("hallazgos: se pueden marcar varios", b.hallazgos.length === 2);
  b = L.alternarHallazgo(b, cat, "sin_irregularidad");
  ok("hallazgos: marcar «Sin irregularidad» quita los demás", igual(b.hallazgos.map((h) => h.codigo), ["sin_irregularidad"]) && L.sinIrregularidad(b, cat));
  b = L.alternarHallazgo(b, cat, "conexion_directa");
  ok("hallazgos: marcar otro quita «Sin irregularidad» (no se combinan)", igual(b.hallazgos.map((h) => h.codigo), ["conexion_directa"]) && !L.sinIrregularidad(b, cat));
  b = L.alternarHallazgo(b, cat, "conexion_directa");
  ok("hallazgos: se desmarca", b.hallazgos.length === 0);
  ok("hallazgos: un código que no está en el catálogo no hace nada", L.alternarHallazgo(b, cat, "inventado") === b);
  const a1 = cat.acciones[1];
  ok("acciones: «corte o taponamiento» solo procede con el hallazgo que la habilita", !L.accionDisponible(a1, L.borradorVacio(), cat) && L.accionDisponible(a1, L.alternarHallazgo(L.borradorVacio(), cat, "reconexion_no_autorizada"), cat));
  ok("acciones: una acción sin habilitador está disponible con cualquier hallazgo", L.accionDisponible(cat.acciones[0], L.alternarHallazgo(L.borradorVacio(), cat, "conexion_directa"), cat));
  ok("acciones: con «Sin irregularidad» ninguna está disponible", !L.accionDisponible(cat.acciones[0], L.alternarHallazgo(L.borradorVacio(), cat, "sin_irregularidad"), cat));
  let c = L.alternarHallazgo(L.borradorVacio(), cat, "reconexion_no_autorizada"); c = { ...c, acciones: [{ codigo: "corte_taponamiento", detalle: { realizado_a_las: "10:30" } }] };
  c = L.alternarHallazgo(c, cat, "reconexion_no_autorizada"); c = L.alternarHallazgo(c, cat, "conexion_directa");
  ok("acciones: al desmarcar el hallazgo que la habilitaba, la acción se depura", L.depurarAcciones(c, cat).acciones.length === 0);
  const d = { ...L.alternarHallazgo(L.borradorVacio(), cat, "conexion_directa"), acciones: [{ codigo: "retiro_medidor", detalle: {} }] };
  ok("acciones: depurar no toca las acciones que siguen disponibles (mismo objeto)", L.depurarAcciones(d, cat) === d);
  ok("marcar «Sin irregularidad» limpia las acciones ya elegidas", L.alternarHallazgo({ ...d }, cat, "sin_irregularidad").acciones.length === 0);
}

// ================= 4. Números =================
ok("número: coma decimal, punto decimal y miles", L.numeroCO("120,5") === 120.5 && L.numeroCO("120.5") === 120.5 && L.numeroCO("1.234,5") === 1234.5 && L.numeroCO("0") === 0);
ok("número: vacío o texto → null", L.numeroCO("") === null && L.numeroCO("abc") === null && L.numeroCO("12a") === null && L.numeroCO("1,2,3") === null);

// ================= 5. Contadores y orden de fotos =================
{
  const b = bien();
  let c = L.contadores(b, fotos("fachada", "acta_fisica"), cat);
  ok("fotos: con irregularidad el mínimo es 2 y faltan tipos obligatorios (hallazgo)", c.conIrregularidad && c.minHallazgo === 2 && c.maxHallazgo === 10 && igual(c.tiposFaltantes, ["Hallazgo"]) && c.hallazgo === 1 && c.papel === 1);
  c = L.contadores({ ...b, hallazgos: [{ codigo: "sin_irregularidad", texto: "" }] }, fotos("fachada"), cat);
  ok("fotos: sin irregularidad el mínimo baja a 1 y no se exigen tipos", !c.conIrregularidad && c.minHallazgo === 1 && c.tiposFaltantes.length === 0);
  c = L.contadores({ ...b, papelPendiente: true }, FB, cat);
  ok("fotos: con «papel pendiente» el papel es 0 a 0", c.minPapel === 0 && c.maxPapel === 0);
  c = L.contadores(b, FB, cat);
  ok("fotos: papel de 1 a 2 y las fotos del papel no cuentan como del hallazgo", c.minPapel === 1 && c.maxPapel === 2 && c.hallazgo === 2 && c.papel === 1);
  const o = L.ordenarFotos([{ tipo: "acta_fisica", n: 1 }, { tipo: "fachada", n: 2 }, { tipo: "hallazgo", n: 3 }, { tipo: "acta_fisica", n: 4 }, { tipo: "medidor", n: 5 }], cat);
  ok("orden: primero las del hallazgo en el orden tomado y después las del papel, contiguos desde 1", igual(o.map((f) => [f.orden, f.n]), [[1, 2], [2, 3], [3, 5], [4, 1], [5, 4]]));
}

// ================= 6. Reglas del servidor anticipadas (faltas) =================
const falta = (b, f = FB, c = cat) => L.faltas(b, f, c, AHORA);
ok("faltas: un acta completa no tiene faltas", igual(falta(bien()), []), falta(bien()).join(" | "));
ok("faltas: un borrador vacío trae faltas (nada se envía sin completar)", falta(L.borradorVacio(), []).length >= 8);
{
  const caso = (n, b, frag, f) => { const m = falta(b, f); ok(`faltas: ${n}`, m.some((x) => x.includes(frag)), m.join(" | ")); };
  caso("con contrato sin número", { ...bien(), contrato: "" }, "Indique el contrato");
  caso("contrato con caracteres no válidos", { ...bien(), contrato: "12 34!" }, "solo puede llevar letras, números y guiones");
  caso("contrato de más de 20 caracteres", { ...bien(), contrato: "1".repeat(21) }, "solo puede llevar letras, números y guiones");
  ok("faltas: sin contrato no se pide número de contrato", falta({ ...bien(), modo: "sin_contrato", contrato: "" }).length === 0);
  caso("dirección corta", { ...bien(), direccion: "ab" }, "dirección");
  caso("sin barrio", { ...bien(), barrio: "  " }, "barrio");
  caso("no se sabe si tiene medidor", { ...bien(), tieneMedidor: null }, "tiene medidor");
  caso("con medidor sin estado", { ...bien(), estadoMedidor: "" }, "estado del medidor");
  caso("lectura fuera de rango", { ...bien(), lectura: "100000000" }, "lectura");
  caso("lectura que no es número", { ...bien(), lectura: "abc" }, "lectura");
  ok("faltas: sin medidor no se piden sus datos", falta({ ...bien(), tieneMedidor: false, estadoMedidor: "", lectura: "" }).length === 0);
  caso("sin hallazgos", { ...bien(), hallazgos: [] }, "al menos un hallazgo");
  caso("«Otro» sin texto", { ...bien(), hallazgos: [{ codigo: "otro", texto: "" }] }, "exige describirlo");
  caso("descripción corta con irregularidad", { ...bien(), descripcion: "corto" }, "mínimo 10");
  ok("faltas: «Sin irregularidad» no exige descripción ni acciones", falta({ ...bien(), hallazgos: [{ codigo: "sin_irregularidad", texto: "" }], descripcion: "" }, fotos("fachada", "acta_fisica")).length === 0);
  caso("acción sin su campo obligatorio", { ...bien(), acciones: [{ codigo: "retiro_medidor", detalle: { serie_retirada: "S1" } }] }, "falta «Lectura»");
  caso("acción con número mal escrito", { ...bien(), acciones: [{ codigo: "retiro_medidor", detalle: { serie_retirada: "S1", lectura_retiro: "x" } }] }, "debe ser un número");
  caso("acción con hora mal escrita", { ...bien(), hallazgos: [{ codigo: "reconexion_no_autorizada", texto: "" }], acciones: [{ codigo: "corte_taponamiento", detalle: { realizado_a_las: "25:99" } }] }, "HH:MM");
  ok("faltas: acción completa", falta({ ...bien(), acciones: [{ codigo: "retiro_medidor", detalle: { serie_retirada: "S1", lectura_retiro: "10,5" } }] }).length === 0);
  caso("no se sabe si alguien atendió", { ...bien(), nadieAtendio: null }, "alguien atendió");
  caso("no se sabe si el operario firmó", { ...bien(), firmoOperario: null }, "operario firmó");
  caso("atendió pero sin nombre", { ...bien(), atNombre: "" }, "nombre de quien atendió");
  caso("atendió pero sin calidad", { ...bien(), atCalidad: "" }, "calidad");
  caso("calidad «Otro» sin texto", { ...bien(), atCalidad: "otro" }, "exige describirlo");
  caso("atendió, no se negó y no consta que firmó", { ...bien(), firmoAtendiente: false }, "firmó el acta física, o que se negó");
  caso("se negó sin constancia ni testigo", { ...bien(), seNego: true, firmoAtendiente: false }, "constancia del operario");
  caso("se negó sin testigo", { ...bien(), seNego: true, firmoAtendiente: false, constancia: "Se negó a firmar el acta" }, "nombre del testigo");
  ok("faltas: se negó con constancia y testigo", falta({ ...bien(), seNego: true, firmoAtendiente: false, constancia: "Se negó a firmar el acta", testigo: "Testigo Prueba" }).length === 0);
  caso("se negó y consta que firmó", { ...bien(), seNego: true, firmoAtendiente: true, constancia: "Se negó a firmar el acta", testigo: "T Prueba" }, "no puede constar que firmó");
  caso("nadie atendió sin constancia", { ...bien(), nadieAtendio: true }, "constancia del operario");
  ok("faltas: nadie atendió con constancia (sin atendiente)", falta({ ...bien(), nadieAtendio: true, atNombre: "", atCalidad: "", firmoAtendiente: null, constancia: "Nadie abrió la puerta" }).length === 0);
  caso("nadie atendió y se negó a la vez", { ...bien(), nadieAtendio: true, seNego: true, constancia: "Nadie abrió la puerta" }, "a la vez");
  caso("el operario no firmó sin motivo", { ...bien(), firmoOperario: false }, "operario no firmó");
  ok("faltas: el operario no firmó con motivo", falta({ ...bien(), firmoOperario: false, constancia: "No alcanzó a firmar el acta" }).length === 0);
  caso("fecha del papel de hace 40 días", { ...bien(), fechaFisica: L.sumarDias(hoy, -40) }, "anterior a 30 días");
  caso("fecha del papel futura", { ...bien(), fechaFisica: L.sumarDias(hoy, 2) }, "futura");
  caso("fecha del papel vacía", { ...bien(), fechaFisica: "" }, "fecha del acta física");
  caso("una sola foto del hallazgo con irregularidad", bien(), "al menos 2 fotos del hallazgo", fotos("fachada", "acta_fisica"));
  caso("falta un tipo obligatorio", bien(), "Faltan fotos obligatorias: Hallazgo", fotos("fachada", "medidor", "acta_fisica"));
  caso("11 fotos del hallazgo", bien(), "Máximo 10 fotos del hallazgo", [...fotos("fachada", "hallazgo", "acta_fisica"), ...fotos(...Array(9).fill("medidor"))]);
  caso("sin foto del papel y sin papel pendiente", bien(), "Falta la foto del acta física", fotos("fachada", "hallazgo"));
  ok("faltas: con «papel pendiente» y sin foto del papel se puede enviar", falta({ ...bien(), papelPendiente: true }, fotos("fachada", "hallazgo")).length === 0);
  caso("«papel pendiente» con foto del papel", { ...bien(), papelPendiente: true }, "Quite la marca", FB);
  caso("tres fotos del papel", bien(), "Máximo 2 fotos del acta física", [...FB, ...fotos("acta_fisica", "acta_fisica")]);
  ok("faltas: el número del acta física es opcional (no genera falta)", falta({ ...bien(), numeroFisico: "" }).length === 0);
}

// ================= 7. Contenido que se registra =================
{
  const c = L.construirContenido({ ...bien(), numeroFisico: " A-123 ", referencia: "", acciones: [{ codigo: "retiro_medidor", detalle: { serie_retirada: "S1", lectura_retiro: "10,5" } }], derechosInformados: true }, FB, cat);
  ok("contenido: modo y contrato", c.modo_identificacion === "con_contrato" && c.contrato === "123456");
  ok("contenido: lo vacío no se envía y lo escrito va sin espacios", !("referencia_ubicacion" in c) && c.numero_acta_fisica === "A-123");
  ok("contenido: lectura como número y medidor", c.lectura_m3 === 120.5 && c.tiene_medidor === true && c.estado_medidor === "funcionando");
  ok("contenido: hallazgos con su código y acciones con detalle tipado (número como número)", igual(c.hallazgos, [{ codigo: "conexion_directa" }]) && igual(c.acciones, [{ codigo: "retiro_medidor", detalle: { serie_retirada: "S1", lectura_retiro: 10.5 } }]));
  ok("contenido: firmas como hechos declarados (booleanos) y atendiente", c.firmo_operario === true && c.firmo_atendiente === true && c.se_nego_a_firmar === false && c.nadie_atendio === false && igual(c.atendiente, { nombre: "Persona Prueba", calidad: "propietario" }) && c.derechos_informados === true);
  ok("contenido: fotos con orden contiguo y tipo; el papel al final; SIN ruta, hora ni autor", igual(c.fotos, [{ orden: 1, tipo: "fachada" }, { orden: 2, tipo: "hallazgo" }, { orden: 3, tipo: "acta_fisica" }]) && !JSON.stringify(c).includes("ruta"));
  ok("contenido: ninguna clave prohibida por el servidor (usuario, email, autor, solicitante, hora) y la única fecha es la del papel", Object.keys(c).every((k) => !/(^usuario$|^email$|^autor$|^solicitante$|hora)/i.test(k) && (!/fecha/i.test(k) || k === "fecha_acta_fisica")));
  ok("contenido: ningún dato de firma digital (sin imágenes ni lienzos)", !/firma_imagen|lienzo|pdf|data:image/i.test(JSON.stringify(c)));
  const s = L.construirContenido({ ...bien(), modo: "sin_contrato", contrato: "999" }, FB, cat);
  ok("contenido: «sin contrato» NO envía el contrato aunque haya texto", s.modo_identificacion === "sin_contrato" && !("contrato" in s));
  const nm = L.construirContenido({ ...bien(), tieneMedidor: false, medidorSerie: "X", marca: "Y", lectura: "5", estadoMedidor: "funcionando" }, FB, cat);
  ok("contenido: sin medidor se quitan los datos del medidor", nm.tiene_medidor === false && !("medidor_serie" in nm) && !("marca" in nm) && !("lectura_m3" in nm) && !("estado_medidor" in nm));
  const na = L.construirContenido({ ...bien(), nadieAtendio: true, atNombre: "X", atCalidad: "propietario", firmoAtendiente: true, constancia: "Nadie abrió la puerta", testigo: "T Prueba" }, FB, cat);
  ok("contenido: si nadie atendió no hay atendiente ni firma del atendiente; el testigo sí consta", na.nadie_atendio === true && !("atendiente" in na) && na.firmo_atendiente === false && igual(na.testigo, { nombre: "T Prueba" }));
  const ng = L.construirContenido({ ...bien(), seNego: true, firmoAtendiente: true, constancia: "Se negó a firmar el acta", testigo: "T Prueba" }, FB, cat);
  ok("contenido: si se negó, firmo_atendiente va en falso aunque haya quedado marcado", ng.se_nego_a_firmar === true && ng.firmo_atendiente === false);
  const ot = L.construirContenido({ ...bien(), hallazgos: [{ codigo: "otro", texto: " Algo raro " }], atCalidad: "otro", atCalidadTexto: "Vecino" }, FB, cat);
  ok("contenido: «Otro» lleva su texto y la calidad «Otro» su descripción", igual(ot.hallazgos, [{ codigo: "otro", texto_otro: "Algo raro" }]) && ot.atendiente.calidad_texto === "Vecino");
  const si = L.construirContenido({ ...bien(), hallazgos: [{ codigo: "sin_irregularidad", texto: "" }], acciones: [{ codigo: "retiro_medidor", detalle: {} }], descripcion: "" }, fotos("fachada", "acta_fisica"), cat);
  ok("contenido: «Sin irregularidad» no envía acciones", !("acciones" in si) && !("descripcion_hallazgos" in si));
  ok("contenido: con «papel pendiente» va la marca y no va foto del papel", L.construirContenido({ ...bien(), papelPendiente: true }, fotos("fachada", "hallazgo"), cat).papel_pendiente === true);
  ok("contenido: un acta completa (sin faltas) arma un contenido que cumple el contrato de 31 claves", Object.keys(c).every((k) => ["modo_identificacion", "contrato", "direccion", "barrio", "estrato", "uso", "referencia_ubicacion", "tiene_medidor", "medidor_serie", "marca", "lectura_m3", "estado_medidor", "estado_sellos", "serie_sellos", "diametro", "descripcion_hallazgos", "hallazgos", "acciones", "nadie_atendio", "derechos_informados", "atendiente", "testigo", "firmo_operario", "firmo_atendiente", "se_nego_a_firmar", "numero_acta_fisica", "fecha_acta_fisica", "papel_pendiente", "constancia_operario", "observaciones", "fotos"].includes(k)));
}

// ================= 8. Lista «Mis actas» =================
{
  const f = (o) => ({ acta_id: "a", consecutivo: "AI-2026-000001", situacion: "registrada", abierto_en: "x", vence_en: "y", registrado_en: "z", estado: "reportado", estado_nombre: "Reportado", modo_identificacion: "con_contrato", contrato: "123", papel_pendiente: false, fotos_papel: 1, tiene_foto_papel: true, max_fotos_papel: 2, puede_adjuntar_papel: false, siguiente_orden_foto: 3, ...o });
  ok("lista: una apertura vigente se puede retomar", L.accionDeFila(f({ situacion: "abierta_en_curso" })) === "continuar");
  ok("lista: una apertura caducada ya no se registra", L.accionDeFila(f({ situacion: "abierta_vencida" })) === "ninguna");
  ok("lista: un acta con papel pendiente permite adjuntar la foto", L.accionDeFila(f({ papel_pendiente: true, tiene_foto_papel: false, puede_adjuntar_papel: true })) === "adjuntar_papel");
  ok("lista: un acta registrada normal no tiene acción", L.accionDeFila(f({})) === "ninguna");
  ok("lista: un acta corregida por la supervisión ya no admite foto del papel", L.accionDeFila(f({ papel_pendiente: true, puede_adjuntar_papel: false })) === "ninguna");
  ok("textos: situación y contrato", L.textoSituacion(f({ situacion: "abierta_en_curso" })) === "Abierta: falta registrarla" && L.textoSituacion(f({ situacion: "abierta_vencida" })) === "Caducó sin registrarse"
    && /falta la foto del papel/.test(L.textoSituacion(f({ papel_pendiente: true, tiene_foto_papel: false }))) && L.textoSituacion(f({})) === "Registrada · Reportado"
    && L.textoContrato(f({})) === "Contrato 123" && L.textoContrato(f({ modo_identificacion: "sin_contrato", contrato: null })) === "Sin contrato" && L.textoContrato(f({ modo_identificacion: null, contrato: null })) === "Contrato por indicar");
  ok("textos: el aviso del consecutivo abierto y el texto fijo del papel dicen lo que deben", /abandona sin registrarlo/.test(L.AVISO_CONSECUTIVO_ABIERTO) && /conciliación/.test(L.AVISO_CONSECUTIVO_ABIERTO)
    && /documento con valor probatorio/.test(L.TEXTO_PAPEL) && /no la reemplaza ni la firma/.test(L.TEXTO_PAPEL));
  ok("textos: ningún texto sugiere firma digital ni PDF", !/(firma digital|firmado digital|firmar en pantalla|\bPDF\b)/i.test(L.AVISO_CONSECUTIVO_ABIERTO + L.TEXTO_PAPEL));
  ok("precisión: avisa si pasa de 30 m o no se conoce", L.avisoPrecision(45) !== null && L.avisoPrecision(10) === null && L.avisoPrecision(null) !== null && L.avisoPrecision(NaN) !== null);
}

// ================= 9. Cliente de API (fetch simulado) =================
{
  sim({ s: 200, cuerpo: { filas: [], hay_mas: false, max_filas: 50 } });
  const r = await A.apiActa.misActas();
  ok("api: mis_actas es un GET a la ruta correcta, con el token y sin cuerpo", llamadas[0].url === "http://sim.local/functions/v1/geoportal-acta?accion=mis_actas" && llamadas[0].init.method === "GET" && llamadas[0].init.headers.Authorization === "Bearer tok-falso" && llamadas[0].init.body === undefined && r.max_filas === 50);
  sim({ s: 200, cuerpo: { existe: true } }); await A.apiActa.precargar("123456");
  ok("api: precargar es POST con el contrato", llamadas[0].url.endsWith("accion=precargar") && llamadas[0].init.method === "POST" && igual(JSON.parse(llamadas[0].init.body), { contrato: "123456" }) && llamadas[0].init.headers["Content-Type"] === "application/json");
  sim({ s: 200, cuerpo: {} }); await A.apiActa.abrir(10.46, -73.25, 8);
  ok("api: abrir manda solo la coordenada y la precisión (nunca el contrato, autor, fecha ni consecutivo)", igual(JSON.parse(llamadas[0].init.body), { lat: 10.46, lon: -73.25, precision_m: 8 }));
  sim({ s: 200, cuerpo: {} }); await A.apiActa.abrir(10.46, -73.25, null);
  ok("api: abrir sin precisión no manda la clave", igual(JSON.parse(llamadas[0].init.body), { lat: 10.46, lon: -73.25 }));
  sim({ s: 200, cuerpo: {} }); await A.apiActa.prepararSubida("id1", [{ orden: 1, tipo: "fachada" }]); await Promise.resolve();
  ok("api: preparar_subida manda el acta y las fotos {orden, tipo} (sin rutas)", igual(JSON.parse(llamadas[0].init.body), { acta_id: "id1", fotos: [{ orden: 1, tipo: "fachada" }] }));
  sim({ s: 200, cuerpo: {} }); await A.apiActa.registrar("id1", { modo_identificacion: "sin_contrato" });
  ok("api: registrar manda {acta_id, contenido}", igual(JSON.parse(llamadas[0].init.body), { acta_id: "id1", contenido: { modo_identificacion: "sin_contrato" } }));
  sim({ s: 200, cuerpo: {} }); await A.apiActa.fotoPapel("id1", 4);
  ok("api: foto_papel manda {acta_id, orden}", igual(JSON.parse(llamadas[0].init.body), { acta_id: "id1", orden: 4 }));
  sim({ s: 200, cuerpo: {} }); await A.apiActa.prediosCercanos(10.4, -73.2); sim({ s: 200, cuerpo: {} }); await A.apiActa.formulario();
  ok("api: predios_cercanos (POST) y formulario (GET)", llamadas[0].url.endsWith("accion=formulario") && llamadas[0].init.method === "GET");
  const usadas = new Set(["mis_actas", "precargar", "abrir", "preparar_subida", "registrar", "foto_papel", "predios_cercanos", "formulario", "motivos_cancelacion", "cancelar", "aperturas_sin_registrar"]);
  const fuente = readFileSync(join(aqui, "../src/campo/acta/apiActa.ts"), "utf8");
  const rutasEnCodigo = [...fuente.matchAll(/(?:pedir<[^>]*>\()"([a-z_]+)"/g)].map((m) => m[1]);
  ok("api: solo se usan las 8 rutas de captura y las 3 de cancelar; no hay vincular_reporte, actas_de_reporte ni las rutas del tablero de supervisión", rutasEnCodigo.length === 11 && rutasEnCodigo.every((r) => usadas.has(r)) && !/pedir<[^>]*>\("(vincular_reporte|vincular_contrato|actas_de_reporte|actas|acta|foto|estado|ocultar|reincluir|custodia|corregir|conciliacion|cercanas|catalogo)"/.test(fuente));
  // errores
  sim({ s: 403, cuerpo: { error: "No tiene permiso para esta acción." } });
  let x = await intenta(() => A.apiActa.misActas());
  ok("api: 403 con texto fijo → error de permiso", x.e instanceof ErrorCampo && x.e.tipo === "permiso" && x.e.status === 403);
  sim({ s: 429, cuerpo: { error: "Alcanzó el máximo de registros por hora. Vuelva a intentarlo en 7 minutos" } });
  x = await intenta(() => A.apiActa.abrir(1, 1, null));
  ok("api: 429 → «limite» con el mensaje de la base", x.e.tipo === "limite" && /7 minutos/.test(x.e.message));
  sim({ s: 400, cuerpo: { error: "Ese contrato no existe: corríjalo o registre el predio como «sin contrato»" } });
  x = await intenta(() => A.apiActa.registrar("a", {}));
  ok("api: 400 → «validacion» con el mensaje para la persona", x.e.tipo === "validacion" && /Ese contrato no existe/.test(x.e.message));
  sim({ s: 409, cuerpo: { error: "La foto 3 del acta física ya existe. Si faltan páginas, suba la siguiente (foto 4)." } });
  x = await intenta(() => A.apiActa.fotoPapel("a", 3));
  ok("api: 409 «ya existe» llega tal cual para mostrarlo", /ya existe/.test(x.e.message) && x.e.status === 409);
  sim({ s: 404, cuerpo: { code: "NOT_FOUND", message: "Requested function was not found" } });
  x = await intenta(() => A.apiActa.formulario());
  ok("api: Edge sin desplegar (404 de la pasarela, sin campo error) → «aún no está disponible», sin texto crudo", x.e.tipo === "servidor" && x.e.message === "El registro de actas aún no está disponible. Intente más tarde." && !/Requested/.test(x.e.message));
  sim({ s: 404, cuerpo: { error: "No hay un tipo de foto activo para el acta física" } });
  x = await intenta(() => A.apiActa.prepararSubida("a", [{ orden: 1, tipo: "x" }]));
  ok("api: un 404 CON error de la Edge es de la base y conserva su mensaje", /tipo de foto activo/.test(x.e.message) && x.e.message !== "El registro de actas aún no está disponible. Intente más tarde.");
  sim({ s: 500, cuerpo: { error: "No se pudo completar la operación." } });
  x = await intenta(() => A.apiActa.misActas());
  ok("api: 500 → «servidor»", x.e.tipo === "servidor");
  sim("RED");
  x = await intenta(() => A.apiActa.abrir(1, 1, null));
  ok("api: sin red → «red» (el abrir pudo o no haber llegado)", x.e.tipo === "red");
  sim({ s: 200, cuerpo: "no es json" });
  x = await intenta(() => A.apiActa.misActas());
  ok("api: 200 sin JSON → «red» (no se puede confirmar)", x.e.tipo === "red");
  globalThis.__sesion = false; sim({ s: 200, cuerpo: {} });
  x = await intenta(() => A.apiActa.misActas());
  ok("api: sin sesión → error de sesión y no se llama a la red", x.e.tipo === "sesion" && llamadas.length === 0); globalThis.__sesion = true;
  globalThis.__refrescos = 0; sim({ s: 401, cuerpo: { error: "x" } }, { s: 200, cuerpo: { filas: [], hay_mas: false, max_filas: 50 } });
  x = await intenta(() => A.apiActa.misActas());
  ok("api: un 401 renueva la sesión UNA vez y repite la misma petición", x.v?.max_filas === 50 && globalThis.__refrescos === 1 && llamadas.length === 2);
  globalThis.__refrescos = 0; globalThis.__refrescoFalla = true; sim({ s: 401, cuerpo: { error: "x" } });
  x = await intenta(() => A.apiActa.misActas());
  ok("api: si la renovación falla, error de sesión", x.e.tipo === "sesion"); globalThis.__refrescoFalla = false;
  ok("api: ninguna petición lleva la clave de servicio ni cuerpos en la URL", llamadas.every((l) => !l.url.includes("body") && !/service/i.test(JSON.stringify(l.init.headers ?? {}))));

  // subida de fotos (PUT directo a la URL firmada)
  const URL_F = "http://sim.local/storage/v1/object/upload/sign/acta-evidencias/x.jpg?token=T";
  const blob = new Blob([new Uint8Array(10)], { type: "image/jpeg" });
  sim({ s: 200, cuerpo: { Key: "x" } }); await A.apiActa.subirFoto(URL_F, blob);
  const pu = llamadas[0];
  ok("subida: PUT directo a la URL firmada (sin SDK), con FormData y sin sobrescribir", pu.url === URL_F && pu.init.method === "PUT" && pu.init.body instanceof FormData && pu.init.headers["x-upsert"] === "false" && !("Authorization" in pu.init.headers));
  sim({ s: 400, cuerpo: { statusCode: "409", error: "Duplicate" } }); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: una foto que ya estaba (409) cuenta como subida", x.e === undefined);
  sim({ s: 409, cuerpo: {} }); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: 409 directo también", x.e === undefined);
  sim({ s: 403, cuerpo: { message: "expired" } }); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: permiso vencido → «subida_vencida» (hay que preparar de nuevo)", x.e.tipo === "subida_vencida");
  sim({ s: 400, cuerpo: { statusCode: "400", message: "otro" } }); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: un 400 que no es duplicado → «subida_vencida»", x.e.tipo === "subida_vencida");
  sim({ s: 503, cuerpo: {} }); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: 5xx → «servidor»", x.e.tipo === "servidor");
  sim("RED"); x = await intenta(() => A.apiActa.subirFoto(URL_F, blob));
  ok("subida: sin red → «red» con mensaje claro", x.e.tipo === "red" && /revise su señal/.test(x.e.message));
}

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
