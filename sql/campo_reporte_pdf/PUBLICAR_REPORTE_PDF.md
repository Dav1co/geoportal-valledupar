# Publicar «PDF de Reportar anomalía» (Code A, 27-nov-2026)

Se publica **después** de la etiqueta del último pago (`campo-etiqueta-pago`): la guardia exige la huella de campo `9f8b8ec55fc7e1c56fdf74a5f4e7f3c4`.

Ramas `campo-reporte-pdf`, sin push:
- **geoportal-emdupar** (`~/geoportal-emdupar-ranpdf`), sobre `campo-etiqueta-pago` (`4e67aa5`): `424205a` SQL · `7c557ec` pantalla, pruebas y SQL sin «→» · `1025a19` guía · ajustes del 27-nov (número RAN seguido, PDF del formato en Supervisión) y esta guía al día.
- **geoportal-web** (`~/geoportal-web-ranpdf`), sobre `00f9f45`: `a893d81` y el ajuste del número interno en letra pequeña.

Huellas:
- Campo `9f8b8ec5…` → **`68942f699d39f30bacf4f231be57e131`** (con el contador del RAN; reemplaza a `3c92536f…`).
- Acta `111506c6…` y Técnica `838b8098…` no cambian.

Sondas: geoportal-campo 50 → 51 (`ran_pdf`); geoportal-acta 16, sin cambio.

## Qué hace
- En Supervisión, el detalle de un reporte de «Reportar anomalía» tiene el botón **«Descargar PDF del reporte»**, junto a «Cambiar estado», «Ocultar» y «Vincular como duplicado».
- El PDF se arma la primera vez que se pide. Las siguientes veces se entrega el mismo. Si el reporte cambió (estado, historial, ocultar o reincluir, duplicado, acta, notas), sale una **versión nueva** con «versión N» en el PDF y `-vN` en el nombre. Las versiones anteriores se conservan.
- Nombre del archivo: `AAAAMMDDHHMMSS-RAN-NNNNNN[-vN].pdf`. La fecha y hora son las del registro del reporte, en hora de Bogotá.
- **Número RAN seguido** (David, 27-nov), en la tabla nueva `campo.reporte_ran`, de solo inserción:
  - Al migrar se numeran todos los reportes de «Reportar anomalía» que ya existen, en orden de fecha de registro: RAN-000001, 000002…
  - Los nuevos reciben su número la primera vez que se pide su PDF, junto con cualquier reporte anterior que aún no lo tenga. Así el orden sigue siendo el de registro, no el de los pedidos.
  - No hay huecos y un número no cambia.
  - El número interno del reporte va aparte, en letra pequeña bajo el número RAN, para ubicarlo en el Geoportal.
- Solo pueden pedirlo la supervisión de Comercial y el administrador. El operario (aunque sea el autor), el dual sin supervisión y quien no tiene permisos reciben 403. Los formatos se rechazan porque tienen su propio PDF.
- Contenido del PDF:
  - grupo, tipo, subtipo y estado;
  - contrato, dirección base comercial y de catastro, y la dirección, el barrio y la referencia encontrados en terreno;
  - coordenadas, precisión, XY digitado o «sin ubicación del dispositivo»;
  - **mapa vectorial** de 400 × 200 m con acueducto, alcantarillado, predios, el punto, la precisión, la escala y el norte;
  - descripción;
  - quién reportó (su **nombre**; el correo solo si no tiene nombre), inicio, fin y duración;
  - fotos con su origen;
  - historial;
  - sello y pie «Generado desde el Geoportal EMDUPAR el … por …».
- Fuera del PDF: datos sensibles, rutas y firmas.
- Fotos: van tal como se comprimieron al subir. Las que no caben en el tope de 1,75 MB salen como recuadro con «Foto omitida por tamaño; disponible en el Geoportal», y el PDF queda en menos de 2 MB.
- Cada descarga y cada generación quedan auditadas: `campo_ran_pdf_generar` y `campo_ran_pdf_descargar`.
- **Formatos en Supervisión** (solo pantalla): el detalle de un formato con PDF (revisiones, instalaciones, SCRR) muestra lo mismo que «Formatos de campo → Actas registradas»:
  - la marca «PDF listo» o «PDF pendiente»;
  - con PDF, «Descargar el PDF»; sin PDF, «Generar el PDF».
  - Usa el mismo componente y las mismas llamadas (`actas_registradas`, `pdf_url`, `pdf_generar`), con el mismo permiso y la misma auditoría. Sin RPC nueva.

## Orden (no cambiarlo)
### 0. Antes: la etiqueta del último pago publicada
Huellas de este paquete, fila 1: debe decir «LISTA PARA ESTE CAMBIO». Si dice «FALTA PUBLICAR la etiqueta del último pago», publique primero esa.

### 1. SQL (editor de Supabase), cada archivo con su md5
1. `huellas_solo_lectura_campo_reporte_pdf_editor.sql` (`1bda562c5edd9cecef9b66da832f44ba`): fila 1 «LISTA PARA ESTE CAMBIO»; filas 2 y 3 «PUBLICADA».
2. `ensayo_en_transaccion_campo_reporte_pdf_editor.sql` (`6b4ae425c7815bf85aaa3b6185a2b196`).
   - Debe terminar en ERROR con «RESULTADO: 54 de 54 pruebas correctas — SIN FALLAS». No deja nada.
   - Crea y luego deshace 5 correos `ztran.*`, el contrato `991800000201` en cartera, 6 reportes de prueba (con sus objetos en `storage.objects`), los números RAN y un cambio de estado.
   - El mapa se mide con las redes y los predios reales. La prueba 05.04 exige menos de 3 s.
   - Si da otro número, pare y mándeme el texto.
