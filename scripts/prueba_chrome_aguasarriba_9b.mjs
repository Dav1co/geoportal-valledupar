// Prueba en Chrome REAL de «Cierre por aguas arriba» en «¿Qué válvulas cierro?» (pase corto del 9b), a 390 px (táctil) y 1280 px:
// · la opción «Cierre por aguas arriba» sale primero y como recomendada, con su lista de válvulas, los contratos, el resultado del modelo y el aviso cuando no
//   coincide con la cota; «Aislamiento total» queda como segunda opción (se calcula al pedirla);
// · cuando por aguas arriba no se puede, lo dice y lleva al aislamiento total (que ya viene en la respuesta);
// · con un daño guardado, «Válvula cerrada» funciona igual desde la lista de aguas arriba;
// · si el servidor todavía no tiene la función nueva, el panel queda como antes (solo el aislamiento total);
// · la Edge geoportal-redes: la ruta simulacion_aguas_arriba con sus rechazos.
// El panel (PanelCierre) se monta solo, con el activo y el registro que diga la dirección; la Edge corre DE VERDAD en Deno y las RPC van a la base de Code B
// (producción con el 14 + el paquete «aguas arriba» del Code A) con el rol de la API (service_role) y los topes de producción (30 s y 8 s).
// Uso: node scripts/prueba_chrome_aguasarriba_9b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <plantilla> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = process.env.RAIZ_UI ? resolve(process.env.RAIZ_UI) : join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_aguasarriba"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_aguasarriba_9b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> <base plantilla, p. ej. emdupar_b_aut> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55989, P_EDGE = 55990;      // puertos de Code B
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_B || "55442", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_chrome`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55432") { console.error("El puerto 55432 es de Code A: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt.admin@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", op2: "zt.oper.sinform@emdupar.gov.co", campo: "zt.campo@emdupar.gov.co", nada: "zt.nada@emdupar.gov.co" };
const ANTES = false;
function rehacer() {
  execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_chrome`, "-c", `create database ${PLANTILLA}_chrome template ${PLANTILLA}`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('${EMAILS.campo}', 'ZT Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos') on conflict do nothing`);
  if (sqlq(`select tecnica.f_formulario_asignado('${EMAILS.op}', 'danos_fallas')`) !== "t") sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'danos_fallas', '${EMAILS.adm}')`);
}
rehacer();
// Los casos salen de la base (no se suponen): el del encargo de David y, buscando entre tramos de acueducto, uno que cae al aislamiento total y uno donde cota y modelo coinciden
const au = (cod) => JSON.parse(sqlq(`select public.geoportal_redes_simulacion_aguas_arriba('${EMAILS.dist}', '${cod}', null, null)`));
const CASO = "RED-000077", R1 = au(CASO);
const candidatos = sqlq(`select string_agg(codigo, ',') from (select m.codigo from redes.activo_vigente_mat m where m.prefijo = 'RED' and not m.retirado and not m.oculto and m.estado_codigo = 'en_operacion' order by md5(m.codigo) limit 60) x`).split(",");
let CAE = null, COINCIDE = null;
for (const c of ["RED-006306", "RED-000937", ...candidatos]) {
  if (CAE && COINCIDE) break;
  let r; try { r = au(c); } catch { continue; }
  if (!CAE && r.cae_a_total) CAE = { cod: c, r };
  if (!COINCIDE && !r.cae_a_total && r.comprobacion.coincide) COINCIDE = { cod: c, r };
}

// ---------- 1. Paquete de la página: el panel solo, con el activo y el registro de la dirección ----------
const dir = mkdtempSync(join(tmpdir(), "ui_au_"));
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
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/tecnica/dano.css";
    import { PanelCierre } from "./src/tecnica/PanelCierre.tsx";
    const q = new URLSearchParams(location.search);
    createRoot(document.getElementById("raiz")).render(<div className="tec-pagina tec-modo-distribucion"><PanelCierre activo={q.get("activo")} registro={q.get("registro")} /></div>);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);
let sinRuta = false;      // «el servidor todavía no tiene la función nueva»

