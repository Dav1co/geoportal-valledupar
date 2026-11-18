import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import "./hoja.css";
import membrete from "./membrete_logo_y_franja.png";
import logo from "./membrete_logo.png";
import { apiLev, type ActaLevantar as Acta } from "./apiLevantar";
import { ErrorTec } from "./apiTecnica";

// «Acta del reporte de activo» en PDF (pase corto del Corte 14): una por punto por levantar. El mismo documento en dos lugares: al terminar «Reportar activo»
// (quien reportó ve la suya) y en Por verificar → «Otros activos por levantamiento» (supervisor de distribución y administrador, todas). Quién la ve lo decide
// el SERVIDOR, que deja la consulta en la auditoría. Trae: código, quién lo reportó (funcionario: nombre, área y cargo), fecha y hora, servicio, tipo, fotos
// (con su sello de hora y GPS, que va estampado en la imagen), coordenadas, precisión, minimapa del punto, observación, estado e historial.
// Sin datos de suscriptores. Hoja membretada oficial (guía visual §9): carta, Arial y «Página N de M». El PDF lo hace el navegador al imprimir.
const BASE = { type: "raster" as const, tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], tileSize: 256, maxzoom: 19, attribution: "© OpenStreetMap" };
const fechaHora = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "long", year: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Bogota" });
const CON_CAJAS = (() => { const m = typeof navigator !== "undefined" ? /(?:Chrome|Edg)\/(\d+)/.exec(navigator.userAgent) : null; return !!m && Number(m[1]) >= 131; })();

