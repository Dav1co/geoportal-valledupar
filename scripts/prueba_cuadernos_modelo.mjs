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
// ---------- deshacer y rehacer ----------
{ const h = M.historiaVacia(); let p = {};
  const paso = (q, clave) => { M.anotar(h, p, clave); p = q; };
  paso({ a: 1 }); paso({ a: 1, b: 1 }); paso({ a: 1, b: 2 }, "nota:b"); paso({ a: 1, b: 3 }, "nota:b");
  ok("14 escribir varias veces la misma nota es UN paso; los demás cambios, uno cada uno (3 pasos)", h.pasado.length === 3);
  const u1 = M.deshacer(h, p); p = u1; const u2 = M.deshacer(h, p); p = u2;
  ok("15 ↶ ↶ vuelve dos pasos y ↷ los rehace en orden", JSON.stringify(u1) === '{"a":1,"b":1}' && JSON.stringify(u2) === '{"a":1}' && JSON.stringify(M.rehacer(h, p)) === '{"a":1,"b":1}');
  p = { a: 1, b: 1 }; paso({ z: 9 });
  ok("16 un cambio nuevo después de deshacer borra lo que se podía rehacer; sin pasos, ↶ no hace nada", M.rehacer(h, p) === null && M.deshacer(M.historiaVacia(), p) === null); }
// ---------- mover y encuadrar ----------
{ const z = M.trasladar(guardada.geom, 0.001, -0.002);
  ok("17 trasladar mueve la figura completa (mismos vértices, corridos)", z.coordinates[0].length === guardada.geom.coordinates[0].length && Math.abs(z.coordinates[0][0][0] - (-73.249)) < 1e-9 && Math.abs(z.coordinates[0][0][1] - 10.458) < 1e-9 && M.figuraDentro(z) && !M.figuraDentro(M.trasladar(guardada.geom, 1, 0)));
  const c = M.encuadre([{ geom: M.punto(-73.25, 10.46), radio_m: 200 }, { geom: M.punto(-73.248, 10.462), radio_m: null }]);
  ok("18 el encuadre del detalle cubre todas las marcas (el círculo con su radio) con margen", c.oeste < -73.25 - 0.0018 && c.este > -73.248 && c.sur < 10.46 - 0.0018 && c.norte > 10.462, JSON.stringify(c));
  ok("19 sin marcas no hay página de detalle; una sola marca da un encuadre mínimo (~300 m)", M.encuadre([]) === null && (() => { const u = M.encuadre([{ geom: M.punto(-73.25, 10.46), radio_m: null }]); return u.este - u.oeste > 0.0025 && u.este - u.oeste < 0.004; })());
  ok("20 el zoom del detalle queda entre 14 y 18 y el paso de la cuadrícula da 4 marcas o más", M.zoomDeEncuadre(c, 0.887) >= 14 && M.zoomDeEncuadre(c, 0.887) <= 18 && (c.este - c.oeste) / M.pasoDeEncuadre(c) >= 4 && M.zoomDeEncuadre({ oeste: -73.3, sur: 10.38, este: -73.2, norte: 10.5 }, 0.887) === 14); }
// ---------- el post-it no tapa pines ni etiquetas ----------
{ const sal2 = sal.replace("modelo.mjs", "pintar.mjs");
  buildSync({ entryPoints: [join(raiz, "src/tecnica/cuadernos/pintar.ts")], bundle: true, format: "esm", platform: "node", outfile: sal2, logLevel: "error" });
  const P = await import(sal2);
  const x = { font: "", measureText: (t) => ({ width: t.length * 6.5 }) };
  const l = { x, k: 1, mpp: () => 1, proy: (lon, lat) => [(lon + 73.26) * 100000, (10.47 - lat) * 100000] };
  const m = (id, tipo, lon, lat, extra = {}) => ({ id, tipo, subtipo: null, sistema: null, categoria: null, nota: null, estilo: null, geom: M.punto(lon, lat), radio_m: null, conteo_predios: null, conteo_contratos: null, activo_codigo: null, sector: null, subsector: null, version: 1, creada_en_version: 1, ...extra });
  const nota = m("n", "postit", -73.25, 10.46, { nota: "revisar con el macromedidor del sector" });
  const solo = P.disponerPostits(l, [nota]).get("n");
  const [cx, cy] = l.proy(-73.25, 10.46);
  ok("21 un post-it solo va arriba de su punto, centrado", Math.abs(solo.x0 + solo.w / 2 - cx) < 1 && solo.y0 + solo.h < cy);
  const pin = m("p", "problema", -73.25, 10.46 + 0.0003, { subtipo: "baja_presion" });      // un pin 30 px arriba: justo donde iría la nota
  const zona = { ...m("z", "zona", 0, 0, { conteo_predios: 256, conteo_contratos: 250 }), geom: M.poligono([[-73.2512, 10.4606], [-73.2488, 10.4606], [-73.2488, 10.4612], [-73.2512, 10.4612]]) };
  const otra = m("n2", "postit", -73.25, 10.46, { nota: "otra nota en el mismo punto" });
  const d = P.disponerPostits(l, [nota, pin, zona, otra]);
  const choca = (a, b) => a.x0 < b.x0 + b.w && a.x0 + a.w > b.x0 && a.y0 < b.y0 + b.h && a.y0 + a.h > b.y0;
  const [px, py] = l.proy(-73.25, 10.4603), cajaPin = { x0: px - 15, y0: py - 37, w: 30, h: 38 };
  const zc = [[-73.2512, 10.4606], [-73.2488, 10.4606], [-73.2488, 10.4612], [-73.2512, 10.4612]].map(([a, b]) => l.proy(a, b)), zx = zc.reduce((s, q) => s + q[0], 0) / 4, zy = zc.reduce((s, q) => s + q[1], 0) / 4;
  const etq = { x0: zx - 100, y0: zy - 10, w: 200, h: 20 };
  ok("22 con un pin y la etiqueta de una zona encima, el post-it se corre: no tapa el pin, ni la etiqueta, ni al otro post-it", [...d.values()].every((c) => !choca(c, cajaPin) && !choca(c, etq)) && !choca(d.get("n"), d.get("n2")), JSON.stringify([...d.values()].map((c) => [Math.round(c.x0 - cx), Math.round(c.y0 - cy)])));
  ok("23 la leyenda del cuaderno lista todos los tipos usados, sin repetir", P.leyendaCuaderno([nota, pin, pin, zona, otra, m("a", "activo", -73.25, 10.46, { subtipo: "pozo", sistema: "alcantarillado" })]).map((i) => i.texto).join("|") === "Baja presión|Pozo · Alcantarillado|Post-it|Zona afectada"); }
console.log(`\nRESULTADO: ${n - mal} de ${n}${mal ? "" : " — SIN FALLAS"}`); process.exit(mal ? 1 : 0);
