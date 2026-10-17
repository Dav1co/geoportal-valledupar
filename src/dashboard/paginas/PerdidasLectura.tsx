import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { comoConsumoCicloDim, comoDesviacionDim, type ConsumoCicloDim, type DesviacionDim } from "../tipos";
import { PanelFiltros, TODOS } from "../PanelFiltros";
import { filtrosCicloUsoEstrato } from "../lecturaComun";
import { ConsumoRangosSeccion } from "./ConsumoRangosBasico";
import { MedidoresAntiguedad, ObservacionesLectura } from "./ContratosLectura";
import { CeroSostenido } from "./CeroSostenido";
import { ContratosCicloMedicion } from "./ContratosCicloMedicion";

// Secciones de lectura, medición y consumo de la pantalla de Pérdidas, debajo de «Lectura y medición».
// Orden: contratos y volumen por rango; medidores por antigüedad (con el promedio de consumo);
// observaciones de lectura; cero sostenido; contratos por ciclo con y sin medidor registrado; y, al final,
// los cambios de medidor entre periodos (CambiosMedidor, bi.v_cambio_medidor_dim).
// Tienen su propio panel de filtros (ciclo, uso, estrato) con las mismas reglas de Facturación
// desagregada: no afecta a las gráficas del IPUF de arriba. Medidores por antigüedad no usa ciclo.
// v_consumo_ciclo_dim y v_desviacion_dim se cargan aquí, cada una con su error y su reintento.

export function PerdidasLectura({ periodo, valores, onCambioValores }: { periodo: string; valores: Record<string, string>; onCambioValores: (v: Record<string, string>) => void }) {
  const [consumo, setConsumo] = useState<ConsumoCicloDim[] | null>(null);
  const [errorConsumo, setErrorConsumo] = useState<string | null>(null);
  const [desv, setDesv] = useState<DesviacionDim[] | null>(null);
  const [errorDesv, setErrorDesv] = useState<string | null>(null);

  function cargarConsumo() {
    setErrorConsumo(null);
    setConsumo(null);
    biCache("v_consumo_ciclo_dim", { periodo })
      .then((r) => setConsumo((r.datos ?? []).map(comoConsumoCicloDim)))
      .catch((e: Error) => setErrorConsumo(e.message));
  }
  function cargarDesv() {
    setErrorDesv(null);
    setDesv(null);
    biCache("v_desviacion_dim", { periodo })
      .then((r) => setDesv((r.datos ?? []).map(comoDesviacionDim)))
      .catch((e: Error) => setErrorDesv(e.message));
  }
  useEffect(() => { cargarConsumo(); cargarDesv(); }, [periodo]);   // eslint-disable-line react-hooks/exhaustive-deps

  // Opciones de ciclo, uso y estrato: las de consumo por ciclo (trae el ciclo 24 y todos los usos). En Pérdidas el estrato se ofrece
  // con uso «Todos» o «Residencial» (con «Todos» solo coinciden las filas residenciales, que son las que traen estrato).
  const filtros = useMemo(
    () => filtrosCicloUsoEstrato(
      (consumo ?? []).map((x) => x.ciclo),
      (consumo ?? []).map((x) => ({ uso: x.categoria, subcategoria: x.subcategoria })),
    ).map((f) => (f.id === "subcategoria"
      ? { ...f, visible: (v: Record<string, string>) => v.uso === TODOS || v.uso === "Residencial", ayuda: "El estrato solo aplica a uso Residencial." }
      : f)),
    [consumo],
  );

  // Si el uso pasa a uno no residencial, el panel limpia el estrato; aquí se explica por qué.
  const [aviso, setAviso] = useState("");
  function cambiarValores(nuevos: Record<string, string>) {
    const limpiado = valores.subcategoria !== TODOS && nuevos.subcategoria === TODOS && nuevos.uso !== TODOS && nuevos.uso !== "Residencial";
    setAviso(limpiado ? `Se limpió el estrato (${valores.subcategoria}) porque solo aplica a uso Residencial.` : "");
    onCambioValores(nuevos);
  }

  return (
    <div className="dash-con-panel">
      <PanelFiltros filtros={filtros} valores={valores} onCambio={cambiarValores} />
      <div className="dash-con-panel-cuerpo">
        {aviso ? <div className="dash-aviso">{aviso}</div> : null}
        <ConsumoRangosSeccion periodo={periodo} valores={valores} />
        <MedidoresAntiguedad periodo={periodo} valores={valores} />
        <ObservacionesLectura periodo={periodo} valores={valores} />
        <CeroSostenido periodo={periodo} datos={desv} error={errorDesv} onReintentar={cargarDesv} valores={valores} />
        <ContratosCicloMedicion
          periodo={periodo}
          datos={consumo}
          error={errorConsumo}
          onReintentar={cargarConsumo}
          valores={valores}
        />
      </div>
    </div>
  );
}
