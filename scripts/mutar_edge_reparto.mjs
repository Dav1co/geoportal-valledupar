// Mutaciones de la Edge geoportal-reparto: copia supabase/functions a una carpeta temporal, rompe UNA defensa y corre prueba_edge_reparto.mjs contra la copia;
// la prueba que la cuida debe fallar. No toca el repositorio. Uso: node scripts/mutar_edge_reparto.mjs <deno> <supabase/functions> <psql> <plantilla> <migración _editor>  (-h)
import { cpSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const USO = "Uso: node scripts/mutar_edge_reparto.mjs <deno> <supabase/functions> <psql> <plantilla> <migración _editor>";
const a = process.argv.slice(2);
for (const x of a) { if (x === "-h" || x === "--help") { console.log(USO); process.exit(0); } if (x.startsWith("-")) { console.error(`Opción desconocida: ${x}\n${USO}`); process.exit(2); } }
if (a.length !== 5) { console.error(USO); process.exit(2); }
const [DENO, FUNCIONES, PSQL, PLANTILLA, MIGRACION] = a;
const PRUEBA = join(dirname(fileURLToPath(import.meta.url)), "prueba_edge_reparto.mjs");
const MUT = [
  ["validar.ts", "  for (const k of Object.keys(b)) if (!permitidas.includes(k)) bad(", "  for (const k of Object.keys(b)) if (false) bad(", "B2", "acepta claves del cuerpo que no conoce"],
  ["validar.ts", "  for (const k of u.searchParams.keys()) if (k !== \"accion\" && !permitidos.includes(k)) bad(", "  for (const k of u.searchParams.keys()) if (false) bad(", "B1", "acepta parámetros que no conoce"],
  ["index.ts", "  sinCamposProhibidos(b as Obj);\n", "\n", "B3", "deja fijar el autor en el cuerpo"],
  ["index.ts", "\"Cache-Control\": \"no-store\"", "\"Cache-Control\": \"max-age=60\"", "Z1", "respuestas en caché"],
  ["rpc.ts", "console.error(`reparto ${fn}: HTTP ${resp.status} código ${c.code ?? \"?\"}`);", "console.error(`reparto ${fn}: HTTP ${resp.status} código ${c.code ?? \"?\"}: ${c.message}`);", "Z3", "escribe el mensaje de la base en el registro"],
  ["rpc.ts", "\"23505\": 409, ", "", "C4", "«ya se registró» sale como error genérico"],
  ["index.ts", "p_despues: d ? entero(d, 0, Number.MAX_SAFE_INTEGER, \"El cursor\") : null", "p_despues: null", "D8", "el mapa en vivo ignora el cursor"],
];
let fallas = 0;
for (const [arch, de, a2, prueba, nombre] of MUT) {
  const tmp = mkdtempSync(join(tmpdir(), "mut_reparto_"));
  try {
    cpSync(FUNCIONES, tmp, { recursive: true });
    const f = join(tmp, "geoportal-reparto", arch), t = readFileSync(f, "utf8");
    if (t.split(de).length !== 2) { console.log(`[SIN TEXTO] ${nombre}`); fallas++; continue; }
    writeFileSync(f, t.replace(de, a2));
    const r = spawnSync(process.execPath, [PRUEBA, DENO, tmp, PSQL, PLANTILLA, MIGRACION], { encoding: "utf8", env: { ...process.env }, maxBuffer: 64 << 20 });
    const atrapada = r.status !== 0 && new RegExp(`^FALLA ${prueba} `, "m").test(r.stdout);
    if (!atrapada) fallas++;
    console.log(`[${atrapada ? "ATRAPADA" : "NO ATRAPADA"}] ${nombre} → ${(r.stdout.match(/RESULTADO:.*/) || ["sin resultado"])[0]} (debe fallar la ${prueba})`);
  } finally { rmSync(tmp, { recursive: true, force: true }); }
}
console.log(`MUTACIONES DE LA EDGE: ${MUT.length - fallas} de ${MUT.length} atrapadas${fallas ? " — HAY FALLAS" : " — SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
