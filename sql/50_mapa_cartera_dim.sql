-- =====================================================================
-- sql/50 · MAPA DE CALOR DE CARTERA (Cartera desagregada): tabla interna, recalculo, despachador, funciones de lectura y rama 65 de la RPC
-- =====================================================================
-- Un mapa de calor de la cartera por celdas de 250 m (100 m al filtrar), con medidas (deuda total y contratos con mas de 8 o mas de 60 facturas
-- vencidas), filtros (comuna, barrio, ciclo, rango de deuda por cuartiles y antiguedad de la deuda del contrato por facturas vencidas) y un cuadro de
-- conciliacion. Solo agregados y supresion siempre encendida.
--
-- Piezas (en este archivo, en este orden):
--   1) bi_interno.cartera_mapa_contrato / cartera_mapa_barrio / cartera_mapa_periodo: tablas INTERNAS (una fila anonima por contrato con saldo y periodo,
--      catalogo de barrios y cortes de cuartil). NUNCA se sirven: no estan en la lista cerrada de vistas; sin RLS y con revoke a public, anon y authenticated;
--      tampoco claude_ro tiene select (una fila con su celda de 100 m, comuna, barrio, ciclo y saldo es casi identificadora donde hay pocos contratos).
--      El tramo (0 = ninguna, 1 = 1 a 3, 2 = 4 a 8, 3 = 9 a 24, 4 = 25 a 60, 5 = mas de 60) clasifica CONTRATOS por su numero de facturas vencidas, no pesos.
--   2) bi.recalcular_cartera_mapa(periodo) y la rama de bi.recalcular (con su limpieza de huerfanos de UN solo recorrido: la version con NOT EXISTS
--      correlacionado vencia el statement_timeout al crecer la tabla).
--   3) bi.f_mapa_cartera (8 argumentos) y bi.f_mapa_cartera_catalogo: funciones SQL de solo lectura que calculan celdas, conciliacion, cortes y catalogo.
--   4) La rama 65 de public.geoportal_bi_consulta (en sql/05): valida y delega; sin SQL dinamico.
--   5) Pruebas de solo lectura (privilegios, regresion de las 64 ramas y prueba EXCEPT de la rama): sql/50_mapa_cartera_pruebas.sql.
-- Fuente: hechos.cartera_contrato (saldo = suma de total_cartera por contrato; facturas vencidas = maximo por contrato; ciclo y comuna),
-- public.predios_comercial (coordenadas y barrio; un registro por cod_usuario, el de menor id; se excluyen vacio y '0') y public.catastro_valledupar
-- (comuna de respaldo, un digito). Las coordenadas son las vigentes (no tienen periodo): se aplican a todos los periodos.
-- Carga: por periodo, en transaccion:  begin; set local statement_timeout = '300s'; select bi.recalcular('bi_interno.cartera_mapa_contrato', '2026NN'); commit;
-- Controles: viven en la entrada de VISTAS_TABLERO de cargar_hechos.py (etl-emdupar) y en sql/50_mapa_cartera_pruebas.sql.
-- Orden de aplicacion: 1 y 2 (tablas, funcion y despachador) -> carga -> 3 (funciones de lectura) -> rama 65 de sql/05 -> Edge (lista cerrada y filtros).
-- =====================================================================

