-- =====================================================================
-- 29_observacion_dim.sql · Observacion de lectura por categoria, estrato y ciclo
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Lectura" de Facturacion detallado (observacion de
-- lectura) y, sumada a nivel empresa, las causales de observacion de Perdidas.
-- Fuente: hechos.consumo_metodo, SOLO la columna observacion (el metodo de
-- consumo NO se toma de funcion ni de metodo_calculo). Patron de sql/24 a 28.
--
-- GRANO: periodo x categoria x subcategoria x ciclo x observacion x
--        con_medidor x resultado_lectura   (~1.400 filas por periodo con ciclo;
--        1.212 a 1.403 en los 8 periodos cargados: no hace falta partirla).
--  · observacion: texto normalizado (espacios repetidos o sobrantes fuera,
--    mayusculas): '99 USUARIO CON LECTURA', '11 CONEXIÓN DIRECTA'. Observacion
--    vacia = 'Sin medidor' (son exactamente los contratos sin medidor).
--  · codigo_observacion: el numero inicial de la observacion (1, 8, 11, 99...),
--    columna aparte para ordenar; NULL en 'Sin medidor'. Se deriva del texto,
--    por eso no forma parte de la llave.
--  · categoria / subcategoria: sin el codigo numerico inicial ('1 Residencial'
--    -> 'Residencial', '1 ESTRATO 1' -> 'ESTRATO 1'), igual que
--    bi.v_consumo_ciclo_dim; vacios o 'NULO' -> '(sin dato)'.
--  · con_medidor y resultado_lectura (avance | igual | menor | sin_lectura): con
--    las mismas reglas de sql/28.
--  · contratos = contratos DISTINTOS: se deja UNA fila por contrato (la que
--    tiene medidor, luego lectura, luego mayor consumo cobrado) antes de agrupar;
--    sum(contratos) = contratos distintos del periodo, sin aviso por duplicados
--    (1 o 2 por periodo, 16 en 202603).
--  · contratos_cero = contratos con consumo cobrado (consumo_cargos) = 0.
--
-- Periodos: 202601 a 202609 (no existe 202606 en la fuente).
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_observacion_dim (
  periodo            text,
  categoria          text,
  subcategoria       text,
  ciclo              text,
  observacion        text,
  codigo_observacion integer,
  con_medidor        boolean,
  resultado_lectura  text,
  contratos          bigint,
  contratos_cero     bigint,
  primary key (periodo, categoria, subcategoria, ciclo, observacion, con_medidor, resultado_lectura)
);
revoke all on bi.v_observacion_dim from public, anon, authenticated;

create or replace function bi.recalcular_observacion_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_observacion_dim where periodo = p_periodo;
  insert into bi.v_observacion_dim
  with u as materialized (
    select distinct on (contrato)
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as categoria,
           case when btrim(coalesce(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+','')) end as subcategoria,
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)') as ciclo,
           coalesce(nullif(upper(btrim(regexp_replace(observacion, '\s+', ' ', 'g'))), ''), 'Sin medidor') as observacion,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
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
  select p_periodo::text, categoria, subcategoria, ciclo, observacion,
         substring(observacion from '^(\d+)\s')::integer as codigo_observacion,
         con_medidor, resultado,
         count(*) as contratos,
         count(*) filter (where cero) as contratos_cero
  from u
  group by categoria, subcategoria, ciclo, observacion, con_medidor, resultado;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_observacion_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_observacion_dim', '2026MM');  -- 202601 a 202605 y 202607 a 202609

-- >>> PASO 4 · controles ------------------------------------------------
--   sum(contratos) = contratos distintos del periodo en consumo_metodo;
--   EXCEPT en ambos sentidos contra una consulta de referencia independiente
--   (row_number, limpieza de categoria evaluada sobre el resto sin el codigo)
--   en los 8 periodos; cifras de 202609 por observacion: 99 con lectura 88.425,
--   sin medidor 8.255 (8.256 filas: 1 duplicado), suministro no encontrado
--   7.781, conexion directa 4.187, predio enrejado con candado 946, vidrio
--   ilegible 645, medidor danado 532, conexion suspendida 468; ACL igual a la
--   de v_lectura_ciclo_dim.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_observacion_dim) desde sql/28_lectura_ciclo_dim.sql
-- drop function bi.recalcular_observacion_dim(text);
-- drop table bi.v_observacion_dim;
