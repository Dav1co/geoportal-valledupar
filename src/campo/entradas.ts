// Entradas del área «Formatos de campo» (Torre A). Cada pantalla es UNA entrada de esta lista; agregar una nueva pantalla = agregar una entrada aquí y un caso en AreaCampo.
// Lógica pura (sin React): se prueba sola en scripts/prueba_integracion.mjs.

export type EntradaId = "reporte_general" | "formatos" | "acta" | "revision";

export type EntradaCampo = {
  id: EntradaId;
  titulo: string;
  descripcion: string;
  /** ¿Se puede abrir ya? Una entrada pendiente se dibuja como «Próximamente» y no hace nada. */
  habilitada: boolean;
  /** MARCADOR: la pantalla de esta entrada aún no existe (acta de inspección, Paso B de la pantalla). Se quita cuando se construya. */
  pendiente?: boolean;
};

export type CondicionesEntradas = {
  /** El servidor dice que la persona puede reportar (def.puede.reportar). */
  puedeReportar: boolean;
  /** Hay al menos un formato del Paso D activo en el catálogo. */
  hayFormatos: boolean;
  /** Permiso `ver_acta` (clave `acta` del perfil): puede capturar actas. Lo decide el servidor; el supervisor de actas también lo tiene. */
  puedeActa: boolean;
  /** El servidor dice que la persona puede supervisar (def.puede.supervisar: supervisor o administrador). Es el permiso `ver_dashboard_campo`; quien reporta nunca ve la lista. */
  puedeSupervisar?: boolean;
};

/** Entradas visibles, en orden. «Reporte general» siempre; «Formatos de actividad» solo si hay formatos activos; «Acta de inspección» SOLO con el permiso de acta. */
export function entradasDeCampo(c: CondicionesEntradas): EntradaCampo[] {
  const e: EntradaCampo[] = [{
    id: "reporte_general", titulo: "Reporte general",
    descripcion: "Registre en segundos lo que encontró: tipo, fotos, ubicación y contrato.", habilitada: c.puedeReportar,
  }];
  if (c.hayFormatos) e.push({
    id: "formatos", titulo: "Formatos de actividad",
    descripcion: "Suspensión, corte, instalaciones y otras actividades, con sus campos, fotos y resultado.", habilitada: c.puedeReportar,
  });
  if (c.puedeActa) e.push({
    id: "acta", titulo: "Acta de inspección",
    descripcion: "Registro digital que acompaña al acta física firmada.", habilitada: false, pendiente: true,
  });
  // Paso C: «Revisión de reportes» (lista, mapa, indicadores; y catálogo y parámetros para el administrador) solo con el permiso de supervisión
  if (c.puedeSupervisar) e.push({
    id: "revision", titulo: "Revisión de reportes",
    descripcion: "Lista, mapa e indicadores de los reportes de campo; estados, duplicados y descargas.", habilitada: true,
  });
  return e;
}
