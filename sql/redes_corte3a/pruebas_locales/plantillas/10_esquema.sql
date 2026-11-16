-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 10 — GUARDIA Y TABLAS DE INTERVENCIONES (formulario «mantenimiento», en pantalla «Registrar intervención»)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- Fuente: 01_modelo_propuesto.md §C, 02 fila 3, la maqueta Intervencion.dc.html y las §4, §6, §17 y las respuestas de David al Corte 2 en la bitácora.
-- · Presupone el Corte 2 aplicado (y por lo tanto el 1a): lo comprueba con la huella md5 del conjunto de funciones de redes.
-- · No toca ningún objeto vivo de otros esquemas. Del Corte 2 REEMPLAZA (create or replace, mismas columnas y firmas):
--     · la vista redes.v_dano: el activo vigente del daño puede venir de «asociar activo» (bandeja de no identificados);
--     · la vista redes.v_epicrisis: le suma las intervenciones (la del activo principal y la de cada «también intervenido»);
--     · las RPC geoportal_redes_preparar_dano y geoportal_redes_crear_dano: el supervisor o el administrador pueden registrar SIN fotos,
--       con el motivo, y el daño queda «sin evidencia fotográfica» (respuesta 2 de David al Corte 2). El operador sigue con al menos una.
--   La reversa deja las cuatro con su texto exacto del Corte 2.
-- · Usa el bucket privado redes-evidencias del Corte 2 (JPEG y PDF, 5 MB, sin políticas): no se crea otro.
-- · Todo objeto nuevo: revoke all a public, anon, authenticated y service_role (40); RLS activa sin políticas.
-- =====================================================================
do $$
begin
  if to_regclass('redes.danos') is null then raise exception 'Falta el Corte 2 (redes.danos): aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_2}}' then
    raise exception 'Las funciones de redes no son las del Corte 2 (o el Corte 3a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> '{{MD5_V_DANO_2}}' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_V_EPICRISIS_2}}' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del Corte 2: deténgase y avise';
  end if;
  if to_regclass('redes.intervenciones') is not null then raise exception 'redes.intervenciones ya existe: el Corte 3a parece aplicado'; end if;
  if not exists (select 1 from storage.buckets where id = 'redes-evidencias' and not public and 'application/pdf' = any (allowed_mime_types) and 'image/jpeg' = any (allowed_mime_types)) then
    raise exception 'Falta el bucket privado redes-evidencias (JPEG y PDF) del Corte 2';
  end if;
  if not exists (select 1 from redes.consecutivos where prefijo = 'ITV') then raise exception 'Falta el consecutivo ITV del Corte 1a'; end if;
  if to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null then raise exception 'Falta tecnica.f_autorizar_captura(text,text)'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CATÁLOGO: tipos de intervención (los cinco de la maqueta) y unidades de los materiales
-- ---------------------------------------------------------------------
create table redes.tipos_intervencion (
  codigo       text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  nombre       text not null check (length(btrim(nombre)) between 2 and 80),
  admite_dano  boolean not null default false,          -- puede nacer de un daño o falla (correctivo, reparación, reposición)
  es_inversion boolean not null default false,          -- pide «activo nuevo» o «mejora de un activo existente»
  activo       boolean not null default true,
  orden        integer not null default 0,
  check (not (admite_dano and es_inversion))
);
create table redes.unidades_material (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{0,19}$'), nombre text not null check (length(btrim(nombre)) between 1 and 40),
  activo boolean not null default true, orden integer not null default 0);

-- ---------------------------------------------------------------------
-- 2. INTERVENCIONES. Un hecho sobre el activo (va a su epicrisis). Flujo A (D-6): se registra después de hecha y queda «cerrada».
--    Solo inserción: el estado, el activo asociado y los recursos completos salen de los eventos y de las versiones de las fuentes.
-- ---------------------------------------------------------------------
create table redes.intervencion_preparaciones (    -- reserva del id y de las rutas de los archivos antes de subir: el reenvío no duplica
  intervencion_id uuid primary key,
  autor           text not null,
  fotos           smallint not null check (fotos between 0 and 20),
  documentos      smallint not null check (documentos between 0 and 10),
  creado_en       timestamptz not null default clock_timestamp()
);

