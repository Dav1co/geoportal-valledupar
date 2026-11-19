// Prueba en Chrome REAL de la corrección del 9b «la válvula que cerró el operador», a 390 px (táctil) y 1280 px:
// · un OPERADOR SIN LA CASILLA DEL GEOVISOR cierra una válvula desde su daño: el panel «Cierre de válvulas» se la muestra cerrada («Válvulas cerradas por DAN-…»,
//   «Cerrada» en la lista) y le ofrece «Válvula abierta»; al volver a entrar sigue ahí; la abre; y sigue sin el geovisor;
// · el operador de mantenimiento la ve cerrada pero sin «Válvula abierta» (abrirla pide el formulario de daños y fallas); el supervisor, como siempre;
// · si el servidor todavía no tiene la lectura nueva, el panel queda como antes (sin error);
// · ANTES (el panel de main, sin la corrección): el mismo operador cierra y el panel NO se la muestra (el hallazgo del Code B), con su captura;
// · la Edge geoportal-redes: la ruta cierres_registro con sus rechazos.
// El panel (PanelCierre) se monta solo, con el activo y el registro que diga la dirección. Las RPC van a la base local de CODE A (localhost:55432: producción al
// 17-nov + este paquete; se copia a <plantilla>_chrome) con el rol de la API (service_role) y los topes de producción (30 s y 8 s).
// La Edge corre con su CÓDIGO REAL: en Deno si se da su ruta; si se pasa «node», empaquetada con esbuild y servida en Node con un doble de Deno.serve y Deno.env
// (la Edge no importa nada más de Deno). Puertos de Code A: 54971 (página, Auth y PostgREST simulados) y 54972 (Edge).
// Uso: node scripts/prueba_chrome_valvula_operador_9b.mjs <chrome> <puppeteer-core> <deno|node> <supabase/functions> <psql> <plantilla> [capturas]
//      RAIZ_ANTES=<checkout de main sin la corrección> para la parte «antes» (por omisión, ../geoportal-emdupar si existe)
import { createRequire } from "node:module";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_valvula_operador"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_valvula_operador_9b.mjs <chrome> <puppeteer-core> <deno|node> <supabase/functions> <psql> <base plantilla, p. ej. redes_local> [capturas]"); process.exit(2); }
const RAIZ_ANTES = process.env.RAIZ_ANTES ? resolve(process.env.RAIZ_ANTES) : (existsSync(join(raiz, "..", "geoportal-emdupar", "src")) ? join(raiz, "..", "geoportal-emdupar") : null);
mkdirSync(CAP, { recursive: true });
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54971, P_EDGE = 54972;      // puertos de Code A
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
// Perfiles sintéticos (prefijo zt9v): «op» es el del hallazgo: operador con «daños y fallas» y SIN la casilla del geovisor
const EMAILS = { adm: "zt9v.admin@emdupar.gov.co", dist: "zt9v.dist@emdupar.gov.co", op: "zt9v.oper@emdupar.gov.co", mant: "zt9v.mant@emdupar.gov.co", nada: "zt9v.nada@emdupar.gov.co" };
function rehacer() {
  execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('${EMAILS.adm}', 'ZT9V Administrador', 'admin', 'sin_restriccion', 'todos')`);
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('${EMAILS.dist}', 'ZT9V Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos')`);
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('${EMAILS.op}', 'ZT9V Operador de daños', 'consulta', true, 'sin_restriccion', 'todos'), ('${EMAILS.mant}', 'ZT9V Operador de mantenimiento', 'consulta', true, 'sin_restriccion', 'todos')`);
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('${EMAILS.nada}', 'ZT9V Sin Técnica', 'consulta', 'sin_restriccion', 'todos')`);
  sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'danos_fallas', '${EMAILS.adm}'), ('${EMAILS.mant}', 'asignar_formulario', 'mantenimiento', '${EMAILS.adm}')`);
}
rehacer();
if (sqlq("select coalesce(to_regprocedure('public.geoportal_redes_cierres_registro(text,text)')::text, '')") === "") { console.error(`La plantilla ${PLANTILLA} no tiene el paquete redes_9b_valvula_operador (sh rehacer_base.sh con_vo)`); process.exit(2); }
const CASO = "RED-000077", R1 = JSON.parse(sqlq(`select public.geoportal_redes_simulacion_aguas_arriba('${EMAILS.dist}', '${CASO}', null, null)`));
const V1 = R1.aguas_arriba.valvulas?.[0]?.codigo;
function nuevoDano(quien = EMAILS.op) {      // un daño de acueducto sobre el caso, registrado por el operador con las RPC publicadas
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${quien}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${quien}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", ubicacion_origen: "mapa", activo: CASO, lat: R1.activo.lat, lon: R1.activo.lon,
    t_detectado: sqlq(`select to_char(now() - interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`)).codigo;
}
const cerradasEnBase = (dan) => sqlq(`select coalesce(string_agg(a.codigo, ',' order by a.codigo), '') from redes.f_cierres_vigentes() c join redes.activos a on a.id = c.valvula_id join redes.danos d on d.id = c.dano_id where d.codigo = '${dan}'`);

// ---------- 1. Paquetes de la página: el panel solo (el de esta rama y, para «antes», el de main) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_vo_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "op";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok-" + rol } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
async function paquete(origen, nombre) {
  const out = join(dir, nombre); mkdirSync(out);
  await build({
    plugins: [doble],
    stdin: { resolveDir: origen, loader: "tsx", contents: `
      import React from "react"; import { createRoot } from "react-dom/client";
      import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/tecnica/dano.css";
      import { PanelCierre } from "./src/tecnica/PanelCierre.tsx";
      const q = new URLSearchParams(location.search);
      createRoot(document.getElementById("raiz")).render(<div className="tec-pagina tec-modo-distribucion"><PanelCierre activo={q.get("activo")} registro={q.get("registro")} /></div>);
      setTimeout(() => { window.__listo = true; }, 300);` },
    bundle: true, platform: "browser", format: "esm", splitting: true, outdir: out, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error", nodePaths: [join(raiz, "node_modules")],
    loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
  });
  const hojas = readdirSync(out).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
  writeFileSync(join(out, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);
}
await paquete(raiz, "despues");
if (RAIZ_ANTES) await paquete(RAIZ_ANTES, "antes");
let sinRuta = false;      // «el servidor todavía no tiene la lectura nueva»

// ---------- 2. Auth y PostgREST simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], desconocidas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select to_jsonb(public.${fn}(${args}))`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: t === "" ? null : JSON.parse(t) };      // to_jsonb: sirve igual para las RPC que devuelven jsonb, texto («ok») o booleano
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  const m = /^\/(despues|antes)\/(.*)$/.exec(u.pathname);
  if (m) {
    const f = m[2] === "" ? "index.html" : m[2];
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, m[1], f)));
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const cuerpo = Buffer.concat(trozos);
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (sinRuta && fn === "geoportal_redes_cierres_registro") { rpcs.push({ fn, a, status: 404 }); return json(404, { code: "PGRST202", message: "Could not find the function" }); }
      // todo lo demás (también el estado de acceso y los permisos que consulta autorizar) va a la base local REAL
      if (sqlq(`select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = ${lit(fn)}`) === "0") { desconocidas.push(fn); return json(404, { code: "PGRST202", message: "no existe" }); }
      const r = rpcBase(fn, a); rpcs.push({ fn, a, status: r.status, code: r.cuerpo?.code });
      return json(r.status, r.cuerpo);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. La Edge geoportal-redes con su código REAL (Deno, o Node con el doble de Deno.serve y Deno.env) ----------
