-- =====================================================================
-- 39_submedicion_dim.sql · Submedicion por vejez del medidor: referencia por estrato, perdidas por ciclo y por rango
-- ---------------------------------------------------------------------
-- Alimenta el analisis de submedicion por vejez del medidor: cuanto menos consume, en promedio, un medidor viejo
-- que uno nuevo del mismo estrato, y cuantos m3 y pesos representa. Fuente: hechos.consumo_metodo (consumo,
-- medidor, observacion, funcion, fecha de instalacion) y hechos.facturacion_contratos (tarifa por m3).
--
-- UNIVERSO (UNIVERSO TRUNCADO): residencial, medidor registrado, observacion 99 y funcion CALCCODL, UN registro por
-- contrato (con medidor, luego con lectura, luego mayor consumo cobrado), antiguedad contada al CIERRE del periodo
-- (ultimo dia del mes, en anos cumplidos) y 0 < consumo_cargos <= v_max_m3 (100 m3). Los contratos con consumo 0 o
-- mayor que 100 NO entran a la referencia, a la media de los de vejez, a las perdidas, al exceso ni a la tabla de
-- rangos; se cuentan aparte (contratos_cero y contratos_sobre_max) para no esconderlos. No hay tope ni winsorizacion.
-- Se usa consumo_cargos y no consumo_facturado: consumo_facturado es NULO justo para los contratos con consumo cobrado
-- igual a 0.
-- La referencia es el PROMEDIO (media) del consumo del universo. No se guardan medianas ni percentiles en ninguna tabla.
-- Cuando falta la referencia el valor es NULL, nunca cero (CASE, no GREATEST).
-- Periodos con antiguedad: desde 202605 (antes la fecha de instalacion viene vacia); 202601 a 202604 no se calculan
-- y no es un error (0 filas).
--
-- bi.v_submedicion_ref_dim · GRANO: periodo x estrato x banda_antig
--  · banda_antig: 0-3, 3-5, 5-10, 10-15, '>15 (fecha real)', '>15 (1986-01-01)' (fecha centinela, antiguedad real
--    desconocida) y 'Sin fecha' (fecha nula o posterior al cierre).
--  · contratos_medidor: residenciales con medidor y consumo_cargos no nulo en la banda, de TODOS los metodos y de
--    cualquier consumo. contratos: los del universo (0 < consumo <= 100). contratos_cero y contratos_sobre_max: los de
--    observacion 99 y CALCCODL con consumo = 0 y con consumo > 100. contratos_promedio: los facturados por promedio
--    (OBTECOPP, OBTECOPS o [FAMC]) entre los residenciales con medidor.
--  · m3_consumo: suma de consumo_cargos del universo.
--  · ref_nuevos_media_m3 y n_nuevos: promedio y numero de los medidores de menos de 3 anos del estrato en el periodo (se
--    repiten en todas las filas del periodo y estrato); NULL si n_nuevos < 30.
--  · media_vejez_m3 y n_vejez: lo mismo para los medidores de VEJEZ, de 3 anos o mas (3-5, 5-10, 10-15 y >15); NULL si
--    n_vejez < 30. 'Sin fecha' no entra a ninguno de los dos grupos (v_edad_nuevo = 3 y v_edad_vejez = 3 en la funcion).
--  · contratos_bajo_ref (consumo menor que la referencia), m3_perdidos_bruta (suma de max(ref - consumo, 0)) y m3_exceso
--    (suma de max(consumo - ref, 0)); la brecha neta de la banda es bruta - exceso.
-- bi.v_submedicion_ciclo_dim · GRANO: periodo x ciclo x estrato, SOLO SUMAS
--  · contratos, m3_consumo, contratos_bajo_ref, m3_perdidos_bruta, m3_exceso, contratos_vejez y
--    m3_perdidos_atrib = suma, sobre los contratos de vejez, de (ref_nuevos_media_m3 - consumo), SIN truncar a cero; es igual
--    a contratos_vejez * (ref_nuevos_media_m3 - media_vejez_m3). NULL si falta la referencia.
-- bi.v_submedicion_rango_dim · GRANO: periodo x ciclo x estrato x rango_m3
--  · rango_m3 con los rangos del dashboard dentro del universo (1-5, 6-10, 11-15, 16-20, 21-30, 31-40, 41-60 y 61-100;
--    limite superior inclusivo; sin 0 y sin >100). contratos, m3_consumo, contratos_bajo_ref, m3_perdidos_bruta.
--  · En las tres: tarifa_m3 = (facturado de los conceptos 2- y 4-) / (consumo del concepto 2-) de
--    facturacion_contratos del periodo; max_m3 (100); calculado_en. Perdida en pesos = m3 * tarifa_m3.
--
-- Costo: lee consumo_metodo (~112 mil filas) y facturacion_contratos (~1,2 millones de lineas) del periodo; del orden
-- de 1 min. Cada periodo se recalcula con begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- Sin DROP ni TRUNCATE de tablas. ROLLBACK: delete de las tres tablas; las tablas y la funcion se pueden dejar. El
-- despachador anterior se guarda antes de aplicar.
-- Orden (cada paso con aprobacion):  1) tablas + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tablas, funcion, permisos --------------------------------
create table bi.v_submedicion_ref_dim (
  periodo              text,
  estrato              text,
  banda_antig          text,
  contratos_medidor    bigint,
  contratos            bigint,
  contratos_promedio   bigint,
  m3_consumo           numeric,
  ref_nuevos_media_m3  numeric,
  n_nuevos             bigint,
  media_vejez_m3       numeric,
  n_vejez              bigint,
  tarifa_m3            numeric,
  contratos_bajo_ref   bigint,
  m3_perdidos_bruta    numeric,
  m3_exceso            numeric,
  max_m3               numeric,
  calculado_en         timestamptz,
  contratos_cero       bigint,
  contratos_sobre_max  bigint,
  primary key (periodo, estrato, banda_antig)
);
revoke all on bi.v_submedicion_ref_dim from public, anon, authenticated;

