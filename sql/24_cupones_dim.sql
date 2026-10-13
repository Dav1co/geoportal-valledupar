-- =====================================================================
-- 24_cupones_dim.sql · bi.v_cupones_mes pasa a leerse de una tabla resumen
-- ---------------------------------------------------------------------
-- PROBLEMA: bi.v_cupones_mes agregaba hechos.cupones_pagos completa
-- (~620.000 filas, 8 periodos) con percentile_cont en cada consulta:
-- 33 s contra el statement_timeout de service_role (30 s), que es el rol
-- con el que la Edge Function geoportal-bi llama al RPC. Tambien la paga
-- bi.v_consolidado_mes, que hace left join con esta vista.
--
-- SOLUCION (mismo patron de las otras dim): tabla bi.v_cupones_mes_dim,
-- poblada por bi.recalcular_cupones_mes_dim(periodo) -borra y reinserta-,
-- y bi.v_cupones_mes queda como vista delgada sobre ella con EXACTAMENTE
-- las mismas 10 columnas y tipos. RPC, Edge Function, frontend y
-- v_consolidado_mes no cambian. bi.v_cupones_canal no se toca (1,2 s con
-- filtro de periodo, que es como siempre se pide).
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga por periodo
--   4) EXCEPT tabla vs vista vieja = 0   5) swap de la vista
-- Integracion en cargar_hechos.py: entrada bi.v_cupones_mes_dim en
-- VISTAS_TABLERO (fuente 'cupones', modo periodo, suma al peso).
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
-- Columnas, orden y tipos tomados de information_schema.columns de la
-- vista vigente. El default privileges de bi solo da SELECT a claude_ro;
-- el revoke es explicito para que no dependa de ello.
create table bi.v_cupones_mes_dim (
  periodo             text primary key,
  anio                integer,
  mes                 integer,
  cupones             bigint,
  valor               numeric,
  ticket_promedio     numeric,
  ticket_mediano      numeric,
  entidades           bigint,
  rezago_dias         numeric,
  cupones_rezago_alto bigint
);
revoke all on bi.v_cupones_mes_dim from public, anon, authenticated;

create or replace function bi.recalcular_cupones_mes_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cupones_mes_dim where periodo = p_periodo;
  insert into bi.v_cupones_mes_dim
  select periodo,
         ("left"(periodo, 4))::integer,
         ("right"(periodo, 2))::integer,
         count(*),
         sum(bi.f_num(valor)),
         round(avg(bi.f_num(valor)), 0),
         round((percentile_cont((0.5)::double precision) within group
                (order by ((bi.f_num(valor))::double precision)))::numeric, 0),
         count(distinct entidad),
         round(avg((bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago))), 2),
         count(*) filter (where ((bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago)) > 3))
  from hechos.cupones_pagos
  where periodo = p_periodo
  group by periodo;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cupones_mes_dim(text) from public, anon, authenticated;

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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial, uno por uno ------------------------------
--   select bi.recalcular_cupones_mes_dim('202602');  ... hasta '202609'

-- >>> PASO 4 · equivalencia (debe dar 0 filas en ambos sentidos) -------
--   select * from bi.v_cupones_mes except select * from bi.v_cupones_mes_dim;
--   select * from bi.v_cupones_mes_dim except select * from bi.v_cupones_mes;
-- (solo valido ANTES del swap: despues ambas leen la misma tabla)

-- >>> PASO 5 · swap a vista delgada --------------------------------------
-- No se hace revoke ni grant sobre la vista: create or replace conserva
-- su ACL (comprobado antes/despues: {postgres=arwdDxtm/postgres,claude_ro=r/postgres}).
create or replace view bi.v_cupones_mes as
select periodo, anio, mes, cupones, valor, ticket_promedio, ticket_mediano,
       entidades, rezago_dias, cupones_rezago_alto
from bi.v_cupones_mes_dim;

-- ROLLBACK del swap (restaura la definicion previa, agregando en vivo):
-- create or replace view bi.v_cupones_mes as
--  select periodo,
--    ("left"(periodo, 4))::integer as anio,
--    ("right"(periodo, 2))::integer as mes,
--    count(*) as cupones,
--    sum(bi.f_num(valor)) as valor,
--    round(avg(bi.f_num(valor)), 0) as ticket_promedio,
--    round((percentile_cont((0.5)::double precision) within group
--           (order by ((bi.f_num(valor))::double precision)))::numeric, 0) as ticket_mediano,
--    count(distinct entidad) as entidades,
--    round(avg((bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago))), 2) as rezago_dias,
--    count(*) filter (where ((bi.f_fecha(fecha_grabacion) - bi.f_fecha(fecha_pago)) > 3)) as cupones_rezago_alto
--  from hechos.cupones_pagos
--  group by periodo;
