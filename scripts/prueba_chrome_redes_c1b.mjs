// Técnica · Fase 1 · Corte 1b · prueba en CHROME REAL (puppeteer-core + el Chrome instalado), de punta a punta y sin Supabase:
//   app compilada (componentes reales) → Edges REALES geoportal-tecnica y geoportal-redes (Deno, en 127.0.0.1) → PostgREST mínimo en Node
//   que llama a las RPC REALES de redes en el PostGIS local (base redes_local con la carga inicial completa de los shapefiles de origen).
// Ficha del activo a 390 px y en escritorio: búsqueda por código y por código de capa, cerca de mí (GPS simulado), tanque con componente,
// macromedidor, válvula (nodo), tramo (extremos y contratos), tramo SIVA (origen tercero), alias, pozo «Sin dato», código inexistente,
// y lo que ve cada perfil (supervisor, administrador, operador y sin Técnica).
//   node scripts/prueba_chrome_redes_c1b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions de geoportal-web> <psql> [capturas]
// Requiere: la base local con la carga publicada (sql/redes_corte1a del worktree tecnica-corte1a: rehacer_base.sh + carga + publicar).
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL] = process.argv.slice(2, 7);
const CAP = resolve(process.argv[7] || join(tmpdir(), "capturas_redes_c1b"));
if (!CHROME || !PUP || !DENO || !FUNCIONES || !PSQL) { console.error("Uso: node scripts/prueba_chrome_redes_c1b.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql> [capturas]"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 54993, P_EDGE = 54994;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: "redes_local" };
const sqlq = (s) => execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8" }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);

// ---------- 0. Datos de la base local (reales de la carga) ----------
const ADMIN = "carga.local@emdupar.gov.co";
const EMAILS = { adm: ADMIN, sup: "zt.super@emdupar.gov.co", op: "zt.oper@emdupar.gov.co", nada: "zt.nada@emdupar.gov.co" };
if (sqlq("select count(*) from redes.activo_vigente_mat") !== "35781") throw new Error("La base local no tiene la carga publicada (35.781 activos)");
// Un componente (el macromedidor MACRO 4 dentro de un tanque) y el alias de TOR, para ver la ficha completa. Solo en la base local.
sqlq(`insert into redes.activo_componentes (padre_id, hijo_id, accion, motivo, autor)
      select p.activo_id, h.activo_id, 'agregar', 'Prueba local de la ficha: macro a la salida del tanque', '${ADMIN}'
        from redes.activo_vigente_mat p, redes.activo_vigente_mat h where p.codigo = 'TAN-000001' and h.codigo_anterior = 'MACRO 4'
         and not exists (select 1 from redes.v_componentes_vigentes)`);
sqlq(`select public.geoportal_redes_alias_fijar('${ADMIN}', 'tipo', 'TOR', 'Hidrante', 'Prueba local: la torre se ve como hidrante')`);
const MAC = sqlq("select codigo from redes.activo_vigente_mat where codigo_anterior = 'MACRO 4'");
const V85 = sqlq("select codigo || '|' || st_y(geom) || '|' || st_x(geom) from redes.activo_vigente_mat where codigo_anterior = 'V85'").split("|");
const TRAMO = sqlq("select codigo from redes.activo_vigente_mat where codigo_anterior = 'Distribucion-8435'");
const SIVA = sqlq("select m.codigo from redes.activo_vigente_mat m join redes.v_activo_origen_vigente o using (activo_id) where o.aportante_codigo = 'siva' order by m.codigo limit 1");
const POZ0 = sqlq("select codigo from redes.v_activo_vigente where prefijo = 'POZ' and atributos ->> 'estado_pozo' = 'Sin dato' and estado_codigo = 'por_eliminar' order by codigo limit 1");
const TOR = sqlq("select codigo from redes.activo_vigente_mat where prefijo = 'TOR' order by codigo limit 1");

// ---------- 1. Paquete de la página ----------
const dir = mkdtempSync(join(tmpdir(), "ui_redes_c1b_"));
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
    createRoot(document.getElementById("raiz")).render(<AreaTecnica uid="u-prueba" correo="persona@emdupar.gov.co" />);
    setTimeout(() => { window.__listo = true; }, 300);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz" style="display:flex;min-height:100vh"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Auth + PostgREST mínimo: las RPC de redes van a la base local REAL ----------
const rpcs = [];
const PERFIL = { [EMAILS.adm]: "admin", [EMAILS.sup]: "supervisor", [EMAILS.op]: "operador" };
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
  try {
    const out = execFileSync(PSQL, ["-AtX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", `select public.${fn}(${args})`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    return { status: 200, cuerpo: JSON.parse(out.trim()) };
  } catch (e) {
    const t = String(e.stderr || "");
    const code = (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000";
    const message = ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim();
    const hint = ((t.match(/(?:HINT|SUGERENCIA):\s+(.*)/) || [])[1] || "").trim();
    return { status: 400, cuerpo: { code, message, hint: hint || undefined } };
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
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(cuerpo || "{}");
      if (fn === "geoportal_estado_acceso") return json(200, "ok");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push({ fn, args: a });
      if (fn === "geoportal_tec_mis_formularios") {
        const p = PERFIL[a.p_solicitante];
        return p ? json(200, { perfil: p, formularios: [{ clave: "danos_fallas", nombre: "Daño o falla", descripcion: "", con_campos: false }] }) : json(403, { code: "42501", message: "Sin permiso" });
      }
      if (fn.startsWith("geoportal_redes_")) { const r = rpcBase(fn, a); return json(r.status, r.cuerpo); }
      return json(404, { code: "PGRST202", message: "no existe" });
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Edges REALES en Deno (las dos en un proceso, por ruta) ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 30000); });

// ---------- 4. Directo a la Edge: lo que recibe cada perfil ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).slice(0, 400) }); };
const edgeGet = async (rol, qs) => { const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?${qs}`, { headers: { Authorization: `Bearer tok-${rol}` } }); return { estado: r.status, j: await r.json() }; };
let x = await edgeGet("op", `accion=activo&codigo=${SIVA}`);
ok("Edge · operador: recibe la ficha SIN origen ni modelo", x.estado === 200 && x.j.activo?.codigo === SIVA && !("origen" in x.j) && !("modelo" in x.j) && x.j.perfil === "operador", JSON.stringify(x.j).slice(0, 200));
x = await edgeGet("sup", `accion=activo&codigo=${SIVA}`);
ok("Edge · supervisor: recibe el origen (tercero, SIVA) y el modelo", x.estado === 200 && x.j.origen?.origen === "tercero" && x.j.origen?.aportante === "siva" && x.j.modelo);
x = await edgeGet("nada", `accion=activo&codigo=${SIVA}`);
ok("Edge · sin Técnica: 403 con el texto fijo", x.estado === 403 && x.j.error === "No tiene permiso para esta acción.", JSON.stringify(x));
x = await edgeGet("sup", "accion=activo&codigo=XYZ-000001");
ok("Edge · código inexistente: 404 con el texto de la base", x.estado === 404 && /No hay ningún activo/.test(x.j.error), JSON.stringify(x));
const todo = JSON.stringify((await edgeGet("adm", `accion=activo&codigo=${TRAMO}`)).j);
ok("Edge · la ficha de un tramo no trae números de contrato, nombres, teléfonos ni deuda (solo cuántos contratos)", !/cod_usuario|telefono|deuda|"contrato":/i.test(todo) && /contratos_enlazados/.test(todo), todo.slice(0, 300));

// ---------- 5. Chrome ----------
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO"] });
const errores = [];
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = (p, re, ms = 10000) => p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source);
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t)); if (!b) return false; b.click(); return true; }, sel, t);
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; set.call(el, valor); el.dispatchEvent(new Event("input", { bubbles: true })); return true; }, sel, valor);
const tamanoMin = (p, sel) => p.evaluate((sel) => Math.min(...[...document.querySelectorAll(sel)].map((e) => e.getBoundingClientRect().height)), sel);
async function abrir(ancho, rol) {
  const p = await nav.newPage(); await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  p.on("pageerror", (e) => errores.push(`${ancho} ${rol}: ${e.message}`));
  p.on("console", (m) => { if (m.type() === "error" && !/status of 40[34]/.test(m.text())) errores.push(`${ancho} ${rol} consola: ${m.text()}`); });
  await p.goto(`http://127.0.0.1:${P_BASE}/?rol=${rol}`); await p.waitForFunction(() => window.__listo === true);
  await esperarTexto(p, /Sesión de/); return p;
}
async function buscar(p, codigo) {
  await poner(p, "#red-codigo", codigo); await clicTexto(p, "button", "Abrir la ficha");
}
const fichaLista = async (p, cod) => {
  try { await esperarTexto(p, new RegExp(`${cod}[\\s\\S]*Datos del activo|No hay ningún activo|No tiene permiso`)); }
  catch (e) { await p.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }); throw new Error(`no abrió la ficha de ${cod}; pantalla: ${(await texto(p)).slice(0, 800)} · edge: ${edgeLog.slice(-600)}`); }
};
const volver = async (p) => { await p.evaluate(() => document.querySelector(".red-volver").click()); };

