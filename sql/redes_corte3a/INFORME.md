# Técnica · fase 1 · Corte 3a — Intervenciones — INFORME

Fuente: `01_modelo_propuesto.md` §C y §I; `02_plan_por_cortes.md` (fila 3); la maqueta `Intervencion.dc.html`; las §4, §6 y §17 de la bitácora; y las respuestas de David al Corte 2.
**Nada se aplicó en Supabase.** Todo se probó en local, en PostgreSQL 17 + PostGIS 3.7 de Homebrew, sobre el 1a con la carga real y el Corte 2 publicado.

**El Corte 3 se partió en dos.** 3a: intervenciones (este paquete). 3b: la ficha como «perfil» (§22 y §23 de la bitácora), en la próxima sesión.

## Qué hay

### SQL (`sql/`)
`pruebas_locales/generar.py` toma de la base local la huella del Corte 2 y los textos de lo que se reemplaza, y con eso escribe 10, 05, 80, 90 y los `_editor`.

- **`10_esquema.sql`**
  - **Guardia:** exige el Corte 2 exacto (huella `06ecefcf…` del conjunto de funciones y las de `v_dano` y `v_epicrisis`), el bucket `redes-evidencias` con JPEG y PDF y el consecutivo ITV.
  - **Catálogos:** `tipos_intervencion` (los 5 de la maqueta; correctivo, reparación y reposición atienden daños; inversión aparte) y `unidades_material`.
  - **Hechos:** `intervenciones`, `intervencion_activos` (también intervenidos), `intervencion_materiales`, `intervencion_fuentes` (por versiones), `intervencion_archivos` (fotos JPEG y documentos PDF), `intervencion_eventos` e `intervencion_preparaciones`. Solo inserción.
  - **Coherencia** con triggers: el tipo admite el daño, el activo y el daño son del mismo sistema, y los también intervenidos son del mismo sistema y distintos del principal.
- **`20_vistas.sql`**
  - `v_intervencion`: activo vigente (el asociado o el del formulario), estado (flujo A: «cerrada»), oculta, fotos, documentos, «sin evidencia», recursos completos o por completar, aportantes y duración.
  - `v_intervencion_fuentes` (la última versión) y `v_no_identificados` (intervenciones y daños sin activo).
  - **Reemplaza** `v_dano` (el activo vigente puede venir de «asociar activo»; mismas columnas) y `v_epicrisis` (suma las intervenciones en el activo principal y en cada también intervenido; el daño sin fotos dice «sin evidencia fotográfica»; el alta de un activo creado por una inversión dice «(inversión ITV-…)»).
- **`25_rpc.sql`**: 8 RPC nuevas y 2 reemplazadas, todas solo para `service_role`.
  - **Captura** (`f_autorizar_captura(…, 'mantenimiento')`): `formulario_intervencion`, `danos_abiertos`, `preparar_intervencion` y `crear_intervencion`.
  - **Supervisor y administrador:** `intervenciones` (lista), `intervencion_recursos`, `no_identificados` y `asociar_activo`.
  - **Reemplazadas:** `preparar_dano` y `crear_dano` (respuesta 2 de David).
  - Internas: `f_supervisor`, `f_mat_refrescar_uno`, `f_activo_crear`, `f_fuentes_validas` y `f_dano_elegible`.
- **`30_semilla.sql`:** 5 tipos, 8 unidades y 11 parámetros (`on conflict do nothing`).
- **`40_permisos.sql`:** revoke a los cuatro roles, RLS y execute solo a `service_role`.
- **`70_pruebas.sql`:** **122 pruebas**, con su propia red de prueba (ID 99300xx, LABEL ZT3-…). No supone códigos ni datos reales.
- **`80_verificacion.sql`:** 11 OK y 3 INFO. Desde aquí, la fila 07 de la verificación del Corte 2 dice MAL a propósito (el conjunto de funciones cambió).
- **`90_reversa.sql`:** devuelve las 2 RPC y las 2 vistas al texto exacto del Corte 2. Se niega si hay intervenciones, preparaciones, archivos, activos creados por intervenciones o daños asociados.

