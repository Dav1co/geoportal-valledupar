// Comercial 21-nov · Personal y cuadrillas (pantallas del Code B, contrato del paquete (a) acordado con el Code A: ~/geoportal-consultas/campo/comercial_21nov/CONTRATO_PERSONAL_acordado_A_B.md).
// Prueba en CHROME REAL (puppeteer-core) de «Supervisión y dashboard» → Personal y Cuadrillas, contra un servidor SIMULADO en 127.0.0.1 que sigue el contrato (nada llega a Supabase),
// a 390 px y a 1280 px, con cuatro perfiles: administrador, supervisor de campo, supervisor de actas (solo ve) y un servidor ANTERIOR al paquete (a) (la pantalla se ve como antes).
//   node scripts/prueba_chrome_personal_cuadrillas.mjs <chrome> <puppeteer-core> [carpeta_capturas]
//   -h | --help  muestra este uso. Cualquier otra opción que empiece con «-» es un error.
// Puertos: 55987 (servidor simulado) y 55988 (página). No prueba: la Edge ni la base reales (eso va con la Edge del Code A cuando entregue el commit), ni un celular físico.
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const USO = "Uso: node scripts/prueba_chrome_personal_cuadrillas.mjs <chrome> <puppeteer-core> [capturas]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a.startsWith("-"));
if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const [CHROME, PUP, CAP_ARG] = args;
if (!CHROME || !PUP) { console.error(USO); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const CAP = resolve(CAP_ARG || join(tmpdir(), "capturas_personal_cuadrillas"));
mkdirSync(CAP, { recursive: true });
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55987;

// ---------- 1. Paquete de la página (componentes reales; doble de supabase: la URL de funciones lleva el perfil simulado) ----------
const dir = mkdtempSync(join(tmpdir(), "ui_percua_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    const rol = new URLSearchParams(location.search).get("rol") || "sup";
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/" + rol + "/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/campo/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css"; import "./src/campo/comercial.css";
    import Revision from "./src/campo/dashboard/Revision.tsx";
    const q = new URLSearchParams(location.search);
    createRoot(document.getElementById("raiz")).render(<div className="com-modulo"><Revision correo={q.get("rol") + "@emdupar.gov.co"} onVolver={() => {}} /></div>);
    setTimeout(() => { window.__listo = true; }, 400);` },
  bundle: true, platform: "browser", format: "iife", outfile: join(dir, "paquete.js"), jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body><div id="raiz"></div><script src="paquete.js"></script></body></html>`);

// ---------- 2. Servidor simulado con el contrato (a) ----------
const iso = (ms = Date.now()) => new Date(ms).toISOString();
const FORMS = [{ clave: "reporte_general", nombre: "Reportar anomalía", grupo: "Reportar anomalía" }, { clave: "tipo:corte", nombre: "Corte", grupo: "Cartera" }];
let est;
function reiniciar() {
  est = {
    sec: 1000,
    areas: [["facturacion", "Facturación"], ["cartera_scrr", "Cartera / SCRR"], ["perdidas", "Pérdidas"], ["pqr", "PQR / Atención al usuario"]].map(([codigo, nombre], i) => ({ codigo, nombre, activa: true, orden: i + 1 })),
    actividades: [["suspension", "Suspensión"], ["corte", "Corte"], ["reconexion", "Reconexión"], ["lectura", "Lectura"], ["reparto", "Reparto"], ["revision_previa", "Revisiones generales"], ["censo_viejo", "Censo (antiguo)"]]
      .map(([codigo, nombre], i) => ({ codigo, nombre, activa: codigo !== "censo_viejo", orden: i + 1 })),
    cuadrillas: [
      { id: 1, nombre: "Cuadrilla Norte", activa: true, acts: ["corte", "suspension"], creada_en: iso(Date.now() - 5 * 86400e3), autor: "admin@emdupar.gov.co" },
      { id: 2, nombre: "Cuadrilla Vieja", activa: false, acts: ["lectura"], creada_en: iso(Date.now() - 50 * 86400e3), autor: "admin@emdupar.gov.co" },
    ],
    personas: [
      { email: "ana@emdupar.gov.co", nombre: "Ana Prueba", perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: true, dashboard_acta: false }, cargo: "Técnica de pérdidas", formularios: [], area: null, cuad: null, propias: ["reparto"] },
      { email: "beto@emdupar.gov.co", nombre: "Beto Prueba", perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: false, dashboard_acta: false }, cargo: null, formularios: [], area: "cartera_scrr", cuad: 1, propias: ["corte", "censo_viejo"] },
      { email: "sup@emdupar.gov.co", nombre: "Sofía Supervisora", perfil: "supervisor", permisos: { campo: false, dashboard_campo: true, acta: false, dashboard_acta: false }, cargo: "Supervisora", formularios: [], area: "perdidas", cuad: null, propias: [] },
      { email: "un.correo.bastante.largo.para.probar.el.ancho@emdupar.gov.co", nombre: null, perfil: "operario", permisos: { campo: true, dashboard_campo: false, acta: false, dashboard_acta: false }, cargo: null, formularios: [], area: null, cuad: 1, propias: [] },
    ],
    eventos: [{ id: 1, persona: null, nombre: null, tipo_evento: "cuadrilla_crear", formulario: null, formulario_nombre: null, cargo: null, motivo: null, autor: "admin@emdupar.gov.co", creado_en: iso(Date.now() - 5 * 86400e3), vigente: true, valor_codigo: null, valor_nombre: "Cuadrilla Norte", cuadrilla: { id: 1, nombre: "Cuadrilla Norte" } }],
  };
}
reiniciar();
const PUEDE = {
  adm: { cargo: true, area: true, cuadrilla: true, cuadrillas: true, actividades: true, formularios: true, catalogos: true },
  sup: { cargo: false, area: false, cuadrilla: true, cuadrillas: true, actividades: true, formularios: true, catalogos: false },
  act: { cargo: false, area: false, cuadrilla: false, cuadrillas: false, actividades: false, formularios: false, catalogos: false },
};
const area = (c) => est.areas.find((a) => a.codigo === c);
const act = (c) => est.actividades.find((a) => a.codigo === c);
const cua = (id) => est.cuadrillas.find((c) => c.id === id);
function actividadesDe(p) {
  const deC = p.cuad ? cua(p.cuad).acts : [];
  const todas = [...new Set([...deC, ...p.propias])];
  return todas.map((c) => ({ codigo: c, nombre: act(c).nombre, activa: act(c).activa, origen: deC.includes(c) && p.propias.includes(c) ? "ambas" : deC.includes(c) ? "cuadrilla" : "propia" }));
}
const personaResp = (p, yo) => ({ email: p.email, nombre: p.nombre, perfil: p.perfil, permisos: p.permisos, cargo: p.cargo, formularios: p.formularios, sin_asignacion: p.formularios.length === 0, ultimo_cambio: null,
  area: p.area ? { codigo: p.area, nombre: area(p.area).nombre, activa: area(p.area).activa } : null, cuadrilla: p.cuad ? { id: p.cuad, nombre: cua(p.cuad).nombre, activa: cua(p.cuad).activa } : null,
  actividades: actividadesDe(p), propia: p.email === yo });
