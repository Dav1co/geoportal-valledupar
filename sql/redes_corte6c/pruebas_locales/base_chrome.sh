#!/bin/sh
# Base para la prueba de Chrome y el arnés del Corte 6c, con el volumen real: lo del 6b con la carga real del 1a (35.781 activos), la MUE y 111.950
# contratos SINTÉTICOS (predio, cartera y ficha inventados: ningún dato real), el hotfix de pg-safeupdate, los dobles del 6c y, si no se pide
# «solo_hotfix», la migración del 6c.
set -e
cd "$(dirname "$0")/.."
C6B=${C6B:-$(cd .. && pwd)/redes_corte6b}
HOT=${HOT:-$(cd .. && pwd)/redes_hotfix_6b_safeupdate}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres} PGOPTIONS='-c client_min_messages=warning'
sh "$C6B/pruebas_locales/base_chrome.sh" >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f "$HOT/migracion_hotfix_6b_safeupdate_editor.sql" >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_6c.sql >/dev/null
if [ "$1" != "solo_hotfix" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte6c_editor.sql >/dev/null
fi
echo "base de Chrome lista ($1)"
