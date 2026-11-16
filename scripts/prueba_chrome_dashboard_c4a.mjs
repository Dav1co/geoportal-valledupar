// Técnica · Fase 1 · Corte 4a · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada → Edges REALES geoportal-tecnica, geoportal-redes y geoportal-admin (Deno) → PostgREST mínimo en Node que llama a las RPC REALES del PostGIS local
//   (1a, carga completa, Cortes 2, 3a, 3b y 4a, con las 4 funciones de permisos con su texto vivo), más un Storage simulado.
// A 390 px y en escritorio: el Dashboard distribución (selector PTAP | distribución, daños con ocultar, reabrir y el tercero auditado; intervenciones con anular;
// reportes del bot con convertir y descartar; no identificados con «Crear el activo»), quién ve cada dashboard, el sector del daño (1 a 100), los tiempos de
// reparación con su casilla, el orden nuevo de «Registrar intervención» y la casilla «Dashboard distribución» en Administración.
//   node scripts/prueba_chrome_dashboard_c4a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_dashboard_c4a"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_dashboard_c4a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", adm: "zt.admin@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co" };
const PERFIL = { [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.adm]: "admin", [EMAILS.planta]: "supervisor", [EMAILS.dist]: "operador" };

if (Number(sqlq("select count(*) from redes.activo_vigente_mat")) < 35781) throw new Error("La base local no tiene la carga publicada");
if (sqlq("select count(*) from information_schema.columns where column_name = 'sector_num'") !== "1") throw new Error("La base local no tiene el Corte 4a");
const n0 = 0;
const guardados = new Map();      // ruta → bytes subidos (para servir la lectura firmada)
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_dashboard_c4a_"));
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
    import { Admin } from "./src/components/Admin.tsx";
    const pantalla = new URLSearchParams(location.search).get("pantalla");
    createRoot(document.getElementById("raiz")).render(pantalla === "admin" ? <Admin onVolver={() => {}} /> : <AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head><body><div id="raiz" style="display:flex;min-height:100vh"></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST + Storage simulados; las RPC de redes van a la base local REAL ----------
const rpcs = [], subidas = [], lecturas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
  try {
    const out = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const t = out.trim();
    return { status: 200, cuerpo: fn === "geoportal_redes_mvt" ? t : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
const PNG_BLANCO = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAACwElEQVR4nO3TMQ0AMAzAsPKnumcagsHoEUsGkCfz7oGsWS+ARQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQNoHNckqBAbZ8j0AAAAASUVORK5CYII=", "base64");   // 256×256 gris claro
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
    if (u.pathname.startsWith("/storage/v1/object/sign/redes-evidencias/")) {       // lectura firmada (Corte 3b): firmar (POST) y descargar (GET)
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") { lecturas.push(ruta); return json(200, { signedURL: `/object/sign/redes-evidencias/${ruta}?token=l-${ruta.length}` }); }
      if (u.searchParams.get("token") !== `l-${ruta.length}`) return json(400, { error: "token" });
      const b = guardados.get(ruta); res.writeHead(200, { "Content-Type": b ? "image/jpeg" : "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(b ?? PNG_BLANCO);
    }
    if (u.pathname.startsWith("/storage/v1/object/upload/sign/redes-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/redes-evidencias/")[1]);
      if (req.method === "POST") return json(200, { url: `/object/upload/sign/redes-evidencias/${ruta}?token=t-${ruta.length}`, token: `t-${ruta.length}` });
      if (req.method === "OPTIONS") { res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "PUT", "Access-Control-Allow-Headers": "content-type, x-upsert" }); return res.end(); }
      if (req.method === "PUT") {
        if (u.searchParams.get("token") !== `t-${ruta.length}`) return json(400, { error: "token" });
        subidas.push({ ruta, bytes: cuerpo.length, mime: req.headers["content-type"] }); guardados.set(ruta, cuerpo);
        sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', ${lit(ruta)}, ${lit({ size: cuerpo.length, mimetype: req.headers["content-type"] })}) on conflict do nothing`);
        return json(200, { Key: `redes-evidencias/${ruta}` });
      }
    }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo.toString() || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, args: a });
      if (fn === "geoportal_tec_mis_formularios") {
        const p = PERFIL[a.p_solicitante];
        return p ? json(200, { perfil: p, formularios: [{ clave: "danos_fallas", nombre: "Daño o falla", descripcion: "", con_campos: false }, { clave: "mantenimiento", nombre: "Registrar intervención", descripcion: "", con_campos: false }] }) : json(403, { code: "42501", message: "Sin permiso" });
      }
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      // Administración (Corte 4a): las funciones de permisos reales de la base local
      if (fn === "geoportal_pausa_estado") return json(200, { activa: false, afectados: 0 });
      if (fn === "geoportal_aislamiento_verificado") return json(200, true);
      if (fn === "geoportal_admin_listar") return json(200, JSON.parse(sqlq(`select coalesce(json_agg(t), '[]') from public.geoportal_admin_listar(${lit(a.p_solicitante)}) t`)));
      if (fn === "geoportal_es_admin" || fn === "geoportal_admin_permisos") {
        const args = Object.entries(a).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
        try { return json(200, JSON.parse(sqlq(`select to_json(public.${fn}(${args}))`))); } catch (e) { return json(400, { code: "XX000", message: String(e.stderr || e.message).slice(0, 300) }); }
      }
      if (fn === "geoportal_log") return json(200, null);
      return json(404, { code: "PGRST202", message: "no existe" });
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
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-admin/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => { const c = new URL(r.url).pathname; return (c.includes("geoportal-redes") ? hs[1] : c.includes("geoportal-admin") ? hs[2] : hs[0])(r); });`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });      // si la prueba se cae a mitad, no deja la Edge escuchando
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 700) }); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation", "camera"]);
const errores = [];
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = async (p, re, ms = 15000) => {
  try { await p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source); }
  catch { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error(`no apareció /${re.source}/; pantalla: ${(await texto(p)).slice(0, 1500)} · edge: ${edgeLog.slice(-800)}`); }
};
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const elegirSelect = (p, sel, valor) => p.select(sel, valor);
const minimos = (p) => p.evaluate(() => Math.min(...[...document.querySelectorAll(".dan-opcion:not(.dan-opcion-off), .dan .tec-boton, .dan .tec-boton-sec, .dan-check")].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)));
async function abrir(ancho, rol, gps) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  // Sin intercepción de peticiones: con ella, las peticiones del worker de MapLibre (las teselas vectoriales) quedan en pausa. La base de OSM se bloquea con
  // --host-resolver-rules (sin red externa) y sus fallos se ignoran: no son de la app.
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("response", (r) => { if (r.url().includes("accion=tesela")) teselas.push(`${r.status()} ${r.url().split("?")[1]}`); });
  p.on("console", async (m) => {
    if (m.type() !== "error" && m.type() !== "warn") return;
    let t = m.text();
    if (/JSHandle@/.test(t)) t = (await Promise.all(m.args().map((a) => a.evaluate((x) => (x instanceof Error ? `${x.name}: ${x.message} ${x.url ?? ""} ${x.status ?? ""}` : String(x))).catch(() => `? (${m.text()} @ ${m.location()?.url ?? ""}:${m.location()?.lineNumber ?? ""})`)))).join(" ");
    if (!/status of 40[034]|Failed to load resource|GL Driver Message|tile\.openstreetmap\.org|AJAXError: Failed to fetch|^TypeError: Failed to fetch/.test(t)) errores.push(`${ancho} ${rol} consola ${m.type()}: ${t}`);
  });
  if (gps) await p.setGeolocation({ latitude: gps[0], longitude: gps[1], accuracy: 6 });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true, { timeout: 15000 }).catch((e) => { console.log("NO CARGA", errores.join(" | ")); throw e; });
  try { await esperarTexto(p, /1\. Activo y ubicación/); } catch (e) { await p.screenshot({ path: join(CAP, `fallo_abrir_${rol}_${ancho}.png`), fullPage: true }); console.log("PANTALLA", rol, (await texto(p)).slice(0, 600)); throw e; }
  return p;
}
/** Espera a que el minimapa tenga red dibujada. */
const teselas = [];
const esperarRed = async (p) => {
  try { await p.waitForFunction(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; return m && m.loaded() && m.queryRenderedFeatures({ layers: ["tramos", "nodos"] }).length > 0; }, { timeout: 30000 }); }
  catch {
    const est = await p.evaluate(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; if (!m) return "sin mapa"; return JSON.stringify({ cargado: m.loaded(), zoom: m.getZoom(), centro: m.getCenter(), fuente: m.isSourceLoaded("red"), feats: m.queryRenderedFeatures().length, errores: window.__errMapa ?? [] }); });
    await p.screenshot({ path: join(CAP, "fallo_mapa.png") });
    throw new Error(`la red no se dibujó: ${est} · teselas: ${JSON.stringify(teselas.slice(-6))} · mvt en la base: ${rpcs.filter((r) => r.fn === "geoportal_redes_mvt").length} · ejemplo: ${JSON.stringify(rpcs.filter((r) => r.fn === "geoportal_redes_mvt").slice(0, 2))} · consola: ${errores.join(" | ").slice(0, 1500)}`);
  }
};
/** Punto en pantalla de un tramo visible (a mitad de su primer segmento), lejos de los nodos. */
const puntoDeTramo = (p) => p.evaluate(() => {
  const el = document.querySelector(".dan-mini-mapa"); el.scrollIntoView({ block: "center" }); const m = el.__mapa; const r = el.getBoundingClientRect();
  for (const f of m.queryRenderedFeatures({ layers: ["tramos"] })) {
    const c = f.geometry.type === "LineString" ? f.geometry.coordinates : f.geometry.coordinates[0];
    for (let i = 0; i + 1 < c.length; i++) {
      const px = m.project([(c[i][0] + c[i + 1][0]) / 2, (c[i][1] + c[i + 1][1]) / 2]);
      if (px.x < 30 || px.y < 30 || px.x > r.width - 30 || px.y > r.height - 30) continue;
      if (m.queryRenderedFeatures([[px.x - 16, px.y - 16], [px.x + 16, px.y + 16]], { layers: ["nodos"] }).length) continue;
      return { x: r.left + px.x, y: r.top + px.y, codigo: f.properties.codigo };
    }
  }
  return null;
});
const tocar = async (p, x, y, movil) => { if (movil) await p.touchscreen.tap(x, y); else await p.mouse.click(x, y); };
async function foto(p, momento) {
  await clicTexto(p, "button", `📷 ${momento}`); await p.waitForSelector(".campo-capturar:not([disabled])", { timeout: 15000 });
  const n = await p.evaluate(() => document.querySelectorAll(".dan-foto").length);
  await p.click(".campo-capturar"); await p.waitForFunction((n) => document.querySelectorAll(".dan-foto").length === n + 1, { timeout: 15000 }, n);
}

// ---------- 5. Recorridos del Corte 4a ----------
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
const marcar = (p, sel) => p.evaluate((sel) => { const l = [...document.querySelectorAll(".dan-check")].find((x) => new RegExp(sel).test(x.textContent)); l.querySelector("input").click(); return true; }, sel);
const seccion = (p, c) => p.evaluate((c) => [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c))?.innerText ?? "", c);
const enSeccion = (p, c, sel, t) => p.evaluate((c, sel, t) => { const s = [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)); s.scrollIntoView({ block: "center" });
  const b = [...s.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t)); if (!b) return false; b.click(); return true; }, c, sel, t);
const ponerEn = (p, c, sel, v) => p.evaluate((c, sel, v) => { const s = [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes(c)); const el = s.querySelector(sel);
  const proto = el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v);
  el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); return true; }, c, sel, v);
/** Datos de prueba de cada vuelta, con las RPC reales (formularios de los Cortes 2 y 3a). */
function datosDeLaVuelta(ancho) {
  const dano = (extra) => {
    const p = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
    sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${p.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
    return JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${p.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]),
      ubicacion_origen: "gps", t_detectado: iso(-300), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "desconocida", fotos: [{ n: 1, momento: "dano", ruta: p.fotos[0].ruta }], ...extra })})`)).codigo;
  };
  const itv = (extra) => {
    const p = JSON.parse(sqlq(`select public.geoportal_redes_preparar_intervencion('${EMAILS.op}', 1, 0)`));
    sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${p.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
    return JSON.parse(sqlq(`select public.geoportal_redes_crear_intervencion('${EMAILS.op}', '${p.intervencion_id}', ${lit({ nace_de: "programada", tipo: "preventivo", sistema: "acueducto", activo: V85[0],
      lat: Number(V85[1]), lon: Number(V85[2]), ubicacion_origen: "gps", t_inicio: iso(-180), t_fin: iso(-120), descripcion: `Revisión de prueba ${ancho}`, ejecutor: "emdupar",
      fuentes: [{ aportante: "emdupar" }], archivos: [{ n: 1, clase: "despues", ruta: p.fotos[0].ruta }], ...extra })})`)).codigo;
  };
  const conTercero = dano({ causa_clase: "terceros", tercero_tipo: "vehiculo", tercero_nombre: `Placa ZT${ancho}`, sector: 4 });
  const atendido = dano({ t_inicio_reparacion: iso(-200), t_restablecido: iso(-150) });
  const intervencion = itv({});
  const noIdent = itv({ sistema: "alcantarillado", activo: null, no_identificado: `Pozo sin código ${ancho}`, lat: Number(V85[1]) + 0.0002, lon: Number(V85[2]) + 0.0002, ubicacion_origen: "mapa", tipo: "correctivo" });
  const bot1 = sqlq(`select redes.f_reporte_externo_recibir('{"radicado": "ZT-${ancho}-1", "canal": "telegram", "tipo": "Fuga", "lat": ${V85[1]}, "lon": ${V85[2]}, "descripcion": "Sale agua del andén"}')`);
  const bot2 = sqlq(`select redes.f_reporte_externo_recibir('{"radicado": "ZT-${ancho}-2", "canal": "telegram", "tipo": "Otro", "lat": ${V85[1]}, "lon": ${V85[2]}, "descripcion": "Repetido"}')`);
  return { conTercero, atendido, intervencion, noIdent, bot1, bot2 };
}
const minimosDash = (p) => p.evaluate(() => Math.min(...[...document.querySelectorAll(".dash-redes .dan-opcion, .dash-redes .tec-boton, .dash-redes .tec-boton-sec, .tec-chip-form")].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)));

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`, movil = ancho < 500;
  const D = datosDeLaVuelta(ancho);
  // ===== A. Quién ve cada dashboard =====
  let p = await abrir(ancho, "planta", null); let t = await texto(p);
  ok(`${tag} el supervisor de planta ve el Dashboard PTAP y no el de distribución`, /Dashboard PTAP/.test(t) && !/Dashboard distribución/.test(t));
  await p.close();
  p = await abrir(ancho, "dist", null); t = await texto(p);
  ok(`${tag} el supervisor de distribución ve el Dashboard distribución y no el PTAP`, /Dashboard distribución/.test(t) && !/Dashboard PTAP/.test(t) && /Ficha de activos \(redes\)/.test(t));
  await p.close();
  p = await abrir(ancho, "op", null); t = await texto(p);
  ok(`${tag} el operador no ve ninguno de los dos dashboards`, !/Dashboard distribución/.test(t) && !/Dashboard PTAP/.test(t));
  await p.close();

  // ===== B. Supervisor con los dos: selector y pestañas =====
  p = await abrir(ancho, "sup", null);
  await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Dashboard distribución[\s\S]*No identificados/);     // §34: encabezado común (ya no hay subtítulo)
  t = await texto(p);
  ok(`${tag} el selector PTAP | distribución aparece arriba, dentro del encabezado (§34; tiene los dos) y las 4 pestañas`, (await p.$$(".tdash-cab .tdash-selector .tdash-sel")).length === 2
     && ["No identificados", "Intervenciones", "Daños y fallas", "Reportes del bot"].every((x) => t.includes(x)));
  // no identificados: crear el activo
  await esperarTexto(p, new RegExp(D.noIdent));
  await enSeccion(p, D.noIdent, ".dan-opcion", "Crear el activo");
  await p.waitForFunction((c) => [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c))?.querySelector("select option[value='POZ']"), { timeout: 10000 }, D.noIdent);
  await ponerEn(p, D.noIdent, "select", "POZ"); await ponerEn(p, D.noIdent, `#mot-${D.noIdent}`, "Pozo visto en la visita de campo");
  await enSeccion(p, D.noIdent, ".itv-guardar", "Crear y asociar");
  await esperarTexto(p, new RegExp(`Se creó POZ-\\d{6} .*${D.noIdent}`));
  const poz = sqlq(`select activo_codigo from redes.v_intervencion where codigo = '${D.noIdent}'`);
  ok(`${tag} «Crear el activo» desde la bandeja: ${poz} «por verificar», y la intervención queda sobre él`, /^POZ-\d{6}$/.test(poz) && sqlq(`select por_verificar from redes.v_activo_vigente where codigo = '${poz}'`) === "t");
  // daños: tercero, ocultar, reabrir
  await clicTexto(p, "[role=tab]", "Daños y fallas"); await esperarTexto(p, new RegExp(D.conTercero));
  t = await seccion(p, D.conTercero);
  ok(`${tag} el daño muestra su sector (4) y que tiene tercero, sin el nombre`, /sector 4/.test(t) && /Ver el nombre o la placa del tercero/.test(t) && !new RegExp(`Placa ZT${ancho}`).test(t));
  await enSeccion(p, D.conTercero, "button", "Ver el nombre o la placa"); await esperarTexto(p, new RegExp(`Tercero: Placa ZT${ancho}`));
  ok(`${tag} ver el tercero lo muestra y deja la lectura auditada (sin el valor)`, sqlq(`select count(*) from public.geoportal_auditoria where accion = 'redes_ver_tercero' and referencia = '${D.conTercero}' and email = '${EMAILS.sup}' and detalle::text not like '%Placa%'`) === "1");
  await enSeccion(p, D.conTercero, "button", "Ocultar"); await p.waitForSelector(`#do-${D.conTercero}`);
  await ponerEn(p, D.conTercero, `#do-${D.conTercero}`, "Dato de prueba del celular");
  await enSeccion(p, D.conTercero, ".itv-guardar", "Confirmar"); await esperarTexto(p, new RegExp(`${D.conTercero} quedó oculto`));
  ok(`${tag} ocultar el daño con motivo: queda oculto (evento; el daño no se borra)`, sqlq(`select estado from redes.v_dano where codigo = '${D.conTercero}'`) === "oculto" && sqlq(`select count(*) from redes.danos where codigo = '${D.conTercero}'`) === "1");
  await clicTexto(p, ".dan-opcion", "Todos"); await esperarTexto(p, new RegExp(D.atendido));
  await enSeccion(p, D.atendido, "button", "Reabrir"); await p.waitForSelector(`#da-${D.atendido}`);
  await ponerEn(p, D.atendido, `#da-${D.atendido}`, "Volvió a salir agua en el mismo punto");
  await enSeccion(p, D.atendido, ".itv-guardar", "Confirmar"); await esperarTexto(p, new RegExp(`${D.atendido} quedó en atención`));
  ok(`${tag} reabrir un daño atendido: queda en atención`, sqlq(`select estado from redes.v_dano where codigo = '${D.atendido}'`) === "en_atencion");
  await p.waitForFunction((c) => [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c))?.innerText.includes("EN ATENCIÓN") || [...document.querySelectorAll(".itv-bandeja")].find((s) => s.innerText.includes(c))?.innerText.toLowerCase().includes("en atención"), { timeout: 10000 }, D.atendido);
  ok(`${tag} tras reabrir, la tarjeta se actualiza, se cierra el formulario y el aviso queda arriba de la lista`, !(await p.$(`#da-${D.atendido}`)) && /quedó en atención/.test(await texto(p)));
  ok(`${tag} el Dashboard distribución no desborda y sus botones miden 44 px o más`, (await sinDesborde(p)) && (await minimosDash(p)) >= 44, String(await minimosDash(p)));
  await p.screenshot({ path: join(CAP, `dashboard_danos_${ancho}.png`), fullPage: true });
  // intervenciones: anular
  await clicTexto(p, "[role=tab]", "Intervenciones"); await clicTexto(p, ".dan-opcion", "Recientes"); await esperarTexto(p, new RegExp(D.intervencion));
  await enSeccion(p, D.intervencion, "button", "Anular"); await p.waitForSelector(`#an-${D.intervencion}`);
  await ponerEn(p, D.intervencion, `#an-${D.intervencion}`, "Se registró dos veces la misma revisión");
  await enSeccion(p, D.intervencion, ".itv-guardar", "Confirmar"); await esperarTexto(p, new RegExp(`${D.intervencion} quedó anulada`));
  ok(`${tag} anular la intervención con motivo: queda «anulada»`, sqlq(`select estado from redes.v_intervencion where codigo = '${D.intervencion}'`) === "anulada");
  // reportes del bot
  await clicTexto(p, "[role=tab]", "Reportes del bot"); await esperarTexto(p, new RegExp(`ZT-${ancho}-1`));
  await enSeccion(p, `ZT-${ancho}-1`, "button", "Convertir en daño o falla"); await p.waitForSelector(`#bs-${D.bot1}`);
  await ponerEn(p, `ZT-${ancho}-1`, `#bs-${D.bot1}`, "acueducto"); await ponerEn(p, `ZT-${ancho}-1`, `#bt-${D.bot1}`, "fuga"); await ponerEn(p, `ZT-${ancho}-1`, `#br-${D.bot1}`, "alto");
  await enSeccion(p, `ZT-${ancho}-1`, ".itv-guardar", "Convertir"); await esperarTexto(p, /Quedó como el daño DAN-\d{6}/);
  ok(`${tag} convertir el reporte del bot en daño: enlazado al radicado`, sqlq(`select count(*) from redes.v_reporte_externo where radicado = 'ZT-${ancho}-1' and dano_codigo is not null`) === "1");
  await esperarTexto(p, new RegExp(`ZT-${ancho}-2`));
  await enSeccion(p, `ZT-${ancho}-2`, "button", "Descartar"); await p.waitForSelector(`#bd-${D.bot2}`);
  await ponerEn(p, `ZT-${ancho}-2`, `#bd-${D.bot2}`, "Es el mismo reporte de la fuga anterior");
  await enSeccion(p, `ZT-${ancho}-2`, ".itv-guardar", "Confirmar"); await esperarTexto(p, new RegExp(`ZT-${ancho}-2 quedó descartado`));
  ok(`${tag} descartar el otro con motivo`, sqlq(`select estado_bot from redes.v_reporte_externo where radicado = 'ZT-${ancho}-2'`) === "descartado");
  await p.screenshot({ path: join(CAP, `dashboard_bot_${ancho}.png`), fullPage: true });
  await p.close();

  // ===== C. Daño: sector 1 a 100 y tiempos de reparación con su casilla =====
  p = await abrir(ancho, "op", [Number(V85[1]), Number(V85[2])]);
  t = await texto(p);
  ok(`${tag} el daño ya no pide los tiempos de reparación hasta marcar «El daño ya se reparó»`, !(await p.$("#dan-trep")) && /El daño ya se reparó/.test(t) && !/sin evidencia fotográfica/.test(t));
  await clicTexto(p, ".dan-opcion", "Acueducto"); await esperarTexto(p, /Se preseleccionó el activo más cercano/);
  await clicTexto(p, ".dan-opcion", "Fuga o tubería rota"); await clicTexto(p, ".dan-opcion", "Rotura parcial"); await clicTexto(p, ".dan-opcion", "Bajo"); await clicTexto(p, ".dan-opcion", "Desconocida");
  await poner(p, "#dan-sector", "150"); await poner(p, "#dan-usuarios", "2,5");
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Falta completar/);
  t = await texto(p);
  ok(`${tag} la pantalla revisa los topes antes de enviar: sector 1 a 100 y usuarios sin decimales`, /El sector va de 1 a 100/.test(t) && /Los usuarios sin servicio va de 0 a 1\.000\.000, sin decimales/.test(t));
  await poner(p, "#dan-sector", "4"); await poner(p, "#dan-usuarios", "30");
  await foto(p, "El daño");
  await clicTexto(p, "button", "Guardar daño o falla"); await esperarTexto(p, /Daño guardado: DAN-\d{6}/, 30000);
  const dc = (await texto(p)).match(/DAN-\d{6}/)[0];
  ok(`${tag} guardado ${dc} con el sector 4 como número, reportado (sin tiempos de reparación)`, sqlq(`select sector_num || '|' || estado from redes.danos n join redes.v_dano d on d.id = n.id where n.codigo = '${dc}'`) === "4|reportado");
  // ===== D. «Registrar la reparación»: el orden nuevo de la intervención =====
  await clicTexto(p, "button", "Registrar la reparación"); await esperarTexto(p, /1\. De dónde nace y tipo/);
  await esperarTexto(p, new RegExp(`${dc}\\s*· Fuga`));
  const orden = await p.evaluate(() => {
    const sec = [...document.querySelectorAll(".itv > section")];
    const iMapa = sec.findIndex((s) => s.querySelector(".dan-mini")), iDanos = sec.findIndex((s) => s.querySelector(".itv-danos")), iCierre = sec.findIndex((s) => s.classList.contains("itv-cierre"));
    return { iMapa, iDanos, iCierre, ultima: sec.length - 1, s1: sec[0].innerText.includes("Daño o falla que se atiende") };
  });
  ok(`${tag} «Daño o falla que se atiende» va después del mapa (misma sección) y «queda resuelto» al final, antes de Guardar (§25.5 y §25.6)`, orden.iDanos === orden.iMapa && orden.iDanos > 0
     && orden.iCierre === orden.ultima && !orden.s1, JSON.stringify(orden));
  await p.screenshot({ path: join(CAP, `intervencion_orden_${ancho}.png`), fullPage: true });
  await p.waitForFunction(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; return !m || (m.loaded() && m.areTilesLoaded()); }, { timeout: 15000 }).catch(() => {});
  await p.close();
  // sin daños abiertos: el aviso
  p = await abrir(ancho, "op", null);
  await clicTexto(p, ".tec-chip-form", "Registrar intervención"); await esperarTexto(p, /1\. De dónde nace y tipo/);
  await clicTexto(p, ".dan-opcion", "Daño o falla"); await clicTexto(p, ".dan-opcion", "Alcantarillado"); await p.waitForSelector(".dan-mini-mapa");
  await p.evaluate((lat, lon) => { const m = document.querySelector(".dan-mini-mapa").__mapa; m.jumpTo({ center: [lon - 0.01, lat - 0.01], zoom: 17 }); }, Number(V85[1]), Number(V85[2]));
  await marcar(p, "No puedo identificar el activo"); await poner(p, "#itv-quees", "Cámara");
  const c1 = await p.evaluate(() => { const el = document.querySelector(".dan-mini-mapa"); el.scrollIntoView({ block: "center" }); const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  if (movil) await p.touchscreen.tap(c1.x, c1.y); else await p.mouse.click(c1.x, c1.y);
  await esperarTexto(p, /No hay daños abiertos en este activo ni cerca/);
  ok(`${tag} sin daños abiertos cerca lo dice (§25.7)`, true);
  await p.waitForFunction(() => { const m = document.querySelector(".dan-mini-mapa")?.__mapa; return !m || (m.loaded() && m.areTilesLoaded()); }, { timeout: 15000 }).catch(() => {});
  await p.close();
}

// ===== E. Administración: la casilla «Dashboard distribución» =====
for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${ancho} admin: ${e.message}`));
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=adm&pantalla=admin`); await p.waitForFunction(() => window.__listo === true);
  await esperarTexto(p, /zt\.oper@emdupar\.gov\.co/);
  await p.evaluate(() => { const fila = [...document.querySelectorAll("tr")].find((r) => r.innerText.includes("zt.oper@emdupar.gov.co")); [...fila.querySelectorAll("button")].find((b) => /Editar|Permisos/.test(b.textContent))?.click(); });
  await esperarTexto(p, /Dashboard distribución \(supervisor de distribución\)/);
  const valor = ancho === 390;
  await p.evaluate((v) => { const l = [...document.querySelectorAll("label")].find((x) => /Dashboard distribución \(supervisor de distribución\)/.test(x.textContent)); const i = l.querySelector("input") ?? document.getElementById(l.htmlFor);
    if (i.checked !== v) i.click(); }, valor);
  await p.evaluate(() => [...document.querySelectorAll("button")].find((b) => /^Guardar/.test(b.textContent.trim()) && b.offsetParent)?.click());
  await esperarTexto(p, /Permisos actualizados para zt\.oper@emdupar\.gov\.co/);
  ok(`${tag} Administración: la casilla «Dashboard distribución» ${valor ? "da" : "quita"} el permiso (Edge geoportal-admin real y función de la base)`,
     sqlq(`select ver_dashboard_redes from public.geoportal_lista_blanca where email = '${EMAILS.op}'`) === (valor ? "t" : "f"));
  ok(`${tag} Administración no desborda`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `admin_permiso_${ancho}.png`), fullPage: false });
  await p.close();
}
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
