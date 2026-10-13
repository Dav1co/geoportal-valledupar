-- =====================================================================
-- 14_incremental.sql · Refresco INCREMENTAL por período
-- ---------------------------------------------------------------------
-- Convierte las cinco preagregadas de DETALLE de vista materializada a
-- TABLA, y añade una función de recálculo por período para cada una.
--
-- POR QUÉ: Postgres no permite refrescar parcialmente una materializada
-- (`REFRESH MATERIALIZED VIEW` rehace siempre todo; no existe
-- `REFRESH … WHERE`, ni se pueden particionar). Como estas fuentes
-- conservan 6 períodos y el cargue mensual solo cambia uno, refrescar
-- entero es recalcular cinco meses que no se movieron.
-- Medido: v_fact_detalle_dim tarda 43 s para UN período contra 254 s
-- completa. El cargue mensual baja de ~18 min a ~3,5 min.
--
-- QUÉ NO SE CONVIERTE: bi.v_kpi_mes (histórica, 43 períodos, 4 s) y
-- bi.v_tarifa_referencia (solo calcula el ancla, 40 s). Siguen siendo
-- materializadas con REFRESH … CONCURRENTLY.
--
-- LOS NOMBRES NO CAMBIAN: el RPC, la Edge Function y el frontend no se
-- tocan. Cambia el tipo de objeto, no su contrato.
--
-- ATOMICIDAD: cada recálculo hace delete + insert dentro de una
-- transacción, así que por MVCC quien consulte durante el recálculo
-- sigue viendo la versión anterior hasta el commit — la misma garantía
-- que daba REFRESH … CONCURRENTLY.
--
-- CONVERSIÓN SIN VENTANA SIN DATOS: se copia primero (create table as
-- select desde la materializada ya calculada, sin recalcular), luego se
-- borra la materializada y se renombra. Todo en una transacción por
-- objeto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) CONVERSIÓN matview -> tabla (copia, no recálculo)
-- ---------------------------------------------------------------------
begin;
create table bi.tmp_fact_detalle_dim as select * from bi.v_fact_detalle_dim;
drop materialized view bi.v_fact_detalle_dim;
alter table bi.tmp_fact_detalle_dim rename to v_fact_detalle_dim;
create unique index v_fact_detalle_dim_ux
  on bi.v_fact_detalle_dim (periodo, ciclo, uso, subcategoria, concepto_num);
create index v_fact_detalle_dim_periodo_ix on bi.v_fact_detalle_dim (periodo);
revoke all on bi.v_fact_detalle_dim from public, anon, authenticated;
commit;

begin;
create table bi.tmp_recaudo_diario_cierre as select * from bi.v_recaudo_diario_cierre;
drop materialized view bi.v_recaudo_diario_cierre;
alter table bi.tmp_recaudo_diario_cierre rename to v_recaudo_diario_cierre;
create unique index v_recaudo_diario_cierre_ux
  on bi.v_recaudo_diario_cierre (periodo, fecha);
revoke all on bi.v_recaudo_diario_cierre from public, anon, authenticated;
commit;

begin;
create table bi.tmp_recaudo_detalle_dim as select * from bi.v_recaudo_detalle_dim;
drop materialized view bi.v_recaudo_detalle_dim;
alter table bi.tmp_recaudo_detalle_dim rename to v_recaudo_detalle_dim;
create unique index v_recaudo_detalle_dim_ux
  on bi.v_recaudo_detalle_dim (periodo, fecha, concepto_num);
create index v_recaudo_detalle_dim_periodo_ix on bi.v_recaudo_detalle_dim (periodo);
revoke all on bi.v_recaudo_detalle_dim from public, anon, authenticated;
commit;

begin;
create table bi.tmp_cartera_detalle_dim as select * from bi.v_cartera_detalle_dim;
drop materialized view bi.v_cartera_detalle_dim;
alter table bi.tmp_cartera_detalle_dim rename to v_cartera_detalle_dim;
create unique index v_cartera_detalle_dim_ux
  on bi.v_cartera_detalle_dim (periodo, barrio, comuna, comuna_origen, ciclo, uso, subcategoria);
create index v_cartera_detalle_dim_periodo_ix on bi.v_cartera_detalle_dim (periodo);
revoke all on bi.v_cartera_detalle_dim from public, anon, authenticated;
commit;

begin;
create table bi.tmp_cartera_contratos_dim as select * from bi.v_cartera_contratos_dim;
drop materialized view bi.v_cartera_contratos_dim;
alter table bi.tmp_cartera_contratos_dim rename to v_cartera_contratos_dim;
create unique index v_cartera_contratos_dim_ux
  on bi.v_cartera_contratos_dim (periodo, ciclo, comuna, uso, estrato);
revoke all on bi.v_cartera_contratos_dim from public, anon, authenticated;
commit;

