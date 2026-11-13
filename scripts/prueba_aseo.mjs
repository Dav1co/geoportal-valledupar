// Prueba de la lógica PURA de Aseo (src/aseo): búsqueda y programación de rutas, formulario del catálogo, cargador de capas (GeoJSON y KML con la capa de prueba de David), lector del plan operativo (.xlsx real)
// y escritor del acta en PDF. Sin red ni navegador. Uso: node scripts/prueba_aseo.mjs   (usa el paquete typescript del proyecto; lee los insumos de ~/geoportal-consultas/campo/insumos_aseo/ si existen)
import { readFileSync, writeFileSync, mkdtempSync, existsSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const salida = mkdtempSync(join(tmpdir(), "aseo_front_"));
for (const f of ["tipos", "logica", "cargador", "xlsx", "pdf", "membrete"]) {
  const js = ts.transpileModule(readFileSync(join(aqui, "../src/aseo", f + ".ts"), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText.replace(/from\s+["']\.\/(\w+)["']/g, 'from "./$1.mjs"');
  writeFileSync(join(salida, f + ".mjs"), js);
}
const imp = (f) => import(pathToFileURL(join(salida, f + ".mjs")).href);
const L = await imp("logica"), C = await imp("cargador"), X = await imp("xlsx"), P = await imp("pdf"), M = await imp("membrete");
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const INS = join(homedir(), "geoportal-consultas/campo/insumos_aseo");

// ---------- Búsqueda ----------
const ruta = (o) => ({ id: 1, codigo: "2010011207003", servicio: { codigo: "12", nombre: "Barrido Manual" }, turno: 1, turno_nombre: "Día", frecuencia: "07", frecuencia_nombre: "L-D", dias: [1, 2, 3, 4, 5, 6, 7], hora_inicio: "06:00", hora_fin: "14:00",
  sectores: "Centro, El Carmen - C19A a 17 de K9 a 6", caracterizacion: "Comercial", km_ruta: 3.9, barrios: ["Centro", "El Carmen"], geometria: null, ...o });
const rutas = [ruta({}), ruta({ id: 2, codigo: "2010011207008", sectores: "Loperena - C16A a 14 de K12 a 11", barrios: ["Loperena"] }), ruta({ id: 3, codigo: "2020011403011", sectores: "La Nevada - K1 a 3", barrios: ["La Nevada"], dias: [1, 4], turno: 2, hora_inicio: "14:00", hora_fin: "22:00" })];
ok("buscar: menos de 5 caracteres no busca", L.buscarRutas(rutas, "cent").length === 0 && L.buscarRutas(rutas, "Cent", 4).length === 1);
ok("buscar por barrio sin tildes ni mayúsculas", L.buscarRutas(rutas, "LOPERENA").map((r) => r.id).join() === "2" && L.buscarRutas(rutas, "el carmen").length === 1);
ok("buscar por calle o carrera del tramo", L.buscarRutas(rutas, "c16a a 14").map((r) => r.id).join() === "2");
ok("buscar por código completo y por fragmento de 5 o más dígitos", L.buscarRutas(rutas, "2010011207003").length === 1 && L.buscarRutas(rutas, "11207").length === 2 && L.buscarRutas(rutas, "207").length === 0);
ok("buscar: todas las palabras deben aparecer", L.buscarRutas(rutas, "centro loperena").length === 0);
ok("normalizar quita tildes y colapsa espacios", L.normalizar("  Ñandú   Plaza  ") === "nandu plaza");
// ---------- Programación ----------
const noche = { dias: [1, 2, 3, 4, 5, 6, 7], hora_inicio: "22:00", hora_fin: "06:00" };
ok("turno nocturno a las 02:00 pertenece al día anterior", L.programacion(noche, "2026-11-10T02:00:00").fecha_servicio === "2026-11-09" && L.programacion(noche, "2026-11-10T23:00:00").fecha_servicio === "2026-11-10");
ok("turno nocturno: en franja de noche y fuera de día", L.programacion(noche, "2026-11-10T23:00:00").en_franja && L.programacion(noche, "2026-11-10T02:00:00").en_franja && !L.programacion(noche, "2026-11-10T12:00:00").en_franja);
ok("frecuencia L-J: el martes no está programada y el lunes sí", !L.programacion({ dias: [1, 4], hora_inicio: "06:00", hora_fin: "14:00" }, "2026-11-10T08:00:00").programada_hoy && L.programacion({ dias: [1, 4], hora_inicio: "06:00", hora_fin: "14:00" }, "2026-11-09T08:00:00").programada_hoy);
ok("el domingo es el día 7 (L-D lo incluye)", L.programacion({ dias: [7], hora_inicio: null, hora_fin: null }, "2026-11-15T10:00:00").programada_hoy && !L.programacion({ dias: [7], hora_inicio: null, hora_fin: null }, "2026-11-14T10:00:00").programada_hoy);
ok("ordenar: primero programadas hoy y en franja", L.ordenarPorProgramacion(rutas, "2026-11-10T08:00:00").map((r) => r.id).join() === "1,2,3");   // martes 08:00: la 3 (L-J, tarde) queda al final
ok("distancia: 1 grado de latitud ≈ 111 km y texto es-CO", Math.abs(L.distanciaM(10, -73, 11, -73) - 111195) < 200 && L.textoDistancia(120.4) === "120 m" && /km/.test(L.textoDistancia(1400)));
ok("fecha y hora del servidor en texto de persona", L.textoFechaHora("2026-11-12T07:05:00") === "12/11/2026 7:05 a. m." && L.textoFechaHora("2026-11-12T12:00:00") === "12/11/2026 12:00 p. m.");
// ---------- Formulario del catálogo ----------
const act = { codigo: "barrido", nombre: "Barrido", orden: 10, activa: true, fotos_max: 5,
  criterios: [{ codigo: "sst_herramientas", nombre: "¿Herramientas?", tipo_dato: "si_no", obligatorio: true, exige_foto_si: "no", etiqueta_foto: "sst_herramientas" }, { codigo: "sst_epp", nombre: "¿EPP?", tipo_dato: "si_no", obligatorio: true, exige_foto_si: "no", etiqueta_foto: "sst_epp" },
    { codigo: "largo", nombre: "Largo", tipo_dato: "decimal", obligatorio: false, minimo: 0, maximo: 10 }],
  fotos: [{ codigo: "ruta", nombre: "Fotos de la ruta", cantidad_min: 3, cantidad_max: 3, condicional: false, soporte_no_realizada: false }, { codigo: "sst_herramientas", nombre: "Evidencia herramientas", cantidad_min: 1, cantidad_max: 1, condicional: true, soporte_no_realizada: false },
    { codigo: "sst_epp", nombre: "Evidencia EPP", cantidad_min: 1, cantidad_max: 1, condicional: true, soporte_no_realizada: false }, { codigo: "evidencia", nombre: "Evidencia de que no se realizó", cantidad_min: 1, cantidad_max: 1, condicional: false, soporte_no_realizada: true }] };
let a = L.aplanarDatos(act, { sst_herramientas: "si", sst_epp: "si" }, "si");
ok("con SST afirmativo no se exigen fotos de evidencia", igual(a.datos, { sst_herramientas: true, sst_epp: true }) && a.fotosExigidas.length === 0 && igual(L.fotosNecesarias(act, "si", a.fotosExigidas).map((f) => f.etiqueta), ["ruta"]));
a = L.aplanarDatos(act, { sst_herramientas: "no", sst_epp: "no" }, "parcial");
ok("SST «No» exige la foto de evidencia de cada pregunta (3 + 2 fotos)", igual(a.fotosExigidas, ["sst_herramientas", "sst_epp"]) && L.fotosNecesarias(act, "parcial", a.fotosExigidas).reduce((s, f) => s + f.max, 0) === 5);
ok("«No se realizó»: sin preguntas y solo la foto de evidencia", igual(L.aplanarDatos(act, { sst_epp: "no" }, "no").datos, {}) && igual(L.fotosNecesarias(act, "no", []).map((f) => f.etiqueta), ["evidencia"]));
ok("falta una pregunta obligatoria", Object.keys(L.aplanarDatos(act, { sst_epp: "si" }, "si").errores).join() === "sst_herramientas");
ok("un número fuera de rango o mal escrito se rechaza; con coma decimal se acepta", "largo" in L.aplanarDatos(act, { sst_herramientas: "si", sst_epp: "si", largo: "11" }, "si").errores && "largo" in L.aplanarDatos(act, { sst_herramientas: "si", sst_epp: "si", largo: "x" }, "si").errores
  && L.aplanarDatos(act, { sst_herramientas: "si", sst_epp: "si", largo: "2,5" }, "si").datos.largo === 2.5);
ok("erroresDeEnvio: sin «¿Se realizó?», sin causal, sin fotos", L.erroresDeEnvio(act, { seRealizo: "", causal: "", valores: {}, fotosPorEtiqueta: {} })[0].includes("Indique si se realizó")
  && L.erroresDeEnvio(act, { seRealizo: "parcial", causal: "", valores: { sst_herramientas: "si", sst_epp: "si" }, fotosPorEtiqueta: { ruta: 3 } }).join().includes("causal"));
ok("erroresDeEnvio: completo = sin errores", L.erroresDeEnvio(act, { seRealizo: "si", causal: "", valores: { sst_herramientas: "si", sst_epp: "si" }, fotosPorEtiqueta: { ruta: 3 } }).length === 0 && L.erroresDeEnvio(act, { seRealizo: "no", causal: "clima", valores: {}, fotosPorEtiqueta: { evidencia: 1 } }).length === 0);
ok("erroresDeEnvio: 2 de 3 fotos de la ruta", L.erroresDeEnvio(act, { seRealizo: "si", causal: "", valores: { sst_herramientas: "si", sst_epp: "si" }, fotosPorEtiqueta: { ruta: 2 } }).some((e) => /2 de 3/.test(e)));
ok("contador de fotos", L.contadorFotos(2, 3, 3) === "2 de 3" && L.contadorFotos(1, 1, 4) === "1 de 4 (mínimo 1)");

// ---------- Cargador de capas: la capa de prueba de David ----------
const geo = existsSync(join(INS, "rutas_prueba.geojson")) ? readFileSync(join(INS, "rutas_prueba.geojson")) : null;
if (geo) {
  const capa = C.leerCapa(geo.toString("utf8"), "rutas_prueba.geojson");
  ok("GeoJSON de David: 3 líneas en EPSG:4326", capa.origen === "geojson" && capa.srid === 4326 && capa.filas.length === 3 && capa.filas.every((f) => f.geometry.type === "LineString"));
  ok("las columnas son «Codigo» y «Sectores» (no se supone ningún nombre)", igual(capa.columnas, ["Codigo", "Sectores"]));
  ok("el código llega como NÚMERO de 13 dígitos exacto y se vuelve texto sin perder precisión", capa.filas.every((f) => typeof f.atributos.Codigo === "number" && String(f.atributos.Codigo).length === 13) && String(capa.filas[0].atributos.Codigo) === "2010011207003" && capa.filas[2].atributos.Codigo === 2010011207008);
  ok("sin advertencias (13 dígitos caben en un entero exacto)", capa.advertencias.length === 0);
  ok("cada línea termina con un vértice repetido o casi repetido (se envía tal cual; lo limpia la base)", capa.filas.every((f) => f.geometry.coordinates.length === 4));
  ok("los atributos originales se conservan completos", capa.filas.every((f) => Object.keys(f.atributos).length === 2 && /Centro|Loperena/.test(String(f.atributos.Sectores))));
  ok("muestra de la columna elegida", igual(C.muestraColumna(capa.filas, "Codigo"), ["2010011207003", "2010011207004", "2010011207008"]));
  ok("huella SHA-256 de 64 caracteres y estable", (await C.sha256Hex(geo)).length === 64 && (await C.sha256Hex(geo)) === (await C.sha256Hex(new Uint8Array(geo))));
  ok("lotes: 3 geometrías en un solo lote desde la 1", igual(C.lotes(capa.filas).map((l) => [l.base, l.filas.length]), [[1, 3]]));
} else console.log("(sin rutas_prueba.geojson en insumos: se omite el bloque de la capa de David)");
const grandes = Array.from({ length: 450 }, (_, i) => ({ atributos: { c: i }, geometry: { type: "Point", coordinates: [0, 0] } }));
ok("lotes: 450 geometrías en lotes de 200, 200 y 50 con su orden inicial", igual(C.lotes(grandes).map((l) => [l.base, l.filas.length]), [[1, 200], [201, 200], [401, 50]]));
const pesadas = Array.from({ length: 10 }, () => ({ atributos: { t: "x".repeat(40000) }, geometry: { type: "Point", coordinates: [0, 0] } }));
ok("lotes: se parten también por tamaño (~300 KB)", C.lotes(pesadas).length >= 2 && C.lotes(pesadas).every((l) => JSON.stringify(l.filas).length < 360000));
ok("GeoJSON con «crs» EPSG:3116 declara su sistema", C.leerGeoJSON('{"type":"FeatureCollection","crs":{"type":"name","properties":{"name":"urn:ogc:def:crs:EPSG::3116"}},"features":[{"type":"Feature","properties":{"c":"1"},"geometry":{"type":"Point","coordinates":[1088977,1646645]}}]}').srid === 3116);
ok("un código de más de 15 dígitos como número produce una advertencia", C.leerGeoJSON('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"c":2010011207003123456},"geometry":{"type":"Point","coordinates":[0,0]}}]}').advertencias.length === 1);
ok("GeoJSON mal formado y capas vacías dan mensajes claros", (() => { try { C.leerGeoJSON("{no"); return false; } catch (e) { return /no es un GeoJSON/.test(e.message); } })() && (() => { try { C.leerGeoJSON('{"type":"FeatureCollection","features":[]}'); return false; } catch (e) { return /ningún objeto/.test(e.message); } })());
ok("un shapefile no se lee directamente: el mensaje propone la conversión", (() => { try { C.leerCapa("", "rutas.zip"); return false; } catch (e) { return /GeoJSON/.test(e.message) && /QGIS/.test(e.message); } })());
const kml = `<?xml version="1.0"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document>
<Placemark><name>Ruta A</name><description><![CDATA[Tramo <b>1</b>]]></description><ExtendedData><Data name="Codigo"><value>2010011207003</value></Data><SchemaData><SimpleData name="Zona">Centro &amp; Norte</SimpleData></SchemaData></ExtendedData>
<LineString><coordinates>-73.2436,10.4707,0 -73.2437,10.4742,0 -73.2430,10.4747,0</coordinates></LineString></Placemark>
<Placemark><name>Ruta B</name><MultiGeometry><LineString><coordinates>-73.1,10.4 -73.2,10.5</coordinates></LineString><LineString><coordinates>-73.3,10.4 -73.4,10.5</coordinates></LineString></MultiGeometry></Placemark>
<Placemark><name>Zona</name><Polygon><outerBoundaryIs><LinearRing><coordinates>-73.2,10.4 -73.1,10.4 -73.1,10.5 -73.2,10.4</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
</Document></kml>`;
const k = C.leerCapa(kml, "capa.kml");
ok("KML: lee línea, multilínea y polígono con sus atributos (nombre, descripción, ExtendedData)", k.origen === "kml" && k.srid === 4326 && k.filas.length === 3 && k.filas[0].geometry.type === "LineString" && k.filas[1].geometry.type === "MultiLineString" && k.filas[2].geometry.type === "Polygon"
  && k.filas[0].atributos.name === "Ruta A" && k.filas[0].atributos.description === "Tramo <b>1</b>" && k.filas[0].atributos.Codigo === "2010011207003" && k.filas[0].atributos.Zona === "Centro & Norte");
ok("KML: las coordenadas quedan en 2D (se descarta la altura)", igual(k.filas[0].geometry.coordinates[0], [-73.2436, 10.4707]) && k.columnas.includes("Codigo"));

// ---------- Lector del plan operativo (.xlsx real) ----------
if (existsSync(join(INS, "plan_operativo_aseo_2020.xlsx"))) {
  const buf = readFileSync(join(INS, "plan_operativo_aseo_2020.xlsx"));
  const hojas = await X.leerXlsx(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  ok("el libro trae 3 hojas: Barrido, Recolección y Puntos críticos", igual(hojas.map((h) => h.nombre), ["Barrido", "Recolección", "Puntos críticos"]));
  const { filas, porHoja, avisos } = X.planDesdeHojas(hojas);
  ok("444 rutas de barrido, 69 de recolección y 28 puntos críticos (541 + 28 = 569 filas… menos los puntos: 541 rutas)", porHoja["Barrido"] === 444 && porHoja["Recolección"] === 69 && porHoja["Puntos críticos"] === 28 && filas.length === 541 && avisos.length === 0);
  const f1 = filas[0];
  ok("primera ruta: código, turno, servicio, frecuencia, horas, sectores y km", f1.codigo === "2010011207001" && f1.clase === "ruta" && f1.turno === 1 && f1.servicio === "12" && f1.frecuencia === "07" && f1.hora_inicio === "06:00" && f1.hora_fin === "14:00"
    && f1.sectores === "Kenedy - C20B a 19C de K7A a 6" && f1.caracterizacion === "Comercial" && f1.km_ruta === 4.1);
  ok("el código decompone coherente con turno, servicio y frecuencia en las 513 rutas", filas.filter((f) => f.clase === "ruta").every((f) => f.codigo.length === 13 && Number(f.codigo[2]) === f.turno && f.codigo.slice(6, 8) === f.servicio && f.codigo.slice(8, 10) === f.frecuencia));
  ok("los 4 servicios del barrido", igual([...new Set(filas.slice(0, 444).map((f) => f.servicio))].sort(), ["12", "13", "14", "16"]));
  ok("recolección: horas que cruzan la medianoche (fin 00:00) se leen como texto HH:MM", filas.slice(444, 513).some((f) => f.hora_fin === "00:00") && filas.slice(444, 513).every((f) => /^\d\d:\d\d$/.test(f.hora_inicio) && /^\d\d:\d\d$/.test(f.hora_fin)));
  const p = filas.filter((f) => f.clase === "punto");
  ok("puntos críticos: 28 con código de 10 dígitos, servicio 44 y su ciclo como caracterización", p.length === 28 && p.every((x) => x.codigo.length === 10 && x.servicio === "44") && p[0].caracterizacion === "Mensual" && p[0].sectores.startsWith("Salida a Bosconia"));
  ok("no se guardan kilómetros al mes (solo km_ruta)", !("km_mes" in f1) && Object.keys(f1).join() === "codigo,clase,turno,servicio,frecuencia,hora_inicio,hora_fin,sectores,caracterizacion,km_ruta");
  ok("los 541 códigos son únicos", new Set(filas.map((f) => f.codigo)).size === filas.length);
} else console.log("(sin el plan operativo en insumos: se omite el bloque del .xlsx)");
ok("un archivo que no es .xlsx da un mensaje claro", await X.leerXlsx(new Uint8Array(100).buffer).then(() => false, (e) => /xlsx/.test(e.message)));

// ---------- Acta en PDF ----------
const jpg = (o) => ({ bytes: Uint8Array.from(Buffer.from(o.b64, "base64")), ancho: o.ancho, alto: o.alto });
const membrete = { logo: jpg(M.LOGO), banda: jpg(M.BANDA) };
const info = P.infoJpeg(membrete.logo.bytes);
ok("infoJpeg lee el tamaño del membrete", info.ancho === 530 && info.alto === 188 && info.componentes === 3);
const datos = { consecutivo: "BAR-000123", registradoEn: "12/11/2026 7:05 a. m.", fechaServicio: "2026-11-12", auditor: { nombre: "Auditor de Prueba Ñandú", correo: "auditor@emdupar.gov.co" }, actividad: "Barrido", modalidad: "Manual", servicio: "12 · Barrido Manual",
  ruta: { codigo: "2010011207003", sectores: "Centro, El Carmen - C19A a 17 de K9 a 6 " + "(tramo largo) ".repeat(12), turno: "Día", horario: "06:00 a 14:00", frecuencia: "L-M-Mi-J-V-S-D", km: 3.92 }, seRealizo: "Parcial", causal: "Condiciones climáticas",
  respuestas: [{ pregunta: "¿Cuenta con las herramientas?", respuesta: "No" }, { pregunta: "¿Usa los EPP?", respuesta: "Sí" }], observaciones: "Lluvia fuerte desde las 9:00 «sin paso» – tramo parcial; 100 % del tramo A.",
  posicion: { inicio: "10,47078, -73,24365", fin: "10,47400, -73,24301", precision: "8 m al enviar" }, marcas: ["Fuera de horario"], fotos: Array.from({ length: 5 }, (_, i) => ({ ...membrete.logo, etiqueta: i < 3 ? "Fotos de la ruta" : "Evidencia" })), sello: "ab12".repeat(16) };
const pdf = P.generarActaPdf(datos, membrete);
const texto = Buffer.from(pdf).toString("latin1");
ok("el PDF empieza con %PDF y termina con %%EOF", texto.startsWith("%PDF-1.4") && texto.trimEnd().endsWith("%%EOF"));
const startxref = Number(texto.match(/startxref\n(\d+)/)[1]);
ok("startxref apunta a la tabla de referencias", texto.slice(startxref, startxref + 4) === "xref");
const offs = [...texto.slice(startxref).matchAll(/(\d{10}) 00000 n /g)].map((m) => Number(m[1]));
ok("cada entrada de la tabla apunta a su objeto", offs.length > 5 && offs.every((o, i) => texto.slice(o).startsWith(`${i + 1} 0 obj`)));
ok("el PDF lleva los tipos de letra estándar con WinAnsi (tildes y ñ)", /\/BaseFont \/Helvetica /.test(texto) && /WinAnsiEncoding/.test(texto) && /Courier/.test(texto));
ok("las fotos van incrustadas como JPEG sin recodificar (DCTDecode)", (texto.match(/DCTDecode/g) ?? []).length >= 7);
ok("con 5 fotos el acta ocupa varias páginas", /\/Count [2-9]/.test(texto));
const dir = mkdtempSync(join(tmpdir(), "acta_pdf_")); const ruta1 = join(dir, "acta.pdf"); writeFileSync(ruta1, pdf);
const py = spawnSync("python3", ["-I", "-c", `import sys; from pypdf import PdfReader; r=PdfReader(sys.argv[1]); t=' '.join(p.extract_text() for p in r.pages); print(len(r.pages)); print('OK' if all(s in t for s in ['ACTA DE AUDITOR','BAR-000123','Auditor de Prueba','2010011207003','Parcial','Condiciones clim','Firma del auditor','ab12ab12']) else 'FALTA: '+t[:400])`, ruta1], { encoding: "utf8" });
if (py.status === 0) { const [n, estado] = py.stdout.trim().split("\n"); ok("un lector de PDF independiente (pypdf) abre el acta, cuenta sus páginas y encuentra su texto con tildes", Number(n) >= 2 && estado === "OK", py.stdout + py.stderr); if (process.env.GUARDAR_ACTA) { writeFileSync(process.env.GUARDAR_ACTA, pdf); } }
else console.log("(sin python3/pypdf: se omite la lectura independiente del PDF)");
const corto = P.generarActaPdf({ ...datos, fotos: [], respuestas: [], observaciones: null, causal: null, seRealizo: "Sí", ruta: { ...datos.ruta, sectores: "Mayales" } }, membrete);
ok("un acta corta cabe en una página", /\/Count 1/.test(Buffer.from(corto).toString("latin1")), String(Buffer.from(corto).toString("latin1").match(/\/Count \d+/)));
if (process.env.GUARDAR_ACTA) writeFileSync(process.env.GUARDAR_ACTA.replace(".pdf", "_corta.pdf"), corto);
ok("partirLineas respeta el ancho y las palabras largas", P.partirLineas("a ".repeat(100), 100, 10).every((l) => P.anchoTexto(l, 10) <= 100) && P.partirLineas("x".repeat(300), 100, 10).every((l) => P.anchoTexto(l, 10) <= 100));
ok("winAnsi: tildes, ñ, comillas angulares y rayas", igual(P.winAnsi("áéíóúñ«»¿¡"), [225, 233, 237, 243, 250, 241, 171, 187, 191, 161]) && P.winAnsi("–")[0] === 0x96);

console.log(fallas === 0 ? `RESULTADO: ${total} de ${total} pruebas correctas — SIN FALLAS` : `RESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas} FALLA(S)`);
process.exit(fallas === 0 ? 0 : 1);
