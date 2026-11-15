// Técnica · Fase 1 · Corte 0b · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada (componentes reales) → Edge geoportal-tecnica REAL (Deno, en 127.0.0.1) → base SIMULADA en Node que imita las reglas de las RPC vivas
//   (tecnica.f_resolver_fecha_muestra: dias_atras_max por formulario, nunca futura, hora futura del mismo día; idempotencia por clave_envio).
// Regresión completa de Entrada (con dosis), Salida (planta y tanque) y Muestreo, y lo nuevo: la fecha de la muestra en Muestreo (hasta 7 días atrás). A 390 px y en escritorio.
//   node scripts/prueba_chrome_tec_c0b.mjs <chrome> <puppeteer-core> <deno> <carpeta supabase/functions de geoportal-web> [carpeta_capturas]
// No prueba: la base real (las reglas de fecha se imitan aquí; las prueban las suites SQL del Corte 2-A, ya en producción), ni un celular físico.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES] = process.argv.slice(2, 6);
const CAP = resolve(process.argv[6] || join(tmpdir(), "capturas_tec_c0b"));
if (!CHROME || !PUP || !DENO || !FUNCIONES) { console.error("Uso: node scripts/prueba_chrome_tec_c0b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54991, P_EDGE = 54992;

// ---------- fechas de Bogotá (UTC−5 todo el año) ----------
const bog = (ms = Date.now()) => new Date(ms - 5 * 3_600_000);
const dia = (n) => bog(Date.now() + n * 86_400_000).toISOString().slice(0, 10);
const HOY = dia(0);
const dmy = (iso) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;
const horaMenos = (min) => bog(Date.now() - min * 60_000).toISOString().slice(11, 16);

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_tec_c0b_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css";
    import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    const q = new URLSearchParams(location.search);
    if (q.get("limpio") === "1") { try { localStorage.clear(); } catch {} }
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="operario@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Base simulada (Auth + PostgREST) con las reglas de las RPC vivas ----------
const DIAS = { entrada: 0, salida: 0, muestreo: 7 };          // tecnica.formularios_config (semilla del Corte 2-A)
const PLANTAS = [{ codigo: "zt_norte", nombre: "ZT Norte" }, { codigo: "zt_sur", nombre: "ZT Sur" }];
const TANQUES = ["TAN-01", "TAN-02", "TAN-03", "TAN-04"].map((c, i) => ({ codigo: c, nombre: `ZT Tanque ${i + 1}`, tipo: "tanque", planta: null }));
const MUES = Array.from({ length: 27 }, (_, i) => { const n = String(i + 1).padStart(2, "0"); return { codigo: `MUE-${n}`, nombre: `ZT Punto ${n}`, tipo: "muestreo", planta: null, zona: ["norte", "sur", "medio"][i % 3], orden: i + 1 }; });
const v = (codigo, nombre, unidad, alcance, extra = {}) => ({ codigo, nombre, unidad, categoria: "x", decimales: 2, orden: 0, obligatoria: false, alcance, punto: null, ...extra });
const DEFS = {
  entrada: { variables: [v("caudal_qi", "Caudal de entrada", "L/s", "por_planta"), v("turbiedad_cruda", "Turbiedad del agua cruda", "UNT", "ambas_plantas")], plantas: PLANTAS, puntos: [] },
  salida: { variables: [v("cloro_salida", "Cloro de salida", "mg/L", "por_planta"), v("cloro_libre_tanque", "Cloro libre", "mg/L", "por_punto", { tipo_punto: "tanque", puntos: TANQUES.map((t) => t.codigo) })], plantas: PLANTAS, puntos: TANQUES },
  muestreo: { variables: [v("ph", "pH", "unidades", "por_punto", { tipo_punto: "muestreo", puntos: MUES.map((p) => p.codigo) }), v("turbiedad", "Turbiedad", "UNT", "por_punto", { tipo_punto: "muestreo", puntos: MUES.map((p) => p.codigo) })], plantas: [], puntos: MUES },
};
for (const d of Object.values(DEFS)) d.variables.forEach((x, i) => (x.orden = i + 1));
const NOMBRES = { entrada: "Entrada", salida: "Salida", muestreo: "Muestreo" };
const rpcs = [], desconocidas = [], porClave = new Map();
const msgU = (status, message) => ({ status, cuerpo: { code: status === 403 ? "42501" : "22023", message, hint: "msg_usuario" } });
function resolverFecha(form, hora, fecha) {          // copia de la regla de tecnica.f_resolver_fecha_muestra
  if (fecha == null) return { fecha: HOY };
  const n = DIAS[form] ?? 0;
  if (n === 0) return { error: msgU(400, "Este formulario no admite elegir la fecha de la muestra: la fija el servidor.") };
  if (fecha > HOY) return { error: msgU(400, "La fecha de la muestra no puede ser futura.") };
  if (fecha < dia(-n)) return { error: msgU(400, `La fecha de la muestra no puede ser anterior al ${dmy(dia(-n))} (máximo ${n} días atrás).`) };
  if (fecha === HOY && hora > horaMenos(-5)) return { error: msgU(400, "La hora de la muestra es posterior a la hora actual. Revise la hora.") };
  return { fecha };
}
function rpc(fn, a) {
  rpcs.push({ fn, args: a });
  switch (fn) {
    case "geoportal_tec_mis_formularios": return { perfil: "operador", formularios: Object.keys(DEFS).map((k) => ({ clave: k, nombre: NOMBRES[k], descripcion: "", con_campos: true })) };
    case "geoportal_tec_obtener_formulario": { const k = a.p_formulario; const d = DEFS[k];
      return { formulario: { clave: k, nombre: NOMBRES[k], descripcion: `Formulario ${NOMBRES[k]}` }, fecha_hoy: HOY, hora_propuesta: horaMenos(15), dias_atras_max: DIAS[k], fecha_minima: dia(-DIAS[k]), plantas: d.plantas, puntos: d.puntos, variables: d.variables }; }
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_listar_quimicos": return a.p_formulario === "entrada" ? { formulario: "entrada", max_ppm: 1000, max_nombre: 60, opciones: [{ codigo: "pac", nombre: "Policloruro de aluminio", pide_nombre: false, predeterminado: true }] } : { formulario: a.p_formulario, max_ppm: 1000, max_nombre: 60, opciones: [] };
    case "geoportal_tec_registrar_medicion":
    case "geoportal_tec_registrar_medicion_dosis": {
      const f = resolverFecha(a.p_formulario, a.p_hora_muestra, a.p_fecha_muestra ?? null);
      if (f.error) return f.error;
      if (porClave.has(a.p_clave_envio)) return { ...porClave.get(a.p_clave_envio), duplicado: true };
      const r = { lote_id: `00000000-0000-4000-8000-${String(porClave.size + 1).padStart(12, "0")}`, formulario: a.p_formulario, fecha_muestra: f.fecha, hora_muestra: a.p_hora_muestra, guardados: a.p_valores.length, duplicado: false, ...(fn.endsWith("_dosis") ? { dosis_guardada: true } : {}) };
      porClave.set(a.p_clave_envio, r); return r;
    }
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || u.pathname.startsWith("/paquete")) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  let cuerpo = ""; req.on("data", (c) => (cuerpo += c));
  req.on("end", () => {
    if (u.pathname === "/auth/v1/user") return (req.headers.authorization ?? "").startsWith("Bearer tok-") ? json(200, { id: "u-prueba", email: "prueba.tec.operario@emdupar.gov.co" }) : json(401, {});
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      const r = rpc(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edge REAL en Deno ----------
const servir = join(dir, "servir_edge.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); let h: any;
(Deno as any).serve = (x: any) => { h = x; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edge lista"); } }, (r: Request) => h(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edge lista/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).slice(0, 400) }); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO"] });
const errores = [];
const ultimo = (fn) => [...rpcs].reverse().find((r) => r.fn.startsWith(fn));
const registros = () => rpcs.filter((r) => r.fn.startsWith("geoportal_tec_registrar_medicion"));
async function abrir(ancho, limpio = true) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${ancho}: ${e.message}`));
  p.on("console", (m) => { if (m.type() === "error" && !/Failed to load resource: the server responded with a status of 400/.test(m.text())) errores.push(`${ancho} consola: ${m.text()}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=op${limpio ? "&limpio=1" : ""}`); await p.waitForFunction(() => window.__listo === true);
  await p.waitForSelector(".tec-chips"); return p;
}
const texto = (p) => p.evaluate(() => document.body.innerText);
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t)); if (!b) return false; b.click(); return true; }, sel, t);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const esperarTexto = (p, re, ms = 8000) => p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source);
/** Pone el valor de un <input> como lo haría la persona (el setter nativo + evento input, para que React lo vea). */
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
async function abrirForm(p, nombre, re) { await clicTexto(p, ".tec-chip-form", nombre); await esperarTexto(p, re); }
async function guardarYConfirmar(p) {
  await clicTexto(p, "button", "Guardar registro");
  try { await esperarTexto(p, /Va a guardar|Confirmar y guardar/); } catch (e) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error("sin confirmación; la pantalla dice: " + (await texto(p)).slice(0, 1500)); }
  const conf = await texto(p);
  await clicTexto(p, "button", "Confirmar y guardar");
  await p.waitForFunction(() => !/Guardando…/.test(document.body.innerText) && /(✔|Registro guardado|registros guardados|No se pudo guardar|No se guardó)/.test(document.body.innerText), { timeout: 10000 });
  return conf;
}
const fechaSoloLectura = (p) => p.evaluate(() => { const el = document.getElementById("tec-fecha"); return el ? { tipo: el.type, ro: el.readOnly, valor: el.value } : null; });

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  // ===== Entrada (FormularioCaptura, no cambia) =====
  let p = await abrir(ancho);
  await abrirForm(p, "Entrada", /Caudal de entrada/);
  let f = await fechaSoloLectura(p);
  ok(`${tag} Entrada: fecha de solo lectura «Hoy · ${dmy(HOY)}» y «Solo se puede registrar el día de hoy.»`, f && f.tipo === "text" && f.ro && f.valor === `Hoy · ${dmy(HOY)}` && /Solo se puede registrar el día de hoy\./.test(await texto(p)), JSON.stringify(f));
  ok(`${tag} Entrada: sin selector de fecha`, !(await p.$('input[type="date"]')));
  await p.type('input[id^="tec-c-caudal_qi"]', "120,5"); await p.type('input[id^="tec-c-turbiedad_cruda"]', "15");
  await p.evaluate(() => { const d = document.querySelector("details.tec-dosis"); if (d) d.open = true; });
  await p.waitForSelector('input[id^="tec-c-dosis.ppm"]'); await p.type('input[id^="tec-c-dosis.ppm"]', "22");
  await p.screenshot({ path: join(CAP, `entrada_lleno_${ancho}.png`), fullPage: true });
  let n0 = registros().length;
  let conf = await guardarYConfirmar(p);
  let r = ultimo("geoportal_tec_registrar_medicion");
  ok(`${tag} Entrada: confirmación «Muestra de hoy, ${dmy(HOY)}»`, conf.includes(`Muestra de hoy, ${dmy(HOY)}`), conf.slice(0, 300));
  ok(`${tag} Entrada con dosis: la Edge llama a la envoltura de dosis, SIN p_fecha_muestra`, registros().length === n0 + 1 && r.fn === "geoportal_tec_registrar_medicion_dosis" && !("p_fecha_muestra" in r.args) && r.args.p_dosis?.ppm === 22 && r.args.p_planta === "zt_norte", JSON.stringify(r?.args));
  ok(`${tag} Entrada: guardado, con la hora de inicio`, /Registro guardado/.test(await texto(p)) && typeof r.args.p_inicio_dispositivo === "string");
  await p.screenshot({ path: join(CAP, `entrada_guardado_${ancho}.png`), fullPage: true });
  ok(`${tag} Entrada: sin desborde horizontal`, await sinDesborde(p));

  // ===== Salida (FormularioPorLugar sin rango: igual que antes) =====
  await abrirForm(p, "Salida", /Cloro de salida/);
  f = await fechaSoloLectura(p);
  ok(`${tag} Salida: fecha de solo lectura y «Solo se puede registrar el día de hoy.» (sin selector)`, f && f.tipo === "text" && f.ro && f.valor === `Hoy · ${dmy(HOY)}` && !(await p.$('input[type="date"]')) && /Solo se puede registrar el día de hoy\./.test(await texto(p)), JSON.stringify(f));
  await p.type('input[id="tec-c-cloro_salida@zt_norte"]', "1,4");
  await p.select("select", "TAN-02"); await p.waitForSelector('input[id="tec-c-cloro_libre_tanque@TAN-02"]'); await p.type('input[id="tec-c-cloro_libre_tanque@TAN-02"]', "0,9");
  n0 = registros().length;
  conf = await guardarYConfirmar(p);
  const sal = registros().slice(n0);
  ok(`${tag} Salida: confirmación «Muestra de hoy, ${dmy(HOY)}» (texto de siempre)`, conf.includes(`Muestra de hoy, ${dmy(HOY)}`) && !/Se registra hoy/.test(conf), conf.slice(0, 300));
  ok(`${tag} Salida: dos registros (planta y tanque), ninguno con p_fecha_muestra`, sal.length === 2 && sal.every((x) => x.fn === "geoportal_tec_registrar_medicion" && !("p_fecha_muestra" in x.args)) && sal.some((x) => x.args.p_planta === "zt_norte") && sal.some((x) => x.args.p_punto === "TAN-02"), JSON.stringify(sal.map((x) => x.args)));
  ok(`${tag} Salida: «2 registros guardados»`, /2 registros guardados/.test(await texto(p)));
  ok(`${tag} Salida: sin desborde horizontal`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `salida_guardado_${ancho}.png`), fullPage: true });

  // ===== Muestreo: selector de fecha =====
  await abrirForm(p, "Muestreo", /Puntos de muestreo/);
  const sel = await p.evaluate(() => { const el = document.getElementById("tec-fecha"); return el ? { tipo: el.type, min: el.min, max: el.max, valor: el.value } : null; });
  ok(`${tag} Muestreo: selector de fecha de ${dmy(dia(-7))} a ${dmy(HOY)}, por omisión hoy`, sel && sel.tipo === "date" && sel.min === dia(-7) && sel.max === HOY && sel.valor === HOY, JSON.stringify(sel));
  ok(`${tag} Muestreo: ayuda «hasta 7 días atrás … No puede ser futura.»`, /hasta 7 días atrás \(desde el \d\d\/\d\d\/\d{4}\), porque los resultados del laboratorio llegan después\. No puede ser futura\./.test(await texto(p)));
  ok(`${tag} Muestreo: ya no dice «Solo se puede registrar el día de hoy.»`, !/Solo se puede registrar el día de hoy/.test(await texto(p)));
  await p.screenshot({ path: join(CAP, `muestreo_vacio_${ancho}.png`), fullPage: true });
  // (a) hoy
  await p.select("select", "MUE-03"); await p.waitForSelector('input[id="tec-c-ph@MUE-03"]'); await p.type('input[id="tec-c-ph@MUE-03"]', "7,4");
  n0 = registros().length;
  conf = await guardarYConfirmar(p);
  r = ultimo("geoportal_tec_registrar_medicion");
  ok(`${tag} Muestreo hoy: confirmación «Muestra tomada hoy, ${dmy(HOY)} … Se registra hoy»`, conf.includes(`Muestra tomada hoy, ${dmy(HOY)}`) && conf.includes(`Se registra hoy, ${dmy(HOY)}`), conf.slice(0, 300));
  ok(`${tag} Muestreo hoy: p_fecha_muestra = hoy, punto MUE-03, sin planta`, registros().length === n0 + 1 && r.args.p_fecha_muestra === HOY && r.args.p_punto === "MUE-03" && r.args.p_planta === null, JSON.stringify(r?.args));
  // (b) hace 3 días
  await poner(p, "#tec-fecha", dia(-3));
  await esperarTexto(p, /Muestra tomada el \d\d/);
  ok(`${tag} Muestreo: al elegir otra fecha, la pista «… (hace 3 días)»`, (await texto(p)).includes(`Muestra tomada el ${dmy(dia(-3))} (hace 3 días).`));
  await p.select("select", "MUE-10"); await p.waitForSelector('input[id="tec-c-turbiedad@MUE-10"]'); await p.type('input[id="tec-c-turbiedad@MUE-10"]', "0,35");
  await p.screenshot({ path: join(CAP, `muestreo_hace3_${ancho}.png`), fullPage: true });
  n0 = registros().length;
  await clicTexto(p, "button", "Guardar registro"); await esperarTexto(p, /Confirmar y guardar/);
  await p.screenshot({ path: join(CAP, `muestreo_confirmacion_${ancho}.png`), fullPage: true });
  conf = await texto(p);
  await clicTexto(p, "button", "Confirmar y guardar");
  await p.waitForFunction(() => /Registro guardado/.test(document.body.innerText), { timeout: 10000 });
  r = ultimo("geoportal_tec_registrar_medicion");
  ok(`${tag} Muestreo hace 3 días: confirmación con las dos fechas (tomada el ${dmy(dia(-3))}, se registra hoy)`, conf.includes(`Muestra tomada el ${dmy(dia(-3))} (hace 3 días)`) && conf.includes(`Se registra hoy, ${dmy(HOY)}`), conf.slice(0, 300));
  ok(`${tag} Muestreo hace 3 días: p_fecha_muestra = ${dia(-3)}, punto MUE-10`, registros().length === n0 + 1 && r.args.p_fecha_muestra === dia(-3) && r.args.p_punto === "MUE-10", JSON.stringify(r?.args));
  ok(`${tag} Muestreo hace 3 días: el estado de la tarjeta dice la fecha`, (await texto(p)).includes(`muestra tomada el ${dmy(dia(-3))} (hace 3 días), a las`), (await texto(p)).match(/valor(es)? guardados?[^\n]*/)?.[0]);
  ok(`${tag} Muestreo: tras guardar, la fecha elegida se conserva`, (await p.$eval("#tec-fecha", (e) => e.value)) === dia(-3));
  await p.screenshot({ path: join(CAP, `muestreo_guardado_hace3_${ancho}.png`), fullPage: true });
  // (c) hace 7 días (el límite) — vale
  await poner(p, "#tec-fecha", dia(-7));
  await p.select("select", "MUE-20"); await p.waitForSelector('input[id="tec-c-ph@MUE-20"]'); await p.type('input[id="tec-c-ph@MUE-20"]', "7,1");
  n0 = registros().length; await guardarYConfirmar(p); r = ultimo("geoportal_tec_registrar_medicion");
  ok(`${tag} Muestreo hace 7 días (el límite): se guarda`, registros().length === n0 + 1 && r.args.p_fecha_muestra === dia(-7) && /Registro guardado/.test(await texto(p)), JSON.stringify(r?.args));
  // (d) hace 8 días — la pantalla lo detiene sin enviar
  await poner(p, "#tec-fecha", dia(-8));
  await p.select("select", "MUE-21"); await p.waitForSelector('input[id="tec-c-ph@MUE-21"]'); await p.type('input[id="tec-c-ph@MUE-21"]', "7");
  n0 = rpcs.length; await clicTexto(p, "button", "Guardar registro"); await esperarTexto(p, /Revise los campos marcados/);
  const foco = await p.waitForFunction(() => document.activeElement?.id === "tec-fecha", { timeout: 3000 }).then(() => "tec-fecha", async () => p.evaluate(() => document.activeElement?.id));   // el foco se mueve en un setTimeout(0)
  ok(`${tag} Muestreo hace 8 días: error en la fecha, el foco va a la fecha y no se envía nada`, (await texto(p)).includes("La fecha de la muestra puede ser hasta 7 días atrás (desde el") && rpcs.length === n0 && foco === "tec-fecha", foco);
  // (e) mañana — la pantalla lo detiene sin enviar
  await poner(p, "#tec-fecha", dia(1));
  n0 = rpcs.length; await clicTexto(p, "button", "Guardar registro"); await esperarTexto(p, /no puede ser futura\.$|no puede ser futura/);
  ok(`${tag} Muestreo mañana: «La fecha de la muestra no puede ser futura.» y no se envía`, (await texto(p)).includes("La fecha de la muestra no puede ser futura.") && rpcs.length === n0);
  await p.screenshot({ path: join(CAP, `muestreo_futura_${ancho}.png`), fullPage: true });
  // (f) vacía
  await poner(p, "#tec-fecha", "");
  n0 = rpcs.length; await clicTexto(p, "button", "Guardar registro"); await esperarTexto(p, /Elija la fecha de la muestra/);
  ok(`${tag} Muestreo sin fecha: «Elija la fecha de la muestra.» y no se envía`, rpcs.length === n0);
  // (g) el borrador guarda la fecha: recarga sin limpiar
  await poner(p, "#tec-fecha", dia(-2));
  await new Promise((x) => setTimeout(x, 700));
  await p.close();
  p = await abrir(ancho, false);
  await abrirForm(p, "Muestreo", /Puntos de muestreo/);
  ok(`${tag} Muestreo: el borrador recupera la fecha elegida (${dia(-2)}) y lo escrito`, (await p.$eval("#tec-fecha", (e) => e.value)) === dia(-2) && /Se recuperó lo que había escrito/.test(await texto(p)), await p.$eval("#tec-fecha", (e) => e.value));
  // (h) Descartar borrador: vuelve a hoy
  await clicTexto(p, "button", "Descartar borrador"); await esperarTexto(p, /¿Descartar lo escrito\?/); await clicTexto(p, "button", "Sí, descartar");
  await esperarTexto(p, /Se descartó lo escrito/);
  ok(`${tag} Muestreo: «Descartar borrador» devuelve la fecha a hoy`, (await p.$eval("#tec-fecha", (e) => e.value)) === HOY);
  ok(`${tag} Muestreo: sin desborde horizontal`, await sinDesborde(p));

  // ===== La Edge real hace cumplir la regla aunque la pantalla se salte =====
  const directo = (cuerpo) => p.evaluate(async (url, cuerpo) => { const r = await fetch(url, { method: "POST", headers: { Authorization: "Bearer tok-op", "Content-Type": "application/json" }, body: JSON.stringify(cuerpo) }); return { s: r.status, j: await r.json() }; }, `http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-tecnica?accion=registrar`, cuerpo);
  const baseE = { formulario: "entrada", planta: "zt_norte", hora: horaMenos(15), valores: [{ variable: "caudal_qi", valor: 100 }], clave_envio: `directo-ent-${ancho}` };
  n0 = rpcs.length;
  let d = await directo({ ...baseE, fecha_muestra: dia(-1) });
  ok(`${tag} Edge real: Entrada con fecha_muestra → 400 «La fecha la fija el servidor.» sin tocar la base`, d.s === 400 && d.j.error === "La fecha la fija el servidor." && rpcs.length === n0, JSON.stringify(d));
  d = await directo({ ...baseE, formulario: "salida", planta: null, punto: "TAN-01", valores: [{ variable: "cloro_libre_tanque", valor: 1 }], fecha_muestra: HOY });
  ok(`${tag} Edge real: Salida con fecha_muestra (aun hoy) → 400 «La fecha la fija el servidor.»`, d.s === 400 && d.j.error === "La fecha la fija el servidor." && rpcs.length === n0, JSON.stringify(d));
  const baseM = { formulario: "muestreo", planta: null, punto: "MUE-05", hora: "08:00", valores: [{ variable: "ph", valor: 7 }], clave_envio: `directo-mue-${ancho}` };
  d = await directo({ ...baseM, fecha_muestra: dia(1) });
  ok(`${tag} Edge real: Muestreo con fecha futura → 400 «… no puede ser futura.» sin tocar la base`, d.s === 400 && d.j.error === "La fecha de la muestra no puede ser futura." && rpcs.length === n0, JSON.stringify(d));
  d = await directo({ ...baseM, fecha_muestra: "2026-02-30" });
  ok(`${tag} Edge real: Muestreo con fecha imposible → 400 «… no es válida.»`, d.s === 400 && d.j.error === "La fecha de la muestra no es válida." && rpcs.length === n0, JSON.stringify(d));
  d = await directo({ ...baseM, fecha_muestra: dia(-8) });
  ok(`${tag} Edge real → base: Muestreo hace 8 días → 400 con el texto de la RPC (máximo 7 días atrás)`, d.s === 400 && /máximo 7 días atrás/.test(d.j.error) && rpcs.length === n0 + 1, JSON.stringify(d));
  await p.close();
}
ok("ninguna RPC pedida fuera de las simuladas", desconocidas.length === 0, desconocidas.join(", "));
ok("sin errores de página ni de consola", errores.length === 0, errores.join(" | "));
await nav.close(); srv.close(); edge.kill();

const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "✔" : "✖"} ${r.nombre}${r.ok || !r.det ? "" : `  →  ${r.det}`}`);
console.log(`\n${bien} de ${resultados.length} · capturas en ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
