// Prueba de las RUTAS del Corte 15 («Evento de suspensión») de punta a punta, sin pantallas (son del Code B): peticiones HTTP a la Edge geoportal-redes
// REAL corriendo en Deno, cuyas RPC van a la base local de CODE A (localhost:55432: producción al 18-nov + el paquete del 15; se copia a <plantilla>_edge15)
// con el rol de la API (service_role) y los topes de producción (30 s y 8 s). Auth y PostgREST son simulados (el segundo pasa cada RPC a la base real).
// Recorre el flujo completo con perfiles sintéticos (supervisor de distribución, supervisor de planta, operador, administrador y alguien sin Técnica) sobre un
// sector sintético que cubre la red real: catálogo, vista previa, declarar (sectores, círculo, total), la asociación automática, vigentes, detalle, regreso,
// desasociar y asociar, los dos catálogos, anular y el cierre en bloque; y los rechazos por forma (400), método (405), permiso (403), estado (409) y sesión (401).
// Puertos de Code A: 54977 (Auth y PostgREST simulados) y 54978 (Edge).
// Uso: node scripts/prueba_edge_eventos_c15.mjs <deno> <supabase/functions> <psql> <plantilla, p. ej. redes_local>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_edge_eventos_c15.mjs <deno> <supabase/functions> <psql> <base plantilla con el Corte 15, p. ej. redes_local>"); process.exit(2); }
const P_BASE = 54977, P_EDGE = 54978;      // puertos de Code A
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_edge15`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : Array.isArray(v) && v.every((x) => typeof x === "string") ? `array[${v.map((x) => `'${x.replace(/'/g, "''")}'`).join(", ")}]::text[]`
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "zt15.admin@emdupar.gov.co", dist: "zt15.dist@emdupar.gov.co", planta: "zt15.planta@emdupar.gov.co", op: "zt15.oper@emdupar.gov.co", nada: "zt15.nada@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_edge15`, "-c", `create database ${PLANTILLA}_edge15 template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select coalesce(to_regclass('redes.eventos_suspension')::text, '')") === "") { console.error(`La plantilla ${PLANTILLA} no tiene el Corte 15 (sh rehacer_base.sh con_15)`); process.exit(2); }
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('${EMAILS.adm}', 'ZT15 Administrador', 'admin', 'sin_restriccion', 'todos'), ('${EMAILS.nada}', 'ZT15 Sin Técnica', 'consulta', 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('${EMAILS.dist}', 'ZT15 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values ('${EMAILS.planta}', 'ZT15 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('${EMAILS.op}', 'ZT15 Operador', 'consulta', true, 'sin_restriccion', 'todos')`);
sqlq(`insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('${EMAILS.op}', 'asignar_formulario', 'danos_fallas', '${EMAILS.adm}')`);
// dos sectores sintéticos sobre la red real (la base local no trae los 36 de producción): la mitad occidental y la oriental de la caja de la red
function sector(nombre, f0, f1) {
  return sqlq(`do $$ declare v_cons bigint; v_id bigint; c geometry; begin
    select ST_SetSRID(ST_Extent(m.geom)::geometry, 4326) into c from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto';
    update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_cons;
    insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values ('SEC-' || lpad(v_cons::text, 6, '0'), 'SEC', 'carga', '${EMAILS.adm}') returning id into v_id;
    insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
    values (v_id, 1, ST_SetSRID(ST_MakeEnvelope(ST_XMin(c) + (ST_XMax(c) - ST_XMin(c)) * ${f0}, ST_YMin(c), ST_XMin(c) + (ST_XMax(c) - ST_XMin(c)) * ${f1}, ST_YMax(c)), 4326),
            '${nombre}', 'sector', 'en_operacion', '{}'::jsonb, md5('${nombre}'), '${EMAILS.adm}');
    insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT15 sector sintético', '${EMAILS.adm}');
    perform redes.f_mat_refrescar_uno(v_id);
  end $$; select codigo from redes.activo_vigente_mat where nombre = '${nombre}'`).split("\n").pop();
}
const S1 = sector("ZT15 Sector occidente", 0, 0.5), S2 = sector("ZT15 Sector oriente", 0.5, 1);
const punto = (cod, fx, fy) => JSON.parse(sqlq(`select jsonb_build_object('lat', round((ST_YMin(geom) + (ST_YMax(geom) - ST_YMin(geom)) * ${fy})::numeric, 6), 'lon', round((ST_XMin(geom) + (ST_XMax(geom) - ST_XMin(geom)) * ${fx})::numeric, 6)) from redes.activo_vigente_mat where codigo = '${cod}'`));
const bot = (rad, p, tipo = "sin_agua") => JSON.parse(sqlq(`select redes.f_reporte_externo_recibir_evento(${lit({ radicado: rad, canal: "telegram", tipo, ...p })})`));

