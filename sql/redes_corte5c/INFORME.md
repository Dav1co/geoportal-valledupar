# Técnica · Fase 1 · Corte 5c — La pantalla del Cargue de capas, «Devolver este campo a la capa» y la corrección de ubicaciones

**Propuesta. No se ha ejecutado en la base real** (solo en el PostGIS local de Homebrew, con la carga real de las redes y la primera carga MUE).
Parte de la rama `tecnica-corte5b` (sin publicar). Se publica **aparte, después** de 4a + 4b + 5a + 5b (§31.3 de la bitácora).

## Qué lleva
- **Cargue de capas** (pestaña nueva del Dashboard distribución; el supervisor de distribución la lee, carga el administrador):
  - las capas en 5 grupos con su estado (al día, desactualizada, sin cargar, sale de otra capa o viene de otro módulo), su versión, su última carga y su carga abierta;
  - cinco pasos: archivo → columna llave → sistema de coordenadas → revisar (nuevos, cambiados, retirados, choques con la ficha y vista previa en el mapa) → publicar con nota;
  - **lectores en el navegador, sin librerías nuevas**: SHP en zip (.shp, .dbf, .prj, .cpg), **GeoPackage (lector propio de SQLite)**, GeoJSON, KML o KMZ, y CSV o Excel con X y Y. El archivo no sale del equipo: al servidor van filas `{orden, wkt, atributos}` en lotes de 200 y menos de 450 KB;
  - **detección del sistema** desde el .prj, el `gpkg_spatial_ref_sys`, el «crs» del GeoJSON o el rango de X y Y (MAGNA Origen Nacional 9377, las zonas MAGNA 3114 a 3118, MAGNA geográficas 4686 y WGS 84); la persona la confirma y la pantalla avisa si no cuadra;
  - **carga masiva**: un GeoPackage o un zip con varios SHP se reparte por el nombre de cada capa (con alias); las que no coinciden se eligen a mano; todas llevan la misma marca (`masiva_id`) y se publican en orden (pozos y descargas antes que conductos);
  - historial de cada capa y **«Volver a la versión anterior»** (revertir, con motivo);
  - la **capa MUE** desde la pantalla, con su resumen punto por punto.
- **Cruce por geometría (D-4)**: una capa del lector genérico se puede cargar «sin columna llave». Cada elemento se cruza con lo vigente de la misma capa y el mismo tipo: puntos a 2 m o menos; líneas y polígonos con la distancia de Hausdorff (en metros, MAGNA Bogotá) por debajo de la misma tolerancia (parámetro `cruce_geometria_tol_m`). Uno a uno, por rondas (dos elementos en el mismo sitio se reparten). Lo que no cruza entra como nuevo.
- **Lector genérico** para las capas de un solo tipo: ACO (acometidas, ya lista) y 11 capas nuevas en `redes.capas` (captaciones, aducción, desarenadores, bombeo de agua potable, sumideros, interceptores, bombeo de aguas residuales, PTAR, sectores hidráulicos, sensores y SCADA). Reconoce NOMBRE, CLASE, MATERIAL, DIAMETRO, ESTADO, PROFUNDIDAD, CAPACIDAD y CODIGO_ANTERIOR sin importar mayúsculas; lo demás va a `atributos.modelo`.
- **EPSG 9377**: este PostGIS no lo trae en `spatial_ref_sys` (el local no lo tiene; en Supabase no se sabe). `f_geo_desde_wkt` lo reproyecta con su definición (Resolución IGAC 471 de 2020) cuando falta. La verificación 09 lo prueba en la base donde se aplique.
- **«Devolver este campo a la capa»** (§31.1): en la lista de choques del resumen, con motivo (solo el administrador). Desde ahí ese campo lo manda la capa, hasta que alguien lo vuelva a editar en la ficha. La ficha no cambia hasta publicar.
- **Puntos de muestreo (Dashboard PTAP › Puntos)**:
  - §32.1: **el administrador sí aprueba una ubicación que tomó él mismo**; el supervisor sigue sin poder;
  - §32.2: **«Corregir la ubicación»** de un punto verificado, con motivo obligatorio: tocando el mapa, con coordenadas o con el GPS del equipo (30 m o menos). La nueva se agrega como verificada, fuente `correccion`; la anterior queda en el historial. Lista de «Últimas correcciones».

