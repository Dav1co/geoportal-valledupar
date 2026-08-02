import { useState } from "react";
import { api, type PredioResumen, type MedidorResumen } from "../lib/api";

type Item = PredioResumen | MedidorResumen;

type Criterio = "contrato" | "medidor" | "dir_catastro" | "dir_comercial";

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
  const [criterio, setCriterio] = useState<Criterio>(
    modo === "medidor" ? "medidor" : "contrato",
  );

  const esDir = criterio === "dir_catastro" || criterio === "dir_comercial";
  const minChars = esDir ? 6 : criterio === "medidor" ? 5 : 2;
  const placeholder =
    criterio === "medidor"
      ? "Serial del medidor (mín. 5)"
      : esDir
        ? "Dirección o parte de ella (mín. 6)"
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
      const { resultados } =
        criterio === "medidor"
          ? await api.buscarMedidor(texto)
          : criterio === "dir_catastro"
            ? await api.buscarDireccion(texto, "catastro")
            : criterio === "dir_comercial"
              ? await api.buscarDireccion(texto, "comercial")
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
      <select
        className="modo-sel buscador-criterio"
        value={criterio}
        onChange={(e) => {
          setCriterio(e.target.value as Criterio);
          setResultados([]);
          setError(null);
        }}
      >
        <option value="contrato">Buscar por contrato</option>
        <option value="medidor">Buscar por medidor</option>
        <option value="dir_catastro">Dirección (catastro)</option>
        <option value="dir_comercial">Dirección (base comercial)</option>
      </select>
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
                {criterio === "medidor"
                  ? (r as MedidorResumen).serial_medidor ?? "—"
                  : r.cod_usuario ?? "—"}
              </span>
              <span className="mono resultado-cod">
                {criterio === "medidor"
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
