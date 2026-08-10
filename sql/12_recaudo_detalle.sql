-- =====================================================================
-- 12_recaudo_detalle.sql · Capa 2: pantalla de Recaudo detallado
--                           + el recaudo DIARIO que faltaba
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06. Sin datos personales (el detalle trae número de
-- contrato; aquí solo salen conteos y montos agregados por día y
-- concepto — ningún contrato identificable llega a bi).
-- Fuente: hechos.recaudo_detalle — 6,6 M filas, retención de 6 períodos.
--
-- LO QUE ESTA FUENTE APORTA Y NINGUNA OTRA TIENE: la FECHA del pago.
-- Con ella se construye el recaudo diario y su acumulado, que es lo que
-- pedía el placeholder "Requiere bi.v_recaudo_diario" del Resumen y el
-- patrón intra-mes de pagos (indicador C8 aprobado).
--
-- ⚠ DIMENSIONES: esta tabla NO trae ciclo, uso ni estrato — solo
-- contrato, concepto, valor y fechas. Por eso el panel de filtros de
-- esta pantalla ofrece servicio/concepto y no las dimensiones
-- territoriales. Cruzar contra facturacion_contratos para obtener
-- ciclo/uso exigiría un join de 6,6 M × 7,2 M filas: queda propuesto
-- como fase posterior, medido antes de prometerlo.
--
-- ⚠ El campo `concepto` de esta tabla trae el NÚMERO puro ("1", "2"),
-- no el formato "1- CARGO FIJO" de las demás. Se castea con bi.f_num,
-- y el cruce de ruta sigue siendo por número — nunca por nombre.
--
-- ⚠ HUECO DE DATOS CONOCIDO: falta el período 202606. El archivo
-- INFORME_RECAUDOS_DETALLADO_202606 no fue entregado (carga_log:
-- estado 'faltante', "No se encontro archivo con el patron"); los otros
-- ocho informes de recaudo de ese mes sí llegaron. No es un fallo del
-- cargue ni de estas vistas: junio 2026 simplemente no tiene detalle
-- diario, y la pantalla debe decirlo en vez de mostrar un mes vacío.
--
-- La fecha que manda es fecha_grabacion (aplicación efectiva del pago),
-- igual que en el diseño de hechos.recaudo_diario para el archivo
-- diario bancario.
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_recaudo_diario_cierre · una fila por período y día: valor, número de
-- transacciones, contratos distintos que pagaron y el ACUMULADO del mes
-- hasta ese día. Base de la curva diaria del Resumen y de la
-- comparación entre meses al mismo día.
-- contratos_pagaron necesita su propio count(distinct): un contrato
-- paga varios conceptos el mismo día, así que NO es sumable desde el
-- preagregado por concepto.
-- ---------------------------------------------------------------------
drop materialized view if exists bi.v_recaudo_diario_cierre;
create materialized view bi.v_recaudo_diario_cierre as
with base as (
  select
    periodo,
    bi.f_fecha(fecha_grabacion) as fecha,
    bi.f_num(valor_recaudo)     as valor,
    contrato
  from hechos.recaudo_detalle
  where bi.f_fecha(fecha_grabacion) is not null
),
dia as (
  select
    periodo,
    fecha,
    sum(valor)               as valor_dia,
    count(*)                 as transacciones,
    count(distinct contrato) as contratos_pagaron
  from base
  group by periodo, fecha
)
select
  periodo,
  fecha,
  extract(day  from fecha)::int as dia,
  extract(isodow from fecha)::int as dia_semana,   -- 1 lunes … 7 domingo
  valor_dia,
  transacciones,
  contratos_pagaron,
  sum(valor_dia) over (partition by periodo order by fecha
                       rows between unbounded preceding and current row) as valor_acumulado
from dia
with data;

create unique index if not exists v_recaudo_diario_cierre_ux
  on bi.v_recaudo_diario_cierre (periodo, fecha);

revoke all on bi.v_recaudo_diario_cierre from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_recaudo_detalle_dim · preagregado de la pantalla 6: período ×
-- día × concepto. ~2.400 filas por período (31 días × 150 conceptos con
-- movimiento), así que la pantalla lo trae completo y filtra en el
-- navegador, igual que Facturación detallado.
-- Sin count(distinct): dentro de un día y un concepto, cada fila es una
-- transacción; los contratos distintos viven en v_recaudo_diario_cierre.
-- ---------------------------------------------------------------------
drop materialized view if exists bi.v_recaudo_detalle_dim;
create materialized view bi.v_recaudo_detalle_dim as
select
  periodo,
  bi.f_fecha(fecha_grabacion)   as fecha,
  bi.f_num(concepto)::int       as concepto_num,
  sum(bi.f_num(valor_recaudo))  as valor,
  count(*)                      as transacciones
from hechos.recaudo_detalle
where bi.f_fecha(fecha_grabacion) is not null
  and bi.f_num(concepto) is not null
group by periodo, bi.f_fecha(fecha_grabacion), bi.f_num(concepto)::int
with data;

create unique index if not exists v_recaudo_detalle_dim_ux
  on bi.v_recaudo_detalle_dim (periodo, fecha, concepto_num);

create index if not exists v_recaudo_detalle_dim_periodo_ix
  on bi.v_recaudo_detalle_dim (periodo);

revoke all on bi.v_recaudo_detalle_dim from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 1) Períodos disponibles y su tamaño (202606 debe estar AUSENTE, ver
--    el hueco de datos documentado arriba):
--      select periodo, count(*) dias, min(fecha), max(fecha)
--      from bi.v_recaudo_diario_cierre group by 1 order by 1;
-- 2) Tamaño del preagregado por período (apto para una sola llamada):
--      select periodo, count(*) from bi.v_recaudo_detalle_dim group by 1 order by 1;
-- 3) COHERENCIA INTERNA — las dos vistas suman lo mismo por período:
--      select d.periodo, d.total, x.total, round(d.total - x.total, 2) dif
--      from (select periodo, sum(valor_dia) total from bi.v_recaudo_diario_cierre group by 1) d
--      join (select periodo, sum(valor) total from bi.v_recaudo_detalle_dim group by 1) x
--        using (periodo)
--      where abs(d.total - x.total) > 0.01;
--      -- debe devolver CERO filas
-- 4) FUENTE INDEPENDIENTE — el total diario contra bi.v_recaudo_mes,
--    que sale de recaudo_agrupado (otra tabla):
--      select d.periodo, round(d.total,2) detalle, round(m.recaudo_total,2) agrupado,
--             round(d.total - m.recaudo_total, 2) dif,
--             round((d.total - m.recaudo_total)/nullif(m.recaudo_total,0)*100, 2) dif_pct
--      from (select periodo, sum(valor_dia) total from bi.v_recaudo_diario_cierre group by 1) d
--      join bi.v_recaudo_mes m using (periodo) order by d.periodo;
--      -- OJO: el detalle se agrupa por FECHA DE GRABACIÓN y el agrupado
--      -- por período de recaudo; una diferencia pequeña es esperable si
--      -- un pago se graba en un mes distinto al de su período.
-- 5) Patrón intra-mes (indicador C8): recaudo por día de la semana:
--      select dia_semana, round(sum(valor_dia)/1e6,0) valor_M, sum(transacciones) trx
--      from bi.v_recaudo_diario_cierre group by 1 order by 1;
-- 6) Refresco (tras cada cargue):
--      refresh materialized view concurrently bi.v_recaudo_diario_cierre;
--      refresh materialized view concurrently bi.v_recaudo_detalle_dim;
-- =====================================================================
