-- =====================================================================
-- sql/42 · MAPA DE CALOR (dimension espacial agregada) · Fase A: solo base de datos y cargador
-- =====================================================================
-- Tres tablas por periodo y capa (dos por celda de 250 m para pintar un mapa de calor estatico con dos capas y un interruptor
-- de cartera, y una de cartera por grupo de mora calculada sobre TODOS los contratos de la capa). PRIVACIDAD: solo agregados por celda; nunca coordenadas individuales, contratos, direcciones ni nombres.
--
-- bi.v_mapa_calor_dim · GRANO: periodo x capa x celda (SOLO celdas publicadas)
--  · celda_x = floor(x/250), celda_y = floor(y/250), con x e y en EPSG:3116 (MAGNA-SIRGAS / Colombia Bogota, en metros)
--    y un origen constante para todos los periodos. lon_centro y lat_centro: centro de la celda en EPSG:4326, 5 decimales.
--  · contratos_base: contratos de la base de la capa en la celda. contratos_capa: los que cumplen la capa.
--    contratos_base_cartera y contratos_capa_cartera: los anteriores que SE MANTIENEN con el interruptor de cartera, es decir,
--    SIN MORA PROFUNDA (8 o menos facturas vencidas, o sin registro en cartera_contrato del periodo). Se conserva el sufijo
--    «_cartera» por compatibilidad con la RPC, la Edge Function y los tipos; ya NO cuentan los contratos con cartera.
--  · SUPRESION EN EL SERVIDOR: una celda se publica solo si contratos_base >= 5; dentro de una celda publicada, cualquier
--    conteo entre 1 y 4 se publica como NULL (el 0 se conserva). Las celdas con menos de 5 contratos de base NO tienen
--    fila: sus contratos se cuentan en la tabla de cobertura.
-- bi.v_mapa_calor_cartera_dim · GRANO: periodo x capa x ambito x grupo (8 filas por periodo)
--  · ambito 'capa' = contratos de la capa; ambito 'universo' = todos los contratos de la base de la capa (misma definicion
--    que el mapa). SOBRE TODOS LOS CONTRATOS: no depende de coordenadas ni de celdas.
--  · grupo 'mora_profunda' = maximo de facturas_vencidas del contrato en el periodo > 8; 'hasta_8' = 8 o menos o SIN registro
--    en cartera_contrato. El corte es el mismo del interruptor del mapa.
--  · contratos; valor_cartera = total_cartera (= saldo_pendiente + saldo_financiado) sumado entre las filas (productos) de cada
--    contrato, vacio = 0; valor_financiado = saldo_financiado sumado igual. No incluye saldos a favor. La fuente no desglosa si
--    saldo_pendiente incluye intereses u otros cargos.
--  · Supresion: un grupo con 1 a 4 contratos publica contratos, valor_cartera y valor_financiado en NULL.
-- bi.v_mapa_calor_cobertura_dim · GRANO: periodo x capa
--  · contratos_universo = contratos_con_coordenadas + contratos_sin_coordenadas
--    = contratos_en_celdas_publicadas + contratos_en_celdas_suprimidas + contratos_sin_coordenadas.
--
-- CAPAS (fuente hechos.consumo_metodo, UN registro por contrato con la misma regla de sql/39):
--  · 'sin_medidor_obs'  base: todos los contratos del periodo.  capa: contrato SIN medidor registrado, O con una
--    observacion cuyo codigo (entero al inicio del texto) esta en {1, 2, 5, 6, 7, 8, 11, 12, 13, 17, 21, 22}. No cuentan:
--    observacion vacia y los codigos 99, 30, 10, 3 y 4.
--  · 'consumo_bajo'     base: contratos residenciales con medidor registrado y lectura real (observacion 99 y funcion
--    CALCCODL), con cualquier consumo.  capa: consumo_cargos entre 0 y 5 m3, ceros incluidos.
--  · CARTERA (interruptor «excluir mora profunda»): se EXCLUYEN los contratos con MAS de 8 facturas vencidas en
--    hechos.cartera_contrato del mismo periodo (maximo de facturas_vencidas por contrato; el texto se convierte a numero
--    solo si cumple ^[0-9]+$). Se mantienen los de 0 a 8 facturas vencidas y los SIN registro de cartera en el periodo.
--    Se asume una factura por mes: 8 facturas equivalen a 8 meses de deuda.
--  · SUPRESION COMPLEMENTARIA (APAGADA por defecto, constante c_supr_compl): como la columna «_cartera» cuenta los que se
--    mantienen, la diferencia con el conteo de la capa (o de la base) es el numero de contratos con mora profunda y puede
--    quedar entre 1 y 4. Con la constante en true, en ese caso el conteo
--    «_cartera» tambien se publica como NULL, para que no se pueda deducir un conteo pequeno. Con la regla simple (1 a 4 en
--    NULL solo en cada columna) esa diferencia ya se podia deducir en la version anterior de este mapa.
--
-- COORDENADAS: public.predios_comercial (cod_usuario = contrato, geom POINT 4326). Un contrato puede tener varios
-- predios: se toma el de menor id. Las coordenadas NO son una fuente del cargador: si cambian, se recalcula a mano.
--
-- Periodos: los que tienen consumo_metodo y cartera_contrato (202602 a 202609, sin 202606).
-- Costo: lee consumo_metodo (~112 mil filas), cartera_contrato (~114 mil) y predios_comercial (~123 mil); del orden de
-- segundos. Cada periodo: begin; set local statement_timeout = '300s'; select bi.recalcular(...); commit;
-- ROLLBACK: delete de las dos tablas; las tablas y la funcion se pueden dejar. El despachador anterior se guarda antes.
-- Orden: 1) tablas + funcion + revoke   2) despachador   3) carga   4) controles
-- =====================================================================

