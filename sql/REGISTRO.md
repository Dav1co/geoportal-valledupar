# Registro de cambios del Tablero Comercial

## 🗺️ ESTADO DEL TABLERO — 10 construidas, 2 bloqueadas, 1 descartada

| # | Pantalla | Fuente | Estado |
|---|---|---|---|
| 1 | Resumen ejecutivo | agrupadas | ✅ construida |
| 2 | Facturación agrupado | facturacion_agrupado | ✅ construida |
| 3 | Recaudo agrupado | recaudo_agrupado | ✅ construida |
| 4 | Cartera agrupado | cartera_resumen | ✅ construida |
| 5 | Facturación detallado | facturacion_contratos | ✅ construida · con filtros |
| 6 | Recaudo detallado | recaudo_detalle | ✅ construida · con filtros |
| 7 | Cartera detallado | cartera_edades + cartera_contrato | ✅ construida · con filtros |
| 8 | PQR | reclamos + recursos | ✅ construida · con filtros |
| 9 | Notas | notas | ✅ construida · con filtros |
| 10 | Cupones | cupones_pagos | ✅ construida · con filtros |
| 11 | ~~Análisis del mes~~ | varias | ❌ **DESCARTADA** (ver abajo) |
| 12 | Consolidado | agrupadas | ✅ construida |
| 13 | Pérdidas e IPUF | — | 🔒 bloqueada: fuente sin identificar (agua producida, tarifa m³, metas IPUF; no sale del sistema comercial) |
| 14 | Recaudo diario | archivo de conciliaciones | 🔒 bloqueada: esperando el archivo. Borrador listo (tabla, cargador, vista comparada y 7 decisiones pendientes) |

### ❌ Pantalla 11 · Análisis del mes — DESCARTADA definitivamente

**No es un pendiente: se decidió no construirla.** Existía en el tablero viejo
porque **las demás páginas no tenían selector de período ni comparación**: hacía
falta una pantalla aparte para poder mirar un mes concreto y contrastarlo.

Eso ya no aplica. Cada pantalla responde lo suyo **para cualquier mes**, con
comparación contra el período que se elija, y **Consolidado** da la visión de
conjunto del año con todos los frentes cruzados. Reconstruirla sería duplicar
funcionalidad que hoy está mejor resuelta y repartida donde corresponde.

## 🎓 LECCIÓN DE MÉTODO — verificar entre vistas de la misma fuente NO prueba nada

**Las verificaciones cruzadas entre vistas que leen la MISMA tabla no detectan
errores del origen.** Si dos vistas comparten fuente, cuadrar entre ellas solo
prueba que la aritmética es consistente — nunca que el dato de entrada sea
correcto.

**Cómo se aprendió:** durante meses, `bi.v_facturacion_mes` y `bi.v_kpi_mes`
cuadraron al centavo en los 43 períodos. Ambas leen `facturacion_agrupado`, que
en 202309–202311 traía una **fila de totales sin etiqueta** sumada como si fuera
un concepto: duplicaba la facturación de esos meses (10.852 M contra 5.100 M
reales) y hundía el % de recaudo de 2023 de 78,6 % a 62,5 %. **Ninguna
verificación cruzada lo vio**, porque las dos vistas incluían la misma fila
fantasma. Se descubrió al mirar la SERIE LARGA en la pantalla Consolidado.

**Qué hacer en adelante:**
1. Verificar contra una **fuente genuinamente independiente** (otra tabla del
   origen), como ya se hace con cartera (`cartera_edades` vs `cartera_contrato`
   vs `cartera_resumen`) y con cupones vs recaudo diario.
2. Verificar contra el **archivo Excel original** cuando no exista otra tabla.
3. **Mirar la serie completa**, no solo el período de corte: los saltos
   interanuales delatan lo que ninguna verificación puntual ve.
4. Sospechar de cifras que sean **exactamente el doble o exactamente el 50 %**
   de lo esperado: es la firma de una fila de total colada en el detalle.


Bitácora corrida para auditar sin reconstruir de memoria. Cada entrada:
qué se creó, qué archivos se tocaron, decisiones de diseño y verificaciones.

Convenciones vigentes: todo anclado a `bi.v_ultimo_periodo` · ninguna vista de
`bi` con datos personales · conceptos siempre por número (`bi.f_concepto_num`,
nunca por nombre) · `consumo` solo es m³ en los conceptos 2 y 4 · toda gráfica
con tooltip y tabla plegable · "agrupado" sin panel de filtros, "detallado" con
panel contextual.

---

## ⚠ PENDIENTES EXTERNOS — lo que hay que pedir o resolver fuera del código

Ninguno es un fallo del tablero: son huecos o inconsistencias del dato de
origen. Se listan aquí para que no se pierdan entre pantallas.

