-- =====================================================================
-- 48_emd_dim.sql · Suspensiones y cortes: conceptos «EMD » facturados (Fase D)
-- ---------------------------------------------------------------------
-- Alimenta la zona «Suspensiones y cortes» de Cartera. Fuente: hechos.facturacion_contratos (conceptos cuyo nombre es «<codigo>- EMD …») y, para
-- clasificar el contrato, hechos.cartera_contrato del mismo periodo. Se construye ENCIMA de las fases B y C: el despachador de este archivo incluye las
-- ramas de bi.v_cartera_pago_dim y bi.v_cartera_transicion_dim, y la RPC lleva las ramas 61 (B), 62 (C) y 63.
--
-- ADVERTENCIA OBLIGATORIA: LO FACTURADO NO ES LA ACTIVIDAD FISICA EN TERRENO. La dimension cuenta contratos y valores COBRADOS EN FACTURA por los conceptos
-- EMD (suspension, corte, reinstalacion, reconexion); una orden ejecutada puede facturarse en un periodo posterior o no facturarse, y un cobro puede
-- corresponder a una orden de otro mes. No es el registro de ordenes (SCRR) ni mide cortes o suspensiones realmente hechos. Debe repetirse en la pantalla.
--
-- GRANO: periodo x uso x estrato x codigo x mora x estado_producto -> contratos (pares contrato-codigo) y valor facturado (pesos).
--  · codigo: '600' corte sencillo, '602' suspension sencilla, '603' reinstalacion sencilla, '605' corte drastico, '606' reconexion drastica; 'agrupado'
--    (codigos con pocos contratos); 'sin_datos'. Un contrato con dos codigos cuenta una vez en cada uno.
--  · CONFIABLE desde 202605. En 202602 a 202604 la fuente no trae conceptos EMD: cada uno de esos periodos tiene UNA fila con codigo 'sin_datos' y
--    contratos y valor en 0, para que la pantalla diga «sin datos» y no «sin actividad».
--  · mora: grupo de mora del contrato en cartera_contrato del mismo periodo ('sin_deuda', 'al_dia', 'v1_2', 'v3_8', 'v9_24', 'v_mas24'); 'sin_cartera'
--    si el contrato no esta en cartera_contrato. estado_producto: 'activo', 'retirado', 'coactivo' (Bloqueo Coactivo), 'suspendido', 'otro'; 'sin_cartera'.
--  · valor_facturado = suma de la columna facturado de las lineas EMD (credito y debito netos).
-- MINIMO 5 (privacidad): (1) por (uso, estrato) como en sql/46. (2) POR CELDA: las celdas con menos de 5 contratos se funden en 4 pasos, siempre con
--    las mismas sumas: estado_producto 'agrupada'; luego tambien mora 'agrupada'; luego uso y estrato 'otros'; y lo que quede se funde en el codigo
--    'agrupado'. Solo esa ultima celda puede tener menos de 5 contratos; entonces se publica con contratos y valor NULL («menos de 5 contratos»).
-- Sin contrato, barrio ni ciclo. SIN seguridad por filas y con REVOKE a anon, authenticated y PUBLIC.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) Edge v28 y rama 63 de la RPC   4) carga   5) controles
-- =====================================================================

-- >>> PASO 1 (IDEMPOTENTE: se puede repetir tras un fallo parcial) · tabla, funcion, permisos --------------------------------

create table if not exists bi.v_emd_dim (
  periodo          text,
  uso              text,
  estrato          text,
  codigo           text,
  mora             text,
  estado_producto  text,
  contratos        bigint,
  valor_facturado  numeric,
  primary key (periodo, uso, estrato, codigo, mora, estado_producto)
);
revoke all on bi.v_emd_dim from public, anon, authenticated;
-- Sin seguridad por filas, como sus hermanas (el entorno la activa al crear la tabla; sin politicas, claude_ro veria 0 filas).
alter table bi.v_emd_dim disable row level security;
comment on table bi.v_emd_dim is 'Conceptos EMD FACTURADOS (600, 602, 603, 605, 606) por uso, estrato, mora y estado del producto. Lo facturado no es la actividad fisica en terreno. Confiable desde 202605; 202602 a 202604 sin datos.';

