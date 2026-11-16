# Técnica · fase 1 · Corte 7a — químicos de planta (bodega, ficha técnica, dosis óptima y esperado contra usado) y respuestas al 6b

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local (todo hasta el 6b, con la carga real, la MUE y contratos sintéticos) y
con un doble de lo vivo de planta copiado del paquete «químicos y dosis» (`pruebas_locales/base_viva_7a.sql`).

El Corte 7 se partió en **7a** (este: motor, Edge y la pestaña «Químicos» del Dashboard PTAP) y **7b** (las pantallas del operador: Entrada y Uso de químicos).
**Se publica después del 6a y el 6b.**

## Huellas
- Antes (6b): `fca28bf695d1fcfa153f1113ce821528` · después (7a): `f6c14c268aaedb5ab243f87685b428dd` (conjunto de funciones de redes; lo de químicos va por tablas y md5 de sus 11 RPC).

## Orden para publicar (en el editor SQL, después del 6b)
1. `huellas_solo_lectura_tecnica_corte7a_editor.sql`: «CORTE 6b (listo para el 7a)», 11 RPC y 7 objetos «NO EXISTE», 2 «CORTE 6b (sin cambiar)». Si algo dice DISTINTA, parar y avisar.
2. `ensayo_en_transaccion_tecnica_corte7a_editor.sql`: ERROR con «**55 de 55** … SIN FALLAS» (crea sus personas, químicos «ZT7 …», PDF en Storage, caudales de Entrada del día y un contrato de prueba; el ERROR final lo deshace).
3. `migracion_tecnica_corte7a_editor.sql`.
4. `verificacion_tecnica_corte7a_editor.sql`: 9 OK (más 1 INFO).
5. Huellas otra vez: «CORTE 7a (aplicado)», 11 «NUEVA», 2 «CORTE 7a (reemplazada)», 7 «EXISTE».
6. Edge `geoportal-tecnica` (rama `tecnica-corte7a`; lleva también lo del 6a y el 6b en `geoportal-redes`) y el frontend (rama `tecnica-corte7a`).

## Qué lleva
- Respuestas al 6b: `redes.f_estado_contrato` (suspendido y cortado) y `geoportal_redes_contrato_tarjeta` (nombre y dirección solo para administrador y supervisor de distribución); CHECK de estados de `redes.contratos_capa`; muestreo a 35 días con su evento.
- Químicos: `tecnica.quimico_ficha_eventos`, `quimico_ficha_preparaciones`, `quimico_movimientos`, `quimico_parametros`; vistas `v_quimico_vigente` y `v_quimico_saldo`; 11 RPC `geoportal_tec_quimic*`; bucket privado `tecnica-evidencias`.
- ⚠ `tecnica.quimicos` (viva): CHECK de rol con «auxiliar», candado de identidad (el nombre no cambia) y el hipoclorito de calcio. `tecnica.uso_quimicos` no se toca.

## Pruebas
- Ensayo 55 de 55. Arnés local 17 de 17 (`resultados/sql_local.txt`).

## Reversa
`reversa_tecnica_corte7a_editor.sql`: las 2 funciones de redes vuelven al texto del 6b; se quitan lo de químicos y el candado; el hipoclorito queda desactivado; el bucket (vacío) se queda porque Storage no deja borrarlo por SQL. Se niega si ya hay movimientos, fichas, archivos o químicos nuevos.