| # | Qué | Detalle | A quién |
|---|---|---|---|
| 1 | **Detalle de recaudo de junio 2026** | `INFORME_RECAUDOS_DETALLADO_202606` no fue entregado (carga_log: 'faltante'); los otros ocho informes de recaudo de ese mes sí llegaron. Junio no tiene detalle diario y la pantalla 6 lo advierte. | sistemas |
| 2 | **22 conceptos sin ficha en la maestra de rutas** | Aparecen en los hechos pero no en `Ruta.xlsx`: familia EMD de suspensión/corte/reconexión (600, 602, 603, 605, 606, 95), excavaciones (609, 610), "VALORES DEJADO DE FACTURAR" (89) y AMB medición/accesorios con sus financiaciones (500, 505, 543, 546, 1502–1542). Hoy caen a la categoría de respaldo. Curioso: 500 y 505 faltan pero 501 y 506 sí están — parecen huecos reales, no basura. | contabilidad |
| 3 | **23 rutas normalizadas por el cargador** | `bi.conceptos_ruta` con `ruta_ajustada = true`: typo TERCEROS (1201, 1801), variante en minúsculas (17 conceptos) y sin ruta 0/vacía (86, 87, 1086, 1087). Listado: `select conccodi, concdesc, nueva_ruta, ruta_efectiva from bi.conceptos_ruta where ruta_ajustada order by conccodi;` | contabilidad |
| 4 | **Re-export de julio 2026** | El Excel del Drive da recaudo total $5.022,7 M y lo cargado $4.999,6 M; y los suscriptores superan en 373 a los del Power BI anterior (diferencia íntegra en Residencial estratos 1–3). Hipótesis: dos exportes del mismo informe en momentos distintos. **No ajustar** hasta confirmar. | área comercial |
| 5 | **Archivo diario de conciliaciones** | Bloquea la pantalla 14. Al llegar: verificar `Parent_Id` primero (riesgo de doble conteo) y resolver las 7 decisiones del borrador. | sistemas / banca |
| 6 | **Fuente de Pérdidas e IPUF** | Agua producida, tarifa m³ y metas IPUF; no sale del sistema comercial. Bloquea la pantalla 13. | área técnica |
| 7 | **Reclamos y recursos de julio 2026** | `RECLAMOS_202607` y `RECURSOS_202607` aparecen FALTANTE en el plan de cargue. Necesarios para la pantalla 8 (PQR). | sistemas |
| 9 | **🔴 INSTITUCIONAL — la comuna 2 desaparece de todo informe por comuna** | En el sistema comercial, los predios de la **comuna 2 no tienen comuna asignada**: los códigos presentes son 101, 103, 104, 105 y 106 — **el 102 nunca aparece**. Ocurre por igual en las dos fuentes, así que **es del origen (Acuo), no de un informe**: `cartera_edades` 32.815 filas sin comuna con **$14.119 M** (11,9 % de la cartera) y `cartera_contrato` 15.649 contratos sin COMMUNE con **$14.143 M** (11,9 %) — la misma plata vista por dos lados. **Evidencia del cruce contra el catastro georreferenciado**: los siete barrios más frecuentes sin comuna pertenecen TODOS a la comuna 2 (VILLA DEL ROSARIO 1.514 predios, DOCE DE OCTUBRE 1.454, CANDELARIA SUR 1.260, SIMON BOLIVAR 896, PANAMA 816, VILLA CLARA 753, VILLA CASTRO 652). **Consecuencia: hoy cualquier informe de EMDUPAR por comuna deja fuera $14.119 M y hace desaparecer una comuna entera.** | reportar a sistemas |
| 8 | **🔴 BLOQUEANTE — barrio y comuna mal mapeados en cartera_edades** | El cargador mapea `barrio ← DESUBGE1` y `comuna ← DESUBGE2`, pero en el archivo esos niveles son **país** ("COLOMBIA") y **municipio** ("VALLEDUPAR"). El barrio real está en **DESUBGE4** (342 valores: LA POPA, LA GRANJA, SIMON BOLIVAR, CENTRO…) y la comuna en **DESUBGE5** (COMUNA 1–6); DESUBGE3 es el departamento (CESAR). Hoy la tabla tiene un único valor de barrio en los 6 períodos, así que **la pantalla 7 no puede filtrar por barrio** hasta corregir el mapeo y recargar. Requiere aprobación (script de cargue). | decisión de David |

## 📓 Lectura de la bitácora de cargue (hechos.carga_log)

**Por qué `cartera_edades` y `cartera_contrato` entran siempre como 'parcial'.**
El cargador marca `parcial` cuando el Excel trae columnas que el diccionario de
sinónimos no mapea; no es un fallo, es "cargado con columnas ignoradas".
`cartera_contrato` ignora 27 columnas (UBICACION, DPTO, MUNICIPIO, MEJORA,
SUBSCRIBER_EMAIL, SUBSCRIPTION_ID, PRODUCT_TYPE, IS_PRIVATE…) y
`cartera_edades` ignora 11 (CICLDESC, CATEDESC, SUCADESC y los códigos
RECAUBGE1–5 con sus descripciones de nivel alto). Son columnas que el tablero
no necesita: **es esperable y no hay nada que corregir**.

⚠ **Consecuencia a tener presente:** estas dos fuentes **nunca alcanzarán
'cargado'**, así que ninguna lógica futura debe condicionarse a ese estado para
ellas. El ancla (`bi.v_ultimo_periodo`) no corre riesgo porque solo mira
`facturacion_agrupado`, `recaudo_agrupado` y `cartera_resumen`, y esas tres sí
llegan a `cargado` de forma sistemática (51, 44 y 44 veces respectivamente,
con un único `parcial` histórico en facturacion_agrupado). Si algún día una
vista dependiera del estado de las fuentes de detalle, hay que aceptar
`cargado` **y** `parcial`, o mejor: mirar si hay filas del período.

**El error del 8-ago-2026 21:27 en cartera_contrato 202607.**
Mensaje: *"Can't reconnect until invalid transaction is rolled back"*
(SQLAlchemy), lanzado dentro de `insertar()`. Es una **desconexión del pooler
en medio de la inserción** de un archivo grande: la conexión quedó en
transacción inválida y el siguiente uso falló en vez de reconectar. El cargador
ya contempla el caso — hace `dispose()` del pool para que el fallo de una fuente
no contamine las siguientes — y el reintento cargó bien. **Es transitorio, no
hay dato perdido**; si se repitiera con frecuencia, la vía sería subir
`pool_recycle` o partir el archivo, no cambiar la lógica.

## ✉️ Reporte a sistemas — LISTO PARA COPIAR A UN CORREO

