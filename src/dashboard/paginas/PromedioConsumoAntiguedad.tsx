import { useMemo, useState } from "react";
import type { MedidorAntigDim } from "../tipos";
import { etiquetaPeriodo, fmtDecimal, fmtEntero, rotuloMostrado } from "../formato";
import { LineasPorcentaje, TablaPlegable } from "../graficas";
import { TODOS } from "../PanelFiltros";
import { PRIMER_PERIODO_ANTIGUEDAD, SIN_MEDIDOR } from "../lecturaComun";

// Promedio de consumo por antigüedad del medidor (bi.v_medidor_antig_dim, sql/30, columna m3_cargos):
// m³ por contrato = m3_cargos ÷ contratos, por banda de antigüedad. Abre en Residencial por estrato.
// Las celdas con menos de 5 contratos no se muestran: se agrupan en «Otros».

const MIN_CONTRATOS = 5;
const BANDAS = ["0-5", "5-10", "10-15", ">15", "Sin fecha", SIN_MEDIDOR];
const etiquetaBanda = (b: string) => (b === "Sin fecha" || b === SIN_MEDIDOR ? rotuloMostrado(b) : `${b} años`);
const COLORES = ["#0A2540", "#0E7C86", "#C98A2D", "#8FB4CE", "#7B5EA7", "#C0392B"];
const TEXTO = {
  titulo: "Promedio de consumo por antigüedad del medidor",
  definicion: "Metros cúbicos cobrados por contrato (consumo cobrado ÷ contratos) según los años cumplidos del medidor.",
  nota: "Promedio simple del universo; en usos no residenciales lo determinan pocos contratos grandes.",
  nota15: "La banda de más de 15 años incluye contratos con fecha de instalación 1986-01-01, de antigüedad desconocida.",
  otros: "Otros (menos de 5 contratos)",
};
const nombreEstrato = (s: string) => s.replace(/^ESTRATO\s+/i, "Estrato ");

type Celda = { contratos: number; m3: number };
const vacia = (): Celda => ({ contratos: 0, m3: 0 });

