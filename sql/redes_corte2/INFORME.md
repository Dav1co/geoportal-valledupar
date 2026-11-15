# Técnica · fase 1 · Corte 2 — Daños y fallas, reportes del bot y minimapa de la red — INFORME

Fuente: `01_modelo_propuesto.md` §B, §B.1 (N-14) y §I; `02_plan_por_cortes.md` (fila 2); la maqueta `Dano.dc.html`; la adenda de minimapas; y las §3, §6, §17 y §19 de la bitácora.
**Nada se aplicó en Supabase.** Todo se probó en local, en PostgreSQL 17 + PostGIS 3.7 de Homebrew, sobre el 1a con la carga real de los shapefiles.

## Qué hay

### SQL (`sql/`)
`pruebas_locales/generar.py` toma de la base local la huella del 1a y el texto de su `v_epicrisis`, y con eso escribe 10, 05, 80, 90 y los `_editor`.

- **`10_esquema.sql`**
  - **Guardia:** exige el 1a exacto (la huella md5 del conjunto de sus funciones), `tecnica.f_autorizar_captura`, `tecnica.f_max_horas_inicio` y Storage. Se niega si el bucket ya existe o si hay políticas que lo mencionen.
  - **Catálogos:** `tipos_dano` (con clase, sistemas y si pide rotura), `tipos_rotura`, `causas` (propias), `tipos_tercero`, `marcas_riesgo` y `caudales_fuga`, que **queda vacía** (D-16).
  - **Daños:** `danos`, `dano_datos_sensibles` (el nombre o la placa del tercero, D-26), `dano_tiempos` (eventos), `dano_eventos`, `dano_fotos` y `dano_preparaciones` (la reserva del id).
  - **Reportes del bot (N-14):** `reportes_externos` (**sin nombre ni teléfono**), `reporte_externo_fotos` y `reporte_externo_eventos`.
  - **Coherencia del daño:** el tipo es de la clase y del sistema, y el activo es del mismo sistema.
  - **Reglas:** 10 tablas de solo inserción y 5 catálogos sin borrar.
  - **Bucket `redes-evidencias`:** privado, 5 MB, JPEG y PDF, y sin políticas, con la misma disciplina que `campo-fotos`.
- **`20_vistas.sql`**
  - `v_dano_tiempos`.
  - `v_dano`: estado (reportado, en atención, atendido u oculto); respuesta, reparación y total; y la pérdida, que es **nula y «sin_tabla»** sin caudales, «no_aplica» sin rotura y «sin_fila» si no hay fila para el caso.
  - `v_reporte_externo`, con el estado que se le devuelve al bot.
  - **`v_epicrisis`:** la del 1a más los daños y fallas del activo, con sus mismas columnas.
- **`25_rpc.sql`**, con 8 RPC nuevas, todas solo para `service_role`:
  - **Daño:** `formulario_dano`, `preparar_dano` y `crear_dano`. Las tres pasan por `tecnica.f_autorizar_captura(…, 'danos_fallas')`: el operador necesita el formulario asignado; el supervisor y el administrador pasan.
  - **Minimapa:** `activo_buscar`, `tramo_nodos` y `mvt` (la tesela liviana: una red, desde z15; los accesorios desde z17; sin material, edad ni origen).
  - **Bot:** `reporte_convertir` y `reporte_descartar`, solo para supervisor y administrador. Más la entrada **interna** `redes.f_reporte_externo_recibir`, que nadie de la API ejecuta y que rechaza nombre, teléfono, cédula o correo.
- **`30_semilla.sql`:** 13 tipos (7 daños y 6 fallas), 4 roturas, 6 causas, 6 terceros, 4 marcas y 6 parámetros (`on conflict do nothing`, para volver a migrar después de una reversa).
- **`40_permisos.sql`:** revoke a los cuatro roles, RLS y execute solo a `service_role` en las 8 RPC.
- **`70_pruebas.sql`:** **87 pruebas**, con su propia red de prueba armada con el motor del 1a.
- **`80_verificacion.sql`:** 11 OK y 3 INFO.
- **`90_reversa.sql`:** devuelve `v_epicrisis` al texto exacto del 1a. Se niega si hay daños, reportes, caudales o fotos.

### Para el editor
`huellas_solo_lectura_redes_corte2_editor.sql`, `ensayo_en_transaccion_redes_corte2_editor.sql`, `migracion_redes_corte2_editor.sql`, `verificacion_redes_corte2_editor.sql` y `reversa_redes_corte2_editor.sql`.

