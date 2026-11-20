// Reportes del Dashboard PTAP (pestaña «Reportes») y descargas del Dashboard distribución (pestaña «Descargas»): una tarjeta por formulario o ítem
// (encargo del 19-nov-2026, paquete_fase1/reportes_ptap_distribucion/ENCARGO.md; contrato del Code A en ENTRADA_BITACORA.md de esa carpeta, 20-nov).
// Aquí va SOLO lo que la pantalla necesita para dibujar cada tarjeta: nombre, descripción, qué filtros aplican y el rótulo de «Incluir…». Las COLUMNAS y el
// «Léame» los manda el servidor al iniciar cada descarga (un cambio de columnas no toca la pantalla). Ningún reporte trae teléfonos, nombres del suscriptor,
// nombre o placa de terceros ni texto libre: lo garantiza el servidor (§1.5 del contrato).

export type Opcion = { codigo: string; nombre: string };
/** De dónde salen las opciones de un filtro: listas del dashboard, una lista fija o un número escrito (el sector hidráulico). */
export type FuenteFiltro = "plantas" | "puntos" | "zonas" | "quimicos" | "tipos_activo" | "fija" | "numero";
export type FiltroReporte = { clave: string; rotulo: string; todos: string; fuente: FuenteFiltro; opciones?: Opcion[] };
export type TipoColumna = "texto" | "entero" | "decimal" | "numero" | "fecha" | "hora" | "fecha_hora" | "si_no" | "enlace";
export type ColumnaReporte = { clave: string; titulo: string; tipo: TipoColumna; unidad?: string | null; decimales?: number; ancho?: number };

export type DefReporte = {
  clave: string;                       // el «reporte» que se le pide al servidor
  titulo: string;                      // nombre de la tarjeta y de la hoja de Excel (máximo 31 caracteres)
  descripcion: string;                 // una línea bajo el nombre
  funcion: "geoportal-tecnica" | "geoportal-redes";
  periodo: boolean;                    // false: inventario a hoy (sin «desde–hasta»)
  periodoPor?: string;                 // qué fecha usa el periodo (ayuda de la tarjeta)
  filtros: FiltroReporte[];
  ocultos: string | null;              // rótulo de la casilla «Incluir…»; null si no aplica (no se manda)
  trae: string;                        // «Léame» de respaldo, si el servidor no manda el suyo
  noTrae: string;
  archivo: string;                     // base del nombre del archivo, si el servidor no manda el suyo
  notas?: [string, string][];          // filas propias del «Léame»
  ruta?: "gestion";                    // las dos descargas que ya existían (Corte 4b): su ruta «descarga», sin paginar
};

const SIN_PERSONALES = "Teléfonos, nombres del suscriptor, nombre o placa de terceros y textos libres (descripciones, observaciones, motivos, notas, causas).";
// ---------- filtros ----------
const PLANTA: FiltroReporte = { clave: "planta", rotulo: "Planta", todos: "Todas las plantas", fuente: "plantas" };
const PUNTO: FiltroReporte = { clave: "punto", rotulo: "Punto", todos: "Todos los puntos", fuente: "puntos" };
const ZONA: FiltroReporte = { clave: "zona", rotulo: "Zona", todos: "Todas las zonas", fuente: "zonas" };
const QUIMICO: FiltroReporte = { clave: "quimico", rotulo: "Químico", todos: "Todos los químicos", fuente: "quimicos" };
const FORMULARIO: FiltroReporte = { clave: "formulario", rotulo: "Formulario", todos: "Todos los formularios", fuente: "fija",
  opciones: [{ codigo: "entrada", nombre: "Entrada" }, { codigo: "salida", nombre: "Salida" }, { codigo: "muestreo", nombre: "Muestreo" }] };
const SECTOR: FiltroReporte = { clave: "sector", rotulo: "Sector", todos: "Todos", fuente: "numero" };
const TIPO_SENSIBLE: FiltroReporte = { clave: "tipo", rotulo: "Tipo", todos: "Todos los tipos", fuente: "fija",
  opciones: [{ codigo: "hospital", nombre: "Hospital" }, { codigo: "clinica", nombre: "Clínica o centro de salud" }, { codigo: "colegio", nombre: "Colegio" },
    { codigo: "sede_propia", nombre: "Sede propia" }, { codigo: "otro", nombre: "Otro" }] };
const TIPO_ACTIVO: FiltroReporte = { clave: "tipo", rotulo: "Tipo de activo", todos: "Todos los tipos", fuente: "tipos_activo" };
const SISTEMA: FiltroReporte = { clave: "sistema", rotulo: "Sistema", todos: "Todos los sistemas", fuente: "fija",
  opciones: [{ codigo: "acueducto", nombre: "Acueducto" }, { codigo: "alcantarillado", nombre: "Alcantarillado" }, { codigo: "tecnologia", nombre: "Tecnología" }] };

