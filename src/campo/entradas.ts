// Entradas del área «Formatos de campo» (Torre A). Cada pantalla es UNA entrada de esta lista; agregar una nueva pantalla = agregar una entrada aquí y un caso en AreaCampo.
// Lógica pura (sin React): se prueba sola en scripts/prueba_integracion.mjs.

export type EntradaId = "reporte_general" | "formatos" | "acta" | "analisis_contrato" | "acta_supervision" | "revision" | "activo_campo" | "reparto" | "reparto_supervision";

export type EntradaCampo = {
  id: EntradaId;
  titulo: string;
  /** Vacía en las entradas de gestión (solo el nombre). */
  descripcion: string;
  /** ¿Se puede abrir ya? Una entrada pendiente se dibuja como «Próximamente» y no hace nada. */
  habilitada: boolean;
  /** MARCADOR: la pantalla de esta entrada aún no existe (hoy ninguna lo usa; «Análisis de contrato» ya tiene pantalla). */
  pendiente?: boolean;
  /** Bloque visual (1 anomalía · 2 formatos · 3 pérdida y análisis · 4 gestión). Entre bloques distintos se dibuja una separación. */
  seccion: 1 | 2 | 3 | 4;
  /** Entrada de gestión (supervisión): va en el color de gestión, igual que en Aseo. */
  gestion?: boolean;
  /** Abre más opciones (se dibuja con flecha ›). */
  abreMas?: boolean;
  /** 25-nov (David): «Registrar en campo» (lo que hace el operario) o «Supervisar» (una tarjeta por motor; cada actividad nueva suma la suya, no se unen en un tablero). */
  bloque: BloqueEntrada;
};
export type BloqueEntrada = "registrar" | "supervisar";
export const ROTULO_BLOQUE: Record<BloqueEntrada, string> = { registrar: "Registrar en campo", supervisar: "Supervisar" };
/** Las entradas de un bloque, en su orden. */
export const entradasDelBloque = (es: EntradaCampo[], b: BloqueEntrada): EntradaCampo[] => es.filter((e) => e.bloque === b);
/** Bloques que se dibujan: las pestañas solo salen si la persona tiene entradas en los dos. */
export const bloquesVisibles = (es: EntradaCampo[]): BloqueEntrada[] => (["registrar", "supervisar"] as const).filter((b) => es.some((e) => e.bloque === b));

export type CondicionesEntradas = {
  /** El servidor dice que la persona puede reportar (def.puede.reportar). */
  puedeReportar: boolean;
  /** Hay al menos un formato del Paso D activo en el catálogo. */
  hayFormatos: boolean;
  /** Permiso `ver_acta` (clave `acta` del perfil): puede capturar actas. Lo decide el servidor; el supervisor de actas también lo tiene. */
  puedeActa: boolean;
  /** Permiso de campo (reportar o supervisar). Por omisión verdadero (como antes). Quien solo tiene acta NO ve «Reportar anomalía» ni «Formatos de actividad». */
  puedeCampo?: boolean;
  /** Permiso `ver_dashboard_acta` (supervisor de actas) o administrador: abre «Aperturas sin registrar» (pantalla mínima; el tablero completo de actas sigue pendiente). */
  puedeSupervisarActas?: boolean;
  /** El servidor dice que la persona puede supervisar (def.puede.supervisar: supervisor o administrador). Es el permiso `ver_dashboard_campo`; quien reporta nunca ve la lista. */
  puedeSupervisar?: boolean;
  /** Permiso `analisis_contrato` (o administrador): abre «Análisis de contrato». Sin él la entrada no aparece. Puede venir solo (usuario comercial sin campo, decisión 12). */
  puedeAnalisis?: boolean;
  /** Corte 14 de Técnica: muestra «Encontrar o reportar activo» (quien tiene Formularios de campo). Por omisión no (como antes). */
  puedeActivoCampo?: boolean;
  /** Reparto de facturas (24-nov): actividad «Reparto» en Personal de Comercial (lo dice el servidor: geoportal-reparto, ruta perfil). Por omisión no. */
  puedeRepartir?: boolean;
  /** Reparto de facturas: actividad «Supervisión de reparto» (o administrador). Por omisión no. */
  puedeSupervisarReparto?: boolean;
};

/** Entradas visibles, en orden (14/11/2026): «Reportar anomalía» · «Formatos de actividad» (solo si hay formatos activos) · «Reportar posible pérdida» (SOLO con el permiso de acta)
 *  y «Análisis de contrato» (solo con el permiso `analisis_contrato`) · al final, en color de gestión, «Aperturas sin registrar» y «Supervisión y dashboard».
 *  Solo cambian los nombres visibles: los id internos (reporte_general, acta, revision…) siguen iguales. */
