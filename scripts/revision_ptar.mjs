// PTAR-2 y PTAR-3 (Code C, 21-nov) · el inicio de Técnica con el modo «PTAR», el Sistema de Control PTAR (el mapa en su vista propia), el Dashboard PTAR y la
// Caracterización (formulario por punto), DE PUNTA A PUNTA EN LOCAL:
//   pantallas compiladas (AreaTecnica real) → las Edges REALES geoportal-tecnica (rama tecnica-ptar-cascaron) y geoportal-redes en Deno → PostgREST mínimo en Node que
//   llama las RPC REALES de la base local del Code C (clúster 55452, por psql_c) como service_role con 30 s y 8 s. Auth simulado (la sesión es la de ?rol=).
//   Plantilla: ptar_p3 = producción + PTAR-1 + el doble de captura de la Torre B (obtener_formulario, registrar_medicion y resumen_operador publicados) + PTAR-3 + la carga del mapa.
//   Dobles en Node SOLO para dos RPC de la Torre B que la base local no trae (geoportal_tec_mis_formularios, armada con el perfil REAL de tecnica.f_perfil, f_formularios y
//   lo asignado en personal_tecnico_eventos; y geoportal_tec_avisos vacío).
//   Personas simuladas (ZTPTAR): A administrador · T supervisor técnico (PTAP y PTAR; David, 21-nov) · J jefe de la PTAR (solo PTAR) · S supervisor de planta (solo PTAP)
//   · O operador con la Caracterización asignada · N sin Técnica. El mapa es la carga real (918 elementos). Puertos del Code C: 56001 (páginas), 56002 (Edges), 56003 (Auth y PostgREST).
// Uso:
//   node scripts/revision_ptar.mjs --servir <deno> <supabase/functions> <psql_c> <plantilla>               → deja todo corriendo para revisarlo en el navegador:
//        http://127.0.0.1:56001/?rol=T  (cambie la letra: A, T, J, S, O, N). Ctrl+C para terminar (la copia de la base se borra).
//   node scripts/revision_ptar.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_c> <plantilla> <carpeta de capturas>   → la prueba en Chrome (390 y 1280 px)
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/revision_ptar.mjs --servir <deno> <supabase/functions> <psql_c> <plantilla>\n     node scripts/revision_ptar.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_c> <plantilla> <capturas>";
const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) { console.log(USO); process.exit(0); }
const servir = args[0] === "--servir";
for (const a of args.slice(servir ? 1 : 0)) if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
if ((servir && args.length !== 5) || (!servir && args.length !== 7)) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA, CAP] = servir ? [null, null, ...args.slice(1)] : args;
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const P_WEB = 56001, P_EDGE = 56002, P_BASE = 56003;
const DB = `${PLANTILLA}_rev`;
const PGENV = { ...process.env, LC_ALL: "C", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 << 20 }).trim();
if (execFileSync(PSQL, ["-AtqX", "-d", "postgres", "-c", "show port"], { env: PGENV, encoding: "utf8" }).trim() !== "55452") { console.error("No es el clúster del Code C (55452)"); process.exit(2); }
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${DB}`, "-c", `create database ${DB} template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select count(*) from tecnica.elementos_planta where activo") === "0" || sqlq("select count(*) from tecnica.puntos where tipo = 'ptar'") !== "4") { console.error(`La plantilla ${PLANTILLA} no tiene PTAR-1, PTAR-3 y la carga del mapa`); process.exit(2); }
const N_MAPA = Number(sqlq("select count(*) from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = 'ptar' and e.activo"));

