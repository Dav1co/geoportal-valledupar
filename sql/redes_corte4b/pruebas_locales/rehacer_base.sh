#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 4a (1a + 2 + 3a + 3b + el doble de las 4 funciones de permisos + la migración
# del 4a y su doble extra) y, si no se pide «solo_4a», la migración del Corte 4b.
set -e
cd "$(dirname "$0")/.."
C4A=${C4A:-$(cd .. && pwd)/redes_corte4a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C4A/pruebas_locales/rehacer_base.sh" >/dev/null
if [ "$1" != "solo_4a" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte4b_editor.sql
fi
echo "redes_local lista ($1)"
