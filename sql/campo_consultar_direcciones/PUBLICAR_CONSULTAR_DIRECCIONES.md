# Publicar «Consultar direcciones» (Code A, 25-nov-2026)

Ramas `campo-consultar-direcciones`, sin push:
- **geoportal-emdupar** (`~/geoportal-emdupar-dirs`): ee6de46 SQL · 9f66662 pantallas · pruebas y esta guía, sobre main f41445f (registro flexible publicado).
- **geoportal-web** (`~/geoportal-web-dirs`): 25dbd2b, sobre 992fccd.

Huellas: campo `66496328d10a5b25eb01e572edae7cda` → **`c476f14d495ea7bdf6c3f42101e9a583`**. Acta `111506c6…` y Técnica `838b8098…` sin cambio.
Sondas: geoportal-campo 48 → 50; geoportal-acta 16 (sin cambio).

La guardia ya usa la estructura real de producción (paso 0, 25-nov 23:25):
- `consultas_analisis`, `parametros` y `reporte_registro`: md5 exacto.
- `catastro_valledupar` y `cartera_suscripcion`: las columnas que se leen y los índices por contrato.
- No hace falta otro paso 0.

## Orden (no cambiarlo)
### 1. SQL (editor de Supabase), cada archivo con su md5
1. `huellas_solo_lectura_campo_consultar_direcciones_editor.sql` — `02b24c099fddd5daf00c4ec544b78118`. ANTES: las tres filas dicen «PUBLICADA».
2. `ensayo_en_transaccion_campo_consultar_direcciones_editor.sql` — `0b2394504655da710d19815fd946d9a4`.
   - Debe terminar en ERROR: «RESULTADO: 57 de 57 pruebas correctas — SIN FALLAS». No deja nada.
   - Durante el ensayo inserta, y luego deshace, 3 contratos de prueba (`9918000000NN`) en `cartera_suscripcion` y `catastro_valledupar`. La prueba 00.01 comprueba antes que no existan.
   - Si da otro número, pare y mándeme el texto.
3. `migracion_campo_consultar_direcciones_editor.sql` — `95929a51ae2bb33ab847f28d834264ad`.
4. `verificacion_campo_consultar_direcciones_editor.sql` — `11e22477c08f1b265832bee23d8334db`: 14 de 14 OK.
5. Huellas otra vez: 1 «CON ESTE CAMBIO» (`c476f14d…`); 2 y 3 «PUBLICADA».

Reversa, si hiciera falta: `reversa_campo_consultar_direcciones_editor.sql` — `9479af0079864ef1d1d3498cfc7b59c5`.
- Nada se borra: quedan `campo.reporte_direccion_contrato`, la columna `via` y el parámetro `limite_direccion_hora`.
- Ojo: tras una reversa, «observar» vuelve a contar también las direcciones pedidas desde un formato.

### 2. Edge (después del SQL)
- Desde `~/geoportal-web-dirs`, desplegar **geoportal-campo**. `_shared` no cambió en este paquete.
- Después: `python3 -I ~/geoportal-consultas/campo/paquete_consultar_direcciones/edge/fundir_sondas_consultar_direcciones.py` (respaldo `PERMISOS_EDGE.json.bak_antes_consultar_direcciones`; 48 → 50), luego `verificar_edge.py --vivo` y las sondas.

### 3. Frontend (después de la Edge)
- Main con `campo-consultar-direcciones`, `npm run build` y desplegar.
- Con la Edge de antes, la dirección del contrato simplemente no aparece: el formulario no falla.

## Qué probar en el celular
1. **Operario sin permiso de Análisis**, en una Revisión previa:
   - Escribe un contrato real. Debe salir «Dirección del contrato: … · barrio» y, si difiere, «En el catastro: …».
   - Marca «La dirección en terreno es distinta», llena la dirección y envía.
   - En Supervisión, en el detalle, en el Excel y en el PDF deben salir las dos.
2. **Un contrato que no existe:** no sale nada.
3. **Consultar** (con Análisis), sección «Predio»:
   - Confirma la lectura de las unidades: cuántas, una por renglón, y el valor del censo debajo.
   - Confirma los rótulos.
4. **Desde Técnica**, Reportar anomalía:
   - Debe haber una sola cabecera «← Volver».
   - Al escribir un contrato, sale su dirección.
