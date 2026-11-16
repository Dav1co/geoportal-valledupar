# Técnica · fase 1 · Corte 4a — Arreglos de la §25, respuestas de la §26 y Dashboard distribución — INFORME

Fuente: §25 y §26 de la bitácora; `02_plan_por_cortes.md` (Corte 4, partido en 4a y 4b); D-12 (supervisor de distribución).
**Nada se aplicó en Supabase.** Todo se probó en local: PostgreSQL 17 + PostGIS 3.7 de Homebrew, sobre el 3b con la carga real, y las 4 funciones de permisos con el texto del 14-nov (paquete de Análisis de contrato).

## Qué hay

### SQL (`sql/`)
`pruebas_locales/generar.py` toma de la base local los textos del 3b de las 10 RPC que cambian, les aplica reemplazos exactos (cada uno se exige una sola vez) y escribe 10, 25, 05, 80, 90 y los `_editor`.
- **`10_esquema.sql`**
  - **Guardia:** exige el 3b exacto (conjunto `45971067176a3d30286b6227f0447c0d`) y las 4 funciones de permisos del 14-nov (md5 de cada una). Si alguna difiere, se detiene y muestra el md5 encontrado.
  - `redes.danos.sector_num smallint check (1 a 100)` (§25.1). `sector_texto` queda, sin uso nuevo.
- **`15_permisos.sql`:** columna `ver_dashboard_redes` en la lista blanca. `geoportal_puede`, `geoportal_mis_permisos`, `geoportal_admin_permisos` (parámetro 20, `p_dashboard_redes`, con la compuerta de aislamiento) y `geoportal_admin_listar`: el texto del 14-nov **más solo** lo de `dashboard_redes`.
- **`24_perfiles.sql`:** perfiles de redes. **admin**; **supervisor** = `ver_dashboard_redes`; **operador** = cualquier otra persona de Técnica. El supervisor de planta pasa a operador en redes. `f_autorizar_captura_redes`: el supervisor de distribución captura sin formulario asignado. `f_editor_ficha`: admin y supervisor de distribución.
- **`25_reemplazos.sql`:** 10 RPC del 2, 3a y 3b.
  - **Sin evidencia fotográfica para nadie (§25.8).** Se rechaza en la RPC con un mensaje claro, y las preparaciones exigen al menos 1 foto.
  - **Sector entero de 1 a 100** en el daño.
  - **Galería para toda Técnica (§26.1)**, auditada.
  - **Ficha:** el supervisor de distribución la edita; **el origen solo el administrador** (§26.2, `puede_origen`).
- **`26_bandejas.sql`:** 7 RPC nuevas.
  - `mi_perfil`;
  - `danos` (abiertos, todos, ocultos y no identificados);
  - `dano_evento` (ocultar, reincluir y reabrir, con motivo);
  - `dano_tercero` (lectura auditada sin el valor);
  - `intervencion_evento` (ocultar, reincluir y anular; avisa si resolvía un daño);
  - `reportes_bot`;
  - `crear_activo_bandeja` (solo tipos de punto; el activo queda «por verificar» con origen `asociacion`).
- **`40_permisos.sql`:** `revoke all … from public, anon, authenticated, service_role` y `grant execute` solo a `service_role`, para todas las `geoportal_redes_*`. Deja la marca de la migración en la auditoría.
- **`70_pruebas.sql`:** 70 pruebas, con su red (99500xx, ZT5-…) y sus usuarios con prefijo. No supone códigos ni datos reales.
- **`80_verificacion.sql`:** 8 OK y 3 INFO.
- **`90_reversa.sql`:** vuelve exacta al 3b y a los textos del 14-nov de las 4 funciones de permisos.
  - Se niega si alguien tiene `ver_dashboard_redes` (primero hay que quitarlo en Administración).
  - Se niega si hay daños con `sector_num`.
  - Nada se borra.

Huellas: 3b `45971067176a3d30286b6227f0447c0d` → **4a `1a2be013019c9a59f1c1e0f2241661f0`**.

