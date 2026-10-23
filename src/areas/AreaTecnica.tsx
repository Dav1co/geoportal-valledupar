import "./areas.css";

// Cascarón del área Técnica (fase 1): sin datos, sin formulario y sin llamadas al servidor. Se construye en la fase 3.
// Ocultarlo a los demás es solo experiencia de usuario; los permisos reales los hará cumplir el servidor (fase 2).
export function AreaTecnica() {
  return (
    <div className="areas-cuerpo">
      <div className="areas-tecnica">
        <div className="areas-caja">
          <h1>Área técnica</h1>
          <p>Cascarón de la fase 1: aquí se construirá el registro técnico y la supervisión.</p>
          <p className="areas-sub" style={{ marginBottom: 0 }}>En construcción · visible solo para administradores.</p>
        </div>
      </div>
    </div>
  );
}
