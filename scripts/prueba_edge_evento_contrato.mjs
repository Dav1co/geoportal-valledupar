// Prueba de la RUTA evento_contrato (aviso de evento por contrato) de punta a punta, sin pantallas (son del Code B): peticiones HTTP a la Edge geoportal-redes
// REAL corriendo en Deno, cuyas RPC van a la base local de CODE A (localhost:55432: producción al 19-nov + este paquete; se copia a <plantilla>_edgeevc)
// con el rol de la API (service_role) y los topes de producción (30 s y 8 s). Auth y PostgREST son simulados (el segundo pasa cada RPC a la base real).
// Sobre la RED REAL, con un evento SIMULADO (círculo en el centro de la red, declarado por la ruta evento_declarar como el supervisor) y contratos reales.
// Perfiles sintéticos como los de las sondas: Comercial (D: ver_comercial + ver_registro_tecnico), Formularios de campo (R), su supervisor (V), actas (T), su supervisor (U), administrador (A),
// supervisor de distribución (Y), supervisor de planta (S), operador (O) y alguien sin permiso. Puertos de Code A: 54991 (Auth y PostgREST) y 54992 (Edge).
// Uso: node scripts/prueba_edge_evento_contrato.mjs <deno> <supabase/functions> <psql> <plantilla con el paquete, p. ej. redes_local>
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn, execFileSync } from "node:child_process";
import http from "node:http";

const [DENO, FUNCIONES, PSQL, PLANTILLA] = process.argv.slice(2, 6);
if (!PLANTILLA) { console.error("Uso: node scripts/prueba_edge_evento_contrato.mjs <deno> <supabase/functions> <psql> <base plantilla con el aviso por contrato, p. ej. redes_local>"); process.exit(2); }
const P_BASE = 54991, P_EDGE = 54992;      // puertos de Code A
const PGENV = { ...process.env, LC_ALL: "C", PGHOST: "localhost", PGPORT: process.env.PGPORT_A || "55432", PGUSER: "postgres", PGDATABASE: `${PLANTILLA}_edgeevc`, PGOPTIONS: "-c client_min_messages=warning" };
if (PGENV.PGPORT === "55442") { console.error("El puerto 55442 es de Code B: no se toca"); process.exit(2); }
const sqlq = (s) => execFileSync(PSQL, ["-AtqX", "-v", "ON_ERROR_STOP=1", "-c", s], { env: PGENV, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lit = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : typeof v === "boolean" ? String(v) : Array.isArray(v) && v.every((x) => typeof x === "string") ? `array[${v.map((x) => `'${x.replace(/'/g, "''")}'`).join(", ")}]::text[]`
  : typeof v === "object" ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb` : `'${String(v).replace(/'/g, "''")}'`);
const EMAILS = { A: "ztevc.e.admin@emdupar.gov.co", D: "ztevc.e.comercial@emdupar.gov.co", R: "ztevc.e.campo@emdupar.gov.co", V: "ztevc.e.supcampo@emdupar.gov.co",
  T: "ztevc.e.acta@emdupar.gov.co", U: "ztevc.e.supacta@emdupar.gov.co", Y: "ztevc.e.sd@emdupar.gov.co", S: "ztevc.e.sp@emdupar.gov.co", O: "ztevc.e.op@emdupar.gov.co", N: "ztevc.e.nada@emdupar.gov.co" };
