import { useCallback, useEffect, useRef, useState } from "react";

// Ubicación del celular con alta precisión. Se muestra la precisión en metros; una precisión mala AVISA pero no impide el envío. Sin ninguna ubicación no hay envío (la base exige coordenada).
// PROPUESTA (parametrizable aquí): por encima de este radio se avisa y se sugiere esperar o salir a cielo abierto.
export const UMBRAL_PRECISION_MALA_M = 30;

export type Fix = { lat: number; lon: number; precision_m: number; tomado: Date };
export type EstadoUbicacion = "buscando" | "ok" | "denegada" | "no_disponible" | "error";

export function useUbicacion(): { estado: EstadoUbicacion; fix: Fix | null; actualizar: () => void; mensaje: string | null } {
  const [estado, setEstado] = useState<EstadoUbicacion>("buscando");
  const [fix, setFix] = useState<Fix | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const reloj = useRef<number | null>(null);

  const detener = () => { if (reloj.current !== null) { navigator.geolocation.clearWatch(reloj.current); reloj.current = null; } };

  const iniciar = useCallback(() => {
    detener();
    if (!("geolocation" in navigator)) {
      setEstado("no_disponible");
      setMensaje("Este navegador no entrega la ubicación.");
      return;
    }
    setEstado("buscando");
    setMensaje(null);
    reloj.current = navigator.geolocation.watchPosition(
      (p) => {
        setFix({ lat: p.coords.latitude, lon: p.coords.longitude, precision_m: p.coords.accuracy, tomado: new Date(p.timestamp) });
        setEstado("ok");
        setMensaje(null);
      },
      (e) => {
        if (e.code === e.PERMISSION_DENIED) {
          setEstado("denegada");
          setMensaje("No se dio permiso para la ubicación. Permítala para este sitio en los ajustes del navegador (en iPhone: Ajustes › Privacidad › Localización › Safari; en Android: candado de la barra de direcciones › Permisos) y pulse «Actualizar ubicación».");
        } else if (e.code === e.POSITION_UNAVAILABLE) {
          setEstado("error");
          setMensaje("No se pudo determinar la ubicación. Salga a cielo abierto y pulse «Actualizar ubicación».");
        } else {
          setEstado("error");
          setMensaje("La ubicación tardó demasiado. Pulse «Actualizar ubicación».");
        }
      },
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 },
    );
  }, []);

  useEffect(() => {
    iniciar();
    return detener;
  }, [iniciar]);

  return { estado, fix, actualizar: iniciar, mensaje };
}
