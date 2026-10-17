-- =====================================================================
-- 46_cartera_pago_dim.sql · Pagos y mora de la cartera: contratos y saldo por uso, estrato, mora, antiguedad del ultimo pago y cobertura
-- ---------------------------------------------------------------------
-- Alimenta la zona "Pagos y mora" de Cartera desagregada (Fase B). Fuente: hechos.cartera_contrato (UNA fila por contrato del periodo tras
-- agrupar por contrato; sin sumar productos dos veces). El universo es TODO contrato del periodo, tenga o no deuda.
--
-- GRANO: periodo x uso x estrato x mora x banda_fecha x banda_cobertura -> contratos y saldo (pesos). ~410 filas por periodo (~3.300 en 8).
--  · mora (facturas vencidas, maximo por contrato): 'sin_deuda' (total_cartera vacio o <= 0), 'al_dia' (con deuda y 0 vencidas, casi todo
--    cartera financiada), 'v1_2', 'v3_8', 'v9_24', 'v_mas24'; 'agrupada' (celdas de menos de 5 contratos, ver abajo).
--  · banda_fecha (antiguedad de fecha_ult_pago frente al ULTIMO DIA del periodo): 'd31' (ultimos 31 dias; incluye las pocas fechas posteriores
--    al corte), 'm1_3' (hasta 92 dias), 'm3_12' (hasta 365 dias), 'm_mas12', 'sin_pago' (fecha vacia); 'agrupada'.
--    La fecha viene como ISO ('2026-09-05 00:00:00') salvo 202603, donde TODA la columna esta guardada como numero serial de Excel (NNNNN.0);
--    la funcion convierte ambos formatos (serial: 1899-12-30 + dias) y no modifica el dato crudo.
--  · banda_cobertura = ultimo_pago / total_cartera del contrato: 'lt5' (< 5 %), 'r5_25', 'r25_100', 'ge100' (>= 100 %), 'sin_pago' (con saldo y sin
--    ultimo pago), 'sin_saldo' (sin deuda; no aplica); 'agrupada'. Denominador = total_cartera (incluye lo financiado); ultimo_pago es el valor
--    del ultimo pago registrado del contrato.
--  · uso: '1','3','5','9' u 'otros'; estrato: '1' a '6' u 'otros'. saldo = suma de total_cartera de los contratos de la celda (pesos).
-- MINIMO 5 (privacidad): (1) por (uso, estrato): si el grupo tiene menos de 5 contratos del periodo, o el uso o el estrato no son de la lista, va a
--    'otros'. (2) POR CELDA: esta dimension publica CONTEOS, y una celda de 1 a 4 contratos mostraria el saldo de una sola persona; por eso las celdas
--    con menos de 5 contratos se funden en 4 pasos, siempre con las mismas sumas: primero banda_cobertura='agrupada'; las que aun tienen menos de 5,
--    tambien banda_fecha='agrupada'; luego mora='agrupada'; y lo que quede, uso/estrato 'otros'. Ninguna celda publicada tiene menos de 5 contratos.
--    Los contratos de celdas pequenas quedan en celdas 'agrupada'. La supresion complementaria sigue apagada (decision de David).
-- Sin contrato, barrio ni ciclo. SIN seguridad por filas (como sql/45) y con REVOKE a anon, authenticated y PUBLIC.
-- Cuadre: sum(contratos) = contratos distintos de cartera_contrato y sum(saldo) = sum(total_cartera), en los 8 periodos (202602 a 202609, 202606 incluido).
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) Edge v27   4) rama 61 de la RPC   5) carga   6) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------

create table bi.v_cartera_pago_dim (
  periodo          text,
  uso              text,
  estrato          text,
  mora             text,
  banda_fecha      text,
  banda_cobertura  text,
  contratos        bigint,
  saldo            numeric,
  primary key (periodo, uso, estrato, mora, banda_fecha, banda_cobertura)
);
revoke all on bi.v_cartera_pago_dim from public, anon, authenticated;
-- Sin seguridad por filas, como sus hermanas (el entorno la activa al crear la tabla; sin politicas, claude_ro veria 0 filas).
alter table bi.v_cartera_pago_dim disable row level security;

