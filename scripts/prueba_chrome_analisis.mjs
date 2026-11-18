// Análisis de contrato · prueba en CHROME REAL (puppeteer-core + el Chrome instalado) de la pantalla nueva, con los componentes reales (AreaCampo, AnalisisContrato, FormatosCampo,
// FormularioFormato, Admin) contra un servidor SIMULADO en 127.0.0.1: nada llega a Supabase y las teselas de OpenStreetMap se bloquean. Datos INVENTADOS («NOMBRE DE PRUEBA», 3000000001).
// A 390×844 y a 1280×900: respuesta completa (marcas, teléfonos tel: con «dato personal», gráfica con el hueco de 202606 y barras huecas, tabla, secciones, mapa y Google Maps),
// no encontrado, comodín, ficha sin calcular, mensajes 400/403 (sin cupo ni 429 en la consulta de contratos), cercanía con su cupo y 429, «Buscar el predio», usuario solo comercial, atajos (submedición → Instalación de medidor con «Cambio»), sin desborde,
// nada personal en localStorage/sessionStorage ni en la consola, y la casilla de Administración solo cuando el servidor trae el booleano.
//   node scripts/prueba_chrome_analisis.mjs <ruta_chrome> <ruta_puppeteer-core> [carpeta_capturas]
// No prueba: la Edge ni la base reales, ni un celular físico, ni la llamada real (tel:) ni Google Maps.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CHROME = process.argv[2], PUP = process.argv[3], CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_analisis"));
if (!CHROME || !PUP) { console.error("Uso: node scripts/prueba_chrome_analisis.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 54991;

// ---------- 1. Paquete de la página (componentes reales; doble de supabase: la URL de funciones lleva el usuario simulado) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_analisis_"));
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
    if (fn === "geoportal-acta") return no(404, "Acción no soportada.");
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
const almacen = (pg) => pg.evaluate(() => { let s = ""; try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); s += k + "=" + localStorage.getItem(k); } for (let i = 0; i < sessionStorage.length; i++) { const k = sessionStorage.key(i); s += k + "=" + sessionStorage.getItem(k); } } catch { /* sin almacenamiento */ } return s; });
const personal = (s) => s.includes(NOMBRE) || s.includes(TEL1) || s.includes(TEL2) || s.includes("300 000 0001");