-- >>> PASO 1 · tablas internas, permisos y funcion de recalculo ---------------------------------------------------------------------------------------------
create table if not exists bi_interno.cartera_mapa_contrato (
  periodo       text        not null,
  x250          integer,                 -- floor(x/250), x en EPSG:3116 (m); null si el contrato no tiene coordenadas
  y250          integer,
  x100          integer,                 -- floor(x/100)
  y100          integer,
  comuna        smallint    not null,    -- 1..6; 0 = Sin comuna
  barrio_id     integer     not null,    -- clave de bi_interno.cartera_mapa_barrio (dentro del periodo)
  ciclo         smallint    not null,    -- 1..24; 0 = Sin ciclo (incluye 9999)
  tramo         smallint,                -- antiguedad por FACTURAS VENCIDAS del contrato (maximo de facturas_vencidas): 0 = ninguna, 1 = 1 a 3, 2 = 4 a 8, 3 = 9 a 24, 4 = 25 a 60, 5 = mas de 60
  cuartil       smallint    not null,    -- 1..4 segun el saldo por contrato de TODA la ciudad (contratos con saldo > 0)
  banda         smallint    not null,    -- 1,2,3 = cuartiles 1..3; 4 = cuartil 4 hasta el percentil 95; 5 = por encima del percentil 95
  saldo         numeric     not null,    -- total_cartera del contrato (todos sus productos)
  saldo_gt8     numeric     not null,    -- = saldo si el contrato tiene MAS de 8 facturas vencidas; si no, 0
  saldo_gt60    numeric     not null,    -- = saldo si tiene MAS de 60; si no, 0
  con_coord     boolean     not null,
  calculado_en  timestamptz not null default now()
);
-- Si la tabla ya existia (creada sin el tramo), se anade la columna sin tocar los datos; el recalculo de cada periodo la llena y, cuando todos los periodos
-- estan recalculados, se puede dejar NOT NULL (alter table ... alter column tramo set not null; falla si algun periodo quedo sin tramo).
alter table bi_interno.cartera_mapa_contrato add column if not exists tramo smallint;
create index if not exists ix_cmc_periodo on bi_interno.cartera_mapa_contrato (periodo);
create index if not exists ix_cmc_periodo_coord on bi_interno.cartera_mapa_contrato (periodo, con_coord);

create table if not exists bi_interno.cartera_mapa_barrio (   -- catalogo de barrios (ya con «Otros barrios» y «Sin barrio» por comuna)
  periodo   text     not null,
  barrio_id integer  not null,
  comuna    smallint not null,
  barrio    text     not null,
  contratos integer  not null,
  primary key (periodo, barrio_id)
);
create table if not exists bi_interno.cartera_mapa_periodo (  -- cortes de cuartil (percentile_cont sobre toda la ciudad) y totales del periodo
  periodo   text primary key,
  contratos integer not null,
  saldo     numeric not null,
  q1 numeric not null, q2 numeric not null, q3 numeric not null, p95 numeric not null,
  calculado_en timestamptz not null default now()
);

alter table bi_interno.cartera_mapa_contrato disable row level security;
alter table bi_interno.cartera_mapa_barrio   disable row level security;
alter table bi_interno.cartera_mapa_periodo  disable row level security;
revoke all on bi_interno.cartera_mapa_contrato from public, anon, authenticated;
revoke all on bi_interno.cartera_mapa_barrio   from public, anon, authenticated;
revoke all on bi_interno.cartera_mapa_periodo  from public, anon, authenticated;
-- claude_ro: SIN grant (decision de privacidad, ver 00_PLAN.md). Si David quiere que claude_ro la lea, es su decision explicita.

-- >>> PASO 2 · funcion de recalculo -----------------------------------------------------------------------------------------
create or replace function bi.recalcular_cartera_mapa(p_periodo text)
returns integer language plpgsql as $$
declare
  c_srid       constant integer := 3116;   -- EPSG:3116, origen constante (igual que sql/42)
  c_min_barrio constant integer := 5;      -- barrio con menos de 5 contratos (con saldo) en su comuna = «Otros barrios»
  n integer;
