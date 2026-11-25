// Técnica · el operador de planta no veía sus formularios (24-nov) · prueba en CHROME REAL de la APP COMPLETA (compilada con Vite) contra un servidor SIMULADO en 127.0.0.1
// (nada llega a Supabase; datos inventados). El simulador responde como el servidor real: geoportal_tec_ptar_perfil devuelve ptap:false a todo el que no es supervisor ni
// administrador, y mis_formularios trae lo asignado. A 390 y 1280 px comprueba qué tarjetas salen en cada modo:
//   operador (ptap:false, ptar:false) con entrada y salida → las dos en Plantas · operador con danos_fallas → en Distribución · operador con ptar_caracterizacion → en PTAR ·
//   supervisor con solo PTAR (D6) → no ve los de la PTAP ni el Dashboard PTAP · supervisor y administrador con PTAP → como siempre.
//   node scripts/prueba_chrome_operador_formularios.mjs <chrome> <puppeteer-core> [carpeta_capturas]
//   -h | --help  este uso. Cualquier otra opción que empiece con «-» es un error.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_operador_formularios.mjs <chrome> <puppeteer-core> [carpeta_capturas]";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, CAP_ARG] = args;
if (!CHROME || !PUP) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_operador_formularios")); mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const P_MOCK = 55988, P_WEB = 55989;      // puertos de Chrome del Code B
const MOCK = `http://127.0.0.1:${P_MOCK}`, ORIGEN = `http://127.0.0.1:${P_WEB}`;

// ---------- 1. La app compilada, apuntando al simulador ----------
const DIST = mkdtempSync(join(tmpdir(), "app_tec_op_"));
const r = spawnSync(process.execPath, [join(raiz, "node_modules", "vite", "bin", "vite.js"), "build", "--outDir", DIST, "--emptyOutDir", "--logLevel", "error"], {
  cwd: raiz, encoding: "utf8", env: { ...process.env, VITE_SUPABASE_URL: MOCK, VITE_SUPABASE_ANON_KEY: "clave-de-prueba", VITE_FUNCTIONS_URL: `${MOCK}/functions/v1` } });
if (r.status !== 0) { console.error("No compiló\n" + r.stdout + r.stderr); process.exit(2); }

// ---------- 2. Servidor simulado ----------
const NOMBRES = { entrada: "Entrada", salida: "Salida", muestreo: "Muestreo", danos_fallas: "Daños o fallas", ptar_caracterizacion: "Caracterización" };
const forms = (...claves) => claves.map((c) => ({ clave: c, nombre: NOMBRES[c] ?? c, descripcion: "", con_campos: true }));
const PERM_TEC = { explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, campo: false, dashboard_campo: false, acta: false, dashboard_acta: false,
  analisis_contrato: false, registro_tecnico: true, dashboard_tecnico: false, aseo: false, dashboard_aseo: false, torre_a: false, torre_b: true, torre_c: false };
