// Técnica · Fase 1 · Corte 5a · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada → Edges REALES (Deno) → PostgREST mínimo en Node que llama a las RPC REALES del PostGIS local (1a con la carga completa, 2, 3a, 3b, 4a, 4b y 5a).
// A 390 px y en escritorio, lo que el 5a cambia en pantalla (§28): el supervisor de distribución asigna y quita los formularios de distribución desde
// Personal (y el operador puede o no abrir «Registrar intervención»), crea cuadrillas, y la intervención del supervisor muestra su tope (30 días y 72 h).
//   node scripts/prueba_chrome_c5a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_c5a"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_c5a.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54995, P_EDGE = 54996;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { sinform: "zt.oper.sinform@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", sup: "zt.super@emdupar.gov.co", adm: "zt.admin@emdupar.gov.co", planta: "zt.planta@emdupar.gov.co", dist: "zt.dist@emdupar.gov.co" };
const PERFIL = { [EMAILS.sinform]: "operador", [EMAILS.op]: "operador", [EMAILS.sup]: "supervisor", [EMAILS.adm]: "admin", [EMAILS.planta]: "supervisor", [EMAILS.dist]: "operador" };

if (Number(sqlq("select count(*) from redes.activo_vigente_mat")) < 35781) throw new Error("La base local no tiene la carga publicada");
if (sqlq("select to_regclass('tecnica.puntos_ubicacion') is not null") !== "t") throw new Error("La base local no tiene el Corte 5a");
const n0 = 0;
const guardados = new Map();      // ruta → bytes subidos (para servir la lectura firmada)
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_c5a_"));
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

