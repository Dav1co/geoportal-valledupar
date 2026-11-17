#!/bin/sh
# Base local de CODE B para el Corte 14 (clúster propio, puerto 55442; nunca el 55432 de Code A). Producción al publicar = el 9b completo (huella final a327aa51…).
# La plantilla «emdupar_b_14base» = emdupar_b_9bt (el 10 + el doble mínimo del 12 + el 9b 1a y 1b) + las migraciones de las Fases 2 y 3 del 9b (rama tecnica-corte9b)
#   + la carga del flujo + doble_campo_personal_base_local.sql (lo mínimo de «campo» que toca el 14, con el texto y el CHECK de producción).
#   sh rehacer_base.sh          → emdupar_b14 = copia limpia de la plantilla (como producción al publicar)
#   sh rehacer_base.sh con_14   → además, la migración del 14
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=${PGPORT_B:-55442} PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
BASE=${BASE_B:-emdupar_b14}
[ "$PGPORT" != "55432" ] || { echo "El puerto 55432 es de Code A: no se toca"; exit 1; }
[ -f "$($PSQL -d postgres -AtXc 'show data_directory')/ES_DE_CODE_B" ] || { echo "Ese clúster no es el de Code B: no se toca"; exit 1; }
if [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'emdupar_b_14base'")" ]; then
  [ -n "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'emdupar_b_9bt'")" ] || { echo "Falta la base emdupar_b_9bt (el 10 + el 9b 1a y 1b)"; exit 1; }
  $PSQL -q -X -d postgres -c "create database emdupar_b_14base template emdupar_b_9bt"
  $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -f ../redes_corte9b_f2/migracion_redes_corte9b_f2_editor.sql >/dev/null
  $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -f ../redes_corte9b_f3/migracion_redes_corte9b_f3_editor.sql >/dev/null
  $PSQL -q -X -d emdupar_b_14base -c "insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('carga.local@emdupar.gov.co', 'Carga local', 'admin', 'sin_restriccion', 'todos') on conflict do nothing" >/dev/null
  (cd ../redes_corte9b_f3/carga_flujo/generado && $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f carga_flujo_modelo.sql >/dev/null)
  $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -f ../redes_corte9b_f3/encender_flujo_modelo_editor.sql >/dev/null
  $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -f pruebas_locales/doble_campo_personal_base_local.sql >/dev/null
  $PSQL -q -X -d emdupar_b_14base -v ON_ERROR_STOP=1 -f pruebas_locales/doble_avisos_funciones_base_local.sql >/dev/null
fi
$PSQL -q -X -d postgres -c "drop database if exists $BASE" -c "create database $BASE template emdupar_b_14base"
if [ "$1" = "con_14" ]; then $PSQL -q -X -d "$BASE" -v ON_ERROR_STOP=1 -f migracion_redes_corte14_editor.sql >/dev/null; fi
echo "$BASE lista ($1)"
