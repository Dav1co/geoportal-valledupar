// Entradas del área «Formatos de campo» (Torre A). Cada pantalla es UNA entrada de esta lista; agregar una nueva pantalla = agregar una entrada aquí y un caso en AreaCampo.
// Lógica pura (sin React): se prueba sola en scripts/prueba_integracion.mjs.

export type EntradaId = "reporte_general" | "formatos" | "acta" | "analisis_contrato" | "acta_supervision" | "revision";

export type EntradaCampo = {
  id: EntradaId;
  titulo: string;
  /** Vacía en las entradas de gestión (solo el nombre). */
  descripcion: string;
  /** ¿Se puede abrir ya? Una entrada pendiente se dibuja como «Próximamente» y no hace nada. */
  habilitada: boolean;
  /** MARCADOR: la pantalla de esta entrada aún no existe («Análisis de contrato»). */
  pendiente?: boolean;
  /** Bloque visual (1 anomalía · 2 formatos · 3 pérdida y análisis · 4 gestión). Entre bloques distintos se dibuja una separación. */
  seccion: 1 | 2 | 3 | 4;
  /** Entrada de gestión (supervisión): va en el color de gestión, igual que en Aseo. */
  gestion?: boolean;
  /** Abre más opciones (se dibuja con flecha ›). */
  abreMas?: boolean;
};

export type CondicionesEntradas = {
  /** El servidor dice que la persona puede reportar (def.puede.reportar). */
  puedeReportar: boolean;
  /** Hay al menos un formato del Paso D activo en el catálogo. */
  hayFormatos: boolean;
  /** Permiso `ver_acta` (clave `acta` del perfil): puede capturar actas. Lo decide el servidor; el supervisor de actas también lo tiene. */
  puedeActa: boolean;
  /** Permiso de campo (reportar o supervisar). Por omisión verdadero (como antes). Quien solo tiene acta NO ve «Reportar anomalía», «Formatos de actividad» ni «Análisis de contrato». */
  puedeCampo?: boolean;
  /** Permiso `ver_dashboard_acta` (supervisor de actas) o administrador: abre «Aperturas sin registrar» (pantalla mínima; el tablero completo de actas sigue pendiente). */
  puedeSupervisarActas?: boolean;
  /** El servidor dice que la persona puede supervisar (def.puede.supervisar: supervisor o administrador). Es el permiso `ver_dashboard_campo`; quien reporta nunca ve la lista. */
  puedeSupervisar?: boolean;
};

/** Entradas visibles, en orden (14/11/2026): «Reportar anomalía» · «Formatos de actividad» (solo si hay formatos activos) · «Reportar posible pérdida» (SOLO con el permiso de acta)
 *  y «Análisis de contrato» (Próximamente, solo con campo) · al final, en color de gestión, «Aperturas sin registrar» y «Supervisión y dashboard».
 *  Solo cambian los nombres visibles: los id internos (reporte_general, acta, revision…) siguen iguales. */
export function entradasDeCampo(c: CondicionesEntradas): EntradaCampo[] {
  const e: EntradaCampo[] = [];
  const campo = c.puedeCampo !== false;
  if (campo) e.push({
    id: "reporte_general", titulo: "Reportar anomalía", seccion: 1,
    descripcion: "Registre en segundos lo que encontró: tipo, fotos, ubicación y contrato.", habilitada: c.puedeReportar,
  });
  if (campo && c.hayFormatos) e.push({
    id: "formatos", titulo: "Formatos de actividad", seccion: 2, abreMas: true,
    descripcion: "Suspensión, corte, instalaciones y otras actividades, con sus campos, fotos y resultado.", habilitada: c.puedeReportar,
  });
  if (c.puedeActa) e.push({
    id: "acta", titulo: "Reportar posible pérdida", seccion: 3,
    descripcion: "Registro digital que acompaña al acta física firmada.", habilitada: true,
  });
  if (campo) e.push({
    id: "analisis_contrato", titulo: "Análisis de contrato", seccion: 3, pendiente: true,
    descripcion: "Escriba un contrato y vea todo: comercial, medidor, consumos, gestiones y ubicación.", habilitada: false,
  });
  if (c.puedeSupervisarActas) e.push({ id: "acta_supervision", titulo: "Aperturas sin registrar", seccion: 4, gestion: true, descripcion: "", habilitada: true });
  // Paso C: «Supervisión y dashboard» (antes «Revisión de reportes»: lista, mapa, indicadores; y catálogo y parámetros para el administrador) solo con el permiso de supervisión
  if (c.puedeSupervisar) e.push({ id: "revision", titulo: "Supervisión y dashboard", seccion: 4, gestion: true, descripcion: "", habilitada: true });
  return e;
}
