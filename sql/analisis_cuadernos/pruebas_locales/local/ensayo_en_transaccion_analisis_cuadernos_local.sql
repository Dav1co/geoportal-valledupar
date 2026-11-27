begin;
-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 06 — FOTO DE ANTES. Va SOLO en el ensayo, ANTES de la guardia y del esquema (la migración no la lleva).
-- Guarda las huellas de redes y de técnica y el número de objetos de esos dos esquemas, para comprobar al final que el paquete no los tocó.
-- =====================================================================
create function pg_temp.foto() returns table (k text, v text) language sql stable as $$
  select 'huella_redes', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
  union all
  select 'huella_tecnica', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%')))
  union all
  select 'objetos_redes_tecnica', (select count(*)::text from pg_class c where c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace))
  union all
  select 'columnas_redes_tecnica', (select md5(coalesce(string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by c.relname, a.attnum), ''))
           from pg_class c join pg_attribute a on a.attrelid = c.oid where c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'funciones_public', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname not like 'geoportal\_analisis\_%')
  union all
  select 'disparadores_redes_tecnica', (select count(*)::text from pg_trigger t join pg_class c on c.oid = t.tgrelid where not t.tgisinternal and c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace)) $$;
create temp table _foto_antes as select * from pg_temp.foto();
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
  if v is distinct from '1ba192724c2fddcf321104700829f3cc' then raise exception 'GUARDIA ANÁLISIS: la huella de redes es % y se esperaba 1ba192724c2fddcf321104700829f3cc', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v is distinct from '4a10aa60971401954717fc3c74d3d869' then raise exception 'GUARDIA ANÁLISIS: la huella de técnica es % y se esperaba 4a10aa60971401954717fc3c74d3d869', v; end if;
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
-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 20 — FUNCIONES INTERNAS (esquema analisis; nadie de la API las ejecuta directamente)
-- =====================================================================
-- Error con texto para la persona (la Edge solo reenvía los mensajes con HINT = msg_usuario).
-- 22023 → 400 · 42501 → 403 · P0002 → 404 · 55000 → 409 · 54000 → 429
create function analisis.f_err(p_mensaje text, p_codigo text default '22023') returns void
language plpgsql set search_path = pg_catalog as $f$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $f$;

create function analisis.f_parametro(p_clave text) returns numeric
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select p.valor from analisis.parametros p where p.clave = p_clave order by p.id desc limit 1
$f$;

-- Quién entra a los cuadernos de Técnica: SOLO el supervisor de Técnica (distribución o planta) y el administrador.
-- La decisión es la del geovisor técnico (redes.f_geovisor_acceso, que no se toca): «completo» = supervisor o administrador.
-- El operador con la casilla del geovisor (solo lectura) y quien no tiene el geovisor reciben 42501 (403).
create function analisis.f_acceso(p_solicitante text, out email text, out admin boolean) returns record
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := redes.f_geovisor_acceso(p_solicitante);      -- 28000 sin solicitante · 42501 sin el geovisor técnico
  if not coalesce(a.completo, false) then
    raise exception 'Los cuadernos de análisis son del supervisor de Técnica' using errcode = '42501';
  end if;
  email := a.email; admin := coalesce(a.admin, false);
end $f$;

create function analisis.f_archivado(p_cuaderno uuid) returns boolean
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select coalesce((select e.tipo = 'archivar' from analisis.cuaderno_eventos e where e.cuaderno_id = p_cuaderno order by e.id desc limit 1), false)
$f$;

create function analisis.f_ultima_version(p_cuaderno uuid) returns integer
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select max(v.version) from analisis.cuaderno_versiones v where v.cuaderno_id = p_cuaderno
$f$;

-- El cuaderno, si el solicitante puede LEERLO (el autor, cualquier supervisor de Técnica y el administrador: todos pasaron f_acceso). Con p_autor, además debe ser SUYO.
-- A propósito no distingue «no existe» de «no es de este módulo»: 404 en los dos casos.
create function analisis.f_cuaderno(p_email text, p_id uuid, p_autor boolean default false) returns analisis.cuadernos
language plpgsql stable security definer set search_path = analisis, pg_catalog as $f$
declare c analisis.cuadernos;
begin
  if p_id is null then perform analisis.f_err('Falta el cuaderno'); end if;
  select * into c from analisis.cuadernos k where k.id = p_id and k.modulo = 'tecnica';
  if not found then perform analisis.f_err('El cuaderno no existe', 'P0002'); end if;
  if p_autor and c.autor <> p_email then
    raise exception 'Solo el autor edita el cuaderno' using errcode = '42501';
  end if;
  return c;
end $f$;

-- Punto que representa a la figura (para anotar el sector y para la exportación): el punto mismo, la mitad de la línea o un punto dentro del polígono.
create function analisis.f_punto(p_geom geometry) returns geometry
language sql immutable parallel safe set search_path = public, pg_catalog as $f$
  select case geometrytype(p_geom) when 'POINT' then p_geom
                                    when 'LINESTRING' then st_lineinterpolatepoint(p_geom, 0.5)
                                    else st_pointonsurface(p_geom) end
$f$;

-- Predios y contratos dentro de una zona. SOLO los dos números (ni direcciones ni códigos). Contratos = cod_usuario distintos y no vacíos.
create function analisis.f_conteo_zona(p_geom geometry, out predios integer, out contratos integer) returns record
language sql stable security definer set search_path = public, pg_catalog as $f$
  select count(*)::integer, (count(distinct c.cod_usuario) filter (where btrim(coalesce(c.cod_usuario, '')) <> ''))::integer
    from public.catastro_valledupar c where st_intersects(c.geom, p_geom)
$f$;

-- Tope de conteos por hora del solicitante (los de «zona» y los que hace «guardar» al calcular sus zonas).
create function analisis.f_cupo_zona(p_email text, p_nuevos integer) returns void
language plpgsql stable security definer set search_path = analisis, pg_catalog as $f$
begin
  if (select count(*) from analisis.zona_consultas z where z.solicitante = p_email and z.creado_en > now() - interval '1 hour') + p_nuevos
     > analisis.f_parametro('zona_conteos_por_hora') then
    perform analisis.f_err('Demasiados conteos de zona en la última hora. Espere unos minutos e intente de nuevo', '54000');
  end if;
end $f$;

-- Una zona lista para contar: polígono válido, dentro de Valledupar y bajo el área máxima.
create function analisis.f_zona_valida(p_geom geometry) returns numeric
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare v_km2 numeric;
begin
  if p_geom is null or geometrytype(p_geom) <> 'POLYGON' or not st_isvalid(p_geom) then perform analisis.f_err('La zona no es un polígono válido'); end if;
  if st_npoints(p_geom) > 2000 then perform analisis.f_err('La zona tiene demasiados vértices'); end if;
  if not analisis.f_en_valledupar(p_geom) then perform analisis.f_err('La zona está fuera de Valledupar'); end if;
  v_km2 := round((st_area(p_geom::geography) / 1e6)::numeric, 4);
  if v_km2 > analisis.f_parametro('zona_area_max_km2') then
    perform analisis.f_err(format('La zona es demasiado grande (%s km²; el máximo es %s km²)', round(v_km2, 1), analisis.f_parametro('zona_area_max_km2')));
  end if;
  return v_km2;
end $f$;

-- Geometría desde el GeoJSON del dispositivo (siempre 4326). Un GeoJSON ilegible es 400, no 500.
create function analisis.f_geom(p jsonb) returns geometry
language plpgsql immutable set search_path = public, pg_temp as $f$
declare g geometry;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  begin
    g := st_setsrid(st_force2d(st_geomfromgeojson(p::text)), 4326);
  exception when others then
    return null;
  end;
  return g;
end $f$;

-- Las marcas de un cuaderno tal como estaban en una versión (la última fila de cada marca hasta esa versión; las anuladas no salen).
create function analisis.f_marcas(p_cuaderno uuid, p_version integer) returns jsonb
language sql stable security definer set search_path = public, analisis, pg_temp as $f$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.marca_id, 'version', u.version, 'creada_en_version', u.creada_en_version, 'tipo', u.tipo, 'subtipo', u.subtipo, 'sistema', u.sistema,
           'categoria', u.categoria, 'nota', u.nota, 'estilo', u.estilo, 'geom', st_asgeojson(u.geom, 7)::jsonb, 'radio_m', u.radio_m,
           'conteo_predios', u.conteo_predios, 'conteo_contratos', u.conteo_contratos, 'activo_codigo', u.activo_codigo, 'sector', u.sector, 'subsector', u.subsector)
           order by u.creada_en_version, u.creado_en, u.marca_id), '[]'::jsonb)
    from (select distinct on (mv.marca_id) mv.*, m.creada_en_version, m.creado_en
            from analisis.marca_versiones mv join analisis.marcas m on m.id = mv.marca_id
           where mv.cuaderno_id = p_cuaderno and mv.version <= p_version
           order by mv.marca_id, mv.version desc) u
   where not u.anulada
$f$;

-- pg-safeupdate: las funciones de este paquete sin DELETE/UPDATE sin WHERE. Es la misma revisión de redes.f_funciones_sin_where(), sobre `analisis` y
-- public.geoportal_analisis_* (la de redes no se toca para no cambiar su huella).
create function analisis.f_funciones_sin_where() returns table (funcion text, sentencia text)
language sql stable set search_path = pg_catalog as $f$
  with f as (
    select p.oid::regprocedure::text as funcion,
           regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace in (select n.oid from pg_namespace n where n.nspname = 'analisis')
            or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select s.funcion, left(s.st, 200) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')
   order by 1, 2
$f$;
-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 26 — RPC public.geoportal_analisis_* (las llama SOLO la Edge geoportal-analisis, con service_role)
-- Todas: SECURITY DEFINER con search_path fijo, p_solicitante = el correo del token (lo pone la Edge) y la decisión de permiso aquí, en SQL.
-- Lee: el autor, cualquier supervisor de Técnica y el administrador. Edita: SOLO el autor (también si es administrador). Operador y sin permisos: 42501 (403).
-- =====================================================================

-- ---------- perfil: quién es, el catálogo y los topes (para armar la barra) ----------
create function public.geoportal_analisis_perfil(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := analisis.f_acceso(p_solicitante);
  return jsonb_build_object(
    'email', a.email, 'admin', a.admin, 'puede_crear', true,
    'catalogo', (select jsonb_agg(jsonb_build_object('grupo', c.grupo, 'codigo', c.codigo, 'nombre', c.nombre, 'color', c.color, 'orden', c.orden) order by c.grupo desc, c.orden)
                   from analisis.catalogo c where c.activo),
    'sistemas', jsonb_build_object('acueducto', '#1F5FA8', 'alcantarillado', '#8A5A2B'),
    'categorias', jsonb_build_array('problema', 'propuesta', 'obra', 'observacion'),
    'topes', (select jsonb_object_agg(x.clave, x.valor) from (select distinct on (p.clave) p.clave, p.valor from analisis.parametros p order by p.clave, p.id desc) x));
end $f$;

-- ---------- lista de cuadernos (los míos y los del equipo) ----------
create function public.geoportal_analisis_cuadernos(p_solicitante text, p_archivados boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := analisis.f_acceso(p_solicitante);
  return jsonb_build_object('cuadernos', coalesce((
    select jsonb_agg(to_jsonb(x) order by x.actualizado_en desc, x.id)
      from (select c.id, v.titulo, v.descripcion, c.autor, (select lb.nombre from public.geoportal_lista_blanca lb where lower(lb.email) = c.autor limit 1) as autor_nombre,
                   c.creado_en, v.version, v.creado_en as actualizado_en, c.autor = a.email as es_mio, analisis.f_archivado(c.id) as archivado,
                   (select count(*) from (select distinct on (mv.marca_id) mv.anulada from analisis.marca_versiones mv where mv.cuaderno_id = c.id
                                           order by mv.marca_id, mv.version desc) u where not u.anulada) as marcas,
                   (select count(*) from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)) as capturas
              from analisis.cuadernos c
              join analisis.cuaderno_versiones v on v.cuaderno_id = c.id and v.version = analisis.f_ultima_version(c.id)
             where c.modulo = 'tecnica' and analisis.f_archivado(c.id) = coalesce(p_archivados, false)
             order by v.creado_en desc limit 500) x), '[]'::jsonb));
end $f$;

-- ---------- un cuaderno: la última versión o la pedida, con sus marcas vigentes y sus capturas ----------
create function public.geoportal_analisis_cuaderno(p_solicitante text, p_id uuid, p_version integer default null) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v analisis.cuaderno_versiones; v_ult integer;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id);
  v_ult := analisis.f_ultima_version(c.id);
  select * into v from analisis.cuaderno_versiones x where x.cuaderno_id = c.id and x.version = coalesce(p_version, v_ult);
  if not found then perform analisis.f_err('Esa versión del cuaderno no existe', 'P0002'); end if;
  return jsonb_build_object(
    'id', c.id, 'modulo', c.modulo, 'autor', c.autor, 'creado_en', c.creado_en, 'es_mio', c.autor = a.email, 'archivado', analisis.f_archivado(c.id),
    'autor_nombre', (select lb.nombre from public.geoportal_lista_blanca lb where lower(lb.email) = c.autor limit 1),
    'version', v.version, 'ultima_version', v_ult, 'titulo', v.titulo, 'descripcion', v.descripcion, 'vista', v.vista, 'guardado_en', v.creado_en,
    'puede_editar', c.autor = a.email and v.version = v_ult and not analisis.f_archivado(c.id),
    'versiones', (select jsonb_agg(jsonb_build_object('version', x.version, 'creado_en', x.creado_en, 'titulo', x.titulo) order by x.version desc)
                    from analisis.cuaderno_versiones x where x.cuaderno_id = c.id),
    'marcas', analisis.f_marcas(c.id, v.version),
    'capturas', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'titulo', k.titulo, 'extension', jsonb_build_array(k.oeste, k.sur, k.este, k.norte),
                                 'ancho', k.ancho, 'alto', k.alto, 'bytes', kc.bytes_reales, 'creado_en', k.creado_en) order by k.creado_en, k.id)
                            from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)), '[]'::jsonb),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'motivo', e.motivo, 'creado_en', e.creado_en) order by e.id)
                           from analisis.cuaderno_eventos e where e.cuaderno_id = c.id), '[]'::jsonb));
