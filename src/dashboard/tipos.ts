// Filas de bi.v_kpi_mes tal como las sirve geoportal-bi.
// Las columnas nacidas del detalle por contrato (contratos_activos,
// contratos_con_cartera) son NULL fuera de la ventana de 6 períodos.
export type KpiMes = {
  periodo: string;
  facturado: number | null;
  recaudo_total: number | null;
  recaudo_0_30: number | null;
  recaudo_60_360: number | null;
  recaudo_may360: number | null;
  pct_recaudo_0_30: number | null;
  pct_recaudo_mes: number | null;
  cartera_total: number | null;
  notas_valor: number | null;
  contratos_activos: number | null;
  contratos_con_cartera: number | null;
};

// Filas de bi.v_kpi_anio: acumulado del año de cada período, enero→mes.
// Única fuente de verdad del "% recaudo del año" (el frontend no acumula).
export type KpiAnio = {
  periodo: string;
  anio: number | null;
  facturado_anio: number | null;
  recaudo_anio: number | null;
  pct_recaudo_anio: number | null;
};

const n = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) ? v : v != null && v !== "" && Number.isFinite(Number(v)) ? Number(v) : null;

export function comoKpiAnio(r: Record<string, unknown>): KpiAnio {
  return {
    periodo: String(r.periodo ?? ""),
    anio: n(r.anio),
    facturado_anio: n(r.facturado_anio),
    recaudo_anio: n(r.recaudo_anio),
    pct_recaudo_anio: n(r.pct_recaudo_anio),
  };
}

// Filas de bi.v_facturacion_mes: la cadena bruta -> déficit -> neta.
export type FacturacionMes = {
  periodo: string;
  anio: number | null;
  mes: number | null;
  bruta: number | null;
  subsidios: number | null;
  contribuciones: number | null;
  deficit: number | null;
  deficit_abs: number | null;
  pct_deficit_bruta: number | null;
  neta: number | null;
  m3_acueducto: number | null;
  m3_alcantarillado: number | null;
};

export function comoFacturacionMes(r: Record<string, unknown>): FacturacionMes {
  return {
    periodo: String(r.periodo ?? ""),
    anio: n(r.anio), mes: n(r.mes),
    bruta: n(r.bruta), subsidios: n(r.subsidios),
    contribuciones: n(r.contribuciones), deficit: n(r.deficit),
    deficit_abs: n(r.deficit_abs), pct_deficit_bruta: n(r.pct_deficit_bruta),
    neta: n(r.neta), m3_acueducto: n(r.m3_acueducto),
    m3_alcantarillado: n(r.m3_alcantarillado),
  };
}

export type FacturacionServicio = {
  periodo: string;
  servicio: string;
  facturado: number | null;
  pct_periodo: number | null;
};

export function comoFacturacionServicio(r: Record<string, unknown>): FacturacionServicio {
  return {
    periodo: String(r.periodo ?? ""),
    servicio: String(r.servicio ?? ""),
    facturado: n(r.facturado),
    pct_periodo: n(r.pct_periodo),
  };
}

export type FacturacionRuta = {
  periodo: string;
  ruta_efectiva: string;
  facturado: number | null;
  variacion: number | null;
  variacion_pct: number | null;
};

export function comoFacturacionRuta(r: Record<string, unknown>): FacturacionRuta {
  return {
    periodo: String(r.periodo ?? ""),
    ruta_efectiva: String(r.ruta_efectiva ?? ""),
    facturado: n(r.facturado),
    variacion: n(r.variacion),
    variacion_pct: n(r.variacion_pct),
  };
}

// bi.v_tarifa_referencia: la tarifa VIGENTE (solo el período ancla,
// 4 filas, sin variación: sin serie no hay contra qué comparar).
export type TarifaReferencia = {
  periodo: string;
  concepto_num: number | null;
  concepto: string;
  tarifa: number | null;
  valores_distintos: number | null;
  contratos_lectura_directa: number | null;
};

export function comoTarifaReferencia(r: Record<string, unknown>): TarifaReferencia {
  return {
    periodo: String(r.periodo ?? ""),
    concepto_num: n(r.concepto_num),
    concepto: String(r.concepto ?? ""),
    tarifa: n(r.tarifa),
    valores_distintos: n(r.valores_distintos),
    contratos_lectura_directa: n(r.contratos_lectura_directa),
  };
}

// bi.v_recaudo_mes: tramos de edad y su composición por período.
export type RecaudoMes = {
  periodo: string;
  anio: number | null;
  mes: number | null;
  recaudo_total: number | null;
  recaudo_0_30: number | null;
  recaudo_60_360: number | null;
  recaudo_may360: number | null;
  recuperacion_cartera: number | null;
  pct_0_30: number | null;
  pct_60_360: number | null;
  pct_may360: number | null;
  pct_recuperacion: number | null;
  variacion: number | null;
  variacion_pct: number | null;
};

export function comoRecaudoMes(r: Record<string, unknown>): RecaudoMes {
  return {
    periodo: String(r.periodo ?? ""),
    anio: n(r.anio), mes: n(r.mes),
    recaudo_total: n(r.recaudo_total),
    recaudo_0_30: n(r.recaudo_0_30),
    recaudo_60_360: n(r.recaudo_60_360),
    recaudo_may360: n(r.recaudo_may360),
    recuperacion_cartera: n(r.recuperacion_cartera),
    pct_0_30: n(r.pct_0_30),
    pct_60_360: n(r.pct_60_360),
    pct_may360: n(r.pct_may360),
    pct_recuperacion: n(r.pct_recuperacion),
    variacion: n(r.variacion),
    variacion_pct: n(r.variacion_pct),
  };
}

export type RecaudoServicio = {
  periodo: string;
  servicio: string;
  recaudo: number | null;
  pct_periodo: number | null;
};

export function comoRecaudoServicio(r: Record<string, unknown>): RecaudoServicio {
  return {
    periodo: String(r.periodo ?? ""),
    servicio: String(r.servicio ?? ""),
    recaudo: n(r.recaudo),
    pct_periodo: n(r.pct_periodo),
  };
}

// bi.v_fact_vs_recaudo_servicio: el cruce de las dos pantallas.
export type FactVsRecaudo = {
  periodo: string;
  servicio: string;
  facturado: number | null;
  recaudo: number | null;
  pct_recaudo: number | null;
  diferencia: number | null;
};

export function comoFactVsRecaudo(r: Record<string, unknown>): FactVsRecaudo {
  return {
    periodo: String(r.periodo ?? ""),
    servicio: String(r.servicio ?? ""),
    facturado: n(r.facturado),
    recaudo: n(r.recaudo),
    pct_recaudo: n(r.pct_recaudo),
    diferencia: n(r.diferencia),
  };
}

// bi.v_cartera_mes: total, descomposición financiada/no financiada y
// tramos de edad. OJO: las cubetas cubren solo la NO financiada.
export type CarteraMes = {
  periodo: string;
  anio: number | null;
  mes: number | null;
  cartera_total: number | null;
  no_financiada: number | null;
  financiada: number | null;
  t_hasta_60: number | null;
  t_60_180: number | null;
  t_180_360: number | null;
  t_may_360: number | null;
  pct_financiada: number | null;
  pct_may_360: number | null;
  pct_may_360_sobre_no_fin: number | null;
  variacion: number | null;
  variacion_pct: number | null;
};