export function PromedioConsumoAntiguedad({ filas, periodo }: { filas: MedidorAntigDim[]; periodo: string }) {
  const usos = useMemo(() => [...new Set(filas.map((x) => x.categoria))].sort((a, b) => a.localeCompare(b, "es")), [filas]);
  const estratos = useMemo(
    () => [...new Set(filas.filter((x) => x.categoria === "Residencial" && /^ESTRATO/i.test(x.subcategoria)).map((x) => x.subcategoria))].sort(),
    [filas],
  );
  // Por defecto: Residencial, desagregado por estrato.
  const [uso, setUso] = useState("Residencial");
  const [estrato, setEstrato] = useState(TODOS);
  const usoEf = uso === TODOS || usos.includes(uso) ? uso : TODOS;
  const porEstrato = usoEf === "Residencial" && estrato === TODOS;

  const { grupos, otros, hayDato } = useMemo(() => {
    const sel = filas.filter(
      (x) =>
        (usoEf === TODOS || x.categoria === usoEf) &&
        (usoEf !== "Residencial" || estrato === TODOS || x.subcategoria === estrato),
    );
    const claveGrupo = (x: MedidorAntigDim) =>
      porEstrato ? (/^ESTRATO/i.test(x.subcategoria) ? nombreEstrato(x.subcategoria) : null)
        : usoEf === TODOS ? "Todos los usos"
        : usoEf === "Residencial" ? nombreEstrato(estrato) : usoEf;
    const m = new Map<string, Map<string, Celda>>();
    let hayDato = false;
    for (const x of sel) {
      const g = claveGrupo(x);
      if (g == null) continue;
      if (x.m3_cargos != null) hayDato = true;
      const porBanda = m.get(g) ?? new Map<string, Celda>();
      const c = porBanda.get(x.banda_antiguedad) ?? vacia();
      c.contratos += x.contratos;
      c.m3 += x.m3_cargos ?? 0;
      porBanda.set(x.banda_antiguedad, c);
      m.set(g, porBanda);
    }
    // Celdas con menos de 5 contratos: fuera de las series y sumadas por banda en «Otros».
    const otros = new Map<string, Celda>();
    const grupos = [...m.entries()].sort((a, b) => a[0].localeCompare(b[0], "es")).map(([nombre, porBanda]) => {
      const prom = BANDAS.map((b) => {
        const c = porBanda.get(b);
        if (!c || c.contratos === 0) return null;
        if (c.contratos < MIN_CONTRATOS) {
          const o = otros.get(b) ?? vacia();
          o.contratos += c.contratos; o.m3 += c.m3; otros.set(b, o);
          return null;
        }
        return { contratos: c.contratos, prom: c.m3 / c.contratos };
      });
      return { nombre, prom };
    });
    return { grupos, otros, hayDato };
  }, [filas, usoEf, estrato, porEstrato]);

  const encabezado = (
    <>
      <h3>{TEXTO.titulo} — {etiquetaPeriodo(periodo)}</h3>
      <div className="dash-nota">{TEXTO.definicion}</div>
    </>
  );
  if (periodo < PRIMER_PERIODO_ANTIGUEDAD) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {encabezado}
        <div className="dash-estado">La antigüedad del medidor está disponible desde {PRIMER_PERIODO_ANTIGUEDAD}.</div>
      </div></div>
    );
  }
  if (!hayDato) {
    return (
      <div className="dash-fila"><div className="dash-carta">
        {encabezado}
        <div className="dash-estado">Sin consumo por antigüedad para este período y filtro.</div>
      </div></div>
    );
  }

  const series = grupos.map((g, i) => ({
    nombre: g.nombre, color: COLORES[i % COLORES.length], valores: g.prom.map((c) => (c ? c.prom : null)),
  }));
  const fmtM3 = (v: number) => `${fmtDecimal(v, 1)} m³`;

  return (
    <div className="dash-fila"><div className="dash-carta">
      {encabezado}
      <div className="dash-filtros-bloque">
        <label>
          Uso
          <select value={usoEf} onChange={(e) => { setUso(e.target.value); setEstrato(TODOS); }}>
            <option value={TODOS}>Todos</option>
            {usos.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
        </label>
        {usoEf === "Residencial" ? (
          <label>
            Estrato
            <select value={estrato} onChange={(e) => setEstrato(e.target.value)}>
              <option value={TODOS}>Por estrato</option>
              {estratos.map((s) => <option key={s} value={s}>{nombreEstrato(s)}</option>)}
            </select>
          </label>
        ) : null}
      </div>
      <LineasPorcentaje
        etiquetas={BANDAS.map(etiquetaBanda)}
        series={series}
        sinTope
        paso={5}
        formatoTick={(t) => `${t.toLocaleString("es-CO", { maximumFractionDigits: 0 })}`}
        formatoValor={fmtM3}
        tituloY="m³ por contrato"
      />
      <TablaPlegable titulo="Datos: promedio de consumo por antigüedad">
        <table className="dash-tabla num">
          <thead>
            <tr><th>{porEstrato ? "Estrato" : "Grupo"}</th>{BANDAS.map((b) => <th key={b}>{etiquetaBanda(b)}</th>)}</tr>
          </thead>
          <tbody>
            {grupos.map((g) => (
              <tr key={g.nombre}>
                <td>{g.nombre}</td>
                {g.prom.map((c, i) => (
                  <td key={BANDAS[i]} className="num">{c ? `${fmtDecimal(c.prom, 1)} (${fmtEntero(c.contratos)})` : "—"}</td>
                ))}
              </tr>
            ))}
            {otros.size > 0 ? (
              <tr>
                <td>{TEXTO.otros}</td>
                {BANDAS.map((b) => {
                  const o = otros.get(b);
                  return <td key={b} className="num">{o && o.contratos > 0 ? `${fmtDecimal(o.m3 / o.contratos, 1)} (${fmtEntero(o.contratos)})` : "—"}</td>;
                })}
              </tr>
            ) : null}
          </tbody>
        </table>
      </TablaPlegable>
      <div className="dash-nota">Cada celda: m³ por contrato (contratos). {TEXTO.nota} {TEXTO.nota15}</div>
    </div></div>
  );
}
