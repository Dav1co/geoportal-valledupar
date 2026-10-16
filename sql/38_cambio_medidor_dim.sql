-- =====================================================================
-- 38_cambio_medidor_dim.sql · Cambios de medidor entre periodos consecutivos (por contrato)
-- ---------------------------------------------------------------------
-- Alimenta el analisis de submedicion por vejez del medidor: cuantos contratos cambian de medidor
-- (serial distinto) entre un periodo y el anterior disponible, de que antiguedad era el medidor anterior
-- y con que metodo se factura el periodo actual. Fuente: hechos.consumo_metodo (serial = medidor).
--
-- GRANO: periodo x ciclo x uso x estrato x tipo_evento x banda_ant x metodo_act. Una fila de la fuente por
--        contrato y periodo (el mismo orden de las demas dims: con medidor, con lectura, mayor consumo).
--  · periodo = mes actual (AAAAMM); periodo_ant = mes anterior DISPONIBLE en consumo_metodo; meses_intervalo =
--    meses entre ambos (1 normalmente; 2 en 202605 -> 202607 porque 202606 no existe en la fuente).
--  · ciclo, uso y estrato: los del periodo ACTUAL (mismas reglas de sql/29: sin el codigo numerico inicial;
--    vacio o NULO -> '(sin dato)'; ciclo vacio -> '(sin ciclo)').
--  · tipo_evento (solo contratos presentes en los dos periodos):
--      CON MEDIDOR EN AMBOS PERIODOS Y SERIAL DISTINTO, segun la continuidad de la lectura (lectura_anterior del periodo
--      actual frente a lectura_actual del periodo anterior; las lecturas son texto con punto decimal y solo se
--      convierten si cumplen ^[0-9]+(\.[0-9]+)?$):
--        reposicion_confirmada        la lectura reinicia: lectura_anterior del periodo <= 10 y menor que la del periodo
--                                     anterior (reinicio claro de un medidor nuevo)
--        cambio_serial_continuo       lectura_anterior del periodo = lectura_actual del anterior (probable recodificacion
--                                     del serial, no un cambio fisico)
--        cambio_serial_retroceso      la lectura retrocede pero queda POR ENCIMA de 10
--        cambio_serial_lectura_mayor  la lectura sube respecto de la del periodo anterior
--        reposicion_sin_lectura       alguna de las dos lecturas esta vacia o no es numerica
--        no_concluyente               solo en pares de DOS meses (202605 -> 202607, porque 202606 no existe): la
--                                     continuidad no se puede evaluar; solo vale la deteccion de reinicio a 10 o menos
--                                     (reposicion_confirmada), y el resto de los cambios de serial queda aqui
--      sin_cambio         con medidor en ambos periodos y el mismo serial (control)
--      instalacion_nueva  sin medidor en el periodo anterior y con medidor en el actual
--      retiro             con medidor en el anterior y sin medidor en el actual
--    Quedan fuera los contratos nuevos (no estaban en el periodo anterior) y los sin medidor en ambos.
--    HALLAZGO (202609): de 2.519 cambios de serial, el 97,5 % de los que tienen lectura evaluable conserva la continuidad
--    (igual que el 100 % de los contratos sin cambio): es una recodificacion masiva de seriales, no cambios fisicos.
--  · banda_ant: antiguedad del medidor ANTERIOR (fecha_instalacion del periodo anterior) al CIERRE del periodo
--    anterior, en anos cumplidos: '0-5', '5-10', '10-15', '>15 (fecha real)', '>15 (1986-01-01)' (fecha
--    centinela, antiguedad real desconocida), 'Sin fecha' (nula o posterior al cierre) y 'Sin medidor'. La fecha de
--    instalacion existe desde 202605; antes todo medidor cae en 'Sin fecha'.
--  · metodo_act (facturacion del periodo actual): 'lectura' = observacion 99 y funcion CALCCODL;
--    'promedio' = OBTECOPP u OBTECOPS, con o sin el prefijo [FAMC]; 'otro' = el resto (incluye [FOVC] y [FAJF],
--    que el propio texto de la funcion describe como "Modificacion Directa de Consumos", y CALCCODL con otra
--    observacion). El significado de los codigos entre corchetes no esta documentado en el cargador ni en el SQL.
--  · contratos = contratos del grupo. contratos_pareados = los que tienen metodo 'lectura' en AMBOS periodos y
--    consumo_facturado no nulo en ambos. m3_ant y m3_act = suma de consumo_facturado SOLO sobre los pareados.
--    contratos_con_medidor_ant = contratos con medidor en el periodo anterior (denominador de la tasa de cambio).
--
-- Costo: lee consumo_metodo de dos periodos (~112 mil filas cada uno); unos 10 s por periodo.
-- Cada periodo se recalcula con begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- Sin DROP ni TRUNCATE. ROLLBACK: delete from bi.v_cambio_medidor_dim; la tabla y la funcion se pueden dejar.
-- Orden (cada paso con aprobacion):  1) tabla + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
create table bi.v_cambio_medidor_dim (
  periodo                   text,
  periodo_ant               text,
  meses_intervalo           integer,
  ciclo                     text,
  uso                       text,
  estrato                   text,
  tipo_evento               text,
  banda_ant                 text,
  metodo_act                text,
  contratos                 bigint,
  contratos_pareados        bigint,
  m3_ant                    numeric,
  m3_act                    numeric,
  contratos_con_medidor_ant bigint,
  primary key (periodo, ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act)
);
revoke all on bi.v_cambio_medidor_dim from public, anon, authenticated;