export function comoCarteraMes(r: Record<string, unknown>): CarteraMes {
  return {
    periodo: String(r.periodo ?? ""),
    anio: n(r.anio), mes: n(r.mes),
    cartera_total: n(r.cartera_total),
    no_financiada: n(r.no_financiada),
    financiada: n(r.financiada),
    t_hasta_60: n(r.t_hasta_60),
    t_60_180: n(r.t_60_180),
    t_180_360: n(r.t_180_360),
    t_may_360: n(r.t_may_360),
    pct_financiada: n(r.pct_financiada),
    pct_may_360: n(r.pct_may_360),
    pct_may_360_sobre_no_fin: n(r.pct_may_360_sobre_no_fin),
    variacion: n(r.variacion),
    variacion_pct: n(r.variacion_pct),
  };
}

export type CarteraTramo = {
  periodo: string;
  orden: number | null;
  tramo: string;
  valor: number | null;
  pct_periodo: number | null;
};

export function comoCarteraTramo(r: Record<string, unknown>): CarteraTramo {
  return {
    periodo: String(r.periodo ?? ""),
    orden: n(r.orden),
    tramo: String(r.tramo ?? ""),
    valor: n(r.valor),
    pct_periodo: n(r.pct_periodo),
  };
}

export type CarteraServicio = {
  periodo: string;
  servicio: string;
  cartera: number | null;
  pct_periodo: number | null;
};

export function comoCarteraServicio(r: Record<string, unknown>): CarteraServicio {
  return {
    periodo: String(r.periodo ?? ""),
    servicio: String(r.servicio ?? ""),
    cartera: n(r.cartera),
    pct_periodo: n(r.pct_periodo),
  };
}

export type CarteraRuta = {
  periodo: string;
  ruta_efectiva: string;
  cartera: number | null;
  pct_periodo: number | null;
  variacion: number | null;
  variacion_pct: number | null;
};

export function comoCarteraRuta(r: Record<string, unknown>): CarteraRuta {
  return {
    periodo: String(r.periodo ?? ""),
    ruta_efectiva: String(r.ruta_efectiva ?? ""),
    cartera: n(r.cartera),
    pct_periodo: n(r.pct_periodo),
    variacion: n(r.variacion),
    variacion_pct: n(r.variacion_pct),
  };
}

// bi.v_fact_detalle_dim: preagregado del detalle por las dimensiones
// filtrables. Se trae UNA vez por período y se filtra en el navegador.
// OJO: consumo solo es m³ en los conceptos 2 y 4.
// bi.v_consumo_ciclo_dim: contratos por ciclo, medición y consumo cero
// (periodo x ciclo x categoria x subcategoria x con_medidor). El ciclo viene
// tal como está en consumo_metodo ('1'..'24'); categoria/subcategoria ya sin
// el código numérico ('Residencial', 'ESTRATO 1'). Los numeric pueden llegar
// como texto del RPC. facturado_acueducto es null donde no hay facturacion_sspd
// (202601 a 202605) y es SOLO acueducto. Dos medidas de consumo: "medido"
// (consumo_facturado: m3_facturados, contratos_consumo_*) y "cobrado" en la
// factura (consumo_cargos: m3_cargos, contratos_cargos_*); consumo_cargos nunca
// es nulo y coincide con el consumo de sspd.
export type ConsumoCicloDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  subcategoria: string;
  con_medidor: boolean;
  contratos: number | null;
  contratos_consumo_cero: number | null;
  contratos_consumo_nulo: number | null;
  m3_facturados: number | null;
  facturado_acueducto: number | null;
  contratos_en_sspd: number | null;
  m3_cargos: number | null;
  contratos_cargos_cero: number | null;
  contratos_cargos_nulo: number | null;
  contratos_cobrado_sin_medido: number | null;
};
export function comoConsumoCicloDim(r: Record<string, unknown>): ConsumoCicloDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    con_medidor: r.con_medidor === true || r.con_medidor === "true",
    contratos: n(r.contratos),
    contratos_consumo_cero: n(r.contratos_consumo_cero),
    contratos_consumo_nulo: n(r.contratos_consumo_nulo),
    m3_facturados: n(r.m3_facturados),
    facturado_acueducto: n(r.facturado_acueducto),
    contratos_en_sspd: n(r.contratos_en_sspd),
    m3_cargos: n(r.m3_cargos),
    contratos_cargos_cero: n(r.contratos_cargos_cero),
    contratos_cargos_nulo: n(r.contratos_cargos_nulo),
    contratos_cobrado_sin_medido: n(r.contratos_cobrado_sin_medido),
  };
}

// bi.v_desviacion_dim (sql/27): contratos por ciclo x categoria x subcategoria x
// tipo_desviacion x grupo_umbral. Solo existe para periodos con los 6 anteriores.
// tipo_desviacion: sin_desviacion | positiva | negativa | sin_historial | sin_promedio.
// grupo_umbral: ge40 (promedio >= 40 m3) | lt40 | sin_umbral.
export type DesviacionDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  subcategoria: string;
  tipo_desviacion: string;
  grupo_umbral: string;
  contratos: number;
  m3_periodo: number | null;
  m3_promedio: number | null;
  contratos_cero_6m: number;
};
export function comoDesviacionDim(r: Record<string, unknown>): DesviacionDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    tipo_desviacion: String(r.tipo_desviacion ?? ""),
    grupo_umbral: String(r.grupo_umbral ?? ""),
    contratos: n(r.contratos) ?? 0,
    m3_periodo: n(r.m3_periodo),
    m3_promedio: n(r.m3_promedio),
    contratos_cero_6m: n(r.contratos_cero_6m) ?? 0,
  };
}

// bi.v_lectura_ciclo_dim (sql/28): lectura efectiva y tiempos por ciclo.
// resultado_lectura: avance | igual | menor | sin_lectura.
// rango_dias: menos_min | en_rango | mas_max | sin_fecha (limites 28 y 32 dias).
export type LecturaCicloDim = {
  periodo: string;
  ciclo: string;
  con_medidor: boolean;
  resultado_lectura: string;
  rango_dias: string;
  contratos: number;
  contratos_con_dias: number;
  dias_suma: number | null;
  dias_min: number | null;
  dias_max: number | null;
  dia_modal: number | null;
};
export function comoLecturaCicloDim(r: Record<string, unknown>): LecturaCicloDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    con_medidor: r.con_medidor === true || r.con_medidor === "true",
    resultado_lectura: String(r.resultado_lectura ?? ""),
    rango_dias: String(r.rango_dias ?? ""),
    contratos: n(r.contratos) ?? 0,
    contratos_con_dias: n(r.contratos_con_dias) ?? 0,
    dias_suma: n(r.dias_suma),
    dias_min: n(r.dias_min),
    dias_max: n(r.dias_max),
    dia_modal: n(r.dia_modal),
  };
}

