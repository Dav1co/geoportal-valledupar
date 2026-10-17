import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { SinDatos } from "../SinDatos";
import { comoIpuf, type Ipuf } from "../tipos";
import {
  etiquetaCorta,
  etiquetaPeriodo,
  fmtEntero,
  fmtIpuf,
  fmtMillones,
  fmtPct,
} from "../formato";
import { BarrasMensuales, LineasPorcentaje, TablaPlegable, colorAnio } from "../graficas";
import { excesoSobreMeta, resumenAnual } from "../ipufAnual";
import { IndicesAnualesSeccion, IpufAnualBloque } from "./PerdidasAnual";
import { IndicadoresLectura } from "./IndicadoresLectura";
import { PerdidasLectura } from "./PerdidasLectura";
import { SubmedicionExplicacion, SubmedicionVejez } from "./SubmedicionVejez";
import { ReclamosMetodoPerdidas } from "./ReclamosMetodoPerdidas";
import { MapaCalor } from "./MapaCalor";
import { MarcaFiltro, Plegable, usePlegables } from "../Plegable";
import { normalizarFiltrosLectura, normalizarFiltrosSubmedicion, useEstadoSesion } from "../memoriaSesion";
import { TODOS } from "../PanelFiltros";
import { CambiosMedidor } from "./CambiosMedidor";

// Pérdidas de agua (IPUF). Serie histórica larga: 114 períodos desde
// enero de 2017, en su propio archivo y con un mes de rezago respecto
// al resto del tablero.
//
// El IPUF, el ICUF y el ISUF son m³ por suscriptor-mes (13,68 m³/susc·mes),
// NO porcentajes (ISUF = ICUF + IPUF, verificado en los 117 períodos); solo
// el IANC y "% facturada sobre potabilizada" son porcentajes. El IPUF se
// juzga contra dos referencias distintas que el origen ya trae:
// la META de EMDUPAR (compromiso propio) y el ESTÁNDAR regulatorio.

const COLOR_IPUF = "#0A2540";
const COLOR_META = "#C98A2D";
const COLOR_ESTANDAR = "#9AA7B5";
const COLOR_ANIO_CORRIDO = "#0E7C86";

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void; onIrAPqr?: () => void };

// Al cambiar de período se reinicia la pantalla (clave = período): el estado recordado es por período y no se arrastra de uno a otro.
export function Perdidas(props: Props) {
  return <PerdidasPeriodo key={props.periodo} {...props} />;
}

const PLEGABLES = ["pl-ipuf", "pl-lectura", "pl-subm", "pl-cambios", "pl-reclamos"];
const LECTURA_VACIO = { ciclo: TODOS, uso: TODOS, subcategoria: TODOS };
const SUBM_VACIO = { subcategoria: TODOS };