// ---------- PTAP · pestaña «Reportes» (§2 del contrato) ----------
const T = "geoportal-tecnica" as const;
export const REPORTES_PTAP: DefReporte[] = [
  { clave: "entrada", titulo: "Entrada", descripcion: "Agua cruda: un envío por fila, cada variable en su columna.", funcion: T,
    periodo: true, periodoPor: "la fecha de la muestra", filtros: [PLANTA], ocultos: "Incluir los excluidos",
    trae: "Un envío del formulario Entrada por fila: muestra, planta, cada variable en su columna, coagulante y dosis, estado y quién registró.", noTrae: SIN_PERSONALES, archivo: "ptap_entrada" },
  { clave: "salida", titulo: "Salida", descripcion: "Agua tratada: un envío por fila, cada variable en su columna.", funcion: T,
    periodo: true, periodoPor: "la fecha de la muestra", filtros: [PLANTA], ocultos: "Incluir los excluidos",
    trae: "Un envío del formulario Salida por fila: muestra, planta, cada variable en su columna, estado y quién registró.", noTrae: SIN_PERSONALES, archivo: "ptap_salida" },
  { clave: "muestreo", titulo: "Muestreo", descripcion: "Muestras en la red: una por fila, con el punto y la zona.", funcion: T,
    periodo: true, periodoPor: "la fecha de la muestra", filtros: [PUNTO, ZONA], ocultos: "Incluir los excluidos",
    trae: "Una muestra de un punto por fila: punto, zona, número de informe, cada variable en su columna, estado y quién registró.", noTrae: SIN_PERSONALES, archivo: "ptap_muestreo" },
  { clave: "uso_quimicos", titulo: "Uso de químicos", descripcion: "Cada uso: planta, químico, cantidad y dosis óptima.", funcion: T,
    periodo: true, periodoPor: "el día del uso", filtros: [PLANTA, QUIMICO], ocultos: null,
    trae: "Un uso registrado por fila: día, químico, planta, para qué, cantidad (como se digitó y en kg) y la dosis óptima vigente.", noTrae: SIN_PERSONALES, archivo: "ptap_uso_quimicos" },
  { clave: "entrada_quimicos", titulo: "Entrada de químicos", descripcion: "Entradas a bodega, con el enlace a la foto de la remisión.", funcion: T,
    periodo: true, periodoPor: "el día de la entrada", filtros: [QUIMICO], ocultos: null,
    trae: "Una entrada a bodega por fila: químico, cantidad, proveedor, remisión, lote, vencimiento y el enlace para ver la foto de la remisión (la foto no va en el archivo).",
    noTrae: `${SIN_PERSONALES} La foto en sí: el enlace la abre en el geoportal, con sesión iniciada.`, archivo: "ptap_entrada_quimicos" },
  { clave: "kardex_quimicos", titulo: "Kardex de químicos", descripcion: "Por químico y bodega, cada movimiento con su saldo.", funcion: T,
    periodo: true, periodoPor: "el día del movimiento", filtros: [QUIMICO], ocultos: null,
    trae: "Por químico: el saldo inicial, cada movimiento en orden (inventario inicial, entradas, usos y ajustes por conteo) con el saldo corrido, y el saldo al cierre.",
    noTrae: SIN_PERSONALES, archivo: "ptap_kardex_quimicos" },
  { clave: "eventos_planta", titulo: "Eventos de planta", descripcion: "Suspensiones de cada planta y su reanudación.", funcion: T,
    periodo: true, periodoPor: "los eventos que tocan el periodo", filtros: [PLANTA], ocultos: "Incluir los anulados",
    trae: "Un evento de suspensión de una planta por fila: desde, regreso estimado (inicial y vigente), reanudación, duración, contratos y sensibles afectados, y reportes asociados.",
    noTrae: SIN_PERSONALES, archivo: "ptap_eventos_planta" },
  { clave: "fuera_referencia", titulo: "Fuera de referencia", descripcion: "Valores fuera de la referencia, con la revisión del supervisor.", funcion: T,
    periodo: true, periodoPor: "la fecha de la muestra", filtros: [PLANTA, FORMULARIO, PUNTO], ocultos: "Incluir los excluidos",
    trae: "Un valor fuera de referencia por fila: variable, valor, referencia mínima y máxima con su origen, y la revisión del supervisor (estado, quién y cuándo).",
    noTrae: `${SIN_PERSONALES} La nota de la revisión.`, archivo: "ptap_fuera_referencia" },
];

