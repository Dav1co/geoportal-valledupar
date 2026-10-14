-- =====================================================================
-- 27_desviacion_dim.sql · Contratos con desviacion significativa de consumo
-- ---------------------------------------------------------------------
-- Res. CRA 943 de 2021, art. 1.13.1.6 (facturacion mensual). Alimenta la
-- seccion "Contratos con desviacion significativa" de Facturacion detallado.
-- Fuente: hechos.facturacion_contratos. Mismo patron que sql/24, 25 y 26.
--
-- DEFINICION (por contrato y periodo evaluado P)
--  · Consumo del periodo = m3 de la LINEA 2 (left(btrim(concepto),2)='2-',
--    una fila por contrato). Un contrato que existe en el periodo (tiene
--    cualquier fila) sin linea 2 tiene consumo 0.
--  · Promedio = promedio de los 6 periodos INMEDIATAMENTE ANTERIORES del mismo
--    contrato, ceros incluidos.
--  · Umbral: 35 % si el promedio es >= 40 m3; 65 % si es < 40 m3.
--  · Desviacion = (consumo - promedio) / promedio. Positiva si > umbral;
--    negativa si < -umbral (comparacion ESTRICTA).
--  · tipo_desviacion: positiva | negativa | sin_desviacion |
--    sin_historial (el contrato no existe en alguno de los 6 periodos
--    anteriores) | sin_promedio (promedio = 0 con consumo > 0). Estas dos
--    ultimas NO son desviacion ni se suman al total de desviacion.
--    Promedio 0 con consumo 0 se queda en sin_desviacion.
--  · grupo_umbral: ge40 | lt40 | sin_umbral (sin historial o promedio 0).
--
-- INDICADOR APARTE: contratos_cero_6m = contratos de la fila con consumo cero
--  (sin linea 2, existiendo como contrato) durante 6 periodos consecutivos,
--  contando el periodo evaluado y los 5 anteriores. Es INDEPENDIENTE de
--  tipo_desviacion y se solapa con cualquiera (p. ej. un contrato puede ser
--  cero sostenido y estar en negativa). Los de 7 periodos (los 6 anteriores y
--  el actual, promedio 0 y consumo 0) son exactamente los de sin_desviacion
--  con promedio 0.
--
-- SOLO SE CALCULA con los 6 periodos anteriores completos en
-- facturacion_contratos: sin ellos la funcion devuelve 0 filas (no ceros). Hoy
-- hay fila para 202608 y 202609; 202602 a 202607 no (202601 no existe en esta
-- fuente).
--
-- DEPENDENCIA HACIA ADELANTE: recargar un periodo q cambia los 6 periodos
-- siguientes. Esta funcion recalcula UN periodo; el cargador (cargar_hechos.py)
-- recalcula en cascada q y los periodos existentes de q+1 a q+6.
-- COSTO: ~1 min por periodo (escanea 7 periodos de la fuente). Es normal.
--
-- CICLO: tal como viene en facturacion_contratos ('CICLO 08'), igual que
-- bi.v_fact_detalle_dim. El ciclo 24 llega como CICLO 05 desde la fuente
-- (problema ya conocido): no se corrige aqui.
-- CATEGORIA/SUBCATEGORIA: de facturacion_contratos ('Residencial',
-- 'ESTRATO 1'); en no residenciales la subcategoria es el diametro.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
-- Tipos tomados de la descripcion de la consulta de referencia (\gdesc).
create table bi.v_desviacion_dim (
  periodo           text,
  ciclo             text,
  categoria         text,
  subcategoria      text,
  tipo_desviacion   text,
  grupo_umbral      text,
  contratos         bigint,
  m3_periodo        numeric,     -- suma del consumo del periodo (linea 2)
  m3_promedio       numeric,     -- suma de los promedios de 6 periodos (null si no hay historial)
  contratos_cero_6m bigint,      -- cero sostenido de 6 periodos (indicador aparte)
  primary key (periodo, ciclo, categoria, subcategoria, tipo_desviacion, grupo_umbral)
);
revoke all on bi.v_desviacion_dim from public, anon, authenticated;

