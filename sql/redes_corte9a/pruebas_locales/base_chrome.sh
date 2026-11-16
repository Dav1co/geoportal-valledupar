#!/bin/sh
# Base de Code B para las pruebas de Chrome y el arnés del Corte 9a: la plantilla (producción hasta el 7a, volumen real y contratos sintéticos), la migración del 9a
# y la CARGA REAL del Plan Maestro (carga_pm/generado: carga_pm_todo.sql y publicar_pm.sql). Queda como plantilla «<base>_9a»; cada prueba saca su copia.
# Solo en el clúster de Code B (puerto 55442; ver rehacer_base.sh). Uso: sh base_chrome.sh
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
sh pruebas_locales/rehacer_base.sh con_9a >/dev/null
(cd carga_pm/generado && $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f carga_pm_todo.sql >/dev/null \
  && $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f publicar_pm.sql >/dev/null 2>&1)
# el enlace contrato → tramo de los contratos sintéticos (en producción ya existe; aquí se calcula una vez, por conexión directa)
$PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -c "select redes.f_recalcular_contrato_tramo()" >/dev/null
$PSQL -q -X -d postgres -c "drop database if exists ${BASE}_9a" -c "create database ${BASE}_9a template $BASE"
echo "plantilla ${BASE}_9a lista (9a + carga del Plan Maestro)"
