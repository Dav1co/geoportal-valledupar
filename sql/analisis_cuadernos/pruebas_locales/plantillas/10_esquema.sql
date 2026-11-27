-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» (Code B, Corte 2 del geovisor técnico) · 10 — GUARDIA Y ESQUEMA
-- Esquema PROPIO `analisis`: no toca `tecnica` ni `redes` (sus huellas deben quedar iguales; lo comprueba la guardia y, al final, 40_permisos).
-- Todas las tablas son de SOLO INSERCIÓN (ni UPDATE, ni DELETE, ni TRUNCATE): cada «Guardar» es una versión nueva y una marca se quita «anulada + motivo».
-- RLS activado SIN políticas; `revoke all` a public, anon, authenticated y service_role; SELECT explícito para homelab_lectura (el Dell). Todo pasa por las RPC.
-- =====================================================================
do $guardia$
declare v text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v is distinct from '{{MD5_REDES}}' then raise exception 'GUARDIA ANÁLISIS: la huella de redes es % y se esperaba {{MD5_REDES}}', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v is distinct from '{{MD5_TECNICA}}' then raise exception 'GUARDIA ANÁLISIS: la huella de técnica es % y se esperaba {{MD5_TECNICA}}', v; end if;
  if exists (select 1 from pg_namespace where nspname = 'analisis') then raise exception 'GUARDIA ANÁLISIS: el esquema analisis ya existe (¿el paquete ya está aplicado?)'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\_analisis\_%') then
    raise exception 'GUARDIA ANÁLISIS: ya hay funciones public.geoportal_analisis_*';
  end if;
  if to_regprocedure('redes.f_geovisor_acceso(text)') is null then raise exception 'GUARDIA ANÁLISIS: falta redes.f_geovisor_acceso(text)'; end if;
  if to_regclass('redes.v_activo_vigente') is null then raise exception 'GUARDIA ANÁLISIS: falta redes.v_activo_vigente'; end if;
  if to_regclass('public.catastro_valledupar') is null
     or not exists (select 1 from pg_attribute where attrelid = 'public.catastro_valledupar'::regclass and attname = 'cod_usuario' and not attisdropped)
     or not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid join pg_am a on a.oid = c.relam
                     where i.indrelid = 'public.catastro_valledupar'::regclass and a.amname = 'gist') then
    raise exception 'GUARDIA ANÁLISIS: public.catastro_valledupar no tiene cod_usuario o le falta el índice GIST de geom';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then raise exception 'GUARDIA ANÁLISIS: no existe el rol homelab_lectura (respaldo del Dell)'; end if;
  -- El bucket lo crea David en el panel ANTES de esta migración: privado, solo JPEG, 600 KB (614400 bytes).
  if not exists (select 1 from storage.buckets where id = 'analisis-capturas' and public = false and file_size_limit = 614400 and allowed_mime_types = array['image/jpeg']) then
    raise exception 'GUARDIA ANÁLISIS: falta el bucket analisis-capturas o no es privado, solo image/jpeg y de 614400 bytes (600 KB)';
  end if;
end
$guardia$;

create schema analisis;
revoke all on schema analisis from public, anon, authenticated, service_role;

-- ---------- funciones que usan las tablas (disparador y CHECK) ----------
-- Solo agregar: bloquea UPDATE y DELETE (por fila) y TRUNCATE (por sentencia). También al dueño: los disparadores no distinguen el rol.
create function analisis.f_solo_agregar() returns trigger
language plpgsql set search_path = pg_catalog as $f$
begin
  raise exception 'Tabla de solo agregar: % no permitido en %.%', tg_op, tg_table_schema, tg_table_name using errcode = '42501';
end $f$;

-- Caja de Valledupar con margen (redes, PTAR, barrios y catastro del encargo: O −73,29679 · S 10,38185 · E −73,21382 · N 10,50684; aquí con ~5 km de holgura).
create function analisis.f_en_valledupar(p_geom geometry) returns boolean
language sql immutable parallel safe set search_path = public, pg_catalog as $f$
  select p_geom is not null and st_srid(p_geom) = 4326 and not st_isempty(p_geom)
     and st_xmin(p_geom) >= -73.35 and st_xmax(p_geom) <= -73.16 and st_ymin(p_geom) >= 10.33 and st_ymax(p_geom) <= 10.56
$f$;

