#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 6a (1a + 2 + … + 5c + 6a y sus dobles), los dobles de lo vivo que lee el 6b
# (base_viva_6b.sql: Comercial y Muestreo) y, si no se pide «solo_6a», la migración del Corte 6b.
set -e
cd "$(dirname "$0")/.."
C6A=${C6A:-$(cd .. && pwd)/redes_corte6a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C6A/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_6b.sql
if [ "$1" != "solo_6a" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte6b_editor.sql
fi
echo "redes_local lista ($1)"
