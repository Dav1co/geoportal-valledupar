// Ícono de cámara de línea para los botones de foto de Técnica (pedido de David, 16-nov: al operario le sirve para ubicarlos).
// SVG en línea, sin emoji: toma el color del texto del botón (currentColor) y mide 18 px; va delante del texto y no se lee en voz alta (el texto ya lo dice).
export function IconoCamara({ tam = 18 }: { tam?: number }) {
  return (
    <svg className="tec-icono-camara" width={tam} height={tam} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"
      aria-hidden="true" focusable="false" data-icono="camara">
      <path d="M4 8h3l1.6-2.4A1 1 0 0 1 9.4 5h5.2a1 1 0 0 1 .8.6L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z" />
      <circle cx="12" cy="13.5" r="3.5" />
    </svg>
  );
}