// Cada persona: lo que entrega mis_formularios y lo que devuelve ptar_perfil (D6: ptap/ptar solo valen para supervisor y administrador; el operador siempre ptap:false, ptar:false)
const PERSONAS = {
  "tok-op-planta": { email: "zt.op.planta@emdupar.gov.co", admin: false, mis: { perfil: "operador", formularios: forms("entrada", "salida") }, ptar: { perfil: "operador", activa: true, admin: false, ptap: false, ptar: false, instalaciones: [] } },
  "tok-op-redes": { email: "zt.op.redes@emdupar.gov.co", admin: false, mis: { perfil: "operador", formularios: forms("danos_fallas") }, ptar: { perfil: "operador", activa: true, admin: false, ptap: false, ptar: false, instalaciones: [] } },
  "tok-op-ptar": { email: "zt.op.ptar@emdupar.gov.co", admin: false, mis: { perfil: "operador", formularios: forms("ptar_caracterizacion") }, ptar: { perfil: "operador", activa: true, admin: false, ptap: false, ptar: false, instalaciones: [] } },
  "tok-op-todo": { email: "zt.op.todo@emdupar.gov.co", admin: false, mis: { perfil: "operador", formularios: forms("entrada", "salida", "danos_fallas", "ptar_caracterizacion") }, ptar: { perfil: "operador", activa: true, admin: false, ptap: false, ptar: false, instalaciones: [] } },
  "tok-sup-ptar": { email: "zt.sup.ptar@emdupar.gov.co", admin: false, mis: { perfil: "supervisor", formularios: forms("entrada", "salida", "ptar_caracterizacion") }, ptar: { perfil: "supervisor", activa: true, admin: false, ptap: false, ptar: true, instalaciones: [] } },
  "tok-sup-ptap": { email: "zt.sup.ptap@emdupar.gov.co", admin: false, mis: { perfil: "supervisor", formularios: forms("entrada", "salida") }, ptar: { perfil: "supervisor", activa: true, admin: false, ptap: true, ptar: false, instalaciones: [] } },
  "tok-adm": { email: "zt.admin@emdupar.gov.co", admin: true, mis: { perfil: "admin", formularios: forms("entrada", "salida", "danos_fallas", "ptar_caracterizacion") }, ptar: { perfil: "admin", activa: true, admin: true, ptap: true, ptar: true, instalaciones: [] } },
};
const CAB = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, apikey, x-client-info, x-supabase-api-version, prefer", "access-control-allow-methods": "GET, POST, PUT, PATCH, OPTIONS" };
const mock = http.createServer((q, res) => {
  const u = new URL(q.url, MOCK);
  const json = (o, s = 200) => { res.writeHead(s, { ...CAB, "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(o)); };
  if (q.method === "OPTIONS") { res.writeHead(204, CAB); return res.end(); }
  q.resume(); q.on("end", () => {
    const tok = (q.headers.authorization ?? "").replace(/^Bearer /, ""), yo = PERSONAS[tok] ?? PERSONAS["tok-op-planta"];
    if (u.pathname.startsWith("/auth/v1/user")) return json({ id: "u", email: yo.email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} });
    if (u.pathname.startsWith("/auth/v1/")) return json({});
    if (u.pathname.startsWith("/rest/v1/")) return json(u.pathname.includes("geoportal_estado_acceso") ? "ok" : null);
    const fn = u.pathname.split("/").at(-1), acc = u.searchParams.get("accion");
    if (fn === "geoportal-admin" && acc === "perfil") return json({ es_admin: yo.admin, permisos: PERM_TEC });
    if (fn === "geoportal-tecnica") {
      if (acc === "mis_formularios") return json(yo.mis);
      if (acc === "ptar_perfil") return json(yo.ptar);
      return json({ error: "no simulado" }, 404);
    }
    if (fn === "geoportal-redes" && acc === "mi_perfil") return json({ perfil: "operador", email: yo.email, dashboard_redes: false });
    return json({ error: "no simulado" }, 404);
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
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const errores = [];
let ANCHO = 390;
async function abrir(tok) {
  const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage();
  await pg.setViewport({ width: ANCHO, height: ANCHO < 500 ? 844 : 900, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  pg.on("pageerror", (e) => errores.push(`${ANCHO} ${String(e).slice(0, 200)}`));
  await pg.evaluateOnNewDocument((t, correo) => {
    if (localStorage.getItem("sb-127-auth-token")) return;
    localStorage.setItem("sb-127-auth-token", JSON.stringify({ access_token: t, refresh_token: "r", token_type: "bearer", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: "u", email: correo, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} } }));
  }, tok, PERSONAS[tok].email);
  await pg.goto(ORIGEN, { waitUntil: "domcontentloaded" });
  // el administrador tiene todas las áreas: cae en la ventana de entrada y elige Técnica
  if (PERSONAS[tok].admin) { await pg.waitForSelector(".area-tarjeta-tecnica", { timeout: 25000 }); await pg.click(".area-tarjeta-tecnica"); }
  // espera a que Técnica termine de cargar (inicio con tarjetas o el aviso de «sin formularios») y a que lleguen ptar_perfil y mi_perfil de redes
  await pg.waitForFunction(() => !!document.querySelector("[data-tarjeta]") || /Todavía no tiene formularios asignados/.test(document.body.innerText), { timeout: 25000, polling: 150 }).catch(() => {});
  await esp(900);
  return { pg, ctx };
}
const modos = (pg) => pg.evaluate(() => [...document.querySelectorAll(".tec-modo[data-modo]")].map((b) => b.getAttribute("data-modo")));
const tarjetas = (pg) => pg.evaluate(() => [...document.querySelectorAll("[data-tarjeta]")].map((e) => e.getAttribute("data-tarjeta")));
/** Las tarjetas de un modo: si hay varios modos, entra a la pestaña; si es uno solo, es el que se ve. Devuelve null si el modo no existe. */
async function deModo(pg, modo) {
  const hay = await modos(pg);
  if (hay.length > 1) { if (!hay.includes(modo)) return null; await pg.evaluate((m) => document.querySelector(`.tec-modo[data-modo="${m}"]`).click(), modo); await esp(250); return tarjetas(pg); }
  const unico = await pg.evaluate(() => document.querySelector("[data-modo-actual]")?.getAttribute("data-modo-actual") ?? null);
  return unico === modo ? tarjetas(pg) : null;
}
const vacio = (pg) => pg.evaluate(() => /Todavía no tiene formularios asignados/.test(document.body.innerText));
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const foto = (pg, n) => pg.screenshot({ path: join(CAP, `${n}_${ANCHO}.png`), fullPage: true });
const iguales = (a, b) => JSON.stringify([...(a ?? [])].sort()) === JSON.stringify([...b].sort());

try {
  for (ANCHO of [390, 1280]) {
    let { pg, ctx } = await abrir("tok-op-planta");
    ok(`${ANCHO} O01 operador (ptap:false, ptar:false) con entrada y salida: NO sale «Todavía no tiene formularios asignados»`, !(await vacio(pg)), await pg.evaluate(() => document.body.innerText));
    ok(`${ANCHO} O02 salen las dos tarjetas en Plantas: entrada y salida`, iguales(await deModo(pg, "planta"), ["entrada", "salida"]), JSON.stringify(await tarjetas(pg)));
    ok(`${ANCHO} O03 sin desborde horizontal`, await sinDesborde(pg)); await foto(pg, "O02_operador_planta");
    await ctx.close();

    ({ pg, ctx } = await abrir("tok-op-redes"));
    ok(`${ANCHO} O04 operador con danos_fallas: sale en Distribución (y no en Plantas)`, iguales(await deModo(pg, "redes"), ["danos_fallas"]) && !(await vacio(pg)) && (await modos(pg)).every((m) => m !== "planta"), JSON.stringify([await modos(pg), await tarjetas(pg)]));
    await ctx.close();

    ({ pg, ctx } = await abrir("tok-op-ptar"));
    ok(`${ANCHO} O05 operador con ptar_caracterizacion: sale en PTAR`, iguales(await deModo(pg, "ptar"), ["ptar_caracterizacion"]) && !(await vacio(pg)), JSON.stringify([await modos(pg), await tarjetas(pg)]));
    await foto(pg, "O05_operador_ptar");
    await ctx.close();

    ({ pg, ctx } = await abrir("tok-op-todo"));
    const m = await modos(pg);
    ok(`${ANCHO} O06 operador con los cuatro: Plantas con entrada y salida, Distribución con danos_fallas y PTAR con la Caracterización`,
      iguales(m, ["planta", "redes", "ptar"]) && iguales(await deModo(pg, "planta"), ["entrada", "salida"]) && iguales(await deModo(pg, "redes"), ["danos_fallas"]) && iguales(await deModo(pg, "ptar"), ["ptar_caracterizacion"]), JSON.stringify(m));
    await ctx.close();

    // D6: supervisor con solo el alcance PTAR no ve los formularios ni el Dashboard de la PTAP
    ({ pg, ctx } = await abrir("tok-sup-ptar"));
    const mp = await modos(pg);
    ok(`${ANCHO} S01 supervisor con solo PTAR (D6): no tiene el modo Plantas ni ve entrada o salida`, !mp.includes("planta") && !(await tarjetas(pg)).some((t) => t === "entrada" || t === "salida"), JSON.stringify([mp, await tarjetas(pg)]));
    const supTarj = await deModo(pg, "supervision"), ptarTarj = await deModo(pg, "ptar");
    ok(`${ANCHO} S02 …ni el Dashboard PTAP; sí ve la PTAR (Dashboard, Sistema de Control y la Caracterización)`, !(supTarj ?? []).includes("dashboard_ptap")
      && ["dashboard_ptar", "control_ptar", "ptar_caracterizacion"].every((t) => (ptarTarj ?? []).includes(t)), JSON.stringify([supTarj, ptarTarj]));
    await foto(pg, "S01_supervisor_solo_ptar");
    await ctx.close();

    // El supervisor con PTAP y el administrador siguen como siempre
    ({ pg, ctx } = await abrir("tok-sup-ptap"));
    ok(`${ANCHO} S03 supervisor con PTAP: ve entrada y salida en Plantas y el Dashboard PTAP en Supervisión`, iguales((await deModo(pg, "planta"))?.filter((t) => t === "entrada" || t === "salida"), ["entrada", "salida"])
      && (await deModo(pg, "supervision"))?.includes("dashboard_ptap") === true, JSON.stringify(await modos(pg)));
    await ctx.close();
    ({ pg, ctx } = await abrir("tok-adm"));
    ok(`${ANCHO} S04 administrador: Plantas con entrada y salida, Distribución con danos_fallas, PTAR y Dashboard PTAP`, (await deModo(pg, "planta"))?.includes("entrada") === true && (await deModo(pg, "redes"))?.includes("danos_fallas") === true
      && (await deModo(pg, "ptar"))?.includes("ptar_caracterizacion") === true && (await deModo(pg, "supervision"))?.includes("dashboard_ptap") === true, JSON.stringify(await modos(pg)));
    await ctx.close();
  }
  ok("Z1 sin errores de página", errores.length === 0, errores.join(" | "));
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 700)); }
await nav.close(); mock.close(); web.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas${fallas ? "" : " — SIN FALLAS"}  (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