-- ---------------------------------------------------------------------
-- 2) FUNCIONES DE RECÁLCULO POR PERÍODO
-- Cada una: borra el período, lo reinserta con la MISMA definición del
-- archivo que creó la vista (11, 12 o 13), y devuelve las filas escritas.
-- ---------------------------------------------------------------------

create or replace function bi.recalcular_fact_detalle_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_fact_detalle_dim where periodo = p_periodo;
  insert into bi.v_fact_detalle_dim
  select
    periodo,
    coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
    coalesce(nullif(btrim(categoria), ''), '(sin uso)'),
    coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)'),
    concepto_num,
    count(distinct contrato),
    sum(facturado),
    sum(consumo)
  from bi_interno.v_facturacion_contratos
  where periodo = p_periodo and concepto_num is not null
  group by periodo,
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
           coalesce(nullif(btrim(categoria), ''), '(sin uso)'),
           coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)'),
           concepto_num;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function bi.recalcular_recaudo_diario_cierre(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_recaudo_diario_cierre where periodo = p_periodo;
  insert into bi.v_recaudo_diario_cierre
  with base as (
    select periodo, bi.f_fecha(fecha_grabacion) as fecha,
           bi.f_num(valor_recaudo) as valor, contrato
    from hechos.recaudo_detalle
    where periodo = p_periodo and bi.f_fecha(fecha_grabacion) is not null
  ),
  dia as (
    select periodo, fecha, sum(valor) valor_dia, count(*) transacciones,
           count(distinct contrato) contratos_pagaron
    from base group by periodo, fecha
  )
  select periodo, fecha,
         extract(day from fecha)::int,
         extract(isodow from fecha)::int,
         valor_dia, transacciones, contratos_pagaron,
         sum(valor_dia) over (partition by periodo order by fecha
                              rows between unbounded preceding and current row)
  from dia;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function bi.recalcular_recaudo_detalle_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_recaudo_detalle_dim where periodo = p_periodo;
  insert into bi.v_recaudo_detalle_dim
  select periodo, bi.f_fecha(fecha_grabacion), coalesce(bi.f_num(concepto_id), bi.f_num(concepto))::int,
         sum(bi.f_num(valor_recaudo)), count(*)
  from hechos.recaudo_detalle
  where periodo = p_periodo
    and bi.f_fecha(fecha_grabacion) is not null
    and coalesce(bi.f_num(concepto_id), bi.f_num(concepto)) is not null
  group by periodo, bi.f_fecha(fecha_grabacion), coalesce(bi.f_num(concepto_id), bi.f_num(concepto))::int;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function bi.recalcular_cartera_detalle_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cartera_detalle_dim where periodo = p_periodo;
  insert into bi.v_cartera_detalle_dim
  with e as (
    select ce.*,
      regexp_replace(upper(translate(btrim(ce.barrio),
        'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN')), '[^A-Z0-9]+', ' ', 'g') as barrio_norm
    from hechos.cartera_edades ce
    where ce.periodo = p_periodo
  )
  select
    periodo,
    coalesce(nullif(btrim(barrio), ''), '(sin barrio)'),
    coalesce(nullif(btrim(comuna), ''),
             'COMUNA ' || right(bc.comuna_catastro, 1), '(sin comuna)'),
    case
      when nullif(btrim(comuna), '') is not null then 'comercial'
      when bc.comuna_catastro is not null        then 'catastro'
      else 'sin dato'
    end,
    coalesce(bc.confiable, true),
    coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
    coalesce(nullif(btrim(categoria), ''), '(sin uso)'),
    coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)'),
    sum(bi.f_num(total)),
    sum(coalesce(bi.f_num(cf_cart0), 0) + coalesce(bi.f_num(cf_cart30), 0)),
    sum(coalesce(bi.f_num(cf_cart60), 0) + coalesce(bi.f_num(cf_cart90), 0)
      + coalesce(bi.f_num(cf_cart120), 0) + coalesce(bi.f_num(cf_cart150), 0)),
    sum(coalesce(bi.f_num(cf_cart180), 0) + coalesce(bi.f_num(cf_cart210), 0)
      + coalesce(bi.f_num(cf_cart240), 0) + coalesce(bi.f_num(cf_cart270), 0)
      + coalesce(bi.f_num(cf_cart300), 0) + coalesce(bi.f_num(cf_cart330), 0)),
    sum(coalesce(bi.f_num(cf_cart360), 0) + coalesce(bi.f_num(cf_cart720), 0)
      + coalesce(bi.f_num(cf_cart1080), 0) + coalesce(bi.f_num(cf_cart1440), 0)
      + coalesce(bi.f_num(cf_cart1800), 0) + coalesce(bi.f_num(cf_cartmay), 0))
  from e
  left join bi.v_barrio_comuna bc on bc.barrio_norm = e.barrio_norm
  group by periodo,
           coalesce(nullif(btrim(barrio), ''), '(sin barrio)'),
           coalesce(nullif(btrim(comuna), ''),
                    'COMUNA ' || right(bc.comuna_catastro, 1), '(sin comuna)'),
           case
             when nullif(btrim(comuna), '') is not null then 'comercial'
             when bc.comuna_catastro is not null        then 'catastro'
             else 'sin dato'
           end,
           coalesce(bc.confiable, true),
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
           coalesce(nullif(btrim(categoria), ''), '(sin uso)'),
           coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function bi.recalcular_cartera_contratos_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cartera_contratos_dim where periodo = p_periodo;
  insert into bi.v_cartera_contratos_dim
  select
    periodo,
    coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
    coalesce(nullif(btrim(comuna), ''), '(sin comuna)'),
    coalesce(nullif(btrim(uso), ''), '(sin uso)'),
    coalesce(nullif(btrim(estrato), ''), '(sin estrato)'),
    count(*),
    count(*) filter (where bi.f_num(total_cartera) > 0),
    sum(bi.f_num(total_cartera)),
    sum(bi.f_num(saldo_financiado)),
    sum(bi.f_num(facturas_vencidas))
  from hechos.cartera_contrato
  where periodo = p_periodo
  group by periodo,
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
           coalesce(nullif(btrim(comuna), ''), '(sin comuna)'),
           coalesce(nullif(btrim(uso), ''), '(sin uso)'),
           coalesce(nullif(btrim(estrato), ''), '(sin estrato)');
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 3) DESPACHADOR · el cargador solo conoce este punto de entrada.
-- CASE cerrado: un nombre no contemplado lanza excepción, nunca SQL
-- dinámico. Además limpia los períodos que la retención ya borró de la
-- fuente, para que no queden huérfanos en la tabla.
-- ---------------------------------------------------------------------
create or replace function bi.recalcular(p_tabla text, p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  if    p_tabla = 'bi.v_fact_detalle_dim'      then n := bi.recalcular_fact_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_diario_cierre' then n := bi.recalcular_recaudo_diario_cierre(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_detalle_dim'   then n := bi.recalcular_recaudo_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_detalle_dim'   then n := bi.recalcular_cartera_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_contratos_dim' then n := bi.recalcular_cartera_contratos_dim(p_periodo);
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
  end if;

  return n;
end $$;

revoke all on function bi.recalcular(text, text) from public, anon, authenticated;

-- =====================================================================
-- RECONSTRUCCIÓN TOTAL · la red de seguridad
-- ---------------------------------------------------------------------
-- Si una tabla queda desincronizada (alguien cargó sin pasar por el
-- cargador, o un recálculo falló a medias), esto la reconstruye entera
-- desde la fuente. Es idempotente y se puede correr en caliente.
-- Ejecutar con psql (tarda minutos) y `set statement_timeout='30min'`:
--
--   do $$
--   declare t text; p text;
--   begin
--     foreach t in array array['bi.v_fact_detalle_dim','bi.v_recaudo_diario_cierre',
--                              'bi.v_recaudo_detalle_dim','bi.v_cartera_detalle_dim',
--                              'bi.v_cartera_contratos_dim'] loop
--       for p in
--         select distinct periodo from hechos.facturacion_contratos where t = 'bi.v_fact_detalle_dim'
--         union select distinct periodo from hechos.recaudo_detalle
--           where t in ('bi.v_recaudo_diario_cierre','bi.v_recaudo_detalle_dim')
--         union select distinct periodo from hechos.cartera_edades where t = 'bi.v_cartera_detalle_dim'
--         union select distinct periodo from hechos.cartera_contrato where t = 'bi.v_cartera_contratos_dim'
--       loop
--         perform bi.recalcular(t, p);
--         raise notice '% % listo', t, p;
--       end loop;
--     end loop;
--   end $$;
--
-- VERIFICACIÓN de sincronía (debe devolver CERO filas):
--   select 'v_fact_detalle_dim' tabla, periodo from (
--     select distinct periodo from hechos.facturacion_contratos
--     except select distinct periodo from bi.v_fact_detalle_dim) x
--   union all select 'v_recaudo_detalle_dim', periodo from (
--     select distinct periodo from hechos.recaudo_detalle
--     except select distinct periodo from bi.v_recaudo_detalle_dim) x
--   union all select 'v_cartera_detalle_dim', periodo from (
--     select distinct periodo from hechos.cartera_edades
--     except select distinct periodo from bi.v_cartera_detalle_dim) x
--   union all select 'v_cartera_contratos_dim', periodo from (
--     select distinct periodo from hechos.cartera_contrato
--     except select distinct periodo from bi.v_cartera_contratos_dim) x;
-- =====================================================================
