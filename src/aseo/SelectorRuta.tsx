import { Suspense, useEffect, useMemo, useState, type ReactNode } from "react";
import { lazyConRecarga } from "../lib/recarga";
import { apiAseo, avisoDeError, ErrorAseo } from "./apiAseo";
import { buscarRutas, ordenarPorProgramacion, programacion, textoDistancia } from "./logica";
import type { Cercana, GeoFeature, RutaPlan } from "./tipos";
import { useUbicacion } from "../campo/ubicacion";

const MapaRutas = lazyConRecarga(() => import("./MapaRutas"));

// Elegir la ruta: dos caminos, los dos hacia la misma lista. 1) BÚSQUEDA (principal): código, barrio o calle, desde 5 caracteres, sobre el plan que ya está en el celular (sin una consulta por tecla).
// 2) UBICACIÓN: mapa centrado en el auditor con la capa de rutas; se toca la ruta (si pasan varias por ese punto, se ofrece la lista). Una ruta sin trazado se encuentra solo por búsqueda y se puede auditar igual.

type Tarjeta = (r: RutaPlan, extra?: string) => ReactNode;

export function SelectorRuta({ actividad, modalidad, rutas, ahora, minCaracteres, zoomInicial, onElegir }: {
  actividad: string; modalidad: string; rutas: RutaPlan[]; ahora: string; minCaracteres: number; zoomInicial: number; onElegir: (r: RutaPlan) => void;
}) {
  const [q, setQ] = useState("");
  const [verMapa, setVerMapa] = useState(false);
  const encontradas = useMemo(() => ordenarPorProgramacion(buscarRutas(rutas, q, minCaracteres), ahora).slice(0, 40), [rutas, q, minCaracteres, ahora]);
  const hoy = useMemo(() => ordenarPorProgramacion(rutas, ahora).filter((r) => { const p = programacion(r, ahora); return p.programada_hoy && p.en_franja; }).slice(0, 8), [rutas, ahora]);

  const tarjeta: Tarjeta = (r, extra) => {
    const p = programacion(r, ahora);
    return (
      <li key={r.id}>
        <button type="button" className="aseo-ruta" onClick={() => onElegir(r)}>
          <span className="aseo-ruta-cab"><strong className="mono">{r.codigo}</strong><span>{r.servicio.nombre}</span>{extra ? <em>{extra}</em> : null}</span>
          <span className="aseo-ruta-sec">{r.sectores ?? "Sin sectores"}</span>
          <span className="aseo-ruta-pie">
            {[r.turno_nombre, r.hora_inicio && r.hora_fin ? `${r.hora_inicio} a ${r.hora_fin}` : null, r.frecuencia_nombre].filter(Boolean).join(" · ")}
            {p.programada_hoy && p.en_franja ? <b className="aseo-marca aseo-marca-ok">Programada ahora</b> : p.programada_hoy ? <b className="aseo-marca">Hoy, otra hora</b> : <b className="aseo-marca aseo-marca-no">No es su día</b>}
            {!r.geometria ? <b className="aseo-marca aseo-marca-no">Sin trazado</b> : null}
          </span>
        </button>
      </li>
    );
  };
  const corto = q.trim().length < minCaracteres;

  return (
    <div className="aseo-selector">
      <label className="campo-etiqueta" htmlFor="aseo-q">Buscar ruta <small>(código, barrio o calle; desde {minCaracteres} caracteres)</small></label>
      <input id="aseo-q" className="aseo-entrada" type="search" inputMode="search" autoComplete="off" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Ej.: Loperena, K12 o 20100112" />
      {q.trim().length > 0 && corto ? <p className="campo-sub">Escriba al menos {minCaracteres} caracteres para buscar.</p> : null}
      {!corto ? (encontradas.length === 0 ? <p className="campo-sub">Ninguna ruta coincide. Pruebe con otra palabra o con el mapa.</p> : <ul className="aseo-lista" aria-label="Resultados">{encontradas.map((r) => tarjeta(r))}</ul>) : null}
      {corto ? (
        <>
          <button type="button" className="tec-boton-sec aseo-ancho" aria-expanded={verMapa} onClick={() => setVerMapa((v) => !v)}>{verMapa ? "Ocultar el mapa" : "Elegir en el mapa, cerca de mi ubicación"}</button>
          {verMapa ? <PanelMapa actividad={actividad} modalidad={modalidad} rutas={rutas} zoomInicial={zoomInicial} tarjeta={tarjeta} />
            : hoy.length > 0 ? (<><p className="campo-etiqueta">Programadas ahora</p><ul className="aseo-lista">{hoy.map((r) => tarjeta(r))}</ul></>) : null}
        </>
      ) : null}
    </div>
  );
}

