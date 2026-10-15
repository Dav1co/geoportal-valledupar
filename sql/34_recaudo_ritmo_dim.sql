-- =====================================================================
-- 34_recaudo_ritmo_dim.sql · Ritmo del recaudo dia a dia frente al facturado del mes (T2)
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Ritmo del mes" de Recaudo desagregada: curva del % acumulado del facturado
-- contra la meta de 85 %, banda historica y proyeccion de cierre.
-- Fuentes: hechos.recaudo_detalle (por FECHA DE GRABACION, como la ficha "Recaudo del mes") y
-- hechos.facturacion_contratos (facturado del mes). No usa clasificacion de contrato.
--
-- GRANO: periodo x dia del mes (1 a 31).
--  · recaudo_dia / recaudo_acumulado: recaudo de ese dia (fecha de grabacion) y acumulado.
--  · pct_acumulado_del_recaudo: acumulado sobre el total del mes CARGADO. En un mes parcial no es
--    definitivo (ver mes_completo).
--  · facturado_mes / pct_acumulado_del_facturado: facturado del mes (suma de facturacion_contratos)
--    y el acumulado sobre ese facturado (NULL si el periodo no tiene facturacion cargada: 202601).
--  · ultimo_dia_con_datos y mes_completo: un mes es completo si es anterior al ultimo periodo
--    cargado en recaudo_detalle o si ya tiene datos hasta su ultimo dia. Un mes parcial genera filas
--    solo hasta el ultimo dia con datos (no rellena con ceros los dias futuros).
--  · Las lineas cuya fecha de grabacion no se puede leer o cae fuera del mes (115 lineas de 202601
--    traen texto como 'CAJ 1' en esa columna) no entran en ningun dia, igual que en la ficha.
--  · Mes en curso (octubre): hoy NO hay recaudo_detalle de octubre (solo los lotes de
--    recaudo_diario, sin fechas diarias de pago), asi que la tabla no tiene octubre.
-- REGLA DEL PERIODO DE UN PAGO: el periodo de una linea de recaudo_detalle (y de un cupon) es el
-- periodo del ARCHIVO, que coincide con el mes de FECHA_DE_GRABACION (la misma regla que usa la
-- ficha "Recaudo del mes", bi.v_recaudo_diario_cierre). La fecha de pago puede ser de un mes
-- anterior (pagos grabados tarde, ~0,4 a 0,6 % del valor de cada mes).
-- CLASIFICACION (ciclo, categoria, subcategoria): hechos.cartera_contrato DEL MISMO PERIODO, via
-- bi.f_clasificacion_contrato. Se elige esa fuente y no facturacion_contratos porque (1) cubre el
-- 100 % de los contratos facturados y de los que pagan (74.177 de 74.177 en 202609; facturacion_
-- contratos deja 1 pagador sin clasificar), y (2) trae el ciclo 24 bien: facturacion_contratos
-- lo entrega como CICLO 05 (2.869 contratos en 202609). Ciclo 9999 o vacio = '(sin ciclo)'.
-- Una sola fuente de clasificacion por tabla. Categoria y subcategoria sin el codigo inicial.
-- REGLA DE MINIMO 5: las celdas con menos de 5 contratos (o cupones, o notas) se agrupan en
-- '(Otros)' / 'Otros'; las sumas no cambian.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------

create table bi.v_recaudo_ritmo_dim (
  periodo                     text,
  dia                         integer,
  recaudo_dia                 numeric,
  recaudo_acumulado           numeric,
  pct_acumulado_del_recaudo   numeric,
  facturado_mes               numeric,
  pct_acumulado_del_facturado numeric,
  ultimo_dia_con_datos        integer,
  mes_completo                boolean,
  primary key (periodo, dia)
);
revoke all on bi.v_recaudo_ritmo_dim from public, anon, authenticated;