// ---------- 5. Recorridos del Corte 4b ----------
const iso = (min) => sqlq(`select to_char(now() + interval '${min} minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')`);
const tarjeta = (p, c) => p.evaluate((c) => [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((s) => s.innerText.includes(c)).pop()?.innerText ?? "", c);
const enTarjeta = async (p, c, sel, t) => { const r = await enTarjeta0(p, c, sel, t); if (!r) { await p.screenshot({ path: join(CAP, "fallo_tarjeta.png"), fullPage: true }); throw new Error(`no hay «${t}» en la tarjeta de «${c}»: ${(await tarjeta(p, c)).slice(0, 600)}`); } return r; };
const enTarjeta0 = (p, c, sel, t) => p.evaluate((c, sel, t) => { const s = [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((x) => x.innerText.includes(c)).pop(); if (!s) return false;
  s.scrollIntoView({ block: "center" }); const b = [...s.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.click(); return true; }, c, sel, t);
const valorEn = (p, c, sel, v) => p.evaluate((c, sel, v) => { const s = [...document.querySelectorAll(".tec-tarjeta, .gest-item")].filter((x) => x.innerText.includes(c)).pop(); const el = s.querySelector(sel);
  if (el.type === "checkbox") { if (el.checked !== v) el.click(); return true; }
  const proto = el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v);
  el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); return true; }, c, sel, v);
const pestana = async (p, n) => { if (!(await clicTexto(p, "[role=tab]", n))) throw new Error(`no está la pestaña ${n}`); };
const minimosDash = (p) => p.evaluate(() => Math.min(...[...document.querySelectorAll(".dash-redes .dan-opcion, .dash-redes .tec-boton, .dash-redes .tec-boton-sec, .dash-redes .gest-check")].filter((e) => e.offsetParent).map((e) => e.getBoundingClientRect().height)));
const ficha = (email) => sqlq(`select coalesce(area, '∅') || '|' || coalesce(cargo, '∅') || '|' || coalesce(cuadrilla_id::text, '∅') || '|' || geovisor from redes.v_personal_ficha where persona = '${email}'`);
async function alDashboard(ancho, rol) {
  const p = await abrir(ancho, rol, null);
  await clicTexto(p, "button", "Dashboard distribución"); await esperarTexto(p, /Redes de acueducto y alcantarillado/);
  return p;
}
function datosDeLaVuelta(ancho) {
  const pd = JSON.parse(sqlq(`select public.geoportal_redes_preparar_dano('${EMAILS.op}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${pd.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const dano = JSON.parse(sqlq(`select public.geoportal_redes_crear_dano('${EMAILS.op}', '${pd.dano_id}', ${lit({ clase: "dano", tipo: "fuga", sistema: "acueducto", activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]),
    ubicacion_origen: "gps", t_detectado: iso(-300), tipo_rotura: "parcial", riesgo: "medio", causa_clase: "terceros", tercero_tipo: "vehiculo", tercero_nombre: `Placa ZQ${ancho}`,
    fotos: [{ n: 1, momento: "dano", ruta: pd.fotos[0].ruta }] })})`)).codigo;
  const pi = JSON.parse(sqlq(`select public.geoportal_redes_preparar_intervencion('${EMAILS.dist}', 1, 0)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${pi.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  const itv = JSON.parse(sqlq(`select public.geoportal_redes_crear_intervencion('${EMAILS.dist}', '${pi.intervencion_id}', ${lit({ nace_de: "dano", dano, resuelve_dano: true, tipo: "reparacion", sistema: "acueducto",
    activo: V85[0], lat: Number(V85[1]), lon: Number(V85[2]), ubicacion_origen: "gps", t_inicio: iso(-180), t_fin: iso(-120), descripcion: `Reparación de prueba ${ancho}`, ejecutor: "emdupar",
    fuentes: [{ aportante: "emdupar", valor: 350000 }], archivos: [{ n: 1, clase: "despues", ruta: pi.fotos[0].ruta }] })})`)).codigo;
  return { dano, itv };
}
const DESCARGAS = join(CAP, "descargas"); mkdirSync(DESCARGAS, { recursive: true });

// dato de la prueba: el operador sin formularios necesita «Reportar daño o falla» para abrir Técnica (es su primera pantalla); «Registrar intervención» no lo tiene
if (sqlq(`select tecnica.f_formulario_asignado('${EMAILS.sinform}', 'danos_fallas')`) !== "t") sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, motivo, autor) values ('${EMAILS.sinform}', 'asignar_formulario', 'danos_fallas', 'Dato de la prueba en Chrome', 'zt.admin@emdupar.gov.co')`);
const asignado = (f) => sqlq(`select tecnica.f_formulario_asignado('${EMAILS.sinform}', '${f}')`) === "t";
async function abrirIntervencion(p) {
  await clicTexto(p, ".tec-chip-form", "Registrar intervención");
  await p.waitForFunction(() => /1\. De dónde nace y tipo|No tiene permiso|no tiene asignado|Sin permiso/i.test(document.body.innerText), { timeout: 20000 });
  return texto(p);
}

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`, primera = ancho === 390;
  // ===== A. El operador sin el formulario =====
  if (primera) {
    const p0 = await abrir(ancho, "sinform", null); const t0 = await abrirIntervencion(p0);
    ok(`${tag} antes: el operador sin «Registrar intervención» no puede abrirla`, !/1\. De dónde nace y tipo/.test(t0) && !asignado("mantenimiento"), t0.slice(0, 300));
    await p0.close();
  }
  // ===== B. El supervisor de distribución asigna (390) o quita (1280) el formulario desde Personal =====
  let p = await alDashboard(ancho, "dist");
  await pestana(p, "Personal"); await esperarTexto(p, /zt\.oper\.sinform@emdupar\.gov\.co/);
  await enTarjeta(p, "zt.oper.sinform@emdupar.gov.co", "button", "Editar ficha"); await p.waitForSelector(".gest-editor");
  let t = await tarjeta(p, "zt.oper.sinform@emdupar.gov.co");
  ok(`${tag} el editor de la ficha trae los formularios de distribución con su casilla`, /Formularios de distribución/.test(t) && /Reportar daño o falla/.test(t) && /Registrar intervención/.test(t));
  await valorEn(p, "zt.oper.sinform@emdupar.gov.co", "input[data-formulario=mantenimiento]", primera);
  await valorEn(p, "zt.oper.sinform@emdupar.gov.co", "input[id^=mo-]", primera ? "Empieza a registrar intervenciones" : "Ya no hace intervenciones");
  await enTarjeta(p, "zt.oper.sinform@emdupar.gov.co", ".itv-guardar", "Guardar (1 cambio)"); await esperarTexto(p, /actualizada \(1 cambio\)/);
  ok(`${tag} ${primera ? "asignado" : "quitado"}: evento en la tabla de siempre, con el supervisor de distribución como autor`, asignado("mantenimiento") === primera
     && sqlq(`select autor from tecnica.personal_tecnico_eventos where persona = '${EMAILS.sinform}' and formulario = 'mantenimiento' order by id desc limit 1`) === EMAILS.dist);
  await p.waitForFunction((si) => { const s = [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes("zt.oper.sinform"))?.innerText ?? "";
    return !s.includes("Guardar (") && s.includes("Registrar intervención") === si; }, { timeout: 10000 }, primera);
  t = await p.evaluate(() => [...document.querySelectorAll(".itv-bandeja")].find((x) => x.innerText.includes("zt.oper.sinform"))?.innerText ?? "");
  ok(`${tag} la tarjeta muestra sus formularios al día`, primera ? /Registrar intervención/.test(t) : !/Registrar intervención/.test(t), t.slice(0, 300));
  t = await tarjeta(p, "zt.dist@emdupar.gov.co");
  ok(`${tag} su propia ficha (y sus formularios) no la edita`, /Su propia ficha la cambia otro supervisor/.test(t));
  ok(`${tag} Personal no desborda y los botones miden 44 px o más`, (await sinDesborde(p)) && (await minimosDash(p)) >= 44, String(await minimosDash(p)));
  await p.screenshot({ path: join(CAP, `personal_formularios_${ancho}.png`), fullPage: true });
  // cuadrillas: ahora también el supervisor de distribución (§28.5)
  await pestana(p, "Catálogo"); await esperarTexto(p, /Crear la cuadrilla/);
  ok(`${tag} el Catálogo le dice que puede crear y cambiar las cuadrillas (y no el nombre visible de los tipos)`, /Usted puede crear y cambiar las cuadrillas/.test(await texto(p)) && !(await clicTexto(p, "button", "Nombre visible")));
  await poner(p, "#cq-nueva", `ZT5 Cuadrilla ${ancho}`); await poner(p, "#cq-nueva-m", "La crea el supervisor de distribución");
  await clicTexto(p, "button", "Crear la cuadrilla"); await esperarTexto(p, new RegExp(`Cuadrilla «ZT5 Cuadrilla ${ancho}» creada`));
  ok(`${tag} el supervisor de distribución crea una cuadrilla`, sqlq(`select autor from redes.cuadrillas where nombre = 'ZT5 Cuadrilla ${ancho}'`) === EMAILS.dist);
  await p.screenshot({ path: join(CAP, `catalogo_cuadrillas_${ancho}.png`), fullPage: true });
  await p.close();
  // ===== C. El operador ahora sí (390) o ya no (1280) abre «Registrar intervención» =====
  p = await abrir(ancho, "sinform", null); t = await abrirIntervencion(p);
  ok(`${tag} el operador ${primera ? "ya abre" : "ya no abre"} «Registrar intervención»`, primera ? /1\. De dónde nace y tipo/.test(t) : !/1\. De dónde nace y tipo/.test(t), t.slice(0, 300));
  await p.close();
  // ===== D. La intervención del supervisor: con tope (§28.1) =====
  p = await abrir(ancho, "dist", null); t = await abrirIntervencion(p);
  ok(`${tag} la intervención del supervisor dice «hasta 30 días atrás» y «máximo 72 h», ya no «sin tope»`, /hasta 30 días atrás/.test(t) && /máximo 72 h/.test(t) && !/sin tope/.test(t),
     (t.match(/El inicio se toma[^\n]*/) || [""])[0]);
  ok(`${tag} la intervención no desborda`, await sinDesborde(p));
  await p.screenshot({ path: join(CAP, `intervencion_topes_${ancho}.png`), fullPage: false });
  await p.close();
}
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
