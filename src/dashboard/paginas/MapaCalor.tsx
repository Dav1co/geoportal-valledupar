import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { biCache } from "../cacheBi";
import { irCuandoExista } from "../Plegable";
import { normalizarBanderas, useEstadoSesion } from "../memoriaSesion";
import {
  comoMapaCalorCarteraDim,
  comoMapaCalorCoberturaDim,
  comoMapaCalorDim,
  type MapaCalorCarteraDim,
  type MapaCalorCoberturaDim,
  type MapaCalorDim,
} from "../tipos";
import { etiquetaPeriodo, fmtDecimal, fmtEntero, fmtMillonesEnteros } from "../formato";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import {
  CAPAS, COLOR_SUPRIMIDA, LADO_M, MIN_CONTRATOS, capaDe, claseDe, clasesPorCuantiles, colorClase, conteoCapa, cuadrado, intervalos, nClases, nSuprimidas,
  pctCelda, sumaCapa, type CapaId,
} from "../mapaCalorComun";
import { COLORES_CALOR, DEGRADE_CALOR_CSS, intensidadBaseCalor, intensidadCalor, pesoCalor, pesosPorCuantil, radioCalor, type CapasMapa } from "../mapaCalorCapas";
import { usePantallaCompleta } from "../usePantallaCompleta";
import "../carteraMapa.css";

// Mapa de calor: contratos sin medidor, con observación y de consumo bajo (tablas bi.v_mapa_calor_dim y
// bi.v_mapa_calor_cobertura_dim, sql/42). Solo agregados por celda de 250 m: nunca coordenadas exactas, contratos ni direcciones.
// Los NULL de las columnas de capa son conteos suprimidos (1 a 4 contratos): se muestran como «menos de 5 contratos».

const MENOS_5 = "menos de 5 contratos";
const FUENTE = "bi.v_mapa_calor_dim y bi.v_mapa_calor_cobertura_dim (hechos.consumo_metodo, hechos.cartera_contrato; coordenadas de public.predios_comercial)";
const pct1 = (v: number | null) => (v == null ? "—" : `${fmtDecimal(v, 1)} %`);

const PARTES_DEFECTO: Record<string, boolean> = { resumen: true, cartera: true, mapa: true };
const PARTES = [
  { id: "resumen", titulo: "Resumen" }, { id: "cartera", titulo: "Cartera por grupo de mora" }, { id: "mapa", titulo: "Mapa" },
  { id: "tabla", titulo: "Tabla resumen del período" }, { id: "metodologia", titulo: "Metodología y fuentes" },
];

const Kpi = ({ eti, valor, sub }: { eti: string; valor: string; sub?: string }) => (
  <div className="dash-carta dash-kpi">
    <div className="dash-eti">{eti}</div>
    <div className="dash-valor num">{valor}</div>
    {sub ? <div className="dash-sub2">{sub}</div> : null}
  </div>
);
const Sub = ({ titulo, children }: { titulo: string; children: ReactNode }) => (
  <div className="dash-subparte"><h3>{titulo}</h3>{children}</div>
);
function Parte({ id, titulo, abierta, onCambio, children }: { id: string; titulo: string; abierta: boolean; onCambio: (abierta: boolean) => void; children: ReactNode }) {
  return (
    <div id={`mapc-${id}`} className="dash-fila"><div className="dash-carta">
      <details open={abierta} onToggle={(e) => onCambio((e.currentTarget as HTMLDetailsElement).open)}>
        <summary><b>{titulo}</b></summary>
        {abierta ? children : null}
      </details>
    </div></div>
  );
}
function Pie({ periodo, calculado, formula }: { periodo: string; calculado: string; formula: string }) {
  return (
    <>
      <div className="dash-nota">Fuente: {FUENTE}. Período: {periodo}. Calculado: {calculado}.</div>
      <details><summary>ⓘ Cómo se calcula</summary><div className="dash-nota">{formula}</div></details>
    </>
  );
}

type Datos = { celdas: MapaCalorDim[]; cob: MapaCalorCoberturaDim[]; car: MapaCalorCarteraDim[] };

// ---------- mapa (MapLibre con importación estática, como el mapa del geoportal) ----------
// Medida del color y del calor: el porcentaje (una razón: solo se dibuja como celdas) o los contratos de la capa (un conteo aditivo: también sirve para el calor suave).
type MedidaMapa = "porcentaje" | "conteo";
const MEDIDAS_MAPA: { id: MedidaMapa; nombre: string }[] = [
  { id: "porcentaje", nombre: "Porcentaje de la capa en la celda" },
  { id: "conteo", nombre: "Contratos de la capa" },
];

