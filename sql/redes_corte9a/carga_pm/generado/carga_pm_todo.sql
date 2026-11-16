-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a — CARGA DEL PLAN MAESTRO 2014 (paso 1 de 2: NO publica las capas del motor). Generado por carga_pm/carga_pm.py.
-- DESPUÉS de la migración del Corte 9a. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal; no va en ningún archivo):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_pm_todo.sql
-- Qué hace: (1) las tablas de referencia del Plan Maestro, en UNA transacción (si algo falla, no queda nada); (2) abre las cargas de «sectores» (36 polígonos)
-- y «sumideros» (484) por el motor del Cargue y muestra su resumen. No toca la ficha oficial de ningún activo. Repetirlo no duplica: la guardia se niega
-- si un conjunto ya está cargado con el mismo archivo. Después: publicar_pm.sql.
-- Archivos de regulatorio/salida_geoportal/ con que se generó (md5):
--   904083b861e7f27bf8b01c03670a72fd  capas/acueducto_nodos.gpkg
--   33178db329e8abe749ea05d7bf0aa049  capas/acueducto_tanques_y_fuentes.gpkg
--   686bd67e5f0bf85c88cd7304d3a479ab  capas/acueducto_tramos.gpkg
--   49f08451406479abde815e9b6141e0b0  capas/acueducto_valvulas_cierre.gpkg
--   c9ed18c211ad3d205357e754cb0b914d  capas/acueducto_valvulas_propuestas.gpkg
--   21336e281133a12b96428129bf25217e  capas/alc_catastro_sumideros.gpkg
--   e0b418fe48c80ad68afe9cdcf0668eb5  capas/campana_presiones_2014.gpkg
--   f3a6a42297777b055afc894d413dc131  capas/pluvial_alternativa2043_conductos.gpkg
--   bd30814d5fe82de70ad11974370f0c20  capas/pluvial_alternativa2043_descargas.gpkg
--   0f898041deb43da7201baa105fe4b355  capas/pluvial_alternativa2043_pozos.gpkg
--   dca55f258bf38f0ef798111ad1c597bc  capas/pluvial_existente_conductos.gpkg
--   eb3b9f45a1e4073e5db2c78720039db0  capas/pluvial_existente_pozos.gpkg
--   d2fb8f98b7a6ac1dda38e4db1a154084  capas/sectores_hidraulicos.gpkg
--   1fca61c0edc40ef9e6133486421da175  capas/subsectores_hidraulicos.gpkg
--   b01a85f288008c65ff8ef3a90ab8ff77  tablas/campana2014_puntos_resumen.csv
--   373cbf42f9fad519651ce3aadde482af  tablas/campana2014_series_15min.csv
--   5338c69d642bb1d53052ba3a9fe0d8bd  tablas/comparacion_geoportal_vs_modelo_nodos.csv
--   92f1ee82d862481d4774faeb26bb3091  tablas/comparacion_geoportal_vs_modelo_tramos.csv
--   c86a0ec53343f8a8b774ef5b4e9fded0  tablas/enriquecimiento_alc_conductos.csv
--   503151f2212dc8f9ff689c2b228380be  tablas/enriquecimiento_alc_pozos.csv
--   63c6d3c6264d8441c79f2335f07e6422  tablas/presiones_nodo_hora_existente.csv
--   afd6f3cf27a2364707fcd3cdcf57c7df  tablas/presiones_nodo_hora_futura.csv
-- =====================================================================
\set ON_ERROR_STOP 1
\if :{?solicitante}
\else
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f carga_pm_todo.sql'
  \quit
\endif
\pset pager off
\timing on
begin;
\ir partes/10_referencia.sql
commit;
\echo '=================== tablas de referencia cargadas ==================='
select conjunto, filas, md5, archivo from redes.v_ref_carga_vigente order by conjunto;
\ir partes/20_motor.sql
\echo 'Si los dos resúmenes dicen «lista para publicar: SÍ», corra publicar_pm.sql con el mismo comando.'
