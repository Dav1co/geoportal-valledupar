-- =====================================================================
-- 30_medidor_antig_dim.sql · Antiguedad del medidor por categoria y estrato
-- ---------------------------------------------------------------------
-- Alimenta la tabla de antiguedad de medidores de Facturacion detallado
-- (seccion "Lectura") y el % de medidores viejos de Perdidas. Fuente:
-- hechos.consumo_metodo. Patron de sql/24 a 29. SIN ciclo.
--
-- GRANO: periodo x categoria x subcategoria x banda_antiguedad x resultado_lectura
--  · Antiguedad = fecha_instalacion (NO fecha_registro) frente a la FECHA DE
--    REFERENCIA, que es el primer dia del mes evaluado (constante c_ref_dias =
--    0 dentro de la funcion: desplazamiento en dias sobre ese primer dia).
--    Anos CUMPLIDOS: '0-5' (0 <= a < 5), '5-10', '10-15', '>15' (a >= 15).
--  · Bandas finales: '0-5', '5-10', '10-15', '>15', 'Sin fecha', 'Sin medidor'.
--      'Sin medidor'  contratos sin medidor (observacion nula) -> la suma
--                     cuadra con los contratos del periodo
--      'Sin fecha'    con medidor y fecha_instalacion nula O POSTERIOR a la
--                     fecha de referencia (174 contratos en 202609): no hay una
--                     banda aparte para las fechas inconsistentes
--  · FECHA CENTINELA 1986-01-01: queda DENTRO de '>15' (decision de David). En
--    202609 son 6.314 contratos con exactamente esa fecha y su antiguedad real
--    es DESCONOCIDA (puede ser un valor por defecto del sistema); la banda '>15'
--    los incluye. La pantalla lo avisa al pie de la tabla.
--  · 202601 a 202604: fecha_instalacion viene TODA nula en esos archivos, asi
--    que todos sus contratos con medidor caen en 'Sin fecha'. No se inventa
--    nada: la pantalla muestra "—" para esos periodos. Hay antiguedad desde 202605.
--  · resultado_lectura (avance | igual | menor | sin_lectura), con medidor y
--    categoria/subcategoria como en sql/28 y sql/29.
--  · contratos = contratos DISTINTOS: una fila por contrato antes de agrupar (la
--    que tiene medidor, luego lectura, luego mayor consumo cobrado);
--    sum(contratos) = contratos distintos del periodo.
--  · contratos_cero = contratos con consumo cobrado (consumo_cargos) = 0.
--
-- Periodos: 202601 a 202609 (no existe 202606 en la fuente).
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_medidor_antig_dim (
  periodo           text,
  categoria         text,
  subcategoria      text,
  banda_antiguedad  text,
  resultado_lectura text,
  contratos         bigint,
  contratos_cero    bigint,
  primary key (periodo, categoria, subcategoria, banda_antiguedad, resultado_lectura)
);
revoke all on bi.v_medidor_antig_dim from public, anon, authenticated;

create or replace function bi.recalcular_medidor_antig_dim(p_periodo text)
returns integer language plpgsql as $$
declare
  n integer;
  c_ref_dias constant integer := 0;   -- fecha de referencia = 1.er dia del mes + estos dias
  v_ref date := to_date(p_periodo || '01', 'YYYYMMDD') + c_ref_dias;
begin
  delete from bi.v_medidor_antig_dim where periodo = p_periodo;
  insert into bi.v_medidor_antig_dim
  with u as materialized (
    select distinct on (contrato)
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as categoria,
           case when btrim(coalesce(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+','')) end as subcategoria,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
           case when fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(fecha_instalacion, 10)::date end as fi,
           case when bi.f_num(lectura_actual) is null or bi.f_num(lectura_anterior) is null then 'sin_lectura'
                when bi.f_num(lectura_actual) > bi.f_num(lectura_anterior) then 'avance'
                when bi.f_num(lectura_actual) = bi.f_num(lectura_anterior) then 'igual'
                else 'menor' end as resultado,
           (bi.f_num(consumo_cargos) = 0) as cero
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion)
  select p_periodo::text, categoria, subcategoria,
         case when not con_medidor then 'Sin medidor'
              when fi is null or fi > v_ref then 'Sin fecha'
              when extract(year from age(v_ref, fi)) < 5  then '0-5'
              when extract(year from age(v_ref, fi)) < 10 then '5-10'
              when extract(year from age(v_ref, fi)) < 15 then '10-15'
              else '>15' end as banda_antiguedad,
         resultado,
         count(*) as contratos,
         count(*) filter (where cero) as contratos_cero
  from u
  group by categoria, subcategoria, resultado,
           case when not con_medidor then 'Sin medidor'
                when fi is null or fi > v_ref then 'Sin fecha'
                when extract(year from age(v_ref, fi)) < 5  then '0-5'
                when extract(year from age(v_ref, fi)) < 10 then '5-10'
                when extract(year from age(v_ref, fi)) < 15 then '10-15'
                else '>15' end;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_medidor_antig_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_medidor_antig_dim', '2026MM');  -- 202601 a 202605 y 202607 a 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) = contratos distintos del periodo en consumo_metodo (8 periodos);
--   EXCEPT en ambos sentidos contra una consulta de referencia independiente
--   (intervalos en lugar de age()) en los 8 periodos; cifras de 202609 con
--   medidor: ver el reporte de la fase A3; ACL igual a la de v_observacion_dim.
--   Las bandas se miden en anos cumplidos: la investigacion previa usaba
--   dias/365,25, asi que unos pocos contratos pueden cambiar de banda en el borde.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_medidor_antig_dim) desde sql/29_observacion_dim.sql
-- drop function bi.recalcular_medidor_antig_dim(text);
-- drop table bi.v_medidor_antig_dim;
