-- =====================================================================
-- 33_recaudo_eficiencia_dim.sql · Eficiencia de recaudo por ciclo, categoria y subcategoria (R1)
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Eficiencia de recaudo" de Recaudo desagregada: recaudo frente a facturado
-- por ciclo, uso y estrato, y los contratos que pagan una vez o dos o mas veces.
-- Fuentes: hechos.facturacion_contratos (facturado), hechos.recaudo_detalle (recaudo neto),
-- hechos.cupones_pagos (numero de pagos = cupones) y hechos.cartera_contrato (clasificacion).
--
-- GRANO: periodo x ciclo x categoria x subcategoria.
--  · contratos_facturados / facturado: contratos con lineas en facturacion_contratos del periodo y
--    la suma de su 'facturado' (6.192,49 M y 111.859 contratos en 202609).
--  · contratos_pagadores / recaudo_neto: contratos con lineas en recaudo_detalle y la suma de
--    valor_recaudo (neto de subsidios aplicados): 74.177 y 5.182,70 M en 202609.
--  · contratos_pago_1: pagadores con un solo pago (cupon) en el mes; contratos_pago_2mas: con dos
--    o mas, y recaudo_pago_2mas su recaudo. Un pagador sin cupon cuenta como de un pago.
--  · Un contrato que paga pero no fue facturado en el periodo (1 en 202609) suma pagador sin
--    facturado en su celda.
--  · Periodos: los que existen en recaudo_detalle Y en la fuente de clasificacion: 202602 a 202605
--    y 202607 a 202609 (202601 no tiene cartera_contrato; 202606 no tiene recaudo_detalle).
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
create or replace function bi.f_clasificacion_contrato(p_periodo text)
returns table (contrato text, ciclo text, categoria text, subcategoria text)
language sql stable as $$
  select distinct on (c.contrato)
         c.contrato,
         case when nullif(regexp_replace(btrim(coalesce(c.ciclo, '')), '\D', '', 'g'), '') is null
                   or regexp_replace(btrim(c.ciclo), '\D', '', 'g')::int >= 9000 then '(sin ciclo)'
              else (regexp_replace(btrim(c.ciclo), '\D', '', 'g'))::int::text end,
         case when btrim(regexp_replace(btrim(coalesce(c.uso, '')), '^-?\d+\s*-?\s*', '')) !~ '[A-Za-z0-9]'
                   or upper(btrim(regexp_replace(btrim(c.uso), '^-?\d+\s*-?\s*', ''))) = 'NULO' then '(sin dato)'
              else btrim(regexp_replace(btrim(c.uso), '^-?\d+\s*-?\s*', '')) end,
         case when btrim(regexp_replace(btrim(coalesce(c.estrato, '')), '^-?\d+\s*-?\s*', '')) !~ '[A-Za-z0-9]'
                   or upper(btrim(regexp_replace(btrim(c.estrato), '^-?\d+\s*-?\s*', ''))) = 'NULO' then '(sin dato)'
              else btrim(regexp_replace(btrim(c.estrato), '^-?\d+\s*-?\s*', '')) end
  from hechos.cartera_contrato c
  where c.periodo = p_periodo
  order by c.contrato, c.ciclo, c.uso, c.estrato
$$;
revoke all on function bi.f_clasificacion_contrato(text) from public, anon, authenticated;
create table bi.v_recaudo_eficiencia_dim (
  periodo              text,
  ciclo                text,
  categoria            text,
  subcategoria         text,
  contratos_facturados bigint,
  facturado            numeric,
  contratos_pagadores  bigint,
  recaudo_neto         numeric,
  contratos_pago_1     bigint,
  contratos_pago_2mas  bigint,
  recaudo_pago_2mas    numeric,
  primary key (periodo, ciclo, categoria, subcategoria)
);
revoke all on bi.v_recaudo_eficiencia_dim from public, anon, authenticated;

