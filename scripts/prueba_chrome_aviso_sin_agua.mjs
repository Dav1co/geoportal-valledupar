// Aviso «sin agua» en Campo (19-nov-2026) · prueba en CHROME REAL con los componentes reales (AreaCampo: Análisis de contrato, Formatos de actividad, Reportar
// anomalía y el acta «Reportar posible pérdida») contra un servidor SIMULADO en 127.0.0.1 (nada llega a Supabase). La ruta del Code A todavía no existe: se simula
// `geoportal-redes?accion=evento_contrato` con la forma acordada {en_evento, codigo, tipo, desde, regreso_estimado, alcance}.
// A 390×844 y 1280×900: el aviso sale si el predio está en un evento activo (con y sin hora de regreso), no sale si no lo está, ni si la consulta falla o tarda
// más de 2 s; no bloquea guardar ni avanzar; mientras se escribe el contrato se consulta una sola vez.
//   node scripts/prueba_chrome_aviso_sin_agua.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_aviso_sin_agua"));
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_aviso_sin_agua.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55995;      // puertos de Code B

// ---------- 1. Paquete de la página (componentes reales; doble de supabase: la URL de funciones lleva el usuario simulado) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_sinagua_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const u = new URLSearchParams(location.search).get("u") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/" + u + "/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) },
      storage: { from: () => ({ uploadToSignedUrl: async () => ({ error: null }) }) } };` }));
} };
const campo = (codigo, nombre, tipo_dato, extra = {}) => ({ codigo, nombre, tipo_dato, obligatorio: false, orden: 1, activo: true, ...extra });
const TIPO_INST = { codigo: "instalacion_medidor", nombre: "Instalación de medidor", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
  fotos_min: 0, fotos_max: 2, requiere_contrato: "opcional", genera_resultado: false, usa_consecutivo: true, causales: [], fotos: [],
  campos: [
    campo("inst_modalidad", "Instalación o cambio de medidor", "opcion", { obligatorio: true, seccion: "1. Datos básicos", opciones: [{ codigo: "instalacion", nombre: "Instalación de medidor", activo: true }, { codigo: "cambio", nombre: "Cambio de medidor", activo: true }] }),
    campo("hora_inicio", "Hora de inicio", "dia_hora", { obligatorio: true, seccion: "1. Datos básicos" }),
    campo("me_lectura", "Medidor retirado · Lectura", "decimal", { obligatorio: true, seccion: "2. Medidor retirado", visible_si: { campo: "inst_modalidad", es: "cambio" }, minimo: 0, maximo: 99999999 }),
  ] };
const DEF = (conInst = true) => ({ perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: false, supervisar: false, administrar_catalogo: false },
  limites: { max_fotos: 2, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
  grupos: [{ codigo: "danos", nombre: "Daños", orden: 1, activo: true, tipos: [{ codigo: "fuga", nombre: "Fuga visible", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] },
           { codigo: "perdidas_formatos", nombre: "Pérdidas", orden: 2, activo: true, tipos: [{ ...TIPO_INST, activo: conInst }] }] });
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaCampo } from "./src/campo/AreaCampo.tsx"; import { Admin } from "./src/components/Admin.tsx";
    const q = new URLSearchParams(location.search), u = q.get("u") || "op", r = createRoot(document.getElementById("raiz"));
    const PROPS = { op: { campo: true, acta: true, analisis: true }, sinform: { campo: true, acta: false, analisis: true }, com: { campo: false, acta: false, analisis: true }, nada: { campo: true, acta: false, analisis: false } };
    if (q.get("p") === "admin") r.render(<Admin onVolver={() => {}} />);
    else r.render(<div style={{ display: "flex", flexDirection: "column", height: "100vh" }}><AreaCampo correo="operario@emdupar.gov.co" {...PROPS[u]} /></div>);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"><style>html,body{margin:0;height:100%}</style></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Respuestas simuladas (todo inventado) ----------
const NOMBRE = "NOMBRE DE PRUEBA", TEL1 = "3000000001", TEL2 = "5700001";
const mes = (periodo, m3, extra = {}) => ({ periodo, sin_dato: false, m3, metodo: "lectura", lectura_real: true, causal: "99 LECTURA NORMAL", ...extra });
const prom = (grupo, vals) => ({ grupo, meses: vals.map(([periodo, media]) => ({ periodo, media, contratos: media === null ? 12 : 900 })) });
const COMPLETO = { encontrado: true, comodin: false, contrato: "1000001",
  suscriptor: { nombre: NOMBRE, telefonos: [TEL1, TEL2], telefono_fuente: "censo", corte: "20261114" },
  comercial: { estado: "ACTIVO", categoria: "1 Residencial", subcategoria: "2 Estrato 2", ciclo: "7", ruta: "0701", barrio: "BARRIO DE PRUEBA", direccion: "CRA 0 00 00",
    deuda_total: 412300, saldo_pendiente: 98000, facturas_pendientes: 5, saldo_financiado: 0, valor_reclamo: 0, saldo_a_favor: 0, tramo_mora: "media", estado_predio: "HABITADO", facturas_vencidas: 4, corte: "20261114" },
  medidor: { serial: "A00001", diametro: "1/2", fecha_instalacion: "2014-03-01", fecha_estado: "real", anios: 12, cambio: { confirmado: null, recodificado: null } },
  consumo: { periodo_ultimo: "202610", maximo: 11, minimo: 5, promedio: 7.8, meses_con_lectura: 4, meses: [
    mes("202605", 7), { periodo: "202606", sin_dato: true, m3: null, metodo: null, lectura_real: false, causal: null }, mes("202607", 9, { metodo: "promedio", lectura_real: false, causal: "21 PREDIO CERRADO" }),
    mes("202608", 11), mes("202609", 5), mes("202610", 6)] },
  promedios: { estrato: prom("Estrato 2", [["202605", 8.1], ["202606", 8.0], ["202607", 8.3], ["202608", 8.2], ["202609", 8.0], ["202610", 8.4]]),
    barrio: prom("BARRIO DE PRUEBA", [["202605", 7.4], ["202607", 7.9], ["202608", 7.1], ["202609", 7.3], ["202610", 7.6]]), uso: prom("Residencial", [["202605", 9.0], ["202610", 9.2]]) },
  submedicion: { marca: true, periodo: "202610", consumo: 6, referencia: 14.2, n_nuevos: 1800, estrato: "Estrato 2", anios: 12, motivo: null },
  pago: { fecha: "2026-09-18", valor: 85000, fuente: "cupones", dias: 57 },
  gestiones: { emd_facturados: [{ codigo: "600", concepto: "600- EMD CORTE DEL SERVICIO", periodo: "202608" }],
    terreno: [{ tipo: "corte", tipo_nombre: "Corte", consecutivo: "COR-000012", fecha: "2026-10-02T15:20:00-05:00", estado: "reportado" }],
    pqr: { ultima: { solicitud: "900001", fecha: "2026-09-20", causal: "1021 - COBRO POR CONSUMO", estado: "13 - Registrado", abierta: true }, abiertas: 1, ultimos_12_meses: 2, total: 3 },
    reportes: [{ consecutivo: "IME-000031", tipo: "instalacion_medidor", tipo_nombre: "Instalación de medidor", fecha: "2026-11-10T09:00:00-05:00", estado: "reportado", resultado: "efectivo" }], reportes_total: 1,
    actas: [{ consecutivo: "ACT-000004", fecha: "2026-11-02", registrado_en: "2026-11-02T10:00:00-05:00" }],
    pendientes: [{ consecutivo: "RPV-000007", tipo_nombre: "Revisiones generales", fecha: "2026-11-01T08:00:00-05:00", sugiere: "cambio_medidor" }] },
  ubicacion: { predios_total: 2, predios: [{ direccion: "CRA 0 00 00", barrio: "BARRIO DE PRUEBA", lat: 10.4631, lon: -73.2532 }, { direccion: "CL 0 00 00", barrio: "BARRIO DE PRUEBA", lat: 10.4641, lon: -73.2522 }] },
  fotos: [], cortes: { cartera: "20261114", consumo: "202610", ficha: "2026-11-14T22:10:00-05:00" }, ficha_disponible: true };
const SIN_FICHA = { ...COMPLETO, contrato: "1000003", suscriptor: { ...COMPLETO.suscriptor, telefono_fuente: "cartera" },
  medidor: { serial: "A00003", diametro: null, fecha_instalacion: null, fecha_estado: null, anios: null, cambio: null }, consumo: null, promedios: null, submedicion: null, pago: null,
  gestiones: { ...COMPLETO.gestiones, emd_facturados: null, pqr: null, pendientes: [] }, ubicacion: { predios_total: 1, predios: [{ direccion: "CRA 0 00 00", barrio: "BARRIO DE PRUEBA", lat: null, lon: null }] },
  cortes: { cartera: "20261114", consumo: null, ficha: null }, ficha_disponible: false };
const RESP = {
  "1000001": [200, COMPLETO],
  "1000002": [200, { encontrado: false, contrato: "1000002" }],
  "99999999": [200, { encontrado: true, comodin: true, contrato: "99999999" }],
  "1000003": [200, SIN_FICHA],
  "1000400": [400, { error: "Escriba solo los números del contrato (hasta 12 dígitos)." }],
  "1000403": [403, { error: "No tiene permiso para esta acción." }],
};
const usuario = (conAnalisis) => ({ email: "persona@emdupar.gov.co", nombre: "Persona Prueba", rol: "consulta", activo: true, creado_en: "2026-01-01T00:00:00Z",
  ver_explorar: true, ver_focalizacion: false, ver_comercial: true, ver_rutas: false, ver_dashboard: false, horario: "laboral", dias: "habiles",
  ver_campo: false, ver_dashboard_campo: false, ver_acta: false, ver_dashboard_acta: false, ...(conAnalisis ? { ver_analisis_contrato: false } : {}) });
const USUARIOS = { admc: usuario(true), adms: usuario(false) };


// ---------- La ruta del Code A, SIMULADA (forma acordada) y el acta ----------
const EVENTO = (regreso) => ({ en_evento: true, codigo: "EVS-000007", tipo: "suspension", desde: new Date(Date.now() - 3600000).toISOString(), regreso_estimado: regreso, alcance: "sectores" });
// contratos ENCONTRADOS en el análisis para cada caso (copias del completo, con otro número)
for (const c of ["1000009", "1000500", "1000777", "1000404"]) RESP[c] = [200, { ...COMPLETO, contrato: c }];
const ESC = { "1000001": [200, EVENTO(new Date(Date.now() + 4 * 3600000).toISOString()), 0], "1000009": [200, EVENTO(null), 0], "1000003": [200, { en_evento: false }, 0], "1000010": [200, EVENTO(null), 0], "1000002": [200, { en_evento: false }, 0],
  "1000500": [500, { error: "falla" }, 0], "1000777": [200, EVENTO(new Date(Date.now() + 3600000).toISOString()), 3000], "12345": [200, EVENTO(new Date(Date.now() + 2 * 3600000).toISOString()), 0],
  "1000404": [400, { error: "Acción no soportada." }, 0] };
function redes(accion, url, r, no) {
  if (accion !== "evento_contrato") return no(400, "Acción no soportada.");
  const x = ESC[url.searchParams.get("contrato")] ?? [200, { en_evento: false }, 0];
  setTimeout(() => { if (r.writableEnded) return; r.writeHead(x[0], cab); r.end(JSON.stringify(x[1])); }, x[2]);
}
const CAT_ACTA = { capacidades: { capturar: true, supervisar: false, administrar: false }, aviso_registro: "Registro digital.", tipos_hallazgo: [{ codigo: "otro", nombre: "Otro", nota: null, exige_texto: true, excluyente: false, habilita_accion: null }],
  calidades_atendiente: [], estados_medidor: [], estados_sellos: [], diametros: [], acciones: [], tipos_foto: [{ codigo: "fachada", nombre: "Fachada", exigida_con_irregularidad: true, acta_fisica: false }],
  limites: { min_fotos_irregularidad: 1, min_fotos_sin_irregularidad: 1, max_fotos: 4, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 } };
function acta(accion, b, ok, no) {
  switch (accion) {
    case "formulario": return ok(CAT_ACTA);
    case "mis_actas": return ok({ filas: [], hay_mas: false, max_filas: 50 });
    case "motivos_cancelacion": return ok({ motivos: [] });
    case "precargar": return ok(["12345", "1000002"].includes(b?.contrato) ? { existe: true, direccion: "CRA 0 00 00", barrio: "BARRIO DE PRUEBA", barrio_en_lista: true, estrato: "2", uso: "Residencial", predios_con_ese_contrato: 1 } : { existe: false });
    default: return no(404, "Acción no soportada.");
  }
}

const peticiones = []; let modoCercanos = "lista";
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json", "Cache-Control": "no-store" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (c) => (cuerpo += c)); q.on("end", () => {
    const url = new URL(q.url, "http://x"), partes = url.pathname.split("/"), u = partes[1], fn = partes.at(-1), accion = url.searchParams.get("accion");
    let b = null; try { b = cuerpo ? JSON.parse(cuerpo) : null; } catch { /* sin cuerpo */ }
    peticiones.push({ u, fn, accion, metodo: q.method, qs: Object.fromEntries(url.searchParams), cuerpo: b, en: Date.now() });
    const ok = (x) => { r.writeHead(200, cab); r.end(JSON.stringify(x)); };
    const no = (s, m) => { r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    if (fn === "geoportal-admin") {
      const yo = USUARIOS[u];
      if (accion === "listar") return ok({ usuarios: [yo] });
      if (accion === "permisos") {
        for (const [k, v] of Object.entries(b ?? {})) if (k !== "email" && typeof v === "boolean") { if (k === "analisis_contrato" && !("ver_analisis_contrato" in yo)) continue; yo[`ver_${k}`] = v; }
        return ok({ guardado: true });
      }
      return no(404, "Acción no soportada.");
    }
    if (fn === "geoportal-redes") return redes(accion, url, r, no);
    if (fn === "geoportal-acta") return acta(accion, b, ok, no);
    switch (accion) {
      case "formulario": return u === "com" ? no(403, "No tiene permiso para esta acción.") : ok(DEF(u !== "sinform"));
      case "config_constancia": return ok({ habilitado: false });
      case "analisis_cercanos": {
        if (modoCercanos === "429") return no(429, "Llegó al límite de 30 búsquedas de contratos cercanos de hoy. Vuelve a tener cupo a las 14:05.");
        if (modoCercanos === "400") return no(400, "La ubicación no viene en la forma esperada.");
        const lista = modoCercanos === "vacia" ? [] : [["1000001", "CRA 0 00 00", 42], ["1000005", "CL 1 00 00", 88], ["1000006", "CL 2 00 00 APTO 301 TORRE B CONJUNTO RESIDENCIAL DE PRUEBA", 140], ["1000007", null, 215], ["1000008", "CRA 9 00 00", 298]]
          .map(([contrato, direccion, distancia_m]) => ({ contrato, direccion, distancia_m }));
        return ok({ radio_m: 300, contratos: lista, cupo: { limite: 30, usadas: 3, restantes: 27, sin_limite: false } });
      }
      case "analisis_contrato": { const x = RESP[url.searchParams.get("contrato")] ?? [200, { encontrado: false, contrato: url.searchParams.get("contrato") }]; r.writeHead(x[0], cab); return r.end(JSON.stringify(x[1])); }
      default: return no(404, "Acción no soportada.");
    }
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + d}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });

const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
const consola = []; const bloqueadas = [];
let ANCHO = 390, ALTO = 844;
// Posición simulada por omisión: 0,001° al sur del predio 1 (≈ 111 m). `ctx` permite un contexto sin permiso de ubicación; `antes` corre en cada documento nuevo (dobles).
const GPS0 = { latitude: 10.4621, longitude: -73.2532, accuracy: 8 };
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${PUERTO + 1}`, ["geolocation", "accelerometer", "gyroscope", "magnetometer"]);
async function abrir(qs, { ctx = null, gps = GPS0, antes = null } = {}) {
  const pg = await (ctx ?? nav).newPage();
  if (antes) await pg.evaluateOnNewDocument(antes);
  if (gps) await pg.setGeolocation(gps);
  await pg.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  await pg.setRequestInterception(true);
  pg.on("request", (q) => { const u = q.url(); if (u.startsWith("http://127.0.0.1:") || u.startsWith("data:") || u.startsWith("blob:")) q.continue(); else { bloqueadas.push(u); q.abort(); } });   // nada sale de la máquina (ni OSM ni Supabase)
  pg.on("pageerror", (e) => { total++; fallas++; console.log("ERROR de página:", String(e).slice(0, 200)); });
  pg.on("console", (m) => consola.push(m.text()));
  await pg.goto(`${ORIGEN}/?${qs}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(500);
  return pg;
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll(".tec-pagina")].every((e) => e.scrollWidth <= e.clientWidth + 1));
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().startsWith(x) && !e.disabled); if (b) b.click(); return !!b; }, sel, t);

async function consultar(pg, contrato) {
  if (!(await pg.$("#ac-contrato"))) { await clicTexto(pg, "button.campo-formato", "Análisis de contrato"); await pg.waitForSelector("#ac-contrato", { timeout: 8000 }); }
  await pg.click("#ac-contrato", { clickCount: 3 }); await pg.keyboard.press("Backspace");
  await pg.type("#ac-contrato", contrato); await pg.keyboard.press("Enter");
  await esp(700);
}
const aviso = (pg) => pg.evaluate(() => { const a = document.querySelector("[data-testid=aviso-sin-agua]"); if (!a) return null; const s = getComputedStyle(a);
  return { txt: a.innerText.replace(/\s+/g, " ").trim(), borde: s.borderLeftColor, fondo: s.backgroundColor, dentro: a.getBoundingClientRect().right <= document.documentElement.clientWidth + 1 }; });
const consultasEvento = () => peticiones.filter((p) => p.fn === "geoportal-redes" && p.accion === "evento_contrato");
const TEXTO_HORA = /^Sin prestación del servicio en este momento\. Regreso estimado: (\d{1,2} de [a-zñ]{3,5}\.?, )?\d{1,2}:\d{2}\s?[ap]\.\s?m\. Llame al usuario y reprograme si la actividad necesita agua\.$/;
const NARANJA = "rgb(194, 94, 0)", SUAVE = "rgb(255, 244, 229)";
async function escribir(pg, sel, valor) { await pg.click(sel, { clickCount: 3 }); await pg.keyboard.press("Backspace"); await pg.type(sel, valor, { delay: 60 }); }

for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
  ANCHO = ancho; ALTO = alto; const T = `[${ancho}]`;

  // ===== A. Análisis de contrato =====
  let pg = await abrir("u=op"); await consultar(pg, "1000001");
  await pg.waitForSelector("[data-testid=aviso-sin-agua]", { timeout: 5000 }).catch(() => {});
  let a = await aviso(pg);
  ok(`${T} A1 Análisis: el contrato está en un evento activo → «Sin prestación del servicio en este momento. Regreso estimado: <hora>.» y la sugerencia de llamar y reprogramar`, !!a && TEXTO_HORA.test(a.txt), a?.txt);
  ok(`${T} A2 el aviso usa el naranja del evento (#c25e00) en el borde y su fondo suave, y no desborda`, !!a && a.borde === NARANJA && a.fondo === SUAVE && a.dentro && (await sinDesborde(pg)), JSON.stringify(a));
  ok(`${T} A3 solo informa: el resto del análisis sigue igual (tarjeta, atajos)`, !!(await pg.$("[data-testid=tarjeta]")) && (await texto(pg)).includes("Atajos con este contrato:"));
  await pg.evaluate(() => document.querySelector("[data-testid=aviso-sin-agua]")?.scrollIntoView({ block: "center" })); await esp(200);
  await pg.screenshot({ path: join(CAP, `despues_aviso_analisis_${ancho}.png`) });
  await consultar(pg, "1000003"); await esp(900);
  ok(`${T} A4 un contrato que no está en ningún evento: sin aviso`, (await aviso(pg)) === null && !!(await pg.$("[data-testid=tarjeta]")));
  await consultar(pg, "1000009"); await pg.waitForSelector("[data-testid=aviso-sin-agua]", { timeout: 5000 }).catch(() => {});
  a = await aviso(pg);
  ok(`${T} A5 en evento sin hora de regreso: «… Todavía no hay hora estimada de regreso.»`, a?.txt === "Sin prestación del servicio en este momento. Todavía no hay hora estimada de regreso. Llame al usuario y reprograme si la actividad necesita agua.", a?.txt);
  await consultar(pg, "1000500"); await esp(900);
  ok(`${T} A6 si la consulta falla (500): sin aviso y el análisis se ve normal`, (await aviso(pg)) === null && !!(await pg.$("[data-testid=tarjeta]")));
  const t0 = Date.now(); await consultar(pg, "1000777"); await pg.waitForSelector("[data-testid=tarjeta]", { timeout: 5000 }).catch(() => {}); const tarjetaMs = Date.now() - t0; await esp(3200);
  ok(`${T} A7 si la consulta tarda más de 2 s (3 s): no espera por ella (la tarjeta sale enseguida) y el aviso NO aparece ni después`, (await aviso(pg)) === null && tarjetaMs < 2000, `${tarjetaMs} ms`);
  await consultar(pg, "1000404"); await esp(900);
  ok(`${T} A8 si la ruta todavía no existe (400 «Acción no soportada»): sin aviso, sin errores`, (await aviso(pg)) === null);
  await pg.close();

  // ===== B. Formatos de actividad =====
  pg = await abrir("u=op"); await clicTexto(pg, "button.campo-formato", "Formatos de actividad"); await esp(400); await clicTexto(pg, "button.campo-formato", "Instalación de medidor"); await pg.waitForSelector("#fp-contrato");
  const botonGuardar = () => pg.evaluate(() => { const b = [...document.querySelectorAll("button")].find((x) => /^(Guardar|Revisar|Enviar)/.test(x.textContent.trim())); return b ? { txt: b.textContent.trim(), dis: b.disabled } : null; });
  const antesN = consultasEvento().length;
  await escribir(pg, "#fp-contrato", "1000002"); await esp(1200);
  const sinEvento = await botonGuardar();
  ok(`${T} B1 Formatos: mientras se escribe el contrato se consulta UNA sola vez (al terminar), y si no está en evento no hay aviso`, consultasEvento().length === antesN + 1 && (await aviso(pg)) === null, `${consultasEvento().length - antesN} consultas`);
  await escribir(pg, "#fp-contrato", "1000001"); await pg.waitForSelector("[data-testid=aviso-sin-agua]", { timeout: 5000 }).catch(() => {});
  a = await aviso(pg); const conEvento = await botonGuardar();
  ok(`${T} B2 con el contrato en un evento activo sale el aviso debajo del campo`, !!a && TEXTO_HORA.test(a.txt) && await pg.evaluate(() => !!document.querySelector("#fp-contrato").closest(".tec-campo").querySelector("[data-testid=aviso-sin-agua]")), a?.txt);
  ok(`${T} B3 no bloquea: el botón para guardar está igual que sin el aviso, y el campo sigue editable`, JSON.stringify(sinEvento) === JSON.stringify(conEvento) && !(await pg.$eval("#fp-contrato", (e) => e.disabled)), JSON.stringify([sinEvento, conEvento]));
  await pg.evaluate(() => document.querySelector("#fp-contrato").scrollIntoView({ block: "center" })); await esp(200); await pg.screenshot({ path: join(CAP, `despues_aviso_formato_${ancho}.png`) });
  await escribir(pg, "#fp-contrato", "123"); await esp(900);
  ok(`${T} B4 un contrato a medio escribir (3 dígitos) no se consulta y el aviso se quita`, (await aviso(pg)) === null && consultasEvento().every((p) => p.qs.contrato !== "123"));
  await pg.close();

  // ===== C. Reportar anomalía (reporte general) =====
  pg = await abrir("u=op"); await clicTexto(pg, "button.campo-formato", "Reportar anomalía"); await pg.waitForSelector("#campo-contrato");
  await escribir(pg, "#campo-contrato", "1000010"); await pg.waitForSelector("[data-testid=aviso-sin-agua]", { timeout: 5000 }).catch(() => {});
  a = await aviso(pg);
  ok(`${T} C1 Reportar anomalía: con el contrato en un evento sin hora, el aviso «Todavía no hay hora estimada de regreso», debajo del campo y sin desbordar`, /Todavía no hay hora estimada de regreso\./.test(a?.txt ?? "") && a.dentro && (await sinDesborde(pg)), a?.txt);
  await pg.evaluate(() => document.querySelector("#campo-contrato").scrollIntoView({ block: "center" })); await esp(200); await pg.screenshot({ path: join(CAP, `despues_aviso_reporte_${ancho}.png`) });
  await escribir(pg, "#campo-contrato", "1000777"); await esp(3500);
  ok(`${T} C2 consulta lenta (3 s): no aparece aviso y el formulario sigue normal`, (await aviso(pg)) === null && !(await pg.$eval("#campo-contrato", (e) => e.disabled)));
  await pg.close();

  // ===== D. Acta («Reportar posible pérdida») =====
  pg = await abrir("u=op"); await clicTexto(pg, "button.campo-formato", "Reportar posible pérdida"); await pg.waitForFunction(() => /Nueva acta/.test(document.body.innerText), { timeout: 8000 });
  await clicTexto(pg, "button", "Nueva acta"); await pg.waitForSelector("#acta-contrato");
  await escribir(pg, "#acta-contrato", "12345"); await esp(800);
  ok(`${T} D1 Acta: con el contrato escrito pero SIN verificar no hay aviso (se identifica al verificar)`, (await aviso(pg)) === null);
  await clicTexto(pg, "button", "Verificar"); await pg.waitForSelector("[data-testid=aviso-sin-agua]", { timeout: 5000 }).catch(() => {});
  a = await aviso(pg);
  ok(`${T} D2 al verificar un contrato que está en un evento activo: el aviso, junto a la dirección del predio`, !!a && TEXTO_HORA.test(a.txt) && /CRA 0 00 00/.test(await texto(pg)), a?.txt);
  await pg.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Abrir registro" && !b.disabled), { timeout: 8000 }).catch(() => {});
  ok(`${T} D3 no bloquea: «Abrir registro» queda habilitado igual`, await pg.evaluate(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Abrir registro" && !b.disabled)));
  await pg.evaluate(() => document.querySelector("[data-testid=aviso-sin-agua]")?.scrollIntoView({ block: "center" })); await esp(200); await pg.screenshot({ path: join(CAP, `despues_aviso_acta_${ancho}.png`) });
  await escribir(pg, "#acta-contrato", "1000002"); await clicTexto(pg, "button", "Verificar"); await esp(900);
  ok(`${T} D4 otro contrato, que no está en evento: el aviso se quita`, (await aviso(pg)) === null && /El contrato existe/.test(await texto(pg)));
  await pg.close();
}
const nombres = consola.filter((m) => /NOMBRE DE PRUEBA|3000000001/.test(m));
ok("Z1 nada personal en la consola", nombres.length === 0);
ok("Z2 ninguna petición salió de la máquina", bloqueadas.length === 0, bloqueadas.slice(0, 3).join(" "));
await nav.close(); srv.close(); estatico.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
