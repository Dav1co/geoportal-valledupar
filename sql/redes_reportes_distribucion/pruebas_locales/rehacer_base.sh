#!/bin/sh
# Base local de CODE A para los reportes del PTAP y las descargas de Distribución (localhost:55432, base redes_local): producción al 20-nov
# (huella de redes b474fbbe…: todo hasta el aviso por contrato) + el doble de planta de la Torre B que leen los reportes del PTAP
# (../../tecnica_reportes_ptap/pruebas_locales/doble_ptap_produccion.sql). La plantilla «redes_rep_base» se arma una vez.
#   sh rehacer_base.sh            → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_dist   → además, la migración de las descargas de Distribución
#   sh rehacer_base.sh con_todo   → además, la de los reportes del PTAP
#   sh rehacer_base.sh plantilla  → rehace también la plantilla
set -e
# Pasada de herramientas (20-nov): -h/--help imprime el uso y sale; un modo que no conoce es error. Es local (55432): no consulta Supabase.
case "${1:-}" in
  -h|--help) sed -n '2,8p' "$0" | sed -e 's/^# \{0,1\}//'; exit 0;;
  ""|con_dist|con_todo|plantilla) ;;
  *) echo "Modo u opción desconocida: $1 (use con_dist, con_todo, plantilla o nada; -h para el uso)" >&2; exit 2;;
esac
[ $# -le 1 ] || { echo "Sobran argumentos (-h para el uso)" >&2; exit 2; }
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_rep_base'")" ]; then
  sh ../redes_aviso_evento_contrato/pruebas_locales/rehacer_base.sh con_evc >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -1 -f ../tecnica_reportes_ptap/pruebas_locales/doble_ptap_produccion.sql >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists redes_rep_base" -c "create database redes_rep_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_rep_base"
if [ "$1" = "con_dist" ] || [ "$1" = "con_todo" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_reportes_distribucion_editor.sql >/dev/null; fi
if [ "$1" = "con_todo" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../tecnica_reportes_ptap/migracion_tecnica_reportes_ptap_editor.sql >/dev/null; fi
echo "redes_local lista (producción al 20-nov $1)"
