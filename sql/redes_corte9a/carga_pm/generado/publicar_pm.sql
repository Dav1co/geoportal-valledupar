-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a — PUBLICAR LA CARGA DEL PLAN MAESTRO 2014 (paso 2 de 2). Generado por carga_pm/carga_pm.py.
-- Córralo SOLO después de revisar los resúmenes de carga_pm_todo.sql:
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f publicar_pm.sql
-- En UNA transacción: publica sectores y sumideros, crea el tanque La Popa, pone el alias «Hidrante» al tipo TOR, marca «por verificar» y corre las
-- comprobaciones «N de N». Si una sola falla, termina en ERROR y no queda nada de este paso.
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
  \echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f publicar_pm.sql'
  \quit
\endif
\pset pager off
\timing on
begin;
\ir partes/30_publicar.sql
\ir partes/40_comprobar.sql
commit;
\echo 'Publicado. Verificación de solo lectura: verificacion_carga_pm.sql'
