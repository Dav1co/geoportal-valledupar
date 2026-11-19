// Prueba en Chrome REAL del borrador local del acta de Comercial («Reportar posible pérdida»), a 390 px (táctil) y 1280 px:
// · se abre un registro, se llena (texto, opciones, fotos del hallazgo y del acta física con la cámara), se RECARGA la página a la mitad y, al retomarlo desde
//   «Mis actas», sale «Tiene un borrador del … ¿Continuar o descartar?»; «Continuar» recupera lo escrito, lo elegido y las fotos del hallazgo, y el registro se hace.
// · SIN datos personales: el borrador no guarda el nombre de quien atendió, el del testigo, las fotos del acta física ni la constancia por correo.
// · volver al formulario sin recargar no pregunta; el borrador se borra al registrar, al descartar y al cancelar; con IndexedDB bloqueado todo funciona sin borrador.
// La Edge geoportal-acta va SIMULADA en Node (la base local de Code B no tiene el esquema del acta): esta prueba es de la pantalla y del almacenamiento del celular.
// Uso: node scripts/prueba_chrome_borrador_acta.mjs <chrome> <puppeteer-core> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP] = process.argv.slice(2, 4);
if (!PUP) { console.error("Uso: node scripts/prueba_chrome_borrador_acta.mjs <chrome> <puppeteer-core> [capturas]"); process.exit(2); }
const CAP = resolve(process.argv[4] || join(tmpdir(), "capturas_borrador_acta")); mkdirSync(CAP, { recursive: true });
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55993;      // puerto de Code B

