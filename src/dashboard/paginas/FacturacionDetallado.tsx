import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoConsumoCicloDim,
  comoDesviacionDim,
  comoFactDetalleDim,
  type ConsumoCicloDim,
  type DesviacionDim,
  type FactDetalleDim,
} from "../tipos";
import { etiquetaCiclo, etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct, numeroCiclo } from "../formato";
import { BarrasHorizontales, Dona, TablaPlegable } from "../graficas";
import { SinDatos } from "../SinDatos";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { ContratosCicloMedicion } from "./ContratosCicloMedicion";
import { ContratosDesviacion } from "./ContratosDesviacion";

const COLOR_USO: Record<string, string> = {
  Residencial: "#0A2540",
  Comercial: "#0E7C86",
  Oficial: "#C98A2D",
  Especial: "#8FB4CE",
  Industrial: "#7B5EA7",
};

const NOMBRE_CONCEPTO: Record<number, string> = {
  1: "Cargo fijo acueducto",
  2: "Consumo acueducto",
  3: "Cargo fijo alcantarillado",
  4: "Servicio alcantarillado",
};

type Props = { periodo: string };

export function FacturacionDetallado({ periodo }: Props) {
  const [datos, setDatos] = useState<FactDetalleDim[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Sección "Contratos por ciclo, medición y consumo cero": su propia carga y
  // su propio error, para que un fallo aquí no afecte al resto de la pantalla.
  const [consumo, setConsumo] = useState<ConsumoCicloDim[] | null>(null);
  const [errorConsumo, setErrorConsumo] = useState<string | null>(null);
  // Sección "Contratos con desviación significativa": igual, carga propia.
  const [desv, setDesv] = useState<DesviacionDim[] | null>(null);
  const [errorDesv, setErrorDesv] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({
    ciclo: TODOS, uso: TODOS, subcategoria: TODOS,
  });

  // Una sola llamada por período: los datos de un período son fijos
  // hasta el cargue siguiente. Al cambiar de período se vuelve a pedir.
  function cargar() {
    setError(null);
    setDatos(null);
    biCache("v_fact_detalle_dim", { periodo })
      .then((r) => setDatos((r.datos ?? []).map(comoFactDetalleDim)))
      .catch((e: Error) => setError(e.message));
    cargarConsumo();
    cargarDesv();
  }
  function cargarConsumo() {
    setErrorConsumo(null);
    setConsumo(null);
    biCache("v_consumo_ciclo_dim", { periodo })
      .then((r) => setConsumo((r.datos ?? []).map(comoConsumoCicloDim)))
      .catch((e: Error) => setErrorConsumo(e.message));
  }
  function cargarDesv() {
    setErrorDesv(null);
    setDesv(null);
    biCache("v_desviacion_dim", { periodo })
      .then((r) => setDesv((r.datos ?? []).map(comoDesviacionDim)))
      .catch((e: Error) => setErrorDesv(e.message));
  }
  useEffect(cargar, [periodo]);

  const filtros: DefFiltro[] = useMemo(() => {
    const d = datos ?? [];
    const unicos = (f: (x: FactDetalleDim) => string) =>
      [...new Set(d.map(f))].sort((a, b) => a.localeCompare(b, "es"));
    return [
      // Ciclos de la facturación ('CICLO 05') y de consumo ('5'), unidos y
      // comparados por número: así el 24 se puede filtrar aunque la facturación
      // todavía no lo traiga (sus bloques quedan en cero).
      {
        id: "ciclo",
        etiqueta: "Ciclo de facturación",
        opciones: [
          ...new Set(
            [...d.map((x) => x.ciclo), ...(consumo ?? []).map((x) => x.ciclo)]
              .map(numeroCiclo)
              .filter((n): n is number => n != null),
          ),
        ]
          .sort((a, b) => a - b)
          .map(etiquetaCiclo),
      },
      { id: "uso", etiqueta: "Uso", opciones: unicos((x) => x.uso) },
      {
        id: "subcategoria",
        etiqueta: "Estrato",
        // Solo con uso Residencial la subcategoría es el estrato; en el
        // resto trae el diámetro de la acometida.
        visible: (v) => v.uso === "Residencial",
        opciones: unicos((x) => (x.uso === "Residencial" ? x.subcategoria : "")).filter(Boolean),
        ayuda: "Solo aplica a uso Residencial",
      },
    ];
  }, [datos, consumo]);

  // Filtrado en el navegador: instantáneo, sin volver a la base.
  const filtrado = useMemo(() => {
    const d = datos ?? [];
    return d.filter(
      (x) =>
        (valores.ciclo === TODOS || numeroCiclo(x.ciclo) === numeroCiclo(valores.ciclo)) &&
        (valores.uso === TODOS || x.uso === valores.uso) &&
        (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
    );
  }, [datos, valores]);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar el detalle: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!datos) return <div className="dash-estado">Cargando detalle del período…</div>;
  if (datos.length === 0) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="detalle por contrato (se conservan solo 6 períodos)"
        disponibles={[]}
      />
    );
  }

  const sumar = (
    campo: "contratos" | "facturado" | "consumo",
    filtro?: (x: FactDetalleDim) => boolean,
  ) =>
    filtrado.reduce((s, x) => (!filtro || filtro(x) ? s + (x[campo] ?? 0) : s), 0);

  const suscAcue = sumar("contratos", (x) => x.concepto_num === 1);
  const suscAlc = sumar("contratos", (x) => x.concepto_num === 3);
  const m3Acue = sumar("consumo", (x) => x.concepto_num === 2);
  const m3Alc = sumar("consumo", (x) => x.concepto_num === 4);
  const neto = sumar("facturado");
  const subsidios = sumar("facturado", (x) => (x.concepto_num ?? 0) >= 26 && (x.concepto_num ?? 0) <= 29);
  const contribuciones = sumar("facturado", (x) => (x.concepto_num ?? 0) >= 30 && (x.concepto_num ?? 0) <= 33);
  const bruta = sumar("facturado", (x) => !((x.concepto_num ?? 0) >= 26 && (x.concepto_num ?? 0) <= 33));
  const consumoMedio = suscAcue > 0 ? m3Acue / suscAcue : null;

  // Agrupaciones para las gráficas (todas sobre el corte filtrado).
  const agrupar = (clave: (x: FactDetalleDim) => string, filtro?: (x: FactDetalleDim) => boolean) => {
    const m = new Map<string, number>();
    for (const x of filtrado) {
      if (filtro && !filtro(x)) continue;
      m.set(clave(x), (m.get(clave(x)) ?? 0) + (x.contratos ?? 0));
    }
    return m;
  };
  const facturadoPor = (clave: (x: FactDetalleDim) => string) => {
    const m = new Map<string, number>();
    for (const x of filtrado) m.set(clave(x), (m.get(clave(x)) ?? 0) + (x.facturado ?? 0));
    return m;
  };

  const porCiclo = [...facturadoPor((x) => x.ciclo).entries()]
    .sort((a, b) => a[0].localeCompare(b[0], "es"))
    .map(([etiqueta, valor]) => ({ etiqueta, valor }));

  const porUso = [...agrupar((x) => x.uso, (x) => x.concepto_num === 1).entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([etiqueta, valor]) => ({
      etiqueta,
      valor,
      color: COLOR_USO[etiqueta] ?? "#C9D4DC",
      pct: suscAcue > 0 ? (valor / suscAcue) * 100 : null,
    }));

  const porEstrato = [...agrupar(
    (x) => x.subcategoria,
    (x) => x.concepto_num === 1 && x.uso === "Residencial",
  ).entries()]
    .sort((a, b) => a[0].localeCompare(b[0], "es"))
    .map(([etiqueta, valor]) => ({ etiqueta, valor }));

  const porConcepto = [...filtrado.reduce((m, x) => {
    const k = x.concepto_num ?? 0;
    const a = m.get(k) ?? { contratos: 0, facturado: 0, consumo: 0 };
    a.contratos += x.contratos ?? 0;
    a.facturado += x.facturado ?? 0;
    a.consumo += x.consumo ?? 0;
    m.set(k, a);
    return m;
  }, new Map<number, { contratos: number; facturado: number; consumo: number }>()).entries()]
    .sort((a, b) => Math.abs(b[1].facturado) - Math.abs(a[1].facturado))
    .slice(0, 25);

  const resumenPanel = `${fmtEntero(suscAcue)} contratos · ${fmtMillones(neto)}`;

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={resumenPanel}
      />

      <div className="dash-con-panel-cuerpo">
        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Suscriptores acueducto</div>
            <div className="dash-valor num">{fmtEntero(suscAcue)}</div>
            <div className="dash-sub2">contratos con cargo fijo (concepto 1)</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Suscriptores alcantarillado</div>
            <div className="dash-valor num">{fmtEntero(suscAlc)}</div>
            <div className="dash-sub2">concepto 3</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">m³ acueducto</div>
            <div className="dash-valor num">{fmtEntero(m3Acue)}</div>
            <div className="dash-sub2 num">
              {consumoMedio != null
                ? `${consumoMedio.toLocaleString("es-CO", { maximumFractionDigits: 1 })} m³ por suscriptor`
                : "—"}
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">m³ alcantarillado</div>
            <div className="dash-valor num">{fmtEntero(m3Alc)}</div>
            <div className="dash-sub2">concepto 4</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Facturación neta</div>
            <div className="dash-valor num">{fmtMillones(neto)}</div>
            <div className="dash-sub2 num">bruta {fmtMillones(bruta)}</div>
          </div>
          <div className="dash-carta dash-kpi dash-kpi-mal">
            <div className="dash-eti">Déficit de subsidios y aportes</div>
            <div className="dash-valor num">{fmtMillones(Math.abs(subsidios + contribuciones))}</div>
            <div className="dash-sub2 num">
              subsidios {fmtMillones(subsidios)} · aportes {fmtMillones(contribuciones)}
            </div>
          </div>
        </div>

        <div className="dash-fila-g3">
          <div className="dash-carta">
            <h3>Facturación por ciclo</h3>
            <BarrasHorizontales datos={porCiclo} formatoValor={fmtMillones} />
            <TablaPlegable titulo="Datos: facturación por ciclo">
              <table className="dash-tabla num">
                <thead><tr><th>Ciclo</th><th>Facturado</th><th>%</th></tr></thead>
                <tbody>
                  {porCiclo.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtMillones(c.valor)}</td>
                      <td className="num">{fmtPct(neto ? (c.valor / neto) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>

          <div className="dash-carta">
            <h3>Suscriptores por uso</h3>
            <Dona partes={porUso} formatoTitulo={(v) => `${fmtEntero(v)} contratos`} />
            <TablaPlegable titulo="Datos: suscriptores por uso">
              <table className="dash-tabla num">
                <thead><tr><th>Uso</th><th>Contratos</th><th>%</th></tr></thead>
                <tbody>
                  {porUso.map((u) => (
                    <tr key={u.etiqueta}>
                      <td>{u.etiqueta}</td>
                      <td className="num">{fmtEntero(u.valor)}</td>
                      <td className="num">{fmtPct(u.pct)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>
        </div>

        {porEstrato.length > 0 && (
          <div className="dash-fila">
            <div className="dash-carta">
              <h3>Suscriptores residenciales por estrato</h3>
              <BarrasHorizontales datos={porEstrato} formatoValor={fmtEntero} color="#0E7C86" />
              <TablaPlegable titulo="Datos: suscriptores por estrato">
                <table className="dash-tabla num">
                  <thead><tr><th>Estrato</th><th>Contratos</th><th>%</th></tr></thead>
                  <tbody>
                    {porEstrato.map((e) => {
                      const total = porEstrato.reduce((s, x) => s + x.valor, 0);
                      return (
                        <tr key={e.etiqueta}>
                          <td>{e.etiqueta}</td>
                          <td className="num">{fmtEntero(e.valor)}</td>
                          <td className="num">{fmtPct(total ? (e.valor / total) * 100 : null)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </TablaPlegable>
              <div className="dash-nota">
                Solo uso Residencial: en los demás usos la subcategoría es el
                diámetro de la acometida, no el estrato.
              </div>
            </div>
          </div>
        )}

        <div className="dash-fila">
          <div className="dash-carta">
            <h3>Facturación por concepto — {etiquetaPeriodo(periodo)}</h3>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr><th>Concepto</th><th>Contratos</th><th>Facturado</th><th>m³</th></tr>
                </thead>
                <tbody>
                  {porConcepto.map(([num, a]) => (
                    <tr key={num}>
                      <td>{num}{NOMBRE_CONCEPTO[num] ? ` · ${NOMBRE_CONCEPTO[num]}` : ""}</td>
                      <td className="num">{fmtEntero(a.contratos)}</td>
                      <td className={`num ${a.facturado < 0 ? "dash-neg" : ""}`}>{fmtMillones(a.facturado)}</td>
                      <td className="num">{num === 2 || num === 4 ? fmtEntero(a.consumo) : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="dash-nota">
              Los 25 conceptos de mayor peso. La columna m³ solo aplica a los
              conceptos 2 y 4: en los demás la columna de consumo del sistema
              trae otra magnitud (base de cálculo), no metros cúbicos.
            </div>
          </div>
        </div>

        <ContratosCicloMedicion
          periodo={periodo}
          datos={consumo}
          error={errorConsumo}
          onReintentar={cargarConsumo}
          valores={valores}
        />

        <ContratosDesviacion
          periodo={periodo}
          datos={desv}
          error={errorDesv}
          onReintentar={cargarDesv}
          valores={valores}
        />
      </div>
    </div>
  );
}
