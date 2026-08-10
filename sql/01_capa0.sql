-- =====================================================================
-- 01_capa0.sql · Cimientos del esquema BI del Tablero Comercial
-- ---------------------------------------------------------------------
-- Crea los esquemas bi (vistas servibles) y bi_interno (casting y apoyo)
-- y las funciones de saneamiento de la landing zone hechos.* (todo TEXT).
-- Ejecutar en el editor SQL de Supabase, antes que 02/03/04.
-- No toca nada existente: solo CREATE de objetos nuevos.
-- =====================================================================

create schema if not exists bi;
create schema if not exists bi_interno;

-- ---------------------------------------------------------------------
-- bi.f_num · texto -> numeric seguro.
-- La landing guarda números como texto ("111579.0", "nan", "").
-- NUNCA devuelve NaN: en Postgres 'NaN'::numeric es válido y una sola
-- fila NaN corrompe cualquier SUM/AVG que la incluya.
-- Comas: verificado contra los Excel de 202607 que ningún campo numérico
-- llega con separador de miles (el cargador escribe str() de numéricos
-- de Excel, siempre con punto decimal). Aun así, la coma se trata por
-- patrón para no convertir '1,234' (miles) en 1.234:
--   '1,234,567.89' -> se quitan las comas de miles
--   '123,45'       -> coma decimal -> '123.45'
-- ---------------------------------------------------------------------
-- Implementada como SQL puro (no plpgsql) para que el planificador la
-- INLINE en las consultas: la versión plpgsql costaba ~23 s al evaluarse
-- 1,2 millones de veces en facturacion_contratos. El patrón numérico
-- decide si el cast es seguro; lo que no calza es NULL, sin excepciones.
create or replace function bi.f_num(t text)
returns numeric
language sql
immutable
as $$
  select case
    when t is null or btrim(t) = '' then null
    when lower(btrim(t)) in ('nan', 'none', 'null') then null
    -- '1,234,567.89' -> coma como separador de miles
    when btrim(t) ~ '^-?\d{1,3}(,\d{3})+(\.\d+)?$'
      then replace(btrim(t), ',', '')::numeric
    -- '123,45' -> coma como decimal
    when btrim(t) ~ '^-?\d+,\d+$'
      then replace(btrim(t), ',', '.')::numeric
    -- '111579.0', '-5.2', '1e+16': cast directo solo si el patrón es
    -- numérico estricto ('NaN'/'Infinity' no calzan: jamás se devuelven)
    when btrim(t) ~ '^-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$'
      then btrim(t)::numeric
    else null
  end
$$;

-- ---------------------------------------------------------------------
-- bi.f_fecha · texto -> date seguro.
-- El cargador escribe fechas en ISO ("2026-07-31 00:00:00"); Acuo además
-- usa fechas comodín para "sin vencimiento": 4732-12-31 y 2032-12-31,
-- que aquí se tratan como NULL.
-- ---------------------------------------------------------------------
create or replace function bi.f_fecha(t text)
returns date
language plpgsql
immutable
as $$
declare
  d date;
begin
  if t is null or btrim(t) = '' or lower(btrim(t)) in ('nan', 'nat', 'none') then
    return null;
  end if;
  t := btrim(t);
  if left(t, 10) in ('4732-12-31', '2032-12-31') then return null; end if;
  begin
    d := left(t, 10)::date;                -- ISO: YYYY-MM-DD [HH:MI:SS]
  exception when others then
    begin
      d := to_date(left(t, 10), 'DD/MM/YYYY');  -- formato alterno de Acuo
    exception when others then
      return null;
    end;
  end;
  return d;
end $$;

-- ---------------------------------------------------------------------
-- bi.f_concepto_num · '2- CONSUMO ACUEDUCTO' -> 2.
-- REGLA: los conceptos SIEMPRE se filtran y agrupan por este número,
-- nunca por nombre (hay nombres repetidos con número distinto y los
-- acentos vienen corrompidos en el cargue: 'FINANCIACIËÄ').
-- ---------------------------------------------------------------------
create or replace function bi.f_concepto_num(t text)
returns int
language sql
immutable
as $$
  select bi.f_num(split_part(coalesce(t, ''), '-', 1))::int
$$;

-- ---------------------------------------------------------------------
-- bi.v_ultimo_periodo · el ANCLA del tablero.
-- Último período (AAAAMM) con las tres fuentes mensuales del resumen en
-- estado 'cargado' estricto según hechos.carga_log. Un mes 'parcial'
-- NO ancla: el tablero se queda en el mes anterior antes que mostrar
-- cifras incompletas como definitivas.
-- Si tras un cargue el ancla no avanza, revisa qué quedó parcial:
--   select periodo, fuente, estado, columnas_ignoradas, columnas_faltantes
--   from hechos.carga_log order by fecha_carga desc limit 20;
-- ---------------------------------------------------------------------
create or replace view bi.v_ultimo_periodo as
select max(periodo) as periodo
from (
  select periodo
  from hechos.carga_log
  where fuente in ('facturacion_agrupado', 'recaudo_agrupado', 'cartera_resumen')
    and estado = 'cargado'
  group by periodo
  having count(distinct fuente) = 3
) fuentes_completas;
