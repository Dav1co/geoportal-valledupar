-- =====================================================================
-- 45_cartera_edad_dim.sql · Cartera por edad de la deuda, por uso, estrato y servicio
-- ---------------------------------------------------------------------
-- Alimenta la seccion "Edad de la cartera" de Cartera desagregada (Fase A). Fuente: hechos.cartera_edades (valor, NO contratos:
-- el reporte no trae contrato). bi.v_cartera_detalle_dim colapsa las 18 etiquetas de edad en 4 tramos (sql/13); esta dimension
-- guarda la ETIQUETA CRUDA, de modo que cambiar la lectura de los limites (superior o inferior) se resuelve en el frontend con una
-- tabla de mapeo, sin tocar la base.
--
-- GRANO: periodo x uso x estrato x servicio x etiqueta. ~360 a 400 filas por periodo (8 periodos, 202602 a 202609: ~3.100 filas).
--  · etiqueta: '0','30','60', ... ,'330','360','720','1080','1440','1800','1801' tal como viene en la fuente (sin el '.0'), y
--    'sin_edad' (edad vacia = cartera financiada). orden: 0 a 17 en el orden de la fuente; 99 para 'sin_edad'.
--  · uso: '1','3','5','9' u 'otros' (usos 2 y -1 de la fuente). estrato: '1' a '6' u 'otros' (estratos -1, 7 y 8).
--    Los nombres de uso los pone el frontend (1 Residencial, 3 Comercial, 5 Oficial, 9 Especial).
--  · servicio: 'Agua' o 'Cobro de Servicios' (como viene).
--  · valor = suma de cartera_edades.total (pesos).
-- SIN barrio, ciclo ni contrato. El ciclo NO se incluye: el ciclo de cartera_edades no coincide con el de cartera_contrato (el reparto de
-- filas y de contratos por ciclo es muy distinto en las dos fuentes), asi que no se puede contar contratos por ciclo
-- para aplicar el minimo de 5. Con ciclo la dimension tendria ~2.700 filas por periodo (~21.600), por debajo de 100.000, y se puede
-- agregar si se obtiene un ciclo consistente.
-- MINIMO 5 (privacidad): el reporte de edades NO trae contratos, asi que el minimo se aplica por (uso, estrato) con los contratos con
-- deuda (total_cartera > 0) de hechos.cartera_contrato del mismo periodo. Si el grupo (uso, estrato) tiene menos de 5 contratos, o el
-- uso no es 1, 3, 5 o 9, o el estrato no es de 1 a 6, su valor va a 'otros'. Las sumas no cambian.
-- LIMITE: una celda etiqueta x uso x estrato PUEDE tener menos de 5 contratos aunque su grupo (uso, estrato) tenga 5 o mas, porque el
-- minimo no se aplica por etiqueta de edad (la supresion complementaria esta apagada por decision de David, ver la metodologia).
-- Lo que se publica es un valor AGREGADO en pesos por etiqueta, uso, estrato y servicio: ningun dato de contrato, barrio ni persona.
-- CUADRE: el total por periodo es igual a hechos.cartera_edades, que es contra lo que comparan el control de suma y el EXCEPT 0/0
-- (referencia independiente: columnas cf_cartN de la misma tabla, tolerancia de $ 1 por coma flotante).
--  · Contra hechos.cartera_contrato (suma por contrato) es igual en 7 de 8 periodos; 202602 difiere por un monto menor (cartera_contrato mayor).
--  · Contra hechos.cartera_resumen difiere por montos menores en 202603 a 202609 (cartera_resumen MENOR que cartera_edades); 202602 es igual.
--    Es una diferencia de las fuentes de origen y no de esta dimension; no se determino su causa.
--
-- Orden (cada paso con aprobacion):
--   1) tabla + funcion + revoke   2) despachador   3) rama en la RPC y en la Edge   4) carga   5) controles
-- =====================================================================

-- >>> PASO 1 · tabla, funcion, permisos --------------------------------

create table bi.v_cartera_edad_dim (
  periodo   text,
  uso       text,
  estrato   text,
  servicio  text,
  etiqueta  text,
  orden     integer,
  valor     numeric,
  primary key (periodo, uso, estrato, servicio, etiqueta)
);
revoke all on bi.v_cartera_edad_dim from public, anon, authenticated;
-- Sin seguridad por filas, como sus hermanas (v_cartera_detalle_dim, v_recaudo_edad_dim): el entorno la activo al crear la tabla (sin politicas) y
-- claude_ro veia 0 filas (la RPC SECURITY DEFINER, que corre como propietario, si las veia). Toda dimension nueva debe llevar esta linea desde el principio.
alter table bi.v_cartera_edad_dim disable row level security;

