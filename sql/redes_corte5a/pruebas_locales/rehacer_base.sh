#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 4b (1a + 2 + 3a + 3b + 4a + 4b y sus dobles), el doble de tecnica.puntos con los 27
# puntos de muestreo y, si no se pide «solo_4b», la migración del Corte 5a.
set -e
cd "$(dirname "$0")/.."
C4B=${C4B:-$(cd .. && pwd)/redes_corte4b}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C4B/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_puntos.sql
if [ "$1" != "solo_4b" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte5a_editor.sql
fi
echo "redes_local lista ($1)"
