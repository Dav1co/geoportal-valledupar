-- =====================================================================
-- 10_cartera.sql · Capa 2: pantalla de Cartera agrupado
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06. Sin datos personales.
-- Fuente: cartera_resumen (histórico de 43 períodos, 8.790 filas) —
-- vistas EN VIVO, nada que materializar. Sin panel de filtros: la
-- fuente agrupada no tiene barrio, ciclo, uso ni estrato (eso llega en
-- la pantalla 7, Cartera detallado, sobre cartera_edades).
--
-- ⚠ ESTRUCTURA DE LA CARTERA — el hallazgo que ordena esta pantalla:
--   cartera_total = cartera NO FINANCIADA + cartera FINANCIADA
-- Las cubetas de edad (cf_cart0 … cf_cartmay) SOLO cubren la cartera NO
-- financiada: su suma NO iguala cartera_total, y esa brecha no es un
-- error del cargue ni del reporte. Verificado contra fuente
-- independiente en 202607:
--   total 118.840 M − cubetas 108.819 M = 10.021 M implícitos
--   hechos.cartera_contrato.saldo_financiado = 10.028 M (8.854 contratos)
--   desviación 0,07 %
-- La brecha existe en los 43 períodos y crece con el tiempo (4,3 % en
-- 2023 → 8,4 % en 2026): la financiación de deuda viene ganando peso.
-- Por eso la pantalla expone las dos piezas por separado y NUNCA
-- presenta la suma de cubetas como si fuera la cartera total.
--
-- TRAMOS DE EDAD: los nombres de columna de Acuo son el CORTE INFERIOR
-- de cada cubeta (misma convención que el recaudo). Se agrupan en
-- cuatro tramos legibles para el negocio.
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_cartera_mes · una fila por período: total, la descomposición
-- financiada / no financiada, los cuatro tramos de edad y la variación
-- contra el período anterior CARGADO.
-- ---------------------------------------------------------------------
create or replace view bi.v_cartera_mes as
with base as (
  select
    periodo,
    sum(cartera_total) as cartera_total,
    sum(coalesce(cf_cart0, 0) + coalesce(cf_cart30, 0))              as t_hasta_60,
    sum(coalesce(cf_cart60, 0) + coalesce(cf_cart90, 0)
      + coalesce(cf_cart120, 0) + coalesce(cf_cart150, 0))           as t_60_180,
    sum(coalesce(cf_cart180, 0) + coalesce(cf_cart210, 0) + coalesce(cf_cart240, 0)
      + coalesce(cf_cart270, 0) + coalesce(cf_cart300, 0) + coalesce(cf_cart330, 0)) as t_180_360,
    sum(coalesce(cf_cart360, 0) + coalesce(cf_cartmay, 0))           as t_may_360
  from bi_interno.v_cartera_resumen
  group by periodo
),
calc as (
  select
    periodo,
    cartera_total,
    t_hasta_60, t_60_180, t_180_360, t_may_360,
    t_hasta_60 + t_60_180 + t_180_360 + t_may_360 as no_financiada,
    cartera_total - (t_hasta_60 + t_60_180 + t_180_360 + t_may_360) as financiada
  from base
)
select
  periodo,
  left(periodo, 4)::int  as anio,
  right(periodo, 2)::int as mes,
  cartera_total,
  no_financiada,
  financiada,
  t_hasta_60, t_60_180, t_180_360, t_may_360,
  round(financiada / nullif(cartera_total, 0) * 100, 1) as pct_financiada,
  round(t_may_360 / nullif(cartera_total, 0) * 100, 1)  as pct_may_360,
  round(t_may_360 / nullif(no_financiada, 0) * 100, 1)  as pct_may_360_sobre_no_fin,
  cartera_total - lag(cartera_total) over w             as variacion,
  round((cartera_total - lag(cartera_total) over w)
        / nullif(abs(lag(cartera_total) over w), 0) * 100, 1) as variacion_pct
from calc
window w as (order by periodo);

revoke all on bi.v_cartera_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_cartera_tramo · formato largo para la dona y la serie de
-- composición: un renglón por período y tramo, incluida la FINANCIADA
-- como tramo propio para que las partes sumen siempre cartera_total.
-- ---------------------------------------------------------------------
create or replace view bi.v_cartera_tramo as
select periodo, orden, tramo, valor,
       round(valor / nullif(sum(valor) over (partition by periodo), 0) * 100, 1) as pct_periodo
