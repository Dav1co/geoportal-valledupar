#!/bin/sh
# Base local de CODE B para el 5d (clúster propio, puerto 55442; nunca el 55432 de Code A). Producción hoy = «emdupar_b_bis» (9a + carga + 9a-bis + sectores
# oficiales; huella 814eac39…) + lo del Corte 8 que toca a redes (base_8.sql). La plantilla queda como «emdupar_b_5dbase».
#   sh rehacer_base.sh          → emdupar_b = copia limpia de la plantilla (como producción hoy)
#   sh rehacer_base.sh con_5d   → además, la migración del 5d
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
[ -f "$($PSQL -d postgres -AtXc 'show data_directory')/ES_DE_CODE_B" ] || { echo "Ese clúster no es el de Code B: no se toca"; exit 1; }
if [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_5dbase'")" ]; then
  [ -n "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_bis'")" ] || { echo "Falta la plantilla ${BASE}_bis (../redes_corte9a_bis/pruebas_locales/base_chrome.sh)"; exit 1; }
  $PSQL -q -X -d postgres -c "create database ${BASE}_5dbase template ${BASE}_bis"
  $PSQL -q -X -d "${BASE}_5dbase" -v ON_ERROR_STOP=1 -f pruebas_locales/base_8.sql >/dev/null
fi
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template ${BASE}_5dbase"
if [ "$1" = "con_5d" ]; then $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte5d_editor.sql >/dev/null; fi
echo "$BASE lista ($1)"