begin
  delete from bi_interno.cartera_mapa_contrato where periodo = p_periodo;
  delete from bi_interno.cartera_mapa_barrio   where periodo = p_periodo;
  delete from bi_interno.cartera_mapa_periodo  where periodo = p_periodo;
  if not exists (select 1 from hechos.cartera_contrato where periodo = p_periodo) then
    return 0;
  end if;

  with cc as (
    select btrim(contrato) as cod,
           sum(coalesce(bi.f_num(total_cartera), 0)) as saldo,
           max(case when btrim(facturas_vencidas) ~ '^[0-9]+$' then btrim(facturas_vencidas)::int end) as fv,
           max(nullif(btrim(ciclo), '')) as ciclo_t,
           max(nullif(btrim(comuna), '')) as comuna_t
    from hechos.cartera_contrato
    where periodo = p_periodo
    group by btrim(contrato)
    having sum(coalesce(bi.f_num(total_cartera), 0)) > 0),
  cat as (
    select distinct on (btrim(cod_usuario::text)) btrim(cod_usuario::text) as cod, nullif(btrim(comuna::text), '') as comuna_cat
    from public.catastro_valledupar
    where nullif(btrim(cod_usuario::text), '') is not null and btrim(cod_usuario::text) <> '0'
    order by btrim(cod_usuario::text), ctid),
  pcg as (
    select distinct on (q.cod) q.cod, q.barrio_t,
           floor(st_x(q.g) / 250)::int as x250, floor(st_y(q.g) / 250)::int as y250,
           floor(st_x(q.g) / 100)::int as x100, floor(st_y(q.g) / 100)::int as y100,
           (q.g is not null) as con_coord
    from (select btrim(cod_usuario::text) as cod, id,
                 nullif(upper(btrim(regexp_replace(barrio::text, '\s+', ' ', 'g'))), '') as barrio_t,
                 st_transform(geom, c_srid) as g
          from public.predios_comercial
          where nullif(btrim(cod_usuario::text), '') is not null and btrim(cod_usuario::text) <> '0') q
    order by q.cod, q.id),
  p as (
    select percentile_cont(array[0.25, 0.5, 0.75, 0.95]) within group (order by saldo) as q from cc),
  b as (
    select cc.cod, cc.saldo, cc.fv,
           case when cc.ciclo_t ~ '^[0-9]+$' and cc.ciclo_t::int between 1 and 24 then cc.ciclo_t::int else 0 end::smallint as ciclo,
           -- comuna: la de cartera_contrato ('101.0'..'106.0' -> 1..6); si falta, la del catastro (digito); si no, 0 = Sin comuna
           case when cc.comuna_t ~ '^10[1-6](\.0+)?$' then right(split_part(cc.comuna_t, '.', 1), 1)::int
                when cat.comuna_cat ~ '^[1-6]$' then cat.comuna_cat::int
                else 0 end::smallint as comuna,
           coalesce(pcg.barrio_t, 'SIN BARRIO') as barrio1,
           pcg.x250, pcg.y250, pcg.x100, pcg.y100, coalesce(pcg.con_coord, false) as con_coord
    from cc left join pcg on pcg.cod = cc.cod left join cat on cat.cod = cc.cod),
  b2 as (
    select b.*, count(*) over (partition by b.comuna, b.barrio1) as nb from b),
  b3 as (
    select b2.*, case when b2.nb < c_min_barrio then 'OTROS BARRIOS' else b2.barrio1 end as barrio2 from b2),
  b4 as (
    select b3.*, dense_rank() over (order by b3.comuna, b3.barrio2)::int as barrio_id from b3),
  ins_bar as (
    insert into bi_interno.cartera_mapa_barrio (periodo, barrio_id, comuna, barrio, contratos)
    select p_periodo, barrio_id, comuna, barrio2, count(*) from b4 group by barrio_id, comuna, barrio2
    returning 1),
  ins_per as (
    insert into bi_interno.cartera_mapa_periodo (periodo, contratos, saldo, q1, q2, q3, p95)
    select p_periodo, count(*), sum(b4.saldo), p.q[1], p.q[2], p.q[3], p.q[4] from b4 cross join p group by p.q
    returning 1)
  insert into bi_interno.cartera_mapa_contrato
    (periodo, x250, y250, x100, y100, comuna, barrio_id, ciclo, tramo, cuartil, banda, saldo, saldo_gt8, saldo_gt60, con_coord)
  select p_periodo, b4.x250, b4.y250, b4.x100, b4.y100, b4.comuna, b4.barrio_id, b4.ciclo,
         -- tramo por facturas vencidas del contrato; sin dato = 0 (hoy no hay contratos con saldo y sin dato). Los cortes 8 y 60 coinciden con saldo_gt8 y saldo_gt60.
         (case when coalesce(b4.fv, 0) = 0 then 0 when b4.fv <= 3 then 1 when b4.fv <= 8 then 2 when b4.fv <= 24 then 3 when b4.fv <= 60 then 4 else 5 end)::smallint,
         (case when b4.saldo <= p.q[1] then 1 when b4.saldo <= p.q[2] then 2 when b4.saldo <= p.q[3] then 3 else 4 end)::smallint,
         (case when b4.saldo <= p.q[1] then 1 when b4.saldo <= p.q[2] then 2 when b4.saldo <= p.q[3] then 3 when b4.saldo <= p.q[4] then 4 else 5 end)::smallint,
         b4.saldo,
         case when coalesce(b4.fv, 0) > 8  then b4.saldo else 0 end,
         case when coalesce(b4.fv, 0) > 60 then b4.saldo else 0 end,
         b4.con_coord
  from b4 cross join p;

  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cartera_mapa(text) from public, anon, authenticated;

