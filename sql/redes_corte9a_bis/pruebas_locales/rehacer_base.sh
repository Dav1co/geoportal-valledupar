#!/bin/sh
# Base local de CODE B para el 9a-bis (clúster propio, puerto 55442; nunca el 55432 de Code A). Parte de «emdupar_b_9a»: producción después del 9a y su carga
# (la plantilla la arma ../redes_corte9a/pruebas_locales/base_chrome.sh).
#   sh rehacer_base.sh          → emdupar_b = copia limpia de la plantilla del 9a (como producción hoy)
#   sh rehacer_base.sh con_bis  → además, la migración del 9a-bis
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
[ -f "$($PSQL -d postgres -AtXc 'show data_directory')/ES_DE_CODE_B" ] || { echo "Ese clúster no es el de Code B: no se toca"; exit 1; }
if [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_9a'")" ]; then sh ../redes_corte9a/pruebas_locales/base_chrome.sh >/dev/null; fi
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template ${BASE}_9a"
if [ "$1" = "con_bis" ]; then $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte9a_bis_editor.sql >/dev/null; fi
echo "$BASE lista ($1)"
