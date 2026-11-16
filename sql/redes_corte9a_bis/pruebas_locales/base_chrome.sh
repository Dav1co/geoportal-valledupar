#!/bin/sh
# Plantilla de Code B para el arnés y las pruebas de Chrome del 9a-bis: producción hoy (9a + su carga), la migración del 9a-bis y la carga de los sectores
# oficiales (carga_sectores/generado/sectores_oficiales.sql). Queda como «<base>_bis». Solo en el clúster de Code B (puerto 55442).
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
sh pruebas_locales/rehacer_base.sh con_bis >/dev/null
(cd carga_sectores/generado && $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f sectores_oficiales.sql >/dev/null 2>&1)
$PSQL -q -X -d postgres -c "drop database if exists ${BASE}_bis" -c "create database ${BASE}_bis template $BASE"
echo "plantilla ${BASE}_bis lista (9a-bis + sectores oficiales)"
