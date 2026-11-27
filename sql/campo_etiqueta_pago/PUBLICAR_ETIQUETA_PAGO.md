# Publicar «Etiqueta del último pago» (Code A, 27-nov-2026)

Aprobado por David. En «Análisis de contrato», la línea del último pago dice el periodo de **su** fuente: «pagos a oct-2026» (cupones) o «cartera mensual a sep-2026» (cartera mensual). Antes decía el periodo del consumo.

Rama `campo-etiqueta-pago`, sin push:
- **geoportal-emdupar** (`~/geoportal-emdupar-pago`), sobre main `4f965e1`: SQL, pantalla y pruebas.
- **geoportal-web**: **sin cambios**. La Edge `geoportal-campo` (`00f9f45`) devuelve la respuesta de la RPC tal cual. No se despliega Edge y las sondas no cambian.

Huellas: campo `c476f14d495ea7bdf6c3f42101e9a583` → **`9f8b8ec55fc7e1c56fdf74a5f4e7f3c4`**, ordenada con `collate "C"`. En esta base da el mismo valor que la fórmula anterior. Acta `111506c6…` y Técnica `838b8098…` no cambian.

Cambio: una sola línea de `public.geoportal_campo_analisis_contrato(text,text,text)`. El md5 de la función pasa de `6ed039f4…` a `81d0967e…`:
```
-    'pago', case when f.ultimo_pago is not null then f.ultimo_pago - 'corte' || jsonb_build_object('dias', …) end,
+    'pago', case when f.ultimo_pago is not null then f.ultimo_pago || jsonb_build_object('dias', …) end,
```

## Orden (no cambiarlo)
### 1. SQL (editor de Supabase), cada archivo con su md5
1. `huellas_solo_lectura_campo_etiqueta_pago_editor.sql` (`de80815a039c56fa858fe7c9f1ab3af7`). ANTES: las tres filas dicen «PUBLICADA».
2. `ensayo_en_transaccion_campo_etiqueta_pago_editor.sql` (`c306782ae2cca9fde9c9f894d62e7919`).
   - Debe terminar en ERROR con «RESULTADO: 23 de 23 pruebas correctas — SIN FALLAS». No deja nada.
   - Inserta y luego deshace 3 contratos de prueba `9918000001NN` en `cartera_suscripcion` y `bi_interno.ficha_contrato`, y 5 correos `ztpag.*`. La prueba 00.01 comprueba antes que no existan.
   - La prueba 00.02 comprueba que la ficha tiene la llave y los 3 CHECK que tiene el doble local.
   - Si da otro número, pare y mándeme el texto.
3. `migracion_campo_etiqueta_pago_editor.sql` (`47fbebcc1fcf892bc7491e1e8916ea8c`).
4. `verificacion_campo_etiqueta_pago_editor.sql` (`88002ad33f34bbb1fdef3f99c6ac0498`): 8 de 8 OK.
5. Huellas otra vez: la fila 1 dice «CON ESTE CAMBIO» (`9f8b8ec5…`); las filas 2 y 3 dicen «PUBLICADA».

Reversa, si hiciera falta: `reversa_campo_etiqueta_pago_editor.sql` (`41a4bc6a695642a662d44cc718629ee4`). Devuelve el texto publicado y no toca datos.

### 2. Edge
No hay. `geoportal-campo` queda en `00f9f45`.

### 3. Frontend (después del SQL)
- Hacer merge de `campo-etiqueta-pago` en main, `npm run build` y desplegar.
- Si el frontend sale antes que el SQL, no se rompe nada: sin `pago.corte`, la pantalla sigue mostrando el periodo del consumo, como hoy (probado en Chrome con la base de antes).

## Pruebas locales (clúster 55432, sin Supabase)
- `pruebas_locales/correr_local.py`: 17 de 17. Cubre el ensayo (23 de 23), la migración, la verificación (8 de 8), la reversa, la repetición que se rechaza, 2 guardias y 1 mutación (ver `resultados_locales.txt`).
- `scripts/prueba_chrome_etiqueta_pago.mjs`: 34 de 34. Usa la Edge REAL en Deno y Chrome real a 390 y 1280 px, con los 5 perfiles y con la base con el paquete y sin él.

## Qué probar en el celular
1. Con Análisis de contrato, consulte un contrato que haya pagado este mes. Debe decir «Último pago: … · $ …» y debajo «pagos a <mes de la carga de cupones>», por ejemplo oct-2026.
2. Consulte un contrato cuyo último pago venga de la cartera mensual. Debe decir «cartera mensual a <periodo de la cartera>».
3. La ficha («ficha a sep-2026») y el consumo siguen con su propio periodo.
