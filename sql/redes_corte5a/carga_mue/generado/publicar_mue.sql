-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a — PUBLICAR LA PRIMERA CARGA DE LA CAPA MUE. Generado por carga_mue.py.
-- Córralo SOLO después de revisar el resumen de carga_mue_todo.sql:
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f publicar_mue.sql
-- En tecnica.puntos no cambia nada (los 27 ya existen y vienen todos): solo se agrega su ubicación en tecnica.puntos_ubicacion.
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f publicar_mue.sql'
  \quit
\endif
\pset pager off
\timing on
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante',
  (select id from redes.v_cargas_estado where capa_codigo = 'muestreo' and sha256 = '6211112c4bfe3e9a18cd04866cf08d5734dda5aef51ef745e5b94b1f32a8196f' and estado = 'abierta'),
  'Primera carga de los 27 puntos de muestreo (§4 de hallazgos, decisión de David del 15-nov)')) order by 1;
\echo '=================== LO QUE QUEDÓ VIGENTE ==================='
select p.codigo, p.nombre, u.exactitud, u.fuente, u.barrio_capa, u.lat, u.lon from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
 where p.tipo = 'muestreo' order by p.codigo;
