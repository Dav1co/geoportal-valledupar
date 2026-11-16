# Técnica · fase 1 · Corte 7c — foto de la remisión y parámetros de químicos editables

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local con el 7a publicado. Todo es del esquema `tecnica`: **ninguna función de redes cambia**
(en producción la huella de redes es `4a46069f…` desde el 9a del Code B; este paquete no la revisa ni la toca: la fila 09 de la verificación solo la informa).

## Qué cambia en la base
- `tecnica.quimico_movimientos`: una columna nueva, `remision_foto` (nula en todo lo que ya existe; solo la llevan las entradas; una foto, una entrada).
- Tablas nuevas, de solo inserción: `tecnica.quimico_remision_preparaciones` (rutas reservadas) y `tecnica.quimico_parametro_eventos` (historial de cambios).
- ⚠ Se reemplazan 2 RPC del 7a, con guardia md5 y su texto en la reversa: `geoportal_tec_quimico_entrada` (acepta la foto, opcional) y `geoportal_tec_quimico_historial` (trae la ruta de la foto; la Edge la cambia por una URL firmada de 60 s).
- 3 RPC nuevas: `geoportal_tec_quimico_remision_preparar`, `geoportal_tec_quimico_parametros` y `geoportal_tec_quimico_parametro_fijar`. Un parámetro nuevo: `max_bytes_remision` (3 MB).
- Se editan desde la pantalla: el desvío de esperado contra usado, la marca (encendida o apagada) y los días atrás de uso y de entrada. Los tamaños de archivo, no.

## Orden para publicar (en el editor SQL)
1. `huellas_solo_lectura_tecnica_corte7c_editor.sql`: 2 «CORTE 7a (sin cambiar)», 5 funciones y 3 objetos «NO EXISTE». Si algo dice DISTINTA o FALTA, parar y avisar.
2. `ensayo_en_transaccion_tecnica_corte7c_editor.sql`: ERROR con «**31 de 31** … SIN FALLAS».
3. `migracion_tecnica_corte7c_editor.sql`.
4. `verificacion_tecnica_corte7c_editor.sql`: 8 OK y 2 INFO.
5. Huellas otra vez: 2 «CORTE 7c (reemplazada)», 5 «NUEVA» y 3 «EXISTE».
6. Edge `geoportal-tecnica` (rama `tecnica-corte7c` de geoportal-web) y después el frontend (rama `tecnica-corte7c`).
   El frontend de hoy funciona con el SQL nuevo (la foto es opcional); la Edge nueva necesita el SQL nuevo para las rutas de la foto y de los parámetros.

## Pruebas
- Ensayo 31 de 31. Arnés local 18 de 18 (`resultados/sql_local.txt`), con las RPC llamadas como la Edge (service_role, 30 s y 8 s) y la reversa exacta al 7a.
- Edge simulada del 7c: 25 de 25; regresiones de planta sin fallas.
- Chrome real a 390 px y 1280 px: 38 de 38 (`resultados/chrome.txt`); regresiones de químicos (7a 40, 7b 46) e inicio (74) sin fallas.

## Reversa
`reversa_tecnica_corte7c_editor.sql`: deja las 2 RPC como en el 7a y quita lo nuevo. **Se niega** si ya hay entradas con foto, fotos reservadas o cambios de parámetros.
