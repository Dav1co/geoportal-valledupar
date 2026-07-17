import { useEffect, useState } from "react";
import { useSession } from "./auth/useSession";
import { Login } from "./auth/Login";
import {
  MapView,
  type PredioApilado,
  type FiltroContrato,
  type FiltroEstado,
  type Conteo,
  type BaseMapa,
  type TerrenoInfo,
  type ModoMapa,
  type ConteoComercial,
  type StatsComercial,
  type PuntoRutaMap,
  type FiltroCatastroRuta,
} from "./components/MapView";
import { PanelIndicadores } from "./components/PanelIndicadores";
import { Buscador } from "./components/Buscador";
import { PredioPanel } from "./components/PredioPanel";
import { Watermark } from "./components/Watermark";
import { Admin } from "./components/Admin";
import { supabase } from "./lib/supabase";
import { api, type RutaItem, type DetalleRuta } from "./lib/api";

const fmt = (n: number) => n.toLocaleString("es-CO");

type Modo = "explorar" | "focalizacion" | "comercial" | "rutas";

// Solo estos correos ven el modo Rutas de lectura.
const CORREOS_RUTAS = new Set([
  "ingdaviddiazr@gmail.com",
  "ddiazrodriguez@emdupar.gov.co",
]);

// --- Opciones de los filtros comerciales (código en BD -> etiqueta visible) ---
type OpcionFiltro = { valor: string; etiqueta: string };

const OPC_MEDICION: OpcionFiltro[] = [
  { valor: "todos", etiqueta: "Todos" },
  { valor: "1", etiqueta: "Con medidor registrado" },
  { valor: "2", etiqueta: "Dañado" },
  { valor: "3", etiqueta: "Sin medidor" },
];
const OPC_FACTURACION: OpcionFiltro[] = [
  { valor: "todos", etiqueta: "Todos" },
  { valor: "1", etiqueta: "Leído" },
  { valor: "2", etiqueta: "Por promedio" },
  { valor: "34", etiqueta: "Suspendido / cortado" },
];
const OPC_CONSUMO: OpcionFiltro[] = [
  { valor: "todos", etiqueta: "Todos" },
  { valor: "cero", etiqueta: "Cero (0 m³)" },
  { valor: "muy_bajo", etiqueta: "Muy bajo (1–6 m³)" },
  { valor: "normal", etiqueta: "Normal (7–17 m³)" },
  { valor: "alto", etiqueta: "Alto (18–32 m³)" },
  { valor: "muy_alto", etiqueta: "Muy alto (33–59 m³)" },
  { valor: "elevado", etiqueta: "Elevado (60–500 m³)" },
  { valor: "grandes", etiqueta: "Grandes (más de 500 m³)" },
];
const OPC_CARTERA: OpcionFiltro[] = [
  { valor: "todos", etiqueta: "Todos" },
  { valor: "con_deuda", etiqueta: "Con deuda" },
  { valor: "al_dia", etiqueta: "Al día" },
  { valor: "leve", etiqueta: "Mora leve (1–2)" },
  { valor: "media", etiqueta: "Mora media (3–8)" },
  { valor: "alta", etiqueta: "Mora alta (9–60)" },
  { valor: "cronica", etiqueta: "Mora crónica (más de 60)" },
];

const DESC_MODO: Record<Modo, string> = {
  explorar: "Busca predios, cambia el mapa base y activa capas.",
  focalizacion: "Aísla predios sin contrato y resalta estados del predio.",
  comercial: "Filtra por cartera, consumo y medición (datos de Acuo).",
  rutas: "Revisa el recorrido de una ruta de lectura y sus anomalías.",
};