end $f$;

-- ---------- crear: nace con la versión 1, sin marcas ----------
create function public.geoportal_analisis_cuaderno_crear(p_solicitante text, p_titulo text, p_descripcion text default null, p_vista jsonb default null) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; v_id uuid; v_titulo text := btrim(coalesce(p_titulo, '')); v_desc text := nullif(btrim(coalesce(p_descripcion, '')), '');
begin
  a := analisis.f_acceso(p_solicitante);
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título debe tener entre 3 y 120 letras'); end if;
  if length(v_desc) > 1000 then perform analisis.f_err('La descripción no puede pasar de 1.000 letras'); end if;
  if p_vista is not null and (jsonb_typeof(p_vista) <> 'object' or length(p_vista::text) > 4000) then perform analisis.f_err('La vista del mapa no es válida'); end if;
  insert into analisis.cuadernos (modulo, autor) values ('tecnica', a.email) returning id into v_id;
  insert into analisis.cuaderno_versiones (cuaderno_id, version, titulo, descripcion, vista, autor) values (v_id, 1, v_titulo, v_desc, p_vista, a.email);
  return jsonb_build_object('id', v_id, 'version', 1);
end $f$;

-- ---------- guardar: SOLO el autor. Cada llamada es una versión nueva (version_base + 1) ----------
-- p_cambios = [{op: 'nueva' | 'cambia' | 'anula', marca_id, …}]. «nueva» y «cambia» traen el estado COMPLETO de la marca; «anula», el motivo.
-- Si version_base no es la última: 55000 (409) «Este cuaderno cambió en otra pestaña». El sector, el subsector y los conteos de las zonas los calcula el servidor.
create function public.geoportal_analisis_cuaderno_guardar(p_solicitante text, p_id uuid, p_version_base integer, p_titulo text default null, p_descripcion text default null,
                                                           p_vista jsonb default null, p_cambios jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare
  a record; c analisis.cuadernos; v_prev analisis.cuaderno_versiones; v_ult integer; v_ver integer;
  v_titulo text; v_desc text; v_cambios jsonb := coalesce(p_cambios, '[]'::jsonb);
  x jsonb; i integer := 0; v_op text; v_mid uuid; v_tipo text; v_sub text; v_sis text; v_cat text; v_nota text; v_est jsonb; g geometry; v_radio numeric; v_act text; v_mot text;
  v_viejo analisis.marca_versiones; v_filas jsonb := '[]'::jsonb; v_ids uuid[] := '{}'; v_nuevas integer := 0; v_anuladas integer := 0; v_zonas integer := 0;
  v_vigentes integer; v_km2 numeric; v_pred integer; v_cont integer; v_mano_max integer; v_pre text; v_forma text;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));        -- dos «Guardar» a la vez del mismo cuaderno: de a uno
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para seguir editando', '55000'); end if;
  v_ult := analisis.f_ultima_version(c.id);
  if p_version_base is null then perform analisis.f_err('Falta la versión de la que parte el cambio'); end if;
  if p_version_base <> v_ult then perform analisis.f_err('Este cuaderno cambió en otra pestaña. Ábralo de nuevo para ver la última versión', '55000'); end if;
  select * into v_prev from analisis.cuaderno_versiones k where k.cuaderno_id = c.id and k.version = v_ult;
  v_ver := v_ult + 1;

  v_titulo := case when p_titulo is null then v_prev.titulo else btrim(p_titulo) end;
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título debe tener entre 3 y 120 letras'); end if;
  v_desc := case when p_descripcion is null then v_prev.descripcion else nullif(btrim(p_descripcion), '') end;       -- '' la borra; sin el dato, queda la anterior
  if length(v_desc) > 1000 then perform analisis.f_err('La descripción no puede pasar de 1.000 letras'); end if;
  if p_vista is not null and (jsonb_typeof(p_vista) <> 'object' or length(p_vista::text) > 4000) then perform analisis.f_err('La vista del mapa no es válida'); end if;
  if jsonb_typeof(v_cambios) <> 'array' then perform analisis.f_err('Los cambios no son válidos'); end if;
  if jsonb_array_length(v_cambios) > analisis.f_parametro('cambios_por_guardado') then perform analisis.f_err('Demasiados cambios en un solo guardado'); end if;
  if jsonb_array_length(v_cambios) = 0 and p_titulo is null and p_descripcion is null and p_vista is null then perform analisis.f_err('No hay cambios para guardar'); end if;
  v_mano_max := analisis.f_parametro('mano_vertices_max');

  for x in select e from jsonb_array_elements(v_cambios) e loop
    i := i + 1; v_pre := 'Marca ' || i || ': ';
    if jsonb_typeof(x) <> 'object' then perform analisis.f_err(v_pre || 'no es válida'); end if;
    v_op := x ->> 'op';
    if v_op is null or v_op not in ('nueva', 'cambia', 'anula') then perform analisis.f_err(v_pre || 'la operación no es válida'); end if;
    begin
      v_mid := nullif(x ->> 'marca_id', '')::uuid;
    exception when others then
      perform analisis.f_err(v_pre || 'el identificador no es válido');
    end;
    if v_op = 'nueva' then
      v_mid := coalesce(v_mid, gen_random_uuid());
      if exists (select 1 from analisis.marcas m where m.id = v_mid) then perform analisis.f_err(v_pre || 'ya existe'); end if;
      v_nuevas := v_nuevas + 1;
    else
      if v_mid is null then perform analisis.f_err(v_pre || 'falta el identificador'); end if;
      select mv.* into v_viejo from analisis.marca_versiones mv where mv.marca_id = v_mid and mv.cuaderno_id = c.id order by mv.version desc limit 1;
      if not found or v_viejo.anulada then perform analisis.f_err(v_pre || 'no existe en este cuaderno o ya está anulada'); end if;
    end if;
    if v_mid = any (v_ids) then perform analisis.f_err(v_pre || 'está repetida en este guardado'); end if;
    v_ids := v_ids || v_mid;

    if v_op = 'anula' then
      v_mot := btrim(coalesce(x ->> 'motivo', ''));
      if length(v_mot) not between 5 and 300 then perform analisis.f_err(v_pre || 'para anularla escriba el motivo (de 5 a 300 letras)'); end if;
      v_anuladas := v_anuladas + 1;
      v_filas := v_filas || jsonb_build_object('marca_id', v_mid, 'nueva', false, 'tipo', v_viejo.tipo, 'subtipo', v_viejo.subtipo, 'sistema', v_viejo.sistema, 'categoria', v_viejo.categoria,
        'nota', v_viejo.nota, 'estilo', v_viejo.estilo, 'geom', v_viejo.geom::text, 'radio_m', v_viejo.radio_m, 'conteo_predios', v_viejo.conteo_predios,
        'conteo_contratos', v_viejo.conteo_contratos, 'activo_codigo', v_viejo.activo_codigo, 'anulada', true, 'motivo', v_mot);
      continue;
    end if;

    v_tipo := x ->> 'tipo';
    if v_tipo is null or v_tipo not in ('problema', 'activo', 'referencia', 'postit', 'mano', 'circulo', 'linea', 'zona') then perform analisis.f_err(v_pre || 'el tipo no es válido'); end if;
    if v_op = 'cambia' and v_tipo <> v_viejo.tipo then perform analisis.f_err(v_pre || 'no se le puede cambiar el tipo'); end if;
    v_sub := nullif(x ->> 'subtipo', ''); v_sis := nullif(x ->> 'sistema', ''); v_cat := nullif(x ->> 'categoria', '');
    v_nota := nullif(btrim(coalesce(x ->> 'nota', '')), ''); v_act := nullif(btrim(coalesce(x ->> 'activo_codigo', '')), '');
    v_est := coalesce(nullif(x -> 'estilo', 'null'::jsonb), '{}'::jsonb);
    if v_tipo in ('problema', 'activo') then
      if v_sub is null or not exists (select 1 from analisis.catalogo k where k.grupo = v_tipo and k.codigo = v_sub and k.activo) then
        perform analisis.f_err(v_pre || case v_tipo when 'problema' then 'elija el problema de la lista' else 'elija el activo de la lista' end);
      end if;
    elsif v_sub is not null then perform analisis.f_err(v_pre || 'ese tipo de marca no lleva subtipo');
    end if;
    if v_tipo = 'activo' then
      if v_sis is null or v_sis not in ('acueducto', 'alcantarillado') then perform analisis.f_err(v_pre || 'elija Acueducto o Alcantarillado'); end if;
      if v_act is not null then perform analisis.f_err(v_pre || 'un ícono de activo es una propuesta y no se enlaza a un activo real'); end if;
    elsif v_sis is not null then perform analisis.f_err(v_pre || 'solo los íconos de activo llevan sistema');
    end if;
    if v_cat is not null and v_cat not in ('problema', 'propuesta', 'obra', 'observacion') then perform analisis.f_err(v_pre || 'la categoría no es válida'); end if;
    if length(v_nota) > 500 then perform analisis.f_err(v_pre || 'la nota no puede pasar de 500 letras'); end if;
    if v_tipo = 'postit' and v_nota is null then perform analisis.f_err(v_pre || 'el post-it necesita su texto'); end if;
    if not analisis.f_estilo_valido(v_est) then perform analisis.f_err(v_pre || 'el color o el grosor no son válidos'); end if;

    g := analisis.f_geom(x -> 'geom');
    if g is null or st_isempty(g) then perform analisis.f_err(v_pre || 'la figura no es válida'); end if;
    v_forma := case when v_tipo in ('mano', 'linea') then 'LINESTRING' when v_tipo = 'zona' then 'POLYGON' else 'POINT' end;
    if geometrytype(g) <> v_forma then perform analisis.f_err(v_pre || 'la figura no corresponde al tipo de marca'); end if;
    if st_npoints(g) > 5000 then perform analisis.f_err(v_pre || 'la figura tiene demasiados puntos'); end if;
    if v_tipo = 'mano' then g := st_simplifypreservetopology(g, 0.00001); end if;                       -- ~1 m: la mano alzada se aligera antes de guardar
    if not st_isvalid(g) then perform analisis.f_err(v_pre || 'la figura no es válida'); end if;
    if not analisis.f_en_valledupar(g) then perform analisis.f_err(v_pre || 'está fuera de Valledupar'); end if;
    if v_tipo = 'mano' and st_npoints(g) > v_mano_max then perform analisis.f_err(v_pre || 'el trazo es demasiado largo: divídalo en dos'); end if;
    if v_tipo = 'linea' and st_npoints(g) > 100 then perform analisis.f_err(v_pre || 'la línea tiene demasiados puntos'); end if;

    v_radio := null; v_pred := null; v_cont := null;
    if v_tipo = 'circulo' then
      begin
        v_radio := round((x ->> 'radio_m')::numeric, 1);
      exception when others then
        v_radio := null;
      end;
      if v_radio is null or v_radio not between 1 and 5000 then perform analisis.f_err(v_pre || 'el radio del círculo debe estar entre 1 y 5.000 m'); end if;
    end if;
    if v_tipo = 'zona' then
      v_km2 := analisis.f_zona_valida(g);
      if v_op = 'cambia' and st_equals(g, v_viejo.geom) then
        v_pred := v_viejo.conteo_predios; v_cont := v_viejo.conteo_contratos;                           -- la zona no se movió: vale su conteo
      else
        v_zonas := v_zonas + 1;
        perform analisis.f_cupo_zona(a.email, 1);
        select z.predios, z.contratos into v_pred, v_cont from analisis.f_conteo_zona(g) z;
        insert into analisis.zona_consultas (solicitante, area_km2, predios, contratos) values (a.email, v_km2, v_pred, v_cont);
      end if;
    end if;
    if v_act is not null then
      if v_act !~ '^[A-Z]{3}-[0-9]{1,9}$' or not exists (select 1 from redes.v_activo_vigente w where w.codigo = v_act) then
        perform analisis.f_err(v_pre || 'el activo ' || left(v_act, 14) || ' no existe');
      end if;
    end if;
    v_filas := v_filas || jsonb_build_object('marca_id', v_mid, 'nueva', v_op = 'nueva', 'tipo', v_tipo, 'subtipo', v_sub, 'sistema', v_sis, 'categoria', v_cat, 'nota', v_nota,
      'estilo', v_est, 'geom', g::text, 'radio_m', v_radio, 'conteo_predios', v_pred, 'conteo_contratos', v_cont, 'activo_codigo', v_act, 'anulada', false, 'motivo', null);
  end loop;

  select count(*) into v_vigentes from (select distinct on (mv.marca_id) mv.anulada from analisis.marca_versiones mv where mv.cuaderno_id = c.id
                                         order by mv.marca_id, mv.version desc) u where not u.anulada;
  if v_vigentes + v_nuevas - v_anuladas > analisis.f_parametro('marcas_por_cuaderno') then
    perform analisis.f_err(format('El cuaderno no puede pasar de %s marcas', analisis.f_parametro('marcas_por_cuaderno')));
  end if;

  insert into analisis.cuaderno_versiones (cuaderno_id, version, titulo, descripcion, vista, autor)
  values (c.id, v_ver, v_titulo, v_desc, coalesce(p_vista, v_prev.vista), a.email);
  insert into analisis.marcas (id, cuaderno_id, creada_en_version)
  select f.marca_id, c.id, v_ver from jsonb_to_recordset(v_filas) as f (marca_id uuid, nueva boolean) where f.nueva;
  -- El sector y el subsector donde cae la marca (su punto, la mitad de la línea o un punto dentro de la zona), de una sola vez
  with sec as materialized (select w.codigo, w.nombre, w.clase, w.geom from redes.v_activo_vigente w where w.prefijo = 'SEC'),
       f as (select t.*, analisis.f_punto(t.geom::geometry) as pt
               from jsonb_to_recordset(v_filas) as t (marca_id uuid, tipo text, subtipo text, sistema text, categoria text, nota text, estilo jsonb, geom text, radio_m numeric,
                                                      conteo_predios integer, conteo_contratos integer, activo_codigo text, anulada boolean, motivo text))
  insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, subtipo, sistema, categoria, nota, estilo, geom, radio_m, conteo_predios, conteo_contratos,
                                        activo_codigo, sector, subsector, anulada, motivo)
  select f.marca_id, c.id, v_ver, f.tipo, f.subtipo, f.sistema, f.categoria, f.nota, f.estilo, f.geom::geometry, f.radio_m, f.conteo_predios, f.conteo_contratos, f.activo_codigo,
         (select left(s.nombre, 80) from sec s where s.clase = 'sector' and st_intersects(s.geom, f.pt) order by s.codigo limit 1),
         (select left(s.nombre, 80) from sec s where s.clase = 'subsector' and st_intersects(s.geom, f.pt) order by s.codigo limit 1),
         f.anulada, f.motivo
    from f;
  return jsonb_build_object('id', c.id, 'version', v_ver, 'marcas', analisis.f_marcas(c.id, v_ver));
