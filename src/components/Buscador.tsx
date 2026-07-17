import { useState } from "react";
import { api, type PredioResumen, type MedidorResumen } from "../lib/api";

type Item = PredioResumen | MedidorResumen;

type Props = {
  onSeleccionar: (id: number, x: number, y: number) => void;
  // Modo de búsqueda: por contrato (default) o por serial de medidor.
  modo?: "contrato" | "medidor";
};

export function Buscador({ onSeleccionar, modo = "contrato" }: Props) {
  const [q, setQ] = useState("");
  const [resultados, setResultados] = useState<Item[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const esMedidor = modo === "medidor";
  const minChars = esMedidor ? 5 : 2;
  const placeholder = esMedidor
    ? "Serial del medidor (mín. 5)"
    : "Contrato o código de usuario";

  async function buscar() {
    const texto = q.trim();
    if (texto.length < minChars) {
      setError(`Escribe al menos ${minChars} caracteres.`);
      return;
    }
    setBuscando(true);
    setError(null);
    try {
      const { resultados } = esMedidor
        ? await api.buscarMedidor(texto)
        : await api.buscar(texto);
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
          placeholder={placeholder}
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
              <span className="mono resultado-contrato">
                {esMedidor
                  ? (r as MedidorResumen).serial_medidor ?? "—"
                  : r.cod_usuario ?? "—"}
              </span>
              <span className="mono resultado-cod">
                {esMedidor
                  ? `${r.cod_usuario ?? "—"} · ${r.direccion ?? "—"}`
                  : r.direccion ?? "—"}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
