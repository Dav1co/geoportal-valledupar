// «Compartir vista» del mapa comercial (24-nov) · prueba en CHROME REAL de la APP COMPLETA (compilada con Vite) contra un servidor SIMULADO en 127.0.0.1
// (nada llega a Supabase; datos inventados). A 390 px y en escritorio:
//   usuario dual con enlace → mapa directo en el punto, con la marca temporal · solo Comercial → igual · solo Técnica o solo campo → su pantalla con el aviso cerrable ·
//   enlace pegado con la página abierta → el mapa vuela al punto (y desde la ventana de entrada lleva al mapa) · el enlace del geovisor de Técnica sigue igual ·
//   sin hash → todo como hoy (y sin marca) · la marca se quita sola a los 15 s y al tocarla; otro enlace la reemplaza.
//   node scripts/prueba_chrome_enlace_vista.mjs <chrome> <puppeteer-core> [carpeta_capturas]
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_enlace_vista.mjs <chrome> <puppeteer-core> [carpeta_capturas]";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, CAP_ARG] = args;
if (!CHROME || !PUP) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_enlace_vista")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const P_MOCK = 55988, P_WEB = 55989;      // puertos de Chrome del Code B
const MOCK = `http://127.0.0.1:${P_MOCK}`, ORIGEN = `http://127.0.0.1:${P_WEB}`;

// ---------- 1. La app compilada, apuntando al simulador ----------
const DIST = mkdtempSync(join(tmpdir(), "app_enlace_"));
const r = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: MOCK, VITE_SUPABASE_ANON_KEY: "clave-de-prueba", VITE_FUNCTIONS_URL: `${MOCK}/functions/v1` } });
if (r.status !== 0) { console.error("No compiló\n" + r.stdout + r.stderr); process.exit(2); }

// ---------- 2. Servidor simulado: Auth, perfil y lo mínimo de cada área ----------
const BASE_P = { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, campo: false, dashboard_campo: false, acta: false, dashboard_acta: false,
  analisis_contrato: false, registro_tecnico: false, dashboard_tecnico: false, aseo: false, dashboard_aseo: false, torre_a: false, torre_b: false, torre_c: false };
const USUARIOS = {
  "tok-dual": { email: "zt.dual@emdupar.gov.co", permisos: { ...BASE_P, explorar: true, comercial: true, registro_tecnico: true, torre_a: true, torre_b: true } },
  "tok-com": { email: "zt.comercial@emdupar.gov.co", permisos: { ...BASE_P, explorar: true, torre_a: true } },
  "tok-tec": { email: "zt.tecnica@emdupar.gov.co", permisos: { ...BASE_P, registro_tecnico: true, torre_b: true } },
  "tok-campo": { email: "zt.campo@emdupar.gov.co", permisos: { ...BASE_P, campo: true, torre_a: true } },
};
const CAB = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer", "access-control-allow-methods": "GET, POST, PUT, PATCH, OPTIONS" };
const DEF_CAMPO = { perfil: "reportante", puede: { reportar: true, crear_desde_escritorio: false, supervisar: false, administrar_catalogo: false },
  limites: { max_fotos: 2, min_fotos_campo: 1, max_bytes_foto: 1572864, tipo_mime: "image/jpeg", max_descripcion: 1000 }, zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
  grupos: [], estados: null, parametros: null, definiciones: [] };
