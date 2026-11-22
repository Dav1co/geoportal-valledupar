// Comercial 21-nov · Actas (pantallas del Code B; contrato (b) del Code A): firmas con el dedo (operario obligatoria; usuario y testigo opcionales), PDF único, «¿Da lugar a otras
// actividades?» con «¿Se requiere cambio de medidor?» oculto y derivado, «¿Viene de…?» (derivadas pendientes y actas de posible pérdida) y la entrada «Actas registradas».
// Chrome real (puppeteer-core) contra un servidor SIMULADO que sigue el contrato (nada llega a Supabase), a 390 y 1280 px.
//   node scripts/prueba_chrome_actas_firmas.mjs <chrome> <puppeteer-core> [capturas]
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos 55991 (servidor) y 55992 (página). No prueba: las Edges reales (cuando el Code A entregue el commit), el PDF de verdad, ni un celular físico.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_actas_firmas.mjs <chrome> <puppeteer-core> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, CAP_ARG] = args;
if (!CHROME || !PUP) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_actas_firmas")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55991;

// ---------- 1. Formatos de prueba (como los entrega el catálogo) ----------
const op = (codigo, nombre) => ({ codigo, nombre, activo: true });
const campo = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const base = { orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [], fotos_min: 0, fotos_max: 2, requiere_contrato: "si", genera_resultado: false, usa_consecutivo: true, causales: [], fotos: [] };
const REV = { ...base, codigo: "revision_previa", nombre: "Revisiones generales", campos: [
  campo("firma_atendio", "Firma de quien atendió", "opcion", { obligatorio: true, opciones: [op("atendio_firmo", "Atendió y firmó el acta"), op("atendio_se_nego", "Atendió y se negó a firmar"), op("nadie_atendio", "Nadie atendió")] }),
  campo("atendio_nombre", "Nombre de quien atendió", "texto", { sensible: true }),
  campo("req_cambio_medidor", "¿Se requiere cambio de medidor?", "si_no", { obligatorio: true }),
  campo("da_lugar", "¿Da lugar a otras actividades?", "opciones", { opciones: [op("cambio_medidor", "Cambio de medidor"), op("instalacion_medidor", "Instalación de medidor"), op("accesorios", "Instalación o cambio de accesorios"), op("reubicacion_cajilla", "Reubicación de cajilla"), op("fuga_externa", "Reparación de fuga (afuera)"), op("posible_perdida", "Posible pérdida"), op("otra", "Otra")] }),
] };
const CORTE = { ...base, codigo: "corte", nombre: "Corte", campos: [campo("observacion_corte", "Observación", "texto")] };
const INST = { ...base, codigo: "instalacion_medidor", nombre: "Instalación de medidor", campos: [campo("inst_modalidad", "Instalación o cambio", "opcion", { obligatorio: true, opciones: [op("instalacion", "Instalación"), op("cambio", "Cambio")] })] };
const LEV = { ...base, codigo: "levantamiento_acometida", nombre: "Levantamiento de la acometida", campos: [] };
const DEF = { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: false, supervisar: false, administrar_catalogo: false }, limites: { max_fotos: 2, min_fotos_campo: 0, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 }, grupos: [{ codigo: "comercial", nombre: "Comercial", orden: 1, activo: true, tipos: [REV, CORTE, INST, LEV] }] };

// ---------- 2. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_actas_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/" + rol + "/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => ({ error: null }) }) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import { FormularioFormato } from "./src/campo/formatos/FormularioFormato.tsx"; import { ActasRegistradas } from "./src/campo/documentos/ActasRegistradas.tsx";
    import * as F from "./src/campo/documentos/firmasLogica.ts";
    window.__logica = F;
    const def = ${JSON.stringify(DEF)};
    const q = new URLSearchParams(location.search), p = q.get("p");
    const tipo = def.grupos[0].tipos.find((t) => t.codigo === p);
    const nombres = new Map([["acta", "Reportar posible pérdida"], ...def.grupos[0].tipos.map((t) => [t.codigo, t.nombre])]);
    createRoot(document.getElementById("raiz")).render(<div className="com-modulo">{p === "actas"
      ? <ActasRegistradas correo="sup@emdupar.gov.co" onVolver={() => {}} nombres={nombres} puedeAperturas={q.get("rol") === "act"} puedeCerrarDerivadas={q.get("rol") !== "act"} />
      : <FormularioFormato def={def} tipo={tipo} correo="operario@emdupar.gov.co" onVolver={() => {}} onOtro={() => {}} />}</div>);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 3. Servidor simulado con el contrato (b) ----------
