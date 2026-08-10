-- =====================================================================
-- 08_facturacion.sql · Capa 2: pantalla de Facturación
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06 (bi.conceptos_ruta cargada). Sin datos personales.
--
-- CIFRAS ENCADENADAS (definiciones oficiales):
--   BRUTA          = TODOS los conceptos facturados del período,
--                    incluidos terceros y financiaciones, EXCEPTO los
--                    conceptos 26 a 33. Total a tarifa plena antes del
--                    juego de subsidios y contribuciones.
--   SUBSIDIOS      = conceptos 26–29 (vienen negativos).
--   CONTRIBUCIONES = conceptos 30–33 (positivas).
--     Ambos se filtran con concepto_num BETWEEN 26 AND 33: eso excluye
--     las financiaciones 1026–1033 por construcción. NO usar
--     SER='SUBSIDIOS' de bi.conceptos_ruta a secas: esa marca cubre 16
--     conceptos (los 8 más sus financiaciones 1026–1033).
--   DÉFICIT        = subsidios + contribuciones (el neto, con signo).
--                    Negativo cuando los subsidios superan a las
--                    contribuciones: plata que la empresa no recibe del
--                    usuario. Se expone también en valor absoluto
--                    ("Déficit de subsidios y aportes") y como % de la
--                    facturación BRUTA.
--   NETA           = bruta + subsidios + contribuciones. El ingreso
--                    real, el que cuadra contra recaudo y cartera.
--                    VERIFICACIÓN OBLIGATORIA: debe coincidir con
--                    bi.v_kpi_mes.facturado del mismo período
--                    (202607: 5.983.961.190,61). Verificado: 43
--                    períodos, cero descuadres.
--
-- Las BARRAS de la pantalla usan la NETA (serie mensual por año), sin
-- superponer la bruta. La DONA agrupa por servicio. La TABLA muestra la
-- ruta contable fina (las 9 categorías de ruta_efectiva).
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_facturacion_mes · una fila por período con la cadena completa.
-- Fuente: facturacion_agrupado (histórico completo, tabla liviana:
-- vista en vivo, no necesita materializarse).
-- m3: consumo solo es m³ en los conceptos 2 y 4 (regla crítica).
-- ---------------------------------------------------------------------
create or replace view bi.v_facturacion_mes as
select
  periodo,
  min(anio) as anio,
  min(mes)  as mes,
  sum(facturado) filter (where concepto_num not between 26 and 33) as bruta,
  sum(facturado) filter (where concepto_num between 26 and 29)     as subsidios,
  sum(facturado) filter (where concepto_num between 30 and 33)     as contribuciones,
  sum(facturado) filter (where concepto_num between 26 and 33)     as deficit,
  abs(sum(facturado) filter (where concepto_num between 26 and 33)) as deficit_abs,
  round(
    abs(sum(facturado) filter (where concepto_num between 26 and 33))
    / nullif(sum(facturado) filter (where concepto_num not between 26 and 33), 0)
    * 100, 1)                                                      as pct_deficit_bruta,
  sum(facturado)                                                   as neta,
  sum(consumo)  filter (where concepto_num = 2)                    as m3_acueducto,
  sum(consumo)  filter (where concepto_num = 4)                    as m3_alcantarillado
from bi_interno.v_facturacion_agrupado
group by periodo;
-- neta = sum(facturado) total: bruta excluye 26–33 y el déficit los
-- reintegra, así que la identidad neta = bruta + subsidios +
-- contribuciones se cumple por construcción. La verificación contra
-- bi.v_kpi_mes confirma que la partición no dejó nada por fuera.

revoke all on bi.v_facturacion_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_facturacion_servicio · la DONA: facturado por servicio.
-- Agrupación de ruta_efectiva (todo el cruce vía bi.f_ruta_concepto,
-- que aplica el respaldo: ninguna categoría vacía):
--   ACUEDUCTO      = ACUEDUCTO - CARGO FIJO / BASICO / OTROS INGRESOS /
--                    RECARGO POR MORA  (los "otros ingresos" suman a SU
--                    servicio: son ingresos del acueducto)
--   ALCANTARILLADO = ALCANTARILLADO - CARGO FIJO / BASICO / OTROS INGRESOS
--   PLUVIAL        = categoría propia, no se agrupa
--   TERCERO        = tercero
-- Los conceptos 26–33 rutean a las categorías de su servicio, así que
-- cada servicio absorbe su déficit y la dona suma la NETA (coherente
-- con las barras). El else 'OTROS' no debería aparecer nunca: si
-- aparece, entró un valor nuevo de ruta_efectiva y hay que
-- clasificarlo aquí.
-- ---------------------------------------------------------------------
create or replace view bi.v_facturacion_servicio as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta,
    sum(facturado)                   as facturado
  from bi_interno.v_facturacion_agrupado
  group by periodo, bi.f_ruta_concepto(concepto_num)
)
select
  periodo,
  case
    when ruta like 'ACUEDUCTO -%'      then 'ACUEDUCTO'
    when ruta like 'ALCANTARILLADO -%' then 'ALCANTARILLADO'
    when ruta = 'PLUVIAL'              then 'PLUVIAL'
    when ruta = 'TERCERO'              then 'TERCERO'
    else 'OTROS'
  end                        as servicio,
  sum(facturado)             as facturado,
  round(sum(facturado) / nullif(sum(sum(facturado)) over (partition by periodo), 0) * 100, 1)
                             as pct_periodo
from por_ruta
group by periodo, 2;