create table bi.v_submedicion_ciclo_dim (
  periodo            text,
  ciclo              text,
  estrato            text,
  contratos          bigint,
  m3_consumo         numeric,
  m3_perdidos_bruta  numeric,
  contratos_vejez    bigint,
  m3_perdidos_atrib  numeric,
  tarifa_m3          numeric,
  contratos_bajo_ref bigint,
  m3_exceso          numeric,
  max_m3             numeric,
  calculado_en       timestamptz,
  primary key (periodo, ciclo, estrato)
);
revoke all on bi.v_submedicion_ciclo_dim from public, anon, authenticated;

create table bi.v_submedicion_rango_dim (
  periodo            text,
  ciclo              text,
  estrato            text,
  rango_m3           text,
  contratos          bigint,
  m3_consumo         numeric,
  contratos_bajo_ref bigint,
  m3_perdidos_bruta  numeric,
  tarifa_m3          numeric,
  max_m3             numeric,
  calculado_en       timestamptz,
  primary key (periodo, ciclo, estrato, rango_m3)
);
revoke all on bi.v_submedicion_rango_dim from public, anon, authenticated;

-- BASE VIVA: las tablas se crearon antes con otras columnas (medianas, tope); se adaptan con ALTER (el ACL no cambia) y se
-- recalculan. En una instalacion nueva este bloque no hace nada.
do $$
declare t text;
begin
  foreach t in array array['v_submedicion_ref_dim','v_submedicion_ciclo_dim','v_submedicion_rango_dim'] loop
    if exists (select 1 from information_schema.columns where table_schema='bi' and table_name=t and column_name='tope_m3') then
      execute format('alter table bi.%I rename column tope_m3 to max_m3', t);
    end if;
  end loop;
  foreach t in array array['v_submedicion_ref_dim','v_submedicion_ciclo_dim'] loop
    if exists (select 1 from information_schema.columns where table_schema='bi' and table_name=t and column_name='m3_consumo_tope') then
      execute format('alter table bi.%I drop column m3_consumo_tope', t);
    end if;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema='bi' and table_name='v_submedicion_ref_dim' and column_name='contratos_sobre_tope') then
    alter table bi.v_submedicion_ref_dim drop column contratos_sobre_tope;
  end if;
  -- vejez = 3 anos o mas (antes: 10 anos o mas)
  if exists (select 1 from information_schema.columns where table_schema='bi' and table_name='v_submedicion_ref_dim' and column_name='media_10mas_m3') then
    alter table bi.v_submedicion_ref_dim rename column media_10mas_m3 to media_vejez_m3;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='bi' and table_name='v_submedicion_ref_dim' and column_name='n_10mas') then
    alter table bi.v_submedicion_ref_dim rename column n_10mas to n_vejez;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='bi' and table_name='v_submedicion_ciclo_dim' and column_name='contratos_10mas') then
    alter table bi.v_submedicion_ciclo_dim rename column contratos_10mas to contratos_vejez;
  end if;
end $$;
alter table bi.v_submedicion_ref_dim add column if not exists contratos_cero bigint, add column if not exists contratos_sobre_max bigint;

