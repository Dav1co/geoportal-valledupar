import { useEffect, useState, type ReactNode } from "react";
import { biCache } from "./cacheBi";
import { etiquetaPeriodo } from "./formato";

// Texto para una sección de consumo/lectura sin datos en el período: si `activo` (alguna rama llegó
// vacía), consulta los períodos que tiene la fuente consumo_metodo y dice entre qué meses hay datos.
export function useVacioConsumo(activo: boolean): ReactNode {
  const [disp, setDisp] = useState<string[] | "error" | null>(null);
  useEffect(() => {
    if (!activo) return;
    biCache("v_periodos_fuente")
      .then((r) =>
        setDisp(
          (r.datos ?? [])
            .filter((x) => String(x.fuente) === "consumo_metodo")
            .map((x) => String(x.periodo))
            .sort(),
        ),
      )
      .catch(() => setDisp("error"));
  }, [activo]);
  return (
    <div className="dash-estado">
      <p>Sin datos de esta sección para este período.</p>
      {disp == null || disp === "error" || disp.length === 0 ? null : (
        <p>
          Hay datos de consumo desde <b>{etiquetaPeriodo(disp[0])}</b> hasta{" "}
          <b>{etiquetaPeriodo(disp[disp.length - 1])}</b>.
        </p>
      )}
    </div>
  );
}