const cuadResp = (c) => { const m = est.personas.filter((p) => p.cuad === c.id); return { id: c.id, nombre: c.nombre, activa: c.activa, miembros: m.map((p) => ({ email: p.email, nombre: p.nombre })), n_miembros: m.length, actividades: c.acts.map((a) => ({ codigo: a, nombre: act(a).nombre })), creada_en: c.creada_en, autor: c.autor }; };
function evento(persona, tipo, extra = {}) { est.eventos.unshift({ id: ++est.sec, persona, nombre: persona ? est.personas.find((p) => p.email === persona)?.nombre ?? null : null, tipo_evento: tipo, formulario: null, formulario_nombre: null, cargo: null, motivo: null, autor: "yo@emdupar.gov.co", creado_en: iso(), vigente: true, valor_codigo: null, valor_nombre: null, cuadrilla: null, ...extra }); return est.sec; }
const malMotivo = (m) => typeof m !== "string" || m.trim().length < 10 || m.trim().length > 300;
const FORM_REV = (adm) => ({ perfil: adm ? "admin" : "supervisor", puede: { reportar: true, crear_desde_escritorio: true, supervisar: true, administrar_catalogo: adm }, limites: { max_fotos: 2 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 }, estados: [{ codigo: "reportado", nombre: "Reportado", orden: 1, activo: true, exige_motivo: false, cambio_manual: false }], grupos: [], parametros: null, definiciones: [] });