let edge, edgeLog = "", EDGE_EN = "Deno";
const envEdge = { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" };
if (DENO === "node") {
  EDGE_EN = "Node (doble de Deno.serve y Deno.env)";
  await build({ entryPoints: [resolve(FUNCIONES, "geoportal-redes/index.ts")], bundle: true, platform: "neutral", format: "esm", outfile: join(dir, "edge_redes.mjs"), logLevel: "error" });
  writeFileSync(join(dir, "servir_edges.mjs"), `import http from "node:http";
const hs = [];
globalThis.Deno = { env: { get: (k) => process.env[k] }, serve: (a, b) => { hs.push(typeof a === "function" ? a : b); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; } };
await import("./edge_redes.mjs");
http.createServer((rq, rs) => { const t = []; rq.on("data", (c) => t.push(c)); rq.on("end", async () => {
  const cuerpo = Buffer.concat(t), h = new Headers(); for (const [k, v] of Object.entries(rq.headers)) if (typeof v === "string") h.set(k, v);
  const r = await hs[0](new Request("http://127.0.0.1:${P_EDGE}" + rq.url, { method: rq.method, headers: h, body: rq.method === "GET" || rq.method === "HEAD" || cuerpo.length === 0 ? undefined : cuerpo }));
  rs.writeHead(r.status, Object.fromEntries(r.headers)); rs.end(Buffer.from(await r.arrayBuffer())); }); }).listen(${P_EDGE}, "127.0.0.1", () => console.log("edges listas"));`);
  edge = spawn(process.execPath, [join(dir, "servir_edges.mjs")], { env: envEdge, stdio: ["ignore", "pipe", "pipe"] });
} else {
  const servir = join(dir, "servir_edges.ts");
  writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => hs[0](r));`);
  edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: envEdge, stdio: ["ignore", "pipe", "pipe"] });
}
edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 700) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 500))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = []; let pagina = null;
const texto = (p) => p.evaluate(() => document.body.innerText);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const minimo = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)), sel);
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t);
const captura = async (p, nombre) => { await new Promise((r) => setTimeout(r, 400)); await p.screenshot({ path: join(CAP, nombre), fullPage: true }); };
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
async function abrir(ancho, rol, registro, version = "despues") {
  const p = await nav.newPage(); pagina = p;
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(60000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", (m) => { if (m.type() !== "error" && m.type() !== "warn") return; const txt = m.text();
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/${version}/?rol=${rol}&activo=${CASO}${registro ? "&registro=" + registro : ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
const simular = async (p) => { await clicTexto(p, "button.tec-boton", "¿Qué válvulas cierro?"); await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-aguas-arriba], [data-testid=cie-resultado]") || !!document.querySelector(".tec-aviso-error"), { timeout: 90000 }); };
// lo que el panel muestra de las válvulas cerradas por el registro
const cerradas = (p) => p.evaluate(() => { const d = document.querySelector("[data-testid=cie-cerradas]"); if (!d) return null;
  return { rot: d.querySelector(".cie-rot")?.textContent ?? "", filas: [...d.querySelectorAll("li[data-valvula]")].map((x) => ({ v: x.dataset.valvula, txt: x.innerText.replace(/\s+/g, " "), abrir: [...x.querySelectorAll("button")].some((b) => b.textContent === "Válvula abierta") })) }; });
const filaLista = (p, v) => p.evaluate((v) => { const li = document.querySelector(`[data-testid=cie-aguas-arriba] li[data-valvula="${v}"], [data-testid=cie-resultado] li[data-valvula="${v}"]`);
  return li ? { boton: li.querySelector("button")?.textContent ?? null, estado: li.querySelector(".cie-estado")?.textContent ?? null } : null; }, v);
const confirmar = async (p) => { await p.waitForSelector("[data-testid=cie-pedir]"); await clicTexto(p, "[data-testid=cie-pedir] button", "Confirmar"); };
const cerrarEnPantalla = async (p, v) => { await p.evaluate((v) => document.querySelector(`[data-testid=cie-aguas-arriba] li[data-valvula="${v}"] button`).click(), v); await confirmar(p);
  await p.waitForFunction(() => /cerrada \(/.test(document.querySelector(".tec-aviso-ok")?.innerText ?? "") || !!document.querySelector(".tec-aviso-error"), { timeout: 60000 }); };
const edgeF = (rol, accion, o = {}) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
  headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined })
  .then(async (r) => ({ status: r.status, cache: r.headers.get("cache-control"), cuerpo: await r.json().catch(() => null) }));
const diagnostico = async (e) => { console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 300) + " · errores: " + errores.join(" | ").slice(0, 900) + " · Edge: " + edgeLog.slice(-400) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-700).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); try { edge.kill(); } catch { /* ya terminó */ } process.exit(1); };
try {
ok(`0 la base trae el caso (${CASO} se cierra por ${V1}) y el perfil del hallazgo: operador con «daños y fallas» y SIN el geovisor; la Edge corre en ${EDGE_EN}`,
  !R1.cae_a_total && V1 && sqlq(`select redes.f_geovisor_lectura('${EMAILS.op}')`) === "f" && sqlq(`select redes.f_puede_formulario('${EMAILS.op}', 'danos_fallas')`) === "t");
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();

  // ===== ANTES (el panel de main): el hallazgo del Code B =====
  if (RAIZ_ANTES) {
    const dan0 = nuevoDano();
    let p = await abrir(ancho, "op", dan0, "antes"); await simular(p);
    await cerrarEnPantalla(p, V1); await espera(1500);
    const c0 = await cerradas(p), f0 = await filaLista(p, V1);
    ok(A(`ANTES (panel de main, sin la corrección): el operador sin geovisor cierra ${V1}; el cierre SÍ queda en la base, pero el panel NO la muestra cerrada ni ofrece «Válvula abierta» (el hallazgo)`),
      cerradasEnBase(dan0) === V1 && c0 === null && f0?.boton === "Válvula cerrada" && f0?.estado === null, JSON.stringify({ c0, f0, base: cerradasEnBase(dan0) }));
    await captura(p, `antes_operador_cierra_${ancho}.png`);
    await p.close();
    sqlq(`select public.geoportal_redes_valvula_maniobra('${EMAILS.op}', '${V1}', 'abrir')`);      // deja la válvula abierta para lo que sigue
  }

  // ===== A. El operador SIN el geovisor cierra desde su daño, la ve cerrada, vuelve a entrar y la abre =====
  rpcs.length = 0;
  const DAN = nuevoDano();
  let p = await abrir(ancho, "op", DAN);
  ok(A("A1 al abrir el panel con su daño recién guardado: todavía no hay «Válvulas cerradas por …» y no hay error"), (await cerradas(p)) === null && !(await p.evaluate(() => !!document.querySelector(".tec-aviso-error")))
    && rpcs.some((x) => x.fn === "geoportal_redes_cierres_registro" && x.status === 200));
  await simular(p);
  ok(A(`A2 «¿Qué válvulas cierro?» le da ${V1} con el botón «Válvula cerrada»`), (await filaLista(p, V1))?.boton === "Válvula cerrada", JSON.stringify(await filaLista(p, V1)));
  await cerrarEnPantalla(p, V1);
  await p.waitForFunction((v) => !!document.querySelector(`[data-testid=cie-cerradas] li[data-valvula="${v}"]`), { timeout: 15000 }, V1).catch(() => {});
  let c = await cerradas(p), f = await filaLista(p, V1);
  ok(A(`A3 LA CORRECCIÓN: al confirmar, ${V1} queda en la base y el panel la muestra en «Válvulas cerradas por ${DAN}», con «Cerrada desde …» y el botón «Válvula abierta»`),
    cerradasEnBase(DAN) === V1 && c && c.rot === `Válvulas cerradas por ${DAN}` && c.filas.length === 1 && c.filas[0].v === V1 && /Cerrada desde/.test(c.filas[0].txt) && c.filas[0].abrir, JSON.stringify(c));
  ok(A("A4 … y en la lista de «¿Qué válvulas cierro?» esa válvula ya dice «Cerrada» (sin el botón de cerrar)"), f?.estado === "Cerrada" && f?.boton === null, JSON.stringify(f));
  ok(A("A5 sin desborde horizontal y botones de 44 px o más"), (await sinDesborde(p)) && (await minimo(p, "[data-testid=panel-cierre] button")) >= 44);
  await captura(p, `despues_operador_cierra_${ancho}.png`);
  await p.close();
  p = await abrir(ancho, "op", DAN);
  await p.waitForFunction((v) => !!document.querySelector(`[data-testid=cie-cerradas] li[data-valvula="${v}"]`), { timeout: 15000 }, V1).catch(() => {});
  c = await cerradas(p);
  ok(A("A6 al volver a entrar a su daño (pantalla nueva), la válvula sigue ahí como cerrada, con «Válvula abierta»"), c && c.filas.length === 1 && c.filas[0].v === V1 && c.filas[0].abrir, JSON.stringify(c));
  await captura(p, `despues_operador_vuelve_${ancho}.png`);
  await clicTexto(p, "[data-testid=cie-cerradas] button", "Válvula abierta"); await confirmar(p);
  await p.waitForFunction(() => /abierta \(/.test(document.querySelector(".tec-aviso-ok")?.innerText ?? "") || !!document.querySelector(".tec-aviso-error"), { timeout: 60000 });
  await p.waitForFunction(() => !document.querySelector("[data-testid=cie-cerradas]"), { timeout: 15000 }).catch(() => {});
  ok(A(`A7 el operador pulsa «Válvula abierta» y confirma: ${V1} queda abierta en la base, sale de la lista y el panel lo dice`),
    cerradasEnBase(DAN) === "" && (await cerradas(p)) === null && new RegExp(`Válvula ${V1} abierta`).test(await texto(p)), (await texto(p)).slice(0, 400));
  await captura(p, `despues_operador_abre_${ancho}.png`);
  ok(A("A8 en todo esto el operador nunca recibió las afectaciones del geovisor, y sigue sin el geovisor (su configuración responde 403)"),
    !rpcs.some((x) => x.fn === "geoportal_redes_cortes_vigentes" && x.a.p_solicitante === EMAILS.op && x.status === 200) && (await edgeF("op", "geovisor")).status === 403
    && (await edgeF("op", "cortes_vigentes")).status === 403 && sqlq(`select redes.f_geovisor_lectura('${EMAILS.op}')`) === "f");
  await p.close();

  // ===== B. Otros perfiles con el mismo daño (la válvula cerrada otra vez por el operador) =====
  sqlq(`select public.geoportal_redes_valvula_maniobra('${EMAILS.op}', '${V1}', 'cerrar', '${DAN}')`);
  p = await abrir(ancho, "mant", DAN);
  await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-cerradas]"), { timeout: 15000 }).catch(() => {});
  c = await cerradas(p);
  ok(A("B1 el operador de mantenimiento ve la válvula cerrada por el daño, SIN el botón «Válvula abierta» (abrirla pide «daños y fallas»)"), c && c.filas.length === 1 && c.filas[0].v === V1 && !c.filas[0].abrir, JSON.stringify(c));
  await captura(p, `despues_mantenimiento_${ancho}.png`);
  await p.close();
  p = await abrir(ancho, "dist", DAN);
  await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-cerradas]"), { timeout: 15000 }).catch(() => {});
  c = await cerradas(p);
  ok(A("B2 el supervisor de distribución, como siempre: la ve cerrada y con «Válvula abierta»"), c && c.filas.length === 1 && c.filas[0].abrir, JSON.stringify(c));
  await p.close();

  // ===== C. El servidor todavía no tiene la lectura nueva: como antes, sin error =====
  sinRuta = true; rpcs.length = 0;
  p = await abrir(ancho, "dist", DAN);
  await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-cerradas]"), { timeout: 15000 }).catch(() => {});
  c = await cerradas(p);
  ok(A("C1 sin la función nueva en el servidor, el supervisor sigue viendo la válvula cerrada (el panel cae a la lectura de antes)"), c && c.filas.length === 1 && c.filas[0].abrir
    && rpcs.some((x) => x.fn === "geoportal_redes_cortes_vigentes" && x.status === 200), JSON.stringify(c));
  await p.close();
  p = await abrir(ancho, "op", DAN); await espera(1500);
  ok(A("C2 … y el operador queda como antes de la corrección: sin la lista y sin error en pantalla"), (await cerradas(p)) === null && !(await p.evaluate(() => !!document.querySelector(".tec-aviso-error"))));
  sinRuta = false;
  await p.close();

  // ===== R. Regresión del 9b: el flujo de siempre del supervisor en el mismo panel (la válvula sigue cerrada por el daño) =====
  p = await abrir(ancho, "dist", DAN); await simular(p);
  ok(A("R1 el supervisor simula: «Cierre por aguas arriba» recomendada, y la válvula ya cerrada dice «Cerrada»"), (await p.evaluate(() => document.querySelector('[data-opcion="aguas_arriba"]')?.getAttribute("aria-selected"))) === "true"
    && (await filaLista(p, V1))?.estado === "Cerrada");
  await p.evaluate(() => document.querySelector('[data-opcion="total"]').click()); await p.waitForSelector("[data-testid=cie-resultado]", { timeout: 90000 });
  await clicTexto(p, "[data-testid=cie-resultado] button", "Guardar esta simulación");
  await p.waitForFunction(() => /Simulación guardada/.test(document.querySelector(".tec-aviso-ok")?.innerText ?? "") || !!document.querySelector(".tec-aviso-error"), { timeout: 90000 });
  ok(A("R2 «Aislamiento total» y «Guardar esta simulación» siguen funcionando: queda guardada con el daño"), new RegExp(`Simulación guardada con ${DAN}`).test(await texto(p))
    && Number(sqlq(`select count(*) from redes.simulaciones_cierre s join redes.danos d on d.id = s.dano_id where d.codigo = '${DAN}'`)) === 1, (await texto(p)).slice(0, 300));
  await clicTexto(p, "[data-testid=cie-cerradas] button", "Válvula abierta"); await confirmar(p);
  await p.waitForFunction(() => !document.querySelector("[data-testid=cie-cerradas]"), { timeout: 60000 }).catch(() => {});
  await p.evaluate(() => document.querySelector('[data-opcion="aguas_arriba"]').click()); await p.waitForSelector("[data-testid=cie-aguas-arriba]");
  ok(A("R3 el supervisor abre la válvula que cerró el operador: sale de la lista y vuelve el botón «Válvula cerrada»"), cerradasEnBase(DAN) === "" && (await cerradas(p)) === null && (await filaLista(p, V1))?.boton === "Válvula cerrada");
  await cerrarEnPantalla(p, V1);
  await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-cerradas]"), { timeout: 15000 }).catch(() => {});
  ok(A("R4 … y la cierra de nuevo desde la lista: vuelve a «Válvulas cerradas por …»"), cerradasEnBase(DAN) === V1 && (await cerradas(p))?.filas.length === 1);
  await p.close();
}

// ===== F. La Edge: la ruta cierres_registro =====
const DANF = sqlq(`select d.codigo from redes.f_cierres_vigentes() c join redes.danos d on d.id = c.dano_id limit 1`);
let r = await edgeF("op", "cierres_registro", { qs: { registro: DANF } });
ok(`F1 cierres_registro (GET) para el operador sin geovisor: 200, sin caché, registro, puede_abrir y las válvulas de ${DANF} (con el nombre del funcionario que cerró); sin datos de suscriptores ni correos`, r.status === 200 && r.cache === "no-store" && r.cuerpo.registro === DANF && r.cuerpo.puede_abrir === true
  && r.cuerpo.valvulas.length === 1 && r.cuerpo.valvulas[0].codigo === V1 && r.cuerpo.valvulas[0].quien === "ZT9V Supervisor de distribución" && !/suscriptor|telefono|direccion|@emdupar/i.test(JSON.stringify(r.cuerpo)), JSON.stringify(r).slice(0, 300));
r = await edgeF("op", "cierres_registro", { qs: { registro: DANF.toLowerCase() } });
ok("F2 acepta el código en minúsculas", r.status === 200 && r.cuerpo.registro === DANF, JSON.stringify(r).slice(0, 200));
ok("F3 rechaza por forma: sin registro o con un código que no es de daño ni de intervención (400), y por POST (405)", (await edgeF("op", "cierres_registro")).status === 400
  && (await edgeF("op", "cierres_registro", { qs: { registro: "VAL-000001" } })).status === 400 && (await edgeF("op", "cierres_registro", { qs: { registro: DANF }, cuerpo: {} })).status === 405);
ok("F4 un daño que no existe: 404", (await edgeF("op", "cierres_registro", { qs: { registro: "DAN-999999" } })).status === 404);
ok("F5 quién: al supervisor y al de mantenimiento, 200 (este con puede_abrir falso); a quien no es de Técnica, 403; sin sesión, 401", (await edgeF("dist", "cierres_registro", { qs: { registro: DANF } })).status === 200
  && (await edgeF("mant", "cierres_registro", { qs: { registro: DANF } })).cuerpo?.puede_abrir === false && (await edgeF("nada", "cierres_registro", { qs: { registro: DANF } })).status === 403
  && (await edgeF("nadie", "cierres_registro", { qs: { registro: DANF } })).status === 401);
ok("F6 las rutas del 9b que el panel ya usaba siguen igual para el operador: simulacion_aguas_arriba 200 y cortes_vigentes 403", (await edgeF("op", "simulacion_aguas_arriba", { cuerpo: { activo: CASO } })).status === 200
  && (await edgeF("op", "cortes_vigentes")).status === 403 && (await edgeF("dist", "cortes_vigentes")).status === 200);
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