revoke all on bi.v_facturacion_servicio from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_facturacion_ruta · la TABLA fina: las 9 categorías de
-- ruta_efectiva con el facturado del período y la variación contra el
-- período anterior CARGADO (lag por ruta; si un mes faltara en el
-- histórico, la variación salta al período previo existente).
-- Peso verificado: 244 ms sobre 43 períodos — vista en vivo.
-- ---------------------------------------------------------------------
create or replace view bi.v_facturacion_ruta as
with por_ruta as (
  select
    periodo,
    bi.f_ruta_concepto(concepto_num) as ruta_efectiva,
    sum(facturado)                   as facturado
  from bi_interno.v_facturacion_agrupado
  group by periodo, bi.f_ruta_concepto(concepto_num)
)
select
  periodo,
  ruta_efectiva,
  facturado,
  facturado - lag(facturado) over w as variacion,
  round(
    (facturado - lag(facturado) over w)
    / nullif(abs(lag(facturado) over w), 0) * 100, 1) as variacion_pct
from por_ruta
window w as (partition by ruta_efectiva order by periodo);

revoke all on bi.v_facturacion_ruta from public, anon, authenticated;

-- =====================================================================
-- bi.v_tarifa_referencia · LA TARIFA VIGENTE: la del último mes cargado
-- (bi.v_ultimo_periodo), no una serie histórica. 4 filas, una por
-- concepto (1–4), sin columnas de variación (sin serie no hay contra
-- qué comparar).
--
-- HALLAZGO DOCUMENTADO (validado contra 202607, método directo):
-- Acuo factura los conceptos 1–4 a TARIFA PLENA ÚNICA, idéntica para
-- todos los estratos y usos; TODA la progresividad vive en 26–33.
-- Lectura: conceptos 1 y 3, el facturado por contrato ES el cargo
-- fijo; conceptos 2 y 4, el facturado de los contratos con EXACTAMENTE
-- 1 m³ ES la tarifa por m³. La tarifa es la MODA (no el mínimo: un
-- cargo prorrateado por retiro a mitad de mes no la arrastra); con
-- valores_distintos = 1 ambas lecturas son idénticas. Respaldo si no
-- hubiera contratos de 1 m³: facturado/consumo (equivale exacto).
--
-- SEÑAL DE CONTROL (valores_distintos): con tarifa única, > 1 es cobro
-- fuera de tarifa o error de facturación — la pantalla lo destaca.
--
-- El filtro periodo = (select ...) baja al índice ix_fc_periodo de la
-- tabla base: lee solo el período ancla (~1,2 M filas), no los 7,2 M.
-- MATERIALIZADA con índice único para refresh concurrently tras cada
-- cargue: refresh materialized view concurrently bi.v_tarifa_referencia;
-- =====================================================================
drop materialized view if exists bi.v_tarifa_referencia;
create materialized view bi.v_tarifa_referencia as
with detalle as (
  select
    concepto_num,
    facturado,
    consumo,
    case
      when concepto_num in (1, 3) then round(facturado, 2)
      when consumo > 0            then round(facturado / consumo, 2)
    end as unitario,
    case
      when concepto_num in (1, 3) or consumo = 1 then round(facturado, 2)
    end as lectura_directa
  from bi_interno.v_facturacion_contratos
  where periodo = (select periodo from bi.v_ultimo_periodo)
    and concepto_num in (1, 2, 3, 4)
)
select
  (select periodo from bi.v_ultimo_periodo) as periodo,
  concepto_num,
  case concepto_num
    when 1 then '1 · Cargo fijo acueducto'
    when 2 then '2 · Consumo acueducto (m³)'
    when 3 then '3 · Cargo fijo alcantarillado'
    when 4 then '4 · Servicio alcantarillado (m³)'
  end                                as concepto,
  coalesce(
    mode() within group (order by lectura_directa),  -- el valor MÁS FRECUENTE
    round(sum(facturado) / nullif(sum(consumo), 0), 2)
  )                                  as tarifa,
  count(distinct unitario)           as valores_distintos,
  count(lectura_directa)             as contratos_lectura_directa
from detalle
group by concepto_num
with data;

create unique index if not exists v_tarifa_referencia_ux
  on bi.v_tarifa_referencia (periodo, concepto_num);

revoke all on bi.v_tarifa_referencia from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES (tras ejecutar este archivo)
-- =====================================================================
-- 1) OBLIGATORIA — la neta cuadra con bi.v_kpi_mes en TODOS los períodos:
--      select f.periodo, f.neta, k.facturado, f.neta - k.facturado as dif
--      from bi.v_facturacion_mes f
--      join bi.v_kpi_mes k using (periodo)
--      where abs(coalesce(f.neta,0) - coalesce(k.facturado,0)) > 0.01;
--      -- debe devolver CERO filas; 202607: neta = 5.983.961.190,61
-- 2) Signos correctos en 202607:
--      select subsidios < 0 and contribuciones > 0 and deficit < 0
--      from bi.v_facturacion_mes where periodo = '202607';
-- 3) La dona no tiene categoría 'OTROS' (si la tiene, hay un valor nuevo
--    de ruta_efectiva sin clasificar):
--      select distinct servicio from bi.v_facturacion_servicio;
-- 4) La tabla fina cubre las 9 rutas con facturado en el período:
--      select ruta_efectiva, facturado, variacion, variacion_pct
--      from bi.v_facturacion_ruta where periodo = '202607' order by facturado desc;
-- 5) Tarifa vigente = 4 filas del período ancla, los cuatro valores
--    conocidos, y la señal de control en calma (valores_distintos = 1):
--      select periodo, concepto, tarifa, valores_distintos,
--             contratos_lectura_directa
--      from bi.v_tarifa_referencia order by concepto_num;
--      -- esperado: 6.506,91 · 1.313,11 · 3.107,55 · 1.414,88
-- =====================================================================
