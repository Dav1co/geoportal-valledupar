// Prueba en Chrome REAL del Corte 7a de Técnica fase 1: la pestaña «Químicos» del Dashboard PTAP (§29: bodega en kg, ficha técnica en PDF con subida firmada,
// dosis óptima, inventario inicial, ajuste, agregar y desactivar, historial, esperado contra usado) y las respuestas de David al 6b (tarjeta del contrato sin
// nombre para el supervisor de planta; un color por estado).
// A 390 px (táctil) y 1280 px.
// · Las Edges geoportal-tecnica y geoportal-redes corren DE VERDAD en Deno; las RPC de redes van a la base local REAL (PostGIS de Homebrew con la carga real,
//   la MUE, el 6a, el 6b y 111.950 contratos SINTÉTICOS); lo de planta (mis formularios) se simula como en el 5c.
// · Antes de cada ancho, la base se rehace (base_chrome.sh) y se siembra la casilla del geovisor para zt.oper.
// Uso: node scripts/prueba_chrome_quimicos_c7a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, BASE] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_c7a"));
if (!BASE) { console.error("Uso: node scripts/prueba_chrome_quimicos_c7a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base_chrome.sh> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54991, P_EDGE = 54992;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local", PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co" };
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.dist]: "operador", [EMAILS.planta]: "supervisor", [EMAILS.op]: "operador", [EMAILS.op2]: "operador" };
const FORMS = { [EMAILS.adm]: ["danos_fallas", "mantenimiento"], [EMAILS.dist]: [], [EMAILS.planta]: ["muestreo"], [EMAILS.op]: ["danos_fallas", "mantenimiento"], [EMAILS.op2]: [] };
const NOMBRE = { danos_fallas: "Reportar daño o falla", mantenimiento: "Registrar intervención", muestreo: "Muestreo" };
const rehacer = () => execFileSync("sh", [BASE], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c7a_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
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
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
// la página imita la app: .app de alto 100 % con la barra de 54 px (como la prueba de los dashboards del §34)
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST simulados; las RPC de redes van a la base local REAL ----------
const HOY = new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const rpcs = [], desconocidas = [], subidas = [], firmasLectura = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcPlanta(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: c === "muestreo" })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_obtener_formulario": return { formulario: { clave: "muestreo", nombre: "Muestreo", descripcion: "" }, fecha_hoy: HOY, hora_propuesta: "08:00", dias_atras_max: 7, fecha_minima: HOY, plantas: [], puntos: [], variables: [] };
    case "geoportal_tec_resumen_operador": return { formulario: a.p_formulario, ventana_horas: 24, filas: [] };
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_listar_registros": return { total: 0, devueltos: 0, registros: [] };
    case "geoportal_tec_listar_dosis": return { total: 0, devueltos: 0, dosis: [] };
    default: desconocidas.push(fn); return { status: 404, cuerpo: { code: "PGRST202", message: "no existe" } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f)));
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT, GET, POST", "Access-Control-Allow-Headers": "content-type, x-upsert, authorization" }); return res.end(); }
    // Storage simulado: firmas (la Edge) y la subida del PDF (el navegador, con PUT a la URL firmada) que queda en storage.objects de la base local
    if (req.method === "PUT" && u.pathname.startsWith("/storage/v1/object/upload/sign/")) {
      const [bucket, ...resto] = decodeURIComponent(u.pathname.slice("/storage/v1/object/upload/sign/".length)).split("/");
      subidas.push({ bucket, ruta: resto.join("/"), bytes: cuerpo.length, mime: req.headers["content-type"] });
      sqlq(`insert into storage.objects (bucket_id, name, metadata) values (${lit(bucket)}, ${lit(resto.join("/"))}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })})`);
      return json(200, { Key: resto.join("/") });
    }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/upload/sign/".length); return json(200, { url: `/object/upload/sign/${ruta}?token=TOKEN` }); }
    if (u.pathname.startsWith("/storage/v1/object/sign/")) { const ruta = u.pathname.slice("/storage/v1/object/sign/".length); firmasLectura.push(ruta); return json(200, { signedURL: `/object/leer/${ruta}?token=LECTURA` }); }
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (fn.startsWith("geoportal_redes_") || /^geoportal_tec_punto|^geoportal_tec_quimic/.test(fn)) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcPlanta(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 300))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = async (p, re, ms = 30000) => {
  try { await p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source); }
  catch { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(-1500)} · edge: ${edgeLog.slice(-600)}`); }
};
const clicTexto = (p, sel, t, dentro = "body") => p.evaluate((sel, t, dentro) => { const b = [...document.querySelector(dentro).querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t, dentro);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const visibilidad = (p, capa) => p.evaluate((c) => document.querySelector(".geo-mapa").__mapa.getLayoutProperty(c, "visibility"), capa);
const dibujados = (p, capa) => p.evaluate((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) ? m.queryRenderedFeatures({ layers: [c] }).length : -1; }, capa);
const esperarDibujo = (p, capa, ms = 60000) => p.waitForFunction((c) => { const m = document.querySelector(".geo-mapa")?.__mapa; return m && m.getLayer(c) && m.queryRenderedFeatures({ layers: [c] }).length > 0; }, { timeout: ms }, capa).then(() => true).catch(() => false);
const marcada = (p, capa) => p.evaluate((c) => document.querySelector(`.geo-panel [data-capa=${c}] input`)?.checked ?? null, capa);
async function abrir(ancho, rol, hash) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(120000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let txt = m.text();
    if (/JSHandle@/.test(txt)) txt = m.args().map((a) => a.remoteObject().description ?? a.remoteObject().value ?? "?").join(" ");      // sin evaluar: la página puede estar cerrándose
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`);
  });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}${hash ?? ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
async function alGeovisor(p, boton = "Geovisor técnico") {
  await esperarTexto(p, new RegExp(boton.replace(/[()]/g, "\\$&"))); await clicTexto(p, "button", boton); await esperarTexto(p, /Geovisor técnico[\s\S]*Capas/);
  await p.waitForFunction(() => !!document.querySelector(".geo-mapa")?.__mapa, { timeout: 30000 });
}
/** Lleva el mapa a un punto y toca la pantalla allí (como un dedo). */
async function tocarEn(p, lon, lat, zoom = 17.5) {
  await p.evaluate((lon, lat, z) => { const m = document.querySelector(".geo-mapa").__mapa; m.jumpTo({ center: [lon, lat], zoom: z }); }, lon, lat, zoom);
  await p.waitForFunction(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); }, { timeout: 60000 }).catch(() => {});
  await new Promise((r) => setTimeout(r, 400));
  const pt = await p.evaluate((lon, lat) => { const m = document.querySelector(".geo-mapa").__mapa; const r = document.querySelector(".geo-mapa").getBoundingClientRect(); const q = m.project([lon, lat]); return { x: r.left + q.x, y: r.top + q.y }; }, lon, lat);
  if (await p.evaluate(() => matchMedia("(hover: none)").matches || navigator.maxTouchPoints > 0)) await p.touchscreen.tap(pt.x, pt.y); else await p.mouse.click(pt.x, pt.y);
}

