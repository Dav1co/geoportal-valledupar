-- =====================================================================
-- 31_consumo_rango_dim.sql · Contratos, m3 y facturado por rango de consumo
-- ---------------------------------------------------------------------
-- Alimenta la seccion de rangos de consumo de Facturacion detallado.
-- Fuente: hechos.consumo_metodo (consumo_cargos) + hechos.facturacion_sspd
-- (acueducto), con la MISMA logica de facturado que bi.v_consumo_ciclo_dim.
-- Patron de sql/24 a 30. Los rangos son solo bandas de consumo.
--
-- GRANO: periodo x ciclo x categoria x subcategoria x con_medidor x rango_consumo
--  (1.362 a 1.552 filas por periodo en los 8 periodos cargados: una sola tabla).
--  · rango_consumo: consumo cobrado del contrato (consumo_cargos) en m3, con el
--    LIMITE SUPERIOR INCLUSIVO. Etiquetas guardadas:
--      '0'  '1-5'  '6-10'  '11-15'  '16-20'  '21-30'  '31-40'  '41-60'  '61-100'  '>100'
--    mas 'Sin dato' (consumo_cargos nulo o negativo).
--    Si hubiera decimales, el valor cae en la banda cuyo limite superior lo
--    contiene (5,5 -> '6-10'; 0,5 -> '1-5'). En los 8 periodos cargados NO hay
--    nulos, negativos ni decimales (minimo 0, maximo 38.101 m3).
--  · con_medidor, categoria, subcategoria y ciclo: igual que sql/28 a 30 (categoria
--    y subcategoria sin el codigo numerico inicial; ciclo tal como viene).
--  · contratos = contratos DISTINTOS: una fila por contrato antes de agrupar (la
--    que tiene medidor, luego lectura, luego mayor consumo cobrado); sum(contratos)
--    = contratos distintos del periodo. Esa fila conserva el mayor consumo, asi que
--    sum(m3_cargos) no cambia por los duplicados de la fuente.
--  · m3_cargos = suma de consumo_cargos. facturado_acueducto = suma de
--    total_facturado de facturacion_sspd (acueducto) por contrato y periodo; NULL
--    si el periodo no tiene facturacion_sspd (solo 202606 a 202609; 202601 a 202605
--    quedan en NULL, igual que bi.v_consumo_ciclo_dim).
--
-- Periodos: 202601 a 202609 (no existe 202606 en consumo_metodo).
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_consumo_rango_dim (
  periodo             text,
  ciclo               text,
  categoria           text,
  subcategoria        text,
  con_medidor         boolean,
  rango_consumo       text,
  contratos           bigint,
  m3_cargos           numeric,
  facturado_acueducto numeric,
  primary key (periodo, ciclo, categoria, subcategoria, con_medidor, rango_consumo)
);
revoke all on bi.v_consumo_rango_dim from public, anon, authenticated;

create or replace function bi.recalcular_consumo_rango_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_consumo_rango_dim where periodo = p_periodo;
  insert into bi.v_consumo_rango_dim
  with u as materialized (
    select distinct on (contrato) contrato,
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as categoria,
           case when btrim(coalesce(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+','')) end as subcategoria,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
           bi.f_num(consumo_cargos) as cc
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion)
  select p_periodo::text, u.ciclo, u.categoria, u.subcategoria, u.con_medidor,
         case when u.cc is null or u.cc < 0 then 'Sin dato'
              when u.cc = 0   then '0'
              when u.cc <= 5  then '1-5'
              when u.cc <= 10 then '6-10'
              when u.cc <= 15 then '11-15'
              when u.cc <= 20 then '16-20'
              when u.cc <= 30 then '21-30'
              when u.cc <= 40 then '31-40'
              when u.cc <= 60 then '41-60'
              when u.cc <= 100 then '61-100'
              else '>100' end as rango_consumo,
         count(*) as contratos,
         sum(u.cc) as m3_cargos,
         sum(bi.f_num(s.total_facturado)) as facturado_acueducto
  from u
  left join hechos.facturacion_sspd s on s.contrato = u.contrato and s.periodo = p_periodo
  group by u.ciclo, u.categoria, u.subcategoria, u.con_medidor,
           case when u.cc is null or u.cc < 0 then 'Sin dato'
                when u.cc = 0   then '0'
                when u.cc <= 5  then '1-5'
                when u.cc <= 10 then '6-10'
                when u.cc <= 15 then '11-15'
                when u.cc <= 20 then '16-20'
                when u.cc <= 30 then '21-30'
                when u.cc <= 40 then '31-40'
                when u.cc <= 60 then '41-60'
                when u.cc <= 100 then '61-100'
                else '>100' end;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_consumo_rango_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_consumo_rango_dim', '2026MM');  -- 202601 a 202605 y 202607 a 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) = contratos distintos del periodo en consumo_metodo (111.757 en
--   202609); sum(m3_cargos) = sum(m3_cargos) de bi.v_consumo_ciclo_dim del periodo;
--   sum(facturado_acueducto) = el de v_consumo_ciclo_dim (NULL en 202601 a 202605);
--   EXCEPT en ambos sentidos contra una consulta de referencia independiente
--   (row_number y una tabla de limites en lugar de la cadena de CASE) en los 8
--   periodos, uno por uno; ACL igual a la de v_observacion_dim; las otras dims
--   no cambian de filas.
--   NOTA facturado: en 202607 a 202609 sum(facturado_acueducto) de esta tabla es
--   MENOR que el de bi.v_consumo_ciclo_dim en 49.526, 55.493 y 49.454 pesos: es
--   exactamente el facturado de los contratos duplicados de consumo_metodo (1, 2 y
--   1), que v_consumo_ciclo_dim cuenta dos veces por unirse a facturacion_sspd con
--   las dos filas. Esta tabla deja una fila por contrato y no los duplica.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_consumo_rango_dim) desde sql/30_medidor_antig_dim.sql
-- drop function bi.recalcular_consumo_rango_dim(text);
-- drop table bi.v_consumo_rango_dim;
