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
} from "./components/MapView";
import { Buscador } from "./components/Buscador";
import { PredioPanel } from "./components/PredioPanel";
import { Watermark } from "./components/Watermark";
import { Admin } from "./components/Admin";
import { supabase } from "./lib/supabase";
import { api } from "./lib/api";

const fmt = (n: number) => n.toLocaleString("es-CO");

// Lee el estado de la vista desde el hash de la URL (#v=lng,lat,zoom&c=sin&e=DEMOLIDO&b=satelital&t=0)
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
  const [apilados, setApilados] = useState<PredioApilado[] | null>(null);
  const [esAdmin, setEsAdmin] = useState(false);
  const [vista, setVista] = useState<"mapa" | "admin">("mapa");
  const [filtro, setFiltro] = useState<FiltroContrato>(URL0?.filtro ?? "todos");
  const [estado, setEstado] = useState<FiltroEstado>(URL0?.estado ?? "");
  const [mostrarTerrenos, setMostrarTerrenos] = useState(URL0?.terrenos ?? true);
  const [base, setBase] = useState<BaseMapa>(URL0?.base ?? "calles");
  const [modoTerrenos, setModoTerrenos] = useState(false);
  const [terreno, setTerreno] = useState<TerrenoInfo | null>(null);
  const [conteo, setConteo] = useState<Conteo>({ disponible: false, con: 0, sin: 0 });
  const [copiado, setCopiado] = useState(false);

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

  if (cargando) {
    return <div className="pantalla-carga">Cargando…</div>;
  }
  if (!session) return <Login />;

  const email = session.user.email ?? "";

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

  // Al activar modo terrenos, apago el resaltado de estado (ambos tocan opacidad).
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
        // Si el navegador bloquea el portapapeles, al menos ponemos el hash en la URL.
        window.location.hash = p.toString();
      },
    );
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
          <span className="mono">{email}</span>
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
          <aside className="lateral">
            <Buscador onSeleccionar={irAPredio} />

            <div className="panel">
              <div className="panel-head">
                <span className="panel-title">Filtros</span>
              </div>

              <div className="filtro-grupo">
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
              </div>

              <p className="contador">{textoConteo()}</p>

              <div className="filtro-grupo">
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

              <div className="filtro-grupo">
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
              onSeleccionar={(id) => {
                setApilados(null);
                setPredioId(id);
              }}
              onSeleccionarVarios={abrirApilados}
              onConteo={setConteo}
              onTerreno={setTerreno}
            />
            <Watermark email={email} />
          </main>
        </div>
      )}
    </div>
  );
}

function rotuloEstado(e: FiltroEstado): string {
  if (e === "DEMOLIDO") return "Demolido";
  if (e === "EN CONSTRUCCION") return "En construcción";
  if (e === "DESOCUPADO") return "Desocupado";
  return "";
}