const FIRMAS = { operario: "obligatoria", usuario: "opcional", testigo: "opcional" };
const CATALOGO = ["acta", "tipo:revision_previa", "tipo:revision_pqr", "tipo:instalacion_medidor", "tipo:instalacion_acometida", "tipo:suspension", "tipo:corte", "tipo:reinstalacion", "tipo:reconexion_servicio"].map((formulario) => ({ formulario, lleva_pdf: true, firmas: FIRMAS }));
const RID = "11111111-2222-4333-8444-555555555555";
let est;
function reiniciar() { est = { firmas: {}, registrados: new Set(), pdfFallas: 0, pdfs: {}, cerradas: [], viejo: false }; }
reiniciar();
const fila = (n, esquema, tipo, tipo_nombre, pdf, der = { total: 0, pendientes: 0 }) => ({ registro_id: `00000000-0000-4000-8000-00000000000${n}`, esquema, tipo, tipo_nombre, consecutivo: `${tipo === "acta" ? "AI-2026" : "RPV"}-00000${n}`, numero_fisico: n === 1 ? "4521" : null,
  fecha: new Date(Date.now() - n * 3600e3).toISOString(), operario: "zt.ana@emdupar.gov.co", contrato: "123456", barrio: "Los Músicos", resultado: null, pdf: pdf ? { estado: "generado", nombre: `20261121090000-RPV-00000${n}.pdf`, version: 1 } : { estado: "pendiente", nombre: null, version: null },
  derivadas: der, firmas: { operario: true, usuario: n === 2 ? "no_firmo" : "firmo", testigo: n === 2 } });
const FILAS = [fila(1, "acta", "acta", "Reportar posible pérdida", true), fila(2, "campo", "revision_previa", "Revisiones generales", false, { total: 2, pendientes: 1 }), fila(3, "campo", "corte", "Corte", true)];
const DERIVADAS = [{ id: 41, actividad: "cambio_medidor", actividad_nombre: "Cambio de medidor", contrato: "123456", estado: "pendiente", origen: { registro_id: FILAS[1].registro_id, tipo: "revision_previa", consecutivo: "RPV-000002", fecha: FILAS[1].fecha }, atendida_por: null },
  { id: 42, actividad: "fuga_externa", actividad_nombre: "Reparación de fuga (afuera)", contrato: "123456", estado: "atendida", origen: { registro_id: FILAS[1].registro_id, tipo: "revision_previa", consecutivo: "RPV-000002", fecha: FILAS[1].fecha }, atendida_por: { registro_id: "x", tipo: "instalacion_medidor", consecutivo: "IME-000009", fecha: FILAS[0].fecha } }];