// ---------- Distribución · pestaña «Descargas» (§3 del contrato) ----------
const R = "geoportal-redes" as const;
const NOTA_TIPO: [string, string][] = [["Tipo de activo", "Va el nombre visible y el prefijo: el prefijo no cambia aunque cambie el nombre visible."]];
export const REPORTES_DISTRIBUCION: DefReporte[] = [
  { clave: "danos", titulo: "Daños y fallas", descripcion: "Un daño o falla por fila, con sus tiempos.", funcion: R, ruta: "gestion",
    periodo: true, periodoPor: "la fecha de detección", filtros: [], ocultos: "Incluir los ocultos",
    trae: "Un daño o falla por fila: activo, tipo, tiempos de respuesta y reparación, causa, tipo de tercero, sector y ubicación.",
    noTrae: "El nombre o la placa del tercero (dato personal), las descripciones y los compañeros (texto libre). Se ven en la pantalla.", archivo: "danos_fallas", notas: NOTA_TIPO },
  { clave: "intervenciones", titulo: "Intervenciones", descripcion: "Una intervención por fila, con recursos y valor.", funcion: R, ruta: "gestion",
    periodo: true, periodoPor: "la fecha de fin", filtros: [], ocultos: "Incluir los ocultos",
    trae: "Una intervención por fila: activo, tipo, inicio, fin, ejecutor, contratista, recursos, aportantes y valor total.",
    noTrae: "El nombre o la placa del tercero (dato personal), las descripciones y los compañeros (texto libre). Se ven en la pantalla.", archivo: "intervenciones", notas: NOTA_TIPO },
  { clave: "levantamientos", titulo: "Encontrar o reportar activo", descripcion: "Puntos LEV: qué se reportó, dónde y cómo quedó.", funcion: R,
    periodo: true, periodoPor: "el día del reporte", filtros: [SECTOR], ocultos: "Incluir los descartados",
    trae: "Un punto LEV por fila: lo que se reportó, área, estado, el activo creado si se levantó, fotos, precisión, sector y ubicación.", noTrae: SIN_PERSONALES, archivo: "levantamientos_lev" },
  { clave: "valvulas", titulo: "Válvulas cerradas", descripcion: "Cada cierre de una válvula, con su apertura y duración.", funcion: R,
    periodo: true, periodoPor: "el día del cierre", filtros: [SECTOR], ocultos: null,
    trae: "Un cierre de válvula por fila: cerrada, regreso estimado, abierta, duración, estado, daño e intervención, sector y quién cerró y abrió.", noTrae: SIN_PERSONALES, archivo: "valvulas_cerradas" },
  { clave: "eventos", titulo: "Eventos de suspensión", descripcion: "Zona, duración, regreso estimado y real, y afectados.", funcion: R,
    periodo: true, periodoPor: "los eventos que tocan el periodo", filtros: [SECTOR], ocultos: "Incluir los anulados",
    trae: "Un evento por fila: alcance, zona, desde, regreso estimado (inicial y vigente), fin, duración, contratos y sensibles afectados (como números) y reportes asociados por canal.",
    noTrae: `${SIN_PERSONALES} La lista de contratos: solo cuántos.`, archivo: "eventos_suspension" },
  { clave: "l116", titulo: "Línea 116", descripcion: "Reportes recibidos por la Línea 116.", funcion: R,
    periodo: true, periodoPor: "el día del reporte", filtros: [SECTOR], ocultos: "Incluir los ocultos",
    trae: "Un reporte de la 116 por fila: número, fecha, servicio, causal, comuna, contrato, estado, ubicación, sector y subsector.", noTrae: SIN_PERSONALES, archivo: "linea_116" },
  { clave: "bot", titulo: "Reportes del bot", descripcion: "Reportes que llegaron por el bot y en qué quedaron.", funcion: R,
    periodo: true, periodoPor: "el día de recibido", filtros: [SECTOR], ocultos: "Incluir los descartados",
    trae: "Un reporte del bot por fila: radicado, recibido, canal, tipo, estado, el daño en que se convirtió, fotos, sector y ubicación.",
    noTrae: `${SIN_PERSONALES} La descripción y la dirección que escribió el ciudadano.`, archivo: "reportes_bot" },
  { clave: "sensibles", titulo: "Usuarios sensibles", descripcion: "La lista de hoy, sin teléfonos ni nombres.", funcion: R,
    periodo: false, filtros: [TIPO_SENSIBLE], ocultos: "Incluir los descartados",
    trae: "Un contrato sensible por fila: contrato, tipo, estado, desde cuándo, origen y sector.", noTrae: `${SIN_PERSONALES} Ningún teléfono ni nombre.`, archivo: "usuarios_sensibles" },
  { clave: "activos", titulo: "Activos de la red", descripcion: "El inventario de hoy, por tipo y sistema.", funcion: R,
    periodo: false, filtros: [TIPO_ACTIVO, SISTEMA], ocultos: "Incluir los retirados y ocultos",
    trae: "Un activo por fila: código, tipo y prefijo, sistema, clase, material, diámetro, longitud, profundidad, instalación, estado, sector y un punto de ubicación.",
    noTrae: SIN_PERSONALES, archivo: "activos_red" },
];
