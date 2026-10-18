-- =====================================================================
-- 49_cartera_concepto_dim.sql · Cartera por concepto: composicion de la cartera por tipo de concepto y tramo de edad (Fase E)
-- ---------------------------------------------------------------------
-- Alimenta la zona «Cartera por concepto» de Cartera desagregada. Fuente: hechos.cartera_edades (valor en pesos por concepto, uso, estrato y etiqueta de edad) y
-- bi.v_concepto_mapa (nombre legible de cada codigo). Se construye ENCIMA de las fases B, C y D (sql/46 a 48): el despachador de este archivo incluye sus
-- ramas y la RPC lleva las ramas 61 a 63 mas la 64.
--
-- ADVERTENCIA: describe la COMPOSICION de la cartera, no su causa. cartera_edades NO trae contrato: el recargo por contrato no se puede obtener de esta fuente.
--
-- GRANO: periodo x uso x estrato x tipo x tramo -> valor (pesos). ~1.050 filas por periodo (~8.500 en 8 periodos: 202602 a 202609, 202606 incluido).
--  · tipo (bi.f_tipo_concepto: clasificacion por codigo y por nombre del mapa; los subsidios van en su propio tipo para poder mostrar neto y bruto):
--      capital_alcantarillado (3, 4, 21) · capital_acueducto (1, 2) · recargo_moratorio (6) · financiacion_capital (1001-1004, 1021, 1030-1033) ·
--      financiacion_recargo (1006) · contribucion (30-33) · cargos_emd (600, 602, 603, 605, 606) · interes_financiacion (20, 245, 9990-9997 y nombres INTERES…) ·
--      subsidios_descuentos (26-29, 38, 39) · corte_susp_reconexion (nombres con corte, suspension, reconexion o reinstalacion, sin EMD) ·
--      conexion_obras (conexion, medidores, accesorios, obras, ventas; incluye los cortes de acometida y de apique 170, 172 y 173) ·
--      financiacion_otros (cualquier otro codigo 1000-1999 o nombre FINANCIACION…/FIN…: financia conexion, obras, cortes, etc.) · otros (consumo excesivo, aseo, ajustes…).
--    «financiacion_otros» se agrego a los tipos pedidos porque meterla en «financiacion_capital» rotularia mal la financiacion de obras y cortes.
--  · tramo: etiqueta cruda de edad agrupada sin perder la lectura de limites: '0_330' (etiquetas mensuales 0 a 330), '360', '720', '1080', '1440', '1800', '1801'
--    (mayor a 1.800 dias segun el reporte) y 'sin_edad' (cartera financiada). El frontend los rotula con su mapeo unico (lectura provisional de limites).
--  · uso: '1', '3', '5', '9' u 'otros'; estrato: '1' a '6' u 'otros'. Subsidios y descuentos son negativos: neto = suma de todo; bruto = neto sin subsidios.
-- MINIMO 5 (privacidad): la fuente no trae contratos; para (uso, estrato) se cuentan los contratos con deuda de cartera_contrato del mismo periodo y el grupo con
--    menos de 5, o con uso o estrato fuera de las listas, va a 'otros' (igual que sql/45). Valor agregado en pesos, sin contrato, barrio ni ciclo.
-- SIN seguridad por filas y con REVOKE a anon, authenticated y PUBLIC.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funciones + revoke   2) despachador   3) Edge v29 y rama 64 de la RPC   4) carga   5) controles
-- =====================================================================

-- >>> PASO 1 (IDEMPOTENTE: se puede repetir tras un fallo parcial) · tabla, funciones, permisos ----

create table if not exists bi.v_cartera_concepto_dim (
  periodo  text,
  uso      text,
  estrato  text,
  tipo     text,
  tramo    text,
  valor    numeric,
  primary key (periodo, uso, estrato, tipo, tramo)
);
revoke all on bi.v_cartera_concepto_dim from public, anon, authenticated;
-- Sin seguridad por filas, como sus hermanas (el entorno la activa al crear la tabla; sin politicas, claude_ro veria 0 filas).
alter table bi.v_cartera_concepto_dim disable row level security;

-- Tipo de concepto a partir del codigo y del nombre del mapa (v_concepto_mapa). Si cambia, se recalcula la dimension.
create or replace function bi.f_tipo_concepto(p_codigo text, p_nombre text)
returns text language sql immutable as $$
  select
    case
      when p_codigo = '6' then 'recargo_moratorio'
      when p_codigo in ('1', '2') then 'capital_acueducto'
      when p_codigo in ('3', '4', '21') then 'capital_alcantarillado'
      when p_codigo in ('26', '27', '28', '29', '38', '39') then 'subsidios_descuentos'
      when p_codigo in ('30', '31', '32', '33') then 'contribucion'
      when p_codigo in ('600', '602', '603', '605', '606') then 'cargos_emd'
      when p_codigo in ('20', '9990', '9991', '9992', '9996', '9997') or upper(coalesce(p_nombre, '')) like 'INTERES%' then 'interes_financiacion'
      when p_codigo = '1006' then 'financiacion_recargo'
      when p_codigo in ('1001', '1002', '1003', '1004', '1021', '1030', '1031', '1032', '1033') then 'financiacion_capital'
      when p_codigo ~ '^1[0-9]{3}$' or upper(coalesce(p_nombre, '')) ~ '^(FINANCIACI|FINAN\.|FIN\.? )' then 'financiacion_otros'
      when p_codigo in ('170', '172', '173') then 'conexion_obras'              -- cortes de acometida y de apique: obras, no cortes del servicio
      when upper(coalesce(p_nombre, '')) ~ '(RECONEX|REINSTAL|SUSPENSI|CORTE)' then 'corte_susp_reconexion'
      when upper(coalesce(p_nombre, '')) ~ '(MEDIDOR|ACCESORIO|CAJA|INSTALACI|MANO DE OBRA|AGUAS POR|CONEXI|ACOMETIDA|VENTA|AMB |RECUPERACI|LLAVE|REGISTRO|SUM INST|NORMALIZACI|REPOSICI)' then 'conexion_obras'
      else 'otros'
    end
