# Técnica · fase 1 · Corte 3b — La ficha del activo como «perfil» — INFORME

Fuente: §22 y §23 de la bitácora; `01_modelo_propuesto.md` §A.2 y §A.3; la maqueta `Ficha.dc.html`.
**Nada se aplicó en Supabase.** Todo se probó en local, en PostgreSQL 17 + PostGIS 3.7 de Homebrew, sobre el 1a con la carga real y los Cortes 2 y 3a.

## Qué hay

### SQL (`sql/`)
`pruebas_locales/generar.py` toma de la base local la huella del 3a y los textos de `v_epicrisis` y `activo_buscar`, y escribe 10, 05, 80, 90 y los `_editor`.
- **`10_esquema.sql`**
  - **Guardia:** exige el 3a exacto (la huella del conjunto de funciones y la de `v_epicrisis`).
  - **Tablas de solo inserción:**
    - `ficha_ediciones`: qué cambió, de A a B, con el motivo, el autor y la versión que creó;
    - `activo_identificador_eventos`: el alias propio y la placa o número de inventario;
    - `foto_perfil_preparaciones` y `activo_fotos_perfil`: la foto principal.
  - **Del 1a solo se agregan filas** a `activo_versiones` (versión nueva, con `carga_id` nulo) y a `activo_origen` (corrección del origen).
- **`20_vistas.sql`**
  - `v_activo_identificadores`: el alias y la placa vigentes.
  - `f_fotos_activo`: las fotos de perfil, de los daños y de las intervenciones (principal o también intervenido).
  - **Reemplaza `v_epicrisis`**, con las mismas columnas: suma los cambios de la ficha, «X: de «A» a «B»» con el motivo, y no repite la versión. La corrección del origen sale sin valores ni motivo.
- **`25_rpc.sql`**: 5 RPC nuevas y 1 reemplazada, todas solo para `service_role`.
  - `perfil`: alias, placa, foto principal y conteo de fotos (estos dos, para supervisor y administrador), y los catálogos y valores para editar (administrador).
  - `galeria`: solo supervisor y administrador; la lectura queda **auditada**.
  - `ficha_editar`: por ahora **solo el administrador**. Lleva:
    - versión nueva con la huella del motor de carga;
    - alias y placa (la placa no se repite entre activos);
    - campos del tipo en atributos;
    - observaciones;
    - corrección del origen (respuesta 3 de David);
    - refresco de una sola fila de la tabla vigente y versión nueva de la tesela.
  - `foto_perfil_preparar` y `foto_perfil_fijar`: JPEG de hasta 1,5 MB, con motivo.
  - **Reemplaza `activo_buscar`**: busca también por la placa (exacta o por el comienzo) y por el alias (contiene).
  - En el Corte 4, el supervisor de distribución se habilita cambiando solo `redes.f_editor_ficha`.
- **`70_pruebas.sql`:** **54 pruebas**, con su propia red (ID 99400xx, LABEL ZT4-…), sin suponer códigos ni datos reales.
- **`80_verificacion.sql`:** 10 OK y 2 INFO. Desde aquí, la fila 06 de la verificación del 3a dice MAL a propósito.
- **`90_reversa.sql`:** vuelve exacta al 3a. Se niega si hay ediciones, preparaciones, fotos de perfil u objetos en `activos/`.

### Edge `geoportal-redes` (rama `tecnica-corte3b`)
- Rutas nuevas: `perfil`, `galeria`, `ficha_editar` (lista cerrada de claves), `foto_perfil_preparar` y `foto_perfil_fijar`.
- **Las rutas de Storage nunca salen al navegador:** la foto principal y la galería se devuelven con URL firmadas de lectura de 60 s.
- `storage.ts` acepta `activos/AAAA-MM/<id>/<uuid>.jpg`. `_shared/auth.ts` y `autorizar()` sin tocar.

### Frontend (rama `tecnica-corte3b`, desde `tecnica-corte3a`)
- **Ficha como perfil:**
  - minimapa estático arriba, con el activo resaltado en su red (un toque acerca o aleja; el geovisor llega en el Corte 6);
  - alias en la cabecera y chip «Placa»;
  - foto principal y galería (supervisor y administrador), con visor grande;
  - la epicrisis como **muro**: daños, intervenciones y cambios de la ficha. El alta y las versiones de carga quedan plegadas en «Cambios del registro».
- **«Editar ficha»** (administrador): los campos por tipo, el alias, la placa y el origen, con la **vista previa** «de A a B» y el motivo obligatorio.
- **«Cambiar foto principal»** (administrador): la foto del computador o del celular, reducida a JPEG.
- **Búsqueda** de «Ficha de activos»: por código, código de la capa, placa o alias.

## Resultados (N de N)
- **Ensayo:** **54 de 54**, sin rastro.
- **Arnés local:** **20 de 20**, con la carga real:
  - reversa exacta al 3a;
  - edición real de V85 (versión 2, tabla vigente de 35.781 filas refrescada en una sola fila);
  - búsqueda por placa y por alias;
  - galería con la foto del daño y la de la reparación;
  - editar tarda menos de 1 s.
- **Edge simulada:** **123 de 123**. Verificador de permisos: 0 errores.
- **Chrome real, a 390 px y en escritorio: 39 de 39.**
- **Regresiones en la rama 3b:** 3a **76 de 76**, Corte 2 **60 de 60**, 1b **60 de 60** (con el aviso vacío nuevo), 0b **68 de 68**, áreas **51 de 51**, `tsc` y build.

## Riesgo conocido (para el Corte 5)
Si llega una carga nueva de la capa, el motor compara la huella y ve distinto un activo editado en la ficha. Entonces crea una versión desde la capa encima de la de la ficha. La versión de la ficha queda en el historial, y el alias, la placa, el origen y la foto no se pierden. El cargue del Corte 5 debe avisar de «editado en la ficha después de la última carga» y dejar elegir.