-- >>> PASO 2b · despachador bi.recalcular (definicion vigente, con la rama del mapa y la limpieza de un solo recorrido)
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
  elsif p_tabla = 'bi_interno.cartera_mapa_contrato' then n := bi.recalcular_cartera_mapa(p_periodo);
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
  elsif p_tabla = 'bi_interno.cartera_mapa_contrato' then
    -- Limpieza de huerfanos de UN solo recorrido: los periodos vivos de la fuente se leen una vez (salto de periodo en periodo por el indice) y las tres
    -- tablas se limpian contra esa lista; sin subconsulta correlacionada fila por fila (la v1 con NOT EXISTS vencia el statement_timeout).
    declare vivos text[];
    begin
      with recursive p(periodo) as (
        select min(periodo) from hechos.cartera_contrato
        union all
        select (select min(periodo) from hechos.cartera_contrato where periodo > p.periodo) from p where p.periodo is not null)
      select coalesce(array_agg(periodo), '{}'::text[]) into vivos from p where periodo is not null;
      delete from bi_interno.cartera_mapa_contrato where periodo <> all (vivos);
      delete from bi_interno.cartera_mapa_barrio   where periodo <> all (vivos);
      delete from bi_interno.cartera_mapa_periodo  where periodo <> all (vivos);
    end;
  end if;

  return n;
end $function$;

-- >>> PASO 3 · funciones de lectura
-- SUPRESION (siempre encendida en esta capa):
--  1. Una celda se publica solo con 5 o mas contratos con deuda.
--  2. Entre las medidas de una celda hay "anillos" (contratos sin mora profunda = n - n8; con 9 a 60 facturas = n8 - n60; con mas de 60 = n60). Si un anillo
--     tiene 1 a 4 contratos, la resta de dos saldos publicados lo revelaria: la medida que lo cierra (saldo_gt8 o saldo_gt60) se publica NULL.
--  3. Supresion complementaria entre celdas: los contratos NO dibujados (celdas de menos de 5 + sin coordenadas + celdas suprimidas por el anillo) forman
--     un residual; si el residual queda con 1 a 4 contratos, su saldo se deduciria restando lo dibujado del total, asi que ademas se oculta la celda
--     dibujada mas pequena (menos contratos de la medida; desempate por indice) y pasa al residual (que queda con 6 o mas).
--  4. El desglose del residual (menos de 5 / sin coordenadas / anillo) solo se publica si cada parte tiene 0 o 5 o mas contratos; si no, solo la suma.
--  5. Si el total del filtro (contratos de la medida) es menor de 5, no se devuelve ni el total.
-- Limite conocido (documentado en la metodologia del mapa): dos consultas con filtros distintos que difieran en pocos contratos podrian restarse; con el filtro de antiguedad por tramos es mas directo. No se cierra aqui: el acceso a esta capa es interno y restringido.

