import { useMemo } from "react";
import { comoCarteraConceptoDim, type CarteraConceptoDim } from "../tipos";
import { BarrasApiladas, LineasPorcentaje, TablaPlegable } from "../graficas";
import { etiquetaCorta, etiquetaPeriodo, fmtPct } from "../formato";
import { MarcaFiltro } from "../Plegable";
import { LECTURA_PROVISIONAL, notaRotulos, tramosAnuales } from "../edadCartera";
import { fmtMillonesUno } from "../edadCarteraCalculo";
import { CODIGOS_POR_TIPO, type TipoConcepto } from "../conceptoTipos";
import {
  COLOR_TIPO, ROTULO_TIPO, TIPOS_BRUTO, composicionPorTipo, evolucionRecargo, filtrarConcepto, franjaMasVieja, perfilEdadPorTipo, recargoVsCapital,
  subsidiosPorEdad, subsidiosPorEstrato,
} from "../conceptoCalculo";
import { Cargando, Lectura, SinCombinacion, useVista } from "./CarteraMora";
import { Ficha, SinCicloBarrio } from "./CarteraEdad";

// Zona «Cartera por concepto» de Cartera desagregada (bi.v_cartera_concepto_dim, sql/49). UNA llamada con todos los períodos al abrirse; uso y estrato son los filtros
// compartidos. Describe la COMPOSICIÓN de la cartera, no su causa: cartera_edades no trae contrato, así que el recargo por contrato no se puede obtener.

type Props = { periodo: string; uso: string; estrato: string; onLimpiar: () => void };
const LECTURA = LECTURA_PROVISIONAL;
const TRAMOS = tramosAnuales(LECTURA);
const nom = (e: string) => (e === "otros" ? "Otros / sin clasificar" : `Estrato ${e}`);

export function ZonaCarteraConcepto(props: Props) {
  const est = useVista("v_cartera_concepto_dim", comoCarteraConceptoDim);
  return <Cargando estado={est} que="la cartera por concepto">{(filas) => <CarteraConcepto {...props} filas={filas} />}</Cargando>;
}

