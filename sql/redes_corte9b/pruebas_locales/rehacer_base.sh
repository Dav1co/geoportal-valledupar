#!/bin/sh
# Base local de CODE A para el Corte 9b (localhost:55432, base redes_local; nunca el 55442 de Code B).
# Producción hoy (17-nov): la base integrada del 12 (7a + 9a + 9a-bis + 7c + 5d + 12, con los CHECK de producción de tecnica) + la migración del 10
# (huella de redes aad5952c…) + las reglas de producción de lista blanca y auditoría + contrato_tramo calculado (en producción se calcula al publicar el acueducto).
# La primera vez queda como plantilla «redes_9bbase»; después cada llamada copia la plantilla.
#   sh rehacer_base.sh          → redes_local = copia limpia de la plantilla (como producción hoy)
#   sh rehacer_base.sh con_9b   → además, la migración del 9b
#   sh rehacer_base.sh plantilla → rehace también la plantilla
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
[ "$PGPORT" = "55432" ] || { echo "Solo en el clúster de Code A (55432)"; exit 1; }
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_9bbase'")" ]; then
  sh ../tecnica_corte12/pruebas_locales/rehacer_base.sh >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte10/migracion_redes_corte10_editor.sql >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/reglas_produccion.sql >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -c "select redes.f_recalcular_contrato_tramo()" -c "analyze" >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_9bbase" -c "create database redes_9bbase template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_9bbase"
if [ "$1" = "con_9b" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte9b_editor.sql >/dev/null; fi
echo "redes_local lista ($1)"
