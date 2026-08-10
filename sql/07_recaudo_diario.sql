-- =====================================================================
-- 07_recaudo_diario.sql · Recaudo diario por lote de conciliación
-- ---------------------------------------------------------------------
-- BORRADOR SOBRE MODELO DE ESTRUCTURA: el archivo real aún no llega.
-- No ejecutar hasta revisarlo contra el archivo real.
--
-- Dos ritmos de datos que se RELEVAN, no compiten (mismo patrón que la
-- foto mensual de cartera vs. la cartera viva del geoportal):
--   · hechos.* cierra al terminar el mes: completo, conciliado, con
--     todas las dimensiones.
--   · este recaudo diario llega cada día, con menos detalle, y cubre
--     el mes en curso hasta que el cierre lo reemplaza.
--
-- Tabla PROPIA, fuera de las 15 fuentes de cargar_hechos.py: otro
-- ritmo, otro ciclo de vida. Grano: LOTE DE CONCILIACIÓN BANCARIA
-- (no pago individual — distinto de hechos.cupones_pagos).
-- Acumula por fecha; la recarga de un día es segura: el script borra
-- el día antes de insertar.
--
-- DEFINICIONES CONFIRMADAS:
--   · El recaudo real es valor_procesado. valor_informado NO se usa
--     para cifras (trae centinelas tipo 999999999999); se carga solo
--     para control de descuadres.
--   · La fecha que manda es fecha_registro (aplicación efectiva).
--     fecha_conciliacion se guarda; servirá para medir el rezago entre
--     aplicación y cierre bancario.
--   · conciliacion_cerrada y cierre_automatico son banderas de control
--     operativo (lotes abiertos o descuadrados). Se guardan CRUDAS
--     hasta ver los valores reales del archivo.
-- =====================================================================

create table if not exists hechos.recaudo_diario (
  conciliacion        text not null,          -- id del lote de conciliación
  entidad_recaudo     text,
  fecha_conciliacion  date,                   -- cierre bancario (rezago futuro)
  fecha_registro      date not null,          -- LA FECHA QUE MANDA (aplicación efectiva)
  num_cupones         integer,                -- cupones informados por la entidad
  valor_informado     numeric,                -- SOLO CONTROL: trae centinelas (999999999999)
  cupones_procesados  integer,
  valor_procesado     numeric,                -- EL RECAUDO REAL
  conciliacion_cerrada text,                  -- bandera cruda (mapear a boolean al ver valores reales)
  cierre_automatico   text,                   -- bandera cruda
  funcionario         text,                   -- dato personal de operario: NUNCA pasa a bi
  empresa             text,
  parent_id           text,                   -- relación entre lotes (semántica por confirmar)
  archivo_origen      text,
  cargado_en          timestamptz not null default now()
);

create index if not exists recaudo_diario_fecha_ix
  on hechos.recaudo_diario (fecha_registro);

revoke all on hechos.recaudo_diario from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_recaudo_diario_comparado · Capa 2, comparación AL MISMO CORTE.
--
-- El día de corte es la FECHA MÁXIMA CARGADA en la tabla, nunca la del
-- calendario. Toda comparación recorta los tres períodos a esa altura:
-- mes en curso hasta el día N, mes anterior hasta el día N, mismo mes
-- del año anterior hasta el día N. Un acumulado sin declarar hasta
-- cuándo acumula es engañoso: fecha_corte y dia_corte van como
-- columnas para que el tablero SIEMPRE los muestre.
--
-- Sin datos personales: funcionario queda fuera. Hoy la vista solo lee
-- de la tabla diaria; cuando existan los snapshots del cierre, el mes
-- anterior y el año anterior podrán venir del cierre (decisión abierta).
-- NOTA: esta vista aún NO está en la lista cerrada del RPC
-- geoportal_bi_consulta; se agrega cuando el frontend la consuma.
-- ---------------------------------------------------------------------
create or replace view bi.v_recaudo_diario_comparado as
with dia_a_dia as (
  select
    fecha_registro                as fecha,
    sum(valor_procesado)          as valor_dia,
    sum(cupones_procesados)       as cupones,
    count(*)                      as lotes
  from hechos.recaudo_diario
  group by fecha_registro
),
corte as (
  select
    max(fecha)                                        as fecha_corte,
    extract(day from max(fecha))::int                 as dia_corte,
    date_trunc('month', max(fecha))::date             as mes_corte,
    (date_trunc('month', max(fecha)) - interval '1 month')::date as mes_anterior,
    (date_trunc('month', max(fecha)) - interval '1 year')::date  as mes_anio_anterior
  from dia_a_dia
)
select
  case date_trunc('month', d.fecha)::date
    when c.mes_corte        then 'mes_corte'
    when c.mes_anterior     then 'mes_anterior'
    else                         'mismo_mes_anio_anterior'
  end                                        as serie,
  to_char(d.fecha, 'YYYYMM')                 as periodo,
  d.fecha,
  extract(day from d.fecha)::int             as dia,
  d.valor_dia,
  sum(d.valor_dia) over (
    partition by date_trunc('month', d.fecha)
    order by d.fecha
  )                                          as valor_acumulado,
  d.cupones,
  d.lotes,
  c.fecha_corte,
  c.dia_corte
from dia_a_dia d
cross join corte c
where date_trunc('month', d.fecha)::date
        in (c.mes_corte, c.mes_anterior, c.mes_anio_anterior)
  and extract(day from d.fecha)::int <= c.dia_corte;
-- El WHERE recorta ANTES de la ventana: el acumulado de cada serie
-- llega exactamente hasta el día N, no hasta su fin de mes.

revoke all on bi.v_recaudo_diario_comparado from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES (cuando haya datos cargados)
-- =====================================================================
-- 1) El corte es la fecha máxima cargada, no el calendario:
--      select distinct fecha_corte, dia_corte from bi.v_recaudo_diario_comparado;
-- 2) Ninguna serie pasa del día de corte:
--      select serie, max(dia) from bi.v_recaudo_diario_comparado group by 1;
--      -- max(dia) <= dia_corte en las tres
-- 3) El acumulado del mes de corte cuadra con la suma simple:
--      select sum(valor_procesado) from hechos.recaudo_diario
--      where date_trunc('month', fecha_registro) =
--            (select date_trunc('month', max(fecha_registro)) from hechos.recaudo_diario);
-- 4) Control de centinelas (no afectan cifras, solo control):
--      select count(*) from hechos.recaudo_diario where valor_informado >= 999999999;
-- =====================================================================