// ---------- Cercanía (agregado §1 y §2) y «Buscar el predio» (§4) ----------
const DOBLES = () => {
  window.__vib = []; window.__clearWatch = 0; window.__quitados = []; window.__agregados = [];
  navigator.vibrate = (p) => { window.__vib.push(p); return true; };
  const g = navigator.geolocation, cw = g.clearWatch.bind(g); g.clearWatch = (id) => { window.__clearWatch++; return cw(id); };
  const ae = window.addEventListener.bind(window), re = window.removeEventListener.bind(window);
  window.addEventListener = (t, f, o) => { if (/^deviceorientation/.test(t)) window.__agregados.push(t); return ae(t, f, o); };
  window.removeEventListener = (t, f, o) => { if (/^deviceorientation/.test(t)) window.__quitados.push(t); return re(t, f, o); };
};
const rumboEsperado = (a, b) => { const r = (x) => x * Math.PI / 180; const y = Math.sin(r(b.lon - a.lon)) * Math.cos(r(b.lat)); const x = Math.cos(r(a.lat)) * Math.sin(r(b.lat)) - Math.sin(r(a.lat)) * Math.cos(r(b.lat)) * Math.cos(r(b.lon - a.lon)); return ((Math.atan2(y, x) * 180 / Math.PI) + 360) % 360; };
const difAng = (a, b) => { const d = Math.abs(((a - b) % 360 + 360) % 360); return Math.min(d, 360 - d); };
const PREDIO = { lat: 10.4631, lon: -73.2532 };
async function pruebasCercania(T) {
  // ---- §1 distancia en la tarjeta ----
  let pg = await abrir("u=op"); await consultar(pg, "1000001");
  await pg.waitForSelector("[data-testid=distancia-valor]", { timeout: 8000 });
  ok(`${T} cercanía: la posición NO se envió al servidor para medir la distancia`, !peticiones.some((p) => JSON.stringify(p.cuerpo ?? {}).includes("10.4621") || JSON.stringify(p.qs).includes("10.4621")));
  await pg.evaluate(() => document.querySelector(".ac-pagina").scrollTo(0, 0));
  await pg.screenshot({ path: join(CAP, "analisis_390_distancia.png") });
  await pg.setGeolocation({ latitude: 10.4531, longitude: -73.2532, accuracy: 8 });
  await clicTexto(pg, "[data-testid=distancia] button", "Actualizar"); await esp(900);
  ok(`${T} «Actualizar» vuelve a medir: 0,01° al sur ≈ 1112 m → «A 1,1 km»`, (await pg.$eval("[data-testid=distancia-valor]", (e) => e.textContent)) === "A 1,1 km");
  await pg.setGeolocation({ latitude: 10.4621, longitude: -73.2532, accuracy: 120 });
  await clicTexto(pg, "[data-testid=distancia] button", "Actualizar"); await esp(900);
  ok(`${T} precisión 120 m: «Precisión del GPS baja (± 120 m): la distancia es aproximada.»`, (await texto(pg)).includes("Precisión del GPS baja (± 120 m): la distancia es aproximada."));
  ok(`${T} nada de la posición en localStorage/sessionStorage`, !/10\.46|73\.25/.test(await almacen(pg)));
  await pg.close();
  // ---- §2 contratos cerca de mí ----
  modoCercanos = "lista";
  pg = await abrir("u=op"); await clicTexto(pg, "button.campo-formato", "Análisis de contrato"); await pg.waitForSelector("#ac-contrato");
  let antes = peticiones.length;
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(1000);
  const pc = peticiones.slice(antes).find((p) => p.accion === "analisis_cercanos");
  ok(`${T} «Contratos cerca de mí»: POST con lat, lon y precision_m de la posición`, pc?.metodo === "POST" && pc.cuerpo?.lat === 10.4621 && pc.cuerpo?.lon === -73.2532 && pc.cuerpo?.precision_m === 8, JSON.stringify(pc?.cuerpo));
  const filas = await pg.evaluate(() => [...document.querySelectorAll(".ac-cercano")].map((b) => b.innerText.replace(/\s+/g, " ").trim()));
  const zona = await pg.$eval("[data-testid=cercanos]", (e) => e.innerText);
  ok(`${T} lista: 5 filas con contrato, dirección y distancia; «radio 300 m» y su cupo de búsquedas cercanas (sin texto de cupo de consultas)`, filas.length === 5 && filas[0].includes("1000001") && filas[0].includes("CRA 0 00 00") && filas[0].includes("42 m") && filas[3].includes("Sin dirección")
    && zona.includes("radio 300 m") && zona.includes("Le quedan 27 búsquedas cercanas hoy.") && !/cupo diario|consultas hoy/.test(zona), JSON.stringify(filas));
  ok(`${T} lista: sin nombre ni teléfono`, !personal(zona));
  ok(`${T} lista sin desborde a 390 (dirección larga incluida)`, await sinDesborde(pg));
  await pg.screenshot({ path: join(CAP, "analisis_390_cercanos.png") });
  antes = peticiones.length;
  await clicTexto(pg, ".ac-cercano", "1000001"); await esp(1000);
  const pa = peticiones.slice(antes).find((p) => p.accion === "analisis_contrato");
  ok(`${T} tocar una fila abre ese contrato con la llamada normal (analisis_contrato) y lo deja escrito`, pa?.qs.contrato === "1000001" && (await texto(pg)).includes("Contrato 1000001 · Activo") && (await pg.$eval("#ac-contrato", (i) => i.value)) === "1000001");
  modoCercanos = "vacia";
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(1000);
  ok(`${T} lista vacía: «No hay predios con contrato a menos de 300 m.»`, (await texto(pg)).includes("No hay predios con contrato a menos de 300 m."));
  modoCercanos = "429";
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(1000);
  ok(`${T} 429 de cercanos: el mensaje del servidor en un aviso`, await pg.evaluate(() => [...document.querySelectorAll("[role=alert]")].some((a) => a.textContent.includes("Llegó al límite de 30 búsquedas de contratos cercanos de hoy. Vuelve a tener cupo a las 14:05."))));
  modoCercanos = "400";
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(1000);
  ok(`${T} 400 de cercanos: «La ubicación no viene en la forma esperada.»`, (await texto(pg)).includes("La ubicación no viene en la forma esperada."));
  ok(`${T} cercanía sin desborde a 390`, await sinDesborde(pg));
  modoCercanos = "lista";
  await pg.close();
  // ---- sin permiso de ubicación ----
  const ctx = await nav.createBrowserContext();
  await ctx.overridePermissions(ORIGEN, []);
  pg = await abrir("u=op", { ctx, gps: null }); await consultar(pg, "1000001"); await esp(800);
  ok(`${T} sin permiso de ubicación: la tarjeta explica cómo activarlo y el análisis se ve completo`, (await pg.$eval("[data-testid=distancia] [data-testid=gps-ayuda]", (e) => e.textContent).catch(() => "")).includes("No tenemos permiso para usar su ubicación") && (await texto(pg)).includes("Posible submedición"));
  antes = peticiones.length;
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(800);
  ok(`${T} sin permiso: «Contratos cerca de mí» explica cómo activarlo y no llama al servidor`, (await pg.$eval("[data-testid=cercanos] [data-testid=gps-ayuda]", (e) => e.textContent).catch(() => "")).includes("Ajustes") && !peticiones.slice(antes).some((p) => p.accion === "analisis_cercanos"));
  await pg.evaluate(() => document.querySelector(".ac-pagina").scrollTo(0, 0));
  await pg.screenshot({ path: join(CAP, "analisis_390_sin_gps.png") });
  await consultar(pg, "1000002");
  ok(`${T} sin permiso: la pantalla sigue funcionando (otra consulta)`, (await texto(pg)).includes("No encontramos ese contrato."));
  ok(`${T} sin permiso sin desborde`, await sinDesborde(pg));
  await pg.close();
  // ---- §4 «Buscar el predio» ----
  const sur = (dLat, accuracy = 8) => ({ latitude: PREDIO.lat - dLat, longitude: PREDIO.lon, accuracy });
  pg = await abrir("u=op", { antes: DOBLES, gps: sur(0.0009) }); await consultar(pg, "1000001");
  await pg.waitForSelector("[data-testid=distancia-valor]", { timeout: 8000 });
  await pg.click("button.ac-boton-buscar"); await pg.waitForSelector("[data-testid=bp-distancia]", { timeout: 8000 }); await esp(400);
  const leer = () => pg.evaluate(() => ({ d: document.querySelector("[data-testid=bp-distancia]")?.textContent, banda: document.querySelector("[data-testid=buscar-predio]")?.dataset.banda, giro: Number(document.querySelector("[data-testid=flecha]")?.dataset.giro),
    fondo: getComputedStyle(document.querySelector("[data-testid=buscar-predio]")).backgroundColor, texto: document.querySelector("[data-testid=buscar-predio]")?.innerText ?? "", vib: window.__vib.length }));
  const metros = (x) => Number(String(x).replace(/[^\d]/g, ""));
  let b = await leer();
  ok(`${T} Buscar: pantalla completa con «Cerrar», 100 m en gris (lejos)`, b.d === "A 100 m" && b.banda === "lejos" && b.texto.includes("Cerrar") && await pg.evaluate(() => { const r = document.querySelector("[data-testid=buscar-predio]").getBoundingClientRect(); return r.width === innerWidth && r.height === innerHeight; }), JSON.stringify(b));
  ok(`${T} Buscar: «Precisión ± 8 m» siempre visible`, b.texto.includes("Precisión ± 8 m"));
  ok(`${T} sin brújula: aviso «sin brújula», marca N y la flecha apunta al rumbo respecto al norte (≈ 0°, «hacia el norte»)`, b.texto.includes("sin brújula") && !!(await pg.$("[data-testid=marca-norte]")) && difAng(b.giro, rumboEsperado({ lat: PREDIO.lat - 0.0009, lon: PREDIO.lon }, PREDIO)) < 1 && b.texto.includes("hacia el norte (0°)"));
  ok(`${T} Google Maps a pie`, (await pg.$eval("[data-testid=buscar-predio] a", (a) => a.getAttribute("href"))) === "https://www.google.com/maps/dir/?api=1&destination=10.4631,-73.2532&travelmode=walking" && (await pg.$eval("[data-testid=buscar-predio] a", (a) => a.target)) === "_blank");
  const fondoLejos = b.fondo;
  // un poco al oeste para que el rumbo no sea 0
  const pos2 = { latitude: PREDIO.lat - 0.0003, longitude: PREDIO.lon - 0.0002, accuracy: 8 };
  await pg.setGeolocation(pos2); await esp(900);
  b = await leer();
  const rumbo2 = rumboEsperado({ lat: pos2.latitude, lon: pos2.longitude }, PREDIO);
  ok(`${T} acercarse: la distancia baja y el color pasa a amarillo (cerca, < 50 m)`, metros(b.d) < 100 && b.banda === "cerca" && b.fondo !== fondoLejos, JSON.stringify(b));
  await pg.evaluate(() => { const e = new Event("deviceorientation"); Object.defineProperty(e, "webkitCompassHeading", { value: 90 }); window.dispatchEvent(e); }); await esp(300);
  b = await leer();
  ok(`${T} brújula de iPhone (webkitCompassHeading 90°): flecha = rumbo − rumbo del celular (±1°) y sin el aviso «sin brújula»`, difAng(b.giro, rumbo2 - 90) < 1 && !b.texto.includes("sin brújula") && !(await pg.$("[data-testid=marca-norte]")), `${b.giro} vs ${(rumbo2 - 90 + 360) % 360}`);
  await pg.evaluate(() => window.dispatchEvent(new DeviceOrientationEvent("deviceorientationabsolute", { alpha: 30, beta: 0, gamma: 0, absolute: true }))); await esp(300);
  const giroAntes = b.giro; b = await leer();
  ok(`${T} brújula absoluta (alpha 30° → rumbo 330°): la flecha gira al cambiar la orientación (±1°)`, difAng(b.giro, rumbo2 - 330) < 1 && difAng(b.giro, giroAntes) > 30, `${b.giro} vs ${(rumbo2 - 330 + 360) % 360}`);
  await pg.screenshot({ path: join(CAP, "analisis_390_buscar_predio.png") });
  await pg.setGeolocation({ ...pos2, accuracy: 60 }); await esp(900);
  ok(`${T} precisión (60 m) peor que la distancia restante: «La señal no alcanza para afinar; busque la dirección»`, (await leer()).texto.includes("La señal no alcanza para afinar; busque la dirección"));
  await pg.setGeolocation(sur(0.0001)); await esp(900);
  b = await leer();
  ok(`${T} llegar (< 15 m): verde, «Llegó: el predio debería estar a la vista» y vibra una vez`, b.banda === "llego" && b.texto.includes("Llegó: el predio debería estar a la vista") && b.vib === 1, JSON.stringify(b));
  for (const x of [0.00012, 0.00016, 0.0001]) { await pg.setGeolocation(sur(x)); await esp(700); }
  ok(`${T} temblor del GPS (13 m → 18 m → 11 m): no vuelve a vibrar`, (await leer()).vib === 1);
  await pg.setGeolocation(sur(0.0003)); await esp(800); await pg.setGeolocation(sur(0.0001)); await esp(800);
  b = await leer();
  ok(`${T} alejarse a más de 20 m y volver: vibra otra vez ([200, 100, 200])`, b.vib === 2 && JSON.stringify(await pg.evaluate(() => window.__vib[1])) === "[200,100,200]");
  ok(`${T} anuncio para lectores de pantalla (aria-live) con distancia y banda`, await pg.evaluate(() => { const a = document.querySelector("[data-testid=bp-anuncio]"); return a.getAttribute("aria-live") === "polite" && /^A \d+ m\./.test(a.textContent); }));
  ok(`${T} Buscar sin desborde`, await sinDesborde(pg));
  const cw0 = await pg.evaluate(() => window.__clearWatch);
  await clicTexto(pg, "[data-testid=buscar-predio] button", "Cerrar"); await esp(400);
  const tras = await pg.evaluate(() => ({ cw: window.__clearWatch, quitados: window.__quitados, agregados: window.__agregados, abierta: !!document.querySelector("[data-testid=buscar-predio]") }));
  ok(`${T} «Cerrar»: apaga el GPS (clearWatch) y la brújula (quita los dos oyentes) y vuelve al análisis`, tras.cw === cw0 + 1 && !tras.abierta && ["deviceorientationabsolute", "deviceorientation"].every((t) => tras.quitados.includes(t)) && (await texto(pg)).includes("Contrato 1000001"), JSON.stringify(tras));
  ok(`${T} Buscar no llamó al servidor ni guardó la posición`, !peticiones.some((p) => JSON.stringify(p.cuerpo ?? {}).includes("10.463")) && !/10\.46|73\.25/.test(await almacen(pg)));
  await pg.close();
  // ---- permiso de brújula negado (iPhone) ----
  pg = await abrir("u=op", { antes: () => { window.DeviceOrientationEvent.requestPermission = () => Promise.resolve("denied"); window.__agregados = []; const ae = window.addEventListener.bind(window); window.addEventListener = (t, f, o) => { if (/^deviceorientation/.test(t)) window.__agregados.push(t); return ae(t, f, o); }; }, gps: sur(0.0003) });
  await consultar(pg, "1000001"); await pg.waitForSelector("[data-testid=distancia-valor]", { timeout: 8000 });
  await pg.click("button.ac-boton-buscar"); await pg.waitForSelector("[data-testid=bp-distancia]", { timeout: 8000 }); await esp(400);
  await pg.evaluate(() => { const e = new Event("deviceorientation"); Object.defineProperty(e, "webkitCompassHeading", { value: 90 }); window.dispatchEvent(e); }); await esp(300);
  ok(`${T} brújula negada (iPhone): sigue con distancia y flecha al norte, aviso «sin brújula», sin oyentes de orientación`, (await texto(pg)).includes("sin brújula") && (await pg.evaluate(() => window.__agregados.length)) === 0 && (await pg.$eval("[data-testid=bp-distancia]", (e) => e.textContent)) === "A 33 m");
  await pg.close();
}
async function escritorioCercania(T) {
  modoCercanos = "lista";
  const pg = await abrir("u=op"); await consultar(pg, "1000001");
  await clicTexto(pg, "button.ac-boton-cerca", "Contratos cerca de mí"); await esp(1000);
  ok(`${T} escritorio: «Contratos cerca de mí» lista 5 filas sin desborde`, (await pg.$$(".ac-cercano")).length === 5 && await sinDesborde(pg));
  await pg.click("button.ac-boton-buscar"); await esp(800);
  ok(`${T} escritorio: «Buscar» abre la pantalla completa con la distancia`, (await pg.$eval("[data-testid=bp-distancia]", (e) => e.textContent).catch(() => null)) === "A 111 m");
  await pg.close();
}

