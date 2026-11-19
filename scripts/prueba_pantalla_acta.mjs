// Prueba de la PANTALLA del acta renderizando los componentes reales en Node (esbuild + react-dom/server): lo que se dibuja con cada estado (catálogo, borrador, fotos, permisos).
// No es un navegador: no ejecuta efectos ni eventos (cámara, GPS, red). Esas partes quedan PENDIENTES de probar en un celular real. Uso: node scripts/prueba_pantalla_acta.mjs
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const requerir = createRequire(join(raiz, "package.json"));
const { build } = requerir("esbuild");

const salida = join(mkdtempSync(join(tmpdir(), "pantalla_acta_")), "paquete.mjs");
// El cliente real de Supabase pide WebSocket (Node 22+): se sustituye por un doble sin red (esta prueba no usa la red).
const dobleSupabase = { name: "doble-supabase", setup(b) {
  b.onResolve({ filter: /lib\/supabase$/ }, () => ({ path: "supabase-doble", namespace: "doble" }));
  b.onLoad({ filter: /.*/, namespace: "doble" }, () => ({ loader: "js", contents: `export const FUNCTIONS_URL = "http://sim.local/functions/v1"; export const DOMINIO = "@emdupar.gov.co"; export const supabase = { auth: { getSession: async () => ({ data: { session: null } }), refreshSession: async () => ({ error: new Error("sin red") }), signOut: async () => {} } };` }));
} };
await build({
  plugins: [dobleSupabase],
  stdin: {
    resolveDir: raiz, loader: "tsx", contents: `
      import React from "react"; import { renderToStaticMarkup } from "react-dom/server";
      import { FormularioActa } from "./src/campo/acta/FormularioActa.tsx"; import { PantallaActa } from "./src/campo/acta/PantallaActa.tsx";
      import { IdentificarPredio } from "./src/campo/acta/IdentificarPredio.tsx"; import { almacenActa } from "./src/campo/acta/almacenActa.ts";
      import { AreaCampo } from "./src/campo/AreaCampo.tsx"; import * as L from "./src/campo/acta/logica.ts";
      export { React, renderToStaticMarkup, FormularioActa, PantallaActa, IdentificarPredio, almacenActa, AreaCampo, L };` },
  bundle: true, platform: "node", format: "esm", outfile: salida, jsx: "automatic", logLevel: "error",
  loader: { ".css": "empty", ".png": "dataurl", ".svg": "dataurl" }, banner: { js: 'import { createRequire as __cr } from "node:module"; const require = __cr(import.meta.url);' },
  define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"anon-falsa"', "import.meta.env.VITE_FUNCTIONS_URL": '"http://sim.local/functions/v1"' },
});
const M = await import(pathToFileURL(salida).href);
const { React: R, renderToStaticMarkup: dibujar, FormularioActa, PantallaActa, IdentificarPredio, almacenActa, AreaCampo, L } = M;
const h = R.createElement;

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const sinEtiquetas = (html) => html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");

