-- =====================================================================
-- 20_periodos_fuente_rapida.sql
-- Reescribe bi.v_periodos_fuente para que deje de tardar 24 segundos.
--
-- EL PROBLEMA
-- La vista responde "que periodos tiene cada fuente": 242 filas, doce
-- ramas UNION ALL, un GROUP BY periodo por tabla. Sin WHERE, cada rama
-- tiene que recorrer la tabla ENTERA para descubrir seis valores
-- distintos: 15 millones de filas agregadas para devolver 242.
-- Medido: 23.807 ms. El statement_timeout de service_role es 30 s, o
-- sea que quedaban 4 segundos de margen. Y como Dashboard.tsx la pide
-- dentro del Promise.all inicial, esos 24 s eran el tiempo de apertura
-- del tablero entero.
--
-- No es un problema de indices: once de las doce tablas YA tienen
-- indice sobre periodo y el plan los usa. Un Index Only Scan sobre los
-- 7,1 millones de entradas de facturacion_contratos cuesta 4,5 s
-- aunque el indice exista. El problema es la forma de la consulta.
--
-- LA SOLUCION: loose index scan (salto por el indice)
-- En vez de agregar todas las filas, se usa el indice para saltar del
-- primer valor distinto al siguiente, con un CTE recursivo. El coste
-- pasa de O(filas) a O(distintos x log filas): seis sondas de indice
-- en lugar de 6,6 millones de filas leidas.
--
--   recaudo_detalle         8.088 ms -> 167 ms   (48x)
--   facturacion_contratos   7.568 ms -> 178 ms   (43x)
--   la vista completa      23.807 ms -> 587 ms   (40x)
--
-- Salida IDENTICA, verificada con EXCEPT en ambos sentidos:
-- 242 filas contra 242, cero diferencias. No cambian el nombre, las
-- columnas ni el contrato con el RPC puente, asi que no hay que tocar
-- ni geoportal_bi_consulta ni la Edge Function ni el frontend.
--
-- POR QUE `where periodo is not null` EN EL ANCLA
-- Un periodo nulo cortaria la recursion en la primera vuelta y la rama
-- devolveria menos periodos de los que hay. El filtro del ancla lo
-- evita, y el `where t.periodo is not null` del paso recursivo corta
-- limpiamente al llegar al ultimo valor.
--
-- REVERSA: la definicion anterior queda en el historial de git de este
-- repo; para volver atras basta reejecutar la version previa de este
-- archivo, o recrear la vista con doce ramas `group by periodo`.
-- =====================================================================

create or replace view bi.v_periodos_fuente as

select 'facturacion_agrupado'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.facturacion_agrupado where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.facturacion_agrupado p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'facturacion_contratos'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.facturacion_contratos where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.facturacion_contratos p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'recaudo_agrupado'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.recaudo_agrupado where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.recaudo_agrupado p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'recaudo_detalle'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.recaudo_detalle where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.recaudo_detalle p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'cartera_resumen'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.cartera_resumen where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.cartera_resumen p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'cartera_edades'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.cartera_edades where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.cartera_edades p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'cartera_contrato'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.cartera_contrato where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.cartera_contrato p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'notas'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.notas where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.notas p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'cupones_pagos'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.cupones_pagos where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.cupones_pagos p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'consumo_metodo'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.consumo_metodo where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.consumo_metodo p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'reclamos'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.reclamos where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.reclamos p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x

union all
select 'recursos'::text as fuente, periodo from (
  with recursive t as (
    (select periodo from hechos.recursos where periodo is not null order by periodo limit 1)
    union all
    select (select p.periodo from hechos.recursos p where p.periodo > t.periodo order by p.periodo limit 1)
    from t where t.periodo is not null)
  select periodo from t where periodo is not null) x;

comment on view bi.v_periodos_fuente is
  'Mapa de huecos del tablero: que periodos tiene realmente cada fuente. '
  'Resuelto con loose index scan (CTE recursivo que salta por el indice '
  'de periodo) en vez de GROUP BY sobre la tabla completa: 587 ms contra '
  'los 23,8 s de la version anterior, misma salida de 242 filas.';


-- ---------------------------------------------------------------------
-- APARTE, sin relacion con lo anterior: el unico indice de periodo que
-- falta y tiene volumen real. Las otras cuatro tablas sin indice
-- (saldos_favor, diferidos, ipuf, recaudo_diario) o no las lee nadie o
-- son minusculas -73 y 114 filas-, asi que no lo llevan.
-- facturacion_sspd son 223.028 filas y la lee bi.v_facturacion_geoportal,
-- de la que depende el mapa.
-- ---------------------------------------------------------------------
create index if not exists ix_fs_periodo
  on hechos.facturacion_sspd (periodo);
