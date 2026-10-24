import { useCallback, useEffect, useState } from "react";
import { apiTec, ErrorTec, type ResumenResp } from "./apiTecnica";
import { formatearOGuion } from "./numeros";

// Resumen de las últimas 24 horas (promedio, mínimo y máximo) de las dos plantas, sin autor y sin registros excluidos. Datos reales del servidor.
// El operador nunca recibe registros individuales, rangos, marcas ni la hora del servidor.
export function ResumenUltimas24({ formulario, version }: { formulario: string; version: number }) {
  const [datos, setDatos] = useState<ResumenResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(() => {
    let vivo = true;
    setCargando(true);
    apiTec.resumen(formulario)
      .then((r) => { if (vivo) { setDatos(r); setError(null); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e.message : "No se pudo cargar el resumen."); })
      .finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
  }, [formulario]);

  useEffect(() => cargar(), [cargar, version]);

  return (
    <section className="tec-tarjeta" aria-labelledby="tec-resumen-tit">
      <div className="tec-resumen-cab">
        <div>
          <h2 id="tec-resumen-tit">Resumen de las últimas 24 horas</h2>
          <p className="tec-sub">De las dos plantas, sin autor y sin registros excluidos.</p>
        </div>
        <button type="button" className="tec-boton-sec tec-boton-corto" onClick={() => cargar()} disabled={cargando}>{cargando ? "Cargando…" : "Actualizar"}</button>
      </div>
      {error ? <p className="tec-error-caja" role="alert">{error} <button type="button" className="tec-enlace" onClick={() => cargar()}>Reintentar</button></p> : null}
      {datos ? (
        <div className="tec-tabla" role="table" aria-label="Resumen de las últimas 24 horas">
          <div role="row" className="tec-fila tec-fila-cab">
            <div role="columnheader">Variable</div><div role="columnheader" className="tec-der">Prom.</div><div role="columnheader" className="tec-der">Mín.</div><div role="columnheader" className="tec-der">Máx.</div>
          </div>
          {datos.filas.map((f) => (
            <div role="row" className="tec-fila" key={`${f.variable}@${f.planta ?? ""}`}>
              <div role="cell">{f.planta_nombre ? `${f.nombre} ${f.planta_nombre}` : f.nombre}<span className="tec-unidad-chica">{f.unidad}</span></div>
              <div role="cell" className="tec-der tec-num">{formatearOGuion(f.promedio, f.decimales)}</div>
              <div role="cell" className="tec-der tec-num">{formatearOGuion(f.minimo, f.decimales)}</div>
              <div role="cell" className="tec-der tec-num">{formatearOGuion(f.maximo, f.decimales)}</div>
            </div>
          ))}
          {datos.filas.length === 0 ? <p className="tec-sub">Este formulario todavía no tiene variables.</p> : null}
        </div>
      ) : cargando ? <p className="tec-sub">Cargando el resumen…</p> : null}
    </section>
  );
}
