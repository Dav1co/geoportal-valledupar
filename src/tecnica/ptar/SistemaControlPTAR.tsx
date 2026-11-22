import "./tokens_ptar.css";
import "./ptar.css";
import { MapaPTAR } from "./MapaPTAR";

// PTAR-3 (Code C, 21-nov): el «Sistema de Control PTAR», una vista propia como el geovisor de distribución (pedido de David). Es el mapa de la planta a pantalla
// completa: cada elemento clicable con su ficha y, en los puntos de medición, sus parámetros (sonda multiparámetro y Caracterización) con su último valor y estado.
export function SistemaControlPTAR({ onVolver, rotuloVolver = "Volver al inicio" }: { onVolver: () => void; rotuloVolver?: string }) {
  return (
    <div className="ptar-control tec-modo-ptar" data-testid="ptar-control">
      <header className="ptar-control-cab">
        <div>
          <h1>Sistema de Control PTAR</h1>
          <p>PTAR El Salguero · lagunas, colectores, pozos y puntos de medición sobre la foto satelital</p>
        </div>
        <button type="button" className="td-boton-claro" onClick={onVolver}>← {rotuloVolver}</button>
      </header>
      <MapaPTAR instalacion="ptar" completo />
    </div>
  );
}