execFileSync(PSQL, ["-qX", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", `drop database if exists ${PLANTILLA}_edgeevc`, "-c", `create database ${PLANTILLA}_edgeevc template ${PLANTILLA}`], { env: PGENV, stdio: ["ignore", "pipe", "pipe"] });
if (sqlq("select coalesce(to_regprocedure('public.geoportal_redes_evento_contrato(text,text)')::text, '')") === "") { console.error(`La plantilla ${PLANTILLA} no tiene el aviso por contrato (sh rehacer_base.sh con_evc)`); process.exit(2); }
const lb = (e, nombre, cols) => sqlq(`insert into public.geoportal_lista_blanca (email, nombre, rol${cols.map((c) => ", " + c).join("")}, horario, dias) values ('${e}', '${nombre}', '${cols.length ? "consulta" : "admin"}'${cols.map(() => ", true").join("")}, 'sin_restriccion', 'todos')`);
lb(EMAILS.A, "ZTEVC Admin", []); lb(EMAILS.D, "ZTEVC Comercial", ["ver_comercial", "ver_registro_tecnico"]); lb(EMAILS.R, "ZTEVC Campo", ["ver_campo"]); lb(EMAILS.V, "ZTEVC Supervisor de campo", ["ver_dashboard_campo"]);
lb(EMAILS.Y, "ZTEVC Supervisor de distribución", ["ver_registro_tecnico", "ver_dashboard_redes"]); lb(EMAILS.S, "ZTEVC Supervisor de planta", ["ver_registro_tecnico", "ver_dashboard_tecnico"]);
lb(EMAILS.O, "ZTEVC Operador", ["ver_registro_tecnico"]); lb(EMAILS.T, "ZTEVC Actas", ["ver_acta"]); lb(EMAILS.U, "ZTEVC Supervisor de actas", ["ver_dashboard_acta"]); lb(EMAILS.N, "ZTEVC Sin módulo", ["ver_explorar"]);
const CENTRO = JSON.parse(sqlq("select jsonb_build_object('lat', round(ST_Y(ST_Centroid(ST_Extent(geom)))::numeric, 6), 'lon', round(ST_X(ST_Centroid(ST_Extent(geom)))::numeric, 6)) from redes.activo_vigente_mat where prefijo = 'RED' and sistema = 'acueducto'"));
const cerca = (m, lim, orden = "ct.contrato") => sqlq(`select string_agg(contrato, ',') from (select ct.contrato from redes.contrato_tramo ct join redes.activo_vigente_mat m on m.activo_id = ct.activo_id
  where ${m} order by ${orden} limit ${lim}) x`.replace(/\$P/g, `ST_SetSRID(ST_MakePoint(${CENTRO.lon}, ${CENTRO.lat}), 4326)::geography`)).split(",");
const DENTRO = cerca("ST_DWithin(m.geom::geography, $P, 150)", 15), FUERA = cerca("not ST_DWithin(m.geom::geography, $P, 1500)", 15, "md5(ct.contrato)");

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
const dir = mkdtempSync(join(tmpdir(), "edge_evc_"));
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
const iso = (min) => new Date(Date.now() + min * 60000).toISOString();
try {
  // ===== A. Quién entra (sin evento todavía) =====
  let r = await E("D", "evento_contrato", { qs: { contrato: FUERA[0] } });
  ok("A1 Comercial (perfil D) consulta un contrato real: 200, sin caché y las 6 claves; sin evento", r.s === 200 && r.cache === "no-store" && Object.keys(r.c).sort().join() === "consultado_en,contrato,en_evento,evento,otros_eventos,ubicado"
     && r.c.en_evento === false && r.c.evento === null && r.c.ubicado === true && r.c.contrato === FUERA[0], r.txt);
  const permiten = [], niegan = [];
  for (const p of ["A", "D", "R", "V", "T", "U", "Y", "S", "O", "N"]) ((await E(p, "evento_contrato", { qs: { contrato: FUERA[0] } })).s === 200 ? permiten : niegan).push(p);
  ok("A2 permiten A, D, R, V, T y U (administrador, Comercial, Formularios de campo, su supervisor, actas y su supervisor); Y, S, O y N reciben 403 — como dice la sonda propuesta", permiten.join() === "A,D,R,V,T,U" && niegan.join() === "Y,S,O,N", `permiten ${permiten} · niegan ${niegan}`);
  ok("A3 sin sesión: 401", (await E(null, "evento_contrato", { qs: { contrato: FUERA[0] } })).s === 401);
  r = await E("D", "evento_contrato", { qs: { contrato: "12A45" } });
  ok("A4 un contrato con letras: 400 con su texto; por POST: 405", r.s === 400 && /número del contrato/.test(r.c?.error ?? "") && (await E("D", "evento_contrato", { metodo: "POST", cuerpo: {} })).s === 405, r.txt);
  r = await E("D", "evento_contrato", { qs: { contrato: "999999999999999" } });
  ok("A5 un contrato que no está amarrado a la red: 200, «ubicado: false» y sin evento", r.s === 200 && r.c.ubicado === false && r.c.en_evento === false, r.txt);

  // ===== B. Un evento SIMULADO sobre la red real, declarado por la ruta como el supervisor =====
  r = await E("Y", "evento_declarar", { cuerpo: { alcance: "circulo", lat: CENTRO.lat, lon: CENTRO.lon, radio_m: 300, causa: "ZTEVC fuga simulada en el centro", regreso: iso(240) } });
  const EV = r.c?.codigo;
  ok(`B1 el supervisor declara por la ruta un evento simulado (círculo de 300 m en el centro de la red real): ${EV}`, r.s === 200 && /^EVS-\d{6}$/.test(EV ?? ""), r.txt);
  const malos = [];
  for (const c of DENTRO) { const x = await E("R", "evento_contrato", { qs: { contrato: c } }); if (!(x.s === 200 && x.c.en_evento && x.c.evento.codigo === EV)) malos.push(`${c}: ${x.txt.slice(0, 120)}`); }
  for (const c of FUERA) { const x = await E("V", "evento_contrato", { qs: { contrato: c } }); if (!(x.s === 200 && x.c.en_evento === false)) malos.push(`${c}: ${x.txt.slice(0, 120)}`); }
  ok("B2 los 15 contratos reales a menos de 150 m del centro están en el evento; los 15 a más de 1,5 km, no", malos.length === 0, malos.join(" | "));
  r = await E("D", "evento_contrato", { qs: { contrato: DENTRO[0] } });
  console.log("   Respuesta real: " + r.txt);
  ok("B3 la respuesta: el evento con sus 9 claves, zona «circulo», tipo «suspension», regreso estimado y el texto de la franja",
     Object.keys(r.c.evento).sort().join() === "causa,codigo,desde,regreso_estimado,texto,tipo,tipo_nombre,zona,zona_nombre" && r.c.evento.zona === "circulo" && r.c.evento.tipo === "suspension"
     && r.c.evento.tipo_nombre === "Suspensión del servicio" && !!r.c.evento.regreso_estimado && /^Sin agua en un círculo de 300 m.* desde las .* por ZTEVC fuga simulada en el centro\. Regreso estimado: /.test(r.c.evento.texto)
     && r.c.otros_eventos === 0, r.txt);

  // ===== C. Tiempos por la Edge =====
  const mediana = (l) => [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)];
  const t = [], base = [];
  for (let i = 0; i < 10; i++) { t.push((await E("D", "evento_contrato", { qs: { contrato: DENTRO[i] } })).ms); base.push((await E("D", "eventos_vigentes")).ms); }
  console.log(`   TIEMPOS por la Edge, diez veces cada una: evento_contrato → mediana ${mediana(t)} ms, la más lenta ${Math.max(...t)} ms · eventos_vigentes (otra lectura con un psql por RPC) → mediana ${mediana(base)} ms`);
  ok(`C1 TIEMPOS: por la Edge la mediana es ${mediana(t)} ms y la más lenta ${Math.max(...t)} ms (el simulador abre un psql por RPC: ~100 ms fijos); ninguna pasa de 1 s y no cuesta más que leer los eventos vigentes`,
     Math.max(...t) < 1000 && mediana(t) <= mediana(base) + 25, `${t} · ${base}`);

  // ===== D. Cerrar =====
  r = await E("Y", "evento_cerrar", { cuerpo: { evento: EV, motivo: "ZTEVC se reparó la fuga simulada" } });
  const x = await E("R", "evento_contrato", { qs: { contrato: DENTRO[0] } });
  ok("D1 cerrado el evento simulado, el contrato vuelve a «sin evento»", r.s === 200 && x.s === 200 && x.c.en_evento === false, r.txt + x.txt);
  ok("Z1 ninguna respuesta de evento_contrato trae correos ni nombres de personas", !todo.filter((s) => s.includes('"en_evento"')).some((s) => /@|ZTEVC (Admin|Comercial|Campo|Supervisor|Operador)/.test(s)));
  ok("Z3 ninguna RPC que no exista en la base", desconocidas.length === 0, [...new Set(desconocidas)].join(", "));
} catch (e) { console.log("FALLA (se detuvo) " + String(e?.stack ?? e).slice(0, 600) + " · Edge: " + edgeLog.slice(-500)); resultados.push({ nombre: "se detuvo", ok: false, det: String(e) }); }

edge.kill(); srv.close();
try { execFileSync(PSQL, ["-qX", "-d", "postgres", "-c", `drop database if exists ${PLANTILLA}_edgeevc`], { env: PGENV }); } catch { /* queda para mirarla */ }
const bien = resultados.filter((r) => r.ok).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
