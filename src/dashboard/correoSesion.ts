// Correo de la sesión para el Dashboard: lo entrega Dashboard (que lo recibe de App.tsx) y lo leen las secciones que pasan a pantalla completa para llevar su propia
// marca de agua. Con un contexto no hace falta pasar el correo por las pantallas (Perdidas.tsx y las que usan graficas.tsx no cambian). Cadena vacía = sin correo.
import { createContext } from "react";

export const CorreoSesion = createContext<string>("");
