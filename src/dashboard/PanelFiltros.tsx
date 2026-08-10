import { useState } from "react";

// Panel de filtros CONTEXTUAL y reutilizable — lo usan las tres
// pantallas "detallado" (5 Facturación, 6 Recaudo, 7 Cartera).
//
// Principios:
//  · Cada pantalla DECLARA qué filtros soporta; el panel muestra solo
//    esos. Nunca un control que no haga nada.
//  · Un filtro puede ser condicional: `visible(valores)` decide si
//    aparece según el estado de los demás. Caso real: el estrato solo
//    tiene sentido con uso Residencial, porque en el resto la
//    subcategoría trae el diámetro de la acometida.
//  · El filtrado ocurre en el NAVEGADOR sobre el preagregado del
//    período, que se trae una sola vez: cada clic es instantáneo y no
//    vuelve a pagar el guardián de la Edge Function.
//  · Al ocultarse un filtro, su valor se limpia: un filtro invisible
//    nunca sigue restringiendo los datos a espaldas del usuario.

export type DefFiltro = {
  id: string;
  etiqueta: string;
  opciones: string[];
  visible?: (valores: Record<string, string>) => boolean;
  ayuda?: string;
  // Añade un campo de búsqueda sobre las opciones. Necesario cuando la
  // lista es larga (barrios, conceptos): quien busca uno concreto y no
  // recuerda a qué comuna pertenece no debe quedar atrapado en la
  // jerarquía del desplegable.
  buscable?: boolean;
};

export const TODOS = "todos";

function normalizar(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

type Props = {
  filtros: DefFiltro[];
  valores: Record<string, string>;
  onCambio: (valores: Record<string, string>) => void;
  resumen?: string;
};

export function PanelFiltros({ filtros, valores, onCambio, resumen }: Props) {
  const [busquedas, setBusquedas] = useState<Record<string, string>>({});
  const visibles = filtros.filter((f) => !f.visible || f.visible(valores));
  const activos = visibles.filter((f) => (valores[f.id] ?? TODOS) !== TODOS).length;

  // La búsqueda filtra las opciones del desplegable; si deja una sola,
  // se puede elegir directamente desde el resultado.
  function opcionesDe(f: DefFiltro): string[] {
    const q = normalizar(busquedas[f.id] ?? "").trim();
    if (!f.buscable || !q) return f.opciones;
    return f.opciones.filter((o) => normalizar(o).includes(q));
  }

  function cambiar(id: string, valor: string) {
    const nuevos = { ...valores, [id]: valor };
    // Limpia los filtros que dejaron de ser visibles con este cambio.
    for (const f of filtros) {
      if (f.visible && !f.visible(nuevos)) nuevos[f.id] = TODOS;
    }
    onCambio(nuevos);
  }

  function limpiar() {
    onCambio(Object.fromEntries(filtros.map((f) => [f.id, TODOS])));
    setBusquedas({});
  }

  return (
    <aside className="dash-panel">
      <div className="dash-panel-tope">
        <span className="dash-panel-tit">Filtros</span>
        {activos > 0 && (
          <button className="dash-panel-limpiar" onClick={limpiar}>
            Limpiar ({activos})
          </button>
        )}
      </div>

      {visibles.map((f) => {
        const ops = opcionesDe(f);
        const q = busquedas[f.id] ?? "";
        return (
          <label key={f.id} className="dash-panel-campo">
            <span>{f.etiqueta}</span>
            {f.buscable && (
              <input
                className="dash-panel-buscar"
                type="search"
                value={q}
                placeholder={`Buscar en ${f.opciones.length}…`}
                onChange={(e) => setBusquedas({ ...busquedas, [f.id]: e.target.value })}
              />
            )}
            <select value={valores[f.id] ?? TODOS} onChange={(e) => cambiar(f.id, e.target.value)}>
              <option value={TODOS}>Todos</option>
              {ops.map((o) => (
                <option key={o} value={o}>{o}</option>
              ))}
            </select>
            {f.buscable && q && (
              <em>
                {ops.length === 0
                  ? "Sin coincidencias"
                  : `${ops.length} de ${f.opciones.length}`}
              </em>
            )}
            {f.ayuda && <em>{f.ayuda}</em>}
          </label>
        );
      })}

      {resumen && <div className="dash-panel-resumen">{resumen}</div>}
      <div className="dash-panel-nota">
        Los filtros se aplican al instante sobre los datos del período: no
        vuelven a consultar la base.
      </div>
    </aside>
  );
}
