-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 10 — GUARDIA, TABLAS DE DAÑOS Y FALLAS, REPORTES DEL BOT Y BUCKET DE EVIDENCIAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- Fuente: 01_modelo_propuesto.md §B y §B.1 (N-14), §I (minimapa), 02 fila 2, la maqueta Dano.dc.html y las §3, §6, §17 y §19 de la bitácora.
-- · Presupone el Corte 1a aplicado (esquema redes) y lo comprueba con la huella md5 de sus funciones.
-- · No toca ningún objeto vivo de otros esquemas. Del 1a solo REEMPLAZA la vista redes.v_epicrisis (le suma daños y fallas;
--   mismas columnas). La reversa la deja con su texto del 1a.
-- · Crea el bucket PRIVADO redes-evidencias (JPEG y PDF), sin políticas en storage.objects: solo la Edge firma URLs con la clave de servicio.
-- · Todo objeto nuevo: revoke all a public, anon, authenticated y service_role (40); RLS activa sin políticas.
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'redes') then raise exception 'Falta el esquema redes: aplique antes el Corte 1a'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_1A}}' then
    raise exception 'Las funciones de redes no son las del Corte 1a (o el Corte 2 ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('redes.danos') is not null then raise exception 'redes.danos ya existe: el Corte 2 parece aplicado'; end if;
  if to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null or to_regprocedure('tecnica.f_max_horas_inicio()') is null then
    raise exception 'Faltan tecnica.f_autorizar_captura(text,text) o tecnica.f_max_horas_inicio()';
  end if;
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then raise exception 'Falta Storage (storage.buckets y storage.objects)'; end if;
  if exists (select 1 from storage.buckets where id = 'redes-evidencias') then raise exception 'El bucket redes-evidencias ya existe: revise antes de seguir'; end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and (qual ilike '%redes-evidencias%' or with_check ilike '%redes-evidencias%')) then
    raise exception 'Hay políticas de storage.objects que mencionan redes-evidencias: el bucket debe quedar sin políticas';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CATÁLOGOS DEL DAÑO
-- ---------------------------------------------------------------------
create table redes.tipos_dano (
  codigo    text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  clase     text not null check (clase in ('dano', 'falla')),
  nombre    text not null check (length(btrim(nombre)) between 2 and 80),
  sistemas  text[] not null default array['acueducto', 'alcantarillado'] check (cardinality(sistemas) >= 1 and sistemas <@ array['acueducto', 'alcantarillado', 'tecnologia']),
  pide_rotura boolean not null default false,          -- muestra «tipo de rotura, largo y presión» (fugas y roturas)
  activo    boolean not null default true,
  orden     integer not null default 0
);
create table redes.tipos_rotura (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'), nombre text not null check (length(btrim(nombre)) between 2 and 60),
  activo boolean not null default true, orden integer not null default 0);
create table redes.causas (                             -- causas PROPIAS (desgaste, sobrepresión…)
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'), nombre text not null check (length(btrim(nombre)) between 2 and 80),
  activo boolean not null default true, orden integer not null default 0);
create table redes.tipos_tercero (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'), nombre text not null check (length(btrim(nombre)) between 2 and 80),
  activo boolean not null default true, orden integer not null default 0);
create table redes.marcas_riesgo (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'), nombre text not null check (length(btrim(nombre)) between 2 and 80),
  activo boolean not null default true, orden integer not null default 0);

-- Tabla de caudales de fuga (D-16). QUEDA VACÍA hasta que Técnica la entregue: sin fila, el daño muestra «sin tabla» y no se calcula pérdida.
create table redes.caudales_fuga (
  id              bigint generated always as identity primary key,
  diametro_min_mm numeric not null check (diametro_min_mm >= 0),
  diametro_max_mm numeric not null,
  tipo_rotura     text not null references redes.tipos_rotura (codigo),
  presion_min_mca numeric,                               -- nulos = cualquier presión
  presion_max_mca numeric,
  caudal_lps      numeric not null check (caudal_lps > 0),
  fuente          text not null check (length(btrim(fuente)) between 3 and 200),
  vigente_desde   date not null default current_date,
  autor           text not null,
  creado_en       timestamptz not null default clock_timestamp(),
  check (diametro_max_mm >= diametro_min_mm),
  check (presion_min_mca is null or presion_max_mca is null or presion_max_mca >= presion_min_mca)
);

