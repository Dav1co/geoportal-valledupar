#!/bin/sh
# Base para la prueba de Chrome y el arnés del Corte 7a: la del 6b (carga real, MUE, contratos sintéticos y el 6b), el doble de planta del 7a, un caudal de
# Entrada de 3 días para las dos plantas y, si no se pide «solo_6b», la migración del 7a.
set -e
cd "$(dirname "$0")/.."
C6B=$(cd .. && pwd)/redes_corte6b
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres} PGOPTIONS='-c client_min_messages=warning'
sh "$C6B/pruebas_locales/base_chrome.sh" >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_7a.sql >/dev/null
$PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -c "insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, p.id, case p.codigo when 'huaricha' then 1000 else 400 end, (clock_timestamp() at time zone 'America/Bogota')::date - d, make_time(h, 0, 0), 'zt.oper@emdupar.gov.co'
    from tecnica.variables v cross join tecnica.plantas p cross join generate_series(0, 2) d cross join generate_series(0, 22, 2) h where v.codigo = 'caudal_qi'" >/dev/null
if [ "$1" != "solo_6b" ]; then
  $PSQL -q -X -d redes_local -v ON_ERROR_STOP=1 -f migracion_tecnica_corte7a_editor.sql >/dev/null
fi
echo "base de Chrome lista"
