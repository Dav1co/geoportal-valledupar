import { useEffect, useState } from "react";
import { api } from "../lib/api";

type Props = { id: number | null; onCerrar: () => void };

// Campos ocultos en el panel (ruido técnico).
const OCULTOS = new Set(["geom", "GPS_X", "GPS_Y", "gps_x", "gps_y"]);

export function PredioPanel({ id, onCerrar }: Props) {
  const [predio, setPredio] = useState<Record<string, unknown> | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (id === null) { setPredio(null); return; }
    setCargando(true);
    setError(null);
    api
      .detalle(id)
      .then(({ predio }) => setPredio(predio))
      .catch((e) => setError(e instanceof Error ? e.message : "Error."))
      .finally(() => setCargando(false));
  }, [id]);

  if (id === null) return null;

  const campos = predio
    ? Object.entries(predio).filter(([k]) => !OCULTOS.has(k))
    : [];

  return (
    <div className="panel">
      <div className="panel-head">
        <span className="panel-title">Predio</span>
        <button className="btn-link" onClick={onCerrar}>Cerrar</button>
      </div>
      {cargando && <p className="hint">Consultando…</p>}
      {error && <p className="error">{error}</p>}
      {predio && (
        <dl className="detalle">
          {campos.map(([k, v]) => (
            <div className="detalle-fila" key={k}>
              <dt>{etiqueta(k)}</dt>
              <dd className="mono">{v === null || v === "" ? "—" : String(v)}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  );
}

function etiqueta(clave: string): string {
  return clave.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}