from (
  select periodo, 1 as orden, 'Hasta 60 días'      as tramo, t_hasta_60 as valor from bi.v_cartera_mes
  union all
  select periodo, 2, '60 a 180 días',   t_60_180   from bi.v_cartera_mes
  union all
  select periodo, 3, '180 a 360 días',  t_180_360  from bi.v_cartera_mes
  union all
  select periodo, 4, 'Más de 360 días', t_may_360  from bi.v_cartera_mes
  union all
  select periodo, 5, 'Financiada',      financiada from bi.v_cartera_mes
) t;

revoke all on bi.v_cartera_tramo from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_cartera_servicio · cartera por servicio, misma agrupación de
-- ruta_efectiva que Facturación y Recaudo (donas comparables entre las
-- tres pantallas). El cruce va por número de concepto (recaconc).
-- ---------------------------------------------------------------------
create or replace view bi.v_cartera_servicio as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta,
    sum(cartera_total)               as cartera
  from bi_interno.v_cartera_resumen
  group by periodo, bi.f_ruta_concepto(concepto_num)
)
select
  periodo,
  case
    when ruta like 'ACUEDUCTO -%'      then 'ACUEDUCTO'
    when ruta like 'ALCANTARILLADO -%' then 'ALCANTARILLADO'
    when ruta = 'PLUVIAL'              then 'PLUVIAL'
    when ruta = 'TERCERO'              then 'TERCERO'
    else 'OTROS'
  end                      as servicio,
  sum(cartera)             as cartera,
  round(sum(cartera) / nullif(sum(sum(cartera)) over (partition by periodo), 0) * 100, 1)
                           as pct_periodo
from por_ruta
group by periodo, 2;

revoke all on bi.v_cartera_servicio from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_cartera_ruta · la TABLA fina: las categorías de ruta_efectiva
-- con la cartera del período, su peso y la variación contra el período
-- anterior CARGADO.
-- ---------------------------------------------------------------------
create or replace view bi.v_cartera_ruta as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta_efectiva,
    sum(cartera_total)               as cartera
  from bi_interno.v_cartera_resumen
  group by periodo, bi.f_ruta_concepto(concepto_num)
)
select
  periodo,
  ruta_efectiva,
  cartera,
  round(cartera / nullif(sum(cartera) over (partition by periodo), 0) * 100, 1) as pct_periodo,
  cartera - lag(cartera) over w as variacion,
  round((cartera - lag(cartera) over w)
        / nullif(abs(lag(cartera) over w), 0) * 100, 1) as variacion_pct
from por_ruta
window w as (partition by ruta_efectiva order by periodo);

revoke all on bi.v_cartera_ruta from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES (tras ejecutar este archivo)
-- =====================================================================
-- 1) COHERENCIA con bi.v_kpi_mes (misma fuente, distinta agregación):
--      select count(*) from bi.v_cartera_mes c join bi.v_kpi_mes k using (periodo)
--      where abs(coalesce(c.cartera_total,0) - coalesce(k.cartera_total,0)) > 0.01;
--      -- debe devolver CERO
-- 2) FUENTE INDEPENDIENTE — la financiada implícita contra el detalle
--    por contrato (solo los 6 períodos retenidos):
--      select c.periodo, round(c.financiada/1e6,0) implicita_M,
--             round(sum(bi.f_num(d.saldo_financiado))/1e6,0) detalle_M
--      from bi.v_cartera_mes c
--      join hechos.cartera_contrato d using (periodo)
--      group by c.periodo, c.financiada order by c.periodo;
--      -- 202607 esperado: 10.021 M vs 10.028 M (desviación 0,07 %)
-- 3) FUENTE INDEPENDIENTE — el total contra cartera_edades:
--      select round(sum(bi.f_num(total))/1e6,0) from hechos.cartera_edades
--      where periodo = '202607';   -- esperado 118.840 M
-- 4) Las partes suman el total en todos los períodos:
--      select periodo from bi.v_cartera_mes
--      where abs(cartera_total - (no_financiada + financiada)) > 0.01;
--      -- debe devolver CERO
-- 5) Los tramos de bi.v_cartera_tramo suman cartera_total:
--      select t.periodo from bi.v_cartera_tramo t join bi.v_cartera_mes m using (periodo)
--      group by t.periodo, m.cartera_total
--      having abs(sum(t.valor) - m.cartera_total) > 0.01;
--      -- debe devolver CERO
-- 6) Composición del corte 202607:
--      select tramo, valor, pct_periodo from bi.v_cartera_tramo
--      where periodo = '202607' order by orden;
-- =====================================================================
