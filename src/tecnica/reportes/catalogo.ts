// Reportes del Dashboard PTAP (pestaña «Reportes») y descargas del Dashboard distribución (pestaña «Descargas"): una tarjeta por formulario o ítem
// (encargo del 19-nov-2026, paquete_fase1/reportes_ptap_distribucion/ENCARGO.md). Aquí va SOLO lo que la pantalla necesita para dibujar cada tarjeta:
// nombre, descripción, qué filtros aplican y qué dice el «Léame». Las COLUMNAS las manda el servidor al iniciar cada descarga (así un cambio de columnas
// no toca la pantalla). Ningún reporte lleva teléfonos, nombres del suscriptor, nombre o placa de terceros ni texto libre con datos de personas.

export type FiltroReporte = "planta" | "sector" | "tipo_activo";
export type TipoColumna = "texto" | "numero" | "entero" | "fecha" | "hora" | "fecha_hora" | "si_no" | "enlace";
export type ColumnaReporte = { clave: string; titulo: string; tipo: TipoColumna; unidad?: string | null; ancho?: number; texto_enlace?: string };

export type DefReporte = {
  clave: string;                       // el «reporte» que se le pide al servidor
  titulo: string;                      // nombre de la tarjeta y de la hoja de Excel (máximo 31 caracteres)
  descripcion: string;                 // una línea bajo el nombre
  funcion: "geoportal-tecnica" | "geoportal-redes";
  periodo: boolean;                    // false: foto de hoy (sin «desde–hasta»)
  periodoPor?: string;                 // qué fecha usa el periodo (va al «Léame»)
  filtros: FiltroReporte[];
  ocultos: string | null;              // rótulo de la casilla («Incluir los excluidos» / «Incluir los ocultos»); null si no aplica
  trae: string;                        // «Léame»: qué trae
  noTrae: string;                      // «Léame»: qué no trae
  archivo: string;                     // base del nombre del archivo (sin datos personales)
  notas?: [string, string][];          // filas propias del «Léame»
  ruta?: "gestion";                    // las dos descargas que ya existían (Corte 4b): su ruta propia, sin paginar
};

const SIN_PERSONALES = "Teléfonos, nombres del suscriptor, nombre o placa de terceros y textos libres con datos de personas.";

// ---------- PTAP · pestaña «Reportes» ----------
export const REPORTES_PTAP: DefReporte[] = [
  { clave: "entrada", titulo: "Entrada", descripcion: "Agua cruda: un envío por fila, cada variable en su columna.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de la muestra", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un envío del formulario Entrada por fila: planta, fecha y hora de la muestra, quién registró y cada variable en su columna, con la unidad en el encabezado.",
    noTrae: SIN_PERSONALES, archivo: "ptap_entrada" },
  { clave: "salida", titulo: "Salida", descripcion: "Agua tratada: un envío por fila, cada variable en su columna.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de la muestra", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un envío del formulario Salida por fila: planta, fecha y hora de la muestra, quién registró y cada variable en su columna, con la unidad en el encabezado.",
    noTrae: SIN_PERSONALES, archivo: "ptap_salida" },
  { clave: "muestreo", titulo: "Muestreo", descripcion: "Muestras en la red: un envío por fila, con el punto y la zona.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de la muestra", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un envío de muestreo por fila: punto, zona, fecha y hora de la muestra, quién registró y cada variable en su columna, con la unidad en el encabezado.",
    noTrae: SIN_PERSONALES, archivo: "ptap_muestreo" },
  { clave: "uso_quimicos", titulo: "Uso de químicos", descripcion: "Cada uso: planta, químico, cantidad y dosis.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha del uso", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un uso de químico por fila: planta, químico, cantidad usada, dosis, fecha y hora, y quién registró.",
    noTrae: SIN_PERSONALES, archivo: "ptap_uso_quimicos" },
  { clave: "entrada_quimicos", titulo: "Entrada de químicos", descripcion: "Remisiones recibidas en bodega, con el enlace a la foto.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de la remisión", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Una remisión por fila: bodega, químico, cantidad, lote y vencimiento, y el enlace para abrir la foto de la remisión en el geoportal (la foto no va dentro del archivo).",
    noTrae: `${SIN_PERSONALES} La foto en sí (solo el enlace, que pide iniciar sesión).`, archivo: "ptap_entrada_quimicos" },
  { clave: "kardex_quimicos", titulo: "Kardex de químicos", descripcion: "Por químico y bodega, cada movimiento con su saldo.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha del movimiento", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Por químico y bodega, cada movimiento en orden (inventario inicial, entradas, usos y ajustes por conteo) con el saldo corrido, y una fila de saldo al cierre del periodo.",
    noTrae: SIN_PERSONALES, archivo: "ptap_kardex_quimicos" },
  { clave: "eventos_planta", titulo: "Eventos de planta", descripcion: "Suspensiones y reanudaciones, con su duración.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de inicio del evento", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un evento por fila: planta, tipo (suspensión o reanudación), causa, inicio, fin y duración.",
    noTrae: SIN_PERSONALES, archivo: "ptap_eventos_planta" },
  { clave: "fuera_referencia", titulo: "Fuera de referencia", descripcion: "Valores fuera de la referencia, con la revisión del supervisor.", funcion: "geoportal-tecnica",
    periodo: true, periodoPor: "la fecha de la muestra", filtros: ["planta"], ocultos: "Incluir los excluidos",
    trae: "Un valor fuera de referencia por fila: variable, valor, referencia mínima y máxima, origen de la referencia, y la revisión del supervisor (estado, quién y cuándo).",
    noTrae: `${SIN_PERSONALES} La nota de la revisión (texto libre).`, archivo: "ptap_fuera_referencia" },
];