const peticiones = [];
const cab = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Content-Type": "application/json" };
const srv = http.createServer((q, r) => {
  if (q.method === "OPTIONS") { r.writeHead(204, cab); return r.end(); }
  let cuerpo = ""; q.on("data", (c) => (cuerpo += c)); q.on("end", () => {
    const u = new URL(q.url, "http://x"), rol = u.pathname.split("/")[1], accion = u.searchParams.get("accion");
    let b = {}; try { b = cuerpo ? JSON.parse(cuerpo) : {}; } catch { /* sin cuerpo */ }
    peticiones.push({ rol, accion, cuerpo: b });
    const ok = (x) => { r.writeHead(200, cab); r.end(JSON.stringify(x)); };
    const no = (s, m) => { r.writeHead(s, cab); r.end(JSON.stringify({ error: m })); };
    const vieja = rol === "vieja" || rol === "viejasup", yo = `${rol}@emdupar.gov.co`, puede = PUEDE[rol] ?? PUEDE.act;
    switch (accion) {
      case "formulario": return ok(FORM_REV(rol === "adm" || rol === "vieja"));
      case "reportes": return ok({ reportes: [], total: 0, siguiente: null, distancia_duplicados_m: 15 });
      case "indicadores": return ok({ total: 0, visibles: 0, ocultos: 0, corte: iso(), filtros: {}, serie_recortada: false, por_dia: [], por_tipo: [], por_estado: [], revision: { revisados: 0, sin_revisar: 0, mediana_segundos: null, promedio_segundos: null, p90_segundos: null } });
      case "personal": {
        if (vieja) return ok({ puede_editar: rol === "vieja", formularios: FORMS, personas: est.personas.map((p) => { const { area: _a, cuadrilla: _c, actividades: _x, propia: _p, ...resto } = personaResp(p, ""); return resto; }) });
        return ok({ puede_editar: rol === "adm", formularios: FORMS, personas: est.personas.map((p) => personaResp(p, yo)), yo,
          areas: est.areas.filter((a) => a.activa).map(({ codigo, nombre }) => ({ codigo, nombre })), cuadrillas: est.cuadrillas.filter((c) => c.activa).map(({ id, nombre }) => ({ id, nombre })),
          actividades: est.actividades.filter((a) => a.activa).map(({ codigo, nombre }) => ({ codigo, nombre })), puede });
      }
      case "historial_personal": {
        if (vieja) return ok({ eventos: est.eventos.filter((e) => e.persona && ["fijar_cargo", "asignar_formulario", "quitar_formulario"].includes(e.tipo_evento)), siguiente: null });
        if (b.cuadrilla_id) { const id = b.cuadrilla_id; return ok({ eventos: est.eventos.filter((e) => e.cuadrilla?.id === id || (e.tipo_evento === "fijar_cuadrilla" && (e.valor_codigo === String(id) || e.de === id)))
          .map((e) => (e.persona ? { ...e, clave: `p:${e.id}`, entra: e.valor_codigo === String(id), cuadrilla: { id, nombre: cua(id).nombre } } : { ...e, clave: `c:${e.id}` })), siguiente: null }); }
        return ok({ eventos: (b.persona ? est.eventos.filter((e) => e.persona === b.persona) : est.eventos).map((e) => ({ ...e, clave: `${e.persona ? "p" : "c"}:${e.id}` })), siguiente: null });
      }
      case "personal_cambiar": {
        if (vieja) { if (rol !== "vieja") return no(403, "No tiene permiso para esta acción."); return ok({ id: evento(b.persona, b.tipo, { formulario: b.formulario ?? null, cargo: b.cargo ?? null, motivo: b.motivo ?? null }), cambio: true }); }
        const p = est.personas.find((x) => x.email === b.persona); if (!p) return no(400, "Esa persona no existe.");
        if (p.email === yo) return no(400, "No puede cambiar su propia ficha");
        const campo = { fijar_cargo: "cargo", fijar_area: "area", fijar_cuadrilla: "cuadrilla", asignar_actividad: "actividades", quitar_actividad: "actividades", asignar_formulario: "formularios", quitar_formulario: "formularios" }[b.tipo];
        if (!campo) return no(400, "Tipo de cambio desconocido.");
        if (!puede[campo]) return no(403, "No tiene permiso para esta acción.");
        if (b.tipo === "fijar_cargo") { p.cargo = b.cargo; return ok({ id: evento(p.email, "fijar_cargo", { cargo: b.cargo }), cambio: true }); }
        if (b.tipo === "fijar_area") { const a = area(b.area); if (!a) return no(400, "Esa área no existe."); if (!a.activa) return no(400, "Esa área está desactivada"); if (p.area === b.area) return no(409, "Ya estaba así."); p.area = b.area; return ok({ id: evento(p.email, "fijar_area", { valor_codigo: a.codigo, valor_nombre: a.nombre }), cambio: true }); }
        if (b.tipo === "fijar_cuadrilla") {
          if (!("cuadrilla_id" in b)) return no(400, "Falta la cuadrilla.");
          const nueva = b.cuadrilla_id; if (nueva === p.cuad) return no(409, "Ya estaba así.");
          if (nueva !== null) { const c = cua(nueva); if (!c) return no(400, "Esa cuadrilla no existe."); if (!c.activa) return no(400, "Esa cuadrilla está desactivada"); }
          if (p.cuad !== null && malMotivo(b.motivo)) return no(400, "Escriba el motivo (entre 10 y 300 caracteres)");
          const de = p.cuad; p.cuad = nueva;
          return ok({ id: evento(p.email, "fijar_cuadrilla", { valor_codigo: nueva === null ? null : String(nueva), valor_nombre: nueva === null ? null : cua(nueva).nombre, motivo: b.motivo ?? null, de }), cambio: true });
        }
        if (b.tipo === "asignar_actividad") { const a = act(b.actividad); if (!a) return no(400, "Esa actividad no existe."); if (!a.activa) return no(400, "Esa actividad está desactivada"); if (p.propias.includes(a.codigo)) return no(409, "Ya estaba así."); p.propias.push(a.codigo); return ok({ id: evento(p.email, "asignar_actividad", { valor_codigo: a.codigo, valor_nombre: a.nombre }), cambio: true }); }
        if (b.tipo === "quitar_actividad") {
          if (malMotivo(b.motivo)) return no(400, "Escriba el motivo (entre 10 y 300 caracteres)");
          if (!p.propias.includes(b.actividad)) { if (p.cuad && cua(p.cuad).acts.includes(b.actividad)) return no(409, `Esa actividad viene de la cuadrilla ${cua(p.cuad).nombre}: se quita en la cuadrilla`); return no(409, "Ya estaba así."); }
          p.propias = p.propias.filter((x) => x !== b.actividad); return ok({ id: evento(p.email, "quitar_actividad", { valor_codigo: b.actividad, valor_nombre: act(b.actividad).nombre, motivo: b.motivo }), cambio: true });
        }
        return ok({ id: evento(p.email, b.tipo, { formulario: b.formulario, motivo: b.motivo ?? null }), cambio: true });
      }
      case "cuadrillas": if (vieja) return no(400, "Acción no soportada."); return ok({ cuadrillas: est.cuadrillas.filter((c) => b.incluir_inactivas || c.activa).map(cuadResp) });
      case "cuadrilla_cambiar": {
        if (vieja) return no(400, "Acción no soportada.");
        if (!puede.cuadrillas) return no(403, "No tiene permiso para esta acción.");
        const c = b.cuadrilla_id ? cua(b.cuadrilla_id) : null;
        const nombreMal = (n) => typeof n !== "string" || n.trim().length < 2 || n.trim().length > 60;
        const ev = (tipo, extra = {}) => evento(null, tipo, { cuadrilla: { id: c.id, nombre: c.nombre }, ...extra });
        switch (b.tipo) {
          case "crear": { if (nombreMal(b.nombre)) return no(400, "El nombre debe tener entre 2 y 60 caracteres."); if (est.cuadrillas.some((x) => x.nombre.toLowerCase() === b.nombre.toLowerCase())) return no(409, "Ya existe una cuadrilla con ese nombre.");
            const n = { id: Math.max(...est.cuadrillas.map((x) => x.id)) + 1, nombre: b.nombre, activa: true, acts: [], creada_en: iso(), autor: yo }; est.cuadrillas.push(n); evento(null, "cuadrilla_crear", { cuadrilla: { id: n.id, nombre: n.nombre }, valor_nombre: n.nombre }); return ok({ id: n.id, cambio: true }); }
          case "renombrar": if (!c) return no(400, "Esa cuadrilla no existe."); if (nombreMal(b.nombre)) return no(400, "El nombre debe tener entre 2 y 60 caracteres."); c.nombre = b.nombre; ev("cuadrilla_renombrar", { valor_nombre: b.nombre }); return ok({ cambio: true });
          case "desactivar": { if (!c) return no(400, "Esa cuadrilla no existe."); if (malMotivo(b.motivo)) return no(400, "Escriba el motivo (entre 10 y 300 caracteres)");
            const n = est.personas.filter((p) => p.cuad === c.id).length; if (n) return no(409, n === 1 ? "La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla" : `La cuadrilla tiene ${n} miembros: sáquelos antes de desactivarla`);
            c.activa = false; ev("cuadrilla_desactivar", { motivo: b.motivo }); return ok({ cambio: true }); }
          case "activar": if (!c) return no(400, "Esa cuadrilla no existe."); if (c.activa) return no(409, "Ya estaba así."); c.activa = true; ev("cuadrilla_activar"); return ok({ cambio: true });
          case "agregar_actividad": { const a = act(b.actividad); if (!c || !a) return no(400, "No existe."); if (!a.activa) return no(400, "Esa actividad está desactivada"); if (c.acts.includes(a.codigo)) return no(409, "Ya estaba así."); c.acts.push(a.codigo); ev("cuadrilla_agregar_actividad", { valor_codigo: a.codigo, valor_nombre: a.nombre }); return ok({ cambio: true }); }
          case "quitar_actividad": if (!c) return no(400, "No existe."); if (malMotivo(b.motivo)) return no(400, "Escriba el motivo (entre 10 y 300 caracteres)"); if (!c.acts.includes(b.actividad)) return no(409, "Ya estaba así.");
            c.acts = c.acts.filter((x) => x !== b.actividad); ev("cuadrilla_quitar_actividad", { valor_codigo: b.actividad, valor_nombre: act(b.actividad).nombre, motivo: b.motivo }); return ok({ cambio: true });
          default: return no(400, "Tipo desconocido.");
        }
      }
      case "catalogos": if (vieja) return no(400, "Acción no soportada."); if (!puede.catalogos) return no(403, "No tiene permiso para esta acción."); return ok({ areas: est.areas, actividades: est.actividades });
      case "catalogo_cambiar": {
        if (!puede.catalogos) return no(403, "No tiene permiso para esta acción.");
        const lista = b.catalogo === "area" ? est.areas : est.actividades, cual = b.catalogo === "area" ? "un área" : "una actividad";
        if (b.tipo === "crear") {
          if (lista.some((x) => x.nombre.toLowerCase() === String(b.nombre).toLowerCase())) return no(409, `Ya existe ${cual} con ese nombre`);
          const codigo = String(b.nombre).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
          lista.push({ codigo, nombre: b.nombre, activa: true, orden: lista.length + 1 }); return ok({ codigo, cambio: true });
        }
        const it = lista.find((x) => x.codigo === b.codigo); if (!it) return no(400, "No existe.");
        if (b.tipo === "renombrar") { it.nombre = b.nombre; return ok({ cambio: true }); }
        if (b.tipo === "desactivar") { if (malMotivo(b.motivo)) return no(400, "Escriba el motivo (entre 10 y 300 caracteres)"); it.activa = false; return ok({ cambio: true }); }
        if (b.tipo === "activar") { it.activa = true; return ok({ cambio: true }); }
        return no(400, "Tipo desconocido.");
      }
      case "personal_actividad": {
        const res = est.personas.map((p) => ({ p, a: actividadesDe(p).find((x) => x.codigo === b.actividad) })).filter((x) => x.a);
        return ok({ personas: res.map(({ p, a }) => ({ email: p.email, nombre: p.nombre, cuadrilla: p.cuad ? { id: p.cuad, nombre: cua(p.cuad).nombre } : null, origen: a.origen })) });
      }
      default: return no(400, "Acción no soportada.");
    }
  });
});
const estatico = http.createServer((q, r) => { const f = q.url.split("?")[0] === "/" ? "index.html" : q.url.split("?")[0].slice(1); try { const t = readFileSync(join(dir, f)); r.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }); r.end(t); } catch { r.writeHead(404); r.end(); } });
await new Promise((a) => srv.listen(PUERTO, "127.0.0.1", a)); await new Promise((a) => estatico.listen(PUERTO + 1, "127.0.0.1", a));