-- >>> PASO 1 · tablas, funcion, permisos --------------------------------
create table bi.v_mapa_calor_dim (
  periodo                 text,
  capa                    text,
  celda_x                 bigint,
  celda_y                 bigint,
  lon_centro              numeric,
  lat_centro              numeric,
  contratos_base          bigint,
  contratos_capa          bigint,
  contratos_base_cartera  bigint,
  contratos_capa_cartera  bigint,
  calculado_en            timestamptz,
  primary key (periodo, capa, celda_x, celda_y)
);
revoke all on bi.v_mapa_calor_dim from public, anon, authenticated;

create table bi.v_mapa_calor_cobertura_dim (
  periodo                        text,
  capa                           text,
  contratos_universo             bigint,
  contratos_con_coordenadas      bigint,
  contratos_sin_coordenadas      bigint,
  contratos_en_celdas_publicadas bigint,
  contratos_en_celdas_suprimidas bigint,
  calculado_en                   timestamptz,
  primary key (periodo, capa)
);
revoke all on bi.v_mapa_calor_cobertura_dim from public, anon, authenticated;

create table bi.v_mapa_calor_cartera_dim (
  periodo            text,
  capa               text,
  ambito             text,
  grupo              text,
  contratos          bigint,
  valor_cartera      numeric,
  valor_financiado   numeric,
  calculado_en       timestamptz,
  primary key (periodo, capa, ambito, grupo)
);
revoke all on bi.v_mapa_calor_cartera_dim from public, anon, authenticated;

create or replace function bi.recalcular_mapa_calor(p_periodo text)
returns integer language plpgsql as $$
declare
  c_celda    constant integer := 250;   -- lado de la celda, en metros
  c_srid     constant integer := 3116;  -- sistema metrico fijo (origen constante)
  c_min_base constant integer := 5;     -- minimo de contratos de base para publicar una celda
  c_mora     constant integer := 8;     -- mas de 8 facturas vencidas = mora profunda (se excluye con el interruptor)
  c_supr_compl constant boolean := false; -- true: suprimir tambien el «_cartera» cuando (total - mantenidos) esta entre 1 y 4
  n integer;