// ---------- Distribución · pestaña «Descargas» ----------
export const REPORTES_DISTRIBUCION: DefReporte[] = [
  { clave: "danos", titulo: "Daños y fallas", descripcion: "Un daño o falla por fila, con sus tiempos.", funcion: "geoportal-redes", ruta: "gestion",
    periodo: true, periodoPor: "la fecha de detección", filtros: [], ocultos: "Incluir los ocultos",
    trae: "Un daño o falla por fila: activo, tipo, tiempos de respuesta y reparación, causa, tipo de tercero, sector y ubicación.",
    noTrae: "El nombre o la placa del tercero (dato personal), las descripciones y los compañeros (texto libre). Se ven en la pantalla.", archivo: "danos_fallas",
    notas: [["Tipo de activo", "Va el nombre visible y el prefijo: el prefijo no cambia aunque cambie el nombre visible."]], },
  { clave: "intervenciones", titulo: "Intervenciones", descripcion: "Una intervención por fila, con recursos y valor.", funcion: "geoportal-redes", ruta: "gestion",
    periodo: true, periodoPor: "la fecha de fin", filtros: [], ocultos: "Incluir los ocultos",
    trae: "Una intervención por fila: activo, tipo, inicio, fin, ejecutor, contratista, recursos, aportantes y valor total.",
    noTrae: "El nombre o la placa del tercero (dato personal), las descripciones y los compañeros (texto libre). Se ven en la pantalla.", archivo: "intervenciones",
    notas: [["Tipo de activo", "Va el nombre visible y el prefijo: el prefijo no cambia aunque cambie el nombre visible."]], },
  { clave: "levantamientos", titulo: "Encontrar o reportar activo", descripcion: "Levantamientos LEV: qué se encontró, dónde y cómo quedó.", funcion: "geoportal-redes",
    periodo: true, periodoPor: "la fecha del levantamiento", filtros: ["sector"], ocultos: "Incluir los ocultos",
    trae: "Un levantamiento LEV por fila: tipo de activo, estado, sector, ubicación, quién lo levantó y cómo quedó (cargado, conservado o descartado con su motivo).",
    noTrae: SIN_PERSONALES, archivo: "levantamientos_lev" },
  { clave: "valvulas_cerradas", titulo: "Válvulas cerradas", descripcion: "Maniobras de cierre y apertura, con la duración.", funcion: "geoportal-redes",
    periodo: true, periodoPor: "la fecha del cierre", filtros: ["sector"], ocultos: "Incluir los ocultos",
    trae: "Una maniobra por fila: válvula, sector, cierre, apertura, duración y quién la hizo.",
    noTrae: SIN_PERSONALES, archivo: "valvulas_cerradas" },
  { clave: "eventos_suspension", titulo: "Eventos de suspensión", descripcion: "Zona, duración, regreso estimado y real, y afectados.", funcion: "geoportal-redes",
    periodo: true, periodoPor: "la fecha de inicio del evento", filtros: ["sector"], ocultos: "Incluir los ocultos",
    trae: "Un evento por fila: tipo, causa, zona, inicio, regreso estimado y real, duración, contratos y usuarios sensibles afectados (como números) y reportes asociados.",
    noTrae: `${SIN_PERSONALES} La lista de contratos (solo el número de afectados).`, archivo: "eventos_suspension" },
  { clave: "linea_116", titulo: "Línea 116", descripcion: "Reportes recibidos por la Línea 116.", funcion: "geoportal-redes",
    periodo: true, periodoPor: "la fecha del reporte", filtros: ["sector"], ocultos: "Incluir los ocultos",
    trae: "Un reporte de la Línea 116 por fila: tipo, contrato, sector, fecha y hora, estado y el evento al que quedó asociado.",
    noTrae: SIN_PERSONALES, archivo: "linea_116" },
  { clave: "reportes_bot", titulo: "Reportes del bot", descripcion: "Reportes que llegaron por el bot y qué se hizo con cada uno.", funcion: "geoportal-redes",
    periodo: true, periodoPor: "la fecha del reporte", filtros: ["sector"], ocultos: "Incluir los ocultos",
    trae: "Un reporte del bot por fila: tipo, contrato, sector, fecha y hora, estado (recibido, convertido o descartado) y el registro en que se convirtió.",
    noTrae: SIN_PERSONALES, archivo: "reportes_bot" },
  { clave: "usuarios_sensibles", titulo: "Usuarios sensibles", descripcion: "La lista de hoy, sin teléfonos ni nombres.", funcion: "geoportal-redes",
    periodo: false, filtros: ["sector"], ocultos: "Incluir los dados de baja",
    trae: "Un usuario sensible por fila: contrato, tipo (hospital, colegio, diálisis…), sector, desde cuándo y quién lo marcó.",
    noTrae: `${SIN_PERSONALES} Ningún teléfono.`, archivo: "usuarios_sensibles" },
  { clave: "activos_red", titulo: "Activos de la red", descripcion: "El inventario de hoy, por tipo de activo y sector.", funcion: "geoportal-redes",
    periodo: false, filtros: ["tipo_activo", "sector"], ocultos: "Incluir los ocultos y retirados",
    trae: "Un activo por fila: código, tipo, sistema, estado, material, diámetro, sector y ubicación.",
    noTrae: SIN_PERSONALES, archivo: "activos_red" },
];
