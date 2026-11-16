import { useEffect, useMemo, useState } from "react";
import "./muestreo.css";
import { apiTec, ErrorTec, puntosDelMapa, type ProponerResp, type PuntoMapa, type PuntosMapaResp } from "./apiTecnica";
import { avisoDeError } from "./FormularioCaptura";
import { useUbicacion } from "../campo/ubicacion";
import { distanciaM, LeyendaPuntos, MiniMapaPuntos } from "./MiniMapaPuntos";
import type { Opcion } from "./lugares";

// Minimapa de Muestreo (Corte 5b), sincronizado con la lista de puntos de la tarjeta: tocar un punto lo elige en la lista, y elegirlo en la lista lo resalta.
// · Solo dibuja los puntos de la tarjeta (la lista la manda el servidor). Los que no tienen ubicación se eligen en la lista.
// · No pide el GPS al abrir (en Muestreo se registran resultados del laboratorio de días atrás, desde la oficina). «Ver dónde estoy» lo pide cuando la persona quiere,
//   y propone el punto más cercano sin cambiar lo elegido.
// · «Guardar la ubicación de este punto» (GPS del operador, §4 de los hallazgos): para un punto con la ubicación aproximada o sin ubicación. Queda en revisión del supervisor.
// · Si el servidor todavía no tiene la ruta (Edge sin desplegar), el mapa no aparece y la lista sigue igual que antes.

const CERCA_M = 300;          // «el punto más cercano» solo se propone si está a menos de esto
const textoExactitud = (p: PuntoMapa | undefined, sinUbic: boolean) =>
  sinUbic ? "Este punto todavía no tiene ubicación en el mapa." : !p ? "" : p.exactitud === "verificada" ? (p.fuente === "gps_operador" ? "Ubicación verificada (GPS del operador, aprobada por el supervisor)." : "Ubicación verificada.")
    : "Ubicación aproximada: es el centro del barrio, no el punto exacto de la toma.";