create or replace function bi.recalcular_cambio_medidor(p_periodo text)
returns integer language plpgsql as $$
declare
  n          integer;
  v_ant      text;
  v_cierre   date;
  v_meses    integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  delete from bi.v_cambio_medidor_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo) then
    return 0;
  end if;
  select max(periodo) into v_ant from hechos.consumo_metodo where periodo < p_periodo;
  if v_ant is null then
    return 0;   -- sin periodo anterior no hay con que comparar (0 filas es lo correcto)
  end if;
  v_cierre := (to_date(v_ant || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;
  v_meses  := (substr(p_periodo, 1, 4)::int * 12 + substr(p_periodo, 5, 2)::int)
            - (substr(v_ant, 1, 4)::int * 12 + substr(v_ant, 5, 2)::int);

  insert into bi.v_cambio_medidor_dim
  with r as materialized (
    select p.periodo, p.contrato,
           coalesce(nullif(btrim(p.ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+','')) end as uso,
           case when btrim(coalesce(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+','')) end as estrato,
           (nullif(btrim(p.medidor), '') is not null
            and upper(btrim(p.medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           upper(btrim(p.medidor)) as serial,
           substring(upper(btrim(p.observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(p.funcion)) as fn,
           case when p.fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(p.fecha_instalacion, 10)::date end as fi,
           bi.f_num(p.consumo_facturado) as cf,
           case when btrim(p.lectura_anterior) ~ '^[0-9]+(\.[0-9]+)?$' then btrim(p.lectura_anterior)::numeric end as la,
           case when btrim(p.lectura_actual)   ~ '^[0-9]+(\.[0-9]+)?$' then btrim(p.lectura_actual)::numeric end as lc
    from (
      select distinct on (periodo, contrato) *
      from hechos.consumo_metodo
      where periodo in (p_periodo, v_ant)
      order by periodo, contrato,
               (nullif(btrim(medidor), '') is not null) desc,
               (bi.f_num(lectura_actual) is not null) desc,
               bi.f_num(consumo_cargos) desc nulls last,
               categoria, subcategoria, observacion) p),
  u as materialized (
    select r.*,
           case when r.fn ~ '^CALCCODL' and r.cod = 99 then 'lectura'
                when r.fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]' then 'promedio'
                else 'otro' end as metodo
    from r),
  j as (
    select b.ciclo, b.uso, b.estrato,
           case when a.con_med and b.con_med then
                  (case when a.serial = b.serial then 'sin_cambio'
                        when b.la is not null and a.lc is not null and b.la < a.lc and b.la <= 10 then 'reposicion_confirmada'
                        when v_meses > 1 then 'no_concluyente'
                        when b.la is null or a.lc is null then 'reposicion_sin_lectura'
                        when b.la = a.lc then 'cambio_serial_continuo'
                        when b.la < a.lc then 'cambio_serial_retroceso'
                        else 'cambio_serial_lectura_mayor' end)
                when not a.con_med and b.con_med then 'instalacion_nueva'
                when a.con_med and not b.con_med then 'retiro' end as tipo_evento,
           case when not a.con_med then 'Sin medidor'
                when a.fi is null or a.fi > v_cierre then 'Sin fecha'
                when extract(year from age(v_cierre, a.fi)) < 5  then '0-5'
                when extract(year from age(v_cierre, a.fi)) < 10 then '5-10'
                when extract(year from age(v_cierre, a.fi)) < 15 then '10-15'
                when a.fi = date '1986-01-01' then '>15 (1986-01-01)'
                else '>15 (fecha real)' end as banda_ant,
           b.metodo as metodo_act,
           (a.metodo = 'lectura' and b.metodo = 'lectura' and a.cf is not null and b.cf is not null) as pareado,
           a.cf as cf_ant, b.cf as cf_act, a.con_med as con_med_ant
    from u b join u a on a.contrato = b.contrato and a.periodo = v_ant
    where b.periodo = p_periodo)
  select p_periodo, v_ant, v_meses, ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act,
         count(*),
         count(*) filter (where pareado),
         sum(cf_ant) filter (where pareado),
         sum(cf_act) filter (where pareado),
         count(*) filter (where con_med_ant)
  from j
  where tipo_evento is not null
  group by ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cambio_medidor(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X). OJO: este texto es la copia PUBLICADA del despachador mas la
-- rama nueva; el despachador VIVO de la base tiene ramas adicionales (piezas no publicadas) y por eso se aplico
-- tomando su definicion viva e insertando solo las dos lineas nuevas, NO ejecutando este bloque tal cual.
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial -------------------------------------------
-- Un periodo por vez:
--   begin; set local statement_timeout = '300s'; select bi.recalcular('bi.v_cambio_medidor_dim', '202607'); commit;
-- Pares disponibles: 202601->202602, 202602->202603, 202603->202604, 202604->202605, 202605->202607 (2 meses),
-- 202607->202608, 202608->202609. (202601 no tiene periodo anterior: 0 filas.)

-- >>> PASO 4 · controles ------------------------------------------------
--   EXCEPT en ambos sentidos, periodo por periodo, contra una consulta de referencia independiente (otro metodo
--   de desduplicacion y de clasificacion). Control: la suma de los seis tipos de cambio de serial de 202609 es 2.519 (todos
--   los usos) y los sin_cambio de 202609 son 100.819; en los pares de un mes, el 100 % de los sin_cambio con lectura
--   evaluable es continuo.