// bi.v_observacion_dim (sql/29): observacion de lectura por categoria, estrato y ciclo.
// observacion viene normalizada ('99 USUARIO CON LECTURA'; vacia = 'Sin medidor').
export type ObservacionDim = {
  periodo: string;
  categoria: string;
  subcategoria: string;
  ciclo: string;
  observacion: string;
  codigo_observacion: number | null;
  con_medidor: boolean;
  resultado_lectura: string;
  contratos: number;
  contratos_cero: number;
};
export function comoObservacionDim(r: Record<string, unknown>): ObservacionDim {
  return {
    periodo: String(r.periodo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    ciclo: String(r.ciclo ?? ""),
    observacion: String(r.observacion ?? ""),
    codigo_observacion: n(r.codigo_observacion),
    con_medidor: r.con_medidor === true || r.con_medidor === "true",
    resultado_lectura: String(r.resultado_lectura ?? ""),
    contratos: n(r.contratos) ?? 0,
    contratos_cero: n(r.contratos_cero) ?? 0,
  };
}

// bi.v_medidor_antig_dim (sql/30): antiguedad del medidor, sin ciclo.
// banda_antiguedad: 0-5 | 5-10 | 10-15 | >15 | Sin fecha | Sin medidor.
export type MedidorAntigDim = {
  periodo: string;
  categoria: string;
  subcategoria: string;
  banda_antiguedad: string;
  resultado_lectura: string;
  contratos: number;
  contratos_cero: number;
  m3_cargos: number | null;   // suma de consumo_cargos; nula en periodos anteriores a 202605
};
export function comoMedidorAntigDim(r: Record<string, unknown>): MedidorAntigDim {
  return {
    periodo: String(r.periodo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    banda_antiguedad: String(r.banda_antiguedad ?? ""),
    resultado_lectura: String(r.resultado_lectura ?? ""),
    contratos: n(r.contratos) ?? 0,
    contratos_cero: n(r.contratos_cero) ?? 0,
    m3_cargos: n(r.m3_cargos),
  };
}

// bi.v_consumo_rango_dim (sql/31): contratos, m3 y facturado por rango de consumo cobrado.
// rango_consumo: 0 | 1-5 | 6-10 | 11-15 | 16-20 | 21-30 | 31-40 | 41-60 | 61-100 | >100 | Sin dato.
export type ConsumoRangoDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  subcategoria: string;
  con_medidor: boolean;
  rango_consumo: string;
  contratos: number;
  m3_cargos: number | null;
  facturado_acueducto: number | null;
};
export function comoConsumoRangoDim(r: Record<string, unknown>): ConsumoRangoDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    con_medidor: r.con_medidor === true || r.con_medidor === "true",
    rango_consumo: String(r.rango_consumo ?? ""),
    contratos: n(r.contratos) ?? 0,
    m3_cargos: n(r.m3_cargos),
    facturado_acueducto: n(r.facturado_acueducto),
  };
}

// bi.v_consumo_basico_dim (sql/32): consumo basico (16 m3) en residencial estratos 1 a 3.
export type ConsumoBasicoDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  subcategoria: string;
  con_medidor: boolean;
  contratos: number;
  contratos_cero: number;
  contratos_hasta_basico: number;
  contratos_sobre_basico: number;
  contratos_sin_dato: number;
  m3_total: number | null;
  m3_basico: number | null;
  m3_exceso: number | null;
  facturado_acueducto: number | null;
};
export function comoConsumoBasicoDim(r: Record<string, unknown>): ConsumoBasicoDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    con_medidor: r.con_medidor === true || r.con_medidor === "true",
    contratos: n(r.contratos) ?? 0,
    contratos_cero: n(r.contratos_cero) ?? 0,
    contratos_hasta_basico: n(r.contratos_hasta_basico) ?? 0,
    contratos_sobre_basico: n(r.contratos_sobre_basico) ?? 0,
    contratos_sin_dato: n(r.contratos_sin_dato) ?? 0,
    m3_total: n(r.m3_total),
    m3_basico: n(r.m3_basico),
    m3_exceso: n(r.m3_exceso),
    facturado_acueducto: n(r.facturado_acueducto),
  };
}

export type FactDetalleDim = {
  periodo: string;
  ciclo: string;
  uso: string;
  subcategoria: string;
  concepto_num: number | null;
  contratos: number | null;
  facturado: number | null;
  consumo: number | null;
};

export function comoFactDetalleDim(r: Record<string, unknown>): FactDetalleDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    uso: String(r.uso ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    concepto_num: n(r.concepto_num),
    contratos: n(r.contratos),
    facturado: n(r.facturado),
    consumo: n(r.consumo),
  };
}

// bi.v_recaudo_diario: una fila por período y día, con el acumulado.
export type RecaudoDia = {
  periodo: string;
  fecha: string;
  dia: number | null;
  dia_semana: number | null;
  valor_dia: number | null;
  transacciones: number | null;
  contratos_pagaron: number | null;
  valor_acumulado: number | null;
};

export function comoRecaudoDia(r: Record<string, unknown>): RecaudoDia {
  return {
    periodo: String(r.periodo ?? ""),
    fecha: String(r.fecha ?? ""),
    dia: n(r.dia),
    dia_semana: n(r.dia_semana),
    valor_dia: n(r.valor_dia),
    transacciones: n(r.transacciones),
    contratos_pagaron: n(r.contratos_pagaron),
    valor_acumulado: n(r.valor_acumulado),
  };
}

// bi.v_recaudo_detalle_dim: preagregado día × concepto del período.
export type RecaudoDetalleDim = {
  periodo: string;
  fecha: string;
  concepto_num: number | null;
  valor: number | null;
  transacciones: number | null;
};

export function comoRecaudoDetalleDim(r: Record<string, unknown>): RecaudoDetalleDim {
  return {
    periodo: String(r.periodo ?? ""),
    fecha: String(r.fecha ?? ""),
    concepto_num: n(r.concepto_num),
    valor: n(r.valor),
    transacciones: n(r.transacciones),
  };
}

// bi.v_concepto_mapa: concepto → ruta contable → servicio (631 filas).
export type ConceptoMapa = {
  concepto_num: number | null;
  nombre: string;
  ruta_efectiva: string;
  servicio: string;
};

export function comoConceptoMapa(r: Record<string, unknown>): ConceptoMapa {
  return {
    concepto_num: n(r.concepto_num),
    nombre: String(r.nombre ?? ""),
    ruta_efectiva: String(r.ruta_efectiva ?? ""),
    servicio: String(r.servicio ?? ""),
  };
}

// bi.v_cartera_detalle_dim: preagregado de cartera NO financiada por
// barrio, comuna, ciclo, uso y subcategoría, con sus tramos de edad.
export type CarteraDetalleDim = {
  periodo: string;
  barrio: string;
  comuna: string;
  // 'comercial' = vino de Acuo · 'catastro' = inferida por barrio ·
  // 'sin dato'. La pantalla debe advertir cuánta cartera es inferida.
  comuna_origen: string;
  comuna_confiable: boolean;
  ciclo: string;
  uso: string;
  subcategoria: string;
  cartera: number | null;
  t_hasta_60: number | null;
  t_60_180: number | null;
  t_180_360: number | null;
  t_may_360: number | null;
};