// Lee el estado de la vista desde el hash de la URL
function leerURL() {
  const h = window.location.hash.replace(/^#/, "");
  if (!h) return null;
  const p = new URLSearchParams(h);
  const v = p.get("v");
  let inicial: { lng: number; lat: number; zoom: number } | null = null;
  if (v) {
    const [lng, lat, zoom] = v.split(",").map(Number);
    if ([lng, lat, zoom].every(Number.isFinite)) inicial = { lng, lat, zoom };
  }
  const c = p.get("c");
  const e = p.get("e");
  const b = p.get("b");
  const t = p.get("t");
  return {
    inicial,
    filtro: (c === "con" || c === "sin" ? c : "todos") as FiltroContrato,
    estado: (["DEMOLIDO", "EN CONSTRUCCION", "DESOCUPADO"].includes(e ?? "")
      ? e
      : "") as FiltroEstado,
    base: (b === "satelital" ? "satelital" : "calles") as BaseMapa,
    terrenos: t !== "0",
  };
}

const URL0 = leerURL();

export default function App() {
  const { session, cargando } = useSession();
  const [predioId, setPredioId] = useState<number | null>(null);
  const [panelMovilAbierto, setPanelMovilAbierto] = useState(false);
  const [apilados, setApilados] = useState<PredioApilado[] | null>(null);
  const [esAdmin, setEsAdmin] = useState(false);
  const [vista, setVista] = useState<"mapa" | "admin">("mapa");
  const [modo, setModo] = useState<Modo>("explorar");
  const [filtro, setFiltro] = useState<FiltroContrato>(URL0?.filtro ?? "todos");
  const [estado, setEstado] = useState<FiltroEstado>(URL0?.estado ?? "");
  const [mostrarTerrenos, setMostrarTerrenos] = useState(URL0?.terrenos ?? true);
  const [base, setBase] = useState<BaseMapa>(URL0?.base ?? "calles");
  const [modoTerrenos, setModoTerrenos] = useState(false);
  const [terreno, setTerreno] = useState<TerrenoInfo | null>(null);
  const [conteo, setConteo] = useState<Conteo>({ disponible: false, con: 0, sin: 0 });
  const [copiado, setCopiado] = useState(false);
  // Filtros comerciales (cada uno guarda el "valor" de la opción activa)
  const [fMedicion, setFMedicion] = useState("todos");
  const [fFacturacion, setFFacturacion] = useState("todos");
  const [fConsumo, setFConsumo] = useState("todos");
  const [fCartera, setFCartera] = useState("todos");
  const [conteoCom, setConteoCom] = useState<ConteoComercial>({ disponible: false, total: 0 });
  const [fCiclo, setFCiclo] = useState("todos");
  const [fBarrio, setFBarrio] = useState("");          // barrio seleccionado (exacto)
  const [barrioTexto, setBarrioTexto] = useState("");  // lo que se escribe
  const [listaBarrios, setListaBarrios] = useState<string[]>([]);
  const [statsCom, setStatsCom] = useState<StatsComercial>({
    disponible: false, total: 0, conDeuda: 0, sinMedidor: 0, consumoAlto: 0,
    medicion: {}, facturacion: {}, consumo: {}, mora: {}, ciclo: {}, barrio: {},
  });
  const [panelAbierto, setPanelAbierto] = useState(false);
  const [listaRutas, setListaRutas] = useState<RutaItem[]>([]);
  const [rutaSel, setRutaSel] = useState("");
  const [detalleRuta, setDetalleRuta] = useState<DetalleRuta | null>(null);
  const [cargandoRuta, setCargandoRuta] = useState(false);
  const [filtroCatRuta, setFiltroCatRuta] = useState<FiltroCatastroRuta>("ninguno");

  useEffect(() => {
    if (!session) {
      setEsAdmin(false);
      return;
    }
    api.admin
      .perfil()
      .then((r) => setEsAdmin(r.es_admin))
      .catch(() => setEsAdmin(false));
  }, [session]);

  // Cargar la lista de barrios la primera vez que se entra al modo Comercial.
  useEffect(() => {
    if (modo === "comercial" && listaBarrios.length === 0) {
      api.barrios()
        .then((r) => setListaBarrios(r.barrios ?? []))
        .catch(() => setListaBarrios([]));
    }
  }, [modo, listaBarrios.length]);

  // Salvaguarda: si un usuario no autorizado cae en modo rutas, devolverlo a explorar.
  useEffect(() => {
    const correo = (session?.user.email ?? "").toLowerCase();
    if (modo === "rutas" && !CORREOS_RUTAS.has(correo)) setModo("explorar");
  }, [modo, session]);

  // Cargar la lista de rutas la primera vez que se entra al modo Rutas.
  useEffect(() => {
    if (modo === "rutas" && listaRutas.length === 0) {
      api.rutasLista()
        .then((r) => setListaRutas(r.rutas ?? []))
        .catch(() => setListaRutas([]));
    }
  }, [modo, listaRutas.length]);

  // Cuando se elige una ruta, cargar su detalle (recorrido + métricas).
  useEffect(() => {
    if (!rutaSel) { setDetalleRuta(null); return; }
    setCargandoRuta(true);
    api.ruta(rutaSel)
      .then((r) => setDetalleRuta(r.ruta))
      .catch(() => setDetalleRuta(null))
      .finally(() => setCargandoRuta(false));
  }, [rutaSel]);

  if (cargando) {
    return <div className="pantalla-carga">Cargando…</div>;
  }
  if (!session) return <Login />;

  const email = session.user.email ?? "";
  const puedeVerRutas = CORREOS_RUTAS.has(email.toLowerCase());

  function irAPredio(id: number, x: number, y: number) {
    setApilados(null);
    setPredioId(id);
    (window as unknown as { __geoFly?: (x: number, y: number) => void }).__geoFly?.(x, y);
  }

  function abrirApilados(lista: PredioApilado[]) {
    setPredioId(null);
    setApilados(lista);
    api
      .resumen(lista.map((p) => p.id))
      .then(({ predios }) => {
        const dir = new Map(predios.map((p) => [p.id, p.direccion]));
        setApilados((prev) =>
          prev
            ? prev.map((p) => ({ ...p, direccion: dir.get(p.id) ?? p.direccion }))
            : prev,
        );
      })
      .catch(() => {});
  }

  function toggleModoTerrenos() {
    const nuevo = !modoTerrenos;
    setModoTerrenos(nuevo);
    if (nuevo) setEstado("");
    else setTerreno(null);
  }

  function compartirVista() {
    const w = window as unknown as {
      __geoVista?: () => { lng: number; lat: number; zoom: number } | null;
    };
    const v = w.__geoVista?.();
    const p = new URLSearchParams();
    if (v) p.set("v", `${v.lng.toFixed(6)},${v.lat.toFixed(6)},${v.zoom.toFixed(2)}`);
    if (filtro !== "todos") p.set("c", filtro);
    if (estado) p.set("e", estado);
    if (base !== "calles") p.set("b", base);
    if (!mostrarTerrenos) p.set("t", "0");
    const url = `${window.location.origin}${window.location.pathname}#${p.toString()}`;
    navigator.clipboard.writeText(url).then(
      () => {
        setCopiado(true);
        window.setTimeout(() => setCopiado(false), 2000);
      },
      () => {
        window.location.hash = p.toString();
      },
    );
  }

// Construye la expresión MapLibre combinada (lógica Y) a partir de los 4 filtros.
  function construirFiltroComercial(): unknown[] | null {
    const conds: unknown[] = [];

    if (fMedicion !== "todos") {
      conds.push(["==", ["get", "estado_medidor"], fMedicion]);
    }
    if (fFacturacion !== "todos") {
      if (fFacturacion === "34") {
        conds.push(["any",
          ["==", ["get", "determinacion_consumo"], "3"],
          ["==", ["get", "determinacion_consumo"], "4"],
        ]);
      } else {
        conds.push(["==", ["get", "determinacion_consumo"], fFacturacion]);
      }
    }
    if (fConsumo !== "todos") {
      conds.push(["==", ["get", "clase_consumo"], fConsumo]);
    }
    if (fCartera !== "todos") {
      if (fCartera === "con_deuda") {
        conds.push(["==", ["get", "tiene_deuda"], true]);
      } else if (fCartera === "al_dia") {
        conds.push(["==", ["get", "tramo_mora"], "al_dia"]);
      } else {
        // tramos de mora específicos
        conds.push(["==", ["get", "tramo_mora"], fCartera]);
      }
    }
    if (fCiclo !== "todos") {
      conds.push(["==", ["get", "ciclo"], fCiclo]);
    }
    if (fBarrio !== "") {
      conds.push(["==", ["get", "barrio"], fBarrio]);
    }

    return conds.length > 0 ? conds : null;
  }

  const filtroComercial = modo === "comercial" ? construirFiltroComercial() : null;
  const puntosRuta: PuntoRutaMap[] | null =
    modo === "rutas" && detalleRuta ? detalleRuta.puntos : null;
  const hayFiltrosCom = fMedicion !== "todos" || fFacturacion !== "todos" || fConsumo !== "todos" || fCartera !== "todos" || fCiclo !== "todos" || fBarrio !== "";

  function limpiarComercial() {
    setFMedicion("todos");
    setFFacturacion("todos");
    setFConsumo("todos");
    setFCartera("todos");
    setFCiclo("todos");
    setFBarrio("");
    setBarrioTexto("");
  }

  function textoConteoComercial() {
    if (!hayFiltrosCom) return "Selecciona filtros para ver cuántos predios cumplen.";
    if (!conteoCom.disponible) return "Acércate para contar los predios que cumplen.";
    return `${fmt(conteoCom.total)} predios cumplen los filtros en pantalla`;
  }

    function textoConteo() {
    if (!conteo.disponible) return "Acércate para contar los predios en pantalla.";
    const total = conteo.con + conteo.sin;
    if (filtro === "con") return `${fmt(conteo.con)} con contrato en pantalla`;
    if (filtro === "sin") return `${fmt(conteo.sin)} sin contrato en pantalla`;
    return `${fmt(total)} en pantalla · ${fmt(conteo.con)} con · ${fmt(conteo.sin)} sin contrato`;
  }

  return (
    <div className="app">
      <header className="barra">
        <div className="barra-marca">
          <span className="brand-mark">◆</span>
          <span>Geoportal Catastral</span>
          <span className="barra-ent">EMDUPAR</span>
        </div>

        <div className="barra-usuario">
          {esAdmin && (
            <button
              className="btn-link"
              onClick={() => setVista(vista === "admin" ? "mapa" : "admin")}
            >
              {vista === "admin" ? "Volver al mapa" : "Administración"}
            </button>
          )}
          <span className="mono barra-correo">{email}</span>
          <button className="btn-link" onClick={() => supabase.auth.signOut()}>
            Salir
          </button>
        </div>
      </header>

      {vista === "admin" ? (
        <div className="cuerpo" style={{ overflow: "auto", padding: 16 }}>
          <Admin onVolver={() => setVista("mapa")} />
        </div>
      ) : (
        <div className="cuerpo">
          <button
            className="btn-panel-movil"
            onClick={() => setPanelMovilAbierto(true)}
            aria-label="Abrir controles"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <line x1="3" y1="6" x2="21" y2="6" /><line x1="3" y1="12" x2="21" y2="12" />
              <line x1="3" y1="18" x2="21" y2="18" />
            </svg>
            Controles
          </button>
          {panelMovilAbierto && (
            <div className="panel-overlay" onClick={() => setPanelMovilAbierto(false)} />
          )}
          <aside className={`lateral ${panelMovilAbierto ? "abierto" : ""}`}>
            <button
              className="btn-cerrar-panel"
              onClick={() => setPanelMovilAbierto(false)}
            >
              ✕ Cerrar
            </button>
            {/* Selector de modo */}
            <div className="modo-wrap">
              <span className="modo-lbl">Modo de trabajo</span>
              <select
                className="modo-sel"
                value={modo}
                onChange={(e) => setModo(e.target.value as Modo)}
              >
                <option value="explorar">Explorar</option>
                <option value="focalizacion">Focalización</option>
                <option value="comercial">Comercial</option>
                {puedeVerRutas && (
                  <option value="rutas">Rutas de lectura</option>
                )}
              </select>
              <div className="modo-desc">{DESC_MODO[modo]}</div>
            </div>

            {/* MODO EXPLORAR */}
            {modo === "explorar" && (
              <>
                <div className="seccion">
                  <span className="filtro-rotulo">Buscar por contrato</span>
                  <Buscador onSeleccionar={irAPredio} modo="contrato" />
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Buscar por serial de medidor</span>
                  <Buscador onSeleccionar={irAPredio} modo="medidor" />
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Mapa base</span>
                  <div className="filtro-segmentado">
                    <button
                      className={`seg ${base === "calles" ? "seg-activo" : ""}`}
                      onClick={() => setBase("calles")}
                    >
                      Calles
                    </button>
                    <button
                      className={`seg ${base === "satelital" ? "seg-activo" : ""}`}
                      onClick={() => setBase("satelital")}
                    >
                      Satélite
                    </button>
                  </div>
                  <label className="filtro-check">
                    <input
                      type="checkbox"
                      checked={mostrarTerrenos}
                      onChange={(e) => setMostrarTerrenos(e.target.checked)}
                    />
                    Mostrar terrenos
                  </label>
                  <button
                    className={`btn-modo ${modoTerrenos ? "btn-modo-activo" : ""}`}
                    onClick={toggleModoTerrenos}
                  >
                    {modoTerrenos ? "✓ Seleccionando terrenos" : "Seleccionar terrenos"}
                  </button>
                  <button className="btn-modo" onClick={compartirVista}>
                    {copiado ? "✓ Enlace copiado" : "Compartir vista"}
                  </button>
                  {modoTerrenos && (
                    <div className="terreno-info">
                      {terreno ? (
                        <>
                          <span className="filtro-rotulo">Código catastral</span>
                          <span className="mono terreno-cod">{terreno.codigo}</span>
                          <span className="filtro-rotulo" style={{ marginTop: 6 }}>
                            Matrícula inmobiliaria
                          </span>
                          <span className="mono terreno-cod">
                            {terreno.matricula ?? "Sin matrícula registrada"}
                          </span>
                        </>
                      ) : (
                        <span className="terreno-ayuda">
                          Haz clic en un lote para ver su código y matrícula.
                        </span>
                      )}
                    </div>
                  )}
                </div>
              </>
            )}

            {/* MODO FOCALIZACIÓN */}
            {modo === "focalizacion" && (
              <>
                <div className="seccion">
                  <span className="filtro-rotulo">Contrato</span>
                  <div className="filtro-segmentado">
                    <button
                      className={`seg ${filtro === "todos" ? "seg-activo" : ""}`}
                      onClick={() => setFiltro("todos")}
                    >
                      Todos
                    </button>
                    <button
                      className={`seg ${filtro === "con" ? "seg-activo" : ""}`}
                      onClick={() => setFiltro("con")}
                    >
                      Con contrato
                    </button>
                    <button
                      className={`seg ${filtro === "sin" ? "seg-activo" : ""}`}
                      onClick={() => setFiltro("sin")}
                    >
                      Sin contrato
                    </button>
                  </div>
                  <p className="contador">{textoConteo()}</p>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Resaltar estado</span>
                  <div className="filtro-segmentado filtro-segmentado-wrap">
                    <button
                      className={`seg ${estado === "" ? "seg-activo" : ""}`}
                      onClick={() => setEstado("")}
                    >
                      Ninguno
                    </button>
                    <button
                      className={`seg ${estado === "DEMOLIDO" ? "seg-activo" : ""}`}
                      onClick={() => setEstado("DEMOLIDO")}
                    >
                      Demolido
                    </button>
                    <button
                      className={`seg ${estado === "EN CONSTRUCCION" ? "seg-activo" : ""}`}
                      onClick={() => setEstado("EN CONSTRUCCION")}
                    >
                      En obra
                    </button>
                    <button
                      className={`seg ${estado === "DESOCUPADO" ? "seg-activo" : ""}`}
                      onClick={() => setEstado("DESOCUPADO")}
                    >
                      Desocupado
                    </button>
                  </div>
                </div>
              </>
            )}

            {/* MODO COMERCIAL */}
            {modo === "comercial" && (
              <>
                <div className="seccion">
                  <span className="filtro-rotulo">Medición</span>
                  <select
                    className="filtro-select"
                    value={fMedicion}
                    onChange={(e) => setFMedicion(e.target.value)}
                  >
                    {OPC_MEDICION.map((o) => (
                      <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
                    ))}
                  </select>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Facturación</span>
                  <select
                    className="filtro-select"
                    value={fFacturacion}
                    onChange={(e) => setFFacturacion(e.target.value)}
                  >
                    {OPC_FACTURACION.map((o) => (
                      <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
                    ))}
                  </select>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Consumo del mes</span>
                  <select
                    className="filtro-select"
                    value={fConsumo}
                    onChange={(e) => setFConsumo(e.target.value)}
                  >
                    {OPC_CONSUMO.map((o) => (
                      <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
                    ))}
                  </select>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Cartera</span>
                  <select
                    className="filtro-select"
                    value={fCartera}
                    onChange={(e) => setFCartera(e.target.value)}
                  >
                    {OPC_CARTERA.map((o) => (
                      <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
                    ))}
                  </select>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Ciclo</span>
                  <select
                    className="filtro-select"
                    value={fCiclo}
                    onChange={(e) => setFCiclo(e.target.value)}
                  >
                    <option value="todos">Todos</option>
                    {Array.from({ length: 23 }, (_, i) => String(i + 1)).map((c) => (
                      <option key={c} value={c}>Ciclo {c}</option>
                    ))}
                  </select>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Barrio</span>
                  {fBarrio ? (
                    <div className="barrio-elegido">
                      <span className="barrio-nombre">{fBarrio}</span>
                      <button
                        className="barrio-x"
                        onClick={() => { setFBarrio(""); setBarrioTexto(""); }}
                        aria-label="Quitar barrio"
                      >
                        ×
                      </button>
                    </div>
                  ) : (
                    <div className="barrio-buscar">
                      <input
                        className="filtro-campo"
                        placeholder="Escribe un barrio…"
                        value={barrioTexto}
                        onChange={(e) => setBarrioTexto(e.target.value)}
                      />
                      {barrioTexto.trim().length >= 2 && (
                        <ul className="barrio-lista">
                          {listaBarrios
                            .filter((b) =>
                              b.toLowerCase().includes(barrioTexto.trim().toLowerCase()),
                            )
                            .slice(0, 12)
                            .map((b) => (
                              <li key={b}>
                                <button
                                  className="barrio-opcion"
                                  onClick={() => { setFBarrio(b); setBarrioTexto(""); }}
                                >
                                  {b}
                                </button>
                              </li>
                            ))}
                        </ul>
                      )}
                    </div>
                  )}
                </div>
                <div className="seccion">
                  <p className="contador">{textoConteoComercial()}</p>
                  {hayFiltrosCom && (
                    <button className="btn-modo" onClick={limpiarComercial}>
                      Limpiar filtros
                    </button>
                  )}
                </div>
              </>
            )}

            {/* MODO RUTAS */}
            {modo === "rutas" && (
              <>
                <div className="seccion">
                  <span className="filtro-rotulo">Puntos de catastro de fondo</span>
                  <div className="filtro-segmentado">
                    <button
                      className={`seg ${filtroCatRuta === "ninguno" ? "seg-activo" : ""}`}
                      onClick={() => setFiltroCatRuta("ninguno")}
                    >
                      Sin puntos
                    </button>
                    <button
                      className={`seg ${filtroCatRuta === "con" ? "seg-activo" : ""}`}
                      onClick={() => setFiltroCatRuta("con")}
                    >
                      Con contrato
                    </button>
                    <button
                      className={`seg ${filtroCatRuta === "sin" ? "seg-activo" : ""}`}
                      onClick={() => setFiltroCatRuta("sin")}
                    >
                      Sin contrato
                    </button>
                  </div>
                </div>
                <div className="seccion">
                  <span className="filtro-rotulo">Ruta de lectura</span>
                  <select
                    className="filtro-select"
                    value={rutaSel}
                    onChange={(e) => setRutaSel(e.target.value)}
                  >
                    <option value="">Elige una ruta…</option>
                    {listaRutas.map((r) => (
                      <option key={r.ruta} value={r.ruta}>
                        Ruta {r.ruta} · ciclo {r.ciclo} · {r.predios} predios
                      </option>
                    ))}
                  </select>
                  {cargandoRuta && <p className="contador">Cargando recorrido…</p>}
                </div>

                {detalleRuta && !cargandoRuta && (
                  <div className="seccion">
                    <span className="filtro-rotulo">Calidad del recorrido</span>
                    <div className="ruta-metricas">
                      <MetricaFila etiqueta="Predios" valor={fmt(detalleRuta.metricas.predios)} />
                      <MetricaFila etiqueta="Distancia total" valor={`${fmt(detalleRuta.metricas.distancia_total)} m`} />
                      <MetricaFila etiqueta="Paso mediana" valor={`${detalleRuta.metricas.paso_mediana} m`} />
                      <MetricaFila etiqueta="Paso promedio" valor={`${detalleRuta.metricas.paso_prom} m`} />
                      <MetricaFila etiqueta="Paso p90" valor={`${detalleRuta.metricas.paso_p90} m`} />
                      <MetricaFila etiqueta="Paso p95" valor={`${detalleRuta.metricas.paso_p95} m`} />
                      <MetricaFila etiqueta="Paso máximo" valor={`${fmt(detalleRuta.metricas.paso_max)} m`} destacar />
                    </div>
                    <span className="filtro-rotulo" style={{ marginTop: 10 }}>Anomalías del recorrido</span>
                    <div className="ruta-metricas">
                      <MetricaFila etiqueta="Pasos largos (>100 m)" valor={fmt(detalleRuta.metricas.largos)} />
                      <MetricaFila etiqueta="Muy largos (>500 m)" valor={fmt(detalleRuta.metricas.muy_largos)} />
                      <MetricaFila etiqueta="Extremos (>1 km)" valor={fmt(detalleRuta.metricas.extremos)} destacar />
                    </div>
                    <p className="ruta-leyenda">
                      En el mapa: la línea azul es el recorrido y los tramos rojos son
                      pasos mayores a 100 m (el lector saltó lejos). El punto
                      verde es el inicio del recorrido y el amarillo, el final.
                    </p>
                  </div>
                )}
              </>
            )}

            {/* Apilados (común a todos los modos) */}
            {apilados && (
              <div className="panel">
                <div className="panel-head">
                  <span className="panel-title">
                    Predios en esta ubicación ({apilados.length})
                  </span>
                  <button className="btn-link" onClick={() => setApilados(null)}>
                    Cerrar
                  </button>
                </div>
                <ul className="resultados">
                  {apilados.map((p) => (
                    <li key={p.id}>
                      <button className="resultado" onClick={() => setPredioId(p.id)}>
                        <span className="mono resultado-contrato">
                          {p.clandestino || !p.cod_usuario || p.cod_usuario === "0"
                            ? "Sin contrato"
                            : p.cod_usuario}
                        </span>
                        <span className="mono resultado-cod">
                          {p.direccion ?? `#${p.id}`}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <PredioPanel id={predioId} onCerrar={() => setPredioId(null)} />

            <div className="leyenda">
              <span><i className="punto punto-normal" /> Con contrato asignado</span>
              <span><i className="punto punto-rojo" /> Sin contrato asignado (por verificar)</span>
              {estado && (
                <span><i className="punto punto-estado" /> {rotuloEstado(estado)}</span>
              )}
            </div>
          </aside>

          <main className="visor">
            <MapView
              accessToken={session.access_token}
              inicial={URL0?.inicial ?? null}
              filtro={filtro}
              estado={estado}
              mostrarTerrenos={mostrarTerrenos}
              base={base}
              modoTerrenos={modoTerrenos}
              modoActivo={modo as ModoMapa}
              filtroComercial={filtroComercial}
              puntosRuta={puntosRuta}
              filtroCatastroRuta={filtroCatRuta}
              onSeleccionar={(id) => {
                if (window.innerWidth <= 760) setPanelMovilAbierto(true);
                setApilados(null);
                setPredioId(id);
              }}
              onSeleccionarVarios={abrirApilados}
              onConteo={setConteo}
              onConteoComercial={setConteoCom}
              onStatsComercial={setStatsCom}
              onTerreno={setTerreno}
            />
            <Watermark email={email} />
            {modo === "comercial" && (
              <PanelIndicadores
                stats={statsCom}
                abierto={panelAbierto}
                onToggle={() => setPanelAbierto((v) => !v)}
              />
            )}
          </main>
        </div>
      )}
    </div>
  );
}

function MetricaFila({ etiqueta, valor, destacar }: {
  etiqueta: string; valor: string; destacar?: boolean;
}) {
  return (
    <div className="ruta-metrica-fila">
      <span className="ruta-metrica-et">{etiqueta}</span>
      <span className={`ruta-metrica-val ${destacar ? "destacar" : ""}`}>{valor}</span>
    </div>
  );
}

function rotuloEstado(e: FiltroEstado): string {
  if (e === "DEMOLIDO") return "Demolido";
  if (e === "EN CONSTRUCCION") return "En construcción";
  if (e === "DESOCUPADO") return "Desocupado";
  return "";
}