end $f$;

-- ---------- archivar o reabrir, con motivo: SOLO el autor ----------
create function public.geoportal_analisis_cuaderno_estado(p_solicitante text, p_id uuid, p_tipo text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v_mot text := btrim(coalesce(p_motivo, '')); v_arch boolean;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  if p_tipo is null or p_tipo not in ('archivar', 'reabrir') then perform analisis.f_err('La acción no es válida'); end if;
  if length(v_mot) not between 5 and 300 then perform analisis.f_err('Escriba el motivo (de 5 a 300 letras)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  v_arch := analisis.f_archivado(c.id);
  if p_tipo = 'archivar' and v_arch then perform analisis.f_err('El cuaderno ya está archivado', '55000'); end if;
  if p_tipo = 'reabrir' and not v_arch then perform analisis.f_err('El cuaderno no está archivado', '55000'); end if;
  insert into analisis.cuaderno_eventos (cuaderno_id, tipo, motivo, autor) values (c.id, p_tipo, v_mot, a.email);
  return jsonb_build_object('id', c.id, 'archivado', p_tipo = 'archivar');
end $f$;

-- ---------- zona afectada: SOLO los dos números, con tope por hora y área máxima ----------
create function public.geoportal_analisis_zona(p_solicitante text, p_geom jsonb) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; g geometry; v_km2 numeric; v_pred integer; v_cont integer;
begin
  a := analisis.f_acceso(p_solicitante);
  g := analisis.f_geom(p_geom);
  v_km2 := analisis.f_zona_valida(g);
  perform analisis.f_cupo_zona(a.email, 1);
  select z.predios, z.contratos into v_pred, v_cont from analisis.f_conteo_zona(g) z;
  insert into analisis.zona_consultas (solicitante, area_km2, predios, contratos) values (a.email, v_km2, v_pred, v_cont);
  return jsonb_build_object('predios', v_pred, 'contratos', v_cont);
end $f$;

-- ---------- captura · 1: reservar la ruta (la Edge firma la subida de ESA ruta) ----------
create function public.geoportal_analisis_captura_firmar(p_solicitante text, p_id uuid, p_titulo text, p_oeste numeric, p_sur numeric, p_este numeric, p_norte numeric,
                                                         p_ancho integer, p_alto integer, p_bytes integer, p_sha256 text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v_titulo text := btrim(coalesce(p_titulo, '')); v_id uuid := gen_random_uuid(); v_ruta text; v_n integer; v_lado integer;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para guardar capturas', '55000'); end if;
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título de la captura debe tener entre 3 y 120 letras'); end if;
  if p_oeste is null or p_sur is null or p_este is null or p_norte is null or p_oeste not between -180 and 180 or p_este not between -180 and 180
     or p_sur not between -90 and 90 or p_norte not between -90 and 90 or p_oeste >= p_este or p_sur >= p_norte then
    perform analisis.f_err('La extensión de la captura no es válida');
  end if;
  v_lado := analisis.f_parametro('captura_lado_max_px');
  if p_ancho is null or p_alto is null or p_ancho < 16 or p_alto < 16 or greatest(p_ancho, p_alto) > v_lado then
    perform analisis.f_err(format('La captura no puede pasar de %s px de lado', v_lado));
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > analisis.f_parametro('captura_bytes_max') then
    perform analisis.f_err(format('La captura no puede pesar más de %s KB', (analisis.f_parametro('captura_bytes_max') / 1024)::integer));
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform analisis.f_err('La huella de la captura no es válida'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  -- Cuentan las confirmadas y las reservadas en los últimos 15 minutos que aún no se confirman (una subida a medias no ocupa el cupo para siempre).
  -- Las ANULADAS no cuentan.
  select count(*) into v_n from analisis.capturas k
   where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id) and (exists (select 1 from analisis.capturas_confirmadas kc where kc.captura_id = k.id) or k.creado_en > now() - interval '15 minutes');
  if v_n >= analisis.f_parametro('capturas_por_cuaderno') then
    perform analisis.f_err(format('El cuaderno ya tiene sus %s capturas', analisis.f_parametro('capturas_por_cuaderno')::integer), '55000');
  end if;
  v_ruta := c.id::text || '/' || v_id::text || '.jpg';
  insert into analisis.capturas (id, cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor)
  values (v_id, c.id, v_ruta, v_titulo, p_oeste, p_sur, p_este, p_norte, p_ancho, p_alto, p_bytes, p_sha256, a.email);
  return jsonb_build_object('captura_id', v_id, 'ruta', v_ruta);
end $f$;

-- ---------- captura · 2: confirmar que el archivo llegó al bucket, con su tamaño y su tipo ----------
create function public.geoportal_analisis_captura_confirmar(p_solicitante text, p_captura uuid) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos; v_size bigint; v_mime text;
begin
  a := analisis.f_acceso(p_solicitante);
  select * into k from analisis.capturas x where x.id = p_captura;
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id, true);
  if exists (select 1 from analisis.capturas_confirmadas kc where kc.captura_id = k.id) then return jsonb_build_object('captura_id', k.id, 'confirmada', true); end if;
  select nullif(o.metadata ->> 'size', '')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
    from storage.objects o where o.bucket_id = 'analisis-capturas' and o.name = k.ruta;
  if not found then perform analisis.f_err('La imagen todavía no está en el almacenamiento. Intente de nuevo', '55000'); end if;
  if v_mime is distinct from 'image/jpeg' then perform analisis.f_err('La captura debe ser una imagen JPEG'); end if;
  if v_size is null or v_size < 1 or v_size > analisis.f_parametro('captura_bytes_max') then perform analisis.f_err('La captura pesa más de lo permitido'); end if;
  if v_size <> k.bytes then perform analisis.f_err('La imagen que llegó no es la que se anunció'); end if;
  insert into analisis.capturas_confirmadas (captura_id, bytes_reales, autor) values (k.id, v_size::integer, a.email);
  return jsonb_build_object('captura_id', k.id, 'confirmada', true);
end $f$;

-- ---------- captura · anular: SOLO el autor, con motivo. No se borra el archivo ni la fila; deja de mostrarse y de contar para el tope ----------
create function public.geoportal_analisis_captura_anular(p_solicitante text, p_captura uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos; v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  a := analisis.f_acceso(p_solicitante);
  select x.* into k from analisis.capturas x join analisis.capturas_confirmadas kc on kc.captura_id = x.id where x.id = p_captura;
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id, true);
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para anular capturas', '55000'); end if;
  if length(v_motivo) not between 5 and 300 then perform analisis.f_err('Para anular la captura escriba el motivo (de 5 a 300 letras)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  if exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id) then perform analisis.f_err('La captura ya está anulada', '55000'); end if;
  insert into analisis.capturas_anuladas (captura_id, motivo, autor) values (k.id, v_motivo, a.email);
  return jsonb_build_object('captura_id', k.id, 'anulada', true);
end $f$;

-- ---------- captura · 3: la ruta de una captura confirmada (la Edge firma la lectura de 60 s) ----------
create function public.geoportal_analisis_captura_ruta(p_solicitante text, p_captura uuid) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos;
begin
  a := analisis.f_acceso(p_solicitante);
  select x.* into k from analisis.capturas x join analisis.capturas_confirmadas kc on kc.captura_id = x.id where x.id = p_captura
     and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = x.id);        -- una captura anulada ya no se abre
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id);
  return jsonb_build_object('captura_id', k.id, 'ruta', k.ruta, 'titulo', k.titulo);
end $f$;

-- ---------- exportar: las marcas vigentes de la última versión, en filas, y la lista de capturas ----------
create function public.geoportal_analisis_cuaderno_exportar(p_solicitante text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v analisis.cuaderno_versiones;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id);
  select * into v from analisis.cuaderno_versiones x where x.cuaderno_id = c.id and x.version = analisis.f_ultima_version(c.id);
  return jsonb_build_object(
    'cuaderno', jsonb_build_object('id', c.id, 'titulo', v.titulo, 'descripcion', v.descripcion, 'autor', c.autor, 'version', v.version, 'guardado_en', v.creado_en),
    'marcas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'n', u.n, 'tipo', u.tipo, 'subtipo', u.subtipo, 'nombre', (select k.nombre from analisis.catalogo k where k.grupo = u.tipo and k.codigo = u.subtipo),
               'sistema', u.sistema, 'categoria', u.categoria, 'nota', u.nota, 'sector', u.sector, 'subsector', u.subsector, 'activo_codigo', u.activo_codigo,
               'predios', u.conteo_predios, 'contratos', u.conteo_contratos, 'radio_m', u.radio_m,
               'longitud_m', case when geometrytype(u.geom) = 'LINESTRING' then round(st_length(u.geom::geography)::numeric, 1) end,
               'area_m2', case when geometrytype(u.geom) = 'POLYGON' then round(st_area(u.geom::geography)::numeric, 0) end,
               'lon', round(st_x(analisis.f_punto(u.geom))::numeric, 6), 'lat', round(st_y(analisis.f_punto(u.geom))::numeric, 6),
               'creada_en_version', u.creada_en_version, 'cambiada_en_version', u.version) order by u.n)
        from (select w.*, row_number() over (order by w.creada_en_version, w.creado_en, w.marca_id) as n
                from (select distinct on (mv.marca_id) mv.*, m.creada_en_version, m.creado_en
                        from analisis.marca_versiones mv join analisis.marcas m on m.id = mv.marca_id
                       where mv.cuaderno_id = c.id order by mv.marca_id, mv.version desc) w
               where not w.anulada) u), '[]'::jsonb),
    'capturas', coalesce((select jsonb_agg(jsonb_build_object('titulo', k.titulo, 'creado_en', k.creado_en, 'ancho', k.ancho, 'alto', k.alto, 'bytes', kc.bytes_reales,
                                 'oeste', k.oeste, 'sur', k.sur, 'este', k.este, 'norte', k.norte) order by k.creado_en, k.id)
                            from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)), '[]'::jsonb));
