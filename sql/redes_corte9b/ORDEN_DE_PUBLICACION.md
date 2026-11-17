# Corte 9b — paquete final y orden de publicación (Code A, 17-nov-2026)

Tres paquetes SQL, cada uno con sus `_editor` (huellas → ensayo → migración → verificación → reversa). Regla vigente: máximo dos operaciones pesadas por día.

| # | Paquete | Qué trae | Parte de la huella de redes | Deja la huella | Estado |
|---|---|---|---|---|---|
| 1 | `sql/redes_corte9b/` | Fase 1a (simulación de cierre) y 1b (cierre real, foto del corte, tesela de Afectaciones, aviso de válvula cerrada) | `aad5952c27e13cc3ad45623279ba7085` | `895517fb68f74d6d6c20079c83bdf7c4` | **Publicado** (17-nov) |
| 2 | `sql/redes_corte9b_f2/` | Fase 2: alertas de presión, usuarios sensibles, afectación, lecturas de sensores, capa de cortes oculta; **reemplaza `tecnica.f_avisos`** (aviso informativo de presiones) | `895517fb68f74d6d6c20079c83bdf7c4` | `7f9c0157c47e371e1d3d87ef6bda847b` | Por publicar |
| 2b | `sql/redes_corte9b_f2/proponer_usuarios_sensibles_editor.sql` | La propuesta de usuarios sensibles (una vez; cambiar el correo) | — | — | Después del 2 |
| 3 | `sql/redes_corte9b_f3/` | Fase 3: tablas y tesela del «Flujo del agua (modelo)» | `7f9c0157c47e371e1d3d87ef6bda847b` | `fbcbd7b3da35dfdc0e4104ed4a6e8f2f` | Después del 2 |
| 3b | `sql/redes_corte9b_f3/carga_flujo/generado/` | Carga por psql: ensayo → carga → verificación (CSV md5 `2b0b8616697e22427f7019f766de1448`) | — | — | Después del 3 |

## md5 de los archivos por correr
- Fase 2: migración `e8b13147d17036d3b0ee027368e79e19` · ensayo `c683124b372aa28058ff9c5ce6fbb407`
- Fase 3: migración `6bfc7c89f0849930266834b6aaf06185` · ensayo `47c9e150cda0dae7c57916e8beeca656`
- Carga del flujo: `10428f6178428da1929b25a8c5b31a9d` (carga) · `463ebc9bd9d0a0744a84c03cff782e7d` (partes/10_flujo.sql)

## Pasos
1. **Fase 2:** `huellas_solo_lectura_redes_corte9b_f2_editor.sql` (debe decir «9b 1a + 1b (listo para la Fase 2)» y `tecnica.f_avisos` «9b 1b (sin cambiar)») → `ensayo_en_transaccion_…` (32 de 32, con TIEMPOS) → `migracion_…` → `verificacion_…` (7 OK).
2. **Propuesta de sensibles:** `proponer_usuarios_sensibles_editor.sql` con el correo de un administrador. Recorre la cartera: correrla temprano.
3. **Fase 3:** huellas («FASE 2 (lista para la Fase 3)») → ensayo (17 de 17) → migración → verificación (6 OK).
4. **Carga del flujo** (psql, desde `carga_flujo/generado/`): `ensayo_carga_flujo_modelo.sql` (10 de 10) → `carga_flujo_modelo.sql` → `verificacion_carga_flujo_modelo.sql` (4 OK).

## Avisos
- La Fase 2 **cambia `tecnica.f_avisos`** (un bloque nuevo, D11). Avisado al Code B en la entrada de bitácora. La verificación del 9b (1a + 1b) que mira su md5 deja de valer.
- Después de cada fase, la fila 03 de la verificación de la fase anterior deja de valer (cambia el conjunto de funciones).
- Edge y pantallas de las Fases 2 y 3: Code B. Sondas propuestas: `paquete_fase1/corte9b/sondas_propuestas.json`.
