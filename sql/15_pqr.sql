-- =====================================================================
-- 15_pqr.sql · Capa 2: pantalla de PQR (reclamos y recursos)
--              + bi.v_periodos_fuente, el mapa de huecos del tablero
-- ---------------------------------------------------------------------
-- Requiere 01, 02. Fuentes: hechos.reclamos y hechos.recursos —
-- HISTÓRICAS (sin retención), pero con huecos reales.
--
-- ⚠ PII: reclamos y recursos traen nombre_cliente, apellido_cliente,
-- identificacion, contrato y funcionario. NINGUNA de esas columnas
-- entra a bi. Solo salen conteos, montos y dimensiones de gestión.
--
-- ⚠ HUECOS DE DATOS (son la norma, no la excepción): hoy hay 17
-- períodos, de 202501 a 202606, y faltan **202506** y **202607** — este
-- último es el período ancla del tablero, así que la pantalla nace sin
-- el mes de corte. La pantalla debe decirlo, no mostrar cero.
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_periodos_fuente · qué períodos tiene REALMENTE cada fuente.
-- Es la base del estándar de huecos del tablero: cada pantalla consulta
-- aquí qué puede ofrecer, en vez de suponer que todo período del
-- selector tiene datos. Barata (una fila por fuente y período).
-- ---------------------------------------------------------------------
create or replace view bi.v_periodos_fuente as
select 'facturacion_agrupado' as fuente, periodo, count(*) filas from hechos.facturacion_agrupado group by 2
union all select 'facturacion_contratos', periodo, count(*) from hechos.facturacion_contratos group by 2
union all select 'recaudo_agrupado',      periodo, count(*) from hechos.recaudo_agrupado group by 2
union all select 'recaudo_detalle',       periodo, count(*) from hechos.recaudo_detalle group by 2
union all select 'cartera_resumen',       periodo, count(*) from hechos.cartera_resumen group by 2
union all select 'cartera_edades',        periodo, count(*) from hechos.cartera_edades group by 2
union all select 'cartera_contrato',      periodo, count(*) from hechos.cartera_contrato group by 2
union all select 'notas',                 periodo, count(*) from hechos.notas group by 2
union all select 'cupones_pagos',         periodo, count(*) from hechos.cupones_pagos group by 2
union all select 'consumo_metodo',        periodo, count(*) from hechos.consumo_metodo group by 2
union all select 'reclamos',              periodo, count(*) from hechos.reclamos group by 2
union all select 'recursos',              periodo, count(*) from hechos.recursos group by 2;

revoke all on bi.v_periodos_fuente from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_pqr_mes · serie mensual de reclamos y recursos.
-- Solo aparecen los períodos que EXISTEN: un mes sin archivo no genera
-- fila, para que el frontend pueda dibujar un hueco en vez de un cero.
-- ---------------------------------------------------------------------
create or replace view bi.v_pqr_mes as
with r as (
  select periodo,
         count(*)                                        as reclamos,
         -- Estados reales de Acuo (verificados): "14 - Atendido",
         -- "13 - Registrado" y "36 - En anulación". Atendido = resuelto;
         -- registrado = aún pendiente de respuesta.
         count(*) filter (where upper(coalesce(estado,'')) like '%ATENDID%') as reclamos_atendidos,
         count(*) filter (where upper(coalesce(estado,'')) like '%REGISTRAD%') as reclamos_pendientes,
         count(*) filter (where upper(coalesce(estado,'')) like '%ANULAC%') as reclamos_anulados,
         sum(bi.f_num(valor_reclamado))                  as valor_reclamado,
         count(distinct contrato)                        as contratos_reclamantes,
         avg(nullif(bi.f_fecha(fecha_atencion) - bi.f_fecha(fecha_registro), null)) as dias_atencion
  from hechos.reclamos group by periodo
),
x as (
  select periodo, count(*) as recursos,
         sum(bi.f_num(valor_reclamado)) as valor_recurrido
  from hechos.recursos group by periodo
)
select
  coalesce(r.periodo, x.periodo)                as periodo,
  left(coalesce(r.periodo, x.periodo), 4)::int  as anio,
  right(coalesce(r.periodo, x.periodo), 2)::int as mes,
  r.reclamos,
  r.reclamos_atendidos,
  r.reclamos_pendientes,
  r.reclamos_anulados,
  round(r.reclamos_atendidos::numeric / nullif(r.reclamos, 0) * 100, 1) as pct_atendidos,
  r.valor_reclamado,
  r.contratos_reclamantes,
  round(r.dias_atencion::numeric, 1)            as dias_atencion_prom,
  x.recursos,
  x.valor_recurrido,
  round(x.recursos::numeric / nullif(r.reclamos, 0) * 100, 1) as pct_recursos_sobre_reclamos
