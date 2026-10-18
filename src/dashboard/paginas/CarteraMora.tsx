import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { comoCarteraTransicionDim, comoEmdDim, type CarteraTransicionDim, type EmdDim } from "../tipos";
import { BarrasApiladas, LineasPorcentaje, TablaPlegable } from "../graficas";
import { etiquetaCorta, etiquetaPeriodo, fmtEntero, fmtPct } from "../formato";
import { MarcaFiltro, Plegable } from "../Plegable";
import { fmtMillonesUno } from "../edadCarteraCalculo";
import {
  CODIGOS_EMD, ESTADOS_ORDEN, MORAS_EMD, PRIMER_PERIODO_EMD, PROFUNDA, ROTULO_ESTADO, ROTULO_GRUPO,
  cohorte, corteSuspensionDetalle, emdCruce, emdPorMes, evolucionMovimiento, filtrarUsoEstrato, matrizTransicion, movimiento, profundaConSin, sumarPeriodo,
} from "../moraEmdCalculo";
import { Ficha, SinCicloBarrio } from "./CarteraEdad";

// Zonas «Movimiento de la mora» (bi.v_cartera_transicion_dim, sql/47) y «Suspensiones y cortes (SCRR)» (bi.v_emd_dim, sql/48) de Cartera desagregada.
// Cada zona hace UNA llamada (con todos los períodos, cacheada) al abrirse; el uso y el estrato son los filtros compartidos de la pantalla. Ninguna depende de
// ciclo, comuna ni barrio. Todo es una DESCRIPCIÓN de lo que pasó con los contratos, no una causa.

const COLOR = { tinta: "#0A2540", agua: "#0E7C86", ambar: "#C98A2D", gris: "#8A99A8", rojo: "#B23A48" };
const COLOR_CODIGO: Record<string, string> = { "600": "#4FA3C7", "602": "#0A2540", "603": "#C98A2D", "605": "#B23A48", "606": "#0E7C86" };
const signo = (v: number) => `${v < 0 ? "−" : "+"}${fmtEntero(Math.abs(v))}`;

type Estado<T> = { datos: T | null; error: string | null; recargar: () => void };
export function useVista<T>(vista: string, convertir: (r: Record<string, unknown>) => T): Estado<T[]> {
  const [datos, setDatos] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    let vivo = true;
    setDatos(null); setError(null);
    biCache(vista).then((r) => { if (vivo) setDatos((r.datos ?? []).map(convertir)); }).catch((e: Error) => { if (vivo) setError(e.message); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vista, intento]);
  return { datos, error, recargar: () => setIntento((i) => i + 1) };
}
export function Cargando<T>({ estado, que, children }: { estado: Estado<T[]>; que: string; children: (d: T[]) => JSX.Element }) {
  if (estado.error) {
    return (<div className="dash-estado"><p>No se pudo cargar {que}: {estado.error}</p><button className="dash-boton" onClick={estado.recargar}>Reintentar</button></div>);
  }
  if (!estado.datos) return <div className="dash-estado">Cargando {que}…</div>;
  return children(estado.datos);
}
export const SinCombinacion = () => (
  <div className="dash-aviso">
    No hay contratos para esta combinación de uso y estrato en este período: por el mínimo de 5 contratos se agrupa en <b>Otros / sin clasificar</b>. Elija otra o limpie el filtro.
  </div>
);
export const Lectura = ({ lineas }: { lineas: string[] }) => (
  <div className="dash-carta">
    <h3>Lectura en palabras</h3>
    <ul className="dash-lectura">{lineas.map((l, i) => <li key={i}>{l}</li>)}</ul>
    <div className="dash-nota">Es una descripción de lo que muestran las cifras de arriba, no una explicación de sus causas.</div>
  </div>
);

// ---------------------------------------------------------------------------------------------------------------------------------
// Movimiento de la mora
// ---------------------------------------------------------------------------------------------------------------------------------
type Props = { periodo: string; uso: string; estrato: string; onLimpiar: () => void };

export function ZonaMovimientoMora(props: Props) {
  const est = useVista("v_cartera_transicion_dim", comoCarteraTransicionDim);
  return <Cargando estado={est} que="el movimiento de la mora">{(filas) => <MovimientoMora {...props} filas={filas} />}</Cargando>;
}