try {
  for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
    ANCHO = ancho; ALTO = alto; const T = `[${ancho}]`;
    // ===== Respuesta completa =====
    let pg = await abrir("u=op");
    let t = await texto(pg);
    ok(`${T} lista: «Análisis de contrato» es una tarjeta activa (sin «Próximamente») con su descripción`, await pg.evaluate(() => [...document.querySelectorAll("button.campo-formato-activo")].some((b) => b.textContent.includes("Análisis de contrato") && b.textContent.includes("Escriba un contrato y vea cartera, consumo, medidor, gestiones y ubicación.") && !b.disabled)) && !t.includes("Próximamente"));
    await clicTexto(pg, "button.campo-formato", "Análisis de contrato"); await pg.waitForSelector("#ac-contrato");
    ok(`${T} cabecera: «← Formularios de campo», título y campo numérico (inputmode numeric, máx. 12)`, await pg.evaluate(() => { const i = document.querySelector("#ac-contrato"); return i.inputMode === "numeric" && i.maxLength === 12 && i.getAttribute("pattern") === "[0-9]*" && [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "← Formularios de campo") && document.body.innerText.includes("Análisis de contrato"); }));
    await pg.type("#ac-contrato", "10a00-001xx99999999");
    ok(`${T} el campo deja solo dígitos y máximo 12`, (await pg.$eval("#ac-contrato", (i) => i.value)) === "100000199999");
    await consultar(pg, "1000001");
    const antesN = peticiones.filter((p) => p.accion === "analisis_contrato").length;
    t = await texto(pg);
    ok(`${T} Enter consulta: GET analisis_contrato con el contrato`, peticiones.filter((p) => p.accion === "analisis_contrato").at(-1)?.qs.contrato === "1000001" && peticiones.filter((p) => p.accion === "analisis_contrato").at(-1)?.metodo === "GET");
    const sinCupo = (x) => !/consultas? hoy|cupo diario|l[ií]mite de \d+ consultas/i.test(x);
    ok(`${T} sin límite diario de consultas: la pantalla no muestra ningún texto de cupo de consultas`, sinCupo(t));
    await pg.waitForSelector("[data-testid=distancia-valor]", { timeout: 8000 }).catch(() => null);
    ok(`${T} distancia en la tarjeta con el GPS simulado (0,001° al sur ≈ 111 m): «A 111 m» y botón «Buscar»`, (await pg.$eval("[data-testid=distancia-valor]", (e) => e.textContent).catch(() => null)) === "A 111 m"
      && await pg.evaluate(() => [...document.querySelectorAll("[data-testid=tarjeta] button")].some((b) => b.textContent.trim() === "Buscar")));
    t = await texto(pg);
    ok(`${T} tarjeta: contrato, estado, nombre con «dato personal»`, t.includes("Contrato 1000001 · Activo") && await pg.evaluate((n) => { const p = document.querySelector(".ac-nombre"); return p.textContent.includes(n) && !!p.querySelector(".ac-tag-personal") && p.querySelector(".ac-tag-personal").textContent === "dato personal"; }, NOMBRE));
    ok(`${T} teléfonos como enlaces tel: con formato (300 000 0001 · 570 0001), celular primero, «dato personal» y «censo nov-2025»`, await pg.evaluate(() => { const a = [...document.querySelectorAll("a.ac-tel")]; const p = document.querySelector(".ac-tels"); return a.length === 2 && a[0].getAttribute("href") === "tel:3000000001" && a[0].textContent.includes("300 000 0001") && a[1].getAttribute("href") === "tel:5700001" && a[1].textContent.includes("570 0001") && p.textContent.includes("dato personal") && p.textContent.includes("censo nov-2025"); }));
    ok(`${T} tarjeta: dirección · barrio, uso · estrato · ciclo, deuda con facturas y tramo, cortes visibles`, t.includes("CRA 0 00 00 · Barrio BARRIO DE PRUEBA") && t.includes("Residencial · Estrato 2 · Ciclo 7") && /Deuda \$ 412\.300 · 5 facturas · mora media/i.test(t) && t.includes("cartera al 14/11/2026"));
    ok(`${T} tarjeta: medidor «A00001 · 12 años» y último pago «18/09/2026 (hace 57 días)»`, t.includes("Medidor A00001 · 12 años") && t.includes("Último pago: 18/09/2026 (hace 57 días)"));
    const marcas = await pg.evaluate(() => [...document.querySelectorAll("[data-marca]")].map((l) => [l.dataset.marca, l.innerText]));
    ok(`${T} MARCAS: submedición, corte facturado, PQR abierta, 2 predios y revisión que sugiere cambio`, marcas.map((m) => m[0]).join() === "submedicion,corte,pqr,predios,pendientes", JSON.stringify(marcas));
    ok(`${T} submedición con la frase exacta y el botón «Instalación de medidor → Cambio»`, marcas[0]?.[1].includes("Consumo 6 m³ frente a la referencia 14,2 m³ de los medidores nuevos del estrato 2 (oct-2026); medidor de 12 años.") && marcas[0]?.[1].includes("Instalación de medidor → Cambio"));
    ok(`${T} corte «hace 2 meses», PQR «(hace 1 mes)», «Este contrato está en 2 predios»`, marcas[1]?.[1].includes("Corte facturado hace 2 meses") && marcas[2]?.[1].includes("PQR abierta (hace 1 mes)") && marcas[3]?.[1].includes("Este contrato está en 2 predios"));
    // gráfica
    const g = await pg.evaluate(() => {
      const s = document.querySelector("[data-testid=grafica-consumo]"); const hueco = s.querySelector("[data-sin-dato='1']");
      const est = [...s.querySelectorAll("rect[data-estimado='1']")], real = [...s.querySelectorAll("rect[data-estimado='0']")];
      return { abierta: s.closest("details").open, hueco: hueco?.getAttribute("data-mes"), huecoTexto: hueco?.textContent, barras: est.length + real.length, est: est.map((r) => [r.dataset.mes, r.getAttribute("fill")]), realFill: real[0]?.getAttribute("fill"),
        lineasEstrato: s.querySelectorAll("polyline[data-serie=estrato]").length, lineasBarrio: s.querySelectorAll("polyline[data-serie=barrio]").length, anchoSvg: s.getBoundingClientRect().width };
    });
    ok(`${T} «Consumo» abierto por defecto; gráfica con 5 barras y el hueco de 202606 rotulado «sin dato» (sin barra)`, g.abierta && g.barras === 5 && g.hueco === "202606" && /sin\s*dato/.test(g.huecoTexto), JSON.stringify(g));
    ok(`${T} el mes estimado (jul-2026) es una barra hueca y el de lectura va lleno`, g.est.length === 1 && g.est[0][0] === "202607" && g.est[0][1] === "#FFFFFF" && g.realFill === "#0A2540", JSON.stringify(g.est));
    ok(`${T} líneas de estrato y barrio, cortadas en el mes sin dato (dos tramos cada una)`, g.lineasEstrato === 2 && g.lineasBarrio === 2, JSON.stringify(g));
    t = await texto(pg);
    ok(`${T} leyenda y Máx · Mín · Prom`, t.includes("Promedio del estrato 2") && t.includes("Promedio del barrio BARRIO DE PRUEBA") && t.includes("Estimado") && t.includes("Máx 11 · Mín 5 · Prom 7,8 m³"));
    const tabla = await pg.evaluate(() => [...document.querySelectorAll("[data-testid=tabla-consumo] tbody tr")].map((r) => [...r.children].map((c) => c.innerText.trim())));
    ok(`${T} tabla: 6 meses; jun-2026 «sin dato»; jul-2026 «estimado» con causal; promedios de estrato, barrio y uso`, tabla.length === 6 && tabla[1][0] === "jun-2026" && tabla[1][2] === "sin dato" && tabla[2][1].includes("estimado") && tabla[2][2].includes("21 PREDIO CERRADO") && tabla[0][3] === "8,1" && tabla[0][4] === "7,4" && tabla[0][5] === "9", JSON.stringify(tabla));
    ok(`${T} cada sección lleva su corte («consumo a oct-2026», «ficha del 14/11/2026»)`, t.includes("consumo a oct-2026") && t.includes("ficha del 14/11/2026"));
    // secciones
    const toggle = async (sec) => { await pg.evaluate((s) => document.querySelector(`details[data-seccion=${s}] > summary`).click(), sec); await esp(250); return pg.evaluate((s) => document.querySelector(`details[data-seccion=${s}]`).open, sec); };
    ok(`${T} secciones: «Comercial y cartera», «Medidor», «Gestiones» y «Ubicación» cerradas; se abren y se cierran`, await pg.evaluate(() => ["comercial", "medidor", "gestiones", "ubicacion"].every((s) => !document.querySelector(`details[data-seccion=${s}]`).open))
      && (await toggle("medidor")) === true && (await toggle("medidor")) === false && (await toggle("comercial")) === true);
    await toggle("medidor"); await toggle("gestiones");
    t = await texto(pg);
    ok(`${T} medidor: diámetro, fecha de instalación y la instalación registrada en el geoportal`, t.includes("01/03/2014") && t.includes("1/2") && t.includes("Instalación de medidor registrada en el geoportal IME-000031"));
    ok(`${T} gestiones: corte facturado, corte del geoportal, PQR, reportes, actas y revisión pendiente (sin autor)`, t.includes("600- EMD CORTE DEL SERVICIO") && t.includes("COR-000012") && t.includes("900001") && t.includes("IME-000031") && t.includes("ACT-000004") && t.includes("RPV-000007") && !t.includes("operario@"));
    ok(`${T} «Fotos del predio» no aparece (fotos vacío)`, !(await pg.$("details[data-seccion=fotos]")) && !t.includes("Fotos del predio"));
    ok(`${T} el mapa no se carga hasta abrir «Ubicación»`, !(await pg.$("[data-testid=mapa-punto]")));
    await toggle("ubicacion"); await esp(1500);
    const mapa = await pg.evaluate(() => { const m = document.querySelector("[data-testid=mapa-punto]"); const a = [...document.querySelectorAll("a")].find((x) => x.textContent.trim() === "Abrir en Google Maps"); return { mapa: !!m, alto: m?.getBoundingClientRect().height ?? 0, marcas: document.querySelectorAll(".maplibregl-marker").length, href: a?.getAttribute("href"), target: a?.target, rel: a?.rel }; });
    ok(`${T} Ubicación: mapa presente con un marcador por predio y «Abrir en Google Maps» correcto (_blank, noopener)`, mapa.mapa && mapa.alto > 100 && mapa.marcas === 2 && mapa.href === "https://www.google.com/maps?q=10.4631,-73.2532" && mapa.target === "_blank" && /noopener/.test(mapa.rel), JSON.stringify(mapa));
    t = await texto(pg);
    ok(`${T} atajos «Reportar anomalía», «Formato…» y «Reportar posible pérdida»`, t.includes("Atajos con este contrato:") && await pg.evaluate(() => { const b = [...document.querySelectorAll(".ac-atajos button")].map((x) => x.textContent.trim()); return b.join("|") === "Reportar anomalía|Formato…|Reportar posible pérdida"; }));
    ok(`${T} sin desborde horizontal`, await sinDesborde(pg));
    if (ancho === 1280) {
      const lay = await pg.evaluate(() => { const c = document.querySelector("[data-testid=tarjeta]").getBoundingClientRect(), s = document.querySelector(".ac-secciones").getBoundingClientRect(); return { izq: c.right <= s.left + 1, arriba: Math.abs(c.top - s.top) < 40, sticky: getComputedStyle(document.querySelector("[data-testid=tarjeta]")).position }; });
      ok(`${T} escritorio: tarjeta a la izquierda (fija) y secciones a la derecha`, lay.izq && lay.sticky === "sticky", JSON.stringify(lay));
    } else {
      const col = await pg.evaluate(() => { const c = document.querySelector("[data-testid=tarjeta]").getBoundingClientRect(), s = document.querySelector(".ac-secciones").getBoundingClientRect(); return c.bottom <= s.top + 1 && c.left >= 8 && window.innerWidth - c.right >= 8; });
      ok(`${T} celular: una sola columna (la tarjeta encima de las secciones) con margen lateral`, col);
    }
    await pg.evaluate(() => document.querySelector(".ac-pagina").scrollTo(0, 0));
    await pg.screenshot({ path: join(CAP, `analisis_${ancho}_completo.png`) });
    if (ancho === 390) { await pg.evaluate(() => document.querySelector(".ac-pagina").style.overflow = "visible"); await pg.screenshot({ path: join(CAP, "analisis_390_completo_largo.png"), fullPage: true }); await pg.evaluate(() => document.querySelector(".ac-pagina").style.overflow = ""); }
    else await pg.evaluate(() => document.querySelector("details[data-seccion=consumo]").scrollIntoView()), await pg.screenshot({ path: join(CAP, "analisis_1280_consumo.png") });
    // repetir: va al servidor (no se reutiliza la respuesta)
    await consultar(pg, "1000001");
    ok(`${T} repetir la consulta vuelve a ir al servidor (la respuesta no se guarda)`, peticiones.filter((p) => p.accion === "analisis_contrato").length === antesN + 1);
    // estados
    await consultar(pg, "1000002"); t = await texto(pg);
    ok(`${T} no encontrado: «No encontramos ese contrato.» y nada del anterior`, t.includes("No encontramos ese contrato.") && !personal(t) && sinCupo(t));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "analisis_390_no_encontrado.png") });
    await consultar(pg, "99999999"); t = await texto(pg);
    ok(`${T} comodín: «Contrato corporativo: no tiene análisis.»`, t.includes("Contrato corporativo: no tiene análisis."));
    await consultar(pg, "1000003"); t = await texto(pg);
    ok(`${T} ficha sin calcular: aviso, lo diario visible (nombre, deuda, serial) y sin «censo nov-2025»`, t.includes("El análisis mensual aún no se ha calculado: faltan consumo, medidor, pago y PQR.") && t.includes(NOMBRE) && t.includes("$ 412.300") && t.includes("Medidor A00003 · sin dato") && t.includes("Último pago: sin dato") && !t.includes("censo nov-2025"));
    await pg.evaluate(() => document.querySelector("details[data-seccion=ubicacion] > summary").click()); await esp(300);
    t = await texto(pg);
    ok(`${T} ficha sin calcular: «Sin coordenadas en el catastro.» y sin enlace a Google Maps`, t.includes("Sin coordenadas en el catastro.") && !t.includes("Abrir en Google Maps") && t.includes("El consumo sale del análisis mensual"));
    ok(`${T} ficha sin calcular sin desborde`, await sinDesborde(pg));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "analisis_390_sin_ficha.png") });
    await consultar(pg, "1000400");
    ok(`${T} 400: el mensaje del servidor en un aviso`, await pg.evaluate(() => [...document.querySelectorAll("[role=alert]")].some((a) => a.textContent.includes("Escriba solo los números del contrato (hasta 12 dígitos)."))));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "analisis_390_error_servidor.png") });
    await consultar(pg, "1000403");
    ok(`${T} 403: el mensaje del servidor en un aviso`, await pg.evaluate(() => [...document.querySelectorAll("[role=alert]")].some((a) => a.textContent.includes("No tiene permiso para esta acción."))));
    ok(`${T} nada personal en localStorage ni sessionStorage`, !personal(await almacen(pg)));
    await pg.close();

    // ===== Atajo de submedición → Instalación de medidor con «Cambio» y el contrato =====
    pg = await abrir("u=op"); await consultar(pg, "1000001");
    await clicTexto(pg, "button.ac-boton-cambio", "Instalación de medidor"); await esp(800);
    await pg.evaluate(() => document.querySelectorAll("details.campo-seccion").forEach((d) => { d.open = true; })); await esp(200);
    const fmt = await pg.evaluate(() => { const r = [...document.querySelectorAll("input[type=radio]")].find((x) => x.value === "cambio"); const s = [...document.querySelectorAll("select")].find((x) => [...x.options].some((o) => o.value === "cambio")); return { cambio: r ? r.checked : s?.value === "cambio", contrato: document.querySelector("#fp-contrato")?.value, retirado: document.body.innerText.includes("Medidor retirado · Lectura"), titulo: document.body.innerText.includes("Instalación de medidor") }; });
    ok(`${T} submedición: abre Instalación de medidor con «Cambio» marcado, el contrato cargado y los datos del medidor retirado a la vista`, fmt.cambio && fmt.contrato === "1000001" && fmt.retirado && fmt.titulo, JSON.stringify(fmt));
    await pg.evaluate(() => { const r = [...document.querySelectorAll("input[type=radio]")].find((x) => x.value === "instalacion"); if (r) { r.click(); return; }
      const sel = [...document.querySelectorAll("select")].find((x) => [...x.options].some((o) => o.value === "instalacion")); const set = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value").set; set.call(sel, "instalacion"); sel.dispatchEvent(new Event("change", { bubbles: true })); }); await esp(250);
    ok(`${T} submedición: «Cambio» solo prellena; la persona lo puede cambiar`, !(await texto(pg)).includes("Medidor retirado · Lectura"));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "analisis_390_atajo_cambio.png") });
    ok(`${T} nada personal en el almacenamiento tras pasar al formato`, !personal(await almacen(pg)));
    await pg.close();
    // ===== Los demás atajos llevan el contrato =====
    pg = await abrir("u=op"); await consultar(pg, "1000001");
    await clicTexto(pg, ".ac-atajos button", "Reportar anomalía"); await esp(600);
    ok(`${T} atajo «Reportar anomalía» con el contrato`, (await pg.$eval("#campo-contrato", (i) => i.value).catch(() => null)) === "1000001");
    await pg.close();
    pg = await abrir("u=op"); await consultar(pg, "1000001");
    await clicTexto(pg, ".ac-atajos button", "Formato…"); await esp(500);
    ok(`${T} atajo «Formato…» abre el selector de formatos`, (await texto(pg)).includes("Formatos de actividad"));
    await clicTexto(pg, "button.campo-formato", "Instalación de medidor"); await esp(600);
    const fmt2 = await pg.evaluate(() => ({ contrato: document.querySelector("#fp-contrato")?.value, cambio: [...document.querySelectorAll("input[type=radio]")].some((x) => x.checked && x.value === "cambio") || [...document.querySelectorAll("select")].some((x) => x.value === "cambio"),
      hayControl: [...document.querySelectorAll("select")].some((x) => [...x.options].some((o) => o.value === "cambio")) }));
    ok(`${T} …y el formato elegido trae el contrato, SIN «Cambio» marcado (eso es solo del atajo de submedición)`, fmt2.contrato === "1000001" && fmt2.hayControl && !fmt2.cambio, JSON.stringify(fmt2));
    await pg.close();
    pg = await abrir("u=op"); await consultar(pg, "1000001");
    const antesActa = peticiones.filter((p) => p.fn === "geoportal-acta").length;
    await clicTexto(pg, ".ac-atajos button", "Reportar posible pérdida"); await esp(700);
    ok(`${T} atajo «Reportar posible pérdida» deja el análisis y abre el acta (pide su catálogo)`, !(await pg.$("#ac-contrato")) && peticiones.filter((p) => p.fn === "geoportal-acta").length > antesActa);
    await pg.close();
    // ===== Formato de instalación inactivo: no se ofrece el atajo de submedición =====
    pg = await abrir("u=sinform"); await consultar(pg, "1000001");
    ok(`${T} con Instalación de medidor inactiva no aparece «Instalación de medidor → Cambio» (la marca sí)`, !(await pg.$("button.ac-boton-cambio")) && (await texto(pg)).includes("Posible submedición"));
    await pg.close();

    if (ancho === 390) await pruebasCercania(T); else await escritorioCercania(T);

    // ===== Usuario solo comercial =====
    const desde = Date.now();
    pg = await abrir("u=com");
    t = await texto(pg);
    const tarjetas = await pg.evaluate(() => [...document.querySelectorAll(".campo-formato")].map((b) => b.querySelector("strong").textContent));
    ok(`${T} solo comercial: únicamente la tarjeta «Análisis de contrato» y NO se pidió el formulario de campo`, tarjetas.join() === "Análisis de contrato" && !peticiones.some((p) => p.u === "com" && p.accion === "formulario" && p.en >= desde) && !t.includes("Reportar anomalía"), JSON.stringify(tarjetas));
    if (ancho === 390) await pg.screenshot({ path: join(CAP, "analisis_390_solo_comercial.png") });
    await consultar(pg, "1000001"); t = await texto(pg);
    ok(`${T} solo comercial: ve el análisis, sin atajos ni botón de cambio de medidor`, t.includes("Contrato 1000001") && !(await pg.$(".ac-atajos")) && !(await pg.$("button.ac-boton-cambio")));
    ok(`${T} solo comercial sin desborde`, await sinDesborde(pg));
    await pg.close();

    // ===== Sin el permiso: la entrada no aparece =====
    pg = await abrir("u=nada");
    ok(`${T} sin el permiso analisis_contrato la entrada no aparece`, !(await texto(pg)).includes("Análisis de contrato"));
    await pg.close();

    // ===== Administración =====
    pg = await abrir("p=admin&u=admc"); await esp(400);
    await clicTexto(pg, "button.btn-link", "Editar"); await esp(300);
    const etiqueta = "Análisis de contrato (consulta un contrato: incluye nombre y teléfono)";
    ok(`${T} Admin: la casilla aparece dentro de «Comercial · Formatos de campo» cuando el servidor trae ver_analisis_contrato`, await pg.evaluate((e) => [...document.querySelectorAll("section[aria-label='Comercial · Formatos de campo'] label.adm-check")].some((l) => l.textContent.trim() === e), etiqueta));
    await pg.evaluate((e) => [...document.querySelectorAll("label.adm-check")].find((l) => l.textContent.trim() === e).querySelector("input").click(), etiqueta); await esp(150);
    if (ancho === 1280) await pg.screenshot({ path: join(CAP, "admin_1280_analisis.png") });
    let antes = peticiones.length;
    await clicTexto(pg, "button", "Guardar cambios"); await esp(800);
    let cuerpoPerm = peticiones.slice(antes).find((p) => p.accion === "permisos")?.cuerpo;
    ok(`${T} Admin: «Guardar» envía analisis_contrato: true y verifica (mensaje de éxito)`, cuerpoPerm?.analisis_contrato === true && (await texto(pg)).includes("Permisos actualizados"), JSON.stringify(cuerpoPerm));
    USUARIOS.admc.ver_analisis_contrato = false;
    await pg.close();
    pg = await abrir("p=admin&u=adms"); await esp(400);
    await clicTexto(pg, "button.btn-link", "Editar"); await esp(300);
    ok(`${T} Admin: sin el booleano en la lista, la casilla NO aparece`, !(await texto(pg)).includes("Análisis de contrato"));
    antes = peticiones.length;
    await clicTexto(pg, "button", "Guardar cambios"); await esp(800);
    cuerpoPerm = peticiones.slice(antes).find((p) => p.accion === "permisos")?.cuerpo;
    ok(`${T} Admin: sin el booleano, el cuerpo NO lleva analisis_contrato`, !!cuerpoPerm && !("analisis_contrato" in cuerpoPerm), JSON.stringify(cuerpoPerm));
    await pg.close();
  }
  ok("nada personal escrito en la consola del navegador", !consola.some(personal), consola.filter(personal).slice(0, 3).join(" | "));
  ok("lo único que intentó salir de 127.0.0.1 fueron teselas de OpenStreetMap (bloqueadas): nada a Supabase ni a teselas comerciales", bloqueadas.every((u) => u.startsWith("https://tile.openstreetmap.org/")), bloqueadas.filter((u) => !u.startsWith("https://tile.openstreetmap.org/")).slice(0, 3).join(" | "));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 600)); }
await nav.close(); srv.close(); estatico.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
