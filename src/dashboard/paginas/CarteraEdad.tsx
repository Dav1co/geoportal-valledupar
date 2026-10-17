import { Fragment, useMemo } from "react";
import type { CarteraEdadDim } from "../tipos";
import { BarrasApiladas, LineasPorcentaje, TablaPlegable } from "../graficas";
import { etiquetaCorta, etiquetaPeriodo, fmtPct } from "../formato";
import { MarcaFiltro } from "../Plegable";
import {
  ETIQUETAS_EDAD,
  LECTURA_PROVISIONAL,
  notaRotulos,
  rotuloEtiqueta,
  tramosAnuales,
} from "../edadCartera";
import {
  COLOR_TRAMO_EDAD,
  cortePor,
  cruceUsoEstrato,
  evolucionGrupos,
  filtrarEdad,
  fmtMillonesUno,
  fmtPuntos,
  fmtVariacionMillones,
  gruposPrincipales,
  periodoAnterior,
  periodosDe,
  resumenPeriodo,
  sumar,
  tramosConValor,
  valorGrupo,
  valorPorEtiqueta,
} from "../edadCarteraCalculo";

// Zonas de «Edad de la cartera» de Cartera desagregada. Todo sale de UNA dimensión (bi.v_cartera_edad_dim, sql/45), traída una sola vez con todos
// los períodos y filtrada en el navegador por uso y estrato; por eso las fichas, las tablas y las gráficas cuadran entre sí. La dimensión no
// tiene ciclo, comuna ni barrio (el ciclo de cartera_edades no coincide con el de cartera_contrato; sql/45), y así se avisa en cada zona.

const LECTURA = LECTURA_PROVISIONAL;
const TRAMOS = tramosAnuales(LECTURA);
const rotuloMayor360 = LECTURA === "superior" ? "Más de 360 días" : "360 días o más";

type FiltroProps = { uso: string; estrato: string };
type BaseProps = FiltroProps & { filas: CarteraEdadDim[]; periodo: string };

/** Aviso fijo mientras la lectura de los límites no esté confirmada por Facturación. */
export function NotaRotulosPendientes() {
  return (
    <div className="dash-nota">
      <b>Rótulos pendientes de confirmar.</b> {notaRotulos(LECTURA)} Si Facturación confirma otra lectura, solo cambian los rótulos y los
      límites de cada tramo; los valores en pesos no cambian.
    </div>
  );
}

export const SinCicloBarrio = () => <div className="dash-sin-filtro">No depende de ciclo, comuna ni barrio.</div>;

function SinDatosCombinacion() {
  return (
    <div className="dash-aviso">
      Esta combinación de uso y estrato no tiene cartera propia en la dimensión de edad: por el mínimo de 5 contratos por (uso, estrato) se agrupa en{" "}
      <b>Otros / sin clasificar</b>. Elija otra combinación o limpie el filtro.
    </div>
  );
}

const signo = (v: number) => (v < 0 ? "−" : "+");
function variacion(actual: number, previo: number | null | undefined, etiquetaPrevio: string | null) {
  if (previo == null || etiquetaPrevio == null) return "sin mes anterior en la serie";
  const d = actual - previo;
  const pct = previo ? (d / previo) * 100 : null;
  return `${fmtVariacionMillones(d)}${pct == null ? "" : ` (${signo(pct)}${fmtPct(Math.abs(pct))})`} frente a ${etiquetaPeriodo(etiquetaPrevio)}`;
}

export function Ficha({ etiqueta, valor, sub, mal = false }: { etiqueta: string; valor: string; sub: string; mal?: boolean }) {
  return (
    <div className={`dash-carta dash-kpi ${mal ? "dash-kpi-mal" : ""}`}>
      <div className="dash-eti">{etiqueta}</div>
      <div className="dash-valor num">{valor}</div>
      <div className="dash-sub2">{sub}</div>
    </div>
  );
}

const cartaTitulo = (t: string) => <h3>{t}</h3>;