const cat = {
  capacidades: { capturar: true, supervisar: false, administrar: false },
  aviso_registro: "Este es el REGISTRO DIGITAL que acompaña al acta física firmada. No sustituye al papel: el acta física es el documento con valor probatorio.",
  tipos_hallazgo: [
    { codigo: "conexion_directa", nombre: "Posible conexión directa a la red de distribución", nota: "Sin medidor o con bypass", exige_texto: false, excluyente: false, habilita_accion: null },
    { codigo: "reconexion_no_autorizada", nombre: "Posible reconexión no autorizada", nota: null, exige_texto: false, excluyente: false, habilita_accion: "corte_taponamiento" },
    { codigo: "otro", nombre: "Otro", nota: null, exige_texto: true, excluyente: false, habilita_accion: null },
    { codigo: "sin_irregularidad", nombre: "Sin irregularidad", nota: "No se combina con otros hallazgos", exige_texto: false, excluyente: true, habilita_accion: null },
  ],
  calidades_atendiente: [{ codigo: "propietario", nombre: "Propietario", exige_texto: false }, { codigo: "otro", nombre: "Otro", exige_texto: true }],
  estados_medidor: [{ codigo: "funcionando", nombre: "Funcionando" }, { codigo: "frenado", nombre: "Frenado" }],
  estados_sellos: [{ codigo: "rotos", nombre: "Rotos" }],
  diametros: [{ codigo: "d_1_2", nombre: "1/2 pulgada" }, { codigo: "otro", nombre: "Otro (describir en observaciones)" }],
  acciones: [
    { codigo: "retiro_medidor", nombre: "Retiro de medidor para calibración", campos: [{ clave: "serie_retirada", etiqueta: "Serie del medidor retirado", tipo: "texto", obligatorio: true }, { clave: "lectura_retiro", etiqueta: "Lectura al retiro (m³)", tipo: "numero", obligatorio: true }] },
    { codigo: "corte_taponamiento", nombre: "Corte o taponamiento", campos: [{ clave: "realizado_a_las", etiqueta: "Hora", tipo: "hora", obligatorio: true }] },
  ],
  tipos_foto: [
    { codigo: "fachada", nombre: "Fachada o nomenclatura", exigida_con_irregularidad: true, acta_fisica: false }, { codigo: "hallazgo", nombre: "Hallazgo", exigida_con_irregularidad: true, acta_fisica: false },
    { codigo: "medidor", nombre: "Medidor y lectura", exigida_con_irregularidad: false, acta_fisica: false }, { codigo: "acta_fisica", nombre: "Acta física firmada (páginas del papel)", exigida_con_irregularidad: false, acta_fisica: true },
  ],
  limites: { min_fotos_irregularidad: 2, min_fotos_sin_irregularidad: 1, max_fotos: 10, max_fotos_acta_fisica: 2, max_bytes_foto: 1572864, max_bytes_foto_acta_fisica: 2621440, vigencia_apertura_horas: 12, max_dias_acta_fisica_atras: 30 },
  zona: { lat_min: 10.35, lat_max: 10.56, lon_min: -73.36, lon_max: -73.18 },
};
const CORREO = "operario@emdupar.gov.co";
almacenActa.alAcceder(CORREO);
let n = 0;
const nueva = (cambio = {}, o = {}) => {
  const id = `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
  almacenActa.crear({ acta_id: id, consecutivo: o.consecutivo ?? "AI-2026-000123", abierto_en: "2026-11-11T20:00:00Z", vence_en: o.vence ?? "2099-01-01T00:00:00Z", aviso_zona: !!o.zona },
    { ...L.borradorVacio(o.modo ?? "con_contrato"), fechaFisica: L.hoyBogota(), ...cambio }, o.precarga ?? null);
  return id;
};
const foto = (id, tipo) => almacenActa.parchar(id, (x) => ({ ...x, fotos: [...x.fotos, { id: Math.random().toString(36).slice(2), tipo, blob: new Blob([new Uint8Array(5)]), url: URL.createObjectURL(new Blob([new Uint8Array(5)])), subida: false }] }));
const form = (id) => dibujar(h(FormularioActa, { cat, actaId: id, correo: CORREO, onVolver: () => {}, onRegistrado: () => {} }));

// ================= Formulario: consecutivo, textos fijos y secciones =================
{
  const id = nueva({ tieneMedidor: true });
  const html = form(id), txt = sinEtiquetas(html);
  ok("formulario: muestra grande el consecutivo que entregó el servidor", html.includes('class="acta-consecutivo"') && txt.includes("AI-2026-000123"));
  ok("formulario: dice «Escriba este consecutivo en el acta física»", txt.includes("Escriba este consecutivo en el acta física"));
  ok("formulario: texto fijo «El acta física firmada sigue siendo el documento con valor probatorio»", txt.includes("El acta física firmada sigue siendo el documento con valor probatorio"));
  ok("formulario: muestra el aviso del servidor", txt.includes("REGISTRO DIGITAL que acompaña al acta física firmada"));
  ok("formulario: las 7 secciones", ["1. Predio", "2. Medidor y acometida", "3. Hallazgos y acciones", "4. Atención de la visita y firmas", "5. Fotos de la visita", "6. Acta física firmada", "7. Observaciones"].every((s) => txt.includes(s)));
  ok("formulario: un checkbox por hallazgo del catálogo (nada escrito a mano) y sus notas", cat.tipos_hallazgo.every((t) => txt.includes(t.nombre)) && txt.includes("Sin medidor o con bypass"));
  ok("formulario: estado del medidor, sellos y diámetro salen del catálogo", txt.includes("Frenado") && txt.includes("Rotos") && txt.includes("1/2 pulgada") && txt.includes("Otro (describir en observaciones)"));
  ok("formulario: el diámetro lleva la nota de que la lista está en revisión por el área técnica", txt.includes("Lista en revisión por el área técnica"));
  ok("formulario: mala señal — dice que todavía no hay modo sin conexión", txt.includes("Todavía no funciona sin conexión"));
  ok("formulario: «Registrar», no «firmar»: botón «Revisar y registrar»", txt.includes("Revisar y registrar") && !/Firmar\b/.test(txt.replace(/firmó|firmar el acta|a firmar|firmar\b[^.]*\./gi, "")) );
  ok("formulario: NO hay botón ni texto de firma digital, PDF, lienzo o imagen de firma", !/(firma digital|firmar en pantalla|lienzo|\bPDF\b|imagen de firma|firmado digitalmente)/i.test(txt) && !/<canvas/i.test(html));
  ok("formulario: SOLO cámara — ningún campo de archivo (sin galería)", !/type="file"/i.test(html) && !/accept=/i.test(html));
  ok("formulario: «Revisar y registrar» deshabilitado mientras falte algo, con la lista de lo que falta", /<button[^>]*campo-enviar[^>]*disabled/.test(html) && txt.includes("Para registrar falta") && txt.includes("Marque al menos un hallazgo"));
  ok("formulario: el contrato usa teclado numérico y acepta el modo «sin contrato»", /id="acta-contrato"[^>]*inputMode="numeric"/i.test(html) && html.includes("Sin contrato (posible conexión clandestina)"));
  ok("formulario: la fecha del acta física limita a hoy y a 30 días atrás", html.includes(`max="${L.hoyBogota()}"`) && html.includes(`min="${L.sumarDias(L.hoyBogota(), -30)}"`) && html.includes('type="date"') && txt.includes("hasta 30 días atrás"));
  ok("formulario: el número del acta física es opcional y avisa con claridad si queda vacío", txt.includes("Número del acta física (si el papel ya trae uno impreso)") && txt.includes("el que cuenta es el consecutivo de este registro (AI-2026-000123)"));
  ok("formulario: «papel pendiente» explica qué pasa", txt.includes("Papel pendiente") && txt.includes("alerta de «registro sin foto del acta física»"));
  ok("formulario: la cámara solo se ofrece con botones (no hay cámara abierta al iniciar)", !html.includes("campo-camara"));
  ok("formulario: toques de 44 px o más (los controles de acta usan clases con min-height)", (readFileSync(join(raiz, "src/campo/acta/acta.css"), "utf8").match(/min-height: (\d+)px/g) ?? []).every((m) => Number(m.match(/\d+/)[0]) >= 44));
  ok("formulario: el contador de fotos del hallazgo y del papel (de 1 a 2) con los topes del servidor", txt.includes("Hallazgo: 0 de 10") && txt.includes("Páginas del papel: 0 de 2 (mínimo 1)") && txt.includes("1,5 MB") && txt.includes("2,5 MB"));
  ok("formulario: «Fotografiar el acta física firmada» disponible sin papel pendiente", txt.includes("Fotografiar el acta física firmada"));
}
// con irregularidad: mínimo 2, tipos obligatorios con asterisco, descripción y acciones
{
  const id = nueva({ hallazgos: [{ codigo: "conexion_directa", texto: "" }] });
  const txt = sinEtiquetas(form(id));
  ok("hallazgo con irregularidad: el mínimo de fotos pasa a 2 y falta fachada y hallazgo", txt.includes("Hallazgo: 0 de 10 (mínimo 2)") && txt.includes("falta: Fachada o nomenclatura, Hallazgo"));
  ok("hallazgo con irregularidad: aparece la descripción y las acciones correctivas disponibles", txt.includes("Descripción de los hallazgos (mínimo 10 caracteres)") && txt.includes("Acciones correctivas ejecutadas") && txt.includes("Retiro de medidor para calibración"));
  ok("hallazgo con irregularidad: la acción «corte» NO aparece sin el hallazgo que la habilita", !txt.includes("Corte o taponamiento"));
  ok("hallazgo con irregularidad: los tipos de foto obligatorios llevan asterisco", /\+ Fachada o nomenclatura \*/.test(sinEtiquetas(form(id))));
  const id2 = nueva({ hallazgos: [{ codigo: "reconexion_no_autorizada", texto: "" }], acciones: [{ codigo: "corte_taponamiento", detalle: {} }] });
  const html2 = form(id2);
  ok("acción habilitada por el hallazgo: aparece y dibuja su campo de hora desde el catálogo", sinEtiquetas(html2).includes("Corte o taponamiento") && /type="time"/.test(html2) && sinEtiquetas(html2).includes("Hora"));
  const id3 = nueva({ hallazgos: [{ codigo: "conexion_directa", texto: "" }], acciones: [{ codigo: "retiro_medidor", detalle: {} }] });
  const t3 = sinEtiquetas(form(id3));
  ok("acción elegida: dibuja sus campos tipados (texto y número) desde el catálogo", t3.includes("Serie del medidor retirado") && t3.includes("Lectura al retiro (m³)"));
  const id4 = nueva({ hallazgos: [{ codigo: "otro", texto: "" }] });
  ok("«Otro» exige describirlo: aparece su campo de texto", sinEtiquetas(form(id4)).includes("Describa «Otro»"));
}
// sin irregularidad
{
  const id = nueva({ hallazgos: [{ codigo: "sin_irregularidad", texto: "" }] });
  const txt = sinEtiquetas(form(id));
  ok("«Sin irregularidad»: no pide descripción ni acciones y el mínimo de fotos baja a 1", !txt.includes("Descripción de los hallazgos") && !txt.includes("Acciones correctivas") && txt.includes("Hallazgo: 0 de 10 (mínimo 1)"));
}
// sin contrato
{
  const id = nueva({}, { modo: "sin_contrato" });
  const html = form(id);
  ok("«sin contrato»: no hay campo de número de contrato y se explica", !/id="acta-contrato"/.test(html) && sinEtiquetas(html).includes("Sin contrato: la dirección y el barrio se escriben a mano"));
}
// firmas declaradas
{
  const id = nueva({ nadieAtendio: false, seNego: true, firmoAtendiente: false });
  const txt = sinEtiquetas(form(id));
  ok("firmas: son HECHOS declarados («lo que consta en el acta física»), sin firma en pantalla", txt.includes("lo que consta en el acta física") && txt.includes("en esta pantalla nadie firma"));
  ok("firmas: opciones «firmó» y «se negó a firmar», testigo obligatorio al negarse", txt.includes("firmó") && txt.includes("se negó a firmar") && txt.includes("Nombre del testigo") && !txt.includes("Nombre del testigo (si lo hubo)"));
  ok("firmas: se pregunta si firmó el operario y hay constancia", txt.includes("¿Firmó el operario en el acta física?") && txt.includes("Constancia del operario (obligatoria"));
  const idN = nueva({ nadieAtendio: true });
  const tN = sinEtiquetas(form(idN));
  ok("firmas: si nadie atendió no se piden datos del atendiente y el testigo es opcional", !tN.includes("Nombre de quien atendió") && tN.includes("Nombre del testigo (si lo hubo)") && tN.includes("Constancia del operario (obligatoria"));
  const idO = nueva({ nadieAtendio: false, atCalidad: "otro" });
  ok("firmas: la calidad «Otro» pide describirla", sinEtiquetas(form(idO)).includes("Describa la calidad"));
}
// papel pendiente, fotos y preparación
{
  const id = nueva({ papelPendiente: true });
  const txt = sinEtiquetas(form(id));
  ok("papel pendiente: no se pide ni se ofrece la foto del papel", !txt.includes("Fotografiar el acta física firmada") && !txt.includes("Páginas del papel"));
  const idF = nueva({ hallazgos: [{ codigo: "conexion_directa", texto: "" }] });
  foto(idF, "fachada"); foto(idF, "hallazgo"); foto(idF, "acta_fisica");
  const hF = form(idF), tF = sinEtiquetas(hF);
  ok("fotos: los contadores reflejan las fotos tomadas (2 del hallazgo, 1 del papel)", tF.includes("Hallazgo: 2 de 10 (mínimo 2)") && tF.includes("Páginas del papel: 1 de 2 (mínimo 1)"));
  ok("fotos: se muestran como miniaturas con su tipo y se pueden quitar mientras no se prepare la subida", (hF.match(/campo-foto-img/g) ?? []).length === 3 && (tF.match(/Quitar/g) ?? []).length === 3);
  ok("fotos: las miniaturas son direcciones en memoria (blob:), nunca archivos ni datos incrustados", (hF.match(/src="blob:/g) ?? []).length === 3 && !/data:image/.test(hF));
  almacenActa.parchar(idF, (x) => ({ ...x, prep: { acta_id: idF, fotos: [] } }));
  const tP = sinEtiquetas(form(idF));
  ok("fotos: con la subida preparada quedan fijas (sin «Quitar») y se dice por qué", tP.includes("La subida ya se preparó") && !tP.includes("Quitar"));
}
// completo: se puede registrar
{
  const id = nueva({
    contrato: "123456", direccion: "CRA 10 # 5-20", barrio: "Centro", tieneMedidor: true, estadoMedidor: "funcionando", hallazgos: [{ codigo: "conexion_directa", texto: "" }], descripcion: "Conexión directa antes del medidor",
    nadieAtendio: false, atNombre: "Persona Prueba", atCalidad: "propietario", firmoAtendiente: true, seNego: false, firmoOperario: true,
  });
  foto(id, "fachada"); foto(id, "hallazgo"); foto(id, "acta_fisica");
  const html = form(id);
  ok("completo: sin faltas, «Revisar y registrar» queda habilitado y no hay lista de faltas", !/<button[^>]*campo-enviar[^>]*disabled/.test(html) && !sinEtiquetas(html).includes("Para registrar falta"));
}
// caducado
{
  // Desde el 19-nov un registro que llega VACÍO al formulario primero busca su borrador local («Cargando…»; aquí no corren los efectos): estos dos traen algo escrito.
  const id = nueva({ observaciones: "ya en pantalla" }, { vence: "2020-01-01T00:00:00Z" });
  const html = form(id);
  ok("registro caducado: lo dice y no deja registrar", sinEtiquetas(html).includes("caducó") && /<button[^>]*campo-enviar[^>]*disabled/.test(html));
  const id2 = nueva({ observaciones: "ya en pantalla" }, { zona: true });
  ok("fuera de zona: avisa que se registra con esa marca", sinEtiquetas(form(id2)).includes("fuera de la zona de operación"));
  ok("acta que ya no está en pantalla: mensaje y salida a «Mis actas»", sinEtiquetas(dibujar(h(FormularioActa, { cat, actaId: "no-existe", correo: CORREO, onVolver: () => {}, onRegistrado: () => {} }))).includes("Volver a Mis actas"));
}

// ================= Identificar el predio =================
{
  const base = { modo: "con_contrato", contrato: "", bloqueado: false, onModo: () => {}, onContrato: () => {}, precarga: null, onPrecarga: () => {} };
  const a = dibujar(h(IdentificarPredio, base));
  ok("identificar: con contrato ofrece «Verificar» con teclado numérico y el botón apagado si está vacío", /inputMode="numeric"/i.test(a) && sinEtiquetas(a).includes("Verificar") && /<button[^>]*disabled[^>]*>Verificar|<button[^>]*>Verificar/.test(a));
  ok("identificar: dentro del formulario el botón se llama «Precargar» (verificación opcional)", sinEtiquetas(dibujar(h(IdentificarPredio, { ...base, opcional: true }))).includes("Precargar"));
  const p = dibujar(h(IdentificarPredio, { ...base, contrato: "123", precarga: { existe: true, direccion: "CALLE 1 # 2-3", barrio: "NORTE", barrio_en_lista: false, estrato: "99", estrato_codigo_no_estandar: true, uso: "RESIDENCIAL" } }));
  const tp = sinEtiquetas(p);
  ok("identificar: muestra SOLO dirección, barrio, estrato y uso; el estrato 99 como «código no estándar»", tp.includes("CALLE 1 # 2-3") && tp.includes("99 (código no estándar)") && tp.includes("RESIDENCIAL") && !/nombre|documento|cédula|teléfono/i.test(tp));
  ok("identificar: avisa si el barrio del catastro no está en la lista de barrios", tp.includes("no está en la lista de barrios"));
  const s = sinEtiquetas(dibujar(h(IdentificarPredio, { ...base, modo: "sin_contrato", ubicacion: { lat: 10.46, lon: -73.25 } })));
  ok("identificar: sin contrato no pide número y ofrece buscar un contrato cercano", !/Número de contrato/.test(s) && s.includes("¿Hay un contrato cercano?") && s.includes("Sin contrato: la dirección y el barrio se escriben a mano"));
}

// ================= Área de campo: entrada del acta y quien solo tiene acta =================
{
  const area = (props) => sinEtiquetas(dibujar(h(AreaCampo, { correo: CORREO, ...props })));
  const soloActa = area({ acta: true, campo: false });
  ok("área (solo acta): entra directo y ve ÚNICAMENTE la entrada del acta", soloActa.includes("Reportar posible pérdida") && !soloActa.includes("Reportar anomalía") && !soloActa.includes("Análisis de contrato") && !soloActa.includes("Formatos de actividad") && !soloActa.includes("Instalación de medidor") && !soloActa.includes("Cargando"));
  ok("área (solo acta): no muestra el error de «Sin acceso a Formatos de campo»", !soloActa.includes("Sin acceso a Formatos de campo"));
  ok("área (solo acta): la entrada del acta se puede abrir (es un botón habilitado, ya no un marcador)", /<button[^>]*campo-formato-activo[^>]*>\s*<strong>Reportar posible pérdida/.test(dibujar(h(AreaCampo, { correo: CORREO, acta: true, campo: false }))) && !soloActa.includes("Próximamente. Registro digital"));
  const nada = area({ acta: false, campo: false });
  ok("área (sin acta ni campo): ninguna entrada (ni botones)", !nada.includes("Reportar anomalía") && !nada.includes("Registro digital que acompaña") && !/<button/.test(dibujar(h(AreaCampo, { correo: CORREO, acta: false, campo: false }))));
  ok("área (con campo): pide el formulario de campo (muestra «Cargando…») y NO enseña el acta si no hay permiso", area({ acta: false, campo: true }).includes("Cargando") && !area({ acta: false, campo: true }).includes("Reportar posible pérdida"));
  const sup = area({ acta: true, campo: false, dashboardActa: true });
  ok("área (supervisor de actas): ve la entrada «Aperturas sin registrar» (ya no es un marcador)", sup.includes("Aperturas sin registrar") && !sup.includes("Próximamente"));
  const raro = dibujar(h(PantallaActa, { correo: CORREO, onVolver: () => {} }));
  ok("pantalla: al abrir muestra «Cargando…» mientras pide el formulario y la lista", sinEtiquetas(raro).includes("Cargando"));
}

// ================= Código fuente: reglas de la pantalla =================
{
  const dir = join(raiz, "src/campo/acta");
  const fuentes = readdirSync(dir).filter((f) => /\.(ts|tsx)$/.test(f)).map((f) => [f, readFileSync(join(dir, f), "utf8")]);
  const todo = fuentes.map(([, t]) => t).join("\n");
  const codigo = fuentes.map(([, t]) => t.replace(/\/\/[^\n]*/g, "").replace(/\/\*[\s\S]*?\*\//g, "")).join("\n");
  ok("fuente: las fotos nunca van al navegador (ni localStorage, sessionStorage ni IndexedDB)", !/(localStorage|sessionStorage|indexedDB)/.test(codigo));
  ok("fuente: ninguna llamada directa a Storage ni al SDK de Supabase desde la pantalla", !/(\.storage\b|createSignedUrl|uploadToSignedUrl|storage\.from)/.test(codigo) && !/from\s+["'][^"']*supabase-js/.test(codigo));
  ok("fuente: no se llama a vincular_reporte ni a actas_de_reporte", !/vincular_reporte|actas_de_reporte/.test(codigo));
  ok("fuente: no hay lienzo, PDF ni imágenes de firma", !/(<canvas|toDataURL|jspdf|pdf-lib|signature_pad|\bPDF\b)/i.test(codigo));
  ok("fuente: sin lenguaje tarifario", !/(tarif|bcr|poir|vaeo)/i.test(todo));
  ok("fuente: el consecutivo no se inventa en el cliente (nunca se arma un «AI-» a mano)", !/["'`]AI-/.test(codigo));
  ok("fuente: el cliente nunca manda autor, fecha del servidor ni hora (solo la fecha del papel)", !/\b(autor|usuario|email|solicitante|hora)\b["']?\s*:/.test(codigo.replace(/consecutivo: string; autor: string;/g, "")));
  ok("fuente: las pantallas de acta no usan Edge de campo ni comerciales", !/geoportal-campo|geoportal-tiles|geoportal-buscar|geoportal-barrios|geoportal-predio/.test(codigo));
}

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
