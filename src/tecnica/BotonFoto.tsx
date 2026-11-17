import { useId } from "react";
import { IconoCamara } from "./IconoCamara";

// Botón de foto de Técnica para donde NO hay cámara de campo (hoy, la remisión de químicos). Es un campo de archivo SIN «capture» (como el 7c-bis): el celular
// ofrece cámara, galería y archivos; en el PC, elegir un archivo. Solo imágenes. El daño y la intervención siguen con la cámara de campo (CamaraActa, con su sello
// de hora y GPS; David, 16-nov) y solo llevan el ícono.
// Delante del texto va el ícono de cámara de línea (IconoCamara), del color del texto del botón. Las pantallas de Comercial no lo usan.
export function BotonFoto({ texto, onArchivo, disabled, className = "tec-boton-sec", etiquetadoPor, id: idFijo }: {
  texto: string; onArchivo: (archivo: File) => void; disabled?: boolean; className?: string; etiquetadoPor?: string; id?: string;
}) {
  const idAuto = useId(); const id = idFijo ?? idAuto;
  return (
    <label className={`${className} tec-boton-foto${disabled ? " tec-boton-foto-off" : ""}`} htmlFor={id} aria-disabled={disabled || undefined} data-boton-foto="">
      <IconoCamara />{texto}
      <input id={id} type="file" accept="image/*" disabled={disabled} aria-labelledby={etiquetadoPor}
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) onArchivo(f); }} />
    </label>
  );
}
