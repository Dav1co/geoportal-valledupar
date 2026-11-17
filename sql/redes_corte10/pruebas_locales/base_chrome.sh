#!/bin/sh
# Plantilla de Code B para la prueba de Chrome del Corte 10: producción hoy (5d) + la migración del 10 + la carga real de la valoración y los amarres.
# Queda como «<base>_10t». Solo en el clúster de Code B (puerto 55442).
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
sh pruebas_locales/rehacer_base.sh cargada >/dev/null
$PSQL -q -X -d postgres -c "drop database if exists ${BASE}_10t" -c "create database ${BASE}_10t template $BASE"
sh pruebas_locales/rehacer_base.sh >/dev/null
echo "plantilla ${BASE}_10t lista (producción hoy + 10 + valoración cargada)"