end $f$;
-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 40 — PERMISOS
-- RPC public.geoportal_analisis_*: EXECUTE SOLO para service_role (la Edge). Las internas del esquema analisis: nadie de la API.
-- Tablas: nada para public, anon, authenticated ni service_role (ya revocado en 10); el Dell (homelab_lectura) lee con SELECT explícito, tabla por tabla.
-- =====================================================================
do $p$
declare f record;
begin
  for f in select p.oid::regprocedure as firma, p.pronamespace = 'public'::regnamespace as es_rpc from pg_proc p
            where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.es_rpc then execute format('grant execute on function %s to service_role', f.firma); end if;
  end loop;
end
$p$;

grant usage on schema analisis to homelab_lectura;
grant select on analisis.catalogo, analisis.parametros, analisis.cuadernos, analisis.cuaderno_versiones, analisis.cuaderno_eventos, analisis.marcas, analisis.marca_versiones,
                analisis.capturas, analisis.capturas_confirmadas, analisis.capturas_anuladas, analisis.zona_consultas to homelab_lectura;

-- Cierre: las huellas de redes y de técnica siguen iguales, y ninguna función del paquete tiene DELETE/UPDATE sin WHERE (pg-safeupdate)
do $cierre$
declare v text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v is distinct from '1ba192724c2fddcf321104700829f3cc' then raise exception 'ANÁLISIS: la huella de redes cambió (%)', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v is distinct from '4a10aa60971401954717fc3c74d3d869' then raise exception 'ANÁLISIS: la huella de técnica cambió (%)', v; end if;
  if exists (select 1 from analisis.f_funciones_sin_where()) then raise exception 'ANÁLISIS: hay funciones con DELETE/UPDATE sin WHERE'; end if;
end
$cierre$;
-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 70 — PRUEBAS «N de N». Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.cuad.*), sus cuadernos (título «ZTCUAD …») y sus archivos en el bucket (solo la fila de storage.objects).
-- Lee el catastro y los sectores reales solo para comparar números; no los cambia. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE ANÁLISIS · CUADERNOS … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    raise exception 'no falló' using errcode = 'ZT001';        -- si no falló, este error deshace lo que alcanzó a escribir: las pruebas siguientes parten del mismo estado
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    if v_e = 'ZT001' then perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar'); return; end if;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
-- Un «guardar» con UNA marca que debe ser rechazada con 22023 y ese texto
create function pg_temp.mala(p_nombre text, p_quien text, p_id uuid, p_base integer, p_marca text, p_texto text, p_estado text default '22023') returns void language sql as $$
  select pg_temp.err(p_nombre, format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, %s, null, null, null, %L::jsonb)', p_quien, p_id, p_base, '[' || p_marca || ']'), p_estado, p_texto) $$;
create function pg_temp.pt(p_x numeric, p_y numeric) returns text language sql as $$ select format('{"type":"Point","coordinates":[%s,%s]}', p_x, p_y) $$;
create function pg_temp.cuadro(p_x numeric, p_y numeric, p_l numeric) returns text language sql as $$
  select format('{"type":"Polygon","coordinates":[[[%s,%s],[%s,%s],[%s,%s],[%s,%s],[%s,%s]]]}', p_x, p_y, p_x + p_l, p_y, p_x + p_l, p_y + p_l, p_x, p_y + p_l, p_x, p_y) $$;

do $prueba$
declare
  adm text := 'prueba.cuad.adm@emdupar.gov.co'; sp text := 'prueba.cuad.sp@emdupar.gov.co'; sd text := 'prueba.cuad.sd@emdupar.gov.co';
  op text := 'prueba.cuad.op@emdupar.gov.co'; op2 text := 'prueba.cuad.op2@emdupar.gov.co'; dual text := 'prueba.cuad.dual@emdupar.gov.co';
  nadie text := 'prueba.cuad.nadie@emdupar.gov.co'; fuera text := 'prueba.cuad.fuera@emdupar.gov.co';
  tablas text[] := array['catalogo', 'parametros', 'cuadernos', 'cuaderno_versiones', 'cuaderno_eventos', 'marcas', 'marca_versiones', 'capturas', 'capturas_confirmadas', 'capturas_anuladas', 'zona_consultas'];
  rpcs text[] := array['geoportal_analisis_perfil', 'geoportal_analisis_cuadernos', 'geoportal_analisis_cuaderno', 'geoportal_analisis_cuaderno_crear', 'geoportal_analisis_cuaderno_guardar',
                       'geoportal_analisis_cuaderno_estado', 'geoportal_analisis_zona', 'geoportal_analisis_captura_firmar', 'geoportal_analisis_captura_confirmar', 'geoportal_analisis_captura_anular',
                       'geoportal_analisis_captura_ruta', 'geoportal_analisis_cuaderno_exportar'];
  llamadas text[]; t text; q text; quien text; i integer;
  j jsonb; m jsonb; v_id uuid; v_id2 uuid; v_adm uuid; v_cap uuid; v_cap2 uuid; v_ruta text; v_n integer; v_n2 integer; v_txt text; v_act text;
  m_prob uuid; m_act uuid; m_ref uuid; m_post uuid; m_mano uuid; m_circ uuid; m_lin uuid; m_zona uuid;
  zona text := pg_temp.cuadro(-73.2560, 10.4640, 0.0060);            -- ~0,44 km² dentro de la ciudad
  zona2 text := pg_temp.cuadro(-73.2500, 10.4700, 0.0040);
  mano text; v_total integer; v_bien integer; v_fallas text;
