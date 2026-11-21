import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUENTE_BASE_CALLES, FUENTE_BASE_SATELITAL } from "../../lib/mapaBase";
import { ErrorTec } from "../apiTecnica";
import { apiPtar, type FichaElemento, type MapaPtar, type PropElemento, type TipoElemento } from "./apiPtar";
import "./ptar.css";

// PTAR-2 (Code C, 21-nov): el mapa interactivo de la planta (pieza central de la primera entrega). Fondo: la foto satelital ESRI World Imagery (D8), con «Calles» de respaldo.
// Cada elemento es clicable y abre su ficha (nombre, alias editable con motivo, tipo, medida, activo de redes e indicadores; hoy «sin variables asignadas»).
// Los colores del mapa son neutros (tokens_ptar.css) mientras no haya variables; los de estado llegan con los indicadores (PTAR-4).

const GRUPOS: { clave: string; nombre: string; tipos: TipoElemento[] }[] = [
  { clave: "lagunas", nombre: "Lagunas", tipos: ["laguna"] },
  { clave: "tramos", nombre: "Colectores, tramos y conductos", tipos: ["tramo"] },
  { clave: "pozos", nombre: "Pozos y descargas", tipos: ["pozo", "descarga"] },
  { clave: "puntos", nombre: "Puntos de medición", tipos: ["punto_medicion"] },
];
const CAPAS_GRUPO: Record<string, string[]> = { lagunas: ["ptar-laguna-relleno", "ptar-laguna-borde"], tramos: ["ptar-tramo-redes", "ptar-tramo-dibujo"],
  pozos: ["ptar-pozo", "ptar-descarga"], puntos: ["ptar-punto"] };
const CLICABLES = ["ptar-punto", "ptar-descarga", "ptar-pozo", "ptar-tramo-dibujo", "ptar-tramo-redes", "ptar-laguna-relleno", "ptar-perimetro-relleno"];
const LAGUNA: Record<string, string> = { anaerobia: "Anaerobia", facultativa: "Facultativa", maduracion: "De maduración" };
const ETAPA: Record<number, string> = { 1: "1 · Anaerobia", 2: "2 · Facultativa", 3: "3 · Maduración" };
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 2 });

function color(nombre: string, respaldo: string) {
  const v = typeof window === "undefined" ? "" : getComputedStyle(document.documentElement).getPropertyValue(nombre).trim();
  return v || respaldo;
}

