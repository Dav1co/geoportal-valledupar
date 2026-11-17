#!/bin/sh
# Base local de CODE A para el Corte 9b, Fase 3 (localhost:55432, base redes_local): producción + 9b (1a + 1b) + Fase 2, que se publican antes.
#   sh rehacer_base.sh          → hasta la Fase 2 (huella 7f9c0157…)
#   sh rehacer_base.sh con_f3   → además, la migración de la Fase 3
#   sh rehacer_base.sh cargada  → además, la carga del flujo del modelo (carga_flujo/generado/carga_flujo_modelo.sql)
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
sh ../redes_corte9b_f2/pruebas_locales/rehacer_base.sh con_f2 >/dev/null
if [ "$1" = "con_f3" ] || [ "$1" = "cargada" ]; then $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte9b_f3_editor.sql >/dev/null; fi
if [ "$1" = "cargada" ]; then
  $PSQL -q -X -d redes_local -c "insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('carga.local@emdupar.gov.co', 'Carga local', 'admin', 'sin_restriccion', 'todos') on conflict do nothing" >/dev/null
  (cd carga_flujo/generado && $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -v solicitante=carga.local@emdupar.gov.co -f carga_flujo_modelo.sql >/dev/null)
fi
echo "redes_local lista (Fase 2 $1)"
