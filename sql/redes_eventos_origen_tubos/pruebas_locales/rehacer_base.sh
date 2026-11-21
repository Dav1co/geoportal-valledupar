#!/bin/sh
# Base local de CODE A para el corte de EVENTOS (origen y tubos) (localhost:55432, base redes_local): PRODUCCIÓN AL 20-NOV 21:08
# (huella de redes 3f3c89e6…: los reportes del PTAP y las descargas de Distribución publicados) + un doble de los sectores por planta (en producción hay
# 72 filas, 36 × 2; aquí 3 sectores ZTBASE asignados a las dos plantas con la RPC publicada, para probar que se desactivan). La plantilla «redes_evt_base» se arma una vez.
#   sh rehacer_base.sh            → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_evt    → además, la migración de este corte
#   sh rehacer_base.sh plantilla  → rehace también la plantilla
set -e
case "${1:-}" in
  -h|--help) sed -n '2,8p' "$0" | sed -e 's/^# \{0,1\}//'; exit 0;;
  ""|con_evt|plantilla) ;;
  *) echo "Modo u opción desconocida: $1 (use con_evt, plantilla o nada; -h para el uso)" >&2; exit 2;;
esac
[ $# -le 1 ] || { echo "Sobran argumentos (-h para el uso)" >&2; exit 2; }
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_evt_base'")" ]; then
  sh ../redes_reportes_distribucion/pruebas_locales/rehacer_base.sh con_todo >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -1 -f pruebas_locales/doble_planta_sectores.sql >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_evt_base" -c "create database redes_evt_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_evt_base"
if [ "$1" = "con_evt" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_eventos_origen_tubos_editor.sql >/dev/null; fi
echo "redes_local lista (producción al 20-nov 21:08 ${1:-})"