-- La firma cambia (parametro nuevo p_tra): se retira la de 7 argumentos para no dejar dos sobrecargas (la RPC nueva llama a la de 8).
drop function if exists bi.f_mapa_cartera(text, text, text, smallint[], integer[], smallint[], smallint[]);
create or replace function bi.f_mapa_cartera(
  p_periodo text, p_medida text, p_resolucion text,
  p_com smallint[], p_bar integer[], p_cic smallint[], p_ban smallint[], p_tra smallint[])
returns jsonb language sql stable
set search_path = public, bi, bi_interno, pg_temp
as $$
with
f as materialized (
  select t.x250, t.y250, t.x100, t.y100, t.saldo, t.saldo_gt8, t.saldo_gt60, t.con_coord
  from bi_interno.cartera_mapa_contrato t
  where t.periodo = p_periodo
    and (p_com is null or t.comuna = any (p_com))
    and (p_bar is null or t.barrio_id = any (p_bar))
    and (p_cic is null or t.ciclo = any (p_cic))
    and (p_ban is null or t.banda = any (p_ban))
    and (p_tra is null or t.tramo = any (p_tra))),
c100 as (
  select x100 as cx, y100 as cy, count(*) as n, sum(saldo) as s from f where con_coord group by 1, 2),
dr as (
  -- resolucion: fijada por el usuario; 250 m sin filtros; con filtros, 100 m si deja >= 20 celdas con 5 o mas contratos que cubran >= 80 % del saldo ubicado
  select case
           when p_resolucion in ('100', '250') then p_resolucion::int
           when p_com is null and p_bar is null and p_cic is null and p_ban is null and p_tra is null then 250
           when (select count(*) filter (where n >= 5) from c100) >= 20
            and (select coalesce(sum(s) filter (where n >= 5), 0) from c100) >= 0.8 * (select coalesce(sum(s), 0) from c100) then 100
           else 250 end as lado,
         case
           when p_resolucion in ('100', '250') then 'fijada por el usuario'
           when p_com is null and p_bar is null and p_cic is null and p_ban is null and p_tra is null then 'ciudad completa'
           when (select count(*) filter (where n >= 5) from c100) >= 20
            and (select coalesce(sum(s) filter (where n >= 5), 0) from c100) >= 0.8 * (select coalesce(sum(s), 0) from c100) then 'filtro con suficientes celdas a 100 m'
           else 'el filtro deja pocas celdas de 5 o mas contratos a 100 m' end as motivo),
cel as (
  select case when d.lado = 100 then f.x100 else f.x250 end as cx, case when d.lado = 100 then f.y100 else f.y250 end as cy,
         count(*) as n, count(*) filter (where f.saldo_gt8 > 0) as n8, count(*) filter (where f.saldo_gt60 > 0) as n60,
         sum(f.saldo) as s, sum(f.saldo_gt8) as s8, sum(f.saldo_gt60) as s60
  from f cross join dr d where f.con_coord group by 1, 2, d.lado),
fl as (
  select cel.*,
         (n >= 5) as ok_s,
         (n >= 5 and (n8 = 0 or n8 >= 5) and (n - n8 = 0 or n - n8 >= 5)) as ok_8,
         (n >= 5 and (n60 = 0 or n60 >= 5) and (n - n60 = 0 or n - n60 >= 5) and (n8 - n60 = 0 or n8 - n60 >= 5)) as ok_60
  from cel),
m as (
  select fl.*,
         case p_medida when 'gt8' then ok_8 when 'gt60' then ok_60 when 'part60' then ok_60 else ok_s end as ok_m,
         case p_medida when 'gt8' then n8 when 'gt60' then n60 else n end as n_m,
         case p_medida when 'gt8' then s8 when 'gt60' then s60 else s end as s_m
  from fl),
sc as (  -- contratos del filtro sin coordenadas, en la medida elegida
  select coalesce(sum(case p_medida when 'gt8' then saldo_gt8 when 'gt60' then saldo_gt60 else saldo end), 0) as s_m,
         count(*) filter (where case p_medida when 'gt8' then saldo_gt8 when 'gt60' then saldo_gt60 else saldo end > 0) as n_m
  from f where not con_coord),