> **Asunto: predios sin comuna asignada en el sistema comercial — la comuna 2 no aparece en ningún informe**
>
> Al construir el tablero comercial detectamos que **los predios de la comuna 2
> no tienen comuna asignada en el sistema comercial**. En los informes, los
> códigos de comuna que aparecen son 101, 103, 104, 105 y 106; **el 102 no
> aparece nunca**, y en su lugar queda un bloque de registros con la comuna en
> blanco.
>
> **El hallazgo no viene de un informe puntual, sino de dos informes de
> estructura distinta que coinciden:**
>
> | Informe | Registros sin comuna | Cartera involucrada | % del total |
> |---|---|---|---|
> | Cartera general por edades | 32.815 filas | $14.119 millones | 11,9 % |
> | Cartera a nivel de contrato | 15.649 contratos | $14.143 millones | 11,9 % |
>
> Que dos reportes con grano y estructura diferentes arrojen **el mismo 11,9 %**
> y **la misma comuna ausente** indica que el vacío está en el dato de origen y
> no en la generación de un informe.
>
> **Verificación contra el catastro georreferenciado del municipio:** los
> barrios que aparecen sin comuna pertenecen, todos, a la comuna 2:
>
> | Barrio | Comuna según catastro | Predios |
> |---|---|---|
> | Villa del Rosario | 2 | 1.514 |
> | Doce de Octubre | 2 | 1.454 |
> | Candelaria Sur | 2 | 1.260 |
> | Simón Bolívar | 2 | 896 |
> | Panamá | 2 | 816 |
> | Villa Clara | 2 | 753 |
> | Villa Castro | 2 | 652 |
>
> **Impacto:** cualquier informe de EMDUPAR desagregado por comuna está dejando
> por fuera $14.119 millones de cartera y omitiendo una comuna completa del
> análisis. Esto afecta la focalización de cobranza, los reportes a entes de
> control y cualquier decisión que se tome mirando el territorio.
>
> **Solicitud:** completar la asignación de comuna de los predios de la comuna 2
> en el sistema comercial. Mientras tanto, el tablero completa el dato cruzando
> por barrio contra el catastro y lo marca como valor inferido, pero es una
> solución de contingencia: el dato debe quedar correcto en el origen.

## 🟢 A EVALUAR PRONTO · Tabla barrio → comuna derivada del catastro

**Cobertura medida, y es alta: vale la pena hacerla.**

| | |
|---|---|
| Barrios distintos en cartera | 372 |
| **Con comuna hallada en el catastro** | **308 — 83 %** |
| **Filas sin comuna que se podrían completar** | **29.312 de 30.995 — 95 %** |
| **Cartera que se recupera para el análisis por comuna** | **$13.979 M de $14.073 M — 99,3 %** |

El 83 % de cobertura por nombre de barrio se traduce en **95 % de las filas** y
**99,3 % de la plata**, porque los barrios que faltan son pequeños: solo **8 sin
equivalencia**, todos conjuntos cerrados recientes (ARGENTINA/BRASIL/CHILE -
CONJUNTO LAS AMERICAS, CONJUNTO CADIZ, CONJUNTO MONTE CARLO, CONJUNTO VIVE
ALTO, CONDOMINIO SOL, SAO PABLO) que el catastro aún no tiene con ese nombre.

Es decir: una tabla de equivalencia derivada del catastro **repara el hueco
institucional de la comuna 2 sin depender de que Acuo lo corrija**, y deja el
análisis territorial por comuna prácticamente completo. Implementación
sugerida: vista materializada `bi.v_barrio_comuna` con la comuna dominante por
barrio (la de más predios en el catastro), y `coalesce(comuna_origen,
comuna_catastro)` en el preagregado, marcando cuál se usó para que sea auditable.

## Pendiente propio · Equivalencia barrio de cartera ↔ capa del mapa

**No abordar ahora.** Diagnóstico hecho para que se retome con criterio.

Al comparar los nombres de barrio de `cartera_edades` (DESUBGE4) contra la capa
`public.barrios_valledupar` del geoportal: **372 barrios en cartera, 492 nombres
en la capa (571 polígonos), y solo 142 coinciden — el 38 %**.

**La diferencia NO es ruido arbitrario, y eso define cómo se resolvería:**
- **La relación es de MUCHOS A UNO, no uno a uno**: cartera desagrega en
  urbanizaciones lo que la capa tiene como un solo barrio
  (`ALTOS DE ZIRUMA 1…6` → `ALTOS DE ZIRUMA`;
  `ARGENTINA - CONJUNTO LAS AMERICAS` → `ARGENTINA`).
- Se suman **diferencias de grafía** (`AREMASAI` / `AREMASSAIN`,
  `BELLA VISTA` / `BELLAVISTA I`).
- Por eso buena parte del emparejamiento **se puede automatizar por patrón de
  sufijos** (numerales romanos y arábigos, " - CONJUNTO …", etapas), dejando
  manual solo el residuo.

**⚠ VÍA A EVALUAR PRIMERO, puede volver innecesaria la tabla de equivalencias:**
el catastro georreferenciado tiene **119.779 predios con su contrato**, así que
la cartera puede llegar al mapa **por contrato**, no por nombre de barrio.
Cruzar por identificador siempre es mejor que cruzar por texto — la misma regla
que ya se aplica para no cruzar por dirección. Evaluar esa ruta antes de
invertir en emparejar cadenas.

## Modo Dashboard — acceso (Entrega 1)

- **BD:** columna `ver_dashboard` en `public.geoportal_lista_blanca`; ramas
  nuevas en `geoportal_puede`, `geoportal_mis_permisos`, `geoportal_admin_permisos`
  (aplicadas por David en el editor).
- **Archivos:** `sql/04_acceso.sql` · enganches mínimos en `src/App.tsx`,
  `src/components/Admin.tsx`, `src/lib/api.ts` · `geoportal-admin/index.ts`
  (+`p_dashboard`).
- **Decisión:** el modo se gatea igual que los otros cuatro; `_shared/auth.ts`
  nunca se toca (obligaría a redesplegar las 12 funciones existentes).

## Capa 0 y Capa 1

- **BD:** esquemas `bi` y `bi_interno`; funciones `bi.f_num`, `bi.f_fecha`,
  `bi.f_concepto_num`; vista `bi.v_ultimo_periodo`; vistas de casting
  `bi_interno.v_facturacion_agrupado`, `v_recaudo_agrupado`, `v_cartera_resumen`,
  `v_notas`, `v_facturacion_contratos`, `v_cartera_contrato`.
