#!/bin/sh
# Base para la prueba de Chrome y el arnés del Corte 6b: lo del 6a con la carga real del 1a y la MUE publicadas, los dobles del 6b con contratos SINTÉTICOS
# (111.950 predios sobre la red real, su cartera y su ficha: ningún dato real) y, si no se pide «solo_6a», la migración del 6b.
set -e
cd "$(dirname "$0")/.."
C1A=${C1A:-$HOME/geoportal-emdupar-tec-c1a/sql/redes_corte1a}
MUE=$(cd .. && pwd)/redes_corte5a/carga_mue/generado
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres} PGOPTIONS='-c client_min_messages=warning'
sh pruebas_locales/rehacer_base.sh solo_6a >/dev/null
(cd "$C1A/carga/generado" && $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f carga_inicial_todo.sql >/dev/null && $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f publicar.sql >/dev/null)
(cd "$MUE" && $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f carga_mue_todo.sql >/dev/null && $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f publicar_mue.sql >/dev/null)
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/contratos_sinteticos.sql >/dev/null
if [ "$1" != "solo_6a" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte6b_editor.sql >/dev/null
fi
echo "base de Chrome lista"
