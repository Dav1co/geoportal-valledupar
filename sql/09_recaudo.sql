-- =====================================================================
-- 09_recaudo.sql · Capa 2: pantalla de Recaudo
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06 (bi.conceptos_ruta cargada). Sin datos personales.
--
-- El núcleo sale de recaudo_agrupado: histórico de 43 períodos y solo
-- 5.740 filas (~150 conceptos por mes). Todas las vistas van EN VIVO —
-- no hay nada que materializar. NO lleva panel de filtros: la fuente
-- agrupada no tiene ciclo, uso ni estrato.
--
-- Los KPIs de % sobre facturado (0–30, del mes y del año) NO se
-- redefinen aquí: la pantalla los toma de bi.v_kpi_mes y bi.v_kpi_anio,
-- que ya los calculan. Una sola fuente de verdad para cada cifra.
-- Lo propio de esta pantalla es la composición por edades y el cruce
-- por servicio.
--
-- TRAMOS DE EDAD (misma convención oficial de bi.v_kpi_mes — los
-- nombres de columna de Acuo son el CORTE INFERIOR de cada cubeta):
--   recaudo_0_30   = rec_0 + rec_30              (pago corriente)
--   recaudo_60_360 = rec_60 + ... + rec_360      (recuperación)
--   recaudo_may360 = rec_may360                  (recuperación vieja)
-- Cuadratura verificada al centavo en 202607: los tres tramos suman
-- recaudo_total (5.022.724.833,00). NO "corregir" esta convención:
-- ver el encabezado de 03_v_kpi.sql para el razonamiento completo.
--
-- La definición de tramos está deliberadamente REPETIDA aquí (no se
-- lee de bi.v_kpi_mes) para que la pantalla sea autónoma. Si algún día
-- cambia, debe cambiar en AMBOS archivos: la verificación 1 del pie
-- compara las dos vistas y falla si divergen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_recaudo_mes · una fila por período: total, tramos de edad, su
-- composición porcentual y la variación contra el período anterior
-- CARGADO. Base de las barras mensuales por año, de la dona de edades
-- del período y de la serie histórica del mix (indicador C7 aprobado:
-- el mockup solo mostraba la composición del mes de corte).
-- ---------------------------------------------------------------------
create or replace view bi.v_recaudo_mes as
with base as (
  select
    periodo,
    sum(recaudo_total)                          as recaudo_total,
    sum(coalesce(rec_0, 0) + coalesce(rec_30, 0)) as recaudo_0_30,
    sum(coalesce(rec_60, 0) + coalesce(rec_90, 0) + coalesce(rec_120, 0)
      + coalesce(rec_150, 0) + coalesce(rec_180, 0) + coalesce(rec_210, 0)
      + coalesce(rec_240, 0) + coalesce(rec_270, 0) + coalesce(rec_300, 0)
      + coalesce(rec_330, 0) + coalesce(rec_360, 0)) as recaudo_60_360,
    sum(coalesce(rec_may360, 0))                as recaudo_may360
  from bi_interno.v_recaudo_agrupado
  group by periodo
)
select
  periodo,
  left(periodo, 4)::int                     as anio,
  right(periodo, 2)::int                    as mes,
  recaudo_total,
  recaudo_0_30,
  recaudo_60_360,
  recaudo_may360,
  recaudo_60_360 + recaudo_may360           as recuperacion_cartera,
  round(recaudo_0_30   / nullif(recaudo_total, 0) * 100, 1) as pct_0_30,
  round(recaudo_60_360 / nullif(recaudo_total, 0) * 100, 1) as pct_60_360,
  round(recaudo_may360 / nullif(recaudo_total, 0) * 100, 1) as pct_may360,
  round((recaudo_60_360 + recaudo_may360)
        / nullif(recaudo_total, 0) * 100, 1) as pct_recuperacion,
  recaudo_total - lag(recaudo_total) over w  as variacion,
  round((recaudo_total - lag(recaudo_total) over w)
        / nullif(abs(lag(recaudo_total) over w), 0) * 100, 1) as variacion_pct
from base
window w as (order by periodo);

revoke all on bi.v_recaudo_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_recaudo_servicio · la DONA: recaudo por servicio. Misma
-- agrupación de ruta_efectiva que la pantalla de Facturación, para que
-- las dos donas sean comparables entre sí (facturado vs recaudado por
-- servicio). Cruce siempre por bi.f_ruta_concepto — ninguna categoría
-- vacía. El else 'OTROS' no debería aparecer nunca.
-- ---------------------------------------------------------------------
create or replace view bi.v_recaudo_servicio as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta,
    sum(recaudo_total)               as recaudo
  from bi_interno.v_recaudo_agrupado
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
  end                        as servicio,
  sum(recaudo)               as recaudo,
  round(sum(recaudo) / nullif(sum(sum(recaudo)) over (partition by periodo), 0) * 100, 1)
                             as pct_periodo
from por_ruta
group by periodo, 2;

