// Límite de la descripción del reporte. UNA sola fuente: el parámetro max_descripcion de la base, que `formulario` entrega en `limites.max_descripcion`.
// El respaldo (1.000, lo que admite la tabla) solo se usa si el servidor aún no lo informa (Edge o base anteriores al Paso C).
export const MAX_DESCRIPCION_RESPALDO = 1000;
export const maxDescripcion = (limites: { max_descripcion?: number } | undefined): number =>
  typeof limites?.max_descripcion === "number" && limites.max_descripcion >= 1 ? Math.floor(limites.max_descripcion) : MAX_DESCRIPCION_RESPALDO;