// ---------- 3. Navegador ----------
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " " + String(d).slice(0, 400)}`); };
const esp = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
const ORIGEN = `http://127.0.0.1:${PUERTO + 1}`;
async function abrir(rol, ancho) {
  const pg = await nav.newPage();
  await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
  pg.on("pageerror", (e) => { total++; fallas++; console.log("FALLA error de página:", String(e).slice(0, 200)); });
  await pg.goto(`${ORIGEN}/?rol=${rol}`); await pg.waitForFunction("window.__listo === true", { timeout: 15000 }); await esp(500);
  return pg;
}
const texto = (pg, sel = "body") => pg.$eval(sel, (e) => e.innerText);
const clicTexto = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.click(); return true; } return false; }, sel, t);
const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const escribir = (pg, sel, v) => pg.evaluate((s, val) => { const i = document.querySelector(s); const proto = i.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : i.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(i, val); i.dispatchEvent(new Event(i.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, v);
const tarjeta = (pg, email) => pg.$eval(`[data-persona="${email}"]`, (e) => e.innerText).catch(() => "");
const marcar = (pg, sel) => pg.evaluate((s) => document.querySelector(s).click(), sel);
const pide = (desde, accion) => peticiones.slice(desde).filter((p) => p.accion === accion).map((p) => p.cuerpo);
/** Botones e interruptores visibles de la sección con menos de 44 px de alto (los enlaces de texto en línea no cuentan). */
const chicos = (pg) => pg.evaluate(() => [...document.querySelectorAll(".rv-seccion button.rv-boton, .rv-seccion button.rv-boton-sec, .rv-modal button, .rv-seccion select, .rv-modal select, .rv-modal input[type=text]")]
  .filter((e) => e.offsetParent && e.getBoundingClientRect().height < 43.5).map((e) => `${e.tagName}:${e.textContent.trim().slice(0, 20)}:${Math.round(e.getBoundingClientRect().height)}`));

try {
  for (const ancho of [390, 1280]) {
    reiniciar();
    // ===== Administrador: Personal =====
    let pg = await abrir("adm", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-persona]"); await esp(300);
    let t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] adm · Personal: «Usted puede» con área, cargo, cuadrilla, actividades y formularios, y «Nadie cambia su propia ficha»`,
      /Usted puede: fijar el área y el cargo, poner a cada persona en una cuadrilla, darle actividades propias y elegir sus formularios/.test(t) && t.includes("Nadie cambia su propia ficha"), t.slice(0, 400));
    let beto = await tarjeta(pg, "beto@emdupar.gov.co");
    ok(`[${ancho}] tarjeta: área, cuadrilla y actividades con su origen («ambas» = propia y de la cuadrilla) y lo desactivado marcado`,
      beto.includes("Cartera / SCRR") && beto.includes("Cuadrilla Norte") && /Corte\s*· propia y de la cuadrilla/.test(beto) && /Suspensión\s*· de la cuadrilla/.test(beto) && /Censo \(antiguo\)\s*· propia · desactivada/.test(beto), beto);
    const ana = await tarjeta(pg, "ana@emdupar.gov.co");
    ok(`[${ancho}] tarjeta sin área ni cuadrilla: «Sin área» y «Sin cuadrilla»`, ana.includes("Sin área") && ana.includes("Sin cuadrilla") && /Reparto\s*· propia/.test(ana), ana);
    // Quién puede hacer…
    let antes = peticiones.length;
    await escribir(pg, "[data-testid=quien-puede] select", "corte"); await pg.waitForFunction(() => document.querySelector(".rv-per-quien-res, .rv-per-quien .rv-vacio")); await esp(200);
    t = await texto(pg, "[data-testid=quien-puede]");
    ok(`[${ancho}] «Quién puede hacer… Corte»: pide personal_actividad y lista a quien la tiene por cuadrilla o propia`,
      pide(antes, "personal_actividad")[0]?.actividad === "corte" && t.includes("2 personas pueden hacer «Corte»") && /Beto Prueba · propia y cuadrilla Cuadrilla Norte/.test(t) && /un\.correo.* · cuadrilla Cuadrilla Norte/.test(t), t);
    // Editar a Ana: área, cuadrilla, una actividad propia más y una menos (pide motivo)
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-persona="ana@emdupar.gov.co"]').querySelectorAll("button")].find((b) => b.textContent === "Editar").click()); await pg.waitForSelector(".rv-modal");
    ok(`[${ancho}] el diálogo del administrador trae área, cargo, cuadrilla, actividades propias y formularios`,
      await pg.evaluate(() => !!document.querySelector(".rv-modal [data-campo=area]") && !!document.querySelector(".rv-modal [data-campo=cuadrilla]") && !!document.querySelector(".rv-modal [data-campo=actividades]") && document.querySelector(".rv-modal").innerText.includes("Formularios que puede llenar") && document.querySelector(".rv-modal").innerText.includes("Cargo")));
    ok(`[${ancho}] las actividades desactivadas no se ofrecen para asignar`, await pg.evaluate(() => !document.querySelector('.rv-modal input[data-actividad="censo_viejo"]')));
    await escribir(pg, ".rv-modal [data-campo=area]", "perdidas");
    await escribir(pg, ".rv-modal [data-campo=cuadrilla]", "1");
    await marcar(pg, '.rv-modal input[data-actividad="lectura"]'); await marcar(pg, '.rv-modal input[data-actividad="reparto"]'); await esp(150);
    ok(`[${ancho}] al quitar una actividad propia se pide el motivo y no deja guardar sin él`, await pg.evaluate(() => !!document.querySelector(".rv-modal textarea") && document.querySelector(".rv-modal").innerText.includes("Motivo para quitar la actividad") && [...document.querySelectorAll(".rv-modal button.rv-boton")].every((b) => b.disabled)));
    await escribir(pg, ".rv-modal textarea", "Ya no hace reparto desde esta semana");
    ok(`[${ancho}] diálogo: controles de 44 px o más`, (await chicos(pg)).length === 0, JSON.stringify(await chicos(pg)));
    await pg.screenshot({ path: join(CAP, `personal_${ancho}_editar_admin.png`) });
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(500);
    const cs = pide(antes, "personal_cambiar");
    ok(`[${ancho}] Guardar envía fijar_area, fijar_cuadrilla (sin motivo: no tenía), asignar_actividad y quitar_actividad con motivo`,
      cs.length === 4 && cs[0].tipo === "fijar_area" && cs[0].area === "perdidas" && cs[1].tipo === "fijar_cuadrilla" && cs[1].cuadrilla_id === 1 && !("motivo" in cs[1])
      && cs[2].tipo === "asignar_actividad" && cs[2].actividad === "lectura" && cs[3].tipo === "quitar_actividad" && cs[3].actividad === "reparto" && cs[3].motivo === "Ya no hace reparto desde esta semana", JSON.stringify(cs));
    const ana2 = await tarjeta(pg, "ana@emdupar.gov.co");
    ok(`[${ancho}] la tarjeta se relee: Pérdidas, Cuadrilla Norte, Corte y Suspensión de la cuadrilla, Lectura propia`, ana2.includes("Pérdidas") && ana2.includes("Cuadrilla Norte") && /Corte\s*· de la cuadrilla/.test(ana2) && /Lectura\s*· propia/.test(ana2) && !ana2.includes("Reparto"), ana2);
    t = await texto(pg, ".rv-per-hist");
    ok(`[${ancho}] historial con los textos nuevos (área, cuadrilla, actividad con su motivo)`, t.includes("Área: «Pérdidas»") && t.includes("Cuadrilla: «Cuadrilla Norte»") && t.includes("Actividad propia: asignó «Lectura»") && t.includes("Actividad propia: quitó «Reparto»") && t.includes("Motivo: Ya no hace reparto"), t.slice(0, 500));
    // Sacar a Beto de la cuadrilla: pide motivo
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-persona="beto@emdupar.gov.co"]').querySelectorAll("button")].find((b) => b.textContent === "Editar").click()); await pg.waitForSelector(".rv-modal");
    await escribir(pg, ".rv-modal [data-campo=cuadrilla]", ""); await esp(100);
    ok(`[${ancho}] sacar de la cuadrilla pide motivo («sacarla de la cuadrilla»)`, (await texto(pg, ".rv-modal")).includes("Motivo para sacarla de la cuadrilla"));
    await escribir(pg, ".rv-modal textarea", "Pasa a trabajar en la oficina");
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    const cs2 = pide(antes, "personal_cambiar");
    ok(`[${ancho}] fijar_cuadrilla con cuadrilla_id null y motivo`, cs2.length === 1 && cs2[0].tipo === "fijar_cuadrilla" && cs2[0].cuadrilla_id === null && cs2[0].motivo === "Pasa a trabajar en la oficina", JSON.stringify(cs2));
    beto = await tarjeta(pg, "beto@emdupar.gov.co");
    ok(`[${ancho}] Beto sin cuadrilla conserva sus propias (Corte pasa de «ambas» a «propia»)`, beto.includes("Sin cuadrilla") && /Corte\s*· propia\b/.test(beto) && !beto.includes("Suspensión"), beto);
    await pg.waitForFunction(() => /Beto Prueba · propia$/m.test(document.querySelector("[data-testid=quien-puede]").innerText)).catch(() => {});
    t = await texto(pg, "[data-testid=quien-puede]");
    ok(`[${ancho}] «Quién puede hacer…» se vuelve a pedir tras guardar: Beto ya sale solo «propia» y Ana entra por su cuadrilla`, /Beto Prueba · propia$/m.test(t) && t.includes("3 personas pueden hacer «Corte»") && /Ana Prueba · cuadrilla Cuadrilla Norte/.test(t), t);
    ok(`[${ancho}] adm · Personal sin desborde horizontal`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `personal_${ancho}_admin.png`), fullPage: ancho < 500 });

    // ===== Administrador: Cuadrillas y «Áreas y actividades» =====
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-cuadrilla]"); await esp(300);
    t = await texto(pg, "[data-testid=cuadrillas]");
    ok(`[${ancho}] Cuadrillas: la activa con sus actividades y miembros; la desactivada no sale sin «Mostrar las desactivadas»`,
      t.includes("Cuadrilla Norte") && t.includes("2 miembros") && t.includes("Corte") && t.includes("Suspensión") && t.includes("Ana Prueba") && !t.includes("Cuadrilla Vieja"), t.slice(0, 600));
    antes = peticiones.length;
    await clicTexto(pg, "button", "Crear cuadrilla"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "Cuadrilla Sur"); await clicTexto(pg, ".rv-modal button.rv-boton", "Crear"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await pg.waitForSelector('[data-cuadrilla="3"]');
    ok(`[${ancho}] Crear cuadrilla: cuadrilla_cambiar crear y aparece «Cuadrilla Sur» sin miembros`, pide(antes, "cuadrilla_cambiar")[0]?.tipo === "crear" && (await texto(pg, '[data-cuadrilla="3"]')).includes("Sin miembros"));
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="3"]').querySelectorAll("button")].find((b) => b.textContent === "Actividades").click()); await pg.waitForSelector(".rv-modal");
    ok(`[${ancho}] actividades de la cuadrilla: sin las desactivadas`, await pg.evaluate(() => !document.querySelector('.rv-modal input[data-actividad="censo_viejo"]')));
    await marcar(pg, '.rv-modal input[data-actividad="lectura"]'); await marcar(pg, '.rv-modal input[data-actividad="reparto"]');
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    const ag = pide(antes, "cuadrilla_cambiar");
    ok(`[${ancho}] agrega dos actividades (agregar_actividad × 2)`, ag.length === 2 && ag.every((x) => x.tipo === "agregar_actividad" && x.cuadrilla_id === 3), JSON.stringify(ag));
    // Quitar una actividad: con motivo
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="3"]').querySelectorAll("button")].find((b) => b.textContent === "Actividades").click()); await pg.waitForSelector(".rv-modal");
    await marcar(pg, '.rv-modal input[data-actividad="reparto"]'); await esp(100);
    ok(`[${ancho}] quitar una actividad de la cuadrilla pide motivo`, await pg.evaluate(() => !!document.querySelector(".rv-modal textarea") && [...document.querySelectorAll(".rv-modal button.rv-boton")].every((b) => b.disabled)));
    await escribir(pg, ".rv-modal textarea", "El reparto lo hace otra cuadrilla");
    await clicTexto(pg, ".rv-modal button.rv-boton", "Guardar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    ok(`[${ancho}] quitar_actividad con su motivo`, JSON.stringify(pide(antes, "cuadrilla_cambiar")) === JSON.stringify([{ tipo: "quitar_actividad", cuadrilla_id: 3, actividad: "reparto", motivo: "El reparto lo hace otra cuadrilla" }]), JSON.stringify(pide(antes, "cuadrilla_cambiar")));
    // Renombrar
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="3"]').querySelectorAll("button")].find((b) => b.textContent === "Renombrar").click()); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "Cuadrilla Sur 2"); await clicTexto(pg, ".rv-modal button.rv-boton", "Renombrar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    ok(`[${ancho}] Renombrar`, (await texto(pg, '[data-cuadrilla="3"]')).includes("Cuadrilla Sur 2"));
    // Desactivar la que tiene miembros: aviso y el 409 del servidor tal cual
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="1"]').querySelectorAll("button")].find((b) => b.textContent === "Desactivar").click()); await pg.waitForSelector(".rv-modal");
    t = await texto(pg, ".rv-modal");
    ok(`[${ancho}] desactivar una cuadrilla con miembros avisa antes de enviar`, t.includes("La cuadrilla tiene 2 miembros: sáquelos en Personal antes de desactivarla"), t);
    await escribir(pg, ".rv-modal textarea", "Se reorganizan las cuadrillas"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await pg.waitForSelector(".rv-modal .rv-error");
    ok(`[${ancho}] si igual se intenta, sale el texto del servidor (409)`, (await texto(pg, ".rv-modal .rv-error")).includes("La cuadrilla tiene 2 miembros: sáquelos antes de desactivarla"));
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    // Desactivar la vacía
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="3"]').querySelectorAll("button")].find((b) => b.textContent === "Desactivar").click()); await pg.waitForSelector(".rv-modal");
    await escribir(pg, ".rv-modal textarea", "Fue una cuadrilla de prueba"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(500);
    ok(`[${ancho}] desactivar con motivo y desaparece de las activas`, pide(antes, "cuadrilla_cambiar")[0]?.motivo === "Fue una cuadrilla de prueba" && !(await pg.$('[data-cuadrilla="3"]')));
    await pg.evaluate(() => [...document.querySelectorAll("label.rv-check")].find((l) => l.textContent.includes("Mostrar las desactivadas")).querySelector("input").click()); await pg.waitForSelector('[data-cuadrilla="3"]'); await esp(200);
    t = await texto(pg, '[data-cuadrilla="3"]');
    ok(`[${ancho}] «Mostrar las desactivadas»: aparecen marcadas, con «Volver a activar»`, t.includes("Desactivada") && t.includes("Volver a activar") && (await texto(pg, "[data-testid=cuadrillas]")).includes("Cuadrilla Vieja"), t);
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="3"]').querySelectorAll("button")].find((b) => b.textContent.includes("historial")).click()); await pg.waitForSelector('[data-cuadrilla="3"] [data-testid=cua-historial] li'); await esp(200);
    t = await texto(pg, '[data-cuadrilla="3"] [data-testid=cua-historial]');
    ok(`[${ancho}] historial de la cuadrilla: creada, actividades, renombrada y desactivada con motivo`, t.includes("Creó la cuadrilla «Cuadrilla Sur»") && t.includes("agregó «Lectura»") && t.includes("quitó «Reparto»") && t.includes("Renombró la cuadrilla a «Cuadrilla Sur 2»") && t.includes("Desactivó la cuadrilla") && t.includes("Motivo: Fue una cuadrilla de prueba"), t);
    await pg.evaluate(() => [...document.querySelector('[data-cuadrilla="1"]').querySelectorAll("button")].find((b) => b.textContent.includes("historial")).click()); await pg.waitForSelector('[data-cuadrilla="1"] [data-testid=cua-historial] li'); await esp(200);
    t = await texto(pg, '[data-cuadrilla="1"] [data-testid=cua-historial]');
    ok(`[${ancho}] historial de Cuadrilla Norte: quién entró y quién salió (con «entra»), con su persona`, t.includes("Entró a la cuadrilla «Cuadrilla Norte»") && t.includes("Salió de la cuadrilla «Cuadrilla Norte»") && t.includes("Ana Prueba") && t.includes("Beto Prueba"), t);
    // Áreas y actividades (solo el administrador)
    t = await texto(pg, "[data-testid=catalogos]");
    ok(`[${ancho}] «Áreas y actividades» con las 4 áreas de David y las actividades, la desactivada marcada`, ["Facturación", "Cartera / SCRR", "Pérdidas", "PQR / Atención al usuario", "Censo (antiguo)", "Desactivada"].every((x) => t.includes(x)), t.slice(0, 400));
    antes = peticiones.length;
    await clicTexto(pg, "[data-catalogo=actividad] button", "Agregar actividad"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "Revisión de PQR"); await clicTexto(pg, ".rv-modal button.rv-boton", "Agregar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    ok(`[${ancho}] agregar actividad: catalogo_cambiar crear y el aviso con el código que generó el servidor`, pide(antes, "catalogo_cambiar")[0]?.tipo === "crear" && (await texto(pg, "[data-testid=cuadrillas]")).includes("(código revision_de_pqr)"));
    await clicTexto(pg, "[data-catalogo=actividad] button", "Agregar actividad"); await pg.waitForSelector(".rv-modal [data-campo=nombre]");
    await escribir(pg, ".rv-modal [data-campo=nombre]", "Corte"); await clicTexto(pg, ".rv-modal button.rv-boton", "Agregar"); await pg.waitForSelector(".rv-modal .rv-error");
    ok(`[${ancho}] un nombre repetido muestra el 409 del servidor tal cual`, (await texto(pg, ".rv-modal .rv-error")).includes("Ya existe una actividad con ese nombre"));
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-catalogo=area] [data-codigo=pqr]').querySelectorAll("button")].find((b) => b.textContent === "Desactivar").click()); await pg.waitForSelector(".rv-modal textarea");
    await escribir(pg, ".rv-modal textarea", "Se une con Facturación en la oficina"); await clicTexto(pg, ".rv-modal button.rv-boton", "Desactivar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal")); await esp(400);
    ok(`[${ancho}] desactivar un área con motivo`, JSON.stringify(pide(antes, "catalogo_cambiar")[0]) === JSON.stringify({ catalogo: "area", tipo: "desactivar", codigo: "pqr", motivo: "Se une con Facturación en la oficina" }));
    ok(`[${ancho}] Cuadrillas: botones de 44 px o más`, (await chicos(pg)).length === 0, JSON.stringify(await chicos(pg)));
    ok(`[${ancho}] adm · Cuadrillas sin desborde horizontal`, await sinDesborde(pg));
    await pg.screenshot({ path: join(CAP, `cuadrillas_${ancho}_admin.png`), fullPage: true });
    await pg.close();

    // ===== Supervisor de campo =====
    pg = await abrir("sup", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-persona]"); await esp(300);
    t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] sup · «Usted puede» sin área ni cargo`, /Usted puede: poner a cada persona en una cuadrilla, darle actividades propias y elegir sus formularios/.test(t), t.slice(0, 300));
    const suTarjeta = await tarjeta(pg, "sup@emdupar.gov.co");
    ok(`[${ancho}] su propia ficha: «Usted», «Es su ficha: no la puede cambiar» y sin «Editar»`, suTarjeta.includes("Usted") && suTarjeta.includes("Es su ficha: no la puede cambiar") && !/\bEditar\b/.test(suTarjeta), suTarjeta);
    await pg.evaluate(() => [...document.querySelector('[data-persona="ana@emdupar.gov.co"]').querySelectorAll("button")].find((b) => b.textContent === "Editar").click()); await pg.waitForSelector(".rv-modal");
    ok(`[${ancho}] sup · el diálogo no trae área ni cargo; sí cuadrilla, actividades y formularios`,
      await pg.evaluate(() => !document.querySelector(".rv-modal [data-campo=area]") && !document.querySelector(".rv-modal").innerText.includes("Cargo") && !!document.querySelector(".rv-modal [data-campo=cuadrilla]") && !!document.querySelector(".rv-modal [data-campo=actividades]")));
    await pg.screenshot({ path: join(CAP, `personal_${ancho}_editar_supervisor.png`) });
    await clicTexto(pg, ".rv-modal button.rv-boton-sec", "Cancelar"); await esp(200);
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-cuadrilla]"); await esp(300);
    t = await texto(pg, "[data-testid=cuadrillas]");
    ok(`[${ancho}] sup · Cuadrillas: puede crear y gestionar; NO ve «Áreas y actividades»`, t.includes("Crear cuadrilla") && t.includes("Actividades") && !(await pg.$("[data-testid=catalogos]")) && !peticiones.some((p) => p.rol === "sup" && p.accion === "catalogos"));
    await pg.close();

    // ===== Supervisor de actas: solo ve =====
    pg = await abrir("act", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-persona]"); await esp(300);
    t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] supervisor de actas · Personal en solo lectura, sin «Editar» ni «Revertir»`, t.includes("Solo lectura.") && !/\bEditar\b|Revertir/.test(t) && t.includes("Cartera / SCRR"), t.slice(0, 300));
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-cuadrilla]"); await esp(300);
    t = await texto(pg, "[data-testid=cuadrillas]");
    ok(`[${ancho}] supervisor de actas · Cuadrillas en solo lectura (sin crear, sin botones de gestión)`, t.includes("Solo lectura.") && !t.includes("Crear cuadrilla") && !/\bRenombrar\b|\bDesactivar\b/.test(t), t.slice(0, 300));
    await pg.screenshot({ path: join(CAP, `cuadrillas_${ancho}_solo_lectura.png`), fullPage: ancho < 500 });
    await pg.close();

    // ===== Servidor anterior al paquete (a): Personal como antes y Cuadrillas avisa =====
    pg = await abrir("viejasup", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-persona]"); await esp(300);
    t = await texto(pg, "[data-testid=personal]");
    ok(`[${ancho}] servidor anterior · Personal como antes («Solo el administrador puede editar», sin Área, Cuadrilla, Actividades ni «Quién puede hacer…»)`,
      t.includes("Solo el administrador puede editar") && !/\bÁrea\b|Cuadrilla|Actividades|Quién puede hacer/.test(t), t.slice(0, 400));
    await clicTexto(pg, "button.rv-tab", "Cuadrillas"); await pg.waitForSelector("[data-testid=cuadrillas] [role=alert]");
    ok(`[${ancho}] servidor anterior · Cuadrillas dice que falta la actualización del servidor`, (await texto(pg, "[data-testid=cuadrillas]")).includes("necesita la actualización del servidor"));
    await pg.close();
    pg = await abrir("vieja", ancho);
    await clicTexto(pg, "button.rv-tab", "Personal"); await pg.waitForSelector("[data-persona]"); await esp(300);
    antes = peticiones.length;
    await pg.evaluate(() => [...document.querySelector('[data-persona="ana@emdupar.gov.co"]').querySelectorAll("button")].find((b) => b.textContent === "Editar").click()); await pg.waitForSelector(".rv-modal");
    ok(`[${ancho}] servidor anterior · el administrador edita cargo y formularios, sin área, cuadrilla ni actividades`,
      await pg.evaluate(() => document.querySelector(".rv-modal").innerText.includes("Cargo") && document.querySelector(".rv-modal").innerText.includes("Formularios que puede llenar") && !document.querySelector(".rv-modal [data-campo=area], .rv-modal [data-campo=cuadrilla], .rv-modal [data-campo=actividades]")));
    await pg.close();
  }
} catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 600)); }
await nav.close(); srv.close(); estatico.close();
console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
process.exit(fallas ? 1 : 0);
