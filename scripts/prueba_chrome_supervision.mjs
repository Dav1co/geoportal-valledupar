// Prueba en CHROME REAL (puppeteer-core + el Chrome instalado) de las pantallas de Aseo tocadas por la Torre C · supervisión y firmas, contra un servidor SIMULADO en 127.0.0.1 (ninguna petición llega a Supabase).
// Cubre: auditor (formulario con texto de rostros, firmas con el pad a pantalla completa, registro, acta en PDF con nombre AAAAMMDDHHMMSS-SIGLA-NNNNNN) y supervisor (entrada sin «Gestión de personal», Resumen en rojo y revisión,
// Auditorías con filtros y detalle, acta regenerada con y sin CORS en las fotos, No conformidades, Indicadores, Personal, descargas CSV y Excel).
// Hora de inicio (pasada 14/11): el cuerpo de «crear» lleva inicio_dispositivo del momento de ABRIR (380 px y escritorio), igual en el reintento y recalculado tras corregir el reloj;
// la supervisión muestra Inicio «(celular)», Fin y Duración en lista y detalle (380 px y escritorio) y las descargas traen las columnas. Capturas en CAPTURAS_DIR si se define.
// Uso:  PUPPETEER_DIR=<carpeta con node_modules/puppeteer-core> node scripts/prueba_chrome_supervision.mjs   (compila una copia del frontend contra la URL simulada)
import http from "node:http";
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, readdirSync, existsSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
// «aseo-estilo» (17-nov): al final recorre TODAS las pantallas de Aseo a 390 y 1280 px como administrador, toma una captura de cada una (estilo_*.png) y comprueba el modelo visual
// (color de Aseo, fuente única, tarjetas, botones de 44 px, rejilla de 4 columnas y 1). ANTES=1 RAIZ_UI=<árbol de main>: solo las capturas de «antes». PUERTO_MOCK cambia el puerto.
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? join(process.env.RAIZ_UI) : join(aqui, "..");
const PP = process.env.PUPPETEER_DIR; if (!PP) { console.error("Defina PUPPETEER_DIR (carpeta que contiene node_modules/puppeteer-core)."); process.exit(2); }
const puppeteer = createRequire(join(PP, "package.json"))("puppeteer-core");
const CHROME = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PUERTO_MOCK = Number(process.env.PUERTO_MOCK || 54998);
const ANTES = process.env.ANTES === "1";
const CAPTURAS = process.env.CAPTURAS_DIR || null;
const captura = async (p, n) => { if (CAPTURAS) await p.screenshot({ path: join(CAPTURAS, n), fullPage: true }); };

// ---------- Compilación contra el servidor simulado ----------
const dist = mkdtempSync(join(tmpdir(), "aseo_dist_"));
const b = spawnSync("npx", ["vite", "build", "--outDir", dist, "--emptyOutDir"], { cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: `http://127.0.0.1:${PUERTO_MOCK}`, VITE_SUPABASE_ANON_KEY: "anon-falsa", VITE_FUNCTIONS_URL: `http://127.0.0.1:${PUERTO_MOCK}/functions/v1` } });
if (b.status !== 0) { console.error(b.stdout, b.stderr); process.exit(2); }

