// Prueba de las RUTAS del corte de EVENTOS (origen obligatorio y sectores por tubo de salida) de punta a punta, sin pantallas (son del Code B): peticiones HTTP
// a las dos Edges REALES corriendo en Deno, cuyas RPC van a la base local de CODE A (localhost:55432: producción al 20-nov 21:08 + este corte; se copia a
// <plantilla>_edgerep) con el rol de la API (service_role) y los topes de producción (30 s y 8 s). Auth y PostgREST son simulados (PostgREST pasa cada RPC a
// la base real). Datos SIMULADOS (prefijo ZTEDGE): 2 tubos, 2 sectores, un tramo y un contrato de prueba; cada comprobación mira solo sus filas.
// Perfiles como los de las sondas: administrador (A), supervisor de planta (S), supervisor de distribución (Y), operador (O), Comercial + operador (D) y
// alguien sin módulo de Técnica (N). Puertos de Code A: 54993 (Auth, PostgREST y Storage) y 54994 (Edges).
// Uso: node scripts/prueba_edge_eventos_origen_tubos.mjs <deno> <supabase/functions> <psql> <plantilla con los dos paquetes, p. ej. redes_local>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

// Pasada de herramientas (20-nov): -h/--help imprime el uso y sale ANTES de tocar ninguna base; una opción desconocida es error. Es local (no consulta Supabase).
const USO = "Uso: node scripts/prueba_edge_eventos_origen_tubos.mjs <deno> <supabase/functions> <psql> <plantilla con los dos paquetes, p. ej. redes_local>   (-h, --help: este uso; base local de Code A, PGPORT_A=55432)";
for (const a of process.argv.slice(2)) {
  if (a === "-h" || a === "--help") { console.log(USO); process.exit(0); }
  if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
}
if (process.argv.length > 6) { console.error(`Sobran argumentos.\n${USO}`); process.exit(2); }
const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_edge_reportes.mjs <deno> <supabase/functions> <psql> <base plantilla con los dos paquetes>"); process.exit(2); }
const P_BASE = 54993, P_EDGE = 54994;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_edgerep`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
// una lista de textos va como text[] (como la convierte PostgREST para un parámetro text[]); un objeto, como jsonb
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v)
  : Array.isArray(v) && v.every((x) => typeof x === "string") && !(v.length === 0 && false) ? `array[${v.map((x) => `'${x.replace(/'/g, "''")}'`).join(", ")}]::text[]`
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { A: "ztedge.admin@emdupar.gov.co", S: "ztedge.sp@emdupar.gov.co", Y: "ztedge.sd@emdupar.gov.co", O: "ztedge.op@emdupar.gov.co", D: "ztedge.comercial@emdupar.gov.co", N: "ztedge.nada@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_edgerep`, "-c", `create database ${PLANTILLA}_edgerep template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select coalesce(to_regprocedure('public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text)')::text, '')") === "") {
  console.error(`La plantilla ${PLANTILLA} no tiene el corte de eventos (sh sql/redes_eventos_origen_tubos/pruebas_locales/rehacer_base.sh con_evt)`); process.exit(2);
}
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZTEDGE Admin", []); lb(EMAILS.S, "ZTEDGE Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]); lb(EMAILS.Y, "ZTEDGE Supervisor de distribución", ["ver_registro_tecnico", "ver_dashboard_redes"]);
lb(EMAILS.O, "ZTEDGE Operador", ["ver_registro_tecnico"]); lb(EMAILS.D, "ZTEDGE Comercial", ["ver_comercial", "ver_registro_tecnico"]); lb(EMAILS.N, "ZTEDGE Sin módulo", ["ver_explorar"]);
// datos simulados: 2 tubos de salida, 2 sectores en un rincón de la caja, un tramo dentro del primero y un contrato de prueba
sqlq(`do $$ declare v_pl bigint; v_c bigint; v_id bigint; v_cod text; i integer; q text := '${EMAILS.A}'; begin
  insert into tecnica.plantas (codigo, nombre) values ('ztedge_pl', 'ZTEDGE Planta') returning id into v_pl;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id) values ('ZTEDGE-T1', 'ZTEDGE Distrito Uno', 'distribucion', v_pl), ('ZTEDGE-T2', 'ZTEDGE Distrito Dos', 'distribucion', v_pl);
  for i in 1..2 loop
    update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_c; v_cod := 'SEC-' || lpad(v_c::text, 6, '0');
    insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'SEC', 'carga', q) returning id into v_id;
    insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
    values (v_id, 1, ST_Multi(ST_MakeEnvelope(-73.58 + 0.003 * (i - 1), 10.13, -73.58 + 0.003 * i, 10.133, 4326)), 'ZTEDGE Sector ' || i, 'sector', 'en_operacion', '{}', md5(v_cod), q);
    insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEDGE', q);
    perform redes.f_mat_refrescar_uno(v_id);
  end loop;
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'RED' returning ultimo into v_c; v_cod := 'RED-' || lpad(v_c::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'RED', 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, ST_MakeLine(ST_SetSRID(ST_MakePoint(-73.5795, 10.131), 4326), ST_SetSRID(ST_MakePoint(-73.5785, 10.131), 4326)), 'ZTEDGE tramo',
          (select codigo from redes.materiales order by orden limit 1), 110, 'en_operacion', '{}', md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEDGE', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo) values ('999999992001', v_id, 2, 'cercania');
end $$`);
const SEC1 = sqlq("select codigo from redes.activo_vigente_mat where prefijo = 'SEC' and nombre = 'ZTEDGE Sector 1'"), SEC2 = sqlq("select codigo from redes.activo_vigente_mat where prefijo = 'SEC' and nombre = 'ZTEDGE Sector 2'");
const hoy = sqlq("select (clock_timestamp() at time zone 'America/Bogota')::date");

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
let b;
try {
  // ===== A. Quién ajusta tubos y causales (las sondas propuestas) =====
  const pt = [], nt = [], pc = [], nc = [];
  for (const p of ["A", "Y", "S", "O", "D", "N"]) {
    const a = await E(p, R, "tubo_sectores_fijar", { cuerpo: { tubo: "ZTEDGE-T1", sectores: [SEC1], motivo: `ZTEDGE el tubo uno abastece el sector uno (${p})` } }); (a.s === 200 ? pt : nt).push(p + (a.s === 200 || a.s === 403 ? "" : `(${a.s})`));
    const b = await E(p, R, "evento_causal_fijar", { cuerpo: { codigo: "otra", activa: true, motivo: `ZTEDGE se deja activa la causal (${p})` } }); (b.s === 200 ? pc : nc).push(p + (b.s === 200 || b.s === 403 ? "" : `(${b.s})`));
  }
  ok("A1 tubo_sectores_fijar: permiten A e Y; S, O, D y N reciben 403", pt.join() === "A,Y" && nt.join() === "S,O,D,N", `permiten ${pt} · niegan ${nt}`);
  ok("A2 evento_causal_fijar: permiten A e Y; S, O, D y N reciben 403", pc.join() === "A,Y" && nc.join() === "S,O,D,N", `permiten ${pc} · niegan ${nc}`);
  ok("A3 sin sesión: 401", (await E(null, R, "tubo_sectores_fijar", { cuerpo: { tubo: "ZTEDGE-T1", sectores: [], motivo: "ZTEDGE sin sesión" } })).s === 401);

  // ===== B. Catálogo y tubos =====
  let r = await E("Y", R, "tubo_sectores_fijar", { cuerpo: { tubo: "ztedge-t2", sectores: [SEC2.toLowerCase()], motivo: "ZTEDGE el tubo dos abastece el sector dos" } });
  ok("B1 fijar el tubo 2 (código y sectores en minúsculas valen): devuelve el tubo, su nombre y sus sectores", r.s === 200 && r.c.tubo === "ZTEDGE-T2" && r.c.nombre === "ZTEDGE Distrito Dos" && JSON.stringify(r.c.sectores) === JSON.stringify([SEC2]), r.txt);
  r = await E("Y", R, "evento_catalogo");
  const t1 = r.c?.tubos?.find((t) => t.codigo === "ZTEDGE-T1");
  ok("B2 el catálogo trae causales (con las 5 de David) y tubos con nombre, planta y sectores; los sectores por planta, vacíos",
    r.s === 200 && ["trabajo_programado", "parametros_entrada", "falla_planta", "mantenimiento_planta", "otra"].every((c) => r.c.causales.some((x) => x.codigo === c && x.activa))
    && t1?.nombre === "ZTEDGE Distrito Uno" && t1?.planta === "ZTEDGE Planta" && JSON.stringify(t1?.sectores) === JSON.stringify([SEC1]) && r.c.plantas.every((p) => p.sectores.length === 0), r.txt.slice(0, 400));
  r = await E("Y", R, "planta_sectores_fijar", { cuerpo: { planta: "ztedge_pl", sectores: [SEC1], motivo: "ZTEDGE ya no se puede por planta" } });
  ok("B3 planta_sectores_fijar: 400 «Los sectores ya no se asignan por planta…»", r.s === 400 && /ya no se asignan por planta/.test(r.c?.error ?? ""), r.txt);

  // ===== C. Declarar por tubo, con origen =====
  r = await E("Y", R, "evento_declarar", { cuerpo: { alcance: "tubos", tubos: ["ZTEDGE-T1"], causa: "ZTEDGE observación de prueba" } });
  ok("C1 sin origen: 400 «Indique el origen…» (lo dice la base)", r.s === 400 && r.c?.error === "Indique el origen: el daño o la intervención, o la causal del trabajo.", r.txt);
  r = await E("Y", R, "evento_vista_previa", { cuerpo: { alcance: "tubos", tubos: ["ZTEDGE-T1", "ZTEDGE-T2"] } });
  ok("C2 vista previa por los dos tubos: alcance «sectores», con zona y conteos", r.s === 200 && r.c.alcance === "sectores" && r.c.zona_geojson && typeof r.c.contratos === "number", r.txt.slice(0, 300));
  r = await E("Y", R, "evento_declarar", { cuerpo: { alcance: "tubos", tubos: ["ZTEDGE-T1", "ZTEDGE-T2"], causal: "trabajo_programado", causa: "ZTEDGE Pedro Prueba 3009990000 trabajo en la red" } });
  const ev = r.c?.codigo;
  ok("C3 declarar por dos tubos: queda por sectores (2), con los dos tubos {codigo, nombre}, origen Trabajo y causal «Trabajo programado en redes»",
    r.s === 200 && r.c.alcance === "sectores" && r.c.sectores.length === 2 && JSON.stringify(r.c.tubos) === JSON.stringify([{ codigo: "ZTEDGE-T1", nombre: "ZTEDGE Distrito Uno" }, { codigo: "ZTEDGE-T2", nombre: "ZTEDGE Distrito Dos" }])
    && r.c.origen?.codigo === "trabajo" && r.c.causal?.nombre === "Trabajo programado en redes", r.txt.slice(0, 500));
  r = await E("Y", R, "evento", { qs: { codigo: ev } });
  ok("C4 el detalle trae lo mismo", r.s === 200 && r.c.tubos?.length === 2 && r.c.origen?.nombre === "Trabajo", r.txt.slice(0, 300));
  r = await E("A", R, "evento_contrato", { qs: { contrato: "999999992001" } });
  ok("C5 evento_contrato: el contrato de prueba está en el evento por tubo, zona «sectores» (la forma de la respuesta no cambia)",
    r.s === 200 && r.c.en_evento === true && r.c.evento?.codigo === ev && r.c.evento?.zona === "sectores" && Object.keys(r.c).sort().join() === "consultado_en,contrato,en_evento,evento,otros_eventos,ubicado", r.txt);

  // ===== D. La descarga de eventos =====
  b = await bajar("Y", R, { reporte: "eventos", desde: hoy, hasta: hoy, formato: "csv", sector: SEC1 });
  const fila = b.filas.find((f) => f.evento === ev);
  ok("D1 Distribución · Eventos (por el sector de prueba): «Por tubo», los tubos, origen y causal; la observación no sale",
    b.i.s === 200 && fila?.alcance === "Por tubo" && fila?.tubos === "ZTEDGE-T1, ZTEDGE-T2" && fila?.origen === "Trabajo" && fila?.causal === "Trabajo programado en redes"
    && !b.i.txt.includes("Pedro") && !JSON.stringify(b.filas).includes("Pedro"), JSON.stringify(fila));

  // ===== Z. Lo que no debe salir =====
  // (el detalle del evento trae «declarado_por» con el nombre del FUNCIONARIO, como desde el Corte 15; aquí se revisan las descargas y los ajustes)
  ok("Z1 las descargas y las respuestas de los ajustes no traen nombres de personas ni teléfonos (la observación tampoco sale en la descarga)",
    !JSON.stringify(b).match(/ZTEDGE (Admin|Supervisor|Operador|Comercial|Sin)|\b3\d{9}\b|Pedro/) && !todo.filter((t) => /"tubo"|"activa"/.test(t)).some((t) => /ZTEDGE (Admin|Supervisor|Operador)|\b3\d{9}\b/.test(t)));
  ok("Z2 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_edgerep`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