// ---------------- Zona 1 · Panorama ----------------
export function PanoramaEdad({ filas, periodo, uso, estrato, onLimpiar }: BaseProps & { onLimpiar: () => void }) {
  const filtradas = useMemo(() => filtrarEdad(filas, uso, estrato), [filas, uso, estrato]);
  const periodos = useMemo(() => periodosDe(filas), [filas]);
  const ant = periodoAnterior(periodos, periodo);
  const act = useMemo(() => resumenPeriodo(filtradas, periodo, ETIQUETAS_EDAD, LECTURA), [filtradas, periodo]);
  const prev = useMemo(() => (ant ? resumenPeriodo(filtradas, ant, ETIQUETAS_EDAD, LECTURA) : null), [filtradas, ant]);
  const t = act.total;
  const pct = (v: number) => (t ? (v / t) * 100 : null);
  const pp = (a: number, p: number | undefined) => (prev && p != null && prev.total && t ? pct(a)! - (p / prev.total) * 100 : null);
  const tramoMayor = act.tramos.find((x) => x.llave === "mayor1800");

  return (
    <>
      <div className="dash-sin-filtro-fila">
        <MarcaFiltro valores={{ uso, estrato }} onLimpiar={onLimpiar} />
        <SinCicloBarrio />
      </div>
      {t === 0 ? (
        <SinDatosCombinacion />
      ) : (
        <>
          <div className="dash-kpis">
            <Ficha etiqueta="Cartera total" valor={fmtMillonesUno(t)} sub={variacion(t, prev?.total, ant)} />
            <Ficha
              etiqueta="Cartera no financiada"
              valor={fmtMillonesUno(act.noFinanciada)}
              sub={`${fmtPct(pct(act.noFinanciada))} del total · ${variacion(act.noFinanciada, prev?.noFinanciada, ant)}`}
            />
            <Ficha
              etiqueta="Cartera financiada"
              valor={fmtMillonesUno(act.financiada)}
              sub={`${fmtPct(pct(act.financiada))} del total · acuerdos de pago, sin edad · ${variacion(act.financiada, prev?.financiada, ant)}`}
            />
            <Ficha
              etiqueta={rotuloMayor360}
              valor={fmtMillonesUno(act.mayor360)}
              sub={`${fmtPct(pct(act.mayor360))} del total · ${fmtPuntos(pp(act.mayor360, prev?.mayor360))} · ${variacion(act.mayor360, prev?.mayor360, ant)} · lectura provisional`}
              mal
            />
            <Ficha
              etiqueta={tramoMayor?.rotulo ?? "Más de 1.800 días"}
              valor={fmtMillonesUno(act.mayor1800)}
              sub={`${fmtPct(pct(act.mayor1800))} del total · ${fmtPuntos(pp(act.mayor1800, prev?.mayor1800))} · ${variacion(act.mayor1800, prev?.mayor1800, ant)}`}
              mal
            />
          </div>

          <div className="dash-fila">
            <div className="dash-carta">
              {cartaTitulo(`Cartera por tramo de edad — ${etiquetaPeriodo(periodo)}`)}
              <div className="dash-leer">Cómo leerlo: la barra reparte el total de la cartera entre los tramos de edad de la deuda; el más oscuro es el más viejo.</div>
              <BarrasApiladas
                datos={[{ etiqueta: "Cartera", valores: act.tramos.map((x) => x.valor) }]}
                series={act.tramos.map((x) => ({ nombre: x.rotulo, color: x.color }))}
                formatoValor={fmtMillonesUno}
                margenIzq={60}
              />
              <TablaPlegable titulo="Datos: cartera por tramo de edad">
                <table className="dash-tabla num">
                  <thead><tr><th>Tramo de edad</th><th>Cartera</th><th>% del total</th></tr></thead>
                  <tbody>
                    {act.tramos.map((x) => (
                      <tr key={x.llave}>
                        <td>{x.rotulo}</td>
                        <td className="num">{fmtMillonesUno(x.valor)}</td>
                        <td className="num">{fmtPct(x.pct)}</td>
                      </tr>
                    ))}
                    <tr className="dash-total"><td>Total</td><td className="num">{fmtMillonesUno(t)}</td><td className="num">100,0 %</td></tr>
                  </tbody>
                </table>
              </TablaPlegable>
              <div className="dash-nota">
                Fuente: reporte de cartera por edades (valor, no contratos). La cartera financiada no tiene edad asignada. Es una descripción de dónde
                está la cartera, no una causa.
              </div>
              <NotaRotulosPendientes />
            </div>
          </div>
        </>
      )}
    </>
  );
}

