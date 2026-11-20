// Prueba de las RUTAS de los reportes del PTAP (geoportal-tecnica) y de las descargas de Distribución (geoportal-redes) de punta a punta, sin pantallas
// (son del Code B): peticiones HTTP a las dos Edges REALES corriendo en Deno, cuyas RPC van a la base local de CODE A (localhost:55432: producción al 20-nov
// + los dos paquetes; se copia a <plantilla>_edgerep) con el rol de la API (service_role) y los topes de producción (30 s y 8 s). Auth, PostgREST y Storage
// son simulados (PostgREST pasa cada RPC a la base real; Storage solo firma). Datos SIMULADOS (prefijo ZTEDGE); los activos son los reales.
// Perfiles como los de las sondas: administrador (A), supervisor de planta (S), supervisor de distribución (Y), operador (O), Comercial + operador (D) y
// alguien sin módulo de Técnica (N). Puertos de Code A: 54993 (Auth, PostgREST y Storage) y 54994 (Edges).
// Uso: node scripts/prueba_edge_reportes.mjs <deno> <supabase/functions> <psql> <plantilla con los dos paquetes, p. ej. redes_local>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_edge_reportes.mjs <deno> <supabase/functions> <psql> <base plantilla con los dos paquetes>"); process.exit(2); }
const P_BASE = 54993, P_EDGE = 54994;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_edgerep`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { A: "ztedge.admin@emdupar.gov.co", S: "ztedge.sp@emdupar.gov.co", Y: "ztedge.sd@emdupar.gov.co", O: "ztedge.op@emdupar.gov.co", D: "ztedge.comercial@emdupar.gov.co", N: "ztedge.nada@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_edgerep`, "-c", `create database ${PLANTILLA}_edgerep template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select coalesce(to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)')::text, '') || coalesce(to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)')::text, '')") === "") {
  console.error(`La plantilla ${PLANTILLA} no tiene los dos paquetes (sh rehacer_base.sh con_todo)`); process.exit(2);
}
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZTEDGE Admin", []); lb(EMAILS.S, "ZTEDGE Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]); lb(EMAILS.Y, "ZTEDGE Supervisor de distribución", ["ver_registro_tecnico", "ver_dashboard_redes"]);
lb(EMAILS.O, "ZTEDGE Operador", ["ver_registro_tecnico"]); lb(EMAILS.D, "ZTEDGE Comercial", ["ver_comercial", "ver_registro_tecnico"]); lb(EMAILS.N, "ZTEDGE Sin módulo", ["ver_explorar"]);
// datos simulados de planta: una planta, una variable de Entrada, 30 días de envíos, un químico con una entrada con foto de la remisión
sqlq(`do $$ declare v_pl bigint; v_var bigint; v_q bigint; begin
  insert into tecnica.plantas (codigo, nombre) values ('ztedge_pl', 'ZTEDGE Planta') returning id into v_pl;
  insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales) values ('ztedge_ti', 'ZTEDGE Turbiedad', 'NTU', 'fisicoquimico', 1) returning id into v_var;
  insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance) values ('entrada', v_var, 990, 'por_planta');
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v_var, v_pl, 10 + d, (clock_timestamp() at time zone 'America/Bogota')::date - d, '08:00', '${EMAILS.O}' from generate_series(0, 29) d;
  insert into tecnica.quimicos (codigo, nombre, rol) values ('ztedge_q', 'ZTEDGE Químico', 'auxiliar') returning id into v_q;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, remision_foto, autor)
  values ('entrada', v_q, 1, 't', 1000, current_date - 1, 'ZTEDGE Proveedor', 'R-1', 'remisiones/2026-11/0b0f8e8c-1111-2222-3333-444455556666.jpg', '${EMAILS.O}');
