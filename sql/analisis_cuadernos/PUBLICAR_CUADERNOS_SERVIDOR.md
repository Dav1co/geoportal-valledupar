# Publicar «Cuadernos de análisis» · paso 1 (solo servidor)

Rama `analisis-cuadernos-servidor` en los dos repos (app desde `bbf1dfd`, Edges desde `25dbd2b`). Sin pantallas: nada cambia para los usuarios hasta que se publiquen (después del Corte 1 de Code A).

No depende del Corte 1 de Code A ni lo toca. No cambia las huellas de redes (`1ba192724c2fddcf321104700829f3cc`) ni de técnica (`838b80984e51cc7873a666f85d657195`): si alguna cambió antes de publicar, la guardia se niega y hay que regenerar el paquete con la huella nueva.

## Orden

1. **Bucket (panel de Supabase, David).** Crear `analisis-capturas`: privado, tope de 600 KB (`614400` bytes), tipos permitidos solo `image/jpeg`. Sin políticas. La guardia de la migración exige esos tres valores exactos.
2. **Huellas antes** (editor SQL): `huellas_solo_lectura_analisis_cuadernos_editor.sql`. Deben salir los valores de «esperado_antes».
3. **Ensayo** (editor SQL): `ensayo_en_transaccion_analisis_cuadernos_editor.sql`. Debe terminar en `ERROR: PRUEBAS DE ANÁLISIS · CUADERNOS … RESULTADO: 279 de 279 pruebas correctas — SIN FALLAS`. No deja nada.
4. **Migración** (editor SQL): `migracion_analisis_cuadernos_editor.sql`. Es liviana: crea 11 tablas vacías (21 filas de catálogo y 8 de topes) y 28 funciones. No recorre tablas grandes.
5. **Verificación** (editor SQL): `verificacion_analisis_cuadernos_editor.sql`. Las 12 filas en «OK».
6. **Edge**: desplegar `geoportal-analisis` (nueva; `verify_jwt` activado como las demás). No se redespliega ninguna otra.
7. **Manifiesto**: en `~/geoportal-consultas/tecnica/herramientas/PERMISOS_EDGE.json`, pasar `geoportal-analisis` de `planeada_cuadernos` a `implementado` y correr las 13 sondas.

## Si algo sale mal

`reversa_analisis_cuadernos_editor.sql`: quita las 12 RPC. Si todavía no hay cuadernos, quita también las tablas y el esquema (queda como antes). Si ya hay datos, conserva las tablas y sus filas. El bucket no se toca.

## Comprobación a mano después de publicar (sin pantallas)

Con el token de un supervisor de Técnica: `GET /functions/v1/geoportal-analisis?accion=perfil` → 200 con 21 íconos en `catalogo`. Con el de un operador → 403.

## md5 de los archivos `_editor`

- `huellas_solo_lectura_analisis_cuadernos_editor.sql` · `35865cfb753524ebb99edd1738664af9` (cambió el 26-nov tras publicar: huella de análisis con `collate "C"`)
- `ensayo_en_transaccion_analisis_cuadernos_editor.sql` · `ab9c32415fa3fdc304422512a0f78820` (cambió el 26-nov; el anterior, `9837a47d…`, ya no se usa)
- `migracion_analisis_cuadernos_editor.sql` · `24b679e0254d7088225e12178b31de7c`
- `verificacion_analisis_cuadernos_editor.sql` · `6d6c526eb99f154d85af79b65e268f9c` (cambió el 26-nov tras publicar: huella de análisis con `collate "C"`)
- `reversa_analisis_cuadernos_editor.sql` · `cb2c28e4f4997e0d5c49a6dfb924528f`

Corrección del 26-nov: el primer ensayo falló en producción sin dejar nada (`42702`, `zona` ambigua: `catastro_valledupar` tiene una columna `zona` y una variable del ensayo se llamaba igual). Solo cambió el archivo del ensayo: las variables son ahora `v_zona_geojson` y `v_zona2_geojson`, y las lecturas del catastro van con alias (`c.geom`, `c.cod_usuario`). La migración, la verificación, la reversa y las huellas son las mismas (mismos md5). El doble local del catastro lleva ahora las 72 columnas reales, y `generar.py` se niega si alguna variable o parámetro del paquete se llama como una columna real de `catastro_valledupar`, `redes.v_activo_vigente`, `storage.buckets` o `storage.objects`.

Publicado el 26-nov 21:40 (ensayo 279/279, migración sin error, Edge v1). La verificación dio 11 de 12: la fila 3 (huella de análisis) ordenaba las firmas con la collation de la base, que en producción no es la del clúster local (`C`); las 28 funciones coincidían una por una (fila 4). Corregido: la huella de análisis se ordena con `collate "C"` en `huellas_solo_lectura` y en `verificacion` (únicos archivos que cambian; solo lectura). Con eso la fila 3 debe dar `c8a803aa…` también en producción. Las fórmulas de redes y de técnica son las de sus paquetes y no se tocan: ordenan por `proname` (tipo `name`, siempre `C`); el desempate de técnica por firma solo pesa si hay funciones sobrecargadas.

Huella de análisis después de migrar: `c8a803aae851e77c9cdf010535dec090` (28 funciones: 12 RPC y 16 internas).