create or replace function bi.recalcular_cartera_edad(p_periodo text)
returns integer language plpgsql as $$
declare n integer;
begin
  delete from bi.v_cartera_edad_dim where periodo = p_periodo;
  insert into bi.v_cartera_edad_dim
  with ce as (
    select coalesce(nullif(btrim(categoria), ''), '(sin dato)')    as uso,
           coalesce(nullif(btrim(subcategoria), ''), '(sin dato)') as est,
           coalesce(nullif(btrim(servicio), ''), '(sin servicio)') as servicio,
           case when nullif(btrim(edad), '') is null then 'sin_edad'
                else (edad::numeric)::bigint::text end             as etiqueta,
           bi.f_num(total) as v
    from hechos.cartera_edades where periodo = p_periodo),
  k as (
    select coalesce(substring(btrim(uso) from '^-?\d+'), '(sin dato)')     as uso,
           coalesce(substring(btrim(estrato) from '^-?\d+'), '(sin dato)') as est,
           count(distinct contrato) as n
    from hechos.cartera_contrato
    where periodo = p_periodo and coalesce(bi.f_num(total_cartera), 0) > 0
    group by 1, 2)
  select p_periodo as periodo,
         case when coalesce(k.n, 0) >= 5 and ce.uso in ('1', '3', '5', '9') then ce.uso else 'otros' end as uso,
         case when coalesce(k.n, 0) >= 5 and ce.est in ('1', '2', '3', '4', '5', '6') then ce.est else 'otros' end as estrato,
         ce.servicio, ce.etiqueta,
         case when ce.etiqueta = 'sin_edad' then 99
              else array_position(array['0','30','60','90','120','150','180','210','240','270','300','330','360','720','1080','1440','1800','1801'], ce.etiqueta) - 1 end as orden,
         sum(ce.v) as valor
  from ce left join k on k.uso = ce.uso and k.est = ce.est
  group by 2, 3, 4, 5, 6
  ;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bi.recalcular_cartera_edad(text) from public, anon, authenticated;

-- >>> PASO 2 · despachador: +1 rama y +1 limpieza de huerfanos ----------
-- (create or replace conserva su ACL postgres=X; texto tomado de la funcion VIVA el 2026-10-17, con la rama nueva)
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
  end if;

  return n;
end $function$;

-- >>> PASO 3 · rama nueva en la RPC (60 ramas) y vista en la Edge (v26) ----
-- sql/05 queda IGUAL A LO VIVO (59 ramas) hasta aplicar; al aplicar se agrega esta rama a sql/05 y se ejecuta la funcion completa
-- (create or replace conserva el ACL: EXECUTE solo para postgres y service_role). Rama, antes del 'else raise exception':
--
--   elsif p_vista = 'v_cartera_edad_dim' then
--     select coalesce(jsonb_agg(to_jsonb(t) order by t.orden, t.uso, t.estrato, t.servicio), '[]'::jsonb)
--       into resultado
--     from bi.v_cartera_edad_dim t
--     where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
--       and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
--       and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');
--
-- Edge: agregar "v_cartera_edad_dim" a VISTAS_PERMITIDAS (geoportal-web, v26). Orden al aplicar: tabla y funciones, carga, Edge, RPC.

-- >>> PASO 4 · carga inicial -------------------------------------------
--   select bi.recalcular('bi.v_cartera_edad_dim', 'AAAAMM');  -- periodos: 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609
-- (cada uno tarda pocos segundos; con begin; set local statement_timeout='300s'; ... commit; por si acaso)

-- >>> PASO 5 · controles ------------------------------------------------
-- (los mismos estan en VISTAS_TABLERO de cargar_hechos.py; tolerancia de $ 1 por redondeo de coma flotante)
--   a) EXCEPT 0/0 por etiqueta contra una referencia independiente que desarma las columnas cf_cartN de cartera_edades
--      (la etiqueta 'sin_edad' = total menos las 18 cubetas), en los 8 periodos.
--   b) suma de la dimension = sum(total) de cartera_edades, y 19 etiquetas (18 + sin_edad) por periodo.
--   c) sin uso fuera de {1,3,5,9,otros} ni estrato fuera de {1..6,otros}; sin valores nulos ni orden nulo.
--   d) 202609: el valor de cada etiqueta cuadra con la suma de su columna cf_cartN en cartera_edades y el total con la suma de total_cartera
--      de cartera_contrato (los valores se verifican al aplicar; no se versionan aqui).
--   e) ACL igual a la de v_cartera_detalle_dim.

-- (09_quitar_rls_dimension.sql, ya aplicado, es esta misma linea.)
-- ROLLBACK (solo si ninguna pantalla lo usa todavia; los scripts estan en el scratchpad, no en el repo):
--   RPC:         ROLLBACK_geoportal_bi_consulta_59ramas.sql (create or replace conserva el ACL), tras quitar la vista de la Edge (v25).
--   Despachador: ROLLBACK_recalcular_antes_cartera_edad.sql.
--   drop function bi.recalcular_cartera_edad(text);
--   drop table bi.v_cartera_edad_dim;