// PDF de prueba (mínimo y válido) para la ficha técnica
const PDF = join(dir, "ficha_tecnica.pdf");
writeFileSync(PDF, "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n");
const tarjetaQ = (p, c) => p.evaluate((c) => document.querySelector(`[data-quimico=${c}]`)?.innerText ?? "", c);
const esperarTarjeta = (p, c, re) => p.waitForFunction((c, s) => new RegExp(s).test(document.querySelector(`[data-quimico=${c}]`)?.innerText ?? ""), { timeout: 20000 }, c, re.source).catch(() => {});
const enTarjeta = (p, c, boton) => clicTexto(p, "button", boton, `[data-quimico=${c}]`);
const escribir = (p, sel, v) => p.evaluate((sel, v) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v); el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
async function alQuimicos(p) {
  await esperarTexto(p, /Dashboard PTAP/); await clicTexto(p, "button", "Dashboard PTAP"); await esperarTexto(p, /Registros/);
  await clicTexto(p, "[role=tab]", "Químicos"); await esperarTexto(p, /Una sola bodega/);
}

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  rehacer(); rpcs.length = 0; subidas.length = 0;
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('${EMAILS.op}', 'asignar_formulario', 'uso_quimicos')`);

  // ===== A. La bodega (supervisor de planta) =====
  let p = await abrir(ancho, "planta");
  await alQuimicos(p);
  let t = await tarjetaQ(p, "pac");
  ok(`${tag} A1 la pestaña «Químicos» del Dashboard PTAP: PAC y cloro gaseoso de potabilización, hipoclorito de calcio para limpieza; sin inventario ni PDF todavía`,
     /Policloruro de aluminio/.test(t) && /De potabilización/.test(t) && /Sin inventario inicial/.test(t) && /Falta el PDF/.test(t) && /Falta fijarla/.test(t)
     && /Limpieza u otro uso/.test(await tarjetaQ(p, "hipoclorito_calcio")) && /De potabilización/.test(await tarjetaQ(p, "cloro_gaseoso")), t);
  ok(`${tag} A2 sin desborde y con botones de 44 px o más`, (await sinDesborde(p)) && (await minimo(p, ".qm button")) >= 44, `mínimo ${await minimo(p, ".qm button")}`);
  await p.screenshot({ path: join(CAP, `bodega_${ancho}.png`), fullPage: true });

  // B. dosis óptima del PAC: sin PDF no se deja; con PDF, sí (subida firmada a Storage)
  await enTarjeta(p, "pac", "Cambiar"); await p.waitForSelector("[data-quimico=pac] [data-form=cambiar]");
  await escribir(p, "#qm-c-dosis-pac", "18"); await escribir(p, "#qm-c-mot-pac", "Jar test de noviembre en Huaricha");
  ok(`${tag} B1 cambiar la dosis óptima sin el PDF: aviso y «Guardar» desactivado`, /adjunte el PDF/.test(await tarjetaQ(p, "pac"))
     && await p.evaluate(() => [...document.querySelectorAll("[data-quimico=pac] [data-form=cambiar] button")].find((b) => b.textContent.startsWith("Guardar"))?.disabled === true));
  await (await p.$("#qm-c-pdf-pac")).uploadFile(PDF);
  await clicTexto(p, "button", "Guardar los cambios", "[data-quimico=pac]"); await esperarTexto(p, /se guardó dosis óptima/); await esperarTarjeta(p, "pac", /18 ppm/);
  t = await tarjetaQ(p, "pac");
  ok(`${tag} B2 con el PDF: el PDF sube a su URL firmada (tecnica-evidencias, application/pdf), la dosis queda en 18 ppm y la ficha se ve (URL firmada)`,
     subidas.length === 1 && subidas[0].bucket === "tecnica-evidencias" && /^quimicos\/\d{4}-\d{2}\/[0-9a-f-]{36}\.pdf$/.test(subidas[0].ruta) && subidas[0].mime === "application/pdf"
     && /18 ppm/.test(t) && /Ver PDF/.test(t) && await p.evaluate(() => document.querySelector("[data-quimico=pac] a")?.href.includes("LECTURA")), JSON.stringify(subidas) + " " + t);
  ok(`${tag} B3 en la base: el evento de dosis óptima con su PDF y el motivo`, sqlq("select e.dosis_optima_ppm || '|' || (e.ficha_ruta is not null) || '|' || e.motivo from tecnica.quimico_ficha_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = 'pac' and e.tipo = 'dosis_optima'")
     === "18|true|Jar test de noviembre en Huaricha");

  // C. inventario inicial en toneladas y ajuste
  await enTarjeta(p, "pac", "Inventario inicial"); await p.waitForSelector("[data-quimico=pac] [data-form=inventario]");
  await escribir(p, "#qm-i-c-pac", "12"); await escribir(p, "#qm-i-u-pac", "t");
  ok(`${tag} C1 el inventario en toneladas muestra su equivalente en kg antes de guardar`, /Queda en 12\.000 kg/.test(await tarjetaQ(p, "pac")));
  await clicTexto(p, "button", "Guardar el inventario", "[data-quimico=pac]"); await esperarTexto(p, /saldo 12\.000 kg/); await esperarTarjeta(p, "pac", /12\.000 kg/);
  ok(`${tag} C2 saldo del PAC: 12.000 kg`, /12\.000 kg/.test(await tarjetaQ(p, "pac")));
  await enTarjeta(p, "pac", "Ajuste"); await p.waitForSelector("[data-quimico=pac] [data-form=ajuste]");
  await escribir(p, "#qm-a-pac", "-50"); await escribir(p, "#qm-a-m-pac", "Faltante del conteo semanal");
  ok(`${tag} C3 el ajuste muestra el saldo que queda`, /pasa de 12\.000 kg a 11\.950 kg/.test(await tarjetaQ(p, "pac")));
  await clicTexto(p, "button", "Guardar el ajuste", "[data-quimico=pac]"); await esperarTexto(p, /saldo 11\.950 kg/); await esperarTarjeta(p, "pac", /11\.950 kg/);
  ok(`${tag} C4 saldo después del ajuste: 11.950 kg`, sqlq("select saldo_kg from tecnica.v_quimico_saldo where codigo = 'pac'") === "11950");

  // D. agregar un químico (PDF obligatorio) y desactivarlo
  await clicTexto(p, "button", "Agregar químico"); await p.waitForSelector("[data-form=nuevo]");
  await escribir(p, "#qm-n-nombre", "Sulfato de aluminio"); await escribir(p, "#qm-n-dosis", "25"); await escribir(p, "#qm-n-mot", "Se empezó a usar en Gota Fría");
  ok(`${tag} D1 sin el PDF no se deja agregar`, await p.evaluate(() => [...document.querySelectorAll("[data-form=nuevo] button")].find((b) => b.textContent === "Agregar")?.disabled === true));
  await (await p.$("#qm-n-pdf")).uploadFile(PDF);
  await clicTexto(p, "button", "Agregar", "[data-form=nuevo]"); await esperarTexto(p, /Se agregó Sulfato de aluminio \(sulfato_de_aluminio\)/); await esperarTarjeta(p, "sulfato_de_aluminio", /25 ppm/);
  ok(`${tag} D2 se agrega con su código, de potabilización, 25 ppm y su ficha`, /25 ppm/.test(await tarjetaQ(p, "sulfato_de_aluminio")) && /Ver PDF/.test(await tarjetaQ(p, "sulfato_de_aluminio")));
  await enTarjeta(p, "sulfato_de_aluminio", "Cambiar"); await p.waitForSelector("[data-quimico=sulfato_de_aluminio] [data-form=cambiar]");
  await p.evaluate(() => [...document.querySelectorAll("[data-quimico=sulfato_de_aluminio] [data-form=cambiar] input[type=checkbox]")][1].click());
  await escribir(p, "#qm-c-mot-sulfato_de_aluminio", "Se dejó de usar: se vuelve al PAC");
  await clicTexto(p, "button", "Guardar los cambios", "[data-quimico=sulfato_de_aluminio]"); await esperarTexto(p, /se guardó activo/); await esperarTarjeta(p, "sulfato_de_aluminio", /Inactivo/);
  ok(`${tag} D3 desactivarlo con motivo: queda «Inactivo» en el catálogo (no se borra)`, /Inactivo/.test(await tarjetaQ(p, "sulfato_de_aluminio"))
     && sqlq("select activo from tecnica.quimicos where codigo = 'sulfato_de_aluminio'") === "f");

  // E. historial
  await enTarjeta(p, "pac", "Historial"); await p.waitForSelector("[data-quimico=pac] [data-form=historial] .qm-historial");
  t = await tarjetaQ(p, "pac");
  ok(`${tag} E1 el historial del PAC: la dosis óptima con su PDF y motivo; el inventario y el ajuste con sus kg`, /Dosis óptima · 18 ppm/.test(t) && /Inventario inicial/.test(t) && /12\.000 kg \(12 t\)/.test(t) && /Ajuste/.test(t) && /-50 kg/.test(t), t.slice(0, 600));
  await p.screenshot({ path: join(CAP, `historial_${ancho}.png`), fullPage: true });

  // F. esperado contra usado (el uso lo registra el operador; su pantalla llega en el 7b: aquí va por la RPC)
  sqlq(`select public.geoportal_tec_quimico_uso('${EMAILS.op}', '{"quimico": "pac", "cantidad": 300, "para_que": "dosificacion", "planta": "huaricha"}', null)`);
  await clicTexto(p, "[role=tab]", "Esperado contra usado"); await esperarTexto(p, /Esperado = dosis óptima/);
  await p.waitForFunction(() => !/Calculando/.test(document.body.innerText), { timeout: 20000 });
  const fila = await p.evaluate(() => [...document.querySelectorAll("[data-cmp]")].find((x) => /\|huaricha\|pac$/.test(x.dataset.cmp) && x.querySelector(".qm-chip-marca"))?.innerText ?? "");
  ok(`${tag} F1 hoy en Huaricha: Qi 1.000 L/s (86.400 m³), 18 ppm, esperado 1.555,2 kg, usado 300 kg y la marca`, /1\.000 L\/s/.test(fila) && /18 ppm/.test(fila) && /1\.555,2 kg/.test(fila) && /300 kg/.test(fila) && /Marca/.test(fila), fila);
  ok(`${tag} F2 sin desborde`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `comparacion_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== G. Quién no ve químicos =====
  p = await abrir(ancho, "op"); await esperarTexto(p, /Tus formularios/);
  ok(`${tag} G1 el operador no tiene el Dashboard PTAP (ni químicos)`, !/Dashboard PTAP/.test(await texto(p)));
  await p.close();
  p = await abrir(ancho, "dist"); await esperarTexto(p, /Dashboard distribución/);
  ok(`${tag} G2 el supervisor de distribución tampoco (químicos es solo de planta)`, !/Dashboard PTAP/.test(await texto(p)));
  await p.close();

  // ===== H. Respuestas al 6b en el geovisor =====
  sqlq("select redes.f_refrescar_contratos_capa()");
  const [C, CLON, CLAT] = sqlq("select c.contrato || '|' || ST_X(c.geom) || '|' || ST_Y(c.geom) from redes.contratos_capa c where c.estado = 'activo' order by c.geom <-> ST_SetSRID(ST_MakePoint(-73.2532, 10.4631), 4326) limit 1").split("|");
  const NOMBRE = sqlq(`select nombre from public.cartera_suscripcion where contrato = '${C}' order by periodo_carga desc limit 1`);
  p = await abrir(ancho, "planta"); await alGeovisor(p);
  await clicTexto(p, ".geo-barra button", "Capas"); await p.waitForSelector(".geo-panel");
  await p.evaluate(() => { const i = document.querySelector(".geo-panel [data-capa=contratos] input"); if (!i.checked) i.click(); });
  await clicTexto(p, ".geo-panel button", "✕");
  await tocarEn(p, Number(CLON), Number(CLAT), 18);
  await p.waitForFunction(() => /Barrio/.test(document.querySelector(".geo-tarjeta[data-capa=contrato]")?.innerText ?? ""), { timeout: 20000 }).catch(() => {});
  t = await p.evaluate(() => document.querySelector(".geo-tarjeta")?.innerText ?? "");
  ok(`${tag} H1 el supervisor de planta ve la tarjeta del contrato SIN nombre ni dirección (sí el barrio y el consumo)`, t.includes(`Contrato ${C}`) && !t.includes(NOMBRE) && !/Dato personal/.test(t)
     && /lo ve el supervisor de distribución|los ve el supervisor de distribución/.test(t) && /Barrio/.test(t) && /Consumo/.test(t), t);
  const colores = JSON.stringify(await p.evaluate(() => document.querySelector(".geo-mapa").__mapa.getPaintProperty("c-contratos", "circle-color")));
  ok(`${tag} H2 un color por estado del contrato (activo, suspendido, cortado, retirado, otro)`, ["activo", "suspendido", "cortado", "retirado", "otro"].every((e) => colores.includes(`"${e}"`)), colores);
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC de planta sin simular", desconocidas.length === 0, desconocidas.join(", "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