-- ---------------------------------------------------------------------
-- 2. REPORTES DEL BOT (N-14, §19). Vacíos hasta que se conecte el bot. SIN nombre ni teléfono de quien reporta: se quedan en el Dell.
-- ---------------------------------------------------------------------
create table redes.reportes_externos (
  id            uuid primary key default gen_random_uuid(),
  radicado      text not null check (radicado ~ '^[A-Za-z0-9][A-Za-z0-9_-]{2,39}$'),
  canal         text not null check (canal in ('telegram', 'whatsapp')),
  origen        text not null default 'bot' check (origen = 'bot'),
  tipo_bot      text not null check (length(btrim(tipo_bot)) between 2 and 60),          -- el tipo del menú del bot, tal cual
  lat           numeric(9, 6) check (lat between -90 and 90),
  lon           numeric(9, 6) check (lon between -180 and 180),
  geom          geometry(Point, 4326) generated always as (case when lat is not null and lon is not null then ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326) end) stored,
  direccion     text check (direccion is null or length(direccion) <= 200),
  descripcion   text check (descripcion is null or length(descripcion) <= 1000),
  recibido_en   timestamptz not null,                                                     -- cuándo lo recibió el bot
  registrado_en timestamptz not null default clock_timestamp(),
  unique (canal, radicado),
  check ((lat is null) = (lon is null)),
  check (lat is not null or direccion is not null)
);
create index ix_rext_geom on redes.reportes_externos using gist (geom);
create table redes.reporte_externo_fotos (
  reporte_id   uuid not null references redes.reportes_externos (id),
  n            smallint not null check (n between 1 and 10),
  ruta_storage text not null unique check (ruta_storage ~ '^bot/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9]{1,2}\.jpg$'),
  bytes        integer not null check (bytes > 0),
  mime         text not null check (mime = 'image/jpeg'),
  creado_en    timestamptz not null default clock_timestamp(),
  primary key (reporte_id, n)
);

-- ---------------------------------------------------------------------
-- 3. DAÑOS Y FALLAS (formulario danos_fallas). Un daño es un EVENTO sobre el activo: va a su epicrisis. Solo inserción.
-- ---------------------------------------------------------------------
create table redes.dano_preparaciones (            -- reserva del id (y de las rutas de las fotos) antes de subir: el reenvío no duplica
  dano_id   uuid primary key,
  autor     text not null,
  fotos     smallint not null check (fotos between 0 and 10),
  creado_en timestamptz not null default clock_timestamp()
);

