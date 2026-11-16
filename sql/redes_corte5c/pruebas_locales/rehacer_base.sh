#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 5b (1a + 2 + 3a + 3b + 4a + 4b + 5a + 5b y sus dobles) y, si no se pide «solo_5b»,
# la migración del Corte 5c.
set -e
cd "$(dirname "$0")/.."
C5B=${C5B:-$(cd .. && pwd)/redes_corte5b}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C5B/pruebas_locales/rehacer_base.sh" >/dev/null
if [ "$1" != "solo_5b" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte5c_editor.sql
fi
echo "redes_local lista ($1)"