export function MapaPTAR({ instalacion = "ptar" }: { instalacion?: string }) {
  const cont = useRef<HTMLDivElement | null>(null);
  const mapa = useRef<maplibregl.Map | null>(null);
  const [datos, setDatos] = useState<MapaPtar | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const [base, setBase] = useState<"satelital" | "calles">("satelital");
  const [ocultos, setOcultos] = useState<Set<string>>(new Set());
  const [sel, setSel] = useState<string | null>(null);
  const [buscar, setBuscar] = useState("");
  const [avisoBuscar, setAvisoBuscar] = useState<string | null>(null);
  const [listo, setListo] = useState(false);      // el estilo del mapa cargó (después, las capas se cambian directo: isStyleLoaded() vuelve a falso mientras bajan mosaicos)

  useEffect(() => { let vivo = true; setError(null); setDatos(null);
    apiPtar.mapa(instalacion).then((d) => { if (vivo) setDatos(d); }).catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e.message : "No se pudo cargar el mapa."); });
    return () => { vivo = false; }; }, [instalacion, intento]);

  // el mapa: una vez por carga del servidor (un alias nuevo solo cambia la fuente, no rehace el mapa)
  const cargado = datos !== null;
  const datosRef = useRef<MapaPtar | null>(null); datosRef.current = datos;
  useEffect(() => {
    const datos = datosRef.current;
    if (!datos || !cont.current) return;
    const c = { per: color("--ptar-mapa-perimetro", "#f4f1ec"), lag: color("--ptar-mapa-laguna", "#ffffff"), tra: color("--ptar-mapa-tramo", "#ffffff"),
                con: color("--ptar-mapa-conducto", "#d5dde6"), poz: color("--ptar-mapa-pozo", "#eef2f5"), ctn: color("--ptar-mapa-contorno", "#22313f"), sel: color("--ptar-mapa-seleccion", "#4a90d9") };
    // la selección va por feature-state («sel»): la fuente usa el código como id (promoteId)
    const esSel = (a: unknown, b: unknown) => ["case", ["boolean", ["feature-state", "sel"], false], a, b] as unknown as maplibregl.ExpressionSpecification;
    const tipo = (t: string) => ["==", ["get", "tipo"], t] as maplibregl.FilterSpecification;
    const m = new maplibregl.Map({
      container: cont.current, attributionControl: { compact: true }, maxZoom: 20,
      bounds: datos.caja ? [[datos.caja[0], datos.caja[1]], [datos.caja[2], datos.caja[3]]] : undefined, fitBoundsOptions: { padding: 24 },
      style: { version: 8, sources: { calles: FUENTE_BASE_CALLES, satelital: FUENTE_BASE_SATELITAL, ptar: { type: "geojson", data: datos.elementos as GeoJSON.FeatureCollection, promoteId: "codigo" } },
        layers: [
          { id: "calles", type: "raster", source: "calles", layout: { visibility: "none" } },
          { id: "satelital", type: "raster", source: "satelital" },
          { id: "ptar-perimetro-relleno", type: "fill", source: "ptar", filter: tipo("perimetro"), paint: { "fill-color": c.per, "fill-opacity": 0.01 } },
          { id: "ptar-perimetro", type: "line", source: "ptar", filter: tipo("perimetro"), paint: { "line-color": esSel(c.sel, c.per) as unknown as string, "line-width": 2.5, "line-dasharray": [3, 2] } },
          { id: "ptar-laguna-relleno", type: "fill", source: "ptar", filter: tipo("laguna"), paint: { "fill-color": esSel(c.sel, c.lag) as unknown as string, "fill-opacity": esSel(0.4, 0.14) as unknown as number } },
          { id: "ptar-laguna-borde", type: "line", source: "ptar", filter: tipo("laguna"), paint: { "line-color": esSel(c.sel, c.lag) as unknown as string, "line-width": esSel(3, 1.5) as unknown as number } },
          { id: "ptar-tramo-redes", type: "line", source: "ptar", filter: ["all", tipo("tramo"), ["==", ["get", "origen"], "redes"]] as maplibregl.FilterSpecification,
            paint: { "line-color": esSel(c.sel, c.con) as unknown as string, "line-width": ["interpolate", ["linear"], ["zoom"], 14, esSel(4, 0.8), 18, esSel(5, 2.5)] as unknown as number } },
          { id: "ptar-tramo-dibujo", type: "line", source: "ptar", filter: ["all", tipo("tramo"), ["==", ["get", "origen"], "dibujo"]] as maplibregl.FilterSpecification,
            paint: { "line-color": esSel(c.sel, c.tra) as unknown as string, "line-width": esSel(6, 3.5) as unknown as number } },
          { id: "ptar-pozo", type: "circle", source: "ptar", filter: tipo("pozo"), paint: { "circle-color": esSel(c.sel, c.poz) as unknown as string,
            "circle-radius": ["interpolate", ["linear"], ["zoom"], 14, esSel(6, 1.5), 18, esSel(8, 5)] as unknown as number, "circle-stroke-color": c.ctn, "circle-stroke-width": 1 } },
          { id: "ptar-descarga", type: "circle", source: "ptar", filter: tipo("descarga"), paint: { "circle-color": esSel(c.sel, c.poz) as unknown as string, "circle-radius": esSel(9, 6) as unknown as number,
            "circle-stroke-color": c.ctn, "circle-stroke-width": 2.5 } },
          { id: "ptar-punto", type: "circle", source: "ptar", filter: tipo("punto_medicion"), paint: { "circle-color": c.ctn, "circle-radius": esSel(10, 7) as unknown as number,
            "circle-stroke-color": esSel(c.sel, c.lag) as unknown as string, "circle-stroke-width": 3 } },
        ] },
    });
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    m.once("load", () => setListo(true));
    m.on("click", (ev) => {
      const capas = CLICABLES.filter((id) => m.getLayer(id) && m.getLayoutProperty(id, "visibility") !== "none");
      const caja: [maplibregl.PointLike, maplibregl.PointLike] = [[ev.point.x - 6, ev.point.y - 6], [ev.point.x + 6, ev.point.y + 6]];
      const f = m.queryRenderedFeatures(caja, { layers: capas });
      // lo más pequeño gana: punto > descarga > pozo > tramo > laguna > perímetro (el orden de CLICABLES)
      const orden = (id: string) => CLICABLES.indexOf(id);
      const g = f.sort((a, b) => orden(a.layer.id) - orden(b.layer.id))[0];
      setSel(g ? String((g.properties as PropElemento).codigo) : null);
    });
    for (const id of CLICABLES) { m.on("mouseenter", id, () => { m.getCanvas().style.cursor = "pointer"; }); m.on("mouseleave", id, () => { m.getCanvas().style.cursor = ""; }); }
    mapa.current = m;
    (window as unknown as { __mapaPtar?: maplibregl.Map }).__mapaPtar = m;      // para las pruebas de Chrome
    return () => { m.remove(); mapa.current = null; setListo(false); };
  }, [cargado, intento]);

  // selección → resaltado (feature-state)
  const anterior = useRef<string | null>(null);
  useEffect(() => {
    const m = mapa.current; if (!m || !listo) return;
    if (anterior.current) m.setFeatureState({ source: "ptar", id: anterior.current }, { sel: false });
    if (sel) m.setFeatureState({ source: "ptar", id: sel }, { sel: true });
    anterior.current = sel;
  }, [sel, listo]);
  // fondo y grupos
  useEffect(() => { const m = mapa.current; if (!m || !listo) return;
    m.setLayoutProperty("satelital", "visibility", base === "satelital" ? "visible" : "none"); m.setLayoutProperty("calles", "visibility", base === "calles" ? "visible" : "none"); }, [base, listo]);
  useEffect(() => { const m = mapa.current; if (!m || !listo) return;
    for (const g of GRUPOS) for (const id of CAPAS_GRUPO[g.clave]) m.setLayoutProperty(id, "visibility", ocultos.has(g.clave) ? "none" : "visible"); }, [ocultos, listo]);

  const props = useMemo(() => (datos?.elementos.features ?? []).map((f) => f.properties), [datos]);
  const irA = (codigo: string) => {
    const f = datos?.elementos.features.find((x) => x.properties.codigo === codigo); const m = mapa.current;
    if (!f || !m) return;
    const b = new maplibregl.LngLatBounds();
    const agregar = (c: unknown): void => { if (Array.isArray(c) && typeof c[0] === "number") b.extend(c as [number, number]); else if (Array.isArray(c)) c.forEach(agregar); };
    agregar((f.geometry as GeoJSON.Point).coordinates);
    m.fitBounds(b, { padding: 60, maxZoom: f.geometry.type === "Point" ? 18 : 17.5, duration: 400 });
    setSel(codigo);
  };
  const alBuscar = (e: React.FormEvent) => {
    e.preventDefault(); const q = buscar.trim().toLowerCase(); setAvisoBuscar(null);
    if (!q) return;
    const h = props.find((p) => p.codigo.toLowerCase() === q || (p.activo ?? "").toLowerCase() === q)
      ?? props.find((p) => (p.alias ?? "").toLowerCase().includes(q) || p.nombre.toLowerCase().includes(q) || p.codigo.toLowerCase().includes(q));
    if (h) irA(h.codigo); else setAvisoBuscar("No hay ningún elemento con ese código, nombre o alias.");
  };
  const alAlias = (codigo: string, alias: string | null) => setDatos((d) => d && ({ ...d, elementos: { ...d.elementos, features: d.elementos.features.map((f) =>
    f.properties.codigo === codigo ? { ...f, properties: { ...f.properties, alias: alias ?? undefined } } : f) } }));
  useEffect(() => { if (!listo) return; const s = mapa.current?.getSource("ptar") as maplibregl.GeoJSONSource | undefined; if (s && datos) s.setData(datos.elementos as GeoJSON.FeatureCollection); }, [datos, listo]);

  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => setIntento((x) => x + 1)}>Reintentar</button></div>;
  if (!datos) return <p className="td-sub" role="status">Cargando el mapa de la planta…</p>;
  const n = datos.por_tipo;
  return (
    <div className="ptar-mapa-pagina" data-testid="ptar-mapa">
      <div className="ptar-mapa-cab">
        <div>
          <h2 className="ptar-tit">{datos.instalacion.nombre}</h2>
          <p className="td-sub">{nf.format(datos.total)} elementos: {n.laguna ?? 0} lagunas, {n.tramo ?? 0} colectores y conductos, {n.pozo ?? 0} pozos{n.descarga ? `, ${n.descarga} ${n.descarga === 1 ? "descarga" : "descargas"}` : ""}{n.punto_medicion ? `, ${n.punto_medicion} ${n.punto_medicion === 1 ? "punto de medición" : "puntos de medición"}` : ""}. Toque un elemento para ver su ficha.</p>
        </div>
        <form className="ptar-buscar" onSubmit={alBuscar} role="search">
          <label htmlFor="ptar-q" className="ptar-oculto">Buscar un elemento</label>
          <input id="ptar-q" type="search" value={buscar} onChange={(e) => setBuscar(e.target.value)} placeholder="Código, activo, nombre o alias" autoComplete="off" />
          <button type="submit" className="tec-boton-sec">Buscar</button>
        </form>
        {avisoBuscar ? <p className="ptar-aviso" role="status">{avisoBuscar}</p> : null}
      </div>
      <div className="ptar-mapa-cuerpo">
        <div className="ptar-mapa-marco">
          <div ref={cont} className="ptar-mapa" role="region" aria-label={`Mapa de ${datos.instalacion.nombre}`} />
          <div className="ptar-fondo" role="group" aria-label="Fondo del mapa">
            <button type="button" aria-pressed={base === "satelital"} onClick={() => setBase("satelital")}>Foto satelital</button>
            <button type="button" aria-pressed={base === "calles"} onClick={() => setBase("calles")}>Calles</button>
          </div>
        </div>
        <aside className="ptar-lado">
          {sel ? <FichaPTAR key={sel} codigo={sel} onCerrar={() => setSel(null)} onAlias={alAlias} onIr={irA} />
            : <p className="ptar-ayuda">Toque una laguna, un colector, un pozo o un punto del mapa para ver su ficha.</p>}
          <fieldset className="ptar-capas">
            <legend>Qué se ve</legend>
            {GRUPOS.map((g) => (
              <label key={g.clave} className="ptar-capa">
                <input type="checkbox" checked={!ocultos.has(g.clave)} onChange={() => setOcultos((o) => { const x = new Set(o); if (x.has(g.clave)) x.delete(g.clave); else x.add(g.clave); return x; })} />
                <span className={`ptar-muestra ptar-muestra-${g.clave}`} aria-hidden="true" />{g.nombre}
              </label>
            ))}
            <p className="ptar-nota">El perímetro de la planta va punteado. Los colores de estado (normal, fuera de referencia, sin dato reciente) se verán cuando cada elemento tenga sus variables.</p>
          </fieldset>
        </aside>
      </div>
    </div>
  );
}

