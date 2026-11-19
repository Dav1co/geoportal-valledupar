import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { instalarManejadorDeCarga, LimiteDeErrores } from "./lib/recarga";
import "./styles/app.css";
import "./areas/areas.css";

// Ningún error deja la pantalla en blanco: un módulo que no carga tras una publicación recarga la página una vez; cualquier otro muestra el aviso con su botón.
instalarManejadorDeCarga();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <LimiteDeErrores>
      <App />
    </LimiteDeErrores>
  </StrictMode>,
);
