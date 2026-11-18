#!/bin/sh
# Base local de CODE B para el acta del Corte 14 (clúster propio, puerto 55442; nunca el 55432 de Code A).
# = emdupar_b_14base (ver ../redes_corte14/pruebas_locales/rehacer_base.sh) + la migración del Corte 14 (producción con el 14 publicado: huella 1a9ef250…).
#   sh rehacer_base.sh           → emdupar_b14a como producción hoy          sh rehacer_base.sh con_acta → además, la migración del acta
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b14a}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
[ -f "$($PSQL -d postgres -AtXc 'show data_directory')/ES_DE_CODE_B" ] || { echo "Ese clúster no es el de Code B: no se toca"; exit 1; }
[ -n "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'emdupar_b_14base'")" ] || { echo "Falta emdupar_b_14base (../redes_corte14/pruebas_locales/rehacer_base.sh)"; exit 1; }
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template emdupar_b_14base"
$PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f ../redes_corte14/migracion_redes_corte14_editor.sql >/dev/null
if [ "$1" = "con_acta" ]; then $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte14_acta_editor.sql >/dev/null; fi
echo "$BASE lista ($1)"
