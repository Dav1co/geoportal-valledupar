-- =====================================================================
-- 11_fact_detalle.sql · Capa 2: pantalla de Facturación detallado
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06. Sin datos personales (solo conteos y montos).
-- Fuente: facturacion_contratos — DETALLE, solo 6 períodos retenidos.
--
-- ARQUITECTURA DE LAS PANTALLAS "DETALLADO" (aplica también a 6 y 7):
--
-- 1. PREAGREGADO, no materialización por combinación de filtros. Se
--    materializa UNA vista al grano de las dimensiones filtrables
--    (período × ciclo × uso × estrato/diámetro × concepto) y el filtro
--    se aplica sobre ella. Cardinalidad real medida en el ancla:
--      249 combinaciones de dimensiones · 5.700 con concepto · 130 conceptos
--    → ~5.700 filas por período, ~34.000 en los 6 retenidos. Liviano.
--    Materializar por combinación de filtros serían cientos de vistas.
--
-- 2. UNA sola llamada por período. Los datos de un período son fijos
--    hasta el cargue siguiente, así que la pantalla trae el preagregado
--    completo del período UNA vez y filtra en el navegador: cada clic
--    es instantáneo y no vuelve a pagar el guardián (token, lista
--    blanca, horario, permiso, auditoría). Solo se consulta de nuevo al
--    cambiar de período.
--
-- 3. SUMABILIDAD. Las métricas son sumables entre combinaciones porque
--    un contrato pertenece a un único ciclo/uso/estrato dentro del
--    período: sumar los contratos de varias filas da el conteo correcto
--    del corte. La verificación 2 lo comprueba contra el total oficial.
--
-- ⚠ subcategoria es HÍBRIDA: para uso Residencial es el ESTRATO; para
-- el resto es el DIÁMETRO de la acometida. Por eso el panel solo
-- muestra el filtro de estrato cuando el uso es Residencial.
-- ⚠ consumo solo es m³ en los conceptos 2 y 4 (regla crítica): la vista
-- lo guarda crudo por concepto y quien sume DEBE filtrar por concepto.
-- =====================================================================

drop materialized view if exists bi.v_fact_detalle_dim;
create materialized view bi.v_fact_detalle_dim as
select
  periodo,
  coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)')               as ciclo,
  coalesce(nullif(btrim(categoria), ''), '(sin uso)')             as uso,
  coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)') as subcategoria,
  concepto_num,
  count(distinct contrato) as contratos,
  sum(facturado)           as facturado,
  sum(consumo)             as consumo   -- m³ SOLO en conceptos 2 y 4
from bi_interno.v_facturacion_contratos
where concepto_num is not null
group by periodo,
         coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
         coalesce(nullif(btrim(categoria), ''), '(sin uso)'),
         coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)'),
         concepto_num
with data;

-- Clave natural completa: requisito de refresh concurrently.
create unique index if not exists v_fact_detalle_dim_ux
  on bi.v_fact_detalle_dim (periodo, ciclo, uso, subcategoria, concepto_num);

-- El filtro del RPC entra siempre por período: índice propio.
create index if not exists v_fact_detalle_dim_periodo_ix
  on bi.v_fact_detalle_dim (periodo);

revoke all on bi.v_fact_detalle_dim from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 1) Tamaño por período (debe rondar 5.700 filas — apto para una sola
--    llamada al navegador):
--      select periodo, count(*) from bi.v_fact_detalle_dim group by 1 order by 1;
-- 2) SUMABILIDAD contra las cifras oficiales del ancla:
--      select sum(contratos) filter (where concepto_num = 1) as susc_acueducto,
--             sum(contratos) filter (where concepto_num = 3) as susc_alcantarillado,
--             sum(consumo)   filter (where concepto_num = 2) as m3_acueducto,
--             sum(consumo)   filter (where concepto_num = 4) as m3_alcantarillado,
--             sum(facturado)                                 as facturado_neto
--      from bi.v_fact_detalle_dim
--      where periodo = (select periodo from bi.v_ultimo_periodo);
--      -- esperado: 111.579 · 110.039 · 1.700.852 · 1.631.457
-- 3) FUENTE INDEPENDIENTE — el facturado neto contra bi.v_facturacion_mes,
--    que sale de facturacion_agrupado (otra tabla):
--      select d.periodo, d.neto, f.neta, round((d.neto - f.neta), 2) as dif
--      from (select periodo, sum(facturado) as neto
--            from bi.v_fact_detalle_dim group by periodo) d
--      join bi.v_facturacion_mes f using (periodo)
--      order by d.periodo;
-- 4) Refresco (tras cada cargue, junto a v_kpi_mes y v_tarifa_referencia):
--      refresh materialized view concurrently bi.v_fact_detalle_dim;
-- =====================================================================