create or replace function bi.recalcular_cartera_pago(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cartera_pago_dim where periodo = p_periodo;
  insert into bi.v_cartera_pago_dim
  with c as (
    select trim(contrato) as k,
           coalesce(substring(btrim(max(uso)) from '^-?\d+'), '(sin dato)') as uso_cod,
           coalesce(substring(btrim(max(estrato)) from '^-?\d+'), '(sin dato)') as est_cod,
           sum(bi.f_num(total_cartera)) as tot,
           max(bi.f_num(facturas_vencidas)) as fv,
           max(case when fecha_ult_pago ~ '^[0-9]+(\.[0-9]+)?$' then date '1899-12-30' + floor(fecha_ult_pago::numeric)::int
                    when fecha_ult_pago ~ '^[0-9]{4}-' then left(fecha_ult_pago, 10)::date end) as f,
           max(bi.f_num(ultimo_pago)) as up
    from hechos.cartera_contrato where periodo = p_periodo group by 1),
  x as (
    select c.k, c.uso_cod, c.est_cod,
           case when coalesce(tot, 0) <= 0 then 'sin_deuda' when coalesce(fv, 0) = 0 then 'al_dia' when fv <= 2 then 'v1_2'
                when fv <= 8 then 'v3_8' when fv <= 24 then 'v9_24' else 'v_mas24' end as mora,
           case when f is null then 'sin_pago' when f > corte - 31 then 'd31' when f > corte - 92 then 'm1_3'
                when f > corte - 365 then 'm3_12' else 'm_mas12' end as bfecha,
           case when coalesce(tot, 0) <= 0 then 'sin_saldo' when up is null then 'sin_pago' when up / tot < 0.05 then 'lt5'
                when up / tot < 0.25 then 'r5_25' when up / tot < 1 then 'r25_100' else 'ge100' end as bcob,
           coalesce(tot, 0) as saldo
    from c cross join (select (to_date(p_periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date as corte) z),
  g as (select uso_cod, est_cod, count(*) as n from x group by 1, 2),
  y as (
    select x.k, x.mora, x.bfecha, x.bcob, x.saldo,
           case when g.n >= 5 and x.uso_cod in ('1', '3', '5', '9') then x.uso_cod else 'otros' end as uso,
           case when g.n >= 5 and x.est_cod in ('1', '2', '3', '4', '5', '6') then x.est_cod else 'otros' end as estrato
    from x join g using (uso_cod, est_cod)),
  c0 as (select uso, estrato, mora, bfecha, bcob, count(*) as n from y group by 1, 2, 3, 4, 5),
  l0 as (select y.* from y join c0 using (uso, estrato, mora, bfecha, bcob) where c0.n >= 5),
  r1 as (select y.k, y.uso, y.estrato, y.mora, y.bfecha, 'agrupada'::text as bcob, y.saldo
         from y join c0 using (uso, estrato, mora, bfecha, bcob) where c0.n < 5),
  c1 as (select uso, estrato, mora, bfecha, bcob, count(*) as n from r1 group by 1, 2, 3, 4, 5),
  l1 as (select r1.* from r1 join c1 using (uso, estrato, mora, bfecha, bcob) where c1.n >= 5),
  r2 as (select r1.k, r1.uso, r1.estrato, r1.mora, 'agrupada'::text as bfecha, r1.bcob, r1.saldo
         from r1 join c1 using (uso, estrato, mora, bfecha, bcob) where c1.n < 5),
  c2 as (select uso, estrato, mora, bfecha, bcob, count(*) as n from r2 group by 1, 2, 3, 4, 5),
  l2 as (select r2.* from r2 join c2 using (uso, estrato, mora, bfecha, bcob) where c2.n >= 5),
  r3 as (select r2.k, r2.uso, r2.estrato, 'agrupada'::text as mora, r2.bfecha, r2.bcob, r2.saldo
         from r2 join c2 using (uso, estrato, mora, bfecha, bcob) where c2.n < 5),
  c3 as (select uso, estrato, mora, bfecha, bcob, count(*) as n from r3 group by 1, 2, 3, 4, 5),
  l3 as (select r3.* from r3 join c3 using (uso, estrato, mora, bfecha, bcob) where c3.n >= 5),
  l4 as (select r3.k, 'otros'::text as uso, 'otros'::text as estrato, r3.mora, r3.bfecha, r3.bcob, r3.saldo
         from r3 join c3 using (uso, estrato, mora, bfecha, bcob) where c3.n < 5),
  todo as (
    select uso, estrato, mora, bfecha, bcob, saldo from l0 union all select uso, estrato, mora, bfecha, bcob, saldo from l1
    union all select uso, estrato, mora, bfecha, bcob, saldo from l2 union all select uso, estrato, mora, bfecha, bcob, saldo from l3
    union all select uso, estrato, mora, bfecha, bcob, saldo from l4)
  select p_periodo as periodo, uso, estrato, mora, bfecha as banda_fecha, bcob as banda_cobertura,
         count(*) as contratos, sum(saldo) as saldo
  from todo group by 2, 3, 4, 5, 6
  ;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cartera_pago(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X; texto tomado de la funcion VIVA, que ya incluye la rama de bi.v_cartera_edad_dim)
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
  elsif p_tabla = 'bi.v_recaudo_subsidio_dim' then n := bi.recalcular_recaudo_subsidio_dim(p_periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then n := bi.recalcular_notas_causal_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then n := bi.recalcular_recaudo_entidad_dim(p_periodo);
  elsif p_tabla = 'bi.v_cambio_medidor_dim' then n := bi.recalcular_cambio_medidor(p_periodo);
  elsif p_tabla in ('bi.v_submedicion_ref_dim', 'bi.v_submedicion_ciclo_dim', 'bi.v_submedicion_rango_dim') then n := bi.recalcular_submedicion(p_periodo);
  elsif p_tabla = 'bi.v_reclamo_metodo_dim' then n := bi.recalcular_reclamo_metodo(p_periodo);
  elsif p_tabla in ('bi.v_reclamo_metodo_banda_dim', 'bi.v_reclamo_metodo_ciclo_dim') then n := bi.recalcular_reclamo_metodo_resumen(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_ticket_dim' then n := bi.recalcular_recaudo_ticket_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_cuadre_dim' then n := bi.recalcular_recaudo_cuadre_dim(p_periodo);
  elsif p_tabla in ('bi.v_mapa_calor_dim', 'bi.v_mapa_calor_cobertura_dim', 'bi.v_mapa_calor_cartera_dim') then n := bi.recalcular_mapa_calor(p_periodo);
  elsif p_tabla = 'bi.v_cartera_edad_dim' then n := bi.recalcular_cartera_edad(p_periodo);
  elsif p_tabla = 'bi.v_cartera_pago_dim' then n := bi.recalcular_cartera_pago(p_periodo);
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
  elsif p_tabla = 'bi.v_recaudo_subsidio_dim' then
    delete from bi.v_recaudo_subsidio_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then
    delete from bi.v_notas_causal_dim t
    where not exists (select 1 from hechos.notas f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then
    delete from bi.v_recaudo_entidad_dim t
    where not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_ticket_dim' then
    delete from bi.v_recaudo_ticket_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_cuadre_dim' then
    delete from bi.v_recaudo_cuadre_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo)
      and not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo)
      and not exists (select 1 from hechos.recaudo_agrupado f where f.periodo = t.periodo);
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
  elsif p_tabla in ('bi.v_mapa_calor_dim', 'bi.v_mapa_calor_cobertura_dim', 'bi.v_mapa_calor_cartera_dim') then
    delete from bi.v_mapa_calor_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_mapa_calor_cobertura_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_mapa_calor_cartera_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_edad_dim' then
    delete from bi.v_cartera_edad_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_pago_dim' then
    delete from bi.v_cartera_pago_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 y 4 · Edge v27 y rama 61 de la RPC -----------------------------
-- Edge (geoportal-web): agregar "v_cartera_pago_dim" a VISTAS_PERMITIDAS y desplegar (v27). Va ANTES de la RPC.
-- sql/05 queda IGUAL A LO VIVO (60 ramas) hasta aplicar; al aplicar se agrega esta rama y se ejecuta la funcion completa (create or replace
-- conserva el ACL: EXECUTE solo para postgres y service_role). Rama, antes del 'else raise exception':
--
--   elsif p_vista = 'v_cartera_pago_dim' then
--     select coalesce(jsonb_agg(to_jsonb(t) order by t.uso, t.estrato, t.mora, t.banda_fecha, t.banda_cobertura), '[]'::jsonb)
--       into resultado
--     from bi.v_cartera_pago_dim t
--     where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
--       and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
--       and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

-- >>> PASO 5 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_cartera_pago_dim', 'AAAAMM');  -- 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609
-- (cada uno en su transaccion con begin; set local statement_timeout='300s'; ... commit;)

-- >>> PASO 6 · controles ------------------------------------------------
-- (los mismos estan en VISTAS_TABLERO de cargar_hechos.py y en el script de controles del paquete)
--   a) sum(contratos) = contratos distintos de cartera_contrato y sum(saldo) = sum(total_cartera), por periodo.
--   b) ninguna celda con menos de 5 contratos; uso y estrato en listas cerradas.
--   c) por mora: ningun conteo de la dimension supera al de la fuente, y (fuente - dimension) = lo que quedo en mora 'agrupada'.
--   d) 202609: los conteos y saldos por mora, antiguedad del ultimo pago y cobertura cuadran con la clasificacion directa sobre cartera_contrato
--      (los valores se verifican al aplicar; no se versionan aqui).
--   e) ACL igual a la de v_cartera_detalle_dim; sin RLS.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia; los scripts estan fuera del repo, en el paquete):
--   RPC:         ROLLBACK_geoportal_bi_consulta_60ramas.sql, tras quitar la vista de la Edge (v26).
--   Despachador: ROLLBACK_recalcular_antes_cartera_pago.sql.
--   drop function bi.recalcular_cartera_pago(text);
--   drop table bi.v_cartera_pago_dim;
