-- =====================================================================
-- 40_reclamo_metodo_dim.sql · Reclamos (solicitudes) segun el metodo de facturacion
-- ---------------------------------------------------------------------
-- Mide cuantos reclamos genera cada tipo de facturacion (lectura real, promedio, etc.) para probar si el medidor y el
-- promedio explican la carga de reclamos. Fuentes: hechos.consumo_metodo (todos los contratos del periodo, un registro por
-- contrato) y hechos.reclamos (SOLO periodo, contrato, solicitud y causal; ningun dato personal ni texto
-- libre).
--
-- GRANO: periodo x ciclo x uso x estrato x metodo_act x metodo_ant x banda_antig
--  · metodo_act (periodo) y metodo_ant (periodo anterior disponible de consumo_metodo, como en sql/38; 202607 se compara con
--    202605): 'lectura' (observacion 99 y funcion CALCCODL), 'promedio' (OBTECOPP, OBTECOPS o [FAMC], con medidor),
--    'promedio_sin_medidor' (las mismas funciones, sin medidor registrado), 'modificacion_directa' ([FOVC] o [FAJF]) y 'otro'
--    (el resto: ESTACONS, OBTECOAF, etc.). metodo_ant vale 'sin_dato' si el contrato no estaba en el periodo anterior.
--  · banda_antig: antiguedad del medidor al CIERRE del periodo (bandas de sql/39: 0-3, 3-5, 5-10, 10-15, '>15 (fecha real)',
--    '>15 (1986-01-01)', 'Sin fecha'), y 'Sin medidor' para los contratos sin medidor registrado.
--  · ciclo, uso y estrato: los del periodo actual (reglas de sql/29).
--  · Grupos de causal, por el codigo de 4 digitos al inicio del texto: consumo = 1102, 1121, 1127, 1129, 1101; promedio = 1120;
--    medidor = 1110; otras = todo lo demas (incluidas las causales sin codigo). El grupo 'otras' se abre ademas en tres subgrupos:
--    solicitudes_desocupado (1114), solicitudes_cartera (1111) y solicitudes_admin (1315); solicitudes_otras sigue siendo el
--    TOTAL del grupo (incluye las tres), asi que el resto de 'otras' = solicitudes_otras - las tres.
--  · contratos = todos los contratos del periodo en la celda (denominador). solicitudes_consumo / _promedio / _medidor /
--    _otras = solicitudes DISTINTAS por contrato, periodo y grupo. contratos_con_reclamo = contratos con al menos una
--    solicitud de cualquier grupo; contratos_con_rec_consumo_prom = con al menos una de los grupos consumo o promedio.
--  · FILA DE CONTROL: los reclamos de contratos que no estan en consumo_metodo del periodo van a una fila con ciclo, uso,
--    estrato, metodo_act, metodo_ant y banda_antig = 'Sin base', contratos = 0 y los dos conteos de contratos en 0 (solo lleva
--    solicitudes), para que el total de solicitudes del periodo cuadre con hechos.reclamos.
--  · Periodos: 202602 a 202609 que tengan consumo_metodo y periodo anterior disponible. 202606 no existe en consumo_metodo (no se
--    calcula y sus reclamos no se usan); 202607 usa 202605.
-- Las expresiones de metodo de facturacion (sql/38) y de antiguedad (sql/39) se reutilizan, no se reinventan.
--
-- Costo: lee consumo_metodo de dos periodos (~112 mil filas) y reclamos (~600 filas); unos 10 s por periodo. Cada periodo se
-- recalcula con begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- Sin DROP ni TRUNCATE. ROLLBACK: delete from bi.v_reclamo_metodo_dim; la tabla y la funcion se pueden dejar.
-- Orden (cada paso con aprobacion):  1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_reclamo_metodo_dim (
  periodo                         text,
  ciclo                           text,
  uso                             text,
  estrato                         text,
  metodo_act                      text,
  metodo_ant                      text,
  banda_antig                     text,
  contratos                       bigint,
  solicitudes_consumo             bigint,
  solicitudes_promedio            bigint,
  solicitudes_medidor             bigint,
  solicitudes_otras               bigint,
  contratos_con_reclamo           bigint,
  contratos_con_rec_consumo_prom  bigint,
  calculado_en                    timestamptz,
  solicitudes_desocupado          bigint,
  solicitudes_cartera             bigint,
  solicitudes_admin               bigint,
  primary key (periodo, ciclo, uso, estrato, metodo_act, metodo_ant, banda_antig)
);
revoke all on bi.v_reclamo_metodo_dim from public, anon, authenticated;
-- BASE VIVA: la tabla se creo antes sin los tres subgrupos de 'otras'; se amplia con ALTER (el ACL no cambia) y se recalcula.
-- En una instalacion nueva este bloque no hace nada.
alter table bi.v_reclamo_metodo_dim
  add column if not exists solicitudes_desocupado bigint, add column if not exists solicitudes_cartera bigint,
  add column if not exists solicitudes_admin bigint;

