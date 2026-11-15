// Respuesta de GET geoportal-campo?accion=analisis_contrato&contrato=… (contrato_respuesta.md del paquete del análisis de contrato).
// DATO PERSONAL: `suscriptor` (nombre y teléfonos) solo se muestra en pantalla. Nunca se guarda (ni en localStorage/sessionStorage), ni se escribe en la consola, ni sale en descargas.

export type Cupo = { limite: number | null; usadas: number; restantes: number | null; sin_limite: boolean; cobrada: boolean };

export type Suscriptor = {
  nombre: string | null;
  /** Máximo 3; primero los celulares de 10 dígitos; [] si no hay. */
  telefonos: string[];
  telefono_fuente: "cartera" | "censo" | null;
  /** AAAAMMDD de la cartera diaria, o null. */
  corte: string | null;
};

export type TramoMora = "al_dia" | "leve" | "media" | "alta" | "cronica";

export type Comercial = {
  estado: string | null; categoria: string | null; subcategoria: string | null; ciclo: string | null; ruta: string | null;
  barrio: string | null; direccion: string | null;
  deuda_total: number | null; saldo_pendiente: number | null; facturas_pendientes: number | null; saldo_financiado: number | null; valor_reclamo: number | null; saldo_a_favor: number | null;
  tramo_mora: TramoMora | null;
  estado_predio: string | null;
  facturas_vencidas: number | null;
  corte: string | null;
};

export type CambioMedidor = { periodo: string; serial_anterior: string | null; serial_nuevo: string | null };
export type Medidor = {
  serial: string | null; diametro: string | null; fecha_instalacion: string | null;
  fecha_estado: "real" | "por_defecto" | "sin_dato" | null;
  anios: number | null;
  cambio: { confirmado: CambioMedidor | null; recodificado: CambioMedidor | null } | null;
};

export type MesConsumo = { periodo: string; sin_dato: boolean; m3: number | null; metodo: string | null; lectura_real: boolean; causal: string | null };
export type Consumo = {
  periodo_ultimo: string;
  /** Siempre 6 meses calendario seguidos, del más antiguo al más reciente. */
  meses: MesConsumo[];
  maximo: number | null; minimo: number | null; promedio: number | null;
  meses_con_lectura: number;
};

export type MesPromedio = { periodo: string; media: number | null; contratos: number | null };
export type Promedio = { grupo: string; meses: MesPromedio[] };
export type Promedios = { estrato: Promedio | null; barrio: Promedio | null; uso: Promedio | null };

export type Submedicion = {
  marca: boolean; periodo: string; consumo: number | null; referencia: number | null; n_nuevos: number | null; estrato: string | null; anios: number | null;
  motivo: string | null;
};

export type Pago = { fecha: string; valor: number | null; fuente: "cupones" | "cartera"; dias: number | null };

export type EmdFacturado = { codigo: string; concepto: string; periodo: string };
export type GestionTerreno = { tipo: string; tipo_nombre: string; consecutivo: string | null; fecha: string; estado: string | null };
export type Pqr = {
  ultima: { solicitud: string; fecha: string; causal: string | null; estado: string | null; abierta: boolean } | null;
  abiertas: number; ultimos_12_meses: number; total: number;
};
export type ReporteGeoportal = { consecutivo: string | null; tipo: string; tipo_nombre: string; fecha: string; estado: string | null; resultado: string | null };
export type ActaGeoportal = { consecutivo: string; fecha: string | null; registrado_en: string | null };
export type PendienteRevision = { consecutivo: string | null; tipo_nombre: string; fecha: string; sugiere: string };
export type Gestiones = {
  emd_facturados: EmdFacturado[] | null;
  terreno: GestionTerreno[];
  pqr: Pqr | null;
  reportes: ReporteGeoportal[];
  reportes_total: number;
  actas: ActaGeoportal[];
  pendientes: PendienteRevision[];
};

export type Predio = { direccion: string | null; barrio: string | null; lat: number | null; lon: number | null };
export type Ubicacion = { predios_total: number; predios: Predio[] };

export type Cortes = { cartera: string | null; consumo: string | null; ficha: string | null };

/** Contrato encontrado (no comodín). Con `ficha_disponible=false`: consumo, medidor (salvo el serial diario), submedición, pago, pqr y emd vienen null. */
export type AnalisisCompleto = {
  encontrado: true; comodin: false; contrato: string; cupo: Cupo;
  suscriptor: Suscriptor | null;
  comercial: Comercial | null;
  medidor: Medidor | null;
  consumo: Consumo | null;
  promedios: Promedios | null;
  submedicion: Submedicion | null;
  pago: Pago | null;
  gestiones: Gestiones | null;
  ubicacion: Ubicacion | null;
  fotos: unknown[];
  cortes: Cortes | null;
  ficha_disponible: boolean;
};
export type AnalisisNoEncontrado = { encontrado: false; contrato: string; cupo: Cupo };
export type AnalisisComodin = { encontrado: true; comodin: true; contrato: string; cupo: Cupo };
export type RespuestaAnalisis = AnalisisCompleto | AnalisisNoEncontrado | AnalisisComodin;
