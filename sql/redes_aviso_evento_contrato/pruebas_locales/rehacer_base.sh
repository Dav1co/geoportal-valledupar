#!/bin/sh
# Base local de CODE A para «Aviso de evento por contrato» (localhost:55432, base redes_local): producción al 19-nov (huella 314112df…: todo hasta «Mis reportes»),
# con los CHECK, llaves y disparadores que traen sus migraciones. La plantilla «redes_evc_base» se arma con la de «Mis reportes» (su rehacer_base.sh con_mios).
#   sh rehacer_base.sh           → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_evc  → además, la migración de este paquete
#   sh rehacer_base.sh plantilla → rehace también la plantilla
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_evc_base'")" ]; then
  sh ../redes_levantar_mios/pruebas_locales/rehacer_base.sh con_mios >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_evc_base" -c "create database redes_evc_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_evc_base"
if [ "$1" = "con_evc" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_aviso_evento_contrato_editor.sql >/dev/null; fi
echo "redes_local lista (producción al 19-nov $1)"