const peticiones = [];
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (c) => (cuerpo += c)); q.on("end", () => {
    const u = new URL(q.url, "http://x"), rol = u.pathname.split("/")[1], edge = u.pathname.split("/").pop(), accion = u.searchParams.get("accion");
    let b = {}; try { b = cuerpo ? JSON.parse(cuerpo) : {}; } catch { /* sin cuerpo */ }
    peticiones.push({ rol, edge, accion, cuerpo: b, en: Date.now() });
    const ok = (x) => { r.writeHead(200, cab); r.end(JSON.stringify(x)); };
    const no = (s, m) => { r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    if (edge !== "geoportal-campo" && edge !== "geoportal-acta") return no(404, "No se pudo completar la operación.");
    switch (accion) {
      case "config_constancia": return ok({ habilitado: false });
      case "documentos_catalogo": return est.viejo ? no(400, "Acción no soportada.") : ok({ formularios: CATALOGO });
      case "preparar_subida": return ok({ reporte_id: RID, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", fotos: [] });
      case "firma_guardar": {
        if (est.registrados.has(b.registro_id)) return no(409, "El registro ya está hecho: la firma es definitiva");
        if (b.estado === "firmo" && (!b.imagen || b.imagen.length < 200)) return no(400, "Falta la imagen de la firma.");
        if (b.rol === "usuario" && b.estado === "firmo" && !(b.nombre?.length >= 2)) return no(400, "Escriba el nombre de quien atendió.");
        if (b.rol === "testigo" && est.firmas[`${b.registro_id}:usuario`]?.estado !== "no_firmo") return no(400, "El testigo solo va si el usuario no firmó.");
        if (b.estado === "quitar") delete est.firmas[`${b.registro_id}:${b.rol}`]; else est.firmas[`${b.registro_id}:${b.rol}`] = b;
        return ok({ rol: b.rol, estado: b.estado, sha256: "ab".repeat(32) });
      }
      case "crear": {
        if (est.registrados.has(b.reporte_id)) return ok({ id: b.reporte_id, registrado_en: new Date().toISOString(), repetido: true, contrato_verificado: true, aviso_zona: false, consecutivo: "RPV-000010" });
        if (!est.viejo && !est.firmas[`${b.reporte_id}:operario`]) return no(400, "Falta la firma del operario");
        if (Array.isArray(b.datos?.da_lugar) && (b.datos.req_cambio_medidor === "si") !== b.datos.da_lugar.includes("cambio_medidor")) return no(400, "¿Se requiere cambio de medidor? no coincide con las actividades derivadas");
        est.registrados.add(b.reporte_id);
        return ok({ id: b.reporte_id, registrado_en: new Date().toISOString(), repetido: false, contrato_verificado: true, aviso_zona: false, consecutivo: "RPV-000010" });
      }
      case "pdf_generar": if (est.pdfFallas > 0) { est.pdfFallas--; return no(502, "No se pudo generar el PDF; intente de nuevo"); }
        est.pdfs[b.registro_id] = { nombre: "20261121184501-RPV-000010.pdf", sha256: "cd".repeat(32), bytes: 812345, version: 1, url: `http://127.0.0.1:${PUERTO + 1}/pdf/${b.registro_id}` }; return ok(est.pdfs[b.registro_id]);
      case "pdf_url": { const f = FILAS.find((x) => x.registro_id === b.registro_id); return f?.pdf.estado === "generado" || est.pdfs[b.registro_id] ? ok(est.pdfs[b.registro_id] ?? { nombre: f.pdf.nombre, sha256: "ef".repeat(32), bytes: 120000, version: 1, url: `http://127.0.0.1:${PUERTO + 1}/pdf/${b.registro_id}` }) : no(404, "Ese registro todavía no tiene PDF"); }
      case "derivadas_abiertas": return ok({ derivadas: b.formulario === "tipo:instalacion_medidor" && b.contrato === "123456" ? [DERIVADAS[0]] : [] });
      case "derivada_atender": return ok({ cambio: true });
      case "actas_abiertas": return ok({ actas: b.contrato === "123456" ? [{ acta_id: "aaaaaaaa-0000-4000-8000-000000000001", consecutivo: "AI-2026-000001", fecha: FILAS[0].fecha }] : [] });
      case "origen_vincular": return ok({ cambio: true });
      case "actas_registradas": { const f = FILAS.filter((x) => !b.tipo || x.tipo === b.tipo).filter((x) => !b.derivadas || (b.derivadas === "pendientes" ? x.derivadas.pendientes > 0 : x.derivadas.total > 0)); return ok({ filas: f, siguiente: null }); }
      case "actas_registradas_descarga": return b.despues ? ok({ filas: FILAS.slice(2), siguiente: null }) : ok({ filas: FILAS.slice(0, 2), siguiente: 2 });
      case "derivadas": return ok({ filas: DERIVADAS.filter((d) => !b.filtros?.estado || d.estado === b.filtros.estado), siguiente: null });
      case "derivada_cerrar": if (rol === "act") return no(403, "No tiene permiso para esta acción."); est.cerradas.push(b); return ok({ cambio: true });
      case "personal": return ok({ puede_editar: false, formularios: [], personas: [], puede: { cargo: false, area: false, cuadrilla: false, cuadrillas: false, actividades: false, formularios: false, catalogos: false }, actividades: [], areas: [], cuadrillas: [] });
      case "historial_personal": return ok({ eventos: [], siguiente: null });
      case "cuadrillas": return ok({ cuadrillas: [] });
      default: return no(400, "Acción no soportada.");
    }
  });
});
const estatico = http.createServer((q, r) => {
  if (q.url.startsWith("/pdf/")) { r.writeHead(200, { "content-type": "application/pdf" }); return r.end("%PDF-1.4\n%prueba\n"); }
  const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 4. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 500)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
await nav.defaultBrowserContext().overridePermissions(ORIGEN, ["geolocation"]);
let ultima = null;
async function abrir(qs, ancho) {
  const pg = await nav.newPage(); ultima = pg;
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  await pg.setGeolocation({ latitude: 10.46, longitude: -73.25, accuracy: 8 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.evaluateOnNewDocument(() => { window.__abiertos = []; window.open = (u) => { window.__abiertos.push(u); return null; }; });
  await pg.goto(`${ORIGEN}/?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(600);
  return pg;
}
const texto = (pg, sel = "body") => pg.$eval(sel, (e) => e.innerText);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : i.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const opcionMultiple = (pg, campo, nombre) => pg.evaluate((c, n) => [...document.querySelectorAll(`[aria-labelledby="fp-${c}-rot"] label`)].find((l) => l.textContent.includes(n)).querySelector("input").click(), campo, nombre);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const pide = (desde, accion) => peticiones.slice(desde).filter((p) => p.accion === accion).map((p) => p.cuerpo);
/** Firma con el dedo en el momento dedicado (FirmaPad de Aseo): unos trazos y «OK». */
async function firmar(pg, textoBoton) {
  ok(`  abre el momento dedicado con «${textoBoton}»`, await clicTexto(pg, "[data-testid=firmas] button", textoBoton));
  await pg.waitForSelector("canvas.aseo-firma-lienzo"); await esp(300);
  const caja = await pg.$eval("canvas.aseo-firma-lienzo", (c) => { const r = c.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  await pg.mouse.move(caja.x + caja.w * 0.15, caja.y + caja.h * 0.6); await pg.mouse.down();
  for (let i = 1; i <= 24; i++) await pg.mouse.move(caja.x + caja.w * (0.15 + i * 0.028), caja.y + caja.h * (0.6 - 0.25 * Math.sin(i / 3)), { steps: 2 });
  await pg.mouse.up(); await esp(150);
  await clicTexto(pg, ".aseo-firma-acc button", "OK");
  await pg.waitForFunction(() => !document.querySelector("canvas.aseo-firma-lienzo"), { timeout: 10000 }); await esp(250);
}

try {
  // Lógica pura del acta (lo que ya declara el acta de posible pérdida → estado de la firma del usuario)
  {
    const pg = await abrir("p=corte", 1280);
    const r = await pg.evaluate(() => { const F = window.__logica; const b = (o) => ({ nadieAtendio: null, seNego: null, firmoAtendiente: null, atNombre: "", testigo: "", ...o });
      return [F.fuenteDelActa(b({ nadieAtendio: true })).estado, F.fuenteDelActa(b({ nadieAtendio: false, seNego: true, testigo: "Luis" })), F.fuenteDelActa(b({ nadieAtendio: false, firmoAtendiente: true, atNombre: "Rosa" })),
        F.estadoDeFirmaAtendio("atendio_se_nego"), F.faltasFirmas({ operario: "obligatoria", usuario: "opcional", testigo: "opcional" }, F.FIRMAS_VACIAS, F.SIN_FUENTE)]; });
    ok("lógica: «nadie atendió» del acta → nadie_atendio; «se negó» → no_firmo con el testigo del acta; «firmó» → firmo con el nombre del acta; firma_atendio se_nego → no_firmo; sin nada falta la del operario",
      r[0] === "nadie_atendio" && r[1].estado === "no_firmo" && r[1].testigoNombre === "Luis" && r[2].estado === "firmo" && r[2].nombre === "Rosa" && r[3] === "no_firmo" && JSON.stringify(r[4]) === '["Falta la firma del operario."]', JSON.stringify(r));
    await pg.close();
  }
  for (const ancho of [390, 1280]) {
    reiniciar();
    // ===== Revisiones generales: firma_atendio y atendio_nombre del formulario alimentan la firma del usuario; da_lugar y req_cambio_medidor =====
    let pg = await abrir("p=revision_previa", ancho);
    await pg.waitForSelector("[data-testid=firmas]");
    ok(`[${ancho}] REV · «¿Se requiere cambio de medidor?» no se pinta y «¿Da lugar a otras actividades?» sí`, !(await pg.$("#fp-req_cambio_medidor")) && !!(await pg.$('[aria-labelledby="fp-da_lugar-rot"]')));
    let t = await texto(pg, "[data-testid=firmas]");
    ok(`[${ancho}] REV · sección «Firmas»: operario obligatoria; el estado del usuario sale de «Firma de quien atendió»`, t.includes("Operario de EMDUPAR") && t.includes("(obligatoria para registrar)") && t.includes("Responda «Firma de quien atendió» en el formulario"), t);
    ok(`[${ancho}] REV · sin la firma del operario no se puede enviar`, (await texto(pg, "[data-testid=faltas-firmas]")).includes("Falta la firma del operario.") && await pg.$eval("button.campo-enviar", (b) => b.disabled));
    await escribir(pg, "#fp-firma_atendio", "atendio_firmo"); await escribir(pg, "#fp-atendio_nombre", "Rosa Prueba"); await esp(200);
    t = await texto(pg, "[data-testid=firmas]");
    ok(`[${ancho}] REV · «Atendió y firmó» → «Firmó el usuario», con el nombre del formulario; falta su firma`, t.includes("Según «Firma de quien atendió»: Firmó el usuario") && t.includes("Firma: Rosa Prueba") && (await texto(pg, "[data-testid=faltas-firmas]")).includes("Falta la firma del usuario."), t);
    await firmar(pg, "Agregar mi firma");
    await firmar(pg, "Agregar la firma del usuario");
    ok(`[${ancho}] REV · las dos firmas quedan como miniatura con «Volver a firmar»`, await pg.$$eval("[data-testid=firmas] .doc-firma-mini img", (l) => l.length) === 2 && (await texto(pg, "[data-testid=firmas]")).includes("Volver a firmar"));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "rev_390_firmas.png"), fullPage: true });
    await escribir(pg, "#fp-contrato", "123456"); await pg.waitForSelector("[data-testid=viene-de]");
    t = await texto(pg, "[data-testid=viene-de]");
    ok(`[${ancho}] REV · «¿Viene de un reporte de posible pérdida de este contrato?» con el acta abierta (actas_abiertas)`, t.includes("AI-2026-000001"), t);
    await pg.evaluate(() => document.querySelector('input[data-acta="aaaaaaaa-0000-4000-8000-000000000001"]').click());
    await opcionMultiple(pg, "da_lugar", "Cambio de medidor"); await opcionMultiple(pg, "da_lugar", "Reparación de fuga"); await esp(200);
    ok(`[${ancho}] REV · con todo, se puede enviar`, !(await pg.$eval("button.campo-enviar", (b) => b.disabled)), await texto(pg, ".campo-faltas").catch(() => ""));
    let antes = peticiones.length;
    await pg.click("button.campo-enviar"); await pg.waitForSelector("[data-testid=pdf-registro]"); await pg.waitForFunction(() => document.querySelector("[data-testid=pdf-registro]").innerText.includes("PDF listo"), { timeout: 15000 });
    const orden = peticiones.slice(antes).map((p) => p.accion).filter((a) => ["preparar_subida", "firma_guardar", "crear", "origen_vincular", "pdf_generar"].includes(a));
    ok(`[${ancho}] REV · orden: preparar_subida → firma_guardar (operario, usuario) → crear → origen_vincular → pdf_generar`, JSON.stringify(orden) === JSON.stringify(["preparar_subida", "firma_guardar", "firma_guardar", "crear", "origen_vincular", "pdf_generar"]), JSON.stringify(orden));
    const fs = pide(antes, "firma_guardar");
    ok(`[${ancho}] REV · firma del operario (JPEG en base64, sin nombre) y del usuario con el nombre del formulario`, fs[0]?.rol === "operario" && fs[0]?.estado === "firmo" && !fs[0]?.nombre && fs[0]?.imagen?.length > 200 && fs[0]?.registro_id === RID
      && fs[1]?.rol === "usuario" && fs[1]?.estado === "firmo" && fs[1]?.nombre === "Rosa Prueba" && fs[1]?.imagen?.length > 200, JSON.stringify(fs.map((x) => ({ ...x, imagen: x.imagen?.length }))));
    const cr = pide(antes, "crear")[0];
    ok(`[${ancho}] REV · crear lleva da_lugar y req_cambio_medidor = «si» (derivado; la base lo exige)`, JSON.stringify(cr?.datos?.da_lugar) === JSON.stringify(["cambio_medidor", "fuga_externa"]) && cr?.datos?.req_cambio_medidor === "si", JSON.stringify(cr?.datos));
    ok(`[${ancho}] REV · origen_vincular con el acta elegida, después de registrar`, JSON.stringify(pide(antes, "origen_vincular")[0]) === JSON.stringify({ registro_id: RID, acta_id: "aaaaaaaa-0000-4000-8000-000000000001" }));
    t = await texto(pg, "[data-testid=pdf-registro]");
    ok(`[${ancho}] REV · «PDF listo» con su nombre y tamaño; «Descargar el PDF» abre la URL firmada`, t.includes("20261121184501-RPV-000010.pdf") && t.includes("793 KB"), t);
    await clicTexto(pg, "[data-testid=pdf-registro] button", "Descargar el PDF"); await esp(400);
    ok(`[${ancho}] REV · descargar pide pdf_url y abre la URL`, (await pg.evaluate(() => window.__abiertos.length)) === 1);
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "rev_390_guardado.png"), fullPage: true });
    await pg.close();

    // ===== Corte (SCRR): sin campos de quien atendió → la sección pregunta; el usuario no quiso firmar → testigo; el PDF falla y se reintenta =====
    reiniciar(); est.pdfFallas = 1;
    pg = await abrir("p=corte", ancho);
    await pg.waitForSelector("[data-testid=firmas] [data-estado=no_firmo]");
    ok(`[${ancho}] SCRR · la sección pregunta si el usuario firmó (tres opciones de 44 px)`, (await pg.$$eval("[data-testid=firmas] .doc-opcion", (l) => l.map((x) => x.getBoundingClientRect().height))).every((h) => h >= 44));
    await firmar(pg, "Agregar mi firma");
    await pg.evaluate(() => document.querySelector('[data-testid=firmas] [data-estado=no_firmo]').click()); await pg.waitForSelector("[data-firma=testigo]");
    await escribir(pg, "#doc-testigo-nombre", "Luis Testigo"); await esp(150);
    ok(`[${ancho}] SCRR · nombre del testigo sin firma: lo pide`, (await texto(pg, "[data-testid=faltas-firmas]")).includes("Falta la firma del testigo"));
    await firmar(pg, "Agregar la firma del testigo");
    await escribir(pg, "#fp-contrato", "123456"); await esp(300);
    antes = peticiones.length;
    await pg.click("button.campo-enviar"); await pg.waitForSelector("[data-testid=pdf-registro] [role=alert]", { timeout: 15000 });
    const f2 = pide(antes, "firma_guardar");
    ok(`[${ancho}] SCRR · firma_guardar: operario, usuario «no_firmo» (sin nombre ni imagen) y testigo con su nombre`, f2.length === 3 && f2[1].rol === "usuario" && f2[1].estado === "no_firmo" && !f2[1].imagen && !f2[1].nombre && f2[2].rol === "testigo" && f2[2].nombre === "Luis Testigo" && f2[2].imagen?.length > 200, JSON.stringify(f2.map((x) => ({ ...x, imagen: x.imagen?.length }))));
    t = await texto(pg, "[data-testid=pdf-registro]");
    ok(`[${ancho}] SCRR · si el PDF falla: el texto de la Edge, «El registro quedó guardado» y «Reintentar el PDF»`, t.includes("No se pudo generar el PDF; intente de nuevo") && t.includes("El registro quedó guardado") && t.includes("Reintentar el PDF"), t);
    await clicTexto(pg, "[data-testid=pdf-registro] button", "Reintentar el PDF"); await pg.waitForFunction(() => document.querySelector("[data-testid=pdf-registro]").innerText.includes("PDF listo"), { timeout: 10000 });
    ok(`[${ancho}] SCRR · al reintentar, el PDF queda listo`, true);
    await pg.close();

    // ===== Instalación de medidor: «¿Viene de otra actividad?» con la derivada pendiente → derivada_atender después de registrar =====
    reiniciar();
    pg = await abrir("p=instalacion_medidor", ancho);
    await pg.waitForSelector("[data-testid=firmas]"); await firmar(pg, "Agregar mi firma");
    await escribir(pg, "#fp-inst_modalidad", "cambio"); await escribir(pg, "#fp-contrato", "123456"); await pg.waitForSelector("[data-testid=viene-de] [data-derivada]");
    t = await texto(pg, "[data-testid=viene-de]");
    ok(`[${ancho}] INST · ofrece la derivada pendiente «Cambio de medidor» de RPV-000002`, t.includes("Cambio de medidor") && t.includes("RPV-000002") && t.includes("Ninguna"), t);
    await pg.evaluate(() => document.querySelector('[data-derivada="41"]').click());
    await pg.evaluate(() => document.querySelector('[data-testid=firmas] [data-estado=nadie_atendio]').click());
    est.registrados.add(RID);         // el envío anterior sí llegó y solo se perdió la respuesta: firma_guardar responde 409 «definitiva» y crear «repetido»
    antes = peticiones.length;
    await pg.click("button.campo-enviar"); await pg.waitForFunction(() => document.querySelector("[data-testid=pdf-registro]")?.innerText.includes("PDF listo"), { timeout: 15000 });
    ok(`[${ancho}] INST · derivada_atender {derivada_id 41, registro_id} después de crear`, JSON.stringify(pide(antes, "derivada_atender")[0]) === JSON.stringify({ derivada_id: 41, registro_id: RID }) && peticiones.slice(antes).findIndex((p) => p.accion === "derivada_atender") > peticiones.slice(antes).findIndex((p) => p.accion === "crear"));
    ok(`[${ancho}] INST · si ya estaba registrado: el 409 «la firma es definitiva» no traba el envío; crear responde «repetido» y sigue al PDF`, (await texto(pg, "body")).includes("ya estaba guardado") && pide(antes, "crear").length === 1 && pide(antes, "pdf_generar").length === 1);
    await pg.close();

    // ===== Un formato sin PDF (levantamiento) y un servidor anterior: sin sección de firmas, se envía como hoy =====
    reiniciar();
    pg = await abrir("p=levantamiento_acometida", ancho); await esp(500);
    ok(`[${ancho}] un formato que no lleva PDF no muestra «Firmas»`, !(await pg.$("[data-testid=firmas]")));
    await pg.close();
    reiniciar(); est.viejo = true;
    pg = await abrir("p=corte", ancho); await esp(800);
    await escribir(pg, "#fp-contrato", "123456"); await esp(300);
    ok(`[${ancho}] servidor anterior (sin documentos_catalogo): sin «Firmas» y se puede enviar`, !(await pg.$("[data-testid=firmas]")) && !(await pg.$eval("button.campo-enviar", (b) => b.disabled)));
    await pg.close();

    // ===== Actas registradas =====
    reiniciar();
    pg = await abrir("p=actas&rol=sup", ancho);
    await pg.waitForSelector("[data-testid=actas-registradas] [data-registro]"); await esp(300);
    t = await texto(pg, "[data-testid=actas-registradas]");
    ok(`[${ancho}] Actas registradas: las filas con tipo, operario, contrato, firmas y el estado del PDF; sin nombres de quien atendió ni del testigo`,
      t.includes("AI-2026-000001") && t.includes("RPV-000002") && t.includes("PDF listo") && t.includes("PDF pendiente") && t.includes("el usuario no firmó") && t.includes("2 actividades · 1 pendiente") && !t.includes("Rosa") && !t.includes("Luis"), t.slice(0, 600));
    ok(`[${ancho}] el selector «Tipo de acta» trae los 9 tipos del servidor con sus nombres`, await pg.$$eval("[data-filtro=tipo] option", (o) => o.length) === 10 && (await texto(pg, "[data-filtro=tipo]")).includes("Revisiones generales"));
    let antes2 = peticiones.length;
    await escribir(pg, "[data-filtro=tipo]", "revision_previa"); await escribir(pg, "[data-filtro=derivadas]", "pendientes"); await clicTexto(pg, "button", "Buscar"); await esp(500);
    ok(`[${ancho}] filtrar envía tipo y derivadas`, JSON.stringify(pide(antes2, "actas_registradas").at(-1)) === JSON.stringify({ tipo: "revision_previa", derivadas: "pendientes", limite: 50 }) && (await pg.$$("[data-registro]")).length === 1, JSON.stringify(pide(antes2, "actas_registradas")));
    antes2 = peticiones.length;
    await clicTexto(pg, `[data-registro="${FILAS[1].registro_id}"] button`, "Generar el PDF"); await pg.waitForFunction((id) => document.querySelector(`[data-registro="${id}"]`).innerText.includes("PDF listo"), { timeout: 10000 }, FILAS[1].registro_id);
    ok(`[${ancho}] «Generar el PDF» en una fila pendiente llama a pdf_generar con su registro`, pide(antes2, "pdf_generar")[0]?.registro_id === FILAS[1].registro_id);
    await escribir(pg, "[data-filtro=tipo]", ""); await escribir(pg, "[data-filtro=derivadas]", ""); await clicTexto(pg, "button", "Buscar"); await esp(500);
    await clicTexto(pg, `[data-registro="${FILAS[0].registro_id}"] button`, "Descargar el PDF"); await esp(400);
    ok(`[${ancho}] «Descargar el PDF» de una fila lista pide pdf_url del esquema del acta (geoportal-acta)`, peticiones.some((p) => p.accion === "pdf_url" && p.edge === "geoportal-acta" && p.cuerpo.registro_id === FILAS[0].registro_id));
    const csv = await (async () => {
      const cdp = await pg.target().createCDPSession(); await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: CAP, eventsEnabled: true });
      const hecho = new Promise((ok2) => cdp.on("Browser.downloadProgress", (e) => { if (e.state === "completed") ok2(); }));
      await clicTexto(pg, "button", "Descargar CSV"); await Promise.race([hecho, esp(8000)]); await esp(300);
      const nombre = `actas_registradas_${new Date().toISOString().slice(0, 10)}.csv`; try { return readFileSync(join(CAP, nombre), "utf8"); } catch { return ""; }
    })();
    ok(`[${ancho}] Descargar CSV: pagina la descarga (2 páginas), 3 filas, sin nombres ni firmas (solo sí/no y el estado)`, csv.split("\r\n").length === 4 && csv.includes("Consecutivo;Número físico;Tipo") && !/Rosa|Luis|imagen|base64/.test(csv) && pide(0, "actas_registradas_descarga").length >= 2, csv.slice(0, 400));
    ok(`[${ancho}] Actas registradas sin desborde horizontal`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `actas_registradas_${ancho}.png`), fullPage: ancho < 500 });
    // Actividades derivadas
    await clicTexto(pg, "button.rv-tab", "Actividades derivadas"); await pg.waitForSelector("[data-testid=derivadas] [data-derivada]"); await esp(200);
    t = await texto(pg, "[data-testid=derivadas]");
    ok(`[${ancho}] Actividades derivadas: la pendiente con su origen y «Cerrar sin formulario»`, t.includes("Cambio de medidor") && t.includes("RPV-000002") && t.includes("Pendiente") && t.includes("Cerrar sin formulario"), t);
    await clicTexto(pg, "[data-derivada] button", "Cerrar sin formulario"); await pg.waitForSelector(".rv-modal textarea");
    await escribir(pg, ".rv-modal textarea", "Se cambió el medidor en la visita del 20-nov"); await clicTexto(pg, ".rv-modal button.rv-boton", "Cerrar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal"));
    ok(`[${ancho}] cerrar una derivada: derivada_cerrar con tipo y motivo`, JSON.stringify(est.cerradas[0]) === JSON.stringify({ derivada_id: 41, tipo: "atendida_fuera", motivo: "Se cambió el medidor en la visita del 20-nov" }));
    await escribir(pg, "[data-filtro=estado]", "atendida"); await pg.waitForFunction(() => document.querySelector("[data-testid=derivadas]").innerText.includes("IME-000009"));
    ok(`[${ancho}] filtro «Atendidas»: muestra qué la atendió`, (await texto(pg, "[data-testid=derivadas]")).includes("La atendió"));
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-testid=personal]"); await esp(300);
    ok(`[${ancho}] pestaña Personal (y Cuadrillas) en solo lectura`, (await texto(pg, ".rv-cuerpo")).includes("Solo lectura.") && !!(await pg.$("[data-testid=cuadrillas]")));
    await pg.close();
    antes2 = peticiones.length;
    pg = await abrir("p=actas&rol=act", ancho);
    await pg.waitForSelector("[data-testid=actas-registradas] [data-registro]"); await esp(200);
    const tabs = await pg.$$eval("button.rv-tab", (l) => l.map((x) => x.textContent));
    ok(`[${ancho}] supervisor de actas: lee por geoportal-acta, ve «Aperturas sin registrar» y no la pestaña de derivadas (vive en geoportal-campo)`,
      peticiones.slice(antes2).some((p) => p.accion === "actas_registradas" && p.edge === "geoportal-acta") && !peticiones.slice(antes2).some((p) => p.accion === "actas_registradas" && p.edge === "geoportal-campo")
      && tabs.includes("Aperturas sin registrar") && !tabs.includes("Actividades derivadas"), JSON.stringify(tabs));
    await pg.close();
  }
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700)); if (ultima) console.log("Pantalla:", (await ultima.evaluate(() => document.body.innerText).catch(() => "")).slice(0, 900)); }
await nav.close(); srv.close(); estatico.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