create table redes.danos (
  id                    uuid primary key,
  codigo                text not null unique check (codigo ~ '^DAN-[0-9]{6}$'),
  clase                 text not null check (clase in ('dano', 'falla')),
  tipo_codigo           text not null references redes.tipos_dano (codigo),
  sistema               text not null references redes.sistemas (codigo),
  activo_id             bigint references redes.activos (id),                -- nulo = «activo no identificado» (va a la bandeja del supervisor)
  no_ident_que_es       text check (no_ident_que_es is null or length(btrim(no_ident_que_es)) between 3 and 120),
  lat                   numeric(9, 6) not null check (lat between -90 and 90),
  lon                   numeric(9, 6) not null check (lon between -180 and 180),
  geom                  geometry(Point, 4326) generated always as (ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326)) stored,
  ubicacion_origen      text not null check (ubicacion_origen in ('gps', 'mapa', 'activo', 'bot')),
  precision_m           numeric check (precision_m is null or precision_m >= 0),
  fuera_de_zona         boolean not null default false,                       -- marca, nunca rechazo
  t_inicio_dano         timestamptz,                                          -- opcional («si se sabe»)
  t_detectado           timestamptz not null,
  inicio_en             timestamptz,                                          -- hora de apertura del formulario (celular), contrato de 12 h
  inicio_origen         text check (inicio_origen in ('dispositivo', 'servidor')),
  tipo_rotura           text references redes.tipos_rotura (codigo),
  largo_afectado_m      numeric check (largo_afectado_m is null or largo_afectado_m between 0 and 10000),
  presion_mca           numeric check (presion_mca is null or presion_mca between 0 and 300),
  usuarios_sin_servicio integer check (usuarios_sin_servicio is null or usuarios_sin_servicio between 0 and 1000000),
  usuarios_propuesta    integer,                                              -- lo propondrá la topología (Corte 9)
  sector_texto          text check (sector_texto is null or length(btrim(sector_texto)) between 2 and 80),
  riesgo                text not null check (riesgo in ('bajo', 'medio', 'alto')),
  marcas                text[] not null default '{}',
  causa_clase           text not null check (causa_clase in ('propia', 'terceros', 'desconocida')),
  causa_codigo          text references redes.causas (codigo),
  tercero_tipo          text references redes.tipos_tercero (codigo),
  descripcion           text check (descripcion is null or length(descripcion) <= 1000),
  origen                text not null default 'formulario' check (origen in ('formulario', 'bot')),
  reporte_externo_id    uuid unique references redes.reportes_externos (id),
  autor                 text not null,
  registrado_en         timestamptz not null default clock_timestamp(),
  check (activo_id is not null or no_ident_que_es is not null),
  check ((inicio_en is null) = (inicio_origen is null)),
  check (causa_clase = 'propia' or causa_codigo is null),
  check (causa_clase = 'terceros' or tercero_tipo is null),
  check (t_inicio_dano is null or t_inicio_dano <= t_detectado),
  check ((origen = 'bot') = (reporte_externo_id is not null))
);
create index ix_danos_geom on redes.danos using gist (geom);
create index ix_danos_activo on redes.danos (activo_id, registrado_en desc) where activo_id is not null;
create index ix_danos_registrado on redes.danos (registrado_en desc);
create index ix_danos_autor on redes.danos (autor, registrado_en desc);
comment on table redes.danos is 'Daños y fallas (solo Técnica). Evento sobre el activo: va a su epicrisis. Solo inserción; el estado y los tiempos de reparación salen de dano_tiempos y dano_eventos.';

-- El nombre o la placa del tercero que causó el daño es un DATO PERSONAL (D-26, Ley 1581): tabla aparte, solo la lee el supervisor con lectura auditada (Corte 4).
create table redes.dano_datos_sensibles (
  dano_id        uuid primary key references redes.danos (id),
  tercero_nombre text not null check (length(btrim(tercero_nombre)) between 2 and 120),
  creado_en      timestamptz not null default clock_timestamp()
);

-- Tiempos de la reparación: pueden llegar después del reporte (eventos; lo vigente es lo último no nulo de cada uno).
create table redes.dano_tiempos (
  id                  bigint generated always as identity primary key,
  dano_id             uuid not null references redes.danos (id),
  t_inicio_reparacion timestamptz,
  t_restablecido      timestamptz,
  fuente              text not null check (fuente in ('formulario', 'intervencion', 'supervisor')),
  autor               text not null,
  creado_en           timestamptz not null default clock_timestamp(),
  check (t_inicio_reparacion is not null or t_restablecido is not null),
  check (t_inicio_reparacion is null or t_restablecido is null or t_restablecido >= t_inicio_reparacion)
);
create index ix_dt_dano on redes.dano_tiempos (dano_id, id desc);

create table redes.dano_eventos (
  id              bigint generated always as identity primary key,
  dano_id         uuid not null references redes.danos (id),
  tipo            text not null check (tipo in ('en_atencion', 'atendido', 'reabrir', 'ocultar', 'reincluir', 'asociar_activo', 'nota')),
  intervencion_id uuid,
  activo_id       bigint references redes.activos (id),
  motivo          text not null check (length(btrim(motivo)) between 10 and 1000),
  autor           text not null,
  creado_en       timestamptz not null default clock_timestamp(),
  check (tipo <> 'asociar_activo' or activo_id is not null)
);
create index ix_de_dano on redes.dano_eventos (dano_id, id desc);

