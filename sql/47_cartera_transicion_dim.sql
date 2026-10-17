-- =====================================================================
-- 47_cartera_transicion_dim.sql · Movimiento de la mora: transiciones de los contratos entre periodos (Fase C)
-- ---------------------------------------------------------------------
-- Alimenta la zona «Movimiento de la mora» de Cartera. Fuente: hechos.cartera_contrato (una fila por contrato tras agrupar). Se construye ENCIMA de la
-- Fase B (sql/46): el despachador de este archivo incluye la rama de bi.v_cartera_pago_dim y la RPC lleva las ramas 61 (B) y 62.
--
-- GRANO: periodo (DESTINO) x referencia x uso x estrato x grupo_origen x grupo_destino -> contratos y saldos en pesos.
--  · referencia 'anterior': el periodo origen es el inmediatamente anterior de la fuente (202606 incluido: 202607 se compara con 202606).
--    referencia 'base': el origen es el PRIMER periodo de la fuente (hoy 202602); permite la cohorte de febrero en cualquier mes posterior.
--    Para el segundo periodo 'base' = 'anterior' y no se repite; el primer periodo no tiene filas.
--  · grupo de mora (facturas vencidas, maximo por contrato): 'sin_deuda' (total_cartera vacio o <= 0), 'al_dia' (con deuda y 0 vencidas, casi todo
--    cartera financiada), 'v1_2', 'v3_8', 'v9_24', 'v_mas24'. 'no_estaba' (solo en grupo_origen): el contrato no existe en el periodo origen.
--    'no_esta' (solo en grupo_destino): el contrato ya no existe en el periodo destino. 'agrupada': celdas pequenas (ver abajo).
--  · mora profunda = mas de 8 facturas vencidas = grupos 'v9_24' y 'v_mas24'. Entradas a la profunda: origen distinto de la profunda y destino en la
--    profunda; salidas: origen en la profunda y destino fuera de ella; permanencia: ambos en la profunda; paso a 'sin_deuda': destino 'sin_deuda'.
--  · uso y estrato del periodo DESTINO (o del origen si el contrato ya no existe). saldo_origen y saldo_destino = total_cartera del contrato en
--    cada periodo (0 si no estaba).
-- MINIMO 5 (privacidad): (1) por (uso, estrato): grupos con menos de 5 contratos, usos distintos de 1, 3, 5, 9 o estratos fuera de 1 a 6 van a 'otros'.
--    (2) POR CELDA (esta dimension publica conteos): las celdas con menos de 5 contratos se funden en 4 pasos, siempre con las mismas sumas:
--    estrato 'otros'; luego tambien uso 'otros'; luego grupo_destino 'agrupada'; y lo que quede, grupo_origen y grupo_destino 'agrupada'. Solo la ultima celda
--    (otros, otros, agrupada, agrupada) puede tener menos de 5 contratos; entonces se publica con contratos y saldos NULL (regla de «menos de 5 contratos»)
--    y se descuenta de los totales. La supresion complementaria sigue apagada (decision de David).
-- Sin contrato, barrio ni ciclo. SIN seguridad por filas y con REVOKE a anon, authenticated y PUBLIC.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funciones + revoke   2) despachador   3) Edge v28 y rama 62 de la RPC   4) carga   5) controles
-- =====================================================================

-- >>> PASO 1 (IDEMPOTENTE: se puede repetir tras un fallo parcial) · tabla, funciones, permisos --------------------------------

create table if not exists bi.v_cartera_transicion_dim (
  periodo          text,
  referencia       text,
  uso              text,
  estrato          text,
  grupo_origen     text,
  grupo_destino    text,
  contratos        bigint,
  saldo_origen     numeric,
  saldo_destino    numeric,
  primary key (periodo, referencia, uso, estrato, grupo_origen, grupo_destino)
);
revoke all on bi.v_cartera_transicion_dim from public, anon, authenticated;
-- Sin seguridad por filas, como sus hermanas (el entorno la activa al crear la tabla; sin politicas, claude_ro veria 0 filas).
alter table bi.v_cartera_transicion_dim disable row level security;

