# Técnica · fase 1 · Corte 7a (REGENERADO sobre el 6c) — químicos de planta y respuestas al 6b, al 6c y al 7a

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local armado como producción (todo hasta el 6c, huella `2c265800…`, con la
carga real, la MUE y 111.950 contratos sintéticos) y con un doble de lo vivo de planta (`pruebas_locales/base_viva_7a.sql`).
**Reemplaza al paquete del 7a hecho sobre el 6b** (huella `f6c14c26…`), que ya no se puede aplicar: su guardia espera el 6b.

## Huellas
- Antes (6c, producción): `2c2658002d114d755f19a7b5f5dfe542` · después (7a): `79f184a4fe37ed2baa67dac7f3dd9b3c` (conjunto de funciones de redes; lo de químicos va por tablas y md5 de sus 11 RPC).

## Orden para publicar (en el editor SQL)
1. `huellas_solo_lectura_tecnica_corte7a_editor.sql`: «CORTE 6c (listo para el 7a)», 11 RPC y 7 objetos «NO EXISTE», 4 «CORTE 6c (sin cambiar)». Si algo dice DISTINTA, parar y avisar.
2. `ensayo_en_transaccion_tecnica_corte7a_editor.sql`: ERROR con «**65 de 65** … SIN FALLAS». La línea **TIEMPOS** dice cuánto tarda la configuración del geovisor con la
   fecha del corte (lee toda la cartera diaria; la prueba 01.09b exige menos de 2 s). La prueba 01.10 revisa también las RPC vivas de planta (`geoportal_tec_*`):
   si marca alguna, parar y avisar con el texto que salga.
3. `migracion_tecnica_corte7a_editor.sql`.
4. `verificacion_tecnica_corte7a_editor.sql`: 11 OK (más 2 INFO).
5. Huellas otra vez: «CORTE 7a (aplicado)», 11 «NUEVA», 4 «CORTE 7a (reemplazada)», 7 «EXISTE».
6. Edge `geoportal-tecnica` (rama `tecnica-corte7a` de geoportal-web, sin cambios desde `6746020`) y el frontend (rama `tecnica-corte7a`, que ya lleva el 6c).

## Qué cambió al regenerarlo
- Sale del 6c: ya no toca `redes.contratos_capa` (no existe). `redes.f_estado_contrato` (suspendido y cortado) sigue: la tesela y la tarjeta lo toman solas.
- `geoportal_redes_contrato_tarjeta` se rehízo sobre el texto del 6c (nombre y dirección solo para administrador y supervisor de distribución).
- **Nuevo:** `geoportal_redes_geovisor` devuelve `contratos_corte` (AAAAMMDD del último corte de la cartera, solo a supervisores) y la capa de contratos muestra
  la nota «Estado según la cartera del 14-nov-2026». Sigue STABLE.
- **Nuevo:** `redes.f_funciones_sin_where` cubre también `public.geoportal_tec_*` (las RPC de químicos entran por la API).
- **Nuevo:** el formulario de químicos devuelve `unidades: ["t", "kg"]`. La entrada va en toneladas o kg, nunca por cilindros (la RPC y la tabla lo rechazan).
- Sin cambio, ahora con prueba propia: el desvío queda en 25 % (editable) y los días con dosis y caudal sin uso salen con usado 0 y la marca.

## Qué lleva (igual que antes)
- Químicos: `tecnica.quimico_ficha_eventos`, `quimico_ficha_preparaciones`, `quimico_movimientos`, `quimico_parametros`; vistas `v_quimico_vigente` y `v_quimico_saldo`; 11 RPC `geoportal_tec_quimic*`; bucket privado `tecnica-evidencias`.
- ⚠ `tecnica.quimicos` (viva): CHECK de rol con «auxiliar», candado de identidad y el hipoclorito de calcio. `tecnica.uso_quimicos` no se toca. Muestreo a 35 días con su evento.

## Pruebas
- Ensayo 65 de 65. Arnés local 17 de 17 (`resultados/sql_local.txt`), con las RPC llamadas como la Edge (service_role, 30 s y 8 s).
- Chrome real a 390 px y 1280 px: químicos 40 de 40 (`resultados/chrome.txt`) y geovisor 54 de 54 con la nota del corte (`resultados/chrome_geovisor.txt`).

## Reversa
`reversa_tecnica_corte7a_editor.sql`: las 4 funciones de redes vuelven al texto del 6c; se quitan lo de químicos y el candado; el hipoclorito queda desactivado; el bucket
(vacío) se queda. Se niega si ya hay movimientos, fichas, archivos o químicos nuevos.