/** 22-nov (R3): «Actas registradas» la abren el supervisor de actas (dashboard_acta; lee por geoportal-acta, con «Aperturas sin registrar») y el supervisor de campo
 *  (dashboard_campo, que el servidor declara como def.puede.supervisar; lee por geoportal-campo, sin «Aperturas sin registrar»). El administrador tiene las dos. */
export const veActasRegistradas = (c: Pick<CondicionesEntradas, "puedeSupervisarActas" | "puedeSupervisar">) => c.puedeSupervisarActas === true || c.puedeSupervisar === true;

export function entradasDeCampo(c: CondicionesEntradas): EntradaCampo[] {
  const e: EntradaCampo[] = [];
  const campo = c.puedeCampo !== false;
  if (campo) e.push({
    id: "reporte_general", titulo: "Reportar anomalía", seccion: 1, bloque: "registrar",
    descripcion: "Registre en segundos lo que encontró: tipo, fotos, ubicación y contrato.", habilitada: c.puedeReportar,
  });
  if (campo && c.hayFormatos) e.push({
    id: "formatos", titulo: "Formatos de actividad", seccion: 2, abreMas: true, bloque: "registrar",
    descripcion: "Suspensión, corte, instalaciones y otras actividades, con sus campos, fotos y resultado.", habilitada: c.puedeReportar,
  });
  // Corte 14 de Técnica: «Encontrar o reportar activo» (la misma pantalla de Técnica). La ve quien tiene Formularios de campo; el servidor lo vuelve a decidir al abrirla.
  if (campo && c.puedeActivoCampo === true) e.push({
    id: "activo_campo", titulo: "Encontrar o reportar activo", seccion: 2, bloque: "registrar",
    descripcion: "Vea los activos de la red que tiene cerca o reporte uno que no está.", habilitada: true,
  });
  // Reparto de facturas (24-nov): quien tiene la actividad «Reparto» en Personal de Comercial
  if (campo && c.puedeRepartir === true) e.push({
    id: "reparto", titulo: "Reparto de facturas", seccion: 2, bloque: "registrar", habilitada: true,
    descripcion: "Escoja su ruta y marque cada factura entregada, con su ubicación, en el orden en que reparte.",
  });
  if (c.puedeActa) e.push({
    id: "acta", titulo: "Reportar posible pérdida", seccion: 3, bloque: "registrar",
    descripcion: "Registro digital que acompaña al acta física firmada.", habilitada: true,
  });
  if (c.puedeAnalisis === true) e.push({
    id: "analisis_contrato", titulo: "Análisis de contrato", seccion: 3, bloque: "registrar", habilitada: true,   // 26-nov (David): vuelve a llamarse así (fue «Consultar»)
    descripcion: "Escriba un contrato y vea cartera, consumo, medidor, gestiones y ubicación.",
  });
  // Comercial 21-nov (B2): «Actas registradas» reúne las actas con PDF, las actividades derivadas, «Aperturas sin registrar» y Personal en solo lectura (el id interno no cambia).
  // 22-nov (R3, David): también el supervisor de campo (dashboard_campo); lee por geoportal-campo (campo.f_autorizar_registradas). Ver veActasRegistradas.
  if (veActasRegistradas(c)) e.push({ id: "acta_supervision", titulo: "Actas registradas", seccion: 4, bloque: "supervisar", gestion: true, descripcion: "Actas con su PDF, avisos y actividades derivadas, aperturas sin registrar y personal.", habilitada: true });
  // Paso C: «Supervisión y dashboard» (antes «Revisión de reportes»: lista, mapa, indicadores; y catálogo y parámetros para el administrador) solo con el permiso de supervisión
  if (c.puedeSupervisar) e.push({ id: "revision", titulo: "Supervisión y dashboard", seccion: 4, bloque: "supervisar", gestion: true, descripcion: "Reportes, indicadores, catálogo, parámetros, personal y cuadrillas.", habilitada: true });
  // Reparto de facturas: el supervisor de reparto (actividad «Supervisión de reparto»; dashboard_campo solo no basta)
  if (campo && c.puedeSupervisarReparto === true) e.push({ id: "reparto_supervision", titulo: "Reparto de facturas · Supervisión", seccion: 4, bloque: "supervisar", gestion: true, descripcion: "Archivos de ruta, avance, mapa y calendario del reparto.", habilitada: true });
  return e;
}
