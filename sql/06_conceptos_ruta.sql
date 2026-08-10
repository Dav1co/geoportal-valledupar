-- =====================================================================
-- 06_conceptos_ruta.sql · Tabla maestra de ruteo contable de conceptos
-- ---------------------------------------------------------------------
-- Fuente: Ruta.xlsx (contabilidad). Dato maestro sin PII: vive en bi.
-- Es un maestro PRÁCTICAMENTE ESTÁTICO: cambia muy rara vez y su
-- actualización depende de sistemas. La carga la hace
-- ~/etl-emdupar/cargar_ruta_conceptos.py — de ejecución EXCEPCIONAL
-- (solo cuando sistemas entregue una versión nueva del archivo), no
-- periódica, y NO enganchada a cargar_hechos.py — con validación
-- completa previa y truncate + recarga total (tabla que reemplaza, no
-- acumula).
--
-- Se cargan TODAS las columnas del archivo tal cual (distintas gráficas
-- usarán distintas clasificaciones) y se agregan:
--   ruta_efectiva : la clasificación que manda (NUEVA RUTA normalizada)
--   ruta_ajustada : true si ruta_efectiva NO vino literal del archivo
--                   (normalización o respaldo) — para listar y
--                   confirmar esos casos con contabilidad.
--
-- REGLAS DE NORMALIZACIÓN (aplicadas por el script, documentadas aquí):
--   1. 'TERCEROS'  -> 'TERCERO'   (typo: 2 filas contra 281)
--   2. 'Otros ingresos (Sobrantes Venta de pliegos, multas y otros)'
--      (variante en minúsculas, 17 filas) ->
--      'ACUEDUCTO - OTROS INGRESOS (SOBRANTES VENTAS DE PLIEGOS, MULTAS Y OTROS)'
--   3. NUEVA RUTA = '0' o vacía (86, 87, 1086, 1087: desviaciones) ->
--      categoría de RESPALDO (la misma de la regla 2)
--   4. 'PLUVIAL' se queda como categoría propia: es un concepto separado
--      con su propio tratamiento contable (NO se agrupa en alcantarillado).
--   5. La columna CAMBIO del archivo se IGNORA: está mal marcada en 9
--      filas; la comparación real es CONTABILIDAD vs NUEVA RUTA.
--
-- REGLA DE RESPALDO (en el cruce, no en la tabla): todo concepto de los
-- hechos que no exista aquí se clasifica como
-- 'ACUEDUCTO - OTROS INGRESOS (SOBRANTES VENTAS DE PLIEGOS, MULTAS Y OTROS)'.
-- NO es un parche provisional: es el mecanismo PERMANENTE para los
-- conceptos nuevos que aparezcan en los hechos antes de alcanzar a
-- entrar en la maestra (que solo se actualiza cuando sistemas la
-- entrega). Ningún concepto queda sin ruta ni produce categorías
-- vacías: usar SIEMPRE bi.f_ruta_concepto() para cruzar, nunca el
-- join directo.
-- =====================================================================

create table if not exists bi.conceptos_ruta (
  conccodi                  integer primary key,   -- llave de cruce = bi.f_concepto_num()
  concdesc                  text,                  -- nombre del concepto en Acuo
  contabilidad              text,                  -- clasificación contable anterior (referencia)
  nueva_ruta                text,                  -- CLASIFICACIÓN CONTABLE OFICIAL, cruda tal como vino
  cambio                    text,                  -- se conserva pero NO se usa (mal marcada en 9 filas)
  servicio                  text,                  -- prestación del servicio vs. accesorio
  servicio_detallado        text,                  -- agrupación operativa: ACUEDUCTO / ALCANTARILLADO / OTROS / TERCERO
  ser                       text,                  -- agrupación operativa: separa CF CC, SUBSIDIOS, ACUEDUCTO, OTROS, TERCERO.
                                                   -- OJO: SER='SUBSIDIOS' son 16 conceptos = los 26-33 MÁS sus
                                                   -- financiaciones 1026-1033; no equivale a la lista fija 26-33.
  ruta                      text,
  concepto_servicios_bienes text,                  -- "concepto de servicios y bienes"
  finan                     text,                  -- contado vs. financiación
  des                       text,                  -- marcas operativas; SCRR = suspensión, corte,
                                                   -- reconexión y reinstalación (68 conceptos)
  concepto_inicial          text,
  a                         text,
  amb                       text,                  -- marca 'amb' = los 12 conceptos del servicio básico
                                                   -- y sus subsidios (1-4 y 26-33)
  ruta_efectiva             text not null,
  ruta_ajustada             boolean not null default false,
  archivo_origen            text,
  cargado_en                timestamptz not null default now()
);

revoke all on bi.conceptos_ruta from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.f_ruta_concepto · la única puerta de cruce concepto -> ruta.
-- Aplica la regla de respaldo: nunca devuelve NULL.
-- ---------------------------------------------------------------------
create or replace function bi.f_ruta_concepto(p_concepto int)
returns text
language sql
stable
as $$
  select coalesce(
    (select ruta_efectiva from bi.conceptos_ruta where conccodi = p_concepto),
    'ACUEDUCTO - OTROS INGRESOS (SOBRANTES VENTAS DE PLIEGOS, MULTAS Y OTROS)'
  )
$$;

-- =====================================================================
-- VERIFICACIONES (tras correr el script de carga)
-- =====================================================================
-- 1) Carga completa: select count(*) from bi.conceptos_ruta;  -- 631
-- 2) Filas ajustadas (a confirmar con contabilidad):
--      select conccodi, concdesc, nueva_ruta, ruta_efectiva
--      from bi.conceptos_ruta where ruta_ajustada order by conccodi;
-- 3) Respaldo en acción (concepto inexistente):
--      select bi.f_ruta_concepto(602);   -- ACUEDUCTO - OTROS INGRESOS (...)
-- 4) Ninguna categoría vacía:
--      select ruta_efectiva, count(*) from bi.conceptos_ruta
--      group by 1 order by 2 desc;   -- sin '0', sin NULL, sin minúsculas
-- =====================================================================
