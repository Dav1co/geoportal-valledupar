#!/bin/sh
# Base de Code A para las REGRESIONES de Chrome del Corte 9b (Fase 4): producción + 9b (1a + 1b) + Fase 2 + Fase 3 + la carga del flujo del modelo.
# Queda en redes_local (localhost:55432). La usan los guiones de Chrome que reciben un script de base (inicio, avisos, estilo, geovisor, dashboards).
set -e
sh "$(dirname "$0")/rehacer_base.sh" cargada >/dev/null
echo "redes_local lista (todo el 9b)"
