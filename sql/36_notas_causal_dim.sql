-- =====================================================================
-- 36_notas_causal_dim.sql · Notas credito y debito por ciclo, categoria y causal (T5)
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Notas credito" de Recaudo desagregada: peso de las notas por causal.
-- Fuentes: hechos.notas (valor con signo: las notas credito CR vienen negativas, las debito DB
-- positivas, igual que bi.v_notas_mes_dim) y hechos.cartera_contrato (clasificacion).
--
-- GRANO: periodo x ciclo x categoria x causal.
--  · causal: SOLO el texto de la causal ('59-Recargo Moratorio', ...); NUNCA la observacion de la
--    nota (texto libre que puede traer nombres). Causales con menos de 5 notas en el periodo se
--    agrupan en 'Otras causales'; las celdas (ciclo x categoria x causal) con menos de 5 notas
--    pasan a ciclo y categoria '(Otros)' y CONSERVAN su causal (asi el recargo moratorio, la causal
--    mas grande, no queda escondido en 'Otras causales').
--  · notas, notas_credito, notas_debito: cantidad de notas (y de tipo CR / DB).
--  · valor: suma con signo; valor_credito (negativo) y valor_debito (positivo): suma por tipo.
--    El total de credito en valor absoluto en 202609 es 205,9 M (4,0 % del recaudo).
--  · Periodos: 202602 a 202609 (los de cartera_contrato; notas tiene desde 202301).
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

create table bi.v_notas_causal_dim (
  periodo       text,
  ciclo         text,
  categoria     text,
  causal        text,
  notas         bigint,
  notas_credito bigint,
  notas_debito  bigint,
  valor         numeric,
  valor_credito numeric,
  valor_debito  numeric,
  primary key (periodo, ciclo, categoria, causal)
);
revoke all on bi.v_notas_causal_dim from public, anon, authenticated;

create or replace function bi.recalcular_notas_causal_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);   -- planes con el periodo conocido (el plan generico elige bucles anidados y no termina)
  perform set_config('enable_nestloop', 'off', true);   -- los cruces con la clasificacion son hash: evita un plan de bucles anidados que no termina
  delete from bi.v_notas_causal_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.cartera_contrato where periodo = p_periodo) then
    return 0;
  end if;
  insert into bi.v_notas_causal_dim
  with cl as materialized (select * from bi.f_clasificacion_contrato(p_periodo)),
  nn as materialized (
    select contrato,
           coalesce(nullif(regexp_replace(btrim(causal), '\s+', ' ', 'g'), ''), '(sin causal)') as causal,
           upper(coalesce(tipo_signo, '')) as ts,
           bi.f_num(valor) as v
    from hechos.notas where periodo = p_periodo),
  ct as (select causal, count(*) as nc from nn group by causal),
  m as (
    select nn.contrato, case when ct.nc < 5 then 'Otras causales' else nn.causal end as causal, nn.ts, nn.v
    from nn join ct on ct.causal = nn.causal),
  f as (
    select coalesce(cl.ciclo, '(sin ciclo)') as ciclo, coalesce(cl.categoria, '(sin dato)') as categoria, m.causal,
           count(*) as notas, count(*) filter (where m.ts = 'CR') as nc, count(*) filter (where m.ts = 'DB') as nd,
           sum(m.v) as valor, sum(m.v) filter (where m.ts = 'CR') as vc, sum(m.v) filter (where m.ts = 'DB') as vd
    from m left join cl on cl.contrato = m.contrato
    group by 1, 2, 3),
  g as (
    -- celda chica: se agrupan SOLO ciclo y uso; la causal queda visible (ya tiene 5 o mas notas en el
    -- periodo, o es 'Otras causales')
    select case when notas < 5 then '(Otros)' else ciclo end as ciclo,
           case when notas < 5 then '(Otros)' else categoria end as categoria,
           causal,
           notas, nc, nd, valor, vc, vd
    from f)
  select p_periodo, ciclo, categoria, causal, sum(notas), sum(nc), sum(nd), sum(valor), sum(vc), sum(vd)
  from g group by ciclo, categoria, causal;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_notas_causal_dim(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X; texto tomado de la funcion viva, SIN las ramas de las
-- piezas no publicadas: el despachador de la base tiene ramas adicionales que no se usan)
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
  elsif p_tabla = 'bi.v_recaudo_edad_dim' then n := bi.recalcular_recaudo_edad_dim(p_periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then n := bi.recalcular_notas_causal_dim(p_periodo);
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
  elsif p_tabla = 'bi.v_recaudo_edad_dim' then
    delete from bi.v_recaudo_edad_dim t
    where not exists (select 1 from hechos.recaudo_agrupado f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then
    delete from bi.v_notas_causal_dim t
    where not exists (select 1 from hechos.notas f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_notas_causal_dim', 'AAAAMM');  -- periodos: 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   en 202609: credito en valor absoluto = 205,9 M; notas, neto, credito y debito = los de
--   bi.v_notas_mes_dim del mismo periodo; EXCEPT en ambos sentidos contra una consulta de referencia
--   independiente en los 8 periodos, uno por uno; ACL igual a la de v_observacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador anterior
--   (sin la rama bi.v_notas_causal_dim) desde el archivo sql anterior
-- drop function bi.recalcular_notas_causal_dim(text);

-- drop table bi.v_notas_causal_dim;
