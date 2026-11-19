// Prueba de la RUTA levantar_mios («Mis reportes») de punta a punta, sin pantallas (son del Code B): peticiones HTTP a la Edge geoportal-redes REAL corriendo
// en Deno, cuyas RPC van a la base local de CODE A (localhost:55432: producción al 19-nov + este paquete; se copia a <plantilla>_edgemios) con el rol de la
// API (service_role) y los topes de producción (30 s y 8 s). Auth y PostgREST son simulados (el segundo pasa cada RPC a la base real).
// Perfiles sintéticos: dos operadores con el formulario, uno sin él, Comercial, el supervisor de distribución y alguien sin permiso. Los puntos se reportan
// con las RPC publicadas; el cambio de estado va por la ruta levantar_evento, como lo hace el supervisor.
// Puertos de Code A: 54987 (Auth y PostgREST simulados) y 54988 (Edge).
// Uso: node scripts/prueba_edge_levantar_mios.mjs <deno> <supabase/functions> <psql> <plantilla con el paquete, p. ej. redes_local>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_edge_levantar_mios.mjs <deno> <supabase/functions> <psql> <base plantilla con «Mis reportes», p. ej. redes_local>"); process.exit(2); }
const P_BASE = 54987, P_EDGE = 54988;      // puertos de Code A
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_edgemios`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : Array.isArray(v) && v.every((x) => typeof x === "string") ? `array[${v.map((x) => `'${x.replace(/'/g, "''")}'`).join(", ")}]::text[]`
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { adm: "ztm.admin@emdupar.gov.co", dist: "ztm.dist@emdupar.gov.co", op: "ztm.oper@emdupar.gov.co", op2: "ztm.oper2@emdupar.gov.co", op3: "ztm.sinform@emdupar.gov.co", campo: "ztm.campo@emdupar.gov.co", nada: "ztm.nada@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_edgemios`, "-c", `create database ${PLANTILLA}_edgemios template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select coalesce(to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)')::text, '')") === "") { console.error(`La plantilla ${PLANTILLA} no tiene «Mis reportes» (sh rehacer_base.sh con_mios)`); process.exit(2); }
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('${EMAILS.adm}', 'ZTM Administrador', 'admin', 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values ('${EMAILS.nada}', 'ZTM Sin permiso', 'consulta', true, 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('${EMAILS.dist}', 'ZTM Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('${EMAILS.op}', 'ZTM Operador uno', 'consulta', true, 'sin_restriccion', 'todos'), ('${EMAILS.op2}', 'ZTM Operador dos', 'consulta', true, 'sin_restriccion', 'todos'), ('${EMAILS.op3}', 'ZTM Operador sin formulario', 'consulta', true, 'sin_restriccion', 'todos')`);
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('${EMAILS.campo}', 'ZTM Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos')`);
for (const e of [EMAILS.op, EMAILS.op2]) sqlq(`select public.geoportal_redes_personal_formulario('${EMAILS.dist}', '${e}', 'activo_campo', true, 'ZTM sale a campo a levantar activos', '127.0.0.1')`);
// un punto por levantar con las RPC publicadas (preparar, «subir» la foto y crear), en un rincón de la caja lejos de la red; devuelve su código
let nPunto = 0;
function reportar(rol, servicio = "acueducto", tipo = "valvula") {
  const prep = JSON.parse(sqlq(`select public.geoportal_redes_levantar_preparar('${EMAILS[rol]}', 1)`));
  sqlq(`insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '${prep.fotos[0].ruta}', '{"size": 200000, "mimetype": "image/jpeg"}')`);
  nPunto++;
  return JSON.parse(sqlq(`select public.geoportal_redes_levantar_crear('${EMAILS[rol]}', '${prep.punto_id}', ${lit({ servicio, tipo, lat: 10.139, lon: Number((-73.58 + nPunto * 0.001).toFixed(6)), precision_m: 5, fotos: prep.fotos })}, '127.0.0.1')`)).codigo;
}

// ---------- Auth y PostgREST simulados; cada RPC va a la base local REAL como la llama la Edge ----------
const desconocidas = [], todo = [], mios = [];
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
const dir = mkdtempSync(join(tmpdir(), "edge_mios_"));
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
  todo.push(txt); if (accion === "levantar_mios" && r.status === 200) mios.push(txt);
  return { s: r.status, c, cache: r.headers.get("cache-control"), txt, ms };
}
try {
  // ===== A. Sin reportes, y quién entra =====
  let r = await E("op", "levantar_mios", { qs: { dias: "30" } });
  ok("A1 sin reportes: 200, {dias: 30, total: 0, recortada: false, items: []} y sin caché", r.s === 200 && r.c.dias === 30 && r.c.total === 0 && r.c.recortada === false && Array.isArray(r.c.items) && r.c.items.length === 0 && Object.keys(r.c).sort().join() === "dias,items,recortada,total" && r.cache === "no-store", r.txt);
  ok("A2 sin sesión: 401", (await E(null, "levantar_mios")).s === 401);
  r = await E("op3", "levantar_mios");
  ok("A3 el operador sin el formulario: 403 (como en «Encontrar»)", r.s === 403, r.txt);
  ok("A4 quien no es de Técnica ni tiene Formularios de campo: 403", (await E("nada", "levantar_mios")).s === 403);
  r = await E("op", "levantar_mios", { qs: { dias: "7" } });
  ok("A5 un periodo que no existe: 400 con su texto; por POST: 405", r.s === 400 && /30 días, de 90 días o todos/.test(r.c?.error ?? "") && (await E("op", "levantar_mios", { metodo: "POST", cuerpo: {} })).s === 405, r.txt);

  // ===== B. Solo lo propio, los últimos primero =====
  const L1 = reportar("op"), L2 = reportar("op", "alcantarillado", "pozo"), O1 = reportar("op2"), C1 = reportar("campo"), L3 = reportar("op", "acueducto", "hidrante");
  r = await E("op", "levantar_mios", { qs: { dias: "30" } });
  ok("B1 el operador ve sus 3 reportes, los últimos primero, y ninguno ajeno", r.s === 200 && r.c.total === 3 && r.c.items.map((i) => i.codigo).join() === [L3, L2, L1].join() && r.cache === "no-store", r.txt);
  ok("B2 cada uno trae las 9 claves del contrato del Code B, y nada más (ni correos ni nombres)", r.c.items.every((i) => Object.keys(i).sort().join() === "activo,codigo,estado,estado_desde,estado_nombre,registrado_en,servicio,tipo,tipo_nombre") && !/@|ZTM/.test(r.txt), r.txt);
  ok("B3 recién reportado: «Reportado», con el nombre del tipo y sin activo", r.c.items[1].estado === "reportado" && r.c.items[1].estado_nombre === "Reportado" && r.c.items[1].servicio === "alcantarillado" && r.c.items[1].tipo === "pozo" && !!r.c.items[1].tipo_nombre && r.c.items[1].activo === null
     && !Number.isNaN(Date.parse(r.c.items[1].registrado_en)) && r.c.items[1].estado_desde === r.c.items[1].registrado_en, JSON.stringify(r.c.items[1]));
  const r2 = await E("op2", "levantar_mios"), r3 = await E("campo", "levantar_mios", { qs: { dias: "0" } }), r4 = await E("dist", "levantar_mios", { qs: { dias: "90" } });
  ok("B4 el otro operador ve solo el suyo, Comercial solo el suyo (con 0 = todos) y el supervisor, que no ha reportado, ninguno", r2.c.items.map((i) => i.codigo).join() === O1 && r2.c.dias === 30 && r3.c.items.map((i) => i.codigo).join() === C1 && r3.c.dias === 0 && r4.s === 200 && r4.c.total === 0 && r4.c.dias === 90, r2.txt + r3.txt + r4.txt);
  r = await E("op", "levantar_mios", { qs: { dias: "30", solicitante: EMAILS.op2, email: EMAILS.op2, autor: EMAILS.op2 } });
  ok("B5 pedir los de otra persona por la URL no sirve: salen los propios", r.s === 200 && r.c.items.map((i) => i.codigo).join() === [L3, L2, L1].join(), r.txt);
  ok("B6 la bandeja del supervisor (levantar_lista) sigue cerrada para el operador: 403; al supervisor le trae los 5", (await E("op", "levantar_lista")).s === 403 && (await E("dist", "levantar_lista", { qs: { estado: "todos" } })).c.items.length === 5);

  // ===== C. El estado cambia cuando el supervisor lo cambia (por su ruta de siempre) =====
  r = await E("dist", "levantar_evento", { cuerpo: { codigo: L1, tipo: "asignado" } });
  const rd = await E("dist", "levantar_evento", { cuerpo: { codigo: L2, tipo: "descartado", motivo: "ZTM repetido de otro reporte" } });
  ok("C1 el supervisor asigna uno y descarta otro por levantar_evento", r.s === 200 && rd.s === 200, r.txt + rd.txt);
  r = await E("op", "levantar_mios");
  const de = (c) => r.c.items.find((i) => i.codigo === c);
  ok("C2 «Mis reportes» lo refleja: «Asignado a levantamiento» y «Descartado», sin el motivo ni quién lo hizo; el tercero sigue «Reportado»", r.s === 200 && de(L1).estado === "asignado" && de(L1).estado_nombre === "Asignado a levantamiento" && Date.parse(de(L1).estado_desde) > Date.parse(de(L1).registrado_en)
     && de(L2).estado === "descartado" && de(L2).estado_nombre === "Descartado" && de(L3).estado === "reportado" && !/repetido|@|ZTM/.test(r.txt), r.txt);
  ok("C3 el operador no puede cambiar el estado de su propio reporte (levantar_evento: 403)", (await E("op", "levantar_evento", { cuerpo: { codigo: L3, tipo: "asignado" } })).s === 403);

  // ===== D. Periodos y recorte con volumen =====
  sqlq(`insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
        select gen_random_uuid(), 'LEV-97' || lpad(i::text, 4, '0'), 'acueducto', 'valvula', 10.14, round((-73.58 + i * 0.00001)::numeric, 6), ST_SetSRID(ST_MakePoint(-73.58 + i * 0.00001, 10.14), 4326), 5, false, 'tecnica', '${EMAILS.op}',
               clock_timestamp() - make_interval(days => case when i <= 20 then 40 when i <= 30 then 120 else 2 end, mins => i) from generate_series(1, 620) i`);
  sqlq(`insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
        select gen_random_uuid(), 'LEV-' || lpad((700000 + i)::text, 6, '0'), 'acueducto', 'valvula', 10.15, round((-73.58 + (i % 4000) * 0.00001)::numeric, 6), ST_SetSRID(ST_MakePoint(-73.58 + (i % 4000) * 0.00001, 10.15), 4326), 5, false, 'tecnica',
               'ztm.relleno' || (i % 200) || '@emdupar.gov.co', clock_timestamp() - make_interval(mins => i) from generate_series(1, 20000) i`);
  sqlq("analyze redes.levantar_puntos");
  const a30 = await E("op", "levantar_mios", { qs: { dias: "30" } }), a90 = await E("op", "levantar_mios", { qs: { dias: "90" } }), a0 = await E("op", "levantar_mios", { qs: { dias: "0" } });
  ok("D1 30 días: 593 (3 + 590); 90 días: 613 (entran los 20 de hace 40 días); todos: 623 (los 10 de hace 120 días)", a30.c.total === 593 && a90.c.total === 613 && a0.c.total === 623, `${a30.c.total} ${a90.c.total} ${a0.c.total}`);
  ok("D2 con más de 500: «recortada» y 500 en la respuesta, los más nuevos primero (el primero es el último reportado)", [a30, a90, a0].every((x) => x.c.recortada === true && x.c.items.length === 500 && x.c.items[0].codigo === L3)
     && a0.c.items.every((x, i, l) => i === 0 || Date.parse(l[i - 1].registrado_en) >= Date.parse(x.registrado_en)));
  const aud0 = sqlq("select count(*) from public.geoportal_auditoria");
  // El simulador lanza un psql por cada RPC (unos 100 ms fijos), así que el tiempo de la ruta se compara con el de la lectura mínima (alguien con 1 reporte):
  // lo que cuesta de más leer 623 reportes propios entre 20.000 debe quedar bajo el tope local (1 s / 6). El tiempo de la base sola lo mide el ensayo SQL.
  const mediana = (l) => [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)];
  const tiempos = [], base = [];
  for (let i = 0; i < 10; i++) { tiempos.push((await E("op", "levantar_mios", { qs: { dias: "0" } })).ms); base.push((await E("campo", "levantar_mios")).ms); }
  console.log(`   TIEMPOS por la Edge (con ${sqlq("select count(*) from redes.levantar_puntos")} puntos en la tabla), diez veces cada una: mis 623 → mediana ${mediana(tiempos)} ms, la más lenta ${Math.max(...tiempos)} ms · alguien con 1 reporte → mediana ${mediana(base)} ms`);
  ok(`D3 TIEMPOS: leer 623 reportes propios cuesta ${mediana(tiempos) - mediana(base)} ms más que leer 1 (medianas de diez; tope local 167 ms = 1 s / 6) y ninguna pasa de 1 s`, mediana(tiempos) - mediana(base) < 167 && Math.max(...tiempos) < 1000);
  ok("D4 leer no deja auditoría", sqlq("select count(*) from public.geoportal_auditoria") === aud0);
  ok(`Z1 ninguna de las ${mios.length} respuestas de levantar_mios trae un correo ni el nombre de una persona`, mios.length > 15 && !mios.some((t) => /@|ZTM/.test(t)));
  ok("Z3 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false, det: String(e) }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_edgemios`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