from r full outer join x using (periodo);

revoke all on bi.v_pqr_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_pqr_dim · preagregado por las dimensiones de gestión, para el
-- panel de filtros. Sin PII: causal, estado, áreas, medio y barrio.
-- El barrio de reclamos viene como "455 - DON CARMELO": se conserva
-- crudo (auditable) y se expone también el nombre sin el código.
-- ---------------------------------------------------------------------
create or replace view bi.v_pqr_dim as
select
  periodo,
  'reclamo'                                                        as tipo,
  coalesce(nullif(btrim(causal), ''), '(sin causal)')              as causal,
  coalesce(nullif(btrim(estado), ''), '(sin estado)')              as estado,
  coalesce(nullif(btrim(area_causante), ''), '(sin area)')         as area_causante,
  coalesce(nullif(btrim(medio_recepcion), ''), '(sin medio)')      as medio_recepcion,
  coalesce(nullif(btrim(barrio), ''), '(sin barrio)')              as barrio_crudo,
  coalesce(nullif(btrim(split_part(barrio, '-', 2)), ''),
           nullif(btrim(barrio), ''), '(sin barrio)')              as barrio,
  count(*)                                                         as cantidad,
  sum(bi.f_num(valor_reclamado))                                   as valor
from hechos.reclamos
group by periodo, 3, 4, 5, 6, 7, 8
union all
select
  periodo,
  'recurso',
  coalesce(nullif(btrim(causal), ''), '(sin causal)'),
  coalesce(nullif(btrim(estado), ''), '(sin estado)'),
  coalesce(nullif(btrim(area_causante), ''), '(sin area)'),
  '(no aplica)',
  coalesce(nullif(btrim(barrio), ''), '(sin barrio)'),
  coalesce(nullif(btrim(split_part(barrio, '-', 2)), ''),
           nullif(btrim(barrio), ''), '(sin barrio)'),
  count(*),
  sum(bi.f_num(valor_reclamado))
from hechos.recursos
group by periodo, 3, 4, 5, 6, 7, 8;

revoke all on bi.v_pqr_dim from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 1) HUECOS: qué períodos tiene PQR y cuáles faltan frente al resto del
--    tablero (hoy faltan 202506 y 202607, el ancla):
--      select periodo, filas from bi.v_periodos_fuente
--      where fuente = 'reclamos' order by periodo;
-- 2) COHERENCIA — la serie mensual contra el preagregado:
--      select m.periodo, m.reclamos, d.cantidad
--      from bi.v_pqr_mes m
--      join (select periodo, sum(cantidad) cantidad from bi.v_pqr_dim
--            where tipo = 'reclamo' group by 1) d using (periodo)
--      where m.reclamos <> d.cantidad;
--      -- debe devolver CERO filas
-- 3) FUENTE INDEPENDIENTE — total contra la tabla cruda:
--      select (select count(*) from hechos.reclamos) crudo,
--             (select sum(reclamos) from bi.v_pqr_mes) vista;
-- 3b) Estados: los reales son "14 - Atendido", "13 - Registrado" y
--     "36 - En anulación" — NO existen "resuelto"/"cerrado".
--      select estado, count(*) from hechos.reclamos group by 1 order by 2 desc;
-- 4) Sin PII: la vista no debe exponer nombre, identificación ni contrato
--    (contratos_reclamantes es un CONTEO, no un identificador)
--      select column_name from information_schema.columns
--      where table_schema='bi' and table_name in ('v_pqr_mes','v_pqr_dim')
--        and column_name ~* 'nombre|apellido|identif|contrato|funcionario';
--      -- debe devolver CERO filas (contratos_reclamantes es un CONTEO)
-- =====================================================================