- **Archivos:** `sql/01_capa0.sql`, `sql/02_capa1_resumen.sql`.
- **Decisiones:** `f_num` se reescribió como SQL puro (inlineable) — en plpgsql
  costaba ~23 s al evaluarse 7,2 M de veces. El ancla exige estado `'cargado'`
  estricto: un mes `'parcial'` no ancla.
- **⚠ `bi` es un esquema COMPARTIDO** con seis vistas preexistentes del
  geoportal, algunas con PII (`bi.v_cartera_contrato`). Protección en dos capas:
  permisos + lista cerrada del RPC. Nunca agregar una vista a la lista sin
  revisar sus columnas; nunca "limpiar" `bi`.

## Pantalla 1 · Resumen ejecutivo

- **BD:** `bi.v_kpi_mes` (MATERIALIZADA, índice único `v_kpi_mes_periodo_ux`),
  `bi.v_kpi_anio`; índices parciales `facturacion_contratos_c1_ix` y
  `cartera_contrato_con_saldo_ix`.
- **Archivos:** `sql/03_v_kpi.sql` · `src/dashboard/` (Dashboard, Resumen,
  SelectorPeriodo, tipos, formato, dashboard.css).
- **Decisiones:** materializada porque la consulta en vivo tardaba 26 s;
  con índices parciales + `f_num` inlineable bajó a 2,8 s de refresco y 0,1 ms
  de lectura. `v_kpi_anio` acumula por período (no hasta el ancla) y es la única
  fuente del "% del año" — el frontend no acumula.
- **Verificado:** tramos de recaudo cuadran al centavo con el Excel fuente.

## Pantalla 2 · Facturación agrupado

- **BD:** `bi.v_facturacion_mes`, `bi.v_facturacion_servicio`,
  `bi.v_facturacion_ruta`, `bi.v_tarifa_referencia` (MATERIALIZADA, solo ancla).
- **Archivos:** `sql/08_facturacion.sql` · `src/dashboard/paginas/FacturacionAgrupado.tsx`
  · `src/dashboard/graficas.tsx`.
- **Decisiones:** cadena bruta → déficit → neta; la dona suma la neta porque
  los conceptos 26–33 rutean a su servicio. Tarifa por MODA (no mínimo: un
  cargo prorrateado por retiro no debe arrastrarla) y solo del período ancla.
- **Verificado:** `neta = v_kpi_mes.facturado` en los **43 períodos, 0 descuadres**
  (202607: 5.983.961.190,61). Tarifas del ancla: 6.506,91 · 1.313,11 ·
  3.107,55 · 1.414,88, `valores_distintos = 1` en los cuatro.
- **Hallazgo:** Acuo factura los conceptos 1–4 a **tarifa plena única** para
  todos los estratos y usos; toda la progresividad vive en los conceptos 26–33.

## Pantalla 3 · Recaudo agrupado

- **BD:** `bi.v_recaudo_mes`, `bi.v_recaudo_servicio`, `bi.v_recaudo_ruta`,
  `bi.v_fact_vs_recaudo_servicio`. RPC `geoportal_bi_consulta` ampliado a 10
  vistas (grants restablecidos tras el `create or replace`).
- **Archivos:** `sql/09_recaudo.sql`, `sql/05_rpc_puente.sql` ·
  `src/dashboard/paginas/RecaudoAgrupado.tsx` · `LineasPorcentaje` en `graficas.tsx`
  · lista cerrada de `geoportal-bi/index.ts`.
- **Decisiones:** los % sobre facturado NO se redefinen — vienen de `v_kpi_mes`
  y `v_kpi_anio`. La evolución del mix va en **líneas con eje ajustado**, no en
  barras apiladas al 100 %: el mix se mueve en banda estrecha (corriente
  80,1 %–88,1 % en 43 períodos) y el apilado lo aplastaría. La tabla
  facturado-vs-recaudado lleva la advertencia ARRIBA (un servicio puede superar
  el 100 % con mora vieja).
- **Verificado:** 0 divergencias contra `v_kpi_mes`; los tres tramos suman el
  total en los 43 períodos; composición del ancla 86,1 / 10,6 / 3,3.

## Pantalla 4 · Cartera agrupado

- **BD:** `bi.v_cartera_mes`, `bi.v_cartera_tramo`, `bi.v_cartera_servicio`,
  `bi.v_cartera_ruta`. Ampliada `bi_interno.v_cartera_resumen` con las 14
  cubetas de edad (autorizado: completar Capa 1 es libre; quitar o renombrar
  columnas no). RPC ampliado a 14 vistas; `geoportal-bi` desplegada.
- **Archivos:** `sql/10_cartera.sql`, `sql/02_capa1_resumen.sql`,
  `sql/05_rpc_puente.sql` · `src/dashboard/paginas/CarteraAgrupado.tsx`.
- **HALLAZGO ESTRUCTURAL:** `cartera_total = no financiada + financiada`. Las
  cubetas de edad cubren SOLO la no financiada; su suma nunca iguala el total y
  eso no es un error. La brecha crece con los años (4,3 % en 2023 → 8,4 % en
  2026): la financiación de deuda gana peso. La pantalla lo explica en un aviso
  y expone las dos piezas por separado.
- **Verificado contra DOS fuentes independientes:** la financiada implícita
  (total − cubetas) vs `cartera_contrato.saldo_financiado` — desviación estable
  de −0,07 % en los 6 períodos retenidos (202607: 10.021 M vs 10.028 M); y el
  total vs `cartera_edades` — 118.840 M exacto. Además: 0 descuadres contra
  `v_kpi_mes`, partes = total y tramos = total en los 43 períodos.
- **Composición del ancla:** > 360 días **79,6 %** (94.547 M) · financiada 8,4 %
  · 180–360 5,7 % · 60–180 4,4 % · hasta 60 2,0 %.
