# Técnica · Fase 1 · Corte 4b — Dashboard distribución (gestión)

**Propuesta. No se ha ejecutado en la base real** (solo en el PostGIS local de Homebrew, con la carga real de las redes).
Parte de la rama `tecnica-corte4a` (sin publicar). Se publica junto con el 4a y el 5 (§27): primero todo el SQL del 4a, luego este, luego el del 5.

## Qué lleva
- **Personal** (D-18, N-13, §27.3): tabla nueva `tecnica.personal_ficha_eventos` (solo inserción) con el **área** (planta, distribución o las dos), el **cargo**, la **cuadrilla** y la **casilla del geovisor** del operador de distribución (solo lectura; la usará el Corte 6). La ponen el supervisor de distribución o el administrador, siempre con motivo; nadie cambia su propia ficha. Administración la **muestra sin editarla**.
- **Catálogo** (N-12): lo lee el supervisor; el **nombre visible (alias)** de cada tipo y las **cuadrillas** (tabla nueva `redes.cuadrillas`, no se borran: se desactivan) los cambia solo el administrador. El alias usa la RPC del 1a (`geoportal_redes_alias_fijar`).
- **Parámetros**: el supervisor los lee; el administrador los cambia con motivo (antes y después en `redes.parametro_eventos` y en la auditoría). La caja de Valledupar no se cambia desde la pantalla, los parámetros que se cuentan van enteros, las fotos mínimas no bajan de 1 (§25.8) y los pares mínimo–máximo no se cruzan.
- **Gráficas** (D-19): intervenciones por mes, tipo y sistema; valor por fuente; daños por clase y causa con los tiempos medios; los 10 activos con más correctivos. Sin ocultos ni anuladas.
- **Descargas en Excel**: intervenciones o daños por rango (hasta un año, tope de 20.000 filas), cada descarga auditada (quién, conjunto, rango, filas e IP). Sin el nombre ni la placa del tercero, ni textos libres (descripción, compañeros). Con el nombre visible del tipo y su prefijo.
- **Nodos por clasificar** (N-3; solo el administrador): los 783 nodos S, J, M, Pila y Módulos; nombre visible o **«Crear el activo»** en la posición del nodo (queda enlazado con `nodo_eventos`; el nombre del modelo queda como código anterior).
- Funciones internas para el Corte 6: `redes.f_geovisor_lectura(email)` y `redes.f_area(email)`.

**No toca nada vivo:** ninguna función existente se reemplaza (solo se agregan 12 RPC, 4 funciones internas, 1 vista y 2 tablas). Las 4 funciones de permisos quedan con su huella del 4a.

## Huellas
- 4a (antes): `1a2be013019c9a59f1c1e0f2241661f0` → 4b (después): **`55668dddf263065b5eb90aeb3001a3b7`**.

## Orden en el editor SQL (después de todo el 4a)
1. `huellas_solo_lectura_redes_corte4b_editor.sql`: «CORTE 4a (listo para el 4b)», las 4 de permisos «CORTE 4a (sin cambiar)», 12 RPC y 2 tablas «NO EXISTE». Cualquier «DISTINTA»: parar y avisar.
2. `ensayo_en_transaccion_redes_corte4b_editor.sql`: termina en ERROR con «**95 de 95** … SIN FALLAS».
3. `migracion_redes_corte4b_editor.sql`.
4. `verificacion_redes_corte4b_editor.sql`: **9 OK** (y 5 INFO). Desde aquí la fila 06 de la verificación del 4a dice MAL a propósito.
5. Huellas otra vez: «CORTE 4b (aplicado)», 12 «NUEVA» y 2 «EXISTE».
- Reversa: `reversa_redes_corte4b_editor.sql` (se niega si ya hay fichas del personal o cuadrillas).

## Pruebas
- Ensayo **95 de 95** (sin datos reales; red propia ZT6 con nodos J-996 y S-996).
- Arnés local **21 de 21** con la carga real (`resultados/sql_local.txt`): reversa exacta al 4a; Personal en 0,03 s; nodos por clasificar 783 en 0,52 s; crear el activo de un nodo J real; gráficas 0,03 s; descarga sin la placa del tercero.
- Edge simulada `geoportal-redes` **184 de 184** (148 + 36 del 4b); `geoportal-admin` 6 de 6 (sin cambios). Verificador de permisos: 0 errores.
- Chrome real a 390 px y escritorio: **59 de 59** (`scripts/prueba_chrome_gestion_c4b.mjs`, `resultados/chrome.txt`), con el Excel descargado de verdad y abierto.
- Regresiones: `resultados/regresiones.txt`.
