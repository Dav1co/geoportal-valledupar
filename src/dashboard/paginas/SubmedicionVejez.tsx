import { useEffect, useMemo, useState, type ReactNode } from "react";
import { biCache } from "../cacheBi";
import {
  comoSubmedicionCicloDim,
  comoSubmedicionRangoDim,
  comoSubmedicionRefDim,
  type Ipuf,
  type SubmedicionRangoDim,
  type SubmedicionRefDim,
} from "../tipos";
import {
  etiquetaCiclo,
  etiquetaCorta,
  etiquetaPeriodo,
  fmtDecimal,
  fmtEntero,
  fmtMillones,
  numeroCiclo,
} from "../formato";
import { BarrasHorizontales, LineasPorcentaje, TablaPlegable } from "../graficas";
import { irCuandoExista } from "../Plegable";
import { normalizarBanderas, useEstadoSesion } from "../memoriaSesion";
import { PanelFiltros, TODOS } from "../PanelFiltros";
import { filtrosCicloUsoEstrato } from "../lecturaComun";

// Submedición por vejez del medidor (tablas bi.v_submedicion_ref_dim, _ciclo_dim y _rango_dim, sql/39).
// Es una ESTIMACIÓN, no un valor exacto: compara el consumo de los medidores de 3 años o más con la media de los
// medidores nuevos (menos de 3 años) del mismo estrato. Solo residencial; solo agregados (mínimo 5 por celda).
// La pérdida atribuible = suma, sobre los contratos de vejez, de (referencia − consumo). La bruta es un techo teórico.

const MIN_CELDA = 5;
const FUENTE_REF = "bi.v_submedicion_ref_dim (hechos.consumo_metodo; tarifa de hechos.facturacion_contratos)";
const BANDAS = ["0-3", "3-5", "5-10", "10-15", ">15 (fecha real)", ">15 (1986-01-01)", "Sin fecha"];
const VEJEZ = ["3-5", "5-10", "10-15", ">15 (fecha real)", ">15 (1986-01-01)"];
const CINCO_MAS = ["5-10", "10-15", ">15 (fecha real)", ">15 (1986-01-01)"];
const DIEZ_MAS = ["10-15", ">15 (fecha real)", ">15 (1986-01-01)"];
const RANGOS = ["1-5", "6-10", "11-15", "16-20", "21-30", "31-40", "41-60", "61-100"];
const OTROS = "Otros (menos de 5 contratos)";
const COLORES = ["#0A2540", "#0E7C86", "#C98A2D", "#8FB4CE", "#7B5EA7", "#C0392B"];
const etiquetaBanda = (b: string) =>
  ["0-3", "3-5", "5-10", "10-15"].includes(b) ? `${b} años`
  : b === ">15 (fecha real)" ? "Más de 15 años (fecha real)"
  : b === ">15 (1986-01-01)" ? "Más de 15 años (fecha 1986-01-01)"
  : b;
const nombreEstrato = (s: string) => s.replace(/^ESTRATO\s+/i, "Estrato ");
const pct1 = (v: number | null) => (v == null ? "—" : `${fmtDecimal(v, 1)} %`);
const m3 = (v: number | null) => (v == null ? "—" : fmtEntero(v));
const div = (a: number, b: number) => (b > 0 ? a / b : null);

// ---------- carga por vista, con error y reintento (guardada en biCache) ----------
type Estado<T> = { datos: T[] | null; error: string | null; recargar: () => void };
function useVista<T>(vista: string, convertir: (r: Record<string, unknown>) => T, activo = true): Estado<T> {
  const [datos, setDatos] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    if (!activo) return;
    let vivo = true;
    setDatos(null);
    setError(null);
    biCache(vista)
      .then((r) => { if (vivo) setDatos((r.datos ?? []).map(convertir)); })
      .catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, activo, intento]);
  return { datos, error, recargar: () => setIntento((i) => i + 1) };
}

// ---------- agregados por banda (estrato × banda de la tabla ref) ----------
type Banda = {
  contratos: number; medidor: number; prom: number; cero: number; sobre: number; m3: number;
  bajo: number; bruta: number; exceso: number; tarifa: number | null;
};
const bandaVacia = (): Banda => ({ contratos: 0, medidor: 0, prom: 0, cero: 0, sobre: 0, m3: 0, bajo: 0, bruta: 0, exceso: 0, tarifa: null });
function porBanda(filas: SubmedicionRefDim[]): Map<string, Banda> {
  const m = new Map<string, Banda>();
  for (const x of filas) {
    const b = m.get(x.banda_antig) ?? bandaVacia();
    b.contratos += x.contratos; b.medidor += x.contratos_medidor; b.prom += x.contratos_promedio;
    b.cero += x.contratos_cero; b.sobre += x.contratos_sobre_max; b.m3 += x.m3_consumo ?? 0;
    b.bajo += x.contratos_bajo_ref ?? 0; b.bruta += x.m3_perdidos_bruta ?? 0; b.exceso += x.m3_exceso ?? 0;
    b.tarifa = x.tarifa_m3 ?? b.tarifa;
    m.set(x.banda_antig, b);
  }
  return m;
}
const neta = (b: Banda | undefined) => (b ? b.bruta - b.exceso : 0);
const sumaNeta = (m: Map<string, Banda>, bandas: string[]) => bandas.reduce((s, k) => s + neta(m.get(k)), 0);
const sumaContratos = (m: Map<string, Banda>, bandas: string[]) => bandas.reduce((s, k) => s + (m.get(k)?.contratos ?? 0), 0);
const tarifaDe = (filas: SubmedicionRefDim[]) => filas.find((x) => x.tarifa_m3 != null)?.tarifa_m3 ?? null;
const pesosDe = (v: number, t: number | null) => (t == null ? null : v * t);
const fechaCalculo = (xs: { calculado_en: string }[]) => {
  const f = xs.map((x) => x.calculado_en).filter(Boolean).sort().pop();
  return f ? new Date(f).toLocaleString("es-CO") : "—";
};

function Pie({ fuente, periodo, calculado, formula }: { fuente: string; periodo: string; calculado: string; formula: string }) {
  return (
    <>
      <div className="dash-nota">Fuente: {fuente}. Período: {periodo}. Calculado: {calculado}. Estimación.</div>
      <details><summary>ⓘ Cómo se calcula</summary><div className="dash-nota">{formula}</div></details>
    </>
  );
}
const Kpi = ({ eti, valor, sub }: { eti: string; valor: string; sub?: string }) => (
  <div className="dash-carta dash-kpi">
    <div className="dash-eti">{eti}</div>
    <div className="dash-valor num">{valor}</div>
    {sub ? <div className="dash-sub2">{sub}</div> : null}
  </div>
);
const Carta = ({ titulo, children }: { titulo: string; children: ReactNode }) => (
  <div className="dash-fila"><div className="dash-carta"><h3>{titulo}</h3>{children}</div></div>
);
// Parte colapsable de la sección (estado de colapso solo en memoria; el índice abre y desplaza).
const PARTES_DEFECTO: Record<string, boolean> = { resumen: true, vejez: true, metodologia: true };
const PARTES = [
  { id: "resumen", titulo: "Resumen" }, { id: "vejez", titulo: "Distribución por vejez" }, { id: "estrato", titulo: "Por estrato" },
  { id: "ciclo", titulo: "Por ciclo" }, { id: "rangos", titulo: "Rangos de consumo" }, { id: "cascada", titulo: "Cascada y serie" },
  { id: "sesgo", titulo: "Sesgo y conciliación" }, { id: "simulacion", titulo: "Simulación" }, { id: "metodologia", titulo: "Metodología" },
];
const Sub = ({ titulo, children }: { titulo: string; children: ReactNode }) => (
  <div className="dash-subparte"><h3>{titulo}</h3>{children}</div>
);
function Parte({ id, titulo, abierta, onCambio, children }: { id: string; titulo: string; abierta: boolean; onCambio: (abierta: boolean) => void; children: ReactNode }) {
  return (
    <div id={`subm-${id}`} className="dash-fila"><div className="dash-carta">
      <details open={abierta} onToggle={(e) => onCambio((e.currentTarget as HTMLDetailsElement).open)}>
        <summary><b>{titulo}</b></summary>
        {abierta ? children : null}
      </details>
    </div></div>
  );
}
function Reintento({ titulo, e }: { titulo: string; e: Estado<unknown> }) {
  if (e.error) {
    return (
      <Carta titulo={titulo}>
        <div className="dash-estado">
          <p>No se pudo cargar esta sección: {e.error}</p>
          <button className="dash-boton" onClick={e.recargar}>Reintentar</button>
        </div>
      </Carta>
    );
  }
  return <Carta titulo={titulo}><div className="dash-estado">Cargando…</div></Carta>;
}

