-- =====================================================================
-- 26_consumo_ciclo_dim.sql · Contratos por ciclo, medición y consumo cero
-- ---------------------------------------------------------------------
-- Alimenta la sección "Contratos por ciclo, medición y consumo cero" de
-- Facturación detallado. Fuente: hechos.consumo_metodo (ciclo, categoría,
-- subcategoría, medidor, consumo_facturado), con el valor facturado de
-- ACUEDUCTO tomado de hechos.facturacion_sspd por contrato.
-- Mismo patrón que sql/24_cupones_dim.sql y sql/25_notas_dim.sql.
--
-- GRANULARIDAD: periodo x ciclo x categoria x subcategoria x con_medidor
-- (~376 filas por periodo).
--
-- REGLAS Y SALVEDADES
--  · MEDIDOR (regla de David): medidor vacío = SIN medidor. Hoy "vacío"
--    es solo NULL (8.256 contratos en 202609); la condición también cubre
--    cadena vacía, espacios y marcadores ('NO APLICA','0','N/A',...) por si
--    la fuente cambia. NO se reclasifica con facturacion_sspd: 55 contratos
--    sin medidor en consumo_metodo figuran con serial real en
--    facturacion_sspd (202609); se dejan como vienen.
--  · CICLO: tal como viene la fuente ('1'..'24'). Sin reemplazos.
--  · CATEGORIA/SUBCATEGORIA: sin el código numérico inicial ('1 Residencial'
--    -> 'Residencial', '1 ESTRATO 1' -> 'ESTRATO 1') para que coincidan con
--    los filtros de uso y estrato de v_fact_detalle_dim; la fila -1/NULO
--    queda '(sin dato)'.
--  · CONTRATO DUPLICADO: un contrato aparece dos veces en consumo_metodo
--    202609 (Residencial estrato 2 y Comercial 1/2). Se deja: cuenta en sus
--    dos grupos (contratos = distintos POR GRUPO; la suma por periodo es 1
--    más que los contratos distintos del periodo).
--  · FILAS REPETIDAS EN LA FUENTE: consumo_metodo trae contratos repetidos
--    dentro del mismo grupo (202603: 16 contratos del ciclo 12, comercial,
--    con consumo 0; 202608: 1). `contratos` y los contadores de cero/nulo
--    cuentan contratos DISTINTOS, por eso sum(contratos) es menor que
--    count(*) de la fuente en esos periodos (111.069 vs 111.085 en 202603);
--    m3_facturados suma todas las filas y cuadra al peso con la fuente.
--  · FACTURADO ACUEDUCTO: facturacion_sspd es el archivo de ACUEDUCTO y solo
--    existe desde 202606; en periodos anteriores facturado_acueducto es NULL
--    y contratos_en_sspd es 0. El promedio por contrato se calcula sobre
--    contratos_en_sspd, no sobre contratos. No concilia al peso con sspd:
--    149 contratos de sspd no están en consumo_metodo ($702.083 en 202609).
--  · consumo_metodo no tiene 202606.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) carga por periodo
--   4) comprobaciones
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------
-- Tipos tomados de la descripcion de la consulta de referencia (\gdesc).
create table bi.v_consumo_ciclo_dim (
  periodo                text,
  ciclo                  text,
  categoria              text,
  subcategoria           text,
  con_medidor            boolean,
  contratos              bigint,
  contratos_consumo_cero bigint,
  contratos_consumo_nulo bigint,
  m3_facturados          numeric,
  facturado_acueducto    numeric,
  contratos_en_sspd      bigint,
  primary key (periodo, ciclo, categoria, subcategoria, con_medidor)
);
revoke all on bi.v_consumo_ciclo_dim from public, anon, authenticated;

