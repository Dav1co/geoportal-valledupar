import { useState } from "react";
import { api, type PredioResumen } from "../lib/api";

type Props = { onSeleccionar: (id: number, x: number, y: number) => void };

export function Buscador({ onSeleccionar }: Props) {
  const [q, setQ] = useState("");
  const [resultados, setResultados] = useState<PredioResumen[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function buscar() {
    const texto = q.trim();
    if (texto.length < 2) return;
    setBuscando(true);
    setError(null);
    try {
      const { resultados } = await api.buscar(texto);
      setResultados(resultados);
      if (resultados.length === 0) setError("Sin coincidencias.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error en la búsqueda.");
    } finally {
      setBuscando(false);
    }
  }

  return (
    <div className="buscador">
      <div className="buscador-input">
        <input
          className="field mono"
          placeholder="Contrato o código de usuario"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && buscar()}
        />
        <button className="btn-sm" onClick={buscar} disabled={buscando}>
          {buscando ? "…" : "Buscar"}
        </button>
      </div>

      {error && <p className="hint">{error}</p>}

      <ul className="resultados">
        {resultados.map((r) => (
          <li key={r.id}>
            <button
              className="resultado"
              onClick={() => onSeleccionar(r.id, r.gps_x, r.gps_y)}
            >
              <span className="mono resultado-contrato">{r.cod_usuario ?? "—"}</span>
              <span className="mono resultado-cod">{r.direccion ?? "—"}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
