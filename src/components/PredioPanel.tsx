import { useEffect, useState } from "react";
import { api } from "../lib/api";

type Props = { id: number | null; onCerrar: () => void };

// Valores que se consideran "basura" y se muestran como "—".
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

// Secciones del catastro: [clave en props, etiqueta]
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

// Traducciones de los códigos de Acuo
const T_MEDIDOR: Record<string, string> = {
  "1": "Con medidor registrado", "2": "Dañado", "3": "Sin medidor",
};
const T_DETERM: Record<string, string> = {
  "1": "Leído", "2": "Por promedio", "3": "Suspendido", "4": "Cortado", "5": "Pago anticipado",
};
const T_CONSUMO: Record<string, string> = {
  cero: "Cero (0 m³)", muy_bajo: "Muy bajo (1–6 m³)", normal: "Normal (7–17 m³)",
  alto: "Alto (18–32 m³)", muy_alto: "Muy alto (33–59 m³)",
  elevado: "Elevado (60–500 m³)", grandes: "Grandes (más de 500 m³)",
};
const T_MORA: Record<string, string> = {
  al_dia: "Al día", leve: "Leve (1–2)", media: "Media (3–8)",
  alta: "Alta (9–60)", cronica: "Crónica (más de 60)",
};

type Acuo = {
  estado_medidor?: string | null;
  determinacion_consumo?: string | null;
  consumo_actual?: number | null;
  consumo_anterior?: number | null;
  clase_consumo?: string | null;
  salto_consumo?: string | null;
  tramo_mora?: string | null;
  facturas_pendientes?: number | null;
  tiene_deuda?: boolean | null;
  ruta_lectura?: string | null;
  ciclo?: string | null;
  cruza_acuo?: boolean | null;
};

export function PredioPanel({ id, onCerrar }: Props) {
  const [predio, setPredio] = useState<Record<string, unknown> | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [abiertas, setAbiertas] = useState<Set<string>>(new Set(["Ubicación e identificación"]));

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

  const acuo = (predio?._acuo ?? {}) as Acuo;

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
          {/* Sección comercial (Acuo) primero, destacada */}
          <div className="ficha-seccion">
            <button className="ficha-tit" onClick={() => toggle("Comercial")}>
              <span>{abiertas.has("Comercial") ? "▾" : "▸"} Datos comerciales (Acuo)</span>
            </button>
            {abiertas.has("Comercial") && (
              acuo.cruza_acuo === false || acuo.cruza_acuo == null ? (
                <p className="ficha-vacio">Este predio no cruza con datos comerciales de Acuo.</p>
              ) : (
                <dl className="ficha-datos">
                  <Fila et="Estado del medidor" v={T_MEDIDOR[String(acuo.estado_medidor)] ?? "—"} />
                  <Fila et="Determinación consumo" v={T_DETERM[String(acuo.determinacion_consumo)] ?? "—"} />
                  <Fila et="Consumo del mes" v={acuo.consumo_actual != null ? `${acuo.consumo_actual} m³` : "—"} />
                  <Fila et="Consumo mes anterior" v={acuo.consumo_anterior != null ? `${acuo.consumo_anterior} m³` : "—"} />
                  <Fila et="Rango de consumo" v={T_CONSUMO[String(acuo.clase_consumo)] ?? "—"} />
                  <Fila et="Tramo de mora" v={T_MORA[String(acuo.tramo_mora)] ?? "—"} />
                  <Fila et="Facturas pendientes" v={acuo.facturas_pendientes != null ? String(acuo.facturas_pendientes) : "—"} />
                  <Fila et="Ruta de lectura" v={limpio(acuo.ruta_lectura)} />
                  <Fila et="Ciclo" v={limpio(acuo.ciclo)} />
                </dl>
              )
            )}
          </div>

          {/* Secciones del catastro */}
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

function Fila({ et, v }: { et: string; v: string }) {
  return (
    <div className="ficha-fila">
      <dt>{et}</dt>
      <dd className={v === "—" ? "vacio" : "mono"}>{v}</dd>
    </div>
  );
}
