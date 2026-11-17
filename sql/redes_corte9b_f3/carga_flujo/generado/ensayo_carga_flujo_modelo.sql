-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — ENSAYO DE LA CARGA DEL FLUJO DEL AGUA (MODELO) (no deja nada). Generado por carga_flujo/carga_flujo.py.
-- Corre toda la carga en UNA transacción que termina en ERROR a propósito y deshace todo:
--   psql "$CADENA_EMDUPAR" -v solicitante=CORREO_DEL_ADMINISTRADOR -f ensayo_carga_flujo_modelo.sql
-- Resultado esperado al final:  ERROR: CARGA DEL FLUJO DEL MODELO … (ENSAYO…) … RESULTADO: N de N comprobaciones correctas — SIN FALLAS
-- Copie la línea TIEMPOS: son los tiempos medidos en la base donde corre (la comprobación 09 falla si alguno pasa de 1 s).
-- Archivo de la Fase 0 con que se generó (md5):  2b0b8616697e22427f7019f766de1448  flujo_modelo_v1.csv
-- Es un flujo de MODELO (modeloV1, Plan Maestro 2014), no medido.
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f ensayo_carga_flujo_modelo.sql'
  \quit
\endif
\pset pager off
\timing on
begin;
set local statement_timeout = 0;
do $$
begin
  if to_regclass('redes.flujo_modelo') is null or to_regprocedure('public.geoportal_redes_flujo_modelo(text)') is null then raise exception 'Falta la migración de la Fase 3 del Corte 9b: deténgase y avise'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \gset
\if :es_admin
\else
  \echo 'Ese correo no es de un administrador del geoportal: no se carga nada.'
  rollback;
  \quit
\endif
select exists (select 1 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo' and md5 = '2b0b8616697e22427f7019f766de1448') as ya_cargada \gset
\if :ya_cargada
  \echo 'Este flujo del modelo ya está cargado y vigente (mismo archivo): no se carga de nuevo.'
  rollback;
  \quit
\endif
select set_config('redes.flujo_ensayo', 'si', true) as ensayo \gset
\ir partes/10_flujo.sql
\ir partes/30_comprobar.sql
rollback;