// ---------- 1. La página: la pantalla real del acta, con la sesión simulada ----------
const dir = mkdtempSync(join(tmpdir(), "ui_borrador_acta_"));
const doble = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /(^\.\/|lib\/)supabase$/ }, () => ({ path: "s", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `
    export const FUNCTIONS_URL = "http://127.0.0.1:${PUERTO}/functions/v1"; export const DOMINIO = "@emdupar.gov.co";
    export const supabase = { auth: { getSession: async () => ({ data: { session: { access_token: "tok" } } }), refreshSession: async () => ({ error: null }), signOut: async () => ({}) } };` }));
} };
await build({
  plugins: [doble],
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css";
    import { PantallaActa } from "./src/campo/acta/PantallaActa.tsx";
    createRoot(document.getElementById("raiz")).render(<PantallaActa correo="zt.campo@emdupar.gov.co" onVolver={() => {}} />);
    setTimeout(() => { window.__listo = true; }, 200);` },
  bundle: true, platform: "browser", format: "esm", splitting: true, outdir: dir, entryNames: "paquete", chunkNames: "trozo-[hash]", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
const hojas = readdirSync(dir).filter((f) => f.endsWith(".css")).map((f) => `<link rel="stylesheet" href="${f}">`).join("");
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es" style="height:100%"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${hojas}</head>
<body style="height:100%;margin:0"><div class="app" style="height:100%;display:flex;flex-direction:column"><div class="barra" style="height:54px;flex:0 0 auto"></div><div id="raiz" style="display:flex;flex-direction:column;flex:1 1 auto;min-height:0;overflow:auto"></div></div><script type="module" src="paquete.js"></script></body></html>`);

// ---------- 2. La Edge geoportal-acta simulada (con su estado: aperturas, registros, cancelaciones, subidas) ----------
const CAT = {
  capacidades: { capturar: true, supervisar: false, administrar: false },
  aviso_registro: "Este es el REGISTRO DIGITAL que acompaña al acta física firmada. No sustituye al papel.",
  tipos_hallazgo: [
    { codigo: "conexion_directa", nombre: "Posible conexión directa a la red de distribución", nota: null, exige_texto: false, excluyente: false, habilita_accion: null },
    { codigo: "otro", nombre: "Otro", nota: null, exige_texto: true, excluyente: false, habilita_accion: null },
    { codigo: "sin_irregularidad", nombre: "Sin irregularidad", nota: "No se combina con otros hallazgos", exige_texto: false, excluyente: true, habilita_accion: null } ],
  calidades_atendiente: [{ codigo: "propietario", nombre: "Propietario", exige_texto: false }, { codigo: "otro", nombre: "Otro", exige_texto: true }],
  estados_medidor: [{ codigo: "funcionando", nombre: "Funcionando" }, { codigo: "frenado", nombre: "Frenado" }], estados_sellos: [{ codigo: "rotos", nombre: "Rotos" }],
  diametros: [{ codigo: "d_1_2", nombre: "1/2 pulgada" }], acciones: [],
  tipos_foto: [{ codigo: "fachada", nombre: "Fachada o nomenclatura", exigida_con_irregularidad: true, acta_fisica: false }, { codigo: "hallazgo", nombre: "Hallazgo", exigida_con_irregularidad: true, acta_fisica: false },
    { codigo: "acta_fisica", nombre: "Acta física firmada (páginas del papel)", exigida_con_irregularidad: false, acta_fisica: true }],
  limites: { min_fotos_irregularidad: 2, min_fotos_sin_irregularidad: 1, max_fotos: 10, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
  zona: { lat_min: 10.1, lat_max: 10.8, lon_min: -73.6, lon_max: -72.9 },
};
const actas = [], subidas = [], registros = [], llamadas = [];
let sig = 1;
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, x-upsert", "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS" };
  const json = (s, o) => { res.writeHead(s, { "Content-Type": "application/json", ...cors }); res.end(JSON.stringify(o)); };
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  if (u.pathname === "/favicon.ico") { res.writeHead(204); return res.end(); }
  if (u.pathname === "/" || /^\/(paquete|trozo)/.test(u.pathname)) { const f = u.pathname === "/" ? "index.html" : u.pathname.slice(1);
    res.writeHead(200, { "Content-Type": f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html", "Cache-Control": "no-store" }); return res.end(readFileSync(join(dir, f))); }
  const trozos = []; req.on("data", (c) => trozos.push(c));
  req.on("end", () => {
    const crudo = Buffer.concat(trozos);
    if (u.pathname.startsWith("/subir/")) { subidas.push({ ruta: u.pathname, bytes: crudo.length }); return json(200, { Key: u.pathname }); }
    if (u.pathname !== "/functions/v1/geoportal-acta") return json(404, {});      // la constancia por correo (geoportal-campo) no está: la sección no aparece
    const accion = u.searchParams.get("accion"), c = crudo.length ? JSON.parse(crudo.toString()) : {}; llamadas.push({ accion, c });
    const fila = (a) => ({ acta_id: a.acta_id, consecutivo: a.consecutivo, situacion: a.registrada ? "registrada" : "abierta_en_curso", abierto_en: a.abierto_en, vence_en: a.vence_en, registrado_en: a.registrada ?? null, estado: null, estado_nombre: null,
      modo_identificacion: null, contrato: null, papel_pendiente: false, fotos_papel: 0, tiene_foto_papel: !!a.registrada, max_fotos_papel: 2, puede_adjuntar_papel: false, siguiente_orden_foto: null, puede_cancelar: !a.registrada });
    switch (accion) {
      case "formulario": return json(200, CAT);
      case "mis_actas": return json(200, { filas: actas.filter((a) => !a.cancelada).map(fila).reverse(), hay_mas: false, max_filas: 50 });
      case "motivos_cancelacion": return json(200, { motivos: [{ codigo: "prueba", nombre: "Era una prueba", exige_texto: false }] });
      case "precargar": return json(200, c.contrato === "12345" ? { existe: true, direccion: "CL 10 12 34", barrio: "ZT BARRIO", barrio_en_lista: true, estrato: "2", uso: "Residencial", predios_con_ese_contrato: 1 } : { existe: false });
      case "abrir": { const a = { acta_id: `a-${sig}`, consecutivo: `AI-2026-00000${sig++}`, abierto_en: new Date().toISOString(), vence_en: new Date(Date.now() + 12 * 3600000).toISOString(), aviso_zona: false }; actas.push(a); return json(200, a); }
      case "preparar_subida": return json(200, { acta_id: c.acta_id, fotos: c.fotos.map((f) => ({ orden: f.orden, tipo: f.tipo, url_subida: `http://127.0.0.1:${PUERTO}/subir/${c.acta_id}/${f.orden}-${f.tipo}`, token: "t" })) });
      case "registrar": { const a = actas.find((x) => x.acta_id === c.acta_id); a.registrada = new Date().toISOString(); registros.push(c); return json(200, { acta_id: a.acta_id, consecutivo: a.consecutivo, version: 1, registrado_en: a.registrada, repetido: false, aviso_zona: false }); }
      case "cancelar": { const a = actas.find((x) => x.acta_id === c.acta_id); a.cancelada = true; return json(200, { acta_id: a.acta_id, consecutivo: a.consecutivo, cancelada: true, repetido: false, cancelada_en: new Date().toISOString() }); }
      default: return json(404, { error: "no existe" });
    }
  });
});
await new Promise((r) => srv.listen(PUERTO, "127.0.0.1", r));

// ---------- 3. Chrome ----------
const resultados = []; const ok = (nombre, cond, det = "") => { resultados.push({ nombre, ok: !!cond, det: String(det).replace(/\n/g, " ⏎ ").slice(0, 700) }); console.log((cond ? "OK    " : "FALLA ") + nombre + (cond ? "" : " → " + String(det).slice(0, 500))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", protocolTimeout: 600000, args: ["--no-first-run", "--no-default-browser-check", "--lang=es-CO", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${PUERTO}`, ["geolocation", "camera"]);
const errores = []; let pagina = null;
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
async function abrir(ancho, antes) {
  const p = await nav.newPage(); pagina = p;
  if (antes) await p.evaluateOnNewDocument(antes);
  await p.setGeolocation({ latitude: 10.4631, longitude: -73.2532, accuracy: 6 });
  await p.setViewport({ width: ancho, height: ancho < 500 ? 844 : 900, deviceScaleFactor: 1, isMobile: ancho < 500, hasTouch: ancho < 500 }); p.setDefaultTimeout(30000);
  p.on("dialog", (d) => void d.accept());      // «¿Salir del sitio?» al recargar con fotos en pantalla
  p.on("pageerror", (e) => errores.push(`${ancho}: ${e.message}`));
  p.on("console", (m) => { if (m.type() !== "error") return; let t = m.text(); if (/JSHandle@/.test(t)) t = m.args().map((a) => a.remoteObject().description ?? "?").join(" "); if (!/Failed to load resource|status of 404/.test(t)) errores.push(`${ancho} consola: ${t.slice(0, 200)}`); });
  await p.goto(`http://127.0.0.1:${PUERTO}/`); await p.waitForFunction(() => window.__listo === true);
  return p;
}
const texto = (p) => p.evaluate(() => document.body.innerText);
const esperarTexto = (p, re, ms = 30000) => p.waitForFunction((s) => new RegExp(s).test(document.body.innerText), { timeout: ms }, re.source);
const clicTexto = (p, sel, t) => p.evaluate((sel, t) => { const b = [...document.querySelectorAll(sel)].find((x) => x.textContent.trim().startsWith(t) && !x.disabled); if (!b) return false; b.scrollIntoView({ block: "center" }); b.click(); return true; }, sel, t);
const slug = (e) => `#acta-${e.replace(/\W+/g, "-").toLowerCase()}`;
const poner = (p, sel, valor) => p.evaluate((sel, valor) => { const el = document.querySelector(sel); if (!el) throw new Error("no está " + sel); const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : el.tagName === "SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(el, valor); el.dispatchEvent(new Event(el.tagName === "SELECT" ? "change" : "input", { bubbles: true })); }, sel, valor);
const valor = (p, sel) => p.evaluate((s) => document.querySelector(s)?.value ?? null, sel);
/** Marca un radio de un grupo por la leyenda del grupo y el texto de la opción. */
const radio = (p, leyenda, opcion) => p.evaluate((l, o) => { const f = [...document.querySelectorAll("fieldset")].find((x) => x.querySelector("legend")?.textContent.startsWith(l)); const r = [...(f?.querySelectorAll("label") ?? [])].find((x) => x.textContent.trim() === o)?.querySelector("input"); if (!r) throw new Error(`no está ${l} / ${o}`); r.click(); }, leyenda, opcion);
const radioMarcado = (p, leyenda) => p.evaluate((l) => { const f = [...document.querySelectorAll("fieldset")].find((x) => x.querySelector("legend")?.textContent.startsWith(l)); return [...(f?.querySelectorAll("label") ?? [])].find((x) => x.querySelector("input")?.checked)?.textContent.trim() ?? null; }, leyenda);
const casilla = (p, t, si = true) => p.evaluate((t, si) => { const c = [...document.querySelectorAll("label.campo-check")].find((x) => x.textContent.trim().startsWith(t))?.querySelector("input"); if (!c) throw new Error("no está la casilla " + t); if (c.checked !== si) c.click(); }, t, si);
const casillaMarcada = (p, t) => p.evaluate((t) => [...document.querySelectorAll("label.campo-check")].find((x) => x.textContent.trim().startsWith(t))?.querySelector("input")?.checked ?? null, t);
async function foto(p, boton) {
  if (!(await clicTexto(p, "button", boton))) throw new Error("no está el botón de foto " + boton);
  await p.waitForFunction(() => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; }, { timeout: 30000 });
  await p.evaluate(() => document.querySelector(".campo-capturar").click()); await p.waitForFunction(() => !document.querySelector(".campo-capturar"), { timeout: 30000 });
}
const fotosEnPantalla = (p) => p.evaluate(async () => Promise.all([...document.querySelectorAll(".campo-foto")].map(async (f) => { const i = f.querySelector("img"); if (!i.complete) await new Promise((r) => { i.onload = i.onerror = r; });
  return { pie: f.querySelector(".campo-foto-n").textContent.trim(), ancho: i.naturalWidth, bytes: (await (await fetch(i.src)).blob()).size }; })));
const idb = (p) => p.evaluate(() => new Promise((ok) => { const r = indexedDB.open("geoportal-tec-borradores", 1);
  r.onupgradeneeded = () => r.result.createObjectStore("borradores", { keyPath: "clave" }); r.onerror = () => ok(null);
  r.onsuccess = () => { const q = r.result.transaction("borradores").objectStore("borradores").getAll();
    q.onsuccess = () => { r.result.close(); ok(q.result.map((x) => ({ clave: x.clave, datos: x.datos ?? null, archivos: (x.archivos ?? []).map((a) => ({ e: a.etiqueta, n: a.blob.size })) }))); }; }; }));
const vaciarIdb = (p) => p.evaluate(() => new Promise((ok) => { const r = indexedDB.deleteDatabase("geoportal-tec-borradores"); r.onsuccess = r.onerror = r.onblocked = () => ok(true); }));
const oferta = (p) => p.evaluate(() => { const o = document.querySelector("[data-testid=borrador-oferta]"); return o ? { txt: [...o.querySelectorAll("p")].map((x) => x.textContent).join(" | "), botones: [...o.querySelectorAll("button")].map((b) => b.textContent.trim()), alto: Math.min(...[...o.querySelectorAll("button")].map((b) => b.getBoundingClientRect().height)) } : null; });
const sinDesborde = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const captura = async (p, n) => { await pausa(300); await p.screenshot({ path: join(CAP, n), fullPage: true }); };
const DESC = "ZT manguera conectada antes del medidor", NOMBRE = "ZT Juana Suscriptora";
/** «Nueva acta» con el contrato 12345 verificado → formulario abierto. Devuelve el consecutivo. */
async function nueva(p) {
  await esperarTexto(p, /Mis actas/); await clicTexto(p, "button", "Nueva acta"); await p.waitForSelector("#acta-contrato");
  await poner(p, "#acta-contrato", "12345"); await clicTexto(p, "button", "Verificar"); await esperarTexto(p, /El contrato existe/);
  await p.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Abrir registro" && !b.disabled), { timeout: 30000 });
  await clicTexto(p, "button", "Abrir registro"); await p.waitForSelector(".acta-form");
  return p.evaluate(() => document.querySelector(".acta-consecutivo").textContent.trim());
}
/** Llena lo obligatorio, menos las fotos y el nombre de quien atendió. */
async function llenar(p) {
  await radio(p, "¿El predio tiene medidor?", "No");
  await casilla(p, "Posible conexión directa"); await p.waitForSelector(slug("Descripción de los hallazgos (mínimo 10 caracteres)"));
  await poner(p, slug("Descripción de los hallazgos (mínimo 10 caracteres)"), DESC);
  await poner(p, slug("Referencia de ubicación (opcional)"), "ZT frente al parque");
  await radio(p, "¿Atendió alguien la visita?", "Sí"); await p.waitForSelector(slug("Nombre de quien atendió"));
  await poner(p, slug("En calidad de"), "propietario"); await radio(p, "En el acta física, quien atendió…", "firmó");
  await radio(p, "¿Firmó el operario en el acta física?", "Sí");
  await poner(p, slug("Observaciones (opcional)"), "ZT observación de prueba");
}
const diagnostico = async (e) => { console.log("FALLA (se detuvo) " + String(e?.message ?? e).slice(0, 400) + " · errores: " + errores.join(" | ").slice(0, 600) + " · pantalla: " + (pagina ? (await texto(pagina).catch(() => "")).slice(-900).replace(/\n/g, " ⏎ ") : ""));
  if (pagina) await pagina.screenshot({ path: join(CAP, "fallo.png"), fullPage: true }).catch(() => {}); process.exit(1); };

try {
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  let p = await abrir(ancho); await vaciarIdb(p);

  // ===== A. Llenar, recargar a la mitad y recuperar =====
  const C1 = await nueva(p); const ID1 = actas.at(-1).acta_id;
  await pausa(800);
  ok(A("A1 un registro recién abierto y sin tocar no deja borrador"), ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await llenar(p); await poner(p, slug("Nombre de quien atendió"), NOMBRE);
  await foto(p, "+ Fachada"); await foto(p, "+ Hallazgo"); await foto(p, "Fotografiar el acta física firmada");
  await pausa(900);
  let b = await idb(p); const rD = b?.find((x) => new RegExp(`^acta:${ID1}:[a-z0-9]+$`).test(x.clave)), rF = b?.find((x) => new RegExp(`^acta:${ID1}:[a-z0-9]+:archivos$`).test(x.clave));
  ok(A("A2 mientras se llena, el borrador queda en IndexedDB, por registro y por persona: lo escrito y las 2 fotos del hallazgo"), !!rD && rD.datos.borrador.descripcion === DESC && rD.datos.borrador.contrato === "12345" && rD.datos.precarga?.direccion === "CL 10 12 34"
     && rF?.archivos.map((x) => x.e).join(",") === "fachada,hallazgo", JSON.stringify(b).slice(0, 500));
  ok(A("A3 SIN datos personales: ni el nombre de quien atendió, ni el del testigo, ni la foto del acta física firmada, ni el correo de la sesión"), !!rD && !("atNombre" in rD.datos.borrador) && !("testigo" in rD.datos.borrador)
     && !/Juana|@/.test(JSON.stringify(b)) && !rF.archivos.some((x) => x.e === "acta_fisica") && (await fotosEnPantalla(p)).length === 3, JSON.stringify(b).slice(0, 500));
  const bytesAntes = rF?.archivos.map((x) => x.n).join(",");
  await captura(p, `despues_acta_llenando_${ancho}.png`);

  await p.reload(); await p.waitForFunction(() => window.__listo === true); await esperarTexto(p, new RegExp(C1));
  ok(A("A4 tras RECARGAR, «Mis actas» muestra el registro abierto con «Retomar y completar»"), /Retomar y completar/.test(await texto(p)));
  await clicTexto(p, "button", "Retomar y completar"); await p.waitForSelector("[data-testid=borrador-oferta]");
  let o = await oferta(p);
  ok(A("A5 al retomarlo: «Tiene un borrador del <fecha y hora> (con 2 fotos). ¿Continuar o descartar?», con el consecutivo, botones de 44 px o más y sin desbordar"),
    new RegExp(`Consecutivo ${C1}`).test(o.txt) && /Tiene un borrador del \d{1,2} de [a-zñ]{3,5}\.?, \d{1,2}:\d{2}\s?[ap]\.\s?m\. \(con 2 fotos\)\. ¿Continuar o descartar\?$/.test(o.txt) && o.botones.join("|") === "Continuar|Descartar" && o.alto >= 44 && (await sinDesborde(p)), JSON.stringify(o));
  await captura(p, `despues_acta_oferta_${ancho}.png`);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Continuar"); await p.waitForSelector(".acta-form");
  ok(A("A6 «Continuar» recupera el contrato y su precarga, medidor, hallazgo, descripción, referencia, calidad, firmas y observaciones"),
    (await valor(p, "#acta-contrato")) === "12345" && (await valor(p, slug("Dirección"))) === "CL 10 12 34" && (await valor(p, slug("Barrio"))) === "ZT BARRIO" && (await radioMarcado(p, "¿El predio tiene medidor?")) === "No"
     && (await casillaMarcada(p, "Posible conexión directa")) === true && (await valor(p, slug("Descripción de los hallazgos (mínimo 10 caracteres)"))) === DESC && (await valor(p, slug("Referencia de ubicación (opcional)"))) === "ZT frente al parque"
     && (await radioMarcado(p, "¿Atendió alguien la visita?")) === "Sí" && (await valor(p, slug("En calidad de"))) === "propietario" && (await radioMarcado(p, "En el acta física, quien atendió…")) === "firmó"
     && (await radioMarcado(p, "¿Firmó el operario en el acta física?")) === "Sí" && (await valor(p, slug("Observaciones (opcional)"))) === "ZT observación de prueba", (await texto(p)).slice(0, 600));
  let fs = await fotosEnPantalla(p);
  ok(A("A7 … y las 2 fotos del hallazgo, con su tipo y los mismos bytes (el sello ya puesto)"), fs.length === 2 && /^Fachada/.test(fs[0].pie) && /^Hallazgo/.test(fs[1].pie) && fs.every((f) => f.ancho > 100) && fs.map((f) => f.bytes).join(",") === bytesAntes, JSON.stringify(fs) + " · " + bytesAntes);
  ok(A("A8 el nombre de quien atendió y la foto del acta física vuelven vacíos, y la pantalla lo avisa"), (await valor(p, slug("Nombre de quien atendió"))) === "" && /Páginas del papel: 0/.test(await texto(p))
     && /Se recuperó el borrador\. Por protección de datos no se guardan el nombre de quien atendió, el del testigo ni las fotos del acta física: vuelva a ponerlos\./.test(await p.evaluate(() => document.querySelector("[data-testid=borrador-recuperado]")?.textContent ?? "")));
  await captura(p, `despues_acta_recuperada_${ancho}.png`);
  await poner(p, slug("Nombre de quien atendió"), NOMBRE); await foto(p, "Fotografiar el acta física firmada");
  await p.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Revisar y registrar" && !b.disabled), { timeout: 15000 }).catch(() => {});
  subidas.length = 0;
  await clicTexto(p, "button", "Revisar y registrar"); await esperarTexto(p, /Confirme el registro/); await clicTexto(p, "button", "Confirmar y registrar"); await esperarTexto(p, /Registro guardado/, 60000).catch(() => {});
  const reg = registros.find((r) => r.acta_id === ID1);
  ok(A("A9 el registro recuperado se registra de verdad: el contenido completo (con el nombre vuelto a escribir) y las 3 fotos subidas"), /Registro guardado/.test(await texto(p)) && !!reg && JSON.stringify(reg.contenido).includes(DESC) && JSON.stringify(reg.contenido).includes(NOMBRE) && subidas.length === 3,
    `${subidas.length} subidas · ${(await texto(p)).slice(0, 400)}`);
  await pausa(500);
  ok(A("A10 al registrar, el borrador se borra del celular"), ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));

  // ===== B. Sin recargar no pregunta; descartar; cancelar =====
  await clicTexto(p, "button", "Volver a Mis actas");
  const C2 = await nueva(p); const ID2 = actas.at(-1).acta_id;
  await llenar(p); await foto(p, "+ Fachada"); await pausa(900);
  await clicTexto(p, ".campo-cab button", "Mis actas"); await esperarTexto(p, /Continuar \(borrador en pantalla\)/);
  await clicTexto(p, "button", "Continuar (borrador en pantalla)"); await p.waitForFunction(() => !!document.querySelector(".acta-form") || !!document.querySelector("[data-testid=borrador-oferta]"));
  ok(A("B1 volver al formulario SIN recargar no pregunta: sigue lo que estaba en pantalla"), !(await p.$("[data-testid=borrador-oferta]")) && (await valor(p, slug("Descripción de los hallazgos (mínimo 10 caracteres)"))) === DESC && (await fotosEnPantalla(p)).length === 1);
  await p.reload(); await p.waitForFunction(() => window.__listo === true); await esperarTexto(p, new RegExp(C2));
  await clicTexto(p, "button", "Retomar y completar"); await p.waitForSelector("[data-testid=borrador-oferta]");
  ok(A("B2 tras recargar pregunta con 1 foto"), /\(con 1 foto\)\. ¿Continuar o descartar\?/.test((await oferta(p)).txt), (await oferta(p)).txt);
  await clicTexto(p, "[data-testid=borrador-oferta] button", "Descartar"); await p.waitForSelector(".acta-form"); await pausa(600);
  ok(A("B3 «Descartar» abre el registro vacío y borra el borrador"), (await radioMarcado(p, "¿El predio tiene medidor?")) === null && (await fotosEnPantalla(p)).length === 0 && ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await radio(p, "¿El predio tiene medidor?", "No"); await poner(p, slug("Observaciones (opcional)"), "ZT para cancelar"); await pausa(900);
  ok(A("B4 (hay borrador otra vez)"), (await idb(p))?.some((x) => x.clave.startsWith(`acta:${ID2}:`)) === true);
  await clicTexto(p, ".campo-cab button.btn-cancelar", "Cancelar"); await p.waitForSelector("#conf-canc-motivo"); await p.select("#conf-canc-motivo", "prueba");
  await clicTexto(p, ".conf-canc button", "Sí, cancelar"); await esperarTexto(p, /Actas que abrí/); await pausa(600);
  ok(A("B5 cancelar el registro (con su motivo) borra el borrador del celular"), actas.find((a) => a.acta_id === ID2).cancelada === true && ((await idb(p)) ?? [null]).length === 0, JSON.stringify(await idb(p)).slice(0, 300));
  await p.close();

  // ===== C. Con el almacenamiento bloqueado, todo funciona sin borrador =====
  const erroresAntes = errores.length;
  p = await abrir(ancho, () => { Object.defineProperty(window, "indexedDB", { configurable: true, get() { return { open() { throw new DOMException("almacenamiento bloqueado", "SecurityError"); }, deleteDatabase() { throw new DOMException("bloqueado", "SecurityError"); } }; } }); });
  await nueva(p); const ID3 = actas.at(-1).acta_id;
  await llenar(p); await poner(p, slug("Nombre de quien atendió"), NOMBRE); await foto(p, "+ Fachada"); await foto(p, "+ Hallazgo"); await foto(p, "Fotografiar el acta física firmada");
  await p.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Revisar y registrar" && !b.disabled), { timeout: 15000 }).catch(() => {});
  await clicTexto(p, "button", "Revisar y registrar"); await esperarTexto(p, /Confirme el registro/); await clicTexto(p, "button", "Confirmar y registrar"); await esperarTexto(p, /Registro guardado/, 60000).catch(() => {});
  ok(A("C1 con IndexedDB bloqueado el acta se abre, se llena y se registra, sin errores de JavaScript"), /Registro guardado/.test(await texto(p)) && registros.some((r) => r.acta_id === ID3) && errores.length === erroresAntes, errores.slice(erroresAntes).join(" | ") + (await texto(p)).slice(0, 300));
  await p.close();
}
ok("Z1 sin errores de JavaScript ni de consola", errores.length === 0, errores.join(" | "));
} catch (e) { await diagnostico(e); }

await nav.close(); srv.close();
const bien = resultados.filter((r) => r.ok).length;
console.log("----");
for (const r of resultados) console.log(`${r.ok ? "OK   " : "FALLA"} ${r.nombre}${r.ok ? "" : " → " + r.det}`);
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
