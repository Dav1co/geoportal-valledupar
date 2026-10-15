import { useEffect, useMemo, useState } from "react";
import { biCache, limpiarCacheBi } from "./cacheBi";
import { comoKpiAnio, comoKpiMes, type KpiAnio, type KpiMes } from "./tipos";
import { etiquetaPeriodo } from "./formato";
import { SelectorPeriodo } from "./SelectorPeriodo";
import { Resumen } from "./paginas/Resumen";
import { ROTULO } from "./rotulos";
import { FacturacionAgrupado } from "./paginas/FacturacionAgrupado";
import { RecaudoAgrupado } from "./paginas/RecaudoAgrupado";
import { CarteraAgrupado } from "./paginas/CarteraAgrupado";
import { FacturacionDetallado } from "./paginas/FacturacionDetallado";
import { RecaudoDetallado } from "./paginas/RecaudoDetallado";
import { CarteraDetallado } from "./paginas/CarteraDetallado";
import { Pqr } from "./paginas/Pqr";
import { Notas } from "./paginas/Notas";
import { Cupones } from "./paginas/Cupones";
import { RecaudoDiario } from "./paginas/RecaudoDiario";
import { Perdidas } from "./paginas/Perdidas";
import { Consolidado } from "./paginas/Consolidado";
import "./dashboard.css";

// El tablero se estructura por FUENTE de datos: las pantallas "agrupado"
// dan histórico largo y no llevan panel de filtros; las "detallado" dan
// 6 períodos y sí lo llevan.
// Cada pantalla declara su FUENTE: con ella se sabe qué períodos puede
// mostrar realmente (estándar de huecos), en vez de suponer que todo
// período del selector tiene datos.
const PAGINAS = [
  { id: "resumen", titulo: "Resumen ejecutivo", fuente: "facturacion_agrupado" },
  { id: "facturacion-agrupado", titulo: ROTULO.facturacionConsolidada, fuente: "facturacion_agrupado" },
  { id: "recaudo-agrupado", titulo: ROTULO.recaudoConsolidado, fuente: "recaudo_agrupado" },
  { id: "cartera-agrupado", titulo: ROTULO.carteraConsolidada, fuente: "cartera_resumen" },
  { id: "facturacion-detallado", titulo: ROTULO.facturacionDesagregada, fuente: "facturacion_contratos" },
  { id: "recaudo-detallado", titulo: ROTULO.recaudoDesagregado, fuente: "recaudo_detalle" },
  { id: "cartera-detallado", titulo: ROTULO.carteraDesagregada, fuente: "cartera_edades" },
  { id: "pqr", titulo: "PQR", fuente: "reclamos" },
  { id: "notas", titulo: "Notas", fuente: "notas" },
  { id: "cupones", titulo: "Cupones", fuente: "cupones_pagos" },
  // Las dos siguientes NO se rigen por el selector mensual como las
  // demás: el recaudo diario va por delante (mes en curso, se reemplaza
  // cada día) y el IPUF va por detrás (llega con un mes de rezago). Su
  // fuente queda vacía a propósito: v_periodos_fuente no las declara,
  // así que el selector no debe marcarles huecos que no existen.
  { id: "recaudo-diario", titulo: "Recaudo diario", fuente: "" },
  { id: "perdidas", titulo: "Pérdidas (IPUF)", fuente: "" },
  { id: "consolidado", titulo: "Consolidado", fuente: "facturacion_agrupado" },
] as const;
type PaginaId = (typeof PAGINAS)[number]["id"];

// Pantallas que reciben `comparado` y muestran Δ contra otro período. En las
// demás el control "Comparar con" no hace nada, así que se oculta.
const PAGINAS_CON_COMPARACION: ReadonlySet<PaginaId> = new Set<PaginaId>([
  "resumen",
  "facturacion-agrupado",
  "recaudo-agrupado",
  "cartera-agrupado",
]);

