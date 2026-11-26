// [Code A] Geovisor único · Corte 1 (26-nov): lógica pura de los sectores (src/tecnica/sectores.ts) con los datos del paso 0 de producción
// (src/tecnica/impresion/sectores_datos.ts) y la configuración de impresión (src/tecnica/impresion/config.ts).
//   node scripts/prueba_sectores.mjs [paso0.json]     (-h: este uso). Con el JSON del paso 0, además compara el archivo generado con él.
import { createRequire } from "node:module"; import { join, dirname } from "node:path"; import { fileURLToPath } from "node:url"; import { mkdtempSync, readFileSync, writeFileSync } from "node:fs"; import { tmpdir } from "node:os";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log("Uso: node scripts/prueba_sectores.mjs [paso0.json]"); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}`); process.exit(2); }
const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const dir = mkdtempSync(join(tmpdir(), "sectores_")), entrada = join(dir, "e.ts"), out = join(dir, "s.mjs");
writeFileSync(entrada, `export * from ${JSON.stringify(join(raiz, "src/tecnica/sectores.ts"))}; export * as C from ${JSON.stringify(join(raiz, "src/tecnica/impresion/config.ts"))};
export { ORIGEN_SECTORES } from ${JSON.stringify(join(raiz, "src/tecnica/impresion/sectores_datos.ts"))};`);
await build({ entryPoints: [entrada], bundle: true, format: "esm", platform: "node", outfile: out, logLevel: "error" });
const S = await import(out);
let t = 0, f = 0; const ok = (n, c, d = "") => { t++; if (!c) f++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + d}`); };

const subs = S.SECTORES.filter((s) => s.clase === "subsector"), secs = S.SECTORES.filter((s) => s.clase === "sector");
ok("los datos son los del paso 0 de producción", /paso 0 de producción/.test(S.ORIGEN_SECTORES), S.ORIGEN_SECTORES);
ok("36 SEC: 7 sectores y 29 subsectores, códigos y nombres sin repetir", S.SECTORES.length === 36 && secs.length === 7 && subs.length === 29
  && new Set(S.SECTORES.map((s) => s.codigo)).size === 36 && new Set(S.SECTORES.map((s) => s.nombre)).size === 36);
const cruzados = subs.filter((s) => { const l = S.leerNombreSector(s.nombre); return !l || l.sector !== s.sector || l.sub !== s.sub; });
ok("comprobación cruzada: los 29 nombres de subsector dicen el mismo sector que su atributo", cruzados.length === 0, cruzados.map((s) => `${s.nombre}→${s.sector}`).join(", "));
ok("los 7 sectores: «Sector N» con su atributo, del 1 al 7", secs.map((s) => s.sector).sort().join() === "1,2,3,4,5,6,7" && secs.every((s) => S.leerNombreSector(s.nombre)?.sector === s.sector && s.sub === null));
ok("cada sector tiene al menos un subsector y todo subsector cae en un sector que existe", secs.every((s) => S.subsectoresDe(s.sector).length > 0) && subs.every((u) => secs.some((s) => s.sector === u.sector)));
ok("leer nombres: «Subsector 7.2» → 7 y 7.2; «Sector 3» → 3; basura → null", JSON.stringify(S.leerNombreSector("Subsector 7.2")) === JSON.stringify({ sector: "7", sub: "7.2" })
  && JSON.stringify(S.leerNombreSector(" Sector  3 ")) === JSON.stringify({ sector: "3", sub: null }) && S.leerNombreSector("Zona 4") === null && S.leerNombreSector(null) === null);