### Edge y frontend
- **Edge** `geoportal-redes` (rama `tecnica-corte2`), con rutas nuevas:
  - `formulario_dano`;
  - `preparar_dano`, que firma una URL de subida por foto y reutiliza `storage.ts` de campo con el bucket y las rutas de daños;
  - `crear_dano`, con la forma validada y una lista cerrada de campos;
  - `activo_buscar`, `tramo_nodos` y `tesela` (MVT binario, con caché privada de 5 min; vacía = 204).
- **Frontend** (rama `tecnica-corte2`, desde `tecnica-corte1b`):
  - `FormularioDano.tsx`, en las 7 secciones de la maqueta;
  - `MiniMapaRed.tsx`: MapLibre diferido, una sola red, el más cercano preseleccionado, tocar un tramo → sus nodos, búsqueda por código y «no identificado» marcando el punto;
  - «Ver ficha» desde el minimapa (respuesta de David al 1b);
  - la epicrisis de la ficha con «Daño» o «Falla» y su estado;
  - el chip «Daño o falla» ya no sale como «Próximamente».

## Resultados (N de N)
- **Ensayo:** **87 de 87**, termina en el ERROR esperado y no deja rastro.
- **Arnés local** (`pruebas_locales/correr_local.py`): **21 de 21**. Recorre:
  - las huellas;
  - el ensayo;
  - la migración y la verificación;
  - que la migración repetida se rechace;
  - la reversa, que vuelve exactamente al 1a (la verificación del 1a da otra vez 13 OK);
  - volver a migrar;
  - la carga real;
  - la consulta de los 35 pozos «0»;
  - las teselas reales;
  - un daño real sobre V85 y su epicrisis;
  - y que la reversa con datos se rechace.
- **Peso de las teselas a z15 en el centro (3×3):** acueducto máx. **29,8 KB**, alcantarillado máx. **37,1 KB**, frente al tope de 150 KB del plan. A z17 sobre V85 pesa 3,2 KB.
- **Edge simulada:** **66 de 66** (37 del 1b y 29 del Corte 2). Verificador de permisos: **0 errores**.
- **Chrome real a 390 px y en escritorio: 60 de 60.** La app compilada habla con las Edges reales en Deno, las RPC reales del PostGIS local con la carga completa y un Storage simulado. Usa WebGL con SwiftShader, la cámara falsa de Chrome y el GPS simulado.
- **Regresiones en la misma rama:** ficha del 1b **60 de 60**, Corte 0b **68 de 68**, áreas **51 de 51**, `tsc` y `npm run build`.

## Decisiones de esta sesión (de Code)
1. **Fotos:** de 1 a 6, al menos una «del daño», de 1,5 MB como máximo. Son parámetros.
2. **Ubicación del daño:**
   - con activo, el GPS del celular o, sin GPS, el punto del activo;
   - «no identificado», el punto que se toca en el mapa;
   - fuera de Valledupar, se guarda con una marca y nunca se rechaza.
3. **Tiempos:** la detección puede ser de hasta 7 días atrás. El orden debe ser inicio ≤ detectado ≤ inicio de la reparación ≤ restablecido, y nada en el futuro. Los tiempos de reparación van en `dano_tiempos`, como eventos.
4. **«Sector»** queda como texto libre opcional (`sector_texto`), porque todavía no hay activos SEC.
5. **Tipos:** dos tipos más de alcantarillado, que la maqueta no traía: «Tubo roto o colapsado» y la falla «Obstrucción». La rotura solo se pide en «Fuga» y «Válvula dañada».
6. **El reporte del bot que se convierte** toma la ubicación del reporte (o la del activo, si solo trae dirección), la hora de recepción como «detectado» y su descripción.
7. **La tesela** pasa por la Edge con el token. MapLibre la pide con `transformRequest`.
8. **La ficha cuenta los «hechos» reales** (daños, fallas e intervenciones) en vez de un 0 fijo. Es un ajuste al `26_lectura.sql` del 1a, que va en su paquete.

## Pospuesto
- **Corte 3:** «Guardar y registrar la reparación».
- **Corte 4:**
  - la bandeja «Reportes del bot» y sus rutas;
  - la lectura auditada del nombre del tercero;
  - las fotos firmadas de 60 s para el supervisor;
  - «asociar activo» en el daño no identificado.
- **Corte 9:** la propuesta de usuarios afectados según la topología.
- **Después de la fase 1:** la entrada de n8n.
- **Cuando Técnica la entregue:** la tabla de caudales de fuga.

## Riesgo por confirmar en el despliegue
La subida va con un `PUT` directo, con el cuerpo crudo, a la URL firmada de Storage. Supabase lo acepta, pero en local se probó contra un Storage simulado: se confirma en el celular con la primera foto.