// ---------- 2. Auth, Storage y PostgREST simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], desconocidas = [], subidas = [];
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: /_mvt($|_)/.test(fn) ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
function rpcOtras(fn, a) {
  switch (fn) {
    case "geoportal_tec_mis_formularios": { const p = PERFIL[a.p_solicitante]; return p ? { perfil: p, formularios: FORMS[a.p_solicitante].map((c) => ({ clave: c, nombre: NOMBRE[c], descripcion: "", con_campos: false })) } : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } }; }
    case "geoportal_tec_catalogo_filtros": return { formularios: [], plantas: [], zonas: [], puntos: [], descarga_max_filas: 50000, descarga_pagina_max: 5000, motivo_min: 10, motivo_max: 500 };
    case "geoportal_tec_avisos": if (a.p_solicitante === EMAILS.dist) {      // Etapa 2: los avisos de distribución salen de la base (tecnica.f_avisos con el bloque del Corte 14)
      const av = JSON.parse(sqlq("select tecnica.f_avisos(false, true)"));
      return { areas: { planta: false, distribucion: true, personal: true }, admin: false, avisos: av, total: av.length, rojos: av.filter((x) => x.nivel === "rojo").length, naranjas: av.filter((x) => x.nivel === "naranja").length, calculado_en: new Date().toISOString(), ms: 1 };
    }
    return { areas: { planta: false, distribucion: true, personal: false }, admin: a.p_solicitante === EMAILS.adm, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 1 };
    case "geoportal_campo_obtener_formulario": return a.p_solicitante === EMAILS.campo
      ? { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: true, supervisar: false, administrar_catalogo: false }, limites: { max_fotos: 6, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg" },
          zona: { lat_min: 10.1, lat_max: 10.8, lon_min: -73.6, lon_max: -72.9 }, grupos: [] }
      : { status: 403, cuerpo: { code: "42501", message: "Sin permiso" } };
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
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/redes-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/redes-evidencias/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT", "Access-Control-Allow-Headers": "content-type, x-upsert" }); return res.end(); }
      if (req.method === "PUT") {
        if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" });
        subidas.push({ ruta, bytes: cuerpo.length, mime: req.headers["content-type"] });
        sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', ${lit(ruta)}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })}) on conflict do nothing`);
        return json(200, { Key: `redes-evidencias/${ruta}` });
      }
    }
    if (u.pathname.startsWith("/storage/v1/object/sign/redes-evidencias/")) {      // lectura firmada (60 s)
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      return json(200, { signedURL: `/object/leer/redes-evidencias/${ruta}?token=l-${ruta.length}` });
    }
    if (u.pathname.startsWith("/storage/v1/object/leer/")) { res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(PNG); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, a });
      if (sinRuta && fn === "geoportal_redes_simulacion_aguas_arriba") return json(404, { code: "PGRST202", message: "Could not find the function" });
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      const r = rpcOtras(fn, a);
      return r && typeof r.status === "number" && r.cuerpo ? json(r.status, r.cuerpo) : json(200, r);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (Técnica, redes y campo) ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const p = new URL(r.url).pathname; return (p.includes("geoportal-redes") ? hs[1] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
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
const clic = (p, sel) => p.evaluate((sel) => { const b = document.querySelector(sel); if (!b || b.disabled) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel);
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t);
const captura = async (p, nombre) => { await new Promise((r) => setTimeout(r, 400)); await p.screenshot({ path: join(CAP, nombre), fullPage: true }); };
async function abrir(ancho, rol, activo, registro) {
  const p = await nav.newPage(); pagina = p;
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.setDefaultTimeout(60000);
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", async (m) => { if (m.type() !== "error" && m.type() !== "warn") return; const txt = m.text();
    if (!/status of 40[0349]|status of 500|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError|Failed to fetch|WebGL|GPU stall/.test(txt)) errores.push(`${ancho} ${rol} consola: ${txt}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}&activo=${activo}${registro ? "&registro=" + registro : ""}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 });
  return p;
}
const simular = async (p) => { await clicTexto(p, "button.tec-boton", "¿Qué válvulas cierro?"); await p.waitForFunction(() => !!document.querySelector("[data-testid=cie-aguas-arriba], [data-testid=cie-resultado]") || !!document.querySelector(".tec-aviso-error"), { timeout: 60000 }); };
const panelAu = (p) => p.evaluate(() => { const d = document.querySelector("[data-testid=cie-aguas-arriba]"); if (!d) return null;
  return { metodo: d.dataset.metodo, txt: d.innerText.replace(/\s+/g, " "), valvulas: [...d.querySelectorAll("li[data-valvula]")].map((x) => x.dataset.valvula), contratos: d.querySelector("[data-testid=cie-au-contratos]")?.textContent ?? null,
    comp: d.querySelector("[data-testid=cie-comprobacion]")?.innerText.replace(/\s+/g, " ") ?? "", coincide: d.querySelector("[data-testid=cie-comprobacion]")?.dataset.coincide, noCoincide: !!d.querySelector("[data-testid=cie-no-coincide]"),
    notas: d.querySelectorAll("[data-testid=cie-notas] li").length, cae: d.querySelector("[data-testid=cie-cae]")?.innerText.replace(/\s+/g, " ") ?? null }; });
const opciones = (p) => p.evaluate(() => [...document.querySelectorAll("[data-testid=cie-opciones] [role=tab]")].map((b) => ({ t: b.textContent.replace(/\s+/g, " ").trim(), sel: b.getAttribute("aria-selected") })));
const nf = new Intl.NumberFormat("es-CO"); const rango = (a, b) => (a !== b ? `De ${nf.format(a)} a ${nf.format(b)}` : nf.format(a));
const edgeF = (rol, accion, o = {}) => fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
  headers: { Authorization: `Bearer tok-${rol}`, ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined })
  .then(async (r) => ({ status: r.status, cache: r.headers.get("cache-control"), cuerpo: await r.json().catch(() => null) }));
const diagnostico = async (e) => { console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 300) + " · errores: " + errores.join(" | ").slice(0, 900) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-700).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); try { edge.kill(); } catch { /* ya terminó */ } process.exit(1); };
try {
ok(`0 la base trae los casos: ${CASO} se puede por aguas arriba; ${CAE?.cod ?? "ninguno"} cae al aislamiento total; en ${COINCIDE?.cod ?? "ninguno"} cota y modelo coinciden`, !R1.cae_a_total && R1.aguas_arriba.se_puede && CAE && COINCIDE);
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  if (ancho !== ANCHOS[0]) rehacer();
  rpcs.length = 0;
  // ===== A. El caso de David: la opción recomendada =====
  let p = await abrir(ancho, "op", CASO);
  await simular(p);
  let op = await opciones(p), d = await panelAu(p);
  ok(A("A1 «¿Qué válvulas cierro?» muestra dos opciones: «Cierre por aguas arriba», primera, elegida y marcada «Recomendada»; «Aislamiento total», segunda"), op.length === 2 && /^Cierre por aguas arriba Recomendada$/.test(op[0].t) && op[0].sel === "true" && op[1].t === "Aislamiento total" && op[1].sel === "false", JSON.stringify(op));
  ok(A(`A2 la lista de válvulas por donde entra el agua, igual a la de la base (${R1.aguas_arriba.valvulas.map((v) => v.codigo).join(", ")}), y los contratos sin agua`), d && d.metodo === "aguas_arriba" && d.valvulas.join() === R1.aguas_arriba.valvulas.map((v) => v.codigo).join()
    && d.contratos === rango(R1.aguas_arriba.contratos_min, R1.aguas_arriba.contratos_max) && new RegExp(`Por donde entra el agua a ${CASO}`).test(d.txt) && /Sentido del agua según la altura del terreno/.test(d.txt), JSON.stringify(d).slice(0, 500));
  ok(A("A3 muestra también el resultado del modelo (sus válvulas y contratos) y AVISA que no coincide con la cota"), d.comp.includes("Resultado del modelo") && R1.comprobacion.valvulas.slice(0, 6).every((v) => d.comp.includes(v.codigo)) && d.coincide === "no" && d.noCoincide
    && d.comp.includes(R1.comprobacion.texto), d.comp);
  ok(A("A4 las notas de la base (confirmar en campo; contratos aproximados) y el minimapa con la válvula numerada"), d.notas >= 2 && /confirme en campo/.test(d.txt)
    && await p.waitForFunction((n) => document.querySelectorAll(".cie-mapa-num").length === n, { timeout: 30000 }, Math.min(R1.aguas_arriba.valvulas.length, 30)).then(() => true).catch(() => false), d.txt.slice(-300));
  ok(A("A5 sin desborde horizontal y botones de 44 px o más; todavía no se ha calculado el aislamiento total"), (await sinDesborde(p)) && (await minimo(p, "[data-testid=panel-cierre] button")) >= 44 && rpcs.filter((x) => x.fn === "geoportal_redes_simulacion_cierre").length === 0);
  await captura(p, `despues_aguas_arriba_${ancho}.png`);
  await clic(p, '[data-opcion="total"]');
  await p.waitForSelector("[data-testid=cie-resultado]", { timeout: 60000 });
  const total = await p.evaluate(() => { const r = document.querySelector("[data-testid=cie-resultado]"); return { txt: r.innerText.replace(/\s+/g, " "), n: r.querySelectorAll("li[data-valvula]").length, sel: document.querySelector('[data-opcion="total"]').getAttribute("aria-selected"), au: !!document.querySelector("[data-testid=cie-aguas-arriba]") }; });
  ok(A("A6 «Aislamiento total», la segunda opción: la simulación de siempre (se calcula al pedirla), con sus válvulas y contratos"), total.sel === "true" && !total.au && new RegExp(`Aislamiento total de ${CASO}`).test(total.txt) && total.n >= 1 && /Contratos sin agua/.test(total.txt)
    && rpcs.filter((x) => x.fn === "geoportal_redes_simulacion_cierre").length === 1, total.txt.slice(0, 300));
  await captura(p, `despues_aislamiento_total_${ancho}.png`);
  await clic(p, '[data-opcion="aguas_arriba"]'); await p.waitForSelector("[data-testid=cie-aguas-arriba]");
  ok(A("A7 al volver a «Cierre por aguas arriba» sigue su resultado (no se vuelve a calcular)"), (await panelAu(p)).valvulas.join() === d.valvulas.join() && rpcs.filter((x) => x.fn === "geoportal_redes_simulacion_aguas_arriba").length === 1);
  await p.close();

  // ===== B. No se puede: lo dice y lleva al aislamiento total =====
  rpcs.length = 0;
  p = await abrir(ancho, "op", CAE.cod); await simular(p);
  d = await panelAu(p);
  ok(A(`B1 ${CAE.cod}: «Por aguas arriba no se puede» con el motivo de la base, y el botón para ver el aislamiento total`), d && d.metodo === "aislamiento_total" && /Por aguas arriba no se puede\./.test(d.cae ?? "") && d.cae.includes(CAE.r.aguas_arriba.texto) && d.valvulas.length === 0
    && await p.evaluate(() => !!document.querySelector("[data-testid=cie-ir-total]")), JSON.stringify(d).slice(0, 400));
  await captura(p, `despues_no_se_puede_${ancho}.png`);
  await clic(p, "[data-testid=cie-ir-total]"); await p.waitForSelector("[data-testid=cie-resultado]", { timeout: 60000 });
  ok(A("B2 cae al aislamiento total, que ya venía en la respuesta (sin otra consulta)"), await p.evaluate((c) => new RegExp(`Aislamiento total de ${c}`).test(document.querySelector("[data-testid=cie-resultado]").innerText), CAE.cod)
    && rpcs.filter((x) => x.fn === "geoportal_redes_simulacion_cierre").length === 0);
  await captura(p, `despues_cae_al_total_${ancho}.png`);
  await p.close();

  // ===== C. Cota y modelo coinciden =====
  p = await abrir(ancho, "op", COINCIDE.cod); await simular(p);
  d = await panelAu(p);
  ok(A(`C1 ${COINCIDE.cod}: cuando el modelo da las mismas válvulas, dice «Coincide» y no hay aviso`), d && d.coincide === "si" && !d.noCoincide && /Coincide: los dos dan las mismas válvulas/.test(d.comp) && d.valvulas.join() === COINCIDE.r.aguas_arriba.valvulas.map((v) => v.codigo).join(), JSON.stringify(d).slice(0, 400));
  await captura(p, `despues_coincide_${ancho}.png`);
  await p.close();

  // ===== D. Con un daño guardado: «Válvula cerrada» desde la lista de aguas arriba =====
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 300000, "mimetype": "image/jpeg"}')`);
  const DAN = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${prep.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", ubicacion_origen: "mapa", activo: CASO, lat: R1.activo.lat, lon: R1.activo.lon,
    t_detectado: sqlq(`select to_char(now() - interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: prep.fotos[0].ruta }] })})`)).codigo;
  // (lo abre el supervisor: la lista «Válvulas cerradas por …» sale de las afectaciones vigentes, que la base solo entrega a quien tiene el geovisor)
  p = await abrir(ancho, "dist", CASO, DAN); await simular(p);
  const v1 = R1.aguas_arriba.valvulas[0].codigo;
  ok(A("D1 con el daño guardado, cada válvula de aguas arriba trae «Válvula cerrada»"), await p.evaluate((v) => document.querySelector(`[data-testid=cie-aguas-arriba] li[data-valvula="${v}"] button`)?.textContent === "Válvula cerrada", v1));
  await p.evaluate((v) => document.querySelector(`[data-testid=cie-aguas-arriba] li[data-valvula="${v}"] button`).click(), v1);
  await p.waitForSelector("[data-testid=cie-pedir]"); await clicTexto(p, "[data-testid=cie-pedir] button", "Confirmar");
  ok(A(`D2 al confirmar, ${v1} queda cerrada por ${DAN} (en la base y en el panel)`), await p.waitForFunction((v) => !!document.querySelector(`[data-testid=cie-cerradas] li[data-valvula="${v}"]`) && /cerrada \(/.test(document.querySelector(".tec-aviso-ok")?.innerText ?? ""), { timeout: 40000 }, v1).then(() => true).catch(() => false)
    && Number(sqlq(`select count(*) from redes.valvula_maniobras m join redes.activos a on a.id = m.valvula_id where a.codigo = '${v1}' and m.tipo = 'cerrar' and m.dano_id is not null`)) >= 1, await texto(p).then((t) => t.slice(0, 400)));
  await captura(p, `despues_valvula_cerrada_${ancho}.png`);
  await p.close();

  // ===== E. El servidor todavía no tiene la función nueva: queda como antes =====
  sinRuta = true; rpcs.length = 0;
  p = await abrir(ancho, "op", CASO); await simular(p);
  ok(A("E1 sin la función nueva en el servidor, el panel queda como antes: solo el aislamiento total («Para aislar …»), sin opciones ni error"), await p.evaluate((c) => !document.querySelector("[data-testid=cie-opciones]") && !document.querySelector("[data-testid=cie-aguas-arriba]")
    && new RegExp(`Para aislar ${c}`).test(document.querySelector("[data-testid=cie-resultado]")?.innerText ?? "") && !document.querySelector(".tec-aviso-error"), CASO));
  sinRuta = false;
  await p.close();
}

// ===== F. La Edge =====
let r = await edgeF("op", "simulacion_aguas_arriba", { cuerpo: { activo: CASO } });
ok("F1 simulacion_aguas_arriba (POST) desde un activo: método, criterio, válvulas, comprobación y notas; sin caché; sin datos de suscriptores", r.status === 200 && r.cuerpo.metodo === "aguas_arriba" && r.cuerpo.aguas_arriba.valvulas.length === R1.aguas_arriba.valvulas.length
  && typeof r.cuerpo.comprobacion.coincide === "boolean" && Array.isArray(r.cuerpo.notas) && r.cache === "no-store" && !/nombre_suscriptor|telefono|direccion/i.test(JSON.stringify(r.cuerpo)), JSON.stringify(r.cuerpo).slice(0, 200));
r = await edgeF("op", "simulacion_aguas_arriba", { cuerpo: { lat: R1.activo.lat, lon: R1.activo.lon } });
ok("F2 … y desde una posición (va en el cuerpo): el tramo más cercano", r.status === 200 && typeof r.cuerpo.metodo === "string", JSON.stringify(r.cuerpo).slice(0, 200));
ok("F3 rechaza por forma: sin activo ni posición, con un dato de más o por GET (405)", (await edgeF("op", "simulacion_aguas_arriba", { cuerpo: {} })).status === 400 && (await edgeF("op", "simulacion_aguas_arriba", { cuerpo: { activo: CASO, criterio: "modelo" } })).status === 400
  && (await edgeF("op", "simulacion_aguas_arriba")).status === 405);
ok("F4 mismos permisos que la simulación de siempre: al supervisor, 200; a Comercial y a quien no es de Técnica, 403", (await edgeF("dist", "simulacion_aguas_arriba", { cuerpo: { activo: CASO } })).status === 200
  && (await edgeF("campo", "simulacion_aguas_arriba", { cuerpo: { activo: CASO } })).status === 403 && (await edgeF("nada", "simulacion_aguas_arriba", { cuerpo: { activo: CASO } })).status === 403
  && (await edgeF("campo", "simulacion_cierre", { cuerpo: { activo: CASO } })).status === 403);
ok("F5 un activo que no existe: el mismo rechazo de la base que en la simulación de siempre", await (async () => { const a = await edgeF("op", "simulacion_aguas_arriba", { cuerpo: { activo: "RED-99999999" } }), b = await edgeF("op", "simulacion_cierre", { cuerpo: { activo: "RED-99999999" } }); return a.status === b.status && a.status >= 400; })());
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
ok("Z2 ninguna RPC sin simular", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { await diagnostico(e); }

await nav.close(); edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_chrome`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
