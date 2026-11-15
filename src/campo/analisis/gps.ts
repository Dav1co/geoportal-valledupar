// Posición del celular para «Análisis de contrato» (distancia al predio y «Contratos cerca de mí»). Se pide UNA vez por gesto o al mostrar el análisis; nunca bloquea la pantalla.
// La posición NO se guarda (ni en localStorage/sessionStorage, ni en la consola): quien la pide la usa y la descarta. Solo «Contratos cerca de mí» la envía al servidor.
export type Posicion = { lat: number; lon: number; precision_m: number };
export type FalloGps = "denegado" | "no_disponible" | "tiempo" | "sin_api";

export const TEXTO_FALLO_GPS: Record<FalloGps, string> = {
  denegado: "No tenemos permiso para usar su ubicación. Para activarlo: en el navegador, toque el candado o el ícono junto a la dirección de la página y permita «Ubicación»; en el teléfono, revise Ajustes → Ubicación (y que el navegador tenga permiso). Luego vuelva a intentarlo.",
  no_disponible: "No se pudo obtener la ubicación. Revise que la ubicación (GPS) del teléfono esté encendida e intente de nuevo.",
  tiempo: "El GPS tardó demasiado en responder. Intente de nuevo, de preferencia a cielo abierto.",
  sin_api: "Este navegador no permite usar la ubicación. Abra el geoportal en Chrome o Safari del teléfono.",
};

export class ErrorGps extends Error {
  tipo: FalloGps;
  constructor(tipo: FalloGps) { super(TEXTO_FALLO_GPS[tipo]); this.name = "ErrorGps"; this.tipo = tipo; }
}

export const TIEMPO_GPS_MS = 15000;

export function pedirPosicion(): Promise<Posicion> {
  return new Promise((resolver, rechazar) => {
    if (typeof navigator === "undefined" || !navigator.geolocation) { rechazar(new ErrorGps("sin_api")); return; }
    navigator.geolocation.getCurrentPosition(
      (p) => resolver({ lat: p.coords.latitude, lon: p.coords.longitude, precision_m: p.coords.accuracy }),
      (e) => rechazar(new ErrorGps(e.code === 1 ? "denegado" : e.code === 3 ? "tiempo" : "no_disponible")),
      { enableHighAccuracy: true, timeout: TIEMPO_GPS_MS, maximumAge: 0 },
    );
  });
}