ok("puntos de etiqueta dentro de Valledupar (la extensión Total)", S.SECTORES.every((s) => s.lon >= S.C.PAGINAS[0].extension.oeste - 0.01 && s.lon <= S.C.PAGINAS[0].extension.este + 0.01 && s.lat >= S.C.PAGINAS[0].extension.sur && s.lat <= S.C.PAGINAS[0].extension.norte));
// colores
const colores = Object.values(S.C.COLOR_SECTOR);
ok("7 colores distintos, ninguno es el de la red (azul #1F5FA8, café #8A5A2B, morado #6D28D9)", colores.length === 7 && new Set(colores).size === 7 && !colores.some((c) => ["#1F5FA8", "#8A5A2B", "#6D28D9"].includes(c.toUpperCase())));
const expr = S.exprColorSector();
ok("la expresión del color cubre los 36 nombres y el subsector lleva el color de su sector", expr[0] === "match" && S.SECTORES.every((s) => { const i = expr.indexOf(s.nombre); return i > 1 && expr[i + 1] === S.C.COLOR_SECTOR[s.sector]; }));
ok("relleno: sector 15–20 %, subsector tenue", S.C.ESTILO_SECTOR.rellenoSector >= 0.15 && S.C.ESTILO_SECTOR.rellenoSector <= 0.2 && S.C.ESTILO_SECTOR.rellenoSubsector < 0.1);
// interruptores
const V = S.VER_SECTORES_INICIAL;
ok("todo encendido: nada oculto", S.nombresOcultos(V).length === 0);
ok("«Subsectores» apagado: se ocultan los 29 y ningún sector", (() => { const o = S.nombresOcultos({ ...V, subsectores: false }); return o.length === 29 && o.every((n) => n.startsWith("Subsector")); })());
ok("«Sectores» apagado: se ocultan los 7 y ningún subsector", (() => { const o = S.nombresOcultos({ ...V, sectores: false }); return o.length === 7 && o.every((n) => /^Sector /.test(n)); })());
ok("el renglón del sector 1 apaga el sector y sus subsectores", (() => { const o = S.nombresOcultos({ ...V, apagados: ["s:1"] }); return o.length === 1 + S.subsectoresDe("1").length && o.includes("Sector 1"); })());
ok("un renglón de subsector apaga solo ese subsector", JSON.stringify(S.nombresOcultos({ ...V, apagados: [`u:${subs[0].sub}`] })) === JSON.stringify([subs[0].nombre]));
ok("ficha corta: «Subsector 1.1» → sector 1", S.fichaSector("Subsector 1.1")?.sector === "Sector 1" && S.fichaSector("Sector 5")?.titulo === "Sector 5" && S.fichaSector("Otra cosa") === null);
ok("etiquetas: 36 puntos; el sector dice «Sector N» y el subsector solo «N.M»", (() => { const e = S.etiquetasSectores().features; return e.length === 36 && e.filter((x) => x.properties.clase === "sector").every((x) => /^Sector \d$/.test(x.properties.texto))
  && e.filter((x) => x.properties.clase === "subsector").every((x) => /^\d\.\d{1,2}$/.test(x.properties.texto)); })());
// impresión
const [P1, P2] = S.C.PAGINAS;
ok("siempre 2 páginas y en este orden: Total y Urbano", S.C.PAGINAS.length === 2 && P1.clave === "total" && P2.clave === "urbano");
ok("Total: O -73,29679 · S 10,38185 · E -73,21382 · N 10,50684; Urbano: el 96 % central del catastro", P1.extension.oeste === -73.29679 && P1.extension.sur === 10.38185 && P1.extension.este === -73.21382 && P1.extension.norte === 10.50684
  && P2.extension.oeste === -73.28887 && P2.extension.sur === 10.4254 && P2.extension.este === -73.22844 && P2.extension.norte === 10.49198);
ok("margen 3 %; etiquetas: sectores en Total, también subsectores en la Urbana; ubicación solo en la Urbana", S.C.MARGEN_EXTENSION === 0.03 && P1.etiquetas.sectores && !P1.etiquetas.subsectores && P2.etiquetas.subsectores && !P1.ubicacion && P2.ubicacion);
ok("zoom de dibujo: Total z14 (red completa), Urbano z15 (nodos)", P1.zoom === 14 && P2.zoom === 15);
// el paso 0 (si se da): el archivo generado coincide con él
const paso0 = args[0];
if (paso0) {
  const d = JSON.parse(readFileSync(paso0, "utf8"))["01_sectores"];
  ok("el archivo generado es el paso 0: mismos 36 códigos, sector del atributo y punto de la etiqueta", d.length === 36 && d.every((x) => { const s = S.SECTORES.find((y) => y.codigo === x.codigo);
    return s && s.nombre === x.nombre && s.sector === String(Number(x.sector_atributo)) && s.lon === x.lon_etiqueta && s.lat === x.lat_etiqueta; }));
}
console.log(`\nRESULTADO: ${t - f} de ${t}${f ? "" : " — SIN FALLAS"}`); process.exit(f ? 1 : 0);
