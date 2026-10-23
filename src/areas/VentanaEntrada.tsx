import "./areas.css";
import type { Area } from "./areas";
import { MapaComercial, PanelComercial, RedTecnica, PanelTecnico } from "./ilustraciones";

// Ventana de entrada: solo para quien tiene acceso a las dos áreas (administradores y duales). Se muestra siempre al iniciar sesión y al recargar.
export function VentanaEntrada({ onElegir }: { onElegir: (a: Area) => void }) {
  return (
    <div className="areas-cuerpo">
      <div className="areas-entrada">
        <h1>¿A qué área desea entrar?</h1>
        <p className="areas-sub">Su cuenta tiene acceso a las dos áreas. Puede volver a esta ventana con el botón «Inicio».</p>
        <div className="areas-tarjetas">
          <button type="button" className="area-tarjeta" onClick={() => onElegir("comercial")}>
            <MapaComercial />
            <span className="area-texto">
              <h2 className="area-titulo"><span>GEOPORTAL</span><strong>COMERCIAL</strong></h2>
              <p>Mapa del geoportal, Explorar, Focalización, Comercial, Rutas y Dashboard comercial.</p>
            </span>
            <PanelComercial />
          </button>
          <button type="button" className="area-tarjeta area-tarjeta-tecnica" onClick={() => onElegir("tecnica")}>
            <RedTecnica />
            <span className="area-texto">
              <h2 className="area-titulo"><span>GEOPORTAL</span><strong>TÉCNICA</strong></h2>
              <p>Registro y gestión de datos de planta: puntos de muestra, mediciones y supervisión.</p>
              <span className="area-etiqueta">En construcción · visible solo para administradores</span>
            </span>
            <PanelTecnico />
          </button>
        </div>
        <p className="areas-pie">Esta ventana solo aparece para cuentas con acceso a ambas áreas.</p>
      </div>
    </div>
  );
}
