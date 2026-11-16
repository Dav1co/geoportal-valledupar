# Técnica · Fase 1 · Corte 5b — Minimapa de Muestreo y «Guardar la ubicación de este punto»

**Propuesta. No se ha ejecutado en la base real** (solo en el PostGIS local de Homebrew, con la carga real de las redes y la primera carga MUE de los 27 puntos).
Parte de la rama `tecnica-corte5a` (sin publicar). Se publica junto con 4a, 4b y 5a (§27 y §31 de la bitácora); el 5c va aparte, después.

## Qué lleva
- **Minimapa de Muestreo** (01 §I, adenda §2): en la tarjeta «Puntos de muestreo», un mapa con una sola capa, sin interruptores, **sincronizado con la lista**: tocar un punto lo elige en la lista y elegirlo en la lista lo resalta. La ubicación **aproximada** (centro del barrio) se dibuja hueca y con un halo; la **verificada**, llena; la que está **en revisión**, con borde morado. Leyenda debajo.
  - **No pide el GPS al abrir** (en Muestreo se registran resultados de laboratorio de hasta 7 días atrás, desde la oficina). «Ver dónde estoy» lo pide cuando la persona quiere y propone el punto más cercano (a menos de 300 m) sin cambiar lo elegido.
  - «Ocultar el mapa» lo quita; la lista sigue como siempre. Si la ruta no está desplegada, el mapa no aparece; si falta el SQL, avisa y la lista funciona igual.
- **«Guardar la ubicación de este punto»** (§4 de los hallazgos; pospuesto del 5a): para un punto con la ubicación aproximada o sin ubicación. Toma el GPS con su precisión en vivo y solo deja guardar con **30 m o menos** (parámetro `mue_gps_precision_max_m`, de 5 a 100). Pide confirmación con la distancia a la ubicación de ahora. **Queda pendiente**: nada cambia hasta que el supervisor la apruebe.
- **Dashboard PTAP · pestaña «Puntos»** (antes «Próximamente»): las ubicaciones por revisar (quién la tomó, cuándo, precisión, distancia y el aviso «Lejos» desde 300 m, parámetro `mue_gps_distancia_aviso_m`), con un minimapa de la de ahora y la propuesta. **Aprobar** (nota opcional) agrega la ubicación como **verificada, fuente `gps_operador`**, con el operador como autor; **rechazar** pide motivo. **Nadie revisa la que tomó** (como en Personal). Debajo, los 27 puntos con su ubicación y las últimas 50 revisiones.
- **Recarga de la capa MUE:** una ubicación **verificada** ya no la pisa un archivo que la trae **aproximada**: el resumen la marca `conserva_verificada` y se queda la vigente. Un archivo con la ubicación verificada sí la cambia (corrección explícita).

## Objetos
- Tablas nuevas (solo inserción, RLS, sin permisos para la API): `tecnica.punto_ubicacion_propuestas` y `tecnica.punto_ubicacion_revisiones` (una decisión por propuesta). Vista `tecnica.v_punto_propuestas` (pendiente, aprobada o rechazada).
- 4 RPC de planta nuevas (solo `service_role`): `geoportal_tec_puntos_mapa`, `geoportal_tec_punto_ubicacion_proponer`, `geoportal_tec_punto_ubicaciones` y `geoportal_tec_punto_ubicacion_revisar`. Usan las puertas vivas `tecnica.f_autorizar_captura(…, 'muestreo')` y `tecnica.f_autorizar_supervision`, que no se tocan.
- 2 parámetros nuevos en `redes.parametros` (los edita el administrador en Parámetros del Dashboard distribución).
- Se reemplaza 1 función interna del 5a: `redes.f_candidatos_muestreo` (texto del 5a con un cambio exacto, `pruebas_locales/generar.py`; reversa con el texto exacto).
- `tecnica.puntos` (viva): **no se toca**. `tecnica.puntos_ubicacion`: solo se le agregan filas al aprobar.
- Edge `geoportal-tecnica`: 4 rutas nuevas (`puntos_mapa`, `ubicacion_proponer`, `ubicaciones`, `ubicacion_revisar`). Las de siempre no cambian. `_shared/auth.ts` y `autorizar()` sin tocar.

## Huellas
- 5a (antes): `5d104bb916ca0b055659c1b14902f519` → 5b (después): **`cbff4ee6e25826251d90496c833ac3de`**.

## Orden (después de todo el 5a, incluida la primera carga MUE)
1. `huellas_solo_lectura_redes_corte5b_editor.sql`: «CORTE 5a (listo para el 5b)», las 4 RPC y las 2 tablas «NO EXISTE», `f_candidatos_muestreo` «CORTE 5a (sin cambiar)». Cualquier «DISTINTA»: parar y avisar.
2. `ensayo_en_transaccion_redes_corte5b_editor.sql`: ERROR con «**53 de 53** … SIN FALLAS».
3. `migracion_redes_corte5b_editor.sql`.
4. `verificacion_redes_corte5b_editor.sql`: **8 OK** (y 2 INFO). Desde aquí la fila 05 de la verificación del 5a dice MAL a propósito (cambió el conjunto de funciones).
5. Huellas otra vez: «CORTE 5b (aplicado)», 4 «NUEVA», «CORTE 5b (reemplazada)», 2 «EXISTE».
- Reversa: `reversa_redes_corte5b_editor.sql` (se niega si ya hay ubicaciones propuestas).

## Pruebas
- Ensayo **53 de 53** (personas `prueba.redes8.*` y puntos MUE-98nn propios; con la carga real y la MUE presentes).
- Arnés local **20 de 20** (`resultados/sql_local.txt`): reversa exacta al 5a, guardia, un operador real propone MUE-05 y un supervisor la aprueba, y una recarga MUE con el archivo de la primera carga conserva la verificada.
- Edge simulada `geoportal-tecnica` (rutas del 5b) **35 de 35** (`resultados/edge_simulada.txt`); regresión de las simuladas de planta (aviso 21, dosis 51, fecha 42, inicio 23), de redes 189 y de admin 6. Verificador de permisos: 0 errores, con 4 sondas nuevas.
- Chrome real a 390 px y 1280 px: **54 de 54** (`scripts/prueba_chrome_mue_c5b.mjs`, `resultados/chrome.txt`).
- Regresiones de Chrome: `resultados/regresiones.txt`.