// ---------- 0. Personas simuladas ----------
const EMAILS = { A: "ztptar.admin@emdupar.gov.co", T: "ztptar.suptec@emdupar.gov.co", J: "ztptar.jefe@emdupar.gov.co", S: "ztptar.sp@emdupar.gov.co", O: "ztptar.op@emdupar.gov.co", N: "ztptar.nada@emdupar.gov.co" };
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZTPTAR Admin", []); lb(EMAILS.T, "ZTPTAR Supervisor técnico", ["ver_registro_tecnico", "ver_dashboard_tecnico"]); lb(EMAILS.J, "ZTPTAR Jefe de la PTAR", ["ver_registro_tecnico", "ver_dashboard_tecnico"]);
lb(EMAILS.S, "ZTPTAR Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]); lb(EMAILS.O, "ZTPTAR Operador", ["ver_registro_tecnico"]); lb(EMAILS.N, "ZTPTAR Sin Técnica", ["ver_explorar"]);
sqlq(`insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values
  ('${EMAILS.T}', 'ptar', 'asignar', 'ZTPTAR el supervisor técnico tiene también la PTAR (David, 21-nov)', '${EMAILS.A}'),
  ('${EMAILS.J}', 'ptar', 'asignar', 'ZTPTAR jefe de la PTAR', '${EMAILS.A}'), ('${EMAILS.J}', 'ptap', 'quitar', 'ZTPTAR el jefe de la PTAR no ve la PTAP', '${EMAILS.A}')`);
sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.O}', 'asignar_formulario', 'ptar_caracterizacion', '${EMAILS.A}')`);

// ---------- 1. Páginas: el AreaTecnica real con un doble del cliente de Supabase (la sesión es la de ?rol=, recordada) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_ptar_"));
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const q = new URLSearchParams(location.search).get("rol"); if (q !== null) localStorage.setItem("zt_rol", q);
    const rol = localStorage.getItem("zt_rol") || "";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: rol ? { access_token: "tok-" + rol } : null } }), refreshSession: async () => ({ data: { session: null }, error: rol ? null : { message: "x" } }),
      signOut: async () => ({}), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) }, storage: { from: () => ({}) } };` }));
} };
await build({ plugins: [doble], bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import { AreaTecnica } from "./src/tecnica/AreaTecnica.tsx";
    const rol = localStorage.getItem("zt_rol") || "";
    createRoot(document.getElementById("raiz")).render(<div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}><AreaTecnica uid={"u-" + rol} correo={${JSON.stringify(EMAILS)}[rol] ?? "sin sesión"} /></div>);
    setTimeout(() => { window.__listo = true; }, 400);` } });
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Técnica · PTAR (local)</title><link rel="stylesheet" href="paquete.css"><style>html,body{margin:0}</style></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);
const web = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x"); const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
  if (!/^(index\.html|paquete\.(js|css))$/.test(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html; charset=utf-8" }); res.end(readFileSync(join(dir, f)));
});
await new Promise((r) => web.listen(P_WEB, "127.0.0.1", r));