export function comoCarteraDetalleDim(r: Record<string, unknown>): CarteraDetalleDim {
  return {
    periodo: String(r.periodo ?? ""),
    barrio: String(r.barrio ?? ""),
    comuna: String(r.comuna ?? ""),
    comuna_origen: String(r.comuna_origen ?? ""),
    comuna_confiable: r.comuna_confiable !== false,
    ciclo: String(r.ciclo ?? ""),
    uso: String(r.uso ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    cartera: n(r.cartera),
    t_hasta_60: n(r.t_hasta_60),
    t_60_180: n(r.t_60_180),
    t_180_360: n(r.t_180_360),
    t_may_360: n(r.t_may_360),
  };
}

// bi.v_cartera_contratos_dim: contratos con deuda por ciclo/comuna/uso/estrato.
export type CarteraContratosDim = {
  periodo: string;
  ciclo: string;
  comuna: string;
  uso: string;
  estrato: string;
  contratos: number | null;
  contratos_con_deuda: number | null;
  cartera_total: number | null;
  saldo_financiado: number | null;
  facturas_vencidas: number | null;
};

export function comoCarteraContratosDim(r: Record<string, unknown>): CarteraContratosDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    comuna: String(r.comuna ?? ""),
    uso: String(r.uso ?? ""),
    estrato: String(r.estrato ?? ""),
    contratos: n(r.contratos),
    contratos_con_deuda: n(r.contratos_con_deuda),
    cartera_total: n(r.cartera_total),
    saldo_financiado: n(r.saldo_financiado),
    facturas_vencidas: n(r.facturas_vencidas),
  };
}

// bi.v_cartera_edad_dim (sql/45): cartera por etiqueta cruda de edad x uso x estrato x servicio, en pesos. Sin ciclo, barrio ni contrato.
// uso: '1','3','5','9' u 'otros'; estrato: '1'..'6' u 'otros'; etiqueta: '0'..'1801' o 'sin_edad' (financiada); orden 0..17 y 99.
export type CarteraEdadDim = {
  periodo: string;
  uso: string;
  estrato: string;
  servicio: string;
  etiqueta: string;
  orden: number;
  valor: number;
};

export function comoCarteraEdadDim(r: Record<string, unknown>): CarteraEdadDim {
  return {
    periodo: String(r.periodo ?? ""),
    uso: String(r.uso ?? ""),
    estrato: String(r.estrato ?? ""),
    servicio: String(r.servicio ?? ""),
    etiqueta: String(r.etiqueta ?? ""),
    orden: n(r.orden) ?? 99,
    valor: n(r.valor) ?? 0,
  };
}

// bi.v_pqr_mes: serie mensual de reclamos y recursos. Un período sin
// archivo NO genera fila (para poder dibujar hueco, no cero).
export type PqrMes = {
  periodo: string;
  anio: number | null;
  mes: number | null;
  reclamos: number | null;
  reclamos_atendidos: number | null;
  reclamos_pendientes: number | null;
  reclamos_anulados: number | null;
  pct_atendidos: number | null;
  valor_reclamado: number | null;
  contratos_reclamantes: number | null;
  dias_atencion_prom: number | null;
  recursos: number | null;
  valor_recurrido: number | null;
  pct_recursos_sobre_reclamos: number | null;
};

export function comoPqrMes(r: Record<string, unknown>): PqrMes {
  return {
    periodo: String(r.periodo ?? ""),
    anio: n(r.anio), mes: n(r.mes),
    reclamos: n(r.reclamos),
    reclamos_atendidos: n(r.reclamos_atendidos),
    reclamos_pendientes: n(r.reclamos_pendientes),
    reclamos_anulados: n(r.reclamos_anulados),
    pct_atendidos: n(r.pct_atendidos),
    valor_reclamado: n(r.valor_reclamado),
    contratos_reclamantes: n(r.contratos_reclamantes),
    dias_atencion_prom: n(r.dias_atencion_prom),
    recursos: n(r.recursos),
    valor_recurrido: n(r.valor_recurrido),
    pct_recursos_sobre_reclamos: n(r.pct_recursos_sobre_reclamos),
  };
}

export type PqrDim = {
  periodo: string;
  tipo: string;
  causal: string;
  estado: string;
  area_causante: string;
  medio_recepcion: string;
  barrio: string;
  cantidad: number | null;
  valor: number | null;
};

export function comoPqrDim(r: Record<string, unknown>): PqrDim {
  return {
    periodo: String(r.periodo ?? ""),
    tipo: String(r.tipo ?? ""),
    causal: String(r.causal ?? ""),
    estado: String(r.estado ?? ""),
    area_causante: String(r.area_causante ?? ""),
    medio_recepcion: String(r.medio_recepcion ?? ""),
    barrio: String(r.barrio ?? ""),
    cantidad: n(r.cantidad),
    valor: n(r.valor),
  };
}

// bi.v_notas_mes: serie mensual de notas (ajustes a lo facturado).
// El valor YA viene con signo: crédito negativo, débito positivo.
export type NotasMes = {
  periodo: string; anio: number | null; mes: number | null;
  notas: number | null; notas_credito: number | null; notas_debito: number | null;
  valor_neto: number | null; valor_credito: number | null; valor_debito: number | null;
  valor_credito_abs: number | null; contratos_afectados: number | null;
};

export function comoNotasMes(r: Record<string, unknown>): NotasMes {
  return {
    periodo: String(r.periodo ?? ""), anio: n(r.anio), mes: n(r.mes),
    notas: n(r.notas), notas_credito: n(r.notas_credito), notas_debito: n(r.notas_debito),
    valor_neto: n(r.valor_neto), valor_credito: n(r.valor_credito),
    valor_debito: n(r.valor_debito), valor_credito_abs: n(r.valor_credito_abs),
    contratos_afectados: n(r.contratos_afectados),
  };
}

export type NotasDim = {
  periodo: string; causal: string; signo: string; servicio: string;
  cantidad: number | null; valor: number | null; contratos: number | null;
};

export function comoNotasDim(r: Record<string, unknown>): NotasDim {
  return {
    periodo: String(r.periodo ?? ""), causal: String(r.causal ?? ""),
    signo: String(r.signo ?? ""), servicio: String(r.servicio ?? ""),
    cantidad: n(r.cantidad), valor: n(r.valor), contratos: n(r.contratos),
  };
}

export type NotasVsPqr = {
  periodo: string; notas: number | null; valor_credito_abs: number | null;
  reclamos: number | null; valor_reclamado: number | null; notas_por_reclamo: number | null;
};

export function comoNotasVsPqr(r: Record<string, unknown>): NotasVsPqr {
  return {
    periodo: String(r.periodo ?? ""), notas: n(r.notas),
    valor_credito_abs: n(r.valor_credito_abs), reclamos: n(r.reclamos),
    valor_reclamado: n(r.valor_reclamado), notas_por_reclamo: n(r.notas_por_reclamo),
  };
}

// bi.v_cupones_mes / v_cupones_canal: por dónde entra la plata.
export type CuponesMes = {
  periodo: string; anio: number | null; mes: number | null;
  cupones: number | null; valor: number | null;
  ticket_promedio: number | null; ticket_mediano: number | null;
  entidades: number | null; rezago_dias: number | null;
  cupones_rezago_alto: number | null;
};

