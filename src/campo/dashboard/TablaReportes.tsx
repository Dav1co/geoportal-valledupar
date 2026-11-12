import { useEffect, useRef, useState } from "react";
import type { FilaReporte } from "./apiRevision";
import type { Columna, Contexto } from "./columnas";

// Tabla de reportes con ventana de filas visibles (sin librerías): pinta solo ~30 filas aunque haya decenas de miles. Orden por columna del registro; las filas ocultas se ven
// atenuadas y rotuladas (nunca se esconden en silencio). La descripción se recorta aquí y se ve completa en el detalle.
const ALTO_FILA = 40;
const anchoDe = (c: Columna): number => (c.clave === "descripcion" ? 300 : c.clave === "registrado_en" ? 140 : c.clave === "autor" ? 230 : c.clave === "tipo" ? 230 : c.clave === "grupo" ? 160
  : c.clave === "estado" || c.clave === "contrato" || c.clave === "subtipo" || c.clave === "resultado" || c.clave === "causal" ? 150 : c.tipo === "logico" ? 110 : c.tipo === "numero" ? 90 : 150);

export function TablaReportes({ filas, columnas, ctx, orden, onOrden, seleccionada, onSeleccion }: {
  filas: FilaReporte[]; columnas: Columna[]; ctx: Contexto; orden: { clave: string; dir: "asc" | "desc" } | null;
  onOrden: (clave: string) => void; seleccionada: string | null; onSeleccion: (id: string) => void;
}) {
  const caja = useRef<HTMLDivElement>(null);
  const [scroll, setScroll] = useState(0); const [alto, setAlto] = useState(520);
  useEffect(() => {
    const el = caja.current; if (!el) return;
    const act = () => setAlto(el.clientHeight || 520); act();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(act) : null; ro?.observe(el);
    return () => ro?.disconnect();
  }, []);
  const anchos = columnas.map(anchoDe); const total = anchos.reduce((a, b) => a + b, 0);
  const plantilla = anchos.map((w) => `${w}px`).join(" ");
  const ini = Math.max(0, Math.floor(scroll / ALTO_FILA) - 6); const fin = Math.min(filas.length, Math.ceil((scroll + alto) / ALTO_FILA) + 6);

  return (
    <div className="rv-tabla-caja" ref={caja} onScroll={(e) => setScroll(e.currentTarget.scrollTop)} role="table" aria-label="Reportes" aria-rowcount={filas.length + 1} aria-colcount={columnas.length}>
      <div className="rv-th" role="row" style={{ gridTemplateColumns: plantilla, width: total }}>
        {columnas.map((c) => (
          <div key={c.clave} role="columnheader" aria-sort={orden?.clave === c.clave ? (orden.dir === "asc" ? "ascending" : "descending") : "none"}>
            {c.ordenable ? <button type="button" className="rv-th-boton" onClick={() => onOrden(c.clave)}>{c.etiqueta}{orden?.clave === c.clave ? (orden.dir === "asc" ? " ▲" : " ▼") : ""}</button> : c.etiqueta}
          </div>
        ))}
      </div>
      {filas.length === 0 ? <p className="rv-vacio">No hay reportes con estos filtros.</p> : null}
      <div className="rv-cuerpo-tabla" style={{ height: filas.length * ALTO_FILA, width: total }}>
        {filas.slice(ini, fin).map((f, i) => (
          <div key={f.id} role="row" aria-rowindex={ini + i + 2} tabIndex={0} className={`rv-fila-t${f.oculto ? " rv-oculta" : ""}${seleccionada === f.id ? " rv-sel" : ""}`}
               style={{ top: (ini + i) * ALTO_FILA, height: ALTO_FILA, gridTemplateColumns: plantilla }} onClick={() => onSeleccion(f.id)} onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSeleccion(f.id); } }}>
            {columnas.map((c) => <div key={c.clave} role="cell" className={c.tipo === "numero" ? "rv-der" : undefined} title={c.clave === "descripcion" ? undefined : c.texto(f, ctx)}>{celda(c, f, ctx)}</div>)}
          </div>
        ))}
      </div>
    </div>
  );
}

function celda(c: Columna, f: FilaReporte, ctx: Contexto) {
  const t = c.texto(f, ctx);
  switch (c.clave) {
    case "riesgo_inmediato": return f.riesgo_inmediato ? <span className="rv-marca rv-marca-alerta">⚠ Riesgo</span> : <span className="rv-tenue">No</span>;
    case "oculto": return f.oculto ? <span className="rv-marca rv-marca-gris">Oculto</span> : <span className="rv-tenue">No</span>;
    case "fuera_de_zona": return f.fuera_de_zona ? <span className="rv-marca rv-marca-info">Fuera de zona</span> : <span className="rv-tenue">No</span>;
    case "estado": return <span className={`rv-estado rv-estado-${f.estado}`}>{t}</span>;
    case "contrato": return f.contrato ? <>{f.contrato}{f.contrato_verificado === false ? <span className="rv-marca rv-marca-amar" title="El contrato digitado no existe en la base comercial"> sin verificar</span> : null}</> : <span className="rv-tenue">—</span>;
    case "grupo_duplicados": return f.grupo_duplicados ? <span className="rv-marca rv-marca-dup" title="Posibles duplicados: el supervisor decide si los vincula">◎ {t}</span> : <span className="rv-tenue">—</span>;
    case "descripcion": return <span className="rv-corta">{t || "—"}</span>;
    default: return t === "" ? <span className="rv-tenue">—</span> : t;
  }
}
