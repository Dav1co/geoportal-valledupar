// Zona «Mapa de calor» de Cartera desagregada.
// NO toca MapaCalor.tsx (mapa de Pérdidas). Reutiliza mapaCalorComun.ts (cuantiles, color, cuadrado con lado parametrizable) y lib/mapaBase.ts.
// Solo agregados: nunca contratos, nombres, direcciones ni coordenadas individuales. Celdas de menos de 5 contratos no llegan del servidor.
import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { biCache } from "../cacheBi";
import { cuadrado } from "../mapaCalorComun";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import { fmtDecimal, fmtEntero, fmtMillonesEnteros } from "../formato";
import { FiltroMultiple } from "../FiltroMultiple";
import "../carteraMapa.css";
import { usePantallaCompleta } from "../usePantallaCompleta";
import {
  COLORES_CALOR, DEGRADE_CALOR_CSS, FILTROS_VACIO, MEDIDAS, barriosVisibles, cajaCeldas, capasEfectivas, depurarBarrios, escalaVisible, hayFiltro, leerCatalogo, leerMapa,
  AYUDA_TRAMOS, intensidadBaseCalor, intensidadCalor, paramsCatalogo, paramsMapa, pesoCalor, pesosPorCuantil, radioCalor, rotuloBarrio, rotulosBandas, valorCelda,
  type CapasMapa, type Catalogo, type Filtros, type Medida, type Resolucion, type RespuestaMapa,
} from "../mapaCarteraCalculo";

const FUENTE = "bi_interno.cartera_mapa_contrato (hechos.cartera_contrato; coordenadas y barrio de public.predios_comercial; comuna de cartera_contrato o, si falta, del catastro)";
const MENOS_5 = "menos de 5 contratos";
const pesos = (v: number) => `$ ${fmtEntero(Math.round(v))}`;
const pesosM = (v: number | null) => (v == null ? MENOS_5 : fmtMillonesEnteros(v));

