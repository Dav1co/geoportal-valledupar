# Técnica · fase 1 · Corte 6a — geovisor técnico (base) y quién carga cada capa

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local de Homebrew con la carga real del 1a (35.781 activos), la MUE y los Cortes 2 a 5c.

El Corte 6 del plan se partió en **6a** (este) y **6b** (contratos con su tarjeta auditada, compartir la vista con enlace y la capa de reportes de Comercial).

## Huellas
- Antes (5c): `a5ce1ff8c5659de3b853e30f4d3025e6` · después (6a): `91a4d3e6e1c3539d8a447cb00a52d735`.

## Orden para publicar (en el editor SQL)
1. `huellas_solo_lectura_redes_corte6a_editor.sql`: «CORTE 5c (listo para el 6a)», 4 RPC «NO EXISTE», 10 «CORTE 5c (sin cambiar)», 3 tablas y 1 columna «NO EXISTE». Si algo dice DISTINTA, parar y avisar.
2. `ensayo_en_transaccion_redes_corte6a_editor.sql`: ERROR con «**93 de 93** … SIN FALLAS».
3. `migracion_redes_corte6a_editor.sql`.
4. `verificacion_redes_corte6a_editor.sql`: 9 OK (más 1 INFO).
5. Huellas otra vez: «CORTE 6a (aplicado)», 4 «NUEVA», 10 «CORTE 6a (reemplazada)», 4 «EXISTE».
6. Edge `geoportal-redes` (rama `tecnica-corte6a` de geoportal-web) y después el frontend (rama `tecnica-corte6a`).

## Qué lleva
- **Quién carga (David, 16-nov 01:30):** columna nueva `redes.capas.carga_supervisor`; el supervisor de distribución carga las 13 capas que no son del modelo (acometidas, captaciones, aducción, desarenadores, bombeo AP y AR, sumideros, interceptores, PTAR, sectores, sensores, SCADA y muestreo). Acueducto, conductos, pozos y descargas: solo el administrador. Funciones nuevas `redes.f_autorizar_carga` y `f_autorizar_carga_id`; se reemplazan 9 RPC del Cargue (la de psql del 1a, no). El origen del activo, al devolver un campo, sigue siendo solo del administrador.
- **Geovisor:** `redes.geovisor_capas` (19 capas: 7 de tesela, 4 por GeoJSON y 8 preparadas), `redes.capas_por_perfil` y sus eventos (N-11), 8 parámetros `geovisor_*`, `redes.f_geovisor_acceso` (N-13), y 4 RPC: `geoportal_redes_geovisor`, `_geovisor_mvt`, `_geovisor_capa` y `_geovisor_capas_fijar`. `geoportal_redes_mi_perfil` trae «geovisor».
- Sin contratos, nombres, descripciones, direcciones del bot ni el tercero de un daño.

## Pruebas
- Ensayo 93 de 93 (sobre la base con la carga real y sin ella).
- Arnés local 21 de 21 (`resultados/sql_local.txt`): huellas, ensayo sin rastro, migración, verificación, guardia, reversa vacía exacta al 5c, migrar de nuevo, peso de la tesela real (z12 vacía, z13 59 KB, z14 la mayor de 20 teselas 189 KB), los 27 puntos MUE, reversa con datos (rechazo).

## Reversa
`reversa_redes_corte6a_editor.sql`: deja las 10 funciones con su texto del 5c, quita lo nuevo y la columna. Se niega si ya hay cambios de las capas por omisión o cargas abiertas por un supervisor después de la migración.