// Número escrito por el usuario (acepta «250.000», «250000» y «1.5»/«1,5»). Vacío o inválido → null.
function leerNumero(t: string): number | null {
  const s = t.trim().replace(/\s/g, "");
  if (!s) return null;
  const limpio = s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : /^\d{1,3}(\.\d{3})+$/.test(s) ? s.replace(/\./g, "") : s;
  const v = Number(limpio);
  return Number.isFinite(v) && v >= 0 ? v : null;
}

// Ficha «Qué parte del IPUF explica la submedición»: aporte = m3 atribuibles (3 años o más) ÷ suscriptores del período.
type SerieIpuf = { p: string; a3: number };
function IpufExplicacion({ periodo, serie, ipufSerie, calculado, fuente, grafica }: {
  periodo: string; serie: SerieIpuf[]; ipufSerie: Ipuf[]; calculado: string; fuente: string; grafica?: ReactNode;
}) {
  const filas = serie.map((s) => {
    const i = ipufSerie.find((x) => x.periodo === s.p);
    const susc = i?.suscriptores ?? null, ip = i?.ipuf ?? null, meta = i?.meta_ipuf ?? null;
    const aporte = susc != null && susc > 0 ? s.a3 / susc : null;
    const pctIpuf = aporte != null && ip != null && ip > 0 ? (aporte / ip) * 100 : null;
    // La reducción hacia la meta solo se calcula desde 202607 (meta de 6,00 de la Res. 1032) y si el IPUF supera la meta.
    const reduccion = s.p >= "202607" && ip != null && meta != null && ip > meta ? ip - meta : null;
    const pctRed = aporte != null && reduccion != null ? (aporte / reduccion) * 100 : null;
    return { p: s.p, m3: s.a3, susc, ip, meta, aporte, pctIpuf, reduccion, pctRed };
  });
  const h = filas.find((f) => f.p === periodo);
  const titulo = "Qué parte del IPUF explica la submedición";
  if (!h || h.aporte == null || h.ip == null) {
    return <Sub titulo={titulo}><div className="dash-sin-filtro">No depende de filtros.</div><div className="dash-nota">Este período no tiene IPUF mensual o suscriptores en la fuente de pérdidas, así que no se calcula la ficha.</div></Sub>;
  }
  const resto = Math.max(h.ip - h.aporte, 0);
  const escala = Math.max(h.ip, h.meta ?? 0) * 1.04;
  const motivoSinReduccion = h.reduccion == null
    ? (periodo < "202607" ? "El período no tiene la meta de 6,00 (rige desde 202607), así que no se calcula la reducción necesaria."
      : "El IPUF del período no supera la meta, así que no hay reducción pendiente.") : "";
  return (
    <Sub titulo={titulo}>
      <div className="dash-sin-filtro">No depende de filtros.</div>
      <div className="dash-kpis">
        <Kpi eti="Submedición estimada" valor={`${fmtDecimal(h.aporte, 2)} m³/susc·mes`} sub={`${fmtEntero(h.m3)} m³ ÷ ${fmtEntero(h.susc ?? 0)} suscriptores`} />
        <Kpi eti="% del IPUF" valor={pct1(h.pctIpuf)} sub={`IPUF del mes: ${fmtDecimal(h.ip, 2)}`} />
        {h.reduccion != null ? (
          <Kpi eti="% de la reducción que falta" valor={pct1(h.pctRed)} sub={`reducción necesaria ${fmtDecimal(h.reduccion, 2)} (IPUF − meta ${fmtDecimal(h.meta ?? 0, 2)})`} />
        ) : null}
      </div>
      {motivoSinReduccion ? <div className="dash-nota">{motivoSinReduccion}</div> : null}
      <div style={{ margin: "10px 0 4px", fontSize: 12 }}>IPUF del mes dividido en submedición estimada y resto (m³ por suscriptor al mes)</div>
      <div className="dash-meta-pista" style={{ height: 26, display: "flex", overflow: "visible" }}>
        <div style={{ width: `${(h.aporte / escala) * 100}%`, background: "#0A2540", borderRadius: "4px 0 0 4px" }} title={`Submedición estimada: ${fmtDecimal(h.aporte, 2)}`} />
        <div style={{ width: `${(resto / escala) * 100}%`, background: "#9AA7B5", borderRadius: "0 4px 4px 0" }} title={`Resto del IPUF: ${fmtDecimal(resto, 2)}`} />
        {h.meta != null ? <div className="dash-meta-marca" style={{ left: `${(h.meta / escala) * 100}%` }} title={`Meta ${fmtDecimal(h.meta, 2)}`} /> : null}
      </div>
      <div className="dash-meta-leyenda">
        <span style={{ color: "#0A2540" }}>■</span> Submedición estimada {fmtDecimal(h.aporte, 2)} · <span style={{ color: "#9AA7B5" }}>■</span> Resto del IPUF (otras fuentes) {fmtDecimal(resto, 2)}
        {h.meta != null ? <> · <span style={{ color: "#C98A2D" }}>▌</span> Meta {fmtDecimal(h.meta, 2)}</> : null}
      </div>
      {grafica}
      <div className="dash-nota">
        La submedición estimada equivale a {fmtDecimal(h.aporte, 2)} m³ por suscriptor al mes, frente a un IPUF de {fmtDecimal(h.ip, 2)}
        {h.meta != null ? ` y una meta de ${fmtDecimal(h.meta, 2)}` : ""}. Eso es cerca del {fmtDecimal(h.pctIpuf ?? 0, 1)} % del IPUF
        {h.reduccion != null ? ` y del ${fmtDecimal(h.pctRed ?? 0, 1)} % de la reducción que falta para llegar a la meta` : ""}. La submedición pesa, pero la mayor
        parte del IPUF sale de otras fuentes que este análisis no mide: por ejemplo pérdidas técnicas, conexiones sin medidor o sin facturación y consumos no autorizados.
      </div>
      <div className="dash-nota">
        Cálculo solo sobre residencial con lectura real, consumo mayor que 0 y hasta 100 m3 y medidor de 3 años o más. Es un piso parcial: no incluye contratos sin medidor ni
        facturados por promedio. El resto del IPUF no se desagrega con los datos actuales.
      </div>
      <div className="dash-tabla-scroll"><table className="dash-tabla num">
        <thead><tr><th>Período</th><th>IPUF</th><th>Meta</th><th>Suscriptores</th><th>m³ atribuibles (3+ años)</th><th>Aporte (m³/susc·mes)</th><th>% del IPUF</th><th>% de la reducción</th></tr></thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.p}><td>{etiquetaCorta(f.p)}</td><td className="num">{f.ip != null ? fmtDecimal(f.ip, 2) : "—"}</td><td className="num">{f.meta != null ? fmtDecimal(f.meta, 2) : "—"}</td>
              <td className="num">{f.susc != null ? fmtEntero(f.susc) : "—"}</td><td className="num">{fmtEntero(f.m3)}</td><td className="num">{f.aporte != null ? fmtDecimal(f.aporte, 2) : "—"}</td>
              <td className="num">{pct1(f.pctIpuf)}</td><td className="num">{f.reduccion != null ? pct1(f.pctRed) : "—"}</td></tr>
          ))}
        </tbody>
      </table></div>
      <div className="dash-nota">La reducción necesaria se calcula solo desde 202607 (meta de 6,00); en 202605 la meta era otra y no se calcula.</div>
      <Pie fuente={`${fuente}; bi.v_ipuf (suscriptores, IPUF y meta)`} periodo={etiquetaPeriodo(periodo)} calculado={calculado}
        formula="Aporte = m³ atribuibles (bruta − exceso de las bandas de 3 años o más) ÷ suscriptores del período. % del IPUF = aporte ÷ IPUF. Reducción necesaria = IPUF − meta (solo desde 202607 y si el IPUF supera la meta). % de la reducción = aporte ÷ reducción necesaria. Resto del IPUF = IPUF − aporte." />
    </Sub>
  );
}

