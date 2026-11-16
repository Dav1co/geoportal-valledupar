#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 5c (1a + 2 + 3a + 3b + 4a + 4b + 5a + 5b + 5c y sus dobles) y, si no se pide «solo_5c»,
# la migración del Corte 6a.
set -e
cd "$(dirname "$0")/.."
C5C=${C5C:-$(cd .. && pwd)/redes_corte5c}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C5C/pruebas_locales/rehacer_base.sh" >/dev/null
if [ "$1" != "solo_5c" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte6a_editor.sql
fi
echo "redes_local lista ($1)"
