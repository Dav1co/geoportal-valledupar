// [Code B] Cuadernos de análisis: la lógica PURA (src/tecnica/cuadernos/modelo.ts) en Node, sin navegador. Uso: node scripts/prueba_cuadernos_modelo.mjs
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log("Uso: node scripts/prueba_cuadernos_modelo.mjs"); process.exit(0); }
if (args.length) { console.error(`Opción desconocida: ${args[0]}`); process.exit(2); }
const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const { buildSync } = createRequire(join(raiz, "package.json"))("esbuild");
const sal = join(mkdtempSync(join(tmpdir(), "cua_modelo_")), "modelo.mjs");
buildSync({ entryPoints: [join(raiz, "src/tecnica/cuadernos/modelo.ts")], bundle: true, format: "esm", platform: "node", outfile: sal, logLevel: "error" });
const M = await import(sal);
let n = 0, mal = 0; const ok = (t, c, d = "") => { n++; if (!c) mal++; console.log((c ? "OK    " : "FALLA ") + t + (c ? "" : " → " + d)); };
const guardada = { id: "11111111-1111-4111-8111-111111111111", version: 2, creada_en_version: 2, tipo: "zona", subtipo: null, sistema: null, categoria: null, nota: "n", estilo: null,
  geom: M.poligono([[-73.25, 10.46], [-73.24, 10.46], [-73.24, 10.47]]), radio_m: null, conteo_predios: 10, conteo_contratos: 9, activo_codigo: null, sector: "3", subsector: null };
const nueva = M.marcaNueva({ tipo: "problema", subtipo: "baja_presion", geom: M.punto(-73.2512345678, 10.4612345678) });
ok("01 una marca nueva nace con identificador propio y 7 decimales", /^[0-9a-f-]{36}$/.test(nueva.marca_id) && nueva.geom.coordinates[0] === -73.2512346);
let pend = { [nueva.marca_id]: nueva };
ok("02 lo visible = guardadas + nuevas", M.marcasVisibles([guardada], pend).length === 2 && M.marcasVisibles([guardada], pend)[1].pendiente === true);
pend = M.conCambio([guardada], pend, nueva.marca_id, { nota: "hola" });
ok("03 cambiar una nueva la deja «nueva»", pend[nueva.marca_id].op === "nueva" && pend[nueva.marca_id].nota === "hola");
pend = M.conCambio([guardada], pend, guardada.id, { nota: "otra" });
ok("04 cambiar una guardada crea un «cambia» con su estado completo; la zona que no se movió conserva su conteo", pend[guardada.id].op === "cambia" && pend[guardada.id].tipo === "zona" && M.marcasVisibles([guardada], pend)[0].conteo_predios === 10);
const movida = M.conCambio([guardada], {}, guardada.id, { geom: M.poligono([[-73.25, 10.46], [-73.24, 10.46], [-73.24, 10.48]]) });
ok("05 la zona que se movió pierde el conteo y el sector hasta guardar", M.marcasVisibles([guardada], movida)[0].conteo_predios === null && M.marcasVisibles([guardada], movida)[0].sector === null);
pend = M.conAnulacion([guardada], pend, nueva.marca_id, "");
ok("06 quitar una nueva la descarta (no se manda nada)", !(nueva.marca_id in pend));
pend = M.conAnulacion([guardada], pend, guardada.id, "ya no aplica");
ok("07 quitar una guardada la ANULA con motivo y sale de lo visible", pend[guardada.id].op === "anula" && M.marcasVisibles([guardada], pend).length === 0);
const env = M.cambiosParaGuardar({ a: nueva, b: pend[guardada.id] });
ok("08 lo que se manda: sin nulos y solo claves conocidas", JSON.stringify(Object.keys(env[0]).sort()) === JSON.stringify(["geom", "marca_id", "op", "subtipo", "tipo"]) && JSON.stringify(Object.keys(env[1]).sort()) === JSON.stringify(["marca_id", "motivo", "op"]));
ok("09 distancia: 0,01° de latitud ≈ 1.112 m", Math.abs(M.distancia([-73.25, 10.46], [-73.25, 10.47]) - 1111.95) < 1);
ok("10 área de un cuadro de 0,01° ≈ 1,216 km² en Valledupar", Math.abs(M.area([[-73.25, 10.46], [-73.24, 10.46], [-73.24, 10.47], [-73.25, 10.47]]) / 1e6 - 1.2159) < 0.005, String(M.area([[-73.25, 10.46], [-73.24, 10.46], [-73.24, 10.47], [-73.25, 10.47]])));
const recta = Array.from({ length: 300 }, (_, i) => [-73.25 + i * 0.00001, 10.46 + (i % 2) * 0.000001]);
ok("11 la mano alzada se aligera (300 puntos casi en línea → pocos) y conserva los extremos", M.aligerar(recta).length < 10 && M.aligerar(recta)[0] === recta[0] && M.aligerar(recta).at(-1) === recta.at(-1), String(M.aligerar(recta).length));
ok("12 la caja de Valledupar es la del servidor", M.dentro(-73.25, 10.46) && !M.dentro(-74.08, 4.6) && M.CAJA.oeste === -73.35 && M.CAJA.norte === 10.56);
ok("13 el aviso de la nota es el que pidió David", M.AVISO_NOTA === "No escriba nombres, cédulas ni teléfonos");
console.log(`\nRESULTADO: ${n - mal} de ${n}${mal ? "" : " — SIN FALLAS"}`); process.exit(mal ? 1 : 0);
