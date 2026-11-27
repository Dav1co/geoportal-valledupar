// [Code B] Cuadernos de análisis: genera src/tecnica/cuadernos/iconos_datos.ts desde la fuente única docs/cuadernos_iconos/iconos.json (hoja aprobada por David, 26-nov).
// Uso: node scripts/iconos_cuadernos.mjs [--comprobar]      (--comprobar: no escribe; termina con error si el archivo generado no está al día)
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const USO = "Uso: node scripts/iconos_cuadernos.mjs [--comprobar]";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log(USO); process.exit(0); }
const rara = args.find((a) => a !== "--comprobar"); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const d = JSON.parse(readFileSync(join(raiz, "docs/cuadernos_iconos/iconos.json"), "utf8"));
const salida = join(raiz, "src/tecnica/cuadernos/iconos_datos.ts");
const t = `// GENERADO por scripts/iconos_cuadernos.mjs desde docs/cuadernos_iconos/iconos.json (${d.version}). No se edita a mano.
export const ICONOS_VERSION = ${JSON.stringify(d.version)};
export const COLOR_SISTEMA: Record<"acueducto" | "alcantarillado", string> = ${JSON.stringify(Object.fromEntries(d.activo.colores.map((c) => [c.codigo, c.color])))};
export type IconoActivo = { codigo: string; nombre: string; svg: string; fondo?: string };
export const ICONOS_ACTIVO: IconoActivo[] = ${JSON.stringify(d.activo.iconos.map((i) => ({ codigo: i.codigo, nombre: i.nombre, svg: i.svg, ...(i.fondo ? { fondo: i.fondo } : {}) })), null, 1)};
export const PIN = ${JSON.stringify({ viewBox: d.problema.pin.viewBox, svg: d.problema.pin.svg, glifo_transform: d.problema.pin.glifo_transform, glifo_color: d.problema.glifo.color })};
export type IconoProblema = { codigo: string; nombre: string; color: string; glifo: string };
export const ICONOS_PROBLEMA: IconoProblema[] = ${JSON.stringify(d.problema.iconos.map((i) => ({ codigo: i.codigo, nombre: i.nombre, color: i.color, glifo: i.glifo })), null, 1)};
`;
if (args.includes("--comprobar")) {
  let actual = ""; try { actual = readFileSync(salida, "utf8"); } catch { /* no existe */ }
  if (actual !== t) { console.error("iconos_datos.ts no está al día con iconos.json: corra node scripts/iconos_cuadernos.mjs"); process.exit(1); }
  console.log(`iconos_datos.ts al día (${d.activo.iconos.length} activos, ${d.problema.iconos.length} problemas)`);
} else { writeFileSync(salida, t); console.log(`escrito ${salida}`); }