export function ActaLevantar({ codigo, onCerrar }: { codigo: string; onCerrar: () => void }) {
  const [d, setD] = useState<Acta | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [mapa, setMapa] = useState<{ img: string | null } | null>(null);
  const [fotos, setFotos] = useState(0);
  const lienzo = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let vivo = true; setD(null); setError(null); setMapa(null); setFotos(0);
    apiLev.acta(codigo).then((r) => { if (vivo) setD(r); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Esta acta la ven quien reportó el activo, el supervisor de distribución y el administrador." : e instanceof Error ? e.message : "No se pudo preparar el acta."); });
    return () => { vivo = false; };
  }, [codigo]);

  // El minimapa del punto: se dibuja una vez y se convierte en imagen, para que salga igual en el PDF; el punto va encima, en HTML.
  useEffect(() => {
    if (!d || !lienzo.current) return;
    let vivo = true; let hecho = false;
    const m = new maplibregl.Map({ container: lienzo.current, interactive: false, attributionControl: false, preserveDrawingBuffer: true, center: [d.lon, d.lat], zoom: 17,
      style: { version: 8, sources: { base: BASE }, layers: [{ id: "fondo", type: "background", paint: { "background-color": "#f2f5f8" } }, { id: "base", type: "raster", source: "base" }] } });
    m.on("error", () => {});
    const tomar = () => {
      if (!vivo || hecho) return; hecho = true;
      let img: string | null = null;
      try { img = m.getCanvas().toDataURL("image/png"); } catch { img = null; }
      setMapa({ img }); m.remove();
    };
    m.once("idle", tomar);
    const reloj = setTimeout(tomar, 6000);      // sin señal el mapa base no llega: el acta sale igual
    return () => { vivo = false; clearTimeout(reloj); if (!hecho) m.remove(); };
  }, [d]);

  const lista = !!d && mapa !== null && fotos >= d.fotos.length;
  const r = d?.reporto;
  return createPortal(
    <div className={`hoja-capa${CON_CAJAS ? " hoja-con-cajas" : ""}`} role="dialog" aria-modal="true" aria-label={`Acta del reporte de activo ${codigo}`} data-testid="acta" data-lista={lista ? "si" : "no"}>
      <style>{`@page { size: 8.5in 11in; margin: 2.5cm 3cm 4cm 3cm; @top-left { content: "Página " counter(page) " de " counter(pages); font: 9pt Arial, Helvetica, sans-serif; color: #52626f; }
        @top-right { content: ""; width: 6cm; background: url("${logo}") right center / 4.4cm auto no-repeat; }
        @bottom-left-corner { content: ""; background: url("${membrete}") 0 bottom / 21.59cm auto no-repeat; }
        @bottom-center { content: ""; width: 15.59cm; background: url("${membrete}") -3cm bottom / 21.59cm auto no-repeat; }
        @bottom-right-corner { content: ""; background: url("${membrete}") -18.59cm bottom / 21.59cm auto no-repeat; } }`}</style>
      <div className="hoja-barra">
        <strong>Acta del reporte de activo</strong>
        <div className="hoja-barra-acc">
          <button type="button" className="tec-boton" disabled={!lista} data-testid="acta-imprimir" onClick={() => window.print()}>{lista ? "Imprimir o guardar como PDF" : error ? "Sin acta" : "Preparando el acta…"}</button>
          <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cerrar</button>
        </div>
        <p className="hoja-ayuda">En la ventana de impresión elija «Guardar como PDF» y el tamaño carta, sin encabezados ni pies del navegador.</p>
      </div>
      {error ? <p className="tec-aviso tec-aviso-error hoja-aviso" role="alert">{error}</p> : null}
      {!d && !error ? <p className="hoja-aviso" role="status">Preparando el acta…</p> : null}
      {d ? (
        <div className="hoja-papel hoja-carta acta">
          <img className="hoja-logo" src={logo} alt="" aria-hidden="true" />
          <img className="hoja-franja" src={membrete} alt="" aria-hidden="true" />
          <h1>Acta del reporte de activo</h1>
          <p className="acta-codigo" data-testid="acta-codigo">{d.codigo}</p>
          <p className="hoja-sub">Activo encontrado en la calle que no está en la red («Encontrar o reportar activo»). Acta generada el {fechaHora(d.generado_en)}</p>
          <dl className="acta-dl">
            <div className="acta-ancho"><dt>Reportado por</dt><dd data-testid="acta-reporto"><strong>{r?.nombre}</strong>{r?.area ? ` · ${r.area}` : ""}{r?.cargo ? ` · ${r.cargo}` : " · sin cargo registrado"}</dd></div>
            <div><dt>Fecha y hora</dt><dd>{fechaHora(d.registrado_en)}</dd></div>
            <div><dt>Estado actual</dt><dd><strong>{d.estado_nombre}</strong>{d.activo ? ` · activo ${d.activo}` : ""}</dd></div>
            <div><dt>Servicio</dt><dd>{d.servicio === "acueducto" ? "Acueducto" : "Alcantarillado"}</dd></div>
            <div><dt>Tipo de activo</dt><dd>{d.tipo_nombre}</dd></div>
            <div><dt>Coordenadas</dt><dd className="hoja-coord">{d.lat.toFixed(6)}, {d.lon.toFixed(6)}</dd></div>
            <div><dt>Precisión del GPS</dt><dd>± {Math.round(d.precision_m)} m{d.precision_baja ? <> · <strong>Precisión baja</strong></> : null}</dd></div>
            {d.sector ? <div><dt>Sector hidráulico</dt><dd>{d.sector}</dd></div> : null}
            <div className="acta-ancho"><dt>Observación</dt><dd>{d.observacion ?? "Sin observación."}</dd></div>
          </dl>
          <figure className="hoja-mapa acta-mapa" data-testid="acta-mapa">
            {mapa ? <>{mapa.img ? <img className="hoja-mapa-img" src={mapa.img} alt="Minimapa del punto reportado" /> : <div className="hoja-mapa-img" />}<span className="hoja-num acta-punto" style={{ left: "50%", top: "50%" }} aria-hidden="true" /></>
              : <div ref={lienzo} className="hoja-mapa-lienzo" />}
            <figcaption>Minimapa del punto reportado (posición del GPS al reportar). Mapa base © OpenStreetMap.</figcaption>
          </figure>
          <h2>Fotos ({d.fotos.length})</h2>
          <div className="acta-fotos">
            {d.fotos.map((f) => <figure key={f.n}><img src={f.url} alt={`Foto ${f.n} de ${d.codigo}`} onLoad={() => setFotos((x) => x + 1)} onError={() => setFotos((x) => x + 1)} /><figcaption>Foto {f.n} · guardada el {fechaHora(f.creado_en)}</figcaption></figure>)}
          </div>
          <p className="hoja-sub">Cada foto lleva estampado su sello de hora y GPS (lo pone el celular al tomarla; la hora oficial es la del servidor).</p>
          <h2>Historial</h2>
          <table className="hoja-tabla acta-historial">
            <thead><tr><th>Qué pasó</th><th>Cuándo</th><th>Quién</th><th>Motivo o activo</th></tr></thead>
            <tbody>{d.historial.map((h, i) => <tr key={i} data-evento={h.tipo}><td><strong>{h.que}</strong></td><td>{fechaHora(h.cuando)}</td><td>{h.quien}</td><td>{[h.activo ? `Activo ${h.activo}` : null, h.motivo].filter(Boolean).join(" · ") || "—"}</td></tr>)}</tbody>
          </table>
        </div>
      ) : null}
    </div>, document.body);
}