-- Transiciones entre DOS periodos (origen -> destino), con el minimo de 5 ya aplicado.
create or replace function bi.f_cartera_transicion(p_origen text, p_destino text)
returns table (uso text, estrato text, grupo_origen text, grupo_destino text, contratos bigint, saldo_origen numeric, saldo_destino numeric)
language sql stable as $$
  with o as (
    select trim(contrato) as k,
           coalesce(substring(btrim(max(uso)) from '^-?\d+'), '(sin dato)') as uso_cod,
           coalesce(substring(btrim(max(estrato)) from '^-?\d+'), '(sin dato)') as est_cod,
           coalesce(sum(bi.f_num(total_cartera)), 0) as saldo,
           case when coalesce(sum(bi.f_num(total_cartera)), 0) <= 0 then 'sin_deuda'
                when coalesce(max(bi.f_num(facturas_vencidas)), 0) = 0 then 'al_dia'
                when max(bi.f_num(facturas_vencidas)) <= 2 then 'v1_2' when max(bi.f_num(facturas_vencidas)) <= 8 then 'v3_8'
                when max(bi.f_num(facturas_vencidas)) <= 24 then 'v9_24' else 'v_mas24' end as grupo
    from hechos.cartera_contrato where periodo = p_origen group by 1),
  d as (
    select trim(contrato) as k,
           coalesce(substring(btrim(max(uso)) from '^-?\d+'), '(sin dato)') as uso_cod,
           coalesce(substring(btrim(max(estrato)) from '^-?\d+'), '(sin dato)') as est_cod,
           coalesce(sum(bi.f_num(total_cartera)), 0) as saldo,
           case when coalesce(sum(bi.f_num(total_cartera)), 0) <= 0 then 'sin_deuda'
                when coalesce(max(bi.f_num(facturas_vencidas)), 0) = 0 then 'al_dia'
                when max(bi.f_num(facturas_vencidas)) <= 2 then 'v1_2' when max(bi.f_num(facturas_vencidas)) <= 8 then 'v3_8'
                when max(bi.f_num(facturas_vencidas)) <= 24 then 'v9_24' else 'v_mas24' end as grupo
    from hechos.cartera_contrato where periodo = p_destino group by 1),
  j as (
    select coalesce(d.k, o.k) as k, coalesce(d.uso_cod, o.uso_cod) as uso_cod, coalesce(d.est_cod, o.est_cod) as est_cod,
           coalesce(o.grupo, 'no_estaba') as g_o, coalesce(d.grupo, 'no_esta') as g_d,
           coalesce(o.saldo, 0) as s_o, coalesce(d.saldo, 0) as s_d
    from o full join d on o.k = d.k),
  g as (select uso_cod, est_cod, count(*) as n from j group by 1, 2),
  y as (
    select j.k, j.g_o, j.g_d, j.s_o, j.s_d,
           case when g.n >= 5 and j.uso_cod in ('1', '3', '5', '9') then j.uso_cod else 'otros' end as uso,
           case when g.n >= 5 and j.est_cod in ('1', '2', '3', '4', '5', '6') then j.est_cod else 'otros' end as estrato
    from j join g using (uso_cod, est_cod)),
  c0 as (select uso, estrato, g_o, g_d, count(*) as n from y group by 1, 2, 3, 4),
  l0 as (select y.* from y join c0 using (uso, estrato, g_o, g_d) where c0.n >= 5),
  r1 as (select y.k, y.uso, 'otros'::text as estrato, y.g_o, y.g_d, y.s_o, y.s_d from y join c0 using (uso, estrato, g_o, g_d) where c0.n < 5),
  c1 as (select uso, estrato, g_o, g_d, count(*) as n from r1 group by 1, 2, 3, 4),
  l1 as (select r1.* from r1 join c1 using (uso, estrato, g_o, g_d) where c1.n >= 5),
  r2 as (select r1.k, 'otros'::text as uso, r1.estrato, r1.g_o, r1.g_d, r1.s_o, r1.s_d from r1 join c1 using (uso, estrato, g_o, g_d) where c1.n < 5),
  c2 as (select uso, estrato, g_o, g_d, count(*) as n from r2 group by 1, 2, 3, 4),
  l2 as (select r2.* from r2 join c2 using (uso, estrato, g_o, g_d) where c2.n >= 5),
  r3 as (select r2.k, r2.uso, r2.estrato, r2.g_o, 'agrupada'::text as g_d, r2.s_o, r2.s_d from r2 join c2 using (uso, estrato, g_o, g_d) where c2.n < 5),
  c3 as (select uso, estrato, g_o, g_d, count(*) as n from r3 group by 1, 2, 3, 4),
  l3 as (select r3.* from r3 join c3 using (uso, estrato, g_o, g_d) where c3.n >= 5),
  l4 as (select r3.k, 'otros'::text as uso, 'otros'::text as estrato, 'agrupada'::text as g_o, 'agrupada'::text as g_d, r3.s_o, r3.s_d
         from r3 join c3 using (uso, estrato, g_o, g_d) where c3.n < 5),
  todo as (
    select uso, estrato, g_o, g_d, s_o, s_d from l0 union all select uso, estrato, g_o, g_d, s_o, s_d from l1
    union all select uso, estrato, g_o, g_d, s_o, s_d from l2 union all select uso, estrato, g_o, g_d, s_o, s_d from l3
    union all select uso, estrato, g_o, g_d, s_o, s_d from l4)
  select uso, estrato, g_o as grupo_origen, g_d as grupo_destino,
         case when uso = 'otros' and estrato = 'otros' and g_o = 'agrupada' and g_d = 'agrupada' and count(*) < 5 then null else count(*) end as contratos,
         case when uso = 'otros' and estrato = 'otros' and g_o = 'agrupada' and g_d = 'agrupada' and count(*) < 5 then null else sum(s_o) end as saldo_origen,
         case when uso = 'otros' and estrato = 'otros' and g_o = 'agrupada' and g_d = 'agrupada' and count(*) < 5 then null else sum(s_d) end as saldo_destino
  from todo group by 1, 2, 3, 4