create or replace function bi.recalcular_desviacion_dim(p_periodo text)
returns integer language plpgsql as $$
declare
  n   integer;
  per text[];   -- per[1] = periodo-1 ... per[6] = periodo-6
  x   text;
begin
  delete from bi.v_desviacion_dim where periodo = p_periodo;
  per := array(select to_char(to_date(p_periodo || '01', 'YYYYMMDD') - (k || ' month')::interval, 'YYYYMM')
               from generate_series(1, 6) k order by k);
  -- Sin el periodo o sin alguno de los 6 anteriores no hay calculo: 0 filas.
  if not exists (select 1 from hechos.facturacion_contratos where periodo = p_periodo) then
    return 0;
  end if;
  foreach x in array per loop
    if not exists (select 1 from hechos.facturacion_contratos where periodo = x) then
      return 0;
    end if;
  end loop;
  insert into bi.v_desviacion_dim
  with c as materialized (
    select periodo, contrato,
           coalesce(nullif(btrim(max(ciclo)), ''), '(sin ciclo)') ciclo,
           coalesce(nullif(btrim(max(categoria)), ''), '(sin uso)') categoria,
           coalesce(nullif(btrim(max(subcategoria)), ''), '(sin subcategoria)') subcategoria,
           sum(bi.f_num(consumo)) filter (where left(btrim(concepto), 2) = '2-') m3
    from hechos.facturacion_contratos
    where periodo = any (per || p_periodo::text)
    group by periodo, contrato),
  a as (
    select cur.contrato, cur.ciclo, cur.categoria, cur.subcategoria,
           (cur.m3 is null) cur_cero, coalesce(cur.m3, 0) cons,
           count(h.periodo) n_prev,
           coalesce(sum(coalesce(h.m3, 0)), 0) s6,
           count(h.periodo) filter (where h.periodo = any ((per)[1:5])) ex5,
           count(h.periodo) filter (where h.periodo = any ((per)[1:5]) and h.m3 is null) zr5
    from c cur
    left join c h on h.contrato = cur.contrato and h.periodo = any (per)
    where cur.periodo = p_periodo
    group by cur.contrato, cur.ciclo, cur.categoria, cur.subcategoria, cur.m3),
  k as (
    select *,
      case when n_prev < 6 then 'sin_historial'
           when s6 = 0 then (case when cons > 0 then 'sin_promedio' else 'sin_desviacion' end)
           when cons * 6 - s6 >  (case when s6 >= 240 then 0.35 else 0.65 end) * s6 then 'positiva'
           when cons * 6 - s6 < -(case when s6 >= 240 then 0.35 else 0.65 end) * s6 then 'negativa'
           else 'sin_desviacion' end tipo,
      case when n_prev < 6 or s6 = 0 then 'sin_umbral' when s6 >= 240 then 'ge40' else 'lt40' end grupo
    from a)
  select p_periodo::text as periodo, ciclo, categoria, subcategoria,
         tipo as tipo_desviacion, grupo as grupo_umbral,
         count(*) as contratos,
         sum(cons) as m3_periodo,
         sum(s6 / 6.0) filter (where n_prev = 6) as m3_promedio,
         count(*) filter (where cur_cero and ex5 = 5 and zr5 = 5) as contratos_cero_6m
  from k group by ciclo, categoria, subcategoria, tipo, grupo;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_desviacion_dim(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X)
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular_desviacion_dim('202608');  select bi.recalcular_desviacion_dim('202609');

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) = contratos distintos del periodo en facturacion_contratos;
--   positiva + negativa + sin_desviacion + sin_historial + sin_promedio = total;
--   sum(m3_periodo) = suma de la linea 2; EXCEPT en ambos sentidos contra la
--   consulta de referencia; ACL igual a la de v_consumo_ciclo_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_desviacion_dim) desde sql/26_consumo_ciclo_dim.sql / 25
-- drop function bi.recalcular_desviacion_dim(text);
-- drop table bi.v_desviacion_dim;
