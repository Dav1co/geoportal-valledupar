-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 — ENSAYO DE LA CARGA DEL INVENTARIO REGULATORIO (no deja nada). Generado por carga_val/carga_val.py.
-- Corre toda la carga en UNA transacción que termina en ERROR a propósito y deshace todo:
--   psql "$CADENA_EMDUPAR" -v solicitante=CORREO_DEL_ADMINISTRADOR -f ensayo_carga_valoracion.sql
-- Resultado esperado al final:  ERROR: CARGA DEL INVENTARIO REGULATORIO · CORTE 10 (ENSAYO…) … RESULTADO: N de N comprobaciones correctas — SIN FALLAS
-- Copie la línea TIEMPOS: son los tiempos medidos en la base donde corre (la comprobación 13 falla si alguno pasa de 5 s).
-- Archivos de paquete_fase1/regulatorio/ con que se generó (md5):
--   16e6a5e96e756700de07e0c92cdf40c3  Valoracion_Tecnica_Valledupar_04122019.xlsx
--   1f1092b8f2e420435c85660c7d619d6a  salida_geoportal/tablas/corte10_tramos_acueducto_fila_valoracion.csv
--   c86a0ec53343f8a8b774ef5b4e9fded0  salida_geoportal/tablas/enriquecimiento_alc_conductos.csv
--   b617c4f9d2196de4126c1f0ac084ebe0  salida_geoportal/tablas/corte10_activos_puntuales.csv
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f ensayo_carga_valoracion.sql'
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
select set_config('redes.val_ensayo', 'si', true) as ensayo \gset
\ir partes/10_valoracion.sql
\ir partes/20_amarre.sql
\ir partes/30_comprobar.sql
rollback;
