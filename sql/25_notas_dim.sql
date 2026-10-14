-- =====================================================================
-- 25_notas_dim.sql · bi.v_notas_mes pasa a leerse de una tabla resumen
-- ---------------------------------------------------------------------
-- PROBLEMA: bi.v_notas_mes agregaba bi_interno.v_notas (~280.000 notas,
-- 45 periodos, con el casteo de hechos.notas en cada consulta): 15,7 s
-- netos medidos contra el statement_timeout de service_role (30 s), el
-- rol con el que la Edge Function geoportal-bi llama al RPC. Mismo
-- patron que sql/24_cupones_dim.sql.
--
-- SOLUCION: tabla bi.v_notas_mes_dim, poblada por
-- bi.recalcular_notas_mes_dim(periodo) -borra y reinserta-, y
-- bi.v_notas_mes queda como vista delgada con EXACTAMENTE las mismas 11
-- columnas y tipos. RPC, Edge Function, frontend y las vistas que
-- dependen de ella (v_consolidado_mes, v_notas_vs_pqr) no cambian.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga por periodo
--   4) EXCEPT tabla vs vista vieja = 0   5) swap de la vista
-- Integracion en cargar_hechos.py: entrada bi.v_notas_mes_dim en
-- VISTAS_TABLERO (fuente 'notas', modo periodo).
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
-- Columnas, orden y tipos tomados de information_schema.columns de la
-- vista vigente. El default privileges de bi solo da SELECT a claude_ro;
-- el revoke es explicito para que no dependa de ello.
create table bi.v_notas_mes_dim (
  periodo             text primary key,
  anio                integer,
  mes                 integer,
  notas               bigint,
  notas_credito       bigint,
  notas_debito        bigint,
  valor_neto          numeric,
  valor_credito       numeric,
  valor_debito        numeric,
  valor_credito_abs   numeric,
  contratos_afectados bigint
);
revoke all on bi.v_notas_mes_dim from public, anon, authenticated;

create or replace function bi.recalcular_notas_mes_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_notas_mes_dim where periodo = p_periodo;
  insert into bi.v_notas_mes_dim
  select periodo,
         ("left"(periodo, 4))::integer,
         ("right"(periodo, 2))::integer,
         count(*),
         count(*) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text)),
         count(*) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'DB'::text)),
         sum(valor),
         sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text)),
         sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'DB'::text)),
         abs(sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text))),
         count(distinct contrato)
  from bi_interno.v_notas
  where periodo = p_periodo
  group by periodo;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_notas_mes_dim(text) from public, anon, authenticated;

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
  elsif p_tabla = 'bi.v_notas_mes_dim'         then n := bi.recalcular_notas_mes_dim(p_periodo);
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial, uno por uno ------------------------------
--   select bi.recalcular_notas_mes_dim('202301');  ... hasta '202609'

-- >>> PASO 4 · equivalencia (debe dar 0 filas en ambos sentidos) -------
--   select * from bi.v_notas_mes except select * from bi.v_notas_mes_dim;
--   select * from bi.v_notas_mes_dim except select * from bi.v_notas_mes;
-- (solo valido ANTES del swap: despues ambas leen la misma tabla)

-- >>> PASO 5 · swap a vista delgada --------------------------------------
-- No se hace revoke ni grant sobre la vista: create or replace conserva
-- su ACL ({postgres=arwdDxtm/postgres,claude_ro=r/postgres}).
create or replace view bi.v_notas_mes as
select periodo, anio, mes, notas, notas_credito, notas_debito, valor_neto,
       valor_credito, valor_debito, valor_credito_abs, contratos_afectados
from bi.v_notas_mes_dim;

-- ROLLBACK del swap (restaura la definicion previa, agregando en vivo):
-- create or replace view bi.v_notas_mes as
--  select periodo,
--    ("left"(periodo, 4))::integer as anio,
--    ("right"(periodo, 2))::integer as mes,
--    count(*) as notas,
--    count(*) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text)) as notas_credito,
--    count(*) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'DB'::text)) as notas_debito,
--    sum(valor) as valor_neto,
--    sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text)) as valor_credito,
--    sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'DB'::text)) as valor_debito,
--    abs(sum(valor) filter (where (upper(coalesce(tipo_signo, ''::text)) = 'CR'::text))) as valor_credito_abs,
--    count(distinct contrato) as contratos_afectados
--  from bi_interno.v_notas
--  group by periodo;