export function MapaMuestreo({ opciones, lugar, onElegir, bloqueado }: { opciones: Opcion[]; lugar: string; onElegir: (codigo: string) => void; bloqueado: boolean }) {
  const [datos, setDatos] = useState<PuntosMapaResp | null>(null);
  const [falla, setFalla] = useState<"no_aplicado" | "error" | null>(null);
  const [intento, setIntento] = useState(0);
  const [visible, setVisible] = useState(true);
  const [buscandoYo, setBuscandoYo] = useState(false);
  const [yo, setYo] = useState<{ lat: number; lon: number; precision_m: number } | null>(null);
  const [avisoYo, setAvisoYo] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);       // panel «Guardar la ubicación de este punto» abierto

  useEffect(() => {
    let vivo = true; setFalla(null);
    apiTec.puntosMapa().then((r) => { if (vivo) setDatos(r); }).catch((e) => { if (vivo) setFalla(e instanceof ErrorTec && e.tipo === "no_aplicado" ? "no_aplicado" : "error"); });
    return () => { vivo = false; };
  }, [intento]);

  const codigos = useMemo(() => new Set(opciones.map((o) => o.codigo)), [opciones]);
  const puntos = useMemo(() => (datos ? puntosDelMapa(datos).filter((p) => codigos.has(p.codigo)) : []), [datos, codigos]);
  const sinUbicacion = useMemo(() => opciones.filter((o) => !puntos.some((p) => p.codigo === o.codigo)), [opciones, puntos]);
  const elegido = puntos.find((p) => p.codigo === lugar);
  const enRevisionSinUbic = datos?.sin_ubicacion.find((x) => x.codigo === lugar)?.en_revision ?? false;
  const cercano = useMemo(() => {
    if (!yo || !puntos.length) return null;
    const c = puntos.map((p) => ({ p, d: distanciaM(yo, p) })).reduce((a, b) => (b.d < a.d ? b : a));
    return c.d <= CERCA_M ? c : null;
  }, [yo, puntos]);

  if (falla === "no_aplicado") return null;          // servidor sin la ruta: la lista sigue como antes
  if (falla) return <p className="tec-ayuda" role="status">No se pudo cargar el mapa de los puntos. Elija el punto en la lista. <button type="button" className="mue-enlace" onClick={() => setIntento((x) => x + 1)}>Reintentar</button></p>;
  if (!datos) return <p className="tec-ayuda" role="status">Cargando el mapa de los puntos…</p>;

  function verDondeEstoy() {
    if (!("geolocation" in navigator)) { setAvisoYo("Este navegador no entrega la ubicación."); return; }
    setBuscandoYo(true); setAvisoYo(null);
    navigator.geolocation.getCurrentPosition(
      (p) => { setBuscandoYo(false); setYo({ lat: p.coords.latitude, lon: p.coords.longitude, precision_m: p.coords.accuracy }); },
      (e) => { setBuscandoYo(false); setAvisoYo(e.code === e.PERMISSION_DENIED ? "No se dio permiso para la ubicación. Permítala para este sitio en los ajustes del navegador." : "No se pudo determinar la ubicación. Intente de nuevo a cielo abierto."); },
      { enableHighAccuracy: true, maximumAge: 10000, timeout: 20000 });
  }

  const puedeGuardar = lugar !== "" && (elegido ? elegido.exactitud !== "verificada" && !elegido.en_revision : !enRevisionSinUbic && sinUbicacion.some((o) => o.codigo === lugar));
  const enRevision = elegido?.en_revision || enRevisionSinUbic;

  return (
    <div className="mue" data-testid="mapa-muestreo">
      <div className="mue-cab">
        <button type="button" className="tec-boton-sec mue-boton" aria-expanded={visible} onClick={() => setVisible((v) => !v)}>{visible ? "Ocultar el mapa" : "Ver los puntos en el mapa"}</button>
        {visible ? <button type="button" className="tec-boton-sec mue-boton" onClick={verDondeEstoy} disabled={buscandoYo} aria-busy={buscandoYo}>{buscandoYo ? "Buscando…" : "Ver dónde estoy"}</button> : null}
      </div>
      {visible ? (
        <>
          <MiniMapaPuntos puntos={puntos} elegido={lugar} yo={yo} onElegir={(c) => { if (!bloqueado) onElegir(c); }} />
          <LeyendaPuntos />
          {sinUbicacion.length ? <p className="tec-ayuda" data-testid="sin-ubicacion">{sinUbicacion.length === 1 ? "1 punto no tiene ubicación en el mapa" : `${sinUbicacion.length} puntos no tienen ubicación en el mapa`}: elíjalo{sinUbicacion.length === 1 ? "" : "s"} en la lista.</p> : null}
        </>
      ) : null}
      {avisoYo ? <p className="tec-error-caja" role="alert">{avisoYo}</p> : null}
      {yo && visible ? (
        cercano ? (
          <div className="mue-cercano" role="status" data-testid="cercano">
            <span>El punto más cercano es <strong>{cercano.p.nombre}</strong>, a {Math.round(cercano.d)} m{cercano.p.exactitud === "aproximada" ? " (de su ubicación aproximada)" : ""}.</span>
            {cercano.p.codigo !== lugar ? <button type="button" className="tec-boton-sec mue-boton" disabled={bloqueado} onClick={() => onElegir(cercano.p.codigo)}>Elegir este punto</button> : null}
          </div>
        ) : <p className="tec-ayuda" role="status">No hay ningún punto de muestreo a menos de {CERCA_M} m de usted. Elíjalo en la lista o en el mapa.</p>
      ) : null}
      {lugar !== "" ? (
        <div className="mue-estado" data-testid="estado-ubicacion">
          <span>{enRevision ? (elegido?.propuesta_mia ? "Usted ya envió la ubicación de este punto: está en revisión del supervisor." : "La ubicación de este punto está en revisión del supervisor.") : textoExactitud(elegido, !elegido)}</span>
          {puedeGuardar && !guardando ? <button type="button" className="tec-boton-sec mue-boton" disabled={bloqueado} onClick={() => setGuardando(true)}>Guardar la ubicación de este punto</button> : null}
        </div>
      ) : null}
      {guardando && lugar !== "" ? (
        <GuardarUbicacion codigo={lugar} nombre={opciones.find((o) => o.codigo === lugar)?.nombre ?? lugar} vigente={elegido ?? null} precisionMax={datos.precision_max_m}
          onCerrar={() => setGuardando(false)} onGuardada={() => setIntento((x) => x + 1)} />
      ) : null}
    </div>
  );
}