create table redes.intervenciones (
  id                   uuid primary key,
  codigo               text not null unique check (codigo ~ '^ITV-[0-9]{6}$'),
  nace_de              text not null check (nace_de in ('programada', 'dano')),     -- «Programada o mejora» o «Daño o falla»
  dano_id              uuid references redes.danos (id),
  tipo_codigo          text not null references redes.tipos_intervencion (codigo),
  inversion_modo       text check (inversion_modo in ('nuevo', 'mejora')),
  sistema              text not null references redes.sistemas (codigo),
  activo_id            bigint references redes.activos (id),                        -- nulo = «activo no identificado» (bandeja del supervisor)
  activo_creado        boolean not null default false,                              -- la inversión creó este activo (queda «por verificar»)
  no_ident_que_es      text check (no_ident_que_es is null or length(btrim(no_ident_que_es)) between 3 and 120),
  lat                  numeric(9, 6) not null check (lat between -90 and 90),
  lon                  numeric(9, 6) not null check (lon between -180 and 180),
  geom                 geometry(Point, 4326) generated always as (ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326)) stored,
  ubicacion_origen     text not null check (ubicacion_origen in ('gps', 'mapa', 'activo')),
  precision_m          numeric check (precision_m is null or precision_m >= 0),
  fuera_de_zona        boolean not null default false,
  t_inicio             timestamptz not null,                                        -- inicio del trabajo
  t_fin                timestamptz not null,                                        -- fin del trabajo
  inicio_en            timestamptz,                                                 -- apertura del formulario (celular), contrato de 12 h
  inicio_origen        text check (inicio_origen in ('dispositivo', 'servidor')),
  descripcion          text not null check (length(btrim(descripcion)) between 10 and 2000),
  ejecutor             text not null check (ejecutor in ('emdupar', 'contratista')),
  contratista_id       bigint references redes.contratistas (id),
  contratista_nombre   text check (contratista_nombre is null or length(btrim(contratista_nombre)) between 2 and 120),   -- si aún no está en el catálogo
  contrato_orden       text check (contrato_orden is null or length(btrim(contrato_orden)) between 1 and 60),
  companeros           text check (companeros is null or length(btrim(companeros)) between 2 and 200),
  sin_evidencia_motivo text check (sin_evidencia_motivo is null or length(btrim(sin_evidencia_motivo)) between 10 and 300),
  autor                text not null,
  registrado_en        timestamptz not null default clock_timestamp(),
  check ((nace_de = 'dano') = (dano_id is not null)),
  check ((tipo_codigo = 'inversion') = (inversion_modo is not null)),
  check (activo_id is not null or no_ident_que_es is not null),
  check (not activo_creado or (inversion_modo = 'nuevo' and activo_id is not null)),
  check (t_fin >= t_inicio),
  check ((inicio_en is null) = (inicio_origen is null)),
  check (ejecutor = 'contratista' or (contratista_id is null and contratista_nombre is null)),
  check (ejecutor = 'emdupar' or contratista_id is not null or contratista_nombre is not null)
);
create index ix_itv_geom on redes.intervenciones using gist (geom);
create index ix_itv_activo on redes.intervenciones (activo_id, t_fin desc) where activo_id is not null;
create index ix_itv_dano on redes.intervenciones (dano_id) where dano_id is not null;
create index ix_itv_registrado on redes.intervenciones (registrado_en desc);
create index ix_itv_autor on redes.intervenciones (autor, registrado_en desc);
comment on table redes.intervenciones is 'Intervenciones (formulario mantenimiento). Hecho sobre el activo: va a su epicrisis. Solo inserción; el estado, el activo asociado y los recursos completos salen de los eventos y de las versiones de las fuentes.';

-- Activos también intervenidos (D-9): salen en la epicrisis de cada uno.
create table redes.intervencion_activos (
  intervencion_id uuid not null references redes.intervenciones (id),
  activo_id       bigint not null references redes.activos (id),
  n               smallint not null check (n between 1 and 30),
  primary key (intervencion_id, activo_id),
  unique (intervencion_id, n)
);
create index ix_itva_activo on redes.intervencion_activos (activo_id);

create table redes.intervencion_materiales (
  intervencion_id uuid not null references redes.intervenciones (id),
  n               smallint not null check (n between 1 and 50),
  material        text not null check (length(btrim(material)) between 2 and 80),
  cantidad        numeric not null check (cantidad > 0 and cantidad < 1000000),
  unidad          text not null references redes.unidades_material (codigo),
  primary key (intervencion_id, n)
);

-- Fuentes de los recursos (D-8). Por VERSIONES: la 1 es la del formulario; el supervisor completa el valor, el porcentaje y el soporte con una
-- versión nueva (completar_recursos). La vigente es la última versión. El operario marca solo quién aporta: su versión no trae valores.
create table redes.intervencion_fuentes (
  id               bigint generated always as identity primary key,
  intervencion_id  uuid not null references redes.intervenciones (id),
  version          integer not null check (version >= 1),
  n                smallint not null check (n between 1 and 10),
  aportante_codigo text not null references redes.entidades_aportantes (codigo),
  entidad          text check (entidad is null or length(btrim(entidad)) between 2 and 120),     -- «Otro»: cuál; o el nombre exacto del convenio
  valor            numeric(16, 2) check (valor is null or valor >= 0),
  porcentaje       numeric(5, 2) check (porcentaje is null or porcentaje between 0 and 100),
  soporte          text check (soporte is null or length(btrim(soporte)) between 2 and 200),     -- convenio, resolución, contrato…
  fuente           text not null check (fuente in ('formulario', 'supervisor')),
  autor            text not null,
  creado_en        timestamptz not null default clock_timestamp(),
  unique (intervencion_id, version, n)
);
create index ix_itvf on redes.intervencion_fuentes (intervencion_id, version desc);