### Edge `geoportal-redes` (rama `tecnica-corte3a` de geoportal-web)
- Rutas nuevas: `formulario_intervencion`, `danos_abiertos` (la posición en el cuerpo), `preparar_intervencion` (firma una URL por foto y por PDF), `crear_intervencion` (lista cerrada de campos), `intervenciones`, `intervencion_recursos`, `no_identificados` y `asociar_activo`.
- `preparar_dano` acepta 0 fotos (lo decide la RPC por perfil) y `crear_dano` acepta `sin_evidencia_motivo`.
- `storage.ts` acepta las rutas `intervenciones/AAAA-MM/<uuid>/<n>.jpg|pdf`. El cuerpo admite hasta 32 KB.
- `_shared/auth.ts` y `autorizar()` sin tocar. Sondas nuevas en `PERMISOS_EDGE.json` (respaldo `.bak_antes_redes_c3a`); el estado sigue en `planeada_corte2` hasta que David despliegue.

### Frontend (rama `tecnica-corte3a` desde `main`)
- **`FormularioIntervencion.tsx`**, «Registrar intervención», con las 7 secciones de la maqueta:
  1. de dónde nace (programada o mejora, o el daño abierto del activo o de los cercanos) y tipo; inversión: activo nuevo o mejora;
  2. activo con el mismo minimapa del Corte 2: el más cercano preseleccionado, «no identificado» marcando el punto, el activo nuevo (punto o tramo de dos toques) y los también intervenidos con los cercanos propuestos;
  3. inicio (del celular al abrir) y fin, con la duración;
  4. descripción y materiales;
  5. EMDUPAR o contratista, contrato u orden y compañeros;
  6. el operario marca quién aporta; el supervisor ve valor, porcentaje y soporte;
  7. fotos de antes, durante y después, y PDF; el supervisor puede registrar sin fotos con el motivo.
- **`MiniMapaRed.tsx`:** modo «línea» (inicio y fin del tramo nuevo) y dibujo del punto o la línea marcados.
- **`IntervencionesSupervisor.tsx`** (entrada «Intervenciones · supervisión», solo supervisor y administrador): bandeja de no identificados con los propuestos y «Asociar», y recursos por completar. En el Corte 4 pasan al Dashboard distribución.
- **Daño:** el supervisor y el administrador pueden registrarlo sin fotos («sin evidencia fotográfica», con el motivo); al guardar, «Registrar la reparación» abre la intervención con el daño ya elegido.
- **Ficha:** botón «Registrar intervención» (pospuesto del 1b), chip «Por verificar» y la intervención en azul en la epicrisis.

## Resultados (N de N)
- **Ensayo:** **122 de 122**, termina en el ERROR esperado y no deja rastro (7,2 s después de la carga real).
- **Arnés local** (`pruebas_locales/correr_local.py`): **21 de 21**. Con la carga real, predios y un daño real. Recorre huellas, ensayo, migración, verificación, guardia, reversa exacta al Corte 2, la verificación del Corte 2 de nuevo, una reparación real sobre V85 que atiende su daño, una inversión que crea RED-010574, la tesela y la búsqueda con el tramo nuevo, y la reversa con datos (rechazo). Registrar una intervención tarda 0,22 s.
- **Edge simulada:** **107 de 107** (66 de antes y 41 nuevas). `deno check` sin errores. Verificador de permisos: **0 errores**.
- **Chrome real, a 390 px y en escritorio: 76 de 76.** App compilada, Edges reales en Deno, RPC reales sobre la carga completa y Storage simulado.
- **Regresiones:** Corte 2 **60 de 60**, 1b **60 de 60**, 0b **68 de 68**, áreas **51 de 51**, `tsc` y `npm run build`.

## Decisiones de esta sesión (de Code)
Ver la entrada del Corte 3a en la bitácora.

## Ajustes del 15-nov-2026 (19:20), con las respuestas de David al 3a (antes de publicar)
1. **Tiempos:** el operario conserva el tope de 7 días atrás y 72 h; el supervisor y el administrador registran las obras largas sin tope (el formulario les manda los topes en nulo).
2. **Un daño puede tener varias intervenciones.** Columna nueva `resuelve_dano` («Con esta queda resuelto el daño»): la intervención que la marca le pone el servicio restablecido y lo deja **atendido**; las demás le ponen el inicio de la reparación (si no lo tenía) y un evento `en_atencion` («sigue abierto»). La epicrisis dice «(lo resuelve)» o «(sigue abierto)». La verificación 09 comprueba el evento de cada una.
3. **El origen del activo nuevo** sigue saliendo de quién aporta; la corrección del origen la hace el Corte 3b (edición de la ficha).
