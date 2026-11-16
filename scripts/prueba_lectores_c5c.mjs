// Prueba de los lectores del Cargue de capas (Corte 5c) en Node, con archivos REALES armados con ogr2ogr desde los shapefiles de origen
// (SHP en zip en 4326, 9377 y 3116; GeoPackage con 3 capas en 9377; GeoJSON; CSV con X y Y en 3116). KML y Excel se prueban en Chrome (usan DOMParser).
// Uso: node scripts/prueba_lectores_c5c.mjs <carpeta de archivos>
import { createRequire } from "node:module";
import { readFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIR = process.argv[2];
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const out = mkdtempSync(join(tmpdir(), "lect_"));
await build({ entryPoints: [join(raiz, "src/tecnica/cargue/lectores.ts")], bundle: true, format: "esm", platform: "neutral", outfile: join(out, "l.mjs"), logLevel: "error" });
const L = await import(join(out, "l.mjs"));
const res = [];
const reg = (n, ok, d = "") => { res.push(ok); console.log((ok ? "OK    " : "FALLA ") + n + (d ? " · " + d : "")); };
const archivo = (n) => new File([readFileSync(join(DIR, n))], n);
const pt = (w) => { const m = /(-?[0-9.]+) (-?[0-9.]+)/.exec(w ?? ""); return m ? [Number(m[1]), Number(m[2])] : null; };

let t = Date.now(); const acu = await L.leerArchivo(archivo("acueducto_4326.zip")); const sAcu = Date.now() - t;
const a = acu[0];
reg("L01 SHP en zip (acueducto real): 1 capa, 10.578 tramos, WGS 84 por el .prj, ID única", acu.length === 1 && a.formato === "shp" && a.filas.length === 10578 && a.srid === 4326
  && L.revisarLlave(a.filas, "ID").unica && a.columnas.includes("STARTNODID"), `${a.filas.length} filas, srid ${a.srid} (${a.sridComo}), ${sAcu} ms`);
reg("L02 las líneas: LINESTRING con coordenadas de Valledupar escritas como en la carga inicial; los atributos con su tipo (ID número, LABEL texto, C número)",
  Object.keys(a.tipos).every((k) => k === "LINESTRING" || k === "MULTILINESTRING") && (() => { const p = pt(a.filas[0].wkt); return p && p[0] > -73.4 && p[0] < -73.1 && p[1] > 10.3 && p[1] < 10.6; })()
  && typeof a.filas[0].atributos.ID === "number" && typeof a.filas[0].atributos.LABEL === "string" && typeof a.filas[0].atributos.C === "number"
  && a.filas[0].wkt.startsWith("LINESTRING(-73.2545768 10.460241722, -73.254880062 10.459671493)"), JSON.stringify(a.tipos) + " " + a.filas[0].wkt.slice(0, 80));
reg("L03 la llave propuesta del acueducto es una columna única (ID o LABEL)", ["ID", "LABEL"].includes(L.proponerLlave(a)), L.proponerLlave(a));
const p9 = (await L.leerArchivo(archivo("pozos_9377.zip")))[0];
reg("L04 SHP en EPSG 9377 (pozos reales reproyectados por GDAL): 9.146 puntos y el .prj se reconoce como Origen Nacional", p9.filas.length === 9146 && p9.srid === 9377,
  `${p9.filas.length}, srid ${p9.srid} (${p9.sridComo}) · ${p9.filas[0].wkt}`);
const c3 = (await L.leerArchivo(archivo("conductos_3116.zip")))[0];
reg("L05 SHP en EPSG 3116 (conductos): 9.064 líneas y MAGNA Bogotá por el .prj", c3.filas.length === 9064 && c3.srid === 3116 && /^LINESTRING\(10\d{5}/.test(c3.filas[0].wkt),
  `${c3.filas.length}, srid ${c3.srid} (${c3.sridComo}) · ${c3.filas[0].wkt.slice(0, 70)}`);
t = Date.now(); const gp = await L.leerArchivo(archivo("alcantarillado_9377.gpkg")); const sGp = Date.now() - t;
const g = Object.fromEntries(gp.map((x) => [x.nombre, x]));
reg("L06 GeoPackage (lector propio de SQLite): 3 capas con su nombre, EPSG 9377 por gpkg_spatial_ref_sys y los conteos de ogrinfo",
  gp.length === 3 && g.conductos?.filas.length === 9064 && g.pozos?.filas.length === 9146 && g.descargas?.filas.length === 4 && gp.every((x) => x.srid === 9377),
  gp.map((x) => `${x.nombre} ${x.filas.length} ${x.srid} ${JSON.stringify(x.tipos)}`).join(" · ") + ` · ${sGp} ms`);
const porLabel = new Map(p9.filas.map((f) => [f.atributos.LABEL, pt(f.wkt)]));
let maxd = 0, comparados = 0;
for (const f of g.pozos.filas) { const q = porLabel.get(f.atributos.LABEL), p = pt(f.wkt); if (q && p) { comparados++; maxd = Math.max(maxd, Math.hypot(p[0] - q[0], p[1] - q[1])); } }
reg("L07 el GeoPackage y el SHP traen las mismas coordenadas por LABEL (a menos de 1 cm)", comparados > 8000 && maxd < 0.01, `${comparados} comparados, máx. ${maxd.toFixed(4)} m`);
reg("L08 las líneas del GeoPackage son LINESTRING o MULTILINESTRING y traen sus atributos (sin la columna de geometría)",
  Object.keys(g.conductos.tipos).every((k) => /LINESTRING/.test(k)) && g.conductos.columnas.includes("LABEL") && !g.conductos.columnas.includes("geom") && typeof g.conductos.filas[0].atributos.fid === "number",
  g.conductos.columnas.slice(0, 8).join(","));
const gj = (await L.leerArchivo(archivo("descargas.geojson")))[0];
reg("L09 GeoJSON: 4 descargas, WGS 84 (sin «crs»)", gj.filas.length === 4 && gj.srid === 4326 && gj.tipos.POINT === 4, gj.sridComo);
const cs = (await L.leerArchivo(archivo("pozos_3116.csv")))[0];
reg("L10 CSV con «;»: 9.146 filas, las dos columnas «X» se distinguen (X y X_2), X y Y propuestas, y MAGNA Bogotá por el rango", cs.filas.length === 9146 && cs.tabla
  && cs.columnas.includes("X_2") && cs.xy?.x === "X" && cs.xy?.y === "Y" && cs.srid === 3116, `${cs.columnas.slice(0, 4).join(",")} … · ${cs.sridComo}`);
const f3 = L.filasConXY(cs, cs.xy, 3116);
reg("L11 la geometría del CSV sale de X y Y (los números con coma decimal también se leen)", f3.every((f) => f.wkt && f.wkt.startsWith("POINT(")) && f3[0].wkt.includes("1087628.92"), f3[0].wkt);
const lotes = L.enLotes(a.filas.map((f, i) => ({ orden: i + 1, wkt: f.wkt, atributos: f.atributos })));
reg("L12 los lotes del acueducto: de 200 filas o menos y menos de 450 KB cada uno", lotes.every((x) => x.length <= 200 && JSON.stringify(x).length < 450000) && lotes.reduce((s, x) => s + x.length, 0) === 10578,
  `${lotes.length} lotes, el mayor de ${Math.max(...lotes.map((x) => JSON.stringify(x).length))} bytes`);
reg("L13 la huella SHA-256 es la del archivo", (await L.sha256Hex("abc")) === "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
reg("L14 la detección del .prj: Origen Nacional, Bogotá, WGS 84 y un sistema raro",
  L.sridDePrj('PROJCS["MAGNA-SIRGAS_Origen-Nacional",GEOGCS["GCS_MAGNA"],PARAMETER["central_meridian",-73.0]]') === 9377
  && L.sridDePrj('PROJCS["MAGNA_Colombia_Bogota",GEOGCS["GCS_MAGNA"]]') === 3116 && L.sridDePrj('GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984"]]') === 4326
  && L.sridDePrj('PROJCS["WGS_1984_UTM_Zone_18N",GEOGCS["GCS_WGS_1984"]]') === null);
let falloZip = ""; try { await L.leerArchivo(new File([new Uint8Array([1, 2, 3])], "x.zip")); } catch (e) { falloZip = e.message; }
let falloShp = ""; try { await L.leerArchivo(new File([new Uint8Array([1])], "x.shp")); } catch (e) { falloShp = e.message; }
reg("L15 un zip dañado y un .shp suelto dan un mensaje claro", /zip válido/.test(falloZip) && /comprímalos juntos en un \.zip/.test(falloShp), falloZip + " · " + falloShp);
// L16: lo que leen estos lectores del shapefile de origen es lo MISMO que subió la carga inicial del 1a (shp.py): la geometría byte a byte y los atributos por valor
const LOTES = process.argv[3];
if (LOTES) {
  const { readdirSync } = await import("node:fs");
  const del1a = new Map();
  for (const f of readdirSync(LOTES).filter((x) => x.startsWith("acueducto_"))) {
    for (const m of readFileSync(join(LOTES, f), "utf8").matchAll(/\$lote\$(\[.*?\])\$lote\$/gs)) for (const x of JSON.parse(m[1])) del1a.set(x.atributos.ID, x);
  }
  const mismoValor = (p, q) => Object.keys(p).length === Object.keys(q).length && Object.entries(p).every(([k, v]) => (typeof v === "number" ? Number(q[k]) === v : q[k] === v));
  let geomDistinta = 0, attrDistintos = 0, ejemplo = "";
  for (const f of a.filas) {
    const x = del1a.get(f.atributos.ID);
    if (!x) { geomDistinta++; continue; }
    if (x.wkt.replace(/, /g, ",") !== f.wkt.replace(/, /g, ",")) { geomDistinta++; ejemplo ||= `${x.wkt.slice(0, 60)} / ${f.wkt.slice(0, 60)}`; }
    if (!mismoValor(f.atributos, x.atributos)) { attrDistintos++; ejemplo ||= JSON.stringify(f.atributos).slice(0, 120) + " / " + JSON.stringify(x.atributos).slice(0, 120); }
  }
  reg("L16 el acueducto leído aquí es el mismo que subió la carga inicial del 1a: 10.578 tramos con la geometría idéntica y los atributos con el mismo valor",
    del1a.size === 10578 && geomDistinta === 0 && attrDistintos === 0, `${del1a.size} en el 1a · geometría distinta ${geomDistinta} · atributos distintos ${attrDistintos} · ${ejemplo}`);
}
console.log(`RESULTADO: ${res.filter(Boolean).length} de ${res.length}`);
