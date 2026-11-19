#!/bin/sh
# Base local de CODE A para la corrección «la válvula que cerró el operador» (localhost:55432, base redes_local): producción al 17-nov
# (huella af34032d…: todo el 9b + Corte 14 + acta del 14 + «Cierre por aguas arriba»), con los CHECK, llaves y disparadores que traen sus migraciones.
# La plantilla «redes_vo_base» se arma con la base de «aguas arriba» (su rehacer_base.sh con_au).
#   sh rehacer_base.sh           → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_vo    → además, la migración de este paquete
#   sh rehacer_base.sh plantilla → rehace también la plantilla (y la de aguas arriba, si no está)
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_vo_base'")" ]; then
  sh ../redes_9b_aguasarriba/pruebas_locales/rehacer_base.sh con_au >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_vo_base" -c "create database redes_vo_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_vo_base"
if [ "$1" = "con_vo" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_9b_valvula_operador_editor.sql >/dev/null; fi
echo "redes_local lista (aguas arriba publicado $1)"
