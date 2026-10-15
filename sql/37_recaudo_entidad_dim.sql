-- =====================================================================
-- 37_recaudo_entidad_dim.sql · Recaudo por entidad y agencia (canal de pago) (T6)
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Entidad y agencia" de Recaudo desagregada. Fuentes: hechos.cupones_pagos
-- (un cupon = un pago) y hechos.cartera_contrato (clasificacion). Sin hora ni caja ni usuario: el
-- canal se infiere de la entidad y la agencia.
--
-- GRANO: periodo x entidad x agencia x categoria.
--  · entidad: nombre sin el codigo inicial ('SUPER GIROS', 'BANCO BBVA COLOMBIA', ...).
--  · agencia: nombre de la agencia o cuenta SIN el codigo inicial ni los numeros de cuenta o convenio
--    (se eliminan los grupos de 5 o mas digitos): 'BBVA PSE EMDUPAR', 'BBVA CONVENIO', ...
--  · en_linea: la agencia es de PSE (pago en linea).
--  · cupones, valor (suma de valor del cupon) y contratos (distintos que pagaron en esa celda).
--  · Minimo 5: las celdas (entidad, agencia, categoria) con menos de 5 cupones pasan a entidad
--    'Otros' y agencia 'Otros' (aqui caen 'EMDUPAR' y las entidades pequenas); si aun asi quedan con
--    menos de 5 cupones, la categoria pasa a '(Otros)'.
--  · Periodos: 202602 a 202609 (incluye 202606: hay cupones aunque no hay recaudo_detalle).
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

create table bi.v_recaudo_entidad_dim (
  periodo   text,
  entidad   text,
  agencia   text,
  categoria text,
  en_linea  boolean,
  cupones   bigint,
  valor     numeric,
  contratos bigint,
  primary key (periodo, entidad, agencia, categoria)
);
revoke all on bi.v_recaudo_entidad_dim from public, anon, authenticated;

create or replace function bi.recalcular_recaudo_entidad_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);   -- planes con el periodo conocido (el plan generico elige bucles anidados y no termina)
  perform set_config('enable_nestloop', 'off', true);   -- los cruces con la clasificacion son hash: evita un plan de bucles anidados que no termina
  delete from bi.v_recaudo_entidad_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.cartera_contrato where periodo = p_periodo) then
    return 0;
  end if;
  insert into bi.v_recaudo_entidad_dim
  with cl as materialized (select * from bi.f_clasificacion_contrato(p_periodo)),
  c as materialized (
    select cu.contrato, bi.f_num(cu.valor) as v,
           regexp_replace(btrim(cu.entidad), '^\d+\s*-\s*', '') as entidad,
           btrim(regexp_replace(regexp_replace(regexp_replace(btrim(cu.agencia_cuenta), '^\d+\s*-\s*', ''), '\d{5,}', '', 'g'), '\s+', ' ', 'g'), ' -.') as agencia,
           coalesce(cl.categoria, '(sin dato)') as categoria
    from hechos.cupones_pagos cu left join cl on cl.contrato = cu.contrato
    where cu.periodo = p_periodo),
  c1 as (
    select entidad, agencia, categoria, count(*) as cupones from c group by 1, 2, 3),
  c2 as materialized (
    select c.contrato, c.v, c.categoria,
           case when c1.cupones < 5 then 'Otros' else c.entidad end as entidad,
           case when c1.cupones < 5 then 'Otros' else c.agencia end as agencia
    from c join c1 on c1.entidad = c.entidad and c1.agencia = c.agencia and c1.categoria = c.categoria),
  c3 as (select entidad, agencia, categoria, count(*) as cupones from c2 group by 1, 2, 3),
  c4 as (
    select c2.contrato, c2.v, c2.entidad, c2.agencia,
           case when c3.cupones < 5 then '(Otros)' else c2.categoria end as categoria
    from c2 join c3 on c3.entidad = c2.entidad and c3.agencia = c2.agencia and c3.categoria = c2.categoria)
  select p_periodo, entidad, agencia, categoria, (agencia ~* 'PSE') as en_linea,
         count(*), sum(v), count(distinct contrato)
  from c4 group by entidad, agencia, categoria;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_recaudo_entidad_dim(text) from public, anon, authenticated;

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
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then n := bi.recalcular_recaudo_entidad_dim(p_periodo);
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
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then
    delete from bi.v_recaudo_entidad_dim t
    where not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_recaudo_entidad_dim', 'AAAAMM');  -- periodos: 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(cupones) y sum(valor) = los de cupones_pagos del periodo (77.629 cupones y 5.182,70 M en
--   202609); BBVA PSE ~ 32,8 % del valor en 202609; EXCEPT en ambos sentidos contra una consulta de
--   referencia independiente en los 8 periodos, uno por uno; ACL igual a la de v_observacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador anterior
--   (sin la rama bi.v_recaudo_entidad_dim) desde el archivo sql anterior
-- drop function bi.recalcular_recaudo_entidad_dim(text);

-- drop table bi.v_recaudo_entidad_dim;