tot as (
  select (select count(*) from f) as n_filtro,
         coalesce((select sum(s_m) from m), 0) + (select s_m from sc) as s_m,
         coalesce((select sum(n_m) from m), 0) + (select n_m from sc) as n_m),
resid as (  -- contratos de la medida que no quedan en una celda dibujable (antes de la supresion complementaria)
  select coalesce(sum(n_m) filter (where not ok_m), 0) + (select n_m from sc) as r from m),
ex as (  -- supresion complementaria entre celdas: se oculta la celda dibujable mas pequena
  select cx, cy from m
  where ok_m and n_m > 0 and (select r from resid) between 1 and 4
  order by n_m, cx, cy limit 1),
fin as (
  select m.*, (m.ok_m and not exists (select 1 from ex where ex.cx = m.cx and ex.cy = m.cy)) as pub from m),
bk as (
  select coalesce(sum(s_m) filter (where pub), 0) as dib_s, coalesce(sum(n_m) filter (where pub), 0) as dib_n,
         coalesce(sum(s_m) filter (where n < 5), 0) as lt5_s, coalesce(sum(n_m) filter (where n < 5), 0) as lt5_n,
         coalesce(sum(s_m) filter (where n >= 5 and not pub), 0) as an_s, coalesce(sum(n_m) filter (where n >= 5 and not pub), 0) as an_n
  from fin),
ok_total as (select (select n_m from tot) >= 5 as ok)
select coalesce(jsonb_agg(x), '[]'::jsonb) from (
  select jsonb_build_object('tipo', 'meta', 'periodo', p_periodo, 'medida', p_medida, 'lado', d.lado, 'motivo_resolucion', d.motivo,
                            'suficiente', (select ok from ok_total), 'contratos_filtro', case when (select ok from ok_total) then (select n_filtro from tot) end) as x
  from dr d
  union all
  select jsonb_build_object('tipo', 'celda', 'cx', fin.cx, 'cy', fin.cy,
           'lon', round(st_x(st_transform(st_setsrid(st_makepoint((fin.cx + 0.5) * d.lado, (fin.cy + 0.5) * d.lado), 3116), 4326))::numeric, 5),
           'lat', round(st_y(st_transform(st_setsrid(st_makepoint((fin.cx + 0.5) * d.lado, (fin.cy + 0.5) * d.lado), 3116), 4326))::numeric, 5),
           'n', fin.n, 's', fin.s,
           'n8', case when fin.ok_8 then fin.n8 end, 's8', case when fin.ok_8 then fin.s8 end,
           'n60', case when fin.ok_60 then fin.n60 end, 's60', case when fin.ok_60 then fin.s60 end)
  from fin cross join dr d where fin.pub and (fin.n_m > 0 or p_medida = 'part60') and (select ok from ok_total)
  union all
  select jsonb_build_object('tipo', 'concilia', 'total_s', t.s_m, 'total_n', t.n_m, 'dibujada_s', b.dib_s, 'dibujada_n', b.dib_n,
           'no_dibujada_s', t.s_m - b.dib_s, 'no_dibujada_n', t.n_m - b.dib_n,
           'desglose', (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5),
           'menos5_s', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then b.lt5_s end,
           'menos5_n', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then b.lt5_n end,
           'sin_coord_s', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then s.s_m end,
           'sin_coord_n', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then s.n_m end,
           'anillo_s', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then b.an_s end,
           'anillo_n', case when (b.lt5_n = 0 or b.lt5_n >= 5) and (s.n_m = 0 or s.n_m >= 5) and (b.an_n = 0 or b.an_n >= 5) then b.an_n end)
  from tot t, bk b, sc s where (select ok from ok_total)
  union all
  select jsonb_build_object('tipo', 'corte', 'q1', q1, 'q2', q2, 'q3', q3, 'p95', p95, 'contratos', contratos, 'saldo', saldo)
  from bi_interno.cartera_mapa_periodo where periodo = p_periodo
) z
$$;

