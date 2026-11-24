-- =====================================================================
-- DOBLES SOLO LOCALES del Reparto de facturas (se cargan en la plantilla local; NUNCA en Supabase).
-- En producción existen de verdad (consulta A del 23-nov): hechos.rutas_consecutivos (TABLA del ETL, 9 columnas text sin NOT NULL ni defaults, índice
-- ix_ru_periodo, sin CHECK ni disparadores) y bi.v_rutas_geoportal (VISTA del último período: contrato, periodo_carga, ciclo, ruta, consecutivo_ruta,
-- consecutivo_predio). El doble tiene la MISMA clase de objeto y las mismas columnas, en el mismo orden. La definición de la vista en producción tiene md5
-- 51da701454deeee5accfd2163a9c8e31 (su texto no se copió): la de aquí hace lo mismo, «el último período de hechos.rutas_consecutivos».
-- =====================================================================
create table if not exists hechos.rutas_consecutivos (
  ciclo text, consecutivo_ruta text, ruta text, contrato text, direccion text, consecutivo_predio text, periodo text, archivo_origen text, fecha_carga text);
create index if not exists ix_ru_periodo on hechos.rutas_consecutivos (periodo);
comment on table hechos.rutas_consecutivos is 'DOBLE LOCAL (Code A, reparto): misma clase y columnas que la tabla del ETL.';
create or replace view bi.v_rutas_consecutivos as
  select contrato, periodo, ciclo, ruta, direccion, consecutivo_ruta, consecutivo_predio, archivo_origen from hechos.rutas_consecutivos;
create or replace view bi.v_rutas_geoportal as
  select contrato, periodo as periodo_carga, ciclo, ruta, consecutivo_ruta, consecutivo_predio
    from hechos.rutas_consecutivos where periodo = (select max(periodo) from hechos.rutas_consecutivos);
comment on view bi.v_rutas_geoportal is 'DOBLE LOCAL (Code A, reparto): el último período de hechos.rutas_consecutivos, con las columnas de producción.';
revoke all on hechos.rutas_consecutivos, bi.v_rutas_consecutivos, bi.v_rutas_geoportal from public, anon, authenticated;
