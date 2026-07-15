import { useEffect, useState } from "react";
import { useSession } from "./auth/useSession";
import { Login } from "./auth/Login";
import { MapView, type PredioApilado, type FiltroContrato } from "./components/MapView";
import { Buscador } from "./components/Buscador";
import { PredioPanel } from "./components/PredioPanel";
import { Watermark } from "./components/Watermark";
import { Admin } from "./components/Admin";
import { supabase } from "./lib/supabase";
import { api } from "./lib/api";

export default function App() {
  const { session, cargando } = useSession();
  const [predioId, setPredioId] = useState<number | null>(null);
  const [apilados, setApilados] = useState<PredioApilado[] | null>(null);
  const [esAdmin, setEsAdmin] = useState(false);
  const [vista, setVista] = useState<"mapa" | "admin">("mapa");
  const [filtro, setFiltro] = useState<FiltroContrato>("todos");
  const [mostrarTerrenos, setMostrarTerrenos] = useState(true);

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

              <label className="filtro-check">
                <input
                  type="checkbox"
                  checked={mostrarTerrenos}
                  onChange={(e) => setMostrarTerrenos(e.target.checked)}
                />
                Mostrar terrenos
              </label>
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
            </div>
          </aside>

          <main className="visor">
            <MapView
              accessToken={session.access_token}
              filtro={filtro}
              mostrarTerrenos={mostrarTerrenos}
              onSeleccionar={(id) => {
                setApilados(null);
                setPredioId(id);
              }}
              onSeleccionarVarios={abrirApilados}
            />
            <Watermark email={email} />
          </main>
        </div>
      )}
    </div>
  );
}
