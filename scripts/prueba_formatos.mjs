// Prueba de la lógica PURA de los formatos del Paso D (src/campo/formatos/logica.ts y tipos.ts): contadores de fotos, regla de inefectivo, aplanado de datos, orden y etiquetas.
// Sin red ni navegador. Uso: node scripts/prueba_formatos.mjs   (usa el paquete typescript del proyecto)
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)("typescript");
const compilar = (f) => ts.transpileModule(readFileSync(join(aqui, "../src/campo/formatos", f), "utf8"), { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const jsTipos = compilar("tipos.ts");
const urlTipos = "data:text/javascript;base64," + Buffer.from(jsTipos).toString("base64");
const jsLogica = compilar("logica.ts").replace(/from\s+["']\.\/tipos["']/, `from "${urlTipos}"`);
const L = await import("data:text/javascript;base64," + Buffer.from(jsLogica).toString("base64"));
const T = await import(urlTipos);

let total = 0, fallas = 0;
const ok = (n, c, d = "") => { total++; if (!c) { fallas++; console.log(`FALLA  ${n} ${d}`); } };
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Formato de ejemplo (estructura idéntica a la de la ruta «formulario»): suspensión con 3 fotos mínimas (2 obligatorias), resultado y campos de todos los tipos.
const sus = {
  codigo: "suspension", nombre: "Suspensión", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
  fotos_min: 3, fotos_max: 5, requiere_contrato: "si", genera_resultado: true, usa_consecutivo: true,
  campos: [
    { codigo: "lectura", nombre: "Lectura", tipo_dato: "decimal", obligatorio: true, minimo: 0, maximo: 9999999, unidad: "m³", orden: 1, activo: true },
    { codigo: "sellos", nombre: "Sellos", tipo_dato: "entero", obligatorio: false, minimo: 0, maximo: 10, orden: 2, activo: true },
    { codigo: "despeje_caja", nombre: "Despeje de caja", tipo_dato: "si_no", obligatorio: false, orden: 3, activo: true },
    { codigo: "despeje_observacion", nombre: "Observación del despeje", tipo_dato: "texto", obligatorio: false, maximo: 120, orden: 4, activo: true },
    { codigo: "diametro", nombre: "Diámetro", tipo_dato: "opcion", obligatorio: true, opciones: [{ codigo: "d12", nombre: "1/2", activo: true }, { codigo: "d34", nombre: "3/4", activo: true }, { codigo: "viejo", nombre: "Viejo", activo: false }], orden: 5, activo: true },
    { codigo: "materiales", nombre: "Materiales", tipo_dato: "opciones", obligatorio: false, opciones: [{ codigo: "pvc", nombre: "PVC" }, { codigo: "cu", nombre: "Cobre" }], orden: 6, activo: true },
    { codigo: "cita_acordada", nombre: "Día y hora acordados", tipo_dato: "dia_hora", obligatorio: false, orden: 7, activo: true },
    { codigo: "telefono_contacto", nombre: "Teléfono", tipo_dato: "texto", obligatorio: false, sensible: true, maximo: 15, orden: 8, activo: true },
    { codigo: "oculto", nombre: "Campo apagado", tipo_dato: "texto", obligatorio: true, orden: 9, activo: false },
  ],
  fotos: [
    { codigo: "fachada", nombre: "Fachada", obligatoria: true, soporte_inefectiva: true, orden: 1, activo: true },
    { codigo: "medidor", nombre: "Medidor", obligatoria: true, soporte_inefectiva: false, orden: 2, activo: true },
    { codigo: "sello", nombre: "Sello", obligatoria: false, soporte_inefectiva: false, orden: 3, activo: true },
    { codigo: "vieja", nombre: "Foto apagada", obligatoria: true, soporte_inefectiva: false, orden: 4, activo: false },
  ],
  causales: [{ codigo: "no_hay_acceso", nombre: "No hay acceso" }, { codigo: "usuario_ausente", nombre: "Usuario ausente" }],
};
const general = { codigo: "fraude", nombre: "Fraude", orden: 1, activo: true, exige_texto: false, exige_subtipo: true, tiene_subtipos: true, subtipos: [], fotos_min: 1, fotos_max: 2, requiere_contrato: "opcional", genera_resultado: false, usa_consecutivo: false, campos: [], fotos: [], causales: [] };
const viejoSinD = { codigo: "fuga", nombre: "Fuga", orden: 2, activo: true, exige_texto: true, exige_subtipo: false, tiene_subtipos: false, subtipos: [] };   // servidor SIN el Paso D

const base = (extra = {}) => ({ resultado: "efectivo", causal: "", subtipo: "", descripcion: "", contrato: "123", valores: { lectura: "1.234,5", diametro: "d12" },
  etiquetasConFoto: ["fachada", "medidor", "sello"], adicionales: 0, tieneUbicacion: true, tienePrecision: true, topeGeneral: 10, ...extra });

// ---- Detección de formatos (y tolerancia a un servidor sin el Paso D) ----
ok("esFormatoD: suspensión sí", T.esFormatoD(sus));
ok("esFormatoD: reporte general (campos y fotos vacíos) no", !T.esFormatoD(general));
ok("esFormatoD: tipo de un servidor sin el Paso D (sin las claves) no", !T.esFormatoD(viejoSinD));
const grupos = [{ codigo: "g1", nombre: "Cartera", orden: 1, activo: true, tipos: [sus, general, { ...sus, codigo: "corte", activo: false }] }, { codigo: "g2", nombre: "General", orden: 2, activo: true, tipos: [general, viejoSinD] }, { codigo: "g3", nombre: "Apagado", orden: 3, activo: false, tipos: [sus] }];
const disp = T.formatosDisponibles(grupos);
ok("formatosDisponibles: solo grupos activos con formatos D activos", disp.length === 1 && disp[0].grupo.codigo === "g1" && disp[0].tipos.length === 1 && disp[0].tipos[0].codigo === "suspension");
ok("formatosDisponibles: sin ningún formato D devuelve []", T.formatosDisponibles([{ codigo: "g", nombre: "G", orden: 1, activo: true, tipos: [general, viejoSinD] }]).length === 0);
ok("formatosDisponibles: tolera undefined", T.formatosDisponibles(undefined).length === 0);
const sin = T.sinFormatosD(grupos);
ok("sinFormatosD: quita los D y los grupos que quedan vacíos", sin.length === 2 && sin[0].tipos.map((t) => t.codigo).join() === "fraude" && sin[1].tipos.length === 2 && !sin.some((g) => g.codigo === "g3" && false));

// ---- Números con formato colombiano ----
ok("leerNumero 1.234,5", L.leerNumero("1.234,5") === 1234.5);
ok("leerNumero 12,5", L.leerNumero("12,5") === 12.5);
ok("leerNumero 12.5", L.leerNumero("12.5") === 12.5);
ok("leerNumero 1.234.567", L.leerNumero("1.234.567") === 1234567);
ok("leerNumero vacío → null", L.leerNumero("  ") === null);
ok("leerNumero abc → NaN", Number.isNaN(L.leerNumero("abc")) && Number.isNaN(L.leerNumero("1,2,3")) && Number.isNaN(L.leerNumero("12e3")));
ok("leerNumero negativo", L.leerNumero("-3,5") === -3.5);

// ---- Aplanado de datos ----
{
  const { datos, errores } = L.aplanarDatos(sus, { lectura: "1.234,5", sellos: "3", despeje_caja: "si", despeje_observacion: "  caja tapada ", diametro: "d34", materiales: ["pvc", "cu"], cita_acordada: "2026-11-12T08:30", telefono_contacto: "3001234567" });
  ok("aplanar: tipos correctos (número, entero, booleano, texto recortado, opción, opciones, día y hora)", igual(datos, { lectura: 1234.5, sellos: 3, despeje_caja: true, despeje_observacion: "caja tapada", diametro: "d34", materiales: ["pvc", "cu"], cita_acordada: "2026-11-12T08:30", telefono_contacto: "3001234567" }));
  ok("aplanar: sin errores", Object.keys(errores).length === 0);
}
ok("aplanar: «No» es false (no se pierde)", L.aplanarDatos(sus, { despeje_caja: "no" }).datos.despeje_caja === false);
ok("aplanar: lo vacío no se envía", igual(L.aplanarDatos(sus, { lectura: "", sellos: "  ", despeje_caja: "", materiales: [] }).datos, null));
ok("aplanar: el campo apagado (activo=false) se ignora aunque traiga valor", !("oculto" in (L.aplanarDatos(sus, { lectura: "1", oculto: "x" }).datos)));
ok("aplanar: un código que no está en el catálogo no pasa", !("intruso" in (L.aplanarDatos(sus, { lectura: "1", intruso: "x" }).datos)));
ok("aplanar: ninguna clave lleva «fecha» ni nombres prohibidos", Object.keys(L.aplanarDatos(sus, { cita_acordada: "2026-11-12T08:30", lectura: "2" }).datos).every((k) => !/fecha|usuario|email|autor|solicitante/i.test(k)));
ok("error: número ilegible", "lectura" in L.aplanarDatos(sus, { lectura: "abc" }).errores);
ok("error: fuera de rango (negativo)", "lectura" in L.aplanarDatos(sus, { lectura: "-1" }).errores);
ok("error: fuera de rango (máximo)", "lectura" in L.aplanarDatos(sus, { lectura: "10.000.000" }).errores);
ok("error: entero con decimales", "sellos" in L.aplanarDatos(sus, { sellos: "2,5" }).errores);
ok("error: entero sobre el máximo", "sellos" in L.aplanarDatos(sus, { sellos: "11" }).errores);
ok("error: texto más largo que el máximo", "despeje_observacion" in L.aplanarDatos(sus, { despeje_observacion: "a".repeat(121) }).errores);
ok("error: opción apagada", "diametro" in L.aplanarDatos(sus, { diametro: "viejo" }).errores);
ok("error: opción inexistente", "diametro" in L.aplanarDatos(sus, { diametro: "zz" }).errores);
ok("error: opciones repetidas o inexistentes", "materiales" in L.aplanarDatos(sus, { materiales: ["pvc", "pvc"] }).errores && "materiales" in L.aplanarDatos(sus, { materiales: ["zz"] }).errores);
ok("error: día y hora mal formado", "cita_acordada" in L.aplanarDatos(sus, { cita_acordada: "12/11/2026" }).errores);
ok("error: día y hora antes de 2020", "cita_acordada" in L.aplanarDatos(sus, { cita_acordada: "2019-01-01T08:00" }).errores);

// ---- Contador y mínimos ----
ok("contador «3 de 5 (mínimo 3)»", L.contadorFotos(3, 3, 5) === "3 de 5 (mínimo 3)");
ok("mínimo efectiva = fotos_min del formato", L.minimoFotos(sus, "efectivo") === 3 && L.minimoFotos(sus, "") === 3);
ok("mínimo inefectiva = 1", L.minimoFotos(sus, "inefectivo") === 1);
ok("mínimo inefectiva si el formato pide 0 = 0", L.minimoFotos({ ...sus, fotos_min: 0 }, "inefectivo") === 0);
ok("máximo: el del formato o el general", L.maximoFotos(sus, 10) === 5 && L.maximoFotos(viejoSinD, 2) === 2);

// ---- Validación: efectiva ----
ok("efectiva completa: sin faltas", L.validarFormato(sus, base()).length === 0);
ok("sin resultado: falta indicar", L.validarFormato(sus, base({ resultado: "" })).some((m) => m.includes("efectiva o inefectiva")));
ok("falta un campo obligatorio (lectura)", L.validarFormato(sus, base({ valores: { diametro: "d12" } })).some((m) => m.includes("Lectura")));
ok("el campo apagado obligatorio NO se exige", !L.validarFormato(sus, base()).some((m) => m.includes("apagado")));
ok("menos fotos del mínimo", L.validarFormato(sus, base({ etiquetasConFoto: ["fachada", "medidor"] })).some((m) => m.includes("al menos 3")));
ok("falta una etiqueta obligatoria aunque el total alcance (2 etiquetas + 1 adicional)", L.validarFormato(sus, base({ etiquetasConFoto: ["fachada", "sello"], adicionales: 1 })).some((m) => m.includes("«Medidor»")));
ok("la etiqueta apagada (obligatoria) NO se exige", !L.validarFormato(sus, base()).some((m) => m.includes("apagada")));
ok("adicionales cuentan para el mínimo (2 obligatorias + 1 adicional = 3)", L.validarFormato(sus, base({ etiquetasConFoto: ["fachada", "medidor"], adicionales: 1 })).length === 0);
ok("más fotos que el máximo", L.validarFormato(sus, base({ adicionales: 3 })).some((m) => m.includes("máximo 5")));
ok("exactamente el máximo (3 + 2 adicionales) pasa", L.validarFormato(sus, base({ adicionales: 2 })).length === 0);
ok("sin contrato donde es obligatorio", L.validarFormato(sus, base({ contrato: "" })).some((m) => m.includes("contrato")));
ok("contrato opcional no se exige", !L.validarFormato({ ...sus, requiere_contrato: "opcional" }, base({ contrato: "" })).some((m) => m.includes("contrato")));
ok("sin ubicación", L.validarFormato(sus, base({ tieneUbicacion: false })).some((m) => m.includes("ubicación")));
ok("subtipo obligatorio (exige_subtipo)", L.validarFormato({ ...sus, exige_subtipo: true }, base()).some((m) => m.includes("subtipo")) && L.validarFormato({ ...sus, exige_subtipo: true }, base({ subtipo: "sencillo" })).length === 0);
ok("descripción obligatoria (exige_texto)", L.validarFormato({ ...sus, exige_texto: true }, base()).some((m) => m.includes("describa")));
ok("efectiva con causal elegida no la exige ni la envía (la causal solo cuenta en inefectiva)", L.validarFormato(sus, base({ causal: "no_hay_acceso" })).length === 0);
ok("un valor inválido se señala aunque el campo sea opcional", L.validarFormato(sus, base({ valores: { lectura: "1", diametro: "d12", sellos: "99" } })).some((m) => m.includes("Sellos")));

// ---- Regla de INEFECTIVO ----
const ine = (extra = {}) => base({ resultado: "inefectivo", causal: "no_hay_acceso", valores: {}, etiquetasConFoto: ["fachada"], ...extra });
ok("inefectiva mínima (causal + fachada + precisión): sin faltas, sin campos ni fotos obligatorias", L.validarFormato(sus, ine()).length === 0);
ok("inefectiva sin causal", L.validarFormato(sus, ine({ causal: "" })).some((m) => m.includes("causal")));
ok("inefectiva con causal que no es del formato", L.validarFormato(sus, ine({ causal: "otra" })).some((m) => m.includes("no aplica")));
ok("inefectiva sin foto de soporte (solo «Medidor»)", L.validarFormato(sus, ine({ etiquetasConFoto: ["medidor"] })).some((m) => m.includes("«Fachada»")));
ok("inefectiva sin ninguna foto", L.validarFormato(sus, ine({ etiquetasConFoto: [] })).length >= 1);
ok("inefectiva sin precisión de la ubicación", L.validarFormato(sus, ine({ tienePrecision: false })).some((m) => m.includes("precisión")));
ok("inefectiva NO exige las etiquetas obligatorias de la efectiva (Medidor)", !L.validarFormato(sus, ine()).some((m) => m.includes("Medidor")));
ok("inefectiva NO exige campos obligatorios", !L.validarFormato(sus, ine()).some((m) => m.includes("Falta «")));
ok("inefectiva: lo que sí se digitó se valida igual", L.validarFormato(sus, ine({ valores: { lectura: "abc" } })).some((m) => m.includes("Lectura")));
ok("inefectiva con las 3 fotos y más: sigue válida mientras no pase el máximo", L.validarFormato(sus, ine({ etiquetasConFoto: ["fachada", "medidor", "sello"], adicionales: 2 })).length === 0);
ok("formato sin foto de soporte en el catálogo: inefectiva solo pide causal, mínimo 1 y precisión", L.validarFormato({ ...sus, fotos: sus.fotos.map((f) => ({ ...f, soporte_inefectiva: false })) }, ine({ etiquetasConFoto: ["medidor"] })).length === 0);
ok("formato que no genera resultado no pide efectiva ni inefectiva", L.validarFormato({ ...sus, genera_resultado: false }, base({ resultado: "" })).length === 0);

// ---- Orden y etiquetas de las fotos que viajan ----
{
  const o = L.ordenarFotos(sus, { sello: "S", fachada: "F", medidor: null }, ["A1", "A2"]);
  ok("orden: etiquetas en el orden del catálogo y luego adicionales, numeradas 1.. sin saltos", igual(o.map((x) => [x.orden, x.etiqueta, x.foto]), [[1, "fachada", "F"], [2, "sello", "S"], [3, "adicional", "A1"], [4, "adicional", "A2"]]));
  ok("orden: las etiquetas de catálogo no se repiten", new Set(o.filter((x) => x.etiqueta !== "adicional").map((x) => x.etiqueta)).size === o.filter((x) => x.etiqueta !== "adicional").length);
  ok("orden: una foto de etiqueta apagada no viaja", !L.ordenarFotos(sus, { vieja: "V" }, []).length);
  const sinEtq = L.ordenarFotos(general, {}, ["X", "Y"]);
  ok("formato sin etiquetas: las fotos van sin etiqueta (la base rechaza etiquetas donde no se usan)", sinEtq.every((x) => x.etiqueta === null) && sinEtq.length === 2);
  const rutas = new Map([[1, "r1"], [2, "r2"], [3, "r3"], [4, "r4"]]);
  const cuerpo = L.fotosParaCrear(o, rutas);
  ok("fotosParaCrear: orden, ruta y etiqueta", igual(cuerpo, [{ orden: 1, ruta: "r1", etiqueta: "fachada" }, { orden: 2, ruta: "r2", etiqueta: "sello" }, { orden: 3, ruta: "r3", etiqueta: "adicional" }, { orden: 4, ruta: "r4", etiqueta: "adicional" }]));
  ok("fotosParaCrear sin etiquetas: la clave etiqueta no aparece", !("etiqueta" in L.fotosParaCrear(sinEtq, new Map([[1, "a"], [2, "b"]]))[0]));
}

// ===== Acta de revisión o instalación: secciones y campos condicionales (solo pantalla) =====
{
  const S1 = "1. Datos básicos", S3 = "3. Estado del medidor", S8 = "8. Irregularidades";
  const rev = {
    codigo: "revision_previa", nombre: "Revisión previa", orden: 1, activo: true, exige_texto: false, exige_subtipo: false, tiene_subtipos: false, subtipos: [],
    fotos_min: 2, fotos_max: 6, requiere_contrato: "si", genera_resultado: true, usa_consecutivo: true, causales: [{ codigo: "nadie_atiende", nombre: "No hay quien atienda" }],
    campos: [
      { codigo: "serie_acta", nombre: "Serie del acta física", tipo_dato: "texto", obligatorio: true, maximo: 20, seccion: S1, orden: 101, activo: true },
      { codigo: "habitantes", nombre: "Habitantes", tipo_dato: "entero", obligatorio: false, minimo: 0, maximo: 99, seccion: S1, orden: 102, activo: true },
      { codigo: "calib_realizada", nombre: "¿Se realizó la calibración?", tipo_dato: "si_no", obligatorio: false, seccion: S3, orden: 305, activo: true },
      { codigo: "calib_vol_patron", nombre: "Volumen del patrón", tipo_dato: "decimal", obligatorio: false, minimo: 0, maximo: 100000, unidad: "L", seccion: S3, visible_si: { campo: "calib_realizada", es: true }, orden: 306, activo: true },
      { codigo: "irr_hay", nombre: "¿Irregularidad?", tipo_dato: "si_no", obligatorio: true, seccion: S8, orden: 801, activo: true },
      { codigo: "irr_tipos", nombre: "Tipos de irregularidad", tipo_dato: "opciones", obligatorio: false, opciones: [{ codigo: "a", nombre: "A" }, { codigo: "b", nombre: "B" }], seccion: S8, visible_si: { campo: "irr_hay", es: true }, orden: 802, activo: true },
      { codigo: "tipo_srv", nombre: "Tipo de servicio", tipo_dato: "opcion", obligatorio: false, opciones: [{ codigo: "res", nombre: "Residencial" }, { codigo: "com", nombre: "Comercial" }], seccion: S1, orden: 103, activo: true },
      { codigo: "detalle_com", nombre: "Detalle comercial", tipo_dato: "texto", obligatorio: false, maximo: 20, seccion: S1, visible_si: { campo: "tipo_srv", es: "com" }, orden: 104, activo: true },
      { codigo: "viejo", nombre: "Campo apagado", tipo_dato: "texto", obligatorio: true, seccion: S1, orden: 105, activo: false },
    ],
    fotos: [{ codigo: "fachada_predio", nombre: "Fachada o predio", obligatoria: true, soporte_inefectiva: true, orden: 1, activo: true }, { codigo: "acta_fisica", nombre: "Acta física firmada", obligatoria: true, soporte_inefectiva: false, orden: 9, activo: true }],
  };
  const campo = (c) => rev.campos.find((x) => x.codigo === c);
  ok("esVisible: sin condición siempre se muestra", L.esVisible(campo("serie_acta"), {}));
  ok("esVisible: condición sí/no oculta mientras el padre está sin responder", !L.esVisible(campo("calib_vol_patron"), {}) && !L.esVisible(campo("calib_vol_patron"), { calib_realizada: "" }));
  ok("esVisible: se muestra con «sí» y se oculta con «no»", L.esVisible(campo("calib_vol_patron"), { calib_realizada: "si" }) && !L.esVisible(campo("calib_vol_patron"), { calib_realizada: "no" }));
  ok("esVisible: condición por código de opción", L.esVisible(campo("detalle_com"), { tipo_srv: "com" }) && !L.esVisible(campo("detalle_com"), { tipo_srv: "res" }));
  ok("esVisible: condición sobre una lista de opciones", L.esVisible({ ...campo("detalle_com"), visible_si: { campo: "irr_tipos", es: "a" } }, { irr_tipos: ["b", "a"] }) && !L.esVisible({ ...campo("detalle_com"), visible_si: { campo: "irr_tipos", es: "a" } }, { irr_tipos: ["b"] }));
  ok("camposVisibles: excluye el campo apagado y los ocultos por condición", igual(L.camposVisibles(rev, {}).map((c) => c.codigo), ["serie_acta", "habitantes", "calib_realizada", "irr_hay", "tipo_srv"].sort((a, b) => rev.campos.findIndex((x) => x.codigo === a) - rev.campos.findIndex((x) => x.codigo === b))));
  const secs = L.agruparSecciones(L.camposVisibles(rev, { calib_realizada: "si", irr_hay: "si", tipo_srv: "com" }));
  ok("agruparSecciones: consecutivos con el mismo título forman una sección (aquí la 1 se parte porque los campos no son consecutivos en el catálogo)", secs.length >= 3 && secs[0].titulo === S1);
  const catalogoOrdenado = [...rev.campos].filter((c) => c.activo).sort((a, b) => a.orden - b.orden);
  const porSec = L.agruparSecciones(catalogoOrdenado);
  ok("agruparSecciones: con el catálogo en su orden salen 3 secciones, cada una una sola vez", porSec.length === 3 && igual(porSec.map((x) => x.titulo), [S1, S3, S8]) && porSec[0].campos.length === 4);
  ok("agruparSecciones: sin títulos, una sola sección sin título (formulario plano de siempre)", (() => { const r = L.agruparSecciones(sus.campos); return r.length === 1 && r[0].titulo === null && r[0].campos.length === sus.campos.length; })());
  ok("agruparSecciones: lista vacía", L.agruparSecciones([]).length === 0);
  const a1 = L.avanceSeccion(porSec[0].campos, { serie_acta: "A1" }, false);
  ok("avanceSeccion: respondidos, total y obligatorios que faltan", a1.respondidos === 1 && a1.total === 4 && a1.faltan === 0);
  ok("avanceSeccion: falta el obligatorio sin responder, y en visita inefectiva no cuenta", L.avanceSeccion(porSec[0].campos, {}, false).faltan === 1 && L.avanceSeccion(porSec[0].campos, {}, true).faltan === 0);
  const ag = L.aplanarDatos(rev, { serie_acta: "A1", calib_vol_patron: "10,5", calib_realizada: "no", irr_hay: "no", irr_tipos: ["a"] });
  ok("aplanarDatos: lo digitado en un campo que quedó oculto NO se envía (calibración con «no», tipos de irregularidad con «no»)", igual(ag.datos, { serie_acta: "A1", calib_realizada: false, irr_hay: false }));
  const ag2 = L.aplanarDatos(rev, { serie_acta: "A1", calib_realizada: "si", calib_vol_patron: "10,5", irr_hay: "si", irr_tipos: ["a", "b"] });
  ok("aplanarDatos: con la condición cumplida el campo viaja (decimal con coma colombiana)", ag2.datos.calib_vol_patron === 10.5 && igual(ag2.datos.irr_tipos, ["a", "b"]));
  ok("aplanarDatos: un campo oculto con un valor inválido no produce error", Object.keys(L.aplanarDatos(rev, { calib_realizada: "no", calib_vol_patron: "abc" }).errores).length === 0);
  ok("aplanarDatos: el mismo valor inválido, ya visible, sí produce error", "calib_vol_patron" in L.aplanarDatos(rev, { calib_realizada: "si", calib_vol_patron: "abc" }).errores);
  const est = { resultado: "efectivo", causal: "", subtipo: "", descripcion: "", contrato: "123", valores: { serie_acta: "A1", irr_hay: "no" }, etiquetasConFoto: ["fachada_predio", "acta_fisica"], adicionales: 0, tieneUbicacion: true, tienePrecision: true, topeGeneral: 2 };
  ok("validarFormato: con lo obligatorio y las fotos del papel, no falta nada", L.validarFormato(rev, est).length === 0);
  ok("validarFormato: sin la foto del acta física falta esa foto", L.validarFormato(rev, { ...est, etiquetasConFoto: ["fachada_predio"] }).some((m) => m.includes("Acta física firmada")));
  ok("validarFormato: un obligatorio oculto por condición no se exige", L.validarFormato({ ...rev, campos: [...rev.campos, { codigo: "extra", nombre: "Extra", tipo_dato: "texto", obligatorio: true, visible_si: { campo: "irr_hay", es: true }, orden: 900, activo: true }] }, est).length === 0);
  ok("validarFormato: visita inefectiva con solo la fachada: no se exigen campos ni el papel", L.validarFormato(rev, { ...est, resultado: "inefectivo", causal: "nadie_atiende", valores: {}, etiquetasConFoto: ["fachada_predio"] }).length === 0);
  ok("marcoIrregularidad: solo con irr_hay = «sí»", L.marcoIrregularidad(rev, { irr_hay: "si" }) && !L.marcoIrregularidad(rev, { irr_hay: "no" }) && !L.marcoIrregularidad(rev, {}));
  ok("marcoIrregularidad: un formato sin ese campo nunca invita a abrir el acta", !L.marcoIrregularidad(sus, { irr_hay: "si" }));
  ok("un formato del Paso D sin secciones ni condiciones se comporta igual que antes (mismos campos visibles)", L.camposVisibles(sus, {}).length === T.camposActivos(sus).length);
  // «Quién atendió» (visible_si con «no_es»)
  const qa = [
    { codigo: "firma_atendio", nombre: "Firma", tipo_dato: "opcion", obligatorio: true, opciones: [{ codigo: "atendio_firmo", nombre: "Atendió y firmó" }, { codigo: "nadie_atendio", nombre: "Nadie atendió" }], seccion: S1, orden: 901, activo: true },
    { codigo: "atendio_nombre", nombre: "Nombre de quien atendió", tipo_dato: "texto", obligatorio: false, maximo: 60, sensible: true, seccion: "10. Quién atendió", visible_si: { campo: "firma_atendio", no_es: "nadie_atendio" }, orden: 910, activo: true },
    { codigo: "atendio_relacion", nombre: "Relación con el predio", tipo_dato: "opcion", obligatorio: false, opciones: [{ codigo: "propietario", nombre: "Propietario" }, { codigo: "otro", nombre: "Otro (¿cuál?)" }], seccion: "10. Quién atendió", visible_si: { campo: "firma_atendio", no_es: "nadie_atendio" }, orden: 911, activo: true },
    { codigo: "atendio_relacion_otra", nombre: "¿Cuál otra relación?", tipo_dato: "texto", obligatorio: false, maximo: 40, seccion: "10. Quién atendió", visible_si: { campo: "atendio_relacion", es: "otro" }, orden: 912, activo: true },
  ];
  const fq = { ...rev, campos: qa };
  const nom = (v) => L.camposVisibles(fq, v).map((c) => c.codigo).join(",");
  ok("no_es: sin responder la firma, nombre y relación no se muestran", nom({}) === "firma_atendio" && nom({ firma_atendio: "" }) === "firma_atendio");
  ok("no_es: «Nadie atendió» los oculta", nom({ firma_atendio: "nadie_atendio" }) === "firma_atendio");
  ok("no_es: con «Atendió y firmó» se muestran nombre y relación", nom({ firma_atendio: "atendio_firmo" }) === "firma_atendio,atendio_nombre,atendio_relacion");
  ok("no_es: «Otro» muestra «¿Cuál otra relación?»", nom({ firma_atendio: "atendio_firmo", atendio_relacion: "otro" }).endsWith("atendio_relacion_otra"));
  ok("no_es: «¿Cuál?» con valor viejo se oculta si su padre está oculto", nom({ firma_atendio: "nadie_atendio", atendio_relacion: "otro", atendio_relacion_otra: "x" }) === "firma_atendio");
  ok("no_es: no se envía el nombre cuando nadie atendió", !("atendio_nombre" in L.aplanarDatos(fq, { firma_atendio: "nadie_atendio", atendio_nombre: "Juan" }).datos));
  ok("no_es: el nombre viaja cuando alguien atendió", L.aplanarDatos(fq, { firma_atendio: "atendio_firmo", atendio_nombre: " Juan Pérez " }).datos.atendio_nombre === "Juan Pérez");
  ok("no_es: nombre y relación vacíos no bloquean (son opcionales)", L.validarFormato({ ...rev, campos: [...rev.campos.filter((c) => c.codigo !== "firma_atendio"), ...qa] }, { ...est, valores: { ...est.valores, firma_atendio: "atendio_firmo" } }).length === 0);
  ok("no_es: una lista de opciones se evalúa por inclusión", L.esVisible(qa[1], { firma_atendio: ["atendio_firmo"] }) && !L.esVisible(qa[1], { firma_atendio: ["nadie_atendio"] }));
}

console.log(`\nRESULTADO: ${total - fallas} de ${total} pruebas correctas — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
process.exit(fallas ? 1 : 0);
