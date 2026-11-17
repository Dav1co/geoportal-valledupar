#!/bin/sh
# Base local de CODE A para el Corte 9b, Fase 2 (localhost:55432, base redes_local): producción + el paquete del 9b (1a + 1b), que se publica antes.
#   sh rehacer_base.sh          → redes_local con la migración del 9b (1a + 1b): huella 895517fb…
#   sh rehacer_base.sh con_f2   → además, la migración de la Fase 2
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
sh ../redes_corte9b/pruebas_locales/rehacer_base.sh con_9b >/dev/null
if [ "$1" = "con_f2" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte9b_f2_editor.sql >/dev/null; fi
echo "redes_local lista (9b $1)"
