#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): 1a + 2 + 3a + 3b (lo publicado) + el doble de las 4 funciones de permisos vivas y, si no se pide
# «solo_3b», la migración del Corte 4a.
set -e
cd "$(dirname "$0")/.."
C3B=${C3B:-$(cd .. && pwd)/redes_corte3b}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C3B/pruebas_locales/rehacer_base.sh" >/dev/null
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_permisos.sql
if [ "$1" != "solo_3b" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte4a_editor.sql
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_extra.sql
fi
echo "redes_local lista ($1)"