## Objetos
- Tablas nuevas (solo inserción, RLS, sin permisos para la API): `redes.ficha_campo_devoluciones` y `tecnica.punto_ubicacion_correcciones`.
- `tecnica.puntos_ubicacion` (5a): su CHECK de `fuente` admite además `correccion`. Sigue siendo de solo inserción.
- 11 filas en `redes.capas` y el parámetro `cruce_geometria_tol_m` (2 m, de 0,1 a 50).
- Función interna nueva `redes.f_cruzar_por_geometria`.
- 6 RPC nuevas (solo `service_role`): `geoportal_redes_cargue_capas`, `_cargue_historial`, `_cargue_iniciar`, `_carga_muestra`, `_carga_devolver_campo` y `geoportal_tec_punto_ubicacion_corregir`. Los lotes, el resumen, publicar, anular y revertir siguen siendo las RPC del 1a.
- **8 reemplazos con su texto exacto en la reversa** (`pruebas_locales/generar.py`): `redes.f_geo_desde_wkt`, `f_candidatos`, `f_preparar_candidatos`, `f_resumen`, `f_fusionar_ficha`, `f_iniciar`, y las 2 RPC de planta del 5b `geoportal_tec_punto_ubicacion_revisar` y `geoportal_tec_punto_ubicaciones`.
- Edges: `geoportal-redes` con 10 rutas `cargue_*` (el lote acepta 512 KB; las demás rutas siguen con 32 KB) y `geoportal-tecnica` con `ubicacion_corregir`. `_shared/auth.ts` y `autorizar()` sin tocar.

## Huellas
- 5b (antes): `cbff4ee6e25826251d90496c833ac3de` → 5c (después): **`a5ce1ff8c5659de3b853e30f4d3025e6`**.

## Orden (después de 4a, 4b, 5a, la carga MUE y 5b, ya publicados)
1. `huellas_solo_lectura_redes_corte5c_editor.sql`: «CORTE 5b (listo para el 5c)», 6 RPC y 2 tablas «NO EXISTE», 8 «CORTE 5b (sin cambiar)». Cualquier «DISTINTA»: parar y avisar.
2. `ensayo_en_transaccion_redes_corte5c_editor.sql`: ERROR con «**68 de 68** … SIN FALLAS».
3. `migracion_redes_corte5c_editor.sql`.
4. `verificacion_redes_corte5c_editor.sql`: **9 OK** (y 2 INFO; la INFO 10 dice si el 9377 está en `spatial_ref_sys`). Desde aquí, las filas 03 y 05 de la verificación del 5b dicen MAL a propósito.
5. Huellas otra vez: «CORTE 5c (aplicado)», 6 «NUEVA», 8 «CORTE 5c (reemplazada)», 2 «EXISTE».
- Reversa: `reversa_redes_corte5c_editor.sql` (se niega si ya hay devoluciones, correcciones, cargas del lector genérico, sin llave o masivas).

## Pruebas
- Ensayo **68 de 68** (personas `prueba.redes9.*`, puntos MUE-97nn y activos en las capas nuevas, que nacen vacías en la misma transacción).
- Arnés local **22 de 22** (`resultados/sql_local.txt`): reversa exacta al 5b (funciones y CHECK), recarga real del acueducto con un tramo editado y su devolución, 8.753 pozos reales en EPSG 9377 a una capa sin llave (a menos de 1 cm) y su recarga en WGS 84 cruzada por geometría, 9.064 conductos sin llave dos veces (Hausdorff), la capa MUE desde la RPC de la pantalla.
- Lectores con archivos reales **16 de 16** (`scripts/prueba_lectores_c5c.mjs`).
- Edge simulada de las rutas nuevas **53 de 53**; regresiones de redes 189, aviso 21, dosis 51, fecha 42, inicio 23, puntos 35 y admin 6. Verificador de permisos: 0 errores, con 11 sondas nuevas.
- Chrome real a 390 px y 1280 px: **76 de 76** (regresiones de Chrome: 5b 54 de 54 y 4b 58 de 59, ver resultados): `scripts/prueba_chrome_cargue_c5c.mjs`, `resultados/chrome.txt`.
