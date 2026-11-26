// [Code A] Consultar direcciones (25-nov) · lógica pura de las unidades del censo (src/campo/analisis/predio.ts), con los valores reales de la muestra del 25-nov.
//   node scripts/prueba_predio_censo.mjs      (-h: este uso)
import { createRequire } from "node:module"; import { join, dirname } from "node:path"; import { fileURLToPath } from "node:url"; import { mkdtempSync, readFileSync } from "node:fs"; import { tmpdir } from "node:os";
if (process.argv.slice(2).some((a) => a === "-h" || a === "--help")) { console.log("Uso: node scripts/prueba_predio_censo.mjs"); process.exit(0); }
const rara = process.argv.slice(2).find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}`); process.exit(2); }
const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const out = join(mkdtempSync(join(tmpdir(), "predio_")), "p.mjs");
await build({ entryPoints: [join(raiz, "src/campo/analisis/predio.ts")], bundle: true, format: "esm", platform: "node", outfile: out, logLevel: "error" });
const P = await import(out);
let t = 0, f = 0; const ok = (n, c, d = "") => { t++; if (!c) f++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + d}`); };
const L = (v) => P.leerUnidades(v);
ok("una unidad: «- 4- - - CASA- CS- 1- - - - ,- » → «4 · CASA · CS · 1»", JSON.stringify(L("- 4- - - CASA- CS- 1- - - - ,- ").unidades) === JSON.stringify(["4 · CASA · CS · 1"]), JSON.stringify(L("- 4- - - CASA- CS- 1- - - - ,- ")));
ok("dos unidades separadas por «,»", JSON.stringify(L("- 4- - - CASA- CS- 1- - - - ,- - - - - APTO- AP- 101- - - - ,- ").unidades) === JSON.stringify(["4 · CASA · CS · 1", "APTO · AP · 101"]));
ok("unidad no habitacional: «LC · 101 · COMERCIAL · SIN ACTIVIDAD · Local»", L("- - - - - LC- 101- - - - COMERCIAL- SIN ACTIVIDAD- Local- ,- ").unidades[0] === "LC · 101 · COMERCIAL · SIN ACTIVIDAD · Local");
ok("«NO APLICA» → no aplica (con su original)", L("NO APLICA").estado === "no_aplica" && L(" no  aplica ").estado === "no_aplica" && L("NO APLICA").original === "NO APLICA");
ok("vacío, nulo o solo guiones → sin dato", L(null).estado === "sin_dato" && L("   ").estado === "sin_dato" && L("- - - ,- ").estado === "sin_dato");
ok("el original se conserva recortado", L("  - - - - CASA- CS- - - - - ,- ").original === "- - - - CASA- CS- - - - - ,-");
ok("cuántas: «1 unidad», «2 unidades», «1.200 unidades»", P.cuantasUnidades(1) === "1 unidad" && P.cuantasUnidades(2) === "2 unidades" && P.cuantasUnidades(1200) === "1.200 unidades", P.cuantasUnidades(1200));
console.log(`\nRESULTADO: ${t - f} de ${t}${f ? "" : " — SIN FALLAS"}`); process.exit(f ? 1 : 0);
