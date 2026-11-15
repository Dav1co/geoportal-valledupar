import "./areas.css";
import { tarjetasEntrada, type Area, type AreasDisponibles } from "./areas";
import { MapaComercial, PanelComercial, RedTecnica, PanelTecnico } from "./ilustraciones";

// Ventana de entrada: solo para quien tiene acceso a dos o más áreas (administradores y duales). Se muestra siempre al iniciar sesión y al recargar.
// «Formatos de campo» es una tarjeta aparte solo cuando la persona NO tiene Comercial (con Comercial se llega desde su cabecera: los formatos viven en la Torre A).
export function VentanaEntrada({ areas, onElegir }: { areas: AreasDisponibles; onElegir: (a: Area) => void }) {
  const tarjetas = tarjetasEntrada(areas);
  return (
    <div className="areas-cuerpo">
      <div className="areas-entrada">
        <h1>¿A qué área desea entrar?</h1>
        <p className="areas-sub">Su cuenta tiene acceso a más de un área. Puede volver a esta ventana con el botón «Inicio».</p>
        <div className="areas-tarjetas">
          {tarjetas.includes("comercial") && (
            <button type="button" className="area-tarjeta" onClick={() => onElegir("comercial")}>
              <MapaComercial />
              <span className="area-texto">
                <h2 className="area-titulo"><span>GEOPORTAL</span><strong>COMERCIAL</strong></h2>
                <p>Mapa del geoportal, Explorar, Focalización, Comercial, Rutas y Dashboard comercial{areas.campo ? ", y Formatos de campo" : ""}.</p>
              </span>
              <PanelComercial />
            </button>
          )}
          {tarjetas.includes("tecnica") && (
            <button type="button" className="area-tarjeta area-tarjeta-tecnica" onClick={() => onElegir("tecnica")}>
              <RedTecnica />
              <span className="area-texto">
                <h2 className="area-titulo"><span>GEOPORTAL</span><strong>TÉCNICA</strong></h2>
                <p>Registro y gestión de datos de planta: puntos de muestra, mediciones y supervisión.</p>
                <span className="area-etiqueta">Disponible: formulario Entrada</span>
              </span>
              <PanelTecnico />
            </button>
          )}
          {tarjetas.includes("campo") && (
            <button type="button" className="area-tarjeta area-tarjeta-campo" onClick={() => onElegir("campo")}>
              <span className="area-texto">
                <h2 className="area-titulo"><span>GEOPORTAL</span><strong>FORMATOS DE CAMPO</strong></h2>
                <p>Reportar anomalía: registre en segundos lo que encontró en terreno, con fotos y ubicación.</p>
                <span className="area-etiqueta">Torre A · Disponible: Reportar anomalía</span>
              </span>
            </button>
          )}
          {tarjetas.includes("aseo") && (
            <button type="button" className="area-tarjeta area-tarjeta-campo" onClick={() => onElegir("aseo")}>
              <span className="area-texto">
                <h2 className="area-titulo"><span>GEOPORTAL</span><strong>INTERVENTORÍA DE ASEO</strong></h2>
                <p>Auditoría de la prestación del servicio de aseo: elija la ruta, registre con fotos y obtenga el acta.</p>
                <span className="area-etiqueta">Torre C · Disponible: Barrido</span>
              </span>
            </button>
          )}
        </div>
        <p className="areas-pie">Esta ventana solo aparece para cuentas con acceso a más de un área.</p>
      </div>
    </div>
  );
}