export function comoCuponesMes(r: Record<string, unknown>): CuponesMes {
  return {
    periodo: String(r.periodo ?? ""), anio: n(r.anio), mes: n(r.mes),
    cupones: n(r.cupones), valor: n(r.valor),
    ticket_promedio: n(r.ticket_promedio), ticket_mediano: n(r.ticket_mediano),
    entidades: n(r.entidades), rezago_dias: n(r.rezago_dias),
    cupones_rezago_alto: n(r.cupones_rezago_alto),
  };
}

export type CuponesCanal = {
  periodo: string; entidad: string; agencia: string;
  cupones: number | null; valor: number | null; ticket_promedio: number | null;
  rezago_dias: number | null; pct_periodo: number | null;
};

export function comoCuponesCanal(r: Record<string, unknown>): CuponesCanal {
  return {
    periodo: String(r.periodo ?? ""), entidad: String(r.entidad ?? ""),
    agencia: String(r.agencia ?? ""), cupones: n(r.cupones), valor: n(r.valor),
    ticket_promedio: n(r.ticket_promedio), rezago_dias: n(r.rezago_dias),
    pct_periodo: n(r.pct_periodo),
  };
}

// bi.v_consolidado_mes / v_consolidado_anio: la pantalla de análisis.
export type ConsolidadoMes = {
  periodo: string; anio: number | null; mes: number | null;
  facturado: number | null; m3_acueducto: number | null; m3_alcantarillado: number | null;
  recaudo_total: number | null; recaudo_corriente: number | null;
  recuperacion_cartera: number | null; cartera_total: number | null;
  cartera_financiada: number | null; cartera_may_360: number | null;
  notas_valor: number | null; cupones_procesados: number | null;
  cupones_valor: number | null; contratos_activos: number | null;
  pct_recaudo: number | null; rotacion_cartera: number | null;
  ticket_facturacion: number | null; ticket_pago: number | null;
  var_cartera_mes: number | null; var_cartera_mes_pct: number | null;
  facturado_ant: number | null; recaudo_total_ant: number | null;
  cartera_total_ant: number | null; pct_recaudo_ant: number | null;
  notas_valor_ant: number | null; m3_acueducto_ant: number | null;
  cupones_procesados_ant: number | null; ticket_facturacion_ant: number | null;
  ticket_pago_ant: number | null;
};

export function comoConsolidadoMes(r: Record<string, unknown>): ConsolidadoMes {
  const g = (k: string) => n(r[k]);
  return {
    periodo: String(r.periodo ?? ""), anio: g("anio"), mes: g("mes"),
    facturado: g("facturado"), m3_acueducto: g("m3_acueducto"),
    m3_alcantarillado: g("m3_alcantarillado"), recaudo_total: g("recaudo_total"),
    recaudo_corriente: g("recaudo_corriente"), recuperacion_cartera: g("recuperacion_cartera"),
    cartera_total: g("cartera_total"), cartera_financiada: g("cartera_financiada"),
    cartera_may_360: g("cartera_may_360"), notas_valor: g("notas_valor"),
    cupones_procesados: g("cupones_procesados"), cupones_valor: g("cupones_valor"),
    contratos_activos: g("contratos_activos"), pct_recaudo: g("pct_recaudo"),
    rotacion_cartera: g("rotacion_cartera"), ticket_facturacion: g("ticket_facturacion"),
    ticket_pago: g("ticket_pago"), var_cartera_mes: g("var_cartera_mes"),
    var_cartera_mes_pct: g("var_cartera_mes_pct"), facturado_ant: g("facturado_ant"),
    recaudo_total_ant: g("recaudo_total_ant"), cartera_total_ant: g("cartera_total_ant"),
    pct_recaudo_ant: g("pct_recaudo_ant"), notas_valor_ant: g("notas_valor_ant"),
    m3_acueducto_ant: g("m3_acueducto_ant"), cupones_procesados_ant: g("cupones_procesados_ant"),
    ticket_facturacion_ant: g("ticket_facturacion_ant"), ticket_pago_ant: g("ticket_pago_ant"),
  };
}

export type ConsolidadoAnio = {
  anio: number | null; meses_con_datos: number | null; ultimo_periodo: string;
  facturado: number | null; recaudo_total: number | null; pct_recaudo: number | null;
  recaudo_corriente: number | null; recuperacion_cartera: number | null;
  pct_corriente: number | null; pct_recuperacion: number | null;
  cartera_cierre: number | null; cartera_may_360_cierre: number | null;
  cartera_financiada_cierre: number | null; var_cartera_anual: number | null;
  var_cartera_anual_pct: number | null; rotacion_cartera: number | null;
  notas_valor: number | null; m3_acueducto: number | null; cupones_procesados: number | null;
};

export function comoConsolidadoAnio(r: Record<string, unknown>): ConsolidadoAnio {
  const g = (k: string) => n(r[k]);
  return {
    anio: g("anio"), meses_con_datos: g("meses_con_datos"),
    ultimo_periodo: String(r.ultimo_periodo ?? ""),
    facturado: g("facturado"), recaudo_total: g("recaudo_total"), pct_recaudo: g("pct_recaudo"),
    recaudo_corriente: g("recaudo_corriente"), recuperacion_cartera: g("recuperacion_cartera"),
    pct_corriente: g("pct_corriente"), pct_recuperacion: g("pct_recuperacion"),
    cartera_cierre: g("cartera_cierre"), cartera_may_360_cierre: g("cartera_may_360_cierre"),
    cartera_financiada_cierre: g("cartera_financiada_cierre"),
    var_cartera_anual: g("var_cartera_anual"), var_cartera_anual_pct: g("var_cartera_anual_pct"),
    rotacion_cartera: g("rotacion_cartera"), notas_valor: g("notas_valor"),
    m3_acueducto: g("m3_acueducto"), cupones_procesados: g("cupones_procesados"),
  };
}

export function comoKpiMes(r: Record<string, unknown>): KpiMes {
  return {
    periodo: String(r.periodo ?? ""),
    facturado: n(r.facturado),
    recaudo_total: n(r.recaudo_total),
    recaudo_0_30: n(r.recaudo_0_30),
    recaudo_60_360: n(r.recaudo_60_360),
    recaudo_may360: n(r.recaudo_may360),
    pct_recaudo_0_30: n(r.pct_recaudo_0_30),
    pct_recaudo_mes: n(r.pct_recaudo_mes),
    cartera_total: n(r.cartera_total),
    notas_valor: n(r.notas_valor),
    contratos_activos: n(r.contratos_activos),
    contratos_con_cartera: n(r.contratos_con_cartera),
  };
}

// ---------------------------------------------------------------------
// Recaudo diario (conciliaciones bancarias) y Pérdidas (IPUF).
// ---------------------------------------------------------------------

// bi.v_recaudo_diario: un lote de conciliación bancaria por fila.
// Es el mes EN CURSO: la tabla de hechos se reemplaza en cada cargue.
export type RecaudoLote = {
  conciliacion: string;
  entidad: string;
  dia: string;
  periodo_registro: string;
  valor_procesado: number | null;
  num_cupones: number | null;
  cupones_procesados: number | null;
  conciliacion_cerrada: string;
  cierre_automatico: string;
  funcionario: string;
};