// ---------------- Zona 2 · Antigüedad (vejez) ----------------
export function AntiguedadEdad({ filas, periodo, uso, estrato }: BaseProps) {
  const filtradas = useMemo(() => filtrarEdad(filas, uso, estrato), [filas, uso, estrato]);
  const periodos = useMemo(() => periodosDe(filas), [filas]);
  const delPeriodo = useMemo(() => filtradas.filter((f) => f.periodo === periodo), [filtradas, periodo]);
  const porEt = useMemo(() => valorPorEtiqueta(delPeriodo, ETIQUETAS_EDAD), [delPeriodo]);
  const tramos = useMemo(() => tramosConValor(delPeriodo, ETIQUETAS_EDAD, LECTURA), [delPeriodo]);
  const evo = useMemo(() => evolucionGrupos(filtradas, periodos, ETIQUETAS_EDAD, LECTURA), [filtradas, periodos]);
  const total = sumar(delPeriodo);
  const pct = (v: number) => (total ? (v / total) * 100 : null);

  if (total === 0) return <SinDatosCombinacion />;

  // Una fila por etiqueta de origen, coloreada por su tramo anual: la serie del tramo lleva el valor y las demás ceros.
  const datosEt = ETIQUETAS_EDAD.map((e) => ({
    etiqueta: rotuloEtiqueta(e, LECTURA),
    valores: TRAMOS.map((t) => (t.etiquetas.includes(e) ? porEt[e] : 0)),
  }));

  const etiquetasPer = evo.filas.map((f) => etiquetaCorta(f.periodo));
  const seriesEvo = evo.grupos.map((g, k) => ({
    nombre: g.rotulo,
    color: g.color,
    valores: evo.filas.map((f) => (f.total ? (f.valores[k] / f.total) * 100 : null)),
  }));

  return (
    <>
      <SinCicloBarrio />
      <div className="dash-fila-g2">
        <div className="dash-carta">
          {cartaTitulo(`Cartera por etiqueta de edad — ${etiquetaPeriodo(periodo)}`)}
          <div className="dash-leer">
            Cómo leerlo: una barra por cada una de las 19 etiquetas del reporte de origen, coloreada por su tramo anual. Las etiquetas mensuales pesan
            poco; el peso está en los tramos anuales y, sobre todo, en el más viejo.
          </div>
          <BarrasApiladas
            datos={datosEt}
            series={TRAMOS.map((t) => ({ nombre: t.rotulo, color: COLOR_TRAMO_EDAD[t.llave] }))}
            formatoValor={fmtMillonesUno}
            margenIzq={150}
          />
          <NotaRotulosPendientes />
        </div>

        <div className="dash-carta">
          {cartaTitulo("Tramos anuales y etiquetas de origen")}
          <TablaPlegable titulo="Datos: tramos anuales y las 19 etiquetas">
            <table className="dash-tabla num">
              <thead><tr><th>Tramo / etiqueta</th><th>Etiqueta de origen</th><th>Cartera</th><th>% del total</th></tr></thead>
              <tbody>
                {tramos.map((x, i) => (
                  <Fragment key={x.llave}>
                    <tr className="dash-tramo-fila">
                      <td>{x.rotulo}</td><td></td>
                      <td className="num">{fmtMillonesUno(x.valor)}</td>
                      <td className="num">{fmtPct(x.pct)}</td>
                    </tr>
                    {TRAMOS[i].etiquetas.map((e) => (
                      <tr key={e}>
                        <td className="dash-sangria">{rotuloEtiqueta(e, LECTURA)}</td>
                        <td>{e === "sin_edad" ? "sin edad" : e}</td>
                        <td className="num">{fmtMillonesUno(porEt[e])}</td>
                        <td className="num">{fmtPct(pct(porEt[e]))}</td>
                      </tr>
                    ))}
                  </Fragment>
                ))}
                <tr className="dash-total"><td>Total</td><td></td><td className="num">{fmtMillonesUno(total)}</td><td className="num">100,0 %</td></tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">Los tramos anuales se destacan en negrita; debajo de cada uno van las etiquetas del reporte que lo componen.</div>
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          {cartaTitulo(`Evolución de la composición por edad — ${etiquetaCorta(periodos[0] ?? periodo)} a ${etiquetaCorta(periodos[periodos.length - 1] ?? periodo)}`)}
          <div className="dash-leer">Cómo leerlo: cada línea es el porcentaje del total de cartera de cada mes que está en ese grupo de edad.</div>
          <LineasPorcentaje etiquetas={etiquetasPer} series={seriesEvo} />
          <TablaPlegable titulo="Datos: evolución por período">
            <table className="dash-tabla num">
              <thead>
                <tr>
                  <th>Período</th><th>Total</th>
                  {evo.grupos.map((g) => <th key={g.llave}>{g.rotulo} · $ M</th>)}
                  {evo.grupos.map((g) => <th key={`p${g.llave}`}>{g.rotulo} · %</th>)}
                </tr>
              </thead>
              <tbody>
                {evo.filas.map((f) => (
                  <tr key={f.periodo}>
                    <td>{etiquetaPeriodo(f.periodo)}</td>
                    <td className="num">{fmtMillonesUno(f.total)}</td>
                    {f.valores.map((v, k) => <td key={k} className="num">{fmtMillonesUno(v)}</td>)}
                    {f.valores.map((v, k) => <td key={`p${k}`} className="num">{fmtPct(f.total ? (v / f.total) * 100 : null)}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Serie de {periodos.length} períodos con detalle por edad (incluye junio de 2026). Los grupos son los de la lectura provisional de límites.
          </div>
        </div>
      </div>
    </>
  );
}

// ---------------- Zona 3 · Por uso y estrato ----------------
export function UsoEstratoEdad({ filas, periodo, uso, estrato }: BaseProps) {
  const filtradas = useMemo(() => filtrarEdad(filas, uso, estrato), [filas, uso, estrato]);
  const porUso = useMemo(() => cortePor(filtradas, periodo, "uso", ETIQUETAS_EDAD, LECTURA), [filtradas, periodo]);
  const porEstrato = useMemo(() => cortePor(filtradas, periodo, "estrato", ETIQUETAS_EDAD, LECTURA), [filtradas, periodo]);
  const cruce = useMemo(() => cruceUsoEstrato(filtradas, periodo), [filtradas, periodo]);
  const grupos = gruposPrincipales(LECTURA);
  const total = cruce.total;
  if (total === 0) return <SinDatosCombinacion />;

  const perfil = (filasCorte: typeof porUso) => ({
    datos: filasCorte.map((c) => ({ etiqueta: c.nombre, valores: c.tramos.map((t) => t.pct ?? 0) })),
    series: TRAMOS.map((t) => ({ nombre: t.rotulo, color: COLOR_TRAMO_EDAD[t.llave] })),
  });
  const tabla = (filasCorte: typeof porUso, titulo: string) => (
    <TablaPlegable titulo={`Datos: ${titulo}`}>
      <table className="dash-tabla num">
        <thead>
          <tr>
            <th>{titulo.startsWith("uso") ? "Uso" : "Estrato"}</th><th>Cartera</th><th>% del total</th>
            {grupos.map((g) => <th key={g.llave}>{g.rotulo} · % de su cartera</th>)}
          </tr>
        </thead>
        <tbody>
          {filasCorte.map((c) => (
            <tr key={c.codigo}>
              <td>{c.nombre}</td>
              <td className="num">{fmtMillonesUno(c.valor)}</td>
              <td className="num">{fmtPct(c.pct)}</td>
              {grupos.map((g) => <td key={g.llave} className="num">{fmtPct(c.valor ? (valorGrupo(c.tramos, g) / c.valor) * 100 : null)}</td>)}
            </tr>
          ))}
          <tr className="dash-total"><td>Total</td><td className="num">{fmtMillonesUno(total)}</td><td className="num">100,0 %</td>{grupos.map((g) => <td key={g.llave}></td>)}</tr>
        </tbody>
      </table>
    </TablaPlegable>
  );

  return (
    <>
      <SinCicloBarrio />
      <div className="dash-fila-g2">
        <div className="dash-carta">
          {cartaTitulo(`Perfil de edad por uso — ${etiquetaPeriodo(periodo)}`)}
          <div className="dash-leer">Cómo leerlo: cada barra es 100 % de la cartera de ese uso, repartida por tramo de edad.</div>
          <BarrasApiladas {...perfil(porUso)} formatoValor={fmtPct} margenIzq={130} />
          {tabla(porUso, "uso")}
        </div>
        <div className="dash-carta">
          {cartaTitulo(`Perfil de edad por estrato — ${etiquetaPeriodo(periodo)}`)}
          <div className="dash-leer">Cómo leerlo: cada barra es 100 % de la cartera de ese estrato, repartida por tramo de edad (mezcla de tramos).</div>
          <BarrasApiladas {...perfil(porEstrato)} formatoValor={fmtPct} margenIzq={130} />
          {tabla(porEstrato, "estrato")}
        </div>
      </div>

      <div className="dash-fila">
        <div className="dash-carta">
          {cartaTitulo("Uso × estrato: cartera")}
          <div className="dash-leer">Cómo leerlo: filas = uso, columnas = estrato; cada celda es la cartera de esa combinación en $ M.</div>
          <TablaPlegable titulo="Datos: cruce de uso y estrato">
            <table className="dash-tabla num">
              <thead><tr><th>Uso \ Estrato</th>{cruce.estratos.map((e) => <th key={e.codigo}>{e.nombre}</th>)}<th>Total</th></tr></thead>
              <tbody>
                {cruce.usos.map((u, i) => (
                  <tr key={u.codigo}>
                    <td>{u.nombre}</td>
                    {cruce.celdas[i].map((v, j) => <td key={j} className="num">{v ? fmtMillonesUno(v) : "—"}</td>)}
                    <td className="num">{fmtMillonesUno(cruce.celdas[i].reduce((a, b) => a + b, 0))}</td>
                  </tr>
                ))}
                <tr className="dash-total">
                  <td>Total</td>
                  {cruce.estratos.map((e, j) => <td key={e.codigo} className="num">{fmtMillonesUno(cruce.celdas.reduce((s, fila) => s + fila[j], 0))}</td>)}
                  <td className="num">{fmtMillonesUno(total)}</td>
                </tr>
              </tbody>
            </table>
          </TablaPlegable>
          <div className="dash-nota">
            Las combinaciones de uso y estrato con menos de 5 contratos se agrupan en «Otros / sin clasificar»; por eso algunas celdas aparecen vacías
            aunque exista cartera (queda dentro de Otros). Las sumas no cambian.
          </div>
          <NotaRotulosPendientes />
        </div>
      </div>
    </>
  );
}

// ---------------- Zona 5 · Metodología y sustento ----------------
export function MetodologiaEdad() {
  return (
    <div className="dash-carta dash-metodologia">
      <h3>Metodología y sustento de la edad de la cartera</h3>
      <ul>
        <li>
          <b>Fuentes.</b> El reporte de cartera por edades (<code>cartera_edades</code>) aporta el valor por etiqueta de edad, uso, estrato y servicio; trae
          valores, no contratos, y no tiene número de contrato. El detalle por contrato (<code>cartera_contrato</code>) solo se usa para contar contratos con
          deuda por (uso, estrato) y aplicar el mínimo de 5. La zona «Por ciclo y barrio» sale de otra tabla ya publicada, con ciclo y barrio.
        </li>
        <li>
          <b>Qué es la edad de la cartera.</b> Es el tiempo que lleva vencida una deuda. El reporte la entrega en 18 etiquetas (de 30 en 30 días hasta 360,
          y luego 720, 1080, 1440, 1800 y 1801 = más de 1.800 días). La cartera <b>financiada</b> (acuerdos de pago) no tiene edad asignada y se muestra
          aparte.
        </li>
        <li>
          <b>Lectura de los límites: pendiente de confirmar.</b> Provisionalmente, cada etiqueta es el <b>límite superior</b> de su tramo (720 = 361 a 720 días).
          La evidencia: la etiqueta 360 pesa lo de un mes y la 720 lo de un año completo. La lectura inferior (360 = 360 a 719) es la que usa el tablero
          anterior, y arroja un porcentaje algo mayor de cartera mayor a 360 días que la lectura provisional.
        </li>
        <li>
          <b>Privacidad.</b> Solo se publican valores agregados en pesos por etiqueta, uso, estrato y servicio: ningún contrato, barrio, ciclo ni persona. Si
          un (uso, estrato) tiene menos de 5 contratos con deuda, o el uso o el estrato no son de la lista, su valor se agrupa en «Otros / sin clasificar».
          Una celda etiqueta × uso × estrato puede tener menos de 5 contratos aunque su grupo tenga 5 o más; es un valor en pesos, no un conteo.
        </li>
        <li>
          <b>Cuadre.</b> El total por período es el del reporte de edades y coincide con el de la tabla de ciclo y barrio. Frente al reporte resumen de cartera
          hay una diferencia menor entre marzo y septiembre de 2026; su causa no está determinada. Frente al
          detalle por contrato coincide en siete de ocho períodos (febrero de 2026 tiene una diferencia menor).
        </li>
        <li>
          <b>Es una descripción, no una causa.</b> Estas cifras muestran dónde está la cartera y qué tan vieja es; no explican por qué ni indican qué
          gestionar.
        </li>
        <li>
          <b>Ciclo y barrio.</b> El ciclo del reporte de edades no coincide con el del detalle por contrato, por eso las zonas de edad no se pueden abrir por
          ciclo ni por barrio.
        </li>
      </ul>
    </div>
  );
}