/** Panel «Guardar la ubicación de este punto»: el GPS del celular, con su precisión en vivo; se guarda solo con la precisión exigida. Queda en revisión del supervisor. */
function GuardarUbicacion({ codigo, nombre, vigente, precisionMax, onCerrar, onGuardada }: {
  codigo: string; nombre: string; vigente: PuntoMapa | null; precisionMax: number; onCerrar: () => void; onGuardada: () => void;
}) {
  const ubic = useUbicacion();
  const [fase, setFase] = useState<"midiendo" | "confirmando" | "enviando" | "hecho">("midiendo");
  const [tomada, setTomada] = useState<{ lat: number; lon: number; precision_m: number } | null>(null);
  const [error, setError] = useState<{ texto: string; detalle?: string } | null>(null);
  const [resp, setResp] = useState<ProponerResp | null>(null);
  const fix = ubic.fix;
  const precisa = !!fix && fix.precision_m <= precisionMax;
  const dist = tomada && vigente ? Math.round(distanciaM(tomada, vigente)) : null;

  async function enviar() {
    if (!tomada || fase === "enviando") return;
    setFase("enviando"); setError(null);
    try {
      const r = await apiTec.proponerUbicacion(codigo, tomada.lat, tomada.lon, tomada.precision_m);
      setResp(r); setFase("hecho"); onGuardada();
    } catch (e) { setError(avisoDeError(e)); setFase("confirmando"); }
  }

  return (
    <section className="mue-guardar" aria-labelledby="mue-guardar-tit" data-testid="guardar-ubicacion">
      <h3 id="mue-guardar-tit">Guardar la ubicación de {nombre}</h3>
      {fase === "hecho" && resp ? (
        <div className="tec-aviso tec-aviso-ok" role="status">
          <strong>{resp.duplicado ? "Ya había enviado la ubicación de este punto." : "Ubicación enviada."}</strong>
          <div>El supervisor la revisa en el Dashboard PTAP. Mientras tanto, el punto sigue con su ubicación de antes.</div>
          <button type="button" className="tec-boton-sec mue-boton" onClick={onCerrar}>Cerrar</button>
        </div>
      ) : fase === "confirmando" || fase === "enviando" ? (
        <>
          <p className="tec-sub" data-testid="confirma-ubicacion">Va a enviar la ubicación del GPS (precisión {Math.round(tomada!.precision_m)} m){dist !== null ? `, a ${dist} m de la ubicación ${vigente?.exactitud === "aproximada" ? "aproximada" : "actual"}` : ""}. No cambia nada hasta que el supervisor la apruebe.</p>
          {error ? <div className="tec-aviso tec-aviso-error" role="alert"><strong>{error.texto}</strong>{error.detalle ? <div>{error.detalle}</div> : null}</div> : null}
          <div className="tec-acciones">
            <button type="button" className="tec-boton" onClick={() => void enviar()} disabled={fase === "enviando"} aria-busy={fase === "enviando"}>{fase === "enviando" ? "Enviando…" : "Confirmar y enviar"}</button>
            <button type="button" className="tec-boton-sec" onClick={() => { setFase("midiendo"); setError(null); }} disabled={fase === "enviando"}>Volver a medir</button>
          </div>
        </>
      ) : (
        <>
          <p className="tec-sub">Párese junto a la llave o el grifo donde toma la muestra y espere a que la precisión baje a {precisionMax} m o menos.</p>
          <p className="mue-precision" role="status" data-testid="precision-gps">
            {ubic.estado === "buscando" && !fix ? "Buscando el GPS…" : fix ? <>Precisión del GPS: <strong className={precisa ? "mue-ok" : "mue-mal"}>{Math.round(fix.precision_m)} m</strong>{precisa ? " (suficiente)" : ` (se necesita ${precisionMax} m o menos)`}</> : null}
          </p>
          {ubic.mensaje ? <p className="tec-error-caja" role="alert">{ubic.mensaje} <button type="button" className="mue-enlace" onClick={ubic.actualizar}>Actualizar ubicación</button></p> : null}
          <div className="tec-acciones">
            <button type="button" className="tec-boton" disabled={!precisa} onClick={() => { if (fix) { setTomada({ lat: fix.lat, lon: fix.lon, precision_m: fix.precision_m }); setFase("confirmando"); } }}>Guardar esta ubicación</button>
            <button type="button" className="btn-cancelar" onClick={onCerrar}>Cancelar</button>
          </div>
        </>
      )}
    </section>
  );
}