create or replace function bi.recalcular_submedicion(p_periodo text)
returns integer language plpgsql as $$
declare
  v_max_m3      constant numeric := 100;   -- LIMITE del universo (m3/contrato): entran 0 < consumo_cargos <= v_max_m3
  v_edad_nuevo  constant integer := 3;     -- NUEVO = menos de v_edad_nuevo anos cumplidos al cierre (la referencia es su media)
  v_edad_vejez  constant integer := 3;     -- VEJEZ = v_edad_vejez anos cumplidos o mas ('Sin fecha' no entra a ninguno)
  v_cierre date;
  v_tar    numeric;
  n1       integer;
  n2       integer;
  n3       integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  delete from bi.v_submedicion_ref_dim   where periodo = p_periodo;
  delete from bi.v_submedicion_ciclo_dim where periodo = p_periodo;
  delete from bi.v_submedicion_rango_dim where periodo = p_periodo;
  if p_periodo < '202605'
     or not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo)
     or not exists (select 1 from hechos.facturacion_contratos where periodo = p_periodo) then
    return 0;   -- sin antiguedad (202601 a 202604) o sin una de las fuentes: 0 filas es lo correcto
  end if;
  v_cierre := (to_date(p_periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;
  select sum(bi.f_num(facturado)) filter (where btrim(concepto) ~ '^[24]\s*-')
         / nullif(sum(bi.f_num(consumo)) filter (where btrim(concepto) ~ '^2\s*-'), 0)
    into v_tar
  from hechos.facturacion_contratos where periodo = p_periodo;

  with r as materialized (
    select distinct on (contrato)
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as uso,
           case when btrim(coalesce(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+','')) end as estrato,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           substring(upper(btrim(observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(funcion)) as fn,
           case when fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(fecha_instalacion, 10)::date end as fi,
           bi.f_num(consumo_cargos) as cc
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion),
  b as materialized (
    select ciclo, estrato, cc,
           (cod = 99 and fn ~ '^CALCCODL' and cc > 0 and cc <= v_max_m3) as en_univ,
           (cod = 99 and fn ~ '^CALCCODL' and cc = 0) as en_cero,
           (cod = 99 and fn ~ '^CALCCODL' and cc > v_max_m3) as en_sobre,
           (fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]') as es_prom,
           case when fi is null or fi > v_cierre then 'Sin fecha'
                when extract(year from age(v_cierre, fi)) < v_edad_nuevo then '0-3'
                when extract(year from age(v_cierre, fi)) < 5  then '3-5'
                when extract(year from age(v_cierre, fi)) < 10 then '5-10'
                when extract(year from age(v_cierre, fi)) < 15 then '10-15'
                when fi = date '1986-01-01' then '>15 (1986-01-01)'
                else '>15 (fecha real)' end as banda,
           case when fi is null or fi > v_cierre then null else extract(year from age(v_cierre, fi))::int end as anios
    from r where uso = 'Residencial' and con_med and cc is not null),
  nue as materialized (
    select estrato, count(*) as n, avg(cc) as media from b where en_univ and anios < v_edad_nuevo group by estrato),
  vie as materialized (
    select estrato, count(*) as n, avg(cc) as media from b where en_univ and anios >= v_edad_vejez group by estrato),
  ref as (select estrato, case when n >= 30 then media end as ref_nuevos, n as n_nuevos from nue),
  mvej as (select estrato, case when n >= 30 then media end as media_vej, n as n_vej from vie),
  uu as materialized (
    select b.*, rf.ref_nuevos, m.media_vej
    from b left join ref rf on rf.estrato = b.estrato left join mvej m on m.estrato = b.estrato),
  i1 as (
    insert into bi.v_submedicion_ref_dim
      (periodo, estrato, banda_antig, contratos_medidor, contratos, contratos_promedio, m3_consumo, ref_nuevos_media_m3,
       n_nuevos, media_vejez_m3, n_vejez, tarifa_m3, contratos_bajo_ref, m3_perdidos_bruta, m3_exceso, max_m3,
       calculado_en, contratos_cero, contratos_sobre_max)
    select p_periodo, uu.estrato, uu.banda,
           count(*), count(*) filter (where uu.en_univ), count(*) filter (where uu.es_prom),
           sum(uu.cc) filter (where uu.en_univ),
           uu.ref_nuevos, coalesce(max(rf.n_nuevos), 0), uu.media_vej, coalesce(max(m.n_vej), 0), v_tar,
           case when uu.ref_nuevos is null then null else count(*) filter (where uu.en_univ and uu.cc < uu.ref_nuevos) end,
           case when uu.ref_nuevos is null then null else coalesce(sum(greatest(uu.ref_nuevos - uu.cc, 0)) filter (where uu.en_univ), 0) end,
           case when uu.ref_nuevos is null then null else coalesce(sum(greatest(uu.cc - uu.ref_nuevos, 0)) filter (where uu.en_univ), 0) end,
           v_max_m3, now(), count(*) filter (where uu.en_cero), count(*) filter (where uu.en_sobre)
    from uu left join ref rf on rf.estrato = uu.estrato left join mvej m on m.estrato = uu.estrato
    group by uu.estrato, uu.banda, uu.ref_nuevos, uu.media_vej
    returning 1),
  i3 as (
    insert into bi.v_submedicion_rango_dim
      (periodo, ciclo, estrato, rango_m3, contratos, m3_consumo, contratos_bajo_ref, m3_perdidos_bruta, tarifa_m3, max_m3, calculado_en)
    select p_periodo, u.ciclo, u.estrato,
           case when u.cc <= 5 then '1-5' when u.cc <= 10 then '6-10' when u.cc <= 15 then '11-15' when u.cc <= 20 then '16-20'
                when u.cc <= 30 then '21-30' when u.cc <= 40 then '31-40' when u.cc <= 60 then '41-60' else '61-100' end,
           count(*), sum(u.cc),
           case when u.ref_nuevos is null then null else count(*) filter (where u.cc < u.ref_nuevos) end,
           case when u.ref_nuevos is null then null else sum(greatest(u.ref_nuevos - u.cc, 0)) end,
           v_tar, v_max_m3, now()
    from uu u where u.en_univ
    group by u.ciclo, u.estrato, u.ref_nuevos,
             case when u.cc <= 5 then '1-5' when u.cc <= 10 then '6-10' when u.cc <= 15 then '11-15' when u.cc <= 20 then '16-20'
                  when u.cc <= 30 then '21-30' when u.cc <= 40 then '31-40' when u.cc <= 60 then '41-60' else '61-100' end
    returning 1)
  insert into bi.v_submedicion_ciclo_dim
    (periodo, ciclo, estrato, contratos, m3_consumo, m3_perdidos_bruta, contratos_vejez, m3_perdidos_atrib, tarifa_m3,
     contratos_bajo_ref, m3_exceso, max_m3, calculado_en)
  select p_periodo, u.ciclo, u.estrato, count(*), sum(u.cc),
         case when u.ref_nuevos is null then null else sum(greatest(u.ref_nuevos - u.cc, 0)) end,
         count(*) filter (where u.anios >= v_edad_vejez),
         case when u.ref_nuevos is null then null
              else coalesce(sum(u.ref_nuevos - u.cc) filter (where u.anios >= v_edad_vejez), 0) end,
         v_tar,
         case when u.ref_nuevos is null then null else count(*) filter (where u.cc < u.ref_nuevos) end,
         case when u.ref_nuevos is null then null else sum(greatest(u.cc - u.ref_nuevos, 0)) end,
         v_max_m3, now()
  from uu u where u.en_univ
  group by u.ciclo, u.estrato, u.ref_nuevos, u.media_vej;

  select count(*) into n1 from bi.v_submedicion_ref_dim   where periodo = p_periodo;
  select count(*) into n2 from bi.v_submedicion_ciclo_dim where periodo = p_periodo;
  select count(*) into n3 from bi.v_submedicion_rango_dim where periodo = p_periodo;
  return n1 + n2 + n3;
end $$;
revoke all on function bi.recalcular_submedicion(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama (las tres tablas se llenan juntas) y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X). OJO: este texto es la copia PUBLICADA del despachador mas las ramas
-- nuevas; el despachador VIVO de la base tiene ramas adicionales (piezas no publicadas) y por eso se aplico tomando su
-- definicion viva e insertando solo las lineas nuevas, NO ejecutando este bloque tal cual.
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
-- Un periodo por vez (el recalculo llena las tres tablas):
--   begin; set local statement_timeout = '300s'; select bi.recalcular('bi.v_submedicion_ref_dim', '202605'); commit;
-- Periodos con antiguedad: 202605, 202607, 202608 y 202609.

-- >>> PASO 4 · controles ------------------------------------------------
--   EXCEPT en ambos sentidos, periodo por periodo, contra una consulta de referencia independiente (otra desduplicacion y
--   otra agrupacion), para cada tabla. Controles: contratos + contratos_cero + contratos_sobre_max = contratos de
--   observacion 99 y CALCCODL con consumo no nulo (72.737 / 72.091 / 70.809 / 71.414 en 202605 / 07 / 08 / 09);
--   tarifa de 202608 = 2.669,79; contratos iguales en las tres tablas; m3_perdidos_bruta igual en las tres; y por estrato,
--   bruta - exceso de las bandas de vejez (3 anos o mas) = n_vejez * (ref_nuevos_media_m3 - media_vejez_m3); la banda 0-3
--   tiene brecha neta 0 (la referencia es su media); y la atribuible acumulada por edad minima (3, 5 y 10 anos) sale de
--   sumar bruta - exceso de las bandas correspondientes.