create or replace function bi.recalcular_consumo_ciclo_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_consumo_ciclo_dim where periodo = p_periodo;
  insert into bi.v_consumo_ciclo_dim
  select c.periodo,
    c.ciclo,
    case when btrim(coalesce(regexp_replace(btrim(c.categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(c.categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(c.categoria),'^-?\d+\s+','')) end as categoria,
    case when btrim(coalesce(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+','')) end as subcategoria,
    (nullif(btrim(c.medidor),'') is not null and upper(btrim(c.medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
    count(distinct c.contrato) as contratos,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_facturado) = 0) as contratos_consumo_cero,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_facturado) is null) as contratos_consumo_nulo,
    sum(bi.f_num(c.consumo_facturado)) as m3_facturados,
    sum(bi.f_num(s.total_facturado)) as facturado_acueducto,
    count(distinct c.contrato) filter (where s.contrato is not null) as contratos_en_sspd
  from hechos.consumo_metodo c
  left join hechos.facturacion_sspd s on s.contrato = c.contrato and s.periodo = c.periodo
  where c.periodo = p_periodo
  group by 1,2,3,4,5;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_consumo_ciclo_dim(text) from public, anon, authenticated;

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
  elsif p_tabla = 'bi.v_consumo_ciclo_dim'     then n := bi.recalcular_consumo_ciclo_dim(p_periodo);
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · carga inicial, uno por uno ------------------------------
--   select bi.recalcular_consumo_ciclo_dim('202601');  ... 202602..202605, 202607..202609

-- >>> PASO 4 · comprobaciones -------------------------------------------
--   sum(contratos) = count(*) de consumo_metodo del periodo;
--   sum(contratos_consumo_cero/nulo) y sum(m3_facturados) contra
--   consumo_metodo; EXCEPT en ambos sentidos contra la consulta de
--   referencia; ACL igual a la de v_notas_mes_dim.

-- ROLLBACK (deshacer todo; solo si ninguna pantalla lo usa todavia):
-- create or replace function bi.recalcular(...)  -- restaurar el despachador
--   anterior (sin la rama v_consumo_ciclo_dim) desde sql/25_notas_dim.sql
-- drop function bi.recalcular_consumo_ciclo_dim(text);
-- drop table bi.v_consumo_ciclo_dim;

-- =====================================================================
-- A2 · CONSUMO COBRADO (consumo_cargos) junto al consumo medido
-- ---------------------------------------------------------------------
-- Verificado por David en 202609 contra facturacion_contratos (concepto
-- "2- CONSUMO ACUEDUCTO", una fila por contrato, 107.549 contratos,
-- 1.785.395 m3): facturacion_sspd.consumo_periodo coincide con esa linea en
-- los 107.548 contratos comunes; consumo_cargos coincide en 107.543 de
-- 107.549. Los 4.310 contratos sin linea 2 son los de consumo cero. Control
-- repetido en solo lectura para 202602-202609: ningun contrato sin linea 2
-- tiene cargos > 0; sspd = linea 2 sin una sola diferencia (202606-202609);
-- m3 de cargos vs linea 2 dentro de 0,1 % (maximo 0,092 % en 202604).
--
-- SIGNIFICADO DE LAS COLUMNAS (las anteriores NO cambian):
--   · m3_facturados / contratos_consumo_cero / contratos_consumo_nulo:
--     miden consumo_facturado (el consumo "medido" que reporta el sistema).
--   · m3_cargos / contratos_cargos_cero / contratos_cargos_nulo: miden
--     consumo_cargos (el consumo COBRADO en la factura; coincide con
--     sspd.consumo_periodo en >99,97 % de los contratos). consumo_cargos
--     nunca es NULL: contratos_cargos_nulo vale 0.
--   · contratos_cobrado_sin_medido: consumo_facturado nulo o 0 con
--     consumo_cargos > 0 (cobrado por promedio sin consumo medido).
--
-- SALVEDADES (observaciones, sin correccion):
--   · 202601 se sale del patron: 293 contratos "cobrado sin medido" contra
--     58 a 98 en los demas periodos (218 con consumo_facturado vacio y
--     cargos > 0). Es el periodo de los archivos con nombre _202612.
--   · HIPOTESIS para el Paso 2: dos contratos con modificacion directa
--     ([FOVC]/[FAJF], "Modificacion Directa de Consumos") sugieren que
--     consumo_facturado es el consumo PREVIO a la modificacion directa,
--     mientras consumo_cargos coincide con sspd y con la linea 2.
--   · seis contratos de 202609 con cargos = 0 y sspd = linea 2 > 0: no se
--     corrigen; no comparten ciclo,
--     observacion ni metodo.
-- ---------------------------------------------------------------------
alter table bi.v_consumo_ciclo_dim
  add column m3_cargos                    numeric,
  add column contratos_cargos_cero        bigint,
  add column contratos_cargos_nulo        bigint,
  add column contratos_cobrado_sin_medido bigint;
-- (el ACL de la tabla no cambia con el ALTER)

create or replace function bi.recalcular_consumo_ciclo_dim(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_consumo_ciclo_dim where periodo = p_periodo;
  insert into bi.v_consumo_ciclo_dim (
    periodo, ciclo, categoria, subcategoria, con_medidor, contratos, contratos_consumo_cero,
    contratos_consumo_nulo, m3_facturados, facturado_acueducto, contratos_en_sspd,
    m3_cargos, contratos_cargos_cero, contratos_cargos_nulo, contratos_cobrado_sin_medido)
  select c.periodo,
    c.ciclo,
    case when btrim(coalesce(regexp_replace(btrim(c.categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(c.categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(c.categoria),'^-?\d+\s+','')) end as categoria,
    case when btrim(coalesce(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(c.subcategoria),'^-?\d+\s+','')) end as subcategoria,
    (nullif(btrim(c.medidor),'') is not null and upper(btrim(c.medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_medidor,
    count(distinct c.contrato) as contratos,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_facturado) = 0) as contratos_consumo_cero,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_facturado) is null) as contratos_consumo_nulo,
    sum(bi.f_num(c.consumo_facturado)) as m3_facturados,
    sum(bi.f_num(s.total_facturado)) as facturado_acueducto,
    count(distinct c.contrato) filter (where s.contrato is not null) as contratos_en_sspd,
    sum(bi.f_num(c.consumo_cargos)) as m3_cargos,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_cargos) = 0) as contratos_cargos_cero,
    count(distinct c.contrato) filter (where bi.f_num(c.consumo_cargos) is null) as contratos_cargos_nulo,
    count(distinct c.contrato) filter (where (bi.f_num(c.consumo_facturado) is null or bi.f_num(c.consumo_facturado) = 0)
                                        and bi.f_num(c.consumo_cargos) > 0) as contratos_cobrado_sin_medido
  from hechos.consumo_metodo c
  left join hechos.facturacion_sspd s on s.contrato = c.contrato and s.periodo = c.periodo
  where c.periodo = p_periodo
  group by 1,2,3,4,5;
  get diagnostics n = row_count;
  return n;
end $$;
-- (create or replace conserva el ACL de la funcion: REVOKE de A sigue vigente)

-- Recarga: select bi.recalcular_consumo_ciclo_dim('202601'); ... 202602..202605, 202607..202609
-- Comprobaciones: EXCEPT en ambos sentidos contra la consulta de referencia
-- ampliada, sumas contra consumo_metodo (sum(consumo_cargos)), ACL igual.

-- ROLLBACK de A2:
-- alter table bi.v_consumo_ciclo_dim drop column m3_cargos, drop column contratos_cargos_cero,
--   drop column contratos_cargos_nulo, drop column contratos_cobrado_sin_medido;
-- y volver a crear bi.recalcular_consumo_ciclo_dim con el cuerpo del PASO 1 de este
-- archivo (insert sin lista de columnas y sin los cuatro campos de cargos); luego
-- recargar los 8 periodos.