type Props = { periodo: string; valores: Record<string, string>; onCambioValores: (v: Record<string, string>) => void };

export function SubmedicionVejez({ periodo, valores, onCambioValores }: Props) {
  const ref = useVista("v_submedicion_ref_dim", comoSubmedicionRefDim);
  const cic = useVista("v_submedicion_ciclo_dim", comoSubmedicionCicloDim);
  // Abiertas por defecto: resumen (fichas), distribución por vejez y metodología. Se recuerdan durante la sesión.
  const [abiertas, setAbiertas] = useEstadoSesion<Record<string, boolean>>(`${periodo}.subm.partes`, PARTES_DEFECTO, normalizarBanderas(PARTES.map((x) => x.id), PARTES_DEFECTO));
  // Los rangos solo se consultan al abrir su parte (también si se recordó abierta).
  const [verRangos, setVerRangos] = useState(!!abiertas.rangos);
  function cambiar(id: string, abierta: boolean) {
    setAbiertas((a) => (a[id] === abierta ? a : { ...a, [id]: abierta }));
    if (id === "rangos" && abierta) setVerRangos(true);
  }
  function abrir(id: string) {
    cambiar(id, true);
    irCuandoExista(`subm-${id}`, true);
  }
  const rng = useVista("v_submedicion_rango_dim", comoSubmedicionRangoDim, verRangos);
  const [modoMapa, setModoMapa] = useState<"pct" | "bruta">("pct");
  // Calculadora: estado SOLO en memoria (no se guarda ni se envía a ningún servidor; se borra al recargar).
  const [valorMedidor, setValorMedidor] = useState("");
  const [pctRec, setPctRec] = useState("");
  const [tasaRec, setTasaRec] = useState("");

  const filas = ref.datos ?? [];
  const periodos = useMemo(() => [...new Set(filas.map((x) => x.periodo))].sort(), [filas]);
  // Solo el estrato: el ciclo no aplica a Submedición (la fuente por estrato y banda no trae ciclo).
  const filtros = useMemo(
    () => filtrosCicloUsoEstrato(
      [],
      [...new Set(filas.map((x) => x.estrato))].map((e) => ({ uso: "Residencial", subcategoria: e })),
    ).filter((f) => f.id === "subcategoria").map((f) => ({ ...f, visible: undefined })),
    [filas],
  );
  // Un estrato recordado de la sesión que no existe en este período se descarta en silencio.
  useEffect(() => {
    if (ref.datos && valores.subcategoria !== TODOS && !filas.some((x) => x.estrato === valores.subcategoria)) onCambioValores({ subcategoria: TODOS });
  }, [ref.datos]);   // eslint-disable-line react-hooks/exhaustive-deps
  const estr = valores.subcategoria;
  const filtraEstr = (e: string) => estr === TODOS || e === estr;

  // Estrato × banda del período (ignora el ciclo: la tabla no lo trae)
  const delPer = useMemo(() => filas.filter((x) => x.periodo === periodo && filtraEstr(x.estrato)), [filas, periodo, estr]); // eslint-disable-line react-hooks/exhaustive-deps
  const bandas = useMemo(() => porBanda(delPer), [delPer]);
  const tarifa = tarifaDe(delPer);

  // Serie por período (respeta el filtro de estrato)
  const serie = useMemo(
    () => periodos.map((p) => {
      const fs = filas.filter((x) => x.periodo === p && filtraEstr(x.estrato));
      const m = porBanda(fs);
      const t = tarifaDe(fs);
      const total = [...m.values()].reduce((s, b) => s + b.bruta, 0);
      return { p, t, a3: sumaNeta(m, VEJEZ), a5: sumaNeta(m, CINCO_MAS), a10: sumaNeta(m, DIEZ_MAS), bruta: total, sf: m.get("Sin fecha")?.contratos ?? 0 };
    }),
    [filas, periodos, estr], // eslint-disable-line react-hooks/exhaustive-deps
  );

  const encabezado = (
    <>
      <h3>Submedición por vejez del medidor — {etiquetaPeriodo(periodo)} (estimación)</h3>
      <div className="dash-nota">
        Estimación del consumo que se dejaría de registrar por la vejez de los medidores residenciales: compara el consumo de los
        medidores de 3 años o más con la media de los de menos de 3 años del mismo estrato. No es un valor exacto ni distingue
        desgaste de desocupación.
      </div>
    </>
  );

  if (ref.error || cic.error) return <Reintento titulo="Submedición por vejez del medidor" e={ref.error ? ref : cic} />;
  if (!ref.datos || !cic.datos) return <Reintento titulo="Submedición por vejez del medidor" e={ref} />;

  if (!periodos.includes(periodo)) {
    const motivo = periodo < "202605" ? "La antigüedad del medidor existe desde 202605, así que este análisis no se calcula antes."
      : periodo === "202606" ? "202606 no existe en la fuente de consumo."
      : `No hay submedición calculada para ${etiquetaPeriodo(periodo)}.`;
    return (
      <div className="dash-fila"><div className="dash-carta">
        {encabezado}
        <div className="dash-estado"><p>{motivo}</p><p>Hay datos de {etiquetaPeriodo(periodos[0])} a {etiquetaPeriodo(periodos[periodos.length - 1])} (sin 202606).</p></div>
      </div></div>
    );
  }

  const calculado = fechaCalculo(delPer);
  const fuenteRef = FUENTE_REF;
  const a3 = sumaNeta(bandas, VEJEZ), a5 = sumaNeta(bandas, CINCO_MAS), a10 = sumaNeta(bandas, DIEZ_MAS);
  const c3 = sumaContratos(bandas, VEJEZ), c5 = sumaContratos(bandas, CINCO_MAS), c10 = sumaContratos(bandas, DIEZ_MAS);
  const universo = [...bandas.values()].reduce((s, b) => s + b.contratos, 0);
  const medidor = [...bandas.values()].reduce((s, b) => s + b.medidor, 0);
  const prom = [...bandas.values()].reduce((s, b) => s + b.prom, 0);
  const ceros = [...bandas.values()].reduce((s, b) => s + b.cero, 0);
  const sobre = [...bandas.values()].reduce((s, b) => s + b.sobre, 0);
  const brutaTotal = [...bandas.values()].reduce((s, b) => s + b.bruta, 0);
  const rangoA3 = (() => { const v = serie.map((s) => s.a3); return v.length ? [Math.min(...v), Math.max(...v)] : [0, 0]; })();
  // Contratos adicionales bajo la referencia frente a la línea base de los nuevos (por estrato y banda de vejez)
  const adicionales = (() => {
    let s = 0;
    for (const e of new Set(delPer.map((x) => x.estrato))) {
      const nuevos = delPer.find((x) => x.estrato === e && x.banda_antig === "0-3");
      const base = nuevos && nuevos.contratos_bajo_ref != null ? div(nuevos.contratos_bajo_ref, nuevos.contratos) : null;
      if (base == null) continue;
      for (const x of delPer) if (x.estrato === e && VEJEZ.includes(x.banda_antig) && x.contratos_bajo_ref != null) s += x.contratos_bajo_ref - x.contratos * base;
    }
    return s;
  })();

  // Pareto por ciclo (m3_perdidos_atrib), respeta el estrato; ignora el filtro de ciclo
  const pareto = (() => {
    const g = new Map<string, { vej: number; m3: number }>();
    for (const x of cic.datos.filter((c) => c.periodo === periodo && filtraEstr(c.estrato))) {
      const k = String(numeroCiclo(x.ciclo) ?? x.ciclo);
      const a = g.get(k) ?? { vej: 0, m3: 0 };
      a.vej += x.contratos_vejez; a.m3 += x.m3_perdidos_atrib ?? 0; g.set(k, a);
    }
    const grandes: [string, { vej: number; m3: number }][] = [];
    const otros = { vej: 0, m3: 0 }; let hayOtros = false;
    for (const [k, a] of g) { if (a.vej < MIN_CELDA) { hayOtros = true; otros.vej += a.vej; otros.m3 += a.m3; } else grandes.push([k, a]); }
    grandes.sort((a, b) => b[1].m3 - a[1].m3);
    const lista = hayOtros ? [...grandes, [OTROS, otros] as [string, { vej: number; m3: number }]] : grandes;
    const total = lista.reduce((s, [, a]) => s + a.m3, 0);
    let acum = 0;
    return lista.map(([k, a]) => { acum += a.m3; return { k, ...a, acum: total ? (acum / total) * 100 : null, etiqueta: /^\d+$/.test(k) ? etiquetaCiclo(Number(k)) : k }; });
  })();

  // Mapa de calor ciclo × rango
  const mapa = (() => {
    const datos = (rng.datos ?? []).filter((x) => x.periodo === periodo && filtraEstr(x.estrato));
    const g = new Map<string, Map<string, { c: number; b: number }>>();
    for (const x of datos) {
      const k = String(numeroCiclo(x.ciclo) ?? x.ciclo);
      const fila = g.get(k) ?? new Map<string, { c: number; b: number }>();
      const a = fila.get(x.rango_m3) ?? { c: 0, b: 0 };
      a.c += x.contratos; a.b += x.m3_perdidos_bruta ?? 0; fila.set(x.rango_m3, a); g.set(k, fila);
    }
    const ciclos = [...g.keys()].sort((a, b) => Number(a) - Number(b));
    const valor = (k: string, r: string) => {
      const fila = g.get(k)!; const a = fila.get(r);
      const tot = [...fila.values()].reduce((s, z) => s + z.c, 0);
      if (!a || a.c < MIN_CELDA) return null;
      return modoMapa === "pct" ? (a.c / tot) * 100 : a.b;
    };
    let max = 0;
    for (const k of ciclos) for (const r of RANGOS) max = Math.max(max, valor(k, r) ?? 0);
    const porRango = RANGOS.map((r) => ({ etiqueta: `${r} m³`, valor: [...g.values()].reduce((s, f) => s + (f.get(r)?.b ?? 0), 0) }));
    return { ciclos, valor, max, porRango };
  })();

  // Calculadora de retorno
  const valor = leerNumero(valorMedidor);
  const pRec = leerNumero(pctRec); const tRec = leerNumero(tasaRec);
  const factorRec = (pRec ?? 100) / 100, factorTasa = (tRec ?? 100) / 100;
  const calc = VEJEZ.map((b) => {
    const x = bandas.get(b);
    const brecha = x ? div(neta(x), x.contratos) : null;
    const ingreso = brecha != null && brecha > 0 && tarifa != null ? brecha * tarifa * factorRec * factorTasa : null;
    return { b, contratos: x?.contratos ?? 0, brecha, ingreso, meses: valor != null && ingreso ? valor / ingreso : null };
  });
  const invTotal = valor == null ? 0 : calc.filter((c) => c.ingreso != null).reduce((s, c) => s + valor * c.contratos, 0);
  const ingTotal = calc.reduce((s, c) => s + (c.ingreso ?? 0) * c.contratos, 0);

  const estratosOrden = [...new Set(delPer.map((x) => x.estrato))].sort();
  const refEstrato = (e: string) => delPer.find((x) => x.estrato === e && x.banda_antig === "0-3");
  const periodosTxt = periodos.map(etiquetaCorta).join(", ");

  return (
    <div className="dash-con-panel">
      <PanelFiltros filtros={filtros} valores={valores} onCambio={onCambioValores} />
      <div className="dash-con-panel-cuerpo">
        <div className="dash-fila"><div className="dash-carta">
          {encabezado}
          <div className="dash-nota">El ciclo no aplica a Submedición: la fuente por estrato y banda no trae ciclo. El filtro de ciclo solo filtra el detalle de lectura y los cambios de medidor. Aquí solo se filtra por estrato.</div>
          <div className="dash-nota">Períodos con datos: {periodosTxt}. 202606 no existe en la fuente.</div>
        </div></div>

        <div className="dash-fila"><div className="dash-carta">
          <nav className="dash-indice" aria-label="Contenido de la sección">
            <b>Contenido:</b>
            {PARTES.map((x) => <button key={x.id} className="dash-boton-indice" onClick={() => abrir(x.id)}>{x.titulo}</button>)}
          </nav>
        </div></div>

        <Parte id="resumen" titulo="Resumen del período (estimación)" abierta={!!abiertas.resumen} onCambio={(o) => cambiar("resumen", o)}>
        <>
          <div className="dash-kpis">
            <Kpi eti="Pérdida atribuible (3 años o más)" valor={`${m3(a3)} m³/mes`} sub={`${fmtMillones(pesosDe(a3, tarifa))}/mes · entre ${fmtEntero(rangoA3[0])} y ${fmtEntero(rangoA3[1])} m³ en los períodos con datos`} />
            <Kpi eti="De ella, medidores de 10 años o más" valor={`${m3(a10)} m³`} sub={`${fmtMillones(pesosDe(a10, tarifa))} · ${pct1(a3 ? (a10 / a3) * 100 : null)} de la atribuible`} />
            <Kpi eti="Contratos de vejez (3 años o más)" valor={fmtEntero(c3)} sub={`${pct1(div(c3, universo) == null ? null : (c3 / universo) * 100)} del universo de ${fmtEntero(universo)}`} />
            <Kpi eti="Contratos adicionales bajo la referencia" valor={fmtEntero(Math.round(adicionales))} sub="frente a la línea base de los medidores nuevos" />
            <Kpi eti="Pérdida bruta" valor={`${m3(brutaTotal)} m³`} sub={`${fmtMillones(pesosDe(brutaTotal, tarifa))} · techo teórico, no recuperable`} />
            <Kpi eti="Cobertura" valor={`${fmtEntero(universo)} de ${fmtEntero(medidor)}`} sub={`residenciales con medidor en el universo · ${pct1(div(prom, medidor) == null ? null : (prom / medidor) * 100)} facturados por promedio · excluidos: ${fmtEntero(ceros)} en cero y ${fmtEntero(sobre)} sobre 100 m³`} />
          </div>
          {tarifa != null ? <div className="dash-nota">Tarifa del período: $ {fmtDecimal(tarifa, 2)} por m³. Las fichas usan el filtro de estrato y no el de ciclo.</div> : null}
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado}
            formula="Atribuible = Σ (referencia − consumo) sobre los contratos de 3 años o más = bruta − exceso de esas bandas. Pesos = m³ × tarifa. Adicionales = Σ por estrato y banda de (contratos bajo la referencia − contratos × proporción bajo la referencia de la banda 0-3)." />

        </>
        </Parte>
        <Parte id="vejez" titulo="Distribución por vejez" abierta={!!abiertas.vejez} onCambio={(o) => cambiar("vejez", o)}>
        <Sub titulo="Pérdida distribuida por vejez del medidor">
          <div className="dash-fila-g2">
            <div><h3>Brecha neta (m³/mes)</h3><BarrasHorizontales datos={BANDAS.map((b) => ({ etiqueta: etiquetaBanda(b), valor: neta(bandas.get(b)) }))} formatoValor={(v) => `${fmtEntero(v)} m³`} color="#0A2540" /></div>
            <div><h3>Contratos</h3><BarrasHorizontales datos={BANDAS.map((b) => ({ etiqueta: etiquetaBanda(b), valor: bandas.get(b)?.contratos ?? 0 }))} formatoValor={fmtEntero} color="#0E7C86" /></div>
          </div>
          <TablaPlegable titulo="Datos: pérdida por banda de antigüedad">
            <table className="dash-tabla num">
              <thead><tr><th>Banda</th><th>Contratos</th><th>% bajo la referencia</th><th>Consumo promedio (m³)</th><th>Brecha por contrato (m³)</th><th>Brecha neta (m³)</th><th>Pesos</th></tr></thead>
              <tbody>
                {BANDAS.map((b) => {
                  const x = bandas.get(b); if (!x) return null;
                  return (
                    <tr key={b}><td>{etiquetaBanda(b)}{b === "0-3" ? " · base" : b === "Sin fecha" ? " · fuera del grupo" : ""}</td><td className="num">{fmtEntero(x.contratos)}</td>
                      <td className="num">{pct1(div(x.bajo, x.contratos) == null ? null : (x.bajo / x.contratos) * 100)}</td><td className="num">{x.contratos ? fmtDecimal(x.m3 / x.contratos, 1) : "—"}</td>
                      <td className="num">{x.contratos ? fmtDecimal(neta(x) / x.contratos, 2) : "—"}</td><td className="num">{fmtEntero(neta(x))}</td><td className="num">{fmtMillones(pesosDe(neta(x), tarifa))}</td></tr>
                  );
                })}
              </tbody>
            </table>
          </TablaPlegable>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Brecha neta de la banda = m3_perdidos_bruta − m3_exceso = Σ (referencia − consumo) de sus contratos. Brecha por contrato = brecha neta ÷ contratos. % bajo la referencia = contratos con consumo menor que la referencia ÷ contratos." />
        </Sub>

        </Parte>
        <Parte id="estrato" titulo="Por estrato" abierta={!!abiertas.estrato} onCambio={(o) => cambiar("estrato", o)}>
        <Sub titulo="Referencia por estrato y confiabilidad">
          <div className="dash-tabla-scroll">
            <table className="dash-tabla num">
              <thead><tr><th>Estrato</th><th>Referencia (m³)</th><th>n de nuevos</th><th>Confiabilidad</th><th>Media de vejez (m³)</th><th>n de vejez</th></tr></thead>
              <tbody>
                {estratosOrden.map((e) => {
                  const x = refEstrato(e); const nn = x?.n_nuevos ?? 0;
                  const sem = nn < 30 ? "no se calcula" : nn < 100 ? "frágil" : "confiable";
                  return (
                    <tr key={e}><td>{nombreEstrato(e)}</td><td className="num">{x?.ref_nuevos_media_m3 != null ? fmtDecimal(x.ref_nuevos_media_m3, 2) : "—"}</td><td className="num">{fmtEntero(nn)}</td>
                      <td>{sem === "confiable" ? "● confiable" : sem === "frágil" ? "◐ frágil (n < 100)" : "○ no se calcula (n < 30)"}</td>
                      <td className="num">{x?.media_vejez_m3 != null ? fmtDecimal(x.media_vejez_m3, 2) : "—"}</td><td className="num">{fmtEntero(x?.n_vejez ?? 0)}</td></tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Referencia = media de consumo_cargos de los medidores de menos de 3 años del estrato; vale NULL (no se calcula) si hay menos de 30. Frágil: menos de 100." />
        </Sub>

        <Sub titulo="Pérdida atribuible por estrato">
          {(() => {
            const filasE = estratosOrden.map((e) => { const m = porBanda(delPer.filter((x) => x.estrato === e)); return { e, m3: sumaNeta(m, VEJEZ), c: sumaContratos(m, VEJEZ), t: tarifa }; });
            return (
              <>
                <BarrasHorizontales datos={filasE.map((f) => ({ etiqueta: nombreEstrato(f.e), valor: f.m3 }))} formatoValor={(v) => `${fmtEntero(v)} m³`} color="#0A2540" />
                <div className="dash-tabla-scroll"><table className="dash-tabla num">
                  <thead><tr><th>Estrato</th><th>Contratos de vejez</th><th>Atribuible (m³)</th><th>Pesos</th></tr></thead>
                  <tbody>{filasE.map((f) => <tr key={f.e}><td>{nombreEstrato(f.e)}</td><td className="num">{fmtEntero(f.c)}</td><td className="num">{fmtEntero(f.m3)}</td><td className="num">{fmtMillones(pesosDe(f.m3, f.t))}</td></tr>)}</tbody>
                </table></div>
              </>
            );
          })()}
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Atribuible del estrato = Σ (bruta − exceso) de sus bandas de 3 años o más." />
        </Sub>

        <Sub titulo="Tabla maestra por estrato y banda">
          <TablaPlegable titulo="Datos: estrato × banda">
            <table className="dash-tabla num">
              <thead><tr><th>Estrato</th><th>Banda</th><th>Contratos</th><th>Consumo promedio (m³)</th><th>Referencia (m³)</th><th>Brecha por contrato (m³)</th><th>Brecha neta (m³)</th><th>Pesos</th></tr></thead>
              <tbody>
                {estratosOrden.flatMap((e) => BANDAS.map((b) => {
                  const x = delPer.find((y) => y.estrato === e && y.banda_antig === b); if (!x) return null;
                  const nt = (x.m3_perdidos_bruta ?? 0) - (x.m3_exceso ?? 0);
                  const peq = x.contratos < MIN_CELDA;
                  return <tr key={e + b}><td>{nombreEstrato(e)}</td><td>{etiquetaBanda(b)}</td><td className="num">{fmtEntero(x.contratos)}</td>
                    <td className="num">{peq || x.m3_consumo == null ? "—" : fmtDecimal(x.m3_consumo / x.contratos, 1)}</td><td className="num">{x.ref_nuevos_media_m3 != null ? fmtDecimal(x.ref_nuevos_media_m3, 2) : "—"}</td>
                    <td className="num">{peq ? "—" : fmtDecimal(nt / x.contratos, 2)}</td><td className="num">{peq ? "—" : fmtEntero(nt)}</td><td className="num">{peq ? "—" : fmtMillones(pesosDe(nt, x.tarifa_m3))}</td></tr>;
                }))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">Las celdas con menos de {MIN_CELDA} contratos no muestran cifras.</div>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Una fila por estrato y banda, tal como están en la tabla bi.v_submedicion_ref_dim." />
        </Sub>

        </Parte>
        <Parte id="ciclo" titulo="Por ciclo" abierta={!!abiertas.ciclo} onCambio={(o) => cambiar("ciclo", o)}>
        <Sub titulo="Pérdida atribuible por ciclo (Pareto)">
          <BarrasHorizontales datos={pareto.map((p) => ({ etiqueta: p.etiqueta, valor: p.m3 }))} formatoValor={(v) => `${fmtEntero(v)} m³`} color="#0E7C86" />
          <LineasPorcentaje etiquetas={pareto.map((p) => p.etiqueta)} series={[{ nombre: "% acumulado", color: "#C98A2D", valores: pareto.map((p) => p.acum) }]}
            sinTope paso={10} formatoTick={(t) => `${fmtDecimal(t, 0)} %`} formatoValor={(v) => `${fmtDecimal(v, 1)} %`} />
          <TablaPlegable titulo="Datos: atribuible por ciclo">
            <table className="dash-tabla num">
              <thead><tr><th>Ciclo</th><th>Contratos de vejez</th><th>Atribuible (m³)</th><th>Pesos</th><th>m³ por contrato</th><th>% acumulado</th></tr></thead>
              <tbody>{pareto.map((p) => <tr key={p.k}><td>{p.etiqueta}</td><td className="num">{fmtEntero(p.vej)}</td><td className="num">{fmtEntero(p.m3)}</td><td className="num">{fmtMillones(pesosDe(p.m3, tarifa))}</td>
                <td className="num">{p.vej ? fmtDecimal(p.m3 / p.vej, 2) : "—"}</td><td className="num">{pct1(p.acum)}</td></tr>)}</tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">Los ciclos con menos de {MIN_CELDA} contratos de vejez se suman en «{OTROS}». En 202609 el ciclo 5 se separó en el 5 y el 24.</div>
          <Pie fuente="bi.v_submedicion_ciclo_dim" periodo={etiquetaPeriodo(periodo)} calculado={fechaCalculo(cic.datos.filter((c) => c.periodo === periodo))} formula="m3_perdidos_atrib del ciclo = Σ (referencia − consumo) de sus contratos de 3 años o más. Ordenado de mayor a menor; el acumulado es la suma progresiva sobre el total." />
        </Sub>

        </Parte>
        <Parte id="rangos" titulo="Rangos de consumo" abierta={!!abiertas.rangos} onCambio={(o) => cambiar("rangos", o)}>
        <Sub titulo="Mapa de calor: ciclo × rango de consumo">
          {!verRangos ? (
            <div className="dash-estado">Abra esta parte para cargar los rangos de consumo.</div>
          ) : rng.error || !rng.datos ? (
            rng.error ? (<div className="dash-estado"><p>No se pudo cargar esta sección: {rng.error}</p><button className="dash-boton" onClick={rng.recargar}>Reintentar</button></div>) : <div className="dash-estado">Cargando…</div>
          ) : (
            <>
              <div className="dash-filtros-bloque">
                <label>Mostrar
                  <select value={modoMapa} onChange={(e) => setModoMapa(e.target.value as "pct" | "bruta")}>
                    <option value="pct">% de contratos del ciclo en cada rango</option>
                    <option value="bruta">Pérdida bruta (m³, techo teórico)</option>
                  </select>
                </label>
              </div>
              <div className="dash-tabla-scroll">
                <table className="dash-tabla num">
                  <thead><tr><th>Ciclo</th>{RANGOS.map((r) => <th key={r}>{r} m³</th>)}</tr></thead>
                  <tbody>
                    {mapa.ciclos.map((k) => (
                      <tr key={k}><td>{etiquetaCiclo(Number(k))}</td>
                        {RANGOS.map((r) => {
                          const v = mapa.valor(k, r);
                          const t = v != null && mapa.max > 0 ? v / mapa.max : 0;
                          return <td key={r} className="num" style={v == null ? { color: "#9AA7B5" } : { background: `rgba(10,37,64,${0.06 + 0.8 * t})`, color: t > 0.5 ? "#fff" : undefined }}>
                            {v == null ? "—" : modoMapa === "pct" ? pct1(v) : fmtEntero(v)}</td>;
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="dash-nota">Las celdas con menos de {MIN_CELDA} contratos no se muestran («—»). Respeta el filtro de estrato.</div>
              <h3>Pérdida bruta por rango de consumo (m³, techo teórico, no recuperable)</h3>
              <BarrasHorizontales datos={mapa.porRango} formatoValor={(v) => `${fmtEntero(v)} m³`} color="#C98A2D" />
              <Pie fuente="bi.v_submedicion_rango_dim" periodo={etiquetaPeriodo(periodo)} calculado={fechaCalculo(rng.datos.filter((x: SubmedicionRangoDim) => x.periodo === periodo))} formula="El rango se asigna con el consumo real (límite superior inclusivo). % = contratos del ciclo en el rango ÷ contratos del ciclo en el universo. Pérdida bruta = Σ máx(referencia − consumo, 0)." />
            </>
          )}
        </Sub>

        </Parte>
        <Parte id="cascada" titulo="Cascada y serie" abierta={!!abiertas.cascada} onCambio={(o) => cambiar("cascada", o)}>
        <Sub titulo="Cascada de la pérdida (m³/mes)">
          {(() => {
            const b0 = bandas.get("0-3")?.bruta ?? 0, bsf = bandas.get("Sin fecha")?.bruta ?? 0;
            const brutaV = brutaTotal - b0 - bsf;
            const exV = VEJEZ.reduce((s, k) => s + (bandas.get(k)?.exceso ?? 0), 0);
            const pasos: [string, number][] = [["Pérdida bruta total (techo teórico)", brutaTotal], ["Menos la bruta de las bandas 0-3 y Sin fecha", -(b0 + bsf)], ["= Bruta del grupo de vejez", brutaV], ["Menos el exceso del grupo de vejez", -exV], ["= Pérdida atribuible", brutaV - exV]];
            return (
              <>
                <BarrasHorizontales datos={pasos.map(([e, v]) => ({ etiqueta: e, valor: Math.abs(v) }))} formatoValor={(v) => `${fmtEntero(v)} m³`} color="#0A2540" />
                <div className="dash-tabla-scroll"><table className="dash-tabla num"><thead><tr><th>Paso</th><th>m³</th><th>Pesos</th></tr></thead>
                  <tbody>{pasos.map(([e, v]) => <tr key={e}><td>{e}</td><td className="num">{v < 0 ? "−" : ""}{fmtEntero(Math.abs(v))}</td><td className="num">{fmtMillones(pesosDe(v, tarifa))}</td></tr>)}</tbody></table></div>
              </>
            );
          })()}
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Atribuible = bruta de las bandas de vejez − exceso de las bandas de vejez." />
        </Sub>

        <Sub titulo="Pérdida atribuible por período y por edad mínima">
          <LineasPorcentaje etiquetas={serie.map((s) => etiquetaCorta(s.p))}
            series={[{ nombre: "3 años o más", color: "#0A2540", valores: serie.map((s) => s.a3) }, { nombre: "5 años o más", color: "#0E7C86", valores: serie.map((s) => s.a5) },
              { nombre: "10 años o más", color: "#C98A2D", valores: serie.map((s) => s.a10) }, { nombre: "Bruta (techo teórico)", color: "#9AA7B5", valores: serie.map((s) => s.bruta) }]}
            sinTope paso={20000} formatoTick={(t) => fmtEntero(t)} formatoValor={(v) => `${fmtEntero(v)} m³`} tituloY="m³ por mes" />
          <TablaPlegable titulo="Datos: m³, pesos y tarifa por período">
            <table className="dash-tabla num">
              <thead><tr><th>Período</th><th>Tarifa ($/m³)</th><th>3+ años (m³)</th><th>3+ años (pesos)</th><th>5+ años (m³)</th><th>10+ años (m³)</th><th>Bruta (m³)</th><th>Bruta (pesos)</th></tr></thead>
              <tbody>{serie.map((s) => <tr key={s.p}><td>{etiquetaCorta(s.p)}</td><td className="num">{s.t != null ? fmtDecimal(s.t, 2) : "—"}</td><td className="num">{fmtEntero(s.a3)}</td><td className="num">{fmtMillones(pesosDe(s.a3, s.t))}</td>
                <td className="num">{fmtEntero(s.a5)}</td><td className="num">{fmtEntero(s.a10)}</td><td className="num">{fmtEntero(s.bruta)}</td><td className="num">{fmtMillones(pesosDe(s.bruta, s.t))}</td></tr>)}</tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">Aviso 202609: la fecha de instalación viene incompleta ({fmtEntero(serie.find((s) => s.p === "202609")?.sf ?? 0)} contratos del universo sin fecha), lo que mueve contratos a «Sin fecha». 202606 no existe en la fuente. La tarifa cambia por período.</div>
          <Pie fuente={fuenteRef} periodo={periodosTxt} calculado={fechaCalculo(filas)} formula="Para cada período: atribuible con edad mínima de 3, 5 o 10 años = Σ (bruta − exceso) de las bandas desde esa edad; bruta = Σ de m3_perdidos_bruta de todas las bandas." />
        </Sub>

        <Sub titulo="Pérdida atribuible según la edad mínima">
          <div className="dash-tabla-scroll"><table className="dash-tabla num">
            <thead><tr><th>Edad mínima</th><th>m³/mes</th><th>Pesos/mes</th><th>Contratos del grupo</th></tr></thead>
            <tbody>
              {([["3 años o más", a3, c3], ["5 años o más", a5, c5], ["10 años o más", a10, c10]] as [string, number, number][]).map(([e, v, c]) =>
                <tr key={e}><td>{e}</td><td className="num">{fmtEntero(v)}</td><td className="num">{fmtMillones(pesosDe(v, tarifa))}</td><td className="num">{fmtEntero(c)}</td></tr>)}
            </tbody>
          </table></div>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Suma de bruta − exceso de las bandas desde la edad mínima: 3 años (3-5 en adelante), 5 años (5-10 en adelante) y 10 años (10-15 en adelante)." />
        </Sub>

        <Sub titulo="Sensibilidad de la referencia">
          <div className="dash-kpis">
            <Kpi eti="Si la referencia sube 1 m³" valor={`+${fmtEntero(c3)} m³/mes`} sub={`${fmtMillones(pesosDe(c3, tarifa))}/mes más de pérdida atribuible`} />
            <Kpi eti="Si la referencia baja 1 m³" valor={`−${fmtEntero(c3)} m³/mes`} sub={`${fmtMillones(pesosDe(c3, tarifa))}/mes menos de pérdida atribuible`} />
          </div>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Cada m³ de cambio en la referencia mueve la atribuible en (contratos del grupo de vejez) × 1 m³, y en pesos × la tarifa del período." />
        </Sub>

        <Sub titulo="Contraste con la comparación de consumo antes y después de «Cambios de medidor»">
          <div className="dash-nota">
            Aún no hay muestra suficiente de reposiciones confirmadas (cambio de serial con la lectura reiniciada a 10 m³ o menos) para medir con la comparación de consumo antes y después el efecto
            de cambiar el medidor. En 202609, el 97,5 % de los cambios de serial con lectura evaluable conservó la continuidad de la lectura: fue una recodificación de seriales y no
            un cambio físico. La validación de esta estimación se hará con el período 202610.
          </div>
          <button className="dash-boton" onClick={() => { const h = [...document.querySelectorAll("h3")].find((x) => x.textContent?.startsWith("Cambios de medidor")); h?.scrollIntoView({ behavior: "smooth", block: "start" }); }}>
            Ir a «Cambios de medidor»
          </button>
          <Pie fuente="bi.v_cambio_medidor_dim (sql/38)" periodo={etiquetaPeriodo(periodo)} calculado="—" formula="Reposición confirmada = serial distinto con la lectura anterior del período de 10 m³ o menos y menor que la lectura actual del período previo. Continuidad = lectura anterior igual a la lectura actual previa. Contratos comparables: contratos con medidor registrado en el período y en el período disponible anterior; son los únicos sobre los que se puede comparar el consumo antes y después." />
        </Sub>

        </Parte>
        <Parte id="sesgo" titulo="Sesgo y conciliación" abierta={!!abiertas.sesgo} onCambio={(o) => cambiar("sesgo", o)}>
        <Sub titulo="Sesgo de selección por banda">
          <div className="dash-tabla-scroll"><table className="dash-tabla num">
            <thead><tr><th>Banda</th><th>Residenciales con medidor</th><th>% en el universo</th><th>% facturado por promedio</th><th>% consumo cero</th><th>% sobre 100 m³</th></tr></thead>
            <tbody>{BANDAS.map((b) => { const x = bandas.get(b); if (!x) return null; const p = (v: number) => pct1(x.medidor ? (v / x.medidor) * 100 : null);
              return <tr key={b}><td>{etiquetaBanda(b)}</td><td className="num">{fmtEntero(x.medidor)}</td><td className="num">{p(x.contratos)}</td><td className="num">{p(x.prom)}</td><td className="num">{p(x.cero)}</td><td className="num">{p(x.sobre)}</td></tr>; })}</tbody>
          </table></div>
          <div className="dash-nota">Los medidores viejos se facturan más por promedio y quedan menos en el universo: la estimación se apoya en los mejor medidos.</div>
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Cada porcentaje = contratos de la categoría ÷ residenciales con medidor de la banda (contratos_medidor)." />
        </Sub>

        </Parte>
        <Parte id="simulacion" titulo="Simulación" abierta={!!abiertas.simulacion} onCambio={(o) => cambiar("simulacion", o)}>
        <Sub titulo="Calculadora de retorno de la inversión (simulación)">
          <div className="dash-nota"><b>Simulación: el resultado depende del valor ingresado y supone que un medidor nuevo registraría el consumo de la referencia. No se guarda.</b> Se calcula solo en este navegador; no se envía ni se almacena en ningún servidor y se borra al recargar la página.</div>
          <div className="dash-filtros-bloque">
            <label>Valor del medidor instalado (COP)<input inputMode="decimal" value={valorMedidor} onChange={(e) => setValorMedidor(e.target.value)} placeholder="" /></label>
            <label>% de la brecha que se recupera (opcional)<input inputMode="decimal" value={pctRec} onChange={(e) => setPctRec(e.target.value)} placeholder="" /></label>
            <label>Tasa de recaudo, % (opcional)<input inputMode="decimal" value={tasaRec} onChange={(e) => setTasaRec(e.target.value)} placeholder="" /></label>
          </div>
          {valor == null ? (
            <div className="dash-nota">Ingrese el valor del medidor instalado para ver los resultados.</div>
          ) : (
            <>
              <div className="dash-nota">
                {pRec == null ? "% recuperado vacío: se asume 100 %. " : ""}{tRec == null ? "Tasa de recaudo vacía: se asume 100 %. " : ""}Ingreso mensual por medidor = brecha por contrato × tarifa × % recuperado × tasa de recaudo; meses de recuperación = valor del medidor ÷ ingreso mensual.
              </div>
              <div className="dash-tabla-scroll"><table className="dash-tabla num">
                <thead><tr><th>Banda</th><th>Contratos</th><th>Brecha por contrato (m³)</th><th>Ingreso mensual por medidor ($)</th><th>Meses de recuperación</th><th>Inversión ($)</th><th>Ingreso mensual total ($)</th></tr></thead>
                <tbody>
                  {calc.map((c) => (
                    <tr key={c.b}><td>{etiquetaBanda(c.b)}</td><td className="num">{fmtEntero(c.contratos)}</td><td className="num">{c.brecha == null ? "—" : fmtDecimal(c.brecha, 2)}</td>
                      {c.ingreso == null ? <td colSpan={2}>no recupera</td> : <><td className="num">{fmtEntero(Math.round(c.ingreso))}</td><td className="num">{c.meses == null ? "—" : fmtDecimal(c.meses, 1)}</td></>}
                      <td className="num">{c.ingreso == null ? "—" : fmtEntero(Math.round(valor * c.contratos))}</td><td className="num">{c.ingreso == null ? "—" : fmtEntero(Math.round(c.ingreso * c.contratos))}</td></tr>
                  ))}
                  <tr className="dash-fila-fuerte"><td>Total del programa (bandas que recuperan)</td><td className="num">{fmtEntero(calc.filter((c) => c.ingreso != null).reduce((s, c) => s + c.contratos, 0))}</td><td /><td />
                    <td className="num">{ingTotal > 0 ? fmtDecimal(invTotal / ingTotal, 1) : "—"}</td><td className="num">{fmtEntero(Math.round(invTotal))}</td><td className="num">{fmtEntero(Math.round(ingTotal))}</td></tr>
                </tbody>
              </table></div>
            </>
          )}
          <Pie fuente={fuenteRef} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Brecha por contrato de la banda = brecha neta ÷ contratos. Si es menor o igual a cero la banda «no recupera»." />
        </Sub>
        </Parte>
        <Parte id="metodologia" titulo="Metodología y fuentes" abierta={!!abiertas.metodologia} onCambio={(o) => cambiar("metodologia", o)}>
        <>
            <div className="dash-nota">
              <p><b>Qué mide.</b> Una estimación de cuántos m³ al mes dejan de registrarse en medidores residenciales de 3 años o más frente a la media de
              los medidores nuevos del mismo estrato. <b>Qué no mide:</b> no es un valor exacto, no prueba que el medidor esté dañado y no distingue desgaste
              de desocupación u otros usos del predio.</p>
              <p><b>Fuentes.</b> Archivo «Metodo_Calculo_Consumo_Por_Periodo» del sistema comercial (hechos.consumo_metodo): consumo, medidor, observación,
              función y fecha de instalación. Facturación (hechos.facturacion_contratos): tarifa. Tablas bi.v_submedicion_ref_dim, bi.v_submedicion_ciclo_dim y
              bi.v_submedicion_rango_dim. Calculado: {calculado}.</p>
              <p><b>Fórmulas.</b> Universo: residencial, medidor registrado, observación 99, función CALCCODL, un registro por contrato, 0 &lt; consumo_cargos ≤ 100 m³,
              antigüedad al cierre del período en años cumplidos. Referencia: media de la banda 0-3 años del estrato. Vejez: 3 años o más (3-5, 5-10, 10-15 y más de 15);
              «Sin fecha» no entra a ningún grupo. Pérdida atribuible = Σ (referencia − consumo) sobre los contratos de vejez. Pérdida bruta = Σ máx(referencia − consumo, 0);
              exceso = Σ máx(consumo − referencia, 0); brecha neta = bruta − exceso. Pesos = m³ × tarifa del período, donde tarifa = (facturado de los conceptos 2- y 4-) ÷ (consumo
              del concepto 2-). Bandas: 0-3, 3-5, 5-10, 10-15, más de 15 (fecha real), más de 15 (fecha 1986-01-01) y sin fecha.</p>
              <p><b>Conciliación por período</b> (todos los estratos):</p>
              <div className="dash-tabla-scroll">
                <table className="dash-tabla num">
                  <thead><tr><th>Período</th><th>Residenciales con medidor</th><th>Universo</th><th>Facturados por promedio</th><th>Consumo cero</th><th>Más de 100 m³</th><th>Otras funciones</th></tr></thead>
                  <tbody>
                    {periodos.map((p) => {
                      const m = porBanda(filas.filter((x) => x.periodo === p));
                      const t = (k: keyof Banda) => [...m.values()].reduce((s, b) => s + (b[k] as number), 0);
                      const otras = t("medidor") - t("contratos") - t("prom") - t("cero") - t("sobre");
                      return (
                        <tr key={p}><td>{etiquetaCorta(p)}</td><td className="num">{fmtEntero(t("medidor"))}</td><td className="num">{fmtEntero(t("contratos"))}</td>
                          <td className="num">{fmtEntero(t("prom"))}</td><td className="num">{fmtEntero(t("cero"))}</td><td className="num">{fmtEntero(t("sobre"))}</td><td className="num">{fmtEntero(otras)}</td></tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <p><b>Límites.</b> Sesgo de selección: el universo (observación 99 y CALCCODL) deja menos medidores viejos que nuevos, porque los viejos se facturan más por promedio.
              Ocupación: un predio desocupado consume poco sin que el medidor falle. La referencia es sensible en los estratos 5 y 6 (pocos medidores nuevos). 202606 no existe en la fuente.
              La fecha de instalación está incompleta en 202609 (831 contratos sin fecha). La fecha 1986-01-01 es un valor por defecto de antigüedad desconocida. La pérdida bruta es un
              techo teórico, no recuperable. La validación definitiva depende del período 202610.</p>
            </div>
          </>
        </Parte>
      </div>
    </div>
  );
}

// Consumo promedio por banda de antigüedad frente a la referencia, con TODOS los estratos (no depende de filtros). La referencia de cada
// estrato es su consumo en la banda 0-3 años, que es el primer punto de su línea.
function ConsumoPorBanda({ filas, periodo, calculado }: { filas: SubmedicionRefDim[]; periodo: string; calculado: string }) {
  const delPer = filas.filter((x) => x.periodo === periodo);
  const estratos = [...new Set(delPer.map((x) => x.estrato))].sort();
  return (
    <Sub titulo="Consumo promedio por banda frente a la referencia">
      <div className="dash-sin-filtro">No depende de filtros.</div>
      <LineasPorcentaje
        etiquetas={BANDAS.slice(0, 6).map(etiquetaBanda)}
        series={estratos.map((e, i) => {
          const por = (b: string) => { const x = delPer.find((y) => y.estrato === e && y.banda_antig === b); return x && x.contratos >= MIN_CELDA && x.m3_consumo != null ? x.m3_consumo / x.contratos : null; };
          return { nombre: nombreEstrato(e), color: COLORES[i % COLORES.length], valores: BANDAS.slice(0, 6).map(por) };
        })}
        sinTope paso={2} formatoTick={(t) => `${fmtDecimal(t, 0)}`} formatoValor={(v) => `${fmtDecimal(v, 1)} m³`} tituloY="m³ por contrato"
      />
      <div className="dash-nota">La referencia de cada estrato es su consumo promedio en la banda de 0 a 3 años, que es el primer punto de cada línea. Celdas con menos de {MIN_CELDA} contratos no se grafican.</div>
      <Pie fuente={FUENTE_REF} periodo={etiquetaPeriodo(periodo)} calculado={calculado} formula="Consumo promedio de la banda = m3_consumo ÷ contratos del universo. Referencia = promedio de la banda 0-3 años del estrato." />
    </Sub>
  );
}

// Explicación «Qué parte del IPUF explica la submedición» y su tabla por período, FUERA del plegable de Submedición: se calcula con
// la serie de TODOS los estratos (no depende de filtros), con los mismos datos de v_submedicion_ref_dim que ya carga la sección.
export function SubmedicionExplicacion({ periodo, ipufSerie }: { periodo: string; ipufSerie: Ipuf[] }) {
  const ref = useVista("v_submedicion_ref_dim", comoSubmedicionRefDim);
  const filas = ref.datos ?? [];
  const serie = useMemo(
    () => [...new Set(filas.map((x) => x.periodo))].sort().map((p) => ({ p, a3: sumaNeta(porBanda(filas.filter((x) => x.periodo === p)), VEJEZ) })),
    [filas],
  );
  if (ref.error || !ref.datos) return <Reintento titulo="Qué parte del IPUF explica la submedición" e={ref} />;
  return (
    <div className="dash-fila"><div className="dash-carta">
      <IpufExplicacion periodo={periodo} serie={serie} ipufSerie={ipufSerie}
        calculado={fechaCalculo(filas.filter((x) => x.periodo === periodo))} fuente={FUENTE_REF}
        grafica={<ConsumoPorBanda filas={filas} periodo={periodo} calculado={fechaCalculo(filas.filter((x) => x.periodo === periodo))} />} />
    </div></div>
  );
}
