-- =====================================================================
-- 13_cartera_detalle.sql · Capa 2: pantalla de Cartera detallado
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06 y la RECARGA de cartera_edades / cartera_contrato
-- con el mapeo geográfico corregido (barrio ← DESUBGE4, comuna ←
-- DESUBGE5, comuna ← COMMUNE). Antes de esa recarga, barrio era una
-- constante ("COLOMBIA") y esta pantalla no podía filtrar territorio.
-- Sin datos personales: cartera_contrato trae nombre, identificación y
-- dirección — NINGUNA de esas columnas entra aquí.
--
-- Fuentes: hechos.cartera_edades (1,5 M filas, 6 períodos) para el
-- desglose por dimensiones, y hechos.cartera_contrato para los conteos
-- de contratos con deuda.
--
-- ARQUITECTURA (la misma de las otras "detallado"): un preagregado por
-- las dimensiones filtrables, traído de una sola vez por período y
-- filtrado en el navegador.
--
-- ⚠ ESTRUCTURA (verificada al peso, misma que cartera_resumen):
--   columna `cartera`  = cartera TOTAL, financiada incluida (118.840 M
--                        en 202607, idéntica a las otras dos fuentes)
--   tramos de edad     = SOLO la cartera NO financiada (108.819 M)
--   cartera − tramos   = la FINANCIADA (10.021 M), exactamente igual a
--                        bi.v_cartera_mes.financiada
-- Por eso la vista expone las dos cosas y la pantalla puede mostrar la
-- financiada POR BARRIO, que ninguna otra fuente permite.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ⚠ COMUNA COMPLETADA DESDE EL CATASTRO.
-- En el sistema comercial los predios de la COMUNA 2 no tienen comuna
-- asignada: los códigos presentes son 101, 103, 104, 105 y 106 — el 102
-- nunca aparece. Son 32.815 filas y $14.119 M (11,9 % de la cartera).
-- El mismo vacío existe en cartera_contrato ($14.143 M, 11,9 %), así que
-- es del ORIGEN, no de un informe.
-- Para que el análisis por comuna no pierda esa plata, la comuna se
-- completa desde bi.v_barrio_comuna (catastro georreferenciado) cuando
-- el origen no la trae. `comuna_origen` marca cuál se usó:
--   'comercial' = vino de Acuo · 'catastro' = inferida por barrio
--   'sin dato'  = ni una ni otra
-- Cobertura medida: recupera el 95 % de las filas y el 99,3 % de la
-- cartera que estaban sin comuna. NUNCA presentar la comuna inferida
-- como dato del sistema comercial: la pantalla debe advertirlo.
-- ---------------------------------------------------------------------
drop materialized view if exists bi.v_cartera_detalle_dim;
create materialized view bi.v_cartera_detalle_dim as
with e as (
  select
    ce.*,
    regexp_replace(upper(translate(btrim(ce.barrio),
      'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN')), '[^A-Z0-9]+', ' ', 'g') as barrio_norm
  from hechos.cartera_edades ce
)
select
  periodo,
  coalesce(nullif(btrim(barrio), ''), '(sin barrio)')             as barrio,
  coalesce(
    nullif(btrim(comuna), ''),
    'COMUNA ' || right(bc.comuna_catastro, 1),
    '(sin comuna)'
  )                                                               as comuna,
  case
    when nullif(btrim(comuna), '') is not null then 'comercial'
    when bc.comuna_catastro is not null        then 'catastro'
    else 'sin dato'
  end                                                             as comuna_origen,
  coalesce(bc.confiable, true)                                    as comuna_confiable,
  coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)')               as ciclo,
  coalesce(nullif(btrim(categoria), ''), '(sin uso)')             as uso,
  coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)') as subcategoria,
  sum(bi.f_num(total))                                            as cartera,
  -- Tramos de edad, misma agrupación que la pantalla 4 (los nombres
  -- cf_cartN son el CORTE INFERIOR de cada cubeta). Aquí sí existen las
  -- cubetas largas 720/1080/1440/1800, que cartera_resumen no trae.
  sum(coalesce(bi.f_num(cf_cart0), 0) + coalesce(bi.f_num(cf_cart30), 0))   as t_hasta_60,
  sum(coalesce(bi.f_num(cf_cart60), 0) + coalesce(bi.f_num(cf_cart90), 0)
    + coalesce(bi.f_num(cf_cart120), 0) + coalesce(bi.f_num(cf_cart150), 0)) as t_60_180,
  sum(coalesce(bi.f_num(cf_cart180), 0) + coalesce(bi.f_num(cf_cart210), 0)
    + coalesce(bi.f_num(cf_cart240), 0) + coalesce(bi.f_num(cf_cart270), 0)
    + coalesce(bi.f_num(cf_cart300), 0) + coalesce(bi.f_num(cf_cart330), 0)) as t_180_360,
  sum(coalesce(bi.f_num(cf_cart360), 0) + coalesce(bi.f_num(cf_cart720), 0)
    + coalesce(bi.f_num(cf_cart1080), 0) + coalesce(bi.f_num(cf_cart1440), 0)
    + coalesce(bi.f_num(cf_cart1800), 0) + coalesce(bi.f_num(cf_cartmay), 0)) as t_may_360
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
         coalesce(nullif(btrim(subcategoria), ''), '(sin subcategoria)')
