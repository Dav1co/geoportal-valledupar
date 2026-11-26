// Prueba LÓGICA del encargo «Formatos de campo ordenados + actividades derivadas en Reportes» (Code B, 25-nov-2026). Sin red ni navegador.
// Cubre: bloques de la lista por perfil, contador «100+», columnas y privacidad de la descarga, ÍCONOS distintos, un solo botón «← Volver».
// Uso: node scripts/prueba_formatos_derivadas.mjs
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const esbuild = createRequire(import.meta.url)(join(raiz, "node_modules", "esbuild"));
const tmp = mkdtempSync(join(tmpdir(), "pfd_"));
const empaquetar = async (rel, nombre) => { const out = join(tmp, nombre + ".mjs"); await esbuild.build({ entryPoints: [join(raiz, rel)], bundle: true, format: "esm", platform: "node", outfile: out, logLevel: "silent" }); return import(out); };
const E = await empaquetar("src/campo/entradas.ts", "entradas");
const C = await empaquetar("src/campo/documentos/contadorDerivadas.ts", "contador");
const D = await empaquetar("src/campo/dashboard/derivadasDescarga.ts", "descarga");
const leer = (rel) => readFileSync(join(raiz, rel), "utf8");
let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- 1. Bloques por perfil (los 5 perfiles de David) ----
const base = { puedeReportar: true, hayFormatos: true, puedeActa: true, puedeCampo: true, puedeAnalisis: true, puedeActivoCampo: true };
const perfiles = {
  admin: { ...base, puedeSupervisarActas: true, puedeSupervisar: true, puedeRepartir: true, puedeSupervisarReparto: true },
  supervisorComercial: { ...base, puedeSupervisarActas: true, puedeSupervisar: true, puedeSupervisarReparto: true },
  operario: { ...base },
  dual: { ...base, puedeSupervisar: true },
  sinPermisos: { puedeReportar: false, hayFormatos: false, puedeActa: false, puedeCampo: false },
};
const lista = (p) => E.entradasDeCampo(perfiles[p]);
const bl = (p) => E.bloquesVisibles(lista(p));
ok("admin: ve los dos bloques y las tres tarjetas de Supervisar", igual(bl("admin"), ["registrar", "supervisar"]) && igual(E.entradasDelBloque(lista("admin"), "supervisar").map((e) => e.id), ["acta_supervision", "revision", "reparto_supervision"]));
ok("supervisor de Comercial: los dos bloques; Supervisar con sus tarjetas", igual(bl("supervisorComercial"), ["registrar", "supervisar"]) && E.entradasDelBloque(lista("supervisorComercial"), "supervisar").length === 3);
ok("operario de campo: SOLO «Registrar en campo» (sin pestañas, sin ninguna tarjeta de supervisión)", igual(bl("operario"), ["registrar"]) && lista("operario").every((e) => !e.gestion));
ok("dual: los dos bloques; Supervisar sin Reparto (no tiene esa actividad)", igual(bl("dual"), ["registrar", "supervisar"]) && !lista("dual").some((e) => e.id === "reparto_supervision"));
ok("sin permisos: ninguna entrada y ningún bloque", lista("sinPermisos").length === 0 && bl("sinPermisos").length === 0);
ok("Registrar en campo: Reportar anomalía, Formatos de actividad, Reportar posible pérdida y «Consultar» (Análisis de contrato) están todas aquí",
  ["reporte_general", "formatos", "acta", "analisis_contrato"].every((id) => E.entradasDelBloque(lista("operario"), "registrar").some((e) => e.id === id)));
ok("toda gestión va en Supervisar y todo lo demás en Registrar", lista("admin").every((e) => (e.gestion ? e.bloque === "supervisar" : e.bloque === "registrar")));
ok("cada tarjeta de Supervisar tiene descripción propia y distinta", (() => { const d = E.entradasDelBloque(lista("admin"), "supervisar").map((e) => e.descripcion); return d.every((x) => x.length > 20) && new Set(d).size === d.length; })());
ok("rótulos de los bloques", E.ROTULO_BLOQUE.registrar === "Registrar en campo" && E.ROTULO_BLOQUE.supervisar === "Supervisar");
ok("solo acta de supervisor sin campo: solo Supervisar (una sola pestaña no se dibuja)", (() => { const l = E.entradasDeCampo({ puedeReportar: false, hayFormatos: false, puedeActa: false, puedeCampo: false, puedeSupervisarActas: true }); return igual(E.bloquesVisibles(l), ["supervisar"]); })());