export function comoRecaudoLote(r: Record<string, unknown>): RecaudoLote {
  return {
    conciliacion: String(r.conciliacion ?? ""),
    entidad: String(r.entidad_recaudo ?? r.entidad ?? ""),
    dia: String(r.dia ?? ""),
    periodo_registro: String(r.periodo_registro ?? ""),
    valor_procesado: n(r.valor_procesado),
    num_cupones: n(r.num_cupones),
    cupones_procesados: n(r.cupones_procesados),
    conciliacion_cerrada: String(r.conciliacion_cerrada ?? ""),
    cierre_automatico: String(r.cierre_automatico ?? ""),
    funcionario: String(r.funcionario ?? ""),
  };
}

// bi.v_recaudo_diario_mes: serie diaria comparable entre períodos.
// `origen` distingue el mes cerrado ('cierre', desde recaudo_detalle)
// del mes en curso ('curso', desde las conciliaciones). No son la
// misma medición y la pantalla lo dice.
export type RecaudoDiaMes = {
  periodo: string;
  dia: number | null;
  fecha: string;
  valor_dia: number | null;
  valor_acumulado: number | null;
  transacciones: number | null;
  origen: string;
};

export function comoRecaudoDiaMes(r: Record<string, unknown>): RecaudoDiaMes {
  return {
    periodo: String(r.periodo ?? ""),
    dia: n(r.dia),
    fecha: String(r.fecha ?? ""),
    valor_dia: n(r.valor_dia),
    valor_acumulado: n(r.valor_acumulado),
    transacciones: n(r.transacciones),
    origen: String(r.origen ?? ""),
  };
}

// bi.v_ipuf: serie histórica de pérdidas, 114 períodos desde 201701.
// El IPUF, el ICUF, el ISUF y las referencias del IPUF (meta, estándar,
// año tarifario) vienen en m³/suscriptor-mes (13.68), NO en porcentaje.
export type Ipuf = {
  periodo: string;
  ano: number | null;
  mes: number | null;
  fecha: string;
  ipuf: number | null;
  icuf: number | null;
  isuf: number | null;
  isuf_meta: number | null;
  ianc: number | null;
  meta_ipuf: number | null;
  ipuf_estandar: number | null;
  ipuf_anio_corrido: number | null;
  brecha_meta_real: number | null;
  brecha_estandar_real: number | null;
  agua_potable: number | null;
  agua_facturada: number | null;
  suscriptores: number | null;
  perdida_total_m3: number | null;
  perdida_total_pesos: number | null;
  perdida_sin_admisible_m3: number | null;
  perdida_sin_admisible_pesos: number | null;
  perdida_sobre_meta_m3: number | null;
  perdida_sobre_meta_pesos: number | null;
  tarifa_m3: number | null;
};

export function comoIpuf(r: Record<string, unknown>): Ipuf {
  return {
    periodo: String(r.periodo ?? ""),
    ano: n(r.ano),
    mes: n(r.mes),
    fecha: String(r.fecha ?? ""),
    ipuf: n(r.ipuf),
    icuf: n(r.icuf),
    isuf: n(r.isuf),
    isuf_meta: n(r.isuf_meta),
    ianc: n(r.ianc),
    meta_ipuf: n(r.meta_ipuf_emdupar),
    ipuf_estandar: n(r.ipuf_estandar),
    ipuf_anio_corrido: n(r.ipuf_anio_corrido),
    brecha_meta_real: n(r.brecha_meta_real),
    brecha_estandar_real: n(r.brecha_estandar_real),
    agua_potable: n(r.agua_potable),
    agua_facturada: n(r.agua_facturada),
    suscriptores: n(r.numero_de_suscriptores),
    perdida_total_m3: n(r.perdida_total),
    perdida_total_pesos: n(r.perdida_total_pesos),
    perdida_sin_admisible_m3: n(r.perdida_sin_admisible),
    perdida_sin_admisible_pesos: n(r.perdida_sin_admisible_pesos),
    perdida_sobre_meta_m3: n(r.perdidas_superiores_meta),
    perdida_sobre_meta_pesos: n(r.perdidas_superiores_meta_pesos),
    tarifa_m3: n(r.tarifa_m3),
  };
}

// ---------------------------------------------------------------------
// Recaudo desagregada (sql/33 a 37)
// ---------------------------------------------------------------------
export type RecaudoEficienciaDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  subcategoria: string;
  contratos_facturados: number;
  facturado: number | null;
  contratos_pagadores: number;
  recaudo_neto: number | null;
  contratos_pago_1: number;
  contratos_pago_2mas: number;
  recaudo_pago_2mas: number | null;
};
export function comoRecaudoEficienciaDim(r: Record<string, unknown>): RecaudoEficienciaDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    subcategoria: String(r.subcategoria ?? ""),
    contratos_facturados: n(r.contratos_facturados) ?? 0,
    facturado: n(r.facturado),
    contratos_pagadores: n(r.contratos_pagadores) ?? 0,
    recaudo_neto: n(r.recaudo_neto),
    contratos_pago_1: n(r.contratos_pago_1) ?? 0,
    contratos_pago_2mas: n(r.contratos_pago_2mas) ?? 0,
    recaudo_pago_2mas: n(r.recaudo_pago_2mas),
  };
}

export type RecaudoRitmoDim = {
  periodo: string;
  dia: number;
  recaudo_dia: number | null;
  recaudo_acumulado: number | null;
  pct_acumulado_del_recaudo: number | null;
  facturado_mes: number | null;
  pct_acumulado_del_facturado: number | null;
  ultimo_dia_con_datos: number | null;
  mes_completo: boolean;
};
export function comoRecaudoRitmoDim(r: Record<string, unknown>): RecaudoRitmoDim {
  return {
    periodo: String(r.periodo ?? ""),
    dia: n(r.dia) ?? 0,
    recaudo_dia: n(r.recaudo_dia),
    recaudo_acumulado: n(r.recaudo_acumulado),
    pct_acumulado_del_recaudo: n(r.pct_acumulado_del_recaudo),
    facturado_mes: n(r.facturado_mes),
    pct_acumulado_del_facturado: n(r.pct_acumulado_del_facturado),
    ultimo_dia_con_datos: n(r.ultimo_dia_con_datos),
    mes_completo: r.mes_completo === true || r.mes_completo === "true",
  };
}

export type RecaudoEdadDim = {
  periodo: string;
  tramo: string;
  orden: number;
  servicio: string;
  recaudo: number | null;
  conceptos: number;
};
export function comoRecaudoEdadDim(r: Record<string, unknown>): RecaudoEdadDim {
  return {
    periodo: String(r.periodo ?? ""),
    tramo: String(r.tramo ?? ""),
    orden: n(r.orden) ?? 0,
    servicio: String(r.servicio ?? ""),
    recaudo: n(r.recaudo),
    conceptos: n(r.conceptos) ?? 0,
  };
}

export type NotasCausalDim = {
  periodo: string;
  ciclo: string;
  categoria: string;
  causal: string;
  notas: number;
  notas_credito: number;
  notas_debito: number;
  valor: number | null;
  valor_credito: number | null;
  valor_debito: number | null;
};
export function comoNotasCausalDim(r: Record<string, unknown>): NotasCausalDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    categoria: String(r.categoria ?? ""),
    causal: String(r.causal ?? ""),
    notas: n(r.notas) ?? 0,
    notas_credito: n(r.notas_credito) ?? 0,
    notas_debito: n(r.notas_debito) ?? 0,
    valor: n(r.valor),
    valor_credito: n(r.valor_credito),
    valor_debito: n(r.valor_debito),
  };
}