-- Fotos de antes, durante y después (JPEG) y documentos (PDF: orden, acta, factura), con el tamaño y el tipo leídos de Storage.
create table redes.intervencion_archivos (
  intervencion_id uuid not null references redes.intervenciones (id),
  n               smallint not null check (n between 1 and 30),
  clase           text not null check (clase in ('antes', 'durante', 'despues', 'documento')),
  ruta_storage    text not null unique check (ruta_storage ~ '^intervenciones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9]{1,2}\.(jpg|pdf)$'),
  bytes           integer not null check (bytes > 0),
  mime            text not null check (mime in ('image/jpeg', 'application/pdf')),
  creado_en       timestamptz not null default clock_timestamp(),
  primary key (intervencion_id, n),
  check ((clase = 'documento') = (mime = 'application/pdf')),
  check ((mime = 'application/pdf') = (ruta_storage like '%.pdf'))
);

create table redes.intervencion_eventos (
  id              bigint generated always as identity primary key,
  intervencion_id uuid not null references redes.intervenciones (id),
  tipo            text not null check (tipo in ('programada', 'en_ejecucion', 'cerrada', 'anulada', 'ocultar', 'reincluir', 'asociar_activo', 'crear_activo',
                                                'completar_recursos', 'nota')),
  activo_id       bigint references redes.activos (id),
  motivo          text check (motivo is null or length(btrim(motivo)) between 10 and 1000),
  autor           text not null,
  creado_en       timestamptz not null default clock_timestamp(),
  check (tipo in ('programada', 'en_ejecucion', 'cerrada', 'completar_recursos') or motivo is not null),
  check (tipo not in ('asociar_activo', 'crear_activo') or activo_id is not null)
);
create index ix_itve on redes.intervencion_eventos (intervencion_id, id desc);

-- Coherencia: el tipo admite nacer de un daño; el activo y el daño son del mismo sistema; los también intervenidos, del mismo sistema y distintos del principal.
create function redes.f_intervencion_coherente() returns trigger language plpgsql set search_path to 'redes', 'pg_temp' as $f$
declare t redes.tipos_intervencion%rowtype; v_sis text;
begin
  select * into t from redes.tipos_intervencion where codigo = new.tipo_codigo;
  if new.nace_de = 'dano' and not t.admite_dano then raise exception 'El tipo % no nace de un daño', new.tipo_codigo using errcode = '23514'; end if;
  if (new.inversion_modo is not null) <> t.es_inversion then raise exception 'El modo de inversión no corresponde al tipo %', new.tipo_codigo using errcode = '23514'; end if;
  if new.activo_id is not null then
    select tp.sistema into v_sis from redes.activos a join redes.tipos_activo tp on tp.prefijo = a.prefijo where a.id = new.activo_id;
    if v_sis is distinct from new.sistema then raise exception 'El activo no es del sistema %', new.sistema using errcode = '23514'; end if;
  end if;
  if new.dano_id is not null and (select sistema from redes.danos where id = new.dano_id) is distinct from new.sistema then
    raise exception 'El daño no es del sistema %', new.sistema using errcode = '23514';
  end if;
  return new;
end $f$;
create trigger t_intervencion_coherente before insert on redes.intervenciones for each row execute function redes.f_intervencion_coherente();

create function redes.f_intervencion_activo_coherente() returns trigger language plpgsql set search_path to 'redes', 'pg_temp' as $f$
declare i redes.intervenciones%rowtype;
begin
  select * into i from redes.intervenciones where id = new.intervencion_id;
  if new.activo_id = i.activo_id then raise exception 'El activo principal no va en «también intervenidos»' using errcode = '23514'; end if;
  if (select tp.sistema from redes.activos a join redes.tipos_activo tp on tp.prefijo = a.prefijo where a.id = new.activo_id) is distinct from i.sistema then
    raise exception 'Un activo también intervenido no es del sistema %', i.sistema using errcode = '23514';
  end if;
  return new;
end $f$;
create trigger t_intervencion_activo_coherente before insert on redes.intervencion_activos for each row execute function redes.f_intervencion_activo_coherente();

-- ---------------------------------------------------------------------
-- 3. REGLAS: hechos de solo inserción; catálogos sin borrar ni vaciar y con código inmutable
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['intervencion_preparaciones', 'intervenciones', 'intervencion_activos', 'intervencion_materiales', 'intervencion_fuentes',
                           'intervencion_archivos', 'intervencion_eventos'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
  foreach t in array array['tipos_intervencion', 'unidades_material'] loop
    execute format('create trigger t_no_borrar before delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_no_vaciar before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_codigo_inmutable before update on redes.%I for each row execute function redes.f_codigo_inmutable(''codigo'')', t);
  end loop;
end $$;