function CarteraConcepto({ filas, periodo, uso, estrato, onLimpiar }: Props & { filas: CarteraConceptoDim[] }) {
  const filtradas = useMemo(() => filtrarConcepto(filas, uso, estrato), [filas, uso, estrato]);
  const periodos = useMemo(() => [...new Set(filas.map((f) => f.periodo))].sort(), [filas]);
  const comp = useMemo(() => composicionPorTipo(filtradas, periodo), [filtradas, periodo]);
  const rvc = useMemo(() => recargoVsCapital(filtradas, periodo, LECTURA), [filtradas, periodo]);
  const evo = useMemo(() => evolucionRecargo(filtradas, periodos), [filtradas, periodos]);
  const perfil = useMemo(() => perfilEdadPorTipo(filtradas, periodo, LECTURA), [filtradas, periodo]);
  const subEst = useMemo(() => subsidiosPorEstrato(filtradas, periodo), [filtradas, periodo]);
  const subEdad = useMemo(() => subsidiosPorEdad(filtradas, periodo, LECTURA), [filtradas, periodo]);
  const vieja = useMemo(() => franjaMasVieja(filtradas, periodo, LECTURA), [filtradas, periodo]);

  if (!periodos.includes(periodo)) {
    return (<><SinCicloBarrio /><div className="dash-aviso">No hay cartera por concepto para {etiquetaPeriodo(periodo)}: la serie va de {etiquetaCorta(periodos[0] ?? periodo)} a {etiquetaCorta(periodos[periodos.length - 1] ?? periodo)}.</div></>);
  }
  if (comp.neto === 0 && comp.bruto === 0) return <><SinCicloBarrio /><SinCombinacion /></>;

  const pctNeto = (v: number) => (comp.neto ? (v / comp.neto) * 100 : null);
  const pctBruto = (v: number) => (comp.bruto ? (v / comp.bruto) * 100 : null);
  const tiposVisibles = comp.tipos.filter((t) => t.valor !== 0);
  const evoPer = evo.map((e) => etiquetaCorta(e.periodo));
  const lectura: string[] = [
    `En ${etiquetaPeriodo(periodo)}, la cartera bruta (sin subsidios) es de ${fmtMillonesUno(comp.bruto)} y la neta ${fmtMillonesUno(comp.neto)}, después de ${fmtMillonesUno(Math.abs(comp.subsidios))} de subsidios y descuentos.`,
    `El recargo moratorio es ${fmtPct(pctNeto(comp.recargo))} de la cartera neta y ${fmtPct(pctBruto(comp.recargo))} de la bruta; frente al capital de servicios equivale a ${fmtPct(comp.capital ? (comp.recargo / comp.capital) * 100 : null)}.`,
  ];
  if (evo.length > 1) {
    const a = evo[0], z = evo[evo.length - 1];
    lectura.push(`Entre ${etiquetaCorta(a.periodo)} y ${etiquetaCorta(z.periodo)}, el recargo pasó de ${fmtPct(a.pctNeto)} a ${fmtPct(z.pctNeto)} de la cartera neta.`);
  }
  if (vieja) lectura.push(`La franja «${vieja.rotulo}» suma ${fmtMillonesUno(vieja.neto)} netos (${fmtPct(pctNeto(vieja.neto))} de la cartera neta).`);

  return (
    <>
      <div className="dash-sin-filtro-fila"><MarcaFiltro valores={{ uso, estrato }} onLimpiar={onLimpiar} /><SinCicloBarrio /></div>
      <div className="dash-aviso">
        <b>Describe la composición, no la causa; no hay contrato en esta fuente, el recargo por contrato no se puede obtener.</b> Neto = todos los conceptos; bruto = neto sin los subsidios y descuentos,
        que restan. Los tramos de edad usan la lectura provisional de límites (rótulos pendientes de confirmar).
      </div>

      <div className="dash-kpis">
        <Ficha etiqueta="Cartera neta" valor={fmtMillonesUno(comp.neto)} sub="con subsidios y descuentos restados" />
        <Ficha etiqueta="Cartera bruta" valor={fmtMillonesUno(comp.bruto)} sub="sin subsidios y descuentos" />
        <Ficha etiqueta="Subsidios y descuentos" valor={fmtMillonesUno(comp.subsidios)} sub={`${fmtPct(pctBruto(Math.abs(comp.subsidios)))} de la cartera bruta`} />
        <Ficha etiqueta="Recargo moratorio" valor={fmtMillonesUno(comp.recargo)} mal sub={`${fmtPct(pctNeto(comp.recargo))} de la neta · ${fmtPct(pctBruto(comp.recargo))} de la bruta`} />
        <Ficha etiqueta="Capital de servicios" valor={fmtMillonesUno(comp.capital)} sub={`${fmtPct(pctNeto(comp.capital))} de la neta · acueducto y alcantarillado`} />
        <Ficha etiqueta="Financiación e intereses" valor={fmtMillonesUno(comp.financiacion)} sub={`${fmtPct(pctNeto(comp.financiacion))} de la neta`} />
      </div>

      <div className="dash-fila"><div className="dash-carta">
        <h3>Composición de la cartera por tipo de concepto — {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-leer">Cómo leerlo: cada barra es un tipo de concepto en la cartera bruta; los subsidios y descuentos se restan aparte para llegar a la neta.</div>
        <BarrasApiladas
          datos={tiposVisibles.map((t) => ({ etiqueta: ROTULO_TIPO[t.tipo], valores: TIPOS_BRUTO.map((x) => (x === t.tipo ? Math.max(0, t.valor) : 0)) }))}
          series={TIPOS_BRUTO.map((t) => ({ nombre: ROTULO_TIPO[t], color: COLOR_TIPO[t] }))}
          formatoValor={fmtMillonesUno} margenIzq={190}
        />
        <TablaPlegable titulo="Datos: neta y bruta por tipo de concepto">
          <table className="dash-tabla num">
            <thead><tr><th>Tipo de concepto</th><th>Valor</th><th>% de la bruta</th><th>% de la neta</th></tr></thead>
            <tbody>
              {tiposVisibles.map((t) => (<tr key={t.tipo}><td>{ROTULO_TIPO[t.tipo]}</td><td className="num">{fmtMillonesUno(t.valor)}</td><td className="num">{fmtPct(t.pctBruto)}</td><td className="num">{fmtPct(t.pctNeto)}</td></tr>))}
              <tr className="dash-tramo-fila"><td>Cartera bruta</td><td className="num">{fmtMillonesUno(comp.bruto)}</td><td className="num">100,0 %</td><td className="num">{fmtPct(pctNeto(comp.bruto))}</td></tr>
              <tr><td>{ROTULO_TIPO.subsidios_descuentos}</td><td className="num">{fmtMillonesUno(comp.subsidios)}</td><td className="num">{fmtPct(pctBruto(comp.subsidios))}</td><td className="num">{fmtPct(pctNeto(comp.subsidios))}</td></tr>
              <tr className="dash-total"><td>Cartera neta</td><td className="num">{fmtMillonesUno(comp.neto)}</td><td className="num">{fmtPct(pctBruto(comp.neto))}</td><td className="num">100,0 %</td></tr>
            </tbody>
          </table>
        </TablaPlegable>
      </div></div>

      <div className="dash-fila-g2">
        <div className="dash-carta">
          <h3>Recargo moratorio frente al capital, por tramo de edad</h3>
          <div className="dash-leer">Cómo leerlo: en cada tramo, el capital de servicios (acueducto y alcantarillado, bruto) y el recargo moratorio.</div>
          <BarrasApiladas
            datos={rvc.map((r) => ({ etiqueta: r.rotulo, valores: [r.capital, r.recargo] }))}
            series={[{ nombre: "Capital de servicios", color: COLOR_TIPO.capital_alcantarillado }, { nombre: "Recargo moratorio", color: COLOR_TIPO.recargo_moratorio }]}
            formatoValor={fmtMillonesUno} margenIzq={150}
          />
          <TablaPlegable titulo="Datos: recargo y capital por tramo">
            <table className="dash-tabla num">
              <thead><tr><th>Tramo de edad</th><th>Capital</th><th>Recargo</th><th>Recargo ÷ capital</th><th>Recargo, % del neto del tramo</th></tr></thead>
              <tbody>{rvc.map((r) => (<tr key={r.llave}><td>{r.rotulo}</td><td className="num">{fmtMillonesUno(r.capital)}</td><td className="num">{fmtMillonesUno(r.recargo)}</td><td className="num">{r.razon == null ? "—" : fmtPct(r.razon)}</td><td className="num">{fmtPct(r.pctNeto)}</td></tr>))}</tbody>
            </table>
          </TablaPlegable>
          <NotaRotulos />
        </div>
        <div className="dash-carta">
          <h3>Evolución mensual del recargo moratorio</h3>
          <div className="dash-leer">Cómo leerlo: el recargo como porcentaje de la cartera neta y como porcentaje del capital de servicios, mes a mes.</div>
          <LineasPorcentaje
            etiquetas={evoPer}
            series={[
              { nombre: "Recargo, % de la cartera neta", color: COLOR_TIPO.recargo_moratorio, valores: evo.map((e) => e.pctNeto) },
              { nombre: "Recargo ÷ capital de servicios, %", color: COLOR_TIPO.capital_acueducto, valores: evo.map((e) => e.razon) },
            ]}
          />
          <TablaPlegable titulo="Datos: recargo por período">
            <table className="dash-tabla num">
              <thead><tr><th>Período</th><th>Recargo</th><th>Capital</th><th>Neta</th><th>% de la neta</th><th>÷ capital</th></tr></thead>
              <tbody>{evo.map((e) => (<tr key={e.periodo}><td>{etiquetaCorta(e.periodo)}</td><td className="num">{fmtMillonesUno(e.recargo)}</td><td className="num">{fmtMillonesUno(e.capital)}</td><td className="num">{fmtMillonesUno(e.neto)}</td><td className="num">{fmtPct(e.pctNeto)}</td><td className="num">{fmtPct(e.razon)}</td></tr>))}</tbody>
            </table>
          </TablaPlegable>
        </div>
      </div>

      <div className="dash-fila"><div className="dash-carta">
        <h3>Perfil de edad por tipo de concepto — {etiquetaPeriodo(periodo)}</h3>
        <div className="dash-leer">Cómo leerlo: cada barra es 100 % del valor de ese tipo, repartido por tramo de edad (el más oscuro es el más viejo).</div>
        <BarrasApiladas
          datos={perfil.map((p) => ({ etiqueta: ROTULO_TIPO[p.tipo], valores: p.tramos.map((t) => t.pct ?? 0) }))}
          series={TRAMOS.map((t, i) => ({ nombre: t.rotulo, color: perfil[0]?.tramos[i]?.color ?? "#999" }))}
          formatoValor={fmtPct} margenIzq={190}
        />
        <TablaPlegable titulo="Datos: % por tramo de edad de cada tipo">
          <table className="dash-tabla num">
            <thead><tr><th>Tipo de concepto</th>{TRAMOS.map((t) => <th key={t.llave}>{t.rotulo}</th>)}</tr></thead>
            <tbody>{perfil.map((p) => (<tr key={p.tipo}><td>{ROTULO_TIPO[p.tipo]}</td>{p.tramos.map((t) => <td key={t.llave} className="num">{fmtPct(t.pct)}</td>)}</tr>))}</tbody>
          </table>
        </TablaPlegable>
        <NotaRotulos />
      </div></div>

      <div className="dash-fila-g2">
        <div className="dash-carta">
          <h3>Subsidios y descuentos por estrato</h3>
          <div className="dash-leer">Cómo leerlo: lo que restan los subsidios y descuentos en cada estrato y qué parte de su cartera bruta representan.</div>
          <TablaPlegable titulo="Datos: subsidios y descuentos por estrato">
            <table className="dash-tabla num">
              <thead><tr><th>Estrato</th><th>Subsidios y descuentos</th><th>Cartera bruta</th><th>% de la bruta</th></tr></thead>
              <tbody>{subEst.map((s) => (<tr key={s.estrato}><td>{nom(s.estrato)}</td><td className="num">{fmtMillonesUno(s.subsidios)}</td><td className="num">{fmtMillonesUno(s.bruto)}</td><td className="num">{s.pct == null ? "—" : fmtPct(Math.abs(s.pct))}</td></tr>))}</tbody>
            </table>
          </TablaPlegable>
        </div>
        <div className="dash-carta">
          <h3>Subsidios y descuentos por tramo de edad</h3>
          <div className="dash-leer">Cómo leerlo: lo que restan los subsidios y descuentos en cada tramo y qué parte de la cartera bruta del tramo representan.</div>
          <TablaPlegable titulo="Datos: subsidios y descuentos por tramo de edad">
            <table className="dash-tabla num">
              <thead><tr><th>Tramo de edad</th><th>Subsidios y descuentos</th><th>Cartera bruta</th><th>% de la bruta</th></tr></thead>
              <tbody>{subEdad.map((s) => (<tr key={s.llave}><td>{s.rotulo}</td><td className="num">{fmtMillonesUno(s.subsidios)}</td><td className="num">{fmtMillonesUno(s.bruto)}</td><td className="num">{s.pct == null || s.bruto === 0 ? "—" : fmtPct(Math.abs(s.pct))}</td></tr>))}</tbody>
            </table>
          </TablaPlegable>
          <NotaRotulos />
        </div>
      </div>

      {vieja && (
        <div className="dash-fila"><div className="dash-carta">
          <h3>La franja más vieja, por separado — {vieja.rotulo}</h3>
          <div className="dash-leer">Cómo leerlo: de qué conceptos está hecha la cartera de la franja más vieja.</div>
          <div className="dash-kpis">
            <Ficha etiqueta={`Neta · ${vieja.rotulo}`} valor={fmtMillonesUno(vieja.neto)} mal sub={`${fmtPct(pctNeto(vieja.neto))} de la cartera neta`} />
            <Ficha etiqueta="Bruta de la franja" valor={fmtMillonesUno(vieja.bruto)} sub="sin subsidios y descuentos" />
            <Ficha etiqueta="Subsidios y descuentos de la franja" valor={fmtMillonesUno(vieja.subsidios)} sub={`${fmtPct(vieja.bruto ? (Math.abs(vieja.subsidios) / vieja.bruto) * 100 : null)} de su bruta`} />
          </div>
          <TablaPlegable titulo="Datos: tipos de concepto de la franja">
            <table className="dash-tabla num">
              <thead><tr><th>Tipo de concepto</th><th>Valor</th><th>% de la bruta de la franja</th></tr></thead>
              <tbody>{vieja.tipos.map((t) => (<tr key={t.tipo}><td>{ROTULO_TIPO[t.tipo]}</td><td className="num">{fmtMillonesUno(t.valor)}</td><td className="num">{fmtPct(t.pctBruto)}</td></tr>))}</tbody>
            </table>
          </TablaPlegable>
        </div></div>
      )}

      <div className="dash-fila"><Lectura lineas={lectura} /></div>
      <MetodologiaConcepto />
    </>
  );
}

const NotaRotulos = () => <div className="dash-nota"><b>Rótulos pendientes de confirmar.</b> {notaRotulos(LECTURA)}</div>;

/** Metodología: cómo se agrupan los conceptos, con los códigos y nombres de cada tipo (sin cifras). */
export function MetodologiaConcepto() {
  const REGLA: Record<TipoConcepto, string> = {
    capital_alcantarillado: "Cargos del servicio de alcantarillado: cargo fijo, servicio y alcantarillado pluvial.",
    capital_acueducto: "Cargos del servicio de acueducto: cargo fijo y consumo.",
    recargo_moratorio: "El recargo por mora (código 6).",
    financiacion_capital: "Financiación de los cargos de los servicios y de su contribución (acuerdos de pago sobre el capital).",
    financiacion_recargo: "Financiación del recargo moratorio (código 1006).",
    financiacion_otros: "Financiación de otros cargos: conexión, obras, medidores, cortes, consumo excesivo y demás conceptos 1000 a 1999 o con nombre de financiación. Se separa de la financiación del capital para no rotularla mal.",
    interes_financiacion: "Intereses de financiación y de refinanciación.",
    contribucion: "Contribución de solidaridad sobre los cargos de servicio.",
    corte_susp_reconexion: "Cobros de corte, suspensión, reinstalación y reconexión que no son los conceptos EMD.",
    cargos_emd: "Conceptos EMD de corte, suspensión, reinstalación y reconexión (600, 602, 603, 605 y 606).",
    conexion_obras: "Conexión, medidores, accesorios, obras y ventas; incluye los cortes de acometida y de apique (170, 172 y 173), que son obras y no cortes del servicio.",
    otros: "Todo lo que no encaja en los demás tipos: consumo excesivo y sus recargos, aseo, ajustes, devoluciones, IVA y similares.",
    subsidios_descuentos: "Subsidios a cargo fijo y consumo de acueducto y alcantarillado y los descuentos a empleados. Restan (valores negativos).",
  };
  const orden: TipoConcepto[] = [...TIPOS_BRUTO, "subsidios_descuentos"];
  return (
    <div className="dash-fila"><div className="dash-carta dash-metodologia">
      <h3>Metodología de la cartera por concepto</h3>
      <ul>
        <li><b>Fuente.</b> El reporte de cartera por edades (<code>cartera_edades</code>): valor por concepto, uso, estrato y etiqueta de edad. No trae contrato, por eso esta zona describe la composición de la cartera y <b>no puede dar el recargo por contrato</b>. Los nombres de los conceptos salen del maestro de conceptos (<code>v_concepto_mapa</code>), no del reporte, que los trae truncados y con la codificación dañada.</li>
        <li><b>Neta y bruta.</b> La cartera neta es la suma de todos los conceptos; la bruta es la neta sin los subsidios y descuentos, que restan. Los subsidios van en su propio tipo para poder mostrar las dos.</li>
        <li><b>Tramos de edad.</b> Se agrupan las etiquetas del reporte con la misma lectura provisional de límites de Cartera por edad (rótulos pendientes de confirmar); la cartera financiada no tiene edad.</li>
        <li><b>Privacidad.</b> Solo agregados en pesos por uso, estrato, tipo y tramo. Si el grupo (uso, estrato) tiene menos de 5 contratos con deuda, o el uso o el estrato no son de la lista, su valor se agrupa en «Otros / sin clasificar». Sin contrato, barrio ni ciclo.</li>
        <li><b>Es una descripción, no una causa.</b> Que un tipo pese más en una edad o en un estrato no explica por qué.</li>
      </ul>
      <h4>Cómo se clasifican los conceptos (código → tipo)</h4>
      {orden.map((t) => (
        <details key={t} className="dash-detalle">
          <summary><b>{ROTULO_TIPO[t]}</b> · {CODIGOS_POR_TIPO[t].length} código(s)</summary>
          <div className="dash-nota">{REGLA[t]}</div>
          <div className="dash-tabla-scroll">
            <table className="dash-tabla"><thead><tr><th>Código</th><th>Nombre</th></tr></thead>
              <tbody>{CODIGOS_POR_TIPO[t].map((c) => <tr key={c.codigo}><td>{c.codigo}</td><td>{c.nombre}</td></tr>)}</tbody></table>
          </div>
        </details>
      ))}
    </div></div>
  );
}
