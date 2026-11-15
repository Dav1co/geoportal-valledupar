#!/bin/sh
# Rehace redes_local (PostGIS de Homebrew, puerto 55432): doble del 1a + migración del 1a + doble del Corte 2 y, si no se pide «solo_1a», la migración del Corte 2.
# El paquete del 1a se toma de C1A (por omisión, el worktree tecnica-corte1a).
set -e
cd "$(dirname "$0")/.."
C1A=${C1A:-$HOME/geoportal-emdupar-tec-c1a/sql/redes_corte1a}
PSQL=${PSQL:-/opt/homebrew/opt/postgresql@17/bin/psql}
export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-55432} PGUSER=${PGUSER:-postgres}
$PSQL -q -d postgres -c "drop database if exists redes_local" -c "create database redes_local"
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -c "create extension postgis" -f "$C1A/pruebas_locales/base_viva_minima.sql"
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f "$C1A/migracion_redes_corte1a_editor.sql"
$PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f pruebas_locales/base_viva_extra.sql
if [ "$1" != "solo_1a" ]; then
  $PSQL -q -d redes_local -v ON_ERROR_STOP=1 -f migracion_redes_corte2_editor.sql
fi
echo "redes_local lista ($1)"