for (const ancho of [390, 1280]) {
  const tag = `[${ancho}]`;
  // ===== Operador: sin la entrada a la ficha en esta pantalla =====
  let p = await abrir(ancho, "op");
  ok(`${tag} operador: no ve «Ficha de activos» (llega a la ficha desde el minimapa, Corte 2)`, !/Ficha de activos/.test(await texto(p)));
  await p.close();

  // ===== Supervisor =====
  p = await abrir(ancho, "sup");
  ok(`${tag} supervisor: ve «Dashboard PTAP» y «Ficha de activos (redes)»`, /Dashboard PTAP/.test(await texto(p)) && /Ficha de activos \(redes\)/.test(await texto(p)));
  await clicTexto(p, "button", "Ficha de activos"); await esperarTexto(p, /Por código/);
  ok(`${tag} búsqueda: código y «Cerca de mí», sin desborde`, /Código del activo o de la capa/.test(await texto(p)) && /Buscar activos a 30 m de mí/.test(await texto(p)) && (await sinDesborde(p)));
  await p.screenshot({ path: join(CAP, `busqueda_${ancho}.png`), fullPage: true });

  // tanque con componente
  await buscar(p, "tan-000001"); await fichaLista(p, "TAN-000001");
  await p.waitForFunction(() => /Cambios del registro|Todavía no hay daños/.test(document.body.innerText), { timeout: 10000 });   // la epicrisis llega aparte de la ficha
  let t = await texto(p);
  ok(`${tag} tanque: cabecera (Acueducto · Almacenamiento, TAN-000001, tipo y estado) como la maqueta`, /ACUEDUCTO · ALMACENAMIENTO|Acueducto · Almacenamiento/i.test(t) && /TAN-000001/.test(t) && /Tanque de almacenamiento/.test(t) && /En operación/.test(t), t.slice(0, 300));
  ok(`${tag} tanque: «Datos del activo» con Capacidad «Sin dato», Fecha de instalación «Sin dato» y Barrio o sector «Sin dato»`, /Capacidad\s*Sin dato/.test(t) && /Fecha de instalación\s*Sin dato/.test(t) && /Barrio o sector\s*Sin dato/.test(t));
  ok(`${tag} tanque: Origen visible para el supervisor, con EMDUPAR marcado`, /Origen/.test(t) && (await p.evaluate(() => document.querySelector(".red-opcion-sel")?.textContent)) === "EMDUPAR");
  ok(`${tag} tanque: Componentes 1 con ${MAC}`, /Componentes\s*1/.test(t) && t.includes(MAC));
  ok(`${tag} tanque: epicrisis vacía con su aviso y «Cambios del registro (2)» (alta y componente agregado)`, /Todavía no hay daños, fallas, intervenciones ni cambios de la ficha/.test(t) && /Cambios del registro \(2\)/.test(t), t.slice(-600));
  ok(`${tag} tanque: sin desborde y filas de 44 px o más`, (await sinDesborde(p)) && (await tamanoMin(p, ".red-fila, .red-volver")) >= 44);
  await p.screenshot({ path: join(CAP, `ficha_tanque_${ancho}.png`), fullPage: true });
  await p.evaluate(() => { const d = document.querySelector(".red-registro"); if (d) d.open = true; });
  await esperarTexto(p, /Alta del activo \(carga/);
  t = await texto(p);
  ok(`${tag} cambios del registro: el alta, con fecha y autor (supervisor)`, /Alta del activo \(carga \d+\)/.test(t) && t.includes(ADMIN));

  // componente → macro → volver
  await clicTexto(p, ".red-fila", MAC); await fichaLista(p, MAC);
  t = await texto(p);
  ok(`${tag} macro: «Hace parte de» TAN-000001 y el punto MAC-04`, /Hace parte de/.test(t) && /TAN-000001/.test(t) && /Punto de macromedición\s*MAC-04/.test(t), t.slice(0, 500));
  ok(`${tag} volver dice «Volver a TAN-000001»`, /Volver a TAN-000001/.test(t));
  await volver(p); await fichaLista(p, "TAN-000001");
  ok(`${tag} volver regresa a la ficha del tanque`, /Tanque de almacenamiento/.test(await texto(p)));
  await volver(p); await esperarTexto(p, /Por código/);

  // válvula por código de la capa (nodo)
  await buscar(p, "V85"); await fichaLista(p, V85[0]);
  t = await texto(p);
  ok(`${tag} V85 (código de la capa): VAL, clase Cierre, efecto «Sin definir», nodo del modelo con sus tramos`, t.includes(V85[0]) && /Válvula · Cierre/.test(t) && /Efecto en la red\s*Sin definir/.test(t) && /Nodo del modelo\s*V85 · lleg/.test(t), t.slice(0, 600));
  ok(`${tag} V85: código anterior y estado en la cabecera`, /Código anterior: V85/.test(t));
  await volver(p); await esperarTexto(p, /Por código/);

  // tramo con extremos y contratos
  await buscar(p, "Distribucion-8435"); await fichaLista(p, TRAMO);
  t = await texto(p);
  ok(`${tag} tramo: Red de distribución con diámetro, longitud y material; «En la red» con desde y hasta (Tee-4685 → Tee-4947); contratos enlazados`,
     /Red de distribución/.test(t) && /Diámetro\s*203 mm/.test(t) && /Material\s*PVC/.test(t) && /desde Tee-4685/.test(t) && /hasta Tee-4947/.test(t) && /Contratos enlazados a este tramo \(por cercanía\)\s*\d/.test(t), t.slice(0, 900));
  ok(`${tag} tramo: datos del modelo hidráulico (plegados) para el supervisor`, /Datos del modelo hidráulico/.test(t));
  await p.screenshot({ path: join(CAP, `ficha_tramo_${ancho}.png`), fullPage: true });
  await clicTexto(p, ".red-fila", "ACC-"); await esperarTexto(p, /Accesorio/);
  ok(`${tag} desde el tramo se abre el extremo (Accesorio · Tee)`, /Accesorio · Tee/.test(await texto(p)));
  await volver(p); await fichaLista(p, TRAMO); await volver(p); await esperarTexto(p, /Por código/);

  // alias
  await buscar(p, TOR); await fichaLista(p, TOR);
  t = await texto(p);
  ok(`${tag} alias: ${TOR} se ve como «Hidrante» y dice el nombre del catálogo`, /Hidrante/.test(t) && /En el catálogo: Torre \(punto hidráulico de salida\) \(TOR\)/.test(t), t.slice(0, 400));
  await volver(p); await esperarTexto(p, /Por código/);

  // pozo con EST_POZO «0»
  await buscar(p, POZ0); await fichaLista(p, POZ0);
  t = await texto(p);
  ok(`${tag} pozo con EST_POZO «0»: «Estado del pozo: Sin dato», estado Por eliminar y aviso de punteado`, /Estado del pozo\s*Sin dato/.test(t) && /Por eliminar/.test(t) && /se dibuja punteado/.test(t), t.slice(0, 600));
  await p.screenshot({ path: join(CAP, `ficha_pozo_sin_dato_${ancho}.png`), fullPage: true });
  await volver(p); await esperarTexto(p, /Por código/);

  // inexistente
  await buscar(p, "XYZ-000001"); await esperarTexto(p, /No hay ningún activo/);
  ok(`${tag} código inexistente: mensaje claro y sin «Reintentar»`, /No hay ningún activo con el código «XYZ-000001»/.test(await texto(p)) && !(await clicTexto(p, "button", "Reintentar")));
  await volver(p); await esperarTexto(p, /Por código/);

  // cerca de mí (GPS simulado sobre la válvula V85)
  const ctx = nav.defaultBrowserContext(); await ctx.overridePermissions(`http://127.0.0.1:${P_BASE}`, ["geolocation"]);
  await p.setGeolocation({ latitude: Number(V85[1]), longitude: Number(V85[2]), accuracy: 5 });
  await clicTexto(p, ".tec-chip-form", "Acueducto");
  await clicTexto(p, "button", "Buscar activos a 30 m"); await esperarTexto(p, / m\n|\d+ m$/m);
  t = await texto(p);
  const filas = await p.evaluate(() => [...document.querySelectorAll('[aria-label="Activos cercanos"] .red-fila')].map((f) => f.innerText));
  ok(`${tag} cerca de mí: la válvula ${V85[0]} de primera (a 0 m; a igual distancia, los puntos antes que los tramos), y todos a 30 m o menos`, filas.length >= 2 && filas[0].includes(V85[0]) && /\b0 m/.test(filas[0])
     && filas.every((f) => { const m = f.match(/(\d+) m\s*$/); return m && Number(m[1]) <= 30; }), JSON.stringify(filas).slice(0, 400));
  const ult = [...rpcs].reverse().find((r) => r.fn === "geoportal_redes_activos_cerca");
  ok(`${tag} cerca de mí: la posición viajó en el cuerpo con sistema acueducto y radio 30`, ult && ult.args.p_sistema === "acueducto" && ult.args.p_radio_m === 30 && Math.abs(ult.args.p_lat - Number(V85[1])) < 1e-6, JSON.stringify(ult?.args));
  await p.screenshot({ path: join(CAP, `cerca_${ancho}.png`), fullPage: true });
  ok(`${tag} cerca de mí: sin desborde`, await sinDesborde(p));
  await clicTexto(p, ".red-fila", V85[0]); await fichaLista(p, V85[0]);
  ok(`${tag} desde la lista se abre la ficha`, /Válvula/.test(await texto(p)));
  await p.close();

  // ===== Administrador: tramo SIVA =====
  p = await abrir(ancho, "adm");
  await clicTexto(p, "button", "Ficha de activos"); await esperarTexto(p, /Por código/);
  await buscar(p, SIVA); await fichaLista(p, SIVA);
  t = await texto(p);
  ok(`${tag} administrador: tramo SIVA con origen «Tercero» marcado, «Entregado por» SIVA y sin soporte`, (await p.evaluate(() => document.querySelector(".red-opcion-sel")?.textContent)) === "Tercero"
     && /Entregado por\s*SIVA/.test(t) && /Sin soporte todavía/.test(t), t.slice(0, 700));
  await p.screenshot({ path: join(CAP, `ficha_siva_${ancho}.png`), fullPage: true });
  ok(`${tag} administrador: sin desborde`, await sinDesborde(p));
  await p.close();
}
ok("sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));

await nav.close(); edge.kill(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`\nRESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}\nCapturas: ${CAP}`);
process.exit(bien === resultados.length ? 0 : 1);