### Edges (rama `tecnica-corte4a`)
- **`geoportal-redes`:**
  - Los errores de regla de la base (23514, 23502 y 22001) salen como **400 con un mensaje claro** (§25.3), por ejemplo «El dato «sector» no cumple las reglas…».
  - Rechaza `sin_evidencia_motivo` y las preparaciones sin fotos.
  - Rutas nuevas: `mi_perfil`, `danos`, `dano_evento`, `dano_tercero` (sin caché), `intervencion_evento`, `reportes_bot`, `reporte_convertir` (lista cerrada de claves), `reporte_descartar` y `crear_activo_bandeja`.
- **`geoportal-admin`:** reenvía `dashboard_redes` solo si llega como booleano. Al darlo exige el aislamiento verificado (409 con un mensaje claro); al quitarlo no.
- `_shared/auth.ts` y `autorizar()` sin tocar.

### Frontend (rama `tecnica-corte4a`, desde `tecnica-corte3b`)
- **Daño:**
  - sector numérico de 1 a 100;
  - sin «sin evidencia»;
  - los tiempos de reparación solo con la casilla «El daño ya se reparó»;
  - los topes se revisan en la pantalla antes de enviar (§25.4).
- **Registrar intervención:**
  - «Daño o falla que se atiende» va **después del minimapa** (sección 2);
  - «Con esta queda resuelto el daño» va **al final, antes de Guardar**;
  - aviso «No hay daños abiertos en este activo ni cerca»;
  - sin «sin evidencia»;
  - todos los topes en la pantalla.
- **Ficha:** el origen solo aparece si el servidor lo permite (`puede_origen`). La revisión de rangos se hace antes de la vista previa.
- **Dashboard distribución** (nuevo), con 4 pestañas:
  - **No identificados:** «Asociar» o «Crear el activo».
  - **Intervenciones:** «Recursos por completar» y «Recientes», con ocultar y anular con motivo.
  - **Daños y fallas:** filtros; ocultar, reincluir y reabrir; «Ver el nombre o la placa del tercero», que queda auditado.
  - **Reportes del bot:** convertir en daño o descartar.
  - El aviso de cada acción queda arriba de la lista.
- **Área técnica:**
  - botones «Dashboard PTAP» (planta) y «Dashboard distribución» (redes);
  - selector PTAP | distribución si la persona tiene los dos;
  - quien solo tiene redes entra directo.
- **Administración:**
  - casilla «Dashboard distribución (supervisor de distribución)» y perfil rápido «Supervisor de distribución»;
  - solo aparecen si el servidor ya lista la columna, y después de guardar se vuelve a leer el usuario para confirmar.

## Resultados (N de N)
- **Ensayo:** **70 de 70**, sin rastro.
- **Arnés local:** **20 de 20**, con la carga real. Comprueba:
  - la reversa exacta al 3b y al 14-nov;
  - reabrir el daño real;
  - ocultar la intervención real;
  - que el supervisor de distribución edita el alias y no el origen;
  - la lista de daños en 0,03 s.
- **Edge simulada:** `geoportal-redes` **148 de 148**; `geoportal-admin` **6 de 6**. Verificador de permisos: 0 errores (perfil Y nuevo).
- **Chrome real, a 390 px y en escritorio: 43 de 43** (`scripts/prueba_chrome_dashboard_c4a.mjs`).
- **Regresiones:** 3a 76/76, 3b 41/41, Corte 2 60/60, 1b 60/60, 0b 68/68, análisis 143/143, p14 54/54, áreas 51/51, `tsc` y build (`resultados/regresiones.txt`).

## Orden de publicación
1. **SQL:**
   1. `huellas_solo_lectura` (debe decir «CORTE 3b (listo para el 4a)» y las 4 «14-nov (sin cambiar)»);
   2. `ensayo_en_transaccion` (ERROR con «70 de 70 … SIN FALLAS»);
   3. `migracion`;
   4. `verificacion` (8 OK);
   5. huellas otra vez («CORTE 4a (aplicado)»).
2. **Edges:** `geoportal-redes` y `geoportal-admin`.
3. **Frontend.**
4. **En Administración:** dar «Dashboard distribución» a los supervisores de distribución. Necesitan también «Registro técnico» para los formularios. Ojo: el supervisor de planta ya no supervisa redes.
