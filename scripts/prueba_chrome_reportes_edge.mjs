// Reportes del Dashboard PTAP y Descargas del Dashboard distribución (20-nov-2026) · prueba en CHROME REAL de punta a punta CON LAS EDGES REALES DEL CODE A:
//   pantallas compiladas → geoportal-tecnica y geoportal-redes (rama tecnica-reportes-ptap-dist del Code A, en Deno) → PostgREST mínimo en Node que llama a las
//   RPC REALES de la base local del Code B (clúster 55442: producción al 20-nov + los dos paquetes del Code A), como service_role con 30 s y 8 s.
//   Auth y Storage simulados (Storage solo firma y sirve una imagen de prueba). Datos SIMULADOS con prefijo ZT; los activos son los reales.
// Comprueba lo que el simulador no puede: que las listas de los filtros que da cada dashboard las acepta el servidor real, que cada archivo trae las columnas
// y las filas que manda el servidor, la auditoría en las tablas reales (iniciar y cerrar), el vínculo «Ver foto» hasta la foto firmada y quién entra.
//   node scripts/prueba_chrome_reportes_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions del Code A> <psql_b> <base plantilla> [capturas]
//   (la base plantilla tiene los dos paquetes; se copia a <plantilla>_ch y la prueba escribe solo en la copia)
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 8);
const CAP = resolve(process.argv[8] || join(tmpdir(), "capturas_reportes_edge"));
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_chrome_reportes_edge.mjs <chrome> <puppeteer-core> <deno> <supabase/functions> <psql_b> <base plantilla> [capturas]"); process.exit(2); }
if (process.env.PGPORT !== "55442") { console.error("Esta prueba es del Code B: PGPORT=55442"); process.exit(2); }
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const P_BASE = 55990, P_EDGE = 55991;      // puertos de Chrome del Code B (55987–55994)
const BASE = `${PLANTILLA}_ch`;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGUSER: "postgres", PGDATABASE: BASE, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 << 20 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${BASE}`, "-c", `create database ${BASE} template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select (to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null and to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null)::text") !== "true") {
  console.error(`La plantilla ${PLANTILLA} no tiene los dos paquetes del Code A`); process.exit(2);
}

// ---------- 0. Personas y datos simulados (ZT) ----------
const EMAILS = { A: "zt.rep.admin@emdupar.gov.co", S: "zt.rep.sp@emdupar.gov.co", Y: "zt.rep.sd@emdupar.gov.co", O: "zt.rep.op@emdupar.gov.co" };
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZT Admin", []); lb(EMAILS.S, "ZT Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]);
lb(EMAILS.Y, "ZT Supervisor de distribución", ["ver_registro_tecnico", "ver_dashboard_redes"]); lb(EMAILS.O, "ZT Operador", ["ver_registro_tecnico"]);
const FOTO = "remisiones/2026-11/0b0f8e8c-aaaa-4bbb-8ccc-1234567890ab.jpg";
sqlq(`do $$ declare v_pl bigint; v_pu bigint; v_var record; d int; l uuid; v_pac bigint; begin
  for d in 1..20 loop
    for v_pl in select id from tecnica.plantas where activa loop
      l := gen_random_uuid();
      insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
      select l, fv.formulario, fv.variable_id, v_pl, 400 + d + 0.25, (clock_timestamp() at time zone 'America/Bogota')::date - d, '07:30', '${EMAILS.O}'
        from tecnica.formulario_variables fv where fv.formulario = 'entrada' and fv.alcance = 'por_planta';
      l := gen_random_uuid();
      insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
      select l, fv.formulario, fv.variable_id, v_pl, 1.35, (clock_timestamp() at time zone 'America/Bogota')::date - d, '08:15', '${EMAILS.O}'
        from tecnica.formulario_variables fv where fv.formulario = 'salida' and fv.alcance = 'por_planta';
    end loop;
    select id into v_pu from tecnica.puntos where codigo = 'MUE-01';
    l := gen_random_uuid();
    insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
    select l, fv.formulario, fv.variable_id, v_pu, case when d = 3 then 9.5 else 0.8 end, (clock_timestamp() at time zone 'America/Bogota')::date - d, '10:00', '${EMAILS.O}'
      from tecnica.formulario_variables fv where fv.formulario = 'muestreo' and fv.alcance = 'por_punto';
  end loop;
  select id into v_pac from tecnica.quimicos where codigo = 'pac';
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
  values ('inventario_inicial', v_pac, 5000, 'kg', 5000, (clock_timestamp() at time zone 'America/Bogota')::date - 25, 'ZT conteo inicial de la prueba', '${EMAILS.O}');
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor)
  values ('entrada', v_pac, 1, 't', 1000, (clock_timestamp() at time zone 'America/Bogota')::date - 10, 'ZT Proveedor S. A.', 'ZT-R1', 'ZT-L1', '2027-06-30', '${FOTO}', '${EMAILS.O}'),
         ('entrada', v_pac, 500, 'kg', 500, (clock_timestamp() at time zone 'America/Bogota')::date - 5, 'ZT Proveedor S. A.', 'ZT-R2', null, null, null, '${EMAILS.O}');
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, autor)
  select 'uso', v_pac, p.id, 'dosificacion', 120.5, 'kg', -120.5, (clock_timestamp() at time zone 'America/Bogota')::date - g, '${EMAILS.O}'
    from tecnica.plantas p, generate_series(1, 4) g where p.activa;
end $$`);
// Distribución: un cierre de válvula (ZT) dentro de un sector de la capa, para bajar Válvulas cerradas filtrado por ese sector (y ver el sector en el «Léame»)
const SEC_VAL = JSON.parse(sqlq(`with v as (select a.activo_id, (redes.f_sector_de(a.geom)).sector as s from redes.activo_vigente_mat a where a.prefijo = 'VAL' and not a.retirado and not a.oculto
    and (redes.f_sector_de(a.geom)).sector is not null order by a.codigo limit 1),
  s as (select x ->> 'codigo' as codigo, x ->> 'nombre' as nombre from jsonb_array_elements(to_jsonb(public.geoportal_redes_reporte_sectores('${EMAILS.A}')) -> 'sectores') x, v
         where x ->> 'clase' = 'sector' and (x ->> 'sector')::int = v.s)
  select json_build_object('activo', v.activo_id, 'sector', v.s, 'codigo', s.codigo, 'nombre', s.nombre) from v, s`));
