#!/bin/sh
# Base local de CODE A para los reportes del PTAP: la misma de las descargas de Distribución (../../redes_reportes_distribucion/pruebas_locales/rehacer_base.sh),
# que es producción al 20-nov (huella de redes b474fbbe…) + el doble de planta de la Torre B (doble_ptap_produccion.sql).
#   sh rehacer_base.sh           → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_ptap  → además, la migración de los reportes del PTAP
#   sh rehacer_base.sh con_todo  → además, antes, la de las descargas de Distribución
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
case "$1" in
  con_todo) sh ../redes_reportes_distribucion/pruebas_locales/rehacer_base.sh con_todo >/dev/null ;;
  con_ptap) sh ../redes_reportes_distribucion/pruebas_locales/rehacer_base.sh >/dev/null
            $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_reportes_ptap_editor.sql >/dev/null ;;
  *) sh ../redes_reportes_distribucion/pruebas_locales/rehacer_base.sh $1 >/dev/null ;;
esac
echo "redes_local lista (producción al 20-nov $1)"