end $$`);
// datos simulados de redes: un sector de prueba en la capa (SEC), un punto LEV dentro y un evento amarrado a un daño de catálogo (falla de bombeo por desgaste)
sqlq(`do $$ declare v_id bigint; v_c bigint; v_cod text; g geometry := ST_Multi(ST_MakeEnvelope(-73.58, 10.13, -73.578, 10.132, 4326)); v_d uuid := gen_random_uuid(); begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_c;
  v_cod := 'SEC-' || lpad(v_c::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'SEC', 'carga', '${EMAILS.A}') returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
  values (v_id, 1, g, 'ZTEDGE Sector 77', 'sector', 'en_operacion', '{"modelo": {"sector": 77}}', md5(v_cod), '${EMAILS.A}');
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEDGE', '${EMAILS.A}');
  perform redes.f_mat_refrescar_uno(v_id);
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor)
  values (gen_random_uuid(), 'LEV-977001', 'acueducto', 'valvula', 10.131, -73.579, ST_SetSRID(ST_MakePoint(-73.579, 10.131), 4326), 4, false, 'tecnica', '${EMAILS.O}');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, no_ident_que_es, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, causa_codigo, descripcion, autor)
  values (v_d, 'DAN-' || lpad(((select coalesce(max(substr(d.codigo, 5)::integer), 0) from redes.danos d) + 1)::text, 6, '0'), 'falla', 'bombeo', 'acueducto', 'ZTEDGE bomba', 10.5, -73.0,
          'gps', clock_timestamp() - interval '3 hours', 'medio', 'propia', 'desgaste', 'ZTEDGE Pedro Prueba 3009990000', '${EMAILS.Y}');
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, zona_nombre, causa, dano_id, desde, contratos, sensibles, autor)
  values ('EVS-977001', 'sectores', false, g, array[v_id], 'ZTEDGE Sector 77', 'ZTEDGE Pedro Prueba 3009990000', v_d, clock_timestamp() - interval '2 hours', 0, 0, '${EMAILS.Y}');
