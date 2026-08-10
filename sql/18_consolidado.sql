-- =====================================================================
-- 18_consolidado.sql · Capa 2: pantalla Consolidado (ANÁLISIS)
-- ---------------------------------------------------------------------
-- Requiere 03, 08, 09, 10, 16, 17 (consume sus vistas, no reimplementa
-- sus definiciones: cada cifra sale de la pantalla especializada, así
-- que no puede divergir de ella).
--
-- PARA QUÉ: las demás pantallas muestran UN mes; para ver comportamiento
-- hay que ir cambiando el selector. Esta da el año completo de un
-- vistazo, con todos los frentes cruzados, para detectar dónde pasó algo
-- y entonces ir a la pantalla específica a profundizar.
--
-- ⚠ VENTANAS: las columnas que nacen del DETALLE solo existen en los 6
-- períodos retenidos y quedan NULL fuera de esa ventana — nunca en cero.
-- Son: ticket_facturacion (necesita contratos facturados) y todo lo de
-- cupones (ticket_pago, cupones_procesados).
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_consolidado_mes · la matriz mensual: todos los frentes en una
-- fila por período, más la variación contra el MISMO MES del año
-- anterior (lag 12 sobre la serie continua de períodos).
-- ---------------------------------------------------------------------
create or replace view bi.v_consolidado_mes as
with base as (
  select
    f.periodo,
    left(f.periodo, 4)::int  as anio,
    right(f.periodo, 2)::int as mes,
    f.neta                          as facturado,
    f.m3_acueducto,
    f.m3_alcantarillado,
    r.recaudo_total,
    r.recaudo_0_30                  as recaudo_corriente,
    r.recuperacion_cartera,
    c.cartera_total,
    c.financiada                    as cartera_financiada,
    c.t_may_360                     as cartera_may_360,
    nt.valor_neto                   as notas_valor,
    cu.cupones                      as cupones_procesados,
    cu.valor                        as cupones_valor,
    k.contratos_activos,
    -- Cobertura: recaudo del mes sobre facturado del mes.
    round(r.recaudo_total / nullif(f.neta, 0) * 100, 1)         as pct_recaudo,
    -- Rotación: a cuántos meses de facturación equivale la deuda.
    round(c.cartera_total / nullif(f.neta, 0), 2)               as rotacion_cartera,
    -- Ticket de FACTURACIÓN: cuánto se le cobra en promedio a cada
    -- suscriptor. Necesita el detalle -> NULL fuera de la ventana.
    round(f.neta / nullif(k.contratos_activos, 0), 2)           as ticket_facturacion,
    -- Ticket de PAGO: cuánto paga la gente por transacción. NO es lo
    -- mismo: alguien puede pagar varias facturas juntas o abonar
    -- parcialmente. Necesita cupones -> NULL fuera de la ventana.
    round(cu.valor / nullif(cu.cupones, 0), 2)                  as ticket_pago
  from bi.v_facturacion_mes f
  left join bi.v_recaudo_mes  r  using (periodo)
  left join bi.v_cartera_mes  c  using (periodo)
  left join bi.v_notas_mes    nt using (periodo)
  left join bi.v_cupones_mes  cu using (periodo)
  left join bi.v_kpi_mes      k  using (periodo)
)
select
  b.*,
  -- Variación de cartera contra el mes anterior (crecimiento mensual).
  b.cartera_total - lag(b.cartera_total) over (order by b.periodo)      as var_cartera_mes,
  round((b.cartera_total - lag(b.cartera_total) over (order by b.periodo))
        / nullif(lag(b.cartera_total) over (order by b.periodo), 0) * 100, 2) as var_cartera_mes_pct,
  -- Variación contra el MISMO MES del año anterior.
  a.facturado          as facturado_ant,
  a.recaudo_total      as recaudo_total_ant,
  a.cartera_total      as cartera_total_ant,
  a.pct_recaudo        as pct_recaudo_ant,
  a.notas_valor        as notas_valor_ant,
  a.m3_acueducto       as m3_acueducto_ant,
  a.cupones_procesados as cupones_procesados_ant,
  a.ticket_facturacion as ticket_facturacion_ant,
  a.ticket_pago        as ticket_pago_ant
from base b
left join base a
  on a.anio = b.anio - 1 and a.mes = b.mes;