3. `migracion_campo_reporte_pdf_editor.sql` (`9ba9df5dcbbd747a5c2a2859938aaf93`).
   - Al final numera los reportes existentes (`select campo.f_ran_numerar(null)`): el resultado de esa línea sale vacío y es lo esperado.
   - La guardia exige, además, `redes_acueducto` y `redes_alcantarillado` como tablas con `geom` y sus índices GiST `idx_redes_acu_geom` e `idx_redes_alc_geom`.
   - También exige `predios_comercial` como vista materializada con `geom` y su índice GiST `idx_predcom_geom_n`, el SRID 3116 y el bucket privado `actas-pdf`.
   - Si se detiene por una capa o un índice, mándeme el texto: puede ser que el índice tenga otra definición en producción.
4. `verificacion_campo_reporte_pdf_editor.sql` (`dcf38653e3d3e8d69b7219bfb88f7691`): 10 de 10 OK. La fila 10 comprueba que los números van seguidos desde 1.
5. Huellas otra vez: fila 1 «CON ESTE CAMBIO» (`68942f69…`); filas 2 y 3 «PUBLICADA».

Reversa, si hiciera falta: `reversa_campo_reporte_pdf_editor.sql` (`8b3ebf7a835ce768bbd91f41eaba8f80`).
- Quita las 9 funciones.
- Nada se borra: `campo.reporte_pdf` y `campo.reporte_ran` (con sus filas) y los PDF del bucket se quedan.
- Si se vuelve a aplicar, la numeración sigue desde el último número.

### 2. Edge (después del SQL)
- Desde `~/geoportal-web-ranpdf`, desplegar **geoportal-campo**.
- Cambia `_shared/pdf_registro.ts`, pero el cambio solo agrega: el PDF de un formato sale idéntico byte a byte. **geoportal-acta no necesita desplegarse.**
- Después:
  1. `python3 -I ~/geoportal-consultas/campo/paquete_reporte_pdf/edge/fundir_sondas_reporte_pdf.py` (respaldo `PERMISOS_EDGE.json.bak_antes_reporte_pdf`; 50 → 51).
  2. `verificar_edge.py --vivo` y las sondas.

### 3. Frontend (después de la Edge)
- Hacer merge de `campo-reporte-pdf` en main, `npm run build` y desplegar.
- Con la Edge anterior, el botón responde «Acción no soportada» y no se rompe nada más.

## Pruebas locales (clúster 55432, sin Supabase)
- **Doble con PostGIS real:** el volcado del doble 4a sin su PostGIS de juguete, más la cadena publicada (Investigación, registro flexible, consultar direcciones, etiqueta del pago), más las capas con el volumen real: 10.578 tramos de acueducto, 9.064 de alcantarillado y 111.651 predios, tomados de `emdupar_b` en solo lectura.
- `pruebas_locales/correr_local.py`: 20 de 20. Cubre el ensayo (54 de 54), la verificación (10 de 10), la reversa con las tablas y sus filas conservadas, volver a aplicar, 3 guardias y 3 mutaciones (el contenido lee los datos sensibles; la autorización deja pasar al autor; el número RAN en orden de pedidos).
- `scripts/prueba_chrome_reporte_pdf.mjs`: 67 de 67, con la Edge real en Deno y Chrome real a 390 y 1.280 px, los 5 perfiles, el PDF revisado por dentro y rasterizado con pdftoppm.
  - Incluye el PDF del formato en Supervisión (pendiente, «Generar el PDF», «PDF listo», «Descargar el PDF»), con las mismas RPC y la misma auditoría que «Actas registradas».
  - Incluye «Actas registradas» antes y después, porque su marca y su botón ahora son componentes compartidos.
  - En esa base local, `max_fotos` se subió a 6 solo para medir el tamaño con 6 fotos. **Este paquete no toca `max_fotos`**: su cambio a 4 va aparte.
  - El formato de control se registra de verdad: reserva, firma del operario y registro.
- Regresión: «Consultar direcciones» (Supervisión, «Reportar anomalía», formatos y Edge de actas) con la Edge y la app nuevas: 59 de 59.
- **Safari: pendiente.** safaridriver no abre la sesión, como le pasó al Code B. Pruébelo a mano: abra el PDF desde la revisión local en Safari y en el iPhone.

## Qué probar en el celular
1. Como supervisor, en Supervisión, abra un «Posible fraude» con fotos → «Descargar PDF del reporte» → «Abrir el PDF». Revise el mapa, las fotos, el historial y su nombre en «Reportó».
2. Cambie el estado y vuelva a pedirlo: debe salir «versión 2» y el archivo `-v2`. Pídalo otra vez sin cambiar nada: debe salir la misma versión.
3. En un formato (por ejemplo, una revisión previa) no sale «Descargar PDF del reporte». Sale «PDF listo» con «Descargar el PDF» (o «PDF pendiente» con «Generar el PDF»), igual que en «Actas registradas».
5. Revise que el PDF diga RAN-000001… en orden de registro, y el número interno abajo, en letra pequeña.
4. Con un operario, el botón no aparece, porque no entra a Supervisión.