create or replace function bi.recalcular_reclamo_metodo(p_periodo text)
returns integer language plpgsql as $$
declare
  v_ant     text;
  v_cierre  date;
  n         integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  delete from bi.v_reclamo_metodo_dim where periodo = p_periodo;
  if p_periodo < '202602' or not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo) then
    return 0;
  end if;
  select max(periodo) into v_ant from hechos.consumo_metodo where periodo < p_periodo;
  if v_ant is null then
    return 0;   -- sin periodo anterior disponible no se calcula (0 filas es lo correcto)
  end if;
  v_cierre := (to_date(p_periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;

  insert into bi.v_reclamo_metodo_dim
    (periodo, ciclo, uso, estrato, metodo_act, metodo_ant, banda_antig, contratos, solicitudes_consumo, solicitudes_promedio,
     solicitudes_medidor, solicitudes_otras, contratos_con_reclamo, contratos_con_rec_consumo_prom, calculado_en,
     solicitudes_desocupado, solicitudes_cartera, solicitudes_admin)
  with r as materialized (
    select p.periodo, p.contrato::bigint as c,
           coalesce(nullif(btrim(p.ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+','')) end as uso,
           case when btrim(coalesce(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+','')) end as estrato,
           (nullif(btrim(p.medidor), '') is not null
            and upper(btrim(p.medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           substring(upper(btrim(p.observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(p.funcion)) as fn,
           case when p.fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(p.fecha_instalacion, 10)::date end as fi
    from (
      select distinct on (periodo, contrato) *
      from hechos.consumo_metodo
      where periodo in (p_periodo, v_ant) and contrato ~ '^[0-9]+$'
      order by periodo, contrato,
               (nullif(btrim(medidor), '') is not null) desc,
               (bi.f_num(lectura_actual) is not null) desc,
               bi.f_num(consumo_cargos) desc nulls last,
               categoria, subcategoria, observacion) p),
  u as materialized (
    select r.*,
           case when r.fn ~ '^CALCCODL' and r.cod = 99 then 'lectura'
                when r.fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]' then (case when r.con_med then 'promedio' else 'promedio_sin_medidor' end)
                when r.fn ~ '^\[(FOVC|FAJF)\]' then 'modificacion_directa'
                else 'otro' end as metodo
    from r),
  rc as materialized (
    select distinct btrim(contrato)::bigint as c, solicitud,
           case when substring(btrim(causal) from '^(\d{4})') in ('1102','1121','1127','1129','1101') then 'consumo'
                when substring(btrim(causal) from '^(\d{4})') = '1120' then 'promedio'
                when substring(btrim(causal) from '^(\d{4})') = '1110' then 'medidor'
                else 'otras' end as grupo,
           case substring(btrim(causal) from '^(\d{4})') when '1114' then 'desocupado' when '1111' then 'cartera' when '1315' then 'admin' end as sub
    from hechos.reclamos
    where periodo = p_periodo and btrim(contrato) ~ '^[0-9]+$'),
  rg as materialized (
    select c,
           count(*) filter (where grupo = 'consumo')  as sc,
           count(*) filter (where grupo = 'promedio') as sp,
           count(*) filter (where grupo = 'medidor')  as sm,
           count(*) filter (where grupo = 'otras')    as so,
           count(*) filter (where sub = 'desocupado') as sd,
           count(*) filter (where sub = 'cartera')    as sk,
           count(*) filter (where sub = 'admin')      as sa
    from rc group by c),
  base as (
    select b.ciclo, b.uso, b.estrato, b.metodo as metodo_act, coalesce(a.metodo, 'sin_dato') as metodo_ant,
           case when not b.con_med then 'Sin medidor'
                when b.fi is null or b.fi > v_cierre then 'Sin fecha'
                when extract(year from age(v_cierre, b.fi)) < 3  then '0-3'
                when extract(year from age(v_cierre, b.fi)) < 5  then '3-5'
                when extract(year from age(v_cierre, b.fi)) < 10 then '5-10'
                when extract(year from age(v_cierre, b.fi)) < 15 then '10-15'
                when b.fi = date '1986-01-01' then '>15 (1986-01-01)'
                else '>15 (fecha real)' end as banda,
           coalesce(g.sc, 0) as sc, coalesce(g.sp, 0) as sp, coalesce(g.sm, 0) as sm, coalesce(g.so, 0) as so,
           coalesce(g.sd, 0) as sd, coalesce(g.sk, 0) as sk, coalesce(g.sa, 0) as sa
    from u b
    left join u a on a.c = b.c and a.periodo = v_ant
    left join rg g on g.c = b.c
    where b.periodo = p_periodo)
  select p_periodo, ciclo, uso, estrato, metodo_act, metodo_ant, banda,
         count(*), sum(sc), sum(sp), sum(sm), sum(so),
         count(*) filter (where sc + sp + sm + so > 0),
         count(*) filter (where sc + sp > 0),
         now(), sum(sd), sum(sk), sum(sa)
  from base
  group by ciclo, uso, estrato, metodo_act, metodo_ant, banda
  union all
  select p_periodo, 'Sin base', 'Sin base', 'Sin base', 'Sin base', 'Sin base', 'Sin base',
         0, sum(sc), sum(sp), sum(sm), sum(so), 0, 0, now(), sum(sd), sum(sk), sum(sa)
  from rg g
  where not exists (select 1 from u where u.periodo = p_periodo and u.c = g.c)
  having count(*) > 0;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_reclamo_metodo(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
-- Un periodo por vez:
--   begin; set local statement_timeout = '300s'; select bi.recalcular('bi.v_reclamo_metodo_dim', '202602'); commit;
-- Periodos: 202602, 202603, 202604, 202605, 202607 (usa 202605), 202608 y 202609.

-- >>> PASO 4 · controles ------------------------------------------------
--   EXCEPT en ambos sentidos, periodo por periodo, contra una referencia independiente. Controles: sum(contratos) del periodo =
--   contratos distintos de consumo_metodo del periodo (las filas pueden ser unas mas por duplicados de la fuente);
--   solicitudes totales (consumo + promedio + medidor + otras, incluida la fila 'Sin base') = solicitudes distintas de
--   hechos.reclamos del periodo (623, 628, 517, 563, 558, 533 y 595); contratos_con_reclamo <= contratos por celda;
--   solicitudes_desocupado + solicitudes_cartera + solicitudes_admin <= solicitudes_otras en toda celda.
