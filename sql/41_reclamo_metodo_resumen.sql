-- =====================================================================
-- 41_reclamo_metodo_resumen.sql · Resumen de reclamos segun el metodo de facturacion (para la pantalla)
-- ---------------------------------------------------------------------
-- La tabla bi.v_reclamo_metodo_dim (sql/40) pesa 1,6 a 1,8 MB por periodo desde 202605 (8,6 MB los siete), demasiado para que la
-- pantalla la cargue. Estas dos tablas resumen se calculan SUMANDO esa tabla fuente, que queda sin cambios:
--  · bi.v_reclamo_metodo_banda_dim (A, sin ciclo): periodo x metodo_ant x metodo_act x banda_antig x estrato x uso.
--  · bi.v_reclamo_metodo_ciclo_dim (B): periodo x ciclo x metodo_act.
-- Mismas medidas que la fuente (contratos, solicitudes de consumo / promedio / medidor / otras / desocupado / cartera /
-- administrativas, contratos_con_reclamo, contratos_con_rec_consumo_prom y calculado_en = el mas reciente de la fuente). Se conserva
-- la fila 'Sin base' (contratos = 0) para que el total de solicitudes del periodo cuadre con hechos.reclamos.
-- Un solo recalculo (bi.recalcular_reclamo_metodo_resumen) llena las dos; debe correr DESPUES de bi.v_reclamo_metodo_dim
-- (el cargador lo ordena asi con "despues_de"). Cuesta menos de 1 s por periodo. Sin DROP ni TRUNCATE.
-- ROLLBACK: delete de las dos tablas; las tablas y la funcion se pueden dejar.
-- =====================================================================

-- >>> PASO 1 · tablas, funcion, permisos --------------------------------
create table bi.v_reclamo_metodo_banda_dim (
  periodo                         text,
  metodo_ant                      text,
  metodo_act                      text,
  banda_antig                     text,
  estrato                         text,
  uso                             text,
  contratos                       bigint,
  solicitudes_consumo             bigint,
  solicitudes_promedio            bigint,
  solicitudes_medidor             bigint,
  solicitudes_otras               bigint,
  solicitudes_desocupado          bigint,
  solicitudes_cartera             bigint,
  solicitudes_admin               bigint,
  contratos_con_reclamo           bigint,
  contratos_con_rec_consumo_prom  bigint,
  calculado_en                    timestamptz,
  primary key (periodo, metodo_ant, metodo_act, banda_antig, estrato, uso)
);
revoke all on bi.v_reclamo_metodo_banda_dim from public, anon, authenticated;

create table bi.v_reclamo_metodo_ciclo_dim (
  periodo                         text,
  ciclo                           text,
  metodo_act                      text,
  contratos                       bigint,
  solicitudes_consumo             bigint,
  solicitudes_promedio            bigint,
  solicitudes_medidor             bigint,
  solicitudes_otras               bigint,
  solicitudes_desocupado          bigint,
  solicitudes_cartera             bigint,
  solicitudes_admin               bigint,
  contratos_con_reclamo           bigint,
  contratos_con_rec_consumo_prom  bigint,
  calculado_en                    timestamptz,
  primary key (periodo, ciclo, metodo_act)
);
revoke all on bi.v_reclamo_metodo_ciclo_dim from public, anon, authenticated;

create or replace function bi.recalcular_reclamo_metodo_resumen(p_periodo text)
returns integer language plpgsql as $$
declare
  n1 integer;
  n2 integer;
begin
  delete from bi.v_reclamo_metodo_banda_dim where periodo = p_periodo;
  delete from bi.v_reclamo_metodo_ciclo_dim where periodo = p_periodo;
  if not exists (select 1 from bi.v_reclamo_metodo_dim where periodo = p_periodo) then
    return 0;   -- la fuente no tiene el periodo (se calcula primero bi.v_reclamo_metodo_dim)
  end if;
  insert into bi.v_reclamo_metodo_banda_dim
  select periodo, metodo_ant, metodo_act, banda_antig, estrato, uso,
           sum(contratos), sum(solicitudes_consumo), sum(solicitudes_promedio), sum(solicitudes_medidor), sum(solicitudes_otras),
           sum(solicitudes_desocupado), sum(solicitudes_cartera), sum(solicitudes_admin), sum(contratos_con_reclamo),
           sum(contratos_con_rec_consumo_prom), max(calculado_en)
  from bi.v_reclamo_metodo_dim where periodo = p_periodo
  group by periodo, metodo_ant, metodo_act, banda_antig, estrato, uso;
  get diagnostics n1 = row_count;
  insert into bi.v_reclamo_metodo_ciclo_dim
  select periodo, ciclo, metodo_act,
           sum(contratos), sum(solicitudes_consumo), sum(solicitudes_promedio), sum(solicitudes_medidor), sum(solicitudes_otras),
           sum(solicitudes_desocupado), sum(solicitudes_cartera), sum(solicitudes_admin), sum(contratos_con_reclamo),
           sum(contratos_con_rec_consumo_prom), max(calculado_en)
  from bi.v_reclamo_metodo_dim where periodo = p_periodo
  group by periodo, ciclo, metodo_act;
  get diagnostics n2 = row_count;
  return n1 + n2;
end $$;
revoke all on function bi.recalcular_reclamo_metodo_resumen(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama (las dos tablas se llenan juntas) y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X). OJO: este texto es la copia PUBLICADA del despachador mas la rama nueva; el
-- despachador VIVO de la base tiene ramas adicionales (piezas no publicadas) y por eso se aplico tomando su definicion viva e
-- insertando solo las lineas nuevas, NO ejecutando este bloque tal cual.
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
  elsif p_tabla = 'bi.v_cambio_medidor_dim' then n := bi.recalcular_cambio_medidor(p_periodo);
  elsif p_tabla in ('bi.v_submedicion_ref_dim', 'bi.v_submedicion_ciclo_dim', 'bi.v_submedicion_rango_dim') then n := bi.recalcular_submedicion(p_periodo);
  elsif p_tabla = 'bi.v_reclamo_metodo_dim' then n := bi.recalcular_reclamo_metodo(p_periodo);
  elsif p_tabla in ('bi.v_reclamo_metodo_banda_dim', 'bi.v_reclamo_metodo_ciclo_dim') then n := bi.recalcular_reclamo_metodo_resumen(p_periodo);
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
  elsif p_tabla = 'bi.v_cambio_medidor_dim' then
    delete from bi.v_cambio_medidor_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_submedicion_ref_dim', 'bi.v_submedicion_ciclo_dim', 'bi.v_submedicion_rango_dim') then
    delete from bi.v_submedicion_ref_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_submedicion_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_submedicion_rango_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_reclamo_metodo_dim' then
    delete from bi.v_reclamo_metodo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_reclamo_metodo_banda_dim', 'bi.v_reclamo_metodo_ciclo_dim') then
    delete from bi.v_reclamo_metodo_banda_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_reclamo_metodo_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
-- Un periodo por vez, DESPUES de bi.v_reclamo_metodo_dim:
--   begin; select bi.recalcular('bi.v_reclamo_metodo_banda_dim', '202602'); commit;
-- Periodos: 202602, 202603, 202604, 202605, 202607, 202608 y 202609.

-- >>> PASO 4 · controles ------------------------------------------------
--   EXCEPT en ambos sentidos, periodo por periodo, contra una referencia que agrega directamente desde la fuente (con otro
--   metodo de agregacion). Contratos y solicitudes por periodo iguales entre la fuente, A y B; el total de solicitudes coincide con
--   las solicitudes distintas de hechos.reclamos (623, 628, 517, 563, 558, 533 y 595).
