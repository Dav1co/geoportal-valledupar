-- =====================================================================
-- 03_v_kpi.sql · Capa 2: KPIs del Resumen ejecutivo
-- ---------------------------------------------------------------------
-- bi.v_kpi_mes es VISTA MATERIALIZADA (patrón public.predios_comercial):
-- la consulta en vivo costaba ~26 s por evaluar el casting fila a fila
-- sobre facturacion_contratos (1,2 M filas). Materializada, la lectura
-- es instantánea y el costo se paga solo al refrescar tras cada cargue:
--
--   refresh materialized view concurrently bi.v_kpi_mes;
--
-- CONCURRENTLY exige el índice único sobre periodo (definido abajo) y
-- NO bloquea a quien consulta: los lectores ven la versión anterior
-- hasta que el refresco confirma; en el peor caso leen datos con unos
-- segundos de rezago. Un REFRESH sin CONCURRENTLY sí bloquearía las
-- lecturas mientras dura.
-- Requiere 01 y 02. Sin datos personales: solo montos, % y conteos.
--
-- Definiciones oficiales (confirmadas contra los datos de 202607):
--   recaudo_0_30   = rec_0 + rec_30              (pago corriente)
--   recaudo_60_360 = rec_60 + ... + rec_360      (recuperación)
--   recaudo_may360 = rec_may360
--   contratos_activos = contratos distintos con concepto 1
--   notas_valor    = suma directa de valor (ya viene con signo)
--
-- CONVENCIÓN DE TRAMOS — NO "CORREGIR" ESTO EN EL FUTURO:
-- Los nombres de las columnas de Acuo (RECAUDO_CARTERA_0_DIAS,
-- _30_DIAS, _60_DIAS, ...) son el CORTE INFERIOR de cada cubeta, no su
-- techo. rec_0 y rec_30 JUNTOS son el pago corriente (edad 0–30): esa
-- suma reproduce el "% recaudo 0–30 = 70,7 %" del tablero histórico
-- (solo rec_0 daría ~35 %, cifra que jamás apareció en reporte alguno,
-- inverosímil en un servicio de facturación mensual). Por eso el tramo
-- siguiente siempre se llamó "60–360" y no "30–360".
-- Cuadratura verificada al centavo contra el Excel fuente de 202607:
--   recaudo_0_30 + recaudo_60_360 + recaudo_may360 = recaudo_total
--   (diferencia 0,00). Ningún tramo se pierde.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Índices parciales de expresión sobre la landing (objetos nuevos).
-- El refresco costaba ~26 s porque facturacion_contratos guarda ~7,2 M
-- de filas (1,2 M × 6 períodos retenidos) y el filtro las recorría
-- todas. El predicado del índice es EXACTAMENTE el mismo texto que el
-- filtro del CTE correspondiente: así el planificador lo aprovecha y el
-- conteo por período sale de un index-only scan.
-- ---------------------------------------------------------------------
create index if not exists facturacion_contratos_c1_ix
  on hechos.facturacion_contratos (periodo, contrato)
  where btrim(split_part(concepto, '-', 1)) = '1';

create index if not exists cartera_contrato_con_saldo_ix
  on hechos.cartera_contrato (periodo, contrato)
  where bi.f_num(total_cartera) > 0;

-- Orden de borrado: primero la dependiente, luego v_kpi_mes según el
-- tipo que tenga instalado (DROP VIEW falla si ya es materializada y
-- viceversa; el bloque lo detecta para que el script sea idempotente).
drop view if exists bi.v_kpi_anio;
do $$
begin
  if exists (select 1 from pg_matviews
             where schemaname = 'bi' and matviewname = 'v_kpi_mes') then
    execute 'drop materialized view bi.v_kpi_mes';
  elsif exists (select 1 from pg_views
                where schemaname = 'bi' and viewname = 'v_kpi_mes') then
    execute 'drop view bi.v_kpi_mes';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- bi.v_kpi_mes · una fila por período, histórico completo.