- **Decisión de diseño:** los tramos usan rampa secuencial de un tono (la edad
  es magnitud ordenada) y la financiada un tono aparte, porque no pertenece a
  ese orden. La serie de deterioro va en líneas con eje ajustado.

## Pantalla 5 · Facturación detallado — primera con panel de filtros

- **BD:** `bi.v_fact_detalle_dim` (MATERIALIZADA, 33.320 filas; índice único
  `v_fact_detalle_dim_ux` + índice por período). RPC ampliado a 15 vistas;
  `geoportal-bi` desplegada.
- **Archivos:** `sql/11_fact_detalle.sql`, `sql/05_rpc_puente.sql` ·
  `src/dashboard/PanelFiltros.tsx` (pieza reutilizable) ·
  `src/dashboard/paginas/FacturacionDetallado.tsx` · `BarrasHorizontales` en
  `graficas.tsx`.
- **ARQUITECTURA de las "detallado"** (aplica a 6 y 7):
  · Preagregado por dimensiones filtrables, NO materialización por combinación
    de filtros. Cardinalidad medida: 249 combinaciones de dimensiones, 5.700
    con concepto, por período.
  · UNA llamada por período (~972 KB de JSON, ~5.700 filas); el filtrado ocurre
    en el navegador. Solo se reconsulta al cambiar de período.
  · El panel declara sus filtros; el de estrato solo aparece con uso
    Residencial (en el resto la subcategoría es el diámetro de acometida). Al
    ocultarse un filtro su valor se limpia.
- **Verificado:** sumabilidad exacta contra las cifras oficiales del ancla
  (111.579 · 110.039 · 1.700.852 m³ · 1.631.457 m³) y **diferencia 0,00 en los
  6 períodos** contra `bi.v_facturacion_mes`, que sale de `facturacion_agrupado`
  — otra tabla.
- **Nota de construcción:** la materializada tardó 4:14 y excede tanto el
  límite del editor web como el del endpoint HTTP (2 min). Se creó con `psql`
  directo y `set statement_timeout='30min'`. `count(distinct contrato)` es
  obligatorio: hay 447 pares contrato-concepto repetidos en el ancla, así que
  `count(*)` inflaría el conteo.
- **PENDIENTE (requiere aprobación):** agregar `bi.v_fact_detalle_dim` a
  `VISTAS_TABLERO` en `cargar_hechos.py` para que se refresque tras cada cargue.

## Pantalla 6 · Recaudo detallado — y el recaudo diario que faltaba

- **BD:** `bi.v_recaudo_diario` (MATERIALIZADA, 181 filas),
  `bi.v_recaudo_detalle_dim` (MATERIALIZADA, 13.414 filas),
  `bi.v_concepto_mapa` (vista, 631 filas: concepto → ruta → servicio,
  reutilizable por cualquier pantalla). RPC a 18 vistas; función desplegada.
- **Archivos:** `sql/12_recaudo_detalle.sql`, `sql/05_rpc_puente.sql` ·
  `src/dashboard/paginas/RecaudoDetallado.tsx` · `LineasPorDia` en
  `graficas.tsx` · `Resumen.tsx` (placeholder reemplazado por la curva real).
- **Verificado:** diferencia **0,00 % en los 6 períodos** contra
  `bi.v_recaudo_mes`, que sale de `recaudo_agrupado` — otra tabla; y coherencia
  interna sin descuadres entre las dos materializadas.
- **⚠ HUECO DE DATOS:** falta el período **202606**. El archivo
  `INFORME_RECAUDOS_DETALLADO_202606` no fue entregado (carga_log: 'faltante',
  "No se encontro archivo con el patron"); los otros ocho informes de recaudo de
  junio sí llegaron. Junio 2026 no tiene detalle diario y la pantalla lo dice en
  vez de mostrar un mes vacío. **Pendiente: pedirlo a sistemas.**
- **Notas de la fuente:** `recaudo_detalle` NO trae ciclo, uso ni estrato (solo
  contrato, concepto, valor y fechas), así que el panel filtra por servicio y
  concepto. Su campo `concepto` trae el número puro ("1"), no el formato
  "1- CARGO FIJO" de las demás tablas. Cruzar contra `facturacion_contratos`
  para obtener ciclo/uso exigiría un join de 6,6 M × 7,2 M: queda propuesto,
  no prometido.
- **Hallazgo operativo:** patrón semanal marcado — martes es el día más fuerte
  (5.786 M acumulados) y domingo el más flojo (1.045 M); el fin de semana
  concentra apenas el 12 % del recaudo.
- **PENDIENTE (requiere aprobación):** sumar `bi.v_recaudo_diario` y
  `bi.v_recaudo_detalle_dim` a `VISTAS_TABLERO` en `cargar_hechos.py`.

## Pantalla 14 · Recaudo diario — BLOQUEADA (no perder de vista)

Comparación día a día del mes EN CURSO contra los meses anteriores al mismo día
de corte. Bloqueada hasta conseguir el **archivo diario de conciliaciones
bancarias**. Borrador ya hecho: tabla `hechos.recaudo_diario`,
`~/etl-emdupar/cargar_recaudo_diario.py`, vista `bi.v_recaudo_diario_comparado`
con la regla del mismo corte, y la lista de **7 decisiones pendientes** — la
primera, verificar `Parent_Id` por el riesgo de doble conteo. Criterio ya
fijado: el diario se conserva aunque llegue el cierre mensual, para comparar
preliminar contra definitivo.

**⚠ OJO CON LOS NOMBRES, se parecen y son fuentes distintas:**
| Objeto | Fuente | Qué cubre | Estado |
|---|---|---|---|
| `bi.v_recaudo_diario` | `hechos.recaudo_detalle` (cierre mensual) | días de meses ya cerrados | **existe** |
| `hechos.recaudo_diario` | archivo bancario diario | el mes en curso, antes del cierre | borrador sin datos |
| `bi.v_recaudo_diario_comparado` | la tabla anterior | pantalla 14 | borrador |