create table redes.dano_fotos (
  dano_id      uuid not null references redes.danos (id),
  n            smallint not null check (n between 1 and 10),
  momento      text not null check (momento in ('dano', 'entorno', 'reparado')),
  ruta_storage text not null unique check (ruta_storage ~ '^danos/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9]{1,2}\.jpg$'),
  bytes        integer not null check (bytes > 0),
  mime         text not null check (mime = 'image/jpeg'),
  creado_en    timestamptz not null default clock_timestamp(),
  primary key (dano_id, n)
);

create table redes.reporte_externo_eventos (
  id         bigint generated always as identity primary key,
  reporte_id uuid not null references redes.reportes_externos (id),
  tipo       text not null check (tipo in ('recibido', 'en_atencion', 'atendido', 'descartado', 'convertido')),
  dano_id    uuid references redes.danos (id),
  motivo     text check (motivo is null or length(btrim(motivo)) between 10 and 1000),
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp(),
  check ((tipo = 'convertido') = (dano_id is not null)),
  check (tipo <> 'descartado' or motivo is not null)
);
create index ix_ree_reporte on redes.reporte_externo_eventos (reporte_id, id desc);

-- Coherencia del daño: el tipo es de la clase y del sistema; el activo es vigente y del mismo sistema; las marcas existen.
create function redes.f_dano_coherente() returns trigger language plpgsql set search_path to 'redes', 'pg_temp' as $f$
declare t redes.tipos_dano%rowtype; v_sis text;
begin
  select * into t from redes.tipos_dano where codigo = new.tipo_codigo;
  if t.clase <> new.clase then raise exception 'El tipo % no es de la clase %', new.tipo_codigo, new.clase using errcode = '23514'; end if;
  if not (new.sistema = any (t.sistemas)) then raise exception 'El tipo % no aplica al sistema %', new.tipo_codigo, new.sistema using errcode = '23514'; end if;
  if new.activo_id is not null then
    select tp.sistema into v_sis from redes.activos a join redes.tipos_activo tp on tp.prefijo = a.prefijo where a.id = new.activo_id;
    if v_sis is distinct from new.sistema then raise exception 'El activo no es del sistema %', new.sistema using errcode = '23514'; end if;
  end if;
  if exists (select 1 from unnest(new.marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m)) then
    raise exception 'Hay una marca de riesgo que no existe' using errcode = '23514';
  end if;
  return new;
end $f$;
create trigger t_dano_coherente before insert on redes.danos for each row execute function redes.f_dano_coherente();

-- ---------------------------------------------------------------------
-- 4. REGLAS: hechos de solo inserción; catálogos sin borrar ni vaciar y con código inmutable
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['danos', 'dano_datos_sensibles', 'dano_tiempos', 'dano_eventos', 'dano_fotos', 'dano_preparaciones',
                           'reportes_externos', 'reporte_externo_fotos', 'reporte_externo_eventos', 'caudales_fuga'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
  foreach t in array array['tipos_dano', 'tipos_rotura', 'causas', 'tipos_tercero', 'marcas_riesgo'] loop
    execute format('create trigger t_no_borrar before delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_no_vaciar before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_codigo_inmutable before update on redes.%I for each row execute function redes.f_codigo_inmutable(''codigo'')', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. BUCKET PRIVADO redes-evidencias: JPEG (fotos del daño y, desde el Corte 3, de la intervención) y PDF (soportes, Corte 3/4).
--    Tope duro de 5 MB por archivo (por los PDF); el tope de las fotos (1,5 MB) es el parámetro max_bytes_foto_dano y lo verifica crear_dano.
--    SIN políticas sobre storage.objects: solo la clave de servicio de la Edge firma URLs de subida (corta vigencia) y de lectura (60 s).
--    Si el editor SQL rechazara este INSERT, crear el bucket con los mismos valores desde el panel (Storage → New bucket).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('redes-evidencias', 'redes-evidencias', false, 5242880, array['image/jpeg', 'application/pdf']);