create or replace function bi.f_mapa_cartera_catalogo(p_periodo text)
returns jsonb language sql stable
set search_path = public, bi, bi_interno, pg_temp
as $$
select coalesce(jsonb_agg(x), '[]'::jsonb) from (
  select jsonb_build_object('tipo', 'comuna', 'id', comuna, 'nombre', case when comuna = 0 then 'Sin comuna' else 'Comuna ' || comuna end,
                            'contratos', case when count(*) >= 5 then count(*) end) as x
  from bi_interno.cartera_mapa_contrato where periodo = p_periodo group by comuna
  union all
  select jsonb_build_object('tipo', 'barrio', 'id', barrio_id, 'comuna', comuna,
                            'nombre', case barrio when 'OTROS BARRIOS' then 'Otros barrios' when 'SIN BARRIO' then 'Sin barrio' else barrio end,
                            'contratos', case when contratos >= 5 then contratos end)
  from bi_interno.cartera_mapa_barrio where periodo = p_periodo
  union all
  select jsonb_build_object('tipo', 'ciclo', 'id', ciclo, 'nombre', case when ciclo = 0 then 'Sin ciclo' else ciclo::text end,
                            'contratos', case when count(*) >= 5 then count(*) end)
  from bi_interno.cartera_mapa_contrato where periodo = p_periodo group by ciclo
  union all
  select jsonb_build_object('tipo', 'tramo', 'id', tramo, 'contratos', case when count(*) >= 5 then count(*) end)
  from bi_interno.cartera_mapa_contrato where periodo = p_periodo group by tramo
) z
$$;
revoke all on function bi.f_mapa_cartera(text, text, text, smallint[], integer[], smallint[], smallint[], smallint[]) from public, anon, authenticated;
revoke all on function bi.f_mapa_cartera_catalogo(text) from public, anon, authenticated;

-- =====================================================================
-- ROLLBACK (orden inverso; la Edge y la RPC primero)
-- =====================================================================
--  1) Edge geoportal-bi: git checkout 8878486 -- supabase/functions/geoportal-bi/index.ts y volver a desplegar (queda la v30, sin mapa; sin --no-verify-jwt).
--  2) RPC a 64 ramas y funciones de lectura (en este orden, desde el paquete paquete_mapa_cartera, fuera del repo):
--        psql -1 -f vivo_64_ORIGINAL.sql -f 07_rollback_paso4_funciones_lectura.sql
--     (vivo_64_ORIGINAL.sql es la RPC de 64 ramas tal como estaba; el segundo archivo retira bi.f_mapa_cartera y bi.f_mapa_cartera_catalogo; create or replace
--      conserva el ACL). Equivale a restaurar sql/05_rpc_puente.sql del commit anterior a la rama 65 y volver a ejecutarlo.
--     Solo para quitar el filtro de antiguedad (volver a la rama 65 sin tramos): psql -1 -f vivo_65_v2.sql -f rama_65_anteriores/03_funciones_lectura_v2_sin_tramos.sql
--     -f 07_rollback_paso4_a_v2.sql, del paquete paquete_mapa_antiguedad.
--  3) Despachador: quitar la rama 'bi_interno.cartera_mapa_contrato' y su limpieza (volver a la definicion de sql/49) y la entrada de cargar_hechos.py.
--  4) Datos y tablas:         drop function if exists bi.recalcular_cartera_mapa(text);
--                             drop table if exists bi_interno.cartera_mapa_contrato, bi_interno.cartera_mapa_barrio, bi_interno.cartera_mapa_periodo;
--     Solo la columna del tramo: alter table bi_interno.cartera_mapa_contrato drop column if exists tramo;  (y restaurar bi.recalcular_cartera_mapa sin tramo).
--  Historia de la rama 65 (para no restaurar la equivocada): la primera version (v1) validaba la lista de barrios con un contador de repeticion de 499, que
--  PostgreSQL rechaza (el limite es 255) y hacia fallar toda llamada con barrios; la vigente usa «*» mas un tope de 2500 caracteres y 500 elementos. La
--  primera version de la limpieza del despachador (NOT EXISTS correlacionado) tampoco debe restaurarse.
-- =====================================================================