// ---------- Datos simulados ----------
const LOGO_B64 = readFileSync(join(raiz, "src/aseo/membrete.ts"), "utf8").match(/export const LOGO = \{[^}]*?b64: "([^"]+)"/)[1];
const JPG = Buffer.from(LOGO_B64, "base64");
const UUID = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const CATALOGO = (perfil) => ({ perfil, correo: "aud@emdupar.gov.co", nombre: "Auditor Prueba", puede: { capturar: true, supervisar: perfil !== "auditor", administrar: perfil === "admin" }, ahora: "2026-11-13T10:30:00",
  limites: { max_bytes_foto: 1572864, busqueda_min_caracteres: 5, mapa_zoom_inicial: 15, distancia_marca_m: 50, precision_aviso_m: 30 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
  actividades: [{ codigo: "barrido", nombre: "Barrido", orden: 10, activa: true, fotos_max: 5, usa_consecutivo: true,
    modalidades: [{ codigo: "manual", nombre: "Manual", orden: 10, activa: true, servicios: [{ codigo: "12", nombre: "Barrido Manual", activo: true }] }],
    criterios: [{ codigo: "sst_herramientas", nombre: "¿Cuenta con las herramientas?", seccion: "SST", tipo_dato: "si_no", obligatorio: true, exige_foto_si: "no", etiqueta_foto: "sst_herramientas", activo: true, orden: 10 },
                { codigo: "sst_epp", nombre: "¿Usa los EPP?", seccion: "SST", tipo_dato: "si_no", obligatorio: true, exige_foto_si: "no", etiqueta_foto: "sst_epp", activo: true, orden: 20 }],
    fotos: [{ codigo: "ruta", nombre: "Fotos de la ruta", cantidad_min: 3, cantidad_max: 3, condicional: false, soporte_no_realizada: false, activo: true, orden: 10 },
            { codigo: "sst_herramientas", nombre: "Evidencia: herramientas", cantidad_min: 1, cantidad_max: 1, condicional: true, soporte_no_realizada: false, activo: true, orden: 20 },
            { codigo: "sst_epp", nombre: "Evidencia: EPP", cantidad_min: 1, cantidad_max: 1, condicional: true, soporte_no_realizada: false, activo: true, orden: 30 },
            { codigo: "evidencia", nombre: "Evidencia de que no se realizó", cantidad_min: 1, cantidad_max: 1, condicional: false, soporte_no_realizada: true, activo: true, orden: 40 }],
    causales: [{ codigo: "clima", nombre: "Clima", activo: true }] }] });
const RUTA = { id: 1, codigo: "2010011207003", servicio: { codigo: "12", nombre: "Barrido Manual" }, turno: 1, turno_nombre: "Día", frecuencia: "07", frecuencia_nombre: "L-D", dias: [1, 2, 3, 4, 5, 6, 7], hora_inicio: "00:00", hora_fin: "23:59", sectores: "Centro, El Carmen - C19A a 17 de K9 a 6", caracterizacion: "Comercial", km_ruta: 3.9, barrios: ["Centro"], geometria: null };
const E = { cors: false, perfil: "auditor", crear: null, cuerpos: [], colaCrear: [], llamadas: [], estados: { [UUID(1)]: "sin_revisar", [UUID(2)]: "sin_revisar", [UUID(3)]: "revisada" }, ocultas: new Set(),
  personas: [{ email: "aud@emdupar.gov.co", nombre: "Auditor Prueba", perfil: "auditor", cargo: null, actividades: [], activo_aseo: true, ultimo_cambio: null }], eventos: [], regFiltros: [] };
const fila = (n, o = {}) => ({ id: UUID(n), seq: n, consecutivo: `BAR-00000${n}`, registrado_en: "2026-11-13T15:30:15+00:00", fecha_servicio: "2026-11-13", ruta_codigo: "2010011207003", actividad: "barrido", actividad_nombre: "Barrido", modalidad_nombre: "Manual", servicio: "12", servicio_nombre: "Barrido Manual",
  turno_nombre: "Día", barrios: "Centro", se_realizo: n === 2 ? "parcial" : "si", causal_nombre: n === 2 ? "Clima" : null, autor: "aud@emdupar.gov.co", lejos_de_ruta: n === 1, fuera_de_zona: false, fuera_de_horario: false, no_programada_hoy: false, sin_trazado: false, oculta: E.ocultas.has(n), n_fotos: 2,
  ...(n === 1 ? { inicio_en: "2026-11-13T15:05:00+00:00", inicio_origen: "dispositivo", duracion_s: 1515 } : n === 3 ? { inicio_en: "2026-11-13T14:20:00+00:00", inicio_origen: "dispositivo", duracion_s: 4215 } : { inicio_en: null, inicio_origen: null, duracion_s: null }),
  nc_tipos: n === 2 ? ["parcial"] : ["sst"], nc_estado: E.estados[UUID(n)], nc_motivos: n === 2 ? [{ tipo: "parcial", criterio: null, pregunta: null, respuesta: null }] : [{ tipo: "sst", criterio: "sst_epp", pregunta: "¿Usa los EPP?", respuesta: "No" }], ...o });
const DET = (n) => ({ ...fila(n), lat: 10.47, lon: -73.24, lat_inicio: null, lon_inicio: null, precision_m: 8, distancia_ruta_m: 12, observaciones: null, frecuencia_nombre: "L-D", marcas: { lejos_de_ruta: n === 1, fuera_de_zona: false, fuera_de_horario: false, no_programada_hoy: false, sin_trazado: false }, oculta_motivo: null, sello: "cd".repeat(32),
  respuestas: [{ codigo: "sst_epp", pregunta: "¿Usa los EPP?", texto: "No" }], fotos: [{ orden: 1, etiqueta: "ruta", nombre: "Fotos de la ruta" }, { orden: 2, etiqueta: "ruta", nombre: "Fotos de la ruta" }], firmas: [{ rol: "auditor", estado: "firmo", nombre: "Auditor Prueba", cargo: "Profesional de interventoría" }, { rol: "representante", estado: "sin_representante", nombre: null, cargo: null }],
  revisiones: E.estados[UUID(n)] === "revisada" ? [{ id: 1, tipo_evento: "revisar", nota: "Revisada en la prueba", autor: "sup@emdupar.gov.co", creado_en: "2026-11-13T16:00:00+00:00" }] : [], eventos_visibilidad: [] });
const ACTA = { consecutivo: "BAR-000001", registrado_en: "2026-11-13T15:30:15+00:00", fecha_servicio: "2026-11-13", sello: "cd".repeat(32), sigla: "BAR", ruta_codigo: "2010011207003", actividad_nombre: "Barrido", modalidad_nombre: "Manual", servicio: "12", servicio_nombre: "Barrido Manual", sectores: "Centro", turno_nombre: "Día", hora_inicio: "06:00", hora_fin: "14:00", frecuencia_nombre: "L-D", km: 3.9,
  se_realizo: "parcial", causal_nombre: "Clima", observaciones: null, respuestas: [{ pregunta: "¿Usa los EPP?", respuesta: "No" }], lat: 10.47, lon: -73.24, precision_m: 8, lat_inicio: null, lon_inicio: null, marcas: { lejos_de_ruta: true, fuera_de_zona: false, fuera_de_horario: false, no_programada_hoy: false, sin_trazado: false },
  auditor: { nombre: "Auditor Prueba", correo: "aud@emdupar.gov.co", cargo: null, imagen_b64: LOGO_B64 }, representante: { estado: "firmo", nombre: "Maria Representante", imagen_b64: LOGO_B64 }, fotos: [{ orden: 1, etiqueta: "Fotos de la ruta" }, { orden: 2, etiqueta: "Fotos de la ruta" }] };
const DFILA = { id: UUID(1), seq: 1, consecutivo: "BAR-000001", registrado_local: "2026-11-13T10:30:15", fecha_servicio: "2026-11-13", actividad_nombre: "Barrido", modalidad_nombre: "Manual", servicio: "12", servicio_nombre: "Barrido Manual", ruta_codigo: "2010011207003", turno_nombre: "Día", frecuencia_nombre: "L-D", barrios: "Centro", autor: "aud@emdupar.gov.co", auditor_nombre: "Auditor Prueba", auditor_cargo: null,
  representante_estado: "firmo", representante_nombre: "Maria Representante", incidencia: "parcial", causal_nombre: "Clima", observaciones: null, marcas: ["Lejos de la ruta"], nc_tipos: ["sst"], nc_estado: "sin_revisar", oculta: false, oculta_motivo: null, n_fotos: 2, lat: 10.47, lon: -73.24, sello: "cd".repeat(32), respuestas: { sst_epp: "No" },
  inicio_local: "2026-11-13T10:05:00", inicio_origen: "dispositivo", duracion_min: 25.3 };

const CAB = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, apikey, x-client-info, x-upsert, cache-control", "access-control-allow-methods": "GET, POST, PUT, OPTIONS" };
const USER = { id: "00000000-0000-0000-0000-000000000001", email: "aud@emdupar.gov.co", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, created_at: "2026-01-01T00:00:00Z" };
const leerCuerpo = (q) => new Promise((r) => { const c = []; q.on("data", (x) => c.push(x)); q.on("end", () => r(Buffer.concat(c).toString())); });
const mock = http.createServer(async (q, r) => {
  const url = new URL(q.url, "http://x"); const json = (o, s = 200, h = {}) => { r.writeHead(s, { ...CAB, "content-type": "application/json", ...h }); r.end(JSON.stringify(o)); };
  if (q.method === "OPTIONS") { r.writeHead(204, CAB); return r.end(); }
  if (url.pathname.startsWith("/auth/v1/token")) return json({ access_token: "token-falso", refresh_token: "r2", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: USER });
  if (url.pathname.startsWith("/auth/v1/user")) return json(USER);
  if (url.pathname.startsWith("/storage/v1/object/upload/sign/")) { await leerCuerpo(q); return json({ Key: "ok" }); }
  if (url.pathname.startsWith("/img/")) { r.writeHead(200, { "content-type": "image/jpeg", ...(E.cors ? { "access-control-allow-origin": "*" } : {}) }); return r.end(JPG); }
  const cuerpo = q.method === "POST" ? JSON.parse((await leerCuerpo(q)) || "{}") : {};
  const accion = url.searchParams.get("accion");
  if (url.pathname.includes("geoportal-admin")) {
    const dash = E.perfil !== "auditor";
    return json({ es_admin: false, permisos: { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, aseo: true, dashboard_aseo: dash, torre_c: true, torre_a: false, torre_b: false } });
  }
  E.llamadas.push({ accion, cuerpo, q: Object.fromEntries(url.searchParams) });
  switch (accion) {
    case "formulario": return json(CATALOGO(E.perfil));
    case "mapa": return json({ etag: "m1", type: "FeatureCollection", features: [{ type: "Feature", geometry: { type: "LineString", coordinates: [[-73.2450, 10.4700], [-73.2436, 10.4707], [-73.2420, 10.4712]] }, properties: { ruta_id: 1, codigo: RUTA.codigo, clase: "linea", version: 1, completa: true } }] });
    case "cercanas": return json([{ ruta_id: 1, codigo: RUTA.codigo, distancia_m: 12, dentro: false }]);
    case "cargas": return json({ cargas: [{ id: UUID(5), tipo: "plan", version: 1, provisional: true, nombre: "plan_operativo_2020.xlsx", filas: 541, origen: null, autor: "adm@emdupar.gov.co", creado_en: "2026-11-10T14:00:00+00:00", aplicada: true },
      { id: UUID(6), tipo: "capa", version: null, provisional: false, nombre: "rutas_barrido.geojson", filas: 320, origen: "geojson", autor: "adm@emdupar.gov.co", creado_en: "2026-11-11T09:30:00+00:00", aplicada: true }], resumen: { rutas: 541, puntos: 12, con_trazado: 320, barrios_sin_coincidencia: 2 } });
    case "barrios_sin_coincidencia": return json({ sugerencias_disponibles: true, barrios: [{ nombre: "Villa del Rosario", rutas: 3, ejemplo_ruta: "2010011207003", sugerencias: ["Villa Rosario"] }, { nombre: "Primero de Mayo", rutas: 1, ejemplo_ruta: "2010011207008", sugerencias: [] }] });
    case "plan": return json({ etag: "e1", ahora: "2026-11-13T10:30:00", rutas: [RUTA] });
    case "preparar_subida": return json({ auditoria_id: UUID(77), max_bytes_foto: 1572864, tipo_mime: "image/jpeg", ahora: "2026-11-13T10:30:00", fotos: Array.from({ length: cuerpo.cantidad }, (_, i) => ({ orden: i + 1, ruta: `auditorias/2026-11/${UUID(77)}/${i + 1}.jpg`, url_subida: `http://127.0.0.1:${PUERTO_MOCK}/storage/v1/object/upload/sign/aseo-fotos/x`, token: "TOKEN" })) });
    case "crear": { E.cuerpos.push(cuerpo); const r0 = E.colaCrear.shift(); if (r0) return json(r0.body, r0.status); }
      E.crear = cuerpo; return json({ id: UUID(77), consecutivo: "BAR-000077", registrado_en: "2026-11-13T15:30:15+00:00", fecha_servicio: "2026-11-13", repetido: false, lejos_de_ruta: false, fuera_de_zona: false, fuera_de_horario: false, no_programada_hoy: false, sin_trazado: true, sello: "ef".repeat(32), auditor: { nombre: "Auditor Prueba", correo: "aud@emdupar.gov.co", cargo: "Profesional de interventoría" }, inicio_en: cuerpo.inicio_dispositivo ?? null });
    case "resumen": { const p = [1, 2].filter((n) => ["sin_revisar", "reabierta"].includes(E.estados[UUID(n)]) && !E.ocultas.has(n)); return json({ pendientes: p.length, revisadas: 1, turnos: [{ codigo: 1, nombre: "Día" }, { codigo: 2, nombre: "Tarde" }], auditores: [{ email: "aud@emdupar.gov.co", nombre: "Auditor Prueba" }], registros: p.map((n) => fila(n)) }); }
    case "registros": { E.regFiltros.push(cuerpo); const nc = cuerpo.nc; let l = [1, 2, 3].map((n) => fila(n)).filter((x) => !(cuerpo.ocultos === "no" || !cuerpo.ocultos ? x.oculta : false));
      if (nc === "pendientes") l = l.filter((x) => ["sin_revisar", "reabierta"].includes(x.nc_estado)); if (nc === "revisadas") l = l.filter((x) => x.nc_estado === "revisada");
      return json({ total: l.length, pendientes: l.filter((x) => ["sin_revisar", "reabierta"].includes(x.nc_estado)).length, revisadas: l.filter((x) => x.nc_estado === "revisada").length, devueltos: l.length, registros: l }); }
    case "revisar": { const id = cuerpo.id; E.estados[id] = cuerpo.accion === "revisar" ? "revisada" : "reabierta"; return json({ evento: 1, nc_estado: E.estados[id], revisado_por: "sup@emdupar.gov.co" }); }
    case "gestionar_auditoria": { const n = Number(cuerpo.id.slice(-2)); if (cuerpo.accion === "ocultar") E.ocultas.add(n); else E.ocultas.delete(n); return json({ evento: 1, oculta: cuerpo.accion === "ocultar" }); }
    case "detalle": return json(DET(Number(url.searchParams.get("id").slice(-2))));
    case "fotos_acta": return json({ fotos: [1, 2].map((n) => ({ orden: n, etiqueta: "ruta", nombre: "Fotos de la ruta", url: `http://127.0.0.1:${PUERTO_MOCK}/img/${n}.jpg`, expira_en: "x" })) });
    case "foto_base64": return json({ orden: 1, tipo: "image/jpeg", b64: JPG.toString("base64") });
    case "acta_datos": return json(ACTA);
    case "indicadores": return json({ auditorias: 3, rutas_auditadas: 1, rutas_plan: 541, incidencia: { si: 2, no: 0, parcial: 1 }, no_conformes: { auditorias: 2, pendientes: 1, revisadas: 1, por_tipo: { sst: 1, no_realizada: 0, parcial: 1, forma_indebida: 0 } }, marcas: { lejos_de_ruta: 1, fuera_de_horario: 0, fuera_de_zona: 0, no_programada_hoy: 0, sin_trazado: 0 } });
    case "personal": return json({ actividades: [{ codigo: "barrido", nombre: "Barrido", activa: true }, { codigo: "poda", nombre: "Poda", activa: false }], personas: E.personas });
    case "personal_cambiar": { const p = E.personas.find((x) => x.email === cuerpo.persona); if (cuerpo.tipo === "fijar_cargo") p.cargo = cuerpo.cargo; if (cuerpo.tipo === "asignar_actividad") p.actividades.push(cuerpo.actividad); if (cuerpo.tipo === "quitar_actividad") p.actividades = p.actividades.filter((a) => a !== cuerpo.actividad); if (cuerpo.tipo === "desactivar_aseo") p.activo_aseo = false; if (cuerpo.tipo === "activar_aseo") p.activo_aseo = true; E.eventos.push(cuerpo); return json({ evento: E.eventos.length }); }
    case "historial_personal": return json({ total: 0, devueltos: 0, eventos: [] });
    case "descarga_iniciar": return json({ descarga_id: 9, total: 1, max: 50000, formato: cuerpo.formato, filtros: cuerpo.filtros, generado_por: "sup@emdupar.gov.co", generado_en: "13/11/2026 10:44", actividad: { codigo: "barrido", nombre: "Barrido" }, criterios: [{ codigo: "sst_epp", nombre: "¿Usa los EPP?", tipo_dato: "si_no" }] });
    case "descarga_pagina": return json({ registros: cuerpo.despues_de ? [] : [DFILA], devueltos: cuerpo.despues_de ? 0 : 1, ultimo_id: 1, hay_mas: false });
    case "descarga_cerrar": return json({ cerrada: true });
    default: return json({ error: "no simulada" }, 400);
  }
});
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json" };
const srv = http.createServer((q, r) => { const p = q.url.split("?")[0]; const f = join(dist, p === "/" ? "index.html" : p); if (!f.startsWith(dist) || !existsSync(f) || statSync(f).isDirectory()) { r.writeHead(404); return r.end(); } r.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); r.end(readFileSync(f)); });
await new Promise((r) => mock.listen(PUERTO_MOCK, "127.0.0.1", r)); await new Promise((r) => srv.listen(0, "127.0.0.1", r));
const URL_APP = `http://127.0.0.1:${srv.address().port}/`;