create or replace function bi.recalcular_recaudo_eficiencia_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);   -- planes con el periodo conocido (el plan generico elige bucles anidados y no termina)
  perform set_config('enable_nestloop', 'off', true);   -- los cruces con la clasificacion son hash: evita un plan de bucles anidados que no termina
  delete from bi.v_recaudo_eficiencia_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.cartera_contrato where periodo = p_periodo) then
    return 0;   -- sin clasificacion no hay tabla (202601)
  end if;
  insert into bi.v_recaudo_eficiencia_dim
  with cl as materialized (select * from bi.f_clasificacion_contrato(p_periodo)),
  fa as materialized (
    select contrato, sum(bi.f_num(facturado)) as fact
    from hechos.facturacion_contratos where periodo = p_periodo group by contrato),
  rc as materialized (
    select contrato, sum(bi.f_num(valor_recaudo)) as rec
    from hechos.recaudo_detalle where periodo = p_periodo group by contrato),
  cu as materialized (
    select contrato, count(*) as pagos
    from hechos.cupones_pagos where periodo = p_periodo group by contrato),
  c as materialized (
    select coalesce(fa.contrato, rc.contrato) as contrato, fa.fact, rc.rec, cu.pagos
    from fa full join rc on rc.contrato = fa.contrato
    left join cu on cu.contrato = coalesce(fa.contrato, rc.contrato)),
  f as (
    select coalesce(cl.ciclo, '(sin ciclo)') as ciclo,
           coalesce(cl.categoria, '(sin dato)') as categoria,
           coalesce(cl.subcategoria, '(sin dato)') as subcategoria,
           count(*) filter (where c.fact is not null) as cf,
           sum(c.fact) as fact,
           count(*) filter (where c.rec is not null) as cp,
           sum(c.rec) as rec,
           count(*) filter (where c.rec is not null and coalesce(c.pagos, 0) <= 1) as p1,
           count(*) filter (where c.pagos >= 2) as p2,
           sum(c.rec) filter (where c.pagos >= 2) as rec2
    from c left join cl on cl.contrato = c.contrato
    group by 1, 2, 3),
  g as (
    select case when cf < 5 or cp between 1 and 4 then '(Otros)' else ciclo end as ciclo,
           case when cf < 5 or cp between 1 and 4 then '(Otros)' else categoria end as categoria,
           case when cf < 5 or cp between 1 and 4 then '(Otros)' else subcategoria end as subcategoria,
           cf, fact, cp, rec, p1, p2, rec2
    from f)
  select p_periodo, ciclo, categoria, subcategoria,
         sum(cf), sum(fact), sum(cp), sum(rec), sum(p1), sum(p2), sum(rec2)
  from g group by ciclo, categoria, subcategoria;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_recaudo_eficiencia_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_recaudo_eficiencia_dim', 'AAAAMM');  -- periodos: 202602, 202603, 202604, 202605, 202607, 202608, 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos_facturados) = contratos distintos de facturacion_contratos del periodo (111.859 en
--   202609); sum(facturado) = suma de facturacion_contratos (6.192,49 M); sum(contratos_pagadores) =
--   contratos distintos de recaudo_detalle (74.177); sum(recaudo_neto) = suma de recaudo_detalle
--   (5.182,70 M); pago_1 + pago_2mas = pagadores; EXCEPT en ambos sentidos contra una consulta de
--   referencia independiente (row_number y split_part en lugar de distinct on y expresiones
--   regulares) en los 7 periodos, uno por uno; ACL igual a la de v_observacion_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador anterior
--   (sin la rama bi.v_recaudo_eficiencia_dim) desde el archivo sql anterior
-- drop function bi.recalcular_recaudo_eficiencia_dim(text);
-- drop function bi.f_clasificacion_contrato(text);  -- solo si ninguna otra tabla la usa
-- drop table bi.v_recaudo_eficiencia_dim;

-- =====================================================================
-- NOTA DE CARGA (cargar_hechos.py): el cargador recalcula esta dim con
--   begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- dentro de una transaccion real. ESA RUTA (SET LOCAL desde el cargador) AUN NO SE HA EJECUTADO EN UNA CARGA REAL.
-- Si falla, se recalcula a mano con exactamente esa secuencia, un periodo por vez.
-- =====================================================================
