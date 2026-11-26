# Publicar «Cuadernos de análisis» · paso 1 (solo servidor)

Rama `analisis-cuadernos-servidor` en los dos repos (app desde `bbf1dfd`, Edges desde `25dbd2b`). Sin pantallas: nada cambia para los usuarios hasta que se publiquen (después del Corte 1 de Code A).

No depende del Corte 1 de Code A ni lo toca. No cambia las huellas de redes (`1ba192724c2fddcf321104700829f3cc`) ni de técnica (`838b80984e51cc7873a666f85d657195`): si alguna cambió antes de publicar, la guardia se niega y hay que regenerar el paquete con la huella nueva.

## Orden

1. **Bucket (panel de Supabase, David).** Crear `analisis-capturas`: privado, tope de 600 KB (`614400` bytes), tipos permitidos solo `image/jpeg`. Sin políticas. La guardia de la migración exige esos tres valores exactos.
2. **Huellas antes** (editor SQL): `huellas_solo_lectura_analisis_cuadernos_editor.sql`. Deben salir los valores de «esperado_antes».
3. **Ensayo** (editor SQL): `ensayo_en_transaccion_analisis_cuadernos_editor.sql`. Debe terminar en `ERROR: PRUEBAS DE ANÁLISIS · CUADERNOS … RESULTADO: 256 de 256 pruebas correctas — SIN FALLAS`. No deja nada.
4. **Migración** (editor SQL): `migracion_analisis_cuadernos_editor.sql`. Es liviana: crea 10 tablas vacías (21 filas de catálogo y 8 de topes) y 27 funciones. No recorre tablas grandes.
5. **Verificación** (editor SQL): `verificacion_analisis_cuadernos_editor.sql`. Las 12 filas en «OK».
6. **Edge**: desplegar `geoportal-analisis` (nueva; `verify_jwt` activado como las demás). No se redespliega ninguna otra.
7. **Manifiesto**: en `~/geoportal-consultas/tecnica/herramientas/PERMISOS_EDGE.json`, pasar `geoportal-analisis` de `planeada_cuadernos` a `implementado` y correr las 12 sondas.

## Si algo sale mal

`reversa_analisis_cuadernos_editor.sql`: quita las 11 RPC. Si todavía no hay cuadernos, quita también las tablas y el esquema (queda como antes). Si ya hay datos, conserva las tablas y sus filas. El bucket no se toca.

## Comprobación a mano después de publicar (sin pantallas)

Con el token de un supervisor de Técnica: `GET /functions/v1/geoportal-analisis?accion=perfil` → 200 con 21 íconos en `catalogo`. Con el de un operador → 403.

## md5 de los archivos `_editor`

- `huellas_solo_lectura_analisis_cuadernos_editor.sql` · `bca984d18bd1484fc6c1228c3c3ae807`
- `ensayo_en_transaccion_analisis_cuadernos_editor.sql` · `aa73d5635d4b1ede9ed7aa0f87c21360`
- `migracion_analisis_cuadernos_editor.sql` · `42b966ac27ad02dabacb634633cfca1e`
- `verificacion_analisis_cuadernos_editor.sql` · `885ee40d766c554397f326ed6733b498`
- `reversa_analisis_cuadernos_editor.sql` · `dbab0aae40037337612f52db271cbb2a`
