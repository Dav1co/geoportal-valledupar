// Prueba de las RUTAS de PTAR-1 (geoportal-tecnica: ptar_perfil, ptar_mapa, ptar_elemento, ptar_alias, ptar_alcances, ptar_alcance) de punta a punta, sin pantallas:
// peticiones HTTP a la Edge REAL corriendo en Deno, cuyas RPC van a la base local del CODE C (clúster propio 55452, por psql_c que fija el puerto) con el rol de la API
// (service_role) y los topes de producción (30 s y 8 s). Auth y PostgREST son simulados (PostgREST pasa cada RPC a la base real). Datos SIMULADOS (prefijo ZTPTAR);
// el mapa es la carga real (914 elementos). Perfiles: administrador (A), supervisor de planta PTAP (S), jefe de la PTAR (R: alcance PTAR, sin PTAP), operador (O),
// alguien sin módulo de Técnica (N). Puertos del Code C: 56005 (Auth y PostgREST) y 56006 (Edge).
// Uso: node scripts/prueba_edge_ptar.mjs <deno> <supabase/functions> <psql_c> <plantilla con la migración y la carga, p. ej. ptar_ptar1>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const USO = "Uso: node scripts/prueba_edge_ptar.mjs <deno> <supabase/functions> <psql_c> <plantilla con PTAR-1 y la carga del mapa>   (-h, --help: este uso; base local del Code C, 55452)";
for (const a of process.argv.slice(2)) {
  if (a === "-h" || a === "--help") { console.log(USO); process.exit(0); }
  if (a.startsWith("-")) { console.error(`Opción desconocida: ${a}\n${USO}`); process.exit(2); }
}
if (process.argv.length !== 6) { console.error(`Faltan o sobran argumentos.\n${USO}`); process.exit(2); }
const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
const P_BASE = 56005, P_EDGE = 56006;
const DB = `${PLANTILLA}_edge`;
const PGENV = { ...process.env, LC_ALL: "C", PGDATABASE: DB, PGOPTIONS: "-c client_min_messages=warning" };
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
if (execFileSync(PSQL, ["-AtqX", "-d", "postgres", "-c", "show port"], { env: PGENV, encoding: "utf8" }).trim() !== "55452") { console.error("No es el clúster del Code C (55452)"); process.exit(2); }
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v)
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { A: "ztptar.admin@emdupar.gov.co", S: "ztptar.sp@emdupar.gov.co", R: "ztptar.jefe@emdupar.gov.co", O: "ztptar.op@emdupar.gov.co", N: "ztptar.nada@emdupar.gov.co", X: "ztptar.sx@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${DB}`, "-c", `create database ${DB} template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select count(*) from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = 'ptar' and e.activo") === "0") {
  console.error(`La plantilla ${PLANTILLA} no tiene PTAR-1 con la carga del mapa`); process.exit(2);
}
const N_MAPA = Number(sqlq("select count(*) from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = 'ptar' and e.activo"));
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZTPTAR Admin", []); lb(EMAILS.S, "ZTPTAR Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]);
lb(EMAILS.R, "ZTPTAR Jefe de la PTAR", ["ver_registro_tecnico", "ver_dashboard_tecnico"]); lb(EMAILS.X, "ZTPTAR Otro supervisor", ["ver_registro_tecnico", "ver_dashboard_tecnico"]);
lb(EMAILS.O, "ZTPTAR Operador", ["ver_registro_tecnico"]); lb(EMAILS.N, "ZTPTAR Sin módulo", ["ver_explorar"]);
sqlq(`insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values ('${EMAILS.R}', 'ptar', 'asignar', 'ZTPTAR jefe de la PTAR', '${EMAILS.A}'),
      ('${EMAILS.R}', 'ptap', 'quitar', 'ZTPTAR el jefe de la PTAR no ve la PTAP', '${EMAILS.A}')`);

