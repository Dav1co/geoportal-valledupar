# Publicar «Registro flexible» (Code A, 25-nov-2026)

Rama `campo-registro-flexible` en los dos repos, sin push:

| Repo | Worktree | Commits |
|---|---|---|
| geoportal-emdupar (SQL, pantallas, pruebas) | `~/geoportal-emdupar-regflex` | 6882335 SQL · f3df17a pantallas · 7d0d01c Volver y derivadas · adc953e pruebas (sobre main 94cc5d3, ya con el paquete del Code B) |
| geoportal-web (Edges) | `~/geoportal-web-regflex` | 992fccd (sobre main f6a9650) |

Huellas: campo `cce593806f59d3d27c34d7f2070cc5c1` → **`66496328d10a5b25eb01e572edae7cda`** · acta `111506c6…` sin cambio · Técnica `838b80984e51cc7873a666f85d657195` sin cambio.
Sondas: geoportal-campo 43 → 48, geoportal-acta 16 (sin cambio).

## Orden (no cambiarlo)

### 0. Antes de nada: la estructura real de cuatro tablas (solo lectura)
Corra `consulta_produccion_estructura_campo_registro_flexible_editor.sql` (md5 `25746347c4e494b1efce32d72569cd54`) y mire la columna «estado» de las 8 filas «0 md5».
- Si las 8 dicen **IGUAL AL DOBLE**: siga.
- Si alguna dice **DISTINTO**: pare y mándeme la salida entera en CSV. La consulta del 24-nov no traía `campo.reportes`, `campo.reporte_fotos`, `campo.reporte_datos_sensibles` ni `public.geoportal_auditoria`, y tengo que rehacer la guardia con la estructura real (los permisos de `homelab_lectura` son lo más probable).

**25-nov, 23:40:** la primera vez, el paso 0 dio DISTINTO en `campo.reportes`, `campo.reporte_fotos` y `public.geoportal_auditoria`. La guardia ya se regeneró con la estructura real. Al volver a correr la consulta (md5 nuevo, arriba), las 8 filas deben decir IGUAL AL DOBLE.

### 1. SQL (editor de Supabase), cada archivo con su md5
1. `huellas_solo_lectura_campo_registro_flexible_editor.sql` — `4842c3534fdd21f540fbede4b6e32ef9`. ANTES: las tres filas dicen «PUBLICADA».
2. `ensayo_en_transaccion_campo_registro_flexible_editor.sql` — `99c6490e569965037a95efd301c493bb`. Debe terminar en ERROR: «RESULTADO: 97 de 97 pruebas correctas — SIN FALLAS». No deja nada. Si da otro número, pare y mándeme el texto.
3. `migracion_campo_registro_flexible_editor.sql` — `c28abc1a68cac2f3c3cd779ae2874839`.
4. `verificacion_campo_registro_flexible_editor.sql` — `b46a14f65bd331c125926b80fa5fb969`: 15 de 15 OK.
5. Huellas otra vez: 1 «CON ESTE CAMBIO» (`66496328…`); 2 y 3 «PUBLICADA».

Reversa, si hiciera falta: `reversa_campo_registro_flexible_editor.sql` — `9979391253267c5a3f903786cb6e50e6`. Nada se borra: `campo.reporte_registro` y `campo.reporte_fotos.origen` se quedan con sus datos, y el sello del PDF de cualquier reporte vuelve a ser el de antes.

### 2. Edges (después del SQL: con la base de antes, `p_registro` no existe)
Desde `~/geoportal-web-regflex`: desplegar **geoportal-campo y geoportal-acta**. Las dos montan `_shared/actas_rutas.ts`; geoportal-acta no cambia de comportamiento.
Después: `python3 -I ~/geoportal-consultas/campo/paquete_registro_flexible/edge/fundir_sondas_registro_flexible.py` (respalda en `PERMISOS_EDGE.json.bak_antes_registro_flexible`; 43 → 48), luego `verificar_edge.py --vivo` (0 errores esperados) y las sondas.

### 3. Frontend (después de la Edge)
Main con la rama `campo-registro-flexible`, `npm run build` y desplegar. Con el frontend nuevo y la Edge vieja, crear falla: por eso va al final.

## Qué probar en el celular
1. **Supervisor de Comercial**, Reportar anomalía:
   - Adjuntar desde la galería en iPhone (HEIC) y en Android.
   - Marcar «Digitar el XY del punto», cambiar el XY y enviar.
   - En Supervisión debe salir «XY digitado — registrado desde otro punto» y la foto «adjuntada desde la galería».
2. **Supervisor**: lo mismo en un formato con PDF (revisión previa inefectiva) y mirar el PDF.
3. **Operario**: igual que siempre, solo cámara. Prueba la casilla de dirección marcada y desmarcada.
4. **Supervisor desde un computador sin ubicación**: el reporte queda «sin ubicación del dispositivo».
5. **Operador de planta desde Técnica**: Reportar anomalía funciona igual, sin adjuntar ni XY.
6. **Avisos y actividades derivadas**: el número de pendientes ya es exacto (no «100+»). Descargar Excel y CSV.