begin
  delete from bi.v_mapa_calor_dim where periodo = p_periodo;
  delete from bi.v_mapa_calor_cobertura_dim where periodo = p_periodo;
  delete from bi.v_mapa_calor_cartera_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo) then
    return 0;
  end if;

  with r as materialized (
    select distinct on (contrato)
           case when btrim(contrato) ~ '^[0-9]+$' then btrim(contrato)::bigint end as cn,
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as uso,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           substring(upper(btrim(observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(funcion)) as fn,
           bi.f_num(consumo_cargos) as cc
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion),
  k as (
    select cn,
           (not con_med or coalesce(cod in (1,2,5,6,7,8,11,12,13,17,21,22), false)) as l1,
           (uso = 'Residencial' and con_med and cod = 99 and fn ~ '^CALCCODL') as u2,
           (uso = 'Residencial' and con_med and cod = 99 and fn ~ '^CALCCODL' and cc >= 0 and cc <= 5) as l2
    from r),
  cv as (
    select btrim(contrato)::bigint as c,
           max(case when btrim(facturas_vencidas) ~ '^[0-9]+$' then btrim(facturas_vencidas)::numeric end) as mx,
           coalesce(sum(bi.f_num(total_cartera)), 0) as tot,
           coalesce(sum(bi.f_num(saldo_financiado)), 0) as fin
    from hechos.cartera_contrato
    where periodo = p_periodo and btrim(contrato) ~ '^[0-9]+$'
    group by 1),
  pc as (
    select distinct on (c) c,
           floor(st_x(g) / c_celda)::bigint as gx,
           floor(st_y(g) / c_celda)::bigint as gy
    from (select btrim(cod_usuario)::bigint as c, id, st_transform(geom, c_srid) as g
          from public.predios_comercial
          where geom is not null and btrim(cod_usuario) ~ '^[0-9]+$') q
    order by c, id),
  j as materialized (
    select x.capa, pc.gx, pc.gy, x.en_capa, not coalesce(cv.mx > c_mora, false) as cart,
           coalesce(cv.tot, 0) as tot, coalesce(cv.fin, 0) as fin
    from (select 'sin_medidor_obs'::text as capa, cn, l1 as en_capa from k
          union all
          select 'consumo_bajo'::text, cn, l2 from k where u2) x
    left join pc on pc.c = x.cn
    left join cv on cv.c = x.cn),
  cel as materialized (
    select capa, gx, gy,
           count(*) as base,
           count(*) filter (where en_capa) as capa_n,
           count(*) filter (where cart) as base_c,          -- «cart» = se mantiene (sin mora profunda)
           count(*) filter (where en_capa and cart) as capa_c
    from j where gx is not null
    group by capa, gx, gy),
  ins_cob as (
    insert into bi.v_mapa_calor_cobertura_dim
    select p_periodo, j.capa, count(*), count(*) filter (where j.gx is not null), count(*) filter (where j.gx is null),
           coalesce((select sum(base) from cel where cel.capa = j.capa and cel.base >= c_min_base), 0),
           coalesce((select sum(base) from cel where cel.capa = j.capa and cel.base < c_min_base), 0),
           now()
    from j group by j.capa
    returning 1),
  ins_car as (
    insert into bi.v_mapa_calor_cartera_dim
    select p_periodo, g.capa, g.ambito, g.grupo,
           case when coalesce(h.n, 0) between 1 and 4 then null else coalesce(h.n, 0) end,
           case when coalesce(h.n, 0) between 1 and 4 then null else coalesce(h.val, 0) end,
           case when coalesce(h.n, 0) between 1 and 4 then null else coalesce(h.fin, 0) end,
           now()
    from (select c.capa, am.ambito, gr.grupo
          from (values ('sin_medidor_obs'), ('consumo_bajo')) c(capa)
          cross join (values ('capa'), ('universo')) am(ambito)
          cross join (values ('mora_profunda'), ('hasta_8')) gr(grupo)) g
    left join (
      select j.capa, am2.ambito, case when j.cart then 'hasta_8' else 'mora_profunda' end as grupo,
             count(*) as n, sum(j.tot) as val, sum(j.fin) as fin
      from j cross join lateral (values ('universo', true), ('capa', coalesce(j.en_capa, false))) am2(ambito, ok)
      where am2.ok
      group by 1, 2, 3) h on h.capa = g.capa and h.ambito = g.ambito and h.grupo = g.grupo
    returning 1)
  insert into bi.v_mapa_calor_dim
  select p_periodo, cel.capa, cel.gx, cel.gy,
         round(st_x(st_transform(st_setsrid(st_makepoint((cel.gx + 0.5) * c_celda, (cel.gy + 0.5) * c_celda), c_srid), 4326))::numeric, 5),
         round(st_y(st_transform(st_setsrid(st_makepoint((cel.gx + 0.5) * c_celda, (cel.gy + 0.5) * c_celda), c_srid), 4326))::numeric, 5),
         cel.base,
         case when cel.capa_n  between 1 and 4 then null else cel.capa_n  end,
         case when cel.base_c between 1 and 4 or (c_supr_compl and cel.base - cel.base_c between 1 and 4) then null else cel.base_c end,
         case when cel.capa_c between 1 and 4 or (c_supr_compl and cel.capa_n - cel.capa_c between 1 and 4) then null else cel.capa_c end,
         now()
  from cel
  where cel.base >= c_min_base;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function bi.recalcular_mapa_calor(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama (las tres tablas se llenan juntas) y +1 limpieza de huerfanos ----------
-- OJO: es el despachador VIVO (definicion viva + las lineas nuevas); otras copias publicadas pueden diferir.
-- create or replace conserva su ACL postgres=X.
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
  end if;

  return n;
end $function$;
