import "./areas.css";

// Cabecera de las pantallas de áreas (ventana de entrada, cascarón técnico y «sin módulos»). El área Comercial conserva su cabecera de siempre.
// «Inicio» solo aparece para quien tiene las dos áreas y no está ya en la ventana de entrada.
export function CabeceraApp({ correo, esAdmin, mostrarInicio, enAdministracion, onInicio, onAdmin, onSalir }: {
  correo: string; esAdmin: boolean; mostrarInicio: boolean; enAdministracion: boolean;
  onInicio: () => void; onAdmin: () => void; onSalir: () => void;
}) {
  return (
    <header className="barra barra-areas">
      <div className="barra-marca">
        <span className="brand-mark">◆</span>
        <span>Geoportal Catastral</span>
        <span className="barra-ent">EMDUPAR</span>
      </div>
      {mostrarInicio && (
        <button type="button" className="btn-inicio" onClick={onInicio}>⌂ Inicio</button>
      )}
      <div className="barra-usuario">
        {esAdmin && (
          <button type="button" className="btn-link" onClick={onAdmin}>
            {enAdministracion ? "Volver" : "Administración"}
          </button>
        )}
        <span className="mono barra-correo">{correo.split("@")[0]}</span>
        <button type="button" className="btn-link" onClick={onSalir}>Salir</button>
      </div>
    </header>
  );
}
