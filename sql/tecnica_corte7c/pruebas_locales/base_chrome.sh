#!/bin/sh
# Base para la prueba de Chrome del Corte 7c: la del 7a (carga real, contratos sintéticos, caudales de Entrada y el 7a) más la migración del 7c.
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres} PGOPTIONS='-c client_min_messages=warning'
sh ../tecnica_corte7a/pruebas_locales/base_chrome.sh >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte7c_editor.sql >/dev/null
echo "base de Chrome lista (7c)"
