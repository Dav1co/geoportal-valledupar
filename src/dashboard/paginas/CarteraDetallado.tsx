import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import {
  comoCarteraContratosDim,
  comoCarteraDetalleDim,
  type CarteraContratosDim,
  type CarteraDetalleDim,
} from "../tipos";
import { etiquetaPeriodo, fmtEntero, fmtMillones, fmtPct } from "../formato";
import { BarrasHorizontales, Dona, TablaPlegable } from "../graficas";
import { SinDatos } from "../SinDatos";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";

// Tramos de edad: rampa secuencial de un tono, igual que Cartera
// agrupado, porque la antigüedad es una magnitud ordenada.
const COLOR_TRAMO: Record<string, string> = {
  "Hasta 60 días": "#8FB4CE",
  "60 a 180 días": "#4FA3C7",
  "180 a 360 días": "#2E7D9E",
  "Más de 360 días": "#0A2540",
};

const TOP_BARRIOS = 20;

type Props = { periodo: string };

export function CarteraDetallado({ periodo }: Props) {
  const [datos, setDatos] = useState<CarteraDetalleDim[] | null>(null);
  const [contratos, setContratos] = useState<CarteraContratosDim[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({
    comuna: TODOS, barrio: TODOS, ciclo: TODOS, uso: TODOS, subcategoria: TODOS,
  });

  function cargar() {
    setError(null);
    setDatos(null);
    Promise.all([
      biCache("v_cartera_detalle_dim", { periodo }),
      biCache("v_cartera_contratos_dim", { periodo }),
    ])
      .then(([d, c]) => {
        setDatos((d.datos ?? []).map(comoCarteraDetalleDim));
        setContratos((c.datos ?? []).map(comoCarteraContratosDim));
      })
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, [periodo]);

  const filtros: DefFiltro[] = useMemo(() => {
    const d = datos ?? [];
    const unicos = (f: (x: CarteraDetalleDim) => string) =>
      [...new Set(d.map(f))].sort((a, b) => a.localeCompare(b, "es"));
    // El barrio se acota a la comuna elegida: 350 barrios en una lista
    // plana son inmanejables, y comuna → barrio es jerarquía natural.
    const barrios = [...new Set(
      d.filter((x) => valores.comuna === TODOS || x.comuna === valores.comuna).map((x) => x.barrio),
    )].sort((a, b) => a.localeCompare(b, "es"));
    return [
      { id: "comuna", etiqueta: "Comuna", opciones: unicos((x) => x.comuna) },
      { id: "barrio", etiqueta: "Barrio", opciones: barrios, buscable: true, ayuda: "Se acota a la comuna elegida" },
      { id: "ciclo", etiqueta: "Ciclo", opciones: unicos((x) => x.ciclo) },
      { id: "uso", etiqueta: "Uso", opciones: unicos((x) => x.uso) },
      {
        id: "subcategoria",
        etiqueta: "Estrato",
        visible: (v) => v.uso === "Residencial",
        opciones: [...new Set(
          d.filter((x) => x.uso === "Residencial").map((x) => x.subcategoria),
        )].sort((a, b) => a.localeCompare(b, "es")),
        ayuda: "Solo aplica a uso Residencial",
      },
    ];
  }, [datos, valores.comuna]);

  const filtrado = useMemo(() => {
    const d = datos ?? [];
    return d.filter(
      (x) =>
        (valores.comuna === TODOS || x.comuna === valores.comuna) &&
        (valores.barrio === TODOS || x.barrio === valores.barrio) &&
        (valores.ciclo === TODOS || x.ciclo === valores.ciclo) &&
        (valores.uso === TODOS || x.uso === valores.uso) &&
        (valores.subcategoria === TODOS || x.subcategoria === valores.subcategoria),
    );
  }, [datos, valores]);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar la cartera detallada: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!datos) return <div className="dash-estado">Cargando detalle de cartera…</div>;
  if (datos.length === 0) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="detalle de cartera (se conservan solo 6 períodos)"
        disponibles={[]}
      />
    );
  }

  const suma = (campo: keyof CarteraDetalleDim) =>
    filtrado.reduce((s, x) => s + ((x[campo] as number | null) ?? 0), 0);

  const cartera = suma("cartera");
  const tHasta60 = suma("t_hasta_60");
  const t60180 = suma("t_60_180");
  const t180360 = suma("t_180_360");
  const tMay360 = suma("t_may_360");
  const carteraTotalPeriodo = (datos ?? []).reduce((s, x) => s + (x.cartera ?? 0), 0);

  // Contratos con deuda del corte: cartera_contrato no tiene barrio, así
  // que solo se cruza por las dimensiones que ambas comparten.
  const contratosCorte = contratos.filter(
    (c) =>
      (valores.ciclo === TODOS || c.ciclo === valores.ciclo) &&
      (valores.uso === TODOS || c.uso === valores.uso) &&
      (valores.subcategoria === TODOS || c.estrato === valores.subcategoria),
  );
  const conDeuda = contratosCorte.reduce((s, c) => s + (c.contratos_con_deuda ?? 0), 0);
  const filtraBarrio = valores.barrio !== TODOS || valores.comuna !== TODOS;

  // La financiada por barrio: cartera total menos los tramos de edad.
  const noFinanciada = tHasta60 + t60180 + t180360 + tMay360;
  const financiada = cartera - noFinanciada;
  const carteraInferida = filtrado
    .filter((x) => x.comuna_origen === "catastro")
    .reduce((s, x) => s + (x.cartera ?? 0), 0);
  const pctInferida = cartera ? (carteraInferida / cartera) * 100 : 0;

  const donaTramos = [
    { etiqueta: "Hasta 60 días", valor: tHasta60 },
    { etiqueta: "60 a 180 días", valor: t60180 },
    { etiqueta: "180 a 360 días", valor: t180360 },
    { etiqueta: "Más de 360 días", valor: tMay360 },
  ].map((t) => ({
    ...t,
    color: COLOR_TRAMO[t.etiqueta],
    pct: noFinanciada ? (t.valor / noFinanciada) * 100 : null,
  }));

  const agrupar = (clave: (x: CarteraDetalleDim) => string) => {
    const m = new Map<string, number>();
    for (const x of filtrado) m.set(clave(x), (m.get(clave(x)) ?? 0) + (x.cartera ?? 0));
    return [...m.entries()].map(([etiqueta, valor]) => ({ etiqueta, valor }));
  };

  const porBarrio = agrupar((x) => x.barrio).sort((a, b) => b.valor - a.valor);
  const porComuna = agrupar((x) => x.comuna).sort((a, b) => b.valor - a.valor);
  const porCiclo = agrupar((x) => x.ciclo).sort((a, b) => a.etiqueta.localeCompare(b.etiqueta, "es"));

  // Barrios con mayor peso de cartera vieja: el foco real de cobranza.
  const criticos = [...filtrado.reduce((m, x) => {
    const a = m.get(x.barrio) ?? { cartera: 0, vieja: 0 };
    a.cartera += x.cartera ?? 0;
    a.vieja += x.t_may_360 ?? 0;
    m.set(x.barrio, a);
    return m;
  }, new Map<string, { cartera: number; vieja: number }>()).entries()]
    .filter(([, a]) => a.cartera > 0)
    .map(([barrio, a]) => ({ barrio, ...a, pct: (a.vieja / a.cartera) * 100 }))
    .sort((a, b) => b.vieja - a.vieja)
    .slice(0, TOP_BARRIOS);

  return (
    <div className="dash-con-panel">
      <PanelFiltros
        filtros={filtros}
        valores={valores}
        onCambio={setValores}
        resumen={`${fmtMillones(cartera)} · ${porBarrio.length} barrio(s)`}
      />

      <div className="dash-con-panel-cuerpo">
        <div className="dash-aviso">
          La <b>cartera del corte</b> es el total, con la deuda financiada
          incluida; los <b>tramos de antigüedad</b> cubren solo la parte no
          financiada, porque los acuerdos de pago no tienen edad asignada. La
          diferencia entre ambos es justamente la cartera financiada, que aquí
          puede verse por barrio.
          {pctInferida > 0 && (
            <>
              {" "}Además, <b>{fmtPct(pctInferida)} de esta cartera
              ({fmtMillones(carteraInferida)})</b> se muestra con la comuna
              <b> completada desde el catastro</b>: en el sistema comercial esos
              predios —los de la comuna 2— no tienen comuna asignada. Es un dato
              correcto pero derivado; conviene advertirlo si se usa en un informe
              oficial.
            </>
          )}
        </div>

        <div className="dash-kpis">
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Cartera del corte</div>
            <div className="dash-valor num">{fmtMillones(cartera)}</div>
            <div className="dash-sub2">
              {cartera < carteraTotalPeriodo
                ? `${fmtPct((cartera / carteraTotalPeriodo) * 100)} de la cartera no financiada`
                : "sin filtros aplicados"}
            </div>
          </div>
          <div className="dash-carta dash-kpi dash-kpi-mal">
            <div className="dash-eti">Más de 360 días</div>
            <div className="dash-valor num">{fmtMillones(tMay360)}</div>
            <div className="dash-sub2">
              {fmtPct(cartera ? (tMay360 / cartera) * 100 : null)} del corte · difícil recaudo
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Barrios en el corte</div>
            <div className="dash-valor num">{fmtEntero(porBarrio.length)}</div>
            <div className="dash-sub2">de {porComuna.length} comuna(s)</div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Contratos con deuda</div>
            <div className="dash-valor num">{filtraBarrio ? "—" : fmtEntero(conDeuda)}</div>
            <div className="dash-sub2">
              {filtraBarrio
                ? "no disponible al filtrar por territorio"
                : "según el detalle por contrato"}
            </div>
          </div>
          <div className="dash-carta dash-kpi">
            <div className="dash-eti">Cartera financiada</div>
            <div className="dash-valor num">{fmtMillones(financiada)}</div>
            <div className="dash-sub2">
              {fmtPct(cartera ? (financiada / cartera) * 100 : null)} del corte ·
              acuerdos de pago, sin edad asignada
            </div>
          </div>
        </div>

        <div className="dash-fila-g3">
          <div className="dash-carta">
            <h3>Barrios con mayor cartera — {etiquetaPeriodo(periodo)}</h3>
            <BarrasHorizontales
              datos={porBarrio.slice(0, TOP_BARRIOS)}
              formatoValor={fmtMillones}
            />
            <TablaPlegable titulo={`Datos: cartera por barrio (${porBarrio.length})`}>
              <table className="dash-tabla num">
                <thead><tr><th>Barrio</th><th>Cartera</th><th>%</th></tr></thead>
                <tbody>
                  {porBarrio.map((b) => (
                    <tr key={b.etiqueta}>
                      <td>{b.etiqueta}</td>
                      <td className="num">{fmtMillones(b.valor)}</td>
                      <td className="num">{fmtPct(cartera ? (b.valor / cartera) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">
              La gráfica muestra los {TOP_BARRIOS} de mayor cartera; la tabla
              trae los {porBarrio.length} del corte completo.
            </div>
          </div>

          <div className="dash-carta">
            <h3>Antigüedad de la cartera no financiada</h3>
            <Dona partes={donaTramos} formatoTitulo={fmtMillones} />
            <TablaPlegable titulo="Datos: antigüedad">
              <table className="dash-tabla num">
                <thead><tr><th>Tramo</th><th>Cartera</th><th>%</th></tr></thead>
                <tbody>
                  {donaTramos.map((t) => (
                    <tr key={t.etiqueta}>
                      <td>{t.etiqueta}</td>
                      <td className="num">{fmtMillones(t.valor)}</td>
                      <td className="num">{fmtPct(t.pct)}</td>
                    </tr>
                  ))}
                  <tr className="dash-total">
                    <td>Total no financiada</td>
                    <td className="num">{fmtMillones(noFinanciada)}</td>
                    <td className="num">100,0 %</td>
                  </tr>
                </tbody>
              </table>
            </TablaPlegable>
          </div>
        </div>

        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Foco de cobranza: barrios con más deuda vieja</h3>
            <div className="dash-tabla-scroll">
              <table className="dash-tabla num">
                <thead>
                  <tr><th>Barrio</th><th>&gt; 360 días</th><th>Cartera total</th><th>% vieja</th></tr>
                </thead>
                <tbody>
                  {criticos.map((c) => (
                    <tr key={c.barrio}>
                      <td>{c.barrio}</td>
                      <td className="num">{fmtMillones(c.vieja)}</td>
                      <td className="num">{fmtMillones(c.cartera)}</td>
                      <td className={`num ${c.pct > 85 ? "dash-neg" : ""}`}>{fmtPct(c.pct)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="dash-nota">
              Ordenado por monto de deuda mayor a 360 días, no por porcentaje: un
              barrio pequeño con 100 % de deuda vieja pesa menos que uno grande
              con 80 %. El porcentaje se resalta por encima del 85 %.
            </div>
          </div>

          <div className="dash-carta">
            <h3>Cartera por ciclo</h3>
            <BarrasHorizontales datos={porCiclo} formatoValor={fmtMillones} color="#0E7C86" />
            <TablaPlegable titulo="Datos: cartera por ciclo">
              <table className="dash-tabla num">
                <thead><tr><th>Ciclo</th><th>Cartera</th><th>%</th></tr></thead>
                <tbody>
                  {porCiclo.map((c) => (
                    <tr key={c.etiqueta}>
                      <td>{c.etiqueta}</td>
                      <td className="num">{fmtMillones(c.valor)}</td>
                      <td className="num">{fmtPct(cartera ? (c.valor / cartera) * 100 : null)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TablaPlegable>
          </div>
        </div>
      </div>
    </div>
  );
}
