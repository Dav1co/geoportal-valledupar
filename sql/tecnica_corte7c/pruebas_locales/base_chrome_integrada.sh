#!/bin/sh
# Base de Code A para las pruebas de Chrome DESPUÉS de unir main (16-nov): como producción hoy en lo que toca a las pantallas de Técnica.
# La del 7a (carga real, contratos sintéticos, caudales) + las migraciones del Code B (9a y 9a-bis, sin su carga del Plan Maestro) + la del 7c.
# Solo en el clúster de Code A (localhost:55432, base redes_local). El Corte 8 se prueba en su propia base (campo_local, localhost:55434).
set -e
cd "$(dirname "$0")/.."
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=localhost PGPORT=55432 PGUSER=postgres PGOPTIONS='-c client_min_messages=warning'
echo "base: redes_local en localhost:55432 (Code A)"
sh ../tecnica_corte7a/pruebas_locales/base_chrome.sh >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte9a/migracion_redes_corte9a_editor.sql >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f ../redes_corte9a_bis/migracion_redes_corte9a_bis_editor.sql >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte7c_editor.sql >/dev/null
echo "base de Chrome integrada lista (7a + 9a + 9a-bis + 7c)"