create or replace function bi.recalcular_recaudo_ritmo_dim(p_periodo text)
returns integer language plpgsql as $$
declare
  n integer;
  v_dias integer := extract(day from (to_date(p_periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day'))::integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);   -- planes con el periodo conocido (el plan generico elige bucles anidados y no termina)
  delete from bi.v_recaudo_ritmo_dim where periodo = p_periodo;
  insert into bi.v_recaudo_ritmo_dim
  with d as materialized (
    select extract(day from left(fecha_grabacion, 10)::date)::integer as dia, sum(bi.f_num(valor_recaudo)) as v
    from hechos.recaudo_detalle
    where periodo = p_periodo and fecha_grabacion ~ '^\d{4}-\d{2}-\d{2}'
      and replace(left(fecha_grabacion, 7), '-', '') = p_periodo
    group by 1),
  u as (select coalesce(max(dia), 0) as ult, sum(v) as total from d),
  comp as (select (p_periodo < (select max(periodo) from hechos.recaudo_detalle)) or u.ult >= v_dias as c from u),
  f as materialized (select sum(bi.f_num(facturado)) as fact from hechos.facturacion_contratos where periodo = p_periodo),
  g as (
    select s as dia from generate_series(1, v_dias) s, u, comp
    where u.ult > 0 and s <= case when comp.c then v_dias else u.ult end),
  x as (select g.dia, coalesce(d.v, 0) as v from g left join d on d.dia = g.dia),
  a as (select dia, v, sum(v) over (order by dia) as acum from x)
  select p_periodo, a.dia, a.v, a.acum,
         case when u.total <> 0 then a.acum / u.total end,
         f.fact,
         case when f.fact is not null and f.fact <> 0 then a.acum / f.fact end,
         u.ult, comp.c
  from a cross join u cross join comp cross join f;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_recaudo_ritmo_dim(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X; texto tomado de la funcion viva)
CREATE OR REPLACE FUNCTION bi.recalcular(p_tabla text, p_periodo text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare n integer;
begin
  if    p_tabla = 'bi.v_fact_detalle_dim'      then n := bi.recalcular_fact_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_diario_cierre' then n := bi.recalcular_recaudo_diario_cierre(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_detalle_dim'   then n := bi.recalcular_recaudo_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_detalle_dim'   then n := bi.recalcular_cartera_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_contratos_dim' then n := bi.recalcular_cartera_contratos_dim(p_periodo);
  elsif p_tabla = 'bi.v_cupones_mes_dim'       then n := bi.recalcular_cupones_mes_dim(p_periodo);
  elsif p_tabla = 'bi.v_notas_mes_dim'         then n := bi.recalcular_notas_mes_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_ciclo_dim'     then n := bi.recalcular_consumo_ciclo_dim(p_periodo);
  elsif p_tabla = 'bi.v_desviacion_dim'        then n := bi.recalcular_desviacion_dim(p_periodo);
  elsif p_tabla = 'bi.v_lectura_ciclo_dim'     then n := bi.recalcular_lectura_ciclo_dim(p_periodo);
  elsif p_tabla = 'bi.v_observacion_dim'       then n := bi.recalcular_observacion_dim(p_periodo);
  elsif p_tabla = 'bi.v_medidor_antig_dim'     then n := bi.recalcular_medidor_antig_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_rango_dim'     then n := bi.recalcular_consumo_rango_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_basico_dim'    then n := bi.recalcular_consumo_basico_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_eficiencia_dim' then n := bi.recalcular_recaudo_eficiencia_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_ritmo_dim' then n := bi.recalcular_recaudo_ritmo_dim(p_periodo);
  else raise exception 'tabla_no_recalculable: %', p_tabla using errcode = 'P0001';
  end if;

  -- Períodos que ya no existen en la fuente (borrados por retención).
  if p_tabla = 'bi.v_fact_detalle_dim' then
    delete from bi.v_fact_detalle_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_recaudo_diario_cierre', 'bi.v_recaudo_detalle_dim') then
    execute format(
      'delete from %s t where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo)',
      p_tabla);
  elsif p_tabla = 'bi.v_cartera_detalle_dim' then
    delete from bi.v_cartera_detalle_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_contratos_dim' then
    delete from bi.v_cartera_contratos_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cupones_mes_dim' then
    delete from bi.v_cupones_mes_dim t
    where not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_notas_mes_dim' then
    delete from bi.v_notas_mes_dim t
    where not exists (select 1 from hechos.notas f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_ciclo_dim' then
    delete from bi.v_consumo_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_desviacion_dim' then
    delete from bi.v_desviacion_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_lectura_ciclo_dim' then
    delete from bi.v_lectura_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_observacion_dim' then
    delete from bi.v_observacion_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_medidor_antig_dim' then
    delete from bi.v_medidor_antig_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_rango_dim' then
    delete from bi.v_consumo_rango_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_basico_dim' then
    delete from bi.v_consumo_basico_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_eficiencia_dim' then
    delete from bi.v_recaudo_eficiencia_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_ritmo_dim' then
    delete from bi.v_recaudo_ritmo_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_recaudo_ritmo_dim', 'AAAAMM');  -- periodos: 202601, 202602, 202603, 202604, 202605, 202607, 202608, 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   el acumulado del ultimo dia = suma de recaudo_detalle con fecha de grabacion dentro del mes
--   (5.182,70 M en 202609; en 202601 queda por debajo de la suma de recaudo_detalle por las 115
--   lineas con fecha ilegible); facturado_mes = suma de facturacion_contratos; EXCEPT en ambos
--   sentidos contra una consulta de referencia independiente en los 8 periodos, uno por uno;
--   ACL igual a la de v_observacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador anterior
--   (sin la rama bi.v_recaudo_ritmo_dim) desde el archivo sql anterior
-- drop function bi.recalcular_recaudo_ritmo_dim(text);

-- drop table bi.v_recaudo_ritmo_dim;

-- =====================================================================
-- NOTA DE CARGA (cargar_hechos.py): el cargador recalcula esta dim con
--   begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- dentro de una transaccion real. ESA RUTA (SET LOCAL desde el cargador) AUN NO SE HA EJECUTADO EN UNA CARGA REAL.
-- Si falla, se recalcula a mano con exactamente esa secuencia, un periodo por vez.
-- =====================================================================
