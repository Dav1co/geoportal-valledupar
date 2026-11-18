#!/bin/sh
# Base local de CODE A para «Cierre por aguas arriba» (localhost:55432, base redes_local): producción con el Corte 14 publicado (huella 1a9ef250…).
# La plantilla «redes_au_base» = todo el 9b + la carga del flujo + la capa encendida + lo mínimo de «campo» que pide el 14 (su doble) + la migración del 14
#   + las tablas de referencia del Plan Maestro (cotas), si su carga está en paquete_fase1/corte9a/carga_pm.
#   sh rehacer_base.sh          → redes_local = copia limpia de la plantilla
#   sh rehacer_base.sh con_au   → además, la migración de este paquete
#   sh rehacer_base.sh plantilla → rehace también la plantilla
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
if [ "$1" = "plantilla" ] || [ -z "$($PSQL -d postgres -AtXc "select 1 from pg_database where datname = 'redes_au_base'")" ]; then
  sh ../redes_corte9b_f3/pruebas_locales/base_chrome.sh >/dev/null 2>&1
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte9b_f3/encender_flujo_modelo_editor.sql >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte14/pruebas_locales/doble_campo_personal_base_local.sql >/dev/null
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte14/migracion_redes_corte14_editor.sql >/dev/null
  # el Plan Maestro (cotas de los nodos), como en producción: su carga está fuera del repositorio (paquete_fase1/corte9a/carga_pm); si no está, la base queda sin cotas
  PM="${CARGA_PM:-$HOME/geoportal-consultas/tecnica/paquete_fase1/corte9a/carga_pm}/partes/10_referencia.sql"
  if [ -f "$PM" ]; then
    $PSQL -q -X -d redes_local -c "insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('carga.local@emdupar.gov.co', 'Carga local', 'admin', 'sin_restriccion', 'todos') on conflict do nothing" >/dev/null
    (echo "begin;"; cat "$PM"; echo "commit;") | $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f - >/dev/null
    $PSQL -q -X -d redes_local -c "analyze" >/dev/null
  else echo "AVISO: no está la carga del Plan Maestro ($PM): la base queda sin cotas"; fi
  $PSQL -q -X -d postgres -c "drop database if exists redes_au_base" -c "create database redes_au_base template redes_local"
fi
$PSQL -q -X -d postgres -c "drop database if exists redes_local" -c "create database redes_local template redes_au_base"
if [ "$1" = "con_au" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_9b_aguasarriba_editor.sql >/dev/null; fi
echo "redes_local lista (Corte 14 $1)"
