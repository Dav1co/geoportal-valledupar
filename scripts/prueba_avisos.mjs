// Prueba de los AVISOS CLAROS cuando falta SQL o una Edge nueva (revisión local contra la base actual). Sin red ni navegador. Uso: node scripts/prueba_avisos.mjs
// Comprueba (1) que «Acción no soportada.» / 404 de la pasarela / 42883 se clasifican como «no_aplicado» y NO como validación o error del servidor, (2) que los errores legítimos no se confunden
// y (3) que cada pantalla nueva o tocada pasa los fallos por esa clasificación (o los traga a propósito, como el aviso de turbiedad).
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const ts = createRequire(import.meta.url)("typescript");
const leer = (r) => readFileSync(join(raiz, r), "utf8");
const js = (r) => ts.transpileModule(leer(r), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const dato = (t) => "data:text/javascript;base64," + Buffer.from(t).toString("base64");
let total = 0, fallas = 0;
const ok = (n, c) => { total++; if (!c) { fallas++; console.log("FALLA ", n); } };

const stub = dato("export const supabase = { auth: { getSession: async () => ({ data: {} }) } }; export const FUNCTIONS_URL = 'http://x';");
const C = await import(dato(js("src/campo/apiCampo.ts").replace(/from\s+["']\.\.\/lib\/supabase["']/, `from "${stub}"`)));
const casos = [
  [400, "Acción no soportada.", "no_aplicado"], [404, "No se pudo completar la operación.", "no_aplicado"], [404, "Ruta desconocida.", "no_aplicado"],
  [500, "function geoportal_x does not exist (42883)", "no_aplicado"], [404, "PGRST202", "no_aplicado"],
  [400, "Los datos del formato tienen demasiados campos.", "validacion"], [404, "El registro no existe.", "validacion"], [409, "Ya estaba cancelada.", "validacion"],
  [500, "No se pudo completar la operación.", "servidor"], [401, "Su sesión venció.", "sesion"], [403, "No tiene permiso para esta acción.", "permiso"], [429, "Espere 5 minutos.", "limite"],
];
for (const [s, m, t] of casos) ok(`clasificar(${s}, «${m}») → ${t}`, C.clasificar(s, m) === t);
const aviso = C.avisoDeError(new C.ErrorCampo("no_aplicado", "x", 400));
ok("el aviso dice que falta la actualización del servidor (SQL/Edge), en español y sin ofrecer reintentar", /necesita la actualización del servidor \(SQL\/Edge\) que aún no está aplicada/.test(aviso.texto) && aviso.reintentable === false);

const T = leer("src/tecnica/apiTecnica.ts");
ok("Técnica: su clasificación también reconoce lo no aplicado (aviso de turbiedad, dosis, etc.)", /esNoAplicado\(status, mensaje\)\) return "no_aplicado"/.test(T) && /"no_aplicado"/.test(T.split("export class ErrorTec")[0]));
ok("Técnica: el formulario de captura y el dashboard muestran el aviso", /case "no_aplicado"/.test(leer("src/tecnica/FormularioCaptura.tsx")) && /case "no_aplicado"/.test(leer("src/tecnica/apiDashboard.ts")));
const av = leer("src/tecnica/AvisoTurbiedad.tsx");
ok("Turbiedad: si la ruta no existe el aviso del Resumen/Eventos no muestra nada ni rompe (catch silencioso → null)", /catch \{ if \(mi === v\.current\) setDatos\(null\); \}/.test(av) && /if \(!datos \|\| datos\.avisos\.length === 0\) return null;/.test(av));
ok("Turbiedad: la tarjeta de umbrales muestra el aviso claro y «no disponible» en su resumen", /setError\(textoError\(e\)\)/.test(av) && /error \? "no disponible"/.test(av));
ok("Aseo supervisión: todas las pestañas pasan el error por textoError → avisoDeError", /avisoDeError\(e\)\.texto/.test(leer("src/aseo/supervision/api.ts")) && ["Resumen", "Auditorias", "Indicadores", "PersonalAseo", "DetalleAuditoria"].every((f) => /textoError\(e\)/.test(leer(`src/aseo/supervision/${f}.tsx`))));
const fa = leer("src/aseo/FormularioAuditoria.tsx");
ok("Aseo firmas: un 413 de la Edge anterior a las firmas sale como «falta la actualización», con lo escrito y las fotos intactas", /err\.status === 413\) err = new ErrorAseo\("no_aplicado", TEXTO_NO_APLICADO, 413\)/.test(fa));
ok("Aperturas sin registrar: el error pasa por avisoDeError", /avisoDeError\(error\)\.texto/.test(leer("src/campo/acta/AperturasSinRegistrar.tsx")));
ok("Cancelar del acta: sin lista de motivos el panel lo dice (falta actualización o conexión) y no deja cancelar", /necesita la actualización del servidor \(SQL\/Edge\)/.test(leer("src/components/ConfirmarCancelar.tsx")) && /motivos === null \|\| motivos\.length === 0/.test(leer("src/components/ConfirmarCancelar.tsx")));
ok("Cancelar del acta: el error de la acción pasa por avisoDeError", /avisoDeError\(err\)\.texto/.test(leer("src/campo/acta/PanelCancelarActa.tsx")));
const k = leer("src/campo/constancia/useConstancia.ts");
ok("Constancia por correo (captura): si la configuración no carga, la sección no aparece y el registro sigue (opcional)", /\.catch\(\(\) => \{ if \(vivo\) setConfig\(null\); \}\)/.test(k) && /if \(!activa\(config\)\) return null;/.test(leer("src/campo/constancia/SeccionConstancia.tsx")));
ok("Constancia por correo (administración): el error pasa por textoError, que reconoce lo no aplicado", /case "no_aplicado"/.test(leer("src/campo/dashboard/apiRevision.ts")) && /textoError\(e\)\.texto/.test(leer("src/campo/constancia/ConstanciasAdmin.tsx")));
console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
