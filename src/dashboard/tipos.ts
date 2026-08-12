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
// Los porcentajes vienen en puntos (13.68 = 13,68 %), no en fracción.
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