function MovimientoMora({ filas, periodo, uso, estrato, onLimpiar }: Props & { filas: CarteraTransicionDim[] }) {
  const filtradas = useMemo(() => filtrarUsoEstrato(filas, uso, estrato), [filas, uso, estrato]);
  const periodos = useMemo(() => [...new Set(filas.map((f) => f.periodo))].sort(), [filas]);
  const mesAnt = sumarPeriodo(periodo, -1);
  const base = periodos.length ? sumarPeriodo(periodos[0], -1) : null;
  const ant = useMemo(() => filtradas.filter((f) => f.periodo === periodo && f.referencia === "anterior"), [filtradas, periodo]);
  const baseFilas = useMemo(() => filtradas.filter((f) => f.periodo === periodo && f.referencia === "base"), [filtradas, periodo]);
  const mv = useMemo(() => movimiento(ant), [ant]);
  const mat = useMemo(() => matrizTransicion(ant), [ant]);
  const coh = useMemo(() => cohorte(baseFilas), [baseFilas]);
  const evo = useMemo(() => evolucionMovimiento(filtradas), [filtradas]);

  if (!periodos.includes(periodo)) {
    return (<>
      <SinCicloBarrio />
      <div className="dash-aviso">
        El movimiento compara cada mes con el anterior, así que el primer período de la fuente ({base ? etiquetaPeriodo(sumarPeriodo(base, 1)) : "—"} en adelante tiene movimiento; {base ? etiquetaPeriodo(base) : "el período base"} no) y los
        períodos sin carga no lo tienen. Elija un período entre {periodos.length ? `${etiquetaCorta(periodos[0])} y ${etiquetaCorta(periodos[periodos.length - 1])}` : "los cargados"}.
      </div>
    </>);
  }
  if (mv.total === 0 && mv.agrupadas === 0) return <><SinCicloBarrio /><SinCombinacion /></>;

  const dif = mv.profundaDestino - mv.profundaOrigen;
  const hayCohorte = baseFilas.length > 0 && base != null;
  const maxFila = (o: string) => Math.max(1, ...mat.destinos.map((d) => mat.celda(o, d).contratos));
  const fondo = (o: string, d: string) => {
    const v = mat.celda(o, d).contratos;
    if (!v) return undefined;
    const a = Math.min(0.55, 0.08 + 0.5 * (v / maxFila(o)));
    return { background: PROFUNDA.has(d) ? `rgba(178,58,72,${a})` : `rgba(14,124,134,${a})` };
  };
  const evoPer = evo.map((e) => etiquetaCorta(e.periodo));
  const lectura: string[] = [
    `En ${etiquetaPeriodo(periodo)}, ${fmtEntero(mv.profundaDestino)} contratos están en mora profunda (más de 8 facturas vencidas): ${dif === 0 ? "los mismos que" : `${fmtEntero(Math.abs(dif))} ${dif > 0 ? "más que" : "menos que"}`} en ${etiquetaPeriodo(mesAnt)} (${fmtEntero(mv.profundaOrigen)}). Entraron ${fmtEntero(mv.entradas)}, salieron ${fmtEntero(mv.salidas)} y ${fmtEntero(mv.permanencia)} permanecieron.`,
    `${fmtEntero(mv.pasoSinDeuda)} contratos con deuda pasaron a «sin deuda» (${fmtEntero(mv.pasoSinDeudaDesdeProfunda)} desde la mora profunda); ${fmtEntero(mv.nuevos)} contratos son nuevos y ${fmtEntero(mv.yaNoEstan)} ya no figuran.`,
  ];
  if (hayCohorte && coh.base > 0) {
    lectura.push(`De los ${fmtEntero(coh.base)} contratos que estaban en mora profunda en ${etiquetaPeriodo(base!)}, ${fmtEntero(coh.siguen)} (${fmtPct((coh.siguen / coh.base) * 100)}) siguen en ella en ${etiquetaPeriodo(periodo)}; ${fmtEntero(coh.bajan)} bajaron a 8 facturas o menos con deuda y ${fmtEntero(coh.sinDeuda)} pasaron a «sin deuda».`);
  }
  if (evo.length > 1) {
    const e = evo.map((x) => x.entradas), s = evo.map((x) => x.salidas);
    lectura.push(`Entre ${etiquetaCorta(evo[0].periodo)} y ${etiquetaCorta(evo[evo.length - 1].periodo)}, las entradas a la mora profunda fueron de ${fmtEntero(Math.min(...e))} a ${fmtEntero(Math.max(...e))} contratos por mes y las salidas de ${fmtEntero(Math.min(...s))} a ${fmtEntero(Math.max(...s))}.`);
  }

  return (
    <>
      <div className="dash-sin-filtro-fila"><MarcaFiltro valores={{ uso, estrato }} onLimpiar={onLimpiar} /><SinCicloBarrio /></div>
      <div className="dash-aviso">
        <b>Mora profunda</b> = más de 8 facturas vencidas (grupos «9-24» y «más de 24»). Las cifras comparan cada contrato entre {etiquetaPeriodo(mesAnt)} y {etiquetaPeriodo(periodo)}.
        Describen lo que pasó con los contratos, no por qué pasó.
      </div>

      <div className="dash-kpis">
        <Ficha etiqueta="Contratos en mora profunda" valor={fmtEntero(mv.profundaDestino)} mal
          sub={`${signo(dif)} frente a ${etiquetaPeriodo(mesAnt)} (${fmtEntero(mv.profundaOrigen)}) · saldo ${fmtMillonesUno(mv.saldoProfundaDestino)}`} />
        <Ficha etiqueta="Entradas a la mora profunda" valor={fmtEntero(mv.entradas)} sub="venían con 8 facturas o menos y existían el mes anterior" />
        <Ficha etiqueta="Salidas de la mora profunda" valor={fmtEntero(mv.salidas)} sub="venían de la mora profunda y quedan con 8 facturas o menos" />
        <Ficha etiqueta="Permanencia" valor={fmtEntero(mv.permanencia)} sub={`${fmtPct(mv.profundaOrigen ? (mv.permanencia / mv.profundaOrigen) * 100 : null)} de los que estaban en la mora profunda`} />
        <Ficha etiqueta="Paso a «sin deuda»" valor={fmtEntero(mv.pasoSinDeuda)} sub={`${fmtEntero(mv.pasoSinDeudaDesdeProfunda)} venían de la mora profunda`} />
        <Ficha etiqueta="Contratos nuevos" valor={fmtEntero(mv.nuevos)} sub="no estaban en el mes anterior" />
        <Ficha etiqueta="Contratos que ya no existen" valor={fmtEntero(mv.yaNoEstan)} sub="estaban el mes anterior y ya no figuran" />
      </div>
      {(mv.agrupadas > 0 || mv.celdasVacias > 0) && (
        <div className="dash-nota">
          {mv.agrupadas > 0 ? `${fmtEntero(mv.agrupadas)} contratos están en celdas «agrupada» (celdas con menos de 5 contratos que se funden para proteger la privacidad) y no se asignan a ninguna de estas fichas. ` : ""}
          {mv.celdasVacias > 0 ? `${fmtEntero(mv.celdasVacias)} celda(s) con menos de 5 contratos se publican vacías.` : ""}
        </div>
      )}

      <div className="dash-fila"><div className="dash-carta">
        <h3>De dónde vienen y a dónde van — {etiquetaPeriodo(mesAnt)} → {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-leer">Cómo leerlo: cada fila es el grupo de mora de los contratos en {etiquetaPeriodo(mesAnt)}; cada columna, su grupo en {etiquetaPeriodo(periodo)}. La diagonal son los que no cambiaron. Rojo = destino en mora profunda.</div>
        <div className="dash-tabla-scroll">
          <table className="dash-tabla num dash-matriz">
            <thead><tr><th>Origen \ Destino</th>{mat.destinos.map((d) => <th key={d}>{ROTULO_GRUPO[d]}</th>)}<th>Total origen</th></tr></thead>
            <tbody>
              {mat.origenes.map((o) => (
                <tr key={o}>
                  <td>{ROTULO_GRUPO[o]}</td>
                  {mat.destinos.map((d) => <td key={d} className="num" style={fondo(o, d)}>{mat.celda(o, d).contratos ? fmtEntero(mat.celda(o, d).contratos) : "·"}</td>)}
                  <td className="num"><b>{fmtEntero(mat.totalFila(o))}</b></td>
                </tr>
              ))}
              <tr className="dash-total"><td>Total destino</td>{mat.destinos.map((d) => <td key={d} className="num">{fmtEntero(mat.totalCol(d))}</td>)}<td className="num">{fmtEntero(mat.total)}</td></tr>
            </tbody>
          </table>
        </div>
        <TablaPlegable titulo="Datos: saldo (M) de los mismos contratos, origen y destino">
          <table className="dash-tabla num">
            <thead><tr><th>Origen → Destino</th><th>Contratos</th><th>Saldo en el origen</th><th>Saldo en el destino</th></tr></thead>
            <tbody>
              {mat.origenes.flatMap((o) => mat.destinos.filter((d) => mat.celda(o, d).contratos > 0).map((d) => (
                <tr key={`${o}-${d}`}><td>{ROTULO_GRUPO[o]} → {ROTULO_GRUPO[d]}</td><td className="num">{fmtEntero(mat.celda(o, d).contratos)}</td><td className="num">{fmtMillonesUno(mat.celda(o, d).saldoOrigen)}</td><td className="num">{fmtMillonesUno(mat.celda(o, d).saldoDestino)}</td></tr>
              )))}
            </tbody>
          </table>
        </TablaPlegable>
      </div></div>

      <div className="dash-fila"><div className="dash-carta">
        <h3>Cohorte de {base ? etiquetaPeriodo(base) : "febrero"} en {etiquetaPeriodo(periodo)}</h3>
        {!hayCohorte || coh.base === 0 ? (
          <div className="dash-nota">Para este período la referencia base ({base ? etiquetaPeriodo(base) : "el primer período"}) coincide con el mes anterior o no tiene contratos en mora profunda para esta combinación: la cohorte se ve en la matriz de arriba.</div>
        ) : (<>
          <div className="dash-leer">Cómo leerlo: son los contratos que estaban en mora profunda en {etiquetaPeriodo(base!)} (referencia base) y dónde están hoy.</div>
          <div className="dash-kpis">
            <Ficha etiqueta={`En mora profunda en ${etiquetaCorta(base!)}`} valor={fmtEntero(coh.base)} sub={`saldo ${fmtMillonesUno(coh.saldoBase)}`} />
            <Ficha etiqueta="Siguen en mora profunda" valor={fmtEntero(coh.siguen)} mal sub={`${fmtPct((coh.siguen / coh.base) * 100)} de la cohorte · saldo hoy ${fmtMillonesUno(coh.saldoDestino)}`} />
            <Ficha etiqueta="Bajaron a 8 facturas o menos" valor={fmtEntero(coh.bajan)} sub={`${fmtPct((coh.bajan / coh.base) * 100)} de la cohorte`} />
            <Ficha etiqueta="Pasaron a «sin deuda»" valor={fmtEntero(coh.sinDeuda)} sub={`${fmtPct((coh.sinDeuda / coh.base) * 100)} de la cohorte`} />
            <Ficha etiqueta="Ya no existen" valor={fmtEntero(coh.yaNoEstan)} sub={coh.agrupados > 0 ? `y ${fmtEntero(coh.agrupados)} en celdas «agrupada»` : "—"} />
          </div>
        </>)}
      </div></div>

      <div className="dash-fila"><div className="dash-carta">
        <h3>Entradas y salidas de la mora profunda, mes a mes</h3>
        <div className="dash-leer">Cómo leerlo: contratos que entran y que salen de la mora profunda en cada mes frente al mes anterior.</div>
        <LineasPorcentaje
          etiquetas={evoPer}
          series={[
            { nombre: "Entradas", color: COLOR.rojo, valores: evo.map((e) => e.entradas) },
            { nombre: "Salidas", color: COLOR.agua, valores: evo.map((e) => e.salidas) },
          ]}
          formatoTick={(t) => fmtEntero(t)} formatoValor={(v) => `${fmtEntero(v)} contratos`} sinTope paso={50}
        />
        <TablaPlegable titulo="Datos: movimiento por período">
          <table className="dash-tabla num">
            <thead><tr><th>Período</th><th>En mora profunda</th><th>Entradas</th><th>Salidas</th><th>Permanencia</th><th>A «sin deuda»</th><th>Nuevos</th><th>Ya no existen</th></tr></thead>
            <tbody>
              {evo.map((e) => (
                <tr key={e.periodo}><td>{etiquetaCorta(e.periodo)}</td><td className="num">{fmtEntero(e.profundaDestino)}</td><td className="num">{fmtEntero(e.entradas)}</td><td className="num">{fmtEntero(e.salidas)}</td><td className="num">{fmtEntero(e.permanencia)}</td><td className="num">{fmtEntero(e.pasoSinDeuda)}</td><td className="num">{fmtEntero(e.nuevos)}</td><td className="num">{fmtEntero(e.yaNoEstan)}</td></tr>
              ))}
            </tbody>
          </table>
        </TablaPlegable>
      </div></div>

      <div className="dash-fila"><Lectura lineas={lectura} /></div>

      <div className="dash-fila"><div className="dash-carta dash-metodologia">
        <h3>Metodología del movimiento de la mora</h3>
        <ul>
          <li><b>Fuente.</b> El detalle por contrato de cartera de cada mes (<code>cartera_contrato</code>). Cada contrato se clasifica por sus facturas vencidas (máximo del contrato): sin deuda, al día con deuda, 1-2, 3-8, 9-24 y más de 24; «no estaba» si no existía en el mes de origen y «ya no está» si no existe en el de destino.</li>
          <li><b>Referencias.</b> «Mes anterior» compara con el período inmediatamente anterior de la fuente; «base» compara con el primer período de la fuente y permite la cohorte desde ese mes.</li>
          <li><b>Privacidad.</b> Solo agregados por uso y estrato, sin contrato, barrio ni ciclo. Las celdas con menos de 5 contratos se funden por pasos (estrato, uso, destino) en «agrupada» con las mismas sumas; si aun la última celda queda con menos de 5, se publica vacía y no entra en los totales. Esos contratos no se asignan a las fichas.</li>
          <li><b>Es una descripción, no una causa.</b> Un contrato que sale de la mora profunda puede haber pagado, haber sido financiado, haber cambiado de estado o haber sido ajustado; la cifra no lo distingue.</li>
        </ul>
      </div></div>
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------
// Suspensiones y cortes (SCRR)
// ---------------------------------------------------------------------------------------------------------------------------------
export function ZonaSuspensionesCortes(props: Props) {
  const est = useVista("v_emd_dim", comoEmdDim);
  return <Cargando estado={est} que="las suspensiones y cortes">{(filas) => <SuspensionesCortes {...props} filas={filas} />}</Cargando>;
}

function ProfundaConSin({ emd, periodo, uso, estrato }: { emd: EmdDim[]; periodo: string; uso: string; estrato: string }) {
  const est = useVista("v_cartera_transicion_dim", comoCarteraTransicionDim);
  return (
    <Cargando estado={est} que="la mora profunda">
      {(trans) => {
        const r = profundaConSin(filtrarUsoEstrato(emd, uso, estrato), filtrarUsoEstrato(trans, uso, estrato), periodo);
        return (<>
          <div className="dash-kpis">
            <Ficha etiqueta="En mora profunda" valor={fmtEntero(r.universo)} sub={`contratos en ${etiquetaPeriodo(periodo)}`} />
            <Ficha etiqueta="Con corte o suspensión facturado" valor={fmtEntero(r.con)} mal sub={`${fmtPct(r.universo ? (r.con / r.universo) * 100 : null)} de la mora profunda`} />
            <Ficha etiqueta="Sin corte ni suspensión facturado" valor={fmtEntero(r.sin)} sub={`${fmtPct(r.universo ? (r.sin / r.universo) * 100 : null)} de la mora profunda`} />
          </div>
          <div className="dash-nota">«Con» cuenta pares contrato-código de 600, 602 y 605 facturados en el mes; un contrato con dos de esos códigos cuenta dos veces. Lo facturado no es la actividad física en terreno.</div>
        </>);
      }}
    </Cargando>
  );
}

function SuspensionesCortes({ filas, periodo, uso, estrato, onLimpiar }: Props & { filas: EmdDim[] }) {
  const filtradas = useMemo(() => filtrarUsoEstrato(filas, uso, estrato), [filas, uso, estrato]);
  const periodos = useMemo(() => [...new Set(filas.map((f) => f.periodo))].sort(), [filas]);
  const meses = useMemo(() => emdPorMes(filtradas, periodos), [filtradas, periodos]);
  const mes = meses.find((m) => m.periodo === periodo);
  const fiables = meses.filter((m) => !m.sinDatos);
  const det = useMemo(() => corteSuspensionDetalle(filtradas, periodo), [filtradas, periodo]);
  const cruceMora = useMemo(() => emdCruce(filtradas, periodo, "mora"), [filtradas, periodo]);
  const cruceEstado = useMemo(() => emdCruce(filtradas, periodo, "estado_producto"), [filtradas, periodo]);
  const [abreProfunda, setAbreProfunda] = useState(false);
  const nombre = (cod: string) => (cod === "agrupado" ? "Otros códigos (agrupados)" : `${cod} · ${CODIGOS_EMD.find((x) => x.codigo === cod)?.nombre ?? cod}`);
  const periodoSinDatos = !mes || mes.sinDatos;

  const lectura: string[] = [];
  if (mes && !mes.sinDatos) {
    lectura.push(`En ${etiquetaPeriodo(periodo)} se facturaron conceptos de corte o suspensión (600, 602 y 605) en ${fmtEntero(mes.corteSusp)} pares contrato-código y de reinstalación o reconexión (603 y 606) en ${fmtEntero(mes.reinstRecon)}; el valor facturado de los cinco conceptos fue ${fmtMillonesUno(mes.valorTotal)}.`);
    if (det.total > 0) lectura.push(`De los ${fmtEntero(det.total)} pares con corte o suspensión facturado, ${fmtEntero(det.activos)} (${fmtPct((det.activos / det.total) * 100)}) corresponden a productos en estado «Activo» según la cartera del mismo mes; el resto está en otros estados o en celdas agrupadas. El estado financiero («Conexión», «Suspensión total») no está en esta dimensión.`);
    if (det.total > 0) lectura.push(`${fmtEntero(det.profunda)} de esos pares (${fmtPct((det.profunda / det.total) * 100)}) son de contratos en mora profunda.`);
  } else {
    lectura.push(`${etiquetaPeriodo(periodo)} no tiene datos de conceptos EMD: la fuente trae estos conceptos desde ${etiquetaPeriodo(PRIMER_PERIODO_EMD)}. «Sin datos» no significa «sin actividad».`);
  }

  const tablaMes = (campo: "contratos" | "valor") => (
    <table className="dash-tabla num">
      <thead><tr><th>Período</th>{CODIGOS_EMD.map((x) => <th key={x.codigo}>{x.codigo} · {x.nombre}</th>)}<th>Otros códigos</th></tr></thead>
      <tbody>
        {meses.map((m) => (
          <tr key={m.periodo}>
            <td>{etiquetaCorta(m.periodo)}</td>
            {m.sinDatos
              ? <td className="num" colSpan={CODIGOS_EMD.length + 1}><i>sin datos (la fuente no trae estos conceptos antes de {etiquetaCorta(PRIMER_PERIODO_EMD)})</i></td>
              : <>{CODIGOS_EMD.map((x) => <td key={x.codigo} className="num">{campo === "contratos" ? fmtEntero(m.porCodigo[x.codigo].contratos) : fmtMillonesUno(m.porCodigo[x.codigo].valor)}</td>)}
                  <td className="num">{m.agrupado.vacio ? "vacío" : campo === "contratos" ? fmtEntero(m.agrupado.contratos) : fmtMillonesUno(m.agrupado.valor)}</td></>}
          </tr>
        ))}
      </tbody>
    </table>
  );

  return (
    <>
      <div className="dash-sin-filtro-fila"><MarcaFiltro valores={{ uso, estrato }} onLimpiar={onLimpiar} /><SinCicloBarrio /></div>
      <div className="dash-aviso">
        <b>Lo facturado no es la actividad física en terreno.</b> Esta zona cuenta lo que se cobró en factura por los conceptos EMD (corte, suspensión, reinstalación y reconexión): una orden ejecutada puede
        facturarse en un mes posterior o no facturarse, y un cobro puede corresponder a una orden de otro mes. No es el registro de órdenes (SCRR) ni mide cortes o suspensiones realmente hechos.
        Los nombres de los conceptos vienen escritos de varias maneras en el origen, por eso se agrupan por <b>código</b> (600, 602, 603, 605 y 606).
      </div>

      {periodoSinDatos ? (
        <div className="dash-aviso"><b>Sin datos en {etiquetaPeriodo(periodo)}.</b> La fuente trae los conceptos EMD desde {etiquetaPeriodo(PRIMER_PERIODO_EMD)}; antes no hay información (no son ceros). Elija un período desde {etiquetaCorta(PRIMER_PERIODO_EMD)}.</div>
      ) : (
        <div className="dash-kpis">
          <Ficha etiqueta="Corte o suspensión facturados" valor={fmtEntero(mes!.corteSusp)} mal sub="pares contrato-código de 600, 602 y 605" />
          <Ficha etiqueta="Reinstalación o reconexión facturadas" valor={fmtEntero(mes!.reinstRecon)} sub="pares contrato-código de 603 y 606" />
          <Ficha etiqueta="Valor facturado (5 conceptos)" valor={fmtMillonesUno(mes!.valorTotal)} sub={`en ${etiquetaPeriodo(periodo)}`} />
          <Ficha etiqueta="Con corte o suspensión en estado «Activo»" valor={fmtEntero(det.activos)} sub={det.total ? `${fmtPct((det.activos / det.total) * 100)} de ${fmtEntero(det.total)} pares con corte o suspensión` : "—"} />
        </div>
      )}

      <div className="dash-fila"><div className="dash-carta">
        <h3>Contratos y valor facturado por código, mes a mes (desde {etiquetaPeriodo(PRIMER_PERIODO_EMD)})</h3>
        <div className="dash-leer">Cómo leerlo: cada línea es un código; cuenta pares contrato-código facturados en el mes. Antes de {etiquetaCorta(PRIMER_PERIODO_EMD)} la fuente no trae estos conceptos (sin datos).</div>
        {fiables.length > 1 ? (
          <LineasPorcentaje
            etiquetas={fiables.map((m) => etiquetaCorta(m.periodo))}
            series={CODIGOS_EMD.map((x) => ({ nombre: `${x.codigo} · ${x.nombre}`, color: COLOR_CODIGO[x.codigo], valores: fiables.map((m) => m.porCodigo[x.codigo].contratos) }))}
            formatoTick={(t) => fmtEntero(t)} formatoValor={(v) => `${fmtEntero(v)} contratos`} sinTope paso={100}
          />
        ) : <div className="dash-nota">Se necesitan al menos dos meses con datos para dibujar la evolución.</div>}
        <TablaPlegable titulo="Datos: contratos (pares contrato-código) por código y mes">{tablaMes("contratos")}</TablaPlegable>
        <TablaPlegable titulo="Datos: valor facturado por código y mes">{tablaMes("valor")}</TablaPlegable>
      </div></div>

      {!periodoSinDatos && (<>
        <div className="dash-fila-g2">
          <div className="dash-carta">
            <h3>Por grupo de mora — {etiquetaPeriodo(periodo)}</h3>
            <div className="dash-leer">Cómo leerlo: cuántos contratos con cada código están en cada grupo de mora del mismo mes.</div>
            {cruceMora.codigos.length ? (
              <BarrasApiladas
                datos={cruceMora.codigos.map((cod) => ({ etiqueta: nombre(cod), valores: MORAS_EMD.map((m) => cruceMora.get(cod, m)) }))}
                series={MORAS_EMD.map((m, i) => ({ nombre: ROTULO_GRUPO[m] ?? "Sin cartera", color: ["#8FB4CE", "#4FA3C7", "#2E7D9E", "#1A5F80", "#12476A", "#0A2540", "#C98A2D", "#8A99A8"][i] }))}
                formatoValor={fmtEntero} margenIzq={150}
              />
            ) : <div className="dash-nota">Sin contratos con estos conceptos para la combinación elegida.</div>}
            <TablaPlegable titulo="Datos: código × grupo de mora">
              <table className="dash-tabla num">
                <thead><tr><th>Código</th>{MORAS_EMD.map((m) => <th key={m}>{ROTULO_GRUPO[m] ?? "Sin cartera"}</th>)}</tr></thead>
                <tbody>{cruceMora.codigos.map((cod) => <tr key={cod}><td>{nombre(cod)}</td>{MORAS_EMD.map((m) => <td key={m} className="num">{cruceMora.get(cod, m) ? fmtEntero(cruceMora.get(cod, m)) : "·"}</td>)}</tr>)}</tbody>
              </table>
            </TablaPlegable>
          </div>
          <div className="dash-carta">
            <h3>Por estado del producto — {etiquetaPeriodo(periodo)}</h3>
            <div className="dash-leer">Cómo leerlo: cuántos contratos con corte o suspensión facturado siguen en estado «Activo» según la cartera del mismo mes.</div>
            {cruceEstado.codigos.length ? (
              <BarrasApiladas
                datos={cruceEstado.codigos.map((cod) => ({ etiqueta: nombre(cod), valores: ESTADOS_ORDEN.map((e) => cruceEstado.get(cod, e)) }))}
                series={ESTADOS_ORDEN.map((e, i) => ({ nombre: ROTULO_ESTADO[e], color: ["#0E7C86", "#C98A2D", "#B23A48", "#8A99A8", "#4FA3C7", "#12476A", "#D9DEE3"][i] }))}
                formatoValor={fmtEntero} margenIzq={150}
              />
            ) : <div className="dash-nota">Sin contratos con estos conceptos para la combinación elegida.</div>}
            <TablaPlegable titulo="Datos: código × estado del producto">
              <table className="dash-tabla num">
                <thead><tr><th>Código</th>{ESTADOS_ORDEN.map((e) => <th key={e}>{ROTULO_ESTADO[e]}</th>)}</tr></thead>
                <tbody>{cruceEstado.codigos.map((cod) => <tr key={cod}><td>{nombre(cod)}</td>{ESTADOS_ORDEN.map((e) => <td key={e} className="num">{cruceEstado.get(cod, e) ? fmtEntero(cruceEstado.get(cod, e)) : "·"}</td>)}</tr>)}</tbody>
              </table>
            </TablaPlegable>
            <div className="dash-nota">El estado del producto no es el estado financiero («Conexión», «Suspensión total»): un contrato con corte o suspensión facturado puede seguir «Activo» como producto.</div>
          </div>
        </div>

        <Plegable id="cd-scrr-prof" diferido titulo="Mora profunda con y sin corte o suspensión facturado" abierto={abreProfunda} onCambio={setAbreProfunda}>
          <ProfundaConSin emd={filas} periodo={periodo} uso={uso} estrato={estrato} />
        </Plegable>
      </>)}

      <div className="dash-fila"><Lectura lineas={lectura} /></div>

      <div className="dash-fila"><div className="dash-carta dash-metodologia">
        <h3>Metodología de suspensiones y cortes</h3>
        <ul>
          <li><b>Fuente.</b> Las líneas de factura de los conceptos cuyo nombre empieza por «EMD» (<code>facturacion_contratos</code>), agrupadas por <b>código</b>: 600 corte sencillo, 602 suspensión sencilla, 603 reinstalación sencilla, 605 corte drástico y 606 reconexión drástica. El grupo de mora y el estado del producto salen de la cartera del mismo mes.</li>
          <li><b>Advertencia.</b> Lo facturado no es la actividad física en terreno ni el registro de órdenes (SCRR).</li>
          <li><b>Cobertura.</b> Confiable desde {etiquetaPeriodo(PRIMER_PERIODO_EMD)}. Antes la fuente no trae estos conceptos y la pantalla dice «sin datos», no cero.</li>
          <li><b>Conteo.</b> «Contratos» son pares contrato-código: un contrato con dos códigos en el mes cuenta una vez en cada uno.</li>
          <li><b>Privacidad.</b> Solo agregados por uso y estrato, sin contrato, barrio ni ciclo. Las celdas con menos de 5 contratos se funden por pasos en «agrupada» u «otros códigos» con las mismas sumas; la última celda puede publicarse vacía.</li>
        </ul>
      </div></div>
    </>
  );
}
