// Prueba en CHROME REAL del mapa comercial: el contenedor (.mapa) y el lienzo (canvas) deben tener alto y ancho mayores que 0, aunque la hoja de estilos de MapLibre
// llegue DESPUÉS de app.css (carga diferida desde el Paso C). Lección del 13/11/2026: `.maplibregl-map { position: relative }` le ganaba a `.mapa { position: absolute; inset: 0 }`
// y el mapa comercial quedaba en blanco en producción (alto 0). Sin red externa: compila la app en una carpeta temporal y la sirve en local con Auth y perfil simulados.
// Nada llega a Supabase real.
// Uso:  PUPPETEER_DIR=<carpeta con node_modules/puppeteer-core> node scripts/prueba_mapa_chrome.mjs [--dist <carpeta ya compilada con VITE_SUPABASE_URL=http://127.0.0.1:54998>]
// Variables: CHROME (ruta de Chrome/Chromium; por omisión el de macOS o el que haya en el PATH), PUPPETEER_DIR (carpeta que contiene puppeteer-core; por omisión se busca en node_modules).
// Se ejecuta con `npm run prueba:mapa`. Sale con código distinto de 0 si algo falla.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const aqui = path.dirname(fileURLToPath(import.meta.url));
const raiz = path.join(aqui, "..");
const PUERTO_MOCK = 54998;
const MOCK = `http://127.0.0.1:${PUERTO_MOCK}`;

// ---------- piezas: Chrome y puppeteer-core ----------
function hallarChrome() {
  const cands = [process.env.CHROME, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"].filter(Boolean);
  return cands.find((c) => fs.existsSync(c));
}
function cargarPuppeteer() {
  const rutas = [process.env.PUPPETEER_DIR, raiz].filter(Boolean);
  for (const r of rutas) {
    for (const base of [r, path.join(r, "node_modules")]) {
      try { return createRequire(path.join(base, "x.js"))("puppeteer-core"); } catch { /* siguiente */ }
      try { return createRequire(path.join(r, "x.js"))(path.join(base, "puppeteer-core")); } catch { /* siguiente */ }
    }
  }
  return null;
}
const CHROME = hallarChrome();
const puppeteer = cargarPuppeteer();
if (!CHROME || !puppeteer) {
  console.error(`FALLA de entorno: ${!CHROME ? "no se encontró Chrome/Chromium (defina CHROME). " : ""}${!puppeteer ? "no se encontró puppeteer-core (defina PUPPETEER_DIR=<carpeta que lo contiene>)." : ""}`);
  process.exit(2);
}

// ---------- compilación local (apunta a un servidor simulado) ----------
let DIST;
const iDist = process.argv.indexOf("--dist");
if (iDist > 0) DIST = path.resolve(process.argv[iDist + 1]);
else {
  DIST = fs.mkdtempSync(path.join(os.tmpdir(), "mapa_chrome_"));
  const r = spawnSync(process.execPath, [path.join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir"], {
    cwd: raiz, encoding: "utf8",
    env: { ...process.env, VITE_SUPABASE_URL: MOCK, VITE_SUPABASE_ANON_KEY: "clave-de-prueba", VITE_FUNCTIONS_URL: `${MOCK}/functions/v1` },
  });
  if (r.status !== 0) { console.error("FALLA: no compiló\n" + (r.stdout || "") + (r.stderr || "")); process.exit(2); }
}

// ---------- servidores ----------
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json" };
const estatico = http.createServer((q, r) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0];
  const f = path.join(DIST, rel);
  if (!f.startsWith(DIST) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { "content-type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(fs.readFileSync(f));
});
const CAB = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version", "access-control-allow-methods": "GET, POST, OPTIONS" };
const TOK = "tok-mapa";
const usuario = { id: "u-mapa", email: "prueba.mapa@emdupar.gov.co", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, created_at: "2026-01-01T00:00:00Z" };
const mock = http.createServer((q, r) => {
  const u = new URL(q.url, MOCK);
  const json = (o, s = 200) => { r.writeHead(s, { ...CAB, "content-type": "application/json" }); r.end(JSON.stringify(o)); };
  if (q.method === "OPTIONS") { r.writeHead(204, CAB); return r.end(); }
  if (u.pathname.startsWith("/auth/v1/token")) return json({ access_token: TOK, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: usuario });
  if (u.pathname.startsWith("/auth/v1/user")) return json(usuario);
  if (u.pathname.endsWith("/geoportal-admin") && u.searchParams.get("accion") === "perfil")
    return json({ es_admin: false, permisos: { explorar: true, focalizacion: false, comercial: true, rutas: false, dashboard: false } });
  if (u.pathname.includes("/geoportal-tiles/")) { r.writeHead(204, CAB); return r.end(); }   // sin teselas: el lienzo igual se dibuja
  json({ error: "no simulado" }, 404);
});

// ---------- verificaciones ----------
let fallas = 0, total = 0;
const ok = (n, c, x) => { total++; if (!c) fallas++; console.log((c ? "OK    " : "FALLA ") + n + (c ? "" : "  -> " + String(typeof x === "string" ? x : JSON.stringify(x)).slice(0, 400))); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));