// Modo Dashboard del geoportal (Tablero Comercial).
// Entrega 2: pantalla Resumen ejecutivo servida por bi.v_kpi_mes.
export function Dashboard() {
  const [filas, setFilas] = useState<KpiMes[] | null>(null);
  const [anios, setAnios] = useState<KpiAnio[]>([]);
  // Mapa de huecos: qué períodos tiene realmente cada fuente.
  const [periodosFuente, setPeriodosFuente] = useState<{ fuente: string; periodo: string }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [periodo, setPeriodo] = useState<string | null>(null);
  const [comparado, setComparado] = useState<string | null>(null);
  const [pagina, setPagina] = useState<PaginaId>("resumen");
  // Cambia al pulsar "Actualizar": va como key de la pantalla activa, así
  // que la remonta y vuelve a pedir con el caché ya vacío.
  const [recarga, setRecarga] = useState(0);

  // Cambiar el período limpia la comparación solo si ahora coincidiría con
  // él (comparar un período contra sí mismo no dice nada).
  function cambiarPeriodo(p: string) {
    setPeriodo(p);
    setComparado((c) => (c === p ? null : c));
  }

  // Al entrar a una pantalla que no compara, la comparación se descarta.
  function cambiarPagina(id: PaginaId) {
    setPagina(id);
    if (!PAGINAS_CON_COMPARACION.has(id)) setComparado(null);
  }

  function actualizarDatos() {
    limpiarCacheBi();
    setRecarga((v) => v + 1);
    cargar();
  }

  function cargar() {
    setError(null);
    setFilas(null);
    Promise.all([biCache("v_kpi_mes"), biCache("v_kpi_anio"), biCache("v_periodos_fuente")])
      .then(([mes, anio, pf]) => {
        setPeriodosFuente(
          (pf.datos ?? []).map((r) => ({ fuente: String(r.fuente ?? ""), periodo: String(r.periodo ?? "") })),
        );
        const datos = (mes.datos ?? [])
          .map(comoKpiMes)
          .filter((f) => /^\d{6}$/.test(f.periodo))
          .sort((a, b) => b.periodo.localeCompare(a.periodo));
        setAnios((anio.datos ?? []).map(comoKpiAnio));
        setFilas(datos);
        // El ancla: último período con facturación cargada.
        const ancla = datos.find((f) => f.facturado != null)?.periodo ?? null;
        setPeriodo((p) => p ?? ancla);
      })
      .catch((e: Error) => setError(e.message));
  }

  useEffect(cargar, []);

  const ancla = useMemo(
    () => filas?.find((f) => f.facturado != null)?.periodo ?? null,
    [filas],
  );
  // Períodos que la pantalla ACTIVA puede mostrar.
  const fuenteActiva = PAGINAS.find((p) => p.id === pagina)?.fuente ?? "";
  const disponiblesPagina = useMemo(
    () => periodosFuente.filter((x) => x.fuente === fuenteActiva).map((x) => x.periodo).sort(),
    [periodosFuente, fuenteActiva],
  );

  const desdeDetalle = useMemo(() => {
    if (!filas) return null;
    const conDetalle = filas.filter((f) => f.contratos_activos != null);
    return conDetalle.length ? conDetalle[conDetalle.length - 1].periodo : null;
  }, [filas]);

  return (
    <div className="dash">
      <div className="dash-tope">
        <div>
          <h2>{PAGINAS.find((p) => p.id === pagina)?.titulo}</h2>
          <span className="dash-sub">Tablero Comercial · EMDUPAR S.A. E.S.P.</span>
        </div>
        <div className="dash-tope-der">
          {ancla && (
            <span className="dash-chip">
              Corte mensual: {etiquetaPeriodo(ancla)}
            </span>
          )}
          <button
            className="dash-actualizar"
            onClick={actualizarDatos}
            title="Vuelve a consultar la base. Úsalo si acaba de entrar un mes nuevo."
          >
            ↻ Actualizar
          </button>
          {filas && filas.length > 0 && periodo && (
            <SelectorPeriodo
              periodos={filas.map((f) => f.periodo)}
              valor={periodo}
              onCambio={cambiarPeriodo}
              comparado={comparado}
              onComparado={setComparado}
              conComparacion={PAGINAS_CON_COMPARACION.has(pagina)}
              sinDatos={disponiblesPagina}
              nota={
                desdeDetalle
                  ? `Detalle por contrato disponible desde ${etiquetaPeriodo(desdeDetalle)}`
                  : undefined
              }
            />
          )}
        </div>
      </div>

      <nav className="dash-nav">
        {PAGINAS.map((p) => (
          <button
            key={p.id}
            className={pagina === p.id ? "activa" : ""}
            onClick={() => cambiarPagina(p.id)}
          >
            {p.titulo}
          </button>
        ))}
      </nav>

      {error && (
        <div className="dash-estado">
          <p>No se pudo cargar el tablero: {error}</p>
          <button className="dash-boton" onClick={cargar}>
            Reintentar
          </button>
        </div>
      )}

      {!error && !filas && <div className="dash-estado">Cargando indicadores…</div>}

      {!error && filas && filas.length === 0 && (
        <div className="dash-estado">
          Aún no hay períodos cargados en el esquema de hechos. El tablero se
          activa con el primer cargue mensual.
        </div>
      )}

      {!error && filas && filas.length > 0 && periodo && pagina === "resumen" && (
        <Resumen key={recarga} filas={filas} anios={anios} periodo={periodo} comparado={comparado} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "facturacion-agrupado" && (
        <FacturacionAgrupado key={recarga} periodo={periodo} comparado={comparado} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "recaudo-agrupado" && (
        <RecaudoAgrupado key={recarga} periodo={periodo} comparado={comparado} kpis={filas} anios={anios} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "cartera-agrupado" && (
        <CarteraAgrupado key={recarga} periodo={periodo} comparado={comparado} kpis={filas} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "facturacion-detallado" && (
        <FacturacionDetallado key={recarga} periodo={periodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "recaudo-detallado" && (
        <RecaudoDetallado key={recarga} periodo={periodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "cartera-detallado" && (
        <CarteraDetallado key={recarga} periodo={periodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "pqr" && (
        <Pqr key={recarga} periodo={periodo} onIrAPeriodo={cambiarPeriodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "notas" && (
        <Notas key={recarga} periodo={periodo} onIrAPeriodo={cambiarPeriodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "cupones" && (
        <Cupones key={recarga} periodo={periodo} onIrAPeriodo={cambiarPeriodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "recaudo-diario" && (
        <RecaudoDiario key={recarga} periodo={periodo} onIrAPeriodo={cambiarPeriodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "perdidas" && (
        <Perdidas key={recarga} periodo={periodo} onIrAPeriodo={cambiarPeriodo} />
      )}
      {!error && filas && filas.length > 0 && periodo && pagina === "consolidado" && (
        <Consolidado key={recarga} periodo={periodo} />
      )}
    </div>
  );
}