end $$`);
const SEC = sqlq("select codigo from redes.activo_vigente_mat where prefijo = 'SEC' and nombre = 'ZTEDGE Sector 77'");
const N_SEC = Number(sqlq("select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto"));
const MOV = Number(sqlq("select id from tecnica.quimico_movimientos where remision = 'R-1' and proveedor = 'ZTEDGE Proveedor'"));
const N_VAL = Number(sqlq("select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and not retirado and not oculto"));
const N_ACT = Number(sqlq("select count(*) from redes.activo_vigente_mat where not retirado and not oculto"));
const hoy = sqlq("select (clock_timestamp() at time zone 'America/Bogota')::date");
const hace = (d) => sqlq(`select (clock_timestamp() at time zone 'America/Bogota')::date - ${d}`);

// ---------- Auth, PostgREST y Storage simulados; cada RPC va a la base local REAL como la llama la Edge ----------
const desconocidas = [], todo = [], firmas = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select to_jsonb(public.${fn}(${args}))`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 256 * 1024 * 1024 }).trim();
    return { status: 200, cuerpo: t === "" ? null : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(), hint: /(HINT|SUGERENCIA):\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return EMAILS[rol] ? json(200, { id: "u-" + rol, email: EMAILS[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/storage/v1/object/sign/")) { firmas.push(u.pathname.slice(24)); return json(200, { signedURL: "/object/sign/" + u.pathname.slice(24) + "?token=firma-local" }); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(Buffer.concat(trozos).toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (sqlq(`select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = ${lit(fn)}`) === "0") { desconocidas.push(fn); return json(404, { code: "PGRST202", message: "no existe" }); }
      const r = rpcBase(fn, a);
      return json(r.status, r.cuerpo);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- las dos Edges REALES en Deno (una sola corrida; la ruta elige la función) ----------
const dir = mkdtempSync(join(tmpdir(), "edge_rep_"));
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

const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).replace(/\n/g, " ").slice(0, 600))); };
async function E(rol, fn, accion, o = {}) {
  const t0 = Date.now();
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/${fn}?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
    headers: { ...(rol ? { Authorization: `Bearer tok-${rol}` } : {}), ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined });
  const txt = await r.text(); let c = null; try { c = JSON.parse(txt); } catch { /* */ }
  todo.push(txt);
  return { s: r.status, c, cache: r.headers.get("cache-control"), txt, ms: Date.now() - t0 };
}
const T = "geoportal-tecnica", R = "geoportal-redes";
async function bajar(rol, fn, cuerpo, limite = 5000) {
  const i = await E(rol, fn, "reporte_iniciar", { cuerpo });
  if (i.s !== 200) return { i, filas: [], paginas: 0, peor: 0 };
  let cursor = null, filas = [], paginas = 0, peor = 0;
  do { const p = await E(rol, fn, "reporte_pagina", { cuerpo: { descarga_id: i.c.descarga_id, cursor, limite } }); if (p.s !== 200) return { i, filas, paginas, peor, error: p.txt };
       filas = filas.concat(p.c.filas); cursor = p.c.cursor; paginas++; peor = Math.max(peor, p.ms); } while (cursor);
  const c = await E(rol, fn, "reporte_cerrar", { cuerpo: { descarga_id: i.c.descarga_id, filas: filas.length, resultado: "completa" } });
  return { i, filas, paginas, peor, cierre: c };
}
try {
  // ===== A. Quién entra (las sondas propuestas) =====
  const ptap = { desde: hace(29), hasta: hoy, planta: "ztedge_pl", formato: "xlsx", reporte: "entrada" };
  const dist = { reporte: "activos", tipo: "VAL", formato: "csv" };
  const pt = [], nt = [], pr = [], nr = [];
  for (const p of ["A", "S", "Y", "O", "D", "N"]) {
    const a = await E(p, T, "reporte_iniciar", { cuerpo: ptap }); (a.s === 200 ? pt : nt).push(p + (a.s === 200 || a.s === 403 ? "" : `(${a.s})`));
    const b = await E(p, R, "reporte_iniciar", { cuerpo: dist }); (b.s === 200 ? pr : nr).push(p + (b.s === 200 || b.s === 403 ? "" : `(${b.s})`));
  }
  ok("A1 PTAP (reporte_iniciar): permiten A y S; Y, O, D y N reciben 403", pt.join() === "A,S" && nt.join() === "Y,O,D,N", `permiten ${pt} · niegan ${nt}`);
  ok("A2 Distribución (reporte_iniciar): permiten A e Y; S, O, D y N reciben 403", pr.join() === "A,Y" && nr.join() === "S,O,D,N", `permiten ${pr} · niegan ${nr}`);
  ok("A3 sin sesión: 401 en las dos", (await E(null, T, "reporte_iniciar", { cuerpo: ptap })).s === 401 && (await E(null, R, "reporte_iniciar", { cuerpo: dist })).s === 401);
  let r = await E("S", T, "reporte_pagina", { cuerpo: { descarga_id: 999999999 } });
  ok("A4 la página de una descarga que no existe: 404 con su texto", r.s === 404 && /no existe/.test(r.c?.error ?? ""), r.txt);
  r = await E("S", T, "reporte_iniciar", { cuerpo: { ...ptap, desde: "2001-01-01", hasta: "2001-01-31" } });
  ok("A5 sin datos con esos filtros: 404 «No hay datos con esos filtros.»", r.s === 404 && r.c?.error === "No hay datos con esos filtros.", r.txt);
  r = await E("S", T, "reporte_iniciar", { cuerpo: { ...ptap, quimico: "ztedge_q" } });
  ok("A6 un filtro que no aplica al reporte: 400 con su texto (lo dice la base)", r.s === 400 && /no aplica/.test(r.c?.error ?? ""), r.txt);

  // ===== B. PTAP: Entrada de punta a punta (iniciar → páginas de 7 → cerrar) =====
  let b = await bajar("S", T, ptap, 7);
  const claves = (o) => Object.keys(o).sort().join();
  ok(`B1 Entrada: ${b.i.c?.total} envíos en ${b.paginas} páginas de 7; cada fila trae exactamente las claves de «columnas»; sin caché; cerrar responde «cerrada»`,
    b.i.s === 200 && b.i.cache === "no-store" && b.i.c.total === 30 && b.filas.length === 30 && b.paginas === 5 && b.filas.every((f) => claves(f) === b.i.c.columnas.map((c) => c.clave).sort().join())
    && b.filas.every((f) => typeof f.v_ztedge_ti === "number") && b.cierre?.c?.cerrada === true, b.error ?? b.i.txt.slice(0, 300));
  ok("B2 la columna de la variable trae su título, la unidad y los decimales; el Léame trae qué trae, qué no, los filtros, quién y cuándo",
    b.i.c.columnas.some((c) => c.clave === "v_ztedge_ti" && c.titulo === "ZTEDGE Turbiedad" && c.unidad === "NTU" && c.tipo === "decimal" && c.decimales === 1)
    && b.i.c.leame.que_trae.length > 0 && b.i.c.leame.que_no_trae.length > 0 && b.i.c.leame.filtros.some((x) => /ZTEDGE Planta/.test(x)) && b.i.c.leame.generado_por === EMAILS.S && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(b.i.c.leame.generado_en));
  ok("B3 las fechas van como hora de Bogotá sin zona («AAAA-MM-DDTHH:MM:SS»)", b.filas.every((f) => /^\d{4}-\d{2}-\d{2}T08:00:00$/.test(f.muestra) && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(f.registrado)));
  r = await E("S", T, "reporte_pagina", { cuerpo: { descarga_id: b.i.c.descarga_id } });
  ok("B4 cerrada la descarga, sus páginas: 409 «ya terminó»", r.s === 409 && /ya terminó/.test(r.c?.error ?? ""), r.txt);
  r = await E("A", T, "reporte_pagina", { cuerpo: { descarga_id: b.i.c.descarga_id } });
  ok("B5 la descarga de otra persona (el administrador pide la del supervisor): 404", r.s === 404, r.txt);

  // ===== C. La foto de la remisión =====
  b = await bajar("S", T, { reporte: "entrada_quimicos", desde: hace(10), hasta: hoy, quimico: "ztedge_q", formato: "xlsx" });
  ok("C1 Entrada de químicos: la foto va como el número del movimiento (enlace), nunca la ruta", b.filas.length === 1 && b.filas[0].foto_remision === MOV && !b.i.txt.includes("remisiones/") && !todo.slice(-3).some((t) => t.includes("remisiones/")), JSON.stringify(b.filas));
  firmas.length = 0;
  r = await E("S", T, "reporte_remision_foto", { qs: { movimiento: MOV } });
  ok("C2 reporte_remision_foto: URL firmada de 60 s del bucket privado, sin la ruta, sin caché", r.s === 200 && r.cache === "no-store" && r.c.movimiento === MOV && /token=firma-local/.test(r.c.url) && !!r.c.expira_en
    && !("ruta" in r.c) && firmas.length === 1 && firmas[0].startsWith("tecnica-evidencias/remisiones/"), r.txt);
  ok("C3 la foto: el supervisor de distribución recibe 403 y el operador también", (await E("Y", T, "reporte_remision_foto", { qs: { movimiento: MOV } })).s === 403 && (await E("O", T, "reporte_remision_foto", { qs: { movimiento: MOV } })).s === 403);

  // ===== D. Distribución: válvulas (tipo VAL) en páginas de 200 y Activos de la red completo en páginas de 5.000 =====
  b = await bajar("Y", R, dist, 200);
  ok(`D1 Activos tipo VAL: ${b.filas.length} filas en ${b.paginas} páginas de 200, sin repetir ni saltar (= los ${N_VAL} vigentes de la base)`,
    b.filas.length === N_VAL && new Set(b.filas.map((f) => f.codigo)).size === N_VAL && b.filas.every((f) => f.prefijo === "VAL") && b.paginas === Math.ceil(N_VAL / 200), b.error ?? "");
  const t0 = Date.now(); b = await bajar("Y", R, { reporte: "activos", formato: "xlsx" }); const tAct = Date.now() - t0;
  console.log(`   TIEMPOS por la Edge: Activos de la red completo (${b.filas.length} filas, ${b.paginas} páginas) en ${tAct} ms; iniciar ${b.i.ms} ms; la página más lenta ${b.peor} ms`);
  ok(`D2 TIEMPOS: Activos de la red completo por la Edge (${b.filas.length} filas en ${b.paginas} páginas): ninguna llamada pasa de 5 s`, b.filas.length === N_ACT && b.i.ms < 5000 && b.peor < 5000, `${b.i.ms} · ${b.peor}`);
  r = await E("Y", R, "reporte_iniciar", { cuerpo: { reporte: "l116", formato: "xlsx" } });
  ok("D3 un reporte con periodo sin periodo: 400 «Elija el periodo»", r.s === 400 && /Elija el periodo/.test(r.c?.error ?? ""), r.txt);
  r = await E("Y", R, "reporte_iniciar", { cuerpo: { reporte: "sensibles", formato: "xlsx", tipo: "hospital" } });
  ok("D4 sin usuarios sensibles en la base: 404 sin datos (y no 500)", r.s === 404, r.txt);

  // ===== E. El filtro de sector (la lista) y el tipo y la causa de catálogo en Eventos =====
  r = await E("Y", R, "reporte_sectores");
  const sec = r.c?.sectores?.find((x) => x.codigo === SEC);
  ok(`E1 reporte_sectores: la lista con los ${N_SEC} sectores y subsectores vigentes de la capa (código, nombre, clase, sector y subsector)`,
    r.s === 200 && r.c.sectores.length === N_SEC && sec?.nombre === "ZTEDGE Sector 77" && sec?.clase === "sector" && sec?.sector === 77 && sec?.subsector === null
    && Object.keys(sec).sort().join() === "clase,codigo,nombre,sector,subsector", r.txt.slice(0, 400));
  ok("E2 la lista: el supervisor de planta y el operador reciben 403; por POST, 405", (await E("S", R, "reporte_sectores")).s === 403 && (await E("O", R, "reporte_sectores")).s === 403
    && (await E("Y", R, "reporte_sectores", { metodo: "POST", cuerpo: {} })).s === 405);
  b = await bajar("Y", R, { reporte: "levantamientos", desde: hace(1), hasta: hoy, sector: SEC.toLowerCase(), formato: "csv" });
  ok("E3 Encontrar o reportar activo por el sector de la lista (el código, aunque venga en minúsculas): el LEV del sector; el Léame dice el nombre",
    b.i.s === 200 && b.filas.length === 1 && b.filas[0].codigo === "LEV-977001" && b.i.c.filtros.sector === SEC && b.i.c.leame.filtros.some((x) => x.includes("ZTEDGE Sector 77")), b.i.txt.slice(0, 400));
  r = await E("Y", R, "reporte_iniciar", { cuerpo: { reporte: "levantamientos", desde: hace(1), hasta: hoy, sector: "77", formato: "csv" } });
  ok("E4 un sector escrito como número: 400 «Elija el sector de la lista.» (lo dice la Edge, sin llegar a la base)", r.s === 400 && r.c?.error === "Elija el sector de la lista.", r.txt);
  b = await bajar("Y", R, { reporte: "eventos", desde: hace(1), hasta: hoy, sector: SEC, formato: "xlsx" });
  const ev = b.filas.find((f) => f.evento === "EVS-977001");
  ok("E5 Eventos: tipo «Falla de bombeo» y causa «Desgaste o vejez de la tubería» del catálogo del daño; la causa escrita y la descripción no salen",
    b.i.s === 200 && ev?.tipo === "Falla de bombeo" && ev?.causa === "Desgaste o vejez de la tubería" && ev?.tipo_intervencion === null
    && b.i.c.columnas.some((c) => c.clave === "tipo" && c.titulo === "Tipo de daño o falla") && !JSON.stringify(b).includes("Pedro"), JSON.stringify(ev));

  // ===== Z. Lo que no debe salir =====
  ok("Z1 ninguna respuesta trae teléfonos ni nombres de las personas de prueba (los correos sí: son de funcionarios)", !todo.some((t) => /ZTEDGE (Admin|Supervisor|Operador|Comercial|Sin)/.test(t) || /\b3\d{9}\b/.test(t)));
  ok("Z2 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_edgerep`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
