// Marca de agua repetida con el correo del usuario. No impide la captura de
// pantalla, pero deja identificada cualquier foto que se reenvíe.
export function Watermark({ email }: { email: string }) {
  const sello = `${email} · ${new Date().toLocaleDateString("es-CO")}`;
  const filas = Array.from({ length: 8 });
  return (
    <div className="watermark" aria-hidden="true">
      {filas.map((_, i) => (
        <div className="watermark-fila" key={i}>
          {Array.from({ length: 6 }).map((__, j) => (
            <span key={j}>{sello}</span>
          ))}
        </div>
      ))}
    </div>
  );
}
