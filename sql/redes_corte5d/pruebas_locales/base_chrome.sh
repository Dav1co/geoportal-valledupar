#!/bin/sh
# Plantilla de Code B para el arnés y la prueba de Chrome del 5d: producción hoy (9a-bis + lo del Corte 8) y la migración del 5d. Queda como «<base>_5dt».
# Solo en el clúster de Code B (puerto 55442).
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
sh pruebas_locales/rehacer_base.sh con_5d >/dev/null
$PSQL -q -X -d postgres -c "drop database if exists ${BASE}_5dt" -c "create database ${BASE}_5dt template $BASE"
echo "plantilla ${BASE}_5dt lista (producción hoy + 5d)"
