// Botón «← Volver» ÚNICO de Formatos de campo (25-nov, David): mismo texto y mismo sitio en todas las pantallas (el extremo de la barra del encabezado, antes del título).
// Uso: <BotonVolver onClick={volver} />. Variantes: «claro» sobre la barra oscura de Supervisión y Actas (`rv-boton-claro`); «normal» (por omisión) dentro de la barra `campo-cab`
// (`tec-boton-sec`, que Comercial pinta de blanco sobre el color del módulo). Si una pantalla necesita decir a dónde vuelve, se lo dice con `aria-label` (nunca cambia el texto visible).
export const TEXTO_VOLVER = "← Volver";

export function BotonVolver({ onClick, variante = "normal", deshabilitado = false, descripcion }: {
  onClick: () => void; variante?: "normal" | "claro"; deshabilitado?: boolean; descripcion?: string;
}) {
  return (
    <button type="button" className={variante === "claro" ? "rv-boton-claro" : "tec-boton-sec"} onClick={onClick} disabled={deshabilitado} aria-label={descripcion ? `Volver: ${descripcion}` : undefined} data-volver="">
      {TEXTO_VOLVER}
    </button>
  );
}
