# Técnica · Fase 1 · Corte 5a — Respuestas de la §28, «gana la ficha» en la recarga y la capa MUE

**Propuesta. No se ha ejecutado en la base real** (solo en el PostGIS local de Homebrew, con la carga real de las redes y los 27 puntos de muestreo).
Parte de la rama `tecnica-corte4b` (sin publicar). El Corte 5 se partió en **5a** (este: motor y reglas) y **5c** (la pantalla del Cargue de capas).

## Qué lleva
- **§28.1:** el supervisor y el administrador ya no registran «sin tope»: 72 h por intervención (como el operador) y hasta **30 días** atrás (parámetro nuevo `itv_dias_atras_max_supervisor`). El operador sigue con 7 días.
- **§28.2:** RPC nueva `geoportal_redes_personal_formulario`: el supervisor de distribución asigna o quita los **formularios de distribución** (tabla nueva `redes.formularios_distribucion`: hoy «Reportar daño o falla» y «Registrar intervención») desde Personal. Escribe el evento en `tecnica.personal_tecnico_eventos` (la tabla viva de siempre; no se altera) y la señal en `tecnica.senal_cambio`, igual que las RPC de planta, que no se tocan.
- **§28.3 y §28.4:** sin cambios de código (la descripción ya estaba fuera de las descargas; TOR queda sin alias).
- **§28.5:** las cuadrillas también las crea y cambia el supervisor de distribución.
- **§26.3 y pendientes 17c:** en una recarga **gana lo editado en la ficha**. Los campos que se editaron alguna vez en la ficha conservan su valor; los demás los cambia la capa. La fecha de instalación y el barrio, que ninguna capa trae, se conservan siempre (antes una recarga los dejaba vacíos). El origen corregido en la ficha no lo pisa la capa. Los **choques** (la capa trae otro valor en un campo de la ficha) salen en el resumen, como aviso y en la tabla para psql, sin bloquear.
- **17f:** los nodos clasificados en la bandeja conservan su activo en la recarga, aunque el nodo cambie de nombre o de posición.
- **Capa MUE** (01 sección E): `tecnica.puntos_ubicacion` y `tecnica.punto_eventos` (solo inserción), la capa `muestreo` y su resumen, publicar y revertir. En `tecnica.puntos` (viva) **solo agrega** filas y cambia `activo` con un evento; nunca borra.
- **Primera carga MUE** (`carga_mue/`): los 27 puntos de la §4 de hallazgos, 3 verificados por David y 24 al centro de su barrio, con el cruce punto → barrio escrito uno por uno en `carga_mue.py` y la lista para revisar en `generado/puntos_mue.csv`.

Se reemplazan 9 funciones: 4 del motor del 1a (vivas: `f_preparar_candidatos`, `f_resumen`, `f_publicar`, `f_revertir`) y 5 RPC de los Cortes 4a y 4b. Todas con su texto vivo y cambios exactos (`pruebas_locales/generar.py`), guardia por la huella del conjunto y reversa con el texto exacto del 4b.

## Huellas
- 4b (antes): `55668dddf263065b5eb90aeb3001a3b7` → 5a (después): **`5d104bb916ca0b055659c1b14902f519`**.

## Orden (después de todo el 4b)
1. `huellas_solo_lectura_redes_corte5a_editor.sql`: «CORTE 4b (listo para el 5a)», 4 de permisos «CORTE 4a (sin cambiar)», la RPC y 3 tablas «NO EXISTE», 9 «CORTE 4b (sin cambiar)». Cualquier «DISTINTA»: parar y avisar.
2. `ensayo_en_transaccion_redes_corte5a_editor.sql`: ERROR con «**55 de 55** … SIN FALLAS».
3. `migracion_redes_corte5a_editor.sql`.
4. `verificacion_redes_corte5a_editor.sql`: **9 OK** (y 3 INFO). Desde aquí la fila 05 de la verificación del 4b dice MAL a propósito.
5. Huellas otra vez: «CORTE 5a (aplicado)».
6. **Primera carga MUE**, por psql (como la carga inicial): `carga_mue/generado/carga_mue_todo.sql` (no publica; revisar el resumen punto por punto) y luego `carga_mue/generado/publicar_mue.sql`.
- Reversa: `reversa_redes_corte5a_editor.sql` (se niega si ya hay cargas MUE, ubicaciones o eventos de puntos).

## Pruebas
- Ensayo **55 de 55** (sin datos reales; red ZT7 y puntos MUE-99nn propios; con la carga real presente).
- Arnés local **21 de 21** con la carga real (`resultados/sql_local.txt`): reversa exacta al 4b; la primera carga MUE real con su maestro de psql (27 ubicaciones: 3 verificadas y 24 aproximadas); una **recarga completa del acueducto real** (10.578 tramos) con una ficha editada y un nodo de la bandeja: resumen 2,6 s, publicar 5,2 s, 0 cambiados, 0 retirados, la ficha intacta.
- Edge simulada `geoportal-redes` **189 de 189**. Verificador de permisos: 0 errores.
- Chrome real a 390 px y escritorio: **22 de 22** (`scripts/prueba_chrome_c5a.mjs`).
- Regresiones: `resultados/regresiones.txt`.