export type RecaudoEntidadDim = {
  periodo: string;
  entidad: string;
  agencia: string;
  categoria: string;
  en_linea: boolean;
  cupones: number;
  valor: number | null;
  contratos: number;
};
export function comoRecaudoEntidadDim(r: Record<string, unknown>): RecaudoEntidadDim {
  return {
    periodo: String(r.periodo ?? ""),
    entidad: String(r.entidad ?? ""),
    agencia: String(r.agencia ?? ""),
    categoria: String(r.categoria ?? ""),
    en_linea: r.en_linea === true || r.en_linea === "true",
    cupones: n(r.cupones) ?? 0,
    valor: n(r.valor),
    contratos: n(r.contratos) ?? 0,
  };
}

// bi.v_cambio_medidor_dim (sql/38): cambios de medidor entre un periodo y el anterior disponible, por
// contrato. tipo_evento: reposicion | instalacion_nueva | retiro | sin_cambio (control).
// banda_ant: 0-5 | 5-10 | 10-15 | >15 (fecha real) | >15 (1986-01-01) | Sin fecha | Sin medidor.
// metodo_act: lectura | promedio | otro. m3_ant y m3_act suman solo los contratos pareados.
export type CambioMedidorDim = {
  periodo: string;
  periodo_ant: string;
  meses_intervalo: number;
  ciclo: string;
  uso: string;
  estrato: string;
  tipo_evento: string;
  banda_ant: string;
  metodo_act: string;
  contratos: number;
  contratos_pareados: number;   // en pantalla se rotula «Contratos comparables» (mismo dato; nombre interno sin cambio)
  m3_ant: number | null;
  m3_act: number | null;
  contratos_con_medidor_ant: number;
};
export function comoCambioMedidorDim(r: Record<string, unknown>): CambioMedidorDim {
  return {
    periodo: String(r.periodo ?? ""),
    periodo_ant: String(r.periodo_ant ?? ""),
    meses_intervalo: n(r.meses_intervalo) ?? 1,
    ciclo: String(r.ciclo ?? ""),
    uso: String(r.uso ?? ""),
    estrato: String(r.estrato ?? ""),
    tipo_evento: String(r.tipo_evento ?? ""),
    banda_ant: String(r.banda_ant ?? ""),
    metodo_act: String(r.metodo_act ?? ""),
    contratos: n(r.contratos) ?? 0,
    contratos_pareados: n(r.contratos_pareados) ?? 0,
    m3_ant: n(r.m3_ant),
    m3_act: n(r.m3_act),
    contratos_con_medidor_ant: n(r.contratos_con_medidor_ant) ?? 0,
  };
}

// bi.v_submedicion_ref_dim, v_submedicion_ciclo_dim y v_submedicion_rango_dim (sql/39): submedicion por vejez del medidor.
// Universo: residencial, medidor registrado, observacion 99, funcion CALCCODL, 0 < consumo_cargos <= 100, antiguedad al cierre.
// banda_antig: 0-3 | 3-5 | 5-10 | 10-15 | >15 (fecha real) | >15 (1986-01-01) | Sin fecha. rango_m3: 1-5 ... 61-100.
export type SubmedicionRefDim = {
  periodo: string;
  estrato: string;
  banda_antig: string;
  contratos_medidor: number;
  contratos: number;
  contratos_promedio: number;
  m3_consumo: number | null;
  ref_nuevos_media_m3: number | null;
  n_nuevos: number;
  media_vejez_m3: number | null;
  n_vejez: number;
  tarifa_m3: number | null;
  contratos_bajo_ref: number | null;
  m3_perdidos_bruta: number | null;
  m3_exceso: number | null;
  max_m3: number | null;
  calculado_en: string;
  contratos_cero: number;
  contratos_sobre_max: number;
};
export function comoSubmedicionRefDim(r: Record<string, unknown>): SubmedicionRefDim {
  return {
    periodo: String(r.periodo ?? ""),
    estrato: String(r.estrato ?? ""),
    banda_antig: String(r.banda_antig ?? ""),
    contratos_medidor: n(r.contratos_medidor) ?? 0,
    contratos: n(r.contratos) ?? 0,
    contratos_promedio: n(r.contratos_promedio) ?? 0,
    m3_consumo: n(r.m3_consumo),
    ref_nuevos_media_m3: n(r.ref_nuevos_media_m3),
    n_nuevos: n(r.n_nuevos) ?? 0,
    media_vejez_m3: n(r.media_vejez_m3),
    n_vejez: n(r.n_vejez) ?? 0,
    tarifa_m3: n(r.tarifa_m3),
    contratos_bajo_ref: n(r.contratos_bajo_ref),
    m3_perdidos_bruta: n(r.m3_perdidos_bruta),
    m3_exceso: n(r.m3_exceso),
    max_m3: n(r.max_m3),
    calculado_en: String(r.calculado_en ?? ""),
    contratos_cero: n(r.contratos_cero) ?? 0,
    contratos_sobre_max: n(r.contratos_sobre_max) ?? 0,
  };
}

export type SubmedicionCicloDim = {
  periodo: string;
  ciclo: string;
  estrato: string;
  contratos: number;
  m3_consumo: number | null;
  m3_perdidos_bruta: number | null;
  contratos_vejez: number;
  m3_perdidos_atrib: number | null;
  tarifa_m3: number | null;
  contratos_bajo_ref: number | null;
  m3_exceso: number | null;
  max_m3: number | null;
  calculado_en: string;
};
export function comoSubmedicionCicloDim(r: Record<string, unknown>): SubmedicionCicloDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    estrato: String(r.estrato ?? ""),
    contratos: n(r.contratos) ?? 0,
    m3_consumo: n(r.m3_consumo),
    m3_perdidos_bruta: n(r.m3_perdidos_bruta),
    contratos_vejez: n(r.contratos_vejez) ?? 0,
    m3_perdidos_atrib: n(r.m3_perdidos_atrib),
    tarifa_m3: n(r.tarifa_m3),
    contratos_bajo_ref: n(r.contratos_bajo_ref),
    m3_exceso: n(r.m3_exceso),
    max_m3: n(r.max_m3),
    calculado_en: String(r.calculado_en ?? ""),
  };
}

export type SubmedicionRangoDim = {
  periodo: string;
  ciclo: string;
  estrato: string;
  rango_m3: string;
  contratos: number;
  m3_consumo: number | null;
  contratos_bajo_ref: number | null;
  m3_perdidos_bruta: number | null;
  tarifa_m3: number | null;
  max_m3: number | null;
  calculado_en: string;
};
export function comoSubmedicionRangoDim(r: Record<string, unknown>): SubmedicionRangoDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    estrato: String(r.estrato ?? ""),
    rango_m3: String(r.rango_m3 ?? ""),
    contratos: n(r.contratos) ?? 0,
    m3_consumo: n(r.m3_consumo),
    contratos_bajo_ref: n(r.contratos_bajo_ref),
    m3_perdidos_bruta: n(r.m3_perdidos_bruta),
    tarifa_m3: n(r.tarifa_m3),
    max_m3: n(r.max_m3),
    calculado_en: String(r.calculado_en ?? ""),
  };
}

