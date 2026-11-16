#!/bin/sh
# Rearma el ensayo (sin rehacer el paquete) y lo corre sobre la base del 5c. Uso: sh ensayo.sh
set -e
cd "$(dirname "$0")/.."
export PGHOST=localhost PGPORT=55432 PGUSER=postgres
P=/opt/homebrew/opt/postgresql@17/bin/psql
{ echo 'begin;'; cat sql/10_esquema.sql sql/26_rpc.sql sql/25_reemplazos.sql sql/40_permisos.sql sql/70_pruebas.sql; echo 'rollback;'; } > ensayo_en_transaccion_redes_corte6a_editor.sql
sh pruebas_locales/rehacer_base.sh solo_5c >/dev/null
$P -X -d redes_local -f ensayo_en_transaccion_redes_corte6a_editor.sql 2>&1 | grep -v "^CREATE\|^BEGIN\|^ALTER\|^INSERT\|^UPDATE\|^DO\|^COMMENT\|^REVOKE\|^ROLLBACK\|^GRANT\|^SET\|^$" | head -60
