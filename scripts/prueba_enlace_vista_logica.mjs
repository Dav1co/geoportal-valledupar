// «Compartir vista» del mapa comercial (24-nov) · lógica PURA de src/areas/enlaceVista.ts: leer el hash y decidir la pantalla inicial. Sin red ni navegador.
// Uso: node scripts/prueba_enlace_vista_logica.mjs      (-h | --help: este uso; cualquier otra opción es un error)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
for (const a of process.argv.slice(2)) { if (a === "-h" || a === "--help") { console.log("Uso: node scripts/prueba_enlace_vista_logica.mjs"); process.exit(0); } console.error(`Opción desconocida: ${a}`); process.exit(2); }
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (f) => ts.transpileModule(readFileSync(join(aqui, "../src/areas", f), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");
const urlAreas = aUrl(compilar("areas.ts"));
const E = await import(aUrl(compilar("enlaceVista.ts").replace(/from\s+["']\.\/areas["']/, `from "${urlAreas}"`)));
let n = 0, malas = 0;
const ok = (nombre, c, d = "") => { n++; if (!c) malas++; console.log(`${c ? "OK   " : "FALLA"} ${nombre}${c ? "" : "  → " + d}`); };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const A = (o) => ({ comercial: false, tecnica: false, campo: false, aseo: false, ...o });

ok("01 sin hash: null (todo como hoy)", E.leerHash("") === null && E.leerHash("#") === null);
ok("02 la vista completa del botón «Compartir vista»", igual(E.leerHash("#v=-73.253200,10.463100,17.50&c=sin&e=DESOCUPADO&b=satelital&t=0"),
  { inicial: { lng: -73.2532, lat: 10.4631, zoom: 17.5 }, filtro: "sin", estado: "DESOCUPADO", base: "satelital", terrenos: false }));
ok("03 solo la vista: los demás por omisión", igual(E.leerHash("#v=-73.25,10.46,15"), { inicial: { lng: -73.25, lat: 10.46, zoom: 15 }, filtro: "todos", estado: "", base: "calles", terrenos: true }));
ok("04 vistas inválidas no cuentan como enlace", ["#v=abc,10,15", "#v=-73.25,10.46", "#v=-73.25,,15", "#v=200,10,15", "#v=-73,95,15", "#v=-73,10,30", "#v=-73,10,-1", "#v=1,2,3,4", "#c=sin"]
  .every((h) => !E.esEnlaceVista(h)));
ok("05 valores raros de c, e, b y t caen a los de siempre", igual(E.leerHash("#v=-73.25,10.46,15&c=x&e=OTRO&b=x&t=1"), { inicial: { lng: -73.25, lat: 10.46, zoom: 15 }, filtro: "todos", estado: "", base: "calles", terrenos: true }));
ok("06 el enlace del geovisor técnico no es un enlace de vista", !E.esEnlaceVista("#geovisor=abcdefghij"));
const dual = A({ comercial: true, tecnica: true }), soloCom = A({ comercial: true }), soloTec = A({ tecnica: true }), soloCampo = A({ campo: true }), nada = A({});
ok("07 dual con enlace: el mapa comercial directo, sin la ventana de entrada", igual(E.pantallaConEnlace(dual, { vista: true, geovisor: false }), { pantalla: "comercial", aviso: null }));
ok("08 dual sin enlace: la ventana de entrada (como hoy)", igual(E.pantallaConEnlace(dual, { vista: false, geovisor: false }), { pantalla: "entrada", aviso: null }));
ok("09 solo Comercial con enlace: el mapa", igual(E.pantallaConEnlace(soloCom, { vista: true, geovisor: false }), { pantalla: "comercial", aviso: null }));
ok("10 solo Técnica con enlace: su pantalla y el aviso", igual(E.pantallaConEnlace(soloTec, { vista: true, geovisor: false }), { pantalla: "tecnica", aviso: E.AVISO_SIN_COMERCIAL }));
ok("11 solo campo con enlace: su pantalla y el aviso", igual(E.pantallaConEnlace(soloCampo, { vista: true, geovisor: false }), { pantalla: "campo", aviso: E.AVISO_SIN_COMERCIAL }));
ok("12 sin módulos con enlace: «sin módulos» y el aviso", igual(E.pantallaConEnlace(nada, { vista: true, geovisor: false }), { pantalla: "sin_modulos", aviso: E.AVISO_SIN_COMERCIAL }));
ok("13 el enlace del geovisor sigue abriendo Técnica (dual)", igual(E.pantallaConEnlace(dual, { vista: false, geovisor: true }), { pantalla: "tecnica", aviso: null }));
ok("14 el texto del aviso es el pedido", E.AVISO_SIN_COMERCIAL === "Este enlace es del mapa Comercial y su usuario no tiene acceso a él.");

console.log(`\nRESULTADO: ${n - malas} de ${n} pruebas correctas${malas ? "" : " — SIN FALLAS"}`);
process.exit(malas ? 1 : 0);
