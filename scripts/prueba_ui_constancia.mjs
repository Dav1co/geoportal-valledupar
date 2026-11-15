// Prueba en Chrome REAL (sin pantalla, 380 px) de la «Constancia por correo»: los componentes verdaderos (FormularioActa, FormularioFormato, ConstanciasAdmin) montados en una página
// contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase). Comprueba qué se dibuja, el toque (≥ 44 px), la validación, el cuerpo que viaja y que NO queda nada en el navegador.
//   node scripts/prueba_ui_constancia.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas]
// No prueba: la Edge ni la base reales, ni iOS Safari / Android, ni cámara ni GPS reales (la ubicación se simula).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_constancia"));
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_ui_constancia.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 54997, URL_FN = `http://127.0.0.1:${PUERTO}/functions/v1`;

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_constancia_"));
const dobleSupabase = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "supabase-doble", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `export const FUNCTIONS_URL = "${URL_FN}"; export const DOMINIO = "@emdupar.gov.co"; export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-prueba" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [dobleSupabase],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import { FormularioActa } from "./src/campo/acta/FormularioActa.tsx"; import { almacenActa } from "./src/campo/acta/almacenActa.ts"; import * as L from "./src/campo/acta/logica.ts";
    import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx"; import { ConstanciasAdmin } from "./src/campo/constancia/ConstanciasAdmin.tsx";
    const cat = ${JSON.stringify({
      capacidades: { capturar: true, supervisar: false, administrar: false }, aviso_registro: "Este registro acompaña al acta física firmada.",
      tipos_hallazgo: [{ codigo: "sin_irregularidad", nombre: "Sin irregularidad", nota: null, exige_texto: false, excluyente: true, habilita_accion: null }],
      calidades_atendiente: [{ codigo: "propietario", nombre: "Propietario", exige_texto: false }], estados_medidor: [{ codigo: "funcionando", nombre: "Funcionando" }], estados_sellos: [{ codigo: "rotos", nombre: "Rotos" }],
      diametros: [{ codigo: "d12", nombre: "1/2 pulgada" }], acciones: [], tipos_foto: [{ codigo: "acta_fisica", nombre: "Acta física firmada", exigida_con_irregularidad: false, acta_fisica: true }],
      limites: { min_fotos_irregularidad: 0, min_fotos_sin_irregularidad: 0, max_fotos: 10, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
      zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 } })};
    const def = ${JSON.stringify({ perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: false, supervisar: false, administrar_catalogo: false }, limites: { max_fotos: 2, min_fotos_campo: 0, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 }, grupos: [] })};
    const tipoRev = ${JSON.stringify({ codigo: "revision_previa", nombre: "Revisiones generales", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [], fotos_min: 0, fotos_max: 2, requiere_contrato: "no", genera_resultado: false, usa_consecutivo: true, campos: [], fotos: [], causales: [] })};
    const tipoOtro = { ...tipoRev, codigo: "suspension", nombre: "Suspensión" };
    window.__listo = false; window.__llamadas = [];
    const q = new URLSearchParams(location.search), p = q.get("pantalla"), raiz = createRoot(document.getElementById("raiz"));
    if (p === "acta") {
      almacenActa.alAcceder("operario@emdupar.gov.co");
      almacenActa.crear({ acta_id: "00000000-0000-4000-8000-000000000001", consecutivo: "AI-2026-000123", abierto_en: "2026-11-13T20:00:00Z", vence_en: "2099-01-01T00:00:00Z", aviso_zona: false },
        { ...L.borradorVacio("sin_contrato"), direccion: "CALLE 1 # 2-3", barrio: "CENTRO", tieneMedidor: false, hallazgos: [{ codigo: "sin_irregularidad", texto: "" }], nadieAtendio: true, firmoOperario: true, firmoAtendiente: false, seNego: false,
          constancia: "No había nadie en el predio al momento de la visita.", fechaFisica: L.hoyBogota(), papelPendiente: true }, null);
      raiz.render(<FormularioActa cat={cat as any} actaId="00000000-0000-4000-8000-000000000001" correo="operario@emdupar.gov.co" onVolver={() => {}} onRegistrado={(c) => { (window as any).__confirmado = c; }} />);
    } else if (p === "formato" || p === "formato_otro") {
      raiz.render(<FormularioFormato def={def as any} tipo={(p === "formato" ? tipoRev : tipoOtro) as any} correo="operario@emdupar.gov.co" onVolver={() => {}} onOtro={() => {}} />);
    } else if (p === "admin") {
      raiz.render(<ConstanciasAdmin />);
    }
    setTimeout(() => { (window as any).__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"anon-falsa"', "import.meta.env.VITE_FUNCTIONS_URL": `"${URL_FN}"`, "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor simulado ----------
let CONFIG = { habilitado: true, texto_version: 2, texto: "Autorizo a EMDUPAR S.A. E.S.P. a tratar mi correo y mi celular únicamente para enviarme la constancia de este registro.", partes: [{ codigo: "quien_atendio", nombre: "Quien atendió la visita" }, { codigo: "suscriptor", nombre: "El suscriptor" }, { codigo: "otro", nombre: "Otra persona" }] };
let ESTADO = { texto: { version: 1, borrador: true, texto: "BORRADOR pendiente de jurídica. Autorizo a EMDUPAR a tratar mi correo." }, documentos: ["acta_inspeccion", "revision_previa", "revision_pqr", "instalacion_medidor", "instalacion_acometida"].map((d) => ({ documento: d, habilitado: false, copias_internas: [] })), cola: {}, fallos_ultimos_30_dias: 0 };
const peticiones = []; let falloConfig = false;
const srv = http.createServer((q, r) => {
  const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json" };
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  if (q.url.startsWith("/static/")) { r.writeHead(404); return r.end(); }
  let cuerpo = ""; q.on("data", (c) => (cuerpo += c)); q.on("end", () => {
    const u = new URL(q.url, "http://x"), fn = u.pathname.split("/").pop(), accion = u.searchParams.get("accion");
    let b = null; try { b = cuerpo ? JSON.parse(cuerpo) : null; } catch { /* sin cuerpo */ }
    peticiones.push({ fn, accion, tipo: u.searchParams.get("tipo"), cuerpo: b });
    const ok = (x) => { r.writeHead(200, cab); r.end(JSON.stringify(x)); };
    if (accion === "config_constancia") { if (falloConfig) { r.writeHead(500, cab); return r.end(JSON.stringify({ error: "No se pudo completar la operación." })); } return ok(CONFIG); }
    if (accion === "constancia_estado") return ok(ESTADO);
    if (accion === "constancia_config") { const f = ESTADO.documentos.find((d) => d.documento === b.documento); if (b.habilitado && ESTADO.texto.borrador) { r.writeHead(400, cab); return r.end(JSON.stringify({ error: "No se puede habilitar: el texto de autorización sigue como borrador (pendiente de jurídica)" })); } f.habilitado = b.habilitado; f.copias_internas = b.copias; return ok({ ok: true }); }
    if (accion === "constancia_texto") { ESTADO.texto = { version: ESTADO.texto.version + 1, borrador: b.borrador, texto: b.texto }; return ok({ version: ESTADO.texto.version, borrador: b.borrador }); }
    if (accion === "constancia_depurar") return ok({ envios: 3, contactos_sin_envio: 1, aplicado: !b.solo_contar });
    if (accion === "registrar") return ok({ acta_id: b.acta_id, consecutivo: "AI-2026-000123", version: 1, registrado_en: "2026-11-13T20:00:00Z", repetido: false, aviso_zona: false, ...(b.constancia ? { constancia: "reservado" } : {}) });
    if (accion === "preparar_subida") return ok({ reporte_id: "11111111-2222-4333-8444-555555555555", max_bytes_foto: 1572864, tipo_mime: "image/jpeg", fotos: [] });
    if (accion === "crear") return ok({ id: b.reporte_id, registrado_en: "2026-11-13T20:00:00Z", repetido: false, contrato_verificado: null, aviso_zona: false, consecutivo: "RPV000001", ...(b.constancia ? { constancia: "reservado" } : {}) });
    r.writeHead(404, cab); r.end(JSON.stringify({}));
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html; charset=utf-8" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--disable-gpu"] });
async function abrir(pantalla) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: 380, height: 800, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const ctx = nav.defaultBrowserContext(); await ctx.overridePermissions(`http://127.0.0.1:${PUERTO + 1}`, ["geolocation"]);
  await pg.setGeolocation({ latitude: 10.46, longitude: -73.25, accuracy: 8 });
  pg.on("pageerror", (e) => { console.log("ERROR de página:", String(e).slice(0, 200)); fallas++; total++; });
  await pg.goto(`http://127.0.0.1:${PUERTO + 1}/?pantalla=${pantalla}`);
  await pg.waitForFunction("window.__listo === true", { timeout: 10000 }); await esp(600);
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const alto = (pg, sel) => pg.evaluate((s) => { const e = document.querySelector(s); return e ? e.getBoundingClientRect().height : 0; }, sel);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const almacen = (pg) => pg.evaluate(() => JSON.stringify({ l: Object.keys(localStorage), s: Object.keys(sessionStorage) }));