create or replace function bi.recalcular_emd(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_emd_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.facturacion_contratos where periodo = p_periodo) then
    return 0;                                   -- periodo inexistente en la fuente
  end if;
  if p_periodo < '202605' then
    insert into bi.v_emd_dim values (p_periodo, 'otros', 'otros', 'sin_datos', 'sin_datos', 'sin_datos', 0, 0);
  else
    insert into bi.v_emd_dim
    select p_periodo, z.uso, z.estrato, z.codigo, z.mora, z.estado_producto, z.contratos, z.valor_facturado
    from (
      with e as (
        select trim(contrato) as k, substring(concepto from '^([0-9]+)-') as cod, sum(bi.f_num(facturado)) as valor
        from hechos.facturacion_contratos
        where periodo = p_periodo and concepto ~ '^[0-9]+- EMD '
        group by 1, 2),
      c as (
        select trim(contrato) as k,
               coalesce(substring(btrim(max(uso)) from '^-?\d+'), '(sin dato)') as uso_cod,
               coalesce(substring(btrim(max(estrato)) from '^-?\d+'), '(sin dato)') as est_cod,
               case when coalesce(sum(bi.f_num(total_cartera)), 0) <= 0 then 'sin_deuda'
                    when coalesce(max(bi.f_num(facturas_vencidas)), 0) = 0 then 'al_dia'
                    when max(bi.f_num(facturas_vencidas)) <= 2 then 'v1_2' when max(bi.f_num(facturas_vencidas)) <= 8 then 'v3_8'
                    when max(bi.f_num(facturas_vencidas)) <= 24 then 'v9_24' else 'v_mas24' end as mora,
               case max(btrim(estado_producto)) when 'Activo' then 'activo' when 'Retirado' then 'retirado' when 'Bloqueo Coactivo' then 'coactivo'
                    when 'Suspendido' then 'suspendido' else 'otro' end as estprod
        from hechos.cartera_contrato where periodo = p_periodo group by 1),
      g as (select uso_cod, est_cod, count(*) as n from c group by 1, 2),
      y as (
        select e.k, e.cod, e.valor, coalesce(c.mora, 'sin_cartera') as mora, coalesce(c.estprod, 'sin_cartera') as estprod,
               case when coalesce(g.n, 0) >= 5 and c.uso_cod in ('1', '3', '5', '9') then c.uso_cod else 'otros' end as uso,
               case when coalesce(g.n, 0) >= 5 and c.est_cod in ('1', '2', '3', '4', '5', '6') then c.est_cod else 'otros' end as estrato
        from e left join c on c.k = e.k left join g on g.uso_cod = c.uso_cod and g.est_cod = c.est_cod),
      c0 as (select uso, estrato, cod, mora, estprod, count(*) as n from y group by 1, 2, 3, 4, 5),
      l0 as (select y.* from y join c0 using (uso, estrato, cod, mora, estprod) where c0.n >= 5),
      r1 as (select y.k, y.cod, y.valor, y.mora, 'agrupada'::text as estprod, y.uso, y.estrato from y join c0 using (uso, estrato, cod, mora, estprod) where c0.n < 5),
      c1 as (select uso, estrato, cod, mora, estprod, count(*) as n from r1 group by 1, 2, 3, 4, 5),
      l1 as (select r1.* from r1 join c1 using (uso, estrato, cod, mora, estprod) where c1.n >= 5),
      r2 as (select r1.k, r1.cod, r1.valor, 'agrupada'::text as mora, r1.estprod, r1.uso, r1.estrato from r1 join c1 using (uso, estrato, cod, mora, estprod) where c1.n < 5),
      c2 as (select uso, estrato, cod, mora, estprod, count(*) as n from r2 group by 1, 2, 3, 4, 5),
      l2 as (select r2.* from r2 join c2 using (uso, estrato, cod, mora, estprod) where c2.n >= 5),
      r3 as (select r2.k, r2.cod, r2.valor, r2.mora, r2.estprod, 'otros'::text as uso, 'otros'::text as estrato from r2 join c2 using (uso, estrato, cod, mora, estprod) where c2.n < 5),
      c3 as (select uso, estrato, cod, mora, estprod, count(*) as n from r3 group by 1, 2, 3, 4, 5),
      l3 as (select r3.* from r3 join c3 using (uso, estrato, cod, mora, estprod) where c3.n >= 5),
      r4 as (select r3.k, 'agrupado'::text as cod, r3.valor, r3.mora, r3.estprod, r3.uso, r3.estrato from r3 join c3 using (uso, estrato, cod, mora, estprod) where c3.n < 5),
      todo as (
        select uso, estrato, cod, mora, estprod, valor from l0 union all select uso, estrato, cod, mora, estprod, valor from l1
        union all select uso, estrato, cod, mora, estprod, valor from l2 union all select uso, estrato, cod, mora, estprod, valor from l3
        union all select uso, estrato, cod, mora, estprod, valor from r4)
      select uso, estrato, cod as codigo, mora, estprod as estado_producto,
             case when cod = 'agrupado' and count(*) < 5 then null else count(*) end as contratos,
             case when cod = 'agrupado' and count(*) < 5 then null else sum(valor) end as valor_facturado
      from todo group by 1, 2, 3, 4, 5
    ) z;
  end if;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_emd(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (texto = el de sql/47 mas la rama de esta dimension: contiene las ramas de las fases B, C y D; es el que se aplica cuando se aplican 47 y 48 juntos)
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · Edge v28 y rama 63 de la RPC -------------------------------
-- Edge (geoportal-web): agregar "v_emd_dim" a VISTAS_PERMITIDAS y desplegar (v28, junto con "v_cartera_transicion_dim"). Va ANTES de la RPC.
-- sql/05 queda IGUAL A LO VIVO hasta aplicar. Rama (despues de la 62), antes del 'else raise exception':
--
--   elsif p_vista = 'v_emd_dim' then
--     select coalesce(jsonb_agg(to_jsonb(t) order by t.codigo, t.uso, t.estrato, t.mora, t.estado_producto), '[]'::jsonb)
--       into resultado
--     from bi.v_emd_dim t
--     where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
--       and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
--       and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

-- >>> PASO 4 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_emd_dim', 'AAAAMM');  -- 202602 a 202609 (202602 a 202604 dejan la fila 'sin_datos')
-- (cada uno en su transaccion con begin; set local statement_timeout='300s'; ... commit;)

-- >>> PASO 5 · controles ------------------------------------------------
--   a) antes de 202605 solo la fila 'sin_datos'; desde 202605 no existe.
--   b) pares (contrato, codigo) y valor facturado = fuente (hasta 4 contratos suprimidos en 'agrupado').
--   c) ninguna celda con menos de 5 contratos; todo en listas cerradas.
--   d) por codigo: ningun conteo supera al de la fuente y lo que falta es lo agrupado.
--   e) ACL igual a la de v_cartera_detalle_dim; sin RLS.

-- ROLLBACK (solo si ninguna pantalla lo usa todavia; los scripts estan fuera del repo, en el paquete):
--   RPC y despachador: volver a los de la Fase C (o B), tras quitar la vista de la Edge.
--   drop function bi.recalcular_emd(text); drop table bi.v_emd_dim;
