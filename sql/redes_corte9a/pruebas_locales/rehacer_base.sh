#!/bin/sh
# Base local de CODE B (reglas_dos_code_en_paralelo.md): clúster PROPIO en el puerto 55442 y bases propias (emdupar_b y su plantilla emdupar_b_base).
# NUNCA toca el clúster ni las bases de Code A (puerto 55432, redes_local): se niega si el puerto es ese o si el clúster no es el de B.
#   sh rehacer_base.sh             → emdupar_b = copia limpia de la plantilla (producción hasta el 7a, con el volumen real y los contratos sintéticos)
#   sh rehacer_base.sh plantilla   → además rehace la plantilla desde la cadena del arnés (1a … 7a; varios minutos)
#   sh rehacer_base.sh con_9a      → emdupar_b con la migración del 9a aplicada
# El clúster de B se marca con el archivo ES_DE_CODE_B en su directorio de datos (lo crea quien lo inicia).
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
DATOS=$($PSQL -d postgres -AtXc 'show data_directory')
[ -f "$DATOS/ES_DE_CODE_B" ] || { echo "El clúster del puerto $PGPORT ($DATOS) no está marcado como de Code B: no se toca"; exit 1; }
echo "Clúster de Code B: $DATOS (puerto $PGPORT). Base que se rehace: $BASE"
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = '${BASE}_base'")" ]; then
  # la cadena del arnés crea «redes_local» (nombre fijo en los cortes anteriores) EN ESTE clúster; aquí se renombra a la plantilla de B
  sh ../tecnica_corte7a/pruebas_locales/base_chrome.sh >/dev/null
  $PSQL -q -X -d postgres -c "drop database if exists ${BASE}_base" -c "alter database redes_local rename to ${BASE}_base"
fi
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template ${BASE}_base"
if [ "$1" = "con_9a" ]; then
  $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte9a_editor.sql >/dev/null
fi
echo "$BASE lista ($1)"
