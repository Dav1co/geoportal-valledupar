# Técnica · fase 1 · Corte 8 — reportes compartidos con Comercial («Reportar anomalía» y «Revisiones generales» desde Técnica)

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en un PostgreSQL local con los paquetes de campo de Comercial hasta la pasada del 14-nov
(sus 21 huellas vivas comprobadas al armar la base), el Corte 1 real de Técnica de planta y el doble de la vista del 6b.

**Regla del corte (David, 16-nov):** el formulario, las tablas y la Edge son los mismos de Comercial. No se crea ninguna tabla ni otra Edge. No se modifica ni se
borra ningún registro existente de las tablas de campo: solo se agrega.

## Qué cambia en la base
- `campo.reportes`: **una columna nueva, `area`** (nula = Comercial; `tecnica` = hecho desde Técnica). Agregarla no reescribe ni cambia ninguna fila.
- ⚠ `campo.f_autorizar_reporte` (viva): **una condición más** (la marca de transacción que ponen las RPC de Técnica). Sin la marca se comporta igual.
- ⚠ `tecnica.formulario_clave` (dominio) y `tecnica.f_formularios` (viva): dos claves más, `anomalia_compartida` y `revision_compartida`.
- 3 funciones internas (`campo.f_tipo_general`, `f_tecnica_claves`, `f_tecnica_entrar`) y 3 RPC nuevas (`geoportal_campo_tec_formulario`, `_preparar_subida`, `_crear_reporte`)
  que autorizan por el formulario de Técnica y llaman a la RPC de campo de siempre en la misma transacción.
- `campo.tipos_reporte`: se agregan «Fuga en acometida» y «Caja de medidor dañada» al grupo `red_acueducto`, **solo si no existe ya uno con ese nombre**. Los 26 actuales no se tocan.
- `redes.v_reportes_comercial` (vista del 6b, vacía): se reemplaza con las mismas columnas. **Ninguna función de redes cambia** (la huella de redes sigue en `79f184a4…`).

## Orden para publicar (en el editor SQL)
1. `huellas_solo_lectura_tecnica_corte8_editor.sql`: 2 «VIVA (sin cambiar)», 3 «FIRMA ESPERADA», 6 «NO EXISTE», columna «NO EXISTE», «7 CLAVES», vista «VACÍA (6b)».
   **Si algo dice DISTINTA o FALTA, parar y avisar** (las huellas de `campo.f_autorizar_reporte` y `tecnica.f_formularios` salen de los paquetes locales; no se han
   comprobado contra la base viva). Las filas «7 …» muestran los tipos parecidos a los dos que se agregan: si ya existe uno equivalente con otro nombre, avisar antes de migrar.
2. `ensayo_en_transaccion_tecnica_corte8_editor.sql`: ERROR con «**35 de 35** … SIN FALLAS».
3. `migracion_tecnica_corte8_editor.sql`.
4. `verificacion_tecnica_corte8_editor.sql`: 9 OK y 2 INFO.
5. Huellas otra vez: 2 «CORTE 8 (reemplazada)», 6 «NUEVA», «EXISTE», «9 CLAVES», vista «CORTE 8».
6. Edge `geoportal-campo` (rama `tecnica-corte8` de geoportal-web) y después el frontend (rama `tecnica-corte8`).
   El SQL solo no cambia nada para nadie; la Edge vieja y el frontend viejo siguen funcionando igual.

## Pruebas
- Ensayo 35 de 35. Arnés local 19 de 19 (`resultados/sql_local.txt`), con las RPC llamadas como la Edge (service_role, 30 s y 8 s) y la reversa exacta.
- Edge simulada del Corte 8: 24 de 24; regresiones de la Edge de campo sin fallas.
- Chrome real a 390 px y 1280 px: 36 de 36 (`resultados/chrome.txt`); regresiones de Comercial y de Técnica sin fallas (ver `ENTRADA_BITACORA.md`).

## Reversa
`reversa_tecnica_corte8_editor.sql`: deja las 2 funciones, el dominio y la vista como estaban y quita lo nuevo. Los 2 tipos agregados no se borran: se desactivan.
**Se niega** si ya hay reportes hechos desde Técnica o personas con un formulario compartido asignado.

## Para armar la base local otra vez
`sh pruebas_locales/rehacer_base.sh` (necesita un clúster local propio en `localhost:55434` y el Python de Anaconda, que trae psycopg). `pgserver.py` de esa carpeta
sustituye al paquete `pgserver` de los arneses de campo: crea la base en ese clúster en vez de bajar un PostgreSQL.