begin
  -- ---------- personas de prueba: los 5 perfiles (y un segundo supervisor, un operador sin la casilla y alguien fuera de la lista) ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTCUAD Administrador', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTCUAD Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTCUAD Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZTCUAD Operador con el geovisor', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZTCUAD Operador sin el geovisor', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, ver_registro_tecnico, horario, dias) values (dual, 'ZTCUAD Dual (Comercial y Técnica)', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (nadie, 'ZTCUAD Sin permisos', 'consulta', 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZTCUAD necesita ver la red en la calle');

  -- ===================== 00. Estructura y permisos =====================
  perform pg_temp.reg('00.01 las 11 tablas existen, con RLS activado y SIN políticas',
    (select count(*) = 11 and bool_and(c.relrowsecurity) from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r' and c.relname = any (tablas))
    and (select count(*) from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r') = 11
    and not exists (select 1 from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'analisis'::regnamespace));
  perform pg_temp.reg('00.02 ninguna tabla da privilegios a public, anon, authenticated ni service_role',
    not exists (select 1 from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r, unnest(array['select', 'insert', 'update', 'delete', 'truncate']) p
                 where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r' and has_table_privilege(r, c.oid, p))
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.relnamespace = 'analisis'::regnamespace and a.grantee = 0));
  perform pg_temp.reg('00.03 el esquema no da USAGE a la API (solo al Dell)',
    not has_schema_privilege('anon', 'analisis', 'usage') and not has_schema_privilege('authenticated', 'analisis', 'usage') and not has_schema_privilege('service_role', 'analisis', 'usage')
    and has_schema_privilege('homelab_lectura', 'analisis', 'usage') and not has_schema_privilege('homelab_lectura', 'analisis', 'create'));
  perform pg_temp.reg('00.04 homelab_lectura: SELECT en las 11 tablas y nada más',
    (select bool_and(has_table_privilege('homelab_lectura', c.oid, 'select') and not has_table_privilege('homelab_lectura', c.oid, 'insert')
                     and not has_table_privilege('homelab_lectura', c.oid, 'update') and not has_table_privilege('homelab_lectura', c.oid, 'delete')
                     and not has_table_privilege('homelab_lectura', c.oid, 'truncate'))
       from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r'));
  perform pg_temp.reg('00.05 las 12 RPC public.geoportal_analisis_* son las del paquete',
    (select array_agg(distinct p.proname::text order by p.proname::text) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')
      = (select array_agg(x order by x) from unnest(rpcs) x)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%') = 12);
  perform pg_temp.reg('00.06 las 12 RPC son SECURITY DEFINER con search_path fijo',
    (select bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'),
    (select string_agg(p.proname, ', ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'
        and not (p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))));
  perform pg_temp.reg('00.07 las 12 RPC: EXECUTE para service_role y NO para public, anon ni authenticated',
    (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'));
  perform pg_temp.reg('00.08 las funciones internas del esquema analisis: sin EXECUTE para public, anon, authenticated ni service_role',
    (select count(*) > 10 and bool_and(not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
       from pg_proc p where p.pronamespace = 'analisis'::regnamespace));
  perform pg_temp.reg('00.09 TODA función del paquete lleva search_path fijo (también las que no son SECURITY DEFINER)',
    (select bool_and(exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) from pg_proc p
      where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')));
  perform pg_temp.reg('00.10 cada tabla tiene sus dos disparadores de solo agregar: por fila (UPDATE y DELETE) y por sentencia (TRUNCATE)',
    (select count(*) = 22 and count(*) filter (where (g.tgtype & 32) = 32 and (g.tgtype & 1) = 0) = 11            -- 32 = TRUNCATE, 1 = por fila
            and count(*) filter (where (g.tgtype & 16) = 16 and (g.tgtype & 8) = 8 and (g.tgtype & 1) = 1) = 11     -- 16 = UPDATE, 8 = DELETE
            and bool_and(g.tgenabled = 'O' and (g.tgtype & 2) = 2 and g.tgfoid = 'analisis.f_solo_agregar()'::regprocedure)
       from pg_trigger g join pg_class c on c.oid = g.tgrelid where not g.tgisinternal and c.relnamespace = 'analisis'::regnamespace));
  foreach t in array tablas loop
    perform pg_temp.err('00.11 TRUNCATE bloqueado en analisis.' || t, format('truncate analisis.%I cascade', t), '42501', 'TRUNCATE no permitido');
  end loop;
  perform pg_temp.reg('00.12 el catálogo: los 9 problemas con su color y los 12 íconos de activo (sin color: lo pone el sistema)',
    (select array_agg(codigo order by orden) from analisis.catalogo where grupo = 'problema') = array['falla_acueducto', 'falla_alcantarillado', 'sin_acueducto', 'sin_alcantarillado',
       'baja_presion', 'fuga_visible', 'agua_turbia', 'rebose_alcantarillado', 'valvula_revisar']
    and (select array_agg(codigo order by orden) from analisis.catalogo where grupo = 'activo') = array['tanque', 'tuberia', 'valvula', 'macromedidor', 'sensor', 'pozo', 'sumidero',
       'acometida', 'colector', 'torre', 'planta', 'vertimiento']
    and (select bool_and((grupo = 'problema') = (color is not null)) from analisis.catalogo));
  perform pg_temp.reg('00.13 los topes: 20 capturas, 1.600 px, 600 KB, 500 marcas, 500 vértices, 25 km², 120 conteos por hora',
    analisis.f_parametro('capturas_por_cuaderno') = 20 and analisis.f_parametro('captura_lado_max_px') = 1600 and analisis.f_parametro('captura_bytes_max') = 614400
    and analisis.f_parametro('marcas_por_cuaderno') = 500 and analisis.f_parametro('mano_vertices_max') = 500 and analisis.f_parametro('zona_area_max_km2') = 25
    and analisis.f_parametro('zona_conteos_por_hora') = 120 and analisis.f_parametro('cambios_por_guardado') = 500);
  perform pg_temp.reg('00.14 pg-safeupdate: ninguna función del paquete (ni de redes o técnica) con DELETE/UPDATE sin WHERE',
    not exists (select 1 from analisis.f_funciones_sin_where()) and not exists (select 1 from redes.f_funciones_sin_where()),
    (select string_agg(funcion, ', ') from analisis.f_funciones_sin_where()));
  perform pg_temp.reg('00.15 la revisión de «sin WHERE» sí mira las funciones del paquete (20 o más)',
    (select count(*) from pg_proc p where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')) >= 20);
  perform pg_temp.reg('00.16 el bucket analisis-capturas es privado, solo JPEG y de 600 KB',
    exists (select 1 from storage.buckets where id = 'analisis-capturas' and not public and file_size_limit = 614400 and allowed_mime_types = array['image/jpeg']));
  perform pg_temp.reg('00.17 ninguna tabla guarda nombre, teléfono, dirección ni cédula de suscriptores (solo el nombre del catálogo)',
    not exists (select 1 from information_schema.columns where table_schema = 'analisis' and column_name ~ '(telefono|direccion|cedula|suscriptor|contrato$|cod_usuario)')
    and (select array_agg(table_name::text) from information_schema.columns where table_schema = 'analisis' and column_name = 'nombre') = array['catalogo']);

  -- ===================== 01. Quién entra (5 perfiles) =====================
  j := public.geoportal_analisis_perfil(sp);
  perform pg_temp.reg('01.01 el supervisor de planta entra: catálogo (21), topes (8), sistemas y categorías',
    jsonb_array_length(j -> 'catalogo') = 21 and (select count(*) from jsonb_object_keys(j -> 'topes')) = 8 and j ->> 'email' = sp and (j ->> 'admin')::boolean = false
    and j -> 'sistemas' ->> 'acueducto' = '#1F5FA8' and j -> 'sistemas' ->> 'alcantarillado' = '#8A5A2B' and jsonb_array_length(j -> 'categorias') = 4);
  perform pg_temp.reg('01.02 el supervisor de distribución y el administrador también entran',
    public.geoportal_analisis_perfil(sd) ->> 'email' = sd and (public.geoportal_analisis_perfil(adm) ->> 'admin')::boolean);
  perform pg_temp.reg('01.03 el correo se normaliza (mayúsculas y espacios)', public.geoportal_analisis_perfil('  ' || upper(sp) || ' ') ->> 'email' = sp);
  -- cada RPC, con cada perfil sin acceso: 42501 (403). Los argumentos son válidos de forma: el rechazo es por permiso, no por el dato
  v_id := gen_random_uuid();
  llamadas := array[
    'geoportal_analisis_perfil(%L)', 'geoportal_analisis_cuadernos(%L)', format('geoportal_analisis_cuaderno(%%L, %L)', v_id), 'geoportal_analisis_cuaderno_crear(%L, ''ZTCUAD no debe crearse'')',
    format('geoportal_analisis_cuaderno_guardar(%%L, %L, 1, ''ZTCUAD x'')', v_id), format('geoportal_analisis_cuaderno_estado(%%L, %L, ''archivar'', ''ZTCUAD motivo'')', v_id),
    format('geoportal_analisis_zona(%%L, %L::jsonb)', zona),
    format('geoportal_analisis_captura_firmar(%%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', v_id, repeat('a', 64)),
    format('geoportal_analisis_captura_confirmar(%%L, %L)', v_id), format('geoportal_analisis_captura_anular(%%L, %L, ''ZTCUAD motivo'')', v_id), format('geoportal_analisis_captura_ruta(%%L, %L)', v_id), format('geoportal_analisis_cuaderno_exportar(%%L, %L)', v_id)];
  for i in 1 .. array_length(llamadas, 1) loop
    foreach quien in array array[op, op2, dual, nadie, fuera] loop
      perform pg_temp.err(format('01.04 %s · %s → 403', rpcs[i], split_part(split_part(quien, '@', 1), '.', 3)), 'select public.' || format(llamadas[i], quien), '42501');
    end loop;
    perform pg_temp.err(format('01.05 %s · sin solicitante → 401', rpcs[i]), 'select public.' || format(llamadas[i], ''), '28000');
  end loop;
  perform pg_temp.reg('01.06 los rechazados no dejaron nada escrito', not exists (select 1 from analisis.cuadernos) and not exists (select 1 from analisis.zona_consultas));
  perform pg_temp.reg('01.07 el operador con la casilla SÍ tiene el geovisor (solo lectura): el 403 es de los cuadernos, no del geovisor',
    redes.f_geovisor_lectura(op) and not redes.f_geovisor_lectura(op2) and not (redes.f_geovisor_acceso(op)).completo);

  -- ===================== 02. Crear y listar =====================
  j := public.geoportal_analisis_cuaderno_crear(sp, '  ZTCUAD Cuaderno del POIR  ', '  Zonas con baja presión  ', '{"centro":[-73.25,10.46],"zoom":14,"tematica":"edad"}');
  v_id := (j ->> 'id')::uuid;
  perform pg_temp.reg('02.01 crear: nace con la versión 1, del autor, con el título y la descripción recortados',
    (j ->> 'version')::integer = 1 and (select autor = sp and modulo = 'tecnica' from analisis.cuadernos where id = v_id)
    and (select titulo = 'ZTCUAD Cuaderno del POIR' and descripcion = 'Zonas con baja presión' and vista ->> 'tematica' = 'edad' and autor = sp from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 1));
  perform pg_temp.err('02.02 un título de 2 letras no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, ''ab'')', sp), '22023', 'título');
  perform pg_temp.err('02.03 un título de 121 letras no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, %L)', sp, repeat('x', 121)), '22023', 'título');
  perform pg_temp.err('02.04 una vista que no es un objeto no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, ''ZTCUAD x'', null, ''[1]''::jsonb)', sp), '22023', 'vista');
  v_adm := (public.geoportal_analisis_cuaderno_crear(adm, 'ZTCUAD Cuaderno del administrador') ->> 'id')::uuid;
  j := public.geoportal_analisis_cuadernos(sd);
  perform pg_temp.reg('02.05 el otro supervisor ve los dos cuadernos del equipo, sin ser suyos, con autor, versión y conteos en cero',
    (select count(*) = 2 and bool_and(not (x ->> 'es_mio')::boolean and (x ->> 'version')::integer = 1 and (x ->> 'marcas')::integer = 0 and (x ->> 'capturas')::integer = 0
                                      and not (x ->> 'archivado')::boolean)
       from jsonb_array_elements(j -> 'cuadernos') x where x ->> 'titulo' like 'ZTCUAD%')
    and (select x ->> 'autor_nombre' from jsonb_array_elements(j -> 'cuadernos') x where x ->> 'id' = v_id::text) = 'ZTCUAD Supervisor de planta');
  perform pg_temp.reg('02.06 el autor ve el suyo marcado como propio',
    (select (x ->> 'es_mio')::boolean from jsonb_array_elements(public.geoportal_analisis_cuadernos(sp) -> 'cuadernos') x where x ->> 'id' = v_id::text));

  -- ===================== 03. Guardar: marcas de los 8 tipos =====================
  select w.codigo into v_act from redes.v_activo_vigente w where w.prefijo = 'VAL' order by w.codigo limit 1;
  select string_agg(format('[%s,%s]', -73.2500 - g * 0.00002, 10.4600 + (g % 2) * 0.0000002 + g * 0.00002), ',' order by g) into mano from generate_series(0, 299) g;   -- 300 puntos casi en línea
  mano := '{"type":"LineString","coordinates":[' || mano || ']}';
  m_prob := gen_random_uuid(); m_act := gen_random_uuid(); m_ref := gen_random_uuid(); m_post := gen_random_uuid();
  m_mano := gen_random_uuid(); m_circ := gen_random_uuid(); m_lin := gen_random_uuid(); m_zona := gen_random_uuid();
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 1, null, null, null, format($j$[
    {"op":"nueva","marca_id":"%s","tipo":"problema","subtipo":"valvula_revisar","categoria":"problema","nota":"  ZTCUAD revisar esta válvula  ","geom":%s,"activo_codigo":"%s"},
    {"op":"nueva","marca_id":"%s","tipo":"activo","subtipo":"tanque","sistema":"acueducto","categoria":"propuesta","nota":"ZTCUAD aquí va un tanque nuevo","geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"referencia","estilo":{"color":"#00AA55"},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"postit","nota":"ZTCUAD post-it","estilo":{"color":"#FFE066"},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"mano","estilo":{"color":"#D00000","grosor":4},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"circulo","radio_m":150.26,"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"linea","categoria":"obra","geom":{"type":"LineString","coordinates":[[-73.2550,10.4650],[-73.2540,10.4660]]}},
    {"op":"nueva","marca_id":"%s","tipo":"zona","nota":"ZTCUAD zona afectada","geom":%s}]$j$,
    m_prob, pg_temp.pt(-73.2530, 10.4660), v_act, m_act, pg_temp.pt(-73.2535, 10.4665), m_ref, pg_temp.pt(-73.2540, 10.4670), m_post, pg_temp.pt(-73.2545, 10.4675),
    m_mano, mano, m_circ, pg_temp.pt(-73.2520, 10.4655), m_lin, m_zona, zona)::jsonb);
  perform pg_temp.reg('03.01 guardar: versión 2 con las 8 marcas (una de cada tipo)',
    (j ->> 'version')::integer = 2 and jsonb_array_length(j -> 'marcas') = 8
    and (select count(distinct x ->> 'tipo') from jsonb_array_elements(j -> 'marcas') x) = 8 and (select count(*) from analisis.marcas where cuaderno_id = v_id and creada_en_version = 2) = 8);
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_prob::text;
  perform pg_temp.reg('03.02 el problema: subtipo, categoría, nota recortada y el activo real enlazado',
    m ->> 'subtipo' = 'valvula_revisar' and m ->> 'categoria' = 'problema' and m ->> 'nota' = 'ZTCUAD revisar esta válvula' and m ->> 'activo_codigo' = v_act and m ->> 'sistema' is null);
  perform pg_temp.reg('03.03 el sector y el subsector los anota el servidor (los mismos que da el mapa de sectores para ese punto)',
    m ->> 'sector' is not distinct from (select w.nombre from redes.v_activo_vigente w where w.prefijo = 'SEC' and w.clase = 'sector'
                                           and st_intersects(w.geom, st_setsrid(st_makepoint(-73.2530, 10.4660), 4326)) order by w.codigo limit 1)
    and m ->> 'subsector' is not distinct from (select w.nombre from redes.v_activo_vigente w where w.prefijo = 'SEC' and w.clase = 'subsector'
                                           and st_intersects(w.geom, st_setsrid(st_makepoint(-73.2530, 10.4660), 4326)) order by w.codigo limit 1)
    and (select count(*) from analisis.marca_versiones where cuaderno_id = v_id and sector is not null) > 0, m ->> 'sector' || ' · ' || coalesce(m ->> 'subsector', '—'));
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_act::text;
  perform pg_temp.reg('03.04 el ícono de activo: su código, el sistema y la categoría; no se enlaza a ningún activo real',
    m ->> 'subtipo' = 'tanque' and m ->> 'sistema' = 'acueducto' and m ->> 'categoria' = 'propuesta' and m ->> 'activo_codigo' is null);
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_mano::text;
  perform pg_temp.reg('03.05 la mano alzada se simplifica antes de guardar (300 puntos casi en línea quedan en muchos menos) y conserva su color y grosor',
    jsonb_array_length(m -> 'geom' -> 'coordinates') < 30 and m -> 'estilo' ->> 'color' = '#D00000' and (m -> 'estilo' ->> 'grosor')::integer = 4,
    jsonb_array_length(m -> 'geom' -> 'coordinates') || ' puntos');
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_circ::text;
  perform pg_temp.reg('03.06 el círculo: un punto con su radio en metros (un decimal)', (m ->> 'radio_m')::numeric = 150.3 and m -> 'geom' ->> 'type' = 'Point');
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_zona::text;
  select count(*), count(distinct cod_usuario) filter (where btrim(coalesce(cod_usuario, '')) <> '') into v_n, v_n2
    from public.catastro_valledupar where st_intersects(geom, st_setsrid(st_geomfromgeojson(zona), 4326));
  perform pg_temp.reg('03.07 la zona: los predios y los contratos los cuenta el servidor (iguales al catastro)',
    (m ->> 'conteo_predios')::integer = v_n and (m ->> 'conteo_contratos')::integer = v_n2 and v_n > 0, v_n || ' predios · ' || v_n2 || ' contratos');
  perform pg_temp.reg('03.08 las demás marcas no llevan conteos ni radio',
    (select bool_and(x ->> 'conteo_predios' is null and x ->> 'conteo_contratos' is null) from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' <> 'zona')
    and (select bool_and(x ->> 'radio_m' is null) from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' <> 'circulo'));
  perform pg_temp.reg('03.09 el conteo de la zona quedó en el registro de consultas (solo números)',
    (select count(*) = 1 and bool_and(predios = v_n and contratos = v_n2 and area_km2 between 0.3 and 0.6) from analisis.zona_consultas where solicitante = sp));
  perform pg_temp.reg('03.10 el título y la vista siguen los de la versión anterior cuando no se mandan',
    (select titulo = 'ZTCUAD Cuaderno del POIR' and vista ->> 'tematica' = 'edad' and descripcion = 'Zonas con baja presión' from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 2));

  -- quién guarda
  perform pg_temp.mala('03.11 otro supervisor NO edita el cuaderno ajeno', sd, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Solo el autor', '42501');
  perform pg_temp.mala('03.12 el administrador tampoco edita el cuaderno ajeno', adm, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Solo el autor', '42501');
  perform pg_temp.mala('03.13 guardar sobre una versión vieja → 409 «cambió en otra pestaña»', sp, v_id, 1, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'otra pestaña', '55000');
  perform pg_temp.mala('03.14 guardar sobre una versión que aún no existe → 409', sp, v_id, 3, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'otra pestaña', '55000');
  perform pg_temp.err('03.15 guardar sin nada que cambiar no crea versión', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2)', sp, v_id), '22023', 'No hay cambios');
  perform pg_temp.err('03.16 un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 1, ''ZTCUAD x'')', sp, gen_random_uuid()), 'P0002');
  -- lo que no entra (cada regla, con su texto)
  perform pg_temp.mala('03.17 operación desconocida', sp, v_id, 2, '{"op":"borra"}', 'operación');
  perform pg_temp.mala('03.18 tipo desconocido', sp, v_id, 2, format('{"op":"nueva","tipo":"estrella","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'tipo');
  perform pg_temp.mala('03.19 un problema que no está en la lista', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"otro","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'elija el problema');
  perform pg_temp.mala('03.20 un problema con código de activo', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"tanque","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'elija el problema');
  perform pg_temp.mala('03.21 un ícono de activo sin sistema', sp, v_id, 2, format('{"op":"nueva","tipo":"activo","subtipo":"pozo","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Acueducto o Alcantarillado');
  perform pg_temp.mala('03.22 un ícono de activo enlazado a un activo real', sp, v_id, 2,
    format('{"op":"nueva","tipo":"activo","subtipo":"valvula","sistema":"acueducto","activo_codigo":"%s","geom":%s}', v_act, pg_temp.pt(-73.25, 10.46)), 'no se enlaza');
  perform pg_temp.mala('03.23 un post-it con sistema', sp, v_id, 2, format('{"op":"nueva","tipo":"postit","nota":"x","sistema":"acueducto","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'sistema');
  perform pg_temp.mala('03.24 una referencia con subtipo', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","subtipo":"tanque","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'subtipo');
  perform pg_temp.mala('03.25 categoría desconocida', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","categoria":"urgente","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'categoría');
  perform pg_temp.mala('03.26 nota de 501 letras', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","nota":"%s","geom":%s}', repeat('n', 501), pg_temp.pt(-73.25, 10.46)), '500 letras');
  perform pg_temp.mala('03.27 post-it sin texto', sp, v_id, 2, format('{"op":"nueva","tipo":"postit","nota":"   ","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'necesita su texto');
  perform pg_temp.mala('03.28 estilo con una clave que no es color ni grosor', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"color":"#112233","url":"x"},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.29 color que no es #RRGGBB', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"color":"red"},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.30 grosor 40', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"grosor":40},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.31 sin figura', sp, v_id, 2, '{"op":"nueva","tipo":"referencia"}', 'figura no es válida');
  perform pg_temp.mala('03.32 figura ilegible', sp, v_id, 2, '{"op":"nueva","tipo":"referencia","geom":{"type":"Point","coordinates":"x"}}', 'figura no es válida');
  perform pg_temp.mala('03.33 un punto con tipo zona', sp, v_id, 2, format('{"op":"nueva","tipo":"zona","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no corresponde');
  perform pg_temp.mala('03.34 un polígono con tipo problema', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","geom":%s}', zona), 'no corresponde');
  perform pg_temp.mala('03.35 un punto en Bogotá', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-74.08, 4.60)), 'fuera de Valledupar');
  perform pg_temp.mala('03.36 una zona en corbatín (inválida)', sp, v_id, 2,
    '{"op":"nueva","tipo":"zona","geom":{"type":"Polygon","coordinates":[[[-73.25,10.46],[-73.24,10.47],[-73.24,10.46],[-73.25,10.47],[-73.25,10.46]]]}}', 'figura no es válida');
  perform pg_temp.mala('03.37 una zona de más de 25 km²', sp, v_id, 2, format('{"op":"nueva","tipo":"zona","geom":%s}', pg_temp.cuadro(-73.30, 10.40, 0.09)), 'demasiado grande');
  perform pg_temp.mala('03.38 un círculo sin radio', sp, v_id, 2, format('{"op":"nueva","tipo":"circulo","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'radio');
  perform pg_temp.mala('03.39 un círculo de 6 km de radio', sp, v_id, 2, format('{"op":"nueva","tipo":"circulo","radio_m":6000,"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'radio');
  perform pg_temp.mala('03.40 un activo real que no existe', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","activo_codigo":"VAL-999999999","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no existe');
  perform pg_temp.mala('03.41 un código de activo con otra forma', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","activo_codigo":"x'' or 1=1","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no existe');
  perform pg_temp.mala('03.42 una marca nueva con un identificador que ya existe', sp, v_id, 2, format('{"op":"nueva","marca_id":"%s","tipo":"referencia","geom":%s}', m_ref, pg_temp.pt(-73.25, 10.46)), 'ya existe');
  perform pg_temp.mala('03.43 identificador que no es UUID', sp, v_id, 2, format('{"op":"nueva","marca_id":"abc","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'identificador');
  perform pg_temp.mala('03.44 cambiar una marca que no es de este cuaderno', sp, v_id, 2, format('{"op":"cambia","marca_id":"%s","tipo":"referencia","geom":%s}', gen_random_uuid(), pg_temp.pt(-73.25, 10.46)), 'no existe en este cuaderno');
  perform pg_temp.mala('03.45 cambiarle el tipo a una marca', sp, v_id, 2, format('{"op":"cambia","marca_id":"%s","tipo":"postit","nota":"x","geom":%s}', m_ref, pg_temp.pt(-73.25, 10.46)), 'cambiar el tipo');
  perform pg_temp.mala('03.46 anular sin motivo', sp, v_id, 2, format('{"op":"anula","marca_id":"%s"}', m_ref), 'motivo');
  perform pg_temp.err('03.47 la misma marca dos veces en un guardado', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2, null, null, null, %L::jsonb)', sp, v_id,
    format('[{"op":"anula","marca_id":"%s","motivo":"ZTCUAD repetida"},{"op":"cambia","marca_id":"%s","tipo":"referencia","geom":%s}]', m_ref, m_ref, pg_temp.pt(-73.25, 10.46))), '22023', 'repetida');
  perform pg_temp.err('03.48 los cambios no son una lista', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2, null, null, null, ''{"op":"nueva"}''::jsonb)', sp, v_id), '22023', 'cambios');
  perform pg_temp.reg('03.49 ningún rechazo dejó una versión a medias: sigue en la 2 con 8 marcas',
    analisis.f_ultima_version(v_id) = 2 and (select count(*) from analisis.marcas where cuaderno_id = v_id) = 8 and (select count(*) from analisis.marca_versiones where cuaderno_id = v_id) = 8);

  -- cambiar, anular y leer versiones
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 2, 'ZTCUAD Cuaderno del POIR 2027', '', '{"zoom":15}', format($j$[
    {"op":"cambia","marca_id":"%s","tipo":"referencia","nota":"ZTCUAD movida","categoria":"observacion","estilo":{"color":"#0000FF"},"geom":%s},
    {"op":"anula","marca_id":"%s","motivo":"  ZTCUAD se puso por error  "},
    {"op":"cambia","marca_id":"%s","tipo":"zona","nota":"ZTCUAD la misma zona, otra nota","geom":%s}]$j$, m_ref, pg_temp.pt(-73.2600, 10.4700), m_post, m_zona, zona)::jsonb);
  perform pg_temp.reg('03.50 versión 3: título nuevo, descripción borrada con «», vista nueva; quedan 7 marcas vigentes',
    (j ->> 'version')::integer = 3 and jsonb_array_length(j -> 'marcas') = 7
    and (select titulo = 'ZTCUAD Cuaderno del POIR 2027' and descripcion is null and vista = '{"zoom":15}' from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 3));
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_ref::text;
  perform pg_temp.reg('03.51 la marca cambiada: estado nuevo en la versión 3, nacida en la 2',
    m ->> 'nota' = 'ZTCUAD movida' and (m ->> 'version')::integer = 3 and (m ->> 'creada_en_version')::integer = 2 and (m -> 'geom' -> 'coordinates' ->> 0)::numeric = -73.26);
  perform pg_temp.reg('03.52 nada se borra: la marca anulada sigue en la tabla, con su motivo recortado y su estado anterior',
    (select count(*) = 2 and bool_or(anulada and motivo = 'ZTCUAD se puso por error' and nota = 'ZTCUAD post-it' and version = 3) and bool_or(not anulada and version = 2)
       from analisis.marca_versiones where marca_id = m_post));
  perform pg_temp.reg('03.53 la zona que no se movió conserva su conteo sin volver a contar (sigue 1 consulta)',
    (select (x ->> 'conteo_predios')::integer = v_n and x ->> 'nota' = 'ZTCUAD la misma zona, otra nota' from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_zona::text)
    and (select count(*) from analisis.zona_consultas where solicitante = sp) = 1);
  perform pg_temp.mala('03.54 una marca anulada ya no se cambia ni se anula otra vez', sp, v_id, 3, format('{"op":"anula","marca_id":"%s","motivo":"ZTCUAD otra vez"}', m_post), 'ya está anulada');
  j := public.geoportal_analisis_cuaderno(sd, v_id, 2);
  perform pg_temp.reg('03.55 la versión 2 se sigue leyendo tal como era: 8 marcas, el post-it vivo, la referencia en su sitio y el título viejo',
    jsonb_array_length(j -> 'marcas') = 8 and j ->> 'titulo' = 'ZTCUAD Cuaderno del POIR' and (j ->> 'version')::integer = 2 and (j ->> 'ultima_version')::integer = 3
    and (select (x -> 'geom' -> 'coordinates' ->> 0)::numeric = -73.254 from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_ref::text)
    and not (j ->> 'puede_editar')::boolean);
  j := public.geoportal_analisis_cuaderno(sp, v_id);
  perform pg_temp.reg('03.56 el autor abre la última: puede editar; trae 3 versiones y 7 marcas',
    (j ->> 'puede_editar')::boolean and (j ->> 'es_mio')::boolean and jsonb_array_length(j -> 'versiones') = 3 and jsonb_array_length(j -> 'marcas') = 7 and (j ->> 'version')::integer = 3);
  perform pg_temp.reg('03.57 el autor en una versión vieja NO puede editar (se edita solo sobre la última)', not (public.geoportal_analisis_cuaderno(sp, v_id, 2) ->> 'puede_editar')::boolean);
  j := public.geoportal_analisis_cuaderno(adm, v_id);
  perform pg_temp.reg('03.58 el administrador y el otro supervisor lo leen, sin poder editarlo',
    not (j ->> 'puede_editar')::boolean and not (j ->> 'es_mio')::boolean and jsonb_array_length(j -> 'marcas') = 7
    and not (public.geoportal_analisis_cuaderno(sd, v_id) ->> 'puede_editar')::boolean);
  perform pg_temp.err('03.59 una versión que no existe → 404', format('select public.geoportal_analisis_cuaderno(%L, %L, 9)', sp, v_id), 'P0002');
  perform pg_temp.err('03.60 un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno(%L, %L)', sp, gen_random_uuid()), 'P0002');
  -- tope de marcas
  insert into analisis.parametros (clave, valor, motivo, autor) values ('marcas_por_cuaderno', 7, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.mala('03.61 con el tope en 7, la octava marca no entra', sp, v_id, 3, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no puede pasar de 7');
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 3, null, null, null, format('[{"op":"anula","marca_id":"%s","motivo":"ZTCUAD hace sitio"},{"op":"nueva","tipo":"referencia","geom":%s}]',
         m_circ, pg_temp.pt(-73.25, 10.46))::jsonb);
  perform pg_temp.reg('03.62 anular una y poner otra en el mismo guardado sí cabe (versión 4, 7 marcas; el servidor le pone identificador)',
    (j ->> 'version')::integer = 4 and jsonb_array_length(j -> 'marcas') = 7);
  insert into analisis.parametros (clave, valor, motivo, autor) values ('marcas_por_cuaderno', 500, 'ZTCUAD vuelve al valor', 'prueba');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('mano_vertices_max', 5, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.mala('03.63 un trazo que tras simplificarse pasa del tope de vértices', sp, v_id, 4,
    '{"op":"nueva","tipo":"mano","geom":{"type":"LineString","coordinates":[[-73.25,10.46],[-73.251,10.461],[-73.25,10.462],[-73.251,10.463],[-73.25,10.464],[-73.251,10.465],[-73.25,10.466]]}}', 'demasiado largo');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('mano_vertices_max', 500, 'ZTCUAD vuelve al valor', 'prueba');
  -- los CHECK de las tablas también lo impiden por debajo de las RPC
  perform pg_temp.err('03.64 CHECK: una marca fuera de Valledupar no entra ni por inserción directa',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom) values (%L, %L, 4, ''referencia'', st_setsrid(st_makepoint(-74.08, 4.6), 4326))', m_ref, v_id), '23514');
  perform pg_temp.err('03.65 CHECK: un punto con tipo zona',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom, conteo_predios, conteo_contratos) values (%L, %L, 4, ''zona'', st_setsrid(st_makepoint(-73.25, 10.46), 4326), 1, 1)', m_ref, v_id), '23514');
  perform pg_temp.err('03.66 CHECK: anulada sin motivo',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom, anulada) values (%L, %L, 4, ''referencia'', st_setsrid(st_makepoint(-73.25, 10.46), 4326), true)', m_ref, v_id), '23514');
  perform pg_temp.err('03.67 LLAVE: un problema con un subtipo que no está en el catálogo',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, subtipo, geom) values (%L, %L, 4, ''problema'', ''inventado'', st_setsrid(st_makepoint(-73.25, 10.46), 4326))', m_ref, v_id), '23503');
  perform pg_temp.err('03.68 LLAVE: una versión de marca en una versión de cuaderno que no existe',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom) values (%L, %L, 99, ''referencia'', st_setsrid(st_makepoint(-73.25, 10.46), 4326))', m_ref, v_id), '23503');
  perform pg_temp.err('03.69 CHECK: un módulo que no es Técnica', format('insert into analisis.cuadernos (modulo, autor) values (''comercial'', %L)', sp), '23514');

  -- ===================== 04. Archivar y reabrir =====================
  perform pg_temp.err('04.01 otro supervisor no archiva el cuaderno ajeno', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', sd, v_id), '42501');
  perform pg_temp.err('04.02 el administrador tampoco', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', adm, v_id), '42501');
  perform pg_temp.err('04.03 archivar sin motivo', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''  '')', sp, v_id), '22023', 'motivo');
  perform pg_temp.err('04.04 una acción que no existe', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''borrar'', ''ZTCUAD motivo'')', sp, v_id), '22023');
  perform pg_temp.err('04.05 reabrir lo que no está archivado → 409', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''reabrir'', ''ZTCUAD motivo'')', sp, v_id), '55000');
  j := public.geoportal_analisis_cuaderno_estado(sp, v_id, 'archivar', 'ZTCUAD ya se entregó el análisis');
  perform pg_temp.reg('04.06 el autor archiva con motivo', (j ->> 'archivado')::boolean and analisis.f_archivado(v_id));
  perform pg_temp.mala('04.07 un cuaderno archivado no se edita → 409', sp, v_id, 4, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'archivado', '55000');
  perform pg_temp.err('04.08 archivarlo dos veces → 409', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', sp, v_id), '55000');
  perform pg_temp.reg('04.09 sale de la lista normal y aparece en la de archivados; se sigue leyendo, sin edición',
    not exists (select 1 from jsonb_array_elements(public.geoportal_analisis_cuadernos(sd) -> 'cuadernos') x where x ->> 'id' = v_id::text)
    and exists (select 1 from jsonb_array_elements(public.geoportal_analisis_cuadernos(sd, true) -> 'cuadernos') x where x ->> 'id' = v_id::text and (x ->> 'archivado')::boolean and (x ->> 'marcas')::integer = 7)
    and not (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'puede_editar')::boolean and (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'archivado')::boolean);
  perform pg_temp.err('04.10 archivado: tampoco recibe capturas → 409',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '55000');
  j := public.geoportal_analisis_cuaderno_estado(sp, v_id, 'reabrir', 'ZTCUAD faltaba una zona');
  perform pg_temp.reg('04.11 el autor lo reabre y vuelve a poder editar; quedan los dos eventos con su motivo',
    not analisis.f_archivado(v_id) and (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'puede_editar')::boolean
    and jsonb_array_length(public.geoportal_analisis_cuaderno(sp, v_id) -> 'eventos') = 2);

  -- ===================== 05. Zona afectada =====================
  select count(*), count(distinct cod_usuario) filter (where btrim(coalesce(cod_usuario, '')) <> '') into v_n, v_n2
    from public.catastro_valledupar where st_intersects(geom, st_setsrid(st_geomfromgeojson(zona2), 4326));
  j := public.geoportal_analisis_zona(sd, zona2::jsonb);
  perform pg_temp.reg('05.01 la zona devuelve SOLO los dos números, iguales al catastro',
    (select array_agg(k order by k) from jsonb_object_keys(j) k) = array['contratos', 'predios'] and (j ->> 'predios')::integer = v_n and (j ->> 'contratos')::integer = v_n2, j::text);
  perform pg_temp.reg('05.02 los contratos nunca son más que los predios, y la respuesta no trae códigos ni direcciones', v_n2 <= v_n and j::text !~ '[A-Za-z]{3,}.*[0-9]{5,}');
  perform pg_temp.reg('05.03 una zona sin predios da cero y cero',
    public.geoportal_analisis_zona(sd, pg_temp.cuadro(-73.3400, 10.5400, 0.0010)::jsonb) = '{"predios":0,"contratos":0}'::jsonb);
  perform pg_temp.err('05.04 más de 25 km² → 400', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, pg_temp.cuadro(-73.30, 10.40, 0.09)), '22023', 'demasiado grande');
  perform pg_temp.err('05.05 fuera de Valledupar → 400', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, pg_temp.cuadro(-74.10, 4.60, 0.01)), '22023', 'fuera de Valledupar');
  perform pg_temp.err('05.06 una línea no es una zona → 400', format('select public.geoportal_analisis_zona(%L, ''{"type":"LineString","coordinates":[[-73.25,10.46],[-73.24,10.47]]}''::jsonb)', sd), '22023', 'polígono');
  perform pg_temp.err('05.07 sin geometría → 400', format('select public.geoportal_analisis_zona(%L, null)', sd), '22023', 'polígono');
  perform pg_temp.err('05.08 un multipolígono no es una zona → 400',
    format('select public.geoportal_analisis_zona(%L, ''{"type":"MultiPolygon","coordinates":[[[[-73.25,10.46],[-73.24,10.46],[-73.24,10.47],[-73.25,10.46]]]]}''::jsonb)', sd), '22023', 'polígono');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('zona_conteos_por_hora', 3, 'ZTCUAD prueba del tope', 'prueba');
  j := public.geoportal_analisis_zona(sd, zona2::jsonb);            -- la tercera del supervisor de distribución en esta hora
  perform pg_temp.err('05.09 con el tope en 3 por hora, la cuarta → 429', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, zona2), '54000', 'Demasiados conteos');
  perform pg_temp.reg('05.10 el tope es por persona: otro supervisor sigue contando', (public.geoportal_analisis_zona(adm, zona2::jsonb) ->> 'predios')::integer = v_n);
  v_id2 := (public.geoportal_analisis_cuaderno_crear(sd, 'ZTCUAD Cuaderno de distribución') ->> 'id')::uuid;
  perform pg_temp.mala('05.11 el tope también vale para las zonas que cuenta «guardar»', sd, v_id2, 1, format('{"op":"nueva","tipo":"zona","geom":%s}', zona2), 'Demasiados conteos', '54000');
  perform pg_temp.reg('05.12 las consultas rechazadas no cuentan ni quedan a medias: el supervisor de distribución tiene 3', (select count(*) from analisis.zona_consultas where solicitante = sd) = 3);
  insert into analisis.parametros (clave, valor, motivo, autor) values ('zona_conteos_por_hora', 120, 'ZTCUAD vuelve al valor', 'prueba');
  perform pg_temp.reg('05.13 el registro de consultas no guarda la geometría ni nada del predio',
    (select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_schema = 'analisis' and table_name = 'zona_consultas')
      = array['id', 'solicitante', 'area_km2', 'predios', 'contratos', 'creado_en']);

  -- ===================== 06. Capturas =====================
  perform pg_temp.err('06.01 otro supervisor no guarda capturas en un cuaderno ajeno',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sd, v_id, repeat('a', 64)), '42501');
  perform pg_temp.err('06.02 más de 1.600 px de lado', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 1601, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', '1600 px');
  perform pg_temp.err('06.03 más de 600 KB', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 1600, 900, 614401, %L)', sp, v_id, repeat('a', 64)), '22023', '600 KB');
  perform pg_temp.err('06.04 huella que no es sha256', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, ''abc'')', sp, v_id), '22023', 'huella');
  perform pg_temp.err('06.05 extensión al revés (oeste mayor que este)', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.25, 10.46, -73.26, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', 'extensión');
  perform pg_temp.err('06.06 sin título', format('select public.geoportal_analisis_captura_firmar(%L, %L, '' '', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', 'título');
  j := public.geoportal_analisis_captura_firmar(sp, v_id, '  ZTCUAD Vista del sector 5  ', -73.26, 10.46, -73.25, 10.47, 1600, 900, 300000, repeat('a', 64));
  v_cap := (j ->> 'captura_id')::uuid; v_ruta := j ->> 'ruta';
  perform pg_temp.reg('06.07 firmar: reserva la ruta <cuaderno>/<captura>.jpg', v_ruta = v_id::text || '/' || v_cap::text || '.jpg' and (select titulo = 'ZTCUAD Vista del sector 5' from analisis.capturas where id = v_cap));
  perform pg_temp.err('06.08 confirmar antes de subir → 409', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap), '55000', 'almacenamiento');
  perform pg_temp.err('06.09 una captura sin confirmar no se puede abrir → 404', format('select public.geoportal_analisis_captura_ruta(%L, %L)', sp, v_cap), 'P0002');
  perform pg_temp.reg('06.10 una captura sin confirmar no sale en el cuaderno', jsonb_array_length(public.geoportal_analisis_cuaderno(sp, v_id) -> 'capturas') = 0);
  insert into storage.objects (bucket_id, name, metadata) values ('analisis-capturas', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/png'));
  perform pg_temp.err('06.11 llegó un PNG → 400', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap), '22023', 'JPEG');
  j := public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD Otra vista', -73.26, 10.46, -73.25, 10.47, 800, 600, 200000, repeat('b', 64));
  v_cap2 := (j ->> 'captura_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) values ('analisis-capturas', j ->> 'ruta', jsonb_build_object('size', 250000, 'mimetype', 'image/jpeg'));
  perform pg_temp.err('06.12 llegó un archivo de otro tamaño que el anunciado → 400', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap2), '22023', 'no es la que se anunció');
  v_cap := (public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD Vista buena', -73.26, 10.46, -73.25, 10.47, 1600, 900, 300000, repeat('c', 64)) ->> 'captura_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) select 'analisis-capturas', ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg') from analisis.capturas where id = v_cap;
  perform pg_temp.err('06.13 otro supervisor no confirma la captura ajena', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sd, v_cap), '42501');
  j := public.geoportal_analisis_captura_confirmar(sp, v_cap);
  perform pg_temp.reg('06.14 confirmar: el archivo está, es JPEG y pesa lo anunciado',
    (j ->> 'confirmada')::boolean and (select bytes_reales = 300000 and autor = sp from analisis.capturas_confirmadas where captura_id = v_cap));
  perform pg_temp.reg('06.15 confirmar dos veces no duplica', (public.geoportal_analisis_captura_confirmar(sp, v_cap) ->> 'confirmada')::boolean
    and (select count(*) from analisis.capturas_confirmadas where captura_id = v_cap) = 1);
  j := public.geoportal_analisis_captura_ruta(sd, v_cap);
  perform pg_temp.reg('06.16 el otro supervisor y el administrador sí la abren (lectura)',
    j ->> 'ruta' = (select ruta from analisis.capturas where id = v_cap) and public.geoportal_analisis_captura_ruta(adm, v_cap) ->> 'titulo' = 'ZTCUAD Vista buena');
  j := public.geoportal_analisis_cuaderno(sd, v_id);
  perform pg_temp.reg('06.17 el cuaderno muestra solo la captura confirmada, con su título, extensión y tamaño; SIN la ruta del archivo',
    jsonb_array_length(j -> 'capturas') = 1 and j -> 'capturas' -> 0 ->> 'titulo' = 'ZTCUAD Vista buena' and (j -> 'capturas' -> 0 ->> 'bytes')::integer = 300000
    and j -> 'capturas' -> 0 -> 'extension' = '[-73.26, 10.46, -73.25, 10.47]'::jsonb and not (j -> 'capturas' -> 0) ? 'ruta' and j::text not like '%.jpg%');
  perform pg_temp.err('06.18 una captura que no existe → 404', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, gen_random_uuid()), 'P0002');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 3, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.err('06.19 con el tope en 3 (1 confirmada y 2 reservadas hace poco), la cuarta → 409',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('d', 64)), '55000', 'ya tiene sus 3 capturas');
  perform pg_temp.reg('06.20 el tope es por cuaderno: en otro cuaderno sí se puede',
    public.geoportal_analisis_captura_firmar(sd, v_id2, 'ZTCUAD captura de distribución', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, repeat('e', 64)) ? 'captura_id');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 20, 'ZTCUAD vuelve al valor', 'prueba');
  perform pg_temp.err('06.21 CHECK: una captura de 700 KB no entra ni por inserción directa',
    format('insert into analisis.capturas (id, cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor) values (%L, %L, %L, ''ZTCUAD x'', -73.26, 10.46, -73.25, 10.47, 800, 600, 700000, %L, %L)',
           v_cap2, v_id, v_id::text || '/' || v_cap2::text || '.jpg', repeat('a', 64), sp), '23514');
  perform pg_temp.err('06.22 CHECK: la ruta debe ser la del cuaderno y la captura',
    format('insert into analisis.capturas (cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor) values (%L, ''otra/cosa.jpg'', ''ZTCUAD x'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L, %L)',
           v_id, repeat('a', 64), sp), '23514');

  -- anular una captura (decisión de David, 26-nov): con motivo, sin borrar el archivo ni la fila; las anuladas no cuentan para el tope
  perform pg_temp.err('06.23 otro supervisor no anula la captura ajena', format('select public.geoportal_analisis_captura_anular(%L, %L, ''ZTCUAD motivo'')', sd, v_cap), '42501');
  perform pg_temp.err('06.24 el administrador tampoco', format('select public.geoportal_analisis_captura_anular(%L, %L, ''ZTCUAD motivo'')', adm, v_cap), '42501');
  perform pg_temp.err('06.25 anular sin motivo', format('select public.geoportal_analisis_captura_anular(%L, %L, ''  ab '')', sp, v_cap), '22023', 'motivo');
  perform pg_temp.err('06.26 una captura sin confirmar no se anula → 404', format('select public.geoportal_analisis_captura_anular(%L, %L, ''ZTCUAD motivo'')', sp, v_cap2), 'P0002');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 3, 'ZTCUAD prueba del tope con anuladas', 'prueba');
  perform pg_temp.err('06.27 antes de anular, el cuaderno está en su tope (3)',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('d', 64)), '55000', 'ya tiene sus 3 capturas');
  j := public.geoportal_analisis_captura_anular(sp, v_cap, '  ZTCUAD salió movida  ');
  perform pg_temp.reg('06.28 el autor anula con motivo: queda la fila de la anulación con el motivo recortado',
    (j ->> 'anulada')::boolean and (select motivo = 'ZTCUAD salió movida' and autor = sp from analisis.capturas_anuladas where captura_id = v_cap));
  perform pg_temp.reg('06.29 nada se borra: siguen la captura, su confirmación y el archivo en el bucket',
    exists (select 1 from analisis.capturas where id = v_cap) and exists (select 1 from analisis.capturas_confirmadas where captura_id = v_cap)
    and exists (select 1 from storage.objects o join analisis.capturas k on k.ruta = o.name where o.bucket_id = 'analisis-capturas' and k.id = v_cap));
  begin
    j := public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD captura tras anular', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, repeat('f', 64));
    perform pg_temp.reg('06.30 la anulada no cuenta para el tope: ahora sí entra otra', j ? 'captura_id');
  exception when others then
    perform pg_temp.reg('06.30 la anulada no cuenta para el tope: ahora sí entra otra', false, sqlerrm);
  end;
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 20, 'ZTCUAD vuelve al valor', 'prueba');
  perform pg_temp.reg('06.31 la anulada ya no sale en el cuaderno ni en el conteo de la lista',
    jsonb_array_length(public.geoportal_analisis_cuaderno(sd, v_id) -> 'capturas') = 0
    and (select (x ->> 'capturas')::integer from jsonb_array_elements(public.geoportal_analisis_cuadernos(sd) -> 'cuadernos') x where x ->> 'id' = v_id::text) = 0);
  perform pg_temp.err('06.32 una captura anulada ya no se abre → 404', format('select public.geoportal_analisis_captura_ruta(%L, %L)', sd, v_cap), 'P0002');
  perform pg_temp.err('06.33 anularla dos veces → 409', format('select public.geoportal_analisis_captura_anular(%L, %L, ''ZTCUAD otra vez'')', sp, v_cap), '55000', 'ya está anulada');
  perform pg_temp.err('06.34 CHECK: una anulación sin motivo no entra ni por inserción directa',
    format('insert into analisis.capturas_anuladas (captura_id, motivo, autor) values (%L, ''ab'', %L)', v_cap2, sp), '23514');
  -- una segunda captura buena, para que la exportación tenga qué mostrar
  v_cap := (public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD Vista definitiva', -73.26, 10.46, -73.25, 10.47, 1600, 900, 280000, repeat('9', 64)) ->> 'captura_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) select 'analisis-capturas', ruta, jsonb_build_object('size', 280000, 'mimetype', 'image/jpeg') from analisis.capturas where id = v_cap;
  perform public.geoportal_analisis_captura_confirmar(sp, v_cap);
  perform public.geoportal_analisis_cuaderno_estado(sp, v_id, 'archivar', 'ZTCUAD para probar la anulación');
  perform pg_temp.err('06.35 en un cuaderno archivado no se anulan capturas → 409', format('select public.geoportal_analisis_captura_anular(%L, %L, ''ZTCUAD motivo'')', sp, v_cap), '55000', 'archivado');
  perform public.geoportal_analisis_cuaderno_estado(sp, v_id, 'reabrir', 'ZTCUAD sigue la prueba');

  -- ===================== 07. Exportar =====================
  j := public.geoportal_analisis_cuaderno_exportar(sd, v_id);
  perform pg_temp.reg('07.01 exportar (lo lee también el otro supervisor): las 7 marcas vigentes numeradas, sin las anuladas, y solo la captura vigente (la anulada no sale)',
    jsonb_array_length(j -> 'marcas') = 7 and (select array_agg((x ->> 'n')::integer order by (x ->> 'n')::integer) from jsonb_array_elements(j -> 'marcas') x) = array[1, 2, 3, 4, 5, 6, 7]
    and not exists (select 1 from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' in ('postit', 'circulo'))
    and jsonb_array_length(j -> 'capturas') = 1 and j -> 'capturas' -> 0 ->> 'titulo' = 'ZTCUAD Vista definitiva' and j -> 'cuaderno' ->> 'titulo' = 'ZTCUAD Cuaderno del POIR 2027' and (j -> 'cuaderno' ->> 'version')::integer = 4);
  perform pg_temp.reg('07.02 cada fila trae su punto (lon, lat), el nombre del catálogo, el sector y, según la figura, longitud, área o conteos',
    (select bool_and(x ->> 'lon' is not null and x ->> 'lat' is not null) from jsonb_array_elements(j -> 'marcas') x)
    and (select x ->> 'nombre' = 'Válvula por revisar' and x ->> 'activo_codigo' = v_act from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'problema')
    and (select x ->> 'nombre' = 'Tanque' and x ->> 'sistema' = 'acueducto' from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'activo')
    and (select (x ->> 'longitud_m')::numeric between 100 and 200 and x ->> 'area_m2' is null from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'linea')
    and (select (x ->> 'area_m2')::numeric between 300000 and 600000 and (x ->> 'predios')::integer > 0 from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'zona'));
  perform pg_temp.reg('07.03 la exportación no trae la ruta de las capturas ni identificadores internos de las marcas',
    j::text not like '%.jpg%' and not exists (select 1 from jsonb_array_elements(j -> 'marcas') x where x ? 'id' or x ? 'geom'));
  perform pg_temp.err('07.04 exportar un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno_exportar(%L, %L)', sp, gen_random_uuid()), 'P0002');

  -- ===================== 08. Solo agregar, con datos en las 11 tablas =====================
  foreach t in array tablas loop
    execute format('select count(*) from analisis.%I', t) into v_n;
    perform pg_temp.reg('08.01 analisis.' || t || ' tiene filas para probar', v_n > 0, v_n::text);
    perform pg_temp.err('08.02 DELETE bloqueado en analisis.' || t, format('delete from analisis.%I where true', t), '42501', 'DELETE no permitido');
    select a.attname into q from pg_attribute a where a.attrelid = ('analisis.' || t)::regclass and a.attnum > 0 and not a.attisdropped and a.attidentity = '' order by a.attnum desc limit 1;
    perform pg_temp.err('08.03 UPDATE bloqueado en analisis.' || t, format('update analisis.%I set %I = %I where true', t, q, q), '42501', 'UPDATE no permitido');
  end loop;
  perform pg_temp.err('08.04 TRUNCATE de todas a la vez', 'truncate analisis.cuadernos, analisis.cuaderno_versiones, analisis.cuaderno_eventos, analisis.marcas, analisis.marca_versiones, '
    || 'analisis.capturas, analisis.capturas_confirmadas, analisis.capturas_anuladas, analisis.zona_consultas, analisis.catalogo, analisis.parametros', '42501', 'TRUNCATE no permitido');

  -- ===================== 09. Lo que el paquete NO toca =====================
  perform pg_temp.reg('09.01 la huella de redes es la de antes (foto tomada antes de aplicar, en esta misma transacción)',
    (select a.v = d.v and a.v is not null from _foto_antes a join pg_temp.foto() d using (k) where k = 'huella_redes'), (select v from _foto_antes where k = 'huella_redes'));
  perform pg_temp.reg('09.02 la huella de técnica es la de antes',
    (select a.v = d.v and a.v is not null from _foto_antes a join pg_temp.foto() d using (k) where k = 'huella_tecnica'), (select v from _foto_antes where k = 'huella_tecnica'));
  perform pg_temp.reg('09.03 redes y técnica: los mismos objetos, columnas y disparadores; public, las mismas funciones más las 12 RPC',
    (select bool_and(a.v = d.v) from _foto_antes a join pg_temp.foto() d using (k) where k in ('objetos_redes_tecnica', 'columnas_redes_tecnica', 'disparadores_redes_tecnica', 'funciones_public')),
    (select string_agg(k || ' ' || a.v || '→' || d.v, ' · ') from _foto_antes a join pg_temp.foto() d using (k) where a.v <> d.v));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE ANÁLISIS · CUADERNOS (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total,
    case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