// ---- 2. Contador «100+» ----
ok("contador: 0 → nada; 7 → «7»; 1 → «1 pendiente»", C.textoPendientes({ n: 0, tope: false }) === "" && C.textoPendientes({ n: 7, tope: false }) === "7" && C.etiquetaPendientes({ n: 1, tope: false }) === " · 1 pendiente");
ok("contador: al llegar al tope (100 filas) → «100+»", C.textoPendientes(C.pendientesDe(100, false)) === "100+" && C.etiquetaPendientes(C.pendientesDe(100, false)) === " · 100+ pendientes");
ok("contador: 99 filas → «99»; 5 filas pero con «siguiente» → «100+»", C.textoPendientes(C.pendientesDe(99, false)) === "99" && C.textoPendientes(C.pendientesDe(5, true)) === "100+");
ok("contador: si la consulta falla (nulo) no se muestra nada", C.textoPendientes(null) === "" && C.etiquetaPendientes(null) === "" && C.etiquetaPendientes(undefined) === "");

// ---- 3. Descarga: columnas, sin datos de contacto ----
const SENSIBLES = ["NOMBRE-SECRETO-ZT", "3009998877", "CEDULA-ZT-123", "correo.secreto@zt.test", "TEXTO LIBRE ZT", "DIRECCION-CORRECTA-ZT", "MOTIVO LIBRE ZT"];
const fila = (i, extra = {}) => ({ id: i, actividad: "aviso_direccion_errada", actividad_nombre: "Aviso: dirección errada", contrato: String(1000000 + i), estado: i % 2 ? "pendiente" : "atendida", creada_en: "2026-11-20T15:30:00Z", antiguedad_dias: 5,
  origen: { clase: "analisis", tipo: "analisis", fecha: "2026-11-20T15:30:00Z", operario: "zt.operario@emdupar.gov.co", observacion_nombre: "Dirección errada", texto: "TEXTO LIBRE ZT", direccion_correcta: "DIRECCION-CORRECTA-ZT", trae_datos: true, entregas_datos: 2, vistos: 1,
    // campos que NO deben salir aunque lleguen por error en la respuesta
    nombre: "NOMBRE-SECRETO-ZT", telefono: "3009998877", cedula: "CEDULA-ZT-123", correo: "correo.secreto@zt.test" },
  cierre: i % 2 ? null : { en: "2026-11-22T10:00:00Z", tipo: "atendida", autor: "zt.supervisor@emdupar.gov.co", esquema: "campo", consecutivo: "IME-000009", registro_id: null, motivo: "MOTIVO LIBRE ZT" }, ...extra });
const filas = [fila(1), fila(2), { ...fila(3), actividad: "actividad_supervisor", actividad_nombre: "Actividad del supervisor", destino_nombre: "Investigación de ubicación", origen: { clase: "registro", tipo: "instalacion_medidor", consecutivo: "IME-000003", fecha: "2026-11-19", operario: "zt.operario@emdupar.gov.co" } }];
const csv = D.csvDerivadas(filas, false), csvA = D.csvDerivadas(filas, true);
ok("descarga: encabezado esperado (sin correos por omisión)", igual(D.columnasDerivadas(false), ["Id", "Contrato", "Origen", "Actividad", "Estado", "Viene de", "Fecha de origen", "Creada", "Antigüedad (días)", "Visto otra vez (veces)", "Trae datos de contacto", "Entregas de datos", "Cierre", "Fecha de cierre", "La atendió (registro)"]));
ok("descarga: tantas líneas como filas más el encabezado y el BOM al inicio", csv.startsWith("﻿") && csv.trim().split("\r\n").length === 4);
ok("descarga: NINGÚN dato de contacto, texto libre, dirección ni motivo (CSV, con y sin correos)", SENSIBLES.every((x) => !csv.includes(x) && !csvA.includes(x)), SENSIBLES.filter((x) => csv.includes(x) || csvA.includes(x)).join());
ok("descarga: cada fila tiene tantas celdas como columnas", filas.every((f) => D.filaDerivada(f, false).length === D.columnasDerivadas(false).length && D.filaDerivada(f, true).length === D.columnasDerivadas(true).length));
ok("descarga: solo dice SI trae datos de contacto y cuántas entregas (sin su contenido)", D.filaDerivada(filas[0], false)[10] === "Sí" && D.filaDerivada(filas[0], false)[11] === 2 && D.filaDerivada(filas[2], false)[10] === "No");
ok("descarga: los correos de quien originó y cerró solo con la opción del administrador", !csv.includes("zt.operario") && !csv.includes("zt.supervisor") && csvA.includes("zt.operario@emdupar.gov.co") && csvA.includes("zt.supervisor@emdupar.gov.co"));
ok("descarga: «Actividad: destino» para la actividad del supervisor, estado y cierre rotulados", D.filaDerivada(filas[2], false)[3] === "Actividad: Investigación de ubicación" && D.filaDerivada(filas[0], false)[4] === "Pendiente" && D.filaDerivada(filas[1], false)[12] === "Atendida por un registro" && D.filaDerivada(filas[1], false)[14] === "IME-000009");
ok("descarga: fechas en hora de Bogotá (20/11/2026 10:30) y día sin hora para el día suelto (19/11/2026)", D.filaDerivada(filas[0], false)[7] === "20/11/2026 10:30" && D.filaDerivada(filas[2], false)[6] === "19/11/2026", JSON.stringify([D.filaDerivada(filas[0], false)[7], D.filaDerivada(filas[2], false)[6]]));
ok("descarga: inyección de fórmulas neutralizada (=, +, -, @)", D.csvDerivadas([fila(4, { contrato: "=1+1" })], false).includes("'=1+1"));
ok("descarga: nombre de archivo y Léame (dice que no hay datos de contacto y que la descarga queda registrada en el servidor: registro flexible, Code A)", D.nombreArchivoDerivadas(new Date(2026, 10, 25, 9, 5), "xlsx") === "avisos_y_actividades_derivadas_20261125_0905.xlsx"
  && (() => { const l = D.leameDerivadas({ generadoPor: "zt@x", generadoEn: "25/11/2026 09:05", filas: 3, filtros: ["Estado: Pendiente"], incluyeAutor: false }).flat().join(" "); return /NO incluye los datos de contacto/.test(l) && /queda registrada en el servidor/.test(l) && /No incluye el correo/.test(l); })());