// ---------- Utilidades ----------
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
let total = 0, fallas = 0; const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d === "" ? "" : JSON.stringify(d).slice(0, 400)}`); } };
const navegador = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ["--no-sandbox", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const DESCARGAS = mkdtempSync(join(tmpdir(), "aseo_desc_"));
const errores = []; const esperadoCors = /blocked by CORS policy/;
async function sesion(perfil, vp) {
  E.perfil = perfil; E.llamadas.length = 0;
  const ctx = await navegador.createBrowserContext(); await ctx.overridePermissions(URL_APP.slice(0, -1), ["geolocation", "camera"]);
  const p = await ctx.newPage(); await p.setViewport(vp); await p.setGeolocation({ latitude: 10.4707, longitude: -73.2436, accuracy: 10 });
  p.on("pageerror", (e) => errores.push(`${perfil}: ${String(e).slice(0, 200)}`)); p.on("console", (m) => { if (m.type() === "error" && !E.mapaAbierto && !/Failed to load resource|net::ERR/.test(m.text()) && !(E.cors === false && esperadoCors.test(m.text()))) errores.push(`${perfil}: ${m.text().slice(0, 200)}`); });
  const c = await navegador.target().createCDPSession(); await c.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: DESCARGAS, browserContextId: ctx.id });
  await p.evaluateOnNewDocument((u) => { const ahora = Math.floor(Date.now() / 1000); localStorage.setItem("sb-127-auth-token", JSON.stringify({ access_token: "token-falso", refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: ahora + 3600, user: u })); }, USER);
  await p.goto(URL_APP); return p;
}
const T = (p) => p.evaluate(() => document.body.innerText);
const clic = async (p, sel, texto) => { const h = await p.evaluateHandle((s, t) => [...document.querySelectorAll(s)].find((e) => !t || e.textContent.includes(t)), sel, texto); const el = h.asElement(); if (!el) throw new Error(`No hay ${sel} «${texto ?? ""}»`); await el.click(); };
const hay = (p, sel, texto) => p.evaluate((s, t) => [...document.querySelectorAll(s)].some((e) => !t || e.textContent.includes(t)), sel, texto);
async function esperar(p, fn, ms = 8000, ...a) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await p.evaluate(fn, ...a)) return true; await esp(100); } return false; }
async function archivoNuevo(antes, ms = 8000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { const n = readdirSync(DESCARGAS).filter((f) => !antes.has(f) && !f.endsWith(".crdownload")); if (n.length) return n[0]; await esp(100); } return null; }
const textoPdf = (f) => spawnSync("python3", ["-I", "-c", "import sys; from pypdf import PdfReader; r=PdfReader(sys.argv[1]); print(' '.join(p.extract_text() for p in r.pages))", join(DESCARGAS, f)], { encoding: "utf8" }).stdout;
async function dibujar(p, sel = ".aseo-firma-lienzo") { const r = await (await p.$(sel)).boundingBox(); const x0 = r.x + r.width * 0.15, y0 = r.y + r.height * 0.5;
  await p.mouse.move(x0, y0); await p.mouse.down(); for (let i = 1; i <= 24; i++) await p.mouse.move(x0 + i * (r.width * 0.03), y0 + Math.sin(i / 2) * r.height * 0.25); await p.mouse.up(); }
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

// =====================================================================  1) AUDITOR en celular
{
  const p = await sesion("auditor", { width: 412, height: 860, isMobile: true, hasTouch: true });
  await esperar(p, () => /Barrido|Aseo/.test(document.body.innerText), 15000);
  if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Interventoría de Aseo/.test(document.body.innerText));
  let t = await T(p);
  ok("auditor: no ve «Supervisión y dashboard» ni «Gestión de personal»", !/Supervisión y dashboard|Gestión de personal/.test(t), t.slice(0, 200));
  await clic(p, ".campo-formato-activo", "Barrido"); await esperar(p, () => /Manual/.test(document.body.innerText));
  await clic(p, ".campo-formato-activo", "Manual"); await p.waitForSelector("#aseo-q"); await p.type("#aseo-q", "2010011207003");
  await p.waitForSelector(".aseo-ruta"); const tAbrir0 = await p.evaluate(() => Date.now()); await clic(p, ".aseo-ruta");
  await p.waitForSelector("input[name=se_realizo]"); const tAbrir1 = await p.evaluate(() => Date.now());
  await clic(p, "label.aseo-opcion", "Sí");
  for (const n of ["sst_herramientas", "sst_epp"]) await p.evaluate((nm) => { const l = [...document.querySelectorAll(`input[name="aseo-c-${nm}"]`)].find((i) => i.value === "si"); l.click(); }, n);
  t = await T(p);
  ok("formulario: texto «Evite fotografiar el rostro de las personas» junto a las fotos", /Evite fotografiar el rostro de las personas/.test(t));
  ok("formulario: muestra «Falta la firma del auditor» y Registrar deshabilitado", /Falta la firma del auditor/.test(t) && await p.evaluate(() => [...document.querySelectorAll("button")].find((b) => /^Registrar$/.test(b.textContent.trim()))?.disabled));
  for (let i = 0; i < 3; i++) {
    await clic(p, "button", "Tomar foto"); await p.waitForSelector(".campo-camara");
    if (i === 0) ok("cámara: el aviso del rostro también está en el visor", /Evite fotografiar el rostro de las personas/.test(await p.evaluate(() => document.querySelector(".campo-camara").innerText)));
    await esperar(p, () => !document.querySelector(".campo-capturar")?.disabled, 10000); await p.click(".campo-capturar"); await esperar(p, () => !document.querySelector(".campo-camara"), 10000);
  }
  ok("fotos: 3 miniaturas tomadas con la cámara simulada", await p.evaluate(() => document.querySelectorAll(".aseo-mini img").length === 3));
  // Pad de firma
  await clic(p, "button", "Agregar firma"); await p.waitForSelector(".aseo-firma-capa");
  const cap = await p.evaluate(() => { const r = document.querySelector(".aseo-firma-capa").getBoundingClientRect(); return { w: r.width, h: r.height, vw: innerWidth, vh: innerHeight, ok: [...document.querySelectorAll(".aseo-firma-acc button")].map((b) => b.textContent.trim()) }; });
  ok("pad: ocupa toda la pantalla y tiene Cancelar, Limpiar y OK", cap.w >= cap.vw - 1 && cap.h >= cap.vh - 1 && ["Cancelar", "Limpiar", "OK"].every((x) => cap.ok.includes(x)), cap);
  ok("pad: OK y Limpiar deshabilitados sin trazo", await p.evaluate(() => [...document.querySelectorAll(".aseo-firma-acc button")].filter((b) => /OK|Limpiar/.test(b.textContent)).every((b) => b.disabled)));
  await clic(p, ".aseo-firma-acc button", "Cancelar"); await esperar(p, () => !document.querySelector(".aseo-firma-capa"));
  ok("pad: Cancelar cierra sin dejar firma", !(await hay(p, ".aseo-firma-mini")) && /Falta la firma del auditor/.test(await T(p)));
  await clic(p, "button", "Agregar firma"); await p.waitForSelector(".aseo-firma-capa"); await esp(300);
  { const r = await (await p.$(".aseo-firma-lienzo")).boundingBox(); await p.mouse.move(r.x + 20, r.y + 20); await p.mouse.down(); await p.mouse.move(r.x + 24, r.y + 22); await p.mouse.up(); }
  await clic(p, ".aseo-firma-acc button", "OK"); await esp(300);
  ok("pad: un toque o raya mínima se rechaza con aviso y no cierra", /muy corta/.test(await T(p)) && await hay(p, ".aseo-firma-capa"));
  await clic(p, ".aseo-firma-acc button", "Limpiar"); await dibujar(p); await clic(p, ".aseo-firma-acc button", "Limpiar"); await dibujar(p);
  await clic(p, ".aseo-firma-acc button", "OK"); await esperar(p, () => !document.querySelector(".aseo-firma-capa"));
  ok("firma del auditor: queda como miniatura con «Volver a firmar»", await p.evaluate(() => !!document.querySelector(".aseo-firma-mini img") && [...document.querySelectorAll("button")].some((b) => /Volver a firmar/.test(b.textContent))));
  // Representante: firma con nombre
  await p.evaluate(() => [...document.querySelectorAll("input[name=rep_estado]")].find((i) => i.value === "firmo").click());
  ok("representante: al elegir «Firma» pide nombre y trazo (Registrar sigue bloqueado)", /Escriba el nombre del representante/.test(await T(p)));
  await p.type("#aseo-rep-nombre", "Maria Representante"); await clic(p, "button", "Agregar firma del representante"); await p.waitForSelector(".aseo-firma-capa"); await esp(300); await dibujar(p);
  await clic(p, ".aseo-firma-acc button", "OK"); await esperar(p, () => !document.querySelector(".aseo-firma-capa"));
  ok("representante: miniatura de la firma y nada pendiente", await p.evaluate(() => document.querySelectorAll(".aseo-firma-mini img").length === 2) && !/Falta/.test(await T(p)));
  ok("el formulario cabe en el ancho del celular (sin desborde horizontal)", await sinDesborde(p));
  await clic(p, "button", "Registrar"); await esperar(p, () => /BAR-000077/.test(document.body.innerText), 20000);
  const c = E.crear;
  ok("crear: envía firmas JPEG (base64 «/9j/») ≤ 56.000 caracteres y el estado del representante", c?.firmas?.auditor?.imagen_b64?.startsWith("/9j/") && c.firmas.auditor.imagen_b64.length < 56000 && c.firmas.representante.estado === "firmo" && c.firmas.representante.nombre === "Maria Representante" && c.firmas.representante.imagen_b64.startsWith("/9j/"), c && Object.keys(c));
  ok("crear (412 px): lleva inicio_dispositivo ISO del momento de abrir el formulario", typeof c?.inicio_dispositivo === "string" && /Z$/.test(c.inicio_dispositivo) && Date.parse(c.inicio_dispositivo) >= tAbrir0 && Date.parse(c.inicio_dispositivo) <= tAbrir1, { ini: c?.inicio_dispositivo, tAbrir0, tAbrir1 });
  ok("crear: no manda nombre, cargo ni hora (los pone el servidor) y lleva 3 fotos", !("nombre" in (c?.firmas?.auditor ?? {})) && c?.fotos?.length === 3 && !JSON.stringify(c).includes("registrado"));
  t = await T(p);
  ok("acta en pantalla: consecutivo, cargo copiado y firmas", /BAR-000077/.test(t) && /Profesional de interventoría/.test(t) && await p.evaluate(() => document.querySelectorAll(".aseo-miniaturas img[alt^=Firma]").length === 2));
  const antes = new Set(readdirSync(DESCARGAS)); await clic(p, "button", "Descargar acta (PDF)"); const f = await archivoNuevo(antes);
  ok("PDF del auditor: nombre AAAAMMDDHHMMSS-SIGLA-NNNNNN.pdf (Bogotá)", f === "20261113103015-BAR-207003.pdf", f);
  if (f) { const x = textoPdf(f); rmSync(join(DESCARGAS, f), { force: true }); ok("PDF del auditor: «Acta de supervisión», «Incidencia», cargo, firmas y sello v2", /ACTA DE SUPERVISI/.test(x) && /INCIDENCIA/.test(x) && !/Resultado/.test(x) && /Profesional de interventor/.test(x) && /Maria Representante/.test(x) && /efefefef/.test(x) && /Firma electr/.test(x), x.slice(0, 300)); }
  await p.close();
}

// =====================================================================  2) SUPERVISOR en escritorio
{
  const p = await sesion("supervisor", { width: 1280, height: 850 });
  await esperar(p, () => /Aseo/.test(document.body.innerText), 15000);
  if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Interventoría de Aseo/.test(document.body.innerText));
  let t = await T(p);
  ok("entrada: «Supervisión y dashboard» activa con su subtítulo y SIN «Gestión de personal»", /Supervisión y dashboard/.test(t) && /Revisión de las actas de supervisión, no conformidades e indicadores/.test(t) && !/Gestión de personal/.test(t), t.slice(0, 300));
  ok("entrada: la tarjeta de supervisión es un botón activo (no «Próximamente»)", await p.evaluate(() => [...document.querySelectorAll("button.campo-formato-activo")].some((b) => /Supervisión y dashboard/.test(b.textContent))));
  await clic(p, "button.campo-formato-activo", "Supervisión y dashboard"); await p.waitForSelector(".tdash");
  t = await T(p);
  ok("cascarón: título, 5 pestañas y «Volver a Aseo»", /Supervisión y dashboard/.test(t) && ["Resumen", "Auditorías", "No conformidades", "Indicadores", "Personal"].every((x) => t.includes(x)) && /Volver a Aseo/.test(t));
  await p.waitForSelector("[data-testid=nc-pendientes]");
  ok("resumen: 2 no conformidades pendientes, con marca roja de tipo", (await p.$eval("[data-testid=nc-pendientes]", (e) => e.textContent)) === "2" && await p.evaluate(() => document.querySelectorAll(".tr-aviso .td-marca-alerta").length >= 2));
  await esperar(p, () => document.querySelectorAll(".tr-aviso").length === 2);
  await p.evaluate(() => document.querySelector(".tr-aviso button.td-boton").click()); await esperar(p, () => document.querySelectorAll(".tr-aviso").length === 1);
  ok("resumen: «Marcar revisada» saca el aviso y deja el mensaje", (await p.$eval("[data-testid=nc-pendientes]", (e) => e.textContent)) === "1" && /Marcada como revisada/.test(await T(p)));
  ok("resumen: el supervisor llama «revisión» a su trabajo (no «supervisar un acta»)", !/supervisar un acta|Supervisó/.test(await T(p)));
  // Auditorías
  await clic(p, ".tdash-tab", "Auditorías"); await p.waitForSelector("table.td-tabla tbody tr[data-auditoria]");
  t = await T(p);
  { const v = await p.evaluate(() => { const th = [...document.querySelectorAll("table.td-tabla thead th")].map((e) => e.textContent.trim()); const f = (n) => [...document.querySelectorAll(`table.td-tabla tbody tr[data-auditoria] td[data-col=${n}]`)].map((e) => e.innerText.replace(/\s+/g, " ").trim()); return { th, ini: f("inicio"), fin: f("fin"), dur: f("duracion") }; });
    ok("escritorio · lista: columnas Inicio, Fin y Duración; Inicio en Bogotá con «(celular)»; «25 min» y «1 h 10 min»; sin inicio «—»", ["Inicio", "Fin", "Duración"].every((x) => v.th.includes(x)) && v.ini[0] === "13/11/2026 10:05 (celular)" && v.fin[0] === "13/11/2026 10:30" && v.dur[0] === "25 min" && v.ini[1] === "—" && v.dur[1] === "—" && v.dur[2] === "1 h 10 min", v);
    await captura(p, "supervision_lista_escritorio.png"); }
  ok("auditorías: columna «Incidencia» (no «Resultado») y filtros de periodo, actividad, modalidad, servicio, turno, barrio, auditor, incidencia", /Incidencia/.test(t) && !/Resultado/.test(t) && ["Periodo", "Actividad", "Modalidad", "Servicio", "Turno", "Barrio", "Auditor"].every((x) => t.includes(x)));
  await p.select("#todas-act", "barrido"); await p.select("#todas-inc", "parcial"); await p.type("#todas-bar", "Centro"); await esp(400);
  const ult = E.regFiltros.at(-1);
  ok("auditorías: los filtros viajan al servidor", ult?.actividad === "barrido" && ult?.incidencia === "parcial" && ult?.barrio === "Centro", ult);
  // Detalle y acta regenerada: SIN CORS → respaldo base64
  await p.evaluate(() => document.querySelector("table.td-tabla tbody tr[data-auditoria] button").click()); await p.waitForSelector(".as-detalle");
  await esperar(p, () => document.querySelectorAll(".as-foto img").length === 2);
  t = await T(p);
  { const dd = await p.evaluate(() => Object.fromEntries(["inicio", "fin", "duracion"].map((k) => [k, document.querySelector(`.as-dl dd[data-campo=${k}]`)?.textContent ?? null])));
    ok("escritorio · detalle: Inicio «13/11/2026 10:05 (celular)», Fin y Duración «25 min»", dd.inicio === "13/11/2026 10:05 (celular)" && dd.fin === "13/11/2026 10:30" && dd.duracion === "25 min", dd);
    await captura(p, "supervision_detalle_escritorio.png"); }
  ok("detalle: incidencia, respuestas, 2 fotos con URL firmada, firmas sin imagen y sello", /Incidencia/.test(t) && /¿Usa los EPP\?/.test(t) && /Profesional de interventoría/.test(t) && /cdcdcd/.test(t) && !(await hay(p, ".as-dl img")));
  E.cors = false; E.llamadas.length = 0; let antes = new Set(readdirSync(DESCARGAS)); await clic(p, "button", "Descargar acta (PDF)"); let f = await archivoNuevo(antes);
  ok("acta regenerada SIN CORS en el Storage: usa la vía de respaldo (foto_base64) y descarga el PDF", E.llamadas.filter((l) => l.accion === "foto_base64").length === 2 && f === "20261113103015-BAR-207003.pdf", { f, llamadas: E.llamadas.map((l) => l.accion) });
  if (f) { const x = textoPdf(f); rmSync(join(DESCARGAS, f), { force: true }); ok("acta regenerada: mismo sello guardado, título, «Incidencia», «Cargo no registrado» y ambas firmas", /ACTA DE SUPERVISI/.test(x) && /cdcdcdcd/.test(x) && /INCIDENCIA/.test(x) && /Cargo no registrado/.test(x) && /Maria Representante/.test(x), x.slice(0, 200)); }
  E.cors = true; E.llamadas.length = 0; antes = new Set(readdirSync(DESCARGAS)); await clic(p, "button", "Descargar acta (PDF)"); f = await archivoNuevo(antes);
  if (f) rmSync(join(DESCARGAS, f), { force: true });
  ok("acta regenerada CON CORS: baja las fotos directo y no pide base64", !!f && E.llamadas.filter((l) => l.accion === "foto_base64").length === 0, E.llamadas.map((l) => l.accion));
  // Revisión y visibilidad desde el detalle
  await clic(p, "button", "Reabrir"); await p.waitForSelector(".td-dialogo"); await p.type(".td-dialogo textarea", "corto");
  ok("reabrir: exige motivo de 10 caracteres (botón deshabilitado con 5)", await p.evaluate(() => [...document.querySelectorAll(".td-dialogo button")].find((b) => /^Reabrir$/.test(b.textContent)).disabled));
  await p.type(".td-dialogo textarea", " y un motivo claro"); await clic(p, ".td-dialogo button", "Reabrir"); await esperar(p, () => /Revisión reabierta/.test(document.body.innerText));
  ok("reabrir: queda «reabierta» en el estado y en el historial", /Reabierta/.test(await T(p)) && E.estados[UUID(1)] === "reabierta");
  await clic(p, "button", "Marcar revisada"); await p.waitForSelector(".td-dialogo"); await clic(p, ".td-dialogo button", "Marcar revisada"); await esperar(p, () => /Marcada como revisada\./.test(document.body.innerText));
  ok("detalle: «Marcar revisada» con nota opcional", E.estados[UUID(1)] === "revisada");
  await clic(p, "button", "Ocultar"); await p.waitForSelector(".td-dialogo"); await p.type(".td-dialogo textarea", "oculta por la prueba del supervisor"); await clic(p, ".td-dialogo button", "Ocultar"); await esperar(p, () => /Oculta|oculta/.test(document.body.innerText) && /Reincluir/.test(document.body.innerText));
  ok("ocultar: queda oculta con «Reincluir» disponible", /Reincluir/.test(await T(p)));
  await clic(p, "button", "Cerrar detalle");
  // Descargas
  await p.select("#todas-ocu", "todos");
  antes = new Set(readdirSync(DESCARGAS)); await clic(p, "button", "Descargar CSV"); f = await archivoNuevo(antes);
  ok("descarga CSV por actividad: nombre sin datos personales", f === "auditorias_barrido_20261113_1044.csv", f);
  if (f) { const csv = readFileSync(join(DESCARGAS, f), "utf8"); ok("CSV: BOM, «Incidencia», pregunta del catálogo, representante sin imagen, cargo no registrado", csv.startsWith("﻿") && /;Incidencia;/.test(csv) && /;¿Usa los EPP\?\r\n/.test(csv) && /Firmó;Maria Representante/.test(csv) && /Cargo no registrado/.test(csv) && !/imagen|b64/i.test(csv), csv.slice(0, 300));
    ok("CSV: columnas Inicio (Bogotá), Duración (min) y Origen del inicio con sus valores", /^\uFEFFConsecutivo;Inicio \(Bogotá\);Fecha y hora de registro \(Bogotá\);Duración \(min\);Origen del inicio;/.test(csv) && /\r\nBAR-000001;13\/11\/2026 10:05;13\/11\/2026 10:30;25,3;Celular;/.test(csv), csv.slice(0, 400)); }
  antes = new Set(readdirSync(DESCARGAS)); await clic(p, "button", "Descargar Excel"); f = await archivoNuevo(antes);
  ok("descarga Excel por actividad (.xlsx, archivo zip válido)", f === "auditorias_barrido_20261113_1044.xlsx" && readFileSync(join(DESCARGAS, f)).subarray(0, 2).toString() === "PK", f);
  ok("las descargas dejaron auditoría (iniciar y cerrar) en el servidor simulado", E.llamadas.filter((l) => l.accion === "descarga_iniciar").length === 2 && E.llamadas.filter((l) => l.accion === "descarga_cerrar").length === 2);
  // Sin actividad: avisa
  await p.select("#todas-act", ""); await clic(p, "button", "Descargar CSV");
  ok("descarga sin actividad: avisa que se descarga por actividad y no llama al servidor", /Elija la actividad/.test(await T(p)));
  // No conformidades
  await clic(p, ".tdash-tab", "No conformidades"); await p.waitForSelector("table.td-tabla"); await esp(700);
  t = await T(p); ok("no conformidades: parte de las pendientes y muestra el conteo", /pendientes/.test(t) && E.regFiltros.at(-1).nc === "pendientes");
  // Indicadores
  await clic(p, ".tdash-tab", "Indicadores"); await p.waitForSelector("[data-testid=ind-auditorias]");
  t = await T(p); ok("indicadores: auditorías, rutas frente al plan, incidencia, tipos de no conformidad y marcas", (await p.$eval("[data-testid=ind-auditorias]", (e) => e.textContent)) === "3" && /1 de 541/.test(t) && /Incidencia/.test(t) && /Forma indebida/.test(t) && /Lejos de la ruta/.test(t));
  // Personal
  await clic(p, ".tdash-tab", "Personal"); await p.waitForSelector(".as-persona");
  ok("personal: aparece la persona sin cargo marcada en rojo", /Sin cargo/.test(await T(p)));
  await p.type(".as-persona input[type=text]", "Profesional de interventoría"); await clic(p, "button", "Guardar cargo"); await esperar(p, () => /Cargo de .* guardado/.test(document.body.innerText));
  ok("personal: guardar el cargo", E.eventos.some((e) => e.tipo === "fijar_cargo" && e.cargo === "Profesional de interventoría"));
  await p.evaluate(() => [...document.querySelectorAll(".as-persona input[type=checkbox]")][0].click()); await esperar(p, () => /Se asignó/.test(document.body.innerText));
  ok("personal: asignar actividad se registra", E.eventos.some((e) => e.tipo === "asignar_actividad" && e.actividad === "barrido"));
  await clic(p, "button", "Desactivar en Aseo"); await p.waitForSelector(".td-dialogo");
  ok("personal: desactivar exige motivo (botón deshabilitado sin motivo)", await p.evaluate(() => [...document.querySelectorAll(".td-dialogo button")].find((b) => /^Desactivar$/.test(b.textContent)).disabled));
  await p.type(".td-dialogo textarea", "desactivada por la prueba de Chrome"); await clic(p, ".td-dialogo button", "Desactivar"); await esperar(p, () => /Desactivada en Aseo/.test(document.body.innerText));
  ok("personal: desactivar se registra", E.eventos.some((e) => e.tipo === "desactivar_aseo" && /prueba de Chrome/.test(e.motivo)));
  // Volver
  await clic(p, "button", "Volver a Aseo"); await esperar(p, () => /Interventoría de Aseo/.test(document.body.innerText)); ok("volver a Aseo desde el cascarón", true);
  await p.close();
}
// =====================================================================  3) SUPERVISOR en celular (sin desborde)
{
  const p = await sesion("supervisor", { width: 412, height: 860, isMobile: true, hasTouch: true });
  await esperar(p, () => /Aseo/.test(document.body.innerText), 15000); if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Supervisión y dashboard/.test(document.body.innerText)); await clic(p, "button.campo-formato-activo", "Supervisión y dashboard"); await p.waitForSelector(".tdash");
  for (const tab of ["Resumen", "Auditorías", "Indicadores", "Personal"]) { await clic(p, ".tdash-tab", tab); await esp(500); ok(`celular: la pestaña ${tab} no desborda el ancho de la página`, await sinDesborde(p)); }
  await p.close();
}
// =====================================================================  4) SUPERVISOR a 380 px: Inicio, Fin y Duración
{
  E.ocultas.clear();                                   // el bloque 2 ocultó la auditoría 1: vuelve a la lista
  const p = await sesion("supervisor", { width: 380, height: 820, isMobile: true, hasTouch: true });
  await esperar(p, () => /Aseo/.test(document.body.innerText), 15000); if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Supervisión y dashboard/.test(document.body.innerText)); await clic(p, "button.campo-formato-activo", "Supervisión y dashboard"); await p.waitForSelector(".tdash");
  await clic(p, ".tdash-tab", "Auditorías"); await p.waitForSelector("table.td-tabla tbody tr[data-auditoria]"); await esp(300);
  const v = await p.evaluate(() => ({ th: [...document.querySelectorAll("table.td-tabla thead th")].map((e) => e.textContent.trim()), ini: document.querySelector("td[data-col=inicio]")?.innerText.replace(/\s+/g, " ").trim(), dur: document.querySelector("td[data-col=duracion]")?.innerText.trim() }));
  ok("380 px · lista: Inicio «(celular)», Fin y Duración, sin desbordar la página", ["Inicio", "Fin", "Duración"].every((x) => v.th.includes(x)) && v.ini === "13/11/2026 10:05 (celular)" && v.dur === "25 min" && await sinDesborde(p), v);
  await captura(p, "supervision_lista_380.png");
  await p.evaluate(() => document.querySelector("table.td-tabla tbody tr[data-auditoria] button").click()); await p.waitForSelector(".as-detalle"); await esp(300);
  const dd = await p.evaluate(() => Object.fromEntries(["inicio", "fin", "duracion"].map((k) => [k, document.querySelector(`.as-dl dd[data-campo=${k}]`)?.textContent ?? null])));
  ok("380 px · detalle: Inicio «(celular)», Fin y Duración «25 min», sin desbordar", dd.inicio === "13/11/2026 10:05 (celular)" && dd.fin === "13/11/2026 10:30" && dd.duracion === "25 min" && await sinDesborde(p), dd);
  await captura(p, "supervision_detalle_380.png");
  await clic(p, "button", "Cerrar detalle"); await p.waitForSelector("table.td-tabla tbody tr[data-auditoria]");
  await p.evaluate(() => document.querySelectorAll("table.td-tabla tbody tr[data-auditoria] button")[1].click()); await p.waitForSelector(".as-detalle"); await esp(300);
  ok("380 px · detalle de una auditoría anterior: «No registrado» y Duración «—»", await p.evaluate(() => /No registrado/.test(document.querySelector(".as-dl dd[data-campo=inicio]").textContent) && document.querySelector(".as-dl dd[data-campo=duracion]").textContent === "—"));
  await p.close();
}
// =====================================================================  5) AUDITOR a 380 px y en escritorio: inicio_dispositivo del momento de abrir
async function hastaFormulario(p) {
  await esperar(p, () => /Barrido|Aseo/.test(document.body.innerText), 15000); if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Interventoría de Aseo/.test(document.body.innerText));
  await clic(p, ".campo-formato-activo", "Barrido"); await esperar(p, () => /Manual/.test(document.body.innerText));
  await clic(p, ".campo-formato-activo", "Manual"); await p.waitForSelector("#aseo-q"); await p.type("#aseo-q", "2010011207003"); await p.waitForSelector(".aseo-ruta");
  const t0 = await p.evaluate(() => Date.now()); await clic(p, ".aseo-ruta"); await p.waitForSelector("input[name=se_realizo]"); const t1 = await p.evaluate(() => Date.now());
  return { t0, t1 };
}
async function llenarFormulario(p) {
  await clic(p, "label.aseo-opcion", "Sí");
  for (const n of ["sst_herramientas", "sst_epp"]) await p.evaluate((nm) => [...document.querySelectorAll(`input[name="aseo-c-${nm}"]`)].find((i) => i.value === "si").click(), n);
  for (let i = 0; i < 3; i++) { await clic(p, "button", "Tomar foto"); await p.waitForSelector(".campo-camara"); await esperar(p, () => !document.querySelector(".campo-capturar")?.disabled, 10000); await p.click(".campo-capturar"); await esperar(p, () => !document.querySelector(".campo-camara"), 10000); }
  await clic(p, "button", "Agregar firma"); await p.waitForSelector(".aseo-firma-capa"); await esp(300); await dibujar(p); await clic(p, ".aseo-firma-acc button", "OK"); await esperar(p, () => !document.querySelector(".aseo-firma-capa"));
  await p.evaluate(() => [...document.querySelectorAll("input[name=rep_estado]")].find((i) => i.value === "sin_representante").click());
  await esperar(p, () => !/Falta/.test(document.body.innerText));
}
const botonEnviar = (p) => p.evaluate(() => { const b = [...document.querySelectorAll("button")].find((x) => /^(Registrar|Reintentar)$/.test(x.textContent.trim())); b?.click(); return b?.textContent.trim() ?? null; });
const MSG_ADEL = "La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.";
for (const [nombre, vp] of [["380 px", { width: 380, height: 820, isMobile: true, hasTouch: true }], ["escritorio", { width: 1280, height: 850 }]]) {
  const p = await sesion("auditor", vp); E.cuerpos.length = 0; E.colaCrear.length = 0;
  const { t0, t1 } = await hastaFormulario(p);
  if (nombre === "380 px") await captura(p, "auditor_formulario_380.png");
  await esp(1500); await llenarFormulario(p);
  // 1.º envío: el servidor falla (500) → «Reintentar»; 2.º: la base rechaza la hora (adelantada); se corrige el reloj (−10 min) y 3.º: registra
  E.colaCrear.push({ status: 500, body: { error: "El servidor no pudo atender" } }, { status: 400, body: { error: MSG_ADEL } });
  const tEnviar = await p.evaluate(() => Date.now());
  await botonEnviar(p); await esperar(p, () => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Reintentar"), 15000);
  const b1 = E.cuerpos[0];
  ok(`auditor ${nombre}: el cuerpo de crear lleva inicio_dispositivo (ISO con zona) del momento de ABRIR, no del de enviar`, typeof b1?.inicio_dispositivo === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(b1.inicio_dispositivo) && Date.parse(b1.inicio_dispositivo) >= t0 && Date.parse(b1.inicio_dispositivo) <= t1 && Date.parse(b1.inicio_dispositivo) < tEnviar - 1000, { ini: b1?.inicio_dispositivo, t0, t1, tEnviar });
  ok(`auditor ${nombre}: inicio_dispositivo va fuera de «datos» y sin claves con «fecha» u «hora»`, !("inicio_dispositivo" in (b1?.datos ?? {})) && !Object.keys(b1 ?? {}).some((k) => /fecha|hora/i.test(k)));
  await esp(400); await botonEnviar(p); await esperar(p, (m) => document.body.innerText.includes(m), 15000, MSG_ADEL);
  ok(`auditor ${nombre}: el reintento manda EXACTAMENTE el mismo inicio_dispositivo`, E.cuerpos.length === 2 && E.cuerpos[1].inicio_dispositivo === b1.inicio_dispositivo && E.cuerpos[1].auditoria_id === b1.auditoria_id);
  ok(`auditor ${nombre}: el rechazo por la hora del celular se muestra con el texto exacto y lo escrito sigue (3 fotos)`, (await T(p)).includes(MSG_ADEL) && await p.evaluate(() => document.querySelectorAll(".aseo-mini img").length === 3));
  await p.evaluate(() => { const o = Date.now.bind(Date); Date.now = () => o() - 600000; });      // la persona corrige el reloj: estaba 10 min adelantado
  await botonEnviar(p); await esperar(p, () => /BAR-000077/.test(document.body.innerText), 20000);
  const b3 = E.cuerpos[2], d = b3 ? Date.parse(b1.inicio_dispositivo) - Date.parse(b3.inicio_dispositivo) : NaN;
  ok(`auditor ${nombre}: tras corregir el reloj, el inicio se recalcula UNA vez (hora corregida − tiempo desde que se abrió) y registra`, E.cuerpos.length === 3 && Math.abs(d - 600000) < 2000 && /BAR-000077/.test(await T(p)), { d, b3: b3?.inicio_dispositivo });
  ok(`auditor ${nombre}: sin desborde horizontal`, await sinDesborde(p));
  await p.close();
}
// =====================================================================  6) ESTILO («aseo-estilo»): todas las pantallas a 390 y 1280 px, como administrador
const ASEO_RGB = "rgb(138, 74, 31)";
const estilo = (p) => p.evaluate(() => {
  const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== "hidden"; };
  const raizM = [...document.querySelectorAll(".aseo-modulo")]; const todos = raizM.flatMap((r) => [r, ...r.querySelectorAll("*")]).filter((e) => !e.closest(".maplibregl-map, svg") && vis(e));
  const fuentes = [...new Set(todos.map((e) => getComputedStyle(e).fontFamily.split(",")[0].replace(/"/g, "").trim()))];
  const degradados = todos.filter((e) => /gradient/.test(getComputedStyle(e).backgroundImage)).length;
  const bajos = todos.filter((e) => e.matches("button, select, input:not([type=radio]):not([type=checkbox]):not([type=file]), textarea") && e.getBoundingClientRect().height < 43.5).map((e) => `${e.tagName}.${e.className}:${Math.round(e.getBoundingClientRect().height)}`);
  const emojis = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(raizM.map((r) => r.innerText).join(" "));
  return { hayRaiz: raizM.length > 0, fuentes, degradados, bajos, emojis, desborde: document.documentElement.scrollWidth > window.innerWidth + 1 };
});
const css = (p, sel, prop) => p.evaluate((s, pr) => { const e = document.querySelector(s); return e ? getComputedStyle(e)[pr] : null; }, sel, prop);
for (const ancho of [390, 1280]) {
  const tag = `estilo ${ancho} px`; const vp = ancho === 390 ? { width: 390, height: 844, isMobile: true, hasTouch: true } : { width: 1280, height: 850 };
  const p = await sesion("admin", vp); const vistos = [];
  const foto = async (n, completa = true) => { await esp(250);
    if (CAPTURAS) {      // la página de Aseo desplaza su propio contenido: para verla entera se alarga la ventana un momento
      const alto = completa ? await p.evaluate(() => { const c = document.querySelector(".tec-pagina, .tdash"); return c ? Math.ceil(c.getBoundingClientRect().top + c.scrollHeight) : 0; }) : 0;
      if (alto > vp.height) { await p.setViewport({ ...vp, height: Math.min(alto, 6000) }); await esp(250); }
      await p.screenshot({ path: join(CAPTURAS, `estilo_${n}_${ancho}.png`), fullPage: completa });
      if (alto > vp.height) { await p.setViewport(vp); await esp(150); }
    } if (!ANTES) vistos.push([n, await estilo(p)]); };
  await esperar(p, () => /Barrido|Aseo/.test(document.body.innerText), 15000); if (await hay(p, ".area-tarjeta", "Aseo")) await clic(p, ".area-tarjeta", "Aseo");
  await esperar(p, () => /Administración de rutas/.test(document.body.innerText)); await foto("01_inicio");
  if (!ANTES) {
    const cols = (await css(p, ".campo-formatos", "gridTemplateColumns")).split(" ").length;
    ok(`${tag}: inicio en rejilla de ${ancho === 390 ? "una columna" : "4 columnas"}`, cols === (ancho === 390 ? 1 : 4), cols);
    ok(`${tag}: las tarjetas del inicio son blancas, con borde izquierdo de 5 px del color de Aseo y radio de 12 a 14 px`, await p.evaluate((c) => [...document.querySelectorAll("button.campo-formato-activo")].every((b) => { const e = getComputedStyle(b);
      return e.borderLeftColor === c && e.borderLeftWidth === "5px" && e.backgroundColor === "rgb(255, 255, 255)" && parseFloat(e.borderTopLeftRadius) >= 12 && parseFloat(e.borderTopLeftRadius) <= 14 && b.getBoundingClientRect().height >= 68; }), ASEO_RGB));
  }
  await clic(p, ".campo-formato-activo", "Barrido"); await esperar(p, () => /Elija la modalidad/.test(document.body.innerText)); await foto("02_modalidad");
  if (!ANTES) ok(`${tag}: el encabezado de la sección es una barra del color de Aseo con el texto blanco`, await css(p, ".campo-cab", "backgroundColor") === ASEO_RGB && await css(p, ".campo-cab h1", "color") === "rgb(255, 255, 255)");
  await clic(p, ".campo-formato-activo", "Manual"); await p.waitForSelector("#aseo-q"); await foto("03_rutas");
  E.mapaAbierto = true;      // el mapa pide su fondo a internet y la prueba no tiene red: sus errores de consola no cuentan
  await clic(p, "button", "Elegir en el mapa"); await esperar(p, () => !!document.querySelector(".aseo-mapa-caja, .aseo-aviso"), 15000); await esp(1500); await foto("04_rutas_mapa");
  if (!ANTES) ok(`${tag}: el mapa de rutas queda neutro (su caja no lleva el color de Aseo; sí sus controles)`, await p.evaluate((c) => { const m = document.querySelector(".aseo-mapa-caja"); if (!m) return true; const b = m.querySelector(".aseo-mapa-ctl button");
    return getComputedStyle(m).borderTopColor !== c && getComputedStyle(m).backgroundColor !== c && (!b || getComputedStyle(b).color === c || b.disabled); }, ASEO_RGB));
  await clic(p, "button", "Ocultar el mapa"); await esp(300); E.mapaAbierto = false; await p.type("#aseo-q", "2010011207003"); await p.waitForSelector(".aseo-ruta"); await foto("04b_rutas_busqueda"); await clic(p, ".aseo-ruta"); await p.waitForSelector("input[name=se_realizo]"); await foto("05_formulario_vacio");
  await clic(p, "label.aseo-opcion", "Sí"); await esperar(p, () => [...document.querySelectorAll("button")].some((b) => /Tomar foto/.test(b.textContent)));
  if (!ANTES) ok(`${tag}: «Tomar foto» lleva el ícono de cámara y el botón principal es del color de Aseo`, await p.evaluate((c) => { const b = [...document.querySelectorAll("button")].find((x) => /Tomar foto/.test(x.textContent));
    return !!b.querySelector("svg[data-icono=camara]") && b.textContent.trim() === "Tomar foto" && getComputedStyle(b).backgroundColor === c && getComputedStyle(b).color === "rgb(255, 255, 255)"; }, ASEO_RGB));
  await clic(p, "button", "Tomar foto"); await p.waitForSelector(".campo-camara"); await esperar(p, () => !document.querySelector(".campo-capturar")?.disabled, 10000); await foto("06_camara", false);
  await clic(p, ".campo-camara-acc button", "Cancelar"); await esperar(p, () => !document.querySelector(".campo-camara"));
  await clic(p, "button", "Agregar firma"); await p.waitForSelector(".aseo-firma-capa"); await esp(300); await dibujar(p); await foto("07_firma", false);
  if (!ANTES) ok(`${tag}: la firma conserva su lienzo blanco; «OK» es del color de Aseo`, await css(p, ".aseo-firma-lienzo", "backgroundColor") === "rgb(255, 255, 255)" && await css(p, ".aseo-firma-acc .tec-boton", "backgroundColor") === ASEO_RGB);
  await clic(p, ".aseo-firma-acc button", "Cancelar"); await esperar(p, () => !document.querySelector(".aseo-firma-capa"));
  await clic(p, "label.aseo-opcion", "Sí"); await llenarFormulario(p); await foto("08_formulario_lleno");
  if (!ANTES) ok(`${tag}: cada sección del formulario es una tarjeta (blanca, borde izquierdo del color de Aseo, radio 12 px)`, await p.evaluate((c) => { const f = [...document.querySelectorAll(".aseo-hoja > fieldset.campo-fieldset, .aseo-hoja > .campo-auto")];
    return f.length >= 4 && f.every((x) => { const e = getComputedStyle(x); return e.borderLeftColor === c && e.borderLeftWidth === "5px" && e.backgroundColor === "rgb(255, 255, 255)" && e.borderTopLeftRadius === "12px"; }); }, ASEO_RGB));
  await botonEnviar(p); await esperar(p, () => /BAR-000077/.test(document.body.innerText), 20000); await foto("09_acta_registrada");
  await clic(p, ".aseo-acciones button", "Salir"); await esperar(p, () => /Administración de rutas/.test(document.body.innerText));
  await clic(p, ".campo-formato-activo", "Administración de rutas"); await p.waitForSelector(".aseo-pestanas");
  for (const [i, n] of ["Plan operativo", "Capa de rutas", "Barrios", "Historial"].entries()) { await clic(p, ".aseo-pestana", n); await esp(500); await foto(`1${i}_admin_${n.toLowerCase().replace(/ /g, "_")}`); }
  if (!ANTES) ok(`${tag}: la pestaña elegida de la administración va en el color de Aseo`, await css(p, ".aseo-pestana-on", "color") === ASEO_RGB);
  await clic(p, ".campo-cab button", "Aseo"); await esperar(p, () => /Supervisión y dashboard/.test(document.body.innerText));
  await clic(p, "button.campo-formato-activo", "Supervisión y dashboard"); await p.waitForSelector(".tdash"); await esperar(p, () => !!document.querySelector(".tr-aviso, .tr-vacio"), 8000); await foto("20_supervision_resumen");
  if (!ANTES) ok(`${tag}: el encabezado de Supervisión y dashboard es del color de Aseo y sus botones principales también`, await css(p, ".tdash-cab", "backgroundColor") === ASEO_RGB);
  await clic(p, ".tdash-tab", "Auditorías"); await p.waitForSelector("table.td-tabla tbody tr[data-auditoria]"); await foto("21_supervision_auditorias");
  await p.evaluate(() => document.querySelector("table.td-tabla tbody tr[data-auditoria] button").click()); await p.waitForSelector(".as-detalle"); await esp(600); await foto("22_supervision_detalle");
  await clic(p, "button", "Cerrar detalle"); await clic(p, ".tdash-tab", "No conformidades"); await esp(700); await foto("23_supervision_no_conformidades");
  await clic(p, ".tdash-tab", "Indicadores"); await esperar(p, () => !!document.querySelector(".as-barra, .td-cajita"), 8000); await esp(300); await foto("24_supervision_indicadores");
  await clic(p, ".tdash-tab", "Personal"); await esperar(p, () => !!document.querySelector(".as-persona"), 8000); await foto("25_supervision_personal");
  if (!ANTES) {
    ok(`${tag}: todas las pantallas llevan los tokens de Aseo (raíz «aseo-modulo»)`, vistos.every(([, e]) => e.hayRaiz), vistos.filter(([, e]) => !e.hayRaiz).map(([n]) => n));
    ok(`${tag}: una sola fuente (Arial; Courier solo en los códigos)`, vistos.every(([, e]) => e.fuentes.every((f) => /^(Arial|Courier New)$/.test(f))), [...new Set(vistos.flatMap(([, e]) => e.fuentes))]);
    ok(`${tag}: sin degradados ni emojis`, vistos.every(([, e]) => e.degradados === 0 && !e.emojis), vistos.filter(([, e]) => e.degradados || e.emojis).map(([n]) => n));
    ok(`${tag}: botones y campos de 44 px o más`, vistos.every(([, e]) => e.bajos.length === 0), vistos.filter(([, e]) => e.bajos.length).map(([n, e]) => `${n}: ${e.bajos.join(" ")}`));
    ok(`${tag}: ninguna pantalla se desborda a lo ancho`, vistos.every(([, e]) => !e.desborde), vistos.filter(([, e]) => e.desborde).map(([n]) => n));
  }
  await p.close();
}
ok("ninguna pantalla produjo errores de JavaScript ni de consola", errores.length === 0, errores);
await navegador.close(); mock.close(); srv.close(); rmSync(dist, { recursive: true, force: true });
console.log(fallas === 0 ? `RESULTADO: ${total} de ${total} pruebas correctas — SIN FALLAS` : `RESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas} FALLA(S)`);
process.exit(fallas === 0 ? 0 : 1);