La pantalla 14 no queda cubierta por la 6: la 6 solo puede mostrar meses
cerrados, y el valor de la 14 es justamente ver el mes en curso.

## Pantalla 7 · Cartera detallado — con territorio

- **BD:** `bi.v_cartera_detalle_dim` (MATERIALIZADA, ~2.750 filas/período),
  `bi.v_cartera_contratos_dim` (458 filas/período), `bi.v_barrio_comuna`
  (vista, 372 barrios). RPC a 20 vistas; función desplegada.
- **Archivos:** `sql/13_cartera_detalle.sql`, `sql/05_rpc_puente.sql` ·
  `src/dashboard/paginas/CarteraDetallado.tsx` · `PanelFiltros.tsx` (búsqueda
  sobre opciones, propiedad `buscable`).
- **Precedida por la CORRECCIÓN DEL MAPEO GEOGRÁFICO y la recarga de 6
  períodos** (12 archivos, ~515 MB, sin errores). Resultado: de 1 barrio
  constante a **359–373 barrios reales** por período.
- **Verificado que las cifras NO se movieron** (la corrección era solo
  geográfica): julio sigue en **$118.840.448.654,36** en `cartera_edades` y
  `cartera_contrato`, y **113.823 contratos distintos** — idénticos a lo medido
  antes de recargar. Las 113.958 filas vs 113.823 contratos son duplicados
  preexistentes, no un cambio.
- **CORRECCIÓN DE UN SUPUESTO MÍO:** creía que `cartera_edades.total` era la
  cartera no financiada. Es la **cartera TOTAL**; los **tramos de edad** son la
  no financiada, y su diferencia es la financiada. Verificado al peso en los 6
  períodos contra `bi.v_cartera_mes` (202607: total 118.840 M = 118.840 M,
  tramos 108.819 M = 108.819 M, financiada 10.021 M = 10.021 M). La pantalla
  aprovecha esto para mostrar **la financiada por barrio**, que ninguna otra
  fuente permite.
- **Comuna completada desde el catastro:** 88,1 % de la cartera trae comuna del
  sistema comercial, **11,8 % ($13.979 M) se completa desde el catastro** y
  0,1 % queda sin dato. La pantalla lo advierte en un aviso, no fila por fila.
  La comuna 2 ya aparece en el tablero.
- **Decisiones de diseño:** el filtro de barrio se acota a la comuna **y** tiene
  búsqueda por nombre (con ~350 opciones, la jerarquía sola no basta);
  "Contratos con deuda" se apaga al filtrar por territorio porque
  `cartera_contrato` no tiene barrio y una cifra aproximada engañaría; la tabla
  de foco de cobranza ordena por **monto** de deuda vieja, no por porcentaje.
- **PENDIENTE (requiere aprobación):** sumar `bi.v_cartera_detalle_dim` y
  `bi.v_cartera_contratos_dim` a `VISTAS_TABLERO` en `cargar_hechos.py`
  (dependen de `cartera_edades` y `cartera_contrato`).

## Pantalla 8 · PQR — y el ESTÁNDAR DE HUECOS del tablero

- **BD:** `bi.v_periodos_fuente` (mapa de huecos: qué períodos tiene cada una de
  las 12 fuentes), `bi.v_pqr_mes`, `bi.v_pqr_dim`. RPC a 23 vistas; desplegada.
- **Archivos:** `sql/15_pqr.sql` · `src/dashboard/SinDatos.tsx` (pieza
  reutilizable) · `paginas/Pqr.tsx` · `SelectorPeriodo.tsx` (marca "(sin
  datos)") · `Dashboard.tsx` (cada pantalla declara su fuente).
- **Períodos disponibles:** 17 (202501–202606). **Faltan 202506 y 202607** —
  este último es el ancla, así que la pantalla nace SIN el mes de corte y lo
  dice explícitamente.
- **Verificado:** serie vs preagregado sin descuadres; totales contra la tabla
  cruda (11.031 reclamos, 846 recursos) exactos; sin PII (el único match de la
  búsqueda es `contratos_reclamantes`, que es un CONTEO).
- **Corrección sobre la marcha:** el filtro de "resuelto" no encontraba nada
  porque los estados reales de Acuo son **"14 - Atendido", "13 - Registrado" y
  "36 - En anulación"** — no existen "resuelto"/"cerrado". Ahora el KPI es
  % atendidos (67,8 % en 202606) y se distingue lo pendiente de lo anulado.

## Pantalla 9 · Notas

- **BD:** `bi.v_notas_mes`, `bi.v_notas_dim`, `bi.v_notas_vs_pqr` (todas EN
  VIVO; la fuente son 296.823 filas). RPC a 26 vistas; desplegada.
- **Archivos:** `sql/16_notas.sql` · `src/dashboard/paginas/Notas.tsx`.
- **Fuente histórica completa:** 43 períodos (202301–202607), **con el ancla
  incluida** — a diferencia de PQR.
- **Verificado:** el neto mensual coincide con `bi.v_kpi_mes.notas_valor`
  (calculado por separado en 03_v_kpi.sql) sin descuadres en los 43 períodos;
  serie vs preagregado exacto; y los signos correctos en todos los períodos
  (crédito negativo, débito positivo). 202607: −183.621.095,30.
- **Qué mide, y por qué importa:** las notas son ajustes a lo YA facturado, así
  que su volumen es una medida directa de la calidad del ciclo comercial. En
  202607, dos causales concentran casi todo el monto: **59-Recargo Moratorio
  (−163,6 M)** y **6-Corrección de Consumos y Lecturas (−22,3 M)**, sobre 578
  contratos afectados.
- **Decisión de diseño:** las barras muestran el crédito **en positivo** para
  poder dimensionarlo; la tabla conserva el signo original del sistema. Las
  causales se ordenan por monto absoluto, no por cantidad: pocas notas de alto
  valor pesan más que muchas pequeñas.