// ---- 4. Íconos y botón de volver (lectura del código) ----
const icon = leer("src/campo/iconosEntradas.tsx");
const trazos = [...icon.matchAll(/^\s+(\w+): "([^"]+)",/gm)].map((m) => m.slice(1));
const ids = ["reporte_general", "formatos", "acta", "analisis_contrato", "acta_supervision", "revision", "activo_campo", "reparto", "reparto_supervision"];
ok("íconos: uno por entrada, todos distintos", ids.every((i) => trazos.some(([k]) => k === i)) && new Set(trazos.map((t) => t[1])).size === trazos.length, String(trazos.length));
ok("íconos: la tarjeta ya no dibuja la inicial del título (la «R» repetida)", !/data-ini=\{e\.titulo/.test(leer("src/campo/AreaCampo.tsx")));
const volver = leer("src/campo/BotonVolver.tsx");
ok("BotonVolver: texto único «← Volver», exportado", /TEXTO_VOLVER = "← Volver"/.test(volver) && /export function BotonVolver/.test(volver));
const PANTALLAS = ["src/campo/dashboard/Revision.tsx", "src/campo/documentos/ActasRegistradas.tsx", "src/campo/acta/PantallaActa.tsx", "src/campo/acta/AperturasSinRegistrar.tsx", "src/campo/reparto/PantallaRepartidor.tsx", "src/campo/reparto/PantallaSupervisor.tsx"];
ok("pantallas: todas usan BotonVolver (sin «Volver a Formatos de campo» ni «Volver» sueltos en la cabecera)", PANTALLAS.every((p) => /<BotonVolver /.test(leer(p)) && !/← Volver a Formatos de campo/.test(leer(p))), PANTALLAS.filter((p) => !/<BotonVolver /.test(leer(p))).join());
// Registro flexible (Code A, 25-nov): formatos/ y ReporteGeneral.tsx ya usan BotonVolver (antes esta prueba exigía que no lo usaran todavía)
ok("formatos/ y ReporteGeneral.tsx usan BotonVolver (cambio del Code A con el componente exportado)", ["src/campo/formatos/FormatosCampo.tsx", "src/campo/formatos/FormularioFormato.tsx", "src/campo/ReporteGeneral.tsx"].every((p) => /<BotonVolver /.test(leer(p)) && !/← Formatos|Volver a los formatos/.test(leer(p))));
import { spawnSync } from "node:child_process";
const cambios = spawnSync("git", ["diff", "--name-only", "main", "--", "src/campo/dashboard/PersonalCampo.tsx", "src/campo/dashboard/Cuadrillas.tsx", "src/campo/dashboard/ejecutarDescarga.ts", "src/campo/dashboard/xlsxRevision.ts"], { cwd: raiz, encoding: "utf8" }).stdout.trim();
ok("intactos: Personal, Cuadrillas y el mecanismo de descarga (ejecutarDescarga, xlsxRevision); formatos/ y ReporteGeneral.tsx los cambia el Code A", cambios === "", cambios);

rmSync(tmp, { recursive: true, force: true });
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas${fallas ? ` — ${fallas} FALLA(S)` : " — SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
