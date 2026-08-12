import { useEffect, useMemo, useState } from "react";
import {
  trazar, renumerar, moverGrupo, aCSV, longitudLinea,
  type Capturado, type PuntoRuta, type Vertice,
} from "../lib/trazado";

// Panel del trazador de rutas. Vive dentro del modo Rutas, que ya está
// protegido por el permiso correspondiente: si el usuario no lo tiene,
// App.tsx nunca lo monta.
//
// No escribe en la base. El resultado es una PROPUESTA de reordenamiento
// que sale en CSV; hechos.rutas_consecutivos no se toca.

export type EstadoTrazo = "inactivo" | "trazando" | "cerrado";

type Props = {
  ciclo: string;
  ruta: string;
  puntos: PuntoRuta[];          // los de la ruta CON geometría
  sinUbicar: number;            // los de la ruta que no cruzan con el mapa
  estado: EstadoTrazo;
  linea: Vertice[];
  radio: number;
  onRadio: (m: number) => void;
  onIniciar: () => void;
  onDeshacer: () => void;
  onCerrar: () => void;
  onCancelar: () => void;
  onResultado: (c: Capturado[], noCapturados: PuntoRuta[]) => void;
};

export function TrazadorRuta({
  ciclo, ruta, puntos, sinUbicar, estado, linea, radio,
  onRadio, onIniciar, onDeshacer, onCerrar, onCancelar, onResultado,
}: Props) {
  const [excluidos, setExcluidos] = useState<Set<string>>(new Set());
  const [orden, setOrden] = useState<Capturado[] | null>(null);

  // Resultado del corredor. Se recalcula solo al cerrar el trazo o al
  // mover el radio, nunca en cada movimiento del ratón: son cientos de
  // puntos contra decenas de segmentos.
  const bruto = useMemo(() => {
    if (estado !== "cerrado" || linea.length < 2) return null;
    return trazar(puntos, linea, radio);
  }, [estado, puntos, linea, radio]);

  // El ajuste manual se aplica encima del resultado bruto.
  const capturados = useMemo(() => {
    if (!bruto) return [];
    const base = orden ?? bruto.capturados;
    return renumerar(base, excluidos);
  }, [bruto, orden, excluidos]);

  // Avisar al mapa para que pinte la numeración y los no capturados.
  // Va en useEffect y no en useMemo: es un efecto secundario, no un
  // valor derivado. onResultado queda fuera de las dependencias a
  // proposito -App.tsx la recrea en cada render y la incluiria en un
  // bucle-; lo que importa es que cambien los datos.
  useEffect(() => {
    if (bruto) onResultado(capturados, bruto.noCapturados);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [capturados, bruto]);

  const grupos = useMemo(
    () => [...new Set(capturados.map((c) => c.grupo))],
    [capturados],
  );

  function descargar() {
    const csv = aCSV(capturados);
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `ruta_${ciclo}_${ruta}_propuesta.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // ---- ruta sin predios ubicables: no hay nada que trazar ----
  if (puntos.length === 0) {
    return (
      <div className="trazador">
        <div className="trazador-aviso">
          <b>Esta ruta no tiene predios ubicables en el mapa.</b>
          <p>
            La ruta {ruta} del ciclo {ciclo} tiene {sinUbicar}{" "}
            {sinUbicar === 1 ? "contrato" : "contratos"}, pero ninguno cruza con
            el catastro georreferenciado, así que no se puede trazar el
            recorrido. Elige otra ruta.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="trazador">
      {sinUbicar > 0 && (
        <p className="trazador-nota">
          {puntos.length} de {puntos.length + sinUbicar} predios ubicables.
          Los {sinUbicar} restantes no cruzan con el catastro y no pueden
          entrar en el trazo.
        </p>
      )}

      {/* ---- controles del trazo ---- */}
      {estado === "inactivo" && (
        <button className="dash-boton" onClick={onIniciar}>
          Trazar recorrido
        </button>
      )}

      {estado === "trazando" && (
        <>
          <p className="trazador-nota">
            Haz clic sobre el mapa siguiendo el recorrido del lector.
            {linea.length > 0 && (
              <> Llevas <b>{linea.length}</b>{" "}
                {linea.length === 1 ? "vértice" : "vértices"}
                {linea.length > 1 && <> · {longitudLinea(linea)} m</>}.
              </>
            )}
          </p>
          <div className="trazador-botones">
            <button className="dash-boton" onClick={onDeshacer} disabled={!linea.length}>
              Deshacer
            </button>
            <button className="dash-boton" onClick={onCerrar} disabled={linea.length < 2}>
              Cerrar trazo
            </button>
            <button className="dash-boton dash-boton-suave" onClick={onCancelar}>
              Cancelar
            </button>
          </div>
        </>
      )}

      {/* ---- radio del corredor ---- */}
      {estado !== "inactivo" && (
        <label className="trazador-radio">
          <span>Radio del corredor: <b>{radio} m</b></span>
          <input
            type="range" min={5} max={50} step={1} value={radio}
            onChange={(e) => onRadio(Number(e.target.value))}
          />
        </label>
      )}

      {/* ---- resultado ---- */}
      {bruto && (
        <>
          <div className="trazador-resumen">
            <div><b>{capturados.length}</b> capturados</div>
            <div><b>{grupos.length}</b> consecutivos</div>
            <div><b>{bruto.noCapturados.length}</b> sin capturar</div>
            <div><b>{bruto.longitudLinea}</b> m de recorrido</div>
          </div>

          {bruto.noCapturados.length > 0 && (
            <p className="trazador-nota">
              Hay {bruto.noCapturados.length} predios de la ruta que la línea no
              tocó, resaltados en rojo. Amplía el radio, alarga el trazo, o
              déjalos fuera a conciencia.
            </p>
          )}

          <div className="trazador-tabla-scroll">
            <table className="dash-tabla">
              <thead>
                <tr>
                  <th>Nuevo</th><th>Actual</th><th>Contrato</th>
                  <th>Tipo</th><th>m</th><th />
                </tr>
              </thead>
              <tbody>
                {capturados.map((c, i) => {
                  const primeroDelGrupo =
                    i === 0 || capturados[i - 1].grupo !== c.grupo;
                  return (
                    <tr key={c.contrato} className={c.tipo === "agrupado" ? "agrupado" : ""}>
                      <td className="num">{primeroDelGrupo ? c.consecutivoNuevo : ""}</td>
                      <td className="num">{c.consecutivoActual}</td>
                      <td>{c.contrato}</td>
                      <td>{c.tipo === "agrupado" ? "agrupado" : "único"}</td>
                      <td className="num">{c.distanciaLinea}</td>
                      <td className="trazador-acciones">
                        {primeroDelGrupo && (
                          <>
                            <button
                              title="Subir este consecutivo"
                              onClick={() => setOrden(moverGrupo(capturados, c.grupo, -1))}
                            >↑</button>
                            <button
                              title="Bajar este consecutivo"
                              onClick={() => setOrden(moverGrupo(capturados, c.grupo, 1))}
                            >↓</button>
                          </>
                        )}
                        <button
                          title="Excluir del resultado"
                          onClick={() =>
                            setExcluidos((s) => new Set(s).add(c.contrato))
                          }
                        >×</button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {excluidos.size > 0 && (
            <p className="trazador-nota">
              {excluidos.size} excluidos.{" "}
              <button className="enlace" onClick={() => setExcluidos(new Set())}>
                Devolverlos
              </button>
            </p>
          )}

          <div className="trazador-botones">
            <button className="dash-boton" onClick={descargar} disabled={!capturados.length}>
              Exportar CSV
            </button>
            <button className="dash-boton dash-boton-suave" onClick={onCancelar}>
              Empezar de nuevo
            </button>
          </div>
          <p className="trazador-nota">
            El CSV es una propuesta: no modifica la ruta en el sistema
            comercial.
          </p>
        </>
      )}
    </div>
  );
}
