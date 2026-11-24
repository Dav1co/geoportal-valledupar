// Prueba de la Edge NUEVA geoportal-reparto de punta a punta, sin pantallas (van en el commit 3): peticiones HTTP a la Edge REAL corriendo en Deno, cuyas
// RPC van a una base local de CODE A (clúster 55432) con el paquete reparto_1 aplicado, como service_role y con los topes de producción (30 s y 8 s).
// Auth y PostgREST son simulados (el segundo pasa cada RPC a la base real; geoportal_estado_acceso es la real). La base la crea ESTA corrida
// (reparto_edge_<pid>, copia de la plantilla) y la borra al final; si ya existe, se niega.
// Perfiles sintéticos (ztrep.*): administrador, dos repartidores (actividad reparto), el supervisor de reparto (supervision_reparto), el mismo con
// dashboard_campo, el supervisor del SCRR (solo dashboard_campo), alguien de campo sin actividad, alguien sin campo e inactivo.
// Puertos de Code A: 55001 (Auth y PostgREST simulados) y 55002 (Edge).
// Uso: node scripts/prueba_edge_reparto.mjs <deno> <supabase/functions> <psql> <plantilla> <migración _editor>      (-h: este uso)
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import http from "node:http";

const USO = "Uso: node scripts/prueba_edge_reparto.mjs <deno> <supabase/functions> <psql> <plantilla> <migración _editor>";
const args = process.argv.slice(2);
for (const a of args) { if (a === "-h" || a === "--help") { console.log(USO); process.exit(0); } if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); } }
const [DENO, FUNCIONES, PSQL, PLANTILLA, MIGRACION] = args;
if (!MIGRACION || args.length !== 5) { console.error(USO); process.exit(2); }
const P_BASE = 55001, P_EDGE = 55002;
const DB = `reparto_edge_${process.pid}`;
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: "55432", PGUSER: "postgres", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
for (const k of ["SUPABASE_RO_URL", "DATABASE_URL", "PGPASSWORD", "PGSERVICE"]) delete PGENV[k];   // nunca otra base que la local
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 << 20 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" || typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const pg = (base, ...a) => execFileSync(PSQL, ["-qX", "-v", "ON_ERROR_STOP=1", "-d", base, ...a], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });

// ---------- base propia de esta corrida ----------
if (execFileSync(PSQL, ["-AtqX", "-d", "postgres", "-c", `select count(*) from pg_database where datname = '${DB}'`], { env: PGENV, encoding: "utf8" }).trim() !== "0") {
  console.error(`La base ${DB} ya existe (resto de otra corrida): este guion no la borra.`); process.exit(2);
}
pg("postgres", "-c", `create database ${DB} template ${PLANTILLA}`);
let creada = true;
const borrarMia = () => { if (creada) { try { pg("postgres", "-c", `drop database if exists ${DB}`); creada = false; } catch { /* queda para mirarla */ } } };
pg(DB, "-f", resolve(MIGRACION));

const E_ = { adm: "ztrep.adm@emdupar.gov.co", rep1: "ztrep.rep1@emdupar.gov.co", rep2: "ztrep.rep2@emdupar.gov.co", sup: "ztrep.sup@emdupar.gov.co",
  supcal: "ztrep.supcal@emdupar.gov.co", scrr: "ztrep.scrr@emdupar.gov.co", campo: "ztrep.campo@emdupar.gov.co", nada: "ztrep.nada@emdupar.gov.co", inactivo: "ztrep.inactivo@emdupar.gov.co" };
const lb = (email, nombre, rol, campo, dash, activo = true, comercial = false) =>
  `('${email}', '${nombre}', '${rol}', ${activo}, 'sin_restriccion', 'todos', false, ${campo}, ${dash}, false, false, false, ${comercial})`;
sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico, ver_comercial) values
  ${[lb(E_.adm, "ZTREP Admin", "admin", false, false), lb(E_.rep1, "ZTREP Repartidor uno", "consulta", true, false), lb(E_.rep2, "ZTREP Repartidor dos", "consulta", true, false),
     lb(E_.sup, "ZTREP Supervisor de reparto", "consulta", true, false), lb(E_.supcal, "ZTREP Supervisor de reparto y campo", "consulta", true, true),
     lb(E_.scrr, "ZTREP Supervisor del SCRR", "consulta", true, true), lb(E_.campo, "ZTREP Campo sin reparto", "consulta", true, false),
     lb(E_.nada, "ZTREP Solo comercial", "consulta", false, false, true, true), lb(E_.inactivo, "ZTREP Inactivo", "consulta", true, false, false)].join(",\n  ")}`);
sqlq(`insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values
  ('${E_.rep1}', 'asignar_actividad', 'reparto', '${E_.adm}'), ('${E_.rep2}', 'asignar_actividad', 'reparto', '${E_.adm}'), ('${E_.inactivo}', 'asignar_actividad', 'reparto', '${E_.adm}'),
  ('${E_.sup}', 'asignar_actividad', 'supervision_reparto', '${E_.adm}'), ('${E_.supcal}', 'asignar_actividad', 'supervision_reparto', '${E_.adm}')`);
const PER = sqlq("select max(periodo) from hechos.rutas_consecutivos");
sqlq(`insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo) values
  ('98', '1000000', '880101', '880000000101', 'ZTREP CALLE', '1', '${PER}'), ('98', '2000000', '880101', '880000000102', 'ZTREP CALLE', '2', '${PER}'),
  ('98', '3000000', '880101', '880000000103', 'ZTREP CALLE', '3', '${PER}'), ('98', '4000000', '880101', '880000000104', 'ZTREP CALLE', '4', '${PER}'),
  ('98', '5000000', '880101', '880000000105', 'ZTREP CALLE', '5', '${PER}'), ('97', '1000000', '970101', '880000000501', 'ZTREP CALLE', '1', '${PER}')`);
sqlq(`insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor)
  select to_char(h, 'YYYYMM'), 98, h + 10, h + 15, jsonb_build_object('reparto', (h - 1)::text), '${E_.adm}' from (select (now() at time zone 'America/Bogota')::date as h) x`);
sqlq("analyze hechos.rutas_consecutivos");

// ---------- Auth y PostgREST simulados ----------
const desconocidas = [];
function rpcBase(fn, a) {
  const argumentos = Object.entries(a).map(([k, val]) => `${k} => ${lit(val)}`).join(", ");
  try {
    const t = execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", "set role service_role", "-c", "set statement_timeout = '30s'", "-c", "set lock_timeout = '8s'",
      "-c", `select to_jsonb(public.${fn}(${argumentos}))`], { env: PGENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 << 20 }).trim();
    return { status: 200, cuerpo: t === "" ? null : JSON.parse(t) };
  } catch (e) {
    const t = String(e.stderr || "");
    return { status: 400, cuerpo: { code: (t.match(/ERROR:\s+([0-9A-Z]{5}):/) || [])[1] || "XX000", message: ((t.match(/ERROR:\s+[0-9A-Z]{5}:\s+(.*)/) || [])[1] || "").trim(),
      hint: /HINT:\s+msg_usuario/.test(t) ? "msg_usuario" : undefined } };
  }
}
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const tok = (req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (u.pathname === "/auth/v1/user") { const rol = tok.replace(/^tok-/, ""); return E_[rol] ? json(200, { id: "u-" + rol, email: E_[rol] }) : json(401, {}); }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice(13), a = JSON.parse(Buffer.concat(trozos).toString() || "{}");
      if (fn === "geoportal_log") return json(200, null);
      if (sqlq(`select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = ${lit(fn)}`) === "0") { desconocidas.push(fn); return json(404, { code: "PGRST202", message: "no existe" }); }
      const r = rpcBase(fn, a); return json(r.status, r.cuerpo);
    }
    json(404, {});
  });
});
await new Promise((r) => srv.listen(P_BASE, "127.0.0.1", r));

// ---------- la Edge REAL en Deno ----------
const dir = mkdtempSync(join(tmpdir(), "edge_reparto_"));
const servir = join(dir, "servir_edges.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-reparto/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edges listas"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d)); edge.stdout.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edges listas/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 60000); });

const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).replace(/\n/g, " ⏎ ").slice(0, 700))); };
const respuestas = [], sinNoStore = [];
async function E(rol, accion, o = {}) {
  const t0 = Date.now();
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-reparto?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo !== undefined ? "POST" : "GET"),
    headers: { ...(rol ? { Authorization: `Bearer tok-${rol}` } : {}), ...(o.cuerpo !== undefined ? { "Content-Type": "application/json" } : {}) },
    body: o.crudo ?? (o.cuerpo !== undefined ? JSON.stringify(o.cuerpo) : undefined) });
  const txt = await r.text(); let c = null; try { c = JSON.parse(txt); } catch { /* */ }
  respuestas.push(txt); if (r.status === 200 && r.headers.get("cache-control") !== "no-store") sinNoStore.push(accion);
  return { s: r.status, c, txt, cache: r.headers.get("cache-control"), ms: Date.now() - t0 };
}
const xy = { lon: -73.25, lat: 10.47, precision_m: 6 };
try {
  // ===== A. Quién entra =====
  ok("A1 sin sesión: 401", (await E(null, "contexto")).s === 401);
  let r = await E("rep1", "contexto");
  ok("A2 el repartidor: 200, es repartidor y no supervisor, con el período de reparto del ciclo 98, sin caché", r.s === 200 && r.c.es_repartidor && !r.c.es_supervisor && r.cache === "no-store"
     && r.c.anterior.find((x) => x.ciclo === "98")?.reparto?.periodo?.length === 6, r.txt.slice(0, 600));
  r = await E("sup", "contexto");
  ok("A3 el supervisor de reparto: es supervisor, sin enlace al calendario (no tiene dashboard_campo)", r.s === 200 && r.c.es_supervisor && !r.c.es_repartidor && r.c.puede_calendario === false, r.txt.slice(0, 300));
  r = await E("supcal", "contexto");
  ok("A4 el supervisor de reparto con dashboard_campo: con el enlace al calendario", r.s === 200 && r.c.es_supervisor && r.c.puede_calendario === true, r.txt.slice(0, 300));
  r = await E("adm", "contexto");
  ok("A5 el administrador: las dos cosas y el calendario", r.s === 200 && r.c.es_supervisor && r.c.es_repartidor && r.c.puede_calendario, r.txt.slice(0, 300));
  const den = await Promise.all(["scrr", "campo", "nada", "inactivo"].map((x) => E(x, "contexto")));
  ok("A6 el supervisor del SCRR (solo dashboard_campo), campo sin actividad, solo comercial e inactivo: 403", den.every((x) => x.s === 403), den.map((x) => x.s + " " + x.txt).join(" | "));
  ok("A7 el repartidor no entra a lo del supervisor; el supervisor no empieza jornadas (403)",
     (await E("rep1", "avance")).s === 403 && (await E("rep1", "mapa")).s === 403 && (await E("rep1", "lotes")).s === 403 && (await E("rep1", "calendario")).s === 403
     && (await E("sup", "empezar", { cuerpo: { origen: "inventada" } })).s === 403);

  const pf = await Promise.all(["rep1", "sup", "adm", "campo", "scrr", "nada"].map((x) => E(x, "perfil")));
  ok("A8 perfil liviano: repartidor, supervisor, administrador; campo sin actividad y el del SCRR con falso y falso (200); sin campo, 403",
     pf[0].s === 200 && pf[0].c.es_repartidor && !pf[0].c.es_supervisor && pf[1].c.es_supervisor && !pf[1].c.es_repartidor && pf[2].c.es_repartidor && pf[2].c.es_supervisor
     && pf[3].s === 200 && !pf[3].c.es_repartidor && !pf[3].c.es_supervisor && pf[4].s === 200 && !pf[4].c.es_supervisor && pf[5].s === 403, pf.map((x) => x.s + " " + x.txt).join(" | "));

  // ===== B. Forma de las peticiones =====
  r = await E("rep1", "lista", { qs: { jornada_id: "1", otra: "x" } });
  ok("B1 un parámetro que no conoce: 400 y dice cuál", r.s === 400 && /«otra»/.test(r.c?.error ?? ""), r.txt);
  r = await E("rep1", "empezar", { cuerpo: { origen: "inventada", extra: 1 } });
  ok("B2 una clave del cuerpo que no conoce: 400 y dice cuál", r.s === 400 && /«extra»/.test(r.c?.error ?? ""), r.txt);
  r = await E("rep1", "empezar", { cuerpo: { origen: "inventada", autor: E_.rep2 } });
  ok("B3 fijar el autor en el cuerpo: 400", r.s === 400 && /lo fija el servidor/.test(r.c?.error ?? ""), r.txt);
  ok("B4 método equivocado: 405; acción que no existe: 400; JSON roto: 400; cuerpo de 2 MB: 413",
     (await E("rep1", "empezar")).s === 405 && (await E("rep1", "contexto", { cuerpo: {} })).s === 405 && (await E("rep1", "otra")).s === 400
     && (await E("rep1", "empezar", { cuerpo: {}, crudo: "{no" })).s === 400 && (await E("rep1", "empezar", { cuerpo: {}, crudo: JSON.stringify({ origen: "x".repeat(2 << 20) }) })).s === 413);
  ok("B5 la ruta anterior con archivo, o sin ruta con ciclo: 400", (await E("rep1", "empezar", { cuerpo: { origen: "anterior", ciclo: "98", ruta: "880101", lote_id: randomUUID() } })).s === 400
     && (await E("rep1", "empezar", { cuerpo: { origen: "inventada", ciclo: "98" } })).s === 400);

  // ===== C. El repartidor: empezar, entregar en desorden, doble toque, anular =====
  r = await E("rep1", "empezar", { cuerpo: { origen: "anterior", ciclo: "98", ruta: "880101" } });
  const j1 = r.c?.jornada?.id;
  ok("C1 empezar la ruta 880101: 5 facturas en orden de lectura, solo los códigos, con su período de reparto", r.s === 200 && r.c.jornada.total === 5
     && r.c.pendientes.map((p) => p.c).join() === "880000000101,880000000102,880000000103,880000000104,880000000105" && r.c.pendientes.every((p) => Object.keys(p).sort().join() === "c,s")
     && /^\d{6}$/.test(r.c.jornada.periodo_reparto) && r.c.jornada.respaldo === false, r.txt.slice(0, 500));
  const u = randomUUID();
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000103", ...xy, por_buscador: false, id_cliente: u } });
  ok("C2 entregar la 3.ª primero: entrega 1", r.s === 200 && r.c.consecutivo === 1 && r.c.repetida === false, r.txt);
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000103", ...xy, por_buscador: false, id_cliente: u } });
  ok("C3 el MISMO toque otra vez (reintento por red): la misma entrega, repetida", r.s === 200 && r.c.consecutivo === 1 && r.c.repetida === true, r.txt);
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000103", ...xy, id_cliente: randomUUID() } });
  ok("C4 la misma factura con otro toque: 409 con el mensaje para la persona", r.s === 409 && /ya se registró/.test(r.c?.error ?? ""), r.txt);
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000101", lon: null, lat: null, precision_m: null, id_cliente: randomUUID() } });
  ok("C5 sin GPS: 400 con «Sin ubicación del GPS…»", r.s === 400 && /^Sin ubicación del GPS/.test(r.c?.error ?? ""), r.txt);
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000999", ...xy, id_cliente: randomUUID() } });
  ok("C6 un contrato que no es de la ruta: 400 con su mensaje", r.s === 400 && r.c?.error === "El contrato 880000000999 no está en esta ruta", r.txt);
  r = await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000105", ...xy, por_buscador: true, id_cliente: randomUUID() } });
  const e2 = r.c?.entrega_id;
  ok("C7 entregar la 5.ª por el buscador: entrega 2", r.s === 200 && r.c.consecutivo === 2, r.txt);
  r = await E("rep1", "lista", { qs: { jornada_id: String(j1) } });
  ok("C8 la lista: los saltados (101 y 102, anteriores a la 103 que se tocó en la lista) arriba y marcados; la 104 NO (la 105 fue con el buscador: no mueve el punto de avance)", r.s === 200 && r.c.pendientes.map((p) => p.c + (p.s ? "*" : "")).join() === "880000000101*,880000000102*,880000000104"
     && r.c.entregadas_mias === 2 && r.cache === "no-store", r.txt);
  ok("C9 la lista de otro repartidor: 403", (await E("rep2", "lista", { qs: { jornada_id: String(j1) } })).s === 403);
  ok("C10 anular con motivo corto: 400; el otro repartidor no la anula: 403", (await E("rep1", "anular", { cuerpo: { entrega_id: e2, motivo: "corto" } })).s === 400
     && (await E("rep2", "anular", { cuerpo: { entrega_id: e2, motivo: "ZTREP no es mía esta" } })).s === 403);
  r = await E("rep1", "anular", { cuerpo: { entrega_id: e2, motivo: "ZTREP toqué la que no era" } });
  ok("C11 el repartidor anula la suya de hoy; otra vez: 409", r.s === 200 && r.c.ok === true && (await E("rep1", "anular", { cuerpo: { entrega_id: e2, motivo: "ZTREP toqué la que no era" } })).s === 409, r.txt);
  r = await E("rep2", "empezar", { cuerpo: { origen: "inventada" } });
  const ji = r.c?.jornada?.id;
  r = await E("rep2", "entregar", { cuerpo: { jornada_id: ji, contrato: "880000000104", ...xy, id_cliente: randomUUID() } });
  ok("C12 sin ruta: el otro repartidor entrega un contrato que existe; queda con su período de reparto", r.s === 200 && r.c.consecutivo === 1 && /^\d{6}$/.test(r.c.periodo_reparto ?? ""), r.txt);
  ok("C13 sin ruta, un código que no existe: 400 con su mensaje", (await E("rep2", "entregar", { cuerpo: { jornada_id: ji, contrato: "880000000998", ...xy, id_cliente: randomUUID() } })).c?.error === "No hay ningún contrato con el código 880000000998");

  // ===== D. El supervisor de reparto =====
  const sha = "a".repeat(64);
  r = await E("sup", "lote_cargar", { cuerpo: { nombre: "ztrep_ruta.xlsx", sha256: sha, tipo: "ruta", ciclo: "98", ruta: "ZT-NUEVA", filas: [{ contrato: "880000000102", orden: 2 }, { contrato: "880000000101", orden: 1 }] } });
  const lote = r.c?.lote_id;
  ok("D1 el supervisor carga un archivo de ruta (Contrato y Orden); el ciclo se deduce de los contratos (98)", r.s === 200 && r.c.ok === true && r.c.filas === 2 && r.c.ciclo === "98" && r.c.ciclo_deducido === true, r.txt);
  const nl = sqlq("select count(*) from reparto.lotes");
  r = await E("sup", "lote_cargar", { cuerpo: { nombre: "previa.xlsx", sha256: "c".repeat(64), tipo: "ruta", ruta: "ZT-P", filas: [{ contrato: "880000000103" }, { contrato: "880000000977" }], confirmar: false } });
  ok("D1b vista previa (confirmar: false), SIN ciclo: deduce 98, avisa 1 sin registro y no escribe nada", r.s === 200 && r.c.previa === true && r.c.ciclo === "98" && r.c.sin_registro === 1 && sqlq("select count(*) from reparto.lotes") === nl, r.txt);
  r = await E("sup", "lote_cargar", { cuerpo: { nombre: "dos.xlsx", sha256: "d".repeat(64), tipo: "ruta", ruta: "ZT-D", filas: [{ contrato: "880000000103" }, { contrato: "880000000104" }, { contrato: "880000000501" }] } });
  ok("D1c contratos de dos ciclos: rechazo con el detalle por ciclo, sin escribir", r.s === 200 && r.c.ok === false && r.c.errores[0] === "El archivo tiene contratos de más de un ciclo: 98: 2 · 97: 1. Un archivo debe ser de un solo ciclo." && sqlq("select count(*) from reparto.lotes") === nl, r.txt);
  r = await E("sup", "lote_cargar", { cuerpo: { nombre: "sin.xlsx", sha256: "e".repeat(64), tipo: "ciclo", filas: [{ contrato: "880000000977" }] } });
  ok("D1d todos sin registro y sin ciclo: pide escogerlo a mano; con «ciclo» se carga", r.s === 200 && r.c.ok === false && r.c.pide_ciclo === true
     && (await E("sup", "lote_cargar", { cuerpo: { nombre: "sin.xlsx", sha256: "e".repeat(64), tipo: "ciclo", ciclo: "98", filas: [{ contrato: "880000000977" }] } })).c?.ciclo === "98", r.txt);
  ok("D1e «confirmar» que no es verdadero o falso, o un ciclo con letras: 400",
     (await E("sup", "lote_cargar", { cuerpo: { nombre: "x.xlsx", sha256: "f".repeat(64), tipo: "ciclo", filas: [{ contrato: "1" }], confirmar: "no" } })).s === 400
     && (await E("sup", "lote_cargar", { cuerpo: { nombre: "x.xlsx", sha256: "f".repeat(64), tipo: "ciclo", ciclo: "C1", filas: [{ contrato: "1" }] } })).s === 400);
  r = await E("sup", "lote_cargar", { cuerpo: { nombre: "malo.xlsx", sha256: "b".repeat(64), tipo: "ciclo", ciclo: "98", filas: [{ contrato: "88A" }, { contrato: "880000000101" }, { contrato: "880000000101" }] } });
  ok("D2 un archivo con errores: 200 con ok=false y los errores por fila", r.s === 200 && r.c.ok === false && r.c.errores.length === 2 && /Fila 2/.test(r.c.errores[0]), r.txt);
  ok("D3 una columna que no es de la plantilla, un archivo de ciclo con ruta, o 10.001 filas: 400",
     (await E("sup", "lote_cargar", { cuerpo: { nombre: "x.xlsx", sha256: sha, tipo: "ruta", ciclo: "98", ruta: "R", filas: [{ contrato: "1", nombre: "x" }] } })).s === 400
     && (await E("sup", "lote_cargar", { cuerpo: { nombre: "x.xlsx", sha256: sha, tipo: "ciclo", ciclo: "98", ruta: "R", filas: [{ contrato: "1" }] } })).s === 400
     && (await E("sup", "lote_cargar", { cuerpo: { nombre: "x.xlsx", sha256: sha, tipo: "ciclo", ciclo: "98", filas: Array.from({ length: 10001 }, (_, i) => ({ contrato: String(i + 1) })) } })).s === 400);
  r = await E("rep2", "empezar", { cuerpo: { origen: "nueva", lote_id: lote } });
  const jn = r.c?.jornada?.id;
  ok("D4 el repartidor empieza con el archivo nuevo: su orden (101, 102), sin las ya entregadas", r.s === 200 && r.c.jornada.nombre_archivo === "ztrep_ruta.xlsx"
     && r.c.pendientes.map((p) => p.c).join() === "880000000101,880000000102", r.txt.slice(0, 500));
  r = await E("sup", "avance");
  const fila = (id) => r.c?.filas?.find((f) => f.jornada_id === id);
  ok("D5 avance de hoy: por repartidor y ruta, con entregadas, pendientes, saltadas, anuladas, la última y el período de reparto",
     r.s === 200 && fila(j1)?.entregadas === 1 && fila(j1)?.anuladas === 1 && fila(j1)?.pendientes === 3 && fila(j1)?.saltadas === 2 && fila(j1)?.nombre === "ZTREP Repartidor uno"
     && fila(ji)?.entregadas === 1 && fila(jn)?.total === 2 && /^\d{6}$/.test(fila(j1)?.periodo_reparto ?? ""), JSON.stringify(r.c?.filas));
  r = await E("sup", "detalle", { qs: { jornada_id: String(j1) } });
  ok("D6 detalle: el orden real con su orden de lectura, y la anulada con su motivo", r.s === 200 && r.c.entregas.map((e) => `${e.consecutivo}:${e.orden_lectura}${e.anulada ? "A" : ""}`).join() === "1:3,2:5A"
     && r.c.entregas[1].motivo_anulacion === "ZTREP toqué la que no era" && r.c.saltados.map((s) => s.contrato).join() === "880000000101,880000000102", r.txt.slice(0, 600));
  // mapa en vivo: primero todo, luego solo lo nuevo con el cursor
  let m1 = await E("sup", "mapa");
  ok("D7 mapa del día: los 3 puntos numerados, la anulada en su lista y el último id", m1.s === 200 && m1.c.puntos.length === 3 && m1.c.anuladas.length === 1 && m1.c.ultimo_id === Math.max(...m1.c.puntos.map((p) => p.id)), m1.txt);
  await E("rep1", "entregar", { cuerpo: { jornada_id: j1, contrato: "880000000101", ...xy, id_cliente: randomUUID() } });
  let m2 = await E("sup", "mapa", { qs: { despues: String(m1.c.ultimo_id) } });
  ok("D8 mapa EN VIVO: con «despues» solo llega el punto nuevo (y el último id sube)", m2.s === 200 && m2.c.puntos.length === 1 && m2.c.puntos[0].contrato === "880000000101" && m2.c.ultimo_id > m1.c.ultimo_id, m2.txt);
  let m3 = await E("sup", "mapa", { qs: { despues: String(m2.c.ultimo_id) } });
  ok("D9 sin nada nuevo: cero puntos", m3.s === 200 && m3.c.puntos.length === 0, m3.txt);
  // tiempos de la consulta periódica (lo que la pantalla repite cada pocos segundos)
  const tiempos = []; for (let i = 0; i < 10; i++) tiempos.push((await E("sup", "mapa", { qs: { despues: String(m2.c.ultimo_id) } })).ms);
  const med = [...tiempos].sort((a, b) => a - b)[5];
  console.log(`   TIEMPOS del mapa en vivo por la Edge (incluye un psql por petición): mediana ${med} ms, la más lenta ${Math.max(...tiempos)} ms`);
  ok(`D10 la consulta del mapa en vivo, diez veces: mediana ${med} ms y ninguna pasa de 1 s`, Math.max(...tiempos) < 1000);
  r = await E("sup", "calendario");
  ok("D11 calendario en solo lectura: el ciclo 98 con su fecha de reparto; sin enlace para el supervisor de reparto; con enlace para el que tiene dashboard_campo",
     r.s === 200 && r.c.ciclos.some((c) => c.ciclo === 98 && /^\d{4}-\d{2}-\d{2}$/.test(c.reparto)) && r.c.puede_cambiar === false && (await E("supcal", "calendario")).c?.puede_cambiar === true, r.txt.slice(0, 400));
  ok("D12 parámetros mal escritos: fecha, cursor, período y jornada: 400",
     (await E("sup", "avance", { qs: { fecha: "23-11-2026" } })).s === 400 && (await E("sup", "mapa", { qs: { despues: "-1" } })).s === 400
     && (await E("sup", "calendario", { qs: { periodo: "2026-11" } })).s === 400 && (await E("sup", "detalle", { qs: { jornada_id: "x" } })).s === 400);
  r = await E("sup", "lote_anular", { cuerpo: { lote_id: lote, motivo: "ZTREP archivo equivocado" } });
  ok("D13 el supervisor anula el archivo; ya no se entrega en esa lista (409) y la lista de archivos lo muestra anulado",
     r.s === 200 && (await E("rep2", "entregar", { cuerpo: { jornada_id: jn, contrato: "880000000102", ...xy, id_cliente: randomUUID() } })).s === 409
     && (await E("sup", "lotes")).c?.lotes?.find((l) => l.id === lote)?.anulado === true, r.txt);
  r = await E("sup", "anular", { cuerpo: { entrega_id: (await E("sup", "detalle", { qs: { jornada_id: String(ji) } })).c.entregas[0].id, motivo: "ZTREP la anula el supervisor" } });
  ok("D14 el supervisor anula la entrega de cualquier repartidor", r.s === 200 && r.c.ok === true, r.txt);

  // ===== Z. Lo que no debe salir =====
  ok(`Z1 todas las respuestas 200 llevan Cache-Control: no-store`, sinNoStore.length === 0, sinNoStore.join());
  ok(`Z2 ninguna de las ${respuestas.length} respuestas trae la dirección, el teléfono ni el nombre de un suscriptor`, !respuestas.some((t) => /ZTREP CALLE|telefono|direccion/i.test(t)));
  ok("Z3 el registro de la Edge no tiene XY, contratos ni filas de archivos", !/10\.47|-73\.25|8800000001|ZT-NUEVA/.test(edgeLog), edgeLog.slice(-600));
  ok("Z4 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false }); }

edge.kill(); srv.close(); borrarMia();
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