function PerdidasPeriodo({ periodo, onIrAPeriodo, onIrAPqr }: Props) {
  const [filas, setFilas] = useState<Ipuf[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Plegables de la pantalla (todos cerrados al entrar); solo en memoria.
  const pl = usePlegables({}, `${periodo}.plegables`, PLEGABLES);
  // Filtros de los dos paneles (cada panel sigue dentro de su plegable). El de Lectura también gobierna los cambios de medidor.
  const [vLectura, setVLectura] = useEstadoSesion<Record<string, string>>(`${periodo}.filtros.lectura`, LECTURA_VACIO, normalizarFiltrosLectura);
  const [vSubm, setVSubm] = useEstadoSesion<Record<string, string>>(`${periodo}.filtros.submedicion`, SUBM_VACIO, normalizarFiltrosSubmedicion);

  function cargar() {
    setError(null);
    setFilas(null);
    biCache("v_ipuf")
      .then((r) => setFilas((r.datos ?? []).map(comoIpuf)))
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  const cronologico = useMemo(
    () => [...(filas ?? [])].sort((a, b) => a.periodo.localeCompare(b.periodo)),
    [filas],
  );

  // Resumen por año tarifario (jul-jun): alimenta los bloques anuales.
  const anual = useMemo(() => resumenAnual(filas ?? []), [filas]);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudieron cargar las pérdidas: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!filas) return <div className="dash-estado">Cargando pérdidas…</div>;

  const disponibles = cronologico.map((f) => f.periodo);
  const sel = filas.find((f) => f.periodo === periodo);

  // El IPUF llega con un mes de rezago: si el período del selector aún
  // no tiene archivo, se muestra el estándar de huecos del tablero.
  if (!sel) {
    return (
      <SinDatos
        periodo={periodo}
        fuente="pérdidas (IPUF)"
        disponibles={disponibles}
        onIr={onIrAPeriodo}
      />
    );
  }

  const idx = cronologico.findIndex((f) => f.periodo === periodo);
  const anterior = idx > 0 ? cronologico[idx - 1] : undefined;
  const hace12 = idx >= 12 ? cronologico[idx - 12] : undefined;

  const sobreMeta = sel.ipuf != null && sel.meta_ipuf != null && sel.ipuf > sel.meta_ipuf;
  // Exceso REAL sobre la meta del mes. La columna perdidas_superiores_meta del
  // origen vale meta x suscriptores (el volumen que la meta permite), no el exceso.
  const exceso = excesoSobreMeta(sel);
  const deltaIpuf = (a: number | null, b: number | null) =>
    a == null || b == null
      ? "—"
      : `${a - b >= 0 ? "+" : "−"}${fmtIpuf(Math.abs(a - b))}`;

  // Índice mensual contra sus dos referencias, serie completa.
  const etiquetas = cronologico.map((f) => etiquetaCorta(f.periodo));
  const seriesIndice = [
    { nombre: "IPUF real", color: COLOR_IPUF, valores: cronologico.map((f) => f.ipuf) },
    // OJO (jul-sep 2026): IPUFAR_ANO del origen trae el literal 16 desde 202607
    // (hasta 202606 traía 16,0337...), así que esta línea queda plana en 16,00 en el
    // año tarifario parcial; corregir en la fuente. El frontend solo la grafica.
    { nombre: "IPUF del año tarifario", color: COLOR_ANIO_CORRIDO, valores: cronologico.map((f) => f.ipuf_anio_corrido) },
    { nombre: "Meta EMDUPAR", color: COLOR_META, valores: cronologico.map((f) => f.meta_ipuf) },
    { nombre: "Estándar regulatorio", color: COLOR_ESTANDAR, valores: cronologico.map((f) => f.ipuf_estandar) },
  ];

  // Pérdida en pesos por mes y año.
  const anios = [...new Set(cronologico.map((f) => f.ano).filter((a): a is number => a != null))].sort();
  const anioMax = Math.max(...anios);
  const seriesPesos = anios.map((a) => ({
    nombre: String(a),
    color: colorAnio(a, anioMax),
    valores: Array.from(
      { length: 12 },
      (_, i) => cronologico.find((f) => f.ano === a && f.mes === i + 1)?.perdida_total_pesos ?? null,
    ),
  }));

  // Balance del mes: cuánta agua se potabiliza y cuánta se factura.
  const pctFacturada =
    sel.agua_potable && sel.agua_facturada ? (sel.agua_facturada / sel.agua_potable) * 100 : null;

  return (
    <>
      <h2 className="dash-zona">IPUF</h2>
      <IpufAnualBloque anual={anual} periodo={periodo} />

      <Plegable id="pl-ipuf" diferido titulo="IPUF mensual y demás indicadores" abierto={!!pl.abiertos["pl-ipuf"]} onCambio={(o) => pl.cambiar("pl-ipuf", o)}>
      <div className="dash-kpis">
        <div className={`dash-carta dash-kpi ${sobreMeta ? "dash-kpi-mal" : ""}`}>
          <div className="dash-eti">IPUF del mes</div>
          <div className="dash-valor num">{fmtIpuf(sel.ipuf)}</div>
          <div className="dash-sub2">
            Meta {fmtIpuf(sel.meta_ipuf)}{" "}
            <span className={`dash-semaforo ${sobreMeta ? "rojo" : "verde"}`}>
              {sobreMeta ? "sobre la meta" : "en meta"}
            </span>
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contra el mes anterior</div>
          <div className="dash-valor num">{deltaIpuf(sel.ipuf, anterior?.ipuf ?? null)}</div>
          <div className="dash-sub2">
            {anterior ? `${etiquetaPeriodo(anterior.periodo)}: ${fmtIpuf(anterior.ipuf)}` : "Sin mes previo"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Contra el mismo mes del año pasado</div>
          <div className="dash-valor num">{deltaIpuf(sel.ipuf, hace12?.ipuf ?? null)}</div>
          <div className="dash-sub2">
            {hace12 ? `${etiquetaPeriodo(hace12.periodo)}: ${fmtIpuf(hace12.ipuf)}` : "Sin doce meses de historia"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Pérdida del mes</div>
          <div className="dash-valor num">{fmtMillones(sel.perdida_total_pesos)}</div>
          <div className="dash-sub2 num">
            {fmtEntero(sel.perdida_total_m3)} m³ · tarifa{" "}
            {sel.tarifa_m3 != null
              ? `${sel.tarifa_m3.toLocaleString("es-CO", { maximumFractionDigits: 0 })} $/m³`
              : "—"}
          </div>
        </div>

        <div className="dash-carta dash-kpi">
          <div className="dash-eti">Pérdida por encima de la meta</div>
          <div className="dash-valor num">{fmtMillones(exceso?.pesos ?? null)}</div>
          <div className="dash-sub2 num">
            {fmtEntero(exceso?.m3 ?? null)} m³ · lo que excede el compromiso propio
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>El índice contra sus dos referencias, mes a mes</h3>
          <LineasPorcentaje
            etiquetas={etiquetas}
            series={seriesIndice}
            tituloY="m³/susc·mes"
            formatoTick={(t) => t.toLocaleString("es-CO", { maximumFractionDigits: 0 })}
            formatoValor={fmtIpuf}
            sinTope
            paso={4}
          />
          <TablaPlegable titulo="Datos: índices por período">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Período</th><th>IPUF (m³/susc·mes)</th><th>Año tarifario</th><th>Meta</th>
                  <th>Estándar</th><th>ICUF (m³/susc·mes)</th><th>ISUF (m³/susc·mes)</th><th>IANC</th>
                </tr>
              </thead>
              <tbody>
                {[...cronologico].reverse().map((f) => (
                  <tr key={f.periodo} className={f.periodo === periodo ? "dash-fila-fuerte" : ""}>
                    <td>{etiquetaPeriodo(f.periodo)}</td>
                    <td className="num">{fmtIpuf(f.ipuf, false)}</td>
                    <td className="num">{fmtIpuf(f.ipuf_anio_corrido, false)}</td>
                    <td className="num">{fmtIpuf(f.meta_ipuf, false)}</td>
                    <td className="num">{fmtIpuf(f.ipuf_estandar, false)}</td>
                    <td className="num">{fmtIpuf(f.icuf, false)}</td>
                    <td className="num">{fmtIpuf(f.isuf, false)}</td>
                    <td className="num">{fmtPct(f.ianc == null ? null : f.ianc * 100)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            El eje se ajusta al rango observado. La <b>meta</b> es
            el compromiso de EMDUPAR y el <b>estándar</b> el de la regulación:
            la distancia entre las dos líneas grises y la azul es el tamaño
            del problema. La verde es el <b>IPUF del año tarifario</b>: un
            valor fijo por año, no un acumulado que se va sumando.
          </div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          <h3>Lo que cuesta el agua que no se factura</h3>
          <BarrasMensuales
            series={seriesPesos}
            formatoY={(v) => (v / 1e9).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " mil M"}
            formatoTitulo={fmtMillones}
          />
          <div className="dash-nota">
            La pérdida en pesos es el volumen no facturado valorado a la
            tarifa media del mes, así que sube tanto cuando se pierde más
            agua como cuando la tarifa aumenta. Para juzgar la gestión, el
            índice de arriba manda; esta gráfica dice cuánto pesa en caja.
          </div>
        </div>
      </div>

      <div className="dash-fila-g3">
        <div className="dash-carta">
          <h3>Balance de {etiquetaPeriodo(periodo)}</h3>
          <table className="dash-tabla num">
            <tbody>
              <tr>
                <td>Agua potabilizada</td>
                <td className="num">{fmtEntero(sel.agua_potable)} m³</td>
              </tr>
              <tr>
                <td>Agua facturada</td>
                <td className="num">{fmtEntero(sel.agua_facturada)} m³</td>
              </tr>
              <tr className="dash-fila-fuerte">
                <td>Diferencia</td>
                <td className="num">
                  {sel.agua_potable != null && sel.agua_facturada != null
                    ? `${fmtEntero(sel.agua_potable - sel.agua_facturada)} m³`
                    : "—"}
                </td>
              </tr>
              <tr>
                <td>% facturada sobre potabilizada</td>
                <td className="num">{fmtPct(pctFacturada)}</td>
              </tr>
              <tr>
                <td>Suscriptores</td>
                <td className="num">{fmtEntero(sel.suscriptores)}</td>
              </tr>
              <tr>
                <td>Consumo facturado por suscriptor</td>
                <td className="num">
                  {sel.agua_facturada != null && sel.suscriptores
                    ? fmtIpuf(sel.agua_facturada / sel.suscriptores)
                    : "—"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div className="dash-carta">
          <h3>Las tres lecturas de la pérdida</h3>
          <table className="dash-tabla num">
            <thead>
              <tr><th>Medida</th><th>m³</th><th>Pesos</th></tr>
            </thead>
            <tbody>
              <tr>
                <td>Pérdida total</td>
                <td className="num">{fmtEntero(sel.perdida_total_m3)}</td>
                <td className="num">{fmtMillones(sel.perdida_total_pesos)}</td>
              </tr>
              <tr>
                <td>Descontando lo admisible</td>
                <td className="num">{fmtEntero(sel.perdida_sin_admisible_m3)}</td>
                <td className="num">{fmtMillones(sel.perdida_sin_admisible_pesos)}</td>
              </tr>
              <tr>
                <td>Por encima de la meta propia</td>
                <td className="num">{fmtEntero(exceso?.m3 ?? null)}</td>
                <td className="num">{fmtMillones(exceso?.pesos ?? null)}</td>
              </tr>
            </tbody>
          </table>
          <div className="dash-nota">
            La regulación acepta un porcentaje de pérdida como inevitable.
            La segunda fila descuenta esa parte y la tercera se queda solo
            con lo que excede el compromiso propio de la empresa: es la
            cifra que mide gestión, no fatalidad.
          </div>
        </div>
      </div>

      <IndicesAnualesSeccion anual={anual} />
      </Plegable>

      <h2 className="dash-zona">Lectura y submedición</h2>
      <IndicadoresLectura periodo={periodo} />
      <SubmedicionExplicacion periodo={periodo} ipufSerie={filas} />

      <Plegable id="pl-lectura" diferido titulo="Detalle de lectura y medición" abierto={!!pl.abiertos["pl-lectura"]} onCambio={(o) => pl.cambiar("pl-lectura", o)}
        marca={<MarcaFiltro valores={vLectura} />}>
        <PerdidasLectura periodo={periodo} valores={vLectura} onCambioValores={setVLectura} />
      </Plegable>
      <Plegable id="pl-subm" diferido titulo="Submedición por vejez (análisis completo)" abierto={!!pl.abiertos["pl-subm"]} onCambio={(o) => pl.cambiar("pl-subm", o)}
        marca={<MarcaFiltro valores={vSubm} />}>
        <SubmedicionVejez periodo={periodo} valores={vSubm} onCambioValores={setVSubm} />
      </Plegable>

      <h2 className="dash-zona">Cambios de medidor y reclamos</h2>
      <div className="dash-fila">
        <span className="dash-sin-filtro">Depende del filtro de «Detalle de lectura y medición» (ciclo, uso y estrato).</span>{" "}
        <MarcaFiltro valores={vLectura} onLimpiar={() => setVLectura(LECTURA_VACIO)} />
      </div>
      <CambiosMedidor periodo={periodo} valores={vLectura} parte="consumo" />
      <Plegable id="pl-cambios" diferido titulo="Cambios de medidor: detalle por período, ciclo, uso, antigüedad y método" abierto={!!pl.abiertos["pl-cambios"]}
        onCambio={(o) => pl.cambiar("pl-cambios", o)} marca={<MarcaFiltro valores={vLectura} />}>
        <CambiosMedidor periodo={periodo} valores={vLectura} parte="resto" />
      </Plegable>
      <Plegable id="pl-reclamos" diferido titulo="Reclamos según el método de facturación" abierto={!!pl.abiertos["pl-reclamos"]} onCambio={(o) => pl.cambiar("pl-reclamos", o)}
        marca={<span className="dash-sin-filtro">No depende de filtros</span>}>
        <ReclamosMetodoPerdidas onIrAPqr={onIrAPqr} />
      </Plegable>

      <MapaCalor periodo={periodo} />
    </>
  );
}