- **Cruce notas ↔ PQR (indicador C4):** implementado como serie mensual, con un
  aviso explícito de que muestra **co-ocurrencia, no causalidad**. No se
  emparejan causales por texto porque los catálogos son distintos; el cruce
  real exigiría contrato + fecha, y queda anotado como trabajo aparte.

## Pantalla 12 · Consolidado (pantalla de ANÁLISIS)

- **BD:** `bi.v_consolidado_mes`, `bi.v_consolidado_anio` (en vivo). RPC a 30
  vistas; desplegada. **No reimplementa nada**: consume las vistas de cada
  pantalla especializada, así que no puede divergir de ellas.
- **Archivos:** `sql/18_consolidado.sql` · `paginas/Consolidado.tsx` ·
  `formato.ts` (`fmtPesosCompleto`, `fmtEnteroCompleto`, `fmtDeltaPct`).
- **Verificado:** las cuatro columnas contra su pantalla especializada
  (facturado vs `v_facturacion_mes`, recaudo y corriente vs `v_recaudo_mes`,
  cartera vs `v_cartera_mes`, notas y cupones vs las suyas) — **cero descuadres**.
- **FORMATO:** cifras completas sin abreviar ($ 5.983.961.190,61), formato es-CO
  con miles en punto y decimales en coma, alineadas a la derecha con cifras
  tabulares. La abreviación se queda solo en las tarjetas de KPI de las otras
  pantallas. Motivo: esta pantalla se copia a Excel para informes de gerencia.
- **Bloque 1 · Tendencia por vigencia:** facturado, recaudo, % recaudo,
  corriente vs recuperación, cartera al cierre, crecimiento anual y rotación.
  La serie quedó **78,6 → 78,9 → 81,0 → 83,6** (tras corregir la fila fantasma).
- **Bloque 2 · Matriz mensual:** 12 filas × 14 columnas con todos los frentes,
  más una tabla de variación contra el mismo mes del año anterior.
- **Indicadores nuevos que solo tienen sentido con la serie completa:**
  · **Rotación de cartera** = cartera ÷ facturación mensual (a cuántos meses de
    facturación equivale la deuda): pasó de **18,66 en 2023 a 20,21 en 2026**.
  · Crecimiento de cartera mes a mes y anual.
  · Cobertura (% recaudo) en serie.
  · **Ticket de facturación** (facturado ÷ contratos facturados) y **ticket de
    pago** (valor cupones ÷ cupones): miden cosas distintas — cuánto se le cobra
    a cada suscriptor vs cuánto paga la gente por transacción. Ambos necesitan
    detalle (6 períodos): fuera de esa ventana van marcados **sin dato**.
- **El % de recaudo interanual se compara en puntos porcentuales**, no en
  variación porcentual: de 80 % a 84 % son 4 puntos, no 5 % de mejora.

## Pantalla 10 · Cupones (canales de recaudo)

- **BD:** `bi.v_cupones_mes`, `bi.v_cupones_canal` (en vivo). RPC a 28 vistas;
  desplegada. Fuente: `cupones_pagos`, detalle con retención de 6 períodos
  (~78.000 cupones/mes).
- **Archivos:** `sql/17_cupones.sql` · `src/dashboard/paginas/Cupones.tsx`.
- **VERIFICACIÓN NOTABLE:** el valor de cupones coincide con el recaudo diario
  (`v_recaudo_diario_cierre`, que sale de `recaudo_detalle` — otra tabla) al
  **0,0 % en todos los períodos comparables**. Es decir: **todo el recaudo entra
  por cupones**, y las dos fuentes se validan mutuamente. (202606 no compara
  porque falta el detalle de recaudo de ese mes — el hueco ya documentado.)
- **Hallazgos operativos del ancla:**
  · **SUPER GIROS concentra el 46,4 %** del recaudo (39.930 cupones) y BBVA el
    31,4 %; EFECTY 8,8 % y Davivienda 5,3 %. El grueso no entra por bancos sino
    por corresponsales.
  · **Rezago de conciliación:** la mayoría concilia en **menos de un día**
    (SUPER GIROS 0,45 · BBVA 0,58), pero **Banco de Bogotá tarda 17,15 días** y
    Bancolombia 23. Es plata ya pagada por el usuario que sigue figurando como
    deuda mientras tanto.
  · **Ticket mediano ($42.025) muy por debajo del promedio ($64.070)**: unos
    pocos pagos grandes elevan la media, así que la mediana describe mejor al
    usuario típico. La pantalla muestra ambos.
- **Decisión de diseño:** el rezago por entidad se pondera por número de
  cupones, no se promedian los promedios de cada agencia — si no, una agencia
  con 4 cupones pesaría igual que otra con 40.000.

### ESTÁNDAR DE HUECOS (aplica a las 12 pantallas)

Los huecos son la norma en estos archivos, no la excepción: junio 2026 sin
detalle de recaudo, 202506 y 202607 sin PQR, reclamos solo desde 2025.

1. **Si el período elegido no tiene datos**, la pantalla dice qué falta, desde
   cuándo hay datos, cuál es el último disponible y cuántos meses faltan en
   medio — con un botón para saltar al último. Nunca pantalla en blanco ni un
   cero que parezca real (`SinDatos`).
2. **El selector marca "(sin datos)"** los períodos que la pantalla activa no
   puede mostrar: cada pantalla declara su fuente y `bi.v_periodos_fuente` dice
   qué tiene realmente.
3. **Las series distinguen cero de sin dato**: se recorre el calendario completo
   y los meses sin archivo quedan en `null`, así la gráfica dibuja **hueco, no
   punto en cero**. Un aviso explica que esos huecos son meses sin archivo, no
   meses sin actividad (`AvisoHuecos`).

**Auditoría de las pantallas anteriores:** 4 incumplían (Resumen, Facturación
agrupado, Recaudo agrupado, Cartera agrupado decían solo "No hay datos para X")
y 3 eran parciales (las detalladas explicaban la retención pero no el rango
disponible). **Las 7 quedaron migradas a `SinDatos`.**

