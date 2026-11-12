import { useCallback, useEffect, useRef, useState } from "react";
import { apiDash, textoError, type DosisFila, type FiltrosRegistros } from "./apiDashboard";
import { fmtFecha, fmtInstante, fmtMiles } from "./formato";
import { formatearNumero } from "./numeros";

// Dashboard técnico · tarjeta «Dosis de coagulante (ppm)» dentro de Registros. Muestra las dosis registradas desde Entrada con los mismos filtros de la lista de Registros.
// La dosis sigue al ENVÍO: se excluye o reincluye desde la fila de Entrada («Excluir envío…»); aquí solo se ve su estado.
const PAGINA = 50;
const decimalesDe = (v: number) => (String(v).split(".")[1] ?? "").length;

/** ¿Aplica la tarjeta a estos filtros? La dosis es de Entrada y por planta: con otro formulario, punto o zona no hay nada que mostrar. */
export const dosisAplica = (f: FiltrosRegistros) => (!f.formulario || f.formulario === "entrada") && !f.punto && !f.zona;

export function DosisCoagulante({ filtros, senal }: { filtros: FiltrosRegistros; senal: string }) {
  const [filas, setFilas] = useState<DosisFila[]>([]);
  const [total, setTotal] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargandoMas, setCargandoMas] = useState(false);
  const [abierta, setAbierta] = useState(false);
  const version = useRef(0);

  const cargar = useCallback(async () => {
    const v = ++version.current;
    try {
      const r = await apiDash.dosis(filtros, { limite: PAGINA });
      if (v !== version.current) return;
      setFilas(r.dosis); setTotal(r.total); setError(null);
    } catch (e) { if (v === version.current) setError(textoError(e).texto); }
  }, [filtros]);
  // Se recarga con los filtros y cada vez que la lista de Registros cambia (la señal = total y registro más reciente).
  useEffect(() => { void cargar(); }, [cargar, senal]);

  async function cargarMas() {
    if (cargandoMas || filas.length === 0) return;
    setCargandoMas(true);
    try {
      const r = await apiDash.dosis(filtros, { despuesDe: filas[filas.length - 1].uso_id, limite: PAGINA });
      setFilas((x) => [...x, ...r.dosis]); setTotal(r.total);
    } catch (e) { setError(textoError(e).texto); } finally { setCargandoMas(false); }
  }

  return (
    <details className="td-dosis" open={abierta} onToggle={(e) => setAbierta((e.currentTarget as HTMLDetailsElement).open)} data-testid="tarjeta-dosis">
      <summary>Dosis de coagulante (ppm){total === null ? "" : ` · ${fmtMiles(total)} dosis`}</summary>
      <p className="td-sub">Se registra desde Entrada, por planta y con la misma fecha y hora del envío. Para excluirla, excluya el envío en su fila de Entrada (la dosis lo sigue).</p>
      {error ? <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => void cargar()}>Reintentar</button></div> : null}
      <div className="td-tabla-caja">
        <table className="td-tabla">
          <caption className="td-solo-lectores">Dosis de coagulante registradas desde Entrada</caption>
          <thead><tr><th>Muestra</th><th>Registro (servidor)</th><th>Planta</th><th>Coagulante</th><th className="td-der">Dosis</th><th>Autor</th><th>Marcas</th></tr></thead>
          <tbody>
            {filas.map((d) => (
              <FilaDosis key={d.uso_id} d={d} />
            ))}
            {total === 0 && !error ? <tr><td colSpan={7} className="td-vacio">No hay dosis con esos filtros.</td></tr> : null}
          </tbody>
        </table>
      </div>
      {total !== null && filas.length < total ? <div className="td-mas"><button type="button" className="td-boton-sec" onClick={cargarMas} disabled={cargandoMas}>{cargandoMas ? "Cargando…" : `Cargar más (${fmtMiles(total - filas.length)} restantes)`}</button></div> : null}
    </details>
  );
}

function FilaDosis({ d }: { d: DosisFila }) {
  return (
    <>
      <tr className={d.excluido ? "td-excluida" : undefined}>
        <td className="td-num">{fmtFecha(d.fecha_muestra)} {d.hora_muestra}</td>
        <td className="td-num">{fmtInstante(d.registrado_en)}</td>
        <td>{d.planta_nombre}</td>
        <td>{d.nombre_mostrar}</td>
        <td className="td-der td-valor">{formatearNumero(d.dosis, decimalesDe(d.dosis))} <span className="td-unidad">{d.unidad}</span></td>
        <td title={d.autor}>{d.autor.split("@")[0]}</td>
        <td><div className="td-marcas">{d.excluido ? <span className="td-marca td-marca-gris">Excluido</span> : null}</div></td>
      </tr>
      {d.excluido ? <tr className="td-excluida td-excluida-motivo"><td colSpan={7}>Excluida con su envío por {d.exclusion_autor?.split("@")[0] ?? "—"} el {fmtInstante(d.exclusion_en)} porque «{d.exclusion_motivo}».</td></tr> : null}
    </>
  );
}
