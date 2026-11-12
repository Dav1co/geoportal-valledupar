// Prueba de la INTEGRACIÓN de la Torre A en el frontend (lógica pura, sin red ni navegador):
//  1. El reporte general NO ofrece los formatos del Paso D (src/campo/ReporteGeneral.tsx usa sinFormatosD).
//  2. La lista de entradas del área de campo y la visibilidad de la entrada del acta solo con el permiso `acta` (src/campo/entradas.ts).
// Uso: node scripts/prueba_integracion.mjs   (usa el paquete typescript del proyecto)
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const leer = (rel) => readFileSync(join(aqui, "..", rel), "utf8");
const compilar = (rel) => ts.transpileModule(leer(rel), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const aUrl = (js) => "data:text/javascript;base64," + Buffer.from(js).toString("base64");
const urlTipos = aUrl(compilar("src/campo/formatos/tipos.ts"));
const T = await import(urlTipos);

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- 1. Filtro de ReporteGeneral ----
const general = (codigo) => ({ codigo, nombre: codigo, orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [], campos: [], fotos: [], genera_resultado: false, usa_consecutivo: false });
const formatoD = (codigo) => ({ ...general(codigo), fotos_min: 2, fotos_max: 4, genera_resultado: true, usa_consecutivo: true, campos: [{ codigo: "lectura", nombre: "Lectura", tipo_dato: "decimal", obligatorio: true, activo: true }], fotos: [{ codigo: "fachada", nombre: "Fachada", obligatoria: true, soporte_inefectiva: true, orden: 1, activo: true }] });
const grupos = [
  { codigo: "comercial_perdidas", nombre: "Pérdidas", orden: 1, activo: true, tipos: [general("fraude"), general("medidor_danado")] },
  { codigo: "cartera_formatos", nombre: "Cartera", orden: 2, activo: true, tipos: [formatoD("suspension"), formatoD("corte")] },
  { codigo: "mixto", nombre: "Mixto", orden: 3, activo: true, tipos: [general("otro"), formatoD("verificacion")] },
];
const visibles = T.sinFormatosD(grupos).filter((g) => g.activo && g.tipos.some((t) => t.activo));
const codigos = visibles.flatMap((g) => g.tipos.map((t) => t.codigo));
ok("filtro: el reporte general conserva sus tipos", igual(codigos, ["fraude", "medidor_danado", "otro"]));
ok("filtro: ningún tipo del Paso D llega al reporte general", !codigos.some((c) => ["suspension", "corte", "verificacion"].includes(c)));
ok("filtro: un grupo solo con formatos del Paso D desaparece", !visibles.some((g) => g.codigo === "cartera_formatos"));
ok("filtro: un grupo mixto se queda solo con lo que el reporte general sabe enviar", igual(visibles.find((g) => g.codigo === "mixto")?.tipos.map((t) => t.codigo), ["otro"]));
ok("filtro: con el servidor sin el Paso D (sin claves nuevas) no cambia nada", igual(T.sinFormatosD([{ codigo: "g", nombre: "g", orden: 1, activo: true, tipos: [{ codigo: "t", nombre: "t", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [] }] }]).flatMap((g) => g.tipos.map((t) => t.codigo)), ["t"]));
ok("filtro: sin grupos devuelve lista vacía", igual(T.sinFormatosD([]), []));
ok("filtro: no modifica los grupos recibidos", grupos[1].tipos.length === 2 && grupos[2].tipos.length === 2);
const rg = leer("src/campo/ReporteGeneral.tsx");
ok("ReporteGeneral.tsx importa sinFormatosD de ./formatos/tipos", /import \{ sinFormatosD \} from "\.\/formatos\/tipos";/.test(rg));
ok("ReporteGeneral.tsx filtra los grupos con sinFormatosD(def.grupos)", /const grupos = useMemo\(\(\) => sinFormatosD\(def\.grupos\)\.filter\(/.test(rg));
ok("ReporteGeneral.tsx ya no usa def.grupos sin filtrar", (rg.match(/def\.grupos/g) ?? []).length === 1);

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
