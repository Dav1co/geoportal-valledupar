import { etiquetaPeriodo } from "./formato";

// ESTÁNDAR DEL TABLERO ante períodos sin datos.
//
// Los huecos son la norma en estos archivos, no la excepción: junio 2026
// sin detalle de recaudo, 202506 y 202607 sin PQR, reclamos solo desde
// 2025. Una pantalla nunca debe quedar en blanco ni mostrar un cero que
// parezca real — un mes sin archivo NO es un mes con cero reclamos.
//
// Esta pieza dice siempre tres cosas: qué falta, desde cuándo hay datos
// y cuál es el último período disponible.
export function SinDatos({
  periodo,
  fuente,
  disponibles,
  onIr,
}: {
  periodo: string;
  fuente: string;
  disponibles: string[];   // períodos que la pantalla SÍ puede mostrar
  onIr?: (p: string) => void;
}) {
  const ordenados = [...disponibles].sort();
  const primero = ordenados[0];
  const ultimo = ordenados[ordenados.length - 1];

  // Huecos internos: períodos ausentes entre el primero y el último.
  const faltantes: string[] = [];
  if (primero && ultimo) {
    let a = Number(primero.slice(0, 4)), m = Number(primero.slice(4));
    while (`${a}${String(m).padStart(2, "0")}` <= ultimo) {
      const p = `${a}${String(m).padStart(2, "0")}`;
      if (!disponibles.includes(p)) faltantes.push(p);
      m += 1;
      if (m > 12) { m = 1; a += 1; }
    }
  }

  return (
    <div className="dash-estado">
      <p>
        <b>No hay datos de {fuente} para {etiquetaPeriodo(periodo)}.</b>
      </p>
      {ordenados.length === 0 ? (
        <p>Esta fuente aún no tiene ningún período cargado.</p>
      ) : (
        <>
          <p>
            Hay datos desde <b>{etiquetaPeriodo(primero)}</b> hasta{" "}
            <b>{etiquetaPeriodo(ultimo)}</b>
            {faltantes.length > 0 && (
              <>
                , con {faltantes.length}{" "}
                {faltantes.length === 1 ? "mes faltante" : "meses faltantes"} en
                medio ({faltantes.map(etiquetaPeriodo).join(", ")})
              </>
            )}
            .
          </p>
          {onIr && (
            <button className="dash-boton" onClick={() => onIr(ultimo)}>
              Ver {etiquetaPeriodo(ultimo)}
            </button>
          )}
        </>
      )}
    </div>
  );
}

// Aviso en línea para cuando la pantalla SÍ tiene datos del período pero
// la serie histórica está incompleta: explica que los huecos de las
// gráficas son meses sin archivo, no meses en cero.
export function AvisoHuecos({ faltantes }: { faltantes: string[] }) {
  if (faltantes.length === 0) return null;
  return (
    <div className="dash-aviso">
      La serie tiene {faltantes.length}{" "}
      {faltantes.length === 1 ? "mes sin archivo" : "meses sin archivo"} (
      {faltantes.map(etiquetaPeriodo).join(", ")}). En las gráficas aparecen
      como <b>hueco, no como cero</b>: no se recibieron esos datos, lo cual es
      distinto de que no hubiera actividad.
    </div>
  );
}

// Calcula los períodos ausentes entre el primero y el último de una lista.
export function huecosDe(disponibles: string[]): string[] {
  const ordenados = [...disponibles].sort();
  if (ordenados.length < 2) return [];
  const primero = ordenados[0], ultimo = ordenados[ordenados.length - 1];
  const faltan: string[] = [];
  let a = Number(primero.slice(0, 4)), m = Number(primero.slice(4));
  while (`${a}${String(m).padStart(2, "0")}` <= ultimo) {
    const p = `${a}${String(m).padStart(2, "0")}`;
    if (!ordenados.includes(p)) faltan.push(p);
    m += 1;
    if (m > 12) { m = 1; a += 1; }
  }
  return faltan;
}
