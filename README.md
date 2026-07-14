# Geoportal Catastral — EMDUPAR

Geoportal web interno de **solo consulta** para la sala de atención al usuario y el
personal administrativo. Permite buscar un predio y verlo sobre el mapa con su
información catastral, **sin entregar ningún archivo descargable** (`.shp`, `.gpkg`
ni Excel). El dato vive en un solo lugar; el funcionario lo consulta, no lo posee.

## Cómo protege la información

- **Acceso cerrado al dominio institucional** `@emdupar.gov.co` + lista blanca.
  Si desactivan el correo de una persona, deja de recibir el código y pierde el
  acceso solo — el buzón es la llave.
- **El mapa se sirve como teselas vectoriales** (`ST_AsMVT`) generadas en PostGIS
  y entregadas por Edge Function autenticada. Nunca existe un archivo geográfico
  para bajar.
- **Solo lectura**: sin botón de exportar; la geometría cruda nunca sale al cliente.
- **Marca de agua** en pantalla con el correo del usuario (identifica cualquier foto
  reenviada).
- **Bitácora de auditoría**: cada búsqueda y cada predio consultado queda registrado
  con correo, referencia y fecha (`geoportal_auditoria`).

> No existe forma de impedir del todo una foto a la pantalla. La meta es dificultar
> la copia fácil y dejar rastro de quién accedió — eso sí se logra, y es lo que
> conviene poder mostrar ante una intervención SSPD.

## Arquitectura

```
Navegador (Vite + React + MapLibre)
   │  Authorization: Bearer <jwt del usuario>
   ▼
Edge Functions  ── validan dominio + lista blanca (service_role)
   ├─ geoportal-tiles    → teselas MVT de predios
   ├─ geoportal-buscar   → búsqueda (excluye clandestinos '0')
   └─ geoportal-predio   → detalle + registro en auditoría
   ▼
PostGIS  ── catastro_valledupar (tabla propia del geoportal, cargada por el loader)
```

La seguridad vive en el **borde de datos**: el geoportal usa funciones propias y
su **propia tabla de catastro**, independiente del Supabase de Acuo.

## Requisitos

- Node 18+
- Supabase CLI (`npm i -g supabase`)
- Proyecto Supabase con PostGIS (ref `kmmocjpuwooprxrlncyb`)

## Puesta en marcha

### 1. Variables de entorno (frontend)

```bash
cp .env.example .env
# completar VITE_SUPABASE_ANON_KEY
```

### 2. Base de datos

El catastro completo **no vive en el Supabase de Acuo** (allí solo hay captura de
información). Por eso el geoportal tiene su **propia tabla** `catastro_valledupar`,
con las ~87 columnas del predio en `props` (jsonb) más `cod_usuario` y `geom`
promovidos para búsqueda y mapa.

Ejecuta las dos migraciones en el SQL Editor o con la CLI:

```bash
supabase db push
# o pega en el editor, en orden:
#   supabase/migrations/0001_geoportal.sql   (lista blanca, auditoría, seguridad)
#   supabase/migrations/0002_catastro.sql    (tabla catastro + funciones)
```

### 2b. Cargar / actualizar el catastro (loader)

El catastro se alimenta desde `puntos.geojson`. El loader lo reemplaza de forma
atómica: durante la carga los usuarios siguen viendo la versión anterior.

```bash
cd loader
cp .env.example .env      # completar DATABASE_URL y GEOJSON_PATH
npm install
npm run cargar
```

Repite `npm run cargar` con el GeoJSON nuevo cada vez que llegue la actualización
mensual del catastro. La `DATABASE_URL` es la *Connection string* del proyecto
(Project Settings → Database). Revisa en `loader/.env.example` el `SRID` y el
nombre de la propiedad del código de usuario (`COD_USUARIO_KEY`).

### 3. Autorizar personas (lista blanca)

```sql
insert into public.geoportal_lista_blanca (email, nombre, creado_por) values
  ('funcionario.uno@emdupar.gov.co', 'Nombre Uno', 'david'),
  ('funcionario.dos@emdupar.gov.co', 'Nombre Dos', 'david');

-- revocar a alguien sin borrarlo:
update public.geoportal_lista_blanca set activo = false
where email = 'funcionario.uno@emdupar.gov.co';
```

### 4. Configurar Auth (dashboard)

En **Authentication → Providers → Email**: activar *Email OTP*.
En **URL Configuration**: agregar la URL donde se publique el geoportal.

### 5. Desplegar Edge Functions

```bash
supabase functions deploy geoportal-tiles  --no-verify-jwt
supabase functions deploy geoportal-buscar --no-verify-jwt
supabase functions deploy geoportal-predio --no-verify-jwt
```

> `--no-verify-jwt` porque la validación del token se hace **dentro** de cada
> función (así se controla dominio + lista blanca, no solo un token válido).
> Recuerda: el toggle *"Verify JWT with legacy secret"* se reactiva en cada
> deploy desde el dashboard — si despliegas por la interfaz, desactívalo a mano.

### 6. Frontend

```bash
npm install
npm run dev      # desarrollo
npm run build    # producción → dist/
```

## Ajustes que probablemente necesites

- **Nombre del código de usuario**: el loader extrae `cod_usuario` de la propiedad
  `COD_USUARIO_KEY` (por defecto `COD_USUARIO`). Ajústalo en `loader/.env` al nombre
  real de esa columna en tu `puntos.geojson`.
- **Búsqueda**: `geoportal_buscar_predio` (migración 0002) busca por `cod_usuario`.
  Para buscar también por dirección u otro campo, agrega una condición sobre
  `props->>'NOMBRE_DEL_CAMPO'` en esa función.
- **SRID**: el loader transforma a 4326 antes de guardar; la función MVT pasa a 3857.
  Define el SRID de origen en `loader/.env` (`4326` si el GeoJSON es lat/lon, `9377`
  si viene en MAGNA-SIRGAS/CTM12).
- **Mapa base**: usa OpenStreetMap. Para uso intensivo, cámbialo por un proveedor
  con llave en `src/components/MapView.tsx`.

## Consulta de la auditoría

```sql
select creado_en, email, accion, referencia
from public.geoportal_auditoria
order by creado_en desc
limit 100;
```