with data;

create unique index if not exists v_cartera_detalle_dim_ux
  on bi.v_cartera_detalle_dim (periodo, barrio, comuna, comuna_origen, ciclo, uso, subcategoria);

create index if not exists v_cartera_detalle_dim_periodo_ix
  on bi.v_cartera_detalle_dim (periodo);

revoke all on bi.v_cartera_detalle_dim from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_cartera_contratos_dim · contratos con deuda por las dimensiones
-- que SÍ trae cartera_contrato (ciclo y comuna; no tiene barrio).
-- Solo conteos y montos: ninguna columna identificable.
-- ---------------------------------------------------------------------
drop materialized view if exists bi.v_cartera_contratos_dim;
create materialized view bi.v_cartera_contratos_dim as
select
  periodo,
  coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)')   as ciclo,
  coalesce(nullif(btrim(comuna), ''), '(sin comuna)') as comuna,
  coalesce(nullif(btrim(uso), ''), '(sin uso)')       as uso,
  coalesce(nullif(btrim(estrato), ''), '(sin estrato)') as estrato,
  count(*)                                                   as contratos,
  count(*) filter (where bi.f_num(total_cartera) > 0)        as contratos_con_deuda,
  sum(bi.f_num(total_cartera))                               as cartera_total,
  sum(bi.f_num(saldo_financiado))                            as saldo_financiado,
  sum(bi.f_num(facturas_vencidas))                           as facturas_vencidas
from hechos.cartera_contrato
group by periodo,
         coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)'),
         coalesce(nullif(btrim(comuna), ''), '(sin comuna)'),
         coalesce(nullif(btrim(uso), ''), '(sin uso)'),
         coalesce(nullif(btrim(estrato), ''), '(sin estrato)')
with data;

create unique index if not exists v_cartera_contratos_dim_ux
  on bi.v_cartera_contratos_dim (periodo, ciclo, comuna, uso, estrato);

revoke all on bi.v_cartera_contratos_dim from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 0) Cuánta cartera se muestra con comuna INFERIDA (la pantalla debe
--    advertirlo; es dato correcto pero derivado):
--      select comuna_origen, count(*) filas, round(sum(cartera)/1e6,0) cartera_M,
--             round(sum(cartera)/sum(sum(cartera)) over ()*100,1) pct
--      from bi.v_cartera_detalle_dim
--      where periodo = (select periodo from bi.v_ultimo_periodo)
--      group by 1 order by 3 desc;
-- 1) El mapeo geográfico quedó corregido (barrio ya NO es constante):
--      select periodo, count(distinct barrio) barrios, count(distinct comuna) comunas
--      from bi.v_cartera_detalle_dim group by 1 order by 1;
--      -- esperado: ~350 barrios y ~6 comunas por período, no 1
-- 2) Tamaño por período (apto para una sola llamada al navegador):
--      select periodo, count(*) from bi.v_cartera_detalle_dim group by 1 order by 1;
-- 3) FUENTE INDEPENDIENTE — contra bi.v_cartera_mes (cartera_resumen,
--    otra tabla). El TOTAL debe coincidir y los TRAMOS deben dar la no
--    financiada:
--      select d.periodo,
--             round(d.total/1e6,0) total_detalle_M, round(m.cartera_total/1e6,0) total_resumen_M,
--             round(d.tramos/1e6,0) tramos_M,        round(m.no_financiada/1e6,0) no_fin_M,
--             round((d.total - d.tramos)/1e6,0) financiada_implicita_M,
--             round(m.financiada/1e6,0) financiada_resumen_M
--      from (select periodo, sum(cartera) total,
--                   sum(t_hasta_60+t_60_180+t_180_360+t_may_360) tramos
--            from bi.v_cartera_detalle_dim group by 1) d
--      join bi.v_cartera_mes m using (periodo) order by d.periodo;
-- 4) Contratos con deuda contra bi.v_kpi_mes (que los cuenta aparte):
--      select c.periodo, sum(c.contratos_con_deuda) detalle, k.contratos_con_cartera kpi
--      from bi.v_cartera_contratos_dim c join bi.v_kpi_mes k using (periodo)
--      group by c.periodo, k.contratos_con_cartera order by c.periodo;
-- 5) Refresco (tras cada cargue de cartera_edades / cartera_contrato):
--      refresh materialized view concurrently bi.v_cartera_detalle_dim;
--      refresh materialized view concurrently bi.v_cartera_contratos_dim;
-- =====================================================================
