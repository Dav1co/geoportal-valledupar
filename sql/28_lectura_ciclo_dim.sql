-- =====================================================================
-- 28_lectura_ciclo_dim.sql · Lectura efectiva y tiempos de lectura por ciclo
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Lectura" de Facturacion detallado (lectura efectiva
-- por ciclo, tiempos y rangos). Fuente: hechos.consumo_metodo. Mismo patron
-- que sql/24 a 27.
--
-- GRANO: periodo x ciclo x con_medidor x resultado_lectura x rango_dias.
--  · con_medidor: igual que bi.v_consumo_ciclo_dim (medidor no vacio y distinto
--    de 'NO APLICA', '0', 'N/A', ...). Medidor vacio = "Sin medidor".
--  · resultado_lectura, SOLO a partir de lectura_actual y lectura_anterior:
--      avance       lectura_actual >  lectura_anterior
--      igual        lectura_actual =  lectura_anterior
--      menor        lectura_actual <  lectura_anterior (vuelta de medidor o error)
--      sin_lectura  falta alguna de las dos
--  · rango_dias = fecha_lectura_actual - fecha_lectura_anterior (en dias de
--    calendario, sin hora). Limites como CONSTANTES de la funcion:
--      menos_min  < 28 dias  |  en_rango  28 a 32  |  mas_max  > 32
--      sin_fecha  falta alguna de las dos fechas o la diferencia es negativa
--    (los nombres de rango no llevan el numero: cambiar los limites no cambia
--    los valores almacenados).
--  · contratos = contratos DISTINTOS. consumo_metodo trae 1 o 2 contratos
--    duplicados por periodo (16 en 202603): se deja UNA fila por contrato antes
--    de agrupar (la que tiene medidor, luego lectura, luego mayor consumo
--    cobrado), de modo que sum(contratos) = contratos distintos del periodo y
--    no hay aviso por duplicados.
--  · dias_suma / contratos_con_dias permiten el promedio de dias al agregar
--    varias filas; dias_min / dias_max y dia_modal (dia del mes mas frecuente
--    de fecha_lectura_actual dentro de la fila).
--
-- NOTA: las fechas de lectura siguen un calendario programado por ciclo (en
-- cada ciclo p10 = p50 = p90): el cumplimiento del rango refleja la
-- programacion, no necesariamente la fecha real de lectura.
-- CICLO: tal como viene en consumo_metodo ('8', '24'; aqui el 24 llega bien).
-- Periodos: 202601 a 202609 (no existe 202606 en la fuente).
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_lectura_ciclo_dim (
  periodo           text,
  ciclo             text,
  con_medidor       boolean,
  resultado_lectura text,
  rango_dias        text,
  contratos         bigint,
  contratos_con_dias bigint,
  dias_suma         numeric,
  dias_min          integer,
  dias_max          integer,
  dia_modal         integer,
  primary key (periodo, ciclo, con_medidor, resultado_lectura, rango_dias)
);
revoke all on bi.v_lectura_ciclo_dim from public, anon, authenticated;

create or replace function bi.recalcular_lectura_ciclo_dim(p_periodo text)
returns integer language plpgsql as $$
declare
  n integer;
  c_dias_min constant integer := 28;   -- limite inferior del rango regulatorio
  c_dias_max constant integer := 32;   -- limite superior
begin
  delete from bi.v_lectura_ciclo_dim where periodo = p_periodo;
  insert into bi.v_lectura_ciclo_dim
  with u as materialized (
    select distinct on (contrato)
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)') as ciclo,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
           bi.f_num(lectura_actual)   as la,
           bi.f_num(lectura_anterior) as lp,
           case when fecha_lectura_actual   ~ '^\d{4}-\d{2}-\d{2}' then left(fecha_lectura_actual, 10)::date   end as fa,
           case when fecha_lectura_anterior ~ '^\d{4}-\d{2}-\d{2}' then left(fecha_lectura_anterior, 10)::date end as fp
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion),
  k as (
    select ciclo, con_medidor,
           case when la is null or lp is null then 'sin_lectura'
                when la > lp then 'avance'
                when la = lp then 'igual'
                else 'menor' end as resultado,
           (fa - fp) as dias,
           fa
    from u)
  select p_periodo::text, ciclo, con_medidor, resultado,
         case when dias is null or dias < 0 then 'sin_fecha'
              when dias < c_dias_min then 'menos_min'
              when dias <= c_dias_max then 'en_rango'
              else 'mas_max' end as rango_dias,
         count(*) as contratos,
         count(dias) filter (where dias >= 0) as contratos_con_dias,
         sum(dias) filter (where dias >= 0) as dias_suma,
         min(dias) filter (where dias >= 0) as dias_min,
         max(dias) filter (where dias >= 0) as dias_max,
         (mode() within group (order by extract(day from fa)::int))::integer as dia_modal
  from k
  group by ciclo, con_medidor, resultado,
           case when dias is null or dias < 0 then 'sin_fecha'
                when dias < c_dias_min then 'menos_min'
                when dias <= c_dias_max then 'en_rango'
                else 'mas_max' end;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_lectura_ciclo_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   Periodos con datos en consumo_metodo: 202601 a 202605 y 202607 a 202609
--   (no existe 202606). select bi.recalcular_lectura_ciclo_dim('2026MM'); x 8

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) = contratos DISTINTOS del periodo en consumo_metodo (111.757
--   en 202609); EXCEPT en ambos sentidos contra una consulta de referencia
--   independiente (row_number en vez de distinct on, rangos con between);
--   cifras de 202609: avance 74.533, igual 12.357, menor 762, sin_lectura
--   15.850 (con medidor) y 8.256 sin medidor; ACL igual a la de v_desviacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_lectura_ciclo_dim) desde sql/27_desviacion_dim.sql
-- drop function bi.recalcular_lectura_ciclo_dim(text);
-- drop table bi.v_lectura_ciclo_dim;
