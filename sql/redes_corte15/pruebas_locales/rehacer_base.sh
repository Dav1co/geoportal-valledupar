#!/bin/sh
# Base local de CODE A para el Corte 15 «Evento de suspensión» (localhost:55432, base redes_local): producción al 18-nov
# (huella 63d91763…: todo el 9b + Corte 14 + acta + «Cierre por aguas arriba» + la corrección «la válvula que cerró el operador»),
# con los CHECK, llaves y disparadores que traen sus migraciones, más el doble de los reportes de campo de Comercial (doble_campo_reportes_base_local.sql). La plantilla «redes_c15_base» se arma con la base de la corrección (su rehacer_base.sh con_vo).
#   sh rehacer_base.sh           → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_15    → además, la migración de este paquete
#   sh rehacer_base.sh plantilla → rehace también la plantilla
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_c15_base'")" ]; then
  sh ../redes_9b_valvula_operador/pruebas_locales/rehacer_base.sh con_vo >/dev/null
  # los reportes de campo de Comercial (campo.reportes y sus hechos) con los CHECK, llaves y disparadores de producción: un «sin_agua» de Comercial se asocia
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/doble_campo_reportes_base_local.sql >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_c15_base" -c "create database redes_c15_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_c15_base"
if [ "$1" = "con_15" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte15_editor.sql >/dev/null; fi
echo "redes_local lista (producción al 18-nov $1)"