function MapaCeldas({ periodo, todas, celdas, capaId, cartera, medida, onMedida, capas, onCapas, controlesCompleta }: {
  periodo: string; todas: MapaCalorDim[]; celdas: MapaCalorDim[]; capaId: CapaId; cartera: boolean;
  medida: MedidaMapa; onMedida: (m: MedidaMapa) => void; capas: CapasMapa; onCapas: (c: CapasMapa) => void; controlesCompleta: ReactNode;
}) {
  const cont = useRef<HTMLDivElement>(null);
  const seccionRef = useRef<HTMLDivElement>(null);
  const topRef = useRef<HTMLDivElement>(null);
  const leyRef = useRef<HTMLDivElement>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mapaRef = useRef<any>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const popupRef = useRef<any>(null);
  const [lista, setLista] = useState(false);
  const [errMapa, setErrMapa] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const ramp = capaDe(capaId).ramp;
  // Pantalla completa de la sección del mapa (hook común con Cartera): el mapa y sus controles a la altura de la ventana.
  const { modo, enPantalla, altoMapa, alternar } = usePantallaCompleta({ seccion: seccionRef, cont, top: topRef, ley: leyRef, redimensionar: () => mapaRef.current?.resize(), reiniciar: intento });
  // Calor suave solo con la medida de conteos: con el porcentaje (una razón) solo existe Celdas.
  const ef: CapasMapa = medida === "porcentaje" ? { celdas: true, calor: false } : capas;

  // Valor que se pinta: el porcentaje o el conteo de contratos de la capa (null = suprimido: 1 a 4 contratos).
  const valorDe = (c: MapaCalorDim) => (medida === "conteo" ? conteoCapa(c, cartera) : pctCelda(c, cartera));
  const clases = useMemo(
    () => clasesPorCuantiles(celdas.map(valorDe).filter((p): p is number => p != null)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [celdas, cartera, medida],
  );

  useEffect(() => {
    let vivo = true;
    setErrMapa(null);
    if (!cont.current) return;
    try {
      const map = new maplibregl.Map({
        container: cont.current,
        center: CENTRO_VALLEDUPAR,
        zoom: 12,
        attributionControl: { compact: true },
        // Mismo mapa base de calles del geoportal, atenuado SOLO aquí (saturación y opacidad) para que se lean las celdas.
        style: {
          version: 8,
          sources: { base: FUENTE_BASE_CALLES },
          layers: [{ id: "base", type: "raster", source: "base", paint: { "raster-saturation": -0.6, "raster-opacity": 0.8 } }],
        },
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
      const popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false, maxWidth: "260px" });
      popupRef.current = popup;
      map.on("load", () => {
        // Calor suave (debajo): un punto por celda en su centro, peso por percentil del conteo; radio de 2,75 lados en metros. Sin bordes.
        map.addSource("calor", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
        map.addLayer({
          id: "calor", type: "heatmap", source: "calor", layout: { visibility: "none" },
          paint: { "heatmap-weight": ["get", "peso"], "heatmap-radius": radioCalor(LADO_M), "heatmap-intensity": intensidadCalor(1), "heatmap-color": ["interpolate", ["linear"], ["heatmap-density"], ...COLORES_CALOR], "heatmap-opacity": 0.78 } as never,
        });
        // Celdas (encima), SIN contorno: se quitó la capa de línea blanca.
        map.addSource("celdas", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
        map.addLayer({ id: "celdas-fill", type: "fill", source: "celdas", paint: { "fill-color": ["get", "color"], "fill-opacity": 0.78 } });
        const mostrar = (e: { features?: { properties?: Record<string, unknown> }[]; lngLat: { lng: number; lat: number } }) => {
          const p = e.features?.[0]?.properties;
          if (!p) return;
          const t = (v: unknown) => (Number(v) < 0 ? MENOS_5 : fmtEntero(Number(v)));
          const lineas = [
            `<b>${p.capaNombre}</b>`,
            `${p.conCartera ? "Contratos de la capa que se mantienen (fuera del rango de gestión drástica)" : "Contratos de la capa"}: ${t(p.cap)}`,
            `Contratos de la celda: ${fmtEntero(Number(p.base))}`,
            `Porcentaje: ${Number(p.pct) < 0 ? MENOS_5 : `${fmtDecimal(Number(p.pct), 1)} %`}`,
          ];
          popup.setLngLat(e.lngLat).setHTML(`<div style="font-size:12px;line-height:1.45">${lineas.join("<br/>")}</div>`).addTo(map);
        };
        map.on("mousemove", "celdas-fill", mostrar);
        map.on("click", "celdas-fill", mostrar);
        map.on("mouseleave", "celdas-fill", () => { popup.remove(); map.getCanvas().style.cursor = ""; });
        map.on("mouseenter", "celdas-fill", () => { map.getCanvas().style.cursor = "pointer"; });
        mapaRef.current = map;
        if (vivo) setLista(true);
      });
      map.on("error", (ev) => { if (vivo && !mapaRef.current) setErrMapa(ev.error?.message ?? "No se pudo crear el mapa"); });
    } catch (e) {
      setErrMapa((e as Error).message);
    }
    return () => {
      vivo = false;
      popupRef.current?.remove();
      mapaRef.current?.remove();
      mapaRef.current = null;
      setLista(false);
    };
  }, [intento]);

  // Datos de la capa y colores
  useEffect(() => {
    const map = mapaRef.current;
    if (!lista || !map) return;
    const nombre = capaDe(capaId).nombre;
    const features = celdas.map((c) => {
      const p = pctCelda(c, cartera);
      const v = conteoCapa(c, cartera);
      const val = medida === "conteo" ? v : p;
      return {
        type: "Feature" as const,
        properties: {
          color: val == null || !clases ? COLOR_SUPRIMIDA : colorClase(claseDe(val, clases), nClases(clases), ramp),
          capaNombre: nombre, base: c.contratos_base, cap: v == null ? -1 : v, pct: p == null ? -1 : p,
          conCartera: cartera, capCart: c.contratos_capa_cartera == null ? -1 : c.contratos_capa_cartera,
        },
        geometry: { type: "Polygon" as const, coordinates: [cuadrado(c.lon_centro, c.lat_centro)] },
      };
    });
    map.getSource("celdas")?.setData({ type: "FeatureCollection", features });
    // Calor suave: solo celdas con conteo publicado (las de 1 a 4 contratos, NULL, quedan fuera); peso por percentil del conteo; intensidad normalizada con los datos.
    const conteos = medida === "conteo" ? celdas.flatMap((c) => { const n = conteoCapa(c, cartera); return n == null ? [] : [{ c, n }]; }) : [];
    const pesos = pesosPorCuantil(conteos.map((x) => x.n));
    map.getSource("calor")?.setData({
      type: "FeatureCollection",
      features: conteos.map((x, i) => ({ type: "Feature" as const, geometry: { type: "Point" as const, coordinates: [x.c.lon_centro, x.c.lat_centro] }, properties: { peso: pesoCalor(pesos[i]) } })),
    });
    map.setPaintProperty("calor", "heatmap-intensity", intensidadCalor(intensidadBaseCalor(conteos.map((x, i) => ({ cx: x.c.celda_x, cy: x.c.celda_y, peso: pesoCalor(pesos[i]) })), LADO_M)));
  }, [lista, celdas, cartera, capaId, clases, ramp, medida]);

  // Capas independientes. Con solo Calor suave la capa de celdas queda INVISIBLE (opacidad 0) pero activa: el cursor y el clic siguen mostrando la ventana de la celda.
  // Con ambas, el calor va debajo y las celdas encima con transparencia. Sin ninguna, no hay capa que consultar.
  useEffect(() => {
    const map = mapaRef.current;
    if (!lista || !map) return;
    const algo = ef.celdas || ef.calor;
    map.setLayoutProperty("calor", "visibility", ef.calor ? "visible" : "none");
    map.setLayoutProperty("celdas-fill", "visibility", algo ? "visible" : "none");
    map.setPaintProperty("celdas-fill", "fill-opacity", ef.celdas ? (ef.calor ? 0.5 : 0.78) : 0);
  }, [lista, ef.celdas, ef.calor]);

  // Encuadre a las celdas del período (una vez por período, para no saltar al cambiar de capa o de interruptor)
  useEffect(() => {
    const map = mapaRef.current;
    if (!lista || !map || !todas.length) return;
    let w = 180, s = 90, e = -180, n = -90;
    for (const c of todas) { w = Math.min(w, c.lon_centro); e = Math.max(e, c.lon_centro); s = Math.min(s, c.lat_centro); n = Math.max(n, c.lat_centro); }
    map.fitBounds([[w - 0.002, s - 0.002], [e + 0.002, n + 0.002]], { padding: 24, duration: 0, maxZoom: 15 });
  }, [lista, periodo, todas]);

  const ints = clases ? intervalos(clases) : [];
  const grises = nSuprimidas(celdas, cartera);
  const avisoGris = cartera && celdas.length > 0 && grises / celdas.length > 0.5;
  const rango = (d: number, h: number) => medida === "conteo"
    ? (d === h ? fmtEntero(d) : `${fmtEntero(d)} a ${fmtEntero(h)}`)
    : (d === h ? `${fmtDecimal(d, 1)} %` : `${fmtDecimal(d, 1)} % a ${fmtDecimal(h, 1)} %`);
  const fmtV = (v: number) => (medida === "conteo" ? fmtEntero(v) : `${fmtDecimal(v, 1)} %`);
  const queMide = medida === "conteo"
    ? (cartera ? "contratos de la capa que se mantienen (sin más de 8 facturas vencidas)" : "contratos de la capa")
    : (cartera ? "contratos de la capa que se mantienen (sin más de 8 facturas vencidas)" : "contratos de la capa") + " ÷ contratos de la celda";
  return (
    <div ref={seccionRef} className={`cm-seccion${enPantalla ? " cm-completa" : ""}${modo === "fijo" ? " cm-fijo" : ""}`}>
      <div className="cm-top" ref={topRef}>
        <div className="cm-encabezado">
          <b className="cm-titulo">Mapa de calor: contratos por celda de 250 m</b>
          <span className="cm-ayuda">Esc para salir</span>
          <button type="button" className="dash-boton cm-boton-fs" onClick={alternar} aria-pressed={enPantalla}>
            {enPantalla ? "Salir de pantalla completa" : "Pantalla completa"}
          </button>
        </div>
        <div className="cm-controles">
          <span className="cm-solo-completa">{controlesCompleta}</span>
          <label>Medida <select value={medida} onChange={(e) => onMedida(e.target.value as MedidaMapa)}>{MEDIDAS_MAPA.map((m) => <option key={m.id} value={m.id}>{m.nombre}</option>)}</select></label>
          <fieldset className="cm-capas">
            <legend>Capas</legend>
            <label><input type="checkbox" checked={ef.celdas} disabled={medida === "porcentaje"} onChange={(e) => onCapas({ ...capas, celdas: e.target.checked })} /> Celdas</label>
            <label title={medida === "porcentaje" ? "El porcentaje es una razón: solo se dibuja con Celdas" : undefined}>
              <input type="checkbox" checked={ef.calor} disabled={medida === "porcentaje"} onChange={(e) => onCapas({ ...capas, calor: e.target.checked })} /> Calor suave
            </label>
          </fieldset>
        </div>
        {medida === "porcentaje" ? <div className="dash-nota">«Calor suave» solo está disponible con la medida «Contratos de la capa»: el porcentaje es una razón y el calor suma el peso de las celdas vecinas, así que mezclaría porcentajes sin sentido. Con el porcentaje solo se dibuja la capa Celdas.</div> : null}
        {!ef.celdas && !ef.calor ? <div className="dash-nota">Ninguna capa está encendida: enciende Celdas o Calor suave para ver el mapa.</div> : null}
        {ef.calor && !ef.celdas ? <div className="dash-nota">Con solo Calor suave, pasa el cursor o haz clic sobre el mapa para ver la ventana de cada celda. Las celdas con «{MENOS_5}» no entran en el calor.</div> : null}
      </div>
      {errMapa ? (
        <div className="dash-estado"><p>No se pudo cargar el mapa: {errMapa}</p><button className="dash-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button></div>
      ) : (
        <div ref={cont} className="cm-mapa" style={{ height: enPantalla ? (altoMapa ?? "60vh") : "clamp(320px, 62vh, 520px)", minHeight: enPantalla ? 300 : undefined }} aria-label="Mapa de calor de contratos por celda de 250 m" />
      )}
      <div ref={leyRef} className="cm-leyendas">
        {ef.celdas ? (
          <div className="dash-leyenda">
            {ints.map((r, i) => (
              <span key={i}><i style={{ background: colorClase(i, ints.length, ramp) }} /> {rango(r.desde, r.hasta)}</span>
            ))}
            <span><i style={{ background: COLOR_SUPRIMIDA }} /> {MENOS_5}</span>
          </div>
        ) : null}
        {ef.calor ? (
          <div className="cm-leyenda cm-leyenda-calor">
            {clases ? (<>
              <span className="cm-leyenda-extremo">menos</span>
              <div className="cm-leyenda-calor-barra">
                <div className="cm-leyenda-barra" style={{ background: DEGRADE_CALOR_CSS }} role="img" aria-label="Degradé del calor suave, de menos a más" />
                <div className="cm-leyenda-cortes">{[clases.min, ...clases.cortes, clases.max].map((v, i) => <span key={i}>{fmtV(v)}</span>)}</div>
              </div>
              <span className="cm-leyenda-extremo">más</span>
              <span>Calor suave: intensidad relativa, suavizada; debajo, los cortes por cuantiles de los contratos de la capa por celda.</span>
            </>) : <span>Sin celdas que mostrar.</span>}
          </div>
        ) : null}
      </div>
      {avisoGris ? (
        <div className="dash-nota">
          <b>Con este filtro la mayoría de las celdas tiene entre 1 y 4 contratos, que no se publican individualmente; el mapa subestima la concentración real.</b>{" "}
          En gris: {fmtEntero(grises)} de {fmtEntero(celdas.length)} celdas publicadas ({pct1((grises / celdas.length) * 100)}).
        </div>
      ) : null}
      <div className="dash-nota">
        Cada cuadrado es una celda de 250 m. Color: {queMide},
        en clases por cuantiles de las celdas de la capa en el período (las clases repetidas se funden; las celdas con 0 contratos en la capa van en el tono más claro).
        Las celdas con menos de {MIN_CONTRATOS} contratos en total no se dibujan. Con «Calor suave», cada celda con conteo publicado aporta un peso por percentil de sus contratos
        de la capa; las celdas con «{MENOS_5}» no entran.
      </div>
    </div>
  );
}

// ---------- cartera por grupo de mora (bi.v_mapa_calor_cartera_dim): todos los contratos de la capa, sin coordenadas ni celdas ----------
const FUENTE_CAR = "bi.v_mapa_calor_cartera_dim (hechos.consumo_metodo y hechos.cartera_contrato)";
const fechaDe = (xs: { calculado_en: string }[]) => { const f = xs.map((x) => x.calculado_en).filter(Boolean).sort().pop(); return f ? new Date(f).toLocaleString("es-CO") : "—"; };
const pesosM = (v: number | null) => (v == null ? MENOS_5 : fmtMillonesEnteros(v));
const GRUPOS_CAR = [
  { id: "mora_profunda", titulo: "Más de 8 facturas vencidas (rango de gestión drástica)" },
  { id: "hasta_8", titulo: "8 facturas vencidas o menos" },
];
function CarteraGrupos({ car, periodoTxt, calculado }: { car: MapaCalorCarteraDim[]; periodoTxt: string; calculado: string }) {
  if (!car.length) return <div className="dash-estado">No hay cartera por grupo de mora calculada para este período.</div>;
  const fila = (ambito: string, grupo: string) => car.find((x) => x.ambito === ambito && x.grupo === grupo);
  // Totales del ámbito (solo si los dos grupos están publicados; si uno viene NULL, no se pueden calcular los porcentajes)
  const total = (ambito: string) => {
    const a = fila(ambito, "mora_profunda"), b = fila(ambito, "hasta_8");
    if (!a || !b || a.contratos == null || b.contratos == null || a.valor_cartera == null || b.valor_cartera == null) return null;
    return { contratos: a.contratos + b.contratos, valor: a.valor_cartera + b.valor_cartera };
  };
  const tCapa = total("capa"), tUni = total("universo");
  const pct = (v: number | null, t: number | undefined) => (v == null || !t ? "—" : `${fmtDecimal((v / t) * 100, 1)} %`);
  const profunda = fila("capa", "mora_profunda");
  const frase = profunda && tCapa && profunda.contratos != null && profunda.valor_cartera != null && tCapa.valor > 0
    ? `El ${fmtDecimal((profunda.contratos / tCapa.contratos) * 100, 1)} % de los contratos de la capa concentra el ${fmtDecimal((profunda.valor_cartera / tCapa.valor) * 100, 1)} % de su cartera.`
    : null;
  return (
    <>
      {frase ? <div className="dash-nota"><b>{frase}</b></div> : null}
      <div className="dash-kpis">
        {GRUPOS_CAR.map((g) => {
          const c = fila("capa", g.id), u = fila("universo", g.id);
          const fin = (x: MapaCalorCarteraDim | undefined) => (x == null || x.valor_financiado == null || x.valor_cartera == null ? MENOS_5 : `${fmtMillonesEnteros(x.valor_financiado)} (${pct(x.valor_financiado, x.valor_cartera)})`);
          return (
            <div key={g.id} className="dash-carta dash-kpi">
              <div className="dash-eti">{g.titulo}</div>
              <div className="dash-valor num">{c?.contratos == null ? MENOS_5 : `${fmtEntero(c.contratos)} contratos`}</div>
              <div className="dash-sub2">{pct(c?.contratos ?? null, tCapa?.contratos)} de los contratos de la capa</div>
              <div className="dash-sub2">Cartera: {pesosM(c?.valor_cartera ?? null)} · {pct(c?.valor_cartera ?? null, tCapa?.valor)} de la cartera de la capa</div>
              <div className="dash-sub2">de ello, financiado: {fin(c)}</div>
              <div className="dash-sub2"><i>En todo el universo de la capa: {u?.contratos == null ? MENOS_5 : `${fmtEntero(u.contratos)} contratos`} ({pct(u?.contratos ?? null, tUni?.contratos)} de los contratos)</i></div>
              <div className="dash-sub2"><i>Cartera del universo: {pesosM(u?.valor_cartera ?? null)} ({pct(u?.valor_cartera ?? null, tUni?.valor)} de la cartera); de ello, financiado: {fin(u)}</i></div>
            </div>
          );
        })}
      </div>
      <div className="dash-nota"><b>Es una descripción de la cartera de la capa; no indica causa.</b></div>
      <div className="dash-nota">El grupo de 8 facturas vencidas o menos incluye contratos sin deuda; su cartera es en gran parte financiada (convenios).</div>
      <div className="dash-nota">Un valor «{MENOS_5}» indica un grupo con 1 a 4 contratos, que no se publica.</div>
      <div className="dash-nota">Fuente: {FUENTE_CAR}. Período: {periodoTxt}. Calculado: {calculado}.</div>
      <details><summary>ⓘ Cómo se calcula</summary><div className="dash-nota">
        Cartera = total_cartera = saldo_pendiente + saldo_financiado, sumada entre los productos (filas) de cada contrato; los vacíos cuentan 0 y no incluye saldos a favor.
        Grupos: máximo de facturas vencidas del contrato en el período mayor que 8 (rango de gestión drástica), o con 8 facturas vencidas o menos, o sin registro de cartera. «De ello, financiado» = saldo_financiado.
        Capa y universo tienen la misma definición del mapa (la capa «Sin medidor o con observación» se mide sobre todos los contratos del período; «Consumo bajo», sobre los residenciales con medidor y lectura real).
        Se calcula sobre todos los contratos, sin depender de coordenadas ni de celdas del mapa. Los porcentajes son sobre el total de la capa o de su universo.
        2.343 contratos con cartera (cerca del 0,1 % de la cartera) quedan fuera del universo de consumo y no aparecen aquí. La fuente no desglosa si saldo_pendiente incluye intereses u otros cargos.
      </div></details>
    </>
  );
}

// ---------- sección ----------
export function MapaCalor({ periodo }: { periodo: string }) {
  const [datos, setDatos] = useState<Datos | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const [capaId, setCapaId] = useState<CapaId>("sin_medidor_obs");
  const [cartera, setCartera] = useState(false);
  const [medidaMapa, setMedidaMapa] = useState<MedidaMapa>("porcentaje");           // por defecto, la medida de siempre
  const [capasMapa, setCapasMapa] = useState<CapasMapa>({ celdas: true, calor: false });   // por defecto solo Celdas
  function elegirMedida(m: MedidaMapa) {
    setMedidaMapa(m);
    if (m === "porcentaje") setCapasMapa({ celdas: true, calor: false });   // el porcentaje solo se dibuja como celdas
  }
  const [abiertas, setAbiertas] = useEstadoSesion<Record<string, boolean>>(`${periodo}.mapa.partes`, PARTES_DEFECTO, normalizarBanderas(PARTES.map((x) => x.id), PARTES_DEFECTO));
  function cambiar(id: string, abierta: boolean) { setAbiertas((a) => (a[id] === abierta ? a : { ...a, [id]: abierta })); }
  function abrir(id: string) {
    cambiar(id, true);
    irCuandoExista(`mapc-${id}`, true);
  }

  useEffect(() => {
    let vivo = true;
    setDatos(null);
    setError(null);
    Promise.all([biCache("v_mapa_calor_dim", { periodo }), biCache("v_mapa_calor_cobertura_dim", { periodo }), biCache("v_mapa_calor_cartera_dim", { periodo })])
      .then(([m, c, k]) => {
        if (vivo) setDatos({ celdas: (m.datos ?? []).map(comoMapaCalorDim), cob: (c.datos ?? []).map(comoMapaCalorCoberturaDim), car: (k.datos ?? []).map(comoMapaCalorCarteraDim) });
      })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
  }, [periodo, intento]);

  const titulo = "Mapa de calor: contratos sin medidor, con observación y de consumo bajo";
  const celdasCapa = useMemo(() => (datos?.celdas ?? []).filter((c) => c.capa === capaId), [datos, capaId]);

  if (error) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo}</h3>
        <div className="dash-estado"><p>No se pudo cargar esta sección: {error}</p><button className="dash-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button></div>
      </div></div>
    );
  }
  if (!datos) return <div className="dash-fila"><div className="dash-carta"><h3>{titulo}</h3><div className="dash-estado">Cargando…</div></div></div>;

  if (!datos.celdas.length || !datos.cob.length) {
    const motivo = periodo === "202606" ? "202606 no existe en la fuente de consumo (consumo_metodo), así que no hay mapa para ese mes."
      : periodo < "202602" ? "El mapa se calcula desde 202602: antes de esa fecha no se cargaron consumo y cartera por contrato."
      : `No hay mapa calculado para ${etiquetaPeriodo(periodo)}: se calcula al cargar consumo_metodo y cartera_contrato del período.`;
    return (
      <div className="dash-fila"><div className="dash-carta">
        <h3>{titulo}</h3>
        <div className="dash-estado"><p>{motivo}</p><p>Hay datos de 202602 a 202609 (sin 202606).</p></div>
      </div></div>
    );
  }

  const cob = datos.cob.find((c) => c.capa === capaId);
  const cap = capaDe(capaId);
  const calculado = (() => { const f = datos.celdas.map((x) => x.calculado_en).filter(Boolean).sort().pop(); return f ? new Date(f).toLocaleString("es-CO") : "—"; })();
  const periodoTxt = etiquetaPeriodo(periodo);
  const suma = sumaCapa(celdasCapa, cartera);
  const supCapa = nSuprimidas(celdasCapa, cartera);

  // La capa y el interruptor de cartera viven arriba de la tarjeta; en pantalla completa de la sección del mapa se repiten, con el mismo estado.
  const controlesCompleta = (
    <>
      <label>Capa <select value={capaId} onChange={(e) => setCapaId(e.target.value as CapaId)}>{CAPAS.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}</select></label>
      <label><input type="checkbox" checked={cartera} onChange={(e) => setCartera(e.target.checked)} /> Excluir contratos con más de 8 facturas vencidas</label>
    </>
  );

  return (
    <div className="dash-fila"><div className="dash-carta">
      <h3>{titulo} — {periodoTxt}</h3>
      <div className="dash-nota">
        Dónde se concentran los contratos sin medidor registrado, con observación de lectura y de consumo bajo, en celdas de 250 m.
        Solo agregados: nunca coordenadas exactas, contratos ni direcciones.
      </div>
      <div className="dash-filtros-bloque">
        <label>
          Capa
          <select value={capaId} onChange={(e) => setCapaId(e.target.value as CapaId)}>
            {CAPAS.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}
          </select>
        </label>
        <label>
          <input type="checkbox" checked={cartera} onChange={(e) => setCartera(e.target.checked)} /> Excluir contratos con más de 8 facturas vencidas
        </label>
      </div>
      <nav className="dash-indice" aria-label="Contenido de la sección">
        <b>Contenido:</b>
        {PARTES.map((x) => <button key={x.id} className="dash-boton-indice" onClick={() => abrir(x.id)}>{x.titulo}</button>)}
      </nav>

      <Parte id="resumen" titulo={`Resumen — ${cap.nombre}`} abierta={!!abiertas.resumen} onCambio={(o) => cambiar("resumen", o)}>
        <div className="dash-kpis">
          <Kpi eti={cartera ? "Contratos en la capa que se mantienen (fuera del rango de gestión drástica)" : "Contratos en la capa"} valor={fmtEntero(suma)}
            sub={`suma de ${fmtEntero(celdasCapa.length)} celdas publicadas${supCapa ? `; ${fmtEntero(supCapa)} celdas con «${MENOS_5}» no suman` : ""}`} />
          <Kpi eti="Porcentaje del universo de la capa" valor={pct1(cob && cob.contratos_universo ? (suma / cob.contratos_universo) * 100 : null)}
            sub={`universo: ${fmtEntero(cob?.contratos_universo ?? null)} contratos`} />
          <Kpi eti="Cobertura de coordenadas" valor={pct1(cob && cob.contratos_universo ? (cob.contratos_con_coordenadas / cob.contratos_universo) * 100 : null)}
            sub={`${fmtEntero(cob?.contratos_con_coordenadas ?? null)} con coordenadas; ${fmtEntero(cob?.contratos_sin_coordenadas ?? null)} sin ellas`} />
          <Kpi eti="Contratos en celdas suprimidas" valor={fmtEntero(cob?.contratos_en_celdas_suprimidas ?? null)}
            sub={`celdas con menos de ${MIN_CONTRATOS} contratos: no se dibujan`} />
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Cartera por grupo de mora</div>
            <div className="dash-sub2">Contratos con más de 8 facturas vencidas y su cartera, calculados sobre todos los contratos de la capa.</div>
            <button className="dash-boton-indice" onClick={() => abrir("cartera")}>Ver cartera por grupo de mora</button>
          </div>
        </div>
        <div className="dash-nota"><b>El filtro excluye los contratos en el rango de gestión drástica, que con frecuencia corresponden a predios cortados o retirados; es una descripción, no indica causa.</b></div>
        <Pie periodo={periodoTxt} calculado={calculado}
          formula={`Contratos en la capa = suma de contratos_capa (con el interruptor, de contratos_capa_cartera: los que se mantienen) de las celdas publicadas; los conteos suprimidos (1 a 4 contratos) no se suman, así que la cifra es un mínimo. Porcentaje del universo = esa suma ÷ contratos del universo de la capa. Cobertura = contratos con coordenadas ÷ universo. Los contratos en el rango de gestión drástica (más de 8 facturas vencidas) y su cartera se calculan sobre todos los contratos de la capa, no sobre las celdas, en la parte «Cartera por grupo de mora».`} />
      </Parte>

      <Parte id="cartera" titulo={`Cartera de la capa por grupo de mora — ${cap.nombre}`} abierta={!!abiertas.cartera} onCambio={(o) => cambiar("cartera", o)}>
        <CarteraGrupos car={datos.car.filter((x) => x.capa === capaId)} periodoTxt={periodoTxt} calculado={fechaDe(datos.car)} />
      </Parte>

      <Parte id="mapa" titulo="Mapa" abierta={!!abiertas.mapa} onCambio={(o) => cambiar("mapa", o)}>
        <MapaCeldas periodo={periodo} todas={datos.celdas} celdas={celdasCapa} capaId={capaId} cartera={cartera} medida={medidaMapa} onMedida={elegirMedida} capas={capasMapa} onCapas={setCapasMapa} controlesCompleta={controlesCompleta} />
        <Pie periodo={periodoTxt} calculado={calculado}
          formula="Cada celda es un cuadrado de 250 m centrado en el punto publicado (±125 m). Porcentaje = contratos de la capa ÷ contratos de la celda (con el interruptor, solo los que se mantienen, es decir, sin más de 8 facturas vencidas, ÷ contratos de la celda). Cinco clases por cuantiles de las celdas de la capa en el período, con un solo tono por capa. Gris: conteo suprimido (menos de 5 contratos). Al pasar el cursor o tocar una celda se ven sus conteos. Los conteos de 1 a 4 contratos se suprimen en cada columna; restando una columna de otra puede deducirse un conteo pequeño dentro de una celda de 5 o más contratos, sin identificar contratos." />
      </Parte>

      <Parte id="tabla" titulo="Tabla resumen del período" abierta={!!abiertas.tabla} onCambio={(o) => cambiar("tabla", o)}>
        <div className="dash-tabla-scroll">
          <table className="dash-tabla num">
            <thead><tr><th>Capa</th><th>Universo</th><th>Con coordenadas</th><th>En celdas publicadas</th><th>En celdas suprimidas</th><th>Celdas publicadas</th><th>Contratos en la capa</th><th>Que se mantienen (fuera del rango de gestión drástica)</th></tr></thead>
            <tbody>
              {CAPAS.map((c) => {
                const cb = datos.cob.find((x) => x.capa === c.id);
                const cs = datos.celdas.filter((x) => x.capa === c.id);
                return (
                  <tr key={c.id}><td>{c.nombre}</td><td className="num">{fmtEntero(cb?.contratos_universo ?? null)}</td>
                    <td className="num">{fmtEntero(cb?.contratos_con_coordenadas ?? null)}</td>
                    <td className="num">{fmtEntero(cb?.contratos_en_celdas_publicadas ?? null)}</td>
                    <td className="num">{fmtEntero(cb?.contratos_en_celdas_suprimidas ?? null)}</td>
                    <td className="num">{fmtEntero(cs.length)}</td>
                    <td className="num">{fmtEntero(sumaCapa(cs, false))}</td>
                    <td className="num">{fmtEntero(sumaCapa(cs, true))}</td></tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="dash-nota">«Contratos en la capa» suma solo las celdas con conteo publicado; los conteos de 1 a 4 contratos aparecen como «{MENOS_5}» en el mapa y no suman.</div>
        <Pie periodo={periodoTxt} calculado={calculado}
          formula="Universo, con coordenadas, en celdas publicadas y en celdas suprimidas vienen de la tabla de cobertura (universo = con coordenadas + sin coordenadas = publicadas + suprimidas + sin coordenadas). Contratos en la capa = suma de las celdas publicadas con conteo conocido, sin y con el interruptor (los que se mantienen: sin más de 8 facturas vencidas o sin registro de cartera)." />
      </Parte>

      <Parte id="metodologia" titulo="Metodología y fuentes" abierta={!!abiertas.metodologia} onCambio={(o) => cambiar("metodologia", o)}>
        <Sub titulo="Capas">
          <ul className="dash-nota">
            <li><b>Sin medidor o con observación:</b> contrato sin medidor registrado, o con una observación de lectura distinta de la normal. No cuentan la observación vacía ni los códigos 99 (lectura normal) y 30, 10, 3 y 4 (conexión suspendida, cortada, predio demolido o lote). Códigos que sí cuentan: 1, 2, 5, 6, 7, 8, 11, 12, 13, 17, 21 y 22. Universo: todos los contratos del período.</li>
            <li><b>Consumo bajo (5 m³ o menos):</b> contratos residenciales con medidor y lectura real (observación 99 y función CALCCODL) con consumo cobrado de 0 a 5 m³, ceros incluidos. Universo: los residenciales con lectura real, con cualquier consumo.</li>
            <li><b>Cartera por grupo de mora:</b> se calcula sobre todos los contratos de la capa y de su universo (no sobre las celdas): contratos y total_cartera (saldo_pendiente + saldo_financiado) sumado entre los productos de cada contrato, separados en más de 8 facturas vencidas (rango de gestión drástica) y 8 facturas vencidas o menos (o sin registro). No incluye saldos a favor.</li>
            <li><b>Interruptor de cartera:</b> excluye los contratos en el rango de gestión drástica, es decir, con más de 8 facturas vencidas (máximo de facturas vencidas del contrato en el período en hechos.cartera_contrato). Se mantienen los de 0 a 8 facturas vencidas y los que no tienen registro de cartera en el período. Se asume una factura por mes, así que 8 facturas equivalen a 8 meses de deuda.</li>
          </ul>
          <div className="dash-nota"><b>Un consumo cero puede ser un predio desocupado, un corte o un medidor detenido:</b> el mapa no distingue entre ellos.</div>
        </Sub>
        <Sub titulo="Celdas y supresión">
          <div className="dash-nota">
            Cuadrícula de 250 m en EPSG:3116 (MAGNA-SIRGAS / Colombia Bogotá), con el mismo origen en todos los períodos. Solo se publican las celdas con {MIN_CONTRATOS} o más contratos de la base de la capa;
            dentro de una celda publicada, un conteo de 1 a 4 contratos se oculta («{MENOS_5}») y el cero se conserva. Los contratos de celdas no publicadas se cuentan en la cobertura, no en el mapa. Los conteos de 1 a 4 contratos se suprimen en cada columna; restando una columna de otra puede deducirse un conteo pequeño dentro de una celda de 5 o más contratos, sin identificar contratos.
          </div>
        </Sub>
        <Sub titulo="Universos distintos por capa">
          <div className="dash-nota">
            La primera capa se mide sobre todos los contratos del período; la segunda, solo sobre los residenciales con medidor y lectura real. Los porcentajes de una y otra capa no son comparables entre sí.
          </div>
        </Sub>
        <Sub titulo="Coordenadas y cobertura">
          <div className="dash-nota">
            La ubicación sale de public.predios_comercial, unida por contrato; si un contrato tiene varios predios se usa uno solo. La cobertura es el porcentaje del universo de la capa con coordenadas.
            Las coordenadas no se recalculan solas: si cambian, el mapa se recalcula a mano.
          </div>
        </Sub>
        <Sub titulo="Límites">
          <ul className="dash-nota">
            <li>Asociación, no causalidad.</li>
            <li>La ubicación es la del predio, no necesariamente la del medidor o la de la persona.</li>
            <li>Los contratos sin coordenadas no se mapean.</li>
            <li>«Contratos en la capa» es un mínimo: no incluye los conteos suprimidos.</li>
          </ul>
        </Sub>
        <Pie periodo={periodoTxt} calculado={calculado}
          formula="Las tablas se calculan en la base a partir de hechos.consumo_metodo, hechos.cartera_contrato y public.predios_comercial. El navegador solo recibe conteos por celda; no recibe contratos, direcciones ni coordenadas individuales." />
      </Parte>
    </div></div>
  );
}