## Refresco INCREMENTAL por período (sql/14_incremental.sql)

- **Qué cambió:** las cinco preagregadas de detalle pasaron de vista
  materializada a **TABLA** con función de recálculo por período.
  `v_kpi_mes` y `v_tarifa_referencia` siguen siendo materializadas.
  **Los nombres no cambiaron**, así que RPC, Edge Function y frontend intactos.
- **Por qué:** Postgres no permite refrescar parcialmente una materializada
  (no existe `REFRESH … WHERE`, ni se pueden particionar). Con retención de 6
  períodos, cargar un mes obligaba a recalcular cinco que no se movieron.
- **Funciones creadas:** `bi.recalcular_<tabla>(p_periodo)` para cada una, más
  el despachador `bi.recalcular(tabla, periodo)` — CASE cerrado, sin SQL
  dinámico, que además borra los períodos que la retención ya eliminó de la
  fuente (evita huérfanos).
- **Atomicidad:** `delete + insert` en transacción; por MVCC quien consulta
  durante el recálculo ve la versión anterior hasta el commit — misma garantía
  que `REFRESH … CONCURRENTLY`.
- **Tiempos MEDIDOS del recálculo de un período:** v_fact_detalle_dim 52 s ·
  v_recaudo_detalle_dim 41 s · v_recaudo_diario_cierre 34 s ·
  v_cartera_detalle_dim 31 s · v_cartera_contratos_dim 5 s = **2,7 min**,
  contra ~17 min de refrescarlas completas. **Cargue mensual: de ~18 a ~3,5 min.**
- **Verificado al peso, sin desviación:** cartera 118.840.448.654,36 · facturado
  5.983.961.190,61 · recaudo 5.022.724.833 · suscriptores 111.579 y 110.039 ·
  filas 33.320 / 181 / 13.414 / 16.100 / 2.759. Idénticas antes de convertir,
  después de convertir y después de recalcular. Sincronía fuente-vs-tabla: cero
  filas de diferencia.

### 🛟 RECONSTRUCCIÓN TOTAL — probada, no solo escrita

Red de seguridad si una tabla queda desincronizada. **Probada** sobre
`v_cartera_contratos_dim`: reconstruyó los 6 períodos en **34 s** y devolvió
exactamente las mismas 2.759 filas y los mismos $118.840.448.654,36.

Comando exacto (psql, no el editor web — puede tardar minutos):

```bash
cd ~/etl-emdupar && export $(grep SUPABASE_DB_URL_GEOPORTAL .env | xargs)
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL_GEOPORTAL" \
  -c "set statement_timeout='30min'" -c "
do \$\$
declare p text; n integer;
begin
  -- cambiar la tabla y su fuente segun lo que haya que reconstruir:
  --   bi.v_fact_detalle_dim      <- hechos.facturacion_contratos
  --   bi.v_recaudo_diario_cierre <- hechos.recaudo_detalle
  --   bi.v_recaudo_detalle_dim   <- hechos.recaudo_detalle
  --   bi.v_cartera_detalle_dim   <- hechos.cartera_edades
  --   bi.v_cartera_contratos_dim <- hechos.cartera_contrato
  for p in select distinct periodo from hechos.cartera_contrato order by 1 loop
    n := bi.recalcular('bi.v_cartera_contratos_dim', p);
    raise notice '% -> % filas', p, n;
  end loop;
end \$\$;"
```

**Verificación de sincronía** (debe devolver CERO filas) — está completa al pie
de `sql/14_incremental.sql`:

```sql
select 'v_fact_detalle_dim' tabla, periodo from (
  select distinct periodo from hechos.facturacion_contratos
  except select distinct periodo from bi.v_fact_detalle_dim) x
union all select 'v_recaudo_detalle_dim', periodo from (
  select distinct periodo from hechos.recaudo_detalle
  except select distinct periodo from bi.v_recaudo_detalle_dim) x
union all select 'v_cartera_detalle_dim', periodo from (
  select distinct periodo from hechos.cartera_edades
  except select distinct periodo from bi.v_cartera_detalle_dim) x
union all select 'v_cartera_contratos_dim', periodo from (
  select distinct periodo from hechos.cartera_contrato
  except select distinct periodo from bi.v_cartera_contratos_dim) x;
```

## Auditoría de consumo de la API (carga bajo demanda y permisos)

- **Archivos:** `src/dashboard/cacheBi.ts` (nuevo) · las 5 páginas y
  `Dashboard.tsx` pasan a usar `biCache` · `src/App.tsx` (guard de montaje).
- **Hallazgo corregido:** el montaje del Dashboard dependía solo de `modo`; la
  salvaguarda que devuelve a Explorar vive en un `useEffect` del padre y en
  React los efectos de los hijos corren ANTES que los del padre — es decir, un
  estado forzado habría disparado las llamadas y solo después habría corregido
  el modo. Ahora el render exige `modo === "dashboard" && puedeVerDashboard`:
  sin permiso el componente no llega a montarse y no hay llamada que rechazar.
- **Carga bajo demanda:** ya lo era (cada página consulta en su propio efecto y
  solo se monta si es la pestaña activa), pero al volver a una pestaña se
  remontaba y reconsultaba. `biCache` cachea a nivel de módulo — sobrevive al
  desmontaje de pantallas y del modo — con clave `vista|filtros`, así que un
  período distinto trae datos nuevos por construcción. Cachea la PROMESA (dos
  pantallas concurrentes comparten una llamada) y borra la entrada si falla,
  para que "Reintentar" reintente de verdad.
- **Frescura del caché — dos mecanismos complementarios:** vencimiento de 30
  min (cubre a quien deja el tablero abierto durante un cargue y no sabe que
  hubo uno) y botón "↻ Actualizar" en el encabezado (cubre a quien SÍ lo sabe y
  no quiere esperar). El botón vacía el caché e incrementa `recarga`, que va
  como `key` de la pantalla activa: la remonta y vuelve a pedir sin necesidad
  de tocar cada página.