$$;
revoke all on function bi.f_tipo_concepto(text, text) from public, anon, authenticated;

create or replace function bi.recalcular_cartera_concepto(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cartera_concepto_dim where periodo = p_periodo;
  insert into bi.v_cartera_concepto_dim
  with ce as (
    select coalesce(nullif(btrim(e.categoria), ''), '(sin dato)')    as uso,
           coalesce(nullif(btrim(e.subcategoria), ''), '(sin dato)') as est,
           bi.f_tipo_concepto(btrim(e.recaconc), m.nombre)                                                  as tipo,
           case when nullif(btrim(e.edad), '') is null then 'sin_edad'
                when e.edad::numeric <= 330 then '0_330'
                else (e.edad::numeric)::bigint::text end             as tramo,
           bi.f_num(e.total)                                         as v
    from hechos.cartera_edades e
    left join bi.v_concepto_mapa m on m.concepto_num::text = btrim(e.recaconc)
    where e.periodo = p_periodo),
  k as (
    select coalesce(substring(btrim(uso) from '^-?\d+'), '(sin dato)')     as uso,
           coalesce(substring(btrim(estrato) from '^-?\d+'), '(sin dato)') as est,
           count(distinct contrato) as n
    from hechos.cartera_contrato
    where periodo = p_periodo and coalesce(bi.f_num(total_cartera), 0) > 0
    group by 1, 2)
  select p_periodo::text as periodo,
         case when coalesce(k.n, 0) >= 5 and ce.uso in ('1', '3', '5', '9') then ce.uso else 'otros' end as uso,
         case when coalesce(k.n, 0) >= 5 and ce.est in ('1', '2', '3', '4', '5', '6') then ce.est else 'otros' end as estrato,
         ce.tipo, ce.tramo, sum(ce.v) as valor
  from ce left join k on k.uso = ce.uso and k.est = ce.est
  group by 2, 3, 4, 5;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cartera_concepto(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (texto = el de sql/48 con las ramas de las fases B, C y D, mas la rama de esta dimension)
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
  elsif p_tabla = 'bi.v_emd_dim' then n := bi.recalcular_emd(p_periodo);
  elsif p_tabla = 'bi.v_cartera_concepto_dim' then n := bi.recalcular_cartera_concepto(p_periodo);
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
  elsif p_tabla = 'bi.v_emd_dim' then
    delete from bi.v_emd_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_concepto_dim' then
    delete from bi.v_cartera_concepto_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  end if;

  return n;
end $function$;

-- >>> PASO 3 · Edge v29 y rama 64 de la RPC -------------------------------
-- Edge (geoportal-web): agregar "v_cartera_concepto_dim" a VISTAS_PERMITIDAS y desplegar (v29). Va ANTES de la RPC. sql/05 queda IGUAL A LO VIVO hasta aplicar.
-- Rama (despues de la 63), antes del 'else raise exception':
--
--   elsif p_vista = 'v_cartera_concepto_dim' then
--     select coalesce(jsonb_agg(to_jsonb(t) order by t.tipo, t.uso, t.estrato, t.tramo), '[]'::jsonb)
--       into resultado
--     from bi.v_cartera_concepto_dim t
--     where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
--       and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
--       and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

-- >>> PASO 4 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_cartera_concepto_dim', 'AAAAMM');  -- 202602 a 202609
-- (cada uno en su transaccion con begin; set local statement_timeout='300s'; ... commit;)

-- >>> PASO 5 · controles ------------------------------------------------
-- (los mismos estan en VISTAS_TABLERO de cargar_hechos.py y en el script de controles del paquete)
--   a) valor total = total de cartera_edades; EXCEPT 0/0 por tramo y por tipo contra cartera_edades (tolerancia de 1 peso).
--   b) anclas por codigo (recargo, capital, subsidios, EMD, contribucion, financiacion del recargo) = sus tipos.
--   c) todo codigo con valor tiene nombre en v_concepto_mapa.
--   d) listas cerradas y valores negativos solo en subsidios y otros.
--   e) ACL igual a la de v_cartera_detalle_dim; sin RLS.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia; los scripts estan fuera del repo, en el paquete):
--   RPC y despachador: volver a los de la Fase D (63 ramas), tras quitar la vista de la Edge (v28).
--   drop function bi.recalcular_cartera_concepto(text); drop function bi.f_tipo_concepto(text, text); drop table bi.v_cartera_concepto_dim;
