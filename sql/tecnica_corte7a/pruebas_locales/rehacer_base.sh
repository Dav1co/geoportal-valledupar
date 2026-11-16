#!/bin/sh
# Rehace redes_local: lo del 6c (1a … 6b, el hotfix de safeupdate, el 6c y sus dobles), el doble de planta del 7a (base_viva_7a.sql) y, si no se pide «solo_6c», la migración del Corte 7a.
set -e
cd "$(dirname "$0")/.."
C6C=${C6C:-$(cd .. && pwd)/redes_corte6c}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C6C/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_7a.sql
if [ "$1" != "solo_6c" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte7a_editor.sql
fi
echo "redes_local lista ($1)"