function FichaPTAR({ codigo, onCerrar, onAlias, onIr }: { codigo: string; onCerrar: () => void; onAlias: (codigo: string, alias: string | null) => void; onIr: (codigo: string) => void }) {
  const [f, setF] = useState<FichaElemento | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editar, setEditar] = useState(false);
  const [alias, setAlias] = useState("");
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => { let vivo = true; setError(null);
    apiPtar.elemento(codigo).then((x) => { if (vivo) { setF(x); setAlias(x.alias ?? ""); } }).catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e.message : "No se pudo cargar la ficha."); });
    return () => { vivo = false; }; }, [codigo, vez]);
  const guardar = async (e: React.FormEvent) => {
    e.preventDefault(); setGuardando(true); setAviso(null);
    try { const r = await apiPtar.alias(codigo, alias.trim(), motivo.trim()); onAlias(codigo, r.alias); setAviso({ tipo: "ok", texto: r.alias ? `Alias guardado: «${r.alias}».` : "Se quitó el alias." });
          setEditar(false); setMotivo(""); setVez((v) => v + 1); }
    catch (er) { setAviso({ tipo: "error", texto: er instanceof ErrorTec ? er.message : "No se pudo guardar el alias." }); }
    finally { setGuardando(false); }
  };
  if (error) return <section className="ptar-ficha" role="alert"><p>{error}</p><button type="button" className="tec-boton-sec" onClick={onCerrar}>Cerrar</button></section>;
  if (!f) return <section className="ptar-ficha" role="status"><p className="td-sub">Cargando la ficha…</p></section>;
  const a = f.atributos as Record<string, string | number | undefined>;
  const filas: [string, string][] = [["Código", f.codigo]];
  if (f.activo) filas.push(["Activo de redes", f.activo]);
  if (f.tipo === "laguna") {
    if (a.tipo_laguna) filas.push(["Tipo de laguna", LAGUNA[String(a.tipo_laguna)] ?? String(a.tipo_laguna)]);
    if (ETAPA[f.orden]) filas.push(["Etapa del proceso", ETAPA[f.orden]]);
    if (a.tren) filas.push(["Tren", String(a.tren)]);
  }
  if (f.medida.area_ha !== undefined) filas.push(["Área", `${nf.format(f.medida.area_ha)} ha (${nf.format(f.medida.area_m2 ?? 0)} m²)`]);
  if (f.medida.longitud_m !== undefined) filas.push(["Longitud", `${nf.format(f.medida.longitud_m)} m`]);
  if (f.medida.lat !== undefined) filas.push(["Coordenadas", `${f.medida.lat}, ${f.medida.lon}`]);
  if (a.diametro_mm) filas.push(["Diámetro", `${nf.format(Number(a.diametro_mm))} mm`]);
  if (a.material) filas.push(["Material", String(a.material)]);
  if (a.profundidad_m) filas.push(["Profundidad", `${nf.format(Number(a.profundidad_m))} m`]);
  if (a.punto_previsto) filas.push(["Punto de medición previsto", String(a.punto_previsto)]);
  return (
    <section className="ptar-ficha" data-testid="ptar-ficha" data-codigo={f.codigo} aria-labelledby="ptar-ficha-tit">
      <div className="ptar-ficha-cab">
        <span className="ptar-chip">{f.tipo_texto}</span>
        <button type="button" className="ptar-cerrar" onClick={onCerrar} aria-label="Cerrar la ficha">×</button>
      </div>
      <h3 id="ptar-ficha-tit">{f.alias ? f.alias : f.nombre}</h3>
      {f.alias ? <p className="ptar-sub">{f.nombre}</p> : null}
      <dl className="ptar-datos">{filas.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
        {f.desde ? <div><dt>Viene de</dt><dd><button type="button" className="td-enlace" onClick={() => onIr(f.desde!.codigo)}>{f.desde.nombre}</button></dd></div> : null}
        {f.hasta ? <div><dt>Va a</dt><dd><button type="button" className="td-enlace" onClick={() => onIr(f.hasta!.codigo)}>{f.hasta.nombre}</button></dd></div> : null}
      </dl>
      <div className="ptar-indicadores" data-testid="ptar-indicadores">
        <h4>Indicadores</h4>
        <p>Sin variables asignadas. Cuando se le asignen, aquí se verán sus últimos valores y su estado frente a la referencia.</p>
      </div>
      {aviso ? <p className={aviso.tipo === "ok" ? "ptar-ok" : "ptar-error"} role={aviso.tipo === "ok" ? "status" : "alert"}>{aviso.texto}</p> : null}
      {editar ? (
        <form className="ptar-alias" onSubmit={guardar}>
          <label htmlFor="ptar-alias">Alias (nombre corto; vacío para quitarlo)</label>
          <input id="ptar-alias" value={alias} maxLength={60} onChange={(e) => setAlias(e.target.value)} />
          <label htmlFor="ptar-motivo">Motivo</label>
          <textarea id="ptar-motivo" value={motivo} maxLength={1000} rows={2} onChange={(e) => setMotivo(e.target.value)} />
          <div className="ptar-botones">
            <button type="submit" className="tec-boton" disabled={guardando || motivo.trim().length < 10}>{guardando ? "Guardando…" : "Guardar alias"}</button>
            <button type="button" className="tec-boton-sec" onClick={() => { setEditar(false); setAlias(f.alias ?? ""); setMotivo(""); }}>Cancelar</button>
          </div>
          {motivo.trim().length < 10 ? <p className="ptar-nota">El motivo lleva al menos 10 caracteres.</p> : null}
        </form>
      ) : <button type="button" className="tec-boton-sec" onClick={() => { setEditar(true); setAviso(null); }}>{f.alias ? "Cambiar el alias" : "Poner un alias"}</button>}
      {f.alias_historial.length > 0 ? (
        <details className="ptar-historial"><summary>Historial del alias ({f.alias_historial.length})</summary>
          <ul>{f.alias_historial.map((h, i) => <li key={i}><strong>{h.alias ?? "(sin alias)"}</strong> · {new Date(h.creado_en).toLocaleString("es-CO")} · {h.motivo}</li>)}</ul>
        </details>) : null}
    </section>
  );
}