// ---------- Auth y PostgREST simulados; cada RPC va a la base local REAL como la llama la Edge ----------
const desconocidas = [], todo = [];
function rpcBase(fn, a) {
  const args = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'", "-c", `select to_jsonb(public.${fn}(${args}))`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 }).trim();
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

// ---------- la Edge REAL en Deno ----------
const dir = mkdtempSync(join(tmpdir(), "edge_c15_"));
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-redes/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 60000); });

const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 600) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 600))); };
let peor = 0;
async function E(rol, accion, o = {}) {
  const t0 = Date.now();
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-redes?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
    headers: { ...(rol ? { Authorization: `Bearer tok-${rol}` } : {}), ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined });
  const txt = await r.text(); let c = null; try { c = JSON.parse(txt); } catch { /* */ }
  const ms = Date.now() - t0; if (r.status === 200) peor = Math.max(peor, ms);
  todo.push(txt);
  return { s: r.status, c, cache: r.headers.get("cache-control"), txt, ms };
}
const iso = (min) => new Date(Date.now() + min * 60000).toISOString();
try {
  // ===== A. Catálogo y vista previa =====
  let r = await E("dist", "evento_catalogo");
  ok("A1 evento_catalogo (GET), supervisor de distribución: 200 sin caché; puede zona y reportes, no total; trae los 2 sectores, las plantas y los 15 tipos",
    r.s === 200 && r.cache === "no-store" && r.c.puede.zona && r.c.puede.reportes && !r.c.puede.total && [S1, S2].every((s) => r.c.sectores.some((x) => x.codigo === s)) && r.c.plantas.length >= 1 && r.c.tipos.length === 15, r.txt.slice(0, 300));
  ok("A2 … al supervisor de planta: puede total; al operador y a quien no es de Técnica, 403; sin sesión, 401; por POST, 405",
    (await E("planta", "evento_catalogo")).c?.puede?.total === true && (await E("op", "evento_catalogo")).s === 403 && (await E("nada", "evento_catalogo")).s === 403
    && (await E(null, "evento_catalogo")).s === 401 && (await E("dist", "evento_catalogo", { cuerpo: {} })).s === 405);
  r = await E("dist", "evento_vista_previa", { cuerpo: { alcance: "sectores", sectores: [S1] } });
  const CONTRATOS1 = r.c?.contratos;
  ok(`A3 evento_vista_previa (POST) de un sector: 200 sin caché, ${CONTRATOS1} contratos, sensibles, reportes y la zona; no guarda nada`,
    r.s === 200 && r.cache === "no-store" && CONTRATOS1 > 1000 && typeof r.c.sensibles === "number" && r.c.reportes.total === 0 && r.c.zona_geojson.type === "MultiPolygon" && sqlq("select count(*) from redes.eventos_suspension") === "0", r.txt.slice(0, 300));
  ok("A4 … rechazos por forma (400): sin alcance, alcance desconocido, sectores vacíos o mal escritos, un dato de más, círculo sin centro; por GET, 405",
    (await E("dist", "evento_vista_previa", { cuerpo: {} })).s === 400 && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "barrio" } })).s === 400
    && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "sectores", sectores: [] } })).s === 400 && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "sectores", sectores: ["S1"] } })).s === 400
    && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "sectores", sectores: [S1], causa: "no va aquí" } })).s === 400
    && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "circulo", radio_m: 100 } })).s === 400 && (await E("dist", "evento_vista_previa")).s === 405);
  ok("A5 … el supervisor de planta no ve la vista previa de un sector (403), ni el de distribución la de un total (403)",
    (await E("planta", "evento_vista_previa", { cuerpo: { alcance: "sectores", sectores: [S1] } })).s === 403 && (await E("dist", "evento_vista_previa", { cuerpo: { alcance: "total", total: "ciudad" } })).s === 403);

  // ===== B. Declarar por sectores; la asociación automática; vigentes y detalle =====
  const antes = bot("ZT15-E001", punto(S1, 0.5, 0.5));      // llega antes de declarar
  r = await E("dist", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S1], causa: "Daño en la tubería matriz", desde: iso(-30), regreso: iso(180) } });
  const EV1 = r.c?.codigo;
  ok(`B1 evento_declarar (POST) por sectores: 200, ${EV1}, abierto, ${r.c?.contratos} contratos, la franja y el reporte del bot que ya estaba (asociado al declarar)`,
    r.s === 200 && /^EVS-[0-9]{6}$/.test(EV1) && r.c.estado === "abierto" && r.c.contratos === CONTRATOS1 && /^Sin agua en ZT15 Sector occidente desde las /.test(r.c.franja) && r.c.asociados_al_declarar === 1 && antes.evento === null, r.txt.slice(0, 400));
  ok("B2 … rechazos: sin causa o con un dato de más, 400; el operador y el supervisor de planta, 403; el de distribución un total, 403; la misma zona otra vez, 409",
    (await E("dist", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S2] } })).s === 400 && (await E("dist", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S2], causa: "ZT15 prueba", autor: "x@emdupar.gov.co" } })).s === 400
    && (await E("op", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S2], causa: "ZT15 prueba" } })).s === 403 && (await E("planta", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S2], causa: "ZT15 prueba" } })).s === 403
    && (await E("dist", "evento_declarar", { cuerpo: { alcance: "total", total: "ciudad", causa: "ZT15 prueba" } })).s === 403
    && (await E("dist", "evento_declarar", { cuerpo: { alcance: "sectores", sectores: [S1], causa: "ZT15 otra vez" } })).s === 409);
  const b2 = bot("ZT15-E002", punto(S1, 0.4, 0.6)), b3 = bot("ZT15-E003", punto(S2, 0.5, 0.5));
  ok("B3 mientras está abierto, un «sin agua» nuevo del bot dentro de la zona queda asociado y recibe el mensaje; uno fuera de la zona, no",
    b2.evento === EV1 && /^Ya sabemos del corte en tu sector\. Regreso estimado: /.test(b2.mensaje) && b3.evento === null && b3.mensaje === null, JSON.stringify([b2, b3]));
  r = await E("op", "eventos_vigentes");
  ok("B4 eventos_vigentes (GET), para el operador: 200 sin caché, 1 evento con su zona (GeoJSON) y su franja; a quien no es de Técnica, 403",
    r.s === 200 && r.cache === "no-store" && r.c.eventos.length === 1 && r.c.eventos[0].codigo === EV1 && r.c.eventos[0].zona_geojson.type === "MultiPolygon" && r.c.eventos[0].reportes.total === 2 && (await E("nada", "eventos_vigentes")).s === 403, r.txt.slice(0, 300));
  r = await E("dist", "evento", { qs: { codigo: EV1.toLowerCase() } });
  ok("B5 evento (GET; el código también en minúsculas): el detalle con 2 asociados, los sensibles y el historial; al operador, 403; código mal escrito, 400; uno que no existe, 404",
    r.s === 200 && r.c.asociados.length === 2 && Array.isArray(r.c.sensibles_lista) && Array.isArray(r.c.historial) && (await E("op", "evento", { qs: { codigo: EV1 } })).s === 403
    && (await E("dist", "evento", { qs: { codigo: "EVS-1" } })).s === 400 && (await E("dist", "evento")).s === 400 && (await E("dist", "evento", { qs: { codigo: "EVS-999999" } })).s === 404, r.txt.slice(0, 300));
  const idB2 = r.c.asociados.find((x) => x.rotulo === "Bot · ZT15-E002")?.ref;

  // ===== C. Regreso, desasociar y asociar =====
  r = await E("dist", "evento_regreso", { cuerpo: { evento: EV1, regreso: iso(300), motivo: "ZT15 el repuesto llega más tarde" } });
  ok("C1 evento_regreso (POST): 200 y vale la hora nueva; sin la hora, 400; el operador, 403",
    r.s === 200 && new Date(r.c.regreso_estimado).getTime() > Date.now() + 280 * 60000 && (await E("dist", "evento_regreso", { cuerpo: { evento: EV1 } })).s === 400 && (await E("op", "evento_regreso", { cuerpo: { evento: EV1, regreso: iso(300) } })).s === 403, r.txt.slice(0, 200));
  r = await E("dist", "evento_desasociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "ZT15 es otro problema distinto" } });
  ok("C2 evento_desasociar (POST) con motivo: 200 y queda 1 asociado; sin motivo o con el reporte mal dicho, 400; el operador, 403; uno que ya no está en el evento, 400",
    r.s === 200 && r.c.reportes.total === 1 && (await E("dist", "evento_desasociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "no" } })).s === 400
    && (await E("dist", "evento_desasociar", { cuerpo: { evento: EV1, origen: "bot", ref: "ZT15-E002", motivo: "ZT15 es otro problema distinto" } })).s === 400
    && (await E("op", "evento_desasociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "ZT15 es otro problema distinto" } })).s === 403
    && (await E("dist", "evento_desasociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "ZT15 es otro problema distinto" } })).s === 400, r.txt.slice(0, 200));
  r = await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "ZT15 sí era del mismo corte" } });
  ok("C3 evento_asociar (POST) con motivo: 200 y vuelven a ser 2; asociarlo otra vez, 400; un daño que no existe, 404",
    r.s === 200 && r.c.reportes.total === 2 && (await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "bot", ref: idB2, motivo: "ZT15 sí era del mismo corte" } })).s === 400
    && (await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "dano", ref: "DAN-999999", motivo: "ZT15 sí era del mismo corte" } })).s === 404, r.txt.slice(0, 200));

  // ===== C bis. El formato de campo de Comercial (David, 19-nov): un «sin agua» hecho desde Comercial se asocia solo, se maneja por su código y se cierra en bloque =====
  const pc = punto(S1, 0.45, 0.55);
  const idCampo = sqlq(`insert into campo.reportes (id, tipo_id, lat, lon, origen, autor) select gen_random_uuid(), t.id, ${pc.lat}, ${pc.lon}, 'campo', 'zt15.comercial@emdupar.gov.co' from campo.tipos_reporte t where t.codigo = 'sin_agua' returning id`).split("\n")[0];
  const codCampo = sqlq(`select 'REP-' || lpad(seq::text, 6, '0') from campo.reportes where id = '${idCampo}'`);
  r = await E("dist", "evento", { qs: { codigo: EV1 } });
  const filaCampo = (r.c.asociados || []).find((x) => x.origen === "campo");
  ok(`C4 FORMATO DE CAMPO: un «sin agua» hecho desde Comercial dentro de la zona queda asociado solo; el detalle lo trae con su código (${codCampo}), sin contrato ni autor`,
    r.s === 200 && r.c.reportes.campo === 1 && r.c.reportes.total === 3 && filaCampo && filaCampo.ref === codCampo && filaCampo.modo === "automatica" && filaCampo.rotulo === `Formato de campo · ${codCampo}`
    && !("contrato" in filaCampo) && !("autor" in filaCampo), r.txt.slice(0, 400));
  r = await E("dist", "evento_desasociar", { cuerpo: { evento: EV1, origen: "campo", ref: codCampo.toLowerCase(), motivo: "ZT15 ese reporte es de otra cuadra" } });
  const r2 = await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "campo", ref: codCampo, motivo: "ZT15 sí era del mismo corte" } });
  ok("C5 … evento_desasociar y evento_asociar con origen «campo» y su código: 200 (queda en 0 y vuelve a 1); un reporte de campo que no existe, 404; una referencia vacía, 400",
    r.s === 200 && r.c.reportes.campo === 0 && r2.s === 200 && r2.c.reportes.campo === 1
    && (await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "campo", ref: "REP-99999999", motivo: "ZT15 sí era del mismo corte" } })).s === 404
    && (await E("dist", "evento_asociar", { cuerpo: { evento: EV1, origen: "campo", ref: "", motivo: "ZT15 sí era del mismo corte" } })).s === 400, r.txt.slice(0, 200) + r2.txt.slice(0, 200));

  // ===== D. Los dos catálogos; el total por planta; el círculo; anular =====
  r = await E("dist", "evento_tipo_fijar", { cuerpo: { origen: "bot", codigo: "dano_red_acueducto", asocia: false, motivo: "ZT15 ese tipo sigue su flujo normal" } });
  ok("D1 evento_tipo_fijar (POST): 200 y el tipo deja de asociarse; sin motivo o sin decir si se asocia, 400; el supervisor de planta, 403",
    r.s === 200 && r.c.asocia === false && (await E("dist", "evento_tipo_fijar", { cuerpo: { origen: "bot", codigo: "dano_red_acueducto", asocia: true } })).s === 400
    && (await E("dist", "evento_tipo_fijar", { cuerpo: { origen: "bot", codigo: "dano_red_acueducto", motivo: "ZT15 ese tipo sigue su flujo normal" } })).s === 400
    && (await E("planta", "evento_tipo_fijar", { cuerpo: { origen: "bot", codigo: "dano_red_acueducto", asocia: true, motivo: "ZT15 ese tipo sigue su flujo normal" } })).s === 403, r.txt.slice(0, 200));
  const PLANTA = sqlq("select codigo from tecnica.plantas where activa order by id limit 1");
  ok("D2 una planta sin sectores asignados no se puede declarar (400 con el motivo claro)",
    await (async () => { const x = await E("planta", "evento_declarar", { cuerpo: { alcance: "total", total: "planta", planta: PLANTA, causa: "ZT15 falla de energía" } }); return x.s === 400 && /no tiene sectores asignados/.test(x.c?.error ?? ""); })());
  r = await E("dist", "planta_sectores_fijar", { cuerpo: { planta: PLANTA, sectores: [S2], motivo: "ZT15 sectores de la planta de prueba" } });
  ok("D3 planta_sectores_fijar (POST), supervisor de distribución: 200; el de planta, 403; sectores mal escritos, 400",
    r.s === 200 && r.c.sectores[0] === S2 && (await E("planta", "planta_sectores_fijar", { cuerpo: { planta: PLANTA, sectores: [S2], motivo: "ZT15 sectores de la planta de prueba" } })).s === 403
    && (await E("dist", "planta_sectores_fijar", { cuerpo: { planta: PLANTA, sectores: ["oriente"], motivo: "ZT15 sectores de la planta de prueba" } })).s === 400, r.txt.slice(0, 200));
  r = await E("planta", "evento_declarar", { cuerpo: { alcance: "total", total: "planta", planta: PLANTA, causa: "Falla de energía en la planta", regreso: iso(120) } });
  const EV2 = r.c?.codigo;
  ok(`D4 el supervisor de planta declara un TOTAL POR PLANTA (${EV2}): la zona es lo que surte la planta; el de distribución no lo cierra (403)`,
    r.s === 200 && r.c.total === "planta" && /^lo que surte la planta /.test(r.c.zona) && r.c.sectores[0] === S2 && (await E("dist", "evento_cerrar", { cuerpo: { evento: EV2, motivo: "ZT15 ya volvió el servicio" } })).s === 403, r.txt.slice(0, 300));
  r = await E("planta", "evento_cerrar", { cuerpo: { evento: EV2, motivo: "Volvió la energía y la planta bombea" } });
  ok("D5 … y lo cierra él (200, «cerrado»)", r.s === 200 && r.c.estado === "cerrado", r.txt.slice(0, 200));
  const c = punto(S2, 0.5, 0.5);
  r = await E("dist", "evento_declarar", { cuerpo: { alcance: "circulo", lat: c.lat, lon: c.lon, radio_m: 300, causa: "Fuga localizada", desde: iso(-60) } });
  const EV3 = r.c?.codigo;
  ok(`D6 evento_declarar POR CÍRCULO (${EV3}; centro y radio de 300 m): 200, guarda el círculo y asocia el «sin agua» que ya estaba en ese punto; un radio imposible, 400`,
    r.s === 200 && r.c.alcance === "circulo" && r.c.circulo.radio_m === 300 && r.c.asociados_al_declarar === 1
    && (await E("dist", "evento_declarar", { cuerpo: { alcance: "circulo", lat: c.lat, lon: c.lon, radio_m: 2, causa: "ZT15 radio muy corto" } })).s === 400, r.txt.slice(0, 300));
  r = await E("dist", "evento_anular", { cuerpo: { evento: EV3, motivo: "ZT15 se declaró por error" } });
  ok("D7 evento_anular (POST) con motivo: 200, «anulado», libera su reporte; sin motivo, 400; anularlo otra vez, 409",
    r.s === 200 && r.c.estado === "anulado" && r.c.reportes_liberados === 1 && (await E("dist", "evento_anular", { cuerpo: { evento: EV1 } })).s === 400
    && (await E("dist", "evento_anular", { cuerpo: { evento: EV3, motivo: "ZT15 se declaró por error" } })).s === 409, r.txt.slice(0, 200));
  r = await E("adm", "evento_declarar", { cuerpo: { alcance: "total", total: "ciudad", causa: "Falla en la captación" } });
  const EV4 = r.c?.codigo;
  ok(`D8 el administrador declara TODA LA CIUDAD (${EV4}): sin geometría y con todos los contratos; lo anula`,
    r.s === 200 && r.c.total === "ciudad" && r.c.zona_geojson === null && r.c.contratos === Number(sqlq("select count(*) from redes.contrato_tramo"))
    && (await E("adm", "evento_anular", { cuerpo: { evento: EV4, motivo: "ZT15 fin de la prueba del total" } })).s === 200, r.txt.slice(0, 200));

  // ===== E. La lista y el cierre en bloque =====
  r = await E("dist", "eventos", { qs: { estado: "todos" } });
  ok("E1 eventos (GET): los 4, los últimos primero; por omisión, solo los abiertos (1); un estado desconocido, 400; al operador, 403",
    r.s === 200 && r.c.eventos.length === 4 && r.c.eventos[0].codigo === EV4 && (await E("dist", "eventos")).c.eventos.length === 1 && (await E("dist", "eventos", { qs: { estado: "viejos" } })).s === 400 && (await E("op", "eventos")).s === 403, r.txt.slice(0, 200));
  r = await E("dist", "evento_cerrar", { cuerpo: { evento: EV1, motivo: "Tubería reparada y servicio restablecido" } });
  ok("E2 evento_cerrar (POST), «dar de alta»: 200, «cerrado», cierra en bloque los 2 reportes del bot y el del formato de campo (quedan «Atendido» con el motivo); sin motivo, 400; cerrarlo otra vez, 409",
    r.s === 200 && r.c.estado === "cerrado" && r.c.cerrados.bot === 2 && r.c.cerrados.campo === 1 && sqlq(`select estado from campo.v_reportes_estado where id = '${idCampo}'`) === "atendido" && sqlq("select count(*) from redes.v_reporte_externo where radicado in ('ZT15-E001', 'ZT15-E002') and estado_bot = 'atendido'") === "2"
    && (await E("dist", "evento_cerrar", { cuerpo: { evento: EV1 } })).s === 400 && (await E("dist", "evento_cerrar", { cuerpo: { evento: EV1, motivo: "Tubería reparada y servicio restablecido" } })).s === 409, r.txt.slice(0, 300));
  ok("E3 al final no queda ningún evento abierto (eventos_vigentes vacío)", (await E("op", "eventos_vigentes")).c.eventos.length === 0);
  ok(`Z1 la respuesta más lenta de la Edge con la red real: ${peor} ms (cada una incluye abrir la conexión a la base)`, peor < 3000);
  ok("Z2 ninguna respuesta trae nombres, teléfonos, direcciones ni correos", !todo.some((t) => /suscriptor|tel[eé]fono|direcci[oó]n|@emdupar/i.test(t)));
  ok("Z3 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false, det: String(e) }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_edge15`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