-- Estilo de una marca: solo «color» (#RRGGBB) y «grosor» (1 a 12). Nada más entra.
create function analisis.f_estilo_valido(p jsonb) returns boolean
language sql immutable parallel safe set search_path = pg_catalog as $f$
  select p is not null and jsonb_typeof(p) = 'object'
     and not exists (select 1 from jsonb_object_keys(p) k where k not in ('color', 'grosor'))
     and (not p ? 'color' or (jsonb_typeof(p -> 'color') = 'string' and (p ->> 'color') ~ '^#[0-9A-Fa-f]{6}$'))
     and (not p ? 'grosor' or (jsonb_typeof(p -> 'grosor') = 'number' and (p ->> 'grosor') ~ '^[0-9]{1,2}$' and (p ->> 'grosor')::integer between 1 and 12))
$f$;

-- ---------- 1. Catálogo: los 9 problemas y los 12 íconos de activo (el código es el del ícono, no el prefijo de redes) ----------
create table analisis.catalogo (
  grupo   text    not null check (grupo in ('problema', 'activo')),
  codigo  text    not null check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  nombre  text    not null check (length(btrim(nombre)) between 3 and 80),
  color   text    check (color is null or color ~ '^#[0-9A-F]{6}$'),          -- solo los problemas; los activos toman el color del sistema
  orden   integer not null check (orden >= 1),
  activo  boolean not null default true,
  primary key (grupo, codigo),
  unique (grupo, orden),
  check ((grupo = 'problema') = (color is not null))
);
insert into analisis.catalogo (grupo, codigo, nombre, color, orden) values
  ('problema', 'falla_acueducto',       'Falla en la prestación de acueducto',      '#0B4F8A', 1),
  ('problema', 'falla_alcantarillado',  'Falla en la prestación de alcantarillado', '#6B4423', 2),
  ('problema', 'sin_acueducto',         'No hay acueducto',                         '#B3261E', 3),
  ('problema', 'sin_alcantarillado',    'No hay alcantarillado',                    '#7F1D1D', 4),
  ('problema', 'baja_presion',          'Baja presión',                             '#C25E00', 5),
  ('problema', 'fuga_visible',          'Fuga visible',                             '#0E7490', 6),
  ('problema', 'agua_turbia',           'Agua turbia',                              '#A16207', 7),
  ('problema', 'rebose_alcantarillado', 'Rebose de alcantarillado',                 '#4D5B1F', 8),
  ('problema', 'valvula_revisar',       'Válvula por revisar',                      '#6D28D9', 9),
  ('activo', 'tanque',       'Tanque',             null, 1),
  ('activo', 'tuberia',      'Tubería',            null, 2),
  ('activo', 'valvula',      'Válvula',            null, 3),
  ('activo', 'macromedidor', 'Macromedidor',       null, 4),
  ('activo', 'sensor',       'Sensor',             null, 5),
  ('activo', 'pozo',         'Pozo',               null, 6),
  ('activo', 'sumidero',     'Sumidero',           null, 7),
  ('activo', 'acometida',    'Acometida',          null, 8),
  ('activo', 'colector',     'Colector',           null, 9),
  ('activo', 'torre',        'Torre o estructura', null, 10),
  ('activo', 'planta',       'Planta',             null, 11),
  ('activo', 'vertimiento',  'Vertimiento',        null, 12);

-- ---------- 2. Parámetros (topes). Solo agregar: el vigente de cada clave es el último ----------
create table analisis.parametros (
  id         bigint      generated always as identity primary key,
  clave      text        not null check (clave in ('capturas_por_cuaderno', 'captura_lado_max_px', 'captura_bytes_max', 'marcas_por_cuaderno', 'mano_vertices_max',
                                                    'zona_area_max_km2', 'zona_conteos_por_hora', 'cambios_por_guardado')),
  valor      numeric     not null check (valor > 0),
  motivo     text        not null check (length(btrim(motivo)) between 5 and 300),
  autor      text        not null check (autor = lower(btrim(autor)) and length(autor) >= 3),
  creado_en  timestamptz not null default now()
);
insert into analisis.parametros (clave, valor, motivo, autor) values
  ('capturas_por_cuaderno', 20,     'Valor inicial (decisión de David, 26-nov)', 'migracion'),
  ('captura_lado_max_px',   1600,   'Valor inicial (decisión de David, 26-nov)', 'migracion'),
  ('captura_bytes_max',     614400, 'Valor inicial: 600 KB, igual al tope del bucket', 'migracion'),
  ('marcas_por_cuaderno',   500,    'Valor inicial (plan aprobado)', 'migracion'),
  ('mano_vertices_max',     500,    'Valor inicial (plan aprobado)', 'migracion'),
  ('zona_area_max_km2',     25,     'Valor inicial (plan aprobado)', 'migracion'),
  ('zona_conteos_por_hora', 120,    'Valor inicial (plan aprobado)', 'migracion'),
  ('cambios_por_guardado',  500,    'Valor inicial: a lo sumo, todas las marcas del cuaderno', 'migracion');

-- ---------- 3. Cuadernos: la identidad ----------
create table analisis.cuadernos (
  id         uuid        primary key default gen_random_uuid(),
  modulo     text        not null default 'tecnica' check (modulo in ('tecnica')),      -- el CHECK se amplía cuando entre Comercial
  autor      text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  creado_en  timestamptz not null default now()
);
create index cuadernos_autor_idx on analisis.cuadernos (autor, creado_en desc);

-- ---------- 4. Versiones: cada «Guardar» es una ----------
create table analisis.cuaderno_versiones (
  cuaderno_id  uuid        not null references analisis.cuadernos (id),
  version      integer     not null check (version >= 1),
  titulo       text        not null check (titulo = btrim(titulo) and length(titulo) between 3 and 120),
  descripcion  text        check (descripcion is null or length(descripcion) between 1 and 1000),
  vista        jsonb       check (vista is null or (jsonb_typeof(vista) = 'object' and length(vista::text) <= 4000)),   -- centro, zoom, temática y capas encendidas
  autor        text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  creado_en    timestamptz not null default now(),
  primary key (cuaderno_id, version)
);

-- ---------- 5. Estado del cuaderno: archivar o reabrir, con motivo ----------
create table analisis.cuaderno_eventos (
  id           bigint      generated always as identity primary key,
  cuaderno_id  uuid        not null references analisis.cuadernos (id),
  tipo         text        not null check (tipo in ('archivar', 'reabrir')),
  motivo       text        not null check (motivo = btrim(motivo) and length(motivo) between 5 and 300),
  autor        text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  creado_en    timestamptz not null default now()
);
create index cuaderno_eventos_cuaderno_idx on analisis.cuaderno_eventos (cuaderno_id, id desc);

-- ---------- 6. Marcas: la identidad ----------
create table analisis.marcas (
  id                 uuid        primary key,                 -- lo pone el dispositivo (el borrador ya la conoce) o el servidor
  cuaderno_id        uuid        not null,
  creada_en_version  integer     not null,
  creado_en          timestamptz not null default now(),
  unique (id, cuaderno_id),
  foreign key (cuaderno_id, creada_en_version) references analisis.cuaderno_versiones (cuaderno_id, version)
);
create index marcas_cuaderno_idx on analisis.marcas (cuaderno_id);

-- ---------- 7. Estado de la marca en cada versión en que cambió (la vigente es la última) ----------
create table analisis.marca_versiones (
  marca_id          uuid     not null,
  cuaderno_id       uuid     not null,
  version           integer  not null,
  tipo              text     not null check (tipo in ('problema', 'activo', 'referencia', 'postit', 'mano', 'circulo', 'linea', 'zona')),
  subtipo           text,                                       -- código del catálogo (problema o activo)
  sistema           text     check (sistema is null or sistema in ('acueducto', 'alcantarillado')),
  categoria         text     check (categoria is null or categoria in ('problema', 'propuesta', 'obra', 'observacion')),
  nota              text     check (nota is null or length(nota) between 1 and 500),
  estilo            jsonb    not null default '{}'::jsonb check (analisis.f_estilo_valido(estilo)),
  geom              geometry(Geometry, 4326) not null,
  radio_m           numeric  check (radio_m is null or radio_m between 1 and 5000),
  conteo_predios    integer  check (conteo_predios is null or conteo_predios >= 0),
  conteo_contratos  integer  check (conteo_contratos is null or conteo_contratos >= 0),
  activo_codigo     text     check (activo_codigo is null or activo_codigo ~ '^[A-Z]{3}-[0-9]{1,9}$'),
  sector            text     check (sector is null or length(sector) between 1 and 80),
  subsector         text     check (subsector is null or length(subsector) between 1 and 80),
  anulada           boolean  not null default false,
  motivo            text     check (motivo is null or (motivo = btrim(motivo) and length(motivo) between 5 and 300)),
  primary key (marca_id, version),
  foreign key (marca_id, cuaderno_id) references analisis.marcas (id, cuaderno_id),
  foreign key (cuaderno_id, version) references analisis.cuaderno_versiones (cuaderno_id, version),
  foreign key (tipo, subtipo) references analisis.catalogo (grupo, codigo),
  constraint marca_geom_valida check (st_isvalid(geom) and analisis.f_en_valledupar(geom) and st_npoints(geom) <= 2000),
  constraint marca_geom_del_tipo check (case when tipo in ('problema', 'activo', 'referencia', 'postit', 'circulo') then geometrytype(geom) = 'POINT'
                                             when tipo in ('mano', 'linea') then geometrytype(geom) = 'LINESTRING'
                                             else geometrytype(geom) = 'POLYGON' end),
  constraint marca_subtipo check ((tipo in ('problema', 'activo')) = (subtipo is not null)),
  constraint marca_sistema check ((tipo = 'activo') = (sistema is not null)),
  constraint marca_radio check ((tipo = 'circulo') = (radio_m is not null)),
  constraint marca_conteos check ((tipo = 'zona') = (conteo_predios is not null) and (tipo = 'zona') = (conteo_contratos is not null)),
  constraint marca_postit_con_texto check (tipo <> 'postit' or nota is not null),
  constraint marca_anulada_con_motivo check (anulada = (motivo is not null))
);
create index marca_versiones_cuaderno_idx on analisis.marca_versiones (cuaderno_id, version);

-- ---------- 8. Capturas: la imagen va al bucket privado analisis-capturas; aquí, solo sus datos ----------
create table analisis.capturas (
  id           uuid        primary key default gen_random_uuid(),
  cuaderno_id  uuid        not null references analisis.cuadernos (id),
  ruta         text        not null unique,
  titulo       text        not null check (titulo = btrim(titulo) and length(titulo) between 3 and 120),
  oeste        numeric     not null check (oeste between -180 and 180),
  sur          numeric     not null check (sur between -90 and 90),
  este         numeric     not null check (este between -180 and 180),
  norte        numeric     not null check (norte between -90 and 90),
  ancho        integer     not null check (ancho between 16 and 1600),
  alto         integer     not null check (alto between 16 and 1600),
  bytes        integer     not null check (bytes between 1 and 614400),
  sha256       text        not null check (sha256 ~ '^[0-9a-f]{64}$'),
  autor        text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  creado_en    timestamptz not null default now(),
  check (oeste < este and sur < norte),
  check (ruta = cuaderno_id::text || '/' || id::text || '.jpg')
);
create index capturas_cuaderno_idx on analisis.capturas (cuaderno_id, creado_en);

-- ---------- 9. Confirmación de la captura: el archivo ya está en el bucket, con su tamaño y tipo comprobados ----------
create table analisis.capturas_confirmadas (
  captura_id     uuid        primary key references analisis.capturas (id),
  bytes_reales   integer     not null check (bytes_reales between 1 and 614400),
  autor          text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  confirmada_en  timestamptz not null default now()
);

-- ---------- 10. Capturas anuladas: con motivo; ni el archivo ni la fila se borran. Las anuladas no cuentan para el tope ni se muestran ----------
create table analisis.capturas_anuladas (
  captura_id  uuid        primary key references analisis.capturas (id),
  motivo      text        not null check (motivo = btrim(motivo) and length(motivo) between 5 and 300),
  autor       text        not null check (autor = lower(btrim(autor)) and position('@' in autor) > 1),
  anulada_en  timestamptz not null default now()
);

-- ---------- 11. Conteos de zona pedidos (para el tope por hora; solo números, sin la geometría) ----------
create table analisis.zona_consultas (
  id           bigint      generated always as identity primary key,
  solicitante  text        not null check (solicitante = lower(btrim(solicitante)) and position('@' in solicitante) > 1),
  area_km2     numeric     not null check (area_km2 >= 0),
  predios      integer     not null check (predios >= 0),
  contratos    integer     not null check (contratos >= 0),
  creado_en    timestamptz not null default now()
);
create index zona_consultas_quien_idx on analisis.zona_consultas (solicitante, creado_en desc);

-- ---------- solo agregar (UPDATE, DELETE y TRUNCATE) y RLS sin políticas, en TODAS ----------
do $t$
declare t text;
begin
  foreach t in array array['catalogo', 'parametros', 'cuadernos', 'cuaderno_versiones', 'cuaderno_eventos', 'marcas', 'marca_versiones', 'capturas', 'capturas_confirmadas', 'capturas_anuladas', 'zona_consultas'] loop
    execute format('create trigger solo_agregar_fila before update or delete on analisis.%I for each row execute function analisis.f_solo_agregar()', t);
    execute format('create trigger solo_agregar_truncate before truncate on analisis.%I for each statement execute function analisis.f_solo_agregar()', t);
    execute format('alter table analisis.%I enable row level security', t);
    execute format('revoke all on analisis.%I from public, anon, authenticated, service_role', t);
  end loop;
end
$t$;
