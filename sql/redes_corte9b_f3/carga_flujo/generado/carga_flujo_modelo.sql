-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — CARGA DEL FLUJO DEL AGUA (MODELO): caudal, velocidad y sentido por tubo. Generado por carga_flujo/carga_flujo.py.
-- DESPUÉS de la migración de la Fase 3 y de su verificación. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_flujo_modelo.sql
-- Todo va en UNA transacción: si una comprobación falla, no queda nada. No cambia la ficha de ningún activo. Repetirlo no duplica (la guardia se niega).
-- Al final muestra «N de N comprobaciones correctas — SIN FALLAS» con los TIEMPOS.
-- Archivo de la Fase 0 con que se generó (md5):  2b0b8616697e22427f7019f766de1448  flujo_modelo_v1.csv
-- Es un flujo de MODELO (modeloV1, Plan Maestro 2014), no medido.
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f carga_flujo_modelo.sql'
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
\ir partes/10_flujo.sql
\ir partes/30_comprobar.sql
commit;
\echo 'Flujo del modelo cargado. Corra ahora verificacion_carga_flujo_modelo.sql.'
