import type { EntradaId } from "./entradas";

// Un ícono propio por entrada de Formatos de campo (25-nov, David: antes se repetía la «R» de la inicial del título). Trazos simples de 24×24, `currentColor`, decorativos (aria-hidden).
// Cada actividad nueva suma el suyo aquí.
const TRAZOS: Record<EntradaId, string> = {
  reporte_general: "M12 3 2.5 20h19L12 3Zm0 6v5m0 3v.01",                                          // triángulo de alerta
  formatos: "M7 3h8l4 4v14H7V3Zm8 0v4h4M10 12h6m-6 4h6",                                          // hoja con líneas
  acta: "M6 3h12v18l-3-2-3 2-3-2-3 2V3Zm3 5h6m-6 4h6",                                            // recibo (posible pérdida)
  analisis_contrato: "M10.5 18a7.5 7.5 0 1 1 0-15 7.5 7.5 0 0 1 0 15Zm5.5-2 5 5",                  // lupa
  activo_campo: "M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11Zm0-8.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z",   // pin
  reparto: "M3 7h11v9H3V7Zm11 3h4l3 3v3h-7v-6ZM7 19.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm10 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z",   // camión
  acta_supervision: "M9 3h6a1 1 0 0 1 1 1v1H8V4a1 1 0 0 1 1-1ZM6 5h12v16H6V5Zm3 7 2 2 4-4",             // portapapeles con visto
  revision: "M4 20V10m6 10V4m6 16v-7m4 7H2",                                                       // barras
  reparto_supervision: "M12 21s-6-5.5-6-10.5a6 6 0 0 1 12 0C18 15.5 12 21 12 21Zm-2.5-10.5 2 2 3-3.5",  // pin con visto
};

export function IconoEntrada({ id }: { id: EntradaId }) {
  return (
    <svg className="com-tarjeta-svg" viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" data-icono={id}>
      <path d={TRAZOS[id]} />
    </svg>
  );
}
export const ICONOS_ENTRADA = Object.keys(TRAZOS) as EntradaId[];
