// Entradas del área «Formatos de campo» (Torre A). Cada pantalla es UNA entrada de esta lista; agregar una nueva pantalla = agregar una entrada aquí y un caso en AreaCampo.
// Lógica pura (sin React): se prueba sola en scripts/prueba_integracion.mjs.

export type EntradaId = "reporte_general" | "formatos" | "acta" | "acta_supervision";

export type EntradaCampo = {
  id: EntradaId;
  titulo: string;
  descripcion: string;
  /** ¿Se puede abrir ya? Una entrada pendiente se dibuja como «Próximamente» y no hace nada. */
  habilitada: boolean;
  /** MARCADOR: la pantalla de esta entrada aún no existe (hoy solo el tablero del supervisor de actas). Se quita cuando se construya. */
  pendiente?: boolean;
};

export type CondicionesEntradas = {
  /** El servidor dice que la persona puede reportar (def.puede.reportar). */
  puedeReportar: boolean;
  /** Hay al menos un formato del Paso D activo en el catálogo. */
  hayFormatos: boolean;
  /** Permiso `ver_acta` (clave `acta` del perfil): puede capturar actas. Lo decide el servidor; el supervisor de actas también lo tiene. */
  puedeActa: boolean;
  /** Permiso de campo (reportar o supervisar). Por omisión verdadero (como antes). Quien solo tiene acta NO ve «Reporte general» ni «Formatos de actividad». */
  puedeCampo?: boolean;
  /** Permiso `ver_dashboard_acta` (supervisor de actas): reconocido, pero su pantalla aún no existe (marcador). */
  puedeSupervisarActas?: boolean;
};

/** Entradas visibles, en orden. «Reporte general» siempre; «Formatos de actividad» solo si hay formatos activos; «Acta de inspección» SOLO con el permiso de acta. */
export function entradasDeCampo(c: CondicionesEntradas): EntradaCampo[] {
  const e: EntradaCampo[] = [];
  const campo = c.puedeCampo !== false;
  if (campo) e.push({
    id: "reporte_general", titulo: "Reporte general",
    descripcion: "Registre en segundos lo que encontró: tipo, fotos, ubicación y contrato.", habilitada: c.puedeReportar,
  });
  if (campo && c.hayFormatos) e.push({
    id: "formatos", titulo: "Formatos de actividad",
    descripcion: "Suspensión, corte, instalaciones y otras actividades, con sus campos, fotos y resultado.", habilitada: c.puedeReportar,
  });
  if (c.puedeActa) e.push({
    id: "acta", titulo: "Acta de inspección",
    descripcion: "Registro digital que acompaña al acta física firmada.", habilitada: true,
  });
  if (c.puedeSupervisarActas) e.push({
    id: "acta_supervision", titulo: "Supervisión de actas",
    descripcion: "Revisión, estados y corrección de las actas registradas.", habilitada: false, pendiente: true,
  });
  return e;
}
