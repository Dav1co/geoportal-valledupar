#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, localhost:55432; base de Code A) como producción hoy: 7a + 9a + 9a-bis + 7c + 5d (la base de Chrome integrada del 7c)
# y, si no se pide «sin_12», aplica la migración del Corte 12.
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55432} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
echo "base: redes_local en localhost:$PGPORT (por omisión 55432, Code A; PGPORT_B lo cambia)"
sh ../tecnica_corte7c/pruebas_locales/base_chrome_integrada.sh >/dev/null
# el rol del Dell es de todo el clúster (no de la base): se quita para que la migración lo cree de nuevo, como en producción
$PSQL -q -X -d redes_local -c "drop role if exists dell_avisos" >/dev/null
# 5d (Code B) ya publicado en producción (huella de redes 5fd6d00e…): la base lo lleva antes del 12
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/dominio_corte8.sql >/dev/null
# las reglas de producción de las tablas de tecnica que usan las pruebas (el doble de planta no las traía; falla del ensayo del 16-nov)
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/reglas_tecnica_produccion.sql >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte5d/migracion_redes_corte5d_editor.sql >/dev/null
if [ "$1" != "sin_12" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte12_editor.sql >/dev/null
fi
echo "redes_local lista ($1)"