$$;
revoke all on function bi.f_cartera_transicion(text, text) from public, anon, authenticated;

create or replace function bi.recalcular_cartera_transicion(p_periodo text)
returns integer language plpgsql as $$
declare
  n integer := 0;
  k integer := 0;
  v_prev text;
  v_base text;
begin
  delete from bi.v_cartera_transicion_dim where periodo = p_periodo;
  select max(periodo) into v_prev from hechos.cartera_contrato where periodo < p_periodo;
  select min(periodo) into v_base from hechos.cartera_contrato;
  if v_prev is null or not exists (select 1 from hechos.cartera_contrato where periodo = p_periodo) then
    return 0;                                   -- primer periodo (o periodo inexistente): sin transiciones
  end if;
  insert into bi.v_cartera_transicion_dim
    select p_periodo, 'anterior', r.* from bi.f_cartera_transicion(v_prev, p_periodo) r;
  get diagnostics n = row_count;
  if v_base < v_prev then
    insert into bi.v_cartera_transicion_dim
      select p_periodo, 'base', r.* from bi.f_cartera_transicion(v_base, p_periodo) r;
    get diagnostics k = row_count;
    n := n + k;
  end if;
  return n;
end $$;
revoke all on function bi.recalcular_cartera_transicion(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (texto = el de sql/46 con la rama de bi.v_cartera_pago_dim, mas la rama de esta dimension; si se aplican 47 y 48 juntos, se aplica SOLO el de sql/48)
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
  elsif p_tabla = 'bi.v_cartera_transicion_dim' then n := bi.recalcular_cartera_transicion(p_periodo);
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
  elsif p_tabla = 'bi.v_cartera_transicion_dim' then
    delete from bi.v_cartera_transicion_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · Edge v28 y rama 62 de la RPC -------------------------------
-- Edge (geoportal-web): agregar "v_cartera_transicion_dim" a VISTAS_PERMITIDAS y desplegar. Va ANTES de la RPC. sql/05 queda IGUAL A LO VIVO hasta aplicar.
-- Rama (despues de la 61), antes del 'else raise exception':
--
--   elsif p_vista = 'v_cartera_transicion_dim' then
--     select coalesce(jsonb_agg(to_jsonb(t) order by t.referencia, t.uso, t.estrato, t.grupo_origen, t.grupo_destino), '[]'::jsonb)
--       into resultado
--     from bi.v_cartera_transicion_dim t
--     where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
--       and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
--       and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

-- >>> PASO 4 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_cartera_transicion_dim', 'AAAAMM');  -- 202603 a 202609 (202602 no genera filas por ser el primer periodo)
-- (cada uno en su transaccion con begin; set local statement_timeout='300s'; ... commit;)

-- >>> PASO 5 · controles ------------------------------------------------
-- (los mismos estan en VISTAS_TABLERO de cargar_hechos.py y en el script de controles del paquete)
--   a) primer periodo sin filas; 'base' solo si es distinta de 'anterior'.
--   b) por referencia: contratos = union de contratos de origen y destino, y saldos = totales de cartera_contrato (hasta 4 contratos suprimidos).
--   c) ninguna celda con menos de 5 contratos; uso, estrato y grupos en listas cerradas.
--   d) pares origen-destino: ningun conteo supera al de la fuente y lo que falta es lo agrupado.
--   e) ACL igual a la de v_cartera_detalle_dim; sin RLS.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia; los scripts estan fuera del repo, en el paquete):
--   RPC:         volver a la RPC de la Fase B (61 ramas), tras quitar la vista de la Edge (v27).
--   Despachador: volver al despachador de la Fase B.
--   drop function bi.recalcular_cartera_transicion(text); drop function bi.f_cartera_transicion(text, text);
--   drop table bi.v_cartera_transicion_dim;