/** El mapa, la ubicación y las rutas cercanas SOLO existen mientras el mapa está abierto: la ubicación del GPS no se pide (ni gasta batería) si la persona busca por texto. */
function PanelMapa({ actividad, modalidad, rutas, zoomInicial, tarjeta }: { actividad: string; modalidad: string; rutas: RutaPlan[]; zoomInicial: number; tarjeta: Tarjeta }) {
  const [features, setFeatures] = useState<GeoFeature[] | null>(null);
  const [errorMapa, setErrorMapa] = useState<string | null>(null);
  const [toque, setToque] = useState<number[] | null>(null);
  const [cercanas, setCercanas] = useState<Cercana[]>([]);
  const ubic = useUbicacion();
  const porId = useMemo(() => new Map(rutas.map((r) => [r.id, r])), [rutas]);
  const fix = ubic.fix; const clave = fix ? `${fix.lat.toFixed(3)},${fix.lon.toFixed(3)}` : "";

  useEffect(() => {
    let vivo = true;
    apiAseo.mapa(actividad, modalidad).then((r) => { if (vivo) setFeatures(r.features ?? []); }).catch((e) => { if (vivo) setErrorMapa(e instanceof ErrorAseo ? avisoDeError(e).texto : "No se pudo cargar el mapa."); });
    return () => { vivo = false; };
  }, [actividad, modalidad]);
  // Cercanía: una consulta cuando la posición cambia de manera notable (no en cada actualización del GPS)
  useEffect(() => {
    if (!fix) return;
    let vivo = true;
    apiAseo.cercanas(actividad, modalidad, fix.lat, fix.lon).then((r) => { if (vivo) setCercanas(r); }).catch(() => { /* la cercanía es ayuda: sin ella el mapa y la búsqueda siguen */ });
    return () => { vivo = false; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave, actividad, modalidad]);

  return (
    <>
      {ubic.estado === "denegada" || ubic.estado === "no_disponible" || ubic.estado === "error" ? <p className="aseo-aviso" role="status">{ubic.mensaje} El mapa se muestra de toda la ciudad.</p> : null}
      {errorMapa ? <p className="aseo-aviso" role="alert">{errorMapa}</p> : !features ? <p className="campo-sub">Cargando el mapa…</p> : (
        <Suspense fallback={<p className="campo-sub">Cargando el mapa…</p>}>
          <MapaRutas features={features} posicion={fix ? { lat: fix.lat, lon: fix.lon, precision: fix.precision_m } : null} zoomInicial={zoomInicial} seleccionada={toque && toque.length === 1 ? toque[0] : null}
            resaltadas={cercanas.filter((c) => c.dentro).map((c) => c.ruta_id)} onToque={(ids) => setToque(ids)} />
        </Suspense>
      )}
      {features && features.length === 0 ? <p className="campo-sub">Todavía no hay rutas con trazado en el mapa. Use la búsqueda.</p> : null}
      {toque !== null ? (toque.length === 0 ? <p className="campo-sub">No hay una ruta en ese punto. Toque sobre una línea o un área del mapa.</p> : (
        <>
          <p className="campo-etiqueta">{toque.length === 1 ? "Ruta en ese punto" : `Elija la ruta (${toque.length} pasan por ese punto)`}</p>
          <ul className="aseo-lista">{toque.map((id) => porId.get(id)).filter((r): r is RutaPlan => !!r).sort((a, b) => a.codigo.localeCompare(b.codigo)).map((r) => tarjeta(r))}</ul>
        </>
      )) : null}
      {toque === null && cercanas.length > 0 ? (
        <>
          <p className="campo-etiqueta">Rutas más cercanas</p>
          <ul className="aseo-lista">{cercanas.slice(0, 6).map((c) => { const r = porId.get(c.ruta_id); return r ? tarjeta(r, c.dentro ? "Está sobre ella" : textoDistancia(c.distancia_m)) : null; })}</ul>
        </>
      ) : null}
    </>
  );
}
