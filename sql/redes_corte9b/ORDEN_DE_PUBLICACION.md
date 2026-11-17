# Corte 9b — paquete final y orden de publicación (Code A, 17-nov-2026, tarde)

Tres paquetes SQL, cada uno con sus `_editor` (huellas → ensayo → migración → verificación → reversa).

**HUELLA FINAL de redes con el 9b completo (después de la Fase 3): `a327aa51f43bb5cc2112a6db089718ed`.** De ahí parte la guardia del Corte 14 (ya no vale `fbcbd7b3…`).

| # | Paquete | Qué trae | Parte de la huella de redes | Deja la huella | Cuándo |
|---|---|---|---|---|---|
| 1 | `sql/redes_corte9b/` | Fase 1a (simulación de cierre) y 1b (cierre real, foto del corte, tesela de Afectaciones, aviso de válvula cerrada) | `aad5952c27e13cc3ad45623279ba7085` | `895517fb68f74d6d6c20079c83bdf7c4` | **Publicado** (17-nov) |
| 2 | `sql/redes_corte9b_f2/` | Fase 2: alertas de presión (solo horas confiables), usuarios sensibles, afectación, daños abiertos sin límite de fecha, lecturas de sensores, capa de cortes oculta; **reemplaza `tecnica.f_avisos`** (aviso informativo de presiones, **apagado** por omisión) | `895517fb68f74d6d6c20079c83bdf7c4` | `24e62e151ff418ea6acf631572d72683` | **HOY** |
| 3 | `sql/redes_corte9b_f3/` | Fase 3: tablas y tesela del «Flujo del agua (modelo)» | `24e62e151ff418ea6acf631572d72683` | `a327aa51f43bb5cc2112a6db089718ed` | **HOY**, después del 2 |
| 3b | `sql/redes_corte9b_f3/carga_flujo/generado/` | Carga por psql: ensayo → carga → verificación (CSV md5 `2b0b8616697e22427f7019f766de1448`) | — | — | **HOY**, después del 3 |
| 3c | `sql/redes_corte9b_f3/encender_flujo_modelo_editor.sql` | Enciende la capa «Flujo del agua (modelo)» en la lista del geovisor | — | — | **HOY, de último**: después de la Edge y del frontend |
| 2b | `sql/redes_corte9b_f2/proponer_usuarios_sensibles_editor.sql` | La propuesta de usuarios sensibles (una vez; cambiar el correo). Recorre la cartera | — | — | **MAÑANA**, temprano |

## md5 de los archivos por correr
- Fase 2: migración `9eda63eb07f6ea9a1dc6d8ecf1053ea4` · ensayo `92b4528352bd772125ed9ac2822cb603`
- Fase 3: migración `586cb772064a6db1fda4df126d802301` · ensayo `8e31927358e7daf6a272695da622051d`
- Carga del flujo: `10428f6178428da1929b25a8c5b31a9d` (carga) · `463ebc9bd9d0a0744a84c03cff782e7d` (partes/10_flujo.sql). No cambió.
- Encender la capa: `66f437e893e2fe86b4ad75399a3586b1`
- `tecnica.f_avisos`: antes `898bafa5adddfcc08d65adf138d0114a` (9b 1b) → después de la Fase 2 `2a7989bead5fd35d3a4d0c4e45bcb92b`.

## Pasos de HOY
1. **Fase 2:** `huellas_solo_lectura_redes_corte9b_f2_editor.sql` (debe decir «9b 1a + 1b (listo para la Fase 2)», `tecnica.f_avisos` «9b 1b (sin cambiar)» y 14 «NO EXISTE») → `ensayo_en_transaccion_…` (**43 de 43**, con TIEMPOS) → `migracion_…` → `verificacion_…` (**7 OK**; la fila INFO del aviso debería decir «0 · 5, 7, 10, 12, 14 · 5985», si el Plan Maestro de producción es el mismo que cargué en local).
2. **Fase 3:** huellas («FASE 2 (lista para la Fase 3)») → ensayo (**17 de 17**) → migración → verificación (**6 OK**).
3. **Carga del flujo** (psql, desde `carga_flujo/generado/`): `ensayo_carga_flujo_modelo.sql` (10 de 10) → `carga_flujo_modelo.sql` → `verificacion_carga_flujo_modelo.sql` (4 OK).
4. (Corte 14 del Code B, si va hoy: su guardia parte de `a327aa51f43bb5cc2112a6db089718ed`.)
5. Edge `geoportal-redes` y frontend (Code B).
6. **Encender la capa de flujo:** `encender_flujo_modelo_editor.sql`. Debe responder «activa · preparada · solo supervisores: sí» y 9.580 tubos. Se niega si el flujo no está cargado. Para apagarla: `update redes.geovisor_capas set estado = 'espera_dato' where codigo = 'flujo_modelo';`

## MAÑANA, temprano
7. **Propuesta de sensibles:** `proponer_usuarios_sensibles_editor.sql` con el correo de un administrador.

## Avisos
- La Fase 2 **cambia `tecnica.f_avisos`** (un bloque nuevo, D11). Avisado al Code B en la entrada de bitácora. La verificación del 9b (1a + 1b) que mira su md5 deja de valer.
- **El aviso de presiones sale APAGADO.** Para encenderlo (Técnica, cuando lo revise): Avisos → «Ver y cambiar los plazos» → «Aviso de presiones del modelo» = 1 (parámetro `presion_modelo_aviso`). Encendido diría hoy «5.985 nodos fuera de rango según el modelo».
- Las alertas y el aviso de presiones no cuentan las horas 5, 7, 10, 12 y 14 de la red existente (tabla `redes.presion_horas_no_confiables`; una hora se vuelve a contar con `activa = false`). La capa de presión del geovisor no cambia.
- Después de cada fase, la fila 03 de la verificación de la fase anterior deja de valer (cambia el conjunto de funciones). Después de encender la capa, la fila 06 de la verificación de la Fase 3 (espera «espera_dato») deja de valer.
- Edge y pantallas de las Fases 2 y 3: Code B. Sondas propuestas: `paquete_fase1/corte9b/sondas_propuestas.json` (9, con la de `afectaciones_danos`).