// Reclamos según el método de facturación (sql/41): A por banda de antigüedad, estrato y uso; B por ciclo.
// Solo agregados: contratos-mes y solicitudes distintas por contrato y período.
export type ReclamoMetodoBandaDim = {
  periodo: string;
  metodo_ant: string;
  metodo_act: string;
  banda_antig: string;
  estrato: string;
  uso: string;
  contratos: number;
  solicitudes_consumo: number;
  solicitudes_promedio: number;
  solicitudes_medidor: number;
  solicitudes_otras: number;
  solicitudes_desocupado: number;
  solicitudes_cartera: number;
  solicitudes_admin: number;
  contratos_con_reclamo: number;
  contratos_con_rec_consumo_prom: number;
  calculado_en: string;
};
export function comoReclamoMetodoBandaDim(r: Record<string, unknown>): ReclamoMetodoBandaDim {
  return {
    periodo: String(r.periodo ?? ""),
    metodo_ant: String(r.metodo_ant ?? ""),
    metodo_act: String(r.metodo_act ?? ""),
    banda_antig: String(r.banda_antig ?? ""),
    estrato: String(r.estrato ?? ""),
    uso: String(r.uso ?? ""),
    contratos: n(r.contratos) ?? 0,
    solicitudes_consumo: n(r.solicitudes_consumo) ?? 0,
    solicitudes_promedio: n(r.solicitudes_promedio) ?? 0,
    solicitudes_medidor: n(r.solicitudes_medidor) ?? 0,
    solicitudes_otras: n(r.solicitudes_otras) ?? 0,
    solicitudes_desocupado: n(r.solicitudes_desocupado) ?? 0,
    solicitudes_cartera: n(r.solicitudes_cartera) ?? 0,
    solicitudes_admin: n(r.solicitudes_admin) ?? 0,
    contratos_con_reclamo: n(r.contratos_con_reclamo) ?? 0,
    contratos_con_rec_consumo_prom: n(r.contratos_con_rec_consumo_prom) ?? 0,
    calculado_en: String(r.calculado_en ?? ""),
  };
}

export type ReclamoMetodoCicloDim = {
  periodo: string;
  ciclo: string;
  metodo_act: string;
  contratos: number;
  solicitudes_consumo: number;
  solicitudes_promedio: number;
  solicitudes_medidor: number;
  solicitudes_otras: number;
  solicitudes_desocupado: number;
  solicitudes_cartera: number;
  solicitudes_admin: number;
  contratos_con_reclamo: number;
  contratos_con_rec_consumo_prom: number;
  calculado_en: string;
};
export function comoReclamoMetodoCicloDim(r: Record<string, unknown>): ReclamoMetodoCicloDim {
  return {
    periodo: String(r.periodo ?? ""),
    ciclo: String(r.ciclo ?? ""),
    metodo_act: String(r.metodo_act ?? ""),
    contratos: n(r.contratos) ?? 0,
    solicitudes_consumo: n(r.solicitudes_consumo) ?? 0,
    solicitudes_promedio: n(r.solicitudes_promedio) ?? 0,
    solicitudes_medidor: n(r.solicitudes_medidor) ?? 0,
    solicitudes_otras: n(r.solicitudes_otras) ?? 0,
    solicitudes_desocupado: n(r.solicitudes_desocupado) ?? 0,
    solicitudes_cartera: n(r.solicitudes_cartera) ?? 0,
    solicitudes_admin: n(r.solicitudes_admin) ?? 0,
    contratos_con_reclamo: n(r.contratos_con_reclamo) ?? 0,
    contratos_con_rec_consumo_prom: n(r.contratos_con_rec_consumo_prom) ?? 0,
    calculado_en: String(r.calculado_en ?? ""),
  };
}

// Mapa de calor (sql/42): celdas de 250 m publicadas por período y capa, y su cobertura. Los NULL de las columnas de
// capa y de cartera son conteos suprimidos (1 a 4 contratos): NO son 0.
export type MapaCalorDim = {
  periodo: string;
  capa: string;
  celda_x: number;
  celda_y: number;
  lon_centro: number;
  lat_centro: number;
  contratos_base: number;
  contratos_capa: number | null;
  contratos_base_cartera: number | null;
  contratos_capa_cartera: number | null;
  calculado_en: string;
};
export function comoMapaCalorDim(r: Record<string, unknown>): MapaCalorDim {
  return {
    periodo: String(r.periodo ?? ""),
    capa: String(r.capa ?? ""),
    celda_x: n(r.celda_x) ?? 0,
    celda_y: n(r.celda_y) ?? 0,
    lon_centro: n(r.lon_centro) ?? 0,
    lat_centro: n(r.lat_centro) ?? 0,
    contratos_base: n(r.contratos_base) ?? 0,
    contratos_capa: n(r.contratos_capa),
    contratos_base_cartera: n(r.contratos_base_cartera),
    contratos_capa_cartera: n(r.contratos_capa_cartera),
    calculado_en: String(r.calculado_en ?? ""),
  };
}

export type MapaCalorCoberturaDim = {
  periodo: string;
  capa: string;
  contratos_universo: number;
  contratos_con_coordenadas: number;
  contratos_sin_coordenadas: number;
  contratos_en_celdas_publicadas: number;
  contratos_en_celdas_suprimidas: number;
  calculado_en: string;
};
export function comoMapaCalorCoberturaDim(r: Record<string, unknown>): MapaCalorCoberturaDim {
  return {
    periodo: String(r.periodo ?? ""),
    capa: String(r.capa ?? ""),
    contratos_universo: n(r.contratos_universo) ?? 0,
    contratos_con_coordenadas: n(r.contratos_con_coordenadas) ?? 0,
    contratos_sin_coordenadas: n(r.contratos_sin_coordenadas) ?? 0,
    contratos_en_celdas_publicadas: n(r.contratos_en_celdas_publicadas) ?? 0,
    contratos_en_celdas_suprimidas: n(r.contratos_en_celdas_suprimidas) ?? 0,
    calculado_en: String(r.calculado_en ?? ""),
  };
}

// Mapa de calor, cartera por grupo de mora (sql/42): 8 filas por período = 2 capas x 2 ámbitos ('capa' y 'universo') x 2 grupos
// ('mora_profunda': más de 8 facturas vencidas; 'hasta_8': 8 facturas vencidas o menos o sin registro). Calculada sobre TODOS los contratos; un grupo
// con 1 a 4 contratos llega con NULL en contratos y valores.
export type MapaCalorCarteraDim = {
  periodo: string;
  capa: string;
  ambito: string;
  grupo: string;
  contratos: number | null;
  valor_cartera: number | null;
  valor_financiado: number | null;
  calculado_en: string;
};
export function comoMapaCalorCarteraDim(r: Record<string, unknown>): MapaCalorCarteraDim {
  return {
    periodo: String(r.periodo ?? ""),
    capa: String(r.capa ?? ""),
    ambito: String(r.ambito ?? ""),
    grupo: String(r.grupo ?? ""),
    contratos: n(r.contratos),
    valor_cartera: n(r.valor_cartera),
    valor_financiado: n(r.valor_financiado),
    calculado_en: String(r.calculado_en ?? ""),
  };
}
