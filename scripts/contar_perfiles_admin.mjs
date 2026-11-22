// Encargo v2 (§0.13): cuántos usuarios quedarían «Personalizado» y con qué perfil se reconoce cada uno, con la MISMA lógica de la pantalla (src/components/perfilesAdmin.ts).
// No consulta nada: lee un archivo JSON con la salida de `listar` ({usuarios: [...]} o la lista sola), por ejemplo la tabla de solo lectura que entrega Claude.
// Uso: node scripts/contar_perfiles_admin.mjs <listar.json>      (-h | --help: este uso; cualquier otra opción es un error)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const USO = "Uso: node scripts/contar_perfiles_admin.mjs <listar.json>";
const a = process.argv.slice(2);
if (a.includes("-h") || a.includes("--help")) { console.log(USO); process.exit(0); }
const rara = a.find((x) => x.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}\n${USO}`); process.exit(2); }
if (a.length !== 1) { console.error(USO); process.exit(2); }
const ts = createRequire(import.meta.url)("typescript");
const js = ts.transpileModule(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../src/components/perfilesAdmin.ts"), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const P = await import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));
const datos = JSON.parse(readFileSync(a[0], "utf8"));
const usuarios = Array.isArray(datos) ? datos : datos.usuarios;
const admins = usuarios.filter((u) => u.rol === "admin"), resto = usuarios.filter((u) => u.rol !== "admin");
const perso = resto.filter((u) => P.esPersonalizado(P.casillasDe(u)).length > 0);
const porGeo = { comercial: 0, tecnica: 0, aseo: 0 };
for (const u of perso) for (const g of P.esPersonalizado(P.casillasDe(u))) porGeo[g]++;
console.log(`Usuarios: ${usuarios.length} · administradores: ${admins.length} · con algún geoportal «Personalizado»: ${perso.length} (Comercial ${porGeo.comercial}, Técnica ${porGeo.tecnica}, Aseo ${porGeo.aseo})`);
const lineas = new Map();
for (const u of resto) { const l = P.lineaUsuario(u); lineas.set(l, (lineas.get(l) ?? 0) + 1); }
console.log("\nCómo se ve cada uno en la lista (línea → cuántos):");
for (const [l, n] of [...lineas].sort((x, y) => y[1] - x[1])) console.log(`  ${String(n).padStart(3)}  ${l}`);
console.log("\n«Personalizado», con las casillas de hoy del geoportal que no calza:");
for (const u of perso) {
  const c = P.casillasDe(u);
  console.log(`  ${u.email}: ${P.esPersonalizado(c).map((g) => `${g} [${P.CASILLAS_DE[g].filter((x) => c[x]).join(", ") || "ninguna"}]`).join(" · ")}`);
}
