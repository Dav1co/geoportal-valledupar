import { useEffect, useState } from "react";
import { api } from "../lib/api";

type Props = { id: number | null; onCerrar: () => void };

const BASURA = new Set([
  "NULO", "#REF!", "NO APLICA", "NINGUNA", "DESCONOCIDO", "DESCONOCIDA",
  "0", "", "000000000",
]);

function limpio(v: unknown): string {
  if (v === null || v === undefined) return "—";
  const s = String(v).trim();
  if (s === "" || BASURA.has(s.toUpperCase())) return "—";
  return s;
}

// Formatea un número como pesos colombianos.
function pesos(v: unknown): string {
  if (v === null || v === undefined || v === "") return "—";
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  return "$" + n.toLocaleString("es-CO");
}

function fechaCorta(v: unknown): string {
  if (!v) return "—";
  try {
    const d = new Date(String(v));
    if (isNaN(d.getTime())) return "—";
    return d.toLocaleDateString("es-CO", { day: "2-digit", month: "2-digit", year: "numeric" });
  } catch { return "—"; }
}

// Secciones del catastro
const SECCIONES: { titulo: string; campos: [string, string][] }[] = [
  {
    titulo: "Ubicación e identificación",
    campos: [
      ["DIRECCION", "Dirección"], ["BARRIO", "Barrio"], ["OTRO_BARRIO", "Otro barrio"],
      ["COMUNA", "Comuna"], ["SECTOR", "Sector"], ["MANZANA", "Manzana"],
      ["PREDIO", "Predio"], ["ZONA", "Zona"], ["DEPARTAMENTO", "Departamento"],
      ["MUNICIPIO", "Municipio"], ["CODIGO_CATASTRAL", "Código catastral"],
      ["COD_IGAC", "Código IGAC"], ["COD_PREDIO", "Código predio"],
      ["COD_USUARIO", "Contrato"], ["MATRICULA_INMOBILIARIA", "Matrícula inmobiliaria"],
      ["NOM_EDIFICIO", "Edificio"], ["UBICM", "Ubicación"],
    ],
  },
  {
    titulo: "Características del predio",
    campos: [
      ["TIPO_PREDIO", "Tipo de predio"], ["ESTA_PREDIO", "Estado"],
      ["ESTRATO", "Estrato"], ["CLASE_USO", "Uso"], ["ACT_ECO", "Actividad económica"],
      ["UNIH", "Unidad habitacional"], ["UNINH", "Unidad no habitacional"],
      ["NRO_HABITANTES", "N.º habitantes"],
    ],
  },
  {
    titulo: "Propietario / suscriptor",
    campos: [
      ["NOMBRE", "Nombre"], ["APEL1", "Apellido"],
      ["NOMBRE_PROPIE", "Nombre propietario"], ["APELLIDO_PROPIE", "Apellido propietario"],
      ["TIPO_IDENTICACION_PROPIE", "Tipo de identificación"],
      ["IDENTICACION_PROPIE", "Identificación"],
      ["EMAIL", "Correo"], ["EMAIL_PROPIE", "Correo propietario"],
      ["TELEFONO", "Teléfono"], ["TELEFONO_PROPIE", "Teléfono propietario"],
    ],
  },
  {
    titulo: "Servicio de agua y alcantarillado",
    campos: [
      ["TIP_SERV", "Proveedor"], ["TIPCONEX", "Tipo de conexión"],
      ["POSEE_SERV", "Posee servicio"], ["SERV_ALC", "Alcantarillado"],
      ["DESTP_SERVALC", "Proveedor alcantarillado"], ["FACTURA", "Recibe factura"],
      ["REGISTRA", "Registra"], ["DES_VERTTIM", "Vertimiento"],
      ["DES_PTOHIDRA", "Punto hidráulico"],
    ],
  },
  {
    titulo: "Medición",
    campos: [
      ["NRO_MED", "N.º medidor"], ["DESC_MARCA", "Marca"],
      ["ELEMENTO_MEDICION", "Elemento de medición"], ["DIAM_MED", "Diámetro medidor"],
      ["DIAM_ACOM", "Diámetro acometida"], ["PESEE_MED", "Posee medidor"],
      ["ESTPTO_MED", "Estado punto medidor"], ["EST_CAJA", "Estado caja"],
      ["LECTURA", "Lectura"], ["AN_MED", "Anomalía medidor"],
      ["OBSERVACION_LECT", "Observación lectura"], ["CODANOMMED", "Código anomalía"],
      ["POSEE_LLAVE_PAS", "Posee llave de paso"], ["POSEE_REG_CORT", "Posee registro de corte"],
    ],
  },
  {
    titulo: "Energía (cruce)",
    campos: [
      ["POSEE_SERV_ENER", "Posee energía"], ["MED_ENERG", "Medidor energía"],
      ["NIC_ENER", "NIC energía"],
    ],
  },
  {
    titulo: "Sectorización hidráulica",
    campos: [
      ["SECTOR_HIDRA", "Sector hidráulico"], ["SUBSECTOR_HIDRA", "Subsector"],
      ["UNIDAD_HIDRA", "Unidad hidráulica"],
    ],
  },
  {
    titulo: "Anomalías y estado",
    campos: [
      ["AN_NOSUS", "Anomalía no suscriptor"], ["ANOM_GENERAL", "Anomalía general"],
      ["DESPOS_FRAUDE", "Posible fraude"], ["MANTENIMIENTO", "Mantenimiento"],
      ["RE_PR", "Relación predio"], ["HAYATENCION", "Hubo atención"],
    ],
  },
  {
    titulo: "Levantamiento / auditoría",
    campos: [
      ["FECHA_CTA", "Fecha de cuenta"], ["DIGITADOR", "Digitador"],
      ["HORA_INI", "Hora inicio"], ["HORA_FIN", "Hora fin"],
      ["METODO TEXTO", "Método (texto)"], ["METODO COMPLETO", "Método (completo)"],
    ],
  },
];

