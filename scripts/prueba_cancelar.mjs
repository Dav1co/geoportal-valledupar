// Pruebas de FUENTE del trabajo «Cancelar» (sin navegador; la prueba con Chrome real está en el paquete: paquete_cancelar_registros/pruebas_chrome/).
//   node scripts/prueba_cancelar.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const leer = (r) => readFileSync(join(aqui, "..", r), "utf8");
let total = 0, fallas = 0;
const ok = (n, c) => { total++; if (!c) { fallas++; console.log("FALLA ", n); } };

const conf = leer("src/components/ConfirmarCancelar.tsx");
ok("panel: es un alertdialog con foco en el título y «Esc» = seguir editando", /role="alertdialog"/.test(conf) && /refTitulo\.current\?\.focus\(\)/.test(conf) && /e\.key === "Escape"/.test(conf));
ok("panel: el texto del motivo se exige solo si el motivo lo pide, con mínimo de 10 caracteres", /MIN_TEXTO_MOTIVO = 10/.test(conf) && /!elegido\?\.exige_texto \|\| texto\.trim\(\)\.length >= MIN_TEXTO_MOTIVO/.test(conf));
ok("panel: con motivos, no se confirma sin elegir uno", /elegido !== null && textoOk/.test(conf));
ok("panel: «Me equivoqué de formulario» ofrece los destinos solo con ese motivo (o sin motivos)", /codigo === MOTIVO_EQUIVOCACION/.test(conf) && /solo se lleva el contrato/.test(conf));
ok("panel: no usa window.confirm", !/window\.confirm|confirm\(/.test(conf));

for (const [f, nombre] of [["src/campo/ReporteGeneral.tsx", "Reporte general"], ["src/campo/formatos/FormularioFormato.tsx", "Formatos"], ["src/aseo/FormularioAuditoria.tsx", "Aseo"]]) {
  const t = leer(f);
  ok(`${nombre}: «Cancelar» confirma solo si hay datos y descarta sin tocar el servidor`, /const pedirCancelar = \(\) => \{ if \(hayDatos\) setCancelando\(true\); else onVolver\(\); \}/.test(t) && /<ConfirmarCancelar/.test(t) && /onConfirmar=\{\(\) => onVolver\(\)\}/.test(t));
  ok(`${nombre}: el botón de cancelar no se puede pulsar mientras se envía`, /btn-cancelar"[^>]*disabled=\{(bloqueado|dis|fase === "enviando")\}/.test(t));
}
ok("Aseo: no se duplica el «Cancelar» de la firma (el de este formulario es del registro completo y no dibuja ningún lienzo)", !/FirmaPad|<canvas/.test(leer("src/aseo/FormularioAuditoria.tsx")));

const api = leer("src/campo/acta/apiActa.ts");
ok("acta: cancelar manda solo acta_id, motivo_codigo y (si hay) motivo_texto; sin autor ni fechas", /cuerpo: \{ acta_id, motivo_codigo, \.\.\.\(motivo_texto\.trim\(\) \? \{ motivo_texto: motivo_texto\.trim\(\) \} : \{\}\) \}/.test(api));
const panel = leer("src/campo/acta/PanelCancelarActa.tsx");
ok("acta: el borrador y las fotos del teléfono se sueltan SOLO después de que el servidor confirmó", panel.indexOf("await apiActa.cancelar") > 0 && panel.indexOf("almacenActa.quitar(actaId)") > panel.indexOf("await apiActa.cancelar"));
ok("acta: con la red caída no se descarta nada y se avisa", /err\.tipo === "red"/.test(panel) && /siguen aquí/.test(panel));
ok("acta: el borrador sigue solo en memoria (nada en localStorage)", !/localStorage|sessionStorage|indexedDB/.test((leer("src/campo/acta/almacenActa.ts") + panel).replace(/\/\/.*$/gm, "")));
const lista = leer("src/campo/acta/PantallaActa.tsx");
ok("acta: «Mis actas» ofrece Cancelar solo a las filas con puede_cancelar", /f\.puede_cancelar && cancelandoId !== f\.acta_id/.test(lista));
const sup = leer("src/campo/acta/AperturasSinRegistrar.tsx");
ok("supervisión: lista sin registradas, con filtro «Ver cancelados» y cancela con motivo", /Ver cancelados/.test(sup) && /apiActa\.aperturasSinRegistrar\(verCancelados\)/.test(sup) && /<PanelCancelarActa/.test(sup));
ok("área: la entrada del supervisor solo abre con dashboardActa (el administrador lo recibe de App)", /abierta === "acta_supervision" && dashboardActa/.test(leer("src/campo/AreaCampo.tsx")) && /dashboard_acta === true \|\| esAdmin/.test(leer("src/App.tsx")));

const c = leer("src/tecnica/FormularioCaptura.tsx");
ok("Técnica (Entrada/Salida): «Descartar borrador» conserva la marca «ya enviada» (solo borra el borrador si no está vigente)", /if \(!comunVigente\(comunEnviada\)\) borrarBorrador\(clave\)/.test(c) && /setTextos\(\{\}\)/.test(c));
ok("Técnica (por lugar): descartar no toca las tarjetas ya guardadas y lo dice", /ya estaban guardadas y no se afectan/.test(leer("src/tecnica/FormularioPorLugar.tsx")));
ok("Técnica: descartar nunca llama al servidor", !/descartar\(\)[^}]*apiTec/.test(c));
ok("sin lenguaje tarifario en lo nuevo", !/(tarif|bcr|poir|vaeo)/i.test(conf + panel + sup));

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
