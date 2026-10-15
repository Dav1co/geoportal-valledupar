import { useMemo, type ReactNode } from "react";
import { comoDesviacionDim, comoMedidorAntigDim, comoObservacionDim } from "../tipos";
import { ETIQ_CON_MEDIDOR, ETIQ_CON_MEDIDOR_CAP, ETIQ_SIN_MEDIDOR, etiquetaPeriodo, fmtEntero, fmtPct } from "../formato";
import { useRama, type Estado } from "../useRama";
import { CODIGO_CON_LECTURA, SIN_MEDIDOR, textoObservacion } from "./ContratosLectura";

// Fila de indicadores de lectura y medición a NIVEL EMPRESA, junto al IPUF de
// Pérdidas: suma de todas las filas de cada rama (sin ciclo, uso ni estrato), en
// el mismo período seleccionado. Fuentes: bi.v_observacion_dim (sql/29),
// bi.v_medidor_antig_dim (sql/30) y bi.v_desviacion_dim (sql/27, cero sostenido).
// Cada tarjeta maneja su propio estado: un fallo en una rama no rompe la página.
// Son indicadores operativos del mismo período; no establecen por sí solos una
// relación causal con el IPUF.

const BANDAS_CON_FECHA = new Set(["0-5", "5-10", "10-15", ">15"]);
const N_CAUSALES = 3;

const pct = (parte: number, total: number) => (total > 0 ? (parte / total) * 100 : null);

// Tarjeta con su propio estado: cargando, error con reintento, sin dato ("—").
function Tarjeta<T>({
  titulo, estado, sinDato, children,
}: {
  titulo: string;
  estado: Estado<T>;
  sinDato: string;                 // texto cuando la rama no trae filas
  children: (datos: T[]) => ReactNode;
}) {
  let cuerpo: ReactNode;
  if (estado.error) {
    cuerpo = (
      <>
        <div className="dash-valor num">—</div>
        <div className="dash-sub2">
          No se pudo cargar.{" "}
          <button className="dash-boton" onClick={estado.recargar}>Reintentar</button>
        </div>
      </>
    );
  } else if (estado.datos == null) {
    cuerpo = <div className="dash-valor num">…</div>;
  } else if (estado.datos.length === 0) {
    cuerpo = (
      <>
        <div className="dash-valor num">—</div>
        <div className="dash-sub2">{sinDato}</div>
      </>
    );
  } else {
    cuerpo = children(estado.datos);
  }
  return (
    <div className="dash-carta dash-kpi">
      <div className="dash-eti">{titulo}</div>
      {cuerpo}
    </div>
  );
}

const SIN_CONSUMO = "Sin datos de lectura para este período";

