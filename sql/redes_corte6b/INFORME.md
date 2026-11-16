# Técnica · fase 1 · Corte 6b — contratos con su tarjeta, compartir la vista, muestreo con color y la capa de reportes de Comercial

PROPUESTA. Nada de esto se ha ejecutado en Supabase. Probado en el PostGIS local con la carga real del 1a, la MUE, el 6a y 111.950 contratos SINTÉTICOS
(predio, cartera y ficha inventados; ningún dato real).

**Se publica junto con el 6a, después de él** (primero todo el SQL del 6a, luego el del 6b).

## Huellas
- Antes (6a): `91a4d3e6e1c3539d8a447cb00a52d735` · después (6b): `fca28bf695d1fcfa153f1113ce821528`.

## Orden para publicar (en el editor SQL, después del 6a)
1. `huellas_solo_lectura_redes_corte6b_editor.sql`: «CORTE 6a (listo para el 6b)», 4 RPC y 5 objetos «NO EXISTE», 2 «CORTE 6a (sin cambiar)». Si algo dice DISTINTA, parar y avisar.
2. `ensayo_en_transaccion_redes_corte6b_editor.sql`: ERROR con «**53 de 53** … SIN FALLAS». Crea contratos de prueba (99000000110x) en el catastro, la cartera y la ficha, y muestras MUE-95nn, como la suite viva de Análisis de contrato; el ERROR final lo deshace todo. Rehace la capa de contratos dentro de la transacción (unos segundos).
3. `migracion_redes_corte6b_editor.sql`.
4. `verificacion_redes_corte6b_editor.sql`: 9 OK (más 1 INFO; la capa dice «sin calcular todavía» hasta que un supervisor abra el geovisor).
5. Huellas otra vez: «CORTE 6b (aplicado)», 4 «NUEVA», 2 «CORTE 6b (reemplazada)», 5 «EXISTE».
6. Edge `geoportal-redes` (rama `tecnica-corte6b` de geoportal-web) y después el frontend (rama `tecnica-corte6b`).

## Qué lleva
- `redes.contratos_capa` (+ estado): un punto por contrato con uso, estado (activo, retirado, otro, sin dato), consumo promedio y años del medidor; **sin nombre, dirección, teléfono ni deuda**. Se rehace sola cuando cambia la ficha del contrato o tiene más de 24 h (al abrir el geovisor un supervisor; 2 s con 112 mil contratos).
- `geoportal_redes_contrato_tarjeta`: número, estado, uso, perfil de consumo de 6 meses, medidor, tramo, y **nombre, dirección y barrio** (dato personal, solo en pantalla); la lectura queda en `geoportal_auditoria` (`redes_contrato_tarjeta`, sin el nombre). Solo supervisores y administrador.
- `redes.vistas_compartidas` y `geoportal_redes_vista_compartir` / `_vista_abrir` (§30.2).
- `redes.muestreo_rangos` y `redes.f_muestreo_calidad`: color del muestreo por el último cloro y turbiedad (no excluidos) frente a la referencia del punto o, si no tiene, la de Salida (`cloro_libre_tanque`, `turbiedad_salida`).
- `redes.v_reportes_comercial`: vacía; el Corte 8 la reemplaza.
- Se reemplazan `geoportal_redes_geovisor` (deja de ser STABLE: puede rehacer la capa) y `geoportal_redes_geovisor_capa`.
- Lee sin tocar: `public.catastro_valledupar`, `public.cartera_suscripcion`, `bi_interno.ficha_contrato(_estado)`, `tecnica.v_registros_estado`, `tecnica.variables`, `tecnica.referencias` y `tecnica.f_referencia_vigente`.

## Pruebas
- Ensayo 53 de 53 (con y sin la carga real). Arnés local 21 de 21 (`resultados/sql_local.txt`).

## Reversa
`reversa_redes_corte6b_editor.sql`: deja las 2 funciones con su texto del 6a, quita lo nuevo y devuelve el catálogo como en el 6a. Se niega si ya hay vistas compartidas.