const mock = http.createServer((q, res) => {
  const u = new URL(q.url, MOCK);
  const json = (o, s = 200) => { res.writeHead(s, { ...CAB, "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(o)); };
  if (q.method === "OPTIONS") { res.writeHead(204, CAB); return res.end(); }
  q.resume(); q.on("end", () => {
    const tok = (q.headers.authorization ?? "").replace(/^Bearer /, ""), yo = USUARIOS[tok] ?? USUARIOS["tok-dual"];
    if (u.pathname.startsWith("/auth/v1/user")) return json({ id: "u", email: yo.email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} });
    if (u.pathname.startsWith("/auth/v1/")) return json({});
    if (u.pathname.startsWith("/rest/v1/")) return json(u.pathname.includes("geoportal_estado_acceso") ? "ok" : null);
    if (u.pathname.includes("/geoportal-tiles/")) { res.writeHead(204, CAB); return res.end(); }
    const fn = u.pathname.split("/").at(-1), acc = u.searchParams.get("accion");
    if (fn === "geoportal-admin" && acc === "perfil") return json({ es_admin: false, permisos: yo.permisos });
    if (fn === "geoportal-barrios") return json({ barrios: [] });
    if (fn === "geoportal-causales") return json({ causales: [] });
    if (fn === "geoportal-campo" && acc === "formulario") return json(DEF_CAMPO);
    return json({ error: "no simulado" }, 404);            // Técnica y lo demás: su aviso de error, a propósito (aquí solo importa la pantalla)
  });
});
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json" };
const web = http.createServer((q, res) => {
  const rel = q.url.split("?")[0] === "/" ? "/index.html" : q.url.split("?")[0], f = join(DIST, rel);
  if (!f.startsWith(DIST) || !existsSync(f) || statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": MIME[extname(f)] || "application/octet-stream" }); res.end(readFileSync(f));
});
await new Promise((a) => mock.listen(P_MOCK, "127.0.0.1", a)); await new Promise((a) => web.listen(P_WEB, "127.0.0.1", a));

// ---------- 3. Recorrido ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + String(d).replace(/\s+/g, " ").slice(0, 500)}`); };
const esp = (ms) => new Promise((x) => setTimeout(x, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
let ANCHO = 390;
async function abrir(tok, hash = "") {
  const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage();
  await pg.setViewport({ width: ANCHO, height: ANCHO < 500 ? 844 : 900, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  pg.on("pageerror", (e) => errores.push(`${ANCHO} ${String(e).slice(0, 200)}`));
  await pg.evaluateOnNewDocument((t, correo) => {
    if (localStorage.getItem("sb-127-auth-token")) return;
    localStorage.setItem("sb-127-auth-token", JSON.stringify({ access_token: t, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: "u", email: correo, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} } }));
  }, tok, USUARIOS[tok].email);
  await pg.goto(`${ORIGEN}/${hash}`, { waitUntil: "domcontentloaded" });
  return { pg, ctx };
}
const texto = (pg) => pg.evaluate(() => document.body.innerText);
const esperar = async (pg, f, ms = 20000, ...a) => pg.waitForFunction(f, { timeout: ms, polling: 150 }, ...a).then(() => true).catch(() => false);
const vista = (pg) => pg.evaluate(() => (window).__geoVista?.() ?? null);
const cerca = (v, lng, lat, zoom) => !!v && Math.abs(v.lng - lng) < 1e-4 && Math.abs(v.lat - lat) < 1e-4 && Math.abs(v.zoom - zoom) < 0.05;
const nMarcas = (pg) => pg.evaluate(() => document.querySelectorAll("[data-marca-enlace]").length);
const mapaListo = (pg) => esperar(pg, () => !!document.querySelector(".maplibregl-canvas") && typeof window.__geoVista === "function" && !!window.__geoVista());
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const foto = (pg, n) => pg.screenshot({ path: join(CAP, `${n}_${ANCHO}.png`) });
const P1 = { lng: -73.2532, lat: 10.4631, zoom: 17.5 }, P2 = { lng: -73.2401, lat: 10.4755, zoom: 16 };
const h = (p, extra = "") => `#v=${p.lng.toFixed(6)},${p.lat.toFixed(6)},${p.zoom.toFixed(2)}${extra}`;
const AVISO = "Este enlace es del mapa Comercial y su usuario no tiene acceso a él.";

try {
  for (ANCHO of [390, 1280]) {
    // 1. Dual con enlace → mapa directo en el punto, con la marca
    let { pg, ctx } = await abrir("tok-dual", h(P1));
    ok(`${ANCHO} E01 dual con enlace: el mapa comercial abre directo, sin «¿A qué área desea entrar?»`, await mapaListo(pg) && !/¿A qué área desea entrar\?/.test(await texto(pg)), await texto(pg));
    ok(`${ANCHO} E02 en el punto del enlace (centro y zoom)`, cerca(await vista(pg), P1.lng, P1.lat, P1.zoom), JSON.stringify(await vista(pg)));
    ok(`${ANCHO} E03 con la marca temporal en el punto (una sola)`, await esperar(pg, () => document.querySelectorAll("[data-marca-enlace]").length === 1));
    ok(`${ANCHO} E04 modo Explorar y sin aviso`, await pg.evaluate(() => !document.querySelector("[data-aviso=enlace]")
      && [...document.querySelectorAll('.modo-opcion[aria-checked="true"]')].map((e) => e.getAttribute("data-modo")).every((m) => m === "explorar")
      && document.querySelectorAll('.modo-opcion[aria-checked="true"]').length > 0),
      await pg.evaluate(() => [...document.querySelectorAll(".modo-opcion")].map((e) => `${e.getAttribute("data-modo")}:${e.getAttribute("aria-checked")}`).join(",")));
    await foto(pg, "E03_dual_enlace");
    ok(`${ANCHO} E05 «Inicio» sigue llevando a la ventana de áreas`, await pg.evaluate(() => { const b = document.querySelector(".btn-inicio"); if (b) b.click(); return !!b; })
      && await esperar(pg, () => /¿A qué área desea entrar\?/.test(document.body.innerText)), await texto(pg));
    // 4. Enlace pegado con la página abierta, desde la ventana de entrada → lleva al mapa, en el punto nuevo, con base satelital
    await pg.evaluate((x) => { window.location.hash = x; }, h(P2, "&b=satelital&c=sin"));
    ok(`${ANCHO} E06 enlace pegado en la ventana de entrada: lleva al mapa comercial en el punto nuevo`, await mapaListo(pg)
      && await esperar(pg, (p) => { const v = window.__geoVista?.(); return !!v && Math.abs(v.lng - p.lng) < 1e-4 && Math.abs(v.lat - p.lat) < 1e-4; }, 20000, P2), JSON.stringify(await vista(pg)));
    ok(`${ANCHO} E07 aplica la base (Satélite) y el filtro del enlace, con la marca`, await esperar(pg, () => [...document.querySelectorAll("button.seg.seg-activo")].some((b) => /Satélite/.test(b.textContent)))
      && await nMarcas(pg) === 1, await texto(pg));
    // Con el mapa abierto, otro enlace: vuela al punto y reemplaza la marca
    await pg.evaluate((x) => { window.location.hash = x; }, h(P1));
    ok(`${ANCHO} E08 con el mapa abierto, otro enlace: el mapa vuela al punto`, await esperar(pg, (p) => { const v = window.__geoVista?.(); return !!v && Math.abs(v.lng - p.lng) < 1e-4 && Math.abs(v.lat - p.lat) < 1e-4 && Math.abs(v.zoom - p.zoom) < 0.05; }, 20000, P1),
      JSON.stringify(await vista(pg)));
    ok(`${ANCHO} E09 la marca se reemplaza (sigue habiendo una sola) y la base vuelve a Calles`, await nMarcas(pg) === 1
      && await esperar(pg, () => [...document.querySelectorAll("button.seg.seg-activo")].some((b) => /Calles/.test(b.textContent))));
    // La marca se quita al tocarla
    await pg.evaluate(() => document.querySelector("[data-marca-enlace]")?.click());
    ok(`${ANCHO} E10 tocar la marca la quita`, await esperar(pg, () => document.querySelectorAll("[data-marca-enlace]").length === 0, 3000));
    ok(`${ANCHO} E11 sin desborde horizontal en el mapa`, await sinDesborde(pg));
    await ctx.close();

    // 2. Solo Comercial con enlace → igual
    ({ pg, ctx } = await abrir("tok-com", h(P1)));
    ok(`${ANCHO} E12 solo Comercial con enlace: el mapa en el punto, con la marca`, await mapaListo(pg) && cerca(await vista(pg), P1.lng, P1.lat, P1.zoom) && await nMarcas(pg) === 1, JSON.stringify(await vista(pg)));
    await ctx.close();

    // 3. Solo Técnica o solo campo → su pantalla, con el aviso cerrable
    for (const [tok, nombre, re] of [["tok-tec", "solo Técnica", /Técnica|TÉCNICA|técnic/], ["tok-campo", "solo campo", /Formatos|Reportar|campo/]]) {
      ({ pg, ctx } = await abrir(tok, h(P1)));
      ok(`${ANCHO} E13 ${nombre} con enlace: su pantalla, sin mapa comercial, con el aviso`, await esperar(pg, (a) => document.body.innerText.includes(a), 20000, AVISO)
        && await pg.evaluate(() => !document.querySelector(".maplibregl-canvas") && !document.querySelector("[data-marca-enlace]")) && re.test(await texto(pg)), await texto(pg));
      ok(`${ANCHO} E14 ${nombre}: sin desborde con el aviso`, await sinDesborde(pg));
      await foto(pg, `E13_${tok}`);
      await pg.evaluate(() => document.querySelector(".aviso-enlace-cerrar")?.click());
      ok(`${ANCHO} E15 ${nombre}: el aviso se cierra`, await esperar(pg, () => !document.querySelector("[data-aviso=enlace]"), 3000));
      await pg.evaluate((x) => { window.location.hash = x; }, h(P2));
      ok(`${ANCHO} E16 ${nombre}: un enlace pegado con la página abierta vuelve a mostrar el aviso y no abre el mapa`, await esperar(pg, (a) => document.body.innerText.includes(a), 5000, AVISO)
        && await pg.evaluate(() => !document.querySelector(".maplibregl-canvas")));
      await ctx.close();
    }

    // 5. El enlace del geovisor de Técnica sigue igual (dual → Técnica, sin aviso)
    ({ pg, ctx } = await abrir("tok-dual", "#geovisor=abcdefghij"));
    ok(`${ANCHO} E17 el enlace del geovisor técnico sigue abriendo Técnica, sin aviso ni mapa comercial`, await esperar(pg, () => !/¿A qué área desea entrar\?/.test(document.body.innerText) && document.body.innerText.length > 30)
      && await esperar(pg, () => !document.querySelector(".maplibregl-canvas.mapa-comercial") && !document.querySelector("[data-aviso=enlace]"), 3000) && !/Este enlace es del mapa Comercial/.test(await texto(pg)), await texto(pg));
    await ctx.close();

    // 6. Sin hash → todo como hoy y sin marca
    ({ pg, ctx } = await abrir("tok-dual"));
    ok(`${ANCHO} E18 dual sin hash: la ventana de entrada, como hoy`, await esperar(pg, () => /¿A qué área desea entrar\?/.test(document.body.innerText)), await texto(pg));
    await ctx.close();
    ({ pg, ctx } = await abrir("tok-com"));
    ok(`${ANCHO} E19 solo Comercial sin hash: el mapa, sin marca ni aviso`, await mapaListo(pg) && (await esp(1500), await nMarcas(pg)) === 0 && await pg.evaluate(() => !document.querySelector("[data-aviso=enlace]")));
    await foto(pg, "E19_sin_hash");
    await ctx.close();
  }
  // La marca se quita sola a los 15 segundos (una vez, en escritorio)
  ANCHO = 1280;
  const { pg, ctx } = await abrir("tok-com", h(P1));
  await mapaListo(pg);
  const t0 = Date.now();
  ok("1280 E20 la marca aparece al abrir el enlace", await nMarcas(pg) === 1);
  await esp(12000);
  ok("1280 E21 a los 12 s la marca sigue", await nMarcas(pg) === 1);
  ok("1280 E22 antes de los 17 s la marca se quitó sola (15 s)", await esperar(pg, () => document.querySelectorAll("[data-marca-enlace]").length === 0, 5000), `pasaron ${(Date.now() - t0) / 1000} s`);
  await ctx.close();
  ok("Z1 sin errores de página", errores.length === 0, errores.join(" | "));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700)); }
await nav.close(); mock.close(); web.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas${fallas ? "" : " — SIN FALLAS"}  (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
