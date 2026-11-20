import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { FotoRemision } from "./FotoRemision";

// Página aparte del geoportal (remision.html) que abre el enlace «Ver foto» de los reportes del Dashboard PTAP (Entrada de químicos). Va aparte para no
// cargar la app entera y no tocar su navegación: usa la sesión que ya está iniciada en este navegador.
createRoot(document.getElementById("root")!).render(<StrictMode><FotoRemision /></StrictMode>);
