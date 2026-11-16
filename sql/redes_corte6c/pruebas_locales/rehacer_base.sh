#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432) como está producción el 16-nov: lo del 6b (1a + 2 + … + 6a + 6b y sus dobles), el hotfix de
# pg-safeupdate (5 funciones con «where true») y los dobles del 6c (base_viva_6c.sql). Si no se pide «solo_hotfix», aplica la migración del Corte 6c.
set -e
cd "$(dirname "$0")/.."
C6B=${C6B:-$(cd .. && pwd)/redes_corte6b}
HOT=${HOT:-$(cd .. && pwd)/redes_hotfix_6b_safeupdate}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C6B/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f "$HOT/migracion_hotfix_6b_safeupdate_editor.sql" >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_6c.sql
if [ "$1" != "solo_hotfix" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte6c_editor.sql
fi
echo "redes_local lista ($1)"