sqlq(`with c as (insert into redes.valvula_maniobras (valvula_id, tipo, motivo, regreso_estimado, hecho_en, autor)
  values (${SEC_VAL.activo}, 'cerrar', 'ZT cierre de prueba para la descarga', now() - interval '5 days' + interval '4 hours', now() - interval '5 days', '${EMAILS.Y}') returning id)
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, hecho_en, autor) select ${SEC_VAL.activo}, 'abrir', c.id, now() - interval '5 days' + interval '3 hours', '${EMAILS.Y}' from c`);
const MOV = sqlq(`select id from tecnica.quimico_movimientos where remision = 'ZT-R1'`);
const hoy = sqlq("select (clock_timestamp() at time zone 'America/Bogota')::date");
const hace = (d) => sqlq(`select (clock_timestamp() at time zone 'America/Bogota')::date - ${d}`);
const N_ACT = Number(sqlq("select count(*) from redes.activo_vigente_mat where not retirado and not oculto"));
/** Envíos (lote y lugar) de un formulario en los últimos 30 días, sin los excluidos enteros: lo que debe traer el reporte. */
const envios = (form, planta, punto) => Number(sqlq(`select count(distinct (r.lote_id, r.planta_id, r.punto_id)) from tecnica.v_registros_estado r left join tecnica.plantas pl on pl.id = r.planta_id left join tecnica.puntos pu on pu.id = r.punto_id
  where r.formulario = '${form}' and r.fecha_muestra between (clock_timestamp() at time zone 'America/Bogota')::date - 30 and (clock_timestamp() at time zone 'America/Bogota')::date and not r.excluido
  ${planta ? `and pl.codigo = '${planta}'` : ""} ${punto ? `and pu.codigo = '${punto}'` : ""}`));
const PLANTAS = sqlq("select string_agg(codigo, ',' order by codigo) from tecnica.plantas where activa").split(",");

// ---------- 1. Páginas (dashboards reales y remision.html; la sesión simulada es la de ?rol=, que se recuerda para abrir el enlace del Excel) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_reportes_edge_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const q = new URLSearchParams(location.search).get("rol"); if (q !== null) localStorage.setItem("zt_rol", q);
    const rol = localStorage.getItem("zt_rol") || "";
    export const FUNCTIONS_URL = "http://127.0.0.1:${P_EDGE}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: rol ? { access_token: "tok-" + rol } : null } }), refreshSession: async () => ({ data: { session: null }, error: rol ? null : { message: "x" } }), signOut: async () => ({}) },
      storage: { from: () => ({}) } };` }));
} };
const opcionesBuild = (salida) => ({ plugins: [doble], bundle: true, platform: "browser", format: "iife", outfile: join(dir, salida), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' } });
await build({ ...opcionesBuild("paquete.js"), stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css";
    import { Dashboard } from "./src/tecnica/Dashboard.tsx"; import { DashboardRedes } from "./src/tecnica/DashboardRedes.tsx";
    const q = new URLSearchParams(location.search), r = createRoot(document.getElementById("raiz"));
    r.render(<div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>{q.get("p") === "dist"
      ? <DashboardRedes correo="zt@emdupar.gov.co" onVolver={() => {}} />
      : <Dashboard correo="zt@emdupar.gov.co" rotuloPerfil="Supervisor de planta" onVolver={() => {}} />}</div>);
    setTimeout(() => { window.__listo = true; }, 400);` } });