// ---------- 2. Auth y PostgREST simulados; las RPC van a la base REAL con el rol y los topes de producción ----------
const rpcs = [], dobles = new Set();
const existe = new Map();
const hayRpc = (fn) => { if (!existe.has(fn)) existe.set(fn, sqlq(`select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = ${lit(fn)}`) !== "0"); return existe.get(fn); };
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'",
      "-c", `select to_jsonb(public.${fn}(${args}))`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 256 << 20 }).trim();
    return { status: 200, cuerpo: t === "" ? null : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /(HINT|SUGERENCIA):\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
// Dobles de la Torre B (no están en la base local): el perfil sale de la función REAL tecnica.f_perfil; los supervisores y el administrador ven los formularios de planta
function dobleMisFormularios(a) {
  const perfil = sqlq(`select tecnica.f_perfil(${lit(a.p_solicitante)})`);
  if (!perfil) return { status: 400, cuerpo: { code: "42501", message: "Sin permiso para esta función" } };
  // supervisor y administrador: todos los formularios de f_formularios (con_campos si tienen variables); operador: los que tiene asignados (último evento)
  const forms = JSON.parse(sqlq(`select coalesce(json_agg(json_build_object('clave', f.clave, 'nombre', f.nombre, 'descripcion', f.descripcion,
      'con_campos', exists (select 1 from tecnica.formulario_variables fv where fv.formulario::text = f.clave and fv.activa)) order by f.orden), '[]') from tecnica.f_formularios() f
    where f.clave in ('entrada', 'salida', 'muestreo', 'ptar_caracterizacion') and (${lit(perfil)} <> 'operador' or (select e.tipo_evento = 'asignar_formulario' from tecnica.personal_tecnico_eventos e
      where e.persona = ${lit(a.p_solicitante)} and e.formulario::text = f.clave and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') order by e.id desc limit 1))`));
  return { status: 200, cuerpo: { perfil, formularios: forms } };
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(Buffer.concat(trozos).toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push(fn);
      if (fn === "geoportal_tec_mis_formularios" && !hayRpc(fn)) { dobles.add(fn); const r = dobleMisFormularios(a); return json(r.status, r.cuerpo); }
      if (fn === "geoportal_tec_avisos" && !hayRpc(fn)) { dobles.add(fn); return json(200, { areas: { planta: true, distribucion: false, personal: false }, admin: false, avisos: [], total: 0, rojos: 0, naranjas: 0, calculado_en: new Date().toISOString(), ms: 0 }); }
      if (!hayRpc(fn)) return json(404, { code: "PGRST202", message: "no existe" });
      const r = rpcBase(fn, a); return json(r.status, r.cuerpo);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Las Edges REALES en Deno (tecnica de esta rama; redes la publicada, para el perfil de redes) ----------
const servirTs = join(dir, "servir_edges.ts");
writeFileSync(servirTs, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servirTs], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
const terminar = (c) => { try { edge.kill(); } catch { /* */ } web.close(); srv.close(); try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${DB}`], { env: PGENV }); } catch { /* */ } process.exit(c); };
process.on("SIGINT", () => terminar(0));
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`las Edges terminaron (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("las Edges no arrancaron: " + edgeLog)), 90000); });

if (servir) {
  console.log(`LISTO. Abra en el navegador (cambie la letra del rol):\n  http://127.0.0.1:${P_WEB}/?rol=T   supervisor técnico (PTAP y PTAR): modo PTAR → Sistema de Control PTAR y Caracterización\n  http://127.0.0.1:${P_WEB}/?rol=J   jefe de la PTAR (solo PTAR)\n  http://127.0.0.1:${P_WEB}/?rol=S   supervisor de planta (solo PTAP)\n  http://127.0.0.1:${P_WEB}/?rol=A   administrador (Personal técnico: alcances)\n  http://127.0.0.1:${P_WEB}/?rol=O   operador con la Caracterización asignada · ?rol=N sin Técnica\nCtrl+C para terminar.`);
} else {
  // ---------- 4. Chrome ----------
  mkdirSync(CAP, { recursive: true });
  const puppeteer = createRequire(import.meta.url)(PUP);
  let total = 0, fallas = 0;
  const ok = (n, cond, d = "") => { total++; if (!cond) fallas++; console.log(`${cond ? "OK   " : "FALLA"} ${n}${cond ? "" : " → " + String(d).replace(/\n/g, " ").slice(0, 700)}`); };
  const esp = (ms) => new Promise((r) => setTimeout(r, ms));
  // los mosaicos de la foto satelital y de las calles NO se piden en la prueba (sin red externa): el fondo queda vacío y el resto se prueba igual
  const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
  const errores = [];
  async function pagina(rol, ancho, alto = ancho < 500 ? 844 : 900) {
    const pg = await nav.newPage();
    await pg.setViewport({ width: ancho, height: alto, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
    pg.on("pageerror", (e) => errores.push(`${rol}@${ancho}: ${e.message}`));
    await pg.evaluateOnNewDocument(() => { try { localStorage.removeItem("tec_modo"); } catch { /* */ } });
    await pg.goto(`http://127.0.0.1:${P_WEB}/?rol=${rol}`, { waitUntil: "networkidle0" });
    await pg.waitForFunction(() => !document.body.innerText.includes("Cargando Técnica"), { timeout: 20000 });
    return pg;
  }
  const texto = (pg) => pg.evaluate(() => document.body.innerText);
  const modos = (pg) => pg.$$eval(".tec-modos [role=tab]", (b) => b.map((x) => x.textContent.trim()));
  const clic = async (pg, sel) => { await pg.waitForSelector(sel, { timeout: 15000 }); await pg.$eval(sel, (b) => b.scrollIntoView({ block: "center" })); await pg.click(sel); };
  const capturar = (pg, n) => pg.screenshot({ path: join(CAP, `${n}.png`), fullPage: false });
  try {
    const hace3 = sqlq("select ((clock_timestamp() at time zone 'America/Bogota')::date - 3)::text");
    const esperarMapa = async (pg) => { await pg.waitForSelector("[data-testid=ptar-mapa]", { timeout: 30000 });
      await pg.waitForFunction(() => { const m = window.__mapaPtar; return m && m.loaded() && m.isStyleLoaded() && m.querySourceFeatures("ptar").length > 0; }, { timeout: 30000 }).catch(() => {}); await esp(600); };
    for (const ancho of [390, 1280]) {
      // ===== A. El inicio por modos =====
      let pg = await pagina("T", ancho);
      let m = await modos(pg);
      ok(`A1 (${ancho}) supervisor técnico: Plantas, Distribución, Supervisión y PTAR (el cuarto)`, m.join() === "Plantas,Distribución,Supervisión,PTAR", m);
      await clic(pg, "[data-modo=ptar]");
      const tarj = await pg.$$eval("[data-modo-actual=ptar] [data-tarjeta]", (t) => t.map((x) => `${x.getAttribute("data-tarjeta")}:${x.classList.contains("tec-tarjeta-pronto") ? "pronto" : "lista"}`));
      ok(`A2 (${ancho}) modo PTAR: Sistema de Control, Dashboard y Caracterización (abren); Afluente, Entre lagunas y Efluente en «Próximamente»`,
        tarj.join() === "control_ptar:lista,dashboard_ptar:lista,ptar_caracterizacion:lista,ptar_afluente:pronto,ptar_lagunas:pronto,ptar_efluente:pronto", tarj);
      await clic(pg, "[data-modo=planta]"); await pg.waitForSelector("[data-modo-actual=planta]", { timeout: 10000 });
      const plantas = await pg.$$eval("[data-modo-actual] [data-tarjeta]", (t) => t.map((x) => x.getAttribute("data-tarjeta")));
      ok(`A3 (${ancho}) la Caracterización NO sale en Plantas (es de la PTAR)`, !plantas.includes("ptar_caracterizacion") && plantas.includes("entrada"), plantas);
      await clic(pg, "[data-modo=ptar]");
      const col = await pg.$eval("[data-modo-actual=ptar] .tec-tarjeta-ini", (e) => getComputedStyle(e).backgroundColor);
      ok(`A4 (${ancho}) pizarra #3d4a5c en las tarjetas del modo`, col === "rgb(61, 74, 92)", col);
      await capturar(pg, `inicio_ptar_${ancho}`);
      // ===== B. El Sistema de Control PTAR (vista propia) =====
      await clic(pg, "[data-tarjeta=control_ptar]");
      await esperarMapa(pg);
      let t = await texto(pg);
      const cab = await pg.$eval(".ptar-control-cab", (e) => getComputedStyle(e).backgroundColor);
      ok(`B1 (${ancho}) Sistema de Control PTAR: vista propia con encabezado pizarra, «Volver al inicio» y los ${N_MAPA} elementos`, cab === "rgb(61, 74, 92)" && t.includes("Sistema de Control PTAR")
        && t.includes("Volver al inicio") && t.includes(`${new Intl.NumberFormat("es-CO").format(N_MAPA)} elementos`), t.slice(0, 400));
      ok(`B2 (${ancho}) el mapa cargó las piezas, con la foto satelital de fondo`, await pg.evaluate(() => window.__mapaPtar.querySourceFeatures("ptar").length > 800 && window.__mapaPtar.getSource("satelital").tiles[0].includes("World_Imagery")));
      const est = await pg.evaluate(() => window.__mapaPtar.querySourceFeatures("ptar", { filter: ["==", ["get", "tipo"], "punto_medicion"] }).map((f) => `${f.properties.punto}=${f.properties.estado}`).sort().filter((x, i, a) => a.indexOf(x) === i).join());
      ok(`B3 (${ancho}) los 4 puntos de medición en el mapa con su punto y estado`, est.split(",").length === 4 && est.includes("PTAR-RIO-ARR=") && est.includes("PTAR-EFL="), est);
      await capturar(pg, `control_ptar_${ancho}`);
      // ===== C. Clic en una laguna → su ficha =====
      const punto = await pg.evaluate(() => { const m = window.__mapaPtar; const f = m.querySourceFeatures("ptar", { filter: ["==", ["get", "codigo"], "PTAR-LAG-1"] })[0];
        const c = f.geometry.coordinates[0]; let x = 0, y = 0; for (const p of c) { x += p[0]; y += p[1]; } x /= c.length; y /= c.length; m.jumpTo({ center: [x, y], zoom: 18 }); return [x, y]; });
      await esp(900);
      const px = await pg.evaluate((p) => { const r = window.__mapaPtar.project(p); const b = window.__mapaPtar.getContainer().getBoundingClientRect(); return [b.left + r.x, b.top + r.y]; }, punto);
      await pg.mouse.click(px[0], px[1]);
      await pg.waitForSelector("[data-testid=ptar-ficha][data-codigo=PTAR-LAG-1]", { timeout: 15000 }).catch(() => {});
      t = await texto(pg);
      ok(`C1 (${ancho}) clic en la laguna anaerobia 1 → su ficha (tipo, etapa, tren, área) y «Sin variables asignadas»`, t.includes("1 · Anaerobia") && /Tren\s*\n?\s*norte/.test(t) && /ha \(/.test(t)
        && t.includes("Sin variables asignadas"), t.slice(0, 700));
      // ===== D. Alias con motivo =====
      await pg.evaluate(() => [...document.querySelectorAll("[data-testid=ptar-ficha] button")].find((b) => /alias/.test(b.textContent)).click());
      await pg.waitForSelector("#ptar-alias");
      await pg.$eval("#ptar-alias", (e) => { e.select(); }); await pg.keyboard.press("Backspace"); await pg.type("#ptar-alias", `A-N1 ${ancho}`);
      await pg.type("#ptar-motivo", "ZTPTAR nombre corto que usa la planta");
      await pg.evaluate(() => [...document.querySelectorAll(".ptar-alias button[type=submit]")][0].click());
      await pg.waitForSelector(".ptar-ok", { timeout: 15000 }).catch(() => {}); await pg.waitForSelector(".ptar-historial", { timeout: 15000 }).catch(() => {});
      t = await texto(pg);
      ok(`D1 (${ancho}) el alias se guarda con motivo e historial, y queda auditado`, t.includes(`Alias guardado: «A-N1 ${ancho}»`) && t.includes("Historial del alias")
        && sqlq(`select count(*) from tecnica.elemento_alias_eventos where codigo = 'PTAR-LAG-1' and alias = 'A-N1 ${ancho}'`) === "1", t.slice(0, 500));
      await capturar(pg, `ficha_laguna_${ancho}`);
      // ===== E. La ficha de un punto de medición: los parámetros =====
      await pg.$eval("#ptar-q", (e) => { e.value = ""; }); await pg.type("#ptar-q", "PTAR-PM-RIO-ARR"); await pg.keyboard.press("Enter");
      await pg.waitForSelector("[data-testid=ptar-ficha][data-codigo=PTAR-PM-RIO-ARR] [data-parametro=ar_ph]", { timeout: 15000 }).catch(() => {});
      const pars = await pg.$$eval("[data-testid=ptar-ficha] [data-parametro]", (l) => l.map((x) => `${x.getAttribute("data-parametro")}:${x.getAttribute("data-estado")}`));
      t = await texto(pg);
      // a 1280 ya tiene los valores que guardó la corrida de 390 (misma base): se mira la sonda y el orden; a 390, todo «sin registros»
      ok(`E1 (${ancho}) ficha del río aguas arriba: primero la sonda (pH, temperatura, OD, «sin registros») y luego la Caracterización`,
        pars.map((x) => x.split(":")[0]).join() === "ar_ph,ar_temperatura,ar_od,ar_caudal,ar_dbo5,ar_dqo,ar_sst,ar_nitrogeno_total,ar_fosforo_total"
        && pars.slice(0, 3).every((x) => x.endsWith(":sin_registros")) && (ancho !== 390 || pars.every((x) => x.endsWith(":sin_registros")))
        && /sonda multiparámetro/i.test(t) && /caracterización/i.test(t), pars);
      await capturar(pg, `ficha_punto_${ancho}`);
      // ===== F. Foto satelital / Calles y grupos =====
      const vis = async () => pg.evaluate(() => [window.__mapaPtar.getLayoutProperty("satelital", "visibility") ?? "visible", window.__mapaPtar.getLayoutProperty("calles", "visibility")]);
      await pg.evaluate(() => [...document.querySelectorAll(".ptar-fondo button")].find((b) => b.textContent === "Calles").click()); await esp(200);
      ok(`F1 (${ancho}) «Calles» cambia el fondo`, (await vis()).join() === "none,visible");
      await pg.evaluate(() => [...document.querySelectorAll(".ptar-capa input")][2].click()); await esp(200);
      ok(`F2 (${ancho}) apagar «Pozos y descargas» los quita del mapa`, await pg.evaluate(() => window.__mapaPtar.getLayoutProperty("ptar-pozo", "visibility") === "none"));
      // ===== G. Volver; el Dashboard PTAR y su acceso directo =====
      await pg.evaluate(() => [...document.querySelectorAll(".ptar-control-cab button")][0].click());
      await pg.waitForSelector("[data-tarjeta=dashboard_ptar]", { timeout: 15000 });
      await clic(pg, "[data-tarjeta=dashboard_ptar]");
      await pg.waitForSelector("[data-testid=ptar-acceso-control]", { timeout: 15000 });
      const tabs = await pg.$$eval(".tdash-tabs .tdash-tab", (x) => x.map((b) => `${b.childNodes[0].textContent.trim()}:${b.disabled ? "pronto" : "ok"}`));
      ok(`G1 (${ancho}) Dashboard PTAR: «Mapa» es el acceso directo; las demás en «Próximamente»`, tabs.join() === "Mapa:ok,Resumen:pronto,Registros:pronto,Eventos:pronto,Referencias:pronto,Personal técnico:pronto,Reportes:pronto", tabs);
      await capturar(pg, `dashboard_ptar_${ancho}`);
      await pg.evaluate(() => [...document.querySelectorAll("[data-testid=ptar-acceso-control] button")][0].click());
      await esperarMapa(pg); t = await texto(pg);
      ok(`G2 (${ancho}) el acceso abre el Sistema de Control, que vuelve al Dashboard`, t.includes("Sistema de Control PTAR") && t.includes("Volver al Dashboard PTAR"), t.slice(0, 300));
      await pg.close();

      // ===== H. La Caracterización desde el celular del operador: del formulario a la ficha =====
      pg = await pagina("O", ancho); m = await modos(pg);
      const tarjO = await pg.$$eval("[data-tarjeta]", (t) => t.map((x) => x.getAttribute("data-tarjeta")));
      ok(`H1 (${ancho}) operador con la Caracterización: la ve en PTAR, sin el Sistema de Control ni el Dashboard (no tiene el alcance)`, tarjO.join() === "ptar_caracterizacion" && !(m.includes("Plantas")), `${m} · ${tarjO}`);
      await clic(pg, "[data-tarjeta=ptar_caracterizacion]");
      await pg.waitForSelector('[id="tec-sel-punto:ptar"]', { timeout: 20000 });
      const opciones = await pg.$$eval('[id="tec-sel-punto:ptar"] option', (o) => o.map((x) => x.value).filter(Boolean));
      ok(`H2 (${ancho}) el formulario: lista de los 4 puntos de la PTAR y la fecha de la muestra (7 días)`, opciones.sort().join() === "PTAR-AFL,PTAR-EFL,PTAR-RIO-ABJ,PTAR-RIO-ARR" && !!(await pg.$("#tec-fecha[type=date]")), opciones);
      const pin = await pg.$eval(".tec-pagina", (e) => getComputedStyle(e).getPropertyValue("--t-modo").trim());
      ok(`H3 (${ancho}) el formulario va en pizarra (modo PTAR)`, pin === "#3d4a5c" || pin === "var(--t-ptar)" || pin.includes("3d4a5c"), pin);
      await pg.select('[id="tec-sel-punto:ptar"]', "PTAR-RIO-ARR");
      await pg.waitForSelector('[id="tec-c-ar_caudal@PTAR-RIO-ARR"]');
      // el borrador de la corrida anterior (mismo Chrome) puede traer texto: se vacía antes de escribir
      const escribir = async (sel, val) => { await pg.$eval(sel, (e) => { e.focus(); e.select(); }); await pg.keyboard.press("Backspace"); await pg.type(sel, val); };
      await escribir('[id="tec-c-ar_caudal@PTAR-RIO-ARR"]', `21${ancho === 390 ? "5" : "6"}0`);
      await escribir('[id="tec-c-ar_dbo5@PTAR-RIO-ARR"]', "4,5");
      await pg.evaluate((f) => { const e = document.getElementById("tec-fecha"); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; set.call(e, f); e.dispatchEvent(new Event("input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); }, hace3);
      await capturar(pg, `caracterizacion_form_${ancho}`);
      await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Guardar registro").click());
      await pg.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Confirmar y guardar"), { timeout: 15000 }).catch(() => {});
      t = await texto(pg); await capturar(pg, `caracterizacion_confirmar_${ancho}`);
      if (!t.includes("Confirmar y guardar")) throw new Error("no apareció la confirmación: " + t.slice(0, 900));
      ok(`H4 (${ancho}) la confirmación muestra la fecha del laboratorio (hace 3 días) y los dos valores`, /hace 3 días/.test(t) && t.includes("Río Cesar aguas arriba"), t.slice(0, 600));
      await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Confirmar y guardar").click());
      await pg.waitForFunction(() => document.body.innerText.includes("valores guardados"), { timeout: 20000 }).catch(() => {});
      t = await texto(pg);
      ok(`H5 (${ancho}) guardado: 2 valores, por el servidor real (registrar_medicion) con la fecha elegida`, t.includes("2 valores guardados")
        && sqlq(`select count(*) from tecnica.registros r join tecnica.puntos p on p.id = r.punto_id where p.codigo = 'PTAR-RIO-ARR' and r.autor = '${EMAILS.O}' and r.fecha_muestra = '${hace3}'`) === String(ancho === 390 ? 2 : 4), t.slice(0, 500));
      await capturar(pg, `caracterizacion_guardada_${ancho}`);
      await pg.close();
      // el supervisor técnico ve el valor en la ficha del Sistema de Control
      pg = await pagina("T", ancho); await clic(pg, "[data-modo=ptar]"); await clic(pg, "[data-tarjeta=control_ptar]"); await esperarMapa(pg);
      await pg.type("#ptar-q", "PTAR-PM-RIO-ARR"); await pg.keyboard.press("Enter");
      await pg.waitForSelector("[data-testid=ptar-ficha] [data-parametro=ar_caudal]", { timeout: 15000 }).catch(() => {});
      const cau = await pg.$eval("[data-testid=ptar-ficha] [data-parametro=ar_caudal]", (e) => `${e.getAttribute("data-estado")}|${e.innerText.replace(/\s+/g, " ")}`).catch(() => "");
      ok(`H6 (${ancho}) la ficha del río aguas arriba muestra el caudal recién guardado, con su fecha y «Sin referencia»`, cau.startsWith("sin_referencia|") && cau.includes(ancho === 390 ? "2.150" : "2.160") && cau.includes("Sin referencia"), cau);
      const estRio = await pg.evaluate(() => window.__mapaPtar.querySourceFeatures("ptar", { filter: ["==", ["get", "codigo"], "PTAR-PM-RIO-ARR"] })[0]?.properties.estado);
      ok(`H7 (${ancho}) …y en el mapa el punto queda «con datos»`, estRio === "con_datos", estRio);
      await capturar(pg, `ficha_punto_con_dato_${ancho}`);
      await pg.close();

      // ===== I. Quién ve qué (D6) =====
      pg = await pagina("J", ancho); m = await modos(pg); t = await texto(pg);
      ok(`I1 (${ancho}) jefe de la PTAR: el modo PTAR, sin Plantas ni el Dashboard PTAP`, (m.includes("PTAR") || (m.length === 0 && t.includes("Sistema de Control PTAR"))) && !m.includes("Plantas") && !t.includes("Dashboard PTAP"), `${m} · ${t.slice(0, 300)}`);
      await pg.close();
      pg = await pagina("S", ancho); m = await modos(pg); t = await texto(pg);
      ok(`I2 (${ancho}) supervisor de planta (solo PTAP): sin el modo PTAR ni la Caracterización`, !m.includes("PTAR") && !t.includes("Caracterización") && !t.includes("Sistema de Control"), m);
      await pg.close();
      pg = await pagina("A", ancho);
      await clic(pg, "[data-modo=ptar]"); await clic(pg, "[data-tarjeta=dashboard_ptar]");
      await pg.waitForSelector("[data-testid=ptar-acceso-control]", { timeout: 30000 });
      await pg.evaluate(() => [...document.querySelectorAll(".tdash-tab")].find((b) => b.textContent.startsWith("Personal técnico")).click());
      await pg.waitForSelector("[data-testid=ptar-alcances]", { timeout: 15000 }).catch(() => {});
      t = await texto(pg);
      ok(`I3 (${ancho}) administrador: «Personal técnico» abre los alcances`, t.includes("Alcance PTAP y PTAR") && t.includes(EMAILS.T) && t.includes(EMAILS.J), t.slice(0, 400));
      await pg.close();
    }
    ok("Z1 sin errores de JavaScript en ninguna página", errores.length === 0, errores.join(" | "));
    ok(`Z2 los únicos dobles fueron las dos RPC de la Torre B que la base local no trae (${[...dobles].join(", ") || "ninguno"})`, [...dobles].every((d) => ["geoportal_tec_mis_formularios", "geoportal_tec_avisos"].includes(d)));
    ok("Z3 ninguna llamada a una RPC que no exista (fuera de esos dos dobles)", rpcs.every((f) => hayRpc(f) || dobles.has(f)), [...new Set(rpcs.filter((f) => !hayRpc(f) && !dobles.has(f)))].join());
  } catch (e) { fallas++; total++; console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 800) + " · Edge: " + edgeLog.slice(-400)); }
  await nav.close();
  console.log(`Capturas en ${CAP}`);
  console.log(`RESULTADO: ${total - fallas} de ${total} — ${fallas === 0 ? "SIN FALLAS" : fallas + " FALLA(S)"}`);
  terminar(fallas === 0 ? 0 : 1);
}
