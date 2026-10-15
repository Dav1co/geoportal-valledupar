-- =====================================================================
-- 32_consumo_basico_dim.sql · Consumo basico: residencial, estratos 1, 2 y 3
-- ---------------------------------------------------------------------
-- Alimenta la seccion de consumo basico de Facturacion detallado. Fuente:
-- hechos.consumo_metodo (consumo_cargos) + hechos.facturacion_sspd (acueducto),
-- con la MISMA logica de facturado que bi.v_consumo_rango_dim. Patron de sql/24 a 31.
--
-- ALCANCE: solo uso Residencial, subcategorias 'ESTRATO 1', 'ESTRATO 2' y
-- 'ESTRATO 3' (en la fuente: '1 Residencial', '1 ESTRATO 1', '2 ESTRATO 2',
-- '3 ESTRATO 3'; sin el codigo numerico inicial, igual que las demas dims).
-- En 202609: 32.361, 36.841 y 22.300 contratos.
--
-- UMBRAL: c_basico = 16 m3 (constante de la funcion). Hasta 16 INCLUSIVE es
-- consumo basico. Un consumo cobrado de cero cuenta como "hasta el basico".
--
-- GRANO: periodo x ciclo x categoria x subcategoria x con_medidor.
--  · contratos             contratos DISTINTOS (una fila por contrato, con la regla
--                          de siempre: con medidor, con lectura, mayor consumo)
--  · contratos_cero        consumo_cargos = 0
--  · contratos_hasta_basico  0 <= consumo_cargos <= 16 (incluye los de cero)
--  · contratos_sobre_basico  consumo_cargos > 16
--  · contratos_sin_dato      consumo_cargos nulo o negativo
--      (hasta_basico + sobre_basico + sin_dato = contratos)
--  · m3_total   = suma de consumo_cargos
--  · m3_basico  = suma de min(consumo, 16)       (la parte que no excede el basico)
--  · m3_exceso  = suma de max(consumo - 16, 0)   (la parte que pasa del basico)
--      (m3_basico + m3_exceso = m3_total)
--  · facturado_acueducto = suma de total_facturado de facturacion_sspd (acueducto);
--    NULL en 202601 a 202605 (la fuente existe desde 202606).
--
-- Periodos: 202601 a 202609 (no existe 202606 en consumo_metodo).
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_consumo_basico_dim (
  periodo                text,
  ciclo                  text,
  categoria              text,
  subcategoria           text,
  con_medidor            boolean,
  contratos              bigint,
  contratos_cero         bigint,
  contratos_hasta_basico bigint,
  contratos_sobre_basico bigint,
  contratos_sin_dato     bigint,
  m3_total               numeric,
  m3_basico              numeric,
  m3_exceso              numeric,
  facturado_acueducto    numeric,
  primary key (periodo, ciclo, categoria, subcategoria, con_medidor)
);
revoke all on bi.v_consumo_basico_dim from public, anon, authenticated;

create or replace function bi.recalcular_consumo_basico_dim(p_periodo text)
returns integer language plpgsql as $$
declare
  n integer;
  c_basico constant numeric := 16;   -- m3: hasta este valor inclusive es consumo basico
begin
  delete from bi.v_consumo_basico_dim where periodo = p_periodo;
  insert into bi.v_consumo_basico_dim
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
         count(*) as contratos,
         count(*) filter (where u.cc = 0) as contratos_cero,
         count(*) filter (where u.cc >= 0 and u.cc <= c_basico) as contratos_hasta_basico,
         count(*) filter (where u.cc > c_basico) as contratos_sobre_basico,
         count(*) filter (where u.cc is null or u.cc < 0) as contratos_sin_dato,
         sum(u.cc) as m3_total,
         sum(least(u.cc, c_basico)) filter (where u.cc >= 0) as m3_basico,
         sum(greatest(u.cc - c_basico, 0)) filter (where u.cc >= 0) as m3_exceso,
         sum(bi.f_num(s.total_facturado)) as facturado_acueducto
  from u
  left join hechos.facturacion_sspd s on s.contrato = u.contrato and s.periodo = p_periodo
  where u.categoria = 'Residencial' and u.subcategoria in ('ESTRATO 1', 'ESTRATO 2', 'ESTRATO 3')
  group by u.ciclo, u.categoria, u.subcategoria, u.con_medidor;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_consumo_basico_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_consumo_basico_dim', '2026MM');  -- 202601 a 202605 y 202607 a 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) y sum(m3_total) = los de bi.v_consumo_rango_dim para Residencial
--   estratos 1, 2 y 3 del mismo periodo; hasta_basico + sobre_basico + sin_dato =
--   contratos; m3_basico + m3_exceso = m3_total; facturado igual al de
--   v_consumo_rango_dim para esos estratos; EXCEPT en ambos sentidos contra una
--   consulta de referencia independiente (row_number, sumas con CASE) en los 8
--   periodos, uno por uno, comparando la tabla ya cargada; ACL igual a la de
--   v_observacion_dim; las otras dims no cambian de filas.
--   NOTA de ejecucion: en los periodos con facturacion_sspd (202607 a 202609) la
--   consulta de referencia pide "set local enable_nestloop = off", porque el
--   planificador subestima el lado de los contratos y re-lee el agregado de sspd
--   por cada fila (no termina). Es un detalle de la prueba, no de la tabla.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_consumo_basico_dim) desde sql/31_consumo_rango_dim.sql
-- drop function bi.recalcular_consumo_basico_dim(text);
-- drop table bi.v_consumo_basico_dim;