try {
  // ===== Acta de inspección =====
  peticiones.length = 0;
  let pg = await abrir("acta");
  ok("acta: pidió la configuración de su documento", peticiones.some((p) => p.fn === "geoportal-acta" && p.accion === "config_constancia"));
  ok("acta: aparece la sección «Constancia por correo (opcional)»", (await texto(pg)).includes("Constancia por correo (opcional)"));
  await pg.evaluate(() => document.querySelector("details.constancia").scrollIntoView());
  await pg.click("summary.constancia-resumen"); await esp(200);
  const t1 = await texto(pg);
  ok("acta: sección abierta: casilla con la frase pedida y el texto de tratamiento", t1.includes("Autorizo a EMDUPAR a enviarme la constancia de este registro") && t1.includes("Autorizo a EMDUPAR S.A. E.S.P. a tratar mi correo"));
  ok("acta: sin la casilla no se piden correo ni celular", (await pg.$("#constancia-correo")) === null);
  ok("acta: el resumen dice que NO es el acta y que el acta física tiene valor probatorio", t1.includes("No es el acta") && t1.includes("valor probatorio"));
  await pg.screenshot({ path: join(CAP, "acta_abierta.png") });
  await pg.click(".constancia-casilla input"); await esp(200);
  ok("acta: al marcar la casilla aparecen correo, celular y «a quién va»", !!(await pg.$("#constancia-correo")) && !!(await pg.$("#constancia-celular")) && !!(await pg.$("#constancia-parte")));
  ok("acta: teclado de correo y numérico", (await pg.$eval("#constancia-correo", (e) => e.type + "|" + e.inputMode)) === "email|email" && (await pg.$eval("#constancia-celular", (e) => e.inputMode)) === "numeric");
  ok("acta: casilla y campos con alto de al menos 44 px", (await alto(pg, ".constancia-casilla")) >= 44 && (await alto(pg, "#constancia-correo")) >= 44 && (await alto(pg, "#constancia-parte")) >= 44 && (await alto(pg, "summary.constancia-resumen")) >= 44);
  ok("acta: nada se sale del ancho de 380 px", await sinDesborde(pg));
  let t2 = await texto(pg);
  ok("acta: con la casilla marcada y sin correo, falta algo y el botón queda bloqueado", t2.includes("Constancia: escriba un correo válido") && (await pg.$eval("button.campo-enviar", (e) => e.disabled)));
  await pg.type("#constancia-correo", "no-es-correo"); await pg.type("#constancia-celular", "12345"); await esp(150);
  t2 = await texto(pg);
  ok("acta: correo y celular inválidos se avisan", t2.includes("correo válido") && t2.includes("10 dígitos") && t2.includes("a quién va"));
  await pg.click("#constancia-correo", { clickCount: 3 }); await pg.type("#constancia-correo", "Titular.Prueba@Correo.Co");
  await pg.click("#constancia-celular", { clickCount: 3 }); await pg.type("#constancia-celular", "300 123 4567");
  await pg.select("#constancia-parte", "suscriptor"); await esp(200);
  ok("acta: con todo válido ya no falta nada de la constancia y el botón se habilita", !(await texto(pg)).includes("Constancia:") && !(await pg.$eval("button.campo-enviar", (e) => e.disabled)));
  await pg.evaluate(() => document.querySelector("button.campo-enviar").scrollIntoView()); await pg.screenshot({ path: join(CAP, "acta_completa.png") });
  await pg.click("button.campo-enviar"); await esp(300);
  ok("acta: la confirmación dice a qué correo se enviará la constancia", (await texto(pg)).includes("Se enviará una constancia de este registro a titular.prueba@correo.co"));
  peticiones.length = 0;
  await pg.click("button.campo-enviar"); await esp(800);
  const reg = peticiones.find((p) => p.accion === "registrar");
  ok("acta: el cuerpo de «registrar» lleva el bloque constancia normalizado y fuera de contenido", reg?.cuerpo?.constancia?.correo_titular === "titular.prueba@correo.co" && reg.cuerpo.constancia.celular_titular === "3001234567" && reg.cuerpo.constancia.parte === "suscriptor"
     && reg.cuerpo.constancia.autoriza === true && reg.cuerpo.constancia.texto_version === 2 && !JSON.stringify(reg.cuerpo.contenido).includes("titular"), JSON.stringify(reg?.cuerpo?.constancia));
  ok("acta: la pantalla recibió la confirmación (constancia: reservado)", (await pg.evaluate(() => window.__confirmado?.constancia)) === "reservado");
  ok("acta: nada se guardó en el navegador (ni localStorage ni sessionStorage)", (await almacen(pg)) === '{"l":[],"s":[]}');
  await pg.close();

  // acta sin marcar la casilla: no viaja nada
  pg = await abrir("acta"); peticiones.length = 0;
  await pg.evaluate(() => document.querySelector("button.campo-enviar").scrollIntoView());
  await pg.click("button.campo-enviar"); await esp(300); await pg.click("button.campo-enviar"); await esp(800);
  const reg2 = peticiones.find((p) => p.accion === "registrar");
  ok("acta: sin la casilla el registro viaja SIN bloque constancia", !!reg2 && !("constancia" in reg2.cuerpo));
  await pg.close();

  // documento apagado / falla la configuración: la pantalla sigue como siempre
  CONFIG = { habilitado: false };
  pg = await abrir("acta");
  ok("acta: con el documento apagado no aparece la sección", !(await texto(pg)).includes("Constancia por correo"));
  await pg.close();
  CONFIG = { habilitado: true, texto_version: 2, texto: "Autorizo a EMDUPAR a tratar mi correo (texto de prueba).", partes: [{ codigo: "suscriptor", nombre: "El suscriptor" }] }; falloConfig = true;
  pg = await abrir("acta");
  ok("acta: si la configuración falla, la sección no aparece y el formulario funciona", !(await texto(pg)).includes("Constancia por correo") && !(await pg.$eval("button.campo-enviar", (e) => e.disabled)));
  await pg.close(); falloConfig = false;

  // ===== Revisiones generales (formato de campo) =====
  peticiones.length = 0;
  pg = await abrir("formato");
  ok("formato: pidió la configuración con el tipo", peticiones.some((p) => p.fn === "geoportal-campo" && p.accion === "config_constancia" && p.tipo === "revision_previa"));
  ok("formato: aparece la sección", (await texto(pg)).includes("Constancia por correo (opcional)"));
  await pg.evaluate(() => document.querySelector("details.constancia").scrollIntoView()); await pg.click("summary.constancia-resumen"); await pg.click(".constancia-casilla input"); await esp(200);
  ok("formato: casilla marcada sin correo: falta el correo y el botón «Enviar reporte» queda bloqueado", (await texto(pg)).includes("Constancia: escriba un correo válido") && (await pg.$eval("button.campo-enviar", (e) => e.disabled)));
  ok("formato: alturas de toque y sin desborde", (await alto(pg, ".constancia-casilla")) >= 44 && (await alto(pg, "#constancia-correo")) >= 44 && await sinDesborde(pg));
  await pg.type("#constancia-correo", "titular@correo.co"); await pg.select("#constancia-parte", "suscriptor"); await esp(300);
  await pg.screenshot({ path: join(CAP, "formato_completo.png") });
  const bloqueado = await pg.$eval("button.campo-enviar", (e) => e.disabled);
  ok("formato: con la constancia completa el botón depende solo del resto del formulario", typeof bloqueado === "boolean", `(bloqueado=${bloqueado}; faltas: ${(await texto(pg)).split("\n").filter((l) => /falta|Constancia/.test(l)).join(" / ").slice(0, 200)})`);
  if (!bloqueado) {
    peticiones.length = 0; await pg.click("button.campo-enviar"); await esp(1200);
    const cr = peticiones.find((p) => p.accion === "crear");
    ok("formato: el cuerpo de «crear» lleva constancia con el reporte_id reservado", cr?.cuerpo?.constancia?.correo_titular === "titular@correo.co" && cr.cuerpo.reporte_id === "11111111-2222-4333-8444-555555555555" && cr.cuerpo.constancia.celular_titular === undefined, JSON.stringify(cr?.cuerpo?.constancia));
  } else ok("formato: el envío no se pudo comprobar (el formulario pide más cosas)", false);
  await pg.close();
  peticiones.length = 0;
  pg = await abrir("formato_otro");
  ok("formato: un tipo que no envía constancia NO pide configuración ni muestra la sección", !peticiones.some((p) => p.accion === "config_constancia") && !(await texto(pg)).includes("Constancia por correo"));
  await pg.close();

  // ===== Administración =====
  pg = await abrir("admin");
  let ta = await texto(pg);
  ok("admin: muestra el texto en BORRADOR, los 5 documentos apagados y la cola vacía", ta.includes("BORRADOR") && ["Acta de inspección técnica", "Revisiones generales", "Revisión PQR", "Instalación de medidor", "Instalación de acometida"].every((d) => ta.includes(d)) && ta.includes("Sin envíos todavía"));
  await pg.screenshot({ path: join(CAP, "admin.png"), fullPage: true });
  ok("admin: sin desborde a 380 px", await sinDesborde(pg));
  // habilitar con texto en borrador: la base lo rechaza y se muestra su mensaje
  const h0 = (await pg.$$(".constancia-doc"))[1];
  await (await h0.$("input[type=checkbox]")).click();
  await (await h0.$("textarea")).type("Sup.Actas@emdupar.gov.co\nsup.actas@emdupar.gov.co"); await esp(150);
  await (await h0.$("button.rv-boton")).click(); await esp(500);
  ok("admin: habilitar con el texto en borrador muestra el mensaje de la base", (await texto(pg)).includes("sigue como borrador"));
  // mala dirección de copia
  await (await h0.$("textarea")).type("\nno-es-correo"); await esp(150);
  ok("admin: una copia inválida se avisa y bloquea el botón", (await texto(pg)).includes("No es un correo válido: no-es-correo") && (await (await h0.$("button.rv-boton")).evaluate((e) => e.disabled)));
  // aprobar el texto
  pg.on("dialog", (d) => d.accept());
  const caja = (await pg.$$(".constancia-doc"))[0];
  await (await caja.$("textarea")).click({ clickCount: 3 }); await (await caja.$("textarea")).type("Texto aprobado por jurídica para la constancia por correo (prueba).");
  await (await caja.$("input[type=checkbox]")).click(); await esp(150);
  await (await caja.$("button.rv-boton")).click(); await esp(600);
  ok("admin: guardar el texto aprobado crea la versión 2 sin borrador", ESTADO.texto.version === 2 && ESTADO.texto.borrador === false && (await texto(pg)).includes("aprobado"));
  const dep = (await pg.$$(".constancia-doc")).at(-1);
  await (await dep.$$("button"))[0].click(); await esp(400);
  ok("admin: «ver cuántos se depurarían» solo cuenta", (await texto(pg)).includes("Por depurar hoy: 3 envíos y 1 contactos") && peticiones.filter((p) => p.accion === "constancia_depurar").at(-1)?.cuerpo?.solo_contar === true);
  ok("admin: no hay correos de titulares en pantalla", !/titular\.prueba/.test(await texto(pg)));
  await pg.close();
} finally {
  await nav.close(); srv.close(); estatico.close();
}
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
