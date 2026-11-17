-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 — CARGA DEL INVENTARIO REGULATORIO (la Valoración Técnica 2019 y el amarre de cada activo con su fila). Generado por carga_val/carga_val.py.
-- DESPUÉS de la migración del Corte 10 y de su verificación. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_valoracion.sql
-- Todo va en UNA transacción: si una comprobación falla, no queda nada. No cambia la ficha oficial de ningún activo. Repetirlo no duplica (la guardia se niega).
-- Al final muestra «N de N comprobaciones correctas — SIN FALLAS» con los TIEMPOS.
-- Archivos de paquete_fase1/regulatorio/ con que se generó (md5):
--   16e6a5e96e756700de07e0c92cdf40c3  Valoracion_Tecnica_Valledupar_04122019.xlsx
--   1f1092b8f2e420435c85660c7d619d6a  salida_geoportal/tablas/corte10_tramos_acueducto_fila_valoracion.csv
--   c86a0ec53343f8a8b774ef5b4e9fded0  salida_geoportal/tablas/enriquecimiento_alc_conductos.csv
--   b617c4f9d2196de4126c1f0ac084ebe0  salida_geoportal/tablas/corte10_activos_puntuales.csv
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f carga_valoracion.sql'
  \quit
\endif
\pset pager off
\timing on
begin;
set local statement_timeout = 0;
do $$
begin
  if to_regclass('redes.val_filas') is null or to_regprocedure('public.geoportal_redes_valoracion(text)') is null then raise exception 'Falta la migración del Corte 10: deténgase y avise'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \gset
\if :es_admin
\else
  \echo 'Ese correo no es de un administrador del geoportal: no se carga nada.'
  rollback;
  \quit
\endif
select exists (select 1 from redes.v_ref_carga_vigente where conjunto = 'valoracion' and md5 = '16e6a5e96e756700de07e0c92cdf40c3') as ya_cargada \gset
\if :ya_cargada
  \echo 'Esta valoración ya está cargada y vigente (mismo archivo): no se carga de nuevo.'
  rollback;
  \quit
\endif
\ir partes/10_valoracion.sql
\ir partes/20_amarre.sql
\ir partes/30_comprobar.sql
commit;
\echo 'Inventario regulatorio cargado. Corra ahora verificacion_carga_valoracion.sql.'