export function IndicadoresLectura({ periodo }: { periodo: string }) {
  const obs = useRama("v_observacion_dim", periodo, comoObservacionDim);
  const ant = useRama("v_medidor_antig_dim", periodo, comoMedidorAntigDim);
  const des = useRama("v_desviacion_dim", periodo, comoDesviacionDim);

  // Totales de v_observacion_dim a nivel empresa (una sola pasada).
  const t = useMemo(() => {
    const filas = obs.datos ?? [];
    let total = 0, sinMedidor = 0, conMedidor = 0, sinAvance = 0, cero = 0;
    const m = new Map<string, { texto: string; codigo: number | null; contratos: number }>();
    for (const x of filas) {
      total += x.contratos;
      cero += x.contratos_cero;
      if (!x.con_medidor) sinMedidor += x.contratos;
      else {
        conMedidor += x.contratos;
        if (x.resultado_lectura !== "avance") sinAvance += x.contratos;
      }
      if (x.observacion !== SIN_MEDIDOR && x.codigo_observacion !== CODIGO_CON_LECTURA) {
        const it = m.get(x.observacion) ?? { texto: textoObservacion(x.observacion), codigo: x.codigo_observacion, contratos: 0 };
        it.contratos += x.contratos;
        m.set(x.observacion, it);
      }
    }
    const causales = [...m.values()]
      .sort((a, b) => b.contratos - a.contratos || (a.codigo ?? -1) - (b.codigo ?? -1))
      .slice(0, N_CAUSALES);
    return { total, sinMedidor, conMedidor, sinAvance, cero, causales };
  }, [obs.datos]);

  return (
    <>
      <div className="dash-fila"><div className="dash-carta">
        <h3>Lectura y medición — {etiquetaPeriodo(periodo)}</h3>
      </div></div>

      <div className="dash-kpis">
        <Tarjeta titulo={`Contratos ${ETIQ_SIN_MEDIDOR}`} estado={obs} sinDato={SIN_CONSUMO}>
          {() => (
            <>
              <div className="dash-valor num">{fmtEntero(t.sinMedidor)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(t.sinMedidor, t.total))} de los contratos</div>
            </>
          )}
        </Tarjeta>

        <Tarjeta titulo={`${ETIQ_CON_MEDIDOR_CAP} y sin avance de lectura`} estado={obs} sinDato={SIN_CONSUMO}>
          {() => (
            <>
              <div className="dash-valor num">{fmtEntero(t.sinAvance)}</div>
              <div className="dash-sub2 num">
                {fmtPct(pct(t.sinAvance, t.conMedidor))} de los {fmtEntero(t.conMedidor)} contratos {ETIQ_CON_MEDIDOR}{" "}
                (lectura igual, menor o sin lectura)
              </div>
            </>
          )}
        </Tarjeta>

        <Tarjeta titulo="Con consumo cobrado en cero" estado={obs} sinDato={SIN_CONSUMO}>
          {() => (
            <>
              <div className="dash-valor num">{fmtEntero(t.cero)}</div>
              <div className="dash-sub2 num">{fmtPct(pct(t.cero, t.total))} de los contratos</div>
            </>
          )}
        </Tarjeta>

        <Tarjeta
          titulo="Con cero sostenido (6 meses)"
          estado={des}
          sinDato="Disponible solo con 6 meses de historia en facturación"
        >
          {(filas) => {
            const sostenido = filas.reduce((s, x) => s + x.contratos_cero_6m, 0);
            const total = filas.reduce((s, x) => s + x.contratos, 0);
            return (
              <>
                <div className="dash-valor num">{fmtEntero(sostenido)}</div>
                <div className="dash-sub2 num">
                  {fmtPct(pct(sostenido, total))} sobre contratos facturados ({fmtEntero(total)})
                </div>
              </>
            );
          }}
        </Tarjeta>

        <Tarjeta titulo="Medidores con más de 15 años" estado={ant} sinDato={SIN_CONSUMO}>
          {(filas) => {
            let conFecha = 0, viejos = 0;
            for (const x of filas) {
              if (BANDAS_CON_FECHA.has(x.banda_antiguedad)) {
                conFecha += x.contratos;
                if (x.banda_antiguedad === ">15") viejos += x.contratos;
              }
            }
            return conFecha === 0 ? (
              <>
                <div className="dash-valor num">—</div>
                <div className="dash-sub2">Antigüedad disponible desde 202605</div>
              </>
            ) : (
              <>
                <div className="dash-valor num">{fmtEntero(viejos)}</div>
                <div className="dash-sub2 num">
                  {fmtPct(pct(viejos, conFecha))} de los {fmtEntero(conFecha)} medidores con fecha de instalación
                </div>
              </>
            );
          }}
        </Tarjeta>

        <Tarjeta titulo="Observaciones más frecuentes" estado={obs} sinDato={SIN_CONSUMO}>
          {() => (
            <ol className="dash-sub2 num" style={{ margin: 0, paddingLeft: "1.2em" }}>
              {t.causales.map((c) => (
                <li key={c.texto}>
                  {c.texto}: <b>{fmtEntero(c.contratos)}</b> ({fmtPct(pct(c.contratos, t.total))})
                </li>
              ))}
            </ol>
          )}
        </Tarjeta>
      </div>

      <div className="dash-fila"><div className="dash-carta">
        <div className="dash-nota">
          Indicadores operativos de lectura y medición del mismo período. No establecen
          por sí solos una relación causal con el IPUF.
        </div>
      </div></div>
    </>
  );
}
