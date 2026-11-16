#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): lo del 5a (1a + 2 + 3a + 3b + 4a + 4b + 5a y sus dobles), el doble extra de planta del 5b
# (f_autorizar_supervision) y, si no se pide «solo_5a», la migración del Corte 5b.
set -e
cd "$(dirname "$0")/.."
C5A=${C5A:-$(cd .. && pwd)/redes_corte5a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C5A/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_supervision.sql
if [ "$1" != "solo_5a" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte5b_editor.sql
fi
echo "redes_local lista ($1)"
