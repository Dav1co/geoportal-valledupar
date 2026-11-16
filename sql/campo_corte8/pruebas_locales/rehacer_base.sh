#!/bin/sh
# Rehace la base local del Corte 8 (campo_local en el clúster propio de localhost:55434) y, si no se pide «solo_base», aplica la migración del Corte 8.
set -e
cd "$(dirname "$0")"
PY=${PY:-/opt/anaconda3/bin/python3}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export CAMPO_DB=${CAMPO_DB:-campo_local}
echo "base: $CAMPO_DB en localhost:55434"
$PY base_campo.py >/dev/null
if [ "$1" != "solo_base" ]; then
  PGHOST=localhost PGPORT=55434 PGUSER=postgres $PSQL -q -X -d "$CAMPO_DB" -v ON_ERROR_STOP=1 -f ../migracion_tecnica_corte8_editor.sql >/dev/null
fi
echo "campo_local lista ($1)"