const medir = (p) => p.evaluate(() => {
  const caja = (e) => { if (!e) return null; const r = e.getBoundingClientRect(); return { w: Math.round(r.width), h: Math.round(r.height) }; };
  const mapa = document.querySelector(".mapa");
  const hojas = [...document.styleSheets].map((h, i) => {
    let tieneMapLibre = false, tieneApp = false;
    try { for (const r of h.cssRules) { const s = r.selectorText || ""; if (s.trim() === ".maplibregl-map") tieneMapLibre = true; if (/(^|,\s*)\.mapa(\s|,|$)/.test(s)) tieneApp = true; } } catch { /* hoja de otro origen */ }
    return { i, tieneMapLibre, tieneApp };
  });
  return {
    contenedor: caja(mapa), lienzo: caja(mapa && mapa.querySelector("canvas")),
    posicion: mapa ? getComputedStyle(mapa).position : null,
    clases: mapa ? mapa.className : null,
    ordenHojas: { app: hojas.find((h) => h.tieneApp)?.i ?? null, maplibre: hojas.find((h) => h.tieneMapLibre)?.i ?? null },
  };
});

await new Promise((r) => estatico.listen(0, "127.0.0.1", r));
await new Promise((r) => mock.listen(PUERTO_MOCK, "127.0.0.1", r));
const URL_APP = `http://127.0.0.1:${estatico.address().port}/`;
let br;
try {
  br = await puppeteer.launch({ headless: true, executablePath: CHROME, args: ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
  for (const [nombre, vp] of [["escritorio 1280x800", { width: 1280, height: 800 }], ["celular 390x800", { width: 390, height: 800, isMobile: true, hasTouch: true }]]) {
    const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ ...vp, deviceScaleFactor: 1 });
    const errs = []; p.on("pageerror", (e) => errs.push(String(e).slice(0, 200)));
    await p.evaluateOnNewDocument((t) => {
      if (localStorage.getItem("sb-127-auth-token")) return;
      localStorage.setItem("sb-127-auth-token", JSON.stringify({ access_token: t, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u-mapa", email: "prueba.mapa@emdupar.gov.co", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} } }));
    }, TOK);
    await p.goto(URL_APP, { waitUntil: "domcontentloaded" });
    let hallado = false;
    try { await p.waitForSelector(".mapa .maplibregl-canvas", { timeout: 25000 }); hallado = true; } catch { /* se reporta abajo */ }
    ok(`[${nombre}] aparece el mapa comercial (contenedor .mapa con lienzo de MapLibre)`, hallado, errs.join(" | ") || "no apareció");
    if (!hallado) { await ctx.close(); continue; }
    await esp(800);   // deja llegar la hoja diferida y el primer ajuste de tamaño

    // 1) Tal como carga la app (la hoja de MapLibre llega diferida)
    let m = await medir(p);
    ok(`[${nombre}] la hoja de MapLibre llega DESPUÉS de app.css (el caso que falló el 13/11)`, m.ordenHojas.app !== null && m.ordenHojas.maplibre !== null && m.ordenHojas.maplibre > m.ordenHojas.app, m.ordenHojas);
    ok(`[${nombre}] el contenedor del mapa tiene alto > 0 y ancho > 0`, m.contenedor && m.contenedor.h > 0 && m.contenedor.w > 0, m.contenedor);
    ok(`[${nombre}] el lienzo del mapa tiene alto > 0 y ancho > 0`, m.lienzo && m.lienzo.h > 0 && m.lienzo.w > 0, m.lienzo);
    ok(`[${nombre}] el contenedor sigue absoluto (no lo pisa .maplibregl-map)`, m.posicion === "absolute", { posicion: m.posicion, clases: m.clases });

    // 2) Peor orden posible: la hoja de MapLibre se vuelve a poner AL FINAL del <head>
    await p.evaluate(() => {
      const h = [...document.styleSheets].find((s) => { try { return [...s.cssRules].some((r) => (r.selectorText || "").trim() === ".maplibregl-map"); } catch { return false; } });
      const nodo = h && h.ownerNode; if (nodo) document.head.appendChild(nodo);
    });
    await esp(400);
    m = await medir(p);
    ok(`[${nombre}] con la hoja de MapLibre forzada al final del head, el contenedor conserva alto > 0`, m.contenedor && m.contenedor.h > 0 && m.contenedor.w > 0 && m.posicion === "absolute", { contenedor: m.contenedor, posicion: m.posicion });
    ok(`[${nombre}] con la hoja de MapLibre forzada al final del head, el lienzo conserva alto > 0`, m.lienzo && m.lienzo.h > 0 && m.lienzo.w > 0, m.lienzo);
    await ctx.close();
  }
} catch (e) {
  ok("la prueba corrió sin excepciones", false, String(e && e.stack || e));
} finally {
  if (br) await br.close().catch(() => {});
  estatico.close(); mock.close();
  if (iDist < 0) fs.rmSync(DIST, { recursive: true, force: true });
}
console.log(`\nRESULTADO: ${total - fallas} de ${total} verificaciones correctas`);
process.exit(fallas ? 1 : 0);
