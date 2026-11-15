import { useEffect, useMemo, useRef, useState } from "react";
import { TEXTO_FALLO_GPS, TIEMPO_GPS_MS } from "./gps";
import {
  anunciarAhora, avisoPrecision, bandaCercania, distanciaTexto, giroFlecha, pasoVibracion, precisionInsuficiente, predioMasCercano, rumboDeOrientacion, rumboGrados,
  TEXTO_BANDA, textoRumbo, urlGoogleMapsAPie, type Banda,
} from "./logica";
import type { Predio } from "./tipos";

// «Buscar el predio» (addendum §4, al estilo AirTag): pantalla completa que guía hasta el predio con una flecha, la distancia en vivo y un color por cercanía.
// TODO ocurre en el celular: la posición (watchPosition) y la brújula (DeviceOrientationEvent) viven solo en memoria mientras la pantalla está abierta; nada se envía ni se guarda.
// Al cerrar (o desmontar) se apagan el GPS (clearWatch) y la brújula (removeEventListener).

export type PermisoBrujula = "concedido" | "denegado" | "no_aplica";
type ConPermiso = { requestPermission?: () => Promise<string> };

/** Debe llamarse DENTRO del toque en «Buscar»: en iPhone, requestPermission solo funciona tras un gesto del usuario. En Android y escritorio no hay que pedir nada. */
export function pedirPermisoBrujula(): Promise<PermisoBrujula> {
  const D = (typeof window !== "undefined" ? (window as unknown as { DeviceOrientationEvent?: ConPermiso }).DeviceOrientationEvent : undefined);
  if (!D || typeof D.requestPermission !== "function") return Promise.resolve("no_aplica");
  try { return D.requestPermission().then((r) => (r === "granted" ? "concedido" : "denegado"), () => "denegado"); } catch { return Promise.resolve("denegado"); }
}

type Fix = { lat: number; lon: number; precision: number };
const EVENTOS = ["deviceorientationabsolute", "deviceorientation"] as const;