revoke all on bi.v_consolidado_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_consolidado_anio · la foto de largo plazo: una fila por vigencia.
-- La cartera "al cierre" es la del ÚLTIMO mes con dato de ese año (para
-- 2026 en curso, el último mes cargado), no un promedio.
-- ---------------------------------------------------------------------
create or replace view bi.v_consolidado_anio as
with m as (select * from bi.v_consolidado_mes),
cierre as (
  select distinct on (anio) anio, periodo, cartera_total, cartera_may_360, cartera_financiada
  from m where cartera_total is not null
  order by anio, periodo desc
),
agg as (
  select
    anio,
    count(*)                        as meses_con_datos,
    max(periodo)                    as ultimo_periodo,
    sum(facturado)                  as facturado,
    sum(recaudo_total)              as recaudo_total,
    sum(recaudo_corriente)          as recaudo_corriente,
    sum(recuperacion_cartera)       as recuperacion_cartera,
    sum(notas_valor)                as notas_valor,
    sum(m3_acueducto)               as m3_acueducto,
    sum(cupones_procesados)         as cupones_procesados
  from m group by anio
)
select
  a.anio,
  a.meses_con_datos,
  a.ultimo_periodo,
  a.facturado,
  a.recaudo_total,
  round(a.recaudo_total / nullif(a.facturado, 0) * 100, 1) as pct_recaudo,
  a.recaudo_corriente,
  a.recuperacion_cartera,
  round(a.recaudo_corriente / nullif(a.recaudo_total, 0) * 100, 1)    as pct_corriente,
  round(a.recuperacion_cartera / nullif(a.recaudo_total, 0) * 100, 1) as pct_recuperacion,
  c.cartera_total                       as cartera_cierre,
  c.cartera_may_360                     as cartera_may_360_cierre,
  c.cartera_financiada                  as cartera_financiada_cierre,
  c.cartera_total - lag(c.cartera_total) over (order by a.anio) as var_cartera_anual,
  round((c.cartera_total - lag(c.cartera_total) over (order by a.anio))
        / nullif(lag(c.cartera_total) over (order by a.anio), 0) * 100, 1) as var_cartera_anual_pct,
  round(c.cartera_total / nullif(a.facturado / nullif(a.meses_con_datos, 0), 0), 2) as rotacion_cartera,
  a.notas_valor,
  a.m3_acueducto,
  a.cupones_procesados
from agg a
left join cierre c using (anio);

revoke all on bi.v_consolidado_anio from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES · cada columna contra su pantalla especializada
-- =====================================================================
-- 1) FACTURADO contra bi.v_facturacion_mes:
--      select c.periodo from bi.v_consolidado_mes c
--      join bi.v_facturacion_mes f using (periodo)
--      where abs(coalesce(c.facturado,0) - coalesce(f.neta,0)) > 0.01;
-- 2) RECAUDO contra bi.v_recaudo_mes:
--      select c.periodo from bi.v_consolidado_mes c
--      join bi.v_recaudo_mes r using (periodo)
--      where abs(coalesce(c.recaudo_total,0) - coalesce(r.recaudo_total,0)) > 0.01
--         or abs(coalesce(c.recaudo_corriente,0) - coalesce(r.recaudo_0_30,0)) > 0.01;
-- 3) CARTERA contra bi.v_cartera_mes:
--      select c.periodo from bi.v_consolidado_mes c
--      join bi.v_cartera_mes k using (periodo)
--      where abs(coalesce(c.cartera_total,0) - coalesce(k.cartera_total,0)) > 0.01;
-- 4) NOTAS contra bi.v_notas_mes y CUPONES contra bi.v_cupones_mes:
--      select c.periodo from bi.v_consolidado_mes c
--      left join bi.v_notas_mes n using (periodo)
--      left join bi.v_cupones_mes u using (periodo)
--      where abs(coalesce(c.notas_valor,0) - coalesce(n.valor_neto,0)) > 0.01
--         or coalesce(c.cupones_procesados,-1) <> coalesce(u.cupones,-1);
--    Las cuatro deben devolver CERO filas.
-- 5) VENTANAS: los tickets solo existen en los 6 períodos retenidos:
--      select periodo, ticket_facturacion, ticket_pago
--      from bi.v_consolidado_mes order by periodo desc limit 10;
--      -- NULL fuera de la ventana, nunca 0
-- 6) La serie por vigencia (esperado: % recaudo creciendo de ~0,78 a ~0,85):
--      select anio, meses_con_datos, pct_recaudo, cartera_cierre,
--             var_cartera_anual_pct, rotacion_cartera
--      from bi.v_consolidado_anio order by anio;
-- =====================================================================
