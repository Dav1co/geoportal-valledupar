#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, localhost:55432) como producción con el 7a publicado y, si no se pide «solo_7a», aplica la migración del Corte 7c.
set -e
cd "$(dirname "$0")/.."
C7A=${C7A:-$(cd .. && pwd)/tecnica_corte7a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
echo "base: redes_local en $PGHOST:$PGPORT"
sh "$C7A/pruebas_locales/${BASE7A:-rehacer_base.sh}" >/dev/null 2>&1
if [ "$1" != "solo_7a" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte7c_editor.sql >/dev/null
fi
echo "redes_local lista ($1)"
