#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): 1a + Corte 2 + Corte 3a (con sus dobles) y, si no se pide «solo_3a», la migración del Corte 3b.
# Paquetes: C1A (worktree tecnica-corte1a), y redes_corte2 y redes_corte3a de esta misma rama.
set -e
cd "$(dirname "$0")/.."
C3A=${C3A:-$(cd .. && pwd)/redes_corte3a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
sh "$C3A/pruebas_locales/rehacer_base.sh" >/dev/null
if [ "$1" != "solo_3a" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte3b_editor.sql
fi
echo "redes_local lista ($1)"
