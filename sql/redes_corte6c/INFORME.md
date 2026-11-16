# Técnica · fase 1 · Corte 6c — la capa de contratos fuera de la petición

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local armado como producción el 16-nov: carga real del 1a (35.781 activos),
MUE, Cortes 2 a 6b, el hotfix de pg-safeupdate y 111.950 contratos SINTÉTICOS (predio, cartera y ficha inventados; ningún dato real).

## Qué cambia
- **Ya no hay copia derivada.** La tesela de contratos se arma al vuelo, solo con los predios de su recuadro: GiST de `catastro_valledupar.geom`,
  y por cada predio su ficha (`ficha_contrato_pkey`) y su último corte de cartera (`idx_cartera_contrato`). No se crea ningún índice.
- **Ninguna petición rehace nada.** `geoportal_redes_geovisor` y la tesela vuelven a ser STABLE (solo leen).
- Se retiran `redes.contratos_capa`, `redes.contratos_capa_estado`, `redes.f_refrescar_contratos_capa()` y `redes.f_contratos_capa_al_dia()`.
  No hace falta botón, pg_cron ni cambio en el ETL: la capa está siempre al día con el catastro, la ficha y la cartera.
- La tarjeta del contrato lee el estado y el uso en el momento (ya no de la copia). Lo demás igual: auditoría sin el nombre, sin teléfono ni deuda.
- Nuevas (internas): `redes.f_contrato_uso` y `redes.f_funciones_sin_where` (comprobación estática de pg-safeupdate).

## Huellas
- Antes (6b + hotfix): `8113af17c6bd862d62a6cbc4bc4cba1f` · después (6c): `2c2658002d114d755f19a7b5f5dfe542`.

## Orden para publicar (en el editor SQL)
1. `huellas_solo_lectura_redes_corte6c_editor.sql`: «CORTE 6b + hotfix (listo para el 6c)», 3 «CORTE 6b (sin cambiar)», 2 «NO EXISTE», 4 «EXISTE (sin aplicar)»
   y **los 4 índices «EXISTE»**. Si algo dice DISTINTA o FALTA, parar y avisar.
2. `ensayo_en_transaccion_redes_corte6c_editor.sql`: ERROR con «**35 de 35** … SIN FALLAS». La línea **TIEMPOS** dice cuánto tarda, con los datos reales,
   la tesela de zoom 16 más cargada de la ciudad (la prueba 05.01 exige menos de 8 s). **Copie esa línea.**
3. `migracion_redes_corte6c_editor.sql`.
4. `verificacion_redes_corte6c_editor.sql`: 9 OK (más 1 INFO). La fila 05 es la de pg-safeupdate.
5. Huellas otra vez: «CORTE 6c (aplicado)», 3 «CORTE 6c (reemplazada)», 2 «NUEVA», 4 «RETIRADO».
6. Frontend: rama `tecnica-corte6c` (un cambio: la versión de la tesela de contratos es el día). **La Edge no cambia** (`geoportal-redes` v5 sirve igual).
   El frontend publicado hoy funciona con el SQL nuevo; no hay que esperar al frontend para arreglar el geovisor.

## Pruebas
- Ensayo 35 de 35 (con y sin el volumen real). Arnés local 22 de 22 (`resultados/sql_local.txt`), con las llamadas de la Edge como las ve producción:
  rol `service_role`, `statement_timeout = 30s` y `lock_timeout = 8s`.
- Chrome real a 390 px y 1280 px: 50 de 50 (`resultados/chrome.txt`), con las RPC bajo esos mismos topes; regresión del 6a 68 de 68.
- pg-safeupdate **no** se cargó en local (no se compiló): lo cubre la comprobación estática, en el ensayo (01.04 y 01.05) y en la verificación (05).

## Tiempos medidos en local (volumen real)
- Configuración del geovisor: 28 ms (con el 6b rehacía la copia: 1,1 s en local y 44,7 s en producción).
- Las 150 teselas de contratos de zoom 16 de la ciudad, una por una: la más lenta 72 ms (2.233 predios, 73 KB).
- Tarjeta del contrato: 28 ms.

## Reversa
`reversa_redes_corte6c_editor.sql`: vuelve a crear la copia (vacía) y deja las funciones como en el 6b + hotfix. Con la reversa vuelve el problema
del tope de 30 s: hay que llenarla a mano con `select redes.f_refrescar_contratos_capa();`.
