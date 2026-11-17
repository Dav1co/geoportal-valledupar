# Geoportal EMDUPAR — instrucciones para Code

## Continuidad entre sesiones (obligatorio)
Cada sesión empieza sin memoria de la anterior. Para no perder contexto:

**Al empezar**, antes de hacer nada, lee en este orden:
1. `~/geoportal-consultas/estado_produccion_2026-11-14.md` (o el `estado_produccion_*` más reciente): lo que está publicado.
2. `~/geoportal-consultas/pendientes_futuro_geoportal.md`: el registro de pendientes vigente.
3. La bitácora del trabajo en curso. Hoy es Técnica, fase 1: `~/geoportal-consultas/tecnica/paquete_fase1/bitacora_tecnica_fase1_15nov.md`, con `01_modelo_propuesto.md`, `02_plan_por_cortes.md`, `03_decisiones.md`, `hallazgos_capas_redes_15nov.md` y `addendum_fase1_minimapas.md` en la misma carpeta.

Tu memoria propia (`~/.claude`) **no** es la fuente del estado de producción. Si contradice estos archivos, ganan los archivos.

**Al terminar cada corte o tarea**, antes de entregar el resumen, agrega al final de la bitácora una entrada en la sección **«Registro por corte»** (créala si no existe), con:
- Fecha y hora, el corte o la tarea, la rama, el worktree y el commit.
- Lo que se hizo y cómo se probó (N de N).
- **Decisiones tomadas** en la sesión (tuyas con su porqué, o de David).
- **Lo que se pospuso** o quedó fuera, y para qué corte.
- Lo que falta para publicar (SQL, Edge o frontend, en orden) y lo que David debe probar en el celular.
- Las preguntas abiertas para David.

Si algo pospuesto o pendiente es de más largo plazo, propón también la línea para `pendientes_futuro_geoportal.md` (no lo reescribas: agrega la línea en la sección que corresponda).

## Reglas permanentes
- Nunca push, merge, despliegue, SQL en Supabase ni consultas a Supabase. Solo commits locales, en ramas o worktrees propios, con el `.env` enlazado (`ln -s ~/geoportal-emdupar/.env .env`).
- `_shared/auth.ts` y `autorizar()` no se tocan.
- Nada se borra: se oculta o se desactiva con motivo. Los hechos son de solo inserción.
- Todo objeto nuevo: `revoke all ... from public, anon, authenticated, service_role` antes de dar los permisos.
- SQL con versión `_editor`, una verificación por archivo, ensayo que termina en ERROR esperado, reversa y guardias md5. Las pruebas crean sus propios datos con prefijo.
- **Las pruebas deben ver lo que ve producción** (encargo del Corte 6c, 16-nov; vale para todos los cortes):
  - En Supabase, las sesiones de la API (rol `authenticator`, también `service_role` desde la Edge) cargan pg-safeupdate: todo `DELETE` o `UPDATE` **sin WHERE** falla (`21000`), también dentro de funciones SECURITY DEFINER. El editor SQL no lo hace. Ninguna función lleva `DELETE`/`UPDATE` sin `WHERE` (si es a propósito, `where true`). El ensayo y la verificación de cada paquete comprueban que `redes.f_funciones_sin_where()` devuelve cero filas (cubre `redes`, `tecnica` y `public.geoportal_redes_*`; `ON CONFLICT … DO UPDATE` no cuenta). pg-safeupdate no se compila ni se carga en local (decisión de David, 16-nov).
  - Topes de producción: `service_role` `statement_timeout = 30s`, `authenticated` 8 s, `authenticator` `lock_timeout = 8s`. Las llamadas simuladas de la Edge (arnés y pruebas de Chrome) corren con `set role service_role`, `statement_timeout = '30s'` y `lock_timeout = '8s'`.
  - El arnés mide el tiempo de las RPC que leen tablas grandes con el volumen real (111 mil contratos, 35.781 activos). Ninguna petición rehace ni recalcula tablas enteras. Un tiempo local no es el de producción: el mismo `insert` tardó 2 s en local y 44,7 s en producción.
  - En producción no están instalados pg_cron ni pg_net.
  - Las bases locales llevan los `CHECK`, las llaves y los disparadores de producción de **toda tabla en la que escriban las pruebas** (regla de David, 17-nov; un ensayo falló en producción por un `CHECK` que el doble local no tenía).
  - Los dobles locales tienen la **misma clase de objeto** que en producción: por ejemplo, `public.predios_comercial` es una vista materializada (no se escribe ni se refresca), y su doble local también debe serlo.
- `verificar_edge.py` debe **rechazar las opciones que no conoce** (terminar con error y decir cuál es), en vez de ignorarlas.
- Sin términos tarifarios en las pantallas del operador de Técnica y de Aseo.
- Nombre y teléfono del suscriptor solo en pantalla, nunca en descargas, listados ni PDF. En Técnica: el teléfono nunca; el **nombre solo en la tarjeta del contrato del geovisor técnico** (decisión de David, 15-nov 23:05; §30 de la bitácora), con lectura auditada y nunca en descargas, listados ni PDF.
- Portabilidad: nada que dependa solo de Supabase cloud.
- Pantallas probadas en Chrome real a 390 px y en escritorio.
- Un corte por sesión. Al terminar, PARA y entrega el resumen.