export function BuscarPredio({ predios, permiso, onCerrar }: { predios: Predio[]; permiso: Promise<PermisoBrujula>; onCerrar: () => void }) {
  const [fix, setFix] = useState<Fix | null>(null);
  const [errorGps, setErrorGps] = useState<string | null>(null);
  const [rumboCel, setRumboCel] = useState<number | null>(null);
  const [brujulaNegada, setBrujulaNegada] = useState(false);
  const [anuncio, setAnuncio] = useState("");
  const armada = useRef(true);
  const ultimoAnuncio = useRef(0);
  const bandaPrevia = useRef<Banda | null>(null);
  const cerrar = useRef<HTMLButtonElement>(null);

  // GPS en vivo
  useEffect(() => {
    if (typeof navigator === "undefined" || !navigator.geolocation) { setErrorGps(TEXTO_FALLO_GPS.sin_api); return; }
    const id = navigator.geolocation.watchPosition(
      (p) => { setErrorGps(null); setFix({ lat: p.coords.latitude, lon: p.coords.longitude, precision: p.coords.accuracy }); },
      (e) => setErrorGps(TEXTO_FALLO_GPS[e.code === 1 ? "denegado" : e.code === 3 ? "tiempo" : "no_disponible"]),
      { enableHighAccuracy: true, timeout: TIEMPO_GPS_MS, maximumAge: 0 },
    );
    return () => navigator.geolocation.clearWatch(id);
  }, []);

  // Brújula (se agrega solo si el permiso no se negó; se quita siempre al salir)
  useEffect(() => {
    let vivo = true;
    const alGirar = (e: Event) => { const r = rumboDeOrientacion(e as unknown as { webkitCompassHeading?: number; alpha?: number | null; absolute?: boolean }); if (r !== null) setRumboCel(r); };
    permiso.then((p) => {
      if (!vivo) return;
      if (p === "denegado") { setBrujulaNegada(true); return; }
      EVENTOS.forEach((t) => window.addEventListener(t, alGirar));
    });
    return () => { vivo = false; EVENTOS.forEach((t) => window.removeEventListener(t, alGirar)); };
  }, [permiso]);

  useEffect(() => {
    cerrar.current?.focus();
    const tecla = (e: KeyboardEvent) => { if (e.key === "Escape") onCerrar(); };
    window.addEventListener("keydown", tecla);
    return () => window.removeEventListener("keydown", tecla);
  }, [onCerrar]);

  const objetivo = useMemo(() => (fix ? predioMasCercano(fix, predios) : null), [fix, predios]);
  const primero = predios.find((p) => p.lat !== null && p.lon !== null) ?? null;
  const destino = objetivo?.predio ?? primero;
  const d = objetivo?.distancia_m ?? null;
  const rumbo = fix && objetivo ? rumboGrados(fix, { lat: objetivo.predio.lat as number, lon: objetivo.predio.lon as number }) : null;
  const sinBrujula = brujulaNegada || rumboCel === null;
  const giro = rumbo === null ? null : giroFlecha(rumbo, sinBrujula ? null : rumboCel);
  const banda: Banda | null = d === null ? null : bandaCercania(d);

  // Vibración al llegar (con histéresis) y anuncio para lectores de pantalla
  useEffect(() => {
    if (d === null || banda === null) return;
    const paso = pasoVibracion(armada.current, d);
    armada.current = paso.armada;
    if (paso.vibrar && typeof navigator !== "undefined" && typeof navigator.vibrate === "function") navigator.vibrate([200, 100, 200]);
    const cambio = bandaPrevia.current !== banda;
    bandaPrevia.current = banda;
    const ahora = Date.now();
    if (anunciarAhora(ultimoAnuncio.current, ahora, cambio)) {
      ultimoAnuncio.current = ahora;
      setAnuncio(`${distanciaTexto(d)}. ${TEXTO_BANDA[banda]}.${rumbo !== null ? ` Predio ${textoRumbo(rumbo)}.` : ""}`);
    }
  }, [d, banda, rumbo]);

  return (
    <div className={`ac-bp ac-bp-${banda ?? "espera"}`} role="dialog" aria-modal="true" aria-labelledby="ac-bp-titulo" data-testid="buscar-predio" data-banda={banda ?? ""}>
      <div className="ac-bp-cab">
        <h2 id="ac-bp-titulo">Buscar el predio</h2>
        <button ref={cerrar} type="button" className="tec-boton-sec tec-boton-corto" onClick={onCerrar}>Cerrar</button>
      </div>
      {destino?.direccion ? <p className="ac-bp-dir">{[destino.direccion, destino.barrio].filter(Boolean).join(" · ")}</p> : null}
      {errorGps ? <p className="ac-gps-ayuda" data-testid="gps-ayuda">{errorGps}</p> : null}
      {!fix && !errorGps ? <p className="ac-bp-espera" role="status">Obteniendo su ubicación…</p> : null}
      {fix && d !== null && giro !== null && rumbo !== null ? (
        <>
          <div className="ac-bp-brujula">
            <svg viewBox="0 0 200 200" className="ac-bp-svg" aria-hidden="true">
              <circle cx="100" cy="100" r="92" className="ac-bp-aro" />
              {sinBrujula ? <text x="100" y="24" textAnchor="middle" className="ac-bp-n" data-testid="marca-norte">N</text> : null}
              <g transform={`rotate(${giro.toFixed(1)} 100 100)`} data-testid="flecha" data-giro={giro.toFixed(2)}>
                <path d="M100 26 L142 120 L100 100 L58 120 Z" className="ac-bp-flecha" />
              </g>
            </svg>
          </div>
          <p className="ac-bp-dist" data-testid="bp-distancia">{distanciaTexto(d)}</p>
          <p className="ac-bp-banda" data-testid="bp-banda">{TEXTO_BANDA[banda as Banda]}</p>
          <p className="ac-bp-precision">Precisión ± {Math.round(fix.precision).toLocaleString("es-CO")} m</p>
          {precisionInsuficiente(d, fix.precision) ? <p className="ac-nota" role="note" data-testid="bp-senal">La señal no alcanza para afinar; busque la dirección</p>
            : avisoPrecision(fix.precision) ? <p className="ac-nota" role="note">{avisoPrecision(fix.precision)}</p> : null}
          {sinBrujula ? (
            <p className="ac-bp-sinbrujula" data-testid="sin-brujula">
              <span className="ac-tag-censo">sin brújula</span> La flecha apunta respecto al norte: gire el celular hasta que la «N» quede arriba. El predio está {textoRumbo(rumbo)}.
            </p>
          ) : null}
        </>
      ) : null}
      {destino ? (
        <a className="tec-boton-sec ac-bp-gmaps" href={urlGoogleMapsAPie(destino.lat as number, destino.lon as number)} target="_blank" rel="noopener noreferrer">Abrir en Google Maps</a>
      ) : null}
      <p className="ac-oculto" aria-live="polite" data-testid="bp-anuncio">{anuncio}</p>
    </div>
  );
}