-- Las columnas nacidas del detalle (contratos_activos,
-- contratos_con_cartera) solo existen para los 6 períodos retenidos:
-- fuera de esa ventana quedan NULL, nunca 0.
-- Los CTE del detalle consultan hechos.* DIRECTO (no las vistas de
-- capa 1) con el mismo predicado de los índices parciales de arriba,
-- para que el emparejamiento índice-filtro sea literal.
-- ---------------------------------------------------------------------
create materialized view bi.v_kpi_mes as
with fact as (
  select periodo, sum(facturado) as facturado
  from bi_interno.v_facturacion_agrupado
  group by periodo
),
rec as (
  -- El grano de la fuente ya es un concepto por fila; se suma el total
  -- del período. Cualquier apertura por concepto se hace por
  -- concepto_num, nunca por nombre.
  select
    periodo,
    sum(recaudo_total) as recaudo_total,
    sum(coalesce(rec_0, 0) + coalesce(rec_30, 0)) as recaudo_0_30,
    sum(coalesce(rec_60, 0) + coalesce(rec_90, 0) + coalesce(rec_120, 0)
      + coalesce(rec_150, 0) + coalesce(rec_180, 0) + coalesce(rec_210, 0)
      + coalesce(rec_240, 0) + coalesce(rec_270, 0) + coalesce(rec_300, 0)
      + coalesce(rec_330, 0) + coalesce(rec_360, 0)) as recaudo_60_360,
    sum(coalesce(rec_may360, 0)) as recaudo_may360
  from bi_interno.v_recaudo_agrupado
  group by periodo
),
cart as (
  select periodo, sum(cartera_total) as cartera_total
  from bi_interno.v_cartera_resumen
  group by periodo
),
notas as (
  select periodo, sum(valor) as notas_valor
  from bi_interno.v_notas
  group by periodo
),
activos as (
  select periodo, count(distinct contrato) as contratos_activos
  from hechos.facturacion_contratos
  where btrim(split_part(concepto, '-', 1)) = '1'
  group by periodo
),
con_cartera as (
  select periodo, count(distinct contrato) as contratos_con_cartera
  from hechos.cartera_contrato
  where bi.f_num(total_cartera) > 0
  group by periodo
)
select
  f.periodo,
  f.facturado,
  r.recaudo_total,
  r.recaudo_0_30,
  r.recaudo_60_360,
  r.recaudo_may360,
  round(r.recaudo_0_30  / nullif(f.facturado, 0) * 100, 1) as pct_recaudo_0_30,
  round(r.recaudo_total / nullif(f.facturado, 0) * 100, 1) as pct_recaudo_mes,
  c.cartera_total,
  n.notas_valor,
  a.contratos_activos,
  cc.contratos_con_cartera
from fact f
left join rec         r  using (periodo)
left join cart        c  using (periodo)
left join notas       n  using (periodo)
left join activos     a  using (periodo)
left join con_cartera cc using (periodo)
with data;

-- Requisito de REFRESH CONCURRENTLY y clave natural de la vista.
create unique index if not exists v_kpi_mes_periodo_ux
  on bi.v_kpi_mes (periodo);

-- La materializada nació después de los REVOKE de 05: se blinda aquí.
revoke all on bi.v_kpi_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_kpi_anio · una fila por período con el acumulado del AÑO DE ESE
-- período, de enero hasta ese mes (no hasta el ancla). Vista simple
-- sobre la materializada (≈ una fila por mes cargado): hereda su
-- velocidad, no su costo — no necesita materializarse ni refrescarse.
-- ---------------------------------------------------------------------
create view bi.v_kpi_anio as
select
  periodo,
  left(periodo, 4)::int as anio,
  sum(facturado)     over anio_hasta as facturado_anio,
  sum(recaudo_total) over anio_hasta as recaudo_anio,
  round(
    sum(recaudo_total) over anio_hasta
    / nullif(sum(facturado) over anio_hasta, 0) * 100, 1
  ) as pct_recaudo_anio
from bi.v_kpi_mes
window anio_hasta as (
  partition by left(periodo, 4)
  order by periodo
  rows between unbounded preceding and current row
);

revoke all on bi.v_kpi_anio from public, anon, authenticated;