revoke all on bi.v_recaudo_servicio from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_recaudo_ruta · la TABLA fina: las 9 categorías de ruta_efectiva
-- con el recaudo del período, su composición y la variación contra el
-- período anterior CARGADO (lag por ruta). Simétrica a
-- bi.v_facturacion_ruta.
-- ---------------------------------------------------------------------
create or replace view bi.v_recaudo_ruta as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta_efectiva,
    sum(recaudo_total)               as recaudo
  from bi_interno.v_recaudo_agrupado
  group by periodo, bi.f_ruta_concepto(concepto_num)
)
select
  periodo,
  ruta_efectiva,
  recaudo,
  round(recaudo / nullif(sum(recaudo) over (partition by periodo), 0) * 100, 1) as pct_periodo,
  recaudo - lag(recaudo) over w as variacion,
  round((recaudo - lag(recaudo) over w)
        / nullif(abs(lag(recaudo) over w), 0) * 100, 1) as variacion_pct
from por_ruta
window w as (partition by ruta_efectiva order by periodo);

revoke all on bi.v_recaudo_ruta from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_fact_vs_recaudo_servicio · el cruce que ninguna de las dos
-- pantallas da por separado: facturado y recaudado del período por
-- servicio, con el % de recaudo de cada uno.
--
-- ⚠ ADVERTENCIA DE LECTURA (que la pantalla debe mostrar): el recaudo
-- de un mes incluye pagos de facturas de meses anteriores — por eso
-- existen los tramos de edad. Este % NO es la cobranza de la
-- facturación de ese mismo mes: es la razón entre dos flujos del
-- período. Un servicio puede superar el 100 % si ese mes se recuperó
-- mora vieja. Para la cobranza real de una facturación específica hace
-- falta la curva de cosecha (indicador C6, fase 2, sobre el detalle).
--
-- full outer join: si un servicio existiera solo en una de las dos
-- fuentes, igual aparece — nunca se pierde plata por el cruce.
-- ---------------------------------------------------------------------
create or replace view bi.v_fact_vs_recaudo_servicio as
select
  coalesce(f.periodo, r.periodo)   as periodo,
  coalesce(f.servicio, r.servicio) as servicio,
  f.facturado,
  r.recaudo,
  round(r.recaudo / nullif(f.facturado, 0) * 100, 1) as pct_recaudo,
  coalesce(r.recaudo, 0) - coalesce(f.facturado, 0)  as diferencia
from bi.v_facturacion_servicio f
full outer join bi.v_recaudo_servicio r
  on f.periodo = r.periodo and f.servicio = r.servicio;

revoke all on bi.v_fact_vs_recaudo_servicio from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES (tras ejecutar este archivo)
-- =====================================================================
-- 1) COHERENCIA con bi.v_kpi_mes — la definición de tramos está
--    repetida en los dos archivos y no puede divergir:
--      select r.periodo
--      from bi.v_recaudo_mes r join bi.v_kpi_mes k using (periodo)
--      where abs(coalesce(r.recaudo_total,0)  - coalesce(k.recaudo_total,0))  > 0.01
--         or abs(coalesce(r.recaudo_0_30,0)   - coalesce(k.recaudo_0_30,0))   > 0.01
--         or abs(coalesce(r.recaudo_60_360,0) - coalesce(k.recaudo_60_360,0)) > 0.01
--         or abs(coalesce(r.recaudo_may360,0) - coalesce(k.recaudo_may360,0)) > 0.01;
--      -- debe devolver CERO filas
-- 2) Los tres tramos suman el total en TODOS los períodos:
--      select periodo, recaudo_total,
--             recaudo_0_30 + recaudo_60_360 + recaudo_may360 as suma_tramos
--      from bi.v_recaudo_mes
--      where abs(recaudo_total - (recaudo_0_30 + recaudo_60_360 + recaudo_may360)) > 0.01;
--      -- debe devolver CERO filas; 202607 total = 5.022.724.833,00
-- 3) La dona no tiene categoría 'OTROS' ni categorías vacías:
--      select distinct servicio from bi.v_recaudo_servicio;
-- 4) La tabla fina cubre las 9 rutas en el período de corte:
--      select ruta_efectiva, recaudo, pct_periodo, variacion, variacion_pct
--      from bi.v_recaudo_ruta where periodo = '202607' order by recaudo desc;
--      -- esperado: ALCANTARILLADO-BASICO 39,0 % · ACUEDUCTO-BASICO 37,5 % ·
--      --           ACUEDUCTO-CARGO FIJO 11,2 % · ... · PLUVIAL 2,2 %
-- 5) Composición de edades del corte (dona y serie del mix):
--      select periodo, pct_0_30, pct_60_360, pct_may360, pct_recuperacion
--      from bi.v_recaudo_mes where periodo = '202607';
--      -- esperado: 86,1 % corriente · 10,6 % · 3,3 % · 13,9 % recuperación
-- 6) Cruce facturado vs recaudado por servicio en el corte:
--      select servicio, facturado, recaudo, pct_recaudo, diferencia
--      from bi.v_fact_vs_recaudo_servicio where periodo = '202607'
--      order by facturado desc nulls last;
--      -- ningún servicio debe quedar con facturado y recaudo ambos nulos
-- =====================================================================
