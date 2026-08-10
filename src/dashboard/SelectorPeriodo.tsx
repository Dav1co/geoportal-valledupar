import { etiquetaPeriodo } from "./formato";

// Control de período reutilizable por todas las pantallas del tablero:
// (a) elegir cualquier período realmente disponible para el dato en uso,
// (b) comparar contra un segundo período (las tarjetas muestran Δ y %).
// El llamador decide qué períodos ofrecer: los históricos permiten muchos
// meses; lo nacido del detalle solo los 6 retenidos (y lo dice en `nota`).
type Props = {
  periodos: string[]; // AAAAMM, de más reciente a más antiguo
  valor: string;
  onCambio: (p: string) => void;
  comparado: string | null;
  onComparado: (p: string | null) => void;
  nota?: string;
  // Períodos que la pantalla activa SÍ puede mostrar. Los demás se
  // marcan "(sin datos)": el usuario ve que existen pero sabe que esa
  // pantalla no los tiene, en vez de elegir uno y encontrar vacío.
  sinDatos?: string[];
};

export function SelectorPeriodo({
  periodos,
  valor,
  onCambio,
  comparado,
  onComparado,
  nota,
  sinDatos,
}: Props) {
  const marca = (p: string) =>
    sinDatos && sinDatos.length > 0 && !sinDatos.includes(p)
      ? `${etiquetaPeriodo(p)} (sin datos)`
      : etiquetaPeriodo(p);
  return (
    <div className="dash-selper">
      <label>
        <span>Período</span>
        <select value={valor} onChange={(e) => onCambio(e.target.value)}>
          {periodos.map((p) => (
            <option key={p} value={p}>
              {marca(p)}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>Comparar con</span>
        <select
          value={comparado ?? ""}
          onChange={(e) => onComparado(e.target.value || null)}
        >
          <option value="">Sin comparación</option>
          {periodos
            .filter((p) => p !== valor)
            .map((p) => (
              <option key={p} value={p}>
                {marca(p)}
              </option>
            ))}
        </select>
      </label>
      {nota && <span className="dash-selper-nota">{nota}</span>}
    </div>
  );
}
