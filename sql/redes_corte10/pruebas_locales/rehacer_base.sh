#!/bin/sh
# Base local de CODE B para el Corte 10 (clúster propio, puerto 55442; nunca el 55432 de Code A). Producción hoy = el 5d publicado (huella 5fd6d00e…).
# La plantilla «emdupar_b_10base» = emdupar_b_5dbase + la migración del 5d + las reglas de producción de los dobles (reglas_produccion.sql).
#   sh rehacer_base.sh          → emdupar_b = copia limpia de la plantilla (como producción hoy)
#   sh rehacer_base.sh con_10   → además, la migración del 10
#   sh rehacer_base.sh cargada  → además, la carga de la valoración y de los amarres (carga_val/generado/carga_valoracion.sql)
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
[ -f "$($PSQL -d postgres -AtXc 'show data_directory')/ES_DE_CODE_B" ] || { echo "Ese clúster no es el de Code B: no se toca"; exit 1; }
if [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_10base'")" ]; then
  [ -n "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_5dbase'")" ] || { echo "Falta la plantilla ${BASE}_5dbase (../redes_corte5d/pruebas_locales/rehacer_base.sh)"; exit 1; }
  $PSQL -q -X -d postgres -c "create database ${BASE}_10base template ${BASE}_5dbase"
  $PSQL -q -X -d "${BASE}_10base" -v ON_ERROR_STOP=1 -f ../redes_corte5d/migracion_redes_corte5d_editor.sql >/dev/null
  $PSQL -q -X -d "${BASE}_10base" -v ON_ERROR_STOP=1 -f pruebas_locales/reglas_produccion.sql >/dev/null
fi
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template ${BASE}_10base"
if [ "$1" = "con_10" ] || [ "$1" = "cargada" ]; then $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte10_editor.sql >/dev/null; fi
if [ "$1" = "cargada" ]; then
  (cd carga_val/generado && $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -v solicitante="${ADMIN_LOCAL:-carga.local@emdupar.gov.co}" -f carga_valoracion.sql >/dev/null)
  [ -n "$($PSQL -d "$BASE" -AtXc "select 1 from redes.v_ref_carga_vigente where conjunto = 'val_amarre'")" ] || { echo "La valoración no quedó cargada (¿el correo es de un administrador?)"; exit 1; }
fi
echo "$BASE lista ($1)"