export function ZonaMapaCartera({ periodo }: { periodo: string }) {
  const [cat, setCat] = useState<Catalogo | null>(null);
  const [filtros, setFiltros] = useState<Filtros>(FILTROS_VACIO);
  const [medida, setMedida] = useState<Medida>("deuda");
  const [res, setRes] = useState<Resolucion>("auto");
  const [capas, setCapas] = useState<CapasMapa>({ celdas: true, calor: false });   // por defecto solo Celdas
  const [datos, setDatos] = useState<RespuestaMapa | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const [listo, setListo] = useState(false);              // el mapa ya cargó su estilo (para pintar datos que llegaron antes)
  const seccionRef = useRef<HTMLDivElement>(null);
  const topRef = useRef<HTMLDivElement>(null);
  const leyRef = useRef<HTMLDivElement>(null);
  const cont = useRef<HTMLDivElement>(null);
  const mapaRef = useRef<maplibregl.Map | null>(null);
  const listoRef = useRef(false);
  const ajusteRef = useRef<string>("");   // firma de lo que debe provocar un ajuste de encuadre (filtros, resolución, período), no la medida

  // 1) Catálogo (comunas, barrios, ciclos) al abrir; no depende de los filtros.
  useEffect(() => {
    let vivo = true;
    biCache("v_cartera_mapa", paramsCatalogo(periodo)).then((r) => { if (vivo) setCat(leerCatalogo(r.datos ?? [])); }).catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
  }, [periodo, intento]);

  // 2) Capa activa: se recalcula con cada cambio de filtro, medida, período o resolución (con una espera corta para no pedir en cada clic).
  useEffect(() => {
    let vivo = true;
    setCargando(true);
    setError(null);
    const t = setTimeout(() => {
      biCache("v_cartera_mapa", paramsMapa(periodo, medida, res, filtros))
        .then((r) => { if (vivo) { setDatos(leerMapa(r.datos ?? [])); setCargando(false); } })
        .catch((e: Error) => { if (vivo) { setError(e.message); setCargando(false); } });
    }, 250);
    return () => { vivo = false; clearTimeout(t); };
  }, [periodo, medida, res, filtros, intento]);

  // Mapa: se crea una vez. Celdas rellenas SIN contorno; borde fino solo en la celda señalada.
  useEffect(() => {
    if (!cont.current) return;
    const map = new maplibregl.Map({
      container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 11.5, attributionControl: { compact: true },
      style: { version: 8, sources: { base: FUENTE_BASE_CALLES }, layers: [{ id: "base", type: "raster", source: "base", paint: { "raster-saturation": -0.6, "raster-opacity": 0.8 } }] },
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    map.on("load", () => {
      map.addSource("cm", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      // Calor suave (debajo) y celdas (encima): la capa de calor se alimenta con los centros de las celdas YA recibidas (5 o más contratos) y no tiene bordes.
      map.addSource("cm-calor", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "cm-calor", type: "heatmap", source: "cm-calor", layout: { visibility: "none" },
        paint: { "heatmap-weight": ["get", "peso"], "heatmap-radius": radioCalor(250), "heatmap-intensity": intensidadCalor(1), "heatmap-color": ["interpolate", ["linear"], ["heatmap-density"], ...COLORES_CALOR], "heatmap-opacity": 0.78 } as never,
      });
      map.addLayer({ id: "cm-fill", type: "fill", source: "cm", paint: { "fill-color": "#C27A12", "fill-opacity": 0.88 } });
      map.addLayer({ id: "cm-resalte", type: "line", source: "cm", filter: ["==", ["get", "id"], ""], paint: { "line-color": "#0A2540", "line-width": 1.5 } });
      listoRef.current = true;
      setListo(true);   // los efectos de pintado dependen de «listo»: pintan los datos que hubieran llegado antes que el mapa
    });
    mapaRef.current = map;
    return () => { listoRef.current = false; setListo(false); map.remove(); mapaRef.current = null; };
  }, []);

  // Pantalla completa (hook común con el mapa de Pérdidas): modo, alto del mapa y alternar.
  const { modo, altoMapa, alternar: alternarPantalla } = usePantallaCompleta({ seccion: seccionRef, cont, top: topRef, ley: leyRef, redimensionar: () => mapaRef.current?.resize() });

  // Pintado: la escala se recalcula por cuantiles sobre lo visible; la ventana emergente solo muestra agregados.
  const pintado = useMemo(() => {
    if (!datos?.meta?.suficiente) return null;
    const lado = datos.meta.lado;
    const vals = datos.celdas.map((c) => valorCelda(c, medida)).filter((v): v is number => v != null);
    const escala = escalaVisible(vals);
    const features = datos.celdas.flatMap((c) => {
      const v = valorCelda(c, medida);
      if (v == null) return [];
      return [{ type: "Feature" as const, geometry: { type: "Polygon" as const, coordinates: [cuadrado(c.lon, c.lat, lado)] },
               properties: { id: c.id, v, n: c.n, s: c.s, n8: c.n8, s8: c.s8, n60: c.n60, s60: c.s60 } }];
    });
    // Calor suave: un punto por celda en su centro, con el peso normalizado por cuantiles del saldo de la medida en pesos (la participación no se pondera).
    const conValor = datos.celdas.flatMap((c) => { const v = valorCelda(c, medida); return v == null ? [] : [{ c, v }]; });
    const pesos = medida === "part60" ? [] : pesosPorCuantil(conValor.map((x) => x.v));
    const puntos = medida === "part60" ? [] : conValor.map((x, i) => ({ type: "Feature" as const, geometry: { type: "Point" as const, coordinates: [x.c.lon, x.c.lat] }, properties: { peso: pesoCalor(pesos[i]) } }));
    const intensidadBase = medida === "part60" ? 1 : intensidadBaseCalor(conValor.map((x, i) => ({ cx: x.c.cx, cy: x.c.cy, peso: pesoCalor(pesos[i]) })), lado);
    return { features, puntos, lado, intensidadBase, escala, caja: cajaCeldas(datos.celdas, lado) };
  }, [datos, medida]);

  useEffect(() => {
    const map = mapaRef.current;
    if (!map || !listoRef.current || !pintado) return;
    const fuente = map.getSource("cm") as maplibregl.GeoJSONSource | undefined;
    fuente?.setData({ type: "FeatureCollection", features: pintado.features });
    (map.getSource("cm-calor") as maplibregl.GeoJSONSource | undefined)?.setData({ type: "FeatureCollection", features: pintado.puntos });
    map.setPaintProperty("cm-calor", "heatmap-radius", radioCalor(pintado.lado) as never);          // 2,75 lados en metros → píxeles por zoom
    map.setPaintProperty("cm-calor", "heatmap-intensity", intensidadCalor(pintado.intensidadBase) as never);   // normalizada con los datos visibles
    const p = pintado.escala.paradas;
    // color continuo: interpolación lineal entre los cortes por cuantiles de lo visible; con un solo valor, color fijo
    if (p.length >= 4) map.setPaintProperty("cm-fill", "fill-color", ["interpolate", ["linear"], ["get", "v"], ...p] as never);
    else map.setPaintProperty("cm-fill", "fill-color", (p[1] as string | undefined) ?? "#C27A12");
    const firma = JSON.stringify([periodo, filtros, res]);
    if (pintado.caja && ajusteRef.current !== firma) {
      ajusteRef.current = firma;
      map.fitBounds([[pintado.caja[0], pintado.caja[1]], [pintado.caja[2], pintado.caja[3]]], { padding: 30, maxZoom: 16, duration: 400 });
    }
  }, [pintado, periodo, filtros, res, listo]);

  // Capas: Celdas y Calor suave son interruptores independientes. Con solo Calor suave la capa de celdas queda INVISIBLE (opacidad 0) pero activa, para que el cursor y el
  // clic sigan mostrando la ventana con los tres saldos. Con ambas, el calor va debajo y las celdas encima con transparencia. Sin ninguna, no hay capa que consultar.
  const ef = capasEfectivas(capas, medida);
  useEffect(() => {
    const map = mapaRef.current;
    if (!map || !listoRef.current) return;
    const algo = ef.celdas || ef.calor;
    map.setLayoutProperty("cm-calor", "visibility", ef.calor ? "visible" : "none");
    map.setLayoutProperty("cm-fill", "visibility", algo ? "visible" : "none");
    map.setLayoutProperty("cm-resalte", "visibility", ef.celdas ? "visible" : "none");   // sin celdas encendidas no se dibuja ningún cuadro, ni al pasar el cursor
    map.setPaintProperty("cm-fill", "fill-opacity", ef.celdas ? (ef.calor ? 0.5 : 0.88) : 0);
  }, [ef.celdas, ef.calor, listo]);

  // Ventana emergente por celda.
  useEffect(() => {
    const map = mapaRef.current;
    if (!map || !listoRef.current || !datos?.concilia) return;
    const popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false, maxWidth: "280px" });
    const total = datos.concilia.totalS;
    const mostrar = (e: maplibregl.MapLayerMouseEvent) => {
      const p = e.features?.[0]?.properties;
      if (!p) return;
      map.setFilter("cm-resalte", ["==", ["get", "id"], String(p.id)]);
      const n = Number(p.n), s = Number(p.s);
      const m = MEDIDAS.find((x) => x.id === medida)!;
      const valor = medida === "part60" ? `${fmtDecimal(Number(p.v), 1)} %` : pesosM(Number(p.v));
      const partic = total > 0 && medida !== "part60" ? `${fmtDecimal((Number(p.v) / total) * 100, 1)} % del total del filtro` : "";
      const sub = (v: unknown, k: unknown) => (v == null || v === "null" ? MENOS_5 : `${pesosM(Number(v))} (${fmtEntero(Number(k))} contratos)`);
      popup.setLngLat(e.lngLat).setHTML(`<div style="font-size:12px;line-height:1.45"><b>${m.corto}: ${valor}</b><br/>Contratos con deuda: ${fmtEntero(n)}<br/>${partic ? partic + "<br/>" : ""}Saldo medio por contrato: ${pesos(s / n)}<br/>Deuda total: ${pesosM(s)}<br/>Más de 8 facturas: ${sub(p.s8, p.n8)}<br/>Más de 60 facturas: ${sub(p.s60, p.n60)}</div>`).addTo(map);
    };
    map.on("mousemove", "cm-fill", mostrar);
    map.on("click", "cm-fill", mostrar);
    const salir = () => { popup.remove(); map.setFilter("cm-resalte", ["==", ["get", "id"], ""]); };
    map.on("mouseleave", "cm-fill", salir);
    return () => { map.off("mousemove", "cm-fill", mostrar); map.off("click", "cm-fill", mostrar); map.off("mouseleave", "cm-fill", salir); popup.remove(); };
  }, [datos, medida, listo]);

  const cambiar = (f: Filtros) => setFiltros(cat ? depurarBarrios(cat, f) : f);
  const bandas = rotulosBandas(datos?.cortes ?? null, pesos);
  const activo = hayFiltro(filtros);
  const mInfo = MEDIDAS.find((x) => x.id === medida)!;
  const c = datos?.concilia ?? null;

  // Leyenda: degradado continuo con los mismos cortes por cuantiles de lo visible que usa el mapa.
  const fmtValor = (v: number) => (medida === "part60" ? `${fmtDecimal(v, 1)} %` : pesosM(v));
  const leyenda = (() => {
    const p = pintado?.escala.paradas ?? [];
    const k = pintado?.escala.clases;
    if (!k || p.length < 2) return null;
    const rango = (p[p.length - 2] as number) - (p[0] as number);
    const stops = [] as string[];
    for (let i = 0; i < p.length; i += 2) stops.push(`${p[i + 1]} ${rango > 0 ? Math.round((((p[i] as number) - (p[0] as number)) / rango) * 100) : 0}%`);
    return { fondo: stops.length > 1 ? `linear-gradient(to right, ${stops.join(", ")})` : String(p[1]), min: k.min, max: k.max, cortes: k.cortes };
  })();
  const enPantalla = modo !== "normal";

  return (
    <div ref={seccionRef} className={`cm-seccion${enPantalla ? " cm-completa" : ""}${modo === "fijo" ? " cm-fijo" : ""}`}>
    <div className="dash-fila">
      <div className="dash-carta">
        <div className="cm-top" ref={topRef}>
        <div className="cm-encabezado">
          <b className="cm-titulo">Mapa de calor de la cartera</b>
          <span className="cm-ayuda">Esc para salir</span>
          <button type="button" className="dash-boton cm-boton-fs" onClick={alternarPantalla} aria-pressed={enPantalla}>
            {enPantalla ? "Salir de pantalla completa" : "Pantalla completa"}
          </button>
        </div>
        {error ? <div className="dash-estado"><p>No se pudo cargar el mapa: {error}</p><button className="dash-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button></div> : null}
        <div className="dash-nota"><b>No depende de los filtros de uso y estrato.</b> Los filtros de este mapa (comuna, barrio, ciclo y rango de deuda) son propios y solo actúan aquí.</div>
        <div className="cm-controles">
          <label>Medida <select value={medida} onChange={(e) => { const m = e.target.value as Medida; setMedida(m); if (m === "part60") setCapas({ celdas: true, calor: false }); }}>{MEDIDAS.map((m) => <option key={m.id} value={m.id}>{m.nombre}</option>)}</select></label>
          <label>Resolución <select value={res} onChange={(e) => setRes(e.target.value as Resolucion)}><option value="auto">Automática</option><option value="250">250 m</option><option value="100">100 m</option></select></label>
          <fieldset className="cm-capas">
            <legend>Capas</legend>
            <label><input type="checkbox" checked={ef.celdas} disabled={medida === "part60"} onChange={(e) => setCapas({ ...capas, celdas: e.target.checked })} /> Celdas</label>
            <label title={medida === "part60" ? "La participación es un porcentaje: solo se dibuja con Celdas" : undefined}>
              <input type="checkbox" checked={ef.calor} disabled={medida === "part60"} onChange={(e) => setCapas({ ...capas, calor: e.target.checked })} /> Calor suave
            </label>
          </fieldset>
          {cat ? (<>
            <FiltroMultiple etiqueta="Comuna" opciones={cat.comunas} elegidas={filtros.comunas} onCambio={(ids) => cambiar({ ...filtros, comunas: ids })} />
            <FiltroMultiple etiqueta="Barrio" buscable opciones={barriosVisibles(cat, filtros.comunas).map((b) => ({ ...b, nombre: rotuloBarrio(cat, b) }))} elegidas={filtros.barrios} onCambio={(ids) => cambiar({ ...filtros, barrios: ids })} />
            <FiltroMultiple etiqueta="Ciclo" opciones={cat.ciclos} elegidas={filtros.ciclos} onCambio={(ids) => cambiar({ ...filtros, ciclos: ids })} />
            <FiltroMultiple etiqueta="Antigüedad de la deuda del contrato" ayuda={AYUDA_TRAMOS} opciones={cat.tramos} elegidas={filtros.tramos} onCambio={(ids) => cambiar({ ...filtros, tramos: ids })} />
            <FiltroMultiple etiqueta="Rango de deuda (cuartiles)" alinearDerecha ayuda="Cuartiles del saldo por contrato de toda la ciudad en el período (contratos con saldo); no dependen de los otros filtros." vacio="Los cortes llegan con el mapa; si no aparecen, el período no los tiene." opciones={bandas.map((b) => ({ id: b.id, nombre: b.nombre }))} elegidas={filtros.bandas} onCambio={(ids) => cambiar({ ...filtros, bandas: ids })} />
          </>) : <span>Cargando filtros…</span>}
          {activo ? <span className="dash-marca-filtro">● Filtro activo <button type="button" onClick={() => setFiltros(FILTROS_VACIO)}>Limpiar</button></span> : null}
        </div>
        {mInfo.nota ? <div className="dash-nota"><b>{mInfo.nota}</b></div> : null}
        {filtros.tramos.length ? <div className="dash-nota"><b>Antigüedad de la deuda del contrato:</b> {AYUDA_TRAMOS}</div> : null}
        {medida === "part60" ? <div className="dash-nota">«Calor suave» no está disponible con la participación: es un porcentaje, y el calor suma pesos de las celdas vecinas, así que mezclaría porcentajes sin sentido. Esta medida solo se dibuja con la capa Celdas; al elegirla, Calor suave se apaga.</div> : null}
        {!ef.celdas && !ef.calor ? <div className="dash-nota">Ninguna capa está encendida: enciende Celdas o Calor suave para ver el mapa.</div> : null}
        {ef.calor && !ef.celdas ? <div className="dash-nota">Con solo Calor suave, pasa el cursor o haz clic sobre el mapa para ver la ventana de cada celda (contratos, saldo y los tres saldos).</div> : null}
        {datos && !datos.meta?.suficiente ? <div className="dash-estado">El filtro deja menos de 5 contratos: no se muestra el mapa.</div> : null}
        </div>
        <div ref={cont} className="cm-mapa" style={{ height: enPantalla ? (altoMapa ?? "60vh") : "50vh", minHeight: enPantalla ? 300 : 360, opacity: cargando ? 0.6 : 1 }} aria-label="Mapa de calor de cartera por celda" />
        <div ref={leyRef} className="cm-leyendas">
          {ef.celdas ? (
            <div className="cm-leyenda">
              {leyenda ? (<>
                <span>{fmtValor(leyenda.min)}</span>
                <div className="cm-leyenda-barra" style={{ background: leyenda.fondo }} role="img" aria-label={`Escala de color de las celdas de ${fmtValor(leyenda.min)} a ${fmtValor(leyenda.max)}`} />
                <span>{fmtValor(leyenda.max)}</span>
                <span>Celdas (escala por cuantiles de lo visible)</span>
              </>) : <span>Sin celdas que mostrar.</span>}
            </div>
          ) : null}
          {ef.calor ? (
            <div className="cm-leyenda cm-leyenda-calor">
              {leyenda ? (<>
                <span className="cm-leyenda-extremo">menos</span>
                <div className="cm-leyenda-calor-barra">
                  <div className="cm-leyenda-barra" style={{ background: DEGRADE_CALOR_CSS }} role="img" aria-label="Degradé del calor suave, de menos a más" />
                  <div className="cm-leyenda-cortes">
                    {[leyenda.min, ...leyenda.cortes, leyenda.max].map((v, i) => <span key={i}>{fmtValor(v)}</span>)}
                  </div>
                </div>
                <span className="cm-leyenda-extremo">más</span>
                <span>Calor suave: intensidad relativa, suavizada; debajo, los cortes por cuantiles de la medida ({medida === "deuda" ? "deuda total" : medida === "gt8" ? "más de 8 facturas" : "más de 60 facturas"}).</span>
              </>) : <span>Sin celdas que mostrar.</span>}
            </div>
          ) : null}
          {!ef.celdas && !ef.calor ? <div className="cm-leyenda"><span>Ninguna capa encendida.</span></div> : null}
        </div>
        {datos?.meta ? <div className="dash-nota">Celdas de {datos.meta.lado} m ({datos.meta.motivo}). Las celdas de menos de 5 contratos no se muestran.</div> : null}
        {c ? (
          <table className="dash-tabla">
            <caption>Conciliación de la medida elegida con la cartera del filtro</caption>
            <tbody>
              <tr><th>Total del filtro</th><td className="num">{pesosM(c.totalS)}</td><td className="num">{fmtEntero(c.totalN)} contratos</td></tr>
              <tr><th>Dibujada en el mapa</th><td className="num">{pesosM(c.dibujadaS)}</td><td className="num">{fmtEntero(c.dibujadaN)} contratos</td></tr>
              {c.desglose ? (<>
                <tr><th>Celdas de menos de 5 contratos</th><td className="num">{pesosM(c.menos5S)}</td><td className="num">{fmtEntero(c.menos5N ?? 0)}</td></tr>
                <tr><th>Sin coordenadas</th><td className="num">{pesosM(c.sinCoordS)}</td><td className="num">{fmtEntero(c.sinCoordN ?? 0)}</td></tr>
                <tr><th>Celdas ocultas por supresión complementaria</th><td className="num">{pesosM(c.anilloS)}</td><td className="num">{fmtEntero(c.anilloN ?? 0)}</td></tr>
              </>) : <tr><th>No dibujada (el desglose tiene grupos de menos de 5 contratos y no se publica)</th><td className="num">{pesosM(c.noDibujadaS)}</td><td className="num">{fmtEntero(c.noDibujadaN)}</td></tr>}
            </tbody>
          </table>
        ) : null}
        <div className="dash-nota">Fuente: {FUENTE}. Período: {periodo}.</div>
        <details><summary>ⓘ Cómo se calcula y qué protege</summary><div className="dash-nota">
          Cada contrato con saldo se ubica en una celda de 250 m (100 m al filtrar, si quedan suficientes celdas); solo se muestran agregados de celdas con 5 o más contratos.
          Las medidas con más de 8 o más de 60 facturas vencidas suman la cartera total de esos contratos. Los rangos de deuda son cuartiles del saldo por contrato de toda la ciudad en el período. La antigüedad de la deuda del contrato clasifica contratos por su número de facturas vencidas (0, 1 a 3, 4 a 8, 9 a 24, 25 a 60 y más de 60), no la edad de cada peso.
          Para que no se deduzcan grupos de menos de 5 contratos, algunos valores se ocultan (supresión complementaria) y el cuadro de conciliación solo se desglosa cuando cada parte es segura.
          <b>Límite conocido:</b> quien pudiera repetir consultas con filtros distintos podría restar resultados y aproximar grupos pequeños; por eso este mapa es de uso interno y el acceso está restringido.
        </div></details>
      </div>
    </div>
    </div>
  );
}