type Cargue = Record<string, unknown> | null;

export function PredioPanel({ id, onCerrar }: Props) {
  const [predio, setPredio] = useState<Record<string, unknown> | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [abiertas, setAbiertas] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (id === null) { setPredio(null); return; }
    setCargando(true);
    setError(null);
    api
      .detalle(id)
      .then(({ predio }) => setPredio(predio))
      .catch((e) => setError(e instanceof Error ? e.message : "Error."))
      .finally(() => setCargando(false));
  }, [id]);

  if (id === null) return null;

  const cargue = (predio?._cargue ?? null) as Cargue;

  function toggle(titulo: string) {
    setAbiertas((prev) => {
      const n = new Set(prev);
      if (n.has(titulo)) n.delete(titulo); else n.add(titulo);
      return n;
    });
  }

  return (
    <div className="panel">
      <div className="panel-head">
        <span className="panel-title">Ficha del predio</span>
        <button className="btn-link" onClick={onCerrar}>Cerrar</button>
      </div>
      {cargando && <p className="hint">Consultando…</p>}
      {error && <p className="error">{error}</p>}

      {predio && (
        <div className="ficha">
          {/* Encabezado: contrato predominante + cargue diario completo */}
          {cargue ? (
            <div className="ficha-cargue">
              <div className="ficha-contrato">
                <span className="ficha-contrato-et">Contrato</span>
                <span className="ficha-contrato-num">{limpio(cargue.contrato)}</span>
                {cargue.estado != null && String(cargue.estado).trim() !== "" && (
                  <span className="ficha-estado">{String(cargue.estado)}</span>
                )}
              </div>
              <dl className="ficha-datos">
                <Fila et="Nombre" v={limpio(cargue.nombre)} />
                <Fila et="Identificación" v={limpio(cargue.identificacion)} />
                <Fila et="Correo" v={limpio(cargue.correo)} />
                <Fila et="Teléfono" v={limpio(cargue.telefono)} />
                <Fila et="Dirección" v={limpio(cargue.direccion)} />
                <Fila et="Barrio" v={limpio(cargue.barrio)} />
                <Fila et="Categoría" v={limpio(cargue.categoria)} />
                <Fila et="Subcategoría" v={limpio(cargue.subcategoria)} />
                <Fila et="Ciclo" v={limpio(cargue.ciclo)} />
                <Fila et="Ruta" v={limpio(cargue.ruta)} />
                <Fila et="Código reparto" v={limpio(cargue.codigo_reparto)} />
                <Fila et="Elemento medición" v={limpio(cargue.serial_medidor)} />
                <Fila et="Facturas pendientes" v={limpio(cargue.facturas_pendientes)} destacar={Number(cargue.facturas_pendientes) > 0} />
                <Fila et="Deuda total" v={pesos(cargue.deuda_total)} destacar={Number(cargue.deuda_total) > 0} />
                <Fila et="Saldo pendiente" v={pesos(cargue.saldo_pendiente)} />
                <Fila et="Saldo a favor" v={pesos(cargue.saldo_a_favor)} />
                <Fila et="Valor reclamo" v={pesos(cargue.valor_reclamo)} />
                <Fila et="Saldo financiado" v={pesos(cargue.saldo_financiado)} />
              </dl>
              <p className="ficha-cargue-pie">
                Cargue del {fechaCorta(cargue.cargado_en)}
              </p>
            </div>
          ) : (
            <div className="ficha-sincargue">
              <div className="ficha-contrato">
                <span className="ficha-contrato-et">Contrato</span>
                <span className="ficha-contrato-num">{limpio(predio.COD_USUARIO)}</span>
              </div>
              <p className="ficha-vacio">
                Este predio no cruza con el cargue comercial (posible predio sin contrato).
              </p>
            </div>
          )}

          {/* Secciones del catastro (colapsables) */}
          {SECCIONES.map((sec) => (
            <div className="ficha-seccion" key={sec.titulo}>
              <button className="ficha-tit" onClick={() => toggle(sec.titulo)}>
                <span>{abiertas.has(sec.titulo) ? "▾" : "▸"} {sec.titulo}</span>
              </button>
              {abiertas.has(sec.titulo) && (
                <dl className="ficha-datos">
                  {sec.campos.map(([clave, et]) => (
                    <Fila key={clave} et={et} v={limpio(predio[clave])} />
                  ))}
                </dl>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function Fila({ et, v, destacar }: { et: string; v: string; destacar?: boolean }) {
  return (
    <div className="ficha-fila">
      <dt>{et}</dt>
      <dd className={v === "—" ? "vacio" : destacar ? "destacar" : "mono"}>{v}</dd>
    </div>
  );
}
