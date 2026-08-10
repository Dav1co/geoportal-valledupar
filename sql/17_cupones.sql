-- =====================================================================
-- 17_cupones.sql · Capa 2: pantalla de Cupones (canales de recaudo)
-- ---------------------------------------------------------------------
-- Requiere 01, 02. Fuente: hechos.cupones_pagos — DETALLE con retención
-- de 6 períodos (~78.000 cupones por mes).
--
-- ⚠ Sin datos personales: la tabla trae contrato y número de cupón;
-- aquí solo salen conteos, montos y el canal.
--
-- QUÉ APORTA ESTA FUENTE Y NINGUNA OTRA: por dónde entra la plata.
-- El recaudo agregado dice cuánto se recaudó; esto dice a través de qué
-- entidad y agencia, con qué ticket promedio y con cuánto rezago entre
-- que el usuario paga y el pago queda grabado (indicador C11 aprobado).
--
-- ⚠ REZAGO: fecha_pago = cuando el usuario pagó en la ventanilla o el
-- canal; fecha_grabacion = cuando entró al sistema comercial. Su
-- diferencia es el rezago de conciliación bancaria. Verificado que
-- ambas fechas están completas en el ancla (78.394 de 78.394 filas).
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_cupones_mes · una fila por período: volumen, valor, ticket
-- promedio y rezago de conciliación.
-- ---------------------------------------------------------------------
create or replace view bi.v_cupones_mes as
select
  periodo,
  left(periodo, 4)::int  as anio,
  right(periodo, 2)::int as mes,
  count(*)                                        as cupones,
  sum(bi.f_num(valor))                            as valor,
  round(avg(bi.f_num(valor)), 0)                  as ticket_promedio,
  round(percentile_cont(0.5) within group (
        order by bi.f_num(valor))::numeric, 0)     as ticket_mediano,
  count(distinct entidad)                         as entidades,
  round(avg(bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago))::numeric, 2) as rezago_dias,
  count(*) filter (where bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago) > 3) as cupones_rezago_alto
from hechos.cupones_pagos
group by periodo;

revoke all on bi.v_cupones_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_cupones_canal · el desglose por entidad y agencia, que es la
-- pregunta de negocio de esta pantalla. El nombre viene con código
-- ("15-SUPER GIROS"): se conserva crudo y se expone limpio.
-- ---------------------------------------------------------------------
create or replace view bi.v_cupones_canal as
select
  periodo,
  coalesce(nullif(btrim(entidad), ''), '(sin entidad)')        as entidad_cruda,
  coalesce(nullif(btrim(split_part(entidad, '-', 2)), ''),
           nullif(btrim(entidad), ''), '(sin entidad)')        as entidad,
  coalesce(nullif(btrim(agencia_cuenta), ''), '(sin agencia)') as agencia,
  count(*)                                                     as cupones,
  sum(bi.f_num(valor))                                         as valor,
  round(avg(bi.f_num(valor)), 0)                               as ticket_promedio,
  round(avg(bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago))::numeric, 2) as rezago_dias,
  round(sum(bi.f_num(valor))
        / nullif(sum(sum(bi.f_num(valor))) over (partition by periodo), 0) * 100, 1) as pct_periodo
from hechos.cupones_pagos
group by periodo, 2, 3, 4;

revoke all on bi.v_cupones_canal from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 1) COHERENCIA — la serie contra el desglose por canal:
--      select m.periodo from bi.v_cupones_mes m
--      join (select periodo, sum(cupones) c, sum(valor) v
--            from bi.v_cupones_canal group by 1) k using (periodo)
--      where m.cupones <> k.c or abs(m.valor - k.valor) > 0.01;
--      -- debe devolver CERO filas
-- 2) FUENTE INDEPENDIENTE — el valor de cupones contra el recaudo
--    diario del mismo período (sale de recaudo_detalle, otra tabla).
--    OJO: no tienen por qué coincidir — los cupones son la vía de pago
--    y el recaudo incluye todo lo aplicado —, pero el orden de magnitud
--    debe ser el mismo y la diferencia estable:
--      select c.periodo, round(c.valor/1e6,0) cupones_M,
--             round(r.total/1e6,0) recaudo_M,
--             round((c.valor - r.total)/nullif(r.total,0)*100, 1) dif_pct
--      from bi.v_cupones_mes c
--      join (select periodo, sum(valor_dia) total from bi.v_recaudo_diario_cierre
--            group by 1) r using (periodo)
--      order by c.periodo;
-- 3) Canales del ancla (esperado: SUPER GIROS y BBVA concentran el grueso):
--      select entidad, cupones, round(valor/1e6,0) valor_M, ticket_promedio,
--             rezago_dias, pct_periodo
--      from bi.v_cupones_canal
--      where periodo = (select periodo from bi.v_ultimo_periodo)
--      order by valor desc;
-- =====================================================================
