-- =====================================================================
-- 35_recaudo_edad_dim.sql · Recaudo segun la edad de la deuda recaudada, por servicio (T3)
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Corriente frente a rezagado" de Recaudo desagregada. Fuente:
-- hechos.recaudo_agrupado (recaudo por concepto y por edad de la cartera recaudada) y
-- bi.v_concepto_mapa (servicio de cada concepto, desde bi.conceptos_ruta). No usa clasificacion de
-- contrato (el archivo agrupado no trae ciclo ni uso).
--
-- GRANO: periodo x tramo de edad x servicio.
--  · tramo: '0', '30', '60', '90', '120', '150', '180', '210', '240', '270', '300', '330', '360' y
--    '>360' (dias de la cartera recaudada; 0 y 30 = recaudo corriente). `orden` (0 a 13) sirve para
--    ordenar.
--  · servicio: 'Acueducto', 'Alcantarillado' y 'Otros'. Decision: el servicio PLUVIAL de
--    bi.v_concepto_mapa (2 conceptos) se cuenta en 'Alcantarillado'; TERCERO y OTROS en 'Otros'.
--  · recaudo = suma del tramo para los conceptos del servicio; conceptos = conceptos con valor.
--  · Periodos: todos los de recaudo_agrupado (202301 a 202609, 45).
--  · Los 14 tramos suman exactamente recaudo_total en todos los periodos (verificado).
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

create table bi.v_recaudo_edad_dim (
  periodo   text,
  tramo     text,
  orden     integer,
  servicio  text,
  recaudo   numeric,
  conceptos bigint,
  primary key (periodo, tramo, servicio)
);
revoke all on bi.v_recaudo_edad_dim from public, anon, authenticated;

create or replace function bi.recalcular_recaudo_edad_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_recaudo_edad_dim where periodo = p_periodo;
  insert into bi.v_recaudo_edad_dim
  with a as materialized (
    select case when m.servicio = 'ACUEDUCTO' then 'Acueducto'
                when m.servicio in ('ALCANTARILLADO', 'PLUVIAL') then 'Alcantarillado'
                else 'Otros' end as servicio,
           bi.f_num(r.rec_0) t0, bi.f_num(r.rec_30) t30, bi.f_num(r.rec_60) t60, bi.f_num(r.rec_90) t90,
           bi.f_num(r.rec_120) t120, bi.f_num(r.rec_150) t150, bi.f_num(r.rec_180) t180,
           bi.f_num(r.rec_210) t210, bi.f_num(r.rec_240) t240, bi.f_num(r.rec_270) t270,
           bi.f_num(r.rec_300) t300, bi.f_num(r.rec_330) t330, bi.f_num(r.rec_360) t360,
           bi.f_num(r.rec_may360) tmay
    from hechos.recaudo_agrupado r
    left join bi.v_concepto_mapa m on m.concepto_num::text = btrim(r.id_concepto)
    where r.periodo = p_periodo),
  u as (
    select a.servicio, v.orden, v.tramo, v.valor
    from a cross join lateral (values
      (0, '0', a.t0), (1, '30', a.t30), (2, '60', a.t60), (3, '90', a.t90), (4, '120', a.t120),
      (5, '150', a.t150), (6, '180', a.t180), (7, '210', a.t210), (8, '240', a.t240),
      (9, '270', a.t270), (10, '300', a.t300), (11, '330', a.t330), (12, '360', a.t360),
      (13, '>360', a.tmay)) as v(orden, tramo, valor))
  select p_periodo, tramo, orden, servicio, coalesce(sum(valor), 0),
         count(*) filter (where coalesce(valor, 0) <> 0)
  from u group by tramo, orden, servicio;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_recaudo_edad_dim(text) from public, anon, authenticated;

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
  elsif p_tabla = 'bi.v_recaudo_edad_dim' then n := bi.recalcular_recaudo_edad_dim(p_periodo);
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_recaudo_edad_dim', 'AAAAMM');  -- periodos: 202301, 202302, 202303, 202304, 202305, 202306, 202307, 202308, 202309, 202310, 202311, 202312, 202401, 202402, 202403, 202404, 202405, 202406, 202407, 202408, 202409, 202410, 202411, 202412, 202501, 202502, 202503, 202504, 202505, 202506, 202507, 202508, 202509, 202510, 202511, 202512, 202601, 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(recaudo) = sum(recaudo_total) de recaudo_agrupado en cada periodo; corriente (0 + 30) =
--   87,0 % en 202609; EXCEPT en ambos sentidos contra una consulta de referencia independiente
--   (el servicio sale de conceptos_ruta.ruta_efectiva y no de v_concepto_mapa; el pivote es union
--   all) en los 45 periodos; ACL igual a la de v_observacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador anterior
--   (sin la rama bi.v_recaudo_edad_dim) desde el archivo sql anterior
-- drop function bi.recalcular_recaudo_edad_dim(text);

-- drop table bi.v_recaudo_edad_dim;
