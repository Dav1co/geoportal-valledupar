# Publicar «PDF de Reportar anomalía» (Code A, 27-nov-2026)

Se publica **después** de la etiqueta del último pago (`campo-etiqueta-pago`): la guardia exige la huella de campo `9f8b8ec55fc7e1c56fdf74a5f4e7f3c4`.

Ramas `campo-reporte-pdf`, sin push:
- **geoportal-emdupar** (`~/geoportal-emdupar-ranpdf`), sobre `campo-etiqueta-pago` (`4e67aa5`): `424205a` SQL · `7c557ec` pantalla, pruebas y SQL sin «→» · esta guía.
- **geoportal-web** (`~/geoportal-web-ranpdf`), sobre `00f9f45`: `a893d81`.

Huellas:
- Campo `9f8b8ec5…` → **`3c92536ff4f21b0f985c31fde0d94c9d`**.
- Acta `111506c6…` y Técnica `838b8098…` no cambian.

Sondas: geoportal-campo 50 → 51 (`ran_pdf`); geoportal-acta 16, sin cambio.

## Qué hace
- En Supervisión, el detalle de un reporte de «Reportar anomalía» tiene el botón **«Descargar PDF del reporte»**, junto a «Cambiar estado», «Ocultar» y «Vincular como duplicado».
- El PDF se arma la primera vez que se pide. Las siguientes veces se entrega el mismo. Si el reporte cambió (estado, historial, ocultar o reincluir, duplicado, acta, notas), sale una **versión nueva** con «versión N» en el PDF y `-vN` en el nombre. Las versiones anteriores se conservan.
- Nombre del archivo: `AAAAMMDDHHMMSS-RAN-NNNNNN[-vN].pdf`. La fecha y hora son las del registro del reporte, en hora de Bogotá. NNNNNN es el número interno del reporte.
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

## Orden (no cambiarlo)
### 0. Antes: la etiqueta del último pago publicada
Huellas de este paquete, fila 1: debe decir «LISTA PARA ESTE CAMBIO». Si dice «FALTA PUBLICAR la etiqueta del último pago», publique primero esa.

### 1. SQL (editor de Supabase), cada archivo con su md5
1. `huellas_solo_lectura_campo_reporte_pdf_editor.sql` (`49d60af1f22168234a2817d910924944`): fila 1 «LISTA PARA ESTE CAMBIO»; filas 2 y 3 «PUBLICADA».
2. `ensayo_en_transaccion_campo_reporte_pdf_editor.sql` (`9bf95f00800d14867129ac0d7429881b`).
   - Debe terminar en ERROR con «RESULTADO: 47 de 47 pruebas correctas — SIN FALLAS». No deja nada.
   - Crea y luego deshace 5 correos `ztran.*`, el contrato `991800000201` en cartera, 3 reportes de prueba (con sus objetos en `storage.objects`) y un cambio de estado.
   - El mapa se mide con las redes y los predios reales. La prueba 05.04 exige menos de 3 s.
   - Si da otro número, pare y mándeme el texto.
3. `migracion_campo_reporte_pdf_editor.sql` (`ce74e87e33b2416f8bd1a2a4d69f9323`).
   - La guardia exige, además, `redes_acueducto` y `redes_alcantarillado` como tablas con `geom` y sus índices GiST `idx_redes_acu_geom` e `idx_redes_alc_geom`.
   - También exige `predios_comercial` como vista materializada con `geom` y su índice GiST `idx_predcom_geom_n`, el SRID 3116 y el bucket privado `actas-pdf`.
   - Si se detiene por una capa o un índice, mándeme el texto: puede ser que el índice tenga otra definición en producción.
4. `verificacion_campo_reporte_pdf_editor.sql` (`a9069b06cf9a411fc7e2eab4c8365649`): 9 de 9 OK.
5. Huellas otra vez: fila 1 «CON ESTE CAMBIO» (`3c92536f…`); filas 2 y 3 «PUBLICADA».

Reversa, si hiciera falta: `reversa_campo_reporte_pdf_editor.sql` (`3660820011acb567d92c872d566f6c41`).
- Quita las 8 funciones.
- Nada se borra: `campo.reporte_pdf` (con sus filas) y los PDF del bucket se quedan.

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
- `pruebas_locales/correr_local.py`: 19 de 19. Cubre el ensayo (47 de 47), la verificación (9 de 9), la reversa con la tabla y sus filas conservadas, volver a aplicar, 3 guardias y 2 mutaciones (el contenido lee los datos sensibles; la autorización deja pasar al autor).
- `scripts/prueba_chrome_reporte_pdf.mjs`: 52 de 52, con la Edge real en Deno y Chrome real a 390 y 1.280 px, los 5 perfiles, el PDF revisado por dentro y rasterizado con pdftoppm.
  - En esa base local, `max_fotos` se subió a 6 para medir 6 fotos. En producción vale 2.
  - El formato de control se insertó sin disparadores; solo sirve para ver que no aparece el botón.
- Regresión: «Consultar direcciones» (Supervisión, «Reportar anomalía», formatos y Edge de actas) con la Edge y la app nuevas: 59 de 59.
- **Safari: pendiente.** safaridriver no abre la sesión, como le pasó al Code B. Pruébelo a mano: abra el PDF desde la revisión local en Safari y en el iPhone.

## Qué probar en el celular
1. Como supervisor, en Supervisión, abra un «Posible fraude» con fotos → «Descargar PDF del reporte» → «Abrir el PDF». Revise el mapa, las fotos, el historial y su nombre en «Reportó».
2. Cambie el estado y vuelva a pedirlo: debe salir «versión 2» y el archivo `-v2`. Pídalo otra vez sin cambiar nada: debe salir la misma versión.
3. Un formato (por ejemplo, una revisión previa) no muestra el botón.
4. Con un operario, el botón no aparece, porque no entra a Supervisión.