// ---------- Auth y PostgREST simulados; cada RPC va a la base local REAL como la llama la Edge ----------
const desconocidas = [], todo = [];
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
const dir = mkdtempSync(join(tmpdir(), "edge_ptar_"));
const servir = join(dir, "servir_edge.ts");
writeFileSync(servir, `const real = Deno.serve.bind(Deno); const hs: any[] = [];
(Deno as any).serve = (x: any) => { hs.push(x); return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {}, addr: {} }; };
await import(${JSON.stringify("file://" + resolve(FUNCIONES, "geoportal-tecnica/index.ts"))});
real({ port: ${P_EDGE}, hostname: "127.0.0.1", onListen() { console.log("edge lista"); } }, (r: Request) => hs[0](r));`);
const edge = spawn(DENO, ["run", "--allow-net", "--allow-env", "--allow-read", "--no-check", servir], { env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${P_BASE}`, SERVICE_ROLE_KEY: "clave-de-prueba", DENO_NO_UPDATE_CHECK: "1" }, stdio: ["ignore", "pipe", "pipe"] });
let edgeLog = ""; edge.stderr.on("data", (d) => (edgeLog += d));
process.on("exit", () => { try { edge.kill(); } catch { /* ya terminó */ } });
await new Promise((ok, mal) => { edge.stdout.on("data", (d) => { if (/edge lista/.test(String(d))) ok(); }); edge.on("exit", (c) => mal(new Error(`la Edge terminó (${c}): ${edgeLog}`))); setTimeout(() => mal(new Error("la Edge no arrancó: " + edgeLog)), 60000); });

const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).replace(/\n/g, " ").slice(0, 600))); };
async function E(rol, accion, o = {}) {
  const t0 = Date.now();
  const r = await fetch(`http://127.0.0.1:${P_EDGE}/functions/v1/geoportal-tecnica?accion=${accion}${o.qs ? "&" + new URLSearchParams(o.qs) : ""}`, { method: o.metodo ?? (o.cuerpo ? "POST" : "GET"),
    headers: { ...(rol ? { Authorization: `Bearer tok-${rol}` } : {}), ...(o.cuerpo ? { "Content-Type": "application/json" } : {}) }, body: o.cuerpo ? JSON.stringify(o.cuerpo) : undefined });
  const txt = await r.text(); let c = null; try { c = JSON.parse(txt); } catch { /* */ }
  todo.push(txt);
  return { s: r.status, c, cache: r.headers.get("cache-control"), txt, ms: Date.now() - t0 };
}
const quien = async (accion, o = {}) => { const si = [], no = []; for (const p of ["A", "S", "R", "O", "N"]) { const r = await E(p, accion, o); (r.s === 200 ? si : no).push(p + (r.s === 200 || r.s === 403 ? "" : `(${r.s})`)); } return `${si.join()}|${no.join()}`; };
try {
  // ===== A. Quién entra (las sondas propuestas) =====
  let q = await quien("ptar_perfil");
  ok("A1 ptar_perfil: A, S, R y O reciben 200; N, 403", q === "A,S,R,O|N", q);
  q = await quien("ptar_mapa");
  ok("A2 ptar_mapa (la PTAR): A y R; S (solo PTAP), O y N reciben 403", q === "A,R|S,O,N", q);
  q = await quien("ptar_elemento", { qs: { codigo: "PTAR-LAG-1" } });
  ok("A3 ptar_elemento (una laguna): A y R; S, O y N reciben 403", q === "A,R|S,O,N", q);
  q = await quien("ptar_alcances");
  ok("A4 ptar_alcances: solo A; S, R, O y N reciben 403", q === "A|S,R,O,N", q);
  q = await quien("ptar_mapa", { qs: { instalacion: "ptap_huaricha" } });
  ok("A5 ptar_mapa de una PTAP: A y S; R (sin PTAP), O y N reciben 403", q === "A,S|R,O,N", q);
  q = await quien("quimicos_catalogo");
  ok("A6 regresión de la puerta PTAP (quimicos_catalogo): A y S; el jefe de la PTAR (R), O y N reciben 403", q === "A,S|R,O,N", q);
  let r = await E(null, "ptar_perfil");
  ok("A7 sin sesión: 401", r.s === 401, r.txt);

  // ===== B. Perfil =====
  r = await E("R", "ptar_perfil");
  ok("B1 el jefe de la PTAR: PTAR sí, PTAP no; ve solo la PTAR El Salguero", r.c?.ptar === true && r.c?.ptap === false && r.c.instalaciones.length === 1 && r.c.instalaciones[0].codigo === "ptar"
    && r.c.instalaciones[0].nombre === "PTAR El Salguero" && r.cache === "no-store", r.txt);
  r = await E("S", "ptar_perfil");
  ok("B2 el supervisor de planta: PTAP sí, PTAR no; ve las dos PTAP", r.c?.ptap === true && r.c?.ptar === false && r.c.instalaciones.map((i) => i.codigo).sort().join() === "ptap_gota_fria,ptap_huaricha", r.txt);
  r = await E("O", "ptar_perfil");
  ok("B3 el operador: ni PTAP ni PTAR, sin instalaciones", r.c?.perfil === "operador" && !r.c.ptap && !r.c.ptar && r.c.instalaciones.length === 0, r.txt);

  // ===== C. Mapa =====
  r = await E("R", "ptar_mapa");
  const f = r.c?.elementos?.features ?? [];
  console.log(`   TIEMPOS por la Edge: mapa de la PTAR ${r.ms} ms, ${r.txt.length} bytes, ${f.length} elementos`);
  ok(`C1 el mapa de la PTAR: los ${N_MAPA} elementos activos, GeoJSON válido, sin caché, en menos de 3 s`, r.s === 200 && r.c.elementos.type === "FeatureCollection" && f.length === N_MAPA
    && r.c.total === N_MAPA && f.every((x) => x.geometry?.type && x.properties?.codigo && (x.properties.tipo === "punto_medicion" ? ["sin_registros", "sin_dato_reciente", "con_datos", "fuera"].includes(x.properties.estado) : x.properties.estado === "sin_variables")) && r.cache === "no-store" && r.ms < 3000, `${r.s} ${r.ms} ${f.length}`);
  ok("C2 las piezas: 1 perímetro, 31 lagunas con su tipo y tren, pozos y conductos copiados de redes con su activo", r.c.por_tipo.perimetro === 1 && r.c.por_tipo.laguna === 31
    && f.filter((x) => x.properties.tipo === "laguna").every((x) => x.properties.tipo_laguna && x.properties.tren)
    && f.filter((x) => x.properties.origen === "redes").every((x) => /^[A-Z]{3}-\d{6}$/.test(x.properties.activo)) && r.c.por_tipo.pozo > 400, JSON.stringify(r.c.por_tipo));
  ok("C3 la caja del mapa está en Valledupar (la PTAR, al sur)", r.c.caja[0] > -73.3 && r.c.caja[2] < -73.2 && r.c.caja[1] > 10.3 && r.c.caja[3] < 10.45, JSON.stringify(r.c.caja));
  r = await E("R", "ptar_mapa", { qs: { instalacion: "PTAR; drop" } });
  ok("C4 instalación mal escrita: 400 en la Edge", r.s === 400 && /no existe/.test(r.c?.error ?? ""), r.txt);
  r = await E("R", "ptar_mapa", { qs: { instalacion: "no_existe" } });
  ok("C5 instalación que no existe: 404 con el texto de la base", r.s === 404 && r.c?.error === "Esa planta no existe", r.txt);
  r = await E("R", "ptar_mapa", { metodo: "POST", cuerpo: {} });
  ok("C6 ptar_mapa por POST: 405", r.s === 405, r.txt);

  // ===== D. Ficha de un elemento =====
  r = await E("R", "ptar_elemento", { qs: { codigo: "PTAR-PER" } });
  ok("D1 la ficha del perímetro: PTAR El Salguero, ~63 ha, sin variables asignadas", r.s === 200 && r.c.nombre === "PTAR El Salguero" && r.c.medida.area_ha > 60 && r.c.medida.area_ha < 66
    && r.c.estado === "sin_variables" && r.c.indicadores.length === 0, r.txt);
  const pozo = f.find((x) => x.properties.tipo === "pozo" && x.properties.origen === "redes")?.properties.codigo;
  r = await E("R", "ptar_elemento", { qs: { codigo: pozo } });
  ok(`D2 la ficha de un pozo copiado (${pozo}): su activo de redes y coordenadas`, r.s === 200 && r.c.tipo === "pozo" && /^POZ-\d{6}$/.test(r.c.activo) && r.c.medida.lat > 10, r.txt);
  r = await E("R", "ptar_elemento", { qs: { codigo: "x;drop" } });
  ok("D3 código mal escrito: 400 en la Edge", r.s === 400, r.txt);
  r = await E("R", "ptar_elemento", { qs: { codigo: "PTAR-NADA-9" } });
  ok("D4 elemento que no existe: 404", r.s === 404 && r.c?.error === "Ese elemento no existe", r.txt);

  // ===== E. Alias =====
  r = await E("R", "ptar_alias", { cuerpo: { codigo: "PTAR-LAG-1", alias: "Anaerobia N1", motivo: "ZTPTAR nombre corto de la laguna" } });
  ok("E1 el jefe de la PTAR pone el alias de una laguna", r.s === 200 && r.c.alias === "Anaerobia N1" && r.c.antes === null, r.txt);
  r = await E("R", "ptar_mapa");
  ok("E2 el alias sale en el mapa", r.c.elementos.features.find((x) => x.properties.codigo === "PTAR-LAG-1")?.properties.alias === "Anaerobia N1");
  r = await E("R", "ptar_alias", { cuerpo: { codigo: "PTAR-LAG-1", alias: "Anaerobia N1", motivo: "ZTPTAR otra vez lo mismo" } });
  ok("E3 el mismo alias otra vez: 400 con el texto de la base", r.s === 400 && r.c?.error === "El elemento ya tiene ese alias", r.txt);
  r = await E("R", "ptar_alias", { cuerpo: { codigo: "PTAR-LAG-1", alias: "Otra", motivo: "corto" } });
  ok("E4 motivo corto: 400 «Escriba el motivo»", r.s === 400 && /motivo/.test(r.c?.error ?? ""), r.txt);
  r = await E("R", "ptar_alias", { cuerpo: { codigo: "PTAR-LAG-1", alias: "Otra", motivo: "ZTPTAR con un dato de más", extra: 1 } });
  ok("E5 una clave que no conoce: 400 «trae un dato que no corresponde»", r.s === 400 && /no corresponde/.test(r.c?.error ?? ""), r.txt);
  r = await E("S", "ptar_alias", { cuerpo: { codigo: "PTAR-LAG-1", alias: "Otra", motivo: "ZTPTAR sin el alcance de la PTAR" } });
  ok("E6 el supervisor de la PTAP no pone alias en la PTAR: 403", r.s === 403, r.txt);
  r = await E("R", "ptar_alias");
  ok("E7 ptar_alias por GET: 405", r.s === 405, r.txt);

  // ===== F. Alcance (solo el administrador) =====
  r = await E("A", "ptar_alcance", { cuerpo: { persona: EMAILS.X, alcance: "ptar", accion: "asignar", motivo: "ZTPTAR supervisor con los dos alcances" } });
  ok("F1 el administrador asigna la PTAR a otro supervisor: queda con los dos", r.s === 200 && r.c.ptar === true && r.c.ptap === true, r.txt);
  r = await E("A", "ptar_alcances");
  ok("F2 la lista de alcances trae al jefe (solo PTAR) y al de los dos", r.s === 200 && r.c.personas.some((p) => p.persona === EMAILS.R && p.ptar && !p.ptap)
    && r.c.personas.some((p) => p.persona === EMAILS.X && p.ptar && p.ptap), r.txt.slice(0, 400));
  r = await E("A", "ptar_alcance", { cuerpo: { persona: EMAILS.X, alcance: "aseo", accion: "asignar", motivo: "ZTPTAR alcance que no existe" } });
  ok("F3 alcance desconocido: 400 en la Edge", r.s === 400 && /PTAP o PTAR/.test(r.c?.error ?? ""), r.txt);
  r = await E("A", "ptar_alcance", { cuerpo: { persona: "sin-arroba", alcance: "ptar", accion: "asignar", motivo: "ZTPTAR correo mal escrito" } });
  ok("F4 correo mal escrito: 400", r.s === 400, r.txt);
  r = await E("A", "ptar_alcance", { cuerpo: { persona: EMAILS.N, alcance: "ptar", accion: "asignar", motivo: "ZTPTAR persona sin Técnica" } });
  ok("F5 persona sin Técnica: 400 con el texto de la base", r.s === 400 && r.c?.error === "Esa persona no tiene acceso a Técnica", r.txt);
  r = await E("S", "ptar_alcance", { cuerpo: { persona: EMAILS.X, alcance: "ptar", accion: "quitar", motivo: "ZTPTAR el supervisor no asigna" } });
  ok("F6 el supervisor no asigna alcances: 403", r.s === 403, r.txt);
  r = await E("A", "ptar_alcance", { cuerpo: { persona: EMAILS.X, alcance: "ptar", accion: "quitar", motivo: "ZTPTAR con un dato de más", ip: "1.2.3.4" } });
  ok("F7 una clave que no conoce (ip en el cuerpo): 400", r.s === 400 && /no corresponde/.test(r.c?.error ?? ""), r.txt);
  ok("F8 lo cambiado queda auditado (alias y alcance)", Number(sqlq(`select count(*) from public.geoportal_auditoria where accion in ('tec_ptar_alias', 'tec_ptar_alcance') and email in ('${EMAILS.R}', '${EMAILS.A}')`)) === 2);

  // ===== G. PTAR-3: la Caracterización (formulario por punto, 7 días hacia atrás) y los parámetros en la ficha =====
  r = await E("R", "formulario", { qs: { formulario: "ptar_caracterizacion" } });
  ok("G1 el formulario Caracterización: los 4 puntos de la PTAR, 6 variables, 7 días hacia atrás", r.s === 200 && r.c.puntos.map((p) => p.codigo).sort().join() === "PTAR-AFL,PTAR-EFL,PTAR-RIO-ABJ,PTAR-RIO-ARR"
    && r.c.variables.length === 6 && r.c.dias_atras_max === 7, r.txt.slice(0, 400));
  ok("G2 el supervisor de la PTAP no abre la Caracterización: 403", (await E("S", "formulario", { qs: { formulario: "ptar_caracterizacion" } })).s === 403);
  const hace3 = sqlq("select ((clock_timestamp() at time zone 'America/Bogota')::date - 3)::text"), hace9 = sqlq("select ((clock_timestamp() at time zone 'America/Bogota')::date - 9)::text");
  r = await E("R", "registrar", { cuerpo: { formulario: "ptar_caracterizacion", punto: "PTAR-AFL", hora: "08:00", fecha_muestra: hace3, valores: [{ variable: "ar_caudal", valor: "412.5" }, { variable: "ar_dbo5", valor: "180" }] } });
  ok("G3 el jefe registra la Caracterización del afluente con la fecha del laboratorio (hace 3 días)", r.s === 200 && r.c.guardados === 2 && r.c.fecha_muestra === hace3, r.txt);
  r = await E("R", "registrar", { cuerpo: { formulario: "ptar_caracterizacion", punto: "PTAR-AFL", hora: "08:00", fecha_muestra: hace9, valores: [{ variable: "ar_caudal", valor: "1" }] } });
  ok("G4 más de 7 días atrás: 400 con el texto de la base", r.s === 400 && /7 días/.test(r.c?.error ?? ""), r.txt);
  r = await E("R", "registrar", { cuerpo: { formulario: "entrada", planta: "huaricha", hora: "08:00", fecha_muestra: hace3, valores: [{ variable: "x", valor: "1" }] } });
  ok("G5 Entrada sigue sin admitir la fecha: 400 «La fecha la fija el servidor.»", r.s === 400 && r.c?.error === "La fecha la fija el servidor.", r.txt);
  r = await E("S", "registrar", { cuerpo: { formulario: "ptar_caracterizacion", punto: "PTAR-AFL", hora: "08:00", valores: [{ variable: "ar_caudal", valor: "1" }] } });
  ok("G6 el supervisor de la PTAP no registra la Caracterización: 403", r.s === 403, r.txt);
  r = await E("R", "ptar_elemento", { qs: { codigo: "PTAR-PM-AFL" } });
  const cau = r.c?.indicadores?.find((x) => x.codigo === "ar_caudal"), ph = r.c?.indicadores?.find((x) => x.codigo === "ar_ph");
  ok("G7 la ficha del afluente: caudal 412,5 con su fecha («sin referencia»), pH de la sonda «sin registros»", r.s === 200 && cau?.valor === 412.5 && cau?.estado === "sin_referencia"
    && String(cau?.muestra_ts).startsWith(hace3) && ph?.estado === "sin_registros" && r.c.estado === "con_datos", r.txt.slice(0, 600));
  r = await E("R", "ptar_mapa");
  ok("G8 en el mapa, el afluente con datos y los otros tres puntos sin registros", r.c.elementos.features.filter((f) => f.properties.tipo === "punto_medicion").map((f) => `${f.properties.punto}=${f.properties.estado}`).sort().join()
    === "PTAR-AFL=con_datos,PTAR-EFL=sin_registros,PTAR-RIO-ABJ=sin_registros,PTAR-RIO-ARR=sin_registros", r.txt.slice(0, 300));

  // ===== Z. Lo que no debe salir =====
  r = await E("R", "ptar_no_existe");
  ok("Z1 una ruta que no existe: 400 «Acción no soportada.»", r.s === 400 && /no soportada/.test(r.c?.error ?? ""), r.txt);
  ok("Z2 ninguna respuesta trae nombres de las personas de prueba ni teléfonos", !todo.some((t) => /ZTPTAR (Admin|Supervisor|Jefe|Operador|Otro|Sin)/.test(t) || /\b3\d{9}\b/.test(t)));
  ok("Z3 ninguna respuesta trae términos tarifarios ni datos del suscriptor", !todo.some((t) => /suscriptor|tarifa|estrato|subsidio/i.test(t)));
  ok("Z4 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${DB}`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
