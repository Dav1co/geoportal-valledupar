import "./areas.css";

// Pantalla cuando no se pudo cargar el perfil por un fallo pasajero (sin red, sin tiempo, servidor caído). La sesión sigue abierta: se puede reintentar o volver al inicio de sesión.
export function PerfilNoDisponible({ mensaje, onReintentar, onSalir }: { mensaje: string; onReintentar: () => void; onSalir: () => void }) {
  return (
    <div className="areas-pantalla-completa">
      <div className="areas-aviso" role="alert">
        <h1>No se pudo cargar su perfil</h1>
        <p>{mensaje}</p>
        <div className="areas-acciones">
          <button type="button" className="btn-sm" onClick={onReintentar}>Reintentar</button>
          <button type="button" className="btn-link" onClick={onSalir}>Volver al inicio de sesión</button>
        </div>
      </div>
    </div>
  );
}