await build({ ...opcionesBuild("remision.js"), stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client"; import { FotoRemision } from "./src/remision/FotoRemision.tsx";
    createRoot(document.getElementById("root")).render(<FotoRemision />); setTimeout(() => { window.__listo = true; }, 300);` } });
const html = (js, css, id) => `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${css}"><style>html,body{margin:0;height:100%}</style></head><body><div id="${id}"></div><script src="${js}"></script></body></html>`;
writeFileSync(join(dir, "index.html"), html("paquete.js", "paquete.css", "raiz"));
writeFileSync(join(dir, "remision.html"), html("remision.js", "remision.css", "root"));
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGNgYGD4z8DAwMDAwMAAAA8AAf+ZqgQAAAAASUVORK5CYII=", "base64");

// ---------- 2. Auth, PostgREST y Storage simulados; las RPC van a la base REAL con el rol y los topes de producción ----------
const firmas = [], fotosServidas = [], rpcs = [];
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
/** Doble del catálogo del Dashboard PTAP (la base local no tiene geoportal_tec_catalogo_filtros): plantas, puntos y zonas REALES de las tablas de planta. */
const catalogoPtap = () => JSON.parse(sqlq(`select json_build_object('formularios', json_build_array(json_build_object('clave','entrada','nombre','Entrada','descripcion',''),json_build_object('clave','salida','nombre','Salida','descripcion',''),json_build_object('clave','muestreo','nombre','Muestreo','descripcion','')),
  'plantas', (select json_agg(json_build_object('codigo', codigo, 'nombre', nombre, 'activa', activa) order by codigo) from tecnica.plantas),
  'zonas', (select json_agg(distinct zona) from tecnica.puntos where zona is not null),
  'puntos', (select json_agg(json_build_object('codigo', pu.codigo, 'nombre', pu.nombre, 'tipo', pu.tipo, 'zona', pu.zona, 'planta', pl.codigo, 'numero_informe', pu.numero_informe, 'activo', pu.activo) order by pu.codigo) from tecnica.puntos pu left join tecnica.plantas pl on pl.id = pu.planta_id),
  'descarga_max_filas', 50000, 'descarga_pagina_max', 5000, 'motivo_min', 10, 'motivo_max', 500)`));
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }); res.end(JSON.stringify(o)); };
  if (req.method === "GET" && /^\/(index\.html|remision\.html|paquete\.(js|css)|remision\.(js|css))?$/.test(u.pathname)) {
    const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    try { res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); return res.end(readFileSync(join(dir, f))); } catch { res.writeHead(404); return res.end(); }
  }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/storage/v1/object/sign/tecnica-evidencias/")) {
      const ruta = decodeURIComponent(u.pathname.split("/tecnica-evidencias/")[1]);
      if (req.method === "POST") { firmas.push(ruta); return json(200, { signedURL: `/object/sign/tecnica-evidencias/${ruta}?token=zt-firma` }); }
      if (u.searchParams.get("token") !== "zt-firma") return json(400, { error: "token" });
      fotosServidas.push(ruta); res.writeHead(200, { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" }); return res.end(PNG);
    }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(Buffer.concat(trozos).toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      rpcs.push(fn);
      if (fn === "geoportal_tec_catalogo_filtros" && !hayRpc(fn)) return json(200, catalogoPtap());
      if (!hayRpc(fn)) return json(404, { code: "PGRST202", message: "no existe" });
      const r = rpcBase(fn, a); return json(r.status, r.cuerpo);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- 3. Las dos Edges REALES del Code A en Deno ----------
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => (new URL(r.url).pathname.includes("geoportal-redes") ? hs[1] : hs[0])(r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`las Edges terminaron (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("las Edges no arrancaron: " + edgeLog)), 60000); });

// ---------- 4. Chrome ----------
let total = 0, fallas = 0;
const ok = (n, cond, d = "") => { total++; if (!cond) fallas++; console.log(`${cond ? "OK   " : "FALLA"} ${n}${cond ? "" : " → " + String(d).replace(/\n/g, " ").slice(0, 700)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
const ORIGEN = `http://127.0.0.1:${P_BASE}`;
let ANCHO = 390, ALTO = 844, BAJADAS = "";
const iniciados = [];      // respuestas reales de reporte_iniciar (200)
async function abrir(qs, pagina = "") {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: ANCHO < 500 ? 2 : 1, isMobile: ANCHO < 500, hasTouch: ANCHO < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("ERROR de página:", String(e).slice(0, 300)); });
  pg.on("response", async (r) => { if (r.url().includes("accion=reporte_iniciar") && r.status() === 200) { try { iniciados.push(await r.json()); } catch { /* sin cuerpo */ } } });
  const cdp = await pg.createCDPSession(); await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: BAJADAS });
  await pg.goto(`${ORIGEN}/${pagina}${qs ? "?" + qs : ""}`); await pg.waitForFunction("window.__listo === true", { timeout: 20000 }); await esp(400);
  return pg;
}
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().startsWith(x) && !e.disabled); if (b) b.click(); return !!b; }, sel, t);
const pestana = (pg, t) => clicTexto(pg, "[role=tab]", t);
const tarjeta = (pg, k) => pg.evaluate((x) => { const b = document.querySelector(`[data-reporte="${x}"] .rep-cab`); if (b && !b.disabled && b.getAttribute("aria-expanded") !== "true") b.click(); return !!b; }, k);
const enTarjeta = (pg, k, t) => clicTexto(pg, `[data-reporte="${k}"] button`, t);
const fijar = (pg, sel, v) => pg.evaluate((s, x) => { const e = document.querySelector(s); if (!e) return false; const set = Object.getOwnPropertyDescriptor(e.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype, "value").set;
  set.call(e, x); e.dispatchEvent(new Event(e.tagName === "SELECT" ? "change" : "input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); return true; }, sel, v);
const opciones = (pg, sel) => pg.evaluate((s) => [...document.querySelectorAll(`${s} option`)].map((o) => o.value).filter(Boolean), sel);
const avisoDe = (pg, k) => pg.evaluate((x) => document.querySelector(`[data-reporte="${x}"] .td-aviso`)?.textContent ?? "", k);
/** Descarga con un botón y espera el aviso NUEVO (se borra el anterior al empezar). */
async function bajar(pg, k, boton, ms = 90000) {
  const antes = readdirSync(BAJADAS);
  await enTarjeta(pg, k, boton);
  await pg.waitForFunction((x) => { const t = document.querySelector(`[data-reporte="${x}"]`); return t && !t.querySelector(".rep-progreso") && !!t.querySelector(".td-aviso"); }, { timeout: ms }, k).catch(() => {});
  const aviso = await avisoDe(pg, k);
  let f = null;
  if (/^Listo/.test(aviso)) { const fin = Date.now() + 15000; while (Date.now() < fin && !f) { const n = readdirSync(BAJADAS).filter((x) => !antes.includes(x) && !x.endsWith(".crdownload")); if (n.length) { await esp(300); f = join(BAJADAS, n[0]); } else await esp(150); } }
  return { aviso, f };
}
const PY = `
import json, sys, openpyxl, datetime
wb = openpyxl.load_workbook(sys.argv[1])
ws = wb.worksheets[0]
filas = list(ws.iter_rows(values_only=True))
def v(x):
    if isinstance(x, datetime.datetime): return {"dt": x.strftime("%Y-%m-%d %H:%M:%S")}
    if isinstance(x, datetime.date): return {"d": x.strftime("%Y-%m-%d")}
    return x
enl = [[c.coordinate, c.hyperlink.target, c.value] for row in ws.iter_rows(min_row=2) for c in row if c.hyperlink]
print(json.dumps({"hojas": wb.sheetnames, "enc": list(filas[0]), "n": len(filas) - 1, "filas": [[v(x) for x in f] for f in filas[1:400]], "enl": enl,
  "leame": [[a, b] for a, b in wb.worksheets[1].iter_rows(values_only=True)]}, default=str))`;
const leerXlsx = (f) => JSON.parse(execFileSync("python3", ["-I", "-c", PY, f], { encoding: "utf8", maxBuffer: 256 << 20 }));
const encabezado = (c) => (c.unidad ? `${c.titulo} (${c.unidad})` : c.titulo);
const ultimo = (rep) => iniciados.filter((x) => x.reporte === rep).at(-1);
/** El archivo trae exactamente las columnas que mandó el servidor, en su orden, y tantas filas como «total». */
function cuadra(x, ini) { return !!x && !!ini && JSON.stringify(x.enc) === JSON.stringify(ini.columnas.map(encabezado)) && x.n === ini.total && JSON.stringify(x.hojas) === JSON.stringify([ini.titulo.slice(0, 31), "Léame"]); }
const auditoria = (esq, email) => JSON.parse(sqlq(`select coalesce(json_agg(json_build_object('reporte', d.reporte, 'formato', d.formato, 'filtros', d.filtros, 'total', d.total, 'filas', c.filas, 'resultado', c.resultado) order by d.id), '[]')
  from ${esq}.reporte_descargas d left join ${esq}.reporte_descarga_cierres c on c.descarga_id = d.id where d.email = ${lit(email)}`));

const tiempos = [];
for (const [ancho, alto] of [[390, 844], [1280, 900]]) {
  ANCHO = ancho; ALTO = alto; const T = `[${ancho}]`;
  BAJADAS = join(CAP, `bajadas_edge_${ancho}`); rmSync(BAJADAS, { recursive: true, force: true }); mkdirSync(BAJADAS, { recursive: true });
  const nAudT = auditoria("tecnica", EMAILS.S).length;

  // ===================== PTAP (supervisor de planta) =====================
  let pg = await abrir("p=ptap&rol=S");
  await pestana(pg, "Reportes"); await pg.waitForSelector(".rep-tarjeta", { timeout: 15000 }).catch(() => {});
  ok(`${T} R1 Dashboard PTAP con la Edge real: ocho tarjetas en «Reportes»`, (await pg.$$(".rep-tarjeta")).length === 8);

  // Entrada en Excel, una planta real, 30 días
  await tarjeta(pg, "entrada"); await esp(200);
  await fijar(pg, "#rep-entrada-desde", hace(30)); await fijar(pg, "#rep-entrada-hasta", hoy);
  const plantas = await opciones(pg, "#rep-entrada-planta");
  ok(`${T} R2 la lista de plantas es la del dashboard (las activas de la base): ${plantas.join(", ")}`, JSON.stringify(plantas) === JSON.stringify(PLANTAS), JSON.stringify(plantas));
  await fijar(pg, "#rep-entrada-planta", PLANTAS[0]);
  let t0 = Date.now(); let r = await bajar(pg, "entrada", "Descargar Excel"); tiempos.push(`${T} Entrada (${PLANTAS[0]}, 30 días): ${Date.now() - t0} ms`);
  let ini = ultimo("entrada"); let x = r.f ? leerXlsx(r.f) : null;
  const nEnt = envios("entrada", PLANTAS[0]);
  ok(`${T} R3 Entrada de ${PLANTAS[0]}: «Listo: ${nEnt} filas» (los envíos de la base en el periodo), el Excel trae exactamente las columnas del servidor (con la unidad) y las filas de «total»`,
     new RegExp(`^Listo: ${nEnt} filas en Excel`).test(r.aviso) && cuadra(x, ini) && ini.total === nEnt, JSON.stringify([r.aviso, x?.enc, ini?.columnas?.map(encabezado), x?.n, ini?.total, nEnt]));
  const cMuestra = ini?.columnas.findIndex((c) => c.clave === "muestra"), cCaudal = ini?.columnas.findIndex((c) => c.tipo === "decimal" && c.clave.startsWith("v_"));
  const cReg = ini?.columnas.findIndex((c) => c.clave === "registro"), mias = (x?.filas ?? []).filter((f) => f[cReg] === EMAILS.O);
  ok(`${T} R4 los 20 envíos de la prueba: la fecha de la muestra es una fecha real de Excel a las 07:30 (hora de Bogotá, sin correrse) y la variable un número (401,25…)`,
     mias.length === 20 && mias.every((f) => / 07:30:00$/.test(f[cMuestra]?.dt ?? "")) && mias.some((f) => f[cCaudal] === 401.25) && x.enc.some((h) => /\(L\/s\)$/.test(h)), JSON.stringify([mias.length, mias[0]]));
  const le = Object.fromEntries((x?.leame ?? []).map(([a, b]) => [a, b ?? ""]));
  ok(`${T} R5 «Léame» con las líneas del servidor real (qué trae, qué no, la planta en los filtros) y quién descargó`,
     !!le["Qué trae"] && le["Qué trae"] === ini.leame.que_trae.join("\n") && le["Lo que no va"] === ini.leame.que_no_trae.join("\n") && le["Descargado por"] === EMAILS.S && le["Filas"] === String(nEnt) && /Planta: /.test(le["Filtros"]), JSON.stringify(le));

  // Salida en CSV: planta y punto vacíos
  await tarjeta(pg, "salida"); await esp(150); await fijar(pg, "#rep-salida-planta", "");
  r = await bajar(pg, "salida", "Descargar CSV"); ini = ultimo("salida");
  const csv = r.f ? readFileSync(r.f, "utf8").split("\r\n").filter(Boolean) : [];
  ok(`${T} R6 Salida en CSV (todas las plantas): el encabezado es el del servidor, una fila por envío y lugar (${PLANTAS.length} plantas × 20 días), coma decimal`,
     /^Listo: 40 filas en CSV/.test(r.aviso) && csv[0] === "﻿" + ini.columnas.map(encabezado).join(";") && csv.length === 41 && csv.slice(1).every((l) => l.includes(";1,35;")), JSON.stringify([r.aviso, csv[0], csv[1]]));

  // Muestreo: cada zona y cada punto de las listas los acepta el servidor (nunca «no aplica» ni «no corresponde»)
  await tarjeta(pg, "muestreo"); await esp(150);
  const zonas = await opciones(pg, "#rep-muestreo-zona"), puntos = await opciones(pg, "#rep-muestreo-punto");
  const rechazos = [];
  for (const z of zonas) { await fijar(pg, "#rep-muestreo-zona", z); r = await bajar(pg, "muestreo", "Descargar CSV"); if (!/^Listo|No hay datos con esos filtros/.test(r.aviso)) rechazos.push(`zona ${z}: ${r.aviso}`); }
  await fijar(pg, "#rep-muestreo-zona", "");
  for (const p of (ancho < 500 ? puntos.slice(0, 3) : puntos)) { await fijar(pg, "#rep-muestreo-punto", p); r = await bajar(pg, "muestreo", "Descargar CSV"); if (!/^Listo|No hay datos con esos filtros/.test(r.aviso)) rechazos.push(`punto ${p}: ${r.aviso}`); }
  ok(`${T} R7 Muestreo: las ${zonas.length} zonas y ${ancho < 500 ? 3 : puntos.length} puntos de la lista los acepta el servidor real (descarga o «No hay datos»)`, zonas.length > 0 && puntos.length > 0 && rechazos.length === 0, rechazos.join(" | "));
  await fijar(pg, "#rep-muestreo-punto", "MUE-01"); r = await bajar(pg, "muestreo", "Descargar Excel"); x = r.f ? leerXlsx(r.f) : null;
  const nMue = envios("muestreo", null, "MUE-01");
  ok(`${T} R8 Muestreo del punto MUE-01 en Excel: ${nMue} envíos (los de la base) con sus tres variables, cada una con su unidad`, new RegExp(`^Listo: ${nMue} filas`).test(r.aviso) && cuadra(x, ultimo("muestreo"))
     && ["(mg/L)", "(NTU)"].every((u) => x.enc.some((h) => h.endsWith(u))), JSON.stringify([r.aviso, x?.enc, nMue]));
  await fijar(pg, "#rep-muestreo-punto", "");

  // Uso de químicos: cada químico de la lista y cada planta
  await tarjeta(pg, "uso_quimicos"); await esp(300);
  const quimicos = await opciones(pg, "#rep-uso_quimicos-quimico");
  rechazos.length = 0;
  for (const q of quimicos) { await fijar(pg, "#rep-uso_quimicos-quimico", q); r = await bajar(pg, "uso_quimicos", "Descargar CSV"); if (!/^Listo|No hay datos con esos filtros/.test(r.aviso)) rechazos.push(`químico ${q}: ${r.aviso}`); }
  await fijar(pg, "#rep-uso_quimicos-quimico", "pac"); await fijar(pg, "#rep-uso_quimicos-planta", PLANTAS[0]);
  r = await bajar(pg, "uso_quimicos", "Descargar Excel"); x = r.f ? leerXlsx(r.f) : null;
  ok(`${T} R9 Uso de químicos: los ${quimicos.length} químicos de la lista los acepta el servidor; PAC en ${PLANTAS[0]}: 4 usos`, quimicos.length > 0 && rechazos.length === 0 && /^Listo: 4 filas/.test(r.aviso) && cuadra(x, ultimo("uso_quimicos")), rechazos.join(" | ") + " " + r.aviso);

  // Entrada de químicos: el vínculo «Ver foto»
  await tarjeta(pg, "entrada_quimicos"); await esp(150); await fijar(pg, "#rep-entrada_quimicos-quimico", "pac");
  r = await bajar(pg, "entrada_quimicos", "Descargar Excel"); x = r.f ? leerXlsx(r.f) : null; ini = ultimo("entrada_quimicos");
  const cFoto = ini?.columnas.findIndex((c) => c.clave === "foto_remision");
  ok(`${T} R10 Entrada de químicos: 2 entradas; la que tiene foto lleva «Ver foto» con vínculo a remision.html?movimiento=${MOV}; la otra, vacía`,
     /^Listo: 2 filas/.test(r.aviso) && cuadra(x, ini) && x.enl.length === 1 && x.enl[0][1] === `${ORIGEN}/remision.html?movimiento=${MOV}` && x.enl[0][2] === "Ver foto"
     && x.filas.some((f) => f[cFoto] === null), JSON.stringify([r.aviso, x?.enl, x?.filas]));
  if (ancho === 1280) await pg.screenshot({ path: join(CAP, `edge_ptap_entrada_quimicos_${ancho}.png`), fullPage: true });

  // Kardex
  await tarjeta(pg, "kardex_quimicos"); await esp(150); await fijar(pg, "#rep-kardex_quimicos-quimico", "pac");
  r = await bajar(pg, "kardex_quimicos", "Descargar Excel"); x = r.f ? leerXlsx(r.f) : null; ini = ultimo("kardex_quimicos");
  const cTipo = ini?.columnas.findIndex((c) => c.clave === "tipo"), cSaldo = ini?.columnas.findIndex((c) => c.clave === "saldo_kg");
  ok(`${T} R11 Kardex de PAC: «Saldo inicial», los movimientos y «Saldo al cierre» (5.000 + 1.000 + 500 − 8 × 120,5 = 5.536 kg)`,
     /^Listo/.test(r.aviso) && cuadra(x, ini) && x.filas[0][cTipo] === "Saldo inicial" && x.filas.at(-1)[cTipo] === "Saldo al cierre" && Math.abs(x.filas.at(-1)[cSaldo] - 5536) < 0.001, JSON.stringify([r.aviso, x?.filas?.map((f) => [f[cTipo], f[cSaldo]])]));

  // Eventos de planta y Fuera de referencia: con o sin datos, nunca un rechazo
  for (const k of ["eventos_planta", "fuera_referencia"]) {
    await tarjeta(pg, k); await esp(150);
    r = await bajar(pg, k, "Descargar Excel");
    ok(`${T} R12 ${k}: el servidor real lo acepta («${r.aviso.slice(0, 60)}»)`, /^Listo|^No hay datos con esos filtros\. No se generó el archivo\./.test(r.aviso), r.aviso);
  }
  if (ancho === 390) await pg.screenshot({ path: join(CAP, `edge_ptap_${ancho}.png`), fullPage: true });
  await pg.close();

  // Ver foto: el vínculo del Excel con la sesión del supervisor de planta, y sin sesión
  const nFirmas = fotosServidas.length;
  pg = await abrir(`movimiento=${MOV}`, "remision.html");
  await pg.waitForFunction(() => !/Cargando/.test(document.body.innerText), { timeout: 20000 }).catch(() => {});
  const foto = await pg.evaluate(() => { const i = document.querySelector("img.rem-foto"); return { src: i?.getAttribute("src") ?? "", carga: !!i && i.complete && i.naturalWidth > 0, txt: document.body.innerText }; });
  ok(`${T} R13 «Ver foto» con la sesión iniciada: la Edge real firma la foto de la remisión (60 s) y la página la muestra`,
     foto.carga && foto.src.includes("/storage/v1/object/sign/tecnica-evidencias/remisiones/") && fotosServidas.length > nFirmas && /vence en un minuto/.test(foto.txt), JSON.stringify(foto).slice(0, 400));
  if (ancho === 390) await pg.screenshot({ path: join(CAP, `edge_remision_${ancho}.png`), fullPage: true });
  await pg.close();
  pg = await abrir(`movimiento=${MOV}&rol=Y`, "remision.html");
  await pg.waitForFunction(() => !/Cargando/.test(document.body.innerText), { timeout: 20000 }).catch(() => {});
  ok(`${T} R14 el supervisor de distribución abre el vínculo: 403 de la Edge real → «Solo el supervisor de planta o el administrador…»`, /Solo el supervisor de planta o el administrador/.test(await pg.evaluate(() => document.body.innerText)));
  await pg.close();

  const audT = auditoria("tecnica", EMAILS.S).slice(nAudT);
  ok(`${T} R15 auditoría real del PTAP: cada descarga iniciada quedó cerrada «completa» con sus filas; sin datos no abre descarga`,
     audT.length > 0 && audT.every((a) => a.resultado === "completa" && a.filas === a.total) && audT.some((a) => a.reporte === "entrada" && a.formato === "xlsx" && a.filtros.planta === PLANTAS[0] && a.total === nEnt),
     JSON.stringify(audT.filter((a) => !(a.resultado === "completa" && a.filas === a.total)).concat(audT.slice(0, 1))));

  // ===================== Distribución (supervisor de distribución) =====================
  const nAudR = auditoria("redes", EMAILS.Y).length;
  pg = await abrir("p=dist&rol=Y");
  await pestana(pg, "Descargas"); await pg.waitForSelector(".rep-tarjeta", { timeout: 15000 }).catch(() => {});
  ok(`${T} D1 Dashboard distribución con la Edge real: nueve tarjetas en «Descargas»`, (await pg.$$(".rep-tarjeta")).length === 9);
  await tarjeta(pg, "activos"); await esp(400);
  const tipos = await opciones(pg, "#dsc-activos-tipo");
  t0 = Date.now(); r = await bajar(pg, "activos", "Descargar Excel", 180000); tiempos.push(`${T} Activos de la red (todo, Excel): ${Date.now() - t0} ms`);
  x = r.f ? leerXlsx(r.f) : null; ini = ultimo("activos");
  ok(`${T} D2 Activos de la red completo en Excel: ${N_ACT.toLocaleString("es-CO")} activos (los vigentes de la base), con las columnas del servidor`, cuadra(x, ini) && ini.total === N_ACT && new RegExp(`^Listo: ${N_ACT.toLocaleString("es-CO")} filas`).test(r.aviso), JSON.stringify([r.aviso, ini?.total, x?.n]));
  rechazos.length = 0;
  for (const t of (ancho < 500 ? tipos.slice(0, 4) : tipos)) { await fijar(pg, "#dsc-activos-tipo", t); r = await bajar(pg, "activos", "Descargar CSV", 120000); if (!/^Listo|No hay datos con esos filtros/.test(r.aviso)) rechazos.push(`${t}: ${r.aviso}`); }
  ok(`${T} D3 Activos: ${ancho < 500 ? 4 : tipos.length} tipos de activo de la lista (catálogo de redes) los acepta el servidor real`, tipos.length > 0 && rechazos.length === 0, rechazos.join(" | "));
  await fijar(pg, "#dsc-activos-tipo", "VAL"); await fijar(pg, "#dsc-activos-sistema", "acueducto");
  r = await bajar(pg, "activos", "Descargar CSV", 120000); ini = ultimo("activos");
  const nVal = Number(sqlq("select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and sistema = 'acueducto' and not retirado and not oculto"));
  ok(`${T} D4 Válvulas de acueducto en CSV: ${nVal} filas, como en la base`, ini?.total === nVal && new RegExp(`^Listo: ${nVal.toLocaleString("es-CO")} fila`).test(r.aviso), JSON.stringify([r.aviso, ini?.total, nVal]));
  await fijar(pg, "#dsc-activos-tipo", ""); await fijar(pg, "#dsc-activos-sistema", "");

  // Los reportes con sector: la lista sale de la ruta real reporte_sectores (sectores y subsectores de la capa) y el servidor acepta cada código; sin sector, también
  await tarjeta(pg, "l116"); await esp(300);
  const secs = await pg.evaluate(() => [...document.querySelectorAll("#dsc-l116-sector option")].filter((o) => o.value).map((o) => [o.value, o.textContent]));
  const secBase = JSON.parse(sqlq(`select to_jsonb(public.geoportal_redes_reporte_sectores(${lit(EMAILS.Y)}))`)).sectores;
  ok(`${T} D5a «Sector» es la lista de la ruta real: ${secBase.filter((x) => x.clase === "sector").length} sectores y ${secBase.filter((x) => x.clase === "subsector").length} subsectores, en su orden; los subsectores, sangrados`,
     secs.length > 0 && secs.length === secBase.length && secs.every(([c, t], i) => c === secBase[i].codigo && t === (secBase[i].clase === "subsector" ? "— " : "") + secBase[i].nombre), JSON.stringify([secs.slice(0, 4), secBase.slice(0, 4)]));
  rechazos.length = 0;
  const probar = ancho < 500 ? secs.slice(0, 3) : secs;
  for (const k of ["levantamientos", "valvulas", "eventos", "l116", "bot"]) {
    await tarjeta(pg, k); await esp(150);
    await fijar(pg, `#dsc-${k}-desde`, hace(300)); await fijar(pg, `#dsc-${k}-hasta`, hoy);
    for (const [c] of [["", ""], ...(k === "l116" ? probar : probar.slice(0, 2))]) {
      await fijar(pg, `#dsc-${k}-sector`, c); r = await bajar(pg, k, "Descargar CSV");
      if (!/^Listo|No hay datos con esos filtros\. No se generó/.test(r.aviso)) rechazos.push(`${k} sector «${c}»: ${r.aviso}`);
    }
    await fijar(pg, `#dsc-${k}-sector`, "");
  }
  await tarjeta(pg, "sensibles"); await esp(150);
  for (const t of await opciones(pg, "#dsc-sensibles-tipo")) { await fijar(pg, "#dsc-sensibles-tipo", t); r = await bajar(pg, "sensibles", "Descargar CSV"); if (!/^Listo|No hay datos con esos filtros\. No se generó/.test(r.aviso)) rechazos.push(`sensibles ${t}: ${r.aviso}`); }
  await tarjeta(pg, "valvulas"); await esp(150); await fijar(pg, "#dsc-valvulas-desde", hace(30)); await fijar(pg, "#dsc-valvulas-hasta", hoy); await fijar(pg, "#dsc-valvulas-sector", SEC_VAL.codigo);
  r = await bajar(pg, "valvulas", "Descargar Excel"); x = r.f ? leerXlsx(r.f) : null; ini = ultimo("valvulas");
  const leV = Object.fromEntries((x?.leame ?? []).map(([a, b]) => [a, b ?? ""])), cSec = ini?.columnas.findIndex((c) => c.clave === "sector");
  ok(`${T} D5b Válvulas cerradas del ${SEC_VAL.nombre} (${SEC_VAL.codigo}): el cierre de la prueba, 3 h de duración; la columna «Sector» es el número ${SEC_VAL.sector}; el «Léame» dice «Sector: ${SEC_VAL.nombre} (${SEC_VAL.codigo})»`,
     /^Listo: 1 fila en Excel/.test(r.aviso) && cuadra(x, ini) && x.filas[0][cSec] === SEC_VAL.sector && leV["Filtros"].includes(`Sector: ${SEC_VAL.nombre} (${SEC_VAL.codigo})`)
     && x.filas[0][ini.columnas.findIndex((c) => c.clave === "duracion_h")] === 3, JSON.stringify([r.aviso, x?.filas?.[0], leV["Filtros"]]));
  await fijar(pg, "#dsc-valvulas-sector", "");
  ok(`${T} D5 Encontrar, Válvulas, Eventos, Línea 116 y Bot (sin sector y con códigos de la lista: ${ancho < 500 ? 3 : "todos"} en la 116) y Usuarios sensibles (cada tipo): el servidor real los acepta`, rechazos.length === 0, rechazos.join(" | "));
  await tarjeta(pg, "danos"); await esp(150);
  r = await bajar(pg, "danos", "Descargar Excel");
  ok(`${T} D6 Daños y fallas sigue por la ruta «descarga» de siempre (Edge real)`, /^Listo|No hay datos con esos filtros\. No se generó/.test(r.aviso), r.aviso);
  if (ancho === 1280) await pg.screenshot({ path: join(CAP, `edge_descargas_${ancho}.png`), fullPage: true });
  await pg.close();
  const audR = auditoria("redes", EMAILS.Y).slice(nAudR);
  ok(`${T} D7 auditoría real de distribución: cada descarga cerrada «completa» con sus filas; el filtro de tipo y sistema quedó guardado`,
     audR.length > 0 && audR.every((a) => a.resultado === "completa" && a.filas === a.total) && audR.some((a) => a.reporte === "activos" && a.filtros.tipo === "VAL" && a.filtros.sistema === "acueducto" && a.formato === "csv"), JSON.stringify(audR.slice(0, 4)));

  // ===================== Quién entra =====================
  pg = await abrir("p=dist&rol=S"); await pestana(pg, "Descargas"); await pg.waitForSelector(".rep-tarjeta", { timeout: 15000 }).catch(() => {});
  await tarjeta(pg, "activos"); await esp(300); r = await bajar(pg, "activos", "Descargar CSV");
  ok(`${T} Q1 el supervisor de planta en Descargas de distribución: 403 real → «Solo el supervisor de distribución o el administrador descargan.»`, r.aviso === "Solo el supervisor de distribución o el administrador descargan.", r.aviso);
  await pg.close();
  pg = await abrir("p=ptap&rol=A"); await pestana(pg, "Reportes"); await pg.waitForSelector(".rep-tarjeta", { timeout: 15000 }).catch(() => {});
  await tarjeta(pg, "entrada"); await esp(200); await fijar(pg, "#rep-entrada-desde", hace(30)); await fijar(pg, "#rep-entrada-hasta", hoy);
  r = await bajar(pg, "entrada", "Descargar CSV");
  const nTodas = envios("entrada", null);
  ok(`${T} Q2 el administrador descarga Entrada (todas las plantas): ${nTodas} filas`, new RegExp(`^Listo: ${nTodas} filas`).test(r.aviso), r.aviso);
  await pg.close();
}
console.log("\nTiempos (navegador + Edges reales + base local; producción es unas 6 veces más lenta en la base):\n  " + tiempos.join("\n  "));
const raras = [...new Set(rpcs)].filter((f) => !hayRpc(f) && f !== "geoportal_tec_catalogo_filtros");
if (raras.length) console.log("RPC que la base local no tiene (las pidieron otras pestañas al cargar):", raras.join(", "));
console.log(`\n${total - fallas} de ${total}${fallas ? ` (${fallas} FALLAS)` : " SIN FALLAS"}`);
await nav.close(); srv.close(); edge.kill();
process.exit(fallas ? 1 : 0);
